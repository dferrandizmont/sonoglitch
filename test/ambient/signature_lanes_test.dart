import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/signature/signature_controller.dart';
import 'package:sonoglitch/ambient/signature/signature_signals.dart';
import 'package:sonoglitch/ambient/signature/scene_signature.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_report.dart';

import '../support/fakes.dart';
import 'noise_service_test.dart' show FakeClock;

/// The lanes of a neutral shot.
void expectNeutralLanes(AmbientState state) {
  final signature = state.signature;
  expect(signature.warmth, 0);
  expect(signature.hue, 0);
  expect(signature.chromaAllowance, 1);
  expect(signature.tilt, 0);
  expect(signature.axisX, 1);
  expect(signature.axisY, 0);
  expect(signature.pulse, 0);
  expect(signature.reserved, 0);
}

/// Builds the contextual signals with fake sensors.
SignatureSignals buildSignals(
  FakeClock clock, {
  DateTime Function()? localNow,
}) => SignatureSignals(
  gravity: () => null,
  magnetometer: () => const Stream<SensorVector>.empty(),
  localNow: localNow,
  clock: clock.call,
);

/// Builds the controller with fake sensors and a deterministic fingerprint.
AmbientController buildController(FakeClock clock, SignatureSignals signals) =>
    AmbientController(
      spectrum: SpectrumService(
        source: const NoopSpectrumSource(),
        clock: clock.call,
      ),
      noise: NoiseService(
        decibelStream: const Stream<double>.empty(),
        clock: clock.call,
      ),
      motion: MotionService(
        samples: const Stream<AccelSample>.empty(),
        gyroSamples: const Stream<AccelSample>.empty(),
        gravitySamples: const Stream<AccelSample>.empty(),
        clock: clock.call,
      ),
      light: LightService(
        ambientLight: FakeAmbientLightSource(),
        clock: clock.call,
      ),
      signature: SignatureController(random: Random(7), clock: clock.call),
      signals: signals,
      clock: clock.call,
    );

