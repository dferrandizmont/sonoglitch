import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A source of the ambient light of the place, in lux.
///
/// The interface lets the light service read a fake sensor in the tests and
/// lets the platforms without a light sensor fall back to the brightness of
/// the picture.
abstract class AmbientLightSource {
  /// Creates a source.
  const AmbientLightSource();

  /// The readings of the sensor, in lux.
  Stream<double> get lux;

  /// Whether the source is able to deliver readings.
  ///
  /// A source that is available can still fail later: the failure arrives
  /// as an error of the stream and the light falls back to the picture.
  bool get available;
}

/// The light sensor of the Android platform.
///
/// The readings come from an event channel, so the sensor of the phone is
/// only read while the Dart side is listening.
class EventChannelAmbientLightSource implements AmbientLightSource {
  /// Creates the source.
  const EventChannelAmbientLightSource();

  /// The channel the plugin of the platform listens to.
  static const EventChannel channel = EventChannel('sonoglitch/ambient_light');

  @override
  Stream<double> get lux => channel
      .receiveBroadcastStream()
      .where((event) => event is num)
      .map((event) => (event as num).toDouble());

  @override
  bool get available => true;
}

/// The source of the platforms without a light sensor.
class UnavailableAmbientLightSource implements AmbientLightSource {
  /// Creates the source.
  const UnavailableAmbientLightSource();

  @override
  Stream<double> get lux => const Stream<double>.empty();

  @override
  bool get available => false;
}

/// The source of the platform the app is running on.
AmbientLightSource platformAmbientLightSource() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return const EventChannelAmbientLightSource();
  }
  return const UnavailableAmbientLightSource();
}
