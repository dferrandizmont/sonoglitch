# iOS status

iOS is not release-ready. Android remains the primary target. The shared Dart code and iOS project configuration do not establish that an iOS build or device flow works.

This configuration was reviewed on Windows, where CocoaPods installation, Xcode compilation, signing and iOS simulator/device testing cannot be verified.

The Apple Developer Program membership was accepted on 2026-10-28. Still to do on the Mac: register the bundle id `es.sonoglitch.app`, create the app record in App Store Connect, set the team in Xcode (Signing & Capabilities) and create the TestFlight internal testers group. The team id and certificates stay out of the repository.

## Configuration in this repository

- The Podfile and the Xcode project's Debug, Profile and Release deployment targets use iOS 16.0.
- The Podfile post-install hook enables only `PERMISSION_CAMERA=1` and `PERMISSION_MICROPHONE=1` for `permission_handler`, preserving inherited preprocessor definitions. This follows the CocoaPods example in the locked `permission_handler_apple` 9.6.4 package. Gallery permissions are handled by Gal; no photo permission macros are enabled for `permission_handler`.
- `Info.plist` describes camera use, microphone level measurement, adding photos and photo-library access to find/create the named Sonoglitch album. The broader photo-library string is needed for album access, rather than just adding an image.
- iOS has no ambient-lux channel implementation; light falls back to camera-image brightness.

## Required Mac and device verification

On a Mac with Flutter 3.47.7, Xcode and CocoaPods, resolve the locked dependencies, run `pod install` in `ios/` and inspect the resolved deployment targets and permission macros. Build the app, configure signing and test on a physical iPhone running iOS 16 or later before considering a release.

Check camera and microphone grant/deny/revocation, continuing without microphone access, level-only microphone behavior and calibration, front/back orientation and mirroring, background/foreground and covered-viewfinder lifecycle, repeated capture, crops, album creation/saving, limited or denied photo-library access and sharing. Confirm temporary-file cleanup on success and failure. No iOS build, simulator run or physical-device validation is claimed by this change.

## Checklist for the first Mac session

1. The bundle identifier is now `es.sonoglitch.app` (Runner and RunnerTests), the same as the Android application id. Set your Apple team in Xcode (Runner > Signing & Capabilities) and register that id.
2. `flutter pub get`, `cd ios && pod install`, then `flutter run` on a real iPhone (the camera does not work in the simulator).
3. Expected platform gaps, all with Dart fallbacks, to confirm on the device: no native spectrum (bass, mid, treble, rhythm and spectral tilt stay neutral, only the noise level works), no ambient-lux channel (light comes from the camera image), no native JPEG encoder (JPEG export goes through the Dart path; check quality and memory at 12 to 24 MP), and the compass and barometer of the optional context line (`NSMotionUsageDescription` is not declared: see Info.plist before enabling the barometer on iOS).
4. Verify the items listed above (permissions, orientation, mirroring, background/foreground, Save to the Photos album, Share), then record the results here.

## App Store screenshots

Sizes checked on Apple's *Screenshot specifications* page on 2026-10-29. Apple changes them, so check the page again in App Store Connect before uploading.

Rules for every file: JPEG or PNG, **no alpha channel**, from 1 to 10 screenshots per device size and per localisation. Apple scales the largest size down to the other sizes when the interface is the same on all of them, so one set is enough.

| Device | Mandatory | Accepted sizes (portrait, px) | Notes |
|---|---|---|---|
| iPhone, Dynamic Island (medium) | **Yes** | **1206 × 2622** or 1179 × 2556 | Use 1206 × 2622 (iPhone 16/17 class). |
| iPhone, Dynamic Island (large) | No | 1320 × 2868, 1290 × 2796, 1260 × 2736 | Optional. If provided, the medium size is derived from it. |
| iPad 13" | No (iPhone-only app) | 2064 × 2752 or 2048 × 2732 | Only if iPad support is added. |

### iPad: not supported

Decided on 2026-10-29: there is no iPad app. `TARGETED_DEVICE_FAMILY = 1` (iPhone only) in all Runner configurations and the iPad orientations were removed from `Info.plist`. The iPad 13" set is therefore not needed; the app can still be installed on an iPad in iPhone compatibility mode, which needs no screenshots. If iPad support is added later, the 13" set (2064 × 2752) becomes mandatory.

### Where the images come from

The camera does not work in the iOS simulator, so the viewfinder and result screens cannot be produced there. Options, in order of preference:

1. **Real iPhone with the screenshot build** (best: native status bar, native rendering). Build it on the Mac with the same define as Android and never upload it:
   `flutter build ios --release --dart-define=SONOGLITCH_SCREENSHOTS=true --dart-define=APP_VERSION=<version>-screenshots`.
   Take the captures with the side button and volume up; AirDrop them to the Mac (a PNG from the iPhone has no alpha channel).
2. **Android captures re-used on iOS** (owner's idea). The whole interface is drawn by Flutter, so the app area looks the same on both systems. Compose each image on the Mac or in Photoshop:
   - Start from a simulator screenshot of the same screen, at the exact size from the table (it brings the iOS status bar, the Dynamic Island and the home indicator).
   - Paste the app area of the Android capture (without the Android status bar and navigation bar) over the simulator one, scaled to the width of the canvas, and fill any gap above or below with the app background `#0D0D11`.
   - Export as PNG or JPEG and flatten it, so there is no alpha channel.

   Rules to keep this honest and acceptable for review (App Review expects screenshots that show the app in use):
   - Only use pixels the app really produced (a genuine capture of the app, with its real effect and its readings). Never paint or edit an effect, a number or a button by hand.
   - No trace of Android: no system bars, navigation buttons, Android fonts in the status bar or the Play Store badge.
   - Use real text of the iOS interface language of the listing (English, and Spanish for the Spanish listing).
   - Replace them with native captures as soon as the app runs on a physical iPhone; keep this route only for the first submission or for scenes that are hard to repeat.

### What to capture

The same nine screenshots as Android (`docs/readme/README.md` table; names in `.local/capturas/CHECKLIST.md`), in the same order: `01-prism-live`, `02-thermal-live`, `03-ripple-live`, `04-result-full`, `05-result-sound-strip`, `06-result-poster`, `07-before-after`, `08-landscape-result` and `09-settings` (optional). The interface is locked to portrait, but the photo follows the way the phone is held, so `08-landscape-result` is a portrait screen showing a photo taken with the phone horizontal.

Use the same scenes and the same photo for the result screens (04 to 06), so the Android and iOS listings match. Keep the folder `.local/capturas-ios/` (ignored by git) with the same names.

### After the images exist

- Upload per localisation in App Store Connect: *English (U.S.)* and *Spanish (Spain)*. The same images can be used for both only when no text of the interface is Spanish or English in them: otherwise capture each language.
- Fill the rest of the listing from the Play kit (`.local/play/PLAY_CONSOLE.es.md`): name, subtitle, description, keywords, support URL, privacy policy URL (`https://sonoglitch.mainshai.com/privacy/`), age rating questionnaire, and App Privacy: **Data Not Collected** (the app has no accounts, servers, analytics or network calls).
- Before the first submission add `ITSAppUsesNonExemptEncryption = NO` and the Spanish permission strings to `Info.plist`, add a `PrivacyInfo.xcprivacy`, and set the supported orientations (portrait) as listed in the QA plan (`docs/qa/plan-de-pruebas.md`).
- `tool/readme/process_screenshots.py` only prepares the README and Google Play versions today. When the iOS images exist, either export them by hand at the exact sizes above or extend that tool with an Apple output (exact size, flatten to RGB, PNG).
