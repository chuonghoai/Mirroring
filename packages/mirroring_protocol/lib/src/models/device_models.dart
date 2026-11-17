import 'dart:convert';
import '../constants.dart';
import '../security/token_validator.dart';

enum MirrorDeviceType {
  windowsHost,
  androidCompanion;

  static MirrorDeviceType? fromWire(String? raw) {
    switch (raw) {
      case 'windowsHost':
        return MirrorDeviceType.windowsHost;
      case 'androidCompanion':
        return MirrorDeviceType.androidCompanion;
      default:
        return null;
    }
  }
}

enum DeviceAvailability {
  available,
  busy,
  streaming,
  offline;

  static DeviceAvailability fromWire(String? raw) {
    switch (raw) {
      case 'available':
        return DeviceAvailability.available;
      case 'busy':
        return DeviceAvailability.busy;
      case 'streaming':
        return DeviceAvailability.streaming;
      case 'offline':
        return DeviceAvailability.offline;
      default:
        return DeviceAvailability.available;
    }
  }
}

/// All required connection/session states for the Windows device list.
enum WindowsDeviceStatus {
  available,
  connectionRequested,
  waitingForApproval,
  connecting,
  connected,
  streaming,
  disconnected,
  unavailable,
  connectionFailed,
}

/// UDP discovery beacon broadcast by Mirroring Windows and Android Companion.
class DiscoveryBeacon {
  final String magic;
  final int protocolVersion;
  final String deviceId;
  final String deviceName;
  final MirrorDeviceType deviceType;
  final int controlPort;
  final DeviceAvailability availability;
  final int timestampMs;

  const DiscoveryBeacon({
    this.magic = MirroringProtocolConstants.discoveryMagic,
    this.protocolVersion = MirroringProtocolConstants.protocolVersion,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.controlPort,
    required this.availability,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'magic': magic,
        'protocolVersion': protocolVersion,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': deviceType.name,
        'controlPort': controlPort,
        'availability': availability.name,
        'timestampMs': timestampMs,
      };

  String toJsonString() => jsonEncode(toJson());

  static DiscoveryBeacon? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      if (decoded['magic'] != MirroringProtocolConstants.discoveryMagic) {
        return null;
      }

      final version = decoded['protocolVersion'];
      if (version is! int ||
          version != MirroringProtocolConstants.protocolVersion) {
        return null;
      }

      final deviceId = decoded['deviceId'];
      if (deviceId is! String || !ProtocolSecurity.isValidDeviceId(deviceId)) {
        return null;
      }

      final rawName = decoded['deviceName'];
      if (rawName is! String) return null;
      final deviceName = ProtocolSecurity.sanitizeDeviceName(rawName);

      final deviceType = MirrorDeviceType.fromWire(
        decoded['deviceType'] as String?,
      );
      if (deviceType == null) return null;

      final controlPort = decoded['controlPort'];
      if (controlPort is! int || controlPort < 0 || controlPort > 65535) {
        return null;
      }
      // Android Companion must advertise a valid listening port > 0
      if (deviceType == MirrorDeviceType.androidCompanion &&
          controlPort == 0) {
        return null;
      }

      final availability = DeviceAvailability.fromWire(
        decoded['availability'] as String?,
      );

      final timestampMs = decoded['timestampMs'];
      if (timestampMs is! int) return null;

      return DiscoveryBeacon(
        magic: MirroringProtocolConstants.discoveryMagic,
        protocolVersion: version,
        deviceId: deviceId,
        deviceName: deviceName,
        deviceType: deviceType,
        controlPort: controlPort,
        availability: availability,
        timestampMs: timestampMs,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A discovered peer device on the local network.
class DiscoveredDevice {
  final String deviceId;
  final String deviceName;
  final MirrorDeviceType deviceType;
  final String ipAddress;
  final int controlPort;
  final int protocolVersion;
  final DeviceAvailability availability;
  final WindowsDeviceStatus status;
  final DateTime lastSeenAt;
  final String? lastError;

  const DiscoveredDevice({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.controlPort,
    required this.protocolVersion,
    required this.availability,
    required this.status,
    required this.lastSeenAt,
    this.lastError,
  });

  String get shortId =>
      deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8);

  bool get isAvailableForConnect =>
      availability == DeviceAvailability.available &&
      (status == WindowsDeviceStatus.available ||
          status == WindowsDeviceStatus.disconnected ||
          status == WindowsDeviceStatus.connectionFailed);

  DiscoveredDevice copyWith({
    String? deviceName,
    String? ipAddress,
    int? controlPort,
    DeviceAvailability? availability,
    WindowsDeviceStatus? status,
    DateTime? lastSeenAt,
    String? lastError,
    bool clearError = false,
  }) {
    return DiscoveredDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType,
      ipAddress: ipAddress ?? this.ipAddress,
      controlPort: controlPort ?? this.controlPort,
      protocolVersion: protocolVersion,
      availability: availability ?? this.availability,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
