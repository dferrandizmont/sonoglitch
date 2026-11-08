import 'ambient_config.dart';

/// The rate at which the gyroscope and the accelerometer are read.
///
/// The sensors are read at [activePeriod] while the phone moves. When their
/// readings stay below [quietLevel] for [quietAfter], the phone is still:
/// the sensors are read at [quietPeriod] instead, which costs less battery
/// and leaves the CPU of the phone free for the picture.
///
/// The decision has a hysteresis: the phone counts as still below
/// [quietLevel], but it only leaves that state above [wakeLevel], which is
/// higher. A phone in the hand hovers around the threshold, and without the
/// gap it would change its rate every few seconds, resubscribing the
/// platform streams each time and losing samples. The quiet state is also
/// kept for at least [quietDwell] once it is left, so the rate cannot change
/// twice in a row.
///
/// The first reading above [wakeLevel] brings the fast rate back at once,
/// so a movement is never missed.
///
/// The decision uses the period of the reading and not its count: the value
/// the effects see is the magnitude of each sample, so it does not depend
/// on how often the sensors are read.
class MotionSensorRate {
  /// Creates the rate with the periods and the threshold of the app.
  MotionSensorRate({
    this.activePeriod = AmbientConfig.motionSensorPeriod,
    this.quietPeriod = AmbientConfig.motionSensorQuietPeriod,
    this.quietAfter = AmbientConfig.motionSensorQuietAfter,
    this.quietLevel = AmbientConfig.motionSensorQuietLevel,
    this.wakeLevel = AmbientConfig.motionSensorWakeLevel,
    this.quietDwell = AmbientConfig.motionSensorQuietDwell,
  });

  /// The period used while the phone moves.
  final Duration activePeriod;

  /// The period used while the phone is still.
  final Duration quietPeriod;

  /// How long the readings have to stay below [quietLevel] before the
  /// sensors are read slowly.
  final Duration quietAfter;

  /// The level below which the phone counts as still.
  final double quietLevel;

  /// The level above which the phone counts as moving again.
  ///
  /// It is above [quietLevel], so a reading between the two keeps the quiet
  /// rate instead of changing it.
  final double wakeLevel;

  /// How long the sensors stay in the quiet rate at least.
  ///
  /// It stops two changes of the rate from happening one after the other.
  final Duration quietDwell;

  int? _quietSinceMicros;
  bool _quiet = false;
  int? _leftQuietMicros;

  /// Whether the sensors are read slowly.
  bool get isQuiet => _quiet;

  /// The period the sensors must be read with.
  Duration get period => _quiet ? quietPeriod : activePeriod;

  /// Forgets the history, so the next reading starts a new session.
  void reset() {
    _quiet = false;
    _quietSinceMicros = null;
    _leftQuietMicros = null;
  }

  /// Feeds the level of the sensors (0..1) read at [micros] and returns the
  /// period the sensors must be read with from now on.
  Duration observe(double level, int micros) {
    if (!level.isFinite) {
      // A broken reading says nothing about the movement: the current rate
      // is kept.
      return period;
    }
    if (_quiet) {
      if (level <= wakeLevel) {
        // The phone is still: the quiet rate stays. The gap between the two
        // levels keeps a phone in the hand from changing its rate every few
        // seconds.
        return quietPeriod;
      }
      // The phone moved: the fast rate comes back at once, so the start of
      // the movement is never missed.
      _quiet = false;
      _quietSinceMicros = null;
      _leftQuietMicros = micros;
      return activePeriod;
    }
    if (level > quietLevel) {
      // The phone moved before it was still: the quiet period starts again
      // from this reading.
      _quietSinceMicros = null;
      return activePeriod;
    }
    final since = _quietSinceMicros;
    if (since == null) {
      _quietSinceMicros = micros;
      return activePeriod;
    }
    if (micros - since < quietAfter.inMicroseconds) {
      // The phone has not been still long enough yet.
      return activePeriod;
    }
    final left = _leftQuietMicros;
    if (left != null && micros - left < quietDwell.inMicroseconds) {
      // The quiet state was left a moment ago: the rate does not change
      // again, so the platform streams are not resubscribed twice in a row.
      return activePeriod;
    }
    _quiet = true;
    _quietSinceMicros = null;
    return quietPeriod;
  }
}
