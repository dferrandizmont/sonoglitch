"""Tests of the generated website.

Run from the repository root:

    python -m unittest discover -s tool/site

The tests build the site into a temporary folder and compare it with the
committed ``site/`` folder, so the committed output is never stale.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
SITE = ROOT / "site"
sys.path.insert(0, str(BASE))

import build  # noqa: E402

#: Hosts the site is allowed to link to. Everything else would be a request
#: to a third party, and the app is privacy first.
ALLOWED_HOSTS = {
    "github.com": "/dferrandizmont",
    "dferrandizmont.github.io": "",
    "ko-fi.com": "/danielmfdev",
}

EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
URL_RE = re.compile(r"https?://[^\s\"'<>]+")
VOID_TAGS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}

#: The attributes of the tags that make the browser fetch something.
RESOURCE_ATTRIBUTES = {
    "img": ("src", "srcset"),
    "script": ("src",),
    "source": ("src", "srcset"),
    "video": ("src", "poster"),
    "audio": ("src",),
    "iframe": ("src",),
    "embed": ("src",),
    "object": ("data",),
    "track": ("src",),
    "input": ("src",),
}

#: The relations of a link that make the browser fetch something. The others,
#: like ``canonical`` or ``alternate``, are metadata and are never requested.
FETCHED_LINK_RELS = {
    "stylesheet",
    "icon",
    "shortcut",
    "apple-touch-icon",
    "apple-touch-icon-precomposed",
    "manifest",
    "preload",
    "prefetch",
    "modulepreload",
    "preconnect",
    "dns-prefetch",
}

#: The stylesheets and the pictures the pages load.
CSS_URL_RE = re.compile(r"url\(\s*['\"]?([^'\")]+)")
SVG_HREF_RE = re.compile(r"(?:xlink:href|href|src)\s*=\s*['\"]([^'\"]+)['\"]")


def html_pages(root: Path) -> list[Path]:
    return sorted(root.rglob("*.html"))


def is_remote(value: str) -> bool:
    """True when the browser would ask another host for something."""
    value = value.strip()
    return value.startswith("//") or value.lower().startswith(("http://", "https://"))


def candidates(value: str) -> list[str]:
    """The addresses of a ``srcset``: one candidate per comma."""
    found = []
    for part in value.split(","):
        part = part.strip()
        if part:
            found.append(part.split()[0])
    return found


class Balance(HTMLParser):
    """Check that every tag is closed, in order."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in VOID_TAGS:
            self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        if not self.stack:
            self.errors.append("closing </" + tag + "> without an open tag")
        elif self.stack[-1] != tag:
            self.errors.append("closing </" + tag + "> while <" + self.stack[-1] + "> is open")
        else:
            self.stack.pop()


class Collector(HTMLParser):
    """Collect the links, the images and the metadata of a page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self.images: list[tuple[str, str, str, str]] = []
        self.meta: list[tuple[str, str]] = []
        self.lang: str | None = None
        self.title: str | None = None
        self.description: str | None = None
        self._text: list[str] = []
        self._href: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if tag == "html":
            self.lang = values.get("lang")
        elif tag == "a":
            self._href = values.get("href", "")
            self._text = []
        elif tag == "img":
            self.images.append((
                values.get("src", ""),
                values.get("alt", ""),
                values.get("width", ""),
                values.get("height", ""),
            ))
        elif tag == "title":
            self.title = ""
        elif tag == "meta":
            if values.get("name") == "description":
                self.description = values.get("content")
            key = values.get("property") or values.get("name") or ""
            if key:
                self.meta.append((key, values.get("content", "")))

    def handle_data(self, data: str) -> None:
        if self.title is not None and self._href is None:
            self.title += data
        elif self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._href is not None:
            self.links.append((self._href, "".join(self._text).strip()))
            self._href = None
        elif tag == "title":
            self.title = (self.title or "").strip()


class Resources(HTMLParser):
    """Collect the resources the browser would load."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.resources: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        for attribute in RESOURCE_ATTRIBUTES.get(tag, ()):
            value = values.get(attribute, "")
            if value:
                self.resources.append((tag + "[" + attribute + "]", value))
        if tag == "link":
            relations = values.get("rel", "").lower().split()
            if any(relation in FETCHED_LINK_RELS for relation in relations):
                value = values.get("href", "")
                if value:
                    self.resources.append(("link[href]", value))


def strip_tags(html: str) -> str:
    return re.sub(r"<[^>]+>", "", html)


