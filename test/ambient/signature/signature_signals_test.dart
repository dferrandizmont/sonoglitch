import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/signature/scene_signature.dart';
import 'package:sonoglitch/ambient/signature/signature_signals.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';

/// A clock the test moves by hand.
class FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

/// A magnetometer the test drives.
class FakeMagnetometer {
  final StreamController<SensorVector> _controller =
      StreamController<SensorVector>.broadcast(sync: true);

  Stream<SensorVector> Function() get source =>
      () => _controller.stream;

  void add(SensorVector field) => _controller.add(field);
}

const upright = (x: 0.0, y: 9.81, z: 0.0);
const east = (x: -50.0, y: 0.0, z: 0.0);

/// Bands with a density slope of [slope] dB per octave.
SpectrumBands density(double slope) {
  double band(double lo, double hi) =>
      -65 +
      slope * math.log(math.sqrt(lo * hi) / 707.1067811865476) / math.ln2 +
      10 * math.log(hi - lo) / math.ln10;
  return (bass: band(20, 250), mid: band(250, 2000), treble: band(2000, 8000));
}

/// The lanes of a neutral shot.
void expectNeutral(SignatureState lanes) {
  expect(lanes.warmth, 0);
  expect(lanes.hue, 0);
  expect(lanes.chromaAllowance, 1);
  expect(lanes.tilt, 0);
  expect(lanes.axisX, 1);
  expect(lanes.axisY, 0);
  expect(lanes.pulse, 0);
  expect(lanes.reserved, 0);
}

/// Builds the service with a magnetometer the test can drive.
SignatureSignals buildSignals({
  required FakeClock clock,
  FakeMagnetometer? magnetometer,
  DateTime Function()? localNow,
  RawSpectrumReading? Function()? spectrum,
  List<RawSpectrumReading> Function()? spectrumDrain,
}) {
  final input = magnetometer ?? FakeMagnetometer();
  return SignatureSignals(
    gravity: () => (vector: upright, timeMicros: clock.micros),
    magnetometer: input.source,
    localNow: localNow,
    spectrum: spectrum,
    spectrumDrain: spectrumDrain,
    clock: clock.call,
  );
}

/// Builds the service with the real spectrum service behind it, the way the
/// ambient controller wires it.
SignatureSignals buildSignalsWithSpectrum({
  required FakeClock clock,
  required SpectrumService spectrum,
}) => SignatureSignals(
  gravity: () => (vector: upright, timeMicros: clock.micros),
  magnetometer: () => const Stream<SensorVector>.empty(),
  spectrum: () => spectrum.lastRawReading,
  spectrumDrain: () => spectrum.drainRawReadings(),
  clock: clock.call,
);

