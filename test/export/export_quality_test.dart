import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/export/export_service.dart';

void main() {
  ExportPlan plan(
    int width,
    int height,
    ExportQuality quality, {
    ExportFormat format = ExportFormat.original,
    int textureLimit = 16384,
  }) => ExportPlan.build(
    sourceWidth: width,
    sourceHeight: height,
    quality: quality,
    format: format,
    textureLimit: textureLimit,
  );

  for (final sample in [
    (4000, 3000, [(2048, 1536), (4000, 3000), (4000, 3000)]),
    (6000, 4000, [(2048, 1365), (4096, 2730), (6000, 4000)]),
    (8160, 6144, [(2048, 1542), (4096, 3084), (5645, 4250)]),
  ]) {
    for (final portrait in [false, true]) {
      for (final quality in ExportQuality.values) {
        test('${sample.$1}x${sample.$2} $quality portrait=$portrait', () {
          final result = plan(
            portrait ? sample.$2 : sample.$1,
            portrait ? sample.$1 : sample.$2,
            quality,
          );
          final expected = sample.$3[quality.index];
          expect((
            result.width,
            result.height,
          ), portrait ? (expected.$2, expected.$1) : expected);
          expect(result.width * result.height, lessThanOrEqualTo(24000000));
          expect(result.decodeWidth, result.width);
          expect(result.decodeHeight, result.height);
        });
      }
    }
  }

  test('texture cap scales both axes and the sampler proportionally', () {
    final result = plan(6000, 4000, ExportQuality.maximum, textureLimit: 4096);
    expect((result.width, result.height), (4096, 2730));
    final cropped = plan(
      8160,
      6144,
      ExportQuality.maximum,
      format: ExportFormat.square,
      textureLimit: 4096,
    );
    expect((cropped.decodeWidth, cropped.decodeHeight), (4096, 3084));
    expect((cropped.width, cropped.height), (3084, 3084));
  });

  test('Maximum 5951x8402 4:5 integer crop never exceeds 24 MP', () {
    final result = plan(
      5951,
      8402,
      ExportQuality.maximum,
      format: ExportFormat.portrait,
    );
    expect((result.decodeWidth, result.decodeHeight), (4380, 6185));
    expect((result.width, result.height), (4380, 5475));
    expect(result.width * result.height, lessThanOrEqualTo(24000000));
  });

  test('odd sources and cropped outputs obey the final integer pixel cap', () {
    for (final size in [
      (5951, 8403),
      (8403, 5951),
      (8001, 6001),
      (6001, 8001),
      (5001, 5001),
    ]) {
      for (final format in ExportFormat.values) {
        for (final quality in ExportQuality.values) {
          final result = plan(size.$1, size.$2, quality, format: format);
          expect(
            result.width * result.height,
            lessThanOrEqualTo(24000000),
            reason: '$size $format $quality',
          );
          expect(result.decodeWidth, lessThanOrEqualTo(size.$1));
          expect(result.decodeHeight, lessThanOrEqualTo(size.$2));
          expect(result.width, lessThanOrEqualTo(result.decodeWidth));
          expect(result.height, lessThanOrEqualTo(result.decodeHeight));
          final crop = ExportPlan.cropRect(
            result.decodeWidth,
            result.decodeHeight,
            format,
          );
          expect((result.width, result.height), (crop.width, crop.height));
        }
      }
    }
  });

  test('no upscaling of small files at any tier', () {
    for (final quality in ExportQuality.values) {
      final result = plan(640, 480, quality);
      expect((result.width, result.height), (640, 480));
    }
  });

  test('crop maths in oriented source pixels, before rendering', () {
    expect(
      ExportPlan.cropRect(4000, 3000, ExportFormat.square),
      const Rect.fromLTWH(500, 0, 3000, 3000),
    );
    expect(
      ExportPlan.cropRect(3000, 4000, ExportFormat.square),
      const Rect.fromLTWH(0, 500, 3000, 3000),
    );
    expect(
      ExportPlan.cropRect(4000, 3000, ExportFormat.portrait),
      const Rect.fromLTWH(800, 0, 2400, 3000),
    );
    expect(
      ExportPlan.cropRect(3000, 4000, ExportFormat.portrait),
      const Rect.fromLTWH(0, 125, 3000, 3750),
    );
    final result = plan(
      8160,
      6144,
      ExportQuality.high,
      format: ExportFormat.portrait,
    );
    expect((result.width, result.height), (3276, 4096));
    // The crop is an integer pixel copy of the decoded input. The effect's
    // maxSide equals that copy's long side, so it performs no second resize.
    final decodedCrop = ExportPlan.cropRect(
      result.decodeWidth,
      result.decodeHeight,
      ExportFormat.portrait,
    );
    expect(
      (decodedCrop.width.toInt(), decodedCrop.height.toInt()),
      (result.width, result.height),
    );
  });

  test('the 9:16 crop keeps the centre of the picture', () {
    // A picture that is already 9:16 is not cropped.
    expect(
      ExportPlan.cropRect(1080, 1920, ExportFormat.story),
      const Rect.fromLTWH(0, 0, 1080, 1920),
    );
    // A landscape picture is cut at the sides: the height is kept.
    expect(
      ExportPlan.cropRect(1920, 1080, ExportFormat.story),
      const Rect.fromLTWH(656, 0, 607, 1080),
    );
    // A portrait picture that is wider than 9:16 is cut at the sides too.
    expect(
      ExportPlan.cropRect(3000, 4000, ExportFormat.story),
      const Rect.fromLTWH(375, 0, 2250, 4000),
    );
    // A picture that is taller than 9:16 is cut at the top and the bottom.
    expect(
      ExportPlan.cropRect(1080, 2400, ExportFormat.story),
      const Rect.fromLTWH(0, 240, 1080, 1920),
    );
  });

  test(
    'memory estimate includes the uncropped decoder and three RGBA surfaces',
    () {
      final native = plan(6000, 4000, ExportQuality.maximum);
      expect(native.estimatedBytes, 288000000);
      final crop = plan(
        16000,
        4000,
        ExportQuality.maximum,
        format: ExportFormat.square,
      );
      expect(crop.estimatedBytes, 768000000);
      expect(crop.estimatedBytes, greaterThan(ExportPlan.memoryBudgetBytes));
      expect(ExportQuality.maximum.lower, ExportQuality.high);
      expect(ExportQuality.high.lower, ExportQuality.standard);
      expect(ExportQuality.standard.lower, isNull);
    },
  );

  test('invalid sizes are rejected', () {
    expect(() => plan(0, 3000, ExportQuality.high), throwsArgumentError);
    expect(
      () => plan(4000, 3000, ExportQuality.high, textureLimit: 0),
      throwsArgumentError,
    );
  });
  test('watermark is 2.2 percent of the short side at every resolution', () {
    for (final size in [(4000.0, 3000.0), (6000.0, 4000.0), (4250.0, 5645.0)]) {
      final a = ExportService.watermarkMetrics(size.$1, size.$2);
      final b = ExportService.watermarkMetrics(size.$2, size.$1);
      final shorter = size.$1 < size.$2 ? size.$1 : size.$2;
      expect(a, b);
      expect(a.fontSize * 0.7, closeTo(shorter * 0.022, 0.00001));
      expect(a.margin, shorter * 0.02);
    }
    final small = ExportService.watermarkMetrics(2000, 1500);
    final large = ExportService.watermarkMetrics(4000, 3000);
    expect(large.fontSize, small.fontSize * 2);
    expect(large.margin, small.margin * 2);
  });
}
