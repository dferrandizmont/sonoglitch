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

const _ids = {'static', 'tape', 'prism'};
const _seeds = [0.13, 0.37, 0.73, 0.91];
const _bands = [
  (1.0, 0.0, 0.0),
  (0.0, 1.0, 0.0),
  (0.0, 0.0, 1.0),
  (1.0, 1.0, 1.0),
];
const _fingerprint = SignatureState(x: 0.125, y: 0.25, z: 0.5, w: 0.75);

// Captured from the SIG-1 shaders BEFORE editing. Only main's name/output
// assignment changed to make its body callable. These hashes cover constants,
// sampling, grading and the entire legacy recipe, independently of render tests.
const _legacyHashes = {
  'static': 'ba3508e6601e0bc9010bf6f7a485772328993b7fd3a356656c3aa19fdbf1d713',
  'tape': '94acf9d531562abcacb69be6dbc26427dc795598cd7fbcd3bc28594ca5a68e7f',
  'prism': '788d4b845a950d3c62a2ea79a50de74b464b6fd32cc19780ff0eb6705a8b3acb',
};

// D2 reuses the center tap through an out parameter and passes a shared grain
// divisor and pulse factor. Remove only that explicit plumbing and guarded
// warmth/pulse blocks before checking the original hash. The D2 render suite
// additionally compares neutral output byte-for-byte with the frozen D1 shader.
String _neutralLegacySource(String source, String style) {
  String replace(String from, String to) {
    expect(source, contains(from));
    source = source.replaceFirst(from, to);
    return source;
  }

  replace(
    'vec3 noiseSample(vec2 uv, vec2 shift, vec2 split, float wet, vec3 clean) {',
    'vec3 noiseSample(vec2 uv, vec2 shift, vec2 split, float wet) {\n'
        '  vec3 clean = sampleImage(uv);',
  );
  replace(
    'vec3 noiseSample(vec2 uv, vec2 shift, vec2 split, float wet) {\n'
        '  return noiseSample(uv, shift, split, wet, sampleImage(uv));\n}\n\n',
    '',
  );
  replace(
    'vec3 motionSample(vec2 uv, vec2 shift, vec2 split, float wet, out vec3 original) {\n'
        '  original = sampleImage(uv);\n'
        '  vec3 color = noiseSample(uv, shift, split, wet, original);',
    'vec3 motionSample(vec2 uv, vec2 shift, vec2 split, float wet) {\n'
        '  vec3 color = noiseSample(uv, shift, split, wet);',
  );
  replace(
    'vec3 moodGrade(vec3 color, vec2 uv, float tick, float grainDivisor)',
    'vec3 moodGrade(vec3 color, vec2 uv, float tick)',
  );
  replace(
    '    vec2 savedUv = uv;\n'
        '    if (uMood.x != 0.0 && uNoise > 0.0) uv /= grainDivisor;\n',
    '',
  );
  replace('    uv = savedUv;\n', '');
  replace(
    'vec3 legacyRecipe(float grainDivisor, float pulseFactor, out vec3 original)',
    'vec3 legacyRecipe()',
  );
  replace(switch (style) {
    'static' =>
      '  if (pulseFactor != 1.0) wet = min(1.0, wet * pulseFactor);\n',
    'tape' => '  if (pulseFactor != 1.0) tracking *= pulseFactor;\n',
    _ => '  if (pulseFactor != 1.0) split *= pulseFactor;\n',
  }, '');
  replace(
    'motionSample(uv, shift, split, wet, original);',
    'motionSample(uv, shift, split, wet);',
  );
  replace(
    'moodGrade(color, uv, tick, grainDivisor);',
    'moodGrade(color, uv, tick);',
  );
  return source;
}

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
    final values = raw.buffer.asFloat32List(
      raw.offsetInBytes,
      raw.lengthInBytes ~/ 4,
    );
    expect(values.every((v) => v.isFinite && v >= 0 && v <= 1), isTrue);
    for (var i = 3; i < values.length; i += 4) {
      expect(values[i], 1);
    }
    return await pixels(image);
  } finally {
    image.dispose();
  }
}

