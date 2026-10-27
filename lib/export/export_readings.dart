import 'dart:ui';

import 'export_layout.dart';

/// A measured number and its scale, independent of export typography.
class ExportReading {
  const ExportReading(
    this.label,
    this.value,
    this.level,
    this.dark,
    this.paper,
  );

  final String label;
  final String value;
  final double level;
  final Color dark;
  final Color paper;
}

double exportLevel(double value) =>
    value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0;

/// Missing instruments never masquerade as a zero reading or camera lux.
List<ExportReading> readingsOf(ExportLayoutValues? values) {
  if (values == null || values.readingsMode == ExportReadingsMode.hidden) {
    return const [];
  }
  final db = values.noiseDb;
  final lux = values.lux;
  final accel = values.accel;
  return [
    if (db != null && db.isFinite && db > 0)
      ExportReading(
        'dB',
        '${db.round()}',
        exportLevel(values.noise),
        const Color(0xFFB69CFF),
        const Color(0xFF6A4BD6),
      ),
    if (lux != null && lux.isFinite)
      ExportReading(
        'lx',
        formatLux(lux),
        exportLevel(values.light),
        const Color(0xFFFFB37A),
        const Color(0xFFE0852F),
      ),
    if (accel != null && accel.isFinite)
      ExportReading(
        'm/s²',
        accel.toStringAsFixed(accel.abs() >= 10 ? 1 : 2),
        exportLevel(values.motion),
        const Color(0xFF55E5F2),
        const Color(0xFF14A3B3),
      ),
  ];
}

String formatLux(double lux) => lux >= 10000
    ? '${(lux / 1000).toStringAsFixed(1)}k'
    : lux < 10
    ? lux.toStringAsFixed(1)
    : '${lux.round()}';

/// Whether the little square ladders under the numbers are printed.
bool showsExportLadders(ExportLayoutValues? values) =>
    (values?.readingsMode ?? ExportReadingsMode.full) ==
    ExportReadingsMode.full;

/// Whether the three ladders of the spectrum are printed.
bool showsExportSpectrum(ExportLayoutValues? values) =>
    showsExportLadders(values) && (values?.spectrumAvailable ?? false);

/// Whether anything of the readings is printed in the chosen mode.
bool hasExportReadings(ExportLayoutValues? values) =>
    readingsOf(values).isNotEmpty || showsExportSpectrum(values);

/// The mode that decides the sizes of the layout for these values.
ExportReadingsMode exportReadingsTier(ExportLayoutValues? values) =>
    ExportLayoutPlan.resolveMode(
      values?.readingsMode ?? ExportReadingsMode.full,
      readings: hasExportReadings(values),
    );
