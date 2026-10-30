import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import 'camera_device.dart';
import 'photo_camera_device.dart';

/// Startup-only selection; pushing or removing the source requires a restart.
class ScreenshotPhotoSource {
  ScreenshotPhotoSource._(this.file, this.active);

  static const fileName = 'screenshot_source.jpg';
  static const androidAdbPath =
      '/sdcard/Android/data/es.sonoglitch.app/files/$fileName';
  static const inactiveStatus = 'Photo source inactive; $androidAdbPath';
  static const _description = CameraDescription(
    name: 'Screenshot photo',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 0,
  );

  final File? file;
  final bool active;

  String get status =>
      'Photo source ${active ? 'active' : 'inactive'}; '
      '${file?.path ?? androidAdbPath}';

  CameraDeviceFactory? get deviceFactory =>
      active ? (_, _) => PhotoCameraDevice(sourceFile: file!) : null;

  // A synthetic back camera keeps rotation, mirroring and flip independent of
  // the emulator's hardware. The normal camera lister is never called here.
  CameraLister? get lister => active ? () async => const [_description] : null;

  static Future<ScreenshotPhotoSource> find({
    bool enabled = AppConfig.screenshotMode,
    Future<Directory?> Function()? directory,
  }) async {
    // Do not even resolve paths without the compile-time screenshot flag.
    if (!enabled) return ScreenshotPhotoSource._(null, false);
    final folder = await (directory ?? _directory)();
    if (folder == null) return ScreenshotPhotoSource._(null, false);
    final file = File('${folder.path}/$fileName');
    return ScreenshotPhotoSource._(file, await file.exists());
  }

  static Future<Directory?> _directory() => Platform.isAndroid
      ? getExternalStorageDirectory()
      : getApplicationDocumentsDirectory();
}
