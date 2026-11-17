/// Sanitizes and validates identifiers and tokens exchanged over LAN.
class ProtocolSecurity {
  ProtocolSecurity._();

  static final RegExp _deviceIdPattern = RegExp(r'^[a-zA-Z0-9_-]{8,64}$');
  static final RegExp _tokenPattern = RegExp(r'^[a-zA-Z0-9_-]{32,128}$');

  static bool isValidDeviceId(String value) => _deviceIdPattern.hasMatch(value);

  static bool isValidSessionToken(String value) => _tokenPattern.hasMatch(value);

  /// Constant-time string comparison to avoid timing side-channels.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Strips control characters and caps length for safe display.
  static String sanitizeDeviceName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (cleaned.isEmpty) return 'Unknown Device';
    if (cleaned.length > 64) return cleaned.substring(0, 64);
    return cleaned;
  }
}
