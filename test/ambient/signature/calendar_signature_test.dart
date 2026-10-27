import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/signature/calendar_signature.dart';

void main() {
  test('warmth matches all civil-hour control points', () {
    const points = {
      0: -1.0,
      5: -1.0,
      8: 0.0,
      12: .15,
      16: .2,
      19: 1.0,
      22: -1.0,
      24: -1.0,
    };
    for (final point in points.entries) {
      expect(
        calendarSignature(DateTime.utc(2024, 2, 1, point.key)).warmth,
        closeTo(point.value, 1e-12),
      );
    }
  });

  test('smoothstep segments are monotonic and midnight is continuous', () {
    const hours = [0, 5, 8, 12, 16, 19, 22, 24];
    for (var i = 0; i < hours.length - 1; i++) {
      var previous = calendarSignature(DateTime.utc(2024, 1, 1, hours[i]))
          .warmth;
      for (
        var minute = hours[i] * 60 + 1;
        minute <= hours[i + 1] * 60;
        minute++
      ) {
        final value = calendarSignature(DateTime.utc(2024, 1, 1, 0, minute))
            .warmth;
        expect(
          i == 5 ? value <= previous + 1e-12 : value >= previous - 1e-12,
          isTrue,
        );
        previous = value;
      }
    }
    expect(
      calendarSignature(DateTime.utc(2024, 1, 1, 23, 59, 59, 999, 999)).warmth,
      -1,
    );
    expect(calendarSignature(DateTime.utc(2024, 1, 2)).warmth, -1);
  });

  test('hue uses the real leap/non-leap year length and UTC moon epoch', () {
    for (final year in [2023, 2024]) {
      final date = DateTime.utc(year, 3, 1, 12);
      final start = DateTime.utc(year);
      final days = year == 2024 ? 366 : 365;
      final angle =
          2 *
          math.pi *
          date.difference(start).inMicroseconds /
          (days * Duration.microsecondsPerDay);
      final phase = moonAge(date) / synodicMonth;
      final result = calendarSignature(date);
      expect(
        result.hue,
        closeTo(
          .75 * math.sin(angle) + .25 * math.cos(2 * math.pi * phase),
          1e-12,
        ),
      );
    }
    final epoch = calendarSignature(DateTime.utc(2000, 1, 6, 18, 14));
    expect(epoch.moonPhase, 0);
    expect(epoch.moonIllumination, 0);
    final full = calendarSignature(
      DateTime.utc(2000, 1, 6, 18, 14).add(
        Duration(
          microseconds: (synodicMonth / 2 * Duration.microsecondsPerDay)
              .round(),
        ),
      ),
    );
    expect(full.moonPhase, closeTo(.5, 1e-10));
    expect(full.moonIllumination, closeTo(1, 1e-10));
  });

  test('local DST transition dates follow civil hour and elapsed local year', () {
    // Host timezone is deliberately not changed. These assertions cover both
    // DST and non-DST hosts, including a 23/25-hour day when locally available.
    for (final monthDay in [(3, 31), (10, 27)]) {
      final date = DateTime(2024, monthDay.$1, monthDay.$2, 8);
      final result = calendarSignature(date);
      expect(result.warmth, 0);
      final fraction =
          date.difference(DateTime(2024)).inMicroseconds /
          DateTime(2025).difference(DateTime(2024)).inMicroseconds;
      expect(
        result.hue,
        closeTo(
          .75 * math.sin(2 * math.pi * fraction) +
              .25 * math.cos(2 * math.pi * result.moonPhase),
          1e-12,
        ),
      );
      final evening = DateTime(2024, monthDay.$1, monthDay.$2, 19);
      expect(calendarSignature(evening).warmth, 1);
    }
  });
}
