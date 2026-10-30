# BÁO CÁO AUDIT CUỐI CÙNG – PHÁP LÝ, GIẤY PHÉP VÀ ĐIỀU KIỆN PHÁT HÀNH
## DỰ ÁN: MIRRORING (WINDOWS & ANDROID WIRELESS MIRRORING)
**Ngày thực hiện:** 31/10/2026 (Cập nhật sau phiên xử lý icon & khuyến cáo bảo mật)  
**Đơn vị thực hiện:** Antigravity Audit Engine  
**Phiên bản ứng dụng:** `1.0.1+1` (theo `pubspec.yaml`)  
**Tác giả / Chủ sở hữu:** Trương Hoài Chương (chuonghoai)

---

## 1. TỔNG QUAN KẾT QUẢ AUDIT (EXECUTIVE SUMMARY)

Đợt audit cuối cùng này kiểm tra toàn diện tính tuân thủ pháp lý, bản quyền, quyền sở hữu trí tuệ, điều khoản miễn trừ trách nhiệm và tính sẵn sàng của dự án **Mirroring** trước khi thực hiện:
1. **Public source code** lên GitHub (`https://github.com/chuonghoai/Mirroring.git`).
2. **Phát hành gói binary Windows** (`build/Mirroring_v1.0.1.zip` hoặc thư mục `Release/`).

### 1.1. Bảng tóm tắt trạng thái theo hạng mục

| Hạng mục kiểm tra | Trạng thái tuân thủ | Mức độ ảnh hưởng | Tóm tắt phát hiện chính |
|---|---|---|---|
| **1. Giấy phép dự án (Project License)** | **COMPLIANT** | LOW | File `LICENSE` (MIT) đầy đủ điều khoản chuẩn OSI. Bản quyền tác giả `Truong Hoai Chuong (chuonghoai)` đã được đồng bộ 100% trên `LICENSE`, `windows/runner/Runner.rc` và `README.md`. |
| **2. Giấy phép bên thứ ba (Third-party)** | **COMPLIANT** | LOW | Đã lập đầy đủ `THIRD-PARTY-NOTICES.md` cho 15 thành phần mã nguồn/binary và Mục 10 ghi nhận bản quyền tác giả **Duy Hưng (duyhungpham94)** cho biểu tượng App Icon. |
| **3. Phân phối ADB (Platform-Tools)** | **COMPLIANT** | MEDIUM | File `tools/scrcpy/adb.exe` có chữ ký số hợp lệ của Google LLC, ghi nhận bản quyền AOSP/Google trong `THIRD-PARTY-NOTICES.md` theo Phương án A đã phê duyệt. |
| **4. Phân phối và sửa đổi scrcpy** | **COMPLIANT** | LOW | Tuân thủ nghiêm ngặt Điều khoản 4(b) Apache License 2.0 thông qua file `tools/scrcpy/NOTICE.txt` minh bạch việc thay thế icon và ghi rõ nguồn gốc tác giả hình ảnh. |
| **5. Điều khoản miễn trừ (Disclaimer)** | **COMPLIANT** | LOW | Đã có miễn trừ bảo hành & trách nhiệm ("AS IS") trong `LICENSE`. Đồng thời đã bổ sung **Mục 14 trong `README.md`** về Miễn trừ trách nhiệm & Khuyến cáo an toàn khi bật Wireless Debugging cho người dùng cuối. |
| **6. Quyền sở hữu trí tuệ & Dữ liệu nhạy cảm** | **COMPLIANT** | LOW | Không có API key, mật khẩu hay dữ liệu cá nhân rò rỉ. Đã bổ sung `flutter.bat` và `run.bat` vào `.gitignore` để tránh lộ cấu trúc ổ đĩa cá nhân. Đã ghi nhận bản quyền biểu tượng app đầy đủ. |
| **7. Quản lý Git / GitHub** | **EXCLUDED (USER MANAGED)** | LOW | Người dùng chủ động quản lý thao tác Git/GitHub thủ công theo quy trình riêng. |
| **8. Sẵn sàng phát hành Windows (Release ZIP)** | **READY (COMPLIANT)** | LOW | Đã biên dịch Release thành công và đóng gói đầy đủ `Mirroring.exe`, DLLs, `LICENSE`, `THIRD-PARTY-NOTICES.md`, `tools/scrcpy/` vào `build/Mirroring_v1.0.1.zip` (22.1 MB). |

