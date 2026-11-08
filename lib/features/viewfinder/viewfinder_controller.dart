import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ambient/ambient_controller.dart';
import '../../ambient/ambient_state.dart';
import '../../ambient/context_sensors.dart';
import '../../camera/camera_service.dart';
import '../../camera/volume_keys.dart';
import '../../debug/capture_metrics.dart';
import '../../debug/debug_log.dart';
import '../../effects/animation_clock.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
import '../../features/result/capture_result.dart';
import '../../features/settings/app_settings.dart';
import '../../features/styles/style_controller.dart';
import 'moment_detector.dart';

/// What the viewfinder controller needs from the screen that shows it.
///
/// The controller owns the flow of the camera, but the flashing overlay, the
/// pulse of the ring and the route belong to the widgets, so the screen
/// supplies them through this interface.
abstract class ViewfinderHost {
  /// Whether the screen is still in the tree.
  bool get mounted;

  /// Whether the route of the viewfinder is the one on top.
  bool get routeIsCurrent;

  /// The message that says the camera did not start.
  String get cameraErrorMessage;

  /// Rebuilds the screen.
  void notify();

  /// Plays the flash that confirms the shot.
  void flashCapture();

  /// Starts or stops the pulse of the ring around the shutter.
  void syncMomentPulse(bool armed);

  /// Opens the result with [result] and waits until it is closed.
  Future<void> pushResult(CaptureResult result);
}

/// The logic of the camera screen: capture, auto shot, volume keys, clock,
/// ambient sensors and lifecycle.
///
/// It holds no widgets, so every rule can be checked without building the
/// screen. The screen listens to it through [ViewfinderHost].
class ViewfinderController {
  ViewfinderController({
    required this.camera,
    required this.ambient,
    required this.styles,
    required this.settings,
    required this.capture,
    required this.log,
    required this.host,
    required this.clock,
    this.contextSensors = const ContextSensors(),
    this.volumeKeys,
  });

  /// The camera and the live frames.
  final CameraService camera;

  /// The merged ambient state.
  final AmbientController ambient;

  /// The styles and the renderer.
  final StyleController styles;

  /// The switches.
  final AppSettings settings;

  /// The timings of the last capture.
  final CaptureMetrics capture;

  /// The logger.
  final DebugLog log;

  /// The screen that shows the controller.
  final ViewfinderHost host;

  /// The clock of the preview animation.
  final AnimationClock clock;

  /// The sensors of the place at the shutter.
  final ContextSensors contextSensors;

  /// Hardware shutter input, when the test brings its own.
  final VolumeKeys? volumeKeys;

  late final VolumeKeys _volumeKeys;
  late final bool _ownsVolumeKeys;
  late final MomentDetector _detector;
  StreamSubscription<void>? _volumeSubscription;
  StreamSubscription<AmbientState>? _momentSubscription;

  final _previewActivity = ValueNotifier(false);

  bool _cameraErrorSet = false;
  String _cameraError = '';
  bool _capturing = false;
  bool _ambientRunning = false;
  bool _appActive = true;
  bool _routeVisible = true;
  bool _previewReady = false;
  bool _cameraReady = false;

  /// Whether the camera is waiting for the peak of the place.
  bool _momentArmed = false;

  /// Whether the camera never takes a photo while nobody is looking at it.
  bool get viewfinderActive => _appActive && _routeVisible;

  /// Whether a photo is being taken.
  bool get capturing => _capturing;

  /// Whether the camera is waiting for the peak of the place.
  bool get momentArmed => _momentArmed;

  /// The message of the last camera error, if any.
  String? get cameraError => _cameraErrorSet ? _cameraError : null;

  /// Whether the preview animation is being drawn.
  ValueListenable<bool> get previewActivity => _previewActivity;

  /// The time of the animation, in seconds.
  double get animationTime => clock.elapsedSeconds;

  /// Whether a photo can be taken right now.
  ///
  /// A photo is only taken while the viewfinder is on top of the navigator,
  /// the app is in the foreground and no other photo is being taken.
  bool get canFireMoment => !_capturing && viewfinderActive;

  /// Starts the listeners and the camera.
  void initialize() {
    _ownsVolumeKeys = volumeKeys == null;
    _volumeKeys = volumeKeys ?? platformVolumeKeys();
    _volumeSubscription = _volumeKeys.presses.listen((_) {
      if (!host.mounted) return;
      // Recheck the route too: a press may already be in flight when a
      // sheet opens, before the dependency change updates the route.
      if (canUseVolumeKeys && host.routeIsCurrent) {
        unawaited(capturePhoto());
      }
    });
    _detector = MomentDetector(
      canFire: () => canFireMoment,
      // The detector measures the quiet period with the clock of the
      // ambient pipeline, so its times and the times of the samples are the
      // same ones.
      clock: ambient.clock,
    );
    _momentSubscription = ambient.states.listen(_onAmbientState);
    styles.addListener(_syncSeedStyle);
    _syncSeedStyle();
    camera.motion = ambient.motion;
    // The colourfulness of the frames feeds the contextual lanes of the shot.
    camera.signals = ambient.signals;
    settings.addListener(_syncIntensity);
    settings.addListener(_syncMomentSettings);
    settings.addListener(syncVolumeKeys);
    camera.frame.addListener(syncVolumeKeys);
    _syncIntensity();
    _syncMomentSettings();
    unawaited(_start());
  }

