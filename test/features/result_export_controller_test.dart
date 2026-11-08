import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_export_controller.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';

import '../support/fakes.dart';

/// A screen that only records what the controller asks of it.
class _Host implements ResultExportHost {
  bool isMounted = true;
  int notifications = 0;
  final messages = <String>[];

  @override
  bool get mounted => isMounted;

  @override
  Rect? get shareOrigin => null;

  @override
  void notify() => notifications++;

  @override
  void showSnack(String message) => messages.add(message);

  @override
  String get savedMessage => 'Saved.';

  @override
  String get sharedMessage => 'Shared.';

  @override
  String get saveFailedMessage => 'Could not save.';

  @override
  String get shareFailedMessage => 'Could not share.';
}

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;
  late AppSettings settings;
  late CaptureMetrics metrics;
  late _Host host;
  late ResultExportController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('sonoglitch_controller_');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
    settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    metrics = CaptureMetrics();
    host = _Host();
  });

  tearDown(() {
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<ui.Image> image(WidgetTester tester, int width) async =>
      (await tester.runAsync(() => buildTestImage(width: width, height: 20)))!;

  Future<void> settle(WidgetTester tester) async {
    // The composition and the writing of the file are plain futures; a few
    // frames let every step finish.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> build(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final rendered = await image(tester, 40);
    for (final format in ExportFormat.values) {
      export.images[format] = await image(tester, 40);
    }
    controller = ResultExportController(
      result: CaptureResult(
        rendered: rendered,
        ambient: AmbientState.calm,
        styleId: 'static',
      ),
      export: export,
      settings: settings,
      log: log,
      capture: metrics,
      host: host,
    )..initialize();
    await settle(tester);
  }

  testWidgets('a format selection composes and a return reuses the cache', (
    tester,
  ) async {
    await build(tester);
    expect(export.composed, <ExportFormat>[ExportFormat.original]);
    expect(controller.format, ExportFormat.original);
    expect(controller.ready, isTrue);
    final original = controller.composed;

    controller.selectFormat(ExportFormat.square);
    expect(controller.ready, isFalse, reason: 'The square is not ready yet');
    await settle(tester);

    expect(export.composed, <ExportFormat>[
      ExportFormat.original,
      ExportFormat.square,
    ]);
    expect(controller.format, ExportFormat.square);
    expect(controller.composed, isNotNull);
    expect(controller.composed, isNot(same(original)));
    expect(controller.ready, isTrue);

    controller.selectFormat(ExportFormat.original);
    await settle(tester);

    expect(
      export.composed,
      hasLength(2),
      reason: 'The original is served from the cache',
    );
    expect(controller.composed, same(original));
    expect(controller.ready, isTrue);
  });

  testWidgets('the layout and the readings are composed and remembered', (
    tester,
  ) async {
    await build(tester);

    controller.selectLayout(ExportLayout.poster);
    await settle(tester);
    expect(export.layouts.last, ExportLayout.poster);
    expect(settings.exportLayout, ExportLayout.poster);
    expect(controller.layout, ExportLayout.poster);

    controller.selectReadingsMode(ExportReadingsMode.hidden);
    await settle(tester);
    expect(export.readingsModes.last, ExportReadingsMode.hidden);
    expect(settings.exportReadingsMode, ExportReadingsMode.hidden);
    expect(controller.readingsMode, ExportReadingsMode.hidden);

    // The full layout has no readings: going back to it is a cache hit even
    // though the chosen mode changed, and the choice stays remembered for the
    // strip and the poster.
    final composedCount = export.composed.length;
    controller.selectLayout(ExportLayout.full);
    await settle(tester);
    expect(export.composed, hasLength(composedCount));
    expect(controller.layout, ExportLayout.full);
    expect(controller.readingsMode, ExportReadingsMode.hidden);
    expect(settings.exportReadingsMode, ExportReadingsMode.hidden);
  });

  testWidgets('the last of a fast sequence is the one that is applied', (
    tester,
  ) async {
    await build(tester);
    final gate = Completer<void>();
    export.gates.add(null);
    export.gates.add(gate);
    controller.selectFormat(ExportFormat.square);

    // The composition is in flight: another selection is taken, but the
    // first one was already requested.
    controller.selectFormat(ExportFormat.portrait);
    await tester.pump();
    expect(export.composed, <ExportFormat>[
      ExportFormat.original,
      ExportFormat.square,
      ExportFormat.portrait,
    ]);

    gate.complete();
    await settle(tester);
    // The last selection is the one that is shown.
    final shown = controller.composed;
    expect(controller.format, ExportFormat.portrait);
    expect(controller.ready, isTrue);
    expect(shown, isNotNull);
  });

  testWidgets('save and share use the ready file and report the result', (
    tester,
  ) async {
    await build(tester);
    final file = controller.file;
    expect(file, isNotNull);

    await controller.save();
    expect(export.saved, 1);
    expect(export.savedFiles.single, file);
    expect(host.messages.last, 'Saved.');

    await controller.share();
    expect(export.shared, 1);
    expect(export.sharedFiles.single, file);
    expect(host.messages.last, 'Shared.');
  });
}
