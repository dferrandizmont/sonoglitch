import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_service.dart';

import '../support/fakes.dart';

/// The pixels of an image, as raw RGBA.
Future<Uint8List> imagePixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

/// How much the pixels of an area are different.
int areaDifference(
  Uint8List a,
  Uint8List b,
  int width, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  var sum = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final index = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        sum += (a[index + channel] - b[index + channel]).abs();
      }
    }
  }
  return sum;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExportFormat', () {
    test('the original keeps the aspect ratio', () {
      expect(ExportFormat.original.aspectRatio, isNull);
    });

    test('the square is one', () {
      expect(ExportFormat.square.aspectRatio, 1);
    });

    test('the vertical is four fifths', () {
      expect(ExportFormat.portrait.aspectRatio, closeTo(0.8, 0.0001));
    });
  });

  group('ExportService', () {
    test(
      'preview bounds memory without resizing or disposing the export input',
      () async {
        final export = ExportService(log: DebugLog());
        final source = await buildTestImage(width: 80, height: 40);
        final preview = await export.preview(source, maxSide: 20);
        expect((preview.width, preview.height), (20, 10));
        expect((source.width, source.height), (80, 40));
        expect(source.debugDisposed, isFalse);
        preview.dispose();
        final small = await export.preview(source, maxSide: 1024);
        expect((small.width, small.height), (80, 40));
        small.dispose();
        source.dispose();
      },
    );

    test('the service is created with a logger', () {
      final service = ExportService(log: DebugLog());
      expect(service.log, isNotNull);
    });

    test('the watermark text is discreet', () {
      expect(ExportService.watermarkText, 'Sonoglitch');
      expect(ExportService.watermarkOpacity, lessThan(1));
      expect(ExportService.watermarkHeightRatio, lessThan(0.05));
    });
  });

  group('the composition', () {
    test('the original keeps the size of the picture', () async {
      final service = ExportService(log: DebugLog());
      final source = await buildTestImage(width: 40, height: 20);
      addTearDown(source.dispose);

      final composed = await service.compose(
        source,
        ExportFormat.original,
        watermark: false,
      );
      addTearDown(composed.dispose);

      expect(composed.width, 40);
      expect(composed.height, 20);
    });

    test('the square is the centre of the picture', () async {
      final service = ExportService(log: DebugLog());
      final source = await buildTestImage(width: 40, height: 20);
      addTearDown(source.dispose);

      final composed = await service.compose(
        source,
        ExportFormat.square,
        watermark: false,
      );
      addTearDown(composed.dispose);

      expect(composed.width, 20);
      expect(composed.height, 20);

      final original = await imagePixels(source);
      final square = await imagePixels(composed);
      // The crop keeps the columns 10 to 30 of the picture.
      for (var y = 0; y < 20; y++) {
        for (var channel = 0; channel < 3; channel++) {
          expect(
            square[(y * 20) * 4 + channel],
            original[(y * 40 + 10) * 4 + channel],
            reason: 'The crop must be the centre of the picture',
          );
        }
      }
    });

    test('the vertical is the centre of the picture', () async {
      final service = ExportService(log: DebugLog());
      final source = await buildTestImage(width: 40, height: 20);
      addTearDown(source.dispose);

      final composed = await service.compose(
        source,
        ExportFormat.portrait,
        watermark: false,
      );
      addTearDown(composed.dispose);

      // Four fifths of twenty is sixteen.
      expect(composed.width, 16);
      expect(composed.height, 20);

      final original = await imagePixels(source);
      final portrait = await imagePixels(composed);
      // The crop keeps the columns 12 to 28 of the picture.
      for (var y = 0; y < 20; y++) {
        for (var channel = 0; channel < 3; channel++) {
          expect(
            portrait[(y * 16) * 4 + channel],
            original[(y * 40 + 12) * 4 + channel],
            reason: 'The crop must be the centre of the picture',
          );
        }
      }
    });

    test('the watermark is only drawn when it is on', () async {
      final service = ExportService(log: DebugLog());
      final source = await buildFlatTestImage(width: 200, height: 200);
      addTearDown(source.dispose);

      final plain = await service.compose(
        source,
        ExportFormat.original,
        watermark: false,
      );
      addTearDown(plain.dispose);
      final marked = await service.compose(
        source,
        ExportFormat.original,
        watermark: true,
      );
      addTearDown(marked.dispose);

      final without = await imagePixels(plain);
      final markedPixels = await imagePixels(marked);

      // The signature is in the bottom right corner.
      expect(
        areaDifference(
          without,
          markedPixels,
          200,
          left: 140,
          top: 175,
          right: 200,
          bottom: 200,
        ),
        greaterThan(0),
      );
      // The rest of the picture is the same.
      expect(
        areaDifference(
          without,
          markedPixels,
          200,
          left: 0,
          top: 0,
          right: 60,
          bottom: 60,
        ),
        0,
      );
    });
  });
}
