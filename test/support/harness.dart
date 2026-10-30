import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/clock.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/app_config.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/volume_keys.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_exporter.dart';
import 'package:sonoglitch/effects/animation_clock.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/settings/settings_screen.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import 'fakes.dart';

/// The pieces of the viewfinder a test can drive.
class ViewfinderHarness {
  ViewfinderHarness({
    required this.camera,
    required this.ambient,
    required this.noise,
    required this.motion,
    required this.light,
    required this.styles,
    required this.settings,
    required this.capture,
    required this.export,
    required this.log,
    required this.directory,
  });

  /// The camera of the screen.
  final CameraService camera;

  /// The fake camera of the screen.
  ///
  /// It is only the camera of the screen when the test did not bring its
  /// own.
  FakeCameraService get fakeCamera => camera as FakeCameraService;

  /// The ambient controller of the screen.
  final AmbientController ambient;

  /// The microphone of the ambient controller.
  final NoiseService noise;

  /// The accelerometer of the ambient controller.
  final MotionService motion;

  /// The light sensor of the ambient controller.
  final LightService light;

  /// The styles of the screen.
  final StyleController styles;

  /// The switches of the screen.
  final AppSettings settings;

  /// The timings of the last capture.
  final CaptureMetrics capture;

  /// The export service of the screen.
  final FakeExportService export;

  /// The logger of the screen.
  final DebugLog log;

  /// Where the fake export service writes its files.
  final Directory directory;

  /// The result of the last capture that was pushed as a route.
  CaptureResult? result;
}

/// Builds the viewfinder with the routes of the app.
///
/// The routes are simple pages, so a test can watch what the screen pushes
/// without building the whole application.
///
/// [diagnostics] turns the on screen panel on before the screen is built.
/// [camera] replaces the fake camera, so a test can drive a camera that
/// counts the frames it converts.
/// [settings] replaces the switches, so a test can start with the values
/// that another screen left behind.
/// [ambientClock] replaces the clock of the ambient pipeline, so a test can
/// move the time of the samples without waiting for it.
Future<ViewfinderHarness> pumpViewfinder(
  WidgetTester tester, {
  StyleController? styles,
  bool diagnostics = false,
  CameraService? camera,
  AppSettings? settings,
  AnimationClock? animationClock,
  VolumeKeys volumeKeys = const NoopVolumeKeys(),
  SpectrumService? spectrum,
  Locale? locale,
  Clock? ambientClock,
  MediaQueryData? mediaQuery,
  ContextSensors contextSensors = const ContextSensors(),
}) async {
  final log = DebugLog();
  final noise = NoiseService(decibelStream: const Stream<double>.empty());
  final motion = MotionService(
    samples: const Stream<AccelSample>.empty(),
    gyroSamples: const Stream<AccelSample>.empty(),
    gravitySamples: const Stream<AccelSample>.empty(),
  );
  final light = LightService(ambientLight: FakeAmbientLightSource());
  final ambient = AmbientController(
    spectrum: spectrum ?? SpectrumService(source: const NoopSpectrumSource()),
    noise: noise,
    motion: motion,
    light: light,
    signals: buildTestSignals(motion: motion, clock: ambientClock),
    clock: ambientClock ?? stopwatchClock,
  );
  final service = camera ?? FakeCameraService(light: light, log: log);
  final controller = styles ?? StyleController(log: log);
  final appSettings =
      settings ?? AppSettings(store: InMemoryPreferencesStore());
  await appSettings.load();
  if (settings == null || diagnostics) {
    await appSettings.setDiagnosticsEnabled(diagnostics);
  }
  final capture = CaptureMetrics();
  // The directory is made synchronously: the real file system does not work
  // inside the fake clock of a widget test.
  final directory = Directory.systemTemp.createTempSync('sonoglitch_test');
  final export = FakeExportService(log: log, directory: directory);
  final clock = animationClock ?? StopwatchAnimationClock();
  final harness = ViewfinderHarness(
    camera: service,
    ambient: ambient,
    noise: noise,
    motion: motion,
    light: light,
    styles: controller,
    settings: appSettings,
    capture: capture,
    export: export,
    log: log,
    directory: directory,
  );
  addTearDown(() async {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(data: mediaQuery, child: child!),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (routeSettings) {
        final arguments = routeSettings.arguments;
        if (arguments is CaptureResult) harness.result = arguments;
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => const Scaffold(body: Center(child: Text('route'))),
        );
      },
      home: ViewfinderScreen(
        camera: service,
        ambient: ambient,
        styles: controller,
        settings: appSettings,
        export: export,
        log: log,
        exporter: DiagnosticExporter(log: log),
        device: const DeviceSummary(
          model: 'test',
          systemVersion: 'test',
          platform: 'test',
        ),
        capture: capture,
        animationClock: clock,
        volumeKeys: volumeKeys,
        contextSensors: contextSensors,
      ),
    ),
  );
  await tester.pump();
  return harness;
}

/// Builds the settings screen.
///
/// The screen reads the values of the switches and the measurements of the
/// ambient, so a test can drive them.
Future<void> pumpSettingsScreen(
  WidgetTester tester,
  AppSettings settings, {
  AmbientController? ambient,
  ValueListenable<CameraMetricsData>? metrics,
  String donationUrl = '',
  Future<bool> Function(Uri uri)? openLink,
  MediaQueryData? mediaQuery,
  bool screenshotMode = AppConfig.screenshotMode,
  String? screenshotPhotoSourceStatus,
}) async {
  final log = DebugLog();
  final controller =
      ambient ??
      AmbientController(
        noise: NoiseService(decibelStream: const Stream<double>.empty()),
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
        ),
        light: LightService(ambientLight: FakeAmbientLightSource()),
        spectrum: SpectrumService(source: const NoopSpectrumSource()),
        screenshotMode: screenshotMode,
      );
  if (ambient == null) addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(data: mediaQuery, child: child!),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(
        settings: settings,
        donationUrl: donationUrl,
        openLink: openLink ?? (_) async => true,
        log: log,
        exporter: DiagnosticExporter(log: log),
        ambient: controller,
        screenshotMode: screenshotMode,
        screenshotPhotoSourceStatus: screenshotPhotoSourceStatus,
        metrics:
            metrics ??
            ValueNotifier<CameraMetricsData>(const CameraMetricsData()),
        capture: CaptureMetrics(),
        styleId: 'static',
        device: const DeviceSummary(
          model: 'test',
          systemVersion: 'test',
          platform: 'test',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
