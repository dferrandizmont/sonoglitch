"""Generate Sonoglitch's README and social artwork with Python 3 and Pillow.

Run from any directory: python tool/readme/make_banner.py
Use --out to write the images somewhere else, for example to compare them with
the committed ones without touching the checkout.
Uses the existing SVG renderer without invoking its asset-writing entry point.
Typography is Roboto from Flutter's cache (Apache 2.0, roboto_license.txt);
no fonts are downloaded or copied. Set FLUTTER_ROOT if Flutter is not on PATH
or installed under ~/sdk/flutter/flutter. Identical inputs and Pillow/font
versions produce identical PNG bytes; no timestamps or random metadata are saved.
"""

import argparse
import importlib.util
import math
import os
from pathlib import Path
import random
import shutil
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/readme"
TITLE = "Sonoglitch"
TAGLINE = "The sound, light and motion around you tear your photos apart."
BACKGROUND = (13, 13, 17)
CYAN = (53, 224, 255)
MAGENTA = (255, 61, 171)
ORANGE = (255, 179, 122)
SEED = 240526
SCALE = 3


def font_directory():
    """Find the licensed SDK fonts without depending on a machine-specific path."""
    roots = []
    if os.environ.get("FLUTTER_ROOT"):
        roots.append(Path(os.environ["FLUTTER_ROOT"]))
    executable = shutil.which("flutter")
    if executable:
        roots.append(Path(executable).resolve().parent.parent)
    roots.extend((Path.home() / "sdk/flutter/flutter", Path.home() / "flutter"))
    for root in roots:
        directory = root / "bin/cache/artifacts/material_fonts"
        license_file = directory / "roboto_license.txt"
        if (
            license_file.is_file()
            and "Apache License" in license_file.read_text(encoding="utf-8")
            and all((directory / name).is_file() for name in (
                "roboto-bold.ttf", "roboto-regular.ttf"
            ))
        ):
            return directory
    raise RuntimeError(
        "Licensed Roboto fonts not found in Flutter's cache. "
        "Set FLUTTER_ROOT to an existing Flutter SDK with material_fonts."
    )


