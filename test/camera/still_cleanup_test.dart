import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  late Directory directory;
  late DebugLog log;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_still');
    log = DebugLog();
  });

  tearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } catch (_) {
      // The temporary directory is left behind in the cache of the system.
    }
  });

  /// The files that are left in the cache of the test.
  List<File> cachedFiles() => directory.listSync().whereType<File>().toList();

  /// A camera whose pictures are the file of [path].
  CameraService buildCamera(String path) {
    return CameraService(
      light: LightService(),
      log: log,
      lister: () async => const [description],
      deviceFactory: (description, preset) =>
          FakeCameraDevice(picturePath: path),
    );
  }

  /// The file where the camera writes the picture.
  File stillFile() =>
      File('${directory.path}${Platform.pathSeparator}still.jpg');

  test('the picture of the camera is deleted after a capture', () async {
    final image = await buildTestImage(width: 8, height: 8);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = stillFile();
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    final camera = buildCamera(file.path);
    await camera.initialize();

    final capture = await camera.captureStill();
    addTearDown(capture!.image.dispose);

    expect(
      file.existsSync(),
      isFalse,
      reason: 'The picture of the camera must not stay in the cache',
    );
    expect(cachedFiles(), isEmpty);
  });

  test(
    'the picture of the camera is deleted when the decoding fails',
    () async {
      // The file of the camera is not a picture, so it cannot be decoded.
      final file = stillFile();
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final camera = buildCamera(file.path);
      await camera.initialize();

      await expectLater(camera.captureStill(), throwsA(anything));

      expect(
        file.existsSync(),
        isFalse,
        reason: 'The picture of the camera must not stay in the cache',
      );
      expect(cachedFiles(), isEmpty);
      expect(
        log.recentLines.any(
          (line) => line.contains('the picture of the camera was deleted'),
        ),
        isTrue,
        reason: 'The deletion of the picture must be reported',
      );
    },
  );

  test(
    'the cache is clean when the picture of the camera cannot be read',
    () async {
      // The camera writes the picture, but the file is not there when the app
      // reads it.
      final camera = buildCamera(stillFile().path);
      await camera.initialize();

      await expectLater(camera.captureStill(), throwsA(anything));

      expect(cachedFiles(), isEmpty);
    },
  );
}
