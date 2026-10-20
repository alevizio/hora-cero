"""Small procedural-texture toolkit used by gen_structures_textures.py (numpy / scipy / PIL only).
Conventions: images are float32 arrays [H, W] or [H, W, 3] in sRGB 0..1, y = 0 is the TOP row.
Normal maps are written OpenGL style (+Y / green = up in the image), as Godot expects."""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from PIL import Image


def col(hex_str):
    hex_str = hex_str.lstrip('#')
    return np.array([int(hex_str[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def smooth(t, a=0.0, b=1.0):
    t = np.clip((t - a) / (b - a + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    if np.ndim(t) == 2 and (np.ndim(a) == 3 or np.ndim(b) == 3 or (np.ndim(a) == 1 and len(a) == 3) or (np.ndim(b) == 1 and len(b) == 3)):
        t = t[..., None]
    return a * (1 - t) + b * t


def norm01(a, lo=0.5, hi=99.5):
    l, h = np.percentile(a, [lo, hi])
    return np.clip((a - l) / (h - l + 1e-9), 0, 1).astype(np.float32)


def fbm(shape, beta=2.0, seed=0, ax=1.0, ay=1.0, lo=1.0, hi=None):
    """Tileable 1/f^beta noise in 0..1. ax/ay > 1 stretch features along that axis."""
    if isinstance(shape, int):
        shape = (shape, shape)
    h, w = shape
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    k = np.sqrt((fx * ax) ** 2 + (fy * ay) ** 2)
    k[0, 0] = 1.0
    amp = k ** (-beta / 2.0)
    amp[k < lo] = 0
    if hi is not None:
        amp[k > hi] = 0
    amp[0, 0] = 0
    return norm01(np.real(np.fft.ifft2(f * amp)))


def white(shape, seed=0):
    if isinstance(shape, int):
        shape = (shape, shape)
    return np.random.default_rng(seed).random(shape).astype(np.float32)


def blur(a, sigma, wrap=True):
    mode = 'wrap' if wrap else 'nearest'
    if a.ndim == 3:
        return np.stack([ndimage.gaussian_filter(a[..., i], sigma, mode=mode) for i in range(a.shape[2])], -1)
    return ndimage.gaussian_filter(a, sigma, mode=mode)


def grid(shape):
    """Pixel-centre coordinates (x, y) as float arrays."""
    if isinstance(shape, int):
        shape = (shape, shape)
    h, w = shape
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x + 0.5, y + 0.5


def warp(a, dx, dy, wrap=True):
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    mode = 'wrap' if wrap else 'nearest'
    coords = [y + dy, x + dx]
    if a.ndim == 3:
        return np.stack([ndimage.map_coordinates(a[..., i], coords, order=1, mode=mode) for i in range(a.shape[2])], -1)
    return ndimage.map_coordinates(a, coords, order=1, mode=mode)


def cell_rand(ix, iy, seed=0, period_x=None, period_y=None):
    """Deterministic per-cell random 0..1 from integer cell indices (arrays)."""
    ix = np.asarray(ix).astype(np.int64)
    iy = np.asarray(iy).astype(np.int64)
    if period_x:
        ix = np.mod(ix, period_x)
    if period_y:
        iy = np.mod(iy, period_y)
    n = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF).astype(np.float32) / float(0xFFFFFF)


def voronoi(shape, pts, wrap=True):
    """F1, F2 distances and nearest index for points given in pixel coords (tileable)."""
    if isinstance(shape, int):
        shape = (shape, shape)
    h, w = shape
    pts = np.asarray(pts, dtype=np.float32)
    n = len(pts)
    if wrap:
        offs = [(dx * w, dy * h) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
        allp = np.concatenate([pts + np.array(o, dtype=np.float32) for o in offs])
    else:
        allp = pts
    x, y = grid(shape)
    d, i = cKDTree(allp).query(np.stack([x.ravel(), y.ravel()], -1), k=2)
    return d[:, 0].reshape(h, w).astype(np.float32), d[:, 1].reshape(h, w).astype(np.float32), (i[:, 0] % n).reshape(h, w)


def normal_from_height(hmap, strength=4.0, wrap_x=True, wrap_y=True):
    """Height (0..1) -> OpenGL tangent-space normal map (RGB float 0..1)."""
    if wrap_x:
        dx = (np.roll(hmap, -1, 1) - np.roll(hmap, 1, 1)) * 0.5
    else:
        dx = np.gradient(hmap, axis=1)
    if wrap_y:
        dy = (np.roll(hmap, -1, 0) - np.roll(hmap, 1, 0)) * 0.5
    else:
        dy = np.gradient(hmap, axis=0)
    nx = -dx * strength
    ny = dy * strength  # image y points down, green points up
    nz = np.ones_like(hmap)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5


def cavity(hmap, sigma=3.0, wrap=True):
    """Positive where the surface is lower than its surroundings (dirt collects), negative on raised edges."""
    return blur(hmap, sigma, wrap) - hmap


def hsv_shift(rgb, dh=0.0, ds=1.0, dv=1.0):
    """Shift hue (dh in turns), scale saturation and value. dh/ds/dv may be arrays."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, -1)
    mn = np.min(rgb, -1)
    d = mx - mn
    hch = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / (d + 1e-9), 0)
    gc = np.where(m, (mx - g) / (d + 1e-9), 0)
    bc = np.where(m, (mx - b) / (d + 1e-9), 0)
    hch = np.where(mx == r, bc - gc, np.where(mx == g, 2.0 + rc - bc, 4.0 + gc - rc))
    hch = (hch / 6.0) % 1.0
    s = np.where(mx > 1e-6, d / (mx + 1e-9), 0)
    v = mx
    hch = (hch + dh) % 1.0
    s = np.clip(s * ds, 0, 1)
    v = np.clip(v * dv, 0, 1)
    i = np.floor(hch * 6.0)
    f = hch * 6.0 - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    i = i.astype(np.int32) % 6
    out = np.zeros_like(rgb)
    for k, (rr, gg, bb) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[..., 0] = np.where(sel, rr, out[..., 0])
        out[..., 1] = np.where(sel, gg, out[..., 1])
        out[..., 2] = np.where(sel, bb, out[..., 2])
    return out


def painterly(rgb, amount=0.5, seed=0):
    """Soften pixel noise into brushy blobs, then add a faint canvas tooth; keeps things from looking 'photo noise'."""
    med = np.stack([ndimage.median_filter(rgb[..., i], size=3, mode='wrap') for i in range(3)], -1)
    out = mix(rgb, med, amount)
    tooth = fbm(rgb.shape[:2], 0.6, seed + 991, lo=30) - 0.5
    return np.clip(out + tooth[..., None] * 0.025, 0, 1)


def to8(a):
    return (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def save_rgb(path, rgb):
    Image.fromarray(to8(rgb), 'RGB').save(path, optimize=True)


def save_rgba(path, rgb, alpha):
    Image.fromarray(np.dstack([to8(rgb), to8(alpha)]), 'RGBA').save(path, optimize=True)


def save_normal(path, n):
    Image.fromarray(to8(n), 'RGB').save(path, optimize=True)


def rough_alpha(r):
    """Roughness is stored in the albedo alpha channel; keep it > 0 so importers never treat texels as transparent."""
    return np.clip(r, 0.03, 1.0)
