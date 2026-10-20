#!/usr/bin/env python3
"""Procedural textures for La Boca (Operation Riachuelo): painted corrugated iron, lime render, the facade atlas
(windows lit and dark, shutters, doors, a lit shop door, hand-painted fileteado signs with invented names, railings,
awnings, posters, the tram's destination board, portholes) and the slush ruts laid along the busy streets.
Usage:  python3 tools/gen_boca_textures.py        (then `godot --import`, then this again with --fix-imports, and
        `godot --import` once more: the import settings follow the project's, mip-maps on and lossless)
Output: godot/assets/tex/boca/*.png. Tiling surfaces: 512 px = 2.56 m (200 px/m), like the structures kit; the
painted surfaces are near white so the builder's vertex colours give the paint its colour.
The atlas rectangles are mirrored in scripts/three_d/boca_houses.gd (ATLAS)."""
import os
import sys
sys.dont_write_bytecode = True
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from structures_texlib import *

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'boca'))
N = 512
SERIF = '/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf'
SANS = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'

ATLAS = {
    'win_lit0': (0, 0, 128, 256), 'win_lit1': (128, 0, 128, 256), 'win_lit2': (256, 0, 128, 256),
    'win_lit3': (384, 0, 128, 256), 'win_lit4': (512, 0, 128, 256),
    'win_dark0': (640, 0, 128, 256), 'win_dark1': (768, 0, 128, 256), 'win_dark2': (896, 0, 128, 256),
    'shutter_louvre': (0, 256, 128, 256), 'shutter_panel': (128, 256, 128, 256), 'door_double': (256, 256, 128, 256),
    'door_zaguan': (384, 256, 128, 256), 'door_shop_lit': (512, 256, 128, 256), 'door_roller': (640, 256, 128, 256),
    'win_small_lit': (768, 256, 128, 128), 'win_small_dark': (768, 384, 128, 128),
    'win_conv_lit': (896, 256, 128, 128), 'win_conv_dark': (896, 384, 128, 128),
    'sign_cafe': (0, 512, 512, 128), 'sign_almacen': (512, 512, 512, 128), 'sign_bar': (0, 640, 512, 128),
    'sign_despacho': (512, 640, 512, 128),
    'rail_iron': (0, 768, 256, 128), 'rail_wood': (256, 768, 256, 128), 'awning_green': (512, 768, 256, 128),
    'awning_red': (768, 768, 256, 128),
    'filete_band': (0, 896, 256, 128), 'poster_baile': (256, 896, 128, 128), 'poster_alquila': (384, 896, 128, 128),
    'tram_dest': (512, 896, 256, 64), 'tram_win_lit': (512, 960, 128, 64), 'shop_lit': (640, 960, 128, 64),
    'porthole_lit': (768, 896, 64, 64), 'porthole_dark': (832, 896, 64, 64), 'balustrade': (896, 896, 128, 64),
    'arch_lit': (768, 960, 64, 64), 'arch_dark': (832, 960, 64, 64), 'plate_guardia': (896, 960, 128, 64),
}


