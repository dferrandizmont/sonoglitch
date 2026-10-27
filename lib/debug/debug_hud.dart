import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient/ambient_controller.dart';
import '../ambient/ambient_state.dart';
import '../app_config.dart';
import '../camera/camera_metrics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'capture_timings.dart';
import 'debug_log.dart';
import 'device_summary.dart';
import 'diagnostic_exporter.dart';
import 'diagnostic_report.dart';

/// The on screen diagnostics panel.
///
/// It is drawn over the viewfinder with a translucent background and a
/// monospace font, and it stays fixed on the screen, so a screenshot of the
/// app always carries the numbers.
///
/// The panel also has the manual mode: the three values can be set by hand
/// instead of measured, so a screenshot or a test of the effects can be
/// reproduced.
class DebugHud extends StatelessWidget {
  const DebugHud({
    super.key,
    required this.ambient,
    required this.metrics,
    required this.styleId,
    required this.timings,
    required this.device,
    required this.log,
    required this.exporter,
  });

  /// The ambient controller, which also holds the manual values.
  final AmbientController ambient;

  /// The current camera measurements.
  final ValueListenable<CameraMetricsData> metrics;

  /// The style that is being drawn.
  final String styleId;

  /// How long the last capture took.
  final CaptureTimings timings;

  /// What is known about the device.
  final DeviceSummary device;

  /// The logger.
  final DebugLog log;

  /// Used to share the report.
  final DiagnosticExporter exporter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.all(AppTheme.safeMargin),
      padding: const EdgeInsets.all(AppTheme.spaceSm),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.outline),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HudReadout(
              ambient: ambient,
              metrics: metrics,
              presentation: () => _text(_lines(ambient.value, metrics.value)),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            _HudManualControls(ambient: ambient, builder: _manualControls),
            const SizedBox(height: AppTheme.spaceXs),
            Row(
              children: [
                _button(
                  context,
                  label: l10n.debugCopyReport,
                  onPressed: () => _copyReport(context),
                ),
                const SizedBox(width: AppTheme.spaceXs),
                _button(
                  context,
                  label: l10n.debugShareLogs,
                  onPressed: () => _shareLogs(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _lines(AmbientState state, CameraMetricsData camera) {
    final rawDb = state.rawDb;
    final rawLuma = state.rawLuma;
    final rawAccel = state.rawAccel;
    final rawLux = state.rawLux;
    final baselineDb = state.baselineDb;
    final burst = state.burst;
    return [
      'noise  ${state.noise.toStringAsFixed(3)}'
          '  db ${rawDb == null ? '--' : rawDb.toStringAsFixed(1)}'
          '  base ${baselineDb == null ? '--' : baselineDb.toStringAsFixed(1)}'
          '  burst ${burst == null ? '--' : burst.toStringAsFixed(2)}',
      'light  ${state.light.toStringAsFixed(3)}'
          '  luma ${rawLuma == null ? '--' : rawLuma.toStringAsFixed(1)}'
          '  lux ${rawLux == null ? '--' : rawLux.toStringAsFixed(1)}',
      'motion ${state.motion.toStringAsFixed(3)}'
          '  accel ${rawAccel == null ? '--' : rawAccel.toStringAsFixed(2)}'
          '  dir ${state.motionDirX.toStringAsFixed(2)},'
          '${state.motionDirY.toStringAsFixed(2)}',
      'bass ${state.bass.toStringAsFixed(3)}'
          '  mid ${state.mid.toStringAsFixed(3)}'
          '  treble ${state.treble.toStringAsFixed(3)}',
      'sources scene ${state.sceneMotion.toStringAsFixed(3)}'
          '  gyro ${state.gyroMotion.toStringAsFixed(3)}'
          '  accel ${state.accelMotion.toStringAsFixed(3)}',
      'stream ${camera.streamResolution}  '
          'fps ${camera.fps.toStringAsFixed(1)}  '
          'conv ${camera.conversionMs.toStringAsFixed(1)}ms  '
          'drop ${camera.droppedFrames}',
      'style $styleId  v${AppConfig.appVersion}',
      '${device.platform} ${device.systemVersion} ${device.model}',
      'capture $timings',
    ];
  }

  /// The switch of the manual mode and its three sliders.
  Widget _manualControls(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manual = ambient.isManual;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(value: manual, onChanged: ambient.setManual),
            const SizedBox(width: AppTheme.spaceXs),
            Text(
              l10n.debugManual,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
            const Spacer(),
            _badge(
              context,
              label: manual ? l10n.debugManual : l10n.debugAuto,
              highlighted: manual,
            ),
          ],
        ),
        if (manual) ...[
          _slider(
            context,
            label: l10n.levelNoise,
            value: ambient.manualNoise,
            onChanged: (value) => ambient.setManualValues(noise: value),
          ),
          _slider(
            context,
            label: l10n.levelLight,
            value: ambient.manualLight,
            onChanged: (value) => ambient.setManualValues(light: value),
          ),
          _slider(
            context,
            label: l10n.levelMotion,
            value: ambient.manualMotion,
            onChanged: (value) => ambient.setManualValues(motion: value),
          ),
        ],
      ],
    );
  }

  /// The badge that tells whether the values are measured or set by hand.
  Widget _badge(
    BuildContext context, {
    required String label,
    required bool highlighted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: highlighted ? AppTheme.accentMuted : AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: highlighted ? AppTheme.accent : AppTheme.outline,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: highlighted ? AppTheme.textPrimary : AppTheme.textSecondary,
        ),
      ),
    );
  }

  /// A compact slider of one of the three controls.
  Widget _slider(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              thumbColor: AppTheme.accent,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.outline,
            ),
            child: SizedBox(
              height: 24,
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _text(List<String> lines) {
    return Text(
      lines.join('\n'),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: ['Roboto Mono', 'Courier New'],
        fontSize: 10,
        height: 1.35,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _button(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceSm,
          vertical: AppTheme.spaceXs,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  Map<String, Object?> _report(AmbientState state, CameraMetricsData camera) {
    return DiagnosticReport.build(
      ambient: state,
      metrics: camera,
      styleId: styleId,
      timings: timings,
      device: device,
      appVersion: AppConfig.appVersion,
      buildMode: kReleaseMode ? 'release' : 'debug',
      logs: log.recentLines
          .skip(log.recentLines.length > 100 ? log.recentLines.length - 100 : 0)
          .toList(),
    );
  }

  Future<void> _copyReport(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final state = ambient.value;
    final camera = metrics.value;
    final report = DiagnosticReport.encode(_report(state, camera));
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.debugReportCopied)));
  }

  Future<void> _shareLogs(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final state = ambient.value;
    final camera = metrics.value;
    try {
      await exporter.share(_report(state, camera));
    } catch (error, stackTrace) {
      log.error('debug', 'the logs could not be shared', error, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.debugShareFailed)));
    }
  }
}

