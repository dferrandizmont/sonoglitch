import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/viewfinder/first_run_hint.dart';
import 'package:sonoglitch/features/viewfinder/level_legend.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/harness.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'compact inset hint dismisses and Settings restores it at $scale',
      (tester) async {
        const size = Size(320, 568);
        const padding = EdgeInsets.only(top: 48, bottom: 24);
        final media = MediaQueryData(
          size: size,
          padding: padding,
          textScaler: TextScaler.linear(scale),
        );
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harness = await pumpViewfinder(
          tester,
          mediaQuery: media,
          diagnostics: true,
        );
        void checkHint() {
          final hint = find.byType(FirstRunHint);
          expect(hint, findsOneWidget);
          final hintRect = tester.getRect(hint);
          for (final key in [
            'vf-meters',
            'vf-settings',
            'vf-style-bar',
            'vf-style-prev',
            'vf-style-next',
            'vf-auto-shot',
            'vf-shutter',
            'vf-flip',
          ]) {
            expect(
              hintRect.overlaps(tester.getRect(find.byKey(ValueKey(key)))),
              isFalse,
              reason: key,
            );
          }
          final targets = [
            find.byTooltip('Dismiss the tip'),
            find.descendant(of: hint, matching: find.byType(TextButton)),
          ];
          for (final target in targets) {
            final rect = tester.getRect(target);
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(target.hitTestable(), findsOneWidget);
          }
          expect(
            tester
                .getRect(targets.first)
                .overlaps(tester.getRect(targets.last)),
            isFalse,
          );
        }

        checkHint();
        await tester.tap(find.byTooltip('Dismiss the tip'));
        await tester.pump();
        expect(find.byType(FirstRunHint), findsNothing);
        expect(harness.settings.tipsSeen, isTrue);
        await pumpSettingsScreen(tester, harness.settings, mediaQuery: media);
        await tester.scrollUntilVisible(find.text('Show tips again'), 100);
        await tester.ensureVisible(find.text('Show tips again'));
        await tester.pump();
        await tester.tap(find.text('Show tips again'));
        await tester.pumpAndSettle();
        expect(harness.settings.tipsSeen, isFalse);
        await pumpViewfinder(
          tester,
          settings: harness.settings,
          mediaQuery: media,
          diagnostics: true,
        );
        checkHint();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'hint uses square chrome and zero feedback duration with reduced motion',
    (tester) async {
      await pumpViewfinder(
        tester,
        mediaQuery: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(1.3),
          disableAnimations: true,
        ),
      );
      final hint = find.byType(FirstRunHint);
      final card = tester.widget<Container>(
        find.descendant(of: hint, matching: find.byType(Container)).first,
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, AppTheme.scrimStrong);
      expect(decoration.borderRadius, BorderRadius.circular(AppTheme.radiusMd));
      expect(decoration.border, Border.all(color: AppTheme.overlayEdge));
      final help = tester.widget<TextButton>(
        find.descendant(of: hint, matching: find.byType(TextButton)),
      );
      expect(help.style!.animationDuration, Duration.zero);
      expect(find.text('HOW IT WORKS'), findsOneWidget);
      final close = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(IconButton),
        ),
      );
      expect(close.style!.animationDuration, Duration.zero);
      expect((close.icon as Icon).size, AppTheme.buttonIconSize);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the hint has 48 dp close and help targets and opens help', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);
    final hint = find.byType(FirstRunHint);
    for (final target in [
      find.byTooltip('Dismiss the tip'),
      find.descendant(of: hint, matching: find.byType(TextButton)),
    ]) {
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(
      find.descendant(of: hint, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HowItWorksSheet), findsOneWidget);
    expect(harness.settings.tipsSeen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the hint is shown and its close target remembers dismissal', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);

    expect(find.byType(FirstRunHint), findsOneWidget);
    expect(
      find.text(
        'Sound, light and movement bend the picture. Swipe to change style.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Dismiss the tip'));
    await tester.pump();

    expect(find.byType(FirstRunHint), findsNothing);
    expect(
      await harness.settings.store.getBool(
        AppSettings.tipsSeenKey,
        defaultValue: false,
      ),
      isTrue,
      reason: 'The tip must be remembered',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the tip can be read by the screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpViewfinder(tester);

      expect(
        find.bySemanticsLabel(
          'Sound, light and movement bend the picture. Swipe to change style.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Dismiss the tip'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the tip does not come back on its own', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await settings.setTipsSeen(true);

    await pumpViewfinder(tester, settings: settings);

    expect(find.byType(FirstRunHint), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the settings bring the tip back', (tester) async {
    final settings = AppSettings(store: InMemoryPreferencesStore());
    await settings.load();
    await settings.setTipsSeen(true);

    await pumpViewfinder(tester, settings: settings);
    expect(find.byType(FirstRunHint), findsNothing);

    // The settings have a row that shows the tip again.
    await pumpSettingsScreen(tester, settings);
    await tester.scrollUntilVisible(find.text('Show tips again'), 150);
    await tester.tap(find.text('Show tips again'));
    await tester.pumpAndSettle();

    expect(settings.tipsSeen, isFalse);
    expect(
      await settings.store.getBool(AppSettings.tipsSeenKey, defaultValue: true),
      isFalse,
      reason: 'The tip must be shown again',
    );

    // And the tip is waiting on the viewfinder.
    await pumpViewfinder(tester, settings: settings);
    expect(find.byType(FirstRunHint), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
