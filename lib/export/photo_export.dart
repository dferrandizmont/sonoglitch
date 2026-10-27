import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../camera/still_source.dart';
import '../debug/debug_log.dart';
import 'export_file_type.dart';
import 'export_format.dart';
import 'export_layout.dart';
import 'export_quality.dart';
import 'export_readings.dart';
import 'export_service.dart';

typedef StillRender = Future<ui.Image> Function(ui.Image source, int maxSide);

/// Full-size PNG and a separately owned image, which may be used as a preview.
class PhotoExport {
  const PhotoExport(this.image, this.file, this.metadata);
  final ui.Image image;
  final File file;
  final Map<String, Object?> metadata;
}

/// One attempt owns all its surfaces and releases them before a lower tier.
class PhotoExporter {
  PhotoExporter({required this.export, required this.log, this.textureProbe});
  final ExportService export;
  final DebugLog log;
  final Future<int> Function(int requested)? textureProbe;

  /// Flutter has no public GPU capability query. Validate the needed dimension
  /// with thin render targets on both axes (at most a few hundred KB), then
  /// binary-search downward if the backend rejects or silently clamps it.
  static Future<int> probeTextureLimit(
    int requested, {
    Future<bool> Function(int side)? supportsDimension,
  }) async {
    if (requested <= 0) throw ArgumentError.value(requested, 'requested');
    Future<bool> supports(int side) async {
      if (supportsDimension != null) return supportsDimension(side);
      for (final size in [(side, 1), (1, side)]) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
        final picture = recorder.endRecording();
        ui.Image? image;
        try {
          image = await picture.toImage(size.$1, size.$2);
          if (image.width != size.$1 || image.height != size.$2) return false;
        } on OutOfMemoryError {
          return false;
        } finally {
          image?.dispose();
          picture.dispose();
        }
      }
      return true;
    }

