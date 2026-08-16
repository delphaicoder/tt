# AppOpenAnimation — Hiệu ứng mở/đóng app kiểu iOS 26 concept (iPadOS 15-16, Rootless)

## 1. Phân tích kỹ thuật từ video (dữ liệu đo thật)

Video gửi kèm là bản slow-motion thật của **iOS 26/iPadOS 26 Beta** ("Slowed to
20%"). Mình đo quỹ đạo mở/đóng app Calculator bằng cách phân tích pixel qua
từng khung hình (đếm vùng tối/vùng đang biến hình, quy đổi ra % kích thước theo
thời gian thực — đã bù hệ số chậm 20%).

| Thông số | Giá trị đo được |
|---|---|
| Thời lượng hình học lúc mở | ~100–110ms tới 99% kích thước |
| Overshoot (nảy quá đích) | **Không có** — đường cong tăng đơn điệu, không vượt 100% |
| Damping (độ nảy) | Cao (~0.86–0.90) |
| Hình dạng đường cong | Tăng nhanh 0–60ms (0→94%), rồi "settle" chậm dần 60–110ms |
| Nội dung app | Placeholder tối/mờ hiện trước, ~100–130ms sau mới crossfade sang UI thật |
| Nền (wallpaper/dock) | Không mờ/dim — giữ nguyên nét suốt |
| Lúc đóng | Đối xứng, hơi lâu hơn (~130–150ms), cũng không overshoot |

**Kết luận quan trọng**: hiệu ứng thật của Apple **không nảy kiểu spring bouncy**
như hay thấy ở concept — mà là ease-out mượt, nhanh, damping cao. Các hằng số
trong `Tweak.x` được tune theo đúng số liệu này.

## 1b. Cập nhật: hiệu ứng "thẻ nổi" (floating card) theo ảnh tham khảo

Theo ảnh so sánh iOS 18 vs iOS 26 bạn gửi, animation mở giờ đi qua **3 giai
đoạn**: icon → thẻ nổi bo tròn (thấy được wallpaper/dock xung quanh) → full màn
hình. Animation đóng đối xứng lại.

**Giới hạn quan trọng cần hiểu**: vì tweak chỉ là overlay phủ lên trên (không
đổi kích thước cửa sổ app thật — xem mục 2), thẻ nổi chỉ là một **điểm dừng
giữa chừng trong animation**, không phải trạng thái cuối cùng. App thật vẫn sẽ
full màn hình bình thường; overlay chỉ "đi qua" hình dạng thẻ nổi cho đẹp mắt
rồi mới mở tiếp ra full để lộ app thật ra. Muốn app thật sự giữ nguyên ở dạng
cửa sổ nhỏ (giống visionOS/Stage Manager) thì cần hook sâu hơn nhiều vào cách
hệ thống định kích thước window — rủi ro cao, ngoài phạm vi bản này.

## 2. Quyết định kiến trúc an toàn — ĐỌC TRƯỚC KHI DÙNG

Yêu cầu gốc là hook `SBUIAppOpenAnimationController` để **thay thế toàn bộ**
pipeline mở/đóng app. Bản này **cố ý không làm vậy**:

- `SBUIAppOpenAnimationController` là lõi quyết định app có mở được hay không.
  Đây là API private, không có class-dump để xác minh chính xác tên
  method/tham số trên từng bản iOS 15/16 cụ thể. Hook sai ở tầng này có thể
  khiến **app không mở được nữa, hoặc SpringBoard treo** — hoàn toàn khác với
  các tweak trang trí khác (folder, overlay) chỉ hỏng phần thẩm mỹ chứ không
  hỏng chức năng.
- Thay vào đó, tweak này dùng kỹ thuật **an toàn hơn nhiều**: bắt lúc chạm icon
  (`SBIconView touchesBegan/touchesEnded` — phương thức `UIResponder` tiêu
  chuẩn, không phải API bí mật gì đặc biệt), chụp nhanh ảnh icon, rồi **phủ một
  lớp overlay riêng** chạy animation của mình. Con đường mở app **thật** của hệ
  thống (`%orig`) **luôn luôn được gọi trước, không điều kiện** — tuyệt đối
  không bị chặn hay trì hoãn bởi bất kỳ lý do gì.
- Nếu overlay có lỗi logic, tệ nhất là animation nhìn không đẹp / hiện sai lúc
  — app vẫn luôn mở được bình thường. Ngoài ra có **timeout cứng 1.2 giây**
  (`kOverlayHardTimeout`) đảm bảo overlay không bao giờ "kẹt" trên màn hình
  vĩnh viễn dù có chuyện gì xảy ra.

## 3. Giới hạn đã biết

1. **Kích hoạt animation đóng** dựa vào `applicationDidResignActive:` /
   `applicationDidBecomeActive:` của SpringBoard (notification công khai, an
   toàn) — nhưng các phương thức này cũng bắn ra khi mở Control Center,
   Notification Center, màn hình khoá... không chỉ riêng lúc mở app. Có thể
   animation đóng đôi khi kích hoạt không đúng lúc (ví dụ sau khi chỉ xem
   Control Center) — đây là đánh đổi có chủ đích để tránh hook sâu hơn/nguy
   hiểm hơn.
2. **Icon nào cũng dùng chung 1 overlay hình chữ nhật bo góc** — không phân
   biệt icon thường/folder/widget. Chưa test riêng cho folder (khuyến nghị tắt
   hiệu ứng khi chạm mở folder nếu thấy xung đột — có thể thêm điều kiện lọc
   class `SBFolderIcon` nếu cần, xem gợi ý trong mã).
3. Chưa test trên thiết bị thật — các con số ANIM_* là điểm khởi đầu tốt dựa
   trên dữ liệu thật, nhưng cảm giác cuối cùng nên tinh chỉnh trực tiếp trên
   máy bạn.

## 4. Cấu trúc project
```
AppOpenAnimation/
├── control
├── Makefile
├── AppOpenAnimation.plist   # filter: chỉ SpringBoard
├── Tweak.x                   # toàn bộ logic (xem chú thích trong file)
└── .github/workflows/build.yml
```

## 5. Các hằng số hay chỉnh nhất (đầu file `Tweak.x`)

| Hằng số | Ý nghĩa | Mặc định (theo số đo thật) |
|---|---|---|
| `kCardStageDuration` | Thời lượng icon → thẻ nổi | `0.09s` |
| `kCardHoldDuration` | Dừng lại ở dạng thẻ nổi bao lâu | `0.10s` |
| `kCardToFullDuration` | Thời lượng thẻ nổi → full màn hình | `0.10s` |
| `kCardWidthRatio` / `kCardHeightRatio` / `kCardTopRatio` | Tỉ lệ kích thước/vị trí thẻ nổi | `0.62 / 0.58 / 0.13` |
| `kCloseGeometryDuration` | Thời lượng lúc đóng | `0.14s` |
| `kSpringDamping` | Độ nảy (1.0 = không nảy) | `0.86` |
| `kSpringInitialVelocity` | Vận tốc ban đầu (mô phỏng lực tha tay) | `0.55` |
| `kContentHoldDuration` | Thời gian giữ placeholder trước khi lộ app thật | `0.12s` |
| `kOverlayFadeOutDuration` | Thời gian mờ dần overlay | `0.10s` |

Muốn nảy nhiều hơn kiểu concept bouncy (khác với số đo thật từ Apple), giảm
`kSpringDamping` xuống `0.65–0.75`.

## 6. Build .deb rootless bằng Theos

### GitHub Actions (khuyến nghị)
Tạo repo mới, upload nội dung thư mục này, tab **Actions** tự build trên Ubuntu
runner miễn phí, tải `.deb` ở mục **Artifacts**.

### Tự build
```bash
export THEOS=/path/to/theos
cd AppOpenAnimation
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

## 7. Cài đặt
Cài `.deb` qua Sileo (Filza → "Open in Sileo"). Tự respring sau khi cài.

## 8. Nếu overlay gây vấn đề
Vì mọi rủi ro đều nằm ở overlay (không phải pipeline mở app thật), cách gỡ an
toàn nhất nếu có sự cố: xoá file `.dylib` của tweak qua Filza tại
`/var/jb/Library/MobileSubstrate/DynamicLibraries/AppOpenAnimation.dylib` (hoặc
đường dẫn tương đương không có `/var/jb` nếu bạn dùng jailbreak rootful), rồi
respring — app vẫn mở bình thường ngay vì pipeline gốc chưa từng bị đụng vào.
