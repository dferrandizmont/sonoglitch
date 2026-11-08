import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sensors_plus/sensors_plus.dart';

import '../camera/capture_orientation.dart';
import 'ambient_config.dart';
import 'motion_sensor_rate.dart';
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

/// Builds a stream of samples with the given sampling period.
///
/// The period is the interval the sensor asks the platform for: the
/// accelerometer and the gyroscope are read at
/// [AmbientConfig.motionSensorPeriod] while the phone moves and at
/// [AmbientConfig.motionSensorQuietPeriod] while it is still.
typedef AccelStreamFactory = AccelStream Function(Duration samplingPeriod);

/// Combines scene displacement, angular velocity and linear acceleration into
/// max(scene, gyro, 0.8 * accel), with the dominant source's screen direction.
///
/// The accelerometer is read without the gravity component
/// (`userAccelerometerEventStream`), so a phone lying still reports zero and
/// only the movement itself is measured.
class MotionService {
  /// Creates the service.
  ///
  /// [samples] is injected so tests can feed known values. A stream that is
  /// given to the service is read at its own rate: the rate can only be
  /// changed when the service builds the streams itself, with
  /// [sampleFactory] and [gyroSampleFactory].
  MotionService({
    AccelStream? samples,
    AccelStream? gyroSamples,
    AccelStream? gravitySamples,
    AccelStreamFactory? sampleFactory,
    AccelStreamFactory? gyroSampleFactory,
    SmoothedValue? magnitudeSmoother,
    SmoothedValue? directionXSmoother,
    SmoothedValue? directionYSmoother,
    this.clock = stopwatchClock,
  }) : samples = samples,
       gyroSamples = gyroSamples,
       gravitySamples = gravitySamples ?? gravitySampleStream(),
       _sampleFactory =
           sampleFactory ?? (samples == null ? _accelerometerStream : null),
       _gyroSampleFactory =
           gyroSampleFactory ?? (gyroSamples == null ? _gyroscopeStream : null),
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
  ///
  /// It is null when the service builds the stream itself, with the period
  /// the sensors must be read with.
  final AccelStream? samples;

  /// The source of the raw gyroscope samples.
  ///
  /// It is null when the service builds the stream itself, with the period
  /// the sensors must be read with.
  final AccelStream? gyroSamples;

  /// Builds the streams of the sensors with the period they must be read
  /// with.
  ///
  /// They are null when the streams were given to the service: a stream that
  /// is already built cannot change its rate, so the sensors of the tests
  /// are always read at their own rate.
  final AccelStreamFactory? _sampleFactory;
  final AccelStreamFactory? _gyroSampleFactory;
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

  /// Decides how often the sensors are read.
  final MotionSensorRate _sensorRate = MotionSensorRate();

  /// The period the sensors are read with right now.
  Duration _samplingPeriod = AmbientConfig.motionSensorPeriod;

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
    // The phone may have stopped moving: the sensors can be read slowly.
    _updateSensorRate();
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

  /// The number of the switch of the sensors.
  ///
  /// It tells a switch that was started before another one whether it is
  /// still the one that must read the sensors again.
  int _epoch = 0;

  /// Whether the sensors are being switched right now.
  bool _switching = false;

  /// The period of a switch that was asked for while another one was
  /// running.
  ///
  /// It is applied when the running switch finishes, so the sensors always
  /// end up with the period the last reading asked for.
  Duration? _pendingPeriod;

  /// The last change of the subscriptions of the sensors.
  ///
  /// A new session waits for it, so the platform never holds two listeners
  /// of the same channel.
  Future<void> _lifecycle = Future<void>.value();

  /// Whether the last change of the subscriptions is still running.
  bool _lifecyclePending = false;

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

