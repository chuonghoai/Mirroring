# Mirroring Monorepo

<p align="center">
  <strong>Ứng dụng phản chiếu màn hình Android lên Windows qua mạng LAN nội bộ — không cần dây cáp, không cần ADB hay Wireless Debugging khi sử dụng thông thường.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011%20(x64)-0078D6?logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/Android-8.0%2B%20(API%2026%2B)-3DDC84?logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Flutter-3.47%2B-02569B?logo=flutter&logoColor=white" alt="Flutter" />
</p>

---

## 1. Tổng quan dự án

Repository `mirroring` là một **Monorepo** chứa hai ứng dụng Flutter độc lập và một gói giao thức dùng chung:

1. **`apps/mirroring_windows` (Mirroring Windows):** Ứng dụng desktop trên Windows dùng để tự động tìm các thiết bị Android Companion trong cùng mạng LAN, gửi yêu cầu kết nối, giải mã luồng video H.264 bằng phần cứng (Windows Media Foundation) và hiển thị màn hình điện thoại theo thời gian thực. Đồng thời vẫn giữ nguyên chế độ **ADB & scrcpy (Nâng cao)** từ phiên bản trước.
2. **`apps/mirroring_mobile` (Mirroring Android Companion):** Ứng dụng Android (tên hiển thị `Mirroring`, dùng chung biểu tượng gốc từ Windows) lắng nghe yêu cầu từ Windows qua LAN, hiển thị hộp thoại cho phép người dùng **Chấp nhận / Từ chối**, xin quyền `MediaProjection`, khởi chạy **Android Foreground Service** bền bỉ (chạy nền ngay cả khi thoát UI hoặc vuốt khỏi Recent Apps) và truyền luồng H.264 nén phần cứng (`MediaCodec`).
3. **`packages/mirroring_protocol`:** Gói Dart thuần định nghĩa bản tin tìm kiếm UDP, bản tin điều khiển WebSocket, khung nhị phân video `MRV1`, và kiểm tra bảo mật token.

---

## 2. Cấu trúc Monorepo

```text
mirroring/
├── .agents/                        # Cấu hình & kỹ năng cho agent dùng chung
├── apps/
│   ├── mirroring_windows/          # Ứng dụng Flutter Desktop Windows
│   │   ├── assets/                 # Logo gốc (app_icon.jpg)
│   │   ├── lib/                    # UI LAN, Viewer, controller & legacy ADB/scrcpy
│   │   ├── test/                   # Unit, widget & loopback integration tests
│   │   ├── tools/scrcpy/           # Công cụ nhị phân ADB & scrcpy cho chế độ nâng cao
│   │   ├── windows/                # Win32 runner + Media Foundation H.264 decoder C++
│   │   ├── analysis_options.yaml
│   │   └── pubspec.yaml
│   └── mirroring_mobile/           # Ứng dụng Flutter Android Companion ("Mirroring")
│       ├── android/                # Kotlin Native: Discovery, WS Control, ForegroundService, MediaCodec
│       ├── assets/                 # Dùng chung app_icon.jpg từ bản Windows
│       ├── lib/                    # Flutter UI & MethodChannel/EventChannel bridge
│       ├── test/                   # Companion state, approval & UI tests
│       ├── analysis_options.yaml
│       └── pubspec.yaml
├── packages/
│   └── mirroring_protocol/         # Giao thức LAN dùng chung (Discovery, Control, Framing, Security)
├── docs/
│   └── architecture.md             # Tài liệu kỹ thuật chi tiết
├── build-release.ps1               # Script PowerShell build release cả 2 ứng dụng
├── install-mobile.ps1              # Script PowerShell cài APK lên Android qua ADB (dev/deploy)
├── LICENSE
├── THIRD-PARTY-NOTICES.md
└── README.md
```

---

## 3. Trách nhiệm các thành phần

### Mirroring Windows (`apps/mirroring_windows`)
- Phát và lắng nghe gói tin tìm kiếm UDP trên cổng `45454` để phát hiện các điện thoại đang mở Mirroring trong cùng mạng LAN.
- Quản lý danh sách thiết bị với đầy đủ 9 trạng thái: *Sẵn sàng, Đã gửi yêu cầu, Chờ xác nhận, Đang kết nối, Đã kết nối, Đang trình chiếu, Đã ngắt kết nối, Không khả dụng, Kết nối thất bại*.
- Kết nối WebSocket điều khiển, nhận `sessionToken` sau khi điện thoại chấp nhận, mở kết nối TCP nhận video H.264 và giải mã trực tiếp bằng `CLSID_CMSH264DecoderMFT` (Windows Media Foundation) lên `Texture` của Flutter.
- Hỗ trợ đẩy Clipboard từ Windows sang Android (`Ctrl+V` hoặc nút **Gửi Clipboard**).
- Tự động gửi `sessionStop` an toàn khi đóng cửa sổ Windows (`WM_CLOSE` deferral) để Android dừng Foreground Service và gỡ thông báo.
- Duy trì đầy đủ chế độ **ADB & scrcpy** (cùng tính năng tạo shortcut Desktop và ẩn/hiện cửa sổ) ở tab phụ cho người dùng cần điều khiển chuột/bàn phím xuyên ứng dụng.

