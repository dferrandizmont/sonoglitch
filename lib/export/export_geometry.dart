import 'dart:math' as math;
import 'dart:ui';

import 'export_layout.dart';
import 'export_readings.dart';
import 'glitch_wordmark.dart';

/// Fixed-pitch instruments pack left, without stretching on landscape photos.
class ReadingGeometry {
  ReadingGeometry(double x, double top, double u, {required bool paper})
    : bounds = Rect.fromLTWH(
        x,
        top + (paper ? .114 : .033) * u,
        .171 * u,
        .088 * u,
      ),
      labelBaseline = Offset(x + .0155 * u, top + (paper ? .127 : .046) * u),
      valueBaseline = Offset(x, top + (paper ? .171 : .090) * u),
      key = Rect.fromLTWH(
        x,
        top + (paper ? .116 : .035) * u,
        .0095 * u,
        .0095 * u,
      ),
      cells = List.unmodifiable(
        List.generate(
          8,
          (i) => Rect.fromLTWH(
            x + i * .022 * u,
            top + (paper ? .185 : .104) * u,
            .017 * u,
            .017 * u,
          ),
        ),
      );

  final Rect bounds;
  final Offset labelBaseline;
  final Offset valueBaseline;
  final Rect key;
  final List<Rect> cells;
}

class LadderGeometry {
  LadderGeometry(double x, double top, double u, {required this.paper})
    : labelBaseline = Offset(x, top + (paper ? .127 : .046) * u),
      cells = List.unmodifiable(
        List.generate(
          5,
          (i) => Rect.fromLTWH(
            x,
            top + ((paper ? .138 : .057) + i * .0136) * u,
            .030 * u,
            .0096 * u,
          ),
        ),
      );
  final Offset labelBaseline;
  final bool paper;

  /// Paper labels end at the ladder's right edge; strip labels start at its left.
  Rect labelBounds(Size size, double alphabeticBaseline) => Rect.fromLTWH(
    paper ? cells.first.right - size.width : labelBaseline.dx,
    labelBaseline.dy - alphabeticBaseline,
    size.width,
    size.height,
  );

  /// Ordered top to bottom; fill starts at the bottom.
  final List<Rect> cells;
}

class SoundStripGeometry {
  SoundStripGeometry._(
    this.band,
    this.slots,
    this.ladders,
    this.wordmarkOrigin,
    this.wordmarkSize,
    this.wordmarkWidth,
    this.idBaseline,
    this.idAtRight,
  );
  final Rect band;
  final List<ReadingGeometry> slots;
  final List<LadderGeometry> ladders;
  final Offset wordmarkOrigin;
  final double wordmarkSize;
  final double wordmarkWidth;

  /// Where the photo ID sits and whether it ends there or starts there.
  final Offset idBaseline;
  final bool idAtRight;

  /// [mode] is the resolved mode of [ExportLayoutPlan.resolveMode]. Without
  /// readings the ID and the signature share one centred row.
  static SoundStripGeometry compute(
    ExportLayoutPlan plan,
    List<ExportReading> readings, {
    bool spectrum = true,
    ExportReadingsMode mode = ExportReadingsMode.full,
  }) {
    final compact = mode == ExportReadingsMode.hidden;
    final numbers = mode == ExportReadingsMode.numbers;
    final u = math.min(plan.photo.width, plan.photo.height);
    final f = math.max(12.0, .028 * u);
    final right = plan.photo.right - .045 * u;
    final leftBlockRight =
        plan.photo.left + (compact ? .045 + .2 : .045 + 2 * .205 + .171) * u;
    // Preserve a gap after the third slot even with a very wide fallback font.
    final wordWidth = math.min(
      GlitchWordmark.measure(f).width,
      math.max(
        .0015 * u,
        right -
            leftBlockRight -
            (compact || numbers ? .034 : .020 + .114 + .034) * u,
      ),
    );
    final wordX = right - wordWidth;
    final spectrumX = wordX - (.034 + .114) * u;
    return SoundStripGeometry._(
      Rect.fromLTWH(
        0,
        plan.photo.bottom,
        plan.width.toDouble(),
        plan.bandHeight.toDouble(),
      ),
      List.unmodifiable(
        List.generate(
          readings.length,
          (i) => ReadingGeometry(
            plan.photo.left + (.045 + i * .205) * u,
            plan.photo.bottom,
            u,
            paper: false,
          ),
        ),
      ),
      spectrum
          ? List.unmodifiable(
              List.generate(
                3,
                (i) => LadderGeometry(
                  spectrumX + i * .042 * u,
                  plan.photo.bottom,
                  u,
                  paper: false,
                ),
              ),
            )
          : const [],
      Offset(wordX, plan.photo.bottom + (compact ? .047 : .090) * u),
      f,
      wordWidth,
      compact
          ? Offset(plan.photo.left + .045 * u, plan.photo.bottom + .047 * u)
          : Offset(right, plan.photo.bottom + (numbers ? .118 : .138) * u),
      !compact,
    );
  }
}

class PosterGeometry {
  PosterGeometry._(
    this.slots,
    this.ladders,
    this.titleBaseline,
    this.wordmarkOrigin,
    this.wordmarkSize,
    this.rule,
    this.registration,
  );
  final List<ReadingGeometry> slots;
  final List<LadderGeometry> ladders;
  final Offset titleBaseline;
  final Offset wordmarkOrigin;
  final double wordmarkSize;
  final Rect rule;
  final List<Rect> registration;

  static PosterGeometry compute(
    ExportLayoutPlan plan,
    List<ExportReading> readings, {
    bool spectrum = true,
  }) {
    final photo = plan.photo;
    final u = math.min(photo.width, photo.height);
    final f = math.max(12.0, .028 * u);
    return PosterGeometry._(
      List.unmodifiable(
        List.generate(
          readings.length,
          (i) => ReadingGeometry(
            photo.left + i * .205 * u,
            photo.bottom,
            u,
            paper: true,
          ),
        ),
      ),
      spectrum
          ? List.unmodifiable(
              List.generate(
                3,
                (i) => LadderGeometry(
                  photo.right - .154 * u + i * .062 * u,
                  photo.bottom,
                  u,
                  paper: true,
                ),
              ),
            )
          : const [],
      Offset(photo.left, photo.bottom + .071 * u),
      Offset(
        photo.right - GlitchWordmark.measure(f).width,
        photo.bottom + .071 * u,
      ),
      f,
      Rect.fromLTWH(
        photo.left,
        photo.bottom + .093 * u,
        photo.width,
        .0016 * u,
      ),
      List.unmodifiable(
        List.generate(
          3,
          (i) => Rect.fromLTWH(
            photo.left + i * .029 * u,
            photo.bottom + .0922 * u,
            .022 * u,
            .0032 * u,
          ),
        ),
      ),
    );
  }
}
