/// A monotonic clock, in microseconds since an arbitrary origin.
///
/// The ambient services take the clock as a dependency so unit tests can
/// advance time by hand instead of sleeping and hoping.
typedef Clock = int Function();

final Stopwatch _stopwatch = Stopwatch()..start();

/// The production clock: monotonic, cheap and independent of the wall clock.
int stopwatchClock() => _stopwatch.elapsedMicroseconds;

/// The period the services assume when the first sample arrives and there is
/// no history yet.
const Duration nominalSamplePeriod = Duration(milliseconds: 50);
