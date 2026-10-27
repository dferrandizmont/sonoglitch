import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/smoothed_value.dart';

void main() {
  group('SmoothedValue', () {
    test('starts at the initial value', () {
      final smoother = SmoothedValue(initialValue: 0.25);
      expect(smoother.value, 0.25);
    });

    test('does not move without time between samples', () {
      final smoother = SmoothedValue();
      smoother.update(1, Duration.zero);
      expect(smoother.value, 0);
    });

    test('follows a rising signal with the attack constant', () {
      final smoother = SmoothedValue(
        attack: const Duration(milliseconds: 100),
        release: const Duration(milliseconds: 1000),
      );
      // After one attack constant the value is 1 - e^-1 of the way there.
      smoother.update(1, const Duration(milliseconds: 100));
      expect(smoother.value, closeTo(0.632, 0.001));
    });

    test('follows a falling signal with the release constant', () {
      final smoother = SmoothedValue(
        initialValue: 1,
        attack: const Duration(milliseconds: 1000),
        release: const Duration(milliseconds: 200),
      );
      smoother.update(0, const Duration(milliseconds: 200));
      // 1 - (1 - e^-1) of the way down.
      expect(smoother.value, closeTo(0.368, 0.001));
    });

    test('the attack is faster than the release', () {
      final smoother = SmoothedValue(
        attack: const Duration(milliseconds: 50),
        release: const Duration(milliseconds: 500),
      );
      final afterAttack = smoother.update(1, const Duration(milliseconds: 50));
      smoother.reset(1);
      final afterRelease = smoother.update(0, const Duration(milliseconds: 50));
      // The signal falls much faster with the attack than with the release.
      expect(1 - afterAttack, greaterThan(1 - afterRelease));
    });

    test('keeps moving towards the target', () {
      final smoother = SmoothedValue();
      final first = smoother.update(0.5, const Duration(milliseconds: 100));
      final second = smoother.update(0.5, const Duration(milliseconds: 100));
      expect(second, greaterThan(first));
      expect(second, lessThanOrEqualTo(0.5));
    });

    test('rejects a time constant of zero', () {
      expect(() => SmoothedValue(attack: Duration.zero), throwsArgumentError);
      expect(() => SmoothedValue(release: Duration.zero), throwsArgumentError);
    });
  });
}
