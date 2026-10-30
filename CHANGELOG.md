# Changelog

What changes in each version of Sonoglitch, newest first, written for the people who use the app. The "Unreleased"
section is filled with every change and becomes the next version on the day it ships.

Numbering: the last number grows with fixes (0.1.1 → 0.1.2), the middle one with new features (→ 0.2.0) and 1.0.0 will
be the production release in the stores. Every version is published on
[GitHub](https://github.com/dferrandizmont/sonoglitch/releases) and TestFlight; Google Play and the App Store receive
several together, so numbers can be skipped. Until now versions were called 0.1.0-alpha.N; 0.1.0-alpha.21 is the last
one with that format.

## Unreleased

- The README and the contributing guide follow the common layout of the family of apps: the README is shorter, and the build, the diagnostics, the checks and the project layout move to the contributing guide.

## 0.2.0-alpha.2 · 29-Oct-2026

- Volume up and down take the photo on Android (Settings > Volume buttons).
- The first-run camera tip shows its full text at large font sizes and scrolls when space is limited.
- Photo measurement labels stay on one line on narrow screens, including with large text.
- The "Shared." message no longer appears when you close the share sheet without sending the picture.
- Permission warnings appear only after a permission request is denied.
- Android starts with a dark splash in both light and dark system modes.
- Spanish settings use the translated layout names consistently.
- Photo actions, readings and the style picker stay readable with large text and on small screens.
- Onboarding and photo actions have larger touch targets; viewfinder controls retain a 48 dp hit area around their compact icons.

## 0.1.0-alpha.21 · 27-Oct-2026

- The glitch loader now sits over the photo area while a picture is processed, so it stays in view when the controls below are scrolled.

## 0.1.0-alpha.20 · 27-Oct-2026

- A Readings selector for the Sound strip and the Poster: full (numbers and square ladders), numbers only, or hidden. The photo ID stays in every mode and the last choice is remembered.
- A glitch loader (a row of square cells with a chromatic fringe) replaces the round spinner while a photo is processed; it stays still when reduced motion is on.

## 0.1.0-alpha.19 · 27-Oct-2026

- Website regenerated from the updated privacy policy; iOS project uses the `es.sonoglitch.app` bundle id.

## 0.1.0-alpha.18 · 27-Oct-2026

- The application id is now `es.sonoglitch.app`, ready for Google Play. Older alpha builds with the previous id are separate apps and do not update to this one.
- Store descriptions rewritten for the per-shot signature and the contextual signals; the privacy policy now covers the compass, barometer and clock.

## 0.1.0-alpha.16 · 27-Oct-2026

- Each shot now also carries the moment and the place: the time of day (cold night, warm evening), the date and moon phase, the compass heading, the rhythm of the place, the spectral tilt of the sound (dark and bassy versus bright and hissy) and how colourful the scene is nudge the six styles within the same bounded distortion budget. They never replace noise, light or motion, nothing is stored or sent, and a place without a beat or a compass simply adds nothing.

- Phosphor, Ripple, Thermal, Static, Tape and Prism skip canvases smaller than one pixel.

## 0.1.0-alpha.15 · 27-Oct-2026

- Every photo gets its own signature: a random seed fixed per shot plus the three sound bands (bass, mid, treble) reshape the pattern of all six styles within a bounded distortion budget, so the subject stays recognisable and no two shots repeat the same layout. A tiny per-shot micro-fingerprint (at most one 8-bit code value per channel) is added to the final pixels.
- An 8-character photo ID such as `A3F9-17C2` is printed discreetly on the Sound strip and the Poster. It is a visual reference, not a global identifier; nothing is stored or sent.
- Optional context line (Settings, off by default) with the date and time, moon phase, compass heading and pressure of the shot on the Sound strip and Poster; read once at the shutter and kept in memory only.

- The watermark is a glitch wordmark like the project banner; the Sound strip and Poster are redesigned with square cells, spectrum ladders and a print palette.

## 0.1.0-alpha.14 · 26-Oct-2026

- A new look: squarer, instrument-like controls (4 dp corners instead of pills), one segmented style bar with the style name and a counter, segmented violet, warm and cyan meters, a shutter with a thin chromatic fringe, calmer sheets with numbered style rows, and a result screen with a single primary action (Save) and quiet square option tiles. The result photo area uses the app background instead of pure black.
- Keyboard and D-pad focus with a visible focus state on the viewfinder controls; the help sheet follows the reduced-motion setting.

- The selected style row and its press feedback were painted behind the sheet background.
- The style counter and unlit meter segments had too little contrast over bright scenes.

## 0.1.0-alpha.13 · 26-Oct-2026

- Cleaner viewfinder: one style button with previous and next arrows that opens a sheet with every style described in one line (and the Random and Match this place actions), the three level meters as a card that opens a "How it works" sheet, and a first-run hint. Nothing overlaps from 320x568 up, and every control is at least 48 dp.
- "Moment" is now "Auto shot" ("Disparo auto"), with a plain explanation: it takes the photo on a loud sound or a sudden movement. The count badge and the notice that covered the result buttons are gone; the triple tap on the image opens diagnostics only in debug builds.
- The result screen explains each layout and has larger controls; Settings is grouped into Camera and Troubleshooting and scrolls lighter.
- The "Free" badge is removed from the styles screen.
- Less background work: the native camera preview is paused when another screen covers the viewfinder, frame conversion no longer allocates per pixel, the diagnostics panel refreshes four times per second, the microphone shuts down off the main thread, and the animation clock stops while a sheet is open.

- Settings switches (watermark, Auto shot, Diagnostics) did not redraw after a tap, so a second tap could repeat the same value.
- The selected style tile now moves when another style is chosen on the styles screen.

## 0.1.0-alpha.12 · 26-Oct-2026

- An optional "Support the project" row in Settings, linking to Ko-fi, in the F-Droid and GitHub builds. The Google Play build is made without it and stays free of donation links.
- Releasing guide (`docs/RELEASING.md`), the F-Droid build recipe and the GitHub funding button.

## 0.1.0-alpha.11 · 26-Oct-2026

- Security reporting policy and a code of conduct.
- Weekly grouped minor/patch dependency update pull requests for GitHub Actions and Dart packages.
- iOS status and Mac/device validation checklist.

- The minimum Android version is now API 29 (Android 10).
- The project licence is now Apache-2.0, replacing GPL-3.0-or-later.
- Refreshed setup and architecture documentation for ambient-light blending, noise baseline/bursts, manual controls, camera lifecycle and temporary-file cleanup.
- Raised the iOS deployment target to 16.0, enabled camera/microphone permission handling and described the photo-library access needed to save into the Sonoglitch album. iOS build and device validation are still pending.
- Refreshed the public documentation: the README, the contributing guide and the Android store metadata now describe the six selectable styles, the measured frequency bands, the motion sources, the export options, the signing setup and the Apache-2.0 licence.

- The documentation and the store metadata announced twelve styles and the changelog said nine: six styles are selectable in the app (Static, Tape, Phosphor, Ripple, Thermal and Prism), and the other recipes are registered but not offered yet.
- The three frequency bands are measured in memory and printed in the export layouts, but the selectable styles do not read them, so they do not change the effect of a photo. Moment mode fires when the sound crosses a threshold after a quiet period, not at the loudest peak of a clip.
- The 24-megapixel cap of the export applies to the cropped picture: the sound strip and the poster add a band or a frame, so the exported file can be slightly larger.

## 0.1.0-alpha.1 · 24-Oct-2026

First test version.

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
