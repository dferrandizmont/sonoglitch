# Text sources of the website

Review aid, not published: the generator only reads `site.toml`, `content/`, `templates/` and `assets/`.
Each claim in `content/en.json` and the file:line that backs it. `content/es.json` says the same; the
Spanish UI labels come from `lib/l10n/app_es.arb` (lines given where they differ from the English ones).
Paths are relative to the repository root.

## Head and hero (`#about`)

| Key | Claim | Source |
|---|---|---|
| `title`, `headline` | "A camera shaped by sound, light and motion" | `README.md:4` (header alt); es `README.es.md:4` |
| `description` | Free, open source camera app for Android; sound, light and movement distort the photo | `README.md:14-17`, `README.md:33` |
| `description`, `key_facts` | No ads, no account, works offline, free, open source | `README.md:21`; es `README.es.md:21` |
| `eyebrow` | Android 10+, early alpha | `README.md:33-34`; `android/app/build.gradle.kts:27` (`minSdk = 29`) |
| `intro` | For anyone who wants a photo to show how a place sounded and felt, not only how it looked | `docs/SPEC.es.md:25` (the Instagram mention is left out) |
| `intro` | Sound level, light and movement distort the picture live in the viewfinder | `README.md:14-17`, `README.md:82` |
| `readings[].name` | Noise / Light / Movement (app labels) | `lib/l10n/app_en.arb:149,153,157`; es `app_es.arb:86-88` |
| `readings[].text` | Strength of the disturbance / tone and contrast / how much the picture moves and its trails | `README.md:76-77`; es `README.es.md:76-77` |
| meter cells | Decorative (`aria-hidden`), levels copied by eye from the first screenshot | `docs/readme/en/01-prism-live.png` |

## `#download`

| Key | Claim | Source |
|---|---|---|
| `download_intro` | Android 10 (API 29)+; iOS not released; early alpha; only test builds; compatibility, performance and image quality still need testing | `README.md:33-36` |
| downloads | APK alpha on GitHub releases; Google Play and App Store "Coming soon" with no link | `web/site.toml`; `README.md:26-35` |
| `ios_text` | The iPhone version will come from the same code but is not ready for release | `AGENTS.md:3`; `docs/IOS_STATUS.md:3` |
| `apk_note` | Each test build is an APK with its own `.sha256` file to check before installing | `README.md:42-43` |

## `#screenshots`

Alts and captions describe what each PNG shows (all eight were opened, en and es).

| Name | What it shows |
|---|---|
| 01 | Prism, live, fruit stall at night, meters top left (`PRISM 06/06`) |
| 02 | Thermal, live, same stall (`THERMAL 05/06`); "heat-camera colours and contours" is `app_en.arb:495` |
| 03 | Ripple, live, sunset over a lake with rings in the sky (`RIPPLE 04/06`) |
| 04 | Photo screen: Full layout, Portrait 4:5 crop, Retake/Share/Save (`app_en.arb:169,227,239,259,263,267`) |
| 05 | Photo screen: Sound strip layout, Original crop, Readings Full (`app_en.arb:243,507,519`) |
| 06 | Photo screen: Poster layout, Story 9:16 crop, frame with THERMAL and readings (`app_en.arb:231,247,511`) |
| 07 | **Pixel-identical to 04** (en and es). The alt only describes the visible compare button (`app_en.arb:255`) |
| 08 | Photo screen: landscape sunset, Sound strip, Original |

## `#features`

