import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/features/viewfinder/viewfinder_screen.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';

import '../ambient/spectrum_service_test.dart' show FakeSpectrumSource;

import '../support/harness.dart';

void main() {
  testWidgets('spectrum follows route visibility and app lifecycle', (
    tester,
  ) async {
    final source = FakeSpectrumSource();
    addTearDown(source.controller.close);
    final spectrum = SpectrumService(source: source);
    await pumpViewfinder(tester, spectrum: spectrum);
    await tester.pump();
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(spectrum.isListening, isTrue);
    final context = tester.element(find.byType(ViewfinderScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(spectrum.isListening, isFalse);
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(spectrum.isListening, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(spectrum.isListening, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(spectrum.isListening, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(spectrum.isListening, isFalse);
  });
  testWidgets('the sensors run while the viewfinder is visible', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);

    expect(harness.noise.isListening, isTrue);
    expect(harness.motion.isListening, isTrue);
    expect(harness.light.isListening, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sensors stop when another route covers the viewfinder', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);
    final context = tester.element(find.byType(ViewfinderScreen));

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      harness.noise.isListening,
      isFalse,
      reason: 'The microphone must be closed',
    );
    expect(harness.motion.isListening, isFalse);
    expect(harness.light.isListening, isFalse);

    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.noise.isListening, isTrue);
    expect(harness.motion.isListening, isTrue);
    expect(harness.light.isListening, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sensors stop when the app goes to the background', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(harness.noise.isListening, isFalse);
    expect(harness.motion.isListening, isFalse);
    expect(harness.light.isListening, isFalse);
    expect(harness.camera.isPaused, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.noise.isListening, isTrue);
    expect(harness.motion.isListening, isTrue);
    expect(harness.light.isListening, isTrue);
    expect(harness.camera.isPaused, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starting and stopping the sensors twice is harmless', (
    tester,
  ) async {
    final harness = await pumpViewfinder(tester);

    // The screen starts the sensors and the route status asks for them again.
    expect(harness.noise.isListening, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(harness.noise.isListening, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.noise.isListening, isTrue);
    expect(harness.noise.isListening, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(harness.noise.isListening, isFalse);
  });
}
