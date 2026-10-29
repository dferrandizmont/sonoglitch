import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ambient/ambient_controller.dart';
import '../../ambient/ambient_state.dart';
import '../../ambient/context_sensors.dart';
import '../../app_config.dart';
import '../../camera/camera_service.dart';
import '../../camera/volume_keys.dart';
import '../../debug/capture_metrics.dart';
import '../../debug/debug_hud.dart';
import '../../debug/debug_log.dart';
import '../../debug/device_summary.dart';
import '../../debug/diagnostic_exporter.dart';
import '../../effects/animation_clock.dart';
import '../../effects/effect_view.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
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
import '../../theme/fringe.dart';
import 'capture_flash.dart';
import 'first_run_hint.dart';
import 'level_legend.dart';
import 'moment_detector.dart';

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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The clock of the preview.
  ///
  /// Both preview paints and still renders read this clock. Its visibility
  /// gate also stops the preview ticker, camera and ambient pipeline.
  late final AnimationClock _clock;
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

  /// The detector of the peaks of the place.
  late final MomentDetector _detector;

  String? _cameraError;
  bool _capturing = false;
  bool _ambientRunning = false;
  bool _appActive = true;
  bool _routeVisible = true;
  bool _previewReady = false;
  bool _cameraReady = false;
  late final VolumeKeys _volumeKeys;
  StreamSubscription<void>? _volumeSubscription;
  final _previewActivity = ValueNotifier(false);

  bool get _viewfinderActive => _appActive && _routeVisible;

  /// Whether the camera is waiting for the peak of the place.
  bool _momentArmed = false;

  int _taps = 0;
  Timer? _tapTimer;
  Timer? _styleFeedbackTimer;
  String? _styleFeedback;
  String? _styleFeedbackStyleId;
  Offset _swipeStart = Offset.zero;
  Offset _swipeDistance = Offset.zero;

  /// The subscription to the samples of the place.
  StreamSubscription<AmbientState>? _momentSubscription;

  static const double _swipeThreshold = 48;
  static const double _swipeHorizontalDominanceRatio = 1.5;
  @override
  void initState() {
    super.initState();
    _volumeKeys = widget.volumeKeys ?? platformVolumeKeys();
    _volumeSubscription = _volumeKeys.presses.listen((_) {
      if (!mounted) return;
      // Recheck the route too: a press may already be in flight when a
      // sheet opens, before the dependency change updates _routeVisible.
      if (_canUseVolumeKeys && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_capture());
      }
    });
    _clock = widget.animationClock ?? StopwatchAnimationClock();
    WidgetsBinding.instance.addObserver(this);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _detector = MomentDetector(
      canFire: _canFireMoment,
      // The detector measures the quiet period with the clock of the
      // ambient pipeline, so its times and the times of the samples are the
      // same ones.
      clock: widget.ambient.clock,
    );
    _momentSubscription = widget.ambient.states.listen(_onAmbientState);
    _listenable = Listenable.merge([
      widget.camera.frame,
      widget.styles,
      widget.settings,
    ]);
    widget.styles.addListener(_invalidateStyleFeedback);
    widget.styles.addListener(_syncSeedStyle);
    _syncSeedStyle();
    widget.camera.motion = widget.ambient.motion;
    // The colourfulness of the frames feeds the contextual lanes of the shot.
    widget.camera.signals = widget.ambient.signals;
    widget.settings.addListener(_syncIntensity);
    widget.settings.addListener(_syncMomentSettings);
    widget.settings.addListener(_syncVolumeKeys);
    widget.camera.frame.addListener(_syncVolumeKeys);
    _syncIntensity();
    _syncMomentSettings();
    unawaited(_start());
  }

  void _syncSeedStyle() => widget.ambient.setStyle(widget.styles.style.id);

  void _syncIntensity() =>
      widget.ambient.setIntensity(widget.settings.intensity);

  Future<void> _start() async {
    _syncAmbient();
    await widget.styles.load();
    try {
      await widget.camera.initialize();
      if (!mounted) return;
      _cameraReady = true;
      _syncVolumeKeys();
    } catch (error, stackTrace) {
      widget.log.error('camera', 'the camera did not start', error, stackTrace);
      if (!mounted) return;
      _showError(AppLocalizations.of(context).viewfinderCameraError);
    }
  }

  @override
  void dispose() {
    _volumeKeys.enabled = false;
    unawaited(_volumeSubscription?.cancel());
    if (widget.volumeKeys == null) _volumeKeys.dispose();
    widget.settings.removeListener(_syncVolumeKeys);
    widget.camera.frame.removeListener(_syncVolumeKeys);
    _tapTimer?.cancel();
    _styleFeedbackTimer?.cancel();
    _momentSubscription?.cancel();
    widget.styles.removeListener(_invalidateStyleFeedback);
    widget.styles.removeListener(_syncSeedStyle);
    widget.settings.removeListener(_syncIntensity);
    widget.settings.removeListener(_syncMomentSettings);
    _flash.dispose();
    _pulse.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _ambientRunning = false;
    _clock.stop();
    _previewActivity.dispose();
    widget.ambient.stop();
    unawaited(widget.camera.dispose());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The status of the route tells whether another screen covers the
    // viewfinder. Asking for it here also makes the screen rebuild when the
    // status changes.
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    // A capture opens the picture, which covers the viewfinder: the moment
    // mode stays armed so the next peak is caught too. Any other screen
    // means the user left the camera, so the mode stops.
    if (!visible && !_capturing) _disarmMoment(rebuild: false);
    _routeVisible = visible;
    _syncAmbient();
    _syncClock();
    _syncCamera();
    _syncVolumeKeys();
    _syncMomentArmed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appActive = false;
        break;
    }
    // The camera never takes a photo on its own while the app is in the
    // background.
    if (!_appActive) _disarmMoment();
    _syncAmbient();
    _syncClock();
    _syncCamera();
    _syncVolumeKeys();
    setState(() {});
  }

  bool get _canUseVolumeKeys =>
      mounted &&
      widget.settings.volumeButtonsEnabled &&
      _viewfinderActive &&
      !_capturing &&
      _cameraReady &&
      _cameraError == null &&
      widget.camera.frame.value != null &&
      !widget.camera.isPaused;

  void _syncVolumeKeys() => _volumeKeys.enabled = _canUseVolumeKeys;

  /// Starts or stops the camera.
  ///
  /// The stream of pictures only runs while the preview is on top of the
  /// navigator and the app is in the foreground: behind another route the
  /// frames would be converted and the light of the scene measured for
  /// nothing. The camera itself stays open, so coming back to the viewfinder
  /// does not wait for a new initialisation.
  void _syncCamera() {
    final shouldRun = _viewfinderActive;
    unawaited(widget.camera.setPaused(!shouldRun));
  }

  /// Starts or stops the ambient sensors.
  ///
  /// The microphone must never be open while the viewfinder is not visible, so
  /// the sensors only run when the screen is on top of the navigator and the
  /// app is in the foreground. Starting or stopping twice is harmless.
  void _syncAmbient() {
    final shouldRun = _viewfinderActive;
    if (shouldRun == _ambientRunning) return;
    _ambientRunning = shouldRun;
    if (shouldRun) {
      widget.ambient.start();
      return;
    }
    widget.ambient.stop();
    _detector.reset();
    // The history of a moment that is already over would pollute the
    // snapshot of the next capture.
    widget.ambient.clearHistory();
  }

  /// Starts or stops the clock of the animation.
  ///
  /// The clock only runs while the preview is drawn and the viewfinder is
  /// visible, so the still is drawn with the same time the preview was
  /// showing. Starting or stopping it twice is harmless.
  void _syncClock() {
    final shouldRun = _previewReady && _viewfinderActive;
    _previewActivity.value = shouldRun;
    if (shouldRun) {
      _clock.start();
      return;
    }
    _clock.stop();
  }

  /// The time of the animation, in seconds.
  double get _animationTime => _clock.elapsedSeconds;

  void _onTap() {
    if (!AppConfig.debugBuild) return;
    _taps++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 400), () {
      _taps = 0;
    });
    if (_taps >= 3) {
      _taps = 0;
      // The triple tap and the switch of the settings are the same thing, so
      // the panel keeps its state between sessions.
      widget.settings.setDiagnosticsEnabled(
        !widget.settings.diagnosticsEnabled,
      );
    }
  }

  void _startSwipe(DragStartDetails details) {
    _swipeStart = details.globalPosition;
    _swipeDistance = Offset.zero;
    _tapTimer?.cancel();
    _taps = 0;
  }

  void _endSwipe(DragEndDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    if (_swipeStart.dx < AppTheme.swipeEdgeDeadZone ||
        _swipeStart.dx > width - AppTheme.swipeEdgeDeadZone ||
        _swipeDistance.dx.abs() < _swipeThreshold ||
        _swipeDistance.dx.abs() <
            _swipeDistance.dy.abs() * _swipeHorizontalDominanceRatio) {
      return;
    }
    _selectRelative(_swipeDistance.dx < 0 ? 1 : -1);
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

  /// Keeps the detector in sync with the settings.
  ///
  /// The switch of the settings can be changed while the viewfinder is
  /// behind another screen, so the value is read every time it changes.
  void _syncMomentSettings() {
    _detector.keepArmed = widget.settings.momentKeepArmed;
  }

  /// Arms or disarms the moment mode.
  ///
  /// While it is armed the camera takes the photo by itself at the peak of
  /// the place, so the user does not have to press the shutter.
  void _toggleMoment() {
    final armed = !_momentArmed;
    if (armed) {
      _detector.arm();
    } else {
      _detector.disarm();
    }
    setState(_syncMomentArmed);
  }

  /// Keeps the indicator and its ticker in sync with the detector.
  void _syncMomentArmed() {
    _momentArmed = _detector.isArmed;
    if (_momentArmed && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  /// Stops waiting for a peak.
  ///
  /// The camera never takes a photo on its own while nobody is looking at
  /// it, so leaving the viewfinder or sending the app to the background
  /// disarms the moment mode.
  void _disarmMoment({bool rebuild = true}) {
    _detector.disarm();
    if (rebuild && mounted) {
      setState(_syncMomentArmed);
      return;
    }
    // The screen is rebuilt right after a dependency change, so the state
    // can be changed without asking for another frame.
    _syncMomentArmed();
  }

  /// Whether a photo can be taken right now.
  ///
  /// A photo is only taken while the viewfinder is on top of the navigator,
  /// the app is in the foreground and no other photo is being taken.
  bool _canFireMoment() => !_capturing && _viewfinderActive;

  /// Watches the place and takes the photo when there is a peak.
  ///
  /// The photo is taken exactly like the one of the shutter, so the flash,
  /// the haptic and the picture of the result are the same.
  void _onAmbientState(AmbientState state) {
    if (!_ambientRunning) return;
    if (!_detector.add(state)) return;
    if (!mounted) return;
    setState(_syncMomentArmed);
    unawaited(_capture());
  }

  Future<void> _flip() async {
    _cameraReady = false;
    _syncVolumeKeys();
    try {
      await widget.camera.flip();
      if (mounted) {
        setState(() => _cameraError = null);
        _cameraReady = true;
        _syncVolumeKeys();
      }
    } catch (error, stackTrace) {
      widget.log.error(
        'camera',
        'the camera could not be flipped',
        error,
        stackTrace,
      );
      if (!mounted) return;
      _showError(AppLocalizations.of(context).viewfinderCameraError);
    }
  }

  Future<void> _capture() async {
    if (_capturing || !_viewfinderActive) return;
    setState(() {
      _capturing = true;
      _cameraError = null;
    });
    _syncVolumeKeys();
    widget.capture.reset();
    // The shot is confirmed with a short flash and a tap in the hand.
    _flash.duration = AppTheme.motionDuration(context, AppTheme.pressDuration);
    _flash.reverse(from: 1);
    unawaited(_haptic());
    // The time of the animation is read at the shutter, so the still shows the
    // same frame of the animation that the preview was showing.
    final time = _animationTime;
    final contextSample = widget.settings.contextLineEnabled
        ? widget.contextSensors.sample(dateTime: DateTime.now())
        : Future<ExportContext?>.value();
    final previewSnapshot = widget.ambient.snapshot(
      const Duration(milliseconds: 1500),
    );
    try {
      final capture = await widget.camera.captureStill(deferDecode: true);
      if (capture == null) {
        throw StateError('The camera did not return a picture');
      }
      final transform = capture.transform;
      final snapshot = previewSnapshot.forPhotoTurns(
        transform?.quarterTurns ?? 0,
        mirrorX: transform?.mirrorPreview ?? false,
      );
      widget.capture.update(
        ambient: snapshot,
        takeMs: capture.timings.takeMs,
        decodeMs: capture.timings.decodeMs,
        animationTime: time,
      );

      final source = capture.source;
      if (source != null) {
        final exportContext = await contextSample;
        if (!mounted) return;
        final quality = widget.settings.exportQuality;
        await Navigator.of(context).pushNamed(
          Routes.result,
          arguments: CaptureResult.source(
            source: source,
            quality: quality,
            render: (image, maxSide) => widget.styles.renderStill(
              image,
              ambient: snapshot,
              time: time,
              maxSide: maxSide,
            ),
            ambient: snapshot,
            context: exportContext,
            styleId: widget.styles.style.id,
          ),
        );
        return;
      }

      final renderStart = DateTime.now().millisecondsSinceEpoch;
      final ui.Image rendered;
      try {
        rendered = await widget.styles.renderStill(
          capture.image,
          ambient: snapshot,
          time: time,
          maxSide: widget.settings.exportQuality == ExportQuality.standard
              ? 2048
              : 4096,
        );
      } finally {
        // The picture of the camera belongs to the capture, not to the
        // renderer.
        capture.image.dispose();
      }
      widget.capture.update(
        renderMs: (DateTime.now().millisecondsSinceEpoch - renderStart)
            .toDouble(),
      );

      final exportContext = await contextSample;
      if (!mounted) {
        rendered.dispose();
        return;
      }
      await Navigator.of(context).pushNamed(
        Routes.result,
        arguments: CaptureResult(
          rendered: rendered,
          ambient: snapshot,
          context: exportContext,
          styleId: widget.styles.style.id,
        ),
      );
    } catch (error, stackTrace) {
      widget.log.error('capture', 'the capture failed', error, stackTrace);
      if (!mounted) return;
      _showError(AppLocalizations.of(context).viewfinderCameraError);
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
        _syncVolumeKeys();
      }
    }
  }

  /// The tap in the hand that confirms the shot.
  ///
  /// The tap is a nicety: a phone without a motor must not break the
  /// capture, so a failure is only written in the log.
  Future<void> _haptic() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (error) {
      widget.log.warning('capture', 'the haptic feedback did not work: $error');
    }
  }

  void _showError(String message) {
    setState(() => _cameraError = message);
    _syncVolumeKeys();
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
            onPanUpdate: (details) =>
                _swipeDistance = details.globalPosition - _swipeStart,
            onPanEnd: _endSwipe,
            child: ListenableBuilder(
              listenable: _listenable,
              builder: (context, _) {
                final renderer = widget.styles.renderer;
                final image = widget.camera.frame.value;
                _previewReady = renderer != null && image != null;
                _syncClock();
                if (renderer == null || image == null) {
                  return const ColoredBox(color: AppTheme.background);
                }
                return RepaintBoundary(
                  child: EffectView(
                    renderer: renderer,
                    image: image,
                    ambient: widget.ambient,
                    animationClock: _clock,
                    active: _previewActivity,
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
                        _TopRow(
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
                                          ? Align(
                                              alignment: Alignment.topLeft,
                                              child: LayoutBuilder(
                                                builder: (context, hudConstraints) {
                                                  // The existing HUD has an intrinsic-width button row.
                                                  // Keep it scrollable without modifying the parallel job's file.
                                                  final minWidth =
                                                      AppTheme
                                                          .diagnosticsMinWidth *
                                                      MediaQuery.textScalerOf(
                                                        context,
                                                      ).scale(1);
                                                  return SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: SizedBox(
                                                      width:
                                                          hudConstraints
                                                                  .maxWidth <
                                                              minWidth
                                                          ? minWidth
                                                          : hudConstraints
                                                                .maxWidth,
                                                      height: hudConstraints
                                                          .maxHeight,
                                                      child: DebugHud(
                                                        ambient: widget.ambient,
                                                        metrics: widget
                                                            .camera
                                                            .metrics,
                                                        styleId: widget
                                                            .styles
                                                            .style
                                                            .id,
                                                        timings: widget
                                                            .capture
                                                            .value,
                                                        device: widget.device,
                                                        log: widget.log,
                                                        exporter:
                                                            widget.exporter,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
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
                                        IgnorePointer(
                                          child: AnimatedSwitcher(
                                            key: ValueKey(
                                              widget.styles.style.id,
                                            ),
                                            duration: AppTheme.motionDuration(
                                              context,
                                              AppTheme
                                                  .feedbackTransitionDuration,
                                            ),
                                            child: _styleFeedback == null
                                                ? const SizedBox.shrink()
                                                : Semantics(
                                                    key: ValueKey(
                                                      _styleFeedback,
                                                    ),
                                                    liveRegion: true,
                                                    child: Container(
                                                      key: const ValueKey(
                                                        'style-feedback',
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: AppTheme
                                                                .spaceSmMd,
                                                            vertical: AppTheme
                                                                .spaceSm,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme
                                                            .scrimStrong,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              AppTheme.radiusSm,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _styleFeedback!,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: AppTheme.body
                                                            .copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
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
                        _StyleBar(
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
                        _StatusSlot(
                          capturing: _capturing,
                          armed: _momentArmed,
                          error: _cameraError,
                        ),
                        const SizedBox(height: AppTheme.spaceSm),
                        _ShutterRow(
                          armed: _momentArmed,
                          busy: _capturing,
                          pulse: _pulse,
                          onAutoShot: _toggleMoment,
                          onShutter: _capture,
                          onFlip: _flip,
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

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.ambient,
    required this.onHelp,
    required this.onSettings,
  });
  final AmbientController ambient;
  final VoidCallback onHelp;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LevelLegend(
        key: const ValueKey('vf-meters'),
        ambient: ambient,
        onExplain: onHelp,
      ),
      _OverlayButton(
        key: const ValueKey('vf-settings'),
        icon: Icons.settings_outlined,
        label: AppLocalizations.of(context).viewfinderSettingsTooltip,
        onPressed: onSettings,
      ),
    ],
  );
}

class _StyleBar extends StatelessWidget {
  const _StyleBar({
    required this.name,
    required this.styleId,
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.onChoose,
  });
  final String name;
  final String styleId;
  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusSm);
    return Center(
      child: Container(
        height: AppTheme.styleBarHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.scrimStrong,
          borderRadius: radius,
          // A foreground border does not subtract space from the 48 dp targets.
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: AppTheme.overlayEdge,
            width: AppTheme.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              key: const ValueKey('vf-style-prev'),
              dimension: AppTheme.touchTarget,
              child: _PressTarget(
                label: l10n.viewfinderPrevStyle,
                onPressed: onPrevious,
                builder: (_, pressed) => _railFace(
                  pressed: pressed,
                  child: const Icon(
                    Icons.chevron_left,
                    size: AppTheme.overlayIconSize,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppTheme.touchTarget,
                  maxWidth: AppTheme.stylePillMaxWidth,
                ),
                child: SizedBox(
                  key: const ValueKey('vf-style-bar'),
                  height: AppTheme.styleBarHeight,
                  child: _PressTarget(
                    label: l10n.viewfinderStyleButton(name),
                    onPressed: onChoose,
                    builder: (_, pressed) => _railFace(
                      pressed: pressed,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            top: AppTheme.spaceSmMd,
                            bottom: AppTheme.spaceSmMd,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.symmetric(
                                  vertical: BorderSide(
                                    color: AppTheme.overlayEdge,
                                    width: AppTheme.borderWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spaceSmMd,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FringeText(
                                    name.toUpperCase(),
                                    value: ValueKey(styleId),
                                    style: AppTheme.micro.copyWith(
                                      color: AppTheme.textPrimary,
                                      fontSize: AppTheme.styleNameFontSize,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: AppTheme.spaceXs + AppTheme.space2xs,
                                ),
                                Text(
                                  '${(index + 1).toString().padLeft(2, '0')}/${count.toString().padLeft(2, '0')}',
                                  style: AppTheme.readoutSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spaceXs),
                                const Icon(
                                  Icons.unfold_more,
                                  size: AppTheme.meterIconSize,
                                  color: AppTheme.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox.square(
              key: const ValueKey('vf-style-next'),
              dimension: AppTheme.touchTarget,
              child: _PressTarget(
                label: l10n.viewfinderNextStyle,
                onPressed: onNext,
                builder: (_, pressed) => _railFace(
                  pressed: pressed,
                  child: const Icon(
                    Icons.chevron_right,
                    size: AppTheme.overlayIconSize,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railFace({required bool pressed, required Widget child}) =>
      ColoredBox(
        color: pressed ? AppTheme.pressedOverlay : Colors.transparent,
        child: Center(child: child),
      );
}

class _StatusSlot extends StatelessWidget {
  const _StatusSlot({required this.capturing, required this.armed, this.error});
  final bool capturing;
  final bool armed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label =
        error ??
        (capturing
            ? l10n.viewfinderCapturing
            : armed
            ? l10n.viewfinderMomentArmed
            : null);
    return SizedBox(
      key: const ValueKey('vf-status'),
      height: AppTheme.statusSlotHeight,
      width: double.infinity,
      child: label == null
          ? null
          : Center(
              child: Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('vf-status-tag'),
                  height: AppTheme.statusSlotHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.scrimStrong,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusLed(
                        blinking: capturing && error == null,
                        color: error != null
                            ? AppTheme.danger
                            : capturing
                            ? AppTheme.warm
                            : AppTheme.accent,
                      ),
                      const SizedBox(
                        width: AppTheme.spaceXs + AppTheme.space2xs,
                      ),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textPrimary,
                            fontSize: AppTheme.statusFontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The capture LED has one on/off cycle per second; errors stay steadily lit.
class _StatusLed extends StatefulWidget {
  const _StatusLed({required this.color, required this.blinking});
  final Color color;
  final bool blinking;

  @override
  State<_StatusLed> createState() => _StatusLedState();
}

class _StatusLedState extends State<_StatusLed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_StatusLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBlink();
  }

  void _syncBlink() {
    final duration = AppTheme.motionDuration(
      context,
      const Duration(seconds: 1),
    );
    if (widget.blinking && duration != Duration.zero) {
      _blink.duration = duration;
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _blink,
    child: SizedBox.square(
      key: const ValueKey('vf-status-led'),
      dimension: AppTheme.spaceXs + AppTheme.space2xs,
      child: ColoredBox(color: widget.color),
    ),
    builder: (_, child) =>
        Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
  );
}

class _ShutterRow extends StatelessWidget {
  // The shared theme has no tokens for these required shutter-only values.
  // Keep them local until the theme owner supplies the shared tokens.
  static const _pressedScale = 0.92;
  static const _haloOpacity = 0.35;

  const _ShutterRow({
    required this.armed,
    required this.busy,
    required this.pulse,
    required this.onAutoShot,
    required this.onShutter,
    required this.onFlip,
    required this.shutterLabel,
  });
  final bool armed;
  final bool busy;
  final Animation<double> pulse;
  final VoidCallback onAutoShot;
  final VoidCallback onShutter;
  final VoidCallback onFlip;
  final String shutterLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: AppTheme.shutterSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            toggled: armed,
            child: _OverlayButton(
              key: const ValueKey('vf-auto-shot'),
              icon: Icons.graphic_eq,
              label: l10n.viewfinderMomentTooltip,
              onPressed: onAutoShot,
              selected: armed,
            ),
          ),
          const SizedBox(
            width:
                AppTheme.shutterSideOffset -
                AppTheme.touchTarget / 2 -
                AppTheme.shutterSize / 2,
          ),
          SizedBox.square(
            key: const ValueKey('vf-shutter'),
            dimension: AppTheme.shutterSize,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (armed)
                  Positioned.fill(
                    left:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    right:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    top:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    bottom:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: pulse,
                        builder: (context, _) {
                          final reduced = MediaQuery.disableAnimationsOf(
                            context,
                          );
                          final t = reduced ? 1.0 : pulse.value;
                          return Transform.scale(
                            scale: reduced
                                ? 1
                                : AppTheme.shutterSize /
                                          AppTheme.pulseRingDiameter +
                                      (1 -
                                              AppTheme.shutterSize /
                                                  AppTheme.pulseRingDiameter) *
                                          t,
                            child: Container(
                              key: const ValueKey('moment-ring'),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.accent.withValues(
                                    alpha: reduced ? 1 : 1 - t / 2,
                                  ),
                                  width: AppTheme.ringStrokeWidth,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                _PressTarget(
                  label: shutterLabel,
                  circularFocus: true,
                  enabled: !busy,
                  onPressed: busy ? null : onShutter,
                  builder: (context, pressed) => Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.background.withValues(
                                alpha: _haloOpacity,
                              ),
                              width: AppTheme.borderWidth,
                            ),
                          ),
                          child: CustomPaint(
                            key: const ValueKey('vf-shutter-ring'),
                            painter: FringeRingPainter(
                              color: busy || armed
                                  ? AppTheme.accent
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        // The shared painter insets the ring by its fringe offset.
                        padding: const EdgeInsets.all(
                          AppTheme.fringeRingOffset +
                              AppTheme.shutterStrokeWidth +
                              AppTheme.shutterInset,
                        ),
                        child: AnimatedScale(
                          key: const ValueKey('vf-shutter-disc'),
                          scale: pressed && !busy ? _pressedScale : 1,
                          duration: AppTheme.motionDuration(
                            context,
                            AppTheme.pressDuration,
                          ),
                          curve: AppTheme.motionCurve,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: busy
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width:
                AppTheme.shutterSideOffset -
                AppTheme.touchTarget / 2 -
                AppTheme.shutterSize / 2,
          ),
          _OverlayButton(
            key: const ValueKey('vf-flip'),
            icon: Icons.cameraswitch_outlined,
            label: l10n.viewfinderFlipTooltip,
            onPressed: onFlip,
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppTheme.touchTarget,
    child: _PressTarget(
      label: label,
      onPressed: onPressed,
      builder: (context, pressed) => Center(
        child: AnimatedContainer(
          duration: AppTheme.motionDuration(context, AppTheme.pressDuration),
          curve: AppTheme.motionCurve,
          width: AppTheme.touchTarget - AppTheme.spaceXs,
          height: AppTheme.touchTarget - AppTheme.spaceXs,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.scrim,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: selected
                ? null
                : Border.all(
                    color: AppTheme.overlayEdge,
                    width: AppTheme.borderWidth,
                  ),
          ),
          foregroundDecoration: pressed
              ? BoxDecoration(
                  color: AppTheme.pressedOverlay,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                )
              : null,
          child: Icon(
            icon,
            size: AppTheme.overlayIconSize,
            color: onPressed == null
                ? AppTheme.textTertiary
                : selected
                ? AppTheme.onAccent
                : AppTheme.textPrimary,
          ),
        ),
      ),
    ),
  );
}

/// Shared accessible hit area. Its visual child can be smaller than the target.
class _PressTarget extends StatefulWidget {
  const _PressTarget({
    required this.label,
    required this.onPressed,
    required this.builder,
    this.enabled,
    this.circularFocus = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool pressed) builder;
  final bool? enabled;
  final bool circularFocus;

  @override
  State<_PressTarget> createState() => _PressTargetState();
}

class _PressTargetState extends State<_PressTarget> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onPressed != null,
    includeFocusSemantics: false,
    onShowFocusHighlight: (value) {
      if (_focused != value) setState(() => _focused = value);
    },
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        },
      ),
    },
    child: Semantics(
      button: true,
      enabled: widget.enabled ?? (widget.onPressed == null ? false : null),
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          onTapDown: widget.onPressed == null ? null : (_) => _setPressed(true),
          onTapUp: widget.onPressed == null ? null : (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: widget.circularFocus
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              borderRadius: widget.circularFocus
                  ? null
                  : BorderRadius.circular(AppTheme.radiusSm),
              color: _focused ? AppTheme.focusOverlay : null,
              border: _focused
                  ? Border.all(
                      color: AppTheme.accent,
                      width: AppTheme.borderWidth,
                    )
                  : null,
            ),
            child: widget.builder(context, _pressed),
          ),
        ),
      ),
    ),
  );
}
