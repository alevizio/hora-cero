#!/usr/bin/env python3
"""Procedural texture set for the game's environments (terrain, shore, rock, water, foliage cards).

Everything is generated from seeded noise and painted strokes - no external assets.
Usage:  python3 tools/gen_nature_textures.py [names...]      (no names = everything)
Output: godot/assets/tex/nature/*.png  (+ tools/preview_*.png contact sheets, not shipped)

Conventions
- Tiling textures wrap in both axes (FFT noise, wrapped blurs, wrapped stroke stamping).
- Normal maps are OpenGL style (+Y / green up), as Godot expects.
- Cut-out cards are painted at 3-4x and box-filtered down so alpha edges are clean, then the
  colour is bled into the transparent area so mip-mapping never pulls in a dark fringe.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "godot", "assets", "tex", "nature"))
PREVIEW = HERE


# ----------------------------------------------------------------------------- helpers
def rng_of(seed):
    return np.random.default_rng(seed)


def fbm(size, beta, seed, kmin=0.0, kmax=1e9):
    """Tileable fractal noise in 0..1 with a 1/f^beta spectrum, optionally band limited (cycles per tile)."""
    r = rng_of(seed)
    spec = np.fft.fft2(r.standard_normal((size, size)))
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    amp = k ** (-beta)
    amp[(k < kmin) | (k > kmax)] = 0.0
    amp[0, 0] = 0.0
    n = np.real(np.fft.ifft2(spec * amp))
    lo, hi = np.percentile(n, [0.5, 99.5])
    return np.clip((n - lo) / (hi - lo), 0.0, 1.0)


def blur(a, sigma):
    return ndi.gaussian_filter(a, sigma, mode="wrap")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def col(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0


def ramp(t, stops):
    """Colour ramp: stops = [(pos, rgb array)], t = array in 0..1 -> (...,3)."""
    t = np.asarray(t, dtype=np.float64)
    out = np.zeros(t.shape + (3,))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        w = np.clip((t - p0) / max(p1 - p0, 1e-6), 0.0, 1.0)
        if i == 0:
            out[:] = c0
        m = t >= p0
        out[m] = (c0 + (c1 - c0) * w[..., None])[m]
    return out


def normal_from_height(h, strength, wrap=True):
    mode_roll = wrap
    if mode_roll:
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        dy, dx = np.gradient(h)
    nx = -dx * strength
    ny = dy * strength  # image rows grow downwards, green points up
    nz = np.ones_like(h)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5], axis=-1)


def to_img(a):
    a = np.clip(a, 0.0, 1.0)
    return Image.fromarray((a * 255.0 + 0.5).astype(np.uint8))


def save(name, a):
    os.makedirs(OUT, exist_ok=True)
    img = a if isinstance(a, Image.Image) else to_img(a)
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")), img.size, img.mode)
    return img


def down(a, f):
    """Box filter an (H,W[,C]) float array by integer factor f."""
    h, w = a.shape[:2]
    if a.ndim == 2:
        return a.reshape(h // f, f, w // f, f).mean(axis=(1, 3))
    return a.reshape(h // f, f, w // f, f, a.shape[2]).mean(axis=(1, 3))


class Canvas:
    """RGB + height painter with optional wrap-around stamping (for tiling textures)."""

    def __init__(self, size, base_rgb, wrap=True, base_h=0):
        self.size = size
        self.wrap = wrap
        self.rgb = to_img(base_rgb) if not isinstance(base_rgb, Image.Image) else base_rgb
        self.h = Image.new("L", (size, size), base_h)
        self.d_rgb = ImageDraw.Draw(self.rgb)
        self.d_h = ImageDraw.Draw(self.h)

    def _offsets(self, x0, y0, x1, y1):
        if not self.wrap:
            return [(0, 0)]
        s = self.size
        xs = [0] + ([s] if x0 < 0 else []) + ([-s] if x1 >= s else [])
        ys = [0] + ([s] if y0 < 0 else []) + ([-s] if y1 >= s else [])
        return [(ox, oy) for ox in xs for oy in ys]

    def line(self, pts, rgb, height, width):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        c = tuple(int(max(0, min(255, v * 255))) for v in rgb)
        pad = width + 1
        for ox, oy in self._offsets(min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad):
            q = [(x + ox, y + oy) for x, y in pts]
            self.d_rgb.line(q, fill=c, width=width)
            if height is not None:
                self.d_h.line(q, fill=int(height), width=width)

    def ellipse(self, cx, cy, rx, ry, rgb, height=None):
        c = tuple(int(max(0, min(255, v * 255))) for v in rgb)
        for ox, oy in self._offsets(cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1):
            box = [cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy]
            self.d_rgb.ellipse(box, fill=c)
            if height is not None:
                self.d_h.ellipse(box, fill=int(height))

    def polygon(self, pts, rgb, height=None):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        c = tuple(int(max(0, min(255, v * 255))) for v in rgb)
        for ox, oy in self._offsets(min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1):
            q = [(x + ox, y + oy) for x, y in pts]
            self.d_rgb.polygon(q, fill=c)
            if height is not None:
                self.d_h.polygon(q, fill=int(height))

    def arrays(self):
        return np.asarray(self.rgb, dtype=np.float64) / 255.0, np.asarray(self.h, dtype=np.float64) / 255.0


def sample_wrap(field, x, y):
    s = field.shape[0]
    return field[int(y) % s, int(x) % s]


# ----------------------------------------------------------------------------- ground: grass
def paint_grass(seed, out=512, ss=2, n=90000, palette=None, base=None, length=(9, 22), straw=0.06, flow_w=0.55):
    """Top-down meadow: tens of thousands of short blade strokes layered dark-to-light."""
    s = out * ss
    r = rng_of(seed)
    patch = fbm(s, 2.2, seed + 1, kmax=10)       # clump-scale hue variation
    patch2 = fbm(s, 1.6, seed + 2, kmin=3, kmax=40)
    flow = fbm(s, 2.6, seed + 3, kmax=6) * math.tau * 2.0
    base_rgb = np.empty((s, s, 3))
    base_rgb[:] = base
    base_rgb *= (0.93 + 0.14 * patch)[..., None]
    cv = Canvas(s, base_rgb, wrap=True, base_h=20)
    dark, mid, light, dry = palette
    xs = r.uniform(0, s, n)
    ys = r.uniform(0, s, n)
    ang_r = r.uniform(0, math.tau, n)
    lens = r.uniform(length[0], length[1], n) * ss * (0.75 + 0.5 * r.random(n))
    jit = r.normal(0, 1, (n, 3))
    pick = r.random(n)
    bend = r.normal(0, 0.35, n)
    for i in range(n):
        t = i / n
        x, y = xs[i], ys[i]
        p = sample_wrap(patch, x, y)
        p2 = sample_wrap(patch2, x, y)
        a = lerp(ang_r[i], sample_wrap(flow, x, y), flow_w)
        ln = lens[i] * (0.8 + 0.5 * p)
        # layer colour: deep blades first, sunlit blades last
        c = lerp(dark, mid, min(1.0, t * 1.5)) if t < 0.66 else lerp(mid, light, (t - 0.66) / 0.34)
        c = c * (0.95 + 0.10 * p) + (p2 - 0.5) * np.array([0.03, 0.035, 0.0])
        if pick[i] < straw * (0.4 + 1.6 * p2):
            c = lerp(c, dry, 0.75)
        c = c + jit[i] * 0.012
        dx, dy = math.cos(a), math.sin(a)
        mx = x + dx * ln * 0.5 - dy * bend[i] * ln * 0.2
        my = y + dy * ln * 0.5 + dx * bend[i] * ln * 0.2
        ex, ey = x + dx * ln, y + dy * ln
        w = ss if (t < 0.5 or pick[i] > 0.5) else ss + 1
        hgt = 40 + 190 * t
        cv.line([(x, y), (mx, my)], c * 0.84, hgt * 0.8, w)
        cv.line([(mx, my), (ex, ey)], c * 1.05, hgt, max(1, w - 1) if ss > 1 else 1)
    rgb, h = cv.arrays()
    rgb = down(rgb, ss)
    h = down(h, ss)
    return rgb, h


def tex_grass():
    pal = (col("3a4a2c"), col("566a3c"), col("7c8a52"), col("a09a66"))
    rgb, h = paint_grass(101, palette=pal, base=col("2e3a24"))
    # keep values in a controlled mid range: compress contrast slightly, soften speckle
    soft = np.stack([blur(rgb[..., i], 0.6) for i in range(3)], axis=-1)
    rgb = lerp(rgb, soft, 0.45)
    mean = rgb.mean(axis=(0, 1))
    rgb = mean + (rgb - mean) * 0.88
    hh = blur(h, 0.7)
    save("grass_albedo", np.dstack([rgb, hh]))
    save("grass_normal", normal_from_height(blur(h, 0.9), 5.5))


# ----------------------------------------------------------------------------- ground: dirt / shingle
def scatter_pebbles(cv, r, count, size_rng, colours, hrange, squash=(0.6, 1.0), shadow=0.55, ao_pad=1.25):
    s = cv.size
    for _ in range(count):
        x, y = r.uniform(0, s, 2)
        ra = r.uniform(*size_rng)
        rb = ra * r.uniform(*squash)
        ang = r.uniform(0, math.pi)
        c = colours[r.integers(len(colours))] * r.uniform(0.86, 1.1)
        pts = []
        k = 9
        wob = r.uniform(0.85, 1.12, k)
        for j in range(k):
            a = j / k * math.tau
            px, py = math.cos(a) * ra * wob[j], math.sin(a) * rb * wob[j]
            pts.append((x + px * math.cos(ang) - py * math.sin(ang), y + px * math.sin(ang) + py * math.cos(ang)))
        # the stone, then a lighter crown; contact shading comes from cavity_ao() afterwards
        hv = r.uniform(*hrange)
        cv.polygon(pts, c, hv)
        crown = [(x + (px - x) * 0.55, y + (py - y) * 0.55) for px, py in pts]
        cv.polygon(crown, c * 1.09, min(255, hv + 22))


def cavity_ao(h, radius, strength):
    """Darken pixels that sit below their surroundings (gaps between stones, ruts, cracks)."""
    return np.clip(1.0 - np.maximum(blur(h, radius) - h, 0.0) * strength, 0.0, 1.0)


def tex_dirt():
    out, ss = 512, 2
    s = out * ss
    r = rng_of(303)
    big = fbm(s, 2.3, 31, kmax=8)
    mid = fbm(s, 1.7, 32, kmin=4, kmax=60)
    fine = fbm(s, 0.9, 33, kmin=40)
    t = np.clip(0.5 + (big - 0.5) * 0.9 + (mid - 0.5) * 0.5, 0, 1)
    base = ramp(t, [(0.0, col("6e5c44")), (0.45, col("857154")), (0.75, col("98845f")), (1.0, col("a8956e"))])
    base *= (0.93 + 0.14 * fine)[..., None]
    cv = Canvas(s, base, wrap=True, base_h=60)
    greys = [col("8a8474"), col("9c9482"), col("7a7466"), col("a59a80"), col("6f6a5e"), col("b0a68c")]
    scatter_pebbles(cv, r, 2600, (1.6, 3.4), greys, (95, 130), shadow=0.72)
    scatter_pebbles(cv, r, 420, (3.5, 7.0), greys, (120, 170), shadow=0.66)
    scatter_pebbles(cv, r, 46, (7.0, 13.0), greys, (150, 205), shadow=0.6)
    # dead straw and root fibres pressed into the earth
    for _ in range(1400):
        x, y = r.uniform(0, s, 2)
        a = r.uniform(0, math.tau)
        ln = r.uniform(8, 26)
        c = lerp(col("9a8c62"), col("b7a878"), r.random()) * r.uniform(0.85, 1.05)
        cv.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], c, 84, 1)
    rgb, h = cv.arrays()
    # packed-earth relief: lumps + cracks from ridged noise
    lump = blur(mid, 2.0)
    ridged = 1.0 - np.abs(fbm(s, 1.5, 34, kmin=3, kmax=30) * 2.0 - 1.0)
    cracks = smoothstep(0.975, 0.999, ridged) * smoothstep(0.45, 0.7, big)
    rgb *= (1.0 - 0.10 * cracks)[..., None]
    hfull = h * 0.75 + lump * 0.22 + fine * 0.06 - cracks * 0.08
    rgb *= cavity_ao(blur(h, 1.0), 5.0, 2.6)[..., None]
    rgb = down(rgb, ss)
    hfull = down(hfull, ss)
    mean = rgb.mean(axis=(0, 1))
    rgb = mean + (rgb - mean) * 0.92
    save("dirt_albedo", np.dstack([rgb, np.clip(hfull, 0, 1)]))
    save("dirt_normal", normal_from_height(blur(hfull, 0.6), 7.0))


def tex_shingle():
    out, ss = 512, 2
    s = out * ss
    r = rng_of(404)
    big = fbm(s, 2.0, 41, kmax=10)
    base = ramp(big, [(0.0, col("54514a")), (0.5, col("666258")), (1.0, col("77705f"))])
    cv = Canvas(s, base, wrap=True, base_h=30)
    stones = [col("8e8c84"), col("a19d90"), col("77776f"), col("b3ab97"), col("6a6c6a"), col("9a8f7a"),
              col("84807a"), col("5e6266"), col("ada596"), col("8a7e6c"), col("c2bcab")]
    # three packed layers: small filler first, larger cobbles on top
    scatter_pebbles(cv, r, 9000, (3.0, 5.5), stones, (60, 110), shadow=0.6, ao_pad=1.2)
    scatter_pebbles(cv, r, 3800, (5.0, 9.5), stones, (110, 170), shadow=0.55, ao_pad=1.18)
    scatter_pebbles(cv, r, 520, (9.0, 17.0), stones, (165, 235), shadow=0.5, ao_pad=1.15)
    rgb, h = cv.arrays()
    fine = fbm(s, 0.8, 42, kmin=60)
    rgb *= (0.94 + 0.12 * fine)[..., None]
    rgb *= cavity_ao(blur(h, 1.2), 7.0, 2.2)[..., None]
    rgb = down(rgb, ss)
    h = down(blur(h, 1.2), ss)
    mean = rgb.mean(axis=(0, 1))
    rgb = mean + (rgb - mean) * 0.9
    save("shingle_albedo", np.dstack([rgb, h]))   # the beach reuses the dirt normal map (saves a sampler)


# ----------------------------------------------------------------------------- rock (triplanar)
def tex_rock():
    s = 512
    r = rng_of(505)
    big = fbm(s, 2.4, 51, kmax=7)
    mid = fbm(s, 1.9, 52, kmin=3, kmax=40)
    fine = fbm(s, 1.1, 53, kmin=24)
    # fracture network: warped Voronoi cell borders (blocky joints) plus faint parallel strata
    pts = r.uniform(0, s, (34, 2))
    tiled = np.concatenate([pts + np.array([ox, oy]) for ox in (-s, 0, s) for oy in (-s, 0, s)])
    gy, gx = np.mgrid[0:s, 0:s].astype(np.float64)
    wx = (fbm(s, 2.0, 54, kmax=14) - 0.5) * 70
    wy = (fbm(s, 2.0, 55, kmax=14) - 0.5) * 70
    d, idx = cKDTree(tiled).query(np.stack([gx + wx, gy + wy], axis=-1).reshape(-1, 2), k=2)
    edge = (d[:, 1] - d[:, 0]).reshape(s, s)
    cell = (idx[:, 0] % len(pts)).reshape(s, s)
    cracks = (1.0 - smoothstep(0.0, 3.2, edge)) * (0.55 + 0.45 * smoothstep(0.3, 0.7, mid))
    facet = (r.random(len(pts))[cell] - 0.5)                      # each block sits at its own level / tone
    strata = 0.5 + 0.5 * np.sin((gy + wy * 0.6 + gx * 0.25) / s * math.tau * 9.0 + big * 5.0)
    strata = smoothstep(0.82, 0.98, strata) * 0.5
    h = np.clip(0.45 + facet * 0.35 + (big - 0.5) * 0.3 + (mid - 0.5) * 0.3 + (fine - 0.5) * 0.14 - cracks * 0.55 - strata * 0.2, 0, 1)
    t = np.clip(0.5 + (big - 0.5) * 0.6 + (mid - 0.5) * 0.5 + facet * 0.35, 0, 1)
    rgb = ramp(t, [(0.0, col("5e5e58")), (0.4, col("76746c")), (0.7, col("8a867a")), (1.0, col("9c9788"))])
    warm = fbm(s, 2.2, 56, kmax=9)
    rgb = lerp(rgb, rgb * np.array([1.08, 1.0, 0.88]), smoothstep(0.55, 0.9, warm)[..., None])
    rgb *= (0.90 + 0.2 * fine)[..., None]
    rgb *= (1.0 - 0.5 * blur(cracks, 0.8) - 0.18 * strata)[..., None]
    rgb *= cavity_ao(h, 6.0, 1.2)[..., None]
    # crustose lichen: pale grey-green and ochre blotches with crisp-ish edges
    for seed, colour, thr, amount in ((57, col("949a84"), 0.72, 0.5), (58, col("a08f58"), 0.82, 0.45), (59, col("bdbeae"), 0.86, 0.45)):
        blot = fbm(s, 1.9, seed, kmin=4, kmax=50)
        m = smoothstep(thr, thr + 0.05, blot) * (0.6 + 0.4 * fbm(s, 0.9, seed + 20, kmin=50)) * amount
        m *= 1.0 - np.clip(cracks * 2.0, 0, 1)
        rgb = lerp(rgb, colour * (0.9 + 0.2 * fine)[..., None], m[..., None])
    save("rock_albedo", rgb)
    save("rock_normal", normal_from_height(blur(h, 0.7), 9.0))


# ----------------------------------------------------------------------------- water
def tex_water():
    s = 512
    r = rng_of(606)
    # sum of wave trains with integer wave vectors (tileable), biased toward one wind direction
    yy, xx = np.mgrid[0:s, 0:s] / s
    h = np.zeros((s, s))
    for _ in range(90):
        k = r.uniform(3, 26)
        a = r.normal(0.5, 0.75)
        kx, ky = round(k * math.cos(a)), round(k * math.sin(a))
        if kx == 0 and ky == 0:
            continue
        kk = math.hypot(kx, ky)
        ph = r.uniform(0, math.tau)
        w = np.sin((xx * kx + yy * ky) * math.tau + ph)
        h += (1.0 - np.abs(w)) ** 1.6 * kk ** -1.15   # peaked crests, flat troughs
    h += (fbm(s, 1.8, 61, kmin=8) - 0.5) * 0.25
    h = (h - h.min()) / (h.max() - h.min())
    save("water_normal", normal_from_height(blur(h, 1.0), 26.0))
    # detail channels: R = foam filaments and patches, G = soft blotches (foam break-up), B = fine noise
    def ridge(seed, kmin, kmax, beta=1.6):
        return 1.0 - np.abs(fbm(s, beta, seed, kmin=kmin, kmax=kmax) * 2.0 - 1.0)
    blotch = fbm(s, 1.9, 64, kmin=2, kmax=18)
    thread = np.maximum(smoothstep(0.86, 0.985, ridge(62, 3, 34)), 0.8 * smoothstep(0.90, 0.99, ridge(63, 9, 90)))
    patch = smoothstep(0.60, 0.80, fbm(s, 1.5, 65, kmin=5, kmax=60)) * smoothstep(0.45, 0.7, blotch)
    bubbles = smoothstep(0.80, 0.95, fbm(s, 0.7, 68, kmin=50)) * 0.5
    lace = np.clip(thread * (0.45 + 0.9 * blotch) + patch * (0.55 + 0.45 * bubbles) + bubbles * patch, 0, 1)
    soft = fbm(s, 2.1, 66, kmax=12)
    fine = fbm(s, 0.9, 67, kmin=20)
    save("water_detail", np.dstack([blur(lace, 0.6), soft, fine]))


# ----------------------------------------------------------------------------- macro variation
def tex_macro():
    s = 256
    a = fbm(s, 2.3, 71, kmax=9)
    b = fbm(s, 1.9, 72, kmin=2, kmax=24)
    c = fbm(s, 1.5, 73, kmin=4, kmax=64)
    d = fbm(s, 2.0, 74, kmax=16)
    save("macro_noise", np.dstack([a, b, c, d]))


# ----------------------------------------------------------------------------- track strip
def tex_track():
    """Vehicle track cross-section strip. U runs across the track (2.47 m), V along it (4.93 m), tiling in V.
    R = albedo multiplier (0.5 = neutral), G = wetness / mud sheen, B = across-track slope (0.5 = flat),
    A = bare-earth coverage (1 = fully worn, 0 = grass)."""
    w, hgt = 256, 512
    r = rng_of(808)
    u = (np.arange(w) + 0.5) / w
    uu = np.tile(u, (hgt, 1))

    def n1(seed, kmax, amp):     # 1D-in-V tileable wobble
        return (fbm(512, 2.0, seed, kmax=kmax)[:hgt, 0] - 0.5) * amp

    wob = np.tile(n1(81, 5, 0.035)[:, None], (1, w))
    edge_l = np.tile(n1(82, 9, 0.10)[:, None], (1, w))
    edge_r = np.tile(n1(83, 9, 0.10)[:, None], (1, w))
    n2d = np.tile(fbm(512, 1.7, 84, kmin=2), (1, 1))[:hgt, :w]
    n2f = fbm(512, 1.0, 85, kmin=24)[:hgt, :w]
    # the texture is 256x512 but noise tiles at 512: fold so V still wraps
    n2d = (n2d + np.roll(n2d[::-1], 0, 0)) * 0.5
    n2f = (n2f + n2f[::-1]) * 0.5
    c = uu - 0.5 + wob
    rut_c = 0.30
    rut_w = 0.055
    # each wheel line wanders and fades on its own, so the ruts never read as ruled lines
    wl = np.tile(n1(86, 7, 0.07)[:, None], (1, w))
    wr = np.tile(n1(87, 7, 0.07)[:, None], (1, w))
    sl = np.tile((0.55 + 0.9 * (n1(88, 6, 1.0) + 0.5))[:, None], (1, w)).clip(0.35, 1.0)
    sr = np.tile((0.55 + 0.9 * (n1(89, 6, 1.0) + 0.5))[:, None], (1, w)).clip(0.35, 1.0)
    ruts = np.exp(-((c + rut_c + wl) / rut_w) ** 2) * sl + np.exp(-((c - rut_c + wr) / rut_w) ** 2) * sr
    hump = np.exp(-(c / 0.11) ** 2)
    shoulder = smoothstep(0.385 + 0.6 * (edge_l * (c < 0) + edge_r * (c >= 0)), 0.485, np.abs(c))
    # tyre lugs: chevron bars inside each rut, faint and broken
    vv = np.tile(((np.arange(hgt) + 0.5) / hgt)[:, None], (1, w))
    lug = 0.5 + 0.5 * np.sin((vv * 46.0 + (np.abs(c) - rut_c) * 9.0 * np.sign(c)) * math.tau)
    lug = smoothstep(0.55, 0.9, lug) * ruts * smoothstep(0.35, 0.7, n2d)
    height = -ruts * 0.55 + hump * 0.18 - lug * 0.15 + (n2d - 0.5) * 0.25 + (n2f - 0.5) * 0.06
    dark = 0.5 - ruts * (0.16 + 0.10 * n2d) - lug * 0.08 + hump * 0.03 + (n2d - 0.5) * 0.10
    wet = np.clip(ruts * smoothstep(0.50, 0.78, blur(n2d, 3)) * 1.3, 0, 1)
    dark -= wet * 0.10
    cover = np.clip(1.0 - shoulder - hump * (0.25 + 0.9 * smoothstep(0.45, 0.8, n2d)), 0, 1)
    cover = np.clip(cover * (0.82 + 0.36 * n2d), 0, 1)
    slope = np.gradient(blur(height, 1.5), axis=1) * 18.0
    save("track_strip", np.dstack([np.clip(dark, 0, 1), wet, np.clip(0.5 - slope, 0, 1), cover]))


# ----------------------------------------------------------------------------- previews
def sheet(name, files, cell=256, cols=4, bg=(70, 70, 70)):
    imgs = []
    for f in files:
        p = os.path.join(OUT, f + ".png")
        if os.path.exists(p):
            imgs.append((f, Image.open(p)))
    if not imgs:
        return
    rows = (len(imgs) + cols - 1) // cols
    sh = Image.new("RGB", (cols * cell, rows * cell), bg)
    for i, (f, im) in enumerate(imgs):
        if im.mode == "RGBA":
            a = np.asarray(im, dtype=np.float64) / 255.0
            if "albedo" in f or f in ("macro_noise", "track_strip"):
                im = to_img(a[..., :3])
            else:   # cut-outs over a checker so the alpha edge is visible
                chk = ((np.indices(a.shape[:2]).sum(axis=0) // 16) % 2)[..., None] * 0.12 + 0.35
                im = to_img(a[..., :3] * a[..., 3:] + chk * (1 - a[..., 3:]))
        im = im.convert("RGB")
        im.thumbnail((cell, cell), Image.LANCZOS)
        sh.paste(im, ((i % cols) * cell, (i // cols) * cell))
    sh.save(os.path.join(PREVIEW, "preview_" + name + ".png"))
    print("preview", name)


GROUND = {"grass": tex_grass, "dirt": tex_dirt, "shingle": tex_shingle, "rock": tex_rock,
          "water": tex_water, "macro": tex_macro, "track": tex_track}
TARGETS = dict(GROUND)

if __name__ == "__main__":
    try:
        import gen_nature_foliage as foliage   # foliage cards live in a sibling module
        TARGETS.update(foliage.TARGETS)
    except ImportError:
        foliage = None
    names = sys.argv[1:] or list(TARGETS.keys())
    for n in names:
        TARGETS[n]()
    sheet("ground", ["grass_albedo", "grass_normal", "dirt_albedo", "dirt_normal", "shingle_albedo",
                     "rock_albedo", "rock_normal", "water_normal", "water_detail", "macro_noise", "track_strip"])
    if foliage:
        foliage.previews(sheet)
