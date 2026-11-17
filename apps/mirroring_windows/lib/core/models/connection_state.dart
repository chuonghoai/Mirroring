enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum ScrcpyStatus {
  stopped,
  starting,
  running,
  reopenNeeded,
  error,
}

class MirroringAppState {
  final ConnectionStatus connectionStatus;
  final ScrcpyStatus scrcpyStatus;
  final String? connectedAddress;
  final String? deviceModel;
  final String? errorMessage;
  final bool isCheckingTools;

  const MirroringAppState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.scrcpyStatus = ScrcpyStatus.stopped,
    this.connectedAddress,
    this.deviceModel,
    this.errorMessage,
    this.isCheckingTools = true,
  });

  bool get isConnected => connectionStatus == ConnectionStatus.connected;
  bool get isConnecting => connectionStatus == ConnectionStatus.connecting;
  bool get isDisconnecting => connectionStatus == ConnectionStatus.disconnecting;
  bool get isScrcpyRunning => scrcpyStatus == ScrcpyStatus.running;

  MirroringAppState copyWith({
    ConnectionStatus? connectionStatus,
    ScrcpyStatus? scrcpyStatus,
    String? connectedAddress,
    bool clearConnectedAddress = false,
    String? deviceModel,
    bool clearDeviceModel = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isCheckingTools,
  }) {
    return MirroringAppState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      scrcpyStatus: scrcpyStatus ?? this.scrcpyStatus,
      connectedAddress: clearConnectedAddress
          ? null
          : (connectedAddress ?? this.connectedAddress),
      deviceModel: clearDeviceModel
          ? null
          : (deviceModel ?? this.deviceModel),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      isCheckingTools: isCheckingTools ?? this.isCheckingTools,
    );
  }
}

