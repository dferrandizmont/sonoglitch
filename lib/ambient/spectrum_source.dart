import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Three native FFT band energies in dBFS. Audio samples never enter Dart.
typedef SpectrumBands = ({double bass, double mid, double treble});

/// One raw reading of the native spectrum, with its monotonic timestamp.
///
/// The timestamp is the monotonic clock of the pipeline, so the readings can
/// be ordered and aged without a wall clock.
typedef RawSpectrumReading = ({SpectrumBands bands, int timeMicros});

abstract interface class SpectrumSource {
  Stream<SpectrumBands> get bands;
}

class EventChannelSpectrumSource implements SpectrumSource {
  const EventChannelSpectrumSource();

  static const channel = EventChannel('sonoglitch/spectrum');

  @override
  Stream<SpectrumBands> get bands =>
      channel.receiveBroadcastStream().map((event) {
        if (event is! List ||
            event.length != 3 ||
            event.any((value) => value is! num || !value.isFinite)) {
          throw const FormatException('Expected three finite band energies');
        }
        return (
          bass: (event[0] as num).toDouble(),
          mid: (event[1] as num).toDouble(),
          treble: (event[2] as num).toDouble(),
        );
      });
}

class NoopSpectrumSource implements SpectrumSource {
  const NoopSpectrumSource();

  @override
  Stream<SpectrumBands> get bands => const Stream.empty();
}

SpectrumSource platformSpectrumSource() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? const EventChannelSpectrumSource()
    : const NoopSpectrumSource();
