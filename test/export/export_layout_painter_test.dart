import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_geometry.dart';
import 'package:sonoglitch/export/export_readings.dart';
import 'package:sonoglitch/export/export_service.dart';

import '../support/fakes.dart';

/// The pixels of an image, as raw RGBA.
Future<Uint8List> imagePixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

/// The colour of a pixel of an image.
({int red, int green, int blue}) pixelAt(
  Uint8List pixels,
  int width,
  int x,
  int y,
) {
  final index = (y * width + x) * 4;
  return (
    red: pixels[index],
    green: pixels[index + 1],
    blue: pixels[index + 2],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const values = ExportLayoutValues(
    styleName: 'Static',
    noiseDb: 72,
    lux: 240,
    accel: 1.5,
    noise: 0.5,
    light: 0.25,
    motion: 0.75,
    bass: 0.3,
    mid: 0.2,
    treble: 0.1,
    spectrumAvailable: true,
  );

  for (final scale in [1, 2]) {
    for (final layout in [ExportLayout.soundStrip, ExportLayout.poster]) {
      test(
        '$layout cell centres retain role colours at ${1080 * scale}px',
        () async {
          final source = await buildFlatTestImage(
            width: 1080 * scale,
            height: 1350 * scale,
          );
          addTearDown(source.dispose);
          final composed = await ExportService(log: DebugLog()).compose(
            source,
            ExportFormat.original,
            layout: layout,
            values: values,
          );
          addTearDown(composed.dispose);
          final plan = ExportLayoutPlan.build(
            layout: layout,
            photoWidth: source.width,
            photoHeight: source.height,
          );
          final readings = readingsOf(values);
          final slots = layout == ExportLayout.poster
              ? PosterGeometry.compute(plan, readings).slots
              : SoundStripGeometry.compute(plan, readings).slots;
          final pixels = await imagePixels(composed);
          for (var i = 0; i < 3; i++) {
            final lit = slots[i].cells.first.center;
            final color = layout == ExportLayout.poster
                ? readings[i].paper
                : readings[i].dark;
            final rgb = pixelAt(
              pixels,
              composed.width,
              lit.dx.round(),
              lit.dy.round(),
            );
            expect(rgb.red, closeTo(color.r * 255, 1));
            expect(rgb.green, closeTo(color.g * 255, 1));
            expect(rgb.blue, closeTo(color.b * 255, 1));
            final unlit = slots[i].cells.last.center;
            final track = pixelAt(
              pixels,
              composed.width,
              unlit.dx.round(),
              unlit.dy.round(),
            );
            final expected = layout == ExportLayout.poster ? 214 : 52;
            expect(track.red, closeTo(expected, 1));
            expect(track.green, closeTo(expected, 1));
            expect(track.blue, closeTo(expected + 3, 1));
          }
          if (layout == ExportLayout.soundStrip) {
            final edge = pixelAt(
              pixels,
              composed.width,
              composed.width ~/ 2,
              plan.photo.bottom.toInt() + 2 * scale,
            );
            expect([
              edge.red,
              edge.green,
              edge.blue,
            ], everyElement(lessThan(40)));
          }
        },
      );
    }
  }

  test('layout signatures leave the photo unchanged; poster title has ink on both sides', () async {
    final source = await buildFlatTestImage(
      width: 1080,
      height: 1350,
      red: 220,
      green: 20,
      blue: 20,
    );
    addTearDown(source.dispose);
    for (final layout in [ExportLayout.soundStrip, ExportLayout.poster]) {
      final image = await ExportService(
        log: DebugLog(),
      ).compose(source, ExportFormat.original, layout: layout, values: values);
      addTearDown(image.dispose);
      final pixels = await imagePixels(image);
      final plan = ExportLayoutPlan.build(
        layout: layout,
        photoWidth: 1080,
        photoHeight: 1350,
      );
      // The old photo signature occupied this lower-right sample.
      for (final point in [
        plan.photo.center,
        plan.photo.bottomRight - const ui.Offset(50, 30),
      ]) {
        final rgb = pixelAt(
          pixels,
          image.width,
          point.dx.toInt(),
          point.dy.toInt(),
        );
        expect(rgb, (red: 220, green: 20, blue: 20));
      }
      if (layout == ExportLayout.poster) {
        final y0 = (plan.photo.bottom + .025 * 1080).floor();
        final y1 = (plan.photo.bottom + .08 * 1080).ceil();
        int inkCount(int left, int right) {
          var count = 0;
          for (var y = y0; y < y1; y++) {
            for (var x = left; x < right; x++) {
              final c = pixelAt(pixels, image.width, x, y);
              if (c.red < 100 && c.green < 100 && c.blue < 100) count++;
            }
          }
          return count;
        }

        expect(
          inkCount(plan.photo.left.toInt(), plan.photo.center.dx.toInt()),
          greaterThan(0),
        );
        expect(
          inkCount(plan.photo.center.dx.toInt(), plan.photo.right.toInt()),
          greaterThan(0),
        );
      }
    }
  });

  test(
    'empty band falls back to Full and reports only the layout reason',
    () async {
      final log = DebugLog();
      final source = await buildFlatTestImage(width: 200, height: 100);
      addTearDown(source.dispose);
      final image = await ExportService(log: log).compose(
        source,
        ExportFormat.original,
        layout: ExportLayout.soundStrip,
        watermark: false,
      );
      addTearDown(image.dispose);
      expect((image.width, image.height), (200, 100));
      expect(
        log.recentLines.join('\n'),
        contains('empty sound strip falls back to full'),
      );
    },
  );

  test('the sound strip adds a dark band under the picture', () async {
    final service = ExportService(log: DebugLog());
    final source = await buildFlatTestImage(
      width: 200,
      height: 100,
      red: 220,
      green: 20,
      blue: 20,
    );
    addTearDown(source.dispose);

    final composed = await service.compose(
      source,
      ExportFormat.original,
      watermark: false,
      layout: ExportLayout.soundStrip,
      values: values,
    );
    addTearDown(composed.dispose);

    final plan = ExportLayoutPlan.build(
      layout: ExportLayout.soundStrip,
      photoWidth: 200,
      photoHeight: 100,
    );
    expect(composed.width, plan.width);
    expect(composed.height, plan.height);
    expect(composed.height, 100 + plan.bandHeight);

    final pixels = await imagePixels(composed);
    // The picture is still the picture.
    final photo = pixelAt(pixels, composed.width, 100, 50);
    expect(photo.red, greaterThan(200));
    expect(photo.green, lessThan(40));
    // The band is dark.
    final band = pixelAt(
      pixels,
      composed.width,
      composed.width ~/ 2,
      plan.photo.height.toInt() + 2,
    );
    expect(band.red, lessThan(40));
    expect(band.green, lessThan(40));
    expect(band.blue, lessThan(40));
  });

  test('the poster puts the picture inside a light frame', () async {
    final service = ExportService(log: DebugLog());
    final source = await buildFlatTestImage(
      width: 200,
      height: 100,
      red: 220,
      green: 20,
      blue: 20,
    );
    addTearDown(source.dispose);

    final composed = await service.compose(
      source,
      ExportFormat.original,
      watermark: false,
      layout: ExportLayout.poster,
      values: values,
    );
    addTearDown(composed.dispose);

    final plan = ExportLayoutPlan.build(
      layout: ExportLayout.poster,
      photoWidth: 200,
      photoHeight: 100,
    );
    expect(composed.width, plan.width);
    expect(composed.height, plan.height);
    expect(composed.width, 200 + plan.frameWidth * 2);
    expect(composed.height, 100 + plan.frameWidth * 2 + plan.captionHeight);

    final pixels = await imagePixels(composed);
    // The paper of the frame is light.
    final paper = pixelAt(pixels, composed.width, 3, 3);
    expect(paper.red, greaterThan(200));
    expect(paper.green, greaterThan(200));
    expect(paper.blue, greaterThan(200));
    // The picture is inside the frame, at the place of the plan.
    final photo = pixelAt(
      pixels,
      composed.width,
      plan.frameWidth + 100,
      plan.frameWidth + 50,
    );
    expect(photo.red, greaterThan(200));
    expect(photo.green, lessThan(40));
  });

  test('the full layout is the picture alone', () async {
    final service = ExportService(log: DebugLog());
    final source = await buildFlatTestImage(width: 200, height: 100);
    addTearDown(source.dispose);

    final composed = await service.compose(
      source,
      ExportFormat.original,
      watermark: false,
      layout: ExportLayout.full,
    );
    addTearDown(composed.dispose);

    expect(composed.width, 200);
    expect(composed.height, 100);
  });
}
