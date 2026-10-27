import 'dart:math' as math;
import 'dart:typed_data';

import '../ambient/ambient_config.dart';
import '../ambient/signature/scene_signature.dart';
import 'raw_frame.dart';

/// Converts a raw camera frame into a small upright RGBA image.
///
/// The conversion reads the camera planes directly, with nearest neighbour
/// subsampling, so the cost depends on the size of the *output* (about 360 px
/// on the long side) and not on the size of the sensor. That is what keeps
/// the live preview cheap on a mid range phone.
///
/// The same pass computes the mean brightness of the scene, which feeds the
/// light measurement, and the colourfulness of the scene, which feeds the
/// contextual lanes of the shot. Both are read from the pixels that are
/// written anyway, so no second pass over the frame is needed.
class FrameConverter {
  const FrameConverter({this.targetLongSide = 360});

  /// Longest side of the converted image, in pixels.
  final int targetLongSide;

  /// Converts [frame] into an upright RGBA buffer.
  ///
  /// [rotationDegrees] is the clockwise rotation applied to the frame so it
  /// appears upright, and [mirror] flips it horizontally, which is what the
  /// front camera needs.
  FrameConversion convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
  }) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    final sourceWidth = frame.width;
    final sourceHeight = frame.height;
    if (sourceWidth <= 0 || sourceHeight <= 0 || frame.planes.isEmpty) {
      return FrameConversion(
        pixels: Uint8List(0),
        width: 0,
        height: 0,
        meanLuma: 0,
      );
    }

    // Dimensions of the frame once rotated.
    final rotatedWidth = rotation == 90 || rotation == 270
        ? sourceHeight
        : sourceWidth;
    final rotatedHeight = rotation == 90 || rotation == 270
        ? sourceWidth
        : sourceHeight;
    final longest = math.max(rotatedWidth, rotatedHeight);
    final scale = math.min(1.0, targetLongSide / longest);
    final outWidth = math.max(1, (rotatedWidth * scale).round());
    final outHeight = math.max(1, (rotatedHeight * scale).round());

    // Buffers belong to this result until asynchronous image creation ends.
    // Only coordinate maps are precomputed; no output storage is shared.
    final pixels = Uint8List(outWidth * outHeight * 4);
    final xMap = Int32List(outWidth);
    final yMap = Int32List(outHeight);
    final swap = rotation == 90 || rotation == 270;
    for (var x = 0; x < outWidth; x++) {
      final ox = mirror ? outWidth - 1 - x : x;
      final rx = ox * rotatedWidth ~/ outWidth;
      xMap[x] = rotation == 90
          ? sourceHeight - 1 - rx
          : rotation == 180
          ? sourceWidth - 1 - rx
          : rx;
    }
    for (var y = 0; y < outHeight; y++) {
      final ry = y * rotatedHeight ~/ outHeight;
      yMap[y] = rotation == 180
          ? sourceHeight - 1 - ry
          : rotation == 270
          ? sourceWidth - 1 - ry
          : ry;
    }
    const columns = AmbientConfig.sceneColumns;
    const rows = AmbientConfig.sceneRows;
    final sceneLuma = List<double>.filled(columns * rows, 0);
    final counts = List<int>.filled(columns * rows, 0);
    final cellX = List<int>.generate(outWidth, (x) => x * columns ~/ outWidth);
    final rowLuma = mirror ? Float64List(outWidth) : null;
    // The colourfulness is accumulated over a sparse grid of at most 1024
    // points of the frame that is being written, so the cost stays tiny. The
    // coordinates of the grid are computed as the frame is written, so no
    // list of points, set or list of axes is built for every frame.
    final colorfulness = SceneColorfulness();
    final grid = sceneSampleGrid(outWidth, outHeight);
    final sampleColumns = grid.columns;
    final sampleRows = grid.rows;
    var nextRow = 0;
    var nextRowY = sampleRows > 0
        ? sceneSampleCoordinate(0, sampleRows, outHeight)
        : -1;
    var lumaSum = 0.0;
    for (var y = 0; y < outHeight; y++) {
      final cellRow = (y * rows ~/ outHeight) * columns;
      var sampled = false;
      while (nextRow < sampleRows && nextRowY <= y) {
        sampled = nextRowY == y;
        nextRow++;
        nextRowY = nextRow < sampleRows
            ? sceneSampleCoordinate(nextRow, sampleRows, outHeight)
            : -1;
      }
      var nextColumn = 0;
      var nextColumnX = sampleColumns > 0
          ? sceneSampleCoordinate(0, sampleColumns, outWidth)
          : -1;
      for (var x = 0; x < outWidth; x++) {
        final sourceX = swap ? yMap[y] : xMap[x];
        final sourceY = swap ? xMap[x] : yMap[y];
        final index = (y * outWidth + x) * 4;
        final luma = _writePixel(frame, sourceX, sourceY, pixels, index);
        if (sampled) {
          while (nextColumn < sampleColumns && nextColumnX <= x) {
            if (nextColumnX == x) {
              colorfulness.add(
                pixels[index],
                pixels[index + 1],
                pixels[index + 2],
              );
            }
            nextColumn++;
            nextColumnX = nextColumn < sampleColumns
                ? sceneSampleCoordinate(nextColumn, sampleColumns, outWidth)
                : -1;
          }
        }
        if (rowLuma == null) {
          lumaSum += luma;
        } else {
          rowLuma[x] = luma;
        }
        // Raster order, including mirroring, preserves the old grid's exact
        // floating-point addition order. Raw luma uses the old source order.
        final cell = cellRow + cellX[x];
        sceneLuma[cell] +=
            0.299 * pixels[index] +
            0.587 * pixels[index + 1] +
            0.114 * pixels[index + 2];
        counts[cell]++;
      }
      if (rowLuma != null) {
        for (var x = outWidth - 1; x >= 0; x--) {
          lumaSum += rowLuma[x];
        }
      }
    }
    for (var i = 0; i < sceneLuma.length; i++) {
      if (counts[i] > 0) sceneLuma[i] /= counts[i];
    }

    return FrameConversion(
      pixels: pixels,
      width: outWidth,
      height: outHeight,
      meanLuma: lumaSum / (outWidth * outHeight),
      sceneLuma: sceneLuma,
      colorfulness: colorfulness.finish(),
    );
  }

  double _writePixel(
    RawFrame frame,
    int x,
    int y,
    Uint8List pixels,
    int index,
  ) {
    pixels[index + 3] = 255;
    if (frame.format == FrameFormat.bgra8888) {
      final plane = frame.planes.first;
      final base = y * plane.bytesPerRow + x * 4;
      final b = _byteAt(plane.bytes, base);
      final g = _byteAt(plane.bytes, base + 1);
      final r = _byteAt(plane.bytes, base + 2);
      pixels[index] = r;
      pixels[index + 1] = g;
      pixels[index + 2] = b;
      return 0.299 * r + 0.587 * g + 0.114 * b;
    }
    if (frame.planes.length < 3) return 0;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];

    final luma = _byteAt(
      yPlane.bytes,
      y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel,
    );
    final chromaX = x >> 1;
    final chromaY = y >> 1;
    final u = _byteAt(
      uPlane.bytes,
      chromaY * uPlane.bytesPerRow + chromaX * uPlane.bytesPerPixel,
    );
    final v = _byteAt(
      vPlane.bytes,
      chromaY * vPlane.bytesPerRow + chromaX * vPlane.bytesPerPixel,
    );

    // BT.601 with the studio swing (limited range), the format cameras
    // deliver: the luma of the frame is mapped to 16..235.
    final yy = (luma - 16) * 1.164383;
    final r = yy + 1.596027 * (v - 128);
    final g = yy - 0.391762 * (u - 128) - 0.812968 * (v - 128);
    final b = yy + 2.017232 * (u - 128);
    pixels[index] = _clampByte(r);
    pixels[index + 1] = _clampByte(g);
    pixels[index + 2] = _clampByte(b);
    return luma.toDouble();
  }

  static int _byteAt(Uint8List bytes, int index) {
    if (index < 0 || index >= bytes.length) return 0;
    return bytes[index];
  }

  static int _clampByte(double value) {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return value.round();
  }
}
