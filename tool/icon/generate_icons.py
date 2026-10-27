"""Render the deliberately small icon.svg vocabulary with Pillow, without I/O beyond owned assets."""

from decimal import Decimal
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageColor, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
SVG = ROOT / "assets/branding/icon.svg"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
CANVAS = 1024
SUPERSAMPLE = 4
ADAPTIVE_SCALE = 0.86
NS = "{http://www.w3.org/2000/svg}"


def render_artwork():
    """Read geometry, translations, clipping and colour directly from the SVG.

    This is intentionally not a general SVG renderer. Unsupported artwork fails
    loudly rather than silently producing an icon different from its source.
    """
    svg = ET.parse(SVG).getroot()
    assert svg.attrib["viewBox"] == "0 0 1024 1024"
    elements = {node.attrib["id"]: node for node in svg.iter() if "id" in node.attrib}
    size = CANVAS * SUPERSAMPLE

    def blank():
        return Image.new("RGBA", (size, size))

    def render(node, offset=0, stroke=None):
        tag = node.tag.removeprefix(NS)
        offset += float(node.get("x", "0")) if tag == "use" else 0
        stroke = node.get("stroke", stroke)
        layer = blank()
        if tag == "g":
            transform = node.get("transform")
            if transform:
                match = re.fullmatch(r"translate\((-?\d+) 0\)", transform)
                if not match:
                    raise ValueError(f"Unsupported transform: {transform}")
                offset += float(match[1])
            for child in node:
                layer.alpha_composite(render(child, offset, stroke))
        elif tag == "use":
            layer = render(elements[node.attrib["href"].removeprefix("#")], offset, stroke)
        elif tag == "circle":
            cx = float(node.attrib["cx"]) + offset
            cy = float(node.attrib["cy"])
            radius = float(node.attrib["r"])
            half_width = float(node.attrib["stroke-width"]) / 2
            mask = Image.new("L", (size, size))
            draw = ImageDraw.Draw(mask)
            for r, fill in ((radius + half_width, 255), (radius - half_width, 0)):
                draw.ellipse(
                    tuple(v * SUPERSAMPLE for v in (cx - r, cy - r, cx + r, cy + r)),
                    fill=fill,
                )
            layer.paste(ImageColor.getrgb(stroke), (0, 0, size, size), mask)
        else:
            raise ValueError(f"Unsupported artwork element: {tag}")
        clip = node.get("clip-path")
        if clip:
            clip_node = elements[clip.removeprefix("url(#").removesuffix(")")]
            assert len(clip_node) == 1 and clip_node[0].tag == NS + "rect"
            rect = clip_node[0]
            x = float(rect.get("x", "0")) + offset
            y = float(rect.get("y", "0"))
            width, height = float(rect.attrib["width"]), float(rect.attrib["height"])
            mask = Image.new("L", (size, size))
            # Pillow rectangle endpoints are inclusive; SVG's upper edge is not.
            ImageDraw.Draw(mask).rectangle(
                (round(x * SUPERSAMPLE), round(y * SUPERSAMPLE),
                 round((x + width) * SUPERSAMPLE) - 1,
                 round((y + height) * SUPERSAMPLE) - 1), fill=255,
            )
            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        return layer

    artwork = render(elements["artwork"]).resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
    background = ImageColor.getrgb(elements["background"].attrib["fill"])
    return artwork, background


def save_png(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def save_text(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8", newline="\n")


def masked_legacy(master, size, rounded):
    scaled = master.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    mask_size = size * SUPERSAMPLE
    mask = Image.new("L", (mask_size, mask_size))
    draw = ImageDraw.Draw(mask)
    box = (0, 0, mask_size - 1, mask_size - 1)
    if rounded:
        draw.rounded_rectangle(box, radius=round(mask_size * 0.22), fill=255)
    else:
        draw.ellipse(box, fill=255)
    scaled.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return scaled


def generate():
    artwork, background = render_artwork()
    master = Image.new("RGB", artwork.size, background)
    master.paste(artwork, mask=artwork.getchannel("A"))
    adaptive = Image.new("RGBA", artwork.size)
    mark_size = round(CANVAS * ADAPTIVE_SCALE)
    mark = artwork.resize((mark_size, mark_size), Image.Resampling.LANCZOS)
    inset = (CANVAS - mark_size) // 2
    adaptive.paste(mark, (inset, inset))
    monochrome = Image.new("RGBA", adaptive.size, "white")
    monochrome.putalpha(adaptive.getchannel("A"))

    for density, size in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        save_png(masked_legacy(master, size, rounded=True), folder / "ic_launcher.png")
        save_png(masked_legacy(master, size, rounded=False), folder / "ic_launcher_round.png")
        foreground_size = size * 9 // 4  # 108dp versus a 48dp legacy icon.
        for name, layer in (("foreground", adaptive), ("monochrome", monochrome)):
            save_png(
                layer.resize((foreground_size, foreground_size), Image.Resampling.LANCZOS),
                folder / f"ic_launcher_{name}.png",
            )

    # A drawable alias lets Android select the density-specific mipmap bitmap.
    for name in ("foreground", "monochrome"):
        save_text(RES / f"drawable/ic_launcher_{name}.xml", f'''<?xml version="1.0" encoding="utf-8"?>
<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@mipmap/ic_launcher_{name}" android:gravity="fill" />
''')
    background_hex = "#" + "".join(f"{channel:02X}" for channel in background)
    save_text(RES / "values/ic_launcher_background.xml", f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{background_hex}</color>
</resources>
''')
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''
    for name in ("ic_launcher", "ic_launcher_round"):
        save_text(RES / f"mipmap-anydpi-v26/{name}.xml", xml)

    catalog = json.loads((IOS / "Contents.json").read_text(encoding="utf-8"))
    for entry in catalog["images"]:
        width, height = entry["size"].split("x")
        scale = Decimal(entry["scale"].removesuffix("x"))
        dimensions = (int(Decimal(width) * scale), int(Decimal(height) * scale))
        save_png(master.resize(dimensions, Image.Resampling.LANCZOS), IOS / entry["filename"])
    print("Generated 20 Android PNGs, 5 Android XML resources and 15 iOS PNGs.")


if __name__ == "__main__":
    generate()
