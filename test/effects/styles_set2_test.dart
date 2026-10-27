import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;

const _ids = {'bleed', 'kaleido', 'mosaic'};
final _styles = kRegisteredStyles.where((style) => _ids.contains(style.id));

double _luma(Uint8List data, int i) =>
    data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;

double _mean(Uint8List data, {int? channel}) {
  var sum = 0.0;
  for (var i = 0; i < data.length; i += 4) {
    sum += channel == null ? _luma(data, i) : data[i + channel];
  }
  return sum / (data.length / 4);
}

double _variance(Uint8List data) {
  final mean = _mean(data);
  var sum = 0.0;
  for (var i = 0; i < data.length; i += 4) {
    sum += math.pow(_luma(data, i) - mean, 2);
  }
  return sum / (data.length / 4);
}

double _correlation(Uint8List a, Uint8List b) {
  final meanA = _mean(a);
  final meanB = _mean(b);
  var covariance = 0.0;
  var varianceA = 0.0;
  var varianceB = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    final x = _luma(a, i) - meanA;
    final y = _luma(b, i) - meanB;
    covariance += x * y;
    varianceA += x * x;
    varianceB += y * y;
  }
  return covariance / math.sqrt(varianceA * varianceB);
}

Future<Uint8List> _render(
  EffectRenderer renderer,
  ui.Image source,
  AmbientState state, {
  double time = 1.25,
}) async {
  final output = await renderer.renderToImage(
    source,
    ambient: state,
    time: time,
  );
  try {
    // Inspect float output BEFORE conversion to bytes: RGBA8 hides NaN.
    final data = (await output.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    final floats = data.buffer.asFloat32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    var valid = true;
    var opaque = true;
    for (var i = 0; i < floats.length; i++) {
      valid &= floats[i].isFinite && floats[i] >= 0 && floats[i] <= 1;
      if (i % 4 == 3) opaque &= floats[i] == 1;
    }
    expect(valid, isTrue, reason: 'Finite, bounded float output');
    expect(opaque, isTrue, reason: 'Alpha must be exactly one');
    return await pixels(output);
  } finally {
    output.dispose();
  }
}

Future<ui.Image> _ramp({bool vertical = false}) async {
  const side = 128;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var i = 0; i < side; i++) {
    final value = (255 * i / (side - 1)).round();
    canvas.drawRect(
      vertical
          ? ui.Rect.fromLTWH(0, i.toDouble(), side.toDouble(), 1)
          : ui.Rect.fromLTWH(i.toDouble(), 0, 1, side.toDouble()),
      ui.Paint()..color = ui.Color.fromARGB(255, value, value, value),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(side, side);
  } finally {
    picture.dispose();
  }
}

// A spatially coherent scene complements the deliberately adversarial,
// high-frequency RGB fixture: sky, sun, hills, a roof, door and windows.
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

  for (final style in _styles) {
    group(style.id, () {
      late EffectRenderer renderer;
      late ui.Image source;
      late Uint8List clean;

      setUp(() async {
        renderer = await EffectRenderer.load(style);
        source = await testImage(width: 128, height: 96);
        clean = await pixels(source);
      });
      tearDown(() {
        renderer.dispose();
        source.dispose();
      });

      test('neutral input preserves the image, for any seed/time', () async {
        for (final seed in [0.0, 0.37, 1.0]) {
          final rendered = await _render(
            renderer,
            source,
            AmbientState(seed: seed),
            time: seed * 1000000,
          );
          expect(difference(clean, rendered), lessThanOrEqualTo(0.1));
        }
      });

      test('noise grows by at least 30 percent at each step', () async {
        final distances = <double>[];
        for (final noise in [0.25, 0.5, 1.0]) {
          distances.add(
            difference(
              clean,
              await _render(renderer, source, AmbientState(noise: noise)),
            ),
          );
        }
        expect(distances.first, greaterThan(1));
        expect(distances[1], greaterThanOrEqualTo(distances[0] * 1.3));
        expect(distances[2], greaterThanOrEqualTo(distances[1] * 1.3));
        // ignore: avoid_print
        print('${style.id}: noise MAD=$distances');
      });

      test(
        'light alone changes colour balance and brightness variance',
        () async {
          final dark = await _render(
            renderer,
            source,
            const AmbientState(light: 0.1),
          );
          final bright = await _render(
            renderer,
            source,
            const AmbientState(light: 0.9),
          );
          expect(difference(dark, bright), greaterThan(3));
          final balanceDark = _mean(dark, channel: 0) - _mean(dark, channel: 2);
          final balanceBright =
              _mean(bright, channel: 0) - _mean(bright, channel: 2);
          expect((balanceBright - balanceDark).abs(), greaterThan(3));
          final varianceChange = (_variance(bright) - _variance(dark)).abs();
          expect(varianceChange, greaterThan(_variance(clean) * 0.02));
        },
      );

      test('motion transports the gradient along both signed axes', () async {
        for (final vertical in [false, true]) {
          final ramp = await _ramp(vertical: vertical);
          try {
            final plus = await _render(
              renderer,
              ramp,
              AmbientState(
                motion: 1,
                motionDirX: vertical ? 0 : 1,
                motionDirY: vertical ? 1 : 0,
              ),
            );
            final minus = await _render(
              renderer,
              ramp,
              AmbientState(
                motion: 1,
                motionDirX: vertical ? 0 : -1,
                motionDirY: vertical ? -1 : 0,
              ),
            );
            final orthogonal = await _render(
              renderer,
              ramp,
              AmbientState(
                motion: 1,
                motionDirX: vertical ? 1 : 0,
                motionDirY: vertical ? 0 : 1,
              ),
            );
            final neutral = await pixels(ramp);
            expect(difference(neutral, orthogonal), lessThan(0.2));
            expect(difference(plus, minus), greaterThan(2));
            expect(
              vertical
                  ? _mean(plus) - _mean(minus)
                  : _mean(minus) - _mean(plus),
              greaterThan(2),
            );
          } finally {
            ramp.dispose();
          }
        }
      });

      test('each spectral band works alone and has its own response', () async {
        final bands = <Uint8List>[];
        for (final state in const [
          AmbientState(bass: 1),
          AmbientState(mid: 1),
          AmbientState(treble: 1),
        ]) {
          final rendered = await _render(renderer, source, state);
          expect(difference(clean, rendered), greaterThan(1));
          bands.add(rendered);
        }
        for (var a = 0; a < bands.length; a++) {
          for (var b = a + 1; b < bands.length; b++) {
            expect(difference(bands[a], bands[b]), greaterThan(1));
          }
        }
      });

      test('seed varies the print reproducibly', () async {
        const state = AmbientState(
          noise: 0.8,
          bass: 0.5,
          mid: 0.5,
          treble: 0.5,
        );
        final first = await _render(renderer, source, state.withSeed(0.17));
        final repeat = await _render(renderer, source, state.withSeed(0.17));
        final other = await _render(renderer, source, state.withSeed(0.81));
        expect(repeat, orderedEquals(first));
        expect(difference(first, other), greaterThan(1));
        final zero = await _render(renderer, source, state.withSeed(0));
        final one = await _render(renderer, source, state.withSeed(1));
        expect(difference(zero, one), greaterThan(1));
      });

      test(
        'noise one retains texture and scene correlation above 0.70',
        () async {
          final scene = await _scene();
          try {
            for (final fixture in [source, scene]) {
              final original = await pixels(fixture);
              for (final seed in [0.0, 0.43, 1.0]) {
                final loud = await _render(
                  renderer,
                  fixture,
                  AmbientState(noise: 1, seed: seed),
                );
                final correlation = _correlation(original, loud);
                expect(correlation, greaterThan(0.70));
                // ignore: avoid_print
                print(
                  '${style.id}: ${fixture.width}px seed=$seed r=$correlation',
                );
                if (style.id == 'kaleido') {
                  // At moderate noise, an actual centre disc is intact, rather
                  // than merely relying on a high whole-image correlation.
                  final moderate = await _render(
                    renderer,
                    fixture,
                    AmbientState(noise: 0.5, seed: seed),
                  );
                  for (
                    var y = fixture.height ~/ 2 - 4;
                    y < fixture.height ~/ 2 + 4;
                    y++
                  ) {
                    for (
                      var x = fixture.width ~/ 2 - 4;
                      x < fixture.width ~/ 2 + 4;
                      x++
                    ) {
                      final i = (y * fixture.width + x) * 4;
                      for (var c = 0; c < 3; c++) {
                        expect(
                          (moderate[i + c] - original[i + c]).abs(),
                          lessThanOrEqualTo(1),
                        );
                      }
                    }
                  }
                }
              }
            }
          } finally {
            scene.dispose();
          }
        },
      );

      test(
        'local brightness lift stays below 20 percent with no flat blocks',
        () async {
          for (final time in [0.0, 1.25, 17.3, 1000000.0]) {
            final output = await _render(
              renderer,
              source,
              const AmbientState(
                noise: 1,
                light: 0.9,
                motion: 1,
                bass: 1,
                mid: 1,
                treble: 1,
                seed: 0.71,
              ),
              time: time,
            );
            for (var i = 0; i < output.length; i += 4) {
              expect(
                _luma(output, i),
                lessThanOrEqualTo(_luma(clean, i) * 1.2 + 1),
              );
            }
            var flat = 0;
            for (var y = 0; y < source.height - 1; y++) {
              for (var x = 0; x < source.width - 1; x++) {
                final i = (y * source.width + x) * 4;
                final offsets = [
                  i,
                  i + 4,
                  i + source.width * 4,
                  i + source.width * 4 + 4,
                ];
                var range = 0;
                for (var c = 0; c < 3; c++) {
                  final values = offsets.map((offset) => output[offset + c]);
                  range = math.max(
                    range,
                    values.reduce(math.max) - values.reduce(math.min),
                  );
                }
                if (range <= 1) flat++;
              }
            }
            expect(
              flat,
              0,
              reason: 'No newly flat 2x2 blocks on textured input',
            );
          }
        },
      );

      if (style.id == 'kaleido') {
        test(
          'small motion changes stay continuous late in a session',
          () async {
            for (final time in [600.0, 3600.0, 36000.0]) {
              for (final motion in [0.2, 0.5, 0.8]) {
                final frames = <Uint8List>[];
                for (final value in [motion, motion + 0.01]) {
                  frames.add(
                    await _render(
                      renderer,
                      source,
                      AmbientState(
                        noise: 0.7,
                        motion: value,
                        bass: 0.4,
                        mid: 0.6,
                        treble: 0.5,
                        seed: 0.37,
                        motionDirX: 0.6,
                        motionDirY: 0.8,
                      ),
                      time: time,
                    ),
                  );
                }
                expect(
                  difference(frames[0], frames[1]),
                  lessThan(1),
                  reason:
                      'Motion delta 0.01 must not pop at ${time}s ($motion)',
                );
              }
            }
          },
        );
      }

      test(
        'every live uniform is continuous, including wedge boundaries',
        () async {
          const base = AmbientState(
            noise: 0.5,
            motion: 0.5,
            bass: 0.5,
            mid: 0.5,
            treble: 0.5,
            seed: 0.5,
          );
          final original = await _render(renderer, source, base);
          for (var field = 0; field < 10; field++) {
            const delta = 0.00001;
            final changed = AmbientState(
              noise: 0.5 + (field == 0 ? delta : 0),
              light: 0.5 + (field == 1 ? delta : 0),
              motion: 0.5 + (field == 2 ? delta : 0),
              bass: 0.5 + (field == 3 ? delta : 0),
              mid: 0.5 + (field == 4 ? delta : 0),
              treble: 0.5 + (field == 5 ? delta : 0),
              seed: 0.5 + (field == 6 ? delta : 0),
              motionDirX: 1 + (field == 7 ? delta : 0),
              motionDirY: field == 8 ? delta : 0,
            );
            expect(
              difference(
                original,
                await _render(
                  renderer,
                  source,
                  changed,
                  time: 1.25 + (field == 9 ? delta : 0),
                ),
              ),
              lessThan(0.25),
              reason: 'Uniform $field must not pop',
            );
          }
          for (final mid in [0.25, 0.5, 0.75]) {
            final before = await _render(
              renderer,
              source,
              AmbientState(noise: 0.7, mid: mid - 0.00001),
            );
            final after = await _render(
              renderer,
              source,
              AmbientState(noise: 0.7, mid: mid + 0.00001),
            );
            expect(difference(before, after), lessThan(0.25));
          }
          for (final time in [0.0, 1000000.0]) {
            for (final light in [0.0, 1.0]) {
              await _render(
                renderer,
                source,
                AmbientState(
                  noise: 1,
                  motion: 1,
                  light: light,
                  bass: 1,
                  mid: 1,
                  treble: 1,
                  seed: 1,
                  motionDirX: -0.6,
                  motionDirY: 0.8,
                ),
                time: time,
              );
            }
          }
        },
      );
    });
  }

  test(
    'set two is distinct from each other and the six existing styles',
    () async {
      final source = await testImage(width: 128, height: 96);
      addTearDown(source.dispose);
      final results = <String, Uint8List>{};
      for (final style in [...kStyles, ..._styles]) {
        final renderer = await EffectRenderer.load(style);
        try {
          results[style.id] = await _render(
            renderer,
            source,
            const AmbientState(
              noise: 0.8,
              light: 0.3,
              motion: 0.5,
              bass: 0.4,
              mid: 0.6,
              treble: 0.7,
              seed: 0.37,
            ),
          );
        } finally {
          renderer.dispose();
        }
      }
      for (final id in _ids) {
        for (final other in results.keys.where((other) => other != id)) {
          expect(
            difference(results[id]!, results[other]!),
            greaterThan(5),
            reason: '$id and $other need distinct visual identities',
          );
        }
      }
    },
  );

  if (Platform.environment['STYLE_SET2_PREVIEWS'] == '1') {
    test('write optional real-shader preview sheets', () async {
      final source = await _scene();
      try {
        for (final style in _styles) {
          final renderer = await EffectRenderer.load(style);
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          try {
            final states = [
              const AmbientState(),
              for (final n in [0.25, 0.5, 1.0])
                AmbientState(noise: n, seed: 0.37),
              const AmbientState(light: 0.1),
              const AmbientState(light: 0.9),
              const AmbientState(bass: 1),
              const AmbientState(mid: 1),
              const AmbientState(treble: 1),
            ];
            for (var i = 0; i < states.length; i++) {
              final image = await renderer.renderToImage(
                source,
                ambient: states[i],
                time: 1.25,
              );
              canvas.drawImage(
                image,
                ui.Offset((i % 3) * 256.0, (i ~/ 3) * 192.0),
                ui.Paint(),
              );
              image.dispose();
            }
          } finally {
            renderer.dispose();
          }
          final picture = recorder.endRecording();
          final sheet = await picture.toImage(768, 576);
          picture.dispose();
          try {
            final png = (await sheet.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final file = File('build/style-previews/${style.id}-set2.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png.buffer.asUint8List());
          } finally {
            sheet.dispose();
          }
        }
      } finally {
        source.dispose();
      }
    });
  }
}
