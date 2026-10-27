import 'dart:collection';
import 'dart:math' as math;

import '../clock.dart';

/// In-memory onset/tempo tracker from scalar log energies, never audio samples.
class RhythmTracker {
  RhythmTracker({this.clock = stopwatchClock});

  final Clock clock;
  static const sampleMicros = 50000;
  static const windowSamples = 240;
  static const confidenceGate = .65;
  static const bandWeights = [.5, .35, .15];
  static const baselineMicros = 1500000;
  static const refractoryMicros = 200000;
  final Queue<({int time, double envelope})> _window = Queue();
  final Queue<int> _attacks = Queue();
  int? _inputTime, _lastAttack, _lastEstimate, _phaseTime, _origin;
  int _bin = 0;
  double _binEnergy = 0;
  List<double>? _input;
  double _mean = 0, _variance = 0, _envelope = 0;
  double _phase = 0, _confidence = 0;
  double? _bpm, _candidate;
  int _stable = 0;

  /// Bounded history sizes, exposed for deterministic memory-budget checks.
  int get bufferedSamples => _window.length;
  int get bufferedAttacks => _attacks.length;

  bool get isFresh {
    final now = clock();
    return _inputTime != null &&
        now >= _inputTime! &&
        now - _inputTime! <= 1000000;
  }

  double get confidence {
    if (!isFresh || _bpm == null || _lastAttack == null) return 0;
    if (clock() - _lastAttack! > 120000000 / _bpm!) return 0;
    return _confidence;
  }

  double? get bpm => confidence > 0 ? _bpm : null;

  /// Signed pulse with continuous phase; missing evidence is exactly zero.
  double get pulse {
    final c = confidence;
    if (c == 0 || _phaseTime == null) return 0;
    return (c * math.cos(_phaseAt(clock()))).clamp(-1.0, 1.0);
  }

  /// The phase of the beat at [time], extrapolated from the last bin.
  ///
  /// The phase of the tracker is the phase at the last emitted bin, which is
  /// up to one bin older than the instant asked for. The extrapolation is
  /// what keeps the correction of an attack aligned with the attack.
  double _phaseAt(int time) {
    final stamp = _phaseTime;
    final bpm = _bpm;
    if (stamp == null || bpm == null) return _phase;
    final elapsed = math.max(0, time - stamp);
    return _phase + 2 * math.pi * bpm / 60 * elapsed / 1000000;
  }

  /// Feed each native reading once, timestamped in monotonic microseconds.
  /// The onset is measured between two native readings and the 50 ms analysis
  /// bin only max-holds its energy, so a kick shorter than one bin is never
  /// skipped. Gaps >250 ms restart acquisition.
  void add(int timeMicros, double bass, double mid, double treble) {
    final raw = [bass, mid, treble];
    if (raw.any((v) => !v.isFinite)) {
      clear();
      return;
    }
    final values = [for (final v in raw) v.clamp(-120.0, 0.0)];
    if (_inputTime != null && timeMicros <= _inputTime!) return;
    if (_inputTime != null && timeMicros - _inputTime! > 250000) clear();
    if (_inputTime == null) {
      _origin = timeMicros;
      _inputTime = timeMicros;
      _input = values;
      _bin = 0;
      _binEnergy = 0;
      return;
    }
    final elapsed = timeMicros - _inputTime!;
    // The onset flux is the rise between two native readings. Its weight no
    // longer depends on where the analysis bin cuts the transient, which is
    // what keeps the envelope symmetric at tempi near a bin boundary.
    var flux = 0.0;
    for (var i = 0; i < 3; i++) {
      flux += bandWeights[i] * math.max(0, values[i] - _input![i]);
    }
    if (values.reduce(math.max) <= -84) flux = 0;
    // A 3 dB minimum rejects tiny stationary fluctuations. The 1.5 s adaptive
    // baseline follows noise without remembering an isolated attack forever.
    final threshold = math.max(3.0, _mean + math.sqrt(_variance));
    final onset = math.max(0.0, flux - threshold);
    final alpha = 1 - math.exp(-elapsed / baselineMicros);
    final difference = flux - _mean;
    _mean += alpha * difference;
    _variance = (1 - alpha) * (_variance + alpha * difference * difference);
    _input = values;
    _inputTime = timeMicros;
    if (onset > 0 &&
        (_lastAttack == null ||
            timeMicros - _lastAttack! >= refractoryMicros)) {
      _attacks.add(timeMicros);
      _lastAttack = timeMicros;
      if (_confidence >= confidenceGate) {
        // Soft correction never resets phase or multiplies wall time by BPM.
        // The error is measured at the instant of the attack and not at the
        // last emitted bin: the bin can be up to 50 ms older, and correcting
        // there would lead the beat by that much.
        final phase = _phaseAt(timeMicros);
        final error = math.atan2(math.sin(phase), math.cos(phase));
        _phase -= .2 * error;
      }
    }
    // Close every bin the reading passed over and max-hold the onset energy
    // of the bin the reading belongs to.
    final bin = (timeMicros - _origin!) ~/ sampleMicros;
    while (_bin < bin) {
      _emit(_origin! + (_bin + 1) * sampleMicros, _binEnergy);
      _bin++;
      _binEnergy = 0;
    }
    if (onset > _binEnergy) _binEnergy = onset;
  }

