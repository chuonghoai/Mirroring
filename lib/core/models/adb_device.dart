enum DeviceState {
  device,
  unauthorized,
  offline,
  unknown,
}

class AdbDevice {
  final String serial;
  final DeviceState state;
  final String? model;

  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
  });

  bool get isConnected => state == DeviceState.device;

  static AdbDevice? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('*') || trimmed.startsWith('List of')) {
      return null;
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final serial = parts[0];
    final stateStr = parts[1].toLowerCase();

    DeviceState state;
    switch (stateStr) {
      case 'device':
        state = DeviceState.device;
        break;
      case 'unauthorized':
        state = DeviceState.unauthorized;
        break;
      case 'offline':
        state = DeviceState.offline;
        break;
      default:
        state = DeviceState.unknown;
    }

    String? model;
    for (final part in parts.skip(2)) {
      if (part.startsWith('model:')) {
        model = part.substring(6).replaceAll('_', ' ');
        break;
      }
    }

    return AdbDevice(
      serial: serial,
      state: state,
      model: model,
    );
  }
}

