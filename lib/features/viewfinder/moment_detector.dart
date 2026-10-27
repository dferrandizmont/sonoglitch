import '../../ambient/ambient_state.dart';
import '../../ambient/clock.dart';

/// The tuning of the [MomentDetector].
///
/// The values live in one place so the moment mode can be reviewed at a
/// glance: a place has to be quiet for a second and then suddenly loud for
/// the picture to be taken.
class MomentDefaults {
  const MomentDefaults._();

  /// The instantaneous level that counts as a peak.
  static const double levelThreshold = 0.85;

  /// The level below which the place is quiet.
  static const double quietLevel = 0.6;

  /// How long the place has to be quiet before a peak counts.
  static const Duration quietPeriod = Duration(seconds: 1);

  /// The movement of the scene that counts as a jump.
  static const double motionThreshold = 0.8;

  /// The movement below which the scene is still.
  static const double quietMotion = 0.4;

  /// Maximum time for a sudden rise, allowing for scene motion smoothing.
  static const Duration motionRiseWindow = Duration(milliseconds: 150);

  /// How long the detector waits after a shot.
  static const Duration cooldown = Duration(seconds: 8);
}

/// Detects the peaks of a place, so the photo can be taken without touching
/// the shutter.
///
/// The detector watches the ambient values and says when something worth
/// photographing happened:
///
/// * the level of the place jumped over the threshold after it had been
///   quiet for a second, which is a goal being scored or a crowd roaring;
/// * the scene moved suddenly, which is a jump or a bump.
///
/// It is a plain object with no widgets and no platform code, so every rule
/// can be checked on its own. The armed state, the cooldown and the rules
/// that decide when a peak counts live here, so the screen only has to
/// decide what to do with the shot.
class MomentDetector {
  /// Creates the detector.
  ///
  /// [canFire] is asked before every shot, so the caller can forbid it
  /// while a photo is being taken or while nobody is looking at the
  /// viewfinder.
  MomentDetector({
    this.levelThreshold = MomentDefaults.levelThreshold,
    this.quietLevel = MomentDefaults.quietLevel,
    this.quietPeriod = MomentDefaults.quietPeriod,
    this.motionThreshold = MomentDefaults.motionThreshold,
    this.quietMotion = MomentDefaults.quietMotion,
    this.motionRiseWindow = MomentDefaults.motionRiseWindow,
    this.cooldown = MomentDefaults.cooldown,
    this.clock = stopwatchClock,
    this.keepArmed = false,
    this.canFire,
  });

  /// The level that counts as a peak.
  final double levelThreshold;

  /// The level below which the place is quiet.
  final double quietLevel;

  /// How long the place has to be quiet before a peak counts.
  final Duration quietPeriod;

  /// The movement of the scene that counts as a jump.
  final double motionThreshold;

  /// The movement below which the scene is still.
  final double quietMotion;

  /// Maximum time to rise from still to moving strongly.
  final Duration motionRiseWindow;

  /// How long the detector waits after a shot.
  final Duration cooldown;

  /// The clock that measures the quiet period and the cooldown.
  final Clock clock;

  /// Whether the detector stays armed after a shot.
  ///
  /// When it is off, the detector takes one photo at the peak and stops,
  /// so the camera never takes a photo on its own without the user asking
  /// for it again.
  bool keepArmed;

  /// Asked before every shot.
  ///
  /// The caller knows whether a photo can be taken right now: while another
  /// photo is being taken, while the app is in the background or while
  /// another screen covers the viewfinder, the answer is no.
  bool Function()? canFire;

  /// Whether the detector is waiting for a peak.
  bool _armed = false;

  /// Whether the place has been quiet long enough for a peak to count.
  ///
  /// A shot consumes this qualification; another noise peak needs a fresh
  /// observed quiet second.
  bool _quietReady = false;

  /// When the current quiet streak started, in microseconds.
  int? _quietSince;

  /// When the last shot was taken, in microseconds.
  int? _lastShotAt;

  /// Whether a sample was already seen.
  bool _hasSample = false;

  /// The level of the previous sample.
  double _level = 0;

  /// When the scene was last observed below the stillness threshold.
  int? _motionQuietAt;

  /// Whether the detector is waiting for a peak.
  bool get isArmed => _armed;

  /// Starts waiting for a peak.
  void arm() => _armed = true;

  /// Stops waiting for a peak.
  void disarm() => _armed = false;

  /// Forgets the samples.
  ///
  /// The detector starts again from scratch: the place has to be quiet for
  /// a second before a peak counts. The shot cooldown is preserved.
  void reset() {
    _hasSample = false;
    _level = 0;
    _motionQuietAt = null;
    _quietSince = null;
    _quietReady = false;
  }

  /// Feeds one sample of the place.
  ///
  /// Returns true when the sample is a peak worth photographing and the
  /// photo has to be taken.
  bool add(AmbientState state) {
    final now = clock();
    final level = instantaneousLevel(state);
    final motion = state.sceneMotion;

    // The level has to cross the threshold: a place that stays loud does
    // not fire once and again.
    final crossedLevel =
        _hasSample && _level < levelThreshold && level >= levelThreshold;
    // The scene has to jump: a phone that is being carried around moves all
    // the time and none of that is a peak.
    final motionQuietAt = _motionQuietAt;
    final jumpedMotion =
        motion > motionThreshold &&
        motionQuietAt != null &&
        Duration(microseconds: now - motionQuietAt) <= motionRiseWindow;
    if (motion < quietMotion) {
      _motionQuietAt = now;
    } else if (motion > motionThreshold ||
        (motionQuietAt != null &&
            Duration(microseconds: now - motionQuietAt) > motionRiseWindow)) {
      _motionQuietAt = null;
    }

    // The place is quiet while the level stays below the quiet level. The
    // credit is kept once the quiet second is done, so a peak that comes
    // later still counts.
    if (level < quietLevel) {
      final since = _quietSince ??= now;
      if (Duration(microseconds: now - since) >= quietPeriod) {
        _quietReady = true;
      }
    } else {
      _quietSince = null;
    }

    _hasSample = true;
    _level = level;

    if (!(crossedLevel && _quietReady || jumpedMotion)) return false;
    if (!_armed) return false;
    if (_inCooldown(now)) return false;
    // The caller knows whether a photo can be taken right now.
    final gate = canFire;
    if (gate != null && !gate()) return false;

    _lastShotAt = now;
    _quietReady = false;
    _quietSince = null;
    if (!keepArmed) _armed = false;
    return true;
  }

  /// The level of the place right now.
  ///
  /// The burst over the baseline counts as much as the level itself: a
  /// single clap is loud even when the place is quiet.
  static double instantaneousLevel(AmbientState state) {
    final burst = state.burst ?? 0;
    return burst > state.noise ? burst : state.noise;
  }

  /// Whether the detector is still waiting for the cooldown to pass.
  bool _inCooldown(int now) {
    final last = _lastShotAt;
    if (last == null) return false;
    return Duration(microseconds: now - last) < cooldown;
  }
}
