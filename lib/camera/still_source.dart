import 'dart:typed_data';
import 'dart:ui' as ui;

/// A compressed camera original. No full-size pixel allocation until export.
abstract class StillSource {
  int get width;
  int get height;
  int get compressedBytes;
  Future<ui.Image> decode(int width, int height);
}

class EncodedStill implements StillSource {
  EncodedStill._(this.bytes, this.width, this.height, this._decode);

  final Uint8List bytes;
  @override
  final int width;
  @override
  final int height;
  final Future<ui.Image> Function(Uint8List, int, int) _decode;
  @override
  int get compressedBytes => bytes.length;

  static Future<EncodedStill> read(
    Uint8List bytes,
    Future<ui.Image> Function(Uint8List, int, int) decode, {
    bool Function(int width, int height)? swapAxes,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final swap = swapAxes?.call(descriptor.width, descriptor.height) ?? false;
      return EncodedStill._(
        bytes,
        swap ? descriptor.height : descriptor.width,
        swap ? descriptor.width : descriptor.height,
        (data, width, height) =>
            decode(data, swap ? height : width, swap ? width : height),
      );
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  Future<ui.Image> decode(int width, int height) =>
      _decode(bytes, width, height);
}
