#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "h264_video_decoder.h"

#include <codecapi.h>
#include <mferror.h>
#include <wmcodecdsp.h>

#include <algorithm>
#include <cstring>
#include <mutex>

namespace {

constexpr uint32_t kStreamMagic = 0x4D525631u;  // 'MRV1'
constexpr size_t kStreamHeaderSize = 24;
constexpr uint32_t kMaxPayloadBytes = 16u * 1024u * 1024u;

int g_y_lut[256];
int g_rv_lut[256];
int g_gu_lut[256];
int g_gv_lut[256];
int g_bu_lut[256];
std::once_flag g_lut_once;

void EnsureYuvTablesInitialized() {
  std::call_once(g_lut_once, []() {
    for (int i = 0; i < 256; ++i) {
      const int y = i - 16;
      const int uv = i - 128;
      g_y_lut[i] = y < 0 ? 0 : 298 * y;
      g_rv_lut[i] = 409 * uv + 128;
      g_gu_lut[i] = -100 * uv;
      g_gv_lut[i] = -208 * uv + 128;
      g_bu_lut[i] = 516 * uv + 128;
    }
  });
}

inline uint8_t ClampByte(int val) {
  if (val <= 0) return 0;
  if (val >= 255) return 255;
  return static_cast<uint8_t>(val);
}

inline uint32_t PackRgba(int c, int rv, int guv, int bu) {
  const uint32_t r = ClampByte((c + rv) >> 8);
  const uint32_t g = ClampByte((c + guv) >> 8);
  const uint32_t b = ClampByte((c + bu) >> 8);
  return 0xFF000000u | (b << 16) | (g << 8) | r;
}

uint16_t ReadBe16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint32_t ReadBe32(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0]) << 24) |
         (static_cast<uint32_t>(p[1]) << 16) |
         (static_cast<uint32_t>(p[2]) << 8) |
         static_cast<uint32_t>(p[3]);
}

struct RetainedPixelFrame {
  std::shared_ptr<void> frame_holder;
};

}  // namespace

