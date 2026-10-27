import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads a file of the translations.
Map<String, dynamic> readArb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The keys of a translation file, without the ones that describe them.
Set<String> keysOf(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// The placeholders of a key, as they are described in the file.
Set<String> placeholdersOf(Map<String, dynamic> arb, String key) {
  final description = arb['@$key'];
  if (description is! Map<String, dynamic>) return <String>{};
  final placeholders = description['placeholders'];
  if (placeholders is! Map<String, dynamic>) return <String>{};
  return placeholders.keys.toSet();
}

/// The placeholders that a message uses.
Set<String> usedPlaceholders(String message) =>
    RegExp(r'\{(\w+)\}')
        .allMatches(message)
        .map((match) => match.group(1)!)
        .toSet();

void main() {
  late Map<String, dynamic> english;
  late Map<String, dynamic> spanish;

  setUpAll(() {
    english = readArb('app_en.arb');
    spanish = readArb('app_es.arb');
  });

  test('the two files have the same keys', () {
    final englishKeys = keysOf(english);
    final spanishKeys = keysOf(spanish);
    expect(spanishKeys, englishKeys);

    // Every key of one file has to exist in the other one, with a message
    // that says which key is missing.
    for (final key in englishKeys) {
      expect(
        spanish.containsKey(key),
        isTrue,
        reason: 'the spanish file is missing the key $key',
      );
    }
    for (final key in spanishKeys) {
      expect(
        english.containsKey(key),
        isTrue,
        reason: 'the english file is missing the key $key',
      );
    }
  });

  test('the moment mode is translated in both languages', () {
    const keys = [
      'viewfinderMomentTooltip',
      'viewfinderMomentArmed',
      'settingsMomentKeepArmedTitle',
      'settingsMomentKeepArmedSubtitle',
    ];
    for (final arb in [english, spanish]) {
      for (final key in keys) {
        expect(arb[key], isA<String>(), reason: key);
        expect((arb[key]! as String).isNotEmpty, isTrue, reason: key);
      }
    }
    expect(
      english['viewfinderMomentArmed'],
      'Waiting for a loud sound or a sudden move',
    );
    expect(
      spanish['viewfinderMomentArmed'],
      'Esperando un ruido fuerte o un movimiento brusco',
    );
    expect(english['settingsMomentKeepArmedTitle'], 'Auto shot: keep waiting');
    expect(
      spanish['settingsMomentKeepArmedTitle'],
      'Disparo auto: seguir esperando',
    );
    for (final arb in [english, spanish]) {
      for (final removed in [
        'viewfinderMomentCaptured',
        'viewfinderMomentCount',
        'viewfinderLegendTooltip',
        'viewfinderLegendSheetTitle',
        'viewfinderStylesTooltip',
        'viewfinderTipMessage',
        'viewfinderDiceTooltip',
        'viewfinderSmartPickTooltip',
      ]) {
        expect(arb.containsKey(removed), isFalse, reason: removed);
      }
    }
  });

  test('the strings of the redesign exist in both languages', () {
    const keys = [
      'viewfinderStyleButton',
      'viewfinderPrevStyle',
      'viewfinderNextStyle',
      'viewfinderMetersTooltip',
      'viewfinderHint',
      'helpTitle',
      'helpOpen',
      'helpSwipe',
      'helpAutoShot',
      'styleSheetRandom',
      'styleSheetMatch',
      'styleDescStatic',
      'styleDescTape',
      'styleDescPhosphor',
      'styleDescRipple',
      'styleDescThermal',
      'styleDescPrism',
      'resultLayoutHintFull',
      'resultLayoutHintSoundStrip',
      'resultLayoutHintPoster',
    ];
    for (final arb in [english, spanish]) {
      for (final key in keys) {
        expect(arb[key], isA<String>(), reason: key);
        expect((arb[key]! as String).isNotEmpty, isTrue, reason: key);
      }
    }
    expect(english['helpTitle'], 'How it works');
    expect(spanish['helpTitle'], 'Cómo funciona');
    expect(english['styleSheetMatch'], 'Match this place');
    expect(spanish['styleSheetMatch'], 'Según el lugar');
    expect(english['viewfinderStyleButton'], contains('{name}'));
    expect(spanish['viewfinderStyleButton'], contains('{name}'));
  });

  test('intensity labels and one-line explanation exist in both languages', () {
    for (final arb in [english, spanish]) {
      for (final key in [
        'settingsIntensityTitle',
        'settingsIntensitySubtitle',
        'intensitySubtle',
        'intensityNormal',
        'intensityExtreme',
      ]) {
        expect(arb[key], isA<String>());
        expect(arb[key], isNot(contains('\n')));
      }
    }
    expect(english['viewfinderHint'], contains('Swipe to change style'));
    expect(
      spanish['viewfinderHint'],
      contains('Desliza para cambiar de estilo'),
    );
  });

  test('no key is empty', () {
    for (final key in keysOf(english)) {
      expect(english[key], isNotNull, reason: key);
      expect((english[key]! as String).isNotEmpty, isTrue, reason: key);
      expect(spanish[key], isNotNull, reason: key);
      expect((spanish[key]! as String).isNotEmpty, isTrue, reason: key);
    }
  });

  test('the formats, the layouts and the file type are in both languages', () {
    const keys = [
      'resultFormatOriginal',
      'resultFormatSquare',
      'resultFormatPortrait',
      'resultFormatStory',
      'resultLayoutLabel',
      'resultLayoutFull',
      'resultLayoutSoundStrip',
      'resultLayoutPoster',
      'resultShowProcessedTooltip',
      'resultCompareTooltip',
      'settingsFileTypeTitle',
      'settingsFileTypeSubtitle',
      'fileTypePng',
      'fileTypeJpeg',
    ];
    for (final arb in [english, spanish]) {
      for (final key in keys) {
        expect(arb[key], isA<String>(), reason: key);
        expect((arb[key]! as String).isNotEmpty, isTrue, reason: key);
      }
    }
    expect(english['resultFormatStory'], 'Story 9:16');
    expect(spanish['resultFormatStory'], 'Historia 9:16');
    expect(english['resultLayoutSoundStrip'], 'Sound strip');
    expect(spanish['resultLayoutSoundStrip'], 'Banda de sonido');
    expect(english['fileTypePng'], 'PNG (lossless)');
    expect(spanish['fileTypePng'], 'PNG (sin pérdidas)');
    expect(english['fileTypeJpeg'], 'JPEG (high quality)');
    expect(spanish['fileTypeJpeg'], 'JPEG (alta calidad)');
  });

  test('the placeholders of the messages are the ones that are described', () {
    // The descriptions of the placeholders live in the english file, which
    // is the template of the translations.
    for (final key in keysOf(english)) {
      final placeholders = placeholdersOf(english, key);
      expect(
        usedPlaceholders(english[key]! as String),
        placeholders,
        reason: key,
      );
      expect(
        usedPlaceholders(spanish[key]! as String),
        placeholders,
        reason: key,
      );
    }
  });

  test('no placeholder is missing in either file', () {
    for (final key in keysOf(english)) {
      final placeholders = placeholdersOf(english, key);
      if (placeholders.isEmpty) continue;
      for (final placeholder in placeholders) {
        expect(
          english[key]! as String,
          contains('{$placeholder}'),
          reason: key,
        );
        expect(
          spanish[key]! as String,
          contains('{$placeholder}'),
          reason: key,
        );
      }
    }
  });
}
