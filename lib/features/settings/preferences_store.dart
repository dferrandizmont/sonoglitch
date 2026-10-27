import 'package:shared_preferences/shared_preferences.dart';

/// A tiny key value store for the settings.
///
/// The interface exists so the settings can be tested with an in memory
/// store, without the platform plugin.
abstract class PreferencesStore {
  /// Reads a boolean.
  Future<bool> getBool(String key, {required bool defaultValue});

  Future<String?> getString(String key);
  Future<void> setString(String key, String value);

  /// Writes a boolean.
  Future<void> setBool(String key, bool value);
}

/// The real store, backed by `shared_preferences`.
class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore({this.preferences});

  /// The preferences to use, loaded on demand when it is null.
  SharedPreferences? preferences;

  Future<SharedPreferences> get _prefs async =>
      preferences ??= await SharedPreferences.getInstance();
  @override
  Future<bool> getBool(String key, {required bool defaultValue}) async {
    final preferences = await _prefs;
    return preferences.getBool(key) ?? defaultValue;
  }

  @override
  Future<String?> getString(String key) async => (await _prefs).getString(key);
  @override
  Future<void> setString(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    final preferences = await _prefs;
    await preferences.setBool(key, value);
  }
}

/// A store that keeps everything in memory, used by the tests.
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore([Map<String, bool>? initial])
    : _values = {...?initial};

  final Map<String, bool> _values;
  final Map<String, String> _strings = {};
  @override
  Future<String?> getString(String key) async => _strings[key];
  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }

  @override
  Future<bool> getBool(String key, {required bool defaultValue}) async =>
      _values[key] ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }
}
