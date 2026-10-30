import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

typedef ScrcpyExitCallback = void Function(int exitCode);

class ScrcpyService {
  final String scrcpyPath;
  Process? _process;
  ScrcpyExitCallback? onProcessExit;

  ScrcpyService({required this.scrcpyPath});

  bool get isRunning => _process != null;

  /// Starts scrcpy targeting a specific device
  Future<bool> start({
    required String targetDevice,
    int maxSize = 1920,
    String videoBitRate = '8M',
    ScrcpyExitCallback? onExit,
  }) async {
    // If a process is already running, terminate it before starting a new one
    if (_process != null) {
      debugPrint('Existing scrcpy process running. Terminating before new start.');
      await stop();
    }

    onProcessExit = onExit;

    final scrcpyFile = File(scrcpyPath);
    final workingDir = scrcpyFile.parent.path;

    final args = [
      '-s', targetDevice,
      '--max-size', '$maxSize',
      '--video-bit-rate', videoBitRate,
      '--window-title', 'Mirroring - $targetDevice',
    ];

    debugPrint('Starting scrcpy: $scrcpyPath with args: ${args.join(' ')}');
    debugPrint('Working directory: $workingDir');

    try {
      _process = await Process.start(
        scrcpyPath,
        args,
        workingDirectory: workingDir,
        mode: ProcessStartMode.normal,
      );

      // Listen to stdout & stderr for diagnostics
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[scrcpy stdout] $data');
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[scrcpy stderr] $data');
      });

      // Track process exit
      _process!.exitCode.then((code) {
        debugPrint('scrcpy exited with code: $code');
        _process = null;
        if (onProcessExit != null) {
          onProcessExit!(code);
        }
      });

      return true;
    } catch (e) {
      debugPrint('Failed to start scrcpy: $e');
      _process = null;
      return false;
    }
  }

  /// Stops the running scrcpy process safely
  Future<void> stop() async {
    if (_process == null) return;

    try {
      debugPrint('Stopping scrcpy process (pid: ${_process!.pid})...');
      _process!.kill(ProcessSignal.sigterm);

      // Wait up to 1.5 seconds for graceful exit, then force kill
      final exited = await _process!.exitCode
          .timeout(const Duration(milliseconds: 1500), onTimeout: () {
        debugPrint('scrcpy did not terminate gracefully, sending SIGKILL');
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      });
      debugPrint('scrcpy process stopped with code: $exited');
    } catch (e) {
      debugPrint('Error stopping scrcpy: $e');
    } finally {
      _process = null;
    }
  }
}

