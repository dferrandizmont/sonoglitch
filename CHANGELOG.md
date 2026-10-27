# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use prerelease identifiers while the app is in early development.

## [0.1.0-alpha.19] - 2026-10-27

### Changed

- Website regenerated from the updated privacy policy; iOS project uses the `es.sonoglitch.app` bundle id.

## [0.1.0-alpha.18] - 2026-10-27

### Changed

- The application id is now `es.sonoglitch.app`, ready for Google Play. Older alpha builds with the previous id are separate apps and do not update to this one.
- Store descriptions rewritten for the per-shot signature and the contextual signals; the privacy policy now covers the compass, barometer and clock.

## [0.1.0-alpha.16] - 2026-10-27

### Added

- Each shot now also carries the moment and the place: the time of day (cold night, warm evening), the date and moon phase, the compass heading, the rhythm of the place, the spectral tilt of the sound (dark and bassy versus bright and hissy) and how colourful the scene is nudge the six styles within the same bounded distortion budget. They never replace noise, light or motion, nothing is stored or sent, and a place without a beat or a compass simply adds nothing.

### Changed

- Phosphor, Ripple, Thermal, Static, Tape and Prism skip canvases smaller than one pixel.

## [0.1.0-alpha.15] - 2026-10-27

### Added

- Every photo gets its own signature: a random seed fixed per shot plus the three sound bands (bass, mid, treble) reshape the pattern of all six styles within a bounded distortion budget, so the subject stays recognisable and no two shots repeat the same layout. A tiny per-shot micro-fingerprint (at most one 8-bit code value per channel) is added to the final pixels.
- An 8-character photo ID such as `A3F9-17C2` is printed discreetly on the Sound strip and the Poster. It is a visual reference, not a global identifier; nothing is stored or sent.
- Optional context line (Settings, off by default) with the date and time, moon phase, compass heading and pressure of the shot on the Sound strip and Poster; read once at the shutter and kept in memory only.

### Changed

- The watermark is a glitch wordmark like the project banner; the Sound strip and Poster are redesigned with square cells, spectrum ladders and a print palette.

## [0.1.0-alpha.14] - 2026-10-27

### Changed

- A new look: squarer, instrument-like controls (4 dp corners instead of pills), one segmented style bar with the style name and a counter, segmented violet, warm and cyan meters, a shutter with a thin chromatic fringe, calmer sheets with numbered style rows, and a result screen with a single primary action (Save) and quiet square option tiles. The result photo area uses the app background instead of pure black.
- Keyboard and D-pad focus with a visible focus state on the viewfinder controls; the help sheet follows the reduced-motion setting.

### Fixed

- The selected style row and its press feedback were painted behind the sheet background.
- The style counter and unlit meter segments had too little contrast over bright scenes.

## [0.1.0-alpha.13] - 2026-10-26

### Changed

- Cleaner viewfinder: one style button with previous and next arrows that opens a sheet with every style described in one line (and the Random and Match this place actions), the three level meters as a card that opens a "How it works" sheet, and a first-run hint. Nothing overlaps from 320x568 up, and every control is at least 48 dp.
- "Moment" is now "Auto shot" ("Disparo auto"), with a plain explanation: it takes the photo on a loud sound or a sudden movement. The count badge and the notice that covered the result buttons are gone; the triple tap on the image opens diagnostics only in debug builds.
- The result screen explains each layout and has larger controls; Settings is grouped into Camera and Troubleshooting and scrolls lighter.
- The "Free" badge is removed from the styles screen.
- Less background work: the native camera preview is paused when another screen covers the viewfinder, frame conversion no longer allocates per pixel, the diagnostics panel refreshes four times per second, the microphone shuts down off the main thread, and the animation clock stops while a sheet is open.

### Fixed

- Settings switches (watermark, Auto shot, Diagnostics) did not redraw after a tap, so a second tap could repeat the same value.
- The selected style tile now moves when another style is chosen on the styles screen.

## [0.1.0-alpha.12] - 2026-10-26

### Added

