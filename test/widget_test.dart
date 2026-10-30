import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirroring/core/models/adb_device.dart';
import 'package:mirroring/core/models/connection_state.dart';
import 'package:mirroring/core/models/tool_info.dart';
import 'package:mirroring/ui/controllers/mirroring_controller.dart';
import 'package:mirroring/ui/screens/home_screen.dart';

void main() {
  group('AdbDevice Parser Tests', () {
    test('parses connected device with model', () {
      const line = '192.168.1.100:5555  device product:panther model:Pixel_7 device:panther transport_id:1';
      final device = AdbDevice.parseLine(line);

      expect(device, isNotNull);
      expect(device!.serial, '192.168.1.100:5555');
      expect(device.state, DeviceState.device);
      expect(device.isConnected, isTrue);
      expect(device.model, 'Pixel 7');
    });

    test('parses unauthorized device', () {
      const line = '192.168.1.105:5555  unauthorized transport_id:2';
      final device = AdbDevice.parseLine(line);

      expect(device, isNotNull);
      expect(device!.serial, '192.168.1.105:5555');
      expect(device.state, DeviceState.unauthorized);
      expect(device.isConnected, isFalse);
    });

    test('parses offline device', () {
      const line = '192.168.1.105:5555  offline transport_id:3';
      final device = AdbDevice.parseLine(line);

      expect(device, isNotNull);
      expect(device!.serial, '192.168.1.105:5555');
      expect(device.state, DeviceState.offline);
      expect(device.isConnected, isFalse);
    });

    test('ignores daemon messages and header lines', () {
      expect(AdbDevice.parseLine('List of devices attached'), isNull);
      expect(AdbDevice.parseLine('* daemon not running; starting now at tcp:5037 *'), isNull);
      expect(AdbDevice.parseLine('* daemon started successfully *'), isNull);
      expect(AdbDevice.parseLine(''), isNull);
      expect(AdbDevice.parseLine('   '), isNull);
    });
  });

  group('ToolInfo Model Tests', () {
    test('isReady is true only when both tools exist and no error', () {
      const ready = ToolInfo(
        adbPath: r'C:\tools\adb.exe',
        adbVersion: '1.0.41',
        scrcpyPath: r'C:\tools\scrcpy.exe',
        scrcpyVersion: '5.0.1',
      );
      expect(ready.isReady, isTrue);
      expect(ready.hasAdb, isTrue);
      expect(ready.hasScrcpy, isTrue);

      const missingScrcpy = ToolInfo(
        adbPath: r'C:\tools\adb.exe',
        adbVersion: '1.0.41',
        error: 'Missing scrcpy',
      );
      expect(missingScrcpy.isReady, isFalse);
      expect(missingScrcpy.hasAdb, isTrue);
      expect(missingScrcpy.hasScrcpy, isFalse);
    });
  });

  group('MirroringAppState Model Tests', () {
    test('state transitions work properly', () {
      const initial = MirroringAppState();
      expect(initial.isConnected, isFalse);
      expect(initial.isConnecting, isFalse);
      expect(initial.isScrcpyRunning, isFalse);

      final connected = initial.copyWith(
        connectionStatus: ConnectionStatus.connected,
        connectedAddress: '192.168.1.50:5555',
        deviceModel: 'Samsung S23',
      );
      expect(connected.isConnected, isTrue);
      expect(connected.connectedAddress, '192.168.1.50:5555');
      expect(connected.deviceModel, 'Samsung S23');

      final withScrcpy = connected.copyWith(scrcpyStatus: ScrcpyStatus.running);
      expect(withScrcpy.isScrcpyRunning, isTrue);

      final disconnected = withScrcpy.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
        scrcpyStatus: ScrcpyStatus.stopped,
        clearConnectedAddress: true,
        clearDeviceModel: true,
      );
      expect(disconnected.isConnected, isFalse);
      expect(disconnected.connectedAddress, isNull);
      expect(disconnected.deviceModel, isNull);
    });
  });

  group('HomeScreen UI Tests', () {
    testWidgets('renders key UI elements', (WidgetTester tester) async {
      final controller = MirroringController(autoInitialize: false);

      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(controller: controller),
        ),
      );
      await tester.pump();

      // Header
      expect(find.text('Android Mirroring'), findsOneWidget);
      expect(find.text('ADB + scrcpy Desktop'), findsOneWidget);

      // Connection fields
      expect(find.text('KẾT NỐI THIẾT BỊ'), findsOneWidget);
      expect(find.text('Địa chỉ IP'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Kết nối ADB'), findsOneWidget);

      // Control card
      expect(find.text('ĐIỀU KHIỂN MÀN HÌNH'), findsOneWidget);
      expect(find.text('Mở Màn hình'), findsOneWidget);

      // Verify Port hintText is '5555' placeholder
      final portField = tester.widget<TextField>(find.widgetWithText(TextField, 'Port'));
      expect(portField.decoration?.hintText, '5555');

      // Allow async _loadVersionFromPubspec to settle
      await tester.pumpAndSettle();
      expect(find.textContaining('phiên bản'), findsOneWidget);

      // Verify pressing Enter in IP field triggers submit (validation error for empty IP)
      final ipFinder = find.widgetWithText(TextField, 'Địa chỉ IP');
      await tester.showKeyboard(ipFinder);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.textContaining('Vui lòng nhập địa chỉ IP'), findsOneWidget);

      controller.dispose();
    });
  });
}
