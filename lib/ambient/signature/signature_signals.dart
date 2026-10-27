import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../clock.dart';
import '../context_sensors.dart' show SensorVector;
import '../spectrum_source.dart';
import 'calendar_signature.dart';
import 'heading_service.dart';
import 'rhythm_tracker.dart';
import 'scene_signature.dart';
import 'signature_state.dart';
import 'spectral_tilt.dart';

export '../spectrum_source.dart' show RawSpectrumReading;

/// The magnetometer of the device, when the platform has one.
///
/// The plugin asks the platform for its sampling period with a call whose
/// result it drops, so an instrument that is not there answers with an error
/// of its own. The platform is called inside a guarded zone, so a device
/// without a magnetometer keeps the neutral axis instead of raising an
/// error.
Stream<SensorVector> platformMagnetometer() {
  late final StreamSubscription<SensorVector> subscription;
  final controller = StreamController<SensorVector>.broadcast(
    onCancel: () => _guarded(subscription.cancel),
  );
  _guarded(() {
    subscription =
        magnetometerEventStream(
              samplingPeriod: const Duration(milliseconds: 100),
            )
            .map((event) => (x: event.x, y: event.y, z: event.z))
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
  });
  return controller.stream;
}

/// Runs [action] where a missing instrument cannot raise an error.
void _guarded(FutureOr<void> Function() action) {
  runZonedGuarded(
    () {
      final result = action();
      if (result is Future<void>) {
        result.catchError((Object _) {});
      }
    },
    (Object error, StackTrace stack) {
      // The platform has no magnetometer: the axis keeps its neutral value.
    },
  );
}

/// The contextual lanes of a shot: the moment and the place, in memory only.
///
/// The class aggregates the producers of delivery 2 behind one injectable
/// service: the civil-time palette, the magnetic bearing of the optical axis,
/// the rhythm of the place, the spectral tilt of the place and the
/// colourfulness of the scene.
///
/// Nothing here is stored, logged or sent. The lanes are sampled while the
/// viewfinder is visible, frozen at the shutter and dropped with the session.
/// Every producer has an explicit neutral fallback, so a missing sensor leaves
/// the picture exactly as it was without the signal.
class SignatureSignals {
  /// Creates the service.
  ///
  /// Every dependency is injected, so the whole pipeline can be driven with
  /// fake sensors and a fake clock.
  SignatureSignals({
    required this.gravity,
    this.spectrum,
    this.spectrumDrain,
    Stream<SensorVector> Function()? magnetometer,
    DateTime Function()? localNow,
    this.clock = stopwatchClock,
  }) : _localNow = localNow ?? DateTime.now,
       _heading = HeadingService(
         gravity: gravity,
         samples: magnetometer ?? platformMagnetometer,
         clock: clock,
       ),
       _rhythm = RhythmTracker(clock: clock),
       _tilt = SpectralTiltFilter(clock: clock),
       _scene = SceneColorFilter(clock: clock),
       _calendar = const CalendarSignature();

  /// The shared gravity of the device, timestamped with the same clock.
  ///
  /// It comes from the motion service, so no second accelerometer
  /// subscription is opened.
  final TimedGravity? Function() gravity;

  /// The optional source of the latest raw spectrum reading.
  ///
  /// The native stream is not subscribed again: the reading published by the
  /// spectrum service is polled and repeats are ignored by timestamp.
  final RawSpectrumReading? Function()? spectrum;

  /// The optional source of the raw spectrum readings that are waiting.
  ///
  /// The native stream is not subscribed again either: the spectrum service
  /// publishes every reading it receives and the lanes drain them in order,
  /// so several readings between two ticks reach the tracker and the tilt
  /// filter as they arrived instead of collapsing into the last one.
  final List<RawSpectrumReading> Function()? spectrumDrain;

  /// The clock used to time the producers.
  final Clock clock;

  /// How often the civil-time palette is refreshed.
  ///
  /// The palette only moves with the hour, so one refresh per second is
  /// enough and the merge tick does not have to touch it.
  static const int calendarIntervalMicros = 1000000;

  final DateTime Function() _localNow;
  final HeadingService _heading;
  final RhythmTracker _rhythm;
  final SpectralTiltFilter _tilt;
  final SceneColorFilter _scene;

  CalendarSignature _calendar;
  int? _lastCalendarMicros;
  int? _lastSpectrumMicros;
  bool _running = false;

  /// Whether the producers are running.
  bool get isRunning => _running;

  /// The number of rhythmic attacks the tracker has registered.
  ///
  /// It is exposed for deterministic checks of the wiring: a rise that
  /// arrives between two ticks is only seen when the reading is not lost.
  int get rhythmAttacks => _rhythm.bufferedAttacks;

