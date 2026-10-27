import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/features/viewfinder/moment_detector.dart';

/// A clock that the test moves by hand.
class _Clock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) => micros += duration.inMicroseconds;
}

/// A quiet sample of the place.
const AmbientState _quiet = AmbientState(noise: 0.2);

/// A loud sample of the place.
const AmbientState _loud = AmbientState(noise: 0.9);

/// Feeds quiet samples for a while, so the place counts as quiet.
void _quietFor(
  MomentDetector detector,
  _Clock clock,
  Duration duration, {
  AmbientState state = _quiet,
}) {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  detector.add(state);
  while (elapsed < duration) {
    clock.advance(step);
    elapsed += step;
    detector.add(state);
  }
}

void main() {
  test('a level over the threshold after a quiet second is a peak', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(_loud), isTrue);
  });

  test('a level over the threshold without a quiet second is not a peak', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 500));

    expect(detector.add(_loud), isFalse);
  });

  test('a level that does not reach the threshold is not a peak', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(const AmbientState(noise: 0.84)), isFalse);
  });

  test('the burst over the baseline counts as the level of the place', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(
      detector.add(const AmbientState(noise: 0.1, burst: 0.9)),
      isTrue,
      reason: 'a single clap is loud even when the place is quiet',
    );
  });

  test('the level has to cross the threshold, it does not fire again', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(_loud), isTrue);
    expect(
      detector.add(_loud),
      isFalse,
      reason: 'the level is still high, it did not cross the threshold',
    );
    expect(
      detector.add(const AmbientState(noise: 0.95)),
      isFalse,
      reason: 'the level is still high, it did not cross the threshold',
    );
  });

  test('a new peak after the place calms down counts again', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);

    // The place calms down and the noise comes back.
    clock.advance(const Duration(seconds: 9));
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);
  });

  test('a shot consumes quiet credit even after the cooldown', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);

    clock.advance(const Duration(seconds: 9));
    detector.add(const AmbientState(noise: 0.84));
    expect(detector.add(_loud), isFalse, reason: 'no new quiet second');
    _quietFor(detector, clock, const Duration(milliseconds: 100));
    expect(detector.add(_loud), isFalse, reason: 'brief quiet is not enough');
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);
  });

  test('reset excludes paused time from quiet qualification', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 500));
    detector.reset();
    clock.advance(const Duration(seconds: 30));
    _quietFor(detector, clock, const Duration(milliseconds: 100));
    expect(detector.add(_loud), isFalse);
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);
  });

  test('reset preserves the shot cooldown', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);
    detector.reset();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isFalse);
    clock.advance(MomentDefaults.cooldown);
    detector.add(_quiet);
    expect(detector.add(_loud), isTrue);
  });

  test('the detector waits for the cooldown after a shot', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue);

    // The place is quiet again, but the cooldown has not passed.
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isFalse);

    // The cooldown is over, so the next peak counts.
    clock.advance(const Duration(seconds: 8));
    _quietFor(detector, clock, const Duration(milliseconds: 100));
    expect(detector.add(_loud), isTrue);
  });

  test('the detector stops after one shot', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(_loud), isTrue);
    expect(detector.isArmed, isFalse);

    clock.advance(const Duration(seconds: 30));
    _quietFor(detector, clock, const Duration(milliseconds: 100));
    expect(
      detector.add(_loud),
      isFalse,
      reason: 'the camera must not take a photo on its own',
    );
  });

  test('the detector stays armed when the setting asks for it', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call, keepArmed: true)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(_loud), isTrue);
    expect(detector.isArmed, isTrue);

    clock.advance(const Duration(seconds: 9));
    _quietFor(detector, clock, const Duration(milliseconds: 1100));
    expect(detector.add(_loud), isTrue, reason: 'the next peak is caught too');
    expect(detector.isArmed, isTrue);
  });

  test('a sudden movement of the scene is a peak', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    detector.add(const AmbientState(sceneMotion: 0.2));

    expect(
      detector.add(const AmbientState(sceneMotion: 0.9)),
      isTrue,
      reason: 'the scene jumped',
    );
  });

  test('a slow movement of the scene is not a peak', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    detector.add(const AmbientState(sceneMotion: 0.2));

    clock.advance(const Duration(milliseconds: 200));
    expect(detector.add(const AmbientState(sceneMotion: 0.5)), isFalse);
    clock.advance(const Duration(milliseconds: 200));
    expect(detector.add(const AmbientState(sceneMotion: 0.85)), isFalse);
  });

  for (final frameMs in [16, 33, 50]) {
    test(
      'smoothed scene movement triggers at ${frameMs}ms frame intervals',
      () {
        final clock = _Clock();
        final motion = MotionService(
          samples: const Stream<AccelSample>.empty(),
          gyroSamples: const Stream<AccelSample>.empty(),
          gravitySamples: const Stream<AccelSample>.empty(),
          clock: clock.call,
        );
        final detector = MomentDetector(clock: clock.call)..arm();
        var fired = false;
        for (var frame = 0; frame <= 120 ~/ frameMs; frame++) {
          if (frame > 0) clock.advance(Duration(milliseconds: frameMs));
          // A translated, wrapped texture gives the real scene estimator a
          // full-scale step on every frame, before its 60 ms attack smoother.
          final pixels = Uint8List.fromList([
            for (var y = 0; y < 24; y++)
              for (var x = 0; x < 32; x++) ...[
                for (var channel = 0; channel < 3; channel++)
                  30 + (((x - frame * 2) * 17 + y * 31) % 180),
                255,
              ],
          ]);
          motion.addSceneFrame(pixels, 32, 24);
          fired =
              detector.add(AmbientState(sceneMotion: motion.sceneLevel)) ||
              fired;
        }
        expect(motion.sceneLevel, greaterThan(MomentDefaults.motionThreshold));
        expect(fired, isTrue);
      },
    );
  }

  test('reset forgets a motion rise before a sampling pause', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    detector.add(const AmbientState(sceneMotion: 0.2));
    detector.reset();
    clock.advance(const Duration(milliseconds: 33));
    expect(detector.add(const AmbientState(sceneMotion: 0.9)), isFalse);
  });

  test('a disarmed detector does not fire', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call);
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(detector.add(_loud), isFalse);
  });

  test('the detector does not fire when a photo cannot be taken', () {
    final clock = _Clock();
    var allowed = false;
    final detector = MomentDetector(clock: clock.call, canFire: () => allowed)
      ..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    expect(
      detector.add(_loud),
      isFalse,
      reason: 'another photo is being taken',
    );
    expect(detector.isArmed, isTrue, reason: 'the peak was not used');

    allowed = true;
    _quietFor(detector, clock, const Duration(milliseconds: 100));
    expect(detector.add(_loud), isTrue);
  });

  test('the detector forgets the samples when it is reset', () {
    final clock = _Clock();
    final detector = MomentDetector(clock: clock.call)..arm();
    _quietFor(detector, clock, const Duration(milliseconds: 1100));

    detector.reset();
    expect(detector.add(_loud), isFalse);
  });
}