  /// Publish one 50 ms bin of the envelope and refresh the tempo estimate.
  void _emit(int time, double energy) {
    _envelope = .5 * _envelope + energy;
    _advancePhase(time);
    _window.add((time: time, envelope: _envelope));
    while (_window.length > windowSamples) {
      _window.removeFirst();
    }
    while (_attacks.isNotEmpty && _attacks.first <= time - 12000000) {
      _attacks.removeFirst();
    }
    if (_lastEstimate == null || time - _lastEstimate! >= 500000) {
      _estimate();
      _lastEstimate = time;
    }
  }

  void _advancePhase(int time) {
    if (_phaseTime != null && _bpm != null) {
      _phase =
          (_phase + 2 * math.pi * _bpm! / 60 * (time - _phaseTime!) / 1000000) %
          (2 * math.pi);
    }
    _phaseTime = time;
  }

  void _reject() {
    _confidence = 0;
    _bpm = null;
    _candidate = null;
    _stable = 0;
  }

  void _estimate() {
    // Six seconds plus three half-second estimates avoids premature locks.
    if (_window.length < 120 || _attacks.length < 4) {
      _reject();
      return;
    }
    final data = _window.map((s) => s.envelope).toList();
    final mean = data.reduce((a, b) => a + b) / data.length;
    final correlations = List<double>.filled(32, 0);
    // 20 Hz * 60 / BPM: inclusive lag range 6..30 = 200..40 BPM.
    for (var lag = 5; lag <= 31; lag++) {
      var cross = 0.0, a2 = 0.0, b2 = 0.0;
      for (var i = lag; i < data.length; i++) {
        final a = data[i] - mean, b = data[i - lag] - mean;
        cross += a * b;
        a2 += a * a;
        b2 += b * b;
      }
      correlations[lag] = a2 * b2 > 1e-12 ? cross / math.sqrt(a2 * b2) : 0;
    }
    final attacks = _attacks.toList();
    var bestScore = 0.0, bestLag = 0.0;
    for (var lag = 6; lag <= 30; lag++) {
      final corr = correlations[lag];
      if (corr < .35 ||
          corr < correlations[lag - 1] ||
          corr < correlations[lag + 1]) {
        continue;
      }
      final denominator =
          correlations[lag - 1] - 2 * corr + correlations[lag + 1];
      final offset = denominator.abs() < 1e-9
          ? 0.0
          : (.5 * (correlations[lag - 1] - correlations[lag + 1]) / denominator)
                .clamp(-.5, .5);
      var period = (lag + offset).clamp(6.0, 30.0);
      var coherent = 0;
      var intervalSum = 0.0;
      for (var i = 1; i < attacks.length; i++) {
        final interval = (attacks[i] - attacks[i - 1]) / sampleMicros;
        if ((interval - period).abs() <= math.max(1.5, .15 * period)) {
          coherent++;
          intervalSum += interval;
        }
      }
      // Harmonic check: a half/double-time peak does not explain consecutive
      // attacks. At least four attacks and 80% of intervals must agree.
      final agreement = coherent / (attacks.length - 1);
      if (coherent < 3 || agreement < .8) continue;
      // Seed the sub-bin fit with coherent intervals, so an ACF peak biased
      // toward lag 7 or 8 cannot slip a beat over a twelve-second 7.5-bin train.
      period = (intervalSum / coherent).clamp(6.0, 30.0);
      // Refine the interpolated ACF peak with attack times. Sub-bin periods
      // (e.g. 7.5 samples at 160 BPM) otherwise accumulate phase bias across
      // twelve seconds. Rounded beat indices tolerate an occasional missed hit.
      final beats = [
        for (final attack in attacks)
          ((attack - attacks.first) / (sampleMicros * period)).roundToDouble(),
      ];
      final times = [
        for (final attack in attacks) (attack - attacks.first) / sampleMicros,
      ];
      final mx = beats.reduce((a, b) => a + b) / beats.length;
      final my = times.reduce((a, b) => a + b) / times.length;
      var xy = 0.0, xx = 0.0;
      for (var i = 0; i < beats.length; i++) {
        xy += (beats[i] - mx) * (times[i] - my);
        xx += (beats[i] - mx) * (beats[i] - mx);
      }
      if (xx > 0 && (xy / xx - period).abs() < .15 * period) {
        period = (xy / xx).clamp(6.0, 30.0);
      }
      var cx = 0.0, sy = 0.0;
      for (final attack in attacks) {
        final angle =
            2 * math.pi * (attack - attacks.first) / (sampleMicros * period);
        cx += math.cos(angle);
        sy += math.sin(angle);
      }
      final concentration = math.sqrt(cx * cx + sy * sy) / attacks.length;
      final score = (.5 * corr + .5 * agreement) * concentration;
      if (score > bestScore) {
        bestScore = score;
        bestLag = period;
      }
    }
    if (bestScore < confidenceGate || bestLag == 0) {
      _reject();
      return;
    }
    final tempo = 1200 / bestLag;
    _stable =
        _candidate != null && (tempo - _candidate!).abs() / _candidate! < .04
        ? _stable + 1
        : 1;
    _candidate = tempo;
    if (_stable < 3) {
      _confidence = 0;
      _bpm = null;
      return;
    }
    _bpm = tempo;
    _confidence = bestScore.clamp(0.0, 1.0);
  }

  /// Clear on pause, source loss, or a camera switch. No timers are owned.
  void clear() {
    _window.clear();
    _attacks.clear();
    _inputTime = _lastAttack = _lastEstimate = _phaseTime = _origin = null;
    _input = null;
    _bin = 0;
    _binEnergy = 0;
    _mean = _variance = _envelope = _phase = _confidence = 0;
    _bpm = _candidate = null;
    _stable = 0;
  }

  void start() => clear();
  void stop() => clear();
}
