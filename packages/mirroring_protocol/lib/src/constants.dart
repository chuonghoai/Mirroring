/// Protocol constants shared between Mirroring Windows and Android Companion.
class MirroringProtocolConstants {
  MirroringProtocolConstants._();

  static const int protocolVersion = 1;
  static const String discoveryMagic = 'MIRRORING_LAN_V1';

  /// UDP broadcast port for LAN device discovery.
  static const int discoveryPort = 45454;

  /// Default WebSocket control server port on Android Companion.
  static const int defaultControlPort = 45455;

  /// Default TCP H.264 stream server port on Android Companion.
  static const int defaultStreamPort = 45456;

  static const Duration beaconInterval = Duration(seconds: 2);
  static const Duration deviceOfflineTimeout = Duration(seconds: 7);
  static const Duration pairRequestTimeout = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 2);
  static const Duration heartbeatTimeout = Duration(seconds: 8);
  static const Duration reconnectWindow = Duration(seconds: 20);

  /// Binary stream frame magic: 'MRV1' (0x4D525631).
  static const int streamMagic = 0x4D525631;
  static const int streamHeaderSize = 24;
  static const int maxStreamPayloadBytes = 16 * 1024 * 1024; // 16 MiB safety cap
}
