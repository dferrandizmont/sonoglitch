import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/volume_keys.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/viewfinder/capture_flash.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class _VolumeKeys implements VolumeKeys {
  final controller = StreamController<void>.broadcast(sync: true);
  @override
  bool enabled = false;
  @override
  Stream<void> get presses => controller.stream;

  // Deliberately deliver disabled presses too, to exercise in-flight guards.
  void press() => controller.add(null);
  @override
  void dispose() => unawaited(controller.close());
}

class _UnavailableCamera extends FakeCameraService {
  _UnavailableCamera() : super(light: LightService(), log: DebugLog());

  @override
  Future<void> initialize({
    CameraLensDirection direction = CameraLensDirection.back,
  }) async {
    throw StateError('Camera unavailable');
  }
}

void main() {
  late _VolumeKeys keys;
  setUp(() => keys = _VolumeKeys());
  tearDown(() => keys.dispose());

  Future<void> ready(WidgetTester tester, ViewfinderHarness harness) async {
    final image = (await tester.runAsync(buildTestImage))!;
    harness.fakeCamera.publishFrame(image);
    await tester.pump();
    expect(keys.enabled, isTrue);
  }

  Future<void> finishRouteTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('one press uses the shutter, busy presses cannot capture twice', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(
      tester,
      volumeKeys: keys,
      styles: styles,
    );
    await ready(tester, harness);
    final still = (await tester.runAsync(buildTestImage))!;
    final rendered = (await tester.runAsync(buildTestImage))!;
    addTearDown(rendered.dispose);
    styles.still = rendered;
    harness.fakeCamera.still = still;
    final gate = Completer<void>();
    harness.fakeCamera.captureGate = gate;

    keys.press();
    keys.press();
    await tester.pump();
    expect(harness.fakeCamera.captures, 1);
    expect(keys.enabled, isFalse);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(
      tester.widget<CaptureFlash>(find.byType(CaptureFlash)).opacity.value,
      greaterThan(0),
    );
    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();
    expect(harness.fakeCamera.captures, 1);

    gate.complete();
    await tester.pump();
    expect(harness.result, isNotNull);
    expect(keys.enabled, isFalse);
    keys.press();
    await tester.pump();
    expect(harness.fakeCamera.captures, 1);
    final context = tester.element(find.byType(ViewfinderScreen));
    Navigator.of(context).pop();
    await finishRouteTransition(tester);
    expect(keys.enabled, isTrue);
    harness.fakeCamera.still = (await tester.runAsync(buildTestImage))!;
    keys.press();
    await tester.pump();
    expect(harness.fakeCamera.captures, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(keys.enabled, isFalse);
  });

  testWidgets(
    'setting off ignores presses and leaves the touch shutter working',
    (tester) async {
      final harness = await pumpViewfinder(tester, volumeKeys: keys);
      await ready(tester, harness);
      await harness.settings.setVolumeButtonsEnabled(false);
      expect(keys.enabled, isFalse);
      keys.press();
      await tester.pump();
      expect(harness.fakeCamera.captures, 0);
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pump();
      expect(harness.fakeCamera.captures, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings, sheets, dialogs, pause and disposal release the keys',
    (tester) async {
      final harness = await pumpViewfinder(tester, volumeKeys: keys);
      await ready(tester, harness);
      final context = tester.element(find.byType(ViewfinderScreen));
      await tester.tap(find.byTooltip('Settings'));
      // A queued hardware press must be ignored even before the next frame.
      keys.press();
      await finishRouteTransition(tester);
      expect(keys.enabled, isFalse);
      expect(harness.fakeCamera.captures, 0);
      keys.press();
      Navigator.of(context).pop();
      await finishRouteTransition(tester);
      expect(keys.enabled, isTrue);

      unawaited(
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => const Text('sheet'),
        ),
      );
      await finishRouteTransition(tester);
      expect(keys.enabled, isFalse);
      keys.press();
      Navigator.of(context).pop();
      await finishRouteTransition(tester);
      expect(keys.enabled, isTrue);

      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await finishRouteTransition(tester);
      expect(keys.enabled, isFalse);
      keys.press();
      Navigator.of(context).pop();
      await finishRouteTransition(tester);
      expect(keys.enabled, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(keys.enabled, isFalse);
      keys.press();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(keys.enabled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(keys.enabled, isTrue);
      expect(harness.fakeCamera.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(keys.enabled, isFalse);
      keys.press();
      expect(harness.fakeCamera.captures, 0);
    },
  );

  testWidgets('no preview or unavailable camera never intercepts', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester, volumeKeys: keys);
    expect(keys.enabled, isFalse);
    keys.press();
    expect(harness.fakeCamera.captures, 0);
    await ready(tester, harness);
    harness.camera.frame.value = null;
    expect(keys.enabled, isFalse);
    keys.press();
    expect(harness.fakeCamera.captures, 0);
    await tester.pumpWidget(const SizedBox.shrink());

    final unavailable = _UnavailableCamera();
    await pumpViewfinder(tester, volumeKeys: keys, camera: unavailable);
    unavailable.publishFrame((await tester.runAsync(buildTestImage))!);
    await tester.pump();
    expect(keys.enabled, isFalse);
    keys.press();
    expect(unavailable.captures, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
