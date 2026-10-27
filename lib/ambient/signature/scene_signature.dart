import 'dart:math' as math;

import '../clock.dart';

/// In-memory opponent-colour statistics for a single converted frame.
class SceneColorReading {
  const SceneColorReading({
    this.colorfulness = 0,
    this.allowance = 1,
    this.meanSaturation = 0,
  });

  final double colorfulness;
  final double allowance;
  final double meanSaturation;
}

/// Constant-space accumulator. RGB inputs are 8-bit code values.
class SceneColorfulness {
  int _count = 0;
  double _rg = 0, _yb = 0, _rgM2 = 0, _ybM2 = 0, _saturation = 0;

  // Synthetic calibration in RGB8 units: grey C=0; muted primary mixtures
  // (136,120,120) and permutations C=17.28; RGB primaries C=275.43;
  // photo-like brown/sky/foliage/skin fixture C=68.41. Thus lo=20 leaves
  // muted scenes untouched, hi=80 fully limits vivid scenes, with a smooth
  // transition for ordinary photo palettes. This is aesthetic, not colorimetry.
  static const low = 20.0;
  static const high = 80.0;

  /// Adds one sample; caller uses [sceneSamplePoints], not every frame pixel.
  void add(int r, int g, int b) {
    r = r.clamp(0, 255).toInt();
    g = g.clamp(0, 255).toInt();
    b = b.clamp(0, 255).toInt();
    final rg = (r - g).toDouble(), yb = (r + g) / 2 - b;
    _count++;
    final dr = rg - _rg, dy = yb - _yb;
    _rg += dr / _count;
    _yb += dy / _count;
    _rgM2 += dr * (rg - _rg);
    _ybM2 += dy * (yb - _yb);
    final hi = math.max(r, math.max(g, b));
    final lo = math.min(r, math.min(g, b));
    _saturation += hi == 0 ? 0 : (hi - lo) / hi;
  }

  /// Finishes without mutating the accumulator; an empty frame is neutral.
  SceneColorReading finish() {
    if (_count == 0) return const SceneColorReading();
    final c =
        math.sqrt(math.max(0, (_rgM2 + _ybM2) / _count)) +
        .3 * math.sqrt(_rg * _rg + _yb * _yb);
    final t = ((c - low) / (high - low)).clamp(0.0, 1.0);
    return SceneColorReading(
      colorfulness: c,
      allowance: 1 - .35 * t * t * (3 - 2 * t),
      meanSaturation: _saturation / _count,
    );
  }
}

/// The size of the sampling grid of [sceneSamplePoints].
///
/// The grid is uniform, so a consumer that only needs the coordinates can
/// compute them arithmetically instead of building a list of points.
({int columns, int rows}) sceneSampleGrid(int width, int height) {
  if (width <= 0 || height <= 0) return (columns: 0, rows: 0);
  final nx = math.min(
    math.min(width, 1024),
    math.max(1, math.sqrt(1024 * width / height).floor()),
  );
  final ny = math.min(height, 1024 ~/ nx);
  return (columns: nx, rows: ny);
}

/// The coordinate of the sample [index] of a grid of [count] over [extent].
int sceneSampleCoordinate(int index, int count, int extent) =>
    ((index + .5) * extent / count).floor();

/// Uniform cell-centre grid, with at most 1024 points inside the frame.
/// Supports narrow frames; empty/invalid dimensions return no points.
List<({int x, int y})> sceneSamplePoints(int width, int height) {
  final grid = sceneSampleGrid(width, height);
  if (grid.columns == 0) return const [];
  return [
    for (var y = 0; y < grid.rows; y++)
      for (var x = 0; x < grid.columns; x++)
        (
          x: sceneSampleCoordinate(x, grid.columns, width),
          y: sceneSampleCoordinate(y, grid.rows, height),
        ),
  ];
}

/// Half-second low-pass. Camera changes must call [clear] before new frames.
class SceneColorFilter {
  SceneColorFilter({this.clock = stopwatchClock});

  final Clock clock;
  int? _last;
  double _value = 1;

  bool get isFresh {
    final now = clock();
    return _last != null && now >= _last! && now - _last! <= 1000000;
  }

  double get allowance => isFresh ? _value : 1;

  /// Feed one completed frame, timestamped by the shared monotonic clock.
  void add(SceneColorReading reading, int timeMicros) {
    if (_last != null && timeMicros <= _last!) return;
    if (!reading.allowance.isFinite) {
      clear();
      return;
    }
    final dt = _last == null || timeMicros - _last! > 1000000
        ? 0
        : timeMicros - _last!;
    if (dt == 0) _value = 1;
    _value +=
        (1 - math.exp(-dt / 500000)) *
        (reading.allowance.clamp(.65, 1) - _value);
    _last = timeMicros;
  }

  /// Forgets the previous camera immediately; no subscriptions or timers.
  void clear() {
    _last = null;
    _value = 1;
  }

  void start() => clear();
  void stop() => clear();
}
