import 'dart:math';
import 'dart:ui' as ui;

import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

/// A renderer with no shader or platform calls, for browsing and loading races.
class FakeBrowsingRenderer implements EffectRenderer {
  FakeBrowsingRenderer(this.style);

  @override
  final StyleDefinition style;
  bool disposed = false;
  int paints = 0;
  final List<double> paintTimes = [];

  @override
  void paint(
    ui.Canvas canvas,
    ui.Size size, {
    required ui.Image image,
    required AmbientState ambient,
    required double time,
  }) {
    if (disposed) throw StateError('Renderer already disposed');
    paints++;
    paintTimes.add(time);
  }

  @override
  Future<ui.Image> renderToImage(
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    int maxSide = 2048,
  }) async => throw UnsupportedError('Browsing does not render stills');

  @override
  void dispose() => disposed = true;
}

/// Records the candidate count and returns the index requested by the test.
class FixedRandom implements Random {
  FixedRandom(this.index);

  int index;
  final List<int> bounds = [];

  @override
  int nextInt(int max) {
    bounds.add(max);
    if (index < 0 || index >= max) throw StateError('Invalid test index');
    return index;
  }

  @override
  bool nextBool() => throw UnsupportedError('Only nextInt is expected');

  @override
  double nextDouble() => throw UnsupportedError('Only nextInt is expected');
}
