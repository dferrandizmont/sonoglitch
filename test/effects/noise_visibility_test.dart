import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show pixels, testImage;

double _luma(Uint8List data, int offset) =>
    data[offset] * 0.2126 +
    data[offset + 1] * 0.7152 +
    data[offset + 2] * 0.0722;

({double corrupted, double dark}) _fractions(Uint8List clean, Uint8List noisy) {
  expect(noisy.length, clean.length);
  var corrupted = 0;
  var dark = 0;
  for (var offset = 0; offset < clean.length; offset += 4) {
    var maximum = 0;
    for (var channel = 0; channel < 3; channel++) {
      maximum = math.max(
        maximum,
        (clean[offset + channel] - noisy[offset + channel]).abs(),
      );
    }
    if (maximum > 96) corrupted++;
    if (_luma(clean, offset) > 64 && _luma(noisy, offset) < 16) dark++;
  }
  final count = clean.length ~/ 4;
  return (corrupted: corrupted / count, dark: dark / count);
}

// Sharp black/white edges exercise displaced shadows, while the grey ramp
// catches broad dark dropouts that a colourful texture can disguise.
Future<ui.Image> _greyImage({
  required bool checker,
  int width = 128,
  int height = 128,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = checker
          ? ((x ~/ 4 + y ~/ 4).isEven ? 0 : 255)
          : 65 + (190 * (x + y) / (width + height - 2)).round();
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()..color = ui.Color.fromARGB(255, value, value, value),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Neutral placeholders are covered by shader_contract_test, not response tests.
  for (final style in kStyles.where((style) => !style.isPlaceholder)) {
    test('${style.id} preserves the scene at maximum noise', () async {
      // These are real runtime shader renders. An unsupported host must fail
      // visibly, rather than pass a CPU approximation or silently skip checks.
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final sources = <String, ui.Image>{};
      addTearDown(() {
        for (final image in sources.values) {
          image.dispose();
        }
      });
      sources['grey ramp'] = await _greyImage(checker: false);
      sources['black/white checker'] = await _greyImage(checker: true);
      sources['small colour texture'] = await testImage();
      sources['landscape colour texture'] = await testImage(
        width: 160,
        height: 96,
      );
      sources['portrait colour texture'] = await testImage(
        width: 96,
        height: 160,
      );
      // A binary periodic mask can alias to the entire frame when its band
      // count matches the output height. Also exercise sub-band-sized output.
      for (final height in [3, 31, 41, 47]) {
        sources['short checker (height $height)'] = await _greyImage(
          checker: true,
          width: 32,
          height: height,
        );
      }

      Future<Uint8List> render(
        ui.Image source, {
        required double noise,
        required double time,
      }) async {
        final output = await renderer.renderToImage(
          source,
          ambient: AmbientState(noise: noise),
          time: time,
        );
        try {
          return await pixels(output);
        } finally {
          output.dispose();
        }
      }

      var worstCorrupted = 0.0;
      var worstDark = 0.0;
      for (final entry in sources.entries) {
        final clean = await render(entry.value, noise: 0, time: 0);
        // Sample consecutive pattern steps and distant phases, including the
        // original regression time and times large enough to stress hashing.
        for (final time in [
          0.0,
          0.041,
          0.083,
          0.125,
          0.167,
          0.209,
          0.251,
          0.5,
          1.25,
          4.0,
          17.3,
          123.456,
          999999.0,
        ]) {
          final noisy = await render(entry.value, noise: 1, time: time);
          final fractions = _fractions(clean, noisy);
          final context = '${entry.key}, time=$time';
          expect(
            fractions.corrupted,
            lessThanOrEqualTo(
              const {'phosphor', 'ripple', 'thermal'}.contains(style.id)
                  ? 0.20
                  : 0.25,
            ),
            reason:
                '$context: max RGB difference > 96 exceeds corruption budget',
          );
          expect(
            fractions.dark,
            lessThan(0.03),
            reason: '$context: introduced dark pixels must cover < 3%',
          );
          worstCorrupted = math.max(worstCorrupted, fractions.corrupted);
          worstDark = math.max(worstDark, fractions.dark);
        }
      }
      // ignore: avoid_print
      print(
        '${style.id}: max-noise worst corrupted='
        '${(worstCorrupted * 100).toStringAsFixed(3)}%; '
        'introduced dark=${(worstDark * 100).toStringAsFixed(3)}% '
        '(${sources.length} fixtures x 13 times)',
      );
    });
  }
}
