import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ambient/ambient_state.dart';
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
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/glitch_loader.dart';
import '../../theme/micro_label.dart';
import 'capture_result.dart';
import 'result_cache.dart';

/// The picture that was just taken, with the values that were measured and
/// the buttons to save, share or repeat.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.export,
    required this.settings,
    required this.log,
    required this.capture,
    this.onSourceReleased,
    this.photoExporter,
  });

  /// The picture and the measured values.
  final CaptureResult result;

  /// Used to compose, write and share the picture.
  final ExportService export;

  /// Optional exporter for platform-free integration tests.
  final PhotoExporter? photoExporter;

  /// The switches, for the watermark and the type of the file.
  final AppSettings settings;

  /// The logger.
  final DebugLog log;

  /// Called when the source picture is released after every composition.
  ///
  /// This is exposed for regression tests that need to observe the lifetime
  /// of the source without inspecting private widget state.
  final void Function()? onSourceReleased;

  /// The timings of the capture.
  final CaptureMetrics capture;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  ExportFormat _format = ExportFormat.original;
  ExportLayout _layout = ExportLayout.full;
  ExportReadingsMode _readingsMode = ExportReadingsMode.full;
  ui.Image? _composed;
  File? _file;

  final _cache = ResultCache();
  ResultCacheKey? _composedKey;
  Rect _composedPhoto = const Rect.fromLTWH(0, 0, 1, 1);
  ResultCacheKey? _requestedKey;
  late _CaptureLease _capture;
  late ExportQuality _quality;
  late ExportQuality _settingsQuality;
  Future<void>? _sourceWork;
  bool _closing = false;
  ui.Image? _transitionImage;
  bool _busy = false;
  int? _processingPixels;
  bool _processing = false;
  int _requests = 0;
  int _originalRequests = 0;

  bool get _ready =>
      !_closing &&
      !_busy &&
      !_processing &&
      _file != null &&
      _composedKey == _key();

  ResultCacheKey _key({bool original = false}) => (
    capture: widget.result,
    format: _format,
    layout: _layout,
    // The full layout has no readings: its picture does not depend on the mode.
    readingsMode: _layout == ExportLayout.full
        ? ExportReadingsMode.full
        : _readingsMode,
    watermark: widget.settings.watermarkEnabled,
    contextLine: widget.settings.contextLineEnabled,
    fileType: widget.settings.fileType,
    quality: _quality,
    original: original,
  );

  /// A small copy of the original photo, without the effect.
  ///
  /// It is decoded once, while the screen is open, and it is released when
  /// the screen is closed: a full size copy of the original would cost tens
  /// of megabytes for a comparison.
  ui.Image? _originalDecoded;

  /// The original photo, cropped like the picture that is on screen.
  ui.Image? _original;

  /// Whether the button asked for the original photo.
  bool _originalLatched = false;

  /// Whether the picture is being held with a finger.
  bool _holding = false;

  /// Whether the original photo is the one that is shown.
  bool get _showOriginal => _originalLatched || _holding;

  /// The longest side of the copy of the original that is kept.
  static const int originalPreviewSide = 1024;

  @override
  void initState() {
    super.initState();
    _layout = widget.settings.exportLayout;
    _readingsMode = widget.settings.exportReadingsMode;
    _quality = widget.result.quality;
    _settingsQuality = widget.settings.exportQuality;
    _capture = _CaptureLease(widget.result, widget.onSourceReleased);
    widget.settings.addListener(_settingsChanged);
    _compose();
    _loadOriginal();
  }

  @override
  void didUpdateWidget(ResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_settingsChanged);
      widget.settings.addListener(_settingsChanged);
      _settingsQuality = widget.settings.exportQuality;
      _quality = _settingsQuality;
    }
    if (!identical(oldWidget.result, widget.result)) {
      _requests++;
      _originalRequests++;
      _clearResults();
      _capture.retire();
      _capture = _CaptureLease(widget.result, widget.onSourceReleased);
      _quality = widget.result.quality;
      _format = ExportFormat.original;
      _layout = widget.settings.exportLayout;
      _readingsMode = widget.settings.exportReadingsMode;
      _originalLatched = false;
      _holding = false;
      _loadOriginal();
      _compose();
    } else if (_requestedKey != _key()) {
      _compose();
    }
  }

  void _settingsChanged() {
    if (_closing) return;
    if (_settingsQuality != widget.settings.exportQuality) {
      _settingsQuality = widget.settings.exportQuality;
      _quality = _settingsQuality;
    }
    if (_requestedKey == _key() || _busy) return;
    setState(() => _processing = true);
    _compose();
  }

  void _clearResults() {
    _transitionImage?.dispose();
    _transitionImage = null;
    _composed = null;
    _file = null;
    _composedKey = null;
    _cache.clear();
    _originalDecoded?.dispose();
    _originalDecoded = null;
    _original?.dispose();
    _original = null;
  }

  @override
  void dispose() {
    _closing = true;
    _requests++;
    _originalRequests++;
    widget.settings.removeListener(_settingsChanged);
    _clearResults();
    _capture.retire();
    super.dispose();
  }

  /// The values that the layouts typeset.
  ExportLayoutValues get _values => ExportLayoutValues.fromAmbient(
    widget.result.ambient,
    styleName: _styleName(widget.result.styleId),
    context: widget.settings.contextLineEnabled ? widget.result.context : null,
    photoId: widget.result.identity?.displayId,
    readingsMode: _readingsMode,
  );

  /// The name of the style that was used, for the poster.
  String _styleName(String id) {
    for (final style in kRegisteredStyles) {
      if (style.id == id) return style.name;
    }
    return id;
  }

  Future<void> _compose() async {
    final request = ++_requests;
    final key = _key();
    _requestedKey = key;
    bool stale() => !mounted || _closing || request != _requests;
    // A cache file may have been removed by the OS. Do not leave a disposed
    // current preview attached when get() drops that missing-file entry.
    if (_composedKey == key && _file != null && !_file!.existsSync()) {
      _composed = null;
      _file = null;
      _composedKey = null;
    }
    final cached = _cache.get(key);
    if (cached != null) {
      setState(() {
        _composed = cached.image;
        _file = cached.file;
        _composedKey = key;
        _composedPhoto = cached.photo;
        _processing = false;
        _processingPixels = null;
      });
      if (cached.metadata != null) {
        widget.capture.value = ExportCaptureTimings(
          widget.capture.value,
          cached.metadata!,
        );
      }
      return;
    }
    final capture = _capture;
    final result = key.capture;
    final export = widget.export;
    final values = _values;
    final pipeline =
        widget.photoExporter ?? PhotoExporter(export: export, log: widget.log);
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
          render: result.render!,
          quality: key.quality,
          format: key.format,
          watermark: key.watermark,
          layout: key.layout,
          values: values,
          fileType: key.fileType,
          // Include all small retained surfaces, including the comparison.
          retainedImageBytes:
              _cache.imageBytes +
              (_originalDecoded == null
                  ? 0
                  : _originalDecoded!.width * _originalDecoded!.height * 4) +
              (_original == null
                  ? 0
                  : _original!.width * _original!.height * 4),
          cancelled: stale,
          onProgress: (pixels) async {
            if (!stale()) {
              setState(() => _processingPixels = pixels);
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
          widget.capture.update(
            decodeMs: photo.metadata['decodeMs']! as double,
            renderMs: photo.metadata['renderMs']! as double,
            encodeMs: photo.metadata['encodeMs']! as double,
          );
          widget.capture.value = ExportCaptureTimings(
            widget.capture.value,
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
      setState(() {
        _composed = entry.image;
        _file = entry.file;
        _composedKey = key;
        _composedPhoto = entry.photo;
      });
      if (result.source == null) {
        widget.capture.update(
          encodeMs: (DateTime.now().millisecondsSinceEpoch - started)
              .toDouble(),
        );
      }
    } catch (error, stackTrace) {
      if (error is ExportCancelled || stale()) return;
      widget.log.error(
        'export',
        'the picture could not be composed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      _showError(AppLocalizations.of(context).resultSaveFailed);
    } finally {
      owned?.dispose();
      deleteResultFile(file);
      if (!stale()) {
        setState(() {
          _processing = false;
          _processingPixels = null;
        });
      }
      capture.pending--;
      capture.releaseIfIdle();
      done?.complete();
    }
  }

  /// Decodes a small copy of the original photo, to compare it with the
  /// processed one.
  Future<void> _loadOriginal() async {
    final result = widget.result;
    final source = result.source;
    if (source == null) return;
    ui.Image? decoded;
    try {
      final longest = source.width > source.height
          ? source.width
          : source.height;
      final scale = longest > originalPreviewSide
          ? originalPreviewSide / longest
          : 1.0;
      final width = (source.width * scale).round().clamp(1, source.width);
      final height = (source.height * scale).round().clamp(1, source.height);
      decoded = await source.decode(width, height);
    } catch (error) {
      widget.log.warning(
        'result',
        'the original photo could not be decoded: $error',
      );
      return;
    }
    if (!mounted || _closing || !identical(result, widget.result)) {
      decoded.dispose();
      return;
    }
    _originalDecoded = decoded;
    await _cropOriginal();
  }

  /// Crops the copy of the original like the picture that is on screen.
  Future<void> _cropOriginal() async {
    final request = ++_originalRequests;
    final key = _key(original: true);
    final original = _originalDecoded;
    if (original == null) return;
    final decoded = original.clone();
    ui.Image? cropped;
    try {
      cropped = await widget.export.crop(decoded, key.format);
    } catch (error) {
      widget.log.warning(
        'result',
        'the original photo could not be cropped: $error',
      );
      return;
    } finally {
      decoded.dispose();
    }
    if (!mounted ||
        _closing ||
        request != _originalRequests ||
        !identical(key.capture, widget.result)) {
      cropped.dispose();
      return;
    }
    setState(() {
      _original?.dispose();
      _original = cropped;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final file = _file;
    if (!_ready || file == null) return;
    setState(() => _busy = true);
    try {
      await widget.export.saveToGallery(file);
      if (!mounted) return;
      // Keep the encoded cache entry for another Save or Share. Eviction,
      // Retake and screen disposal own cleanup, as for shared files.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).resultSaved)),
      );
    } catch (error, stackTrace) {
      widget.log.error(
        'export',
        'the picture could not be saved',
        error,
        stackTrace,
      );
      if (!mounted) return;
      _showError(AppLocalizations.of(context).resultSaveFailed);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Settings can change while the platform is reading this file. Defer
        // recomposition (and eviction) until that operation has returned.
        if (!_closing && _requestedKey != _key()) _compose();
      }
    }
  }

  Future<void> _share() async {
    final file = _file;
    if (!_ready || file == null) return;
    setState(() => _busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final shared = await widget.export.share(file, origin: origin);
      if (!mounted) return;
      // The working file is NOT deleted here: `share_plus` on Android
      // returns when the chooser is dismissed, not when the receiving
      // app has read the bytes, so a delete in this same tick removes
      // the file the target app is about to open. The file stays in the
      // cache and is cleaned up on eviction, Retake or `dispose`,
      // or by `removeStaleTemporaryFiles` at the next app start.
      if (shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).resultShared)),
        );
      }
    } catch (error, stackTrace) {
      widget.log.error(
        'export',
        'the picture could not be shared',
        error,
        stackTrace,
      );
      if (!mounted) return;
      _showError(AppLocalizations.of(context).resultShareFailed);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Settings can change while the platform is reading this file. Defer
        // recomposition (and eviction) until that operation has returned.
        if (!_closing && _requestedKey != _key()) _compose();
      }
    }
  }

  void _retake() {
    if (_closing) return;
    _closing = true;
    _requests++;
    _originalRequests++;
    // The route may still paint its reverse transition. Detach a bounded copy
    // for that transition before disposing every cache-owned image and file.
    final showingOriginal = _showOriginal && _original != null;
    final transitionImage = (showingOriginal ? _original : _composed)?.clone();
    final transitionPhoto = showingOriginal
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : _composedPhoto;
    _clearResults();
    setState(() {
      _transitionImage = transitionImage;
      _composed = transitionImage;
      _composedPhoto = transitionPhoto;
      _originalLatched = false;
      _holding = false;
    });
    _capture.retire();
    Navigator.of(context).pop();
  }

  /// Picks the format of the export and composes it again.
  void _selectFormat(ExportFormat format) {
    if (format == _format || _busy || _closing) {
      return;
    }
    setState(() {
      _format = format;
      _processing = true;
    });
    _compose();
    // The original is cropped like the picture that is on screen.
    _cropOriginal();
  }

  /// Picks the layout of the export and composes it again.
  void _selectLayout(ExportLayout layout) {
    if (layout == _layout || _busy || _closing) {
      return;
    }
    setState(() {
      _layout = layout;
      _processing = true;
    });
    // The layout is remembered, so the next photo starts with it.
    _compose();
    widget.settings.setExportLayout(layout);
  }

  /// Picks which readings the strip and the poster print and composes again.
  void _selectReadingsMode(ExportReadingsMode mode) {
    if (mode == _readingsMode || _busy || _closing) {
      return;
    }
    setState(() {
      _readingsMode = mode;
      _processing = true;
    });
    // The choice is remembered, so the next photo starts with it.
    _compose();
    widget.settings.setExportReadingsMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.resultTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _retake,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: AppTheme.background,
              padding: const EdgeInsets.all(AppTheme.spaceSm),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: _picture(l10n)),
                  // The one loader of the screen sits where the photo is, so
                  // it stays in view however far the controls are scrolled.
                  if (_processing)
                    IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(AppTheme.spaceMd),
                        decoration: BoxDecoration(
                          color: AppTheme.background.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                        ),
                        child: const GlitchLoader(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The slot keeps its height, so the controls below do not
                  // jump when the loader appears or goes away.
                  SizedBox(
                    height: _processingSlotHeight,
                    child: _processingPixels == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.all(AppTheme.spaceSm),
                            child: Text(
                              l10n.processingMegapixels(
                                (_processingPixels! / 1000000).toStringAsFixed(
                                  1,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceMd,
                      vertical: AppTheme.spaceSm,
                    ),
                    child: _Measurements(ambient: widget.result.ambient),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MicroLabel(l10n.resultFormatLabel),
                        const SizedBox(height: AppTheme.spaceXs),
                        Wrap(
                          spacing: AppTheme.spaceSm - AppTheme.space2xs,
                          runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
                          children: [
                            for (final format in ExportFormat.values)
                              _SelectorChip(
                                key: ValueKey('res-format-${format.name}'),
                                label: _formatLabel(l10n, format),
                                selected: format == _format,
                                onTap: _selectorsEnabled
                                    ? () => _selectFormat(format)
                                    : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        MicroLabel(l10n.resultLayoutLabel),
                        const SizedBox(height: AppTheme.spaceXs),
                        // The hint explains what the chosen layout does. It
                        // may take two lines on a small screen, so it never
                        // pushes the chips out of the way.
                        Text(
                          _layoutHint(l10n, _layout),
                          key: const ValueKey('res-layout-hint'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Wrap(
                          spacing: AppTheme.spaceSm - AppTheme.space2xs,
                          runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
                          children: [
                            for (final layout in ExportLayout.values)
                              _SelectorChip(
                                key: ValueKey('res-layout-${layout.name}'),
                                label: _layoutLabel(l10n, layout),
                                selected: layout == _layout,
                                onTap: _selectorsEnabled
                                    ? () => _selectLayout(layout)
                                    : null,
                              ),
                          ],
                        ),
                        // The readings only exist in the strip and the poster.
                        AnimatedSize(
                          duration: AppTheme.motionDuration(
                            context,
                            AppTheme.sheetDuration,
                          ),
                          curve: AppTheme.motionCurve,
                          alignment: Alignment.topLeft,
                          child: _layout == ExportLayout.full
                              ? const SizedBox(
                                  width: double.infinity,
                                  height: 0,
                                )
                              : _readingsSelector(l10n, theme),
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppTheme.outline,
                  width: AppTheme.borderWidth,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final stacked = constraints.maxWidth / scale < 220;
                    final verticalIcons =
                        !stacked && constraints.maxWidth < 340;
                    final actions = [
                      TextButton(
                        onPressed: _busy ? null : _retake,
                        style: _actionStyle(context).copyWith(
                          foregroundColor: const WidgetStatePropertyAll(
                            AppTheme.textSecondary,
                          ),
                        ),
                        child: _actionContent(
                          Icons.replay,
                          l10n.resultRetake,
                          verticalIcons,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _ready ? _share : null,
                        style: _actionStyle(context),
                        child: _actionContent(
                          Icons.share_outlined,
                          l10n.resultShare,
                          verticalIcons,
                        ),
                      ),
                      FilledButton(
                        onPressed: _ready ? _save : null,
                        style: _actionStyle(context),
                        child: _actionContent(
                          Icons.download_outlined,
                          l10n.resultSave,
                          verticalIcons,
                        ),
                      ),
                    ];
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppTheme.spaceXs),
                            actions[i],
                          ],
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: AppTheme.spaceSm),
                            Expanded(child: actions[i]),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The selector of the readings, under the chips of the layout.
  Widget _readingsSelector(AppLocalizations l10n, ThemeData theme) => Column(
    key: const ValueKey('res-readings'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: AppTheme.spaceMd),
      MicroLabel(l10n.resultReadingsLabel),
      const SizedBox(height: AppTheme.spaceXs),
      Text(
        _readingsHint(l10n, _readingsMode),
        key: const ValueKey('res-readings-hint'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
      const SizedBox(height: AppTheme.spaceXs),
      Wrap(
        spacing: AppTheme.spaceSm - AppTheme.space2xs,
        runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
        children: [
          for (final mode in ExportReadingsMode.values)
            _SelectorChip(
              key: ValueKey('res-readings-${mode.name}'),
              label: _readingsLabel(l10n, mode),
              selected: mode == _readingsMode,
              onTap: _selectorsEnabled ? () => _selectReadingsMode(mode) : null,
            ),
        ],
      ),
    ],
  );

  String _readingsLabel(AppLocalizations l10n, ExportReadingsMode mode) =>
      switch (mode) {
        ExportReadingsMode.full => l10n.resultReadingsFull,
        ExportReadingsMode.numbers => l10n.resultReadingsNumbers,
        ExportReadingsMode.hidden => l10n.resultReadingsHidden,
      };

  /// The line that explains what the chosen readings mode does.
  String _readingsHint(AppLocalizations l10n, ExportReadingsMode mode) =>
      switch (mode) {
        ExportReadingsMode.full => l10n.resultReadingsHintFull,
        ExportReadingsMode.numbers => l10n.resultReadingsHintNumbers,
        ExportReadingsMode.hidden => l10n.resultReadingsHintHidden,
      };

  /// The picture on screen, with the button that shows the original.
  Widget _picture(AppLocalizations l10n) {
    final image = _showOriginal && _original != null ? _original : _composed;
    if (image == null) return const SizedBox.shrink();
    // Fit the stack to the image so Compare follows the actual photo corner.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = applyBoxFit(
          BoxFit.contain,
          Size(image.width.toDouble(), image.height.toDouble()),
          constraints.biggest,
        ).destination;
        final photo = _showOriginal && _original != null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : _composedPhoto;
        return SizedBox.fromSize(
          size: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onLongPressStart: (_) => setState(() => _holding = true),
                  onLongPressEnd: (_) => setState(() => _holding = false),
                  onLongPressCancel: () => setState(() => _holding = false),
                  child: RawImage(image: image, fit: BoxFit.contain),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('res-photo-frame'),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.overlayEdge.withValues(alpha: 0.08),
                        width: AppTheme.borderWidth,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AppTheme.spaceXs + (1 - photo.right) * size.width,
                top: AppTheme.spaceXs + photo.top * size.height,
                child: Semantics(
                  button: true,
                  enabled: _original != null,
                  label: _compareLabel(l10n),
                  onTap: _original == null ? null : _toggleOriginal,
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey('res-compare'),
                    onPressed: _original == null ? null : _toggleOriginal,
                    tooltip: _compareLabel(l10n),
                    icon: Ink(
                      width: AppTheme.touchTarget - AppTheme.spaceSm,
                      height: AppTheme.touchTarget - AppTheme.spaceSm,
                      decoration: BoxDecoration(
                        color: AppTheme.scrim,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Icon(
                        _showOriginal ? Icons.image_outlined : Icons.compare,
                        size: AppTheme.overlayIconSize,
                      ),
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: AppTheme.touchTarget,
                      height: AppTheme.touchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      disabledForegroundColor: AppTheme.textSecondary,
                      animationDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppTheme.pressDuration,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Height of the line of the loader and the megapixels text.
  static const double _processingSlotHeight = AppTheme.spaceSm * 2 + 20;

  bool get _selectorsEnabled => !_busy && !_closing;

  void _toggleOriginal() =>
      setState(() => _originalLatched = !_originalLatched);

  Widget _actionContent(IconData icon, String label, bool vertical) {
    final text = Text(label, textAlign: TextAlign.center);
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: AppTheme.spaceXs),
          text,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(width: AppTheme.spaceSm),
        Flexible(child: text),
      ],
    );
  }

  ButtonStyle _actionStyle(BuildContext context) => ButtonStyle(
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: AppTheme.spaceXs,
        vertical: AppTheme.spaceXs,
      ),
    ),
    minimumSize: const WidgetStatePropertyAll(
      Size.square(AppTheme.touchTarget),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.pressDuration,
  );

  String _formatLabel(AppLocalizations l10n, ExportFormat format) {
    switch (format) {
      case ExportFormat.original:
        return l10n.resultFormatOriginal;
      case ExportFormat.square:
        return l10n.resultFormatSquare;
      case ExportFormat.portrait:
        return l10n.resultFormatPortrait;
      case ExportFormat.story:
        return l10n.resultFormatStory;
    }
  }

  String _layoutLabel(AppLocalizations l10n, ExportLayout layout) {
    switch (layout) {
      case ExportLayout.full:
        return l10n.resultLayoutFull;
      case ExportLayout.soundStrip:
        return l10n.resultLayoutSoundStrip;
      case ExportLayout.poster:
        return l10n.resultLayoutPoster;
    }
  }

  /// The line that explains what the chosen layout does.
  String _layoutHint(AppLocalizations l10n, ExportLayout layout) {
    switch (layout) {
      case ExportLayout.full:
        return l10n.resultLayoutHintFull;
      case ExportLayout.soundStrip:
        return l10n.resultLayoutHintSoundStrip;
      case ExportLayout.poster:
        return l10n.resultLayoutHintPoster;
    }
  }

  /// What the button of the comparison says.
  ///
  /// The button compares the photo with the original one, and holding the
  /// photo does the same, so the label says both.
  String _compareLabel(AppLocalizations l10n) => _showOriginal
      ? l10n.resultShowProcessedTooltip
      : l10n.resultCompareTooltip;
}

/// In-flight work keeps its own capture alive across widget replacements.
class _CaptureLease {
  _CaptureLease(this.result, this.onReleased);
  final CaptureResult result;
  final void Function()? onReleased;
  int pending = 0;
  bool retired = false;
  bool released = false;

  void retire() {
    retired = true;
    releaseIfIdle();
  }

  void releaseIfIdle() {
    if (!retired || pending != 0 || released) return;
    released = true;
    if (result.source == null) result.rendered.dispose();
    onReleased?.call();
  }
}

/// The values that were measured when the picture was taken.
class _Measurements extends StatelessWidget {
  const _Measurements({required this.ambient});

  final AmbientState ambient;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rawDb = ambient.rawDb;
    final light = _levelWord(l10n, ambient.light);
    final motion = _levelWord(l10n, ambient.motion);
    final readings = <Widget>[
      _Reading(
        label: l10n.levelNoise,
        value: rawDb == null
            ? _levelWord(l10n, ambient.noise)
            : '\u2248${rawDb.round()} dB',
        semanticsLabel: rawDb == null
            ? null
            : l10n.resultNoiseLabel(rawDb.round()),
        color: AppTheme.accent,
      ),
      _Reading(
        label: l10n.levelLight,
        value: light,
        semanticsLabel: l10n.resultLightLabel(light),
        color: AppTheme.warm,
      ),
      _Reading(
        label: l10n.levelMotion,
        value: motion,
        semanticsLabel: l10n.resultMotionLabel(motion),
        color: AppTheme.signalCyan,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth / scale < 200;
        if (stacked) {
          return Column(
            key: const ValueKey('res-readings'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < readings.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTheme.spaceSm),
                readings[i],
              ],
            ],
          );
        }
        return Row(
          key: const ValueKey('res-readings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final reading in readings) Expanded(child: reading)],
        );
      },
    );
  }

  String _levelWord(AppLocalizations l10n, double value) {
    if (value < 0.33) return l10n.resultLevelLow;
    if (value < 0.66) return l10n.resultLevelMedium;
    return l10n.resultLevelHigh;
  }
}

/// One instrument readout; the spoken noise value retains its calibration caveat.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    required this.color,
    this.semanticsLabel,
  });
  final String label;
  final String value;
  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    excludeSemantics: semanticsLabel != null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MicroLabel(label),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Row(
          children: [
            SizedBox.square(
              dimension: AppTheme.spaceXs,
              child: ColoredBox(color: color),
            ),
            const SizedBox(width: AppTheme.spaceXs),
            Flexible(
              child: Text(
                value.isEmpty
                    ? value
                    : '${value[0].toUpperCase()}${value.substring(1)}',
                style: AppTheme.readout,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A square option tile with explicit selected and disabled states.
class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.pressDuration,
        color: selected
            ? AppTheme.accentTint
            : AppTheme.surface.withValues(alpha: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          side: BorderSide(
            color: selected ? AppTheme.accent : AppTheme.edge,
            width: AppTheme.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppTheme.touchTarget,
              minHeight: AppTheme.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceMd - AppTheme.space2xs,
                vertical: AppTheme.spaceXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