def save(name, rgb, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.png')
    if alpha is None:
        save_rgb(path, rgb)
    else:
        save_rgba(path, rgb, alpha)
    print('wrote', name)


# --------------------------------------------------------------------------------------------------------------------
# Tiling surfaces
# --------------------------------------------------------------------------------------------------------------------
def tex_chapa():
    """Painted corrugated iron with the ribs running across (U = along the wall): near-white paint, chipped to the dark
    primer and rust here and there, rust bleeding from the nail rows, laps between sheets. Alpha = roughness."""
    shape = (N, N)
    x, y = grid(shape)
    period = 200 * 0.076                         # one corrugation every 76 mm
    sheet_w = N / 3.0                            # three sheets across a tile (0.85 m each)
    sheet_h = N / 2.0
    srow = np.floor(y / sheet_h).astype(np.int32)
    phase = (cell_rand(0, srow, 7, period_y=2) - 0.5) * 40.0
    xs = x + phase
    scol = np.floor(xs / sheet_w).astype(np.int32)
    fx = xs - scol * sheet_w
    fy = y - srow * sheet_h
    corr = 0.5 + 0.5 * np.cos(2 * np.pi * y / period)
    paint = 0.86 + 0.06 * (fbm(shape, 2.2, 1) - 0.5) + 0.04 * (cell_rand(np.mod(scol, 3), srow, 2, 3, 2) - 0.5)
    rgb = np.stack([paint, paint, paint * 0.98], -1)
    # chips of paint gone: dark primer and rust beneath, on the crests more than in the troughs
    chip_v = fbm(shape, 1.6, 3, lo=4) * 0.75 + fbm(shape, 0.9, 4, lo=20) * 0.25 + corr * 0.08
    chip = smooth(chip_v, 0.76, 0.8)
    rust_col = mix(col('7a4a2e'), col('4e3024'), fbm(shape, 1.0, 5, lo=6)[..., None])
    rgb = mix(rgb, rust_col, chip[..., None] * 0.85)
    # nail rows along the laps, with rust bleeding downwards
    nail = np.zeros(shape, np.float32)
    for ny in (sheet_h * 0.08, sheet_h * 0.92):
        crest = np.abs(((y / period) % 2.0) - 1.0)
        dn = np.sqrt((np.mod(fx, 50) - 25) ** 2 + (fy - ny) ** 2)
        nail = np.maximum(nail, np.clip(1.0 - dn / 2.5, 0, 1))
    drip = np.clip(ndimage.gaussian_filter(np.roll(nail, 16, 0), (18, 1.5), mode='wrap') * 16, 0, 1)
    rgb = mix(rgb, col('8a5a3a'), (drip * 0.45 + blur(nail, 2.0) * 2.0).clip(0, 0.7)[..., None])
    # streaks of grime running down the ribs
    streak = fbm(shape, 1.2, 6, ax=0.1, ay=8.0, lo=10)
    rgb = rgb * (0.92 + 0.08 * streak)[..., None]
    lap = smooth(fx, 3.0, 0.0) + smooth(fx, sheet_w - 2.0, sheet_w) * 0.5
    rgb = rgb * (1 - 0.35 * lap)[..., None] * (1 - 0.3 * smooth(fy, 3.0, 0.0))[..., None]
    rgb = rgb * (0.8 + 0.2 * corr)[..., None]
    height = corr * 0.9 - chip * 0.05 + (fy / sheet_h) * 0.15
    rough = 0.55 + 0.3 * chip + 0.1 * (1 - corr)
    rgb = painterly(rgb, 0.3, 8)
    save('chapa_a', rgb, rough_alpha(rough))
    save('chapa_n', normal_from_height(height, 6.0))


def tex_stucco():
    """Lime render over brick, limewashed near white: soft trowel marks, damp patches, hairline cracks, the odd patch
    of fallen render. V anchored at the ground (image bottom); tiles along U."""
    shape = (N, N)
    x, y = grid(shape)
    big = fbm(shape, 2.3, 21)
    trowel = fbm(shape, 1.1, 22, ax=3.0, ay=1.0, lo=8)
    v = 0.84 + 0.07 * (big - 0.5) + 0.05 * (trowel - 0.5)
    rgb = np.stack([v, v * 0.985, v * 0.96], -1)
    damp = smooth(fbm(shape, 1.8, 23), 0.62, 0.85)
    rgb = rgb * (1 - 0.12 * damp)[..., None]
    crack = np.zeros(shape, np.float32)
    cn = fbm(shape, 1.6, 24, lo=3)
    crack = np.clip(1.0 - np.abs(cn - 0.5) / 0.006, 0, 1) * smooth(fbm(shape, 1.5, 25), 0.55, 0.75)
    rgb = mix(rgb, col('6b655a'), (crack * 0.6)[..., None])
    # fallen patches (brick showing), mostly low on the wall
    pn = fbm(shape, 2.2, 26, lo=2) + smooth(y, N * 0.55, N) * 0.12
    patch = smooth(pn, 0.80, 0.82)
    brick = mix(col('8a5442'), col('a46a52'), fbm(shape, 0.8, 27, lo=30)[..., None])
    courses = (np.mod(y, 13) < 1.5) | (np.mod(x + (np.floor(y / 13) % 2) * 14, 28) < 1.5)
    brick = np.where(courses[..., None], col('cfc4b0'), brick)
    rgb = mix(rgb, brick, patch[..., None])
    rim = smooth(pn, 0.78, 0.80) * (1 - patch)
    rgb = rgb * (1 - 0.25 * rim)[..., None]
    height = 0.7 + 0.1 * trowel - patch * 0.4 - crack * 0.2
    rgb = painterly(rgb, 0.35, 28)
    save('stucco_a', rgb)
    save('stucco_n', normal_from_height(height, 3.0, True, False))


def tex_ruts():
    """A strip for the busy streets: two tyre tracks of wet grey slush pressed into the snow, setts showing dark in the
    bottom of each rut, splashed edges. U across the street lane (0..1), V along it (tiles). Alpha = coverage."""
    h, w = 512, 128
    shape = (h, w)
    x, y = grid(shape)
    u = x / w
    a = np.zeros(shape, np.float32)
    wet = np.zeros(shape, np.float32)
    wob = (fbm((h, 1), 1.8, 31, lo=2)[:, 0] - 0.5) * 0.05
    for c in (0.27, 0.73):
        d = np.abs(u - c - wob[:, None])
        a = np.maximum(a, smooth(d, 0.12, 0.05))
        wet = np.maximum(wet, smooth(d, 0.07, 0.02))
    tread = fbm(shape, 0.8, 32, ax=1.0, ay=0.2, lo=10)
    slush = fbm(shape, 1.6, 33, lo=3)
    rgb = mix(col('7a7e8a'), col('4b4e58'), wet[..., None] * (0.7 + 0.3 * tread)[..., None])
    rgb = mix(rgb, col('a7abb8'), (smooth(slush, 0.6, 0.85) * (1 - wet) * 0.6)[..., None])
    alpha = a * (0.75 + 0.25 * smooth(slush, 0.2, 0.6))
    # the middle hump between the tracks: a little dirty slush
    hump = smooth(np.abs(u - 0.5), 0.12, 0.0) * 0.35 * smooth(slush, 0.35, 0.7)
    alpha = np.maximum(alpha, hump)
    alpha = alpha * smooth(u, 0.0, 0.08) * smooth(u, 1.0, 0.92)
    save('ruts_a', rgb, alpha)


# --------------------------------------------------------------------------------------------------------------------
# Facade atlas
# --------------------------------------------------------------------------------------------------------------------
def rgbf(img):
    return np.asarray(img.convert('RGB'), np.float32) / 255.0


def interior(w, h, seed, warm=1.0, curtain=None, blind=0.0, figure=False, dim=1.0):
    """A lit room seen through glass: a warm falloff from a lamp, a dark band of furniture at the bottom."""
    xx, yy = grid((h, w))
    rng = np.random.default_rng(seed)
    lx, ly = w * rng.uniform(0.35, 0.65), h * rng.uniform(0.15, 0.35)
    d = np.sqrt(((xx - lx) / w) ** 2 + ((yy - ly) / h) ** 2 * 0.6)
    glow = np.clip(1.15 - d * 1.8, 0.15, 1.0)
    base = mix(col('7a3a18'), col('ffcf8a'), glow[..., None]) * dim
    base = mix(base, col('ffe7b8'), (smooth(d, 0.18, 0.0) * 0.8)[..., None])
    furn = smooth(yy, h * 0.78, h * 0.84) * (0.7 + 0.3 * fbm((h, w), 1.0, seed, lo=4))
    base = mix(base, col('3a1c10'), furn[..., None] * 0.8)
    if figure:
        fx = w * 0.42
        head = np.sqrt((xx - fx) ** 2 + (yy - h * 0.42) ** 2) < w * 0.11
        body = (np.abs(xx - fx) < w * 0.17 + (yy - h * 0.5) * 0.12) & (yy > h * 0.5)
        base = np.where((head | body)[..., None], col('2a1610'), base)
    if curtain is not None:
        c = col(curtain)
        folds = 0.75 + 0.25 * np.cos(xx / w * 2 * np.pi * 7.0)
        side = np.minimum(xx, w - xx) / w
        cm = smooth(side, 0.28, 0.2) * (1 - 0.3 * smooth(yy, h * 0.7, h))
        base = mix(base, c * folds[..., None] * (0.55 + 0.6 * glow[..., None]), cm[..., None] * 0.92)
    if blind > 0.0:
        bm = (yy < h * blind)
        slat = 0.7 + 0.3 * (np.mod(yy, 6.0) < 4.0)
        base = np.where(bm[..., None], col('b88a5a') * slat[..., None] * (0.6 + 0.5 * glow[..., None]), base)
    return np.clip(base * warm, 0, 1)


def glazing(img, x0, y0, w, h, frame, leaves=2, panes=3, fan=True, bar=3):
    """Window frame and glazing bars drawn over a cell (PIL draw, in place)."""
    d = ImageDraw.Draw(img)
    fr = tuple(int(c * 255) for c in frame)
    d.rectangle([x0, y0, x0 + w - 1, y0 + h - 1], outline=fr, width=6)
    top = y0
    if fan:
        fan_h = int(h * 0.2)
        d.rectangle([x0, y0 + fan_h - 2, x0 + w - 1, y0 + fan_h + 2], fill=fr)
        for i in range(1, 4):
            d.line([x0 + w * i // 4, y0, x0 + w * i // 4, y0 + fan_h], fill=fr, width=bar)
        top = y0 + fan_h
    for i in range(1, leaves):
        d.rectangle([x0 + w * i // leaves - 3, top, x0 + w * i // leaves + 3, y0 + h], fill=fr)
    for j in range(1, panes):
        yy = top + (y0 + h - top) * j // panes
        d.line([x0, yy, x0 + w, yy], fill=fr, width=bar)
    for i in range(leaves):
        lx = x0 + w * i // leaves + w // leaves // 2
        d.line([lx, top, lx, y0 + h], fill=fr, width=max(2, bar - 1))


def cell_window(w, h, seed, lit, variant):
    rng = np.random.default_rng(seed)
    frame = col(['2a1c14', '3c2a1e', '1e2a24', '2c2620'][variant % 4])
    if lit:
        kinds = [dict(curtain='f2e6cc'), dict(curtain='b0402c', dim=0.95), dict(blind=0.45), dict(figure=True, curtain='e8d8b8'),
                 dict(curtain='d8c8a0', dim=0.7)]
        rgb = interior(w, h, seed, **kinds[variant % len(kinds)])
    else:
        xx, yy = grid((h, w))
        sky = mix(col('8e97b4'), col('2a3042'), smooth(yy / h, 0.0, 0.9)[..., None])
        streak = smooth(np.abs((xx / w + yy / h * 0.35) % 0.6 - 0.3), 0.06, 0.0) * 0.25
        rgb = np.clip(sky + streak[..., None], 0, 1)
        if variant == 1:
            rgb = mix(rgb, col('4a1c18') * 0.8, np.full((h, w, 1), 0.85))
        if variant == 2:
            rgb = mix(rgb, col('1a1c22'), np.full((h, w, 1), 0.6))
    img = Image.fromarray(to8(rgb))
    glazing(img, 0, 0, w, h, frame, 2, 3, True)
    out = rgbf(img)
    # sill shadow at the foot, reveal shading at the top
    yy = grid((h, w))[1]
    out = out * (1 - 0.35 * smooth(yy, 14, 0))[..., None]
    return out


def cell_shutter(w, h, seed, louvre=True):
    xx, yy = grid((h, w))
    base = np.full((h, w, 3), 0.8, np.float32) * (0.95 + 0.08 * fbm((h, w), 1.5, seed))[..., None]
    if louvre:
        sl = np.mod(yy, 9.0)
        shade = np.where(sl < 2.0, 0.55, 0.85 + 0.15 * (sl / 9.0))
        inner = (np.abs(xx - w * 0.5) > 4) & (np.minimum(xx, w - xx) > 8) & (yy > 10) & (yy < h - 10)
        rail = (np.abs(yy - h * 0.5) < 5)
        base = np.where((inner & ~rail)[..., None], base * shade[..., None], base)
        base = np.where((np.abs(xx - w * 0.5) < 3)[..., None], base * 0.45, base)
    else:
        for (a, b) in ((10, h * 0.45), (h * 0.55, h - 10)):
            for (l, r) in ((10, w * 0.5 - 6), (w * 0.5 + 6, w - 10)):
                m = (xx > l) & (xx < r) & (yy > a) & (yy < b)
                edge = (np.abs(xx - l) < 3) | (np.abs(yy - a) < 3)
                base = np.where(m[..., None], base * 0.9, base)
                base = np.where((m & edge)[..., None], base * 0.7, base)
        base = np.where((np.abs(xx - w * 0.5) < 3)[..., None], base * 0.45, base)
    chip = smooth(fbm((h, w), 1.4, seed + 1, lo=6), 0.78, 0.82)
    base = mix(base, col('5a4a3a'), chip[..., None] * 0.7)
    return base * (1 - 0.3 * smooth(yy, h - 8, h))[..., None]


def cell_door(w, h, seed, kind):
    xx, yy = grid((h, w))
    if kind == 'double':
        base = np.full((h, w, 3), 0.72, np.float32) * (0.92 + 0.12 * fbm((h, w), 1.0, seed, ax=0.2, ay=4.0, lo=6))[..., None]
        fan_h = h * 0.22
        glass = (yy < fan_h) & (np.minimum(xx, w - xx) > 8) & (yy > 8)
        base = np.where(glass[..., None], col('2a3040'), base)
        for (a, b) in ((fan_h + 12, h * 0.6), (h * 0.65, h - 12)):
            for (l, r) in ((12, w * 0.5 - 8), (w * 0.5 + 8, w - 12)):
                m = (xx > l) & (xx < r) & (yy > a) & (yy < b)
                edge = (np.abs(xx - l) < 3) | (np.abs(yy - a) < 3)
                base = np.where(m[..., None], base * 0.86, base)
                base = np.where((m & edge)[..., None], base * 0.62, base)
        base = np.where((np.abs(xx - w * 0.5) < 2.5)[..., None], base * 0.4, base)
        knob = np.sqrt((xx - w * 0.43) ** 2 + (yy - h * 0.62) ** 2) < 3.5
        base = np.where(knob[..., None], col('c9a050'), base)
        return base
    if kind == 'zaguan':
        inner = interior(w, h, seed, dim=0.35)
        grille = (np.mod(xx, 14) < 3) | (np.mod(yy, 40) < 3) | (np.sqrt(((np.mod(xx, 28) - 14)) ** 2 + (np.mod(yy, 40) - 20) ** 2) - 9 < 1.5) & (np.sqrt(((np.mod(xx, 28) - 14)) ** 2 + (np.mod(yy, 40) - 20) ** 2) - 9 > -1.5)
        base = np.where(grille[..., None], col('141618'), inner)
        frame = (np.minimum(xx, w - xx) < 7) | (yy < 7)
        return np.where(frame[..., None], col('1a1a1c'), base)
    if kind == 'shop':
        inner = interior(w, h, seed + 4, dim=1.0)
        shelves = (np.mod(yy, 30) < 4) & (yy < h * 0.7) & (yy > h * 0.25)
        bottles = (np.mod(yy, 30) > 4) & (np.mod(yy, 30) < 16) & (np.mod(xx, 9) < 4) & (yy < h * 0.7) & (yy > h * 0.25)
        inner = np.where(shelves[..., None], col('5a2a14'), inner)
        inner = np.where(bottles[..., None], mix(col('6a8a3a'), col('9a3a20'), fbm((h, w), 0.5, seed, lo=30)[..., None]), inner)
        img = Image.fromarray(to8(inner))
        glazing(img, 0, 0, w, h, col('2c1e14'), 2, 2, True)
        out = rgbf(img)
        kick = yy > h * 0.86
        return np.where(kick[..., None], col('3a2418'), out)
    if kind == 'roller':
        slat = 0.7 + 0.3 * (np.mod(yy, 7.0) / 7.0)
        base = np.full((h, w, 3), 0.75, np.float32) * slat[..., None]
        streak = fbm((h, w), 1.2, seed, ax=0.1, ay=6.0, lo=8)
        base = base * (0.85 + 0.2 * streak)[..., None]
        rust = smooth(fbm((h, w), 1.6, seed + 2), 0.7, 0.85) * smooth(yy, h * 0.5, h)
        return mix(base, col('7a4a2e'), rust[..., None] * 0.6)


def cell_small_window(w, h, seed, lit, conv):
    if lit:
        rgb = interior(w, h, seed, curtain=('e0c8a0' if conv else 'f0e4cc'), dim=0.9)
    else:
        xx, yy = grid((h, w))
        rgb = mix(col('8a93ae'), col('262c3c'), smooth(yy / h, 0.0, 0.9)[..., None])
    img = Image.fromarray(to8(rgb))
    glazing(img, 0, 0, w, h, col('2a2018') if not conv else col('d8d0c0'), 2, 2, False, 4)
    return rgbf(img)


def scroll(d, cx, cy, r, turns, colour, width, flip=1.0, start=0.0):
    pts = []
    for i in range(int(48 * turns)):
        t = i / 48.0
        a = start + flip * t * 2 * np.pi
        rr = r * (1.0 - t / (turns + 0.4))
        pts.append((cx + np.cos(a) * rr, cy + np.sin(a) * rr))
    d.line(pts, fill=colour, width=width, joint='curve')


def leaf(d, cx, cy, ang, length, colour, outline):
    pts = []
    for i in range(16):
        t = i / 15.0
        wdt = np.sin(t * np.pi) * length * 0.28
        pts.append((t * length, wdt))
    pts += [(p[0], -p[1]) for p in reversed(pts)]
    ca, sa = np.cos(ang), np.sin(ang)
    poly = [(cx + p[0] * ca - p[1] * sa, cy + p[0] * sa + p[1] * ca) for p in pts]
    d.polygon(poly, fill=colour, outline=outline)


def cell_sign(w, h, text, seed, ground='14120f', letter='f2dfa0', shade='7a1e18', ornament=('c8322a', '2f8a4a', 'e8b830', '2e6ab0')):
    """A hand-painted fileteado board: a lined frame, curling scrolls and acanthus leaves in the corners, the name in
    shaded serif capitals. The names are invented."""
    s = 2
    img = Image.new('RGB', (w * s, h * s), tuple(int(c * 255) for c in col(ground)))
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    gold = tuple(int(c * 255) for c in col('e8c060'))
    d.rectangle([6, 6, W - 7, H - 7], outline=gold, width=4)
    d.rectangle([16, 16, W - 17, H - 17], outline=tuple(int(c * 255) for c in col(ornament[0])), width=3)
    rng = np.random.default_rng(seed)
    orn = [tuple(int(c * 255) for c in col(o)) for o in ornament]
    for (cx, flip) in ((70, 1.0), (W - 70, -1.0)):
        for k, (dy, rr) in enumerate(((H * 0.5, 46), (H * 0.3, 26), (H * 0.72, 26))):
            c = orn[(k + (0 if flip > 0 else 1)) % len(orn)]
            scroll(d, cx, dy, rr, 1.4, c, 7, flip, rng.uniform(0, 6.28))
            scroll(d, cx, dy, rr, 1.4, (250, 240, 220), 2, flip, rng.uniform(0, 6.28))
        for j in range(3):
            leaf(d, cx + flip * 30, H * 0.5 + (j - 1) * 34, (0.0 if flip > 0 else np.pi) + (j - 1) * 0.6, 60, orn[(j + 2) % 4], (255, 245, 220))
        d.ellipse([cx - 8, H * 0.5 - 8, cx + 8, H * 0.5 + 8], fill=orn[2], outline=(255, 245, 220))
    size = int(H * 0.5)
    font = ImageFont.truetype(SERIF, size)
    while d.textlength(text, font=font) > W - 300 and size > 20:
        size -= 2
        font = ImageFont.truetype(SERIF, size)
    tw = d.textlength(text, font=font)
    tx, ty = (W - tw) / 2, H * 0.5 - size * 0.62
    sh = tuple(int(c * 255) for c in col(shade))
    for o in range(1, 7):
        d.text((tx + o, ty + o), text, font=font, fill=sh)
    d.text((tx, ty), text, font=font, fill=tuple(int(c * 255) for c in col(letter)), stroke_width=2, stroke_fill=(30, 20, 14))
    # thin highlight line in each letter (the painter's white brush)
    img = img.resize((w, h), Image.LANCZOS)
    rgb = rgbf(img)
    wear = smooth(fbm((h, w), 1.5, seed + 9, lo=5), 0.8, 0.86)
    return mix(rgb, rgb * 0.6, wear[..., None])


def cell_railing(w, h, kind):
    """A cut-out railing that repeats along its length: iron balusters with scrolls, or a wooden balustrade."""
    s = 2
    img = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    if kind == 'iron':
        d.rectangle([0, 6, W, 16], fill=255)
        d.rectangle([0, H - 14, W, H - 6], fill=255)
        for i in range(8):
            x = (i + 0.5) * W / 8
            d.rectangle([x - 3, 10, x + 3, H - 10], fill=255)
        for i in range(4):
            cx = (i + 0.5) * W / 4
            for sgn in (-1, 1):
                d.arc([cx - 30 + sgn * 18, H * 0.25, cx + 6 + sgn * 18, H * 0.25 + 36], 0, 360, fill=255, width=5)
                d.arc([cx - 30 + sgn * 18, H * 0.62, cx + 6 + sgn * 18, H * 0.62 + 36], 0, 360, fill=255, width=5)
        col_rgb = np.full((h, w, 3), 0.16, np.float32)
    else:
        d.rectangle([0, 4, W, 26], fill=255)
        d.rectangle([0, H - 20, W, H - 6], fill=255)
        for i in range(10):
            x = (i + 0.5) * W / 10
            d.rectangle([x - 7, 20, x + 7, H - 14], fill=255)
            d.ellipse([x - 12, H * 0.42, x + 12, H * 0.42 + 30], fill=255)
        xx, yy = grid((h, w))
        col_rgb = np.full((h, w, 3), 0.78, np.float32) * (0.9 + 0.12 * fbm((h, w), 1.0, 41, ax=4.0, ay=0.3, lo=4))[..., None]
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return col_rgb, a


def cell_balustrade(w, h):
    s = 2
    img = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    for i in range(6):
        x = (i + 0.5) * W / 6
        pts = []
        for j in range(21):
            t = j / 20.0
            r = 7 + 9 * np.sin(np.pi * (0.15 + 0.7 * t)) ** 2 * (1.0 if t > 0.35 else 0.6)
            pts.append((x + r, H * (0.08 + 0.84 * t)))
        pts += [(2 * x - p[0], p[1]) for p in reversed(pts)]
        d.polygon(pts, fill=255)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    xx, yy = grid((h, w))
    rgb = np.full((h, w, 3), 0.86, np.float32) * (0.75 + 0.25 * np.cos((xx % (w / 6.0)) / (w / 6.0) * np.pi * 2 - np.pi) * 0.5 + 0.25)[..., None]
    return np.clip(rgb, 0, 1), a


def cell_awning(w, h, a_col, b_col):
    xx, yy = grid((h, w))
    stripe = np.mod(xx, 32.0) < 16.0
    rgb = np.where(stripe[..., None], col(a_col), col(b_col))
    rgb = rgb * (0.85 + 0.15 * fbm((h, w), 1.0, 51, lo=4))[..., None]
    scallop = (yy > h * 0.82) & (np.sqrt((np.mod(xx, 16.0) - 8) ** 2 + (yy - h * 0.82) ** 2) > 8.5)
    rgb = rgb * (1 - 0.25 * smooth(yy, h * 0.6, h * 0.82))[..., None]
    return rgb, np.where(scallop, 0.0, 1.0)


def cell_band(w, h, seed):
    s = 2
    img = Image.new('RGB', (w * s, h * s), tuple(int(c * 255) for c in col('e8dcc0')))
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    orn = [tuple(int(c * 255) for c in col(o)) for o in ('c8322a', '2f8a4a', 'e8b830', '2e6ab0')]
    d.rectangle([0, 8, W, 16], fill=orn[0])
    d.rectangle([0, H - 16, W, H - 8], fill=orn[0])
    for i in range(4):
        cx = (i + 0.5) * W / 4
        scroll(d, cx - 30, H * 0.5, 34, 1.5, orn[i % 4], 8, 1.0, 0.0)
        scroll(d, cx + 30, H * 0.5, 34, 1.5, orn[(i + 1) % 4], 8, -1.0, 3.1)
        leaf(d, cx, H * 0.5, -np.pi / 2, 40, orn[(i + 2) % 4], (40, 30, 20))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_poster(w, h, lines, ground, ink, seed):
    s = 2
    img = Image.new('RGB', (w * s, h * s), tuple(int(c * 255) for c in col(ground)))
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    y = 18
    for text, size in lines:
        font = ImageFont.truetype(SANS, size)
        tw = d.textlength(text, font=font)
        while tw > W - 24:
            size -= 2
            font = ImageFont.truetype(SANS, size)
            tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, y), text, font=font, fill=tuple(int(c * 255) for c in col(ink)))
        y += int(size * 1.15)
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    wear = smooth(fbm((h, w), 1.4, seed, lo=4), 0.7, 0.85)
    return mix(rgb, rgb * 0.7, wear[..., None])


def cell_text(w, h, text, ground, ink, font=SANS, lit=False):
    s = 2
    img = Image.new('RGB', (w * s, h * s), tuple(int(c * 255) for c in col(ground)))
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    size = int(H * 0.6)
    f = ImageFont.truetype(font, size)
    while d.textlength(text, font=f) > W - 16:
        size -= 2
        f = ImageFont.truetype(font, size)
    tw = d.textlength(text, font=f)
    d.rectangle([3, 3, W - 4, H - 4], outline=tuple(int(c * 255) for c in col(ink)), width=3)
    d.text(((W - tw) / 2, H * 0.5 - size * 0.6), text, font=f, fill=tuple(int(c * 255) for c in col(ink)))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_porthole(w, h, lit, seed):
    xx, yy = grid((h, w))
    r = np.sqrt((xx - w / 2) ** 2 + (yy - h / 2) ** 2)
    if lit:
        inner = interior(w, h, seed, dim=1.0)
    else:
        inner = mix(col('7a84a0'), col('20242e'), smooth(yy / h, 0.1, 0.9)[..., None])
    ring = (r > w * 0.36) & (r < w * 0.48)
    rgb = np.where(ring[..., None], col('8a7a50'), inner)
    rgb = np.where((r >= w * 0.48)[..., None], col('2a2c30'), rgb)
    return rgb


def cell_arch(w, h, lit, seed):
    xx, yy = grid((h, w))
    if lit:
        inner = interior(w, h, seed, dim=0.85)
    else:
        inner = mix(col('7a84a0'), col('1e222c'), smooth(yy / h, 0.0, 0.9)[..., None])
    arch = (yy > h * 0.42) | (np.sqrt((xx - w / 2) ** 2 + (yy - h * 0.42) ** 2) < w * 0.42)
    side = np.abs(xx - w / 2) < w * 0.42
    inside = arch & side & (yy < h - 4)
    rgb = np.where(inside[..., None], inner, col('7a4a3a'))
    bars = inside & ((np.abs(xx - w / 2) < 1.5) | (np.mod(yy, 14) < 1.5))
    return np.where(bars[..., None], col('2a2420'), rgb)


def tex_facade():
    A = 1024
    rgb = np.zeros((A, A, 3), np.float32)
    alpha = np.ones((A, A), np.float32)

    def put(name, cell, a=None):
        x, y, w, h = ATLAS[name]
        rgb[y:y + h, x:x + w] = cell[:h, :w]
        if a is not None:
            alpha[y:y + h, x:x + w] = a[:h, :w]

    for i in range(5):
        put('win_lit%d' % i, cell_window(128, 256, 100 + i, True, i))
    for i in range(3):
        put('win_dark%d' % i, cell_window(128, 256, 200 + i, False, i))
    put('shutter_louvre', cell_shutter(128, 256, 300, True))
    put('shutter_panel', cell_shutter(128, 256, 301, False))
    put('door_double', cell_door(128, 256, 310, 'double'))
    put('door_zaguan', cell_door(128, 256, 311, 'zaguan'))
    put('door_shop_lit', cell_door(128, 256, 312, 'shop'))
    put('door_roller', cell_door(128, 256, 313, 'roller'))
    put('win_small_lit', cell_small_window(128, 128, 320, True, False))
    put('win_small_dark', cell_small_window(128, 128, 321, False, False))
    put('win_conv_lit', cell_small_window(128, 128, 322, True, True))
    put('win_conv_dark', cell_small_window(128, 128, 323, False, True))
    # the names are invented: no real business is meant
    put('sign_cafe', cell_sign(512, 128, 'CAFÉ LA BRUMA', 400))
    put('sign_almacen', cell_sign(512, 128, 'ALMACÉN FERRANTE', 401, ground='1c2a20', letter='f4e4b0', shade='8a2a1a'))
    put('sign_bar', cell_sign(512, 128, 'BAR EL TRANVÍA', 402, ground='2a1416', letter='f0d890', shade='1c3a6a'))
    put('sign_despacho', cell_sign(512, 128, 'DESPACHO DE BEBIDAS', 403, ground='14182a', letter='f2e0a8', shade='8a1e18'))
    c, a = cell_railing(256, 128, 'iron')
    put('rail_iron', c, a)
    c, a = cell_railing(256, 128, 'wood')
    put('rail_wood', c, a)
    c, a = cell_awning(256, 128, '2f6a44', 'e8e0c8')
    put('awning_green', c, a)
    c, a = cell_awning(256, 128, 'a8302a', 'ece2c8')
    put('awning_red', c, a)
    put('filete_band', cell_band(256, 128, 500))
    put('poster_baile', cell_poster(128, 128, [('GRAN', 34), ('BAILE', 40), ('SÁBADO', 22), ('ORQUESTA', 18)], 'e8d8a8', 'a02820', 510))
    put('poster_alquila', cell_poster(128, 128, [('SE', 30), ('ALQUILA', 30), ('PIEZA', 30)], 'f0ece0', '1a1a1a', 511))
    put('tram_dest', cell_text(256, 64, 'VUELTA DE ROCHA', '141414', 'f0e8d0'))
    put('tram_win_lit', interior(128, 64, 520, dim=0.9))
    put('shop_lit', interior(128, 64, 521, curtain='f0e0c0'))
    put('porthole_lit', cell_porthole(64, 64, True, 530))
    put('porthole_dark', cell_porthole(64, 64, False, 531))
    c, a = cell_balustrade(128, 64)
    put('balustrade', c, a)
    put('arch_lit', cell_arch(64, 64, True, 540))
    put('arch_dark', cell_arch(64, 64, False, 541))
    put('plate_guardia', cell_text(128, 64, 'GUARDIA', '1e2c4a', 'e8e4d8'))
    save('facade_a', rgb, alpha)


def tex_slush():
    """Snow trodden by a whole neighbourhood: soft grey-lavender, pressed into overlapping boot prints and heel marks,
    brown-grey where it has gone to slush, lumps of clean snow kicked up between. Tileable. Alpha = height."""
    S = 512
    h = np.zeros((S, S), np.float32)
    rng = np.random.default_rng(91)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    for i in range(520):
        cx, cy = rng.uniform(0, S), rng.uniform(0, S)
        a = rng.uniform(0, np.pi)
        L, W = rng.uniform(9, 13), rng.uniform(4, 5.5)
        dx = (xx - cx + S / 2) % S - S / 2
        dy = (yy - cy + S / 2) % S - S / 2
        u = dx * np.cos(a) + dy * np.sin(a)
        v = -dx * np.sin(a) + dy * np.cos(a)
        d = (u / L) ** 2 + (v / W) ** 2
        h -= np.clip(1.0 - d, 0, 1) ** 0.6 * rng.uniform(0.25, 0.5)
    h = blur(h, 1.2)
    h = norm01(h + fbm((S, S), 2.0, 92) * 0.8)
    dirt = smooth(fbm((S, S), 1.7, 93), 0.55, 0.85)
    lumps = smooth(fbm((S, S), 0.7, 94, lo=20), 0.7, 0.85)
    low = 1.0 - h
    rgb = mix(col('c4c6d2'), col('8e909c'), smooth(low, 0.35, 0.85)[..., None])
    rgb = mix(rgb, col('7a746c'), (dirt * smooth(low, 0.4, 0.9) * 0.6)[..., None])
    rgb = mix(rgb, col('dfe2ec'), (lumps * 0.6)[..., None])
    rgb = painterly(rgb, 0.4, 95)
    save('slush_a', rgb, h)


def tex_tiles():
    """The café's floor: cream and terracotta squares on the diagonal (32 cm), worn and dulled by the boots; light enough
    that the people in the room stand out against it."""
    S = 512
    x, y = grid((S, S))
    t = S / 8.0
    u = (x + y) / np.sqrt(2.0)
    v = (x - y) / np.sqrt(2.0)
    cu = np.floor(u / (t * 0.707))
    cv = np.floor(v / (t * 0.707))
    chk = np.mod(cu + cv, 2.0)
    vein = fbm((S, S), 1.3, 101, ax=0.4, ay=2.0, lo=4)
    white = mix(col('ece4d0'), col('d0c6b0'), smooth(vein, 0.6, 0.9)[..., None])
    black = mix(col('9a5a44'), col('b07058'), smooth(vein, 0.55, 0.9)[..., None])
    rgb = np.where(chk[..., None] > 0.5, white, black)
    fu = u / (t * 0.707) - cu
    fv = v / (t * 0.707) - cv
    grout = (np.minimum(fu, 1 - fu) < 0.03) | (np.minimum(fv, 1 - fv) < 0.03)
    rgb = np.where(grout[..., None], col('6a645a'), rgb)
    wear = fbm((S, S), 2.0, 102)
    rgb = mix(rgb, col('8a8478'), (smooth(wear, 0.6, 0.9) * 0.25)[..., None])
    save('tiles_a', rgb)


def tex_twigs():
    """A card of bare plane-tree twigs under wet snow, for the trees' crowns: branching grey-brown twigs fanning up from
    the bottom middle, a line of snow along the top of each. Alpha cut-out."""
    S = 512
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    snowl = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(img)
    ds = ImageDraw.Draw(snowl)
    rng = np.random.default_rng(77)

    def branch(x, y, ang, length, width, depth):
        if depth > 7 or length < 5:
            return
        x2 = x + np.cos(ang) * length
        y2 = y - np.sin(ang) * length
        bark = (int(58 + 16 * rng.random()), int(52 + 14 * rng.random()), int(50 + 12 * rng.random()), 255)
        if depth >= 1:
            d.line([(x, y), (x2, y2)], fill=bark, width=max(1, int(width)))
            # wet snow lies along the top of every twig that is not near vertical, thick on the boughs
            if abs(np.cos(ang)) > 0.15:
                ds.line([(x, y - width * 0.55), (x2, y2 - width * 0.55)], fill=255, width=max(1, int(width * 0.9 + 1)))
        n = 2 if depth < 2 else (2 + (1 if rng.random() < 0.4 else 0))
        for i in range(n):
            na = ang + rng.uniform(-0.75, 0.75)
            branch(x2, y2, na, length * rng.uniform(0.58, 0.78), width * 0.68, depth + 1)
    for k in range(9):
        a = np.pi * (0.2 + 0.6 * k / 8.0) + rng.uniform(-0.08, 0.08)
        branch(S / 2 + np.cos(a) * 30, S - 20 - np.sin(a) * 20, a, rng.uniform(78, 96), 7, 0)
    a = np.asarray(img, np.float32) / 255.0
    sn = np.asarray(snowl, np.float32) / 255.0
    rgb = a[..., :3]
    alpha = a[..., 3]
    snow = sn * (alpha > 0.1)
    snow = blur(np.asarray(snowl, np.float32) / 255.0, 0.6, False)
    alpha = np.clip(np.maximum(alpha, snow * 0.95), 0, 1)
    rgb = mix(rgb, np.array([0.9, 0.91, 0.95], np.float32), np.clip(snow * 1.2, 0, 1)[..., None])
    save('twigs_a', rgb, alpha)


def tex_leaves():
    """Evergreen foliage under snow, for the canopies of the patios' trees: dark glossy leaf clumps, small gaps of
    darker shade between them. Tileable; snow is laid on by the shader where the canopy faces up."""
    shape = (N, N)
    rng = np.random.default_rng(141)
    h = np.zeros(shape, np.float32)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    for i in range(900):
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        a = rng.uniform(0, np.pi)
        L, W = rng.uniform(7, 12), rng.uniform(3, 5)
        dx = (xx - cx + N / 2) % N - N / 2
        dy = (yy - cy + N / 2) % N - N / 2
        u = dx * np.cos(a) + dy * np.sin(a)
        v = -dx * np.sin(a) + dy * np.cos(a)
        d = (u / L) ** 2 + (v / W) ** 2
        h = np.maximum(h, np.clip(1.0 - d, 0, 1) * rng.uniform(0.6, 1.0))
    clump = fbm(shape, 2.2, 142)
    rgb = mix(col('12201a'), col('2e4630'), h[..., None])
    rgb = rgb * (0.7 + 0.5 * clump)[..., None]
    rgb = mix(rgb, col('4a5a3a'), (smooth(h, 0.85, 1.0) * 0.4)[..., None])
    save('leaves_a', rgb)
    save('leaves_n', normal_from_height(h * 0.6 + clump * 0.4, 5.0))


def tex_lattice():
    """Riveted iron lattice for the transporter bridge, cut-out (alpha): the top half a tower face (flanged edges, X
    bracing, battens, rivets), the bottom half a girder side (top and bottom chords, verticals, Warren diagonals). Grey
    iron with rust at the joints; U repeats along the member."""
    W, H = 512, 512
    s = 2
    img = Image.new('L', (W * s, H * s), 0)
    d = ImageDraw.Draw(img)
    # tower face: 0..H/2, one panel per 128 px of width (repeats)
    for p in range(4):
        x0 = p * 128 * s
        x1 = (p + 1) * 128 * s
        d.rectangle([x0, 0, x1, 10 * s], fill=255)
        d.rectangle([x0, 0, x0 + 8 * s, 256 * s], fill=255)
        d.rectangle([x1 - 8 * s, 0, x1, 256 * s], fill=255)
        d.line([(x0 + 6 * s, 8 * s), (x1 - 6 * s, 248 * s)], fill=255, width=7 * s)
        d.line([(x1 - 6 * s, 8 * s), (x0 + 6 * s, 248 * s)], fill=255, width=7 * s)
        d.rectangle([x0, 122 * s, x1, 132 * s], fill=255)
    d.rectangle([0, 246 * s, W * s, 256 * s], fill=255)
    # girder side: 256..512
    for p in range(4):
        x0 = p * 128 * s
        x1 = (p + 1) * 128 * s
        d.rectangle([x0, 256 * s, x1, 272 * s], fill=255)
        d.rectangle([x0, 496 * s, x1, 512 * s], fill=255)
        d.rectangle([x0, 256 * s, x0 + 9 * s, 512 * s], fill=255)
        d.line([(x0 + 4 * s, 268 * s), (x0 + 64 * s, 500 * s)], fill=255, width=8 * s)
        d.line([(x0 + 64 * s, 500 * s), (x1 - 4 * s, 268 * s)], fill=255, width=8 * s)
        d.line([(x0 + 64 * s, 268 * s), (x0 + 64 * s, 500 * s)], fill=255, width=4 * s)
    a = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255.0
    x, y = grid((H, W))
    iron = np.stack([np.full((H, W), 0.36), np.full((H, W), 0.37), np.full((H, W), 0.38)], -1).astype(np.float32)
    iron = iron * (0.85 + 0.25 * fbm((H, W), 1.4, 151))[..., None]
    rust = smooth(fbm((H, W), 1.8, 152), 0.68, 0.85)
    iron = mix(iron, col('6a4430'), rust[..., None] * 0.6)
    # rivets: a lighter dot every 8 px along the flanges
    riv = ((np.mod(x, 8) < 2.5) & (np.mod(y, 8) < 2.5)).astype(np.float32) * smooth(a, 0.9, 1.0)
    iron = iron * (1 + 0.35 * riv)[..., None]
    # edges of each member darker (depth)
    edge = np.clip(a - blur(a, 1.5, False), 0, 1)
    iron = iron * (1 - 0.4 * edge)[..., None]
    save('lattice_a', iron, a)


def tex_walls_array():
    """The tiling surfaces of La Boca's houses as one array texture (one draw for a whole stretch of houses): layers
    chapa, stucco, brick, planks, corrugated iron, stone, steel, snow (the caps and drifts), slate (the mansards),
    leaves (the canopies), top to bottom; alpha = roughness. And the normals."""
    struct = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'structures'))
    snowdir = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'snow'))
    layers = [(OUT, 'chapa', None), (OUT, 'stucco', 0.9), (struct, 'brick', 0.93), (struct, 'planks', 0.9),
              (struct, 'corrugated', None), (struct, 'stone', 0.95), (struct, 'steel', None),
              (snowdir, 'snow', 0.8), (struct, 'slate', None), (OUT, 'leaves', 0.6)]
    albedo = []
    normal = []
    for folder, name, rough in layers:
        a = Image.open(os.path.join(folder, name + '_a.png')).convert('RGBA').resize((N, N))
        arr = np.asarray(a, np.float32) / 255.0
        if rough is not None:
            arr[..., 3] = rough
        albedo.append(arr)
        normal.append(np.asarray(Image.open(os.path.join(folder, name + '_n.png')).convert('RGB').resize((N, N)), np.float32) / 255.0)
    # WebP (near-lossless quality): the layers repeat textures already in the project, so keep the copy small
    a = np.concatenate(albedo, 0)
    Image.fromarray(np.dstack([to8(a[..., :3]), to8(a[..., 3])]), 'RGBA').save(os.path.join(OUT, 'walls_a.webp'), quality=92, method=6)
    Image.fromarray(to8(np.concatenate(normal, 0)), 'RGB').save(os.path.join(OUT, 'walls_n.webp'), quality=94, method=6)
    print('wrote walls_a.webp, walls_n.webp')


