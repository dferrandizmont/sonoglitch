import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/animation_clock.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/effects/effect_view.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/browsing_fakes.dart';

void main() {
  for (final cover in ['styles', 'help', 'settings', 'result', 'background']) {
    testWidgets('$cover pauses shader paints and the shared capture clock', (
      tester,
    ) async {
      final renderer = FakeBrowsingRenderer(kStyles.first);
      final styles = FakeStyleController(
        log: DebugLog(),
        loader: (_) async => renderer,
      );
      addTearDown(styles.dispose);
      final clock = FakeAnimationClock();
      final harness = await pumpViewfinder(
        tester,
        styles: styles,
        animationClock: clock,
      );
      final preview = await tester.runAsync(buildTestImage);
      final still = await tester.runAsync(buildTestImage);
      final rendered = await tester.runAsync(buildTestImage);
      addTearDown(rendered!.dispose);
      styles.still = rendered;
      harness.fakeCamera.publishFrame(preview!);
      harness.fakeCamera.still = still;
      await tester.pump();
      clock.advance(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 16));
      expect(renderer.paintTimes.last, 2);
      final paintsBeforeCover = renderer.paints;

      if (cover == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (cover == 'result') {
        await tester.tap(find.byKey(const ValueKey('vf-shutter')));
      } else {
        await tester.tap(
          find.byKey(
            ValueKey(switch (cover) {
              'styles' => 'vf-style-bar',
              'help' => 'vf-meters',
              _ => 'vf-settings',
            }),
          ),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(clock.isRunning, isFalse);
      if (cover == 'styles' || cover == 'help') {
        expect(
          renderer.paints,
          paintsBeforeCover,
          reason: 'Neither real sheet may repaint the shader while opening',
        );
      }
      final paints = renderer.paints;
      if (cover == 'background') {
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'The shader ticker stops synchronously before frames pause',
        );
      }
      clock.advance(const Duration(seconds: 30));
      // Even an externally published ambient value cannot run a hidden shader.
      harness.ambient.value = const AmbientState(noise: 0.9);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      // Publishing a synthetic value while frames are paused may queue a
      // LayoutBuilder rebuild; that callback is not an animation ticker.
      if (cover != 'background') {
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'The shader ticker must stop after sheet and ink transitions',
        );
      }
      expect(renderer.paints, paints);
      expect(clock.elapsedSeconds, 2);
      final effectContext = tester.element(
        find.byType(EffectView, skipOffstage: false),
      );
      final effect = tester.widget<EffectView>(
        find.byType(EffectView, skipOffstage: false),
      );
      expect(effect.active!.value, isFalse);
      if (cover == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        Navigator.of(effectContext).pop();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(clock.isRunning, isTrue);
      clock.advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 16));
      expect(renderer.paints, greaterThan(paints));
      expect(renderer.paintTimes.last, 2.25);
      await tester.tap(find.byKey(const ValueKey('vf-shutter')));
      await tester.pump();
      expect(styles.times.last, renderer.paintTimes.last);
      expect(harness.capture.value.animationTime, 2.25);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the still is drawn with the time of the preview', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final clock = FakeAnimationClock();
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      animationClock: clock,
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

    // The clock of the animation is the one of the screen, so the time it
    // shows is the time of the still.
    expect(clock.isRunning, isTrue);
    clock.advance(const Duration(milliseconds: 7500));

    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(styles.times, hasLength(1), reason: 'The picture must be drawn');
    expect(
      styles.times.single,
      closeTo(7.5, 0.0001),
      reason: 'The still must be drawn with the time the preview was showing',
    );
    expect(
      harness.capture.value.animationTime,
      closeTo(7.5, 0.0001),
      reason: 'The timings must show the time of the animation',
    );
    expect(harness.result, isNotNull);
    expect(harness.result?.styleId, harness.styles.style.id);

    // The picture handed to the result is the one the renderer produced, and
    // not the picture of the camera.
    expect(
      harness.result?.rendered,
      same(rendered),
      reason: 'The result must show the picture the renderer drew',
    );
    expect(
      harness.result?.rendered,
      isNot(same(still)),
      reason: 'The result must not show the raw picture of the camera',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the clock of the animation is frozen while the screen is hidden',
    (tester) async {
      final styles = FakeStyleController(log: DebugLog());
      final clock = FakeAnimationClock();
      final harness = await pumpViewfinder(
        tester,
        styles: styles,
        animationClock: clock,
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

      clock.advance(const Duration(milliseconds: 1250));

      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final first = styles.times.single;

      // The result of the capture covers the viewfinder.
      final context = tester.element(find.byType(ViewfinderScreen));
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Another screen covers the viewfinder: the animation of the preview is
      // frozen, so the clock must be frozen too.
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      // The clock is stopped while the screen is covered, so the time of the
      // hidden screen is not counted.
      expect(
        clock.isRunning,
        isFalse,
        reason: 'The clock must be stopped while the screen is covered',
      );
      clock.advance(const Duration(seconds: 30));

      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        clock.isRunning,
        isTrue,
        reason: 'The clock must run again when the screen comes back',
      );

      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(styles.times, hasLength(2));
      expect(
        styles.times.last,
        closeTo(first, 0.0001),
        reason: 'The time the screen was hidden must not be counted',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
