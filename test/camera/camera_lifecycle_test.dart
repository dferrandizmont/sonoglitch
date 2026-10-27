import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/signature/signature_signals.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  const back = description;
  const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 90,
  );

  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_camera');
  });

  tearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } catch (_) {
      // The temporary directory is left behind in the cache of the system.
    }
  });

  /// Writes a picture in a file of the test and returns its path.
  Future<String> writePicture({bool valid = true}) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}still_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    if (valid) {
      final image = await buildTestImage(width: 8, height: 8);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    } else {
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    }
    return file.path;
  }

  test('the camera is closed when the service is closed', () async {
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice();
        devices.add(device);
        return device;
      },
    );

    await camera.initialize();
    expect(devices, hasLength(1));
    expect(devices.single.starts, 1);

    await camera.dispose();

    expect(devices.single.closings, 1, reason: 'The camera must be released');
    expect(devices.single.stops, 1, reason: 'The stream must be stopped');
    expect(camera.isStreaming, isFalse);
  });

  test('a camera that opens while the service is closed is released', () async {
    final gate = Completer<void>();
    final devices = <FakeCameraDevice>[];
    final created = Completer<FakeCameraDevice>();
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice(openGate: gate);
        devices.add(device);
        if (!created.isCompleted) created.complete(device);
        return device;
      },
    );

    final opening = camera.initialize();
    final device = await created.future;

    // The service is closed while the camera is opening.
    final closing = camera.dispose();
    gate.complete();
    await opening;
    await closing;

    expect(
      device.closings,
      1,
      reason: 'The camera that lost the race must be released',
    );
    expect(device.starts, 0, reason: 'The stream must not start');
    expect(camera.isStreaming, isFalse);
  });

  test('the camera is not opened when the service is closed at once', () async {
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice();
        devices.add(device);
        return device;
      },
    );

    final opening = camera.initialize();
    final closing = camera.dispose();
    await opening;
    await closing;

    expect(
      devices,
      isEmpty,
      reason: 'The camera must not be opened after the service was closed',
    );
  });

  test('the camera of the picture is released when the capture ends', () async {
    final picture = await writePicture();
    final devices = <FakeCameraDevice>[];
    final stillCreated = Completer<FakeCameraDevice>();
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice(picturePath: picture);
        devices.add(device);
        if (preset == ResolutionPreset.max && !stillCreated.isCompleted) {
          stillCreated.complete(device);
        }
        return device;
      },
    );

    await camera.initialize();
    final capture = await camera.captureStill();
    addTearDown(capture!.image.dispose);

    expect(
      devices,
      hasLength(3),
      reason: 'The picture needs a second camera and the live one comes back',
    );
    expect(devices[1].closings, 1, reason: 'The camera of the picture is gone');
    expect(devices[0].closings, 1, reason: 'The live camera was closed');
    expect(devices[2].closings, 0, reason: 'The live camera is open again');
    expect(camera.isStreaming, isTrue, reason: 'The live camera is back');
  });

  test(
    'the picture fails when the camera is closed while it is taken',
    () async {
      final picture = await writePicture();
      final stillGate = Completer<void>();
      final devices = <FakeCameraDevice>[];
      final stillCreated = Completer<FakeCameraDevice>();
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice(
            openGate: preset == ResolutionPreset.max ? stillGate : null,
            picturePath: picture,
          );
          devices.add(device);
          if (preset == ResolutionPreset.max && !stillCreated.isCompleted) {
            stillCreated.complete(device);
          }
          return device;
        },
      );

      await camera.initialize();
      final capture = camera.captureStill();
      final still = await stillCreated.future;

      // The service is closed while the camera of the picture is opening.
      final closing = camera.dispose();
      stillGate.complete();

      await expectLater(capture, throwsA(isA<CameraException>()));
      await closing;

      expect(still.closings, 1, reason: 'The camera must be released');
      expect(
        devices,
        hasLength(2),
        reason: 'The live camera must not be opened again',
      );
      expect(camera.isStreaming, isFalse);
    },
  );

  test(
    'the live camera is not opened again when the service is closed',
    () async {
      final picture = await writePicture();
      final pictureGate = Completer<void>();
      final devices = <FakeCameraDevice>[];
      final stillCreated = Completer<FakeCameraDevice>();
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice(
            picturePath: picture,
            pictureGate: preset == ResolutionPreset.max ? pictureGate : null,
          );
          devices.add(device);
          if (preset == ResolutionPreset.max && !stillCreated.isCompleted) {
            stillCreated.complete(device);
          }
          return device;
        },
      );

      await camera.initialize();
      final capture = camera.captureStill();
      final still = await stillCreated.future;
      await still.pictureAsked.future;

      // The service is closed while the picture is being taken.
      final closing = camera.dispose();
      pictureGate.complete();

      final result = await capture;
      addTearDown(result!.image.dispose);
      await closing;

      expect(still.closings, 1, reason: 'The camera must be released');
      expect(
        devices,
        hasLength(2),
        reason: 'The live camera must not be opened again',
      );
      expect(camera.isStreaming, isFalse);
    },
  );

  test('no frame is converted while the camera is paused', () async {
    final light = LightService();
    final converter = CountingConverter();
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: light,
      log: DebugLog(),
      converter: converter,
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice();
        devices.add(device);
        return device;
      },
    );

    await camera.initialize();
    devices.single.pushFrame(buildTestFrame());
    await Future<void>.delayed(Duration.zero);

    expect(converter.conversions, 1, reason: 'The frame must be converted');
    final luma = light.rawLuma;
    expect(luma, isNotNull, reason: 'The light of the scene is measured');

    await camera.setPaused(true);
    devices.single.pushFrame(buildTestFrame());
    await Future<void>.delayed(Duration.zero);

    expect(
      converter.conversions,
      1,
      reason: 'No frame may be converted while the camera is hidden',
    );
    expect(
      light.rawLuma,
      luma,
      reason: 'The light of the scene must not be measured while hidden',
    );
  });

  test(
    'a pause followed by a resume without waiting still stops the stream',
    () async {
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
      );

      await camera.initialize();
      expect(devices.single.isStreamingImages, isTrue);
      final startsBefore = devices.single.starts;
      final stopsBefore = devices.single.stops;

      // A pause immediately followed by a resume, without awaiting the
      // pause: the queued pause action must still call `stopImageStream`,
      // otherwise the sensor stays open while the app is hidden.
      final pausing = camera.setPaused(true);
      final resuming = camera.setPaused(false);
      await pausing;
      await resuming;

      expect(
        devices.single.stops,
        stopsBefore + 1,
        reason: 'The stream must be stopped by the pause action',
      );
      expect(
        devices.single.starts,
        startsBefore + 1,
        reason: 'The stream must be restarted by the resume action',
      );
      expect(
        devices.single.isStreamingImages,
        isTrue,
        reason: 'The camera is running again after the resume',
      );
    },
  );

  test(
    'a pause that is undone before it runs still stops the stream',
    () async {
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
      );

      await camera.initialize();
      final startsBefore = devices.single.starts;
      final stopsBefore = devices.single.stops;

      // Two pauses queued in a row (no resume between): the camera must end
      // paused and the stream must have been stopped exactly once.
      await camera.setPaused(true);
      final second = camera.setPaused(true);
      await second;

      expect(
        devices.single.stops,
        stopsBefore + 1,
        reason: 'The stream is stopped exactly once',
      );
      expect(
        devices.single.starts,
        startsBefore,
        reason: 'The stream is not restarted',
      );
      expect(devices.single.isStreamingImages, isFalse);
      expect(camera.isPaused, isTrue);
    },
  );
  test('export capture asks max preset, preserves the real file size and restores a small stream', () async {
    final picture = await writePicture();
    final presets = <ResolutionPreset>[];
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        presets.add(preset);
        return FakeCameraDevice(picturePath: picture);
      },
    );
    addTearDown(camera.dispose);
    await camera.initialize();
    final capture = (await camera.captureStill(deferDecode: true))!;
    expect(presets[1], ResolutionPreset.max);
    expect(presets.first, isNot(ResolutionPreset.max));
    expect(presets.last, presets.first);
    expect(camera.isStreaming, isTrue);
    expect((capture.source!.width, capture.source!.height), (8, 8));
    expect(capture.source!.compressedBytes, greaterThan(0));
    expect(
      capture.timings.decodeMs,
      0,
      reason: 'No pixel decoding before the export plan',
    );
    expect(File(picture).existsSync(), isFalse);
    final decoded = await capture.source!.decode(4, 4);
    expect((decoded.width, decoded.height), (4, 4));
    decoded.dispose();
  });
  test(
    'capture reopening while hidden restores a paused native preview',
    () async {
      final picture = await writePicture();
      final gate = Completer<void>();
      final created = Completer<FakeCameraDevice>();
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (_, preset) {
          final device = FakeCameraDevice(
            picturePath: picture,
            pictureGate: preset == ResolutionPreset.max ? gate : null,
          );
          devices.add(device);
          if (preset == ResolutionPreset.max) created.complete(device);
          return device;
        },
      );
      addTearDown(camera.dispose);
      await camera.initialize();
      final capture = camera.captureStill(deferDecode: true);
      final still = await created.future;
      await still.pictureAsked.future;
      final pause = camera.setPaused(true);
      gate.complete();
      await capture;
      await pause;
      expect(devices.last.previewPaused, isTrue);
      expect(devices.last.starts, 0);
      await camera.setPaused(false);
      expect(devices.last.previewPaused, isFalse);
      expect(devices.last.starts, 1);
    },
  );

  test('a pause and a lens change forget the colours of the camera', () async {
    var micros = 0;
    final signals = SignatureSignals(
      gravity: () => null,
      magnetometer: () => const Stream<SensorVector>.empty(),
      clock: () => micros,
    );
    signals.start();
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: LightService(),
      log: DebugLog(),
      clock: () => micros,
      lister: () async => const [back, front],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice();
        devices.add(device);
        return device;
      },
      imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
    )..signals = signals;
    addTearDown(camera.dispose);
    await camera.initialize();

    // Two frames of a vivid scene: the allowance of the scene moves.
    micros += 100000;
    devices.single.pushFrame(vividFrame());
    await waitForFrame(camera);
    micros += 100000;
    devices.single.pushFrame(vividFrame());
    await waitForFrame(camera);
    expect(
      signals.moodLanes().chromaAllowance,
      lessThan(1),
      reason: 'The colours of the camera must reach the lanes',
    );

    // A paused camera never lends its colours to the next one.
    await camera.setPaused(true);
    expect(
      signals.moodLanes().chromaAllowance,
      1,
      reason: 'A pause must forget the colours of the camera',
    );

    // The same after a lens change.
    await camera.setPaused(false);
    micros += 100000;
    devices.last.pushFrame(vividFrame());
    await waitForFrame(camera);
    micros += 100000;
    devices.last.pushFrame(vividFrame());
    await waitForFrame(camera);
    expect(signals.moodLanes().chromaAllowance, lessThan(1));

    await camera.flip();
    expect(
      signals.moodLanes().chromaAllowance,
      1,
      reason: 'A lens change must forget the colours of the camera',
    );
  });
}

/// Waits until the service has published a converted frame.
///
/// The service converts one frame at a time, so the next frame is only taken
/// after the previous one is published.
Future<void> waitForFrame(CameraService camera) {
  if (camera.frame.value != null) return Future<void>.value();
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  camera.frame.addListener(listener);
  return completer.future.whenComplete(
    () => camera.frame.removeListener(listener),
  );
}

/// A frame of two vivid colours, in the BGRA order of the camera.
RawFrame vividFrame() => RawFrame(
  width: 2,
  height: 1,
  format: FrameFormat.bgra8888,
  planes: [
    RawPlane(
      bytes: Uint8List.fromList([0, 0, 255, 255, 0, 255, 0, 255]),
      bytesPerRow: 8,
    ),
  ],
);
