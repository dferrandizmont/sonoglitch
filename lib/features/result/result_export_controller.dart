import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// The public arguments name the sources; the fields stay private.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/material.dart';

import '../../ambient/signature/capture_identity.dart';
import '../../debug/capture_metrics.dart';
import '../../debug/debug_log.dart';
import '../../effects/style_definition.dart';
import '../../export/export_capture_timings.dart';
import '../../export/export_format.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
import '../../export/export_readings.dart';
import '../../export/export_service.dart';
import '../../export/photo_export.dart';
import '../../features/settings/app_settings.dart';
import 'capture_result.dart';
import 'result_cache.dart';
import 'result_capture_lease.dart';
import 'result_original.dart';
import 'result_style_stills.dart';
import 'result_style_thumbnails.dart';

/// What the export controller needs from the screen that shows it.
///
/// The messages and the origin of the share sheet depend on the widgets, so
/// the screen supplies them; everything else belongs to the controller.
abstract class ResultExportHost {
  /// Whether the screen is still in the tree.
  bool get mounted;

  /// Rebuilds the screen.
  void notify();

  /// The rectangle of the screen that a share sheet may point at.
  Rect? get shareOrigin;

  /// Shows a short message over the screen.
  void showSnack(String message);

  /// The message that confirms a save.
  String get savedMessage;

  /// The message that confirms a share.
  String get sharedMessage;

  /// The message that says the save failed.
  String get saveFailedMessage;

  /// The message that says the share failed.
  String get shareFailedMessage;
}

/// The state and the work of the result screen: style, format, layout and
/// readings selection, composition, cache, comparison with the original, save, share
/// and retake.
///
/// It holds no widgets, so the selections and the cache can be checked
/// without building the screen. The screen reads the values and calls the
/// actions, and rebuilds through [ResultExportHost].
class ResultExportController {
  ResultExportController({
    required CaptureResult result,
    required ExportService export,
    required AppSettings settings,
    required DebugLog log,
    required CaptureMetrics capture,
    required ResultExportHost host,
    PhotoExporter? photoExporter,
    StyleStills? styleStills,
    void Function()? onSourceReleased,
  }) : _result = result,
       _export = export,
       _settings = settings,
       _log = log,
       _captureMetrics = capture,
       _host = host,
       _photoExporter = photoExporter,
       _stills = styleStills ?? ShaderStyleStills(),
       _ownsStills = styleStills == null,
       _styleId = result.styleId,
       _onSourceReleased = onSourceReleased;

  final ExportService _export;
  final DebugLog _log;
  final CaptureMetrics _captureMetrics;
  final ResultExportHost _host;
  final PhotoExporter? _photoExporter;
  final StyleStills _stills;
  final bool _ownsStills;

  CaptureResult _result;
  AppSettings _settings;
  void Function()? _onSourceReleased;

  String _styleId;
  ExportFormat _format = ExportFormat.original;
  ExportLayout _layout = ExportLayout.full;
  ExportReadingsMode _readingsMode = ExportReadingsMode.full;
  ui.Image? _composed;
  File? _file;

  final _cache = ResultCache();
  ResultCacheKey? _composedKey;
  Rect _composedPhoto = const Rect.fromLTWH(0, 0, 1, 1);
  ResultCacheKey? _requestedKey;
  late ResultCaptureLease _capture;
  late final OriginalComparison _comparison;
  late final ResultStyleThumbnails _thumbnails;
  late ExportQuality _quality;
  late ExportQuality _settingsQuality;
  Future<void>? _sourceWork;
  bool _closing = false;
  ui.Image? _transitionImage;
  bool _busy = false;
  int? _processingPixels;
  bool _processing = false;
  int _requests = 0;

  /// The id of the style the photo is drawn with.
  ///
  /// It starts as the style of the capture and changes with [selectStyle].
  String get styleId => _styleId;

  /// Whether the photo can be drawn again with another style.
  ///
  /// A capture that only holds a finished picture cannot.
  bool get canChangeStyle => _result.source != null;

