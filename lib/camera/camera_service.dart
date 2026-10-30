import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ambient/clock.dart';
import '../ambient/light_service.dart';
import '../ambient/motion_service.dart';
import '../ambient/signature/signature_signals.dart';
import '../debug/capture_timings.dart';
import '../debug/debug_log.dart';
import 'camera_device.dart';
import 'camera_metrics.dart';
import 'exif.dart';
import 'frame_converter.dart';
import 'raw_frame.dart';
import 'oriented_still.dart';
import 'still_source.dart';

/// The picture of a capture and how long each step took.
class StillCapture {
  const StillCapture({
    required ui.Image image,
    required this.timings,
    this.decodedMirrored = false,
    this.transform,
  }) : _image = image, // ignore: prefer_initializing_formals
       source = null;

  const StillCapture.encoded({
    required this.source,
    required this.timings,
    this.decodedMirrored = false,
    this.transform,
  }) : _image = null;

  final ui.Image? _image;
  final StillSource? source;
  final bool decodedMirrored;
  final StillTransform? transform;

  /// The picture, already upright.
  ui.Image get image => _image!;

  /// How long the capture and the decoding took.
  final CaptureTimings timings;
}

/// Owns the camera: the live stream, the measurements and the still capture.
///
/// The live path converts every frame into a small upright RGBA image and
/// publishes it through [frame]. The effect renderer reads that image, so the
/// preview always shows the real picture and never a screenshot of the
/// widget.
///
/// The operations that change the camera run one after the other, and every
/// one of them looks at the state of the service again after it waits: a
/// camera that was opened while the service was closed is released instead
/// of being left open for nothing.
class CameraService {
  /// Creates the service.
  CameraService({
    required this.light,
    required this.log,
    this.converter = const FrameConverter(),
    this.clock = stopwatchClock,
    this.preserveSourceOrientation = false,
    CameraDeviceFactory? deviceFactory,
    CameraLister? lister,
    Future<ui.Image> Function(FrameConversion)? imageFactory,
  }) : _deviceFactory = deviceFactory ?? pluginCameraDevice,
       _lister = lister ?? availableCameras,
       _imageFactory = imageFactory ?? _toUiImage;

  /// Where the brightness of the scene is measured.
  final LightService light;

  /// Connected by the viewfinder to the same motion service as the HUD.
  MotionService? motion;

  /// Connected by the viewfinder to the contextual lanes of the ambient.
  ///
  /// The colourfulness of every converted frame is forwarded here. The pixels
  /// are not retained: only the numbers of the frame are read.
  SignatureSignals? signals;

  /// Where the problems are reported.
  final DebugLog log;

  /// The converter of the raw frames.
  final FrameConverter converter;

  /// The clock used to measure the conversion time.
  final Clock clock;

  /// The screenshot photo already has its final orientation, in both paths.
  /// Hardware cameras keep their existing sensor and gravity transforms.
  final bool preserveSourceOrientation;

  /// Builds the camera that the service drives.
  final CameraDeviceFactory _deviceFactory;

  /// The cameras of the device.
  final CameraLister _lister;

  /// Creates the live image; injectable to control asynchronous completion.
  final Future<ui.Image> Function(FrameConversion) _imageFactory;

  /// Longest side of the still picture, in pixels.
  static const int stillMaxSide = 4096;

  /// The latest converted frame. The previous one is disposed when a new one
  /// arrives.
  final ValueNotifier<ui.Image?> frame = ValueNotifier<ui.Image?>(null);

  /// Live measurements: frames per second, conversion time and resolution.
  final CameraMetrics metrics = CameraMetrics();

  CameraDevice? _device;
  CameraDescription? _description;
  bool _converting = false;
  bool _paused = false;
  bool? _previewPaused = false;
  bool _previewUnsupported = false;
  bool _disposed = false;
  int _generation = 0;
  int _streamGeneration = 0;
  int _pauseRequestGeneration = 0;
  int _lastLogMicros = 0;

