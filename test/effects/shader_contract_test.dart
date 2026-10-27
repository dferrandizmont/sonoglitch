import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/ambient/signature/signature_state.dart';
import 'package:sonoglitch/effects/effect_renderer.dart';
import 'package:sonoglitch/effects/style_definition.dart';

import 'effect_renderer_test.dart' show difference, pixels, testImage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all shaders and Dart setters use the twenty-eight-float contract', () {
    const declarations = [
      'vec2 uSize',
      'float uNoise',
      'float uLight',
      'float uMotion',
      'float uTime',
      'vec2 uMotionDir',
      'vec2 uUvScale',
      'vec2 uUvOffset',
      'float uBass',
      'float uMid',
      'float uTreble',
      'float uSeed',
      'vec4 uFingerprint',
      'vec4 uMood',
      'vec4 uSign',
      'sampler2D uImage',
    ];
    final manifest = File('pubspec.yaml').readAsStringSync();
    final files = Directory('shaders')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.frag'));
    expect(files.length, kRegisteredStyles.length);
    for (final file in files) {
      expect(
        RegExp(r'uniform\s+(\w+\s+\w+)\s*;')
            .allMatches(file.readAsStringSync())
            .map((match) => match[1]),
        declarations,
        reason: file.path,
      );
    }
    for (final style in kRegisteredStyles) {
      expect(
        RegExp(RegExp.escape('- ${style.shaderAsset}')).allMatches(manifest),
        hasLength(1),
      );
    }
    // The pure array is the same array paint writes, in order, every frame.
    final uniforms = EffectRenderer.uniformValues(
      size: const Size(200, 100),
      imageSize: const Size(200, 100),
      ambient: const AmbientState(
        noise: 0.1,
        light: 0.2,
        motion: 0.3,
        motionDirX: 0,
        motionDirY: 1,
        bass: 0.4,
        mid: 0.5,
        treble: 0.6,
        seed: 0.7,
        signature: SignatureState(x: 0.125, y: 0.25, z: 0.5, w: 0.75),
      ),
      time: 12,
    );
    expect(uniforms, [
      200,
      100,
      0.1,
      0.2,
      0.3,
      12,
      0,
      1,
      1,
      1,
      0,
      0,
      0.4,
      0.5,
      0.6,
      0.7,
      0.125,
      0.25,
      0.5,
      0.75,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
    ]);
    expect(uniforms, hasLength(28));
    final dart = File('lib/effects/effect_renderer.dart').readAsStringSync();
    expect(dart, contains('_shader.setFloat(index, uniforms[index])'));
    expect(dart, contains('setImageSampler(0, image'));
    expect(manifest, isNot(contains('- shaders/signature_common.glsl')));
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        contains('#include "signature_common.glsl"'),
      );
    }
  });

  test(
    'fingerprint binding is neutral, finite, and overwritten in each array',
    () {
      List<double> values(AmbientState state) => EffectRenderer.uniformValues(
        size: const Size(200, 100),
        imageSize: const Size(200, 100),
        ambient: state,
        time: double.nan,
      );
      expect(values(AmbientState.calm).sublist(16, 20), [0, 0, 0, 0]);
      expect(
        values(
          const AmbientState(
            signature: SignatureState(
              x: double.nan,
              y: double.infinity,
              z: -1,
              w: 2,
            ),
          ),
        ).sublist(16, 20),
        [0, 0, 0, 1],
      );
      expect(
        values(AmbientState.calm).every((value) => value.isFinite),
        isTrue,
      );
    },
  );

  test(
    'the fingerprint and contextual lanes 16..27 are neutral and bounded',
    () {
      List<double> values(AmbientState state) => EffectRenderer.uniformValues(
        size: const Size(200, 100),
        imageSize: const Size(200, 100),
        ambient: state,
        time: 3,
      );
      // Neutral inputs end the array with the neutral mood and sign lanes.
      expect(values(AmbientState.calm).sublist(16, 28), [
        0, 0, 0, 0, // fingerprint
        0, 0, 1, 0, // mood
        1, 0, 0, 0, // sign
      ]);
      // The signed lanes clamp to -1..1 and the chroma allowance to 0.65..1.
      expect(
        values(
          const AmbientState(
            signature: SignatureState(
              warmth: 2,
              hue: -3,
              chromaAllowance: 0.1,
              tilt: 4,
              pulse: -5,
              reserved: 6,
            ),
          ),
        ).sublist(20),
        [1, -1, 0.65, 1, 1, 0, -1, 1],
      );
      // Nonfinite lanes fall back to their neutral value.
      expect(
        values(
          const AmbientState(
            signature: SignatureState(
              warmth: double.nan,
              hue: double.infinity,
              chromaAllowance: double.nan,
              tilt: double.negativeInfinity,
              axisX: double.nan,
              axisY: double.infinity,
              pulse: double.nan,
              reserved: double.infinity,
            ),
          ),
        ).sublist(20),
        [0, 0, 1, 0, 1, 0, 0, 0],
      );
      // The axis is a unit vector; a degenerate one means "no rotation".
      expect(
        values(
          const AmbientState(signature: SignatureState(axisX: 3, axisY: 4)),
        ).sublist(24, 26),
        [0.6, 0.8],
      );
      expect(
        values(
          const AmbientState(signature: SignatureState(axisX: 0, axisY: 0)),
        ).sublist(24, 26),
        [1, 0],
      );
      expect(
        values(AmbientState.calm).every((value) => value.isFinite),
        isTrue,
      );
    },
  );

  for (final style in kRegisteredStyles) {
    final legacy = const {
      'static',
      'tape',
      'phosphor',
      'ripple',
      'thermal',
      'prism',
    }.contains(style.id);
    final signatureRecipe = const {
      'static',
      'tape',
      'prism',
      'phosphor',
      'ripple',
      'thermal',
    }.contains(style.id);
    final contract = legacy
        ? 'preserve legacy pixels with neutral signature inputs'
        : 'render reproducibly';
    test('${style.id}: extended signals $contract', () async {
      final renderer = await EffectRenderer.load(style);
      addTearDown(renderer.dispose);
      // Resolve the new recipes' macroblocks and fine plate/print patterns.
      final source = legacy
          ? await testImage()
          : await testImage(width: 192, height: 144);
      addTearDown(source.dispose);
      final original = await pixels(source);
      // Migrated recipes apply only bounded microtexture at neutral controls;
      // recipes without a signature recipe keep the declaration-only contract.
      // Exact legacy renders for Phosphor, Ripple and Thermal are checked against
      // frozen GPU oracles in signature_sig2b_test.dart.
      final neutral = await renderer.renderToImage(
        source,
        ambient: AmbientState.calm,
        time: 3,
      );
      addTearDown(neutral.dispose);
      final declaredOnly = await renderer.renderToImage(
        source,
        ambient: const AmbientState(
          signature: SignatureState(x: 0.125, y: 0.25, z: 0.5, w: 0.75),
        ),
        time: 3,
      );
      addTearDown(declaredOnly.dispose);
      final declaredPixels = await pixels(declaredOnly);
      final neutralPixels = await pixels(neutral);
      if (signatureRecipe) {
        for (var i = 0; i < declaredPixels.length; i++) {
          expect(
            (declaredPixels[i] - neutralPixels[i]).abs(),
            lessThanOrEqualTo(1),
          );
        }
      } else {
        expect(declaredPixels, neutralPixels);
      }
      const states = [
        AmbientState(),
        AmbientState(noise: 1, light: 0, motion: 1),
        AmbientState(noise: 0.4, light: 1, motion: 0.3),
      ];
      for (final state in states) {
        final before = await renderer.renderToImage(
          source,
          ambient: state,
          time: 3,
        );
        addTearDown(before.dispose);
        final extended = AmbientState(
          noise: state.noise,
          light: state.light,
          motion: state.motion,
          bass: 0.25,
          mid: 0.5,
          treble: 1,
          seed: 0.75,
        );
        final after = await renderer.renderToImage(
          source,
          ambient: extended,
          time: 3,
        );
        addTearDown(after.dispose);
        final beforePixels = await pixels(before);
        final afterPixels = await pixels(after);
        if (legacy && !signatureRecipe) {
          // Recipes without a signature recipe retain the declaration-only comparison.
          expect(afterPixels, beforePixels);
        } else {
          // Migrated/new recipes consume bands and seed. Their dedicated
          // effect tests check diversity and recognizability independently.
          if (const {'static', 'tape', 'prism'}.contains(style.id) &&
              state == AmbientState.calm) {
            expect(afterPixels, beforePixels);
          }
          if (state == AmbientState.calm) {
            expect(difference(beforePixels, original), lessThanOrEqualTo(0.1));
          }
          final repeated = await renderer.renderToImage(
            source,
            ambient: extended,
            time: 3,
          );
          addTearDown(repeated.dispose);
          expect(await pixels(repeated), afterPixels);
        }
      }
    });
  }

  test('registry has twelve styles in design family order', () {
    expect(kRegisteredStyles.map((style) => style.id), [
      'static',
      'tape',
      'phosphor',
      'datamosh',
      'chladni',
      'ripple',
      'thermal',
      'risograph',
      'bleed',
      'mosaic',
      'prism',
      'kaleido',
    ]);
    expect(
      kRegisteredStyles.where((style) => style.isPlaceholder),
      hasLength(6),
    );
    expect(
      kRegisteredStyles.map((style) => style.family.index),
      orderedEquals(
        kRegisteredStyles.map((style) => style.family.index).toList()..sort(),
      ),
    );
  });
}
