import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:sonoglitch/ambient/ambient_light_source.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/clock.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/signature/signature_signals.dart';
import 'package:sonoglitch/camera/camera_device.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/frame_converter.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_service.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';

/// A camera that never touches the hardware.
///
/// Every method of the real service is replaced by a record of what was
/// asked, so the screens can be driven from a test.
class FakeCameraService extends CameraService {
  FakeCameraService({required super.light, required super.log});

  /// Whether [initialize] was called.
  bool initialized = false;

  /// Whether [dispose] was called.
  bool disposed = false;

  /// The last value given to [setPaused].
  bool? paused;

  /// How many times the live stream was flipped.
  int flips = 0;

  /// How many times a picture was asked for.
  int captures = 0;

  /// The picture [captureStill] returns, null when there is none.
  ui.Image? still;

  /// The gate the picture waits for.
  ///
  /// When it is not completed the capture does not finish, which is what a
  /// test needs to keep the shutter busy.
  Completer<void>? captureGate;

  /// Publishes a picture in the live stream.
  void publishFrame(ui.Image image) => frame.value = image;

  @override
  Future<void> initialize({
    CameraLensDirection direction = CameraLensDirection.back,
  }) async {
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  @override
  Future<void> setPaused(bool value) async {
    paused = value;
    await super.setPaused(value);
  }

  @override
  Future<void> flip() async {
    flips++;
  }

  @override
  Future<StillCapture?> captureStill({bool deferDecode = false}) async {
    captures++;
    final gate = captureGate;
    if (gate != null) await gate.future;
    final image = still;
    if (image == null) return null;
    return StillCapture(
      image: image,
      timings: const CaptureTimings(takeMs: 12, decodeMs: 3),
    );
  }
}

/// A camera that never touches the hardware.
///
/// It records what was asked of it and can be told to wait, so a test can
/// open and close the camera while it is working.
class FakeCameraDevice implements CameraDevice {
  FakeCameraDevice({this.openGate, this.picturePath, this.pictureGate});

  /// The gate the opening of the camera waits for.
  ///
  /// When it is not completed the camera stays half open, which is what a
  /// test needs to close the service while the camera is opening.
  final Completer<void>? openGate;

  /// The path that [takePicture] returns.
  final String? picturePath;

  /// The gate the picture waits for.
  ///
  /// When it is not completed the camera keeps the picture, which is what a
  /// test needs to close the service while the picture is being taken.
  final Completer<void>? pictureGate;

  /// Completes when a picture is asked for.
  final Completer<void> pictureAsked = Completer<void>();

  /// Whether the camera was opened.
  bool opened = false;

  /// Whether the stream of pictures is running.
  @override
  bool isStreamingImages = false;

  /// The size of the preview.
  @override
  ui.Size previewSize = const ui.Size(360, 640);

  /// The orientation of the device.
  @override
  DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp;

  /// How many times the stream was started.
  int starts = 0;

  final operations = <String>[];
  bool previewPaused = false;
  bool failPreview = false;
  Object? previewUnsupported;
  int resumeFailures = 0;
  bool failInitializeAfterOpen = false;
  bool failStop = false;
  void Function(RawFrame)? get frameCallback => _onFrame;

  @override
  Future<void> pausePreview() async {
    operations.add('pausePreview');
    if (previewUnsupported case final error?) throw error;
    if (failPreview) throw StateError('preview failed');
    previewPaused = true;
  }

  @override
  Future<void> resumePreview() async {
    operations.add('resumePreview');
    if (previewUnsupported case final error?) throw error;
    if (resumeFailures > 0) {
      resumeFailures--;
      throw CameraException('resume-failed', 'Preview resume failed');
    }
    if (failPreview) throw StateError('preview failed');
    previewPaused = false;
  }

  /// How many times the stream was stopped.
  int stops = 0;

  /// How many times the camera was closed.
  int closings = 0;

  void Function(RawFrame frame)? _onFrame;

  @override
  Future<void> initialize() async {
    final gate = openGate;
    if (gate != null) await gate.future;
    opened = true;
    if (failInitializeAfterOpen) {
      throw CameraException(
        'orientation-lock-failed',
        'Orientation lock failed',
      );
    }
  }

  @override
  Future<void> startImageStream(void Function(RawFrame frame) onFrame) async {
    operations.add('startStream');
    _onFrame = onFrame;
    starts++;
    isStreamingImages = true;
  }

  @override
  Future<void> stopImageStream() async {
    operations.add('stopStream');
    if (failStop) throw StateError('stop failed');
    stops++;
    isStreamingImages = false;
  }

  @override
  Future<String> takePicture() async {
    if (!pictureAsked.isCompleted) pictureAsked.complete();
    final gate = pictureGate;
    if (gate != null) await gate.future;
    final path = picturePath;
    if (path == null) throw StateError('The camera has no picture');
    return path;
  }