// Area-average luminance to <=64 pixels on the long side. Do not decimate:
// that would alias the deliberately high-frequency colour fixture.
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
  expect(
    varianceA * varianceB,
    greaterThan(0),
    reason: 'Use textured fixtures',
  );
  return covariance / math.sqrt(varianceA * varianceB);
}

// Remove the mean RGB difference before measuring the spatial residual.
// A seed that only adds a uniform tint must fail this diversity check.
double _spatialDifference(Uint8List a, Uint8List b) {
  final means = List<double>.filled(3, 0);
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      means[c] += a[i + c] - b[i + c];
    }
  }
  for (var c = 0; c < 3; c++) {
    means[c] /= a.length / 4;
  }
  var total = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      total += (a[i + c] - b[i + c] - means[c]).abs();
    }
  }
  return total / (a.length * 0.75);
}

// Same coherent synthetic scene as styles_set2_test.dart. There are currently
// no versioned photographic fixtures in test/effects; do not fetch private or
// unlicensed photographs to hide that integration gap.
Future<ui.Image> _scene() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawPaint(
    ui.Paint()
      ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(0, 192), [
        const ui.Color(0xff365778),
        const ui.Color(0xffdcc69c),
      ]),
  );
  canvas.drawCircle(
    const ui.Offset(208, 35),
    22,
    ui.Paint()..color = const ui.Color(0xffedcd76),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 122)
      ..lineTo(70, 63)
      ..lineTo(149, 119)
      ..lineTo(215, 82)
      ..lineTo(256, 127)
      ..lineTo(256, 192)
      ..lineTo(0, 192)
      ..close(),
    ui.Paint()..color = const ui.Color(0xff345849),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(83, 112, 91, 68),
    ui.Paint()..color = const ui.Color(0xffcc956e),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(74, 115)
      ..lineTo(129, 77)
      ..lineTo(184, 115)
      ..close(),
    ui.Paint()..color = const ui.Color(0xff6e3833),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(119, 141, 20, 39),
    ui.Paint()..color = const ui.Color(0xff303b49),
  );
  for (final x in [92.0, 148.0]) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x, 129, 13, 15),
      ui.Paint()..color = const ui.Color(0xffb3d1dd),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(256, 192);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in kStyles.where((s) => _ids.contains(s.id))) {
    test('${style.id}: neutral path retains the historical arithmetic', () {
      final source = File(style.shaderAsset)
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final legacy = source
          .substring(
            source.indexOf('const float TRAIL_LENGTH'),
            source.indexOf('// Signature-only sampling'),
          )
          .trim();
      expect(
        sha256
            .convert(utf8.encode(_neutralLegacySource(legacy, style.id)))
            .toString(),
        _legacyHashes[style.id],
      );
      expect(
        source,
        contains(
          'bool signatureEnabled = uBass != 0.0 || uMid != 0.0 || uTreble != 0.0 || uSeed != 0.0;',
        ),
      );
      expect(
        source,
        contains('color = legacyRecipe(grainDivisor, pulseFactor, original);'),
      );
    });

    test('${style.id}: signature diversity, structure and determinism', () async {
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final fixtures = [
        await testImage(width: 192, height: 144),
        await _scene(),
        await testImage(width: 96, height: 160),
      ];
      addTearDown(() {
        for (final image in fixtures) {
          image.dispose();
        }
      });
      var minSimilarity = 1.0;
      var minDiversity = double.infinity;
      var minSpatial = double.infinity;
      // The photographic scene is mostly saturated or dark, which masks the
      // grain: it keeps a lower floor than the two synthetic fixtures.
      var minSceneDiversity = double.infinity;
      var minSceneSpatial = double.infinity;
      for (final source in fixtures) {
        final isScene = identical(source, fixtures[1]);
        final original = await pixels(source);
        final originalStructure = _thumbnail(
          original,
          source.width,
          source.height,
        );
        // Exact GPU equality for explicit zeros, at active legacy controls too.
        // The source hash above independently locks the historical calculation.
        for (final controls in [
          (0.0, 0.5, 0.0),
          (1.0, 0.0, 1.0),
          (0.4, 1.0, 0.3),
        ]) {
          final implicit = AmbientState(
            noise: controls.$1,
            light: controls.$2,
            motion: controls.$3,
          );
          final explicit = AmbientState(
            noise: controls.$1,
            light: controls.$2,
            motion: controls.$3,
            bass: 0,
            mid: 0,
            treble: 0,
            seed: 0,
            signature: SignatureState.neutral,
          );
          expect(
            await _render(renderer, source, explicit),
            await _render(renderer, source, implicit),
          );
        }
        for (final bands in _bands) {
          final renders = <Uint8List>[];
          for (final seed in _seeds) {
            final state = AmbientState(
              noise: 1,
              motion: 0.7,
              bass: bands.$1,
              mid: bands.$2,
              treble: bands.$3,
              seed: seed,
              signature: _fingerprint,
            );
            final output = await _render(renderer, source, state);
            expect(
              await _render(renderer, source, state),
              output,
              reason: 'Equal frozen inputs must be byte deterministic',
            );
            final similarity = _correlation(
              originalStructure,
              _thumbnail(output, source.width, source.height),
            );
            minSimilarity = math.min(minSimilarity, similarity);
            renders.add(output);
          }
          for (var i = 0; i < renders.length; i++) {
            for (var j = i + 1; j < renders.length; j++) {
              final diversity = difference(renders[i], renders[j]);
              final spatial = _spatialDifference(renders[i], renders[j]);
              if (isScene) {
                minSceneDiversity = math.min(minSceneDiversity, diversity);
                minSceneSpatial = math.min(minSceneSpatial, spatial);
              } else {
                minDiversity = math.min(minDiversity, diversity);
                minSpatial = math.min(minSpatial, spatial);
              }
            }
          }
        }
      }
      // ignore: avoid_print
      print(
        '${style.id}: min correlation64=$minSimilarity; min seed MAE RGB8=$minDiversity; min centered residual=$minSpatial; scene MAE=$minSceneDiversity residual=$minSceneSpatial',
      );
      expect(
        minSimilarity,
        greaterThanOrEqualTo(0.85),
        reason: '${style.id}: recognizability against original',
      );
      expect(
        minDiversity,
        greaterThanOrEqualTo(1.0),
        reason: '${style.id}: RGB8 seed diversity',
      );
      expect(
        minSpatial,
        greaterThanOrEqualTo(0.5),
        reason: '${style.id}: layout diversity, excluding uniform tint',
      );
      expect(minSceneDiversity, greaterThanOrEqualTo(0.1));
      expect(minSceneSpatial, greaterThanOrEqualTo(0.1));
    });

    test(
      '${style.id}: individual bands respond and microtexture stays bounded',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final source = await testImage(width: 192, height: 144);
        addTearDown(source.dispose);
        final baseline = await _render(
          renderer,
          source,
          const AmbientState(noise: 1, seed: 0.37),
        );
        for (final bands in _bands.take(3)) {
          final changed = await _render(
            renderer,
            source,
            AmbientState(
              noise: 1,
              seed: 0.37,
              bass: bands.$1,
              mid: bands.$2,
              treble: bands.$3,
            ),
          );
          expect(
            difference(baseline, changed),
            greaterThan(0.05),
            reason: 'Each band must modify its own recipe',
          );
        }
        for (final configuration in [
          (0.0, 0.0),
          (1.0, 0.0),
          (0.0, 0.37),
          (1.0, 0.37),
        ]) {
          final noise = configuration.$1;
          final seed = configuration.$2;
          final macro = await _render(
            renderer,
            source,
            AmbientState(noise: noise, seed: seed),
          );
          final fingerprints = <Uint8List>[];
          for (final signature in [
            _fingerprint,
            const SignatureState(x: 0.4),
            const SignatureState(y: 0.4),
            const SignatureState(z: 0.4),
            const SignatureState(w: 0.4),
          ]) {
            final micro = await _render(
              renderer,
              source,
              AmbientState(noise: noise, seed: seed, signature: signature),
            );
            expect(micro, isNot(orderedEquals(macro)));
            for (final previous in fingerprints) {
              expect(micro, isNot(orderedEquals(previous)));
            }
            fingerprints.add(micro);
            for (var i = 0; i < macro.length; i++) {
              expect(
                (micro[i] - macro[i]).abs(),
                lessThanOrEqualTo(1),
                reason: 'Fingerprint may only add one RGB8 code',
              );
            }
          }
        }
      },
    );
  }
}
