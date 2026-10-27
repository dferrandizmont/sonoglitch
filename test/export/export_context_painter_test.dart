import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_service.dart';

import '../support/fakes.dart';
import 'export_service_test.dart' show imagePixels, areaDifference;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an ID alone keeps the strip and is drawn with watermark off', () async {
    final source = await buildFlatTestImage(width: 1080, height: 1350);
    addTearDown(source.dispose);
    final service = ExportService(log: DebugLog());
    final image = await service.compose(
      source,
      ExportFormat.original,
      layout: ExportLayout.soundStrip,
      watermark: false,
      values: const ExportLayoutValues(styleName: '', photoId: 'A3F9-17C2'),
    );
    addTearDown(image.dispose);
    final plan = ExportLayoutPlan.build(
      layout: ExportLayout.soundStrip,
      photoWidth: 1080,
      photoHeight: 1350,
      readings: false,
      watermark: false,
      photoId: 'A3F9-17C2',
    );
    expect(plan.bandHeight, (1080 * ExportLayoutPlan.bandHeightRatio).round());
    expect((image.width, image.height), (plan.width, plan.height));
    final pixels = await imagePixels(image);
    // Check for text ink in the ID reserve without depending on glyph shapes.
    var ink = 0;
    for (var y = (1350 + .11 * 1080).floor(); y < image.height; y++) {
      for (var x = (1080 - .3 * 1080).floor(); x < 1080; x++) {
        final i = (y * image.width + x) * 4;
        if (pixels[i] > 100 && pixels[i + 1] > 100 && pixels[i + 2] > 100) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(0));
    final empty = await service.compose(
      source,
      ExportFormat.original,
      layout: ExportLayout.soundStrip,
      watermark: false,
      values: const ExportLayoutValues(styleName: ''),
    );
    addTearDown(empty.dispose);
    expect((empty.width, empty.height), (source.width, source.height));
  });
  for (final layout in [ExportLayout.soundStrip, ExportLayout.poster]) {
    test(
      '$layout context adds exactly one row; ID stays in its reserved area',
      () async {
        final source = await buildFlatTestImage(width: 1080, height: 1350);
        addTearDown(source.dispose);
        final service = ExportService(log: DebugLog());
        Future<ui.Image> compose({
          bool id = false,
          ExportContext? context,
        }) async {
          final image = await service.compose(
            source,
            ExportFormat.original,
            layout: layout,
            values: ExportLayoutValues(
              styleName: 'Prism',
              photoId: id ? 'A3F9-17C2' : null,
              context: context,
            ),
          );
          addTearDown(image.dispose);
          return image;
        }

        final plain = await compose();
        final withId = await compose(id: true);
        expect((withId.width, withId.height), (plain.width, plain.height));
        final plan = ExportLayoutPlan.build(
          layout: layout,
          photoWidth: 1080,
          photoHeight: 1350,
          readings: false,
        );
        final idTop =
            plan.photo.bottom +
            (layout == ExportLayout.poster ? .075 : .12) * 1080;
        final idBottom =
            plan.photo.bottom +
            (layout == ExportLayout.poster ? .108 : .15) * 1080;
        expect(
          areaDifference(
            await imagePixels(plain),
            await imagePixels(withId),
            plain.width,
            left: (plan.photo.right - .3 * 1080).floor(),
            top: idTop.floor(),
            right: plan.photo.right.ceil(),
            bottom: idBottom.ceil(),
          ),
          greaterThan(0),
        );
        final withContext = await compose(
          context: ExportContext(
            dateTime: DateTime(2026, 10, 26, 21, 32),
            heading: 42,
            pressure: 1013,
          ),
        );
        final expected = ExportLayoutPlan.build(
          layout: layout,
          photoWidth: 1080,
          photoHeight: 1350,
          readings: false,
          context: true,
        );
        expect(
          (withContext.width, withContext.height),
          (expected.width, expected.height),
        );
        expect(
          withContext.height - plain.height,
          closeTo((layout == ExportLayout.poster ? .045 : .048) * 1080, 1),
        );
        final pixels = await imagePixels(withContext);
        final top =
            (plan.photo.bottom +
                    (layout == ExportLayout.poster ? .11 : .155) * 1080)
                .ceil() +
            3;
        var secondary = 0;
        final target = layout == ExportLayout.poster
            ? const ui.Color(0xFF6B6B78)
            : const ui.Color(0xFFA5A5B2);
        for (var y = top; y < top + (.035 * 1080).floor(); y++) {
          for (
            var x = plan.photo.left.toInt();
            x < plan.photo.right.toInt();
            x++
          ) {
            final i = (y * withContext.width + x) * 4;
            if ((pixels[i] - target.r * 255).abs() < 2 &&
                (pixels[i + 1] - target.g * 255).abs() < 2 &&
                (pixels[i + 2] - target.b * 255).abs() < 2) {
              secondary++;
            }
          }
        }
        expect(secondary, greaterThan(0));
      },
    );
  }
  test('Full ignores all optional context without reserving a row', () async {
    final source = await buildFlatTestImage(width: 200, height: 300);
    addTearDown(source.dispose);
    final service = ExportService(log: DebugLog());
    final plain = await service.compose(
      source,
      ExportFormat.original,
      watermark: false,
    );
    final context = await service.compose(
      source,
      ExportFormat.original,
      watermark: false,
      values: ExportLayoutValues(
        styleName: 'Prism',
        context: ExportContext(dateTime: DateTime(2026)),
      ),
    );
    addTearDown(plain.dispose);
    addTearDown(context.dispose);
    expect((context.width, context.height), (200, 300));
    expect(await imagePixels(context), orderedEquals(await imagePixels(plain)));
  });
}
