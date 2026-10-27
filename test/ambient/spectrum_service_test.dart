import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';

class FakeSpectrumSource implements SpectrumSource {
  FakeSpectrumSource() {
    controller = StreamController<SpectrumBands>.broadcast(
      sync: true,
      onListen: () => subscriptions++,
    );
  }

  int subscriptions = 0;
  late final StreamController<SpectrumBands> controller;
  @override
  Stream<SpectrumBands> get bands => controller.stream;
}

void main() {
  late int micros;
  late SpectrumService spectrum;
  void feed(SpectrumBands bands, {int count = 1}) {
    for (var i = 0; i < count; i++) {
      micros += 50000;
      spectrum.addReading(bands);
    }
  }

  setUp(() {
    micros = 0;
    spectrum = SpectrumService(
      source: const NoopSpectrumSource(),
      clock: () => micros,
    );
  });
  const quiet = (bass: -80.0, mid: -80.0, treble: -80.0);

  test('warmup learns quiet floors without driving the image', () {
    feed(quiet, count: 199);
    expect(spectrum.available, isFalse);
    expect((spectrum.bass, spectrum.mid, spectrum.treble), (0, 0, 0));
    feed(quiet);
    expect(spectrum.available, isTrue);
    expect(spectrum.floors, quiet);
    expect(spectrum.bass, 0);
  });

  test('bass-only and treble-only events preserve their spectral balance', () {
    feed(quiet, count: 220);
    feed((bass: -10, mid: -80, treble: -80), count: 8);
    expect(spectrum.bass, greaterThan(0.9));
    expect(spectrum.mid, 0);
    expect(spectrum.treble, 0);
    feed(quiet, count: 80);
    feed((bass: -80, mid: -80, treble: -10), count: 8);
    expect(spectrum.treble, greaterThan(0.9));
    expect(spectrum.bass, lessThan(0.01));
    expect(spectrum.mid, 0);
  });

  test('flat loud events never saturate all three bands', () {
    feed(quiet, count: 220);
    feed((bass: -10, mid: -10, treble: -10), count: 20);
    expect(spectrum.bass, closeTo(1.4 / 3, 0.01));
    expect(spectrum.mid, closeTo(spectrum.treble, 0.01));
    expect(
      spectrum.bass + spectrum.mid + spectrum.treble,
      lessThanOrEqualTo(1.4),
    );
  });

  test(
    'floor and ceiling learn independently and the rolling floor expires',
    () {
      feed((bass: -90, mid: -70, treble: -50), count: 220);
      expect(spectrum.floors, (bass: -90, mid: -70, treble: -50));
      feed((bass: -5, mid: -20, treble: -30));
      expect(spectrum.ceilings, (bass: -5, mid: -20, treble: -30));
      feed((bass: -60, mid: -40, treble: -20), count: 1400);
      expect(spectrum.floors, (bass: -60, mid: -40, treble: -20));
      expect(spectrum.ceilings.bass, lessThan(-5));
      expect(
        spectrum.ceilings.bass - spectrum.floors.bass,
        greaterThanOrEqualTo(18),
      );
      expect(spectrum.bass, lessThan(0.01));
    },
  );

  test(
    'attack is faster than release and invalid data cannot poison values',
    () {
      feed(quiet, count: 220);
      feed((bass: -5, mid: -80, treble: -80));
      final attack = spectrum.bass;
      expect(attack, greaterThan(0.5));
      feed(quiet);
      expect(spectrum.bass, greaterThan(attack * 0.8));
      final value = spectrum.bass;
      feed((bass: double.nan, mid: double.infinity, treble: -80));
      expect(spectrum.bass, value);
    },
  );

  test(
    'stop cancels, ignores late samples, clears values, and resumes once',
    () async {
      final source = FakeSpectrumSource();
      addTearDown(source.controller.close);
      spectrum = SpectrumService(
        source: source,
        clock: () => micros,
        warmup: Duration.zero,
      );
      spectrum.start();
      spectrum.start();
      await Future<void>.delayed(Duration.zero);
      expect(spectrum.isListening, isTrue);
      source.controller.add(quiet);
      micros += 50000;
      source.controller.add((bass: -5, mid: -80, treble: -80));
      expect(spectrum.bass, greaterThan(0));
      spectrum.stop();
      source.controller.add((bass: -5, mid: -5, treble: -5));
      expect(spectrum.isListening, isFalse);
      expect((spectrum.bass, spectrum.mid, spectrum.treble), (0, 0, 0));
      spectrum.start();
      spectrum.stop();
      spectrum.start();
      await Future<void>.delayed(Duration.zero);
      expect(spectrum.isListening, isTrue);
      source.controller.addError(StateError('unavailable'));
      expect(spectrum.isListening, isFalse);
      expect(spectrum.available, isFalse);
      spectrum.stop();
    },
  );

  test('disabled microphone never opens a source', () async {
    final source = FakeSpectrumSource();
    spectrum = SpectrumService(source: source, clock: () => micros);
    addTearDown(() async {
      spectrum.stop();
      await source.controller.close();
    });
    spectrum.enabled = false;
    spectrum.start();
    await Future<void>.delayed(Duration.zero);
    expect(source.subscriptions, 0);
    expect(spectrum.isListening, isFalse);

    spectrum.enabled = true;
    spectrum.start();
    spectrum.start();
    await Future<void>.delayed(Duration.zero);
    expect(source.subscriptions, 1);
    expect(spectrum.isListening, isTrue);
  });

  test('every reading is drained in order and the queue is emptied', () {
    feed((bass: -75, mid: -75, treble: -75));
    feed((bass: -20, mid: -60, treble: -60));
    feed((bass: -75, mid: -75, treble: -75));

    final drained = spectrum.drainRawReadings();
    expect(drained, hasLength(3));
    expect(drained[0].bands.bass, -75);
    expect(drained[1].bands.bass, -20);
    expect(drained[2].bands.bass, -75);
    expect(drained.map((reading) => reading.timeMicros), [
      50000,
      100000,
      150000,
    ]);
    // The drain empties the queue, so a reading is never delivered twice.
    expect(spectrum.drainRawReadings(), isEmpty);
    // The latest reading is still published.
    expect(spectrum.lastRawReading!.timeMicros, 150000);
  });

  test('the pending readings are bounded and dropped with the session', () {
    for (var i = 0; i < SpectrumService.maxPendingReadings + 10; i++) {
      micros += 1000;
      spectrum.addReading(quiet);
    }
    final drained = spectrum.drainRawReadings();
    expect(drained, hasLength(SpectrumService.maxPendingReadings));
    // The oldest readings are the ones that are dropped.
    expect(drained.first.timeMicros, 11000);

    micros += 1000;
    spectrum.addReading(quiet);
    spectrum.stop();
    expect(spectrum.drainRawReadings(), isEmpty);
  });

  test('a disabled service drops the readings that are waiting', () {
    feed(quiet);
    spectrum.enabled = false;
    expect(spectrum.drainRawReadings(), isEmpty);
    // The queue is empty, so enabling the service again gives nothing old.
    spectrum.enabled = true;
    expect(spectrum.drainRawReadings(), isEmpty);
  });
}
