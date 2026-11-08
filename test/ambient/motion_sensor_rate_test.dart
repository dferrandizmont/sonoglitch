import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_config.dart';
import 'package:sonoglitch/ambient/motion_sensor_rate.dart';
import 'package:sonoglitch/ambient/motion_service.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

/// A sensor of the platform that the test drives.
///
/// The service asks for a new stream when it changes the rate of the
/// sensors, and the sensor remembers the periods it was asked for.
class FakeSensor {
  final _controller = StreamController<AccelSample>.broadcast();

  /// The period the sensor is read with.
  Duration period = AmbientConfig.motionSensorPeriod;

  /// The periods the sensor was asked for, in order.
  final periods = <Duration>[];

  /// The stream of the sensor.
  Stream<AccelSample> get stream => _controller.stream;

  /// Builds the stream of the sensor with the period it is asked for.
  AccelStream streamFor(Duration samplingPeriod) {
    periods.add(samplingPeriod);
    period = samplingPeriod;
    return stream;
  }

  /// Delivers a sample of the sensor.
  void add(AccelSample sample) => _controller.add(sample);

  /// Closes the sensor.
  Future<void> close() => _controller.close();
}

/// A sensor of the platform that counts its active listeners.
///
/// The platform keeps one listener per channel, so a new listener
/// registered before the old one is gone cancels the new one. The fake
/// counts them, so a test can tell that the service never holds two.
class CountingSensor {
  final _controller = StreamController<AccelSample>.broadcast();

  /// How many listeners are reading the sensor right now.
  int active = 0;

  /// The highest number of listeners the sensor ever held.
  int peak = 0;

  /// The periods the sensor was asked for, in order.
  final periods = <Duration>[];

  /// Builds the stream of the sensor with the period it is asked for.
  AccelStream streamFor(Duration samplingPeriod) {
    periods.add(samplingPeriod);
    return Stream<AccelSample>.multi((controller) {
      active++;
      if (active > peak) peak = active;
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        subscription.cancel();
        active--;
      };
    });
  }

  /// Delivers a sample of the sensor.
  void add(AccelSample sample) => _controller.add(sample);

  /// Closes the sensor.
  Future<void> close() => _controller.close();
}

