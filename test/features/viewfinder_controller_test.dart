import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/camera/volume_keys.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/animation_clock.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_controller.dart';

import '../support/fakes.dart';

/// A screen that only records what the controller asks of it.
class _Host implements ViewfinderHost {
  bool isMounted = true;
  bool isCurrent = true;
  int notifications = 0;
  int flashes = 0;
  bool? pulseArmed;
  final results = <CaptureResult>[];

  @override
  bool get mounted => isMounted;

  @override
  bool get routeIsCurrent => isCurrent;

  @override
  String get cameraErrorMessage => 'The camera could not be started.';

  @override
  void notify() => notifications++;

  @override
  void flashCapture() => flashes++;

  @override
  void syncMomentPulse(bool armed) => pulseArmed = armed;

  @override
  Future<void> pushResult(CaptureResult result) async => results.add(result);
}

/// A volume key that never fires: the controller only needs it to exist.

void main() {
  late DebugLog log;
  late FakeCameraService camera;
  late FakeStyleController styles;
  late AmbientController ambient;
  late AppSettings settings;
  late CaptureMetrics metrics;
  late FakeAnimationClock clock;
  late _Host host;
  late ViewfinderController controller;
  var disposed = false;

  /// Releases the controller inside the test body: the ambient pipeline keeps
  /// a periodic timer and the widget tester refuses to end with one pending.
  void releaseAll() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
    settings.dispose();
    ambient.dispose();
    styles.dispose();
  }

  Future<void> build(WidgetTester tester) async {
    disposed = false;
    log = DebugLog();
    final light = LightService(ambientLight: FakeAmbientLightSource());
    camera = FakeCameraService(light: light, log: log);
    styles = FakeStyleController(log: log);
    ambient = AmbientController(
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      noise: NoiseService(decibelStream: const Stream<double>.empty()),
      motion: MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
      ),
      light: light,
    );
    settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    metrics = CaptureMetrics();
    clock = FakeAnimationClock();
    host = _Host();
    controller = ViewfinderController(
      camera: camera,
      ambient: ambient,
      styles: styles,
      settings: settings,
      capture: metrics,
      log: log,
      host: host,
      clock: clock,
      volumeKeys: const NoopVolumeKeys(),
    )..initialize();
    await tester.pump();
  }

  tearDown(releaseAll);

  testWidgets('a shot freezes the time and opens the result', (tester) async {
    await build(tester);
    final preview = (await tester.runAsync(buildTestImage))!;
    final still = (await tester.runAsync(buildTestImage))!;
    final rendered = (await tester.runAsync(buildTestImage))!;
    addTearDown(rendered.dispose);
    styles.still = rendered;
    camera.publishFrame(preview);

    // The preview is drawn: the clock runs with the animation.
    controller.setPreviewReady(true);
    clock.advance(const Duration(milliseconds: 500));
    final shutterTime = clock.elapsedSeconds;
    camera.still = still;

    await controller.capturePhoto();

    expect(camera.captures, 1);
    expect(styles.times, hasLength(1));
    expect(
      styles.times.single,
      closeTo(shutterTime, 1e-9),
      reason: 'The still is drawn with the time of the preview',
    );
    expect(host.flashes, 1);
    expect(host.results, hasLength(1));
    expect(host.results.single.rendered, same(rendered));
    expect(host.results.single.styleId, styles.style.id);
    expect(metrics.value.animationTime, closeTo(shutterTime, 1e-9));
    expect(controller.capturing, isFalse);
    expect(controller.cameraError, isNull);
    releaseAll();
  });

  testWidgets('a capture without a picture reports the camera error', (
    tester,
  ) async {
    await build(tester);
    camera.still = null;

    await controller.capturePhoto();

    expect(camera.captures, 1);
    expect(host.results, isEmpty);
    expect(controller.cameraError, 'The camera could not be started.');
    expect(controller.capturing, isFalse);
    releaseAll();
  });

  testWidgets('the clock only runs while the preview is visible', (
    tester,
  ) async {
    await build(tester);
    expect(clock.isRunning, isFalse);

    controller.setPreviewReady(true);
    expect(clock.isRunning, isTrue);
    expect(controller.previewActivity.value, isTrue);

    controller.didChangeVisibility(false);
    expect(clock.isRunning, isFalse);
    expect(controller.previewActivity.value, isFalse);

    controller.didChangeVisibility(true);
    expect(clock.isRunning, isTrue);

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(clock.isRunning, isFalse);
    expect(controller.viewfinderActive, isFalse);

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(clock.isRunning, isTrue);
    releaseAll();
  });

  testWidgets('the moment mode arms and disarms with its toggle', (
    tester,
  ) async {
    await build(tester);
    expect(controller.momentArmed, isFalse);

    controller.toggleMoment();
    expect(controller.momentArmed, isTrue);
    expect(host.pulseArmed, isTrue);

    controller.toggleMoment();
    expect(controller.momentArmed, isFalse);
    expect(host.pulseArmed, isFalse);
    releaseAll();
  });
}
