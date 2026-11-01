import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show pixels;

// Portrait scenes stand in for the phone viewfinder. They are synthetic (no
// photographs are versioned), but reproduce the two cases that matter: a calm
// scene made of broad stripes and a busy one made of sparse sparks.
const _width = 180;
const _height = 400;

Future<ui.Image> _lighthouse() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawPaint(
    ui.Paint()
      ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(0, 400), [
        const ui.Color(0xff1d2c52),
        const ui.Color(0xffd9946a),
      ]),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 330, 180, 70),
    ui.Paint()..color = const ui.Color(0xff202a35),
  );
  for (var i = 0; i < 9; i++) {
    canvas.drawRect(
      ui.Rect.fromLTRB(62, 80.0 + i * 28, 118, 108.0 + i * 28),
      ui.Paint()
        ..color = i.isEven
            ? const ui.Color(0xfff0ebe2)
            : const ui.Color(0xffb02c2a),
    );
  }
  canvas.drawRect(
    const ui.Rect.fromLTWH(54, 62, 72, 18),
    ui.Paint()..color = const ui.Color(0xff2b2b30),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(70, 40, 40, 22),
    ui.Paint()..color = const ui.Color(0xfffff2b0),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_width, _height);
  } finally {
    picture.dispose();
  }
}

ui.Color _hsv(double h) {
  const s = 0.6;
  const v = 1.0;
  const c = v * s;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());
  const m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return ui.Color.fromARGB(
    255,
    ((r + m) * 255).round(),
    ((g + m) * 255).round(),
    ((b + m) * 255).round(),
  );
}

Future<ui.Image> _fireworks() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawPaint(ui.Paint()..color = const ui.Color(0xff05060e));
  final random = math.Random(7);
  for (final centre in const [
    ui.Offset(60, 120),
    ui.Offset(130, 230),
    ui.Offset(70, 320),
  ]) {
    for (var i = 0; i < 40; i++) {
      final angle = i / 40 * 2 * math.pi;
      final length = 18 + random.nextDouble() * 26;
      canvas.drawLine(
        centre,
        centre + ui.Offset(math.cos(angle), math.sin(angle)) * length,
        ui.Paint()
          ..strokeWidth = 1.6
          ..color = _hsv((i * 37) % 360.0),
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_width, _height);
  } finally {
    picture.dispose();
  }
}

// Hard black/white edges (worst case for displacement) and a grey ramp.
Future<ui.Image> _grey({required bool checker}) async {
  const side = 128;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final value = checker
          ? ((x ~/ 4 + y ~/ 4).isEven ? 0 : 255)
          : 65 + (190 * (x + y) / (2 * side - 2)).round();
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()..color = ui.Color.fromARGB(255, value, value, value),
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(side, side);
  } finally {
    picture.dispose();
  }
}

const _levels = <String, AmbientState>{
  'neutral': AmbientState(seed: 0.37),
  'lively': AmbientState(
    noise: 0.6,
    light: 0.6,
    motion: 0.35,
    bass: 0.7,
    mid: 0.55,
    treble: 0.35,
    seed: 0.37,
  ),
  'intense': AmbientState(
    noise: 0.9,
    light: 0.5,
    motion: 0.65,
    bass: 0.9,
    mid: 0.75,
    treble: 0.6,
    seed: 0.37,
  ),
  'max': AmbientState(
    noise: 1,
    light: 0.5,
    motion: 1,
    bass: 1,
    mid: 1,
    treble: 1,
    seed: 0.37,
  ),
};

// Mean absolute RGB8 difference, and the share of pixels that moved by more
// than 24 codes in any channel (a change a viewer can actually see).
({double mae, double visible}) _metrics(Uint8List a, Uint8List b) {
  var sum = 0;
  var visible = 0;
  for (var i = 0; i < a.length; i += 4) {
    var peak = 0;
    for (var c = 0; c < 3; c++) {
      final d = (a[i + c] - b[i + c]).abs();
      sum += d;
      peak = math.max(peak, d);
    }
    if (peak > 24) visible++;
  }
  return (mae: sum / (a.length * 0.75), visible: visible / (a.length / 4));
}

