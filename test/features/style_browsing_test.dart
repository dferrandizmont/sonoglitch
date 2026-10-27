import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/app_config.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/effect_view.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';
import 'package:sonoglitch/features/viewfinder/level_legend.dart';

import '../support/browsing_fakes.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

final preview = find.byKey(const ValueKey('style-preview'));
final feedback = find.byKey(const ValueKey('style-feedback'));

StyleController fakeStyles({FixedRandom? random, RendererLoader? loader}) {
  final controller = StyleController(
    log: DebugLog(),
    random: random,
    loader: loader ?? (style) async => FakeBrowsingRenderer(style),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> swipe(WidgetTester tester, double dx) async {
  await tester.dragFrom(
    Offset(tester.getCenter(preview).dx, 150),
    Offset(dx, 0),
  );
  await tester.pump();
}

void main() {
  testWidgets('arrows wrap and the pill names the selected style', (
    tester,
  ) async {
    final styles = fakeStyles();
    final semantics = tester.ensureSemantics();
    try {
      await pumpViewfinder(tester, styles: styles);
      await tester.tap(find.byKey(const ValueKey('vf-style-prev')));
      await tester.pump();
      expect(styles.style.id, kStyles.last.id);
      expect(
        find.bySemanticsLabel('Style: ${kStyles.last.name}. Tap to choose'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('vf-style-next')));
      await tester.pump();
      expect(styles.style.id, kStyles.first.id);
      expect(find.text('Static - Digital bands and tearing'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'edge-origin drags preserve style; interior-origin drags change it',
    (tester) async {
      final styles = fakeStyles();
      await pumpViewfinder(tester, styles: styles);
      final width = tester.getSize(preview).width;
      for (final (x, dx) in [(23.0, 180.0), (width - 23, -180.0)]) {
        await tester.dragFrom(Offset(x, 150), Offset(dx, 0));
        await tester.pump();
        expect(styles.style, same(kStyles.first));
        expect(feedback, findsNothing);
      }
      await tester.dragFrom(const Offset(25, 150), const Offset(180, 0));
      await tester.pump();
      expect(styles.style, same(kStyles.last));
      await tester.dragFrom(Offset(width - 25, 150), const Offset(-180, 0));
      await tester.pump();
      expect(styles.style, same(kStyles.first));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('match uses the fresh opening snapshot for choice and reason', (
    tester,
  ) async {
    final styles = fakeStyles();
    final harness = await pumpViewfinder(tester, styles: styles);
    harness.ambient.setManual(true);
    harness.ambient.setManualValues(noise: 0.1, light: 0.1, motion: 0);
    harness.ambient.setManualValues(noise: 0.1, light: 0.9);
    // The current controls differ from the last published reading. Opening
    // must take a fresh tick, rather than reuse this stale dark-scene value.
    harness.ambient.value = const AmbientState(noise: 0.1, light: 0.1);
    await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
    await tester.pumpAndSettle();
    expect(harness.ambient.isRunning, isFalse);
    harness.ambient.setManualValues(noise: 0.9, light: 0.1, motion: 0.8);
    await tester.pump();
    await tester.tap(find.text('Match this place'));
    await tester.pumpAndSettle();
    expect(styles.style.id, 'prism');
    expect(find.text('Calm and bright: Prism'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'feedback lasts ${reduced ? 2500 : 1500} ms and honours reduced motion',
      (tester) async {
        final styles = fakeStyles();
        await pumpViewfinder(
          tester,
          styles: styles,
          mediaQuery: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: reduced,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('vf-style-next')));
        await tester.pump();
        expect(
          find.text('Tape - Worn VHS: wobble, lines and grain'),
          findsOneWidget,
        );
        final switcher = tester.widget<AnimatedSwitcher>(
          find
              .ancestor(of: feedback, matching: find.byType(AnimatedSwitcher))
              .first,
        );
        expect(
          switcher.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 160),
        );
        await tester.pump(Duration(milliseconds: reduced ? 2499 : 1499));
        expect(feedback, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        if (!reduced) {
          final expired = tester.widget<AnimatedSwitcher>(
            find
                .ancestor(of: feedback, matching: find.byType(AnimatedSwitcher))
                .first,
          );
          expect(expired.child, isA<SizedBox>());
        }
        await tester.pumpAndSettle();
        expect(feedback, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('swipes move next and previous, wrapping in both directions', (
    tester,
  ) async {
    final styles = fakeStyles();
    await pumpViewfinder(tester, styles: styles);
    final ticks = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') ticks.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await swipe(tester, 200);
    expect(styles.style.id, kStyles.last.id);
    await swipe(tester, -200);
    expect(styles.style.id, kStyles.first.id);
    for (var i = 1; i <= kStyles.length; i++) {
      await swipe(tester, -200);
      expect(styles.style.id, kStyles[i % kStyles.length].id);
      expect(styles.style.isPlaceholder, isFalse);
    }
    expect(ticks, everyElement('HapticFeedbackType.selectionClick'));
    expect(ticks, hasLength(kStyles.length + 2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'style description fades after 1500 ms and a new swipe restarts it',
    (tester) async {
      final styles = fakeStyles();
      await pumpViewfinder(tester, styles: styles);
      await swipe(tester, -200);
      expect(
        find.descendant(
          of: feedback,
          matching: find.textContaining('${kStyles[1].name} -'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(feedback, findsOneWidget);
      await swipe(tester, -200);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: feedback,
          matching: find.textContaining('${kStyles[2].name} -'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 200));
      expect(feedback, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'swipes reset taps and triple tap respects the debug build gate',
    (tester) async {
      final harness = await pumpViewfinder(tester, styles: fakeStyles());
      final center = Offset(tester.getCenter(preview).dx, 150);
      await tester.tapAt(center);
      await tester.tapAt(center);
      await swipe(tester, -200);
      await tester.tapAt(center);
      await tester.pump();
      expect(harness.settings.diagnosticsEnabled, isFalse);
      await tester.pump(const Duration(milliseconds: 450));
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(harness.settings.diagnosticsEnabled, AppConfig.debugBuild);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'short horizontal drags and vertical drags do not select a style',
    (tester) async {
      final styles = fakeStyles();
      await pumpViewfinder(tester, styles: styles);
      await swipe(tester, 30);
      await tester.dragFrom(
        Offset(tester.getCenter(preview).dx, 150),
        const Offset(0, 150),
      );
      expect(styles.style, same(kStyles.first));
      expect(feedback, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'diagonal drags require clear horizontal dominance from pointer down',
    (tester) async {
      final styles = fakeStyles();
      await pumpViewfinder(tester, styles: styles);
      final ticks = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            ticks.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      for (final direction in [-1.0, 1.0]) {
        // Horizontal recognition must not hide the later vertical movement.
        final gesture = await tester.startGesture(
          Offset(tester.getCenter(preview).dx, 150),
        );
        await gesture.moveBy(Offset(direction * 30, 0));
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(Offset(direction * 17.5, 60));
        }
        await gesture.up();
        await tester.pump();
        expect(styles.style, same(kStyles.first));
        expect(feedback, findsNothing);
      }
      await tester.dragFrom(
        Offset(tester.getCenter(preview).dx, 150),
        const Offset(-150, 120),
      );
      await tester.pump();
      expect(styles.style, same(kStyles.first));
      expect(ticks, isEmpty);
      await tester.dragFrom(
        Offset(tester.getCenter(preview).dx, 150),
        const Offset(-180, 60),
      );
      await tester.pump();
      expect(styles.style, same(kStyles[1]));
      expect(ticks, ['HapticFeedbackType.selectionClick']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sheet selection immediately removes feedback before its timer expires',
    (tester) async {
      final styles = fakeStyles();
      await pumpViewfinder(tester, styles: styles);
      await swipe(tester, -200);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: feedback,
          matching: find.textContaining('${kStyles[1].name} -'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kStyles.first.name));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(styles.style, same(kStyles.first));
      expect(feedback, findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(feedback, findsNothing);
      await tester.pump(const Duration(milliseconds: 800));
      expect(feedback, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sheet selection and sheet scrolling stay separate from preview swipes',
    (tester) async {
      final styles = fakeStyles();
      final harness = await pumpViewfinder(tester, styles: styles);
      await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
      await tester.pumpAndSettle();
      await tester.drag(find.text(kStyles[1].name), const Offset(0, -30));
      await tester.pumpAndSettle();
      expect(styles.style.id, kStyles.first.id);
      await tester.tap(find.text(kStyles[1].name));
      await tester.pumpAndSettle();
      expect(styles.style.id, kStyles[1].id);
      expect(feedback, findsNothing);
      expect(harness.settings.diagnosticsEnabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dice uses injected candidate index and never repeats current style',
    (tester) async {
      final random = FixedRandom(0);
      final styles = fakeStyles(random: random);
      await pumpViewfinder(tester, styles: styles);
      for (var i = 0; i < 12; i++) {
        final previous = styles.style;
        final candidates = kStyles
            .where((style) => style.id != previous.id)
            .toList();
        random.index = i % candidates.length;
        await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Random'));
        await tester.pumpAndSettle();
        expect(styles.style, same(candidates[random.index]));
        expect(styles.style.id, isNot(previous.id));
        expect(styles.style.isPlaceholder, isFalse);
      }
      expect(random.bounds, List.filled(12, kStyles.length - 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'dice does nothing for a single-style registry without drawing random',
    () async {
      final random = FixedRandom(0);
      final controller = StyleController(
        log: DebugLog(),
        styles: [kStyles.first],
        random: random,
        loader: (style) async => FakeBrowsingRenderer(style),
      );
      addTearDown(controller.dispose);
      await controller.selectRandom();
      expect(controller.style, same(kStyles.first));
      expect(random.bounds, isEmpty);
    },
  );

  for (final spanish in [false, true]) {
    testWidgets(
      'Smart pick selects the current ambience with ${spanish ? 'Spanish' : 'English'} reasons',
      (tester) async {
        final styles = fakeStyles();
        final harness = await pumpViewfinder(
          tester,
          styles: styles,
          locale: Locale(spanish ? 'es' : 'en'),
        );
        harness.ambient.setManual(true);
        final cases = [
          (
            const AmbientState(noise: 0.1, light: 0.9),
            'prism',
            spanish ? 'Calma y mucha luz: Prism' : 'Calm and bright: Prism',
          ),
          (
            const AmbientState(noise: 0.1, light: 0.1),
            'thermal',
            spanish ? 'Calma y poca luz: Thermal' : 'Calm and dark: Thermal',
          ),
          (
            const AmbientState(noise: 0.8, light: 0.9),
            'static',
            spanish ? 'Lugar ruidoso: Static' : 'Loud place: Static',
          ),
          (
            const AmbientState(motion: 0.8),
            // Unfinished Datamosh must not replace the working movement effect.
            'tape',
            spanish ? 'En movimiento: Tape' : 'In motion: Tape',
          ),
          (
            const AmbientState(noise: 0.4),
            'phosphor',
            spanish ? 'Ambiente variado: Phosphor' : 'Mixed ambience: Phosphor',
          ),
        ];
        for (final (state, id, reason) in cases) {
          harness.ambient.setManualValues(
            noise: state.noise,
            light: state.light,
            motion: state.motion,
          );
          await tester.tap(find.byKey(const ValueKey('vf-style-bar')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(spanish ? 'Según el lugar' : 'Match this place'),
          );
          await tester.pumpAndSettle();
          expect(styles.style.id, id);
          expect(find.text(reason), findsOneWidget);
          // The pick is on demand: changing ambience alone preserves the style.
          harness.ambient.setManualValues(noise: 1, motion: 1);
          await tester.pump(const Duration(milliseconds: 200));
          expect(styles.style.id, id);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'new buttons have labelled 48 dp targets clear of shutter and legend',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        final harness = await pumpViewfinder(
          tester,
          styles: fakeStyles(),
          diagnostics: true,
        );
        harness.ambient.setManual(true);
        await tester.pump();
        for (final label in ['Previous style', 'Next style']) {
          final button = find.byTooltip(label);
          final rect = tester.getRect(button);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(
            rect.overlaps(tester.getRect(find.byTooltip('Take a photo'))),
            isFalse,
          );
          expect(
            rect.overlaps(tester.getRect(find.byType(LevelLegend))),
            isFalse,
          );
          expect(
            tester
                .getSemantics(button)
                .getSemanticsData()
                .flagsCollection
                .isButton,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'swipe keeps drawing the previous renderer until the new one is ready',
    (tester) async {
      final pending = Completer<EffectRenderer>();
      final first = FakeBrowsingRenderer(kStyles.first);
      final second = FakeBrowsingRenderer(kStyles[1]);
      final styles = fakeStyles(
        loader: (style) async =>
            style.id == kStyles.first.id ? first : pending.future,
      );
      final harness = await pumpViewfinder(tester, styles: styles);
      final image = await tester.runAsync(buildTestImage);
      harness.fakeCamera.publishFrame(image!);
      await tester.pump();
      final paintsBefore = first.paints;
      await swipe(tester, -200);
      await tester.pump(const Duration(milliseconds: 32));
      expect(styles.isLoading, isTrue);
      expect(
        tester.widget<EffectView>(find.byType(EffectView)).renderer,
        same(first),
      );
      expect(first.paints, greaterThan(paintsBefore));
      expect(first.disposed, isFalse);
      pending.complete(second);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<EffectView>(find.byType(EffectView)).renderer,
        same(second),
      );
      expect(first.disposed, isTrue);
      expect(styles.isLoading, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
