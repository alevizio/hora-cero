#!/usr/bin/env python3
"""Alpha cut-out foliage cards for the game (imported by gen_nature_textures.py).

foliage_atlas.png (1024x1024, 4x4 grid of 256 px cells)
    col 0-1, rows 0-1 : spruce bough A / bough B (256x512 each, base at the bottom edge)
    col 2,   rows 0-1 : spruce leader (tree top, side view)
    col 3,   rows 0-1 : four 64x512 bark strips: spruce, pine, birch, dead branch wood
    col 0-1, rows 2-3 : broadleaf cluster (512x512)
    col 2,   row 2    : shrub cluster          col 3, row 2 : birch spray
    col 2,   row 3    : pine needle tuft       col 3, row 3 : small-leaf cluster (saplings / shrubs)
groundcover_atlas.png (512x512)
    rows 0-1: four upright 128x256 cards: meadow tuft, seeding grass, dry sedge, dock weed
    rows 2-3 (upper half): four upright 128x128 cards: white umbels, buttercups, thrift, fern
    rows 3   (lower half): four flat 128x128 decals: twigs, leaf litter, pebbles, rosette
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

import gen_nature_textures as base
from gen_nature_textures import col, lerp, rng_of, fbm, smoothstep, save, to_img


class Card:
    """Supersampled RGBA cut-out painter."""

    def __init__(self, w, h, ss=3, fill=(0.2, 0.3, 0.2)):
        self.w, self.h, self.ss = w, h, ss
        self.rgb = Image.new("RGB", (w * ss, h * ss), tuple(int(v * 255) for v in fill))
        self.a = Image.new("L", (w * ss, h * ss), 0)
        self.d = ImageDraw.Draw(self.rgb)
        self.da = ImageDraw.Draw(self.a)

    @staticmethod
    def _c(rgb):
        return tuple(int(max(0, min(255, v * 255))) for v in rgb)

    def line(self, pts, rgb, width):
        s = self.ss
        q = [(x * s, y * s) for x, y in pts]
        w = max(1, int(round(width * s)))
        self.d.line(q, fill=self._c(rgb), width=w)
        self.da.line(q, fill=255, width=w)

    def poly(self, pts, rgb):
        s = self.ss
        q = [(x * s, y * s) for x, y in pts]
        self.d.polygon(q, fill=self._c(rgb))
        self.da.polygon(q, fill=255)

    def dot(self, x, y, rad, rgb):
        s = self.ss
        box = [(x - rad) * s, (y - rad) * s, (x + rad) * s, (y + rad) * s]
        self.d.ellipse(box, fill=self._c(rgb))
        self.da.ellipse(box, fill=255)

    def finish(self, pad=5, shade=None):
        rgb = np.asarray(self.rgb, dtype=np.float64) / 255.0
        a = np.asarray(self.a, dtype=np.float64) / 255.0
        if shade is not None:
            rgb = rgb * shade(rgb.shape[0], rgb.shape[1])[..., None]
        pm = base.down(rgb * a[..., None], self.ss)
        al = base.down(a, self.ss)
        # keep a clear margin so neighbouring atlas cells never bleed in through the mip chain
        m = np.zeros_like(al)
        m[pad:-pad, pad:-pad] = 1.0
        al *= m
        out = np.where(al[..., None] > 1e-3, pm / np.maximum(al[..., None], 1e-3), 0.0)
        return bleed(np.dstack([out, al]))


def bleed(rgba, thr=0.35):
    """Copy the nearest opaque colour into transparent texels (prevents dark mip fringes)."""
    solid = rgba[..., 3] > thr
    if not solid.any():
        return rgba
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    out = rgba.copy()
    filled = rgba[..., :3][idx[0], idx[1]]
    out[..., :3] = np.where(solid[..., None], rgba[..., :3], filled)
    # soften the copied colour so partially covered edge texels take a local average
    soft = np.stack([ndi.gaussian_filter(out[..., i], 1.5) for i in range(3)], axis=-1)
    out[..., :3] = np.where(solid[..., None], out[..., :3], soft)
    return out


def leaf_poly(x, y, ang, length, width, skew=0.0, n=7):
    """Pointed oval leaf outline starting at its stalk end."""
    pts_l, pts_r = [], []
    dx, dy = math.cos(ang), math.sin(ang)
    for i in range(n + 1):
        t = i / n
        w = width * math.sin(math.pi * t ** 0.72) * 0.5
        cx = x + dx * length * t - dy * skew * length * math.sin(math.pi * t) * 0.5
        cy = y + dy * length * t + dx * skew * length * math.sin(math.pi * t) * 0.5
        pts_l.append((cx - dy * w, cy + dx * w))
        pts_r.append((cx + dy * w, cy - dx * w))
    return pts_l, pts_r[::-1]


def draw_leaf(card, r, x, y, ang, length, width, c, vein=True):
    left, right = leaf_poly(x, y, ang, length, width, skew=r.normal(0, 0.12))
    mid = [((l[0] + rr[0]) * 0.5, (l[1] + rr[1]) * 0.5) for l, rr in zip(left, right[::-1])]
    # two-tone blade: one half catches the sky, the other sits in its own shade
    card.poly(left + mid[::-1], c * 1.06)
    card.poly(mid + right, c * 0.88)
    if vein:
        card.line([mid[0], mid[-1]], c * 1.2, 0.45)


# ----------------------------------------------------------------------------- conifers
SPRUCE = (col("1f3226"), col("34503a"), col("4f6c48"), col("74895a"))
PINE = (col("24382e"), col("3d5846"), col("5b7658"), col("86986c"))


def needle_twig(card, r, twigs, pal, needle, width, mass=True):
    """twigs: list of (points, level 0..1, tipness fn). Draw backing mass then needles, deep to bright."""
    dark, mid, light, tip = pal
    if mass:
        for pts, lvl in twigs:
            card.line(pts, lerp(dark, mid, 0.25) * 0.9, needle * 1.25)
    order = sorted(range(len(twigs)), key=lambda i: twigs[i][1])
    for i in order:
        pts, lvl = twigs[i]
        n = len(pts)
        for j in range(n - 1):
            (x0, y0), (x1, y1) = pts[j], pts[j + 1]
            seg = math.hypot(x1 - x0, y1 - y0)
            a = math.atan2(y1 - y0, x1 - x0)
            tipn = (j + 1) / (n - 1)
            count = max(1, int(seg / 1.15))
            for k in range(count):
                t = (k + r.random()) / count
                px, py = lerp(x0, x1, t), lerp(y0, y1, t)
                for side in (-1, 1):
                    na = a + side * r.uniform(0.55, 1.05)
                    ln = needle * r.uniform(0.7, 1.15) * (1.0 - 0.35 * tipn)
                    b = lvl * 0.55 + tipn * 0.45 + r.normal(0, 0.10)
                    c = lerp(dark, mid, min(1, b * 2.2)) if b < 0.45 else (lerp(mid, light, (b - 0.45) / 0.35) if b < 0.8 else lerp(light, tip, min(1, (b - 0.8) / 0.25)))
                    card.line([(px, py), (px + math.cos(na) * ln, py + math.sin(na) * ln)], c, width)
        # the woody twig shows through near its base
        if lvl > 0.35 and n > 3:
            card.line(pts[: max(2, n // 3)], col("4a3d2c"), 0.9)


def grow(x, y, ang, length, r, wobble=0.10, step=5.0, curl=0.0):
    pts = [(x, y)]
    n = max(2, int(length / step))
    for i in range(n):
        ang += r.normal(0, wobble) + curl / n
        x += math.cos(ang) * length / n
        y += math.sin(ang) * length / n
        pts.append((x, y))
    return pts


def spruce_bough(seed, w=256, h=512, kind="bough"):
    r = rng_of(seed)
    card = Card(w, h, ss=3, fill=tuple(SPRUCE[1]))
    twigs = []
    cx = w * 0.5
    if kind == "leader":
        length, lmax, node = h - 34, w * 0.44, 12.0
    else:
        length, lmax, node = h - 30, w * 0.60, 11.5
    main = grow(cx, h - 8, -math.pi / 2, length, r, wobble=0.012 if kind == "leader" else 0.02, step=8.0)
    twigs.append((main, 0.9))
    acc = 0.0
    side = 1
    for i in range(1, len(main)):
        (x0, y0), (x1, y1) = main[i - 1], main[i]
        acc += math.hypot(x1 - x0, y1 - y0)
        if acc < node:
            continue
        acc = 0.0
        t = i / (len(main) - 1)
        a_main = math.atan2(y1 - y0, x1 - x0)
        for sgn in (side, -side):
            if kind == "leader":
                prof = (1.0 - t) ** 0.85 * 0.96 + 0.04
                sweep = lerp(1.95, 1.05, t ** 0.7) + r.normal(0, 0.10)      # drooping low, up-swept near the tip
                curl = lerp(0.5, -0.2, t) * sgn
            else:
                prof = (0.55 + 0.45 * smoothstep(0.0, 0.22, t)) * (1.0 - t) ** 0.55
                sweep = lerp(1.12, 0.66, t) + r.normal(0, 0.09)
                curl = -0.25 * sgn
            ln = lmax * prof * r.uniform(0.82, 1.08)
            if ln < 6:
                continue
            tw = grow(x1, y1, a_main + sgn * sweep, ln, r, wobble=0.07, step=6.0, curl=curl)
            lvl = r.uniform(0.25, 1.0)
            twigs.append((tw, lvl))
            # secondary sprays
            sub_acc, s2 = 0.0, 1
            for j in range(1, len(tw) - 1):
                sub_acc += 6.0
                if sub_acc < 11.0:
                    continue
                sub_acc = 0.0
                tt = j / (len(tw) - 1)
                a_tw = math.atan2(tw[j][1] - tw[j - 1][1], tw[j][0] - tw[j - 1][0])
                sl = ln * 0.44 * (1.0 - tt * 0.6) * r.uniform(0.7, 1.15)
                if sl > 5:
                    twigs.append((grow(tw[j][0], tw[j][1], a_tw + s2 * r.uniform(0.6, 0.95), sl, r, wobble=0.08, step=5.0), min(1.0, lvl + r.uniform(-0.2, 0.25))))
                s2 = -s2
        side = -side
    needle_twig(card, r, twigs, SPRUCE, needle=9.5 if kind == "bough" else 8.0, width=1.0)

    def shade(hh, ww):
        yy, xx = np.mgrid[0:hh, 0:ww]
        v = yy / hh
        u = np.abs(xx / ww - 0.5) * 2.0
        if kind == "leader":
            return 0.80 + 0.26 * (1.0 - v) + 0.10 * u
        # darker toward the trunk end and along the spine, lighter outer fringe
        return 0.66 + 0.36 * (1.0 - v) ** 0.8 + 0.14 * u
    return card.finish(shade=shade)


def pine_tuft(seed, s=256):
    r = rng_of(seed)
    card = Card(s, s, ss=3, fill=tuple(PINE[1]))
    dark, mid, light, tip = PINE
    c0 = s * 0.5
    bursts = []
    # woody forks from the centre, each ending in a needle burst
    for i in range(9):
        a = i / 9 * math.tau + r.normal(0, 0.25)
        ln = s * r.uniform(0.16, 0.33)
        tw = grow(c0, c0, a, ln, r, wobble=0.18, step=7.0)
        card.line(tw, col("5a4632") * r.uniform(0.85, 1.1), 2.2)
        bursts.append((tw[-1][0], tw[-1][1], a, r.uniform(0.3, 1.0)))
        if r.random() < 0.7:
            k = len(tw) // 2
            tw2 = grow(tw[k][0], tw[k][1], a + r.choice([-1, 1]) * r.uniform(0.6, 1.0), ln * 0.55, r, wobble=0.15, step=6.0)
            card.line(tw2, col("5a4632") * 0.95, 1.6)
            bursts.append((tw2[-1][0], tw2[-1][1], a, r.uniform(0.2, 0.9)))
    bursts.append((c0, c0, 0.0, 1.0))
    for x, y, a, lvl in sorted(bursts, key=lambda b: b[3]):
        rad = s * r.uniform(0.13, 0.19)
        card.dot(x, y, rad * 0.55, lerp(dark, mid, 0.3))
        n = 150
        for k in range(n):
            na = r.uniform(0, math.tau)
            ln = rad * r.uniform(0.55, 1.1)
            b = lvl * 0.5 + r.random() * 0.5 + (0.12 if k > n * 0.6 else -0.1)
            c = lerp(dark, mid, min(1, b * 2.0)) if b < 0.5 else lerp(mid, light, min(1, (b - 0.5) / 0.4))
            if b > 0.92:
                c = lerp(light, tip, 0.6)
            ex, ey = x + math.cos(na) * ln, y + math.sin(na) * ln
            card.line([(x + math.cos(na) * rad * 0.1, y + math.sin(na) * rad * 0.1), (ex, ey)], c, 1.0)

    def shade(hh, ww):
        yy, xx = np.mgrid[0:hh, 0:ww]
        d = np.hypot(xx / ww - 0.5, yy / hh - 0.5) * 2.0
        return 0.78 + 0.26 * np.clip(d, 0, 1)
    return card.finish(shade=shade)


# ----------------------------------------------------------------------------- broadleaf
def leaf_cluster(seed, s, pal, leaf_len, leaf_w, count, reach=0.44, hang=0.0, twig_col="4d4030", lobes=5):
    """Dense rounded spray of leaves: lobed outline, leaves radiate outward, deep ones dark, top ones bright."""
    r = rng_of(seed)
    card = Card(s, s, ss=3, fill=tuple(pal[1]))
    dark, mid, light, tip = pal
    c0 = s * 0.5
    ph = r.uniform(0, math.tau, 3)

    def radius(a):       # irregular, lobed silhouette
        return s * reach * (0.80 + 0.14 * math.sin(a * lobes + ph[0]) + 0.08 * math.sin(a * (lobes * 2 + 1) + ph[1]) + 0.05 * math.sin(a * 2 + ph[2]))
    # a few woody twigs underneath
    for i in range(7):
        a = i / 7 * math.tau + r.normal(0, 0.3)
        tw = grow(c0, c0, a, radius(a) * 0.8, r, wobble=0.16, step=s * 0.04, curl=hang * math.cos(a))
        card.line(tw, col(twig_col) * r.uniform(0.8, 1.1), 1.6)
    leaves = []
    for _ in range(count):
        a = r.uniform(0, math.tau)
        d = radius(a) * r.random() ** 0.62
        d = max(0.0, d - leaf_len * 0.55)                      # leaf grows outward from here, tip lands near the outline
        x, y = c0 + math.cos(a) * d, c0 + math.sin(a) * d
        if hang > 0.0:
            la = lerp(a, math.pi / 2, hang) + r.normal(0, 0.5)
        else:
            la = a + r.normal(0, 0.75)
        rel = d / (s * reach)
        leaves.append((r.random() * 0.62 + rel * 0.38, x, y, la, leaf_len * r.uniform(0.72, 1.18) * (1.0 - 0.2 * rel)))
    leaves.sort(key=lambda q: q[0])
    for hgt, x, y, la, L in leaves:
        b = hgt + r.normal(0, 0.07)
        c = lerp(dark, mid, min(1, max(0, b) * 2.3)) if b < 0.43 else lerp(mid, light, min(1, (b - 0.43) / 0.4))
        if b > 0.88 and r.random() < 0.5:
            c = lerp(light, tip, 0.7)
        draw_leaf(card, r, x, y, la, L, L * leaf_w * r.uniform(0.85, 1.15), c)

    def shade(hh, ww):
        yy, xx = np.mgrid[0:hh, 0:ww]
        d = np.hypot(xx / ww - 0.5, yy / hh - 0.5) * 2.0
        return 0.80 + 0.24 * np.clip(d, 0, 1) ** 1.3
    return card.finish(shade=shade)


# ----------------------------------------------------------------------------- bark
def bark_strip(kind, w=64, h=512, seed=0):
    r = rng_of(900 + seed)
    n1 = fbm(512, 1.8, 910 + seed, kmin=2)[:h, :w]
    fine = fbm(512, 1.0, 920 + seed, kmin=30)[:h, :w]
    # vertical furrows: noise stretched along the trunk
    furrow = ndi.zoom(fbm(64, 1.6, 930 + seed, kmin=3), (8, 1), order=1, mode="wrap")[:h, :w]
    ridged = 1.0 - np.abs(furrow * 2.0 - 1.0)
    v = (np.arange(h) / h)[:, None] * np.ones((1, w))
    if kind == "spruce":
        t = np.clip(0.5 + (furrow - 0.5) * 1.1 + (fine - 0.5) * 0.3, 0, 1)
        rgb = base.ramp(t, [(0, col("3c342a")), (0.5, col("5e5345")), (1, col("7b7060"))])
        rgb *= (1.0 - 0.45 * smoothstep(0.88, 0.99, ridged))[..., None]
    elif kind == "pine":
        t = np.clip(0.5 + (furrow - 0.5) * 1.0 + (fine - 0.5) * 0.3, 0, 1)
        low = base.ramp(t, [(0, col("3d352c")), (0.5, col("655a4b")), (1, col("857a66"))])
        high = base.ramp(t, [(0, col("6e4a32")), (0.5, col("946644")), (1, col("b0865e"))])
        k = smoothstep(0.62, 0.30, v + (n1 - 0.5) * 0.25)        # top of the strip = top of the tree
        rgb = lerp(low, high, k[..., None])
        rgb *= (1.0 - 0.5 * smoothstep(0.86, 0.99, ridged) * (1.0 - 0.5 * k))[..., None]
    elif kind == "birch":
        rgb = np.empty((h, w, 3))
        rgb[:] = col("d6d4c6")
        rgb *= (0.90 + 0.14 * n1 + 0.06 * fine)[..., None]
        img = to_img(rgb)
        d = ImageDraw.Draw(img)
        for _ in range(150):                                       # lenticels: short horizontal dashes
            x, y = r.uniform(-8, w), r.uniform(0, h)
            ln = r.uniform(5, 26)
            g = int(r.uniform(60, 130))
            d.line([(x, y), (x + ln, y + r.normal(0, 0.6))], fill=(g, g - 4, g - 12), width=1)
        for _ in range(9):                                         # black branch scars
            x, y = r.uniform(4, w - 4), r.uniform(10, h - 10)
            sz = r.uniform(5, 12)
            d.polygon([(x - sz, y), (x, y - sz * 0.9), (x + sz, y), (x, y + sz * 0.45)], fill=(38, 36, 32))
        rgb = np.asarray(img, dtype=np.float64) / 255.0
        rough = smoothstep(0.80, 1.0, v + (n1 - 0.5) * 0.2)        # dark, cracked foot of the trunk
        rgb = lerp(rgb, rgb * np.array([0.38, 0.36, 0.33]), rough[..., None])
        rgb = np.stack([ndi.gaussian_filter(rgb[..., i], 0.6) for i in range(3)], axis=-1)
    else:   # weathered branch wood
        t = np.clip(0.5 + (furrow - 0.5) * 0.9 + (fine - 0.5) * 0.3, 0, 1)
        rgb = base.ramp(t, [(0, col("463c30")), (0.5, col("675b4b")), (1, col("8b8070"))])
    # round shading across the strip is left to the mesh normals; only add soft grime at the foot
    rgb *= (1.0 - 0.22 * smoothstep(0.90, 1.0, v))[..., None]
    return np.dstack([rgb, np.ones((h, w))])


# ----------------------------------------------------------------------------- atlas assembly
BROADLEAF = (col("2a3f26"), col("435a34"), col("5f7742"), col("839456"))
SHRUB = (col("2a4024"), col("44602f"), col("67803f"), col("8a9a52"))
BIRCH = (col("3a5229"), col("566f36"), col("7a8c46"), col("9ea85a"))
SMALL = (col("304a2a"), col("4e6a38"), col("72883f"), col("9aa856"))


def tex_foliage_atlas():
    atlas = np.zeros((1024, 1024, 4))
    atlas[..., :3] = col("3a5238")
    atlas[0:512, 0:256] = spruce_bough(11)
    atlas[0:512, 256:512] = spruce_bough(12)
    atlas[0:512, 512:768] = spruce_bough(13, kind="leader")
    for i, kind in enumerate(("spruce", "pine", "birch", "wood")):
        atlas[0:512, 768 + i * 64:832 + i * 64] = bark_strip(kind, seed=i)
    atlas[512:1024, 0:512] = leaf_cluster(21, 512, BROADLEAF, leaf_len=27, leaf_w=0.56, count=1500, reach=0.46, lobes=6)
    atlas[512:768, 512:768] = leaf_cluster(22, 256, SHRUB, leaf_len=21, leaf_w=0.5, count=430, reach=0.455, lobes=4)
    atlas[512:768, 768:1024] = leaf_cluster(23, 256, BIRCH, leaf_len=15, leaf_w=0.74, count=420, reach=0.45, hang=0.7, twig_col="3a3028", lobes=6)
    atlas[768:1024, 512:768] = pine_tuft(24)
    atlas[768:1024, 768:1024] = leaf_cluster(25, 256, SMALL, leaf_len=14, leaf_w=0.6, count=560, reach=0.455, lobes=7)
    save("foliage_atlas", bleed_cells(atlas))


def bleed_cells(atlas):
    return atlas


# ----------------------------------------------------------------------------- ground cover
GRASS = (col("34462a"), col("52683a"), col("75864c"), col("9aa262"))
STRAW = (col("5e5a40"), col("7c7654"), col("98906a"), col("aea681"))
MARRAM = (col("46523e"), col("617058"), col("818c6e"), col("9ea488"))   # blue-grey dune grass


def blade(card, r, x, y, ang, length, w0, c0, c1, curl):
    """Tapered curved grass blade from the root (x,y); colour runs dark root -> light tip."""
    n = 6
    pts = [(x, y)]
    a = ang
    for i in range(n):
        a += curl / n
        x += math.cos(a) * length / n
        y += math.sin(a) * length / n
        pts.append((x, y))
    for i in range(n):
        t = i / n
        card.line([pts[i], pts[i + 1]], lerp(c0, c1, t), max(0.5, w0 * (1.0 - t * 0.8)))
    return pts[-1]


def tuft(seed, pal, n=110, height=215, spread=0.62, w0=3.6, seeds=0, w=128, h=256):
    r = rng_of(seed)
    card = Card(w, h, ss=4, fill=tuple(pal[1]))
    dark, mid, light, tip = pal
    tips = []
    order = sorted(range(n), key=lambda i: r.random())
    for k, i in enumerate(order):
        t = k / n
        a = -math.pi / 2 + r.normal(0, spread * 0.55)
        a = max(-math.pi / 2 - spread * 1.3, min(-math.pi / 2 + spread * 1.3, a))
        L = height * r.uniform(0.35, 1.0) * (1.0 - 0.35 * abs(a + math.pi / 2) / (spread * 1.3))
        cbase = lerp(dark, mid, t) * r.uniform(0.9, 1.08)
        ctip = lerp(mid, light, 0.3 + 0.7 * t) * r.uniform(0.92, 1.08)
        if r.random() < 0.10:
            ctip = lerp(ctip, STRAW[2], 0.7)
        end = blade(card, r, w * 0.5 + r.normal(0, 9.0), h - 7, a, L, w0 * r.uniform(0.7, 1.2), cbase, ctip, (a + math.pi / 2) * r.uniform(0.3, 1.1))
        tips.append(end)
    for i in range(seeds):
        x, y = tips[int(r.integers(len(tips)))]
        a = -math.pi / 2 + r.normal(0, 0.25)
        stalk = blade(card, r, w * 0.5 + r.normal(0, 4.0), h - 7, a, height * r.uniform(0.95, 1.1), 1.3, mid, STRAW[1], r.normal(0, 0.25))
        for j in range(16):       # feathery seed head
            t = j / 16
            px = stalk[0] - math.cos(a) * t * 34 + r.normal(0, 0.6)
            py = stalk[1] - math.sin(a) * t * 34
            for sgn in (-1, 1):
                card.line([(px, py), (px + sgn * r.uniform(2, 5), py - r.uniform(2, 6))], lerp(STRAW[0], STRAW[2], r.random()), 0.9)
    return card.finish(pad=3)


def weed_dock(seed, w=128, h=256):
    r = rng_of(seed)
    card = Card(w, h, ss=4, fill=tuple(BROADLEAF[1]))
    pal = (col("32482a"), col("4c6636"), col("6c8244"), col("8f9c56"))
    for k in range(9):
        a = -math.pi / 2 + (k - 4) * 0.30 + r.normal(0, 0.08)
        L = r.uniform(95, 150) * (1.0 - 0.25 * abs(k - 4) / 4)
        c = lerp(pal[0], pal[2], k / 8 if k % 2 else 1 - k / 8) * r.uniform(0.9, 1.1)
        draw_leaf(card, r, w * 0.5 + r.normal(0, 3), h - 8, a, L, L * 0.30, c)
    # rusty seed spike
    stalk = blade(card, r, w * 0.5, h - 8, -math.pi / 2 + 0.05, 215, 1.8, pal[1], col("6e5236"), 0.08)
    for j in range(90):
        t = r.random()
        px, py = lerp(w * 0.5, stalk[0], 0.45 + 0.55 * t), lerp(h - 8, stalk[1], 0.45 + 0.55 * t)
        card.dot(px + r.normal(0, 3.2 * (1 - t * 0.6)), py + r.normal(0, 2), r.uniform(1.0, 2.0), lerp(col("5e4230"), col("806244"), r.random()))
    return card.finish(pad=3)


def flowers(seed, kind, w=128, h=128):
    r = rng_of(seed)
    card = Card(w, h, ss=4, fill=tuple(GRASS[1]))
    dark, mid, light, tip = GRASS
    # low leafy base
    for k in range(60):
        a = -math.pi / 2 + r.normal(0, 0.6)
        blade(card, r, w * 0.5 + r.normal(0, 12), h - 5, a, r.uniform(30, 66), 3.2, lerp(dark, mid, r.random()), lerp(mid, light, r.random()), (a + math.pi / 2) * 0.8)
    heads = []
    for k in range({"umbel": 5, "buttercup": 7, "thrift": 7}[kind]):
        a = -math.pi / 2 + r.normal(0, 0.30)
        end = blade(card, r, w * 0.5 + r.normal(0, 7), h - 5, a, r.uniform(62, 100), 2.0, mid, lerp(mid, light, 0.5), r.normal(0, 0.3))
        heads.append(end)
    for x, y in heads:
        if kind == "umbel":
            # a solid flat-topped flower head (reads as one pale shape, not as loose sparkling dots)
            card.poly([(x - 10, y + 1), (x - 7, y - 4), (x, y - 6), (x + 7, y - 4), (x + 10, y + 1), (x, y + 4)], col("9c9d8a"))
            for j in range(22):
                a = r.uniform(0, math.tau)
                d = 8.5 * math.sqrt(r.random())
                card.dot(x + math.cos(a) * d, y - 1 + math.sin(a) * d * 0.5, r.uniform(1.2, 2.0), lerp(col("a9aa97"), col("c4c3b0"), r.random()))
        elif kind == "buttercup":
            card.dot(x, y, 4.4, col("a58c36"))
            card.dot(x - 0.8, y - 0.8, 2.4, col("bfa94e"))
        else:
            card.dot(x, y, 5.0, col("96586e"))
            for j in range(9):
                a = r.uniform(0, math.tau)
                card.dot(x + math.cos(a) * 2.8, y + math.sin(a) * 2.8, 1.7, lerp(col("a66c82"), col("bd8a9e"), r.random()))
    return card.finish(pad=3)


def fern(seed, w=128, h=128):
    r = rng_of(seed)
    card = Card(w, h, ss=4, fill=tuple(GRASS[1]))
    pal = (col("2e4628"), col("48622f"), col("68803c"), col("8a9a4c"))
    for k, a0 in enumerate((-2.25, -1.85, -1.57, -1.25, -0.9)):
        a = a0 + r.normal(0, 0.06)
        L = r.uniform(85, 112) * (1.0 - 0.2 * abs(k - 2) / 2)
        pts = grow(w * 0.5, h - 5, a, L, r, wobble=0.03, step=5.0, curl=(a + math.pi / 2) * 0.9)
        c = lerp(pal[0], pal[2], r.uniform(0.2, 1.0))
        card.line(pts, c * 0.8, 1.0)
        for j in range(2, len(pts)):
            tt = j / (len(pts) - 1)
            a_p = math.atan2(pts[j][1] - pts[j - 1][1], pts[j][0] - pts[j - 1][0])
            pin = 17 * math.sin(math.pi * tt ** 0.6) + 2
            for sgn in (-1, 1):
                draw_leaf(card, r, pts[j][0], pts[j][1], a_p + sgn * 1.15, pin, pin * 0.34, c * r.uniform(0.9, 1.12), vein=False)
    return card.finish(pad=3)


def decal_twigs(seed, s=128):
    r = rng_of(seed)
    card = Card(s, s, ss=4, fill=(0.35, 0.3, 0.22))
    for k in range(3):
        a = r.uniform(0, math.tau)
        L = r.uniform(60, 100)
        x, y = s * 0.5 - math.cos(a) * L * 0.5 + r.normal(0, 8), s * 0.5 - math.sin(a) * L * 0.5 + r.normal(0, 8)
        tw = grow(x, y, a, L, r, wobble=0.10, step=8.0)
        c = lerp(col("4c4032"), col("7a6a54"), r.random())
        card.line(tw, c * 0.55, 3.4)          # baked contact shadow
        card.line(tw, c, 2.2)
        card.line([(px - 0.5, py - 0.5) for px, py in tw], c * 1.2, 0.8)
        for j in (len(tw) // 3, 2 * len(tw) // 3):
            a2 = a + r.choice([-1, 1]) * r.uniform(0.5, 0.9)
            tw2 = grow(tw[j][0], tw[j][1], a2, L * 0.3, r, wobble=0.1, step=6.0)
            card.line(tw2, c * 0.6, 2.2)
            card.line(tw2, c * 1.05, 1.3)
    return card.finish(pad=3)


def decal_litter(seed, s=128):
    r = rng_of(seed)
    card = Card(s, s, ss=4, fill=(0.4, 0.33, 0.22))
    cols = [col("6e5a38"), col("8a6e40"), col("5c4a30"), col("9a8450"), col("7a5a34"), col("5a5a34")]
    for k in range(26):
        a = r.uniform(0, math.tau)
        d = s * 0.36 * math.sqrt(r.random())
        x, y = s * 0.5 + math.cos(a) * d, s * 0.5 + math.sin(a) * d
        c = cols[int(r.integers(len(cols)))] * r.uniform(0.85, 1.1)
        L = r.uniform(9, 16)
        la = r.uniform(0, math.tau)
        left, right = leaf_poly(x + 0.8, y + 0.8, la, L, L * 0.5)
        card.poly(left + right, c * 0.5)
        draw_leaf(card, r, x, y, la, L, L * 0.5, c)
    return card.finish(pad=3)


def decal_pebbles(seed, s=128):
    r = rng_of(seed)
    card = Card(s, s, ss=4, fill=(0.5, 0.48, 0.44))
    cols = [col("8e8c84"), col("a19d90"), col("77776f"), col("b3ab97"), col("6a6c6a"), col("9a8f7a")]
    for k in range(22):
        a = r.uniform(0, math.tau)
        d = s * 0.38 * r.random() ** 0.7
        x, y = s * 0.5 + math.cos(a) * d, s * 0.5 + math.sin(a) * d
        rad = r.uniform(2.2, 7.5) * (1.0 - 0.5 * d / (s * 0.38))
        c = cols[int(r.integers(len(cols)))] * r.uniform(0.88, 1.08)
        k2 = 8
        wob = r.uniform(0.8, 1.15, k2)
        sq = r.uniform(0.65, 1.0)
        rot = r.uniform(0, math.pi)

        def ring(scale, ox=0.0, oy=0.0):
            out = []
            for j in range(k2):
                t = j / k2 * math.tau
                px, py = math.cos(t) * rad * wob[j] * scale, math.sin(t) * rad * sq * wob[j] * scale
                out.append((x + ox + px * math.cos(rot) - py * math.sin(rot), y + oy + px * math.sin(rot) + py * math.cos(rot)))
            return out
        card.poly(ring(1.18), c * 0.42)
        card.poly(ring(1.0), c)
        card.poly(ring(0.55, -rad * 0.12, -rad * 0.12), c * 1.12)
    return card.finish(pad=3)


def decal_rosette(seed, s=128):
    r = rng_of(seed)
    card = Card(s, s, ss=4, fill=tuple(BROADLEAF[1]))
    pal = (col("34502c"), col("4f6c38"), col("6e8846"), col("8ea058"))
    n = 15
    for k in range(n):
        a = k / n * math.tau * 2.4 + r.normal(0, 0.1)
        L = s * lerp(0.44, 0.24, k / n) * r.uniform(0.9, 1.1)
        c = lerp(pal[0], pal[2], k / n) * r.uniform(0.92, 1.08)
        left, right = leaf_poly(s * 0.5 + 1, s * 0.5 + 1, a, L, L * 0.42)
        card.poly(left + right, c * 0.55)
        draw_leaf(card, r, s * 0.5, s * 0.5, a, L, L * 0.42, c)
    card.dot(s * 0.5, s * 0.5, 3.0, pal[3])
    return card.finish(pad=3)


def tex_groundcover_atlas():
    atlas = np.zeros((512, 512, 4))
    atlas[..., :3] = col("52683a")
    atlas[0:256, 0:128] = tuft(31, GRASS)
    atlas[0:256, 128:256] = tuft(32, GRASS, n=80, height=232, spread=0.5, w0=3.2, seeds=8)
    atlas[0:256, 256:384] = tuft(33, MARRAM, n=95, height=205, spread=0.66, w0=3.2, seeds=3)
    atlas[0:256, 384:512] = weed_dock(34)
    atlas[256:384, 0:128] = flowers(35, "umbel")
    atlas[256:384, 128:256] = flowers(36, "buttercup")
    atlas[256:384, 256:384] = flowers(37, "thrift")
    atlas[256:384, 384:512] = fern(38)
    atlas[384:512, 0:128] = decal_twigs(39)
    atlas[384:512, 128:256] = decal_litter(40)
    atlas[384:512, 256:384] = decal_pebbles(41)
    atlas[384:512, 384:512] = decal_rosette(42)
    save("groundcover_atlas", atlas)


TARGETS = {"foliage_atlas": tex_foliage_atlas, "groundcover_atlas": tex_groundcover_atlas}


def previews(sheet):
    sheet("foliage", ["foliage_atlas", "groundcover_atlas"], cell=1024, cols=2)
