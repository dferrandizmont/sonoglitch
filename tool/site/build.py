#!/usr/bin/env python3
"""Generate the static site of Sonoglitch.

Python 3 standard library only: no third party package, no network request and
no JavaScript. The output is written under ``site/`` and committed, so the
branch can be served as it is.

Usage:
    python tool/site/build.py [--out DIR]

The tests run the build into a temporary directory and compare it with the
committed ``site/`` folder, so the output must be reproducible byte by byte.
"""

from __future__ import annotations

import argparse
import html
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "site"
DOCS_README = ROOT / "docs" / "readme"
ICON_SVG = ROOT / "assets" / "branding" / "icon.svg"
PRIVACY_MD = ROOT / "docs" / "PRIVACY.md"

REPO_URL = "https://github.com/dferrandizmont/sonoglitch"
RELEASES_URL = REPO_URL + "/releases"
KOFI_URL = "https://ko-fi.com/danielmfdev"
SITE_URL = "https://dferrandizmont.github.io/sonoglitch"
CONTACT_EMAIL = "dev@mainshai.com"
SITE_PATH = "/sonoglitch"

#: Entries of the output folder this generator owns and rewrites.
MANAGED = (
    "index.html",
    "es",
    "privacy",
    "img",
    "styles.css",
    "robots.txt",
    ".nojekyll",
    "404.html",
)

#: Screenshots are the numbered files of ``docs/readme/``. The banner, the
#: icon and the Open Graph image are not screenshots.
GALLERY_PATTERN = re.compile(r"^\d{2}-.+\.png$")

#: The alternative text of every screenshot, in the language of the page.
GALLERY_ALT = {
    "en": {
        "01-prism-live.png": "Live viewfinder with the Prism style",
        "02-thermal-live.png": "Live viewfinder with the Thermal style",
        "03-ripple-live.png": "Live viewfinder with the Ripple style",
        "04-result-full.png": "Result screen with the Full export layout",
        "05-result-sound-strip.png": "Result screen with the Sound strip export layout",
        "06-result-poster.png": "Result screen with the Poster export layout",
        "07-before-after.png": "Comparison between the processed picture and the original",
        "08-landscape-result.png": "Result of a landscape photo",
        "09-settings.png": "Settings screen of the app",
    },
    "es": {
        "01-prism-live.png": "Visor en directo con el estilo Prism",
        "02-thermal-live.png": "Visor en directo con el estilo Thermal",
        "03-ripple-live.png": "Visor en directo con el estilo Ripple",
        "04-result-full.png": "Pantalla de resultado con la composición Full",
        "05-result-sound-strip.png": "Pantalla de resultado con la composición Sound strip",
        "06-result-poster.png": "Pantalla de resultado con la composición Poster",
        "07-before-after.png": "Comparación entre la foto procesada y la original",
        "08-landscape-result.png": "Resultado de una foto en horizontal",
        "09-settings.png": "Pantalla de ajustes de la app",
    },
}

#: The alternative text of a screenshot without one of its own.
GALLERY_ALT_DEFAULT = {
    "en": "Screenshot of Sonoglitch",
    "es": "Captura de Sonoglitch",
}

#: The absolute address of the Open Graph image. It has to be absolute
#: because the pages are published in more than one folder.
OG_IMAGE_URL = SITE_URL + "/img/og.png"


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

