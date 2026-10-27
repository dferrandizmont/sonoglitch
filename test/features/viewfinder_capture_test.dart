import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/oriented_still.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/animation_clock.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class _GatedContext extends ContextSensors {
  final gate = Completer<ExportContext>();
  DateTime? shutterTime;
  int calls = 0;
  @override
  Future<ExportContext> sample({required DateTime dateTime}) {
    calls++;
    shutterTime = dateTime;
    return gate.future;
  }
}

class _FrontCapture extends FakeCameraService {
  _FrontCapture() : super(light: LightService(), log: DebugLog());

  @override
  Future<StillCapture?> captureStill({bool deferDecode = false}) async {
    final capture = await super.captureStill(deferDecode: deferDecode);
    return StillCapture(
      image: capture!.image,
      timings: capture.timings,
      transform: StillTransform(
        frontLens: true,
        decodedMirrored: false,
        previewQuarterTurns: 3,
      ),
    );
  }
}

void main() {
  for (final enabled in [false, true]) {
    testWidgets('context opt-in=$enabled never holds up the camera shutter', (
      tester,
    ) async {
      final sensor = _GatedContext();
      final styles = FakeStyleController(log: DebugLog());
      final harness = await pumpViewfinder(
        tester,
        styles: styles,
        contextSensors: sensor,
      );
      await harness.settings.setContextLineEnabled(enabled);
      final preview = (await tester.runAsync(buildTestImage))!;
      final still = (await tester.runAsync(buildTestImage))!;
      final rendered = (await tester.runAsync(buildTestImage))!;
      addTearDown(rendered.dispose);
      styles.still = rendered;
      harness.fakeCamera.publishFrame(preview);
      harness.fakeCamera.still = still;
      await tester.pump();
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      expect(harness.fakeCamera.captures, 1);
      expect(sensor.calls, enabled ? 1 : 0);
      if (enabled) {
        expect(harness.result, isNull);
        final frozen = ExportContext(
          dateTime: sensor.shutterTime,
          heading: 42,
          pressure: 1013,
        );
        sensor.gate.complete(frozen);
        await tester.pump();
        expect(harness.result!.context, same(frozen));
      } else {
        expect(harness.result!.context, isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'front still uses the frozen capture basis for result and diagnostics',
    (tester) async {
      final camera = _FrontCapture();
      final styles = FakeStyleController(log: DebugLog());
      final harness = await pumpViewfinder(
        tester,
        camera: camera,
        styles: styles,
      );
      final preview = await tester.runAsync(buildTestImage);
      final still = await tester.runAsync(buildTestImage);
      final rendered = await tester.runAsync(buildTestImage);
      addTearDown(rendered!.dispose);
      styles.still = rendered;
      camera.publishFrame(preview!);
      camera.still = still;
      await tester.pump();
      harness.motion.directionX.reset(1);
      harness.motion.directionY.reset(0);
      harness.motion.magnitude.reset(1);
      harness.ambient.clearHistory();
      harness.ambient.tick();
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      // Preview right must be reflected left BEFORE its CW rotation: it ends
      // up pointing UP in the unmirrored landscape selfie, not down.
      expect(harness.result!.ambient.motionDirX, 0);
      expect(harness.result!.ambient.motionDirY, 1);
      expect(harness.capture.value.ambient!.motionDirY, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

    // Pump a frame so the preview becomes ready and the clock starts, then
    // advance the fake clock by a known amount. The viewfinder's
    // `renderStill` must receive exactly that time.
    await tester.pump();
    clock.advance(const Duration(milliseconds: 500));
    // The viewfinder reads _animationTime once for the shutter and once
    // more for the capture; advance the clock between the two.
    final shutterTime = clock.elapsedSeconds;
    await tester.tap(find.byTooltip('Take a photo'));
    clock.advance(const Duration(milliseconds: 100));
    await tester.pump();

    expect(styles.times, hasLength(1), reason: 'The picture must be drawn');
    expect(
      styles.times.single,
      closeTo(shutterTime, 1e-9),
      reason: 'The still must be drawn with the time of the preview, not later',
    );
    expect(
      harness.capture.value.animationTime,
      closeTo(shutterTime, 1e-9),
      reason: 'The timings must show the time of the animation',
    );
    // The image handed to the result is the fake's still, not the source.
    expect(harness.result, isNotNull);
    expect(harness.result!.styleId, harness.styles.style.id);
    expect(identical(harness.result!.rendered, rendered), isTrue);

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

      // First shutter at a known time.
      clock.advance(const Duration(milliseconds: 500));
      final firstTime = clock.elapsedSeconds;
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(styles.times, hasLength(1));

      // The result route covers the viewfinder.
      final context = tester.element(find.byType(ViewfinderScreen));
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Another route covers the viewfinder: the animation of the preview
      // is frozen, so the clock must be frozen too. Advancing the fake clock
      // while it is frozen must not change the elapsed time.
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        clock.elapsedSeconds,
        closeTo(firstTime, 1e-9),
        reason: 'The clock must be frozen while the screen is hidden',
      );

      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Second shutter, with the clock advanced only after coming back.
      clock.advance(const Duration(milliseconds: 100));
      final secondTime = clock.elapsedSeconds;
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(styles.times, hasLength(2));
      // The 2 s the screen was covered must not be counted: the only time
      // elapsed between the two shutters is the 100 ms we advanced the clock
      // after coming back. If the clock leaked through the hidden period,
      // the difference would be > 0.1 s.
      expect(
        styles.times.last - firstTime,
        closeTo(0.1, 1e-9),
        reason: 'Only the visible time (100 ms) must be counted',
      );
      expect(
        styles.times.last,
        closeTo(secondTime, 1e-9),
        reason: 'The second still must be drawn with the visible clock',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
