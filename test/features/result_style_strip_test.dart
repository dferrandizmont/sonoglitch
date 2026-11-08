import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_screen.dart';
import 'package:sonoglitch/features/result/result_style_thumbnails.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/fakes.dart';
import '../support/style_fakes.dart';

ValueKey<String> _tile(String id) => ValueKey('res-style-$id');

/// Lets the picture and the previews finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;
  late RecordingExporter exporter;
  late RecordingStills stills;
  late CaptureResult capture;
  var captureRenders = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_styles_');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
    exporter = RecordingExporter(
      export: export,
      log: log,
      directory: directory,
    );
    captureRenders = 0;
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// Builds the screen with a source capture taken with [styleId].
  Future<void> pumpResult(
    WidgetTester tester, {
    String styleId = 'static',
    Locale locale = const Locale('en'),
    double textScale = 1,
    CloningSource? source,
    AmbientState ambient = const AmbientState(noise: .7, light: .4, motion: .2),
    Set<String> failing = const {},
  }) async {
    final original = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final picture = (await tester.runAsync(
      () => buildTestImage(width: 24, height: 12),
    ))!;
    stills = RecordingStills(picture)..failing.addAll(failing);
    export.crops[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    capture = CaptureResult.source(
      source: source ?? CloningSource(original),
      quality: ExportQuality.high,
      render: (image, maxSide) async {
        captureRenders++;
        return picture.clone();
      },
      ambient: ambient,
      time: 12.5,
      styleId: styleId,
    );
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
          result: capture,
          export: export,
          photoExporter: exporter,
          styleStills: stills,
          settings: settings,
          log: log,
          capture: CaptureMetrics(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapTile(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.byKey(_tile(id)));
    await tester.pump();
    await tester.tap(find.byKey(_tile(id)));
    await settle(tester);
  }

  /// The previews that were drawn for the strip, not for the main picture.
  Iterable<StillCall> thumbnailCalls() =>
      stills.calls.where((call) => call.maxSide == ResultStyleThumbnails.side);

  testWidgets('the strip has one tile per style, the capture style first', (
    tester,
  ) async {
    await pumpResult(tester, styleId: 'tape');

    final ids = [for (final style in kStyles) style.id];
    for (final id in ids) {
      expect(find.byKey(_tile(id)), findsOneWidget, reason: id);
    }
    final order = [...ids]
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byKey(_tile(a)))
            .dx
            .compareTo(tester.getTopLeft(find.byKey(_tile(b))).dx),
      );
    expect(order.first, 'tape');
    expect(order.toSet(), ids.toSet());

    // The style of the capture is the selected one, and every tile is named.
    final tape = tester.getSemantics(find.byKey(_tile('tape')));
    expect(tape.label, 'Tape style');
    expect(tape.flagsCollection.isSelected, Tristate.isTrue);
    expect(tape.flagsCollection.isButton, isTrue);
    final prism = tester.getSemantics(find.byKey(_tile('prism')));
    expect(prism.label, 'Prism style');
    expect(prism.flagsCollection.isSelected, Tristate.isFalse);
    expect(find.bySemanticsLabel('Style'), findsWidgets);
  });

  testWidgets('the previews are drawn one at a time, small, once', (
    tester,
  ) async {
    final original = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final source = CloningSource(original, width: 4000, height: 3000);
    await pumpResult(tester, source: source, styleId: 'phosphor');

    final calls = thumbnailCalls().toList();
    expect(calls.map((call) => call.styleId), [
      'phosphor',
      ...kStyles.map((style) => style.id).where((id) => id != 'phosphor'),
    ]);
    expect(stills.maxActive, 1);
    // The frozen values of the capture, not the live ones.
    expect(
      calls.every((call) => identical(call.ambient, capture.ambient)),
      isTrue,
    );
    expect(calls.every((call) => call.time == 12.5), isTrue);
    // One small decode serves every preview: 320 px on the long side.
    expect(source.requests, contains((320, 240)));
    expect(source.requests.where((r) => r.$1 == 320), hasLength(1));
    // The previews are on screen.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('res-style-strip')),
        matching: find.byType(RawImage),
      ),
      findsNWidgets(kStyles.length),
    );
    // Taking another style does not draw the previews again.
    await tapTile(tester, 'tape');
    expect(thumbnailCalls(), hasLength(kStyles.length));
  });

  testWidgets('the previews wait for the main picture', (tester) async {
    exporter.gates.add(Completer<void>());
    await pumpResult(tester);
    expect(find.byKey(_tile('tape')), findsOneWidget);
    expect(thumbnailCalls(), isEmpty);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('res-style-strip')),
        matching: find.byType(RawImage),
      ),
      findsNothing,
    );
    exporter.gates.first.complete();
    await settle(tester);
    expect(thumbnailCalls(), hasLength(kStyles.length));
  });

  testWidgets('a preview that fails leaves the rest of the strip working', (
    tester,
  ) async {
    await pumpResult(tester, failing: {'ripple'});

    final strip = find.byKey(const ValueKey('res-style-strip'));
    expect(
      find.descendant(of: strip, matching: find.byType(RawImage)),
      findsNWidgets(kStyles.length - 1),
    );
    // The tile of the failed style is still there and still works.
    stills.failing.clear();
    await tapTile(tester, 'ripple');
    expect(exporter.calls.last.styleName, 'Ripple');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on a style redraws the photo with it for save and share', (
    tester,
  ) async {
    await pumpResult(tester);
    expect(exporter.calls, hasLength(1));
    expect(exporter.calls.single.styleName, 'Static');
    expect(captureRenders, 1);

    await tapTile(tester, 'tape');

    // Only the shader changed: same capture, same frozen values.
    expect(exporter.calls, hasLength(2));
    expect(exporter.calls.last.styleName, 'Tape');
    expect(captureRenders, 1);
    final redraw = stills.calls.singleWhere((call) => call.maxSide == 1024);
    expect(redraw.styleId, 'tape');
    expect(identical(redraw.ambient, capture.ambient), isTrue);
    expect(redraw.time, 12.5);
    expect(
      tester.getSemantics(find.byKey(_tile('tape'))).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(_tile('static')))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Share'));
    await tester.pump();
    final tapeFile = exporter.calls.last.file;
    expect(export.savedFiles.single, tapeFile);
    expect(export.sharedFiles.single, tapeFile);
    expect(tapeFile.path, contains('Tape'));

    // Going back to the style of the capture reuses its picture.
    await tapTile(tester, 'static');
    expect(exporter.calls, hasLength(2));
    expect(captureRenders, 1);
  });

  testWidgets('the poster prints the name of the style that was chosen', (
    tester,
  ) async {
    await pumpResult(tester);
    await tapTile(tester, 'ripple');
    await tester.ensureVisible(find.text('Poster'));
    await tester.pump();
    await tester.tap(find.text('Poster'));
    await settle(tester);
    expect(exporter.calls.last.layout.name, 'poster');
    expect(exporter.calls.last.styleName, 'Ripple');

    await tapTile(tester, 'thermal');
    expect(exporter.calls.last.layout.name, 'poster');
    expect(exporter.calls.last.styleName, 'Thermal');

    // The format follows the new style too.
    await tester.ensureVisible(find.text('Square 1:1'));
    await tester.pump();
    await tester.tap(find.text('Square 1:1'));
    await settle(tester);
    expect(exporter.calls.last.format, ExportFormat.square);
    expect(exporter.calls.last.styleName, 'Thermal');
  });

  testWidgets('the screen releases the previews when it goes away', (
    tester,
  ) async {
    await pumpResult(tester);
    await tapTile(tester, 'prism');
    expect(stills.produced, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(stills.produced.every((image) => image.debugDisposed), isTrue);
    expect(stills.disposed, isFalse, reason: 'the test owns its stills');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a capture that is only a picture has no strip', (tester) async {
    final rendered = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
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
    expect(find.byKey(const ValueKey('res-style-strip')), findsNothing);
  });

  for (final language in ['en', 'es']) {
    testWidgets('$language strip fits 320x568 at 1.3x text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpResult(tester, locale: Locale(language), textScale: 1.3);

      final first = find.byKey(_tile('static'));
      await tester.ensureVisible(first);
      await tester.pump();
      final rect = tester.getRect(first);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(first.hitTestable(), findsOneWidget);
      // The strip scrolls sideways to the last style.
      await tester.ensureVisible(find.byKey(_tile('prism')));
      await tester.pump();
      expect(find.byKey(_tile('prism')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      final label = language == 'en' ? 'Tape style' : 'Estilo Tape';
      expect(tester.getSemantics(find.byKey(_tile('tape'))).label, label);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the strip works in landscape', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpResult(tester, textScale: 1.3);
    await tapTile(tester, 'thermal');
    expect(exporter.calls.last.styleName, 'Thermal');
    expect(tester.takeException(), isNull);
  });
}