  /// The styles of the strip, with the style of the capture first.
  List<StyleDefinition> get styles => resultStyleOrder(_result.styleId);

  /// The small preview of the photo in [styleId], null while it is not drawn.
  ui.Image? styleThumbnail(String styleId) => _thumbnails.imageFor(styleId);

  /// The format of the export.
  ExportFormat get format => _format;

  /// The layout of the export.
  ExportLayout get layout => _layout;

  /// Which readings the strip and the poster print.
  ExportReadingsMode get readingsMode => _readingsMode;

  /// The preview of the composed picture.
  ui.Image? get composed => _composed;

  /// The encoded file of the composed picture.
  File? get file => _file;

  /// The bounds of the photo inside the composed preview.
  Rect get composedPhoto => _composedPhoto;

  /// Whether a composition is in flight.
  bool get processing => _processing;

  /// The pixels of the composition that are being drawn, when reported.
  int? get processingPixels => _processingPixels;

  /// Whether the platform is saving or sharing.
  bool get busy => _busy;

  /// Whether the screen is closing.
  bool get closing => _closing;

  /// Whether the picture of the selections is on screen.
  bool get ready =>
      !_closing &&
      !_busy &&
      !_processing &&
      _file != null &&
      _composedKey == _key();

  /// Whether the screen can accept another selection.
  bool get selectorsEnabled => !_busy && !_closing;

  /// Whether the original photo is the one that is shown.
  bool get showOriginal => _comparison.showOriginal;

  /// The original photo, cropped like the picture that is on screen.
  ui.Image? get original => _comparison.image;

  /// Starts the composition and the copy of the original.
  void initialize() {
    _layout = _settings.exportLayout;
    _readingsMode = _settings.exportReadingsMode;
    _quality = _result.quality;
    _settingsQuality = _settings.exportQuality;
    _capture = ResultCaptureLease(_result, _onSourceReleased);
    _comparison = OriginalComparison(
      export: _export,
      log: _log,
      isMounted: () => _host.mounted,
      isClosing: () => _closing,
      result: () => _result,
      originalKey: () => _key(original: true),
      notify: _host.notify,
    );
    _thumbnails = ResultStyleThumbnails(
      stills: _stills,
      log: _log,
      isMounted: () => _host.mounted,
      isClosing: () => _closing,
      isBusy: () => _processing,
      result: () => _result,
      notify: _host.notify,
    );
    _settings.addListener(_settingsChanged);
    _compose();
    _comparison.load(_key(original: true));
    // The previews wait until the main picture is on screen.
    _thumbnails.start();
  }

  /// Follows a new capture or a new settings object.
  void updateWidget({
    required CaptureResult result,
    required AppSettings settings,
    void Function()? onSourceReleased,
  }) {
    if (!identical(_settings, settings)) {
      _settings.removeListener(_settingsChanged);
      _settings = settings;
      _settings.addListener(_settingsChanged);
      _settingsQuality = settings.exportQuality;
      _quality = _settingsQuality;
    }
    _onSourceReleased = onSourceReleased;
    if (!identical(_result, result)) {
      _result = result;
      _requests++;
      _clearResults();
      _capture.retire();
      _capture = ResultCaptureLease(result, onSourceReleased);
      _quality = result.quality;
      _styleId = result.styleId;
      _format = ExportFormat.original;
      _layout = settings.exportLayout;
      _readingsMode = settings.exportReadingsMode;
      _comparison.load(_key(original: true));
      _compose();
      _thumbnails.start();
    } else if (_requestedKey != _key()) {
      _compose();
    }
  }

  void _settingsChanged() {
    if (_closing) return;
    if (_settingsQuality != _settings.exportQuality) {
      _settingsQuality = _settings.exportQuality;
      _quality = _settingsQuality;
    }
    if (_requestedKey == _key() || _busy) return;
    _processing = true;
    _host.notify();
    _compose();
  }

  void _clearResults() {
    _transitionImage?.dispose();
    _transitionImage = null;
    _composed = null;
    _file = null;
    _composedKey = null;
    _cache.clear();
    _comparison.clear();
    _thumbnails.clear();
  }

