import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_config.dart';
import 'package:sonoglitch/ambient/scene_motion.dart';
import 'package:sonoglitch/camera/frame_converter.dart';
import 'package:sonoglitch/camera/raw_frame.dart';

import '../support/reference_frame_converter.dart';

List<double> referenceGrid(FrameConversion frame) {
  const columns = AmbientConfig.sceneColumns;
  const rows = AmbientConfig.sceneRows;
  final luma = List<double>.filled(columns * rows, 0);
  final counts = List<int>.filled(columns * rows, 0);
  for (var y = 0; y < frame.height; y++) {
    final row = y * rows ~/ frame.height;
    for (var x = 0; x < frame.width; x++) {
      final cell = row * columns + x * columns ~/ frame.width;
      final i = (y * frame.width + x) * 4;
      luma[cell] +=
          0.299 * frame.pixels[i] +
          0.587 * frame.pixels[i + 1] +
          0.114 * frame.pixels[i + 2];
      counts[cell]++;
    }
  }
  for (var i = 0; i < luma.length; i++) {
    if (counts[i] > 0) luma[i] /= counts[i];
  }
  return luma;
}

void main() {
  test('micro benchmark: random padded frames exactly match the baseline', () {
    final random = Random(6194089);
    RawFrame randomFrame(FrameFormat format, int width, int height) {
      RawPlane plane(int w, int h, int stride, int padding) {
        final row = w * stride + padding;
        return RawPlane(
          bytes: Uint8List.fromList(
            List.generate(row * h, (_) => random.nextInt(256)),
          ),
          bytesPerRow: row,
          bytesPerPixel: stride,
        );
      }

      return RawFrame(
        width: width,
        height: height,
        format: format,
        planes: format == FrameFormat.bgra8888
            ? [plane(width, height, 4, 12)]
            : [
                plane(width, height, 1, 7),
                plane((width + 1) ~/ 2, (height + 1) ~/ 2, 2, 9),
                plane((width + 1) ~/ 2, (height + 1) ~/ 2, 2, 5),
              ],
      );
    }

    final frames = [
      for (final format in FrameFormat.values)
        for (final size in [(7, 5), (64, 96), (320, 480)])
          randomFrame(format, size.$1, size.$2),
    ];
    var baselineMicros = 0;
    var optimizedMicros = 0;
    var comparisons = 0;
    for (final side in [36, 360]) {
      final converter = FrameConverter(targetLongSide: side);
      final reference = ReferenceFrameConverter(targetLongSide: side);
      for (final rotation in [0, 90, 180, 270]) {
        for (final mirror in [false, true]) {
          final oldMotion = SceneMotion();
          final newMotion = SceneMotion();
          for (final frame in frames) {
            final watch = Stopwatch()..start();
            final expected = reference.convert(
              frame,
              rotationDegrees: rotation,
              mirror: mirror,
            );
            baselineMicros += watch.elapsedMicroseconds;
            watch.reset();
            final actual = converter.convert(
              frame,
              rotationDegrees: rotation,
              mirror: mirror,
            );
            optimizedMicros += watch.elapsedMicroseconds;
            watch.stop();
            expect(
              (actual.width, actual.height),
              (expected.width, expected.height),
            );
            expect(actual.pixels, expected.pixels);
            expect(actual.meanLuma, expected.meanLuma);
            expect(actual.sceneLuma, referenceGrid(expected));
            oldMotion.addRgba(expected.pixels, expected.width, expected.height);
            newMotion.addLumaGrid(
              actual.sceneLuma!,
              actual.width,
              actual.height,
            );
            expect(
              (
                newMotion.difference,
                newMotion.dx,
                newMotion.dy,
                newMotion.level,
              ),
              (
                oldMotion.difference,
                oldMotion.dx,
                oldMotion.dy,
                oldMotion.level,
              ),
            );
            comparisons++;
          }
        }
      }
    }
    // Observational only: debug/JIT timing is not a device performance claim.
    // ignore: avoid_print
    print(
      'Parity micro benchmark: $comparisons frames; baseline=$baselineMicros us; conversion+grid=$optimizedMicros us',
    );
  });

  test('conversion output storage is never reused by later frames', () {
    const converter = FrameConverter();
    final pixels = Uint8List.fromList([1, 2, 3, 255]);
    RawFrame frame() => RawFrame(
      width: 1,
      height: 1,
      format: FrameFormat.bgra8888,
      planes: [RawPlane(bytes: pixels, bytesPerRow: 4)],
    );
    final first = converter.convert(frame(), rotationDegrees: 0, mirror: false);
    final copy = Uint8List.fromList(first.pixels);
    pixels.fillRange(0, 3, 200);
    final second = converter.convert(
      frame(),
      rotationDegrees: 0,
      mirror: false,
    );
    expect(identical(first.pixels, second.pixels), isFalse);
    expect(first.pixels, copy);
  });
}
