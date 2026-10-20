#!/usr/bin/env python3
"""Exports Hora Cero for the web into a folder, ready to be served at the root of a site (https://horacero.app/):
the release export of the project's "Web" preset, its page (godot/web/shell.html) given the game's title,
description and link-preview tags (Open Graph and Twitter, with the image og.jpg next to the page, copied from
tools/site/og.jpg), and the pack cut into parts no bigger than PART_BYTES, because a site deployed from a Git
repository may take no file over 100 MB (GitHub's limit). The page fetches the parts in order and hands them to the
engine as one pack; window.HORACERO_PACK_PARTS, written into the page here, lists them, and window.HORACERO_BUILD names
the build ("web 2026-10-18 abc1234": the day and the commit).

    python3 tools/web_site_build.py <out dir>
    python3 tools/web_site_build.py --ink <out dir>                      # drawn in comic ink from the start
    python3 tools/web_site_build.py --feedback-url https://... <out dir> # the questions on, posting there
    python3 tools/web_site_build.py --site https://example.org/ <out dir>

--ink adds the custom feature "comic_ink" for this export (scripts/three_d/ink.gd); godot/export_presets.cfg is
changed for the time of the export only and put back byte for byte afterwards, failed export or not.

--feedback-url <url> turns the launch screen's questions on for this build: the answers are posted to <url> as one JSON
object (scripts/feedback.gd). --feedback-header "Name: value" (repeatable) adds a request header, for a service that
wants a key. Both go into this build's page only (window.HORACERO_FEEDBACK_URL / _HEADERS), never into the repository.
Without --feedback-url the game offers no questions and sends nothing anywhere.

--site <url> is where the page is served from (its link previews point there): https://horacero.app/ unless given.

GODOT names the Godot 4.7 binary (export templates installed); else `godot` on the PATH."""
import datetime
import html
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PRESETS = os.path.join(ROOT, "godot", "export_presets.cfg")
PART_BYTES = 48 * 1024 * 1024
FONTS = ["BarlowCondensed-SemiBold.ttf", "BigShouldersStencilDisplay-wght.ttf"]
SITE = "https://horacero.app/"
PRESET = "Web"
TITLE = "Hora Cero · Invasión Buenos Aires"
DESCRIPTION = ("Buenos Aires, 1958, la noche en que empieza a nevar: poné a cubierto a la gente de la Plaza de Mayo antes "
               "de que la nieve la tape, y después cruzá el Riachuelo. Un adelanto para jugar en el navegador.")
IMAGE_ALT = "Hora Cero: la Plaza de Mayo de noche, cuando empieza a nevar."
OG_IMAGE = os.path.join(ROOT, "tools", "site", "og.jpg")


def godot() -> str:
    found = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if not found:
        sys.exit("set GODOT to the Godot 4.7 binary (export templates installed)")
    return found


def main(out: str, ink: bool = False, feedback_url: str = "", feedback_headers: list = (), site: str = SITE) -> None:
    out = os.path.abspath(out)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    page = os.path.join(out, "index.html")
    with swapped(PRESETS, lambda text: with_features(text, PRESET, ["comic_ink"] if ink else [])):
        subprocess.run([godot(), "--headless", "--path", os.path.join(ROOT, "godot"), "--export-release", PRESET, page], check=True)
    pack = os.path.join(out, "index.pck")
    parts = []
    with open(pack, "rb") as f:
        while True:
            chunk = f.read(PART_BYTES)
            if not chunk:
                break
            name = f"index.pck.part{len(parts)}"
            with open(os.path.join(out, name), "wb") as p:
                p.write(chunk)
            parts.append(name)
    os.remove(pack)
    text = open(page, encoding="utf-8").read()
    build = build_name()
    listing = "<script>window.HORACERO_BUILD = %s; window.HORACERO_PACK_PARTS = [%s];" % (
        json.dumps(build), ", ".join(json.dumps(p) for p in parts))
    if feedback_url:
        listing += " window.HORACERO_FEEDBACK_URL = %s;" % json.dumps(feedback_url)
        if feedback_headers:
            listing += " window.HORACERO_FEEDBACK_HEADERS = %s;" % json.dumps("\n".join(feedback_headers))
    listing += "</script>\n\t\t"
    marker = '<script src="index.js"></script>'
    if marker not in text:
        sys.exit("the page has no engine script to put the parts before")
    text = text.replace(marker, listing + marker, 1)
    text = site_page(text, site)
    open(page, "w", encoding="utf-8").write(text)
    if os.path.isfile(OG_IMAGE):
        shutil.copy(OG_IMAGE, os.path.join(out, "og.jpg"))
    else:
        print("warning: no", OG_IMAGE, "for the link preview's og.jpg", file=sys.stderr)
    os.makedirs(os.path.join(out, "fonts"))
    for name in FONTS:
        shutil.copy(os.path.join(ROOT, "godot", "assets", "fonts", name), os.path.join(out, "fonts", name))
    print("web build in", out, "build:", build, "pack parts:", ", ".join(parts),
          "feedback:", feedback_url or "off")


