#!/usr/bin/env python3
"""Dev-only: the paint pass over Juan Salvo's portrait render (tools/dev/salvo_portrait.gd runs it), so that the render
of the friends' model sits in the HUD beside the squad's painted portraits (godot/assets/operatives.webp, the four of
the Plaza de Mayo: Hornero, Lechuza, Benteveo, Biguá) as one series. Nothing is drawn: the render is filtered.
  - the backdrop is theirs: the warm olive ground of their portraits, its brushwork taken only from where their
    portraits are ground (their sides and tops, away from the figures) and laid out afresh, over their broad light;
  - the render is laid on it and painted over with an oil filter (a generalized Kuwahara: flat strokes the size of
    theirs), its edges softened into the ground as a brush leaves them, and brushwork laid along its forms; its snow
    (small bright specks) kept as crisp dabs over the oil, as their flecks are;
  - their canvas: the fine grain of their ground laid over the whole picture, the render and all;
  - their grade: the render's colours drawn part way to theirs (the warmth, the depth of the shadows), their vignette,
    and a fine grain.
    python3 tools/dev/salvo_portrait_paint.py render.png out.png operatives.webp [side] [p1|p2|p3|p4]
The way he was taken (salvo_portrait.gd) sets the weight of the paint: p1 (chiaroscuro) the heaviest oil and a dimmer
ground, p2 (profile) the darkest ground, p3 (over the shoulder) between.
Needs numpy, Pillow and opencv-python."""
import sys

import cv2
import numpy as np
from PIL import Image

# the squad's portraits in operatives.webp (384 px squares side by side): the four of the Plaza de Mayo, Hornero,
# Lechuza, Benteveo and Biguá (tools/dev/plaza_layout.py PORTRAITS)
SQUAD = (0, 1, 2, 3)
# per way of taking him: how bright their ground is behind him, the oil's stroke (the picture's size over it), the
# brushwork's strength, how far his colours and his light are drawn to theirs, and a lift of the middle tones (a gamma:
# the darks stay dark) so that the card reads as well as theirs at the size the HUD shows it
STYLES = {
    "p1": {"ground": 0.95, "stroke": 66, "lic": 0.055, "colour": 0.5, "light": 0.12, "lift": 1.38},
    "p2": {"ground": 0.8, "stroke": 78, "lic": 0.045, "colour": 0.45, "light": 0.08, "lift": 1.6},
    "p3": {"ground": 0.95, "stroke": 72, "lic": 0.05, "colour": 0.5, "light": 0.2, "lift": 1.45},
    "p4": {"ground": 1.0, "stroke": 50, "lic": 0.07, "colour": 0.62, "light": 0.3, "lift": 1.22},
}


def squad_portraits(path):
    atlas = np.asarray(Image.open(path).convert("RGB"))
    return [atlas[:, 384 * k:384 * (k + 1)].copy() for k in SQUAD]


def ground_samples(portrait):
    """Where a portrait is its ground alone: its sides and top, wherever it is close to the ground's own colours (a hat,
    a rope or a shoulder that strays there left out). A mask, 384 px."""
    h, w = portrait.shape[:2]
    lab = cv2.cvtColor(portrait, cv2.COLOR_RGB2LAB).astype(np.float32)
    outer = np.zeros((h, w), bool)
    outer[:, : int(w * 0.16)] = True
    outer[:, int(w * 0.86):] = True
    outer[: int(h * 0.07), :] = True
    outer[int(h * 0.62):, :] = False
    ref = np.median(lab[outer], axis=0)
    local = cv2.GaussianBlur(lab, (0, 0), 6)
    close = np.linalg.norm(local - ref, axis=2) < 22.0
    mask = (outer & close).astype(np.uint8)
    return cv2.erode(mask, np.ones((5, 5), np.uint8)) > 0


