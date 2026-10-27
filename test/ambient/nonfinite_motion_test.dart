import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/motion_service.dart';

/// A clock the test moves by hand.
class _FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

void main() {
  group('MotionService rejects non-finite samples', () {
    test('a NaN sample does not poison later finite readings', () async {
      final clock = _FakeClock();
      final service = MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );

      // A well-formed reading seeds the smoothers.
      service.addSample(const AccelSample(3, 4, 0));
      clock.advance(const Duration(milliseconds: 16));
      expect(service.dirX.isFinite, isTrue);
      expect(service.dirY.isFinite, isTrue);
      expect(service.rawAccel.isFinite, isTrue);
      final baselineX = service.dirX;
      final baselineY = service.dirY;
      final baselineRaw = service.rawAccel;

      // A broken reading is rejected: nothing must change.
      service.addSample(AccelSample(double.nan, 4, 0));
      clock.advance(const Duration(milliseconds: 16));
      expect(service.dirX, closeTo(baselineX, 1e-9));
      expect(service.dirY, closeTo(baselineY, 1e-9));
      expect(service.rawAccel, closeTo(baselineRaw, 1e-9));

      // The smoothers and the raw reading recover to the new finite
      // reading without dragging the NaN along.
      service.addSample(const AccelSample(1, 2, 0));
      clock.advance(const Duration(milliseconds: 16));
      expect(service.dirX.isFinite, isTrue);
      expect(service.dirY.isFinite, isTrue);
      expect(service.rawAccel.isFinite, isTrue);

      // An infinity in an axis is rejected too.
      service.addSample(const AccelSample(1, double.infinity, 0));
      clock.advance(const Duration(milliseconds: 16));
      expect(service.dirY.isFinite, isTrue);
    });
  });
}
