import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_hud.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/features/settings/app_settings.dart';
import 'package:sonoglitch/features/settings/preferences_store.dart';

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
