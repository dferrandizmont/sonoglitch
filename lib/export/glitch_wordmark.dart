import 'package:flutter/painting.dart';

/// The one spelling used by every export signature.
const watermarkText = 'Sonoglitch';

/// Crisp horizontal channel displacement; no intermediate surface or blur.
class GlitchWordmark {
  const GlitchWordmark._();

  static const slices = [
    (top: -0.47, bottom: -0.39, shift: -0.04),
    (top: -0.30, bottom: -0.20, shift: 0.07),
    (top: -0.10, bottom: -0.04, shift: -0.03),
  ];

  static TextPainter _text(double f, Color color) => TextPainter(
    text: TextSpan(
      text: watermarkText,
      style: TextStyle(
        fontSize: f,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();

  /// Natural advance and line height. Channel spill is at most 0.13f.
  static Size measure(double f) {
    final text = _text(f, const Color(0xFFF3F3F6));
    try {
      return text.size;
    } finally {
      text.dispose();
    }
  }

  static void paint(
    Canvas canvas,
    Offset baselineLeft,
    double f, {
    Color ink = const Color(0xFFF3F3F6),
    double inkAlpha = .92,
    double fringeAlpha = .70,
    bool glitch = true,
    double? maxWidth,
  }) {
    // Tiny test surfaces and unusually wide system fonts must still fit their
    // reserved block. Normal phone fonts keep their natural advance.
    final width = measure(f).width;
    if (maxWidth != null && width > maxWidth && maxWidth > 0) {
      canvas.save();
      canvas.translate(baselineLeft.dx, baselineLeft.dy);
      canvas.scale(maxWidth / width, 1);
      paint(
        canvas,
        Offset.zero,
        f,
        ink: ink,
        inkAlpha: inkAlpha,
        fringeAlpha: fringeAlpha,
        glitch: glitch,
      );
      canvas.restore();
      return;
    }
    final text = _text(f, ink.withValues(alpha: inkAlpha));
    final cyan = _text(
      f,
      const Color(0xFF55E5F2).withValues(alpha: fringeAlpha),
    );
    final magenta = _text(
      f,
      const Color(0xFFF36CCB).withValues(alpha: fringeAlpha),
    );
    try {
      final baseline = text.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final origin = baselineLeft - Offset(0, baseline);
      if (!glitch || f < 20) {
        text.paint(canvas, origin);
        return;
      }
      void strip(double top, double bottom, double shift, bool fringe) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(
            baselineLeft.dx - .3 * f,
            baselineLeft.dy + top * f,
            baselineLeft.dx + text.width + .3 * f,
            baselineLeft.dy + bottom * f,
          ),
        );
        if (fringe) {
          cyan.paint(canvas, origin + Offset((shift - .06) * f, 0));
          magenta.paint(canvas, origin + Offset((shift + .06) * f, 0));
        }
        text.paint(canvas, origin + Offset(shift * f, 0));
        canvas.restore();
      }

      var top = -baseline / f - .3;
      for (final slice in slices) {
        strip(top, slice.top, 0, false);
        strip(slice.top, slice.bottom, slice.shift, true);
        top = slice.bottom;
      }
      strip(top, (text.height - baseline) / f + .3, 0, false);
    } finally {
      text.dispose();
      cyan.dispose();
      magenta.dispose();
    }
  }
}
