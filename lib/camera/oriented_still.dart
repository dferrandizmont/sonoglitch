import 'dart:math' as math;
import 'dart:ui' as ui;

import 'still_source.dart';

/// Maps the mirrored portrait preview into the EXIF-decoded still's basis,
/// then rotates in that basis. Reflection and rotation do not commute.
class StillTransform {
  StillTransform({
    required bool frontLens,
    required bool decodedMirrored,
    required int previewQuarterTurns,
  }) : mirrorPreview = frontLens != decodedMirrored,
       quarterTurns =
           ((frontLens != decodedMirrored)
               ? -previewQuarterTurns
               : previewQuarterTurns) %
           4;

  final bool mirrorPreview;
  final int quarterTurns;
}

/// The camera codec has already applied EXIF (including any front-camera
/// mirror). This extra rotation compensates only for physical handset pose.
/// Exposing oriented dimensions makes export plan its crop AFTER the rotation.
class OrientedStill implements StillSource {
  OrientedStill(this.source, int quarterTurns)
    : quarterTurns = quarterTurns % 4;

  final StillSource source;
  final int quarterTurns;
  bool get swapsAxes => quarterTurns.isOdd;
  @override
  int get width => swapsAxes ? source.height : source.width;
  @override
  int get height => swapsAxes ? source.width : source.height;
  @override
  int get compressedBytes => source.compressedBytes;

  @override
  Future<ui.Image> decode(int width, int height) async {
    final decoded = await source.decode(
      swapsAxes ? height : width,
      swapsAxes ? width : height,
    );
    if (quarterTurns == 0) return decoded;
    try {
      return await rotatePhoto(decoded, quarterTurns);
    } finally {
      decoded.dispose();
    }
  }
}

/// Returns a separately owned surface. Rotating never introduces a mirror.
Future<ui.Image> rotatePhoto(ui.Image source, int quarterTurns) async {
  final turns = quarterTurns % 4;
  if (turns == 0) return source.clone();
  final width = turns.isOdd ? source.height : source.width;
  final height = turns.isOdd ? source.width : source.height;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(width / 2, height / 2);
  canvas.rotate(turns * math.pi / 2);
  canvas.translate(-source.width / 2, -source.height / 2);
  canvas.drawImage(source, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
