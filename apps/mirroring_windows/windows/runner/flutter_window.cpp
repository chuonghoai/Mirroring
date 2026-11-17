#include "flutter_window.h"

#include <algorithm>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size_needed =
      MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (size_needed <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size_needed - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), size_needed);
  return out;
}

int ReadIntArg(const flutter::EncodableMap* args, const char* key,
               int fallback) {
  if (!args) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return static_cast<int>(std::get<int64_t>(it->second));
  }
  return fallback;
}

std::string ReadStringArg(const flutter::EncodableMap* args, const char* key,
                          const std::string& fallback) {
  if (!args) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  if (std::holds_alternative<std::string>(it->second)) {
    return std::get<std::string>(it->second);
  }
  return fallback;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupNativeChannels();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupNativeChannels() {
  auto raw_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("MirroringRunner");
  plugin_registrar_ =
      std::make_unique<flutter::PluginRegistrarWindows>(raw_registrar);

  decoder_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          plugin_registrar_->messenger(),
          "com.chuonghoai.mirroring/video_decoder",
          &flutter::StandardMethodCodec::GetInstance());

  decoder_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleDecoderCall(call, std::move(result));
      });

  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          plugin_registrar_->messenger(),
          "com.chuonghoai.mirroring/window_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());

  lifecycle_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleLifecycleCall(call, std::move(result));
      });
}