  /// The period the gyroscope and the accelerometer are read with.
  ///
  /// It is [AmbientConfig.motionSensorPeriod] while the phone moves and
  /// [AmbientConfig.motionSensorQuietPeriod] while it is still.
  Duration get sensorSamplingPeriod => _samplingPeriod;

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
    // A new session starts with the fast rate: the phone may have been
    // still while the viewfinder was hidden.
    _sensorRate.reset();
    _samplingPeriod = _sensorRate.period;
    // The sensors of the previous session may still be cancelling: the new
    // ones are only read once the old ones are gone, so the platform never
    // holds two listeners of the same channel.
    final previous = _lifecycle;
    if (_lifecyclePending) {
      final started = Completer<void>();
      _lifecycle = started.future;
      _lifecyclePending = true;
      previous.whenComplete(() {
        if (!started.isCompleted) started.complete();
        if (!_running) return;
        _listenToSensors();
        _lifecyclePending = false;
      });
      return;
    }
    _listenToSensors();
  }

  /// Reads the sensors of the platform with the current period.
  void _listenToSensors() {
    _subscription = _listen(_accelStream(), _onSample, _onError);
    _gyroSubscription = _listen(_gyroStream(), addGyroSample, _onGyroError);
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
    // The switch of the rate is abandoned: a subscription that is still
    // being cancelled must not read the sensors again.
    _epoch++;
    _switching = false;
    _pendingPeriod = null;
    final subscription = _subscription;
    final gyro = _gyroSubscription;
    final gravity = _gravitySubscription;
    _subscription = null;
    _gyroSubscription = null;
    _gravitySubscription = null;
    final cancelled = Completer<void>();
    _lifecycle = cancelled.future;
    _lifecyclePending = true;
    // The cancellations are awaited before anything else is read: the
    // platform has one listener per channel, so a new one must never be
    // registered before the old one is gone.
    Future.wait<void>([
      if (subscription != null) subscription.cancel(),
      if (gyro != null) gyro.cancel(),
      if (gravity != null) gravity.cancel(),
    ]).whenComplete(() {
      if (!cancelled.isCompleted) cancelled.complete();
      _lifecyclePending = false;
    });
    _gyro.reset(0);
    _lastGyroMicros = null;
    rawGyro = null;
    _lastGravityMicros = null;
    _latestGravitySample = null;
    _lastDirectionMicros = null;
    _sensorRate.reset();
    _samplingPeriod = _sensorRate.period;
    resetScene();
  }

  /// The stream of acceleration samples with the current period.
  AccelStream _accelStream() {
    final factory = _sampleFactory;
    if (factory != null) return factory(_samplingPeriod);
    return samples ?? const Stream<AccelSample>.empty();
  }

  /// The stream of gyroscope samples with the current period.
  AccelStream _gyroStream() {
    final factory = _gyroSampleFactory;
    if (factory != null) return factory(_samplingPeriod);
    return gyroSamples ?? const Stream<AccelSample>.empty();
  }

  /// Reads the sensors again when the phone moves or stops moving.
  ///
  /// The scene is not part of the decision: it is measured from the
  /// pictures, not from the sensors, so it cannot say whether the phone
  /// itself is still.
  void _updateSensorRate() {
    final accelFactory = _sampleFactory;
    final gyroFactory = _gyroSampleFactory;
    if (accelFactory == null && gyroFactory == null) {
      // The streams were given to the service: a stream that is already
      // built cannot change its rate, so the sensors keep the rate they
      // were given.
      return;
    }
    final level = math.max(accelLevel, gyroLevel);
    final period = _sensorRate.observe(level, clock());
    if (period == _samplingPeriod) return;
    _samplingPeriod = period;
    // The switch is serialised inside: the old subscriptions are cancelled
    // before the new ones are registered.
    unawaited(_resubscribe(period));
  }

  /// Reads the sensors again with the given period.
  ///
  /// The streams of the platform are built with the period they ask for, so
  /// the sensors have to be read again to change it. The switch is
  /// serialised: the old subscriptions are cancelled before the new ones
  /// are registered, because the platform keeps one listener per channel and
  /// a new listener registered too early would cancel the new one.
  Future<void> _resubscribe(Duration period) async {
    final accelFactory = _sampleFactory;
    final gyroFactory = _gyroSampleFactory;
    if (accelFactory == null && gyroFactory == null) return;
    if (_switching) {
      // A switch is already running: the period asked for now is the one
      // that matters, so the running switch applies it when it finishes.
      _pendingPeriod = period;
      return;
    }
    _switching = true;
    final serial = ++_epoch;
    final accel = _subscription;
    final gyro = _gyroSubscription;
    _subscription = null;
    _gyroSubscription = null;
    try {
      await accel?.cancel();
      await gyro?.cancel();
    } finally {
      _switching = false;
    }
    // Another switch happened, or the sensors are not wanted any more.
    if (serial != _epoch || !_running) return;
    if (accelFactory != null) {
      _subscription = _listen(accelFactory(period), _onSample, _onError);
    }
    if (gyroFactory != null) {
      _gyroSubscription = _listen(
        gyroFactory(period),
        addGyroSample,
        _onGyroError,
      );
    }
    final pending = _pendingPeriod;
    if (pending != null && pending != period) {
      _pendingPeriod = null;
      await _resubscribe(pending);
    } else {
      _pendingPeriod = null;
    }
  }

  /// Forgets the gyroscope when its stream fails.
  void _onGyroError(Object error, StackTrace stackTrace) {
    _signatureGyro.clear();
    _gyro.reset(0);
    rawGyro = null;
    _lastGyroMicros = null;
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
    // The phone may have stopped moving: the sensors can be read slowly.
    _updateSensorRate();
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
AccelStream accelerometerSampleStream({
  Duration samplingPeriod = AmbientConfig.motionSensorPeriod,
}) =>
    userAccelerometerEventStream(samplingPeriod: samplingPeriod)
        .map((event) => AccelSample(event.x, event.y, event.z));

/// Angular velocity only; no audio or image data passes through this stream.
AccelStream gyroscopeSampleStream({
  Duration samplingPeriod = AmbientConfig.motionSensorPeriod,
}) =>
    gyroscopeEventStream(samplingPeriod: samplingPeriod)
        .map((e) => AccelSample(e.x, e.y, e.z));

/// Gravity is used only to infer the still orientation while the preview runs.
AccelStream gravitySampleStream() =>
    accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 100))
        .map((e) => AccelSample(e.x, e.y, e.z));

/// The accelerometer of the platform, read with the given period.
AccelStream _accelerometerStream(Duration samplingPeriod) =>
    accelerometerSampleStream(samplingPeriod: samplingPeriod);

/// The gyroscope of the platform, read with the given period.
AccelStream _gyroscopeStream(Duration samplingPeriod) =>
    gyroscopeSampleStream(samplingPeriod: samplingPeriod);
