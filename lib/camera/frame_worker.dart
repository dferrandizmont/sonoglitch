import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../ambient/signature/scene_signature.dart';
import 'frame_converter.dart';
import 'raw_frame.dart';

/// Converts the frames of the camera.
///
/// The service asks the worker for a frame and gets the result back through
/// a callback. The implementation decides where the work happens: in the
/// isolate of the caller or in a background isolate. The service does not
/// care, so both paths share the same code and the same guarantees.
abstract interface class FrameConversionWorker {
  /// Prepares the worker.
  ///
  /// It is called when the stream starts, before the first frame. A worker
  /// that cannot run must not throw: it converts the frames in the isolate
  /// of the caller instead.
  Future<void> start();

  /// Converts [frame] into an upright RGBA buffer.
  ///
  /// The result is handed to [onConverted]: the inline worker does it
  /// before this call returns, the isolate worker does it when the
  /// background isolate answers. A frame that was dropped arrives as null.
  ///
  /// A conversion that could not be done is reported through [onError]. The
  /// worker never throws.
  void convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
    required void Function(FrameConversion? conversion) onConverted,
    required void Function(Object error, StackTrace stackTrace) onError,
  });

  /// Whether the frames are converted in a background isolate.
  ///
  /// It is false when the worker converts them in the isolate of the caller,
  /// which is the fallback when no isolate can be spawned.
  bool get usesBackgroundIsolate;

  /// Closes the worker.
  ///
  /// A conversion that is in flight is dropped, not thrown, and everything
  /// the worker holds is released.
  void dispose();
}

/// Builds the worker that converts the frames.
///
/// The converter is given to the factory so the worker uses the same
/// settings as the service.
typedef FrameWorkerFactory = FrameConversionWorker Function(
  FrameConverter converter,
);

/// Builds the worker that converts the frames in the isolate of the caller.
///
/// It is the default of the camera service: the conversion stays where the
/// caller is, which is what the tests observe. The app injects the worker
/// that converts the frames in a background isolate.
FrameConversionWorker inlineFrameWorker(FrameConverter converter) =>
    InlineFrameWorker(converter);

/// Builds the worker that converts the frames in a background isolate.
///
/// It is the worker of the app: the conversion leaves the UI isolate, so
/// the interface stays responsive while a frame is converted. The settings
/// of the converter travel with the request, so the isolate uses the same
/// ones as the service.
FrameConversionWorker isolateFrameWorker(FrameConverter converter) =>
    IsolateFrameWorker(converter: converter);

/// Converts the frames in the isolate of the caller.
///
/// It is the fallback when no background isolate can be used, and the path
/// the tests observe. The conversion happens before [convert] returns, so
/// the caller sees the frame in the same tick it asked for it.
class InlineFrameWorker implements FrameConversionWorker {
  InlineFrameWorker(this.converter);

  /// The converter of the raw frames.
  final FrameConverter converter;

  bool _disposed = false;

  @override
  bool get usesBackgroundIsolate => false;

  @override
  Future<void> start() async {}

  @override
  void convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
    required void Function(FrameConversion? conversion) onConverted,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    if (_disposed) {
      onConverted(null);
      return;
    }
    try {
      onConverted(
        converter.convert(
          frame,
          rotationDegrees: rotationDegrees,
          mirror: mirror,
        ),
      );
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _disposed = true;
  }
}

/// Converts the frames in a background isolate.
///
/// The isolate is spawned when the worker starts and lives until it is
/// disposed, so the cost of the spawn is paid once per stream and not once
/// per frame. The planes travel as transferable data and the pixels come
/// back the same way, so neither direction copies the buffer twice. The
/// staging of the planes still copies them once on the calling isolate:
/// the transfer is zero copy, but the preparation of the buffer is not.
///
/// The converter stays a pure function: the isolate only calls it. When no
/// isolate can be spawned, the conversion falls back to the isolate of the
/// caller, so the preview keeps working everywhere.
class IsolateFrameWorker implements FrameConversionWorker {
  IsolateFrameWorker({FrameConverter? converter})
    : _converter = converter ?? const FrameConverter() {
    _inline = InlineFrameWorker(_converter);
  }

  final FrameConverter _converter;

  /// The worker used when no isolate is available.
  late final InlineFrameWorker _inline;

  Isolate? _isolate;
  ReceivePort? _results;
  ReceivePort? _exit;
  SendPort? _commands;
  bool _disposed = false;
  bool _started = false;
  bool _deathLogged = false;
  int _nextId = 0;
  final Map<int, Completer<FrameConversion?>> _pending = {};

