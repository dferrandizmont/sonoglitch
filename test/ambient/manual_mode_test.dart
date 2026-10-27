import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/app_config.dart';

import '../support/fakes.dart';

void main() {
  test('a build that asks for it starts in manual mode', () {
    if (!AppConfig.manualMode) {
      markTestSkipped(
        'The build must ask for the manual values: '
        '--dart-define=SONOGLITCH_MANUAL=0.9,0.1,0',
      );
      return;
    }

    final controller = AmbientController(
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      noise: NoiseService(decibelStream: const Stream<double>.empty()),
      motion: MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
      ),
      light: LightService(ambientLight: FakeAmbientLightSource()),
    );

    expect(controller.isManual, isTrue);
    expect(controller.value.noise, AppConfig.manualValues![0]);
    expect(controller.value.light, AppConfig.manualValues![1]);
    expect(controller.value.motion, AppConfig.manualValues![2]);
  });
}
