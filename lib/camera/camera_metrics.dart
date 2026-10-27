import 'package:flutter/foundation.dart';

import '../ambient/clock.dart';

/// A snapshot of the camera measurements.
class CameraMetricsData {
  const CameraMetricsData({
    this.fps = 0,
    this.conversionMs = 0,
    this.streamWidth = 0,
    this.streamHeight = 0,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.frames = 0,
    this.droppedFrames = 0,
  });

  /// Frames per second of the camera stream.
  final double fps;

  /// Time spent converting a frame, in milliseconds.
  final double conversionMs;

  /// Width of the frames the camera delivers.
  final int streamWidth;

  /// Height of the frames the camera delivers.
  final int streamHeight;

  /// Width of the small image published to the UI.
  final int previewWidth;

  /// Height of the small image published to the UI.
  final int previewHeight;

  /// Number of frames converted since the camera started.
  final int frames;

  /// Number of frames dropped because the previous conversion was still
  /// running.
  final int droppedFrames;

  /// The resolution of the stream, as `WIDTHxHEIGHT`.
  String get streamResolution => '${streamWidth}x$streamHeight';
}

/// Measures the live camera: how many frames arrive, how long the conversion
/// takes and the resolution of the stream.
///
/// The values are published through the notifier so the debug panel can show
/// them without polling.
class CameraMetrics extends ValueNotifier<CameraMetricsData> {
  CameraMetrics({this.clock = stopwatchClock})
    : super(const CameraMetricsData());

  /// The clock used to measure the time between frames.
  final Clock clock;

  int _lastFrameMicros = 0;

  /// Records a converted frame.
  void recordFrame({
    required Duration conversionTime,
    required int streamWidth,
    required int streamHeight,
    required int previewWidth,
    required int previewHeight,
  }) {
    final now = clock();
    final previous = value;
    var fps = previous.fps;
    if (_lastFrameMicros != 0) {
      final micros = now - _lastFrameMicros;
      if (micros > 0) {
        final instant = 1000000 / micros;
        // A light exponential average, so the number does not jump around.
        fps = fps == 0 ? instant : fps * 0.85 + instant * 0.15;
      }
    }
    _lastFrameMicros = now;

    final conversionMs = previous.conversionMs == 0
        ? conversionTime.inMicroseconds / 1000
        : previous.conversionMs * 0.85 +
              (conversionTime.inMicroseconds / 1000) * 0.15;

    value = CameraMetricsData(
      fps: fps,
      conversionMs: conversionMs,
      streamWidth: streamWidth,
      streamHeight: streamHeight,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
      frames: previous.frames + 1,
      droppedFrames: previous.droppedFrames,
    );
  }

  /// Records a frame that was thrown away because the previous conversion was
  /// still running.
  void recordDroppedFrame() {
    final previous = value;
    value = CameraMetricsData(
      fps: previous.fps,
      conversionMs: previous.conversionMs,
      streamWidth: previous.streamWidth,
      streamHeight: previous.streamHeight,
      previewWidth: previous.previewWidth,
      previewHeight: previous.previewHeight,
      frames: previous.frames,
      droppedFrames: previous.droppedFrames + 1,
    );
  }

  /// Forgets the measurements, used when the camera is paused.
  void reset() {
    _lastFrameMicros = 0;
    value = const CameraMetricsData();
  }
}
