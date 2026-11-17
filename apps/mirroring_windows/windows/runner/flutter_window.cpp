#include "flutter_window.h"

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

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
  if (call.method_name() == "confirmClose") {
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
