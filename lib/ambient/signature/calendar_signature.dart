import 'dart:math' as math;

import '../context_sensors.dart';

/// Ephemeral civil-time palette descriptors, evaluated at the supplied instant.
class CalendarSignature {
  const CalendarSignature({
    this.warmth = 0,
    this.hue = 0,
    this.moonPhase = 0,
    this.moonIllumination = 0,
  });

  final double warmth;
  final double hue;
  final double moonPhase;
  final double moonIllumination;
}

/// Uses civil hours for warmth and actual elapsed local-year duration for hue.
/// Supply local time (UTC is also supported for deterministic callers). The
/// owner refreshes at 1 Hz while active and freezes the result at the shutter.
CalendarSignature calendarSignature(DateTime local) {
  const hours = [0.0, 5.0, 8.0, 12.0, 16.0, 19.0, 22.0, 24.0];
  const values = [-1.0, -1.0, 0.0, .15, .2, 1.0, -1.0, -1.0];
  final h =
      local.hour +
      local.minute / 60 +
      local.second / 3600 +
      (local.millisecond * 1000 + local.microsecond) / 3600000000;
  var i = 0;
  while (i < hours.length - 2 && h > hours[i + 1]) {
    i++;
  }
  final t = ((h - hours[i]) / (hours[i + 1] - hours[i])).clamp(0.0, 1.0);
  final warmth = values[i] + (values[i + 1] - values[i]) * t * t * (3 - 2 * t);
  final start = local.isUtc ? DateTime.utc(local.year) : DateTime(local.year);
  final end = local.isUtc
      ? DateTime.utc(local.year + 1)
      : DateTime(local.year + 1);
  final angle =
      2 *
      math.pi *
      local.difference(start).inMicroseconds /
      end.difference(start).inMicroseconds;
  final phase = moonAge(local) / synodicMonth;
  final moonCos = math.cos(2 * math.pi * phase);
  return CalendarSignature(
    warmth: warmth,
    hue: (.75 * math.sin(angle) + .25 * moonCos).clamp(-1.0, 1.0),
    moonPhase: phase,
    moonIllumination: (1 - moonCos) / 2,
  );
}
