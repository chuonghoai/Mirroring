#include "h264_video_decoder.h"

#include <codecapi.h>
#include <mferror.h>
#include <wmcodecdsp.h>

#include <algorithm>
#include <cstring>

namespace {

inline uint8_t ClampByte(int val) {
  if (val < 0) return 0;
  if (val > 255) return 255;
  return static_cast<uint8_t>(val);
}

struct RetainedPixelFrame {
  std::shared_ptr<void> frame_holder;
};

}  // namespace

H264VideoDecoder::H264VideoDecoder(flutter::TextureRegistrar* registrar)
    : registrar_(registrar) {
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
  mf_started_ = SUCCEEDED(hr);

  texture_variant_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture(
          [this](size_t width,
                 size_t height) -> const FlutterDesktopPixelBuffer* {
            return this->CopyPixelBuffer(width, height);
          }));

  if (registrar_) {
    texture_id_ = registrar_->RegisterTexture(texture_variant_.get());
  }
}

H264VideoDecoder::~H264VideoDecoder() {
  Dispose();
}

void H264VideoDecoder::Dispose() {
  ShutdownMft();
  if (registrar_ && texture_id_ >= 0) {
    registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  if (mf_started_) {
    MFShutdown();
    mf_started_ = false;
  }
}

void H264VideoDecoder::Reset() {
  ShutdownMft();
  std::lock_guard<std::mutex> lock(buffer_mutex_);
  frame_width_ = 0;
  frame_height_ = 0;
  latest_frame_.reset();
}

bool H264VideoDecoder::EnsureMftInitialized(int width, int height) {
  if (!mf_started_) return false;
  const int target_w = std::max(width, 64);
  const int target_h = std::max(height, 64);

  if (mft_ && mft_width_ == target_w && mft_height_ == target_h) {
    return true;
  }

  ShutdownMft();

  HRESULT hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&mft_));
  if (FAILED(hr) || !mft_) {
    return false;
  }

  Microsoft::WRL::ComPtr<ICodecAPI> codec_api;
  if (SUCCEEDED(mft_.As(&codec_api)) && codec_api) {
    VARIANT var_true;
    VariantInit(&var_true);
    var_true.vt = VT_BOOL;
    var_true.boolVal = VARIANT_TRUE;
    codec_api->SetValue(&CODECAPI_AVLowLatencyMode, &var_true);
    VariantClear(&var_true);
  }

  Microsoft::WRL::ComPtr<IMFMediaType> input_type;
  hr = MFCreateMediaType(&input_type);
  if (FAILED(hr)) {
    ShutdownMft();
    return false;
  }

  input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  input_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(input_type.Get(), MF_MT_FRAME_SIZE, target_w, target_h);
  MFSetAttributeRatio(input_type.Get(), MF_MT_FRAME_RATE, 30, 1);
  MFSetAttributeRatio(input_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

  hr = mft_->SetInputType(0, input_type.Get(), 0);
  if (FAILED(hr)) {
    ShutdownMft();
    return false;
  }

  if (!ConfigureOutputNv12()) {
    ShutdownMft();
    return false;
  }

  mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  streaming_started_ = true;
  mft_width_ = target_w;
  mft_height_ = target_h;
  coded_width_ = target_w;
  coded_height_ = target_h;
  return true;
}

bool H264VideoDecoder::ConfigureOutputNv12() {
  if (!mft_) return false;
  for (DWORD idx = 0;; ++idx) {
    Microsoft::WRL::ComPtr<IMFMediaType> out_type;
    HRESULT hr = mft_->GetOutputAvailableType(0, idx, &out_type);
    if (FAILED(hr)) break;

    GUID subtype = GUID_NULL;
    if (SUCCEEDED(out_type->GetGUID(MF_MT_SUBTYPE, &subtype)) &&
        subtype == MFVideoFormat_NV12) {
      hr = mft_->SetOutputType(0, out_type.Get(), 0);
      if (SUCCEEDED(hr)) {
        UINT32 w = 0;
        UINT32 h = 0;
        if (SUCCEEDED(
                MFGetAttributeSize(out_type.Get(), MF_MT_FRAME_SIZE, &w, &h))) {
          coded_width_ = static_cast<int>(w);
          coded_height_ = static_cast<int>(h);
        }
        UINT32 stride_val = 0;
        if (SUCCEEDED(out_type->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride_val))) {
          output_stride_ = static_cast<LONG>(static_cast<int32_t>(stride_val));
        } else {
          output_stride_ = static_cast<LONG>(coded_width_);
        }
        return true;
      }
    }
  }
  return false;
}

