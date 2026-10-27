import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';

import '../support/fakes.dart';

void main() {
  test('state JSON, rotation and capture copies preserve the new signals', () {
    const defaults = AmbientState();
    expect(
      (defaults.bass, defaults.mid, defaults.treble, defaults.seed),
      (0, 0, 0, 0),
    );
    const state = AmbientState(bass: 0.1, mid: 0.2, treble: 0.3, seed: 0.4);
    expect(state.toJson(), containsPair('bass', 0.1));
    expect(state.toJson(), containsPair('mid', 0.2));
    expect(state.toJson(), containsPair('treble', 0.3));
    expect(state.toJson(), isNot(contains('seed')));
    final rotated = state.forPhotoTurns(1, mirrorX: true);
    expect(
      (rotated.bass, rotated.mid, rotated.treble, rotated.seed),
      (0.1, 0.2, 0.3, 0.4),
    );
    expect(state.withSeed(0.7).toJson(), state.toJson());
    expect(state.withSeed(0.7).seed, 0.7);
  });

  test('the contextual lanes survive copies, mirror and stay out of JSON', () {
    const signature = SignatureState(
      x: 0.1,
      y: 0.2,
      z: 0.3,
      w: 0.4,
      warmth: 0.5,
      hue: -0.5,
      chromaAllowance: 0.8,
      tilt: 0.25,
      axisX: 0,
      axisY: 1,
      pulse: 0.75,
      reserved: 0.1,
    );
    const state = AmbientState(signature: signature);
    // Copies keep every lane of the state.
    expect(state.withSeed(0.7).signature, same(state.signature));
    // A plain quarter turn leaves the small rotation unchanged.
    for (final turns in [1, 2, 3]) {
      final rotated = state.forPhotoTurns(turns);
      expect(rotated.signature.axisX, 0);
      expect(rotated.signature.axisY, 1);
      expect(rotated.signature.warmth, 0.5);
      expect(rotated.signature.pulse, 0.75);
    }
    // Mirroring flips the sign of the axis and nothing else.
    final mirrored = state.forPhotoTurns(0, mirrorX: true);
    expect(mirrored.signature.axisX, 0);
    expect(mirrored.signature.axisY, -1);
    expect(mirrored.signature.x, 0.1);
    expect(mirrored.signature.w, 0.4);
    expect(mirrored.signature.warmth, 0.5);
    expect(mirrored.signature.chromaAllowance, 0.8);
    expect(mirrored.signature.pulse, 0.75);
    expect(mirrored.signature.reserved, 0.1);
    // The contextual lanes never reach the diagnostics.
    final json = state.toJson();
    for (final excluded in [
      'warmth',
      'hue',
      'chromaAllowance',
      'tilt',
      'axisX',
      'axisY',
      'pulse',
      'reserved',
      'signature',
    ]) {
      expect(json, isNot(contains(excluded)));
    }
  });

  test('pending preview is stable and consumed once by each capture', () {
    var micros = 0;
    final controller = AmbientController(
      noise: NoiseService(decibelStream: const Stream.empty()),
      motion: MotionService(
        samples: const Stream.empty(),
        gyroSamples: const Stream.empty(),
        gravitySamples: const Stream.empty(),
      ),
      light: LightService(ambientLight: FakeAmbientLightSource()),
      spectrum: SpectrumService(source: const NoopSpectrumSource()),
      clock: () => micros,
      utcNow: () => DateTime.utc(2026),
      random: Random(7),
    );
    addTearDown(controller.dispose);
    controller.tick();
    final pendingSeed = controller.value.seed;
    final previewMicro = controller.value.signature;
    micros += 100000000;
    controller.tick();
    expect(controller.value.seed, pendingSeed);
    controller.setStyle('tape');
    expect(controller.value.seed, pendingSeed);
    final first = controller.snapshot();
    expect(first.seed, pendingSeed);
    expect(first.identity, isNotNull);
    expect(first.signature.x, isNot(previewMicro.x));
    final nextSeed = controller.value.seed;
    expect(nextSeed, isNot(pendingSeed));
    final second = controller.snapshot();
    expect(second.seed, nextSeed);
    expect(second.identity!.photoId, isNot(first.identity!.photoId));
    expect(
      first.forPhotoTurns(1).captureSignature,
      same(first.captureSignature),
    );
    expect(first.withSeed(0.2).captureSignature, same(first.captureSignature));
    controller.stop();
    controller.tick();
    expect(controller.value.seed, isNot(second.seed));
    expect(first.seed, pendingSeed);
    controller.setManual(true);
    final manualSeed = controller.value.seed;
    final manual = controller.snapshot();
    expect(manual.seed, manualSeed);
    expect(manual.identity, isNotNull);
    expect(controller.value.seed, isNot(manualSeed));
  });

  test(
    'controller freezes latest published bands rather than their history mean',
    () {
      var micros = 0;
      final spectrum = SpectrumService(
        source: const NoopSpectrumSource(),
        clock: () => micros,
        warmup: Duration.zero,
      );
      final controller = AmbientController(
        noise: NoiseService(decibelStream: const Stream.empty()),
        motion: MotionService(
          samples: const Stream.empty(),
          gyroSamples: const Stream.empty(),
          gravitySamples: const Stream.empty(),
        ),
        light: LightService(ambientLight: FakeAmbientLightSource()),
        spectrum: spectrum,
        clock: () => micros,
        random: Random(7),
      );
      addTearDown(controller.dispose);
      spectrum.addReading((bass: -80, mid: -80, treble: -80));
      controller.tick();
      micros += 50000;
      spectrum.addReading((bass: -5, mid: -80, treble: -80));
      controller.tick();
      expect(controller.value.bass, spectrum.bass);
      expect(controller.snapshot().bass, closeTo(spectrum.bass, 1e-12));
    },
  );
}