  /// Releases the pictures and the files of the screen.
  void dispose() {
    _closing = true;
    _requests++;
    _settings.removeListener(_settingsChanged);
    _clearResults();
    _capture.retire();
    if (_ownsStills) _stills.dispose();
  }

  /// The values that the layouts typeset.
  ExportLayoutValues get _values => ExportLayoutValues.fromAmbient(
    _result.ambient,
    styleName: _styleName(_styleId),
    context: _settings.contextLineEnabled ? _result.context : null,
    photoId: _result.identity?.displayId,
    readingsMode: _readingsMode,
  );

  /// The name of the style the photo is drawn with, for the poster.
  String _styleName(String id) {
    for (final style in kRegisteredStyles) {
      if (style.id == id) return style.name;
    }
    return id;
  }

  ResultCacheKey _key({bool original = false}) => (
    capture: _result,
    styleId: _styleId,
    format: _format,
    layout: _layout,
    // The full layout has no readings: its picture does not depend on the mode.
    readingsMode: _layout == ExportLayout.full
        ? ExportReadingsMode.full
        : _readingsMode,
    watermark: _settings.watermarkEnabled,
    contextLine: _settings.contextLineEnabled,
    fileType: _settings.fileType,
    quality: _quality,
    original: original,
  );

  Future<void> _compose() async {
    final request = ++_requests;
    final key = _key();
    _requestedKey = key;
    bool stale() => !_host.mounted || _closing || request != _requests;
    // A cache file may have been removed by the OS. Do not leave a disposed
    // current preview attached when get() drops that missing-file entry.
    if (_composedKey == key && _file != null && !_file!.existsSync()) {
      _composed = null;
      _file = null;
      _composedKey = null;
    }
    final cached = _cache.get(key);
    if (cached != null) {
      _composed = cached.image;
      _file = cached.file;
      _composedKey = key;
      _composedPhoto = cached.photo;
      _processing = false;
      _processingPixels = null;
      _host.notify();
      _thumbnails.kick();
      if (cached.metadata != null) {
        _captureMetrics.value = ExportCaptureTimings(
          _captureMetrics.value,
          cached.metadata!,
        );
      }
      return;
    }
    final capture = _capture;
    final result = key.capture;
    final export = _export;
    final values = _values;
    final render = result.source == null
        ? null
        : _renderFor(key.styleId, result);
    final pipeline = _photoExporter ?? PhotoExporter(export: export, log: _log);
    final started = DateTime.now().millisecondsSinceEpoch;
    capture.pending++;
    _processing = true;
    _processingPixels = null;
    ui.Image? owned;
    File? file;
    Rect photoRect = const Rect.fromLTWH(0, 0, 1, 1);
    Map<String, Object?>? metadata;
    // Only one full-resolution export allocates at a time, even when rapid
    // selections cancel it. Cache hits still publish immediately while it drains.
    final previousWork = result.source == null ? null : _sourceWork;
    final done = result.source == null ? null : Completer<void>();
    if (done != null) _sourceWork = done.future;
    try {
      if (previousWork != null) {
        await previousWork;
        if (stale()) return;
      }
      if (result.source != null) {
        final photo = await pipeline.process(
          source: result.source!,
          render: render!,
          quality: key.quality,
          format: key.format,
          watermark: key.watermark,
          layout: key.layout,
          values: values,
          fileType: key.fileType,
          // Include all small retained surfaces, including the comparison.
          retainedImageBytes:
              _cache.imageBytes +
              _comparison.retainedBytes +
              _thumbnails.retainedBytes,
          cancelled: stale,
          onProgress: (pixels) async {
            if (!stale()) {
              _processingPixels = pixels;
              _host.notify();
              await WidgetsBinding.instance.endOfFrame;
            }
          },
        );
        owned = photo.image;
        file = photo.file;
        metadata = photo.metadata;
        if (photo.metadata['photoLeft'] case final num left) {
          final width = (photo.metadata['width']! as num).toDouble();
          final height = (photo.metadata['height']! as num).toDouble();
          photoRect = Rect.fromLTWH(
            left / width,
            (photo.metadata['photoTop']! as num) / height,
            (photo.metadata['photoWidth']! as num) / width,
            (photo.metadata['photoHeight']! as num) / height,
          );
        }
        if (!stale()) {
          _captureMetrics.update(
            decodeMs: photo.metadata['decodeMs']! as double,
            renderMs: photo.metadata['renderMs']! as double,
            encodeMs: photo.metadata['encodeMs']! as double,
          );
          _captureMetrics.value = ExportCaptureTimings(
            _captureMetrics.value,
            photo.metadata,
          );
        }
      } else {
        owned = await export.compose(
          result.rendered,
          key.format,
          watermark: key.watermark,
          layout: key.layout,
          values: values,
        );
        file = await export.writeFile(owned, key.fileType);
        final crop = ExportPlan.cropRect(
          result.rendered.width,
          result.rendered.height,
          key.format,
        );
        final plan = ExportLayoutPlan.build(
          layout: key.layout,
          photoWidth: crop.width.toInt(),
          photoHeight: crop.height.toInt(),
          readings: hasExportReadings(values),
          readingsMode: values.readingsMode,
          context: values.context?.hasItems ?? false,
          watermark: key.watermark,
          photoId: values.photoId,
        );
        photoRect = Rect.fromLTWH(
          plan.photo.left / plan.width,
          plan.photo.top / plan.height,
          plan.photo.width / plan.width,
          plan.photo.height / plan.height,
        );
      }
      if (stale()) return;
      if (owned.width > ResultCache.previewSide ||
          owned.height > ResultCache.previewSide) {
        final small = await export.preview(
          owned,
          maxSide: ResultCache.previewSide,
        );
        owned.dispose();
        owned = small;
      }
      if (stale()) return;
      final entry = CachedResult(
        owned,
        file,
        photo: photoRect,
        metadata: metadata,
      );
      _cache.put(key, entry);
      owned = null;
      file = null;
      _composed = entry.image;
      _file = entry.file;
      _composedKey = key;
      _composedPhoto = entry.photo;
      _host.notify();
      if (result.source == null) {
        _captureMetrics.update(
          encodeMs: (DateTime.now().millisecondsSinceEpoch - started)
              .toDouble(),
        );
      }
    } catch (error, stackTrace) {
      if (error is ExportCancelled || stale()) return;
      _log.error(
        'export',
        'the picture could not be composed',
        error,
        stackTrace,
      );
      if (!_host.mounted) return;
      _host.showSnack(_host.saveFailedMessage);
    } finally {
      owned?.dispose();
      deleteResultFile(file);
      if (!stale()) {
        _processing = false;
        _processingPixels = null;
        _host.notify();
        _thumbnails.kick();
      }
      capture.pending--;
      capture.releaseIfIdle();
      done?.complete();
    }
  }

