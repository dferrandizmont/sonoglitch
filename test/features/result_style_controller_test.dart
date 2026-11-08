import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/capture_metrics.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/features/result/capture_result.dart';
import 'package:sonoglitch/features/result/result_cache.dart';
import 'package:sonoglitch/features/result/result_export_controller.dart';
import 'package:sonoglitch/features/result/result_style_stills.dart';
import 'package:sonoglitch/features/result/result_style_thumbnails.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';

import '../support/fakes.dart';
import '../support/style_fakes.dart';

class _Host implements ResultExportHost {
  int notifications = 0;
  final messages = <String>[];

  @override
  bool mounted = true;

  @override
  void notify() => notifications++;

  @override
  Rect? get shareOrigin => null;

  @override
  void showSnack(String message) => messages.add(message);

  @override
  String get savedMessage => 'saved';

  @override
  String get sharedMessage => 'shared';

  @override
  String get saveFailedMessage => 'save failed';

  @override
  String get shareFailedMessage => 'share failed';
}

/// Lets the work of the controller, which only awaits microtasks, finish.
Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory directory;
  late DebugLog log;
  late FakeExportService export;
  late RecordingExporter exporter;
  late RecordingStills stills;
  late _Host host;
  late AppSettings settings;
  late ui.Image picture;
  late ResultExportController controller;
  late CaptureResult capture;
  var captureRenders = 0;

  CaptureResult sourceCapture({String styleId = 'static'}) =>
      CaptureResult.source(
        source: CloningSource(picture),
        quality: ExportQuality.high,
        render: (image, maxSide) async {
          captureRenders++;
          return picture.clone();
        },
        ambient: const AmbientState(noise: .6, light: .5, motion: .1),
        time: 3.25,
        styleId: styleId,
      );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('sonoglitch_ctrl_');
    log = DebugLog();
    export = FakeExportService(log: log, directory: directory);
    exporter = RecordingExporter(
      export: export,
      log: log,
      directory: directory,
    );
    picture = await buildTestImage(width: 24, height: 12);
    stills = RecordingStills(picture);
    host = _Host();
    settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    captureRenders = 0;
    capture = sourceCapture();
    controller = ResultExportController(
      result: capture,
      export: export,
      settings: settings,
      log: log,
      capture: CaptureMetrics(),
      host: host,
      photoExporter: exporter,
      styleStills: stills,
    )..initialize();
    await _settle();
  });

  tearDown(() {
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('the photo starts in the style of the capture', () {
    expect(controller.styleId, 'static');
    expect(controller.canChangeStyle, isTrue);
    expect(controller.ready, isTrue);
    expect(exporter.calls.single.styleName, 'Static');
    expect(captureRenders, 1);
  });

  test('the strip lists every style with the capture style first', () {
    expect(controller.styles.map((style) => style.id), [
      'static',
      ...kStyles.map((style) => style.id).where((id) => id != 'static'),
    ]);
    expect(resultStyleOrder('prism').map((style) => style.id).first, 'prism');
    expect(
      resultStyleOrder('nonexistent').map((style) => style.id),
      kStyles.map((style) => style.id),
    );
  });

  test(
    'selecting a style draws the same frozen capture with its shader',
    () async {
      controller.selectStyle('thermal');
      expect(controller.styleId, 'thermal');
      expect(controller.processing, isTrue);
      await _settle();

      expect(controller.ready, isTrue);
      expect(exporter.calls, hasLength(2));
      expect(exporter.calls.last.styleName, 'Thermal');
      // The capture renderer is not used for another style.
      expect(captureRenders, 1);
      final redraw = stills.calls.singleWhere((call) => call.maxSide == 1024);
      expect(redraw.styleId, 'thermal');
      expect(identical(redraw.ambient, capture.ambient), isTrue);
      expect(redraw.time, 3.25);
      expect(controller.file, exporter.calls.last.file);
    },
  );

  test('a style that was drawn comes back from the cache', () async {
    controller.selectStyle('tape');
    await _settle();
    controller.selectStyle('static');
    await _settle();
    expect(controller.styleId, 'static');
    expect(exporter.calls, hasLength(2));
    controller.selectStyle('tape');
    await _settle();
    expect(exporter.calls, hasLength(2));
    expect(controller.file, exporter.calls.last.file);
    expect(controller.ready, isTrue);
  });

  test('the layout and the format keep the style that was chosen', () async {
    controller.selectStyle('ripple');
    await _settle();
    controller.selectLayout(ExportLayout.poster);
    await _settle();
    expect(exporter.calls.last.layout, ExportLayout.poster);
    expect(exporter.calls.last.styleName, 'Ripple');
    // The style is not a setting: the next photo starts with its own.
    expect(settings.exportLayout, ExportLayout.poster);
  });

  test('a style that is not selectable is ignored', () async {
    controller.selectStyle('static');
    controller.selectStyle('datamosh');
    controller.selectStyle('nonexistent');
    await _settle();
    expect(controller.styleId, 'static');
    expect(exporter.calls, hasLength(1));
  });

  test('a capture that is only a picture cannot change style', () async {
    final rendered = await buildTestImage(width: 40, height: 20);
    export.images[ExportFormat.original] = await buildTestImage(
      width: 40,
      height: 20,
    );
    final legacy = CaptureResult(
      rendered: rendered,
      ambient: AmbientState.calm,
      styleId: 'static',
    );
    final legacyHost = _Host();
    final legacyController = ResultExportController(
      result: legacy,
      export: export,
      settings: settings,
      log: log,
      capture: CaptureMetrics(),
      host: legacyHost,
      styleStills: stills,
    )..initialize();
    addTearDown(legacyController.dispose);
    await _settle();
    expect(legacyController.canChangeStyle, isFalse);
    legacyController.selectStyle('tape');
    expect(legacyController.styleId, 'static');
    expect(legacyController.processing, isFalse);
  });

  test('a closing screen does not take another style', () async {
    controller.closeForRetake();
    controller.selectStyle('tape');
    expect(controller.styleId, 'static');
  });

  test('the previews are kept per capture and released with it', () async {
    expect(
      stills.calls.where((call) => call.maxSide == ResultStyleThumbnails.side),
      hasLength(kStyles.length),
    );
    for (final style in kStyles) {
      expect(controller.styleThumbnail(style.id), isNotNull, reason: style.id);
    }
    final shown = [
      for (final style in kStyles) controller.styleThumbnail(style.id)!,
    ];
    expect(stills.maxActive, 1);

    // A new capture drops the previews of the old one and starts again.
    final next = sourceCapture(styleId: 'prism');
    controller.updateWidget(result: next, settings: settings);
    expect(shown.every((image) => image.debugDisposed), isTrue);
    expect(controller.styleId, 'prism');
    expect(controller.styles.first.id, 'prism');
    expect(controller.styleThumbnail('prism'), isNull);
    await _settle();
    expect(controller.styleThumbnail('prism'), isNotNull);

    final again = [
      for (final style in kStyles) controller.styleThumbnail(style.id)!,
    ];
    controller.dispose();
    expect(again.every((image) => image.debugDisposed), isTrue);
    expect(stills.produced.every((image) => image.debugDisposed), isTrue);
    expect(controller.styleThumbnail('prism'), isNull);
    // The stills belong to the test, which passed them in.
    expect(stills.disposed, isFalse);
  });

  test('a late preview of a closed screen is thrown away', () async {
    final gate = Completer<void>();
    final slow = RecordingStills(picture)..gates['tape'] = gate;
    final slowHost = _Host();
    final slowController = ResultExportController(
      result: sourceCapture(),
      export: export,
      settings: settings,
      log: log,
      capture: CaptureMetrics(),
      host: slowHost,
      photoExporter: exporter,
      styleStills: slow,
    )..initialize();
    await _settle();
    expect(slow.calls.map((call) => call.styleId), contains('tape'));
    slowController.dispose();
    gate.complete();
    await _settle();
    expect(slow.produced.every((image) => image.debugDisposed), isTrue);
  });

  group('StyleThumbnailCache', () {
    test('keeps bounded previews and disposes what it replaces', () async {
      final cache = StyleThumbnailCache();
      final first = await buildTestImage(width: 32, height: 16);
      final second = await buildTestImage(width: 16, height: 8);
      cache.put('tape', first);
      expect(cache.imageBytes, 32 * 16 * 4);
      cache.put('tape', second);
      expect(first.debugDisposed, isTrue);
      expect(cache.get('tape'), same(second));
      expect(cache.length, 1);
      cache.clear();
      expect(second.debugDisposed, isTrue);
      expect(cache.imageBytes, 0);
    });

    test('refuses a picture that is larger than a preview', () async {
      final cache = StyleThumbnailCache();
      final big = await buildTestImage(
        width: StyleThumbnailCache.maxSide + 1,
        height: 4,
      );
      expect(() => cache.put('tape', big), throwsArgumentError);
      expect(big.debugDisposed, isTrue);
      expect(cache.length, 0);
    });
  });

  group('ShaderStyleStills', () {
    test('a shader that fails to load is tried again later', () async {
      var loads = 0;
      final stills = ShaderStyleStills(
        load: (style) async {
          loads++;
          throw StateError('no shader');
        },
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          stills.render(
            kStyles.first,
            picture,
            ambient: AmbientState.calm,
            time: 0,
            maxSide: 64,
          ),
          throwsStateError,
        );
      }
      expect(loads, 2);
      stills.dispose();
      await expectLater(
        stills.render(
          kStyles.first,
          picture,
          ambient: AmbientState.calm,
          time: 0,
          maxSide: 64,
        ),
        throwsStateError,
      );
      expect(loads, 2);
    });
  });
}
