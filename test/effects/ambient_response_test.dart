import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels;

const _side = 128;

// A symmetric grey ramp makes colour balance and direction measurable without
// bias from the fixture. The central checker patch supplies sharp edges.
Future<ui.Image> _fixture({bool directional = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < _side; y++) {
    for (var x = 0; x < _side; x++) {
      var value = 30 + (180 * (x + y) / (2 * (_side - 1))).round();
      if (directional) {
        // Independent stripe patches disambiguate blur orientation. Blurring a
        // checker alone reduces BOTH gradients, even for a one-axis kernel.
        final stripe = x < _side ~/ 2 ? x ~/ 4 : y ~/ 4;
        value = stripe.isEven ? 55 : 200;
      } else if (x >= 24 && x < 104 && y >= 24 && y < 104) {
        value = (x ~/ 4 + y ~/ 4).isEven ? 55 : 200;
      }
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()..color = ui.Color.fromARGB(255, value, value, value),
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_side, _side);
  } finally {
    picture.dispose();
  }
}

double _balance(Uint8List data) {
  var sum = 0.0;
  for (var i = 0; i < data.length; i += 4) {
    sum += data[i] - data[i + 2];
  }
  return sum / (data.length / 4);
}

double _luma(Uint8List data, int pixel) {
  final i = pixel * 4;
  return data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;
}

double _variance(Uint8List data) {
  var sum = 0.0;
  var squares = 0.0;
  final count = data.length ~/ 4;
  for (var i = 0; i < count; i++) {
    final value = _luma(data, i);
    sum += value;
    squares += value * value;
  }
  return squares / count - math.pow(sum / count, 2);
}

double _gradient(Uint8List data, {required bool horizontal}) {
  var sum = 0.0;
  var count = 0;
  // Measure the vertical stripes on the left for H, horizontal on the right
  // for V. Stay farther than the longest trail from edges and the patch seam.
  for (var y = 16; y < _side - 16; y++) {
    final startX = horizontal ? 16 : 80;
    for (var x = startX; x < startX + 32; x++) {
      final pixel = y * _side + x;
      final next = pixel + (horizontal ? 1 : _side);
      sum += (_luma(data, pixel) - _luma(data, next)).abs();
      count++;
    }
  }
  return sum / count;
}

