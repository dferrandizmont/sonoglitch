import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/context_sensors.dart';
import 'package:sonoglitch/export/export_context.dart';
import 'package:sonoglitch/export/export_layout.dart';

void main() {
  test(
    'context has only available items, units, local time and numeric heading',
    () {
      expect(contextItems(null), isEmpty);
      expect(contextItems(const ExportContext()), isEmpty);
      final context = ExportContext(
        dateTime: DateTime(2026, 10, 26, 21, 32),
        heading: 42,
        pressure: 1013.2,
      );
      expect(contextItems(context).map((i) => i.text), [
        '2026-10-26 21:32',
        '042°',
        '1013 hPa',
      ]);
      expect(
        contextItems(const ExportContext(pressure: 1000)).single.kind,
        ContextItemKind.pressure,
      );
      expect(
        contextItems(const ExportContext(heading: 359.9)).single.text,
        '000°',
      );
      expect(
        contextItems(
          const ExportContext(heading: double.nan, pressure: double.infinity),
        ),
        isEmpty,
      );
      expect(const ExportContext(pressure: 0).hasItems, isFalse);
    },
  );
  test('northern phases are bounded, mirrored, and have the expected illuminated side', () {
    const center = Offset(100, 100);
    const r = 20.0;
    final waxing = moonPhasePath(center, r, synodicMonth / 4);
    final waning = moonPhasePath(center, r, 3 * synodicMonth / 4);
    expect(waxing.contains(center + const Offset(10, 0)), isTrue);
    expect(waxing.contains(center - const Offset(10, 0)), isFalse);
    expect(waning.contains(center - const Offset(10, 0)), isTrue);
    expect(waning.contains(center + const Offset(10, 0)), isFalse);
    final full = moonPhasePath(center, r, synodicMonth / 2);
    expect(full.contains(center), isTrue);
    expect(moonPhasePath(center, r, 0).contains(center), isFalse);
    for (final path in [waxing, waning, full]) {
      expect(path.getBounds().left, greaterThanOrEqualTo(80));
      expect(path.getBounds().right, lessThanOrEqualTo(120));
      expect(path.getBounds().top, 80);
      expect(path.getBounds().bottom, 120);
    }
  });
}