- An optional "Support the project" row in Settings, linking to Ko-fi, in the F-Droid and GitHub builds. The Google Play build is made without it and stays free of donation links.
- Releasing guide (`docs/RELEASING.md`), the F-Droid build recipe and the GitHub funding button.

## [0.1.0-alpha.11] - 2026-10-26

### Added

- Security reporting policy and a code of conduct.
- Weekly grouped minor/patch dependency update pull requests for GitHub Actions and Dart packages.
- iOS status and Mac/device validation checklist.

### Changed

- The minimum Android version is now API 29 (Android 10).
- The project licence is now Apache-2.0, replacing GPL-3.0-or-later.
- Refreshed setup and architecture documentation for ambient-light blending, noise baseline/bursts, manual controls, camera lifecycle and temporary-file cleanup.
- Raised the iOS deployment target to 16.0, enabled camera/microphone permission handling and described the photo-library access needed to save into the Sonoglitch album. iOS build and device validation are still pending.
- Refreshed the public documentation: the README, the contributing guide and the Android store metadata now describe the six selectable styles, the measured frequency bands, the motion sources, the export options, the signing setup and the Apache-2.0 licence.

### Fixed

- The documentation and the store metadata announced twelve styles and the changelog said nine: six styles are selectable in the app (Static, Tape, Phosphor, Ripple, Thermal and Prism), and the other recipes are registered but not offered yet.
- The three frequency bands are measured in memory and printed in the export layouts, but the selectable styles do not read them, so they do not change the effect of a photo. Moment mode fires when the sound crosses a threshold after a quiet period, not at the loudest peak of a clip.
- The 24-megapixel cap of the export applies to the cropped picture: the sound strip and the poster add a band or a frame, so the exported file can be slightly larger.

## [0.1.0-alpha.10] - 2026-10-26

### Added

- Six new shaders (Datamosh, Chladni, Risograph, Bleed, Kaleido, Mosaic), registered in the code and driven by the new signals, but not selectable yet. Six styles are selectable in the app: Static, Tape, Phosphor, Ripple, Thermal and Prism.
- The sound now has timbre: three frequency bands (bass, mid, treble) measured on the phone as plain numbers and printed in the export layouts, plus a seed that changes with the style and with every capture. The selectable styles do not read them yet, so the timbre does not change the picture.
- Moment mode: arm the camera and it shoots by itself when the sound crosses a threshold after a quiet second (a goal, a cheer), or when the scene jumps suddenly, with an eight second cooldown and a Keep armed option.
- Export: Sound strip and Poster layouts, a 9:16 format for stories, a high quality JPEG option and a press-and-hold before and after on the result screen.
- Privacy policy updated for the new signals; review follow-ups applied after four independent reviews.

## [0.1.0-alpha.9] - 2026-10-25

### Added

- The noise reading is much more sensitive: the quiet reference and the loud ceiling are learned per session (a loud place now reaches the top of the scale, a quiet room stays low), with a new response curve and an Intensity setting (Subtle, Normal, Extreme).
- Each photo uses the peak (90th percentile) of the last moments instead of the average, so a shout or a goal is not diluted.
- Motion now measures the scene and the camera: difference between consecutive frames with a direction, the gyroscope and the accelerometer, so panning or filming a moving crowd registers.
- Photos are rotated according to how the phone was held when shooting (landscape photos no longer come out sideways), before the crop and the watermark.
- Review follow-ups: front camera transforms, orientation filtering, false motion from auto-exposure, consistent motion directions.

## [0.1.0-alpha.8] - 2026-10-25

### Added

- Style browsing in the viewfinder: swipe horizontally on the preview to change the style (with a fading name label and a light haptic tick), a dice button for a random style, and a Smart pick button that chooses a style from the ambience (loud, dark, bright, moving or calm) and tells you why.
- Accessibility for the new controls (labels, 48 dp targets) and Spanish and English strings.
- Review follow-ups: vertical gestures no longer change the style, and the style label never names a style that is no longer selected.

## [0.1.0-alpha.7] - 2026-10-25

### Added

