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
    var message = "Chờ lần truy cập đầu tiên"
}

// All filesystem work runs off the main actor. Descriptors are closed after
// every pulse so the app does not retain an open file between intervals.
actor DiskWorker {
    func discover() -> [MountedDisk] {
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

        // Recheck mount identity immediately before opening. Never recreate a
        // missing mount path or follow a symlink to another filesystem.
        guard discover().contains(where: { $0.id == disk.id && $0.url == disk.url }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = open(disk.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        var volumeInfo = statfs()
        guard fstatfs(directory, &volumeInfo) == 0,
              volumeInfo.f_flags & UInt32(MNT_LOCAL) != 0,
              volumeInfo.f_flags & UInt32(MNT_ROOTFS) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
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
                let count = pwrite(file, base.advanced(by: offset),
                                   buffer.count - offset, off_t(offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
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
final class DiskAwakeModel {
    var disks: [MountedDisk] = []
    var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }
    var interval = max(10, min(600, UserDefaults.standard.object(forKey: "interval") as? Int ?? 30)) {
        didSet { UserDefaults.standard.set(interval, forKey: "interval") }
    }
    private var excluded = Set(UserDefaults.standard.stringArray(forKey: "excluded") ?? [])
    private var lastAttempt: [String: Date] = [:]
    private var loop: Task<Void, Never>?
    private let worker = DiskWorker()
    private var activity: NSObjectProtocol?
    private let filename: String = {
        let defaults = UserDefaults.standard
        let token = defaults.string(forKey: "fileToken") ?? UUID().uuidString
        defaults.set(token, forKey: "fileToken")
        return ".disk-awake-" + token
    }()

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func isSelected(_ disk: MountedDisk) -> Bool { !excluded.contains(disk.id) }

    func select(_ disk: MountedDisk, enabled: Bool) {
        if enabled { excluded.remove(disk.id) } else { excluded.insert(disk.id) }
        UserDefaults.standard.set(Array(excluded), forKey: "excluded")
        lastAttempt[disk.id] = nil
    }

    private func tick() async {
        let mounted = await worker.discover()
        disks = mounted.map { disk in
            var updated = disk
            if let previous = disks.first(where: { $0.id == disk.id && $0.url == disk.url }) {
                updated.lastSuccess = previous.lastSuccess
                updated.message = previous.message
            }
            return updated
        }
        let ids = Set(disks.map(\.id))
        lastAttempt = lastAttempt.filter { ids.contains($0.key) }
        let active = enabled && disks.contains { isSelected($0) && $0.writable }
        if active && activity == nil {
            // Disable App Nap, but allow the Mac itself to sleep normally.
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Duy trì truy cập định kỳ cho ổ đĩa ngoài"
            )
        } else if !active, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        guard enabled else { return }
        for disk in disks where disk.writable && isSelected(disk) {
            guard enabled, isSelected(disk) else { continue }
            if let previous = lastAttempt[disk.id],
               Date().timeIntervalSince(previous) < Double(interval) { continue }
            lastAttempt[disk.id] = Date()
            do {
                let fullSync = try await worker.pulse(
                    disk, filename: filename
                )
                if let index = disks.firstIndex(where: { $0.id == disk.id }) {
                    disks[index].lastSuccess = Date()
                    disks[index].message = fullSync ? "Đã ghi và đồng bộ xuống ổ" : "Đã ghi; ổ chỉ hỗ trợ fsync"
                }
            } catch {
                if let index = disks.firstIndex(where: { $0.id == disk.id }) {
                    disks[index].message = "Lỗi: " + error.localizedDescription
                }
            }
        }
    }

}
