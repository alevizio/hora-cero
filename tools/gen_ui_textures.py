#!/usr/bin/env python3
"""Procedural HUD textures for Hora Cero (field-kit / operations-dossier look).

Everything is authored at 2x density (2 texture px per logical HUD px) and drawn at
half scale by the HUD code, so plates stay crisp on a retina phone.

Run:  python3 tools/gen_ui_textures.py            (writes godot/assets/ui/*.png)
      python3 tools/gen_ui_textures.py --sheet X  (also writes a contact sheet to X)

9-slice conventions (texture px; halve for logical px) -- mirrored in action_slot.gd:
  plate_*      144x144  bleed 8   margin 24   centre tile 96
  tape         144x96   bleed 4   margin 24   centre tile 96x48
  strip        112x112  bleed 8   margin 24   centre tile 64
  glyphs       576x480  6x5 cells of 96 px, white on alpha (tinted in code)
  badges       880x176  five round result stamps of 176 px, white ink on alpha
  edge_glow    128x128  bleed 0   margin 56   centre transparent (alarm frame, tinted in code)
  stamp_*      white ink on alpha, tinted and rotated in code
  paper        256x256  bleed 20  margin 48   centre tile 160
  map_frame    160x160  bleed 8   margin 36   centre transparent
  photo_frame   96x96   bleed 0   margin 28   centre transparent
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "ui")
FONTS = os.path.join(ROOT, "godot", "assets", "fonts")
SEED = 19440606


def rng(tag):
    return np.random.default_rng(SEED + sum(ord(c) * (i + 1) for i, c in enumerate(tag)))


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0


# ---------------------------------------------------------------- helpers
def periodic_noise(shape, period, sigma, r, off=(0, 0)):
    """Smooth noise that repeats every `period` px, sampled over `shape` (so a 9-slice
    centre of size `period` tiles seamlessly and continues into the border cells)."""
    py, px = period if isinstance(period, tuple) else (period, period)
    base = r.standard_normal((py, px))
    base = ndi.gaussian_filter(base, sigma, mode="wrap")
    base /= (base.std() + 1e-9)
    yy = (np.arange(shape[0]) - off[0]) % py
    xx = (np.arange(shape[1]) - off[1]) % px
    return base[np.ix_(yy, xx)]


def sd_round_box(shape, x0, y0, x1, y1, rad):
    """Signed distance (px, negative inside) to a rounded box."""
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float64) + 0.5
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - rad, (y1 - y0) / 2 - rad
    qx, qy = np.abs(xx - cx) - hx, np.abs(yy - cy) - hy
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad


def cover(sd):
    """Anti-aliased coverage from a signed distance."""
    return np.clip(0.5 - sd, 0.0, 1.0)


def band(sd, lo, hi):
    """Coverage of the ring lo <= -sd < hi (distance inside the edge)."""
    return np.clip(-sd - lo + 0.5, 0, 1) * np.clip(hi + sd + 0.5, 0, 1)


def over(dst_rgb, dst_a, src_rgb, src_a):
    """Straight-alpha 'over'. src_rgb may be a colour (3,) or an image."""
    src_rgb = np.broadcast_to(src_rgb, dst_rgb.shape)
    sa = src_a[..., None]
    da = dst_a[..., None]
    out_a = sa + da * (1 - sa)
    out_rgb = (src_rgb * sa + dst_rgb * da * (1 - sa)) / np.maximum(out_a, 1e-6)
    return out_rgb, out_a[..., 0]


def save(name, rgb, a):
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]])
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    return img


def shadow(shape, sd, spread, strength, dy=2.0):
    """Soft contact shadow outside a shape (uses the same sd shifted down)."""
    s = np.roll(sd, int(round(dy)), axis=0)
    return np.clip(1.0 - np.maximum(s, 0) / spread, 0, 1) ** 2 * strength


def lit_edges(sd, light=(-0.45, -0.9)):
    """Fake bevel lighting term in [-1, 1] from the sd gradient (light from top-left)."""
    gy, gx = np.gradient(sd)
    n = np.hypot(gx, gy) + 1e-6
    return -(gx / n * light[0] + gy / n * light[1])


# ---------------------------------------------------------------- steel plates
def steel_plate(name, base, *, size=144, bleed=8, rad=5, pressed=False, keyline=None,
                rim=True, wear=1.0, grain=1.0, bevel=1.0):
    r = rng(name.replace("_pressed", ""))
    shape = (size, size)
    period = size - 48
    sd = sd_round_box(shape, bleed, bleed, size - bleed, size - bleed, rad)
    inside = cover(sd)
    # Painted steel: slow mottling + fine grain + faint vertical drag marks.
    mott = periodic_noise(shape, period, 14, r, (24, 24))
    fine = periodic_noise(shape, period, 0.8, r, (24, 24))
    drag = periodic_noise((1, size), (1, period), 1.2, r, (0, 24))
    drag = np.repeat(drag, size, axis=0)
    val = 1.0 + (0.016 * mott + 0.030 * fine + 0.010 * drag) * grain
    rgb = base[None, None, :] * val[..., None]
    # Slight top-to-bottom falloff reads as a lit sheet (only inside the border cells so the
    # tiled centre stays seamless: it is flat there).
    lit = lit_edges(sd) * (-1.0 if pressed else 1.0)
    edge = band(sd, 1.5, 5.0)
    rgb = rgb * (1.0 + 0.30 * bevel * lit * edge)[..., None]
    if rim:
        # Stamped rim: a pressed groove 4 logical px inside the edge (dark line + catch light).
        groove = band(sd, 9.0, 11.0)
        catch = band(sd, 11.0, 12.5)
        rgb = rgb * (1.0 - 0.22 * groove)[..., None]
        rgb = rgb * (1.0 + 0.10 * catch * np.clip(lit, -1, 1) + 0.05 * catch)[..., None]
    if keyline is not None:
        k = band(sd, 5.0, 8.0)
        glow = np.clip(1.0 + sd / 26.0, 0, 1) ** 2 * inside * 0.16
        rgb = rgb * (1 - glow[..., None]) + keyline[None, None, :] * glow[..., None]
        rgb = rgb * (1 - k[..., None]) + (keyline * (0.92 + 0.08 * fine[..., None])) * k[..., None]
    # Dark outline (1 logical px).
    outline = band(sd, 0.0, 2.0)
    rgb = rgb * (1.0 - 0.72 * outline)[..., None]
    # Corner wear: paint chipped back to bare metal, corners only (edges tile in a 9-slice).
    if wear > 0:
        yy, xx = np.mgrid[0:size, 0:size]
        cdist = np.minimum(np.minimum(np.hypot(xx - bleed, yy - bleed), np.hypot(xx - (size - bleed), yy - bleed)),
                           np.minimum(np.hypot(xx - bleed, yy - (size - bleed)), np.hypot(xx - (size - bleed), yy - (size - bleed))))
        chip_n = ndi.gaussian_filter(r.standard_normal(shape), 1.3)
        chip_n /= chip_n.std()
        near_edge = np.clip(1.0 - (-sd - 1.0) / 6.0, 0, 1) * (sd < -1.0)
        near_corner = np.clip(1.0 - cdist / 22.0, 0, 1)
        chips = np.clip((chip_n + 2.4 * near_edge * near_corner - 2.0) * 2.2, 0, 1) * np.clip(near_edge * near_corner * 4.0, 0, 1) * inside * wear
        metal = hexc("9a9a8a") * (0.9 + 0.1 * fine[..., None])
        rgb = rgb * (1 - chips[..., None]) + metal * chips[..., None]
        # Fine scuffs: a few short light scratches inside the corner cells.
        scuff = np.zeros(shape)
        for _ in range(int(5 * wear)):
            cx = r.choice([r.uniform(bleed + 4, 22), r.uniform(size - 22, size - bleed - 4)])
            cy = r.choice([r.uniform(bleed + 4, 22), r.uniform(size - 22, size - bleed - 4)])
            ang = r.uniform(-0.6, 0.6)
            ln = r.uniform(4, 9)
            for t in np.linspace(-ln / 2, ln / 2, 24):
                px, py = int(cx + np.cos(ang) * t), int(cy + np.sin(ang) * t)
                if 0 <= px < size and 0 <= py < size:
                    scuff[py, px] = 1.0
        scuff = ndi.gaussian_filter(scuff, 0.6) * 1.6 * inside * np.clip(1.0 - cdist / 20.0, 0, 1)
        rgb = rgb * (1.0 + 0.16 * np.clip(scuff, 0, 1))[..., None]
    a = inside.copy()
    sh = shadow(shape, sd, bleed, 0.0 if pressed else 0.42)
    rgb, a = over(np.zeros_like(rgb), sh * (1 - inside), rgb, a)
    return save(name, rgb, a)


# ---------------------------------------------------------------- canvas name tape
def tape(name, base, thread):
    r = rng(name)
    h, w, bleed = 96, 144, 4
    shape = (h, w)
    sd = sd_round_box(shape, bleed, bleed, w - bleed, h - bleed, 3)
    inside = cover(sd)
    yy, xx = np.mgrid[0:h, 0:w]
    # Plain weave, 4 px thread pitch (2 logical px): alternating over/under checker.
    wx = np.sin((xx + 0.5) * np.pi / 2.0)
    wy = np.sin((yy + 0.5) * np.pi / 2.0)
    checker = ((xx // 2 + yy // 2) % 2) * 2.0 - 1.0
    weave = 0.035 * checker + 0.022 * wx * wy
    slub = periodic_noise(shape, (48, 96), (0.6, 5.0), r, (24, 24))  # long horizontal slubs
    mott = periodic_noise(shape, (48, 96), 7, r, (24, 24))
    val = 1.0 + weave + 0.022 * slub + 0.03 * mott
    rgb = base[None, None, :] * val[..., None]
    # Folded, overlocked edge: darker hem + stitch line 3 logical px in.
    hem = band(sd, 0.0, 3.0)
    rgb = rgb * (1 - 0.42 * hem)[..., None]
    lit = lit_edges(sd)
    rgb = rgb * (1.0 + 0.10 * lit * band(sd, 2.0, 5.0))[..., None]
    stitch_line = band(sd, 6.0, 8.0)
    # Dashes follow the perimeter: period 16 px so they tile with the 96 px centre.
    along = np.where(np.minimum(yy - bleed, h - bleed - 1 - yy) < np.minimum(xx - bleed, w - bleed - 1 - xx), xx, yy)
    dash = (((along - 24) % 16) < 9).astype(np.float64)
    st = stitch_line * dash
    st_shadow = np.roll(st, 1, axis=0) * 0.5
    rgb = rgb * (1 - 0.35 * st_shadow)[..., None]
    rgb = rgb * (1 - st[..., None]) + thread[None, None, :] * st[..., None]
    a = inside
    sh = shadow(shape, sd, bleed, 0.35, dy=1)
    rgb, a = over(np.zeros_like(rgb), sh * (1 - inside), rgb, a)
    return save(name, rgb, a)


# ---------------------------------------------------------------- dark canvas strip
def strip(name, base, alpha):
    r = rng(name)
    size, bleed = 112, 8
    shape = (size, size)
    sd = sd_round_box(shape, bleed, bleed, size - bleed, size - bleed, 5)
    inside = cover(sd)
    yy, xx = np.mgrid[0:size, 0:size]
    checker = ((xx // 2 + yy // 2) % 2) * 2.0 - 1.0
    mott = periodic_noise(shape, 64, 6, r, (24, 24))
    val = 1.0 + 0.05 * checker + 0.05 * mott
    rgb = base[None, None, :] * val[..., None]
    lit = lit_edges(sd)
    rgb = rgb + 0.035 * np.clip(lit, 0, 1)[..., None] * band(sd, 1.5, 3.5)[..., None]
    outline = band(sd, 0.0, 2.0)
    rgb = rgb * (1 - 0.6 * outline)[..., None]
    a = inside * (alpha + (1 - alpha) * outline)
    sh = shadow(shape, sd, bleed, 0.30)
    rgb, a = over(np.zeros_like(rgb), sh * (1 - inside), rgb, a)
    return save(name, rgb, a)


# ---------------------------------------------------------------- dossier paper
def paper_fibres(shape, period, r, count):
    """Short curved fibres (periodic) as a signed field."""
    canvas = Image.new("F", (period * 3, period * 3), 0.0)
    d = ImageDraw.Draw(canvas)
    for _ in range(count):
        x, y = r.uniform(0, period), r.uniform(0, period)
        ang = r.uniform(0, np.pi)
        ln = r.uniform(5, 16)
        bend = r.uniform(-0.5, 0.5)
        pts = []
        for t in np.linspace(0, 1, 6):
            a2 = ang + bend * (t - 0.5)
            pts.append((x + np.cos(a2) * ln * (t - 0.5), y + np.sin(a2) * ln * (t - 0.5)))
        v = float(r.choice([-1.0, 1.0]) * r.uniform(0.4, 1.0))
        for ox in (0, period, 2 * period):
            for oy in (0, period, 2 * period):
                d.line([(px + ox, py + oy) for px, py in pts], fill=v, width=1)
    f = np.asarray(canvas)[period:2 * period, period:2 * period]
    f = ndi.gaussian_filter(f, 0.55, mode="wrap")
    yy = (np.arange(shape[0])) % period
    xx = (np.arange(shape[1])) % period
    return f[np.ix_(yy, xx)]


def paper(name, base, edge_tint, *, size=256, bleed=20, period=160, rough=1.0, shadow_strength=0.5):
    r = rng(name)
    shape = (size, size)
    off = ((size - period) // 2,) * 2
    sd = sd_round_box(shape, bleed, bleed, size - bleed, size - bleed, 3)
    # Slightly uneven cut edge (corners only would look odd; keep it tiny so tiling edges hide it).
    cut = periodic_noise(shape, period, 5.0, r, off) * 0.22 * rough
    sd = sd + cut
    inside = cover(sd)
    cloud = periodic_noise(shape, period, 14, r, off)
    fine = periodic_noise(shape, period, 0.7, r, off)
    fib = np.roll(paper_fibres(shape, period, r, 260), off, axis=(0, 1))
    val = 1.0 + 0.012 * cloud + 0.016 * fine + 0.04 * fib
    rgb = base[None, None, :] * val[..., None]
    # Aged edge: toned toward tobacco within ~8 logical px, strongest at the very rim.
    age = np.clip(1.0 + sd / 22.0, 0, 1) ** 2.0 * 0.30 + band(sd, 0.0, 2.0) * 0.22
    age = np.clip(age, 0, 1)
    rgb = rgb * (1 - age[..., None]) + (edge_tint[None, None, :] * val[..., None]) * age[..., None]
    # A hair of catch light along the top-left edge (paper thickness).
    lit = lit_edges(sd)
    rgb = rgb + 0.05 * np.clip(lit, 0, 1)[..., None] * band(sd, 0.5, 2.5)[..., None]
    a = inside
    sh = shadow(shape, sd, bleed, shadow_strength, dy=4)
    rgb, a = over(np.zeros_like(rgb), sh * (1 - inside), rgb, a)
    return save(name, rgb, a)


def paper_stain(name):
    """Low-frequency foxing overlay, stretched over the whole sheet at low alpha."""
    r = rng(name)
    size = 128
    blot = ndi.gaussian_filter(r.standard_normal((size, size)), 16)
    blot /= blot.std()
    blot2 = ndi.gaussian_filter(r.standard_normal((size, size)), 6)
    blot2 /= blot2.std()
    a = np.clip((blot - 0.6) * 0.08, 0, 0.10) + np.clip((blot2 - 1.7) * 0.08, 0, 0.06)
    # Foxing specks.
    dots = np.zeros((size, size))
    for _ in range(9):
        x, y = r.integers(6, size - 6, 2)
        dots[y, x] = r.uniform(0.5, 1.6)
    a = a + np.clip(ndi.gaussian_filter(dots, 0.9) * 1.6, 0, 0.14)
    # A faint ring (mug mark) low on the sheet, mostly broken up.
    yy, xx = np.mgrid[0:size, 0:size]
    ring = np.exp(-((np.hypot((xx - 96) * 1.0, (yy - 100) * 1.6) - 17) ** 2) / 2.2)
    a = a + ring * np.clip(blot2 * 0.5 + 0.5, 0, 1) * 0.06
    # Keep the overlay off the sheet's very edge so the 9-slice rim stays clean.
    fade = np.clip(np.minimum(np.minimum(xx, size - 1 - xx), np.minimum(yy, size - 1 - yy)) / 6.0, 0, 1)
    a = a * fade
    rgb = np.broadcast_to(hexc("6b4a22"), (size, size, 3)).copy()
    return save(name, rgb, a)


# ---------------------------------------------------------------- recon map case
def rivet(rgb, a_mask, cx, cy, rad, base):
    yy, xx = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]].astype(np.float64) + 0.5
    d = np.hypot(xx - cx, yy - cy)
    m = np.clip(rad - d + 0.5, 0, 1)
    # Domed head: light from top-left, small specular.
    nx, ny = (xx - cx) / rad, (yy - cy) / rad
    shade = 1.0 + 0.45 * (-(nx * 0.45 + ny * 0.9)) * np.clip(d / rad, 0, 1)
    spec = np.exp(-((xx - cx + rad * 0.3) ** 2 + (yy - cy + rad * 0.35) ** 2) / (rad * 0.55) ** 2) * 0.35
    col = base[None, None, :] * shade[..., None] + spec[..., None]
    ring = np.clip(rad + 1.5 - d + 0.5, 0, 1) * (1 - m)
    rgb[:] = rgb * (1 - 0.5 * ring * a_mask)[..., None]
    rgb[:] = rgb * (1 - m[..., None]) + col * m[..., None]


def map_frame(name, base):
    r = rng(name)
    size, bleed, thick = 160, 8, 14
    shape = (size, size)
    period = size - 72
    sd_out = sd_round_box(shape, bleed, bleed, size - bleed, size - bleed, 5)
    sd_in = sd_round_box(shape, bleed + thick, bleed + thick, size - bleed - thick, size - bleed - thick, 2)
    frame = cover(sd_out) * (1 - cover(sd_in))
    mott = periodic_noise(shape, period, 8, r, (36, 36))
    fine = periodic_noise(shape, period, 0.8, r, (36, 36))
    rgb = base[None, None, :] * (1.0 + 0.035 * mott + 0.03 * fine)[..., None]
    lit = lit_edges(sd_out)
    rgb = rgb * (1.0 + 0.30 * lit * band(sd_out, 1.5, 5.0))[..., None]
    # Inner lip of the frame catches light on the opposite (bottom/right) faces.
    lit_in = lit_edges(sd_in)
    lip = np.clip(1.0 - np.abs(sd_in - 2.0) / 2.0, 0, 1) * (sd_in > 0)
    rgb = rgb * (1.0 + 0.28 * lit_in * lip)[..., None]
    rgb = rgb * (1.0 - 0.72 * band(sd_out, 0.0, 2.0))[..., None]
    rgb = rgb * (1.0 - 0.55 * np.clip(1.0 - np.abs(sd_in - 0.5) / 1.2, 0, 1) * (sd_in > -0.5))[..., None]
    for cx, cy in ((bleed + 7.5, bleed + 7.5), (size - bleed - 7.5, bleed + 7.5), (bleed + 7.5, size - bleed - 7.5), (size - bleed - 7.5, size - bleed - 7.5)):
        rivet(rgb, frame, cx, cy, 3.4, base * 1.25)
    # Inner shadow thrown onto the map sheet (top/left heavier).
    inner = cover(sd_in)
    sh_in = np.clip(1.0 + sd_in / 9.0, 0, 1) ** 2 * inner
    sh_in = sh_in * (0.34 + 0.22 * np.clip(-lit_in, 0, 1))
    a = frame + sh_in * (1 - frame)
    rgb = rgb * frame[..., None]
    outside = shadow(shape, sd_out, bleed, 0.42) * (1 - cover(sd_out))
    a = a + outside
    return save(name, rgb, a)


def map_paper(name, base):
    r = rng(name)
    size = 128
    shape = (size, size)
    cloud = periodic_noise(shape, size, 12, r)
    fine = periodic_noise(shape, size, 0.7, r)
    fib = paper_fibres(shape, size, r, 150)
    rgb = base[None, None, :] * (1.0 + 0.014 * cloud + 0.018 * fine + 0.035 * fib)[..., None]
    return save(name, rgb, np.ones(shape))


def photo_frame(name):
    """Overlay drawn on top of an ID photo: bezel line, inner shadow and four corner mounts."""
    size = 96
    shape = (size, size)
    sd = sd_round_box(shape, 0, 0, size, size, 2)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) + 0.5
    lit = lit_edges(sd)
    rgb = np.zeros((size, size, 3))
    # Inner shadow: photo sits recessed behind the holder window.
    a = np.clip(1.0 + sd / 12.0, 0, 1) ** 2 * (0.42 + 0.22 * np.clip(lit, 0, 1))
    line = band(sd, 0.0, 2.0)
    a = np.maximum(a, line * 0.9)
    # Corner mounts (slotted photo corners), 9 logical px legs.
    steel = hexc("4a5142")
    leg = 20.0
    for sx, sy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        u = xx if sx == 0 else size - xx
        v = yy if sy == 0 else size - yy
        tri = np.clip(leg - (u + v) + 0.5, 0, 1)
        edge_hi = np.clip(1.0 - np.abs(leg - (u + v) - 1.2) / 1.2, 0, 1) * tri
        shade = 1.0 + (0.12 if (sx + sy) == 0 else (-0.10 if (sx + sy) == 2 else 0.0))
        col = steel * shade
        rgb = rgb * (1 - tri[..., None]) + (col[None, None, :] * (1 + 0.35 * edge_hi[..., None])) * tri[..., None]
        drop = np.clip(leg + 5 - (u + v), 0, 5) / 5.0 * (1 - tri) * 0.5
        a = np.maximum(a, drop)
        a = np.maximum(a, tri)
    a = a * cover(sd)
    return save(name, rgb, a)


# ---------------------------------------------------------------- rubber stamps
def stamp(name, text):
    r = rng(name)
    ss = 3
    font = ImageFont.truetype(os.path.join(FONTS, "BigShouldersStencilDisplay-wght.ttf"), 66 * ss)
    font.set_variation_by_axes([800])
    track = 5 * ss
    widths = [font.getlength(ch) for ch in text]
    tw = int(sum(widths) + track * (len(text) - 1))
    box = font.getbbox(text)
    th = box[3] - box[1]
    pad_x, pad_y, border, gap, bleed = 22 * ss, 14 * ss, 5 * ss, 4 * ss, 6 * ss
    w = tw + 2 * (pad_x + border + bleed)
    h = th + 2 * (pad_y + border + bleed)
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([bleed, bleed, w - bleed - 1, h - bleed - 1], radius=9 * ss, outline=255, width=border)
    d.rounded_rectangle([bleed + border + gap, bleed + border + gap, w - bleed - border - gap - 1, h - bleed - border - gap - 1], radius=6 * ss, outline=255, width=max(1, ss + 1))
    x = bleed + border + pad_x
    y = bleed + border + pad_y - box[1]
    for ch, cw in zip(text, widths):
        d.text((x, y), ch, font=font, fill=255)
        x += cw + track
    w2, h2 = (w // ss) // 2 * 2, (h // ss) // 2 * 2
    a = np.asarray(im.resize((w2, h2), Image.LANCZOS), dtype=np.float64) / 255.0
    # Ink behaviour: soft squeeze-out, blotchy coverage, dry patches and speckle.
    a = np.clip(ndi.gaussian_filter(a, 0.7) * 1.25, 0, 1)
    blot = ndi.gaussian_filter(r.standard_normal(a.shape), 9)
    blot /= blot.std()
    mid = ndi.gaussian_filter(r.standard_normal(a.shape), 2.2)
    mid /= mid.std()
    speck = r.random(a.shape)
    ink = 0.80 + 0.14 * np.clip(blot, -1.5, 1.5) / 1.5
    dry = np.clip((mid + 0.55 * blot + 1.75) * 1.4, 0, 1)
    a = a * ink * dry * (0.82 + 0.18 * (speck > 0.16))
    rgb = np.ones(a.shape + (3,))
    return save(name, rgb, a)


# ---------------------------------------------------------------- glyph atlas
CELL = 96          # texture px per glyph cell (48 logical)
SS = 4             # supersampling
GLYPH_COLS = 6
GLYPHS = ["crouch", "walk", "throw", "key", "cell", "rescue",
          "boat", "pause", "play", "rot_l", "rot_r", "brief",
          "knife", "bind", "pistol", "revolver", "tripwire", "cutters",
          "radio", "carry", "drop", "hide", "flag", "tap",
          "drag", "pinch", "target", "eye", "clock", "cross",
          "limpet", "charge", "switch", "cigarette", "gate", "cosh",
          "bottle", "uniform", "rope", "talk", "skis", "phone",
          "smg", "snowsuit", "window", "duct"]
BADGES = ["ghost", "clean_hands", "not_a_shot", "saboteur", "swift"]
BADGE_CELL = 176   # texture px per result stamp (88 logical)


def turned(pts, deg, at=(24.0, 24.0), origin=(0.0, 0.0)):
    """Rotates points drawn around `origin` by `deg` and moves that origin to `at`."""
    c, s_ = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return [(at[0] + (x - origin[0]) * c - (y - origin[1]) * s_, at[1] + (x - origin[0]) * s_ + (y - origin[1]) * c) for x, y in pts]


class Pen:
    """Round-capped vector pen in 48x48 logical glyph units."""

    def __init__(self):
        self.k = CELL * SS / 48.0
        self.im = Image.new("L", (CELL * SS, CELL * SS), 0)
        self.d = ImageDraw.Draw(self.im)

    def dot(self, x, y, rad, fill=255):
        k = self.k
        self.d.ellipse([(x - rad) * k, (y - rad) * k, (x + rad) * k, (y + rad) * k], fill=fill)

    def line(self, pts, w=3.4, fill=255):
        k = self.k
        self.d.line([(x * k, y * k) for x, y in pts], fill=fill, width=int(round(w * k)), joint="curve")
        for x, y in pts:
            self.dot(x, y, w / 2 - 0.02, fill)

    def poly(self, pts, fill=255):
        k = self.k
        self.d.polygon([(x * k, y * k) for x, y in pts], fill=fill)

    def round_poly(self, pts, rad, fill=255):
        self.poly(pts, fill)
        self.line(list(pts) + [pts[0]], rad * 2, fill)

    def rect(self, x0, y0, x1, y1, rad=0.0, fill=255):
        k = self.k
        self.d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], radius=rad * k, fill=fill)

    def arc(self, cx, cy, rad, a0, a1, w=3.4, fill=255, steps=48):
        pts = [(cx + np.cos(np.radians(a)) * rad, cy + np.sin(np.radians(a)) * rad) for a in np.linspace(a0, a1, steps)]
        self.line(pts, w, fill)

    def out(self):
        return np.asarray(self.im.resize((CELL, CELL), Image.LANCZOS), dtype=np.float64) / 255.0


def glyph(kind):
    p = Pen()
    if kind == "crouch":
        # Low, forward-leaning figure moving right; rear knee down.
        p.dot(31.0, 13.5, 4.6)
        p.line([(27.5, 19.5), (17.5, 27.5)], 5.2)                 # torso
        p.line([(26.5, 20.5), (33.5, 25.5), (38.5, 23.0)], 3.2)   # leading arm
        p.line([(17.5, 27.5), (27.0, 31.5), (25.0, 40.0), (30.5, 40.0)], 3.6)  # front leg
        p.line([(17.5, 27.5), (13.5, 37.5), (7.0, 40.0)], 3.6)    # rear leg, knee toward ground
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)             # ground line
    elif kind == "walk":
        p.dot(25.5, 8.5, 4.6)
        p.line([(24.5, 15.5), (22.5, 28.0)], 5.2)                 # torso
        p.line([(24.5, 16.5), (31.5, 22.0), (33.5, 28.0)], 3.2)   # front arm
        p.line([(24.0, 16.5), (17.0, 22.5), (14.5, 27.5)], 3.2)   # rear arm
        p.line([(22.5, 28.0), (29.5, 34.5), (30.0, 41.5), (34.5, 41.5)], 3.6)
        p.line([(22.5, 28.0), (18.0, 35.5), (11.5, 41.0)], 3.6)
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)
    elif kind == "throw":
        # Thrown stone: dashed arc from the hand, stone at the far end, two noise ticks.
        cx, cy, rad = 21.0, 37.0, 21.0
        for a0 in (200, 222, 244, 266, 288):
            p.arc(cx, cy, rad, a0, a0 + 12, 2.8, steps=8)
        p.dot(37.5, 29.5, 5.2)
        p.arc(37.5, 29.5, 9.5, 20, 80, 2.0, 190, 10)
        p.arc(37.5, 29.5, 9.5, 100, 160, 2.0, 190, 10)
        p.dot(6.0, 33.5, 2.6)
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)
    elif kind == "key":
        p.arc(13.0, 24.0, 7.0, 0, 360, 3.6)
        p.line([(20.5, 24.0), (41.0, 24.0)], 3.6)
        p.line([(33.0, 24.0), (33.0, 31.0)], 3.4)
        p.line([(40.0, 24.0), (40.0, 33.0)], 3.4)
    elif kind == "cell":
        # Barred gate in a frame.
        p.line([(9.0, 43.0), (9.0, 8.0), (39.0, 8.0), (39.0, 43.0)], 3.4)
        for x in (16.5, 24.0, 31.5):
            p.line([(x, 14.0), (x, 43.0)], 2.6)
        p.line([(9.0, 26.0), (39.0, 26.0)], 2.6)
        p.rect(19.5, 22.0, 28.5, 30.0, 1.2)
    elif kind == "rescue":
        # Gate swung open with a figure stepping out.
        p.line([(7.0, 43.0), (7.0, 8.0), (25.0, 8.0)], 3.4)
        p.line([(7.0, 8.0), (16.0, 13.0), (16.0, 39.0), (7.0, 43.0)], 2.6)
        p.dot(30.0, 16.0, 4.2)
        p.line([(29.5, 22.5), (28.5, 31.5)], 4.8)
        p.line([(28.5, 31.5), (33.5, 36.5), (34.0, 42.5)], 3.2)
        p.line([(28.5, 31.5), (25.5, 37.0), (22.0, 42.5)], 3.2)
        p.line([(29.5, 23.0), (35.5, 27.0), (40.0, 25.0)], 2.8)
    elif kind == "boat":
        # Small launch: hull, post and a wake line.
        p.round_poly([(6.0, 26.0), (42.0, 26.0), (36.0, 34.5), (11.5, 34.5)], 1.2)
        p.line([(22.0, 25.0), (22.0, 10.0)], 2.8)
        p.round_poly([(25.5, 11.0), (35.5, 21.5), (25.5, 21.5)], 0.8)
        for x0 in (5.0, 19.0, 33.0):
            p.arc(x0 + 5.0, 37.0, 6.0, 35, 145, 2.2, 200, 10)
    elif kind == "pause":
        p.rect(13.5, 10.0, 21.0, 38.0, 1.4)
        p.rect(27.0, 10.0, 34.5, 38.0, 1.4)
    elif kind == "play":
        p.round_poly([(16.0, 11.0), (36.5, 24.0), (16.0, 37.0)], 1.6)
    elif kind in ("rot_l", "rot_r"):
        # Three-quarter turn arrow; mirrored for the other direction.
        # rot_l turns anticlockwise: the head sits upper-left and points down along the circle.
        cx, cy, rad, end = 24.5, 25.0, 13.0, -150.0
        p.arc(cx, cy, rad, 105, end + 14, 3.6)
        th = np.radians(end)
        px, py = cx + np.cos(th) * rad, cy + np.sin(th) * rad
        tx, ty = np.sin(th), -np.cos(th)          # tangent for decreasing angle
        nx, ny = np.cos(th), np.sin(th)           # radial
        p.round_poly([(px + tx * 7.5, py + ty * 7.5), (px - tx * 3.5 + nx * 7.0, py - ty * 3.5 + ny * 7.0), (px - tx * 3.5 - nx * 7.0, py - ty * 3.5 - ny * 7.0)], 0.9)
        if kind == "rot_r":
            p.im = p.im.transpose(Image.FLIP_LEFT_RIGHT)
    elif kind == "brief":
        p.line([(12.0, 7.0), (30.0, 7.0), (37.0, 14.0), (37.0, 41.0), (12.0, 41.0), (12.0, 7.0)], 3.0)
        for y in (19.0, 26.0, 33.0):
            p.line([(18.0, y), (31.0, y)], 2.2)
    elif kind == "knife":
        # Fighting knife, point up and to the right.
        def k(pts):
            return turned(pts, -45.0, (24.5, 23.5), (18.5, 0.0))
        p.poly(k([(14.0, -3.7), (31.0, -3.2), (40.5, 0.0), (31.0, 3.2), (14.0, 3.7)]))      # blade
        p.line(k([(15.0, 0.0), (33.0, 0.0)]), 0.9, 0)                                       # fuller
        p.line(k([(12.4, -7.2), (12.4, 7.2)]), 3.0)                                         # guard
        p.line(k([(0.5, 0.0), (11.0, 0.0)]), 5.4)                                           # grip
        for gx in (3.2, 6.0, 8.8):
            p.line(k([(gx, -2.9), (gx, 2.9)]), 0.9, 0)
        p.dot(*k([(-1.6, 0.0)])[0], 3.5)                                                    # pommel
    elif kind == "bind":
        # A coil of rope, lashed at the top, one end hanging free.
        p.arc(22.0, 27.0, 12.0, 0, 360, 6.6, steps=72)
        for a0 in range(0, 360, 20):
            th = np.radians(a0)
            cx, cy = 22.0 + np.cos(th) * 12.0, 27.0 + np.sin(th) * 12.0
            tx, ty = np.cos(th + 0.55), np.sin(th + 0.55)
            p.line([(cx - tx * 3.6, cy - ty * 3.6), (cx + tx * 3.6, cy + ty * 3.6)], 1.0, 0)
        p.rect(17.0, 10.4, 27.0, 19.6, 1.4)
        for y in (13.4, 16.6):
            p.line([(17.4, y), (26.6, y)], 1.1, 0)
        p.line([(26.5, 12.0), (35.5, 8.5), (41.0, 12.5), (41.5, 21.0)], 3.0)
    elif kind == "pistol":
        # Self-loading pistol with a long suppressor, muzzle to the right.
        p.rect(5.0, 15.0, 27.0, 22.6, 1.0)                                                  # slide
        p.rect(5.0, 12.8, 7.6, 15.6, 0.5)                                                   # rear sight
        p.line([(8.0, 18.9), (24.5, 18.9)], 0.9, 0)                                         # slide line
        p.rect(26.0, 17.0, 29.5, 20.6)                                                      # muzzle
        p.rect(29.0, 14.6, 45.5, 23.0, 2.4)                                                 # suppressor
        p.line([(33.0, 15.2), (33.0, 22.4)], 0.9, 0)
        p.round_poly([(7.4, 22.0), (16.2, 22.0), (13.4, 36.6), (5.6, 36.6)], 1.1)           # grip
        p.arc(20.4, 24.2, 4.0, 5, 175, 1.7, steps=16)                                       # trigger guard
        p.line([(19.6, 23.0), (19.2, 26.0)], 1.5)
    elif kind == "revolver":
        # Service revolver: fluted cylinder, short barrel, round butt.
        p.rect(25.0, 14.6, 44.0, 19.6, 0.9)                                                 # barrel
        p.rect(41.0, 12.2, 43.6, 15.2, 0.5)                                                 # front sight
        p.rect(26.0, 19.0, 34.0, 21.6, 0.8)                                                 # ejector rod housing
        p.rect(11.0, 13.6, 27.0, 23.6, 1.6)                                                 # frame
        p.rect(14.2, 11.6, 25.6, 25.6, 2.6)                                                 # cylinder
        for y in (15.6, 18.6, 21.6):
            p.line([(16.4, y), (23.4, y)], 1.0, 0)
        p.round_poly([(8.6, 12.0), (12.6, 13.4), (11.6, 16.0)], 0.6)                        # hammer
        p.round_poly([(11.6, 22.6), (18.6, 23.4), (17.0, 31.0), (13.4, 38.0), (6.2, 37.4), (6.6, 31.6)], 1.3)  # butt
        p.arc(22.4, 25.4, 4.0, 5, 175, 1.7, steps=16)
        p.line([(21.6, 24.4), (21.2, 27.4)], 1.5)
    elif kind == "tripwire":
        # Two pegs, a taut wire and a boot about to find it.
        p.line([(7.5, 41.5), (9.5, 29.0)], 3.6)
        p.line([(40.5, 41.5), (38.5, 29.0)], 3.6)
        p.line([(9.0, 33.0), (39.0, 33.0)], 2.2)
        boot = [(-6.5, -19.0), (0.5, -19.0), (1.0, -8.0), (8.5, -5.5), (10.0, -3.0), (10.0, 0.0), (-6.5, 0.0)]
        p.round_poly(turned(boot, 14.0, (22.5, 27.0)), 1.3)
        p.line(turned([(-6.0, -13.0), (0.4, -13.0)], 14.0, (22.5, 27.0)), 1.1, 0)
        p.line(turned([(-7.0, -2.6), (10.5, -2.6)], 14.0, (22.5, 27.0)), 1.0, 0)
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)
    elif kind == "cutters":
        # Wire cutters biting through a strand.
        p.line([(11.0, 43.0), (20.0, 27.0), (26.4, 18.5)], 4.0)
        p.line([(37.0, 43.0), (28.0, 27.0), (21.6, 18.5)], 4.0)
        p.round_poly([(21.0, 20.0), (27.0, 20.0), (25.6, 9.5), (24.0, 8.2), (22.4, 9.5)], 1.0)   # jaws
        p.line([(24.0, 9.0), (24.0, 17.0)], 0.9, 0)
        p.dot(24.0, 22.4, 2.5)
        p.dot(24.0, 22.4, 0.9, 0)
        p.line([(4.0, 12.0), (18.0, 12.0)], 1.9)
        p.line([(30.0, 12.0), (44.0, 12.0)], 1.9)
        p.line([(18.0, 12.0), (19.4, 8.0)], 1.5)
        p.line([(30.0, 12.0), (28.6, 16.0)], 1.5)
    elif kind == "radio":
        # Field wireless set: dial, speaker slots, whip aerial and two waves.
        p.rect(7.0, 19.0, 39.0, 41.0, 2.4)
        p.dot(16.5, 30.0, 5.2, 0)
        p.dot(16.5, 30.0, 2.0)
        for y in (25.0, 30.0, 35.0):
            p.line([(26.0, y), (34.5, y)], 1.7, 0)
        p.line([(32.5, 19.0), (36.5, 5.5)], 2.2)
        p.dot(36.5, 5.5, 1.7)
        p.arc(36.5, 5.5, 6.5, 150, 215, 1.9, 220, 10)
        p.arc(36.5, 5.5, 11.5, 152, 213, 1.9, 220, 12)
        p.line([(11.0, 19.0), (11.0, 15.5), (19.0, 15.5), (19.0, 19.0)], 2.0)
    elif kind == "carry":
        # Lifting a body: the mirror of "drop".
        p.line([(24.0, 11.0), (24.0, 24.0)], 3.2)
        p.round_poly([(17.0, 13.5), (31.0, 13.5), (24.0, 5.0)], 0.9)
        p.dot(9.5, 35.5, 3.8)
        p.line([(15.5, 36.5), (29.0, 36.5)], 5.4)
        p.line([(29.0, 36.5), (36.0, 33.0), (41.5, 38.0)], 3.6)
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)
    elif kind == "drop":
        # Setting a body down.
        p.line([(24.0, 5.0), (24.0, 17.0)], 3.2)
        p.round_poly([(17.0, 15.5), (31.0, 15.5), (24.0, 24.0)], 0.9)
        p.dot(9.5, 35.5, 3.8)
        p.line([(15.5, 36.5), (29.0, 36.5)], 5.4)
        p.line([(29.0, 36.5), (36.0, 33.0), (41.5, 38.0)], 3.6)
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.4, 150)
    elif kind == "hide":
        # A bush with a pair of boots sticking out of it.
        p.dot(11.0, 28.0, 8.4)
        p.dot(20.5, 21.0, 10.0)
        p.dot(28.5, 29.0, 8.0)
        p.dot(14.5, 16.5, 5.4)
        p.dot(27.5, 17.5, 5.0)
        p.rect(3.5, 29.0, 34.0, 41.5, 3.4)
        p.arc(11.0, 28.5, 4.8, 195, 290, 1.2, 0, 10)
        p.arc(21.0, 22.0, 6.0, 210, 320, 1.2, 0, 10)
        p.arc(28.5, 29.5, 4.4, 235, 340, 1.2, 0, 10)
        p.line([(33.0, 38.6), (44.0, 38.6)], 4.4)
        p.line([(44.2, 38.6), (44.2, 31.5)], 3.8)
        p.line([(33.8, 34.0), (33.8, 43.0)], 1.2, 0)
        p.line([(3.0, 44.0), (46.0, 44.0)], 1.4, 150)
    elif kind == "flag":
        # Marker pennant: a checkpoint.
        p.line([(14.0, 7.0), (14.0, 42.0)], 3.0)
        p.round_poly([(16.5, 8.5), (38.0, 15.5), (16.5, 23.0)], 0.9)
        p.line([(8.0, 42.0), (21.0, 42.0)], 2.6)
    elif kind == "tap":
        p.dot(24.0, 24.0, 5.4)
        p.arc(24.0, 24.0, 11.5, 0, 360, 2.2, steps=64)
        for a0 in (20, 110, 200, 290):
            p.arc(24.0, 24.0, 18.0, a0, a0 + 50, 1.8, 170, 12)
    elif kind == "drag":
        p.dot(11.5, 33.0, 4.8)
        p.arc(11.5, 33.0, 8.6, 0, 360, 1.6, 170, 48)
        p.line([(18.5, 27.5), (34.5, 15.0)], 3.0)
        p.round_poly(turned([(0.0, -5.6), (8.0, 0.0), (0.0, 5.6)], -38.0, (34.0, 15.4)), 0.8)
    elif kind == "pinch":
        p.dot(18.0, 30.0, 4.4)
        p.dot(30.0, 18.0, 4.4)
        p.line([(13.5, 34.5), (9.5, 38.5)], 2.8)
        p.round_poly(turned([(0.0, -5.0), (7.0, 0.0), (0.0, 5.0)], 135.0, (9.0, 39.0)), 0.8)
        p.line([(34.5, 13.5), (38.5, 9.5)], 2.8)
        p.round_poly(turned([(0.0, -5.0), (7.0, 0.0), (0.0, 5.0)], -45.0, (39.0, 9.0)), 0.8)
    elif kind == "target":
        p.arc(24.0, 24.0, 12.0, 0, 360, 2.6, steps=64)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p.line([(24.0 + dx * 7.0, 24.0 + dy * 7.0), (24.0 + dx * 18.0, 24.0 + dy * 18.0)], 2.6)
        p.dot(24.0, 24.0, 2.0)
    elif kind == "eye":
        top = [(6.0 + 36.0 * t, 24.0 - 11.0 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 24)]
        low = [(42.0 - 36.0 * t, 24.0 + 11.0 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 24)]
        p.line(top + low + [top[0]], 2.8)
        p.dot(24.0, 24.0, 5.6)
        p.dot(22.2, 22.2, 1.6, 0)
    elif kind == "clock":
        p.arc(24.0, 26.0, 13.5, 0, 360, 3.0, steps=64)
        p.rect(21.0, 5.0, 27.0, 9.6, 1.0)
        p.line([(24.0, 9.0), (24.0, 12.5)], 2.6)
        p.line([(24.0, 26.0), (24.0, 17.5)], 2.6)
        p.line([(24.0, 26.0), (30.0, 29.5)], 2.6)
    elif kind == "cross":
        p.line([(13.0, 13.0), (35.0, 35.0)], 4.2)
        p.line([(35.0, 13.0), (13.0, 35.0)], 4.2)
    elif kind == "limpet":
        # A limpet mine against a hull plate, below the waterline, its placing rod reaching down to it.
        p.line([(4.0, 17.0), (44.0, 17.0)], 1.6, 170)                               # waterline
        for x0 in (6.0, 20.0, 34.0):
            p.arc(x0 + 4.0, 13.5, 4.0, 30, 150, 1.4, 150, 8)
        p.line([(42.0, 6.0), (42.0, 44.0)], 2.2, 200)                              # hull side
        p.line([(10.0, 3.0), (29.0, 27.0)], 2.8)                                   # placing rod
        p.rect(24.0, 24.0, 40.0, 40.0, 7.5)                                        # the mine
        p.dot(32.0, 32.0, 3.2, 0)
        p.dot(32.0, 32.0, 1.4)
    elif kind == "charge":
        # A demolition charge strapped up, a time pencil in the primer, the fuse burning.
        p.rect(7.0, 22.0, 37.0, 41.0, 2.2)
        for x in (15.0, 29.0):
            p.line([(x, 22.0), (x, 41.0)], 1.6, 0)
        p.line([(31.0, 22.5), (38.0, 9.0)], 3.0)                                   # time pencil
        p.line([(38.0, 9.0), (41.5, 4.0)], 1.6)
        for a in (0, 60, 120, 180, 240, 300):
            th = np.radians(a)
            p.line([(42.5 + np.cos(th) * 2.2, 3.5 + np.sin(th) * 2.2), (42.5 + np.cos(th) * 4.6, 3.5 + np.sin(th) * 4.6)], 1.2)
    elif kind == "switch":
        # Main switch: a knife lever thrown down out of its jaws, a lightning bolt struck through.
        p.rect(8.0, 6.0, 30.0, 42.0, 2.0)
        p.rect(11.0, 9.0, 27.0, 39.0, 1.0, 0)
        p.line([(14.0, 30.0), (24.0, 30.0)], 2.4)
        p.dot(19.0, 30.0, 2.6)
        p.line([(19.0, 30.0), (19.0, 42.0), (21.0, 46.0)], 3.0)                    # lever thrown down
        p.round_poly([(36.0, 4.0), (30.5, 19.0), (36.0, 19.0), (32.0, 34.0), (44.0, 15.0), (38.0, 15.0), (42.0, 4.0)], 0.6)
    elif kind == "cigarette":
        # A cigarette, its tip lit, a curl of smoke going up.
        p.line([(4.0, 34.0), (34.0, 34.0)], 6.6)                                   # paper
        p.line([(12.0, 30.5), (12.0, 37.5)], 1.4, 0)                               # where the filter starts
        p.dot(38.5, 34.0, 3.8)                                                     # the glowing end
        curl = [(39.0 + 4.0 * np.sin(t * 6.0), 27.0 - 22.0 * t) for t in np.linspace(0, 1, 24)]
        p.line(curl, 2.0)
    elif kind == "gate":
        # Going home: an open dock gate, a figure walking out through it.
        p.line([(5.0, 44.0), (5.0, 8.0), (20.0, 8.0), (20.0, 44.0)], 2.6)
        p.line([(20.0, 8.0), (30.0, 13.0), (30.0, 44.0)], 2.0)                     # the gate swung open
        for y in (18.0, 28.0, 38.0):
            p.line([(20.0, y), (30.0, y + 3.0)], 1.4)
        p.dot(38.5, 13.0, 3.2)                                                     # walking out
        p.line([(38.0, 17.5), (36.5, 28.0)], 3.0)
        p.line([(36.5, 28.0), (32.5, 38.0)], 2.8)
        p.line([(36.5, 28.0), (41.0, 37.0), (43.0, 42.0)], 2.8)
        p.line([(37.5, 20.0), (42.5, 26.0)], 2.4)
    elif kind == "cosh":
        # A leather cosh swung down: a thick weighted head on a short grip with its wrist loop, motion lines.
        p.line(turned([(0.0, 0.0), (17.0, 0.0)], -40.0, (9.0, 40.0)), 4.6)             # grip
        p.line(turned([(17.0, 0.0), (29.0, 0.0)], -40.0, (9.0, 40.0)), 8.6)            # weighted head
        p.arc(8.0, 44.0, 3.8, 0, 360, 1.8, steps=24)                                   # wrist loop
        for i, r in enumerate((24.0, 30.0)):
            p.arc(9.0, 40.0, r, -78 + i * 4, -52 + i * 4, 1.6, 200 - i * 60, 12)          # the swing
    elif kind == "bottle":
        # An empty wine bottle thrown, turning in the air, and where it lands: shards and a burst.
        p.line(turned([(-9.0, 0.0), (5.0, 0.0)], -35.0, (17.0, 22.0)), 9.0)             # body
        p.line(turned([(5.0, 0.0), (14.0, 0.0)], -35.0, (17.0, 22.0)), 3.8)             # neck
        p.arc(17.0, 22.0, 17.0, 120, 170, 1.6, 170, 10)                                 # its arc
        for a in (200, 240, 280, 320):
            th = np.radians(a)
            p.line([(37.0 + np.cos(th) * 4.0, 41.0 + np.sin(th) * 4.0), (37.0 + np.cos(th) * 8.5, 41.0 + np.sin(th) * 8.5)], 1.8)
        p.round_poly([(31.0, 44.0), (34.0, 40.0), (36.0, 44.0)], 0.4)
        p.round_poly([(39.0, 44.0), (42.0, 39.0), (44.0, 44.0)], 0.4)
    elif kind == "uniform":
        # A guard's tunic on its hanger: open collar, two rows of buttons, the belt.
        p.arc(24.0, 6.2, 2.8, 180, 430, 1.8, 255, 16)                                  # hook
        p.line([(24.0, 9.0), (24.0, 11.5)], 1.8)
        p.round_poly([(15.0, 12.5), (33.0, 12.5), (42.0, 18.5), (40.5, 33.0), (35.5, 31.0), (35.5, 44.0),
                      (12.5, 44.0), (12.5, 31.0), (7.5, 33.0), (6.0, 18.5)], 1.0)
        p.line([(18.5, 12.5), (24.0, 21.0), (29.5, 12.5)], 2.2, 0)                    # collar
        p.line([(24.0, 21.0), (24.0, 44.5)], 1.3, 0)                                   # front
        p.line([(12.0, 35.0), (36.0, 35.0)], 2.0, 0)                                   # belt
        for y in (25.0, 30.5, 40.0):
            p.dot(20.6, y, 1.3, 0)
            p.dot(27.4, y, 1.3, 0)
    elif kind == "rope":
        # A coil of climbing rope hanging from a piton, its free end running down.
        p.line([(24.0, 4.0), (24.0, 11.0)], 2.6)                                       # piton
        p.dot(24.0, 4.0, 2.4)
        for r in (12.0, 9.5, 7.0):
            p.arc(24.0, 22.0, r, 0, 360, 2.0, steps=40)
        p.line([(31.0, 30.0), (34.0, 38.0), (31.0, 45.0)], 2.2)                         # the free end
    elif kind == "talk":
        # A quiet word: a speech balloon with a finger to the lips beside it.
        p.round_poly([(5.0, 8.0), (32.0, 8.0), (32.0, 27.0), (17.0, 27.0), (10.0, 35.0), (11.0, 27.0), (5.0, 27.0)], 2.0)
        for x in (12.0, 18.5, 25.0):
            p.dot(x, 17.5, 2.1, 0)
        p.line([(38.5, 22.0), (38.5, 44.0)], 3.6)                                      # a raised finger
        p.dot(38.5, 21.0, 2.0)
        p.line([(35.0, 33.0), (42.0, 33.0)], 2.0)                                      # across the lips
    elif kind == "skis":
        # A pair of skis crossed with a pole: the tips turned up.
        for sgn in (-1.0, 1.0):
            pts = turned([(-19.0, 0.0), (15.0, 0.0), (19.0, -2.0), (21.0, -5.0)], sgn * 32.0, (24.0, 25.0))
            p.line(pts, 3.4)
        p.line([(24.0, 4.0), (24.0, 45.0)], 1.8)
        p.arc(24.0, 40.5, 3.6, 0, 360, 1.4, steps=20)
    elif kind == "phone":
        # A field telephone's line cut: the receiver, its cord severed, the two ends apart.
        p.line([(8.0, 14.0), (22.0, 8.0)], 4.6)                                        # receiver
        p.dot(8.0, 15.0, 4.2)
        p.dot(22.5, 8.0, 4.2)
        p.line([(15.0, 13.0), (16.0, 22.0), (12.0, 30.0), (19.0, 34.0)], 1.8)           # cord
        p.line([(26.0, 38.0), (33.0, 34.0), (40.0, 40.0), (44.0, 36.0)], 1.8)
        p.line([(21.0, 31.0), (27.0, 41.0)], 1.6)                                      # the cut
        p.line([(25.0, 30.0), (22.0, 42.0)], 1.6)
    elif kind == "smg":
        # A submachine gun with its drum, laid on the floor.
        p.line([(6.0, 26.0), (36.0, 26.0)], 4.6)                                       # receiver
        p.line([(36.0, 25.0), (45.0, 25.0)], 2.2)                                      # barrel
        p.line([(6.0, 27.0), (2.5, 31.0)], 4.2)                                        # stock
        p.dot(20.0, 33.0, 6.0)                                                         # the drum
        p.dot(20.0, 33.0, 2.2, 0)
        p.line([(29.0, 28.0), (31.0, 36.0)], 3.0)                                      # grip
        p.line([(4.0, 44.0), (44.0, 44.0)], 1.6)                                       # the floor
    elif kind == "window":
        # A window pane breaking: the frame, a star of cracks from where it was struck.
        p.rect(8.0, 6.0, 40.0, 42.0, 2.6)
        p.rect(11.0, 9.0, 37.0, 39.0, 1.0, 0)                                           # the frame
        p.line([(24.0, 8.0), (24.0, 40.0)], 1.8)                                       # the glazing bar
        p.line([(10.0, 24.0), (38.0, 24.0)], 1.8)
        for a in (20.0, 75.0, 140.0, 200.0, 255.0, 320.0):
            dx, dy = np.cos(np.radians(a)), np.sin(np.radians(a))
            p.line([(17.0, 22.0), (17.0 + dx * 7.0, 22.0 + dy * 7.0), (17.0 + dx * 9.0 + dy * 2.0, 22.0 + dy * 9.0 - dx * 2.0)], 1.5)
        p.dot(17.0, 22.0, 2.4, 0)
        p.line([(30.0, 30.0), (36.0, 38.0)], 1.4)                                      # a shard falling
    elif kind == "duct":
        # A cable duct's grille, unscrewed: the louvred cover swung aside, the dark mouth behind it.
        p.round_poly([(6.0, 14.0), (28.0, 14.0), (28.0, 36.0), (6.0, 36.0)], 2.0)      # the dark mouth
        p.rect(9.0, 17.0, 25.0, 33.0, 1.6, 0)
        pts = [(30.0, 10.0), (44.0, 16.0), (44.0, 40.0), (30.0, 34.0)]                 # the grille, swung open
        p.line(pts + [pts[0]], 2.2)
        for t in (0.25, 0.5, 0.75):
            p.line([(30.0, 10.0 + 24.0 * t), (44.0, 16.0 + 24.0 * t)], 1.6)
        for x, y in ((31.5, 12.5), (31.5, 31.5)):
            p.dot(x, y, 1.1)
    elif kind == "snowsuit":
        # A man in a hooded snowsuit, crouched and still: a white shape in the snow.
        p.dot(19.0, 14.0, 5.6)                                                         # hooded head
        p.dot(21.5, 14.8, 2.2, 0)                                                      # the face in the hood
        p.round_poly([(13.0, 20.0), (26.0, 19.0), (35.0, 29.0), (32.0, 37.0), (11.0, 37.0), (9.5, 28.0)], 2.0)  # crouched
        p.line([(4.0, 40.0), (44.0, 40.0)], 2.0)                                        # the snow
        for x in (8.0, 18.0, 30.0, 40.0):
            p.dot(x, 45.0, 1.2)
    return p.out()


def glyph_atlas(name):
    cols = GLYPH_COLS
    rows = (len(GLYPHS) + cols - 1) // cols
    a = np.zeros((rows * CELL, cols * CELL))
    for i, g in enumerate(GLYPHS):
        y, x = (i // cols) * CELL, (i % cols) * CELL
        a[y:y + CELL, x:x + CELL] = glyph(g)
    rgb = np.ones(a.shape + (3,))
    return save(name, rgb, a)


# ---------------------------------------------------------------- result stamps
def badge_icon(kind):
    """Pictogram for a result stamp in 48x48 units (drawn inside a ring of radius ~21)."""
    p = Pen()
    if kind == "ghost":
        # Never seen: an eye struck out.
        top = [(7.0 + 34.0 * t, 24.0 - 11.5 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 24)]
        low = [(41.0 - 34.0 * t, 24.0 + 11.5 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 24)]
        p.line(top + low + [top[0]], 2.6)
        p.dot(24.0, 24.0, 5.4)
        p.line([(11.0, 38.0), (37.0, 10.0)], 6.4, 0)
        p.line([(11.0, 38.0), (37.0, 10.0)], 2.8)
    elif kind == "clean_hands":
        # An open palm.
        p.rect(16.5, 22.0, 31.0, 36.0, 3.6)
        for x, top in ((18.3, 14.5), (22.4, 11.5), (26.5, 12.5), (30.3, 15.5)):
            p.line([(x, 24.0), (x, top)], 3.1)
        p.line([(17.0, 30.0), (12.0, 25.0), (11.0, 21.5)], 3.2)
        p.line([(20.0, 28.5), (27.5, 28.5)], 1.0, 0)
    elif kind == "not_a_shot":
        # A round left in its box: cartridge, struck through.
        p.round_poly([(21.0, 20.0), (27.0, 20.0), (27.0, 15.5), (24.0, 10.5), (21.0, 15.5)], 0.8)
        p.rect(20.2, 21.4, 27.8, 35.0, 0.8)
        p.rect(19.4, 35.6, 28.6, 37.6, 0.6)
        p.line([(13.0, 34.0), (35.0, 14.0)], 5.0, 0)
        p.line([(13.0, 34.0), (35.0, 14.0)], 2.4)
    elif kind == "saboteur":
        # A dead wireless: aerial and a bolt through it.
        p.line([(15.0, 37.0), (33.0, 37.0)], 2.6)
        p.line([(18.0, 37.0), (24.0, 13.0), (30.0, 37.0)], 2.2)
        p.line([(20.6, 27.0), (27.4, 27.0)], 1.8)
        p.round_poly([(27.0, 9.5), (19.5, 23.5), (24.4, 23.5), (21.0, 34.0), (30.0, 19.0), (25.0, 19.0), (29.0, 9.5)], 0.5, 0)
        p.round_poly([(27.5, 10.5), (21.2, 22.6), (25.4, 22.6), (23.0, 30.5), (28.6, 20.0), (24.2, 20.0), (27.8, 10.5)], 0.3)
    elif kind == "swift":
        # Stop-watch with speed lines.
        p.arc(26.0, 26.0, 10.0, 0, 360, 2.4, steps=48)
        p.rect(23.8, 11.0, 28.2, 14.6, 0.8)
        p.line([(26.0, 26.0), (26.0, 19.5)], 2.0)
        p.line([(26.0, 26.0), (30.5, 28.5)], 2.0)
        for y, x0 in ((21.0, 10.0), (26.0, 8.0), (31.0, 11.0)):
            p.line([(x0, y), (13.5, y)], 1.8)
    return p.out()


def badges(name):
    """Five round rubber stamps side by side: double ring, pictogram, uneven ink."""
    r = rng(name)
    cell = BADGE_CELL
    a = np.zeros((cell, cell * len(BADGES)))
    ss = 3
    for i, kind in enumerate(BADGES):
        im = Image.new("L", (cell * ss, cell * ss), 0)
        d = ImageDraw.Draw(im)
        c = cell * ss / 2.0
        for rad, w in ((80.0, 6.0), (70.0, 2.0)):
            d.ellipse([c - rad * ss, c - rad * ss, c + rad * ss, c + rad * ss], outline=255, width=int(w * ss))
        # Tick marks between the rings, like a date stamp.
        for k in range(24):
            ang = k * np.pi / 12.0
            d.line([(c + np.cos(ang) * 72.5 * ss, c + np.sin(ang) * 72.5 * ss), (c + np.cos(ang) * 76.0 * ss, c + np.sin(ang) * 76.0 * ss)], fill=255, width=int(1.6 * ss))
        ring = np.asarray(im.resize((cell, cell), Image.LANCZOS), dtype=np.float64) / 255.0
        icon = Image.fromarray((badge_icon(kind) * 255).astype(np.uint8), "L").resize((156, 156), Image.LANCZOS)
        ring[10:166, 10:166] = np.maximum(ring[10:166, 10:166], np.asarray(icon, dtype=np.float64) / 255.0)
        a[:, i * cell:(i + 1) * cell] = ring
    a = np.clip(ndi.gaussian_filter(a, 0.6) * 1.2, 0, 1)
    blot = ndi.gaussian_filter(r.standard_normal(a.shape), 9)
    blot /= blot.std()
    mid = ndi.gaussian_filter(r.standard_normal(a.shape), 2.2)
    mid /= mid.std()
    speck = r.random(a.shape)
    ink = 0.82 + 0.14 * np.clip(blot, -1.5, 1.5) / 1.5
    dry = np.clip((mid + 0.55 * blot + 1.9) * 1.4, 0, 1)
    a = a * ink * dry * (0.84 + 0.16 * (speck > 0.14))
    return save(name, np.ones(a.shape + (3,)), a)


def edge_glow(name):
    """Soft inner glow hugging the screen edge (9-slice, centre empty), tinted red for the alarm."""
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) + 0.5
    d = np.minimum(np.minimum(xx, size - xx), np.minimum(yy, size - yy))
    a = np.clip(1.0 - d / 52.0, 0, 1) ** 2.4 * 0.85
    return save(name, np.ones((size, size, 3)), a)


# ---------------------------------------------------------------- build
def build():
    os.makedirs(OUT, exist_ok=True)
    made = {}
    olive = hexc("3d4433")
    gun = hexc("292d29")
    brass = hexc("d8a544")
    made["plate"] = steel_plate("plate", olive)
    made["plate_pressed"] = steel_plate("plate_pressed", olive * 0.74, pressed=True)
    made["plate_armed"] = steel_plate("plate_armed", hexc("3f4230"), keyline=brass, rim=False)
    made["plate_gun"] = steel_plate("plate_gun", gun, rim=False, wear=0.7, bevel=0.8)
    made["plate_gun_pressed"] = steel_plate("plate_gun_pressed", gun * 0.72, rim=False, wear=0.7, bevel=0.8, pressed=True)
    made["tape"] = tape("tape", hexc("b3a67d"), hexc("ddd4b0"))
    made["strip"] = strip("strip", hexc("171b16"), 0.86)
    made["paper"] = paper("paper", hexc("d9cfb1"), hexc("9a7f52"), rough=0.0)
    made["paper_stain"] = paper_stain("paper_stain")
    made["map_frame"] = map_frame("map_frame", hexc("3a4034"))
    made["map_paper"] = map_paper("map_paper", hexc("ada383"))
    made["photo_frame"] = photo_frame("photo_frame")
    made["stamp_secret"] = stamp("stamp_secret", "MOST SECRET")
    made["stamp_complete"] = stamp("stamp_complete", "EXTRACTED")
    made["stamp_aborted"] = stamp("stamp_aborted", "ABORTED")
    # the same stamps in Spanish (lang.gd picks them when the game is in Spanish)
    made["stamp_secret_es"] = stamp("stamp_secret_es", "ALTO SECRETO")
    made["stamp_complete_es"] = stamp("stamp_complete_es", "EXTRAÍDOS")
    made["stamp_aborted_es"] = stamp("stamp_aborted_es", "ABORTADA")
    made["glyphs"] = glyph_atlas("glyphs")
    made["badges"] = badges("badges")
    made["edge_glow"] = edge_glow("edge_glow")
    return made


def nine(img, w, h, margin):
    """Reference 9-slice (tiled centre) used only for the contact sheet."""
    out = Image.new("RGBA", (w, h))
    iw, ih = img.size
    xs = [(0, margin, 0, margin), (margin, iw - margin, margin, w - margin), (iw - margin, iw, w - margin, w)]
    ys = [(0, margin, 0, margin), (margin, ih - margin, margin, h - margin), (ih - margin, ih, h - margin, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            tile = img.crop((sx0, sy0, sx1, sy1))
            tw, th = tile.size
            for x in range(dx0, dx1, tw):
                for y in range(dy0, dy1, th):
                    out.paste(tile.crop((0, 0, min(tw, dx1 - x), min(th, dy1 - y))), (x, y))
    return out


def sheet(made, path):
    bg = Image.new("RGBA", (1500, 1100), (86, 92, 70, 255))
    # A noisy two-tone backdrop so wear and shadows can be judged over a busy scene.
    d = ImageDraw.Draw(bg)
    d.rectangle([750, 0, 1500, 1100], fill=(150, 142, 112, 255))
    x = 20
    for key, w, h, m in (("plate", 284, 176, 24), ("plate_pressed", 284, 176, 24), ("plate_armed", 284, 176, 24), ("plate_gun", 152, 160, 24), ("plate_gun_pressed", 152, 160, 24)):
        bg.alpha_composite(nine(made[key], w + 16, h + 16, 24), (x, 20))
        x += w + 30
    bg.alpha_composite(nine(made["tape"], 208, 56, 24), (20, 230))
    bg.alpha_composite(nine(made["strip"], 600, 150, 24), (260, 230))
    bg.alpha_composite(nine(made["map_frame"], 572, 372, 36), (900, 230))
    bg.alpha_composite(nine(made["photo_frame"], 200, 216, 28), (20, 320))
    bg.alpha_composite(nine(made["paper"], 860, 620, 48), (20, 440))
    st = made["paper_stain"].resize((820, 580), Image.BICUBIC)
    bg.alpha_composite(st, (40, 460))
    for i, key in enumerate(("stamp_secret", "stamp_complete", "stamp_aborted")):
        s = np.asarray(made[key], dtype=np.float64) / 255.0
        col = [(0.25, 0.26, 0.2), (0.25, 0.33, 0.22), (0.66, 0.2, 0.14)][i]
        s[..., :3] = col
        s[..., 3] *= 0.8
        bg.alpha_composite(Image.fromarray((s * 255).astype(np.uint8), "RGBA").rotate(-6 + 3 * i, expand=True, resample=Image.BICUBIC), (80 + 250 * i, 520 + 150 * i))
    g = made["glyphs"]
    bg.alpha_composite(g, (900, 600))
    b = np.asarray(made["badges"], dtype=np.float64) / 255.0
    b[..., :3] = (0.2, 0.26, 0.17)
    bg.alpha_composite(Image.fromarray((b * 255).astype(np.uint8), "RGBA").resize((440, 88), Image.LANCZOS), (40, 980))
    bg.save(path)
    # Glyphs once more at the size the action bar draws them (44 px), on plate olive and on paper.
    small = Image.new("RGBA", (GLYPH_COLS * 60, ((len(GLYPHS) + GLYPH_COLS - 1) // GLYPH_COLS) * 60 * 2), (61, 68, 51, 255))
    ImageDraw.Draw(small).rectangle([0, small.size[1] // 2, small.size[0], small.size[1]], fill=(217, 207, 177, 255))
    for i in range(len(GLYPHS)):
        cell = g.crop(((i % GLYPH_COLS) * CELL, (i // GLYPH_COLS) * CELL, (i % GLYPH_COLS + 1) * CELL, (i // GLYPH_COLS + 1) * CELL)).resize((44, 44), Image.LANCZOS)
        small.alpha_composite(cell, ((i % GLYPH_COLS) * 60 + 8, (i // GLYPH_COLS) * 60 + 8))
        dark = np.asarray(cell, dtype=np.float64) / 255.0
        dark[..., :3] = (0.14, 0.145, 0.12)
        small.alpha_composite(Image.fromarray((dark * 255).astype(np.uint8), "RGBA"), ((i % GLYPH_COLS) * 60 + 8, small.size[1] // 2 + (i // GLYPH_COLS) * 60 + 8))
    small.save(path.replace(".png", "_glyphs_small.png"))
    print("sheet", path)


if __name__ == "__main__":
    made = build()
    total = 0
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            s = os.path.getsize(os.path.join(OUT, f))
            total += s
            print("%-24s %4dx%-4d %6.1f KB" % (f, *Image.open(os.path.join(OUT, f)).size, s / 1024))
    print("total %.1f KB" % (total / 1024))
    if "--sheet" in sys.argv:
        sheet(made, sys.argv[sys.argv.index("--sheet") + 1])