H264VideoDecoder::H264VideoDecoder(flutter::TextureRegistrar* registrar)
    : registrar_(registrar) {
  EnsureYuvTablesInitialized();
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
  mf_started_ = SUCCEEDED(hr);

  WSADATA wsa_data{};
  wsa_started_ = (WSAStartup(MAKEWORD(2, 2), &wsa_data) == 0);

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
  StopTcpStream();
  {
    std::lock_guard<std::mutex> lock(mft_mutex_);
    ShutdownMft();
  }
  if (registrar_ && texture_id_ >= 0) {
    registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  if (wsa_started_) {
    WSACleanup();
    wsa_started_ = false;
  }
  if (mf_started_) {
    MFShutdown();
    mf_started_ = false;
  }
}

void H264VideoDecoder::Reset() {
  StopTcpStream();
  {
    std::lock_guard<std::mutex> lock(mft_mutex_);
    ShutdownMft();
  }
  std::lock_guard<std::mutex> lock(buffer_mutex_);
  frame_width_ = 0;
  frame_height_ = 0;
  stream_rotation_ = 0;
  decoded_frames_ = 0;
  latest_frame_.reset();
  buffer_pool_.clear();
}

bool H264VideoDecoder::StartTcpStream(const std::string& host, int port,
                                      const std::string& session_token) {
  StopTcpStream();
  if (!wsa_started_ || !mf_started_ || host.empty() || port <= 0 ||
      session_token.empty()) {
    return false;
  }

  stream_stop_requested_ = false;
  stream_connected_ = false;
  stream_ended_ = false;
  decoded_frames_ = 0;
  {
    std::lock_guard<std::mutex> lock(error_mutex_);
    stream_error_.clear();
  }

  stream_thread_ = std::thread(&H264VideoDecoder::TcpStreamLoop, this, host,
                               port, session_token);
  return true;
}

void H264VideoDecoder::StopTcpStream() {
  stream_stop_requested_ = true;
  {
    std::lock_guard<std::mutex> lock(socket_mutex_);
    if (stream_socket_ != kInvalidSocketHandle) {
      SOCKET s = static_cast<SOCKET>(stream_socket_);
      shutdown(s, SD_BOTH);
      closesocket(s);
      stream_socket_ = kInvalidSocketHandle;
    }
  }
  if (stream_thread_.joinable()) {
    stream_thread_.join();
  }
  stream_connected_ = false;
}

H264VideoDecoder::StreamStats H264VideoDecoder::GetStreamStats() {
  StreamStats stats;
  stats.connected = stream_connected_.load();
  stats.ended = stream_ended_.load();
  stats.width = frame_width_.load();
  stats.height = frame_height_.load();
  stats.rotation = stream_rotation_.load();
  stats.decoded_frames = decoded_frames_.load();
  {
    std::lock_guard<std::mutex> lock(error_mutex_);
    stats.error = stream_error_;
  }
  return stats;
}

bool H264VideoDecoder::SendAll(uintptr_t sock_handle, const uint8_t* data,
                               size_t len) {
  SOCKET sock = static_cast<SOCKET>(sock_handle);
  size_t sent = 0;
  while (sent < len) {
    const int n = send(sock, reinterpret_cast<const char*>(data + sent),
                       static_cast<int>(len - sent), 0);
    if (n <= 0) return false;
    sent += static_cast<size_t>(n);
  }
  return true;
}

bool H264VideoDecoder::RecvExact(uintptr_t sock_handle, uint8_t* out,
                                 size_t len) {
  SOCKET sock = static_cast<SOCKET>(sock_handle);
  size_t received = 0;
  while (received < len) {
    const int n = recv(sock, reinterpret_cast<char*>(out + received),
                       static_cast<int>(len - received), 0);
    if (n <= 0) return false;
    received += static_cast<size_t>(n);
  }
  return true;
}

void H264VideoDecoder::TcpStreamLoop(std::string host, int port,
                                     std::string session_token) {
  const HRESULT com_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool com_owned = SUCCEEDED(com_hr);

  auto finish_with_error = [&](const std::string& msg) {
    if (!stream_stop_requested_.load() && !msg.empty()) {
      std::lock_guard<std::mutex> lock(error_mutex_);
      stream_error_ = msg;
    }
    {
      std::lock_guard<std::mutex> lock(socket_mutex_);
      if (stream_socket_ != kInvalidSocketHandle) {
        closesocket(static_cast<SOCKET>(stream_socket_));
        stream_socket_ = kInvalidSocketHandle;
      }
    }
    stream_connected_ = false;
    stream_ended_ = true;
    {
      std::lock_guard<std::mutex> lock(mft_mutex_);
      ShutdownMft();
    }
    if (com_owned) {
      CoUninitialize();
    }
  };

  addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  addrinfo* res = nullptr;
  const std::string port_str = std::to_string(port);
  if (getaddrinfo(host.c_str(), port_str.c_str(), &hints, &res) != 0 || !res) {
    finish_with_error("Không thể phân giải địa chỉ stream");
    return;
  }

  SOCKET sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (sock == INVALID_SOCKET) {
    freeaddrinfo(res);
    finish_with_error("Không thể tạo TCP socket");
    return;
  }

  BOOL nodelay = TRUE;
  setsockopt(sock, IPPROTO_TCP, TCP_NODELAY,
             reinterpret_cast<const char*>(&nodelay), sizeof(nodelay));
  int rcv_buf = 512 * 1024;
  setsockopt(sock, SOL_SOCKET, SO_RCVBUF,
             reinterpret_cast<const char*>(&rcv_buf), sizeof(rcv_buf));
  DWORD handshake_timeout = 5000;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
             reinterpret_cast<const char*>(&handshake_timeout),
             sizeof(handshake_timeout));

  if (connect(sock, res->ai_addr, static_cast<int>(res->ai_addrlen)) != 0) {
    freeaddrinfo(res);
    closesocket(sock);
    finish_with_error("Không thể kết nối tới cổng video TCP");
    return;
  }
  freeaddrinfo(res);

  {
    std::lock_guard<std::mutex> lock(socket_mutex_);
    if (stream_stop_requested_.load()) {
      closesocket(sock);
      finish_with_error("");
      return;
    }
    stream_socket_ = static_cast<uintptr_t>(sock);
  }

  const uintptr_t sock_handle = static_cast<uintptr_t>(sock);

  // Send JSON token handshake
  const std::string handshake =
      "{\"sessionToken\":\"" + session_token + "\"}\n";
  if (!SendAll(sock_handle, reinterpret_cast<const uint8_t*>(handshake.data()),
               handshake.size())) {
    finish_with_error("Gửi xác thực luồng video thất bại");
    return;
  }

  std::string reply_line;
  char ch = 0;
  while (reply_line.size() < 512) {
    const int n = recv(sock, &ch, 1, 0);
    if (n <= 0) {
      finish_with_error("Hết thời gian chờ xác thực luồng video");
      return;
    }
    if (ch == '\n') break;
    if (ch != '\r') reply_line.push_back(ch);
  }
  if (reply_line.find("\"accepted\":true") == std::string::npos) {
    finish_with_error("Xác thực luồng video bị từ chối");
    return;
  }

  // Remove short handshake timeout during active streaming
  DWORD stream_timeout = 0;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
             reinterpret_cast<const char*>(&stream_timeout),
             sizeof(stream_timeout));
  stream_connected_ = true;

  uint8_t header[kStreamHeaderSize];
  std::vector<uint8_t> payload_buf;

  while (!stream_stop_requested_.load()) {
    if (!RecvExact(sock_handle, header, kStreamHeaderSize)) {
      finish_with_error("Luồng video đã ngắt");
      return;
    }

    const uint32_t magic = ReadBe32(header);
    if (magic != kStreamMagic) {
      finish_with_error("Sai định dạng khung hình MRV1");
      return;
    }

    const uint8_t frame_type = header[4];
    const int rotation = static_cast<int>(header[5] & 0x03);
    const int width = static_cast<int>(ReadBe16(header + 6));
    const int height = static_cast<int>(ReadBe16(header + 8));
    const uint32_t payload_len = ReadBe32(header + 20);

    if (payload_len > kMaxPayloadBytes) {
      finish_with_error("Khung hình vượt quá giới hạn cho phép");
      return;
    }

    if (payload_len > 0) {
      if (payload_buf.size() < payload_len) {
        payload_buf.resize(payload_len);
      }
      if (!RecvExact(sock_handle, payload_buf.data(), payload_len)) {
        finish_with_error("Mất dữ liệu khung hình video");
        return;
      }
    }

    if (frame_type == 3 || payload_len == 0) {
      continue;
    }

    stream_rotation_ = rotation;
    DecodeAnnexB(payload_buf.data(), payload_len, width, height);
  }

  finish_with_error("");
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
  MFSetAttributeRatio(input_type.Get(), MF_MT_FRAME_RATE, 60, 1);
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
  std::lock_guard<std::mutex> lock(mft_mutex_);

  if (!EnsureMftInitialized(hint_width, hint_height)) {
    return false;
  }

  const DWORD needed = static_cast<DWORD>(size);
  if (!reusable_in_buffer_ || reusable_in_capacity_ < needed) {
    reusable_in_buffer_.Reset();
    reusable_in_sample_.Reset();
    const DWORD alloc_size = std::max<DWORD>(needed, 256u * 1024u);
    if (FAILED(MFCreateMemoryBuffer(alloc_size, &reusable_in_buffer_)) ||
        !reusable_in_buffer_) {
      return false;
    }
    if (FAILED(MFCreateSample(&reusable_in_sample_)) || !reusable_in_sample_) {
      reusable_in_buffer_.Reset();
      return false;
    }
    reusable_in_sample_->AddBuffer(reusable_in_buffer_.Get());
    reusable_in_capacity_ = alloc_size;
  }

  BYTE* dst = nullptr;
  HRESULT hr = reusable_in_buffer_->Lock(&dst, nullptr, nullptr);
  if (FAILED(hr) || !dst) return false;
  std::memcpy(dst, data, size);
  reusable_in_buffer_->Unlock();
  reusable_in_buffer_->SetCurrentLength(needed);

  hr = mft_->ProcessInput(0, reusable_in_sample_.Get(), 0);
  if (hr == MF_E_NOTACCEPTING) {
    DrainOutputSamples();
    hr = mft_->ProcessInput(0, reusable_in_sample_.Get(), 0);
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

    if (!mft_provides_samples) {
      const DWORD buf_size = std::max<DWORD>(
          stream_info.cbSize,
          static_cast<DWORD>(std::max(coded_width_, mft_width_) *
                             std::max(coded_height_, mft_height_) * 2));
      if (!reusable_out_buffer_ || reusable_out_capacity_ < buf_size) {
        reusable_out_buffer_.Reset();
        reusable_out_sample_.Reset();
        if (FAILED(MFCreateMemoryBuffer(buf_size, &reusable_out_buffer_))) break;
        if (FAILED(MFCreateSample(&reusable_out_sample_))) {
          reusable_out_buffer_.Reset();
          break;
        }
        reusable_out_sample_->AddBuffer(reusable_out_buffer_.Get());
        reusable_out_capacity_ = buf_size;
      }
      reusable_out_buffer_->SetCurrentLength(0);
      output_data.pSample = reusable_out_sample_.Get();
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

std::shared_ptr<H264VideoDecoder::FrameBuffer>
H264VideoDecoder::AcquireFrameBuffer(size_t rgba_bytes) {
  std::lock_guard<std::mutex> lock(buffer_mutex_);
  for (auto& buf : buffer_pool_) {
    if (buf && buf.use_count() == 1 && buf->rgba.size() == rgba_bytes) {
      return buf;
    }
  }
  auto created = std::make_shared<FrameBuffer>();
  created->rgba.resize(rgba_bytes);
  if (buffer_pool_.size() < 4) {
    buffer_pool_.push_back(created);
  }
  return created;
}

void H264VideoDecoder::ConvertNv12ToRgba(const uint8_t* nv12, LONG stride,
                                         int width, int height) {
  const int uv_offset = static_cast<int>(stride) * coded_height_;
  const size_t rgba_bytes = static_cast<size_t>(width) * height * 4;
  auto next_frame = AcquireFrameBuffer(rgba_bytes);
  next_frame->width = width;
  next_frame->height = height;

  const uint8_t* y_plane = nv12;
  const uint8_t* uv_plane = nv12 + uv_offset;
  uint32_t* dst_pixels = reinterpret_cast<uint32_t*>(next_frame->rgba.data());

  const int even_h = height & ~1;
  const int even_w = width & ~1;

  // Fast 2x2 block NV12 -> RGBA32 conversion using precomputed YUV lookup tables.
  for (int y = 0; y < even_h; y += 2) {
    const uint8_t* y_row0 = y_plane + y * stride;
    const uint8_t* y_row1 = y_row0 + stride;
    const uint8_t* uv_row = uv_plane + (y >> 1) * stride;
    uint32_t* dst_row0 = dst_pixels + static_cast<size_t>(y) * width;
    uint32_t* dst_row1 = dst_row0 + width;

    for (int x = 0; x < even_w; x += 2) {
      const uint8_t u = uv_row[x];
      const uint8_t v = uv_row[x + 1];
      const int rv = g_rv_lut[v];
      const int guv = g_gu_lut[u] + g_gv_lut[v];
      const int bu = g_bu_lut[u];

      dst_row0[x] = PackRgba(g_y_lut[y_row0[x]], rv, guv, bu);
      dst_row0[x + 1] = PackRgba(g_y_lut[y_row0[x + 1]], rv, guv, bu);
      dst_row1[x] = PackRgba(g_y_lut[y_row1[x]], rv, guv, bu);
      dst_row1[x + 1] = PackRgba(g_y_lut[y_row1[x + 1]], rv, guv, bu);
    }

    if (even_w < width) {
      const int x = even_w;
      const uint8_t u = uv_row[x & ~1];
      const uint8_t v = uv_row[(x & ~1) + 1];
      const int rv = g_rv_lut[v];
      const int guv = g_gu_lut[u] + g_gv_lut[v];
      const int bu = g_bu_lut[u];
      dst_row0[x] = PackRgba(g_y_lut[y_row0[x]], rv, guv, bu);
      dst_row1[x] = PackRgba(g_y_lut[y_row1[x]], rv, guv, bu);
    }
  }

  if (even_h < height) {
    const int y = even_h;
    const uint8_t* y_row = y_plane + y * stride;
    const uint8_t* uv_row = uv_plane + (y >> 1) * stride;
    uint32_t* dst_row = dst_pixels + static_cast<size_t>(y) * width;
    for (int x = 0; x < width; ++x) {
      const uint8_t u = uv_row[x & ~1];
      const uint8_t v = uv_row[(x & ~1) + 1];
      dst_row[x] = PackRgba(g_y_lut[y_row[x]], g_rv_lut[v],
                            g_gu_lut[u] + g_gv_lut[v], g_bu_lut[u]);
    }
  }

  {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    latest_frame_ = std::move(next_frame);
    frame_width_ = width;
    frame_height_ = height;
  }
  decoded_frames_.fetch_add(1);

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
  reusable_in_sample_.Reset();
  reusable_in_buffer_.Reset();
  reusable_in_capacity_ = 0;
  reusable_out_sample_.Reset();
  reusable_out_buffer_.Reset();
  reusable_out_capacity_ = 0;
  mft_width_ = 0;
  mft_height_ = 0;
  coded_width_ = 0;
  coded_height_ = 0;
  output_stride_ = 0;
}
