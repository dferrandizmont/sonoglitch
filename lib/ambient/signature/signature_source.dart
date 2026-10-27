import 'dart:typed_data';

/// Ephemeral low mantissa byte with explicit presence and source age.
/// Never serialize or log this material. Missing and measured zero differ.
class SignatureReading {
  const SignatureReading({this.lowByte, this.ageMicros});

  final int? lowByte;
  final int? ageMicros;
  bool get present => lowByte != null && ageMicros != null;
  bool get fresh => present && ageMicros! >= 0 && ageMicros! <= 1500000;
}

/// Observes existing scalar/axis events; never opens a sensor subscription.
/// Holds only the last float32 mantissa byte, not full sensor readings.
class SignatureSource {
  SignatureSource(int width) : _bytes = List<int?>.filled(width, null);

  final List<int?> _bytes;
  int? _time;

  void update(List<double> values, int monotonicMicros) {
    if (values.length != _bytes.length) throw ArgumentError('Invalid width');
    final bits = ByteData(4);
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      bits.setFloat32(0, value, Endian.big);
      _bytes[i] = value.isFinite && bits.getFloat32(0, Endian.big).isFinite
          ? bits.getUint32(0, Endian.big) & 255
          : null;
    }
    _time = monotonicMicros;
    bits.setUint32(0, 0);
  }

  List<SignatureReading> readings(int now) => [
    for (final byte in _bytes)
      SignatureReading(
        lowByte: byte,
        ageMicros: _time == null ? null : now - _time!,
      ),
  ];

  void clear() {
    _bytes.fillRange(0, _bytes.length, null);
    _time = null;
  }
}
