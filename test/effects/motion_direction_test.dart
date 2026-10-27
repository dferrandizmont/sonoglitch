import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels;

const _side = 128;

/// A horizontal edge: black above row 64, white below.
///
/// A vertical motion smear pulls colour from behind the direction of the
/// motion. With the fix, a shake *up* (motionDirY = +1) pulls the white
/// pixels just below the edge upward, so the band just above the edge
/// becomes whiter. A shake *down* (motionDirY = -1) pulls the black
/// pixels just above the edge downward, so the band just below the edge
/// becomes darker. The test asserts those two changes happen in their
/// expected halves (regression for the inverted Y of the motion trail).
Future<ui.Image> _horizontalEdgeFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, _side.toDouble(), _side.toDouble()),
    ui.Paint()..color = const ui.Color.fromARGB(255, 0, 0, 0),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 64, _side.toDouble(), 64),
    ui.Paint()..color = const ui.Color.fromARGB(255, 255, 255, 255),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(_side, _side);
  } finally {
    picture.dispose();
  }
}

/// The mean luma of [data] in the band [top]..[bottom] (exclusive), across
/// the full width minus a small border.
double _meanLumaIn(Uint8List data, int top, int bottom) {
  var sum = 0.0;
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = 16; x < _side - 16; x++) {
      final i = (y * _side + x) * 4;
      sum += data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;
      count++;
    }
  }
  return sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Neutral placeholders are covered by shader_contract_test, not response tests.
  for (final style in kStyles.where((style) => !style.isPlaceholder)) {
    test(
      '${style.id}: a vertical motion smear follows the direction of the motion',
      () async {
        final renderer = await EffectRenderer.load(style);
        addTearDown(renderer.dispose);
        final source = await _horizontalEdgeFixture();
        addTearDown(source.dispose);

        final shakeUp = await renderer.renderToImage(
          source,
          ambient: const AmbientState(motion: 1, motionDirX: 0, motionDirY: 1),
          time: 1.25,
        );
        addTearDown(shakeUp.dispose);
        final shakeDown = await renderer.renderToImage(
          source,
          ambient: const AmbientState(motion: 1, motionDirX: 0, motionDirY: -1),
          time: 1.25,
        );
        addTearDown(shakeDown.dispose);

        final original = await pixels(source);
        final up = await pixels(shakeUp);
        final down = await pixels(shakeDown);

        // The two renderings must differ from each other AND from the source:
        // a smear with a direction must not be the same as no smear at all.
        expect(difference(up, down), greaterThan(1));
        expect(difference(original, up), greaterThan(1));
        expect(difference(original, down), greaterThan(1));

        // Bands immediately on either side of the edge (rows 60-63 are
        // black in the source; rows 65-68 are white).
        final aboveSource = _meanLumaIn(original, 60, 64);
        final belowSource = _meanLumaIn(original, 65, 69);
        final aboveUp = _meanLumaIn(up, 60, 64);
        final belowDown = _meanLumaIn(down, 65, 69);

        // Shake up: pull white up into the black band above the edge.
        expect(
          aboveUp - aboveSource,
          greaterThan(5),
          reason: 'A shake up must brighten the black band above the edge',
        );
        // Shake down: pull black down into the white band below the edge.
        expect(
          belowDown - belowSource,
          lessThan(-5),
          reason: 'A shake down must darken the white band below the edge',
        );
      },
    );
  }
}
