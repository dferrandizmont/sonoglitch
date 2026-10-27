import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_light_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('sonoglitch/ambient_light');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('the light source of the platform', () {
    test('the readings of the plugin arrive as lux', () async {
      const source = EventChannelAmbientLightSource();
      expect(source.available, isTrue);

      final readings = <double>[];
      final subscription = source.lux.listen(readings.add);

      // The plugin of the platform sends a reading.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'sonoglitch/ambient_light',
            const StandardMethodCodec().encodeSuccessEnvelope(120.5),
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);

      expect(readings, [120.5]);

      await subscription.cancel();
    });

    test('the readings that are not numbers are ignored', () async {
      const source = EventChannelAmbientLightSource();
      final readings = <double>[];
      final subscription = source.lux.listen(readings.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'sonoglitch/ambient_light',
            const StandardMethodCodec().encodeSuccessEnvelope('dark'),
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);

      expect(readings, isEmpty);

      await subscription.cancel();
    });

    test('the platforms without a sensor give no readings', () async {
      const source = UnavailableAmbientLightSource();
      expect(source.available, isFalse);

      final readings = <double>[];
      final subscription = source.lux.listen(readings.add);
      await Future<void>.delayed(Duration.zero);

      expect(readings, isEmpty);

      await subscription.cancel();
    });
  });
}
