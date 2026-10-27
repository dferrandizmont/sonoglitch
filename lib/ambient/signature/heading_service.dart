import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../clock.dart';
import '../context_sensors.dart';

/// Shared gravity in m/s², timestamped with the same monotonic clock.
typedef TimedGravity = ({SensorVector vector, int timeMicros});

/// Back-camera bearing in radians and its bounded reliability.
class HeadingAxis {
  const HeadingAxis({this.heading = 0, this.reliability = 0});

  final double heading;
  final double reliability;

  double get delta => math.pi / 15 * math.sin(heading) * reliability;
  double get x => math.cos(delta);
  double get y => math.sin(delta);
}

double _ramp(double x, double lo, double hi) {
  final t = ((x - lo) / (hi - lo)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Tilt-compensated magnetic bearing of device -z, independent of screen roll.
/// Flat on a table points at zenith/nadir and intentionally has no bearing.
HeadingAxis opticalAxis(SensorVector field, SensorVector gravity) {
  if ([
    field.x,
    field.y,
    field.z,
    gravity.x,
    gravity.y,
    gravity.z,
  ].any((v) => !v.isFinite)) {
    return const HeadingAxis();
  }
  final b = math.sqrt(
    field.x * field.x + field.y * field.y + field.z * field.z,
  );
  final g = math.sqrt(
    gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z,
  );
  if (b < 20 || b > 70 || g < 1) return const HeadingAxis();
  final ax = gravity.x / g, ay = gravity.y / g, az = gravity.z / g;
  var ex = field.y * az - field.z * ay;
  var ey = field.z * ax - field.x * az;
  var ez = field.x * ay - field.y * ax;
  final e = math.sqrt(ex * ex + ey * ey + ez * ez);
  if (e < .001) return const HeadingAxis();
  ex /= e;
  ey /= e;
  ez /= e;
  final nz = ax * ey - ay * ex;
  final projection = math.sqrt(ez * ez + nz * nz);
  // Fade within ~6..24 degrees of vertical; reject magnetic dip degeneracy
  // and acceleration inconsistent with gravity (1..3 m/s² away from 9.81).
  final reliability =
      _ramp(projection, .1, .4) *
      _ramp(e / b, .1, .3) *
      (1 - _ramp((g - 9.81).abs(), 1, 3));
  return HeadingAxis(heading: math.atan2(-ez, -nz), reliability: reliability);
}

/// Optional magnetometer input. No accelerometer subscription or timers.
class HeadingService {
  HeadingService({
    required this.gravity,
    Stream<SensorVector> Function()? samples,
    this.clock = stopwatchClock,
  }) : samples = samples ?? _magnetometer;

  final TimedGravity? Function() gravity;
  final Stream<SensorVector> Function() samples;
  final Clock clock;
  static const staleMicros = 1000000;
  static const tauMicros = 800000;
  StreamSubscription<SensorVector>? _subscription;
  Future<void> _cancellation = Future<void>.value();
  bool _running = false;
  int _generation = 0;
  int? _last;
  double _sin = 0, _cos = 0;

  bool get isListening => _running;

  /// Whether both the field and shared gravity are at most one second old.
  bool get isFresh {
    final now = clock();
    final g = gravity();
    return _last != null &&
        g != null &&
        now >= _last! &&
        now >= g.timeMicros &&
        now - _last! <= staleMicros &&
        now - g.timeMicros <= staleMicros;
  }

  /// Unit modulation axis. Reliability fades over the final 200 ms of freshness.
  ({double x, double y}) get axis {
    final now = clock();
    final last = _last;
    final g = gravity();
    if (last == null || g == null) return (x: 1, y: 0);
    final age = math.max(now - last, now - g.timeMicros);
    if (now < last || now < g.timeMicros || age > staleMicros) {
      return (x: 1, y: 0);
    }
    final fade = 1 - _ramp(age.toDouble(), 800000, 1000000);
    // Do not normalize sin/cos: their length preserves reliability and lets
    // opposing headings fade through neutral instead of flipping abruptly.
    final reliability = math.sqrt(_sin * _sin + _cos * _cos).clamp(0.0, 1.0);
    final heading = math.atan2(_sin, _cos);
    final delta = math.pi / 15 * math.sin(heading) * reliability * fade;
    return (x: math.cos(delta), y: math.sin(delta));
  }

  /// Idempotently starts one input; plugin errors fall back to neutral.
  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    // A rapid resume waits for the previous native cancellation to finish.
    unawaited(
      _cancellation.then((_) {
        if (!_running || generation != _generation) return;
        try {
          final subscription = samples().listen(
            (field) {
              if (_running && generation == _generation) add(field);
            },
            onError: (Object _) {
              if (generation == _generation) stop();
            },
            onDone: () {
              if (generation == _generation) stop();
            },
          );
          // A synchronous stream may already have completed during listen().
          if (!_running || generation != _generation) {
            _cancellation = _cancel(subscription);
          } else {
            _subscription = subscription;
          }
        } catch (_) {
          stop();
        }
      }),
    );
  }

  /// Cancels input and clears all transient state, including on lens changes.
  void stop() {
    _running = false;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) _cancellation = _cancel(subscription);
    _last = null;
    _sin = _cos = 0;
  }

  Future<void> _cancel(StreamSubscription<SensorVector> subscription) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // Optional instrument cleanup must never fail the camera lifecycle.
    }
  }

  /// Feeds a field in µT using the latest shared gravity; useful for tests.
  void add(SensorVector field) {
    final now = clock();
    final g = gravity();
    final valid =
        g != null && now >= g.timeMicros && now - g.timeMicros <= staleMicros;
    final target = valid ? opticalAxis(field, g.vector) : const HeadingAxis();
    final elapsed = _last == null || now - _last! > staleMicros
        ? 0
        : math.max(0, now - _last!);
    if (_last == null || now - _last! > staleMicros) _sin = _cos = 0;
    final alpha = 1 - math.exp(-elapsed / tauMicros);
    _sin += alpha * (math.sin(target.heading) * target.reliability - _sin);
    _cos += alpha * (math.cos(target.heading) * target.reliability - _cos);
    _last = now;
  }

  static Stream<SensorVector> _magnetometer() =>
      magnetometerEventStream(samplingPeriod: const Duration(milliseconds: 100))
          .map((e) => (x: e.x, y: e.y, z: e.z));
}