LAYERS = 10
IMPORT_ARRAY = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://assets/tex/boca/{name}.webp"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={slices}
"""


def fix_imports():
    """Mipmaps on, lossless, the normal-map flag for *_n, no automatic re-compression; the wall arrays as arrays.
    Run after `godot --import` has written the .import files, then import again."""
    import glob
    import re
    for path in sorted(glob.glob(os.path.join(OUT, '*.png.import'))):
        name = os.path.basename(path)[:-len('.png.import')]
        text = open(path).read()
        new = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", text)
        new = re.sub(r"compress/normal_map=\d", "compress/normal_map=%d" % (1 if name.endswith('_n') else 2), new)
        new = re.sub(r"compress/mode=\d", "compress/mode=0", new)
        new = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", new)
        if new != text:
            open(path, 'w').write(new)
            print('patched', name)
    for name in ('walls_a', 'walls_n'):
        path = os.path.join(OUT, name + '.webp.import')
        text = open(path).read() if os.path.exists(path) else ''
        if 'importer="2d_array_texture"' not in text or 'slices/vertical=%d' % LAYERS not in text:
            open(path, 'w').write(IMPORT_ARRAY.format(name=name, slices=LAYERS))
            print('array import', name)


if __name__ == '__main__':
    if sys.argv[1:] == ['--fix-imports']:
        fix_imports()
        sys.exit(0)
    tex_chapa()
    tex_stucco()
    tex_ruts()
    tex_facade()
    tex_twigs()
    tex_slush()
    tex_tiles()
    tex_leaves()
    tex_lattice()
    tex_walls_array()
    fix_imports()
