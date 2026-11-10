import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: DiskAwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AwakeHeader(enabled: $model.enabled)
            Divider()
            DiskList(model: model)
            Divider()
            AwakeFooter()
        }
        .padding(16)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AwakeHeader: View {
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Awake").font(.title2.bold())
                Text(enabled ? "Keep awake every 30 seconds" : "Paused")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Keep Drives Awake", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct DiskList: View {
    let model: DiskAwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("External Drives").font(.headline)
                Spacer()
                Text("\(model.disks.count) connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.disks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.title)
                    Text("Connect a drive to get started")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Give the scroll region a real height in the menu bar window.
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.disks) { disk in
                            DiskRow(model: model, disk: disk)
                        }
                    }
                }
                .frame(height: min(CGFloat(model.disks.count) * 82, 300))
            }
        }
    }
}

private struct AwakeFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Write 30s · Scan 15s")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .help("Pauses when your Mac sleeps and resumes when it wakes. Every 30 seconds, writes and syncs 4 KB to a hidden file on each selected drive. Effectiveness depends on the drive or DAS firmware.")
                .accessibilityLabel("How Disk Awake works")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }
}

private struct DiskRow: View {
    let model: DiskAwakeModel
    let disk: MountedDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.isSelected(disk) },
                set: { model.select(disk, enabled: $0) }
            )) {
                Label(disk.name, systemImage: "externaldrive")
                    .font(.headline)
                    .lineLimit(1)
                    .help(disk.url.path)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!disk.writable)

            if !disk.writable {
                Label("Read-only drive", systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if !model.enabled || !model.isSelected(disk) {
                Text("Paused")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    if disk.message.hasPrefix("Error:") {
                        Label("Write failed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(disk.message)
                    } else if let date = disk.lastSuccess {
                        Text("Last write \(date.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.secondary)
                            .help(disk.message)
                    } else {
                        Text("No writes yet").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    WriteCountdown(
                        nextWrite: model.nextWriteDate(for: disk),
                        isWriting: model.writingDiskID == disk.id
                    )
                }
                .monospacedDigit()
            }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
                    Text("Write in \(seconds)s").foregroundStyle(.white)
                } else {
                    Text("Waiting…").foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Waiting…").foregroundStyle(.secondary)
        }
    }
}
