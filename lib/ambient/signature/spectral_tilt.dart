import 'dart:math' as math;

import '../clock.dart';
import '../spectrum_source.dart';

/// The centres of the native FFT bands, in octaves.
///
/// Native FFT bands: 20..250, 250..2000, 2000..8000 Hz. Integrated power
/// needs 10*log10(width), not an amplitude correction (20*log10).
///
/// The regression of the density against these centres does not change from
/// reading to reading, so the coefficients are computed once.
final List<double> _tiltCenters = [
  math.log(math.sqrt(20 * 250)) / math.ln2,
  math.log(math.sqrt(250 * 2000)) / math.ln2,
  math.log(math.sqrt(2000 * 8000)) / math.ln2,
];

/// The mean of the centres of the bands.
final double _tiltMean =
    (_tiltCenters[0] + _tiltCenters[1] + _tiltCenters[2]) / 3;

/// The deviation of every centre from the mean.
final List<double> _tiltWeights = [
  _tiltCenters[0] - _tiltMean,
  _tiltCenters[1] - _tiltMean,
  _tiltCenters[2] - _tiltMean,
];

/// The spread of the centres, the denominator of the regression.
final double _tiltVariance =
    _tiltWeights[0] * _tiltWeights[0] +
    _tiltWeights[1] * _tiltWeights[1] +
    _tiltWeights[2] * _tiltWeights[2];

/// The power of every band, subtracted from its density.
final List<double> _tiltWidths = [
  10 * math.log(230.0) / math.ln10,
  10 * math.log(1750.0) / math.ln10,
  10 * math.log(6000.0) / math.ln10,
];

/// Relative dB-density slope, normalized so ±6 dB/octave becomes ±1.
/// Floors are dBFS band energies, optionally the session's learned floors.
double spectralTilt(
  SpectrumBands bands, {
  SpectrumBands floors = (bass: -90, mid: -90, treble: -90),
  double minSnrDb = 6,
}) {
  final db0 = bands.bass, db1 = bands.mid, db2 = bands.treble;
  final fl0 = floors.bass, fl1 = floors.mid, fl2 = floors.treble;
  if (!db0.isFinite ||
      !db1.isFinite ||
      !db2.isFinite ||
      !fl0.isFinite ||
      !fl1.isFinite ||
      !fl2.isFinite ||
      !minSnrDb.isFinite) {
    return 0;
  }
  if (!(db0 - fl0 > minSnrDb || db1 - fl1 > minSnrDb || db2 - fl2 > minSnrDb)) {
    return 0;
  }
  final y0 = db0 - _tiltWidths[0];
  final y1 = db1 - _tiltWidths[1];
  final y2 = db2 - _tiltWidths[2];
  final my = (y0 + y1 + y2) / 3;
  final covariance =
      _tiltWeights[0] * (y0 - my) +
      _tiltWeights[1] * (y1 - my) +
      _tiltWeights[2] * (y2 - my);
  final result = covariance / _tiltVariance / 6;
  return result.isFinite ? result.clamp(-1.0, 1.0) : 0;
}

/// Timestamped one-second low-pass; stale/missing input is neutral zero.
class SpectralTiltFilter {
  SpectralTiltFilter({this.clock = stopwatchClock});

  final Clock clock;
  int? _last;
  double _value = 0;

  bool get isFresh {
    final now = clock();
    return _last != null && now >= _last! && now - _last! <= 1000000;
  }

  double get value => isFresh ? _value : 0;

  /// Feed each new raw spectrum once, before session normalization.
  void add(
    SpectrumBands bands,
    int timeMicros, {
    SpectrumBands floors = (bass: -90, mid: -90, treble: -90),
  }) {
    if (_last != null && timeMicros <= _last!) return;
    final target = spectralTilt(bands, floors: floors);
    final dt = _last == null || timeMicros - _last! > 1000000
        ? 0
        : timeMicros - _last!;
    if (dt == 0) _value = 0;
    _value += (1 - math.exp(-dt / 1000000)) * (target - _value);
    _last = timeMicros;
  }

  /// Clear on pause, source loss, or camera change. No timers are owned.
  void clear() {
    _last = null;
    _value = 0;
  }

  void start() => clear();
  void stop() => clear();
}