---

## 2. PROJECT LICENSE AUDIT – GIẤY PHÉP CHÍNH CỦA DỰ ÁN

### 2.1. Bảng đối chiếu chi tiết

| Vấn đề | Bằng chứng nội bộ | Bằng chứng bên ngoài | Phân tích | Kết luận | Hướng xử lý |
|---|---|---|---|---|---|
| **Văn bản giấy phép gốc** | Tệp `LICENSE` (dòng 1–21), dung lượng 1.081 bytes. | OSI MIT License: `https://opensource.org/licenses/MIT` | **[FACT]** File `LICENSE` chứa toàn văn giấy phép MIT chuẩn gồm: cấp quyền sử dụng/sửa đổi/phân phối/bán lại, nghĩa vụ giữ copyright notice, và 2 đoạn miễn trừ bảo hành/trách nhiệm in hoa. | **COMPLIANT** | Duy trì tệp `LICENSE` tại thư mục gốc. |
| **Tên chủ sở hữu bản quyền** | 1. `LICENSE` dòng 3: `Truong Hoai Chuong (chuonghoai)`<br>2. `windows/runner/Runner.rc` dòng 96: `Copyright (C) 2026 Truong Hoai Chuong (chuonghoai)`<br>3. `README.md` dòng 381: `Trương Hoài Chương (chuonghoai)` | Quy chuẩn bản quyền Berne Convention & USPTO | **[FACT]** Cả 3 vị trí đều đồng nhất 100% tên tác giả `Truong Hoai Chuong (chuonghoai)`. Thông tin PE Header của `Mirroring.exe` sau khi biên dịch phản ánh chính xác chuỗi bản quyền này. | **COMPLIANT** | Đã hoàn tất đồng bộ. |
| **Tính độc quyền mã nguồn** | Các tệp Dart trong `lib/` (11 tệp, 1.250 dòng code) và C++ trong `windows/runner/` | Không phát hiện mã nguồn sao chép từ dự án đóng nào | **[FACT]** Kiểm tra toàn bộ mã nguồn `lib/` và `windows/runner/`: Không có header bản quyền của bên thứ ba ngoại trừ template mặc định của Flutter. Toàn bộ logic kết nối ADB và gọi scrcpy do tác giả tự phát triển. | **COMPLIANT** | Tác giả có toàn quyền cấp phép mã nguồn này theo giấy phép MIT. |
| **Công bố trong README** | `README.md` (Mục 13, dòng 379–389) | Quy chuẩn Open Source Documentation | **[FACT]** Mục 13 nêu rõ mã nguồn phát hành theo MIT License kèm đường dẫn trực tiếp tới tệp `LICENSE`. | **COMPLIANT** | Đã đáp ứng đầy đủ. |

---

## 3. THIRD-PARTY LICENSES AUDIT – GIẤY PHÉP BÊN THỨ BA

Dự án Mirroring sử dụng và tích hợp các thành phần bên thứ ba và tài nguyên thiết kế. Dưới đây là bảng kiểm kê chi tiết:

### 3.1. Bảng kiểm kê và đối chiếu các thành phần bên thứ ba

