# Disk Awake

Ứng dụng nhỏ trên thanh menu macOS, giúp giữ ổ đĩa ngoài hoạt động bằng cách ghi dữ liệu định kỳ và tùy chọn ngăn Mac tự động ngủ.

<p align="center">
  <img src=".github/assets/disk-awake.png" alt="Disk Awake trên thanh menu macOS với hai công tắc Keep Mac Awake và Keep All External Drives Awake" width="560">
</p>

## Tính năng

- Tự động nhận diện các ổ đĩa ngoài đang được gắn vào máy.
- Ghi 4 KiB mỗi 30 giây lên mỗi volume ngoài có thể ghi.
- Bật hoặc tắt việc giữ tất cả ổ ngoài hoạt động bằng một công tắc.
- Giữ Mac thức độc lập với tính năng ghi lên ổ đĩa.
- Hiển thị số volume kết nối, thời gian đến lần ghi tiếp theo và số lỗi ghi.
- Chạy trên thanh menu, không có biểu tượng trong Dock.
- Tạm dừng ghi khi hệ thống ngủ và tiếp tục sau khi màn hình thức dậy.

## Yêu cầu

- **macOS 27.2 trở lên**, theo deployment target hiện tại của dự án.
- Xcode hỗ trợ định dạng dự án và SDK tương ứng để biên dịch từ mã nguồn. Cấu hình dự án hiện ghi nhận Xcode 27.2.
- Quyền ghi vào thư mục gốc của volume ngoài để dùng tính năng giữ ổ hoạt động.

## Biên dịch và chạy

1. Clone repository:

   ```sh
   git clone https://github.com/phamquangbaoplus/Disk-Awake.git
   cd Disk-Awake
   open "Disk Awake.xcodeproj"
   ```

2. Chọn scheme **Disk Awake** và đích chạy **My Mac** trong Xcode.
3. Nếu Xcode yêu cầu cấu hình ký ứng dụng, chọn development team của bạn trong **Signing & Capabilities**.
4. Nhấn **⌘R** để biên dịch và chạy.
5. Bấm biểu tượng ổ đĩa trên thanh menu để mở bảng điều khiển.

## Cách sử dụng

| Điều khiển | Chức năng |
| --- | --- |
| **Keep Mac Awake** | Ngăn hệ thống tự động ngủ do không hoạt động. Màn hình vẫn có thể ngủ và bạn vẫn có thể cho Mac ngủ thủ công. |
| **Keep All External Drives Awake** | Bật hoặc tắt việc ghi định kỳ cho tất cả volume ngoài có thể ghi. |
| **Quit** | Thoát ứng dụng, dừng ghi và giải phóng yêu cầu giữ Mac thức. |

Tính năng giữ ổ ngoài hoạt động mặc định được bật trong lần chạy đầu và ghi nhớ lựa chọn giữa các lần mở ứng dụng. **Keep Mac Awake** mặc định tắt mỗi khi khởi động ứng dụng và chỉ áp dụng cho phiên hiện tại.

## Cơ chế hoạt động

Ứng dụng quét các volume mỗi 15 giây, chọn volume cục bộ được macOS nhận diện là bên ngoài và bỏ qua volume ẩn. Ổ nội bộ và ổ mạng không thuộc phạm vi xử lý; volume chỉ đọc được nhận diện nhưng không được ghi.

Trên mỗi volume có thể ghi, Disk Awake tạo một tệp ẩn có tên `.disk-awake-<UUID>` trong thư mục gốc. Mỗi lần ghi sẽ thay nội dung bằng 4 KiB dữ liệu ngẫu nhiên, giữ kích thước tệp ở 4 KiB và yêu cầu đồng bộ xuống ổ đĩa bằng `F_FULLFSYNC`, với `fsync` làm phương án dự phòng. Tệp được đóng sau mỗi lần ghi.

Tệp này được tái sử dụng và không tự xóa khi thoát. Nếu không còn dùng ứng dụng, bạn có thể thoát Disk Awake rồi xóa tệp `.disk-awake-<UUID>` do ứng dụng tạo trên từng volume.

Việc ghi định kỳ giúp tạo hoạt động trên ổ đĩa; hiệu quả chống ngủ còn phụ thuộc vào phần cứng và firmware của ổ hoặc hộp chuyển đổi. Bật giữ ổ ngoài hoạt động riêng lẻ không ngăn Mac ngủ.

## Khắc phục sự cố

| Trạng thái | Cách kiểm tra |
| --- | --- |
| **No external drives** | Kiểm tra ổ đã được mount trong Finder và chờ lần quét tiếp theo, thường trong vòng 15 giây. |
| **Read-only drives** | Kiểm tra định dạng và quyền ghi của volume. Ứng dụng không ghi lên volume chỉ đọc. |
| **Paused** | Bật **Keep All External Drives Awake** để tiếp tục ghi. |
| **write errors** | Kiểm tra kết nối, dung lượng trống và quyền ghi vào thư mục gốc của volume. |
| Ổ vẫn ngủ | Kiểm tra chế độ tiết kiệm điện của ổ hoặc hộp chuyển đổi; một số thiết bị có cơ chế ngủ riêng. |

## Cấu trúc dự án

| Đường dẫn | Vai trò |
| --- | --- |
| `Disk Awake/MyApp.swift` | Điểm khởi chạy ứng dụng và giao diện thanh menu. |
| `Disk Awake/ContentView.swift` | Công tắc điều khiển, trạng thái và đếm ngược. |
| `Disk Awake/DiskAwakeModel.swift` | Phát hiện volume, ghi định kỳ và quản lý trạng thái ngủ/thức. |
| `Disk Awake/Localizable.xcstrings` | Chuỗi giao diện và bản dịch. |
| `.github/assets/` | Ảnh phục vụ README, nằm ngoài thư mục mã nguồn ứng dụng. |

## Đóng góp

Bạn có thể [báo lỗi hoặc đề xuất tính năng](https://github.com/phamquangbaoplus/Disk-Awake/issues). Khi báo lỗi liên quan đến ổ đĩa, hãy kèm phiên bản macOS, loại ổ hoặc hộp chuyển đổi, định dạng volume và các bước tái hiện.

## Giấy phép

Repository hiện chưa có tệp `LICENSE` quy định giấy phép sử dụng mã nguồn.
