import 'dart:ui' as ui;

import '../../ambient/ambient_state.dart';
import '../../effects/effect_renderer.dart';
import '../../effects/style_definition.dart';

/// Draws the frozen values of a capture with the shader of any style.
///
/// The result screen uses it for the strip of styles and for the picture of a
/// style other than the one the photo was taken with. The uniforms are the
/// ones of the capture; only the shader changes.
abstract class StyleStills {
  /// Draws [source] with [style], at most [maxSide] pixels on the long side.
  ///
  /// The returned image belongs to the caller, who has to dispose it.
  Future<ui.Image> render(
    StyleDefinition style,
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    required int maxSide,
  });

  /// Releases the shaders that were loaded.
  void dispose();
}

/// The real implementation: one compiled shader per style, loaded on demand.
class ShaderStyleStills implements StyleStills {
  ShaderStyleStills({
    Future<EffectRenderer> Function(StyleDefinition style)? load,
  }) : _load = load ?? EffectRenderer.load;

  final Future<EffectRenderer> Function(StyleDefinition style) _load;
  final _renderers = <String, Future<EffectRenderer>>{};
  int _inFlight = 0;
  bool _disposed = false;

  @override
  Future<ui.Image> render(
    StyleDefinition style,
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    required int maxSide,
  }) async {
    if (_disposed) throw StateError('The style renderers were released');
    _inFlight++;
    try {
      final loading = _renderers.putIfAbsent(style.id, () => _load(style));
      final EffectRenderer renderer;
      try {
        renderer = await loading;
      } catch (_) {
        // Let a later request try to load the shader again.
        _renderers.remove(style.id);
        rethrow;
      }
      return await renderer.renderToImage(
        source,
        ambient: ambient,
        time: time,
        maxSide: maxSide,
      );
    } finally {
      _inFlight--;
      if (_disposed && _inFlight == 0) _release();
    }
  }

  /// Releases the shaders once the last render in flight has finished.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_inFlight == 0) _release();
  }

  void _release() {
    final loading = _renderers.values.toList();
    _renderers.clear();
    for (final future in loading) {
      future.then((renderer) => renderer.dispose(), onError: (Object _) {});
    }
  }
}
