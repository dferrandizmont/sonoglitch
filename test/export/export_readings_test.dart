import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_readings.dart';

void main() {
  test('missing, refused and silent instruments leave no slots', () {
    for (final db in [null, 0.0, -1.0, double.nan, double.infinity]) {
      expect(
        readingsOf(ExportLayoutValues(styleName: '', noiseDb: db)),
        isEmpty,
      );
    }
    expect(readingsOf(null), isEmpty);
  });
  test(
    'present zero levels keep their numbers, order and distinct palettes',
    () {
      final readings = readingsOf(
        const ExportLayoutValues(
          styleName: '',
          noiseDb: 28.4,
          lux: 0,
          accel: 0,
          light: 0,
        ),
      );
      expect(readings.map((r) => r.label), ['dB', 'lx', 'm/s²']);
      expect(readings.map((r) => r.value), ['28', '0.0', '0.00']);
      expect(readings.map((r) => r.level), [0, 0, 0]);
      expect(readings.map((r) => r.dark).toSet(), hasLength(3));
      expect(readings.every((r) => r.dark != r.paper), isTrue);
      expect(
        readingsOf(const ExportLayoutValues(styleName: '', accel: 10.25))
            .single
            .value,
        '10.3',
      );
    },
  );
  test('lux formatting and finite clamped scales', () {
    expect([0.0, 9.25, 10.0, 9999.0, 12400.0].map(formatLux), [
      '0.0',
      '9.3',
      '10',
      '9999',
      '12.4k',
    ]);
    expect([-1.0, 0.0, 0.5, 2.0, double.nan].map(exportLevel), [
      0,
      0,
      .5,
      1,
      0,
    ]);
    expect(
      hasExportReadings(
        const ExportLayoutValues(styleName: '', spectrumAvailable: true),
      ),
      isTrue,
    );
  });
}
