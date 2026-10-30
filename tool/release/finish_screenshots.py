#!/usr/bin/env python3
"""Turns the raw screenshots of ``.local/capturas/`` into everything that uses them.

One command, after the captures are in place:

    python tool/release/finish_screenshots.py

It runs ``tool/readme/process_screenshots.py`` (README and Google Play
versions), copies the Google Play versions to
``fastlane/metadata/android/{en-US,es-ES}/images/phoneScreenshots/`` (the
folder Google Play, F-Droid and ``fastlane supply`` read), switches on the
screenshots section of both READMEs. The website (web/) is regenerated separately. The result is
left uncommitted so it can be reviewed.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / ".local" / "capturas"
PLAY = ROOT / "docs" / "readme" / "play"
LOCALES = ("en-US", "es-ES")

#: The section is commented out in the READMEs until the pictures exist.
SECTION = re.compile(
    r"<!--\r?\n(## (?:Screenshots|Capturas)\r?\n.*?)-->\r?\n", re.DOTALL
)


def run(*command: str) -> None:
    print("$", " ".join(command))
    subprocess.run(command, cwd=ROOT, check=True)


def enable_readme_section(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    updated, count = SECTION.subn(r"\1", text, count=1)
    if count:
        path.write_text(updated, encoding="utf-8", newline="")
    return bool(count)


def main() -> int:
    raw = sorted(RAW.glob("*")) if RAW.is_dir() else []
    if not raw:
        print("No captures in %s: put the screenshots there first." % RAW, file=sys.stderr)
        return 1
    run(sys.executable, "tool/readme/process_screenshots.py")

    shots = sorted(PLAY.glob("*.png"))
    if len(shots) < 2:
        print("Google Play needs at least two phone screenshots.", file=sys.stderr)
        return 1
    for locale in LOCALES:
        target = ROOT / "fastlane" / "metadata" / "android" / locale / "images" / "phoneScreenshots"
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)
        for shot in shots:
            shutil.copy2(shot, target / shot.name)
    print("Copied %d Google Play screenshots to fastlane (en-US, es-ES)." % len(shots))

    for name in ("README.md", "README.es.md"):
        path = ROOT / name
        if path.exists():
            print("%s: screenshots section %s" % (name, "enabled" if enable_readme_section(path) else "already on or not found"))

    print("Done. Review `git status`, then commit, and regenerate the website from web/.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
