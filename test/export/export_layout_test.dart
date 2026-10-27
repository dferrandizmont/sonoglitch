import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/export/export_layout.dart';

void main() {
  group('the size of the layouts', () {
    test(
      'new ratios, context heights, compact caption and empty strip fallback',
      () {
        ExportLayoutPlan plan(
          ExportLayout layout, {
          bool readings = true,
          bool context = false,
          bool watermark = true,
        }) => ExportLayoutPlan.build(
          layout: layout,
          photoWidth: 1000,
          photoHeight: 1250,
          readings: readings,
          context: context,
          watermark: watermark,
        );
        expect(plan(ExportLayout.soundStrip).bandHeight, 155);
        expect(plan(ExportLayout.soundStrip, context: true).bandHeight, 203);
        expect(plan(ExportLayout.poster).captionHeight, 210);
        expect(plan(ExportLayout.poster, context: true).captionHeight, 255);
        expect(plan(ExportLayout.poster, readings: false).captionHeight, 110);
        expect(
          plan(
            ExportLayout.poster,
            readings: false,
            context: true,
          ).captionHeight,
          155,
        );
        final empty = plan(
          ExportLayout.soundStrip,
          readings: false,
          watermark: false,
        );
        expect(empty.height, 1250);
        expect(empty.bandHeight, 0);
        expect(plan(ExportLayout.soundStrip, readings: false).bandHeight, 155);
        expect(
          plan(
            ExportLayout.soundStrip,
            readings: false,
            watermark: false,
            context: true,
          ).bandHeight,
          203,
        );
      },
    );
    test('only a non-empty photo ID keeps an otherwise empty strip', () {
      for (final id in [null, '', 'A3F9-17C2']) {
        final plan = ExportLayoutPlan.build(
          layout: ExportLayout.soundStrip,
          photoWidth: 1000,
          photoHeight: 1250,
          readings: false,
          watermark: false,
          photoId: id,
        );
        final band = id == 'A3F9-17C2' ? 155 : 0;
        expect(plan.bandHeight, band);
        expect(plan.height, 1250 + band);
        expect(plan.photo, const Rect.fromLTWH(0, 0, 1000, 1250));
      }
    });
    test('the full layout is the picture alone', () {
      final plan = ExportLayoutPlan.build(
        layout: ExportLayout.full,
        photoWidth: 4000,
        photoHeight: 3000,
      );
      expect(plan.width, 4000);
      expect(plan.height, 3000);
      expect(plan.photo, const Rect.fromLTWH(0, 0, 4000, 3000));
      expect(plan.bandHeight, 0);
      expect(plan.frameWidth, 0);
      expect(plan.captionHeight, 0);
    });

    test('the band of the sound strip is a fraction of the shorter side', () {
      for (final size in [(4000, 3000), (3000, 4000), (2048, 2048)]) {
        final plan = ExportLayoutPlan.build(
          layout: ExportLayout.soundStrip,
          photoWidth: size.$1,
          photoHeight: size.$2,
        );
        final shorter = size.$1 < size.$2 ? size.$1 : size.$2;
        expect(
          plan.bandHeight,
          (shorter * ExportLayoutPlan.bandHeightRatio).round(),
          reason: '$size',
        );
        // The band is added under the picture: the picture is not shrunk.
        expect(plan.width, size.$1);
        expect(plan.height, size.$2 + plan.bandHeight);
        expect(
          plan.photo,
          Rect.fromLTWH(0, 0, size.$1.toDouble(), size.$2.toDouble()),
        );
        expect(plan.frameWidth, 0);
        expect(plan.captionHeight, 0);
      }
    });

    test('the frame of the poster is a fraction of the width', () {
      for (final size in [(4000, 3000), (3000, 4000), (1080, 1920)]) {
        final plan = ExportLayoutPlan.build(
          layout: ExportLayout.poster,
          photoWidth: size.$1,
          photoHeight: size.$2,
        );
        final shorter = size.$1 < size.$2 ? size.$1 : size.$2;
        expect(
          plan.frameWidth,
          (size.$1 * ExportLayoutPlan.frameWidthRatio).round(),
          reason: '$size',
        );
        expect(
          plan.captionHeight,
          (shorter * ExportLayoutPlan.captionHeightRatio).round(),
          reason: '$size',
        );
        // The frame and the caption are added around the picture.
        expect(plan.width, size.$1 + plan.frameWidth * 2);
        expect(plan.height, size.$2 + plan.frameWidth * 2 + plan.captionHeight);
        expect(
          plan.photo,
          Rect.fromLTWH(
            plan.frameWidth.toDouble(),
            plan.frameWidth.toDouble(),
            size.$1.toDouble(),
            size.$2.toDouble(),
          ),
        );
      }
    });

    test('the picture keeps its size in every layout', () {
      for (final layout in ExportLayout.values) {
        final plan = ExportLayoutPlan.build(
          layout: layout,
          photoWidth: 4000,
          photoHeight: 3000,
        );
        expect(plan.photo.width, 4000, reason: '$layout');
        expect(plan.photo.height, 3000, reason: '$layout');
        expect(plan.width, greaterThanOrEqualTo(4000), reason: '$layout');
        expect(plan.height, greaterThanOrEqualTo(3000), reason: '$layout');
      }
    });

    test('a tiny picture still gets a band and a frame of one pixel', () {
      final band = ExportLayoutPlan.build(
        layout: ExportLayout.soundStrip,
        photoWidth: 4,
        photoHeight: 4,
      );
      expect(band.bandHeight, 1);
      final poster = ExportLayoutPlan.build(
        layout: ExportLayout.poster,
        photoWidth: 4,
        photoHeight: 4,
      );
      expect(poster.frameWidth, 1);
      expect(poster.captionHeight, 1);
    });

    test('invalid sizes are rejected', () {
      expect(
        () => ExportLayoutPlan.build(
          layout: ExportLayout.full,
          photoWidth: 0,
          photoHeight: 3000,
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportLayoutPlan.build(
          layout: ExportLayout.poster,
          photoWidth: 4000,
          photoHeight: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the values of the layouts', () {
    test('the values of a capture carry the measured numbers', () {
      final values = ExportLayoutValues.fromAmbient(
        const AmbientState(
          noise: 0.4,
          light: 0.6,
          motion: 0.2,
          rawDb: 72,
          rawLux: 240,
          rawAccel: 1.5,
          bass: 0.3,
          mid: 0.2,
          treble: 0.1,
        ),
        styleName: 'Static',
      );
      expect(values.styleName, 'Static');
      expect(values.noiseDb, 72);
      expect(values.lux, 240);
      expect(values.accel, 1.5);
      expect(values.noise, 0.4);
      expect(values.light, 0.6);
      expect(values.motion, 0.2);
      expect(values.spectrumAvailable, isTrue);
    });

    test('a phone without a spectrum leaves the three bands out', () {
      final values = ExportLayoutValues.fromAmbient(
        AmbientState.calm,
        styleName: 'Tape',
      );
      expect(values.spectrumAvailable, isFalse);
      expect(values.bass, 0);
      expect(values.mid, 0);
      expect(values.treble, 0);
      expect(values.noiseDb, isNull);
      expect(values.lux, isNull);
    });
  });
}
