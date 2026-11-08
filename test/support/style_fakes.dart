import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/camera/still_source.dart';
import 'package:sonoglitch/effects/style_definition.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/export/photo_export.dart';
import 'package:sonoglitch/features/result/result_style_stills.dart';

/// A source that gives a new copy of the picture of the test on every decode,
/// the way the real source does, and remembers what was asked.
class CloningSource implements StillSource {
  CloningSource(this.image, {int? width, int? height})
    : width = width ?? image.width,
      height = height ?? image.height;

  final ui.Image image;
  final requests = <(int, int)>[];

  @override
  final int width;

  @override
  final int height;

  @override
  int get compressedBytes => 4096;

  @override
  Future<ui.Image> decode(int width, int height) async {
    requests.add((width, height));
    return image.clone();
  }
}

/// One call to [RecordingStills].
class StillCall {
  StillCall(this.styleId, this.ambient, this.time, this.maxSide);
  final String styleId;
  final AmbientState ambient;
  final double time;
  final int maxSide;
}

/// Style stills that draw nothing: they give a copy of a picture of the test
/// and remember every call, so a test can check what was drawn, with which
/// frozen values and whether two draws ever overlapped.
class RecordingStills implements StyleStills {
  RecordingStills(this.picture);

  /// The picture every call returns a copy of.
  final ui.Image picture;
  final calls = <StillCall>[];
  final produced = <ui.Image>[];
  final gates = <String, Completer<void>>{};
  final failing = <String>{};
  int active = 0;
  int maxActive = 0;
  bool disposed = false;

  @override
  Future<ui.Image> render(
    StyleDefinition style,
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    required int maxSide,
  }) async {
    calls.add(StillCall(style.id, ambient, time, maxSide));
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await gates[style.id]?.future;
      if (failing.contains(style.id)) throw StateError('shader failed');
      final image = picture.clone();
      produced.add(image);
      return image;
    } finally {
      active--;
    }
  }

  @override
  void dispose() => disposed = true;
}

/// What the exporter saw in one composition.
class ExportCall {
  ExportCall(this.format, this.layout, this.styleName, this.file);
  final ExportFormat format;
  final ExportLayout layout;
  final String? styleName;
  final File file;
}

/// An exporter that runs the renderer it is given on a small picture and
/// writes a file that is named after the style that was typeset.
class RecordingExporter extends PhotoExporter {
  RecordingExporter({
    required super.export,
    required super.log,
    required this.directory,
  });

  final Directory directory;
  final calls = <ExportCall>[];
  final gates = <Completer<void>>[];

  @override
  Future<PhotoExport> process({
    required StillSource source,
    required StillRender render,
    required ExportQuality quality,
    required ExportFormat format,
    required bool watermark,
    ExportLayout layout = ExportLayout.full,
    ExportLayoutValues? values,
    ExportFileType fileType = ExportFileType.png,
    int retainedImageBytes = 0,
    FutureOr<void> Function(int pixels)? onProgress,
    bool Function()? cancelled,
  }) async {
    final index = calls.length;
    final input = await source.decode(8, 4);
    final ui.Image image;
    try {
      image = await render(input, 1024);
    } finally {
      input.dispose();
    }
    if (index < gates.length) await gates[index].future;
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'sonoglitch_${values?.styleName}_$index.png',
    )..writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    calls.add(ExportCall(format, layout, values?.styleName, file));
    return PhotoExport(image, file, {
      'width': image.width,
      'height': image.height,
      'decodeMs': 1.0,
      'renderMs': 1.0,
      'encodeMs': 1.0,
    });
  }
}

/// Style stills for the tests that are not about the strip: they draw nothing,
/// so the screen shows empty tiles and only the main picture.
class NoStills implements StyleStills {
  @override
  Future<ui.Image> render(
    StyleDefinition style,
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    required int maxSide,
  }) async => throw StateError('No style is drawn in this test');

  @override
  void dispose() {}
}
