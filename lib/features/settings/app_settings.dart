import 'package:flutter/foundation.dart';

import '../../app_config.dart';
import '../../ambient/signal_intensity.dart';
import '../../export/export_file_type.dart';
import '../../export/export_layout.dart';
import '../../export/export_quality.dart';
import 'preferences_store.dart';

/// The settings of the app, kept in the shared preferences.
///
/// The values are loaded once at start up and written back on every change.
class AppSettings extends ChangeNotifier {
  AppSettings({required this.store});

  /// Key of the watermark switch.
  static const String watermarkKey = 'settings.watermark';

  /// Key of the diagnostics switch.
  static const String diagnosticsKey = 'settings.diagnostics';

  /// Key of the flag that says the tip of the viewfinder was dismissed.
  static const String tipsSeenKey = 'settings.tipsSeen';

  /// Key of the switch that keeps the moment mode armed.
  static const String momentKeepArmedKey = 'settings.momentKeepArmed';

  /// Where the values are stored.
  final PreferencesStore store;

  static const volumeButtonsKey = 'settings.volumeButtons';
  bool _volumeButtonsEnabled = true;
  bool get volumeButtonsEnabled => _volumeButtonsEnabled;

  Future<void> setVolumeButtonsEnabled(bool value) async {
    if (_volumeButtonsEnabled == value) return;
    _volumeButtonsEnabled = value;
    notifyListeners();
    await store.setBool(volumeButtonsKey, value);
  }

  static const exportQualityKey = 'settings.exportQuality';
  ExportQuality _exportQuality = ExportQuality.high;
  ExportQuality get exportQuality => _exportQuality;

  Future<void> setExportQuality(ExportQuality value) async {
    if (_exportQuality == value) return;
    _exportQuality = value;
    notifyListeners();
    await store.setString(exportQualityKey, value.name);
  }

  /// Key of the layout of the export.
  static const exportLayoutKey = 'settings.exportLayout';
  ExportLayout _exportLayout = ExportLayout.full;
  ExportLayout get exportLayout => _exportLayout;

  /// Remembers the layout of the export.
  ///
  /// The layout is chosen in the result screen and it is remembered here, so
  /// the next photo starts with the layout the user left.
  Future<void> setExportLayout(ExportLayout value) async {
    if (_exportLayout == value) return;
    _exportLayout = value;
    notifyListeners();
    await store.setString(exportLayoutKey, value.name);
  }

  /// Key of the readings that the sound strip and the poster print.
  static const exportReadingsModeKey = 'settings.exportReadingsMode';
  ExportReadingsMode _exportReadingsMode = ExportReadingsMode.full;
  ExportReadingsMode get exportReadingsMode => _exportReadingsMode;

  /// Remembers which readings the export prints.
  Future<void> setExportReadingsMode(ExportReadingsMode value) async {
    if (_exportReadingsMode == value) return;
    _exportReadingsMode = value;
    notifyListeners();
    await store.setString(exportReadingsModeKey, value.name);
  }

  /// Key of the type of the file that is written.
  static const fileTypeKey = 'settings.fileType';
  ExportFileType _fileType = ExportFileType.png;
  ExportFileType get fileType => _fileType;

  /// Remembers the type of the file that is written.
  Future<void> setFileType(ExportFileType value) async {
    if (_fileType == value) return;
    _fileType = value;
    notifyListeners();
    await store.setString(fileTypeKey, value.name);
  }

  static const intensityKey = 'settings.intensity';
  SignalIntensity _intensity = SignalIntensity.normal;
  SignalIntensity get intensity => _intensity;

  Future<void> setIntensity(SignalIntensity value) async {
    if (_intensity == value) return;
    _intensity = value;
    notifyListeners();
    await store.setString(intensityKey, value.name);
  }

  static const contextLineKey = 'settings.contextLine';
  bool _contextLineEnabled = false;
  bool get contextLineEnabled => _contextLineEnabled;

  Future<void> setContextLineEnabled(bool value) async {
    if (_contextLineEnabled == value) return;
    _contextLineEnabled = value;
    notifyListeners();
    await store.setBool(contextLineKey, value);
  }

