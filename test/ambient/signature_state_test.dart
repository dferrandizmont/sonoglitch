import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';

void main() {
  test('the neutral state carries the neutral contextual lanes', () {
    const state = SignatureState.neutral;
    expect((state.x, state.y, state.z, state.w), (0, 0, 0, 0));
    expect(
      (
        state.warmth,
        state.hue,
        state.chromaAllowance,
        state.tilt,
        state.axisX,
        state.axisY,
        state.pulse,
        state.reserved,
      ),
      (0, 0, 1, 0, 1, 0, 0, 0),
    );
  });

  test('copyWith replaces only the given lanes', () {
    const state = SignatureState(x: 0.1, y: 0.2, z: 0.3, w: 0.4, warmth: 0.5);
    final copy = state.copyWith(hue: -0.25);
    expect(copy.hue, -0.25);
    expect(copy.warmth, 0.5);
    expect((copy.x, copy.y, copy.z, copy.w), (0.1, 0.2, 0.3, 0.4));
    expect(state.hue, 0, reason: 'the original state is immutable');
  });

  test('withMood merges the mood and keeps the capture fingerprint', () {
    const state = SignatureState(x: 0.1, y: 0.2, z: 0.3, w: 0.4);
    final merged = state.withMood(warmth: 0.5, pulse: -0.5);
    expect((merged.x, merged.y, merged.z, merged.w), (0.1, 0.2, 0.3, 0.4));
    expect(merged.warmth, 0.5);
    expect(merged.pulse, -0.5);
    // The lanes that were not named keep their neutral value.
    expect(merged.chromaAllowance, 1);
    expect(merged.axisX, 1);
    expect(merged.axisY, 0);
    expect(merged.tilt, 0);
    expect(merged.reserved, 0);
  });
}
