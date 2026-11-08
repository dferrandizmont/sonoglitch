import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app_config.dart';
import '../../theme/app_theme.dart';

/// The horizontal swipe that steps through the styles.
///
/// The gesture only counts away from the edges of the screen and when the
/// movement is clearly horizontal, so a vertical flick is left to the rest of
/// the screen.
class StyleSwipeGesture {
  /// The distance that the finger has to travel.
  static const double threshold = 48;

  /// How much more horizontal than vertical the swipe has to be.
  static const double horizontalDominanceRatio = 1.5;

  Offset _start = Offset.zero;
  Offset _distance = Offset.zero;

  /// Starts watching a swipe at [globalPosition].
  void start(Offset globalPosition) {
    _start = globalPosition;
    _distance = Offset.zero;
  }

  /// Follows the finger to [globalPosition].
  void update(Offset globalPosition) {
    _distance = globalPosition - _start;
  }

  /// The step of the style that the swipe asks for.
  ///
  /// Returns 1 for the next style, -1 for the previous one and null when the
  /// swipe has to be ignored. [width] is the width of the screen, where the
  /// dead zones of the edges live.
  int? end(double width) {
    if (_start.dx < AppTheme.swipeEdgeDeadZone ||
        _start.dx > width - AppTheme.swipeEdgeDeadZone ||
        _distance.dx.abs() < threshold ||
        _distance.dx.abs() < _distance.dy.abs() * horizontalDominanceRatio) {
      return null;
    }
    return _distance.dx < 0 ? 1 : -1;
  }
}

/// Counts the taps that open the diagnostics panel in a debug build.
///
/// The switch of the settings is the same thing, so the panel keeps its state
/// between sessions.
class DebugTapGesture {
  DebugTapGesture({
    required this.onTripleTap,
    this.enabled = AppConfig.debugBuild,
  });

  /// Called when three taps land inside [window].
  final VoidCallback onTripleTap;

  /// Whether the gesture is available at all.
  final bool enabled;

  /// How long the taps count together.
  static const Duration window = Duration(milliseconds: 400);

  int _taps = 0;
  Timer? _timer;

  /// Records one tap.
  void register() {
    if (!enabled) return;
    _taps++;
    _timer?.cancel();
    _timer = Timer(window, () {
      _taps = 0;
    });
    if (_taps >= 3) {
      _taps = 0;
      onTripleTap();
    }
  }

  /// Forgets the taps and stops the timer.
  void cancel() {
    _timer?.cancel();
    _taps = 0;
  }

  /// Releases the timer.
  void dispose() => cancel();
}
