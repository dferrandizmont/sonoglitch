import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_screen.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/fakes.dart';

/// The keys of the chips of the format.
const _formatKeys = [
  'res-format-original',
  'res-format-square',
  'res-format-portrait',
  'res-format-story',
];

/// The keys of the chips of the layout.
const _layoutKeys = [
  'res-layout-full',
  'res-layout-soundStrip',
  'res-layout-poster',
];

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_result_');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<AppSettings> pumpResult(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    AmbientState ambient = AmbientState.calm,
  }) async {
    final rendered = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    // Every format gets its own picture: the screen releases the picture of
    // the previous composition when it composes again.
    for (final format in ExportFormat.values) {
      export.images[format] = (await tester.runAsync(
        () => buildTestImage(width: 40, height: 20),
      ))!;
    }
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ResultScreen(
          result: CaptureResult(
            rendered: rendered,
            ambient: ambient,
            styleId: 'static',
          ),
          export: export,
          settings: settings,
          log: log,
          capture: CaptureMetrics(),
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  /// Scrolls the panel of the screen until the widget is on the screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();
  }

  testWidgets('the layout selector composes again and is remembered', (
    tester,
  ) async {
    final settings = await pumpResult(tester);
    expect(export.layouts, <ExportLayout>[ExportLayout.full]);

    await scrollTo(tester, find.text('Sound strip'));
    await tester.tap(find.text('Sound strip'));
    await tester.pump();
    expect(export.layouts.last, ExportLayout.soundStrip);
    expect(settings.exportLayout, ExportLayout.soundStrip);

    await scrollTo(tester, find.text('Poster'));
    await tester.tap(find.text('Poster'));
    await tester.pump();
    expect(export.layouts.last, ExportLayout.poster);
    expect(settings.exportLayout, ExportLayout.poster);

    // The value is read back by another instance, the way the app does it
    // when it starts.
    final read = AppSettings(store: settings.store);
    await read.load();
    expect(read.exportLayout, ExportLayout.poster);
  });

  testWidgets('the layout of the last session is the one on screen', (
    tester,
  ) async {
    final rendered = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await settings.setExportLayout(ExportLayout.soundStrip);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          result: CaptureResult(
            rendered: rendered,
            ambient: AmbientState.calm,
            styleId: 'static',
          ),
          export: export,
          settings: settings,
          log: log,
          capture: CaptureMetrics(),
        ),
      ),
    );
    await tester.pump();

    expect(export.layouts, <ExportLayout>[ExportLayout.soundStrip]);
  });

  testWidgets('the 9:16 format is offered and composes again', (tester) async {
    await pumpResult(tester);
    expect(find.text('Story 9:16'), findsOneWidget);

    await tester.tap(find.text('Story 9:16'));
    await tester.pump();

    expect(export.composed.last, ExportFormat.story);
  });

  testWidgets('the hint explains the layout that is chosen', (tester) async {
    await pumpResult(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(ResultScreen)));

    expect(find.text(l10n.resultLayoutHintFull), findsOneWidget);
    expect(find.text(l10n.resultLayoutHintSoundStrip), findsNothing);
    expect(find.text(l10n.resultLayoutHintPoster), findsNothing);

    await scrollTo(tester, find.text(l10n.resultLayoutSoundStrip));
    await tester.tap(find.text(l10n.resultLayoutSoundStrip));
    await tester.pump();

    expect(find.text(l10n.resultLayoutHintSoundStrip), findsOneWidget);
    expect(find.text(l10n.resultLayoutHintFull), findsNothing);

    await scrollTo(tester, find.text(l10n.resultLayoutPoster));
    await tester.tap(find.text(l10n.resultLayoutPoster));
    await tester.pump();

    expect(find.text(l10n.resultLayoutHintPoster), findsOneWidget);
    expect(find.text(l10n.resultLayoutHintSoundStrip), findsNothing);
  });

  testWidgets('the chips are buttons and the chosen one says so', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpResult(tester);

      for (final key in _formatKeys) {
        final node = tester.getSemantics(find.byKey(ValueKey(key)));
        expect(node.flagsCollection.isButton, isTrue, reason: key);
      }
      for (final key in _layoutKeys) {
        final node = tester.getSemantics(find.byKey(ValueKey(key)));
        expect(node.flagsCollection.isButton, isTrue, reason: key);
      }

      // The layout that is on screen is the chosen one.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('res-layout-full')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('res-layout-poster')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );

      // The chosen chip is also the one that stands out.
      final chosen = tester.getRect(
        find.byKey(const ValueKey('res-layout-full')),
      );
      final other = tester.getRect(
        find.byKey(const ValueKey('res-layout-poster')),
      );
      expect(chosen, isNot(equals(other)));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the compare button is 48 dp and says that it can be held', (
    tester,
  ) async {
    await pumpResult(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(ResultScreen)));

    final button = find.byKey(const ValueKey('res-compare'));
    expect(tester.getSize(button), const Size(48, 48));
    expect(
      find.byTooltip('Compare with the original (or hold the photo)'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(l10n.resultCompareTooltip),
      findsOneWidget,
      reason: 'the screen reader must say what the button does',
    );
    expect(l10n.resultCompareTooltip, contains('hold the photo'));
  });

  testWidgets(
    'readings form equal columns with role squares and spoken caveat',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpResult(
          tester,
          ambient: const AmbientState(rawDb: 51, light: 0.2, motion: 0.5),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ResultScreen)),
        );
        final readings = find.byKey(const ValueKey('res-readings'));
        for (final label in [
          l10n.levelNoise,
          l10n.levelLight,
          l10n.levelMotion,
        ]) {
          expect(
            find.descendant(
              of: readings,
              matching: find.text(label.toUpperCase()),
            ),
            findsOneWidget,
          );
        }
        expect(find.text('\u224851 dB'), findsOneWidget);
        expect(find.text('Low'), findsOneWidget);
        expect(find.text('Medium'), findsOneWidget);
        expect(
          find.bySemanticsLabel(l10n.resultNoiseLabel(51)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(l10n.resultLightLabel(l10n.resultLevelLow)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(l10n.resultMotionLabel(l10n.resultLevelMedium)),
          findsOneWidget,
        );
        final row = tester.widget<Row>(readings);
        final widths = row.children
            .map((child) => tester.getSize(find.byWidget(child)).width)
            .toList();
        expect(widths[0], closeTo(widths[1], 0.01));
        expect(widths[1], closeTo(widths[2], 0.01));
        final squares = find.descendant(
          of: readings,
          matching: find.byType(ColoredBox),
        );
        expect(squares, findsNWidgets(3));
        expect(tester.widgetList<ColoredBox>(squares).map((box) => box.color), [
          AppTheme.accent,
          AppTheme.warm,
          AppTheme.signalCyan,
        ]);
        for (final square in squares.evaluate()) {
          expect(
            tester.getSize(find.byWidget(square.widget)),
            const Size(4, 4),
          );
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('compare frame and visual follow the fitted photo corner', (
    tester,
  ) async {
    await pumpResult(tester);
    final photo = tester.getRect(find.byType(RawImage));
    final frameFinder = find.byKey(const ValueKey('res-photo-frame'));
    expect(tester.getRect(frameFinder), photo);
    final frame =
        tester.widget<DecoratedBox>(frameFinder).decoration as BoxDecoration;
    final border = frame.border! as Border;
    expect(border.top.width, 1);
    expect(border.top.color, AppTheme.overlayEdge.withValues(alpha: 0.08));
    final visual = find.descendant(
      of: find.byKey(const ValueKey('res-compare')),
      matching: find.byType(Ink),
    );
    expect(tester.getSize(visual), const Size(40, 40));
    final corner = tester.getRect(visual);
    expect(photo.right - corner.right, closeTo(8, 0.01));
    expect(corner.top - photo.top, closeTo(8, 0.01));
  });

  for (final layout in ExportLayout.values) {
    testWidgets('compare stays at the photo top-right in ${layout.name}', (
      tester,
    ) async {
      await pumpResult(tester);
      if (layout != ExportLayout.full) {
        final chip = find.byKey(ValueKey('res-layout-${layout.name}'));
        await scrollTo(tester, chip);
        await tester.tap(chip);
        await tester.pump();
      }
      final image = tester.getRect(find.byType(RawImage));
      final visual = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('res-compare')),
          matching: find.byType(Ink),
        ),
      );
      final plan = ExportLayoutPlan.build(
        layout: layout,
        photoWidth: 40,
        photoHeight: 20,
        readings: false,
      );
      final photoTop = image.top + plan.photo.top / plan.height * image.height;
      final photoRight =
          image.left + plan.photo.right / plan.width * image.width;
      expect(visual.top - photoTop, closeTo(8, 0.01));
      expect(photoRight - visual.right, closeTo(8, 0.01));
      expect(
        tester.getSize(find.byKey(const ValueKey('res-compare'))),
        const Size(48, 48),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Save is the sole primary and follows Share and Retake', (
    tester,
  ) async {
    await pumpResult(tester);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Share'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retake'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Retake')).dx,
      lessThan(tester.getCenter(find.text('Share')).dx),
    );
    expect(
      tester.getCenter(find.text('Share')).dx,
      lessThan(tester.getCenter(find.text('Save')).dx),
    );
  });

  testWidgets('option tiles show their selected fill and square border', (
    tester,
  ) async {
    await pumpResult(tester);
    Material tile(String key) => tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Material),
          )
          .first,
    );
    void expectTile(String key, bool selected) {
      final material = tile(key);
      expect(
        material.color,
        selected ? AppTheme.accentTint : AppTheme.surface.withValues(alpha: 0),
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(4));
      expect(shape.side.color, selected ? AppTheme.accent : AppTheme.edge);
    }

    expectTile('res-format-original', true);
    expectTile('res-format-square', false);
    expectTile('res-layout-full', true);
    expectTile('res-layout-poster', false);
    await tester.tap(find.byKey(const ValueKey('res-format-square')));
    await tester.pump();
    expectTile('res-format-original', false);
    expectTile('res-format-square', true);
    await scrollTo(tester, find.byKey(const ValueKey('res-layout-poster')));
    await tester.tap(find.byKey(const ValueKey('res-layout-poster')));
    await tester.pump();
    expectTile('res-layout-full', false);
    expectTile('res-layout-poster', true);
  });

  testWidgets('the actions are big enough for a finger', (tester) async {
    await pumpResult(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(ResultScreen)));

    for (final label in [
      l10n.resultRetake,
      l10n.resultSave,
      l10n.resultShare,
    ]) {
      final button = find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first;
      expect(button, findsOneWidget, reason: label);
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the small screen keeps the chips whole at $scale text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpResult(
        tester,
        locale: const Locale('es'),
        textScale: scale,
        ambient: const AmbientState(
          rawDb: 78,
          rawLux: 400,
          rawAccel: 1.2,
          noise: 0.8,
          light: 0.7,
          motion: 0.6,
        ),
      );

      // Every chip is as tall as a finger needs it to be.
      for (final key in [..._formatKeys, ..._layoutKeys]) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(48),
          reason: key,
        );
        expect(
          tester.getSize(find.byKey(ValueKey(key))).width,
          greaterThanOrEqualTo(48),
        );
      }

      for (final type in [TextButton, OutlinedButton, FilledButton]) {
        final size = tester.getSize(find.byType(type));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }

      // The hint is between the label of the layout and its chips, and it
      // never lands on top of them.
      final hint = tester.getRect(
        find.byKey(const ValueKey('res-layout-hint')),
      );
      final chips = tester.getRect(
        find.byKey(const ValueKey('res-layout-full')),
      );
      expect(hint.bottom, lessThanOrEqualTo(chips.top));
      expect(hint.height, greaterThan(0));

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in ['en', 'es']) {
    testWidgets(
      'small $language viewport keeps export actions reachable at 2x text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpResult(
            tester,
            locale: Locale(language),
            textScale: 2,
            ambient: const AmbientState(
              rawDb: 78,
              rawLux: 400,
              rawAccel: 1.2,
              noise: 0.8,
              light: 0.7,
              motion: 0.6,
            ),
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ResultScreen)),
          );
          expect(
            find.bySemanticsLabel(l10n.resultNoiseLabel(78)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(RawImage)).height, greaterThan(40));

          void expectActionsVisible() {
            for (final label in [l10n.resultSave, l10n.resultShare]) {
              final action = find.text(label);
              expect(action.hitTestable(), findsOneWidget);
              final rect = tester.getRect(action);
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(568));
            }
          }

          expectActionsVisible();
          await tester.scrollUntilVisible(
            find.text(l10n.resultLayoutPoster),
            100,
            scrollable: find.byType(Scrollable),
          );
          await tester.tap(find.text(l10n.resultLayoutPoster));
          await tester.pump();
          expect(export.layouts.last, ExportLayout.poster);
          expectActionsVisible();
          await tester.tap(find.text(l10n.resultShare));
          await tester.pump();
          expect(export.shared, 1);
          await tester.tap(find.text(l10n.resultSave));
          await tester.pump();
          expect(export.saved, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
