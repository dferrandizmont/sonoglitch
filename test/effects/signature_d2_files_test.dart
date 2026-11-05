import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'signature_d2a_cases.dart';
import 'signature_d2b_cases.dart';

// The delivery-2 matrices run one style per file so that they run in
// parallel. A style without its file would silently lose its coverage.
void main() {
  test('every delivery-2 style has its own test file', () {
    for (final (file, runner, ids) in [
      ('signature_d2a', 'signatureD2aTests', signatureD2aStyleIds),
      ('signature_d2b', 'signatureD2bTests', signatureD2bStyleIds),
    ]) {
      for (final id in ids) {
        final path = 'test/effects/${file}_${id}_test.dart';
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(
          File(path).readAsStringSync(),
          contains("main() => $runner('$id');"),
          reason: path,
        );
      }
    }
  });
}
