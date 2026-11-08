import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/light_service.dart';
import 'package:sonoglitch/camera/camera_service.dart';
import 'package:sonoglitch/camera/frame_converter.dart';
import 'package:sonoglitch/camera/frame_worker.dart';
import 'package:sonoglitch/camera/raw_frame.dart';
import 'package:sonoglitch/debug/debug_log.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const description = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  group('the frame worker', () {
    test(
      'the isolate gives the same picture as the synchronous path',
      () async {
        final worker = IsolateFrameWorker();
        await worker.start();
        addTearDown(worker.dispose);
        final inline = InlineFrameWorker(const FrameConverter());

        for (final format in FrameFormat.values) {
          for (final rotation in [0, 90, 180, 270]) {
            for (final mirror in [false, true]) {
              final frame = _frame(format);
              final expected = await _convert(
                inline,
                frame,
                rotationDegrees: rotation,
                mirror: mirror,
              );
              final actual = await _convert(
                worker,
                frame,
                rotationDegrees: rotation,
                mirror: mirror,
              );
              expect(actual, isNotNull, reason: 'the frame must be converted');
              expect(actual!.width, expected!.width);
              expect(actual.height, expected.height);
              expect(actual.pixels, expected.pixels);
              expect(actual.meanLuma, expected.meanLuma);
              expect(actual.sceneLuma, expected.sceneLuma);
              expect(
                actual.colorfulness?.allowance,
                expected.colorfulness?.allowance,
              );
              expect(
                actual.colorfulness?.meanSaturation,
                expected.colorfulness?.meanSaturation,
              );
            }
          }
        }
      },
    );

    test('the synchronous path answers before it returns', () async {
      final inline = InlineFrameWorker(const FrameConverter());
      var answered = false;
      inline.convert(
        _frame(FrameFormat.yuv420),
        rotationDegrees: 0,
        mirror: false,
        onConverted: (_) => answered = true,
        onError: (error, stackTrace) => fail('$error'),
      );
      expect(
        answered,
        isTrue,
        reason: 'the caller sees the frame in the same tick it asked for it',
      );
    });

    test('the isolate answers later, in another isolate', () async {
      final worker = IsolateFrameWorker();
      await worker.start();
      addTearDown(worker.dispose);
      var answered = false;
      worker.convert(
        _frame(FrameFormat.yuv420),
        rotationDegrees: 0,
        mirror: false,
        onConverted: (_) => answered = true,
        onError: (error, stackTrace) => fail('$error'),
      );
      expect(
        answered,
        isFalse,
        reason: 'the picture comes back from the background isolate',
      );
      await _waitUntil(() => answered);
      expect(answered, isTrue);
    });

    test('the worker of the app converts the frames in an isolate', () async {
      // The wiring of the app: the frames leave the UI isolate.
      final worker = isolateFrameWorker(const FrameConverter());
      expect(worker, isA<IsolateFrameWorker>());
      await worker.start();
      addTearDown(worker.dispose);
      expect(
        worker.usesBackgroundIsolate,
        isTrue,
        reason: 'the app converts the frames in a background isolate',
      );
    });

    test(
      'the isolate uses the settings of the converter of the service',
      () async {
        final worker = IsolateFrameWorker(
          converter: const FrameConverter(targetLongSide: 64),
        );
        await worker.start();
        addTearDown(worker.dispose);

        final conversion = await _convert(
          worker,
          _frame(FrameFormat.yuv420),
          rotationDegrees: 0,
          mirror: false,
        );

        expect(conversion, isNotNull);
        expect(
          conversion!.width,
          lessThanOrEqualTo(64),
          reason:
              'the isolate must use the size of the service, not the default',
        );
        expect(conversion.height, lessThanOrEqualTo(64));
      },
    );

    test(
      'a frame that was in flight when the isolate died is not left pending',
      () async {
        final worker = IsolateFrameWorker();
        await worker.start();
        addTearDown(worker.dispose);

        final completer = Completer<FrameConversion?>();
        worker.convert(
          _bigFrame(),
          rotationDegrees: 0,
          mirror: false,
          onConverted: (conversion) {
            if (!completer.isCompleted) completer.complete(conversion);
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );

        // The isolate dies with the frame in flight. The frame must not stay
        // pending for ever: the caller has to be released.
        await worker.killIsolate();

        final result = await completer.future.timeout(
          const Duration(seconds: 5),
        );
        expect(
          result,
          isNull,
          reason: 'the frame of a dead isolate must be dropped, not pending',
        );
        expect(
          worker.usesBackgroundIsolate,
          isFalse,
          reason: 'the dead isolate is released',
        );
      },
    );

    test('the next frame is converted after the isolate died', () async {
      final worker = IsolateFrameWorker();
      await worker.start();
      addTearDown(worker.dispose);

      await worker.killIsolate();

      // The next frame is converted in the isolate of the caller, so the
      // preview does not freeze for good.
      final next = await _convert(
        worker,
        _frame(FrameFormat.yuv420),
        rotationDegrees: 0,
        mirror: false,
      );
      expect(next, isNotNull, reason: 'the next frame must be converted');
      expect(next!.width, greaterThan(0));
    });

    test('the worker starts when the isolate cannot answer', () async {
      final worker = IsolateFrameWorker();
      // The isolate is killed before it can answer, so the worker must fall
      // back to the isolate of the caller instead of waiting for ever.
      await worker.start();
      await worker.killIsolate();

      expect(worker.usesBackgroundIsolate, isFalse);
      final conversion = await _convert(
        worker,
        _frame(FrameFormat.yuv420),
        rotationDegrees: 0,
        mirror: false,
      );
      expect(conversion, isNotNull);
    });

    test(
      'disposing with a frame in flight drops it without throwing',
      () async {
        final worker = IsolateFrameWorker();
        await worker.start();
        expect(
          worker.usesBackgroundIsolate,
          isTrue,
          reason: 'the isolate is running',
        );

        final completer = Completer<FrameConversion?>();
        worker.convert(
          _frame(FrameFormat.yuv420),
          rotationDegrees: 0,
          mirror: false,
          onConverted: (conversion) {
            if (!completer.isCompleted) completer.complete(conversion);
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );

        worker.dispose();

        final result = await completer.future;
        expect(result, isNull, reason: 'the frame in flight is dropped');
        expect(
          worker.usesBackgroundIsolate,
          isFalse,
          reason: 'the isolate is released with the worker',
        );
      },
    );

    test('a closed worker does not convert anything else', () async {
      final worker = InlineFrameWorker(const FrameConverter());
      worker.dispose();
      final completer = Completer<FrameConversion?>();
      worker.convert(
        _frame(FrameFormat.yuv420),
        rotationDegrees: 0,
        mirror: false,
        onConverted: (conversion) {
          if (!completer.isCompleted) completer.complete(conversion);
        },
        onError: (error, stackTrace) => fail('$error'),
      );
      expect(await completer.future, isNull);
    });
  });

  group('the camera service with a worker', () {
    test('a frame of an old stream generation is discarded', () async {
      final light = LightService();
      final devices = <FakeCameraDevice>[];
      final worker = _HoldingWorker();
      addTearDown(worker.close);
      final camera = CameraService(
        light: light,
        log: DebugLog(),
        workerFactory: (_) => worker,
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
        imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
      );
      addTearDown(camera.dispose);

      await camera.initialize();
      devices.single.pushFrame(buildTestFrame());
      await worker.converted.future;

      // The camera is hidden and the stream comes back: the frame that was
      // in flight belongs to a stream that is not the current one.
      await camera.setPaused(true);
      await camera.setPaused(false);
      worker.release();
      await Future<void>.delayed(Duration.zero);

      expect(
        camera.frame.value,
        isNull,
        reason: 'the frame of the old generation must not be published',
      );
      expect(
        light.rawLuma,
        isNull,
        reason: 'the frame of the old generation must not be measured',
      );
      expect(camera.metrics.value.frames, 0);
    });

    test('the frame of the current generation is published', () async {
      final light = LightService();
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: light,
        log: DebugLog(),
        workerFactory: (converter) => IsolateFrameWorker(converter: converter),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
        imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
      );
      addTearDown(camera.dispose);

      await camera.initialize();
      devices.single.pushFrame(buildTestFrame());
      for (var i = 0; camera.frame.value == null && i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(camera.frame.value, isNotNull, reason: 'the frame is published');
      expect(light.rawLuma, isNotNull, reason: 'the scene is measured');
      expect(camera.metrics.value.frames, 1);
    });

    test('the preview keeps working after a pause and a resume', () async {
      final light = LightService();
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: light,
        log: DebugLog(),
        workerFactory: (converter) => IsolateFrameWorker(converter: converter),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
        imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
      );
      addTearDown(camera.dispose);

      await camera.initialize();
      await camera.setPaused(true);
      await camera.setPaused(false);

      devices.last.pushFrame(buildTestFrame());
      await _waitUntil(() => camera.frame.value != null);

      expect(
        camera.frame.value,
        isNotNull,
        reason: 'the frames are converted again after a resume',
      );
      expect(light.rawLuma, isNotNull, reason: 'the scene is measured again');
      expect(camera.metrics.value.frames, 1);
    });

    test('the preview keeps working after a lens change', () async {
      const front = CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 90,
      );
      final light = LightService();
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: light,
        log: DebugLog(),
        workerFactory: (converter) => IsolateFrameWorker(converter: converter),
        lister: () async => const [description, front],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
        imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
      );
      addTearDown(camera.dispose);

      await camera.initialize();
      await camera.flip();

      devices.last.pushFrame(buildTestFrame());
      await _waitUntil(() => camera.frame.value != null);

      expect(
        camera.frame.value,
        isNotNull,
        reason: 'the frames are converted again after a lens change',
      );
      expect(camera.metrics.value.frames, 1);
    });

    test('the preview works when the worker cannot be built', () async {
      final light = LightService();
      final devices = <FakeCameraDevice>[];
      final camera = CameraService(
        light: light,
        log: DebugLog(),
        workerFactory: (_) => throw StateError('the worker cannot be built'),
        lister: () async => const [description],
        deviceFactory: (description, preset) {
          final device = FakeCameraDevice();
          devices.add(device);
          return device;
        },
        imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
      );
      addTearDown(camera.dispose);

      await camera.initialize();
      devices.single.pushFrame(buildTestFrame());
      await _waitUntil(() => camera.frame.value != null);

      expect(
        camera.frame.value,
        isNotNull,
        reason:
            'the frames are converted in the UI isolate when the worker '
            'cannot be built',
      );
      expect(light.rawLuma, isNotNull);
    });

    test(
      'the worker is closed when the camera is hidden while it starts',
      () async {
        final gate = Completer<void>();
        final workers = <_GatedWorker>[];
        final devices = <FakeCameraDevice>[];
        final camera = CameraService(
          light: LightService(),
          log: DebugLog(),
          workerFactory: (_) {
            final worker = _GatedWorker(gate);
            workers.add(worker);
            return worker;
          },
          lister: () async => const [description],
          deviceFactory: (description, preset) {
            final device = FakeCameraDevice();
            devices.add(device);
            return device;
          },
          imageFactory: (conversion) => buildTestImage(width: 2, height: 1),
        );
        addTearDown(camera.dispose);

        final initializing = camera.initialize();
        // The camera is hidden while the worker is starting.
        await _waitUntil(() => workers.isNotEmpty);
        final hiding = camera.setPaused(true);
        gate.complete();
        await initializing;
        await hiding;

        expect(workers, hasLength(1));
        expect(
          workers.single.disposed,
          isTrue,
          reason:
              'the worker that was created must be released with the '
              'hidden camera',
        );
        expect(
          devices.single.starts,
          0,
          reason:
              'the stream must not start behind the back of the '
              'viewfinder',
        );
      },
    );
  });
}