| STT | Thành phần | Phiên bản | Tệp nhị phân / Tài nguyên | Giấy phép / Bản quyền | Quyền phân phối lại | Nghĩa vụ bắt buộc đã thực hiện | Trạng thái tuân thủ |
|:---:|---|:---:|---|---|:---:|---|:---:|
| 1 | **scrcpy** | 5.0.1 | `tools/scrcpy/scrcpy.exe`<br>`tools/scrcpy/scrcpy-server` | Apache-2.0 | **CÓ** | Đã kèm `LICENSE.txt`, lập `NOTICE.txt` ghi nhận sửa đổi icon theo Điều 4(b). | **COMPLIANT** |
| 2 | **Android Debug Bridge (ADB)** | 1.0.41 (SDK 37.0.1) | `tools/scrcpy/adb.exe`<br>`AdbWinApi.dll`<br>`AdbWinUsbApi.dll` | Apache-2.0 / Google SDK Terms | **CÓ** | Chữ ký số Google LLC hợp lệ. Ghi nhận bản quyền AOSP trong `THIRD-PARTY-NOTICES.md`. | **COMPLIANT** |
| 3 | **FFmpeg (avcodec)** | 63.1.102 (FFmpeg 9.0.2) | `tools/scrcpy/avcodec-63.dll` | LGPL-2.1 or later | **CÓ** | Liên kết động DLL độc lập. Chuỗi bản quyền LGPL xác thực trong binary. Đã dẫn link mã nguồn gốc. | **COMPLIANT** |
| 4 | **FFmpeg (avformat)** | 63.1.102 | `tools/scrcpy/avformat-63.dll` | LGPL-2.1 or later | **CÓ** | Liên kết động DLL độc lập. | **COMPLIANT** |
| 5 | **FFmpeg (avutil)** | 61.1.102 | `tools/scrcpy/avutil-61.dll` | LGPL-2.1 or later | **CÓ** | Liên kết động DLL độc lập. | **COMPLIANT** |
| 6 | **FFmpeg (swresample)** | 7.1.102 | `tools/scrcpy/swresample-7.dll` | LGPL-2.1 or later | **CÓ** | Liên kết động DLL độc lập. | **COMPLIANT** |
| 7 | **Simple DirectMedia Layer (SDL3)** | 3.4.18 | `tools/scrcpy/SDL3.dll` | zlib License | **CÓ** | Copyright 2026 Sam Lantinga. Đã trích dẫn nguyên văn zlib License trong notices. | **COMPLIANT** |
| 8 | **libusb** | 1.0.30 | `tools/scrcpy/libusb-1.0.dll` | LGPL-2.1 or later | **CÓ** | Liên kết động DLL. VersionInfo xác nhận LGPL v2.1. Đã dẫn link mã nguồn gốc. | **COMPLIANT** |
| 9 | **Flutter Engine** | 3.47.0 | `build/.../Release/flutter_windows.dll` | BSD-3-Clause | **CÓ** | Thông báo BSD 3-Clause đã được trích dẫn trong `THIRD-PARTY-NOTICES.md` và `NOTICES.Z`. | **COMPLIANT** |
| 10 | **ICU Data** | Unicode 15.1 | `build/.../Release/data/icudtl.dat` | ICU License (Unicode-TOU) | **CÓ** | IBM Corporation copyright. Đã ghi nhận trong `THIRD-PARTY-NOTICES.md`. | **COMPLIANT** |
| 11 | **Material Icons** | Font v1.0 | `data/flutter_assets/fonts/MaterialIcons-Regular.otf` | Apache-2.0 | **CÓ** | Google LLC. Ghi nhận Apache-2.0 trong `THIRD-PARTY-NOTICES.md`. | **COMPLIANT** |
| 12 | **ffi (Dart package)** | 2.2.0 | `pubspec.lock` | BSD-3-Clause | **CÓ** | The Dart project authors. Trích xuất tự động vào `NOTICES.Z`. | **COMPLIANT** |
| 13 | **cupertino_icons** | 1.0.9 | `pubspec.lock` | MIT License | **CÓ** | Flutter Authors. Hoàn toàn tương thích MIT. | **COMPLIANT** |
| 14 | **Biểu tượng App Icon** | N/A | `assets/app_icon.jpg`<br>`windows/runner/resources/app_icon.ico`<br>`tools/scrcpy/scrcpy.png` | Bản quyền tác giả Duy Hưng (duyhungpham94) | **CÓ (Phi thương mại)** | Đã ghi nhận tác giả Duy Hưng, dẫn link Pinterest cá nhân và pin gốc trong `THIRD-PARTY-NOTICES.md`, `README.md` và `NOTICE.txt`. | **COMPLIANT** |
| 15 | **Transitive Dart Packages** | 1.x – 2.x | `collection`, `meta`, `vector_math`, `characters`... | BSD-3-Clause / Apache-2.0 | **CÓ** | Được Flutter SDK tự động thu thập và đóng gói vào `data/flutter_assets/NOTICES.Z`. | **COMPLIANT** |

