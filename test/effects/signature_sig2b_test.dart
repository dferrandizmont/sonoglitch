import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;
import 'new_styles_test.dart' show sig2bScene;

const _ids = {'phosphor', 'ripple', 'thermal'};
const _seeds = [0.07, 0.29, 0.61, 0.93];
const _bands = [
  (1.0, 0.0, 0.0),
  (0.0, 1.0, 0.0),
  (0.0, 0.0, 1.0),
  (1.0, 1.0, 1.0),
  (0.0, 0.0, 0.0),
];

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
    // Fail on unsupported rendering or invalid floats, before RGB8 hides NaN.
    final raw = (await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    final floats = raw.buffer.asFloat32List(
      raw.offsetInBytes,
      raw.lengthInBytes ~/ 4,
    );
    expect(
      floats.every((value) => value.isFinite && value >= 0 && value <= 1),
      isTrue,
    );
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

// Area-average luma to a longest side of 64, retaining the source aspect ratio.
// Averaging rather than point sampling prevents scanline/grille aliasing from
// impersonating global structure. This metric requires non-flat fixtures.
List<double> _thumbnail(Uint8List bytes, int width, int height) {
  final scale = 64 / math.max(width, height);
  final outWidth = math.max(1, (width * scale).round());
  final outHeight = math.max(1, (height * scale).round());
  final sums = List<double>.filled(outWidth * outHeight, 0);
  final counts = List<int>.filled(sums.length, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bin = (y * outHeight ~/ height) * outWidth + x * outWidth ~/ width;
      final offset = (y * width + x) * 4;
      sums[bin] +=
          bytes[offset] * 0.2126 +
          bytes[offset + 1] * 0.7152 +
          bytes[offset + 2] * 0.0722;
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
  expect(
    varianceA * varianceB,
    greaterThan(0),
    reason: 'Textured fixture required',
  );
  return covariance / math.sqrt(varianceA * varianceB);
}

// Spatial variation of the pairwise residual, excluding a uniform RGB tint.
double _residualSpread(Uint8List a, Uint8List b) {
  var sum = 0.0;
  var square = 0.0;
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    final delta =
        (a[i] - b[i]) * 0.2126 +
        (a[i + 1] - b[i + 1]) * 0.7152 +
        (a[i + 2] - b[i + 2]) * 0.0722;
    sum += delta;
    square += delta * delta;
    count++;
  }
  return math.sqrt(math.max(0, square / count - math.pow(sum / count, 2)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in kStyles.where((style) => _ids.contains(style.id))) {
    group('${style.id} signature', () {
      late EffectRenderer renderer;
      late EffectRenderer legacy;
      late List<ui.Image> sources;
      setUp(() async {
        renderer = await EffectRenderer.load(style);
        legacy = await EffectRenderer.load(
          StyleDefinition(
            id: '${style.id}-legacy',
            name: 'Frozen legacy oracle',
            shaderAsset: 'test/effects/fixtures/sig2b_legacy_${style.id}.frag',
          ),
        );
        sources = [
          await testImage(width: 256, height: 192),
          await sig2bScene(),
        ];
      });
      tearDown(() {
        renderer.dispose();
        legacy.dispose();
        for (final source in sources) {
          source.dispose();
        }
      });

      test('extended signals preserve legacy pixels when neutral', () async {
        for (final source in sources) {
          for (final state in const [
            AmbientState.calm,
            AmbientState(
              noise: 1,
              light: 0,
              motion: 1,
              motionDirX: -0.6,
              motionDirY: 0.8,
            ),
            AmbientState(noise: 0.4, light: 1, motion: 0.3),
          ]) {
            for (final time in [0.0, 1.25, 1000000.0]) {
              expect(
                await _render(renderer, source, state, time: time),
                await _render(legacy, source, state, time: time),
              );
            }
          }
        }
      });

      test('seed diversity, recognisability and determinism matrix', () async {
        var minOriginal = 1.0;
        var minLegacy = 1.0;
        var minDiversity = double.infinity;
        var minSpread = double.infinity;
        // Floors are set under the measured minima (original >= 0.93, legacy
        // >= 0.80, seed MAE >= 0.73, spread >= 0.96 across the three styles).
        // The minima are printed even on failure.
        try {
          for (var fixture = 0; fixture < sources.length; fixture++) {
            final source = sources[fixture];
            List<double> thumb(Uint8List bytes) =>
                _thumbnail(bytes, source.width, source.height);
            final original = thumb(await pixels(source));
            for (final controls in [
              (0.8, 0.35, 0.5),
              (1.0, 0.0, 1.0),
              (1.0, 1.0, 1.0),
            ]) {
              final baseline = thumb(
                await _render(
                  legacy,
                  source,
                  AmbientState(
                    noise: controls.$1,
                    light: controls.$2,
                    motion: controls.$3,
                    motionDirX: 0.6,
                    motionDirY: 0.8,
                  ),
                ),
              );
              for (final bands in _bands) {
                final results = <Uint8List>[];
                for (final seed in _seeds) {
                  final state = AmbientState(
                    noise: controls.$1,
                    light: controls.$2,
                    motion: controls.$3,
                    motionDirX: 0.6,
                    motionDirY: 0.8,
                    bass: bands.$1,
                    mid: bands.$2,
                    treble: bands.$3,
                    seed: seed,
                  );
                  final rendered = await _render(renderer, source, state);
                  expect(
                    await _render(renderer, source, state),
                    rendered,
                    reason: 'Identical snapshot must render identically',
                  );
                  final thumbnail = thumb(rendered);
                  minOriginal = math.min(
                    minOriginal,
                    _correlation(original, thumbnail),
                  );
                  minLegacy = math.min(
                    minLegacy,
                    _correlation(baseline, thumbnail),
                  );
                  results.add(rendered);
                }
                for (var i = 0; i < results.length; i++) {
                  for (var j = i + 1; j < results.length; j++) {
                    minDiversity = math.min(
                      minDiversity,
                      difference(results[i], results[j]),
                    );
                    minSpread = math.min(
                      minSpread,
                      _residualSpread(results[i], results[j]),
                    );
                  }
                }
              }
            }
          }
        } finally {
          // ignore: avoid_print
          print(
            '${style.id} SIG-2B: min correlation original=$minOriginal, legacy=$minLegacy; min seed RGB8 MAE=$minDiversity, residual spread=$minSpread',
          );
        }
        expect(minOriginal, greaterThanOrEqualTo(0.85));
        expect(minLegacy, greaterThanOrEqualTo(0.75));
        expect(minDiversity, greaterThanOrEqualTo(0.5));
        expect(minSpread, greaterThanOrEqualTo(0.5));
      });

      test(
        'each band changes pattern independently under active noise',
        () async {
          final source = sources.last;
          const base = AmbientState(noise: 1, seed: 0.29);
          final neutralBands = await _render(renderer, source, base);
          final outputs = <Uint8List>[];
          for (final band in _bands.take(3)) {
            final rendered = await _render(
              renderer,
              source,
              AmbientState(
                noise: 1,
                seed: 0.29,
                bass: band.$1,
                mid: band.$2,
                treble: band.$3,
              ),
            );
            expect(difference(neutralBands, rendered), greaterThan(0.01));
            outputs.add(rendered);
          }
          for (var i = 0; i < outputs.length; i++) {
            for (var j = i + 1; j < outputs.length; j++) {
              expect(difference(outputs[i], outputs[j]), greaterThan(0.01));
            }
          }
        },
      );

      test('all four fingerprint lanes are deterministic and bounded', () async {
        final source = sources.first;
        // A fingerprint cannot switch recipes, even when macro inputs are zero.
        for (final seed in [0.0, 0.29]) {
          for (final active in [false, true]) {
            AmbientState state(SignatureState fingerprint) => AmbientState(
              noise: active ? 1 : 0,
              light: active ? 0 : 0.5,
              motion: active ? 1 : 0,
              motionDirX: 0.6,
              motionDirY: 0.8,
              seed: seed,
              signature: fingerprint,
            );
            final base = await _render(
              renderer,
              source,
              state(SignatureState.neutral),
            );
            for (final fingerprint in const [
              SignatureState(x: 0.17),
              SignatureState(y: 0.31),
              SignatureState(z: 0.53),
              SignatureState(w: 0.79),
              SignatureState(x: 0.17, y: 0.31, z: 0.53, w: 0.79),
            ]) {
              final rendered = await _render(
                renderer,
                source,
                state(fingerprint),
              );
              expect(
                await _render(renderer, source, state(fingerprint)),
                rendered,
              );
              expect(difference(base, rendered), greaterThan(0));
              var maxDelta = 0;
              for (var i = 0; i < base.length; i++) {
                maxDelta = math.max(maxDelta, (rendered[i] - base[i]).abs());
              }
              expect(maxDelta, lessThanOrEqualTo(1));
            }
          }
        }
      });
    });
  }
}
