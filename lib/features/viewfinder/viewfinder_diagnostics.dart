import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ambient/ambient_controller.dart';
import '../../camera/camera_metrics.dart';
import '../../debug/capture_timings.dart';
import '../../debug/debug_hud.dart';
import '../../debug/debug_log.dart';
import '../../debug/device_summary.dart';
import '../../debug/diagnostic_exporter.dart';
import '../../theme/app_theme.dart';

/// The diagnostics panel of the viewfinder.
///
/// The existing HUD has an intrinsic-width button row, so it is kept in a
/// horizontal scroll view that never takes room from the controls below.
class ViewfinderDiagnostics extends StatelessWidget {
  const ViewfinderDiagnostics({
    super.key,
    required this.ambient,
    required this.metrics,
    required this.styleId,
    required this.timings,
    required this.device,
    required this.log,
    required this.exporter,
  });

  final AmbientController ambient;
  final ValueListenable<CameraMetricsData> metrics;
  final String styleId;
  final CaptureTimings timings;
  final DeviceSummary device;
  final DebugLog log;
  final DiagnosticExporter exporter;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: LayoutBuilder(
      builder: (context, hudConstraints) {
        final minWidth =
            AppTheme.diagnosticsMinWidth *
            MediaQuery.textScalerOf(context).scale(1);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: hudConstraints.maxWidth < minWidth
                ? minWidth
                : hudConstraints.maxWidth,
            height: hudConstraints.maxHeight,
            child: DebugHud(
              ambient: ambient,
              metrics: metrics,
              styleId: styleId,
              timings: timings,
              device: device,
              log: log,
              exporter: exporter,
            ),
          ),
        );
      },
    ),
  );
}
