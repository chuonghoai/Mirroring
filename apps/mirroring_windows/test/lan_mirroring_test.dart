import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirroring/core/services/lan_discovery_service.dart';
import 'package:mirroring/core/services/lan_session_client.dart';
import 'package:mirroring/core/services/windows_video_decoder_service.dart';
import 'package:mirroring/ui/controllers/lan_mirroring_controller.dart';
import 'package:mirroring/ui/controllers/mirroring_controller.dart';
import 'package:mirroring/ui/screens/home_screen.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';

class FakeVideoDecoderBackend extends VideoDecoderBackend {
  int createdCount = 0;
  int decodedFrames = 0;
  int resetCount = 0;
  int disposedCount = 0;
  final List<Uint8List> receivedPayloads = [];

  @override
  Future<int?> createTexture() async {
    createdCount++;
    return 42;
  }

  @override
  Future<DecodedFrameResult> decodeFrame({
    required Uint8List bytes,
    required int width,
    required int height,
  }) async {
    decodedFrames++;
    receivedPayloads.add(bytes);
    return DecodedFrameResult(ok: true, width: width, height: height);
  }

  @override
  Future<void> resetDecoder() async {
    resetCount++;
  }

  @override
  Future<void> disposeTexture() async {
    disposedCount++;
  }
}

