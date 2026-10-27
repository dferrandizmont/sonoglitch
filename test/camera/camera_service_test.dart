import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/exif.dart';
import 'package:sonoglitch/camera/still_source.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

/// The JPEG fixture: an asymmetric 4x2 grayscale picture with a real EXIF block.
/// The orientation byte lives at offset 0x1E (low byte, little endian).
final Uint8List _jpegFixture = base64Decode(
  '/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAQAAAAAAAAD/4AAQSkZJRgABAQAAAQABAAD/'
  '2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB'
  'AQEBAQEBAQEBAQH/wAALCAACAAQBAREA/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL'
  '/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2Jy'
  'ggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
  'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo'
  '6erx8vP09fb3+Pn6/9oACAEBAAA/AP3m/wCCbfwC+BP/AAyZ8P8A/iyvwl/5bf8ANOPB3/Plp3/U'
  'Gr//2Q==',
);

/// Copies the fixture and writes [orientation] into its EXIF tag.
Uint8List _jpegWithOrientation(int orientation) {
  final bytes = Uint8List.fromList(_jpegFixture);
  // The orientation SHORT is at offset 0x1E in little endian (low byte first).
  bytes[0x1E] = orientation & 0xFF;
  bytes[0x1F] = (orientation >> 8) & 0xFF;
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  for (final deferred in [false, true]) {
    test(
      'front capture preserves physical up with mirrored and unmirrored EXIF, deferred=$deferred',
      () async {
        final directory = Directory.systemTemp.createTempSync('front_basis');
        addTearDown(() => directory.deleteSync(recursive: true));
        final outputs = <List<int>>[];
        for (final exif in [6, 5]) {
          final file = File('${directory.path}/still.jpg')
            ..writeAsBytesSync(_jpegWithOrientation(exif));
          final motion = MotionService(
            samples: const Stream<AccelSample>.empty(),
            gyroSamples: const Stream<AccelSample>.empty(),
            gravitySamples: const Stream<AccelSample>.empty(),
          );
          for (var i = 0; i < 25; i++) {
            motion.orientation.addGravity(9.8, 0, 0);
          }
          final camera = CameraService(
            light: LightService(),
            log: DebugLog(),
            lister: () async => [
              const CameraDescription(
                name: 'front',
                lensDirection: CameraLensDirection.front,
                sensorOrientation: 90,
              ),
            ],
            deviceFactory: (_, _) => FakeCameraDevice(picturePath: file.path),
          )..motion = motion;
          await camera.initialize();
          final capture = (await camera.captureStill(deferDecode: deferred))!;
          final image = deferred
              ? await capture.source!.decode(4, 2)
              : capture.image;
          try {
            expect((image.width, image.height), (4, 2));
            final pixels = (await image.toByteData())!.buffer.asUint8List();
            outputs.add([for (var i = 0; i < pixels.length; i += 4) pixels[i]]);
            expect(capture.transform!.quarterTurns, exif == 6 ? 1 : 3);
            expect(capture.transform!.mirrorPreview, exif == 6);
          } finally {
            image.dispose();
            await camera.dispose();
          }
        }
        // EXIF=6 decoded left edge becomes the physical top after one CW turn.
        // EXIF=5 contains the mirrored portrait basis: three CW turns put the
        // SAME edge at the top, preserving only the intended horizontal mirror.
        expect(outputs[0].first, closeTo(230, 5));
        expect(outputs[0].last, closeTo(20, 5));
        expect(outputs[1], [
          ...outputs[0].sublist(0, 4).reversed,
          ...outputs[0].sublist(4).reversed,
        ]);
      },
    );
  }

  test('the still is decoded and turned upright', () async {
    final camera = CameraService(light: LightService(), log: DebugLog());
    final source = await buildTestImage(width: 40, height: 20);
    addTearDown(source.dispose);
    final data = await source.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();

    final decoded = await camera.decodeStill(bytes, description);
    addTearDown(decoded.dispose);

    // The picture was stored sideways, so it is turned.
    expect(decoded.width, 20);
    expect(decoded.height, 40);
  });

  test('the still is capped at the maximum size', () async {
    final camera = CameraService(light: LightService(), log: DebugLog());
    final source = await buildTestImage(width: 100, height: 50);
    addTearDown(source.dispose);
    final data = await source.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();

    final decoded = await camera.decodeStill(bytes, description);
    addTearDown(decoded.dispose);

    expect(decoded.width, lessThanOrEqualTo(CameraService.stillMaxSide));
    expect(decoded.height, lessThanOrEqualTo(CameraService.stillMaxSide));
  });

  group('the EXIF path of decodeStill', () {
    test(
      'a JPEG with EXIF=1 is not rotated even when the pixels are landscape',
      () async {
        final camera = CameraService(light: LightService(), log: DebugLog());

        final decoded = await camera.decodeStill(
          _jpegWithOrientation(1),
          description,
        );
        addTearDown(decoded.dispose);

        // The fixture is 4x2 (landscape). EXIF says no rotation, so the
        // decoded picture must stay landscape. Without the fix the
        // aspect heuristic would rotate it to 2x4.
        expect(decoded.width, 4, reason: 'EXIF=1 must be honoured');
        expect(decoded.height, 2);
      },
    );

    test('a JPEG with EXIF=6 is rotated by 90 degrees', () async {
      final camera = CameraService(light: LightService(), log: DebugLog());

      final decoded = await camera.decodeStill(
        _jpegWithOrientation(6),
        description,
      );
      addTearDown(decoded.dispose);

      expect(decoded.width, 2);
      expect(decoded.height, 4);
    });

    test('a JPEG with EXIF=8 is rotated by 270 degrees', () async {
      final camera = CameraService(light: LightService(), log: DebugLog());

      final decoded = await camera.decodeStill(
        _jpegWithOrientation(8),
        description,
      );
      addTearDown(decoded.dispose);

      expect(decoded.width, 2);
      expect(decoded.height, 4);
    });

    test('a JPEG with EXIF=2 (mirrored, no rotation) is mirrored', () async {
      final camera = CameraService(light: LightService(), log: DebugLog());

      final decoded = await camera.decodeStill(
        _jpegWithOrientation(2),
        description,
      );
      addTearDown(decoded.dispose);

      // EXIF=2 means mirrored, no rotation: dimensions stay 4x2.
      expect(decoded.width, 4);
      expect(decoded.height, 2);
    });

    test('a JPEG with EXIF=3 (rotation 180) is not turned by the aspect '
        'heuristic into a portrait', () async {
      final camera = CameraService(light: LightService(), log: DebugLog());

      final decoded = await camera.decodeStill(
        _jpegWithOrientation(3),
        description,
      );
      addTearDown(decoded.dispose);

      // EXIF=3 means rotation 180; landscape pixels stay landscape.
      // The old code would turn it into a 2x4 portrait (rotation 90).
      expect(decoded.width, 4);
      expect(decoded.height, 2);
    });
  });

  group('EXIF is applied exactly once to the pixels', () {
    // Top-left and bottom-right values after each EXIF transformation of
    // the asymmetric fixture. Dimensions alone miss double mirroring and
    // double 180-degree rotation.
    const corners = <(int, int)>[
      (20, 230),
      (140, 110),
      (230, 20),
      (110, 140),
      (20, 230),
      (110, 140),
      (230, 20),
      (140, 110),
    ];
    for (var orientation = 1; orientation <= 8; orientation++) {
      test('orientation $orientation keeps the expected corners', () async {
        final camera = CameraService(light: LightService(), log: DebugLog());
        final image = await camera.decodeStill(
          _jpegWithOrientation(orientation),
          description,
        );
        addTearDown(image.dispose);
        expect(image.width, orientation >= 5 ? 2 : 4);
        expect(image.height, orientation >= 5 ? 4 : 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final pixels = data!.buffer.asUint8List();
        final expected = corners[orientation - 1];
        expect(pixels[0], closeTo(expected.$1, 5));
        expect(pixels[pixels.length - 4], closeTo(expected.$2, 5));
      });
    }
  });

  group('the rotation decision', () {
    final camera = CameraService(light: LightService(), log: DebugLog());

    test('the EXIF rotation is honoured when EXIF is present', () {
      final result = camera.decideStillRotation(
        exif: ExifOrientation.fromValue(6),
        sensorOrientation: 90,
        decodedWidth: 40,
        decodedHeight: 20,
      );
      expect(result.rotation, 90);
      expect(result.mirrored, isFalse);
    });

    test('the aspect heuristic does not override the EXIF when the pixels are '
        'landscape but the EXIF says no rotation', () {
      final result = camera.decideStillRotation(
        exif: ExifOrientation.fromValue(1),
        sensorOrientation: 90,
        decodedWidth: 40,
        decodedHeight: 20,
      );
      expect(
        result.rotation,
        0,
        reason: 'EXIF=1 says no rotation; the aspect must not override it',
      );
    });

    test('the aspect heuristic does not override the EXIF when the pixels are '
        'portrait but the EXIF says it is already rotated', () {
      final result = camera.decideStillRotation(
        exif: ExifOrientation.fromValue(6),
        sensorOrientation: 90,
        decodedWidth: 20,
        decodedHeight: 40,
      );
      expect(
        result.rotation,
        90,
        reason: 'EXIF=6 says rotate 90; the aspect must not clear it',
      );
    });

    test(
      'a picture without EXIF that is still landscape is turned to portrait',
      () {
        final result = camera.decideStillRotation(
          exif: null,
          sensorOrientation: 90,
          decodedWidth: 40,
          decodedHeight: 20,
        );
        expect(result.rotation, 90);
      },
    );

    test('a picture without EXIF that is already portrait is left alone', () {
      final result = camera.decideStillRotation(
        exif: null,
        sensorOrientation: 90,
        decodedWidth: 20,
        decodedHeight: 40,
      );
      expect(result.rotation, 0);
    });
  });
  for (var orientation = 1; orientation <= 8; orientation++) {
    test(
      'deferred metadata and targeted decoding agree for EXIF $orientation',
      () async {
        final camera = CameraService(light: LightService(), log: DebugLog());
        final source = await EncodedStill.read(
          _jpegWithOrientation(orientation),
          (data, width, height) => camera.decodeStill(
            data,
            description,
            targetWidth: width,
            targetHeight: height,
          ),
        );
        final expected = orientation >= 5 ? (2, 4) : (4, 2);
        expect((source.width, source.height), expected);
        final image = await source.decode(source.width, source.height);
        expect((image.width, image.height), expected);
        image.dispose();
      },
    );
  }
}
