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

import 'effect_renderer_test.dart' show pixels, testImage;
import 'new_styles_test.dart' show sig2bScene;

// Independently captured before D2 edits: uniforms, helpers AND the entire D1
// recipe. The dispatcher must call this exact implementation at neutral inputs,
// including nonzero bands/seed (the older GPU oracles predate those recipes).
const _delivery1 = {
  'phosphor':
      'ea2f0eb2c11e2160afbb1177eaf9ab6231583f8ab6b05b7497b94fbc2e1e3e85',
  'ripple': '8ba44cef327b196fc3ae7b72749dc9dd1704305782fec148436819744beb4d88',
  'thermal': 'a54d3e8d5b610d275b443b2f7a8a3b3254f0bdf826f073818cb3b689ab80b868',
};

final _signals = <String, SignatureState>{
  'warmth-': const SignatureState(warmth: -1),
  'warmth+': const SignatureState(warmth: 1),
  'hue-': const SignatureState(hue: -1),
  'hue+': const SignatureState(hue: 1),
  'chroma': const SignatureState(chromaAllowance: 0.65),
  'tilt-': const SignatureState(tilt: -1),
  'tilt+': const SignatureState(tilt: 1),
  'axis-12': SignatureState(
    axisX: math.cos(math.pi / 15),
    axisY: -math.sin(math.pi / 15),
  ),
  'axis+12': SignatureState(
    axisX: math.cos(math.pi / 15),
    axisY: math.sin(math.pi / 15),
  ),
  'pulse-': const SignatureState(pulse: -1),
  'pulse+': const SignatureState(pulse: 1),
};

AmbientState _state(
  SignatureState signature, {
  double noise = 1,
  double light = 0.35,
  double motion = 0.5,
  double seed = 0.29,
  double band = 0.6,
}) => AmbientState(
  noise: noise,
  light: light,
  motion: motion,
  motionDirX: 0.6,
  motionDirY: 0.8,
  bass: band,
  mid: band,
  treble: band,
  seed: seed,
  signature: signature,
);

Future<Uint8List> _render(
  EffectRenderer renderer,
  ui.Image source,
  AmbientState state, {
  double time = 1.25,
}) async {
  final image = await renderer.renderToImage(
    source,
    ambient: state,
    time: time,
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
    var opaque = true;
    for (var i = 3; i < floats.length; i += 4) {
      opaque &= floats[i] == 1;
    }
    expect(opaque, isTrue);
    return await pixels(image);
  } finally {
    image.dispose();
  }
}

// RGB-only MAE and largest per-pixel L-infinity difference, in RGB8 levels.
// Alpha is checked separately in float space; it must not dilute the metric.
(double, int) _delta(Uint8List a, Uint8List b) {
  var total = 0;
  var maximum = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final d = (a[i + c] - b[i + c]).abs();
      total += d;
      maximum = math.max(maximum, d);
    }
  }
  return (total / (a.length ~/ 4 * 3), maximum);
}

