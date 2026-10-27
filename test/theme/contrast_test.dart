import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/theme/app_theme.dart';

double contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  // All text, including quiet labels and button text, needs WCAG AA contrast.
  for (final (name, foreground, background) in [
    ('textPrimary/background', AppTheme.textPrimary, AppTheme.background),
    ('textPrimary/surface', AppTheme.textPrimary, AppTheme.surface),
    ('textSecondary/background', AppTheme.textSecondary, AppTheme.background),
    ('textSecondary/surface', AppTheme.textSecondary, AppTheme.surface),
    ('accent/background', AppTheme.accent, AppTheme.background),
    ('onAccent/accent', AppTheme.onAccent, AppTheme.accent),
    ('textTertiary/background', AppTheme.textTertiary, AppTheme.background),
    ('textTertiary/surface', AppTheme.textTertiary, AppTheme.surface),
  ]) {
    test('$name text contrast is at least 4.5:1', () {
      final ratio = contrast(foreground, background);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            '$name is ${ratio.toStringAsFixed(3)}:1; keep the specified '
            'colours and report a failure to the design owner.',
      );
    });
  }

  test('signalCyan/background graphics contrast is at least 3:1', () {
    final ratio = contrast(AppTheme.signalCyan, AppTheme.background);
    expect(
      ratio,
      greaterThanOrEqualTo(3),
      reason: 'signalCyan/background is ${ratio.toStringAsFixed(3)}:1.',
    );
  });

  // White is the brightest possible live image. Check the actual composited
  // scrim, with the text roles used on each overlay rather than opaque surfaces.
  for (final (name, scrim, textColors) in [
    ('scrim', AppTheme.scrim, {'textPrimary': AppTheme.textPrimary}),
    (
      'scrimStrong',
      AppTheme.scrimStrong,
      {
        'textPrimary': AppTheme.textPrimary,
        'textSecondary': AppTheme.textSecondary,
        'accent': AppTheme.accent,
      },
    ),
  ]) {
    final background = Color.alphaBlend(scrim, Colors.white);
    for (final entry in textColors.entries) {
      test('${entry.key}/$name over white text contrast is at least 4.5:1', () {
        expect(contrast(entry.value, background), greaterThanOrEqualTo(4.5));
      });
    }
    // Enabled overlay icons, meter signals and status LEDs use these tokens.
    for (final entry in {
      'textPrimary': AppTheme.textPrimary,
      'textSecondary': AppTheme.textSecondary,
      'accent': AppTheme.accent,
      'warm': AppTheme.warm,
      'signalCyan': AppTheme.signalCyan,
      if (name == 'scrimStrong') 'danger': AppTheme.danger,
    }.entries) {
      test('${entry.key}/$name over white icon contrast is at least 3:1', () {
        expect(contrast(entry.value, background), greaterThanOrEqualTo(3));
      });
    }
  }
}
