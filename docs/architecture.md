# Mirroring Technical Architecture

## 1. Overview

Mirroring is a monorepo containing two independent Flutter applications and one shared pure-Dart protocol package:

- **`apps/mirroring_windows`**: Windows desktop host application (Flutter Desktop + Win32 C++ runner with Windows Media Foundation H.264 hardware/MFT decoding).
- **`apps/mirroring_mobile`**: Android Companion application (Flutter UI + Kotlin Native Foreground Service, `MediaProjection`, hardware `MediaCodec` H.264 encoder, RFC 6455 WebSocket control server, and authenticated TCP stream server).
- **`packages/mirroring_protocol`**: Shared protocol constants, beacon/control schemas, binary stream frame header/parser, and token security utilities.

Normal operation runs **entirely over the local area network (LAN / Wi-Fi)** without USB cables, ADB, Wireless Debugging, Developer Options, or external servers.

---

## 2. LAN Discovery Protocol

- **Transport**: UDP broadcast on port `45454` (`255.255.255.255` + directed IPv4 subnet broadcast addresses).
- **Beacon Interval**: Every `2 seconds`.
- **Offline Pruning Timeout**: `7 seconds` without a valid beacon.
- **Android Wi-Fi Support**: `LanDiscoveryManager.kt` acquires a non-reference-counted `WifiManager.MulticastLock` while active so UDP discovery packets are delivered reliably on Android devices.
- **Beacon Payload (`MIRRORING_LAN_V1`)**:
  ```json
  {
    "magic": "MIRRORING_LAN_V1",
    "protocolVersion": 1,
    "deviceId": "android_a1b2c3d4...",
    "deviceName": "Pixel 8",
    "deviceType": "androidCompanion",
    "controlPort": 45455,
    "availability": "available",
    "timestampMs": 1700000000000
  }
  ```
- **Privacy & Deduplication**:
  - Only app-generated random `deviceId`, sanitized device display name, device type, listening control port, and availability are broadcast. No phone numbers, accounts, IMEI, or MAC addresses are transmitted.
  - Peers are keyed by `deviceId`, preventing duplicate entries and updating IP addresses dynamically if DHCP renews an address.
  - Non-matching packets (wrong magic, unsupported `protocolVersion`, invalid `deviceId`, or invalid ports) are silently discarded.

---

## 3. Control Channel & Session Security

- **Transport**: Direct WebSocket (`ws://<android-ip>:<controlPort>`) hosted by `ControlWebSocketServer.kt` inside the Android process.
- **Security Flow**:
  1. **Explicit Approval**: Windows sends `pairRequest` (`requestId`, `windowsDeviceId`, `windowsDeviceName`, `nonce`, `timestampMs`). Android displays an interactive approval card with a **30-second expiration timer**. No screen capture starts prior to explicit user approval.
  2. **MediaProjection Consent**: After the user taps **Accept**, Android requests the OS-level `MediaProjection` permission dialog (`MediaProjectionManager.createScreenCaptureIntent()`).
  3. **Foreground Service & Token Issuance**: Once granted, `MirroringForegroundService` starts immediately (`startForeground` with `FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`), generates a cryptographically random 256-bit `sessionToken` (`SecureRandom`, URL-safe Base64), and sends `pairResponse(accepted: true, sessionToken, streamPort)`.
  4. **Authenticated Control & Stream**: Every subsequent `sessionStart`, `heartbeat`, `clipboardPush`, `sessionStop`, and the TCP video socket handshake must present the active `sessionToken` (verified via constant-time `MessageDigest.isEqual`). Unauthorized clients are rejected and closed immediately.

---

## 4. Video Streaming Pipeline

### Why Custom H.264 over LAN TCP + Native Decoders?
We evaluated WebRTC (`flutter_webrtc`) against a direct hardware-accelerated H.264 pipeline (`MediaProjection` + `MediaCodec` -> TCP `MRV1` framing -> Windows Media Foundation `CLSID_CMSH264DecoderMFT` + Flutter `Texture`):

