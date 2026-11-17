import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirroring_mobile/core/models/companion_state.dart';
import 'package:mirroring_mobile/core/services/native_mirroring_bridge.dart';
import 'package:mirroring_mobile/ui/controllers/companion_controller.dart';
import 'package:mirroring_mobile/ui/screens/companion_home_screen.dart';

class FakeMirroringBridge implements MirroringNativeBridge {
  final StreamController<Map<Object?, Object?>> _events =
      StreamController<Map<Object?, Object?>>.broadcast();

  bool notificationGranted = true;
  bool respondResult = true;
  bool mediaProjectionResult = true;
  final List<String> calls = [];

  Map<Object?, Object?> currentSnapshot = {
    'sessionState': 'IDLE',
    'deviceId': 'android_12345678',
    'deviceName': 'Pixel 8 Test',
    'localIps': ['192.168.1.45'],
    'controlPort': 45455,
    'streamPort': 0,
    'discoveredHosts': [
      {
        'deviceId': 'win_host_001',
        'deviceName': 'DESKTOP-TEST',
        'ipAddress': '192.168.1.10',
        'controlPort': 0,
        'availability': 'available',
        'lastSeenAtMs': 1700000000000,
      },
    ],
    'pendingRequest': null,
    'statusMessage': null,
  };

  void emitState(Map<Object?, Object?> snapshot) {
    currentSnapshot = snapshot;
    _events.add({'type': 'state', 'data': snapshot});
  }

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  @override
  Future<Map<Object?, Object?>> getSnapshot() async {
    calls.add('getSnapshot');
    return currentSnapshot;
  }

  @override
  Future<bool> hasNotificationPermission() async => notificationGranted;

  @override
  Future<void> refreshDiscovery() async {
    calls.add('refreshDiscovery');
  }

  @override
  Future<bool> requestMediaProjectionAndStart() async {
    calls.add('requestMediaProjectionAndStart');
    return mediaProjectionResult;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    notificationGranted = true;
    return true;
  }

  @override
  Future<bool> respondToRequest({
    required String requestId,
    required bool accepted,
    String? reason,
  }) async {
    calls.add('respondToRequest:$requestId:$accepted');
    return respondResult;
  }

  @override
  Future<void> stopSession({String? reason}) async {
    calls.add('stopSession');
  }

  void dispose() {
    _events.close();
  }
}

