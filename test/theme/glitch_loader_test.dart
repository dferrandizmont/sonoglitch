import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';
import 'package:sonoglitch/theme/glitch_loader.dart';

Widget _app({bool reduced = false}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: const Scaffold(body: Center(child: GlitchLoader())),
  ),
);

/// Records the rectangles that a painter draws, with their colours.
class _RecordingCanvas implements Canvas {
  final rects = <(Rect, Color)>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not expected');
}

List<(Rect, Color)> _draw(double? value) {
  final canvas = _RecordingCanvas();
  final painter = GlitchLoaderPainter(
    progress: value == null ? null : AlwaysStoppedAnimation(value),
  );
  painter.paint(canvas, GlitchLoaderPainter.sizeFor(2));
  return canvas.rects;
}

void main() {
  testWidgets('builds, sweeps and exposes a live "Processing" label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    expect(find.byType(GlitchLoader), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    final node = tester.getSemantics(find.byType(GlitchLoader));
    expect(node.label, 'Processing');
    expect(node.flagsCollection.isLiveRegion, isTrue);
    // The sweep keeps scheduling frames.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
    semantics.dispose();
  });

  testWidgets('keeps its size while it animates', (tester) async {
    await tester.pumpWidget(_app());
    final before = tester.getSize(
      find.byKey(const ValueKey('glitch-loader-paint')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.getSize(
      find.byKey(const ValueKey('glitch-loader-paint')),
    );
    expect(after, before);
    expect(before, GlitchLoaderPainter.sizeFor(2));
  });

  testWidgets('reduced motion draws a still frame without a ticker', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduced: true));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('the same value draws the same frame', () {
    for (final v in [0.0, 0.13, 0.5, 0.99, 1.0]) {
      expect(_draw(v), _draw(v));
    }
  });

  test('the still frame lights the first three cells without a fringe', () {
    final rects = _draw(null);
    // 8 track cells plus 3 lit ones.
    expect(rects.length, 11);
    final lit = rects.skip(8).map((r) => r.$2.toARGB32()).toList();
    expect(lit, GlitchLoaderPainter.colors.map((c) => c.toARGB32()).toList());
    expect(
      rects
          .where((r) => r.$2.toARGB32() == AppTheme.meterTrack.toARGB32())
          .length,
      8,
    );
  });

  test('the window moves left to right through the row', () {
    final starts = [
      for (var i = 0; i < GlitchLoaderPainter.steps; i++)
        GlitchLoaderPainter.windowStart((i + .5) / GlitchLoaderPainter.steps),
    ];
    expect(starts.first, -2);
    expect(starts.last, 7);
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], starts[i - 1] + 1);
    }
  });

  test('the fringe flickers only at fixed ticks and never by chance', () {
    final offsets = [
      for (var t = 0; t < GlitchLoaderPainter.ticks; t++)
        GlitchLoaderPainter.fringeOffset((t + .5) / GlitchLoaderPainter.ticks),
    ];
    expect(offsets.any((o) => o != 0), isTrue);
    expect(
      offsets.where((o) => o == 0).length,
      greaterThan(offsets.length ~/ 2),
    );
    for (final o in offsets) {
      expect(o.abs() == 0 || o.abs() == GlitchLoaderPainter.fringe, isTrue);
    }
    // A flicker frame draws the lit cells three times.
    final tick = offsets.indexWhere((o) => o != 0);
    final value = (tick + .5) / GlitchLoaderPainter.ticks;
    final lit = GlitchLoaderPainter.windowStart(value);
    final visible = [
      for (var k = 0; k < GlitchLoaderPainter.window; k++)
        if (lit + k >= 0 && lit + k < GlitchLoaderPainter.cells) k,
    ].length;
    expect(_draw(value).length, GlitchLoaderPainter.cells + visible * 3);
  });

  test('the painter only calls drawRect', () {
    // No saveLayer or blur: the recording canvas throws on anything else.
    expect(() => _draw(.4), returnsNormally);
  });
}
