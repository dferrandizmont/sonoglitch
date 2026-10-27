import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_config.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/scene_motion.dart';
import 'package:sonoglitch/ambient/signal_intensity.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/diagnostic_report.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/export/export_capture_timings.dart';

import '../support/fakes.dart';
import 'noise_service_test.dart' show FakeClock, feed, buildService;

MotionService fakeMotion(FakeClock clock, {AccelStream? gyro}) => MotionService(
  samples: const Stream<AccelSample>.empty(),
  gyroSamples: gyro ?? const Stream<AccelSample>.empty(),
  gravitySamples: const Stream<AccelSample>.empty(),
  clock: clock.call,
);

/// A wrapped gradient has visible edges, unlike an unbounded linear ramp whose
/// translation is mathematically indistinguishable from a brightness change.
List<double> gradient({int dx = 0, int dy = 0, double brightness = 0}) => [
  for (var y = 0; y < AmbientConfig.sceneRows; y++)
    for (var x = 0; x < AmbientConfig.sceneColumns; x++)
      30.0 + (((x - dx) * 17 + (y - dy) * 31) % 180) + brightness,
];

Uint8List rgba(List<double> grid) => Uint8List.fromList([
  for (final value in grid) ...[
    value.round(),
    value.round(),
    value.round(),
    255,
  ],
]);

