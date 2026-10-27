import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/capture_orientation.dart';
import 'package:sonoglitch/camera/oriented_still.dart';
import 'package:sonoglitch/camera/still_source.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/export/export_service.dart';
import 'package:sonoglitch/export/photo_export.dart';

import '../support/fakes.dart';

class _Source implements StillSource {
  _Source(this.width, this.height, {this.image});
  @override
  final int width;
  @override
  final int height;
  final ui.Image? image;
  (int, int)? requested;
  @override
  int get compressedBytes => 10;
  @override
  Future<ui.Image> decode(int width, int height) async {
    requested = (width, height);
    return image!.clone();
  }
}

Future<ui.Image> _corners() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // Deliberately asymmetric, as a mirrored front-camera still would be.
  canvas.drawColor(const ui.Color(0xFF202020), ui.BlendMode.src);
  for (final (rect, color) in [
    (const ui.Rect.fromLTWH(0, 0, 150, 300), const ui.Color(0xFFFF0000)),
    (const ui.Rect.fromLTWH(150, 0, 150, 300), const ui.Color(0xFF00FF00)),
    (const ui.Rect.fromLTWH(0, 300, 150, 300), const ui.Color(0xFF0000FF)),
    (const ui.Rect.fromLTWH(150, 300, 150, 300), const ui.Color(0xFFFFFF00)),
  ]) {
    canvas.drawRect(rect, ui.Paint()..color = color);
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(300, 600);
  } finally {
    picture.dispose();
  }
}

Future<int> _pixel(ui.Image image, int x, int y) async {
  final bytes = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  return (bytes.getUint8(i) << 16) |
      (bytes.getUint8(i + 1) << 8) |
      bytes.getUint8(i + 2);
}