  void _syncSeedStyle() => ambient.setStyle(styles.style.id);

  void _syncIntensity() => ambient.setIntensity(settings.intensity);

  Future<void> _start() async {
    _syncAmbient();
    await styles.load();
    try {
      await camera.initialize();
      if (!host.mounted) return;
      _cameraReady = true;
      syncVolumeKeys();
    } catch (error, stackTrace) {
      log.error('camera', 'the camera did not start', error, stackTrace);
      if (!host.mounted) return;
      _showError(host.cameraErrorMessage);
    }
  }

  /// Releases everything the controller owns.
  ///
  /// The screen keeps its own listeners and its animations.
  void dispose() {
    _volumeKeys.enabled = false;
    unawaited(_volumeSubscription?.cancel());
    if (_ownsVolumeKeys) _volumeKeys.dispose();
    settings.removeListener(syncVolumeKeys);
    camera.frame.removeListener(syncVolumeKeys);
    _momentSubscription?.cancel();
    styles.removeListener(_syncSeedStyle);
    settings.removeListener(_syncIntensity);
    settings.removeListener(_syncMomentSettings);
    _ambientRunning = false;
    clock.stop();
    _previewActivity.dispose();
    ambient.stop();
    unawaited(camera.dispose());
  }

  /// Tells the controller whether another route covers the viewfinder.
  void didChangeVisibility(bool visible) {
    // A capture opens the picture, which covers the viewfinder: the moment
    // mode stays armed so the next peak is caught too. Any other screen
    // means the user left the camera, so the mode stops.
    if (!visible && !_capturing) _disarmMoment(rebuild: false);
    _routeVisible = visible;
    _syncAmbient();
    _syncClock();
    _syncCamera();
    syncVolumeKeys();
    _syncMomentArmed();
  }

