import 'package:flutter/services.dart';

class DecodedFrameResult {
  final bool ok;
  final int width;
  final int height;

  const DecodedFrameResult({
    required this.ok,
    required this.width,
    required this.height,
  });
}

class NativeStreamStats {
  final bool connected;
  final bool ended;
  final int width;
  final int height;
  final int rotation;
  final int decodedFrames;
  final String error;

  const NativeStreamStats({
    required this.connected,
    required this.ended,
    required this.width,
    required this.height,
    required this.rotation,
    required this.decodedFrames,
    required this.error,
  });
}

abstract class VideoDecoderBackend {
  bool get supportsNativeStream => false;

  Future<int?> createTexture();

  Future<bool> startNativeStream({
    required String host,
    required int port,
    required String sessionToken,
  }) async =>
      false;

  Future<void> stopNativeStream() async {}

  Future<NativeStreamStats> getStreamStats() async => const NativeStreamStats(
        connected: false,
        ended: false,
        width: 0,
        height: 0,
        rotation: 0,
        decodedFrames: 0,
        error: '',
      );

  Future<DecodedFrameResult> decodeFrame({
    required Uint8List bytes,
    required int width,
    required int height,
  });

  Future<void> resetDecoder();
  Future<void> disposeTexture();
}

class MethodChannelVideoDecoderBackend implements VideoDecoderBackend {
  static const MethodChannel _channel =
      MethodChannel('com.chuonghoai.mirroring/video_decoder');

  @override
  bool get supportsNativeStream => true;

  @override
  Future<int?> createTexture() async {
    final id = await _channel.invokeMethod<int>('createTexture');
    return id;
  }

  @override
  Future<bool> startNativeStream({
    required String host,
    required int port,
    required String sessionToken,
  }) async {
    final ok = await _channel.invokeMethod<bool>('startStream', {
      'host': host,
      'port': port,
      'sessionToken': sessionToken,
    });
    return ok ?? false;
  }

  @override
  Future<void> stopNativeStream() async {
    await _channel.invokeMethod<void>('stopStream');
  }

  @override
  Future<NativeStreamStats> getStreamStats() async {
    final resp = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getStreamStats',
    );
    if (resp == null) {
      return const NativeStreamStats(
        connected: false,
        ended: false,
        width: 0,
        height: 0,
        rotation: 0,
        decodedFrames: 0,
        error: '',
      );
    }
    return NativeStreamStats(
      connected: (resp['connected'] as bool?) ?? false,
      ended: (resp['ended'] as bool?) ?? false,
      width: (resp['width'] as int?) ?? 0,
      height: (resp['height'] as int?) ?? 0,
      rotation: (resp['rotation'] as int?) ?? 0,
      decodedFrames: (resp['decodedFrames'] as int?) ?? 0,
      error: (resp['error'] as String?) ?? '',
    );
  }

  @override
  Future<DecodedFrameResult> decodeFrame({
    required Uint8List bytes,
    required int width,
    required int height,
  }) async {
    final resp = await _channel.invokeMethod<Map<Object?, Object?>>(
      'decodeFrame',
      {
        'bytes': bytes,
        'width': width,
        'height': height,
      },
    );
    if (resp == null) {
      return const DecodedFrameResult(ok: false, width: 0, height: 0);
    }
    return DecodedFrameResult(
      ok: (resp['ok'] as bool?) ?? false,
      width: (resp['width'] as int?) ?? 0,
      height: (resp['height'] as int?) ?? 0,
    );
  }

  @override
  Future<void> resetDecoder() async {
    await _channel.invokeMethod<void>('resetDecoder');
  }

  @override
  Future<void> disposeTexture() async {
    await _channel.invokeMethod<void>('disposeTexture');
  }
}
