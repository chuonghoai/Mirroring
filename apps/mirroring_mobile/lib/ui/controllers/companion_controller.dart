import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models/companion_state.dart';
import '../../core/services/native_mirroring_bridge.dart';

class CompanionController extends ChangeNotifier {
  final MirroringNativeBridge _bridge;

  CompanionAppState _state = const CompanionAppState();
  CompanionAppState get state => _state;

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  StreamSubscription<Map<Object?, Object?>>? _eventSub;
  Timer? _countdownTimer;

  CompanionController({
    MirroringNativeBridge? bridge,
    bool autoInitialize = true,
  }) : _bridge = bridge ?? MethodChannelMirroringBridge() {
    if (autoInitialize) {
      initialize();
    }
  }

  Future<void> initialize() async {
    _eventSub?.cancel();
    _eventSub = _bridge.events.listen(_onNativeEvent);

    try {
      final hasNotif = await _bridge.hasNotificationPermission();
      final snapshot = await _bridge.getSnapshot();
      _state = CompanionAppState.fromNativeMap(
        snapshot,
        hasNotificationPermission: hasNotif,
        isResponding: _state.isResponding,
      );
      _syncCountdownTimer();
      notifyListeners();

      if (!hasNotif) {
        await _bridge.requestNotificationPermission();
        final updated = await _bridge.hasNotificationPermission();
        _state = _state.copyWith(hasNotificationPermission: updated);
        notifyListeners();
      }
    } catch (e) {
      _appendLog('Lỗi khởi tạo native bridge: $e');
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _bridge.requestNotificationPermission();
      final granted = await _bridge.hasNotificationPermission();
      _state = _state.copyWith(hasNotificationPermission: granted);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshDiscovery() async {
    try {
      await _bridge.refreshDiscovery();
    } catch (e) {
      _appendLog('Không thể làm mới tìm kiếm LAN: $e');
    }
  }

  Future<void> acceptIncomingRequest() async {
    final req = _state.pendingRequest;
    if (req == null || _state.isResponding) return;

    _state = _state.copyWith(isResponding: true);
    notifyListeners();

    try {
      final ok = await _bridge.respondToRequest(
        requestId: req.requestId,
        accepted: true,
      );
      if (!ok) {
        _appendLog('Yêu cầu kết nối không còn hiệu lực.');
        return;
      }

      // Request notification permission if needed so foreground service notice is visible
      if (!_state.hasNotificationPermission) {
        await _bridge.requestNotificationPermission();
        final granted = await _bridge.hasNotificationPermission();
        _state = _state.copyWith(hasNotificationPermission: granted);
      }

      final grantedProjection = await _bridge.requestMediaProjectionAndStart();
      if (!grantedProjection) {
        _appendLog('Quyền chia sẻ màn hình MediaProjection đã bị từ chối.');
      }
    } catch (e) {
      _appendLog('Lỗi chấp nhận kết nối: $e');
    } finally {
      _state = _state.copyWith(isResponding: false);
      notifyListeners();
    }
  }

  Future<void> rejectIncomingRequest() async {
    final req = _state.pendingRequest;
    if (req == null || _state.isResponding) return;

    _state = _state.copyWith(isResponding: true);
    notifyListeners();

    try {
      await _bridge.respondToRequest(
        requestId: req.requestId,
        accepted: false,
        reason: 'Người dùng trên điện thoại đã từ chối kết nối',
      );
    } catch (e) {
      _appendLog('Lỗi từ chối yêu cầu: $e');
    } finally {
      _state = _state.copyWith(isResponding: false);
      notifyListeners();
    }
  }

  Future<void> stopMirroring() async {
    try {
      await _bridge.stopSession(reason: 'Người dùng đã dừng chia sẻ trên điện thoại');
    } catch (e) {
      _appendLog('Lỗi dừng phiên chia sẻ: $e');
    }
  }

  void _onNativeEvent(Map<Object?, Object?> event) {
    final type = event['type'] as String?;
    if (type == 'state') {
      final data = event['data'] as Map<Object?, Object?>?;
      if (data != null) {
        _state = CompanionAppState.fromNativeMap(
          data,
          hasNotificationPermission: _state.hasNotificationPermission,
          isResponding: _state.isResponding,
        );
        _syncCountdownTimer();
        notifyListeners();
      }
    } else if (type == 'log') {
      final msg = event['message'] as String?;
      if (msg != null && msg.isNotEmpty) {
        _appendLog(msg);
      }
    }
  }

  void _syncCountdownTimer() {
    if (_state.pendingRequest != null) {
      _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state.pendingRequest == null) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
        } else {
          notifyListeners();
        }
      });
    } else {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  void _appendLog(String msg) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _logs.insert(0, '[$hh:$mm:$ss] $msg');
    if (_logs.length > 20) {
      _logs.removeRange(20, _logs.length);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}
