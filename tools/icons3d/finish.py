#!/usr/bin/env python3
"""Before and after the 3D icon renders (tools/icons3d/studio.gd).

    python3 tools/icons3d/finish.py prepare <out_dir>   # badge normal maps from godot/assets/ui/badges.png
    python3 tools/icons3d/finish.py sheets <out_dir>    # outlines, HUD sizes and the comparison sheets
    python3 tools/icons3d/finish.py contact <out_dir> knife rope ...   # a check sheet for some icons
    python3 tools/icons3d/finish.py atlas <out_dir>     # the game's atlases: assets/ui/icons3d.png and medals.png

The renders are 1024 px with a transparent background. "sheets" crops each to its content, adds a thin ink outline
so the object reads on the dark plates and on the paper dossier, scales it to the sizes the game draws icons at
(34 and 26 px on a phone at 1x, so 68 and 52 at 2x) and lays the new icons beside today's glyphs.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
GLYPHS = ["crouch", "walk", "throw", "key", "cell", "rescue", "boat", "pause", "play", "rot_l", "rot_r", "brief",
          "knife", "bind", "pistol", "revolver", "tripwire", "cutters", "radio", "carry", "drop", "hide", "flag", "tap",
          "drag", "pinch", "target", "eye", "clock", "cross", "limpet", "charge", "switch", "cigarette", "gate", "cosh",
          "bottle", "uniform", "rope", "talk", "skis", "phone", "smg", "snowsuit", "window", "duct"]
BADGES = ["ghost", "clean_hands", "not_a_shot", "saboteur", "swift"]
## The objects in the game's icon atlas, in atlas order (ActionSlot.ICONS3D must list the same; "atlas" checks).
ICONS3D = ["throw", "key", "cell", "boat", "brief", "knife", "bind", "pistol", "revolver", "tripwire", "cutters",
           "radio", "hide", "flag", "clock", "limpet", "charge", "switch", "cigarette", "gate", "cosh", "bottle",
           "uniform", "rope", "skis", "phone", "smg", "snowsuit", "window", "duct", "lampkey", "bell", "papers", "oars",
           "handle", "cord", "ladder", "cellar", "lampboard", "gondola", "rowboat", "flatcap", "motorcap", "hand", "tram",
           "subte", "tarp", "stretcher"]
ATLAS_CELL = 192
ATLAS_COLS = 8
MEDAL_CELL = 192
## Transparent border kept round every cell so mipmaps of one icon never pick up its neighbour.
GUTTER = 4
## The light rim: ivory outline with an ink line inside, sized for an icon drawn 68 px across.
RIM = (214, 206, 180)
RIM_AT = 68
INK = (20, 23, 17)
PLATE = (40, 44, 40)
PAPER = (236, 230, 210)
IVORY = (236, 230, 210)
FONT = GODOT / "assets/fonts/BarlowCondensed-SemiBold.ttf"


def prepare(out: Path) -> None:
    prep = out / "prep"
    prep.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(GODOT / "assets/ui/badges.png").convert("RGBA")
    cell = 176
    for i, name in enumerate(BADGES):
        stamp = sheet.crop((i * cell, 0, (i + 1) * cell, cell)).resize((512, 512), Image.LANCZOS)
        a = np.asarray(stamp, dtype=np.float32) / 255.0
        height = a[..., 3] * a[..., :3].mean(axis=2)
        h_img = Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))
        h = np.asarray(h_img, dtype=np.float32) / 255.0
        gx = np.zeros_like(h)
        gy = np.zeros_like(h)
        gx[:, 1:-1] = (h[:, 2:] - h[:, :-2]) * 0.5
        gy[1:-1, :] = (h[2:, :] - h[:-2, :]) * 0.5
        strength = 9.0
        n = np.dstack([-gx * strength, gy * strength, np.ones_like(h)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(prep / f"badge_{name}_n.png")
        albedo = 0.72 + 0.28 * h
        Image.fromarray((np.dstack([albedo] * 3) * 255).astype(np.uint8)).save(prep / f"badge_{name}_a.png")
    print("prepared", prep)


def cropped(img: Image.Image, pad: float = 0.03) -> Image.Image:
    """Square crop round the object's pixels, with a margin."""
    box = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if not box:
        return img
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    side = int(side * (1 + 2 * pad))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)), (0, 0))
    return canvas


