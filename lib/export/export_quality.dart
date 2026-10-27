import 'dart:math' as math;
import 'dart:ui';

import 'export_format.dart';

/// Resolution caps, never an instruction to upscale a camera picture.
enum ExportQuality {
  standard,
  high,
  maximum;

  ExportQuality? get lower => switch (this) {
    maximum => high,
    high => standard,
    standard => null,
  };
}

/// The crop is chosen in oriented source pixels before decoding or rendering.
class ExportPlan {
  const ExportPlan({
    required this.crop,
    required this.width,
    required this.height,
    required this.decodeWidth,
    required this.decodeHeight,
  });

  static const maxPixels = 24000000;
  static const memoryBudgetBytes = 700000000;
  final Rect crop;
  final int width;
  final int height;
  final int decodeWidth;
  final int decodeHeight;
  int get maxSide => math.max(width, height);
  // Include the uncropped decoder surface, not just the output crop.
  int get estimatedBytes => decodeWidth * decodeHeight * 4 * 3;

  static Rect cropRect(int width, int height, ExportFormat format) {
    final aspect = format.aspectRatio;
    if (aspect == null) {
      return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    }
    // Integral source pixels keep a crop from introducing another resize.
    final cropWidth = math.min(width, (height * aspect).floor());
    final cropHeight = math.min(height, (width / aspect).floor());
    return Rect.fromLTWH(
      ((width - cropWidth) ~/ 2).toDouble(),
      ((height - cropHeight) ~/ 2).toDouble(),
      math.max(1, cropWidth).toDouble(),
      math.max(1, cropHeight).toDouble(),
    );
  }

  static ExportPlan build({
    required int sourceWidth,
    required int sourceHeight,
    required ExportQuality quality,
    required ExportFormat format,
    required int textureLimit,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0 || textureLimit <= 0) {
      throw ArgumentError(
        'Image dimensions and texture limit must be positive',
      );
    }
    final crop = cropRect(sourceWidth, sourceHeight, format);
    final side = switch (quality) {
      ExportQuality.standard => 2048,
      ExportQuality.high => 4096,
      ExportQuality.maximum => math.max(sourceWidth, sourceHeight),
    };
    final scale = [
      1.0,
      side / math.max(crop.width, crop.height),
      math.sqrt(maxPixels / (crop.width * crop.height)),
      // A single-pass sampler also needs the whole decoded source to fit.
      textureLimit / math.max(sourceWidth, sourceHeight),
    ].reduce(math.min);
    var decodeWidth = math.max(1, (sourceWidth * scale).floor());
    var decodeHeight = math.max(1, (sourceHeight * scale).floor());
    var decodedCrop = cropRect(decodeWidth, decodeHeight, format);
    // Rounding the decoder dimensions changes the integer crop's aspect and
    // can put it just over the cap. Reduce the decode plan, never resize again.
    while (decodedCrop.width * decodedCrop.height > maxPixels) {
      final smallerScale = math.min(
        (decodeWidth - 1) / sourceWidth,
        (decodeHeight - 1) / sourceHeight,
      );
      decodeWidth = math.max(1, (sourceWidth * smallerScale).floor());
      decodeHeight = math.max(1, (sourceHeight * smallerScale).floor());
      decodedCrop = cropRect(decodeWidth, decodeHeight, format);
    }
    return ExportPlan(
      crop: crop,
      width: decodedCrop.width.toInt(),
      height: decodedCrop.height.toInt(),
      decodeWidth: decodeWidth,
      decodeHeight: decodeHeight,
    );
  }
}
