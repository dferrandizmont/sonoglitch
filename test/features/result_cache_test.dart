import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_cache.dart';
import 'package:sonoglitch/features/result/result_screen.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';

import '../support/fakes.dart';

class Surface extends Fake implements ui.Image {
  @override
  int get width => ResultCache.previewSide;
  @override
  int get height => ResultCache.previewSide;
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;
  late AppSettings settings;
  late CaptureResult capture;
  final allocated = <ui.Image>[];

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('sonoglitch_cache_test_');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
    settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
  });

  tearDown(() {
    for (final image in allocated) {
      if (!image.debugDisposed) image.dispose();
    }
    allocated.clear();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<ui.Image> image(WidgetTester tester, int width) async {
    final image = (await tester.runAsync(
      () => buildTestImage(width: width, height: 20),
    ))!;
    allocated.add(image);
    return image;
  }

  Future<void> prepare(WidgetTester tester) async {
    capture = CaptureResult(
      rendered: await image(tester, 40),
      ambient: AmbientState.calm,
      styleId: 'static',
    );
    for (var i = 0; i < 9; i++) {
      export.compositions.add(await image(tester, 40 + i));
    }
  }

  Future<void> pumpResult(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          result: capture,
          export: export,
          settings: settings,
          log: log,
          capture: CaptureMetrics(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, String key) async {
    final chip = find.byKey(ValueKey(key));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    // Let the readings selector finish its size animation.
    await tester.pump(const Duration(milliseconds: 300));
  }

  ui.Image displayed(WidgetTester tester) =>
      tester.widget<RawImage>(find.byType(RawImage)).image!;

  test(
    'every output input, capture identity and variant belongs to the key',
    () {
      final source = Surface();
      final capture = CaptureResult(
        rendered: source,
        ambient: AmbientState.calm,
        styleId: 'static',
      );
      ResultCacheKey key({
        CaptureResult? identity,
        ExportFormat format = ExportFormat.original,
        ExportLayout layout = ExportLayout.full,
        ExportReadingsMode readingsMode = ExportReadingsMode.full,
        bool watermark = true,
        bool contextLine = false,
        ExportFileType fileType = ExportFileType.png,
        ExportQuality quality = ExportQuality.high,
        bool original = false,
      }) => (
        capture: identity ?? capture,
        format: format,
        layout: layout,
        readingsMode: readingsMode,
        watermark: watermark,
        contextLine: contextLine,
        fileType: fileType,
        quality: quality,
        original: original,
      );
      expect({
        key(),
        key(format: ExportFormat.square),
        key(layout: ExportLayout.poster),
        key(readingsMode: ExportReadingsMode.numbers),
        key(readingsMode: ExportReadingsMode.hidden),
        key(watermark: false),
        key(contextLine: true),
        key(fileType: ExportFileType.jpeg),
        key(quality: ExportQuality.standard),
        key(original: true),
        key(
          identity: CaptureResult(
            rendered: source,
            ambient: AmbientState.calm,
            styleId: 'static',
          ),
        ),
      }, hasLength(11));
    },
  );

  test('the frozen lanes of a capture belong to its key', () {
    final source = Surface();
    // The key holds the capture itself, so it holds the lanes that were
    // frozen at its shutter and the photo identity with them.
    final cold = CaptureResult(
      rendered: source,
      ambient: const AmbientState(
        signature: SignatureState(warmth: -0.5, pulse: 0.25),
      ),
      styleId: 'static',
    );
    final warm = CaptureResult(
      rendered: source,
      ambient: const AmbientState(
        signature: SignatureState(warmth: 0.5, pulse: -0.25),
      ),
      styleId: 'static',
    );
    ResultCacheKey key(CaptureResult capture) => (
      capture: capture,
      format: ExportFormat.original,
      layout: ExportLayout.full,
      readingsMode: ExportReadingsMode.full,
      watermark: true,
      contextLine: false,
      fileType: ExportFileType.png,
      quality: ExportQuality.high,
      original: false,
    );
    // Two captures with different frozen lanes never collide.
    expect({key(cold), key(warm)}, hasLength(2));
    // The same capture always builds the same key.
    expect(key(cold), key(cold));
  });

  test('a re-render of the same capture reuses its frozen lanes', () {
    final source = Surface();
    final capture = CaptureResult(
      rendered: source,
      ambient: const AmbientState(
        signature: SignatureState(warmth: 0.25, pulse: -0.5),
      ),
      styleId: 'static',
    );
    final key = (
      capture: capture,
      format: ExportFormat.original,
      layout: ExportLayout.full,
      readingsMode: ExportReadingsMode.full,
      watermark: true,
      contextLine: false,
      fileType: ExportFileType.png,
      quality: ExportQuality.high,
      original: false,
    );
    final cache = ResultCache();
    final file = File('${directory.path}/sonoglitch_lanes.png')
      ..writeAsStringSync('image');
    cache.put(key, CachedResult(source, file));

    final hit = cache.get(key);
    expect(hit, isNotNull);
    expect(hit!.image, same(source));
    // The lanes of the capture are the frozen ones and they are still there.
    expect(capture.ambient.signature.warmth, 0.25);
    expect(capture.ambient.signature.pulse, -0.5);
    cache.clear();
  });

  test('cache accounts for a 16 MiB maximum and drops missing temp files', () {
    final source = Surface();
    final capture = CaptureResult(
      rendered: source,
      ambient: AmbientState.calm,
      styleId: 'static',
    );
    final cache = ResultCache();
    final surfaces = <Surface>[];
    final files = <File>[];
    ResultCacheKey key(ExportFormat format) => (
      capture: capture,
      format: format,
      layout: ExportLayout.full,
      readingsMode: ExportReadingsMode.full,
      watermark: true,
      contextLine: false,
      fileType: ExportFileType.png,
      quality: ExportQuality.high,
      original: false,
    );
    for (final format in ExportFormat.values) {
      final surface = Surface();
      final file = File('${directory.path}/sonoglitch_${format.name}.png')
        ..writeAsStringSync('image');
      surfaces.add(surface);
      files.add(file);
      cache.put(key(format), CachedResult(surface, file));
    }
    expect(cache.imageBytes, 16 * 1024 * 1024);
    files.first.deleteSync();
    expect(cache.get(key(ExportFormat.original)), isNull);
    expect(surfaces.first.disposals, 1);
    cache.clear();
    cache.clear();
    expect(cache.imageBytes, 0);
    expect(surfaces.every((surface) => surface.disposals == 1), isTrue);
    expect(files.every((file) => !file.existsSync()), isTrue);
  });

  testWidgets(
    'Original -> Square -> Original reuses preview and encoded file',
    (tester) async {
      await prepare(tester);
      await pumpResult(tester);
      final first = displayed(tester);
      final firstFile = export.written.single;
      await select(tester, 'res-format-square');
      await select(tester, 'res-format-original');
      expect(displayed(tester), same(first));
      expect(export.composed, [ExportFormat.original, ExportFormat.square]);
      expect(export.written, hasLength(2));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(export.savedFiles.single, firstFile);
      expect(export.sharedFiles.single, firstFile);
      expect(export.written, hasLength(2));
      expect(firstFile.existsSync(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(first.debugDisposed, isTrue);
      expect(export.written.every((file) => !file.existsSync()), isTrue);
    },
  );

  testWidgets('four-entry LRU refreshes hits and disposes images and files', (
    tester,
  ) async {
    await prepare(tester);
    await pumpResult(tester);
    for (final format in ['square', 'portrait', 'story', 'original']) {
      await select(tester, 'res-format-$format');
    }
    final original = export.compositions[0];
    final square = export.compositions[1];
    final squareFile = export.written[1];
    await select(tester, 'res-layout-poster');
    expect(export.composed, hasLength(5));
    expect(original.debugDisposed, isFalse);
    expect(square.debugDisposed, isTrue);
    expect(squareFile.existsSync(), isFalse);
    expect(export.written.where((file) => file.existsSync()), hasLength(4));
    await select(tester, 'res-layout-full');
    expect(displayed(tester), original);
    expect(export.composed, hasLength(5));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      export.compositions.take(5).every((image) => image.debugDisposed),
      isTrue,
    );
    expect(export.written.every((file) => !file.existsSync()), isTrue);
  });

  testWidgets(
    'the readings selector exists for the strip and the poster only',
    (tester) async {
      await prepare(tester);
      await pumpResult(tester);
      expect(find.byKey(const ValueKey('res-readings-full')), findsNothing);
      await select(tester, 'res-layout-soundStrip');
      for (final mode in ExportReadingsMode.values) {
        expect(find.byKey(ValueKey('res-readings-${mode.name}')), findsOne);
      }
      expect(find.text('READINGS'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);
      await select(tester, 'res-layout-poster');
      expect(find.byKey(const ValueKey('res-readings-numbers')), findsOne);
      await select(tester, 'res-layout-full');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('res-readings-numbers')), findsNothing);
    },
  );

  testWidgets(
    'a readings mode re-renders from the same effect, is cached and persisted',
    (tester) async {
      await prepare(tester);
      settings = AppSettings(store: InMemoryPreferencesStore());
      await settings.load();
      await pumpResult(tester);
      await select(tester, 'res-layout-poster');
      await select(tester, 'res-readings-numbers');
      await select(tester, 'res-readings-hidden');
      expect(export.layouts, [
        ExportLayout.full,
        ExportLayout.poster,
        ExportLayout.poster,
        ExportLayout.poster,
      ]);
      expect(export.readingsModes, [
        ExportReadingsMode.full,
        ExportReadingsMode.full,
        ExportReadingsMode.numbers,
        ExportReadingsMode.hidden,
      ]);
      // The effect is not run again: every composition starts from the
      // picture that the effect already produced.
      expect(
        export.sources.every((s) => identical(s, capture.rendered)),
        isTrue,
      );
      expect(settings.exportReadingsMode, ExportReadingsMode.hidden);
      // Going back is a cache hit.
      final hidden = displayed(tester);
      await select(tester, 'res-readings-numbers');
      await select(tester, 'res-readings-hidden');
      expect(displayed(tester), same(hidden));
      expect(export.composed, hasLength(4));
      // What is previewed is what is saved.
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(export.savedFiles.single, export.written.last);
    },
  );

  testWidgets('a cache hit wins over a late render for another key', (
    tester,
  ) async {
    await prepare(tester);
    await pumpResult(tester);
    final first = displayed(tester);
    final gate = Completer<void>();
    export.gates.addAll([null, gate]);
    await select(tester, 'res-format-square');
    await select(tester, 'res-format-original');
    expect(displayed(tester), first);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    gate.complete();
    await tester.pump();
    expect(displayed(tester), first);
    expect(export.compositions[1].debugDisposed, isTrue);
    expect(export.written.last.existsSync(), isFalse);
    expect(export.written.first.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'context toggle invalidates output and switching back reuses the old export',
    (tester) async {
      await prepare(tester);
      await pumpResult(tester);
      final original = displayed(tester);
      await settings.setContextLineEnabled(true);
      await tester.pump();
      expect(export.composed, hasLength(2));
      expect(displayed(tester), isNot(same(original)));
      await settings.setContextLineEnabled(false);
      await tester.pump();
      expect(export.composed, hasLength(2));
      expect(displayed(tester), same(original));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings invalidate watermark, quality and file type immediately',
    (tester) async {
      await prepare(tester);
      await pumpResult(tester);
      await settings.setWatermarkEnabled(false);
      await tester.pump();
      expect(export.watermarks, [true, false]);
      await settings.setExportQuality(ExportQuality.standard);
      await tester.pump();
      expect(export.composed, hasLength(3));
      await settings.setFileType(ExportFileType.jpeg);
      await tester.pump();
      expect(export.fileTypes, [
        ExportFileType.png,
        ExportFileType.png,
        ExportFileType.png,
        ExportFileType.jpeg,
      ]);
      // Unrelated preference notifications must not reprocess the picture.
      await settings.setDiagnosticsEnabled(true);
      await tester.pump();
      expect(export.composed, hasLength(4));
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(export.sharedFiles.single, export.written.last);
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.setWatermarkEnabled(true);
      await tester.pump();
      expect(export.composed, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement capture clears cache and releases a pending old source safely',
    (tester) async {
      await prepare(tester);
      await pumpResult(tester);
      final first = export.compositions[0];
      final oldSource = capture.rendered;
      final gate = Completer<void>();
      export.gates.addAll([null, gate]);
      await select(tester, 'res-format-square');
      capture = CaptureResult(
        rendered: await image(tester, 60),
        ambient: AmbientState.calm,
        styleId: 'static',
      );
      await pumpResult(tester);
      expect(first.debugDisposed, isTrue);
      expect(export.written.first.existsSync(), isFalse);
      expect(oldSource.debugDisposed, isFalse);
      final replacement = displayed(tester);
      gate.complete();
      await tester.pump();
      expect(oldSource.debugDisposed, isTrue);
      expect(displayed(tester), replacement);
      expect(export.compositions[1].debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
