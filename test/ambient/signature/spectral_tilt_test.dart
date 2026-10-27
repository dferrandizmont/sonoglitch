import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/spectral_tilt.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';

SpectrumBands density(double slope) {
  double band(double lo, double hi) =>
      -65 +
      slope * math.log(math.sqrt(lo * hi) / 707.1067811865476) / math.ln2 +
      10 * math.log(hi - lo) / math.ln10;
  return (bass: band(20, 250), mid: band(250, 2000), treble: band(2000, 8000));
}

void main() {
  for (final slope in [0.0, -3.0, 6.0, -6.0, 12.0, -12.0]) {
    test('density slope $slope dB/oct uses actual native widths', () {
      expect(
        spectralTilt(density(slope)),
        closeTo((slope / 6).clamp(-1.0, 1.0), 1e-12),
      );
    });
  }
  test('floor and invalid input are neutral', () {
    expect(spectralTilt((bass: -90, mid: -89, treble: -87)), 0);
    expect(spectralTilt((bass: -10, mid: double.nan, treble: -20)), 0);
    expect(spectralTilt((bass: -10, mid: -20, treble: double.infinity)), 0);
    expect(spectralTilt(density(6), floors: density(6)), 0);
  });
  test('one-second filter, stale reset, and lifecycle use injected time', () {
    var now = 0;
    final filter = SpectralTiltFilter(clock: () => now);
    expect(filter.value, 0);
    filter.add(density(6), now);
    for (var i = 0; i < 10; i++) {
      now += 100000;
      filter.add(density(6), now);
    }
    expect(filter.value, closeTo(1 - math.exp(-1), 1e-12));
    filter.add(density(-6), now - 1);
    expect(filter.value, closeTo(1 - math.exp(-1), 1e-12));
    now += 1000001;
    expect(filter.value, 0);
    expect(filter.isFresh, isFalse);
    filter.add(density(-6), now);
    expect(filter.value, 0);
    filter.stop();
    filter.start();
    expect(filter.isFresh, isFalse);
  });
  test('raw getter preserves pre-normalization values and clears on stop', () {
    var now = 10;
    final service = SpectrumService(
      source: const NoopSpectrumSource(),
      clock: () => now,
    );
    expect(service.lastRawReading, isNull);
    const bands = (bass: -43.0, mid: -55.0, treble: -64.0);
    service.addReading(bands);
    expect(service.lastRawReading, (bands: bands, timeMicros: 10));
    now++;
    service.addReading((bass: double.nan, mid: 0, treble: 0));
    expect(service.lastRawReading!.timeMicros, 10);
    service.enabled = false;
    expect(service.lastRawReading, isNull);
    service.stop();
    service.enabled = true;
    expect(service.lastRawReading, isNull);
  });
}
