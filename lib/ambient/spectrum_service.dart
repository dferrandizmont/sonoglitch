import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'clock.dart';
import 'smoothed_value.dart';
import 'spectrum_source.dart';
import 'signature/signature_source.dart';

/// Learns independent session envelopes from scalar band energies only.
/// The P10 floor uses sixty one-second buckets. Ten seconds of active samples
/// establish a floor before a band can affect the image. No PCM is retained.
class SpectrumService {
  SpectrumService({
    SpectrumSource? source,
    this.clock = stopwatchClock,
    this.warmup = const Duration(seconds: 10),
  }) : source = source ?? platformSpectrumSource();

  final SpectrumSource source;
  final Clock clock;
  final Duration warmup;
  bool enabled = true;
  final _signature = SignatureSource(3);
  List<SignatureReading> get signatureReadings => enabled
      ? _signature.readings(clock())
      : const [SignatureReading(), SignatureReading(), SignatureReading()];
  final _bands = [_Band(60, 400), _Band(40, 250), _Band(30, 180)];
  StreamSubscription<SpectrumBands>? _subscription;
  Future<void> _cancellation = Future.value();
  int _generation = 0;
  bool _wanted = false;
  int? _lastTime;
  SpectrumBands? _lastRawBands;

  /// The readings that arrived since the last drain, in order.
  final Queue<RawSpectrumReading> _pending = Queue();

  /// How many readings are kept for the consumers of the contextual lanes.
  ///
  /// The queue is a safety net, not a buffer: the lanes drain it on every
  /// tick, so it only grows when nobody consumes it.
  static const int maxPendingReadings = 256;

  /// Latest finite, unnormalized native dBFS bands and monotonic timestamp.
  /// Null on pause/source loss, or while spectrum input is disabled.
  ({SpectrumBands bands, int timeMicros})? get lastRawReading =>
      !enabled || _lastTime == null || _lastRawBands == null
      ? null
      : (bands: _lastRawBands!, timeMicros: _lastTime!);

  /// The raw readings that arrived since the last drain, in order.
  ///
  /// Every native reading is delivered, so a burst between two ticks is not
  /// collapsed into its last value: the tracker and the tilt filter see the
  /// rise and the fall of a hit as they happened. The queue is emptied by the
  /// call, and it is dropped with the session.
  List<RawSpectrumReading> drainRawReadings() {
    if (_pending.isEmpty) return const [];
    final readings = _pending.toList(growable: false);
    _pending.clear();
    // A disabled service has no valid reading to give.
    return enabled ? readings : const [];
  }

  int _activeMicros = 0;

  bool get isListening => _subscription != null;
  bool get available =>
      _activeMicros >= warmup.inMicroseconds && _lastTime != null;
  double get bass => available ? _bands[0].smoother.value : 0;
  double get mid => available ? _bands[1].smoother.value : 0;
  double get treble => available ? _bands[2].smoother.value : 0;
  SpectrumBands get floors =>
      (bass: _bands[0].floor, mid: _bands[1].floor, treble: _bands[2].floor);
  SpectrumBands get ceilings => (
    bass: _bands[0].ceiling,
    mid: _bands[1].ceiling,
    treble: _bands[2].ceiling,
  );

  void start() {
    if (!enabled || _wanted) return;
    _wanted = true;
    final generation = ++_generation;
    // A rapid resume must wait for cancellation of the previous native input.
    unawaited(
      _cancellation.then((_) {
        if (!_wanted || generation != _generation) return;
        _subscription = source.bands.listen(
          (bands) {
            if (generation == _generation) addReading(bands);
          },
          onError: (Object error) {
            if (generation == _generation) stop();
          },
          onDone: () {
            if (generation == _generation) stop();
          },
        );
      }),
    );
  }

  void stop() {
    _signature.clear();
    _wanted = false;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) _cancellation = subscription.cancel();
    _lastTime = null;
    _lastRawBands = null;
    _pending.clear();
    for (final band in _bands) {
      band.smoother.reset();
    }
  }

  /// Public for deterministic synthetic input, in dB relative to full scale.
  void addReading(SpectrumBands reading) {
    final raw = [reading.bass, reading.mid, reading.treble];
    if (raw.any((value) => !value.isFinite)) return;
    final values = raw.map((value) => value.clamp(-120.0, 0.0)).toList();
    final now = clock();
    _lastRawBands = reading;
    _signature.update(raw, now);
    final elapsed = _lastTime == null
        ? nominalSamplePeriod
        : Duration(microseconds: (now - _lastTime!).clamp(0, 250000));
    _lastTime = now;
    _activeMicros += elapsed.inMicroseconds;
    // Every reading is kept for the contextual lanes, so a burst between two
    // ticks is not collapsed into its last value.
    _pending.add((bands: reading, timeMicros: now));
    while (_pending.length > maxPendingReadings) {
      _pending.removeFirst();
    }
    final targets = <double>[];
    final strongest = values.reduce(math.max);
    for (var i = 0; i < 3; i++) {
      final band = _bands[i];
      band.learn(values[i], _activeMicros, elapsed);
      final relative = ((values[i] - band.floor) / (band.ceiling - band.floor))
          .clamp(0.0, 1.0);
      final curve = relative * relative * (3 - 2 * relative);
      // A weaker band stays weaker even when its own learned range is small.
      final balance = math.pow(10, (values[i] - strongest) / 20).toDouble();
      targets.add(available ? curve * balance : 0);
    }
    // Bound the total energy even in a loud, spectrally flat environment.
    final scale = math.max(1.0, targets.reduce((a, b) => a + b) / 1.4);
    for (var i = 0; i < 3; i++) {
      _bands[i].smoother.update(targets[i] / scale, elapsed);
    }
    final sum = _bands.fold(0.0, (sum, band) => sum + band.smoother.value);
    if (sum > 1.4) {
      for (final band in _bands) {
        band.smoother.reset(band.smoother.value * 1.4 / sum);
      }
    }
  }
}

class _Band {
  _Band(int attack, int release)
    : smoother = SmoothedValue(
        attack: Duration(milliseconds: attack),
        release: Duration(milliseconds: release),
      );

  final SmoothedValue smoother;
  final Queue<(int, double)> _history = Queue();
  double floor = -90;
  double ceiling = -24;
  int _bucket = -1;
  double _sum = 0;
  int _count = 0;

  void learn(double db, int activeMicros, Duration elapsed) {
    final bucket = activeMicros ~/ 1000000;
    if (_bucket != bucket) {
      if (_count > 0) _history.add((_bucket, _sum / _count));
      _bucket = bucket;
      _sum = 0;
      _count = 0;
    }
    _sum += db;
    _count++;
    while (_history.isNotEmpty && _history.first.$1 < bucket - 59) {
      _history.removeFirst();
    }
    final sorted = [for (final sample in _history) sample.$2, _sum / _count]
      ..sort();
    floor = sorted[math.max(0, (sorted.length * 0.1).ceil() - 1)];
    final decay = math.exp(-elapsed.inMicroseconds / 30000000);
    ceiling = math.max(
      floor + 18,
      math.max(db, floor + (ceiling - floor) * decay),
    );
  }
}
