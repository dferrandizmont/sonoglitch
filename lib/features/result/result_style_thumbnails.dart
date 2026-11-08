import 'dart:async';
import 'dart:ui' as ui;

import '../../debug/debug_log.dart';
import '../../effects/style_definition.dart';
import 'capture_result.dart';
import 'result_cache.dart';
import 'result_style_stills.dart';

/// The styles of the strip, with the style of the capture first.
List<StyleDefinition> resultStyleOrder(String captureStyleId) {
  final first = kStyles.where((style) => style.id == captureStyleId);
  return [...first, ...kStyles.where((style) => style.id != captureStyleId)];
}

/// The small previews of the photo in every style, for the strip of styles.
///
/// They are drawn one at a time, from one small decode of the original, and
/// only while the main picture is not being composed, so they never delay it.
/// The previews live in a bounded [StyleThumbnailCache] and are released with
/// the screen.
class ResultStyleThumbnails {
  ResultStyleThumbnails({
    required this.stills,
    required this.log,
    required this.isMounted,
    required this.isClosing,
    required this.isBusy,
    required this.result,
    required this.notify,
  });

  final StyleStills stills;
  final DebugLog log;

  /// Whether the screen is still in the tree.
  final bool Function() isMounted;

  /// Whether the screen is closing.
  final bool Function() isClosing;

  /// Whether the main picture is being composed.
  final bool Function() isBusy;

  /// The capture that is on screen.
  final CaptureResult Function() result;

  /// Rebuilds the screen.
  final void Function() notify;

  /// The longest side of a preview, in pixels.
  static const int side = 320;

  final _cache = StyleThumbnailCache();
  int _generation = 0;
  Completer<void>? _wake;

  /// The preview of [styleId], null while it has not been drawn.
  ui.Image? imageFor(String styleId) => _cache.get(styleId);

  /// The bytes of the previews that are kept.
  int get retainedBytes => _cache.imageBytes;

  /// Starts drawing the previews of the capture that is on screen.
  void start() {
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  /// Tells the drawing that the main picture may have finished.
  void kick() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Forgets the previews and stops the drawing in flight.
  void clear() {
    _generation++;
    _cache.clear();
    kick();
  }

  Future<void> _run(int generation) async {
    final capture = result();
    final source = capture.source;
    if (source == null) return;
    bool stale() => !isMounted() || isClosing() || generation != _generation;
    // The main picture goes first: wait until it has been composed.
    Future<bool> idle() async {
      while (isBusy()) {
        final wake = _wake ??= Completer<void>();
        await wake.future;
        if (stale()) return false;
      }
      return !stale();
    }

    ui.Image? small;
    try {
      if (!await idle()) return;
      final longest = source.width > source.height
          ? source.width
          : source.height;
      final scale = longest > side ? side / longest : 1.0;
      final width = (source.width * scale).round().clamp(1, source.width);
      final height = (source.height * scale).round().clamp(1, source.height);
      small = await source.decode(width, height);
      if (stale()) return;
      for (final style in resultStyleOrder(capture.styleId)) {
        if (_cache.contains(style.id)) continue;
        if (!await idle()) return;
        final ui.Image image;
        try {
          image = await stills.render(
            style,
            small,
            ambient: capture.ambient,
            time: capture.time,
            maxSide: side,
          );
        } catch (error) {
          // One style that fails leaves an empty tile, not an empty strip.
          log.warning(
            'result',
            'the ${style.id} preview could not be drawn: $error',
          );
          continue;
        }
        if (stale()) {
          image.dispose();
          return;
        }
        _cache.put(style.id, image);
        notify();
      }
    } catch (error) {
      log.warning('result', 'the style previews could not be drawn: $error');
    } finally {
      small?.dispose();
    }
  }
}
