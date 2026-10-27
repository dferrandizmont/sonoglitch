import 'dart:math' as math;

import '../ambient/ambient_config.dart';

/// Clockwise turns to make a portrait-locked camera photo match physical up.
/// Landscape left means the top of the handset points left (positive x gravity).
enum CaptureOrientation {
  portrait(0),
  landscapeLeft(3),
  portraitUpsideDown(2),
  landscapeRight(1);

  const CaptureOrientation(this.quarterTurns);
  final int quarterTurns;
}

/// Uses gravity including its sign, retaining the last pose near diagonals or
/// when the handset lies flat. No orientation events from the locked UI needed.
class CaptureOrientationTracker {
  CaptureOrientation value = CaptureOrientation.portrait;
  double _x = 0;
  double _y = 9.8;
  double _z = 0;
  CaptureOrientation? _candidate;
  Duration _stable = Duration.zero;

  void addGravity(
    double x,
    double y,
    double z, {
    Duration elapsed = const Duration(milliseconds: 100),
  }) {
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    // Raw accelerometers include linear acceleration. Reject implausible
    // gravity and low-pass the rest before asking for sustained pose evidence.
    final length = math.sqrt(x * x + y * y + z * z);
    if (!length.isFinite || length < 7 || length > 12.5) {
      _candidate = null;
      _stable = Duration.zero;
      return;
    }
    final dt = elapsed.inMicroseconds.clamp(0, 200000);
    final alpha = 1 - math.exp(-dt / 350000);
    _x += alpha * (x - _x);
    _y += alpha * (y - _y);
    _z += alpha * (z - _z);
    final ax = _x.abs();
    final ay = _y.abs();
    CaptureOrientation? next;
    // Check raw AND filtered z, so setting the phone flat cannot briefly
    // promote a stale in-plane direction during the filter's settling time.
    if (z.abs() < length * 0.75 && _z.abs() < math.max(ax, ay)) {
      if (ax > AmbientConfig.orientationMinGravity &&
          ax > ay * AmbientConfig.orientationDominance &&
          ax > _z.abs()) {
        next = _x > 0
            ? CaptureOrientation.landscapeLeft
            : CaptureOrientation.landscapeRight;
      } else if (ay > AmbientConfig.orientationMinGravity &&
          ay > ax * AmbientConfig.orientationDominance &&
          ay > _z.abs()) {
        next = _y > 0
            ? CaptureOrientation.portrait
            : CaptureOrientation.portraitUpsideDown;
      }
    }
    if (next == null || next == value) {
      _candidate = null;
      _stable = Duration.zero;
      return;
    }
    if (_candidate != next) {
      _candidate = next;
      _stable = Duration.zero;
    }
    _stable += Duration(microseconds: dt);
    if (_stable >= const Duration(milliseconds: 400)) {
      value = next;
      _candidate = null;
      _stable = Duration.zero;
    }
  }
}
