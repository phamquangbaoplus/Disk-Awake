import Foundation
import Observation

/// Feature preference for external drives. Jellyfin HTTP state lives in the
/// shared monitor so the Mac and drive features never poll independently.
@MainActor
@Observable
final class JellyfinDriveAwakeController {
    let activity: JellyfinActivityMonitor

    var enabled = UserDefaults.standard.bool(forKey: "keepExternalDrivesAwakeForJellyfin") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "keepExternalDrivesAwakeForJellyfin")
            enabled ? start() : stop()
        }
    }

    init(activity: JellyfinActivityMonitor) {
        self.activity = activity
    }

    var shouldKeepDrivesAwake: Bool {
        enabled && activity.shouldKeepAwake
    }

    func start() {
        activity.setConsumer(.externalDrives, active: enabled)
    }

    func stop() {
        activity.setConsumer(.externalDrives, active: false)
    }
}
