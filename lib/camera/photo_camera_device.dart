import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_device.dart';
import 'raw_frame.dart';

/// A private screenshot camera backed by one JPEG or PNG, displayed upright.
/// The stream uses the same limited-range YUV420 contract as Android cameras.
class PhotoCameraDevice implements CameraDevice {
  PhotoCameraDevice({
    required this.sourceFile,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  final File sourceFile;
  final Future<Directory> Function() temporaryDirectory;

  static const previewLongSide = 640;
  static const frameInterval = Duration(microseconds: 33333);
  static int _captureSequence = 0;

  Uint8List? _sourceBytes;
  RawFrame? _frame;
  Timer? _timer;
  bool _disposed = false;

  @override
  bool get isStreamingImages => _timer?.isActive ?? false;

  @override
  ui.Size get previewSize => _frame == null
      ? ui.Size.zero
      : ui.Size(_frame!.width.toDouble(), _frame!.height.toDouble());

  @override
  DeviceOrientation get deviceOrientation => DeviceOrientation.portraitUp;

  @override
  Future<void> initialize() async {
    if (_disposed) throw StateError('The photo camera is closed');
    final bytes = await sourceFile.readAsBytes();
    final image = await _decode(bytes);
    try {
      final scale = math.min(
        1.0,
        previewLongSide / math.max(image.width, image.height),
      );
      final width = math.max(1, (image.width * scale).round());
      final height = math.max(1, (image.height * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      final ui.Image preview;
      try {
        preview = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
      try {
        final rgba = await preview.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (_disposed) throw StateError('The photo camera is closed');
        _frame = _toYuv420(rgba!.buffer.asUint8List(), width, height);
        _sourceBytes = bytes;
      } finally {
        preview.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> startImageStream(void Function(RawFrame frame) onFrame) async {
    if (_disposed || _frame == null) {
      throw StateError('The photo camera is not initialized');
    }
    await stopImageStream();
    _timer = Timer.periodic(frameInterval, (_) => onFrame(_frame!));
  }

  @override
  Future<void> stopImageStream() async {
    _timer?.cancel();
    _timer = null;
  }

  // There is no independent native preview surface to pause.
  @override
  Future<void> pausePreview() async {}

  @override
  Future<void> resumePreview() async {}

  @override
  Future<String> takePicture() async {
    final bytes = _sourceBytes;
    if (_disposed || bytes == null) {
      throw StateError('The photo camera is not initialized');
    }
    final image = await _decode(bytes);
    final ByteData? png;
    try {
      // Bake EXIF orientation into pixels and drop metadata. Preview and still
      // now have exactly the same basis, including landscape source pictures.
      png = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    final cache = await temporaryDirectory();
    final file = File(
      '${cache.path}/sonoglitch_photo_'
      '${DateTime.now().microsecondsSinceEpoch}_${_captureSequence++}.png',
    );
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
    return file.path;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stopImageStream();
    _frame = null;
    _sourceBytes = null;
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static RawFrame _toYuv420(Uint8List rgba, int width, int height) {
    final y = Uint8List(width * height);
    final chromaWidth = (width + 1) ~/ 2;
    final chromaHeight = (height + 1) ~/ 2;
    final u = Uint8List(chromaWidth * chromaHeight);
    final v = Uint8List(chromaWidth * chromaHeight);
    int byte(double value) => value.round().clamp(0, 255);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final index = (row * width + column) * 4;
        // rawRgba is premultiplied, so its RGB already flattens onto black.
        final r = rgba[index];
        final g = rgba[index + 1];
        final b = rgba[index + 2];
        y[row * width + column] = byte(
          16 + 0.256788 * r + 0.504129 * g + 0.097906 * b,
        );
        if (row.isEven && column.isEven) {
          final chroma = (row ~/ 2) * chromaWidth + column ~/ 2;
          u[chroma] = byte(128 - 0.148223 * r - 0.290993 * g + 0.439216 * b);
          v[chroma] = byte(128 + 0.439216 * r - 0.367788 * g - 0.071427 * b);
        }
      }
    }
    return RawFrame(
      width: width,
      height: height,
      format: FrameFormat.yuv420,
      planes: [
        RawPlane(bytes: y, bytesPerRow: width),
        RawPlane(bytes: u, bytesPerRow: chromaWidth),
        RawPlane(bytes: v, bytesPerRow: chromaWidth),
      ],
    );
  }
}
