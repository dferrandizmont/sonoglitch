import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/capture_identity.dart';

void main() {
  test('the printed photo ID has two groups of four characters', () {
    expect(const CaptureIdentity('A3F917C2').displayId, 'A3F9-17C2');
  });

  test('an identity that is not eight characters is printed as it is', () {
    expect(const CaptureIdentity('A3F9').displayId, 'A3F9');
  });
}