def quilt(sources, masks, size, patch, rng):
    """A texture `size` square laid out of `patch`-square pieces of the sources taken only where their masks are whole,
    each feathered into the next."""
    out = np.zeros((size, size), np.float32)
    weight = np.zeros((size, size), np.float32)
    ramp = np.minimum(np.arange(patch) + 1, np.arange(patch)[::-1] + 1).astype(np.float32)
    feather = np.minimum(np.outer(ramp, ramp) / (patch / 4.0) ** 2, 1.0)
    spots = []
    for k, m in enumerate(masks):
        ok = cv2.erode(m.astype(np.uint8), np.ones((patch, patch), np.uint8), anchor=(0, 0)) > 0
        ys, xs = np.nonzero(ok[: m.shape[0] - patch, : m.shape[1] - patch])
        spots += [(k, y, x) for y, x in zip(ys.tolist(), xs.tolist())]
    step = patch // 2
    for y in range(-step, size, step):
        for x in range(-step, size, step):
            k, sy, sx = spots[rng.integers(len(spots))]
            piece = sources[k][sy:sy + patch, sx:sx + patch]
            if rng.random() < 0.5:
                piece = piece[:, ::-1]
            y0, x0 = max(y, 0), max(x, 0)
            y1, x1 = min(y + patch, size), min(x + patch, size)
            py, px = y0 - y, x0 - x
            out[y0:y1, x0:x1] += piece[py:py + y1 - y0, px:px + x1 - x0] * feather[py:py + y1 - y0, px:px + x1 - x0]
            weight[y0:y1, x0:x1] += feather[py:py + y1 - y0, px:px + x1 - x0]
    return out / np.maximum(weight, 1e-6)


def backdrop(squad, size):
    """Their ground at `size`: its brushwork (the fine strokes of their backdrops, only where it is ground) laid out
    afresh over the broad light of theirs (warm olive, lighter behind the head and toward the light on the left, the
    corners deep), its colours their ground's."""
    masks = [ground_samples(p) for p in squad]
    labs = [cv2.cvtColor(p, cv2.COLOR_RGB2LAB).astype(np.float32) for p in squad]
    ground = np.concatenate([l[m] for l, m in zip(labs, masks)])
    # the strokes: each channel's detail about its own blur, quilted at the portraits' scale, then enlarged
    detail = []
    for c in range(3):
        srcs = [l[..., c] - cv2.GaussianBlur(l[..., c], (0, 0), 7) for l in labs]
        detail.append(quilt(srcs, masks, 384, 56, np.random.default_rng(1958 + c)))
    detail = np.stack(detail, 2)
    detail = cv2.resize(detail, (size, size), interpolation=cv2.INTER_CUBIC)
    # the broad light: their ground's median, lighter behind the head and up to the left
    mid = np.median(ground, axis=0)
    lo = np.percentile(ground[:, 0], 12)
    hi = np.percentile(ground[:, 0], 88)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    d = np.sqrt(((xx - 0.4) / 0.62) ** 2 + ((yy - 0.32) / 0.7) ** 2)
    light = np.clip(1.0 - d, 0.0, 1.0) ** 1.2
    lab = np.zeros((size, size, 3), np.float32)
    lab[..., 0] = lo + (hi - lo) * light
    lab[..., 1] = mid[1]
    lab[..., 2] = mid[2] + 4.0 * (light - 0.5)
    lab += detail * np.array([1.8, 1.2, 1.2], np.float32)
    rgb = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB).astype(np.float32)
    return rgb, (labs, masks)


def canvas(grounds, size):
    """The fine grain of their ground (the weave and the smallest strokes), as a signed texture about zero."""
    labs, masks = grounds
    srcs = [l[..., 0] - cv2.GaussianBlur(l[..., 0], (0, 0), 2.5) for l in labs]
    tex = quilt(srcs, masks, 384, 32, np.random.default_rng(77))
    return cv2.resize(tex, (size, size), interpolation=cv2.INTER_CUBIC)