  /// The operations that change the camera, one after the other.
  ///
  /// Two of them at the same time would fight over the camera: one would
  /// close the camera that the other is opening, and the camera that lost
  /// would never be released.
  Future<void> _queue = Future<void>.value();

  /// The camera that is being used, or null before [initialize].
  CameraDescription? get description => _description;

  /// Whether the live stream is running.
  bool get isStreaming => _device?.isStreamingImages ?? false;

  /// Whether the camera is paused.
  ///
  /// A paused camera stays open, so coming back to the viewfinder does not
  /// wait for a new initialisation.
  bool get isPaused => _paused;

  /// Opens the camera and starts the live stream.
  Future<void> initialize({
    CameraLensDirection direction = CameraLensDirection.back,
  }) {
    return _serial(() async {
      if (_disposed) return;
      final cameras = await _lister();
      if (_disposed) return;
      if (cameras.isEmpty) {
        throw CameraException('no-camera', 'No camera found on this device');
      }
      _description = _pick(cameras, direction);
      await _openLive();
      log.info(
        'camera',
        'initialised lens=${_description!.lensDirection.name} '
            'name=${_description!.name} '
            'sensorOrientation=${_description!.sensorOrientation}',
      );
    });
  }

  /// Switches between the back and the front camera.
  Future<void> flip() {
    return _serial(() async {
      if (_disposed) return;
      final cameras = await _lister();
      if (_disposed) return;
      final current = _description;
      CameraDescription? next;
      for (final camera in cameras) {
        if (camera.lensDirection != current?.lensDirection) {
          next = camera;
          break;
        }
      }
      next ??= current;
      if (next == null) return;

      await _teardownLive();
      _description = next;
      await _openLive();
      log.info('camera', 'flipped to lens=${next.lensDirection.name}');
    });
  }

  /// Stops or restarts the live stream, without closing the camera.
  ///
  /// The camera is kept open while it is paused, so the viewfinder can come
  /// back without waiting for a new initialisation. No frame is converted
  /// while it is paused.
  ///
  /// Queued pauses always stop analysis. A superseded resume skips startup,
  /// and failed preview reconciliation is retried even for the same request.
  Future<void> setPaused(bool paused) {
    if (_disposed ||
        (_paused == paused &&
            (_previewUnsupported || _previewPaused == paused))) {
      return Future<void>.value();
    }
    // The flag is changed right away, so no frame is converted while the
    // camera is hidden, even if the stream takes a moment to stop.
    _paused = paused;
    final request = ++_pauseRequestGeneration;
    if (paused) _streamGeneration++;
    motion?.resetScene();
    // The colourfulness of the previous camera is forgotten: a paused camera
    // must never lend its colours to the next one.
    signals?.clearScene();
    return _serial(() async {
      final device = _device;
      if (device == null) return;
      if (paused) {
        try {
          if (device.isStreamingImages) await device.stopImageStream();
        } catch (error, stackTrace) {
          log.error('camera', 'cannot stop the stream', error, stackTrace);
        }
        // CameraX stream cancellation clears analysis, not the native Preview.
        // Whether unbinding Preview fixes device jank still needs a trace.
        await _setPreviewPaused(device, true);
      } else {
        if (_paused || _disposed || request != _pauseRequestGeneration) return;
        var resumed = await _setPreviewPaused(device, false);
        if (_paused || _disposed || request != _pauseRequestGeneration) return;
        if (!resumed) resumed = await _setPreviewPaused(device, false);
        if (_paused || _disposed || request != _pauseRequestGeneration) return;
        if (!resumed) {
          // Reuse the capture/flip reopening path instead of leaving a
          // successfully paused native preview frozen after a failed resume.
          await _teardownLive();
          await _openLive();
          return;
        }
        try {
          await _startStream(resumeRequest: request);
        } catch (error, stackTrace) {
          log.error('camera', 'cannot restart the stream', error, stackTrace);
        }
      }
    });
  }

