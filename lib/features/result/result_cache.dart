import 'dart:io';
import 'dart:ui' as ui;

import '../../export/export_file_type.dart';
import '../../export/export_format.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
import 'capture_result.dart';

/// CaptureResult identity also freezes the source, effect and ambient values.
/// Compare is a display-only original variant; exports always use processed.
typedef ResultCacheKey = ({
  CaptureResult capture,
  ExportFormat format,
  ExportLayout layout,
  bool watermark,
  bool contextLine,
  ExportFileType fileType,
  ExportQuality quality,
  bool original,
});

/// Owns one small preview and the already encoded full-resolution temp file.
class CachedResult {
  CachedResult(
    this.image,
    this.file, {
    this.photo = const ui.Rect.fromLTWH(0, 0, 1, 1),
    this.metadata,
  });
  final ui.Image image;
  final File file;

  /// Photo bounds in normalized preview coordinates, excluding decorations.
  final ui.Rect photo;
  final Map<String, Object?>? metadata;

  void dispose() {
    image.dispose();
    deleteResultFile(file);
  }
}

/// Four previews of at most 1024 x 1024 RGBA pixels: at most 16 MiB.
/// Full-resolution surfaces are never retained here. Files keep the export
/// service's app-cache location, sonoglitch_ name and startup 24-hour cleanup.
class ResultCache {
  static const maxEntries = 4;
  static const previewSide = 1024;
  final _entries = <ResultCacheKey, CachedResult>{};

  int get imageBytes => _entries.values.fold(
    0,
    (sum, entry) => sum + entry.image.width * entry.image.height * 4,
  );

  CachedResult? get(ResultCacheKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!entry.file.existsSync()) {
      entry.dispose();
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  void put(ResultCacheKey key, CachedResult entry) {
    if (entry.image.width > previewSide || entry.image.height > previewSide) {
      throw ArgumentError('Only bounded previews can enter the result cache');
    }
    _entries.remove(key)?.dispose();
    _entries[key] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first)!.dispose();
    }
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}

void deleteResultFile(File? file) {
  if (file == null) return;
  try {
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Best effort; startup removes app-prefixed files older than 24 hours.
  }
}
