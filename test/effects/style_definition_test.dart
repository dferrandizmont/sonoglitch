import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/effects/style_definition.dart';

void main() {
  test('styles have unique ids, names and existing shader assets', () {
    expect(kRegisteredStyles.map((style) => style.id).toSet(), {
      'static',
      'tape',
      'prism',
      'phosphor',
      'ripple',
      'thermal',
      // Six future recipes are registered now as neutral placeholders.
      'datamosh',
      'chladni',
      'risograph',
      'bleed',
      'kaleido',
      'mosaic',
    });
    expect(
      kRegisteredStyles.map((style) => style.id).toSet().length,
      kRegisteredStyles.length,
    );
    for (final style in kRegisteredStyles) {
      expect(style.name.trim(), isNotEmpty);
      expect(style.shaderAsset, startsWith('shaders/'));
      expect(File(style.shaderAsset).existsSync(), isTrue);
    }
  });

  test('only implemented styles are selectable', () {
    expect(kStyles.map((style) => style.id), [
      'static',
      'tape',
      'phosphor',
      'ripple',
      'thermal',
      'prism',
    ]);
    expect(kStyles.any((style) => style.isPlaceholder), isFalse);
    expect(kStyles, kRegisteredStyles.where((style) => !style.isPlaceholder));
  });
}
