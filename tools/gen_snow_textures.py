#!/usr/bin/env python3
"""Procedural snow textures (the snow layer and the footprints of La Boca and the Plaza de Mayo).
Usage:  python3 tools/gen_snow_textures.py [name ...]      (no names = everything)
Output: godot/assets/tex/snow/<name>_a.png  (albedo; alpha = height)
        godot/assets/tex/snow/<name>_n.png  (OpenGL normal map)
        godot/assets/tex/snow/prints.png    (footprint atlas: boots on the left half, a ski track on the right)
Texel density: the ground textures tile every 4 m (512 px, 128 px/m); the prints are drawn at about 300 px/m."""
import os
import sys
sys.dont_write_bytecode = True
import numpy as np
from scipy import ndimage
from PIL import Image
from structures_texlib import *

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'snow'))
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


def tex_snow():
    """Wind-packed fresh snow: long soft ripples (sastrugi) running across U, the odd scoured hollow, a fine
    sugar grain. Albedo is near white with the faintest blue in the hollows; alpha = height."""
    shape = (N, N)
    x, y = grid(shape)
    big = fbm(shape, beta=3.2, seed=11, ax=1.0, ay=3.0)            # stretched along U: ripples across the wind
    ripple = np.sin((y / N) * np.pi * 2 * 9 + big * 5.0) * 0.5 + 0.5
    ripple = smooth(ripple, 0.25, 0.95) ** 1.6
    hollow = smooth(fbm(shape, beta=2.6, seed=12), 0.55, 0.9)
    grain = fbm(shape, beta=0.6, seed=13)
    h = 0.55 * big + 0.28 * ripple - 0.25 * hollow + 0.05 * grain
    h = norm01(h)
    shade = 0.92 + 0.08 * h - 0.05 * hollow
    rgb = np.stack([shade * 0.97, shade * 0.985, shade * 1.0], -1)
    n = normal_from_height(blur(h, 0.8), strength=2.2)
    out('snow', rgb, n, h)


def tex_packed():
    """Snow trodden and driven over: compacted, greyed with grit and cinders, crossed by ruts and boot marks.
    Ruts run along U. Alpha = height."""
    shape = (N, N)
    rng = np.random.default_rng(21)
    x, y = grid(shape)
    base = fbm(shape, beta=2.4, seed=22)
    # two pairs of wheel ruts along U, wandering a little
    ruts = np.zeros(shape, np.float32)
    wob = fbm(shape, beta=3.0, seed=23, ax=1.0, ay=6.0) * 18.0
    for c in (0.22, 0.38, 0.66, 0.82):
        d = np.abs(((y + wob) / N - c + 0.5) % 1.0 - 0.5) * N
        ruts += np.exp(-(d / 7.0) ** 2)
    # boot prints scattered about
    prints = np.zeros(shape, np.float32)
    for i in range(140):
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        a = rng.uniform(0, np.pi * 2)
        dx = ((x - cx + N / 2) % N) - N / 2
        dy = ((y - cy + N / 2) % N) - N / 2
        u = dx * np.cos(a) + dy * np.sin(a)
        v = -dx * np.sin(a) + dy * np.cos(a)
        prints = np.maximum(prints, np.exp(-((u / 15.0) ** 2 + (v / 6.0) ** 2) ** 2))
    grit = smooth(fbm(shape, beta=0.8, seed=24), 0.62, 0.9)
    h = 0.5 + 0.25 * base - 0.35 * ruts - 0.2 * prints
    h = norm01(blur(h, 0.7))
    tone = 0.80 + 0.12 * h - 0.18 * grit - 0.06 * ruts
    rgb = np.stack([tone * 0.95, tone * 0.95, tone * 0.97], -1)
    dirt = np.array([0.42, 0.39, 0.35])
    rgb = mix(rgb, np.broadcast_to(dirt, rgb.shape), (grit * 0.55 + ruts * 0.25)[..., None])
    n = normal_from_height(h, strength=3.0)
    out('packed', rgb, n, h)


