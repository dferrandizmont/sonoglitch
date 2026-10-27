import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// What the app knows about the device it runs on.
///
/// It is shown in the diagnostics panel and in the exported report, and it
/// never contains anything personal: only the model of the phone and the
/// version of the system.
class DeviceSummary {
  const DeviceSummary({
    required this.model,
    required this.systemVersion,
    required this.platform,
  });

  /// The model of the phone, for example "Pixel 10 Pro".
  final String model;

  /// The version of the operating system.
  final String systemVersion;

  /// The name of the platform, "Android" or "iOS".
  final String platform;

  /// Reads the information from the system.
  static Future<DeviceSummary> load() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        return DeviceSummary(
          model: info.model,
          systemVersion: 'Android ${info.version.release}',
          platform: 'Android',
        );
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        return DeviceSummary(
          model: info.model,
          systemVersion: 'iOS ${info.systemVersion}',
          platform: 'iOS',
        );
      }
    } catch (error) {
      debugPrint(
        'DeviceSummary: the device information is not available: $error',
      );
    }
    return const DeviceSummary(
      model: 'unknown',
      systemVersion: 'unknown',
      platform: 'unknown',
    );
  }

  /// The information as a map, for the JSON report.
  Map<String, Object?> toJson() => {
    'model': model,
    'systemVersion': systemVersion,
    'platform': platform,
  };
}
