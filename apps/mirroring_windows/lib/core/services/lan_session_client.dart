import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import 'windows_device_identity.dart';
import 'windows_video_decoder_service.dart';

class LanSessionUpdate {
  final String deviceId;
  final WindowsDeviceStatus status;
  final int? textureId;
  final int streamWidth;
  final int streamHeight;
  final int rotationQuarterTurns;
  final int fps;
  final String? errorMessage;
  final String? statusMessage;

  const LanSessionUpdate({
    required this.deviceId,
    required this.status,
    this.textureId,
    this.streamWidth = 0,
    this.streamHeight = 0,
    this.rotationQuarterTurns = 0,
    this.fps = 0,
    this.errorMessage,
    this.statusMessage,
  });
}

class LanSessionClient {
  final VideoDecoderBackend _decoder;
  final void Function(LanSessionUpdate update) onUpdate;

  WebSocket? _controlWs;
  Socket? _streamSocket;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _streamSub;
  final StreamFrameParser _frameParser = StreamFrameParser();

  Timer? _pairTimeoutTimer;
  Timer? _heartbeatTimer;
  Timer? _fpsTimer;

  DiscoveredDevice? _targetDevice;
  String? _activeRequestId;
  String? _sessionToken;
  int? _streamPort;
  int? _textureId;
  int _heartbeatSeq = 0;
  DateTime? _lastHeartbeatAckAt;
  bool _manualStopping = false;
  bool _reconnecting = false;

  int _streamWidth = 0;
  int _streamHeight = 0;
  int _rotation = 0;
  int _framesInCurrentSecond = 0;
  int _currentFps = 0;
  WindowsDeviceStatus _status = WindowsDeviceStatus.disconnected;

  Future<void> _decodeQueue = Future<void>.value();

  LanSessionClient({
    VideoDecoderBackend? decoder,
    required this.onUpdate,
  }) : _decoder = decoder ?? MethodChannelVideoDecoderBackend();

  WindowsDeviceStatus get status => _status;
  String? get activeDeviceId => _targetDevice?.deviceId;
  int? get textureId => _textureId;

