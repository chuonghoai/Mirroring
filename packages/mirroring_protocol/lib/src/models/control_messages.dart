import 'dart:convert';
import '../constants.dart';
import '../security/token_validator.dart';

enum ControlMessageType {
  pairRequest,
  pairResponse,
  pairCancel,
  sessionStart,
  sessionAck,
  heartbeat,
  heartbeatAck,
  sessionStop,
  streamConfig,
  clipboardPush,
  error;

  static ControlMessageType? fromWire(String? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// JSON message exchanged over the WebSocket control channel.
class ControlMessage {
  final int protocolVersion;
  final ControlMessageType type;
  final Map<String, dynamic> payload;

  const ControlMessage({
    this.protocolVersion = MirroringProtocolConstants.protocolVersion,
    required this.type,
    required this.payload,
  });

  String toJsonString() => jsonEncode({
        'protocolVersion': protocolVersion,
        'type': type.name,
        'payload': payload,
      });

  static ControlMessage? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final version = decoded['protocolVersion'];
      if (version is! int ||
          version != MirroringProtocolConstants.protocolVersion) {
        return null;
      }

      final type = ControlMessageType.fromWire(decoded['type'] as String?);
      if (type == null) return null;

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) return null;

      return ControlMessage(
        protocolVersion: version,
        type: type,
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }

  factory ControlMessage.pairRequest({
    required String requestId,
    required String windowsDeviceId,
    required String windowsDeviceName,
    required String nonce,
    required int timestampMs,
  }) {
    return ControlMessage(
      type: ControlMessageType.pairRequest,
      payload: {
        'requestId': requestId,
        'windowsDeviceId': windowsDeviceId,
        'windowsDeviceName':
            ProtocolSecurity.sanitizeDeviceName(windowsDeviceName),
        'nonce': nonce,
        'timestampMs': timestampMs,
      },
    );
  }

  factory ControlMessage.pairResponse({
    required String requestId,
    required bool accepted,
    String? reason,
    String? sessionToken,
    int? streamPort,
    String? deviceId,
    String? deviceName,
  }) {
    return ControlMessage(
      type: ControlMessageType.pairResponse,
      payload: {
        'requestId': requestId,
        'accepted': accepted,
        'reason': ?reason,
        'sessionToken': ?sessionToken,
        'streamPort': ?streamPort,
        'deviceId': ?deviceId,
        'deviceName': ?deviceName,
      },
    );
  }

  factory ControlMessage.pairCancel({
    required String requestId,
    required String reason,
  }) {
    return ControlMessage(
      type: ControlMessageType.pairCancel,
      payload: {
        'requestId': requestId,
        'reason': reason,
      },
    );
  }

  factory ControlMessage.sessionStart({
    required String sessionToken,
    required String windowsDeviceId,
    int maxDimension = 1280,
    int targetFps = 30,
    int bitrate = 4000000,
  }) {
    return ControlMessage(
      type: ControlMessageType.sessionStart,
      payload: {
        'sessionToken': sessionToken,
        'windowsDeviceId': windowsDeviceId,
        'maxDimension': maxDimension,
        'targetFps': targetFps,
        'bitrate': bitrate,
      },
    );
  }

  factory ControlMessage.sessionAck({
    required String sessionToken,
    required int width,
    required int height,
    required int rotation,
    required int streamPort,
  }) {
    return ControlMessage(
      type: ControlMessageType.sessionAck,
      payload: {
        'sessionToken': sessionToken,
        'width': width,
        'height': height,
        'rotation': rotation,
        'streamPort': streamPort,
      },
    );
  }

  factory ControlMessage.heartbeat({
    required String sessionToken,
    required int seq,
    required int timestampMs,
  }) {
    return ControlMessage(
      type: ControlMessageType.heartbeat,
      payload: {
        'sessionToken': sessionToken,
        'seq': seq,
        'timestampMs': timestampMs,
      },
    );
  }

  factory ControlMessage.heartbeatAck({
    required String sessionToken,
    required int seq,
    required int timestampMs,
  }) {
    return ControlMessage(
      type: ControlMessageType.heartbeatAck,
      payload: {
        'sessionToken': sessionToken,
        'seq': seq,
        'timestampMs': timestampMs,
      },
    );
  }

  factory ControlMessage.sessionStop({
    required String sessionToken,
    required String reason,
  }) {
    return ControlMessage(
      type: ControlMessageType.sessionStop,
      payload: {
        'sessionToken': sessionToken,
        'reason': reason,
      },
    );
  }

  factory ControlMessage.streamConfig({
    required String sessionToken,
    required int width,
    required int height,
    required int rotation,
  }) {
    return ControlMessage(
      type: ControlMessageType.streamConfig,
      payload: {
        'sessionToken': sessionToken,
        'width': width,
        'height': height,
        'rotation': rotation,
      },
    );
  }

  factory ControlMessage.clipboardPush({
    required String sessionToken,
    required String text,
  }) {
    return ControlMessage(
      type: ControlMessageType.clipboardPush,
      payload: {
        'sessionToken': sessionToken,
        'text': text,
      },
    );
  }

  factory ControlMessage.error({
    required String code,
    required String message,
  }) {
    return ControlMessage(
      type: ControlMessageType.error,
      payload: {
        'code': code,
        'message': message,
      },
    );
  }
}
