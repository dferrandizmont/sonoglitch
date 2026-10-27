import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';

import '../support/fakes.dart';

/// A clock the test moves by hand.
class _FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

AmbientController _build(_FakeClock clock) => AmbientController(
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

void main() {
  test(
    'manual samples are not mixed into the snapshot of an automatic capture',
    () {
      final clock = _FakeClock();
      final controller = _build(clock);

      // 1) Run in automatic mode long enough to have a measured history.
      //    The noise stream is empty, so the measured value stays zero
      //    unless we push a reading.
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 16));
      }
      expect(controller.value.noise, closeTo(0, 1e-9));

      // 2) Switch to manual, set a known value, let the history fill up
      //    with manual ticks.
      controller.setManual(true);
      controller.setManualValues(noise: 1, light: 1, motion: 1);
      for (var i = 0; i < 30; i++) {
        controller.tick();
        clock.advance(const Duration(milliseconds: 16));
      }
      expect(controller.isManual, isTrue);
      expect(controller.value.noise, 1);

      // 3) Switch back to automatic in a silent room. The very next tick
      //    pushes a measured sample (noise = 0). The snapshot must reflect
      //    ONLY measured values, never the manual ones that came before.
      controller.setManual(false);
      controller.tick();
      expect(controller.isManual, isFalse);

      final snapshot = controller.snapshot(const Duration(milliseconds: 1500));
      expect(
        snapshot.noise,
        closeTo(0, 0.05),
        reason:
            'Manual samples must not contaminate the automatic snapshot '
            '(measured ${snapshot.noise}, manual would push it towards 1)',
      );
      expect(
        snapshot.noise,
        lessThan(0.1),
        reason:
            'The manual phase set noise to 1; the snapshot must not '
            'remember it',
      );
      // Sanity: the current value is also measured (zero), not the manual.
      expect(controller.value.noise, closeTo(0, 0.05));
    },
  );

  test('changing the manual values clears the previous manual history', () {
    final clock = _FakeClock();
    final controller = _build(clock);

    controller.setManual(true);
    controller.setManualValues(noise: 0.5);
    controller.tick();
    controller.tick();
    // Switching the value to a different one must clear the old ring,
    // so the snapshot reflects only the new manual value, not an
    // average of the old and the new.
    controller.setManualValues(noise: 0.9);

    final snapshot = controller.snapshot();
    expect(
      snapshot.noise,
      closeTo(0.9, 1e-9),
      reason: 'Only the latest manual value should appear in the snapshot',
    );
  });
}