def outlined(img: Image.Image, size: int, width: float, colour=INK, inner: float = 0.0) -> Image.Image:
    """Scale to `size` and add an outline `width` px wide (at that size) round the silhouette; `inner` adds a thin
    ink line inside a light outline so the object keeps its edge on light and dark grounds alike."""
    big = 4
    work = img.resize((size * big, size * big), Image.LANCZOS)
    alpha = work.getchannel("A")
    grow = max(1, int(round(width * big)))
    spread = grown(alpha, grow).filter(ImageFilter.GaussianBlur(big * 0.6))
    rim = Image.new("RGBA", work.size, tuple(colour) + (0,))
    rim.putalpha(spread)
    if inner > 0:
        line = Image.new("RGBA", work.size, INK + (0,))
        line.putalpha(grown(alpha, max(1, int(round(inner * big)))))
        rim.alpha_composite(line)
    rim.alpha_composite(work)
    return rim.resize((size, size), Image.LANCZOS)


def grown(mask: Image.Image, r: int) -> Image.Image:
    """The mask spread `r` px every way (a square max filter, as PIL's MaxFilter(2r + 1), done in two passes so
    a wide outline on a big atlas cell stays quick)."""
    a = np.asarray(mask)
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r, r)
        p = np.pad(a, pad)
        n = a.shape[axis]
        a = np.max([np.take(p, range(i, i + n), axis=axis) for i in range(2 * r + 1)], axis=0)
    return Image.fromarray(a, "L")


def lifted(img: Image.Image, gain: float = 1.25) -> Image.Image:
    """Brighter mid-tones for the dark HUD plates (alpha kept)."""
    a = np.asarray(img, dtype=np.float32) / 255.0
    rgb = np.clip(1.0 - (1.0 - a[..., :3]) ** gain, 0, 1)
    return Image.fromarray((np.dstack([rgb, a[..., 3:]]) * 255).astype(np.uint8), "RGBA")


def label(draw: ImageDraw.ImageDraw, xy, text, size=16, fill=IVORY):
    draw.text(xy, text, font=ImageFont.truetype(str(FONT), size), fill=fill)