void main() {
  test('photo direction rotates with the photo without changing scalars', () {
    const state = AmbientState(
      noise: 0.8,
      light: 0.4,
      motion: 0.6,
      motionDirX: 1,
      motionDirY: 0,
      sceneMotion: 0.6,
      gyroMotion: 0.2,
      accelMotion: 0.1,
      rawGyro: 0.5,
      noiseCeilingDb: 80,
    );
    for (final (turns, expectedX, expectedY) in [
      (0, 1, 0),
      (1, 0, -1),
      (2, -1, 0),
      (3, 0, 1),
    ]) {
      final photo = state.forPhotoTurns(turns);
      expect((photo.motionDirX, photo.motionDirY), (expectedX, expectedY));
      expect({
        ...photo.toJson(),
        'motionDirX': 1.0,
        'motionDirY': 0.0,
      }, state.toJson());
    }
  });

  test(
    'ceiling learns the session peak, decays over ten minutes, has a floor',
    () {
      final clock = FakeClock();
      final noise = buildService(clock);
      expect(noise.ceilingDb, 73);
      feed(noise, clock, 80, const Duration(seconds: 2));
      expect(noise.ceilingDb, 80);
      expect(noise.level, closeTo(1, 0.001));
      clock.advance(const Duration(minutes: 10));
      noise.addReading(40);
      // Exponential ten-minute time constant: 72 + (80-72)/e = 74.943 dB.
      expect(noise.ceilingDb, closeTo(72 + 8 / math.e, 0.001));
      clock.advance(const Duration(hours: 10));
      noise.addReading(40);
      expect(noise.ceilingDb, closeTo(noise.floorDb + 15, 1e-9));
      final otherSession = buildService(clock);
      expect(otherSession.ceilingDb, 73);
    },
  );

  test('noise floor/ceiling and each intensity curve are explicit', () {
    expect(NoiseService.mapDecibels(40), 0);
    expect(NoiseService.mapDecibels(62), closeTo(0.12066, 0.001));
    expect(NoiseService.mapDecibels(80, ceilingDb: 80), 1);
    // pow(0.25,gamma)*gain: 0.2125 / 0.378929... / 0.575.
    expect(SignalIntensity.subtle.apply(0.25), closeTo(0.2125, 1e-9));
    expect(SignalIntensity.normal.apply(0.25), closeTo(0.3789291416, 1e-9));
    expect(SignalIntensity.extreme.apply(0.25), closeTo(0.575, 1e-9));
    for (final intensity in SignalIntensity.values) {
      expect(intensity.apply(0), 0);
      expect(intensity.apply(-1), 0);
      expect(intensity.apply(double.nan), 0);
    }
    expect(SignalIntensity.subtle.apply(1), 0.85);
    expect(SignalIntensity.extreme.apply(1), 1);
  });

  test('merge curves noise/motion only; snapshot uses P90 and mean light', () {
    final clock = FakeClock();
    final noise = buildService(clock);
    final motion = fakeMotion(clock);
    final light = LightService(ambientLight: FakeAmbientLightSource());
    final ambient = AmbientController(
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      noise: noise,
      motion: motion,
      light: light,
      clock: clock.call,
    );
    for (final intensity in SignalIntensity.values) {
      ambient.setIntensity(intensity);
      ambient.clearHistory();
      for (var i = 0; i < 10; i++) {
        noise.smoother.reset(i / 10);
        // Undo the 0.8 acceleration weight to arrange a known motion window.
        motion.magnitude.reset(i / 10 / 0.8);
        motion.directionX.reset(i.isEven ? 1 : -1);
        light.smoother.reset(i / 10);
        ambient.tick();
        clock.advance(const Duration(milliseconds: 100));
      }
      final snapshot = ambient.snapshot();
      // Nearest rank ceil(10*0.9)-1 = index 8: raw P90=0.8, mean=0.45.
      expect(snapshot.noise, closeTo(intensity.apply(0.8), 1e-9));
      expect(snapshot.motion, closeTo(intensity.apply(0.8), 1e-9));
      expect(snapshot.light, closeTo(0.45, 1e-9));
      expect(snapshot.noise, greaterThan(intensity.apply(0.45)));
      expect(snapshot.motionDirX, 1, reason: 'direction of the selected peak');
      final capture = CaptureMetrics()..update(ambient: snapshot, takeMs: 12);
      capture.update(encodeMs: 8);
      capture.value = ExportCaptureTimings(capture.value, {'width': 100});
      final report = DiagnosticReport.build(
        ambient: ambient.value,
        metrics: const CameraMetricsData(),
        styleId: 'static',
        timings: capture.value,
        device: const DeviceSummary(
          model: 'fake',
          systemVersion: 'fake',
          platform: 'test',
        ),
        appVersion: 'test',
        buildMode: 'test',
        logs: [],
      );
      final lastCapture = report['lastCapture']! as Map<String, Object?>;
      expect(lastCapture['ambient'], snapshot.toJson());
      expect(
        snapshot.toJson().keys,
        containsAll([
          'sceneMotion',
          'gyroMotion',
          'accelMotion',
          'rawGyro',
          'noiseCeilingDb',
        ]),
      );
      capture.dispose();
    }
    ambient.dispose();
  });

  test(
    'scene motion ignores identical frames and global brightness changes',
    () {
      final scene = SceneMotion();
      scene.addGrid(gradient());
      scene.addGrid(gradient());
      expect(scene.level, closeTo(0, 1e-9));
      scene.addGrid(gradient(brightness: 20));
      expect(scene.difference, closeTo(0, 1e-9));
      expect(scene.level, 0);
      expect((scene.dx, scene.dy), (0, 0));
    },
  );

  for (final shift in [(2, 0), (-2, 0), (0, 2), (0, -2)]) {
    test('scene gradient shift $shift gives matching screen direction', () {
      final scene = SceneMotion();
      scene.addGrid(gradient());
      scene.addGrid(gradient(dx: shift.$1, dy: shift.$2));
      expect(scene.level, greaterThan(0.5));
      expect(scene.dx, closeTo(shift.$1.sign.toDouble(), 1e-9));
      expect(scene.dy, closeTo(-shift.$2.sign.toDouble(), 1e-9));
    });
  }

  test(
    'scene fast attack, slower release, stale decay and comparison reset',
    () {
      final clock = FakeClock();
      final motion = fakeMotion(clock);
      void frame(int dx) => motion.addSceneFrame(
        rgba(gradient(dx: dx)),
        AmbientConfig.sceneColumns,
        AmbientConfig.sceneRows,
      );
      frame(0);
      clock.advance(const Duration(milliseconds: 60));
      frame(2);
      final peak = motion.sceneLevel;
      expect(peak, closeTo(1 - 1 / math.e, 0.001));
      expect(motion.dirX, 1);
      expect(motion.level, peak);
      clock.advance(const Duration(milliseconds: 60));
      frame(2);
      expect(motion.sceneLevel, closeTo(peak * math.exp(-0.06 / 0.5), 0.001));
      expect(motion.dirX, 1, reason: 'release preserves its direction');
      clock.advance(const Duration(seconds: 5));
      expect(motion.sceneLevel, lessThan(0.001));
      motion.resetScene();
      frame(0);
      expect(
        motion.sceneLevel,
        0,
        reason: 'first frame after reset has no delta',
      );
    },
  );

  test(
    'gyro mapping, dominant axes, finite guards and dominant-source fusion',
    () {
      expect(MotionService.mapGyroscope(0.15), 0);
      expect(MotionService.mapGyroscope(1.075), closeTo(0.5, 1e-9));
      expect(MotionService.mapGyroscope(2), 1);
      expect(MotionService.mapGyroscope(double.infinity), 0);
      final clock = FakeClock();
      final motion = fakeMotion(clock);
      motion.addGyroSample(const AccelSample(0, 2, 0));
      clock.advance(const Duration(milliseconds: 480));
      motion.addGyroSample(const AccelSample(0, 2, 0));
      expect(motion.gyroLevel, greaterThan(0.98));
      expect(motion.level, motion.gyroLevel);
      expect((motion.dirX, motion.dirY), (1, 0));
      motion.addGyroSample(const AccelSample(double.nan, 0, 0));
      expect(motion.rawGyro, 2);
      clock.advance(const Duration(seconds: 5));
      motion.addGyroSample(const AccelSample(2, 0, 0));
      expect(motion.dirX, closeTo(0, 0.001));
      expect(motion.dirY, closeTo(-1, 0.001));
      clock.advance(const Duration(seconds: 5));
      motion.addGyroSample(const AccelSample(0, 0, -2));
      expect(motion.dirX, closeTo(-1, 0.001));
      expect(motion.dirY, closeTo(0, 0.001));
      clock.advance(const Duration(milliseconds: 20));
      motion.addGyroSample(const AccelSample(0, 0, 0));
      expect(
        motion.dirX,
        closeTo(-1, 0.001),
        reason: 'gyro release keeps its direction',
      );
      clock.advance(const Duration(seconds: 5));
      expect(motion.gyroLevel, lessThan(0.001));
    },
  );

  test('gravity stream lifecycle tolerates missing sensors', () async {
    final clock = FakeClock();
    final gravity = StreamController<AccelSample>();
    final gyro = StreamController<AccelSample>();
    final accel = StreamController<AccelSample>();
    final motion = MotionService(
      samples: accel.stream,
      gyroSamples: gyro.stream,
      gravitySamples: gravity.stream,
      clock: clock.call,
    );
    motion.start();
    motion.start();
    expect(gravity.hasListener, isTrue);
    for (var i = 0; i < 20; i++) {
      clock.advance(const Duration(milliseconds: 100));
      gravity.add(const AccelSample(9.8, 0, 0));
      await Future<void>.delayed(Duration.zero);
    }
    expect(motion.orientation.value.quarterTurns, 3);
    gravity.addError(StateError('gravity unavailable'));
    gyro.addError(StateError('gyro unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(motion.orientation.value.quarterTurns, 3);
    expect(motion.gyroLevel, 0);
    motion.stop();
    motion.stop();
    await Future<void>.delayed(Duration.zero);
    expect(
      [gravity.hasListener, gyro.hasListener, accel.hasListener],
      [false, false, false],
    );
    await gravity.close();
    await gyro.close();
    await accel.close();
  });

  test('missing/erroring gyro leaves scene and acceleration working, stops subscriptions', () async {
    final clock = FakeClock();
    final gyro = StreamController<AccelSample>();
    final motion = fakeMotion(clock, gyro: gyro.stream);
    motion.start();
    gyro.add(const AccelSample(0, 2, 0));
    await Future<void>.delayed(Duration.zero);
    gyro.addError(StateError('gyroscope absent'));
    await Future<void>.delayed(Duration.zero);
    expect(motion.gyroLevel, 0);
    expect(motion.rawGyro, isNull);
    motion.addSample(const AccelSample(20, 0, 0));
    clock.advance(const Duration(seconds: 5));
    motion.addSample(const AccelSample(20, 0, 0));
    expect(motion.level, closeTo(0.8, 0.001));
    expect(motion.dirX, greaterThan(0));
    motion.resetScene();
    motion.addSceneFrame(rgba(gradient()), 32, 24);
    clock.advance(const Duration(milliseconds: 300));
    motion.addSceneFrame(rgba(gradient(dx: -2)), 32, 24);
    expect(motion.sceneLevel, greaterThan(0.99));
    expect(motion.level, motion.sceneLevel);
    expect(
      motion.dirX,
      inExclusiveRange(-1, 0),
      reason: 'dominance transition is smoothed',
    );
    motion.stop();
    await Future<void>.delayed(Duration.zero);
    expect(gyro.hasListener, isFalse);
    await gyro.close();
  });
}
