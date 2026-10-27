import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/camera/still_source.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/export/photo_export.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_screen.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';

import '../support/fakes.dart';

/// A source that gives the picture of the test, without decoding anything.
class FakeSource implements StillSource {
  FakeSource(this.image);

  final ui.Image image;

  @override
  int get width => image.width;

  @override
  int get height => image.height;

  @override
  int get compressedBytes => 4096;

  @override
  Future<ui.Image> decode(int width, int height) async => image;
}

/// An exporter that returns the picture of the test.
class ControlledExporter extends PhotoExporter {
  ControlledExporter({
    required super.export,
    required super.log,
    required this.photo,
  });

  final PhotoExport photo;
  final layouts = <ExportLayout>[];

  @override
  Future<PhotoExport> process({
    required StillSource source,
    required StillRender render,
    required ExportQuality quality,
    required ExportFormat format,
    required bool watermark,
    ExportLayout layout = ExportLayout.full,
    ExportLayoutValues? values,
    ExportFileType fileType = ExportFileType.png,
    int retainedImageBytes = 0,
    FutureOr<void> Function(int)? onProgress,
    bool Function()? cancelled,
  }) async {
    layouts.add(layout);
    if (layouts.length == 1) return photo;
    final file = File(
      '${photo.file.parent.path}/sonoglitch_${layouts.length}.png',
    )..writeAsStringSync('full-size output');
    return PhotoExport(photo.image.clone(), file, photo.metadata);
  }
}

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

  /// Builds the screen with a picture that was already composed.
  Future<void> pumpResult(
    WidgetTester tester, {
    required ui.Image processed,
    required ui.Image original,
    required ui.Image cropped,
    required PhotoExporter pipeline,
    required AppSettings settings,
  }) async {
    export.images[ExportFormat.original] = processed;
    export.crops[ExportFormat.original] = cropped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          result: CaptureResult.source(
            source: FakeSource(original),
            quality: ExportQuality.high,
            render: (_, _) async =>
                throw StateError('The fake exporter owns the rendering'),
            ambient: AmbientState.calm,
            styleId: 'static',
          ),
          export: export,
          photoExporter: pipeline,
          settings: settings,
          log: log,
          capture: CaptureMetrics(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the button shows the original photo and comes back', (
    tester,
  ) async {
    final processed = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final original = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final cropped = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final file = File('${directory.path}/full.png')
      ..writeAsStringSync('processed');
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    final pipeline = ControlledExporter(
      export: export,
      log: log,
      photo: PhotoExport(processed, file, {
        'width': 40,
        'height': 20,
        'decodeMs': 1.0,
        'renderMs': 1.0,
        'encodeMs': 1.0,
      }),
    );
    await pumpResult(
      tester,
      processed: processed,
      original: original,
      cropped: cropped,
      pipeline: pipeline,
      settings: settings,
    );

    // The processed picture is the one on screen.
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, processed);

    // The button shows the original.
    await tester.tap(find.byIcon(Icons.compare));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, cropped);

    // And it comes back.
    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, processed);
  });

  testWidgets('holding the picture shows the original', (tester) async {
    final processed = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final original = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final cropped = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final file = File('${directory.path}/full.png')
      ..writeAsStringSync('processed');
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    final pipeline = ControlledExporter(
      export: export,
      log: log,
      photo: PhotoExport(processed, file, {
        'width': 40,
        'height': 20,
        'decodeMs': 1.0,
        'renderMs': 1.0,
        'encodeMs': 1.0,
      }),
    );
    await pumpResult(
      tester,
      processed: processed,
      original: original,
      cropped: cropped,
      pipeline: pipeline,
      settings: settings,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawImage)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      cropped,
      reason: 'The original is shown while the picture is held',
    );

    await gesture.up();
    await tester.pump();
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      processed,
      reason: 'The processed picture comes back when the finger leaves',
    );
  });

  testWidgets('the copy of the original is released with the screen', (
    tester,
  ) async {
    final processed = (await tester.runAsync(
      () => buildTestImage(width: 40, height: 20),
    ))!;
    final original = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final cropped = (await tester.runAsync(
      () => buildTestImage(width: 30, height: 15),
    ))!;
    final file = File('${directory.path}/full.png')
      ..writeAsStringSync('processed');
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    final pipeline = ControlledExporter(
      export: export,
      log: log,
      photo: PhotoExport(processed, file, {
        'width': 40,
        'height': 20,
        'decodeMs': 1.0,
        'renderMs': 1.0,
        'encodeMs': 1.0,
      }),
    );
    await pumpResult(
      tester,
      processed: processed,
      original: original,
      cropped: cropped,
      pipeline: pipeline,
      settings: settings,
    );

    expect(original.debugDisposed, isFalse);
    expect(cropped.debugDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(
      original.debugDisposed,
      isTrue,
      reason: 'The decoded copy of the original only lives with the screen',
    );
    expect(
      cropped.debugDisposed,
      isTrue,
      reason: 'The cropped copy of the original only lives with the screen',
    );
  });

  for (final close in [false, true]) {
    testWidgets(
      'late comparison crop is disposed after ${close ? 'close' : 'a newer crop'}',
      (tester) async {
        final processed = (await tester.runAsync(
          () => buildTestImage(width: 40, height: 20),
        ))!;
        final original = (await tester.runAsync(
          () => buildTestImage(width: 30, height: 15),
        ))!;
        final crops = <ui.Image>[];
        for (final width in [30, 15, 30]) {
          crops.add(
            (await tester.runAsync(
              () => buildTestImage(width: width, height: 15),
            ))!,
          );
        }
        addTearDown(() {
          for (final crop in crops) {
            if (!crop.debugDisposed) crop.dispose();
          }
        });
        final oldGate = Completer<void>();
        final newGate = Completer<void>();
        export.cropCompositions.addAll(crops);
        export.cropGates.addAll([null, oldGate, newGate]);
        final file = File('${directory.path}/sonoglitch_processed.png')
          ..writeAsStringSync('photo');
        final pipeline = ControlledExporter(
          export: export,
          log: log,
          photo: PhotoExport(processed, file, {
            'width': 40,
            'height': 20,
            'decodeMs': 1.0,
            'renderMs': 1.0,
            'encodeMs': 1.0,
          }),
        );
        final settings = AppSettings(store: InMemoryPreferencesStore());
        await settings.load();
        await pumpResult(
          tester,
          processed: processed,
          original: original,
          cropped: crops[0],
          pipeline: pipeline,
          settings: settings,
        );
        await tester.tap(find.byKey(const ValueKey('res-compare')));
        await tester.pump();
        await tester.tap(find.text('Square 1:1'));
        await tester.pump();
        if (close) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await tester.tap(find.text('Original'));
          await tester.pump();
          newGate.complete();
          await tester.pump();
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            crops[2],
          );
        }
        oldGate.complete();
        await tester.pump();
        expect(crops[1].debugDisposed, isTrue);
        if (!close) {
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            crops[2],
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(original.debugDisposed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a picture without a source cannot show the original', (
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

    final button = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byIcon(Icons.compare),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'There is no original photo to compare with',
    );
  });
}
