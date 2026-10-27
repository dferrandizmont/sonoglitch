import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/scene_signature.dart';
import 'package:sonoglitch/camera/frame_converter.dart';
import 'package:sonoglitch/camera/raw_frame.dart';

/// The grey value the converter produces for a luma of [y].
int expectedGrey(int y) => ((y - 16) * 1.164383).round().clamp(0, 255);

RawFrame yuvFrame(List<int> luma, {required int width, required int height}) {
  final chroma = Uint8List((width ~/ 2) * (height ~/ 2));
  for (var i = 0; i < chroma.length; i++) {
    chroma[i] = 128;
  }
  return RawFrame(
    width: width,
    height: height,
    format: FrameFormat.yuv420,
    planes: [
      RawPlane(bytes: Uint8List.fromList(luma), bytesPerRow: width),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
    ],
  );
}

void main() {
  group('FrameConverter', () {
    const converter = FrameConverter(targetLongSide: 4);

    test('converts a YUV frame into RGBA', () {
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );

      expect(conversion.width, 4);
      expect(conversion.height, 2);
      expect(conversion.pixels.length, 4 * 2 * 4);
      // Red, green and blue of the first pixel.
      expect(conversion.pixels[0], expectedGrey(50));
      expect(conversion.pixels[1], expectedGrey(50));
      expect(conversion.pixels[2], expectedGrey(50));
      expect(conversion.pixels[3], 255);
    });

    test('computes the mean brightness of the frame', () {
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      expect(conversion.meanLuma, closeTo(53.5, 0.001));
    });

    test('turns the frame a quarter turn', () {
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 90,
        mirror: false,
      );

      // The frame becomes portrait.
      expect(conversion.width, 2);
      expect(conversion.height, 4);
      // The first pixel of the turned frame is the bottom left of the source.
      expect(conversion.pixels[0], expectedGrey(54));
      // The second one is the top left.
      expect(conversion.pixels[4], expectedGrey(50));
    });

    test('turns the frame half a turn', () {
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 180,
        mirror: false,
      );

      expect(conversion.width, 4);
      expect(conversion.height, 2);
      expect(conversion.pixels[0], expectedGrey(57));
    });

    test('mirrors the frame horizontally', () {
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: true,
      );

      // The first row of the source is [50, 51, 52, 53] and the frame is
      // mirrored, so it becomes [53, 52, 51, 50].
      expect(conversion.pixels[0], expectedGrey(53));
      expect(conversion.pixels[4], expectedGrey(52));
      expect(conversion.pixels[12], expectedGrey(50));
    });

    test('subsamples to the wanted size', () {
      const small = FrameConverter(targetLongSide: 2);
      final frame = yuvFrame(
        List<int>.generate(64, (index) => 50 + index),
        width: 8,
        height: 8,
      );
      final conversion = small.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      expect(conversion.width, 2);
      expect(conversion.height, 2);
    });

    test('does not enlarge a small frame', () {
      const small = FrameConverter(targetLongSide: 64);
      final frame = yuvFrame(
        [50, 51, 52, 53, 54, 55, 56, 57],
        width: 4,
        height: 2,
      );
      final conversion = small.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      expect(conversion.width, 4);
      expect(conversion.height, 2);
    });

    test('reads a BGRA frame', () {
      final frame = RawFrame(
        width: 2,
        height: 1,
        format: FrameFormat.bgra8888,
        planes: [
          RawPlane(
            bytes: Uint8List.fromList([30, 20, 10, 255, 60, 50, 40, 255]),
            bytesPerRow: 8,
          ),
        ],
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );

      expect(conversion.width, 2);
      expect(conversion.height, 1);
      // Red, green and blue are swapped in the source.
      expect(conversion.pixels[0], 10);
      expect(conversion.pixels[1], 20);
      expect(conversion.pixels[2], 30);
      expect(conversion.pixels[4], 40);
      expect(conversion.meanLuma, closeTo((18.15 + 48.15) / 2, 0.01));
    });

    test('an empty frame does not break the conversion', () {
      final frame = RawFrame(
        width: 0,
        height: 0,
        format: FrameFormat.yuv420,
        planes: const [],
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      expect(conversion.width, 0);
      expect(conversion.pixels, isEmpty);
      // An empty frame has no colour to describe.
      expect(conversion.colorfulness, isNull);
    });

    test('measures the colourfulness of the frame in the same pass', () {
      final frame = RawFrame(
        width: 2,
        height: 1,
        format: FrameFormat.bgra8888,
        planes: [
          RawPlane(
            bytes: Uint8List.fromList([30, 20, 10, 255, 60, 50, 40, 255]),
            bytesPerRow: 8,
          ),
        ],
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      final reading = conversion.colorfulness!;
      // The producer sees exactly the pixels the converter wrote.
      final accumulator = SceneColorfulness();
      for (final point in sceneSamplePoints(
        conversion.width,
        conversion.height,
      )) {
        final index = (point.y * conversion.width + point.x) * 4;
        accumulator.add(
          conversion.pixels[index],
          conversion.pixels[index + 1],
          conversion.pixels[index + 2],
        );
      }
      final expected = accumulator.finish();
      expect(reading.colorfulness, closeTo(expected.colorfulness, 1e-12));
      expect(reading.allowance, closeTo(expected.allowance, 1e-12));
      expect(reading.meanSaturation, closeTo(expected.meanSaturation, 1e-12));
      // The pixels and the brightness of the frame are untouched.
      expect(conversion.pixels[0], 10);
      expect(conversion.pixels[1], 20);
      expect(conversion.pixels[2], 30);
      expect(conversion.meanLuma, closeTo((18.15 + 48.15) / 2, 0.01));
    });

    test('the colourfulness follows the colours of the frame', () {
      final converter = FrameConverter(targetLongSide: 8);
      RawFrame bgra(List<int> pixels) => RawFrame(
        width: pixels.length ~/ 4,
        height: 1,
        format: FrameFormat.bgra8888,
        planes: [
          RawPlane(
            bytes: Uint8List.fromList(pixels),
            bytesPerRow: pixels.length,
          ),
        ],
      );

      final grey = converter.convert(
        bgra([128, 128, 128, 255, 128, 128, 128, 255]),
        rotationDegrees: 0,
        mirror: false,
      );
      expect(grey.colorfulness!.colorfulness, 0);
      expect(grey.colorfulness!.allowance, 1);

      final vivid = converter.convert(
        bgra([0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255]),
        rotationDegrees: 0,
        mirror: false,
      );
      expect(vivid.colorfulness!.colorfulness, greaterThan(0));
      expect(vivid.colorfulness!.allowance, lessThan(1));
    });

    test('the sampled points of a big frame are the ones of the grid', () {
      final converter = FrameConverter(targetLongSide: 64);
      const width = 40;
      const height = 30;
      final pixels = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        pixels[i * 4] = (i * 37) % 256;
        pixels[i * 4 + 1] = (i * 61) % 256;
        pixels[i * 4 + 2] = (i * 97) % 256;
        pixels[i * 4 + 3] = 255;
      }
      final frame = RawFrame(
        width: width,
        height: height,
        format: FrameFormat.bgra8888,
        planes: [RawPlane(bytes: pixels, bytesPerRow: width * 4)],
      );
      final conversion = converter.convert(
        frame,
        rotationDegrees: 0,
        mirror: false,
      );
      // The producer sees exactly the pixels of the grid of the frame.
      final accumulator = SceneColorfulness();
      for (final point in sceneSamplePoints(
        conversion.width,
        conversion.height,
      )) {
        final index = (point.y * conversion.width + point.x) * 4;
        accumulator.add(
          conversion.pixels[index],
          conversion.pixels[index + 1],
          conversion.pixels[index + 2],
        );
      }
      final expected = accumulator.finish();
      final reading = conversion.colorfulness!;
      expect(reading.colorfulness, closeTo(expected.colorfulness, 1e-12));
      expect(reading.allowance, closeTo(expected.allowance, 1e-12));
      expect(reading.meanSaturation, closeTo(expected.meanSaturation, 1e-12));
    });
  });
}
