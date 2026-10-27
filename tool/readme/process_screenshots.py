#!/usr/bin/env python3
"""Turn the raw phone screenshots into the images used by the README and the store.

The raw screenshots are dropped by hand in ``.local/capturas/`` (the folder is
ignored by git). Two versions are written for every screenshot:

* ``docs/readme/<name>.png``: PNG, at most 1080 px on the long side, without
  metadata. This is the one the README and the website use.
* ``docs/readme/play/<name>.png``: the version for Google Play. PNG, 24 bit, no
  alpha channel, every side between 320 px and 3840 px and a long side of at
  most twice the short side. A screenshot that is taller than 2:1 is padded
  with the background of the app (#0D0D11) until the ratio is exactly 2:1.
  The picture is never stretched and never cropped.

Two rules keep the output usable:

* the file never goes over the 8 MB that Google Play accepts: it is scaled
  down, keeping the bounds of the store, and it is encoded as a 24 bit JPEG
  when no PNG fits;
* the names are the ones of the table of ``docs/readme/README.md`` and the
  extension of the output is always ``.png``, whatever the capture was.

Pillow is the only dependency. Usage:

    python tool/readme/process_screenshots.py
"""

from __future__ import annotations

import argparse
import io
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the tool cannot work without Pillow
    print("Pillow is needed: python -m pip install Pillow", file=sys.stderr)
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / ".local" / "capturas"
DEFAULT_README = ROOT / "docs" / "readme"
DEFAULT_PLAY = DEFAULT_README / "play"

#: Background of the app, used to pad the screenshots for the store.
BACKGROUND = (0x0D, 0x0D, 0x11)

#: Longest side of the version used by the README and the website.
README_MAX_SIDE = 1080

#: Bounds Google Play asks for, and the size this tool targets.
PLAY_MIN_SIDE = 320
PLAY_MAX_SIDE = 3840

#: The long side of a store screenshot may not be more than twice the short one.
PLAY_MAX_RATIO = 2

#: Google Play accepts a screenshot of at most 8 MB.
PLAY_MAX_BYTES = 8 * 1024 * 1024

#: The shortest long side a store screenshot may have: the canvas of a 2:1
#: picture is twice the short side, so it cannot go below 640 px.
PLAY_MIN_MAX_SIDE = PLAY_MIN_SIDE * PLAY_MAX_RATIO

#: The screenshots the pipeline accepts, in the order of the README.
EXPECTED_NAMES = (
    "01-prism-live",
    "02-thermal-live",
    "03-ripple-live",
    "04-result-full",
    "05-result-sound-strip",
    "06-result-poster",
    "07-before-after",
    "08-landscape-result",
    "09-settings",
)

#: The other images of ``docs/readme/``. A capture cannot use their names.
RESERVED_NAMES = ("header", "icon-512", "og")

#: Quality of the JPEG used when no PNG fits in the size of the store.
JPEG_QUALITIES = (95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40, 35, 30, 25)

#: How many times the picture is scaled down before the JPEG is used.
SHRINK_STEPS = 8

RESAMPLING = getattr(getattr(Image, "Resampling", Image), "LANCZOS")


class ScreenshotError(Exception):
    """A capture that cannot be processed."""


def to_rgb(image: Image.Image) -> Image.Image:
    """Return the picture in RGB, without alpha and without metadata."""
    if image.mode in ("RGBA", "LA", "PA") or "transparency" in image.info:
        rgba = image.convert("RGBA")
        canvas = Image.new("RGB", rgba.size, BACKGROUND)
        canvas.paste(rgba, mask=rgba.split()[-1])
        picture = canvas
    else:
        picture = image.convert("RGB")
    picture.info.clear()
    return picture


def fit_long_side(image: Image.Image, max_side: int) -> Image.Image:
    """Scale the picture down so its long side is at most ``max_side``."""
    long_side = max(image.width, image.height)
    if long_side <= max_side:
        return image
    scale = max_side / long_side
    width = max(1, round(image.width * scale))
    height = max(1, round(image.height * scale))
    return image.resize((width, height), RESAMPLING)


def fit_ratio(width: int, height: int) -> tuple[int, int]:
    """Return a size whose long side is at most twice the short one."""
    if width >= height:
        return (min(width, PLAY_MAX_RATIO * height), height)
    return (width, min(height, PLAY_MAX_RATIO * width))


def check_play_size(size: tuple[int, int], max_side: int = PLAY_MAX_SIDE) -> None:
    """Raise when a size does not respect the bounds of the store."""
    width, height = size
    long_side = max(width, height)
    short_side = min(width, height)
    if short_side < PLAY_MIN_SIDE:
        raise ScreenshotError(
            "the short side is %d px, below the %d px of the store"
            % (short_side, PLAY_MIN_SIDE)
        )
    if long_side > max_side:
        raise ScreenshotError(
            "the long side is %d px, above the %d px of the store" % (long_side, max_side)
        )
    if long_side > PLAY_MAX_RATIO * short_side:
        raise ScreenshotError(
            "the long side is %d px, more than twice the short one" % long_side
        )


