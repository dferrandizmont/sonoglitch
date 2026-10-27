import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/camera/camera_device.dart';

const _description = CameraDescription(
  name: 'test',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

// Models CameraX onListen: subscribing returns before setAnalyzer runs.
class _DelayedAnalyzerController extends CameraController {
  _DelayedAnalyzerController() : super(_description, ResolutionPreset.medium);

  void Function(CameraImage)? callback;
  bool analyzerActive = false;
  int stops = 0;
  int closings = 0;

  @override
  Future<void> startImageStream(onLatestImageAvailable onAvailable) async {
    callback = onAvailable;
    value = value.copyWith(isStreamingImages: true);
  }

  void installAnalyzer() {
    analyzerActive = true;
    callback!(_UnusedImage());
  }

  @override
  Future<void> stopImageStream() async {
    stops++;
    analyzerActive = false;
    value = value.copyWith(isStreamingImages: false);
  }

  @override
  Future<void> dispose() async {
    closings++;
    // Like clearAnalyzer, this cannot cancel an installation still pending.
    analyzerActive = false;
    await super.dispose();
  }
}

// Canceled generations must never inspect or convert the image.
class _UnusedImage extends Fake implements CameraImage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stop waits for late analyzer installation and clears it afterwards',
    () async {
      final controller = _DelayedAnalyzerController();
      final device = PluginCameraDevice(controller);
      var deliveries = 0;
      await device.startImageStream((_) => deliveries++);
      expect(device.isStreamingImages, isTrue);
      expect(controller.analyzerActive, isFalse);
      final stopping = device.stopImageStream();
      expect(controller.stops, 0);
      // Installation completes only after cancellation was requested.
      controller.installAnalyzer();
      expect(controller.analyzerActive, isTrue);
      await stopping;
      expect(controller.analyzerActive, isFalse);
      expect(device.isStreamingImages, isFalse);
      expect(controller.stops, 1);
      expect(deliveries, 0);
      // Even callbacks already posted by native analysis cannot escape.
      controller.callback!(_UnusedImage());
      expect(deliveries, 0);
      await device.dispose();
      expect(controller.closings, 1);
    },
  );

  test('disposal also waits for pending analyzer installation', () async {
    final controller = _DelayedAnalyzerController();
    final device = PluginCameraDevice(controller);
    await device.startImageStream(
      (_) => fail('Disposed stream delivered a frame'),
    );
    final disposing = device.dispose();
    expect(controller.closings, 0);
    controller.installAnalyzer();
    await disposing;
    expect(controller.analyzerActive, isFalse);
    expect(controller.stops, 1);
    expect(controller.closings, 1);
  });

  test(
    'an old callback cannot satisfy readiness for a restarted stream',
    () async {
      final controller = _DelayedAnalyzerController();
      final device = PluginCameraDevice(controller);
      await device.startImageStream(
        (_) => fail('Canceled stream delivered a frame'),
      );
      final oldCallback = controller.callback!;
      final firstStop = device.stopImageStream();
      controller.installAnalyzer();
      await firstStop;
      await device.startImageStream(
        (_) => fail('Canceled stream delivered a frame'),
      );
      final secondStop = device.stopImageStream();
      oldCallback(_UnusedImage());
      await Future<void>.delayed(Duration.zero);
      expect(controller.stops, 1);
      controller.installAnalyzer();
      await secondStop;
      expect(controller.analyzerActive, isFalse);
      expect(controller.stops, 2);
      await device.dispose();
    },
  );
}
