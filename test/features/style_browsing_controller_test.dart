import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/style_controller.dart';

import '../support/browsing_fakes.dart';

void main() {
  testWidgets(
    'an older load cannot clear loading or replace the active preview',
    (tester) async {
      final pending = <Completer<EffectRenderer>>[];
      final controller = StyleController(
        log: DebugLog(),
        loader: (_) {
          final completer = Completer<EffectRenderer>();
          pending.add(completer);
          return completer.future;
        },
      );
      addTearDown(controller.dispose);
      final initialRenderer = FakeBrowsingRenderer(kStyles.first);
      final initial = controller.load();
      pending[0].complete(initialRenderer);
      await initial;
      final older = controller.select(kStyles[1]);
      final newest = controller.select(kStyles[2]);
      final obsoleteRenderer = FakeBrowsingRenderer(kStyles[1]);
      pending[1].complete(obsoleteRenderer);
      await older;
      expect(controller.isLoading, isTrue);
      expect(controller.renderer, same(initialRenderer));
      expect(initialRenderer.disposed, isFalse);
      expect(obsoleteRenderer.disposed, isTrue);

      final newestRenderer = FakeBrowsingRenderer(kStyles[2]);
      pending[2].complete(newestRenderer);
      await newest;
      expect(controller.isLoading, isFalse);
      expect(controller.renderer, same(newestRenderer));
      await tester.pump();
      expect(initialRenderer.disposed, isTrue);
    },
  );

  testWidgets('returning to a pending style ignores its original stale load', (
    tester,
  ) async {
    final pending = <Completer<EffectRenderer>>[];
    final controller = StyleController(
      log: DebugLog(),
      loader: (_) {
        final completer = Completer<EffectRenderer>();
        pending.add(completer);
        return completer.future;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.load();
    final second = controller.select(kStyles[1]);
    final third = controller.select(kStyles.first);
    final winner = FakeBrowsingRenderer(kStyles.first);
    pending[2].complete(winner);
    await third;
    final staleFirst = FakeBrowsingRenderer(kStyles.first);
    pending[0].complete(staleFirst);
    await first;
    final staleSecond = FakeBrowsingRenderer(kStyles[1]);
    pending[1].complete(staleSecond);
    await second;
    expect(controller.renderer, same(winner));
    expect(staleFirst.disposed, isTrue);
    expect(staleSecond.disposed, isTrue);
    expect(winner.disposed, isFalse);
    expect(controller.isLoading, isFalse);
  });

  test(
    'a renderer completing after disposal is released without notification',
    () async {
      final pending = Completer<EffectRenderer>();
      final controller = StyleController(
        log: DebugLog(),
        loader: (_) => pending.future,
      );
      final loading = controller.load();
      controller.dispose();
      final renderer = FakeBrowsingRenderer(kStyles.first);
      pending.complete(renderer);
      await loading;
      expect(renderer.disposed, isTrue);
      expect(controller.renderer, isNull);
    },
  );

  test('a failed selection leaves the previous renderer available', () async {
    final renderer = FakeBrowsingRenderer(kStyles.first);
    final controller = StyleController(
      log: DebugLog(),
      loader: (style) async {
        if (style.id == kStyles.first.id) return renderer;
        throw StateError('Test loading failure');
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.select(kStyles[1]);
    expect(controller.renderer, same(renderer));
    expect(renderer.disposed, isFalse);
    expect(controller.isLoading, isFalse);
  });
}
