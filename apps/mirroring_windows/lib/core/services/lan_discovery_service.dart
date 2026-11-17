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
      debugPrint(
        'Failed to bind UDP port ${MirroringProtocolConstants.discoveryPort}: $e',
      );
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

    final bytes = _buildBeaconBytes(id);
    final peerIps = _devices.values.map((d) => d.ipAddress).toSet();
    final lanAddrs = await _getLanInterfaceAddresses();

    var sentViaInterface = false;
    for (final localAddr in lanAddrs) {
      final parts = localAddr.address.split('.');
      if (parts.length != 4) continue;
      final directedBroadcast = InternetAddress(
        '${parts[0]}.${parts[1]}.${parts[2]}.255',
      );

      RawDatagramSocket? ifaceSocket;
      try {
        // Bind directly to the physical LAN IPv4 interface so VPN/WARP virtual
        // adapters do not hijack 255.255.255.255 or subnet broadcasts.
        ifaceSocket = await RawDatagramSocket.bind(localAddr, 0);
        ifaceSocket.broadcastEnabled = true;
        ifaceSocket.send(
          bytes,
          directedBroadcast,
          MirroringProtocolConstants.discoveryPort,
        );
        ifaceSocket.send(
          bytes,
          InternetAddress('255.255.255.255'),
          MirroringProtocolConstants.discoveryPort,
        );
        for (final peerIp in peerIps) {
          ifaceSocket.send(
            bytes,
            InternetAddress(peerIp),
            MirroringProtocolConstants.discoveryPort,
          );
        }
        sentViaInterface = true;
      } catch (_) {
      } finally {
        ifaceSocket?.close();
      }
    }

    if (!sentViaInterface) {
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
        ...peerIps.map(InternetAddress.new),
      ];
      for (final target in targets) {
        try {
          socket.send(bytes, target, MirroringProtocolConstants.discoveryPort);
        } catch (_) {}
      }
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
      if (_isRunning) {
        unawaited(_sendBeaconUnicast(senderIp));
      }
    }
    return true;
  }

  Future<void> _sendBeaconUnicast(String targetIp) async {
    final id = _localDeviceId;
    if (!_isRunning || id == null) return;
    final bytes = _buildBeaconBytes(id);
    final lanAddrs = await _getLanInterfaceAddresses();
    final target = InternetAddress(targetIp);

    for (final localAddr in lanAddrs) {
      RawDatagramSocket? ifaceSocket;
      try {
        ifaceSocket = await RawDatagramSocket.bind(localAddr, 0);
        ifaceSocket.send(bytes, target, MirroringProtocolConstants.discoveryPort);
        return;
      } catch (_) {
      } finally {
        ifaceSocket?.close();
      }
    }

    try {
      _socket?.send(bytes, target, MirroringProtocolConstants.discoveryPort);
    } catch (_) {}
  }

  List<int> _buildBeaconBytes(String deviceId) {
    final beacon = DiscoveryBeacon(
      deviceId: deviceId,
      deviceName: WindowsDeviceIdentity.getHostName(),
      deviceType: MirrorDeviceType.windowsHost,
      controlPort: 0,
      availability: availabilityProvider(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    return utf8.encode(beacon.toJsonString());
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

  Future<List<InternetAddress>> _getLanInterfaceAddresses() async {
    final candidates = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        if (_isVirtualOrTunnelInterface(nameLower)) continue;
        for (final addr in iface.addresses) {
          if (_isUsableLanIpv4(addr.address)) {
            candidates.add(addr);
          }
        }
      }
    } catch (_) {}
    return candidates;
  }

  static bool _isVirtualOrTunnelInterface(String nameLower) {
    return nameLower.contains('warp') ||
        nameLower.contains('cloudflare') ||
        nameLower.contains('tun') ||
        nameLower.contains('tap') ||
        nameLower.contains('wireguard') ||
        nameLower.contains('tailscale') ||
        nameLower.contains('zerotier') ||
        nameLower.contains('vethernet') ||
        nameLower.contains('wsl') ||
        nameLower.contains('virtualbox') ||
        nameLower.contains('vmware') ||
        nameLower.contains('hyper-v');
  }

  static bool _isUsableLanIpv4(String ip) {
    if (ip.startsWith('127.') || ip.startsWith('169.254.')) return false;
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? -1;
      // 172.16.0.2 is often used by Cloudflare WARP / VPNs; allow RFC1918 172.16-31
      // except 172.16.0.2 single-host WARP endpoint.
      if (ip == '172.16.0.2') return false;
      return second >= 16 && second <= 31;
    }
    return false;
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
