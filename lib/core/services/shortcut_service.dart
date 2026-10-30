import 'dart:io';
import 'package:flutter/foundation.dart';

class ShortcutService {
  /// Creates a desktop shortcut pointing to the running mirroring executable.
  static Future<bool> createDesktopShortcut() async {
    if (!Platform.isWindows) return false;

    try {
      final exePath = Platform.resolvedExecutable;
      final workingDir = File(exePath).parent.path;

      // Escape single quotes if path contains any
      final safeExe = exePath.replaceAll("'", "''");
      final safeDir = workingDir.replaceAll("'", "''");

      final script = '''
\$desktop = [Environment]::GetFolderPath('Desktop')
\$shortcutPath = Join-Path \$desktop 'Mirroring.lnk'
if (Test-Path \$shortcutPath) { Remove-Item \$shortcutPath -Force }
\$shell = New-Object -ComObject WScript.Shell
\$shortcut = \$shell.CreateShortcut(\$shortcutPath)
\$shortcut.TargetPath = '$safeExe'
\$shortcut.WorkingDirectory = '$safeDir'
\$shortcut.IconLocation = '$safeExe,0'
\$shortcut.Description = 'Mirroring'
\$shortcut.Save()
Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -NoNewWindow -ErrorAction SilentlyContinue
''';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      ).timeout(const Duration(seconds: 6));

      debugPrint('Shortcut creation exitCode: ${result.exitCode}');
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error creating shortcut: $e');
      return false;
    }
  }
}

