import 'dart:typed_data';
import '../constants.dart';

enum StreamFrameType {
  config(0),
  keyFrame(1),
  deltaFrame(2),
  metadata(3);

  final int wireValue;
  const StreamFrameType(this.wireValue);

  static StreamFrameType? fromWire(int value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

/// 24-byte big-endian binary header preceding each H.264 Annex-B access unit.
class StreamFrameHeader {
  final StreamFrameType frameType;
  final int rotationQuarterTurns;
  final int width;
  final int height;
  final int timestampUs;
  final int payloadLength;

  const StreamFrameHeader({
    required this.frameType,
    required this.rotationQuarterTurns,
    required this.width,
    required this.height,
    required this.timestampUs,
    required this.payloadLength,
  });

  Uint8List encode() {
    final data = ByteData(MirroringProtocolConstants.streamHeaderSize);
    data.setUint32(0, MirroringProtocolConstants.streamMagic, Endian.big);
    data.setUint8(4, frameType.wireValue);
    data.setUint8(5, rotationQuarterTurns & 0x03);
    data.setUint16(6, width, Endian.big);
    data.setUint16(8, height, Endian.big);
    data.setUint16(10, 0, Endian.big);
    data.setUint64(12, timestampUs, Endian.big);
    data.setUint32(20, payloadLength, Endian.big);
    return data.buffer.asUint8List();
  }

  static StreamFrameHeader? tryDecode(Uint8List bytes) {
    if (bytes.length < MirroringProtocolConstants.streamHeaderSize) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0, Endian.big);
    if (magic != MirroringProtocolConstants.streamMagic) {
      return null;
    }
    final frameType = StreamFrameType.fromWire(data.getUint8(4));
    if (frameType == null) return null;

    final rotation = data.getUint8(5) & 0x03;
    final width = data.getUint16(6, Endian.big);
    final height = data.getUint16(8, Endian.big);
    final timestampUs = data.getUint64(12, Endian.big);
    final payloadLength = data.getUint32(20, Endian.big);

    if (payloadLength > MirroringProtocolConstants.maxStreamPayloadBytes) {
      return null;
    }

    return StreamFrameHeader(
      frameType: frameType,
      rotationQuarterTurns: rotation,
      width: width,
      height: height,
      timestampUs: timestampUs,
      payloadLength: payloadLength,
    );
  }
}

class StreamFrame {
  final StreamFrameHeader header;
  final Uint8List payload;

  const StreamFrame({
    required this.header,
    required this.payload,
  });

  Uint8List encodeFullFrame() {
    final headerBytes = header.encode();
    final out = Uint8List(headerBytes.length + payload.length);
    out.setAll(0, headerBytes);
    out.setAll(headerBytes.length, payload);
    return out;
  }
}

/// Incremental TCP stream parser that yields validated [StreamFrame]s.
class StreamFrameParser {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  List<StreamFrame> addBytes(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    _buffer.add(chunk);

    final frames = <StreamFrame>[];
    var bytes = _buffer.toBytes();
    var offset = 0;

    while (bytes.length - offset >=
        MirroringProtocolConstants.streamHeaderSize) {
      final headerSlice = Uint8List.sublistView(
        bytes,
        offset,
        offset + MirroringProtocolConstants.streamHeaderSize,
      );
      final header = StreamFrameHeader.tryDecode(headerSlice);
      if (header == null) {
        throw const FormatException('Invalid stream frame header or magic');
      }

      final totalSize =
          MirroringProtocolConstants.streamHeaderSize + header.payloadLength;
      if (bytes.length - offset < totalSize) {
        break;
      }

      final payload = Uint8List.fromList(
        Uint8List.sublistView(
          bytes,
          offset + MirroringProtocolConstants.streamHeaderSize,
          offset + totalSize,
        ),
      );
      frames.add(StreamFrame(header: header, payload: payload));
      offset += totalSize;
    }

    if (offset > 0) {
      final remaining = bytes.length - offset;
      _buffer.clear();
      if (remaining > 0) {
        _buffer.add(Uint8List.sublistView(bytes, offset));
      }
    }

    return frames;
  }

  void reset() {
    _buffer.clear();
  }
}