| Criterion | WebRTC Plugin | Direct H.264 + Media Foundation (Chosen) |
| :--- | :--- | :--- |
| **Background Survival** | Tied to Flutter Activity / Dart isolate; swiping app from Recents destroys `FlutterEngine` and kills WebRTC | Capture, encoding, WebSocket control, and TCP streaming run 100% in Kotlin Native `MirroringForegroundService` (`stopWithTask="false"`) |
| **LAN-Only Operation** | Requires ICE/SDP negotiation & large native binary | Direct LAN socket with 24-byte `MRV1` framing; zero ICE/STUN overhead |
| **Hardware Acceleration** | Varies by plugin build | Android `MediaCodec` `COLOR_FormatSurface` GPU input + Windows Media Foundation `CODECAPI_AVLowLatencyMode` |
| **Dependencies & Footprint** | Heavy external native binaries | Uses built-in Android MediaCodec and built-in Windows 10/11 Media Foundation SDK |

### Binary Frame Format (`MRV1`, 24 bytes Big-Endian)
- Bytes `0..3`: Magic `0x4D525631` (`"MRV1"`)
- Byte `4`: `frameType` (`0 = SPS/PPS Config`, `1 = IDR Keyframe`, `2 = P-Frame`, `3 = Metadata`)
- Byte `5`: `rotationQuarterTurns` (`0..3`)
- Bytes `6..7`: `width` (`uint16`)
- Bytes `8..9`: `height` (`uint16`)
- Bytes `10..11`: reserved (`0`)
- Bytes `12..19`: `timestampUs` (`uint64`)
- Bytes `20..23`: `payloadLength` (`uint32`, capped at 16 MiB)
- Followed by `payloadLength` bytes of H.264 Annex-B NAL units (`00 00 00 01` start codes). SPS+PPS is cached and prepended before every IDR keyframe so decoding recovers immediately on reconnect or orientation changes.

---

## 5. Android Foreground Service & OS Limitations

### Background Continuity
- `MirroringForegroundService` is registered with `android:foregroundServiceType="mediaProjection"` and `android:stopWithTask="false"`.
- On Android 14+ (API 34+), `startForeground(..., FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)` is invoked inside `onStartCommand` **before** calling `mediaProjectionManager.getMediaProjection(resultCode, data)`.
- An ongoing, non-dismissible notification (`Mirroring — Màn hình đang được chia sẻ với <WindowsName>`) with a **Dừng chia sẻ** action remains visible throughout the active session.
- Because `ControlWebSocketServer`, `H264StreamServer`, `ScreenCaptureEncoder`, and the heartbeat supervisor live in Kotlin Native (`MirroringSessionCoordinator` + `MirroringForegroundService`), pressing **Home**, switching apps, or **swiping Mirroring away from Recent Apps** does **not** terminate mirroring.

### Session Termination & Unexpected Disconnection
- **Normal Close**: Closing the Windows app triggers `WM_CLOSE` deferral (`com.chuonghoai.mirroring/window_lifecycle`), sends authenticated `sessionStop`, waits up to 600ms, and exits. Android immediately stops `ScreenCaptureEncoder`, `H264StreamServer`, `MediaProjection`, stops the foreground service, and removes the notification.
- **Unexpected Loss**: Windows sends heartbeats every 2s. If Android detects no heartbeat/control traffic for `8s` or loses the socket without `sessionStop`, it enters `RECONNECTING` for `20s` (updating the notification). If Windows does not reconnect with the valid `sessionToken` within `20s`, Android terminates the session and releases all resources to save battery.

### Honest Android Platform Limitations
1. **MediaProjection Permission Reuse**: Android forbids persisting or silently reusing `MediaProjection` tokens across separate user sessions (and Android 14+ enforces single-use grants per consent dialog). Each new mirroring session requires user confirmation.
2. **Force Stop & Reboot**: If the user performs **Force Stop** in Android System Settings or reboots the phone, Android kills all services immediately. Mirroring does not attempt to circumvent Force Stop.
3. **OEM Battery Optimizers**: Some aggressive OEM ROMs (MIUI/HyperOS, ColorOS, OneUI power saving) may terminate background services if battery restrictions are set to "Restricted". Setting Battery usage to "Unrestricted" or "Optimized" may be needed on those devices.
4. **Remote Touch/Keyboard Input via AccessibilityService (LAN Mode)**: `MediaProjection` only captures display output. To provide full mouse/touch/scroll/Back/Home/Recents and text input over LAN **without ADB**, Mirroring v2.0.0 includes an explicit, user-enabled Android `AccessibilityService` (`MirroringAccessibilityService` / *"Mirroring Remote Control"*), using `dispatchGesture()`, `performGlobalAction()`, and `ACTION_SET_TEXT` exclusively during active authenticated sessions. Users who prefer ADB-based input without enabling Accessibility can still use the preserved **ADB & scrcpy** tab.