void main() {
  test('the lanes are neutral before any data', () {
    final clock = FakeClock();
    final signals = buildSignals(clock: clock);
    expectNeutral(signals.moodLanes());
    // The producers are idle until the service starts.
    signals.start();
    expectNeutral(signals.moodLanes());
  });

  test('the civil palette follows the wall clock at about one hertz', () {
    final clock = FakeClock();
    var wall = DateTime(2024, 6, 21, 3);
    final signals = buildSignals(clock: clock, localNow: () => wall);
    signals.start();
    signals.update();
    // Three in the morning is the coldest hour of the curve.
    expect(signals.moodLanes().warmth, -1);

    // The palette is not refreshed on every tick.
    wall = DateTime(2024, 6, 21, 12);
    signals.update();
    expect(signals.moodLanes().warmth, -1);

    // One second later it is refreshed.
    clock.advance(const Duration(seconds: 1));
    signals.update();
    expect(signals.moodLanes().warmth, closeTo(0.15, 1e-12));
    expect(signals.moodLanes().hue, inInclusiveRange(-1, 1));
  });

  test(
    'the orientation axis follows the magnetometer and the gravity',
    () async {
      final clock = FakeClock();
      final magnetometer = FakeMagnetometer();
      final signals = buildSignals(clock: clock, magnetometer: magnetometer);
      signals.start();
      await Future<void>.value();
      expect(magnetometer._controller.hasListener, isTrue);

      for (var i = 0; i <= 8; i++) {
        clock.advance(const Duration(milliseconds: 100));
        magnetometer.add(east);
      }
      final lanes = signals.moodLanes();
      expect(lanes.axisY, greaterThan(0));
      expect(
        lanes.axisX * lanes.axisX + lanes.axisY * lanes.axisY,
        closeTo(1, 1e-12),
      );
      expect(lanes.axisX, inInclusiveRange(-1, 1));
      expect(lanes.axisY, inInclusiveRange(-1, 1));

      // The subscription is cancelled when the service stops.
      signals.stop();
      await Future<void>.value();
      expect(magnetometer._controller.hasListener, isFalse);
      expectNeutral(signals.moodLanes());
    },
  );

  test('the spectral tilt follows the raw spectrum', () {
    final clock = FakeClock();
    final signals = buildSignals(clock: clock);
    signals.start();
    for (var i = 0; i < 20; i++) {
      clock.advance(const Duration(milliseconds: 100));
      signals.addSpectrum(density(6), clock.micros);
    }
    // A brightness slope of six decibels per octave is the top of the scale.
    expect(signals.moodLanes().tilt, inInclusiveRange(0.8, 0.9));

    // A dark slope inverts the lane.
    for (var i = 0; i < 40; i++) {
      clock.advance(const Duration(milliseconds: 100));
      signals.addSpectrum(density(-6), clock.micros);
    }
    expect(signals.moodLanes().tilt, inInclusiveRange(-1, -0.9));
  });

  test('the rhythmic pulse follows the raw spectrum', () {
    final clock = FakeClock();
    final signals = buildSignals(clock: clock);
    signals.start();
    const bpm = 120.0;
    final period = 60000000 / bpm;
    for (var time = 0; time <= 10000000; time += 10000) {
      clock.micros = time;
      final position = time % period;
      final double kick = position < 70000 ? 1 - position / 70000 : 0;
      signals.addSpectrum((
        bass: -75 + 55 * kick,
        mid: -75 + 20 * kick,
        treble: -78 + 8 * kick,
      ), time);
    }
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      clock.advance(const Duration(milliseconds: 10));
      final pulse = signals.moodLanes().pulse;
      expect(pulse, inInclusiveRange(-1, 1));
      peak = math.max(peak, pulse.abs());
    }
    expect(peak, greaterThan(0.5));
  });

  test('the chroma allowance follows the scene and falls back to neutral', () {
    final clock = FakeClock();
    final signals = buildSignals(clock: clock);
    signals.start();
    signals.addScene(const SceneColorReading(allowance: .65));
    expect(signals.moodLanes().chromaAllowance, 1);

    clock.advance(const Duration(milliseconds: 100));
    signals.addScene(const SceneColorReading(allowance: .65));
    expect(
      signals.moodLanes().chromaAllowance,
      closeTo(1 - .35 * (1 - math.exp(-.2)), 1e-12),
    );

    // A frame that is more than a second old is not used.
    clock.advance(const Duration(milliseconds: 1001));
    expect(signals.moodLanes().chromaAllowance, 1);

    // Another camera forgets the colours of the previous one.
    clock.advance(const Duration(milliseconds: 100));
    signals.addScene(const SceneColorReading(allowance: .65));
    signals.clearScene();
    expect(signals.moodLanes().chromaAllowance, 1);
  });

  test('the spectrum is polled once per timestamp', () {
    final clock = FakeClock();
    final signals = buildSignals(
      clock: clock,
      spectrum: () => (bands: density(6), timeMicros: clock.micros),
    );
    signals.start();
    signals.update();
    expect(signals.moodLanes().tilt, 0);

    clock.advance(const Duration(milliseconds: 100));
    signals.update();
    final first = signals.moodLanes().tilt;
    expect(first, greaterThan(0));

    // The same reading again does not move the filter.
    signals.update();
    expect(signals.moodLanes().tilt, first);
  });

  test('every reading between two ticks reaches the rhythm tracker', () {
    final clock = FakeClock();
    final spectrum = SpectrumService(
      source: const NoopSpectrumSource(),
      clock: clock.call,
    );
    final signals = buildSignalsWithSpectrum(clock: clock, spectrum: spectrum);
    signals.start();

    // A quiet reading, a hit and the fall of it, all between two ticks.
    spectrum.addReading((bass: -75, mid: -75, treble: -75));
    clock.micros = 10000;
    spectrum.addReading((bass: -20, mid: -60, treble: -60));
    clock.micros = 20000;
    spectrum.addReading((bass: -75, mid: -75, treble: -75));

    signals.update();
    expect(
      signals.rhythmAttacks,
      1,
      reason: 'The rise must reach the tracker, not only the last reading',
    );
  });

  test('a source without a drain loses the rise between two ticks', () {
    final clock = FakeClock();
    final latest = <RawSpectrumReading>[];
    final signals = buildSignals(
      clock: clock,
      spectrum: () => latest.isEmpty ? null : latest.last,
    );
    signals.start();

    latest.add((bands: (bass: -75, mid: -75, treble: -75), timeMicros: 1000));
    latest.add((bands: (bass: -20, mid: -60, treble: -60), timeMicros: 11000));
    latest.add((bands: (bass: -75, mid: -75, treble: -75), timeMicros: 21000));

    signals.update();
    expect(
      signals.rhythmAttacks,
      0,
      reason: 'Only the last reading is polled, so the hit is lost',
    );
  });

  test('every reading between two ticks reaches the tilt filter', () {
    final clock = FakeClock();
    final spectrum = SpectrumService(
      source: const NoopSpectrumSource(),
      clock: clock.call,
    );
    final signals = buildSignalsWithSpectrum(clock: clock, spectrum: spectrum);
    signals.start();

    spectrum.addReading(density(6));
    clock.micros = 500000;
    spectrum.addReading(density(-6));
    clock.micros = 1000000;
    spectrum.addReading(density(6));

    signals.update();
    // Three readings: the filter moved twice and the lane left the neutral
    // zero. With only the last reading the lane would still be at zero.
    expect(signals.moodLanes().tilt, greaterThan(0.1));
  });

  test('stop drops the transient values and a new start begins neutral', () {
    final clock = FakeClock();
    final signals = buildSignals(
      clock: clock,
      localNow: () => DateTime(2024, 6, 21, 12),
    );
    signals.start();
    signals.update();
    clock.advance(const Duration(milliseconds: 100));
    signals.addSpectrum(density(6), clock.micros);
    clock.advance(const Duration(milliseconds: 100));
    signals.addSpectrum(density(6), clock.micros);
    signals.addScene(const SceneColorReading(allowance: .65));
    expect(signals.moodLanes().tilt, greaterThan(0));

    signals.stop();
    expectNeutral(signals.moodLanes());

    // The next session starts from the neutral lanes again.
    signals.start();
    expectNeutral(signals.moodLanes());
    signals.update();
    expect(signals.moodLanes().warmth, closeTo(0.15, 1e-12));
  });

  test('the platform magnetometer stays quiet without the platform', () async {
    // The plugin asks the platform for its sampling period with a call whose
    // result it drops. Without a platform the answer is an error, and it
    // must not reach the zone of the app.
    final stream = platformMagnetometer();
    final subscription = stream.listen((_) {}, onError: (Object _) {});
    await Future<void>.value();
    await subscription.cancel();
    await Future<void>.value();
  });

  test('the lanes of a fingerprint keep the shot they belong to', () {
    final clock = FakeClock();
    final signals = buildSignals(
      clock: clock,
      localNow: () => DateTime(2024, 6, 21, 12),
    );
    signals.start();
    signals.update();
    const fingerprint = SignatureState(x: 0.25, y: 0.5, z: 0.75, w: 0.1);
    final merged = signals.applyLanes(fingerprint);
    expect(merged.x, 0.25);
    expect(merged.y, 0.5);
    expect(merged.z, 0.75);
    expect(merged.w, 0.1);
    expect(merged.warmth, closeTo(0.15, 1e-12));
  });
}
