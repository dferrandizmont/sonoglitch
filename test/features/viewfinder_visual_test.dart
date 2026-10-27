import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/features/styles/style_sheet.dart';
import 'package:sonoglitch/theme/app_theme.dart';
import 'package:sonoglitch/theme/fringe.dart';

import '../support/browsing_fakes.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

Finder keyed(String key) => find.byKey(ValueKey(key));
Finder get fringeTexts =>
    find.descendant(of: find.byType(FringeText), matching: find.byType(Text));

FocusNode targetFocus(WidgetTester tester, String key) => Focus.of(
  tester.element(
    find
        .descendant(of: keyed(key), matching: find.byType(GestureDetector))
        .first,
  ),
);

Finder focusChrome(String key) => find.descendant(
  of: keyed(key),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.position == DecorationPosition.foreground &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == AppTheme.focusOverlay,
  ),
);

StyleController selectableStyles() {
  final styles = StyleController(
    log: DebugLog(),
    // A reduced registry catches counters accidentally tied to kStyles.
    styles: [kStyles.first, kStyles[1], kStyles.last],
    loader: (style) async => FakeBrowsingRenderer(style),
  );
  addTearDown(styles.dispose);
  return styles;
}

Semantics shutterSemantics(WidgetTester tester) => tester.widget<Semantics>(
  find
      .ancestor(
        of: find.byTooltip('Take a photo'),
        matching: find.byType(Semantics),
      )
      .first,
);

Color discColor(WidgetTester tester) =>
    (tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: keyed('vf-shutter-disc'),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration)
        .color!;

Color ringColor(WidgetTester tester) =>
    (tester.widget<CustomPaint>(keyed('vf-shutter-ring')).painter
            as FringeRingPainter)
        .color;

