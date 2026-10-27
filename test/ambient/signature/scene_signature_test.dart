import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/scene_signature.dart';

SceneColorReading fixture(List<(int, int, int)> colors) {
  final accumulator = SceneColorfulness();
  for (final (r, g, b) in colors) {
    accumulator.add(r, g, b);
  }
  return accumulator.finish();
}

void main() {
  test('empty and grey are neutral, independent of brightness', () {
    expect(SceneColorfulness().finish().allowance, 1);
    final grey = fixture([
      (0, 0, 0),
      (80, 80, 80),
      (128, 128, 128),
      (255, 255, 255),
    ]);
    expect(grey.colorfulness, 0);
    expect(grey.meanSaturation, 0);
    expect(grey.allowance, 1);
  });
  test('synthetic calibration distinguishes muted, photo-like and vivid', () {
    final muted = fixture([(136, 120, 120), (120, 136, 120), (120, 120, 136)]);
    final photo = fixture([
      (120, 85, 60),
      (100, 150, 190),
      (70, 110, 60),
      (190, 140, 115),
    ]);
    final vivid = fixture([(255, 0, 0), (0, 255, 0), (0, 0, 255)]);
    expect(muted.colorfulness, lessThan(SceneColorfulness.low));
    expect(muted.colorfulness, closeTo(17.28, .01));
    expect(muted.allowance, 1);
    expect(
      photo.colorfulness,
      inExclusiveRange(SceneColorfulness.low, SceneColorfulness.high),
    );
    expect(photo.colorfulness, closeTo(68.41, .01));
    expect(photo.allowance, inExclusiveRange(.65, 1));
    expect(vivid.colorfulness, closeTo(255 * math.sqrt(7 / 6), 1e-10));
    expect(vivid.allowance, closeTo(.65, 1e-12));
    expect(vivid.meanSaturation, 1);
    // A constant vivid colour still contributes through the opponent mean.
    expect(
      fixture([(255, 0, 0)]).colorfulness,
      closeTo(.3 * math.sqrt(255 * 255 + 127.5 * 127.5), 1e-10),
    );
    expect(fixture([(255, 0, 0)]).allowance, closeTo(.65, 1e-12));
  });
  test(
    'Welford population variance is order independent and finish is stable',
    () {
      final colors = [(255, 128, 0), (12, 40, 80), (200, 100, 80)];
      expect(
        fixture(colors).colorfulness,
        closeTo(fixture(colors.reversed.toList()).colorfulness, 1e-10),
      );
      final accumulator = SceneColorfulness()..add(1, 2, 3);
      expect(
        accumulator.finish().colorfulness,
        accumulator.finish().colorfulness,
      );
      expect(fixture([(-10, 300, 0)]).allowance, inInclusiveRange(.65, 1));
    },
  );
  test(
    'sample grid is bounded, uniform, unique, and inside any aspect ratio',
    () {
      for (final size in [
        (0, 100),
        (10, -1),
        (1, 1),
        (8, 4),
        (1920, 1080),
        (1080, 1920),
        (100000, 1),
        (1, 100000),
      ]) {
        final points = sceneSamplePoints(size.$1, size.$2);
        expect(points.length, lessThanOrEqualTo(1024));
        expect(points.toSet().length, points.length);
        if (size.$1 <= 0 || size.$2 <= 0) {
          expect(points, isEmpty);
          continue;
        }
        expect(points, isNotEmpty);
        for (final p in points) {
          expect(p.x, inInclusiveRange(0, size.$1 - 1));
          expect(p.y, inInclusiveRange(0, size.$2 - 1));
        }
        final xs = points.map((p) => p.x).toSet().toList()..sort();
        final ys = points.map((p) => p.y).toSet().toList()..sort();
        for (final coords in [xs, ys]) {
          final gaps = [
            for (var i = 1; i < coords.length; i++) coords[i] - coords[i - 1],
          ];
          if (gaps.isNotEmpty) {
            expect(
              gaps.reduce(math.max) - gaps.reduce(math.min),
              lessThanOrEqualTo(1),
            );
          }
        }
      }
    },
  );
  test('the grid helper describes the same points as the point list', () {
    for (final size in [
      (0, 100),
      (10, -1),
      (1, 1),
      (8, 4),
      (64, 48),
      (1920, 1080),
      (100000, 1),
    ]) {
      final grid = sceneSampleGrid(size.$1, size.$2);
      final points = sceneSamplePoints(size.$1, size.$2);
      if (size.$1 <= 0 || size.$2 <= 0) {
        expect(grid.columns, 0);
        expect(grid.rows, 0);
        expect(points, isEmpty);
        continue;
      }
      expect(points.length, grid.columns * grid.rows);
      // The coordinates can be computed one by one, without building the list.
      for (var y = 0; y < grid.rows; y++) {
        for (var x = 0; x < grid.columns; x++) {
          final point = points[y * grid.columns + x];
          expect(point.x, sceneSampleCoordinate(x, grid.columns, size.$1));
          expect(point.y, sceneSampleCoordinate(y, grid.rows, size.$2));
        }
      }
    }
  });
  test('half-second smoothing and stale/lens/pause neutralization', () {
    var now = 0;
    final filter = SceneColorFilter(clock: () => now);
    const vivid = SceneColorReading(allowance: .65);
    expect(filter.allowance, 1);
    filter.add(vivid, now);
    for (var i = 0; i < 5; i++) {
      now += 100000;
      filter.add(vivid, now);
    }
    expect(filter.allowance, closeTo(1 - .35 * (1 - math.exp(-1)), 1e-12));
    now += 1000001;
    expect(filter.allowance, 1);
    filter.add(vivid, now);
    expect(filter.allowance, 1);
    filter.clear();
    expect(filter.isFresh, isFalse);
    filter.start();
    filter.stop();
    expect(filter.allowance, 1);
  });
}
