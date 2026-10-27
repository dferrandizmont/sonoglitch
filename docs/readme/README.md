# Images of the README and of the website

This folder holds the pictures used by [README.md](../../README.md),
[README.es.md](../../README.es.md) and the [website](../../tool/site/README.md).

| File | Use |
| --- | --- |
| `header.png` | The banner at the top of both READMEs, 1024 px wide |
| `icon-512.png` | The app icon, 512 px square |
| `og.png` | The Open Graph image of the website, only used when it exists |
| `NN-*.png` | The screenshots, in the order they are listed below |
| `play/NN-*.png` | The same screenshots prepared for Google Play |

The banner, the icon and the Open Graph image are made by
`tool/readme/make_banner.py`. The screenshots are processed by
`tool/readme/process_screenshots.py`.

## The screenshots

| Name | What it shows |
| --- | --- |
| `01-prism-live.png` | The live viewfinder with the Prism style |
| `02-thermal-live.png` | The live viewfinder with the Thermal style |
| `03-ripple-live.png` | The live viewfinder with the Ripple style |
| `04-result-full.png` | The result screen with the Full export layout: the picture alone |
| `05-result-sound-strip.png` | The result screen with the Sound strip export layout, with the measured values under the picture |
| `06-result-poster.png` | The result screen with the Poster export layout, a framed print with the name of the style |
| `07-before-after.png` | The comparison between the processed picture and the original |
| `08-landscape-result.png` | The result of a photo taken in horizontal |
| `09-settings.png` | The Settings screen, optional |

Only these names are accepted, and the extension of the output is always
`.png`, whatever the extension of the capture was. The names of the other
images of the folder (`header`, `icon-512` and `og`) are reserved: a capture
cannot overwrite them. The tool checks every name before it writes anything,
and refuses the run when one is unexpected or when two captures would end up
with the same name.

The section of the README that shows the screenshots is inside an HTML comment
until the pictures exist. Uncomment it once the files are here.

## How to regenerate them

1. Take the screenshots on a phone with the app and copy them to
   `.local/capturas/`, with the names of the table above. The folder is
   ignored by git, so the raw captures never enter the repository.
2. Run the pipeline, with Pillow installed:

   ```sh
   python tool/readme/process_screenshots.py
   ```

3. Regenerate the website, because it copies the screenshots:

   ```sh
   python tool/site/build.py
   ```

4. Run the tests:

   ```sh
   python -m unittest discover -s tool/readme -p "test_process_screenshots.py"
   python -m unittest discover -s tool/site
   ```

The tool prints a table with the size of every file it writes.

## The two versions

The version of this folder is the one the README and the website use: PNG, at
most 1080 px on the long side, and no metadata.

The version of `play/` is the one Google Play accepts: PNG in 24 bit with no
alpha channel, every side between 320 px and 3840 px, and a long side of at
most twice the short side. A phone screenshot in vertical is taller than 2:1,
so it is padded with the background of the app (`#0D0D11`) until the ratio is
exactly 2:1. The picture itself is never stretched and never cropped. One
scale is computed for the whole picture, so the padded canvas and the picture
inside it always respect both limits at the same time.

Google Play also accepts a file of at most 8 MB. The tool checks the bytes
of the file it writes: if the PNG is too big, the picture is scaled down
inside the same limits, and if no PNG fits, it is written as a 24 bit JPEG
with a lower quality. The extension of the file of the store follows the
encoding, and the table the tool prints says which one was used.

The longest side of the store version can be changed with `--max-side`, but
it has to stay between 640 px (twice the minimum side) and 3840 px, the
maximum the store accepts.
