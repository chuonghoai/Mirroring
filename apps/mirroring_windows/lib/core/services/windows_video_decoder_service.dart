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

abstract class VideoDecoderBackend {
  Future<int?> createTexture();
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
  Future<int?> createTexture() async {
    final id = await _channel.invokeMethod<int>('createTexture');
    return id;
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