  bool _watermarkEnabled = true;
  bool _diagnosticsEnabled = false;
  bool _tipsSeen = false;
  bool _momentKeepArmed = false;
  bool _loaded = false;

  /// Whether the exported picture carries the discreet signature.
  bool get watermarkEnabled => _watermarkEnabled;

  /// Whether the on screen diagnostics panel is shown.
  bool get diagnosticsEnabled => _diagnosticsEnabled;

  /// Whether the tip of the viewfinder was already dismissed.
  ///
  /// The tip is shown until it is dismissed, so it is shown again after the
  /// settings bring it back.
  bool get tipsSeen => _tipsSeen;

  /// Whether the moment mode stays armed after every photo.
  ///
  /// When it is off, the moment mode takes one photo at the peak and stops,
  /// so the camera never takes a photo on its own without the user asking
  /// for it again.
  bool get momentKeepArmed => _momentKeepArmed;

  /// Whether the values have been read from the store.
  bool get isLoaded => _loaded;

  /// Reads the values from the store.
  Future<void> load() async {
    _volumeButtonsEnabled = await store.getBool(
      volumeButtonsKey,
      defaultValue: true,
    );
    _watermarkEnabled = await store.getBool(watermarkKey, defaultValue: true);
    _contextLineEnabled = await store.getBool(
      contextLineKey,
      defaultValue: false,
    );
    // The panel is off by default, unless the build asks for it.
    _diagnosticsEnabled = await store.getBool(
      diagnosticsKey,
      defaultValue: AppConfig.debugBuild,
    );
    _tipsSeen = await store.getBool(tipsSeenKey, defaultValue: false);
    _momentKeepArmed = await store.getBool(
      momentKeepArmedKey,
      defaultValue: false,
    );
    final quality = await store.getString(exportQualityKey);
    _exportQuality = ExportQuality.values.firstWhere(
      (value) => value.name == quality,
      orElse: () => ExportQuality.high,
    );
    final layout = await store.getString(exportLayoutKey);
    _exportLayout = ExportLayout.values.firstWhere(
      (value) => value.name == layout,
      orElse: () => ExportLayout.full,
    );
    final readingsMode = await store.getString(exportReadingsModeKey);
    _exportReadingsMode = ExportReadingsMode.values.firstWhere(
      (value) => value.name == readingsMode,
      orElse: () => ExportReadingsMode.full,
    );
    final fileType = await store.getString(fileTypeKey);
    _fileType = ExportFileType.values.firstWhere(
      (value) => value.name == fileType,
      orElse: () => ExportFileType.png,
    );
    final intensity = await store.getString(intensityKey);
    _intensity = SignalIntensity.values.firstWhere(
      (value) => value.name == intensity,
      orElse: () => SignalIntensity.normal,
    );
    _loaded = true;
    notifyListeners();
  }

  /// Turns the watermark on or off.
  Future<void> setWatermarkEnabled(bool value) async {
    if (_watermarkEnabled == value) return;
    _watermarkEnabled = value;
    notifyListeners();
    await store.setBool(watermarkKey, value);
  }

  /// Turns the diagnostics panel on or off.
  Future<void> setDiagnosticsEnabled(bool value) async {
    if (_diagnosticsEnabled == value) return;
    _diagnosticsEnabled = value;
    notifyListeners();
    await store.setBool(diagnosticsKey, value);
  }

  /// Remembers that the tip of the viewfinder was dismissed.
  Future<void> setTipsSeen(bool value) async {
    if (_tipsSeen == value) return;
    _tipsSeen = value;
    notifyListeners();
    await store.setBool(tipsSeenKey, value);
  }

  /// Shows the tip of the viewfinder again.
  Future<void> resetTips() => setTipsSeen(false);

  /// Keeps the moment mode armed after every photo, or stops it.
  Future<void> setMomentKeepArmed(bool value) async {
    if (_momentKeepArmed == value) return;
    _momentKeepArmed = value;
    notifyListeners();
    await store.setBool(momentKeepArmedKey, value);
  }
}
