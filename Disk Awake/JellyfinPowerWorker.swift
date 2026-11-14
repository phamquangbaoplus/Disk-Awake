import Foundation
import IOKit.pwr_mgt
import Darwin

// Runs outside the main actor. netstat includes sockets owned by other users,
// unlike a per-process file-descriptor scan.
nonisolated struct JellyfinConnectionScanner {
    enum ScanError: LocalizedError {
        case commandFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let status):
                "netstat failed or was terminated (exit status \(status))."
            }
        }
    }

    static func hasEstablishedConnection() throws -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-an", "-p", "tcp"]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/usr/sbin:/bin:/sbin"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ScanError.commandFailed(process.terminationStatus)
        }
        return Self.containsConnection(String(decoding: data, as: UTF8.self))
    }

    nonisolated static func containsConnection(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 6,
                  fields[0] == "tcp4" || fields[0] == "tcp6",
                  fields[5] == "ESTABLISHED" else { return false }
            // Match the LOCAL port only; outgoing connections to another
            // server's 8096 must not keep this Mac awake.
            return fields[3].hasSuffix(".8096")
        }
    }
}


// Private SPI ABI from Apple's IOPMLibPrivate.h. Resolve at runtime so a
// missing SPI produces a visible error, not a launch-time linker failure.
nonisolated private final class PowerConnectionAPI {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UInt32, UInt32) -> Void
    typealias Create = @convention(c) (CFString, UInt32, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    typealias SetNotification = @convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Callback) -> Int32
    typealias SetQueue = @convention(c) (OpaquePointer, DispatchQueue?) -> Void
    typealias Acknowledge = @convention(c) (OpaquePointer, UInt32) -> Int32
    typealias Release = @convention(c) (OpaquePointer) -> Int32
    typealias Capabilities = @convention(c) () -> UInt32

    private let library: UnsafeMutableRawPointer
    let create: Create
    let setNotification: SetNotification
    let setQueue: SetQueue
    let acknowledge: Acknowledge
    let release: Release
    let capabilities: Capabilities

    init?() {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        guard let create = dlsym(library, "IOPMConnectionCreate"),
              let notification = dlsym(library, "IOPMConnectionSetNotification"),
              let queue = dlsym(library, "IOPMConnectionSetDispatchQueue"),
              let acknowledge = dlsym(library, "IOPMConnectionAcknowledgeEvent"),
              let release = dlsym(library, "IOPMConnectionRelease"),
              let capabilities = dlsym(library, "IOPMConnectionGetSystemCapabilities") else {
            dlclose(library)
            return nil
        }
        self.library = library
        // Keep the framework loaded for the lifetime of these function pointers.
        self.create = unsafeBitCast(create, to: Create.self)
        setNotification = unsafeBitCast(notification, to: SetNotification.self)
        setQueue = unsafeBitCast(queue, to: SetQueue.self)
        self.acknowledge = unsafeBitCast(acknowledge, to: Acknowledge.self)
        self.release = unsafeBitCast(release, to: Release.self)
        self.capabilities = unsafeBitCast(capabilities, to: Capabilities.self)
    }

    deinit { dlclose(library) }
}

