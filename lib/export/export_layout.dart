import 'dart:math' as math;
import 'dart:ui';

import '../ambient/ambient_state.dart';

/// The composition of the exported picture.
///
/// The layouts are drawn at the full resolution of the capture, after the
/// rotation and the crop and before the encoding. The band and the frame are
/// added around the picture, so the picture is never shrunk to make room for
/// them: it keeps the resolution of the chosen quality.
enum ExportLayout {
  /// The picture fills the frame and nothing else is drawn. The default.
  full,

  /// A dark band under the picture with the measured values.
  soundStrip,

  /// A framed print: the picture, the name of the style and the values.
  poster,
}

/// Which readings the sound strip and the poster print.
///
/// The photo ID, the name of the style, the signature and the context line do
/// not depend on it. The full layout has no readings and ignores the mode.
enum ExportReadingsMode {
  /// The numbers with their little square ladders, and the spectrum ladders.
  full,

  /// The numbers and their labels only: no ladders and no spectrum.
  numbers,

  /// No readings at all.
  hidden,
}

/// The size of a layout, in pixels.
///
/// The picture is never resized for a layout: the extra room is added around
/// it, so a layout of a 4096 pixel picture is as sharp as the picture.
class ExportLayoutPlan {
  const ExportLayoutPlan({
    required this.width,
    required this.height,
    required this.photo,
    required this.bandHeight,
    required this.frameWidth,
    required this.captionHeight,
  });

  /// The height of the band of the sound strip, as a fraction of the shorter
  /// side of the picture.
  static const double bandHeightRatio = 0.155;

  /// The width of the frame of the poster, as a fraction of the width of the
  /// picture.
  static const double frameWidthRatio = 0.06;

  /// The height of the caption of the poster, as a fraction of the shorter
  /// side of the picture.
  static const double captionHeightRatio = 0.21;

  /// The height of the band of the sound strip with the numbers alone.
  static const double bandNumbersHeightRatio = 0.135;

  /// The height of the band of the sound strip without readings.
  static const double bandCompactHeightRatio = 0.075;

  /// The height of the caption of the poster with the numbers alone.
  static const double captionNumbersHeightRatio = 0.18;

  /// The height of the caption of the poster without readings.
  static const double captionCompactHeightRatio = 0.11;

  /// The mode that decides the sizes: a mode that prints nothing, or numbers
  /// when there are none, shrinks the layout to its compact form.
  static ExportReadingsMode resolveMode(
    ExportReadingsMode mode, {
    required bool readings,
  }) =>
      mode == ExportReadingsMode.hidden ||
          (mode == ExportReadingsMode.numbers && !readings)
      ? ExportReadingsMode.hidden
      : mode;

  /// The height of the band of a resolved mode, as a fraction of U.
  static double bandRatio(ExportReadingsMode resolved) => switch (resolved) {
    ExportReadingsMode.full => bandHeightRatio,
    ExportReadingsMode.numbers => bandNumbersHeightRatio,
    ExportReadingsMode.hidden => bandCompactHeightRatio,
  };

  /// The height of the caption of a resolved mode, as a fraction of U.
  ///
  /// The full mode without any reading keeps the compact caption it always had.
  static double captionRatio(
    ExportReadingsMode resolved, {
    required bool readings,
  }) => switch (resolved) {
    ExportReadingsMode.full =>
      readings ? captionHeightRatio : captionCompactHeightRatio,
    ExportReadingsMode.numbers => captionNumbersHeightRatio,
    ExportReadingsMode.hidden => captionCompactHeightRatio,
  };

  /// The width of the whole export.
  final int width;

  /// The height of the whole export.
  final int height;

  /// Where the picture is drawn inside the export.
  final Rect photo;

  /// The height of the band of the sound strip. Zero when there is no band.
  final int bandHeight;

  /// The width of the frame of the poster. Zero when there is no frame.
  final int frameWidth;

  /// The height of the caption of the poster. Zero when there is no caption.
  final int captionHeight;