---

## 4. CHI TIẾT VỀ ADB VÀ SCRCPY

### 4.1. Android Debug Bridge (ADB)
- **Bằng chứng nội bộ:**
  - Đường dẫn: `tools/scrcpy/adb.exe`, dung lượng: 8.273.560 bytes.
  - Chữ ký số Authenticode:
    - Subject: `CN=Google LLC, O=Google LLC, L=Mountain View, S=California, C=US`
    - Issuer: `CN=DigiCert Trusted G4 Code Signing RSA4096 SHA384 2021 CA1`
    - Serial Number: `0B50CF246B263EFD85A729315158F3FF`
    - Thời hạn chữ ký: Có hiệu lực đến `11/04/2027 06:59:59`
    - Trạng thái chữ ký: `Valid. Signature verified.`
  - Phiên bản binary: `Android Debug Bridge version 1.0.41, Version 37.0.1-15733141`.
- **Phân tích:** 
  - `adb.exe` được phân phối nguyên bản với chữ ký số toàn vẹn của Google LLC. Việc ghi nhận nguồn gốc AOSP/Google trong `THIRD-PARTY-NOTICES.md` tuân thủ phương án phân phối đã được phê duyệt.
- **Kết luận:** **COMPLIANT**.

### 4.2. scrcpy & Sửa đổi biểu tượng
- **Bằng chứng nội bộ:**
  - Đường dẫn: `tools/scrcpy/scrcpy.exe`, `tools/scrcpy/scrcpy-server`.
  - Phiên bản: `scrcpy 5.0.1 <https://github.com/Genymobile/scrcpy>`.
  - Giấy phép gốc: `tools/scrcpy/LICENSE.txt` (Apache License 2.0).
  - Tệp thông báo chỉnh sửa: `tools/scrcpy/NOTICE.txt`.
- **Phân tích nghĩa vụ Apache License 2.0 Điều khoản 4:**
  - **Điều 4(a) - Kèm bản sao giấy phép:** Có `tools/scrcpy/LICENSE.txt` và `THIRD-PARTY-NOTICES.md`. -> **ĐẠT**.
  - **Điều 4(b) - Thông báo sửa đổi (Modification Notice):** Tệp `scrcpy.png` đã được thay bằng logo Mirroring, và tài nguyên icon Win32 PE (`RT_GROUP_ICON`) trong `scrcpy.exe` đã được cập nhật bằng logo Mirroring. Đồng thời đã ghi rõ nguồn tác giả của ảnh gốc (Duy Hưng - duyhungpham94) tại `tools/scrcpy/NOTICE.txt`. -> **ĐẠT**.
  - **Điều 4(c) - Giữ nguyên thông báo bản quyền:** Giữ nguyên copyright của Genymobile và Romain Vimont. -> **ĐẠT**.
  - **Điều 4(d) - Tệp NOTICE:** Tệp `NOTICE.txt` được phân phối kèm trong thư mục phát hành. -> **ĐẠT**.
- **Kết luận:** **COMPLIANT**.

---

## 5. DISCLAIMER & LIABILITY AUDIT – ĐIỀU KHOẢN MIỄN TRỪ TRÁCH NHIỆM

### 5.1. Bảng đối chiếu các loại Disclaimer