def tex_ice():
    """River ice: grey-green clear ice with white crazing and drifted snow in patches. Alpha = snow cover."""
    shape = (N, N)
    rng = np.random.default_rng(31)
    pts = rng.uniform(0, N, (90, 2))
    cells = voronoi(shape, pts)
    edge = cells[1] - cells[0]
    cracks = 1.0 - smooth(edge, 0.0, 3.5)
    fine = 1.0 - smooth(voronoi(shape, rng.uniform(0, N, (400, 2)))[1] - voronoi(shape, rng.uniform(0, N, (400, 2)))[0], 0.0, 2.0)
    drift = smooth(fbm(shape, beta=2.8, seed=32), 0.5, 0.75)
    clear = np.array([0.20, 0.27, 0.28])
    white = np.array([0.86, 0.9, 0.94])
    rgb = mix(np.broadcast_to(clear, (N, N, 3)), np.broadcast_to(white, (N, N, 3)), (cracks * 0.7 + fine * 0.15)[..., None])
    rgb = mix(rgb, np.broadcast_to(white, (N, N, 3)), drift[..., None])
    h = 0.5 + 0.3 * drift - 0.2 * cracks
    out('ice', rgb, normal_from_height(blur(h, 1.0), strength=1.4), drift)


def tex_prints():
    """Footprint atlas, 512 x 256: left cell a pair of boot prints (left and right foot, toes up the cell), right
    cell two ski grooves running the length of the cell. RGB = shading inside the dent (darker on the side the
    light comes from), alpha = how deep."""
    W, Hh = 512, 256
    img = np.zeros((Hh, W, 4), np.float32)
    yy, xx = np.mgrid[0:Hh, 0:W].astype(np.float32)
    # boots: each cell 256 x 256, a print about 0.3 m long drawn 200 px long
    def boot(cx, cy, flip):
        u = (xx - cx) * (-1 if flip else 1)
        v = (yy - cy)
        sole = ((u / 34.0) ** 2 + ((v + 30) / 62.0) ** 2) <= 1.0
        heel = ((u / 30.0) ** 2 + ((v - 62) / 30.0) ** 2) <= 1.0
        shape = (sole | heel).astype(np.float32)
        shape = blur(shape, 3.0, wrap=False)
        lugs = (np.sin(v * 0.55) * 0.5 + 0.5) * 0.25
        return shape, lugs
    a1, l1 = boot(92, 118, False)
    a2, l2 = boot(166, 140, True)
    depth = np.maximum(a1, a2)
    lug = np.maximum(l1 * a1, l2 * a2)
    left = xx < 256
    rim = np.clip(ndimage.sobel(blur(depth, 2.0, wrap=False), axis=0) * 0.08, -0.3, 0.3)
    shade = 0.55 + rim - lug * 0.4
    img[..., 0] = np.where(left, shade, img[..., 0])
    img[..., 1] = np.where(left, shade, img[..., 1])
    img[..., 2] = np.where(left, shade * 1.08, img[..., 2])
    img[..., 3] = np.where(left, np.clip(depth, 0, 1) * 0.85, 0)
    # skis: two grooves 18 px wide, 70 px apart, the full height of the cell, a pole basket mark beside each
    groove = np.zeros((Hh, W), np.float32)
    for gx in (256 + 93, 256 + 163):
        groove = np.maximum(groove, np.exp(-((xx - gx) / 9.0) ** 6))
    for bx, by in ((256 + 40, 70), (256 + 216, 190)):
        groove = np.maximum(groove, np.exp(-(((xx - bx) ** 2 + (yy - by) ** 2) / 90.0)) * 0.8)
    right = ~left
    rim = np.clip(ndimage.sobel(blur(groove, 2.0, wrap=False), axis=1) * 0.1, -0.3, 0.3)
    shade = 0.6 + rim
    for c in range(3):
        img[..., c] = np.where(right, shade * (1.08 if c == 2 else 1.0), img[..., c])
    img[..., 3] = np.where(right, groove * 0.8, img[..., 3])
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'prints.png'))
    print('wrote prints')


ALL = {'snow': tex_snow, 'packed': tex_packed, 'ice': tex_ice, 'prints': tex_prints}

if __name__ == '__main__':
    names = sys.argv[1:] or list(ALL)
    for name in names:
        ALL[name]()