List<double> _thumbnail(Uint8List bytes, int width, int height) {
  final scale = 64 / math.max(width, height);
  final w = math.max(1, (width * scale).round());
  final h = math.max(1, (height * scale).round());
  final sums = List<double>.filled(w * h, 0);
  final counts = List<int>.filled(w * h, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bin = (y * h ~/ height) * w + x * w ~/ width;
      final i = (y * width + x) * 4;
      sums[bin] +=
          bytes[i] * 0.2126 + bytes[i + 1] * 0.7152 + bytes[i + 2] * 0.0722;
      counts[bin]++;
    }
  }
  return List.generate(sums.length, (i) => sums[i] / counts[i]);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in kStyles.where((s) => _delivery1.containsKey(s.id))) {
    group('${style.id} D2', () {
      test('neutral dispatcher preserves the exact delivery-1 implementation', () {
        final source = File(style.shaderAsset)
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        final frozen = source
            .substring(
              source.indexOf('uniform vec2 uSize;'),
              source.indexOf('// D2-LEGACY-END:'),
            )
            .trimRight()
            .replaceFirst('void sig2dLegacy()', 'void main()');
        expect(
          sha256.convert(utf8.encode('$frozen\n')).toString(),
          _delivery1[style.id],
        );
        final dispatcher = source.substring(source.indexOf('void main()'));
        expect(dispatcher, contains('uMood.z < 1.0'));
        expect(dispatcher, contains('(signedRecipe && colorOnly)'));
        expect(dispatcher, contains('any(notEqual(uFingerprint, vec4(0.0)))'));
        expect(
          dispatcher,
          contains('else if (colorOnly && (uSign.z == 0.0 || uNoise <= 0.0))'),
        );
        expect(
          dispatcher,
          contains('sig2dColorOnly(fragColor.rgb, imageAt(p)'),
        );
        expect(dispatcher, contains('else if (colorOnly) sig2dPulse();'));
        expect(dispatcher, contains('(uNoise > 0.0 && (uMood.w != 0.0'));
        expect(dispatcher, contains('any(notEqual(uSign.xy, vec2(1.0, 0.0)))'));
        expect(
          dispatcher,
          contains('else if (uSign.z != 0.0 && uNoise > 0.0) sig2dPulse();'),
        );
        final selection = dispatcher.substring(
          0,
          dispatcher.indexOf('if (contextual)'),
        );
        expect(selection, isNot(contains('uSign.z')));
        // sig2dPulse is the delivery-1 path: it keeps the frozen pow so that a
        // vanishing pulse converges to delivery 1 on every backend.
        final afterLegacy = source.substring(
          source.indexOf('// D2-LEGACY-END:'),
        );
        final pulseStart = afterLegacy.indexOf('void sig2dPulse()');
        final pulseEnd = afterLegacy.indexOf('// D2 helpers');
        expect(
          afterLegacy.substring(0, pulseStart) +
              afterLegacy.substring(pulseEnd),
          isNot(contains('pow(')),
        );
        final modulated = source.substring(
          source.indexOf('void sig2dPulse()'),
          source.indexOf('// D2 helpers'),
        );
        expect(
          modulated,
          contains(
            'bool signedRecipe = uBass > 0.0 || uMid > 0.0 || uTreble > 0.0 || uSeed > 0.0;',
          ),
        );
        expect(
          modulated,
          contains('if (signedRecipe) color = signatureRetainOriginal'),
        );
        expect(modulated, contains('color = sig2dColorOnly('));
      });

      test('tilt conserves the effective post-pulse envelope', () {
        final source = File(style.shaderAsset)
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        final context = source.substring(source.indexOf('void sig2dContext()'));
        // Bind the numerical contract below to the shader's actual allocation:
        // pulse is included before the transfer and never applied to it again.
        switch (style.id) {
          case 'phosphor':
            expect(
              context,
              contains('0.075 * (1.0 + 0.15 * uBass) * pulseGain;'),
            );
            expect(context, contains('min(glowAmount, snowAmount)'));
            expect(context, contains('* n * (glowAmount - transfer);'));
          case 'thermal':
            expect(
              context,
              contains('float contourAmount = 0.18 * pulseGain;'),
            );
            expect(context, contains('min(contourAmount, hissAmount)'));
            expect(context, contains('(contourAmount - transfer) * ridge\n'));
          case 'ripple':
            expect(context, contains('abs(0.08 - 0.24 * uLight) * pulseGain;'));
            expect(context, contains('min(broadEnvelope, detailAmount)'));
            expect(context, contains('broadAmount *= broadGain;'));
            expect(
              context,
              contains('cappedRings * n * broadGain * pulseGain;'),
            );
        }
        // Round each operation to float32, matching shader coefficient precision.
        double f(double value) => Float32List.fromList([value]).single;
        var maxError = 0.0;
        for (final noise in [0.0, 0.35, 1.0]) {
          for (final bass in [0.0, 1.0]) {
            for (final treble in [0.0, 1.0]) {
              for (final light in [0.0, 0.5, 1.0]) {
                for (final pulse in [-1.0, 0.0, 1.0]) {
                  final p = f(1 + f(f(0.04 * pulse) * noise));
                  final broad = switch (style.id) {
                    'phosphor' => f(f(0.075 * f(1 + f(0.15 * bass))) * p),
                    'thermal' => f(0.18 * p),
                    _ => f(0.030 + f(f((0.08 - 0.24 * light).abs()) * p)),
                  };
                  final fine = f(
                    (style.id == 'phosphor'
                            ? 0.26
                            : style.id == 'thermal'
                            ? 0.045
                            : 0.08) *
                        f(1 + f(0.15 * treble)),
                  );
                  final neutral = f(broad + fine);
                  for (final tilt in [-1.0, 0.0, 1.0]) {
                    final transfer = f(
                      f(0.15 * (noise > 0 ? tilt : 0)) * math.min(broad, fine),
                    );
                    final gain = f(f(broad - transfer) / broad);
                    final allocatedBroad = style.id == 'ripple'
                        ? f(f(0.030 * gain) + f(f(broad - 0.030) * gain))
                        : f(broad - transfer);
                    final allocatedFine = f(fine + transfer);
                    final effective = f(allocatedBroad + allocatedFine);
                    maxError = math.max(maxError, (effective - neutral).abs());
                    expect(allocatedBroad, greaterThanOrEqualTo(0));
                    expect(allocatedFine, greaterThanOrEqualTo(0));
                    expect(effective, closeTo(neutral, 1e-7));
                    expect(effective, lessThanOrEqualTo(neutral + 1e-7));
                  }
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print(
          '${style.id} D2 tilt/pulse maximum float32 envelope error=$maxError',
        );
      });

      late EffectRenderer renderer;
      late EffectRenderer legacy;
      late List<ui.Image> sources;
      setUp(() async {
        renderer = await EffectRenderer.load(style);
        legacy = await EffectRenderer.load(
          StyleDefinition(
            id: '${style.id}-legacy',
            name: 'Frozen pre-signature oracle',
            shaderAsset: 'test/effects/fixtures/sig2b_legacy_${style.id}.frag',
          ),
        );
        sources = [
          await testImage(width: 256, height: 192),
          await sig2bScene(),
          await testImage(width: 192, height: 256),
        ];
      });
      tearDown(() {
        renderer.dispose();
        legacy.dispose();
        for (final source in sources) {
          source.dispose();
        }
      });

      test('neutral pixels, including bands/seed, and reserved lane', () async {
        for (final source in sources) {
          for (final controls in [
            (0.0, 0.5, 0.0),
            (1.0, 0.0, 1.0),
            (0.4, 1.0, 0.3),
          ]) {
            for (final time in [0.0, 1.25, 1000000.0]) {
              final neutral = _state(
                SignatureState.neutral,
                noise: controls.$1,
                light: controls.$2,
                motion: controls.$3,
                band: 0,
                seed: 0,
              );
              expect(
                await _render(renderer, source, neutral, time: time),
                await _render(legacy, source, neutral, time: time),
              );
              for (final band in [0.0, 1.0]) {
                final base = _state(
                  SignatureState.neutral,
                  noise: controls.$1,
                  light: controls.$2,
                  motion: controls.$3,
                  band: band,
                );
                final explicit = _state(
                  const SignatureState(
                    warmth: 0,
                    hue: 0,
                    chromaAllowance: 1,
                    tilt: 0,
                    axisX: 1,
                    axisY: 0,
                    pulse: 0,
                    reserved: 1,
                  ),
                  noise: controls.$1,
                  light: controls.$2,
                  motion: controls.$3,
                  band: band,
                );
                expect(
                  await _render(renderer, source, explicit, time: time),
                  await _render(renderer, source, base, time: time),
                );
              }
            }
          }
        }
      });

      test('individual signals: measurable, bounded, deterministic', () async {
        for (var fixture = 0; fixture < sources.length; fixture++) {
          final source = sources[fixture];
          final base = await _render(
            renderer,
            source,
            _state(SignatureState.neutral),
          );
          for (final signal in _signals.entries) {
            final state = _state(signal.value);
            final result = await _render(renderer, source, state);
            final delta = _delta(base, result);
            // ignore: avoid_print
            print(
              '${style.id} D2 fixture=$fixture ${signal.key}: RGB8 MAE=${delta.$1}, maxPixelLInf=${delta.$2}',
            );
            expect(delta.$1, greaterThan(0.001), reason: signal.key);
            // Spatial frequency/axis changes can have sharp local residuals;
            // exact 45% retention bounds any one channel to ceil(.55*255).
            expect(delta.$1, lessThanOrEqualTo(15), reason: signal.key);
            expect(delta.$2, lessThanOrEqualTo(141), reason: signal.key);
            if (signal.key.startsWith('pulse')) {
              expect(delta.$1, lessThanOrEqualTo(0.6));
              expect(delta.$2, lessThanOrEqualTo(4));
            }
            expect(await _render(renderer, source, state), result);
          }
        }
      });

      test('colour-only signals preserve D1 sampling and the 4% gain cap', () async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const ui.Color(0xff808080), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final grey = await picture.toImage(48, 32);
        picture.dispose();
        addTearDown(grey.dispose);
        var maximum = 0;
        var greyQuietMaximum = 0;
        final failures = <String>[];
        for (final source in [...sources, grey]) {
          for (final light in [0.0, 0.5, 1.0]) {
            for (final noise in [0.0, 0.35, 1.0]) {
              for (final motion in [0.0, 1.0]) {
                AmbientState state(SignatureState signal) => _state(
                  signal,
                  noise: noise,
                  light: light,
                  motion: motion,
                  band: 0,
                  seed: 0,
                );
                final baseline = await _render(
                  legacy,
                  source,
                  state(SignatureState.neutral),
                );
                expect(
                  await _render(
                    renderer,
                    source,
                    state(SignatureState.neutral),
                  ),
                  baseline,
                );
                for (final signal in {
                  ...Map.fromEntries(
                    _signals.entries.where(
                      (s) =>
                          s.key.startsWith('warmth') ||
                          s.key.startsWith('hue') ||
                          s.key == 'chroma',
                    ),
                  ),
                  'warmth epsilon': const SignatureState(warmth: 1e-6),
                  'hue epsilon': const SignatureState(hue: -1e-6),
                  'chroma epsilon': const SignatureState(
                    chromaAllowance: 1 - 1e-6,
                  ),
                  'combined colour': const SignatureState(
                    warmth: 1,
                    hue: -1,
                    chromaAllowance: 0.65,
                  ),
                }.entries) {
                  final result = await _render(
                    renderer,
                    source,
                    state(signal.value),
                  );
                  final delta = _delta(baseline, result);
                  maximum = math.max(maximum, delta.$2);
                  if (source == grey && noise == 0 && motion == 0) {
                    greyQuietMaximum = math.max(greyQuietMaximum, delta.$2);
                  }
                  final activity = math.max(noise, (2 * light - 1).abs());
                  var excess = 0.0;
                  for (var i = 0; i < result.length; i += 4) {
                    for (var c = 0; c < 3; c++) {
                      // Two RGB8 codes cover reference/output quantisation
                      // and independent shader arithmetic, as in D2A.
                      final bound = baseline[i + c] * 0.04 * activity + 2;
                      excess = math.max(
                        excess,
                        (baseline[i + c] - result[i + c]).abs() - bound,
                      );
                    }
                  }
                  if (excess > 0 ||
                      (signal.key.endsWith('epsilon') && delta.$2 > 1) ||
                      (activity == 0 && delta.$2 != 0)) {
                    failures.add(
                      '${signal.key} n=$noise L=$light m=$motion: max=${delta.$2}, excess=$excess',
                    );
                  }
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print(
          '${style.id} D2 colour-only maximum RGB8 change=$maximum, quiet grey maximum=$greyQuietMaximum (4% gain cap)',
        );
        expect(failures.length, 0, reason: failures.take(8).join('\n'));
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('pulse converges to D1 with zero bands and seed', () async {
        for (final source in sources) {
          for (final controls in [
            (0.35, 0.35, 0.5),
            (1.0, 0.0, 1.0),
            (1.0, 1.0, 1.0),
          ]) {
            final neutral = _state(
              SignatureState.neutral,
              noise: controls.$1,
              light: controls.$2,
              motion: controls.$3,
              band: 0,
              seed: 0,
            );
            final d1 = await _render(renderer, source, neutral);
            expect(d1, await _render(legacy, source, neutral));
            for (final pulse in [0.0, -1e-4, 1e-4, -1.0, 1.0]) {
              final state = _state(
                SignatureState(pulse: pulse),
                noise: controls.$1,
                light: controls.$2,
                motion: controls.$3,
                band: 0,
                seed: 0,
              );
              final result = await _render(renderer, source, state);
              final delta = _delta(d1, result);
              // ignore: avoid_print
              print(
                '${style.id} D2 pulse=$pulse controls=$controls: RGB8 MAE=${delta.$1}, maxPixelLInf=${delta.$2}',
              );
              if (pulse == 0) {
                expect(result, d1);
              } else if (pulse.abs() <= 1e-4) {
                expect(delta.$2, lessThanOrEqualTo(1));
              } else {
                expect(delta.$2, lessThanOrEqualTo(4));
              }
              expect(await _render(renderer, source, state), result);
            }
          }
        }
      });

      test(
        'pulse, tilt and axis bypass noise zero, including active context',
        () async {
          for (final source in sources) {
            for (final seed in [0.0, 0.29]) {
              for (final band in [0.0, 1.0]) {
                for (final light in [0.0, 0.5, 1.0]) {
                  for (final signature in [
                    SignatureState.neutral,
                    const SignatureState(
                      warmth: 1,
                      hue: -1,
                      chromaAllowance: 0.65,
                    ),
                  ]) {
                    Future<Uint8List> render(SignatureState value) => _render(
                      renderer,
                      source,
                      _state(
                        value,
                        noise: 0,
                        seed: seed,
                        band: band,
                        light: light,
                      ),
                    );
                    final base = await render(signature);
                    for (final signal in _signals.entries.where(
                      (s) =>
                          s.key.startsWith('pulse') ||
                          s.key.startsWith('tilt') ||
                          s.key.startsWith('axis'),
                    )) {
                      expect(
                        await render(
                          signature.copyWith(
                            pulse: signal.value.pulse,
                            tilt: signal.value.tilt,
                            axisX: signal.value.axisX,
                            axisY: signal.value.axisY,
                          ),
                        ),
                        base,
                        reason: signal.key,
                      );
                    }
                  }
                }
              }
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test('combined extremes retain recognisability and original floor', () async {
        final pairedFailures = <String>[];
        var minOriginal = 1.0;
        var minD1 = 1.0;
        var minLegacy = 1.0;
        for (var fixture = 0; fixture < sources.length; fixture++) {
          final source = sources[fixture];
          List<double> thumb(Uint8List bytes) =>
              _thumbnail(bytes, source.width, source.height);
          final original = await pixels(source);
          for (final controls in [
            (0.8, 0.35, 0.5),
            (1.0, 0.0, 1.0),
            (1.0, 1.0, 1.0),
          ]) {
            final old = await _render(
              legacy,
              source,
              _state(
                SignatureState.neutral,
                noise: controls.$1,
                light: controls.$2,
                motion: controls.$3,
                band: 0,
                seed: 0,
              ),
            );
            for (final seed in [0.07, 0.93]) {
              final d1 = await _render(
                renderer,
                source,
                _state(
                  const SignatureState(x: 0.17, y: 0.31, z: 0.53, w: 0.79),
                  noise: controls.$1,
                  light: controls.$2,
                  motion: controls.$3,
                  band: 1,
                  seed: seed,
                ),
              );
              // Both independent heading signs inside each of the 16 corners:
              // 32 combinations, minimum allowance, all bands at one.
              for (var corner = 0; corner < 16; corner++) {
                double sign(int bit) => corner & (1 << bit) == 0 ? -1 : 1;
                for (final axisSign in [-1.0, 1.0]) {
                  final signature = SignatureState(
                    warmth: sign(0),
                    hue: sign(1),
                    chromaAllowance: 0.65,
                    tilt: sign(2),
                    pulse: sign(3),
                    axisX: math.cos(math.pi / 15),
                    axisY: axisSign * math.sin(math.pi / 15),
                    x: 0.17,
                    y: 0.31,
                    z: 0.53,
                    w: 0.79,
                  );
                  final state = _state(
                    signature,
                    noise: controls.$1,
                    light: controls.$2,
                    motion: controls.$3,
                    band: 1,
                    seed: seed,
                  );
                  final result = await _render(renderer, source, state);
                  final d2Original = _correlation(
                    thumb(result),
                    thumb(original),
                  );
                  final d1Original = _correlation(thumb(d1), thumb(original));
                  final d2D1 = _correlation(thumb(result), thumb(d1));
                  final d2Legacy = _correlation(thumb(result), thumb(old));
                  final d1Legacy = _correlation(thumb(d1), thumb(old));
                  minOriginal = math.min(minOriginal, d2Original);
                  minD1 = math.min(minD1, d2D1);
                  minLegacy = math.min(minLegacy, d2Legacy);
                  // Collect failures so all 32 combinations are rendered and printed.
                  // ignore: avoid_print
                  print(
                    '${style.id} D2 fixture=$fixture controls=$controls seed=$seed corner=$corner axis=$axisSign: corr(D2,D1)=$d2D1, corr(D2,original)=$d2Original, corr(D1,original)=$d1Original, dropOriginal=${d1Original - d2Original}, corr(D2,legacy)=$d2Legacy, corr(D1,legacy)=$d1Legacy, dropLegacy=${d1Legacy - d2Legacy}',
                  );
                  // The signed path keeps >= 45 % of the original, so it moves
                  // toward the original and away from the legacy render by
                  // design: the legacy correlation is diagnostic only.
                  if (d2D1 < 0.95 || d2Original < d1Original - 0.02) {
                    pairedFailures.add(
                      'fixture=$fixture controls=$controls seed=$seed corner=$corner axis=$axisSign',
                    );
                  }
                  // The effect term is clamped before the 45/55 mix. Allow
                  // one code for fingerprint plus one for RGB8 quantisation.
                  var retained = true;
                  for (var i = 0; i < result.length; i += 4) {
                    for (var c = 0; c < 3; c++) {
                      final lower = math.max(
                        0,
                        (0.45 * original[i + c]).floor() - 2,
                      );
                      final upper = math.min(
                        255,
                        (0.45 * original[i + c] + 0.55 * 255).ceil() + 2,
                      );
                      retained &=
                          result[i + c] >= lower && result[i + c] <= upper;
                    }
                  }
                  expect(retained, isTrue, reason: '45% original envelope');
                  if (corner == 0) {
                    expect(await _render(renderer, source, state), result);
                  }
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print(
          '${style.id} D2 minimum luma correlation: original=$minOriginal, D1=$minD1, legacy=$minLegacy',
        );
        expect(
          pairedFailures,
          isEmpty,
          reason: 'Each pair must meet D2/D1 >= .95 and both D1-relative drops <= .02',
        );
      }, timeout: const Timeout(Duration(minutes: 5)));
    });
  }
}
