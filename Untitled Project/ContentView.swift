import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: DiskAwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Disk Awake").font(.title2.bold())
                    Text(model.enabled ? "Tự động giữ thức ổ đĩa ngoài" : "Đang tạm dừng")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Bật giữ thức", isOn: $model.enabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $model.interval, in: 10...600, step: 5) {
                    Text("Chu kỳ: \(model.interval) giây").monospacedDigit()
                }
                Text("Đặt chu kỳ ngắn hơn thời gian tự sleep của DAS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Ổ ngoài đang mount").font(.headline)
                Spacer()
                Text("\(model.disks.count)").foregroundStyle(.secondary)
            }
            if model.disks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus").font(.largeTitle)
                    Text("Đang chờ ổ đĩa")
                        .font(.headline)
                    Text("Tự chạy khi ổ ngoài được mount; tự dừng khi unmount.")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.disks) { disk in
                            DiskRow(model: model, disk: disk)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            Text("Mỗi lần ghi 4 KB vào tệp ẩn .disk-awake-… trên ổ và yêu cầu đồng bộ. Chỉ áp dụng cho ổ ngoài cục bộ có quyền ghi. Bạn có thể tắt các ổ SSD không cần giữ thức.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Ứng dụng hoạt động khi Mac đang thức. Khả năng ngăn sleep tùy firmware DAS; trạng thái ghi không phải trạng thái quay của HDD.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("Tự kiểm tra mount mỗi 2 giây", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Thoát") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct DiskRow: View {
    let model: DiskAwakeModel
    let disk: MountedDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(
                get: { model.isSelected(disk) },
                set: { model.select(disk, enabled: $0) }
            )) {
                Label(disk.name, systemImage: "externaldrive")
                    .font(.headline)
            }
            .disabled(!disk.writable)
            Text(disk.url.path)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !disk.writable {
                Label("Ổ chỉ đọc — không thể giữ thức bằng ghi", systemImage: "lock")
                    .font(.caption).foregroundStyle(.orange)
            } else if !model.enabled || !model.isSelected(disk) {
                Text("Đã tạm dừng").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(disk.message).font(.caption)
                if let date = disk.lastSuccess {
                    Text("Lần ghi thành công: \(date.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
