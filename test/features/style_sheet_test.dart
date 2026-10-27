import 'dart:async';
import 'dart:math';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/features/styles/style_copy.dart';
import 'package:sonoglitch/features/styles/style_sheet.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/browsing_fakes.dart';

/// A controller whose renderers never touch a shader.
StyleController fakeStyles({Random? random}) {
  final controller = StyleController(
    log: DebugLog(),
    random: random,
    loader: (style) async => FakeBrowsingRenderer(style),
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Opens the sheet of the styles over a button that shows it.
Future<void> pumpSheet(
  WidgetTester tester, {
  required StyleController styles,
  required void Function(String styleId) onSelect,
  VoidCallback? onRandom,
  VoidCallback? onMatch,
  double textScale = 1,
  bool reducedMotion = false,
  Size screen = const Size(400, 900),
}) async {
  // The sheet may use the 70% of the screen, so the screen is made big
  // enough to show the whole list of the styles.
  tester.view.physicalSize = screen * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showStyleSheet(
                context,
                styles: styles.styles,
                selectedStyleId: styles.style.id,
                onSelect: onSelect,
                onRandom: onRandom ?? () {},
                onMatch: onMatch ?? () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet shows the name and the description of every style', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final styles = fakeStyles();

    await pumpSheet(tester, styles: styles, onSelect: (_) {});

    expect(find.text('Styles'), findsOneWidget);
    expect(find.byType(StyleTile), findsNWidgets(kStyles.length));
    for (final style in kStyles) {
      expect(find.text(style.name), findsOneWidget, reason: style.id);
      expect(
        find.text(styleDescription(l10n, style.id)),
        findsOneWidget,
        reason: style.id,
      );
    }
  });

  testWidgets('the tile of the style that is selected says so', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final styles = fakeStyles();
      await styles.select(kStyles[2]);

      await pumpSheet(tester, styles: styles, onSelect: (_) {});

      final tiles = tester
          .widgetList<StyleTile>(find.byType(StyleTile))
          .toList();
      expect(tiles[kStyles.indexOf(kStyles[2])].isSelected, isTrue);
      expect(
        tiles.where((tile) => tile.isSelected).length,
        1,
        reason: 'only one style is selected',
      );
      expect(find.byIcon(Icons.check), findsOneWidget);

      // The screen reader also knows which one is selected.
      final node = tester.getSemantics(find.byType(StyleTile).at(2));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping a tile selects the style and closes the sheet', (
    tester,
  ) async {
    final styles = fakeStyles();
    String? selected;

    await pumpSheet(tester, styles: styles, onSelect: (id) => selected = id);

    await tester.tap(find.text(kStyles[1].name));
    await tester.pumpAndSettle();

    expect(selected, kStyles[1].id);
    expect(
      find.byType(StyleSheet),
      findsNothing,
      reason: 'the sheet closes itself once the style is chosen',
    );
  });

  testWidgets('the random button asks for a random style', (tester) async {
    final styles = fakeStyles();
    var asked = 0;

    await pumpSheet(
      tester,
      styles: styles,
      onSelect: (_) {},
      onRandom: () => asked++,
    );

    await tester.tap(find.text('Random'));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(find.byType(StyleSheet), findsNothing);
  });

  testWidgets('the random action picks another style', (tester) async {
    final styles = fakeStyles(random: FixedRandom(0));
    final actions = StyleSheetActions(
      styles: styles,
      ambient: ValueNotifier<AmbientState>(AmbientState.calm),
    );

    await pumpSheet(
      tester,
      styles: styles,
      onSelect: (_) {},
      onRandom: () => unawaited(actions.random()),
    );

    await tester.tap(find.text('Random'));
    await tester.pumpAndSettle();

    expect(styles.style.id, isNot(kStyles.first.id));
    expect(styles.style.id, kStyles[1].id);
  });

  testWidgets('matching the place picks the style of a loud place', (
    tester,
  ) async {
    final styles = fakeStyles();
    // The place is loud, so the style that breaks the picture the most
    // is the one that fits.
    final ambient = ValueNotifier<AmbientState>(
      const AmbientState(noise: 0.9, light: 0.5),
    );
    final actions = StyleSheetActions(styles: styles, ambient: ambient);
    await styles.select(kStyles[1]);

    await pumpSheet(
      tester,
      styles: styles,
      onSelect: (_) {},
      onMatch: () => unawaited(actions.match()),
    );

    await tester.tap(find.text('Match this place'));
    await tester.pumpAndSettle();

    expect(styles.style.id, 'static');
    expect(find.byType(StyleSheet), findsNothing);
  });

  testWidgets('the sheet never covers more than the 70% of the screen', (
    tester,
  ) async {
    final styles = fakeStyles();

    await pumpSheet(tester, styles: styles, onSelect: (_) {});

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byType(StyleSheet)).height,
      lessThanOrEqualTo(screen * 0.7 + 1),
    );
  });

  testWidgets('the sheet fits a small screen with the text at 1.3', (
    tester,
  ) async {
    final styles = fakeStyles();

    await pumpSheet(
      tester,
      styles: styles,
      onSelect: (_) {},
      textScale: 1.3,
      screen: const Size(320, 568),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Random'), findsOneWidget);
    expect(find.text('Match this place'), findsOneWidget);
  });
  testWidgets('compact sheet has adjacent 48 dp actions and 60 dp rows', (
    tester,
  ) async {
    final styles = fakeStyles();
    await pumpSheet(
      tester,
      styles: styles,
      onSelect: (_) {},
      textScale: 1.3,
      screen: const Size(320, 568),
      reducedMotion: true,
    );
    final route = ModalRoute.of(tester.element(find.byType(StyleSheet)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    final actions = find.descendant(
      of: find.byType(StyleSheet),
      matching: find.byType(OutlinedButton),
    );
    expect(actions, findsNWidgets(2));
    final first = tester.getRect(actions.first);
    final second = tester.getRect(actions.last);
    for (final rect in [first, second]) {
      expect(rect.height, 48);
      expect(rect.width, greaterThanOrEqualTo(48));
    }
    expect(first.top, second.top);
    expect(first.overlaps(second), isFalse);
    for (final button in tester.widgetList<OutlinedButton>(actions)) {
      expect(button.style!.animationDuration, Duration.zero);
    }
    for (final style in styles.styles) {
      final row = find.byWidgetPredicate(
        (widget) => widget is StyleTile && widget.style.id == style.id,
      );
      await tester.scrollUntilVisible(
        row,
        60,
        scrollable: find.descendant(
          of: find.byType(StyleSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(60));
      expect(tester.getSize(row).width, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected row has tint, left rule, number and a plain check', (
    tester,
  ) async {
    final styles = fakeStyles();
    await styles.select(kStyles[1]);
    await pumpSheet(tester, styles: styles, onSelect: (_) {});
    final selected = find.byWidgetPredicate(
      (widget) => widget is StyleTile && widget.isSelected,
    );
    final ink = tester.widget<Ink>(
      find.descendant(of: selected, matching: find.byType(Ink)),
    );
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, AppTheme.accentTint);
    expect(
      (decoration.border! as Border).left,
      const BorderSide(color: AppTheme.accent, width: 2),
    );
    expect(decoration.borderRadius, isNull);
    expect(
      find.descendant(of: selected, matching: find.text('02')),
      findsOneWidget,
    );
    final check = tester.widget<Icon>(
      find.descendant(of: selected, matching: find.byIcon(Icons.check)),
    );
    expect(check.color, AppTheme.accent);
    expect(check.size, 20);
    final name = tester.widget<Text>(
      find.descendant(of: selected, matching: find.text(kStyles[1].name)),
    );
    expect(name.style!.fontWeight, FontWeight.w600);
  });

  testWidgets('selection and held press paint on the sheet Material', (
    tester,
  ) async {
    await pumpSheet(tester, styles: fakeStyles(), onSelect: (_) {});
    final selected = find.byWidgetPredicate(
      (widget) => widget is StyleTile && widget.isSelected,
    );
    final ink = find.descendant(of: selected, matching: find.byType(Ink));
    final material = find
        .ancestor(of: ink, matching: find.byType(Material))
        .first;
    // The ink host must live INSIDE the sheet chrome. The old opaque
    // DecoratedBox painted above a host outside StyleSheet and hid all ink.
    expect(
      find.ancestor(of: material, matching: find.byType(StyleSheet)),
      findsOneWidget,
    );
    expect(tester.widget<Material>(material).color, AppTheme.surface);
    tester.element(ink).visitAncestorElements((ancestor) {
      if (ancestor.widget is Material) return false;
      final widget = ancestor.widget;
      if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        expect(
          decoration.color?.a ?? 0,
          0,
          reason: 'No background may cover the Material ink',
        );
        expect(decoration.image, isNull);
        expect(decoration.gradient, isNull);
      }
      if (widget is ColoredBox) expect(widget.color.a, 0);
      return true;
    });
    final controller = Material.of(tester.element(ink));
    expect(
      controller,
      paints..something(
        (method, arguments) =>
            method == #drawRect &&
            (arguments[1] as Paint).color.toARGB32() ==
                AppTheme.accentTint.toARGB32(),
      ),
    );
    expect(
      controller,
      paints..something(
        (method, arguments) =>
            method == #drawPath &&
            (arguments[1] as Paint).color.toARGB32() ==
                AppTheme.accent.toARGB32(),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(selected));
    try {
      // Resolve the scrollable's tap deadline, then finish the highlight fade.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        controller,
        paints..something(
          (method, arguments) =>
              method == #drawRect &&
              (arguments[1] as Paint).color.toARGB32() ==
                  AppTheme.pressedOverlay.toARGB32(),
        ),
      );
    } finally {
      await gesture.cancel();
    }
    await tester.pumpAndSettle();
    expect(find.byType(StyleSheet), findsOneWidget);
  });
}
