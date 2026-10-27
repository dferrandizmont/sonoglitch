# Contributing to Sonoglitch

Sonoglitch is in early development, with pre-release alpha builds only. Read [AGENTS.md](AGENTS.md) for project conventions and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the implemented design. The Spanish product specification contains goals as well as current behavior; verify changes against the code.

Follow the [code of conduct](CODE_OF_CONDUCT.md). Use the [security policy](SECURITY.md) to report vulnerabilities privately rather than opening a public issue with sensitive details. iOS work must account for the unverified Mac/device checks in [iOS status](docs/IOS_STATUS.md).

## Setup

1. Install Flutter **3.47.7 stable**, matching `.github/workflows/ci.yml`. `pubspec.yaml` requires Dart `^3.13.5`.
2. For Android, install Java 17 and Android SDK platform 37. Use a device with Android API 29 (Android 10) or newer. Run `flutter doctor` to check your environment.
3. Clone your fork, create a focused branch such as `feat/new-style`, `fix/capture-error` or `docs/setup`, then run:

   ```sh
   flutter pub get
   flutter run --dart-define=SONOGLITCH_DEBUG=true
   ```

Keep code, comments, documentation and commit messages in English. Store metadata and app translations may use their target languages. Do not commit local machine paths, credentials, tokens, `.env` files, keystores or signing passwords.

## Changes and checks

Keep changes small and focused. Use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat: add a camera style`, `fix: handle capture failure` or `docs: clarify setup`. Do not put WIP commits on `main`. Open a pull request explaining the behavior, relevant limitations and verification.

All three checks must pass before merging:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Use `dart format .` when you need to apply formatting. If Flutter tooling rewrites `analysis_options.yaml` without an intended configuration change, restore that incidental rewrite before committing. Add meaningful tests for changed behavior. Camera orientation, permission handling, gallery export and sharing also need physical-device checks; passing unit tests does not establish those results.

Add a dependency only with a documented reason. Prefer maintained packages with a permissive license (Apache-2.0, MIT or BSD), and verify the license before adding it.

## The camera screen

The camera screen is the reference for the look of the app:

- The style pill at the bottom shows the style that is on. The arrows beside it move to the previous or the next style, and the pill opens the sheet of the styles, with the list, **Random** and **Match this place**.
- Swiping the picture changes the style as well.
- **Auto shot** is the name of the mode that takes the photo by itself on a loud sound or a sudden move. The identifiers still say "moment" (`settings.momentKeepArmed`, `viewfinderMomentTooltip`), but every string the user reads says **Auto shot**.
- The card of the three levels opens the **How it works** sheet, which explains the noise, the light and the movement in plain words.
- The diagnostics panel is opened from **Settings > Troubleshooting**. The triple tap on the preview only exists in debug builds (`--dart-define=SONOGLITCH_DEBUG=true`).

The copy lives in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb`. English is the template, both files keep the same keys and every key has a description. Run `flutter gen-l10n` after changing an ARB file, and keep the generated classes in `lib/l10n/` up to date.

## Add a style

1. Create `shaders/<style_id>.frag`. Start from an existing shader and retain the Flutter runtime-effect include, uniform declarations and their order. Compute geometry using normalized coordinates (`FlutterFragCoord().xy / uSize`), so the effect scales with image resolution.
2. Add a `StyleDefinition` with a stable unique ID, display name and shader asset path to `kRegisteredStyles` in `lib/effects/style_definition.dart`. A style becomes selectable when it does not set `isPlaceholder`; the style pill, the sheet of the styles of the viewfinder and the styles screen read the `kStyles` list derived from the registry. The registry also holds recipes that are still in development: they are marked `isPlaceholder`, they are not offered in the app, and their shaders are not part of the selectable set yet.
3. Add the one-line description of the style in `lib/features/styles/style_copy.dart`: it maps the id of the style to the `styleDesc<Id>` message of the ARB files. The registry keeps the display name free of translations.
4. Register the asset under `flutter.shaders` in `pubspec.yaml`. A registry entry alone does not bundle the shader.
5. Keep the common semantics: noise controls the intensity of the disturbance, light the tone and the contrast and motion the movement and the trails it leaves. How a shader uses them is up to the style: not every style has to displace the pixels or separate the color channels, and not every style has a vignette, bloom or flares. Keep distortion bounded, and assess recognizable subjects on a real device.
6. Verify loading, control extremes, portrait/landscape source images, crops, live preview and still rendering. Extend the relevant tests under `test/effects/`; tests that enumerate the current registry may need updating.