void main() {
  test('the lanes are neutral before any data', () {
    final clock = FakeClock();
    final controller = buildController(clock, buildSignals(clock));
    controller.tick();
    expectNeutralLanes(controller.value);
    controller.dispose();
  });

  test('the measured lanes are published with the state', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();
    // Noon is the warmest neutral hour of the curve.
    expect(controller.value.signature.warmth, closeTo(0.15, 1e-12));
    expect(controller.value.signature.hue, inInclusiveRange(-1, 1));
    controller.dispose();
  });

  test('the manual mode publishes neutral lanes', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();
    expect(controller.value.signature.warmth, closeTo(0.15, 1e-12));

    controller.setManual(true);
    controller.tick();
    expectNeutralLanes(controller.value);
    final snapshot = controller.snapshot();
    expectNeutralLanes(snapshot);
    expectNeutralLanes(
      AmbientState(signature: snapshot.captureSignature!.signature),
    );
    controller.dispose();
  });

  test('the snapshot freezes the lanes at the shutter', () {
    final clock = FakeClock();
    var wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();

    final snapshot = controller.snapshot();
    expect(snapshot.signature.warmth, closeTo(0.15, 1e-12));
    expect(snapshot.captureSignature!.signature.warmth, closeTo(0.15, 1e-12));

    // The moment moves on: the shot keeps the lanes of its own instant.
    wall = DateTime(2024, 6, 21, 20);
    clock.advance(const Duration(seconds: 2));
    controller.tick();
    expect(controller.value.signature.warmth, isNot(closeTo(0.15, 1e-9)));
    expect(snapshot.signature.warmth, closeTo(0.15, 1e-12));
    expect(snapshot.captureSignature!.signature.warmth, closeTo(0.15, 1e-12));
    controller.dispose();
  });

  test('two consecutive captures keep the lanes of their own shutter', () {
    final clock = FakeClock();
    var wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();

    final first = controller.snapshot();
    expect(first.signature.warmth, closeTo(0.15, 1e-12));
    expect(first.captureSignature!.signature.warmth, closeTo(0.15, 1e-12));

    // The moment moves on: the second shot carries the lanes of its own
    // instant, not the ones of the first shot.
    wall = DateTime(2024, 6, 21, 20);
    clock.advance(const Duration(seconds: 2));
    controller.tick();
    final second = controller.snapshot();
    expect(second.signature.warmth, isNot(closeTo(0.15, 1e-9)));
    expect(
      second.captureSignature!.signature.warmth,
      isNot(closeTo(0.15, 1e-9)),
    );
    expect(second.signature.warmth, second.captureSignature!.signature.warmth);

    // The first shot is not touched by the second one.
    expect(first.signature.warmth, closeTo(0.15, 1e-12));
    expect(first.captureSignature!.signature.warmth, closeTo(0.15, 1e-12));
    // Every shot has its own identity.
    expect(second.identity!.photoId, isNot(first.identity!.photoId));
    expect(first.captureSignature, isNot(second.captureSignature));
    controller.dispose();
  });

  test('the state published after the shot is the next pending one', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();

    final pending = controller.value.signature;
    final snapshot = controller.snapshot();
    final next = controller.value.signature;
    // The fingerprint of the next photo is a new one.
    expect(next.x, isNot(pending.x));
    expect(next.y, isNot(pending.y));
    // The capture keeps the final fingerprint of its own, not the preview one.
    expect(snapshot.signature.x, isNot(pending.x));
    // The lanes of the published state are the current ones.
    expect(next.warmth, closeTo(0.15, 1e-12));
    controller.dispose();
  });

  test('stopping the controller drops the lanes for the next session', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();
    expect(controller.value.signature.warmth, closeTo(0.15, 1e-12));

    controller.stop();
    // The transient lanes are dropped with the session.
    expectNeutralLanes(AmbientState(signature: controller.signals.moodLanes()));

    // The next session begins with the neutral lanes and picks the civil
    // palette up again with its first tick.
    controller.start();
    final lanes = controller.signals.moodLanes();
    expect(lanes.tilt, 0);
    expect(lanes.pulse, 0);
    expect(lanes.chromaAllowance, 1);
    expect(lanes.axisX, 1);
    expect(lanes.warmth, closeTo(0.15, 1e-12));
    controller.tick();
    expect(controller.value.signature.warmth, closeTo(0.15, 1e-12));
    controller.dispose();
  });

  test('the photo turns keep the lanes', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();
    final snapshot = controller.snapshot();

    final photo = snapshot.forPhotoTurns(1);
    expect(photo.signature.warmth, snapshot.signature.warmth);
    expect(photo.signature.hue, snapshot.signature.hue);
    expect(photo.signature.chromaAllowance, snapshot.signature.chromaAllowance);
    expect(photo.signature.tilt, snapshot.signature.tilt);
    expect(photo.signature.pulse, snapshot.signature.pulse);
    expect(
      photo.captureSignature!.signature.pulse,
      snapshot.captureSignature!.signature.pulse,
    );
    expect(photo.captureSignature!.identity.photoId, isNotEmpty);
    controller.dispose();
  });

  test('the contextual lanes never reach the JSON or the diagnostics', () {
    final clock = FakeClock();
    final wall = DateTime(2024, 6, 21, 12);
    final controller = buildController(
      clock,
      buildSignals(clock, localNow: () => wall),
    );
    controller.start();
    controller.tick();
    final state = controller.value;
    // The lanes are there, they are just never written down.
    expect(state.signature.warmth, closeTo(0.15, 1e-12));

    const forbidden = [
      'warmth',
      'hue',
      'chromaallowance',
      'tilt',
      'axisx',
      'axisy',
      'pulse',
      'reserved',
      'heading',
      'rhythm',
      'calendar',
      'colorfulness',
      'moon',
      'mood',
      'signature',
    ];
    final json = state.toJson();
    final encoded = jsonEncode(json).toLowerCase();
    for (final key in forbidden) {
      expect(
        json.keys.map((name) => name.toLowerCase()),
        isNot(contains(key)),
        reason: 'the key $key must not be serialized',
      );
      expect(encoded, isNot(contains(key)));
    }

    final report = DiagnosticReport.build(
      ambient: state,
      metrics: const CameraMetricsData(),
      styleId: 'static',
      timings: CaptureTimings(takeMs: 1, ambient: state),
      device: const DeviceSummary(
        model: 'test',
        systemVersion: 'test',
        platform: 'test',
      ),
      appVersion: 'test',
      buildMode: 'test',
      logs: const [],
    );
    final reported = jsonEncode(report).toLowerCase();
    for (final key in forbidden) {
      expect(reported, isNot(contains(key)));
    }
    controller.dispose();
  });

  test('the lanes follow the scene of the camera', () {
    final clock = FakeClock();
    final signals = buildSignals(clock);
    final controller = buildController(clock, signals);
    controller.start();
    signals.addScene(const SceneColorReading(allowance: .65));
    clock.advance(const Duration(milliseconds: 100));
    signals.addScene(const SceneColorReading(allowance: .65));
    controller.tick();
    expect(controller.value.signature.chromaAllowance, lessThan(1));

    // Another camera forgets the colours of the previous one.
    signals.clearScene();
    controller.tick();
    expect(controller.value.signature.chromaAllowance, 1);
    controller.dispose();
  });
}