  /// Saves the picture in the gallery.
  Future<void> save() async {
    final file = _file;
    if (!ready || file == null) return;
    _busy = true;
    _host.notify();
    try {
      await _export.saveToGallery(file);
      if (!_host.mounted) return;
      // Keep the encoded cache entry for another Save or Share. Eviction,
      // Retake and screen disposal own cleanup, as for shared files.
      _host.showSnack(_host.savedMessage);
    } catch (error, stackTrace) {
      _log.error('export', 'the picture could not be saved', error, stackTrace);
      if (!_host.mounted) return;
      _host.showSnack(_host.saveFailedMessage);
    } finally {
      if (_host.mounted) {
        _busy = false;
        _host.notify();
        // Settings can change while the platform is reading this file. Defer
        // recomposition (and eviction) until that operation has returned.
        if (!_closing && _requestedKey != _key()) _compose();
      }
    }
  }

  /// Shares the picture with the system share sheet.
  Future<void> share() async {
    final file = _file;
    if (!ready || file == null) return;
    _busy = true;
    _host.notify();
    try {
      final shared = await _export.share(file, origin: _host.shareOrigin);
      if (!_host.mounted) return;
      // The working file is NOT deleted here: `share_plus` on Android
      // returns when the chooser is dismissed, not when the receiving
      // app has read the bytes, so a delete in this same tick removes
      // the file the target app is about to open. The file stays in the
      // cache and is cleaned up on eviction, Retake or `dispose`,
      // or by `removeStaleTemporaryFiles` at the next app start.
      if (shared) {
        _host.showSnack(_host.sharedMessage);
      }
    } catch (error, stackTrace) {
      _log.error(
        'export',
        'the picture could not be shared',
        error,
        stackTrace,
      );
      if (!_host.mounted) return;
      _host.showSnack(_host.shareFailedMessage);
    } finally {
      if (_host.mounted) {
        _busy = false;
        _host.notify();
        // Settings can change while the platform is reading this file. Defer
        // recomposition (and eviction) until that operation has returned.
        if (!_closing && _requestedKey != _key()) _compose();
      }
    }
  }