`EffectRenderer` in `lib/effects/effect_renderer.dart` binds the following contract. Do not reorder declarations without a coordinated renderer change:

| Float indices | GLSL uniform | Meaning |
| --- | --- | --- |
| 0–1 | `vec2 uSize` | Output width and height in pixels |
| 2 | `float uNoise` | Smoothed noise, 0–1 |
| 3 | `float uLight` | Smoothed brightness, 0–1 |
| 4 | `float uMotion` | Smoothed motion (scene, gyroscope and accelerometer), 0–1 |
| 5 | `float uTime` | Animation time in seconds |
| 6–7 | `vec2 uMotionDir` | Screen-space trail direction, faded near zero |
| 8–9 | `vec2 uUvScale` | Cover-fit texture scale |
| 10–11 | `vec2 uUvOffset` | Cover-fit texture offset |
| 12 | `float uBass` | Energy of the bass band, 0–1 |
| 13 | `float uMid` | Energy of the mid band, 0–1 |
| 14 | `float uTreble` | Energy of the treble band, 0–1 |
| 15 | `float uSeed` | Procedural pattern seed, 0–1, frozen for a capture |
| 16-19 | `vec4 uFingerprint` | Four independent 24-bit fractions; neutral `(0, 0, 0, 0)` |

The ABI is exactly **20 floats**, without std140 padding, plus sampler 0. Indices 0�15 are unchanged. The band uniforms carry filtered scalar energies measured in memory. The seed comes from the pending photo's ephemeral nonce and stays stable until the shutter; it does not drift or reroll on a style change. The six selectable recipes still only declare spectrum/seed/fingerprint; SIG-2 will consume them. Hidden styles keep their existing spectrum/seed behavior. A zero fingerprint preserves the previous rendering exactly.

All twelve fragment shaders include `signature_common.glsl` from the same directory. Only `.frag` files belong under `flutter.shaders`; the compiler resolves the relative helper include and tracks it in the depfile. The helper contains no uniforms or `#version`. Its pure functions are `signatureAspectPosition(uv, size)`, `signatureLimitOffset(totalOffsetUv, size)`, `signatureRetainOriginal(original, effected, wet)` and `signatureMicroFingerprint(color, uv, fingerprint)` (plus the arithmetic `signatureHash`). Apply the microtexture last. The total sample offset is bounded to 5% of the short side, original contribution to at least 45%, and microtexture to one RGB8 level per channel. These helpers are available for SIG-2 and are not yet called by recipes. Verify all registered shaders load, and incremental include invalidation, through the lead's shader tests before integration.

Bind `sampler2D uImage` at sampler index **0**. Apply `uUvScale` and `uUvOffset` to normalized coordinates and clamp the final texture coordinates to 0–1, as the existing shaders do. Use the same renderer contract for preview and stills. The caller owns rendered `ui.Image` instances and must dispose them; reusable renderers also have an explicit `dispose()` method.

## Capture signature foundation

`lib/ambient/signature/` owns immutable `SignatureState`, `CaptureSignature` and `CaptureIdentity`, the one-shot `PendingCaptureSignature`, `SignatureController`, and ephemeral `SignatureSource`/`SignatureReading`. It adds no subscriptions, timers, storage, network requests, PCM access or delivery-2 signals. `crypto 3.0.7` is a direct dependency for HMAC-SHA256; it was already locked transitively and its license is BSD-3-Clause.

A fresh 32-byte `Random.secure()` nonce is prepared per pending photo. Domain-separated HMAC-SHA256 derives the stable macro seed (`sonoglitch/pattern/v1`) and provisional microtexture (`sonoglitch/preview-micro/v1`). At the shutter, `AmbientController.snapshot()` consumes it once with `sonoglitch/capture/v1`, preserving P90 noise/motion and mean light while freezing the latest published filtered bands. It returns an immutable state carrying `captureSignature` and `identity`, then publishes a new pending photo. Rotation and seed copies preserve that identity. The nonce and mutable derivation buffers are cleared best effort; managed-memory secure erasure is not guaranteed.

The v1 big-endian binary message contains a version, session shot counter, UTC and monotonic microseconds, recipe version, length-prefixed UTF-8 style ID, reading count, presence/freshness masks, and per-reading age and low mantissa byte. Canonical channel order: linear acceleration x/y/z, gyro x/y/z, scalar microphone dB, scalar bass/mid/treble energies. Only the low eight float32 mantissa bits of the latest finite events are sampled. Missing, backward-clock and older-than-1500-ms readings are not fresh; stale bytes are excluded. Source ages use their injected monotonic clocks. Stop clears their transient material. Randomness is the main entropy source; sensor entropy and physical clock resolution are not guaranteed.

