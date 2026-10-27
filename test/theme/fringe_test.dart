import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/theme/app_theme.dart';
import 'package:sonoglitch/theme/fringe.dart';

Widget host(
  String text, {
  Object? value,
  bool reducedMotion = false,
  TextAlign? textAlign,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 150,
          child: FringeText(
            text,
            value: value,
            style: AppTheme.micro,
            textAlign: textAlign,
          ),
        ),
      ),
    ),
  ),
);

Finder get copies =>
    find.descendant(of: find.byType(FringeText), matching: find.byType(Text));

void main() {
  testWidgets('idle and unchanged values render one Text without a ticker', (
    tester,
  ) async {
    await tester.pumpWidget(host('THERMAL'));
    expect(copies, findsOneWidget);
    await tester.pumpWidget(host('THERMAL'));
    expect(copies, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('text change separates the copies then settles after 180 ms', (
    tester,
  ) async {
    await tester.pumpWidget(host('THERMAL'));
    await tester.pumpWidget(host('PRISM'));
    expect(copies, findsNWidgets(3));

    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(FringeText),
        matching: find.byType(Transform),
      ),
    );
    expect(transforms.map((t) => t.transform.storage[12]), [-3, 3]);
    final texts = tester.widgetList<Text>(copies).toList();
    final cyan = texts[0].style!.foreground!.color;
    expect(cyan.r, closeTo(AppTheme.signalCyan.r, 0.001));
    expect(cyan.a, closeTo(0.55 * 0.9, 0.005));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(copies, findsNWidgets(3));
    final moving = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(FringeText),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(moving.transform.storage[12], allOf(greaterThan(-3), lessThan(0)));
    await tester.pump(const Duration(milliseconds: 90));
    // One more frame rebuilds the settled widget as a single Text.
    await tester.pump(const Duration(milliseconds: 1));
    expect(copies, findsOneWidget);
    expect(find.text('PRISM'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a change key value animates even when text is unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(host('THERMAL', value: const ValueKey(1)));
    await tester.pumpWidget(host('THERMAL', value: const ValueKey(2)));
    expect(copies, findsNWidgets(3));
    await tester.pumpAndSettle();
    expect(copies, findsOneWidget);
  });

  testWidgets('reduced motion skips value and text transitions', (
    tester,
  ) async {
    await tester.pumpWidget(host('THERMAL', reducedMotion: true));
    await tester.pumpWidget(host('PRISM', value: 2, reducedMotion: true));
    expect(copies, findsOneWidget);
    expect(find.text('PRISM'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('centered copies preserve the idle text layout', (tester) async {
    await tester.pumpWidget(host('THERMAL', textAlign: TextAlign.center));
    final idle = tester.getRect(copies);
    await tester.pumpWidget(
      host('THERMAL', value: 2, textAlign: TextAlign.center),
    );
    for (final element in copies.evaluate()) {
      expect(
        tester.getSize(find.byElementPredicate((e) => e == element)),
        idle.size,
      );
    }
    expect(tester.getRect(copies.last), idle);
    await tester.pumpAndSettle();
    expect(tester.getRect(copies), idle);
  });

  testWidgets('enabling reduced motion stops an active fringe', (tester) async {
    await tester.pumpWidget(host('THERMAL'));
    await tester.pumpWidget(host('PRISM'));
    expect(copies, findsNWidgets(3));
    await tester.pumpWidget(host('PRISM', reducedMotion: true));
    expect(copies, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('rapid changes restart cleanly and dispose during animation', (
    tester,
  ) async {
    await tester.pumpWidget(host('THERMAL'));
    await tester.pumpWidget(host('PRISM'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(host('TAPE'));
    expect(find.text('TAPE'), findsNWidgets(3));
    expect(find.text('PRISM'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('decorative copies do not duplicate the semantic label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host('THERMAL'));
      await tester.pumpWidget(host('PRISM'));
      expect(find.bySemanticsLabel('PRISM'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.pumpAndSettle();
  });

  test('ring repaints only when its colour or stroke changes', () {
    const painter = FringeRingPainter();
    expect(painter.shouldRepaint(const FringeRingPainter()), isFalse);
    expect(
      painter.shouldRepaint(const FringeRingPainter(color: AppTheme.accent)),
      isTrue,
    );
    expect(
      painter.shouldRepaint(const FringeRingPainter(strokeWidth: 2)),
      isTrue,
    );
  });

  test(
    'ring paints a static fringe at shutter size and handles small bounds',
    () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = FringeRingPainter();
      painter.paint(canvas, const Size.square(AppTheme.shutterSize));
      painter.paint(canvas, Size.zero);
      recorder.endRecording().dispose();
    },
  );
}
