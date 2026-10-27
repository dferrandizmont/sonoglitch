import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';

import '../support/fakes.dart';

/// Draws with [renderer] and fails when the renderer was released.
void paint(EffectRenderer renderer, ui.Image image) {
  final recorder = ui.PictureRecorder();
  renderer.paint(
    ui.Canvas(recorder),
    const ui.Size(10, 10),
    image: image,
    ambient: AmbientState.calm,
    time: 0,
  );
  recorder.endRecording().dispose();
}

void main() {
  testWidgets('the renderer that is replaced is released', (tester) async {
    final controller = StyleController(log: DebugLog());
    await controller.load();
    final first = controller.renderer;
    expect(first, isNotNull);
    final image = await tester.runAsync(buildTestImage);
    addTearDown(image!.dispose);

    await controller.select(kStyles[1]);
    await tester.pump();

    expect(controller.renderer, isNot(same(first)));
    expect(
      () => paint(first!, image),
      throwsStateError,
      reason: 'The renderer that is not drawn any more must be released',
    );
    controller.dispose();
  });

  testWidgets('the renderer that lost the race is released', (tester) async {
    final pending = <String, Completer<EffectRenderer>>{};
    final controller = StyleController(
      log: DebugLog(),
      loader: (style) {
        final completer = Completer<EffectRenderer>();
        pending[style.id] = completer;
        return completer.future;
      },
    );
    final image = await tester.runAsync(buildTestImage);
    addTearDown(image!.dispose);

    final first = controller.select(kStyles[0]);
    final second = controller.select(kStyles[1]);

    final winner = await EffectRenderer.load(kStyles[1]);
    pending[kStyles[1].id]!.complete(winner);
    await second;

    final loser = await EffectRenderer.load(kStyles[0]);
    pending[kStyles[0].id]!.complete(loser);
    await first;
    await tester.pump();

    expect(controller.renderer, same(winner));
    expect(
      () => paint(loser, image),
      throwsStateError,
      reason: 'The renderer that was never drawn must be released',
    );
    controller.dispose();
  });

  test('the renderer is released with the controller', () async {
    final controller = StyleController(log: DebugLog());
    await controller.load();
    final renderer = controller.renderer;
    expect(renderer, isNotNull);
    final image = await buildTestImage();
    addTearDown(image.dispose);

    controller.dispose();

    expect(() => paint(renderer!, image), throwsStateError);
  });
}
