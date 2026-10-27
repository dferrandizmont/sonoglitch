import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show pixels;

const _side = 96;

/// A vertical gradient: top is dark, bottom is bright. The independent top
/// and bottom strips give a sharp signal of which way a smear has shifted
/// pixels, with no confounding contribution from horizontal noise/shifts.
Future<ui.Image> _verticalGradient() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < _side; y++) {
    // 0 at the top, 255 at the bottom, linear in between.
    final value = (255 * y / (_side - 1)).round();
    canvas.drawRect(
      ui.Rect.fromLTWH(0, y.toDouble(), _side.toDouble(), 1),
      ui.Paint()..color = ui.Color.fromARGB(255, value, value, value),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_side, _side);
  } finally {
    picture.dispose();
  }
}

/// The mean luminance of [data] across the strip [fromY, toY) of the frame,
/// restricted to a central column band so horizontal edges cannot leak in.
double _stripLuma(Uint8List data, int fromY, int toY) {
  const stripLeft = 16;
  const stripRight = _side - 16;
  var sum = 0.0;
  var count = 0;
  for (var y = fromY; y < toY; y++) {
    for (var x = stripLeft; x < stripRight; x++) {
      final i = (y * _side + x) * 4;
      sum += data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;
      count++;
    }
  }
  return sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Render the same vertical gradient with motion Y = +1 (up) and Y = -1
  // (down). The gradient is so strong that the smear cannot invert it, but
  // it can lift pixels at the dark top end toward bright when the shake
  // points up, and pull pixels at the bright bottom end toward dark when
  // the shake points down. The unsigned MAD used in
  // `ambient_response_test.dart` cannot detect a Y-axis flip, so this
  // assertion lives here.
  // Neutral placeholders are covered by shader_contract_test, not response tests.
  for (final style in kStyles.where((style) => !style.isPlaceholder)) {
    test('${style.id} smears towards the shake direction on the Y axis', () async {
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      final source = await _verticalGradient();
      addTearDown(source.dispose);

      Future<double> strip(AmbientState ambient, bool top) async {
        final image = await renderer.renderToImage(
          source,
          ambient: ambient,
          time: 0,
        );
        try {
          final data = await pixels(image);
          return top
              ? _stripLuma(data, 4, _side ~/ 3)
              : _stripLuma(data, _side - _side ~/ 3, _side - 4);
        } finally {
          image.dispose();
        }
      }

      const up = AmbientState(motion: 1, motionDirX: 0, motionDirY: 1);
      const down = AmbientState(motion: 1, motionDirX: 0, motionDirY: -1);

      final topUp = await strip(up, true);
      final topDown = await strip(down, true);
      final bottomUp = await strip(up, false);
      final bottomDown = await strip(down, false);

      // A +Y shake must move bright content UP: the top strip must be
      // brighter with +Y than it is with -Y. A flipped shader does the
      // opposite and makes the top darker with +Y than with -Y.
      expect(
        topUp,
        greaterThan(topDown),
        reason:
            'A +Y shake must lift the dark top toward bright; a -Y shake '
            'must leave it dark. Top strip +Y=${topUp.toStringAsFixed(2)} '
            '-Y=${topDown.toStringAsFixed(2)}.',
      );
      // A -Y shake must pull mid-tone content DOWN: the bottom strip must
      // be darker with -Y than it is with +Y (where ghosts sample the
      // clamped bright edge and the bottom stays at source brightness).
      expect(
        bottomDown,
        lessThan(bottomUp),
        reason:
            'A -Y shake must pull the bright bottom toward dark; a +Y shake '
            'must leave it at the source brightness. Bottom strip '
            '-Y=${bottomDown.toStringAsFixed(2)} +Y=${bottomUp.toStringAsFixed(2)}.',
      );
    });
  }
}
