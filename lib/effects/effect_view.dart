import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../ambient/ambient_state.dart';
import 'animation_clock.dart';
import 'effect_renderer.dart';

/// Draws [image] with the effect, cover-fitted to the available space.
///
/// A caller may share its capture clock and stop animation while covered.
class EffectView extends StatefulWidget {
  const EffectView({
    super.key,
    required this.renderer,
    required this.image,
    required this.ambient,
    this.animationClock,
    this.active,
  });

  final EffectRenderer renderer;
  final ui.Image? image;
  final ValueListenable<AmbientState> ambient;

  /// When supplied, preview and still rendering read this same clock.
  final AnimationClock? animationClock;

  /// Stops the ticker synchronously, including when lifecycle pauses frames.
  final ValueListenable<bool>? active;

  @override
  State<EffectView> createState() => _EffectViewState();
}

class _EffectViewState extends State<EffectView>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker;
  double _timeAtStart = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _clock.value =
          widget.animationClock?.elapsedSeconds ??
          _timeAtStart +
              elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    widget.active?.addListener(_activityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTicker();
  }

  @override
  void didUpdateWidget(EffectView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      oldWidget.active?.removeListener(_activityChanged);
      widget.active?.addListener(_activityChanged);
    }
    _updateTicker();
  }

  void _activityChanged() {
    // Paused apps may not build another frame. Stop the ticker immediately.
    _updateTicker();
    setState(() {});
  }

  void _updateTicker() {
    final animate =
        (widget.active?.value ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        widget.image != null;
    if (animate && !_ticker.isActive) {
      _timeAtStart = _clock.value;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.active?.removeListener(_activityChanged);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    if (img == null) return const SizedBox.expand();
    return CustomPaint(
      size: Size.infinite,
      painter: _EffectPainter(
        widget.renderer,
        img,
        widget.ambient,
        _clock,
        Listenable.merge([
          if (widget.active?.value ?? true) widget.ambient,
          _clock,
        ]),
        widget.active?.value ?? true,
        widget.animationClock,
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter(
    this.renderer,
    this.image,
    this.ambient,
    this.clock,
    Listenable repaint,
    this.active,
    this.animationClock,
  ) : super(repaint: repaint);

  final EffectRenderer renderer;
  final ui.Image image;
  final ValueListenable<AmbientState> ambient;
  final ValueListenable<double> clock;
  final bool active;
  final AnimationClock? animationClock;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    renderer.paint(
      canvas,
      size,
      image: image,
      ambient: ambient.value,
      time: animationClock?.elapsedSeconds ?? clock.value,
    );
  }

  @override
  bool shouldRepaint(_EffectPainter old) =>
      old.renderer != renderer ||
      old.image != image ||
      old.ambient != ambient ||
      old.clock != clock ||
      // Retain the cached preview under a non-opaque sheet. Resuming must
      // repaint even if the image and ambient sources have not changed.
      (!old.active && active) ||
      old.animationClock != animationClock;
}
