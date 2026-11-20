import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: DiskAwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AwakeHeader()

            ControlSection(
                "Mac",
                systemImage: "desktopcomputer",
                headerTrailing: { EmptyView() }
            ) {
                AwakeToggleRow(
                    "Keep Mac Awake",
                    isOn: $model.keepMacAwake
                )
                .help("Prevents automatic system sleep while this app is running. The display can still sleep, and you can still put your Mac to sleep manually.")

            }

            ControlSection(
                "External Drives",
                systemImage: "externaldrive",
                headerTrailing: { DriveSectionStatus(model: model) }
            ) {
                AwakeToggleRow(
                    "Keep External Drives Awake",
                    isOn: $model.enabled
                )

                Divider().opacity(0.6)
                JellyfinDriveAwakeSection(
                    controller: model.jellyfinDrives,
                    activity: model.jellyfinActivity
                )
            }

            Divider()
            AwakeFooter(model: model)
        }
        .padding(16)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ControlSection<HeaderTrailing: View, Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                headerTrailing
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct AwakeToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct AwakeHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Disk Awake").font(.headline)
        }
    }
}

private struct DriveSectionStatus: View {
    let model: DiskAwakeModel

    var body: some View {
        HStack(spacing: 6) {
            Text("\(model.disks.count) drives")
            Text("•").foregroundStyle(.tertiary)
            if !model.drivesShouldBeKeptAwake {
                Text("Paused")
            } else if model.disks.isEmpty {
                Text("No external drives")
            } else if !model.disks.contains(where: { $0.writable }) {
                Text("Read-only drives")
            } else {
                WriteCountdown(
                    nextWrite: model.disks.compactMap { model.nextWriteDate(for: $0) }.min(),
                    isWriting: model.writingDiskID != nil
                )
            }
        }
        .font(.caption)
        .monospacedDigit()
    }
}

private struct JellyfinDriveAwakeSection: View {
    @Bindable var controller: JellyfinDriveAwakeController
    @Bindable var activity: JellyfinActivityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AwakeToggleRow(
                "Keep External Drives Awake for Jellyfin",
                isOn: $controller.enabled
            )
            .help("Checks Jellyfin every 15 seconds. When a client is connected or playing, all writable external drives stay active for 5 minutes.")

            if controller.enabled {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Text(activity.status)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if activity.isChecking {
                            ProgressView().controlSize(.mini)
                        }
                        if let deadline = activity.keepAwakeUntil, deadline > context.date {
                            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60)) left")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AwakeFooter: View {
    let model: DiskAwakeModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
            Spacer()
            let errorCount = model.disks.filter { $0.hasWriteError }.count
            if errorCount > 0 {
                Label("\(errorCount) write errors", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .controlSize(.small)
        }
    }
}

struct JellyfinSettingsView: View {
    @Bindable var activity: JellyfinActivityMonitor
    @State private var apiKey = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Jellyfin") {
                LabeledContent("Server") {
                    Text("localhost:8096")
                        .foregroundStyle(.secondary)
                }
                TextField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        activity.updateConfiguration(apiKey: apiKey)
                        saved = true
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 420)
        .onAppear { apiKey = activity.apiKey }
        .onChange(of: apiKey) { _, _ in saved = false }
    }
}

private struct WriteCountdown: View {
    let nextWrite: Date?
    let isWriting: Bool

    var body: some View {
        if isWriting {
            Text("Writing…").foregroundStyle(.tint)
        } else if let nextWrite {
            TimelineView(.periodic(from: nextWrite.addingTimeInterval(-30), by: 1)) { context in
                let seconds = max(0, Int(ceil(nextWrite.timeIntervalSince(context.date))))
                if seconds > 0 {
                    Text("Write in \(seconds)s").foregroundStyle(.secondary)
                } else {
                    Text("Waiting…").foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Waiting…").foregroundStyle(.secondary)
        }
    }
}
