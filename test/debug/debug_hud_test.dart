import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/debug/debug_hud.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_exporter.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';

void main() {
  late AmbientController ambient;
  late CameraMetrics metrics;
  late DebugLog log;

  setUp(() {
    ambient = AmbientController(
      noise: NoiseService(),
      light: LightService(),
      motion: MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
      ),
    );
    metrics = CameraMetrics();
    log = DebugLog();
  });
  tearDown(() {
    ambient.dispose();
    metrics.dispose();
  });

  Widget hud() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DebugHud(
        ambient: ambient,
        metrics: metrics,
        styleId: 'static',
        timings: const CaptureTimings(),
        device: const DeviceSummary(
          model: 'test',
          systemVersion: 'test',
          platform: 'test',
        ),
        log: log,
        exporter: DiagnosticExporter(log: log),
      ),
    ),
  );
  Text readout(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining('stream '));
  void measure() {
    metrics.recordFrame(
      conversionTime: const Duration(milliseconds: 2),
      streamWidth: 640,
      streamHeight: 480,
      previewWidth: 270,
      previewHeight: 360,
    );
    metrics.recordDroppedFrame();
    ambient.tick();
  }

  testWidgets('HUD coalesces text at 4 Hz without dropping measurements', (
    tester,
  ) async {
    var cameraNotifications = 0;
    var ambientNotifications = 0;
    metrics.addListener(() => cameraNotifications++);
    ambient.addListener(() => ambientNotifications++);
    await tester.pumpWidget(hud());
    final initial = readout(tester);
    for (var i = 0; i < 100; i++) {
      measure();
      await tester.pump(const Duration(milliseconds: 2));
    }
    expect(identical(readout(tester), initial), isTrue);
    expect(metrics.value.frames, 100);
    expect(metrics.value.droppedFrames, 100);
    expect(cameraNotifications, 200);
    expect(ambientNotifications, 100);
    await tester.pump(const Duration(milliseconds: 50));
    expect(readout(tester).data, contains('drop 100'));
    final presented = readout(tester);
    for (var i = 0; i < 100; i++) {
      measure();
    }
    await tester.pump(const Duration(milliseconds: 249));
    expect(identical(readout(tester), presented), isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(readout(tester).data, contains('drop 200'));
    expect(metrics.value.frames, 200);
    expect(metrics.value.droppedFrames, 200);
    expect(cameraNotifications, 400);
    expect(ambientNotifications, 200);
    final settled = readout(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(identical(readout(tester), settled), isTrue);
  });

  testWidgets('sensor and camera ticks do not rebuild manual sliders', (
    tester,
  ) async {
    ambient.setManual(true);
    await tester.pumpWidget(hud());
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(3));
    for (var i = 0; i < 100; i++) {
      measure();
    }
    await tester.pump(const Duration(milliseconds: 250));
    final after = tester.widgetList<Slider>(find.byType(Slider)).toList();
    for (var i = 0; i < 3; i++) {
      expect(identical(after[i], sliders[i]), isTrue);
    }
    ambient.setManualValues(noise: 0.7);
    await tester.pump();
    expect(tester.widgetList<Slider>(find.byType(Slider)).first.value, 0.7);
    // Drag the thumb while a presentation update is pending. Controls must
    // react without waiting for the 250 ms text update.
    measure();
    final slider = find.byType(Slider).first;
    final bounds = tester.getRect(slider);
    final gesture = await tester.startGesture(
      Offset(bounds.left + 10 + (bounds.width - 20) * 0.7, bounds.center.dy),
    );
    await gesture.moveBy(Offset(-bounds.width * 0.3, 0));
    await tester.pump();
    final dragged = tester.widget<Slider>(slider).value;
    expect(dragged, lessThan(0.7));
    expect(dragged, closeTo(0.4, 0.1));
    expect(ambient.manualNoise, dragged);
    expect(ambient.value.noise, dragged);
    await gesture.up();
    ambient.setManual(false);
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacing sources detaches old listeners and disposal cancels pending text',
    (tester) async {
      await tester.pumpWidget(hud());
      final oldMetrics = metrics;
      final oldAmbient = ambient;
      metrics = CameraMetrics();
      ambient = AmbientController(
        noise: NoiseService(),
        light: LightService(),
        motion: MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
        ),
      );
      await tester.pumpWidget(hud());
      await tester.pump(const Duration(milliseconds: 250));
      final presented = readout(tester);
      oldMetrics.recordDroppedFrame();
      oldAmbient.tick();
      await tester.pump(const Duration(milliseconds: 300));
      expect(identical(readout(tester), presented), isTrue);
      measure();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      oldMetrics.dispose();
      oldAmbient.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
