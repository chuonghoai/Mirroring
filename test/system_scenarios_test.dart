import 'package:flutter_test/flutter_test.dart';
import 'package:mirroring/core/models/adb_device.dart';
import 'package:mirroring/core/models/connection_state.dart';
import 'package:mirroring/core/models/tool_info.dart';
import 'package:mirroring/core/services/tool_locator_service.dart';
import 'package:mirroring/ui/controllers/mirroring_controller.dart';

void main() {
  group('Kiểm thử kịch bản thiếu công cụ (Missing Tools)', () {
    test('Thiếu cả ADB và scrcpy', () {
      const toolInfo = ToolInfo(
        error: 'Không tìm thấy ADB và scrcpy. Vui lòng kiểm tra thư mục tools/scrcpy.',
      );
      expect(toolInfo.isReady, isFalse);
      expect(toolInfo.hasAdb, isFalse);
      expect(toolInfo.hasScrcpy, isFalse);
      expect(toolInfo.error, contains('Không tìm thấy ADB và scrcpy'));
    });

    test('Thiếu scrcpy (chỉ có ADB)', () {
      const toolInfo = ToolInfo(
        adbPath: r'C:\tools\adb.exe',
        adbVersion: '1.0.41',
        error: 'Không tìm thấy scrcpy.',
      );
      expect(toolInfo.isReady, isFalse);
      expect(toolInfo.hasAdb, isTrue);
      expect(toolInfo.hasScrcpy, isFalse);
      expect(toolInfo.error, contains('Không tìm thấy scrcpy'));
    });

    test('Thiếu ADB (chỉ có scrcpy)', () {
      const toolInfo = ToolInfo(
        scrcpyPath: r'C:\tools\scrcpy.exe',
        scrcpyVersion: '5.0.1',
        error: 'Không tìm thấy ADB.',
      );
      expect(toolInfo.isReady, isFalse);
      expect(toolInfo.hasAdb, isFalse);
      expect(toolInfo.hasScrcpy, isTrue);
      expect(toolInfo.error, contains('Không tìm thấy ADB'));
    });
  });

  group('Kiểm thử validation IP và Port không hợp lệ', () {
    test('IP trống', () async {
      final controller = MirroringController(autoInitialize: false);
      await controller.connect('', '5555');

      expect(controller.state.connectionStatus, ConnectionStatus.error);
      expect(controller.state.errorMessage, contains('nhập địa chỉ IP'));
      controller.dispose();
    });

    test('IP chứa dấu hai chấm (ví dụ dán cả ip:port vào ô IP)', () async {
      final controller = MirroringController(autoInitialize: false);
      await controller.connect('192.168.1.10:5555', '5555');

      expect(controller.state.connectionStatus, ConnectionStatus.error);
      expect(controller.state.errorMessage, contains('dấu hai chấm'));
      controller.dispose();
    });

    test('IP không đúng định dạng IPv4', () async {
      final controller = MirroringController(autoInitialize: false);
      await controller.connect('192.168.1', '5555');
      expect(controller.state.errorMessage, contains('định dạng IPv4'));

      await controller.connect('999.999.999.999', '5555');
      expect(controller.state.errorMessage, contains('định dạng IPv4'));

      await controller.connect('abc.xyz.1.2', '5555');
      expect(controller.state.errorMessage, contains('định dạng IPv4'));
      controller.dispose();
    });

    test('Port không phải số', () async {
      final controller = MirroringController(autoInitialize: false);
      await controller.connect('192.168.1.100', 'abc');

      expect(controller.state.connectionStatus, ConnectionStatus.error);
      expect(controller.state.errorMessage, contains('Port'));
      controller.dispose();
    });

    test('Port ngoài dải cho phép (0 hoặc > 65535)', () async {
      final controller = MirroringController(autoInitialize: false);
      await controller.connect('192.168.1.100', '0');

      expect(controller.state.connectionStatus, ConnectionStatus.error);
      expect(controller.state.errorMessage, contains('1 đến 65535'));

      await controller.connect('192.168.1.100', '70000');
      expect(controller.state.connectionStatus, ConnectionStatus.error);
      expect(controller.state.errorMessage, contains('1 đến 65535'));

      controller.dispose();
    });

    test('Port để trống không báo lỗi mà tự động fallback về cổng 5555', () async {
      final controller = MirroringController(autoInitialize: false);
      // Khi IP hợp lệ và port để trống '', controller không được văng lỗi validation Port
      await controller.connect('192.168.1.100', '');

      // Controller qua được khâu validate port (chỉ dừng lại ở bước công cụ vì autoInitialize=false)
      expect(controller.state.errorMessage, isNot(contains('Port')));
      controller.dispose();
    });
  });

  group('Kiểm thử định vị công cụ thực tế trên môi trường hiện tại', () {
    test('ToolLocatorService tìm thấy cả ADB và scrcpy trong tools/scrcpy', () async {
      final locator = ToolLocatorService();
      final toolInfo = await locator.locateTools();

      expect(toolInfo.isReady, isTrue);
      expect(toolInfo.adbPath, isNotNull);
      expect(toolInfo.scrcpyPath, isNotNull);
      expect(toolInfo.adbVersion, isNotNull);
      expect(toolInfo.scrcpyVersion, isNotNull);
      expect(toolInfo.error, isNull);
    });
  });

  group('Kiểm thử phân tích phản hồi ADB', () {
    test('Phân tích kết quả adb devices đa trạng thái', () {
      const output = '''
List of devices attached
192.168.1.50:5555      device product:husky model:Pixel_8_Pro device:husky transport_id:1
192.168.1.51:5555      unauthorized transport_id:2
192.168.1.52:5555      offline transport_id:3
emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64x transport_id:4
''';
      final lines = output.split('\n');
      final devices = lines
          .map((l) => AdbDevice.parseLine(l))
          .whereType<AdbDevice>()
          .toList();

      expect(devices.length, 4);

      // Pixel 8 Pro
      expect(devices[0].serial, '192.168.1.50:5555');
      expect(devices[0].isConnected, isTrue);
      expect(devices[0].model, 'Pixel 8 Pro');

      // Unauthorized
      expect(devices[1].serial, '192.168.1.51:5555');
      expect(devices[1].state, DeviceState.unauthorized);
      expect(devices[1].isConnected, isFalse);

      // Offline
      expect(devices[2].serial, '192.168.1.52:5555');
      expect(devices[2].state, DeviceState.offline);
      expect(devices[2].isConnected, isFalse);

      // Emulator
      expect(devices[3].serial, 'emulator-5554');
      expect(devices[3].isConnected, isTrue);
    });
  });
}

