import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_exporter.dart';
import 'package:sonoglitch/export/export_service.dart';
import 'package:sonoglitch/features/onboarding/permission_gateway.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/main.dart';

import 'support/fakes.dart';

/// A permission gateway that says no to everything.
class RefusingPermissionGateway implements PermissionGateway {
  @override
  Future<bool> isGranted(AppPermission permission) async => false;

  @override
  Future<PermissionResult> request(AppPermission permission) async =>
      PermissionResult(
        permission: permission,
        granted: false,
        permanentlyDenied: false,
      );

  @override
  Future<bool> openSettings() async => false;
}

void main() {
  testWidgets('the app starts on the onboarding', (tester) async {
    final log = DebugLog();
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    final light = LightService(ambientLight: FakeAmbientLightSource());

    await tester.pumpWidget(
      SonoglitchApp(
        log: log,
        settings: settings,
        permissions: RefusingPermissionGateway(),
        ambient: AmbientController(
          spectrum: SpectrumService(source: const NoopSpectrumSource()),
          noise: NoiseService(),
          motion: MotionService(),
          light: light,
        ),
        camera: CameraService(light: light, log: log),
        styles: StyleController(log: log),
        export: ExportService(log: log),
        exporter: DiagnosticExporter(log: log),
        device: const DeviceSummary(
          model: 'test',
          systemVersion: 'test',
          platform: 'test',
        ),
        capture: CaptureMetrics(),
        noise: NoiseService(enabled: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('A camera that lets'), findsOneWidget);
    expect(find.textContaining('never recorded'), findsOneWidget);
  });
}