def glyph(name: str, size: int, colour=IVORY) -> Image.Image:
    sheet = Image.open(GODOT / "assets/ui/glyphs.png").convert("RGBA")
    i = GLYPHS.index(name)
    cell = 96
    g = sheet.crop(((i % 6) * cell, (i // 6) * cell, (i % 6 + 1) * cell, (i // 6 + 1) * cell))
    tinted = Image.new("RGBA", g.size, colour + (0,))
    tinted.putalpha(g.getchannel("A"))
    return tinted.resize((size, size), Image.LANCZOS)


def sheets(out: Path) -> None:
    final = out / "final"
    final.mkdir(exist_ok=True)
    renders = {p.stem: Image.open(p).convert("RGBA") for p in sorted(out.glob("*.png"))}
    icons = {name: cropped(img) for name, img in renders.items()}
    for name, img in icons.items():
        outlined(img, 256, 3.0).save(final / f"{name}_256.png")

    kit = [n for n in ["knife", "pistol", "radio", "limpet", "cutters", "rope"] if n in icons]
    # 1. The style sheet: each icon large on the dark plate and on the dossier paper.
    cellw = 300
    sheet = Image.new("RGB", (cellw * len(kit), 2 * cellw + 40), PLATE)
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(kit):
        icon = outlined(icons[name], 240, 3.0)
        sheet.paste(icon, (i * cellw + 30, 20), icon)
        d.rectangle((i * cellw, cellw + 20, (i + 1) * cellw, 2 * cellw + 40), fill=PAPER)
        sheet.paste(icon, (i * cellw + 30, cellw + 40), icon)
        label(d, (i * cellw + 12, 2), name.upper(), 15)
    sheet.save(final / "sheet_kit.png")

    # 2. At play size: the HUD's kit row at 2x (68 px and 52 px), today's glyphs above the 3D icons.
    plate = Image.open(GODOT / "assets/ui/plate.png").convert("RGBA")
    rows = [("TODAY", None), ("3D INK", None), ("3D RIM", None)]
    sizes = [68, 52]
    w = 140 + len(kit) * 96
    h = 60 + len(sizes) * len(rows) * 96
    hud = Image.new("RGB", (w, h), (24, 27, 24))
    d = ImageDraw.Draw(hud)
    y = 40
    for s in sizes:
        for which, _ in rows:
            label(d, (16, y + 30), f"{which} {s // 2}px", 18)
            for i, name in enumerate(kit):
                x = 140 + i * 96
                p = plate.resize((88, 88), Image.LANCZOS)
                hud.paste(p, (x, y), p)
                if which == "TODAY":
                    icon = glyph(name, s)
                elif which == "3D INK":
                    icon = outlined(icons[name], s, 1.6)
                else:
                    icon = outlined(lifted(icons[name]), s, 2.2, (214, 206, 180), 0.9)
                hud.paste(icon, (x + 44 - s // 2, y + 44 - s // 2), icon)
            y += 96
    label(d, (16, 8), "Kit slots at phone size (2x pixels), on the game's own plate", 18)
    hud.save(final / "sheet_hud_sizes.png")

    # 3. The rest: badge, marker, app icon concept.
    extras = [n for n in ["badge_ghost", "marker_objective", "app_beret"] if n in icons]
    if extras:
        ex = Image.new("RGB", (340 * len(extras) + 340, 380), PLATE)
        d = ImageDraw.Draw(ex)
        for i, name in enumerate(extras):
            if name == "app_beret":
                tile = app_icon(icons[name], 300)
                ex.paste(tile, (i * 340 + 20, 50))
            else:
                icon = outlined(icons[name], 300, 3.0)
                ex.paste(icon, (i * 340 + 20, 50), icon)
            label(d, (i * 340 + 20, 14), name.replace("_", " ").upper(), 16)
        now = Image.open(GODOT / "icon.png").convert("RGB").resize((300, 300), Image.LANCZOS)
        mask = Image.new("L", (300, 300), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 299, 299), 66, fill=255)
        ex.paste(now, (len(extras) * 340 + 20, 50), mask)
        label(d, (len(extras) * 340 + 20, 14), "APP ICON TODAY", 16)
        ex.save(final / "sheet_extras.png")
        if "app_beret" in icons:
            app_icon(icons["app_beret"], 1024).save(final / "app_icon_3d_1024.png")
            small = Image.new("RGB", (420, 140), (30, 30, 30))
            for j, s in enumerate([120, 60, 40]):
                t = app_icon(icons["app_beret"], s)
                small.paste(t, (20 + j * 140, 10))
            small.save(final / "app_icon_3d_small.png")
    print("sheets in", final)


def app_icon(subject: Image.Image, size: int) -> Image.Image:
    """The 3D subject on a dark olive field with a soft light behind it, in the home-screen rounded square."""
    s = 1024
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32) / s
    glow = np.exp(-(((xx - 0.42) ** 2) + ((yy - 0.38) ** 2)) / 0.09)
    base = np.array([0.13, 0.16, 0.12])
    light = np.array([0.36, 0.38, 0.26])
    field = base + (light - base) * glow[..., None]
    vignette = 1.0 - 0.35 * (((xx - 0.5) ** 2 + (yy - 0.5) ** 2) / 0.5)
    field *= vignette[..., None]
    bg = Image.fromarray((np.clip(field, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    subj = subject.resize((int(s * 0.92), int(s * 0.92)), Image.LANCZOS)
    shadow = Image.new("RGBA", subj.size, (0, 0, 0, 0))
    shadow.putalpha(subj.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.55)))
    bg.alpha_composite(shadow, (int(s * 0.05), int(s * 0.07)))
    bg.alpha_composite(subj, (int(s * 0.04), int(s * 0.03)))
    tile = bg.convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), int(size * 0.22), fill=255)
    out = Image.new("RGB", (size, size), (30, 30, 30))
    out.paste(tile, (0, 0), mask)
    return out


def contact(out: Path, names: list) -> Path:
    """One row per icon: large on the plate colour and on paper, then on the HUD plate at 44, 34 and 26 px
    (2x pixels) with the light rim, beside today's glyph when there is one."""
    plate = Image.open(GODOT / "assets/ui/plate.png").convert("RGBA").resize((104, 104), Image.LANCZOS)
    row_h = 230
    sheet = Image.new("RGB", (1180, row_h * len(names) + 10), (24, 27, 24))
    d = ImageDraw.Draw(sheet)
    for r, name in enumerate(names):
        path = out / f"{name}.png"
        if not path.exists():
            label(d, (12, r * row_h + 10), f"{name}: no render", 18)
            continue
        icon = cropped(Image.open(path).convert("RGBA"))
        y = r * row_h + 10
        label(d, (12, y), name.upper(), 18)
        big = outlined(icon, 200, 3.0)
        sheet.paste(Image.new("RGB", (210, 210), PLATE), (12, y + 22))
        sheet.paste(big, (17, y + 24), big)
        sheet.paste(Image.new("RGB", (210, 210), PAPER), (230, y + 22))
        sheet.paste(big, (235, y + 24), big)
        x = 470
        for s in (88, 68, 52):
            sheet.paste(plate, (x, y + 60), plate)
            small = outlined(lifted(icon), s, 2.2, (214, 206, 180), 0.9)
            sheet.paste(small, (x + 52 - s // 2, y + 112 - s // 2), small)
            x += 120
        if name in GLYPHS:
            sheet.paste(plate, (x + 20, y + 60), plate)
            g = glyph(name, 68)
            sheet.paste(g, (x + 72 - 34, y + 112 - 34), g)
            label(d, (x + 20, y + 168), "today", 14)
    target = out / "final" / f"contact_{names[0]}_{len(names)}.png"
    target.parent.mkdir(exist_ok=True)
    sheet.save(target)
    print("contact sheet", target)
    return target


def greyed(img: Image.Image, dark=(34, 37, 32), light=(150, 154, 140)) -> Image.Image:
    """The disabled look: the icon's light and shade mapped onto a flat grey-olive ramp (alpha kept)."""
    a = np.asarray(img, dtype=np.float32) / 255.0
    lum = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    lo = np.array(dark, dtype=np.float32) / 255.0
    hi = np.array(light, dtype=np.float32) / 255.0
    rgb = lo + (hi - lo) * lum[..., None]
    return Image.fromarray((np.dstack([rgb, a[..., 3:]]) * 255 + 0.5).astype(np.uint8), "RGBA")


def _cell(img: Image.Image, cell: int, rim: bool) -> Image.Image:
    """One atlas cell: the render cropped to the object, outlined, inside the gutter."""
    side = cell - 2 * GUTTER
    k = side / RIM_AT
    if rim:
        icon = outlined(lifted(cropped(img, 0.04)), side, 2.2 * k, RIM, 0.9 * k)
    else:
        icon = outlined(cropped(img, 0.02), side, 0.9 * k)
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    out.alpha_composite(icon, (GUTTER, GUTTER))
    return out


def small_medal(img: Image.Image, i: int, cell: int) -> Image.Image:
    """A medal for a leaderboard row or an operation card (about 22 px): the struck relief is lost that small, so
    the brass is brightened and softened and the badge's symbol from badges.png is inked onto it."""
    side = cell - 2 * GUTTER
    med = cropped(img, 0.02).resize((side, side), Image.LANCZOS)
    alpha = med.getchannel("A")
    med = lifted(med.filter(ImageFilter.GaussianBlur(side / 124)), 1.6)
    med.putalpha(alpha)
    stamp = Image.open(GODOT / "assets/ui/badges.png").convert("RGBA").crop((i * 176, 0, (i + 1) * 176, 176))
    a = np.asarray(stamp.resize((side, side), Image.LANCZOS).getchannel("A"), dtype=np.float32) / 255.0
    yy, xx = np.mgrid[0:side, 0:side]
    a *= np.hypot(xx - (side - 1) / 2, yy - (side - 1) / 2) < side * 0.33   # the symbol, not the stamp's rings
    symbol = grown(Image.fromarray((a * 255).astype(np.uint8)), max(1, side // 124))
    ink = Image.new("RGBA", (side, side), (48, 30, 8, 0))
    ink.putalpha(symbol.point(lambda v: int(v * 0.92)))
    med.alpha_composite(ink)
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    out.alpha_composite(outlined(med, side, 0.9 * side / RIM_AT), (GUTTER, GUTTER))
    return out


def _check_order(const: str, names: list) -> None:
    """Warn when action_slot.gd's list of atlas names is not this one."""
    import re
    src = (GODOT / "scripts/three_d/action_slot.gd").read_text()
    m = re.search(r"const %s := \[(.*?)\]" % const, src, re.S)
    found = re.findall(r'"([a-z_]+)"', m.group(1)) if m else []
    if found != names:
        print(f"WARNING: action_slot.gd {const} differs from the atlas; it should read:")
        print(f"const {const} := [" + ",".join(f'"{n}"' for n in names) + "]")


def atlas(out: Path) -> None:
    """godot/assets/ui/icons3d.png: every object in ICONS3D with the light rim, ATLAS_CELL px cells, ATLAS_COLS
    across; the same cells again below in grey for a disabled or recharging action. medals.png: the five debrief
    medals in BADGES order, full colour on the top row, greyed (an earlier run's) on the second and the small
    inked version (leaderboard rows, operation cards) on the third."""
    missing = [n for n in ICONS3D + ["badge_" + b for b in BADGES] if not (out / f"{n}.png").exists()]
    if missing:
        sys.exit("no render for: " + ", ".join(missing))
    rows = (len(ICONS3D) + ATLAS_COLS - 1) // ATLAS_COLS
    sheet = Image.new("RGBA", (ATLAS_COLS * ATLAS_CELL, rows * 2 * ATLAS_CELL), (0, 0, 0, 0))
    for i, name in enumerate(ICONS3D):
        cell = _cell(Image.open(out / f"{name}.png").convert("RGBA"), ATLAS_CELL, True)
        x, y = (i % ATLAS_COLS) * ATLAS_CELL, (i // ATLAS_COLS) * ATLAS_CELL
        sheet.alpha_composite(cell, (x, y))
        sheet.alpha_composite(greyed(cell), (x, y + rows * ATLAS_CELL))
    medals = Image.new("RGBA", (len(BADGES) * MEDAL_CELL, 3 * MEDAL_CELL), (0, 0, 0, 0))
    for i, name in enumerate(BADGES):
        render = Image.open(out / f"badge_{name}.png").convert("RGBA")
        cell = _cell(render, MEDAL_CELL, False)
        medals.alpha_composite(cell, (i * MEDAL_CELL, 0))
        medals.alpha_composite(greyed(cell, (40, 42, 38), (176, 176, 168)), (i * MEDAL_CELL, MEDAL_CELL))
        medals.alpha_composite(small_medal(render, i, MEDAL_CELL), (i * MEDAL_CELL, 2 * MEDAL_CELL))
    for img, name in ((sheet, "icons3d.png"), (medals, "medals.png")):
        target = GODOT / "assets/ui" / name
        img.save(target, optimize=True)
        print(target, img.size, target.stat().st_size, "bytes")
    _check_order("ICONS3D", ICONS3D)
    _check_order("BADGES", BADGES)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("prepare", "sheets", "contact", "atlas"):
        sys.exit(__doc__)
    if sys.argv[1] == "contact":
        contact(Path(sys.argv[2]), sys.argv[3:])
    else:
        {"prepare": prepare, "sheets": sheets, "atlas": atlas}[sys.argv[1]](Path(sys.argv[2]))
