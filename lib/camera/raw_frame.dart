import 'dart:typed_data';

import '../ambient/signature/scene_signature.dart';

/// Pixel layout of a raw camera frame.
enum FrameFormat {
  /// Planar YUV 4:2:0, the format Android delivers.
  yuv420,

  /// Packed blue, green, red, alpha, the format iOS delivers.
  bgra8888,
}

/// One plane of a raw frame.
class RawPlane {
  const RawPlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
  });

  /// The raw bytes of the plane.
  final Uint8List bytes;

  /// Distance in bytes between the start of two consecutive rows.
  final int bytesPerRow;

  /// Distance in bytes between two consecutive pixels of the same row.
  final int bytesPerPixel;
}

/// A raw frame coming from the camera, independent of the plugin types.
class RawFrame {
  const RawFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });

  /// Width in pixels of the largest plane.
  final int width;

  /// Height in pixels of the largest plane.
  final int height;

  /// The pixel layout.
  final FrameFormat format;

  /// The planes: Y, U and V for [FrameFormat.yuv420], a single one for
  /// [FrameFormat.bgra8888].
  final List<RawPlane> planes;
}

/// The result of converting a frame: a small upright RGBA buffer and the mean
/// brightness of the scene.
class FrameConversion {
  const FrameConversion({
    required this.pixels,
    required this.width,
    required this.height,
    required this.meanLuma,
    this.sceneLuma,
    this.colorfulness,
  });

  /// The RGBA pixels, 4 bytes each, row major.
  final Uint8List pixels;

  /// Width of [pixels] in pixels.
  final int width;

  /// Height of [pixels] in pixels.
  final int height;

  /// The mean brightness of the sampled pixels, 0..255.
  final double meanLuma;

  /// Coarse scene grid accumulated in raster order during conversion.
  final List<double>? sceneLuma;

  /// The colourfulness of the scene, computed in the same pass.
  ///
  /// It is absent for an empty frame: an empty frame has no colour to
  /// describe, so the neutral allowance is used instead.
  final SceneColorReading? colorfulness;
}