  /// The renderer of the full-size picture in the style [styleId].
  ///
  /// The style of the capture keeps the renderer that took the photo; any
  /// other style draws the same frozen values with its own shader.
  StillRender _renderFor(String styleId, CaptureResult result) {
    if (styleId == result.styleId) return result.render!;
    final style = kStyles.firstWhere((style) => style.id == styleId);
    return (image, maxSide) => _stills.render(
      style,
      image,
      ambient: result.ambient,
      time: result.time,
      maxSide: maxSide,
    );
  }

  /// Draws the photo with another style and composes it again.
  ///
  /// The choice belongs to this photo only: the style of the viewfinder is
  /// not changed. Format, layout, comparison, save and share follow it.
  void selectStyle(String styleId) {
    if (styleId == _styleId || _busy || _closing || !canChangeStyle) return;
    if (!kStyles.any((style) => style.id == styleId)) return;
    _styleId = styleId;
    _processing = true;
    _host.notify();
    _compose();
  }

  /// Picks the format of the export and composes it again.
  void selectFormat(ExportFormat format) {
    if (format == _format || _busy || _closing) {
      return;
    }
    _format = format;
    _processing = true;
    _host.notify();
    _compose();
    // The original is cropped like the picture that is on screen.
    _comparison.crop(_key(original: true));
  }

  /// Picks the layout of the export and composes it again.
  void selectLayout(ExportLayout layout) {
    if (layout == _layout || _busy || _closing) {
      return;
    }
    _layout = layout;
    _processing = true;
    _host.notify();
    // The layout is remembered, so the next photo starts with it.
    _compose();
    _settings.setExportLayout(layout);
  }

  /// Picks which readings the strip and the poster print and composes again.
  void selectReadingsMode(ExportReadingsMode mode) {
    if (mode == _readingsMode || _busy || _closing) {
      return;
    }
    _readingsMode = mode;
    _processing = true;
    _host.notify();
    // The choice is remembered, so the next photo starts with it.
    _compose();
    _settings.setExportReadingsMode(mode);
  }

  /// Shows the original photo or the processed one.
  void toggleOriginal() => _comparison.toggle();

  /// Tells the controller whether the picture is held with a finger.
  void setHolding(bool holding) => _comparison.setHolding(holding);

  /// Closes the screen for another shot.
  ///
  /// Returns false when the screen was already closing.
  bool closeForRetake() {
    if (_closing) return false;
    _closing = true;
    _requests++;
    // The route may still paint its reverse transition. Detach a bounded copy
    // for that transition before disposing every cache-owned image and file.
    final showingOriginal = showOriginal && _comparison.image != null;
    final transitionImage = (showingOriginal ? _comparison.image : _composed)
        ?.clone();
    final transitionPhoto = showingOriginal
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : _composedPhoto;
    _clearResults();
    _transitionImage = transitionImage;
    _composed = transitionImage;
    _composedPhoto = transitionPhoto;
    _host.notify();
    _capture.retire();
    return true;
  }
}
