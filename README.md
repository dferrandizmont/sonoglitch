<p align="center">
  <img src="docs/readme/header.png" alt="Sonoglitch — a camera shaped by sound, light and motion" width="1024">
</p>

# Sonoglitch

[English](README.md) · [Español](README.es.md)

[![Licence: Apache-2.0](https://img.shields.io/badge/Licence-Apache--2.0-6E5AA8)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/dferrandizmont/sonoglitch?label=release)](https://github.com/dferrandizmont/sonoglitch/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/dferrandizmont/sonoglitch/total?label=downloads)](https://github.com/dferrandizmont/sonoglitch/releases)

Sonoglitch is a free, open source camera app that lets the surroundings shape a
photo. The sound level of the microphone, the light of the place blended with
the brightness of the camera image, and the movement of the scene and of the
phone drive a live fragment shader: six styles turn those three readings into
digital tearing, tape noise, phosphor glow, ripples, heat maps or prism
dispersion. Take a still, choose a crop and a layout, then save it to the
gallery or share it through the system share sheet. **Free, without ads,
without accounts and without network access.**

**Status: early development, pre-release alpha builds only.** Device
compatibility, performance and image quality still need testing.

## Downloads

<p>
  <a href="https://github.com/dferrandizmont/sonoglitch/releases"><img src="https://img.shields.io/badge/Available_on-GitHub-181717?logo=github&amp;style=for-the-badge" alt="Available on GitHub"></a>
  <!--
  <a href="[PLAY_URL]"><img src="https://img.shields.io/badge/Google_Play-Download-414141?logo=googleplay&amp;style=for-the-badge" alt="Available on Google Play"></a>
  <a href="[FDROID_URL]"><img src="https://img.shields.io/badge/F--Droid-Download-1976D2?logo=fdroid&amp;style=for-the-badge" alt="Available on F-Droid"></a>
  -->
</p>

Coming soon to Google Play and F-Droid.

<!--
## Screenshots

<p>
  <a href="docs/readme/01-prism-live.png"><img src="docs/readme/01-prism-live.png" width="160" alt="Live viewfinder with the Prism style"></a>
  <a href="docs/readme/02-thermal-live.png"><img src="docs/readme/02-thermal-live.png" width="160" alt="Live viewfinder with the Thermal style"></a>
  <a href="docs/readme/03-ripple-live.png"><img src="docs/readme/03-ripple-live.png" width="160" alt="Live viewfinder with the Ripple style"></a>
  <a href="docs/readme/04-result-full.png"><img src="docs/readme/04-result-full.png" width="160" alt="Result screen with the Full export layout"></a>
  <a href="docs/readme/05-result-sound-strip.png"><img src="docs/readme/05-result-sound-strip.png" width="160" alt="Result screen with the Sound strip export layout"></a>
  <a href="docs/readme/06-result-poster.png"><img src="docs/readme/06-result-poster.png" width="160" alt="Result screen with the Poster export layout"></a>
  <a href="docs/readme/07-before-after.png"><img src="docs/readme/07-before-after.png" width="160" alt="Comparison between the processed picture and the original"></a>
  <a href="docs/readme/08-landscape-result.png"><img src="docs/readme/08-landscape-result.png" width="160" alt="Result of a landscape photo"></a>
</p>

Tap a screenshot to enlarge it.
-->

## Features

- Six styles, all included: Static, Tape, Phosphor, Ripple, Thermal and Prism.
- Three ambient inputs with the same meaning in every style: noise, light and motion.
- Live viewfinder with the effect on the picture; a style button with arrows (or a swipe) changes the style, and its sheet describes every style and offers Random and Match this place, which chooses one for the ambience and tells you why.
- Auto shot: the camera takes the photo by itself when the sound crosses a threshold after a quiet second, or when the scene jumps suddenly.
- Three export layouts: the picture alone, a sound strip with the measured values, or a poster with the style name.
- Four crops: the original aspect ratio, a centred 1:1 square, a centred 4:5 portrait and a 9:16 story.
- Three quality tiers: Standard (up to 2048 px on the long side), High (up to 4096 px) and Maximum (up to the native size of the sensor), subject to the size of the original and to the limits of the device. The 24-megapixel cap applies to the cropped picture: the sound strip adds a band under it and the poster a frame and a caption, so the exported file can be slightly larger.
- PNG (lossless) or JPEG, saved to the gallery or shared through the system share sheet.
- Press and hold the photo to compare it with the original.
- Android 10 (API 29) or newer.

## How it works

Every style reads the same three normalised inputs:

| Input | Measurement | Effect |
| --- | --- | --- |
| Noise | Microphone level, read in memory | The intensity of the disturbance |
| Light | Ambient light sensor blended with the brightness of the camera image | The tone and the contrast of the picture |
| Motion | Displacement of the scene between preview frames, plus the gyroscope and the accelerometer | How much the picture moves |

The sound is also measured in three frequency bands, in memory, but the bands are
only shown in the export layouts: they do not change the effect of a photo.
The sound readings are relative and depend on the device, not calibrated
measurements. The microphone permission is optional; without it the noise
stays at zero.

The camera screen shows the three levels in a card at the top. Tapping that
card opens the **How it works** sheet, which explains the noise, the light and
the movement in plain words, how the style is changed and what **Auto shot**
does.

## Privacy

The app reads only the microphone volume level and the energy of three
frequency bands, in memory: audio is never recorded, stored or transmitted.
The processing is local, with no accounts, no ads, no analytics and no servers.
The release builds declare no `INTERNET` permission, so the app has no network
access at all.

Read the [privacy policy](docs/PRIVACY.md) for the details.

<!-- The full policy is also published on the website:
https://dferrandizmont.github.io/sonoglitch/privacy/ -->

## Support

Sonoglitch is free, without ads or accounts. The F-Droid and GitHub builds
include an optional [Ko-fi](https://ko-fi.com/danielmfdev) link in Settings;
the Google Play build has none, because Play does not allow donations outside
its own billing. See [Releasing](docs/RELEASING.md) for how the channels differ.

## License

Sonoglitch is licensed under [Apache-2.0](LICENSE). Contributions use the same
license.

---

The sections below are the technical documentation of the project.

## Build and run

Use **Flutter 3.47.7 stable**, pinned in [CI](.github/workflows/ci.yml). The Dart SDK constraint in `pubspec.yaml` is `^3.13.5`. Android development also needs Java 17, Android SDK platform 37 and an Android device running API 29 (Android 10) or newer. Install the SDK components with your normal Flutter/Android tooling and check the setup with `flutter doctor`.

From the repository root:

```sh
flutter pub get
flutter run
```

For a build with diagnostics enabled by default and an explicit displayed version:

```sh
flutter run --dart-define=SONOGLITCH_DEBUG=true --dart-define=APP_VERSION=0.1.0-alpha.18
```

`SONOGLITCH_DEBUG=true` sets the default diagnostics preference and enables the triple tap on the preview. A previously saved preference takes precedence; the **Settings > Troubleshooting > Diagnostics** switch always works. `APP_VERSION` sets the version shown in About and diagnostic reports (default `0.1.0`). It does not change the Android package version: use Flutter's `--build-name` and `--build-number` options for that.

To start with reproducible manual controls in `noise,light,motion` order:

```sh
flutter run --dart-define=SONOGLITCH_DEBUG=true --dart-define=SONOGLITCH_MANUAL=0.9,0.1,0
```

The define requires three finite numbers, each clamped to 0–1; malformed input is ignored. The diagnostics panel also provides a manual-mode switch and sliders. Manual mode overrides the published controls and uses the selected values directly for stills instead of the 1.5-second snapshot of the readings. It does not disable sensor subscriptions while the viewfinder is active.

To build a local APK:

```sh
flutter build apk --release --target-platform android-arm64,android-x64 --dart-define=APP_VERSION=0.1.0-alpha.18
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. Release builds are signed with the keystore described in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias` and `keyPassword`); a relative `storeFile` is resolved from `android/`, and the file is ignored by git. When that file is absent the Gradle build falls back to the debug key, which is only good for a local install. The [tag release workflow](.github/workflows/release.yml) signs the published APK with the repository secrets instead; see [Contributing](CONTRIBUTING.md#release-workflow). iOS configuration targets version 16.0 or later, but is not release-ready until built and verified on a Mac and physical device; see [iOS status](docs/IOS_STATUS.md).

## Diagnostics

In a debug build (`SONOGLITCH_DEBUG=true`), triple-tap the viewfinder image, leaving less than 400 ms between taps, to show or hide the diagnostic panel. A release build has no triple tap: the panel is opened from **Settings > Troubleshooting > Diagnostics**. The preference persists between sessions.

- **Copy report** in the panel copies JSON with app version/build mode, device and OS, sensor readings, camera metrics, selected style, capture timings and recent log lines.
- **Share logs** in the panel opens the system share sheet with a JSON report and the current log file when available. **Export diagnostic report** in Settings provides another route to sharing diagnostics.

Technical logs are maintained locally in all build modes, even when the panel is hidden. They rotate at 512 KiB and keep up to three files. No audio or image content is included in the diagnostic report. Absolute-path redaction is best effort; review device details, remaining paths and error text before including a report in a public issue.

## Checks and contributions

Run the same three checks as CI:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

See [Contributing](CONTRIBUTING.md), [project conventions](AGENTS.md), the [code of conduct](CODE_OF_CONDUCT.md) and the [changelog](CHANGELOG.md). Report vulnerabilities privately as described in the [security policy](SECURITY.md). The [architecture](docs/ARCHITECTURE.md) documents the pipeline, shader contract and current limitations. The [Spanish product specification](docs/SPEC.es.md) includes goals that are not all implemented.

The website is a static site generated with the Python standard library only:

```sh
python tool/site/build.py
python -m unittest discover -s tool/site
```

See [tool/site/README.md](tool/site/README.md).

## Project layout

| Path | Responsibility |
| --- | --- |
| `lib/ambient/` | Sound level/baseline/bursts, the three frequency bands, ambient lux and image brightness, scene/gyroscope/accelerometer motion and smoothing |
| `lib/camera/` | Camera stream conversion, still capture and orientation |
| `lib/effects/`, `shaders/` | Style registry, rendering and fragment shaders |
| `lib/export/` | Crops, watermark, export quality, layouts, PNG/JPEG encoding, gallery and sharing |
| `lib/features/` | Onboarding, viewfinder, styles, result and settings |
| `lib/debug/` | Local logs, reports and diagnostics panel |
| `lib/theme/`, `lib/l10n/` | UI tokens and English/Spanish localization |
| `test/` | Unit, widget and shader-related tests |
| `tool/` | Icon, screenshot and website generators |
| `docs/readme/` | Banner, icon and screenshots used by the README and the website |
| `site/` | Generated website, committed so it can be served from the branch |
| `.github/`, `fastlane/metadata/android/` | CI, release automation, templates and store text |
