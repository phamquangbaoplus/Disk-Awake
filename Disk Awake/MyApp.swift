import SwiftUI
import AppKit

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Disk Awake", systemImage: "externaldrive.badge.checkmark") {
            ContentView(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            JellyfinSettingsView(activity: delegate.model.jellyfinActivity)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DiskAwakeModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateOlderInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    private func terminateOlderInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        let currentLaunchDate = current.launchDate ?? Date()
        let currentPID = current.processIdentifier
        let olderInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).filter { application in
            guard application.processIdentifier != currentPID else { return false }
            let launchDate = application.launchDate ?? .distantPast
            if launchDate != currentLaunchDate { return launchDate < currentLaunchDate }
            return application.processIdentifier < currentPID
        }

        guard !olderInstances.isEmpty else { return }
        for application in olderInstances {
            _ = application.terminate()
        }

        // Older builds do not know about the single-instance handshake. Give
        // them time to clean up power assertions, then ensure they are gone.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for application in olderInstances where !application.isTerminated {
                _ = application.forceTerminate()
            }
        }
    }
}
