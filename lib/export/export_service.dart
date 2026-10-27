import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../debug/debug_log.dart';
import '../debug/redact_paths.dart';
import 'export_file_type.dart';
import 'export_format.dart';
import 'export_layout.dart';
import 'export_layout_painter.dart';
import 'export_quality.dart';
import 'export_readings.dart';
import 'image_encoder.dart';
import 'glitch_wordmark.dart' as signature;

/// Builds the final picture and gets it out of the phone.
///
/// The composition is done on a canvas: the crop of the chosen format, the
/// discreet watermark and the layout of the export. The result is written in
/// the temporary directory, from where it can be saved in the gallery or
/// shared.
class ExportService {
  /// Creates the service.
  ExportService({
    required this.log,
    this.temporaryDirectory,
    ImageEncoder? encoder,
  }) : encoder = encoder ?? ImageEncoder(log: log);

  /// Where the problems are reported.
  final DebugLog log;

  /// Optional destination for platform-free encoding tests.
  final Directory? temporaryDirectory;

  /// The native encoder that writes the JPEG of the exports.
  final ImageEncoder encoder;
  static int _fileSequence = 0;

  /// Text of the watermark.
  static const String watermarkText = signature.watermarkText;

  /// Height of the watermark, as a fraction of the shorter side of the
  /// picture.
  static const double watermarkHeightRatio = 0.022;

  /// Opacity of the watermark.
  static const double watermarkOpacity = 0.92;

  /// A separately owned, bounded display copy. The caller keeps ownership of
  /// the full-size input and releases it after encoding and making this copy.
  Future<ui.Image> preview(ui.Image image, {required int maxSide}) async {
    final scale = math.min(1.0, maxSide / math.max(image.width, image.height));
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Composes [source] with the crop of [format], the layout of the export
  /// and, when [watermark] is on, the signature.
  ///
  /// The layout is drawn around the picture: the picture keeps the size it
  /// was rendered at, so the band of the sound strip and the frame of the
  /// poster never make it smaller than the chosen quality.
  ///
  /// The returned image belongs to the caller, who has to dispose it.
  Future<ui.Image> compose(
    ui.Image source,
    ExportFormat format, {
    bool watermark = true,
    ExportLayout layout = ExportLayout.full,
    ExportLayoutValues? values,
  }) async {
    final crop = _cropRect(source, format);
    final plan = ExportLayoutPlan.build(
      layout: layout,
      photoWidth: crop.width.round().clamp(1, 100000),
      photoHeight: crop.height.round().clamp(1, 100000),
      readings: hasExportReadings(values),
      readingsMode: values?.readingsMode ?? ExportReadingsMode.full,
      context: values?.context?.hasItems ?? false,
      watermark: watermark,
      photoId: values?.photoId,
    );
    final painter = ExportLayoutPainter(
      layout: layout,
      plan: plan,
      values: values,
      watermark: watermark,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    try {
      painter.paintBackground(canvas);
      canvas.drawImageRect(
        source,
        crop,
        plan.photo.topLeft & plan.photo.size,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      if (layout == ExportLayout.soundStrip && plan.bandHeight == 0) {
        log.info('export', 'empty sound strip falls back to full');
      }
      if (watermark && plan.bandHeight == 0 && plan.frameWidth == 0) {
        _paintWatermark(canvas, plan.photo);
      }
      painter.paintForeground(canvas);
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(plan.width, plan.height);
    } finally {
      picture.dispose();
    }
  }

  /// Crop at decoded pixel boundaries, without resizing, before the effect.
  Future<ui.Image> crop(ui.Image source, ExportFormat format) async {
    final rect = ExportPlan.cropRect(source.width, source.height, format);
    if (rect.width == source.width && rect.height == source.height) {
      return source.clone();
    }
    final recorder = ui.PictureRecorder();
    try {
      ui.Canvas(recorder)
          .drawImage(source, Offset(-rect.left, -rect.top), ui.Paint());
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(rect.width.toInt(), rect.height.toInt());
    } finally {
      picture.dispose();
    }
  }

  /// Writes [image] as a PNG in the temporary directory of the app.
  Future<File> writePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('The picture could not be encoded as PNG');
    }
    final directory = temporaryDirectory ?? await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'sonoglitch_${DateTime.now().microsecondsSinceEpoch}_${_fileSequence++}.png',
    );
    try {
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } catch (_) {
      if (file.existsSync()) await file.delete();
      rethrow;
    }
    // Only the name of the file is written: the log must not carry the paths
    // of the device.
    log.info('export', 'picture written to ${fileName(file.path)}');
    return file;
  }

