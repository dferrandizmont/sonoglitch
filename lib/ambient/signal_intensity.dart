import 'dart:math' as math;

import 'ambient_config.dart';

/// Applied once, after combining the measured noise/motion sources.
/// Manual controls intentionally bypass this curve.
enum SignalIntensity {
  subtle(AmbientConfig.subtleGamma, AmbientConfig.subtleGain),
  normal(AmbientConfig.normalGamma, AmbientConfig.normalGain),
  extreme(AmbientConfig.extremeGamma, AmbientConfig.extremeGain);

  const SignalIntensity(this.gamma, this.gain);
  final double gamma;
  final double gain;

  double apply(double value) => value.isFinite
      ? (math.pow(value.clamp(0.0, 1.0), gamma) * gain).clamp(0.0, 1.0)
      : 0;
}
