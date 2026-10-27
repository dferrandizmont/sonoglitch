import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/viewfinder/capture_flash.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Whether the shutter can be pressed.
///
/// The button of the shutter tells the screen readers that it is disabled
/// while the picture is being taken, so the state is read from the node of
/// the button.
bool? shutterEnabled(WidgetTester tester) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(
          of: find.byTooltip('Take a photo'),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.enabled;
}

void main() {
  testWidgets('the shutter is disabled while the picture is being taken', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final styles = FakeStyleController(log: DebugLog());
      final harness = await pumpViewfinder(tester, styles: styles);
      final preview = await tester.runAsync(buildTestImage);
      final still = await tester.runAsync(buildTestImage);
      final rendered = await tester.runAsync(buildTestImage);
      addTearDown(rendered!.dispose);
      styles.still = rendered;
      harness.fakeCamera.publishFrame(preview!);
      harness.fakeCamera.still = still;

      // The capture waits, so the shutter stays busy.
      final gate = Completer<void>();
      harness.fakeCamera.captureGate = gate;

      await tester.pump();
      expect(shutterEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();

      expect(find.text('Capturing…'), findsOneWidget);
      expect(
        shutterEnabled(tester),
        isFalse,
        reason: 'The shutter must be disabled while the picture is taken',
      );

      // The shutter does not take a second picture.
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      expect(harness.fakeCamera.captures, 1);

      gate.complete();
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the shot flashes and buzzes', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(tester, styles: styles);
    final preview = await tester.runAsync(buildTestImage);
    final still = await tester.runAsync(buildTestImage);
    final rendered = await tester.runAsync(buildTestImage);
    addTearDown(rendered!.dispose);
    styles.still = rendered;
    harness.fakeCamera.publishFrame(preview!);
    harness.fakeCamera.still = still;

    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();

    // The phone gives a short tap in the hand.
    expect(
      calls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.mediumImpact',
      ),
      isNotEmpty,
      reason: 'The shot must be confirmed with a haptic tap',
    );

    // The preview flashes.
    final flash = tester.widget<CaptureFlash>(find.byType(CaptureFlash));
    expect(flash.opacity.value, greaterThan(0));

    // And the flash is over in less than 150 ms.
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<CaptureFlash>(find.byType(CaptureFlash)).opacity.value,
      0,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
