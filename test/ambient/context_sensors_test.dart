import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/export/export_layout.dart';

void main() {
  final epoch = DateTime.utc(2000, 1, 6, 18, 14);
  test('lunar age is UTC based, fractional and wraps backwards', () {
    expect(moonAge(epoch), 0);
    expect(moonAge(epoch.add(const Duration(hours: 12))), .5);
    expect(
      moonAge(epoch.subtract(const Duration(days: 1))),
      closeTo(synodicMonth - 1, 1e-9),
    );
    final month = Duration(
      microseconds: (synodicMonth * Duration.microsecondsPerDay).round(),
    );
    expect(
      moonAge(epoch.add(month)),
      anyOf(closeTo(0, 1e-9), closeTo(synodicMonth, 1e-9)),
    );
    expect(moonAge(epoch.toLocal()), moonAge(epoch));
  });
  test('magnetic compass rejects invalid fields, handles tilt and wraps', () {
    const flat = (x: 0.0, y: 0.0, z: 9.8);
    expect(magneticHeading((x: 0, y: 50, z: 0), flat), closeTo(0, .001));
    expect(magneticHeading((x: -50, y: 0, z: 0), flat), closeTo(90, .001));
    expect(magneticHeading((x: 0, y: -50, z: 0), flat), closeTo(180, .001));
    expect(magneticHeading((x: 50, y: 0, z: 0), flat), closeTo(270, .001));
    for (final v in [0.0, 19.0, 71.0, double.nan, double.infinity]) {
      expect(magneticHeading((x: 0, y: v, z: 0), flat), isNull);
    }
    expect(magneticHeading((x: 0, y: 50, z: 0), (x: 0, y: 0, z: 0)), isNull);
    // Rotate the phone 30 degrees about its x axis: north stays north.
    final a = math.pi / 6;
    expect(
      magneticHeading(
        (x: 0, y: 50 * math.cos(a), z: -50 * math.sin(a)),
        (x: 0, y: 9.8 * math.sin(a), z: 9.8 * math.cos(a)),
      ),
      closeTo(0, .001),
    );
  });
  test(
    'one-shot values and cancellations, no sensor survives completion',
    () async {
      var cancelled = 0;
      Stream<T> event<T>(T value) => Stream<T>.multi((controller) {
        controller.onCancel = () => cancelled++;
        controller.add(value);
      });
      final sample = await ContextSensors(
        magnetometer: () => event(MagnetometerEvent(0, 50, 0, epoch)),
        accelerometer: () => event(AccelerometerEvent(0, 0, 9.8, epoch)),
        barometer: () => event(BarometerEvent(1013.2, epoch)),
      ).sample(dateTime: epoch);
      expect(sample.dateTime, epoch);
      expect(sample.heading, closeTo(0, .001));
      expect(sample.pressure, 1013.2);
      expect(cancelled, 3);
    },
  );
  testWidgets('300 and 500 ms deadlines run concurrently and cancel upstream', (
    tester,
  ) async {
    var cancelled = 0;
    Stream<T> silent<T>() => Stream<T>.multi((controller) {
      controller.onCancel = () => cancelled++;
    });
    ExportContext? context;
    ContextSensors(
      magnetometer: () => silent<MagnetometerEvent>(),
      accelerometer: () => silent<AccelerometerEvent>(),
      barometer: () => silent<BarometerEvent>(),
    ).sample(dateTime: epoch).then((value) => context = value);
    await tester.pump(const Duration(milliseconds: 299));
    expect(cancelled, 0);
    expect(context, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cancelled, 2);
    expect(context, isNull);
    await tester.pump(const Duration(milliseconds: 200));
    expect(cancelled, 3);
    // Stream cancellation completes on a real event-loop turn.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(context, isNotNull);
    expect(context!.heading, isNull);
    expect(context!.pressure, isNull);
  });
  for (final headingAvailable in [false, true]) {
    testWidgets(
      '500 ms deadline ignores pending cancellation (heading: $headingAvailable)',
      (tester) async {
        var cancelled = 0;
        final neverCancelled = Completer<void>();
        StreamController<T> sensor<T>() => StreamController<T>(
          onCancel: () {
            cancelled++;
            return neverCancelled.future;
          },
        );
        final magnetic = sensor<MagnetometerEvent>();
        final acceleration = sensor<AccelerometerEvent>();
        final pressure = sensor<BarometerEvent>();
        ExportContext? context;
        ContextSensors(
          magnetometer: () => magnetic.stream,
          accelerometer: () => acceleration.stream,
          barometer: () => pressure.stream,
        ).sample(dateTime: epoch).then((value) => context = value);
        if (headingAvailable) {
          magnetic.add(MagnetometerEvent(0, 50, 0, epoch));
          acceleration.add(AccelerometerEvent(0, 0, 9.8, epoch));
        }
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(cancelled, headingAvailable ? 2 : 0);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(cancelled, 2);
        expect(context, isNull);
        await tester.pump(const Duration(milliseconds: 199));
        expect(context, isNull);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(cancelled, 3);
        expect(neverCancelled.isCompleted, isFalse);
        expect(context, isNotNull);
        expect(context!.dateTime, epoch);
        expect(context!.heading, headingAvailable ? closeTo(0, .001) : isNull);
        expect(context!.pressure, isNull);
      },
    );
  }
  test('asynchronous cancellation errors do not escape sampling', () async {
    Stream<T> event<T>(T value) {
      final controller = StreamController<T>(
        onCancel: () => Future<void>.error(StateError('cleanup failed')),
      )..add(value);
      return controller.stream;
    }

    final context = await ContextSensors(
      magnetometer: () => event(MagnetometerEvent(0, 50, 0, epoch)),
      accelerometer: () => event(AccelerometerEvent(0, 0, 9.8, epoch)),
      barometer: () => event(BarometerEvent(1013.2, epoch)),
    ).sample(dateTime: epoch);
    await Future<void>.delayed(Duration.zero);
    expect(context.heading, closeTo(0, .001));
    expect(context.pressure, 1013.2);
  });
  test('unsupported plugins and closed streams omit instruments', () async {
    final context = await ContextSensors(
      magnetometer: () => throw UnsupportedError('absent'),
      accelerometer: () => const Stream.empty(),
      barometer: () => Stream.error(UnsupportedError('absent')),
    ).sample(dateTime: epoch);
    expect(context.dateTime, epoch);
    expect(context.heading, isNull);
    expect(context.pressure, isNull);
  });
}
