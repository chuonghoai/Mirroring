import 'dart:async';
import 'package:flutter/services.dart';

abstract class MirroringNativeBridge {
  Stream<Map<Object?, Object?>> get events;
  Future<Map<Object?, Object?>> getSnapshot();
  Future<void> refreshDiscovery();
  Future<bool> hasNotificationPermission();
  Future<bool> requestNotificationPermission();
  Future<bool> respondToRequest({
    required String requestId,
    required bool accepted,
    String? reason,
  });
  Future<bool> requestMediaProjectionAndStart();
  Future<void> stopSession({String? reason});
  Future<void> openAccessibilitySettings();
}

class MethodChannelMirroringBridge implements MirroringNativeBridge {
  static const MethodChannel _method = MethodChannel('com.chuonghoai.mirroring/native');
  static const EventChannel _events = EventChannel('com.chuonghoai.mirroring/events');

  @override
  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>();

  @override
  Future<Map<Object?, Object?>> getSnapshot() async {
    final result = await _method.invokeMethod<Map<Object?, Object?>>('getSnapshot');
    return result ?? const {};
  }

  @override
  Future<void> refreshDiscovery() async {
    await _method.invokeMethod<void>('refreshDiscovery');
  }

  @override
  Future<bool> hasNotificationPermission() async {
    return (await _method.invokeMethod<bool>('hasNotificationPermission')) ?? true;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    return (await _method.invokeMethod<bool>('requestNotificationPermission')) ?? true;
  }

  @override
  Future<bool> respondToRequest({
    required String requestId,
    required bool accepted,
    String? reason,
  }) async {
    return (await _method.invokeMethod<bool>('respondToRequest', {
          'requestId': requestId,
          'accepted': accepted,
          'reason': ?reason,
        })) ??
        false;
  }

  @override
  Future<bool> requestMediaProjectionAndStart() async {
    return (await _method.invokeMethod<bool>('requestMediaProjectionAndStart')) ??
        false;
  }

  @override
  Future<void> stopSession({String? reason}) async {
    await _method.invokeMethod<void>('stopSession', {
      'reason': ?reason,
    });
  }

  @override
  Future<void> openAccessibilitySettings() async {
    await _method.invokeMethod<void>('openAccessibilitySettings');
  }
}
