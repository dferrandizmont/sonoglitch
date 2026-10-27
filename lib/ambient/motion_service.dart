import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sensors_plus/sensors_plus.dart';

import '../camera/capture_orientation.dart';
import 'ambient_config.dart';
import 'scene_motion.dart';
import 'clock.dart';
import 'context_sensors.dart' show SensorVector;
import 'smoothed_value.dart';
import 'signature/signature_source.dart';

/// A raw acceleration sample in m/s^2, with the gravity already removed.
class AccelSample {
  const AccelSample(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Length of the acceleration vector.
  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

/// Stream of raw acceleration samples.
typedef AccelStream = Stream<AccelSample>;

/// Combines scene displacement, angular velocity and linear acceleration into
/// max(scene, gyro, 0.8 * accel), with the dominant source's screen direction.
///
/// The accelerometer is read without the gravity component
/// (`userAccelerometerEventStream`), so a phone lying still reports zero and
/// only the movement itself is measured.
class MotionService {
  /// Creates the service.
  ///
  /// [samples] is injected so tests can feed known values.
  MotionService({
    AccelStream? samples,
    AccelStream? gyroSamples,
    AccelStream? gravitySamples,
    SmoothedValue? magnitudeSmoother,
    SmoothedValue? directionXSmoother,
    SmoothedValue? directionYSmoother,
    this.clock = stopwatchClock,
  }) : samples = samples ?? accelerometerSampleStream(),
       gyroSamples = gyroSamples ?? gyroscopeSampleStream(),
       gravitySamples = gravitySamples ?? gravitySampleStream(),
       magnitude =
           magnitudeSmoother ??
           SmoothedValue(
             attack: AmbientConfig.motionAttack,
             release: AmbientConfig.motionRelease,
           ),
       directionX =
           directionXSmoother ??
           SmoothedValue(
             attack: AmbientConfig.motionDirectionAttack,
             release: AmbientConfig.motionDirectionRelease,
           ),
       directionY =
           directionYSmoother ??
           SmoothedValue(
             attack: AmbientConfig.motionDirectionAttack,
             release: AmbientConfig.motionDirectionRelease,
           );

  /// The source of the raw acceleration samples.
  final AccelStream samples;
  final AccelStream gyroSamples;
  final AccelStream gravitySamples;
  final CaptureOrientationTracker orientation = CaptureOrientationTracker();
  final SceneMotion scene = SceneMotion();
  final _signatureAccel = SignatureSource(3);
  final _signatureGyro = SignatureSource(3);
  List<SignatureReading> get signatureReadings => [
    ..._signatureAccel.readings(clock()),
    ..._signatureGyro.readings(clock()),
  ];
  final SmoothedValue _gyro = SmoothedValue(
    attack: AmbientConfig.motionAttack,
    release: AmbientConfig.motionRelease,
  );
  final SmoothedValue _scene = SmoothedValue(
    attack: AmbientConfig.sceneAttack,
    release: AmbientConfig.sceneRelease,
  );
  StreamSubscription<AccelSample>? _gyroSubscription;
  StreamSubscription<AccelSample>? _gravitySubscription;
  int? _lastGyroMicros;
  int? _lastSceneMicros;
  bool _running = false;
  double _gyroX = 0;
  double _gyroY = 0;
  double? rawGyro;
  bool _frontLens = false;
  bool _mirrored = false;
  int? _lastGravityMicros;
  AccelSample? _latestGravitySample;

  /// Latest shared gravity and monotonic timestamp; no additional subscription.
  ({SensorVector vector, int timeMicros})? get latestGravity {
    final s = _latestGravitySample;
    final time = _lastGravityMicros;
    if (s == null || time == null || !_valid(s)) return null;
    return (vector: (x: s.x, y: s.y, z: s.z), timeMicros: time);
  }

  int? _lastDirectionMicros;
  double _fusedX = 0;
  double _fusedY = 0;

  /// All sources report observed scene displacement in the portrait preview:
  /// x right, y up. Front previews are mirrored on both supported platforms.
  void setCameraBasis({required bool frontLens, required bool mirrored}) {
    if (_frontLens == frontLens && _mirrored == mirrored) return;
    _frontLens = frontLens;
    _mirrored = mirrored;
    resetScene();
    _gyro.reset(0);
    _lastGyroMicros = null;
    _lastDirectionMicros = null;
    _gyroX = _gyroY = _fusedX = _fusedY = 0;
  }

  double get accelLevel => magnitude.value;
  double get gyroLevel => _fresh(_gyro.value, _lastGyroMicros);
  double get sceneLevel => _fresh(_scene.value, _lastSceneMicros);

  double _fresh(double value, int? last) {
    if (last == null) return 0;
    final age = clock() - last - AmbientConfig.motionStaleAfter.inMicroseconds;
    return age <= 0
        ? value
        : value * math.exp(-age / AmbientConfig.motionRelease.inMicroseconds);
  }

  (double, double) get _targetDirection {
    final sceneValue = sceneLevel;
    final gyroValue = gyroLevel;
    final accelValue = AmbientConfig.accelWeight * accelLevel;
    if (sceneValue > 0 && sceneValue >= math.max(gyroValue, accelValue)) {
      return (scene.dx, scene.dy);
    }
    if (gyroValue > accelValue) return (_gyroX, _gyroY);
    final length = math.sqrt(
      directionX.value * directionX.value + directionY.value * directionY.value,
    );
    return length > 0
        ? (directionX.value / length, directionY.value / length)
        : (0, 0);
  }

  (double, double) get _direction => _lastDirectionMicros == null
      ? (directionX.value, directionY.value)
      : (_fusedX, _fusedY);

  void _smoothDirection() {
    final now = clock();
    final target = _targetDirection;
    if (_lastDirectionMicros == null) {
      if (target.$1 == 0 && target.$2 == 0) return;
      _fusedX = target.$1;
      _fusedY = target.$2;
    } else {
      final dt = math.max(0, now - _lastDirectionMicros!);
      final alpha =
          1 -
          math.exp(-dt / AmbientConfig.motionDirectionAttack.inMicroseconds);
      // Do not renormalize: opposing directions fade through zero rather
      // than causing a sudden 180-degree trail reversal.
      _fusedX += alpha * (target.$1 - _fusedX);
      _fusedY += alpha * (target.$2 - _fusedY);
    }
    _lastDirectionMicros = now;
  }

  /// Reset comparisons across lens changes, pause/resume and still captures.
  void resetScene() {
    scene.reset();
    _scene.reset(0);
    _lastSceneMicros = null;
  }

  void addSceneFrame(
    Uint8List pixels,
    int width,
    int height, {
    List<double>? lumaGrid,
  }) {
    if (lumaGrid == null) {
      scene.addRgba(pixels, width, height);
    } else {
      scene.addLumaGrid(lumaGrid, width, height);
    }
    final now = clock();
    final elapsed = _lastSceneMicros == null
        ? nominalSamplePeriod
        : Duration(microseconds: now - _lastSceneMicros!);
    _lastSceneMicros = now;
    _scene.update(scene.level, elapsed);
    _smoothDirection();
  }

  /// Gyroscope axes are angular velocities in rad/s. Yaw sweeps horizontally,
  /// pitch vertically; roll contributes horizontally when it is dominant.
  void addGyroSample(AccelSample sample) {
    if (!_valid(sample)) return;
    final now = clock();
    final elapsed = _lastGyroMicros == null
        ? nominalSamplePeriod
        : Duration(microseconds: now - _lastGyroMicros!);
    _lastGyroMicros = now;
    _signatureGyro.update([sample.x, sample.y, sample.z], now);
    rawGyro = sample.magnitude;
    _gyro.update(mapGyroscope(sample.magnitude), elapsed);
    // Roll has no global translation; use its tangent at the top of the
    // image as a representative direction when it dominates yaw.
    final horizontal = sample.y.abs() >= sample.z.abs()
        ? sample.y
        : sample.z * (_frontLens ? -1 : 1);
    final x = horizontal * (_mirrored ? -1 : 1);
    final y = sample.x * (_frontLens ? 1 : -1);
    final length = math.sqrt(x * x + y * y);
    if (length > 0 && sample.magnitude > AmbientConfig.gyroFloor) {
      _gyroX = x / length;
      _gyroY = y / length;
    }
    _smoothDirection();
  }

  static bool _valid(AccelSample sample) =>
      sample.x.isFinite &&
      sample.y.isFinite &&
      sample.z.isFinite &&
      sample.magnitude.isFinite;

  static double mapGyroscope(double rate) => !rate.isFinite
      ? 0
      : ((rate - AmbientConfig.gyroFloor) /
                (AmbientConfig.gyroCeiling - AmbientConfig.gyroFloor))
            .clamp(0.0, 1.0);

  /// The smoother of the magnitude of the movement.
  final SmoothedValue magnitude;

  /// The smoother of the horizontal direction of the movement.
  final SmoothedValue directionX;

  /// The smoother of the vertical direction of the movement.
  final SmoothedValue directionY;

  /// The clock used to measure the time between samples.
  final Clock clock;

  StreamSubscription<AccelSample>? _subscription;
  int _lastSampleMicros = 0;
  bool _hasSample = false;
  double _rawAccel = 0;

  /// Whether the accelerometer is being read.
  ///
  /// The sensor must not run while the viewfinder is not visible, so the
  /// lifecycle of the screen is checked with this.
  bool get isListening => _running;

  /// The normalised movement, 0..1.
  double get level => math.max(
    sceneLevel,
    math.max(gyroLevel, AmbientConfig.accelWeight * accelLevel),
  );

  /// Direction of the movement in screen space, on the x axis.
  ///
  /// Not normalised: the length carries the strength of the movement.
  double get dirX => _direction.$1;

  /// Direction of the movement in screen space, on the y axis.
  double get dirY => _direction.$2;

  /// The last raw acceleration magnitude in m/s^2.
  double get rawAccel => _rawAccel;

  /// Starts listening. Calling it twice is harmless.
  void start() {
    if (_running) return;
    _running = true;
    _lastSampleMicros = clock();
    _subscription = _listen(samples, _onSample, _onError);
    _gyroSubscription = _listen(gyroSamples, addGyroSample, (e, s) {
      _signatureGyro.clear();
      _gyro.reset(0);
      rawGyro = null;
      _lastGyroMicros = null;
    });
    _gravitySubscription = _listen(
      gravitySamples,
      (s) {
        _latestGravitySample = s;
        final now = clock();
        orientation.addGravity(
          s.x,
          s.y,
          s.z,
          elapsed: _lastGravityMicros == null
              ? const Duration(milliseconds: 100)
              : Duration(microseconds: now - _lastGravityMicros!),
        );
        _lastGravityMicros = now;
      },
      (error, stack) {
        _latestGravitySample = null;
        _onError(error, stack);
      },
    );
  }

  /// Stops listening. Calling it twice is harmless.
  void stop() {
    _signatureAccel.clear();
    _signatureGyro.clear();
    _running = false;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    unawaited(_gyroSubscription?.cancel());
    unawaited(_gravitySubscription?.cancel());
    _gyroSubscription = _gravitySubscription = null;
    _gyro.reset(0);
    _lastGyroMicros = null;
    rawGyro = null;
    _lastGravityMicros = null;
    _latestGravitySample = null;
    _lastDirectionMicros = null;
    resetScene();
  }

  StreamSubscription<AccelSample>? _listen(
    AccelStream stream,
    void Function(AccelSample) onData,
    void Function(Object, StackTrace) onError,
  ) {
    try {
      return stream.listen(onData, onError: onError);
    } catch (error, stack) {
      onError(error, stack);
      return null;
    }
  }

  /// Feeds a raw sample. Exposed for tests and for fake sensors.
  void addSample(AccelSample sample) => _onSample(sample);

  void _onSample(AccelSample sample) {
    // Every axis and the magnitude must be finite; otherwise a single NaN or
    // infinity in the stream would poison the smoothed direction for the
    // whole service lifetime, because the smoother cannot recover from a
    // nonfinite value through arithmetic alone.
    if (!sample.x.isFinite ||
        !sample.y.isFinite ||
        !sample.z.isFinite ||
        !sample.magnitude.isFinite) {
      return;
    }

    final now = clock();
    final elapsed = _elapsedSince(now);

    final rawMagnitude = sample.magnitude;

    _signatureAccel.update([sample.x, sample.y, sample.z], now);
    _rawAccel = rawMagnitude;
    magnitude.update(mapAcceleration(rawMagnitude), elapsed);

    // The accelerometer axes follow the device: x to the right, y to the top
    // of the phone and z out of the screen. The app is locked to portrait, so
    // the device axes and the screen axes match; the rotation is kept explicit
    // so landscape support stays a one line change.
    final (screenX, screenY) = rotateToScreen(sample.x, sample.y, 0);
    directionX.update(screenX, elapsed);
    directionY.update(screenY, elapsed);
    if (_lastDirectionMicros != null) _smoothDirection();
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
    _signatureAccel.clear();
    // The accelerometer is not available on every device; the movement simply
    // stays at zero.
  }

  /// Maps an acceleration magnitude to the 0..1 scale.
  ///
  /// The range is 0 to [AmbientConfig.motionFullScale] m/s^2: a phone at rest
  /// reads 0 and a hard shake saturates the scale.
  static double mapAcceleration(double accel) {
    if (!accel.isFinite || accel <= 0) return 0;
    final scaled = accel / AmbientConfig.motionFullScale;
    return scaled > 1 ? 1 : scaled;
  }
}

/// Rotates a device space vector into screen space.
///
/// [quarterTurns] is the number of clockwise quarter turns of the device with
/// respect to portrait. The device axes are x to the right and y to the top of
/// the phone; the screen axes are x to the right and y to the top of the
/// screen.
(double, double) rotateToScreen(double x, double y, int quarterTurns) {
  switch (quarterTurns % 4) {
    case 1:
      return (y, -x);
    case 2:
      return (-x, -y);
    case 3:
      return (-y, x);
    default:
      return (x, y);
  }
}

/// The default accelerometer source: the user accelerometer of `sensors_plus`,
/// which does not include the gravity.
AccelStream accelerometerSampleStream() => userAccelerometerEventStream(
  samplingPeriod: const Duration(milliseconds: 20),
).map((event) => AccelSample(event.x, event.y, event.z));

/// Angular velocity only; no audio or image data passes through this stream.
AccelStream gyroscopeSampleStream() =>
    gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 20))
        .map((e) => AccelSample(e.x, e.y, e.z));

/// Gravity is used only to infer the still orientation while the preview runs.
AccelStream gravitySampleStream() =>
    accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 100))
        .map((e) => AccelSample(e.x, e.y, e.z));
