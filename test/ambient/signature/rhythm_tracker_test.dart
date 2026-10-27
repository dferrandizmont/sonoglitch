import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/rhythm_tracker.dart';

/// Narrow bass kicks sampled at 100 Hz, with native timestamps in microseconds.
void kicks(
  RhythmTracker tracker,
  void Function(int) setTime, {
  required double bpm,
  required int from,
  required int until,
}) {
  final period = 60000000 / bpm;
  for (var time = from; time <= until; time += 10000) {
    setTime(time);
    final position = (time - from) % period;
    final double kick = position < 70000 ? 1 - position / 70000 : 0;
    tracker.add(time, -75 + 55 * kick, -75 + 20 * kick, -78 + 8 * kick);
  }
}

/// The same kicks, but the alignment of the pulse with every hit is recorded.
///
/// The alignment is cos(phase) at the instant of the hit: one means the pulse
/// peaks exactly on the attack.
List<double> kickAlignments(
  RhythmTracker tracker,
  void Function(int) setTime, {
  required double bpm,
  required int from,
  required int until,
  int settledFrom = 0,
}) {
  final period = 60000000 / bpm;
  final alignments = <double>[];
  var previous = -100.0;
  for (var time = from; time <= until; time += 10000) {
    setTime(time);
    final position = (time - from) % period;
    final double kick = position < 70000 ? 1 - position / 70000 : 0;
    final bass = -75 + 55 * kick;
    tracker.add(time, bass, -75 + 20 * kick, -78 + 8 * kick);
    // The hit is the reading where the bass rises again.
    if (bass - previous > 20 && time >= settledFrom) {
      final confidence = tracker.confidence;
      if (confidence > 0) alignments.add(tracker.pulse / confidence);
    }
    previous = bass;
  }
  return alignments;
}

void main() {
  for (final tempo in [90.0, 100.0, 120.0, 160.0, 180.0]) {
    test('$tempo BPM kicks lock within ±3 BPM after ten seconds', () {
      var now = 0;
      final tracker = RhythmTracker(clock: () => now);
      kicks(tracker, (t) => now = t, bpm: tempo, from: 0, until: 10000000);
      expect(tracker.bpm, isNotNull);
      expect(tracker.bpm!, closeTo(tempo, 3));
      expect(tracker.confidence, greaterThanOrEqualTo(.65));
      expect(tracker.pulse, inInclusiveRange(-1, 1));
      final before = tracker.pulse;
      now += 1000;
      expect((tracker.pulse - before).abs(), lessThan(.03));
      now += 1000001;
      expect(tracker.confidence, 0);
      expect(tracker.pulse, 0);
      expect(tracker.bpm, isNull);
    });
  }
  for (final scenario in [
    'silence',
    'steady',
    'noise',
    'single',
    'irregular',
  ]) {
    test('$scenario has no rhythmic evidence', () {
      var now = 0;
      final tracker = RhythmTracker(clock: () => now);
      // Fixed irregular intervals; no random generator and no wall-clock waits.
      const hits = [
        1.0,
        1.23,
        2.04,
        3.19,
        3.57,
        5.06,
        5.33,
        6.11,
        7.28,
        8.61,
        9.04,
        10.46,
        10.79,
        11.47,
        13.12,
        13.41,
        14.37,
      ];
      for (now = 0; now <= 16000000; now += 10000) {
        final seconds = now / 1000000;
        final hit = scenario == 'single'
            ? seconds >= 1 && seconds < 1.07
            : scenario == 'irregular' &&
                  hits.any((h) => seconds >= h && seconds < h + .07);
        final db = switch (scenario) {
          'silence' => -110.0,
          'noise' =>
            -55 + .8 * math.sin(seconds * 17) + .6 * math.sin(seconds * 31),
          _ => hit ? -20.0 : -75.0,
        };
        tracker.add(now, db, db - 3, db - 6);
        expect(tracker.confidence, 0);
        expect(tracker.pulse, 0);
      }
    });
  }
  test('tempo change rejects the mixed window then reacquires new cadence', () {
    var now = 0;
    final tracker = RhythmTracker(clock: () => now);
    kicks(tracker, (t) => now = t, bpm: 120, from: 0, until: 10000000);
    expect(tracker.bpm!, closeTo(120, 3));
    kicks(tracker, (t) => now = t, bpm: 90, from: 10010000, until: 26010000);
    expect(tracker.bpm!, closeTo(90, 3));
    expect(tracker.confidence, greaterThanOrEqualTo(.65));
  });
  test(
    'resampling tolerates timestamp jitter, duplicates and faster native input',
    () {
      var now = 0;
      final tracker = RhythmTracker(clock: () => now);
      for (var i = 0; i <= 1000; i++) {
        now = i * 10000 + (i.isEven ? 0 : 2000);
        final phase = now % 500000;
        final double kick = phase < 100000 ? 1 - phase / 100000 : 0;
        tracker.add(now, -75 + 55 * kick, -75, -78);
        tracker.add(now, -75, -75, -78); // Duplicate timestamps cannot advance.
      }
      expect(tracker.bpm!, closeTo(120, 3));
    },
  );
  test('clear, invalid data, long gaps, and lifecycle forget all evidence', () {
    var now = 0;
    final tracker = RhythmTracker(clock: () => now);
    kicks(tracker, (t) => now = t, bpm: 120, from: 0, until: 10000000);
    expect(tracker.confidence, greaterThanOrEqualTo(.65));
    tracker.clear();
    expect(tracker.bufferedSamples, 0);
    expect(tracker.bufferedAttacks, 0);
    expect(tracker.pulse, 0);
    expect(tracker.bpm, isNull);
    tracker.add(now, -10, double.nan, -10);
    expect(tracker.confidence, 0);
    kicks(tracker, (t) => now = t, bpm: 120, from: 10010000, until: 20010000);
    now += 1000000;
    tracker.add(now, -75, -75, -75);
    expect(tracker.confidence, 0);
    expect(tracker.bufferedSamples, 0);
    tracker.start();
    tracker.stop();
    expect(tracker.pulse, 0);
  });
  test('long run retains at most twelve seconds and bounded attacks', () {
    var now = 0;
    final tracker = RhythmTracker(clock: () => now);
    kicks(tracker, (t) => now = t, bpm: 160, from: 0, until: 180000000);
    expect(tracker.bufferedSamples, lessThanOrEqualTo(240));
    expect(tracker.bufferedAttacks, lessThanOrEqualTo(60));
    expect(tracker.bpm!, closeTo(160, 3));
  });

  for (final tempo in [90.0, 120.0, 160.0]) {
    test('$tempo BPM peaks the pulse on the attacks', () {
      var now = 0;
      final tracker = RhythmTracker(clock: () => now);
      final alignments = kickAlignments(
        tracker,
        (t) => now = t,
        bpm: tempo,
        from: 0,
        until: 30000000,
        settledFrom: 20000000,
      );
      expect(alignments, isNotEmpty, reason: 'The tracker must lock the tempo');
      expect(tracker.bpm, isNotNull);
      expect(tracker.bpm!, closeTo(tempo, 3));
      var worst = 0.0;
      for (final alignment in alignments) {
        worst = math.max(worst, (alignment - 1).abs());
      }
      // The phase error is measured at the instant of the attack, so the peak
      // of the pulse lands on it and not one analysis bin before it.
      expect(
        worst,
        lessThan(0.05),
        reason: 'The pulse must peak on the attacks (worst $worst)',
      );
    });
  }
}
