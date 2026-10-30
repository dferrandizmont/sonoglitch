import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ambient/ambient_controller.dart';
import 'ambient/light_service.dart';
import 'ambient/motion_service.dart';
import 'ambient/noise_service.dart';
import 'app_config.dart';
import 'camera/camera_service.dart';
import 'camera/screenshot_photo_source.dart';
import 'debug/capture_metrics.dart';
import 'debug/debug_log.dart';
import 'debug/device_summary.dart';
import 'debug/diagnostic_exporter.dart';
import 'export/export_service.dart';
import 'export/temporary_files.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/permission_gateway.dart';
import 'features/result/capture_result.dart';
import 'features/result/result_screen.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/preferences_store.dart';
import 'features/settings/settings_screen.dart';
import 'features/styles/style_controller.dart';
import 'features/styles/styles_screen.dart';
import 'features/viewfinder/viewfinder_screen.dart';
import 'l10n/app_localizations.dart';
import 'routes.dart';
import 'theme/app_theme.dart';

/// Starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is a portrait camera: the rotation of the frames and the crop of
  // the export are built around it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final log = DebugLog();
  await log.init();
  _installErrorHooks(log);
  log.info('app', 'started version ${AppConfig.appVersion}');

  // The working pictures and the reports that were left in the cache are
  // removed when they are old.
  await removeStaleTemporaryFiles();

  final settings = AppSettings(store: SharedPreferencesStore());
  await settings.load();

  final light = LightService();
  final noise = NoiseService(enabled: false);
  final ambient = AmbientController(
    noise: noise,
    motion: MotionService(),
    light: light,
  );
  ScreenshotPhotoSource? photoSource;
  if (AppConfig.screenshotMode) {
    photoSource = await ScreenshotPhotoSource.find();
  }
  final camera = CameraService(
    light: light,
    log: log,
    deviceFactory: photoSource?.deviceFactory,
    lister: photoSource?.lister,
    preserveSourceOrientation: photoSource?.active ?? false,
  );
  final styles = StyleController(log: log);
  final export = ExportService(log: log);
  final exporter = DiagnosticExporter(log: log);
  final device = await DeviceSummary.load();

  runApp(
    SonoglitchApp(
      log: log,
      settings: settings,
      permissions: const PermissionHandlerGateway(),
      ambient: ambient,
      camera: camera,
      styles: styles,
      export: export,
      exporter: exporter,
      device: device,
      capture: CaptureMetrics(),
      noise: noise,
      screenshotPhotoSourceStatus: photoSource?.status,
    ),
  );
}

/// Sends the errors of the framework and of the platform to the log file.
void _installErrorHooks(DebugLog log) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    log.error(
      'flutter',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.error('platform', 'unhandled error', error, stackTrace);
    return true;
  };
}

/// The application.
class SonoglitchApp extends StatelessWidget {
  const SonoglitchApp({
    super.key,
    required this.log,
    required this.settings,
    required this.permissions,
    required this.ambient,
    required this.camera,
    required this.styles,
    required this.export,
    required this.exporter,
    required this.device,
    required this.capture,
    required this.noise,
    this.screenshotPhotoSourceStatus,
  });

  final DebugLog log;
  final AppSettings settings;
  final PermissionGateway permissions;
  final AmbientController ambient;
  final CameraService camera;
  final StyleController styles;
  final ExportService export;
  final DiagnosticExporter exporter;
  final DeviceSummary device;
  final CaptureMetrics capture;

  final String? screenshotPhotoSourceStatus;

  /// The noise source, switched on when the microphone is granted.
  final NoiseService noise;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: Routes.home,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => OnboardingScreen(
            permissions: permissions,
            onContinue: (microphoneGranted) {
              // Without the microphone the noise stays at zero and the
              // microphone is never touched.
              noise.enabled = microphoneGranted;
              Navigator.of(context).pushReplacementNamed(Routes.viewfinder);
            },
          ),
        );
      case Routes.viewfinder:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => ViewfinderScreen(
            camera: camera,
            ambient: ambient,
            styles: styles,
            settings: this.settings,
            export: export,
            log: log,
            exporter: exporter,
            device: device,
            capture: capture,
          ),
        );
      case Routes.result:
        final result = settings.arguments as CaptureResult;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => ResultScreen(
            result: result,
            export: export,
            settings: this.settings,
            log: log,
            capture: capture,
          ),
        );
      case Routes.styles:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => StylesScreen(styles: styles),
        );
      case Routes.settings:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => SettingsScreen(
            settings: this.settings,
            log: log,
            exporter: exporter,
            ambient: ambient,
            metrics: camera.metrics,
            capture: capture,
            styleId: styles.style.id,
            device: device,
            screenshotPhotoSourceStatus: screenshotPhotoSourceStatus,
          ),
        );
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) =>
              const Scaffold(body: Center(child: Icon(Icons.error_outline))),
        );
    }
  }
}
