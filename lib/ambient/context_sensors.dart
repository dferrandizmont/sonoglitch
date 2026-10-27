import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../export/export_layout.dart';

const synodicMonth = 29.530588853;

/// Fractional lunar age in days, including dates before the reference epoch.
double moonAge(DateTime date) =>
    (date.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inMicroseconds /
        Duration.microsecondsPerDay) %
    synodicMonth;

typedef SensorVector = ({double x, double y, double z});

/// Android compass convention: device top projected onto the horizontal plane.
/// Returns magnetic north, with no location lookup or declination correction.
double? magneticHeading(SensorVector field, SensorVector gravity) {
  final components = [
    field.x,
    field.y,
    field.z,
    gravity.x,
    gravity.y,
    gravity.z,
  ];
  if (components.any((v) => !v.isFinite)) return null;
  final magnitude = math.sqrt(
    field.x * field.x + field.y * field.y + field.z * field.z,
  );
  if (magnitude < 20 || magnitude > 70) return null;
  final g = math.sqrt(
    gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z,
  );
  if (g < 1) return null;
  final ax = gravity.x / g, ay = gravity.y / g, az = gravity.z / g;
  var ex = field.y * az - field.z * ay;
  var ey = field.z * ax - field.x * az;
  var ez = field.x * ay - field.y * ax;
  final e = math.sqrt(ex * ex + ey * ey + ez * ez);
  if (e < .001) return null;
  ex /= e;
  ey /= e;
  ez /= e;
  final northY = az * ex - ax * ez;
  // A vertical device top has no compass bearing.
  if (math.sqrt(ey * ey + northY * northY) < .001) return null;
  return (math.atan2(ey, northY) * 180 / math.pi) % 360;
}

/// One-shot, in-memory instruments. Every subscription is bounded and cancelled.
class ContextSensors {
  const ContextSensors({this.magnetometer, this.accelerometer, this.barometer});

  static const headingTimeout = Duration(milliseconds: 300);
  static const pressureTimeout = Duration(milliseconds: 500);
  final Stream<MagnetometerEvent> Function()? magnetometer;
  final Stream<AccelerometerEvent> Function()? accelerometer;
  final Stream<BarometerEvent> Function()? barometer;

  Future<ExportContext> sample({required DateTime dateTime}) async {
    final heading = _heading();
    final pressure = _first<BarometerEvent>(
      barometer ?? () => barometerEventStream(),
      pressureTimeout,
      (event) => event.pressure.isFinite && event.pressure > 0,
    );
    return ExportContext(
      dateTime: dateTime,
      heading: await heading,
      pressure: (await pressure)?.pressure,
    );
  }

  Future<double?> _heading() async {
    final magnetic = _first<MagnetometerEvent>(
      magnetometer ?? () => magnetometerEventStream(),
      headingTimeout,
      (event) => true,
    );
    final acceleration = _first<AccelerometerEvent>(
      accelerometer ?? () => accelerometerEventStream(),
      headingTimeout,
      (event) => true,
    );
    final field = await magnetic;
    final gravity = await acceleration;
    if (field == null || gravity == null) return null;
    return magneticHeading(
      (x: field.x, y: field.y, z: field.z),
      (x: gravity.x, y: gravity.y, z: gravity.z),
    );
  }

  Future<T?> _first<T>(
    Stream<T> Function() stream,
    Duration timeout,
    bool Function(T) valid,
  ) async {
    final result = Completer<T?>();
    StreamSubscription<T>? subscription;
    final timer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });
    try {
      subscription = stream().listen(
        (event) {
          if (!result.isCompleted && valid(event)) result.complete(event);
        },
        onError: (Object _) {
          if (!result.isCompleted) result.complete(null);
        },
        onDone: () {
          if (!result.isCompleted) result.complete(null);
        },
      );
      return await result.future;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
      try {
        // Cleanup must not extend the sensor deadline.
        final cancellation = subscription?.cancel();
        if (cancellation != null) {
          unawaited(cancellation.catchError((Object _) {}));
        }
      } catch (_) {
        // Optional instrument cleanup must never fail a camera capture.
      }
    }
  }
}
