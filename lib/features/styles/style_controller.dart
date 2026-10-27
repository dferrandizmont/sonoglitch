import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../ambient/ambient_state.dart';
import '../../debug/debug_log.dart';
import '../../effects/effect_renderer.dart';
import '../../effects/style_definition.dart';

/// Loads the renderer of a style.
///
/// It is a dependency so the tests can decide when a renderer is ready.
typedef RendererLoader = Future<EffectRenderer> Function(StyleDefinition style);

/// Holds the style that is selected and the renderer that draws it.
///
/// When a new style is chosen the previous renderer stays alive until the new
/// one is ready, so the preview never goes black. The renderer that is
/// replaced is released once the frame that draws the new one is painted.
class StyleController extends ChangeNotifier {
  StyleController({
    required this.log,
    List<StyleDefinition>? styles,
    RendererLoader? loader,
    Random? random,
  }) : _styles = styles ?? kStyles,
       _style = (styles ?? kStyles).first,
       _loader = loader ?? EffectRenderer.load,
       _random = random ?? Random();

  /// Where the changes are reported.
  final DebugLog log;

  /// How the renderers are loaded.
  final RendererLoader _loader;
  final Random _random;

  final List<StyleDefinition> _styles;
  StyleDefinition _style;
  EffectRenderer? _renderer;
  bool _loading = false;
  int _loadGeneration = 0;
  bool _disposed = false;

  /// The renderers that were replaced and are waiting to be released.
  final List<EffectRenderer> _retired = <EffectRenderer>[];

  /// Every style of the registry.
  List<StyleDefinition> get styles => List.unmodifiable(_styles);

  /// The selected style.
  StyleDefinition get style => _style;

  /// The renderer of the selected style, null while the first one loads.
  EffectRenderer? get renderer => _renderer;

  /// Whether a new renderer is being loaded.
  bool get isLoading => _loading;

  /// Draws the still of a capture with the renderer of the selected style.
  ///
  /// [time] is the time of the animation, in seconds, so the still shows the
  /// same frame of the animation that the preview was showing.
  ///
  /// The returned image belongs to the caller, who has to dispose it.
  Future<ui.Image> renderStill(
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    int maxSide = 2048,
  }) async {
    final renderer = _renderer;
    if (renderer == null) {
      throw StateError('There is no style loaded');
    }
    return renderer.renderToImage(
      source,
      ambient: ambient,
      time: time,
      maxSide: maxSide,
    );
  }

  /// Loads the renderer of the selected style.
  Future<void> load() async {
    if (_renderer != null) return;
    await _load(_style);
  }

  /// Selects [style] and loads its renderer.
  ///
  /// The renderer of the previous style keeps drawing until the new one is
  /// ready.
  Future<void> select(StyleDefinition style) async {
    if (style.id == _style.id && _renderer != null) return;
    _style = style;
    _loading = true;
    notifyListeners();
    log.info('style', 'selected ${style.id}');
    await _load(style);
  }

  /// Moves through registry order, wrapping in either direction.
  Future<void> selectRelative(int offset) {
    final index = _styles.indexWhere((style) => style.id == _style.id);
    return select(_styles[(index + offset) % _styles.length]);
  }

  /// Uniformly chooses another style, with no retry loop or repeated id.
  Future<void> selectRandom() async {
    final candidates = _styles.where((style) => style.id != _style.id).toList();
    if (candidates.isEmpty) return;
    await select(candidates[_random.nextInt(candidates.length)]);
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _releaseRetired();
    _renderer?.dispose();
    _renderer = null;
    super.dispose();
  }

  Future<void> _load(StyleDefinition style) async {
    final generation = ++_loadGeneration;
    try {
      final renderer = await _loader(style);
      if (_disposed || generation != _loadGeneration) {
        // Another style was chosen while this one was loading: this renderer
        // will never be drawn, so it is released right away.
        renderer.dispose();
        return;
      }
      final previous = _renderer;
      _renderer = renderer;
      notifyListeners();
      if (previous != null) {
        // The frame that is on screen may still be drawn with the old
        // renderer, so it is released after the next frame is painted.
        _retire(previous);
      }
    } catch (error, stackTrace) {
      log.error(
        'style',
        'the style ${style.id} did not load',
        error,
        stackTrace,
      );
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Keeps [renderer] until the next frame is painted.
  void _retire(EffectRenderer renderer) {
    _retired.add(renderer);
    final binding = _binding;
    if (binding == null) {
      // Without a binding nothing can be painted, so the renderer can go
      // right away.
      _releaseRetired();
      return;
    }
    binding.addPostFrameCallback((_) => _releaseRetired());
    // The frame that is on screen may still be drawn with the old renderer,
    // so the release waits for the next one.
    binding.scheduleFrame();
  }

  /// Releases the renderers that are not drawn any more.
  void _releaseRetired() {
    for (final renderer in _retired) {
      renderer.dispose();
    }
    _retired.clear();
  }

  /// The binding of the framework, null when the code runs without one.
  static SchedulerBinding? get _binding {
    try {
      return SchedulerBinding.instance;
    } catch (_) {
      // A plain unit test has no binding, and nothing can be painted.
      return null;
    }
  }
}
