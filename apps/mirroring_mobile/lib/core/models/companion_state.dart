enum CompanionSessionStatus {
  idle,
  pendingApproval,
  awaitingCapturePermission,
  streaming,
  reconnecting;

  static CompanionSessionStatus fromNative(String? value) {
    switch (value) {
      case 'PENDING_APPROVAL':
        return CompanionSessionStatus.pendingApproval;
      case 'AWAITING_CAPTURE_PERMISSION':
        return CompanionSessionStatus.awaitingCapturePermission;
      case 'STREAMING':
        return CompanionSessionStatus.streaming;
      case 'RECONNECTING':
        return CompanionSessionStatus.reconnecting;
      case 'IDLE':
      default:
        return CompanionSessionStatus.idle;
    }
  }
}

class DiscoveredWindowsHost {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final int controlPort;
  final String availability;
  final int lastSeenAtMs;

  const DiscoveredWindowsHost({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.controlPort,
    required this.availability,
    required this.lastSeenAtMs,
  });

  factory DiscoveredWindowsHost.fromMap(Map<Object?, Object?> map) {
    return DiscoveredWindowsHost(
      deviceId: (map['deviceId'] as String?) ?? '',
      deviceName: (map['deviceName'] as String?) ?? 'Windows PC',
      ipAddress: (map['ipAddress'] as String?) ?? '',
      controlPort: (map['controlPort'] as int?) ?? 0,
      availability: (map['availability'] as String?) ?? 'available',
      lastSeenAtMs: (map['lastSeenAtMs'] as int?) ?? 0,
    );
  }
}

class IncomingPairRequest {
  final String requestId;
  final String windowsDeviceId;
  final String windowsDeviceName;
  final String remoteIp;
  final int createdAtMs;
  final int expiresAtMs;