- Photos are saved in much higher resolution: Settings has an export quality (Standard 2048 px, High 4096 px, Maximum up to the native size and 24 megapixels), the still is captured at the highest camera resolution, cropped to 1:1 or 4:5 before rendering, drawn with the watermark at full resolution and written as lossless PNG; it falls back to a lower level when memory or the GPU limit require it.
- Three new styles: Phosphor (CRT), Ripple (shout shockwave) and Thermal (heat map), each reading noise, light and motion differently.
- Review follow-ups: clearer fallback diagnostics, the 24 megapixel ceiling is enforced on the final cropped size.

## [0.1.0-alpha.6] - 2026-10-25

### Changed

- WIP saved by delegate.sh (uncommitted agent work)
- fix: finish the pending R3 review fixes
- fix(camera): apply the pause value the action was enqueued with
- fix(result): release the source image only after compositions settle
- fix(ambient): clear the history at every manual mode change
- fix(motion): reject samples with non-finite axes
- feat(viewfinder): inject the animation clock so tests can assert on it
- fix: finish the pending R1 review fixes
- fix(shaders): invert the Y of the motion trail
- docs: repository hygiene, documentation refresh and iOS configuration
- test(viewfinder): cover the legend, the tip, the shutter and the panel
- fix(viewfinder): read the tip of the first run only once
- feat(viewfinder): keep the diagnostics panel away from the shutter
- feat(viewfinder): tell on the first run how the picture is distorted
- feat(viewfinder): confirm the shot with a flash and a tap in the hand
- feat(viewfinder): name the three levels with a legend and explain them

## [0.1.0-alpha.5] - 2026-10-25

### Changed

- Kept subjects more recognizable at maximum noise, with bounded distortion and less excessive darkening.

### Fixed

- Paused camera streaming and new frame conversion when the viewfinder is covered or the app is not in the foreground.
- Released camera controllers that finish opening after disposal and serialized camera operations to avoid competing camera lifecycles.
- Attempted cleanup of camera-created still files even if reading or decoding fails.

## [0.1.0-alpha.4] - 2026-10-24

### Added

- Android ambient-light sensor readings, blended with camera-image brightness and falling back to image brightness when unavailable.
- Adaptive noise baseline and burst response for short events such as shouts and claps.
- Manual noise/light/motion controls in diagnostics and the `SONOGLITCH_MANUAL` build define.

### Changed

- Made light, noise and movement produce more distinct responses in the three styles.

## [0.1.0-alpha.3] - 2026-10-24

### Added

- Provisional Sonoglitch app icon.

### Fixed

- Kept Save and Share unavailable until the currently selected crop has finished composing.
- Disabled Android app backups to keep private app data out of platform backups.
- Tightened tagged APK release validation and publication checks.

## [0.1.0-alpha.2] - 2026-10-24

### Added

- Contributor, architecture and privacy documentation, GitHub issue forms and a pull request checklist.
- English and Spanish Android store metadata.
- Tagged APK releases with optional release-key signing, SHA-256 checksums and prerelease labels.

### Fixed

- Updated style chips and diagnostics when the selected style changes.
- Stopped ambient sensors when the viewfinder is hidden and used the preview animation clock for still rendering.
- Prevented older crop compositions from replacing the latest result.
- Released unused renderers and image codecs, cleaned up working pictures and redacted device paths from logs.

## [0.1.0-alpha.1]

### Added

- Portrait camera viewfinder with a live fragment-shader effect and front/back camera switching.
- Smoothed microphone volume, camera-image brightness and gravity-removed phone acceleration inputs; captures use the preceding 1.5-second mean.
- Three free styles: Static, Tape and Prism.
- Separate still capture with orientation handling and a processed-image longest-side limit of 2048 pixels.
- PNG exports in original aspect ratio, centered square and centered 4:5 portrait formats.
- Gallery saving, system sharing and an optional watermark controlled in Settings.
- Camera/microphone onboarding, including continuation without microphone access.
- English and Spanish interface text and persisted watermark/diagnostics preferences.
- Triple-tap diagnostics panel, JSON reports, local rotating technical logs and user-initiated diagnostic sharing.
- Local processing without accounts, ads or app network requests; audio is never recorded or saved.