void settleGravity(
  CaptureOrientationTracker tracker,
  double x,
  double y,
  double z,
) {
  for (var i = 0; i < 25; i++) {
    tracker.addGravity(x, y, z);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'four signed gravity poses, diagonal hysteresis and flat/invalid samples',
    () {
      final tracker = CaptureOrientationTracker();
      expect(tracker.value, CaptureOrientation.portrait);
      settleGravity(tracker, 9.8, 0, 0);
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      // Device +x points to physical up: a right-pointing image vector must
      // rotate counterclockwise (3 CW turns) to point up in the final photo.
      expect(tracker.value.quarterTurns, 3);
      settleGravity(tracker, 6.8, 7.1, 0);
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      settleGravity(tracker, 5, 8, 0);
      expect(tracker.value, CaptureOrientation.portrait);
      settleGravity(tracker, 7.1, 6.8, 0);
      expect(tracker.value, CaptureOrientation.portrait);
      settleGravity(tracker, -9.8, 0, 0);
      expect(tracker.value, CaptureOrientation.landscapeRight);
      expect(tracker.value.quarterTurns, 1);
      settleGravity(tracker, 0, -9.8, 0);
      expect(tracker.value, CaptureOrientation.portraitUpsideDown);
      settleGravity(tracker, 0, 0, 9.8);
      settleGravity(tracker, 1, 2, 9.5);
      settleGravity(tracker, double.nan, 9.8, 0);
      expect(tracker.value, CaptureOrientation.portraitUpsideDown);
      settleGravity(tracker, 0, 9.8, 0);
      expect(tracker.value.quarterTurns, 0);
    },
  );

  for (final (width, height) in [(3000, 4000), (4000, 6000), (6144, 8160)]) {
    for (var turns = 0; turns < 4; turns++) {
      test(
        '12/24/50 MP $width x $height rotation=$turns precedes crop planning',
        () {
          final source = OrientedStill(_Source(width, height), turns);
          final w = turns.isOdd ? height : width;
          final h = turns.isOdd ? width : height;
          expect((source.width, source.height), (w, h));
          expect(source.compressedBytes, 10);
          final square = ExportPlan.cropRect(w, h, ExportFormat.square);
          expect(
            (square.width, square.height),
            (width.toDouble(), width.toDouble()),
          );
          final portrait = ExportPlan.cropRect(w, h, ExportFormat.portrait);
          if (turns.isOdd) {
            // Landscape is cropped to 4:5 in its final axes, not rotated 5:4.
            expect(
              (portrait.width, portrait.height),
              ((width * 0.8).floor(), width),
            );
            expect(portrait.left, ((height - portrait.width) ~/ 2).toDouble());
            expect(portrait.top, 0);
          }
          for (final format in ExportFormat.values) {
            final plan = ExportPlan.build(
              sourceWidth: source.width,
              sourceHeight: source.height,
              quality: ExportQuality.maximum,
              format: format,
              textureLimit: 16384,
            );
            expect(plan.crop, ExportPlan.cropRect(w, h, format));
            expect(plan.width * plan.height, lessThanOrEqualTo(24000000));
            expect(plan.decodeWidth, lessThanOrEqualTo(w));
            expect(plan.decodeHeight, lessThanOrEqualTo(h));
          }
        },
      );
    }
  }

  test(
    'rotation maps asymmetric pixels through all four turns without mirroring',
    () async {
      final image = await _corners();
      addTearDown(image.dispose);
      final expected = [
        [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00],
        [0x0000FF, 0xFF0000, 0xFFFF00, 0x00FF00],
        [0xFFFF00, 0x0000FF, 0x00FF00, 0xFF0000],
        [0x00FF00, 0xFFFF00, 0xFF0000, 0x0000FF],
      ];
      for (var turns = 0; turns < 4; turns++) {
        final source = _Source(300, 600, image: image);
        final oriented = OrientedStill(source, turns);
        final output = await oriented.decode(oriented.width, oriented.height);
        try {
          expect(source.requested, (300, 600));
          expect(
            (output.width, output.height),
            (oriented.width, oriented.height),
          );
          expect(
            await Future.wait([
              _pixel(output, 10, 10),
              _pixel(output, output.width - 10, 10),
              _pixel(output, 10, output.height - 10),
              _pixel(output, output.width - 10, output.height - 10),
            ]),
            expected[turns],
          );
        } finally {
          output.dispose();
        }
      }
    },
  );

  test(
    'export crop and watermark follow the rotated photo, including PNG output',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'orientation_export',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = await _corners();
      addTearDown(image.dispose);
      final log = DebugLog();
      final service = ExportService(log: log, temporaryDirectory: directory);
      final exporter = PhotoExporter(
        export: service,
        log: log,
        textureProbe: (requested) async => requested,
      );
      final source = OrientedStill(_Source(300, 600, image: image), 1);
      for (final format in [ExportFormat.square, ExportFormat.portrait]) {
        Future<PhotoExport> process(bool watermark) => exporter.process(
          source: source,
          render: (input, _) async => input.clone(),
          quality: ExportQuality.maximum,
          format: format,
          watermark: watermark,
        );
        final plain = await process(false);
        final marked = await process(true);
        try {
          final expectedWidth = format == ExportFormat.square ? 300 : 240;
          expect(
            (marked.image.width, marked.image.height),
            (expectedWidth, 300),
          );
          expect(marked.metadata['nativeWidth'], 600);
          expect(marked.metadata['nativeHeight'], 300);
          // After the clockwise turn, left is blue/yellow and right red/green.
          expect(await _pixel(plain.image, 10, 10), 0x0000FF);
          expect(await _pixel(plain.image, expectedWidth - 10, 10), 0xFF0000);
          expect(await _pixel(plain.image, 10, 290), 0xFFFF00);
          final before = (await plain.image.toByteData())!;
          final after = (await marked.image.toByteData())!;
          var changed = 0;
          for (var y = 0; y < 300; y++) {
            for (var x = 0; x < expectedWidth; x++) {
              final offset = (y * expectedWidth + x) * 4;
              if (before.getUint32(offset) == after.getUint32(offset)) continue;
              changed++;
              expect(x, greaterThan(expectedWidth ~/ 2));
              expect(
                y,
                greaterThan(250),
                reason: 'watermark stays bottom right',
              );
            }
          }
          expect(changed, greaterThan(10));
          final codec = await ui.instantiateImageCodec(
            await marked.file.readAsBytes(),
          );
          final png = (await codec.getNextFrame()).image;
          try {
            expect((png.width, png.height), (expectedWidth, 300));
          } finally {
            png.dispose();
            codec.dispose();
          }
        } finally {
          plain.image.dispose();
          marked.image.dispose();
        }
      }
    },
  );

  test('camera freezes physical orientation at shutter while live frames remain portrait', () async {
    final directory = Directory.systemTemp.createTempSync(
      'orientation_capture',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = await _corners();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    final path = '${directory.path}/still.png';
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
    final gate = Completer<void>();
    final still = FakeCameraDevice(picturePath: path, pictureGate: gate);
    final live = FakeCameraDevice()
      ..deviceOrientation = DeviceOrientation.landscapeLeft;
    final motion = MotionService(
      samples: const Stream<AccelSample>.empty(),
      gyroSamples: const Stream<AccelSample>.empty(),
      gravitySamples: const Stream<AccelSample>.empty(),
    );
    final camera = CameraService(
      light: LightService(ambientLight: FakeAmbientLightSource()),
      log: DebugLog(),
      lister: () async => [
        const CameraDescription(
          name: 'fake',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 90,
        ),
      ],
      deviceFactory: (_, preset) =>
          preset == ResolutionPreset.max ? still : live,
    )..motion = motion;
    addTearDown(camera.dispose);
    await camera.initialize();
    live.pushFrame(buildTestFrame(width: 4, height: 2));
    // Wait only for the fake conversion, with a bounded timeout.
    for (var i = 0; camera.frame.value == null && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect((camera.frame.value!.width, camera.frame.value!.height), (2, 4));
    settleGravity(motion.orientation, 9.8, 0, 0);
    final pending = camera.captureStill(deferDecode: true);
    await still.pictureAsked.future;
    settleGravity(motion.orientation, 0, -9.8, 0);
    gate.complete();
    final captured = (await pending)!;
    expect((captured.source!.width, captured.source!.height), (600, 300));
    final decoded = await captured.source!.decode(600, 300);
    expect((decoded.width, decoded.height), (600, 300));
    // An unmirrored front still has physical up on its left for +X gravity.
    // Its left edge must become the TOP, not the bottom, of the final photo.
    expect(await _pixel(decoded, 10, 10), 0x0000FF);
    expect(await _pixel(decoded, 590, 10), 0xFF0000);
    expect(captured.transform!.quarterTurns, 1);
    expect(captured.transform!.mirrorPreview, isTrue);
    decoded.dispose();
  });
}