// Damage and retention caps measured on the real render: share of pixels that
// moved by more than 96 codes in any channel, share of bright pixels turned
// dark, and the largest single-channel change.
({double corrupted, double dark, int peak}) _caps(
  Uint8List clean,
  Uint8List output,
) {
  var corrupted = 0;
  var dark = 0;
  var peak = 0;
  for (var i = 0; i < clean.length; i += 4) {
    var local = 0;
    for (var c = 0; c < 3; c++) {
      local = math.max(local, (clean[i + c] - output[i + c]).abs());
    }
    if (local > 96) corrupted++;
    peak = math.max(peak, local);
    double luma(Uint8List d) =>
        d[i] * 0.2126 + d[i + 1] * 0.7152 + d[i + 2] * 0.0722;
    if (luma(clean) > 64 && luma(output) < 16) dark++;
  }
  final count = clean.length / 4;
  return (corrupted: corrupted / count, dark: dark / count, peak: peak);
}

// Minimum visibility, in mean absolute RGB8 difference against the original,
// that Static, Prism and Tape must keep on a calm and a busy scene. Measured before
// the visibility change: Prism 0.94 and Static 0.81 on the calm scene; Tape
// 0.81 (intense) and 1.17 (maximum).
const _minimumMae = 3.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in kStyles.where(
    (s) => {'static', 'prism', 'tape'}.contains(s.id),
  )) {
    test(
      '${style.id}: recognisable at lively, intense and maximum controls',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final scenes = {
          'lighthouse': await _lighthouse(),
          'fireworks': await _fireworks(),
        };
        addTearDown(() {
          for (final image in scenes.values) {
            image.dispose();
          }
        });
        for (final scene in scenes.entries) {
          final original = await pixels(scene.value);
          for (final level in _levels.entries) {
            var mae = 0.0;
            var visible = 0.0;
            const times = [0.5, 1.25, 2.0, 3.3];
            for (final time in times) {
              final output = await renderer.renderToImage(
                scene.value,
                ambient: level.value,
                time: time,
              );
              try {
                final m = _metrics(original, await pixels(output));
                mae += m.mae / times.length;
                visible += m.visible / times.length;
              } finally {
                output.dispose();
              }
            }
            // ignore: avoid_print
            print(
              'VIS ${style.id} ${scene.key} ${level.key}: '
              'MAE=${mae.toStringAsFixed(2)} '
              'visible>24=${(visible * 100).toStringAsFixed(2)}%',
            );
            if (level.key == 'neutral') {
              expect(mae, lessThanOrEqualTo(1), reason: 'neutral is identity');
            } else {
              expect(
                mae,
                greaterThanOrEqualTo(_minimumMae),
                reason:
                    '${style.id} ${scene.key} ${level.key} must stay visible',
              );
            }
          }
        }
      },
    );

    test('${style.id}: visibility stays inside the damage and retention caps', () async {
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final sources = {
        'checker': await _grey(checker: true),
        'ramp': await _grey(checker: false),
        'lighthouse': await _lighthouse(),
        'fireworks': await _fireworks(),
      };
      addTearDown(() {
        for (final image in sources.values) {
          image.dispose();
        }
      });
      const still = AmbientState(
        noise: 1,
        bass: 1,
        mid: 1,
        treble: 1,
        seed: 0.37,
      );
      final states = {
        for (final entry in _levels.entries)
          if (entry.key != 'neutral') entry.key: entry.value,
        'max-still': still,
      };
      var worstCorrupted = 0.0;
      var worstDark = 0.0;
      var worstPeak = 0;
      for (final source in sources.entries) {
        final clean = await pixels(source.value);
        for (final state in states.entries) {
          for (final time in const [0.5, 1.25, 2.0, 3.3, 17.3]) {
            final output = await renderer.renderToImage(
              source.value,
              ambient: state.value,
              time: time,
            );
            try {
              final caps = _caps(clean, await pixels(output));
              worstCorrupted = math.max(worstCorrupted, caps.corrupted);
              worstDark = math.max(worstDark, caps.dark);
              worstPeak = math.max(worstPeak, caps.peak);
            } finally {
              output.dispose();
            }
          }
        }
      }
      // ignore: avoid_print
      print(
        'CAP ${style.id}: damaged>96=${(worstCorrupted * 100).toStringAsFixed(2)}% '
        'dark=${(worstDark * 100).toStringAsFixed(2)}% peak=$worstPeak',
      );
      expect(worstCorrupted, lessThanOrEqualTo(0.20), reason: 'damaged area');
      expect(worstDark, lessThan(0.03), reason: 'introduced dark pixels');
      // 45% of the original always survives: 0.55 * 255 = 140.25, plus the
      // 1/255 fingerprint rounding that the renderer test fixtures allow.
      expect(worstPeak, lessThanOrEqualTo(142), reason: 'retention floor');
    });
  }
}