  /// Tells the controller whether the app is in the foreground.
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
    syncVolumeKeys();
    host.notify();
  }

  /// Tells the controller whether the preview can be drawn.
  ///
  /// The screen calls this while it builds, so the clock follows the
  /// availability of a renderer and a frame.
  void setPreviewReady(bool ready) {
    _previewReady = ready;
    _syncClock();
  }

  /// Whether the volume keys can take a photo right now.
  bool get canUseVolumeKeys =>
      host.mounted &&
      settings.volumeButtonsEnabled &&
      viewfinderActive &&
      !_capturing &&
      _cameraReady &&
      !_cameraErrorSet &&
      camera.frame.value != null &&
      !camera.isPaused;

  /// Enables or disables the hardware shutter.
  void syncVolumeKeys() => _volumeKeys.enabled = canUseVolumeKeys;

  /// Starts or stops the camera.
  ///
  /// The stream of pictures only runs while the preview is on top of the
  /// navigator and the app is in the foreground: behind another route the
  /// frames would be converted and the light of the scene measured for
  /// nothing. The camera itself stays open, so coming back to the viewfinder
  /// does not wait for a new initialisation.
  void _syncCamera() {
    final shouldRun = viewfinderActive;
    unawaited(camera.setPaused(!shouldRun));
  }

  /// Starts or stops the ambient sensors.
  ///
  /// The microphone must never be open while the viewfinder is not visible, so
  /// the sensors only run when the screen is on top of the navigator and the
  /// app is in the foreground. Starting or stopping twice is harmless.
  void _syncAmbient() {
    final shouldRun = viewfinderActive;
    if (shouldRun == _ambientRunning) return;
    _ambientRunning = shouldRun;
    if (shouldRun) {
      ambient.start();
      return;
    }
    ambient.stop();
    _detector.reset();
    // The history of a moment that is already over would pollute the
    // snapshot of the next capture.
    ambient.clearHistory();
  }

  /// Starts or stops the clock of the animation.
  ///
  /// The clock only runs while the preview is drawn and the viewfinder is
  /// visible, so the still is drawn with the same time the preview was
  /// showing. Starting or stopping it twice is harmless.
  void _syncClock() {
    final shouldRun = _previewReady && viewfinderActive;
    _previewActivity.value = shouldRun;
    if (shouldRun) {
      clock.start();
      return;
    }
    clock.stop();
  }

  /// Keeps the detector in sync with the settings.
  ///
  /// The switch of the settings can be changed while the viewfinder is
  /// behind another screen, so the value is read every time it changes.
  void _syncMomentSettings() {
    _detector.keepArmed = settings.momentKeepArmed;
  }

  /// Arms or disarms the moment mode.
  ///
  /// While it is armed the camera takes the photo by itself at the peak of
  /// the place, so the user does not have to press the shutter.
  void toggleMoment() {
    final armed = !_momentArmed;
    if (armed) {
      _detector.arm();
    } else {
      _detector.disarm();
    }
    _syncMomentArmed();
    host.notify();
  }

  /// Keeps the indicator and its ticker in sync with the detector.
  void _syncMomentArmed() {
    _momentArmed = _detector.isArmed;
    host.syncMomentPulse(_momentArmed);
  }

  /// Stops waiting for a peak.
  ///
  /// The camera never takes a photo on its own while nobody is looking at
  /// it, so leaving the viewfinder or sending the app to the background
  /// disarms the moment mode.
  void _disarmMoment({bool rebuild = true}) {
    _detector.disarm();
    _syncMomentArmed();
    if (rebuild && host.mounted) host.notify();
  }

  /// Watches the place and takes the photo when there is a peak.
  ///
  /// The photo is taken exactly like the one of the shutter, so the flash,
  /// the haptic and the picture of the result are the same.
  void _onAmbientState(AmbientState state) {
    if (!_ambientRunning) return;
    if (!_detector.add(state)) return;
    if (!host.mounted) return;
    _syncMomentArmed();
    host.notify();
    unawaited(capturePhoto());
  }

  /// Flips the camera.
  Future<void> flip() async {
    _cameraReady = false;
    syncVolumeKeys();
    try {
      await camera.flip();
      if (host.mounted) {
        _cameraErrorSet = false;
        host.notify();
        _cameraReady = true;
        syncVolumeKeys();
      }
    } catch (error, stackTrace) {
      log.error('camera', 'the camera could not be flipped', error, stackTrace);
      if (!host.mounted) return;
      _showError(host.cameraErrorMessage);
    }
  }

  /// Takes a picture and opens it in the result screen.
  Future<void> capturePhoto() async {
    if (_capturing || !viewfinderActive) return;
    _capturing = true;
    _cameraErrorSet = false;
    host.notify();
    syncVolumeKeys();
    capture.reset();
    // The shot is confirmed with a short flash and a tap in the hand.
    host.flashCapture();
    unawaited(_haptic());
    // The time of the animation is read at the shutter, so the still shows the
    // same frame of the animation that the preview was showing.
    final time = animationTime;
    final contextSample = settings.contextLineEnabled
        ? contextSensors.sample(dateTime: DateTime.now())
        : Future<ExportContext?>.value();
    final previewSnapshot = ambient.snapshot(
      const Duration(milliseconds: 1500),
    );
    try {
      final still = await camera.captureStill(deferDecode: true);
      if (still == null) {
        throw StateError('The camera did not return a picture');
      }
      final transform = still.transform;
      final snapshot = previewSnapshot.forPhotoTurns(
        transform?.quarterTurns ?? 0,
        mirrorX: transform?.mirrorPreview ?? false,
      );
      capture.update(
        ambient: snapshot,
        takeMs: still.timings.takeMs,
        decodeMs: still.timings.decodeMs,
        animationTime: time,
      );

      final source = still.source;
      if (source != null) {
        final exportContext = await contextSample;
        if (!host.mounted) return;
        final quality = settings.exportQuality;
        await host.pushResult(
          CaptureResult.source(
            source: source,
            quality: quality,
            render: (image, maxSide) => styles.renderStill(
              image,
              ambient: snapshot,
              time: time,
              maxSide: maxSide,
            ),
            ambient: snapshot,
            time: time,
            context: exportContext,
            styleId: styles.style.id,
          ),
        );
        return;
      }

      final renderStart = DateTime.now().millisecondsSinceEpoch;
      final ui.Image rendered;
      try {
        rendered = await styles.renderStill(
          still.image,
          ambient: snapshot,
          time: time,
          maxSide: settings.exportQuality == ExportQuality.standard
              ? 2048
              : 4096,
        );
      } finally {
        // The picture of the camera belongs to the capture, not to the
        // renderer.
        still.image.dispose();
      }
      capture.update(
        renderMs: (DateTime.now().millisecondsSinceEpoch - renderStart)
            .toDouble(),
      );

      final exportContext = await contextSample;
      if (!host.mounted) {
        rendered.dispose();
        return;
      }
      await host.pushResult(
        CaptureResult(
          rendered: rendered,
          ambient: snapshot,
          context: exportContext,
          styleId: styles.style.id,
        ),
      );
    } catch (error, stackTrace) {
      log.error('capture', 'the capture failed', error, stackTrace);
      if (!host.mounted) return;
      _showError(host.cameraErrorMessage);
    } finally {
      if (host.mounted) {
        _capturing = false;
        host.notify();
        syncVolumeKeys();
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
      log.warning('capture', 'the haptic feedback did not work: $error');
    }
  }

  void _showError(String message) {
    _cameraErrorSet = true;
    _cameraError = message;
    host.notify();
    syncVolumeKeys();
  }
}
