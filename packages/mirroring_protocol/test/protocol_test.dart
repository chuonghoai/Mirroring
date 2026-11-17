import 'dart:typed_data';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('DiscoveryBeacon', () {
    test('serializes and parses valid Android Companion beacon', () {
      const beacon = DiscoveryBeacon(
        deviceId: 'android_abc12345',
        deviceName: 'Pixel 8 Pro',
        deviceType: MirrorDeviceType.androidCompanion,
        controlPort: 45455,
        availability: DeviceAvailability.available,
        timestampMs: 1700000000000,
      );

      final parsed = DiscoveryBeacon.tryParse(beacon.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, 'android_abc12345');
      expect(parsed.deviceName, 'Pixel 8 Pro');
      expect(parsed.deviceType, MirrorDeviceType.androidCompanion);
      expect(parsed.controlPort, 45455);
      expect(parsed.availability, DeviceAvailability.available);
    });

    test('rejects invalid magic or foreign JSON packets', () {
      expect(DiscoveryBeacon.tryParse('{"magic":"OTHER"}'), isNull);
      expect(DiscoveryBeacon.tryParse('not json'), isNull);
      expect(
        DiscoveryBeacon.tryParse(
          '{"magic":"MIRRORING_LAN_V1","protocolVersion":99,"deviceId":"abc12345","deviceName":"Phone","deviceType":"androidCompanion","controlPort":45455,"availability":"available","timestampMs":1}',
        ),
        isNull,
      );
      // Android companion with port 0 must be rejected
      expect(
        DiscoveryBeacon.tryParse(
          '{"magic":"MIRRORING_LAN_V1","protocolVersion":1,"deviceId":"abc12345","deviceName":"Phone","deviceType":"androidCompanion","controlPort":0,"availability":"available","timestampMs":1}',
        ),
        isNull,
      );
    });

    test('sanitizes control characters from deviceName', () {
      final sanitized = ProtocolSecurity.sanitizeDeviceName('My\nPhone\r\t01');
      expect(sanitized, 'MyPhone01');
    });
  });

  group('ControlMessage', () {
    test('roundtrips pairRequest and pairResponse', () {
      final req = ControlMessage.pairRequest(
        requestId: 'req-1234',
        windowsDeviceId: 'win_host_001',
        windowsDeviceName: 'WORKSTATION',
        nonce: 'nonce-abc',
        timestampMs: 123456789,
      );
      final decodedReq = ControlMessage.tryParse(req.toJsonString());
      expect(decodedReq, isNotNull);
      expect(decodedReq!.type, ControlMessageType.pairRequest);
      expect(decodedReq.payload['windowsDeviceName'], 'WORKSTATION');

      final res = ControlMessage.pairResponse(
        requestId: 'req-1234',
        accepted: true,
        sessionToken: 'a' * 48,
        streamPort: 45456,
      );
      final decodedRes = ControlMessage.tryParse(res.toJsonString());
      expect(decodedRes, isNotNull);
      expect(decodedRes!.type, ControlMessageType.pairResponse);
      expect(decodedRes.payload['accepted'], isTrue);
      expect(decodedRes.payload['streamPort'], 45456);
    });

    test('roundtrips inputGesture, inputAction, inputText, and accessibilityStatus', () {
      final token = 'a' * 40;
      final gesture = ControlMessage.inputGesture(
        sessionToken: token,
        points: [
          {'x': 0.25, 'y': 0.5},
          {'x': 0.75, 'y': 0.5},
        ],
        durationMs: 180,
      );
      final parsedGesture = ControlMessage.tryParse(gesture.toJsonString());
      expect(parsedGesture?.type, ControlMessageType.inputGesture);
      expect(parsedGesture?.payload['durationMs'], 180);

      final action = ControlMessage.inputAction(
        sessionToken: token,
        action: 'back',
      );
      expect(
        ControlMessage.tryParse(action.toJsonString())?.payload['action'],
        'back',
      );

      final text = ControlMessage.inputText(
        sessionToken: token,
        text: 'Xin chào Việt Nam',
      );
      expect(
        ControlMessage.tryParse(text.toJsonString())?.payload['text'],
        'Xin chào Việt Nam',
      );

      final acc = ControlMessage.accessibilityStatus(
        sessionToken: token,
        enabled: true,
      );
      expect(
        ControlMessage.tryParse(acc.toJsonString())?.payload['enabled'],
        isTrue,
      );
    });

    test('rejects unknown message type or wrong protocol version', () {
      expect(
        ControlMessage.tryParse(
          '{"protocolVersion":1,"type":"unknownAction","payload":{}}',
        ),
        isNull,
      );
      expect(
        ControlMessage.tryParse(
          '{"protocolVersion":2,"type":"heartbeat","payload":{}}',
        ),
        isNull,
      );
    });
  });

  group('StreamFrameParser', () {
    test('parses frames split across arbitrary TCP chunks', () {
      final frame1 = StreamFrame(
        header: const StreamFrameHeader(
          frameType: StreamFrameType.config,
          rotationQuarterTurns: 0,
          width: 720,
          height: 1600,
          timestampUs: 1000,
          payloadLength: 6,
        ),
        payload: Uint8List.fromList([0, 0, 0, 1, 0x67, 0x42]),
      );
      final frame2 = StreamFrame(
        header: const StreamFrameHeader(
          frameType: StreamFrameType.keyFrame,
          rotationQuarterTurns: 1,
          width: 1600,
          height: 720,
          timestampUs: 33333,
          payloadLength: 5,
        ),
        payload: Uint8List.fromList([0, 0, 0, 1, 0x65]),
      );

      final combined = Uint8List.fromList([
        ...frame1.encodeFullFrame(),
        ...frame2.encodeFullFrame(),
      ]);

      final parser = StreamFrameParser();
      final out = <StreamFrame>[];
      // Feed 5 bytes at a time
      for (var i = 0; i < combined.length; i += 5) {
        final end = (i + 5 < combined.length) ? i + 5 : combined.length;
        out.addAll(parser.addBytes(Uint8List.sublistView(combined, i, end)));
      }

      expect(out.length, 2);
      expect(out[0].header.frameType, StreamFrameType.config);
      expect(out[0].header.width, 720);
      expect(out[0].header.height, 1600);
      expect(out[0].payload, [0, 0, 0, 1, 0x67, 0x42]);

      expect(out[1].header.frameType, StreamFrameType.keyFrame);
      expect(out[1].header.rotationQuarterTurns, 1);
      expect(out[1].header.width, 1600);
      expect(out[1].header.height, 720);
      expect(out[1].payload, [0, 0, 0, 1, 0x65]);
    });

    test('throws FormatException on corrupted stream magic', () {
      final parser = StreamFrameParser();
      expect(
        () => parser.addBytes(Uint8List(24)),
        throwsFormatException,
      );
    });
  });

  group('ProtocolSecurity', () {
    test('validates tokens and constant-time equality', () {
      final token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-';
      expect(ProtocolSecurity.isValidSessionToken(token), isTrue);
      expect(ProtocolSecurity.isValidSessionToken('short'), isFalse);
      expect(ProtocolSecurity.constantTimeEquals(token, token), isTrue);
      expect(
        ProtocolSecurity.constantTimeEquals(token, '${token.substring(0, token.length - 1)}X'),
        isFalse,
      );
    });
  });
}