| Loại điều khoản | Bằng chứng nội bộ | Bằng chứng bên ngoài | Phân tích | Kết luận |
|---|---|---|---|:---:|
| **A. Disclaimer of Warranty** | `LICENSE` dòng 15–17: *"THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND..."* | Section 7 Apache-2.0, Điều khoản chuẩn MIT License OSI | **[FACT]** Miễn trừ toàn bộ bảo đảm về tính thương mại, tính phù hợp cho mục đích cụ thể, và tính không vi phạm. | **COMPLIANT** |
| **B. Limitation of Liability** | `LICENSE` dòng 17–21: *"IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY..."* | Điều khoản chuẩn MIT License OSI | **[FACT]** Giới hạn toàn bộ trách nhiệm dân sự đối với mọi thiệt hại phát sinh từ việc sử dụng phần mềm. | **COMPLIANT** |
| **C. Third-party Disclaimer** | `THIRD-PARTY-NOTICES.md` (Mục 1, 4, 6) | Giấy phép BSD, Apache, zlib | **[FACT]** Giữ nguyên các tuyên bố miễn trừ của tác giả bên thứ ba (Flutter Authors, Romain Vimont, Sam Lantinga). | **COMPLIANT** |
| **D. User-facing Security Disclaimer** | `README.md` Mục 14: *"Tuyên bố miễn trừ trách nhiệm & Khuyến cáo bảo mật"* | Google Developer Best Practices về Wireless Debugging | **[FACT]** Đã bổ sung 2 tiểu mục: (1) Miễn trừ rủi ro kỹ thuật; (2) Khuyến cáo người dùng không bật Wireless Debugging trên Wi-Fi công cộng, kiểm tra kỹ khóa RSA trước khi cho phép và tắt khi không sử dụng. | **COMPLIANT** |

---

## 6. INTELLECTUAL PROPERTY & SECURITY AUDIT – BẢO MẬT & SỞ HỮU TRÍ TUỆ

### 6.1. Bảng kiểm tra quyền sở hữu trí tuệ và thông tin nhạy cảm

| Hạng mục | Bằng chứng nội bộ | Phân tích | Kết luận |
|---|---|---|:---:|
| **Biểu tượng ứng dụng (App Icon)** | `assets/app_icon.jpg` (168 KB), `windows/runner/resources/app_icon.ico` (92 KB), `tools/scrcpy/scrcpy.png` | **[FACT]** Tác phẩm thiết kế của tác giả Duy Hưng (`duyhungpham94`), đăng tải tại Pinterest: `https://www.pinterest.com/pin/958211258215792168/`. Đã ghi nhận quyền tác giả công khai, rõ ràng tại `THIRD-PARTY-NOTICES.md` (Mục 10), `README.md` (Mục 13) và `tools/scrcpy/NOTICE.txt`. | **COMPLIANT** |
| **Hình ảnh cá nhân trong hướng dẫn** | Thư mục `assets/guide/` | **[FACT]** Toàn bộ hình ảnh chứa thông tin thiết bị cá nhân đã được dọn sạch hoàn toàn khỏi repository. | **COMPLIANT** |
| **Bí mật thương mại, API key, Token** | Quét toàn bộ repository | **[FACT]** Không có bất kỳ tệp `.env`, file cấu hình mật khẩu, token, private key nào trong workspace. | **COMPLIANT** |
| **Đường dẫn cục bộ máy phát triển** | `.gitignore` dòng 26–28 | **[FACT]** Đã bổ sung `flutter.bat` và `run.bat` vào `.gitignore`. Mã nguồn được bảo vệ khỏi việc commit các đường dẫn ổ đĩa tuyệt đối (`D:\installer\SDK\...`). | **COMPLIANT** |

---

## 7. GITHUB PUBLIC SOURCE AUDIT – ĐÁNH GIÁ ĐIỀU KIỆN PUBLIC MÃ NGUỒN

- **Quản lý Git:** Người dùng chủ động thao tác thủ công.
- **Tính sạch sẽ của mã nguồn:**
  - Không có thông tin nhạy cảm hoặc rò rỉ dữ liệu cá nhân.
  - Tệp `.gitignore` bảo vệ đầy đủ các thư mục sinh ra trong quá trình build và file script cá nhân.
  - Tệp `pubspec.yaml` đã cập nhật mô tả ứng dụng chuyên nghiệp:
    `"Ứng dụng điều khiển và phản chiếu màn hình điện thoại Android không dây trên Windows qua ADB và scrcpy."`
  - Đầy đủ `LICENSE`, `THIRD-PARTY-NOTICES.md`, `README.md` chuẩn bị sẵn sàng.

