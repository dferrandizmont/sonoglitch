import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ambient/ambient_controller.dart';
import '../../ambient/context_sensors.dart';
import '../../camera/camera_service.dart';
import '../../camera/volume_keys.dart';
import '../../debug/capture_metrics.dart';
import '../../debug/debug_log.dart';
import '../../debug/device_summary.dart';
import '../../debug/diagnostic_exporter.dart';
import '../../effects/animation_clock.dart';
import '../../effects/effect_view.dart';
import '../../export/export_service.dart';
import '../../features/result/capture_result.dart';
import '../../features/settings/app_settings.dart';
import '../../features/styles/smart_pick.dart';
import '../../features/styles/style_controller.dart';
import '../../features/styles/style_copy.dart';
import '../../features/styles/style_sheet.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../theme/app_theme.dart';
import 'capture_flash.dart';
import 'first_run_hint.dart';
import 'level_legend.dart';
import 'viewfinder_controller.dart';
import 'viewfinder_controls.dart';
import 'viewfinder_diagnostics.dart';
import 'viewfinder_gestures.dart';
import 'viewfinder_shutter.dart';

/// The camera screen: the live picture with the effect applied.
class ViewfinderScreen extends StatefulWidget {
  const ViewfinderScreen({
    super.key,
    required this.camera,
    required this.ambient,
    required this.styles,
    required this.settings,
    required this.export,
    required this.log,
    required this.exporter,
    required this.device,
    required this.capture,
    this.animationClock,
    this.volumeKeys,
    this.contextSensors = const ContextSensors(),
  });

  final ContextSensors contextSensors;

  /// The camera and the live frames.
  final CameraService camera;

  /// The merged ambient state.
  final AmbientController ambient;

  /// The styles and the renderer.
  final StyleController styles;

  /// The switches.
  final AppSettings settings;

  /// Used to write the pictures.
  final ExportService export;

  /// The logger.
  final DebugLog log;

  /// Used to share the logs.
  final DiagnosticExporter exporter;

  /// What is known about the device.
  final DeviceSummary device;

  /// The timings of the last capture.
  final CaptureMetrics capture;

  /// The clock of the preview animation.
  ///
  /// Injected so tests can assert on the time without sleeping on a real
  /// stopwatch. A production [StopwatchAnimationClock] is used when this is
  /// null.
  final AnimationClock? animationClock;

  /// Hardware shutter input; the platform implementation is owned by the screen.
  final VolumeKeys? volumeKeys;

  @override
  State<ViewfinderScreen> createState() => _ViewfinderScreenState();
}