def resolve(page: Path, href: str) -> Path:
    """Resolve an internal link of ``page`` to a path inside the site."""
    href = href.split("#", 1)[0].split("?", 1)[0]
    if not href:
        return page
    if href.startswith("/"):
        relative = href.lstrip("/")
        prefix = "sonoglitch/"
        if relative.startswith(prefix):
            relative = relative[len(prefix) :]
        target = SITE / relative
    else:
        target = page.parent / href
    target = Path(os.path.normpath(str(target)))
    if target.is_dir():
        target = target / "index.html"
    return target


def relative_luminance(colour: str) -> float:
    """The luminance of a colour written as ``#RRGGBB``."""
    digits = colour.lstrip("#")
    channels = [int(digits[index : index + 2], 16) / 255 for index in (0, 2, 4)]
    linear = [
        value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
        for value in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    """The ratio of contrast between two colours written as ``#RRGGBB``."""
    one = relative_luminance(first)
    two = relative_luminance(second)
    high, low = max(one, two), min(one, two)
    return (high + 0.05) / (low + 0.05)


def css_palettes() -> dict[str, dict[str, str]]:
    """The colours of the dark and of the light palette of the stylesheet."""
    text = (SITE / "styles.css").read_text(encoding="utf-8")
    palettes: dict[str, dict[str, str]] = {}
    dark = re.search(r":root\s*\{(.*?)\}", text, re.S)
    light = re.search(
        r"prefers-color-scheme:\s*light\)\s*\{\s*:root\s*\{(.*?)\}", text, re.S
    )
    assert dark is not None and light is not None, "the stylesheet has no palette"
    for name, block in (("dark", dark.group(1)), ("light", light.group(1))):
        palettes[name] = {
            variable: value
            for variable, value in re.findall(
                r"(--[\w-]+)\s*:\s*(#[0-9A-Fa-f]{6})\s*;", block
            )
        }
    return palettes


class CommittedSiteTest(unittest.TestCase):
    """The committed ``site/`` folder is what the generator produces."""

    def test_build_matches_the_committed_site(self) -> None:
        self.assertTrue(SITE.is_dir(), "the site folder is missing, run python tool/site/build.py")
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary) / "site"
            build.build(out)
            produced = sorted(p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file())
            committed = sorted(p.relative_to(SITE).as_posix() for p in SITE.rglob("*") if p.is_file())
            self.assertEqual(
                produced,
                committed,
                "the committed site is stale, run python tool/site/build.py",
            )
            for relative in produced:
                self.assertEqual(
                    (out / relative).read_bytes(),
                    (SITE / relative).read_bytes(),
                    relative + " differs from the generated file",
                )

    def test_expected_files_are_present(self) -> None:
        for relative in (
            "index.html",
            "es/index.html",
            "privacy/index.html",
            "404.html",
            "styles.css",
            "robots.txt",
            ".nojekyll",
            "img/icon.svg",
        ):
            self.assertTrue((SITE / relative).is_file(), relative + " is missing")

    def test_robots_allows_everything(self) -> None:
        robots = (SITE / "robots.txt").read_text(encoding="utf-8")
        self.assertIn("User-agent: *", robots)
        self.assertIn("Allow: /", robots)

    def test_the_generator_uses_the_standard_library_only(self) -> None:
        source = (BASE / "build.py").read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r"\b(?:from|import)\s+PIL\b", source),
            "the generator of the site uses an image library",
        )

    def test_the_gallery_copies_the_screenshots(self) -> None:
        for source in build.gallery_sources():
            target = SITE / "img" / source.name
            with self.subTest(name=source.name):
                self.assertTrue(target.is_file(), source.name + " is not in the site")
                self.assertEqual(target.read_bytes(), source.read_bytes())

    def test_the_gallery_declares_the_size_of_the_images(self) -> None:
        for page in html_pages(SITE):
            parser = Collector()
            parser.feed(page.read_text(encoding="utf-8"))
            for source, _, width, height in parser.images:
                if not source.endswith(".png"):
                    continue
                target = resolve(page, source)
                if not target.is_file():
                    continue
                size = build.png_size(target)
                with self.subTest(page=page.name, image=source):
                    self.assertIsNotNone(size)
                    self.assertEqual((width, height), (str(size[0]), str(size[1])))


