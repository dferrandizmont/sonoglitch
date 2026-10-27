import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

Future<ui.Image> testImage({int width = 32, int height = 24}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()
          ..color = ui.Color.fromARGB(
            255,
            (x * 37 + y * 3) % 256,
            (y * 41 + x * 5) % 256,
            (x * 19 + y * 23) % 256,
          ),
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

double difference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 != 3) sum += (a[i] - b[i]).abs();
  }
  return sum / (a.length * 0.75);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Neutral placeholders are covered by shader_contract_test, not response tests.
  for (final style in kStyles.where((style) => !style.isPlaceholder)) {
    test(
      '${style.id} loads, renders cleanly and responds to every control',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final source = await testImage();
        addTearDown(source.dispose);
        final original = await pixels(source);

        Future<Uint8List> render(
          AmbientState state, {
          double time = 1.25,
        }) async {
          final output = await renderer.renderToImage(
            source,
            ambient: state,
            time: time,
          );
          try {
            expect(output.width, source.width);
            expect(output.height, source.height);
            final data = await pixels(output);
            for (var i = 3; i < data.length; i += 4) {
              expect(data[i], 255, reason: 'Every output pixel must be opaque');
            }
            return data;
          } finally {
            output.dispose();
          }
        }

        final clean = await render(AmbientState.calm);
        expect(difference(original, clean), lessThanOrEqualTo(1));
        expect(
          difference(clean, await render(AmbientState.calm, time: 50)),
          lessThanOrEqualTo(1),
        );
        for (final state in [
          const AmbientState(noise: 1),
          const AmbientState(light: 0),
          const AmbientState(light: 1),
          const AmbientState(motion: 1),
          const AmbientState(motion: 1, motionDirX: 0, motionDirY: 1),
        ]) {
          expect(difference(clean, await render(state)), greaterThan(1));
        }
        final noisy = await render(const AmbientState(noise: 1));
        final leftNearZero = await render(
          const AmbientState(motion: 1, motionDirX: -0.00001),
        );
        final rightNearZero = await render(
          const AmbientState(motion: 1, motionDirX: 0.00001),
        );
        expect(difference(leftNearZero, rightNearZero), lessThan(1));
        expect(
          difference(
            noisy,
            await render(const AmbientState(noise: 1), time: 4),
          ),
          greaterThan(0.5),
        );
        expect(
          difference(
            noisy,
            await render(const AmbientState(noise: 1), time: 1.251),
          ),
          lessThan(2),
          reason: 'Nearby times must not produce hard flicker',
        );

        final small = await renderer.renderToImage(
          source,
          ambient: AmbientState.calm,
          time: 0,
          maxSide: 16,
        );
        expect((small.width, small.height), (16, 12));
        small.dispose();
        final cropRecorder = ui.PictureRecorder();
        renderer.paint(
          ui.Canvas(cropRecorder),
          const ui.Size(24, 24),
          image: source,
          ambient: AmbientState.calm,
          time: 0,
        );
        final cropPicture = cropRecorder.endRecording();
        final cropped = await cropPicture.toImage(24, 24);
        cropPicture.dispose();
        final croppedPixels = await pixels(cropped);
        cropped.dispose();
        for (var y = 0; y < 24; y++) {
          for (var x = 0; x < 24; x++) {
            for (var channel = 0; channel < 3; channel++) {
              expect(
                croppedPixels[(y * 24 + x) * 4 + channel],
                closeTo(original[(y * 32 + x + 4) * 4 + channel], 1),
                reason:
                    'Square output must keep the centered 24 source columns',
              );
            }
          }
        }
        await expectLater(
          renderer.renderToImage(
            source,
            ambient: AmbientState.calm,
            time: 0,
            maxSide: 0,
          ),
          throwsArgumentError,
        );
      },
    );
  }
}
