/// Immutable shader inputs only. No nonce, key material or clock state is
/// retained. The contextual lanes are in-memory approximations of the moment
/// and the place, frozen at the shutter and never serialized.
class SignatureState {
  const SignatureState({
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.w = 0,
    this.warmth = 0,
    this.hue = 0,
    this.chromaAllowance = 1,
    this.tilt = 0,
    this.axisX = 1,
    this.axisY = 0,
    this.pulse = 0,
    this.reserved = 0,
  });

  /// Four independently derived 24-bit fractions. All zero disables microtexture.
  final double x;
  final double y;
  final double z;
  final double w;

  /// Time-of-day warmth: -1 cold night .. 1 warm evening.
  final double warmth;

  /// Calendar and moon hue, -1 .. 1.
  final double hue;

  /// How much chroma the effect may add, 0.65 .. 1. One allows everything.
  final double chromaAllowance;

  /// Spectral tilt: -1 dark and bassy .. 1 bright and hissy.
  final double tilt;

  /// Orientation axis as a unit vector: [axisX] is cos(delta), [axisY] is
  /// sin(delta). The neutral axis is (1, 0).
  final double axisX;
  final double axisY;

  /// Rhythmic pulse, signed, -1 .. 1.
  final double pulse;

  /// Reserved for a future signal; neutral zero until something uses it.
  final double reserved;

  static const neutral = SignatureState();

  /// Copies this state, replacing only the given lanes. A null lane keeps the
  /// current value.
  SignatureState copyWith({
    double? x,
    double? y,
    double? z,
    double? w,
    double? warmth,
    double? hue,
    double? chromaAllowance,
    double? tilt,
    double? axisX,
    double? axisY,
    double? pulse,
    double? reserved,
  }) => SignatureState(
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    w: w ?? this.w,
    warmth: warmth ?? this.warmth,
    hue: hue ?? this.hue,
    chromaAllowance: chromaAllowance ?? this.chromaAllowance,
    tilt: tilt ?? this.tilt,
    axisX: axisX ?? this.axisX,
    axisY: axisY ?? this.axisY,
    pulse: pulse ?? this.pulse,
    reserved: reserved ?? this.reserved,
  );

  /// Merges the contextual lanes into this fingerprint state. The capture
  /// fingerprint (x, y, z, w) is kept, so a mood never loses the shot.
  SignatureState withMood({
    double? warmth,
    double? hue,
    double? chromaAllowance,
    double? tilt,
    double? axisX,
    double? axisY,
    double? pulse,
    double? reserved,
  }) => copyWith(
    warmth: warmth,
    hue: hue,
    chromaAllowance: chromaAllowance,
    tilt: tilt,
    axisX: axisX,
    axisY: axisY,
    pulse: pulse,
    reserved: reserved,
  );
}

/// A human visual reference, not a globally unique identifier.
class CaptureIdentity {
  const CaptureIdentity(this.photoId);

  /// Exactly eight Crockford Base32 characters for production captures.
  final String photoId;
}

/// Frozen at the shutter, reusable for every rendering of the same capture.
class CaptureSignature {
  const CaptureSignature({
    required this.seed,
    required this.signature,
    required this.identity,
  });

  final double seed;
  final SignatureState signature;
  final CaptureIdentity identity;
}