  /// The size of the export of [layout] for a picture of the given size.
  ///
  /// The picture keeps its size: the band and the frame are added around it.
  static ExportLayoutPlan build({
    required ExportLayout layout,
    required int photoWidth,
    required int photoHeight,
    bool readings = true,
    ExportReadingsMode readingsMode = ExportReadingsMode.full,
    bool context = false,
    bool watermark = true,
    String? photoId,
  }) {
    final resolved = resolveMode(readingsMode, readings: readings);
    if (photoWidth <= 0 || photoHeight <= 0) {
      throw ArgumentError('The size of the picture must be positive');
    }
    if (layout == ExportLayout.soundStrip &&
        !readings &&
        !context &&
        !watermark &&
        (photoId == null || photoId.isEmpty)) {
      layout = ExportLayout.full;
    }
    final shorterSide = math.min(photoWidth, photoHeight);
    switch (layout) {
      case ExportLayout.full:
        return ExportLayoutPlan(
          width: photoWidth,
          height: photoHeight,
          photo: Rect.fromLTWH(
            0,
            0,
            photoWidth.toDouble(),
            photoHeight.toDouble(),
          ),
          bandHeight: 0,
          frameWidth: 0,
          captionHeight: 0,
        );
      case ExportLayout.soundStrip:
        final band = math.max(
          1,
          (shorterSide * (bandRatio(resolved) + (context ? .048 : 0))).round(),
        );
        return ExportLayoutPlan(
          width: photoWidth,
          height: photoHeight + band,
          photo: Rect.fromLTWH(
            0,
            0,
            photoWidth.toDouble(),
            photoHeight.toDouble(),
          ),
          bandHeight: band,
          frameWidth: 0,
          captionHeight: 0,
        );
      case ExportLayout.poster:
        final frame = math.max(1, (photoWidth * frameWidthRatio).round());
        final caption = math.max(
          1,
          (shorterSide *
                  (captionRatio(resolved, readings: readings) +
                      (context ? .045 : 0)))
              .round(),
        );
        return ExportLayoutPlan(
          width: photoWidth + frame * 2,
          height: photoHeight + frame * 2 + caption,
          photo: Rect.fromLTWH(
            frame.toDouble(),
            frame.toDouble(),
            photoWidth.toDouble(),
            photoHeight.toDouble(),
          ),
          bandHeight: 0,
          frameWidth: frame,
          captionHeight: caption,
        );
    }
  }
}

/// The measured values that the layouts typeset.
///
/// The exports carry numbers and units, never sentences: a picture is shared
/// with people who do not speak the language of the phone. The only word is
/// the name of the style, which is a name and not a text.
class ExportLayoutValues {
  const ExportLayoutValues({
    required this.styleName,
    this.noiseDb,
    this.baselineDb,
    this.lux,
    this.accel,
    this.noise = 0,
    this.light = 0.5,
    this.motion = 0,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.spectrumAvailable = false,
    this.readingsMode = ExportReadingsMode.full,
    this.photoId,
    this.context,
  });

  final String? photoId;
  final ExportContext? context;

  /// The name of the style that was used.
  final String styleName;

  /// The loudness of the place in dB, when it was measured.
  final double? noiseDb;

  /// The baseline of the place in dB, when it was measured.
  final double? baselineDb;

  /// The light of the place in lux, when the phone has a light sensor.
  final double? lux;

  /// The acceleration of the phone in m/s², when it was measured.
  final double? accel;

  /// The level of the noise, 0..1.
  final double noise;

  /// The level of the light, 0..1.
  final double light;

  /// The level of the movement, 0..1.
  final double motion;

  /// The energy of the band 20–250 Hz, 0..1.
  final double bass;

  /// The energy of the band 250 Hz–2 kHz, 0..1.
  final double mid;

  /// The energy of the band 2–8 kHz, 0..1.
  final double treble;

  /// Whether the three bands of the spectrum are drawn.
  final bool spectrumAvailable;

  /// Which readings are printed.
  final ExportReadingsMode readingsMode;

  /// The values of a capture.
  ///
  /// The spectrum is drawn when it carries energy: a phone without a
  /// spectrum analyser leaves the three bands at zero, and three empty bars
  /// would say more about the phone than about the place.
  factory ExportLayoutValues.fromAmbient(
    AmbientState ambient, {
    required String styleName,
    ExportContext? context,
    String? photoId,
    ExportReadingsMode readingsMode = ExportReadingsMode.full,
  }) {
    final spectrum = ambient.bass > 0 || ambient.mid > 0 || ambient.treble > 0;
    return ExportLayoutValues(
      styleName: styleName,
      context: context,
      photoId: photoId,
      noiseDb: ambient.rawDb,
      baselineDb: ambient.baselineDb,
      lux: ambient.rawLux,
      accel: ambient.rawAccel,
      noise: ambient.noise,
      light: ambient.light,
      motion: ambient.motion,
      bass: ambient.bass,
      mid: ambient.mid,
      treble: ambient.treble,
      spectrumAvailable: spectrum,
      readingsMode: readingsMode,
    );
  }
}

/// Optional shutter-time metadata; never persisted or logged.
class ExportContext {
  const ExportContext({this.dateTime, this.heading, this.pressure});
  final DateTime? dateTime;
  final double? heading;
  final double? pressure;
  bool get hasItems =>
      dateTime != null || validHeading != null || validPressure != null;
  double? get validHeading =>
      heading != null && heading!.isFinite ? heading! % 360 : null;
  double? get validPressure =>
      pressure != null && pressure!.isFinite && pressure! > 0 ? pressure : null;
}
