import '../../ambient/ambient_state.dart';
import '../../effects/style_definition.dart';

const double loudNoiseThreshold = 0.65;
const double movingMotionThreshold = 0.5;
const double calmNoiseThreshold = 0.25;
const double calmMotionThreshold = 0.2;
const double brightLightThreshold = 0.65;
const double darkLightThreshold = 0.35;

/// Simple classes using only the three signals available today.
enum StyleAmbience { calmBright, calmDark, loud, moving, mixed }

/// Loudness takes priority over movement, then quiet, still scenes use light.
StyleAmbience classifyAmbience(AmbientState state) {
  if (state.noise >= loudNoiseThreshold) return StyleAmbience.loud;
  if (state.motion >= movingMotionThreshold) return StyleAmbience.moving;
  if (state.noise <= calmNoiseThreshold &&
      state.motion <= calmMotionThreshold) {
    if (state.light >= brightLightThreshold) return StyleAmbience.calmBright;
    if (state.light <= darkLightThreshold) return StyleAmbience.calmDark;
  }
  return StyleAmbience.mixed;
}

/// Picks an available style without changing the registry or using raw readings.
///
/// Preferences are ordered; an unfamiliar registry falls back to its first entry.
/// An empty registry cannot produce a style and throws [ArgumentError].
StyleDefinition pickStyle(AmbientState state, List<StyleDefinition> styles) {
  if (styles.isEmpty) {
    throw ArgumentError.value(styles, 'styles', 'Must not be empty');
  }
  final preferredIds = switch (classifyAmbience(state)) {
    StyleAmbience.loud => const ['static', 'ripple', 'tape'],
    StyleAmbience.moving => const ['datamosh', 'tape'],
    StyleAmbience.calmBright => const ['prism', 'phosphor', 'tape'],
    StyleAmbience.calmDark => const ['thermal', 'tape', 'phosphor'],
    StyleAmbience.mixed => const ['phosphor', 'tape'],
  };
  for (final id in preferredIds) {
    for (final style in styles) {
      if (style.id == id) return style;
    }
  }
  return styles.first;
}
