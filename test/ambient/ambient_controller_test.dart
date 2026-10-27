import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';

import '../support/fakes.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

void main() {
  group('AmbientController', () {
    late FakeClock clock;
    late NoiseService noise;
    late MotionService motion;
    late LightService light;
    late AmbientController controller;

    setUp(() {
      clock = FakeClock();
      noise = NoiseService(
        decibelStream: const Stream<double>.empty(),
        clock: clock.call,
      );
      motion = MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      light = LightService(
        ambientLight: FakeAmbientLightSource(),
        clock: clock.call,
      );
      controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: noise,
        motion: motion,
        light: light,
        clock: clock.call,
      );
    });

    test('publishes the state of the three sources', () {
      noise.addReading(100);
      motion.addSample(const AccelSample(10, 0, 0));
      light.addLuma(255);
      controller.tick();

      expect(controller.value.noise, greaterThan(0));
      expect(controller.value.light, greaterThan(0));
      expect(controller.value.motion, greaterThan(0));
      expect(controller.value.rawDb, 100);
      expect(controller.value.rawLuma, 255);
    });

    test('the snapshot preserves the high percentile of noise', () {
      // A loud moment followed by a quiet one.
      noise.addReading(100);
      controller.tick();
      final loud = controller.value.noise;
      clock.advance(const Duration(milliseconds: 100));
      noise.addReading(35);
      controller.tick();
      final quiet = controller.value.noise;

      final snapshot = controller.snapshot(const Duration(seconds: 1));
      // Nearest-rank P90 of two samples selects the larger, not their mean.
      expect(snapshot.noise, closeTo(loud > quiet ? loud : quiet, 0.0001));
    });

    test('the snapshot ignores the samples outside the window', () {
      noise.addReading(100);
      controller.tick();
      clock.advance(const Duration(seconds: 5));
      noise.addReading(35);
      controller.tick();

      final snapshot = controller.snapshot(const Duration(milliseconds: 500));
      // Only the quiet sample is inside the window.
      expect(snapshot.noise, closeTo(controller.value.noise, 0.0001));
    });

    test('the snapshot of an empty window is the current state', () {
      noise.addReading(100);
      controller.tick();
      final snapshot = controller.snapshot(const Duration(milliseconds: 1));
      expect(snapshot.noise, controller.value.noise);
    });

    test('the default window is one second and a half', () {
      noise.addReading(100);
      controller.tick();
      clock.advance(const Duration(milliseconds: 1400));
      noise.addReading(35);
      controller.tick();

      // The first sample is still inside the default window.
      final snapshot = controller.snapshot();
      expect(snapshot.noise, greaterThan(controller.value.noise));
    });

    test('the history is bounded', () {
      for (var i = 0; i < 1000; i++) {
        noise.addReading(100);
        controller.tick();
        clock.advance(const Duration(milliseconds: 33));
      }
      // The old samples fall out of the window, so the snapshot only sees the
      // recent ones. The learned ceiling makes steady 100 dB full scale:
      // 1^0.7 = 1 in Normal intensity (previous weighted cap was 0.65).
      final snapshot = controller.snapshot(const Duration(milliseconds: 1500));
      expect(snapshot.noise, closeTo(1, 0.05));
    });

    test('the timer merges on its own', () async {
      controller.start();
      expect(controller.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      controller.stop();
      expect(controller.isRunning, isFalse);
    });
  });

  group('the manual mode of the controller', () {
    test('gives exactly the values that were set', () {
      final clock = FakeClock();
      final controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: NoiseService(
          decibelStream: const Stream<double>.empty(),
          clock: clock.call,
        ),
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        ),
        light: LightService(
          ambientLight: FakeAmbientLightSource(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      expect(controller.isManual, isFalse);

      controller.setManual(true);
      controller.setManualValues(noise: 0.9, light: 0.1, motion: 0);

      expect(controller.isManual, isTrue);
      expect(controller.value.noise, 0.9);
      expect(controller.value.light, 0.1);
      expect(controller.value.motion, 0);
    });

    test('the snapshot gives the values that were set', () {
      final clock = FakeClock();
      final controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: NoiseService(
          decibelStream: const Stream<double>.empty(),
          clock: clock.call,
        ),
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        ),
        light: LightService(
          ambientLight: FakeAmbientLightSource(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      controller.setManual(true);
      controller.setManualValues(noise: 0.75, light: 0.25, motion: 0.5);

      expect(controller.snapshot().noise, 0.75);
      expect(controller.snapshot().light, 0.25);
      expect(controller.snapshot().motion, 0.5);
    });

    test('the measured values come back when it is turned off', () {
      final clock = FakeClock();
      final noise = NoiseService(
        decibelStream: const Stream<double>.empty(),
        clock: clock.call,
      );
      final controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: noise,
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        ),
        light: LightService(
          ambientLight: FakeAmbientLightSource(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      controller.setManual(true);
      controller.setManualValues(noise: 0.9);
      expect(controller.value.noise, 0.9);

      controller.setManual(false);
      expect(controller.isManual, isFalse);
      expect(controller.value.noise, 0);
    });

    test('manual history does not contaminate the auto snapshot', () {
      // The history built while the controller is in manual mode must not
      // leak into a capture taken right after switching back to automatic:
      // both the current value and the snapshot must reflect only the
      // measured samples that follow the transition.
      final clock = FakeClock();
      final noise = NoiseService(
        decibelStream: const Stream<double>.empty(),
        clock: clock.call,
      );
      final controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: noise,
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        ),
        light: LightService(
          ambientLight: FakeAmbientLightSource(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      // Drive the manual mode hard: set the noise to its top, tick a few
      // times so the ring fills up with manual samples.
      controller.setManual(true);
      controller.setManualValues(noise: 1);
      for (var i = 0; i < 5; i++) {
        controller.tick();
        clock.advance(const Duration(milliseconds: 33));
      }
      expect(controller.snapshot().noise, closeTo(1, 0.0001));

      // Switch back to automatic and tick again. The new sample is silence.
      controller.setManual(false);
      expect(controller.value.noise, 0);
      // The snapshot window (1500 ms by default) covers the manual samples
      // we just generated, so without dropping the history at the transition
      // the snapshot would still average them in.
      expect(controller.snapshot().noise, closeTo(0, 0.0001));
    });

    test('the values are clamped to the scale of the controls', () {
      final clock = FakeClock();
      final controller = AmbientController(
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        noise: NoiseService(
          decibelStream: const Stream<double>.empty(),
          clock: clock.call,
        ),
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        ),
        light: LightService(
          ambientLight: FakeAmbientLightSource(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      controller.setManualValues(noise: 2, light: -1, motion: 0.5);
      expect(controller.manualNoise, 1);
      expect(controller.manualLight, 0);
      expect(controller.manualMotion, 0.5);
    });
  });
}