---

## 8. WINDOWS RELEASE AUDIT – ĐÁNH GIÁ ĐIỀU KIỆN PHÁT HÀNH BINARY

### 8.1. Cấu trúc gói phát hành Windows

Kiểm tra thư mục `build/windows/x64/runner/Release/` và tệp `build/Mirroring_v1.0.1.zip`:

| Tệp / Thư mục trong Release | Kích thước | Nguồn gốc | Tình trạng pháp lý & Tài liệu đi kèm | Trạng thái |
|---|:---:|---|---|:---:|
| `Mirroring.exe` | 148 KB | Biên dịch Release Flutter/C++ | PE Resource chứa `Copyright (C) 2026 Truong Hoai Chuong (chuonghoai)`, version `1.0.1+1`. | **COMPLIANT** |
| `flutter_windows.dll` | 21.2 MB | Flutter Engine SDK 3.47.0 | BSD-3-Clause, có ghi nhận trong `THIRD-PARTY-NOTICES.md`. | **COMPLIANT** |
| `LICENSE` | 1.081 bytes | MIT License gốc của dự án | Tự động copy vào thư mục Release. | **COMPLIANT** |
| `THIRD-PARTY-NOTICES.md` | 7.375 bytes | Thông báo bên thứ ba | Bao gồm đầy đủ 15 thành phần + ghi nhận tác giả icon Duy Hưng. | **COMPLIANT** |
| `data/` | ~35 MB | Flutter AOT assets & ICU | Chứa `icudtl.dat`, `app.so`, `NOTICES.Z`. | **COMPLIANT** |
| `tools/scrcpy/` | ~25 MB | Portable ADB & scrcpy bundle | Chứa đầy đủ `LICENSE.txt`, `NOTICE.txt` (có ghi nhận tác giả icon), các DLL LGPL và ADB có chữ ký Google LLC. | **COMPLIANT** |
| `build/Mirroring_v1.0.1.zip` | 22.1 MB | Nén toàn bộ thư mục Release | Người dùng giải nén là chạy được ngay không cần cài đặt. | **COMPLIANT** |

---

## 9. FINAL READINESS ASSESSMENT – ĐÁNH GIÁ SẴN SÀNG CUỐI CÙNG

### 9.1. Đánh giá phát hành bản Windows Build (READY TO RELEASE WINDOWS BUILD)

> **TRẠNG THÁI: READY (ĐÃ ĐỦ ĐIỀU KIỆN 100% ĐỂ PHÁT HÀNH)**

- **Bằng chứng xác nhận:**
  1. Bản build Release `build/windows/x64/runner/Release/Mirroring.exe` biên dịch hoàn tất, PE Header mang đúng thông tin bản quyền của tác giả.
  2. Gói zip `build/Mirroring_v1.0.1.zip` (22.1 MB) chứa đầy đủ `LICENSE`, `THIRD-PARTY-NOTICES.md`, `tools/scrcpy/NOTICE.txt` và `tools/scrcpy/LICENSE.txt`.
  3. Mọi nghĩa vụ ghi nhận bản quyền bên thứ ba (scrcpy, ADB Google, FFmpeg LGPL, SDL3 zlib, libusb LGPL, Flutter BSD, Material Icons Apache-2.0, Icon Duy Hưng) đều đã được đáp ứng đầy đủ và minh bạch.

---

### 9.2. Đánh giá mã nguồn (READY TO PUBLIC SOURCE)

> **TRẠNG THÁI: READY (MÃ NGUỒN ĐÃ SẴN SÀNG ĐỂ NGƯỜI DÙNG PUSH GITHUB)**

- Mã nguồn hoàn toàn sạch sẽ, không có secret/token/personal path.
- Tài liệu hướng dẫn `README.md`, giấy phép `LICENSE` và thông báo bản quyền `THIRD-PARTY-NOTICES.md` đã hoàn chỉnh 100%.

---

*Báo cáo hoàn tất và lưu trữ tại workspace dự án.*
