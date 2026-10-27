import 'dart:async';
import 'dart:io';

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

class Original extends Fake implements StillSource {}

class ControlledExporter extends PhotoExporter {
  ControlledExporter({
    required super.export,
    required super.log,
    required this.photo,
  });
  final PhotoExport photo;
  final gate = Completer<void>();
  final formats = <ExportFormat>[];
  final retainedBytes = <int>[];
  PhotoExport? replacement;

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
    expect(quality, ExportQuality.high);
    formats.add(format);
    retainedBytes.add(retainedImageBytes);
    await onProgress?.call(12000000);
    await gate.future;
    return replacement ?? photo;
  }
}

class QueuedExporter extends PhotoExporter {
  QueuedExporter({required super.export, required super.log});
  final photos = <PhotoExport>[];
  final gates = <Completer<void>?>[];
  final inputs = <(ExportFormat, ExportQuality, bool, ExportFileType)>[];
  final cancellations = <bool Function()?>[];
  int active = 0;
  int maxActive = 0;

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
    final index = inputs.length;
    inputs.add((format, quality, watermark, fileType));
    cancellations.add(cancelled);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (index < gates.length) await gates[index]?.future;
      return photos[index];
    } finally {
      active--;
    }
  }
}

void main() {
  for (final change in ['cached return', 'rapid misses', 'settings']) {
    testWidgets(
      'full-resolution queue handles $change without overlapping allocations',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'sonoglitch_queue_',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final log = DebugLog();
        final export = FakeExportService(log: log, directory: directory);
        final pipeline = QueuedExporter(export: export, log: log);
        for (var i = 0; i < 2; i++) {
          final image = (await tester.runAsync(
            () => buildTestImage(width: 40 + i, height: 30),
          ))!;
          addTearDown(() {
            if (!image.debugDisposed) image.dispose();
          });
          final file = File('${directory.path}/sonoglitch_$i.png')
            ..writeAsStringSync('full-size output');
          pipeline.photos.add(
            PhotoExport(image, file, {
              'width': 4000 + i,
              'height': 3000,
              'decodeMs': 1.0,
              'renderMs': 1.0,
              'encodeMs': 1.0,
            }),
          );
        }
        final gate = Completer<void>();
        pipeline.gates.addAll(
          change == 'cached return' ? [null, gate] : [gate, null],
        );
        final settings = AppSettings(store: InMemoryPreferencesStore());
        await settings.load();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResultScreen(
              result: CaptureResult.source(
                source: Original(),
                render: (_, _) async => throw StateError('Fake exporter'),
                quality: ExportQuality.high,
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
        if (change == 'settings') {
          await settings.setWatermarkEnabled(false);
          await settings.setExportQuality(ExportQuality.standard);
          await settings.setFileType(ExportFileType.jpeg);
          await tester.pump();
        } else {
          await tester.tap(find.text('Square 1:1'));
          await tester.pump();
          await tester.tap(
            find.text(change == 'cached return' ? 'Original' : 'Portrait 4:5'),
          );
          await tester.pump();
        }
        expect(pipeline.maxActive, 1);
        if (change == 'cached return') {
          expect(pipeline.inputs, hasLength(2));
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            pipeline.photos[0].image,
          );
          expect(pipeline.cancellations[1]!(), isTrue);
        } else {
          expect(pipeline.inputs, hasLength(1));
          expect(pipeline.cancellations[0]!(), isTrue);
        }
        gate.complete();
        await tester.pump();
        expect(pipeline.maxActive, 1);
        expect(pipeline.inputs, hasLength(2));
        final staleIndex = change == 'cached return' ? 1 : 0;
        final appliedIndex = 1 - staleIndex;
        expect(pipeline.photos[staleIndex].image.debugDisposed, isTrue);
        expect(pipeline.photos[staleIndex].file.existsSync(), isFalse);
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image,
          pipeline.photos[appliedIndex].image,
        );
        if (change == 'settings') {
          expect(pipeline.inputs, [
            (
              ExportFormat.original,
              ExportQuality.high,
              true,
              ExportFileType.png,
            ),
            (
              ExportFormat.original,
              ExportQuality.standard,
              false,
              ExportFileType.jpeg,
            ),
          ]);
        } else if (change == 'rapid misses') {
          expect(pipeline.inputs.map((input) => input.$1), [
            ExportFormat.original,
            ExportFormat.portrait,
          ]);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(
          pipeline.photos.every((photo) => photo.image.debugDisposed),
          isTrue,
        );
        expect(
          pipeline.photos.every((photo) => !photo.file.existsSync()),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final action in ['Save', 'Share', 'Close', 'Change format']) {
    testWidgets(
      'original-source export: $action uses the full file and owns cleanup',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'sonoglitch_result_',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final preview = (await tester.runAsync(
          () => buildTestImage(width: 4, height: 3),
        ))!;
        final file = File('${directory.path}/full_4000x3000.png')
          ..writeAsStringSync('full 12 MP PNG');
        final log = DebugLog();
        final export = FakeExportService(log: log, directory: directory);
        final photo = PhotoExport(preview, file, {
          'width': 4000,
          'height': 3000,
          'decodeMs': 20.0,
          'renderMs': 30.0,
          'encodeMs': 40.0,
        });
        final pipeline = ControlledExporter(
          export: export,
          log: log,
          photo: photo,
        );
        final capture = CaptureMetrics();
        var released = false;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResultScreen(
              result: CaptureResult.source(
                source: Original(),
                quality: ExportQuality.high,
                render: (_, _) async =>
                    throw StateError('The fake exporter owns rendering'),
                ambient: AmbientState.calm,
                styleId: 'static',
              ),
              export: export,
              photoExporter: pipeline,
              settings: AppSettings(store: InMemoryPreferencesStore()),
              log: log,
              capture: capture,
              onSourceReleased: () => released = true,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Processing 12.0 MP…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull,
        );
        if (action == 'Close') {
          await tester.pumpWidget(const SizedBox.shrink());
          expect(released, isFalse);
          pipeline.gate.complete();
          await tester.pump();
          expect(released, isTrue);
          expect(file.existsSync(), isFalse);
          return;
        }
        pipeline.gate.complete();
        await tester.pump();
        expect(find.text('Processing 12.0 MP…'), findsNothing);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 4);
        expect(capture.value.toJson()['width'], 4000);
        expect(capture.value.toJson()['height'], 3000);
        expect(pipeline.retainedBytes, [0]);
        if (action == 'Change format') {
          final replacement = (await tester.runAsync(
            () => buildTestImage(width: 3, height: 3),
          ))!;
          final replacementFile = File('${directory.path}/square.png')
            ..writeAsStringSync('replacement');
          pipeline.replacement = PhotoExport(replacement, replacementFile, {
            ...photo.metadata,
            'width': 3000,
          });
          await tester.tap(find.text('Square 1:1'));
          await tester.pump();
          await tester.pump();
          expect(pipeline.formats, [
            ExportFormat.original,
            ExportFormat.square,
          ]);
          expect(pipeline.retainedBytes, [0, 4 * 3 * 4]);
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            replacement,
          );
          expect(file.existsSync(), isTrue);
          await tester.tap(find.text('Original'));
          await tester.pump();
          expect(pipeline.formats, [
            ExportFormat.original,
            ExportFormat.square,
          ]);
          expect(tester.widget<RawImage>(find.byType(RawImage)).image, preview);
          expect(capture.value.toJson()['width'], 4000);
          await tester.tap(find.text('Share'));
          await tester.pump();
          expect(export.sharedFiles.single, file);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(released, isTrue);
          expect(replacementFile.existsSync(), isFalse);
          return;
        }
        await tester.tap(find.text(action));
        await tester.pump();
        final received = action == 'Save'
            ? export.savedFiles
            : export.sharedFiles;
        expect(received.single.path, file.path);
        expect(
          export.composed,
          isEmpty,
          reason: 'No second render or thumbnail encoding',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(released, isTrue);
      },
    );
  }
}