### Mirroring Android Companion (`apps/mirroring_mobile`)
- Định danh ứng dụng: **Mirroring** (`com.chuonghoai.mirroring`), dùng lại đúng logo gốc từ Windows để tạo launcher icon & adaptive icon.
- Phát hiện máy tính Windows trong mạng LAN (sử dụng `WifiManager.MulticastLock`).
- Nhận yêu cầu kết nối qua WebSocket, hiển thị hộp thoại xác nhận kèm tên máy tính, IP và bộ đếm hết hạn `30 giây`. Không ghi màn hình trước khi người dùng bấm chấp nhận.
- Sau khi chấp nhận, xin quyền `MediaProjection` theo chuẩn Android 8–15+.
- Khởi chạy `MirroringForegroundService` (`foregroundServiceType="mediaProjection"`, `stopWithTask="false"`) cùng thông báo cố định đang chia sẻ màn hình và nút **Dừng chia sẻ**.
- Mã hóa màn hình bằng `MediaCodec` (`video/avc`, Surface input, tự xử lý xoay màn hình & thay đổi độ phân giải).
- Giám sát heartbeat: nếu Windows sập hoặc mất mạng đột ngột, chuyển sang trạng thái chờ kết nối lại tối đa `20 giây` rồi tự động dừng và giải phóng toàn bộ tài nguyên.

---

## 4. Kiến trúc kỹ thuật

Xem chi tiết tại [docs/architecture.md](docs/architecture.md):
- **Discovery:** UDP Broadcast cổng `45454`, magic `MIRRORING_LAN_V1`, tự loại bỏ thiết bị ngoại tuyến sau `7s`, chống trùng lặp theo `deviceId`.
- **Control Channel:** WebSocket RFC 6455 (cổng mặc định `45455`), xác thực bằng `sessionToken` 256-bit ngẫu nhiên.
- **Video Streaming:** TCP (`TCP_NODELAY`, cổng mặc định `45456`) với header nhị phân 24-byte `MRV1` mang luồng H.264 Annex-B (SPS/PPS + IDR + P-frames).

---

## 5. Yêu cầu môi trường & Cài đặt phát triển

### Yêu cầu hệ thống
- **Windows:** Windows 10 hoặc Windows 11 (64-bit).
- **Android:** Android 8.0 (API 26) trở lên.
- **Mạng LAN:** Máy tính Windows và điện thoại Android phải kết nối cùng một mạng Wi-Fi/LAN và **không bị router bật Client/AP Isolation** (cách ly các thiết bị cùng Wi-Fi).

### Công cụ phát triển
- **Flutter SDK:** `>= 3.47.0` (Dart `>= 3.11.0`)
- **Visual Studio 2022 / Build Tools:** Gói *Desktop development with C++* và Windows 10/11 SDK
- **Android SDK + JDK 17/21** (để build APK)
- **ADB** (chỉ dùng cho script `tools/install-mobile.ps1` khi cài đặt APK lên máy test; **không cần khi sử dụng bình thường**)

### Chạy ở chế độ phát triển

Chạy ứng dụng Windows:
```powershell
cd apps\mirroring_windows
flutter pub get
flutter run -d windows
```

Chạy ứng dụng Android Companion:
```powershell
cd apps\mirroring_mobile
flutter pub get
flutter run
```

Chạy kiểm thử tự động cho cả 3 gói:
```powershell
cd packages\mirroring_protocol; dart test
cd ..\..\apps\mirroring_windows; flutter test
cd ..\mirroring_mobile; flutter test
```

---

## 6. Quyền Android & Hành vi dịch vụ nền