/// A frame big enough that its conversion takes a moment.
///
/// The isolate needs time to convert it, so a test can kill the isolate
/// while the frame is still in flight.
RawFrame _bigFrame() {
  const width = 640;
  const height = 480;
  final chroma = Uint8List((width ~/ 2) * (height ~/ 2));
  for (var i = 0; i < chroma.length; i++) {
    chroma[i] = 128;
  }
  return RawFrame(
    width: width,
    height: height,
    format: FrameFormat.yuv420,
    planes: [
      RawPlane(
        bytes: Uint8List.fromList(
          List<int>.generate(width * height, (i) => (i * 7) % 256),
        ),
        bytesPerRow: width,
      ),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
      RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
    ],
  );
}

/// A worker that waits before it starts.
///
/// It stands for a worker that needs a moment to be ready, so the camera
/// can be hidden while it is starting.
class _GatedWorker implements FrameConversionWorker {
  _GatedWorker(this._gate);

  final Completer<void> _gate;

  /// Whether the worker was closed.
  bool disposed = false;

  @override
  bool get usesBackgroundIsolate => false;

  @override
  Future<void> start() => _gate.future;

  @override
  void convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
    required void Function(FrameConversion?) onConverted,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    onConverted(null);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// Waits until [condition] is true, or fails when it takes too long.
///
/// The round trip of the isolate is not instantaneous, so a test must not
/// rely on a single turn of the event loop.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the condition was not met within ${timeout.inMilliseconds} ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Converts a frame with a worker and waits for the result.
Future<FrameConversion?> _convert(
  FrameConversionWorker worker,
  RawFrame frame, {
  required int rotationDegrees,
  required bool mirror,
}) {
  final completer = Completer<FrameConversion?>();
  worker.convert(
    frame,
    rotationDegrees: rotationDegrees,
    mirror: mirror,
    onConverted: (conversion) {
      if (!completer.isCompleted) completer.complete(conversion);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
  );
  return completer.future;
}

/// A frame of one grey value, in the format of the camera.
RawFrame _frame(FrameFormat format) {
  const width = 4;
  const height = 2;
  final chroma = Uint8List((width ~/ 2) * (height ~/ 2));
  for (var i = 0; i < chroma.length; i++) {
    chroma[i] = 128;
  }
  return RawFrame(
    width: width,
    height: height,
    format: format,
    planes: format == FrameFormat.bgra8888
        ? [
            RawPlane(
              bytes: Uint8List.fromList(
                List<int>.generate(width * height * 4, (i) => (i * 37) % 256),
              ),
              bytesPerRow: width * 4,
              bytesPerPixel: 4,
            ),
          ]
        : [
            RawPlane(
              bytes: Uint8List.fromList(
                List<int>.generate(width * height, (i) => 40 + i * 30),
              ),
              bytesPerRow: width,
            ),
            RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
            RawPlane(bytes: chroma, bytesPerRow: width ~/ 2),
          ],
  );
}

/// A worker that holds the frame until the test releases it.
///
/// The worker keeps the background isolate alive when it is disposed, so the
/// generation of the stream is what discards the frame, not the worker.
class _HoldingWorker implements FrameConversionWorker {
  _HoldingWorker() : _inner = IsolateFrameWorker();

  final IsolateFrameWorker _inner;
  final Completer<void> _converted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  /// Completes when the frame has been converted and is waiting.
  Completer<void> get converted => _converted;

  /// Lets the waiting frame arrive.
  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  /// Closes the background isolate.
  void close() => _inner.dispose();

  @override
  bool get usesBackgroundIsolate => _inner.usesBackgroundIsolate;

  @override
  Future<void> start() => _inner.start();

  @override
  void convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
    required void Function(FrameConversion? conversion) onConverted,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    _inner.convert(
      frame,
      rotationDegrees: rotationDegrees,
      mirror: mirror,
      onConverted: (conversion) {
        if (!_converted.isCompleted) _converted.complete();
        _release.future.then((_) => onConverted(conversion));
      },
      onError: onError,
    );
  }

  @override
  void dispose() {
    // The frame in flight is kept, so the test can release it after the
    // stream of the camera changed.
  }
}
