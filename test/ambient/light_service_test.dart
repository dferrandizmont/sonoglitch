import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_light_source.dart';
import 'package:sonoglitch/ambient/light_service.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

/// A light sensor the test drives.
class FakeLightSource implements AmbientLightSource {
  FakeLightSource({this.available = true});

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

void main() {
  group('the mapping of the light', () {
    test('black is dark and white is bright', () {
      expect(LightService.mapLuma(0), 0);
      expect(LightService.mapLuma(255), closeTo(1, 0.0001));
    });

    test('the middle of the range stays in the middle', () {
      expect(LightService.mapLuma(127.5), closeTo(0.5, 0.001));
    });

    test('the curve is an S: the shadows darken and the lights brighten', () {
      expect(LightService.mapLuma(64), lessThan(64 / 255));
      expect(LightService.mapLuma(191), greaterThan(191 / 255));
    });

    test('a broken reading is zero', () {
      expect(LightService.mapLuma(double.nan), 0);
    });
  });

  group('the mapping of the lux', () {
    test('a dark room reads about 0.23', () {
      expect(LightService.mapLux(10), closeTo(0.2314, 0.001));
    });

    test('a lit room reads about 0.55', () {
      expect(LightService.mapLux(300), closeTo(0.5508, 0.001));
    });

    test('the shade of a tree reads about 0.82', () {
      expect(LightService.mapLux(5000), closeTo(0.822, 0.001));
    });

    test('the direct sun reaches the top of the scale', () {
      expect(LightService.mapLux(30000), closeTo(0.995, 0.001));
      expect(LightService.mapLux(100000), 1);
    });

    test('a broken reading is zero', () {
      expect(LightService.mapLux(double.nan), 0);
      expect(LightService.mapLux(-5), 0);
    });
  });

  group('LightService', () {
    test('smooths the readings', () {
      final clock = FakeClock();
      final service = LightService(clock: clock.call);
      service.addLuma(255);
      expect(service.rawLuma, 255);
      expect(service.level, greaterThan(0));
      expect(service.level, lessThan(1));

      clock.advance(const Duration(seconds: 5));
      service.addLuma(255);
      expect(service.level, closeTo(1, 0.01));
    });

    test('forgets the measurement when it is reset', () {
      final service = LightService();
      service.addLuma(255);
      service.reset();
      expect(service.rawLuma, isNull);
      expect(service.level, 0);
    });

    test('the sensor of the phone is the main source of the light', () async {
      final clock = FakeClock();
      final source = FakeLightSource();
      final service = LightService(ambientLight: source, clock: clock.call);
      service.start();
      addTearDown(source.close);

      source.addLux(300);
      await Future<void>.delayed(Duration.zero);
      expect(service.rawLux, 300);
      expect(service.hasLux, isTrue);

      clock.advance(const Duration(seconds: 2));
      source.addLux(300);
      await Future<void>.delayed(Duration.zero);

      // 0.75 of the lux of a lit room and nothing of the picture yet.
      expect(service.level, closeTo(0.75 * 0.5508, 0.01));
    });

    test('the picture rounds the reading of the sensor off', () async {
      final clock = FakeClock();
      final source = FakeLightSource();
      final service = LightService(ambientLight: source, clock: clock.call);
      service.start();
      addTearDown(source.close);

      source.addLux(300);
      service.addLuma(128);
      await Future<void>.delayed(Duration.zero);

      clock.advance(const Duration(seconds: 2));
      source.addLux(300);
      service.addLuma(128);
      await Future<void>.delayed(Duration.zero);

      final expected = 0.75 * 0.5508 + 0.25 * LightService.mapLuma(128);
      expect(service.level, closeTo(expected, 0.01));
    });

    test('a device without a light sensor uses the picture alone', () async {
      final clock = FakeClock();
      final source = FakeLightSource();
      final service = LightService(ambientLight: source, clock: clock.call);
      service.start();
      addTearDown(source.close);

      source.fail();
      await Future<void>.delayed(Duration.zero);
      expect(service.hasLux, isFalse);
      expect(service.rawLux, isNull);

      service.addLuma(255);
      clock.advance(const Duration(seconds: 2));
      service.addLuma(255);

      expect(service.level, closeTo(1, 0.01));
    });

    test('the sensor is only read while the service is started', () async {
      final source = FakeLightSource();
      final service = LightService(ambientLight: source);
      expect(service.isListening, isFalse);

      service.start();
      expect(service.isListening, isTrue);
      service.start();

      service.stop();
      expect(service.isListening, isFalse);
      service.stop();
      addTearDown(source.close);
    });

    test('a source without a sensor is never read', () {
      final service = LightService(
        ambientLight: const UnavailableAmbientLightSource(),
      );
      service.start();
      expect(service.isListening, isFalse);
      expect(service.hasLux, isFalse);
    });
  });
}
