import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/features/viewfinder/level_legend.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

import '../support/harness.dart';

void main() {
  test('segment counts clamp and quantize each control independently', () {
    for (var count = 0; count <= 12; count++) {
      expect(SegmentedMeterPainter.litCount(count / 12), count);
    }
    final painter = SegmentedMeterPainter(noise: -1, light: 0.5, motion: 2);
    expect(painter.noiseCount, 0);
    expect(painter.lightCount, 6);
    expect(painter.motionCount, 12);
  });

  test('meter repaint depends only on the three lit counts', () {
    final original = SegmentedMeterPainter(noise: 0.5, light: 0.5, motion: 0.5);
    expect(
      SegmentedMeterPainter(
        noise: 0.51,
        light: 0.49,
        motion: 0.5,
      ).shouldRepaint(original),
      isFalse,
    );
    for (final levels in [
      [0.6, 0.5, 0.5],
      [0.5, 0.6, 0.5],
      [0.5, 0.5, 0.6],
    ]) {
      expect(
        SegmentedMeterPainter(
          noise: levels[0],
          light: levels[1],
          motion: levels[2],
        ).shouldRepaint(original),
        isTrue,
      );
    }
  });

  test('zero paints 36 empty square segments with no fallback dot', () {
    expect(AppTheme.meterTrack, const Color(0x29FFFFFF));
    final painter = SegmentedMeterPainter(noise: 0, light: 0, motion: 0);
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(59, 54));
    final rects = canvas.invocations
        .where((call) => call.invocation.memberName == #drawRect)
        .toList();
    expect(rects, hasLength(36));
    for (final call in rects) {
      final rect = call.invocation.positionalArguments[0] as Rect;
      final paint = call.invocation.positionalArguments[1] as Paint;
      expect(rect.size, const Size(4, 4));
      expect(paint.color.toARGB32(), 0x29FFFFFF);
    }
  });

  test('lit scales paint the noise, light and motion role colours', () {
    final painter = SegmentedMeterPainter(noise: 0.25, light: 0.5, motion: 1);
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(59, 54));
    final colors = <int, int>{};
    for (final call in canvas.invocations) {
      if (call.invocation.memberName != #drawRect) continue;
      final color = (call.invocation.positionalArguments[1] as Paint).color;
      colors.update(color.toARGB32(), (count) => count + 1, ifAbsent: () => 1);
    }
    expect(colors[AppTheme.accent.toARGB32()], 3);
    expect(colors[AppTheme.warm.toARGB32()], 6);
    expect(colors[AppTheme.signalCyan.toARGB32()], 12);
    expect(colors[0x29FFFFFF], 15);
  });

  testWidgets('one painter fits a 48 to 71 dp target at 320 and 1.3x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ambient = ValueNotifier(AmbientState.calm);
    addTearDown(ambient.dispose);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LevelLegend(
              ambient: ambient,
              onExplain: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    final legend = find.byType(LevelLegend);
    final size = tester.getSize(legend);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.height, lessThan(72));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(
      find.descendant(
        of: legend,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is SegmentedMeterPainter,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.open_with)).color,
      AppTheme.signalCyan,
    );
    await tester.tap(legend);
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the legend names the three levels with an icon and a tooltip', (
    tester,
  ) async {
    await pumpViewfinder(tester);

    expect(find.byType(LevelLegend), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_with), findsOneWidget);

    // Every icon says what its bar measures.
    expect(find.byTooltip('Noise: how loud the place is'), findsOneWidget);
    expect(find.byTooltip('Light: bright or in shadow'), findsOneWidget);
    expect(
      find.byTooltip('Movement: how much the phone shakes'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the legend shows the three levels as horizontal bars', (
    tester,
  ) async {
    await pumpViewfinder(tester);

    // The bars are horizontal and the card says that it opens the help.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    final card = tester.getRect(find.byType(LevelLegend));
    expect(card.height, greaterThanOrEqualTo(48));
    expect(card.width, lessThan(card.height * 3));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the legend reads the name of every level', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpViewfinder(tester);

      expect(
        find.bySemanticsLabel('Live sound, light and movement. Tap for help'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Noise \d+%$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Light \d+%$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Movement \d+%$')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the legend reads the level of every bar', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final harness = await pumpViewfinder(tester);

      // Start in calm: every level is 0%.
      expect(find.bySemanticsLabel('Noise 0%'), findsOneWidget);
      expect(find.bySemanticsLabel('Light 0%'), findsOneWidget);
      expect(find.bySemanticsLabel('Movement 0%'), findsOneWidget);

      // Add a loud reading: the noise level goes up.
      harness.noise.addReading(85);
      harness.ambient.tick();
      await tester.pump();

      final noiseLabel = find.bySemanticsLabel(RegExp(r'^Noise \d+%$'));
      expect(noiseLabel, findsOneWidget);
      final semantic = tester.getSemantics(noiseLabel);
      expect(semantic.label, isNot('Noise 0%'));
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the legend opens the sheet that explains the levels', (
    tester,
  ) async {
    await pumpViewfinder(tester);

    expect(
      find.descendant(
        of: find.byType(HowItWorksSheet),
        matching: find.text('How it works'),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(LevelLegend));
    await tester.pumpAndSettle();

    final route = ModalRoute.of(tester.element(find.byType(HowItWorksSheet)))!;
    expect(route.transitionDuration, const Duration(milliseconds: 220));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 220));

    expect(
      find.descendant(
        of: find.byType(HowItWorksSheet),
        matching: find.text('How it works'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Noise is how loud the place is. The louder it is, the more the '
        'photo breaks.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Light is whether the scene is bright or in shadow. The darker it '
        'is, the stronger the effect.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Movement is how much the phone is being shaken. The more it moves, '
        'the more the photo breaks.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sheet also explains the swipe and the auto shot', (
    tester,
  ) async {
    await pumpViewfinder(tester);

    await tester.tap(find.byType(LevelLegend));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Swipe left or right on the picture, or use the arrows, to change '
        'style.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Auto shot waits and takes the photo by itself on a loud sound or a '
        'sudden move.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sheet of the legend can be closed', (tester) async {
    await pumpViewfinder(tester);

    await tester.tap(find.byType(LevelLegend));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HowItWorksSheet),
        matching: find.text('How it works'),
      ),
      findsOneWidget,
    );

    // The sheet is longer than the screen of the test, so the button is
    // brought into view before it is pressed.
    await tester.ensureVisible(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(HowItWorksSheet),
        matching: find.text('How it works'),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('help scrolls without overflow at 320x568 and 1.3x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpViewfinder(
      tester,
      mediaQuery: const MediaQueryData(
        size: Size(320, 568),
        textScaler: TextScaler.linear(1.3),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.byType(LevelLegend));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(HowItWorksSheet)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    final close = find.descendant(
      of: find.byType(HowItWorksSheet),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(HowItWorksSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the legend sits on a translucent dark surface', (tester) async {
    await pumpViewfinder(tester);

    // The legend's outer container carries a scrim so the icons keep their
    // contrast over a bright scene instead of sitting on the raw pixels of
    // the preview.
    final surface = tester.widget<Container>(
      find.descendant(
        of: find.byType(LevelLegend),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == AppTheme.scrim,
        ),
      ),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, isNotNull);
    final r = (decoration.color!.r * 255).round();
    final g = (decoration.color!.g * 255).round();
    final b = (decoration.color!.b * 255).round();
    expect(r, lessThan(64));
    expect(g, lessThan(64));
    expect(b, lessThan(64));
    expect(
      decoration.borderRadius,
      isNotNull,
      reason: 'The scrim has rounded corners, like the other overlays',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
