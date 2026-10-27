import 'package:flutter/foundation.dart';

import '../ambient/ambient_state.dart';
import 'capture_timings.dart';

/// The timings of the last capture, shared by the screens.
///
/// The camera, the viewfinder and the result screen each measure their part
/// and write it here, so the diagnostics panel always shows the whole
/// capture.
class CaptureMetrics extends ValueNotifier<CaptureTimings> {
  CaptureMetrics() : super(const CaptureTimings());

  /// Updates one or more steps of the last capture.
  void update({
    double? takeMs,
    double? decodeMs,
    double? renderMs,
    double? encodeMs,
    double? animationTime,
    AmbientState? ambient,
  }) {
    value = CaptureTimings(
      takeMs: takeMs ?? value.takeMs,
      decodeMs: decodeMs ?? value.decodeMs,
      renderMs: renderMs ?? value.renderMs,
      encodeMs: encodeMs ?? value.encodeMs,
      animationTime: animationTime ?? value.animationTime,
      ambient: ambient ?? value.ambient,
    );
  }

  /// Forgets the measurements.
  void reset() {
    value = const CaptureTimings();
  }
}
