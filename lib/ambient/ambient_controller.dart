import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import 'ambient_config.dart';
import 'ambient_state.dart';
import 'clock.dart';
import 'light_service.dart';
import 'motion_service.dart';
import 'noise_service.dart';
import 'signal_intensity.dart';
import 'signature/signature_controller.dart';
import 'signature/signature_signals.dart';
import 'signature/signature_state.dart';
import 'spectrum_service.dart';

/// Merges the three ambient sources into a single [AmbientState] and keeps a
/// short history for peak-preserving captures (P90 noise/motion, mean light).
///
/// The controller is a [ValueNotifier]: the UI listens to it and the effect
/// renderer reads the current value for every frame.
class AmbientController extends ValueNotifier<AmbientState> {
  /// Creates the controller.
  ///
  /// Every dependency is injected so the whole pipeline can be tested with
  /// fake sensors.
  AmbientController({
    required this.noise,
    required this.motion,
    required this.light,
    SpectrumService? spectrum,
    Random? random,
    SignatureController? signature,
    SignatureSignals? signals,
    DateTime Function()? utcNow,
    this.mergeInterval = AmbientConfig.mergeInterval,
    this.clock = stopwatchClock,
  }) : spectrum = spectrum ?? SpectrumService(),
       signature =
           signature ??
           SignatureController(random: random, clock: clock, utcNow: utcNow),
       super(AmbientState.calm) {
    // The contextual lanes share the sensors of the place: the gravity of the
    // motion service and the raw bands of the spectrum service. No second
    // subscription is opened for any of them.
    this.signals =
        signals ??
        SignatureSignals(
          gravity: () => motion.latestGravity,
          spectrum: () => this.spectrum.lastRawReading,
          // Every native reading is drained in order, so a burst between two
          // ticks does not collapse into its last value.
          spectrumDrain: () => this.spectrum.drainRawReadings(),
          clock: clock,
        );
    // A build can ask for the values by hand, so a screenshot or a test of
    // the effects can be reproduced.
    final manual = AppConfig.manualValues;
    if (manual != null) {
      _manual = true;
      _manualNoise = manual[0];
      _manualLight = manual[1];
      _manualMotion = manual[2];
      // The values are published right away: the picture of the first frame
      // must already show them.
      tick();
    }
  }

  /// The source of the loudness of the place.
  final NoiseService noise;

  /// The source of the movement of the place.
  final MotionService motion;

  /// The source of the light of the place.
  final LightService light;

  final SpectrumService spectrum;
  final SignatureController signature;

  /// The contextual lanes of the moment: warmth, hue, chroma allowance,
  /// spectral tilt, orientation axis and rhythmic pulse.
  ///
  /// They live in memory only. They are never serialized, logged or added to
  /// the key of the result cache.
  late final SignatureSignals signals;

  String? _styleId;
  int _recipeVersion = 1;

  /// Style changes do not consume the pending photo identity.
  void setStyle(String id, {int recipeVersion = 1}) {
    if (_styleId == id && _recipeVersion == recipeVersion) return;
    _styleId = id;
    _recipeVersion = recipeVersion;
    tick();
  }

  /// How often the three sources are merged.
  final Duration mergeInterval;

  /// The clock used to time the merged samples.
  final Clock clock;

  /// The stream of the merged states.
  ///
  /// The peak detector of the moment mode listens to it, so it sees every
  /// sample of the place and not only the last value.
  Stream<AmbientState> get states => _states.stream;

  final Queue<_Sample> _ring = Queue<_Sample>();
  final StreamController<AmbientState> _states =
      StreamController<AmbientState>.broadcast();
  Timer? _timer;
  SignalIntensity _intensity = SignalIntensity.normal;
  SignalIntensity get intensity => _intensity;
  void setIntensity(SignalIntensity intensity) {
    if (_intensity == intensity) return;
    _intensity = intensity;
    _ring.clear();
    tick();
  }

  bool _manual = false;
  double _manualNoise = 0;
  double _manualLight = 0.5;
  double _manualMotion = 0;

  /// Whether the controller is merging.
  bool get isRunning => _timer != null;

  /// Whether the values are set by hand instead of measured.
  ///
  /// The debug panel switches to this mode, so a screenshot or a test of
  /// the effects can be reproduced.
  bool get isManual => _manual;

  /// The value of the noise set by hand, 0..1.
  double get manualNoise => _manualNoise;

  /// The value of the light set by hand, 0..1.
  double get manualLight => _manualLight;