`sonoglitch/photo-id/v1` derives exactly eight Crockford Base32 characters (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`) from 40 bits. Example: `7K3M9Q2D`. This is a visual reference, with possible collisions, not a global identifier. Each shot gets a new signature and bounded visual variation; identical final images remain possible, especially after clipping or JPEG. Crop/quality changes and reexports retain the capture's existing ID and inputs.

`CaptureResult` already retains the immutable ambient state. Import `ambient/signature/capture_identity.dart` to access its `identity` and `captureSignature` extension getters without editing result/export-owned files. Legacy/test inputs return null. Export's owner forwards `identity?.photoId` to `ExportLayoutValues.photoId`; no ID is derived during composition. Freezing the actual renderer and moving the shutter snapshot before haptics/awaits is the separate D1.4 integration step.

Seeds, fingerprints, photo IDs and derivation material are excluded from ambient JSON and diagnostics/HUD. Existing scalar diagnostics are unchanged. Never add serialization, logging, seed import or replay for signature material. Tests inject randomness and both clocks; production must use secure randomness. Real GPU compilation, helper invalidation, rendering neutrality and perceptual/device checks remain integration gates.

## Privacy

Never record, store or transmit audio. Only the volume level and the energy of the three frequency bands may be read, in memory: no audio sample is kept, written to disk or sent anywhere. Keep camera audio capture disabled. Do not add app network requests, servers, accounts, analytics, ads or trackers. Processing stays on the device; sharing is initiated explicitly by the user through the system share sheet. Keep logs free of audio, image content and secrets, preserve absolute-path redaction and review device information and error text before posting reports publicly. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Signing a local build

A local release build is signed with the keystore described in `android/key.properties`, a file that git ignores and that never leaves your machine. It holds four keys:

| Key | Meaning |
| --- | --- |
| `storeFile` | Path to the keystore. A relative path is resolved from `android/`. |
| `storePassword` | Password of the keystore. |
| `keyAlias` | Alias of the signing key inside the keystore. |
| `keyPassword` | Password of the signing key. |

When that file exists, Gradle creates a `release` signing configuration from it and signs the release build with it. When the file is absent, the release build falls back to the debug key, which is only good for installing the app on your own device. A file that exists but cannot be read fails the build instead of falling back silently. Never commit the file or the keystore.

## Release workflow

The workflow in `.github/workflows/release.yml` runs on `v*` tags. Use a version such as `v0.1.0-alpha.1` or `v0.1.0`. Tags containing `-alpha`, `-beta` or `-rc` create GitHub prereleases; other accepted version tags create normal releases. Tag publication and releases are maintainer actions.

The workflow builds one release APK containing `android-arm64` and `android-x64`, sets the displayed `APP_VERSION` from the tag without the leading `v`, and attaches the APK and its SHA-256 file. Android's build name uses the numeric part of the version; the build number still comes from `pubspec.yaml` unless deliberately updated separately. Store version codes must increase for subsequent store submissions. The Gradle build of the workflow is debug-signed, because the keystore of the repository is not part of the checkout; the signing job replaces that signature.

The build passes `--dart-define=DONATION_URL=...` to show the optional support link; the Google Play build is made without it. See [Releasing](docs/RELEASING.md).

Optional repository secrets for signing are:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded signing keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing key alias |
| `ANDROID_KEY_PASSWORD` | Signing key password |

Configure all four or none. Partial configuration fails the job. With all four, the workflow decodes the keystore into a runner temporary file outside the checkout, aligns the built APK, replaces its debug signature using `apksigner`, verifies the result and removes the temporary key. With none, the job fails on a stable release: only a prerelease (`-alpha`, `-beta` or `-rc`) keeps Gradle's debug signature, and it adds a visible warning to the job summary and the release notes. Debug-signed builds are for testing and cannot establish a stable production signing identity. Invalid configured credentials fail the job rather than falling back. Keep the same release key for compatible updates.

## License of contributions

By submitting a contribution, you agree to license it under **Apache-2.0**, the same license as the project (inbound = outbound). Retain required notices and ensure any contributed assets or dependencies are compatible with that license. See [LICENSE](LICENSE).