class MarkupTest(unittest.TestCase):
    """Every page is well formed, accessible and free of scripts."""

    def test_tags_are_balanced(self) -> None:
        for page in html_pages(SITE):
            parser = Balance()
            parser.feed(page.read_text(encoding="utf-8"))
            self.assertEqual(parser.errors, [], page.name + " has unbalanced tags")
            self.assertEqual(parser.stack, [], page.name + " has unclosed tags")

    def test_no_scripts_and_no_inline_handlers(self) -> None:
        for page in html_pages(SITE):
            text = page.read_text(encoding="utf-8")
            self.assertNotIn("<script", text, page.name + " has a script")
            self.assertIsNone(
                re.search(r"\son[a-z]+\s*=", text),
                page.name + " has an inline event handler",
            )

    def test_pages_have_the_expected_metadata(self) -> None:
        for page in html_pages(SITE):
            parser = Collector()
            parser.feed(page.read_text(encoding="utf-8"))
            self.assertTrue(parser.lang, page.name + " has no lang attribute")
            self.assertTrue(parser.title, page.name + " has no title")
            self.assertGreater(len(parser.title), 10, page.name + " has a short title")
            self.assertTrue(parser.description, page.name + " has no description")
            self.assertGreater(len(parser.description), 30, page.name + " has a short description")

    def test_images_have_an_alt_text(self) -> None:
        for page in html_pages(SITE):
            parser = Collector()
            parser.feed(page.read_text(encoding="utf-8"))
            for source, alt, _, _ in parser.images:
                self.assertTrue(alt, page.name + ": " + source + " has no alt text")

    def test_the_alt_text_is_written_in_the_language_of_the_page(self) -> None:
        english = (SITE / "index.html").read_text(encoding="utf-8")
        spanish = (SITE / "es" / "index.html").read_text(encoding="utf-8")
        self.assertIn("Sonoglitch app icon", english)
        self.assertNotIn("Sonoglitch app icon", spanish)
        self.assertIn("Icono de la app Sonoglitch", spanish)


class PrivacyTest(unittest.TestCase):
    """The policy page is generated from the markdown of the repository."""

    def setUp(self) -> None:
        self.page = SITE / "privacy" / "index.html"

    def test_every_heading_of_the_markdown_is_published(self) -> None:
        markdown = (ROOT / "docs" / "PRIVACY.md").read_text(encoding="utf-8")
        headings = re.findall(r"^##\s+(.+)$", markdown, re.M)
        self.assertGreaterEqual(len(headings), 5)
        published = strip_tags(self.page.read_text(encoding="utf-8"))
        for heading in headings:
            clean = heading.replace("*", "").replace("`", "")
            self.assertIn(clean, published, "missing heading: " + clean)

    def test_the_policy_keeps_its_table_and_its_lists(self) -> None:
        text = self.page.read_text(encoding="utf-8")
        self.assertIn("<table>", text)
        self.assertIn("<ul>", text)
        self.assertIn("<em>Last updated:", text)

    def test_the_page_is_english_only(self) -> None:
        parser = Collector()
        parser.feed(self.page.read_text(encoding="utf-8"))
        self.assertEqual(parser.lang, "en")


class MetadataTest(unittest.TestCase):
    """The metadata of the pages points to the files that exist."""

    def test_the_open_graph_image_is_an_absolute_address(self) -> None:
        for page in html_pages(SITE):
            parser = Collector()
            parser.feed(page.read_text(encoding="utf-8"))
            found = False
            for key, value in parser.meta:
                if key in ("og:image", "twitter:image"):
                    found = True
                    self.assertEqual(
                        value,
                        build.OG_IMAGE_URL,
                        page.name + " has a relative " + key,
                    )
                    self.assertTrue(value.startswith("https://"))
            self.assertTrue(found, page.name + " has no " + "og:image")

    def test_the_open_graph_image_is_in_the_site(self) -> None:
        self.assertTrue((SITE / "img" / "og.png").is_file())


class ContrastTest(unittest.TestCase):
    """The text of the buttons keeps a readable contrast in both palettes."""

    def test_the_primary_button_is_readable(self) -> None:
        for scheme, palette in css_palettes().items():
            with self.subTest(scheme=scheme):
                text = palette["--on-accent"]
                self.assertGreaterEqual(
                    contrast_ratio(palette["--accent"], text),
                    4.5,
                    scheme + ": the button is not readable",
                )
                self.assertGreaterEqual(
                    contrast_ratio(palette["--accent-hover"], text),
                    4.5,
                    scheme + ": the button is not readable when it is hovered",
                )

    def test_the_hover_rule_uses_the_palette(self) -> None:
        text = (SITE / "styles.css").read_text(encoding="utf-8")
        self.assertIn(
            ".button.primary:hover { background: var(--accent-hover);", text
        )


