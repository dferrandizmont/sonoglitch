import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/effect_view.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show testImage;

void main() {
  testWidgets('animates, listens to ambient changes, rebinds and disposes', (
    tester,
  ) async {
    final renderer = await EffectRenderer.load(kStyles.first);
    final image = await tester.runAsync(testImage);
    final replacement = await tester.runAsync(testImage);
    final ambient = ValueNotifier(AmbientState.calm);
    final nextAmbient = ValueNotifier(AmbientState.calm);
    addTearDown(renderer.dispose);
    addTearDown(image!.dispose);
    addTearDown(replacement!.dispose);
    addTearDown(ambient.dispose);
    addTearDown(nextAmbient.dispose);

    Widget view({bool enabled = true, bool empty = false, bool swap = false}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(
            enabled: enabled,
            child: SizedBox(
              width: 100,
              height: 100,
              child: EffectView(
                renderer: renderer,
                image: empty ? null : (swap ? replacement : image),
                ambient: swap ? nextAmbient : ambient,
              ),
            ),
          ),
        );

    await tester.pumpWidget(view());
    var painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
    var repaints = 0;
    void onRepaint() => repaints++;
    painter.addListener(onRepaint);
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      repaints,
      greaterThan(0),
      reason: 'Time advances without sensor input',
    );
    final afterTick = repaints;
    ambient.value = const AmbientState(noise: 0.7);
    expect(repaints, greaterThan(afterTick));
    painter.removeListener(onRepaint);

    await tester.pumpWidget(view(swap: true));
    final previousPainter = painter;
    painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
    expect(painter.shouldRepaint(previousPainter), isTrue);
    painter.addListener(onRepaint);
    final afterSwap = repaints;
    ambient.value = const AmbientState(noise: 0.1);
    expect(repaints, afterSwap, reason: 'The old notifier is detached');
    nextAmbient.value = const AmbientState(motion: 0.5);
    expect(repaints, greaterThan(afterSwap));
    painter.removeListener(onRepaint);

    await tester.pumpWidget(view(enabled: false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(view(empty: true));
    expect(find.byType(CustomPaint), findsNothing);
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
