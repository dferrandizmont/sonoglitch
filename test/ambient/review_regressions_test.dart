import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_controller.dart';
import 'package:sonoglitch/ambient/spectrum_service.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/ambient/motion_service.dart';
import 'package:sonoglitch/ambient/scene_motion.dart';
import 'package:sonoglitch/ambient/signal_intensity.dart';
import 'package:sonoglitch/camera/capture_orientation.dart';
import 'package:sonoglitch/camera/oriented_still.dart';

import '../support/fakes.dart';
import 'noise_service_test.dart' show FakeClock, buildService, feed;

MotionService motionFor(FakeClock clock) => MotionService(
  samples: const Stream<AccelSample>.empty(),
  gyroSamples: const Stream<AccelSample>.empty(),
  gravitySamples: const Stream<AccelSample>.empty(),
  clock: clock.call,
);

// A non-periodic spatial texture makes diagonal block matches unambiguous.
double texture(int x, int y) =>
    40 + math.Random(y * 997 + x * 17).nextInt(150).toDouble();

Uint8List frame({
  int shiftX = 0,
  int shiftY = 0,
  int width = 256,
  int height = 384,
}) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = texture(
        x * 32 ~/ width - shiftX,
        y * 24 ~/ height - shiftY,
      ).round();
      final i = (y * width + x) * 4;
      pixels[i] = pixels[i + 1] = pixels[i + 2] = value;
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}

