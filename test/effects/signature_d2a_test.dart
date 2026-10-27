import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;
import 'new_styles_test.dart' show sig2bScene;

const _ids = {'static', 'tape', 'prism'};
// Frozen before D2A edits; the delivery-1 shared helper is inlined verbatim.
const _oracleHashes = {
  'static': 'c7de3d069f41c8005ff4edef0c37abb7e3e52d6ba995f59757e4871a70b1a304',
  'tape': 'c2f1782e8ed2c547e101e9601a85c9109ebfae475f87b050778743082207bdfb',
  'prism': '39983049176d29c68bf81979770426a66b62a42536297f21b5227a566f053224',
};
const _micro = SignatureState(x: 0.125, y: 0.25, z: 0.5, w: 0.75);
final _axisCos = math.cos(math.pi / 15);
final _axisSin = math.sin(math.pi / 15);

final _signals = <String, SignatureState>{
  'warmth -1': const SignatureState(warmth: -1),
  'warmth +1': const SignatureState(warmth: 1),
  'hue -1': const SignatureState(hue: -1),
  'hue +1': const SignatureState(hue: 1),
  'chroma .65': const SignatureState(chromaAllowance: 0.65),
  'tilt -1': const SignatureState(tilt: -1),
  'tilt +1': const SignatureState(tilt: 1),
  'axis -12deg': SignatureState(axisX: _axisCos, axisY: -_axisSin),
  'axis +12deg': SignatureState(axisX: _axisCos, axisY: _axisSin),
  'pulse -1': const SignatureState(pulse: -1),
  'pulse +1': const SignatureState(pulse: 1),
};

// Cover both signs and reinforcing/opposing warmth/hue combinations.
final _extremes = [
  for (final signs in [(1.0, 1.0), (-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0)])
    _micro.withMood(
      warmth: signs.$1,
      hue: signs.$2,
      chromaAllowance: 0.65,
      tilt: signs.$1,
      axisX: _axisCos,
      axisY: _axisSin * signs.$2,
      pulse: signs.$2,
    ),
];

AmbientState _state(
  SignatureState signature, {
  double noise = 0.85,
  double light = 0.25,
  double motion = 0.4,
  double seed = 0.37,
}) => AmbientState(
  noise: noise,
  light: light,
  motion: motion,
  motionDirX: 0.6,
  motionDirY: 0.8,
  bass: 1,
  mid: 1,
  treble: 1,
  seed: seed,
  signature: signature,
);

Future<Uint8List> _render(
  EffectRenderer renderer,
  ui.Image source,
  AmbientState state,
) async {
  final image = await renderer.renderToImage(
    source,
    ambient: state,
    time: 1.25,
  );
  try {
    final raw = (await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    final floats = raw.buffer.asFloat32List(
      raw.offsetInBytes,
      raw.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    expect(floats.every((v) => v.isFinite && v >= 0 && v <= 1), isTrue);
    expect([
      for (var i = 3; i < floats.length; i += 4) floats[i],
    ], everyElement(1));
    return await pixels(image);
  } finally {
    image.dispose();
  }
}

// Maximum per-pixel L-infinity distance: the largest RGB channel delta.
int _maxPixelChange(Uint8List a, Uint8List b) {
  var maximum = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 != 3) maximum = math.max(maximum, (a[i] - b[i]).abs());
  }
  return maximum;
}

// Area averaging avoids aliasing the existing high-frequency RGB fixture.
List<double> _thumbnail(Uint8List data, int width, int height) {
  final scale = math.min(1.0, 64 / math.max(width, height));
  final w = math.max(1, (width * scale).round());
  final h = math.max(1, (height * scale).round());
  final sums = List<double>.filled(w * h, 0);
  final counts = List<int>.filled(w * h, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final cell = (y * h ~/ height) * w + x * w ~/ width;
      sums[cell] +=
          data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;
      counts[cell]++;
    }
  }
  return [for (var i = 0; i < sums.length; i++) sums[i] / counts[i]];
}

