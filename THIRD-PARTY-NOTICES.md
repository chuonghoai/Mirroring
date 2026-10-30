# Thông báo Bản quyền Bên Thứ Ba (Third-Party Notices)

Dự án **Mirroring** sử dụng hoặc phân phối kèm một số thư viện, thành phần mã nguồn mở và tệp nhị phân bên thứ ba. Tài liệu này cung cấp thông tin ghi nhận bản quyền và giấy phép tương ứng của từng thành phần theo quy định của các giấy phép mã nguồn mở liên quan.

---

## Mục lục

1. [scrcpy & scrcpy-server (Apache-2.0)](#1-scrcpy--scrcpy-server)
2. [Android Debug Bridge - ADB (Apache-2.0 / Google EULA)](#2-android-debug-bridge---adb)
3. [FFmpeg (LGPL v2.1 or later)](#3-ffmpeg-libraries)
4. [Simple DirectMedia Layer - SDL3 (zlib License)](#4-simple-directmedia-layer---sdl3)
5. [libusb (LGPL v2.1 or later)](#5-libusb)
6. [Flutter Engine & Framework (BSD-3-Clause)](#6-flutter-engine--framework)
7. [Thư viện ICU Data (ICU License / Unicode-TOU)](#7-icu-data-library)
8. [Phông chữ Material Icons (Apache-2.0)](#8-material-icons-font)
9. [Các gói Dart Packages (BSD-3-Clause, MIT, Apache-2.0)](#9-các-gói-dart-packages)
10. [Biểu tượng ứng dụng - App Icon (Duy Hưng)](#10-biểu-tượng-ứng-dụng---app-icon)

---

## 1. scrcpy & scrcpy-server

- **Tác giả:** Genymobile, Romain Vimont
- **Trang chủ:** https://github.com/Genymobile/scrcpy
- **Giấy phép:** Apache License 2.0 (Toàn văn tại `tools/scrcpy/LICENSE.txt`)

### Thông báo sửa đổi tệp theo Điều 4(b) Apache License 2.0:
Trong gói phân phối của dự án Mirroring:
- Tệp hình ảnh `tools/scrcpy/scrcpy.png` đã được thay thế bằng biểu tượng của ứng dụng Mirroring.
- Tài nguyên biểu tượng nhị phân (PE Resource Icon) bên trong tệp `tools/scrcpy/scrcpy.exe` đã được cập nhật bằng biểu tượng của ứng dụng Mirroring nhằm mục đích đồng bộ hiển thị nhận diện.
- Toàn bộ các mã lệnh thực thi, logic xử lý và tệp `scrcpy-server` đều được giữ nguyên gốc từ bản phát hành chính thức v5.0.1 của tác giả.

---

## 2. Android Debug Bridge - ADB

- **Thành phần:** `adb.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll` (v1.0.41 / SDK 37.0.1)
- **Bản quyền mã nguồn gốc:** Copyright (C) Android Open Source Project (AOSP), Google LLC.
- **Trang chủ:** https://source.android.com / https://developer.android.com/tools/adb
- **Giấy phép mã nguồn:** Apache License 2.0 (https://source.android.com/setup/start/licenses)
- **Ghi chú phân phối:** Các tệp nhị phân được trích xuất từ gói Android SDK Platform-Tools chính thức của Google nhằm mục đích hỗ trợ kết nối không dây với thiết bị Android.

---

## 3. FFmpeg Libraries

- **Thành phần:** `avcodec-63.dll`, `avformat-63.dll`, `avutil-61.dll`, `swresample-7.dll` (v9.0.2)
- **Tác giả:** Fabrice Bellard và các cộng tác viên dự án FFmpeg.
- **Trang chủ:** https://ffmpeg.org
- **Giấy phép:** GNU Lesser General Public License (LGPL) version 2.1 or later.
- **Tuân thủ LGPL v2.1:** Các thư viện FFmpeg được liên kết động dưới dạng các tệp DLL độc lập và không làm thay đổi tính chất giấy phép của ứng dụng Mirroring. Bạn có thể tải mã nguồn hoàn chỉnh của FFmpeg trực tiếp từ trang chủ https://ffmpeg.org.

---

## 4. Simple DirectMedia Layer - SDL3

- **Thành phần:** `SDL3.dll` (v3.4.18)
- **Tác giả:** Sam Lantinga và các cộng tác viên SDL.
- **Trang chủ:** https://www.libsdl.org
- **Giấy phép:** zlib License:
  > This software is provided 'as-is', without any express or implied warranty. In no event will the authors be held liable for any damages arising from the use of this software.
  > Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
  > 1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.
  > 2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
  > 3. This notice may not be removed or altered from any source distribution.

---

## 5. libusb

- **Thành phần:** `libusb-1.0.dll` (v1.0.30)
- **Tác giả:** Các cộng tác viên dự án libusb.
- **Trang chủ:** https://libusb.info
- **Giấy phép:** GNU Lesser General Public License (LGPL) version 2.1 or later.
- **Mã nguồn:** Bạn có thể tải mã nguồn của libusb tại https://github.com/libusb/libusb.

---

## 6. Flutter Engine & Framework

- **Thành phần:** `flutter_windows.dll` và khung ứng dụng Flutter.
- **Bản quyền:** Copyright 2014 The Flutter Authors. All rights reserved.
- **Giấy phép:** BSD 3-Clause License:
  > Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
  > * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  > * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
  > * Neither the name of Google Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

---

## 7. ICU Data Library

- **Thành phần:** `icudtl.dat`
- **Bản quyền:** Copyright (c) 1995-2023 International Business Machines Corporation and others. All rights reserved.
- **Giấy phép:** ICU License / Unicode Terms of Use (Permissive). Toàn văn thông báo được đóng gói trong tệp `data/flutter_assets/NOTICES.Z`.

---

## 8. Các phông chữ biểu tượng (Icon Fonts) & Phông chữ hệ thống

Dự án chỉ sử dụng 2 bộ phông chữ biểu tượng mã nguồn mở đi kèm framework Flutter:
- **`MaterialIcons-Regular.otf`**: Bản quyền Google LLC. Giấy phép Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0.txt).
- **`CupertinoIcons.ttf`**: Bản quyền Flutter Authors. Giấy phép MIT License (đi kèm gói `cupertino_icons`).

*Lưu ý về phông chữ hiển thị văn bản (Typography):* Ứng dụng chỉ định sử dụng phông chữ hệ thống có sẵn của Windows (`'Segoe UI'`), **hoàn toàn không đóng gói (bundle) hay phân phối bất kỳ tệp phông chữ `.ttf` / `.otf` thương mại nào**, đảm bảo an toàn pháp lý 100% về vấn đề bản quyền phông chữ.

---

## 9. Các gói Dart Packages

Các gói phụ thuộc được khai báo trong `pubspec.yaml` và `pubspec.lock` bao gồm:
- **`ffi`**: Copyright (c) 2019, the Dart project authors. (BSD-3-Clause)
- **`cupertino_icons`**: Copyright (c) 2016, Flutter authors. (MIT License)
- **Các thư viện phụ trợ khác**: `characters`, `collection`, `material_color_utilities`, `meta`, `vector_math` đều được cấp phép theo BSD-3-Clause hoặc Apache-2.0.

Toàn văn giấy phép của tất cả các gói Dart trên được Flutter tự động biên soạn và lưu trữ trong tệp nén `data/flutter_assets/NOTICES.Z` đi kèm bản build Release.

---

## 10. Biểu tượng ứng dụng - App Icon

- **Thành phần:** `assets/app_icon.jpg`, `windows/runner/resources/app_icon.ico`, `tools/scrcpy/scrcpy.png`
- **Tác giả thiết kế:** Duy Hưng (duyhungpham94)
- **Hồ sơ tác giả:** https://www.pinterest.com/duyhungpham94/
- **Nguồn tác phẩm gốc:** https://www.pinterest.com/pin/958211258215792168/
- **Mục đích sử dụng:** Được sử dụng làm biểu tượng nhận diện phi thương mại cho ứng dụng mã nguồn mở Mirroring. Mọi quyền tác giả đối với hình ảnh thiết kế gốc thuộc về tác giả Duy Hưng.