  /// Whether the worker holds a background isolate.
  @override
  bool get usesBackgroundIsolate => _isolate != null;

  /// Prepares the worker and spawns its isolate.
  ///
  /// It never throws: a platform that cannot spawn an isolate keeps the
  /// conversion in the isolate of the caller. It never waits forever either:
  /// an isolate that dies before it answers leaves the frames to the isolate
  /// of the caller.
  @override
  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    final results = ReceivePort();
    final exit = ReceivePort();
    // The port of the isolate is null when the isolate stopped before it
    // was ready: the frames are then converted in the isolate of the caller.
    final ready = Completer<SendPort?>();
    results.listen(
      (message) {
        if (message is SendPort) {
          if (!ready.isCompleted) ready.complete(message);
          return;
        }
        _onResult(message);
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete(null);
        _onIsolateDead();
      },
    );
    // The exit of the isolate is watched: a dead isolate never answers, so
    // the frame in flight would stay pending for ever. A death before the
    // isolate sent its port also ends the wait for it at once, so start()
    // does not sit out the ready timeout, and a port that arrives after the
    // death is ignored.
    exit.listen((_) {
      if (!ready.isCompleted) ready.complete(null);
      _onIsolateDead();
    });
    try {
      final isolate = await Isolate.spawn(_workerMain, results.sendPort);
      isolate.addOnExitListener(exit.sendPort);
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        results.close();
        exit.close();
        return;
      }
      _isolate = isolate;
      _results = results;
      _exit = exit;
      SendPort? commands;
      try {
        commands = await ready.future.timeout(
          _readyTimeout,
          onTimeout: () => null,
        );
      } on TimeoutException {
        commands = null;
      }
      if (commands == null) {
        // The isolate stopped before it was ready, or it did not answer in
        // time: the frames are converted in the isolate of the caller.
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        _results = null;
        _exit = null;
        results.close();
        exit.close();
        _drainPending();
        return;
      }
      _commands = commands;
    } catch (_) {
      // The isolate cannot be spawned: the frames are converted here.
      results.close();
      exit.close();
      _results = null;
      _exit = null;
    }
  }

  /// How long the isolate has to answer before the frames are converted in
  /// the isolate of the caller instead.
  static const Duration _readyTimeout = Duration(seconds: 5);

  /// Kills the background isolate, as a crash of the platform would.
  ///
  /// The frames that were in flight are dropped and the next ones are
  /// converted in the isolate of the caller. It is exposed so the tests can
  /// check the behaviour of a dead isolate.
  @visibleForTesting
  Future<void> killIsolate() async {
    final isolate = _isolate;
    if (isolate == null) return;
    isolate.kill(priority: Isolate.immediate);
    // The worker learns that the isolate is dead through the exit port, but
    // the frames that were in flight are dropped here so the caller is
    // released even if the port is late.
    _onIsolateDead();
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void convert(
    RawFrame frame, {
    required int rotationDegrees,
    required bool mirror,
    required void Function(FrameConversion? conversion) onConverted,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    if (_disposed) {
      onConverted(null);
      return;
    }
    final commands = _commands;
    if (commands == null) {
      // The isolate is not ready: the frame is converted here.
      _inline.convert(
        frame,
        rotationDegrees: rotationDegrees,
        mirror: mirror,
        onConverted: onConverted,
        onError: onError,
      );
      return;
    }
    final id = _nextId++;
    final completer = Completer<FrameConversion?>();
    _pending[id] = completer;
    try {
      commands.send(
        _ConvertRequest(
          id: id,
          width: frame.width,
          height: frame.height,
          format: frame.format,
          data: TransferableTypedData.fromList([
            for (final plane in frame.planes) plane.bytes,
          ]),
          planeLengths: [for (final plane in frame.planes) plane.bytes.length],
          bytesPerRow: [for (final plane in frame.planes) plane.bytesPerRow],
          bytesPerPixel: [
            for (final plane in frame.planes) plane.bytesPerPixel,
          ],
          rotationDegrees: rotationDegrees,
          mirror: mirror,
          converter: _converter.config,
        ),
      );
    } catch (_) {
      // The isolate died: the frame is converted here.
      _pending.remove(id);
      _inline.convert(
        frame,
        rotationDegrees: rotationDegrees,
        mirror: mirror,
        onConverted: onConverted,
        onError: onError,
      );
      return;
    }
    completer.future.then(
      onConverted,
      onError: (Object error, StackTrace stackTrace) {
        onError(error, stackTrace);
      },
    );
  }

  void _onResult(Object? message) {
    if (message is _Converted) {
      final completer = _pending.remove(message.id);
      if (completer == null || completer.isCompleted) return;
      completer.complete(
        FrameConversion(
          pixels: message.pixels.materialize().asUint8List(),
          width: message.width,
          height: message.height,
          meanLuma: message.meanLuma,
          sceneLuma: message.sceneLuma,
          colorfulness: message.colorfulness,
        ),
      );
      return;
    }
    if (message is _Failed) {
      final completer = _pending.remove(message.id);
      if (completer == null || completer.isCompleted) return;
      completer.completeError(
        StateError(message.error),
        StackTrace.fromString(message.stack),
      );
    }
  }

  /// Releases everything the worker holds.
  ///
  /// The frame that was in flight is dropped, not thrown, and the isolate is
  /// killed.
  @override
  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _results?.close();
    _results = null;
    _exit?.close();
    _exit = null;
    _commands = null;
    // The frames that were in flight are dropped, not thrown.
    _drainPending();
  }

  /// Releases the worker of the isolate that died.
  ///
  /// A dead isolate never answers, so the frames that were in flight are
  /// dropped and the next frames are converted in the isolate of the caller.
  void _onIsolateDead() {
    _isolate = null;
    _commands = null;
    _drainPending();
    if (_disposed) return;
    if (_deathLogged) return;
    _deathLogged = true;
    debugPrint(
      'IsolateFrameWorker: the background isolate died; '
      'the frames are converted in the UI isolate from now on.',
    );
  }

  /// Completes the frames that were in flight with nothing.
  ///
  /// They are dropped, not thrown: the caller sees a frame that was not
  /// converted and releases its conversion slot.
  void _drainPending() {
    if (_pending.isEmpty) return;
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete(null);
    }
  }
}