def render_icon():
    """Reuse the hand-written SVG vocabulary renderer; keep every pixel opaque."""
    spec = importlib.util.spec_from_file_location(
        "sonoglitch_icon_renderer", ROOT / "tool/icon/generate_icons.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    artwork, background = module.render_artwork()
    icon = Image.new("RGBA", artwork.size, (*background, 255))
    icon.alpha_composite(artwork)
    return icon


def background(size):
    """A low-contrast violet bloom, with the app's near-black at the edges."""
    width, height = size
    pixels = []
    for y in range(height):
        for x in range(width):
            glow = math.exp(-(
                ((x / width - 0.56) / 0.44) ** 2
                + ((y / height - 0.48) / 0.73) ** 2
            ) * 2.2)
            pixels.append((
                BACKGROUND[0] + round(15 * glow),
                BACKGROUND[1] + round(8 * glow),
                BACKGROUND[2] + round(29 * glow),
            ))
    image = Image.new("RGB", size)
    image.putdata(pixels)
    return image


def text_mask(size, text, font_path, font_size, position):
    """Supersample type once, using FreeType's portable basic layout engine."""
    mask = Image.new("L", tuple(value * SCALE for value in size))
    font = ImageFont.truetype(
        str(font_path), font_size * SCALE, layout_engine=ImageFont.Layout.BASIC
    )
    ImageDraw.Draw(mask).text(
        tuple(value * SCALE for value in position), text, font=font,
        fill=255, anchor="lt",
    )
    return mask.resize(size, Image.Resampling.LANCZOS)


def translate(mask, dx):
    """Shift with empty exposed edges, never a wrapping seam."""
    shifted = Image.new(mask.mode, mask.size)
    shifted.paste(mask, (dx, 0))
    return shifted


def add_title(image, mask, top, height):
    """Keep white letter cores; expose colour only outside a few thin slices."""
    rng = random.Random(SEED)
    # The fringe is clipped to title ink, so the tagline stays clean.
    for fraction, color, direction in (
        (0.23, CYAN, -1), (0.54, MAGENTA, 1), (0.79, ORANGE, 1)
    ):
        y = top + round(height * fraction)
        depth = rng.randint(2, 3)
        band = Image.new("L", image.size)
        band.paste(mask.crop((0, y, image.width, y + depth)), (0, y))
        fringe = ImageChops.subtract(translate(band, direction * 3), mask)
        image.paste(color, (0, 0, image.width, image.height), fringe)
    image.paste((245, 242, 255), (0, 0, image.width, image.height), mask)


def displace_slices(image, top, height):
    """Displace three strips of the complete composition by only a few pixels."""
    source = image.copy()
    rng = random.Random(SEED)
    for fraction, direction in ((0.24, -1), (0.55, 1), (0.80, -1)):
        y = top + round(height * fraction)
        depth = rng.randint(2, 3)
        dx = direction * rng.randint(2, 4)
        # Preserve the outer edge rather than wrapping it to the opposite side.
        left, right = max(0, -dx), min(image.width, image.width - dx)
        image.paste(source.crop((left, y, right, y + depth)), (left + dx, y))


def composition(size, icon, fonts):
    is_header = size == (1024, 300)
    image = background(size)
    if is_header:
        icon_x, icon_y, icon_size = 38, 40, 220
        title_x, title_y, title_size = 300, 85, 94
        tagline_y, tagline_size, line_step = 193, 23, 32
    else:
        icon_x, icon_y, icon_size = 64, 155, 320
        title_x, title_y, title_size = 440, 227, 112
        tagline_y, tagline_size, line_step = 359, 27, 38

    # Only the presentation tile is rounded. The Play Store output is square.
    tile = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    tile_mask = Image.new("L", (icon_size * SCALE, icon_size * SCALE))
    ImageDraw.Draw(tile_mask).rounded_rectangle(
        (0, 0, tile_mask.width - 1, tile_mask.height - 1),
        radius=round(icon_size * 0.22 * SCALE), fill=255,
    )
    image.paste(tile.convert("RGB"), (icon_x, icon_y), tile_mask.resize(
        tile.size, Image.Resampling.LANCZOS
    ))

    title = text_mask(size, TITLE, fonts / "roboto-bold.ttf", title_size,
                      (title_x, title_y))
    title_height = title.getbbox()[3] - title_y
    add_title(image, title, title_y, title_height)
    # A deliberate line break preserves the exact tagline, including punctuation.
    lines = ("The sound, light and motion around you", "tear your photos apart.")
    assert " ".join(lines) == TAGLINE
    for index, line in enumerate(lines):
        mask = text_mask(size, line, fonts / "roboto-regular.ttf", tagline_size,
                         (title_x + 2, tagline_y + index * line_step))
        image.paste((187, 182, 202), (0, 0, *size), mask)

    # Tiny colour registration marks echo the lens without adding visual noise.
    draw = ImageDraw.Draw(image)
    rule_y = 58 if is_header else 174
    for index, color in enumerate((CYAN, MAGENTA, ORANGE)):
        x = title_x + index * 21
        draw.line((x, rule_y, x + 12, rule_y), fill=color, width=2)
    displace_slices(image, title_y, title_height)
    return image


def generate(output=None):
    """Write the three images and return the files that were written."""
    destination = Path(output) if output else OUTPUT
    fonts = font_directory()
    icon = render_icon()
    images = {
        "header.png": composition((1024, 300), icon, fonts),
        "icon-512.png": icon.resize((512, 512), Image.Resampling.LANCZOS),
        "og.png": composition((1200, 630), icon, fonts),
    }
    destination.mkdir(parents=True, exist_ok=True)
    written = []
    for name, image in images.items():
        image.save(destination / name, format="PNG", optimize=False, compress_level=9)
        written.append(destination / name)
        print(f"Generated {destination / name}: {image.width}x{image.height} {image.mode}")
    return written


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate the banner, the icon and the Open Graph image."
    )
    parser.add_argument(
        "--out",
        default=str(OUTPUT),
        help="folder to write the images into (default: docs/readme)",
    )
    args = parser.parse_args(argv)
    generate(Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