double _correlation(List<double> a, List<double> b) {
  final meanA = a.reduce((x, y) => x + y) / a.length;
  final meanB = b.reduce((x, y) => x + y) / b.length;
  var covariance = 0.0;
  var varianceA = 0.0;
  var varianceB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i] - meanA;
    final y = b[i] - meanB;
    covariance += x * y;
    varianceA += x * x;
    varianceB += y * y;
  }
  expect(varianceA * varianceB, greaterThan(0));
  return covariance / math.sqrt(varianceA * varianceB);
}

// Apply only the documented colour terms to the frozen, zero-band D1 RGB.
// Quantized inputs allow two RGB8 codes of rounding tolerance in GPU checks.
Uint8List _colorOnly(
  String style,
  Uint8List baseline,
  Uint8List original,
  int width,
  int height,
  double light,
  SignatureState signal,
) {
  final result = Uint8List.fromList(baseline);
  for (var i = 0; i < baseline.length; i += 4) {
    final color = [for (var c = 0; c < 3; c++) baseline[i + c] / 255];
    double luma(List<double> rgb) =>
        rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
    final y = ((i ~/ 4 ~/ width) + 0.5) / height;
    final mask = switch (style) {
      'static' => 1 - luma(color),
      'tape' => math.max(1 - luma(color), 1 - y),
      _ => math.max(luma(color), 1 - y),
    };
    const temperature = [0.04, 0.0, -0.04];
    const hue = [-0.02, 0.01, 0.02];
    for (var c = 0; c < 3; c++) {
      final gain = (temperature[c] * signal.warmth + hue[c] * signal.hue * mask)
          .clamp(-0.04, 0.04);
      color[c] *= 1 + gain * (2 * light - 1).abs();
    }
    if (signal.chromaAllowance != 1) {
      final delta = [
        for (var c = 0; c < 3; c++)
          color[c].clamp(0.0, 1.0) - original[i + c] / 255,
      ];
      final neutral = luma(delta);
      for (var c = 0; c < 3; c++) {
        color[c] =
            original[i + c] / 255 +
            neutral +
            (delta[c] - neutral) * signal.chromaAllowance;
      }
    }
    for (var c = 0; c < 3; c++) {
      result[i + c] = (color[c].clamp(0.0, 1.0) * 255).round();
    }
  }
  return result;
}