class swapped:
    """A project file changed for the time of an export, then put back byte for byte, failed export or not."""

    def __init__(self, path: str, change):
        self.path, self.change = path, change

    def __enter__(self):
        self.original = open(self.path, "rb").read()
        open(self.path, "wb").write(self.change(self.original.decode("utf-8")).encode("utf-8"))

    def __exit__(self, *exc):
        open(self.path, "wb").write(self.original)
        if open(self.path, "rb").read() != self.original:
            sys.exit(f"{os.path.relpath(self.path, ROOT)} could not be put back as it was")
        return False


def with_features(text: str, preset: str, features: list) -> str:
    """export_presets.cfg with the named preset's custom_features extended by the given features."""
    if not features:
        return text
    sections = re.split(r"(?m)^(?=\[)", text)
    for i, section in enumerate(sections):
        if re.match(r"\[preset\.\d+\]", section) and re.search(r'(?m)^name="%s"$' % re.escape(preset), section):
            had = re.search(r'(?m)^custom_features="(.*)"$', section).group(1)
            value = ",".join([f for f in had.split(",") if f] + features)
            sections[i] = re.sub(r'(?m)^custom_features=.*$', lambda _: f'custom_features="{value}"', section, count=1)
            return "".join(sections)
    sys.exit(f"export_presets.cfg has no {preset} preset")


def site_page(text: str, site: str) -> str:
    """The page as the site's own: its title and description, and the link-preview tags pointing at the site."""
    url = site if site.endswith("/") else site + "/"
    title = html.escape(TITLE)
    description = html.escape(DESCRIPTION)
    alt = html.escape(IMAGE_ALT)
    tags = "\n\t\t".join([
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Hora Cero">',
        f'<meta property="og:title" content="{title}">',
        f'<meta property="og:description" content="{description}">',
        f'<meta property="og:url" content="{url}">',
        f'<meta property="og:image" content="{url}og.jpg">',
        '<meta property="og:image:type" content="image/jpeg">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        f'<meta property="og:image:alt" content="{alt}">',
        '<meta property="og:locale" content="es_AR">',
        '<meta property="og:locale:alternate" content="en_US">',
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{title}">',
        f'<meta name="twitter:description" content="{description}">',
        f'<meta name="twitter:image" content="{url}og.jpg">',
        f'<meta name="twitter:image:alt" content="{alt}">',
    ])
    swaps = [
        (r'<meta name="description" content="[^"]*">', lambda m: f'<meta name="description" content="{description}">\n\t\t{tags}'),
        (r"<title>[^<]*</title>", lambda m: f"<title>{title}</title>"),
    ]
    for pattern, make in swaps:
        text, count = re.subn(pattern, make, text, count=1)
        if count != 1:
            sys.exit(f"the page has nothing that matches {pattern}")
    return text


def build_name(kind: str = "web") -> str:
    """"web 2026-10-18 abc1234": the day of the build and the commit it was made from (with a + if it had changes)."""
    day = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    try:
        sha = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                             check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--untracked-files=no"],
                               capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return f"{kind} {day}"
    return f"{kind} {day} {sha}{'+' if dirty else ''}"


def _take(args: list, flag: str) -> list:
    """Every value given after `flag` (removed from args)."""
    values = []
    while flag in args:
        i = args.index(flag)
        if i + 1 >= len(args):
            sys.exit(f"{flag} needs a value")
        values.append(args[i + 1])
        del args[i:i + 2]
    return values


if __name__ == "__main__":
    args = sys.argv[1:]
    inked = "--ink" in args
    if inked:
        args.remove("--ink")
    urls = _take(args, "--feedback-url")
    headers = _take(args, "--feedback-header")
    sites = _take(args, "--site")
    if len(urls) > 1 or len(sites) > 1 or (headers and not urls):
        sys.exit(__doc__)
    if urls and not re.match(r"^https?://", urls[0]):
        sys.exit("--feedback-url takes an http(s) address")
    if any(":" not in h for h in headers):
        sys.exit("--feedback-header takes \"Name: value\"")
    if len(args) != 1 or args[0].startswith("-"):
        sys.exit(__doc__)
    main(args[0], inked, urls[0] if urls else "", headers, sites[0] if sites else SITE)
