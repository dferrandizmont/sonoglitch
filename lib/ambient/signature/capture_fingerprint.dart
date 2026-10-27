import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'signature_source.dart';
import 'signature_state.dart';

/// One pending photo owns a fresh 256-bit key. Its macro pattern stays stable
/// until consumed. Deterministic Random instances are for tests only.
class PendingCaptureSignature {
  PendingCaptureSignature({Random? random}) {
    final source = random ?? Random.secure();
    _nonce = Uint8List.fromList(List.generate(32, (_) => source.nextInt(256)));
    final pattern = _mac('sonoglitch/pattern/v1');
    seed = _fraction(pattern, 0);
    pattern.fillRange(0, pattern.length, 0);
    final preview = _mac('sonoglitch/preview-micro/v1');
    signature = _fingerprint(preview);
    preview.fillRange(0, preview.length, 0);
  }

  late final Uint8List _nonce;
  late final double seed;
  late final SignatureState signature;
  bool _consumed = false;

  /// Consumes and clears the key exactly once, even on derivation failure.
  CaptureSignature consume({
    required int counter,
    required int utcMicros,
    required int monotonicMicros,
    required String styleId,
    int recipeVersion = 1,
    List<SignatureReading> readings = const [],
  }) {
    if (_consumed) throw StateError('Pending signature already consumed');
    _consumed = true;
    Uint8List? message;
    Uint8List? digest;
    Uint8List? id;
    try {
      message = _encode(
        counter,
        utcMicros,
        monotonicMicros,
        styleId,
        recipeVersion,
        readings,
      );
      digest = _mac('sonoglitch/capture/v1', message);
      id = _mac('sonoglitch/photo-id/v1', digest);
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      // Stream bits through a small accumulator, including on Dart web (32-bit
      // bitwise operations); never pack all 40 ID bits into a bitwise integer.
      final characters = <int>[];
      var accumulator = 0;
      var bits = 0;
      for (var i = 0; i < 5; i++) {
        accumulator = (accumulator << 8) | id[i];
        bits += 8;
        while (bits >= 5) {
          bits -= 5;
          characters.add(alphabet.codeUnitAt((accumulator >> bits) & 31));
        }
        accumulator &= (1 << bits) - 1;
      }
      final photoId = String.fromCharCodes(characters);
      return CaptureSignature(
        seed: seed,
        signature: _fingerprint(digest),
        identity: CaptureIdentity(photoId),
      );
    } finally {
      discard();
      message?.fillRange(0, message.length, 0);
      digest?.fillRange(0, digest.length, 0);
      id?.fillRange(0, id.length, 0);
    }
  }

  void discard() {
    _consumed = true;
    _nonce.fillRange(0, _nonce.length, 0);
  }

  Uint8List _mac(String domain, [List<int> message = const []]) {
    final input = Uint8List.fromList([...utf8.encode(domain), ...message]);
    try {
      return Uint8List.fromList(Hmac(sha256, _nonce).convert(input).bytes);
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }
}

double _fraction(List<int> bytes, int start) =>
    ((bytes[start] << 16) | (bytes[start + 1] << 8) | bytes[start + 2]) /
    16777216;

SignatureState _fingerprint(List<int> bytes) => SignatureState(
  x: _fraction(bytes, 0),
  y: _fraction(bytes, 3),
  z: _fraction(bytes, 6),
  w: _fraction(bytes, 9),
);

/// v1, big-endian: u32 version; i64 counter/UTC/monotonic; u32 recipe;
/// u32 UTF-8 style length + bytes; u32 reading count; u32 presence/freshness
/// masks; then each reading's i64 age (-1 absent) and u8 low byte (0 if stale).
/// Explicit lengths and fixed channel order make the encoding unambiguous.
Uint8List _encode(
  int counter,
  int utc,
  int monotonic,
  String style,
  int recipe,
  List<SignatureReading> readings,
) {
  if (readings.length > 32) throw ArgumentError('At most 32 readings');
  final styleBytes = utf8.encode(style);
  final data = ByteData(48 + styleBytes.length + readings.length * 9);
  var offset = 0;
  void u32(int value) {
    data.setUint32(offset, value, Endian.big);
    offset += 4;
  }

  void i64(int value) {
    data.setInt64(offset, value, Endian.big);
    offset += 8;
  }

  u32(1);
  i64(counter);
  i64(utc);
  i64(monotonic);
  u32(recipe);
  u32(styleBytes.length);
  for (final byte in styleBytes) {
    data.setUint8(offset++, byte);
  }
  u32(readings.length);
  var presence = 0;
  var freshness = 0;
  for (var i = 0; i < readings.length; i++) {
    if (readings[i].present) presence |= 1 << i;
    if (readings[i].fresh) freshness |= 1 << i;
  }
  u32(presence);
  u32(freshness);
  for (final reading in readings) {
    i64(reading.present ? reading.ageMicros! : -1);
    data.setUint8(offset++, reading.fresh ? reading.lowByte! & 255 : 0);
  }
  return data.buffer.asUint8List();
}