/// The entry point of the background isolate.
///
/// It converts the frames it receives with the same converter the service
/// uses and sends the result back. Nothing else lives in the isolate.
void _workerMain(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort.send(commands.sendPort);
  commands.listen((message) {
    if (message is! _ConvertRequest) return;
    try {
      mainPort.send(_convertFrame(message));
    } catch (error, stackTrace) {
      mainPort.send(
        _Failed(id: message.id, error: '$error', stack: '$stackTrace'),
      );
    }
  });
}

/// Converts one frame inside the background isolate.
_Converted _convertFrame(_ConvertRequest request) {
  final bytes = request.data.materialize().asUint8List();
  final planes = <RawPlane>[];
  var offset = 0;
  for (var i = 0; i < request.planeLengths.length; i++) {
    final length = request.planeLengths[i];
    planes.add(
      RawPlane(
        bytes: Uint8List.sublistView(bytes, offset, offset + length),
        bytesPerRow: request.bytesPerRow[i],
        bytesPerPixel: request.bytesPerPixel[i],
      ),
    );
    offset += length;
  }
  final frame = RawFrame(
    width: request.width,
    height: request.height,
    format: request.format,
    planes: planes,
  );
  final conversion = request.converter.toConverter().convert(
    frame,
    rotationDegrees: request.rotationDegrees,
    mirror: request.mirror,
  );
  return _Converted(
    id: request.id,
    pixels: TransferableTypedData.fromList([conversion.pixels]),
    width: conversion.width,
    height: conversion.height,
    meanLuma: conversion.meanLuma,
    sceneLuma: conversion.sceneLuma,
    colorfulness: conversion.colorfulness,
  );
}

/// The request the service sends to the background isolate.
///
/// The planes travel in one transferable buffer, so the message itself does
/// not copy them again.
class _ConvertRequest {
  const _ConvertRequest({
    required this.id,
    required this.width,
    required this.height,
    required this.format,
    required this.data,
    required this.planeLengths,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.rotationDegrees,
    required this.mirror,
    required this.converter,
  });

  final int id;
  final int width;
  final int height;
  final FrameFormat format;
  final TransferableTypedData data;
  final List<int> planeLengths;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final int rotationDegrees;
  final bool mirror;

  /// The settings of the converter, so the isolate uses the same ones as the
  /// service and not the defaults.
  final FrameConverterConfig converter;
}

/// The result the background isolate sends back.
class _Converted {
  const _Converted({
    required this.id,
    required this.pixels,
    required this.width,
    required this.height,
    required this.meanLuma,
    required this.sceneLuma,
    required this.colorfulness,
  });

  final int id;
  final TransferableTypedData pixels;
  final int width;
  final int height;
  final double meanLuma;
  final List<double>? sceneLuma;
  final SceneColorReading? colorfulness;
}

/// The failure of one conversion.
class _Failed {
  const _Failed({required this.id, required this.error, required this.stack});

  final int id;
  final String error;
  final String stack;
}
