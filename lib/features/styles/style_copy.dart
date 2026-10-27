import '../../ambient/ambient_state.dart';
import '../../effects/style_definition.dart';
import '../../l10n/app_localizations.dart';
import 'smart_pick.dart';

/// The one-line description of a style, in the language of the app.
///
/// The registry of the styles stays free of translations: the copy of
/// every style is chosen here by its id. A style without a description of
/// its own is named by its own name.
String styleDescription(AppLocalizations l10n, String styleId) {
  return switch (styleId) {
    'static' => l10n.styleDescStatic,
    'tape' => l10n.styleDescTape,
    'phosphor' => l10n.styleDescPhosphor,
    'ripple' => l10n.styleDescRipple,
    'thermal' => l10n.styleDescThermal,
    'prism' => l10n.styleDescPrism,
    _ => styleName(styleId),
  };
}

/// The name of a style of the registry.
///
/// An id that is not in the registry is returned as it is, so the copy of
/// an unknown style is never empty.
String styleName(String styleId) {
  for (final style in kStyles) {
    if (style.id == styleId) return style.name;
  }
  return styleId;
}

/// The one-line reason that explains why a style fits the place.
String stylePickReason(AppLocalizations l10n, AmbientState state, String name) {
  return switch (classifyAmbience(state)) {
    StyleAmbience.calmBright => l10n.stylePickCalmBright(name),
    StyleAmbience.calmDark => l10n.stylePickCalmDark(name),
    StyleAmbience.loud => l10n.stylePickLoud(name),
    StyleAmbience.moving => l10n.stylePickMoving(name),
    StyleAmbience.mixed => l10n.stylePickMixed(name),
  };
}