  /// Takes the picture and returns it as an upright image.
  ///
  /// The picture is taken with the highest resolution the camera offers: the
  /// live controller is closed, a second one is opened with
  /// [ResolutionPreset.max] and the live stream is restored afterwards. If
  /// that fails, the picture of the live controller is used as a fallback.
  Future<StillCapture?> captureStill({bool deferDecode = false}) {
    // Freeze at the shutter, before any queued camera initialisation or I/O.
    final turns = preserveSourceOrientation
        ? 0
        : motion?.orientation.value.quarterTurns ?? 0;
    return _serial(() async {
      final description = _description;
      final device = _device;
      if (description == null || device == null) return null;

      try {
        final capture = await _captureAtHighestResolution(
          description,
          deferDecode: deferDecode,
        );
        return await _orientCapture(capture, turns, description);
      } catch (error, stackTrace) {
        log.error(
          'camera',
          'the high resolution capture failed, falling back',
          error,
          stackTrace,
        );
        final fallback = _device;
        if (fallback == null || _disposed) rethrow;
        final capture = await _captureWith(
          fallback,
          description,
          deferDecode: deferDecode,
        );
        return await _orientCapture(capture, turns, description);
      }
    });
  }

  Future<StillCapture> _orientCapture(
    StillCapture capture,
    int previewTurns,
    CameraDescription description,
  ) async {
    final transform = StillTransform(
      frontLens: description.lensDirection == CameraLensDirection.front,
      decodedMirrored: capture.decodedMirrored,
      previewQuarterTurns: previewTurns,
    );
    final turns = transform.quarterTurns;
    final source = capture.source;
    if (source != null) {
      return StillCapture.encoded(
        source: OrientedStill(source, turns),
        timings: capture.timings,
        decodedMirrored: capture.decodedMirrored,
        transform: transform,
      );
    }
    try {
      return StillCapture(
        image: await rotatePhoto(capture.image, turns),
        timings: capture.timings,
        decodedMirrored: capture.decodedMirrored,
        transform: transform,
      );
    } finally {
      capture.image.dispose();
    }
  }

  /// Closes the camera and releases every resource.
  ///
  /// The notifiers are not disposed on purpose: the widgets that listen to
  /// them are removed after this call, and a notifier that is disposed too
  /// early makes them fail.
  Future<void> dispose() async {
    if (_disposed) return;
    // The flag is set right away: an operation that is running now sees it
    // and releases the camera it was opening.
    _disposed = true;
    _generation++;
    await _serial(() async {
      try {
        await _teardownLive();
        final image = frame.value;
        frame.value = null;
        image?.dispose();
      } catch (error, stackTrace) {
        log.error(
          'camera',
          'the camera was not closed cleanly',
          error,
          stackTrace,
        );
      }
    });
  }

  // Internals ----------------------------------------------------------------

  /// Runs [action] when the previous operation is finished.
  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _openLive() async {
    final description = _description;
    if (description == null || _disposed) return;
    final front = description.lensDirection == CameraLensDirection.front;
    motion?.setCameraBasis(frontLens: front, mirrored: front);
    // The colourfulness of the previous lens is forgotten.
    signals?.clearScene();
    final generation = _generation;
    final device = _deviceFactory(description, ResolutionPreset.medium);
    try {
      await device.initialize();
    } catch (_) {
      // Initialization can fail after opening (e.g. orientation locking).
      // Until publication here, the local scope owns the device.
      await _release(device);
      rethrow;
    }
    if (_disposed || generation != _generation) {
      // The camera was closed while it was opening: nobody else knows about
      // it, so it is released here.
      await _release(device);
      return;
    }
    _device = device;
    _previewPaused = false;
    _previewUnsupported = false;
    if (_paused) {
      await _setPreviewPaused(device, true);
    } else {
      await _startStream();
    }
    log.info('camera', 'live stream opened preview=${device.previewSize}');
  }

