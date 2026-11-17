#ifndef RUNNER_H264_VIDEO_DECODER_H_
#define RUNNER_H264_VIDEO_DECODER_H_

#include <flutter/texture_registrar.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl/client.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

// Decodes raw H.264 Annex-B frames using Windows Media Foundation
// (CLSID_CMSH264DecoderMFT) and publishes RGBA32 frames to a Flutter Texture.
class H264VideoDecoder {
 public:
  explicit H264VideoDecoder(flutter::TextureRegistrar* registrar);
  ~H264VideoDecoder();

  int64_t texture_id() const { return texture_id_; }

  bool DecodeAnnexB(const uint8_t* data, size_t size, int hint_width,
                    int hint_height);
  void Reset();
  void Dispose();

  int width() const { return frame_width_; }
  int height() const { return frame_height_; }

 private:
  struct FrameBuffer {
    std::vector<uint8_t> rgba;
    int width = 0;
    int height = 0;
  };

  bool EnsureMftInitialized(int width, int height);
  bool ConfigureOutputNv12();
  void DrainOutputSamples();
  void ConvertNv12ToRgba(const uint8_t* nv12, LONG stride, int width,
                         int height);
  void ShutdownMft();

  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);
  static void ReleasePixelBufferCallback(void* release_context);

  flutter::TextureRegistrar* registrar_;
  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  int64_t texture_id_ = -1;

  bool mf_started_ = false;
  Microsoft::WRL::ComPtr<IMFTransform> mft_;
  int mft_width_ = 0;
  int mft_height_ = 0;
  int coded_width_ = 0;
  int coded_height_ = 0;
  LONG output_stride_ = 0;
  bool streaming_started_ = false;

  std::mutex buffer_mutex_;
  std::shared_ptr<FrameBuffer> latest_frame_;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  int frame_width_ = 0;
  int frame_height_ = 0;
};

#endif  // RUNNER_H264_VIDEO_DECODER_H_
