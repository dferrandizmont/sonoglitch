import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;

const _ids = {'phosphor', 'ripple', 'thermal'};
final _styles = kStyles.where((style) => _ids.contains(style.id));

double _luma(Uint8List data, int i) =>
    data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;

Future<ui.Image> _ramp(int width, int height, {bool vertical = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (255 * (vertical ? y / (height - 1) : x / (width - 1))).round();
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()..color = ui.Color.fromARGB(255, v, v, v),
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
  AmbientState ambient, {
  double time = 1.25,
}) async {
  final image = await renderer.renderToImage(
    source,
    ambient: ambient,
    time: time,
  );
  try {
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    final values = data.buffer.asFloat32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    for (var i = 0; i < values.length; i++) {
      expect(values[i].isFinite, isTrue, reason: 'No NaN or infinity');
      expect(values[i], inInclusiveRange(0.0, 1.0));
      if (i % 4 == 3) expect(values[i], 1.0);
    }
    return await pixels(image);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _scene({int? solid, bool vertical = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (solid != null || vertical) {
    final v = solid ?? 0;
    canvas.drawPaint(ui.Paint()..color = ui.Color.fromARGB(255, v, v, v));
    if (vertical) {
      canvas.drawRect(
        const ui.Rect.fromLTWH(128, 0, 128, 192),
        ui.Paint()..color = const ui.Color(0xffffffff),
      );
    }
  } else {
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 256, 192),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(0, 192),
          [const ui.Color(0xff2c577a), const ui.Color(0xffe5ccb3)],
        ),
    );
    canvas.drawCircle(
      const ui.Offset(202, 39),
      21,
      ui.Paint()..color = const ui.Color(0xffffdf91),
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(0, 125)
        ..lineTo(90, 70)
        ..lineTo(155, 122)
        ..lineTo(230, 85)
        ..lineTo(256, 140)
        ..lineTo(256, 192)
        ..lineTo(0, 192)
        ..close(),
      ui.Paint()..color = const ui.Color(0xff34564b),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(82, 112, 94, 67),
      ui.Paint()..color = const ui.Color(0xffd6a07a),
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(73, 114)
        ..lineTo(129, 76)
        ..lineTo(184, 114)
        ..close(),
      ui.Paint()..color = const ui.Color(0xff703b35),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(120, 139, 20, 40),
      ui.Paint()..color = const ui.Color(0xff384452),
    );
    for (final x in [91.0, 149.0]) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x, 127, 14, 16),
        ui.Paint()..color = const ui.Color(0xffc8dce6),
      );
    }
    canvas.drawRect(
      const ui.Rect.fromLTWH(34, 110, 8, 72),
      ui.Paint()..color = const ui.Color(0xff54402f),
    );
    canvas.drawOval(
      const ui.Rect.fromLTWH(12, 53, 53, 81),
      ui.Paint()..color = const ui.Color(0xff233d37),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(256, 192);
  } finally {
    picture.dispose();
  }
}