void main() {
  group('CompanionAppState parsing', () {
    test('parses streaming and reconnecting states from native map', () {
      final streaming = CompanionAppState.fromNativeMap({
        'sessionState': 'STREAMING',
        'deviceId': 'android_test_1',
        'deviceName': 'Galaxy S24',
        'localIps': ['192.168.1.25'],
        'controlPort': 45455,
        'streamPort': 45456,
        'connectedWindowsName': 'OFFICE-PC',
        'streamWidth': 720,
        'streamHeight': 1600,
      });

      expect(streaming.isStreaming, isTrue);
      expect(streaming.isActiveSession, isTrue);
      expect(streaming.connectedWindowsName, 'OFFICE-PC');
      expect(streaming.streamWidth, 720);

      final reconnecting = CompanionAppState.fromNativeMap({
        'sessionState': 'RECONNECTING',
        'reconnectSecondsLeft': 15,
        'connectedWindowsName': 'OFFICE-PC',
      });
      expect(reconnecting.isReconnecting, isTrue);
      expect(reconnecting.reconnectSecondsLeft, 15);
    });
  });

  group('CompanionController approval & rejection flow', () {
    test('accepts incoming request and invokes MediaProjection', () async {
      final bridge = FakeMirroringBridge();
      final controller = CompanionController(bridge: bridge, autoInitialize: false);
      await controller.initialize();

      final now = DateTime.now().millisecondsSinceEpoch;
      bridge.emitState({
        ...bridge.currentSnapshot,
        'sessionState': 'PENDING_APPROVAL',
        'pendingRequest': {
          'requestId': 'req-100',
          'windowsDeviceId': 'win_host_001',
          'windowsDeviceName': 'OFFICE-PC',
          'remoteIp': '192.168.1.10',
          'createdAtMs': now,
          'expiresAtMs': now + 30000,
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.pendingRequest?.windowsDeviceName, 'OFFICE-PC');
      await controller.acceptIncomingRequest();

      expect(bridge.calls, contains('respondToRequest:req-100:true'));
      expect(bridge.calls, contains('requestMediaProjectionAndStart'));

      controller.dispose();
      bridge.dispose();
    });

    test('logs denial when user denies MediaProjection', () async {
      final bridge = FakeMirroringBridge()..mediaProjectionResult = false;
      final controller = CompanionController(bridge: bridge, autoInitialize: false);
      await controller.initialize();

      final now = DateTime.now().millisecondsSinceEpoch;
      bridge.emitState({
        ...bridge.currentSnapshot,
        'sessionState': 'PENDING_APPROVAL',
        'pendingRequest': {
          'requestId': 'req-101',
          'windowsDeviceId': 'win_host_001',
          'windowsDeviceName': 'OFFICE-PC',
          'remoteIp': '192.168.1.10',
          'createdAtMs': now,
          'expiresAtMs': now + 30000,
        },
      });
      await Future<void>.delayed(Duration.zero);

      await controller.acceptIncomingRequest();
      expect(controller.logs.any((l) => l.contains('MediaProjection')), isTrue);

      controller.dispose();
      bridge.dispose();
    });

    test('rejects incoming request cleanly without requesting MediaProjection', () async {
      final bridge = FakeMirroringBridge();
      final controller = CompanionController(bridge: bridge, autoInitialize: false);
      await controller.initialize();

      final now = DateTime.now().millisecondsSinceEpoch;
      bridge.emitState({
        ...bridge.currentSnapshot,
        'sessionState': 'PENDING_APPROVAL',
        'pendingRequest': {
          'requestId': 'req-102',
          'windowsDeviceId': 'win_host_001',
          'windowsDeviceName': 'UNKNOWN-PC',
          'remoteIp': '192.168.1.99',
          'createdAtMs': now,
          'expiresAtMs': now + 30000,
        },
      });
      await Future<void>.delayed(Duration.zero);

      await controller.rejectIncomingRequest();
      expect(bridge.calls, contains('respondToRequest:req-102:false'));
      expect(bridge.calls, isNot(contains('requestMediaProjectionAndStart')));

      controller.dispose();
      bridge.dispose();
    });
  });

  group('CompanionHomeScreen UI', () {
    testWidgets('renders Mirroring identity, discovered Windows host, and approval card',
        (tester) async {
      final bridge = FakeMirroringBridge();
      final controller = CompanionController(bridge: bridge, autoInitialize: false);
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: CompanionHomeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.text('Mirroring'), findsOneWidget);
      expect(find.text('Pixel 8 Test'), findsOneWidget);
      expect(find.text('DESKTOP-TEST'), findsOneWidget);

      final now = DateTime.now().millisecondsSinceEpoch;
      bridge.emitState({
        ...bridge.currentSnapshot,
        'sessionState': 'PENDING_APPROVAL',
        'pendingRequest': {
          'requestId': 'req-ui',
          'windowsDeviceId': 'win_host_001',
          'windowsDeviceName': 'OFFICE-PC',
          'remoteIp': '192.168.1.10',
          'createdAtMs': now,
          'expiresAtMs': now + 25000,
        },
      });
      await tester.pump();
      await tester.pump();

      expect(find.text('OFFICE-PC'), findsOneWidget);
      expect(find.text('Chấp nhận & Chia sẻ'), findsOneWidget);
      expect(find.text('Từ chối'), findsOneWidget);

      controller.dispose();
      bridge.dispose();
    });
  });
}
