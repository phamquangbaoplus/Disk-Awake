import Foundation
import Observation

private struct JellyfinSession: Decodable {
    let userName: String?
    let nowPlayingItem: NowPlayingItem?

    struct NowPlayingItem: Decodable {}

    enum CodingKeys: String, CodingKey {
        case userName = "UserName"
        case nowPlayingItem = "NowPlayingItem"
    }
}

/// Shared Jellyfin state for every feature that reacts to server activity.
/// This is the only type that talks to the Jellyfin HTTP API.
@MainActor
@Observable
final class JellyfinActivityMonitor {
    enum Consumer: Hashable {
        case macAwake
        case externalDrives
    }

    struct PowerState: Sendable {
        let graceRemaining: TimeInterval?
        let lastCheckSucceeded: Bool
    }

    static let pollInterval: TimeInterval = 15
    static let graceInterval: TimeInterval = 5 * 60

    private(set) var status = "Off"
    private(set) var keepAwakeUntil: Date?
    private(set) var connectedSessionCount = 0
    private(set) var playingSessionCount = 0
    private(set) var isChecking = false
    private(set) var lastCheckSucceeded = false
    @ObservationIgnored private(set) var apiKey = UserDefaults.standard.string(
        forKey: "jellyfinAPIKey"
    ) ?? ""
    @ObservationIgnored var stateChanged: (() -> Void)?
    @ObservationIgnored private var consumers: Set<Consumer> = []
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    var shouldKeepAwake: Bool {
        keepAwakeUntil.map { $0 > Date() } == true
    }

    var powerState: PowerState {
        let remaining = keepAwakeUntil.map { max(0, $0.timeIntervalSinceNow) }
        return PowerState(
            graceRemaining: remaining.flatMap { $0 > 0 ? $0 : nil },
            lastCheckSucceeded: lastCheckSucceeded
        )
    }

    func setConsumer(_ consumer: Consumer, active: Bool) {
        let changed: Bool
        if active {
            changed = consumers.insert(consumer).inserted
        } else {
            changed = consumers.remove(consumer) != nil
        }
        guard changed else { return }

        if consumers.isEmpty {
            stopPolling(clearState: true)
        } else {
            startPollingIfNeeded()
        }
        stateChanged?()
    }

    func updateConfiguration(apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmedKey
        UserDefaults.standard.set(trimmedKey, forKey: "jellyfinAPIKey")
        stopPolling(clearState: false)
        if consumers.isEmpty {
            clearActivity(status: "Off")
        } else {
            startPollingIfNeeded()
        }
        stateChanged?()
    }

    func checkNow() async {
        guard !consumers.isEmpty, !apiKey.isEmpty, !isChecking else { return }
        let requestGeneration = generation
        isChecking = true
        defer {
            if generation == requestGeneration {
                isChecking = false
                stateChanged?()
            }
        }

        do {
            let sessions = try await fetchSessions()
            guard generation == requestGeneration, !consumers.isEmpty else { return }
            lastCheckSucceeded = true
            connectedSessionCount = sessions.filter {
                $0.userName?.isEmpty == false || $0.nowPlayingItem != nil
            }.count
            playingSessionCount = sessions.filter { $0.nowPlayingItem != nil }.count

            if connectedSessionCount > 0 || playingSessionCount > 0 {
                keepAwakeUntil = Date().addingTimeInterval(Self.graceInterval)
                let sessionSummary = connectedSessionCount == 1
                    ? "1 Jellyfin session"
                    : "\(connectedSessionCount) Jellyfin sessions"
                status = playingSessionCount > 0
                    ? "\(sessionSummary) • \(playingSessionCount) playing"
                    : sessionSummary
            } else {
                if !shouldKeepAwake { keepAwakeUntil = nil }
                status = "No active sessions"
            }
        } catch {
            guard generation == requestGeneration, !consumers.isEmpty else { return }
            lastCheckSucceeded = false
            connectedSessionCount = 0
            playingSessionCount = 0
            status = "Jellyfin check failed: \(error.localizedDescription)"
            if !shouldKeepAwake { keepAwakeUntil = nil }
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil else { return }
        guard !apiKey.isEmpty else {
            clearActivity(status: "API key required")
            return
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkNow()
                do {
                    try await Task.sleep(for: .seconds(Self.pollInterval))
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling(clearState: Bool) {
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        isChecking = false
        lastCheckSucceeded = false
        if clearState { clearActivity(status: "Off") }
    }

    private func clearActivity(status: String) {
        keepAwakeUntil = nil
        connectedSessionCount = 0
        playingSessionCount = 0
        self.status = status
    }

    private func fetchSessions() async throws -> [JellyfinSession] {
        guard var components = URLComponents(string: "http://localhost:8096/Sessions") else {
            throw APIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "ActiveWithinSeconds", value: "60")]
        guard let url = components.url else { throw APIError.invalidResponse }

        let escapedKey = apiKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "MediaBrowser Client=\"Disk Awake\", Device=\"Mac\", DeviceId=\"\(Self.deviceID)\", Version=\"1.0\", Token=\"\(escapedKey)\"",
            forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode([JellyfinSession].self, from: data)
    }

    private static let deviceID: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "jellyfinDeviceID") { return existing }
        let value = UUID().uuidString
        defaults.set(value, forKey: "jellyfinDeviceID")
        return value
    }()

    private enum APIError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "The Jellyfin server returned an invalid response"
            case .httpStatus(401):
                "API key was rejected"
            case .httpStatus(let status):
                "Jellyfin returned HTTP \(status)"
            }
        }
    }
}
