import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/export/export_geometry.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_readings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Ahem's square glyphs do not model production label widths. Use the
    // Flutter SDK's bundled Roboto when the SDK root is known; otherwise the
    // test font still gives consistent measured widths.
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) return;
    final font = File(
      '$root/bin/cache/artifacts/material_fonts/roboto-medium.ttf',
    );
    if (!font.existsSync()) return;
    final loader = FontLoader('ExportGeometryRoboto')
      ..addFont(font.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });
  final readings = readingsOf(
    const ExportLayoutValues(
      styleName: 'Prism',
      noiseDb: 28,
      lux: 42,
      accel: .16,
    ),
  );
  ExportLayoutPlan plan(
    ExportLayout layout,
    int scale, {
    bool context = false,
  }) => ExportLayoutPlan.build(
    layout: layout,
    photoWidth: 1080 * scale,
    photoHeight: 1350 * scale,
    context: context,
  );
  void scaledRect(Rect a, Rect b, [double tolerance = 1]) {
    for (final pair in [
      (a.left, b.left),
      (a.top, b.top),
      (a.width, b.width),
      (a.height, b.height),
    ]) {
      expect(pair.$2, closeTo(4 * pair.$1, tolerance));
    }
  }

  void containedAndSeparate(Rect bounds, List<Rect> rects, double u) {
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      expect(bounds.contains(r.topLeft), isTrue, reason: '$r');
      expect(r.right, lessThanOrEqualTo(bounds.right + 1e-6));
      expect(r.bottom, lessThanOrEqualTo(bounds.bottom + 1e-6));
      expect(r.shortestSide, greaterThanOrEqualTo(.0015 * u));
      for (var j = i + 1; j < rects.length; j++) {
        expect(r.overlaps(rects[j]), isFalse, reason: '$r / ${rects[j]}');
      }
    }
  }

  test(
    'strip cells, instruments and wordmark block stay disjoint at 1x and 4x',
    () {
      final a = SoundStripGeometry.compute(
        plan(ExportLayout.soundStrip, 1),
        readings,
      );
      final b = SoundStripGeometry.compute(
        plan(ExportLayout.soundStrip, 4),
        readings,
      );
      List<Rect> rects(SoundStripGeometry g) => [
        ...g.slots.expand((s) => [s.key, ...s.cells]),
        ...g.ladders.expand((s) => s.cells),
        Rect.fromLTWH(
          g.wordmarkOrigin.dx,
          g.wordmarkOrigin.dy - g.wordmarkSize,
          g.wordmarkWidth,
          g.wordmarkSize,
        ),
      ];
      final ar = rects(a), br = rects(b);
      containedAndSeparate(a.band, ar, 1080);
      containedAndSeparate(b.band, br, 4320);
      for (var i = 0; i < ar.length; i++) {
        scaledRect(ar[i], br[i]);
      }
      for (var i = 1; i < a.slots.length; i++) {
        expect(
          a.slots[i].bounds.left - a.slots[i - 1].bounds.left,
          closeTo(.205 * 1080, .001),
        );
      }
    },
  );
  test('poster spectrum label rects fit and stay separate at 1x and 4x', () {
    const labels = ['160 Hz', '2k Hz', '8k Hz'];
    final rects = <List<Rect>>[];
    for (final scale in [1, 4]) {
      final p = plan(ExportLayout.poster, scale);
      final geometry = PosterGeometry.compute(p, readings);
      final u = 1080.0 * scale;
      final bounds = <Rect>[];
      for (var i = 0; i < labels.length; i++) {
        final f = .019 * u;
        final text = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontFamily: 'ExportGeometryRoboto',
              fontSize: f,
              fontWeight: FontWeight.w600,
              letterSpacing: .1 * f,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        try {
          final ladder = geometry.ladders[i];
          final rect = ladder.labelBounds(
            text.size,
            text.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          );
          bounds.add(rect);
          expect(rect.right, closeTo(ladder.cells.first.right, 1e-6));
          expect(rect.right, lessThanOrEqualTo(p.photo.right + 1e-6));
          if (i > 0) {
            expect(
              ladder.cells.first.left -
                  geometry.ladders[i - 1].cells.first.left,
              closeTo(.062 * u, 1e-6),
            );
          }
        } finally {
          text.dispose();
        }
      }
      containedAndSeparate(
        Rect.fromLTWH(
          p.photo.left,
          p.photo.bottom,
          p.photo.width,
          p.captionHeight.toDouble(),
        ),
        bounds,
        u,
      );
      rects.add(bounds);
    }
    for (var i = 0; i < labels.length; i++) {
      // Text advances round per glyph, so measured labels scale within 2 px.
      scaledRect(rects[0][i], rects[1][i], 2);
    }
  });
  test('landscape adds empty space and missing readings pack left', () {
    final portrait = SoundStripGeometry.compute(
      plan(ExportLayout.soundStrip, 1),
      readings,
    );
    final landscape = SoundStripGeometry.compute(
      ExportLayoutPlan.build(
        layout: ExportLayout.soundStrip,
        photoWidth: 1920,
        photoHeight: 1080,
      ),
      readings,
    );
    expect(
      landscape.slots.map((s) => s.bounds.width),
      portrait.slots.map((s) => s.bounds.width),
    );
    expect(
      landscape.slots.map((s) => s.bounds.left),
      portrait.slots.map((s) => s.bounds.left),
    );
    expect(
      landscape.ladders.first.cells.first.left,
      greaterThan(portrait.ladders.first.cells.first.left),
    );
    final light = readingsOf(const ExportLayoutValues(styleName: '', lux: 0));
    expect(
      SoundStripGeometry.compute(
        plan(ExportLayout.soundStrip, 1),
        light,
      ).slots.single.bounds.left,
      portrait.slots.first.bounds.left,
    );
  });
  test(
    'poster preserves scale, fixed instrument sizes and print registration',
    () {
      final p = plan(ExportLayout.poster, 1), q = plan(ExportLayout.poster, 4);
      final a = PosterGeometry.compute(p, readings),
          b = PosterGeometry.compute(q, readings);
      final ar = [
        ...a.slots.expand((s) => [s.key, ...s.cells]),
        ...a.ladders.expand((s) => s.cells),
        ...a.registration,
      ];
      final br = [
        ...b.slots.expand((s) => [s.key, ...s.cells]),
        ...b.ladders.expand((s) => s.cells),
        ...b.registration,
      ];
      containedAndSeparate(
        Rect.fromLTWH(
          p.photo.left,
          p.photo.bottom,
          p.photo.width,
          p.captionHeight.toDouble(),
        ),
        ar,
        1080,
      );
      for (var i = 0; i < ar.length; i++) {
        scaledRect(ar[i], br[i]);
      }
      scaledRect(a.rule, b.rule);
      expect(a.titleBaseline.dx, p.photo.left);
      expect(a.wordmarkOrigin.dx, greaterThan(p.photo.center.dx));
      expect(a.rule.height, closeTo(.0016 * 1080, .001));
    },
  );
}
