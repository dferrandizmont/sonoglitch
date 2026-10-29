import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_hud.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';
import 'package:sonoglitch/features/viewfinder/first_run_hint.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

const _keys = [
  'vf-meters',
  'vf-settings',
  'vf-style-bar',
  'vf-style-prev',
  'vf-style-next',
  'vf-auto-shot',
  'vf-shutter',
  'vf-flip',
  'vf-hint',
  'vf-status',
];

void main() {
  for (final language in ['en', 'es']) {
    testWidgets('full $language tip scrolls in a 270 dp viewport at 2x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(270, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: FirstRunHint(onDismiss: () {}, onHelp: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      final hint = find.byType(FirstRunHint);
      final l10n = AppLocalizations.of(tester.element(hint));
      final text = find.text(l10n.viewfinderHint);
      expect(text, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
      );
      final scrollable = find.descendant(
        of: hint,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final viewport = tester.getRect(scrollable);
      expect(tester.getRect(text).top, greaterThanOrEqualTo(viewport.top));
      await tester.drag(scrollable, Offset(0, -position.maxScrollExtent - 20));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(text).bottom,
        lessThanOrEqualTo(viewport.bottom + 0.01),
      );
      expect(
        find.byTooltip(l10n.viewfinderTipDismiss).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text(l10n.helpOpen.toUpperCase()).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [320.0, 393.0]) {
    for (final language in ['en', 'es']) {
      for (final diagnostics in [false, true]) {
        testWidgets(
          'full $language tip is readable at ${width}x568, 2x text, diagnostics $diagnostics',
          (tester) async {
            final size = Size(width, 568);
            const padding = EdgeInsets.only(top: 48, bottom: 24);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await pumpViewfinder(
              tester,
              styles: FakeStyleController(log: DebugLog()),
              locale: Locale(language),
              diagnostics: diagnostics,
              mediaQuery: MediaQueryData(
                size: size,
                padding: padding,
                textScaler: TextScaler.linear(2),
              ),
            );
            final hint = find.byKey(const ValueKey('vf-hint'));
            final l10n = AppLocalizations.of(tester.element(hint));
            final text = find.text(l10n.viewfinderHint);
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse);
            final hintRect = tester.getRect(hint);
            expect(hintRect.top, greaterThanOrEqualTo(padding.top));
            expect(hintRect.bottom, lessThanOrEqualTo(568 - padding.bottom));
            expect(hintRect.left, greaterThanOrEqualTo(0));
            expect(hintRect.right, lessThanOrEqualTo(width));
            for (final key in _keys.where((key) => key != 'vf-hint')) {
              expect(
                hintRect.overlaps(tester.getRect(find.byKey(ValueKey(key)))),
                isFalse,
                reason: 'Tip overlaps $key',
              );
            }
            final scrollable = find.descendant(
              of: hint,
              matching: find.byType(Scrollable),
            );
            // Every part of the paragraph must be reachable, including the
            // final sentence when the viewport requires scrolling.
            final position = tester.state<ScrollableState>(scrollable).position;
            final viewport = tester.getRect(scrollable);
            expect(viewport.height, greaterThan(0));
            expect(
              tester.getRect(text).top,
              greaterThanOrEqualTo(viewport.top),
            );
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            expect(
              tester.getRect(text).bottom,
              lessThanOrEqualTo(viewport.bottom + 0.01),
            );
            expect(
              find.byTooltip(l10n.viewfinderTipDismiss).hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            // Style feedback must also fit above the tip while it is open.
            await tester.tap(find.byKey(const ValueKey('vf-style-next')));
            await tester.pump();
            expect(find.text(l10n.viewfinderHint), findsOneWidget);
            expect(
              tester.getRect(hint).bottom,
              lessThanOrEqualTo(
                tester.getRect(find.byKey(const ValueKey('vf-style-bar'))).top,
              ),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final size in [const Size(320, 568), const Size(393, 852)]) {
    testWidgets(
      'viewfinder at 2x text has full semantic touch targets on $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        try {
          await pumpViewfinder(
            tester,
            styles: FakeStyleController(log: DebugLog()),
            locale: const Locale('es'),
            mediaQuery: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(2),
            ),
          );
          for (final key in [
            'vf-settings',
            'vf-auto-shot',
            'vf-flip',
            'vf-style-prev',
            'vf-style-next',
            'vf-shutter',
          ]) {
            final target = find.byKey(ValueKey(key));
            expect(target.hitTestable(), findsOneWidget);
            expect(
              tester.getSize(target).width,
              greaterThanOrEqualTo(48),
              reason: key,
            );
            expect(
              tester.getSize(target).height,
              greaterThanOrEqualTo(48),
              reason: key,
            );
            final rect = tester.getSemantics(target).rect;
            expect(rect.width, greaterThanOrEqualTo(48), reason: key);
            expect(rect.height, greaterThanOrEqualTo(48), reason: key);
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tester.tap(find.byKey(const ValueKey('vf-auto-shot')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final size in [
    const Size(360, 640),
    const Size(393, 852),
    const Size(412, 915),
    const Size(320, 568),
  ]) {
    for (final padding in [
      EdgeInsets.zero,
      const EdgeInsets.only(top: 48, bottom: 24),
    ]) {
      for (final scale in [1.0, 1.3]) {
        for (final hint in [false, true]) {
          for (final diagnostics in [false, true]) {
            for (final state in ['idle', 'armed', 'capturing']) {
              testWidgets(
                '$size padding $padding scale $scale hint $hint diagnostics $diagnostics $state',
                (tester) async {
                  await tester.binding.setSurfaceSize(size);
                  addTearDown(() => tester.binding.setSurfaceSize(null));
                  final settings = AppSettings(
                    store: InMemoryPreferencesStore(),
                  );
                  await settings.load();
                  await settings.setTipsSeen(!hint);
                  final harness = await pumpViewfinder(
                    tester,
                    styles: FakeStyleController(log: DebugLog()),
                    settings: settings,
                    diagnostics: diagnostics,
                    locale: const Locale('es'),
                    mediaQuery: MediaQueryData(
                      size: size,
                      padding: padding,
                      textScaler: TextScaler.linear(scale),
                    ),
                  );
                  if (diagnostics) harness.ambient.setManual(true);
                  Completer<void>? gate;
                  if (state == 'armed') {
                    await tester.tap(
                      find.byKey(const ValueKey('vf-auto-shot')),
                    );
                  } else if (state == 'capturing') {
                    gate = Completer<void>();
                    harness.fakeCamera.captureGate = gate;
                    await tester.tap(find.byKey(const ValueKey('vf-shutter')));
                  }
                  await tester.pump();
                  final rects = <String, Rect>{};
                  final safe = Rect.fromLTRB(
                    padding.left,
                    padding.top,
                    size.width - padding.right,
                    size.height - padding.bottom,
                  );
                  for (final key in _keys) {
                    final finder = find.byKey(ValueKey(key));
                    if (key == 'vf-hint' && !hint) {
                      expect(finder, findsNothing);
                      continue;
                    }
                    expect(finder, findsOneWidget, reason: key);
                    final rect = tester.getRect(finder);
                    rects[key] = rect;
                    expect(
                      rect.left,
                      greaterThanOrEqualTo(safe.left),
                      reason: key,
                    );
                    expect(
                      rect.top,
                      greaterThanOrEqualTo(safe.top),
                      reason: key,
                    );
                    expect(
                      rect.right,
                      lessThanOrEqualTo(safe.right),
                      reason: key,
                    );
                    expect(
                      rect.bottom,
                      lessThanOrEqualTo(safe.bottom),
                      reason: key,
                    );
                    if (key != 'vf-status') {
                      expect(rect.width, greaterThanOrEqualTo(48), reason: key);
                      expect(
                        rect.height,
                        greaterThanOrEqualTo(48),
                        reason: key,
                      );
                    } else {
                      expect(rect.height, 24);
                    }
                  }
                  final entries = rects.entries.toList();
                  for (var i = 0; i < entries.length; i++) {
                    for (var j = i + 1; j < entries.length; j++) {
                      expect(
                        entries[i].value.overlaps(entries[j].value),
                        isFalse,
                        reason: '${entries[i].key} overlaps ${entries[j].key}',
                      );
                    }
                  }
                  expect(
                    rects['vf-shutter']!.center.dx,
                    closeTo(size.width / 2, 0.5),
                  );
                  expect(rects['vf-auto-shot']!.center.dx, size.width / 2 - 94);
                  expect(rects['vf-flip']!.center.dx, size.width / 2 + 94);
                  if (diagnostics) {
                    final hud = tester.getRect(find.byType(DebugHud));
                    for (final rect in rects.values) {
                      expect(hud.overlaps(rect), isFalse);
                    }
                    final controls = find.descendant(
                      of: find.byType(DebugHud),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is Slider ||
                            widget is Switch ||
                            (widget is GestureDetector &&
                                widget.onTap != null &&
                                widget.child is Container),
                      ),
                    );
                    expect(
                      find.descendant(
                        of: find.byType(DebugHud),
                        matching: find.byType(Slider),
                      ),
                      findsNWidgets(3),
                    );
                    expect(controls.evaluate().length, greaterThanOrEqualTo(6));
                    // Diagnostics scroll in both axes. Measure each actual
                    // interactive child after bringing it into its viewport,
                    // rather than claiming its offscreen layout is reachable.
                    for (final element in controls.evaluate().toList()) {
                      await Scrollable.ensureVisible(element, alignment: 0.5);
                      await tester.pump();
                      final target = find.byElementPredicate(
                        (candidate) => identical(candidate, element),
                      );
                      // A slider can be wider than the horizontal viewport;
                      // only its clipped, painted portion is interactive.
                      final rect = tester
                          .getRect(target)
                          .intersect(hud)
                          .intersect(safe);
                      expect(target.hitTestable(), findsOneWidget);
                      expect(rect.isEmpty, isFalse);
                      expect(hud.contains(rect.topLeft), isTrue);
                      expect(
                        hud.contains(
                          rect.bottomRight - const Offset(0.01, 0.01),
                        ),
                        isTrue,
                      );
                      for (final other in rects.entries) {
                        expect(
                          rect.overlaps(other.value),
                          isFalse,
                          reason:
                              'Diagnostics ${element.widget.runtimeType} overlaps ${other.key}',
                        );
                      }
                      final viewport = tester
                          .getRect(
                            find.descendant(
                              of: find.byType(DebugHud),
                              matching: find.byType(SingleChildScrollView),
                            ),
                          )
                          .intersect(hud)
                          .intersect(safe);
                      final visible = controls
                          .evaluate()
                          .map(
                            (child) => tester
                                .getRect(
                                  find.byElementPredicate(
                                    (candidate) => identical(candidate, child),
                                  ),
                                )
                                .intersect(viewport),
                          )
                          .where((bounds) => !bounds.isEmpty)
                          .toList();
                      for (var i = 0; i < visible.length; i++) {
                        for (var j = i + 1; j < visible.length; j++) {
                          expect(
                            visible[i].overlaps(visible[j]),
                            isFalse,
                            reason:
                                'Visible diagnostics targets overlap: ${visible[i]} and ${visible[j]}',
                          );
                        }
                      }
                    }
                  }
                  expect(tester.takeException(), isNull);
                  // Report the measured canonical geometry, with first-run hint.
                  if (padding == EdgeInsets.zero &&
                      scale == 1 &&
                      hint &&
                      !diagnostics &&
                      state == 'idle' &&
                      size.width != 393) {
                    debugPrint('UI-B layout $size: $rects');
                  }
                  gate?.complete();
                  await tester.pump();
                  await tester.pumpWidget(const SizedBox.shrink());
                  expect(tester.takeException(), isNull);
                },
              );
            }
          }
        }
      }
    }
  }
}
