import '../debug/capture_timings.dart';

/// Adds final export dimensions to every diagnostic report, including the HUD,
/// without changing the shared diagnostics module's public contract.
class ExportCaptureTimings extends CaptureTimings {
  ExportCaptureTimings(CaptureTimings timings, this.export)
    : super(
        takeMs: timings.takeMs,
        decodeMs: timings.decodeMs,
        renderMs: timings.renderMs,
        encodeMs: timings.encodeMs,
        animationTime: timings.animationTime,
        ambient: timings.ambient,
      );

  final Map<String, Object?> export;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), ...export};

  @override
  String toString() =>
      '${super.toString()}, ${export['width']}x${export['height']}';
}
