import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/app_config.dart';

void main() {
  group('the manual values of the build', () {
    test('are read as noise, light and movement', () {
      expect(AppConfig.parseManualValues('0.9,0.1,0'), [0.9, 0.1, 0.0]);
    });

    test('the spaces are ignored', () {
      expect(AppConfig.parseManualValues(' 0.9 , 0.1 , 0 '), [0.9, 0.1, 0.0]);
    });

    test('are clamped to the scale of the controls', () {
      expect(AppConfig.parseManualValues('2,-1,0.5'), [1.0, 0.0, 0.5]);
    });

    test('a build without them has no manual values', () {
      expect(AppConfig.parseManualValues(''), isNull);
      expect(AppConfig.manualValues, isNull);
      expect(AppConfig.manualMode, isFalse);
    });

    test('a broken list is ignored', () {
      expect(AppConfig.parseManualValues('0.9,0.1'), isNull);
      expect(AppConfig.parseManualValues('0.9,0.1,0,0.5'), isNull);
      expect(AppConfig.parseManualValues('loud,dark,still'), isNull);
      expect(AppConfig.parseManualValues('0.9,nan,0'), isNull);
    });
  });
}
