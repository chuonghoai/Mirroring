import 'dart:io';
import 'dart:math';

class WindowsDeviceIdentity {
  static String? _cachedId;

  static Future<String> getOrCreateDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final dir = Directory('$appData${Platform.pathSeparator}Mirroring');
        final file = File('${dir.path}${Platform.pathSeparator}device_id.txt');
        if (await file.exists()) {
          final raw = (await file.readAsString()).trim();
          if (RegExp(r'^[a-zA-Z0-9_-]{8,64}$').hasMatch(raw)) {
            _cachedId = raw;
            return raw;
          }
        }
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final generated = _generateId();
        await file.writeAsString(generated);
        _cachedId = generated;
        return generated;
      }
    } catch (_) {}

    _cachedId = _generateId();
    return _cachedId!;
  }

  static String getHostName() {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'Windows PC';
  }

  static String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'win_$hex';
  }
}
