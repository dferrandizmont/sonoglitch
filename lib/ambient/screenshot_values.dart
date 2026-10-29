/// In-memory demo readings for private screenshot builds only.
class ScreenshotValues {
  const ScreenshotValues({
    this.preset = 'Custom',
    required this.noise,
    required this.light,
    required this.motion,
    required this.db,
    required this.lux,
    required this.accel,
    required this.bass,
    required this.mid,
    required this.treble,
  });

  final String preset;
  final double noise;
  final double light;
  final double motion;
  final double db;
  final double lux;
  final double accel;
  final double bass;
  final double mid;
  final double treble;

  static const calm = ScreenshotValues(
    preset: 'Calm',
    noise: 0.25,
    light: 0.55,
    motion: 0.10,
    db: 48,
    lux: 220,
    accel: 0.08,
    bass: 0.30,
    mid: 0.20,
    treble: 0.10,
  );
  static const lively = ScreenshotValues(
    preset: 'Lively',
    noise: 0.60,
    light: 0.60,
    motion: 0.35,
    db: 66,
    lux: 340,
    accel: 0.28,
    bass: 0.70,
    mid: 0.55,
    treble: 0.35,
  );
  static const intense = ScreenshotValues(
    preset: 'Intense',
    noise: 0.90,
    light: 0.50,
    motion: 0.65,
    db: 82,
    lux: 420,
    accel: 0.70,
    bass: 0.90,
    mid: 0.75,
    treble: 0.60,
  );

  /// Editing any slider selects Custom and keeps the other readings.
  ScreenshotValues copyWith({
    double? noise,
    double? light,
    double? motion,
    double? db,
    double? lux,
    double? accel,
    double? bass,
    double? mid,
    double? treble,
  }) => ScreenshotValues(
    noise: (noise ?? this.noise).clamp(0.0, 1.0),
    light: (light ?? this.light).clamp(0.0, 1.0),
    motion: (motion ?? this.motion).clamp(0.0, 1.0),
    db: (db ?? this.db).clamp(30.0, 100.0),
    lux: (lux ?? this.lux).clamp(0.0, 2000.0),
    accel: (accel ?? this.accel).clamp(0.0, 2.0),
    bass: (bass ?? this.bass).clamp(0.0, 1.0),
    mid: (mid ?? this.mid).clamp(0.0, 1.0),
    treble: (treble ?? this.treble).clamp(0.0, 1.0),
  );
}