bool H264VideoDecoder::DecodeAnnexB(const uint8_t* data, size_t size,
                                    int hint_width, int hint_height) {
  if (!data || size == 0) return false;
  if (!EnsureMftInitialized(hint_width, hint_height)) {
    return false;
  }

  Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
  HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(size), &buffer);
  if (FAILED(hr) || !buffer) return false;

  BYTE* dst = nullptr;
  hr = buffer->Lock(&dst, nullptr, nullptr);
  if (FAILED(hr) || !dst) return false;
  std::memcpy(dst, data, size);
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(size));

  Microsoft::WRL::ComPtr<IMFSample> sample;
  hr = MFCreateSample(&sample);
  if (FAILED(hr) || !sample) return false;
  sample->AddBuffer(buffer.Get());

  hr = mft_->ProcessInput(0, sample.Get(), 0);
  if (hr == MF_E_NOTACCEPTING) {
    DrainOutputSamples();
    hr = mft_->ProcessInput(0, sample.Get(), 0);
  }
  if (FAILED(hr)) {
    return false;
  }

  DrainOutputSamples();
  return true;
}

void H264VideoDecoder::DrainOutputSamples() {
  if (!mft_) return;

  for (;;) {
    MFT_OUTPUT_STREAM_INFO stream_info{};
    HRESULT hr = mft_->GetOutputStreamInfo(0, &stream_info);
    if (FAILED(hr)) break;

    const bool mft_provides_samples =
        (stream_info.dwFlags &
         (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES |
          MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;

    MFT_OUTPUT_DATA_BUFFER output_data{};
    output_data.dwStreamID = 0;

    Microsoft::WRL::ComPtr<IMFSample> allocated_sample;
    if (!mft_provides_samples) {
      const DWORD buf_size = std::max<DWORD>(
          stream_info.cbSize,
          static_cast<DWORD>(std::max(coded_width_, mft_width_) *
                             std::max(coded_height_, mft_height_) * 2));
      Microsoft::WRL::ComPtr<IMFMediaBuffer> out_buf;
      if (FAILED(MFCreateMemoryBuffer(buf_size, &out_buf))) break;
      if (FAILED(MFCreateSample(&allocated_sample))) break;
      allocated_sample->AddBuffer(out_buf.Get());
      output_data.pSample = allocated_sample.Get();
    }

    DWORD status = 0;
    hr = mft_->ProcessOutput(0, 1, &output_data, &status);

    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      if (output_data.pEvents) {
        output_data.pEvents->Release();
      }
      if (!ConfigureOutputNv12()) break;
      continue;
    }

    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT || FAILED(hr)) {
      if (output_data.pEvents) {
        output_data.pEvents->Release();
      }
      break;
    }

    IMFSample* out_sample = output_data.pSample;
    if (out_sample) {
      Microsoft::WRL::ComPtr<IMFMediaBuffer> media_buf;
      if (SUCCEEDED(out_sample->ConvertToContiguousBuffer(&media_buf)) &&
          media_buf) {
        BYTE* raw_ptr = nullptr;
        DWORD raw_len = 0;
        LONG stride = output_stride_ > 0 ? output_stride_
                                         : static_cast<LONG>(coded_width_);

        Microsoft::WRL::ComPtr<IMF2DBuffer> buf2d;
        bool locked_2d = false;
        if (SUCCEEDED(media_buf.As(&buf2d)) && buf2d) {
          if (SUCCEEDED(buf2d->Lock2D(&raw_ptr, &stride))) {
            locked_2d = true;
          }
        }

        if (!locked_2d) {
          if (SUCCEEDED(media_buf->Lock(&raw_ptr, nullptr, &raw_len)) &&
              raw_ptr) {
            const int vis_w = std::min(mft_width_, coded_width_);
            const int vis_h = std::min(mft_height_, coded_height_);
            if (vis_w > 0 && vis_h > 0 &&
                raw_len >= static_cast<DWORD>(stride * coded_height_ * 3 / 2)) {
              ConvertNv12ToRgba(raw_ptr, stride, vis_w, vis_h);
            }
            media_buf->Unlock();
          }
        } else {
          const int vis_w = std::min(mft_width_, coded_width_);
          const int vis_h = std::min(mft_height_, coded_height_);
          if (raw_ptr && vis_w > 0 && vis_h > 0 && stride > 0) {
            ConvertNv12ToRgba(raw_ptr, stride, vis_w, vis_h);
          }
          buf2d->Unlock2D();
        }
      }
      if (mft_provides_samples) {
        out_sample->Release();
      }
    }

    if (output_data.pEvents) {
      output_data.pEvents->Release();
    }
  }
}