def strokes(img, length, rng):
    """Brush strokes over the picture: a noise smeared along the forms (line-integral convolution along the direction
    of least change, from the structure tensor), so the paint seems laid with the shapes. A signed texture about zero."""
    h, w = img.shape[:2]
    lum = cv2.cvtColor(np.clip(img, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32)
    gx = cv2.Sobel(lum, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(lum, cv2.CV_32F, 0, 1, ksize=3)
    sig = max(2.0, w / 160.0)
    jxx = cv2.GaussianBlur(gx * gx, (0, 0), sig)
    jyy = cv2.GaussianBlur(gy * gy, (0, 0), sig)
    jxy = cv2.GaussianBlur(gx * gy, (0, 0), sig)
    # the direction along the forms (perpendicular to the gradient): the tensor's minor eigenvector
    theta = 0.5 * np.arctan2(2.0 * jxy, jxx - jyy) + np.pi / 2.0
    tx, ty = np.cos(theta), np.sin(theta)
    grain = rng.random((h // 2 + 1, w // 2 + 1)).astype(np.float32)
    noise = cv2.resize(grain, (w, h), interpolation=cv2.INTER_NEAREST)
    noise = cv2.GaussianBlur(noise, (0, 0), 0.8)
    acc = noise.copy()
    total = np.ones_like(noise)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    for sign in (1.0, -1.0):
        px, py = xs.copy(), ys.copy()
        for i in range(length):
            ix = np.clip(px, 0, w - 1).astype(np.int32)
            iy = np.clip(py, 0, h - 1).astype(np.int32)
            px += sign * tx[iy, ix]
            py += sign * ty[iy, ix]
            wgt = 1.0 - i / length
            acc += cv2.remap(noise, px, py, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT) * wgt
            total += wgt
    lic = acc / total
    lic = (lic - lic.mean()) / (lic.std() + 1e-6)
    return lic


def grade(img, squad, amount=0.45, light=None):
    """The render's colours drawn part way to the squad's portraits' (mean and spread per channel, in Lab); its light
    (L) by `light` (as much as its colours unless said: a dark picture kept dark)."""
    ref = np.concatenate([cv2.cvtColor(p, cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32) for p in squad])
    lab = cv2.cvtColor(np.clip(img, 0, 255).astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)
    flat = lab.reshape(-1, 3)
    mu, sd = flat.mean(0), flat.std(0) + 1e-3
    rmu, rsd = ref.mean(0), ref.std(0)
    moved = (flat - mu) / sd * rsd + rmu
    weights = np.array([amount if light is None else light, amount, amount], np.float32)
    out = flat + (moved - flat) * weights
    out = np.clip(out, 0, 255).reshape(lab.shape).astype(np.uint8)
    return cv2.cvtColor(out, cv2.COLOR_LAB2RGB).astype(np.float32)


def kuwahara(img, radius, sectors=8, q=8.0):
    """The oil filter: a generalized Kuwahara (each pixel takes the colour of the calmest of the sectors about it, by
    their spread), which leaves flat strokes and keeps edges. img: float RGB 0..255."""
    r = int(radius)
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float32)
    dist = np.hypot(xx, yy)
    ang = np.arctan2(yy, xx)
    ring = np.exp(-(dist / (r * 0.55)) ** 2) * (dist <= r + 0.5)
    num = np.zeros_like(img, dtype=np.float64)
    den = np.zeros(img.shape[:2], np.float64)
    sq = img * img
    for k in range(sectors):
        centre = -np.pi + (k + 0.5) * 2.0 * np.pi / sectors
        diff = np.angle(np.exp(1j * (ang - centre)))
        sector = np.exp(-(diff / (np.pi / sectors * 0.9)) ** 2) * ring
        sector[r, r] = sector.max()
        sector /= sector.sum()
        m = cv2.filter2D(img, -1, sector, borderType=cv2.BORDER_REFLECT)
        m2 = cv2.filter2D(sq, -1, sector, borderType=cv2.BORDER_REFLECT)
        spread = np.sqrt(np.maximum(m2 - m * m, 0.0).sum(2)) + 1.0
        w = spread.astype(np.float64) ** (-q)
        num += m * w[..., None]
        den += w
    return (num / den[..., None]).astype(np.float32)


def paint(render_path, out_path, squad_path, side=768, style="p1"):
    look = STYLES.get(style, STYLES["p1"])
    rgba = np.asarray(Image.open(render_path).convert("RGBA")).astype(np.float32)
    big = rgba.shape[0]
    squad = squad_portraits(squad_path)
    ground, grounds = backdrop(squad, big)
    ground = ground * look["ground"]
    rng = np.random.default_rng(1957)
    alpha = rgba[..., 3:4] / 255.0
    # the edge of the figure as a brush leaves it: a little soft
    alpha = cv2.GaussianBlur(alpha, (0, 0), big / 900)[..., None]
    comp = rgba[..., :3] * alpha + ground * (1.0 - alpha)
    # their grade (before the paint, so the strokes carry it)
    comp = grade(comp, squad, look["colour"], look["light"])
    # the oil: flat strokes about the size of theirs (a 384 px portrait's, at this size), twice, the second finer
    stroke = max(5, big // look["stroke"])
    oil = kuwahara(comp.astype(np.float32), stroke)
    oil = kuwahara(oil, max(3, stroke // 2))
    # the snow kept as dabs (flakes resting on him and falling between): what stands bright out of its surroundings in
    # small specks is laid back over the oil, as the squad's painted flecks are
    lum = cv2.cvtColor(np.clip(comp, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32)
    around = cv2.medianBlur(lum.astype(np.uint8), 2 * (stroke // 2) + 1).astype(np.float32)
    flecks = np.clip((lum - around - 25.0) / 35.0, 0.0, 1.0) * np.clip((lum - 110.0) / 50.0, 0.0, 1.0)
    flecks = cv2.GaussianBlur(cv2.dilate(flecks, np.ones((3, 3), np.uint8)), (0, 0), 1.2)[..., None]
    oil = oil * (1.0 - flecks) + comp * flecks
    img = cv2.resize(oil, (side, side), interpolation=cv2.INTER_AREA)
    # the brushwork laid along the forms, a little stronger on the figure than on the ground
    lic = strokes(img, max(5, side // 90), rng)
    fig = cv2.resize(alpha[..., 0], (side, side), interpolation=cv2.INTER_AREA)[..., None]
    img = img * (1.0 + lic[..., None] * look["lic"] * (0.7 + 0.3 * fig))
    # the strokes' edges kept crisp where the figure's are (a light unsharp mask)
    soft = cv2.GaussianBlur(img, (0, 0), 1.2)
    img = img * 1.3 - soft * 0.3
    # their canvas over all of it
    tex = canvas(grounds, side)
    img = img * (1.0 + tex[..., None] / 255.0 * 1.6)
    # their vignette: the corners darker, the light falling from the upper left
    yy, xx = np.mgrid[0:side, 0:side].astype(np.float32) / side
    d = np.sqrt(((xx - 0.4) / 0.7) ** 2 + ((yy - 0.33) / 0.72) ** 2)
    img *= (1.0 - 0.55 * np.clip((d - 0.42) / 0.7, 0.0, 1.0) ** 1.3)[..., None]
    # and the light falling away below the face, as it does on their coats
    img *= (1.0 - 0.3 * np.clip((yy - 0.6) / 0.4, 0.0, 1.0) ** 1.2)[..., None]
    # the middle tones lifted for the card
    img = 255.0 * (np.clip(img, 0, 255) / 255.0) ** (1.0 / look["lift"])
    # a fine grain
    img *= (1.0 + (rng.random((side, side, 1)).astype(np.float32) - 0.5) * 0.05)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(out_path, optimize=True)
    print(f"painted {out_path} ({side} x {side}) from {render_path}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    paint(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 768, sys.argv[5] if len(sys.argv) > 5 else "p1")
