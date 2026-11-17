#ifndef RUNNER_H264_VIDEO_DECODER_H_
#define RUNNER_H264_VIDEO_DECODER_H_

#include <flutter/texture_registrar.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Decodes raw H.264 Annex-B frames using Windows Media Foundation
// (CLSID_CMSH264DecoderMFT) and publishes RGBA32 frames to a Flutter Texture.
// Supports both direct Dart-pushed Annex-B frames and a high-FPS background
// Winsock2 TCP receiver + decoder thread.
class H264VideoDecoder {
 public:
  struct StreamStats {
    bool connected = false;
    bool ended = false;
    int width = 0;
    int height = 0;
    int rotation = 0;
    int64_t decoded_frames = 0;
    std::string error;
  };

  explicit H264VideoDecoder(flutter::TextureRegistrar* registrar);
  ~H264VideoDecoder();

  int64_t texture_id() const { return texture_id_; }

  bool StartTcpStream(const std::string& host, int port,
                      const std::string& session_token);
  void StopTcpStream();
  StreamStats GetStreamStats();

  bool DecodeAnnexB(const uint8_t* data, size_t size, int hint_width,
                    int hint_height);
  void Reset();
  void Dispose();

  int width() const { return frame_width_.load(); }
  int height() const { return frame_height_.load(); }

 private:
  struct FrameBuffer {
    std::vector<uint8_t> rgba;
    int width = 0;
    int height = 0;
  };

  void TcpStreamLoop(std::string host, int port, std::string session_token);
  static bool RecvExact(uintptr_t sock, uint8_t* out, size_t len);
  static bool SendAll(uintptr_t sock, const uint8_t* data, size_t len);

  bool EnsureMftInitialized(int width, int height);
  bool ConfigureOutputNv12();
  void DrainOutputSamples();
  void ConvertNv12ToRgba(const uint8_t* nv12, LONG stride, int width,
                         int height);
  std::shared_ptr<FrameBuffer> AcquireFrameBuffer(size_t rgba_bytes);
  void ShutdownMft();

  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);
  static void ReleasePixelBufferCallback(void* release_context);

  flutter::TextureRegistrar* registrar_;
  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  int64_t texture_id_ = -1;

  bool mf_started_ = false;
  bool wsa_started_ = false;

  std::mutex mft_mutex_;
  Microsoft::WRL::ComPtr<IMFTransform> mft_;
  Microsoft::WRL::ComPtr<IMFSample> reusable_in_sample_;
  Microsoft::WRL::ComPtr<IMFMediaBuffer> reusable_in_buffer_;
  DWORD reusable_in_capacity_ = 0;
  Microsoft::WRL::ComPtr<IMFSample> reusable_out_sample_;
  Microsoft::WRL::ComPtr<IMFMediaBuffer> reusable_out_buffer_;
  DWORD reusable_out_capacity_ = 0;

  int mft_width_ = 0;
  int mft_height_ = 0;
  int coded_width_ = 0;
  int coded_height_ = 0;
  LONG output_stride_ = 0;
  bool streaming_started_ = false;

  std::mutex buffer_mutex_;
  std::shared_ptr<FrameBuffer> latest_frame_;
  std::vector<std::shared_ptr<FrameBuffer>> buffer_pool_;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::atomic<int> frame_width_{0};
  std::atomic<int> frame_height_{0};
  std::atomic<int> stream_rotation_{0};
  std::atomic<int64_t> decoded_frames_{0};

  std::mutex socket_mutex_;
  static constexpr uintptr_t kInvalidSocketHandle = ~uintptr_t{0};
  uintptr_t stream_socket_ = kInvalidSocketHandle;
  std::thread stream_thread_;
  std::atomic<bool> stream_stop_requested_{false};
  std::atomic<bool> stream_connected_{false};
  std::atomic<bool> stream_ended_{false};
  std::mutex error_mutex_;
  std::string stream_error_;
};

#endif  // RUNNER_H264_VIDEO_DECODER_H_
