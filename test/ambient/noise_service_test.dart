import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/noise_service.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

/// The period between two readings of the microphone.
const sampleStep = Duration(milliseconds: 20);

/// Feeds the same level during [duration], as the microphone would.
void feed(NoiseService service, FakeClock clock, double db, Duration duration) {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    service.addReading(db);
    clock.advance(sampleStep);
    elapsed += sampleStep;
  }
}

/// A service that reads a stream the test drives.
NoiseService buildService(FakeClock clock) => NoiseService(
  decibelStream: const Stream<double>.empty(),
  clock: clock.call,
);

void main() {
  group('the mapping of the decibels', () {
    // Session calibration starts at 58 dB with at least 15 dB of headroom.
    test('ignores anything below the floor', () {
      expect(NoiseService.mapDecibels(39), 0);
      expect(NoiseService.mapDecibels(0), 0);
      expect(NoiseService.mapDecibels(-10), 0);
    });

    test('the floor is exactly zero', () {
      expect(NoiseService.mapDecibels(58), 0);
    });

    test('the ceiling is exactly one', () {
      expect(NoiseService.mapDecibels(73), 1);
    });

    test('anything above the ceiling is one', () {
      expect(NoiseService.mapDecibels(120), 1);
    });

    test(
      'the quiet-end knee suppresses small changes without hiding loudness',
      () {
        expect(NoiseService.mapDecibels(62), closeTo(0.12066, 0.001));
        expect(NoiseService.mapDecibels(70), closeTo(0.69975, 0.001));
      },
    );

    test('a broken reading is zero', () {
      expect(NoiseService.mapDecibels(double.nan), 0);
    });
  });

  group('NoiseService', () {
    test('smooths the readings', () {
      final clock = FakeClock();
      final service = buildService(clock);

      service.addReading(100);
      expect(service.rawDb, 100);
      // The first sample only moves a little: the smoother starts at zero.
      expect(service.level, greaterThan(0));
      expect(service.level, lessThan(1));

      clock.advance(const Duration(seconds: 5));
      service.addReading(100);
      // The learned ceiling is 100: absolute noise can now reach 1.0 even
      // after the baseline settles, instead of the old 0.65 weighted cap.
      expect(service.level, closeTo(1.0, 0.01));
    });

    test('keeps the raw reading even when it is below the floor', () {
      final clock = FakeClock();
      final service = buildService(clock);
      service.addReading(30);
      expect(service.rawDb, 30);
      expect(service.level, 0);
    });

    test('a silent room does not break the smoothing', () {
      final clock = FakeClock();
      final service = buildService(clock);
      service.addReading(double.negativeInfinity);
      expect(service.rawDb, 0);
      expect(service.level, 0);
    });

    test('reads the readings of the stream when it is started', () async {
      final controller = StreamController<double>();
      final clock = FakeClock();
      final service = NoiseService(
        decibelStream: controller.stream,
        clock: clock.call,
      );
      service.start();
      controller.add(70);
      await Future<void>.delayed(Duration.zero);
      expect(service.rawDb, 70);
      service.stop();
      await controller.close();
    });

    test('does not touch the microphone when it is disabled', () async {
      final controller = StreamController<double>.broadcast();
      final service = NoiseService(
        decibelStream: controller.stream,
        enabled: false,
      );
      service.start();
      controller.add(70);
      await Future<void>.delayed(Duration.zero);
      expect(service.rawDb, isNull);
      expect(service.level, 0);
      service.stop();
      await controller.close();
    });
  });

  group('the noise of a place', () {
    test('a quiet room of 65 dB keeps a steady value', () {
      final clock = FakeClock();
      final service = buildService(clock);

      feed(service, clock, 65, const Duration(seconds: 30));

      // The quiet reference moves slowly; this is already much lower than
      // the old 0.78125, and continued quiet calibrates it down towards zero.
      expect(service.level, lessThan(0.25));
      feed(service, clock, 65, const Duration(minutes: 5));
      expect(service.level, lessThan(0.03));
      // The baseline follows the level of the place.
      expect(service.baselineDb, closeTo(65, 0.5));
      // Nothing stands over the baseline, so there is no burst.
      expect(service.burst, closeTo(0, 0.01));
    });

    test('a quiet room of 40 dB is silence', () {
      final clock = FakeClock();
      final service = buildService(clock);

      feed(service, clock, 40, const Duration(seconds: 30));

      // 40 dB stays below even the lowest permitted session floor.
      expect(service.level, closeTo(0, 0.01));
      expect(service.burst, closeTo(0, 0.01));
    });

    test('a loud street of 85 dB stays high', () {
      final clock = FakeClock();
      final service = buildService(clock);

      feed(service, clock, 85, const Duration(seconds: 30));

      // The ceiling learns 85 dB, making this place full scale instead of
      // the old fixed-ceiling weighted value 0.578.
      expect(service.level, closeTo(1.0, 0.01));
      expect(service.burst, closeTo(0, 0.01));
    });

    test('a shout of 25 dB over the baseline reaches the top', () {
      final clock = FakeClock();
      final service = buildService(clock);

      // A room of 65 dB, so the baseline is settled.
      feed(service, clock, 65, const Duration(seconds: 2));
      final quiet = service.level;

      // The shout.
      feed(service, clock, 90, const Duration(milliseconds: 150));

      // The shout has to be at the top of the scale in a fraction of a
      // second: the burst alone is 0.944 and the absolute part is full.
      // The measured values are 0.990 of noise and 0.913 of burst.
      expect(service.level, greaterThan(0.9));
      expect(service.burst, greaterThan(0.9));
      expect(service.level, greaterThan(quiet));

      // And it has to fall again when the shout ends.
      feed(service, clock, 65, const Duration(milliseconds: 2850));
      // The shout releases back towards the calibrated quiet-room value.
      expect(service.level, lessThan(0.12));
    });

    test('the burst falls slowly after the shout', () {
      final clock = FakeClock();
      final service = buildService(clock);

      feed(service, clock, 65, const Duration(seconds: 2));
      feed(service, clock, 90, const Duration(milliseconds: 200));
      expect(service.burst, greaterThan(0.9));

      // The burst is still there a moment later, it does not cut off: it
      // measures 0.444 three hundred milliseconds after the shout.
      feed(service, clock, 65, const Duration(milliseconds: 300));
      expect(service.burst, greaterThan(0.4));

      // But it is gone after a few seconds.
      feed(service, clock, 65, const Duration(seconds: 3));
      expect(service.burst, lessThan(0.1));
    });

    test('the baseline does not follow a shout', () {
      final clock = FakeClock();
      final service = buildService(clock);

      feed(service, clock, 65, const Duration(seconds: 2));
      final baseline = service.baselineDb!;

      feed(service, clock, 95, const Duration(seconds: 1));

      // The baseline is slow: twenty seconds of time constant, so a second
      // of shouting barely moves it.
      expect(service.baselineDb, closeTo(baseline, 1.5));
    });

    test('the baseline is measured with the first second of data', () {
      final clock = FakeClock();
      final service = buildService(clock);

      // Half a second of 65 dB and half a second of 70 dB: the mean is the
      // first value of the baseline.
      feed(service, clock, 65, const Duration(milliseconds: 500));
      feed(service, clock, 70, const Duration(milliseconds: 500));

      expect(service.baselineDb, closeTo(67.5, 0.5));
    });
  });
}
