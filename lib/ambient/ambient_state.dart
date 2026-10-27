import 'signature/signature_state.dart';

/// Normalised snapshot of the surroundings, shared by sensors, UI and effects.
///
/// All `0..1` values are already smoothed. They are the only thing a shader
/// style depends on, so every style keeps the same meaning for the three controls.
class AmbientState {
  const AmbientState({
    this.noise = 0,
    this.light = 0.5,
    this.motion = 0,
    this.motionDirX = 1,
    this.motionDirY = 0,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.seed = 0,
    this.signature = SignatureState.neutral,
    this.captureSignature,
    this.rawDb,
    this.rawLuma,
    this.rawAccel,
    this.rawLux,
    this.baselineDb,
    this.burst,
    this.noiseCeilingDb,
    this.sceneMotion = 0,
    this.gyroMotion = 0,
    this.accelMotion = 0,
    this.rawGyro,
  });

  /// 0 = silent, 1 = very loud.
  final double noise;

  /// 0 = dark / cold tones, 1 = bright / warm tones.
  final double light;

  /// 0 = still, 1 = strong shaking.
  final double motion;

  /// Direction of the dominant movement in screen space (not necessarily unit length).
  final double motionDirX;
  final double motionDirY;

  /// Normalised spectrum energies and the procedural pattern seed, 0..1.
  final double bass;
  final double mid;
  final double treble;
  final double seed;

  final SignatureState signature;
  final CaptureSignature? captureSignature;
  CaptureIdentity? get identity => captureSignature?.identity;

  /// Raw readings, for the debug panel and the result screen. Null until measured.
  final double? rawDb;
  final double? rawLuma;
  final double? rawAccel;

  /// Reading of the light sensor of the phone, in lux. Null when the device
  /// has no light sensor.
  final double? rawLux;

  /// The loudness of the place in dB, without the peaks.
  ///
  /// It is the reference the noise is compared against.
  final double? baselineDb;

  /// How much of the noise is a peak over the baseline, 0..1.
  final double? burst;

  /// Uncurved, smoothed source components; accel is before the 0.8 weight.
  final double sceneMotion;
  final double gyroMotion;
  final double accelMotion;
  final double? rawGyro;
  final double? noiseCeilingDb;

  static const AmbientState calm = AmbientState();

  /// Move the trail vector into the rotated still's axes; the live state stays
  /// in portrait coordinates. Scalar controls and diagnostics are unchanged.
  AmbientState forPhotoTurns(int clockwiseTurns, {bool mirrorX = false}) {
    final basisX = mirrorX ? -motionDirX : motionDirX;
    final (x, y) = switch (clockwiseTurns % 4) {
      1 => (motionDirY, -basisX),
      2 => (-basisX, -motionDirY),
      3 => (-motionDirY, basisX),
      _ => (basisX, motionDirY),
    };
    // A small rotation flips under mirroring; plain quarter turns keep it.
    // A zero axis component cannot change sign, so the state stays identical.
    final rotatedSignature = mirrorX && signature.axisY != 0
        ? signature.withMood(axisY: -signature.axisY)
        : signature;
    return AmbientState(
      noise: noise,
      light: light,
      motion: motion,
      motionDirX: x,
      motionDirY: y,
      bass: bass,
      mid: mid,
      treble: treble,
      seed: seed,
      signature: rotatedSignature,
      captureSignature: captureSignature,
      rawDb: rawDb,
      rawLuma: rawLuma,
      rawAccel: rawAccel,
      rawLux: rawLux,
      baselineDb: baselineDb,
      burst: burst,
      noiseCeilingDb: noiseCeilingDb,
      sceneMotion: sceneMotion,
      gyroMotion: gyroMotion,
      accelMotion: accelMotion,
      rawGyro: rawGyro,
    );
  }

  /// Freezes a capture seed while preserving every measured value.
  AmbientState withSeed(double seed) =>
      _withSignature(seed, signature, captureSignature);

  /// Attaches an already consumed shutter identity without deriving it again.
  AmbientState withCaptureSignature(CaptureSignature capture) =>
      _withSignature(capture.seed, capture.signature, capture);

  AmbientState _withSignature(
    double seed,
    SignatureState signature,
    CaptureSignature? capture,
  ) => AmbientState(
    noise: noise,
    light: light,
    motion: motion,
    motionDirX: motionDirX,
    motionDirY: motionDirY,
    bass: bass,
    mid: mid,
    treble: treble,
    seed: seed,
    signature: signature,
    captureSignature: capture,
    rawDb: rawDb,
    rawLuma: rawLuma,
    rawAccel: rawAccel,
    rawLux: rawLux,
    baselineDb: baselineDb,
    burst: burst,
    noiseCeilingDb: noiseCeilingDb,
    sceneMotion: sceneMotion,
    gyroMotion: gyroMotion,
    accelMotion: accelMotion,
    rawGyro: rawGyro,
  );

  Map<String, Object?> toJson() => {
    'noise': noise,
    'light': light,
    'motion': motion,
    'motionDirX': motionDirX,
    'motionDirY': motionDirY,
    'bass': bass,
    'mid': mid,
    'treble': treble,
    'rawDb': rawDb,
    'rawLuma': rawLuma,
    'rawAccel': rawAccel,
    'rawLux': rawLux,
    'baselineDb': baselineDb,
    'burst': burst,
    'noiseCeilingDb': noiseCeilingDb,
    'sceneMotion': sceneMotion,
    'gyroMotion': gyroMotion,
    'accelMotion': accelMotion,
    'rawGyro': rawGyro,
  };
}
