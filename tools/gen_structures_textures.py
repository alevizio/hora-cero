#!/usr/bin/env python3
"""Procedural textures for the structures kit (buildings, props, vehicles) the La Boca and Plaza de Mayo kits build on.
Usage:  python3 tools/gen_structures_textures.py [name ...]      (no names = everything)
Output: godot/assets/tex/structures/<name>_a.png  (albedo; alpha = roughness unless the texture is a cut-out)
        godot/assets/tex/structures/<name>_n.png  (OpenGL normal map)
Texel density: 512 px = 2.56 m (200 px/m) for all tiling surface textures.
Wall textures (siding, brick, render) tile along U only; V is anchored: image bottom = ground line."""
import json
import os
import sys
sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont
from structures_texlib import *

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'structures'))
# the three painted signs of the trim atlas (trim_labels.json lists them for the game)
SIGN_LABELS = ["BARRACKS", "RADIO POST", "SUPPLY DEPOT"]
N = 512
FONT_BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'


def out(name, rgb, normal=None, rough=None, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    rgb = np.clip(rgb, 0, 1)
    if alpha is not None:
        save_rgba(os.path.join(OUT, name + '_a.png'), rgb, alpha)
    elif rough is not None:
        save_rgba(os.path.join(OUT, name + '_a.png'), rgb, rough_alpha(rough))
    else:
        save_rgb(os.path.join(OUT, name + '_a.png'), rgb)
    if normal is not None:
        save_normal(os.path.join(OUT, name + '_n.png'), normal)
    print('wrote', name)


# --------------------------------------------------------------------------------------------------------------------
# Shared weathering helpers
# --------------------------------------------------------------------------------------------------------------------
def top_streaks(shape, seed, reach=0.45, density=0.5):
    """Rain streaks hanging from the top edge (0..1), tileable along x only."""
    h, w = shape
    _, y = grid(shape)
    col_noise = fbm((1, w), 1.2, seed, lo=3)[0]
    col_fine = fbm((1, w), 0.4, seed + 1, lo=20)[0]
    length = (0.25 + 0.75 * col_noise) * reach * h * (0.6 + 0.8 * col_fine)
    s = np.clip(1.0 - y / (length[None, :] + 1e-3), 0, 1) ** 1.5
    s *= smooth(col_noise * 0.6 + col_fine * 0.4, 1.0 - density, 1.0 - density + 0.35)[None, :]
    ragged = fbm(shape, 1.5, seed + 2, ax=0.25, ay=6.0)
    return np.clip(s * (0.55 + 0.6 * ragged), 0, 1)


def base_grime(shape, seed, height_px=110):
    """Splash-back dirt band rising from the bottom edge (0..1) with an irregular tide line."""
    h, w = shape
    _, y = grid(shape)
    line = fbm((1, w), 1.6, seed, lo=2)[0] * 0.7 + fbm((1, w), 0.8, seed + 3, lo=12)[0] * 0.3
    top = h - height_px * (0.45 + 0.9 * line)
    g = smooth(y, top[None, :] - 18, top[None, :] + height_px * 0.55)
    return np.clip(g * (0.65 + 0.5 * fbm(shape, 1.8, seed + 5)), 0, 1)


def speckle(shape, seed, density=0.02, size=1.2):
    s = white(shape, seed) < density
    return np.clip(blur(s.astype(np.float32), size) * (6.0 * size * size), 0, 1)


def lichen_blobs(shape, seed, amount=0.5):
    """Irregular clustered crusty patches (0..1), not polka dots."""
    a = fbm(shape, 1.1, seed, lo=10, hi=70)
    b = fbm(shape, 2.2, seed + 1, lo=2)
    return smooth(a, 0.74 - 0.1 * amount, 0.80 - 0.1 * amount) * smooth(b, 0.45, 0.75)


def cracks(shape, seed, width=0.012, lo=2):
    a = fbm(shape, 2.2, seed, lo=lo)
    b = fbm(shape, 2.0, seed + 7, lo=lo)
    ridge = np.minimum(np.abs(a - 0.5), 1.0) / width
    gate = smooth(b, 0.45, 0.62)
    return np.clip(1.0 - ridge, 0, 1) * gate


# --------------------------------------------------------------------------------------------------------------------
# Wood
# --------------------------------------------------------------------------------------------------------------------
def wood_rows(shape, seed, rows, joint_every=None):
    """Returns dict with per-row wood grain (0..1), row index, in-row v (0..1), per-board id noise and joint mask."""
    h, w = shape
    x, y = grid(shape)
    rh = h / rows
    row = np.floor(y / rh).astype(np.int32)
    fy = (y / rh) - row
    grain_src = fbm(shape, 1.5, seed, ax=14.0, ay=1.0, lo=3)
    fine_src = fbm(shape, 0.7, seed + 1, ax=10.0, ay=1.0, lo=24)
    offs = (cell_rand(row, 0, seed + 2) * w).astype(np.float32)
    yoff = (cell_rand(row, 1, seed + 3) * h).astype(np.float32)
    grain = warp(grain_src, offs, yoff)
    fine = warp(fine_src, offs * 1.7, yoff * 0.6)
    # one butt joint per row at a pseudo random stud line
    studs = joint_every or (w // 4)
    jx = (np.floor(cell_rand(row, 2, seed + 4) * (w / studs)) * studs + studs * 0.5 * (row % 2))
    dj = np.abs(((x - jx + w / 2) % w) - w / 2)
    joint = np.clip(1.0 - dj / 1.3, 0, 1)
    board = (row * 2 + (((x - jx) % w) > w / 2)).astype(np.int32)  # two boards per row, split at the joint
    tone = cell_rand(board, 7, seed + 5)
    hue = cell_rand(board, 9, seed + 6)
    return dict(grain=grain, fine=fine, row=row, fy=fy, joint=joint, jdist=dj, tone=tone, hue=hue, x=x, y=y, rh=rh)


def knots(shape, seed, count, rows):
    """Dark knot blobs + a ring field to bend nearby grain a little."""
    h, w = shape
    rng = np.random.default_rng(seed)
    x, y = grid(shape)
    k = np.zeros(shape, np.float32)
    rh = h / rows
    for _ in range(count):
        cx = rng.uniform(0, w)
        cy = (rng.integers(0, rows) + rng.uniform(0.3, 0.7)) * rh
        r = rng.uniform(2.0, 4.5)
        dx = ((x - cx + w / 2) % w) - w / 2
        dy = (y - cy)
        d = np.sqrt((dx / 1.6) ** 2 + dy ** 2)
        k = np.maximum(k, np.clip(1.0 - d / r, 0, 1))
    return k


def tex_planks():
    """Rough sawn planks, boards run along U, 16 boards of 0.16 m per tile. Pale so vertex colour can tint it."""
    shape = (N, N)
    wr = wood_rows(shape, 11, 16)
    kn = knots(shape, 12, 26, 16)
    g = np.clip(wr['grain'] * 0.75 + wr['fine'] * 0.35 - kn * 0.25, 0, 1)
    light = col('c4b08a')
    grey = col('a39c8c')
    dark = col('6f5f49')
    base = mix(light, grey, (wr['hue'] * 0.9)[..., None])
    rgb = mix(dark, base, smooth(g, 0.12, 0.78)[..., None])
    rgb = rgb * (0.78 + 0.34 * wr['tone'])[..., None]
    rgb = mix(rgb, col('4a3c2c'), (smooth(kn, 0.25, 0.9) * 0.8)[..., None])
    gap = np.clip(1.0 - np.minimum(wr['fy'], 1 - wr['fy']) * wr['rh'] / 1.4, 0, 1)
    cup = 1.0 - (np.abs(wr['fy'] - 0.5) * 2) ** 3
    height = 0.55 + 0.25 * cup + 0.16 * (g - 0.5) + 0.06 * (wr['tone'] - 0.5) - 0.2 * kn
    height = height * (1 - gap) * (1 - 0.8 * wr['joint'])
    # nails either side of each joint and at regular bearers
    nail = np.zeros(shape, np.float32)
    ny = np.minimum(np.abs(wr['fy'] - 0.25), np.abs(wr['fy'] - 0.75)) * wr['rh']
    for bx in (N * 0.25, N * 0.75):
        dn = np.sqrt((np.abs(((wr['x'] - bx + N / 2) % N) - N / 2)) ** 2 + ny ** 2)
        nail = np.maximum(nail, np.clip(1.0 - dn / 1.7, 0, 1))
    dn = np.sqrt((wr['jdist'] - 6.0) ** 2 + ny ** 2)
    nail = np.maximum(nail, np.clip(1.0 - dn / 1.7, 0, 1))
    rust = blur(nail, 2.5) * 6
    rust_drip = np.clip(blur(np.roll(nail, 4, 0), (5, 1.2)) * 8, 0, 1)
    rgb = mix(rgb, col('6a4630'), (np.clip(rust + rust_drip, 0, 1) * 0.45)[..., None])
    rgb = mix(rgb, col('2e2a26'), nail[..., None] * 0.9)
    dirt = fbm(shape, 1.9, 13)
    rgb = rgb * (0.86 + 0.2 * dirt)[..., None]
    cav = cavity(height, 2.0)
    rgb = rgb * np.clip(1.0 - cav * 2.2, 0.35, 1.25)[..., None]
    rgb = mix(rgb, col('1c1915'), (np.clip(gap * 1.2 + wr['joint'] * 0.8, 0, 1) * 0.9)[..., None])
    rgb = painterly(rgb, 0.35, 14)
    out('planks', rgb, normal_from_height(height + nail * 0.08, 5.0))


def tex_siding():
    """Horizontal weatherboard with peeling drab paint; U tiles, V anchored (bottom = ground, top = under the eaves)."""
    shape = (N, N)
    rows = 16
    wr = wood_rows(shape, 21, rows, joint_every=128)
    x, y = wr['x'], wr['y']
    g = np.clip(wr['grain'] * 0.75 + wr['fine'] * 0.35, 0, 1)
    wood = mix(col('4d463c'), mix(col('91897a'), col('7b7364'), wr['hue'][..., None]), smooth(g, 0.1, 0.8)[..., None])
    wood = wood * (0.8 + 0.3 * wr['tone'])[..., None]
    paint_a = col('a8a892')
    paint_b = col('bcbaa4')
    paint_c = col('90917c')
    blot = fbm(shape, 2.0, 22)
    paint = mix(mix(paint_c, paint_a, smooth(blot, 0.15, 0.6)[..., None]), paint_b, smooth(blot, 0.55, 0.95)[..., None])
    paint = paint * (0.92 + 0.14 * wr['tone'])[..., None]
    paint = paint * (0.95 + 0.08 * wr['fine'])[..., None]
    # peeling: more at the lower edge of each board, near the ground and in large weathered patches
    peel_n = fbm(shape, 2.0, 23, ax=1.6, ay=1.0, lo=2) * 0.62 + fbm(shape, 1.0, 24, ax=2.5, lo=9) * 0.38
    low_edge = wr['fy'] ** 2.5
    ground = smooth(y, N * 0.55, N * 1.0)
    board_bias = (cell_rand(wr['row'], 5, 25) - 0.5) * 0.22
    peel_v = peel_n + low_edge * 0.22 + ground * 0.2 + board_bias + 0.1 * top_streaks(shape, 26, 0.5, 0.6)
    peel = smooth(peel_v, 0.63, 0.655)
    flake_rim = smooth(peel_v, 0.60, 0.63) * (1 - peel)
    rgb = mix(paint, wood, peel[..., None])
    rgb = mix(rgb, np.clip(paint * 1.18, 0, 1), flake_rim[..., None] * 0.6)
    # lap shadow under each board's lower edge and the stepped clapboard profile
    lap = np.clip(1.0 - wr['fy'] * wr['rh'] / 5.0, 0, 1)
    height = wr['fy'] * 0.8 + 0.1 * (g - 0.5) * peel + 0.06 * (1 - peel)
    height = height * (1 - 0.6 * wr['joint'])
    rgb = rgb * (1.0 - 0.42 * lap ** 1.5)[..., None]
    rgb = rgb * (1.0 + 0.10 * smooth(wr['fy'], 0.7, 1.0))[..., None]
    rgb = mix(rgb, col('26231d'), (wr['joint'] * 0.8)[..., None])
    # nail columns on the studs with rust dribbles
    ny = np.abs(wr['fy'] - 0.72) * wr['rh']
    nail = np.zeros(shape, np.float32)
    for sx in range(0, N, 128):
        dn = np.sqrt((np.abs(((x - sx - 64 + N / 2) % N) - N / 2)) ** 2 + ny ** 2)
        nail = np.maximum(nail, np.clip(1.0 - dn / 1.6, 0, 1))
    drip = np.clip(ndimage.gaussian_filter(np.roll(nail, 7, 0), (7, 1.0), mode='wrap') * 9, 0, 1)
    rgb = mix(rgb, col('70482f'), (drip * 0.5)[..., None])
    rgb = mix(rgb, col('3a2e26'), nail[..., None])
    # weathering gradients
    st = top_streaks(shape, 27, 0.55, 0.7)
    gr = base_grime(shape, 28, 100)
    algae = gr * smooth(fbm(shape, 1.8, 29), 0.45, 0.8)
    rgb = mix(rgb, col('4d4a3e'), (st * 0.5)[..., None])
    rgb = mix(rgb, col('5c5138'), (gr * 0.62)[..., None])
    rgb = mix(rgb, col('4f5a36'), (algae * 0.35)[..., None])
    rgb = rgb * (0.9 + 0.16 * fbm(shape, 2.2, 30))[..., None]
    rgb = painterly(rgb, 0.35, 31)
    out('siding', rgb, normal_from_height(height + nail * 0.05, 5.5, True, False))


# --------------------------------------------------------------------------------------------------------------------
# Masonry
# --------------------------------------------------------------------------------------------------------------------
def brick_layer(shape, seed, course=16.0):
    """English bond brickwork: returns rgb, height, mortar mask. Tileable in x and y."""
    h, w = shape
    x, y = grid(shape)
    wob = (fbm(shape, 1.2, seed, lo=6) - 0.5) * 1.6
    xx = x + wob
    yy = y + (fbm(shape, 1.2, seed + 1, lo=6) - 0.5) * 1.2
    row = np.floor(yy / course).astype(np.int32)
    rows_total = int(round(h / course))
    fy = yy - row * course
    header = (row % 2) == 1
    bw = np.where(header, w / 24.0, w / 12.0)
    off = np.where(header, w / 48.0, 0.0)
    bx = np.floor((xx + off) / bw).astype(np.int32)
    fx = (xx + off) - bx * bw
    per = np.where(header, 24, 12)
    bxm = np.mod(bx, per)
    rowm = np.mod(row, rows_total)
    d = np.minimum(np.minimum(fx, bw - fx), np.minimum(fy, course - fy))
    mortar = 1.0 - smooth(d, 1.0, 2.2)
    r1 = cell_rand(bxm + header * 100, rowm, seed + 2)
    r2 = cell_rand(bxm + header * 100, rowm, seed + 3)
    r3 = cell_rand(bxm + header * 100, rowm, seed + 4)
    base = mix(col('84584a'), col('9a6a50'), r1[..., None])
    base = mix(base, col('6e4a40'), smooth(r2, 0.55, 0.9)[..., None] * 0.9)
    base = mix(base, col('54474a'), (r3 > 0.9).astype(np.float32)[..., None] * 0.85)
    base = mix(base, col('b3906f'), (r3 < 0.06).astype(np.float32)[..., None] * 0.7)
    grainy = fbm(shape, 0.8, seed + 5, lo=14)
    base = base * (0.84 + 0.3 * grainy)[..., None]
    pits = speckle(shape, seed + 6, 0.012, 0.8)
    base = base * (1 - 0.35 * pits)[..., None]
    mort_col = mix(col('8f8672'), col('a69d88'), fbm(shape, 1.5, seed + 7)[..., None])
    rgb = mix(base, mort_col, mortar[..., None])
    height = (1 - mortar) * (0.75 + 0.2 * (r2 - 0.5) + 0.12 * (grainy - 0.5) - 0.15 * pits) + mortar * 0.38
    # soft chipped edges
    rgb = rgb * (1.0 - 0.25 * smooth(d, 3.2, 1.6) * (1 - mortar))[..., None]
    return rgb, height.astype(np.float32), mortar


def tex_brick():
    shape = (N, N)
    rgb, height, mortar = brick_layer(shape, 41)
    soot = fbm(shape, 2.1, 42)
    rgb = rgb * (0.82 + 0.26 * soot)[..., None]
    eff = smooth(fbm(shape, 1.8, 43), 0.62, 0.85) * (1 - mortar) * 0.4
    rgb = mix(rgb, col('c9c2b0'), eff[..., None])
    st = top_streaks(shape, 44, 0.5, 0.55)
    gr = base_grime(shape, 45, 95)
    rgb = mix(rgb, col('3d3833'), (st * 0.5)[..., None])
    rgb = mix(rgb, col('4a4032'), (gr * 0.6)[..., None])
    rgb = mix(rgb, col('4c5634'), (gr * smooth(fbm(shape, 1.7, 46), 0.4, 0.75) * 0.45)[..., None])
    rgb = rgb * np.clip(1.0 - cavity(height, 2.0) * 1.2, 0.6, 1.2)[..., None]
    rgb = painterly(rgb, 0.3, 47)
    out('brick', rgb, normal_from_height(height, 4.5))


def tex_render():
    """Lime render over brick: cracks, fallen patches showing brick, damp base, streaks from the eaves."""
    shape = (N, N)
    brick, bh, _ = brick_layer(shape, 51)
    brick = brick * 0.92
    x, y = grid(shape)
    big = fbm(shape, 2.3, 52)
    trowel = fbm(shape, 1.1, 53, ax=3.0, ay=1.0, lo=8)
    plaster = mix(col('b9b196'), col('d2c9ac'), smooth(big, 0.2, 0.8)[..., None])
    plaster = plaster * (0.93 + 0.12 * trowel)[..., None]
    old = smooth(fbm(shape, 1.9, 54), 0.5, 0.8)
    plaster = mix(plaster, col('a89f86'), (old * 0.5)[..., None])
    # fallen patches: favour the lower third, noisy edge
    pn = fbm(shape, 2.2, 55, lo=2) * 0.7 + fbm(shape, 1.0, 56, lo=9) * 0.3
    pv = pn + smooth(y, N * 0.5, N) * 0.16 - smooth(y, 0, N * 0.3) * 0.05
    patch = smooth(pv, 0.69, 0.71)
    rim = smooth(pv, 0.655, 0.69) * (1 - patch)
    cr = cracks(shape, 57, 0.010) * (1 - patch)
    cr2 = cracks(shape, 58, 0.006, lo=4) * (1 - patch) * 0.6
    crack = np.clip(cr + cr2, 0, 1)
    rgb = mix(plaster, brick, patch[..., None])
    rgb = mix(rgb, np.clip(plaster * 1.12, 0, 1), rim[..., None] * 0.7)
    under = np.clip(patch - np.roll(patch, 4, 0), 0, 1)  # top inner edge of each hole sits in shadow
    rgb = rgb * (1 - 0.45 * blur(under, 1.2))[..., None]
    rgb = mix(rgb, col('4b4438'), (crack * 0.75)[..., None])
    height = mix(0.8 + 0.08 * (trowel - 0.5), bh * 0.55, patch) - crack * 0.25
    st = top_streaks(shape, 59, 0.6, 0.75)
    gr = base_grime(shape, 60, 105)
    rgb = mix(rgb, col('5a5548'), (st * 0.55)[..., None])
    rgb = mix(rgb, col('6a5c40'), (gr * 0.6)[..., None])
    rgb = mix(rgb, col('56613a'), (gr * smooth(fbm(shape, 1.7, 61), 0.4, 0.75) * 0.5)[..., None])
    rust = top_streaks(shape, 62, 0.8, 0.12)
    rgb = mix(rgb, col('8a5a36'), (rust * 0.35)[..., None])
    rgb = rgb * (0.9 + 0.16 * fbm(shape, 2.4, 63))[..., None]
    rgb = painterly(rgb, 0.35, 64)
    out('render', rgb, normal_from_height(height, 4.0, True, False))


def tex_stone():
    """Coursed rubble masonry (compound walls). Tileable both ways."""
    shape = (N, N)
    rng = np.random.default_rng(71)
    pts = []
    rows = 14
    rh = N / rows
    for r in range(rows):
        x0 = rng.uniform(0, 40)
        xpos = x0
        while xpos < N + x0 - 18:
            wdt = rng.uniform(34, 78)
            pts.append(((xpos + wdt * 0.5) % N, (r + 0.5) * rh + rng.uniform(-4, 4)))
            xpos += wdt
    pts = np.array(pts, np.float32)
    # anisotropic metric: stones are wider than tall
    sy = 1.7
    x, y = grid(shape)
    big_shape = (int(N * sy), N)
    f1, f2, idx = voronoi(big_shape, pts * np.array([1, sy], np.float32))
    f1 = np.asarray(Image.fromarray(f1).resize((N, N), Image.BILINEAR))
    f2 = np.asarray(Image.fromarray(f2).resize((N, N), Image.BILINEAR))
    idx = np.asarray(Image.fromarray(idx.astype(np.int32)).resize((N, N), Image.NEAREST))
    edge = (f2 - f1) + (fbm(shape, 1.2, 72, lo=8) - 0.5) * 5.0
    mortar = 1.0 - smooth(edge, 2.0, 5.5)
    r1 = cell_rand(idx, 1, 73)
    r2 = cell_rand(idx, 2, 74)
    r3 = cell_rand(idx, 3, 75)
    stone = mix(col('8d8776'), col('a39a82'), r1[..., None])
    stone = mix(stone, col('78705f'), smooth(r2, 0.5, 0.9)[..., None] * 0.9)
    stone = mix(stone, col('8f7f66'), (r3 > 0.8).astype(np.float32)[..., None] * 0.55)
    stone = mix(stone, col('71746f'), (r3 < 0.14).astype(np.float32)[..., None] * 0.55)
    rough_n = fbm(shape, 1.3, 76, lo=5)
    strat = fbm(shape, 1.4, 77, ax=5.0, lo=6)
    stone = stone * (0.72 + 0.34 * rough_n + 0.2 * strat)[..., None]
    dome = smooth(edge, 2.0, 16.0)
    height = (1 - mortar) * (0.45 + 0.4 * dome + 0.18 * (r2 - 0.5) + 0.2 * (rough_n - 0.5)) + mortar * 0.25
    mort_col = mix(col('5f584a'), col('7d7563'), fbm(shape, 1.5, 78)[..., None])
    rgb = mix(stone, mort_col, mortar[..., None])
    rgb = rgb * np.clip(1.0 - cavity(height, 3.0) * 1.8, 0.5, 1.3)[..., None]
    moss = smooth(fbm(shape, 2.0, 79), 0.55, 0.8) * smooth(mortar + cavity(height, 4.0) * 2.5, 0.2, 0.7)
    rgb = mix(rgb, col('56603a'), (moss * 0.6)[..., None])
    lichen = lichen_blobs(shape, 80, 0.6) * (1 - mortar)
    rgb = mix(rgb, col('b4b094'), (lichen * 0.5)[..., None])
    rgb = rgb * (0.88 + 0.2 * fbm(shape, 2.3, 81))[..., None]
    rgb = painterly(rgb, 0.35, 82)
    out('stone', rgb, normal_from_height(height, 5.5))


def tex_concrete():
    shape = (N, N)
    x, y = grid(shape)
    big = fbm(shape, 2.2, 91)
    mid = fbm(shape, 1.3, 92, lo=6)
    rgb = mix(col('86837a'), col('a9a598'), smooth(big * 0.6 + mid * 0.4, 0.2, 0.85)[..., None])
    board = np.abs(((y / 40.0) % 1.0) - 0.5) * 2  # shutter-board lines every 0.2 m
    line = smooth(board, 0.9, 1.0)
    grainb = fbm(shape, 1.2, 93, ax=12.0, lo=6)
    rgb = rgb * (0.94 + 0.1 * grainb)[..., None] * (1 - 0.18 * line)[..., None]
    pits = speckle(shape, 94, 0.0025, 1.1) * smooth(fbm(shape, 1.8, 940), 0.3, 0.7)
    agg = fbm(shape, 0.3, 95, lo=40)
    rgb = rgb * (1 - 0.4 * pits)[..., None] * (0.95 + 0.1 * agg)[..., None]
    cr = cracks(shape, 96, 0.007)
    rgb = mix(rgb, col('45423b'), (cr * 0.7)[..., None])
    stain = smooth(fbm(shape, 2.0, 97, ax=0.5, ay=2.5), 0.55, 0.9)
    rgb = mix(rgb, col('6b6657'), (stain * 0.45)[..., None])
    rgb = mix(rgb, col('5d6642'), (smooth(fbm(shape, 2.0, 98), 0.68, 0.9) * 0.3)[..., None])
    height = 0.6 + 0.12 * (mid - 0.5) + 0.06 * (grainb - 0.5) - 0.2 * line - 0.3 * pits - 0.3 * cr
    rgb = painterly(rgb, 0.35, 99)
    out('concrete', rgb, normal_from_height(height, 3.0))


# --------------------------------------------------------------------------------------------------------------------
# Roofing
# --------------------------------------------------------------------------------------------------------------------
def tex_corrugated():
    """Galvanised corrugated iron: 4 sheets across x 2 rows per tile; V runs down the slope. Alpha = roughness."""
    shape = (N, N)
    x, y = grid(shape)
    sheet_w, sheet_h = N / 4.0, N / 2.0
    srow = np.floor(y / sheet_h).astype(np.int32)
    phase = (cell_rand(0, srow, 101, period_y=2) - 0.5) * 9.0
    xs = x + phase
    scol = np.floor(xs / sheet_w).astype(np.int32)
    fx = xs - scol * sheet_w
    fy = y - srow * sheet_h
    scolm = np.mod(scol, 4)
    period = N / 24.0
    corr = 0.5 + 0.5 * np.cos(2 * np.pi * xs / period)
    r1 = cell_rand(scolm, srow, 102, 4, 2)
    r2 = cell_rand(scolm, srow, 103, 4, 2)
    blot = fbm(shape, 1.8, 104)
    spang = fbm(shape, 0.6, 105, lo=18)
    zinc = mix(col('7b827d'), col('a2a8a1'), smooth(blot * 0.6 + r1 * 0.4, 0.1, 0.9)[..., None])
    zinc = zinc * (0.94 + 0.1 * spang)[..., None]
    # rust: sheet ends (above the lap), side laps, random blooms, all dragged down-slope
    end_rust = smooth(fy, sheet_h * 0.72, sheet_h) * 0.5 + smooth(fy, sheet_h * 0.1, 0) * 0.15
    side_rust = smooth(np.minimum(fx, sheet_w - fx), 9, 0) * 0.3
    bloom = fbm(shape, 1.9, 106, ax=0.6, ay=2.2, lo=2)
    drag = fbm(shape, 1.2, 107, ax=0.2, ay=8.0, lo=8)
    rv = bloom * 0.62 + drag * 0.28 + end_rust + side_rust + (r2 - 0.5) * 0.42 + (1 - corr) * 0.05
    rust = smooth(rv, 0.74, 0.92)
    rust_heavy = smooth(rv, 0.92, 1.12)
    rust_col = mix(col('8a5632'), col('6a3d26'), fbm(shape, 1.2, 108, lo=5)[..., None])
    rgb = mix(zinc, rust_col, rust[..., None] * 0.85)
    rgb = mix(rgb, col('4f2f20'), rust_heavy[..., None] * 0.7)
    # nail rows with halos and drips
    nail = np.zeros(shape, np.float32)
    crest = np.abs(((xs / period + 0.5) % 2.0) - 1.0) * period  # every second crest
    for ny in (sheet_h * 0.12, sheet_h * 0.55, sheet_h * 0.93):
        dn = np.sqrt(crest ** 2 + (fy - ny) ** 2)
        nail = np.maximum(nail, np.clip(1.0 - dn / 2.0, 0, 1))
    halo = np.clip(blur(nail, 2.2) * 5, 0, 1)
    drip = np.clip(ndimage.gaussian_filter(np.roll(nail, 12, 0), (12, 1.3), mode='wrap') * 14, 0, 1)
    rgb = mix(rgb, col('7e4e2e'), (np.clip(halo + drip * 0.8, 0, 1) * 0.55)[..., None])
    rgb = mix(rgb, col('3c3a36'), nail[..., None] * 0.9)
    # lap edges
    lap_edge = smooth(fy, 3.5, 0.0)          # lower sheet tucked under the one above: shadow just below the lap
    lap_lip = smooth(fy, sheet_h - 2.5, sheet_h)  # bright lip of the upper sheet's lower edge
    side = smooth(fx, 2.0, 0.0)
    rgb = rgb * (1 - 0.5 * lap_edge)[..., None] * (1 + 0.12 * lap_lip)[..., None] * (1 - 0.3 * side)[..., None]
    dirt = fbm(shape, 2.0, 109, ay=2.0)
    rgb = rgb * (0.74 + 0.26 * corr * (0.6 + 0.4 * dirt) + 0.1 * dirt)[..., None]
    moss = smooth(fbm(shape, 2.1, 110), 0.7, 0.9) * (1 - corr) * 0.5
    rgb = mix(rgb, col('5a6140'), moss[..., None])
    dents = (fbm(shape, 2.0, 111, lo=3) - 0.5) * 0.25
    height = corr * 0.8 + dents + (fy / sheet_h) * 0.25 + nail * 0.15 - rust_heavy * 0.05
    rough = 0.48 + 0.42 * rust + 0.15 * (1 - corr) * dirt + 0.1 * moss
    rgb = painterly(rgb, 0.3, 112)
    out('corrugated', rgb, normal_from_height(height, 7.0), rough=rough)


def shingle_layout(shape, rows, per_row, seed, slip=0.0):
    h, w = shape
    x, y = grid(shape)
    rh = h / rows
    tw = w / per_row
    row0 = np.floor(y / rh).astype(np.int32)
    # per tile vertical slip (a few px) for irregular courses
    def lay(rowi):
        off = np.where(rowi % 2 == 1, tw * 0.5, 0.0) + (cell_rand(0, rowi, seed, period_y=rows) - 0.5) * tw * 0.2
        ti = np.floor((x + off) / tw).astype(np.int32)
        fx = (x + off) - ti * tw
        return ti, fx
    ti, fx = lay(row0)
    tim = np.mod(ti, per_row)
    s = (cell_rand(tim, np.mod(row0, rows), seed + 1) - 0.5) * 2 * slip
    y2 = y - s
    row = np.floor(y2 / rh).astype(np.int32)
    ti, fx = lay(row)
    tim = np.mod(ti, per_row)
    rowm = np.mod(row, rows)
    fy = (y2 / rh) - row
    return dict(x=x, y=y, row=rowm, col=tim, fx=fx / tw, fy=fy, rh=rh, tw=tw)


def tex_rooftile():
    """Weathered clay plain tiles, 16 courses x 12 tiles per 2.56 m. V runs down the slope (eave at the bottom)."""
    shape = (N, N)
    L = shingle_layout(shape, 16, 12, 121, slip=1.6)
    r1 = cell_rand(L['col'], L['row'], 122)
    r2 = cell_rand(L['col'], L['row'], 123)
    r3 = cell_rand(L['col'], L['row'], 124)
    base = mix(col('8c5640'), col('a26a4c'), r1[..., None])
    base = mix(base, col('75493b'), smooth(r2, 0.45, 0.9)[..., None] * 0.9)
    base = mix(base, col('5c443c'), (r3 > 0.86).astype(np.float32)[..., None] * 0.8)
    base = mix(base, col('b08460'), (r3 < 0.04).astype(np.float32)[..., None] * 0.7)
    sand = fbm(shape, 0.7, 125, lo=16)
    base = base * (0.86 + 0.24 * sand)[..., None]
    side = np.minimum(L['fx'], 1 - L['fx']) * L['tw']
    joint = smooth(side, 1.6, 0.4)
    top_shadow = smooth(L['fy'] * L['rh'], 5.0, 0.0)       # tucked under the course above
    lip = smooth(L['fy'], 0.86, 1.0)
    corner = smooth(side, 4.0, 0.0) * smooth(L['fy'], 0.8, 1.0)  # rounded lower corners
    height = L['fy'] * 0.75 + (r2 - 0.5) * 0.22 + 0.08 * (sand - 0.5)
    height = height * (1 - 0.7 * joint) - corner * 0.3
    rgb = base * (1 - 0.5 * top_shadow)[..., None] * (1 + 0.1 * lip)[..., None] * (0.86 + 0.2 * L['fy'])[..., None]
    rgb = mix(rgb, col('2b211c'), (np.clip(joint + corner * 0.8, 0, 1) * 0.8)[..., None])
    weather = fbm(shape, 2.0, 126, ay=1.8)
    rgb = mix(rgb, col('5a4c44'), (smooth(weather, 0.35, 0.85) * 0.55)[..., None])
    streak = fbm(shape, 1.3, 127, ax=0.25, ay=7.0, lo=6)
    rgb = rgb * (0.86 + 0.2 * streak)[..., None]
    moss_m = smooth(fbm(shape, 2.1, 128), 0.6, 0.82)
    moss = moss_m * smooth(top_shadow + joint + fbm(shape, 0.9, 129, lo=12) * 0.6, 0.45, 0.9)
    rgb = mix(rgb, col('566038'), (moss * 0.8)[..., None])
    lichen = lichen_blobs(shape, 130, 0.8)
    rgb = mix(rgb, col('a9a482'), (lichen * 0.6)[..., None])
    rgb = painterly(rgb, 0.3, 131)
    out('rooftile', rgb, normal_from_height(height + moss * 0.1, 5.5))


def tex_slate():
    """Welsh-style slates, 12 courses x 8 per 2.56 m, a little sheen. Alpha = roughness."""
    shape = (N, N)
    L = shingle_layout(shape, 12, 8, 141, slip=2.2)
    r1 = cell_rand(L['col'], L['row'], 142)
    r2 = cell_rand(L['col'], L['row'], 143)
    r3 = cell_rand(L['col'], L['row'], 144)
    base = mix(col('4c5660'), col('66707a'), r1[..., None])
    base = mix(base, col('5f5c68'), smooth(r2, 0.6, 0.95)[..., None] * 0.6)
    base = mix(base, col('5c665f'), (r3 > 0.86).astype(np.float32)[..., None] * 0.5)
    base = mix(base, col('40464d'), (r3 < 0.1).astype(np.float32)[..., None] * 0.7)
    cleave = fbm(shape, 1.3, 145, ax=0.3, ay=5.0, lo=5)
    flake = fbm(shape, 1.6, 146, lo=4)
    base = base * (0.84 + 0.18 * cleave + 0.1 * flake)[..., None]
    side = np.minimum(L['fx'], 1 - L['fx']) * L['tw']
    joint = smooth(side, 1.3, 0.3)
    top_shadow = smooth(L['fy'] * L['rh'], 4.0, 0.0)
    lip = smooth(L['fy'], 0.93, 1.0)
    chip = smooth(side, 7.0, 0.0) * smooth(L['fy'], 0.78, 1.0) * (r2 > 0.6)
    height = L['fy'] * 0.5 + (r2 - 0.5) * 0.16 + 0.1 * (cleave - 0.5)
    height = height * (1 - 0.7 * joint) - chip * 0.3
    rgb = base * (1 - 0.5 * top_shadow)[..., None] * (1 + 0.16 * lip)[..., None] * (0.9 + 0.14 * L['fy'])[..., None]
    rgb = mix(rgb, col('1f2226'), (np.clip(joint + chip, 0, 1) * 0.8)[..., None])
    # rusty nail weeps, pale lichen, green in the laps
    weep = smooth(fbm(shape, 1.2, 147, ax=0.2, ay=7.0, lo=7), 0.72, 0.92) * smooth(fbm(shape, 2.0, 148), 0.5, 0.8)
    rgb = mix(rgb, col('7a5a40'), (weep * 0.4)[..., None])
    lichen = lichen_blobs(shape, 149, 0.7)
    rgb = mix(rgb, col('aeb0a0'), (lichen * 0.5)[..., None])
    moss = smooth(fbm(shape, 2.1, 150), 0.62, 0.85) * smooth(top_shadow + joint, 0.3, 0.9)
    rgb = mix(rgb, col('4f5b3c'), (moss * 0.7)[..., None])
    dust = fbm(shape, 2.2, 151)
    rgb = rgb * (0.88 + 0.2 * dust)[..., None]
    rough = 0.52 + 0.2 * dust + 0.3 * lichen + 0.3 * moss + 0.15 * joint
    rgb = painterly(rgb, 0.3, 152)
    out('slate', rgb, normal_from_height(height, 4.5), rough=rough)


# --------------------------------------------------------------------------------------------------------------------
# Fabric, metal, rubber
# --------------------------------------------------------------------------------------------------------------------
def tex_canvas():
    """Proofed canvas / tarpaulin: calm drab khaki, soft drawn wrinkles, faint stains, stitched seams every 1.28 m."""
    shape = (N, N)
    x, y = grid(shape)
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * x / 3.2) + 0.25 * np.sin(2 * np.pi * y / 3.2)
    big = norm01(blur(fbm(shape, 2.8, 161, lo=1), 10))
    # wrinkles pulled across the cloth (long in x) plus a weaker set the other way
    wr_a = fbm(shape, 2.2, 162, ax=5.0, ay=1.0, lo=2, hi=40)
    wr_b = fbm(shape, 2.2, 163, ax=1.0, ay=4.0, lo=2, hi=28)
    billow = blur(fbm(shape, 2.4, 167, lo=1.5, hi=8), 3)
    relief = 0.55 * (wr_a - 0.5) + 0.3 * (wr_b - 0.5) + 0.45 * (billow - 0.5)
    height = 0.5 + relief + 0.02 * weave
    base = mix(col('77735e'), col('8b866e'), smooth(big, 0.1, 0.9)[..., None])
    base = base * (0.95 + 0.07 * weave)[..., None]
    rgb = base * (1.0 + 0.22 * relief)[..., None]                    # ridges rub pale, hollows hold dirt
    stain = smooth(blur(fbm(shape, 2.4, 164, lo=1.5), 4), 0.6, 0.9)
    rgb = mix(rgb, col('5e5a4a'), (stain * 0.3)[..., None])
    run = fbm(shape, 1.4, 165, ax=0.3, ay=7.0, lo=5)
    rgb = rgb * (0.94 + 0.1 * run)[..., None]
    sx = np.abs(((x + 128) % 256.0) - 128.0)
    seam = smooth(sx, 6.0, 4.0)
    stitch = (smooth(np.abs(sx - 4.0), 1.0, 0.3)) * (((y / 5.0) % 1.0) < 0.6)
    rgb = rgb * (1 - 0.14 * seam)[..., None]
    rgb = mix(rgb, col('b3ad94'), (stitch * 0.45)[..., None])
    height = height + seam * 0.05
    rgb = painterly(rgb, 0.3, 166)
    out('canvas', rgb, normal_from_height(height, 6.0))


def tex_burlap():
    """Hessian sandbag cloth, 256 px. One bag = one tile: stitched seams near the U ends, dirt in the creases."""
    n = 256
    shape = (n, n)
    x, y = grid(shape)
    wx = 0.5 + 0.5 * np.sin(2 * np.pi * x / 4.0)
    wy = 0.5 + 0.5 * np.sin(2 * np.pi * y / 4.0)
    tx = cell_rand(np.floor(x / 4.0), 0, 171)
    ty = cell_rand(0, np.floor(y / 4.0), 172)
    over = ((np.floor(x / 4.0) + np.floor(y / 4.0)) % 2) == 0
    weave = np.where(over, wx * (0.7 + 0.3 * tx), wy * (0.7 + 0.3 * ty))
    big = fbm(shape, 2.2, 173)
    base = mix(col('8b7f64'), col('aca084'), smooth(big, 0.2, 0.85)[..., None])
    rgb = base * (0.72 + 0.36 * weave)[..., None]
    dirt = smooth(fbm(shape, 1.9, 174), 0.5, 0.85)
    rgb = mix(rgb, col('665c4a'), (dirt * 0.55)[..., None])
    sx = np.minimum(x, n - x)
    seam = smooth(sx, 13.0, 9.0) * smooth(sx, 5.0, 9.0)
    stitch = seam * (((y / 6.0) % 1.0) < 0.55)
    rgb = rgb * (1 - 0.25 * seam)[..., None]
    rgb = mix(rgb, col('d0c4a0'), (stitch * 0.5)[..., None])
    height = 0.5 + 0.22 * (weave - 0.5) + 0.3 * (big - 0.5) - 0.2 * seam
    rgb = painterly(rgb, 0.2, 175)
    Image.fromarray(to8(rgb)).save(os.path.join(OUT, 'burlap_a.png'), optimize=True)
    save_normal(os.path.join(OUT, 'burlap_n.png'), normal_from_height(height, 4.0))
    print('wrote burlap')


def tex_steel():
    """Drab painted steel with chips, scratches and rust. Kept light and fairly neutral so vertex colour tints it.
    Alpha = roughness."""
    shape = (N, N)
    big = fbm(shape, 2.2, 181)
    mid = fbm(shape, 1.3, 182, lo=6)
    paint = mix(col('9a9c86'), col('b6b79f'), smooth(big * 0.65 + mid * 0.35, 0.2, 0.85)[..., None])
    brush = fbm(shape, 0.9, 183, ax=6.0, lo=14)
    paint = paint * (0.95 + 0.08 * brush)[..., None]
    chip_n = fbm(shape, 1.4, 184, lo=5) * 0.6 + fbm(shape, 0.7, 185, lo=20) * 0.4
    chip = smooth(chip_n, 0.71, 0.74)
    chip_rim = smooth(chip_n, 0.685, 0.71) * (1 - chip)
    rust_n = fbm(shape, 1.9, 186, lo=2) * 0.7 + fbm(shape, 1.0, 187, lo=9) * 0.3
    rust = smooth(rust_n, 0.66, 0.8)
    run = np.clip(ndimage.gaussian_filter(np.roll(chip, 10, 0), (10, 1.0), mode='wrap') * 2.2, 0, 1)
    scratch = 1.0 - np.clip(np.abs(fbm(shape, 1.6, 188, ax=9.0, ay=0.6, lo=4) - 0.5) / 0.004, 0, 1)
    scratch2 = 1.0 - np.clip(np.abs(fbm(shape, 1.6, 189, ax=0.7, ay=7.0, lo=4) - 0.5) / 0.004, 0, 1)
    sc = np.clip(scratch + scratch2, 0, 1) * smooth(fbm(shape, 2.0, 190), 0.4, 0.7)
    rgb = mix(paint, col('7a5236'), (rust * 0.7)[..., None])
    rgb = mix(rgb, col('86573a'), (run * 0.4)[..., None])
    rgb = mix(rgb, col('4a3a30'), chip[..., None] * 0.92)
    rgb = mix(rgb, np.clip(paint * 1.2, 0, 1), chip_rim[..., None] * 0.6)
    rgb = mix(rgb, col('c9c9b6'), (sc * 0.35)[..., None])
    dust = fbm(shape, 2.3, 191)
    rgb = rgb * (0.86 + 0.2 * dust)[..., None]
    height = 0.6 + 0.05 * (brush - 0.5) - 0.2 * chip - 0.08 * rust * fbm(shape, 0.8, 192, lo=14) - 0.05 * sc
    rough = 0.55 + 0.35 * rust + 0.3 * chip + 0.1 * dust - 0.1 * sc
    rgb = painterly(rgb, 0.3, 193)
    out('steel', rgb, normal_from_height(height, 2.5), rough=rough)


def tex_rubber():
    """Tyre: U runs round the circumference (tiles), V across the profile: sidewall / tread / sidewall."""
    n = 256
    shape = (n, n)
    x, y = grid(shape)
    v = y / n
    tread_zone = smooth(v, 0.28, 0.33) * smooth(v, 0.72, 0.67)
    # chevron lug pattern
    cx = (x + np.abs(v - 0.5) * n * 0.9) % 32.0
    lug = smooth(np.abs(cx - 16.0), 11.0, 8.0)
    centre_rib = smooth(np.abs(v - 0.5), 0.035, 0.02)
    tread = np.clip(lug + centre_rib, 0, 1) * tread_zone
    rings = 0.5 + 0.5 * np.cos(2 * np.pi * v * 22.0)
    side_h = (1 - tread_zone) * (0.35 + 0.05 * rings)
    height = tread * 0.9 + side_h
    dust = fbm(shape, 1.9, 201)
    base = mix(col('26272a'), col('3a3a3a'), dust[..., None])
    rgb = base * (0.7 + 0.5 * height)[..., None]
    mud = smooth(fbm(shape, 1.8, 202), 0.45, 0.8) * (0.4 + 0.6 * (1 - tread) * tread_zone + 0.3 * (1 - tread_zone))
    rgb = mix(rgb, col('5a5042'), (mud * 0.35)[..., None])
    rgb = painterly(rgb, 0.2, 203)
    Image.fromarray(to8(rgb)).save(os.path.join(OUT, 'rubber_a.png'), optimize=True)
    save_normal(os.path.join(OUT, 'rubber_n.png'), normal_from_height(height, 6.0))
    print('wrote rubber')



# --------------------------------------------------------------------------------------------------------------------
# Atlas helpers
# --------------------------------------------------------------------------------------------------------------------
class Canvas:
    """A sub-rectangle of an atlas being painted: rgb, height and roughness layers plus PIL-drawn masks."""

    def __init__(self, w, h, seed):
        self.w, self.h, self.seed = w, h, seed
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.height = np.zeros((h, w), np.float32)
        self.rough = np.full((h, w), 0.85, np.float32)

    def mask(self, draw_fn, ss=3):
        """draw_fn(ImageDraw, scale) paints white on black; returns an anti-aliased float mask."""
        im = Image.new('L', (self.w * ss, self.h * ss), 0)
        draw_fn(ImageDraw.Draw(im), ss)
        return np.asarray(im.resize((self.w, self.h), Image.LANCZOS), np.float32) / 255.0

    def rect(self, x0, y0, x1, y1):
        return self.mask(lambda d, s: d.rectangle([x0 * s, y0 * s, x1 * s - 1, y1 * s - 1], fill=255))

    def poly(self, pts):
        return self.mask(lambda d, s: d.polygon([(x * s, y * s) for x, y in pts], fill=255))

    def line(self, pts, width):
        return self.mask(lambda d, s: d.line([(x * s, y * s) for x, y in pts], fill=255, width=int(width * s), joint='curve'))

    def ellipse(self, x0, y0, x1, y1):
        return self.mask(lambda d, s: d.ellipse([x0 * s, y0 * s, x1 * s, y1 * s], fill=255))

    def put(self, m, rgb, height=None, rough=None, shadow=0.0):
        """Composite a layer through mask m. shadow > 0 drops a soft contact shadow around the shape first."""
        if shadow > 0:
            sh = np.clip(blur(m, shadow, False) * 1.3 - m, 0, 1)
            self.rgb *= (1 - 0.5 * sh)[..., None]
        self.rgb = mix(self.rgb, rgb, m[..., None])
        if height is not None:
            self.height = mix(self.height, height, m)
        if rough is not None:
            self.rough = mix(self.rough, rough, m)


def wood_patch(w, h, seed, vertical=False, board=32, tone=(0.75, 1.1), base=('b9a680', '9a927f', '665743')):
    """Boards with grain; returns rgb, height. vertical=True runs the boards up the patch."""
    if vertical:
        rgb, hh = wood_patch(h, w, seed, False, board, tone, base)
        return np.rot90(rgb).copy(), np.rot90(hh).copy()
    shape = (h, w)
    rows = max(1, int(round(h / board)))
    wr = wood_rows(shape, seed, rows, joint_every=max(8, w * 4))
    g = np.clip(wr['grain'] * 0.75 + wr['fine'] * 0.35, 0, 1)
    b = mix(col(base[0]), col(base[1]), wr['hue'][..., None])
    rgb = mix(col(base[2]), b, smooth(g, 0.12, 0.8)[..., None])
    rgb = rgb * (tone[0] + (tone[1] - tone[0]) * cell_rand(wr['row'], 3, seed + 9))[..., None]
    gap = np.clip(1.0 - np.minimum(wr['fy'], 1 - wr['fy']) * wr['rh'] / 1.3, 0, 1) if rows > 1 else np.zeros(shape, np.float32)
    hh = (0.6 + 0.14 * (g - 0.5)) * (1 - gap)
    rgb = mix(rgb, col('1e1a15'), (gap * 0.85)[..., None])
    return rgb.astype(np.float32), hh.astype(np.float32)


def peel_paint(under, colour, seed, amount=0.5, low_bias=0.25):
    """Flaking paint over a surface: returns rgb and the paint mask."""
    h, w = under.shape[:2]
    _, y = grid((h, w))
    n = fbm((h, w), 1.8, seed, lo=2) * 0.6 + fbm((h, w), 0.9, seed + 1, lo=8) * 0.4
    v = n + smooth(y, h * 0.6, h) * low_bias
    peel = smooth(v, 0.78 - amount * 0.3, 0.81 - amount * 0.3)
    rim = smooth(v, 0.74 - amount * 0.3, 0.78 - amount * 0.3) * (1 - peel)
    c = col(colour) * (0.86 + 0.22 * fbm((h, w), 2.0, seed + 2))[..., None]
    c = c * (0.94 + 0.08 * fbm((h, w), 0.8, seed + 3, ax=1, ay=8, lo=10))[..., None]
    rgb = mix(c, under, peel[..., None])
    rgb = mix(rgb, np.clip(c * 1.2, 0, 1), (rim * 0.6)[..., None])
    return rgb, 1 - peel


def iron_patch(w, h, seed):
    shape = (h, w)
    n = fbm(shape, 1.8, seed)
    rgb = mix(col('2e2c2a'), col('4a4640'), n[..., None])
    rust = smooth(fbm(shape, 1.5, seed + 1, lo=3), 0.5, 0.8)
    return mix(rgb, col('6d4630'), (rust * 0.6)[..., None])


def glass_patch(w, h, seed):
    """Dirty pane: dark interior, a soft sky sheen, dust in the corners. Returns rgb, roughness."""
    shape = (h, w)
    x, y = grid(shape)
    sheen = smooth(1.0 - (x / w * 0.6 + y / h * 0.8), 0.1, 0.9)
    rgb = mix(col('1f2a2c'), col('5d7078'), (sheen * 0.75)[..., None])
    dust = fbm(shape, 2.0, seed)
    edge = np.minimum(np.minimum(x, w - x), np.minimum(y, h - y))
    grime = np.clip(smooth(edge, min(w, h) * 0.3, 0) * 0.8 + smooth(dust, 0.5, 0.9) * 0.5, 0, 1)
    rgb = mix(rgb, col('7b7a66'), (grime * 0.6)[..., None])
    streak = fbm(shape, 1.2, seed + 1, ax=0.2, ay=6.0, lo=5)
    rgb = rgb * (0.9 + 0.2 * streak)[..., None]
    return rgb, 0.12 + 0.6 * grime


def stencil_mask(text, px, pad=2):
    """Bold condensed lettering with stencil bridges cut where a glyph's centre column crosses a counter."""
    font = ImageFont.truetype(FONT_BOLD, px)
    x0, y0, x1, y1 = font.getbbox(text)
    w, h = x1 - x0 + pad * 2, y1 - y0 + pad * 2
    im = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(im)
    d.text((pad - x0, pad - y0), text, font=font, fill=255)
    a = np.asarray(im, np.float32) / 255.0
    cx = pad
    gap = max(2, px // 14)
    for ch in text:
        adv = font.getlength(ch)
        if ch.strip():
            g0, _, g1, _ = font.getbbox(ch)
            mid = int(round(cx + (g0 + g1) * 0.5))
            colm = a[:, min(max(mid, 0), w - 1)] > 0.5
            runs = int(np.sum(colm[1:] & ~colm[:-1]) + (1 if colm[0] else 0))
            if runs >= 2 and (g1 - g0) > px * 0.34:
                a[:, max(0, mid - gap // 2):mid + (gap + 1) // 2] = 0
        cx += adv
    return a


def place(dst, src, cx, cy):
    """Paste mask src centred at (cx, cy) into an empty mask the size of dst (clipped)."""
    out_m = np.zeros(dst, np.float32)
    h, w = src.shape
    x0, y0 = int(round(cx - w / 2)), int(round(cy - h / 2))
    xs0, ys0 = max(0, -x0), max(0, -y0)
    xe, ye = min(w, dst[1] - x0), min(h, dst[0] - y0)
    if xe > xs0 and ye > ys0:
        out_m[y0 + ys0:y0 + ye, x0 + xs0:x0 + xe] = src[ys0:ye, xs0:xe]
    return out_m


def worn(mask, seed, amount=0.45):
    """Break up a painted marking so it looks brushed through a stencil and weathered."""
    n = fbm(mask.shape, 1.3, seed, lo=5) * 0.6 + fbm(mask.shape, 0.6, seed + 1, lo=20) * 0.4
    return mask * smooth(n, amount - 0.12, amount + 0.12)


# --------------------------------------------------------------------------------------------------------------------
# Crate atlas: 2 x 2 cells of 256 px (see CRATE_CELLS in structures_kit.gd)
#   (0,0) braced side   (1,0) stencilled side   (0,1) lid   (1,1) end with rope handle
# --------------------------------------------------------------------------------------------------------------------
def crate_cell(kind, seed):
    n = 256
    c = Canvas(n, n, seed)
    vertical = kind == 'end'
    rgb, hh = wood_patch(n, n, seed, vertical=vertical, board=51 if kind != 'lid' else 43, base=('c2aa7c', 'a89a7e', '6f5c42'))
    c.rgb, c.height = rgb, hh * 0.55
    brgb_h, bh_h = wood_patch(n, n, seed + 20, False, 300, base=('cdb688', 'b3a486', '7a6548'))
    brgb_v, bh_v = wood_patch(n, n, seed + 21, True, 300, base=('cdb688', 'b3a486', '7a6548'))
    bw = 26

    def batten(m, vert):
        c.put(m, brgb_v if vert else brgb_h, (bh_v if vert else bh_h) * 0.3 + 0.75, shadow=3.5)

    nails = []
    if kind in ('braced', 'stencil', 'end'):
        if kind == 'braced':
            d = 21
            batten(c.poly([(bw, n - bw - d * 0.2), (bw + d, n - bw), (n - bw, bw + d * 0.2), (n - bw - d, bw)]), False)
        batten(c.rect(0, 0, n, bw), False)
        batten(c.rect(0, n - bw, n, n), False)
        batten(c.rect(0, 0, bw, n), True)
        batten(c.rect(n - bw, 0, n, n), True)
        for t in np.linspace(0.12, 0.88, 6):
            nails += [(bw / 2, t * n), (n - bw / 2, t * n), (t * n, bw / 2), (t * n, n - bw / 2)]
    else:
        for yb in (46, n - 46 - bw):
            batten(c.rect(0, yb, n, yb + bw), False)
            nails += [(t * n, yb + bw / 2) for t in np.linspace(0.08, 0.92, 7)]
    ink = col('2c2e26')
    if kind == 'stencil':
        m = place((n, n), stencil_mask('No 47', 44), n * 0.5, n * 0.36)
        m += place((n, n), stencil_mask('12', 34), n * 0.3, n * 0.68)
        arrow = c.poly([(170, 205), (170, 165), (155, 165), (182, 132), (209, 165), (194, 165), (194, 205)])
        m = np.clip(m + arrow, 0, 1)
        c.rgb = mix(c.rgb, ink, (worn(m, seed + 30, 0.33) * 0.85)[..., None])
    elif kind == 'braced':
        m = place((n, n), stencil_mask('B 3', 30), n * 0.34, n * 0.26)
        c.rgb = mix(c.rgb, ink, (worn(m, seed + 30, 0.33) * 0.8)[..., None])
    elif kind == 'lid':
        m = place((n, n), stencil_mask('214', 36), n * 0.5, n * 0.5)
        band = c.rect(40, n * 0.5 - 30, 48, n * 0.5 + 30) + c.rect(n - 48, n * 0.5 - 30, n - 40, n * 0.5 + 30)
        c.rgb = mix(c.rgb, ink, (worn(np.clip(m + band, 0, 1), seed + 30, 0.33) * 0.8)[..., None])
    elif kind == 'end':
        # rope handle: a loop through two holes under a cleat
        loop = c.line([(84, 118), (92, 160), (128, 172), (164, 160), (172, 118)], 9)
        rope_tex = 0.75 + 0.25 * np.sin((grid((n, n))[0] + grid((n, n))[1]) * 1.9)
        c.put(loop, col('b5a37a')[None, None, :] * rope_tex[..., None], 0.95, shadow=3.0)
        batten(c.rect(64, 96, 192, 96 + 22), False)
        nails += [(74, 107), (182, 107), (128, 107)]
        m = place((n, n), stencil_mask('7', 40), n * 0.5, n * 0.78)
        c.rgb = mix(c.rgb, ink, (worn(m, seed + 30, 0.33) * 0.8)[..., None])
    for nx, ny in nails:
        m = c.ellipse(nx - 2.2, ny - 2.2, nx + 2.2, ny + 2.2)
        c.put(m, col('2a2622'), 0.95)
        c.rgb = mix(c.rgb, col('6f4a30'), (np.clip(blur(m, 2.5, False) * 3, 0, 1) * 0.35)[..., None])
    dirt = fbm((n, n), 2.0, seed + 40)
    _, y = grid((n, n))
    c.rgb *= (0.84 + 0.22 * dirt)[..., None]
    if kind != 'lid':
        c.rgb = mix(c.rgb, col('5d5038'), (smooth(y, n * 0.72, n) * 0.4 * (0.5 + dirt))[..., None])
    c.rgb *= np.clip(1.0 - cavity(c.height, 2.5, False) * 1.5, 0.5, 1.2)[..., None]
    return c


def tex_crate():
    rgb = np.zeros((N, N, 3), np.float32)
    hh = np.zeros((N, N), np.float32)
    for i, kind in enumerate(['braced', 'stencil', 'lid', 'end']):
        c = crate_cell(kind, 300 + i * 50)
        x0, y0 = (i % 2) * 256, (i // 2) * 256
        rgb[y0:y0 + 256, x0:x0 + 256] = c.rgb
        hh[y0:y0 + 256, x0:x0 + 256] = c.height
    rgb = painterly(rgb, 0.3, 399)
    nrm = np.zeros((N, N, 3), np.float32)
    for i in range(4):  # per-cell normals so cells do not bleed gradients into each other
        x0, y0 = (i % 2) * 256, (i // 2) * 256
        nrm[y0:y0 + 256, x0:x0 + 256] = normal_from_height(hh[y0:y0 + 256, x0:x0 + 256], 5.0, False, False)
    out('crate', rgb, nrm)



# --------------------------------------------------------------------------------------------------------------------
# Trim sheet 1024 x 1024: signs, doors, windows, shutters and small fittings. Alpha = roughness.
# The rectangles below are mirrored in TRIM in structures_kit.gd - keep both in step.
# --------------------------------------------------------------------------------------------------------------------
TRIM = {
    'sign0': (0, 0, 512, 112), 'sign1': (0, 112, 512, 112), 'sign2': (0, 224, 512, 112),
    'plate_arrow': (0, 336, 128, 88), 'plate_no': (128, 336, 128, 88), 'plate_warn': (256, 336, 128, 88),
    'plate_blank': (384, 336, 128, 88), 'board_blank': (0, 424, 512, 88),
    'door_plank': (512, 0, 256, 512), 'door_glazed': (768, 0, 256, 512), 'slide_door': (0, 512, 320, 512),
    'window_a': (320, 512, 256, 256), 'window_b': (576, 512, 256, 256), 'shutter': (832, 512, 96, 256),
    'vent': (928, 512, 96, 96), 'lock': (928, 608, 96, 96), 'tabletop': (320, 768, 256, 256),
    'grille': (576, 768, 128, 192), 'lens': (704, 768, 64, 64), 'glass': (704, 832, 64, 64),
    'drum_lid': (768, 768, 128, 128), 'cable_drum': (768, 896, 128, 128), 'panel': (896, 768, 128, 128),
    'blanket': (896, 896, 128, 128),
}


def mission_labels():
    return list(SIGN_LABELS)


def finish(c, seed, dirt_amt=0.2, cav=1.4):
    d = fbm((c.h, c.w), 2.0, seed + 70)
    c.rgb *= (1 - dirt_amt * 0.5 + dirt_amt * d)[..., None]
    c.rgb *= np.clip(1.0 - cavity(c.height, 2.5, False) * cav, 0.5, 1.2)[..., None]
    return c


def trim_sign(text, seed, w=512, h=112):
    c = Canvas(w, h, seed)
    wood, hh = wood_patch(w, h, seed, False, 38, base=('b4a888', '9c9482', '5e5546'))
    board, pm = peel_paint(wood, 'cfc7aa', seed + 1, 0.3, 0.1)
    c.rgb, c.height = board, hh * 0.5 + 0.2 + pm * 0.06
    ink = col('2b3028')
    border = c.rect(7, 7, w - 7, h - 7) - c.rect(12, 12, w - 12, h - 12)
    m = np.clip(border, 0, 1)
    if text:
        px = 74
        while True:
            tm = stencil_mask(text, px)
            if tm.shape[1] <= w - 64 and tm.shape[0] <= h - 36:
                break
            px -= 2
        m = np.clip(m + place((h, w), tm, w / 2, h / 2 + 1), 0, 1)
    c.rgb = mix(c.rgb, ink, (worn(m, seed + 5, 0.25) * pm * 0.92)[..., None])
    for nx in (22, w - 22):
        for ny in (22, h - 22):
            nm = c.ellipse(nx - 3, ny - 3, nx + 3, ny + 3)
            c.put(nm, col('3a322a'), 0.9)
            drip = np.clip(ndimage.gaussian_filter(np.roll(nm, 8, 0), (8, 1.2)) * 8, 0, 1)
            c.rgb = mix(c.rgb, col('7a5236'), (drip * 0.45)[..., None])
    st = top_streaks((h, w), seed + 6, 0.7, 0.5)
    c.rgb = mix(c.rgb, col('5d5a4c'), (st * 0.35)[..., None])
    return finish(c, seed, 0.18)


def trim_plate(kind, seed, w=128, h=88):
    """Small enamelled steel notice plates."""
    c = Canvas(w, h, seed)
    c.rgb[:] = col('c9c2a6')
    c.rgb *= (0.9 + 0.15 * fbm((h, w), 2.0, seed))[..., None]
    c.height[:] = 0.5
    c.rough[:] = 0.5
    ink = col('2b2d27')
    m = c.rect(4, 4, w - 4, h - 4) - c.rect(7, 7, w - 7, h - 7)
    if kind == 'arrow':
        m += c.poly([(22, 36), (74, 36), (74, 22), (106, 44), (74, 66), (74, 52), (22, 52)])
    elif kind == 'no':
        m += place((h, w), stencil_mask('No 4', 36), w / 2, h / 2)
    elif kind == 'warn':
        tri = c.poly([(64, 12), (104, 76), (24, 76)]) - c.poly([(64, 26), (92, 69), (36, 69)])
        m += tri + c.rect(61, 38, 67, 56) + c.ellipse(60, 59, 68, 67)
    c.rgb = mix(c.rgb, ink, (np.clip(m, 0, 1) * 0.92)[..., None])
    chip = smooth(fbm((h, w), 1.3, seed + 1, lo=4), 0.68, 0.72)
    x, y = grid((h, w))
    edge = np.minimum(np.minimum(x, w - x), np.minimum(y, h - y))
    chip = np.clip(chip + smooth(edge, 6, 1) * smooth(fbm((h, w), 1.0, seed + 2, lo=6), 0.4, 0.6), 0, 1)
    c.put(chip, col('5a3a2a'), 0.35, 0.9)
    for nx, ny in ((10, 10), (w - 10, 10), (10, h - 10), (w - 10, h - 10)):
        c.put(c.ellipse(nx - 2.5, ny - 2.5, nx + 2.5, ny + 2.5), col('35302a'), 0.8)
    return finish(c, seed, 0.12, 0.8)


def trim_door_plank(seed, w=256, h=512, paint='4f5c48'):
    c = Canvas(w, h, seed)
    wood, hh = wood_patch(w, h, seed, True, 51)
    rgb, pm = peel_paint(wood, paint, seed + 1, 0.42, 0.3)
    c.rgb, c.height = rgb, hh * 0.6 + pm * 0.05
    frame = c.rect(0, 0, w, h) - c.rect(9, 9, w - 9, h - 4)
    fr, _ = peel_paint(np.rot90(wood_patch(h, w, seed + 3, False, 400)[0]).copy(), 'b9b294', seed + 4, 0.35)
    c.put(np.clip(frame, 0, 1), fr, 0.95, shadow=3.0)
    iron = iron_patch(w, h, seed + 5)
    for hy in (86, 410):
        strap = c.poly([(9, hy - 9), (150, hy - 5), (162, hy), (150, hy + 5), (9, hy + 9)])
        c.put(strap, iron, 0.95, 0.6, shadow=2.5)
        for bx in (24, 70, 120):
            c.put(c.ellipse(bx - 2.5, hy - 2.5, bx + 2.5, hy + 2.5), col('57504a'), 1.0)
    c.put(c.rect(204, 236, 228, 300), iron, 0.9, 0.55, shadow=2.5)
    c.put(c.ellipse(209, 246, 223, 260), col('6b665c'), 1.0, 0.4, shadow=2.0)
    c.put(c.ellipse(213, 276, 219, 286), col('14120f'), 0.6)
    _, y = grid((h, w))
    kick = smooth(y, h * 0.8, h) * (0.5 + fbm((h, w), 1.8, seed + 6))
    c.rgb = mix(c.rgb, col('5c513b'), (np.clip(kick, 0, 1) * 0.6)[..., None])
    st = top_streaks((h, w), seed + 7, 0.3, 0.5)
    c.rgb = mix(c.rgb, col('3c3a30'), (st * 0.4)[..., None])
    return finish(c, seed)


def trim_door_glazed(seed, w=256, h=512, paint='6a4a3c'):
    c = Canvas(w, h, seed)
    wood, hh = wood_patch(w, h, seed, True, 400)
    rgb, pm = peel_paint(wood, paint, seed + 1, 0.3, 0.35)
    c.rgb, c.height = rgb, hh * 0.3 + 0.55
    frame = c.rect(0, 0, w, h) - c.rect(9, 9, w - 9, h - 4)
    fr, _ = peel_paint(np.rot90(wood_patch(h, w, seed + 3, False, 400)[0]).copy(), 'b9b294', seed + 4, 0.35)
    c.put(np.clip(frame, 0, 1), fr, 0.95, shadow=3.0)
    g, gr = glass_patch(w, h, seed + 8)
    for i in range(2):
        for j in range(2):
            x0, y0 = 36 + i * 96, 44 + j * 92
            pane = c.rect(x0, y0, x0 + 86, y0 + 82)
            c.put(pane, np.roll(g, (i * 31, j * 47), (1, 0)), 0.3, np.roll(gr, (i * 31, j * 47), (1, 0)), shadow=0)
            inner_sh = pane * smooth(grid((h, w))[1], y0 + 12, y0)  # shadow of the glazing bar on the glass
            c.rgb *= (1 - 0.35 * inner_sh)[..., None]
    for x0, y0, x1, y1 in ((36, 262, 122, 470), (134, 262, 220, 470)):
        panel = c.rect(x0, y0, x1, y1)
        inner = c.rect(x0 + 8, y0 + 8, x1 - 8, y1 - 8)
        c.height = c.height - 0.3 * (panel - inner) + 0.0
        c.rgb *= (1 - 0.3 * (panel - inner) * smooth(grid((h, w))[1], y0 + 10, y0))[..., None]
        c.rgb *= (1 + 0.08 * inner)[..., None]
    iron = iron_patch(w, h, seed + 5)
    c.put(c.rect(206, 236, 228, 296), iron, 0.9, 0.55, shadow=2.5)
    c.put(c.ellipse(210, 244, 224, 258), col('7d7461'), 1.0, 0.35, shadow=2.0)
    _, y = grid((h, w))
    kick = smooth(y, h * 0.82, h) * (0.5 + fbm((h, w), 1.8, seed + 6))
    c.rgb = mix(c.rgb, col('5c513b'), (np.clip(kick, 0, 1) * 0.6)[..., None])
    return finish(c, seed)


def trim_slide_door(seed, w=320, h=512, paint='59624c'):
    c = Canvas(w, h, seed)
    wood, hh = wood_patch(w, h, seed, True, 40)
    rgb, pm = peel_paint(wood, paint, seed + 1, 0.55, 0.3)
    c.rgb, c.height = rgb, hh * 0.5 + pm * 0.05
    bw = 30
    rail_src, rail_h = wood_patch(w, h, seed + 2, False, 600)
    rail, _ = peel_paint(rail_src, paint, seed + 3, 0.5, 0.2)
    rail = rail * 0.92
    for m in (c.poly([(bw, h - 40), (bw + 30, h - 40), (w - bw, 262), (w - bw - 30, 262)]),
              c.poly([(bw, 250), (bw + 30, 250), (w - bw, 44), (w - bw - 30, 44)]),
              c.rect(0, 30, w, 30 + bw), c.rect(0, 241, w, 241 + bw), c.rect(0, h - 44, w, h - 44 + bw),
              c.rect(0, 30, bw, h - 14), c.rect(w - bw, 30, w, h - 14)):
        c.put(m, rail, rail_h * 0.2 + 0.8, shadow=4.0)
    iron = iron_patch(w, h, seed + 5)
    c.put(c.rect(0, 0, w, 26), iron * 0.9, 0.9, 0.55, shadow=4.0)   # top hanger strap
    for bx in (48, w - 48):
        c.put(c.rect(bx - 16, 0, bx + 16, 62), iron, 0.98, 0.55, shadow=3.0)
        c.put(c.ellipse(bx - 9, 6, bx + 9, 24), col('55504a'), 1.0, 0.45)
        for by in (36, 52):
            c.put(c.ellipse(bx - 3, by - 3, bx + 3, by + 3), col('5a544c'), 1.0)
    c.put(c.rect(w - 24, 250, w - 12, 330), iron, 1.0, 0.5, shadow=3.0)  # pull handle
    num = place((h, w), stencil_mask('2', 84), w * 0.42, 150)
    c.rgb = mix(c.rgb, col('c8c2a4'), (worn(num, seed + 9, 0.4) * 0.7)[..., None])
    _, y = grid((h, w))
    kick = smooth(y, h * 0.8, h) * (0.5 + fbm((h, w), 1.8, seed + 6))
    c.rgb = mix(c.rgb, col('5c513b'), (np.clip(kick, 0, 1) * 0.65)[..., None])
    return finish(c, seed)


def trim_window(seed, variant, n=256):
    c = Canvas(n, n, seed)
    wood, hh = wood_patch(n, n, seed, True, 600)
    fr, pm = peel_paint(wood, 'bdb698', seed + 1, 0.35, 0.3)
    c.rgb, c.height = fr, hh * 0.2 + 0.75
    g, gr = glass_patch(n, n, seed + 2)
    fw, mw = 20, 9
    pw = (n - 2 * fw - mw) / 2.0
    ph = (n - 2 * fw - 2 * mw) / 3.0
    _, y = grid((n, n))
    k = 0
    for i in range(2):
        for j in range(3):
            x0, y0 = fw + i * (pw + mw), fw + j * (ph + mw)
            pane = c.rect(x0, y0, x0 + pw, y0 + ph)
            shift = (i * 53 + j * 17, j * 61 + i * 29)
            prgb, prough = np.roll(g, shift, (1, 0)), np.roll(gr, shift, (1, 0))
            if variant == 'b' and k == 4:        # a pane replaced with a scrap of board
                bd, bh = wood_patch(n, n, seed + 9, False, 14)
                c.put(pane, bd * 0.8, bh * 0.3 + 0.5, 0.85)
            elif variant == 'b' and k in (0, 3):  # blackout paper behind the glass
                c.put(pane, mix(prgb, col('20201c'), 0.75), 0.25, np.clip(prough + 0.25, 0, 1))
            else:
                c.put(pane, prgb, 0.25, prough)
            c.rgb *= (1 - 0.4 * pane * smooth(y, y0 + 10, y0))[..., None]
            k += 1
    if variant == 'a':  # a strip of gummed anti-blast tape across the panes
        for a, b in (((fw, fw), (n - fw, n - fw)), ((n - fw, fw), (fw, n - fw))):
            tape = c.line([a, b], 5) * (c.height < 0.4)
            c.rgb = mix(c.rgb, col('a89f80'), (tape * 0.55)[..., None])
            c.rough = mix(c.rough, 0.8, tape)
    sill = c.rect(0, n - 16, n, n)
    c.rgb *= (1 + 0.1 * sill)[..., None]
    st = top_streaks((n, n), seed + 4, 0.5, 0.5)
    c.rgb = mix(c.rgb, col('46443a'), (st * 0.3)[..., None])
    return finish(c, seed, 0.2, 1.0)


def trim_shutter(seed, w=96, h=256, paint='4d5a47'):
    c = Canvas(w, h, seed)
    x, y = grid((h, w))
    slat = (y / 16.0) % 1.0
    wood, _ = wood_patch(w, h, seed, False, 16)
    rgb, pm = peel_paint(wood, paint, seed + 1, 0.4, 0.2)
    c.rgb = rgb * (0.62 + 0.5 * slat)[..., None]
    c.height = slat * 0.7
    frame = c.rect(0, 0, w, h) - c.rect(10, 10, w - 10, h - 10)
    fwood, _ = wood_patch(w, h, seed + 2, True, 300)
    fr, _ = peel_paint(fwood, paint, seed + 3, 0.4, 0.2)
    c.put(np.clip(frame, 0, 1), fr, 0.95, shadow=2.5)
    c.put(c.rect(10, h / 2 - 6, w - 10, h / 2 + 6), fr, 0.95, shadow=2.5)
    return finish(c, seed)


def trim_vent(seed, n=96):
    c = trim_shutter(seed, n, n, 'b9b294')
    return c


def trim_lock(seed, n=96):
    c = Canvas(n, n, seed)
    iron = iron_patch(n, n, seed)
    c.rgb, c.rough = iron * 1.1, np.full((n, n), 0.6, np.float32)
    c.height[:] = 0.5
    for nx, ny in ((12, 12), (n - 12, 12), (12, n - 12), (n - 12, n - 12)):
        c.put(c.ellipse(nx - 4, ny - 4, nx + 4, ny + 4), col('5f5850'), 0.8)
    shackle = c.line([(34, 50), (34, 26), (62, 26), (62, 50)], 7)
    c.put(shackle, col('6a655c'), 0.9, 0.4, shadow=2.0)
    c.put(c.rect(26, 46, 70, 82), col('7a6a44'), 1.0, 0.45, shadow=3.0)
    c.put(c.ellipse(44, 56, 52, 64), col('1a1814'), 0.7)
    c.put(c.rect(46, 62, 50, 74), col('1a1814'), 0.7)
    return finish(c, seed, 0.15, 1.0)


def trim_tabletop(seed, n=256):
    c = Canvas(n, n, seed)
    wood, hh = wood_patch(n, n, seed, False, 43, base=('a8946c', '8f866f', '5a4a36'))
    c.rgb, c.height = wood, hh * 0.5
    x, y = grid((n, n))
    # a map sheet with grid, contours and a pencilled route
    sheet = c.poly([(30, 44), (196, 30), (206, 170), (40, 186)])
    paper = col('cfc6a6') * (0.9 + 0.14 * fbm((n, n), 2.0, seed + 1))[..., None]
    lines = ((np.abs(((x + y * 0.08) / 28.0) % 1.0 - 0.5) > 0.47) | (np.abs(((y - x * 0.08) / 28.0) % 1.0 - 0.5) > 0.47)).astype(np.float32)
    paper = mix(paper, col('8d8a78'), (lines * 0.35)[..., None])
    cont = fbm((n, n), 2.4, seed + 2, lo=2)
    contour = (np.abs((cont * 9.0) % 1.0 - 0.5) > 0.44).astype(np.float32)
    paper = mix(paper, col('8a6a4a'), (blur(contour, 0.6, False) * 0.5)[..., None])
    sea = smooth(cont, 0.3, 0.26)
    paper = mix(paper, col('9fb0ac'), (sea * 0.5)[..., None])
    route = c.line([(70, 150), (96, 118), (140, 110), (168, 70)], 2.5)
    paper = mix(paper, col('7a2f26'), (route * 0.8)[..., None])
    c.put(sheet, paper, 0.62, 0.8, shadow=3.0)
    fold = c.line([(118, 37), (124, 178)], 2)
    c.rgb *= (1 - 0.15 * fold * sheet)[..., None]
    # loose papers, an enamel mug and a pencil
    c.put(c.poly([(170, 160), (236, 150), (244, 226), (178, 236)]), col('c9c2a8') * 0.96, 0.6, 0.8, shadow=3.0)
    scrib = (np.abs(((y + x * 0.14) / 9.0) % 1.0 - 0.5) > 0.38).astype(np.float32) * c.poly([(180, 172), (230, 164), (236, 216), (186, 224)])
    c.rgb = mix(c.rgb, col('54524a'), (scrib * 0.4)[..., None])
    c.put(c.ellipse(26, 196, 70, 240), col('8f9690'), 0.9, 0.35, shadow=4.0)
    c.put(c.ellipse(32, 202, 64, 234), col('3a2c20'), 0.75, 0.3)
    c.put(c.line([(96, 214), (150, 226)], 4), col('a8873a'), 0.7, 0.6, shadow=2.0)
    return finish(c, seed, 0.2, 1.2)


def trim_grille(seed, w=128, h=192):
    """Radiator: vertical slats in a pressed surround. Light neutral paint so the body colour comes from vertex tint."""
    c = Canvas(w, h, seed)
    x, y = grid((h, w))
    paint = col('aeb09a') * (0.9 + 0.16 * fbm((h, w), 2.0, seed))[..., None]
    c.rgb, c.rough = paint.copy(), np.full((h, w), 0.6, np.float32)
    c.height[:] = 0.8
    core = c.rect(16, 18, w - 16, h - 14)
    slat = smooth(np.abs((x / 9.0) % 1.0 - 0.5), 0.2, 0.34)
    dark = mix(col('15171a'), col('3a3d3a'), (slat * 0.5)[..., None])
    c.put(core * (1 - slat * 0.75), dark, 0.2, 0.7)
    c.put(c.rect(w / 2 - 3, 18, w / 2 + 3, h - 14), paint, 0.85, 0.6)
    chip = smooth(fbm((h, w), 1.3, seed + 1, lo=5), 0.7, 0.74) * (1 - core)
    c.put(chip, col('5a3d2c'), 0.6, 0.9)
    bug = smooth(fbm((h, w), 1.6, seed + 2), 0.5, 0.9) * core
    c.rgb = mix(c.rgb, col('6a5c44'), (bug * 0.3)[..., None])
    return finish(c, seed, 0.15, 1.0)


def trim_lens(seed, n=64):
    c = Canvas(n, n, seed)
    x, y = grid((n, n))
    r = np.sqrt((x - n / 2) ** 2 + (y - n / 2) ** 2) / (n / 2)
    c.rgb[:] = col('2b2c2a')
    flutes = 0.5 + 0.5 * np.sin(x * 1.3)
    lens = mix(col('8f9a98'), col('d9dfd6'), (smooth(r, 0.9, 0.0) * 0.6 + flutes * 0.25)[..., None])
    lens = mix(lens, col('f2f3ea'), (smooth(np.sqrt((x - n * 0.38) ** 2 + (y - n * 0.36) ** 2), 9, 3) * 0.7)[..., None])
    m = smooth(r, 0.86, 0.80)
    c.put(m, lens, 0.6, 0.12)
    rim = smooth(r, 0.98, 0.94) * (1 - m)
    c.put(rim, col('6c6d66'), 0.9, 0.4)
    dust = fbm((n, n), 2.0, seed)
    c.rgb = mix(c.rgb, col('7b7662'), (smooth(dust, 0.5, 0.9) * 0.35)[..., None])
    return c


def trim_glass(seed, n=64):
    c = Canvas(n, n, seed)
    c.rgb, c.rough = glass_patch(n, n, seed)
    c.height[:] = 0.5
    return c


def trim_drum_lid(seed, n=128):
    c = Canvas(n, n, seed)
    x, y = grid((n, n))
    r = np.sqrt((x - n / 2) ** 2 + (y - n / 2) ** 2) / (n / 2)
    paint = col('a9ab96') * (0.86 + 0.2 * fbm((n, n), 2.0, seed))[..., None]
    c.rgb, c.rough = paint, np.full((n, n), 0.6, np.float32)
    rings = 0.5 + 0.5 * np.cos(np.clip(r, 0, 1) * np.pi * 5.0)
    c.height = 0.4 + 0.2 * rings * (r < 0.86) + 0.5 * smooth(r, 0.86, 0.93)
    c.rgb *= (0.86 + 0.2 * rings)[..., None]
    puddle = smooth(fbm((n, n), 2.0, seed + 1), 0.45, 0.7) * smooth(r, 0.86, 0.6)
    c.put(puddle * 0.75, col('6a4a32'), None, 0.9)
    c.put(c.ellipse(86, 30, 104, 48), col('5f5d54'), 0.9, 0.45, shadow=2.5)
    c.put(c.ellipse(91, 35, 99, 43), col('2f2d29'), 0.7)
    c.put(c.ellipse(28, 84, 38, 94), col('5f5d54'), 0.8, 0.45, shadow=2.0)
    rim = smooth(r, 0.9, 0.95) * smooth(r, 1.0, 0.97)
    c.put(rim * smooth(fbm((n, n), 1.2, seed + 2, lo=4), 0.4, 0.6), col('5c3e2c'), None, 0.9)
    c.rgb *= (1 - 0.6 * smooth(r, 0.985, 1.02))[..., None]
    return finish(c, seed, 0.15, 1.0)


def trim_cable_drum(seed, n=128):
    c = Canvas(n, n, seed)
    x, y = grid((n, n))
    r = np.sqrt((x - n / 2) ** 2 + (y - n / 2) ** 2) / (n / 2)
    wood, hh = wood_patch(n, n, seed, True, 18)
    c.rgb, c.height = wood * 0.95, hh * 0.5
    ring = smooth(np.abs(r - 0.62), 0.07, 0.05)
    c.put(ring, wood_patch(n, n, seed + 1, False, 300)[0] * 1.05, 0.8, shadow=2.0)
    for a in np.linspace(0, 2 * np.pi, 8, endpoint=False):
        bx, by = n / 2 + np.cos(a) * n * 0.31, n / 2 + np.sin(a) * n * 0.31
        c.put(c.ellipse(bx - 3, by - 3, bx + 3, by + 3), col('2d2a26'), 0.95)
    c.put(smooth(r, 0.2, 0.17), iron_patch(n, n, seed + 2), 0.9, 0.55, shadow=2.0)
    c.put(smooth(r, 0.09, 0.07), col('14120f'), 0.2)
    m = place((n, n), stencil_mask('60', 22), n * 0.5, n * 0.83)
    c.rgb = mix(c.rgb, col('2b2d27'), (worn(m, seed + 3, 0.35) * 0.8)[..., None])
    c.rgb *= (1 - 0.7 * smooth(r, 0.975, 1.01))[..., None]
    return finish(c, seed)


def trim_panel(seed, n=128):
    """Enamelled switch panel for the generator / junction box."""
    c = Canvas(n, n, seed)
    c.rgb[:] = col('7d8580')
    c.rgb *= (0.88 + 0.18 * fbm((n, n), 2.0, seed))[..., None]
    c.height[:] = 0.5
    c.rough[:] = 0.5
    edge = c.rect(0, 0, n, n) - c.rect(6, 6, n - 6, n - 6)
    c.rgb *= (1 - 0.25 * np.clip(edge, 0, 1))[..., None]
    for cx in (38, 90):
        c.put(c.ellipse(cx - 24, 14, cx + 24, 62), col('26282a'), 0.8, 0.4, shadow=2.5)
        c.put(c.ellipse(cx - 19, 19, cx + 19, 57), col('cfcab2'), 0.7, 0.2)
        c.put(c.line([(cx, 38), (cx + 10, 26)], 2), col('1a1a1a'), 0.75)
    for i, cx in enumerate((26, 52, 78, 104)):
        c.put(c.ellipse(cx - 8, 76, cx + 8, 92), col('2c2c2c'), 0.85, 0.45, shadow=2.0)
        c.put(c.rect(cx - 2, 70 + (i % 2) * 8, cx + 2, 86 + (i % 2) * 8), col('b9b6a8'), 1.0, 0.35)
        c.put(c.rect(cx - 10, 100, cx + 10, 108), col('c9c2a6'), 0.55, 0.6)
    c.put(c.rect(14, 114, n - 14, 122), col('35373a'), 0.3)
    chip = smooth(fbm((n, n), 1.3, seed + 1, lo=5), 0.72, 0.76)
    c.put(chip, col('5a3d2c'), None, 0.9)
    return finish(c, seed, 0.15, 1.0)


def trim_blanket(seed, n=128):
    c = Canvas(n, n, seed)
    x, y = grid((n, n))
    wool = fbm((n, n), 0.9, seed, lo=10)
    folds = fbm((n, n), 2.4, seed + 1, ax=0.6, ay=1.5)
    c.rgb = mix(col('64665c'), col('7f8074'), wool[..., None]) * (0.8 + 0.35 * folds)[..., None]
    stripe = smooth(np.abs(y - 26), 7, 5) + smooth(np.abs(y - 44), 3, 2)
    c.rgb = mix(c.rgb, col('3b4650'), (np.clip(stripe, 0, 1) * 0.8)[..., None])
    c.height = 0.4 + 0.5 * folds + 0.05 * wool
    c.rough[:] = 0.95
    return c


def tex_trim():
    S = 1024
    rgb = np.zeros((S, S, 3), np.float32)
    rgb[:] = col('6a6658')
    hh = np.full((S, S), 0.5, np.float32)
    rough = np.full((S, S), 0.85, np.float32)
    nrm = np.zeros((S, S, 3), np.float32)
    nrm[:] = (0.5, 0.5, 1.0)
    labels = (mission_labels() + ['', '', ''])[:3]
    cells = {
        'sign0': trim_sign(labels[0], 400), 'sign1': trim_sign(labels[1], 410), 'sign2': trim_sign(labels[2], 420),
        'plate_arrow': trim_plate('arrow', 430), 'plate_no': trim_plate('no', 431), 'plate_warn': trim_plate('warn', 432),
        'plate_blank': trim_plate('blank', 433), 'board_blank': trim_sign('', 440, 512, 88),
        'door_plank': trim_door_plank(450), 'door_glazed': trim_door_glazed(460), 'slide_door': trim_slide_door(470),
        'window_a': trim_window(480, 'a'), 'window_b': trim_window(490, 'b'), 'shutter': trim_shutter(500),
        'vent': trim_vent(505), 'lock': trim_lock(510), 'tabletop': trim_tabletop(520), 'grille': trim_grille(530),
        'lens': trim_lens(540), 'glass': trim_glass(545), 'drum_lid': trim_drum_lid(550),
        'cable_drum': trim_cable_drum(560), 'panel': trim_panel(570), 'blanket': trim_blanket(580),
    }
    for key, c in cells.items():
        x, y, w, h = TRIM[key]
        assert (c.w, c.h) == (w, h), key
        rgb[y:y + h, x:x + w] = painterly(c.rgb, 0.25, 600 + x + y)
        rough[y:y + h, x:x + w] = c.rough
        nrm[y:y + h, x:x + w] = normal_from_height(c.height, 4.0, False, False)
    out('trim', rgb, nrm, rough=rough)
    with open(os.path.join(OUT, 'trim_labels.json'), 'w') as f:
        json.dump({'labels': labels}, f)



# --------------------------------------------------------------------------------------------------------------------
# Wire cut-outs 512 x 512 (alpha scissor). Bands tile along U only (see WIRE_* in structures_kit.gd):
#   y   0..256  woven stock fence (graduated horizontal wires + stays every 0.16 m)
#   y 256..320  one barbed strand
#   y 320..512  concertina coil seen from the side
# --------------------------------------------------------------------------------------------------------------------
def tex_wire():
    S = 512
    ss = 3
    im = Image.new('L', (S * ss, S * ss), 0)
    d = ImageDraw.Draw(im)

    def ln(pts, w):
        d.line([(x * ss, y * ss) for x, y in pts], fill=255, width=int(round(w * ss)))

    # stock fence: horizontals closer together near the ground
    ys = [6, 62, 112, 154, 188, 214, 234, 250]
    for y in ys:
        ln([(0, y), (S, y)], 3.4)
    for x in range(16, S, 32):
        ln([(x, ys[0]), (x, ys[-1])], 2.8)
        for y in ys:
            d.ellipse([(x - 3.6) * ss, (y - 3.6) * ss, (x + 3.6) * ss, (y + 3.6) * ss], fill=255)
    # barbed strand: two twisted wires and four-point barbs
    yb = 288
    xs = np.arange(0, S + 1, 4)
    ln([(x, yb + 2.2 * np.sin(x * 2 * np.pi / 32.0)) for x in xs], 3.0)
    ln([(x, yb - 2.2 * np.sin(x * 2 * np.pi / 32.0)) for x in xs], 3.0)
    for x in range(32, S, 64):
        ln([(x - 11, yb - 13), (x + 11, yb + 13)], 2.8)
        ln([(x + 11, yb - 13), (x - 11, yb + 13)], 2.8)
        d.ellipse([(x - 5) * ss, (yb - 5) * ss, (x + 5) * ss, (yb + 5) * ss], fill=255)
    # concertina: overlapping loops, every loop barbed
    cy, ry, rx = 416, 84, 62
    for cx in range(-64, S + 65, 64):
        d.ellipse([(cx - rx) * ss, (cy - ry) * ss, (cx + rx) * ss, (cy + ry) * ss], outline=255, width=int(3.4 * ss))
        for a in np.linspace(0, 2 * np.pi, 14, endpoint=False):
            px, py = cx + np.cos(a) * rx, cy + np.sin(a) * ry
            tx, ty = -np.sin(a) * 7, np.cos(a) * 7
            ln([(px - tx - ty * 0.6, py - ty + tx * 0.6), (px + tx + ty * 0.6, py + ty - tx * 0.6)], 2.6)
    a = np.asarray(im.resize((S, S), Image.LANCZOS), np.float32) / 255.0
    a = np.clip(a * 1.25, 0, 1)
    n = fbm((S, S), 1.6, 701)
    rust = smooth(fbm((S, S), 1.4, 702, lo=3), 0.45, 0.7)
    rgb = mix(col('4a4a46'), col('6f6f68'), n[..., None])
    rgb = mix(rgb, col('6e4a34'), (rust * 0.65)[..., None])
    # bleed colour outward so mip levels do not pull in black at the cut-out edges
    rgb = np.broadcast_to(rgb, (S, S, 3)).copy()
    out('wire', rgb, None, alpha=a)


# --------------------------------------------------------------------------------------------------------------------
# Ground decals 512 x 512 (alpha blended, colour mostly from vertex colour), 2 x 2 cells of 256 px:
#   (0,0) soft round contact blob     (1,0) wall skirt: opaque along the top edge fading down
#   (0,1) oil / fuel stain            (1,1) trampled bare earth
# --------------------------------------------------------------------------------------------------------------------
def tex_decal():
    n = 256
    S = 512
    rgb = np.ones((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    x, y = grid((n, n))
    r = np.sqrt((x - n / 2) ** 2 + (y - n / 2) ** 2) / (n / 2)
    edge_fade = smooth(np.minimum(np.minimum(x, n - x), np.minimum(y, n - y)), 2, 14)
    # blob
    a[0:n, 0:n] = smooth(r, 0.96, 0.15) ** 1.4
    # skirt (fades toward +v, breaks up a little along u, clear at the left/right cell borders)
    rag = blur(fbm((n, n), 2.4, 801, lo=1), 5, False)
    sk = smooth(y / n, 0.55 + 0.4 * rag, 0.0) ** 1.6
    a[0:n, n:S] = sk * smooth(np.minimum(y, n - y), 0, 6)
    # oil
    blot = blur(fbm((n, n), 2.6, 802, lo=1.5), 3, False) * 0.85 + fbm((n, n), 1.6, 803, lo=6) * 0.15
    oil = smooth(blot - r * 0.6, 0.02, 0.16)
    spl = speckle((n, n), 804, 0.0012, 1.6) * smooth(r, 1.0, 0.5)
    oil_a = np.clip(oil * (0.75 + 0.25 * fbm((n, n), 1.5, 805)) + spl * 0.8, 0, 1) * edge_fade
    a[n:S, 0:n] = oil_a
    sheen = fbm((n, n), 1.6, 806)
    rgb[n:S, 0:n] = mix(col('17140f'), col('3a3226'), sheen[..., None])
    # trampled earth
    dn = blur(fbm((n, n), 2.6, 807, lo=1.5), 3, False) * 0.8 + fbm((n, n), 1.4, 808, lo=8) * 0.2
    dirt = smooth(dn - r * 0.66, -0.1, 0.22) * edge_fade
    a[n:S, n:S] = dirt * (0.8 + 0.2 * fbm((n, n), 0.8, 809, lo=12))
    earth = mix(col('5a4d38'), col('83745a'), fbm((n, n), 1.7, 810)[..., None])
    peb = speckle((n, n), 811, 0.004, 1.0)
    rgb[n:S, n:S] = mix(earth, col('a39a84'), (peb * 0.6)[..., None])
    os.makedirs(OUT, exist_ok=True)
    save_rgba(os.path.join(OUT, 'decal_a.png'), rgb, a)
    print('wrote decal')


ALL = {}
for _name, _fn in list(globals().items()):
    if _name.startswith('tex_') and callable(_fn):
        ALL[_name[4:]] = _fn

if __name__ == '__main__':
    names = sys.argv[1:] or list(ALL.keys())
    for nm in names:
        ALL[nm]()
