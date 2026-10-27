import 'dart:math' as math;
import 'dart:typed_data';

import 'ambient_config.dart';

/// Frame-only motion in the upright, mirrored preview's coordinates. Buffers
/// contain just a coarse luma grid and are never written anywhere.
class SceneMotion {
  List<double>? _previous;
  (int, int)? _size;
  double difference = 0;
  double dx = 0;
  double dy = 0;

  void reset() {
    _previous = null;
    _size = null;
    difference = dx = dy = 0;
  }

  void addRgba(Uint8List pixels, int width, int height) {
    if (width <= 0 || height <= 0 || pixels.length < width * height * 4) return;
    const columns = AmbientConfig.sceneColumns;
    const rows = AmbientConfig.sceneRows;
    if (_size != (width, height)) reset();
    _size = (width, height);
    final luma = List<double>.filled(columns * rows, 0);
    final counts = List<int>.filled(columns * rows, 0);
    // Average every cell instead of sampling one noisy sensor pixel.
    for (var y = 0; y < height; y++) {
      final row = y * rows ~/ height;
      for (var x = 0; x < width; x++) {
        final cell = row * columns + x * columns ~/ width;
        final i = (y * width + x) * 4;
        luma[cell] +=
            0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
        counts[cell]++;
      }
    }
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final cell = y * columns + x;
        if (counts[cell] > 0) luma[cell] /= counts[cell];
      }
    }
    addLumaGrid(luma, width, height);
  }

  /// Accepts the converter's grid, with the same size/reset semantics as RGBA.
  void addLumaGrid(List<double> luma, int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (_size != (width, height)) reset();
    _size = (width, height);
    addGrid(
      luma,
      cellWidth: width / AmbientConfig.sceneColumns,
      cellHeight: height / AmbientConfig.sceneRows,
    );
  }

  /// Mean absolute temporal difference after subtracting global exposure change.
  /// A textureless linear ramp translated without edges is indistinguishable
  /// from exposure change; direction needs spatial structure to be observable.
  void addGrid(
    List<double> luma, {
    double cellWidth = 1,
    double cellHeight = 1,
  }) {
    const w = AmbientConfig.sceneColumns;
    const h = AmbientConfig.sceneRows;
    if (luma.length != w * h || luma.any((v) => !v.isFinite)) return;
    final previous = _previous;
    _previous = List<double>.of(luma);
    difference = 0;
    if (previous == null) return;
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final currentMean = mean(luma);
    final previousMean = mean(previous);
    // Neither exposure normalization nor block matching is reliable near black.
    if (math.min(currentMean, previousMean) < 18) return;
    double contrast(List<double> values, double mean) => math.sqrt(
      values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
          values.length,
    );
    final currentContrast = contrast(luma, currentMean);
    final previousContrast = contrast(previous, previousMean);
    if (math.min(currentContrast, previousContrast) < 4) return;
    // Match both gain and offset. A stationary auto-exposure change then has
    // zero residual even on a scene containing dark and light regions.
    final gain = currentContrast / previousContrast;
    final offset = currentMean - gain * previousMean;
    var sum = 0.0;
    for (var i = 0; i < luma.length; i++) {
      sum += (luma[i] - gain * previous[i] - offset).abs();
    }
    final residual = sum / luma.length;
    // Retain the last observable direction during the magnitude's release.
    if (residual <= AmbientConfig.sceneFloor) return;

    // Compare small blocks across a sparse interior grid. All candidates use
    // the same pixels, so edge overlap cannot favour larger displacements.
    const radius = AmbientConfig.sceneSearchRadius;
    const block = AmbientConfig.sceneBlockRadius;
    const margin = radius + block;
    double cost(int ox, int oy) {
      var total = 0.0;
      var count = 0;
      for (
        var y = margin;
        y < h - margin;
        y += AmbientConfig.sceneMatchStride
      ) {
        for (
          var x = margin;
          x < w - margin;
          x += AmbientConfig.sceneMatchStride
        ) {
          for (var by = -block; by <= block; by++) {
            for (var bx = -block; bx <= block; bx++) {
              total +=
                  (luma[(y + by) * w + x + bx] -
                          gain * previous[(y + by - oy) * w + x + bx - ox] -
                          offset)
                      .abs();
              count++;
            }
          }
        }
      }
      return total / count;
    }

    final stationary = cost(0, 0);
    var best = stationary;
    var bestX = 0;
    var bestY = 0;
    for (var y = -radius; y <= radius; y++) {
      for (var x = -radius; x <= radius; x++) {
        final candidate = cost(x, y);
        if (candidate < best - 1e-6 ||
            ((candidate - best).abs() <= 1e-6 &&
                x * x + y * y < bestX * bestX + bestY * bestY)) {
          best = candidate;
          bestX = x;
          bestY = y;
        }
      }
    }
    // Random residuals can occasionally favour a displacement. Require a
    // substantial, coherent improvement, not just a numerically better match.
    if (stationary - best < math.max(2, stationary * 0.35)) return;
    difference = residual;
    final imageX = bestX * cellWidth;
    final imageY = bestY * cellHeight;
    final length = math.sqrt(imageX * imageX + imageY * imageY);
    if (length > 0) {
      dx = imageX / length;
      // Sensor directions use y towards the top of the portrait preview.
      dy = -imageY / length;
    }
  }

  double get level =>
      ((difference - AmbientConfig.sceneFloor) /
              (AmbientConfig.sceneCeiling - AmbientConfig.sceneFloor))
          .clamp(0.0, 1.0);
}
