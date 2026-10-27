import 'dart:math';

import '../clock.dart';
import 'capture_fingerprint.dart';
import 'signature_source.dart';
import 'signature_state.dart';

/// Synchronous shutter identity, independent of rendering or async acquisition.
class SignatureController {
  SignatureController({
    Random? random,
    this.clock = stopwatchClock,
    DateTime Function()? utcNow,
  }) : _random = random ?? Random.secure(),
       _utcNow = utcNow ?? DateTime.now;

  final Random _random;
  final Clock clock;
  final DateTime Function() _utcNow;
  PendingCaptureSignature? _pending;
  int _counter = 0;

  PendingCaptureSignature get _current =>
      _pending ??= PendingCaptureSignature(random: _random);
  double get seed => _current.seed;
  SignatureState get state => _current.signature;

  CaptureSignature freeze({
    required String styleId,
    int recipeVersion = 1,
    List<SignatureReading> readings = const [],
  }) {
    final pending = _current;
    _pending = null;
    try {
      return pending.consume(
        counter: ++_counter,
        utcMicros: _utcNow().toUtc().microsecondsSinceEpoch,
        monotonicMicros: clock(),
        styleId: styleId,
        recipeVersion: recipeVersion,
        readings: readings,
      );
    } finally {
      // Also discard if an injected clock throws before consume is entered.
      pending.discard();
    }
  }

  /// Call on pause/dispose. The next preview gets a new pending identity.
  void clear() {
    _pending?.discard();
    _pending = null;
  }
}
