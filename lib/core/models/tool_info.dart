class ToolInfo {
  final String? adbPath;
  final String? adbVersion;
  final String? scrcpyPath;
  final String? scrcpyVersion;
  final String? error;

  const ToolInfo({
    this.adbPath,
    this.adbVersion,
    this.scrcpyPath,
    this.scrcpyVersion,
    this.error,
  });

  bool get isReady =>
      adbPath != null &&
      scrcpyPath != null &&
      error == null;

  bool get hasAdb => adbPath != null;
  bool get hasScrcpy => scrcpyPath != null;

  ToolInfo copyWith({
    String? adbPath,
    String? adbVersion,
    String? scrcpyPath,
    String? scrcpyVersion,
    String? error,
  }) {
    return ToolInfo(
      adbPath: adbPath ?? this.adbPath,
      adbVersion: adbVersion ?? this.adbVersion,
      scrcpyPath: scrcpyPath ?? this.scrcpyPath,
      scrcpyVersion: scrcpyVersion ?? this.scrcpyVersion,
      error: error ?? this.error,
    );
  }
}

