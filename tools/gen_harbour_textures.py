#!/usr/bin/env python3
"""Procedural harbour textures (cinder, setts, hull, streaks) La Boca's quays and river banks are built from.
Usage:  python3 tools/gen_harbour_textures.py [name ...]      (no names = everything)
Output: godot/assets/tex/harbour/<name>_a.png  (albedo; alpha = height for ground textures, roughness for hull)
        godot/assets/tex/harbour/<name>_n.png  (OpenGL normal map)
Texel density: 512 px = 2.56 m (200 px/m) for the tiling surfaces, like the structures textures.
streaks.png is a macro overlay (512 px = 8 m) for the bunker's leaching and rain marks."""
import os
import sys
sys.dont_write_bytecode = True
import numpy as np
from scipy import ndimage
from PIL import Image
from structures_texlib import *

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'harbour'))
N = 512


def out(name, rgb, normal=None, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    rgb = np.clip(rgb, 0, 1)
    if alpha is not None:
        save_rgba(os.path.join(OUT, name + '_a.png'), rgb, np.clip(alpha, 0.02, 1.0))
    else:
        save_rgb(os.path.join(OUT, name + '_a.png'), rgb)
    if normal is not None:
        save_normal(os.path.join(OUT, name + '_n.png'), normal)
    print('wrote', name)


def tex_setts():
    """Granite setts (pavés) laid in straight courses across the quay, joints filled with grit.
    Courses run along U; a sett is about 0.24 x 0.13 m. Alpha = height (joints low: puddles gather there)."""
    shape = (N, N)
    rng = np.random.default_rng(301)
    x, y = grid(shape)
    course = N / 20.0                       # 20 courses per tile -> 0.128 m
    row = np.floor(y / course).astype(np.int32)
    # each course has its own stagger and a run of sett lengths that tiles across U
    sid = np.zeros(shape, np.int32)
    edge_u = np.zeros(shape, np.float32)
    for r in range(20):
        lengths = []
        total = 0.0
        while total < N - 60:
            l = rng.uniform(38, 56)
            lengths.append(l)
            total += l
        scale = N / (total + rng.uniform(38, 56))
        lengths.append(N / scale - total)
        lengths = np.array(lengths) * scale
        cuts = np.concatenate([[0], np.cumsum(lengths)])
        off = rng.uniform(0, N)
        sel = row == r
        xs = (x[sel] + off) % N
        k = np.searchsorted(cuts, xs, side='right') - 1
        k = np.clip(k, 0, len(lengths) - 1)
        d = np.minimum(xs - cuts[k], cuts[k + 1] - xs)
        sid[sel] = r * 100 + k
        edge_u[sel] = d
    vy = (y % course)
    edge_v = np.minimum(vy, course - vy)
    jitter = (fbm(shape, 1.1, 302, lo=10) - 0.5) * 3.0
    edge = np.minimum(edge_u, edge_v * 1.15) + jitter
    joint = 1.0 - smooth(edge, 1.2, 4.0)
    r1 = cell_rand(sid, 1, 303)
    r2 = cell_rand(sid, 2, 304)
    r3 = cell_rand(sid, 3, 305)
    granite = mix(col('77797a'), col('9a9890'), r1[..., None])
    granite = mix(granite, col('8f8178'), (r2 > 0.82).astype(np.float32)[..., None] * 0.7)    # pinkish ones
    granite = mix(granite, col('5f6366'), (r3 < 0.18).astype(np.float32)[..., None] * 0.6)    # darker, oily
    speck = white(shape, 306)
    mica = (speck > 0.985).astype(np.float32) * 0.5 - (speck < 0.03).astype(np.float32) * 0.35
    grain = fbm(shape, 0.6, 307, lo=40)
    granite = granite * (0.88 + 0.18 * grain + 0.1 * mica)[..., None]
    dome = smooth(edge, 1.0, 14.0)
    tilt = (r2 - 0.5) * 0.25
    worn = fbm(shape, 1.6, 308, lo=4)
    height = (1 - joint) * (0.55 + 0.32 * dome + tilt * 0.4 + 0.1 * (worn - 0.5)) + joint * 0.08
    grit = mix(col('3b3833'), col('57524a'), fbm(shape, 1.4, 309)[..., None])
    rgb = mix(granite, grit, joint[..., None])
    rgb = rgb * np.clip(1.0 - cavity(height, 2.5) * 1.5, 0.55, 1.25)[..., None]
    polish = smooth(dome, 0.6, 1.0) * 0.08
    rgb = rgb + polish[..., None]
    oil = smooth(fbm(shape, 2.2, 310), 0.62, 0.85)
    rgb = mix(rgb, col('2e2c2a'), (oil * 0.35)[..., None])
    rgb = painterly(rgb, 0.3, 311)
    out('setts', rgb, normal_from_height(height, 6.0), alpha=height)


def tex_cinder():
    """Railway ballast and cinders: dark broken stone, clinker and coal grit. Alpha = height."""
    shape = (N, N)
    rng = np.random.default_rng(321)
    pts = rng.random((900, 2)).astype(np.float32) * N
    f1, f2, idx = voronoi(shape, pts)
    edge = f2 - f1
    stone = smooth(edge, 0.0, 6.0)
    r1 = cell_rand(idx, 1, 322)
    r2 = cell_rand(idx, 2, 323)
    base = mix(col('3f3d3a'), col('6a665f'), r1[..., None])
    base = mix(base, col('5a4a3f'), (r2 > 0.85).astype(np.float32)[..., None] * 0.6)   # rusty clinker
    base = mix(base, col('1f1f20'), (r2 < 0.2).astype(np.float32)[..., None] * 0.7)    # coal
    fine = fbm(shape, 0.4, 324, lo=60)
    height = stone * (0.5 + 0.5 * r1) * 0.8 + fine * 0.15
    rgb = base * (0.7 + 0.45 * stone)[..., None] * (0.9 + 0.2 * fine)[..., None]
    rgb = rgb * np.clip(1.0 - cavity(height, 2.0) * 1.6, 0.45, 1.3)[..., None]
    dust = smooth(fbm(shape, 2.0, 325), 0.45, 0.8)
    rgb = mix(rgb, col('4b4740'), (dust * 0.35)[..., None])
    rgb = painterly(rgb, 0.25, 326)
    out('cinder', rgb, normal_from_height(height, 5.0), alpha=height)


def tex_tarmac():
    """Old tar macadam on the road: dark, patched, cracked, grit showing through. Alpha = height."""
    shape = (N, N)
    big = fbm(shape, 2.2, 341)
    mid = fbm(shape, 1.2, 342, lo=8)
    grit = white(shape, 343)
    rgb = mix(col('2a2a2b'), col('454442'), smooth(big * 0.6 + mid * 0.4, 0.2, 0.9)[..., None])
    stones = (grit > 0.93).astype(np.float32)
    stones = ndimage.maximum_filter(stones, 2, mode='wrap')
    rgb = mix(rgb, col('6c6a64'), (stones * 0.45)[..., None])
    patch = smooth(fbm(shape, 2.6, 344), 0.6, 0.64)
    rgb = mix(rgb, col('1c1c1d'), (patch * 0.6)[..., None])
    cr = cracks(shape, 345)
    rgb = mix(rgb, col('141414'), (cr * 0.8)[..., None])
    height = 0.5 + 0.1 * (mid - 0.5) + 0.12 * stones - 0.35 * cr - 0.05 * patch
    rgb = painterly(rgb, 0.25, 346)
    out('tarmac', rgb, normal_from_height(height, 4.0), alpha=height)


def cracks(shape, seed, width=0.010):
    a = fbm(shape, 1.6, seed, lo=3)
    b = fbm(shape, 1.6, seed + 1, lo=3)
    c = 1.0 - np.clip(np.abs(a - 0.5) / width, 0, 1)
    d = 1.0 - np.clip(np.abs(b - 0.5) / width, 0, 1)
    return np.clip(c * smooth(b, 0.45, 0.7) + d * smooth(a, 0.5, 0.75) * 0.7, 0, 1)


def tex_hull():
    """A ship's side: welded and riveted strakes (two per tile, 1.28 m), plate butts staggered, rivet rows on
    every seam, paint gone chalky, rust weeping down from the seams. Light neutral grey: vertex colour paints it.
    Alpha = roughness."""
    shape = (N, N)
    x, y = grid(shape)
    strake = N / 2.0
    row = np.floor(y / strake)
    vy = y % strake
    seam_h = np.minimum(vy, strake - vy)
    off = np.where(row % 2 == 0, 0.0, N * 0.5)
    ux = (x + off) % N
    seam_v = np.minimum(ux, N - ux)
    seam = 1.0 - smooth(np.minimum(seam_h, seam_v), 0.6, 2.6)
    # lapped plates: each strake slightly proud at its lower edge
    lap = smooth(vy, strake - 14, strake - 1) * 0.12
    # rivets along both seams, 0.1 m pitch
    pitch = 20.0
    rv_h = np.minimum(np.abs(vy - 8.0), np.abs(vy - (strake - 8.0)))
    rv_hx = np.abs(((x + 10.0) % pitch) - pitch * 0.5)
    rivet_h = 1.0 - smooth(np.sqrt(rv_h ** 2 + rv_hx ** 2), 1.6, 3.4)
    rv_v = np.minimum(np.abs(ux - 8.0), np.abs(ux - (N - 8.0)))
    rv_vy = np.abs(((y + 10.0) % pitch) - pitch * 0.5)
    rivet_v = 1.0 - smooth(np.sqrt(rv_v ** 2 + rv_vy ** 2), 1.6, 3.4)
    rivet = np.clip(rivet_h + rivet_v, 0, 1)
    plate_id = (row * 7 + np.floor((x + off) / N)).astype(np.int32)
    tone = cell_rand(plate_id, 1, 361)
    big = fbm(shape, 2.0, 362)
    paint = mix(col('b7b9b6'), col('cfd0cb'), (tone * 0.5 + big * 0.5)[..., None])
    chalk = smooth(fbm(shape, 1.5, 363, ax=0.6, ay=1.6), 0.5, 0.85)
    paint = mix(paint, col('dcdcd4'), (chalk * 0.25)[..., None])
    # rust: blooms at rivets and seams, then runs down the plate
    seed_rust = np.clip(rivet * 0.8 + seam * 0.5, 0, 1) * smooth(fbm(shape, 1.4, 364, lo=4), 0.45, 0.75)
    weep = ndimage.gaussian_filter(seed_rust, (0.5, 0.5), mode='wrap')
    runs = np.zeros_like(weep)
    acc = weep.copy()
    for k in range(1, 90, 3):
        acc = np.roll(weep, k, 0) * np.exp(-k / 38.0)
        runs = np.maximum(runs, acc)
    runs = ndimage.gaussian_filter(runs, (2.0, 1.2), mode='wrap')
    runs = runs / (np.percentile(runs, 99.5) + 1e-6)
    runs = np.clip(runs, 0, 1) * smooth(fbm(shape, 1.2, 365, ax=8.0, ay=0.4, lo=6), 0.3, 0.75)
    rust = np.clip(seed_rust * 1.4 + runs * 0.85, 0, 1)
    rgb = mix(paint, col('7b4a2c'), (rust * 0.75)[..., None])
    rgb = mix(rgb, col('5a3a28'), (smooth(seed_rust, 0.3, 0.8) * 0.6)[..., None])
    rgb = rgb * (1.0 - 0.35 * seam)[..., None]
    scrape = smooth(fbm(shape, 1.0, 366, ax=6.0, ay=0.3, lo=8), 0.78, 0.86)
    rgb = mix(rgb, col('6c6458'), (scrape * 0.4)[..., None])
    rgb = rgb * (0.88 + 0.16 * fbm(shape, 2.3, 367))[..., None]
    height = 0.55 + lap - 0.35 * seam + 0.35 * rivet + 0.04 * (big - 0.5) - 0.05 * rust
    rough = 0.6 + 0.3 * rust + 0.1 * chalk - 0.15 * rivet
    rgb = painterly(rgb, 0.25, 368)
    out('hull', rgb, normal_from_height(height, 3.5), alpha=rough)


def tex_streaks():
    """Macro overlay for mass concrete (8 m per tile): leaching and rain streaks hanging from pour lines,
    damp at the foot. Greyscale, 0.5 = no change. Tiles along U; V runs down the wall."""
    shape = (N, N)
    x, y = grid(shape)
    s = fbm(shape, 1.0, 381, ax=14.0, ay=0.35, lo=4)
    s2 = fbm(shape, 1.3, 382, ax=6.0, ay=0.5, lo=3)
    lines = np.abs(((y / (N / 5.0)) % 1.0))               # five pour lifts per 8 m
    hang = np.exp(-lines * 3.5)                            # darkest just below each lift
    streak = smooth(s, 0.45, 0.9) * hang + smooth(s2, 0.6, 0.95) * 0.5
    light = smooth(fbm(shape, 1.2, 383, ax=10.0, ay=0.4, lo=5), 0.65, 0.95) * hang * 0.6   # efflorescence
    val = 0.5 - 0.32 * np.clip(streak, 0, 1) + 0.22 * light
    val = val + (fbm(shape, 2.0, 384) - 0.5) * 0.12
    img = np.clip(val, 0, 1)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(to8(img), 'L').save(os.path.join(OUT, 'streaks.png'), optimize=True)
    print('wrote streaks')


ALL = {'setts': tex_setts, 'cinder': tex_cinder, 'tarmac': tex_tarmac, 'hull': tex_hull, 'streaks': tex_streaks}

if __name__ == '__main__':
    names = sys.argv[1:] or list(ALL)
    for n in names:
        ALL[n]()
