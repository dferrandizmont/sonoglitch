import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_theme.dart';

/// A row of square cells with a lit window that sweeps left to right, drawn
/// three times with a small chromatic offset that flickers at fixed ticks.
///
/// It uses the square cells and the colours of the segmented meters. With
/// reduced motion it is a still frame and no ticker runs.
class GlitchLoader extends StatefulWidget {
  const GlitchLoader({super.key, this.scale = 2});

  /// Multiplier of the cell size of the segmented meters.
  final double scale;

  /// Time of one full sweep.
  static const Duration period = Duration(milliseconds: 1200);

  @override
  State<GlitchLoader> createState() => _GlitchLoaderState();
}

class _GlitchLoaderState extends State<GlitchLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GlitchLoader.period,
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = GlitchLoaderPainter.sizeFor(widget.scale);
    return Semantics(
      label: AppLocalizations.of(context).processingLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('glitch-loader-paint'),
            size: size,
            painter: GlitchLoaderPainter(
              progress: _reduced ? null : _controller,
              scale: widget.scale,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the loader. A null [progress] draws the still frame.
class GlitchLoaderPainter extends CustomPainter {
  GlitchLoaderPainter({this.progress, this.scale = 2})
    : super(repaint: progress);

  static const int cells = 8;
  static const int window = 3;

  /// Steps of one sweep: the window enters, crosses and leaves the row.
  static const int steps = cells + window - 1;

  /// Flicker ticks of one sweep.
  static const int ticks = 30;

  /// Chromatic offset in logical pixels.
  static const double fringe = AppTheme.fringeRingOffset;

  final Animation<double>? progress;
  final double scale;

  double get cell => AppTheme.meterSegmentSize * scale;
  double get gap => AppTheme.meterSegmentGap * scale;

  static Size sizeFor(double scale) {
    final cell = AppTheme.meterSegmentSize * scale;
    final gap = AppTheme.meterSegmentGap * scale;
    return Size(cells * cell + (cells - 1) * gap + 2 * fringe, cell);
  }

  /// First lit cell for a sweep position in 0..1. It may be negative or past
  /// the row while the window enters and leaves.
  static int windowStart(double value) =>
      (value.clamp(0.0, 1.0) * steps).floor().clamp(0, steps - 1) -
      (window - 1);

  /// The horizontal chromatic offset at a sweep position: zero most of the
  /// time, and a short burst at fixed ticks. Deterministic, never random.
  static double fringeOffset(double value) {
    final tick = (value.clamp(0.0, 1.0) * ticks).floor().clamp(0, ticks - 1);
    final burst = (tick * 7 + 3) % 11 < 2;
    if (!burst) return 0;
    return tick.isEven ? fringe : -fringe;
  }

  /// Colours of the lit window, from its trailing to its leading cell.
  static const List<Color> colors = [
    AppTheme.warm,
    AppTheme.accent,
    AppTheme.signalCyan,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final value = progress?.value;
    final start = value == null ? 0 : windowStart(value);
    final offset = value == null ? 0.0 : fringeOffset(value);
    final paint = Paint();
    final left = fringe;
    Rect rect(int i, [double dx = 0]) =>
        Rect.fromLTWH(left + i * (cell + gap) + dx, 0, cell, cell);
    paint.color = AppTheme.meterTrack;
    for (var i = 0; i < cells; i++) {
      canvas.drawRect(rect(i), paint);
    }
    final lit = [
      for (var k = 0; k < window; k++)
        if (start + k >= 0 && start + k < cells) start + k,
    ];
    if (offset != 0) {
      paint.color = AppTheme.signalCyan.withValues(
        alpha: AppTheme.fringeOpacity,
      );
      for (final i in lit) {
        canvas.drawRect(rect(i, -offset), paint);
      }
      paint.color = AppTheme.signalMagenta.withValues(
        alpha: AppTheme.fringeOpacity,
      );
      for (final i in lit) {
        canvas.drawRect(rect(i, offset), paint);
      }
    }
    for (final i in lit) {
      paint.color = colors[i - start];
      canvas.drawRect(rect(i), paint);
    }
  }

  @override
  bool shouldRepaint(GlitchLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scale != scale;
}