  Future<void> connectAndStart(DiscoveredDevice device) async {
    await stopSession(reason: 'Bắt đầu kết nối mới', notifyPeer: false);

    _manualStopping = false;
    _reconnecting = false;
    _targetDevice = device;
    _streamWidth = 0;
    _streamHeight = 0;
    _rotation = 0;
    _currentFps = 0;
    _framesInCurrentSecond = 0;

    _emit(
      status: WindowsDeviceStatus.connectionRequested,
      statusMessage: 'Đang gửi yêu cầu kết nối tới ${device.deviceName}...',
    );

    try {
      final ws = await WebSocket.connect(
        'ws://${device.ipAddress}:${device.controlPort}',
      ).timeout(const Duration(seconds: 6));
      _controlWs = ws;

      final windowsId = await WindowsDeviceIdentity.getOrCreateDeviceId();
      final windowsName = WindowsDeviceIdentity.getHostName();
      final reqId = _randomToken(12);
      _activeRequestId = reqId;

      _wsSub = ws.listen(
        _onControlData,
        onError: (Object err) => _handleUnexpectedDrop('Lỗi kênh điều khiển: $err'),
        onDone: () => _handleUnexpectedDrop('Kênh điều khiển đã đóng'),
      );

      final pairReq = ControlMessage.pairRequest(
        requestId: reqId,
        windowsDeviceId: windowsId,
        windowsDeviceName: windowsName,
        nonce: _randomToken(16),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      ws.add(pairReq.toJsonString());

      _emit(
        status: WindowsDeviceStatus.waitingForApproval,
        statusMessage: 'Đang chờ xác nhận trên điện thoại ${device.deviceName}...',
      );

      _pairTimeoutTimer?.cancel();
      _pairTimeoutTimer = Timer(
        MirroringProtocolConstants.pairRequestTimeout + const Duration(seconds: 2),
        () {
          if (_status == WindowsDeviceStatus.waitingForApproval) {
            stopSession(
              reason: 'Hết thời gian chờ xác nhận trên điện thoại',
              notifyPeer: false,
              finalStatus: WindowsDeviceStatus.connectionFailed,
              errorMessage: 'Điện thoại không phản hồi yêu cầu trong 30 giây.',
            );
          }
        },
      );
    } catch (e) {
      await stopSession(
        reason: 'Không thể kết nối tới ${device.ipAddress}:${device.controlPort}',
        notifyPeer: false,
        finalStatus: WindowsDeviceStatus.connectionFailed,
        errorMessage: 'Không thể kết nối tới ${device.deviceName} (${device.ipAddress}:${device.controlPort}): $e',
      );
    }
  }

  Future<void> cancelPendingRequest() async {
    final reqId = _activeRequestId;
    final ws = _controlWs;
    if (reqId != null && ws != null) {
      try {
        ws.add(
          ControlMessage.pairCancel(
            requestId: reqId,
            reason: 'Người dùng trên Windows đã hủy yêu cầu',
          ).toJsonString(),
        );
      } catch (_) {}
    }
    await stopSession(
      reason: 'Đã hủy yêu cầu kết nối',
      notifyPeer: false,
      finalStatus: WindowsDeviceStatus.disconnected,
    );
  }

  Future<bool> pushClipboard(String text) async {
    final ws = _controlWs;
    final token = _sessionToken;
    if (ws == null || token == null || text.isEmpty) return false;
    try {
      ws.add(
        ControlMessage.clipboardPush(
          sessionToken: token,
          text: text,
        ).toJsonString(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopSession({
    required String reason,
    bool notifyPeer = true,
    WindowsDeviceStatus finalStatus = WindowsDeviceStatus.disconnected,
    String? errorMessage,
  }) async {
    _manualStopping = true;
    _reconnecting = false;
    _pairTimeoutTimer?.cancel();
    _pairTimeoutTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _fpsTimer?.cancel();
    _fpsTimer = null;

    final ws = _controlWs;
    final token = _sessionToken;
    if (notifyPeer && ws != null && token != null) {
      try {
        ws.add(
          ControlMessage.sessionStop(
            sessionToken: token,
            reason: reason,
          ).toJsonString(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
      } catch (_) {}
    }

    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _controlWs?.close();
    } catch (_) {}
    _controlWs = null;

    await _streamSub?.cancel();
    _streamSub = null;
    try {
      _streamSocket?.destroy();
    } catch (_) {}
    _streamSocket = null;
    _frameParser.reset();

    try {
      await _decoder.resetDecoder();
    } catch (_) {}

    final prevDeviceId = _targetDevice?.deviceId;
    _sessionToken = null;
    _streamPort = null;
    _activeRequestId = null;

    if (prevDeviceId != null) {
      _emit(
        deviceId: prevDeviceId,
        status: finalStatus,
        errorMessage: errorMessage,
        statusMessage: reason,
      );
    }
    _targetDevice = null;
  }

  void _onControlData(dynamic raw) {
    if (raw is! String) return;
    final msg = ControlMessage.tryParse(raw);
    if (msg == null) return;

    switch (msg.type) {
      case ControlMessageType.pairResponse:
        _handlePairResponse(msg.payload);
        break;
      case ControlMessageType.sessionAck:
        _handleSessionAck(msg.payload);
        break;
      case ControlMessageType.heartbeatAck:
        _lastHeartbeatAckAt = DateTime.now();
        break;
      case ControlMessageType.streamConfig:
        _handleStreamConfig(msg.payload);
        break;
      case ControlMessageType.sessionStop:
        final reason =
            (msg.payload['reason'] as String?) ?? 'Điện thoại đã dừng chia sẻ màn hình';
        stopSession(
          reason: reason,
          notifyPeer: false,
          finalStatus: WindowsDeviceStatus.disconnected,
        );
        break;
      case ControlMessageType.error:
        final errMsg = (msg.payload['message'] as String?) ?? 'Lỗi từ thiết bị Android';
        debugPrint('Control channel error: $errMsg');
        break;
      default:
        break;
    }
  }

  Future<void> _handlePairResponse(Map<String, dynamic> payload) async {
    final reqId = payload['requestId'] as String?;
    if (reqId != _activeRequestId) return;

    _pairTimeoutTimer?.cancel();
    _pairTimeoutTimer = null;

    final accepted = (payload['accepted'] as bool?) ?? false;
    if (!accepted) {
      final reason =
          (payload['reason'] as String?) ?? 'Điện thoại đã từ chối kết nối';
      await stopSession(
        reason: reason,
        notifyPeer: false,
        finalStatus: WindowsDeviceStatus.connectionFailed,
        errorMessage: reason,
      );
      return;
    }

    final token = payload['sessionToken'] as String?;
    final streamPort = payload['streamPort'] as int?;
    if (token == null ||
        !ProtocolSecurity.isValidSessionToken(token) ||
        streamPort == null ||
        streamPort <= 0) {
      await stopSession(
        reason: 'Phản hồi xác thực không hợp lệ',
        notifyPeer: false,
        finalStatus: WindowsDeviceStatus.connectionFailed,
        errorMessage: 'Thiết bị Android trả về token phiên hoặc cổng stream không hợp lệ.',
      );
      return;
    }

    _sessionToken = token;
    _streamPort = streamPort;
    _emit(
      status: WindowsDeviceStatus.connecting,
      statusMessage: 'Đã được chấp nhận! Đang mở luồng video...',
    );

    await _connectVideoStreamAndStart();
  }

  Future<void> _connectVideoStreamAndStart() async {
    final device = _targetDevice;
    final token = _sessionToken;
    final port = _streamPort;
    if (device == null || token == null || port == null) return;

    try {
      _textureId ??= await _decoder.createTexture();

      final socket = await Socket.connect(
        device.ipAddress,
        port,
        timeout: const Duration(seconds: 6),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _streamSocket = socket;
      _frameParser.reset();

      // Send token handshake line
      socket.write('${jsonEncode({'sessionToken': token})}\n');
      await socket.flush();

      var handshakeCompleted = false;
      final lineBuf = <int>[];

      _streamSub?.cancel();
      _streamSub = socket.listen(
        (Uint8List chunk) {
          if (!handshakeCompleted) {
            for (var i = 0; i < chunk.length; i++) {
              final b = chunk[i];
              if (b == 10) {
                // '\n'
                final line = utf8.decode(lineBuf, allowMalformed: true).trim();
                lineBuf.clear();
                final parsed = _tryParseJsonMap(line);
                if (parsed?['accepted'] != true) {
                  _handleUnexpectedDrop('Xác thực luồng video bị từ chối');
                  return;
                }
                handshakeCompleted = true;
                _emit(
                  status: WindowsDeviceStatus.connected,
                  statusMessage: 'Đã kết nối luồng video, đang chờ khung hình...',
                );
                if (i + 1 < chunk.length) {
                  _processStreamBytes(Uint8List.sublistView(chunk, i + 1));
                }
                break;
              } else if (b != 13) {
                lineBuf.add(b);
              }
            }
            return;
          }
          _processStreamBytes(chunk);
        },
        onError: (Object err) => _handleUnexpectedDrop('Lỗi luồng video: $err'),
        onDone: () => _handleUnexpectedDrop('Luồng video đã ngắt'),
      );

      final windowsId = await WindowsDeviceIdentity.getOrCreateDeviceId();
      _controlWs?.add(
        ControlMessage.sessionStart(
          sessionToken: token,
          windowsDeviceId: windowsId,
        ).toJsonString(),
      );

      _startHeartbeat();
      _startFpsCounter();
    } catch (e) {
      _handleUnexpectedDrop('Không thể mở cổng stream $port: $e');
    }
  }

  void _processStreamBytes(Uint8List chunk) {
    try {
      final frames = _frameParser.addBytes(chunk);
      for (final frame in frames) {
        if (frame.header.frameType == StreamFrameType.metadata) {
          continue;
        }
        final w = frame.header.width;
        final h = frame.header.height;
        final rot = frame.header.rotationQuarterTurns;
        _decodeQueue = _decodeQueue.then((_) async {
          if (_manualStopping || _targetDevice == null) return;
          final res = await _decoder.decodeFrame(
            bytes: frame.payload,
            width: w,
            height: h,
          );
          if (res.ok && res.width > 0 && res.height > 0) {
            _framesInCurrentSecond++;
            final changed = _streamWidth != res.width ||
                _streamHeight != res.height ||
                _rotation != rot ||
                _status != WindowsDeviceStatus.streaming;
            _streamWidth = res.width;
            _streamHeight = res.height;
            _rotation = rot;
            if (changed) {
              _emit(
                status: WindowsDeviceStatus.streaming,
                statusMessage:
                    'Đang trình chiếu ${_targetDevice?.deviceName ?? ''} (${res.width}×${res.height})',
              );
            }
          }
        });
      }
    } catch (e) {
      _handleUnexpectedDrop('Dữ liệu khung hình lỗi: $e');
    }
  }

  void _handleSessionAck(Map<String, dynamic> payload) {
    final w = payload['width'] as int?;
    final h = payload['height'] as int?;
    final rot = payload['rotation'] as int?;
    if (w != null && w > 0) _streamWidth = w;
    if (h != null && h > 0) _streamHeight = h;
    if (rot != null) _rotation = rot;
    _emit(
      status: _status == WindowsDeviceStatus.streaming
          ? WindowsDeviceStatus.streaming
          : WindowsDeviceStatus.connected,
      statusMessage: 'Đã đồng bộ phiên trình chiếu ($_streamWidth×$_streamHeight)',
    );
  }

  void _handleStreamConfig(Map<String, dynamic> payload) {
    final w = payload['width'] as int?;
    final h = payload['height'] as int?;
    final rot = payload['rotation'] as int?;
    if (w != null && w > 0) _streamWidth = w;
    if (h != null && h > 0) _streamHeight = h;
    if (rot != null) _rotation = rot;
    _emit(status: _status);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastHeartbeatAckAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(
      MirroringProtocolConstants.heartbeatInterval,
      (_) {
        final ws = _controlWs;
        final token = _sessionToken;
        if (ws == null || token == null || _manualStopping) return;

        final lastAck = _lastHeartbeatAckAt;
        if (lastAck != null &&
            DateTime.now().difference(lastAck) >
                MirroringProtocolConstants.heartbeatTimeout) {
          _handleUnexpectedDrop('Hết thời gian chờ phản hồi heartbeat từ điện thoại');
          return;
        }

        try {
          ws.add(
            ControlMessage.heartbeat(
              sessionToken: token,
              seq: ++_heartbeatSeq,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ).toJsonString(),
          );
        } catch (e) {
          _handleUnexpectedDrop('Không thể gửi heartbeat: $e');
        }
      },
    );
  }

  void _startFpsCounter() {
    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == WindowsDeviceStatus.streaming) {
        _currentFps = _framesInCurrentSecond;
        _framesInCurrentSecond = 0;
        _emit(status: _status);
      } else {
        _framesInCurrentSecond = 0;
        _currentFps = 0;
      }
    });
  }

  Future<void> _handleUnexpectedDrop(String reason) async {
    if (_manualStopping || _reconnecting) return;

    final device = _targetDevice;
    final token = _sessionToken;
    final port = _streamPort;
    if (device == null || token == null || port == null) {
      await stopSession(
        reason: reason,
        notifyPeer: false,
        finalStatus: WindowsDeviceStatus.connectionFailed,
        errorMessage: reason,
      );
      return;
    }

    _reconnecting = true;
    _heartbeatTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _controlWs?.close();
    } catch (_) {}
    _controlWs = null;

    await _streamSub?.cancel();
    _streamSub = null;
    try {
      _streamSocket?.destroy();
    } catch (_) {}
    _streamSocket = null;
    _frameParser.reset();

    _emit(
      status: WindowsDeviceStatus.connecting,
      statusMessage: 'Mất kết nối ($reason). Đang thử kết nối lại...',
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!_manualStopping && DateTime.now().isBefore(deadline)) {
      try {
        final ws = await WebSocket.connect(
          'ws://${device.ipAddress}:${device.controlPort}',
        ).timeout(const Duration(seconds: 3));
        _controlWs = ws;
        _wsSub = ws.listen(
          _onControlData,
          onError: (Object err) => _handleUnexpectedDrop('Lỗi kênh điều khiển: $err'),
          onDone: () => _handleUnexpectedDrop('Kênh điều khiển đã đóng'),
        );
        _reconnecting = false;
        await _connectVideoStreamAndStart();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    if (!_manualStopping) {
      await stopSession(
        reason: 'Không thể kết nối lại với ${device.deviceName}',
        notifyPeer: false,
        finalStatus: WindowsDeviceStatus.connectionFailed,
        errorMessage: 'Kết nối tới ${device.deviceName} bị ngắt ($reason).',
      );
    }
  }

  void _emit({
    String? deviceId,
    required WindowsDeviceStatus status,
    String? errorMessage,
    String? statusMessage,
  }) {
    _status = status;
    final targetId = deviceId ?? _targetDevice?.deviceId;
    if (targetId == null) return;
    onUpdate(
      LanSessionUpdate(
        deviceId: targetId,
        status: status,
        textureId: _textureId,
        streamWidth: _streamWidth,
        streamHeight: _streamHeight,
        rotationQuarterTurns: _rotation,
        fps: _currentFps,
        errorMessage: errorMessage,
        statusMessage: statusMessage,
      ),
    );
  }

  Map<String, dynamic>? _tryParseJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _randomToken(int byteLen) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLen, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> dispose() async {
    await stopSession(reason: 'Đóng ứng dụng Windows', notifyPeer: true);
    try {
      await _decoder.disposeTexture();
    } catch (_) {}
    _textureId = null;
  }
}
