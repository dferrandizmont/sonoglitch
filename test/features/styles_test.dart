import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/features/styles/style_copy.dart';
import 'package:sonoglitch/features/styles/style_sheet.dart';
import 'package:sonoglitch/features/styles/styles_screen.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

Future<void> pumpStyles(
  WidgetTester tester,
  StyleController styles, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StylesScreen(styles: styles),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tile of the style that is called [styleName].
Finder tileOf(String styleName) =>
    find.ancestor(of: find.text(styleName), matching: find.byType(StyleTile));

/// The check that marks the style that is selected, inside its own tile.
Finder checkOf(String styleName) =>
    find.descendant(of: tileOf(styleName), matching: find.byIcon(Icons.check));

/// The badge that marks the style that is selected, inside its own tile.
Finder badgeOf(String styleName) =>
    find.descendant(of: tileOf(styleName), matching: find.text('SELECTED'));

void main() {
  testWidgets('shows every style and marks the selected one', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final styles = StyleController(log: DebugLog());
    // Keep the entire selectable grid visible for the availability assertions.
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpStyles(tester, styles);

    for (final style in kStyles) {
      expect(find.text(style.name), findsOneWidget, reason: style.id);
      // Every style says what it does.
      expect(
        find.text(styleDescription(l10n, style.id)),
        findsOneWidget,
        reason: style.id,
      );
    }
    for (final style in kRegisteredStyles.where(
      (style) => style.isPlaceholder,
    )) {
      expect(find.text(style.name), findsNothing, reason: style.id);
    }
    // The badge of the free styles is gone.
    expect(find.text('Free'), findsNothing);
    // The first style is the selected one.
    expect(find.text('SELECTED'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('choosing a style selects it', (tester) async {
    final styles = StyleController(log: DebugLog());
    await pumpStyles(tester, styles);

    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();

    expect(styles.style.id, kStyles[1].id);
    // The badge and the mark move to the style that was chosen.
    expect(find.text('SELECTED'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('the selection moves to the tile that was tapped', (
    tester,
  ) async {
    final styles = StyleController(log: DebugLog());
    await pumpStyles(tester, styles);

    // The first style is the one that is selected.
    expect(checkOf(kStyles[0].name), findsOneWidget);
    expect(checkOf(kStyles[1].name), findsNothing);
    expect(badgeOf(kStyles[0].name), findsOneWidget);
    expect(badgeOf(kStyles[1].name), findsNothing);

    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();

    expect(styles.style.id, kStyles[1].id);
    // The check and the badge belong to the tile that was tapped.
    expect(checkOf(kStyles[1].name), findsOneWidget);
    expect(checkOf(kStyles[0].name), findsNothing);
    expect(badgeOf(kStyles[1].name), findsOneWidget);
    expect(badgeOf(kStyles[0].name), findsNothing);
  });

  testWidgets('the selected style is the one of the semantics', (tester) async {
    final styles = StyleController(log: DebugLog());
    await pumpStyles(tester, styles);

    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();

    final selected = tester.getSemantics(
      find
          .byType(StyleTile)
          .at(kStyles.indexWhere((s) => s.id == kStyles[1].id)),
    );
    final other = tester.getSemantics(
      find
          .byType(StyleTile)
          .at(kStyles.indexWhere((s) => s.id == kStyles[0].id)),
    );
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    expect(other.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('the style that is selected is the one of the controller', (
    tester,
  ) async {
    final styles = StyleController(log: DebugLog());
    await styles.select(kStyles[2]);
    await pumpStyles(tester, styles);

    expect(styles.style.id, kStyles[2].id);
    expect(find.text('SELECTED'), findsOneWidget);
  });
  testWidgets('styles rows and selected badge fit 320x568 at 1.3x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final styles = StyleController(log: DebugLog());
    addTearDown(styles.dispose);
    await pumpStyles(tester, styles, textScale: 1.3);
    for (final style in styles.styles) {
      final row = tileOf(style.name);
      await tester.scrollUntilVisible(row, 60);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(60));
      expect(tester.getSize(row).width, greaterThanOrEqualTo(48));
    }
    await tester.scrollUntilVisible(tileOf(kStyles.first.name), -60);
    final badge = tester.widget<Text>(badgeOf(kStyles.first.name));
    expect(badge.style!.color, AppTheme.accent);
    expect(badge.style!.fontSize, 10);
    expect(tester.takeException(), isNull);
  });
}
