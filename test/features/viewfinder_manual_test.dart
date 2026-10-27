import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_hud.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/effect_view.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  testWidgets('the manual mode drives the values of the picture', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      diagnostics: true,
    );
    final preview = await tester.runAsync(buildTestImage);
    harness.fakeCamera.publishFrame(preview!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The panel starts in automatic mode.
    expect(harness.ambient.isManual, isFalse);
    expect(find.text('AUTO'), findsOneWidget);
    expect(find.text('MANUAL'), findsNothing);
    expect(find.byType(Slider), findsNothing);

    // The switch turns the manual mode on.
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(harness.ambient.isManual, isTrue);
    expect(find.text('MANUAL'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));

    // Moving the slider of the noise changes the value of the picture.
    final before = harness.ambient.value.noise;
    await tester.ensureVisible(find.byType(Slider).at(0));
    await tester.pump();
    await tester.drag(find.byType(Slider).at(0), const Offset(120, 0));
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider).at(0));
    expect(slider.value, greaterThan(before));
    expect(harness.ambient.value.noise, closeTo(slider.value, 0.0001));

    // The effect view reads the same values.
    final view = tester.widget<EffectView>(find.byType(EffectView));
    expect(view.ambient.value.noise, closeTo(slider.value, 0.0001));

    // And so does the snapshot of a capture.
    expect(harness.ambient.snapshot().noise, closeTo(slider.value, 0.0001));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the capture takes the values of the manual mode', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      diagnostics: true,
    );
    final preview = await tester.runAsync(buildTestImage);
    final still = await tester.runAsync(buildTestImage);
    final rendered = await tester.runAsync(buildTestImage);
    addTearDown(rendered!.dispose);
    styles.still = rendered;
    harness.fakeCamera.publishFrame(preview!);
    harness.fakeCamera.still = still;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.ensureVisible(find.byType(Slider).at(0));
    await tester.pump();
    await tester.drag(find.byType(Slider).at(0), const Offset(120, 0));
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider).at(0));

    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.result, isNotNull);
    expect(harness.result!.ambient.noise, closeTo(slider.value, 0.0001));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the panel does not cover the shutter and the style bar', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester, diagnostics: true);
    await tester.pump();

    await tester.tap(find.byType(Switch));
    await tester.pump();

    // The shutter and the style bar are still on the screen.
    expect(find.byTooltip('Take a photo'), findsOneWidget);
    expect(find.text(harness.styles.style.name.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);

    // And the panel does not paint over them.
    final panel = tester.getRect(find.byType(DebugHud));
    expect(
      panel.overlaps(tester.getRect(find.byTooltip('Take a photo'))),
      isFalse,
      reason: 'The panel must not cover the shutter',
    );
    expect(
      panel.overlaps(
        tester.getRect(find.byKey(const ValueKey('vf-style-bar'))),
      ),
      isFalse,
      reason: 'The panel must not cover the style bar',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
