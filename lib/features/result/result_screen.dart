import 'package:flutter/material.dart';

import '../../debug/capture_metrics.dart';
import '../../debug/debug_log.dart';
import '../../export/export_service.dart';
import '../../export/photo_export.dart';
import '../../features/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/glitch_loader.dart';
import 'capture_result.dart';
import 'result_export_controller.dart';
import 'result_measurements.dart';
import 'result_picture.dart';
import 'result_selectors.dart';
import 'result_style_stills.dart';
import 'result_style_strip.dart';
import 'result_toolbar.dart';

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
    this.styleStills,
  });

  /// The picture and the measured values.
  final CaptureResult result;

  /// Used to compose, write and share the picture.
  final ExportService export;

  /// Optional exporter for platform-free integration tests.
  final PhotoExporter? photoExporter;

  /// Draws the photo in the other styles; the shaders of the app by default.
  ///
  /// Exposed for platform-free tests, which cannot compile shaders.
  final StyleStills? styleStills;

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

class _ResultScreenState extends State<ResultScreen>
    implements ResultExportHost {
  late final ResultExportController _controller;

  /// Height of the line of the loader and the megapixels text.
  static const double _processingSlotHeight = AppTheme.spaceSm * 2 + 20;

  @override
  void initState() {
    super.initState();
    _controller = ResultExportController(
      result: widget.result,
      export: widget.export,
      settings: widget.settings,
      log: widget.log,
      capture: widget.capture,
      host: this,
      photoExporter: widget.photoExporter,
      styleStills: widget.styleStills,
      onSourceReleased: widget.onSourceReleased,
    )..initialize();
  }

  @override
  void didUpdateWidget(ResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.updateWidget(
      result: widget.result,
      settings: widget.settings,
      onSourceReleased: widget.onSourceReleased,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void notify() {
    if (mounted) setState(() {});
  }

  @override
  Rect? get shareOrigin {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  String get savedMessage => AppLocalizations.of(context).resultSaved;

  @override
  String get sharedMessage => AppLocalizations.of(context).resultShared;

  @override
  String get saveFailedMessage => AppLocalizations.of(context).resultSaveFailed;

  @override
  String get shareFailedMessage =>
      AppLocalizations.of(context).resultShareFailed;

  void _retake() {
    if (_controller.closeForRetake()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
                  Center(
                    child: ResultPicture(
                      composed: _controller.composed,
                      original: _controller.original,
                      showOriginal: _controller.showOriginal,
                      photo: _controller.composedPhoto,
                      compareLabel: _compareLabel(l10n),
                      onToggleOriginal: _controller.toggleOriginal,
                      onHoldingChanged: _controller.setHolding,
                    ),
                  ),
                  // The one loader of the screen sits where the photo is, so
                  // it stays in view however far the controls are scrolled.
                  if (_controller.processing)
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
                    child: _controller.processingPixels == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.all(AppTheme.spaceSm),
                            child: Text(
                              l10n.processingMegapixels(
                                (_controller.processingPixels! / 1000000)
                                    .toStringAsFixed(1),
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
                    child: ResultMeasurements(ambient: widget.result.ambient),
                  ),
                  // Only a photo that still has its original can be drawn in
                  // another style.
                  if (_controller.canChangeStyle)
                    ResultStyleStrip(
                      styles: _controller.styles,
                      selectedId: _controller.styleId,
                      enabled: _controller.selectorsEnabled,
                      imageFor: _controller.styleThumbnail,
                      onSelect: _controller.selectStyle,
                    ),
                  ResultSelectors(
                    format: _controller.format,
                    layout: _controller.layout,
                    readingsMode: _controller.readingsMode,
                    enabled: _controller.selectorsEnabled,
                    onSelectFormat: _controller.selectFormat,
                    onSelectLayout: _controller.selectLayout,
                    onSelectReadingsMode: _controller.selectReadingsMode,
                  ),
                ],
              ),
            ),
          ),
          ResultToolbar(
            busy: _controller.busy,
            ready: _controller.ready,
            onRetake: _retake,
            onShare: _controller.share,
            onSave: _controller.save,
          ),
        ],
      ),
    );
  }

  /// What the button of the comparison says.
  ///
  /// The button compares the photo with the original one, and holding the
  /// photo does the same, so the label says both.
  String _compareLabel(AppLocalizations l10n) => _controller.showOriginal
      ? l10n.resultShowProcessedTooltip
      : l10n.resultCompareTooltip;
}
