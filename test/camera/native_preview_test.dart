import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const back = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 90,
  );

  CameraService service(
    FakeCameraDevice device, {
    CountingConverter? converter,
    Future<ui.Image> Function(FrameConversion)? imageFactory,
  }) => CameraService(
    light: LightService(),
    log: DebugLog(),
    converter: converter ?? CountingConverter(),
    imageFactory: imageFactory,
    lister: () async => [back, front],
    deviceFactory: (_, _) => device,
  );

  test('native preview transitions are serialized with the stream', () async {
    final device = FakeCameraDevice();
    final camera = service(device);
    addTearDown(camera.dispose);
    await camera.initialize();
    await camera.setPaused(true);
    await camera.setPaused(false);
    expect(device.operations, [
      'startStream',
      'stopStream',
      'pausePreview',
      'resumePreview',
      'startStream',
    ]);
    expect(device.previewPaused, isFalse);
  });

  test('rapid pause resume pause preserves ordering and ends hidden', () async {
    final device = FakeCameraDevice();
    final camera = service(device);
    addTearDown(camera.dispose);
    await camera.initialize();
    await Future.wait([
      camera.setPaused(true),
      camera.setPaused(false),
      camera.setPaused(true),
    ]);
    expect(device.operations, ['startStream', 'stopStream', 'pausePreview']);
    expect(device.previewPaused, isTrue);
    expect(camera.isStreaming, isFalse);
  });

  test('only the latest queued resume starts analysis', () async {
    final device = FakeCameraDevice();
    final camera = service(device);
    addTearDown(camera.dispose);
    await camera.initialize();
    await Future.wait([
      camera.setPaused(true),
      camera.setPaused(false),
      camera.setPaused(true),
      camera.setPaused(false),
    ]);
    expect(device.starts, 2, reason: 'The superseded resume must not start');
    expect(device.stops, 1);
    expect(device.previewPaused, isFalse);
    expect(camera.isStreaming, isTrue);
  });

  test(
    'initialization already hidden and lens flip never start analysis',
    () async {
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => [back, front],
        deviceFactory: (_, _) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
      );
      addTearDown(camera.dispose);
      await camera.setPaused(true);
      await camera.initialize();
      await camera.flip();
      for (final device in devices) {
        expect(device.operations, ['pausePreview']);
        expect(device.starts, 0);
      }
      await camera.setPaused(false);
      expect(devices.last.operations, [
        'pausePreview',
        'resumePreview',
        'startStream',
      ]);
    },
  );

  test('pause during initialization pauses the newly opened preview', () async {
    final gate = Completer<void>();
    final device = FakeCameraDevice(openGate: gate);
    final camera = service(device);
    addTearDown(camera.dispose);
    final opening = camera.initialize();
    await Future<void>.delayed(Duration.zero);
    final hiding = camera.setPaused(true);
    gate.complete();
    await opening;
    await hiding;
    expect(device.starts, 0);
    expect(device.previewPaused, isTrue);
  });

  test(
    'a one-shot resume failure retries the actually paused preview',
    () async {
      final device = FakeCameraDevice()..resumeFailures = 1;
      final camera = service(device);
      addTearDown(camera.dispose);
      await camera.initialize();
      await camera.setPaused(true);
      expect(device.previewPaused, isTrue);
      await camera.setPaused(false);
      expect(device.previewPaused, isFalse);
      expect(device.closings, 0);
      expect(camera.isStreaming, isTrue);
      expect(device.operations, [
        'startStream',
        'stopStream',
        'pausePreview',
        'resumePreview',
        'resumePreview',
        'startStream',
      ]);
    },
  );

  test('persistent resume failure recreates the live controller', () async {
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => [back],
      deviceFactory: (_, _) {
        final device = FakeCameraDevice()..resumeFailures = 100;
        devices.add(device);
        return device;
      },
    );
    addTearDown(camera.dispose);
    await camera.initialize();
    await camera.setPaused(true);
    expect(devices.first.previewPaused, isTrue);
    await camera.setPaused(false);
    expect(devices, hasLength(2));
    expect(devices.first.closings, 1);
    expect(devices.first.isStreamingImages, isFalse);
    expect(devices.last.opened, isTrue);
    expect(devices.last.previewPaused, isFalse);
    expect(camera.isStreaming, isTrue);
  });

  test('a failed pause is retried for the same requested state', () async {
    final device = FakeCameraDevice()..failPreview = true;
    final camera = service(device);
    addTearDown(camera.dispose);
    await camera.initialize();
    await camera.setPaused(true);
    expect(device.previewPaused, isFalse);
    device.failPreview = false;
    await camera.setPaused(true);
    expect(device.previewPaused, isTrue);
    expect(device.operations.where((op) => op == 'pausePreview'), hasLength(2));
  });

  for (final error in <Object>[
    UnimplementedError(),
    UnsupportedError('preview'),
    MissingPluginException(),
    CameraException('notImplemented', 'preview'),
  ]) {
    test(
      'unsupported preview is ignored quietly: ${error.runtimeType}',
      () async {
        final device = FakeCameraDevice()..previewUnsupported = error;
        final camera = service(device);
        addTearDown(camera.dispose);
        await camera.initialize();
        await camera.setPaused(true);
        await camera.setPaused(false);
        expect(camera.isStreaming, isTrue);
        expect(device.closings, 0);
        expect(device.operations.where((op) => op == 'resumePreview'), isEmpty);
        expect(
          camera.log.recentLines.where((line) => line.contains('ERROR')),
          isEmpty,
        );
      },
    );
  }

  test('partial initialization failure releases local ownership', () async {
    final device = FakeCameraDevice()..failInitializeAfterOpen = true;
    final camera = service(device);
    addTearDown(camera.dispose);
    await expectLater(
      camera.initialize(),
      throwsA(
        isA<CameraException>().having(
          (error) => error.code,
          'code',
          'orientation-lock-failed',
        ),
      ),
    );
    expect(device.opened, isTrue);
    expect(device.closings, 1);
    expect(device.starts, 0);
    expect(camera.isStreaming, isFalse);
    await camera.dispose();
    expect(device.closings, 1);
  });

  test(
    'late callbacks from a previous stream epoch are rejected after resume',
    () async {
      final device = FakeCameraDevice();
      final converter = CountingConverter();
      final camera = service(device, converter: converter);
      addTearDown(camera.dispose);
      await camera.initialize();
      final oldCallback = device.frameCallback!;
      await camera.setPaused(true);
      await camera.setPaused(false);
      oldCallback(buildTestFrame());
      expect(converter.conversions, 0);
      expect(camera.metrics.value.frames, 0);
    },
  );

  test(
    'an old image completing after pause and resume is disposed once',
    () async {
      final device = FakeCameraDevice();
      final pending = Completer<ui.Image>();
      final stale = await buildTestImage();
      final fresh = await buildTestImage();
      final disposed = Completer<void>();
      final previousHook = ui.Image.onDispose;
      var staleDisposals = 0;
      ui.Image.onDispose = (image) {
        previousHook?.call(image);
        if (identical(image, stale)) {
          staleDisposals++;
          if (!disposed.isCompleted) disposed.complete();
        }
      };
      addTearDown(() => ui.Image.onDispose = previousHook);
      var creations = 0;
      final camera = service(
        device,
        imageFactory: (_) {
          creations++;
          return creations == 1 ? pending.future : Future.value(fresh);
        },
      );
      addTearDown(camera.dispose);
      final publications = <ui.Image?>[];
      camera.frame.addListener(() => publications.add(camera.frame.value));
      await camera.initialize();
      device.pushFrame(buildTestFrame());
      expect(creations, 1);
      await camera.setPaused(true);
      await camera.setPaused(false);
      pending.complete(stale);
      await disposed.future;
      expect(staleDisposals, 1);
      expect(camera.frame.value, isNull);
      expect(publications, isEmpty);
      expect(camera.metrics.value.frames, 0);
      final published = Completer<void>();
      camera.frame.addListener(() {
        if (camera.frame.value == fresh && !published.isCompleted) {
          published.complete();
        }
      });
      device.pushFrame(buildTestFrame());
      await published.future;
      expect(creations, 2);
      expect(camera.frame.value, same(fresh));
      expect(camera.metrics.value.frames, 1);
      expect(publications, [fresh]);
      await camera.dispose();
      expect(staleDisposals, 1);
    },
  );
}
