"""Exercise the real generator and its delivered PNGs, without extra artifacts.

The generator writes into temporary folders, so the test never touches the
checkout, and the committed images of ``docs/readme/`` are compared with the
ones the generator produces.
"""

import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageStat


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "header.png": ((1024, 300), "RGB"),
    "icon-512.png": ((512, 512), "RGBA"),
    "og.png": ((1200, 630), "RGB"),
}


def luminance(pixel):
    def linear(channel):
        value = channel / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return sum(weight * linear(channel) for weight, channel in zip(
        (0.2126, 0.7152, 0.0722), pixel[:3]
    ))


class BannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        cls.committed = {name: ROOT / "docs/readme" / name for name in EXPECTED}
        cls.before = {
            name: path.stat().st_mtime_ns for name, path in cls.committed.items()
        }
        cls.runs = []
        for index in range(2):
            out = root / ("run" + str(index))
            subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(ROOT / "tool/readme/make_banner.py"),
                    "--out",
                    str(out),
                ],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            cls.runs.append({
                name: (out / name).read_bytes() for name in EXPECTED
            })

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_sizes_and_modes(self):
        for name, (size, mode) in EXPECTED.items():
            with self.subTest(name=name), Image.open(io.BytesIO(self.runs[0][name])) as image:
                self.assertEqual(image.format, "PNG")
                self.assertEqual(image.size, size)
                self.assertEqual(image.mode, mode)
                if mode == "RGBA":
                    self.assertEqual(image.getchannel("A").getextrema(), (255, 255))

    def test_identical_bytes_on_two_runs(self):
        for name in EXPECTED:
            with self.subTest(name=name):
                self.assertEqual(self.runs[0][name], self.runs[1][name])

    def test_the_committed_images_are_the_ones_the_generator_writes(self):
        for name in EXPECTED:
            with self.subTest(name=name):
                self.assertEqual(
                    self.committed[name].read_bytes(),
                    self.runs[0][name],
                    name + " is not the file the generator writes, "
                    "run python tool/readme/make_banner.py",
                )

    def test_the_checkout_is_not_touched(self):
        for name, path in self.committed.items():
            with self.subTest(name=name):
                self.assertEqual(
                    self.before[name],
                    path.stat().st_mtime_ns,
                    name + " was written by the test",
                )

    def test_non_empty_artwork(self):
        for name in EXPECTED:
            with self.subTest(name=name), Image.open(io.BytesIO(self.runs[0][name])) as image:
                rgb = image.convert("RGB")
                self.assertGreater(min(ImageStat.Stat(rgb).stddev), 15)
                self.assertIsNone(rgb.getcolors(maxcolors=100))

    def test_title_contrast_against_local_background(self):
        # Independently sample the visible title and the empty strip just above it.
        for name, title_box, background_box in (
            ("header.png", (300, 85, 960, 180), (300, 68, 960, 78)),
            ("og.png", (440, 227, 1140, 340), (440, 200, 1140, 215)),
        ):
            with self.subTest(name=name), Image.open(io.BytesIO(self.runs[0][name])) as image:
                title = sorted(map(luminance, image.crop(title_box).getdata()))
                backdrop = sorted(map(luminance, image.crop(background_box).getdata()))
                # The brightest tenth must be substantial high-contrast letter ink,
                # not just a single hot pixel. WCAG luminance ratio must exceed 7:1.
                ink = title[int(len(title) * 0.90)]
                contrast = (ink + 0.05) / (backdrop[len(backdrop) // 2] + 0.05)
                self.assertGreater(contrast, 7)
                self.assertGreater(sum(value > 0.7 for value in title) / len(title), 0.08)


if __name__ == "__main__":
    unittest.main()