def fit_play(image: Image.Image, max_side: int = PLAY_MAX_SIDE) -> tuple[Image.Image, int]:
    """Return the store version of a picture and the padding added to it.

    The picture is padded with the background of the app until its ratio is
    exactly 2:1, and the padded canvas is scaled once, so that every side is
    between 320 px and ``max_side`` and the long side is at most twice the
    short one. The picture itself is never stretched and never cropped.
    """
    width, height = image.width, image.height
    long_side = max(width, height)
    short_side = min(width, height)

    if long_side > PLAY_MAX_RATIO * short_side:
        # The short side grows until the ratio is exactly 2:1. The padding
        # goes to the top and the bottom of a landscape picture, and to the
        # left and the right of a portrait one.
        if height >= width:
            canvas = ((height + 1) // 2, height)
        else:
            canvas = (width, (width + 1) // 2)
    else:
        canvas = (width, height)

    # One scale for the whole operation: the canvas goes inside the bounds of
    # the store and the picture is scaled with it.
    scale = min(max_side / max(canvas), max(1.0, PLAY_MIN_SIDE / min(canvas)))
    target = (
        max(1, round(canvas[0] * scale)),
        max(1, round(canvas[1] * scale)),
    )
    # The rounding of the scale can break the ratio by a pixel.
    target = fit_ratio(*target)
    check_play_size(target, max_side)

    content = (
        max(1, round(width * scale)),
        max(1, round(height * scale)),
    )
    if content[0] > target[0] or content[1] > target[1]:
        content = target
    picture = image.resize(content, RESAMPLING)
    canvas_image = Image.new("RGB", target, BACKGROUND)
    canvas_image.paste(
        picture,
        ((target[0] - content[0]) // 2, (target[1] - content[1]) // 2),
    )
    padded = canvas_image.width * canvas_image.height - content[0] * content[1]
    return canvas_image, padded


def encode_png(image: Image.Image) -> bytes:
    """Return the bytes of a PNG without metadata."""
    buffer = io.BytesIO()
    fresh = image.copy()
    fresh.info.clear()
    fresh.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def encode_jpeg(image: Image.Image, quality: int) -> bytes:
    """Return the bytes of a 24 bit JPEG."""
    buffer = io.BytesIO()
    fresh = image.convert("RGB")
    fresh.info.clear()
    fresh.save(buffer, format="JPEG", quality=quality, optimize=True)
    return buffer.getvalue()


def shrink(picture: Image.Image, max_bytes: int) -> tuple[bytes, tuple[int, int]] | None:
    """Scale the picture down until its PNG fits in ``max_bytes``.

    The bounds of the store are kept: the short side never goes below 320 px
    and the long side never grows. ``None`` is returned when the picture
    cannot be scaled any further.
    """
    current = picture
    for _ in range(SHRINK_STEPS):
        data = encode_png(current)
        if len(data) <= max_bytes:
            return data, current.size
        short_side = min(current.size)
        if short_side <= PLAY_MIN_SIDE:
            return None
        factor = math.sqrt(max_bytes / len(data)) * 0.95
        new_short = max(PLAY_MIN_SIDE, round(short_side * factor))
        factor = new_short / short_side
        width = max(1, round(current.width * factor))
        height = max(1, round(current.height * factor))
        if min(width, height) < PLAY_MIN_SIDE:
            if width <= height:
                width = PLAY_MIN_SIDE
            else:
                height = PLAY_MIN_SIDE
        size = fit_ratio(width, height)
        if size == current.size:
            return None
        current = current.resize(size, RESAMPLING)
    return None


def fit_size(
    picture: Image.Image,
    max_bytes: int = PLAY_MAX_BYTES,
) -> dict[str, object]:
    """Return the store version of a picture, at most ``max_bytes`` long.

    The picture is scaled down first, keeping the bounds of the store, and it
    is encoded as a 24 bit JPEG when no PNG fits in ``max_bytes``.
    """
    data = encode_png(picture)
    if len(data) <= max_bytes:
        return {"bytes": data, "encoding": "png", "size": picture.size, "scaled": False}

    smaller = shrink(picture, max_bytes)
    if smaller is not None:
        data, size = smaller
        return {"bytes": data, "encoding": "png", "size": size, "scaled": True}

    for quality in JPEG_QUALITIES:
        data = encode_jpeg(picture, quality)
        if len(data) <= max_bytes:
            return {
                "bytes": data,
                "encoding": "jpeg",
                "size": picture.size,
                "scaled": False,
            }

    raise ScreenshotError(
        "the screenshot does not fit in %d bytes, not even as a JPEG" % max_bytes
    )


def write_bytes(destination: Path, data: bytes) -> None:
    """Write a file, creating its folder when it is missing."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def process(
    source: Path,
    readme_dir: Path,
    play_dir: Path,
    max_side: int = PLAY_MAX_SIDE,
    max_bytes: int = PLAY_MAX_BYTES,
) -> dict[str, object]:
    """Write both versions of one screenshot and return what was written."""
    with Image.open(source) as opened:
        opened.load()
        picture = to_rgb(opened)

    stem = source.stem
    readme = fit_long_side(picture, README_MAX_SIDE)
    readme_path = readme_dir / (stem + ".png")
    write_bytes(readme_path, encode_png(readme))

    play, padded = fit_play(picture, max_side)
    fitted = fit_size(play, max_bytes)
    data = fitted["bytes"]
    encoding = str(fitted["encoding"])
    play_path = play_dir / (stem + (".jpg" if encoding == "jpeg" else ".png"))
    write_bytes(play_path, data)  # type: ignore[arg-type]

    return {
        "name": stem + ".png",
        "readme": readme.size,
        "play": fitted["size"],
        "padded": padded,
        "readme_path": readme_path,
        "play_path": play_path,
        "bytes": len(data),  # type: ignore[arg-type]
        "encoding": encoding,
        "scaled": fitted["scaled"],
    }


def sources(input_dir: Path) -> list[Path]:
    """The raw screenshots of the input folder, in a stable order."""
    if not input_dir.is_dir():
        return []
    found = [
        path
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() in (".png", ".jpg", ".jpeg")
    ]
    return sorted(found)


def validate_names(found: list[Path]) -> list[str]:
    """Check the captures and return the name of every output.

    Only the screenshots of the table of ``docs/readme/README.md`` are
    accepted, the names of the other images of the folder are reserved, and
    two captures cannot end up with the same name. The check happens before
    anything is written.
    """
    stems: dict[str, Path] = {}
    for path in found:
        stem = path.stem
        if stem in RESERVED_NAMES:
            raise ScreenshotError(
                "%s uses the reserved name '%s'" % (path.name, stem)
            )
        if stem not in EXPECTED_NAMES:
            raise ScreenshotError(
                "%s is not one of the expected screenshots (%s)"
                % (path.name, ", ".join(EXPECTED_NAMES))
            )
        if stem in stems:
            raise ScreenshotError(
                "%s and %s would both be written as %s.png"
                % (stems[stem].name, path.name, stem)
            )
        stems[stem] = path
    return list(stems)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Turn the raw screenshots into the README and the store versions."
    )
    parser.add_argument(
        "--input",
        default=str(DEFAULT_INPUT),
        help="folder with the raw screenshots (default: .local/capturas)",
    )
    parser.add_argument(
        "--readme",
        default=str(DEFAULT_README),
        help="folder for the README version (default: docs/readme)",
    )
    parser.add_argument(
        "--play",
        default=str(DEFAULT_PLAY),
        help="folder for the store version (default: docs/readme/play)",
    )
    parser.add_argument(
        "--max-side",
        type=int,
        default=PLAY_MAX_SIDE,
        help="longest side of the store version, between %d and %d (default: %d)"
        % (PLAY_MIN_MAX_SIDE, PLAY_MAX_SIDE, PLAY_MAX_SIDE),
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=PLAY_MAX_BYTES,
        help="size of the store version in bytes (default: %d)" % PLAY_MAX_BYTES,
    )
    args = parser.parse_args(argv)

    if not PLAY_MIN_MAX_SIDE <= args.max_side <= PLAY_MAX_SIDE:
        print(
            "The longest side of the store version must be between %d and %d px"
            % (PLAY_MIN_MAX_SIDE, PLAY_MAX_SIDE),
            file=sys.stderr,
        )
        return 1
    if args.max_bytes < 1:
        print("The size of the store version must be positive", file=sys.stderr)
        return 1

    input_dir = Path(args.input)
    readme_dir = Path(args.readme)
    play_dir = Path(args.play)

    found = sources(input_dir)
    if not found:
        print("No screenshot found in " + str(input_dir))
        print("Drop the raw captures there, with the names of the README:")
        print("  01-prism-live.png  02-thermal-live.png  03-ripple-live.png")
        print("  04-result-full.png  05-result-sound-strip.png  06-result-poster.png")
        print("  07-before-after.png  08-landscape-result.png  09-settings.png")
        return 1

    try:
        validate_names(found)
        rows = [
            process(path, readme_dir, play_dir, args.max_side, args.max_bytes)
            for path in found
        ]
    except ScreenshotError as error:
        print(str(error), file=sys.stderr)
        return 1

    print("Written %d screenshots" % len(rows))
    print()
    print("%-26s %-14s %-16s %-10s %s" % ("name", "readme", "play", "size", "note"))
    print("%-26s %-14s %-16s %-10s %s" % ("-" * 26, "-" * 14, "-" * 16, "-" * 10, "-" * 12))
    for row in rows:
        readme = "%dx%d" % row["readme"]
        play = "%dx%d" % row["play"]
        size = "%d kB" % round(int(row["bytes"]) / 1024)
        notes = []
        if row["padded"]:
            notes.append("padded to 2:1")
        if row["scaled"]:
            notes.append("scaled to fit")
        if row["encoding"] != "png":
            notes.append("JPEG")
        print(
            "%-26s %-14s %-16s %-10s %s"
            % (row["name"], readme, play, size, ", ".join(notes))
        )
    print()
    print("README version: " + str(readme_dir))
    print("Store version:  " + str(play_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