| Key | Claim | Source |
|---|---|---|
| `features_intro` | Every style uses the three readings its own way; bounded effect; subject recognisable | `README.md:77-79` |
| `styles` | The six selectable styles and their one-line descriptions | names `lib/effects/style_definition.dart:22-25` (non-placeholder ids: static, tape, phosphor, ripple, thermal, prism), `docs/SPEC.es.md:15`; texts `app_en.arb:479-499`, es `app_es.arb:215-235` |
| `features[0]` | Six styles, each a different glitch from noise, light and movement | `README.md:16-18,81` |
| `features[1]` | Effect already on the picture; swipe or style button; Random and Match this place, which picks a style and tells you why | `README.md:82`; labels `app_en.arb:471,475` (es `app_es.arb:207,211`: "Al azar", "Según el lugar"); used in `lib/features/styles/style_sheet.dart` |
| `features[2]` | Auto shot: sound crosses a threshold after a quiet second, or the scene jumps | `README.md:83`; `lib/features/viewfinder/moment_detector.dart:7-20`; label `app_en.arb:7` ("Disparo auto" `app_es.arb:7`) |
| `features[3]` | Full / Sound strip / Poster and what each adds | `app_en.arb:239-247,503-511`; es `app_es.arb:104-106,239-247`; `README.md:84` |
| `features[4]` | Original, Square 1:1, Portrait 4:5, Story 9:16 | `app_en.arb:219-231`; es `app_es.arb:99-102`; `README.md:85` |
| `features[5]` | Standard ≤2048 px, High ≤4096 px, Maximum native up to 24 MP, device limits; PNG or JPEG; save or share; press and hold to compare | `app_en.arb:408-415`; `README.md:86-87`; `app_en.arb:255,259,263` (es `Guardar`/`Compartir` `app_es.arb:109-110`) |

## `#privacy`

| Key | Claim | Source |
|---|---|---|
| `privacy_summary[0]`, `mic_steps`, FAQ 3 | Only the volume level and the energy of three bands (bass, mid, treble) are measured, in memory; buffers processed in memory then discarded; only the numbers kept, briefly, to drive the effect; no audio recorded, stored or sent | `docs/legal/politica-privacidad.en.md:12`; es `docs/legal/politica-privacidad.md:12` |
| `privacy_summary[1]` | Works entirely on the device; no accounts, ads, analytics or trackers | `politica-privacidad.en.md:5,21` |
| `privacy_summary[2]`, `glance` network row, FAQ 2 | Release builds do not declare the INTERNET permission, so no network access | `politica-privacidad.en.md:22`; `android/app/src/main/AndroidManifest.xml` (no INTERNET; only `src/debug` and `src/profile` declare it) |
| `glance` | Audio never recorded; processing on the device; no accounts/ads; no analytics/trackers | `politica-privacidad.en.md:5,12,21` |

## `#support`

| Key | Claim | Source |
|---|---|---|
| FAQ 1 | Free, no ads, no purchases; Apache-2.0; the GitHub build has an optional Ko-fi link in Settings | `README.md:14,21,114-116,120`; `docs/SPEC.es.md:4`; `politica-privacidad.en.md:33`; `lib/features/settings/settings_screen.dart:391` |
| FAQ 2 | No accounts, works offline, no INTERNET permission in release builds | `README.md:21`; `politica-privacidad.en.md:21-22` |
| FAQ 4 | Android 10 (API 29)+; early alpha; testing still needed | `README.md:33-36` |
| FAQ 5 | Google Play and F-Droid later; iOS not released; only alpha test builds on GitHub | `README.md:33-35` |
| FAQ 6 | Install steps, `.sha256` check, unknown apps, Settings > About, debug-key prereleases | `README.md:41-49`; labels `app_en.arb:287,343` (es `Ajustes > Acerca de`, `app_es.arb:116,130`; `README.es.md:45`) |
| `issue_link` | Issues can be opened in the project repository | `politica-privacidad.en.md:41`; `README.md:111` |
| `licence_text` | Apache-2.0 | `README.md:120`; `LICENSE` |
| `privacy_date` | 2026-10-27 | `politica-privacidad.en.md:3`; es `politica-privacidad.md:3` |

## Open points

- `docs/SPEC.es.md:17` says the six styles do not read the frequency bands, while the policy (`politica-privacidad.en.md:12`)
  says the bands are measured "to drive the effect". The site repeats the policy wording; the policy may need a fix.
- `07-before-after.png` is identical to `04-result-full.png`, so it shows no comparison.
