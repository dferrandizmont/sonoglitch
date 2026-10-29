/// Build time constants.
///
/// Everything that is baked into the binary lives here so it can be found in
/// one place: the version shown in Settings, the donation link and the debug
/// flags.
class AppConfig {
  const AppConfig._();

  /// Human readable application name.
  static const String appName = 'Sonoglitch';

  /// Version shown in the About section.
  ///
  /// Overridable at build time with
  /// `--dart-define=APP_VERSION=1.2.3`.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  /// When true the diagnostics HUD is enabled by default.
  ///
  /// Set with `--dart-define=SONOGLITCH_DEBUG=true`.
  static const bool debugBuild = bool.fromEnvironment('SONOGLITCH_DEBUG');

  /// Private screenshot tooling. Never enable in a published build.
  static const bool screenshotMode = bool.fromEnvironment(
    'SONOGLITCH_SCREENSHOTS',
  );

  /// The values of the three controls set by hand, as `noise,light,motion`.
  ///
  /// Overridable at build time with
  /// `--dart-define=SONOGLITCH_MANUAL=0.9,0.1,0`. The app then starts in
  /// manual mode with those values, so a screenshot or a test of the
  /// effects can be reproduced.
  static const String manualOverride = String.fromEnvironment(
    'SONOGLITCH_MANUAL',
  );

  /// The manual values of the three controls, or null when the build does
  /// not ask for them.
  static List<double>? get manualValues => parseManualValues(manualOverride);

  /// Whether the app starts with the values set by hand.
  static bool get manualMode => manualValues != null;

  /// Reads a list of three values, as `noise,light,motion`.
  ///
  /// The values are clamped to the 0..1 scale and a malformed list is
  /// ignored, so a broken define never breaks the app.
  static List<double>? parseManualValues(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parts = text.split(',');
    if (parts.length != 3) return null;
    final values = <double>[];
    for (final part in parts) {
      final value = double.tryParse(part.trim());
      if (value == null || !value.isFinite) return null;
      values.add(value.clamp(0.0, 1.0));
    }
    return values;
  }

  /// Link behind the "Support the project" row.
  ///
  /// Empty means the row is hidden. The Google Play build is made without it
  /// (the app is free and shows no donation link there); the F-Droid and GitHub
  /// builds set it with `--dart-define=DONATION_URL=...`.
  static const String donationUrl = String.fromEnvironment(
    'DONATION_URL',
    defaultValue: '',
  );

  /// Album used when saving to the gallery.
  static const String galleryAlbum = 'Sonoglitch';

  /// Licence of the project.
  static const String license = 'Apache-2.0';
}
