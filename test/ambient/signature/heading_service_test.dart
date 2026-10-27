import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/signature/heading_service.dart';

const upright = (x: 0.0, y: 9.81, z: 0.0);
const east = (x: -50.0, y: 0.0, z: 0.0);
const west = (x: 50.0, y: 0.0, z: 0.0);

void main() {
  test('back optical axis works upright for known magnetic bearings', () {
    for (final entry in [
      ((x: 0.0, y: 0.0, z: -50.0), 0.0),
      (east, math.pi / 2),
      (west, -math.pi / 2),
    ]) {
      final value = opticalAxis(entry.$1, upright);
      expect(value.heading, closeTo(entry.$2, 1e-12));
      expect(value.reliability, closeTo(1, 1e-12));
      expect(value.x * value.x + value.y * value.y, closeTo(1, 1e-12));
    }
    final south = opticalAxis((x: 0, y: 0, z: 50), upright);
    expect(south.heading.abs(), closeTo(math.pi, 1e-12));
    // Screen roll changes gravity and field components, not optical heading.
    final rolled = opticalAxis((x: 0, y: 50, z: 0), (x: 9.81, y: 0, z: 0));
    expect(rolled.heading, closeTo(math.pi / 2, 1e-12));
  });
  test('flat postures and invalid/unstable gravity are neutral', () {
    for (final g in [
      (x: 0.0, y: 0.0, z: 9.81),
      (x: 0.0, y: 0.0, z: -9.81),
      (x: 0.0, y: 0.0, z: 0.0),
      (x: 0.0, y: 15.0, z: 0.0),
    ]) {
      final value = opticalAxis(east, g);
      expect(value.reliability, 0);
      expect(value.x, 1);
      expect(value.y, 0);
    }
    for (final magnitude in [0.0, 19.9, 70.1, double.nan, double.infinity]) {
      expect(opticalAxis((x: magnitude, y: 0, z: 0), upright).reliability, 0);
    }
    expect(opticalAxis((x: 0, y: 50, z: 0), upright).reliability, 0);
    expect(opticalAxis(east, (x: double.nan, y: 0, z: 0)).reliability, 0);
    // Approaching nadir attenuates continuously before full degeneracy.
    final partial = opticalAxis(east, (
      x: 0,
      y: 9.81 * .25,
      z: 9.81 * math.sqrt(1 - .25 * .25),
    ));
    expect(partial.reliability, closeTo(.5, 1e-12));
  });
  test('tilt compensation agrees at multiple camera elevations', () {
    for (final angle in [-.8, -.4, 0.0, .4, .8]) {
      final g = (x: 0.0, y: 9.81 * math.cos(angle), z: 9.81 * math.sin(angle));
      final heading = opticalAxis(east, g);
      expect(heading.heading, closeTo(math.pi / 2, 1e-12));
      expect(heading.reliability, closeTo(1, 1e-12));
    }
  });
  test('sin/cos smoothing, unit axis, stale fade, and recovery', () {
    var now = 0;
    TimedGravity? gravity;
    final service = HeadingService(gravity: () => gravity, clock: () => now);
    expect(service.axis, (x: 1.0, y: 0.0));
    for (var i = 0; i <= 8; i++) {
      now = i * 100000;
      gravity = (vector: upright, timeMicros: now);
      service.add(east);
    }
    final delta = math.pi / 15 * (1 - math.exp(-1));
    expect(service.axis.y, closeTo(math.sin(delta), 1e-12));
    expect(
      service.axis.x * service.axis.x + service.axis.y * service.axis.y,
      closeTo(1, 1e-12),
    );
    now += 900000;
    expect(service.axis.y, closeTo(math.sin(delta * .5), 1e-12));
    now += 100001;
    expect(service.axis, (x: 1.0, y: 0.0));
    gravity = (vector: upright, timeMicros: now);
    service.add(west);
    expect(service.axis, (x: 1.0, y: 0.0));
    now += 100000;
    gravity = (vector: upright, timeMicros: now);
    service.add(west);
    expect(service.axis.y, lessThan(0));
    gravity = null;
    expect(service.axis, (x: 1.0, y: 0.0));
    service.stop();
  });
  test(
    'start/stop, sensor errors/completion and late old events are neutral',
    () async {
      var now = 0, subscriptions = 0, cancellations = 0;
      final stream = StreamController<SensorVector>.broadcast(
        sync: true,
        onListen: () => subscriptions++,
        onCancel: () => cancellations++,
      );
      final service = HeadingService(
        gravity: () => (vector: upright, timeMicros: now),
        samples: () => stream.stream,
        clock: () => now,
      );
      service.start();
      service.start();
      await Future<void>.value();
      expect(subscriptions, 1);
      for (var i = 0; i < 10; i++) {
        now += 100000;
        stream.add(east);
      }
      expect(service.axis.y, greaterThan(0));
      stream.addError(StateError('missing'));
      expect(service.axis, (x: 1.0, y: 0.0));
      await Future<void>.value();
      expect(cancellations, 1);
      service.start();
      await Future<void>.value();
      expect(subscriptions, 2);
      service.stop();
      service.stop();
      now += 100000;
      stream.add(west);
      expect(service.axis, (x: 1.0, y: 0.0));
      await stream.close();
      final unavailable = HeadingService(
        gravity: () => null,
        samples: () => throw UnsupportedError('absent'),
      );
      unavailable.start();
      await Future<void>.value();
      expect(unavailable.isListening, isFalse);
      final done = HeadingService(
        gravity: () => null,
        samples: () => const Stream.empty(),
      );
      done.start();
      await Future<void>.value();
      await Future<void>.value();
      expect(done.isListening, isFalse);
    },
  );
  test(
    'resume waits for native cancellation and skips abandoned starts',
    () async {
      var subscriptions = 0;
      final cancellation = Completer<void>();
      final first = StreamController<SensorVector>(
        sync: true,
        onListen: () => subscriptions++,
        onCancel: () => cancellation.future,
      );
      final second = StreamController<SensorVector>(
        sync: true,
        onListen: () => subscriptions++,
      );
      var requests = 0;
      final service = HeadingService(
        gravity: () => null,
        samples: () => requests++ == 0 ? first.stream : second.stream,
      );
      service.start();
      await Future<void>.value();
      expect(subscriptions, 1);
      service.stop();
      service.start();
      service.stop();
      service.start();
      await Future<void>.value();
      expect(subscriptions, 1);
      cancellation.complete();
      // Drain only known microtask chains, without wall-clock waits.
      for (var i = 0; i < 5; i++) {
        await Future<void>.value();
      }
      expect(subscriptions, 2);
      service.stop();
      await first.close();
      await second.close();
    },
  );

  test('failed cancellation still permits a neutral restart', () async {
    final stream = StreamController<SensorVector>(
      onCancel: () => Future<void>.error(StateError('cleanup failed')),
    );
    var requests = 0;
    final service = HeadingService(
      gravity: () => null,
      samples: () => requests++ == 0 ? stream.stream : const Stream.empty(),
    );
    service.start();
    await Future<void>.value();
    service.stop();
    service.start();
    for (var i = 0; i < 5; i++) {
      await Future<void>.value();
    }
    expect(service.axis, (x: 1.0, y: 0.0));
    expect(service.isListening, isFalse);
    await stream.close();
  });

  test(
    'MotionService exposes its existing gravity input and clears on pause',
    () async {
      var now = 100;
      final gravity = StreamController<AccelSample>.broadcast(sync: true);
      final motion = MotionService(
        samples: const Stream.empty(),
        gyroSamples: const Stream.empty(),
        gravitySamples: gravity.stream,
        clock: () => now,
      );
      expect(motion.latestGravity, isNull);
      motion.start();
      gravity.add(const AccelSample(0, 9.81, 0));
      expect(motion.latestGravity, (vector: upright, timeMicros: 100));
      gravity.addError(StateError('gravity unavailable'));
      expect(motion.latestGravity, isNull);
      now++;
      gravity.add(const AccelSample(double.nan, 0, 0));
      expect(motion.latestGravity, isNull);
      motion.stop();
      expect(motion.latestGravity, isNull);
      await gravity.close();
    },
  );
}
