import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_screen.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';

import '../support/fakes.dart';

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_test');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
  });

  tearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } catch (_) {
      // The temporary directory is left behind in the cache of the system.
    }
  });

  /// The pictures of the three formats: the crop of a 40x20 picture is
  /// 40x20, 20x20 and 16x20.
  Future<void> giveFormats(WidgetTester tester) async {
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    export.images[ExportFormat.square] = (await tester.runAsync(
      () => buildTestImage(width: 20, height: 20),
    ))!;
    export.images[ExportFormat.portrait] = (await tester.runAsync(
      () => buildTestImage(width: 16, height: 20),
    ))!;
  }

  Future<void> pumpResult(
    WidgetTester tester,
    ui.Image rendered, {
    AmbientState ambient = AmbientState.calm,
    void Function()? onSourceReleased,
  }) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
          onSourceReleased: onSourceReleased,
        ),
      ),
    );
    await tester.pump();
  }

  /// The button with the label [label].
  ButtonStyleButton buttonOf(WidgetTester tester, String label) {
    return tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first,
    );
  }

  testWidgets('only the last composition is applied', (tester) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    await giveFormats(tester);
    final gates = <Completer<void>>[
      Completer<void>(),
      Completer<void>(),
      Completer<void>(),
    ];
    export.gates.addAll(gates);
    await pumpResult(tester, rendered!);

    await tester.tap(find.text('Square 1:1'));
    await tester.pump();
    await tester.tap(find.text('Portrait 4:5'));
    await tester.pump();

    // The last composition finishes first.
    gates[2].complete();
    await tester.pump();
    gates[1].complete();
    await tester.pump();
    gates[0].complete();
    await tester.pump();

    // The picture on screen is the portrait one.
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 16);
    expect(image.height, 20);

    // The files of the obsolete compositions are deleted.
    expect(export.written, hasLength(3));
    expect(export.files[ExportFormat.original]!.existsSync(), isFalse);
    expect(export.files[ExportFormat.square]!.existsSync(), isFalse);
    expect(export.files[ExportFormat.portrait]!.existsSync(), isTrue);
  });

  testWidgets('the file of a composition that finishes late is deleted', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final gates = <Completer<void>>[Completer<void>()];
    export.gates.addAll(gates);
    await pumpResult(tester, rendered!);

    // The screen is closed while the composition is running.
    await tester.pumpWidget(const SizedBox.shrink());
    gates[0].complete();
    await tester.pump();

    expect(export.written, hasLength(1));
    expect(export.written.single.existsSync(), isFalse);
  });

  testWidgets('the working file is deleted when the screen is left', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    await pumpResult(tester, rendered!);
    await tester.pump();

    expect(export.written, hasLength(1));
    expect(export.written.single.existsSync(), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(export.written.single.existsSync(), isFalse);
  });

  testWidgets('the working file stays cached after a save', (tester) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    await pumpResult(tester, rendered!);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(export.saved, 1);
    expect(export.written.single.existsSync(), isTrue);
  });

  testWidgets('the working file stays in the cache right after a share', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    await pumpResult(tester, rendered!);
    await tester.pump();

    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(export.shared, 1);
    // The file is not deleted in the same tick as the share returns:
    // `share_plus` resolves when the chooser is dismissed, not when the
    // receiving app has read the bytes, so the file must outlive the
    // share call and be cleaned up later (next composition, dispose, or
    // `removeStaleTemporaryFiles`).
    expect(
      export.written.single.existsSync(),
      isTrue,
      reason: 'The working file must stay in the cache for the target app',
    );
  });

  testWidgets('Save followed by Share reuses the encoded working file', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    await pumpResult(tester, rendered!);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(export.saved, 1);
    expect(export.written.single.existsSync(), isTrue);
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(export.sharedFiles.single, export.savedFiles.single);
    expect(export.written, hasLength(1));
    expect(export.composed, hasLength(1));
  });

  testWidgets('the measured values are shown in words', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final rendered = await tester.runAsync(
        () => buildTestImage(width: 40, height: 20),
      );
      export.images[ExportFormat.original] = (await tester.runAsync(
        () => buildTestImage(width: 40, height: 20),
      ))!;
      await pumpResult(
        tester,
        rendered!,
        ambient: const AmbientState(
          noise: 0.5,
          light: 0.2,
          motion: 0.8,
          rawDb: 72,
          rawLuma: 120,
          rawAccel: 3,
        ),
      );

      expect(
        find.bySemanticsLabel('Noise: about 72 dB (approximate)'),
        findsOneWidget,
      );
      // Under 0.33 is low and from 0.66 is high.
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the middle levels are shown in words', (tester) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    await pumpResult(
      tester,
      rendered!,
      ambient: const AmbientState(light: 0.5, motion: 0.5),
    );

    expect(find.text('Medium'), findsNWidgets(2));
  });

  testWidgets('the format selector changes the picture', (tester) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    await giveFormats(tester);
    await pumpResult(tester, rendered!);
    await tester.pump();

    expect(export.composed, <ExportFormat>[ExportFormat.original]);

    await tester.tap(find.text('Square 1:1'));
    await tester.pump();
    expect(export.composed.last, ExportFormat.square);

    await tester.tap(find.text('Portrait 4:5'));
    await tester.pump();
    expect(export.composed.last, ExportFormat.portrait);

    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 16);
    expect(image.height, 20);
  });

  testWidgets('the retake button closes the screen', (tester) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    export.images[ExportFormat.original] = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ResultScreen(
                    result: CaptureResult(
                      rendered: rendered!,
                      ambient: AmbientState.calm,
                      styleId: 'static',
                    ),
                    export: export,
                    settings: settings,
                    log: log,
                    capture: CaptureMetrics(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);

    final cachedImage = tester.widget<RawImage>(find.byType(RawImage)).image!;
    await tester.tap(find.text('Retake'));
    await tester.pump();
    expect(cachedImage.debugDisposed, isTrue);
    expect(export.written.every((file) => !file.existsSync()), isTrue);
    await tester.pumpAndSettle();
    expect(rendered!.debugDisposed, isTrue);

    expect(find.byType(ResultScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the save and the share wait for the picture of the format', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    await giveFormats(tester);
    final gate = Completer<void>();
    // The first picture is composed right away, the second one waits.
    export.gates.addAll(<Completer<void>?>[null, gate]);
    await pumpResult(tester, rendered!);
    await tester.pump();

    expect(buttonOf(tester, 'Save').onPressed, isNotNull);
    expect(buttonOf(tester, 'Share').onPressed, isNotNull);

    // Another format is chosen and its picture is not ready yet.
    await tester.tap(find.text('Square 1:1'));
    await tester.pump();

    expect(
      buttonOf(tester, 'Save').onPressed,
      isNull,
      reason: 'The picture of the format is not ready',
    );
    expect(
      buttonOf(tester, 'Share').onPressed,
      isNull,
      reason: 'The picture of the format is not ready',
    );

    // The picture of the format is ready.
    gate.complete();
    await tester.pump();

    expect(buttonOf(tester, 'Save').onPressed, isNotNull);
    expect(buttonOf(tester, 'Share').onPressed, isNotNull);
  });

  testWidgets('the export never uses the file of a previous format', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    await giveFormats(tester);
    final gate = Completer<void>();
    export.gates.addAll(<Completer<void>?>[null, gate]);
    await pumpResult(tester, rendered!);
    await tester.pump();

    await tester.tap(find.text('Square 1:1'));
    await tester.pump();

    // The picture of the square is not ready, so the file of the original
    // must not be exported.
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(export.saved, 0, reason: 'The picture of the format is not ready');
    expect(export.shared, 0, reason: 'The picture of the format is not ready');

    gate.complete();
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(export.saved, 1);
    // The file that was saved is the one of the square, not the one of the
    // original.
    final square = export.outputs.firstWhere(
      (output) => output.format == ExportFormat.square,
    );
    expect(export.savedFiles.single.path, square.file.path);
    // The previous format remains cached for a return to Original.
    final original = export.outputs.firstWhere(
      (output) => output.format == ExportFormat.original,
    );
    expect(
      original.file.existsSync(),
      isTrue,
      reason: 'The previous format must remain cached',
    );
  });

  testWidgets('the last format of a fast sequence is the one that is applied', (
    tester,
  ) async {
    final rendered = await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    );
    // Every composition has its own picture, so the one on screen tells
    // which composition was applied.
    export.compositions.addAll(<ui.Image>[
      (await tester.runAsync(() => buildTestImage(width: 41, height: 20)))!,
      (await tester.runAsync(() => buildTestImage(width: 20, height: 20)))!,
      (await tester.runAsync(() => buildTestImage(width: 16, height: 20)))!,
      (await tester.runAsync(() => buildTestImage(width: 30, height: 10)))!,
    ]);
    final gates = <Completer<void>>[
      Completer<void>(),
      Completer<void>(),
      Completer<void>(),
      Completer<void>(),
    ];
    export.gates.addAll(gates);
    await pumpResult(tester, rendered!);

    await tester.tap(find.text('Square 1:1'));
    await tester.pump();
    await tester.tap(find.text('Portrait 4:5'));
    await tester.pump();
    await tester.tap(find.text('Original'));
    await tester.pump();

    expect(export.composed, <ExportFormat>[
      ExportFormat.original,
      ExportFormat.square,
      ExportFormat.portrait,
      ExportFormat.original,
    ]);

    // The compositions finish in the wrong order: the last one first.
    gates[3].complete();
    await tester.pump();
    gates[2].complete();
    await tester.pump();
    gates[1].complete();
    await tester.pump();
    gates[0].complete();
    await tester.pump();

    // The picture on screen is the one of the last composition.
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 30);
    expect(image.height, 10);

    // The export uses the file of the last composition.
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(export.saved, 1);
    final applied = export.outputs.firstWhere(
      (output) => output.composition == 3,
    );
    expect(export.savedFiles.single.path, applied.file.path);
  });

  testWidgets(
    'the source image is not disposed while a composition is in flight',
    (tester) async {
      final rendered = await tester.runAsync(
        () => buildTestImage(width: 40, height: 20),
      );
      final gate = Completer<void>();
      export.gates.add(gate);
      var sourceReleased = false;
      await pumpResult(
        tester,
        rendered!,
        onSourceReleased: () => sourceReleased = true,
      );
      await tester.pump();

      expect(export.sources, hasLength(1));
      final source = export.sources.single;
      expect(source, same(rendered));

      // The screen is disposed while the composition is still pending: the
      // source picture is shared with the composition and must stay alive
      // until the composition settles, otherwise the engine rasterises a
      // disposed image.
      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        sourceReleased,
        isFalse,
        reason:
            'The source image must not be disposed while a composition '
            'is in flight',
      );

      // The composition finishes; only now is the source released.
      gate.complete();
      await tester.pump();

      expect(
        sourceReleased,
        isTrue,
        reason:
            'The source image must be released after the composition '
            'settles',
      );
    },
  );
  for (final action in ['Save', 'Share']) {
    testWidgets(
      '$action receives the full-size PNG rather than a preview file',
      (tester) async {
        final rendered = await tester.runAsync(
          () => buildTestImage(width: 4096, height: 2),
        );
        export.images[ExportFormat.original] = (await tester.runAsync(
          () => buildTestImage(width: 4096, height: 2),
        ))!;
        final preview = (await tester.runAsync(
          () => buildTestImage(width: 1024, height: 1),
        ))!;
        export.previews.add(preview);
        final fullSize = export.images[ExportFormat.original]!;
        await pumpResult(tester, rendered!);
        await tester.pump();
        final output = export.written.single;
        expect(fullSize.debugDisposed, isTrue);
        expect(export.previewInputs, [fullSize]);
        expect(export.sources.single.width, 4096);
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image!.width,
          1024,
        );
        await tester.tap(find.text(action));
        await tester.pump();
        final received = action == 'Save'
            ? export.savedFiles
            : export.sharedFiles;
        expect(received.single.path, output.path);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