### Các quyền khai báo trong AndroidManifest
- `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`: Tìm kiếm LAN UDP và truyền video TCP/WebSocket nội bộ.
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`: Duy trì `MediaProjection` ở dịch vụ nền hợp lệ trên Android 14+.
- `POST_NOTIFICATIONS`: Hiển thị thông báo trạng thái chia sẻ màn hình đang hoạt động trên Android 13+.

### Lưu ý & Giới hạn hệ điều hành Android
1. **Giữ chạy nền khi thoát UI / vuốt Recent Apps:** `MirroringForegroundService` chạy độc lập với `MainActivity` và đặt `android:stopWithTask="false"`, nên bạn có thể bấm Home, mở app khác hoặc vuốt Mirroring khỏi màn hình đa nhiệm mà quá trình chia sẻ vẫn tiếp tục.
2. **Force Stop & Khởi động lại:** Nếu bạn vào Cài đặt hệ thống bấm **Buộc dừng (Force Stop)** hoặc khởi động lại máy, Android sẽ chấm dứt mọi dịch vụ và phiên chia sẻ kết thúc theo đúng quy định hệ điều hành.
3. **Tối ưu pin OEM:** Một số hãng (Xiaomi, Oppo, Vivo) có thể chặn dịch vụ nền nếu bật giới hạn pin nghiêm ngặt; nên đặt ứng dụng ở mức *Không hạn chế* hoặc *Tối ưu hóa* nếu bị ngắt bất thường.
4. **Quyền MediaProjection theo từng phiên:** Android không cho phép lưu vĩnh viễn quyền ghi màn hình cho các phiên sau; mỗi lần kết nối mới người dùng đều cần xác nhận trên hộp thoại hệ thống.
5. **Điều khiển cảm ứng & bàn phím qua mạng LAN (v2.0.0):** `MediaProjection` chỉ đọc hình ảnh màn hình. Để điều khiển chạm, vuốt, cuộn, Back/Home/Recents và gõ chữ trên Windows qua LAN **không cần ADB**, hãy bật dịch vụ **Mirroring Remote Control** trong *Cài đặt > Hỗ trợ (Trợ năng / Accessibility) > Dịch vụ đã cài đặt* trên điện thoại (hoặc bấm nút **Bật ngay** ngay trong app Mirroring Android). Tab **ADB & scrcpy** vẫn được giữ nguyên làm chế độ nâng cao dự phòng.

---

## 7. Build bản phát hành (PowerShell)

Chạy từ thư mục gốc repository (hoặc bất kỳ thư mục nào):

```powershell
# Build cả Windows Release và Android Release APK
.\build-release.ps1

# Chỉ build Windows
.\build-release.ps1 -WindowsOnly

# Chỉ build Android APK
.\build-release.ps1 -MobileOnly

# Bỏ qua bước flutter analyze
.\build-release.ps1 -SkipAnalyze
```

Thành phẩm đầu ra:
- **Windows Release:** `apps\mirroring_windows\build\windows\x64\runner\Release\` (gồm `Mirroring.exe`, `flutter_windows.dll`, `data\`, `tools\scrcpy\`, `LICENSE`, `THIRD-PARTY-NOTICES.md`)
- **Android Release APK:** `apps\mirroring_mobile\build\app\outputs\flutter-apk\app-release.apk`

---

## 8. Cài đặt APK lên điện thoại qua ADB (Tùy chọn cho dev/triển khai)

> Lưu ý: Script này chỉ phục vụ cài đặt APK qua ADB Wireless Debugging/USB đã được ghép nối và ủy quyền sẵn. Khi sử dụng Mirroring hàng ngày qua LAN, bạn không cần bật ADB.

```powershell
# Tự động cài nếu chỉ có 1 thiết bị ADB hợp lệ (hoặc hỏi chọn nếu có nhiều thiết bị)
.\install-mobile.ps1

# Chỉ định rõ serial thiết bị
.\install-mobile.ps1 -Serial "192.168.1.50:5555"
```

---

## 9. Xử lý sự cố thường gặp

- **Không thấy điện thoại trong danh sách LAN:**
  - Kiểm tra cả Windows và Android đang dùng chung một mạng Wi-Fi (không bật 4G/5G hoặc VPN trên một trong hai máy).
  - Kiểm tra Windows Defender Firewall: nếu lần đầu chạy Windows hỏi quyền mạng Private/Public cho `Mirroring.exe`, hãy chọn **Allow access** (cần UDP `45454` và TCP đi ra `45455`/`45456`).
  - Kiểm tra router Wi-Fi không bật tính năng *AP Isolation / Client Isolation*.
- **Thông báo nền không hiện trên Android 13+:**
  - Cấp quyền **Thông báo (Notifications)** cho ứng dụng Mirroring trong phần Cài đặt ứng dụng.
- **Màn hình đen hoặc không giải mã được trên Windows:**
  - Đảm bảo chạy trên Windows 10/11 với bộ giải mã H.264 Media Foundation tích hợp sẵn; nếu điện thoại vừa đổi trạng thái khóa màn hình, hãy thử dừng và kết nối lại.

---

## 10. Giấy phép

Mã nguồn thuộc dự án **Mirroring** được phát hành theo giấy phép **[MIT License](LICENSE)**.
Thông tin bản quyền các thành phần bên thứ ba và biểu tượng ứng dụng được ghi nhận đầy đủ tại **[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)**.
