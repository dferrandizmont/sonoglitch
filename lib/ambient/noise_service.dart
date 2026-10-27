import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:noise_meter/noise_meter.dart';

import 'ambient_config.dart';
import 'clock.dart';
import 'smoothed_value.dart';
import 'signature/signature_source.dart';

/// Stream of raw decibel readings.
typedef DecibelStream = Stream<double>;

/// Reads the loudness of the room and normalises it to 0..1.
///
/// PRIVACY: only the level of the sound is read, in memory. No sample is ever
/// stored, written to disk or sent anywhere. The raw dB value is kept because
/// the debug panel shows it, but it is only a number, not audio.
///
/// ACCURACY: phone microphones are not calibrated and the automatic gain
/// control of the device changes the reading a lot (a quiet room can read
/// 60 dB on one phone and 30 dB on another). The value is therefore useful to
/// compare moments on the same device, not as an absolute measurement.
///
/// The level of a place barely moves: a room reads 60 to 70 dB all the time.
/// The noise is therefore built from three parts:
///
/// * the level above the session's slowly learned quiet floor;
/// * the level over the baseline, the loudness of the place without the
///   peaks, which is what a shout or a clap stands out from;
/// * the burst, which appears when the level goes over the baseline and
///   falls back slowly, so a single clap is a visible event.
class NoiseService {
  /// Creates the service.
  ///
  /// [decibelStream] is injected so tests can feed known values.
  NoiseService({
    DecibelStream? decibelStream,
    SmoothedValue? smoother,
    this.enabled = true,
    this.clock = stopwatchClock,
  }) : decibelStream = decibelStream ?? microphoneDecibelStream(),
       smoother =
           smoother ??
           SmoothedValue(
             attack: AmbientConfig.timeConstant(AmbientConfig.noiseAttack),
             release: AmbientConfig.timeConstant(AmbientConfig.noiseRelease),
           ),
       _fast = SmoothedValue(
         attack: AmbientConfig.timeConstant(AmbientConfig.noiseFastSmoothing),
         release: AmbientConfig.timeConstant(AmbientConfig.noiseFastSmoothing),
       ),
       _burst = SmoothedValue(
         attack: AmbientConfig.timeConstant(AmbientConfig.noiseBurstAttack),
         release: AmbientConfig.timeConstant(AmbientConfig.noiseBurstRelease),
       ),
       _baseline = SmoothedValue(
         attack: AmbientConfig.noiseBaseline,
         release: AmbientConfig.noiseBaseline,
       );

  /// Whether the microphone is used.
  ///
  /// When the user refuses the microphone the noise stays at zero, without
  /// touching the microphone at all. The onboarding sets it before the
  /// viewfinder starts.
  bool enabled;
  final _signature = SignatureSource(1);
  List<SignatureReading> get signatureReadings =>
      enabled ? _signature.readings(clock()) : const [SignatureReading()];

  /// The source of the raw decibel readings.
  final DecibelStream decibelStream;

  /// The smoother applied to the normalised reading.
  final SmoothedValue smoother;

  /// The clock used to measure the time between samples.
  final Clock clock;

  /// The level of the place, smoothed fast so a shout is not missed.
  final SmoothedValue _fast;

  /// The burst over the baseline.
  final SmoothedValue _burst;

  /// The loudness of the place without the peaks.
  final SmoothedValue _baseline;

  StreamSubscription<double>? _subscription;
  int _lastSampleMicros = 0;
  bool _hasSample = false;
  double? _rawDb;
  double? _baselineDb;
  double _warmupSum = 0;
  int _warmupCount = 0;
  Duration _warmupElapsed = Duration.zero;
  bool _warmupDone = false;
  double _floorDb = AmbientConfig.noiseFloorDb;
  double _ceilingDb = math.max(
    AmbientConfig.noiseCeilingDb,
    AmbientConfig.noiseFloorDb + AmbientConfig.noiseMinSpanDb,
  );
  final Queue<(int, double)> _quietHistory = Queue<(int, double)>();
  double _quietTarget = AmbientConfig.noiseFloorDb;

  /// Session-only P10 quiet reference. Only scalar dB levels are retained.
  double get floorDb => _floorDb;

  /// Learned session envelope; never below the initial 72 dB ceiling.
  double get ceilingDb => _ceilingDb;

  /// Whether the microphone is being read.
  ///
  /// The microphone must never be open while the viewfinder is not visible,
  /// so the lifecycle of the screen is checked with this.
  bool get isListening => _subscription != null;

  /// The normalised loudness, 0..1.
  double get level => smoother.value;

  /// The last raw reading in dB, or null while nothing has been measured.
  double? get rawDb => _rawDb;

  /// The loudness of the place in dB, without the peaks.
  ///
  /// It is the reference the noise is compared against, so it is null only
  /// before the first reading.
  double? get baselineDb => _baselineDb;

  /// How much of the noise is a peak over the baseline, 0..1.
  ///
  /// It is null before the first reading.
  double? get burst => _hasSample ? _burst.value : null;

  /// Starts listening. Calling it twice is harmless.
  void start() {
    if (!enabled) return;
    if (_subscription != null) return;
    _lastSampleMicros = clock();
    _subscription = decibelStream.listen(_onReading, onError: _onError);
  }

  /// Stops listening. Calling it twice is harmless.
  void stop() {
    _signature.clear();
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }

  /// Feeds a raw reading. Exposed for tests and for fake microphones.
  void addReading(double db) => _onReading(db);

