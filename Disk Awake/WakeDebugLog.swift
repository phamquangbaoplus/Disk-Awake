import AppKit
import Foundation
import Darwin

/// Diagnostic logging never creates a power assertion or wakes the display.
@MainActor
final class WakeDebugLog: NSObject {
    var enabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    private var started = false
    private var clockMonitor: Task<Void, Never>?
    private var lastSleepTime = 0.0

    func start() {
        guard enabled, !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screenWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        append("DEBUG_STARTED pid=\(ProcessInfo.processInfo.processIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        append("INFO Wake events confirm this app resumed execution, not receipt of a Magic Packet. No wake event does not prove wake failed. No display-wake request is made.")
        lastSleepTime = accumulatedSleepTime()
        clockMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self else { return }
                let current = self.accumulatedSleepTime()
                let elapsed = current - self.lastSleepTime
                if elapsed > 0.1 {
                    self.record("WAKE_OBSERVED source=clock sleepSeconds=\(elapsed) classification=unknown (may be background/Dark Wake); packetReceipt=unknown")
                }
                self.lastSleepTime = current
            }
        }
    }

    func stop() {
        clockMonitor?.cancel()
        clockMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        started = false
    }

    func record(_ event: String) {
        guard enabled else { return }
        append(event)
    }

    @objc private func willSleep() {
        record("SYSTEM_WILL_SLEEP notification=NSWorkspace; sleep requested, completion not yet confirmed")
    }

    @objc private func didWake() {
        record("SYSTEM_DID_WAKE notification=NSWorkspace; app running; packetReceipt=unknown")
    }

    @objc private func screenSleep() {
        record("SCREENS_DID_SLEEP notification=NSWorkspace")
    }

    @objc private func screenWake() {
        record("SCREENS_DID_WAKE notification=NSWorkspace; observed, not requested by debug logger")
    }

    private func accumulatedSleepTime() -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let absolute = mach_absolute_time()
        let continuous = mach_continuous_time()
        return Double(continuous - absolute) * Double(info.numer) / Double(info.denom) / 1e9
    }

    private func append(_ event: String) {
        #if DEBUG
        let timestamp = Date().ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
        print("[Disk Awake] \(timestamp) \(event.replacingOccurrences(of: "\n", with: " "))")
        #endif
    }
}