CONTENT = {
    "en": {
        "lang": "en",
        "html_lang": "en",
        "title": "Sonoglitch — a camera shaped by sound, light and motion",
        "description": (
            "Sonoglitch is a free and open source camera app: the sound, the light "
            "and the movement of the surroundings distort the photo. Six styles, "
            "no ads, no accounts and no network access."
        ),
        "canonical": SITE_URL + "/",
        "og_locale": "en",
        "icon_alt": (
            "Sonoglitch app icon: a violet camera lens torn into displaced "
            "colour channels by sound"
        ),
        "other_lang": "es",
        "other_label": "Español",
        "other_path": "es/",
        "nav": (("styles", "Styles"), ("features", "Features"), ("privacy", "Privacy")),
        "nav_label": "Main",
        "pitch": (
            "Sonoglitch is a free and open source camera app that lets the "
            "surroundings shape the photo. The sound level of the microphone, the "
            "light of the place and the movement of the scene and of the phone "
            "drive a live shader that distorts the picture while you watch it."
        ),
        "note": "Requires Android 10 (API 29) or newer. Pre-release alpha builds for now.",
        "download_title": "Download",
        "download_github": "Download for Android",
        "download_soon": "coming soon",
        "styles_title": "Six styles",
        "styles_intro": (
            "Every style reads the same three inputs: the noise of the place, "
            "the light and the movement. Each one uses them in its own way."
        ),
        "styles": (
            ("Static", "Digital tearing: displaced horizontal bands, blocky corruption and split colour channels."),
            ("Tape", "Tracking bands and tears, faded analogue colour and grain."),
            ("Phosphor", "A CRT tube: scan lines, shadow grille, green persistence and snow."),
            ("Ripple", "A travelling wavefront from a shout, with a refracted crest."),
            ("Thermal", "A heat map of the luminance, with isotherm contours and sensor hiss."),
            ("Prism", "Flowing distortion, colour dispersion and light leaks."),
        ),
        "features_title": "What it does",
        "features": (
            "Three ambient inputs, with the same meaning in every style: noise, light and motion.",
            "Live viewfinder with the effect on the picture: a style button with arrows (or a swipe) changes the style, and its sheet describes every style and offers Random and Match this place, which chooses one for the ambience and tells you why.",
            "The card with the three levels opens the How it works sheet, which explains the noise, the light and the movement in plain words, how the style is changed and what Auto shot does.",
            "Auto shot: the camera takes the photo by itself when the sound crosses a threshold after a quiet second, or when the scene jumps suddenly.",
            "Three export layouts: the picture alone, a sound strip with the measured values, or a poster with the style name.",
            "Four crops: the original aspect ratio, a centred 1:1 square, a centred 4:5 portrait and a 9:16 story.",
            "Three quality tiers: Standard (up to 2048 px on the long side), High (up to 4096 px) and Maximum (up to the native size of the sensor), subject to the size of the original and to the limits of the device. The 24-megapixel cap applies to the cropped picture, so the exported file can be slightly larger with the sound strip or the poster.",
            "PNG (lossless) or JPEG, saved to the gallery or shared through the system share sheet.",
            "Press and hold the photo to compare it with the original.",
            "The three frequency bands of the sound are measured in memory and shown in the export layouts; they never change the effect.",
        ),
        "gallery_title": "Screenshots",
        "gallery_intro": "The live viewfinder, the three export layouts and the comparison with the original.",
        "support_title": "Support",
        "support_text": (
            "Sonoglitch is free, without ads or accounts. The F-Droid and GitHub "
            "builds show an optional Ko-fi link in Settings; the Google Play "
            "build has none, because Play does not allow donations outside its "
            "own billing."
        ),
        "support_link_label": "Ko-fi",
        "privacy_title": "Privacy",
        "privacy_text": (
            "Audio is never recorded, stored or transmitted: the app reads the "
            "volume level and the energy of three frequency bands in memory, and "
            "nothing else. There are no accounts, no ads, no analytics and no "
            "servers. The release builds declare no INTERNET permission, so the "
            "app has no network access at all."
        ),
        "privacy_link_label": "Read the privacy policy",
        "privacy_note": "",
        "repo_label": "Source code",
        "repo_text": "The code of the app is free software; read it, build it and send patches.",
        "footer_note": (
            "Sonoglitch is licensed under Apache-2.0. It is an independent app, "
            "not affiliated with any store or platform."
        ),
    },
    "es": {
        "lang": "es",
        "html_lang": "es",
        "title": "Sonoglitch — una cámara moldeada por el sonido, la luz y el movimiento",
        "description": (
            "Sonoglitch es una cámara gratuita y de código abierto: el sonido, "
            "la luz y el movimiento del entorno distorsionan la foto. Seis estilos, "
            "sin anuncios, sin cuentas y sin acceso a la red."
        ),
        "canonical": SITE_URL + "/es/",
        "og_locale": "es_ES",
        "icon_alt": (
            "Icono de la app Sonoglitch: una lente violeta deshecha en canales "
            "de color desplazados por el sonido"
        ),
        "other_lang": "en",
        "other_label": "English",
        "other_path": "../",
        "nav": (("estilos", "Estilos"), ("funciones", "Funciones"), ("privacidad", "Privacidad")),
        "nav_label": "Principal",
        "pitch": (
            "Sonoglitch es una cámara gratuita y de código abierto que deja que el "
            "entorno dé forma a la foto. El nivel de sonido del micrófono, la luz "
            "del lugar y el movimiento de la escena y del móvil alimentan un shader "
            "en vivo que distorsiona la imagen mientras la miras."
        ),
        "note": "Requiere Android 10 (API 29) o posterior. Versiones alfa preliminares por ahora.",
        "download_title": "Descargar",
        "download_github": "Descargar para Android",
        "download_soon": "próximamente",
        "styles_title": "Seis estilos",
        "styles_intro": (
            "Todos los estilos leen las mismas tres entradas: el ruido del lugar, "
            "la luz y el movimiento. Cada uno las usa a su manera."
        ),
        "styles": (
            ("Static", "Roturas digitales: bandas horizontales desplazadas, corrupción en bloques y canales de color separados."),
            ("Tape", "Bandas de seguimiento y rasgaduras, color analógico desvaído y grano."),
            ("Phosphor", "Un tubo CRT: líneas de barrido, rejilla de sombra, persistencia verde y nieve."),
            ("Ripple", "Un frente de onda que viaja desde un grito, con la cresta refractada."),
            ("Thermal", "Un mapa de calor de la luminancia, con contornos de isoterma y ruido de sensor."),
            ("Prism", "Distorsión fluida, dispersión de color y fugas de luz."),
        ),
        "features_title": "Qué hace",
        "features": (
            "Tres entradas del entorno con el mismo significado en todos los estilos: ruido, luz y movimiento.",
            "Visor en directo con el efecto sobre la imagen: un botón de estilo con flechas (o un deslizamiento) cambia el estilo, y su panel de estilos describe cada estilo y ofrece Al azar y Según el lugar, que elige uno para el ambiente y te dice por qué.",
            "La tarjeta con los tres niveles abre el panel Cómo funciona, que explica el ruido, la luz y el movimiento con palabras sencillas, cómo se cambia el estilo y qué hace el Disparo auto.",
            "Disparo auto: la cámara hace la foto sola cuando el sonido supera un umbral tras un segundo de calma, o cuando la escena da un salto brusco.",
            "Tres composiciones de exportación: solo la foto, una banda de sonido con los valores medidos o un póster con el nombre del estilo.",
            "Cuatro recortes: la proporción original, un cuadrado 1:1 centrado, un vertical 4:5 centrado y un 9:16 para historias.",
            "Tres niveles de calidad: Estándar (hasta 2048 px en el lado largo), Alta (hasta 4096 px) y Máxima (hasta el tamaño nativo del sensor), según el tamaño del original y los límites del dispositivo. El tope de 24 megapíxeles se aplica a la foto recortada, así que el archivo exportado puede ser algo mayor con la banda de sonido o el póster.",
            "PNG (sin pérdida) o JPEG, guardado en la galería o compartido con el menú del sistema.",
            "Mantén pulsada la foto para compararla con el original.",
            "Las tres bandas de frecuencias del sonido se miden en memoria y se muestran en las composiciones de exportación; nunca cambian el efecto.",
        ),
        "gallery_title": "Capturas",
        "gallery_intro": "El visor en directo, las tres composiciones de exportación y la comparación con el original.",
        "support_title": "Soporte",
        "support_text": (
            "Sonoglitch es gratis, sin anuncios y sin cuentas. Las versiones de "
            "F-Droid y de GitHub muestran un enlace opcional a Ko-fi en Ajustes; la "
            "versión de Google Play no lo tiene, porque Play no permite donaciones "
            "fuera de su propia facturación."
        ),
        "support_link_label": "Ko-fi",
        "privacy_title": "Privacidad",
        "privacy_text": (
            "El audio nunca se graba, almacena ni transmite: la app lee en memoria "
            "el nivel de volumen y la energía de tres bandas de frecuencias, y nada "
            "más. No hay cuentas, ni anuncios, ni analítica, ni servidores. Las "
            "versiones de publicación no declaran el permiso INTERNET, así que la "
            "app no tiene acceso a la red."
        ),
        "privacy_link_label": "Leer la política de privacidad",
        "privacy_note": "La política de privacidad se publica solo en inglés.",
        "repo_label": "Código fuente",
        "repo_text": "El código de la app es software libre: léelo, compílalo y envía parches.",
        "footer_note": (
            "Sonoglitch se distribuye con la licencia Apache-2.0. Es una app "
            "independiente, sin afiliación con ninguna tienda o plataforma."
        ),
    },
}


# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------

INLINE_RE = re.compile(
    r"(?P<code>`[^`]+`)"
    r"|(?P<link>\[(?P<label>[^\]]*)\]\((?P<url>[^)\s]+)\))"
    r"|(?P<bold>\*\*(?P<bold_text>.+?)\*\*)"
    r"|(?P<italic>(?<!\*)\*(?P<italic_text>[^*\n]+)\*(?!\*))"
    r"|(?P<mail>[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"
)

LIST_ITEM_RE = re.compile(r"^(?:[-*+]|\d+\.)\s+(.*)$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
SEPARATOR_CELL_RE = re.compile(r"^:?-{2,}:?$")


def inline(text: str) -> str:
    """Render the inline markup of one line of markdown."""
    escaped = html.escape(text, quote=False)

    def replace(match: re.Match[str]) -> str:
        if match.group("code") is not None:
            return "<code>" + match.group("code")[1:-1] + "</code>"
        if match.group("link") is not None:
            url = match.group("url")
            label = match.group("label")
            return '<a href="' + html.escape(url, quote=True) + '">' + label + "</a>"
        if match.group("bold") is not None:
            return "<strong>" + match.group("bold_text") + "</strong>"
        if match.group("italic") is not None:
            return "<em>" + match.group("italic_text") + "</em>"
        if match.group("mail") is not None:
            address = match.group("mail")
            return '<a href="mailto:' + address + '">' + address + "</a>"
        return match.group(0)

    return INLINE_RE.sub(replace, escaped)


def table_cells(row: str) -> list[str]:
    return [cell.strip() for cell in row.strip().strip("|").split("|")]


def render_table(rows: list[str]) -> str:
    """Render a markdown table as a scrollable HTML table."""
    head = table_cells(rows[0])
    body = rows[1:]
    if body and all(SEPARATOR_CELL_RE.match(cell) for cell in table_cells(body[0])):
        body = body[1:]
    parts = ['<div class="table-wrap"><table>', "<thead><tr>"]
    parts.extend("<th>" + inline(cell) + "</th>" for cell in head)
    parts.append("</tr></thead>")
    parts.append("<tbody>")
    for row in body:
        parts.append(
            "<tr>"
            + "".join("<td>" + inline(cell) + "</td>" for cell in table_cells(row))
            + "</tr>"
        )
    parts.append("</tbody></table></div>")
    return "".join(parts)


def render_list(lines: list[str], start: int, out: list[str]) -> int:
    """Render a flat bullet or numbered list and return the next line index."""
    ordered = bool(re.match(r"^\d+\.\s", lines[start].strip()))
    tag = "ol" if ordered else "ul"
    out.append("<" + tag + ">")
    index = start
    total = len(lines)
    while index < total:
        match = LIST_ITEM_RE.match(lines[index].strip())
        if match is None:
            if not lines[index].strip():
                lookahead = index
                while lookahead < total and not lines[lookahead].strip():
                    lookahead += 1
                if lookahead < total and LIST_ITEM_RE.match(lines[lookahead].strip()):
                    index = lookahead
                    continue
            break
        out.append("<li>" + inline(match.group(1)) + "</li>")
        index += 1
    out.append("</" + tag + ">")
    return index


def markdown_to_html(markdown: str) -> str:
    """Convert the subset of markdown used by the privacy policy."""
    lines = markdown.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    index = 0
    total = len(lines)
    first_paragraph = True
    while index < total:
        stripped = lines[index].strip()
        if not stripped:
            index += 1
            continue
        heading = HEADING_RE.match(stripped)
        if heading is not None:
            level = len(heading.group(1))
            out.append("<h" + str(level) + ">" + inline(heading.group(2)) + "</h" + str(level) + ">")
            index += 1
            continue
        if stripped.startswith("|"):
            rows = []
            while index < total and lines[index].strip().startswith("|"):
                rows.append(lines[index].strip())
                index += 1
            out.append(render_table(rows))
            continue
        if LIST_ITEM_RE.match(stripped):
            index = render_list(lines, index, out)
            continue
        if re.fullmatch(r"(?:-{3,}|\*{3,}|_{3,})", stripped):
            out.append("<hr>")
            index += 1
            continue
        paragraph = [stripped]
        index += 1
        while index < total and lines[index].strip():
            nxt = lines[index].strip()
            if (
                HEADING_RE.match(nxt)
                or LIST_ITEM_RE.match(nxt)
                or nxt.startswith("|")
                or re.fullmatch(r"(?:-{3,}|\*{3,}|_{3,})", nxt)
            ):
                break
            paragraph.append(nxt)
            index += 1
        text = " ".join(paragraph)
        css = ' class="updated"' if first_paragraph and text.startswith("*") else ""
        first_paragraph = False
        out.append("<p" + css + ">" + inline(text) + "</p>")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

HEAD_TEMPLATE = """<!DOCTYPE html>
<html lang="{html_lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{canonical}">
<meta property="og:type" content="{og_type}">
<meta property="og:site_name" content="Sonoglitch">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{canonical}">
<meta property="og:locale" content="{og_locale}">
{og_image}<link rel="icon" href="{prefix}img/icon.svg" type="image/svg+xml">
{alternate}<link rel="stylesheet" href="{prefix}styles.css">
</head>
"""


def head(
    page: dict[str, object],
    prefix: str,
    og_type: str,
    og_image: str,
    alternate: str = "",
) -> str:
    return HEAD_TEMPLATE.format(
        html_lang=page["html_lang"],
        title=html.escape(str(page["title"]), quote=True),
        description=html.escape(str(page["description"]), quote=True),
        canonical=page["canonical"],
        og_type=og_type,
        og_locale=page["og_locale"],
        og_image=og_image,
        prefix=prefix,
        alternate=alternate,
    )


def topbar(page: dict[str, object], home: str) -> str:
    nav = "".join(
        '<a href="#' + anchor + '">' + html.escape(label) + "</a>"
        for anchor, label in page["nav"]  # type: ignore[union-attr]
    )
    return (
        '<header class="topbar"><div class="wrap">'
        '<a class="brand" href="' + home + '">Sonoglitch</a>'
        '<nav class="nav" aria-label="' + html.escape(str(page["nav_label"]), quote=True) + '">'
        + nav
        + '<a class="lang" href="' + str(page["other_path"]) + '" hreflang="'
        + str(page["other_lang"])
        + '" lang="'
        + str(page["other_lang"])
        + '">'
        + html.escape(str(page["other_label"]))
        + "</a>"
        "</nav></div></header>"
    )


def render_index(
    language: str,
    gallery: list[tuple[str, tuple[int, int] | None]],
    og_image: str,
) -> str:
    """Render the landing page in one of the two languages."""
    page = CONTENT[language]
    prefix = "" if language == "en" else "../"
    styles = "".join(
        "<li><strong>"
        + html.escape(name)
        + "</strong> — "
        + html.escape(description)
        + "</li>"
        for name, description in page["styles"]  # type: ignore[union-attr]
    )
    features = "".join(
        "<li>" + html.escape(item) + "</li>" for item in page["features"]  # type: ignore[union-attr]
    )
    soon = html.escape(str(page["download_soon"]))
    buttons = (
        '<p class="buttons">'
        '<a class="button primary" href="'
        + RELEASES_URL
        + '">'
        + html.escape(str(page["download_github"]))
        + "</a>"
        '<span class="button disabled" aria-disabled="true">Google Play — '
        + soon
        + "</span>"
        '<span class="button disabled" aria-disabled="true">F-Droid — '
        + soon
        + "</span>"
        "</p>"
    )
    gallery_html = ""
    if gallery:
        items = ""
        for name, size in gallery:
            alt = GALLERY_ALT[language].get(name, GALLERY_ALT_DEFAULT[language])
            attributes = ""
            if size is not None:
                attributes = ' width="' + str(size[0]) + '" height="' + str(size[1]) + '"'
            items += (
                '<li><img src="'
                + prefix
                + "img/"
                + html.escape(name, quote=True)
                + '" alt="'
                + html.escape(alt, quote=True)
                + '"'
                + attributes
                + ' loading="lazy"></li>'
            )
        gallery_html = (
            '<section id="'
            + ("gallery" if language == "en" else "galeria")
            + '"><div class="wrap"><h2>'
            + html.escape(str(page["gallery_title"]))
            + "</h2><p>"
            + html.escape(str(page["gallery_intro"]))
            + '</p><ul class="gallery">'
            + items
            + "</ul></div></section>"
        )
    privacy_note = ""
    if page["privacy_note"]:
        privacy_note = (
            "<p>"
            + html.escape(str(page["privacy_note"]))
            + ' <a href="'
            + prefix
            + 'privacy/">'
            + html.escape(str(page["privacy_link_label"]))
            + "</a>.</p>"
        )
    else:
        privacy_note = (
            '<p><a href="' + prefix + 'privacy/">'
            + html.escape(str(page["privacy_link_label"]))
            + "</a>.</p>"
        )
    body = (
        topbar(page, "./" if language == "en" else "../")
        + '<main>'
        + '<section class="hero"><div class="wrap">'
        + '<img class="icon" src="'
        + prefix
        + 'img/icon.svg" width="96" height="96" alt="'
        + html.escape(str(page["icon_alt"]), quote=True)
        + '">'
        + '<h1><span class="glitch" data-text="Sonoglitch">Sonoglitch</span></h1>'
        + '<p class="pitch">'
        + html.escape(str(page["pitch"]))
        + "</p>"
        + buttons
        + '<p class="note">'
        + html.escape(str(page["note"]))
        + "</p>"
        + "</div></section>"
        + '<section id="'
        + ("styles" if language == "en" else "estilos")
        + '"><div class="wrap"><h2>'
        + html.escape(str(page["styles_title"]))
        + "</h2><p>"
        + html.escape(str(page["styles_intro"]))
        + '</p><ul class="styles">'
        + styles
        + "</ul></div></section>"
        + '<section id="'
        + ("features" if language == "en" else "funciones")
        + '"><div class="wrap"><h2>'
        + html.escape(str(page["features_title"]))
        + '</h2><ul class="features">'
        + features
        + "</ul></div></section>"
        + gallery_html
        + '<section id="'
        + ("support" if language == "en" else "soporte")
        + '"><div class="wrap"><h2>'
        + html.escape(str(page["support_title"]))
        + "</h2><p>"
        + html.escape(str(page["support_text"]))
        + ' <a href="'
        + KOFI_URL
        + '">'
        + html.escape(str(page["support_link_label"]))
        + "</a>.</p></div></section>"
        + '<section id="'
        + ("privacy" if language == "en" else "privacidad")
        + '"><div class="wrap"><h2>'
        + html.escape(str(page["privacy_title"]))
        + "</h2><p>"
        + html.escape(str(page["privacy_text"]))
        + "</p>"
        + privacy_note
        + '<p><a href="'
        + REPO_URL
        + '">'
        + html.escape(str(page["repo_label"]))
        + "</a> — "
        + html.escape(str(page["repo_text"]))
        + "</p></div></section>"
        + "</main>"
        + '<footer><div class="wrap">'
        + '<p><a href="mailto:'
        + CONTACT_EMAIL
        + '">'
        + CONTACT_EMAIL
        + "</a></p>"
        + "<p>"
        + html.escape(str(page["footer_note"]))
        + "</p></div></footer>"
    )
    alternate = (
        '<link rel="alternate" hreflang="'
        + str(page["other_lang"])
        + '" href="'
        + SITE_URL
        + ("/es/" if language == "en" else "/")
        + '">\n'
    )
    return head(page, prefix, "website", og_image, alternate) + "<body>" + body + "</body>\n</html>\n"


def render_privacy(og_image: str) -> str:
    """Render the privacy policy page from ``docs/PRIVACY.md``."""
    policy = PRIVACY_MD.read_text(encoding="utf-8")
    content = markdown_to_html(policy)
    page = {
        "html_lang": "en",
        "title": "Privacy policy — Sonoglitch",
        "description": (
            "How Sonoglitch handles your data: audio is never recorded, stored or "
            "transmitted, and the release builds have no network access."
        ),
        "canonical": SITE_URL + "/privacy/",
        "og_type": "article",
        "og_locale": "en",
        "other_lang": "es",
    }
    body = (
        '<header class="topbar"><div class="wrap">'
        '<a class="brand" href="../">Sonoglitch</a>'
        '<nav class="nav" aria-label="Main">'
        '<a class="lang" href="../es/" hreflang="es" lang="es">Español</a>'
        "</nav></div></header>"
        '<main class="prose">'
        + content
        + "</main>"
        '<footer><div class="wrap">'
        + '<p><a href="mailto:' + CONTACT_EMAIL + '">' + CONTACT_EMAIL + "</a></p>"
        + "<p>Sonoglitch is licensed under Apache-2.0.</p>"
        "</div></footer>"
    )
    return head(page, "../", "article", og_image) + "<body>" + body + "</body>\n</html>\n"

def render_404(og_image: str) -> str:
    """Render the not found page.

    GitHub Pages serves this file for any missing path, so its links are
    absolute and carry the project prefix.
    """
    page = {
        "html_lang": "en",
        "title": "Page not found — Sonoglitch",
        "description": "The page you asked for does not exist on the Sonoglitch website.",
        "canonical": SITE_URL + "/404.html",
        "og_type": "website",
        "og_locale": "en",
        "other_lang": "es",
    }
    body = (
        '<header class="topbar"><div class="wrap">'
        '<a class="brand" href="' + SITE_PATH + '/">Sonoglitch</a>'
        '<nav class="nav" aria-label="Main">'
        '<a class="lang" href="' + SITE_PATH + '/es/" hreflang="es" lang="es">Español</a>'
        "</nav></div></header>"
        '<main class="prose">'
        "<h1>Page not found</h1>"
        "<p>The page you asked for is not here. "
        '<a href="' + SITE_PATH + '/">Go back to the home page</a>.</p>'
        "</main>"
    )
    return head(page, SITE_PATH + "/", "website", og_image) + "<body>" + body + "</body>\n</html>\n"


STYLES_CSS = """/* Sonoglitch website. Dark by default, light on request. No JavaScript. */
:root {
  color-scheme: dark light;
  --bg: #0D0D11;
  --surface: #16161C;
  --surface-high: #1F1F27;
  --outline: #2C2C36;
  --accent: #B69CFF;
  --accent-hover: #A88CF5;
  --on-accent: #17121F;
  --warm: #FFB37A;
  --text: #F3F3F6;
  --text-2: #A5A5B2;
  --fringe-a: #55E5F2;
  --fringe-b: #F36CCB;
  --radius: 12px;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #F6F4FA;
    --surface: #FFFFFF;
    --surface-high: #EFEBF8;
    --outline: #D8D2E6;
    --accent: #6E5AA8;
    --accent-hover: #5B4A8E;
    --on-accent: #FFFFFF;
    --warm: #8F4E1E;
    --text: #17141F;
    --text-2: #55506B;
    --fringe-a: #0E8C99;
    --fringe-b: #B32A83;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.65 system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  overflow-wrap: break-word;
}
img { max-width: 100%; height: auto; }
a { color: var(--accent); text-decoration: underline; text-underline-offset: 2px; }
a:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; border-radius: 2px; }
.wrap { max-width: 960px; margin: 0 auto; padding-left: 16px; padding-right: 16px; }
.topbar { border-bottom: 1px solid var(--outline); }
.topbar .wrap {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
  gap: 8px 16px; padding-top: 12px; padding-bottom: 12px;
}
.brand { font-weight: 700; text-decoration: none; letter-spacing: .01em; }
.nav { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 16px; font-size: .95rem; }
.nav a { text-decoration: none; color: var(--text-2); }
.nav a:hover, .nav a:focus-visible { color: var(--accent); }
.nav .lang { color: var(--accent); }
.hero { padding: 48px 0 32px; text-align: center; }
.hero .icon {
  display: block; width: 96px; height: 96px; margin: 0 auto;
  border-radius: 20px; border: 1px solid var(--outline);
}
h1 {
  font-size: clamp(2rem, 8vw, 3.25rem); line-height: 1.1; margin: 16px 0 12px;
  letter-spacing: -0.02em;
}
h2 { font-size: clamp(1.3rem, 4.5vw, 1.7rem); line-height: 1.25; margin: 0 0 12px; }
p { margin: 0 0 1rem; }
.pitch { max-width: 46ch; margin-left: auto; margin-right: auto; font-size: 1.05rem; }
.note { color: var(--text-2); font-size: .9rem; }
.buttons { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; margin: 24px 0 12px; }
.button {
  display: inline-block; padding: 11px 18px; border-radius: 999px;
  border: 1px solid var(--outline); background: var(--surface); color: var(--text);
  font-size: .95rem; font-weight: 600; text-decoration: none;
}
.button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
/* The hover keeps a contrast of 4.5:1 with its text in both palettes. */
.button.primary:hover { background: var(--accent-hover); border-color: var(--accent-hover); color: var(--on-accent); }
.button.disabled { color: var(--text-2); cursor: default; }
section { padding: 28px 0; }
.styles {
  list-style: none; margin: 0; padding: 0; display: grid; gap: 12px;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
}
.styles li {
  background: var(--surface); border: 1px solid var(--outline);
  border-radius: var(--radius); padding: 14px 16px;
}
.styles strong { color: var(--accent); }
.features { margin: 0; padding-left: 1.15rem; }
.features li { margin-bottom: .45rem; }
.gallery {
  list-style: none; margin: 0; padding: 0; display: grid; gap: 16px;
  grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
}
.gallery img {
  display: block; width: 100%; border: 1px solid var(--outline);
  border-radius: 10px; background: var(--surface);
}
footer {
  border-top: 1px solid var(--outline); margin-top: 24px; padding: 20px 0 48px;
  color: var(--text-2); font-size: .9rem;
}
footer p { margin: 0 0 .4rem; }
.prose { max-width: 760px; margin: 0 auto; padding: 24px 16px 48px; }
.prose h1 { font-size: clamp(1.75rem, 6vw, 2.5rem); margin-top: 8px; }
.prose h2 { margin-top: 2rem; }
.prose h3 { margin-top: 1.5rem; font-size: 1.1rem; }
.prose ul { padding-left: 1.15rem; }
.prose li { margin-bottom: .35rem; }
.prose p.updated { color: var(--text-2); }
.prose code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
  background: var(--surface-high); border-radius: 4px; padding: .1em .35em; font-size: .9em;
}
.table-wrap { overflow-x: auto; margin: 0 0 1rem; }
table { border-collapse: collapse; width: 100%; min-width: 520px; font-size: .95rem; }
th, td { border: 1px solid var(--outline); padding: 8px 10px; text-align: left; vertical-align: top; }
th { background: var(--surface-high); }
hr { border: 0; border-top: 1px solid var(--outline); margin: 2rem 0; }
/* The title is the only element with the glitch fringe. */
.glitch { position: relative; display: inline-block; }
.glitch::before, .glitch::after {
  content: attr(data-text); position: absolute; inset: 0; pointer-events: none; opacity: .8;
}
.glitch::before {
  color: var(--fringe-a); clip-path: inset(0 0 76% 0);
  animation: fringe-a 3.4s steps(2, end) infinite;
}
.glitch::after {
  color: var(--fringe-b); clip-path: inset(76% 0 0 0);
  animation: fringe-b 2.9s steps(2, end) infinite;
}
@keyframes fringe-a {
  0%, 88%, 100% { transform: translate(0, 0); }
  90% { transform: translate(-2px, -1px); }
  94% { transform: translate(1px, 1px); }
}
@keyframes fringe-b {
  0%, 86%, 100% { transform: translate(0, 0); }
  88% { transform: translate(2px, 1px); }
  93% { transform: translate(-1px, -1px); }
}
@media (prefers-reduced-motion: reduce) {
  .glitch::before, .glitch::after { animation: none; transform: none; }
}
@media (max-width: 420px) {
  .hero { padding-top: 32px; }
  .buttons .button { width: 100%; text-align: center; }
}
"""


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------


def gallery_sources() -> list[Path]:
    """The screenshots of ``docs/readme/``, in a stable order."""
    if not DOCS_README.is_dir():
        return []
    found = [
        path
        for path in DOCS_README.iterdir()
        if path.is_file() and GALLERY_PATTERN.match(path.name)
    ]
    return sorted(found)


def png_size(path: Path) -> tuple[int, int] | None:
    """Return the size of a PNG, read from its header.

    The standard library is enough: the size is in the first chunk of the
    file, so no image library is needed to write the gallery.
    """
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    if header[12:16] != b"IHDR":
        return None
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    return (width, height)


def og_tag(og_image: bool) -> str:
    """The Open Graph image tag, omitted when there is no image.

    The address is absolute: the pages are published in more than one folder,
    so a relative path would point to a file that does not exist.
    """
    if not og_image:
        return ""
    return (
        '<meta property="og:image" content="'
        + OG_IMAGE_URL
        + '">\n'
        + '<meta name="twitter:image" content="'
        + OG_IMAGE_URL
        + '">\n'
    )


def clean(out_dir: Path) -> None:
    """Remove the entries this generator owns, so a build never leaves stale files."""
    for name in MANAGED:
        target = out_dir / name
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()


def guard(out_dir: Path) -> None:
    """Refuse to build into the repository root or above it."""
    out = out_dir.resolve()
    if out == ROOT or out in ROOT.parents or out == Path(out.anchor):
        raise SystemExit("refusing to build into " + str(out))


def build(out_dir: Path) -> list[str]:
    """Write the whole site into ``out_dir`` and return the written files."""
    guard(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    clean(out_dir)
    written: list[str] = []

    def write(relative: str, text: str) -> None:
        target = out_dir / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
        written.append(relative)

    images = out_dir / "img"
    images.mkdir(parents=True, exist_ok=True)
    # The icon is copied as text, with the line endings normalised, so the
    # output is the same on every platform.
    (images / "icon.svg").write_text(
        ICON_SVG.read_text(encoding="utf-8").replace("\r\n", "\n"),
        encoding="utf-8",
        newline="\n",
    )
    written.append("img/icon.svg")

    gallery: list[tuple[str, tuple[int, int] | None]] = []
    for source in gallery_sources():
        name = source.name
        # The screenshots are copied as they are: the pipeline of
        # ``tool/readme/process_screenshots.py`` already made them small
        # enough, and the output has to be the same with and without Pillow.
        shutil.copyfile(source, images / name)
        written.append("img/" + name)
        gallery.append((name, png_size(source)))

    has_og = (DOCS_README / "og.png").is_file()
    if has_og:
        shutil.copyfile(DOCS_README / "og.png", images / "og.png")
        written.append("img/og.png")
    og_image = og_tag(has_og)

    write("index.html", render_index("en", gallery, og_image))
    write("es/index.html", render_index("es", gallery, og_image))
    write("privacy/index.html", render_privacy(og_image))
    write("404.html", render_404(og_image))
    write("styles.css", STYLES_CSS)
    write("robots.txt", "User-agent: *\nAllow: /\n")
    write(".nojekyll", "")
    return written


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the Sonoglitch website.")
    parser.add_argument(
        "--out",
        default=str(DEFAULT_OUT),
        help="folder to write the site into (default: site/)",
    )
    args = parser.parse_args(argv)
    written = build(Path(args.out))
    print("Written " + str(len(written)) + " files in " + str(args.out))
    for name in written:
        print("  " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