  const IncomingPairRequest({
    required this.requestId,
    required this.windowsDeviceId,
    required this.windowsDeviceName,
    required this.remoteIp,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  int secondsRemaining(int nowMs) {
    final diff = expiresAtMs - nowMs;
    if (diff <= 0) return 0;
    return (diff / 1000).ceil();
  }

  factory IncomingPairRequest.fromMap(Map<Object?, Object?> map) {
    return IncomingPairRequest(
      requestId: (map['requestId'] as String?) ?? '',
      windowsDeviceId: (map['windowsDeviceId'] as String?) ?? '',
      windowsDeviceName: (map['windowsDeviceName'] as String?) ?? 'Windows PC',
      remoteIp: (map['remoteIp'] as String?) ?? '',
      createdAtMs: (map['createdAtMs'] as int?) ?? 0,
      expiresAtMs: (map['expiresAtMs'] as int?) ?? 0,
    );
  }
}

class CompanionAppState {
  final CompanionSessionStatus sessionStatus;
  final String deviceId;
  final String deviceName;
  final List<String> localIps;
  final int controlPort;
  final int streamPort;
  final List<DiscoveredWindowsHost> discoveredHosts;
  final IncomingPairRequest? pendingRequest;
  final String? connectedWindowsId;
  final String? connectedWindowsName;
  final int streamWidth;
  final int streamHeight;
  final int streamRotation;
  final int reconnectSecondsLeft;
  final String? statusMessage;
  final bool hasNotificationPermission;
  final bool accessibilityEnabled;
  final bool isResponding;

  const CompanionAppState({
    this.sessionStatus = CompanionSessionStatus.idle,
    this.deviceId = '',
    this.deviceName = 'Android',
    this.localIps = const [],
    this.controlPort = 0,
    this.streamPort = 0,
    this.discoveredHosts = const [],
    this.pendingRequest,
    this.connectedWindowsId,
    this.connectedWindowsName,
    this.streamWidth = 0,
    this.streamHeight = 0,
    this.streamRotation = 0,
    this.reconnectSecondsLeft = 0,
    this.statusMessage,
    this.hasNotificationPermission = true,
    this.accessibilityEnabled = false,
    this.isResponding = false,
  });

  bool get isStreaming => sessionStatus == CompanionSessionStatus.streaming;
  bool get isReconnecting => sessionStatus == CompanionSessionStatus.reconnecting;
  bool get isActiveSession => isStreaming || isReconnecting;

  CompanionAppState copyWith({
    CompanionSessionStatus? sessionStatus,
    String? deviceId,
    String? deviceName,
    List<String>? localIps,
    int? controlPort,
    int? streamPort,
    List<DiscoveredWindowsHost>? discoveredHosts,
    IncomingPairRequest? pendingRequest,
    bool clearPendingRequest = false,
    String? connectedWindowsId,
    bool clearConnectedWindowsId = false,
    String? connectedWindowsName,
    bool clearConnectedWindowsName = false,
    int? streamWidth,
    int? streamHeight,
    int? streamRotation,
    int? reconnectSecondsLeft,
    String? statusMessage,
    bool clearStatusMessage = false,
    bool? hasNotificationPermission,
    bool? accessibilityEnabled,
    bool? isResponding,
  }) {
    return CompanionAppState(
      sessionStatus: sessionStatus ?? this.sessionStatus,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      localIps: localIps ?? this.localIps,
      controlPort: controlPort ?? this.controlPort,
      streamPort: streamPort ?? this.streamPort,
      discoveredHosts: discoveredHosts ?? this.discoveredHosts,
      pendingRequest: clearPendingRequest
          ? null
          : (pendingRequest ?? this.pendingRequest),
      connectedWindowsId: clearConnectedWindowsId
          ? null
          : (connectedWindowsId ?? this.connectedWindowsId),
      connectedWindowsName: clearConnectedWindowsName
          ? null
          : (connectedWindowsName ?? this.connectedWindowsName),
      streamWidth: streamWidth ?? this.streamWidth,
      streamHeight: streamHeight ?? this.streamHeight,
      streamRotation: streamRotation ?? this.streamRotation,
      reconnectSecondsLeft: reconnectSecondsLeft ?? this.reconnectSecondsLeft,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      hasNotificationPermission:
          hasNotificationPermission ?? this.hasNotificationPermission,
      accessibilityEnabled: accessibilityEnabled ?? this.accessibilityEnabled,
      isResponding: isResponding ?? this.isResponding,
    );
  }

  factory CompanionAppState.fromNativeMap(
    Map<Object?, Object?> map, {
    bool hasNotificationPermission = true,
    bool isResponding = false,
  }) {
    final rawHosts = map['discoveredHosts'] as List<Object?>? ?? const [];
    final hosts = rawHosts
        .whereType<Map<Object?, Object?>>()
        .map(DiscoveredWindowsHost.fromMap)
        .toList();

    final rawPending = map['pendingRequest'] as Map<Object?, Object?>?;
    final rawIps = map['localIps'] as List<Object?>? ?? const [];

    return CompanionAppState(
      sessionStatus: CompanionSessionStatus.fromNative(
        map['sessionState'] as String?,
      ),
      deviceId: (map['deviceId'] as String?) ?? '',
      deviceName: (map['deviceName'] as String?) ?? 'Android',
      localIps: rawIps.whereType<String>().toList(),
      controlPort: (map['controlPort'] as int?) ?? 0,
      streamPort: (map['streamPort'] as int?) ?? 0,
      discoveredHosts: hosts,
      pendingRequest: rawPending != null
          ? IncomingPairRequest.fromMap(rawPending)
          : null,
      connectedWindowsId: map['connectedWindowsId'] as String?,
      connectedWindowsName: map['connectedWindowsName'] as String?,
      streamWidth: (map['streamWidth'] as int?) ?? 0,
      streamHeight: (map['streamHeight'] as int?) ?? 0,
      streamRotation: (map['streamRotation'] as int?) ?? 0,
      reconnectSecondsLeft: (map['reconnectSecondsLeft'] as int?) ?? 0,
      statusMessage: map['statusMessage'] as String?,
      hasNotificationPermission: hasNotificationPermission,
      accessibilityEnabled: (map['accessibilityEnabled'] as bool?) ?? false,
      isResponding: isResponding,
    );
  }
}