  /// The value of the movement set by hand, 0..1.
  double get manualMotion => _manualMotion;

  /// Turns the manual mode on or off.
  ///
  /// In manual mode the controller gives exactly the values that were set
  /// by hand and nothing is measured. Switching modes clears the short
  /// history so a snapshot taken right after the switch is not
  /// contaminated with values from the previous phase.
  void setManual(bool value) {
    if (_manual == value) return;
    _manual = value;
    // The history is dropped at every transition: a capture that fires
    // immediately after switching back to automatic must average only the
    // measured samples, not the manual ones that accumulated just before.
    _ring.clear();
    tick();
  }

  /// Sets the values of the manual mode.
  ///
  /// The values that are not given keep the value they had. The history is
  /// also cleared so a manual snapshot does not mix with an automatic one
  /// taken shortly after.
  void setManualValues({double? noise, double? light, double? motion}) {
    if (noise != null) _manualNoise = noise.clamp(0.0, 1.0);
    if (light != null) _manualLight = light.clamp(0.0, 1.0);
    if (motion != null) _manualMotion = motion.clamp(0.0, 1.0);
    _ring.clear();
    tick();
  }

  /// Starts the three services and the merge timer.
  void start() {
    if (_timer != null) return;
    noise.start();
    motion.start();
    light.start();
    spectrum.enabled = noise.enabled;
    spectrum.start();
    // The contextual lanes start with the rest of the pipeline: the
    // magnetometer is only read while the viewfinder is visible.
    signals.start();
    _timer = Timer.periodic(mergeInterval, (_) => tick());
    tick();
  }

  /// Stops the merge timer and the three services.
  void stop() {
    _timer?.cancel();
    _timer = null;
    noise.stop();
    motion.stop();
    light.stop();
    spectrum.stop();
    // The transient lanes are dropped, so the next session starts neutral.
    signals.stop();
    signature.clear();
  }

  @override
  void dispose() {
    stop();
    unawaited(_states.close());
    super.dispose();
  }

  /// Merges the three sources once and publishes the result.
  ///
  /// The timer calls this at about 30 Hz. It is public so tests can drive the
  /// controller deterministically.
  void tick() {
    final now = clock();
    // The producers that need polling are refreshed here: the civil-time
    // palette at about 1 Hz and the raw spectrum of the session.
    signals.update();
    final state = _manual ? _manualState() : _measuredState();
    _push(now, state);
    value = state;
    _states.add(state);
  }

  /// The state of the three sensors.
  AmbientState _measuredState() => AmbientState(
    noise: intensity.apply(noise.level),
    light: light.level,
    motion: intensity.apply(motion.level),
    motionDirX: motion.dirX,
    motionDirY: motion.dirY,
    bass: spectrum.bass,
    mid: spectrum.mid,
    treble: spectrum.treble,
    seed: signature.seed,
    signature: signals.applyLanes(signature.state),
    rawDb: noise.rawDb,
    rawLuma: light.rawLuma,
    rawAccel: motion.rawAccel,
    rawLux: light.rawLux,
    baselineDb: noise.baselineDb,
    burst: noise.burst,
    noiseCeilingDb: noise.ceilingDb,
    sceneMotion: motion.sceneLevel,
    gyroMotion: motion.gyroLevel,
    accelMotion: motion.accelLevel,
    rawGyro: motion.rawGyro,
  );

  /// The state of the values set by hand.
  ///
  /// The contextual lanes stay neutral in manual mode, so a screenshot or a
  /// test of the effects is reproducible.
  AmbientState _manualState() => AmbientState(
    noise: _manualNoise,
    light: _manualLight,
    motion: _manualMotion,
    seed: signature.seed,
    signature: signature.state,
  );

