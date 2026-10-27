import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/theme/app_theme.dart';

void main() {
  testWidgets(
    'tonal buttons use a neutral container instead of a warm signal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FilledButton.tonal(
              onPressed: () {},
              child: const Text('Share'),
            ),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppTheme.surfaceHigh);
      expect(
        (material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(4),
      );
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  test('selection combines tint with a visible accent border', () {
    final theme = AppTheme.dark();
    expect(theme.chipTheme.selectedColor, AppTheme.accentTint);
    final border = theme.chipTheme.side! as WidgetStateBorderSide;
    expect(border.resolve({WidgetState.selected})!.color, AppTheme.accent);
    expect(border.resolve({})!.color, AppTheme.edge);
    expect(theme.colorScheme.outline, AppTheme.edge);
    expect(theme.colorScheme.outlineVariant, AppTheme.outline);
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
    expect(theme.splashFactory, InkRipple.splashFactory);
  });

  test('switch roles and button interaction overlays follow the theme', () {
    final theme = AppTheme.dark();
    expect(
      theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
      AppTheme.accent,
    );
    expect(
      theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
      AppTheme.onAccent,
    );
    expect(theme.switchTheme.trackColor!.resolve({}), AppTheme.background);
    expect(theme.switchTheme.trackOutlineColor!.resolve({}), AppTheme.edge);
    expect(theme.switchTheme.thumbColor!.resolve({}), AppTheme.textSecondary);
    for (final style in [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.iconButtonTheme.style!,
    ]) {
      expect(
        style.overlayColor!.resolve({WidgetState.pressed}),
        AppTheme.pressedOverlay,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.focused}),
        AppTheme.focusOverlay,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.disabled}),
        Colors.transparent,
      );
    }
  });

  testWidgets('motion duration respects the system preference', (tester) async {
    for (final reduced in [false, true]) {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Builder(
            builder: (context) {
              duration = AppTheme.motionDuration(
                context,
                AppTheme.sheetDuration,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        duration,
        reduced ? Duration.zero : const Duration(milliseconds: 220),
      );
    }
  });
}