/// Coalesces presentation only: producers and report exports retain every sample.
class _HudReadout extends StatefulWidget {
  const _HudReadout({
    required this.ambient,
    required this.metrics,
    required this.presentation,
  });
  final AmbientController ambient;
  final ValueListenable<CameraMetricsData> metrics;
  final Widget Function() presentation;

  @override
  State<_HudReadout> createState() => _HudReadoutState();
}

class _HudReadoutState extends State<_HudReadout> {
  Timer? _pending;
  late Widget _presentation;

  @override
  void initState() {
    super.initState();
    _presentation = widget.presentation();
    _listen();
  }

  void _listen() {
    widget.ambient.addListener(_schedule);
    widget.metrics.addListener(_schedule);
  }

  void _schedule() {
    // Do not reset the deadline on each sample: a continuous stream still
    // presents its latest values once per 250 ms, with no idle polling timer.
    _pending ??= Timer(const Duration(milliseconds: 250), () {
      _pending = null;
      setState(() => _presentation = widget.presentation());
    });
  }

  @override
  void didUpdateWidget(_HudReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.ambient.removeListener(_schedule);
    oldWidget.metrics.removeListener(_schedule);
    _listen();
    _schedule();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: _presentation);

  @override
  void dispose() {
    _pending?.cancel();
    widget.ambient.removeListener(_schedule);
    widget.metrics.removeListener(_schedule);
    super.dispose();
  }
}

/// Sensor ticks do not rebuild the manual sliders; only their own values do.
class _HudManualControls extends StatefulWidget {
  const _HudManualControls({required this.ambient, required this.builder});
  final AmbientController ambient;
  final WidgetBuilder builder;

  @override
  State<_HudManualControls> createState() => _HudManualControlsState();
}

class _HudManualControlsState extends State<_HudManualControls> {
  late (bool, double, double, double) _values;

  (bool, double, double, double) get _current => (
    widget.ambient.isManual,
    widget.ambient.manualNoise,
    widget.ambient.manualLight,
    widget.ambient.manualMotion,
  );

  @override
  void initState() {
    super.initState();
    _values = _current;
    widget.ambient.addListener(_changed);
  }

  void _changed() {
    final values = _current;
    if (values != _values) setState(() => _values = values);
  }

  @override
  void didUpdateWidget(_HudManualControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.ambient.removeListener(_changed);
    widget.ambient.addListener(_changed);
    _values = _current;
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: widget.builder(context));

  @override
  void dispose() {
    widget.ambient.removeListener(_changed);
    super.dispose();
  }
}
