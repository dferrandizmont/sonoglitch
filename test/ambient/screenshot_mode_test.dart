import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/screenshot_values.dart';
import 'package:sonoglitch/ambient/signature/capture_identity.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/app_config.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_readings.dart';

import '../support/fakes.dart';

void main() {
  AmbientController controller({
    bool screenshotMode = AppConfig.screenshotMode,
  }) {
    final motion = MotionService(
      samples: const Stream<AccelSample>.empty(),
      gyroSamples: const Stream<AccelSample>.empty(),
      gravitySamples: const Stream<AccelSample>.empty(),
    );
    final result = AmbientController(
      noise: NoiseService(decibelStream: const Stream<double>.empty()),
      motion: motion,
      light: LightService(ambientLight: FakeAmbientLightSource()),
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      signals: buildTestSignals(motion: motion, clock: () => 0),
      clock: () => 0,
      screenshotMode: screenshotMode,
    );
    addTearDown(result.dispose);
    return result;
  }

  test('normal builds reject demo values and keep manual readings absent', () {
    expect(AppConfig.screenshotMode, isFalse);
    final ambient = controller();
    ambient.setScreenshotValues(ScreenshotValues.intense);
    ambient.setDemoValues(true);
    expect(ambient.isManual, isFalse);
    expect(ambient.demoValuesEnabled, isFalse);
    ambient.setManual(true);
    ambient.setManualValues(noise: 0.8);
    final snapshot = ambient.snapshot();
    expect(snapshot.noise, 0.8);
    expect(snapshot.rawDb, isNull);
    expect(snapshot.rawLux, isNull);
    expect(snapshot.rawAccel, isNull);
    expect(snapshot.bass, 0);
    expect(snapshot.mid, 0);
    expect(snapshot.treble, 0);
    final values = ExportLayoutValues.fromAmbient(
      snapshot,
      styleName: 'Static',
    );
    expect(readingsOf(values), isEmpty);
    expect(values.spectrumAvailable, isFalse);
  });

  test('demo snapshots freeze readings, neutral lanes and a new photo ID', () {
    final ambient = controller(screenshotMode: true);
    ambient.setDemoValues(true);
    for (final preset in [
      ScreenshotValues.calm,
      ScreenshotValues.lively,
      ScreenshotValues.intense,
    ]) {
      ambient.setScreenshotValues(preset);
      // Settings pauses the pipeline. Resuming must retain the demo state.
      ambient.stop();
      ambient.start();
      ambient.stop();
      final snapshot = ambient.snapshot();
      expect(ambient.isManual, isTrue);
      expect(snapshot.noise, preset.noise);
      expect(snapshot.light, preset.light);
      expect(snapshot.motion, preset.motion);
      expect(snapshot.rawDb, preset.db);
      expect(snapshot.rawLux, preset.lux);
      expect(snapshot.rawAccel, preset.accel);
      expect(snapshot.bass, preset.bass);
      expect(snapshot.mid, preset.mid);
      expect(snapshot.treble, preset.treble);
      expect(snapshot.signature.tilt, 0);
      expect(snapshot.signature.pulse, 0);
      expect(snapshot.signature.warmth, 0);
      expect(snapshot.signature.hue, 0);
      expect(snapshot.signature.chromaAllowance, 1);
      expect(snapshot.signature.axisX, 1);
      expect(snapshot.signature.axisY, 0);
      expect(snapshot.identity, isNotNull);
      final second = ambient.snapshot();
      expect(second.identity!.displayId, isNot(snapshot.identity!.displayId));
      final values = ExportLayoutValues.fromAmbient(
        snapshot,
        styleName: 'Static',
        photoId: snapshot.identity!.displayId,
      );
      expect(readingsOf(values).map((r) => r.label), ['dB', 'lx', 'm/s²']);
      expect(readingsOf(values).map((r) => r.value), [
        '${preset.db.round()}',
        '${preset.lux.round()}',
        preset.accel.toStringAsFixed(2),
      ]);
      expect(values.photoId, isNotEmpty);
      expect(values.spectrumAvailable, isTrue);
      expect(showsExportSpectrum(values), isTrue);
      ambient.setScreenshotValues(preset.copyWith(db: 99, bass: 0.01));
      expect(snapshot.rawDb, preset.db);
      expect(snapshot.bass, preset.bass);
    }
    ambient.setDemoValues(false);
    expect(ambient.isManual, isFalse);
    expect(ambient.demoValuesEnabled, isFalse);
    ambient.noise.addReading(45);
    ambient.tick();
    expect(ambient.snapshot().rawDb, 45);
    expect(ambient.snapshot().noise, ambient.noise.level);
    // Turning ordinary manual mode on later must not reuse demo readings.
    ambient.setManual(true);
    expect(ambient.snapshot().rawDb, isNull);
    expect(controller(screenshotMode: true).demoValuesEnabled, isFalse);
  });
}
