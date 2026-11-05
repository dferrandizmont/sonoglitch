# Images of the README and of the website

This folder holds the pictures used by [README.md](../../README.md),
[README.es.md](../../README.es.md) and the website (`web/`).

| File | Use |
| --- | --- |
| `header.png` | The banner at the top of both READMEs, 1024 px wide |
| `icon-512.png` | The app icon, 512 px square |
| `og.png` | The source of the English Open Graph image of the website (`web/assets/og/en.png`) |
| `en/NN-*.png`, `es/NN-*.png` | The screenshots of each README, 1080x2400, in the order listed below |

The banner, the icon and the Open Graph image are made by
`tool/readme/make_banner.py` (Pillow required).

## The screenshots

| Name | What it shows |
| --- | --- |
| `01-prism-live.png` | The live viewfinder with the Prism style |
| `02-thermal-live.png` | The live viewfinder with the Thermal style |
| `03-ripple-live.png` | The live viewfinder with the Ripple style |
| `04-result-full.png` | The result screen with the Full export layout: the picture alone |
| `05-result-sound-strip.png` | The result screen with the Sound strip export layout, with the measured values under the picture |
| `06-result-poster.png` | The result screen with the Poster export layout, a framed print with the name of the style |
| `07-before-after.png` | The result screen with the compare button on: the original photo, without the effect |
| `08-landscape-result.png` | The result of a photo taken in horizontal |

## How the current screenshots were made

The screenshots of `en/` and `es/` were taken on the Android emulator
(1080x2400, demo status bar) with the screenshot build and its photo source
(see [RELEASING.md](../RELEASING.md)), with the app in English and in
Spanish. The effects are the real ones; the scenes are photos taken by the
developer, and the noise, light and motion readings are demo values (maximum
noise and motion). The originals stay outside the repository
(`.local/capturas/fuentes/`), with the bottom of the fireworks photo cropped
to remove advertising.

| Shots | Photo | Style |
| --- | --- | --- |
| 01 | Fireworks over a stadium | Prism |
| 02 | Human tower (castellers) | Thermal |
| 03 | Lighthouse at dusk with the moon | Ripple |
| 04 to 07 | Correfoc devil among sparks | Static |
| 08 | Sea view from a hotel (horizontal) | Phosphor |

The Google Play images are generated from them into `docs/store/` (not
published) with the `store_shots.py` tool of the shared README template.

## How to regenerate them

1. Build and install the screenshot build, push the photo source and set the
   demo status bar as described in [RELEASING.md](../RELEASING.md)
   ("Screenshot build").
2. Take the screenshots on the emulator in English and in Spanish, with the
   names of the table above, and save them in `en/` and `es/`. Keep the raw
   captures and the original photos in `.local/capturas/`, which git ignores.
3. Regenerate the Google Play images of `docs/store/` with `store_shots.py`
   and `docs/store/shots.json`.
4. Regenerate and deploy the website, which reads these screenshots.