void main() {
  group('LanDiscoveryService', () {
    test('discovers multiple Android devices, deduplicates, handles IP change and timeout',
        () {
      final service = LanDiscoveryService(
        offlineTimeout: const Duration(seconds: 7),
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      final phone1 = const DiscoveryBeacon(
        deviceId: 'android_phone_01',
        deviceName: 'Pixel 8',
        deviceType: MirrorDeviceType.androidCompanion,
        controlPort: 45455,
        availability: DeviceAvailability.available,
        timestampMs: 1000,
      ).toJsonString();

      final phone2 = const DiscoveryBeacon(
        deviceId: 'android_phone_02',
        deviceName: 'Galaxy S24',
        deviceType: MirrorDeviceType.androidCompanion,
        controlPort: 45455,
        availability: DeviceAvailability.available,
        timestampMs: 1000,
      ).toJsonString();

      final foreignPacket = '{"hello":"world"}';
      final windowsBeacon = const DiscoveryBeacon(
        deviceId: 'win_other_pc',
        deviceName: 'OTHER-PC',
        deviceType: MirrorDeviceType.windowsHost,
        controlPort: 0,
        availability: DeviceAvailability.available,
        timestampMs: 1000,
      ).toJsonString();

      expect(service.processIncomingPacket(foreignPacket, '192.168.1.99', now: t0),
          isFalse);
      expect(service.processIncomingPacket(windowsBeacon, '192.168.1.20', now: t0),
          isFalse);
      expect(service.processIncomingPacket(phone1, '192.168.1.30', now: t0),
          isTrue);
      expect(service.processIncomingPacket(phone2, '192.168.1.31', now: t0),
          isTrue);
      // Duplicate beacon with new IP updates existing entry rather than duplicating
      expect(
        service.processIncomingPacket(
          phone1,
          '192.168.1.130',
          now: t0.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );

      final devices = service.currentDevices;
      expect(devices.length, 2);
      final pixel = devices.firstWhere((d) => d.deviceId == 'android_phone_01');
      expect(pixel.ipAddress, '192.168.1.130');

      // Prune at t0 + 8s: phone2 (last seen at t0) expires, pixel (last seen at t0+2s) stays
      final pruned = service.pruneOfflineDevices(t0.add(const Duration(seconds: 8)));
      expect(pruned, isTrue);
      expect(service.currentDevices.length, 1);
      expect(service.currentDevices.first.deviceId, 'android_phone_01');

      service.dispose();
    });
  });

  group('LanSessionClient loopback integration', () {
    test('completes pairing approval, stream auth, frame decode, clipboard push, and clean stop',
        () async {
      final token = 'TestSessionToken_0123456789abcdef0123456789';
      final receivedControlTypes = <ControlMessageType>[];
      String? receivedClipboard;
      String? receivedInputAction;
      String? receivedInputText;
      List<dynamic>? receivedGesturePoints;
      String? receivedStopReason;
      final sessionStoppedCompleter = Completer<void>();

      // Start loopback H.264 TCP stream server
      final streamServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      streamServer.listen((socket) async {
        final lines = utf8.decoder.bind(socket).transform(const LineSplitter());
        final firstLine = await lines.first;
        final auth = jsonDecode(firstLine) as Map<String, dynamic>;
        expect(auth['sessionToken'], token);

        socket.write('{"accepted":true}\n');
        await socket.flush();

        // Send a config frame + keyframe
        final cfg = StreamFrame(
          header: const StreamFrameHeader(
            frameType: StreamFrameType.config,
            rotationQuarterTurns: 0,
            width: 720,
            height: 1280,
            timestampUs: 1000,
            payloadLength: 6,
          ),
          payload: Uint8List.fromList([0, 0, 0, 1, 0x67, 0x42]),
        );
        final key = StreamFrame(
          header: const StreamFrameHeader(
            frameType: StreamFrameType.keyFrame,
            rotationQuarterTurns: 0,
            width: 720,
            height: 1280,
            timestampUs: 33333,
            payloadLength: 5,
          ),
          payload: Uint8List.fromList([0, 0, 0, 1, 0x65]),
        );
        socket.add(cfg.encodeFullFrame());
        socket.add(key.encodeFullFrame());
        await socket.flush();
      });

      // Start loopback WebSocket control server
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      httpServer.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((raw) {
          final msg = ControlMessage.tryParse(raw as String);
          if (msg == null) return;
          receivedControlTypes.add(msg.type);

          switch (msg.type) {
            case ControlMessageType.pairRequest:
              ws.add(
                ControlMessage.pairResponse(
                  requestId: msg.payload['requestId'] as String,
                  accepted: true,
                  sessionToken: token,
                  streamPort: streamServer.port,
                  deviceId: 'android_loopback_1',
                  deviceName: 'Loopback Phone',
                ).toJsonString(),
              );
              break;
            case ControlMessageType.sessionStart:
              ws.add(
                ControlMessage.sessionAck(
                  sessionToken: token,
                  width: 720,
                  height: 1280,
                  rotation: 0,
                  streamPort: streamServer.port,
                  accessibilityEnabled: true,
                ).toJsonString(),
              );
              break;
            case ControlMessageType.clipboardPush:
              receivedClipboard = msg.payload['text'] as String?;
              break;
            case ControlMessageType.inputGesture:
              receivedGesturePoints = msg.payload['points'] as List<dynamic>?;
              break;
            case ControlMessageType.inputAction:
              receivedInputAction = msg.payload['action'] as String?;
              break;
            case ControlMessageType.inputText:
              receivedInputText = msg.payload['text'] as String?;
              break;
            case ControlMessageType.sessionStop:
              receivedStopReason = msg.payload['reason'] as String?;
              if (!sessionStoppedCompleter.isCompleted) {
                sessionStoppedCompleter.complete();
              }
              break;
            default:
              break;
          }
        });
      });

      final decoder = FakeVideoDecoderBackend();
      final updates = <LanSessionUpdate>[];
      final streamingCompleter = Completer<void>();

      final client = LanSessionClient(
        decoder: decoder,
        onUpdate: (u) {
          updates.add(u);
          if (u.status == WindowsDeviceStatus.streaming &&
              !streamingCompleter.isCompleted) {
            streamingCompleter.complete();
          }
        },
      );

      final device = DiscoveredDevice(
        deviceId: 'android_loopback_1',
        deviceName: 'Loopback Phone',
        deviceType: MirrorDeviceType.androidCompanion,
        ipAddress: '127.0.0.1',
        controlPort: httpServer.port,
        protocolVersion: 1,
        availability: DeviceAvailability.available,
        status: WindowsDeviceStatus.available,
        lastSeenAt: DateTime.now(),
      );

      await client.connectAndStart(device);
      await streamingCompleter.future.timeout(const Duration(seconds: 5));
      for (var i = 0; i < 20 && decoder.decodedFrames < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }

      expect(decoder.createdCount, 1);
      expect(decoder.decodedFrames, 2);
      expect(client.status, WindowsDeviceStatus.streaming);

      final pushed = await client.pushClipboard('Hello Android');
      expect(pushed, isTrue);

      expect(
        client.sendTouchGesture(
          points: [
            {'x': 0.5, 'y': 0.5},
          ],
          durationMs: 45,
        ),
        isTrue,
      );
      expect(client.sendInputAction('back'), isTrue);
      expect(client.sendInputText('Xin chào'), isTrue);

      await client.stopSession(reason: 'Test stop', notifyPeer: true);
      await sessionStoppedCompleter.future.timeout(const Duration(seconds: 3));

      expect(receivedClipboard, 'Hello Android');
      expect(receivedGesturePoints?.length, 1);
      expect(receivedInputAction, 'back');
      expect(receivedInputText, 'Xin chào');
      expect(receivedStopReason, 'Test stop');
      expect(receivedControlTypes, contains(ControlMessageType.pairRequest));
      expect(receivedControlTypes, contains(ControlMessageType.sessionStart));
      expect(receivedControlTypes, contains(ControlMessageType.sessionStop));

      await client.dispose();
      await streamServer.close();
      await httpServer.close(force: true);
    });

    test('handles rejected connection request cleanly', () async {
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      httpServer.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((raw) {
          final msg = ControlMessage.tryParse(raw as String);
          if (msg?.type == ControlMessageType.pairRequest) {
            ws.add(
              ControlMessage.pairResponse(
                requestId: msg!.payload['requestId'] as String,
                accepted: false,
                reason: 'Từ chối thử nghiệm',
              ).toJsonString(),
            );
          }
        });
      });

      final decoder = FakeVideoDecoderBackend();
      final failedCompleter = Completer<LanSessionUpdate>();
      final client = LanSessionClient(
        decoder: decoder,
        onUpdate: (u) {
          if (u.status == WindowsDeviceStatus.connectionFailed &&
              !failedCompleter.isCompleted) {
            failedCompleter.complete(u);
          }
        },
      );

      final device = DiscoveredDevice(
        deviceId: 'android_reject_1',
        deviceName: 'Reject Phone',
        deviceType: MirrorDeviceType.androidCompanion,
        ipAddress: '127.0.0.1',
        controlPort: httpServer.port,
        protocolVersion: 1,
        availability: DeviceAvailability.available,
        status: WindowsDeviceStatus.available,
        lastSeenAt: DateTime.now(),
      );

      await client.connectAndStart(device);
      final failedUpdate =
          await failedCompleter.future.timeout(const Duration(seconds: 5));

      expect(failedUpdate.errorMessage, 'Từ chối thử nghiệm');
      expect(decoder.decodedFrames, 0);

      await client.dispose();
      await httpServer.close(force: true);
    });
  });

  group('HomeScreen with LanMirroringController UI', () {
    testWidgets('shows LAN mode by default and allows switching to ADB mode',
        (tester) async {
      final discovery = LanDiscoveryService();
      final lanController = LanMirroringController(
        discoveryService: discovery,
        decoderBackend: FakeVideoDecoderBackend(),
        autoStart: false,
      );
      final adbController = MirroringController(autoInitialize: false);

      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            controller: adbController,
            lanController: lanController,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LAN Không dây'), findsOneWidget);
      expect(find.text('ADB & scrcpy'), findsOneWidget);
      expect(find.text('THIẾT BỊ ANDROID TRONG LAN'), findsOneWidget);

      // Switch to ADB mode
      await tester.tap(find.text('ADB & scrcpy'));
      await tester.pump();

      expect(find.text('KẾT NỐI THIẾT BỊ'), findsOneWidget);
      expect(find.text('Kết nối ADB'), findsOneWidget);

      adbController.dispose();
      await lanController.cleanup();
    });
  });
}