void main() {
  test(
    'portrait sideways shake cannot rotate capture; a sustained turn can',
    () {
      final tracker = CaptureOrientationTracker();
      for (var i = 0; i < 20; i++) {
        tracker.addGravity(0, 9.8, 0);
      }
      tracker.addGravity(14, 9.8, 0);
      expect(tracker.value, CaptureOrientation.portrait);
      // Even a short impulse with a plausible gravity magnitude is filtered.
      tracker.addGravity(9.8, 0, 0);
      tracker.addGravity(0, 9.8, 0);
      expect(tracker.value, CaptureOrientation.portrait);
      for (var i = 0; i < 20; i++) {
        tracker.addGravity(9.8, 0, 0);
      }
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      // Diagonal jitter and a screen-flat pose preserve the last stable pose.
      for (var i = 0; i < 20; i++) {
        tracker.addGravity(i.isEven ? 6.7 : 7.1, i.isEven ? 7.1 : 6.7, 0);
      }
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      for (var i = 0; i < 20; i++) {
        tracker.addGravity(-3, 0, 9.5);
      }
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      tracker.addGravity(double.infinity, 0, 0);
      expect(tracker.value, CaptureOrientation.landscapeLeft);
      for (var i = 0; i < 25; i++) {
        tracker.addGravity(-9.8, 0, 0);
      }
      expect(tracker.value, CaptureOrientation.landscapeRight);
    },
  );

  for (final front in [false, true]) {
    for (final mirrored in [false, true]) {
      test(
        'still basis front=$front mirrored=$mirrored reflects BEFORE rotating',
        () {
          const state = AmbientState(
            motion: 0.8,
            motionDirX: 1,
            motionDirY: 0.5,
          );
          for (final pose in CaptureOrientation.values) {
            final transform = StillTransform(
              frontLens: front,
              decodedMirrored: mirrored,
              previewQuarterTurns: pose.quarterTurns,
            );
            final result = state.forPhotoTurns(
              transform.quarterTurns,
              mirrorX: transform.mirrorPreview,
            );
            // First reflect into the decoded photo, then rotate its pixel axes.
            final x = front != mirrored ? -1.0 : 1.0;
            final angle = transform.quarterTurns * math.pi / 2;
            expect(
              result.motionDirX,
              closeTo(x * math.cos(angle) + 0.5 * math.sin(angle), 1e-9),
            );
            expect(
              result.motionDirY,
              closeTo(-x * math.sin(angle) + 0.5 * math.cos(angle), 1e-9),
            );
            expect(result.motion, state.motion);
          }
        },
      );
    }
  }

  test(
    'stationary gain and offset exposure flicker does not become motion',
    () {
      final scene = SceneMotion();
      final grid = [
        for (var y = 0; y < 24; y++)
          for (var x = 0; x < 32; x++) x < 16 ? 50.0 : 150.0,
      ];
      scene.addGrid(grid);
      for (var i = 0; i < 20; i++) {
        scene.addGrid(
          grid.map((v) => i.isEven ? v * 1.5 : v * 0.8 + 10).toList(),
        );
        expect(scene.level, 0);
        expect(scene.difference, 0);
      }
    },
  );

  test(
    'dark noise and independent sensor noise lack structured displacement',
    () {
      final random = math.Random(44);
      final scene = SceneMotion();
      for (final mean in [8, 100]) {
        scene.reset();
        for (var i = 0; i < 20; i++) {
          scene.addGrid(
            List.generate(32 * 24, (_) => mean + random.nextDouble() * 16 - 8),
          );
          expect(scene.level, 0);
        }
      }
    },
  );

  test('RGBA grid spatially averages isolated pixel flicker', () {
    final scene = SceneMotion();
    final first = frame();
    final second = Uint8List.fromList(first);
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 32; x++) {
        // These are the single pixels that the former point sampler read.
        final i =
            (((y + 0.5) * 16).floor() * 256 + ((x + 0.5) * 8).floor()) * 4;
        second[i] = second[i + 1] = second[i + 2] = 255;
      }
    }
    scene.addRgba(first, 256, 384);
    scene.addRgba(second, 256, 384);
    expect(scene.level, 0);
  });

  test('portrait diagonal displacement uses image pixels, not stretched grid cells', () {
    final scene = SceneMotion();
    scene.addRgba(frame(width: 270, height: 360), 270, 360);
    scene.addRgba(
      frame(shiftX: 1, shiftY: 1, width: 270, height: 360),
      270,
      360,
    );
    expect(scene.level, greaterThan(0.5));
    // One cell is 8.4375 pixels wide and 15 high: about 60.6 degrees.
    expect(scene.dx, closeTo(9 / math.sqrt(337), 1e-9));
    expect(scene.dy, closeTo(-16 / math.sqrt(337), 1e-9));
  });

  for (final front in [false, true]) {
    for (final mirrored in [false, true]) {
      for (final yaw in [false, true]) {
        test(
          'gyro and scene agree for same positive ${yaw ? 'yaw' : 'pitch'} front=$front mirrored=$mirrored',
          () {
            final clock = FakeClock();
            final gyro = motionFor(clock)
              ..setCameraBasis(frontLens: front, mirrored: mirrored);
            final scene = motionFor(clock)
              ..setCameraBasis(frontLens: front, mirrored: mirrored);
            // Positive right-handed yaw sends the stationary rear scene right.
            // Positive pitch sends it down on the rear lens and up on the front.
            // A horizontal preview mirror reverses yaw only.
            final shiftX = yaw ? (mirrored ? -1 : 1) : 0;
            final shiftY = yaw ? 0 : (front ? -1 : 1);
            scene.addSceneFrame(frame(), 256, 384);
            for (var i = 1; i <= 5; i++) {
              clock.advance(const Duration(milliseconds: 100));
              gyro.addGyroSample(
                yaw ? const AccelSample(0, 2, 0) : const AccelSample(2, 0, 0),
              );
              scene.addSceneFrame(
                frame(shiftX: shiftX * i, shiftY: shiftY * i),
                256,
                384,
              );
            }
            expect(scene.sceneLevel, greaterThan(0.5));
            expect(
              gyro.dirX * scene.dirX + gyro.dirY * scene.dirY,
              greaterThan(0.99),
            );
          },
        );
      }
    }
  }

  test(
    'fused direction transitions smoothly as scene displaces gyro dominance',
    () {
      final clock = FakeClock();
      final motion = motionFor(clock);
      motion.addGyroSample(const AccelSample(0, 2, 0));
      expect(motion.dirX, 1);
      clock.advance(const Duration(seconds: 2));
      motion.addSceneFrame(frame(), 256, 384);
      clock.advance(const Duration(milliseconds: 20));
      motion.addSceneFrame(frame(shiftX: -1), 256, 384);
      expect(motion.sceneLevel, greaterThan(motion.gyroLevel));
      expect(
        motion.dirX,
        greaterThan(0.8),
        reason: 'no instant reversal on source change',
      );
      for (var i = 2; i <= 20; i++) {
        clock.advance(const Duration(milliseconds: 100));
        motion.addSceneFrame(frame(shiftX: -i), 256, 384);
      }
      expect(motion.dirX, lessThan(-0.9));
      motion.setCameraBasis(frontLens: true, mirrored: true);
      expect(motion.sceneLevel, 0);
      expect(motion.gyroLevel, 0);
      motion.addGyroSample(const AccelSample(0, 2, 0));
      expect(motion.dirX, -1);
    },
  );

  for (final quietHistory in [false, true]) {
    test(
      'complete noise/controller/intensity pipeline, quiet history=$quietHistory',
      () {
        final clock = FakeClock();
        final noise = buildService(clock);
        final controller = AmbientController(
          spectrum: SpectrumService(source: const NoopSpectrumSource()),
          noise: noise,
          motion: motionFor(clock),
          light: LightService(ambientLight: FakeAmbientLightSource()),
          clock: clock.call,
        );
        addTearDown(controller.dispose);
        expect(noise.floorDb, 58);
        void assertIntensities({
          required double minimum,
          required double maximum,
        }) {
          controller.setIntensity(SignalIntensity.subtle);
          controller.tick();
          final subtle = controller.value.noise;
          controller.setIntensity(SignalIntensity.normal);
          controller.tick();
          final normal = controller.value.noise;
          expect(normal, inInclusiveRange(minimum, maximum));
          expect(controller.snapshot().noise, closeTo(normal, 1e-9));
          controller.setIntensity(SignalIntensity.extreme);
          expect(subtle, lessThan(normal));
          expect(controller.value.noise, greaterThanOrEqualTo(normal));
        }

        if (quietHistory) {
          // Quiet-room behavior must hold before and after the slow adaptation.
          feed(noise, clock, 62, const Duration(seconds: 2));
          assertIntensities(minimum: 0, maximum: 0.249);
          feed(noise, clock, 62, const Duration(minutes: 3));
          assertIntensities(minimum: 0, maximum: 0.249);
          expect(noise.floorDb, inExclusiveRange(60, 62));
        }
        feed(noise, clock, 80, const Duration(seconds: 1));
        assertIntensities(minimum: quietHistory ? 0.9 : 0.6, maximum: 1);
        // Even a long session that starts loud cannot calibrate the stadium away.
        feed(noise, clock, 80, const Duration(minutes: 15));
        assertIntensities(minimum: 0.6, maximum: 1);
        expect(noise.floorDb, lessThanOrEqualTo(70));
        expect(noise.ceilingDb - noise.floorDb, greaterThanOrEqualTo(15));
      },
    );
  }

  test(
    'quiet floor follows recent P10 slowly, bounds it, and resets per session',
    () {
      final clock = FakeClock();
      final noise = buildService(clock);
      for (var second = 0; second < 180; second++) {
        feed(
          noise,
          clock,
          second % 5 == 0 ? 80 : 62,
          const Duration(seconds: 1),
        );
      }
      expect(
        noise.floorDb,
        inExclusiveRange(60, 62),
        reason: 'peaks must not raise P10',
      );
      feed(noise, clock, 20, const Duration(minutes: 20));
      expect(noise.floorDb, inInclusiveRange(45, 45.1));
      feed(noise, clock, 100, const Duration(minutes: 20));
      expect(noise.floorDb, inInclusiveRange(69.9, 70));
      expect(noise.ceilingDb - noise.floorDb, greaterThanOrEqualTo(15));
      final floor = noise.floorDb;
      noise.addReading(double.nan);
      expect(noise.floorDb, floor);
      expect(buildService(clock).floorDb, 58);
    },
  );
}
