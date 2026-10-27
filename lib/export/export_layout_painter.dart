import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/app_theme.dart';
import 'export_context.dart';
import 'export_geometry.dart';
import 'export_layout.dart';
import 'export_readings.dart';
import 'glitch_wordmark.dart';

/// Export-only, fixed-resolution drawing. All geometry uses the photo's U.
class ExportLayoutPainter {
  const ExportLayoutPainter({
    required this.layout,
    required this.plan,
    required this.values,
    this.watermark = true,
  });

  final ExportLayout layout;
  final ExportLayoutPlan plan;
  final ExportLayoutValues? values;
  final bool watermark;
  static const Color paper = Color(0xFFF1F1F4);
  static const Color ink = Color(0xFF101014);
  static const Color border = Color(0x33000000);
  static const Color paperSecondary = Color(0xFF6B6B78);
  static const Color paperTrack = Color(0x1F101014);
  static const darkSpectrum = [
    Color(0xFF7B5CF5),
    Color(0xFFB69CFF),
    Color(0xFFE0D6FF),
  ];
  static const paperSpectrum = [
    Color(0xFF3D2799),
    Color(0xFF6A4BD6),
    Color(0xFF9F85F2),
  ];

  double get u => math.min(plan.photo.width, plan.photo.height);

  void paintBackground(Canvas canvas) {
    if (layout == ExportLayout.poster) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, plan.width.toDouble(), plan.height.toDouble()),
        Paint()..color = paper,
      );
    }
  }

  void paintForeground(Canvas canvas) {
    switch (layout) {
      case ExportLayout.full:
        return;
      case ExportLayout.soundStrip:
        if (plan.bandHeight > 0) _paintSoundStrip(canvas);
      case ExportLayout.poster:
        _paintPoster(canvas);
    }
  }

  void _paintSoundStrip(Canvas canvas) {
    final readings = readingsOf(values);
    final geometry = SoundStripGeometry.compute(
      plan,
      readings,
      spectrum: showsExportSpectrum(values),
      mode: exportReadingsTier(values),
    );
    canvas.drawRect(geometry.band, Paint()..color = AppTheme.background);
    canvas.save();
    canvas.clipRect(geometry.band);
    canvas.drawRect(
      Rect.fromLTWH(0, geometry.band.top, geometry.band.width, .0016 * u),
      Paint()..color = const Color(0x14FFFFFF),
    );
    for (var i = 0; i < readings.length; i++) {
      _reading(
        canvas,
        readings[i],
        geometry.slots[i],
        onPaper: false,
        ladder: showsExportLadders(values),
      );
    }
    _spectrum(canvas, geometry.ladders, onPaper: false);
    if (watermark) {
      GlitchWordmark.paint(
        canvas,
        geometry.wordmarkOrigin,
        geometry.wordmarkSize,
        maxWidth: geometry.wordmarkWidth,
      );
    }
    final id = values?.photoId;
    if (id != null) {
      _text(
        canvas,
        id,
        geometry.idBaseline,
        .019 * u,
        AppTheme.textSecondary,
        right: geometry.idAtRight,
        tracking: .1,
      );
    }
    _context(canvas, onPaper: false);
    canvas.restore();
  }

  void _paintPoster(Canvas canvas) {
    canvas.drawRect(
      plan.photo.inflate(.0008 * u),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = .0016 * u,
    );
    final readings = readingsOf(values);
    final geometry = PosterGeometry.compute(
      plan,
      readings,
      spectrum: showsExportSpectrum(values),
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        plan.photo.bottom + .0016 * u,
        plan.width.toDouble(),
        plan.height.toDouble(),
      ),
    );
    _text(
      canvas,
      values?.styleName.toUpperCase() ?? '',
      geometry.titleBaseline,
      .032 * u,
      ink,
      weight: FontWeight.w700,
      tracking: .08,
    );
    if (watermark) {
      GlitchWordmark.paint(
        canvas,
        geometry.wordmarkOrigin,
        geometry.wordmarkSize,
        ink: ink,
        fringeAlpha: .85,
      );
    }
    canvas.drawRect(geometry.rule, Paint()..color = ink.withValues(alpha: .14));
    const registrationColors = [
      Color(0xFF14A3B3),
      Color(0xFFD43C93),
      Color(0xFFE0852F),
    ];
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        geometry.registration[i],
        Paint()..color = registrationColors[i],
      );
    }
    final id = values?.photoId;
    if (id != null) {
      // A paper reserve keeps the micro ID readable on the rule itself.
      final size = _measure(id, .019 * u, tracking: .1);
      canvas.drawRect(
        Rect.fromLTWH(
          plan.photo.right - size.width - .012 * u,
          geometry.rule.top - .016 * u,
          size.width + .012 * u,
          .024 * u,
        ),
        Paint()..color = paper,
      );
      _text(
        canvas,
        id,
        Offset(plan.photo.right, geometry.rule.top + .006 * u),
        .019 * u,
        paperSecondary,
        right: true,
        tracking: .1,
      );
    }
    for (var i = 0; i < readings.length; i++) {
      _reading(
        canvas,
        readings[i],
        geometry.slots[i],
        onPaper: true,
        ladder: showsExportLadders(values),
      );
    }
    _spectrum(canvas, geometry.ladders, onPaper: true);
    _context(canvas, onPaper: true);
    canvas.restore();
  }

  void _reading(
    Canvas canvas,
    ExportReading reading,
    ReadingGeometry geometry, {
    required bool onPaper,
    bool ladder = true,
  }) {
    final color = onPaper ? reading.paper : reading.dark;
    canvas.drawRect(geometry.key, Paint()..color = color);
    _text(
      canvas,
      reading.label,
      geometry.labelBaseline,
      .019 * u,
      onPaper ? paperSecondary : AppTheme.textSecondary,
      tracking: .1,
    );
    _text(
      canvas,
      reading.value,
      geometry.valueBaseline,
      .046 * u,
      onPaper ? ink : AppTheme.textPrimary,
      tracking: -.01,
    );
    if (!ladder) return;
    final lit = (reading.level * 8).round();
    for (var i = 0; i < 8; i++) {
      canvas.drawRect(
        geometry.cells[i],
        Paint()
          ..color = i < lit
              ? color
              : (onPaper ? paperTrack : AppTheme.meterTrack),
      );
    }
  }

  void _spectrum(
    Canvas canvas,
    List<LadderGeometry> ladders, {
    required bool onPaper,
  }) {
    final levels = [values?.bass ?? 0, values?.mid ?? 0, values?.treble ?? 0];
    final labels = onPaper ? ['160 Hz', '2k Hz', '8k Hz'] : ['160', '2k', '8k'];
    for (var i = 0; i < ladders.length; i++) {
      final ladder = ladders[i];
      final label = _painter(
        labels[i],
        .019 * u,
        onPaper ? paperSecondary : AppTheme.textSecondary,
        tracking: .1,
      );
      try {
        final bounds = ladder.labelBounds(
          label.size,
          label.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        label.paint(canvas, bounds.topLeft);
      } finally {
        label.dispose();
      }
      final lit = (exportLevel(levels[i]) * 5).round();
      for (var j = 0; j < 5; j++) {
        canvas.drawRect(
          ladder.cells[j],
          Paint()
            ..color = j >= 5 - lit
                ? (onPaper ? paperSpectrum : darkSpectrum)[i]
                : (onPaper ? paperTrack : AppTheme.meterTrack),
        );
      }
    }
  }

  void _context(Canvas canvas, {required bool onPaper}) {
    final context = values?.context;
    final items = contextItems(context);
    if (items.isEmpty) return;
    final color = onPaper ? paperSecondary : AppTheme.textSecondary;
    final tier = exportReadingsTier(values);
    final base = onPaper
        ? ExportLayoutPlan.captionRatio(
            tier,
            readings: hasExportReadings(values),
          )
        : ExportLayoutPlan.bandRatio(tier);
    final top = plan.photo.bottom + base * u;
    final left = plan.photo.left + (onPaper ? 0 : .045 * u);
    final right = plan.photo.right - (onPaper ? 0 : .045 * u);
    canvas.drawRect(
      Rect.fromLTWH(left, top, right - left, .0016 * u),
      Paint()
        ..color = (onPaper ? ink : const Color(0xFFFFFFFF)).withValues(
          alpha: onPaper ? .14 : .08,
        ),
    );
    final baseline = top + .030 * u;
    var x = left;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) {
        x += .034 * u;
        canvas.drawRect(
          Rect.fromLTWH(x, baseline - .010 * u, .006 * u, .006 * u),
          Paint()..color = color,
        );
        x += .040 * u;
      }
      if (item.kind == ContextItemKind.heading) {
        paintHeadingNeedle(
          canvas,
          Offset(x + .00665 * u, baseline - .00665 * u),
          .0133 * u,
          context!.validHeading!,
          color,
        );
        x += .022 * u;
      }
      _text(canvas, item.text, Offset(x, baseline), .019 * u, color);
      x += _measure(item.text, .019 * u).width;
      if (item.kind == ContextItemKind.date) {
        x += .016 * u;
        paintMoon(
          canvas,
          Offset(x, baseline - .00665 * u),
          u,
          context!.dateTime!,
          color,
        );
        x += .008 * u;
      }
    }
  }

  TextPainter _painter(
    String text,
    double f,
    Color color, {
    FontWeight weight = FontWeight.w600,
    double tracking = 0,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: f,
        color: color,
        fontWeight: weight,
        letterSpacing: tracking * f,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    ),
    textDirection: ui.TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();

  Size _measure(String text, double f, {double tracking = 0}) {
    final painter = _painter(text, f, ink, tracking: tracking);
    try {
      return painter.size;
    } finally {
      painter.dispose();
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset baseline,
    double f,
    Color color, {
    FontWeight weight = FontWeight.w600,
    double tracking = 0,
    bool right = false,
  }) {
    final painter = _painter(
      text,
      f,
      color,
      weight: weight,
      tracking: tracking,
    );
    try {
      painter.paint(
        canvas,
        baseline -
            Offset(
              right ? painter.width : 0,
              painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
            ),
      );
    } finally {
      painter.dispose();
    }
  }
}
