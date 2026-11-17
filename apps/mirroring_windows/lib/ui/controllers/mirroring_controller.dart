import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/models/connection_state.dart';
import '../../core/models/tool_info.dart';
import '../../core/services/adb_service.dart';
import '../../core/services/scrcpy_service.dart';
import '../../core/services/tool_locator_service.dart';
import '../../core/services/window_service.dart';

class MirroringController extends ChangeNotifier {
  final ToolLocatorService _toolLocatorService;
  AdbService? _adbService;
  ScrcpyService? _scrcpyService;

  ToolInfo _toolInfo = const ToolInfo();
  ToolInfo get toolInfo => _toolInfo;

  MirroringAppState _state = const MirroringAppState();
  MirroringAppState get state => _state;

  Timer? _statusPollTimer;

  MirroringController({
    ToolLocatorService? toolLocatorService,
    bool autoInitialize = true,
  }) : _toolLocatorService = toolLocatorService ?? ToolLocatorService() {
    if (autoInitialize) {
      initialize();
    }
  }

  /// Initialize and locate tools
  Future<void> initialize() async {
    _state = _state.copyWith(isCheckingTools: true, clearErrorMessage: true);
    notifyListeners();

    _toolInfo = await _toolLocatorService.locateTools();

    if (_toolInfo.isReady) {
      _adbService = AdbService(adbPath: _toolInfo.adbPath!);
      _scrcpyService = ScrcpyService(scrcpyPath: _toolInfo.scrcpyPath!);

      // Check if any device is already connected via ADB
      await _checkExistingConnection();
    } else {
      _state = _state.copyWith(
        errorMessage: _toolInfo.error ?? 'Thiếu công cụ cần thiết.',
      );
    }

    _state = _state.copyWith(isCheckingTools: false);
    notifyListeners();
  }

