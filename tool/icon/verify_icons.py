"""Check every icon, resource reference, safe zone and optional byte determinism."""

import argparse
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageColor

sys.dont_write_bytecode = True
from generate_icons import DENSITIES, IOS, RES, ROOT, SVG, generate  # noqa: E402


ANDROID = "{http://schemas.android.com/apk/res/android}"


def open_png(path, size, mode):
    with Image.open(path) as image:
        image.load()
        assert image.format == "PNG", path
        assert image.size == (size, size), (path, image.size)
        assert image.mode == mode, (path, image.mode)
        return image.copy()


def safe_zone(image):
    """Even faint antialiasing must stay in the central 66% diameter circle."""
    alpha = image.getchannel("A")
    size = image.width
    radius_squared = max(
        ((x + 0.5 - size / 2) ** 2 + (y + 0.5 - size / 2) ** 2)
        for y in range(size) for x in range(size) if alpha.getpixel((x, y))
    )
    radius = radius_squared ** 0.5 / size
    assert radius <= 0.33, radius
    return radius


def luminance(rgb):
    def linear(value):
        value /= 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return sum(weight * linear(value) for weight, value in zip((0.2126, 0.7152, 0.0722), rgb))


def verify():
    paths = set()
    max_radius = 0
    svg = ET.parse(SVG).getroot()
    background_hex = svg.find(".//*[@id='background']").attrib["fill"]
    background = ImageColor.getrgb(background_hex)
    colours = {node.attrib["stroke"] for node in svg.iter() if "stroke" in node.attrib}
    assert colours == {"#B9A6FF", "#55E5F2", "#F36CCB", "#FFB784"}, colours
    contrasts = {
        colour: (luminance(ImageColor.getrgb(colour)) + 0.05) / (luminance(background) + 0.05)
        for colour in sorted(colours)
    }
    assert min(contrasts.values()) >= 4.5, contrasts

    for density, size in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        for name in ("ic_launcher", "ic_launcher_round"):
            path = folder / f"{name}.png"
            image = open_png(path, size, "RGBA")
            assert image.getpixel((0, 0))[3] == 0, path
            assert image.getpixel((size // 2, size // 2)) == (*background, 255), path
            assert image.getpixel((size // 2, 0))[3] >= 250, path
            paths.add(path)
        layers = []
        for name in ("foreground", "monochrome"):
            path = folder / f"ic_launcher_{name}.png"
            image = open_png(path, size * 9 // 4, "RGBA")
            max_radius = max(max_radius, safe_zone(image))
            assert image.getchannel("A").getextrema() == (0, 255), path
            if name == "monochrome":
                assert {pixel[:3] for pixel in image.getdata() if pixel[3]} == {(255, 255, 255)}, path
            layers.append(image)
            paths.add(path)
        assert layers[0].getchannel("A").tobytes() == layers[1].getchannel("A").tobytes()

    for name in ("foreground", "monochrome"):
        alias = ET.parse(RES / f"drawable/ic_launcher_{name}.xml").getroot()
        assert alias.tag == "bitmap"
        assert alias.attrib[ANDROID + "src"] == f"@mipmap/ic_launcher_{name}"
        assert alias.attrib[ANDROID + "gravity"] == "fill"
    for name in ("ic_launcher", "ic_launcher_round"):
        adaptive = ET.parse(RES / f"mipmap-anydpi-v26/{name}.xml").getroot()
        assert adaptive.tag == "adaptive-icon"
        assert {child.tag: child.attrib[ANDROID + "drawable"] for child in adaptive} == {
            "background": "@color/ic_launcher_background",
            "foreground": "@drawable/ic_launcher_foreground",
            "monochrome": "@drawable/ic_launcher_monochrome",
        }
    colour_resource = ET.parse(RES / "values/ic_launcher_background.xml").getroot()
    assert colour_resource.find("color").attrib["name"] == "ic_launcher_background"
    assert colour_resource.find("color").text == background_hex

    catalog = json.loads((IOS / "Contents.json").read_text(encoding="utf-8"))
    for entry in catalog["images"]:
        width, height = entry["size"].split("x")
        scale = Decimal(entry["scale"].removesuffix("x"))
        assert width == height
        size = int(Decimal(width) * scale)
        path = IOS / entry["filename"]
        image = open_png(path, size, "RGB")
        # All iOS exports are opaque squares; iOS supplies its own corner mask.
        assert image.getpixel((0, 0)) == background, path
        assert image.getpixel((size - 1, size - 1)) == background, path
        if entry["idiom"] == "ios-marketing":
            assert size == 1024 and "A" not in image.getbands(), path
        paths.add(path)
    actual = set(IOS.glob("*.png"))
    actual.update(RES.glob("mipmap-*/ic_launcher*.png"))
    actual.update((ROOT / "assets/branding").glob("*.png"))
    assert actual == paths, (actual - paths, paths - actual)
    assert len(paths) == 35, len(paths)
    print(f"PASS: {len(paths)} PNGs; sizes, modes, masks, iOS opacity, Android XML references.")
    print(f"PASS: all adaptive pixels inside radius {max_radius:.2%} (limit 33.00%).")
    print("Palette contrast on background: " + ", ".join(f"{c} {r:.2f}:1" for c, r in contrasts.items()))


def output_hashes():
    paths = list((ROOT / "assets/branding").glob("*"))
    paths.extend(RES.glob("mipmap-*/ic_launcher*"))
    paths.extend(RES.glob("drawable/ic_launcher*"))
    paths.append(RES / "values/ic_launcher_background.xml")
    paths.extend(IOS.glob("*"))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths if path.is_file()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-determinism", action="store_true", help="Regenerate twice and compare all asset bytes")
    args = parser.parse_args()
    verify()
    if args.check_determinism:
        original = output_hashes()
        for _ in range(2):
            generate()
            assert output_hashes() == original, "Regeneration changed output bytes"
        print("PASS: two regenerations are byte-identical to the checked-in assets.")