  @override
  Future<void> dispose() async {
    closings++;
    isStreamingImages = false;
    _onFrame = null;
  }

  /// Publishes a frame in the stream.
  void pushFrame(RawFrame frame) => _onFrame?.call(frame);
}

/// Builds a raw frame of one grey value for the tests.
RawFrame buildTestFrame({int width = 4, int height = 2, int luma = 100}) {
  final chroma = Uint8List((width ~/ 2) * (height ~/ 2));
  for (var i = 0; i < chroma.length; i++) {
    chroma[i] = 128;
  }
  return RawFrame(
    width: width,
    height: height,
    format: FrameFormat.yuv420,
    planes: [
      RawPlane(
        bytes: Uint8List.fromList(List<int>.filled(width * height, luma)),
        bytesPerRow: width,
      ),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
    ],
  );
}

/// A converter that counts the frames it converts.
///
/// It tells how many frames the camera pipeline worked on, which is what a
/// test needs to know when the viewfinder is hidden.
class CountingConverter extends FrameConverter {
  CountingConverter();

  /// How many frames were converted.
  int conversions = 0;

  @override
  FrameConversion convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
  }) {
    conversions++;
    return super.convert(
      frame,
      rotationDegrees: rotationDegrees,
      mirror: mirror,
    );
  }
}

/// A picture that was written to a file.
class WrittenPicture {
  const WrittenPicture({
    required this.composition,
    required this.format,
    required this.file,
  });

  /// The number of the composition, in the order they were asked for.
  final int composition;

  /// The format of the composition.
  final ExportFormat format;

  /// The file the picture was written to.
  final File file;
}

/// An export service that writes to a directory of the test.
class FakeExportService extends ExportService {
  FakeExportService({required super.log, required this.directory});

  /// Where the PNGs are written.
  final Directory directory;

  /// The source images passed to [compose], in order.
  ///
  /// The result screen must keep these images alive while a composition is in
  /// flight, so the test checks that the image is still valid after the
  /// screen is closed but before the composition finishes.
  final List<ui.Image> sources = <ui.Image>[];

  /// The formats that were composed, in order.
  final List<ExportFormat> composed = [];

  /// The layouts that were composed, in order.
  final List<ExportLayout> layouts = [];

  /// The readings modes that were composed, in order.
  final List<ExportReadingsMode> readingsModes = [];
  final List<bool> watermarks = [];
  final List<ExportFileType> fileTypes = [];
  final List<ui.Image> previewInputs = [];
  final List<ui.Image> previews = [];

  /// The pictures that [crop] returns, one per format.
  ///
  /// The real crop draws with the engine, which does not work inside the
  /// fake clock of a widget test, so a test gives the pictures it wants.
  final Map<ExportFormat, ui.Image> crops = <ExportFormat, ui.Image>{};
  final List<Completer<void>?> cropGates = [];
  final List<ui.Image> cropCompositions = [];
  final List<ui.Image> cropped = [];

  /// The files that were written, in order.
  final List<File> written = [];

  /// How many times the picture was saved in the gallery.
  int saved = 0;

  /// How many times the picture was shared.
  int shared = 0;

  /// The files that were saved in the gallery.
  final List<File> savedFiles = [];

  /// The files that were shared.
  final List<File> sharedFiles = [];

  /// What [share] reports: false simulates closing the sheet without sending.
  bool shareCompletes = true;

  /// The last file written for every format.
  final Map<ExportFormat, File> files = <ExportFormat, File>{};

  /// The gates the compositions wait for.
  ///
  /// The composition number [n] waits for the gate number [n], so a test can
  /// decide in which order the compositions finish. A gate that is not in
  /// the list does not hold any composition.
  final List<Completer<void>?> gates = [];

  /// The pictures that [compose] returns, one per composition.
  ///
  /// The real composition draws with the engine, which does not work inside
  /// the fake clock of a widget test, so a test can give the pictures. The
  /// picture of the composition number [n] is the one of the list with that
  /// number, so a test can tell which composition was applied.
  final List<ui.Image> compositions = <ui.Image>[];

  /// The pictures that [compose] returns, one per format.
  final Map<ExportFormat, ui.Image> images = <ExportFormat, ui.Image>{};

  /// The files that were written, with the composition they belong to.
  final List<WrittenPicture> outputs = <WrittenPicture>[];

  /// The compositions that are waiting to be written.
  ///
  /// The queue is in the order the compositions finish, so the file of every
  /// composition is known.
  final List<int> _finished = [];

  /// The pictures that were already given to the screen.
  ///
  /// The screen releases the picture of the previous composition, so a
  /// picture that was already given cannot be given again.
  final Set<ui.Image> _given = <ui.Image>{};

  /// How many files were written, to give every one of them its own name.
  int _written = 0;