  void _onReading(double db) {
    // A perfectly silent room makes `noise_meter` report -infinity (a
    // logarithm of zero); treat it as silence instead of poisoning the
    // smoothed value.
    final value = db.isFinite ? db : 0.0;
    final now = clock();
    final elapsed = _elapsedSince(now);
    if (db.isFinite) _signature.update([db], now);
    _rawDb = value;
    if (db.isFinite) _updateFloor(value, now, elapsed);
    final decay = math.exp(
      -elapsed.inMicroseconds.clamp(0, 1 << 62) /
          AmbientConfig.noiseCeilingDecay.inMicroseconds,
    );
    _ceilingDb = math.max(
      _floorDb + AmbientConfig.noiseMinSpanDb,
      math.max(
        value,
        AmbientConfig.noiseCeilingDb +
            (_ceilingDb - AmbientConfig.noiseCeilingDb) * decay,
      ),
    );

    // The fast reading follows the level of the place without the lag of
    // the slow filters.
    final fastDb = _fast.update(value, elapsed);

    // The baseline is the loudness of the place without the peaks.
    final baseline = _updateBaseline(value, elapsed);

    final absolute = mapDecibels(
      fastDb,
      floorDb: _floorDb,
      ceilingDb: _ceilingDb,
    );
    final relative = baseline == null
        ? 0.0
        : ((fastDb - baseline) / AmbientConfig.noiseRelativeSpanDb).clamp(
            0.0,
            1.0,
          );
    final burstTarget = baseline == null
        ? 0.0
        : ((fastDb - baseline - AmbientConfig.noiseBurstThresholdDb) /
                  AmbientConfig.noiseBurstSpanDb)
              .clamp(0.0, 1.0);
    final burst = _burst.update(burstTarget, elapsed);

    final combined =
        AmbientConfig.noiseAbsoluteWeight * absolute +
        AmbientConfig.noiseRelativeWeight * relative;
    final target = math.max(combined, burst);
    smoother.update(target.clamp(0.0, 1.0), elapsed);
  }

  void _updateFloor(double db, int now, Duration elapsed) {
    // One scalar per second bounds memory and percentile work independently
    // of microphone callback frequency. Silence/invalid samples do not enter.
    while (_quietHistory.isNotEmpty &&
        now - _quietHistory.first.$1 >
            AmbientConfig.noiseFloorWindow.inMicroseconds) {
      _quietHistory.removeFirst();
    }
    if (_quietHistory.isEmpty || now - _quietHistory.last.$1 >= 1000000) {
      _quietHistory.addLast((now, db));
      final sorted = _quietHistory.map((entry) => entry.$2).toList()..sort();
      _quietTarget = sorted[(sorted.length * 0.1).ceil() - 1].clamp(
        AmbientConfig.noiseMinFloorDb,
        AmbientConfig.noiseMaxFloorDb,
      );
    }
    // A lifecycle gap is not evidence of a sustained room level.
    final dt = elapsed.inMicroseconds.clamp(0, 1000000);
    final alpha =
        1 - math.exp(-dt / AmbientConfig.noiseFloorAdaptation.inMicroseconds);
    _floorDb += alpha * (_quietTarget - _floorDb);
    _floorDb = _floorDb.clamp(
      AmbientConfig.noiseMinFloorDb,
      AmbientConfig.noiseMaxFloorDb,
    );
  }

  /// The loudness of the place without the peaks.
  ///
  /// It is the mean of the first second of data and, from then on, a slow
  /// average of the level with a time constant of twenty seconds. A shout
  /// barely moves it, which is the point: the noise is compared against the
  /// quiet of the place.
  double? _updateBaseline(double value, Duration elapsed) {
    if (!_warmupDone) {
      _warmupSum += value;
      _warmupCount++;
      _warmupElapsed += elapsed;
      final mean = _warmupSum / _warmupCount;
      _baselineDb = mean;
      if (_warmupElapsed >= AmbientConfig.noiseBaselineWarmup) {
        _warmupDone = true;
        _baseline.reset(mean);
      }
      return mean;
    }
    _baseline.update(value, elapsed);
    final baseline = _baseline.value;
    _baselineDb = baseline;
    return baseline;
  }

  /// The time since the previous sample.
  ///
  /// The first sample has no history, so a nominal period is used instead of
  /// nothing at all.
  Duration _elapsedSince(int now) {
    if (!_hasSample) {
      _hasSample = true;
      _lastSampleMicros = now;
      return nominalSamplePeriod;
    }
    final elapsed = Duration(microseconds: now - _lastSampleMicros);
    _lastSampleMicros = now;
    return elapsed;
  }

  void _onError(Object error, StackTrace stackTrace) {
    // The microphone can fail (a call takes it, the OS revokes the
    // permission). The noise simply stays where it was.
    _signature.clear();
    _rawDb = null;
  }

  /// Maps a raw dB reading to the 0..1 scale.
  ///
  /// The quiet end has a gentle knee to suppress small room-level variations
  /// during the slow calibration. Intensity is applied by AmbientController.
  static double mapDecibels(
    double db, {
    double floorDb = AmbientConfig.noiseFloorDb,
    double ceilingDb = AmbientConfig.noiseCeilingDb,
  }) {
    if (db.isNaN) return 0;
    if (db <= floorDb) return 0;
    ceilingDb = math.max(ceilingDb, floorDb + AmbientConfig.noiseMinSpanDb);
    if (db >= ceilingDb) return 1;
    return math.pow((db - floorDb) / (ceilingDb - floorDb), 1.6).toDouble();
  }
}

/// The default microphone source: the loudness reported by `noise_meter`.
/// The package only exposes the level of the sound, never the samples.
DecibelStream microphoneDecibelStream() =>
    NoiseMeter().noise.map((reading) => reading.meanDecibel);
