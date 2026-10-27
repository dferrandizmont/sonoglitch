import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signal_intensity.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/harness.dart';

void main() {
  /// Scrolls the settings until the row with [text] is on the screen.
  ///
  /// The body of the screen is a list: the rows that are below the fold are
  /// only built when they are reached.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 150);
    await tester.pumpAndSettle();
  }

  /// The value that the switch of the row [title] shows on the screen.
  ///
  /// It reads the switch that is painted, not the stored setting, so a
  /// switch that does not rebuild after a tap is caught.
  bool visibleSwitchValue(WidgetTester tester, String title) {
    final toggle = find.descendant(
      of: find.widgetWithText(SwitchListTile, title),
      matching: find.byType(Switch),
    );
    expect(toggle, findsOneWidget, reason: 'the switch of "$title"');
    return tester.widget<Switch>(toggle).value;
  }

  test('context metadata is opt-in and only its toggle is persisted', () async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    expect(settings.contextLineEnabled, isFalse);
    await settings.setContextLineEnabled(true);
    final reloaded = AppSettings(store: store);
    await reloaded.load();
    expect(reloaded.contextLineEnabled, isTrue);
    await reloaded.setContextLineEnabled(false);
    expect(
      await store.getBool(AppSettings.contextLineKey, defaultValue: true),
      isFalse,
    );
  });

  testWidgets('context line switch reflects its value after each tap', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);
    await scrollTo(tester, 'Context line');
    expect(visibleSwitchValue(tester, 'Context line'), isFalse);
    await tester.tap(find.text('Context line'));
    await tester.pumpAndSettle();
    expect(visibleSwitchValue(tester, 'Context line'), isTrue);
    await tester.tap(find.text('Context line'));
    await tester.pumpAndSettle();
    expect(visibleSwitchValue(tester, 'Context line'), isFalse);
  });
  testWidgets(
    'dropdown fields and menus keep 48 dp targets at 320 dp and 1.3x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(store: InMemoryPreferencesStore());
      await settings.load();
      await pumpSettingsScreen(
        tester,
        settings,
        mediaQuery: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(1.3),
          disableAnimations: true,
        ),
      );
      for (final type in [
        DropdownButton<ExportQuality>,
        DropdownButton<SignalIntensity>,
        DropdownButton<ExportFileType>,
      ]) {
        final dropdown = find.byType(type);
        await tester.scrollUntilVisible(dropdown, 100);
        await tester.pumpAndSettle();
        expect(dropdown.hitTestable(), findsOneWidget);
        expect(tester.getSize(dropdown).height, 48);
        expect(tester.getSize(dropdown).width, greaterThanOrEqualTo(48));
        expect(
          find.ancestor(
            of: dropdown,
            matching: find.byType(DropdownButtonHideUnderline),
          ),
          findsOneWidget,
        );
        final field = tester.widget<Container>(
          find
              .ancestor(
                of: dropdown,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container &&
                      widget.foregroundDecoration is BoxDecoration,
                ),
              )
              .first,
        );
        final decoration = field.foregroundDecoration! as BoxDecoration;
        expect(
          decoration.borderRadius,
          BorderRadius.circular(AppTheme.radiusSm),
        );
        expect((decoration.border! as Border).top.color, AppTheme.edge);
        if (type == DropdownButton<ExportQuality>) {
          final widget = tester.widget<DropdownButton<ExportQuality>>(dropdown);
          expect(widget.dropdownColor, AppTheme.surfaceHigh);
          expect(widget.borderRadius, BorderRadius.circular(AppTheme.radiusSm));
          expect(widget.itemHeight, 48);
        }
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(0, 0));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Normal is default, all intensity values persist, invalid values fall back',
    () async {
      final store = InMemoryPreferencesStore();
      final settings = AppSettings(store: store);
      await settings.load();
      expect(settings.intensity, SignalIntensity.normal);
      for (final intensity in SignalIntensity.values) {
        await settings.setIntensity(intensity);
        final restored = AppSettings(store: store);
        await restored.load();
        expect(restored.intensity, intensity);
      }
      await store.setString(AppSettings.intensityKey, 'obsolete');
      await settings.load();
      expect(settings.intensity, SignalIntensity.normal);
    },
  );

  test('intensity persists through the SharedPreferences adapter', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(store: SharedPreferencesStore());
    await settings.load();
    await settings.setIntensity(SignalIntensity.extreme);
    final restored = AppSettings(store: SharedPreferencesStore());
    await restored.load();
    expect(restored.intensity, SignalIntensity.extreme);
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppSettings.intensityKey,
      ),
      'extreme',
    );
  });

  testWidgets('intensity selector changes the persisted setting', (
    tester,
  ) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);
    expect(find.text('Intensity'), findsOneWidget);
    expect(
      find.text(
        'How strongly noise and movement affect your photos. '
        'Light is not affected.',
      ),
      findsOneWidget,
      reason: 'the intensity only bends the noise and the movement',
    );
    await tester.tap(find.byType(DropdownButton<SignalIntensity>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extreme').last);
    await tester.pumpAndSettle();
    expect(settings.intensity, SignalIntensity.extreme);
    expect(await store.getString(AppSettings.intensityKey), 'extreme');
  });

  testWidgets('viewfinder applies loaded and changed intensity immediately', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await settings.setIntensity(SignalIntensity.subtle);
    final harness = await pumpViewfinder(tester, settings: settings);
    expect(harness.ambient.intensity, SignalIntensity.subtle);
    harness.noise.smoother.reset(0.25);
    harness.motion.magnitude.reset(0.25 / 0.8);
    harness.light.smoother.reset(0.4);
    await settings.setIntensity(SignalIntensity.extreme);
    expect(harness.ambient.value.noise, 0.575);
    expect(harness.ambient.value.motion, 0.575);
    expect(harness.ambient.value.light, 0.4);
    expect(
      harness.ambient.snapshot().noise,
      0.575,
      reason: 'old intensity history was dropped',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the watermark is on by default', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    expect(settings.watermarkEnabled, isTrue);

    await pumpSettingsScreen(tester, settings);
    expect(find.text('Watermark'), findsOneWidget);
  });

  testWidgets('the diagnostics are off by default', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    expect(settings.diagnosticsEnabled, isFalse);

    await pumpSettingsScreen(tester, settings);
    // The diagnostics live in the section of the troubleshooting.
    await scrollTo(tester, 'Diagnostics');
    expect(find.text('Diagnostics'), findsOneWidget);
  });

  testWidgets('the sections are Camera, Troubleshooting and About', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    // The first section is the one of the camera.
    expect(find.text('CAMERA'), findsOneWidget);
    expect(find.text('Photo quality'), findsOneWidget);
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('Watermark'), findsOneWidget);
    expect(find.text('Auto shot: keep waiting'), findsOneWidget);

    // The diagnostics and the report live in the section of the
    // troubleshooting, which is the one before the last.
    await scrollTo(tester, 'Diagnostics');
    expect(find.text('TROUBLESHOOTING'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);

    await scrollTo(tester, 'Export diagnostic report');
    expect(find.text('Export diagnostic report'), findsOneWidget);

    // The last section is the one about the app.
    await scrollTo(tester, 'ABOUT');
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('the body is a list, not a column inside a scroll view', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    expect(
      find.byType(ListView),
      findsOneWidget,
      reason: 'the rows below the fold are only built when they are needed',
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('the switches change the stored values', (tester) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Watermark'));
    await tester.pumpAndSettle();

    expect(settings.watermarkEnabled, isFalse);
    expect(
      await store.getBool(AppSettings.watermarkKey, defaultValue: true),
      isFalse,
    );

    await scrollTo(tester, 'Diagnostics');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(settings.diagnosticsEnabled, isTrue);
    expect(
      await store.getBool(AppSettings.diagnosticsKey, defaultValue: false),
      isTrue,
    );
  });

  testWidgets('the watermark switch shows the value that is stored', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    // The switch starts with the value that is stored.
    expect(visibleSwitchValue(tester, 'Watermark'), isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Watermark'));
    await tester.pumpAndSettle();

    // The switch that is on the screen is the one that was turned off.
    expect(visibleSwitchValue(tester, 'Watermark'), isFalse);
    expect(settings.watermarkEnabled, isFalse);

    // A second tap reverses it instead of sending the same value again.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Watermark'));
    await tester.pumpAndSettle();

    expect(visibleSwitchValue(tester, 'Watermark'), isTrue);
    expect(settings.watermarkEnabled, isTrue);
  });

  testWidgets('the auto shot switch shows the value that is stored', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    expect(visibleSwitchValue(tester, 'Auto shot: keep waiting'), isFalse);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Auto shot: keep waiting'),
    );
    await tester.pumpAndSettle();

    expect(visibleSwitchValue(tester, 'Auto shot: keep waiting'), isTrue);
    expect(settings.momentKeepArmed, isTrue);

    // A second tap reverses it instead of sending the same value again.
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Auto shot: keep waiting'),
    );
    await tester.pumpAndSettle();

    expect(visibleSwitchValue(tester, 'Auto shot: keep waiting'), isFalse);
    expect(settings.momentKeepArmed, isFalse);
  });

  testWidgets('the diagnostics switch shows the value that is stored', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await scrollTo(tester, 'Diagnostics');
    expect(visibleSwitchValue(tester, 'Diagnostics'), isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(visibleSwitchValue(tester, 'Diagnostics'), isTrue);
    expect(settings.diagnosticsEnabled, isTrue);

    // A second tap reverses it instead of sending the same value again.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(visibleSwitchValue(tester, 'Diagnostics'), isFalse);
    expect(settings.diagnosticsEnabled, isFalse);
  });

  testWidgets('the selectors show the value that is stored', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    // The three selectors of the camera section listen to the settings, so
    // the value that is shown is the value that is stored.
    expect(
      tester
          .widget<DropdownButton<ExportQuality>>(
            find.byType(DropdownButton<ExportQuality>),
          )
          .value,
      ExportQuality.high,
    );
    expect(
      tester
          .widget<DropdownButton<SignalIntensity>>(
            find.byType(DropdownButton<SignalIntensity>),
          )
          .value,
      SignalIntensity.normal,
    );

    await tester.tap(find.byType(DropdownButton<ExportQuality>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maximum').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<ExportQuality>>(
            find.byType(DropdownButton<ExportQuality>),
          )
          .value,
      ExportQuality.maximum,
    );
    expect(settings.exportQuality, ExportQuality.maximum);

    await tester.tap(find.byType(DropdownButton<SignalIntensity>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subtle').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<SignalIntensity>>(
            find.byType(DropdownButton<SignalIntensity>),
          )
          .value,
      SignalIntensity.subtle,
    );
    expect(settings.intensity, SignalIntensity.subtle);

    // The file type is the last selector of the camera section.
    await tester.scrollUntilVisible(find.text('File type'), 200);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<ExportFileType>>(
            find.byType(DropdownButton<ExportFileType>),
          )
          .value,
      ExportFileType.png,
    );

    await tester.tap(find.byType(DropdownButton<ExportFileType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPEG (high quality)').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<ExportFileType>>(
            find.byType(DropdownButton<ExportFileType>),
          )
          .value,
      ExportFileType.jpeg,
    );
    expect(settings.fileType, ExportFileType.jpeg);
  });

  testWidgets('the stored values are read back', (tester) async {
    final store = InMemoryPreferencesStore({
      AppSettings.watermarkKey: false,
      AppSettings.diagnosticsKey: true,
    });
    final settings = AppSettings(store: store);
    await settings.load();

    expect(settings.watermarkEnabled, isFalse);
    expect(settings.diagnosticsEnabled, isTrue);

    await pumpSettingsScreen(tester, settings);
  });

  testWidgets('shows the version and the licence', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await tester.scrollUntilVisible(find.text('Privacy'), 150);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.textContaining('Version'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
  });

  testWidgets('the donation row is hidden without a link', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await scrollTo(tester, 'Privacy');
    expect(find.text('Support the project'), findsNothing);
  });

  testWidgets('the donation row opens an https link outside the app', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    final opened = <Uri>[];
    await pumpSettingsScreen(
      tester,
      settings,
      donationUrl: 'https://ko-fi.com/example',
      openLink: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await tester.scrollUntilVisible(find.text('Support the project'), 150);
    await tester.tap(find.text('Support the project'));
    await tester.pump();

    expect(opened, [Uri.parse('https://ko-fi.com/example')]);
  });

  testWidgets('the donation row ignores a link that is not https', (
    tester,
  ) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    var opened = 0;
    await pumpSettingsScreen(
      tester,
      settings,
      donationUrl: 'http://example.com',
      openLink: (uri) async {
        opened++;
        return true;
      },
    );

    await tester.scrollUntilVisible(find.text('Support the project'), 150);
    await tester.tap(find.text('Support the project'));
    await tester.pump();

    expect(opened, 0);
  });

  testWidgets('the watermark switch is remembered', (tester) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Watermark'));
    await tester.pumpAndSettle();
    expect(settings.watermarkEnabled, isFalse);

    // The value is read back by another instance, the way the app does it
    // when it starts.
    final read = AppSettings(store: store);
    await read.load();
    expect(read.watermarkEnabled, isFalse);
  });

  testWidgets('the diagnostics switch is remembered', (tester) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await scrollTo(tester, 'Diagnostics');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Diagnostics'));
    await tester.pumpAndSettle();
    expect(settings.diagnosticsEnabled, isTrue);

    final read = AppSettings(store: store);
    await read.load();
    expect(read.diagnosticsEnabled, isTrue);
  });

  testWidgets('the moment mode stops after one photo by default', (
    tester,
  ) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();

    expect(settings.momentKeepArmed, isFalse);

    await pumpSettingsScreen(tester, settings);
    expect(find.text('Auto shot: keep waiting'), findsOneWidget);
  });

  testWidgets('the keep armed switch is remembered', (tester) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Auto shot: keep waiting'),
    );
    await tester.pumpAndSettle();

    expect(settings.momentKeepArmed, isTrue);
    expect(
      await store.getBool(AppSettings.momentKeepArmedKey, defaultValue: false),
      isTrue,
    );

    // The value is read back by another instance, the way the app does it
    // when it starts.
    final read = AppSettings(store: store);
    await read.load();
    expect(read.momentKeepArmed, isTrue);
  });
  test(
    'High is the default, all three quality values survive reload',
    () async {
      final store = InMemoryPreferencesStore();
      final settings = AppSettings(store: store);
      await settings.load();
      expect(settings.exportQuality, ExportQuality.high);
      for (final quality in ExportQuality.values) {
        await settings.setExportQuality(quality);
        final restored = AppSettings(store: store);
        await restored.load();
        expect(restored.exportQuality, quality);
      }
      await store.setString(AppSettings.exportQualityKey, 'obsolete-value');
      await settings.load();
      expect(settings.exportQuality, ExportQuality.high);
    },
  );

  test('quality persists through the real SharedPreferences adapter', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(store: SharedPreferencesStore());
    await settings.load();
    await settings.setExportQuality(ExportQuality.maximum);
    final restored = AppSettings(store: SharedPreferencesStore());
    await restored.load();
    expect(restored.exportQuality, ExportQuality.maximum);
  });

  testWidgets('quality can be chosen in Settings', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await pumpSettingsScreen(tester, settings);
    await tester.tap(find.byType(DropdownButton<ExportQuality>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maximum').last);
    await tester.pumpAndSettle();
    expect(settings.exportQuality, ExportQuality.maximum);
  });

  test('PNG is the default file type, every type survives a reload', () async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    expect(settings.fileType, ExportFileType.png);
    for (final type in ExportFileType.values) {
      await settings.setFileType(type);
      final restored = AppSettings(store: store);
      await restored.load();
      expect(restored.fileType, type);
    }
    await store.setString(AppSettings.fileTypeKey, 'obsolete-value');
    await settings.load();
    expect(settings.fileType, ExportFileType.png);
  });

  test(
    'the full layout is the default, every layout survives a reload',
    () async {
      final store = InMemoryPreferencesStore();
      final settings = AppSettings(store: store);
      await settings.load();
      expect(settings.exportLayout, ExportLayout.full);
      for (final layout in ExportLayout.values) {
        await settings.setExportLayout(layout);
        final restored = AppSettings(store: store);
        await restored.load();
        expect(restored.exportLayout, layout);
      }
      await store.setString(AppSettings.exportLayoutKey, 'obsolete-value');
      await settings.load();
      expect(settings.exportLayout, ExportLayout.full);
    },
  );

  test('the readings mode defaults to full and survives a reload', () async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    expect(settings.exportReadingsMode, ExportReadingsMode.full);
    for (final mode in ExportReadingsMode.values) {
      await settings.setExportReadingsMode(mode);
      final restored = AppSettings(store: store);
      await restored.load();
      expect(restored.exportReadingsMode, mode);
    }
    await store.setString(AppSettings.exportReadingsModeKey, 'obsolete-value');
    await settings.load();
    expect(settings.exportReadingsMode, ExportReadingsMode.full);
  });

  testWidgets('the file type can be chosen in Settings', (tester) async {
    final store = InMemoryPreferencesStore();
    final settings = AppSettings(store: store);
    await settings.load();
    await pumpSettingsScreen(tester, settings);
    await tester.scrollUntilVisible(find.text('File type'), 200);
    expect(find.text('File type'), findsOneWidget);
    await tester.ensureVisible(find.byType(DropdownButton<ExportFileType>));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<ExportFileType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPEG (high quality)').last);
    await tester.pumpAndSettle();

    expect(settings.fileType, ExportFileType.jpeg);
    expect(await store.getString(AppSettings.fileTypeKey), 'jpeg');
  });
}
