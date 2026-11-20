import Foundation
import Observation

/// Owns the macOS power policy for Jellyfin. Session detection is delegated to
/// JellyfinActivityMonitor; the worker only handles Dark Wake, TCP bootstrap,
/// and the IOPM assertion.
@MainActor
@Observable
final class JellyfinAwakeController: NSObject {
    let activity: JellyfinActivityMonitor

    var enabled = UserDefaults.standard.bool(forKey: "keepMacAwakeForJellyfin") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "keepMacAwakeForJellyfin")
            enabled ? start() : stop()
        }
    }
    private(set) var status: LocalizedStringResource = "Waiting for Jellyfin"
    @ObservationIgnored weak var debugLog: WakeDebugLog?
    @ObservationIgnored private var worker: JellyfinPowerWorker?
    @ObservationIgnored private var generation = 0

    init(activity: JellyfinActivityMonitor) {
        self.activity = activity
    }

    func start() {
        guard enabled, worker == nil else { return }
        generation += 1
        let session = generation
        let worker = JellyfinPowerWorker(
            report: { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session, self.enabled else { return }
                    self.status = state
                }
            },
            requestActivityRefresh: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session, self.enabled else { return }
                    await self.activity.checkNow()
                }
            }
        )
        self.worker = worker
        activity.setConsumer(.macAwake, active: true)
        worker.start()
        activityDidChange()
    }

    func stop() {
        generation += 1
        activity.setConsumer(.macAwake, active: false)
        worker?.stop()
        worker = nil
        status = "Waiting for Jellyfin"
    }

    func activityDidChange() {
        guard enabled, let worker else { return }
        let state = activity.powerState
        worker.updateJellyfinActivity(
            graceRemaining: state.graceRemaining,
            apiCheckSucceeded: state.lastCheckSucceeded
        )
    }
}
