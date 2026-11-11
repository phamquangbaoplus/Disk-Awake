# Tự động phát hành Disk Awake

- Push vào `main`: build Release, tạo DMG và GitHub Release chính thức, đặt làm bản mới nhất (Latest).
- Workflow tự tạo tag dạng `build-<số lần chạy>-<commit>` tại commit vừa push; không cần tạo hay chọn tag thủ công.
- Có thể chạy thủ công trong Actions → Build DMG and release.
- Release đính kèm DMG và checksum SHA-256; artifact cũng được lưu trong Actions.

## Thiết lập một lần

Dự án dùng `project.xcproj`, Xcode 27.2 và deployment target macOS 27.2.
Runner phải có Xcode tương thích; workflow không hạ phiên bản macOS của ứng dụng.

1. Trong GitHub Settings → Actions → Runners, thêm runner macOS với label `disk-awake`.
2. Cài Xcode 27.2, chọn bằng `xcode-select`, chấp nhận license; cài `brew install create-dmg gh`.
3. Chạy runner trong phiên người dùng đã đăng nhập có Finder. Cho phép Terminal/runner điều khiển Finder khi macOS yêu cầu để đặt ảnh nền và vị trí biểu tượng.
4. Cho phép GitHub Actions chạy trong repository. Workflow sử dụng `GITHUB_TOKEN` với `contents: write`, không cần PAT.

Có thể đặt repository variable `MACOS_RUNNER` thành chuỗi JSON chứa tên runner khác, ví dụ `["self-hosted","macOS","disk-awake"]`. Chỉ chuyển sang runner hosted khi image đó có Xcode đọc được định dạng dự án này và hỗ trợ cấu hình Finder.

App hiện được ký ad hoc, chưa có Developer ID/notarization; macOS Gatekeeper có thể chặn bản tải xuống. Cần bổ sung chứng chỉ và notarization để phát hành với danh tính nhà phát triển được Apple xác thực.

## Ảnh nền DMG

Mặc định script tự vẽ nền 660 × 440 với mũi tên, hướng dẫn tiếng Anh và tiếng Việt. Hai biểu tượng nằm tại (170, 205) và (490, 205), tính từ góc trên trái cửa sổ Finder.

Để dùng ảnh riêng, commit ảnh PNG/JPG vào `packaging/`, rồi đặt repository variable `DMG_BACKGROUND` thành đường dẫn, ví dụ `packaging/background.png`. Để trống dùng nền mặc định; đặt `none` để bỏ nền. Nên dùng ảnh 660 × 440 và chừa vùng cho biểu tượng.

Đóng gói app đã build trên máy:

```sh
bash scripts/package-dmg.sh '/path/to/Disk Awake.app' dist/Disk-Awake.dmg
DMG_BACKGROUND=packaging/background.png bash scripts/package-dmg.sh '/path/to/Disk Awake.app' dist/Disk-Awake-custom.dmg
```

Sau khi commit các thay đổi, chỉ cần push vào `main` để tự động tạo DMG và release:

```sh
git push origin main
```

Tag tự sinh chỉ đặt tên release/DMG; cập nhật `MARKETING_VERSION` trong dự án khi tăng phiên bản app. Build number trong CI lấy từ `github.run_number`.

Tham khảo: [create-dmg](https://github.com/create-dmg/create-dmg), [GitHub CLI releases](https://cli.github.com/manual/gh_release_create).
