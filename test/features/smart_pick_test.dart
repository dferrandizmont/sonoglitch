import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/features/styles/smart_pick.dart';

StyleDefinition definition(String id) =>
    StyleDefinition(id: id, name: id, shaderAsset: 'unused');

void main() {
  const cases = [
    (AmbientState(noise: 0.1, light: 0.9), StyleAmbience.calmBright, 'prism'),
    (AmbientState(noise: 0.1, light: 0.1), StyleAmbience.calmDark, 'thermal'),
    (AmbientState(noise: 0.8, light: 0.9), StyleAmbience.loud, 'static'),
    (AmbientState(motion: 0.8), StyleAmbience.moving, 'datamosh'),
    (AmbientState(noise: 0.4), StyleAmbience.mixed, 'phosphor'),
  ];
  final registry = [
    for (final id in [
      'tape',
      'static',
      'prism',
      'thermal',
      'phosphor',
      'datamosh',
      'ripple',
    ])
      definition(id),
  ];

  for (final (state, ambience, id) in cases) {
    test('$ambience chooses $id independent of registry order', () {
      expect(classifyAmbience(state), ambience);
      final style = pickStyle(state, registry);
      expect(style.id, id);
      expect(style, same(registry.firstWhere((style) => style.id == id)));
      expect(pickStyle(state, registry.reversed.toList()).id, id);
    });

    test('$ambience falls back when preferred ids are missing', () {
      final fallback = definition('tape');
      expect(
        pickStyle(state, [definition('unknown'), fallback]),
        same(fallback),
      );
      final unknown = definition('unknown');
      expect(pickStyle(state, [unknown]), same(unknown));
    });
  }

  test('thresholds include their boundary and loudness wins over motion', () {
    expect(
      classifyAmbience(
        const AmbientState(noise: loudNoiseThreshold, motion: 1),
      ),
      StyleAmbience.loud,
    );
    expect(
      classifyAmbience(
        const AmbientState(
          noise: loudNoiseThreshold - 0.001,
          motion: movingMotionThreshold,
        ),
      ),
      StyleAmbience.moving,
    );
    expect(
      classifyAmbience(
        const AmbientState(
          noise: calmNoiseThreshold,
          motion: calmMotionThreshold,
          light: brightLightThreshold,
        ),
      ),
      StyleAmbience.calmBright,
    );
    expect(
      classifyAmbience(const AmbientState(light: darkLightThreshold)),
      StyleAmbience.calmDark,
    );
    expect(
      classifyAmbience(const AmbientState(light: darkLightThreshold + 0.001)),
      StyleAmbience.mixed,
    );
    expect(
      classifyAmbience(const AmbientState(light: brightLightThreshold - 0.001)),
      StyleAmbience.mixed,
    );
    expect(
      classifyAmbience(
        const AmbientState(noise: calmNoiseThreshold + 0.001, light: 1),
      ),
      StyleAmbience.mixed,
    );
    expect(
      classifyAmbience(
        const AmbientState(motion: calmMotionThreshold + 0.001, light: 1),
      ),
      StyleAmbience.mixed,
    );
  });

  test('loud falls back to ripple before tape', () {
    expect(
      pickStyle(const AmbientState(noise: 1), [
        definition('tape'),
        definition('ripple'),
      ]).id,
      'ripple',
    );
  });

  test(
    'production movement falls back to Tape while Datamosh is unfinished',
    () {
      expect(
        kRegisteredStyles
            .singleWhere((style) => style.id == 'datamosh')
            .isPlaceholder,
        isTrue,
      );
      expect(
        pickStyle(const AmbientState(noise: 0, motion: 1), kStyles).id,
        'tape',
      );
    },
  );

  test('raw readings do not override the normalized signals', () {
    expect(
      pickStyle(
        const AmbientState(
          noise: 0,
          light: 1,
          motion: 0,
          rawDb: 120,
          rawLux: 0,
          rawAccel: 100,
        ),
        registry,
      ).id,
      'prism',
    );
  });

  test('empty registry fails explicitly', () {
    expect(() => pickStyle(AmbientState.calm, []), throwsArgumentError);
  });
}