// Round each transfer operation to float32, as in the shader. This checks the
// conservative scalar envelope, not image correlation or GPU frame time.
void _expectConserved(double broad, double fine, double tilt) {
  double f(double x) => Float32List.fromList([x]).single;
  broad = f(broad);
  fine = f(fine);
  var broadGain = 1.0;
  var fineGain = 1.0;
  if (math.min(broad, fine) >= f(0.000001)) {
    final transfer = f(f(f(0.15) * tilt) * math.min(broad, fine));
    broadGain = f(1 - f(transfer / broad));
    fineGain = f(1 + f(transfer / fine));
  } else {
    expect(broadGain, 1);
    expect(fineGain, 1);
  }
  expect(broadGain, inInclusiveRange(0.8499999, 1.1500001));
  expect(fineGain, inInclusiveRange(0.8499999, 1.1500001));
  final before = f(broad + fine);
  final after = f(f(broad * broadGain) + f(fine * fineGain));
  expect(after, closeTo(before, math.max(1e-12, before.abs() * 3e-7)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in kStyles.where((s) => _ids.contains(s.id))) {
    test('${style.id} recipe eligibility is independent of pulse', () {
      final shader = File('shaders/${style.id}.frag').readAsStringSync();
      final eligibility = shader.substring(
        shader.indexOf('bool stpD2GeometryEnabled()'),
        shader.indexOf('vec2 stpD2Rotate('),
      );
      // Includes Tape's near-epsilon tilt eligibility bound: pulse must not
      // change that threshold even when it does not directly select a recipe.
      expect(eligibility, isNot(contains('uSign.z')));
    });

    test('${style.id} tilt conserves its pulse-adjusted float32 envelope', () {
      final shader = File('shaders/${style.id}.frag').readAsStringSync();
      // Tie the numerical contract to the actual GLSL guard and denominators.
      expect(shader, contains('if (min(broadBound, fineBound) >= 0.000001)'));
      expect(shader, contains('1.0 - transfer / broadBound'));
      expect(shader, contains('1.0 + transfer / fineBound'));
      expect(shader, isNot(contains('transfer / max(')));
      if (style.id == 'prism') {
        final fine = RegExp(r'float fineBound = ([^;]+);')
            .firstMatch(shader)![1]!;
        expect(fine, contains('splitAmplitude * detail * pulseFactor'));
        expect(shader, contains('split *= pulseFactor;'));
      }
      for (final broad in [0.0, 1e-12, 0.999e-6, 1e-6, 1.001e-6, 0.05]) {
        for (final fine in [0.0, 1e-12, 0.999e-6, 1e-6, 1.001e-6, 0.07]) {
          for (final tilt in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
            _expectConserved(broad, fine, tilt);
          }
        }
      }
      double smooth(double lo, double hi, double x) {
        final t = ((x - lo) / (hi - lo)).clamp(0.0, 1.0);
        return t * t * (3 - 2 * t);
      }

      for (final noise in [0.0, 0.1, 0.250001, 0.3, 0.65, 1.0]) {
        final onset = math.pow(noise, 0.75).toDouble();
        final tearing = smooth(0.25, 0.65, noise);
        final corruption = smooth(0.60, 1, noise);
        for (final bass in [0.0, 1.0]) {
          for (final treble in [0.0, 1.0]) {
            for (final pulse in [-1.0, 0.0, 1.0]) {
              final detail = 1 + (style.id == 'tape' ? 0.12 : 0.15) * treble;
              final pulseFactor = 1 + 0.04 * pulse * noise;
              final broad = switch (style.id) {
                'static' =>
                  0.020 * tearing + 0.018 * corruption + 0.003 * bass * noise,
                'tape' =>
                  (0.016 +
                              0.012 *
                                  (1 + 0.15 * bass) *
                                  (1 + 0.04 * pulse.abs() * noise)) *
                          tearing +
                      0.014 * corruption,
                _ => 0.018 * tearing + 0.018 * corruption,
              };
              final split = switch (style.id) {
                'static' =>
                  (0.006 * onset + 0.007 * tearing + 0.010 * corruption) *
                      detail,
                'tape' =>
                  (0.0065 * onset + 0.006 * tearing + 0.009 * corruption) *
                      detail,
                _ =>
                  1.414214 *
                      (0.007 * onset + 0.008 * tearing + 0.012 * corruption) *
                      detail *
                      pulseFactor,
              };
              final fine =
                  (style.id == 'tape' ? 0.0025 : 0.003) * onset * detail +
                  split +
                  0.004 * noise * treble;
              for (final tilt in [-1.0, 1.0]) {
                _expectConserved(broad, fine, tilt);
              }
            }
          }
        }
      }
    });

    group('${style.id} delivery 2', () {
      late EffectRenderer renderer;
      late EffectRenderer oracle;
      late List<ui.Image> sources;
      final oraclePath = 'test/effects/fixtures/d2a_delivery1_${style.id}.frag';

      setUp(() async {
        renderer = await EffectRenderer.load(style);
        oracle = await EffectRenderer.load(
          StyleDefinition(
            id: '${style.id}-delivery1',
            name: 'Frozen delivery 1 oracle',
            shaderAsset: oraclePath,
          ),
        );
        sources = [
          await testImage(width: 192, height: 144),
          await sig2bScene(),
          await testImage(width: 96, height: 160),
        ];
      });
      tearDown(() {
        renderer.dispose();
        oracle.dispose();
        for (final source in sources) {
          source.dispose();
        }
      });

      test('neutral context exactly reproduces frozen delivery 1', () async {
        final frozen = File(oraclePath)
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        expect(
          sha256.convert(utf8.encode(frozen)).toString(),
          _oracleHashes[style.id],
        );
        for (final source in sources) {
          for (final state in [
            AmbientState.calm,
            const AmbientState(noise: 1, light: 0, motion: 1),
            const AmbientState(noise: 0.4, light: 1, motion: 0.3),
            _state(SignatureState.neutral),
            _state(_micro, light: 1),
            _state(_micro, noise: 1, light: 0, motion: 1, seed: 0.91),
          ]) {
            final expected = await _render(oracle, source, state);
            expect(
              await _render(renderer, source, state),
              orderedEquals(expected),
            );
          }
        }
      });

      test('zero-band pulse converges continuously to delivery 1', () async {
        final maxMae = {-1.0: 0.0, 1.0: 0.0};
        final maxPixel = {-1.0: 0, 1.0: 0};
        var maxEpsilonPixel = 0;
        for (final source in sources) {
          for (final noise in [0.0, 0.1, 0.25, 0.250001, 0.3, 0.85, 1.0]) {
            for (final light in [0.0, 0.5, 1.0]) {
              for (final motion in [0.0, 1.0]) {
                AmbientState state(double pulse) => AmbientState(
                  noise: noise,
                  light: light,
                  motion: motion,
                  motionDirX: 0.6,
                  motionDirY: 0.8,
                  bass: 0,
                  mid: 0,
                  treble: 0,
                  seed: 0,
                  signature: SignatureState(pulse: pulse),
                );
                final baseline = await _render(oracle, source, state(0));
                expect(
                  await _render(renderer, source, state(0)),
                  orderedEquals(baseline),
                );
                for (final pulse in [-0.0001, 0.0001, -1.0, 1.0]) {
                  final changed = await _render(renderer, source, state(pulse));
                  final mae = difference(baseline, changed);
                  final maximum = _maxPixelChange(baseline, changed);
                  final reason =
                      'pulse=$pulse noise=$noise light=$light motion=$motion '
                      'size=${source.width}x${source.height}';
                  if (noise == 0 || (style.id == 'tape' && noise <= 0.25)) {
                    expect(changed, orderedEquals(baseline), reason: reason);
                  }
                  if (pulse.abs() < 1) {
                    maxEpsilonPixel = math.max(maxEpsilonPixel, maximum);
                    // Per channel, per pixel; an average would hide a jump.
                    expect(maximum, lessThanOrEqualTo(1), reason: reason);
                  } else {
                    maxMae[pulse] = math.max(maxMae[pulse]!, mae);
                    maxPixel[pulse] = math.max(maxPixel[pulse]!, maximum);
                    // Only a <=4% component modulation on the selected D1 path.
                    expect(mae, lessThanOrEqualTo(5), reason: reason);
                    expect(
                      maximum,
                      lessThanOrEqualTo(style.id == 'static' ? 16 : 96),
                      reason: reason,
                    );
                  }
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print('${style.id} zero-band pulse epsilon max RGB8=$maxEpsilonPixel');
        for (final pulse in [-1.0, 1.0]) {
          // Report each sign separately, aggregated over the fixture/control grid.
          // ignore: avoid_print
          print(
            '${style.id} zero-band pulse=$pulse: '
            'maxMAE RGB8=${maxMae[pulse]} maxPixelLinf RGB8=${maxPixel[pulse]}',
          );
          expect(maxMae[pulse], greaterThan(0));
        }
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('each contextual signal is effective and bounded', () async {
        final largestMae = {for (final key in _signals.keys) key: 0.0};
        for (var f = 0; f < sources.length; f++) {
          final source = sources[f];
          final baseline = await _render(
            renderer,
            source,
            _state(SignatureState.neutral),
          );
          for (final signal in _signals.entries) {
            final state = _state(signal.value);
            final changed = await _render(renderer, source, state);
            final mae = difference(baseline, changed);
            final maximum = _maxPixelChange(baseline, changed);
            largestMae[signal.key] = math.max(largestMae[signal.key]!, mae);
            // Print before assertions so failures retain calibration evidence.
            // ignore: avoid_print
            print(
              '${style.id} fixture=$f ${signal.key}: MAE RGB8=$mae maxPixelLinf RGB8=$maximum',
            );
            expect(mae, greaterThan(0), reason: '${signal.key}, fixture $f');
            // Provisional acceptance limits; the lead must inspect measured logs.
            expect(
              mae,
              lessThanOrEqualTo(signal.key.startsWith('pulse') ? 5 : 40),
            );
            // Two outputs each retain 45% of the identical source: ceil(.55*255).
            expect(maximum, lessThanOrEqualTo(141));
            expect(
              await _render(renderer, source, state),
              orderedEquals(changed),
            );
          }
        }
        for (final entry in largestMae.entries) {
          expect(entry.value, greaterThanOrEqualTo(0.005), reason: entry.key);
        }
      });

      test(
        'inapplicable tilt and tracking keep the zero-band D1 route',
        () async {
          for (final source in sources) {
            for (final noise in [0.1, 0.250001]) {
              for (final light in [0.0, 0.5, 1.0]) {
                AmbientState state(SignatureState signature) => AmbientState(
                  noise: noise,
                  light: light,
                  motion: 0,
                  signature: signature,
                );
                final baseline = await _render(
                  oracle,
                  source,
                  state(SignatureState.neutral),
                );
                for (final tilt in [-1.0, 1.0]) {
                  expect(
                    await _render(
                      renderer,
                      source,
                      state(SignatureState(tilt: tilt)),
                    ),
                    orderedEquals(baseline),
                  );
                }
                if (style.id == 'tape' && noise <= 0.25) {
                  for (final pulse in [-1.0, 1.0]) {
                    expect(
                      await _render(
                        renderer,
                        source,
                        state(SignatureState(pulse: pulse)),
                      ),
                      orderedEquals(baseline),
                    );
                  }
                }
              }
            }
          }
        },
      );

      test('zero-band context preserves D1 grading and only changes colour', () async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final black = await picture.toImage(48, 32);
        picture.dispose();
        addTearDown(black.dispose);
        for (final source in [...sources, black]) {
          final original = await pixels(source);
          for (final light in [0.0, 1.0, 0.5]) {
            AmbientState quiet(SignatureState signature) => AmbientState(
              noise: 0,
              light: light,
              motion: 0,
              bass: 0,
              mid: 0,
              treble: 0,
              seed: 0,
              signature: signature,
            );
            final baseline = await _render(
              oracle,
              source,
              quiet(SignatureState.neutral),
            );
            expect(
              await _render(renderer, source, quiet(SignatureState.neutral)),
              orderedEquals(baseline),
            );
            for (final signal in {
              ..._signals,
              'warmth infinitesimal': const SignatureState(warmth: 0.000001),
              'hue infinitesimal': const SignatureState(hue: 0.000001),
            }.entries) {
              final changed = await _render(
                renderer,
                source,
                quiet(signal.value),
              );
              final isColor =
                  signal.key.startsWith('warmth') ||
                  signal.key.startsWith('hue') ||
                  signal.key.startsWith('chroma');
              if (!isColor || light == 0.5) {
                expect(changed, orderedEquals(baseline), reason: signal.key);
              } else {
                final expected = _colorOnly(
                  style.id,
                  baseline,
                  original,
                  source.width,
                  source.height,
                  light,
                  signal.value,
                );
                expect(
                  _maxPixelChange(changed, expected),
                  lessThanOrEqualTo(2),
                  reason: '${signal.key}, light=$light',
                );
                if (!signal.key.startsWith('chroma')) {
                  expect(
                    _maxPixelChange(baseline, changed),
                    lessThanOrEqualTo(11),
                  );
                }
              }
              expect(
                await _render(renderer, source, quiet(signal.value)),
                orderedEquals(changed),
              );
            }
          }
          // The protected D1 path must also ignore axis/tilt/pulse at n=0,
          // including light extremes where a changed grain cell would show up.
          for (final light in [0.0, 0.5, 1.0]) {
            final baseline = await _render(
              oracle,
              source,
              _state(SignatureState.neutral, noise: 0, light: light, motion: 0),
            );
            for (final signal in _signals.entries.where(
              (s) =>
                  s.key.startsWith('axis') ||
                  s.key.startsWith('tilt') ||
                  s.key.startsWith('pulse'),
            )) {
              expect(
                await _render(
                  renderer,
                  source,
                  _state(signal.value, noise: 0, light: light, motion: 0),
                ),
                orderedEquals(baseline),
                reason: signal.key,
              );
            }
          }
        }
      });

      test('silent pulse, reserved lane and neutral controls are exact bypasses', () async {
        for (final source in sources) {
          // Include the zero-band/seed legacy route: a silent pulse must not
          // accidentally enable the protected macro recipe and soften grading.
          for (final base in [
            SignatureState.neutral,
            _extremes.first.withMood(pulse: 0),
          ]) {
            for (final signed in [false, true]) {
              AmbientState quiet(SignatureState signature) => signed
                  ? _state(signature, noise: 0)
                  : AmbientState(
                      noise: 0,
                      light: 0.25,
                      motion: 0.4,
                      signature: signature,
                    );
              final expected = await _render(renderer, source, quiet(base));
              for (final pulse in [-1.0, 1.0]) {
                expect(
                  await _render(
                    renderer,
                    source,
                    quiet(base.copyWith(pulse: pulse)),
                  ),
                  orderedEquals(expected),
                );
              }
              expect(
                await _render(
                  renderer,
                  source,
                  quiet(base.copyWith(reserved: 1)),
                ),
                orderedEquals(expected),
              );
            }
          }
          final calm = await _render(
            renderer,
            source,
            _state(SignatureState.neutral, noise: 0, light: 0.5, motion: 0),
          );
          for (final context in _extremes) {
            final noMicro = context.copyWith(x: 0, y: 0, z: 0, w: 0);
            expect(
              await _render(
                renderer,
                source,
                _state(noMicro, noise: 0, light: 0.5, motion: 0),
              ),
              orderedEquals(calm),
            );
          }
        }
      });

      test('combined extremes retain structure with bands, seed and fingerprint', () async {
        var minOriginal = 1.0;
        var minOriginalD1 = 1.0;
        var minDelivery1 = 1.0;
        var maxMae = 0.0;
        var maxPixel = 0;
        for (final source in sources) {
          final original = _thumbnail(
            await pixels(source),
            source.width,
            source.height,
          );
          for (final seed in [0.13, 0.73]) {
            for (final light in [0.0, 0.5, 1.0]) {
              final baseline = await _render(
                oracle,
                source,
                _state(_micro, noise: 1, light: light, motion: 1, seed: seed),
              );
              final oldStructure = _thumbnail(
                baseline,
                source.width,
                source.height,
              );
              minOriginalD1 = math.min(
                minOriginalD1,
                _correlation(original, oldStructure),
              );
              for (final context in _extremes) {
                final state = _state(
                  context,
                  noise: 1,
                  light: light,
                  motion: 1,
                  seed: seed,
                );
                final changed = await _render(renderer, source, state);
                final structure = _thumbnail(
                  changed,
                  source.width,
                  source.height,
                );
                minOriginal = math.min(
                  minOriginal,
                  _correlation(original, structure),
                );
                final correlation = _correlation(oldStructure, structure);
                minDelivery1 = math.min(minDelivery1, correlation);
                expect(
                  correlation,
                  greaterThanOrEqualTo(0.95),
                  reason: '${style.id}, seed=$seed, light=$light',
                );
                maxMae = math.max(maxMae, difference(baseline, changed));
                maxPixel = math.max(
                  maxPixel,
                  _maxPixelChange(baseline, changed),
                );
                expect(
                  await _render(renderer, source, state),
                  orderedEquals(changed),
                );
              }
            }
          }
        }
        // ignore: avoid_print
        print(
          '${style.id} extremes: minCorrelation64 original-D1=$minOriginalD1 original-D2=$minOriginal D1-D2=$minDelivery1 maxMAE RGB8=$maxMae maxPixelLinf RGB8=$maxPixel',
        );

        expect(maxMae, lessThanOrEqualTo(40));
        // Same bounded micro-fingerprint can differ by one code after clipping.
        expect(maxPixel, lessThanOrEqualTo(142));
      });
    });
  }
}
