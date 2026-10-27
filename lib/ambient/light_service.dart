import 'dart:async';
import 'dart:math' as math;

import 'ambient_config.dart';
import 'ambient_light_source.dart';
import 'clock.dart';
import 'smoothed_value.dart';

/// Turns the light of the place into a 0..1 light level.
///
/// The main source is the light sensor of the phone: it sees the place
/// instead of what the camera is aimed at, so it does not get cancelled by
/// the automatic exposure of the camera. The mean luma (0..255) of the
/// frames, computed by the camera pipeline while it converts them, is the
/// fallback for the devices without a light sensor and rounds the reading
/// of the sensor off.
class LightService {
  /// Creates the service.
  ///
  /// [ambientLight] is injected so tests can feed known values.
  LightService({
    AmbientLightSource? ambientLight,
    SmoothedValue? smoother,
    this.clock = stopwatchClock,
  }) : ambientLight = ambientLight ?? platformAmbientLightSource(),
       smoother =
           smoother ??
           SmoothedValue(
             attack: AmbientConfig.lightAttack,
             release: AmbientConfig.lightRelease,
           );

  /// The source of the lux of the place.
  final AmbientLightSource ambientLight;

  /// The smoother applied to the light level.
  final SmoothedValue smoother;

  /// The clock used to measure the time between samples.
  final Clock clock;

  StreamSubscription<double>? _luxSubscription;
  int _lastSampleMicros = 0;
  bool _hasSample = false;
  double? _rawLuma;
  double? _rawLux;
  double _lumaLevel = 0;
  double _luxLevel = 0;
  bool _luxUsable = false;

  /// Whether the light sensor is being read.
  bool get isListening => _luxSubscription != null;

  /// The normalised light level, 0..1.
  double get level => smoother.value;

  /// The last mean luma (0..255), or null while nothing has been measured.
  double? get rawLuma => _rawLuma;

  /// The last reading of the light sensor in lux, or null while there is
  /// none.
  double? get rawLux => _rawLux;

  /// Whether the reading of the light sensor is being used.
  ///
  /// It is not when the device has no light sensor: the brightness of the
  /// picture is then the only source.
  bool get hasLux => _luxUsable;

  /// Starts reading the light sensor. Calling it twice is harmless.
  void start() {
    if (_luxSubscription != null) return;
    if (!ambientLight.available) return;
    try {
      _luxSubscription = ambientLight.lux.listen(_onLux, onError: _onLuxError);
    } catch (_) {
      // The plugin of the platform is not there (or there is no binding to
      // talk to it): the brightness of the picture is used alone.
      _luxSubscription = null;
      _luxUsable = false;
    }
  }

  /// Stops reading the light sensor. Calling it twice is harmless.
  void stop() {
    final subscription = _luxSubscription;
    _luxSubscription = null;
    unawaited(subscription?.cancel());
  }

  /// Feeds the mean luma of a frame.
  void addLuma(double meanLuma) {
    if (!meanLuma.isFinite) return;
    _rawLuma = meanLuma;
    _lumaLevel = mapLuma(meanLuma);
    _update();
  }

  void _onLux(double lux) {
    if (!lux.isFinite || lux < 0) return;
    _rawLux = lux;
    _luxLevel = mapLux(lux);
    _luxUsable = true;
    _update();
  }

  void _onLuxError(Object error, StackTrace stackTrace) {
    // The device has no light sensor (the plugin ends the stream with an
    // `unavailable` error). The brightness of the picture is used alone, so
    // the app keeps working.
    _luxUsable = false;
    _rawLux = null;
    _update();
  }

  /// Merges the two sources and smooths the result.
  void _update() {
    final elapsed = _elapsedSince(clock());
    final target = _luxUsable
        ? AmbientConfig.luxWeight * _luxLevel +
              AmbientConfig.lumaWeight * _lumaLevel
        : _lumaLevel;
    smoother.update(target, elapsed);
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

  /// Forgets the measurement, used when the camera is paused.
  void reset() {
    _rawLuma = null;
    smoother.reset();
  }

  /// Maps a mean luma (0..255) to the 0..1 scale.
  ///
  /// A gentle smoothstep: it keeps the extremes (a black frame stays dark, a
  /// white frame stays bright) and spreads the middle of the range, where most
  /// indoor scenes live, without the harsh contrast of a linear map.
  static double mapLuma(double meanLuma) {
    if (!meanLuma.isFinite) return 0;
    final t = (meanLuma / 255).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Maps a reading of the light sensor, in lux, to the 0..1 scale.
  ///
  /// The lux of a place span many decades, so the mapping is logarithmic:
  /// about 10 lux (a dark room) reads 0.23, 300 lux (a lit room) 0.55,
  /// 5000 lux (the shade of a tree) 0.82 and 30000 lux (the direct sun) 1.
  static double mapLux(double lux) {
    if (!lux.isFinite || lux <= 0) return 0;
    final level = math.log(lux + 1) / math.ln10 / AmbientConfig.luxRange;
    return level.clamp(0.0, 1.0);
  }
}