void FlutterWindow::HandleDecoderCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "createTexture") {
    if (!video_decoder_) {
      video_decoder_ = std::make_unique<H264VideoDecoder>(
          plugin_registrar_->texture_registrar());
    }
    result->Success(flutter::EncodableValue(video_decoder_->texture_id()));
    return;
  }

  if (method == "startStream") {
    if (!video_decoder_) {
      video_decoder_ = std::make_unique<H264VideoDecoder>(
          plugin_registrar_->texture_registrar());
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string host = ReadStringArg(args, "host", "");
    const int port = ReadIntArg(args, "port", 0);
    const std::string token = ReadStringArg(args, "sessionToken", "");
    const bool started = video_decoder_->StartTcpStream(host, port, token);
    result->Success(flutter::EncodableValue(started));
    return;
  }

  if (method == "stopStream") {
    if (video_decoder_) {
      video_decoder_->StopTcpStream();
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "getStreamStats") {
    flutter::EncodableMap resp;
    if (video_decoder_) {
      const auto stats = video_decoder_->GetStreamStats();
      resp[flutter::EncodableValue("connected")] =
          flutter::EncodableValue(stats.connected);
      resp[flutter::EncodableValue("ended")] =
          flutter::EncodableValue(stats.ended);
      resp[flutter::EncodableValue("width")] =
          flutter::EncodableValue(stats.width);
      resp[flutter::EncodableValue("height")] =
          flutter::EncodableValue(stats.height);
      resp[flutter::EncodableValue("rotation")] =
          flutter::EncodableValue(stats.rotation);
      resp[flutter::EncodableValue("decodedFrames")] =
          flutter::EncodableValue(stats.decoded_frames);
      resp[flutter::EncodableValue("error")] =
          flutter::EncodableValue(stats.error);
    } else {
      resp[flutter::EncodableValue("connected")] =
          flutter::EncodableValue(false);
      resp[flutter::EncodableValue("ended")] = flutter::EncodableValue(false);
      resp[flutter::EncodableValue("width")] = flutter::EncodableValue(0);
      resp[flutter::EncodableValue("height")] = flutter::EncodableValue(0);
      resp[flutter::EncodableValue("rotation")] = flutter::EncodableValue(0);
      resp[flutter::EncodableValue("decodedFrames")] =
          flutter::EncodableValue(int64_t{0});
      resp[flutter::EncodableValue("error")] =
          flutter::EncodableValue(std::string());
    }
    result->Success(flutter::EncodableValue(resp));
    return;
  }

  if (method == "decodeFrame") {
    if (!video_decoder_) {
      result->Error("NO_DECODER", "Decoder not initialized");
      return;
    }
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map arguments");
      return;
    }

    auto bytes_it = args->find(flutter::EncodableValue("bytes"));
    auto width_it = args->find(flutter::EncodableValue("width"));
    auto height_it = args->find(flutter::EncodableValue("height"));
    if (bytes_it == args->end() || width_it == args->end() ||
        height_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing bytes/width/height");
      return;
    }

    const auto* bytes =
        std::get_if<std::vector<uint8_t>>(&bytes_it->second);
    const int width =
        std::holds_alternative<int32_t>(width_it->second)
            ? std::get<int32_t>(width_it->second)
            : static_cast<int>(std::get<int64_t>(width_it->second));
    const int height =
        std::holds_alternative<int32_t>(height_it->second)
            ? std::get<int32_t>(height_it->second)
            : static_cast<int>(std::get<int64_t>(height_it->second));

    if (!bytes || bytes->empty()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const bool ok =
        video_decoder_->DecodeAnnexB(bytes->data(), bytes->size(), width, height);
    flutter::EncodableMap resp;
    resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(ok);
    resp[flutter::EncodableValue("width")] =
        flutter::EncodableValue(video_decoder_->width());
    resp[flutter::EncodableValue("height")] =
        flutter::EncodableValue(video_decoder_->height());
    result->Success(flutter::EncodableValue(resp));
    return;
  }

  if (method == "resetDecoder") {
    if (video_decoder_) {
      video_decoder_->Reset();
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "disposeTexture") {
    video_decoder_.reset();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::HandleLifecycleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "enterViewerMode") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const int sw = ReadIntArg(args, "streamWidth", 720);
    const int sh = ReadIntArg(args, "streamHeight", 1280);
    const std::string title = ReadStringArg(args, "title", "Mirroring");
    EnterViewerWindowMode(sw, sh, title);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "exitViewerMode") {
    ExitViewerWindowMode();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "confirmClose") {
    result->Success(flutter::EncodableValue(true));
    if (close_requested_ && !close_confirmed_) {
      close_confirmed_ = true;
      KillTimer(GetHandle(), kCloseTimeoutTimerId);
      DestroyWindow(GetHandle());
    }
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::EnterViewerWindowMode(int stream_width, int stream_height,
                                          const std::string& title) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  if (!in_viewer_mode_) {
    if (GetWindowRect(hwnd, &saved_controller_rect_)) {
      has_saved_controller_rect_ = true;
    }
  }
  in_viewer_mode_ = true;

  const std::wstring wide_title = Utf8ToWide(title);
  if (!wide_title.empty()) {
    SetWindowTextW(hwnd, wide_title.c_str());
  }

  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (!GetMonitorInfoW(monitor, &mi)) {
    return;
  }

  const int work_w = mi.rcWork.right - mi.rcWork.left;
  const int work_h = mi.rcWork.bottom - mi.rcWork.top;

  double dpi_scale = 1.0;
  HDC hdc = GetDC(hwnd);
  if (hdc) {
    const int dpi = GetDeviceCaps(hdc, LOGPIXELSX);
    if (dpi > 0) {
      dpi_scale = static_cast<double>(dpi) / 96.0;
    }
    ReleaseDC(hwnd, hdc);
  }

  const int sw = std::max(stream_width, 320);
  const int sh = std::max(stream_height, 320);

  // Reserve room for viewer top/bottom toolbars and padding, scaled by DPI.
  const int chrome_h = static_cast<int>(108 * dpi_scale);
  const int chrome_w = static_cast<int>(24 * dpi_scale);
  const int min_w = static_cast<int>(480 * dpi_scale);
  const int min_h = static_cast<int>(680 * dpi_scale);

  const int max_video_h =
      std::max(static_cast<int>(360 * dpi_scale),
               static_cast<int>(work_h * 0.88) - chrome_h);
  const int max_video_w =
      std::max(static_cast<int>(360 * dpi_scale),
               static_cast<int>(work_w * 0.88) - chrome_w);

  const double scale_w = static_cast<double>(max_video_w) / static_cast<double>(sw);
  const double scale_h = static_cast<double>(max_video_h) / static_cast<double>(sh);
  const double scale = std::min(scale_w, scale_h);

  const int client_w = std::clamp(
      static_cast<int>(sw * scale) + chrome_w,
      min_w,
      std::max(min_w, work_w - 40));
  const int client_h = std::clamp(
      static_cast<int>(sh * scale) + chrome_h,
      min_h,
      std::max(min_h, work_h - 40));

  RECT adj{0, 0, client_w, client_h};
  const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_STYLE));
  const DWORD ex_style = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_EXSTYLE));
  AdjustWindowRectEx(&adj, style, FALSE, ex_style);

  const int win_w = std::min(work_w, static_cast<int>(adj.right - adj.left));
  const int win_h = std::min(work_h, static_cast<int>(adj.bottom - adj.top));
  const int x = mi.rcWork.left + (work_w - win_w) / 2;
  const int y = mi.rcWork.top + (work_h - win_h) / 2;

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetWindowPos(hwnd, nullptr, x, y, win_w, win_h,
               SWP_NOZORDER | SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ExitViewerWindowMode() {
  in_viewer_mode_ = false;
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  SetWindowTextW(hwnd, L"Mirroring");

  if (has_saved_controller_rect_) {
    const int win_w =
        saved_controller_rect_.right - saved_controller_rect_.left;
    const int win_h =
        saved_controller_rect_.bottom - saved_controller_rect_.top;
    if (IsIconic(hwnd)) {
      ShowWindow(hwnd, SW_RESTORE);
    }
    SetWindowPos(hwnd, nullptr, saved_controller_rect_.left,
                 saved_controller_rect_.top, win_w, win_h,
                 SWP_NOZORDER | SWP_SHOWWINDOW);
    SetForegroundWindow(hwnd);
  }
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kCloseTimeoutTimerId);
  video_decoder_.reset();
  decoder_channel_.reset();
  lifecycle_channel_.reset();
  plugin_registrar_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (in_viewer_mode_ && lifecycle_channel_) {
        // Closing the mirroring viewer returns to the Mirroring controller screen,
        // matching scrcpy's window-close behavior.
        lifecycle_channel_->InvokeMethod("onViewerCloseRequested", nullptr);
        return 0;
      }
      if (!close_confirmed_ && lifecycle_channel_) {
        if (!close_requested_) {
          close_requested_ = true;
          SetTimer(hwnd, kCloseTimeoutTimerId, 600, nullptr);
          lifecycle_channel_->InvokeMethod("onWindowCloseRequested", nullptr);
        }
        return 0;
      }
      break;

    case WM_TIMER:
      if (wparam == kCloseTimeoutTimerId && !close_confirmed_) {
        close_confirmed_ = true;
        KillTimer(hwnd, kCloseTimeoutTimerId);
        DestroyWindow(hwnd);
        return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