String _numbers(Iterable<double> values) =>
    values.map((value) => value.toStringAsFixed(3)).join(', ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every selectable style must respond; placeholders only have contract tests.
  for (final style in kStyles) {
    test('${style.id} has distinct, measurable ambient responses', () async {
      // Shader loading/rendering failures intentionally fail this test. A host
      // without runtime effects must report that limitation, never silently skip.
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final source = await _fixture();
      addTearDown(source.dispose);
      final directionSource = await _fixture(directional: true);
      addTearDown(directionSource.dispose);
      final original = await pixels(source);

      Future<Uint8List> render(
        AmbientState ambient, {
        double time = 1.25,
        bool directional = false,
      }) async {
        final image = await renderer.renderToImage(
          directional ? directionSource : source,
          ambient: ambient,
          time: time,
        );
        try {
          final floats = (await image.toByteData(
            format: ui.ImageByteFormat.rawExtendedRgba128,
          ))!;
          final values = floats.buffer.asFloat32List(
            floats.offsetInBytes,
            floats.lengthInBytes ~/ Float32List.bytesPerElement,
          );
          for (var i = 0; i < values.length; i++) {
            expect(values[i].isFinite, isTrue, reason: 'No NaN or infinity');
            if (i % 4 == 3) expect(values[i], 1.0);
          }
          return await pixels(image);
        } finally {
          image.dispose();
        }
      }

      final clean = await render(AmbientState.calm);
      final neutralError = difference(original, clean);
      expect(neutralError, lessThanOrEqualTo(1.0));
      final dark = await render(const AmbientState(light: 0.1));
      final bright = await render(const AmbientState(light: 0.9));
      final darkBalance = _balance(dark);
      final brightBalance = _balance(bright);
      final darkVariance = _variance(dark);
      final brightVariance = _variance(bright);
      final legacy = const {'static', 'tape', 'prism'}.contains(style.id);
      if (legacy) {
        // Preserve the original grade regression for the original shaders.
        expect(darkBalance, lessThan(-8));
        expect(brightBalance, greaterThan(8));
        expect(brightBalance - darkBalance, greaterThan(25));
        expect(brightVariance, lessThan(darkVariance * 0.85));
      } else {
        // New looks have different light structures, not a shared warm wash.
        expect((brightBalance - darkBalance).abs(), greaterThan(8));
        expect(
          (brightVariance - darkVariance).abs(),
          greaterThan(darkVariance * 0.05),
        );
      }

      final noiseErrors = <double>[];
      for (final noise in [0.25, 0.5, 1.0]) {
        noiseErrors.add(
          difference(clean, await render(AmbientState(noise: noise))),
        );
      }
      expect(noiseErrors.first, greaterThan(0.75));
      expect(noiseErrors[1], greaterThanOrEqualTo(noiseErrors[0] * 1.30));
      expect(noiseErrors[2], greaterThanOrEqualTo(noiseErrors[1] * 1.30));

      final directionClean = await render(AmbientState.calm, directional: true);
      final horizontal = await render(
        const AmbientState(motion: 1),
        directional: true,
      );
      final vertical = await render(
        const AmbientState(motion: 1, motionDirX: 0, motionDirY: 1),
        directional: true,
      );
      final cleanH = _gradient(directionClean, horizontal: true);
      final cleanV = _gradient(directionClean, horizontal: false);
      final horizontalH = _gradient(horizontal, horizontal: true);
      final horizontalV = _gradient(horizontal, horizontal: false);
      final verticalH = _gradient(vertical, horizontal: true);
      final verticalV = _gradient(vertical, horizontal: false);
      expect(horizontalH, lessThan(cleanH * 0.80));
      expect(verticalV, lessThan(cleanV * 0.80));
      expect(horizontalH, lessThan(verticalH * 0.85));
      expect(verticalV, lessThan(horizontalV * 0.85));
      expect(
        difference(
          horizontal,
          await render(
            const AmbientState(motion: 1, motionDirX: -1),
            directional: true,
          ),
        ),
        greaterThan(2),
        reason: 'The trail must reverse when the direction reverses',
      );

      // A control reacts immediately. Legacy patterns step; new looks animate
      // continuously (the dedicated new-style tests probe tiny uniform changes).
      final loud = await render(const AmbientState(noise: 1));
      expect(difference(loud, await render(const AmbientState(noise: 1))), 0);
      expect(difference(clean, loud), greaterThan(noiseErrors[1] * 1.30));
      expect(
        difference(
          loud,
          await render(const AmbientState(noise: 1), time: 1.251),
        ),
        legacy ? 0 : lessThan(2),
      );

      // Include the extremes and simultaneous controls in finite/opaque checks.
      for (final light in [0.0, 0.25, 0.75, 1.0]) {
        await render(AmbientState(light: light));
      }
      await render(const AmbientState(noise: 1, light: 0, motion: 1));
      await render(const AmbientState(noise: 1, light: 1, motion: 1));

      // ignore: avoid_print
      print(
        '${style.id}: neutral MAD=${neutralError.toStringAsFixed(3)}; '
        'light R-B dark/bright=[${_numbers([darkBalance, brightBalance])}]; '
        'luma variance dark/bright=[${_numbers([darkVariance, brightVariance])}]; '
        'noise MAD .25/.5/1=[${_numbers(noiseErrors)}]; '
        'gradient clean H/V=[${_numbers([cleanH, cleanV])}], '
        'motion X H/V=[${_numbers([horizontalH, horizontalV])}], '
        'motion Y H/V=[${_numbers([verticalH, verticalV])}]',
      );
    });
  }
}
