enum StyleFamily { analog, physical, print, optic }

/// A visual style: one fragment shader driven by the three ambient controls.
class StyleDefinition {
  const StyleDefinition({
    required this.id,
    required this.name,
    required this.shaderAsset,
    this.family = StyleFamily.analog,
    this.isPlaceholder = false,
  });

  final String id;
  final String name;
  final String shaderAsset;
  final StyleFamily family;

  /// Registered ahead of its visual recipe; currently passes the image through.
  final bool isPlaceholder;
}

/// Selectable free styles. Unfinished recipes stay in [kRegisteredStyles] only.
final List<StyleDefinition> kStyles = List.unmodifiable(
  kRegisteredStyles.where((style) => !style.isPlaceholder),
);

/// Development registry, including unfinished recipes and their shader assets.
const List<StyleDefinition> kRegisteredStyles = [
  StyleDefinition(
    id: 'static',
    name: 'Static',
    shaderAsset: 'shaders/static.frag',
    family: StyleFamily.analog,
  ),
  StyleDefinition(
    id: 'tape',
    name: 'Tape',
    shaderAsset: 'shaders/tape.frag',
    family: StyleFamily.analog,
  ),
  StyleDefinition(
    id: 'phosphor',
    name: 'Phosphor',
    shaderAsset: 'shaders/phosphor.frag',
    family: StyleFamily.analog,
  ),
  StyleDefinition(
    id: 'datamosh',
    name: 'Datamosh',
    shaderAsset: 'shaders/datamosh.frag',
    family: StyleFamily.analog,
    isPlaceholder: true,
  ),
  StyleDefinition(
    id: 'chladni',
    name: 'Chladni',
    shaderAsset: 'shaders/chladni.frag',
    family: StyleFamily.physical,
    isPlaceholder: true,
  ),
  StyleDefinition(
    id: 'ripple',
    name: 'Ripple',
    shaderAsset: 'shaders/ripple.frag',
    family: StyleFamily.physical,
  ),
  StyleDefinition(
    id: 'thermal',
    name: 'Thermal',
    shaderAsset: 'shaders/thermal.frag',
    family: StyleFamily.physical,
  ),
  StyleDefinition(
    id: 'risograph',
    name: 'Risograph',
    shaderAsset: 'shaders/risograph.frag',
    family: StyleFamily.print,
    isPlaceholder: true,
  ),
  StyleDefinition(
    id: 'bleed',
    name: 'Bleed',
    shaderAsset: 'shaders/bleed.frag',
    family: StyleFamily.print,
    isPlaceholder: true,
  ),
  StyleDefinition(
    id: 'mosaic',
    name: 'Mosaic',
    shaderAsset: 'shaders/mosaic.frag',
    family: StyleFamily.print,
    isPlaceholder: true,
  ),
  StyleDefinition(
    id: 'prism',
    name: 'Prism',
    shaderAsset: 'shaders/prism.frag',
    family: StyleFamily.optic,
  ),
  StyleDefinition(
    id: 'kaleido',
    name: 'Kaleido',
    shaderAsset: 'shaders/kaleido.frag',
    family: StyleFamily.optic,
    isPlaceholder: true,
  ),
];
