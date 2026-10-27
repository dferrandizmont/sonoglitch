import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';
import 'package:sonoglitch/app_config.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  testWidgets(
    'diagnostics show the spectrum as plain numbers and never the seed',
    (tester) async {
      final harness = await pumpViewfinder(tester, diagnostics: true);
      // Keep this synthetic formatting sample stable until the HUD deadline.
      harness.ambient.stop();
      harness.ambient.value = const AmbientState(
        bass: 0.1,
        mid: 0.2,
        treble: 0.3,
        seed: 0.4,
      );
      await tester.pump();
      // Diagnostic presentation is coalesced at 4 Hz.
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.textContaining('bass 0.100  mid 0.200  treble 0.300'),
        findsOneWidget,
      );
      // The capture signature is never shown in diagnostics.
      expect(find.textContaining('seed'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('the style rail opens the sheet and a tile updates the panel', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester, diagnostics: true);

    expect(harness.styles.style.id, kStyles.first.id);
    expect(find.textContaining('style ${kStyles.first.id}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();
    // Diagnostic presentation is coalesced at 4 Hz.
    await tester.pump(const Duration(milliseconds: 250));

    expect(harness.styles.style.id, kStyles[1].id);
    expect(find.textContaining('style ${kStyles[1].id}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selecting a style updates the rail and the panel', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester, diagnostics: true);

    expect(find.textContaining('style ${kStyles.first.id}'), findsOneWidget);
    expect(find.textContaining('style ${kStyles[1].id}'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();
    // Diagnostic presentation is coalesced at 4 Hz.
    await tester.pump(const Duration(milliseconds: 250));

    expect(harness.styles.style.id, kStyles[1].id);
    // The panel shows the new style and not the old one.
    expect(find.textContaining('style ${kStyles[1].id}'), findsOneWidget);
    expect(find.textContaining('style ${kStyles.first.id}'), findsNothing);
    expect(find.text(kStyles[1].name.toUpperCase()), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'triple taps only toggle diagnostics in SONOGLITCH_DEBUG builds',
    (tester) async {
      final harness = await pumpViewfinder(tester);
      expect(harness.settings.diagnosticsEnabled, isFalse);

      final center = Offset(
        20,
        tester.getCenter(find.byType(ViewfinderScreen)).dy,
      );
      for (var tap = 0; tap < 3; tap++) {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(harness.settings.diagnosticsEnabled, AppConfig.debugBuild);

      for (var tap = 0; tap < 3; tap++) {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(harness.settings.diagnosticsEnabled, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the shutter takes a picture with the style and the values', (
    tester,
  ) async {
    final styles = FakeStyleController(log: DebugLog());
    final harness = await pumpViewfinder(tester, styles: styles);
    final preview = await tester.runAsync(buildTestImage);
    final still = await tester.runAsync(buildTestImage);
    final rendered = await tester.runAsync(buildTestImage);
    addTearDown(rendered!.dispose);
    styles.still = rendered;
    harness.fakeCamera.publishFrame(preview!);
    harness.fakeCamera.still = still;
    harness.noise.addReading(72);
    harness.ambient.tick();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.fakeCamera.captures, 1);
    expect(harness.result, isNotNull);
    expect(harness.result!.styleId, harness.styles.style.id);
    expect(harness.result!.ambient.rawDb, 72);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
