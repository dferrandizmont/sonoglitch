import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A brief chromatic separation when [text] or [value] changes.
///
/// Keep the widget's key stable so its state survives. To animate a change key,
/// pass it as [value] (for example `value: ValueKey(style.id)`). The first frame
/// and the settled state contain only one [Text].
class FringeText extends StatefulWidget {
  const FringeText(
    this.text, {
    super.key,
    this.value,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final Object? value;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<FringeText> createState() => _FringeTextState();
}

class _FringeTextState extends State<FringeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTheme.fringeDuration,
    value: 1,
  );
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(FringeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.value != widget.value) {
      if (_reducedMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Text _text(TextStyle? style) => Text(
    widget.text,
    style: style,
    textAlign: widget.textAlign,
    maxLines: widget.maxLines,
    overflow: widget.overflow,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      if (_controller.isCompleted || _reducedMotion) return child!;

      final remaining = 1 - AppTheme.motionCurve.transform(_controller.value);
      final offset = AppTheme.fringeTextOffset * remaining;
      final alpha =
          AppTheme.fringeOpacity * AppTheme.fringeTextAlpha * remaining;
      // Resolve inherited geometry once so the copies match the foreground.
      // A foreground Paint overrides TextStyle.color, so explicitly replace it.
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      return Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          for (final (signal, dx) in [
            (AppTheme.signalCyan, -offset),
            (AppTheme.signalMagenta, offset),
          ])
            Positioned.fill(
              child: ExcludeSemantics(
                child: Transform.translate(
                  offset: Offset(dx, 0),
                  child: _text(
                    style.copyWith(
                      foreground: Paint()
                        ..color = signal.withValues(alpha: alpha),
                      shadows: const [],
                    ),
                  ),
                ),
              ),
            ),
          child!,
        ],
      );
    },
    child: _text(widget.style),
  );
}

/// Static shutter ring with a 1.5 dp cyan/magenta separation.
///
/// Place its [CustomPaint] inside a [RepaintBoundary]. No ticker or repaint
/// listenable is used. The ring is inset to keep the fringe inside its bounds.
class FringeRingPainter extends CustomPainter {
  const FringeRingPainter({
    this.color = AppTheme.textPrimary,
    this.strokeWidth = AppTheme.shutterStrokeWidth,
  }) : assert(strokeWidth > 0);

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const offset = AppTheme.fringeRingOffset;
    final radius = (size.shortestSide - strokeWidth) / 2 - offset;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(
      center.translate(-offset, 0),
      radius,
      paint
        ..color = AppTheme.signalCyan.withValues(alpha: AppTheme.fringeOpacity),
    );
    canvas.drawCircle(
      center.translate(offset, 0),
      radius,
      paint
        ..color = AppTheme.signalMagenta.withValues(
          alpha: AppTheme.fringeOpacity,
        ),
    );
    canvas.drawCircle(center, radius, paint..color = color);
  }

  @override
  bool shouldRepaint(FringeRingPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}
