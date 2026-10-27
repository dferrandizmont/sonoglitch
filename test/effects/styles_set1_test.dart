import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;

const _ids = ['datamosh', 'chladni', 'risograph'];
final _styles = _ids.map(
  (id) => kRegisteredStyles.singleWhere((style) => style.id == id),
);

double _luma(Uint8List data, int i) =>
    data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;

(double, double) _statistics(Uint8List data) {
  var balance = 0.0;
  var sum = 0.0;
  var square = 0.0;
  final count = data.length ~/ 4;
  for (var i = 0; i < data.length; i += 4) {
    balance += data[i] - data[i + 2];
    final y = _luma(data, i);
    sum += y;
    square += y * y;
  }
  return (balance / count, square / count - math.pow(sum / count, 2));
}

Future<ui.Image> _gradient(
  int width,
  int height, {
  bool vertical = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = (32 + 190 * (vertical ? y / (height - 1) : x / (width - 1)))
          .round();
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
    final raw = (await output.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    final floats = raw.buffer.asFloat32List(
      raw.offsetInBytes,
      raw.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    var finite = true;
    var opaque = true;
    var inRange = true;
    for (var i = 0; i < floats.length; i++) {
      finite = finite && floats[i].isFinite;
      inRange = inRange && floats[i] >= 0 && floats[i] <= 1;
      if (i % 4 == 3) opaque = opaque && floats[i] == 1;
    }
    expect(
      finite,
      isTrue,
      reason: 'Real shader output must not contain NaN/Inf',
    );
    expect(inRange, isTrue, reason: 'RGB output must remain displayable');
    expect(opaque, isTrue, reason: 'Every rendered alpha must equal one');
    return await pixels(output);
  } finally {
    output.dispose();
  }
}

double _meanInterior(Uint8List data, int width, int height) {
  var sum = 0.0;
  var count = 0;
  for (var y = height ~/ 5; y < height * 4 ~/ 5; y++) {
    for (var x = width ~/ 5; x < width * 4 ~/ 5; x++) {
      sum += _luma(data, (y * width + x) * 4);
      count++;
    }
  }
  return sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final style in _styles) {
    group(style.id, () {
      late EffectRenderer renderer;
      late ui.Image source;
      setUp(() async {
        renderer = await EffectRenderer.load(style);
        source = await testImage(width: 192, height: 144);
      });
      tearDown(() {
        renderer.dispose();
        source.dispose();
      });

      test('neutral is unchanged, including seed and time extremes', () async {
        final clean = await pixels(source);
        for (final seed in [0.0, 0.37, 1.0]) {
          for (final time in [0.0, 1000000.0]) {
            expect(
              difference(
                clean,
                await _render(
                  renderer,
                  source,
                  AmbientState(seed: seed),
                  time: time,
                ),
              ),
              lessThanOrEqualTo(0.1),
            );
          }
        }
      });

      test('noise steps each grow by at least thirty percent', () async {
        final clean = await pixels(source);
        final changes = <double>[];
        for (final noise in [0.25, 0.5, 1.0]) {
          changes.add(
            difference(
              clean,
              await _render(
                renderer,
                source,
                AmbientState(noise: noise, seed: 0.37),
              ),
            ),
          );
        }
        expect(changes[0], greaterThan(0.15));
        expect(changes[1], greaterThan(changes[0] * 1.3));
        expect(changes[2], greaterThan(changes[1] * 1.3));
        // ignore: avoid_print
        print('${style.id} noise MAD: $changes');
      });

      test(
        'light independently changes ink balance and brightness variance',
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
          final a = _statistics(dark);
          final b = _statistics(bright);
          expect(difference(dark, bright), greaterThan(2));
          expect((a.$1 - b.$1).abs(), greaterThan(3));
          expect((a.$2 - b.$2).abs() / math.max(a.$2, b.$2), greaterThan(0.01));
        },
      );

      test('motion transports the gradient along both signed axes', () async {
        for (final size in [(160, 96), (96, 160)]) {
          for (final vertical in [false, true]) {
            final ramp = await _gradient(size.$1, size.$2, vertical: vertical);
            try {
              final clean = _meanInterior(await pixels(ramp), size.$1, size.$2);
              final means = <double>[];
              for (final sign in [-1.0, 1.0]) {
                final moved = await _render(
                  renderer,
                  ramp,
                  AmbientState(
                    motion: 1,
                    motionDirX: vertical ? 0 : sign,
                    motionDirY: vertical ? sign : 0,
                  ),
                );
                means.add(_meanInterior(moved, size.$1, size.$2));
              }
              // Sensor axes are X right, Y up; texture V increases downwards.
              final darker = means[vertical ? 0 : 1];
              final brighter = means[vertical ? 1 : 0];
              expect(darker, lessThan(clean - 0.4));
              expect(brighter, greaterThan(clean + 0.4));
              expect(brighter - darker, greaterThan(1));
            } finally {
              ramp.dispose();
            }
          }
        }
      });

      test('each band acts on its own and bass differs from treble', () async {
        final none = await _render(renderer, source, const AmbientState());
        final bands = <Uint8List>[];
        for (final state in [
          const AmbientState(bass: 1, seed: 0.37),
          const AmbientState(mid: 1, seed: 0.37),
          const AmbientState(treble: 1, seed: 0.37),
        ]) {
          bands.add(await _render(renderer, source, state));
          expect(difference(none, bands.last), greaterThan(0.5));
        }
        for (var i = 0; i < bands.length; i++) {
          for (var j = i + 1; j < bands.length; j++) {
            expect(difference(bands[i], bands[j]), greaterThan(0.5));
          }
        }
      });

      test('seed gives a repeatable and distinct photo', () async {
        const first = AmbientState(
          noise: 0.8,
          bass: 0.6,
          mid: 0.4,
          treble: 0.5,
          seed: 0.17,
        );
        const second = AmbientState(
          noise: 0.8,
          bass: 0.6,
          mid: 0.4,
          treble: 0.5,
          seed: 0.81,
        );
        final a = await _render(renderer, source, first);
        final b = await _render(renderer, source, second);
        expect(difference(a, b), greaterThan(0.5));
        expect(await _render(renderer, source, first), orderedEquals(a));
      });

      test('noise alone corrupts at most twenty percent without flash or flat blocks', () async {
        final clean = await pixels(source);
        var largestFraction = 0.0;
        for (final seed in [0.0, 0.37, 0.81]) {
          final loud = await _render(
            renderer,
            source,
            AmbientState(noise: 1, seed: seed),
          );
          var changed = 0;
          var newFlat = 0;
          for (var y = 0; y < source.height; y++) {
            for (var x = 0; x < source.width; x++) {
              final i = (y * source.width + x) * 4;
              if (List.generate(
                    3,
                    (c) => (loud[i + c] - clean[i + c]).abs(),
                  ).reduce(math.max) >
                  1) {
                changed++;
              }
              expect(
                _luma(loud, i),
                lessThanOrEqualTo(_luma(clean, i) * 1.2 + 1),
              );
              if (x == source.width - 1 || y == source.height - 1) continue;
              final offsets = [
                i,
                i + 4,
                i + source.width * 4,
                i + source.width * 4 + 4,
              ];
              var before = 0;
              var after = 0;
              for (var c = 0; c < 3; c++) {
                final a = offsets.map((j) => clean[j + c]);
                final b = offsets.map((j) => loud[j + c]);
                before = math.max(
                  before,
                  a.reduce(math.max) - a.reduce(math.min),
                );
                after = math.max(
                  after,
                  b.reduce(math.max) - b.reduce(math.min),
                );
              }
              if (before > 24 && after <= 1) newFlat++;
            }
          }
          final fraction = changed / (source.width * source.height);
          largestFraction = math.max(largestFraction, fraction);
          expect(fraction, lessThanOrEqualTo(0.20));
          expect(newFlat, 0);
        }
        // ignore: avoid_print
        print('${style.id} maximum corruption area: $largestFraction');
      });

      test(
        'sampling footprint is within five percent, with all signals high',
        () async {
          // A step edge is compared against identically processed constant fields:
          // any difference beyond the bound must have come from an illegal tap.
          for (final vertical in [false, true]) {
            const width = 128;
            const height = 96;
            Future<ui.Image> fixture(int kind) async {
              final recorder = ui.PictureRecorder();
              final canvas = ui.Canvas(recorder);
              canvas.drawPaint(ui.Paint()..color = const ui.Color(0xff303030));
              if (kind != 0) {
                canvas.drawRect(
                  kind == 2
                      ? const ui.Rect.fromLTWH(0, 0, 128, 96)
                      : (vertical
                            ? const ui.Rect.fromLTWH(0, 48, 128, 48)
                            : const ui.Rect.fromLTWH(64, 0, 64, 96)),
                  ui.Paint()..color = const ui.Color(0xffd0d0d0),
                );
              }
              final picture = recorder.endRecording();
              try {
                return await picture.toImage(width, height);
              } finally {
                picture.dispose();
              }
            }

            final fixtures = [
              await fixture(0),
              await fixture(1),
              await fixture(2),
            ];
            try {
              for (final time in [0.0, 17.3, 1000000.0]) {
                const state = AmbientState(
                  noise: 1,
                  motion: 1,
                  motionDirX: 0.6,
                  motionDirY: 0.8,
                  bass: 1,
                  mid: 1,
                  treble: 1,
                  seed: 0.37,
                );
                final results = <Uint8List>[];
                for (final image in fixtures) {
                  results.add(
                    await _render(renderer, image, state, time: time),
                  );
                }
                var maximum = 0;
                for (var y = 0; y < height; y++) {
                  for (var x = 0; x < width; x++) {
                    final distance = vertical
                        ? y + 0.5 - height / 2
                        : x + 0.5 - width / 2;
                    if (distance.abs() <= width * 0.05 + 1) continue;
                    final i = (y * width + x) * 4;
                    final reference = distance < 0 ? results[0] : results[2];
                    for (var c = 0; c < 3; c++) {
                      maximum = math.max(
                        maximum,
                        (results[1][i + c] - reference[i + c]).abs(),
                      );
                    }
                  }
                }
                expect(maximum, lessThanOrEqualTo(1));
              }
            } finally {
              for (final image in fixtures) {
                image.dispose();
              }
            }
          }
        },
      );

      test('all uniforms remain continuous and finite at extremes', () async {
        const base = AmbientState(
          noise: 0.5,
          light: 0.4,
          motion: 0.5,
          motionDirX: 0.6,
          motionDirY: 0.8,
          bass: 0.4,
          mid: 0.6,
          treble: 0.5,
          seed: 0.37,
        );
        final reference = await _render(renderer, source, base);
        const epsilon = 0.00001;
        for (var control = 0; control < 9; control++) {
          final state = AmbientState(
            noise: base.noise + (control == 0 ? epsilon : 0),
            light: base.light + (control == 1 ? epsilon : 0),
            motion: base.motion + (control == 2 ? epsilon : 0),
            motionDirX: base.motionDirX + (control == 3 ? epsilon : 0),
            motionDirY: base.motionDirY + (control == 4 ? epsilon : 0),
            bass: base.bass + (control == 5 ? epsilon : 0),
            mid: base.mid + (control == 6 ? epsilon : 0),
            treble: base.treble + (control == 7 ? epsilon : 0),
            seed: base.seed + (control == 8 ? epsilon : 0),
          );
          expect(
            difference(reference, await _render(renderer, source, state)),
            lessThan(0.15),
            reason: 'control $control',
          );
        }
        expect(
          difference(
            reference,
            await _render(renderer, source, base, time: 1.25 + epsilon),
          ),
          lessThan(0.15),
        );
        for (final light in [0.0, 1.0]) {
          for (final time in [0.0, 1000000.0]) {
            await _render(
              renderer,
              source,
              AmbientState(
                noise: 1,
                light: light,
                motion: 1,
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
      });
    });
  }

  test('set one has separate identities from each other and the six existing looks', () async {
    final source = await testImage(width: 192, height: 144);
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
            bass: 0.5,
            mid: 0.4,
            treble: 0.6,
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
          greaterThan(1.5),
          reason: '$id vs $other',
        );
      }
    }
  });
}
