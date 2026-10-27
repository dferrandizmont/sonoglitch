/// Tuning constants of the ambient pipeline.
///
/// They live in one place so the mapping of the three variables is easy to
/// review: the noise floor and ceiling are the pair the product spec asks
/// for, the rest are the time constants of the smoothing.
class AmbientConfig {
  const AmbientConfig._();

  /// Noise below this level is ignored: it maps to 0 on the 0..1 scale.
  ///
  /// Phone microphones are not calibrated and the automatic gain control
  /// changes the reading depending on the device, so the absolute value is
  /// only meaningful as a relative one.
  static const double noiseFloorDb = 58;
  static const double noiseMinFloorDb = 45;
  static const double noiseMaxFloorDb = 70;
  static const double noiseMinSpanDb = 15;
  static const Duration noiseFloorWindow = Duration(minutes: 3);
  static const Duration noiseFloorAdaptation = Duration(minutes: 3);

  /// Noise at or above this level is full scale (1 on the 0..1 scale).
  static const double noiseCeilingDb = 72;

  /// Peak envelope falls 63% of the way back in ten minutes of quiet.
  static const Duration noiseCeilingDecay = Duration(minutes: 10);

  static const double subtleGamma = 1.0;
  static const double subtleGain = 0.85;
  static const double normalGamma = 0.7;
  static const double normalGain = 1.0;
  static const double extremeGamma = 0.5;
  static const double extremeGain = 1.15;

  /// How many dB over the baseline make the relative part full scale.
  ///
  /// The relative part is what moves: a shout twenty decibels over the
  /// loudness of the place is the top of the scale.
  static const double noiseRelativeSpanDb = 20;

  /// How many dB over the baseline a burst needs to start.
  static const double noiseBurstThresholdDb = 8;

  /// How many dB over the baseline make the burst full scale.
  static const double noiseBurstSpanDb = 18;

  /// How much of the noise comes from the absolute level of the place.
  static const double noiseAbsoluteWeight = 1.0;

  /// How much of the noise comes from the level over the baseline.
  static const double noiseRelativeWeight = 0.35;

  /// Time constant of the baseline: the loudness of the place without the
  /// peaks.
  ///
  /// It is slow on purpose: the baseline is the reference the noise is
  /// compared against, so it must not follow a shout.
  static const Duration noiseBaseline = Duration(seconds: 20);

  /// How long the baseline is measured at the start.
  ///
  /// The first second of data gives the first value of the baseline, so the
  /// app reacts from the very first moment.
  static const Duration noiseBaselineWarmup = Duration(seconds: 1);

  /// Time the fast reading of the level takes to reach the target.
  static const Duration noiseFastSmoothing = Duration(milliseconds: 100);

  /// Time the burst takes to rise.
  static const Duration noiseBurstAttack = Duration(milliseconds: 60);

  /// Time the burst takes to fall.
  static const Duration noiseBurstRelease = Duration(milliseconds: 1200);

  /// Time the noise takes to rise.
  static const Duration noiseAttack = Duration(milliseconds: 80);

  /// Time the noise takes to fall.
  static const Duration noiseRelease = Duration(milliseconds: 500);

  /// Acceleration, in m/s^2, that maps to the top of the 0..1 motion scale.
  ///
  /// Hand held phones move roughly between 0 and 10 m/s^2; 20 m/s^2 is a
  /// hard shake, so it is a sensible full scale.
  static const double motionFullScale = 20;

  static const double accelWeight = 0.8;
  static const double gyroFloor = 0.15;
  static const double gyroCeiling = 2.0;
  static const int sceneColumns = 32;
  static const int sceneRows = 24;
  static const int sceneSearchRadius = 3;
  static const int sceneBlockRadius = 1;
  static const int sceneMatchStride = 4;
  static const double sceneFloor = 2;
  static const double sceneCeiling = 25;
  static const double sceneMatchImprovement = 0.1;
  static const Duration sceneAttack = Duration(milliseconds: 60);
  static const Duration sceneRelease = Duration(milliseconds: 500);
  static const Duration motionStaleAfter = Duration(milliseconds: 500);

  /// Ignore face-up/down poses and require a clear winner near diagonals.
  static const double orientationMinGravity = 4;
  static const double orientationDominance = 1.25;

  /// Time constants of the motion smoothing.
  static const Duration motionAttack = Duration(milliseconds: 120);
  static const Duration motionRelease = Duration(milliseconds: 500);

  /// Time constants used for the direction of the movement. Slower than the
  /// magnitude so the direction does not jitter.
  static const Duration motionDirectionAttack = Duration(milliseconds: 400);
  static const Duration motionDirectionRelease = Duration(milliseconds: 600);

  /// Time constants of the light smoothing.
  static const Duration lightAttack = Duration(milliseconds: 150);
  static const Duration lightRelease = Duration(milliseconds: 400);

  /// The constant of an exponential filter that settles in [settling].
  ///
  /// The filters of the ambient pipeline are exponential, so their constant
  /// is the time they need to cover the 63% of the distance to the target.
  /// The times of the noise are the time the value needs to be practically
  /// at the target instead, which is why the constant is a third of them: a
  /// shout then reaches the top of the scale in about 150 ms, as the
  /// product asks for.
  static Duration timeConstant(Duration settling) =>
      Duration(microseconds: (settling.inMicroseconds / 3).round());

  /// Divisor of the logarithmic mapping of the lux of the light sensor.
  ///
  /// The light of a place spans many decades, so the lux are mapped with a
  /// logarithm: a dark room reads about 0.23, a lit room about 0.55, the
  /// shade of a tree about 0.82 and the direct sun reaches 1.
  static const double luxRange = 4.5;

  /// How much of the light comes from the sensor of the phone.
  ///
  /// The sensor sees the place, while the picture only sees what the camera
  /// is aimed at, and the automatic exposure of the camera hides how dark
  /// the place really is. The sensor is therefore the main source and the
  /// brightness of the picture only rounds it off.
  static const double luxWeight = 0.75;

  /// How much of the light comes from the brightness of the picture.
  static const double lumaWeight = 0.25;

  /// How often the three sources are merged into an [AmbientState].
  static const Duration mergeInterval = Duration(milliseconds: 33);

  /// Capture window: P90 noise/motion and mean light over the last 1.5 seconds.
  static const Duration snapshotWindow = Duration(milliseconds: 1500);
  static const double snapshotPercentile = 0.9;

  /// Number of merged samples kept in the ring buffer.
  ///
  /// 240 samples at 30 Hz are 8 seconds, far more than [snapshotWindow].
  static const int ringCapacity = 240;
}