/// Mutable state is confined to queue. Scans run on a separate queue so even
/// a stalled netstat cannot delay acknowledgement of a power notification.
nonisolated final class JellyfinPowerWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "DiskAwake.power", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "DiskAwake.tcp", qos: .utility)
    private let report: @Sendable (LocalizedStringResource) -> Void
    private var api: PowerConnectionAPI?
    private var connection: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var assertion: IOPMAssertionID = 0
    private var deadline: ContinuousClock.Instant?
    private var running = false
    private var cpuAvailable = true
    private var scanInFlight = false
    private var generation = 0
    private var lastSnapshot = ""
    private var lastLogTime = ContinuousClock.now

    init(report: @escaping @Sendable (LocalizedStringResource) -> Void) {
        self.report = report
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            guard let api = PowerConnectionAPI() else {
                report("Dark Wake monitoring is unavailable on this macOS version.")
                log("POWER_API_UNAVAILABLE")
                return
            }
            self.api = api
            var newConnection: OpaquePointer?
            let result = api.create("Disk Awake Jellyfin" as CFString, 0x1F, &newConnection)
            guard result == 0, let newConnection else {
                report("Could not register for Dark Wake notifications.")
                log("POWER_REGISTER_FAILED result=\(result)")
                return
            }
            connection = newConnection
            let callbackResult = api.setNotification(newConnection, Unmanaged.passUnretained(self).toOpaque()) {
                context, connection, token, capabilities in
                guard let context, let connection else { return }
                let worker = Unmanaged<JellyfinPowerWorker>.fromOpaque(context).takeUnretainedValue()
                worker.powerChanged(connection: connection, token: token, capabilities: capabilities)
            }
            guard callbackResult == 0 else {
                _ = api.release(newConnection)
                connection = nil
                report("Could not register for Dark Wake notifications.")
                log("POWER_CALLBACK_FAILED result=\(callbackResult)")
                return
            }
            running = true
            cpuAvailable = api.capabilities() & 1 != 0
            // Suppress App Nap without preventing system sleep.
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Monitor Jellyfin power and network events"
            )
            api.setQueue(newConnection, queue)
            log("POWER_REGISTERED interests=CPU,Video,Audio,Network,Disk queue=background capabilities=\(api.capabilities())")
            if cpuAvailable { grantGrace(reason: "enabled") }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .seconds(5), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        // No scanning or main-actor work can block this queue.
        queue.sync {
            running = false
            generation += 1
            timer?.cancel()
            timer = nil
            if let connection, let api {
                api.setQueue(connection, nil)
                _ = api.release(connection)
            }
            connection = nil
            deadline = nil
            releaseAssertion()
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            log("POWER_MONITOR_STOPPED")
        }
    }

    private func powerChanged(connection: OpaquePointer, token: UInt32, capabilities: UInt32) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let api else { return }
        // Every token must be acknowledged promptly, including sleep events.
        defer {
            let result = api.acknowledge(connection, token)
            log("POWER_ACK token=\(token) result=\(result)")
        }
        guard running else { return }
        let hadCPU = cpuAvailable
        cpuAvailable = capabilities & 1 != 0
        let hasVideo = capabilities & 2 != 0
        log("POWER_EVENT capabilities=\(capabilities) cpu=\(cpuAvailable) video=\(hasVideo) network=\(capabilities & 8 != 0) mainThread=\(Thread.isMainThread)")
        if !cpuAvailable {
            generation += 1
            deadline = nil
            releaseAssertion()
            report("Waiting for Mac to wake")
        } else if !hadCPU {
            generation += 1
            // Take the assertion synchronously BEFORE acknowledging the wake.
            // Never dispatch this critical work to AppKit's main run loop.
            grantGrace(reason: hasVideo ? "fullWake" : "darkWake")
        }
    }

    private func grantGrace(reason: String) {
        deadline = .now.advanced(by: .seconds(300))
        updateAssertion()
        if reason != "tcp" {
            log("WAKE_GRACE reason=\(reason) seconds=300 assertionID=\(assertion) displayWakeRequested=false")
        }
    }

    private func tick() {
        guard running, cpuAvailable else { return }
        updateAssertion()
        guard !scanInFlight else { return }
        scanInFlight = true
        let session = generation
        scanQueue.async { [self] in
            let result = Result { try JellyfinConnectionScanner.hasEstablishedConnection() }
            queue.async { [self] in
                scanInFlight = false
                guard running, cpuAvailable, generation == session else { return }
                switch result {
                case .success(let connected):
                    if connected { grantGrace(reason: "tcp") }
                    snapshot("TCP_SCAN established=\(connected) assertionID=\(assertion)")
                    if assertion != 0 {
                        report(connected
                            ? "Jellyfin connected — keeping Mac awake"
                            : "Keeping Mac awake for Jellyfin — 5-minute grace period")
                    }
                case .failure(let error):
                    snapshot("TCP_SCAN_FAILED \(error.localizedDescription)")
                    report("Cannot inspect TCP 8096 connections")
                }
            }
        }
    }

    private func updateAssertion() {
        guard let deadline, ContinuousClock.now < deadline else {
            releaseAssertion()
            report("No Jellyfin connections — system sleep allowed")
            return
        }
        let duration = ContinuousClock.now.duration(to: deadline).components
        let seconds = max(1, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        if assertion != 0 {
            let result = IOPMAssertionSetProperty(assertion, kIOPMAssertionTimeoutKey as CFString,
                                                  NSNumber(value: seconds))
            if result == 0 {
                let levelResult = IOPMAssertionSetProperty(
                    assertion, kIOPMAssertionLevelKey as CFString,
                    NSNumber(value: kIOPMAssertionLevelOn)
                )
                if levelResult == 0 { return }
                log("ASSERTION_LEVEL_FAILED result=\(levelResult)")
            }
            if result != 0 { log("ASSERTION_RENEW_FAILED result=\(result)") }
            releaseAssertion()
        }
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertNetworkClientActive,
            kIOPMAssertionNameKey: "Disk Awake: Jellyfin TCP 8096",
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionTimeoutKey: seconds,
            kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionTurnOff
        ]
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &assertion)
        log("ASSERTION_CREATE id=\(assertion) result=\(result) seconds=\(seconds) displayWakeRequested=false")
        if result == 0 {
            report("Keeping Mac awake for Jellyfin — 5-minute grace period")
        } else {
            assertion = 0
            report("Could not keep Mac awake for Jellyfin")
        }
    }

    private func releaseAssertion() {
        guard assertion != 0 else { return }
        let result = IOPMAssertionRelease(assertion)
        log("ASSERTION_RELEASE id=\(assertion) result=\(result)")
        assertion = 0
    }

    private func snapshot(_ value: String) {
        let now = ContinuousClock.now
        guard value != lastSnapshot || lastLogTime.duration(to: now) >= .seconds(60) else { return }
        log(value)
        lastSnapshot = value
        lastLogTime = now
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Disk Awake] \(Date().ISO8601Format()) \(message)")
        #endif
    }
}
