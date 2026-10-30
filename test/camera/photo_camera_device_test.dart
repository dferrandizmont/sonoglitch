import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/app_config.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/frame_converter.dart';
import 'package:sonoglitch/camera/photo_camera_device.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/camera/screenshot_photo_source.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_photo_test_');
    file = File('${directory.path}/${ScreenshotPhotoSource.fileName}');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> writePhoto({int width = 1280, int height = 720}) async {
    final image = await buildFlatTestImage(
      width: width,
      height: height,
      red: 200,
      green: 80,
      blue: 30,
    );
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  PhotoCameraDevice device() => PhotoCameraDevice(
    sourceFile: file,
    temporaryDirectory: () async => directory,
  );

  testWidgets('streams reusable Android YUV420 frames at 30 fps and stops', (
    tester,
  ) async {
    final camera = device();
    addTearDown(camera.dispose);
    await tester.runAsync(() async {
      await writePhoto();
      await camera.initialize();
    });
    expect(camera.previewSize, const ui.Size(640, 360));
    expect(camera.deviceOrientation, DeviceOrientation.portraitUp);
    final frames = <RawFrame>[];
    await camera.startImageStream(frames.add);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frames, hasLength(3));
    expect(camera.isStreamingImages, isTrue);
    expect(frames.first.format, FrameFormat.yuv420);
    expect(frames.first.planes.map((p) => p.bytesPerRow), [640, 320, 320]);
    expect(frames.first.planes.map((p) => p.bytesPerPixel), [1, 1, 1]);
    final converted = const FrameConverter().convert(
      frames.first,
      rotationDegrees: 0,
      mirror: false,
    );
    expect((converted.width, converted.height), (360, 203));
    expect(converted.pixels[0], closeTo(200, 3));
    expect(converted.pixels[1], closeTo(80, 3));
    expect(converted.pixels[2], closeTo(30, 3));
    expect(converted.sceneLuma, isNotEmpty);
    expect(converted.colorfulness, isNotNull);
    await camera.stopImageStream();
    await tester.pump(const Duration(milliseconds: 100));
    expect(frames, hasLength(3));
    expect(camera.isStreamingImages, isFalse);
    await camera.startImageStream(frames.add);
    await tester.pump(const Duration(milliseconds: 34));
    expect(frames, hasLength(4));
    await camera.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    expect(frames, hasLength(4));
    expect(camera.isStreamingImages, isFalse);
  });

  test('small odd-sized portrait images are not enlarged', () async {
    await writePhoto(width: 7, height: 11);
    final camera = device();
    addTearDown(camera.dispose);
    await camera.initialize();
    expect(camera.previewSize, const ui.Size(7, 11));
    final frame = Completer<RawFrame>();
    await camera.startImageStream((value) {
      if (!frame.isCompleted) frame.complete(value);
    });
    final converted = const FrameConverter().convert(
      await frame.future.timeout(const Duration(seconds: 5)),
      rotationDegrees: 0,
      mirror: false,
    );
    expect((converted.width, converted.height), (7, 11));
    expect(converted.pixels.last, 255);
    expect(converted.pixels[converted.pixels.length - 4], closeTo(200, 3));
  });

  test(
    'capture is a readable full-size copy and leaves the source intact',
    () async {
      await writePhoto();
      final original = await file.readAsBytes();
      final camera = device();
      addTearDown(camera.dispose);
      await camera.initialize();
      final firstPath = await camera.takePicture();
      final secondPath = await camera.takePicture();
      expect(firstPath, isNot(file.path));
      expect(secondPath, isNot(firstPath));
      final codec = await ui.instantiateImageCodec(
        await File(firstPath).readAsBytes(),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        expect((image.width, image.height), (1280, 720));
        image.dispose();
      } finally {
        codec.dispose();
      }
      expect(await file.readAsBytes(), original);
    },
  );

  for (final enabled in [false, true]) {
    for (final exists in [false, true]) {
      test('factory selection: flag=$enabled, file=$exists', () async {
        if (exists) await writePhoto(width: 8, height: 4);
        var resolutions = 0;
        final source = await ScreenshotPhotoSource.find(
          enabled: enabled,
          directory: () async {
            resolutions++;
            return directory;
          },
        );
        expect(resolutions, enabled ? 1 : 0);
        expect(source.active, enabled && exists);
        if (!source.active) {
          expect(source.deviceFactory, isNull);
          expect(source.lister, isNull);
          expect(source.status, contains('Photo source inactive'));
          return;
        }
        expect(source.status, contains(file.path));
        final descriptions = await source.lister!();
        final description = descriptions.single;
        expect(description.sensorOrientation, 0);
        expect(description.lensDirection, CameraLensDirection.back);
        final camera = source.deviceFactory!(
          description,
          ResolutionPreset.medium,
        );
        expect(camera, isA<PhotoCameraDevice>());
        await camera.dispose();
      });
    }
  }

  test('the default compile-time flag does not resolve a photo path', () async {
    expect(AppConfig.screenshotMode, isFalse);
    final source = await ScreenshotPhotoSource.find(
      directory: () => throw StateError('Must not resolve paths'),
    );
    expect(source.deviceFactory, isNull);
  });

  test(
    'JPEG EXIF is baked once into matching preview and still pixels',
    () async {
      // Generate a baseline grayscale JPEG: two 8x8 blocks with zero DCT
      // coefficients, plus orientation=6. The upright dimensions are 16x8.
      final jpeg = <int>[0xff, 0xd8];
      void segment(int marker, List<int> payload) {
        final length = payload.length + 2;
        jpeg.addAll([0xff, marker, length >> 8, length & 255, ...payload]);
      }

      segment(0xe1, [
        69, 120, 105, 102, 0, 0, // Exif signature.
        73, 73, 42, 0, 8, 0, 0, 0, // Little-endian TIFF header.
        1, 0, // One IFD entry.
        0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, // Orientation SHORT.
        0, 0, 0, 0,
      ]);
      segment(0xdb, [0, ...List<int>.filled(64, 1)]);
      segment(0xc0, [8, 0, 16, 0, 8, 1, 1, 0x11, 0]);
      for (final table in [0, 0x10]) {
        segment(0xc4, [table, 1, ...List<int>.filled(15, 0), 0]);
      }
      segment(0xda, [1, 1, 0, 0, 63, 0]);
      jpeg.addAll([0x0f, 0xff, 0xd9]); // Two DC=0/EOB pairs, then padding.
      await file.writeAsBytes(jpeg);
      final camera = device();
      addTearDown(camera.dispose);
      await camera.initialize();
      expect(camera.previewSize, const ui.Size(16, 8));
      final path = await camera.takePicture();
      final bytes = await File(path).readAsBytes();
      expect(bytes.take(4), [0x89, 0x50, 0x4e, 0x47]);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          expect((image.width, image.height), (16, 8));
          final rgba = (await image.toByteData())!.buffer.asUint8List();
          expect(rgba.first, closeTo(128, 1));
          expect(rgba.last, 255);
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    },
  );

  for (final deferred in [false, true]) {
    test(
      'service preserves landscape preview, flip and capture, deferred=$deferred',
      () async {
        // Asymmetric pixels catch accidental rotations and mirrors.
        final image = await buildTestImage(width: 12, height: 8);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final expectedPixels = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        await file.writeAsBytes(png!.buffer.asUint8List());
        final source = await ScreenshotPhotoSource.find(
          enabled: true,
          directory: () async => directory,
        );
        final motion = MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
        );
        for (var i = 0; i < 30; i++) {
          motion.orientation.addGravity(9.8, 0, 0);
        }
        expect(motion.orientation.value.quarterTurns, isNot(0));
        final camera = CameraService(
          light: LightService(ambientLight: FakeAmbientLightSource()),
          log: DebugLog(),
          lister: source.lister,
          deviceFactory: (_, _) => device(),
          preserveSourceOrientation: source.active,
        )..motion = motion;
        addTearDown(camera.dispose);
        final frameReady = Completer<void>();
        camera.frame.addListener(() {
          if (camera.frame.value != null && !frameReady.isCompleted) {
            frameReady.complete();
          }
        });
        await camera.initialize();
        await frameReady.future.timeout(const Duration(seconds: 5));
        expect(
          (camera.frame.value!.width, camera.frame.value!.height),
          (12, 8),
        );
        await camera.flip();
        expect(camera.description!.lensDirection, CameraLensDirection.back);
        final capture = (await camera.captureStill(deferDecode: deferred))!;
        final ui.Image captured;
        if (deferred) {
          expect((capture.source!.width, capture.source!.height), (12, 8));
          captured = await capture.source!.decode(12, 8);
        } else {
          captured = capture.image;
        }
        try {
          expect((captured.width, captured.height), (12, 8));
          expect(capture.transform!.quarterTurns, 0);
          expect(capture.transform!.mirrorPreview, isFalse);
          expect(
            (await captured.toByteData())!.buffer.asUint8List(),
            expectedPixels,
          );
        } finally {
          captured.dispose();
        }
        expect(file.existsSync(), isTrue);
        expect(directory.listSync().whereType<File>().map((f) => f.uri), [
          file.uri,
        ]);
        expect(camera.isStreaming, isTrue);
        await camera.setPaused(true);
        expect(camera.isStreaming, isFalse);
        await camera.setPaused(false);
        expect(camera.isStreaming, isTrue);
      },
    );
  }
}
