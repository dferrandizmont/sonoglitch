import 'dart:ui' as ui;

import '../../ambient/ambient_state.dart';
import '../../camera/still_source.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
import '../../export/photo_export.dart';

/// What a capture leaves behind: the picture with the effect applied and the
/// ambient values of the moment.
///
/// The picture belongs to the screen that shows it, which has to dispose it.
class CaptureResult {
  const CaptureResult({
    required ui.Image rendered,
    required this.ambient,
    required this.styleId,
    this.context,
  }) : _rendered = rendered, // ignore: prefer_initializing_formals
       source = null,
       render = null,
       quality = ExportQuality.high;

  const CaptureResult.source({
    required this.source,
    required this.render,
    required this.quality,
    required this.ambient,
    required this.styleId,
    this.context,
  }) : _rendered = null;

  final ExportContext? context;
  final StillSource? source;
  final StillRender? render;
  final ExportQuality quality;

  /// Legacy pre-rendered input; camera originals are decoded on demand.
  final ui.Image? _rendered;
  ui.Image get rendered => _rendered!;

  /// The mean of the ambient state of the last seconds before the shot.
  final AmbientState ambient;

  /// The style that was used.
  final String styleId;
}
