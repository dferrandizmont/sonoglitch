import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/camera/screenshot_photo_source.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_readings.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/settings/screenshot_section.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  testWidgets('the default build has no screenshot section', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);
    await tester.scrollUntilVisible(find.text('Privacy'), 150);
    expect(find.byType(ScreenshotSection), findsNothing);
    expect(find.text('Screenshot mode'), findsNothing);
    expect(find.text('Demo values'), findsNothing);
    expect(find.textContaining('Photo source'), findsNothing);
  });

  for (final active in [false, true]) {
    testWidgets(
      'screenshot settings show photo source active=$active and path',
      (tester) async {
        final settings = AppSettings(store: InMemoryPreferencesStore());
        await settings.load();
        final status =
            'Photo source ${active ? 'active' : 'inactive'}; '
            '${ScreenshotPhotoSource.androidAdbPath}';
        await pumpSettingsScreen(
          tester,
          settings,
          screenshotMode: true,
          screenshotPhotoSourceStatus: status,
        );
        await tester.scrollUntilVisible(find.text(status), 200);
        expect(find.text(status), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('demo values survive Settings and capture until switched off', (
    tester,
  ) async {
    final motion = MotionService(
      samples: const Stream<AccelSample>.empty(),
      gyroSamples: const Stream<AccelSample>.empty(),
      gravitySamples: const Stream<AccelSample>.empty(),
    );
    final ambient = AmbientController(
      noise: NoiseService(decibelStream: const Stream<double>.empty()),
      motion: motion,
      light: LightService(ambientLight: FakeAmbientLightSource()),
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      signals: buildTestSignals(motion: motion, clock: () => 0),
      clock: () => 0,
      screenshotMode: true,
    );
    addTearDown(ambient.dispose);
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    Future<void> openSettings() async {
      await pumpSettingsScreen(
        tester,
        settings,
        ambient: ambient,
        screenshotMode: true,
      );
      await tester.scrollUntilVisible(find.text('Demo values'), 150);
      await tester.pumpAndSettle();
    }

    await openSettings();
    expect(find.text('Screenshot mode'), findsOneWidget);
    expect(find.text('Screenshot mode (not for stores)'), findsOneWidget);
    await tester.tap(find.text('Demo values'));
    await tester.pumpAndSettle();
    expect(ambient.isManual, isTrue);
    expect(ambient.value.noise, 0.60);
    expect(ambient.value.light, 0.60);
    expect(ambient.value.motion, 0.35);
    final snapshot = ambient.snapshot();
    expect(snapshot.rawDb, 66);
    expect(snapshot.rawLux, 340);
    expect(snapshot.rawAccel, 0.28);
    expect(snapshot.bass, 0.70);
    expect(snapshot.mid, 0.55);
    expect(snapshot.treble, 0.35);
    final exported = ExportLayoutValues.fromAmbient(
      snapshot,
      styleName: 'Static',
    );
    expect(readingsOf(exported), hasLength(3));
    expect(exported.spectrumAvailable, isTrue);

    await tester.ensureVisible(find.text('Intense'));
    await tester.tap(find.text('Intense'));
    await tester.pumpAndSettle();
    expect(ambient.value.noise, 0.90);
    expect(ambient.value.rawDb, 82);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('screenshot-Noise')))
          .value,
      0.90,
    );
    await tester.tap(find.text('Calm'));
    await tester.pumpAndSettle();
    expect(ambient.value.noise, 0.25);
    expect(ambient.value.rawLux, 220);

    // Every slider writes its own independent lane, including raw numbers
    // and spectrum. Use deterministic callbacks rather than timed gestures.
    for (final (label, value) in [
      ('Noise', 0.77),
      ('Light', 0.44),
      ('Motion', 0.33),
      ('Sound dB', 73.0),
      ('Light lx', 1234.0),
      ('Motion m/s²', 1.23),
      ('Bass', 0.8),
      ('Mid', 0.6),
      ('Treble', 0.4),
    ]) {
      final slider = find.byKey(ValueKey('screenshot-$label'));
      await tester.scrollUntilVisible(slider, 100);
      tester.widget<Slider>(slider).onChanged!(value);
      await tester.pump();
    }
    expect(ambient.screenshotValues.preset, 'Custom');
    expect(ambient.value.noise, 0.77);
    expect(ambient.value.light, 0.44);
    expect(ambient.value.motion, 0.33);
    expect(ambient.value.rawDb, 73);
    expect(ambient.value.rawLux, 1234);
    expect(ambient.value.rawAccel, 1.23);
    expect(ambient.value.bass, 0.8);
    expect(ambient.value.mid, 0.6);
    expect(ambient.value.treble, 0.4);

    // Destroy the Settings route; the shared controller owns the values.
    await tester.pumpWidget(const SizedBox.shrink());
    ambient.tick();
    expect(ambient.snapshot().rawDb, 73);
    await openSettings();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Demo values'),
          )
          .value,
      isTrue,
    );
    expect(ambient.screenshotValues.preset, 'Custom');
    await tester.tap(find.text('Demo values'));
    await tester.pumpAndSettle();
    expect(ambient.isManual, isFalse);
    expect(ambient.value.rawDb, isNull);
    expect(ambient.snapshot().noise, 0);
    expect(ambient.demoValuesEnabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