  Future<bool> _setPreviewPaused(CameraDevice device, bool paused) async {
    if (_previewUnsupported || _previewPaused == paused) return true;
    try {
      if (paused) {
        await device.pausePreview();
      } else {
        await device.resumePreview();
      }
      _previewPaused = paused;
      log.info('camera', 'native preview ${paused ? 'paused' : 'resumed'}');
      return true;
    } on UnimplementedError {
      _previewUnsupported = true;
      return true;
    } on UnsupportedError {
      _previewUnsupported = true;
      return true;
    } on MissingPluginException {
      _previewUnsupported = true;
      return true;
    } catch (error, stackTrace) {
      if (error is CameraException &&
          (error.code == 'notImplemented' || error.code == 'notSupported')) {
        _previewUnsupported = true;
        return true;
      }
      // The requested state is not evidence of the applied native state.
      _previewPaused = null;
      log.error(
        'camera',
        'cannot change native preview state',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<void> _startStream({int? resumeRequest}) async {
    final device = _device;
    if (device == null) return;
    // A failed stop may have left a callback from an invalidated epoch.
    if (device.isStreamingImages) await device.stopImageStream();
    if (_disposed) {
      // The camera is not wanted any more: it is released instead of being
      // left open for nothing.
      await _release(device);
      return;
    }
    if (_paused ||
        (resumeRequest != null && resumeRequest != _pauseRequestGeneration)) {
      return;
    }
    final generation = ++_streamGeneration;
    await device.startImageStream((frame) => _onFrame(frame, generation));
  }

  Future<void> _teardownLive() async {
    final device = _device;
    _device = null;
    _generation++;
    _streamGeneration++;
    motion?.resetScene();
    // Another camera may be opened next: the colours of this one are dropped.
    signals?.clearScene();
    if (device == null) return;
    try {
      if (device.isStreamingImages) {
        await device.stopImageStream();
      }
    } catch (error) {
      log.warning('camera', 'the stream did not stop cleanly: $error');
    }
    await _release(device);
  }

  /// Closes [device] and forgets it when it is the one in use.
  Future<void> _release(CameraDevice device) async {
    if (identical(_device, device)) _device = null;
    try {
      await device.dispose();
    } catch (error) {
      log.warning('camera', 'the camera was not closed cleanly: $error');
    }
  }

  Future<void> _onFrame(RawFrame frame, int generation) async {
    if (_disposed || _paused || generation != _streamGeneration) {
      // The camera is hidden: the frame is not converted and the light of
      // the scene is not measured.
      return;
    }
    if (_converting) {
      metrics.recordDroppedFrame();
      return;
    }
    _converting = true;
    final started = clock();
    try {
      final conversion = converter.convert(
        frame,
        rotationDegrees: _rotationDegrees(),
        mirror: _shouldMirror(),
      );
      light.addLuma(conversion.meanLuma);
      // The colourfulness of the frame feeds the contextual lanes. Only the
      // numbers of the frame travel: the pixels stay in the conversion.
      final colorfulness = conversion.colorfulness;
      if (colorfulness != null) signals?.addScene(colorfulness);
      motion?.addSceneFrame(
        conversion.pixels,
        conversion.width,
        conversion.height,
        lumaGrid: conversion.sceneLuma,
      );

      final published = await _imageFactory(conversion);
      if (_disposed || _paused || generation != _streamGeneration) {
        published.dispose();
        return;
      }
      final previous = this.frame.value;
      this.frame.value = published;
      previous?.dispose();

      final elapsed = Duration(microseconds: clock() - started);
      metrics.recordFrame(
        conversionTime: elapsed,
        streamWidth: frame.width,
        streamHeight: frame.height,
        previewWidth: conversion.width,
        previewHeight: conversion.height,
      );
      _logMetrics(elapsed, frame, conversion);
    } catch (error, stackTrace) {
      log.error('camera', 'the frame conversion failed', error, stackTrace);
    } finally {
      _converting = false;
    }
  }

  void _logMetrics(
    Duration elapsed,
    RawFrame frame,
    FrameConversion conversion,
  ) {
    final now = clock();
    if (_lastLogMicros != 0 && now - _lastLogMicros < 5000000) return;
    _lastLogMicros = now;
    log.info(
      'camera',
      'stream ${frame.width}x${frame.height} preview=${conversion.width}x'
          '${conversion.height} fps=${metrics.value.fps.toStringAsFixed(1)} '
          'conversion=${elapsed.inMicroseconds / 1000}ms luma='
          '${conversion.meanLuma.toStringAsFixed(1)}',
    );
  }

  static Future<ui.Image> _toUiImage(FrameConversion conversion) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      conversion.pixels,
      conversion.width,
      conversion.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
      rowBytes: conversion.width * 4,
    );
    return completer.future;
  }

  Future<StillCapture> _captureAtHighestResolution(
    CameraDescription description, {
    bool deferDecode = false,
  }) async {
    await _teardownLive();
    final generation = _generation;
    CameraDevice? still;
    String? path;
    try {
      still = _deviceFactory(description, ResolutionPreset.max);
      await still.initialize();
      if (_disposed || generation != _generation) {
        throw CameraException(
          'camera-closed',
          'The camera was closed while the picture was taken',
        );
      }
      final takeStart = clock();
      path = await still.takePicture();
      final bytes = await File(path).readAsBytes();
      final takeMs = (clock() - takeStart) / 1000;

      if (deferDecode) return await _encodedCapture(bytes, description, takeMs);
      final decodeStart = clock();
      final image = await decodeStill(bytes, description);
      final decodeMs = (clock() - decodeStart) / 1000;

      log.info(
        'camera',
        'still captured ${image.width}x${image.height} bytes=${bytes.length} '
            'take=${takeMs.toStringAsFixed(0)}ms decode=${decodeMs.toStringAsFixed(0)}ms',
      );
      return StillCapture(
        image: image,
        decodedMirrored: _decodedMirrored(bytes),
        timings: CaptureTimings(takeMs: takeMs, decodeMs: decodeMs),
      );
    } finally {
      // The picture of the camera is read into memory, so the file it wrote
      // is not needed any more. It is deleted even when the reading or the
      // decoding failed, so it never stays in the cache of the device.
      if (path != null) await _deleteStill(path);
      try {
        await still?.dispose();
      } catch (error, stackTrace) {
        log.error(
          'camera',
          'the camera of the picture was not closed cleanly',
          error,
          stackTrace,
        );
      }
      try {
        await _openLive();
      } catch (error, stackTrace) {
        log.error(
          'camera',
          'the live stream did not recover',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<StillCapture> _captureWith(
    CameraDevice device,
    CameraDescription description, {
    bool deferDecode = false,
  }) async {
    final takeStart = clock();
    String? path;
    try {
      path = await device.takePicture();
      final bytes = await File(path).readAsBytes();
      final takeMs = (clock() - takeStart) / 1000;

      if (deferDecode) return await _encodedCapture(bytes, description, takeMs);
      final decodeStart = clock();
      final image = await decodeStill(bytes, description);
      final decodeMs = (clock() - decodeStart) / 1000;

      return StillCapture(
        image: image,
        decodedMirrored: _decodedMirrored(bytes),
        timings: CaptureTimings(takeMs: takeMs, decodeMs: decodeMs),
      );
    } finally {
      // The file of the camera is deleted even when the reading or the
      // decoding failed, so it never stays in the cache of the device.
      if (path != null) await _deleteStill(path);
    }
  }

  Future<StillCapture> _encodedCapture(
    Uint8List bytes,
    CameraDescription description,
    double takeMs,
  ) async {
    final source = await EncodedStill.read(
      bytes,
      (data, width, height) => decodeStill(
        data,
        description,
        targetWidth: width,
        targetHeight: height,
      ),
      swapAxes: (width, height) {
        if (preserveSourceOrientation) return false;
        if (readExifOrientation(bytes) != null) return false;
        final rotation = _decideStillRotation(
          exif: null,
          sensorOrientation: description.sensorOrientation,
          decodedWidth: width,
          decodedHeight: height,
        ).rotation;
        return rotation == 90 || rotation == 270;
      },
    );
    log.info(
      'capture',
      'take=${takeMs.toStringAsFixed(0)}ms '
          'native=${source.width}x${source.height} bytes=${bytes.length}',
    );
    return StillCapture.encoded(
      source: source,
      decodedMirrored: _decodedMirrored(bytes),
      timings: CaptureTimings(takeMs: takeMs),
    );
  }

  static bool _decodedMirrored(Uint8List bytes) =>
      ExifOrientation.fromValue(readExifOrientation(bytes) ?? 1)?.mirrored ??
      false;

  /// Decodes a JPEG into an upright image, capped at [stillMaxSide].
  ///
  /// EXIF AND ORIENTATION, what the code does and why:
  ///
  /// * Flutter's codec applies EXIF rotation and mirroring while decoding.
  ///   Applying the tag again would rotate or mirror the picture twice.
  /// * On iOS the plugin writes the picture with `fileDataRepresentation()`,
  ///   which keeps the pixels in the orientation of the sensor and records the
  ///   rotation in the EXIF tag. The tag has to be honoured.
  /// * On Android the plugin sets the target rotation of the `ImageCapture`
  ///   use case to the rotation of the display, so CameraX already turns the
  ///   picture. The EXIF tag is read, and is the authoritative description of
  ///   the picture: when it is present the rotation it says is honoured, and
  ///   the aspect of the decoded picture is not used to second-guess it.
  /// * The aspect heuristic is only used when the picture has no EXIF at all:
  ///   the sensor orientation is the only hint in that case, and a picture
  ///   that is still landscape after decoding has to be turned, while one
  ///   that is already portrait is left alone.
  ///
  /// The returned image belongs to the caller, who has to dispose it.
  Future<ui.Image> decodeStill(
    Uint8List bytes,
    CameraDescription description, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    int width = 0;
    int height = 0;
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      width = descriptor.width;
      height = descriptor.height;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }

    final longest = math.max(width, height);
    final scale = longest > stillMaxSide
        ? stillMaxSide / longest.toDouble()
        : 1.0;
    targetWidth ??= math.max(1, (width * scale).round());
    targetHeight ??= math.max(1, (height * scale).round());

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final ui.Image decoded;
    try {
      final frame = await codec.getNextFrame();
      decoded = frame.image;
    } finally {
      // The codec holds the picture until it is released. The frame it gave
      // is owned by the caller of this method.
      codec.dispose();
    }

    final exifValue = readExifOrientation(bytes);
    final exif = exifValue == null
        ? null
        : ExifOrientation.fromValue(exifValue);

    if (preserveSourceOrientation) return decoded;

    if (exif != null) {
      log.info(
        'camera',
        'still decoded ${decoded.width}x${decoded.height} '
            'exif=$exifValue applied by codec',
      );
      return decoded;
    }

    final rotationMirror = _decideStillRotation(
      exif: exif,
      sensorOrientation: description.sensorOrientation,
      decodedWidth: decoded.width,
      decodedHeight: decoded.height,
    );

    log.info(
      'camera',
      'still decoded ${decoded.width}x${decoded.height} '
          'exif=${exif == null ? 'none' : exif.rotationDegrees} '
          'rotation=${rotationMirror.rotation}',
    );

    if (rotationMirror.rotation == 0 && !rotationMirror.mirrored) {
      return decoded;
    }
    try {
      return await _rotate(
        decoded,
        rotationMirror.rotation,
        rotationMirror.mirrored,
      );
    } finally {
      decoded.dispose();
    }
  }

  /// The clockwise rotation and horizontal flip a still needs to be upright.
  ///
  /// When the picture has EXIF, its tag is authoritative: it is the value
  /// the camera wrote to describe the picture, and second-guessing it with
  /// the decoded aspect can turn a correct landscape shot into a portrait
  /// one (see review R2-03).
  ///
  /// When the picture has no EXIF, the sensor orientation is the only
  /// hint available, and the aspect of the decoded picture is used as a
  /// fallback so that a sensor-mounted landscape shot still ends up
  /// portrait (or the other way round) on devices that do not write EXIF.
  @visibleForTesting
  ({int rotation, bool mirrored}) decideStillRotation({
    required ExifOrientation? exif,
    required int sensorOrientation,
    required int decodedWidth,
    required int decodedHeight,
  }) => _decideStillRotation(
    exif: exif,
    sensorOrientation: sensorOrientation,
    decodedWidth: decodedWidth,
    decodedHeight: decodedHeight,
  );

  static ({int rotation, bool mirrored}) _decideStillRotation({
    required ExifOrientation? exif,
    required int sensorOrientation,
    required int decodedWidth,
    required int decodedHeight,
  }) {
    var rotation = exif?.rotationDegrees ?? sensorOrientation;
    var mirrored = exif?.mirrored ?? false;

    if (exif == null) {
      // No EXIF: fall back to the aspect heuristic so a sensor-mounted
      // landscape shot without a tag still ends up portrait.
      if (decodedWidth > decodedHeight && (rotation == 0 || rotation == 180)) {
        rotation = 90;
      } else if (decodedWidth < decodedHeight &&
          (rotation == 90 || rotation == 270)) {
        rotation = 0;
      }
    }

    return (rotation: rotation, mirrored: mirrored);
  }

  /// Removes the temporary file that the camera wrote.
  ///
  /// The picture is read into memory, so the file of the camera is not
  /// needed any more and must not stay in the cache of the device.
  Future<void> _deleteStill(String path) async {
    try {
      if (path.isEmpty) return;
      final still = File(path);
      if (!still.existsSync()) return;
      await still.delete();
      log.info('camera', 'the picture of the camera was deleted');
    } catch (_) {
      // The system cleans its own cache when it needs to.
      log.warning('camera', 'the picture of the camera was not deleted');
    }
  }

  Future<ui.Image> _rotate(ui.Image image, int degrees, bool mirrored) async {
    final swap = degrees == 90 || degrees == 270;
    final width = (swap ? image.height : image.width).toDouble();
    final height = (swap ? image.width : image.height).toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.save();
    canvas.translate(width / 2, height / 2);
    canvas.rotate(degrees * math.pi / 180);
    if (mirrored) canvas.scale(-1, 1);
    canvas.translate(-image.width / 2, -image.height / 2);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width.round(), height.round());
    } finally {
      picture.dispose();
    }
  }

  /// The clockwise rotation needed to show the frames upright.
  int _rotationDegrees() {
    final description = _description;
    if (description == null) return 0;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The iOS implementation of the plugin already turns the video stream
      // to the orientation of the device, so the frames arrive upright.
      return 0;
    }
    // The preview stays portrait regardless of physical handset pose; only
    // the still receives the extra gravity-derived quarter turn.
    return description.sensorOrientation;
  }

  /// Whether the frames have to be flipped horizontally.
  bool _shouldMirror() {
    final description = _description;
    if (description == null) return false;
    if (description.lensDirection != CameraLensDirection.front) return false;
    // The iOS implementation of the plugin mirrors the front camera stream
    // itself; on Android the frames come raw and the mirror is done here.
    return defaultTargetPlatform != TargetPlatform.iOS;
  }

  static CameraDescription _pick(
    List<CameraDescription> cameras,
    CameraLensDirection direction,
  ) {
    for (final camera in cameras) {
      if (camera.lensDirection == direction) return camera;
    }
    return cameras.first;
  }
}