void main() {
  const controls = [
    'vf-settings',
    'vf-style-prev',
    'vf-style-bar',
    'vf-style-next',
    'vf-auto-shot',
    'vf-shutter',
    'vf-flip',
  ];

  testWidgets(
    'keyboard traverses controls in reading order with visible focus',
    (tester) async {
      final harness = await pumpViewfinder(tester, styles: selectableStyles());
      await harness.settings.setTipsSeen(true);
      await tester.pump();
      // A keyboard event selects traditional highlight mode; pointer taps must
      // not leave a persistent focus tint on the live viewfinder.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      targetFocus(tester, controls.first).requestFocus();
      await tester.pump();
      for (var index = 0; index < controls.length; index++) {
        final key = controls[index];
        expect(targetFocus(tester, key).hasPrimaryFocus, isTrue, reason: key);
        final chrome = tester.widget<DecoratedBox>(focusChrome(key));
        final decoration = chrome.decoration as BoxDecoration;
        expect(decoration.border, Border.all(color: AppTheme.accent, width: 1));
        if (key == 'vf-shutter') {
          expect(decoration.shape, BoxShape.circle);
        } else {
          expect(decoration.borderRadius, BorderRadius.circular(4));
        }
        expect(
          tester.getSize(keyed(key)).shortestSide,
          greaterThanOrEqualTo(48),
        );
        if (index + 1 < controls.length) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(focusChrome(key), findsNothing);
        }
      }
      // Reverse traversal and directional D-pad movement share the same nodes.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(targetFocus(tester, 'vf-shutter').hasPrimaryFocus, isTrue);
      targetFocus(tester, 'vf-style-prev').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(targetFocus(tester, 'vf-style-bar').hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(targetFocus(tester, 'vf-style-next').hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final activation in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    for (final key in controls) {
      testWidgets('$key activates with ${activation.keyLabel}', (tester) async {
        final styles = selectableStyles();
        final harness = await pumpViewfinder(tester, styles: styles);
        targetFocus(tester, key).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(activation);
        await tester.pump();
        // Bounded pumps also work while Auto shot's ring repeats.
        await tester.pump(const Duration(milliseconds: 250));
        switch (key) {
          case 'vf-settings':
            expect(find.text('route'), findsOneWidget);
          case 'vf-style-prev':
            expect(styles.style.id, styles.styles.last.id);
          case 'vf-style-bar':
            expect(find.byType(StyleSheet), findsOneWidget);
          case 'vf-style-next':
            expect(styles.style.id, styles.styles[1].id);
          case 'vf-auto-shot':
            expect(keyed('moment-ring'), findsOneWidget);
          case 'vf-shutter':
            expect(harness.fakeCamera.captures, 1);
          case 'vf-flip':
            expect(harness.fakeCamera.flips, 1);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('overlay visuals are square 44 dp inside 48 dp hit targets', (
    tester,
  ) async {
    await pumpViewfinder(tester, styles: selectableStyles());
    for (final key in ['vf-settings', 'vf-auto-shot', 'vf-flip']) {
      final target = keyed(key);
      expect(tester.getSize(target), const Size.square(48));
      final face = find.descendant(
        of: target,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(face), const Size.square(44));
      final decoration =
          tester.widget<AnimatedContainer>(face).decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
      expect(decoration.color, AppTheme.scrim);
      expect(decoration.border, Border.all(color: AppTheme.overlayEdge));
    }
    await tester.tap(keyed('vf-auto-shot'));
    await tester.pump();
    final armed = tester.widget<AnimatedContainer>(
      find.descendant(
        of: keyed('vf-auto-shot'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((armed.decoration! as BoxDecoration).color, AppTheme.accent);
    expect((armed.decoration! as BoxDecoration).border, isNull);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: keyed('vf-auto-shot'),
              matching: find.byType(Icon),
            ),
          )
          .color,
      AppTheme.onAccent,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'rail uses uppercase names, the selectable count and wrapping arrows',
    (tester) async {
      final styles = selectableStyles();
      await pumpViewfinder(tester, styles: styles);
      expect(find.text(styles.style.name.toUpperCase()), findsOneWidget);
      expect(find.text('01/03'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('01/03')).style!.color,
        AppTheme.textSecondary,
      );
      final name = tester.widget<Text>(fringeTexts);
      expect(name.style!.fontSize, 13);
      expect(name.style!.letterSpacing, AppTheme.micro.letterSpacing);
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);

      await tester.tap(keyed('vf-style-next'));
      await tester.pump();
      expect(styles.style.id, styles.styles[1].id);
      expect(find.text('02/03'), findsOneWidget);
      expect(
        tester.widget<FringeText>(find.byType(FringeText)).text,
        styles.style.name.toUpperCase(),
      );
      await tester.tap(keyed('vf-style-prev'));
      await tester.pump();
      expect(find.text('01/03'), findsOneWidget);
      await tester.tap(keyed('vf-style-prev'));
      await tester.pump();
      expect(styles.style.id, styles.styles.last.id);
      expect(find.text('03/03'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(360, 640), const Size(412, 915)]) {
    testWidgets('rail segments touch without overlap at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpViewfinder(tester, styles: selectableStyles());
      final previous = tester.getRect(keyed('vf-style-prev'));
      final name = tester.getRect(keyed('vf-style-bar'));
      final next = tester.getRect(keyed('vf-style-next'));
      for (final rect in [previous, name, next]) {
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, 48);
      }
      expect(previous.right, name.left);
      expect(name.right, next.left);
      expect(previous.overlaps(name), isFalse);
      expect(name.overlaps(next), isFalse);
      expect(previous.overlaps(next), isFalse);
      expect(name.width, lessThanOrEqualTo(220));
      final dividers = find.descendant(
        of: keyed('vf-style-bar'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border ==
                  const Border.symmetric(
                    vertical: BorderSide(color: AppTheme.overlayEdge),
                  ),
        ),
      );
      expect(tester.getSize(dividers).height, 24);
      final shutter = tester.getRect(keyed('vf-shutter'));
      final status = tester.getRect(keyed('vf-status'));
      expect(shutter.size, const Size.square(76));
      expect(status.height, 24);
      expect(tester.getCenter(keyed('vf-auto-shot')).dx, size.width / 2 - 94);
      expect(tester.getCenter(keyed('vf-flip')).dx, size.width / 2 + 94);
      debugPrint(
        'VIS-B1 $size: prev=$previous name=$name next=$next '
        'status=$status shutter=$shutter',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('fringe plays once per selection; reduced motion=$reduced', (
      tester,
    ) async {
      final styles = selectableStyles();
      final harness = await pumpViewfinder(
        tester,
        styles: styles,
        mediaQuery: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
      );
      expect(fringeTexts, findsOneWidget);
      final state = tester.state(find.byType(FringeText));
      await tester.tap(keyed('vf-style-next'));
      await tester.pump();
      expect(tester.state(find.byType(FringeText)), same(state));
      expect(
        tester.widget<FringeText>(find.byType(FringeText)).value,
        ValueKey(styles.style.id),
      );
      expect(fringeTexts, reduced ? findsOneWidget : findsNWidgets(3));
      await tester.pump(const Duration(milliseconds: 90));
      expect(fringeTexts, reduced ? findsOneWidget : findsNWidgets(3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fringeTexts, findsOneWidget);
      // A settings notification rebuilds the rail without selecting a style.
      await harness.settings.setTipsSeen(true);
      await tester.pump();
      expect(fringeTexts, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(fringeTexts, findsOneWidget);
      // Re-selecting the same ID must not replay the fringe either.
      await styles.select(styles.style);
      await tester.pump();
      expect(fringeTexts, findsOneWidget);
      await tester.tap(keyed('vf-style-next'));
      await tester.pump();
      expect(fringeTexts, reduced ? findsOneWidget : findsNWidgets(3));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shutter press scales only the disc; reduced motion=$reduced', (
      tester,
    ) async {
      await pumpViewfinder(
        tester,
        styles: selectableStyles(),
        mediaQuery: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
      );
      final bounds = tester.getRect(keyed('vf-shutter'));
      final gesture = await tester.startGesture(bounds.center);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      final scale = tester.widget<AnimatedScale>(keyed('vf-shutter-disc'));
      expect(scale.scale, 0.92);
      expect(
        scale.duration,
        reduced ? Duration.zero : const Duration(milliseconds: 120),
      );
      expect(tester.getRect(keyed('vf-shutter')), bounds);
      await gesture.cancel();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(keyed('vf-shutter-disc')).scale, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'shutter size, semantics and static fringe survive idle, armed and busy',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final harness = await pumpViewfinder(
          tester,
          styles: FakeStyleController(log: DebugLog()),
          mediaQuery: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
        );
        final bounds = tester.getRect(keyed('vf-shutter'));
        expect(bounds.size, const Size.square(76));
        expect(shutterSemantics(tester).properties.button, isTrue);
        expect(shutterSemantics(tester).properties.enabled, isTrue);
        expect(shutterSemantics(tester).properties.label, 'Take a photo');
        expect(discColor(tester), AppTheme.textPrimary);
        expect(ringColor(tester), AppTheme.textPrimary);
        expect(
          find.ancestor(
            of: keyed('vf-shutter-ring'),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
        );
        final gesture = find.descendant(
          of: find.byTooltip('Take a photo'),
          matching: find.byType(GestureDetector),
        );
        expect(gesture, findsOneWidget);

        await tester.tap(keyed('vf-auto-shot'));
        await tester.pump();
        expect(tester.getRect(keyed('vf-shutter')), bounds);
        expect(shutterSemantics(tester).properties.enabled, isTrue);
        expect(ringColor(tester), AppTheme.accent);
        final ring = tester.getRect(keyed('moment-ring'));
        expect(ring.size, const Size.square(92));
        expect(ring.left - tester.getRect(keyed('vf-auto-shot')).right, 24);
        expect(tester.getRect(keyed('vf-flip')).left - ring.right, 24);
        await tester.pump(const Duration(milliseconds: 750));
        expect(tester.getRect(keyed('moment-ring')), ring);

        final gate = Completer<void>();
        harness.fakeCamera.captureGate = gate;
        await tester.tap(keyed('vf-shutter'));
        await tester.pump();
        expect(tester.getRect(keyed('vf-shutter')), bounds);
        expect(shutterSemantics(tester).properties.button, isTrue);
        expect(shutterSemantics(tester).properties.enabled, isFalse);
        expect(shutterSemantics(tester).properties.label, 'Take a photo');
        expect(discColor(tester), AppTheme.textSecondary);
        expect(ringColor(tester), AppTheme.accent);
        expect(tester.widget<GestureDetector>(gesture).onTap, isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.getSize(keyed('vf-status-led')), const Size.square(6));
        expect(
          tester
              .widget<ColoredBox>(
                find.descendant(
                  of: keyed('vf-status-led'),
                  matching: find.byType(ColoredBox),
                ),
              )
              .color,
          AppTheme.warm,
        );
        expect(
          tester.getSize(keyed('vf-status-tag')).width,
          lessThan(tester.getSize(keyed('vf-status')).width),
        );
        expect(tester.getCenter(keyed('vf-status-tag')).dx, bounds.center.dx);
        final opacity = find
            .ancestor(
              of: keyed('vf-status-led'),
              matching: find.byType(Opacity),
            )
            .first;
        expect(tester.widget<Opacity>(opacity).opacity, 1);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.widget<Opacity>(opacity).opacity, 1);
        gate.complete();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'capture LED blinks at 1 Hz; camera errors stay in the status slot',
    (tester) async {
      final harness = await pumpViewfinder(
        tester,
        styles: FakeStyleController(log: DebugLog()),
      );
      final gate = Completer<void>();
      harness.fakeCamera.captureGate = gate;
      final slot = tester.getRect(keyed('vf-status'));
      await tester.tap(keyed('vf-shutter'));
      await tester.pump();
      final opacity = find
          .ancestor(of: keyed('vf-status-led'), matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      // A missing still deliberately exercises the existing capture error path.
      gate.complete();
      await tester.pump();
      expect(tester.getRect(keyed('vf-status')), slot);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: keyed('vf-status-led'),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        AppTheme.danger,
      );
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(shutterSemantics(tester).properties.enabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