void H264VideoDecoder::ConvertNv12ToRgba(const uint8_t* nv12, LONG stride,
                                         int width, int height) {
  const int uv_offset = static_cast<int>(stride) * coded_height_;
  const size_t rgba_bytes = static_cast<size_t>(width) * height * 4;

  auto next_frame = std::make_shared<FrameBuffer>();
  next_frame->width = width;
  next_frame->height = height;
  next_frame->rgba.resize(rgba_bytes);

  const uint8_t* y_plane = nv12;
  const uint8_t* uv_plane = nv12 + uv_offset;

  for (int y = 0; y < height; ++y) {
    const uint8_t* y_row = y_plane + y * stride;
    const uint8_t* uv_row = uv_plane + (y / 2) * stride;
    uint8_t* dst_row =
        next_frame->rgba.data() + static_cast<size_t>(y) * width * 4;

    for (int x = 0; x < width; ++x) {
      const int y_val = static_cast<int>(y_row[x]) - 16;
      const int uv_idx = (x & ~1);
      const int u_val = static_cast<int>(uv_row[uv_idx]) - 128;
      const int v_val = static_cast<int>(uv_row[uv_idx + 1]) - 128;

      const int c = y_val < 0 ? 0 : 298 * y_val;
      const int r = (c + 409 * v_val + 128) >> 8;
      const int g = (c - 100 * u_val - 208 * v_val + 128) >> 8;
      const int b = (c + 516 * u_val + 128) >> 8;

      const size_t px = static_cast<size_t>(x) * 4;
      dst_row[px + 0] = ClampByte(r);
      dst_row[px + 1] = ClampByte(g);
      dst_row[px + 2] = ClampByte(b);
      dst_row[px + 3] = 255;
    }
  }

  {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    latest_frame_ = std::move(next_frame);
    frame_width_ = width;
    frame_height_ = height;
  }

  if (registrar_ && texture_id_ >= 0) {
    registrar_->MarkTextureFrameAvailable(texture_id_);
  }
}

const FlutterDesktopPixelBuffer* H264VideoDecoder::CopyPixelBuffer(
    size_t /*width*/, size_t /*height*/) {
  std::shared_ptr<FrameBuffer> frame;
  {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    frame = latest_frame_;
  }
  if (!frame || frame->rgba.empty() || frame->width <= 0 ||
      frame->height <= 0) {
    return nullptr;
  }

  auto* retained = new RetainedPixelFrame{frame};
  pixel_buffer_.buffer = frame->rgba.data();
  pixel_buffer_.width = static_cast<size_t>(frame->width);
  pixel_buffer_.height = static_cast<size_t>(frame->height);
  pixel_buffer_.release_callback = &H264VideoDecoder::ReleasePixelBufferCallback;
  pixel_buffer_.release_context = retained;
  return &pixel_buffer_;
}

// static
void H264VideoDecoder::ReleasePixelBufferCallback(void* release_context) {
  auto* retained = static_cast<RetainedPixelFrame*>(release_context);
  delete retained;
}

void H264VideoDecoder::ShutdownMft() {
  if (mft_) {
    if (streaming_started_) {
      mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
      mft_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
      streaming_started_ = false;
    }
    mft_.Reset();
  }
  mft_width_ = 0;
  mft_height_ = 0;
  coded_width_ = 0;
  coded_height_ = 0;
  output_stride_ = 0;
}