    if (await supports(requested)) return requested;
    var low = 0;
    var high = requested;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (await supports(middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }
    if (low == 0) throw StateError('No render target available');
    return low;
  }

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
    if (retainedImageBytes < 0) {
      throw ArgumentError.value(retainedImageBytes, 'retainedImageBytes');
    }
    if (cancelled?.call() ?? false) throw const ExportCancelled();
    // Probe both the decoder and the decorated output before allocating either.
    final preliminary = ExportPlan.build(
      sourceWidth: source.width,
      sourceHeight: source.height,
      quality: quality,
      format: format,
      textureLimit: source.width > source.height ? source.width : source.height,
    );
    final preliminaryLayout = ExportLayoutPlan.build(
      layout: layout,
      photoWidth: preliminary.width,
      photoHeight: preliminary.height,
      readings: hasExportReadings(values),
      context: values?.context?.hasItems ?? false,
      watermark: watermark,
      photoId: values?.photoId,
    );
    final requested = [
      preliminary.decodeWidth,
      preliminary.decodeHeight,
      preliminaryLayout.width,
      preliminaryLayout.height,
    ].reduce(math.max);
    final limit = await (textureProbe ?? probeTextureLimit)(requested);
    var level = quality;
    while (true) {
      if (cancelled?.call() ?? false) throw const ExportCancelled();
      ExportPlan planAt(int side) => ExportPlan.build(
        sourceWidth: source.width,
        sourceHeight: source.height,
        quality: level,
        format: format,
        textureLimit: side,
      );
      ExportLayoutPlan layoutAt(ExportPlan plan) => ExportLayoutPlan.build(
        layout: layout,
        photoWidth: plan.width,
        photoHeight: plan.height,
        readings: hasExportReadings(values),
        context: values?.context?.hasItems ?? false,
        watermark: watermark,
        photoId: values?.photoId,
      );
      bool fits(ExportPlan plan) {
        final output = layoutAt(plan);
        return output.width <= limit && output.height <= limit;
      }

      var plan = planAt(limit);
      if (!fits(plan)) {
        // Supported fallback: lower the decode resolution, keeping the layout
        // and a single resize. Integer layout rounding is checked at every step.
        var low = 1;
        var high = math.min(
          limit,
          math.max(plan.decodeWidth, plan.decodeHeight),
        );
        if (!fits(planAt(low))) {
          throw StateError(
            'No render target available for the selected layout',
          );
        }
        while (high - low > 1) {
          final middle = (low + high) ~/ 2;
          if (fits(planAt(middle))) {
            low = middle;
          } else {
            high = middle;
          }
        }
        plan = planAt(low);
        log.warning(
          'capture',
          'export layout fallback layout=${layout.name} '
              'photo=${plan.width}x${plan.height} textureLimit=$limit',
        );
      }
      final layoutPlan = layoutAt(plan);
      ui.Image? decoded;
      ui.Image? cropped;
      ui.Image? rendered;
      ui.Image? composed;
      File? file;
      var stage = 'memory guard';
      final estimatedBytes =
          plan.estimatedBytes +
          // Decorated layouts need the final surface and encoding buffers in
          // addition to the photo surfaces covered by the original guard.
          (layoutPlan.bandHeight == 0 && layoutPlan.frameWidth == 0
              ? 0
              : layoutPlan.width * layoutPlan.height * 4 * 3) +
          source.compressedBytes +
          retainedImageBytes;
      try {
        if (estimatedBytes > ExportPlan.memoryBudgetBytes) {
          throw _ExportMemoryLimitExceeded(estimatedBytes);
        }
        stage = 'progress';
        await onProgress?.call(plan.width * plan.height);
        // Let the progress label paint before starting the decoder/encoder.
        await Future<void>.delayed(Duration.zero);
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        final decodeWatch = Stopwatch()..start();
        stage = 'decode';
        decoded = await source.decode(plan.decodeWidth, plan.decodeHeight);
        if (decoded.width != plan.decodeWidth ||
            decoded.height != plan.decodeHeight) {
          throw StateError('The decoder returned an unexpected image size');
        }
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        final decodeMs = decodeWatch.elapsedMicroseconds / 1000;
        final renderWatch = Stopwatch()..start();
        stage = 'crop';
        cropped = await export.crop(decoded, format);
        decoded.dispose();
        decoded = null;
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        stage = 'render';
        rendered = await render(cropped, plan.maxSide);
        cropped.dispose();
        cropped = null;
        if (rendered.width != plan.width || rendered.height != plan.height) {
          throw StateError('The renderer clamped the requested output size');
        }
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        final renderMs = renderWatch.elapsedMicroseconds / 1000;
        final encodeWatch = Stopwatch()..start();
        stage = 'compose';
        composed = await export.compose(
          rendered,
          ExportFormat.original,
          watermark: watermark,
          layout: layout,
          values: values,
        );
        rendered.dispose();
        rendered = null;
        if (composed.width != layoutPlan.width ||
            composed.height != layoutPlan.height) {
          throw StateError('The composition clamped the requested output size');
        }
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        stage = 'encode';
        file = await export.writeFile(composed, fileType);
        final actualFileType = file.path.toLowerCase().endsWith('.png')
            ? ExportFileType.png
            : ExportFileType.jpeg;
        if (cancelled?.call() ?? false) throw const ExportCancelled();
        final encodeMs = encodeWatch.elapsedMicroseconds / 1000;
        final metadata = <String, Object?>{
          'width': composed.width,
          'height': composed.height,
          'photoLeft': layoutPlan.photo.left,
          'photoTop': layoutPlan.photo.top,
          'photoWidth': layoutPlan.photo.width,
          'photoHeight': layoutPlan.photo.height,
          'nativeWidth': source.width,
          'nativeHeight': source.height,
          'requestedQuality': quality.name,
          'quality': level.name,
          'layout': layout.name,
          'requestedFileType': fileType.name,
          'fileType': actualFileType.name,
          'textureLimit': limit,
          'estimatedBytes': estimatedBytes,
          'decodeMs': decodeMs,
          'renderMs': renderMs,
          'encodeMs': encodeMs,
        };
        log.info(
          'capture',
          'decode=${decodeMs.toStringAsFixed(0)}ms '
              'render=${renderMs.toStringAsFixed(0)}ms encode=${encodeMs.toStringAsFixed(0)}ms '
              'size=${composed.width}x${composed.height} quality=${level.name} '
              '${actualFileType.name.toUpperCase()} layout=${layout.name} '
              'requestedFileType=${fileType.name}',
        );
        final result = PhotoExport(composed, file, metadata);
        composed = null;
        file = null;
        return result;
      } catch (error, stackTrace) {
        if (error is ExportCancelled) rethrow;
        // Fail closed: generic engine exceptions, size mismatches, programming
        // errors and filesystem failures do not establish allocation pressure.
        final retryable =
            error is _ExportMemoryLimitExceeded ||
            (error is OutOfMemoryError && stage != 'progress');
        final lower = level.lower;
        log.error(
          'capture',
          'export failed quality=${level.name} stage=$stage '
              'retry=${retryable && lower != null}',
          error,
          stackTrace,
        );
        if (!retryable || lower == null) rethrow;
        log.warning(
          'capture',
          'export fallback ${level.name} -> ${lower.name} stage=$stage',
        );
        level = lower;
      } finally {
        decoded?.dispose();
        cropped?.dispose();
        rendered?.dispose();
        composed?.dispose();
        if (file != null && file.existsSync()) file.deleteSync();
      }
    }
  }
}

class ExportCancelled implements Exception {
  const ExportCancelled();
}

class _ExportMemoryLimitExceeded implements Exception {
  const _ExportMemoryLimitExceeded(this.bytes);
  final int bytes;

  @override
  String toString() =>
      'Estimated export memory $bytes bytes exceeds '
      '${ExportPlan.memoryBudgetBytes} bytes';
}
