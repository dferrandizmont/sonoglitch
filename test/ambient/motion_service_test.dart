import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/motion_service.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

void main() {
  group('the mapping of the acceleration', () {
    test('a still phone is zero', () {
      expect(MotionService.mapAcceleration(0), 0);
      expect(MotionService.mapAcceleration(-2), 0);
    });

    test('the full scale saturates', () {
      expect(MotionService.mapAcceleration(20), 1);
      expect(MotionService.mapAcceleration(40), 1);
    });

    test('is linear in between', () {
      expect(MotionService.mapAcceleration(10), closeTo(0.5, 0.0001));
      expect(MotionService.mapAcceleration(5), closeTo(0.25, 0.0001));
    });

    test('a broken reading is zero', () {
      expect(MotionService.mapAcceleration(double.nan), 0);
    });
  });

  group('the rotation into the screen space', () {
    test('portrait keeps the axes', () {
      final (x, y) = rotateToScreen(3, 4, 0);
      expect(x, 3);
      expect(y, 4);
    });

    test('a quarter turn swaps and flips the axes', () {
      final (x, y) = rotateToScreen(3, 4, 1);
      expect(x, 4);
      expect(y, -3);
    });

    test('half a turn flips both axes', () {
      final (x, y) = rotateToScreen(3, 4, 2);
      expect(x, -3);
      expect(y, -4);
    });

    test('three quarter turns swap the axes the other way', () {
      final (x, y) = rotateToScreen(3, 4, 3);
      expect(x, -4);
      expect(y, 3);
    });

    test('more than a full turn is the same as none', () {
      final (x, y) = rotateToScreen(3, 4, 4);
      expect(x, 3);
      expect(y, 4);
    });
  });

  group('MotionService', () {
    test('measures the magnitude of the movement', () {
      final clock = FakeClock();
      final service = MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      service.addSample(const AccelSample(3, 4, 0));
      expect(service.rawAccel, closeTo(5, 0.0001));
      expect(service.level, greaterThan(0));

      clock.advance(const Duration(seconds: 5));
      service.addSample(const AccelSample(3, 4, 0));
      // Accelerometer fallback is now weighted 0.8: (5/20)*0.8 = 0.20.
      expect(service.level, closeTo(0.20, 0.01));
    });

    test('a nonfinite sample is rejected without poisoning later readings', () {
      final clock = FakeClock();
      final service = MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );

      // The first call seeds the smoother with a known value so we can prove
      // the nonfinite one is dropped instead of polluting it.
      service.addSample(const AccelSample(2, 0, 0));
      final beforeX = service.dirX;
      expect(beforeX.isFinite, isTrue);

      // One invalid sample in any axis (here NaN in x) must not change any
      // public state: the magnitude, the smoothed level and the directions
      // stay at their previous finite values.
      service.addSample(const AccelSample(double.nan, 0, 0));
      expect(service.rawAccel, closeTo(2, 0.0001));
      expect(service.dirX, beforeX);
      expect(service.dirX.isFinite, isTrue);
      expect(service.dirY.isFinite, isTrue);
      expect(service.level.isFinite, isTrue);

      // The same guard rejects infinity in any axis too.
      service.addSample(const AccelSample(0, 0, double.infinity));
      expect(service.rawAccel, closeTo(2, 0.0001));
      expect(service.dirX, beforeX);
      expect(service.dirX.isFinite, isTrue);
      expect(service.dirY.isFinite, isTrue);

      // A later valid sample settles to its target with no trace of NaN.
      clock.advance(const Duration(seconds: 5));
      service.addSample(const AccelSample(2, 0, 0));
      expect(service.dirX.isFinite, isTrue);
      expect(service.dirY.isFinite, isTrue);
      expect(service.dirX, closeTo(2, 0.05));
      expect(service.dirY, closeTo(0, 0.05));
      expect(service.rawAccel.isFinite, isTrue);
    });

    test('keeps the direction of the movement', () {
      final clock = FakeClock();
      final service = MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      service.addSample(const AccelSample(2, 0, 0));
      clock.advance(const Duration(seconds: 5));
      service.addSample(const AccelSample(2, 0, 0));
      expect(service.dirX, closeTo(2, 0.05));
      expect(service.dirY, closeTo(0, 0.05));
    });

    test('reads the samples of the stream when it is started', () async {
      final controller = StreamController<AccelSample>();
      final service = MotionService(
        samples: controller.stream,
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
      );
      service.start();
      controller.add(const AccelSample(1, 0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(service.rawAccel, closeTo(1, 0.0001));
      service.stop();
      await controller.close();
    });
  });
}
