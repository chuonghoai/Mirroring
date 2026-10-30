import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/adb_device.dart';

class AdbActionResult {
  final bool success;
  final String message;
  final String? rawOutput;

  const AdbActionResult({
    required this.success,
    required this.message,
    this.rawOutput,
  });
}

class AdbService {
  final String adbPath;
  static const Duration _commandTimeout = Duration(seconds: 8);

  AdbService({required this.adbPath});

  /// Connects to a device via adb connect IP:PORT
  Future<AdbActionResult> connect(String ip, int port) async {
    final target = '$ip:$port';
    debugPrint('ADB connecting to $target using $adbPath');

    try {
      final result = await Process.run(
        adbPath,
        ['connect', target],
      ).timeout(_commandTimeout);

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      final fullOutput = '$stdout\n$stderr'.trim();

      debugPrint('ADB connect output: $fullOutput (exitCode: ${result.exitCode})');

      final lower = fullOutput.toLowerCase();
      if (lower.contains('already connected to') ||
          (lower.contains('connected to') && !lower.contains('failed to') && !lower.contains('cannot connect'))) {
        
        // Wait brief moment and check device authorization status
        await Future.delayed(const Duration(milliseconds: 600));
        final devices = await getDevices();
        final device = devices.where((d) => d.serial == target).firstOrNull;

        if (device != null) {
          if (device.state == DeviceState.unauthorized) {
            return AdbActionResult(
              success: false,
              message: 'Thiết bị chưa được cấp quyền (Unauthorized). Vui lòng chấp nhận thông báo RSA trên màn hình điện thoại.',
              rawOutput: fullOutput,
            );
          } else if (device.state == DeviceState.offline) {
            return AdbActionResult(
              success: false,
              message: 'Thiết bị ở trạng thái Offline. Vui lòng tắt/bật lại Wireless Debugging trên điện thoại.',
              rawOutput: fullOutput,
            );
          }
        }

        return AdbActionResult(
          success: true,
          message: 'Kết nối thành công đến $target',
          rawOutput: fullOutput,
        );
      } else {
        String errorMsg = 'Không thể kết nối đến $target. Vui lòng kiểm tra lại IP/Port và đảm bảo điện thoại đang bật Gỡ lỗi qua Wi-Fi.';
        if (lower.contains('refused') || lower.contains('actively refused')) {
          errorMsg = 'Kết nối bị từ chối. Hãy kiểm tra lại IP, Port và đảm bảo "Gỡ lỗi qua Wi-Fi" đang BẬT trên điện thoại.';
        } else if (lower.contains('timed out') || lower.contains('timeout')) {
          errorMsg = 'Hết thời gian chờ kết nối (Timeout). Đảm bảo máy tính và điện thoại đang kết nối cùng mạng Wi-Fi.';
        } else if (lower.contains('no route to host') || lower.contains('unreachable')) {
          errorMsg = 'Không tìm thấy thiết bị trong mạng LAN. Vui lòng kiểm tra lại địa chỉ IP.';
        } else if (lower.contains('cannot connect')) {
          errorMsg = 'Không thể kết nối đến $target. Vui lòng kiểm tra lại địa chỉ IP và Port.';
        } else if (fullOutput.isNotEmpty) {
          errorMsg = 'Lỗi kết nối ADB: $fullOutput';
        }
        return AdbActionResult(
          success: false,
          message: errorMsg,
          rawOutput: fullOutput,
        );
      }
    } on TimeoutException {
      return AdbActionResult(
        success: false,
        message: 'Lệnh ADB hết thời gian phản hồi (Timeout). Vui lòng kiểm tra lại địa chỉ IP và mạng Wi-Fi.',
      );
    } catch (e) {
      return AdbActionResult(
        success: false,
        message: 'Lỗi thực thi ADB: $e',
      );
    }
  }

  /// Disconnects from device via adb disconnect IP:PORT
  Future<AdbActionResult> disconnect(String target) async {
    debugPrint('ADB disconnecting from $target');
    try {
      final result = await Process.run(
        adbPath,
        ['disconnect', target],
      ).timeout(_commandTimeout);

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      final fullOutput = '$stdout\n$stderr'.trim();

      debugPrint('ADB disconnect output: $fullOutput');
      return AdbActionResult(
        success: true,
        message: 'Đã ngắt kết nối $target',
        rawOutput: fullOutput,
      );
    } on TimeoutException {
      return AdbActionResult(
        success: false,
        message: 'Ngắt kết nối hết thời gian phản hồi.',
      );
    } catch (e) {
      return AdbActionResult(
        success: false,
        message: 'Lỗi khi ngắt kết nối: $e',
      );
    }
  }

  /// Lists connected devices
  Future<List<AdbDevice>> getDevices() async {
    try {
      final result = await Process.run(
        adbPath,
        ['devices', '-l'],
      ).timeout(const Duration(seconds: 5));

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        final devices = <AdbDevice>[];
        for (final line in lines) {
          final device = AdbDevice.parseLine(line);
          if (device != null) {
            devices.add(device);
          }
        }
        return devices;
      }
    } catch (e) {
      debugPrint('Error getting devices: $e');
    }
    return [];
  }

  /// Checks if specific device is currently in connected state
  Future<bool> isDeviceConnected(String target) async {
    final devices = await getDevices();
    return devices.any((d) => d.serial == target && d.isConnected);
  }
}

