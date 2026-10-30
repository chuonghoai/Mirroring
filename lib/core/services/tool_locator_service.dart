import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/tool_info.dart';

class ToolLocatorService {
  final Duration probeTimeout;

  ToolLocatorService({this.probeTimeout = const Duration(seconds: 5)});

  /// Find and validate ADB and scrcpy binaries.
  Future<ToolInfo> locateTools() async {
    String? adbPath;
    String? adbVersion;
    String? scrcpyPath;
    String? scrcpyVersion;
    String? error;

    // Search directories in priority order
    final candidateDirs = _getCandidateDirectories();

    // 1. Check local bundled directories for ADB
    for (final dir in candidateDirs) {
      final candidate = '$dir${Platform.pathSeparator}adb.exe';
      if (await File(candidate).exists()) {
        final version = await _verifyAdb(candidate);
        if (version != null) {
          adbPath = candidate;
          adbVersion = version;
          break;
        }
      }
    }

    // Fallback: check system PATH and Android SDK for ADB
    if (adbPath == null) {
      final pathAdb = await _findInPath('adb.exe');
      if (pathAdb != null) {
        final version = await _verifyAdb(pathAdb);
        if (version != null) {
          adbPath = pathAdb;
          adbVersion = version;
        }
      }
    }

    if (adbPath == null) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final sdkAdb =
            '$localAppData${Platform.pathSeparator}Android${Platform.pathSeparator}Sdk${Platform.pathSeparator}platform-tools${Platform.pathSeparator}adb.exe';
        if (await File(sdkAdb).exists()) {
          final version = await _verifyAdb(sdkAdb);
          if (version != null) {
            adbPath = sdkAdb;
            adbVersion = version;
          }
        }
      }
    }

    // 2. Check local bundled directories for scrcpy
    for (final dir in candidateDirs) {
      final candidate = '$dir${Platform.pathSeparator}scrcpy.exe';
      if (await File(candidate).exists()) {
        final version = await _verifyScrcpy(candidate);
        if (version != null) {
          scrcpyPath = candidate;
          scrcpyVersion = version;
          break;
        }
      }
    }

    // Fallback: check system PATH for scrcpy
    if (scrcpyPath == null) {
      final pathScrcpy = await _findInPath('scrcpy.exe');
      if (pathScrcpy != null) {
        final version = await _verifyScrcpy(pathScrcpy);
        if (version != null) {
          scrcpyPath = pathScrcpy;
          scrcpyVersion = version;
        }
      }
    }

    // Determine error message if tools are missing
    if (adbPath == null && scrcpyPath == null) {
      error = 'Không tìm thấy ADB và scrcpy. Vui lòng kiểm tra thư mục tools/scrcpy.';
    } else if (adbPath == null) {
      error = 'Không tìm thấy ADB (Android Debug Bridge).';
    } else if (scrcpyPath == null) {
      error = 'Không tìm thấy scrcpy. Vui lòng đảm bảo scrcpy.exe có trong tools/scrcpy hoặc biến môi trường PATH.';
    }

    debugPrint('ToolLocatorService result: adb=$adbPath ($adbVersion), scrcpy=$scrcpyPath ($scrcpyVersion), error=$error');

    return ToolInfo(
      adbPath: adbPath,
      adbVersion: adbVersion,
      scrcpyPath: scrcpyPath,
      scrcpyVersion: scrcpyVersion,
      error: error,
    );
  }

  List<String> _getCandidateDirectories() {
    final dirs = <String>{};

    // App executable directory (e.g. Release build: app/tools/scrcpy)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      dirs.add('$exeDir${Platform.pathSeparator}tools${Platform.pathSeparator}scrcpy');
      dirs.add('$exeDir${Platform.pathSeparator}tools');
      dirs.add(exeDir);
    } catch (_) {}

    // Current working directory (e.g. during flutter run / debug)
    try {
      final cwd = Directory.current.path;
      dirs.add('$cwd${Platform.pathSeparator}tools${Platform.pathSeparator}scrcpy');
      dirs.add('$cwd${Platform.pathSeparator}tools');
    } catch (_) {}

    return dirs.toList();
  }

  Future<String?> _findInPath(String executable) async {
    try {
      final result = await Process.run('where.exe', [executable])
          .timeout(probeTimeout);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && await File(trimmed).exists()) {
            return trimmed;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _verifyAdb(String path) async {
    try {
      final result = await Process.run(path, ['version'])
          .timeout(probeTimeout);
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final match = RegExp(r'version\s+([^\r\n]+)').firstMatch(stdout);
        if (match != null) {
          return match.group(1)?.trim();
        }
        return 'Sẵn sàng';
      }
    } catch (e) {
      debugPrint('Error verifying ADB at $path: $e');
    }
    return null;
  }

  Future<String?> _verifyScrcpy(String path) async {
    try {
      final result = await Process.run(path, ['--version'])
          .timeout(probeTimeout);
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final match = RegExp(r'scrcpy\s+([^\r\n]+)').firstMatch(stdout);
        if (match != null) {
          return match.group(1)?.trim();
        }
        return 'Sẵn sàng';
      }
    } catch (e) {
      debugPrint('Error verifying scrcpy at $path: $e');
    }
    return null;
  }
}
