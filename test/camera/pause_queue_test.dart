import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

/// A [FakeCameraDevice] whose [stopImageStream] and [startImageStream]
/// wait for optional gates, so the serial queue of the camera service can
/// be observed while it is busy.
class GatedCameraDevice extends FakeCameraDevice {
  GatedCameraDevice({this.pauseGate, this.startGate});

  Completer<void>? pauseGate;
  Completer<void>? startGate;

  @override
  Future<void> stopImageStream() async {
    await super.stopImageStream();
    final gate = pauseGate;
    if (gate != null && !gate.isCompleted) await gate.future;
  }

  @override
  Future<void> startImageStream(void Function(RawFrame frame) onFrame) async {
    final gate = startGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    await super.startImageStream(onFrame);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  test(
    'a queued pause followed by a resume ends up resumed, not mid-pause',
    () async {
      final devices = <GatedCameraDevice>[];
      final camera = CameraService(
        light: LightService(),
        log: DebugLog(),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = GatedCameraDevice();
          devices.add(device);
          return device;
        },
      );
      await camera.initialize();
      expect(devices.single.starts, 1);
      expect(devices.single.stops, 0);

      // Hold the serial queue open inside the first pause so the resume
      // is forced to enqueue behind it. With the bug, both queued
      // actions read `_paused == false` and called `_startStream()`,
      // so the camera never stops.
      final pauseGate = Completer<void>();
      devices.single.pauseGate = pauseGate;
      final startGate = Completer<void>();
      devices.single.startGate = startGate;

      // Enqueue pause, then resume without awaiting.
      final pauseFuture = camera.setPaused(true);
      final resumeFuture = camera.setPaused(false);

      // Release the first pause so the queue can run.
      pauseGate.complete();
      await pauseFuture;
      // The resume is now sitting on the gated start. Let the event
      // loop run once so any spurious call to start would happen here.
      await Future<void>.delayed(Duration.zero);

      // The live camera must not have been opened a second time while
      // the resume is still waiting.
      expect(
        devices.single.starts,
        equals(1),
        reason:
            'The resume must wait its turn, not call start while the '
            'pause is still in flight',
      );

      // Let the resume finish.
      startGate.complete();
      await resumeFuture;

      expect(
        devices.single.isStreamingImages,
        isTrue,
        reason:
            'A queued pause followed by a resume must leave the stream '
            'running',
      );
      // The pause stopped the stream once.
      expect(
        devices.single.stops,
        equals(1),
        reason: 'The pause must have called stopImageStream at least once',
      );
    },
  );
}