  Future<void> _checkExistingConnection() async {
    if (_adbService == null) return;
    try {
      final devices = await _adbService!.getDevices();
      final activeDevice = devices.where((d) => d.isConnected && d.serial.contains(':')).firstOrNull;
      if (activeDevice != null) {
        _state = _state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          connectedAddress: activeDevice.serial,
          deviceModel: activeDevice.model,
          scrcpyStatus: ScrcpyStatus.stopped,
        );
        _startDeviceMonitoring();
      }
    } catch (_) {}
  }

  /// Validates standard IPv4 address format (e.g. 192.168.1.10)
  static bool isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty) return false;
      if (!RegExp(r'^[0-9]+$').hasMatch(part)) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
      final val = int.tryParse(part);
      if (val == null || val < 0 || val > 255) return false;
    }
    return true;
  }

  /// Connect to Android phone via IP & Port
  Future<void> connect(String ipInput, String portInput) async {
    final ip = ipInput.trim();
    final rawPort = portInput.trim();
    // Default to port 5555 if user leaves it empty
    final portStr = rawPort.isEmpty ? '5555' : rawPort;

    // 1. Validate inputs first
    if (ip.isEmpty) {
      _state = _state.copyWith(
        errorMessage: 'Vui lòng nhập địa chỉ IP của điện thoại.',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    if (ip.contains(':')) {
      _state = _state.copyWith(
        errorMessage: 'Địa chỉ IP không được chứa dấu hai chấm \':\'. Vui lòng nhập riêng IP và Port.',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    if (!isValidIpv4(ip)) {
      _state = _state.copyWith(
        errorMessage: 'Địa chỉ IP không đúng định dạng IPv4 (Ví dụ hợp lệ: 192.168.1.10).',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null) {
      _state = _state.copyWith(
        errorMessage: 'Cổng (Port) không hợp lệ, phải là số nguyên (Ví dụ: 5555).',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    if (port <= 0 || port > 65535) {
      _state = _state.copyWith(
        errorMessage: 'Cổng (Port) không hợp lệ (hợp lệ từ 1 đến 65535).',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    // 2. Check tool readiness
    if (!_toolInfo.isReady || _adbService == null) {
      _state = _state.copyWith(
        errorMessage: 'Công cụ ADB chưa sẵn sàng.',
        connectionStatus: ConnectionStatus.error,
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      clearErrorMessage: true,
    );
    notifyListeners();

    final result = await _adbService!.connect(ip, port);
    if (result.success) {
      // Fetch device model info
      String? model;
      final devices = await _adbService!.getDevices();
      final device = devices.where((d) => d.serial == '$ip:$port').firstOrNull;
      if (device != null) {
        model = device.model;
      }

      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        connectedAddress: '$ip:$port',
        deviceModel: model,
        scrcpyStatus: ScrcpyStatus.stopped,
        clearErrorMessage: true,
      );
      notifyListeners();

      _startDeviceMonitoring();
    } else {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage: result.message,
      );
      notifyListeners();
    }
  }

  /// Disconnect current device
  Future<void> disconnect() async {
    final target = _state.connectedAddress;
    if (target == null || _adbService == null) return;

    _statusPollTimer?.cancel();
    _statusPollTimer = null;

    _state = _state.copyWith(connectionStatus: ConnectionStatus.disconnecting);
    notifyListeners();

    // 1. Terminate scrcpy if running and make sure window is visible
    if (_scrcpyService != null && _scrcpyService!.isRunning) {
      await _scrcpyService!.stop();
      await WindowService.show();
    }

    // 2. Disconnect ADB
    await _adbService!.disconnect(target);

    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      scrcpyStatus: ScrcpyStatus.stopped,
      clearConnectedAddress: true,
      clearDeviceModel: true,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  /// Open scrcpy window
  Future<void> openScrcpy() async {
    final target = _state.connectedAddress;
    if (target == null || _scrcpyService == null) return;

    _state = _state.copyWith(scrcpyStatus: ScrcpyStatus.starting);
    notifyListeners();

    final success = await _scrcpyService!.start(
      targetDevice: target,
      onExit: (exitCode) {
        // Restore/show Mirroring window when phone screen is closed
        WindowService.show();

        // Detect window close
        if (_state.isConnected) {
          _state = _state.copyWith(scrcpyStatus: ScrcpyStatus.reopenNeeded);
        } else {
          _state = _state.copyWith(scrcpyStatus: ScrcpyStatus.stopped);
        }
        notifyListeners();
      },
    );

    if (success) {
      _state = _state.copyWith(scrcpyStatus: ScrcpyStatus.running);
      notifyListeners();

      // Give scrcpy window a brief moment to display, then hide the controller window
      await Future.delayed(const Duration(milliseconds: 600));
      if (_state.isScrcpyRunning) {
        await WindowService.hide();
      }
    } else {
      _state = _state.copyWith(
        scrcpyStatus: ScrcpyStatus.error,
        errorMessage: 'Không thể khởi chạy cửa sổ scrcpy.',
      );
      notifyListeners();
    }
  }

  /// Start monitoring if device stays connected in background
  void _startDeviceMonitoring() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      final target = _state.connectedAddress;
      if (target == null || _adbService == null || !_state.isConnected) {
        timer.cancel();
        return;
      }

      final isConnected = await _adbService!.isDeviceConnected(target);
      if (!isConnected) {
        debugPrint('Device $target disconnected from ADB');
        timer.cancel();
        // If device dropped, stop scrcpy and ensure window is visible
        if (_scrcpyService != null && _scrcpyService!.isRunning) {
          await _scrcpyService!.stop();
          await WindowService.show();
        }
        _state = _state.copyWith(
          connectionStatus: ConnectionStatus.error,
          scrcpyStatus: ScrcpyStatus.stopped,
          clearConnectedAddress: true,
          clearDeviceModel: true,
          errorMessage: 'Thiết bị đã mất kết nối ADB.',
        );
        notifyListeners();
      }
    });
  }

  /// Clean up all sub-processes when app exits
  Future<void> cleanup() async {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
    if (_scrcpyService != null) {
      await _scrcpyService!.stop();
    }
    await WindowService.show();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
