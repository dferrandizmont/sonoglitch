import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_geometry.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_layout_painter.dart';
import 'package:sonoglitch/export/export_readings.dart';
import 'package:sonoglitch/export/export_service.dart';

import '../support/fakes.dart';

/// Counts what a painter draws; anything unexpected (saveLayer, blur) throws.
class _CountingCanvas implements Canvas {
  int rects = 0;
  int paragraphs = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects++;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}

  @override
  void translate(double dx, double dy) {}

  @override
  void scale(double sx, [double? sy]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not expected');
}

ExportLayoutValues _values(
  ExportReadingsMode mode, {
  String? id = 'A3F9-17C2',
  bool spectrum = true,
}) => ExportLayoutValues(
  styleName: 'Static',
  noiseDb: 72,
  lux: 240,
  accel: 1.5,
  noise: .5,
  light: .25,
  motion: .75,
  bass: .3,
  mid: .2,
  treble: .1,
  spectrumAvailable: spectrum,
  readingsMode: mode,
  photoId: id,
);

({int rects, int paragraphs}) _paint(
  ExportLayout layout,
  ExportLayoutValues values, {
  bool watermark = true,
}) {
  final plan = ExportLayoutPlan.build(
    layout: layout,
    photoWidth: 1000,
    photoHeight: 1250,
    readings: hasExportReadings(values),
    readingsMode: values.readingsMode,
    watermark: watermark,
    photoId: values.photoId,
  );
  final canvas = _CountingCanvas();
  ExportLayoutPainter(
    layout: layout,
    plan: plan,
    values: values,
    watermark: watermark,
  ).paintForeground(canvas);
  return (rects: canvas.rects, paragraphs: canvas.paragraphs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sizes follow what remains to print', () {
    ExportLayoutPlan plan(
      ExportLayout layout,
      ExportReadingsMode mode, {
      bool readings = true,
      bool context = false,
      bool watermark = true,
      String? id,
    }) => ExportLayoutPlan.build(
      layout: layout,
      photoWidth: 1000,
      photoHeight: 1250,
      readings: readings,
      readingsMode: mode,
      context: context,
      watermark: watermark,
      photoId: id,
    );

    test('the sound strip band', () {
      expect(
        plan(ExportLayout.soundStrip, ExportReadingsMode.full).bandHeight,
        155,
      );
      expect(
        plan(ExportLayout.soundStrip, ExportReadingsMode.numbers).bandHeight,
        135,
      );
      expect(
        plan(ExportLayout.soundStrip, ExportReadingsMode.hidden).bandHeight,
        75,
      );
      expect(
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.hidden,
          context: true,
        ).bandHeight,
        123,
      );
    });

    test('the poster caption', () {
      expect(
        plan(ExportLayout.poster, ExportReadingsMode.full).captionHeight,
        210,
      );
      expect(
        plan(ExportLayout.poster, ExportReadingsMode.numbers).captionHeight,
        180,
      );
      expect(
        plan(ExportLayout.poster, ExportReadingsMode.hidden).captionHeight,
        110,
      );
      expect(
        plan(
          ExportLayout.poster,
          ExportReadingsMode.numbers,
          context: true,
        ).captionHeight,
        225,
      );
    });

    test('numbers without any number shrinks like hidden', () {
      expect(
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.numbers,
          readings: false,
        ).bandHeight,
        75,
      );
      expect(
        plan(
          ExportLayout.poster,
          ExportReadingsMode.numbers,
          readings: false,
        ).captionHeight,
        110,
      );
    });

    test('the full layout ignores the mode', () {
      final reference = plan(ExportLayout.full, ExportReadingsMode.full);
      for (final mode in ExportReadingsMode.values) {
        final other = plan(ExportLayout.full, mode);
        expect(other.width, reference.width);
        expect(other.height, reference.height);
        expect(other.bandHeight, 0);
        expect(other.captionHeight, 0);
      }
    });

    test('the strip falls back to full only when nothing remains', () {
      expect(
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.hidden,
          readings: false,
          watermark: false,
        ).bandHeight,
        0,
      );
      for (final keep in [
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.hidden,
          readings: false,
        ),
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.hidden,
          readings: false,
          watermark: false,
          id: 'A3F9-17C2',
        ),
        plan(
          ExportLayout.soundStrip,
          ExportReadingsMode.hidden,
          readings: false,
          watermark: false,
          context: true,
        ),
      ]) {
        expect(keep.bandHeight, greaterThan(0));
      }
    });

    test('sizes stay deterministic fractions of the shorter side', () {
      for (final mode in ExportReadingsMode.values) {
        for (final side in [10, 100, 4096]) {
          final a = ExportLayoutPlan.build(
            layout: ExportLayout.soundStrip,
            photoWidth: side,
            photoHeight: side * 2,
            readingsMode: mode,
          );
          final b = ExportLayoutPlan.build(
            layout: ExportLayout.soundStrip,
            photoWidth: side,
            photoHeight: side * 2,
            readingsMode: mode,
          );
          expect(a.bandHeight, b.bandHeight);
          expect(a.bandHeight, greaterThanOrEqualTo(1));
        }
      }
    });
  });

  group('what the values expose', () {
    test('hidden has no readings, numbers has no spectrum or ladders', () {
      final hidden = _values(ExportReadingsMode.hidden);
      expect(readingsOf(hidden), isEmpty);
      expect(hasExportReadings(hidden), isFalse);
      expect(showsExportSpectrum(hidden), isFalse);
      final numbers = _values(ExportReadingsMode.numbers);
      expect(readingsOf(numbers), hasLength(3));
      expect(hasExportReadings(numbers), isTrue);
      expect(showsExportLadders(numbers), isFalse);
      expect(showsExportSpectrum(numbers), isFalse);
      final full = _values(ExportReadingsMode.full);
      expect(showsExportLadders(full), isTrue);
      expect(showsExportSpectrum(full), isTrue);
    });
  });

  group('the painter draws only what the mode allows', () {
    test('sound strip', () {
      final full = _paint(
        ExportLayout.soundStrip,
        _values(ExportReadingsMode.full),
      );
      final numbers = _paint(
        ExportLayout.soundStrip,
        _values(ExportReadingsMode.numbers),
      );
      final hidden = _paint(
        ExportLayout.soundStrip,
        _values(ExportReadingsMode.hidden),
      );
      // Band and hairline, then a key per number, then 8 cells per number
      // and 3 ladders of 5 cells.
      expect(hidden.rects, 2);
      expect(numbers.rects, 2 + 3);
      expect(full.rects, 2 + 3 + 3 * 8 + 3 * 5);
      // Labels and values of three numbers, then three spectrum labels.
      expect(numbers.paragraphs - hidden.paragraphs, 6);
      expect(full.paragraphs - numbers.paragraphs, 3);
    });

    test('poster', () {
      final full = _paint(
        ExportLayout.poster,
        _values(ExportReadingsMode.full),
      );
      final numbers = _paint(
        ExportLayout.poster,
        _values(ExportReadingsMode.numbers),
      );
      final hidden = _paint(
        ExportLayout.poster,
        _values(ExportReadingsMode.hidden),
      );
      expect(numbers.rects - hidden.rects, 3);
      expect(full.rects - numbers.rects, 3 * 8 + 3 * 5);
      expect(numbers.paragraphs - hidden.paragraphs, 6);
      expect(full.paragraphs - numbers.paragraphs, 3);
    });

    test('the photo ID and the watermark stay in every mode', () {
      for (final layout in [ExportLayout.soundStrip, ExportLayout.poster]) {
        for (final mode in ExportReadingsMode.values) {
          final withId = _paint(layout, _values(mode));
          final noId = _paint(layout, _values(mode, id: null));
          final noMark = _paint(layout, _values(mode), watermark: false);
          expect(
            withId.paragraphs,
            noId.paragraphs + 1,
            reason: '$layout $mode',
          );
          expect(
            withId.paragraphs,
            greaterThan(noMark.paragraphs),
            reason: '$layout $mode',
          );
        }
      }
    });

    test('the full layout draws nothing whatever the mode', () {
      for (final mode in ExportReadingsMode.values) {
        final counts = _paint(ExportLayout.full, _values(mode));
        expect(counts.rects, 0);
        expect(counts.paragraphs, 0);
      }
    });
  });

  group('the geometry of the strip', () {
    test('without readings the ID and the signature share a centred row', () {
      final full = ExportLayoutPlan.build(
        layout: ExportLayout.soundStrip,
        photoWidth: 1000,
        photoHeight: 1250,
      );
      final hiddenPlan = ExportLayoutPlan.build(
        layout: ExportLayout.soundStrip,
        photoWidth: 1000,
        photoHeight: 1250,
        readingsMode: ExportReadingsMode.hidden,
      );
      final a = SoundStripGeometry.compute(full, const []);
      final b = SoundStripGeometry.compute(
        hiddenPlan,
        const [],
        spectrum: false,
        mode: ExportReadingsMode.hidden,
      );
      expect(a.idAtRight, isTrue);
      expect(b.idAtRight, isFalse);
      expect(b.idBaseline.dy, b.wordmarkOrigin.dy);
      expect(b.idBaseline.dy, lessThan(hiddenPlan.photo.bottom + 75));
      expect(b.ladders, isEmpty);
    });

    test('the content of every mode fits inside its band', () {
      for (final mode in ExportReadingsMode.values) {
        final plan = ExportLayoutPlan.build(
          layout: ExportLayout.soundStrip,
          photoWidth: 1000,
          photoHeight: 1250,
          readingsMode: mode,
        );
        final readings = mode == ExportReadingsMode.hidden
            ? const <ExportReading>[]
            : readingsOf(_values(mode));
        final geometry = SoundStripGeometry.compute(
          plan,
          readings,
          spectrum: mode == ExportReadingsMode.full,
          mode: mode,
        );
        expect(geometry.idBaseline.dy, lessThan(geometry.band.bottom));
        expect(geometry.wordmarkOrigin.dy, lessThan(geometry.band.bottom));
        for (final slot in geometry.slots) {
          expect(slot.valueBaseline.dy, lessThan(geometry.band.bottom));
          if (mode == ExportReadingsMode.full) {
            expect(slot.cells.last.bottom, lessThan(geometry.band.bottom));
          }
        }
      }
    });
  });

  group('the composition', () {
    test('has the plan size in every mode and keeps the photo size', () async {
      final source = await buildFlatTestImage(width: 400, height: 500);
      addTearDown(source.dispose);
      const heights = {
        ExportReadingsMode.full: 62,
        ExportReadingsMode.numbers: 54,
        ExportReadingsMode.hidden: 30,
      };
      for (final mode in ExportReadingsMode.values) {
        final composed = await ExportService(log: DebugLog()).compose(
          source,
          ExportFormat.original,
          layout: ExportLayout.soundStrip,
          values: _values(mode),
        );
        addTearDown(composed.dispose);
        expect(composed.width, 400);
        expect(composed.height, 500 + heights[mode]!, reason: '$mode');
        final full = await ExportService(log: DebugLog())
            .compose(source, ExportFormat.original, values: _values(mode));
        addTearDown(full.dispose);
        expect(full.height, 500);
      }
    });
  });
}
