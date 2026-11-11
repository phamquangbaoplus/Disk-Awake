import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: DiskAwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AwakeHeader(model: model)
            Divider()
            Toggle(isOn: $model.keepMacAwake) {
                Label("Keep Mac Awake", systemImage: "cup.and.saucer")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Prevents automatic system sleep while this app is running. The display can still sleep, and you can still put your Mac to sleep manually.")
            Toggle(isOn: $model.enabled) {
                Label("Keep All External Drives Awake", systemImage: "externaldrive")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Divider()
            AwakeFooter(model: model)
        }
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AwakeHeader: View {
    let model: DiskAwakeModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Disk Awake").font(.headline)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(model.disks.count) connected")
                if !model.enabled {
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
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct AwakeFooter: View {
    let model: DiskAwakeModel

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
        }
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
