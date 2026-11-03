# Mirroring

<p align="center">
  <strong>Ứng dụng Windows Desktop gọn nhẹ giúp kết nối, hiển thị và điều khiển điện thoại Android không dây qua ADB và scrcpy.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/N%E1%BB%81n%20t%E1%BA%A3ng-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white" alt="Nền tảng Windows" />
  <img src="https://img.shields.io/badge/Flutter-%3E%3D3.11.0-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/scrcpy-v5.0.1-brightgreen" alt="scrcpy" />
  <img src="https://img.shields.io/badge/ADB-v1.0.41-orange?logo=android&logoColor=white" alt="ADB" />
</p>

---

## Mục lục

- [1. Giới thiệu dự án](#1-giới-thiệu-dự-án)
- [2. Tính năng chính](#2-tính-năng-chính)
- [3. Trải nghiệm & Giao diện người dùng](#3-trải-nghiệm--giao-diện-người-dùng)
- [4. Tải xuống và cài đặt (Dành cho người dùng)](#4-tải-xuống-và-cài-đặt-dành-cho-người-dùng)
- [5. Hướng dẫn sử dụng chi tiết](#5-hướng-dẫn-sử-dụng-chi-tiết)
  - [Bước 1: Chuẩn bị thiết bị Android](#bước-1-chuẩn-bị-thiết-bị-android)
  - [Bước 2: Lấy địa chỉ IP và Cổng kết nối (Port)](#bước-2-lấy-địa-chỉ-ip-và-cổng-kết-nối-port)
  - [Bước 3: Kết nối ADB trên ứng dụng Mirroring](#bước-3-kết-nối-adb-trên-ứng-dụng-mirroring)
  - [Bước 4: Mở màn hình điện thoại](#bước-4-mở-màn-hình-điện-thoại)
  - [Bước 5: Thao tác và điều khiển điện thoại](#bước-5-thao-tác-và-điều-khiển-điện-thoại)
  - [Bước 6: Ngắt kết nối](#bước-6-ngắt-kết-nối)
- [6. Yêu cầu hệ thống](#6-yêu-cầu-hệ-thống)
- [7. Xử lý sự cố thường gặp](#7-xử-lý-sự-cố-thường-gặp)
- [8. Công nghệ sử dụng](#8-công-nghệ-sử-dụng)
- [9. Hướng dẫn phát triển (Dành cho lập trình viên)](#9-hướng-dẫn-phát-triển-dành-cho-lập-trình-viên)
- [10. Đóng gói bản phát hành Windows](#10-đóng-gói-bản-phát-hành-windows)
- [11. Cấu trúc dự án](#11-cấu-trúc-dự-án)
- [12. Đóng góp cho dự án](#12-đóng-góp-cho-dự-án)
- [13. Giấy phép](#13-giấy-phép)
- [14. Tuyên bố miễn trừ trách nhiệm & Khuyến cáo bảo mật](#14-tuyên-bố-miễn-trừ-trách-nhiệm--khuyến-cáo-bảo-mật)

---

## 1. Giới thiệu dự án

**Mirroring** là ứng dụng desktop chạy trên hệ điều hành Windows, được xây dựng nhằm phục vụ nhu cầu hiển thị và điều khiển điện thoại Android trực tiếp trên máy tính thông qua kết nối mạng không dây Wi-Fi.

Ứng dụng hướng đến sự tối giản, hiệu quả và nhẹ nhàng:
- **Người dùng văn phòng & giải trí:** Nhận thông báo, gõ tin nhắn, lướt mạng xã hội trên điện thoại bằng bàn phím và chuột máy tính mà không cần nhấc điện thoại lên hay cắm dây cáp rườm rà.
- **Lập trình viên & Kiểm thử viên (Tester):** Dễ dàng thao tác, kiểm tra ứng dụng Android trực tiếp trên máy tính với độ trễ thấp và không phụ thuộc vào các phần mềm giả lập nặng nề.

Ứng dụng kết hợp sức mạnh giao diện của **Flutter Desktop**, khả năng quản lý kết nối của **ADB (Android Debug Bridge)** và giải pháp truyền hình ảnh tốc độ cao của **scrcpy**.

---

## 2. Tính năng chính

- **Kết nối ADB không dây (Wireless Debugging):** Kết nối điện thoại và máy tính qua mạng Wi-Fi bằng địa chỉ IP và Port. Mặc định tự động nhận cổng `5555` nếu người dùng để trống.
- **Tiện ích độc lập (Portable) – Không cần cài đặt công cụ ngoài:** Ứng dụng đã nhúng sẵn bản quyền nhị phân chính thức của **ADB (v1.0.41)** và **scrcpy (v5.0.1)**. Người dùng không cần cấu hình biến môi trường PATH hay cài thêm bất kỳ phần mềm phụ trợ nào.
- **Truyền hình ảnh mượt mà, độ trễ thấp:** Tối ưu hóa phân giải Full HD (1080p) ở bitrate 8 Mbps, tận dụng giải mã phần cứng thông qua scrcpy giúp hình ảnh hiển thị sắc nét và mượt mà.
- **Điều khiển chuột và bàn phím đầy đủ:** Thao tác nhấp, vuốt, cuộn trang bằng chuột; gõ văn bản tiếng Việt/tiếng Anh vào điện thoại trực tiếp bằng bàn phím máy tính.
- **Đồng bộ bộ nhớ tạm hai chiều (Clipboard Sync):** Sao chép văn bản trên máy tính Windows và dán vào điện thoại bằng phím tắt <kbd>Ctrl</kbd> + <kbd>V</kbd>, hoặc sao chép trên điện thoại và dán lên máy tính.
- **Quản lý cửa sổ thông minh:** Khi bấm mở màn hình điện thoại, giao diện Mirroring sẽ tự động ẩn đi để nhường toàn bộ không gian cho màn hình trình chiếu. Khi đóng cửa sổ điện thoại, giao diện Mirroring sẽ tự động hiện lại.
- **Phím tắt nhanh Enter & Lối tắt Desktop:** Hỗ trợ nhấn phím <kbd>Enter</kbd> tại bất kỳ ô nhập liệu nào để kết nối ngay lập tức; tích hợp nút bấm tạo lối tắt nhanh (`Mirroring.lnk`) ra màn hình Desktop.
- **Xác thực dữ liệu & Thông báo tiếng Việt 100%:** Kiểm tra chặt chẽ định dạng IPv4, dải cổng kết nối và hiển thị hướng dẫn khắc phục hoàn toàn bằng tiếng Việt rõ ràng.

---

## 3. Trải nghiệm & Giao diện người dùng

Giao diện ứng dụng được thiết kế theo phong cách tối giản (Minimalist Dark Theme) với hai khu vực chức năng trực quan:

1. **Khung Kết nối thiết bị:**
   - Ô nhập **Địa chỉ IP** (hỗ trợ gợi ý dạng `192.168.1.10`).
   - Ô nhập **Port** (hiển thị mờ số `5555` đóng vai trò cổng mặc định, chỉ cho phép nhập số).
   - Nút **Kết nối ADB** đổi trạng thái linh hoạt (*Chưa kết nối*, *Đang kết nối...*, *Đã kết nối*, *Lỗi*).
2. **Khung Điều khiển màn hình:**
   - Hiển thị tên thiết bị Android đã kết nối kèm địa chỉ mạng.
   - Nút **Mở Màn hình** cho phép khởi chạy màn hình trình chiếu scrcpy riêng biệt.
3. **Thanh chân trang:**
   - Hiển thị thông tin phiên bản ứng dụng được nạp động từ cấu hình dự án.
   - Nút bấm tạo nhanh shortcut ra màn hình Desktop.

---

## 4. Tải xuống và cài đặt (Dành cho người dùng)

Phần này dành cho người dùng thông thường muốn sử dụng ứng dụng ngay mà không cần cài đặt môi trường lập trình.

### Bước 1: Tải bộ phát hành
1. Truy cập vào trang phát hành của dự án tại mục **[Releases](../../releases)**.
2. Tìm phiên bản mới nhất và tải tệp nén có tên dạng: `Mirroring_vX.X.X.zip` (dung lượng khoảng 22 MB).

### Bước 2: Giải nén và sử dụng
1. Nhấp chuột phải vào tệp `.zip` vừa tải về và chọn **Extract All...** (Giải nén toàn bộ) vào thư mục bạn mong muốn (ví dụ: `D:\Mirroring\`).
2. Mở thư mục đã giải nén.
3. Nhấp đúp chuột vào tệp **`Mirroring.exe`** để mở ứng dụng.
4. *(Tùy chọn)* Tại màn hình chính của ứng dụng, bấm vào dòng chữ **"Tạo shortcut Desktop"** để tạo icon ra ngoài màn hình chính cho các lần sử dụng sau.

> [!IMPORTANT]
> **Quy tắc bắt buộc khi sử dụng bản Release:**  
> **Không được sao chép riêng lẻ tệp `Mirroring.exe` ra nơi khác.**  
> Ứng dụng Flutter Desktop yêu cầu các tệp thư viện liên kết đi kèm để hoạt động, bao gồm:
> - `Mirroring.exe`: Tệp chạy chính.
> - `flutter_windows.dll`: Thư viện lõi của Flutter Engine.
> - Thư mục `data/`: Chứa mã chương trình biên dịch và tài nguyên ứng dụng.
> - Thư mục `tools/`: Chứa bộ công cụ ADB và scrcpy đã được tích hợp sẵn.  
> Luôn giữ nguyên vẹn cấu trúc thư mục sau khi giải nén.

---

## 5. Hướng dẫn sử dụng chi tiết

### Bước 1: Chuẩn bị thiết bị Android

1. Đảm bảo cả **điện thoại Android** và **máy tính Windows** đang kết nối vào **cùng một mạng Wi-Fi** (cùng lớp mạng nội bộ).
> [!IMPORTANT]
> **Cảnh báo an toàn mạng nội bộ (Luật An toàn thông tin mạng 86/2015/QH13):**  
> Phản chiếu màn hình qua ADB Wi-Fi truyền tải hình ảnh giao diện điện thoại trong mạng nội bộ (có thể chứa thông tin riêng tư, tin nhắn). Khuyến cáo người dùng chỉ bật Wireless Debugging trên mạng Wi-Fi gia đình/nội bộ đáng tin cậy, tránh dùng trên Wi-Fi công cộng.
2. **Bật Tùy chọn cho nhà phát triển (Developer Options):**
   - Trên điện thoại, vào **Cài đặt (Settings)** > **Giới thiệu về điện thoại (About Phone)** > **Thông tin phần mềm**.
   - Chạm liên tục **7 lần** vào dòng **Số hiệu bản dựng (Build Number)** cho đến khi màn hình hiển thị thông báo *"Bạn đã là nhà phát triển"*.
3. **Bật Gỡ lỗi qua Wi-Fi (Wireless Debugging):**
   - Quay lại menu **Cài đặt** > chọn **Tùy chọn cho nhà phát triển** (Developer Options).
   - Cuộn xuống nhóm thiết lập *Gỡ lỗi (Debugging)*, tìm mục **Gỡ lỗi qua Wi-Fi (Wireless Debugging)** và gạt công tắc sang **BẬT (ON)**.

---

### Bước 2: Lấy địa chỉ IP và Cổng kết nối (Port)

1. Nhấp trực tiếp vào dòng chữ **Gỡ lỗi qua Wi-Fi (Wireless Debugging)** (nhấp vào chữ, không chỉ gạt công tắc) để mở trang thông tin cấu hình chi tiết.
2. Tìm đến mục có tên **Địa chỉ IP và cổng (IP address & port)**.
3. Bạn sẽ thấy một dãy số có dạng: `Địa_chỉ_IP:Cổng_kết_nối`.

**Ví dụ minh họa:**
Nếu màn hình điện thoại hiển thị dòng chữ: `192.168.1.100:43257`

Bạn phân tách dữ liệu thành 2 giá trị riêng biệt:
- **Địa chỉ IP:** `192.168.1.100` (dãy số nằm phía trước dấu hai chấm).
- **Cổng kết nối (Port):** `43257` (dãy số nằm phía sau dấu hai chấm).

> [!WARNING]
> **Lưu ý kỹ thuật quan trọng về Cổng kết nối (Port):**
> - **Chỉ nhập Cổng kết nối chính (Connection Port):** Nhập đúng số cổng hiển thị ngay tại mục *Địa chỉ IP và cổng*.
> - **KHÔNG dùng Cổng ghép nối (Pairing Port):** Trong trang Gỡ lỗi qua Wi-Fi thường có thêm nút *"Ghép nối thiết bị bằng mã ghép nối" (Pair device with pairing code)*, khi bấm vào đó Android sẽ sinh ra một cổng pairing và mã PIN 6 số khác. Ứng dụng Mirroring sử dụng phương thức kết nối trực tiếp `adb connect`, do đó **không nhập cổng pairing vào ứng dụng**.
> - **Cổng có thể thay đổi:** Hệ điều hành Android sẽ sinh ra một số cổng ngẫu nhiên mới mỗi lần bạn tắt/bật lại Wi-Fi hoặc tắt/bật tính năng Wireless Debugging. Hãy luôn nhìn vào màn hình điện thoại để lấy số cổng hiện tại.

---

### Bước 3: Kết nối ADB trên ứng dụng Mirroring

1. Mở ứng dụng **Mirroring** trên Windows.
2. Tại ô **Địa chỉ IP**, nhập địa chỉ IP lấy từ điện thoại (ví dụ: `192.168.1.100`).
3. Tại ô **Port**, nhập cổng kết nối (ví dụ: `43257`). Nếu điện thoại của bạn sử dụng cổng cố định mặc định 5555, bạn có thể để trống ô này.
4. Bấm nút **Kết nối ADB** hoặc nhấn phím <kbd>Enter</kbd> trên bàn phím.
5. **Ủy quyền trên điện thoại (ở lần kết nối đầu tiên):**
   - Trên màn hình điện thoại sẽ hiện một hộp thoại thông báo: *"Cho phép gỡ lỗi không dây trên mạng này?" (Allow Wireless Debugging on this network?)*.
   - Bạn tích chọn vào mục **"Luôn cho phép từ mạng này"** và nhấn **Cho phép (Allow)**.
6. **Nhận biết trạng thái:**
   - Thẻ trạng thái chuyển sang màu xanh lá cây với nhãn **Đã kết nối**.
   - Tên thiết bị của bạn (ví dụ: `Samsung Galaxy M31`) sẽ hiển thị ngay bên dưới.

---

### Bước 4: Mở màn hình điện thoại

1. Sau khi kết nối thành công, tại ô **ĐIỀU KHIỂN MÀN HÌNH**, nút **Mở Màn hình** sẽ chuyển sang màu xanh ngọc sẵn sàng.
2. Bấm vào nút **Mở Màn hình**.
3. Cửa sổ trình chiếu scrcpy sẽ xuất hiện với tiêu đề dạng `Mirroring - [IP]:[Port]`, hiển thị toàn bộ màn hình điện thoại theo thời gian thực.
4. Cửa sổ ứng dụng Mirroring sẽ tự động ẩn đi để bàn làm việc của bạn gọn gàng nhất.

---

### Bước 5: Thao tác và điều khiển điện thoại

Bạn có thể tương tác trực tiếp với điện thoại thông qua chuột và bàn phím máy tính:

| Thao tác | Phím / Chuột | Tác dụng trên điện thoại |
| :--- | :--- | :--- |
| **Chạm / Mở ứng dụng** | Nhấp chuột trái | Tương đương thao tác chạm ngón tay |
| **Cuộn danh sách / Lướt web** | Cuộn con lăn chuột hoặc giữ chuột trái kéo | Cuộn màn hình mượt mà |
| **Quay lại (Phím Back)** | Nhấp chuột phải | Quay lại màn hình hoặc đóng bàn phím ảo |
| **Về màn hình chính (Home)** | Nhấp chuột giữa (con lăn) | Trở về màn hình chính Android |
| **Nhập văn bản** | Bàn phím máy tính | Gõ chữ trực tiếp vào các ô nhập liệu, tìm kiếm, tin nhắn |
| **Sao chép & Dán (Clipboard)** | <kbd>Ctrl</kbd> + <kbd>C</kbd> / <kbd>Ctrl</kbd> + <kbd>V</kbd> | Tự động đồng bộ bộ nhớ tạm hai chiều giữa Windows và Android |
| **Mở lại cửa sổ điều khiển** | Đóng cửa sổ màn hình | Giao diện điều khiển Mirroring sẽ tự động hiện lại |

---

### Bước 6: Ngắt kết nối

Khi không còn nhu cầu điều khiển:
1. Đóng cửa sổ màn hình trình chiếu điện thoại.
2. Cửa sổ ứng dụng Mirroring sẽ tự động hiện lại trên màn hình máy tính.
3. Nhấp vào nút **Ngắt kết nối** (nút màu đỏ). Ứng dụng sẽ tự động giải phóng tiến trình scrcpy và ngắt phiên làm việc ADB một cách an toàn.

---

## 6. Yêu cầu hệ thống

### Máy tính Windows (Host PC)
- **Hệ điều hành:** Windows 10 hoặc Windows 11 (phiên bản 64-bit).
- **Kết nối mạng:** Kết nối mạng Wi-Fi hoặc mạng dây LAN chung mạng nội bộ với điện thoại.
- **Phần cứng:** Cấu hình văn phòng cơ bản, card đồ họa hỗ trợ DirectX/OpenGL để giải mã luồng video mượt mà.

### Điện thoại Android (Target Device)
- **Phiên bản hệ điều hành:** Android 11 trở lên được khuyến nghị để sử dụng tính năng Gỡ lỗi qua Wi-Fi độc lập mà không cần cắm cáp lần đầu.
  *(Các phiên bản Android cũ hơn từ 5.0 đến 10 có thể dùng qua lệnh `adb tcpip 5555` bằng cáp USB trong lần đầu).*
- **Cài đặt:** Phải bật được mục *Tùy chọn cho nhà phát triển* và tính năng *Gỡ lỗi qua Wi-Fi*.

---

## 7. Xử lý sự cố thường gặp

### Sự cố 1: Thông báo "Vui lòng nhập địa chỉ IP của điện thoại"
- **Biểu hiện:** Bấm Kết nối nhưng ô IP bị báo lỗi đỏ.
- **Nguyên nhân:** Ô nhập IP đang bị để trống.
- **Cách xử lý:** Mở trang Gỡ lỗi qua Wi-Fi trên điện thoại, xem lại địa chỉ IP và điền vào ô.

### Sự cố 2: Thông báo "Địa chỉ IP không đúng định dạng IPv4"
- **Biểu hiện:** Ứng dụng báo lỗi định dạng ngay sau khi bấm kết nối.
- **Nguyên nhân:** Nhập nhầm ký tự chữ, hoặc dán nhầm cả dấu hai chấm kèm port vào ô IP (ví dụ dán `192.168.1.10:43257` vào ô IP).
- **Cách xử lý:** Chỉ nhập địa chỉ IP gồm 4 cụm số ngăn cách bởi dấu chấm (ví dụ: `192.168.1.10`) vào ô IP, còn số cổng nhập riêng vào ô Port.

### Sự cố 3: Lỗi "Kết nối bị từ chối" (Connection Refused)
- **Biểu hiện:** Trạng thái chuyển sang màu đỏ báo kết nối bị từ chối.
- **Nguyên nhân:** 
  1. Tính năng Gỡ lỗi qua Wi-Fi trên điện thoại đang bị TẮT hoặc vừa bị hệ điều hành tự động ngắt.
  2. Số Port trên điện thoại đã bị thay đổi sang số khác nhưng trên máy tính vẫn nhập số cũ.
- **Cách xử lý:** Mở lại trang Gỡ lỗi qua Wi-Fi trên điện thoại, kiểm tra chắc chắn công tắc đang BẬT, nhìn lại số port mới nhất và nhập lại vào máy tính.

### Sự cố 4: Lỗi "Hết thời gian chờ kết nối" (Timeout)
- **Biểu hiện:** Ứng dụng xoay vòng kết nối khoảng 8 giây rồi báo lỗi Timeout.
- **Nguyên nhân:** Máy tính và điện thoại không thể nhìn thấy nhau trong mạng (khác mạng Wi-Fi, hoặc router Wi-Fi bật tính năng cách ly mạng *AP Isolation / Client Isolation*).
- **Cách xử lý:**
  1. Kiểm tra lại xem điện thoại có đang dùng 4G/5G thay vì Wi-Fi không.
  2. Đảm bảo cả hai máy cùng bắt vào một bộ phát Wi-Fi.
  3. Tắt tạm tường lửa (Firewall) hoặc kiểm tra cấu hình mạng nội bộ trên router.

### Sự cố 5: Lỗi "Thiết bị chưa được cấp quyền" (Unauthorized)
- **Biểu hiện:** Ứng dụng báo thiết bị chưa được ủy quyền.
- **Nguyên nhân:** Bạn chưa bấm chấp nhận hộp thoại xác thực khóa RSA trên màn hình điện thoại.
- **Cách xử lý:** Mở sáng màn hình điện thoại, tìm hộp thoại xác nhận và bấm nút **Cho phép (Allow)**.

### Sự cố 6: Cửa sổ màn hình mở lên rồi tắt ngay lập tức
- **Biểu hiện:** Bấm Mở màn hình, cửa sổ scrcpy nháy lên rồi biến mất.
- **Nguyên nhân:** Luồng video bị gián đoạn do tín hiệu Wi-Fi yếu hoặc phiên kết nối ADB bị ngắt bất ngờ.
- **Cách xử lý:** Bấm nút **Ngắt kết nối** trên ứng dụng, sau đó thực hiện kết nối lại từ đầu.

---

## 8. Công nghệ sử dụng

Dự án sử dụng các công nghệ tiêu chuẩn nhằm đảm bảo hiệu năng và độ ổn định cao:

- **[Flutter Desktop (Windows)](https://flutter.dev/):** Xây dựng giao diện ứng dụng mượt mà, tiêu tốn ít tài nguyên (chỉ khoảng ~100 MB RAM).
- **[Dart & FFI (Foreign Function Interface)](https://dart.dev/):** Tương tác trực tiếp với Windows API (`user32.dll`) để điều khiển trạng thái ẩn/hiện và phục hồi tiêu điểm cửa sổ mượt mà.
- **[ADB (Android Debug Bridge)](https://developer.android.com/tools/adb):** Quản lý kết nối mạng không dây, kiểm tra thông tin định danh và trạng thái thiết bị Android.
- **[scrcpy](https://github.com/Genymobile/scrcpy):** Đảm nhiệm truyền luồng hình ảnh màn hình qua giao thức H.264/H.265 thời gian thực, điều hướng sự kiện chuột, bàn phím và đồng bộ clipboard.

---

## 9. Hướng dẫn phát triển (Dành cho lập trình viên)

Dành cho các lập trình viên muốn chạy mã nguồn từ môi trường phát triển, sửa đổi hoặc đóng góp tính năng mới.

### Yêu cầu môi trường
- **Flutter SDK:** Phiên bản `>= 3.11.0` (Đã kiểm thử hoạt động ổn định trên Flutter 3.47 / Dart 3.13).
- **Visual Studio 2022:** Đã cài đặt gói công việc *"Desktop development with C++"* (Bao gồm MSVC v143 và Windows 10/11 SDK).
- **Git**.

### Các bước cài đặt và chạy ứng dụng

1. **Sao chép mã nguồn:**
   ```bash
   git clone https://github.com/chuonghoai/Mirroring.git
   cd Mirroring
   ```

2. **Cài đặt các gói phụ thuộc (Dependencies):**
   ```bash
   flutter pub get
   ```

3. **Kiểm tra môi trường:**
   ```bash
   flutter doctor
   ```

4. **Chạy ứng dụng ở chế độ Debug trên Windows:**
   ```bash
   flutter run -d windows
   ```

5. **Chạy bộ kiểm thử tự động (Unit & Integration Tests):**
   Dự án đã tích hợp sẵn 18 bài kiểm thử tự động kiểm tra định dạng IP/Port, phân tích phản hồi ADB và xác thực giao diện:
   ```bash
   flutter test
   flutter analyze
   ```

---

## 10. Đóng gói bản phát hành Windows

Để biên dịch bản Release tối ưu hóa cho người dùng cuối:

```bash
flutter build windows --release
```

Sau khi biên dịch hoàn tất, thư mục thành phẩm nằm tại:
```
build\windows\x64\runner\Release\
```

Thư mục thành phẩm bao gồm:
```
Release/
├── Mirroring.exe           # Tệp thực thi chính của ứng dụng
├── flutter_windows.dll     # Lõi Flutter Windows Engine
├── LICENSE                 # Giấy phép MIT của ứng dụng Mirroring
├── THIRD-PARTY-NOTICES.md  # Bảng thông báo bản quyền đầy đủ của các bên thứ ba
├── data/                   # Tài nguyên đồ họa và mã nhị phân ứng dụng (app.so)
└── tools/scrcpy/           # Bộ công cụ ADB và scrcpy đã được CMake tự động sao chép
```

### Đóng gói thành tệp ZIP phân phối
Bạn có thể dùng PowerShell để nén toàn bộ thư mục Release thành một tệp ZIP hoàn chỉnh duy nhất:

```powershell
Compress-Archive -Path "build\windows\x64\runner\Release\*" -DestinationPath "build\Mirroring_v1.0.1.zip" -Force
```

---

## 11. Cấu trúc dự án

Cấu trúc các thư mục quan trọng trong dự án:

```
Mirroring/
├── LICENSE                          # Giấy phép chính thức của dự án (MIT License)
├── THIRD-PARTY-NOTICES.md           # Bảng thông báo bản quyền & giấy phép các bên thứ ba
├── assets/                          # Tài nguyên tĩnh (app logo)
├── lib/
│   ├── core/
│   │   ├── models/                  # Các lớp dữ liệu: AdbDevice, ToolInfo, MirroringAppState
│   │   └── services/                # Các dịch vụ xử lý nền:
│   │                                # - adb_service.dart (Quản lý tiến trình kết nối ADB)
│   │                                # - scrcpy_service.dart (Khởi chạy và giám sát scrcpy)
│   │                                # - tool_locator_service.dart (Tự động định vị công cụ portable)
│   │                                # - window_service.dart (Điều khiển ẩn/hiện cửa sổ qua Windows FFI)
│   │                                # - shortcut_service.dart (Tạo shortcut Desktop)
│   ├── ui/
│   │   ├── controllers/             # Quản lý trạng thái và luồng nghiệp vụ (MirroringController)
│   │   └── screens/                 # Giao diện người dùng (HomeScreen)
│   └── main.dart                    # Điểm khởi chạy ứng dụng
├── test/                            # Toàn bộ bài kiểm thử tự động (18 test cases)
├── tools/
│   └── scrcpy/                      # Bộ công cụ nhúng sẵn ADB v1.0.41, scrcpy v5.0.1, SDL3, FFmpeg DLLs
│       ├── LICENSE.txt              # Giấy phép gốc của scrcpy (Apache-2.0)
│       └── NOTICE.txt               # Thông báo nội dung chỉnh sửa icon theo Điều 4(b) Apache-2.0
├── windows/
│   ├── runner/                      # Mã nguồn C++ khởi tạo cửa sổ Win32 và cấu hình biểu tượng
│   └── CMakeLists.txt               # Kịch bản build CMake (tự động sao chép thư mục tools vào Release)
└── pubspec.yaml                     # Cấu hình dự án, phiên bản và các gói phụ thuộc
```

---

## 12. Đóng góp cho dự án

Mọi đóng góp, báo cáo lỗi và đề xuất tính năng mới đều rất được hoan nghênh:

1. **Báo lỗi:** Nếu gặp bất kỳ lỗi nào trong quá trình kết nối hoặc điều khiển, vui lòng mở một phiếu phản hồi tại mục **[Issues](../../issues)** với mô tả chi tiết lỗi và dòng thông báo hiển thị trên màn hình.
2. **Đề xuất tính năng:** Mở một Issue với nhãn `enhancement` để thảo luận về ý tưởng của bạn.
3. **Đóng góp mã nguồn (Pull Request):**
   - Fork repository về tài khoản cá nhân của bạn.
   - Tạo nhánh tính năng mới (`git checkout -b feature/tinh-nang-moi`).
   - Viết mã và đảm bảo toàn bộ kiểm thử đều vượt qua (`flutter test` và `flutter analyze`).
   - Tạo Pull Request kèm giải thích chi tiết về thay đổi của bạn.

---

## 13. Giấy phép

Mã nguồn của dự án **Mirroring** được phát hành theo giấy phép **[MIT License](LICENSE)**. Bản quyền © 2026 thuộc về tác giả Trương Hoài Chương (chuonghoai).

### Các thành phần bên thứ ba được tích hợp sẵn
- **scrcpy:** Bản quyền thuộc về Genymobile, Romain Vimont. Phát hành theo giấy phép [Apache License 2.0](https://github.com/Genymobile/scrcpy/blob/master/LICENSE). Biểu tượng icon đã được thay đổi để đồng bộ với ứng dụng Mirroring theo Điều 4(b) Apache-2.0 (chi tiết tại `tools/scrcpy/NOTICE.txt`).
- **ADB (Android Platform-Tools):** Được phát triển bởi Google trong khuôn khổ Dự án Mã nguồn mở Android (AOSP). Mã nguồn gốc phát hành theo [Apache License 2.0](https://source.android.com/setup/start/licenses).
- **FFmpeg & libusb:** Phát hành theo giấy phép [LGPL v2.1 or later](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).
- **SDL3:** Phát hành theo giấy phép [zlib License](https://www.libsdl.org/license.php).
- **Biểu tượng ứng dụng (App Icon):** Tác phẩm thiết kế của tác giả [Duy Hưng (duyhungpham94)](https://www.pinterest.com/duyhungpham94/), nguồn gốc tác phẩm tại [Pinterest](https://www.pinterest.com/pin/958211258215792168/). Được sử dụng cho mục đích nhận diện phi thương mại của dự án.

*Để xem toàn văn giấy phép và thông tin ghi nhận bản quyền chi tiết của tất cả các thư viện, vui lòng tham khảo tệp **[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)**.*

---

## 14. Tuyên bố miễn trừ trách nhiệm & Khuyến cáo bảo mật

### 14.1. Miễn trừ trách nhiệm bảo hành & rủi ro kỹ thuật
Ứng dụng **Mirroring** được cung cấp theo nguyên tắc "AS IS" (nguyên trạng), hoàn toàn miễn phí theo giấy phép MIT. Tác giả không chịu trách nhiệm đối với bất kỳ rủi ro, tổn thất dữ liệu, hư hỏng thiết bị hay gián đoạn dịch vụ nào phát sinh từ việc sử dụng ứng dụng hoặc các công cụ bên thứ ba đi kèm (ADB, scrcpy).

### 14.2. Khuyến cáo an toàn khi sử dụng Wireless Debugging (Cảnh báo an toàn mạng nội bộ)
- **Bảo mật mạng Wi-Fi & Quyền riêng tư (Luật An toàn thông tin mạng 86/2015/QH13):** Phản chiếu màn hình qua ADB Wi-Fi truyền tải hình ảnh giao diện điện thoại (có thể chứa thông tin riêng tư, tin nhắn). Khuyến cáo người dùng chỉ bật Wireless Debugging trên mạng Wi-Fi gia đình/nội bộ đáng tin cậy, tránh dùng trên Wi-Fi công cộng để phòng ngừa các thiết bị lạ trong cùng mạng dò quét và bảo vệ an toàn thông tin cá nhân.
- **Xác nhận khóa RSA:** Luôn kiểm tra kỹ hộp thoại xác thực khóa RSA xuất hiện trên màn hình điện thoại trước khi bấm "Cho phép". Chỉ cho phép khi chính bạn vừa bấm nút kết nối từ máy tính của mình.
- **Tắt khi không sử dụng:** Sau khi hoàn thành phiên làm việc, bạn nên tắt tính năng Wireless Debugging trong menu Tùy chọn nhà phát triển (Developer Options) trên điện thoại để tiết kiệm pin và đảm bảo an toàn tối đa.
