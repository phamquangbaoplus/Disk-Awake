import Foundation
import Observation

@MainActor
@Observable
final class JellyfinAwakeController: NSObject {
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

    func start() {
        guard enabled, worker == nil else { return }
        generation += 1
        let session = generation
        let worker = JellyfinPowerWorker { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, self.enabled else { return }
                self.status = state
            }
        }
        self.worker = worker
        worker.start()
    }

    func stop() {
        generation += 1
        worker?.stop()
        worker = nil
        status = "Waiting for Jellyfin"
    }
}