Future<void> _writePreviews() async {
  final source = await _scene();
  try {
    for (final style in _styles) {
      final renderer = await EffectRenderer.load(style);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // Rows: noise, light, motion. Columns: low, neutral/mid, high.
      // Avoid test-font text: Flutter's Ahem font draws labels as solid blocks.
      final samples = [
        for (final n in [0.1, 0.5, 1.0]) AmbientState(noise: n),
        for (final l in [0.1, 0.5, 0.9]) AmbientState(light: l),
        for (final m in [0.1, 0.5, 1.0]) AmbientState(motion: m),
      ];
      try {
        for (var i = 0; i < samples.length; i++) {
          final image = await renderer.renderToImage(
            source,
            ambient: samples[i],
            time: 1.25,
          );
          try {
            final origin = ui.Offset((i % 3) * 256.0, (i ~/ 3) * 216.0);
            canvas.drawImage(image, origin, ui.Paint());
          } finally {
            image.dispose();
          }
        }
      } finally {
        renderer.dispose();
      }
      final picture = recorder.endRecording();
      final sheet = await picture.toImage(768, 648);
      picture.dispose();
      try {
        final png = (await sheet.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('build/style-previews/${style.id}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png.buffer.asUint8List());
      } finally {
        sheet.dispose();
      }
    }
  } finally {
    source.dispose();
  }
}

// Reuse the existing coherent fixture without duplicating its geometry.
Future<ui.Image> sig2bScene() => _scene();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.environment['STYLE_PREVIEWS'] == '1') {
    test('write optional real-shader visual review sheets', _writePreviews);
  }

  test('new shaders retain the current ABI and are bundled once', () {
    final declarations = RegExp(r'uniform\s+\w+\s+\w+\s*;');
    final current = declarations
        .allMatches(File('shaders/static.frag').readAsStringSync())
        .map((match) => match[0])
        .toList();
    final manifest = File('pubspec.yaml').readAsStringSync();
    for (final style in _styles) {
      final shader = File(style.shaderAsset).readAsStringSync();
      expect(declarations.allMatches(shader).map((match) => match[0]), current);
      expect(shader, startsWith('#version 460 core'));
      expect(shader, contains('#include <flutter/runtime_effect.glsl>'));
      expect(
        RegExp(RegExp.escape('- ${style.shaderAsset}')).allMatches(manifest),
        hasLength(1),
      );
    }
    // Family ordering now interleaves these with the six neutral placeholders.
    expect(_styles.map((style) => style.id), _ids.toList());
  });

  for (final style in _styles) {
    test(
      '${style.id} keeps the entire sampling footprint within five percent',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final edge = await _scene(vertical: true);
        final black = await _scene(solid: 0);
        final white = await _scene(solid: 255);
        addTearDown(edge.dispose);
        addTearDown(black.dispose);
        addTearDown(white.dispose);
        var largestError = 0;
        for (final light in [0.0, 0.5, 1.0]) {
          for (final time in [0.0, 1.25, 17.3]) {
            final state = AmbientState(noise: 1, light: light, motion: 1);
            final rendered = await _render(renderer, edge, state, time: time);
            final dark = await _render(renderer, black, state, time: time);
            final bright = await _render(renderer, white, state, time: time);
            for (var y = 0; y < edge.height; y++) {
              for (var x = 0; x < edge.width; x++) {
                if ((x + 0.5 - edge.width / 2).abs() <= edge.width * 0.05 + 1) {
                  continue;
                }
                final reference = x < edge.width / 2 ? dark : bright;
                final i = (y * edge.width + x) * 4;
                for (var c = 0; c < 3; c++) {
                  largestError = math.max(
                    largestError,
                    (rendered[i + c] - reference[i + c]).abs(),
                  );
                }
              }
            }
          }
        }
        expect(largestError, lessThanOrEqualTo(1));
        // ignore: avoid_print
        print(
          '${style.id}: maximum edge error outside 5% footprint=$largestError',
        );
      },
    );

    test('${style.id} bounds flash and retains local texture', () async {
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final fixtures = [
        await testImage(width: 128, height: 96),
        await _ramp(96, 128),
      ];
      addTearDown(() {
        for (final source in fixtures) {
          source.dispose();
        }
      });
      var maxFlash = 0.0;
      var flatPatches = 0;
      for (final source in fixtures) {
        final clean = await pixels(source);
        for (final time in [0.0, 1.25, 4.0, 17.3, 999999.0]) {
          final loud = await _render(
            renderer,
            source,
            const AmbientState(noise: 1),
            time: time,
          );
          for (var i = 0; i < clean.length; i += 4) {
            final before = _luma(clean, i);
            final after = _luma(loud, i);
            expect(after, lessThanOrEqualTo(before * 1.20 + 1.0));
            if (before >= 16) maxFlash = math.max(maxFlash, after / before);
          }
          // Detect newly flat 2x2 patches on the textured source. Natural flat
          // input is excluded; compare all channels to catch flat colour too.
          for (var y = 0; y < source.height - 1; y++) {
            for (var x = 0; x < source.width - 1; x++) {
              final i = (y * source.width + x) * 4;
              final offsets = [
                i,
                i + 4,
                i + source.width * 4,
                i + source.width * 4 + 4,
              ];
              var sourceRange = 0;
              var outputRange = 0;
              for (var c = 0; c < 3; c++) {
                final a = offsets.map((offset) => clean[offset + c]);
                final b = offsets.map((offset) => loud[offset + c]);
                sourceRange = math.max(
                  sourceRange,
                  a.reduce(math.max) - a.reduce(math.min),
                );
                outputRange = math.max(
                  outputRange,
                  b.reduce(math.max) - b.reduce(math.min),
                );
              }
              if (sourceRange > 24 && outputRange <= 1) flatPatches++;
            }
          }
        }
      }
      expect(flatPatches, 0);
      // ignore: avoid_print
      print(
        '${style.id}: maximum flash ratio=${maxFlash.toStringAsFixed(4)}; '
        'new flat patches=$flatPatches',
      );
    });

    test(
      '${style.id} is continuous and finite at control/time extremes',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final source = await testImage(width: 96, height: 80);
        addTearDown(source.dispose);
        const base = AmbientState(noise: 0.5, motion: 0.5);
        final reference = await _render(renderer, source, base);
        var largest = 0.0;
        for (final state in [
          const AmbientState(noise: 0.5001, motion: 0.5),
          const AmbientState(noise: 0.5, light: 0.5001, motion: 0.5),
          const AmbientState(noise: 0.5, light: 0.4999, motion: 0.5),
          const AmbientState(noise: 0.5, motion: 0.5001),
          const AmbientState(noise: 0.5, motion: 0.5, motionDirY: 0.0001),
        ]) {
          largest = math.max(
            largest,
            difference(reference, await _render(renderer, source, state)),
          );
        }
        largest = math.max(
          largest,
          difference(
            reference,
            await _render(renderer, source, base, time: 1.2501),
          ),
        );
        expect(largest, lessThan(0.25));
        for (final time in [0.0, 999999.0, 1000000.0]) {
          for (final light in [0.0, 1.0]) {
            await _render(
              renderer,
              source,
              AmbientState(
                noise: 1,
                light: light,
                motion: 1,
                motionDirX: -0.6,
                motionDirY: 0.8,
              ),
              time: time,
            );
          }
        }
        // ignore: avoid_print
        print(
          '${style.id}: largest tiny-uniform MAD=${largest.toStringAsFixed(4)}',
        );
      },
    );

    test(
      '${style.id} motion transports at most five percent of width',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        var largest = 0.0;
        for (final size in [(160, 96), (96, 160)]) {
          for (final vertical in [false, true]) {
            final source = await _ramp(size.$1, size.$2, vertical: vertical);
            try {
              final clean = await pixels(source);
              final moved = await _render(
                renderer,
                source,
                AmbientState(
                  motion: 1,
                  motionDirX: vertical ? 0 : 1,
                  motionDirY: vertical ? 1 : 0,
                ),
              );
              final span = vertical ? source.height - 1 : source.width - 1;
              for (var i = 0; i < clean.length; i += 4) {
                final offset =
                    (_luma(moved, i) - _luma(clean, i)).abs() /
                    255 *
                    span /
                    source.width;
                largest = math.max(largest, offset);
              }
            } finally {
              source.dispose();
            }
          }
        }
        // Allow one byte of quantisation in the ramp measurement.
        expect(largest, lessThanOrEqualTo(0.05 + 1 / 255));
        // ignore: avoid_print
        print(
          '${style.id}: maximum effective ramp displacement='
          '${(100 * largest).toStringAsFixed(3)}% of width',
        );
      },
    );
  }

  test(
    'new looks differ from one another and from every existing look',
    () async {
      final source = await testImage(width: 128, height: 96);
      addTearDown(source.dispose);
      final results = <String, Uint8List>{};
      for (final style in kStyles) {
        final renderer = await EffectRenderer.load(style);
        try {
          results[style.id] = await _render(
            renderer,
            source,
            const AmbientState(noise: 0.8, light: 0.3, motion: 0.5),
          );
        } finally {
          renderer.dispose();
        }
      }
      for (var i = 0; i < kStyles.length; i++) {
        for (var j = i + 1; j < kStyles.length; j++) {
          final a = kStyles[i].id;
          final b = kStyles[j].id;
          if (!_ids.contains(a) && !_ids.contains(b)) continue;
          final mad = difference(results[a]!, results[b]!);
          expect(
            mad,
            greaterThan(5),
            reason: '$a and $b need separate identities',
          );
          // ignore: avoid_print
          print('style separation $a/$b: MAD=${mad.toStringAsFixed(3)}');
        }
      }
    },
  );
}