  /// The orientation axis of the optical axis, as the heading service sees it.
  ({double x, double y}) get axis => _heading.axis;

  /// Starts the producers. Calling it twice is harmless.
  void start() {
    if (_running) return;
    _running = true;
    _heading.start();
    _rhythm.start();
    _tilt.start();
    _scene.start();
  }

  /// Stops the producers, cancels the magnetometer input and drops every
  /// transient value. Calling it twice is harmless.
  void stop() {
    _running = false;
    _heading.stop();
    _rhythm.stop();
    _tilt.stop();
    _scene.stop();
    clear();
  }

  /// Drops the transient values of the producers, without touching the
  /// subscriptions. A stopped service starts again from the neutral lanes.
  void clear() {
    _rhythm.clear();
    _tilt.clear();
    _scene.clear();
    // The readings that arrived while the producers were idle are dropped
    // with the rest of the transient values.
    spectrumDrain?.call();
    _lastSpectrumMicros = null;
    _lastCalendarMicros = null;
    _calendar = const CalendarSignature();
  }

  /// Refreshes the producers that need polling. Called once per ambient tick.
  void update() {
    if (!_running) return;
    _refreshCalendar();
    updateSpectrum();
  }

  /// Reads the raw spectrum of the session once.
  ///
  /// The native stream is not subscribed again: the readings already
  /// published by the spectrum service are drained in order, so a burst
  /// between two ticks is not collapsed into its last value. The latest
  /// reading is polled as well, for the sources that do not queue.
  void updateSpectrum() {
    final drain = spectrumDrain;
    if (drain != null) {
      for (final reading in drain()) {
        addSpectrum(reading.bands, reading.timeMicros);
      }
    }
    final source = spectrum;
    if (source == null) return;
    final reading = source();
    if (reading == null) return;
    addSpectrum(reading.bands, reading.timeMicros);
  }

  /// Feeds one raw spectrum reading, timestamped in monotonic microseconds.
  void addSpectrum(SpectrumBands bands, int timeMicros) {
    final last = _lastSpectrumMicros;
    if (last != null && timeMicros <= last) return;
    _lastSpectrumMicros = timeMicros;
    _rhythm.add(timeMicros, bands.bass, bands.mid, bands.treble);
    _tilt.add(bands, timeMicros);
  }

  /// Feeds the colourfulness of one converted frame.
  ///
  /// The reading is timestamped with the clock of the pipeline, so a stale
  /// frame falls back to the neutral allowance on its own.
  void addScene(SceneColorReading reading) => _scene.add(reading, clock());

  /// Forgets the colourfulness of the previous camera.
  ///
  /// A lens change, a camera restart or a pause must never show the value of
  /// another camera.
  void clearScene() => _scene.clear();

  void _refreshCalendar() {
    final now = clock();
    final last = _lastCalendarMicros;
    if (last != null && now - last < calendarIntervalMicros) return;
    _lastCalendarMicros = now;
    _calendar = calendarSignature(_localNow());
  }

  /// The current lanes, with the neutral value of every missing signal.
  ///
  /// The lanes are never NaN and never leave their range: warmth, hue, tilt
  /// and pulse are signed, the chroma allowance stays between 0.65 and 1 and
  /// the orientation axis is a unit vector.
  SignatureState moodLanes() {
    final axis = _heading.axis;
    return SignatureState(
      warmth: _signed(_calendar.warmth),
      hue: _signed(_calendar.hue),
      chromaAllowance: _chroma(_scene.allowance),
      tilt: _signed(_tilt.value),
      axisX: axis.x.isFinite ? axis.x.clamp(-1.0, 1.0) : 1,
      axisY: axis.y.isFinite ? axis.y.clamp(-1.0, 1.0) : 0,
      pulse: _signed(_rhythm.pulse),
      reserved: 0,
    );
  }

  /// Merges the current lanes into a fingerprint state.
  ///
  /// The fingerprint of the pending photo is kept, so a lane never loses the
  /// shot it belongs to.
  SignatureState applyLanes(SignatureState fingerprint) {
    final lanes = moodLanes();
    return fingerprint.withMood(
      warmth: lanes.warmth,
      hue: lanes.hue,
      chromaAllowance: lanes.chromaAllowance,
      tilt: lanes.tilt,
      axisX: lanes.axisX,
      axisY: lanes.axisY,
      pulse: lanes.pulse,
      reserved: lanes.reserved,
    );
  }
}

/// A signed contextual lane. A nonfinite value falls back to the neutral zero.
double _signed(double value) => value.isFinite ? value.clamp(-1.0, 1.0) : 0;

/// The chroma allowance never drops below the floor and never exceeds one.
double _chroma(double value) => value.isFinite ? value.clamp(0.65, 1.0) : 1;
