import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_service.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG round-trip preserves every output pixel and dimensions', () async {
    final directory = Directory.systemTemp.createTempSync('sonoglitch_png_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final export = ExportService(
      log: DebugLog(),
      temporaryDirectory: directory,
    );
    final source = await buildTestImage(width: 40, height: 30);
    addTearDown(source.dispose);
    final cropped = await export.crop(source, ExportFormat.portrait);
    addTearDown(cropped.dispose);
    expect((cropped.width, cropped.height), (24, 30));
    final composed = await export.compose(cropped, ExportFormat.original);
    addTearDown(composed.dispose);
    final file = await export.writePng(composed);
    final bytes = await file.readAsBytes();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final decoded = (await codec.getNextFrame()).image;
      try {
        expect((decoded.width, decoded.height), (24, 30));
        final before = (await composed.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final after = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(after.buffer.asUint8List(), before.buffer.asUint8List());
      } finally {
        decoded.dispose();
      }
    } finally {
      codec.dispose();
    }
  });
}
