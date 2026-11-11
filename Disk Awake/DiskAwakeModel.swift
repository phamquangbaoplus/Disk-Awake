import AppKit
import Foundation
import Observation
import Darwin

struct MountedDisk: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let writable: Bool
    var lastSuccess: Date?
    var message = String(localized: "Waiting for the first write")
    var hasWriteError = false
}

// All filesystem work runs off the main actor. Descriptors are closed after
// every pulse so the app does not retain an open file between intervals.
actor DiskWorker {
    func discover() throws -> [MountedDisk] {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [
            .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey,
            .volumeUUIDStringKey, .volumeNameKey
        ]
        return (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]
        ) ?? []).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true,
                  values.volumeIsInternal == false else { return nil }
            return MountedDisk(
                id: values.volumeUUIDString ?? url.path,
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                writable: values.volumeIsReadOnly != true
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func pulse(_ disk: MountedDisk, filename: String) throws -> Bool {
        try Task.checkCancellation()

        // Recheck mount identity immediately before opening. Never recreate a
        // missing mount path or follow a symlink to another filesystem.
        guard try discover().contains(where: { $0.id == disk.id && $0.url == disk.url }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try Task.checkCancellation()
        let directory = open(disk.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        var volumeInfo = statfs()
        guard fstatfs(directory, &volumeInfo) == 0,
              volumeInfo.f_flags & UInt32(MNT_LOCAL) != 0,
              volumeInfo.f_flags & UInt32(MNT_ROOTFS) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try Task.checkCancellation()
        let file = openat(directory, filename, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard file >= 0 else { throw posixError() }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == getuid() else { throw CocoaError(.fileWriteNoPermission) }

        var bytes = [UInt8](repeating: 0, count: 4096)
        arc4random_buf(&bytes, bytes.count)
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { throw CocoaError(.fileWriteUnknown) }
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let count = pwrite(file, base.advanced(by: offset),
                                   buffer.count - offset, off_t(offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        try Task.checkCancellation()
        guard ftruncate(file, 4096) == 0 else { throw posixError() }
        if fcntl(file, F_FULLFSYNC) == 0 { return true }
        guard fsync(file) == 0 else { throw posixError() }
        return false
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

@MainActor
@Observable
final class DiskAwakeModel: NSObject {
    var disks: [MountedDisk] = []
    var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            needsTick = true
            sleepTask?.cancel()
        }
    }
    // Session-only, independent of the periodic disk writes.
    var keepMacAwake = false {
        didSet { updateMacAwakeActivity() }
    }
    @ObservationIgnored private var macAwakeActivity: NSObjectProtocol?

    private func updateMacAwakeActivity() {
        if keepMacAwake && !suspendedForSystemSleep {
            guard macAwakeActivity == nil else { return }
            macAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Disk Awake: Keep Mac Awake"
            )
        } else if let macAwakeActivity {
            ProcessInfo.processInfo.endActivity(macAwakeActivity)
            self.macAwakeActivity = nil
        }
    }

    @objc private func applicationWillTerminate() {
        keepMacAwake = false
    }

    private let pulseInterval: TimeInterval = 30
    private let scanInterval: TimeInterval = 15
    private var nextScan = Date.distantPast
    private var lastAttempt: [String: Date] = [:]
    private(set) var writingDiskID: String?
    private var loop: Task<Void, Never>?
    private var sleepTask: Task<Void, Error>?
    private var needsTick = false
    private var suspendedForSystemSleep = false
    private var observingSleep = false
    private let worker = DiskWorker()
    private var activity: NSObjectProtocol?
    private let filename: String = {
        let defaults = UserDefaults.standard
        let token = defaults.string(forKey: "fileToken") ?? UUID().uuidString
        defaults.set(token, forKey: "fileToken")
        return ".disk-awake-" + token
    }()

    func start() {
        if !observingSleep {
            let center = NSWorkspace.shared.notificationCenter
            center.addObserver(self, selector: #selector(systemWillSleep),
                               name: NSWorkspace.willSleepNotification, object: nil)
            center.addObserver(self, selector: #selector(screensDidWake),
                               name: NSWorkspace.screensDidWakeNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(applicationWillTerminate),
                name: NSApplication.willTerminateNotification, object: nil
            )
            observingSleep = true
        }
        guard loop == nil, !suspendedForSystemSleep else { return }
        loop = Task { [weak self] in
            defer {
                self?.loop = nil
                // A screen wake may arrive while a cancelled disk operation unwinds.
                if let self, !self.suspendedForSystemSleep, Task.isCancelled {
                    self.start()
                }
            }
            while !Task.isCancelled {
                guard let self else { return }
                self.needsTick = false
                await self.tick()
                guard !Task.isCancelled, !self.suspendedForSystemSleep else { return }
                if self.needsTick { continue }
                // Wake at the next scan or write deadline, independently.
                // A scan must never round a pending write up to another 15 seconds.
                var deadline = self.nextScan
                if self.enabled {
                    for disk in self.disks where disk.writable {
                        let due = (self.lastAttempt[disk.id] ?? .distantPast)
                            .addingTimeInterval(self.pulseInterval)
                        deadline = min(deadline, due)
                    }
                }
                let delay = max(0.1, deadline.timeIntervalSinceNow)
                let sleeper = Task {
                    try await Task.sleep(for: .seconds(delay), clock: .continuous)
                }
                self.sleepTask = sleeper
                // Cancel only the wait, keeping disk writes serialized in this loop.
                _ = await sleeper.result
                self.sleepTask = nil
            }
        }
    }

    @objc private func systemWillSleep() {
        suspendedForSystemSleep = true
        updateMacAwakeActivity()
        loop?.cancel()
        sleepTask?.cancel()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    @objc private func screensDidWake() {
        guard suspendedForSystemSleep else { return }
        // Deliberately do not resume on didWakeNotification: background wakes
        // must not restart disk I/O. Wait for the display to wake instead.
        suspendedForSystemSleep = false
        updateMacAwakeActivity()
        nextScan = .distantPast
        let now = Date()
        for disk in disks {
            lastAttempt[disk.id] = now
        }
        start()
    }

    func nextWriteDate(for disk: MountedDisk) -> Date? {
        guard !suspendedForSystemSleep, enabled, disk.writable,
              let attempt = lastAttempt[disk.id] else { return nil }
        return attempt.addingTimeInterval(pulseInterval)
    }

    private func refreshDisks() async {
        guard let mounted = try? await worker.discover(),
              !Task.isCancelled, !suspendedForSystemSleep else { return }
        disks = mounted.map { disk in
            var updated = disk
            if let previous = disks.first(where: { $0.id == disk.id && $0.url == disk.url }) {
                updated.lastSuccess = previous.lastSuccess
                updated.message = previous.message
                updated.hasWriteError = previous.hasWriteError
            }
            return updated
        }
        let ids = Set(disks.map(\.id))
        lastAttempt = lastAttempt.filter { ids.contains($0.key) }
    }

    private func tick() async {
        guard !Task.isCancelled, !suspendedForSystemSleep else { return }
        if Date() >= nextScan {
            await refreshDisks()
            nextScan = Date().addingTimeInterval(scanInterval)
        }
        guard !Task.isCancelled, !suspendedForSystemSleep else { return }
        let active = enabled && disks.contains { $0.writable }
        if active && activity == nil {
            // Disable App Nap, but allow the Mac itself to sleep normally.
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: String(localized: "Keep external drives active with periodic writes")
            )
        } else if !active, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        guard enabled else { return }
        for disk in disks where disk.writable {
            guard !Task.isCancelled, !suspendedForSystemSleep else { return }
            guard enabled else { return }
            if let previous = lastAttempt[disk.id],
               Date().timeIntervalSince(previous) < pulseInterval { continue }
            lastAttempt[disk.id] = Date()
            writingDiskID = disk.id
            defer { writingDiskID = nil }
            do {
                let fullSync = try await worker.pulse(
                    disk, filename: filename
                )
                if let index = disks.firstIndex(where: { $0.id == disk.id }) {
                    disks[index].lastSuccess = Date()
                    disks[index].hasWriteError = false
                    disks[index].message = fullSync
                        ? String(localized: "Written and synced to the drive")
                        : String(localized: "Written; the drive only supports fsync")
                }
            } catch is CancellationError {
                return
            } catch {
                if let index = disks.firstIndex(where: { $0.id == disk.id }) {
                    let nsError = error as NSError
                    disks[index].hasWriteError = true
                    disks[index].message = String(localized: "Error: Could not write to the drive (\(nsError.domain), code \(nsError.code)).", comment: "Write failure; first value is the error domain, second is the error code.")
                }
            }
        }
    }

}