class _ViewfinderScreenState extends State<ViewfinderScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin
    implements ViewfinderHost {
  late final ViewfinderController _controller;

  /// The preview, the chosen style and the switches.
  late final Listenable _listenable;

  /// The flash that confirms the shot.
  ///
  /// It goes from white to transparent in a fraction of a second, so it
  /// never gets in the way of the preview.
  late final AnimationController _flash;

  /// The pulse of the ring around the shutter.
  ///
  /// It only runs while the moment mode is armed, so the camera is quiet
  /// when nothing is waiting for a peak.
  late final AnimationController _pulse;

  late final DebugTapGesture _tapGesture;

  Timer? _styleFeedbackTimer;
  String? _styleFeedback;
  String? _styleFeedbackStyleId;

  final _swipe = StyleSwipeGesture();

  @override
  void initState() {
    super.initState();
    final clock = widget.animationClock ?? StopwatchAnimationClock();
    WidgetsBinding.instance.addObserver(this);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _controller = ViewfinderController(
      camera: widget.camera,
      ambient: widget.ambient,
      styles: widget.styles,
      settings: widget.settings,
      capture: widget.capture,
      log: widget.log,
      host: this,
      clock: clock,
      contextSensors: widget.contextSensors,
      volumeKeys: widget.volumeKeys,
    )..initialize();
    _listenable = Listenable.merge([
      widget.camera.frame,
      widget.styles,
      widget.settings,
    ]);
    widget.styles.addListener(_invalidateStyleFeedback);
    _tapGesture = DebugTapGesture(
      onTripleTap: () => widget.settings.setDiagnosticsEnabled(
        !widget.settings.diagnosticsEnabled,
      ),
    );
  }

  @override
  void dispose() {
    _styleFeedbackTimer?.cancel();
    _tapGesture.dispose();
    _controller.dispose();
    widget.styles.removeListener(_invalidateStyleFeedback);
    _flash.dispose();
    _pulse.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The status of the route tells whether another screen covers the
    // viewfinder. Asking for it here also makes the screen rebuild when the
    // status changes.
    _controller.didChangeVisibility(ModalRoute.isCurrentOf(context) ?? true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.didChangeAppLifecycleState(state);
  }

  @override
  bool get routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  String get cameraErrorMessage =>
      AppLocalizations.of(context).viewfinderCameraError;

  @override
  void notify() {
    if (mounted) setState(() {});
  }

  @override
  void flashCapture() {
    _flash.duration = AppTheme.motionDuration(context, AppTheme.pressDuration);
    _flash.reverse(from: 1);
  }

  @override
  void syncMomentPulse(bool armed) {
    if (armed && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  Future<void> pushResult(CaptureResult result) async {
    await Navigator.of(context).pushNamed(Routes.result, arguments: result);
  }

  void _onTap() => _tapGesture.register();

  void _startSwipe(DragStartDetails details) {
    _swipe.start(details.globalPosition);
    _tapGesture.cancel();
  }

  void _updateSwipe(DragUpdateDetails details) {
    _swipe.update(details.globalPosition);
  }

  void _endSwipe(DragEndDetails details) {
    final offset = _swipe.end(MediaQuery.sizeOf(context).width);
    if (offset == null) return;
    _selectRelative(offset);
  }

  Future<void> _selectionHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (error) {
      widget.log.warning('style', 'the haptic feedback did not work: $error');
    }
  }

  void _showStyleFeedback(String message) {
    _styleFeedbackTimer?.cancel();
    _styleFeedbackStyleId = widget.styles.style.id;
    setState(() => _styleFeedback = message);
    _styleFeedbackTimer = Timer(
      MediaQuery.disableAnimationsOf(context)
          ? AppTheme.styleFeedbackReducedDuration
          : AppTheme.styleFeedbackDuration,
      () {
        if (mounted) setState(() => _styleFeedback = null);
      },
    );
  }

  void _invalidateStyleFeedback() {
    if (_styleFeedback == null ||
        _styleFeedbackStyleId == widget.styles.style.id) {
      return;
    }
    _styleFeedbackTimer?.cancel();
    setState(() => _styleFeedback = null);
  }

  void _selectRelative(int offset) {
    unawaited(widget.styles.selectRelative(offset));
    _showSelectionFeedback();
    unawaited(_selectionHaptic());
  }

  void _showSelectionFeedback() {
    final style = widget.styles.style;
    _showStyleFeedback(
      '${style.name} - ${styleDescription(AppLocalizations.of(context), style.id)}',
    );
  }

  void _openStyles() {
    // Sampling stops under the sheet. Match the scene at opening, using one
    // fresh reading for both the choice and its explanation, even if values
    // change while the sheet is open (for example through manual controls).
    widget.ambient.tick();
    final openingAmbient = widget.ambient.value;
    final actions = StyleSheetActions(
      styles: widget.styles,
      ambient: widget.ambient,
    );
    unawaited(
      showStyleSheet(
        context,
        styles: widget.styles.styles,
        selectedStyleId: widget.styles.style.id,
        onSelect: (id) {
          unawaited(
            widget.styles.select(
              widget.styles.styles.firstWhere((style) => style.id == id),
            ),
          );
        },
        onRandom: () {
          // Selection is synchronous; renderer loading may finish later.
          unawaited(actions.random());
          _showSelectionFeedback();
        },
        onMatch: () {
          unawaited(
            widget.styles.select(
              pickStyle(openingAmbient, widget.styles.styles),
            ),
          );
          _showStyleFeedback(
            stylePickReason(
              AppLocalizations.of(context),
              openingAmbient,
              widget.styles.style.name,
            ),
          );
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(Routes.settings);
  }

  /// Opens the sheet that explains how the app works.
  void _showLegend() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: AnimationStyle(
          duration: AppTheme.motionDuration(context, AppTheme.sheetDuration),
          reverseDuration: AppTheme.motionDuration(
            context,
            AppTheme.sheetDuration,
          ),
        ),
        backgroundColor: AppTheme.surface,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              AppTheme.styleSheetMaxHeightFactor,
        ),
        builder: (_) => const HowItWorksSheet(),
      ),
    );
  }

  /// Hides the tip of the first run.
  ///
  /// The tip is remembered, so it only comes back when the settings ask
  /// for it.
  void _dismissTip() {
    unawaited(widget.settings.setTipsSeen(true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('style-preview'),
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: _startSwipe,
            onPanUpdate: _updateSwipe,
            onPanEnd: _endSwipe,
            child: ListenableBuilder(
              listenable: _listenable,
              builder: (context, _) {
                final renderer = widget.styles.renderer;
                final image = widget.camera.frame.value;
                _controller.setPreviewReady(renderer != null && image != null);
                if (renderer == null || image == null) {
                  return const ColoredBox(color: AppTheme.background);
                }
                return RepaintBoundary(
                  child: EffectView(
                    renderer: renderer,
                    image: image,
                    ambient: widget.ambient,
                    animationClock: _controller.clock,
                    active: _controller.previewActivity,
                  ),
                );
              },
            ),
          ),
          Positioned.fill(child: CaptureFlash(opacity: _flash)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
              child: ListenableBuilder(
                listenable: Listenable.merge([widget.settings, widget.styles]),
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    // The first-run hint takes priority. Expanded shrinks the
                    // scrollable diagnostics before any essential controls.
                    final hintVisible =
                        widget.settings.isLoaded && !widget.settings.tipsSeen;
                    return Column(
                      children: [
                        const SizedBox(height: AppTheme.spaceSm),
                        ViewfinderTopRow(
                          ambient: widget.ambient,
                          onHelp: _showLegend,
                          onSettings: _openSettings,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, middleConstraints) {
                              // Keep a diagnostics control reachable inside
                              // its margin, padding and border when enabled.
                              final diagnosticsSpace =
                                  widget.settings.diagnosticsEnabled
                                  ? (AppTheme.touchTarget +
                                            2 *
                                                (AppTheme.safeMargin +
                                                    AppTheme.spaceSm +
                                                    AppTheme.borderWidth))
                                        .clamp(
                                          0.0,
                                          middleConstraints.maxHeight / 3,
                                        )
                                  : 0.0;
                              return Column(
                                children: [
                                  Expanded(
                                    child: ClipRect(
                                      child: widget.settings.diagnosticsEnabled
                                          ? ViewfinderDiagnostics(
                                              ambient: widget.ambient,
                                              metrics: widget.camera.metrics,
                                              styleId: widget.styles.style.id,
                                              timings: widget.capture.value,
                                              device: widget.device,
                                              log: widget.log,
                                              exporter: widget.exporter,
                                            )
                                          : const SizedBox.expand(),
                                    ),
                                  ),
                                  // Bound the tip and transient feedback together;
                                  // diagnostics yield space before the controls.
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          middleConstraints.maxHeight -
                                          diagnosticsSpace,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ViewfinderStyleFeedback(
                                          message: _styleFeedback,
                                          styleId: widget.styles.style.id,
                                        ),
                                        if (hintVisible)
                                          Flexible(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal:
                                                        AppTheme.spaceSm,
                                                    vertical: AppTheme.spaceSm,
                                                  ),
                                              child: FirstRunHint(
                                                key: const ValueKey('vf-hint'),
                                                onDismiss: _dismissTip,
                                                onHelp: _showLegend,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        ViewfinderStyleBar(
                          name: widget.styles.style.name,
                          styleId: widget.styles.style.id,
                          index: widget.styles.styles.indexWhere(
                            (style) => style.id == widget.styles.style.id,
                          ),
                          count: widget.styles.styles.length,
                          onPrevious: () => _selectRelative(-1),
                          onNext: () => _selectRelative(1),
                          onChoose: _openStyles,
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        ViewfinderStatusSlot(
                          capturing: _controller.capturing,
                          armed: _controller.momentArmed,
                          error: _controller.cameraError,
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        ViewfinderShutterRow(
                          armed: _controller.momentArmed,
                          busy: _controller.capturing,
                          pulse: _pulse,
                          onAutoShot: _controller.toggleMoment,
                          onShutter: _controller.capturePhoto,
                          onFlip: _controller.flip,
                          shutterLabel: l10n.viewfinderShutterTooltip,
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
