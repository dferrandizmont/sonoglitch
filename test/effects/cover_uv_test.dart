import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/effects/cover_uv.dart';

void main() {
  test('wider image crops the horizontal axis centrally', () {
    final uv = coverUv(const Size(400, 200), const Size(100, 100));
    expect(uv.scale, const Offset(0.5, 1));
    expect(uv.offset, const Offset(0.25, 0));
  });

  test('taller image crops the vertical axis centrally', () {
    final uv = coverUv(const Size(200, 400), const Size(100, 100));
    expect(uv.scale, const Offset(1, 0.5));
    expect(uv.offset, const Offset(0, 0.25));
  });

  test('equal aspects preserve the full source', () {
    final uv = coverUv(const Size(400, 200), const Size(200, 100));
    expect(uv.scale, const Offset(1, 1));
    expect(uv.offset, Offset.zero);
  });

  test('cover transform is independent of resolution', () {
    expect(
      coverUv(const Size(400, 300), const Size(90, 160)),
      coverUv(const Size(4000, 3000), const Size(900, 1600)),
    );
  });
}
