"""Tests of the screenshot pipeline.

Run from the repository root:

    python -m unittest discover -s tool/readme -p "test_process_screenshots.py"

The tests build synthetic screenshots, so no real capture is needed.
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
sys.path.insert(0, str(BASE))

import process_screenshots as screenshots  # noqa: E402


def synthetic(width: int, height: int, colour: tuple[int, int, int]) -> Image.Image:
    """A flat picture of one colour, easy to recognise after the processing."""
    return Image.new("RGB", (width, height), colour)


def noise(width: int, height: int) -> Image.Image:
    """A picture of random pixels, the worst case for the size of a file."""
    return Image.frombytes("RGB", (width, height), os.urandom(width * height * 3))


class ReadmeVersionTest(unittest.TestCase):
    """The version used by the README and the website."""

    def test_the_long_side_is_at_most_1080(self) -> None:
        picture = synthetic(1344, 2992, (10, 20, 30))
        result = screenshots.fit_long_side(picture, screenshots.README_MAX_SIDE)
        self.assertEqual(max(result.width, result.height), 1080)
        self.assertEqual(result.size, (485, 1080))

    def test_a_small_picture_is_not_enlarged(self) -> None:
        picture = synthetic(400, 800, (10, 20, 30))
        result = screenshots.fit_long_side(picture, screenshots.README_MAX_SIDE)
        self.assertEqual(result.size, (400, 800))

    def test_the_written_file_is_a_png_without_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "01-prism-live.png"
            picture = synthetic(1344, 2992, (10, 20, 30))
            picture.save(source, format="PNG", pnginfo=None)
            row = screenshots.process(source, root / "readme", root / "play")
            written = Path(str(row["readme_path"]))
            self.assertTrue(written.is_file())
            with Image.open(written) as opened:
                self.assertEqual(opened.format, "PNG")
                self.assertEqual(max(opened.width, opened.height), 1080)
                self.assertEqual(opened.info, {})


class PlayVersionTest(unittest.TestCase):
    """The version uploaded to Google Play."""

    def test_a_tall_screenshot_is_padded_to_two_to_one(self) -> None:
        picture = synthetic(1344, 2992, (200, 40, 60))
        result, padded = screenshots.fit_play(picture)
        self.assertEqual(result.size, (1496, 2992))
        self.assertEqual(result.width * 2, result.height)
        self.assertGreater(padded, 0)

    def test_the_padding_uses_the_background_of_the_app(self) -> None:
        picture = synthetic(1344, 2992, (200, 40, 60))
        result, _ = screenshots.fit_play(picture)
        self.assertEqual(result.getpixel((0, 0)), screenshots.BACKGROUND)
        self.assertEqual(result.getpixel((result.width - 1, 0)), screenshots.BACKGROUND)
        self.assertEqual(result.getpixel((result.width // 2, 10)), (200, 40, 60))

    def test_the_picture_is_neither_stretched_nor_cropped(self) -> None:
        width, height = 1344, 2992
        picture = synthetic(width, height, (200, 40, 60))
        result, _ = screenshots.fit_play(picture)
        # The content keeps its size and its shape: the padding is the same
        # on both sides and the picture is not resized.
        self.assertEqual(result.height, height)
        left = (result.width - width) // 2
        right = result.width - left - width
        self.assertEqual(left, right)
        self.assertEqual(result.getpixel((left - 1, 0)), screenshots.BACKGROUND)
        self.assertEqual(result.getpixel((left, 0)), (200, 40, 60))
        self.assertEqual(result.getpixel((left + width - 1, 0)), (200, 40, 60))

    def test_a_landscape_screenshot_is_padded_top_and_bottom(self) -> None:
        picture = synthetic(2992, 1344, (30, 60, 200))
        result, padded = screenshots.fit_play(picture)
        self.assertEqual(result.size, (2992, 1496))
        self.assertEqual(result.height * 2, result.width)
        self.assertGreater(padded, 0)
        self.assertEqual(result.getpixel((0, 0)), screenshots.BACKGROUND)
        self.assertEqual(result.getpixel((10, result.height // 2)), (30, 60, 200))

    def test_a_screenshot_inside_the_ratio_is_not_padded(self) -> None:
        picture = synthetic(1080, 1920, (30, 60, 200))
        result, padded = screenshots.fit_play(picture)
        self.assertEqual(result.size, (1080, 1920))
        self.assertEqual(padded, 0)

    def test_the_store_bounds_are_respected(self) -> None:
        for width, height in ((1344, 2992), (2992, 1344), (1080, 1920), (2400, 1080)):
            with self.subTest(size=(width, height)):
                result, _ = screenshots.fit_play(synthetic(width, height, (1, 2, 3)))
                long_side = max(result.width, result.height)
                short_side = min(result.width, result.height)
                self.assertGreaterEqual(long_side, screenshots.PLAY_MIN_SIDE)
                self.assertLessEqual(long_side, screenshots.PLAY_MAX_SIDE)
                self.assertGreaterEqual(short_side, screenshots.PLAY_MIN_SIDE)
                self.assertLessEqual(short_side, screenshots.PLAY_MAX_SIDE)
                self.assertLessEqual(long_side, 2 * short_side)

    def test_the_written_file_has_no_alpha(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "02-thermal-live.png"
            synthetic(1344, 2992, (200, 40, 60)).save(source, format="PNG")
            row = screenshots.process(source, root / "readme", root / "play")
            written = Path(str(row["play_path"]))
            self.assertTrue(written.is_file())
            with Image.open(written) as opened:
                self.assertIn(opened.format, ("PNG", "JPEG"))
                self.assertEqual(opened.mode, "RGB")
                self.assertNotIn("A", opened.mode)
                self.assertEqual(opened.info, {})

    def test_a_transparent_source_loses_its_alpha(self) -> None:
        picture = Image.new("RGBA", (600, 1200), (200, 40, 60, 255))
        picture.putpixel((0, 0), (0, 0, 0, 0))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "03-ripple-live.png"
            picture.save(source, format="PNG")
            screenshots.process(source, root / "readme", root / "play")
            with Image.open(root / "play" / source.name) as opened:
                self.assertEqual(opened.mode, "RGB")
            with Image.open(root / "readme" / source.name) as opened:
                self.assertEqual(opened.mode, "RGB")


class PlaySizeTest(unittest.TestCase):
    """One scale for the whole picture, and both limits of the store at once."""

    def test_a_tiny_picture_is_enlarged_to_the_minimum(self) -> None:
        result, padded = screenshots.fit_play(synthetic(1, 1, (10, 20, 30)))
        self.assertEqual(result.size, (320, 320))
        self.assertEqual(padded, 0)

    def test_an_extreme_ratio_is_padded_and_kept_in_the_bounds(self) -> None:
        result, padded = screenshots.fit_play(synthetic(1, 1000, (10, 20, 30)))
        self.assertEqual(result.size, (500, 1000))
        self.assertEqual(result.width * 2, result.height)
        self.assertGreaterEqual(min(result.size), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(result.size), screenshots.PLAY_MAX_SIDE)
        self.assertGreater(padded, 0)

    def test_a_landscape_of_one_pixel_is_kept_in_the_bounds(self) -> None:
        result, _ = screenshots.fit_play(synthetic(1000, 1, (10, 20, 30)))
        self.assertEqual(result.size, (1000, 500))
        self.assertGreaterEqual(min(result.size), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(result.size), screenshots.PLAY_MAX_SIDE)

    def test_the_long_side_never_goes_above_the_maximum(self) -> None:
        result, _ = screenshots.fit_play(synthetic(8000, 4000, (10, 20, 30)))
        self.assertEqual(max(result.size), screenshots.PLAY_MAX_SIDE)
        self.assertGreaterEqual(min(result.size), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(result.size), 2 * min(result.size))

    def test_a_very_tall_picture_never_goes_above_the_maximum(self) -> None:
        result, _ = screenshots.fit_play(synthetic(100, 20000, (10, 20, 30)))
        self.assertLessEqual(max(result.size), screenshots.PLAY_MAX_SIDE)
        self.assertGreaterEqual(min(result.size), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(result.size), 2 * min(result.size))

    def test_the_boundary_sizes_are_respected(self) -> None:
        for width, height in (
            (320, 320),
            (320, 640),
            (640, 320),
            (3840, 3840),
            (1920, 3840),
            (3840, 1920),
            (320, 3840),
        ):
            with self.subTest(size=(width, height)):
                result, _ = screenshots.fit_play(synthetic(width, height, (1, 2, 3)))
                long_side = max(result.width, result.height)
                short_side = min(result.width, result.height)
                self.assertGreaterEqual(short_side, screenshots.PLAY_MIN_SIDE)
                self.assertLessEqual(long_side, screenshots.PLAY_MAX_SIDE)
                self.assertLessEqual(long_side, 2 * short_side)

    def test_a_smaller_max_side_is_respected(self) -> None:
        result, _ = screenshots.fit_play(synthetic(1344, 2992, (1, 2, 3)), 1000)
        self.assertLessEqual(max(result.size), 1000)
        self.assertGreaterEqual(min(result.size), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(result.size), 2 * min(result.size))

    def test_a_max_side_above_the_store_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "01-prism-live.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                        "--max-side",
                        "5000",
                    ]
                )
            self.assertEqual(code, 1)
            self.assertFalse((root / "readme").exists())

    def test_a_max_side_below_the_store_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "01-prism-live.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                        "--max-side",
                        "100",
                    ]
                )
            self.assertEqual(code, 1)
            self.assertFalse((root / "readme").exists())


class StoreSizeTest(unittest.TestCase):
    """The file of the store never goes over the size that the store accepts."""

    def test_a_picture_that_fits_is_written_as_it_is(self) -> None:
        picture = synthetic(1344, 2992, (200, 40, 60))
        fitted = screenshots.fit_size(picture, screenshots.PLAY_MAX_BYTES)
        self.assertEqual(fitted["encoding"], "png")
        self.assertFalse(fitted["scaled"])
        self.assertLessEqual(len(fitted["bytes"]), screenshots.PLAY_MAX_BYTES)

    def test_a_picture_that_does_not_fit_is_scaled_down(self) -> None:
        picture = synthetic(1344, 2992, (200, 40, 60))
        fitted = screenshots.fit_size(picture, 4096)
        self.assertTrue(fitted["scaled"])
        self.assertLessEqual(len(fitted["bytes"]), 4096)
        width, height = fitted["size"]
        self.assertGreaterEqual(min(width, height), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(width, height), screenshots.PLAY_MAX_SIDE)
        self.assertLessEqual(max(width, height), 2 * min(width, height))

    def test_a_noisy_picture_of_3840_pixels_fits_in_eight_megabytes(self) -> None:
        picture = noise(3840, 3840)
        fitted = screenshots.fit_size(picture, screenshots.PLAY_MAX_BYTES)
        self.assertLessEqual(len(fitted["bytes"]), screenshots.PLAY_MAX_BYTES)
        width, height = fitted["size"]
        self.assertLessEqual(max(width, height), screenshots.PLAY_MAX_SIDE)
        self.assertGreaterEqual(min(width, height), screenshots.PLAY_MIN_SIDE)
        self.assertLessEqual(max(width, height), 2 * min(width, height))

    def test_the_written_file_of_a_noisy_capture_fits_in_the_store(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "01-prism-live.png"
            noise(3840, 3840).save(source, format="PNG")
            row = screenshots.process(source, root / "readme", root / "play")
            written = Path(str(row["play_path"]))
            self.assertTrue(written.is_file())
            self.assertLessEqual(written.stat().st_size, screenshots.PLAY_MAX_BYTES)
            with Image.open(written) as opened:
                self.assertIn(opened.format, ("PNG", "JPEG"))
                self.assertEqual(opened.mode, "RGB")
                long_side = max(opened.width, opened.height)
                short_side = min(opened.width, opened.height)
                self.assertGreaterEqual(short_side, screenshots.PLAY_MIN_SIDE)
                self.assertLessEqual(long_side, screenshots.PLAY_MAX_SIDE)
                self.assertLessEqual(long_side, 2 * short_side)

    def test_a_picture_that_cannot_be_encoded_is_an_error(self) -> None:
        picture = synthetic(1344, 2992, (200, 40, 60))
        with self.assertRaises(screenshots.ScreenshotError):
            screenshots.fit_size(picture, 16)


class NameTest(unittest.TestCase):
    """The names of the captures are checked before anything is written."""

    def test_a_jpeg_capture_is_written_as_a_png(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "01-prism-live.jpg"
            synthetic(1344, 2992, (10, 20, 30)).save(source, format="JPEG")
            row = screenshots.process(source, root / "readme", root / "play")
            self.assertEqual(Path(str(row["readme_path"])).name, "01-prism-live.png")
            self.assertEqual(Path(str(row["play_path"])).name, "01-prism-live.png")
            self.assertTrue((root / "readme" / "01-prism-live.png").is_file())
            self.assertTrue((root / "play" / "01-prism-live.png").is_file())

    def test_a_capture_in_capital_letters_is_written_as_a_png(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "02-thermal-live.PNG"
            synthetic(1344, 2992, (10, 20, 30)).save(source, format="PNG")
            row = screenshots.process(source, root / "readme", root / "play")
            self.assertEqual(Path(str(row["readme_path"])).name, "02-thermal-live.png")
            self.assertTrue((root / "play" / "02-thermal-live.png").is_file())

    def test_an_unexpected_name_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "10-unknown.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                    ]
                )
            self.assertEqual(code, 1)
            self.assertFalse((root / "readme").exists())
            self.assertFalse((root / "play").exists())

    def test_a_reserved_name_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "header.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                    ]
                )
            self.assertEqual(code, 1)
            self.assertFalse((root / "readme").exists())

    def test_two_captures_with_the_same_name_are_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "01-prism-live.png")
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "01-prism-live.jpg")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                    ]
                )
            self.assertEqual(code, 1)
            self.assertFalse((root / "readme").exists())
            self.assertFalse((root / "play").exists())

    def test_the_expected_names_are_the_ones_of_the_readme(self) -> None:
        self.assertEqual(
            list(screenshots.EXPECTED_NAMES),
            [
                "01-prism-live",
                "02-thermal-live",
                "03-ripple-live",
                "04-result-full",
                "05-result-sound-strip",
                "06-result-poster",
                "07-before-after",
                "08-landscape-result",
                "09-settings",
            ],
        )
        self.assertEqual(
            list(screenshots.RESERVED_NAMES), ["header", "icon-512", "og"]
        )


class TableTest(unittest.TestCase):
    """The tool prints what it wrote."""

    def test_the_command_reports_the_written_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "capturas"
            captures.mkdir()
            synthetic(1344, 2992, (10, 20, 30)).save(captures / "01-prism-live.png")
            synthetic(2992, 1344, (10, 20, 30)).save(captures / "08-landscape-result.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(captures),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                    ]
                )
            self.assertEqual(code, 0)
            self.assertIn("01-prism-live.png", output.getvalue())
            self.assertIn("485x1080", output.getvalue())
            self.assertTrue((root / "readme" / "01-prism-live.png").is_file())
            self.assertTrue((root / "play" / "01-prism-live.png").is_file())
            self.assertTrue((root / "readme" / "08-landscape-result.png").is_file())
            self.assertTrue((root / "play" / "08-landscape-result.png").is_file())

    def test_an_empty_folder_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = screenshots.main(
                    [
                        "--input",
                        str(root / "empty"),
                        "--readme",
                        str(root / "readme"),
                        "--play",
                        str(root / "play"),
                    ]
                )
            self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
