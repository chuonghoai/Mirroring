import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import '../../core/services/lan_discovery_service.dart';
import '../../core/services/lan_session_client.dart';
import '../../core/services/windows_video_decoder_service.dart';

class LanMirroringController extends ChangeNotifier {
  static const MethodChannel _lifecycleChannel =
      MethodChannel('com.chuonghoai.mirroring/window_lifecycle');

  final LanDiscoveryService _discoveryService;
  late final LanSessionClient _sessionClient;

  StreamSubscription<List<DiscoveredDevice>>? _discoverySub;
  List<DiscoveredDevice> _devices = [];
  List<DiscoveredDevice> get devices => _devices;

  String? _activeDeviceId;
  String? get activeDeviceId => _activeDeviceId;

  WindowsDeviceStatus _sessionStatus = WindowsDeviceStatus.disconnected;
  WindowsDeviceStatus get sessionStatus => _sessionStatus;

  int? _textureId;
  int? get textureId => _textureId;

  int _streamWidth = 0;
  int get streamWidth => _streamWidth;

  int _streamHeight = 0;
  int get streamHeight => _streamHeight;

  int _fps = 0;
  int get fps => _fps;

  bool _accessibilityEnabled = false;
  bool get accessibilityEnabled => _accessibilityEnabled;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isViewerVisible = false;
  bool get isViewerVisible => _isViewerVisible;

  int _lastSizedWidth = 0;
  int _lastSizedHeight = 0;
  bool _disposed = false;

  LanMirroringController({
    LanDiscoveryService? discoveryService,
    VideoDecoderBackend? decoderBackend,
    bool autoStart = true,
  }) : _discoveryService = discoveryService ?? LanDiscoveryService() {
    _discoveryService.availabilityProvider = () {
      if (_sessionStatus == WindowsDeviceStatus.streaming ||
          _sessionStatus == WindowsDeviceStatus.connected) {
        return DeviceAvailability.streaming;
      }
      return DeviceAvailability.available;
    };

    _sessionClient = LanSessionClient(
      decoder: decoderBackend,
      onUpdate: _onSessionUpdate,
    );

    _lifecycleChannel.setMethodCallHandler((call) async {
      if (call.method == 'onViewerCloseRequested') {
        await stopSession();
      } else if (call.method == 'onWindowCloseRequested') {
        await cleanup();
        try {
          await _lifecycleChannel.invokeMethod<void>('confirmClose');
        } catch (_) {}
      }
    });

    if (autoStart) {
      start();
    }
  }

  DiscoveredDevice? get activeDevice {
    if (_activeDeviceId == null) return null;
    for (final d in _devices) {
      if (d.deviceId == _activeDeviceId) return d;
    }
    return null;
  }

  bool get isStreamingOrConnected =>
      _sessionStatus == WindowsDeviceStatus.streaming ||
      _sessionStatus == WindowsDeviceStatus.connected;

  bool get isBusyConnecting =>
      _sessionStatus == WindowsDeviceStatus.connectionRequested ||
      _sessionStatus == WindowsDeviceStatus.waitingForApproval ||
      _sessionStatus == WindowsDeviceStatus.connecting;

  Future<void> start() async {
    _discoverySub?.cancel();
    _discoverySub = _discoveryService.devicesStream.listen((list) {
      _devices = _mergeActiveDeviceStatus(list);
      notifyListeners();
    });
    await _discoveryService.start();
    _devices = _mergeActiveDeviceStatus(_discoveryService.currentDevices);
    notifyListeners();
  }

  Future<void> refreshDiscovery() async {
    await _discoveryService.sendBeaconNow();
  }

  Future<void> connectToDevice(DiscoveredDevice device) async {
    _activeDeviceId = device.deviceId;
    _errorMessage = null;
    _statusMessage = 'Đang gửi yêu cầu kết nối tới ${device.deviceName}...';
    notifyListeners();
    await _sessionClient.connectAndStart(device);
  }

  Future<void> cancelPendingRequest() async {
    await _sessionClient.cancelPendingRequest();
  }

  Future<void> stopSession() async {
    _isViewerVisible = false;
    await _exitViewerWindowMode();
    await _sessionClient.stopSession(
      reason: 'Người dùng trên Windows đã dừng trình chiếu',
      notifyPeer: true,
    );
  }

