# Website generator

The website of Sonoglitch is a static site: plain HTML and one CSS file, no
JavaScript, no external font, no analytics and no request to any third party.
It is generated with the Python 3 standard library only.

## Generate the site

From the repository root:

```sh
python tool/site/build.py
```

The output goes to `site/`, which is committed so the branch can be served as
it is. The build is reproducible: the same inputs always produce the same
bytes.

Use `--out` to write somewhere else, for example to compare the output with
the committed folder:

```sh
python tool/site/build.py --out /tmp/sonoglitch-site
```

## Test the site

```sh
python -m unittest discover -s tool/site
```

The tests check that:

- the committed `site/` folder is exactly what the generator produces;
- every page has balanced tags, a `lang` attribute, a title, a description
  and alt texts for its images;
- the alt texts are written in the language of the page;
- no page has a script, an inline event handler or an external resource;
- no stylesheet and no SVG loads anything from another host;
- the Open Graph image is an absolute address, so it works in every folder;
- the primary button keeps a contrast of 4.5:1 with its text in the dark and
  in the light palette;
- the only URLs are the ones of the repository, the website and Ko-fi, and
  all of them use `https`;
- the only email address is `dev@mainshai.com`;
- the stores are plain text, never a dead link;
- every internal link resolves to a file of the site;
- the privacy page carries every `##` heading of `docs/PRIVACY.md`.

## What the generator reads

| Path | Use |
| --- | --- |
| `assets/branding/icon.svg` | Copied to `site/img/icon.svg` and used as the icon of the pages |
| `docs/PRIVACY.md` | Converted to `site/privacy/index.html` with a small markdown converter |
| `docs/readme/NN-*.png` | The screenshots of the gallery, copied to `site/img/` as they are |
| `docs/readme/og.png` | Optional. When it exists it is copied to `site/img/og.png` and the Open Graph image tag is added |

The gallery section only appears when there is at least one screenshot. The
banner, the icon and the Open Graph image are not screenshots and are never
part of the gallery.

The screenshots are copied, never resized: the pipeline of
`tool/readme/process_screenshots.py` already writes them at most 1080 px on
the long side, and the size of every picture is read from the header of its
PNG, so the output is the same with and without Pillow.

## After adding screenshots or changing the policy

Run the build again and commit the result:

```sh
python tool/site/build.py
python -m unittest discover -s tool/site
```

The tests fail while the committed `site/` is older than its sources.

## Colours and layout

The colours come from the theme of the app (`lib/theme/app_theme.dart`): the
background `#0D0D11`, the surface `#16161C`, the violet accent `#B69CFF`, the
warm accent `#FFB37A` and the text `#F3F3F6`. The site is dark by default and
offers a light palette with `prefers-color-scheme: light`.

The glitch fringe is on the title only. It is a CSS animation, it is disabled
with `prefers-reduced-motion: reduce`, and it never moves the layout.
