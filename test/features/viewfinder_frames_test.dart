import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  /// The camera of the viewfinder and the cameras it made.
  ({CameraService camera, List<FakeCameraDevice> devices}) buildCamera(
    CountingConverter converter,
  ) {
    final devices = <FakeCameraDevice>[];
    final camera = CameraService(
      light: LightService(ambientLight: FakeAmbientLightSource()),
      log: DebugLog(),
      converter: converter,
      lister: () async => const [description],
      deviceFactory: (description, preset) {
        final device = FakeCameraDevice();
        devices.add(device);
        return device;
      },
    );
    return (camera: camera, devices: devices);
  }

  testWidgets(
    'no frame is converted while another route covers the viewfinder',
    (tester) async {
      final converter = CountingConverter();
      final built = buildCamera(converter);
      await pumpViewfinder(tester, camera: built.camera);
      await tester.pump();

      expect(built.devices, hasLength(1));
      final device = built.devices.single;
      expect(
        device.starts,
        1,
        reason: 'The stream must run while the viewfinder is visible',
      );

      device.pushFrame(buildTestFrame());
      await tester.pump();
      expect(converter.conversions, 1, reason: 'The frame must be converted');

      // The styles route covers the viewfinder.
      final context = tester.element(find.byType(ViewfinderScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(built.camera.isPaused, isTrue);
      expect(device.stops, 1, reason: 'The stream must stop');
      expect(
        device.closings,
        0,
        reason: 'The camera must stay open while the viewfinder is covered',
      );

      device.pushFrame(buildTestFrame());
      await tester.pump();
      expect(
        converter.conversions,
        1,
        reason: 'No frame may be converted while the viewfinder is covered',
      );

      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(built.camera.isPaused, isFalse);
      expect(device.starts, 2, reason: 'The stream must come back');
      expect(device.closings, 0, reason: 'The camera must not be opened again');

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('no frame is converted while the app is in the background', (
    tester,
  ) async {
    final converter = CountingConverter();
    final built = buildCamera(converter);
    await pumpViewfinder(tester, camera: built.camera);
    await tester.pump();

    final device = built.devices.single;
    device.pushFrame(buildTestFrame());
    await tester.pump();
    expect(converter.conversions, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(built.camera.isPaused, isTrue);
    expect(device.stops, 1, reason: 'The stream must stop');
    expect(device.closings, 0, reason: 'The camera must stay open');

    device.pushFrame(buildTestFrame());
    await tester.pump();
    expect(
      converter.conversions,
      1,
      reason: 'No frame may be converted while the app is in the background',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(built.camera.isPaused, isFalse);
    expect(device.starts, 2, reason: 'The stream must come back');
    expect(device.closings, 0, reason: 'The camera must not be opened again');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