void main() {
  group('the rate of the sensors', () {
    test('it slows down after the quiet period', () {
      final rate = MotionSensorRate();
      var micros = 0;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorPeriod);

      // Two seconds of stillness are not enough.
      micros = 2000000;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorPeriod);
      expect(rate.isQuiet, isFalse);

      // The quiet period is over.
      micros = 3000000;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorQuietPeriod);
      expect(rate.isQuiet, isTrue);

      // And it stays slow while the phone is still.
      micros = 4000000;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorQuietPeriod);
    });

    test('it speeds up at once on the first movement', () {
      final rate = MotionSensorRate();
      var micros = 0;
      rate.observe(0, micros);
      micros = 3000000;
      rate.observe(0, micros);
      expect(rate.isQuiet, isTrue);

      // The phone moves: the fast rate comes back at once.
      micros = 3000020;
      expect(rate.observe(0.2, micros), AmbientConfig.motionSensorPeriod);
      expect(rate.isQuiet, isFalse);

      // The quiet period starts again from the movement.
      micros = 6000000;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorPeriod);
    });

    test('a broken reading does not slow the sensors down', () {
      final rate = MotionSensorRate();
      expect(rate.observe(double.nan, 0), AmbientConfig.motionSensorPeriod);
      expect(rate.isQuiet, isFalse);
    });

    test('a level that oscillates around the threshold keeps the rate', () {
      final rate = MotionSensorRate();
      var micros = 0;
      rate.observe(0, micros);

      // The phone is held in the hand: the level hovers around the threshold
      // and crosses it every now and then. The rate must not change.
      final periods = <Duration>[];
      for (var i = 0; i < 400; i++) {
        micros += 20000;
        final level = i.isEven ? 0.06 : 0.04;
        periods.add(rate.observe(level, micros));
      }

      expect(
        periods.toSet(),
        hasLength(1),
        reason:
            'the rate must not change while the level oscillates around '
            'the threshold',
      );
      expect(periods.last, AmbientConfig.motionSensorPeriod);
      expect(rate.isQuiet, isFalse);
    });

    test('the quiet state is left only above the wake level', () {
      final rate = MotionSensorRate();
      var micros = 0;
      rate.observe(0, micros);
      micros = 3000000;
      expect(rate.observe(0, micros), AmbientConfig.motionSensorQuietPeriod);
      expect(rate.isQuiet, isTrue);

      // A level between the two thresholds keeps the quiet rate.
      micros = 3000020;
      expect(
        rate.observe(0.07, micros),
        AmbientConfig.motionSensorQuietPeriod,
        reason: 'a level below the wake level must not wake the sensors',
      );
      expect(rate.isQuiet, isTrue);
    });

    test(
      'the first reading above the wake level brings the fast rate back',
      () {
        final rate = MotionSensorRate();
        var micros = 0;
        rate.observe(0, micros);
        micros = 3000000;
        rate.observe(0, micros);
        expect(rate.isQuiet, isTrue);

        // The quiet state has been held for its minimum dwell.
        micros = 4000000;
        expect(
          rate.observe(0.2, micros),
          AmbientConfig.motionSensorPeriod,
          reason: 'a real movement brings the fast rate back',
        );
        expect(rate.isQuiet, isFalse);
      },
    );

    test('the quiet state is not entered again right after it was left', () {
      final rate = MotionSensorRate();
      var micros = 0;
      rate.observe(0, micros);
      micros = 3000000;
      rate.observe(0, micros);
      expect(rate.isQuiet, isTrue);

      // The movement comes right after the quiet state was entered: the fast
      // rate comes back at once, so the movement is not missed.
      micros = 3000020;
      expect(
        rate.observe(0.5, micros),
        AmbientConfig.motionSensorPeriod,
        reason: 'the fast rate comes back at once',
      );
      expect(rate.isQuiet, isFalse);

      // The phone is still again, but the quiet state is not entered again
      // during its minimum dwell: the rate does not change twice in a row.
      micros = 3100020;
      expect(
        rate.observe(0, micros),
        AmbientConfig.motionSensorPeriod,
        reason: 'the quiet state is not entered again right away',
      );
      expect(rate.isQuiet, isFalse);

      // After the dwell and the quiet period, the phone is still again and
      // the sensors are read slowly.
      micros = 3200020;
      rate.observe(0, micros);
      micros = 6300020;
      expect(
        rate.observe(0, micros),
        AmbientConfig.motionSensorQuietPeriod,
        reason: 'the quiet state is entered again after the dwell',
      );
    });
  });

  group('the motion service', () {
    late FakeClock clock;
    late FakeSensor accel;
    late FakeSensor gyro;
    late MotionService service;

    setUp(() {
      clock = FakeClock();
      accel = FakeSensor();
      gyro = FakeSensor();
      service = MotionService(
        sampleFactory: accel.streamFor,
        gyroSampleFactory: gyro.streamFor,
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
    });

    tearDown(() async {
      service.stop();
      await accel.close();
      await gyro.close();
    });

    test('the sensors are read slowly after the quiet period', () async {
      service.start();
      expect(accel.periods, [AmbientConfig.motionSensorPeriod]);

      await _read(clock, [
        (accel, const AccelSample(0, 0, 0)),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(seconds: 2));
      expect(
        service.sensorSamplingPeriod,
        AmbientConfig.motionSensorPeriod,
        reason: 'two seconds of stillness are not enough',
      );

      await _read(clock, [
        (accel, const AccelSample(0, 0, 0)),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(seconds: 2));
      expect(
        service.sensorSamplingPeriod,
        AmbientConfig.motionSensorQuietPeriod,
        reason: 'the sensors are read slowly while the phone is still',
      );
      expect(accel.periods.last, AmbientConfig.motionSensorQuietPeriod);
      expect(gyro.periods.last, AmbientConfig.motionSensorQuietPeriod);
    });

    test('the sensors are read fast again on the first movement', () async {
      service.start();
      await _read(clock, [
        (accel, const AccelSample(0, 0, 0)),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(seconds: 4));
      expect(
        service.sensorSamplingPeriod,
        AmbientConfig.motionSensorQuietPeriod,
      );

      // The phone moves.
      await _read(clock, [
        (accel, const AccelSample(5, 0, 0)),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(milliseconds: 200));
      expect(
        service.sensorSamplingPeriod,
        AmbientConfig.motionSensorPeriod,
        reason: 'the fast rate comes back on the first movement',
      );
      expect(accel.periods.last, AmbientConfig.motionSensorPeriod);
      expect(gyro.periods.last, AmbientConfig.motionSensorPeriod);
    });

    test('only one listener is read after the rate changed', () async {
      final countingAccel = CountingSensor();
      final countingGyro = CountingSensor();
      final counted = MotionService(
        sampleFactory: countingAccel.streamFor,
        gyroSampleFactory: countingGyro.streamFor,
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      addTearDown(counted.stop);
      addTearDown(countingAccel.close);
      addTearDown(countingGyro.close);

      counted.start();
      expect(countingAccel.active, 1);
      expect(countingGyro.active, 1);

      // The phone stops moving: the sensors are read again with the quiet
      // period.
      for (var i = 0; i < 200; i++) {
        clock.advance(const Duration(milliseconds: 20));
        countingAccel.add(const AccelSample(0, 0, 0));
        countingGyro.add(const AccelSample(0, 0, 0));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        countingAccel.active,
        1,
        reason: 'the platform keeps one listener per channel',
      );
      expect(countingGyro.active, 1);
      expect(
        countingAccel.peak,
        1,
        reason:
            'the new listener must not be registered before the old one '
            'is gone',
      );
      expect(countingGyro.peak, 1);
    });

    test('only one listener is read after a stop and a start', () async {
      final countingAccel = CountingSensor();
      final countingGyro = CountingSensor();
      final counted = MotionService(
        sampleFactory: countingAccel.streamFor,
        gyroSampleFactory: countingGyro.streamFor,
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      addTearDown(counted.stop);
      addTearDown(countingAccel.close);
      addTearDown(countingGyro.close);

      counted.start();
      expect(countingAccel.active, 1);

      // The viewfinder is hidden and comes back: the sensors are read again.
      counted.stop();
      counted.start();
      await Future<void>.delayed(Duration.zero);

      expect(
        countingAccel.active,
        1,
        reason:
            'the old listener must be gone before the new one is '
            'registered',
      );
      expect(countingGyro.active, 1);
      expect(countingAccel.peak, 1);
      expect(countingGyro.peak, 1);
    });

    test('the value of the movement is the same at both rates', () async {
      // A phone that rests on a table is not perfectly still: a small and
      // constant acceleration, below the threshold of the stillness. It does
      // not turn, so the gyroscope reads zero.
      const resting = AccelSample(0.4, 0, 0);
      service.start();

      // The fast phase: the value settles.
      await _read(clock, [
        (accel, resting),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(seconds: 2));
      final fast = service.level;
      expect(
        fast,
        closeTo(0.8 * 0.4 / AmbientConfig.motionFullScale, 0.0001),
        reason: 'the accelerometer is mapped per second, not per sample',
      );

      // The slow phase: the same movement gives the same value.
      await _read(clock, [
        (accel, resting),
        (gyro, const AccelSample(0, 0, 0)),
      ], forHowLong: const Duration(seconds: 4));
      final slow = service.level;
      expect(
        service.sensorSamplingPeriod,
        AmbientConfig.motionSensorQuietPeriod,
        reason: 'the sensors were read slowly in the second phase',
      );
      expect(
        slow,
        closeTo(fast, 0.0001),
        reason: 'the rate of the sensors does not change the value',
      );
      expect(slow, closeTo(0.8 * 0.4 / AmbientConfig.motionFullScale, 0.0001));
    });

    test('a stream that is given to the service keeps its rate', () async {
      final controller = StreamController<AccelSample>.broadcast();
      final fixed = MotionService(
        samples: controller.stream,
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      );
      addTearDown(fixed.stop);
      addTearDown(controller.close);
      fixed.start();

      for (var i = 0; i < 400; i++) {
        clock.advance(const Duration(milliseconds: 20));
        controller.add(const AccelSample(0, 0, 0));
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        fixed.sensorSamplingPeriod,
        AmbientConfig.motionSensorPeriod,
        reason: 'a stream that is already built cannot change its rate',
      );
      expect(fixed.level, 0);
    });
  });
}

/// Feeds the sensors with their own sample for [forHowLong] of the test
/// clock.
///
/// The sensors deliver a sample every their own period, which is the period
/// the service asked for.
Future<void> _read(
  FakeClock clock,
  List<(FakeSensor, AccelSample)> sensors, {
  required Duration forHowLong,
}) async {
  final until = clock.micros + forHowLong.inMicroseconds;
  while (clock.micros < until) {
    clock.advance(sensors.first.$1.period);
    for (final (sensor, sample) in sensors) {
      sensor.add(sample);
    }
    await Future<void>.delayed(Duration.zero);
  }
}
