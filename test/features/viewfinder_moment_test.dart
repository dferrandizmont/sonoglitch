import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/clock.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The tooltip of the button that arms the moment mode.
const String _momentTooltip =
    'Auto shot: takes the photo on a loud sound or sudden move';

/// The line that says the camera is waiting for the peak.
const String _momentArmed = 'Waiting for a loud sound or a sudden move';

/// The message that says the photo was taken at the peak.
const String _momentCaptured = 'Auto shot captured';

/// A clock that follows the fake time of the widget tester.
///
/// The moment detector measures the quiet period with it, so the test can
/// move the time of the samples without waiting for it.
Clock _fakeClock(WidgetTester tester) =>
    () => tester.binding.clock.now().microsecondsSinceEpoch;

/// Retain the real controller so removing the ring cannot hide a live ticker.
AnimationController _pulseController(WidgetTester tester) =>
    tester
            .widget<AnimatedBuilder>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('moment-ring')),
                    matching: find.byType(AnimatedBuilder),
                  )
                  .first,
            )
            .animation
        as AnimationController;

void main() {
  testWidgets(
    'reduced motion keeps a static ring and exposes the armed toggle',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpViewfinder(
          tester,
          mediaQuery: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('vf-auto-shot')));
        await tester.pump();
        final pulse = _pulseController(tester);
        expect(pulse.isAnimating, isFalse);
        expect(
          tester.getSemantics(find.byKey(const ValueKey('vf-auto-shot'))),
          matchesSemantics(
            isButton: true,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
            label: _momentTooltip,
          ),
        );
        final ring = find.byKey(const ValueKey('moment-ring'));
        final before = tester.getRect(ring);
        await tester.pump(const Duration(milliseconds: 750));
        expect(tester.getRect(ring), before);
        expect(pulse.isAnimating, isFalse);
        expect(before.width, 92);
        // The neighbouring targets remain 24 dp clear of the static ring.
        final autoShot = tester.getRect(
          find.byKey(const ValueKey('vf-auto-shot')),
        );
        final flip = tester.getRect(find.byKey(const ValueKey('vf-flip')));
        expect(before.left - autoShot.right, closeTo(24, 0.01));
        expect(flip.left - before.right, closeTo(24, 0.01));
      } finally {
        semantics.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'the Auto shot button has a label, tooltip and toggled semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpViewfinder(tester, ambientClock: _fakeClock(tester));

        final button = find.byTooltip(_momentTooltip);
        expect(button, findsOneWidget);
        expect(
          find.bySemanticsLabel(_momentTooltip),
          findsOneWidget,
          reason: 'the button must say what it does',
        );
        expect(
          tester.getSize(button),
          const Size(48, 48),
          reason: 'the button is as big as the other ones of the row',
        );

        final autoShot = tester.getCenter(button);
        final shutter = tester.getCenter(
          find.byKey(const ValueKey('vf-shutter')),
        );
        expect(autoShot.dx, shutter.dx - 94);
        expect(autoShot.dy, shutter.dy);
        expect(
          tester.getSemantics(find.byKey(const ValueKey('vf-auto-shot'))),
          matchesSemantics(
            isButton: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
            label: _momentTooltip,
          ),
        );
      } finally {
        handle.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the button arms the camera and says it', (tester) async {
    await pumpViewfinder(tester, ambientClock: _fakeClock(tester));

    expect(find.text(_momentArmed), findsNothing);
    expect(find.byKey(const ValueKey('moment-ring')), findsNothing);

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();

    expect(find.text(_momentArmed), findsOneWidget);
    expect(
      find.byKey(const ValueKey('moment-ring')),
      findsOneWidget,
      reason: 'the ring around the shutter says the camera is waiting',
    );

    // Tapping it again stops the camera.
    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();

    expect(find.text(_momentArmed), findsNothing);
    expect(find.byKey(const ValueKey('moment-ring')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the peak takes the photo without a count or snackbar', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      ambientClock: _fakeClock(tester),
    );
    final still = await tester.runAsync(buildTestImage);
    harness.fakeCamera.still = still;

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();

    // The place is quiet for a second, so the next peak counts.
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));

    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.fakeCamera.captures, 1, reason: 'the photo was taken');
    expect(harness.result, isNotNull);
    expect(find.text(_momentCaptured), findsNothing);
    expect(find.byKey(const ValueKey('moment-count')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the camera does not take a photo when it is not armed', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      ambientClock: _fakeClock(tester),
    );
    final still = await tester.runAsync(buildTestImage);
    harness.fakeCamera.still = still;

    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      harness.fakeCamera.captures,
      0,
      reason: 'the camera only takes a photo when the user asks for it',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final throws in [false, true]) {
    testWidgets('a ${throws ? 'throwing' : 'null'} capture is not counted', (
      tester,
    ) async {
      final harness = await pumpViewfinder(
        tester,
        ambientClock: _fakeClock(tester),
      );
      final gate = Completer<void>();
      harness.fakeCamera.captureGate = gate;
      await tester.tap(find.byTooltip(_momentTooltip));
      await tester.pump();
      final pulse = _pulseController(tester);
      expect(pulse.isAnimating, isTrue);

      harness.ambient.setManual(true);
      harness.ambient.setManualValues(noise: 0.2);
      await tester.pump(const Duration(seconds: 2));
      harness.ambient.setManualValues(noise: 0.95);
      await tester.pump();
      expect(harness.fakeCamera.captures, 1);
      expect(find.text(_momentCaptured), findsNothing);
      expect(find.byKey(const ValueKey('moment-count')), findsNothing);
      expect(
        pulse.isAnimating,
        isFalse,
        reason: 'single shot disarms immediately',
      );

      if (throws) {
        gate.completeError(StateError('Camera failed'));
      } else {
        gate.complete();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.result, isNull);
      expect(
        find.text('The camera could not be started.'),
        findsOneWidget,
        reason: 'capture error is reported',
      );
      expect(find.text(_momentCaptured), findsNothing);
      expect(find.byKey(const ValueKey('moment-count')), findsNothing);
      expect(find.text(_momentArmed), findsNothing);
      expect(pulse.isAnimating, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the camera does not take a photo while one is being taken', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      ambientClock: _fakeClock(tester),
    );
    final still = await tester.runAsync(buildTestImage);
    harness.fakeCamera.still = still;
    // The photo waits, so the shutter stays busy.
    final gate = Completer<void>();
    harness.fakeCamera.captureGate = gate;

    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();
    expect(harness.fakeCamera.captures, 1);

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();

    expect(
      harness.fakeCamera.captures,
      1,
      reason: 'a photo was already being taken',
    );
    expect(find.text('Capturing…'), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-ring')), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving the viewfinder stops the camera', (tester) async {
    final harness = await pumpViewfinder(
      tester,
      ambientClock: _fakeClock(tester),
    );

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    expect(find.text(_momentArmed), findsOneWidget);

    final context = tester.element(find.byType(ViewfinderScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text(_momentArmed, skipOffstage: false),
      findsNothing,
      reason: 'the camera must not take a photo while nobody is looking',
    );

    // Supply a qualifying quiet period and peak even though sampling stopped.
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump();
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(harness.fakeCamera.captures, 0);

    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_momentArmed), findsNothing);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(harness.fakeCamera.captures, 0, reason: 'returning does not rearm');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the app in the background stops the camera', (tester) async {
    await pumpViewfinder(tester, ambientClock: _fakeClock(tester));

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    expect(find.text(_momentArmed), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      find.text(_momentArmed),
      findsNothing,
      reason: 'the camera must not take a photo while the app is away',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('quiet qualification cannot span a sensor pause', (tester) async {
    final harness = await pumpViewfinder(
      tester,
      ambientClock: _fakeClock(tester),
    );
    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(milliseconds: 500));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(harness.ambient.isRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump(const Duration(milliseconds: 100));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(
      harness.fakeCamera.captures,
      0,
      reason: 'unobserved time is not quiet',
    );

    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(milliseconds: 1100));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(
      harness.fakeCamera.captures,
      1,
      reason: 'a fresh quiet second qualifies',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the camera stops after one photo', (tester) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      ambientClock: _fakeClock(tester),
    );
    final still = await tester.runAsync(buildTestImage);
    harness.fakeCamera.still = still;

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    final pulse = _pulseController(tester);
    expect(pulse.isAnimating, isTrue);
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.fakeCamera.captures, 1);
    expect(pulse.isAnimating, isFalse);
    expect(
      find.text(_momentArmed, skipOffstage: false),
      findsNothing,
      reason: 'the camera waits for the user after one photo',
    );

    final context = tester.element(
      find.byType(ViewfinderScreen, skipOffstage: false),
    );
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_momentArmed), findsNothing);
    expect(
      pulse.isAnimating,
      isFalse,
      reason: 'returning does not restart the pulse',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the setting keeps the camera waiting for the next peak', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await settings.setMomentKeepArmed(true);
    final harness = await pumpViewfinder(
      tester,
      styles: styles,
      settings: settings,
      ambientClock: _fakeClock(tester),
    );
    final still = await tester.runAsync(buildTestImage);
    harness.fakeCamera.still = still;

    await tester.tap(find.byTooltip(_momentTooltip));
    await tester.pump();
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.fakeCamera.captures, 1);

    // The picture is shown, and the camera is still waiting behind it.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('route'), findsOneWidget);
    expect(
      find.textContaining('Capturing', skipOffstage: false),
      findsOneWidget,
    );
    expect(harness.ambient.isRunning, isFalse);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 9));
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump();
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(
      harness.fakeCamera.captures,
      1,
      reason: 'covered peaks cannot capture',
    );
    expect(
      find.textContaining('Capturing', skipOffstage: false),
      findsOneWidget,
    );

    // Leave a quiet sample behind the result route: it must not earn credit.
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump(const Duration(seconds: 2));
    final context = tester.element(
      find.byType(ViewfinderScreen, skipOffstage: false),
    );
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_momentArmed), findsOneWidget);
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    expect(
      harness.fakeCamera.captures,
      1,
      reason: 'paused time is not observed quiet',
    );

    // The place calms down and the next peak is caught too.
    // Each capture owns and disposes its source image.
    harness.fakeCamera.still = await tester.runAsync(buildTestImage);
    harness.ambient.setManualValues(noise: 0.2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    harness.ambient.setManualValues(noise: 0.95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.fakeCamera.captures, 2, reason: 'the next peak is caught');
    expect(find.byKey(const ValueKey('moment-count')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