class RequestTest(unittest.TestCase):
    """The site never asks a third party for anything."""

    def test_only_allowed_urls(self) -> None:
        for page in html_pages(SITE):
            text = page.read_text(encoding="utf-8")
            for url in URL_RE.findall(text):
                self.assertTrue(
                    url.startswith("https://"),
                    page.name + " uses an insecure URL: " + url,
                )
                parts = urlsplit(url)
                self.assertIn(
                    parts.hostname or "",
                    ALLOWED_HOSTS,
                    page.name + " links to a third party: " + url,
                )
                allowed_path = ALLOWED_HOSTS[parts.hostname or ""]
                self.assertTrue(
                    parts.path.startswith(allowed_path),
                    page.name + " links outside the allowed path: " + url,
                )

    def test_the_only_email_is_the_contact_address(self) -> None:
        for page in html_pages(SITE):
            for address in set(EMAIL_RE.findall(page.read_text(encoding="utf-8"))):
                self.assertEqual(address, "dev@mainshai.com", page.name + " has another address")

    def test_the_stores_are_plain_text(self) -> None:
        for page in html_pages(SITE):
            text = page.read_text(encoding="utf-8")
            for forbidden in ("play.google.com", "f-droid.org", "market://", "itunes.apple.com"):
                self.assertNotIn(forbidden, text, page.name + " links to a store")
            parser = Collector()
            parser.feed(text)
            for href, label in parser.links:
                if "play" in label.lower() or "f-droid" in label.lower():
                    self.assertFalse(
                        href.startswith("http"),
                        page.name + " has a dead store link: " + label,
                    )

    def test_no_external_resource_is_loaded(self) -> None:
        for page in html_pages(SITE):
            parser = Resources()
            parser.feed(page.read_text(encoding="utf-8"))
            for kind, value in parser.resources:
                for url in candidates(value):
                    self.assertFalse(
                        is_remote(url),
                        page.name + " loads a remote resource (" + kind + "): " + url,
                    )

    def test_the_stylesheets_load_nothing(self) -> None:
        for path in sorted(SITE.rglob("*.css")):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("@import", text, path.name + " imports another stylesheet")
            for url in CSS_URL_RE.findall(text):
                self.assertFalse(
                    is_remote(url), path.name + " loads a remote resource: " + url
                )

    def test_the_svgs_load_nothing(self) -> None:
        for path in sorted(SITE.rglob("*.svg")):
            text = path.read_text(encoding="utf-8")
            for url in SVG_HREF_RE.findall(text):
                self.assertFalse(
                    is_remote(url), path.name + " loads a remote resource: " + url
                )
            for url in CSS_URL_RE.findall(text):
                self.assertFalse(
                    is_remote(url), path.name + " loads a remote resource: " + url
                )

    def test_no_page_mentions_a_third_party_font_or_analytics(self) -> None:
        for page in html_pages(SITE):
            text = page.read_text(encoding="utf-8")
            for forbidden in (
                "fonts.googleapis.com",
                "fonts.gstatic.com",
                "googletagmanager",
                "google-analytics",
                "cdn.jsdelivr.net",
                "unpkg.com",
                "@import",
            ):
                self.assertNotIn(forbidden, text, page.name + " uses " + forbidden)


class LinkTest(unittest.TestCase):
    """Every internal link points to a file of the site."""

    def test_links_resolve(self) -> None:
        for page in html_pages(SITE):
            parser = Collector()
            parser.feed(page.read_text(encoding="utf-8"))
            for href, label in parser.links:
                if not href or href.startswith("#"):
                    continue
                if href.startswith(("https://", "http://", "mailto:", "tel:", "data:")):
                    continue
                target = resolve(page, href)
                self.assertTrue(
                    target.is_file(),
                    page.name + " links to a missing file: " + href + " (" + label + ")",
                )

    def test_the_two_languages_link_to_each_other(self) -> None:
        parser = Collector()
        parser.feed((SITE / "index.html").read_text(encoding="utf-8"))
        self.assertTrue(any(href == "es/" for href, _ in parser.links))
        parser = Collector()
        parser.feed((SITE / "es" / "index.html").read_text(encoding="utf-8"))
        self.assertTrue(any(href == "../" for href, _ in parser.links))


if __name__ == "__main__":
    unittest.main()