  @override
  Future<ui.Image> compose(
    ui.Image source,
    ExportFormat format, {
    bool watermark = true,
    ExportLayout layout = ExportLayout.full,
    ExportLayoutValues? values,
  }) async {
    final index = composed.length;
    sources.add(source);
    composed.add(format);
    layouts.add(layout);
    readingsModes.add(values?.readingsMode ?? ExportReadingsMode.full);
    watermarks.add(watermark);
    if (index < gates.length) {
      final gate = gates[index];
      if (gate != null) await gate.future;
    }
    _finished.add(index);
    if (index < compositions.length) return compositions[index];
    final image = images[format];
    if (image != null) {
      if (_given.contains(image)) return image.clone();
      _given.add(image);
      return image;
    }
    return super.compose(
      source,
      format,
      watermark: watermark,
      layout: layout,
      values: values,
    );
  }

  @override
  Future<ui.Image> crop(ui.Image source, ExportFormat format) async {
    final index = cropped.length;
    final image = index < cropCompositions.length
        ? cropCompositions[index]
        : crops[format] ?? source.clone();
    cropped.add(image);
    if (index < cropGates.length) await cropGates[index]?.future;
    return image;
  }

  @override
  Future<File> writePng(ui.Image image) => _write(ExportFileType.png);

  @override
  Future<File> writeFile(ui.Image image, ExportFileType type) {
    fileTypes.add(type);
    return _write(type);
  }

  @override
  Future<ui.Image> preview(ui.Image image, {required int maxSide}) async {
    previewInputs.add(image);
    return previews.removeAt(0);
  }

  Future<File> _write(ExportFileType type) async {
    // The picture is not encoded and the file is written synchronously: the
    // engine and the real file system do not work inside the fake clock of
    // a widget test, and the content of the file does not matter.
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'sonoglitch_${_written++}${type.extension}',
    );
    file.writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47], flush: true);
    written.add(file);
    final index = _finished.isEmpty ? -1 : _finished.removeAt(0);
    final format = index < 0 ? null : composed[index];
    if (format != null) files[format] = file;
    outputs.add(
      WrittenPicture(
        composition: index,
        format: format ?? ExportFormat.original,
        file: file,
      ),
    );
    return file;
  }

  @override
  Future<void> saveToGallery(File file) async {
    saved++;
    savedFiles.add(file);
  }

  @override
  Future<bool> share(File file, {ui.Rect? origin}) async {
    shared++;
    sharedFiles.add(file);
    return shareCompletes;
  }
}

/// A style controller that draws the stills without touching the shaders.
///
/// The times of the animation that were used are recorded, so a test can
/// check that the still shows the same frame of the animation that the
/// preview was showing.
class FakeStyleController extends StyleController {
  FakeStyleController({required super.log, super.loader});

  /// The times of the animation of every still, in order.
  final List<double> times = [];

  /// The picture returned by [renderStill].
  ui.Image? still;

  @override
  Future<ui.Image> renderStill(
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    int maxSide = 2048,
  }) async {
    times.add(time);
    final image = still;
    if (image == null) return source;
    return image;
  }
}

/// The magnetometer of the tests: it never delivers anything.
///
/// The platform magnetometer needs a plugin that the tests do not have, so
/// the contextual lanes keep their neutral orientation axis.
Stream<SensorVector> fakeMagnetometer() => const Stream<SensorVector>.empty();

/// Builds the contextual signals of a test with fake sensors.
SignatureSignals buildTestSignals({
  required MotionService motion,
  Clock? clock,
  DateTime Function()? localNow,
}) => SignatureSignals(
  gravity: () => motion.latestGravity,
  magnetometer: fakeMagnetometer,
  localNow: localNow,
  clock: clock ?? stopwatchClock,
);

/// A light sensor that the test drives.
class FakeAmbientLightSource implements AmbientLightSource {
  FakeAmbientLightSource({this.available = true});

  /// Whether the sensor pretends to exist.
  @override
  final bool available;

  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  @override
  Stream<double> get lux => _controller.stream;

  /// Feeds a reading of the sensor.
  void addLux(double lux) => _controller.add(lux);

  /// Makes the sensor fail, as a device without one does.
  void fail() => _controller.addError(PlatformException(code: 'unavailable'));

  Future<void> close() => _controller.close();
}

/// Builds a picture of one colour for the tests.
Future<ui.Image> buildFlatTestImage({
  int width = 200,
  int height = 200,
  int red = 20,
  int green = 40,
  int blue = 60,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = ui.Color.fromARGB(255, red, green, blue),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// Builds a small picture for the tests.
Future<ui.Image> buildTestImage({int width = 32, int height = 24}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        ui.Paint()
          ..color = ui.Color.fromARGB(
            255,
            (x * 37 + y * 3) % 256,
            (y * 41 + x * 5) % 256,
            (x * 19 + y * 23) % 256,
          ),
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
