import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/export/glitch_wordmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Uint8List> render(double f, bool glitch) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFF808080), ui.BlendMode.src);
    GlitchWordmark.paint(canvas, const ui.Offset(30, 100), f, glitch: glitch);
    final picture = recorder.endRecording();
    final image = await picture.toImage(700, 150);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('advance scales linearly without a maximum', () {
    expect(
      GlitchWordmark.measure(60).width,
      closeTo(GlitchWordmark.measure(30).width * 2, 1),
    );
    expect(
      GlitchWordmark.measure(120).width,
      closeTo(GlitchWordmark.measure(30).width * 4, 1),
    );
  });
  test(
    'deterministic fringes only above the small-type threshold, within spill',
    () async {
      final bytes = await render(40, true);
      expect(bytes, orderedEquals(await render(40, true)));
      for (final (f, glitch, expected) in [
        (40.0, true, true),
        (40.0, false, false),
        (19.0, true, false),
      ]) {
        final pixels = await render(f, glitch);
        var cyan = 0;
        var magenta = 0;
        for (var i = 0; i < pixels.length; i += 4) {
          final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
          if (g > r + 10 && b > r + 10) cyan++;
          if (r > g + 10 && b > g + 10) magenta++;
          if (r != 128 || g != 128 || b != 128) {
            final x = (i ~/ 4) % 700, y = (i ~/ 4) ~/ 700;
            expect(
              x,
              inInclusiveRange(
                (30 - .3 * f).floor(),
                (30 + GlitchWordmark.measure(f).width + .3 * f).ceil(),
              ),
            );
            expect(
              y,
              inInclusiveRange(
                (100 - GlitchWordmark.measure(f).height).floor(),
                (100 + f).ceil(),
              ),
            );
          }
        }
        expect(cyan > 0, expected);
        expect(magenta > 0, expected);
      }
    },
  );
}