  /// Nearest-rank P90 noise/motion and mean light over the last [window].
  /// Raw diagnostics remain means. Direction and motion component diagnostics
  /// come from the sample selected by motion P90, avoiding cancellation between
  /// opposing movements. Empty windows return the current state; manual values
  /// bypass both the curve and temporal aggregation.
  AmbientState snapshot([Duration window = AmbientConfig.snapshotWindow]) {
    final frozen = _snapshot(window);
    // The lanes are frozen at the shutter, synchronously and before any
    // await, exactly like the fingerprint. The values that arrive later
    // belong to the next picture.
    final lanes = _manual ? SignatureState.neutral : signals.moodLanes();
    final capture = signature.freeze(
      styleId: _styleId ?? 'static',
      recipeVersion: _recipeVersion,
      readings: _manual
          ? const []
          : [
              ...motion.signatureReadings,
              ...noise.signatureReadings,
              ...spectrum.signatureReadings,
            ],
    );
    // The frozen lanes travel with the capture, so the decode, the crop and
    // the export of the same picture always use the same values.
    final frozenCapture = CaptureSignature(
      seed: capture.seed,
      signature: capture.signature.withMood(
        warmth: lanes.warmth,
        hue: lanes.hue,
        chromaAllowance: lanes.chromaAllowance,
        tilt: lanes.tilt,
        axisX: lanes.axisX,
        axisY: lanes.axisY,
        pulse: lanes.pulse,
        reserved: lanes.reserved,
      ),
      identity: capture.identity,
    );
    final result = frozen.withCaptureSignature(frozenCapture);
    // Publish the next pending pattern only after the shutter state is frozen.
    // This is an identity transition, not another sensor/history sample.
    value = _manual ? _manualState() : _measuredState();
    _states.add(value);
    return result;
  }

  AmbientState _snapshot(Duration window) {
    if (_manual) return _manualState();
    final cutoff = clock() - window.inMicroseconds;
    var count = 0;
    final noiseSamples = <double>[];
    final motionSamples = <AmbientState>[];
    var light = 0.0;
    var rawDb = 0.0;
    var rawLuma = 0.0;
    var rawAccel = 0.0;
    var rawLux = 0.0;
    var baselineDb = 0.0;
    var burst = 0.0;
    var rawDbCount = 0;
    var rawLumaCount = 0;
    var rawAccelCount = 0;
    var rawLuxCount = 0;
    var baselineDbCount = 0;
    var burstCount = 0;

    for (final sample in _ring) {
      if (sample.time < cutoff) continue;
      count++;
      noiseSamples.add(sample.state.noise);
      light += sample.state.light;
      motionSamples.add(sample.state);
      final db = sample.state.rawDb;
      if (db != null) {
        rawDb += db;
        rawDbCount++;
      }
      final luma = sample.state.rawLuma;
      if (luma != null) {
        rawLuma += luma;
        rawLumaCount++;
      }
      final accel = sample.state.rawAccel;
      if (accel != null) {
        rawAccel += accel;
        rawAccelCount++;
      }
      final lux = sample.state.rawLux;
      if (lux != null) {
        rawLux += lux;
        rawLuxCount++;
      }
      final baseline = sample.state.baselineDb;
      if (baseline != null) {
        baselineDb += baseline;
        baselineDbCount++;
      }
      final peak = sample.state.burst;
      if (peak != null) {
        burst += peak;
        burstCount++;
      }
    }

    if (count == 0) return value;

    noiseSamples.sort();
    motionSamples.sort((a, b) => a.motion.compareTo(b.motion));
    final rank = (count * AmbientConfig.snapshotPercentile).ceil() - 1;
    final peakMotion = motionSamples[rank];
    return AmbientState(
      noise: noiseSamples[rank],
      light: light / count,
      bass: value.bass,
      mid: value.mid,
      treble: value.treble,
      motion: peakMotion.motion,
      motionDirX: peakMotion.motionDirX,
      motionDirY: peakMotion.motionDirY,
      sceneMotion: peakMotion.sceneMotion,
      gyroMotion: peakMotion.gyroMotion,
      accelMotion: peakMotion.accelMotion,
      rawGyro: peakMotion.rawGyro,
      noiseCeilingDb: noise.ceilingDb,
      rawDb: rawDbCount == 0 ? null : rawDb / rawDbCount,
      rawLuma: rawLumaCount == 0 ? null : rawLuma / rawLumaCount,
      rawAccel: rawAccelCount == 0 ? null : rawAccel / rawAccelCount,
      rawLux: rawLuxCount == 0 ? null : rawLux / rawLuxCount,
      baselineDb: baselineDbCount == 0 ? null : baselineDb / baselineDbCount,
      burst: burstCount == 0 ? null : burst / burstCount,
    );
  }

  /// Empties the history, used when the camera is paused.
  void clearHistory() {
    _ring.clear();
  }

  void _push(int time, AmbientState state) {
    _ring.addLast(_Sample(time, state));
    while (_ring.length > AmbientConfig.ringCapacity) {
      _ring.removeFirst();
    }
  }
}

class _Sample {
  const _Sample(this.time, this.state);

  final int time;
  final AmbientState state;
}