  /// Writes [image] in the file type the user chose.
  ///
  /// The PNG is always written first, because it is the lossless master of
  /// the export. A JPEG is encoded from it by the native encoder, which
  /// deletes the PNG when it works. When the encoder fails, the PNG is the
  /// file of the export, so the extension of the file always tells what it
  /// really is.
  Future<File> writeFile(ui.Image image, ExportFileType type) async {
    final png = await writePng(image);
    if (type == ExportFileType.png) return png;
    final output = File(_withExtension(png.path, type.extension));
    return encoder.encode(png, output);
  }

  /// The path of [path] with the extension [extension].
  static String _withExtension(String path, String extension) {
    final dot = path.lastIndexOf('.');
    final separator = math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    if (dot > separator) {
      return '${path.substring(0, dot)}$extension';
    }
    return '$path$extension';
  }

  /// The album to save in, or null when the system cannot create it without
  /// a storage permission.
  ///
  /// Android 10 only lets an app create an album with the legacy storage
  /// permission, which the app does not request. From Android 11 the album is
  /// created through the media store without any permission.
  static Future<String?> _galleryAlbum() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AppConfig.galleryAlbum;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt >= 30 ? AppConfig.galleryAlbum : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves [file] in the gallery, in the album of the app when possible.
  Future<void> saveToGallery(File file) async {
    try {
      await Gal.putImage(file.path, album: await _galleryAlbum());
      log.info('export', 'picture saved in the gallery');
    } catch (error, stackTrace) {
      log.error('export', 'the picture could not be saved', error, stackTrace);
      rethrow;
    }
  }

  /// Shares [file] with the system share sheet, without any text.
  Future<void> share(File file, {Rect? origin}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: AppConfig.appName,
          sharePositionOrigin: origin,
        ),
      );
      log.info('export', 'picture shared');
    } catch (error, stackTrace) {
      log.error('export', 'the picture could not be shared', error, stackTrace);
      rethrow;
    }
  }

  /// The area of [source] that keeps the aspect ratio of [format], centred.
  Rect _cropRect(ui.Image source, ExportFormat format) {
    final width = source.width.toDouble();
    final height = source.height.toDouble();
    final aspect = format.aspectRatio;
    if (aspect == null) return Rect.fromLTWH(0, 0, width, height);

    final sourceAspect = width / height;
    double cropWidth;
    double cropHeight;
    if (sourceAspect > aspect) {
      // The source is wider: keep the full height and cut the sides.
      cropHeight = height;
      cropWidth = height * aspect;
    } else {
      // The source is taller: keep the full width and cut the top and bottom.
      cropWidth = width;
      cropHeight = width / aspect;
    }
    final left = (width - cropWidth) / 2;
    final top = (height - cropHeight) / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  /// Watermark metrics in final output pixels, independent of orientation.
  static ({double fontSize, double margin}) watermarkMetrics(
    double width,
    double height,
  ) {
    final shorterSide = math.min(width, height);
    return (
      fontSize: shorterSide * watermarkHeightRatio / 0.7,
      margin: shorterSide * 0.02,
    );
  }

  /// A square dark plate, inset from the final photo edges.
  void _paintWatermark(ui.Canvas canvas, Rect photo) {
    final metrics = watermarkMetrics(photo.width, photo.height);
    final f = math.max(12.0, metrics.fontSize);
    final width = math.min(
      signature.GlitchWordmark.measure(f).width,
      math.max(
        .0015 * math.min(photo.width, photo.height),
        photo.width / 2 - metrics.margin - .84 * f - .005 * photo.width,
      ),
    );
    final baseline = Offset(
      photo.right - metrics.margin - .42 * f - width,
      photo.bottom - metrics.margin - .40 * f,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        baseline.dx - .42 * f,
        baseline.dy - .98 * f,
        baseline.dx + width + .42 * f,
        baseline.dy + .40 * f,
      ),
      ui.Paint()..color = const Color(0xFF0D0D11).withValues(alpha: .62),
    );
    signature.GlitchWordmark.paint(
      canvas,
      baseline,
      f,
      inkAlpha: watermarkOpacity,
      maxWidth: width,
    );
  }
}
