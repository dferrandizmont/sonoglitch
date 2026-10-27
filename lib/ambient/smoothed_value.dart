import 'dart:math' as math;

/// Exponential smoother with separate attack and release time constants.
///
/// A rising signal (the *attack*) is followed quickly so the effect reacts at
/// once; a falling signal (the *release*) decays slowly so the picture does
/// not flicker between frames.
///
/// The class is pure Dart: it only needs the time elapsed since the previous
/// sample, which the caller measures. That keeps it deterministic and easy to
/// unit test.
class SmoothedValue {
  /// Creates a smoother starting at [initialValue].
  SmoothedValue({
    double initialValue = 0,
    Duration attack = const Duration(milliseconds: 120),
    Duration release = const Duration(milliseconds: 400),
  }) : _value = initialValue,
       _attack = attack,
       _release = release {
    if (attack <= Duration.zero) {
      throw ArgumentError.value(attack, 'attack', 'must be positive');
    }
    if (release <= Duration.zero) {
      throw ArgumentError.value(release, 'release', 'must be positive');
    }
  }

  final Duration _attack;
  final Duration _release;
  double _value;

  /// The current smoothed value.
  double get value => _value;

  /// The time constant used for rising values.
  Duration get attack => _attack;

  /// The time constant used for falling values.
  Duration get release => _release;

  /// Feeds a new [target] sample and returns the smoothed value.
  ///
  /// [elapsed] is the time since the previous sample. The smoothing factor is
  /// `1 - e^(-dt / tau)`, the usual exponential smoothing step, where `tau` is
  /// the attack or the release constant depending on the direction of the
  /// change.
  double update(double target, Duration elapsed) {
    final tau = target >= _value ? _attack : _release;
    final micros = elapsed.inMicroseconds;
    if (micros <= 0) return _value;
    final alpha = 1 - math.exp(-micros / tau.inMicroseconds);
    _value += (target - _value) * alpha;
    return _value;
  }

  /// Jumps straight to [value], without smoothing.
  void reset([double value = 0]) => _value = value;
}
