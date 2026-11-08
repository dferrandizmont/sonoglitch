import 'dart:ui' as ui;

import '../../debug/debug_log.dart';
import '../../export/export_service.dart';
import 'capture_result.dart';
import 'result_cache.dart';

/// The small copy of the original photo that the screen compares with.
///
/// It is decoded once, while the screen is open, and it is released when the
/// screen is closed: a full size copy of the original would cost tens of
/// megabytes for a comparison. The crop follows the format that is on screen.
class OriginalComparison {
  OriginalComparison({
    required this.export,
    required this.log,
    required this.isMounted,
    required this.isClosing,
    required this.result,
    required this.originalKey,
    required this.notify,
  });

  final ExportService export;
  final DebugLog log;

  /// Whether the screen is still in the tree.
  final bool Function() isMounted;

  /// Whether the screen is closing.
  final bool Function() isClosing;

  /// The capture that is on screen.
  final CaptureResult Function() result;

  /// The key of the original copy, with the format of the moment.
  final ResultCacheKey Function() originalKey;

  /// Rebuilds the screen.
  final void Function() notify;

  /// The longest side of the copy of the original that is kept.
  static const int previewSide = 1024;

  /// The decoded copy of the original, without the effect.
  ui.Image? _decoded;

  /// The original, cropped like the picture that is on screen.
  ui.Image? _cropped;

  /// Whether the button asked for the original photo.
  bool _latched = false;

  /// Whether the picture is being held with a finger.
  bool _holding = false;

  int _requests = 0;

  /// Whether the original photo is the one that is shown.
  bool get showOriginal => _latched || _holding;

  /// The original photo, cropped like the picture that is on screen.
  ui.Image? get image => _cropped;

  /// The bytes of the small surfaces that are kept.
  int get retainedBytes =>
      (_decoded == null ? 0 : _decoded!.width * _decoded!.height * 4) +
      (_cropped == null ? 0 : _cropped!.width * _cropped!.height * 4);

  /// Shows or hides the original photo.
  void toggle() {
    _latched = !_latched;
    notify();
  }

  /// Tells the comparison whether the picture is held with a finger.
  void setHolding(bool holding) {
    _holding = holding;
    notify();
  }

  /// Releases the copies and forgets the latches.
  ///
  /// A crop that finishes late finds a newer request and disposes itself.
  void clear() {
    _requests++;
    _decoded?.dispose();
    _decoded = null;
    _cropped?.dispose();
    _cropped = null;
    _latched = false;
    _holding = false;
  }

  /// Decodes a small copy of the original and crops it with [key].
  Future<void> load(ResultCacheKey key) async {
    final capture = result();
    final source = capture.source;
    if (source == null) return;
    _latched = false;
    _holding = false;
    ui.Image? decoded;
    try {
      final longest = source.width > source.height
          ? source.width
          : source.height;
      final scale = longest > previewSide ? previewSide / longest : 1.0;
      final width = (source.width * scale).round().clamp(1, source.width);
      final height = (source.height * scale).round().clamp(1, source.height);
      decoded = await source.decode(width, height);
    } catch (error) {
      log.warning('result', 'the original photo could not be decoded: $error');
      return;
    }
    if (!isMounted() || isClosing() || !identical(capture, result())) {
      decoded.dispose();
      return;
    }
    _decoded = decoded;
    await crop(key);
  }

  /// Crops the copy of the original like the picture that is on screen.
  Future<void> crop(ResultCacheKey key) async {
    final request = ++_requests;
    final original = _decoded;
    if (original == null) return;
    final decoded = original.clone();
    ui.Image? cropped;
    try {
      cropped = await export.crop(decoded, key.format);
    } catch (error) {
      log.warning('result', 'the original photo could not be cropped: $error');
      return;
    } finally {
      decoded.dispose();
    }
    if (!isMounted() ||
        isClosing() ||
        request != _requests ||
        !identical(key.capture, result())) {
      cropped.dispose();
      return;
    }
    _cropped?.dispose();
    _cropped = cropped;
    notify();
  }
}
