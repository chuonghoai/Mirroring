import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import 'windows_device_identity.dart';

class LanDiscoveryService {
  final Duration beaconInterval;
  final Duration offlineTimeout;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;
  String? _localDeviceId;
  bool _isRunning = false;

  final Map<String, DiscoveredDevice> _devices = {};
  final StreamController<List<DiscoveredDevice>> _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  DeviceAvailability Function() availabilityProvider;

  LanDiscoveryService({
    this.beaconInterval = MirroringProtocolConstants.beaconInterval,
    this.offlineTimeout = MirroringProtocolConstants.deviceOfflineTimeout,
    DeviceAvailability Function()? availabilityProvider,
  }) : availabilityProvider =
            availabilityProvider ?? (() => DeviceAvailability.available);

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;
  List<DiscoveredDevice> get currentDevices =>
      _devices.values.toList()..sort((a, b) => a.deviceName.compareTo(b.deviceName));
  bool get isRunning => _isRunning;
  String? get localDeviceId => _localDeviceId;

  Future<void> start({String? overrideDeviceId}) async {
    if (_isRunning) return;
    _localDeviceId =
        overrideDeviceId ?? await WindowsDeviceIdentity.getOrCreateDeviceId();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        MirroringProtocolConstants.discoveryPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              final raw = utf8.decode(datagram.data, allowMalformed: true);
              processIncomingPacket(raw, datagram.address.address);
            }
          }
        },
        onError: (Object err) {
          debugPrint('LAN discovery socket error: $err');
        },
      );
      _isRunning = true;
    } catch (e) {
      debugPrint('Failed to bind UDP port ${MirroringProtocolConstants.discoveryPort}: $e');
      // Fallback ephemeral socket for sending beacons if port is already occupied
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _socket!.broadcastEnabled = true;
        _isRunning = true;
      } catch (inner) {
        debugPrint('Failed to bind fallback discovery UDP socket: $inner');
        return;
      }
    }

    await sendBeaconNow();
    _beaconTimer = Timer.periodic(beaconInterval, (_) => sendBeaconNow());
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => pruneOfflineDevices(DateTime.now()),
    );
  }

  Future<void> sendBeaconNow() async {
    final socket = _socket;
    final id = _localDeviceId;
    if (socket == null || id == null) return;

    final beacon = DiscoveryBeacon(
      deviceId: id,
      deviceName: WindowsDeviceIdentity.getHostName(),
      deviceType: MirrorDeviceType.windowsHost,
      controlPort: 0,
      availability: availabilityProvider(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    final bytes = utf8.encode(beacon.toJsonString());

    final targets = await _resolveBroadcastTargets();
    for (final target in targets) {
      try {
        socket.send(bytes, target, MirroringProtocolConstants.discoveryPort);
      } catch (_) {}
    }
  }

  /// Processes an incoming UDP beacon payload. Exposed for deterministic unit testing.
  bool processIncomingPacket(String raw, String senderIp, {DateTime? now}) {
    final beacon = DiscoveryBeacon.tryParse(raw);
    if (beacon == null) return false;
    if (_localDeviceId != null && beacon.deviceId == _localDeviceId) return false;
    if (beacon.deviceType != MirrorDeviceType.androidCompanion) return false;

    final timestamp = now ?? DateTime.now();
    final existing = _devices[beacon.deviceId];
    final mappedStatus = switch (beacon.availability) {
      DeviceAvailability.available => WindowsDeviceStatus.available,
      DeviceAvailability.busy ||
      DeviceAvailability.streaming =>
        WindowsDeviceStatus.unavailable,
      DeviceAvailability.offline => WindowsDeviceStatus.disconnected,
    };

    final updated = DiscoveredDevice(
      deviceId: beacon.deviceId,
      deviceName: beacon.deviceName,
      deviceType: beacon.deviceType,
      ipAddress: senderIp,
      controlPort: beacon.controlPort,
      protocolVersion: beacon.protocolVersion,
      availability: beacon.availability,
      status: existing != null &&
              existing.status != WindowsDeviceStatus.available &&
              existing.status != WindowsDeviceStatus.unavailable &&
              existing.status != WindowsDeviceStatus.disconnected
          ? existing.status
          : mappedStatus,
      lastSeenAt: timestamp,
      lastError: existing?.lastError,
    );

    final changed = existing == null ||
        existing.ipAddress != updated.ipAddress ||
        existing.deviceName != updated.deviceName ||
        existing.controlPort != updated.controlPort ||
        existing.availability != updated.availability;

    _devices[beacon.deviceId] = updated;
    if (changed) {
      _emitDevices();
    }
    return true;
  }

  /// Removes devices that have not sent a beacon within [offlineTimeout].
  bool pruneOfflineDevices(DateTime now) {
    var removed = false;
    final staleIds = <String>[];
    for (final entry in _devices.entries) {
      if (now.difference(entry.value.lastSeenAt) > offlineTimeout) {
        staleIds.add(entry.key);
      }
    }
    for (final id in staleIds) {
      _devices.remove(id);
      removed = true;
    }
    if (removed) {
      _emitDevices();
    }
    return removed;
  }

  void updateDeviceStatus(
    String deviceId,
    WindowsDeviceStatus status, {
    String? error,
    bool clearError = false,
  }) {
    final existing = _devices[deviceId];
    if (existing == null) return;
    _devices[deviceId] = existing.copyWith(
      status: status,
      lastError: error,
      clearError: clearError,
    );
    _emitDevices();
  }

  Future<List<InternetAddress>> _resolveBroadcastTargets() async {
    final targets = <String, InternetAddress>{
      '255.255.255.255': InternetAddress('255.255.255.255'),
    };
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final directed = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            targets[directed] = InternetAddress(directed);
          }
        }
      }
    } catch (_) {}
    return targets.values.toList();
  }

  void _emitDevices() {
    if (!_devicesController.isClosed) {
      _devicesController.add(currentDevices);
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    _emitDevices();
  }

  Future<void> dispose() async {
    await stop();
    await _devicesController.close();
  }
}
