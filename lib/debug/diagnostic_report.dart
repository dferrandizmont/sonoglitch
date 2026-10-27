import 'dart:convert';

import '../ambient/ambient_state.dart';
import '../camera/camera_metrics.dart';
import 'capture_timings.dart';
import 'device_summary.dart';
import 'redact_paths.dart';

/// Builds the JSON report of the diagnostics.
class DiagnosticReport {
  const DiagnosticReport._();

  /// Collects everything the panel shows into a map.
  ///
  /// [logs] are the last lines of the log file, so the report and the log
  /// tell the same story.
  static Map<String, Object?> build({
    required AmbientState ambient,
    required CameraMetricsData metrics,
    required String styleId,
    required CaptureTimings timings,
    required DeviceSummary device,
    required String appVersion,
    required String buildMode,
    required List<String> logs,
  }) {
    return {
      'appVersion': appVersion,
      'buildMode': buildMode,
      'device': device.toJson(),
      'ambient': ambient.toJson(),
      'camera': {
        'fps': metrics.fps,
        'conversionMs': metrics.conversionMs,
        'streamWidth': metrics.streamWidth,
        'streamHeight': metrics.streamHeight,
        'previewWidth': metrics.previewWidth,
        'previewHeight': metrics.previewHeight,
        'frames': metrics.frames,
        'droppedFrames': metrics.droppedFrames,
      },
      'style': styleId,
      'lastCapture': timings.toJson(),
      'logs': logs.map(redactPaths).toList(),
    };
  }

  /// The report as pretty printed JSON.
  static String encode(Map<String, Object?> report) =>
      const JsonEncoder.withIndent('  ').convert(report);
}
