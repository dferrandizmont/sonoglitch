import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/noise_service.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/signature/capture_fingerprint.dart';
import 'package:sonoglitch/ambient/signature/capture_identity.dart';
import 'package:sonoglitch/ambient/signature/signature_controller.dart';
import 'package:sonoglitch/ambient/signature/signature_source.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/features/result/capture_result.dart';

/// Known nonce 00..1f; production uses Random.secure, never this generator.
class ByteSequenceRandom implements Random {
  int _next = 0;
  @override
  int nextInt(int max) => _next++ % max;
  @override
  double nextDouble() => throw UnimplementedError();
  @override
  bool nextBool() => throw UnimplementedError();
}

CaptureSignature fixed({
  List<SignatureReading> readings = const [
    SignatureReading(lowByte: 171, ageMicros: 20),
    SignatureReading(),
  ],
  String style = 'tape',
  int recipe = 1,
  int counter = 7,
  int utc = 1760000000000000,
  int monotonic = 9000,
}) => PendingCaptureSignature(random: ByteSequenceRandom()).consume(
  counter: counter,
  utcMicros: utc,
  monotonicMicros: monotonic,
  styleId: style,
  recipeVersion: recipe,
  readings: readings,
);

void main() {
  test(
    'existing sensor events supply only ephemeral low bits and clear on stop',
    () {
      var now = 0;
      final motion = MotionService(
        samples: const Stream.empty(),
        gyroSamples: const Stream.empty(),
        gravitySamples: const Stream.empty(),
        clock: () => now,
      );
      final noise = NoiseService(
        decibelStream: const Stream.empty(),
        clock: () => now,
      );
      final spectrum = SpectrumService(
        source: const NoopSpectrumSource(),
        clock: () => now,
      );
      addTearDown(motion.stop);
      addTearDown(noise.stop);
      addTearDown(spectrum.stop);
      expect(motion.signatureReadings.every((r) => !r.present), isTrue);
      expect(noise.signatureReadings.single.present, isFalse);
      expect(spectrum.signatureReadings.every((r) => !r.present), isTrue);
      motion.addSample(const AccelSample(1.0000001192092896, 0, 0));
      motion.addGyroSample(const AccelSample(0, 1.0000001192092896, 0));
      noise.addReading(60);
      spectrum.addReading((bass: -40, mid: -50, treble: -60));
      expect(motion.signatureReadings.map((r) => r.lowByte), [
        1,
        0,
        0,
        0,
        1,
        0,
      ]);
      expect(noise.signatureReadings.single.fresh, isTrue);
      // Energy readings are available as contextual bits even during warmup;
      // they are not promoted to visible normalized band controls prematurely.
      expect(spectrum.available, isFalse);
      expect(spectrum.signatureReadings.every((r) => r.fresh), isTrue);
      now = 1500001;
      expect(motion.signatureReadings.every((r) => !r.fresh), isTrue);
      expect(noise.signatureReadings.single.fresh, isFalse);
      expect(spectrum.signatureReadings.every((r) => !r.fresh), isTrue);
      noise.enabled = spectrum.enabled = false;
      expect(noise.signatureReadings.single.present, isFalse);
      expect(spectrum.signatureReadings.every((r) => !r.present), isTrue);
      motion.stop();
      noise.stop();
      spectrum.stop();
      noise.enabled = spectrum.enabled = true;
      expect(motion.signatureReadings.every((r) => !r.present), isTrue);
      expect(noise.signatureReadings.single.present, isFalse);
      expect(spectrum.signatureReadings.every((r) => !r.present), isTrue);
    },
  );

  test('v1 matches independent HMAC-SHA256 / binary encoding vector', () {
    // Reference computed independently with Python struct/hmac/hashlib.
    final capture = fixed();
    expect(capture.seed, 0.5399879813194275);
    expect(
      [
        capture.signature.x,
        capture.signature.y,
        capture.signature.z,
        capture.signature.w,
      ],
      [
        0.4859033226966858,
        0.6836431622505188,
        0.3586210012435913,
        0.013707637786865234,
      ],
    );
    expect(capture.identity.photoId, '1YBBQGPC');
    expect(fixed().identity.photoId, capture.identity.photoId);
  });

  test('each contextual field is domain-bound without changing macro seed', () {
    final baseline = fixed();
    for (final other in [
      fixed(style: 'static'),
      fixed(recipe: 2),
      fixed(counter: 8),
      fixed(utc: 1760000000000001),
      fixed(monotonic: 9001),
      fixed(readings: const []),
      fixed(readings: const [SignatureReading(lowByte: 172, ageMicros: 20)]),
    ]) {
      expect(other.seed, baseline.seed);
      expect(other.identity.photoId, isNot(baseline.identity.photoId));
    }
  });

  test(
    'secure nonces produce new fingerprints and eight-character references',
    () {
      final ids = <String>{};
      final fingerprints = <String>{};
      for (var i = 0; i < 64; i++) {
        final capture = PendingCaptureSignature().consume(
          counter: 1,
          utcMicros: 0,
          monotonicMicros: 0,
          styleId: 'static',
        );
        expect(
          capture.identity.photoId,
          matches(RegExp(r'^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{8}$')),
        );
        ids.add(capture.identity.photoId);
        final values = [
          capture.signature.x,
          capture.signature.y,
          capture.signature.z,
          capture.signature.w,
        ];
        for (final value in values) {
          expect(value, inInclusiveRange(0, 1 - 1 / 16777216));
          expect(value * 16777216, (value * 16777216).roundToDouble());
        }
        fingerprints.add(values.join(','));
      }
      expect(ids, hasLength(64));
      expect(fingerprints, hasLength(64));
    },
  );

  test(
    'pending identity is consumed once, also after invalid input or discard',
    () {
      final pending = PendingCaptureSignature(random: Random(1));
      pending.consume(
        counter: 1,
        utcMicros: 0,
        monotonicMicros: 0,
        styleId: 'tape',
      );
      expect(
        () => pending.consume(
          counter: 1,
          utcMicros: 0,
          monotonicMicros: 0,
          styleId: 'tape',
        ),
        throwsStateError,
      );
      final invalid = PendingCaptureSignature(random: Random(1));
      expect(
        () => invalid.consume(
          counter: 1,
          utcMicros: 0,
          monotonicMicros: 0,
          styleId: 'tape',
          readings: List.filled(33, const SignatureReading()),
        ),
        throwsArgumentError,
      );
      expect(
        () => invalid.consume(
          counter: 1,
          utcMicros: 0,
          monotonicMicros: 0,
          styleId: 'tape',
        ),
        throwsStateError,
      );
      final discarded = PendingCaptureSignature()..discard();
      expect(
        () => discarded.consume(
          counter: 1,
          utcMicros: 0,
          monotonicMicros: 0,
          styleId: 'tape',
        ),
        throwsStateError,
      );
    },
  );

  test('source availability, zero, stale readings and float32 validity differ', () {
    final source = SignatureSource(3);
    expect(source.readings(0).every((r) => !r.present), isTrue);
    source.update([0, 1.0000001192092896, double.nan], 100);
    final fresh = source.readings(120);
    expect(fresh[0].lowByte, 0);
    expect(fresh[0].fresh, isTrue);
    expect(fresh[1].lowByte, 1);
    expect(fresh[1].ageMicros, 20);
    expect(fresh[2].present, isFalse);
    expect(source.readings(1600101)[0].fresh, isFalse);
    expect(source.readings(99)[0].fresh, isFalse);
    final missing = fixed(readings: const [SignatureReading()]);
    final zero = fixed(
      readings: const [SignatureReading(lowByte: 0, ageMicros: 0)],
    );
    final stale = fixed(
      readings: const [SignatureReading(lowByte: 0, ageMicros: 1500001)],
    );
    expect(missing.identity.photoId, isNot(zero.identity.photoId));
    expect(stale.identity.photoId, isNot(zero.identity.photoId));
    // Stale low bits are excluded from derivation; age/presence still included.
    expect(
      stale.identity.photoId,
      fixed(
        readings: const [SignatureReading(lowByte: 255, ageMicros: 1500001)],
      ).identity.photoId,
    );
    source.update([double.infinity, 1e300, -double.infinity], 200);
    expect(source.readings(200).every((r) => !r.present), isTrue);
    source.clear();
    expect(source.readings(200).every((r) => !r.present), isTrue);
  });

  test(
    'injected clocks and RNG reproduce controller captures, not pending micro',
    () {
      SignatureController controller() => SignatureController(
        random: Random(123),
        clock: () => 9000,
        utcNow: () =>
            DateTime.fromMicrosecondsSinceEpoch(1760000000000000, isUtc: true),
      );
      final a = controller();
      final b = controller();
      addTearDown(a.clear);
      addTearDown(b.clear);
      final seed = a.seed;
      final preview = a.state;
      final shot = a.freeze(styleId: 'tape');
      expect(shot.seed, seed);
      expect(shot.signature.x, isNot(preview.x));
      expect(shot.identity.photoId, b.freeze(styleId: 'tape').identity.photoId);
      expect(a.seed, isNot(seed));
    },
  );

  test('immutable identity travels through ambient copies and result without JSON', () {
    final signature = fixed();
    final state = const AmbientState(noise: 0.2)
        .withCaptureSignature(signature);
    final rotated = state.forPhotoTurns(3, mirrorX: true);
    final result = CaptureResult.source(
      source: null,
      render: null,
      quality: ExportQuality.high,
      ambient: rotated,
      styleId: 'tape',
    );
    expect(result.identity, same(signature.identity));
    expect(result.captureSignature, same(signature));
    expect(rotated.signature, same(state.signature));
    expect(state.withSeed(0).identity, same(signature.identity));
    final json = jsonEncode(state.toJson());
    for (final excluded in [
      'seed',
      'signature',
      'fingerprint',
      'nonce',
      'photoId',
      'ageMicros',
      'lowByte',
      signature.identity.photoId,
    ]) {
      expect(json, isNot(contains(excluded)));
    }
    expect(jsonEncode(const AmbientState(noise: 0.2).toJson()), json);
    // New signature modules never call diagnostics, JSON, printing or file IO.
    for (final file in Directory(
      'lib/ambient/signature',
    ).listSync().whereType<File>()) {
      expect(
        file.readAsStringSync(),
        isNot(
          matches(RegExp(r'\b(print|debugPrint|toJson|DebugLog|File)\s*\(')),
        ),
      );
    }
    expect(
      File('lib/debug/debug_hud.dart').readAsStringSync(),
      isNot(contains('state.seed')),
    );
  });
}
