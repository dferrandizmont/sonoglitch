import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'raw_frame.dart';

/// The camera that the service drives.
///
/// It is an interface so the tests can use a camera that does not touch the
/// hardware, and so the types of the plugin stay inside this file.
abstract interface class CameraDevice {
  /// Whether the stream of pictures is running.
  bool get isStreamingImages;

  /// The size of the preview.
  ui.Size get previewSize;

  /// The orientation of the device when the camera was opened.
  DeviceOrientation get deviceOrientation;

  /// Opens the camera.
  Future<void> initialize();

  /// Starts the stream of pictures and calls [onFrame] with every frame.
  Future<void> startImageStream(void Function(RawFrame frame) onFrame);

  /// Stops the stream of pictures.
  Future<void> stopImageStream();

  /// Pauses or resumes the native preview independently of image analysis.
  Future<void> pausePreview();
  Future<void> resumePreview();

  /// Takes a picture and returns the path of the file it was written to.
  Future<String> takePicture();

  /// Closes the camera and releases every resource.
  Future<void> dispose();
}

/// Builds the camera that the service drives.
///
/// The preset of the resolution tells how big the pictures are: the live
/// stream uses a small one and the still capture the biggest one the camera
/// offers.
typedef CameraDeviceFactory = CameraDevice Function(
  CameraDescription description,
  ResolutionPreset resolutionPreset,
);

/// The cameras of the device.
typedef CameraLister = Future<List<CameraDescription>> Function();

/// Builds the camera of the plugin.
CameraDevice pluginCameraDevice(
  CameraDescription description,
  ResolutionPreset resolutionPreset,
) {
  final controller = CameraController(
    description,
    resolutionPreset,
    // The camera never records audio: the microphone is only read, on its
    // own, for the noise measurement.
    enableAudio: false,
    imageFormatGroup: _imageFormatGroup,
  );
  return PluginCameraDevice(controller);
}

/// The image format group that matches the platform.
ImageFormatGroup get _imageFormatGroup {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return ImageFormatGroup.bgra8888;
  }
  return ImageFormatGroup.yuv420;
}

/// The camera of the plugin.
class PluginCameraDevice implements CameraDevice {
  /// Wraps the controller of the plugin.
  PluginCameraDevice(this._controller);

  final CameraController _controller;
  int _streamGeneration = 0;
  Completer<void>? _analyzerReady;
  Future<void>? _streamStarting;

  @override
  bool get isStreamingImages => _controller.value.isStreamingImages;

  @override
  ui.Size get previewSize => _controller.value.previewSize ?? ui.Size.zero;

  @override
  DeviceOrientation get deviceOrientation =>
      _controller.value.deviceOrientation;

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    // EXIF describes a portrait-locked base photo. Physical gravity is applied
    // later, exactly once, before export chooses a crop or paints its signature.
    await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
  }

  @override
  Future<void> startImageStream(void Function(RawFrame frame) onFrame) async {
    final generation = ++_streamGeneration;
    final ready = Completer<void>();
    _analyzerReady = ready;
    final starting = _controller.startImageStream((image) {
      // CameraX 0.7.6 installs its analyzer in an asynchronous onListen.
      // The first frame proves installation has reached setAnalyzer; the
      // public startImageStream future only confirms the subscription.
      if (!ready.isCompleted) ready.complete();
      if (generation == _streamGeneration) onFrame(_toRawFrame(image));
    });
    _streamStarting = starting;
    try {
      await starting;
    } catch (_) {
      if (identical(_analyzerReady, ready)) _analyzerReady = null;
      rethrow;
    } finally {
      if (identical(_streamStarting, starting)) _streamStarting = null;
    }
  }

  @override
  Future<void> stopImageStream() async {
    // Invalidate delivery immediately, but leave the subscription alive until
    // installation is known to have finished. Clearing earlier can be undone
    // by CameraX's pending setAnalyzer. No timeout can prove installation.
    _streamGeneration++;
    await _streamStarting;
    final ready = _analyzerReady;
    if (ready != null) await ready.future;
    if (_controller.value.isStreamingImages) {
      await _controller.stopImageStream();
    }
    if (identical(_analyzerReady, ready)) _analyzerReady = null;
  }

  @override
  Future<void> pausePreview() => _controller.pausePreview();

  @override
  Future<void> resumePreview() => _controller.resumePreview();

  @override
  Future<String> takePicture() async {
    final file = await _controller.takePicture();
    return file.path;
  }

  @override
  Future<void> dispose() async {
    try {
      await stopImageStream();
    } finally {
      await _controller.dispose();
    }
  }
}

/// Turns the picture of the plugin into the raw frame of the converter.
RawFrame _toRawFrame(CameraImage image) {
  final planes = <RawPlane>[];
  for (final plane in image.planes) {
    planes.add(
      RawPlane(
        bytes: plane.bytes,
        bytesPerRow: plane.bytesPerRow,
        bytesPerPixel: plane.bytesPerPixel ?? 1,
      ),
    );
  }
  final format = image.format.group == ImageFormatGroup.bgra8888
      ? FrameFormat.bgra8888
      : FrameFormat.yuv420;
  return RawFrame(
    width: image.width,
    height: image.height,
    format: format,
    planes: planes,
  );
}
