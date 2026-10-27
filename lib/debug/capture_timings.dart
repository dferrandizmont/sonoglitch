import '../ambient/ambient_state.dart';

/// How long each step of the last capture took.
class CaptureTimings {
  const CaptureTimings({
    this.takeMs = 0,
    this.decodeMs = 0,
    this.renderMs = 0,
    this.encodeMs = 0,
    this.animationTime = 0,
    this.ambient,
  });

  /// Time the camera needed to take the picture.
  final double takeMs;

  /// Time needed to decode the picture.
  final double decodeMs;

  /// Time needed to apply the effect.
  final double renderMs;

  /// Time needed to encode the picture as PNG.
  final double encodeMs;

  /// The animation time of the preview when the shutter was pressed, in
  /// seconds.
  ///
  /// The still is drawn with this time, so it shows the same frame of the
  /// animation that the preview was showing.
  final double animationTime;

  /// Peak-preserving snapshot taken at shutter time, also shown on the result.
  final AmbientState? ambient;

  /// The timings as a map, for the JSON report.
  Map<String, Object?> toJson() => {
    'takeMs': takeMs,
    'decodeMs': decodeMs,
    'renderMs': renderMs,
    'encodeMs': encodeMs,
    'animationTime': animationTime,
    if (ambient != null) 'ambient': ambient!.toJson(),
  };

  @override
  String toString() =>
      'take ${takeMs.toStringAsFixed(0)}ms, '
      'decode ${decodeMs.toStringAsFixed(0)}ms, '
      'render ${renderMs.toStringAsFixed(0)}ms, '
      'encode ${encodeMs.toStringAsFixed(0)}ms, '
      'animation ${animationTime.toStringAsFixed(2)}s';
}