  void showViewer() {
    if (_textureId != null && isStreamingOrConnected) {
      _isViewerVisible = true;
      unawaited(_enterViewerWindowMode(forceResize: true));
      notifyListeners();
    }
  }

  void hideViewerToDeviceList() {
    _isViewerVisible = false;
    unawaited(_exitViewerWindowMode());
    notifyListeners();
  }

  Future<bool> pushClipboardToPhone() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) {
        _statusMessage = 'Clipboard Windows hiện đang trống.';
        notifyListeners();
        return false;
      }
      final ok = await _sessionClient.pushClipboard(text);
      _statusMessage = ok
          ? 'Đã gửi văn bản Clipboard (${text.length} ký tự) sang điện thoại.'
          : 'Không thể gửi Clipboard (chưa có kết nối hợp lệ).';
      notifyListeners();
      return ok;
    } catch (e) {
      _errorMessage = 'Lỗi đọc Clipboard Windows: $e';
      notifyListeners();
      return false;
    }
  }

  bool sendTouchGesture({
    required List<Map<String, double>> points,
    required int durationMs,
  }) {
    return _sessionClient.sendTouchGesture(
      points: points,
      durationMs: durationMs,
    );
  }

  bool sendInputAction(String action) {
    return _sessionClient.sendInputAction(action);
  }

  bool sendInputText(String text) {
    return _sessionClient.sendInputText(text);
  }

  Future<void> _enterViewerWindowMode({bool forceResize = false}) async {
    final w = _streamWidth > 0 ? _streamWidth : 720;
    final h = _streamHeight > 0 ? _streamHeight : 1280;
    if (!forceResize && _lastSizedWidth == w && _lastSizedHeight == h) {
      return;
    }
    _lastSizedWidth = w;
    _lastSizedHeight = h;
    final deviceName = activeDevice?.deviceName ?? 'Android';
    try {
      await _lifecycleChannel.invokeMethod<void>('enterViewerMode', {
        'streamWidth': w,
        'streamHeight': h,
        'title': 'Mirroring - $deviceName',
      });
    } catch (_) {}
  }

  Future<void> _exitViewerWindowMode() async {
    _lastSizedWidth = 0;
    _lastSizedHeight = 0;
    try {
      await _lifecycleChannel.invokeMethod<void>('exitViewerMode');
    } catch (_) {}
  }

  List<DiscoveredDevice> _mergeActiveDeviceStatus(List<DiscoveredDevice> list) {
    final activeId = _activeDeviceId;
    if (activeId == null) return list;
    return list.map((d) {
      if (d.deviceId == activeId) {
        return d.copyWith(
          status: _sessionStatus,
          lastError: _errorMessage,
          clearError: _errorMessage == null,
        );
      }
      return d;
    }).toList();
  }

  void _onSessionUpdate(LanSessionUpdate update) {
    if (_disposed) return;

    final wasViewerVisible = _isViewerVisible;
    _activeDeviceId = update.deviceId;
    _sessionStatus = update.status;
    _textureId = update.textureId;
    _streamWidth = update.streamWidth;
    _streamHeight = update.streamHeight;
    _fps = update.fps;
    _accessibilityEnabled = update.accessibilityEnabled;
    _errorMessage = update.errorMessage;
    _statusMessage = update.statusMessage;

    if (update.status == WindowsDeviceStatus.streaming &&
        update.textureId != null) {
      _isViewerVisible = true;
      unawaited(
        _enterViewerWindowMode(forceResize: !wasViewerVisible),
      );
    } else if (update.status == WindowsDeviceStatus.disconnected ||
        update.status == WindowsDeviceStatus.connectionFailed) {
      _isViewerVisible = false;
      if (wasViewerVisible) {
        unawaited(_exitViewerWindowMode());
      }
    }

    _discoveryService.updateDeviceStatus(
      update.deviceId,
      update.status,
      error: update.errorMessage,
      clearError: update.errorMessage == null,
    );

    _devices = _mergeActiveDeviceStatus(_discoveryService.currentDevices);
    notifyListeners();
  }

  Future<void> cleanup() async {
    if (_disposed) return;
    _disposed = true;
    _discoverySub?.cancel();
    _discoverySub = null;
    await _sessionClient.dispose();
    await _discoveryService.dispose();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
