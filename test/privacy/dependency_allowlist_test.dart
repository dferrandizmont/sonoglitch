import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every package that may appear in `pubspec.lock`, direct and transitive.
///
/// The app promises that it never touches the network, so a new dependency is
/// a privacy change until somebody has looked at it: it may open a socket,
/// and it may carry a licence that the project does not accept. Add a package
/// here only after checking both.
const Set<String> allowedPackages = {
  // The Flutter SDK and the tool chain of the tests.
  'flutter',
  'flutter_lints',
  'flutter_localizations',
  'flutter_plugin_android_lifecycle',
  'flutter_test',
  'flutter_web_plugins',
  'sky_engine',
  'async',
  'boolean_selector',
  'characters',
  'clock',
  'collection',
  'fake_async',
  'matcher',
  'material_color_utilities',
  'meta',
  'path',
  'source_span',
  'stack_trace',
  'stream_channel',
  'stream_transform',
  'string_scanner',
  'term_glyph',
  'test_api',
  'vector_math',
  'vm_service',
  'web',

  // The packages the app depends on.
  'camera',
  'camera_android_camerax',
  'camera_avfoundation',
  'camera_platform_interface',
  'camera_web',
  'crypto',
  'device_info_plus',
  'device_info_plus_platform_interface',
  'gal',
  'intl',
  'noise_meter',
  'path_provider',
  'path_provider_android',
  'path_provider_foundation',
  'path_provider_linux',
  'path_provider_platform_interface',
  'path_provider_windows',
  'permission_handler',
  'permission_handler_android',
  'permission_handler_apple',
  'permission_handler_html',
  'permission_handler_platform_interface',
  'permission_handler_windows',
  'sensors_plus',
  'sensors_plus_platform_interface',
  'share_plus',
  'share_plus_platform_interface',
  'shared_preferences',
  'shared_preferences_android',
  'shared_preferences_foundation',
  'shared_preferences_linux',
  'shared_preferences_platform_interface',
  'shared_preferences_web',
  'shared_preferences_windows',
  'url_launcher',
  'url_launcher_android',
  'url_launcher_ios',
  'url_launcher_linux',
  'url_launcher_macos',
  'url_launcher_platform_interface',
  'url_launcher_web',
  'url_launcher_windows',

  // The packages that the plugins and the tool chain pull in.
  'args',
  'audio_streamer',
  'code_assets',
  'cross_file',
  'ffi',
  'ffi_leak_tracker',
  'file',
  'fixnum',
  'hooks',
  'jni',
  'jni_flutter',
  'jni_util',
  'leak_tracker',
  'leak_tracker_flutter_testing',
  'leak_tracker_testing',
  'lints',
  'logging',
  'mime',
  'objective_c',
  'package_config',
  'platform',
  'plugin_platform_interface',
  'pub_semver',
  'record_use',
  'uuid',
  'win32',
  'win32_registry',
  'xdg_directories',
  'yaml',

  // The local package with the GPU test oracles. It is a dev dependency, so
  // it never reaches a release build.
  'sonoglitch_test_shaders',
};

/// The message that tells the next person what to do with a new package.
const String newDependencyMessage =
    'New dependency: check its licence and that it adds no network access, '
    'then add it to the list';

void main() {
  test('pubspec.lock only holds allow-listed packages', () {
    final lock = File('pubspec.lock');
    expect(
      lock.existsSync(),
      isTrue,
      reason: 'pubspec.lock is missing: run flutter pub get',
    );
    final packages = lockedPackages(lock.readAsStringSync());
    expect(packages, isNotEmpty);
    expect(
      packages.difference(allowedPackages),
      isEmpty,
      reason: newDependencyMessage,
    );
  });

  test('the allow-list holds no package that the lock file has dropped', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue);
    expect(
      allowedPackages.difference(lockedPackages(lock.readAsStringSync())),
      isEmpty,
      reason:
          'Stale entry in the allow-list: remove it or restore the '
          'dependency',
    );
  });
}

/// The names of the packages of the `packages:` section of a pub lock file.
///
/// The lock file is YAML, but its shape is fixed: a `packages:` mapping with
/// one two-space indented key per package, and the `sdks:` section after it.
/// Reading that shape keeps the check free of a YAML dependency.
Set<String> lockedPackages(String lock) {
  final names = <String>{};
  var inPackages = false;
  for (final line in const LineSplitter().convert(lock)) {
    if (line.isEmpty || line.trimLeft().startsWith('#')) {
      continue;
    }
    if (!line.startsWith(' ')) {
      inPackages = line.startsWith('packages:');
      continue;
    }
    if (!inPackages) {
      continue;
    }
    final match = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
    if (match != null) {
      names.add(match.group(1)!);
    }
  }
  return names;
}
