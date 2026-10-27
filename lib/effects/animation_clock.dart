/// The clock of the preview animation.
///
/// Preview paints and still renders read the same viewfinder-owned clock.
/// The clock only runs while the preview is drawn and the viewfinder is
/// visible, so the still is drawn with the same time the preview was showing.
/// An injectable clock lets tests assert on the time without sleeping.
abstract class AnimationClock {
  /// Starts measuring the elapsed time. Calling it twice is harmless.
  void start();

  /// Stops measuring the elapsed time. Calling it twice is harmless.
  void stop();

  /// Stops and zeroes the clock.
  void reset();

  /// The time elapsed since [start], in seconds. Always finite and `>= 0`.
  double get elapsedSeconds;
}

/// The production clock: backed by a [Stopwatch].
class StopwatchAnimationClock implements AnimationClock {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void start() => _stopwatch.start();

  @override
  void stop() => _stopwatch.stop();

  @override
  void reset() {
    if (_stopwatch.isRunning) _stopwatch.stop();
    _stopwatch.reset();
  }

  @override
  double get elapsedSeconds =>
      _stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
}

/// A deterministic clock for tests.
///
/// The clock only advances when [advance] is called, so the viewfinder tests
/// can assert on the time of the still without sleeping on a wall clock.
class FakeAnimationClock implements AnimationClock {
  FakeAnimationClock();

  Duration _elapsed = Duration.zero;
  bool _running = false;

  /// The total time the clock has accumulated since it was last reset.
  Duration get elapsed => _elapsed;

  /// Whether [start] has been called more recently than [stop].
  bool get isRunning => _running;

  /// Adds [duration] to the elapsed time. Calling it while the clock is
  /// stopped does nothing, which is what the widget tester needs to keep the
  /// "frozen while hidden" property of the viewfinder under test.
  void advance(Duration duration) {
    if (!_running) return;
    _elapsed += duration;
  }

  @override
  void start() {
    _running = true;
  }

  @override
  void stop() {
    _running = false;
  }

  @override
  void reset() {
    _elapsed = Duration.zero;
    _running = false;
  }

  @override
  double get elapsedSeconds => _elapsed.inMicroseconds / 1e6;
}
