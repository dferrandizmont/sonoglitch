// PERF-1 baseline converter, retained only for byte-for-byte parity tests.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sonoglitch/camera/raw_frame.dart';

/// Converts a raw camera frame into a small upright RGBA image.
///
/// The conversion reads the camera planes directly, with nearest neighbour
/// subsampling, so the cost depends on the size of the *output* (about 360 px
/// on the long side) and not on the size of the sensor. That is what keeps
/// the live preview cheap on a mid range phone.
///
/// The same pass computes the mean brightness of the scene, which feeds the
/// light measurement.
class ReferenceFrameConverter {
  const ReferenceFrameConverter({this.targetLongSide = 360});

  /// Longest side of the converted image, in pixels.
  final int targetLongSide;

  /// Converts [frame] into an upright RGBA buffer.
  ///
  /// [rotationDegrees] is the clockwise rotation applied to the frame so it
  /// appears upright, and [mirror] flips it horizontally, which is what the
  /// front camera needs.
  FrameConversion convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
  }) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    final sourceWidth = frame.width;
    final sourceHeight = frame.height;
    if (sourceWidth <= 0 || sourceHeight <= 0 || frame.planes.isEmpty) {
      return FrameConversion(
        pixels: Uint8List(0),
        width: 0,
        height: 0,
        meanLuma: 0,
      );
    }

    // Dimensions of the frame once rotated.
    final rotatedWidth = rotation == 90 || rotation == 270
        ? sourceHeight
        : sourceWidth;
    final rotatedHeight = rotation == 90 || rotation == 270
        ? sourceWidth
        : sourceHeight;
    final longest = math.max(rotatedWidth, rotatedHeight);
    final scale = math.min(1.0, targetLongSide / longest);
    final outWidth = math.max(1, (rotatedWidth * scale).round());
    final outHeight = math.max(1, (rotatedHeight * scale).round());

    final pixels = Uint8List(outWidth * outHeight * 4);
    var lumaSum = 0.0;
    var samples = 0;

    for (var oy = 0; oy < outHeight; oy++) {
      final rotatedY = (oy * rotatedHeight) ~/ outHeight;
      for (var ox = 0; ox < outWidth; ox++) {
        final rotatedX = (ox * rotatedWidth) ~/ outWidth;

        // Inverse of the clockwise rotation, in the rotated frame.
        int sourceX;
        int sourceY;
        if (rotation == 90) {
          sourceX = rotatedY;
          sourceY = sourceHeight - 1 - rotatedX;
        } else if (rotation == 180) {
          sourceX = sourceWidth - 1 - rotatedX;
          sourceY = sourceHeight - 1 - rotatedY;
        } else if (rotation == 270) {
          sourceX = sourceWidth - 1 - rotatedY;
          sourceY = rotatedX;
        } else {
          sourceX = rotatedX;
          sourceY = rotatedY;
        }

        final pixel = _samplePixel(frame, sourceX, sourceY);
        final index = ((mirror ? outWidth - 1 - ox : ox) + oy * outWidth) * 4;
        pixels[index] = pixel.r;
        pixels[index + 1] = pixel.g;
        pixels[index + 2] = pixel.b;
        pixels[index + 3] = 255;
        lumaSum += pixel.luma;
        samples++;
      }
    }

    return FrameConversion(
      pixels: pixels,
      width: outWidth,
      height: outHeight,
      meanLuma: samples == 0 ? 0 : lumaSum / samples,
    );
  }

  _Pixel _samplePixel(RawFrame frame, int x, int y) {
    if (frame.format == FrameFormat.bgra8888) {
      return _sampleBgra(frame.planes.first, x, y);
    }
    return _sampleYuv(frame, x, y);
  }

  _Pixel _sampleYuv(RawFrame frame, int x, int y) {
    if (frame.planes.length < 3) {
      return const _Pixel(0, 0, 0, 0);
    }
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];

    final luma = _byteAt(
      yPlane.bytes,
      y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel,
    );
    final chromaX = x >> 1;
    final chromaY = y >> 1;
    final u = _byteAt(
      uPlane.bytes,
      chromaY * uPlane.bytesPerRow + chromaX * uPlane.bytesPerPixel,
    );
    final v = _byteAt(
      vPlane.bytes,
      chromaY * vPlane.bytesPerRow + chromaX * vPlane.bytesPerPixel,
    );

    // BT.601 with the studio swing (limited range), the format cameras
    // deliver: the luma of the frame is mapped to 16..235.
    final yy = (luma - 16) * 1.164383;
    final r = yy + 1.596027 * (v - 128);
    final g = yy - 0.391762 * (u - 128) - 0.812968 * (v - 128);
    final b = yy + 2.017232 * (u - 128);
    return _Pixel(_clampByte(r), _clampByte(g), _clampByte(b), luma.toDouble());
  }

  _Pixel _sampleBgra(RawPlane plane, int x, int y) {
    final base = y * plane.bytesPerRow + x * 4;
    final b = _byteAt(plane.bytes, base);
    final g = _byteAt(plane.bytes, base + 1);
    final r = _byteAt(plane.bytes, base + 2);
    // Rec. 601 luma, the same weighting the eye uses.
    final luma = 0.299 * r + 0.587 * g + 0.114 * b;
    return _Pixel(r, g, b, luma);
  }

  static int _byteAt(Uint8List bytes, int index) {
    if (index < 0 || index >= bytes.length) return 0;
    return bytes[index];
  }

  static int _clampByte(double value) {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return value.round();
  }
}

class _Pixel {
  const _Pixel(this.r, this.g, this.b, this.luma);

  final int r;
  final int g;
  final int b;
  final double luma;
}
