"""Things the baker paints and builds on top of MakeHuman's assets (dev tool, not shipped):
weathered skin (stubble, sun, grime), and headgear, a scarf and a moustache shaped to each head.

Everything works in the game's bind-pose space (metres, +Y up, facing +Z, the figure's left +X).
"""
import numpy as np
from PIL import Image, ImageFilter


# --- texture space -----------------------------------------------------------------------------
def raster(uv, tris, size, attrs):
    """Interpolates per-vertex attributes (N x k) over the triangles in texture space.
    uv: (N, 2) with v down (image rows). Returns (H x W x k image, H x W coverage)."""
    H = W = size
    k = attrs.shape[1]
    out = np.zeros((H, W, k), dtype=np.float32)
    cov = np.zeros((H, W), dtype=bool)
    px = uv.astype(np.float64) * [W, H] - 0.5
    for t in tris:
        a, b, c = px[t[0]], px[t[1]], px[t[2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))), W - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))), H - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        l2 = 1.0 - l0 - l1
        inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
        if not inside.any():
            continue
        yy, xx = ys[inside], xs[inside]
        val = l0[inside, None] * attrs[t[0]] + l1[inside, None] * attrs[t[1]] + l2[inside, None] * attrs[t[2]]
        out[yy, xx] = val
        cov[yy, xx] = True
    return out, cov


def dilate(img, cov, steps):
    """Bleeds covered texels outward so that filtering never reaches the background."""
    img = img.copy()
    cov = cov.copy()
    for _ in range(steps):
        acc = np.zeros_like(img)
        cnt = np.zeros(cov.shape, dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh_c = np.roll(cov, (dy, dx), axis=(0, 1))
            sh_i = np.roll(img, (dy, dx), axis=(0, 1))
            acc += sh_i * sh_c[..., None]
            cnt += sh_c
        grow = (~cov) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        cov = cov | grow
    return img, cov


# --- noise -------------------------------------------------------------------------------------
def _hash3(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float32) / 65535.0


def vnoise3(P, freq, seed=0):
    """Smooth value noise in 0..1 at points P (N x 3), `freq` cells per metre."""
    q = P * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(P), dtype=np.float32)
    for dx in (0, 1):
        wx = f[:, 0] if dx else 1.0 - f[:, 0]
        for dy in (0, 1):
            wy = f[:, 1] if dy else 1.0 - f[:, 1]
            for dz in (0, 1):
                wz = f[:, 2] if dz else 1.0 - f[:, 2]
                out += wx * wy * wz * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm3(P, freq, octaves=4, seed=0):
    out = np.zeros(len(P), dtype=np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * vnoise3(P, freq * (2.0 ** o), seed + o * 7)
        tot += amp
        amp *= 0.5
    return out / tot


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- mesh measures ------------------------------------------------------------------------------
def cavity(pos, faces, smooth_iters=3):
    """Per-vertex concavity of a polygon mesh (positive in creases), relative to the local edge
    length, smoothed over the neighbourhood so that only real folds show."""
    n = len(pos)
    ea, eb, fa, fb, fc = [], [], [], [], []
    for f in faces:
        m = len(f)
        for j in range(m):
            ea.append(f[j])
            eb.append(f[(j + 1) % m])
        if m >= 3:
            fa.append(f[0])
            fb.append(f[1])
            fc.append(f[2])
    ea = np.array(ea + eb, dtype=np.int64)
    eb2 = np.array(eb + ea[:len(eb)].tolist(), dtype=np.int64)
    eb = eb2
    nb_sum = np.zeros_like(pos)
    nb_cnt = np.zeros(n)
    np.add.at(nb_sum, ea, pos[eb])
    np.add.at(nb_cnt, ea, 1.0)
    elen = np.zeros(n)
    np.add.at(elen, ea, np.linalg.norm(pos[ea] - pos[eb], axis=1))
    fa, fb, fc = np.array(fa), np.array(fb), np.array(fc)
    fn = np.cross(pos[fb] - pos[fa], pos[fc] - pos[fa])
    normals = np.zeros_like(pos)
    for idx in (fa, fb, fc):
        np.add.at(normals, idx, fn)
    cnt = np.maximum(nb_cnt, 1.0)
    ln = np.linalg.norm(normals, axis=1, keepdims=True)
    ln[ln == 0] = 1
    normals /= ln
    lap = nb_sum / cnt[:, None] - pos
    c = (lap * normals).sum(axis=1) / np.maximum(elen / cnt, 1e-6)
    for _ in range(smooth_iters):
        acc = np.zeros(n)
        np.add.at(acc, ea, c[eb])
        c = 0.5 * c + 0.5 * acc / cnt
    return c


def head_frame(meta):
    h = meta["head"]
    return {"zc": 0.5 * (h["front"] + h["back"]), "top": h["top"], "brow": h["brow"], "hw": h["half_width"],
            "front": h["front"], "back": h["back"], "chin": h["chin"]}


# --- weathered skin -------------------------------------------------------------------------------
def beard_mask(P, meta, spec):
    """How much stubble grows at each point: upper lip, chin, jaw, lower cheeks, sideburns, throat."""
    lm = meta["landmarks"]
    hf = head_frame(meta)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = np.degrees(np.abs(np.arctan2(x, z - meta["ear_z"])))
    nb, mo, ch = lm["nose_base"][1], lm["mouth"][1], lm["chin"][1]
    ul, ll, cx = lm["upper_lip"][1], lm["lower_lip"][1], abs(lm["corner"][0])
    brow = hf["brow"]
    line = spec.get("beard_line", 0.0)  # raises (+) or lowers the cheek line
    nt = lm["nose_tip"][1]
    top = np.interp(az, [0, 6, 10, 16, 26, 40, 55, 68, 74, 84, 89, 98],
                    [nb - 0.002, nb - 0.003, mo + 0.007 + line, mo + 0.005 + line, mo + 0.013 + line, nb + 0.004 + line,
                     nb + 0.014 + line, nt + 0.014 + line, brow - 0.036, brow - 0.036, nb - 0.004, ch - 0.035])
    bottom = np.interp(az, [0, 30, 60, 80, 95], [ch - 0.048, ch - 0.042, ch - 0.024, ch - 0.004, ch - 0.02])
    ragged = (fbm3(P, 260.0, 2, 41) - 0.5) * 0.008
    m = smooth(top - y + ragged, -0.004, 0.009) * smooth(y - bottom + ragged, -0.006, 0.018)
    m *= smooth(100.0 - az, 0.0, 6.0)
    # not on the lips
    lip_c = 0.5 * (ul + ll) - 0.001
    lip_h = 0.5 * (ul - ll) + 0.0025
    e = (x / (cx * 1.12)) ** 2 + ((y - lip_c) / lip_h) ** 2
    m *= smooth(e, 0.75, 1.25)
    return m


def weather_skin(src_png, out_png, size, skin, body_cav, meta, spec, eyes):
    """Paints sun, creases, eye-socket shadow, stubble and grime over MakeHuman's skin texture."""
    w = spec.get("weather", {})
    hw = meta["head"]["half_width"]
    hp = skin.pos[(skin.bones[:, 0] == 3) & (np.abs(skin.pos[:, 0]) > hw * 0.9) & (np.abs(skin.pos[:, 1] - meta["landmarks"]["nose_tip"][1]) < 0.02)]
    meta["ear_z"] = float(hp[:, 2].mean()) if len(hp) else 0.5 * (meta["head"]["front"] + meta["head"]["back"])
    base = np.asarray(Image.open(src_png).convert("RGB").resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    head_w = (skin.weights * (skin.bones == 3)).sum(axis=1)
    attrs = np.concatenate([skin.pos, skin.nrm, head_w[:, None], body_cav[:, None]], axis=1).astype(np.float32)
    img, cov = raster(skin.uv, skin.idx, size, attrs)
    img, cov2 = dilate(img, cov, 6)
    sel = cov2
    P = img[sel][:, 0:3]
    N = img[sel][:, 3:6]
    headw = img[sel][:, 6]
    cav = img[sel][:, 7]
    col = base[sel]
    lum = col.mean(axis=1, keepdims=True)
    lm = meta["landmarks"]
    hf = head_frame(meta)
    face = smooth(P[:, 2] - hf["zc"], -0.01, 0.04) * headw
    # 1. creases: deeper, a little warmer (the portraits are lit hard from above)
    c = np.clip(cav * w.get("crease_gain", 6.0), -1.0, 1.0)
    crease = np.clip(c, 0.0, 1.0)
    col *= (1.0 - w.get("crease", 0.32) * crease[:, None] * np.array([1.0, 1.12, 1.25]))
    ridge = np.clip(-c, 0.0, 1.0)
    col *= (1.0 + 0.10 * ridge[:, None])
    # 2. sun: red-brown on the nose, cheekbones, brow ridge and ears; the face and neck tanned
    sun = np.zeros(len(P), dtype=np.float32)
    for cx, cy, cz, r, a in ((lm["nose_tip"][0] * 0, lm["nose_tip"][1], lm["nose_tip"][2], 0.016, 1.0),
                             (0.034, lm["nose_tip"][1] + 0.012, lm["nose_base"][2] - 0.035, 0.020, 0.8),
                             (-0.034, lm["nose_tip"][1] + 0.012, lm["nose_base"][2] - 0.035, 0.020, 0.8),
                             (0.0, hf["brow"] + 0.010, hf["front"], 0.030, 0.45)):
        d2 = ((P - np.array([cx, cy, cz])) ** 2).sum(axis=1)
        sun += a * np.exp(-d2 / (r * r))
    sun = np.clip(sun, 0, 1) * headw * (0.6 + 0.4 * fbm3(P, 60.0, 3, 11))
    flush = np.array([0.98, 0.70, 0.60], dtype=np.float32)
    col = col * (1.0 - w.get("sun", 0.30) * sun[:, None]) + (col * flush) * (w.get("sun", 0.30) * sun[:, None])
    # 2b. cold: the cheeks, the end of the nose and the ears reddened (a boy out in the snow)
    cold = w.get("cold", 0.0)
    if cold > 0.0:
        hw = meta["head"]["half_width"]
        m = np.zeros(len(P), dtype=np.float32)
        for cx, cy, cz, r, a in ((0.038, lm["nose_tip"][1] - 0.008, lm["nose_base"][2] - 0.032, 0.022, 1.0),
                                 (-0.038, lm["nose_tip"][1] - 0.008, lm["nose_base"][2] - 0.032, 0.022, 1.0),
                                 (0.0, lm["nose_tip"][1], lm["nose_tip"][2], 0.012, 0.8),
                                 (hw, lm["nose_tip"][1] + 0.004, meta["ear_z"], 0.022, 0.7),
                                 (-hw, lm["nose_tip"][1] + 0.004, meta["ear_z"], 0.022, 0.7)):
            d2 = ((P - np.array([cx, cy, cz])) ** 2).sum(axis=1)
            m += a * np.exp(-d2 / (r * r))
        m = np.clip(m, 0, 1) * headw * cold
        flush = np.array([1.0, 0.60, 0.56], dtype=np.float32)
        col = col * (1.0 - m[:, None]) + col * flush * 1.08 * m[:, None]
    # 3. eye sockets: a shadow between the brow and the cheekbone, so the eyes sit deep
    if eyes is not None:
        for sgn in (1.0, -1.0):
            e = eyes.pos[eyes.pos[:, 0] * sgn > 0]
            ec = e.mean(axis=0)
            rx, ry = 0.022, 0.015
            d = ((P[:, 0] - ec[0]) / rx) ** 2 + ((P[:, 1] - (ec[1] + 0.002)) / ry) ** 2
            s = np.exp(-d * 1.4) * smooth(P[:, 2] - (ec[2] - 0.03), 0.0, 0.01)
            col *= (1.0 - w.get("socket", 0.22) * s[:, None] * np.array([1.0, 1.15, 1.10]))
    # 4. stubble: a blue-grey shadow under the skin and the dots of cut hairs
    beard = beard_mask(P, meta, spec) * headw * w.get("stubble", 0.6)
    beard *= 0.8 + 0.4 * fbm3(P, 180.0, 2, 5)
    shadow = np.array([0.66, 0.64, 0.64], dtype=np.float32)
    col = col * (1.0 - beard[:, None]) + col * shadow * beard[:, None]
    rnd = _hash3(*(np.floor(P * 2200.0).astype(np.int64).T), 3)
    dots = smooth(rnd, 1.0 - 0.45 * beard, 1.0 - 0.45 * beard + 0.25) * np.clip(beard * 1.4, 0, 1)
    hair = np.array(spec.get("stubble_rgb", [0.16, 0.12, 0.10]), dtype=np.float32)
    col = col * (1.0 - 0.38 * dots[:, None]) + col * hair * 2.0 * (0.38 * dots[:, None])
    # 5. grime: dirt in patches, worked into the creases and the hands
    hands = smooth(1.0 - P[:, 1], 0.05, 0.12) * (1.0 - headw)
    dirt = fbm3(P, 22.0, 4, 21)
    dirt = smooth(dirt, 0.45, 0.8) * w.get("grime", 0.25) + crease * 0.5 * w.get("grime", 0.25) + hands * 0.10
    mud = np.array([0.55, 0.47, 0.38], dtype=np.float32)
    col = col * (1.0 - dirt[:, None]) + col * mud * dirt[:, None]
    # 6. pores and blotches
    pores = (_hash3(*(np.floor(P * 1800.0).astype(np.int64).T), 9) - 0.5) * 0.05
    blot = (fbm3(P, 90.0, 3, 31) - 0.5) * 0.10
    col *= (1.0 + pores[:, None] + blot[:, None] * np.array([0.6, 1.0, 1.2]))
    # weathered skin is duller than MakeHuman's: pull the colour towards its own grey
    g = col.mean(axis=1, keepdims=True)
    col = g + (col - g) * w.get("saturation", 0.72)
    out = base.copy()
    out[sel] = np.clip(col, 0.0, 1.0)
    im = Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGB")
    im.save(out_png, optimize=True)
    return {"P": img, "cov": cov}


# --- built parts ---------------------------------------------------------------------------------
HEAD_BONE = 3


class Part:
    """A baked surface built here (same fields as mhbake.Surface)."""

    def __init__(self, name):
        self.name = name
        self.P, self.UV, self.C, self.T, self.B = [], [], [], [], []
        self.bone = None    # one bone for what is added next, or
        self.skin = None    # a function p -> (bones[4], weights[4])

    def add(self, p, uv, c):
        self.P.append(p)
        self.UV.append(uv)
        self.C.append(c)
        self.B.append(self.skin(np.asarray(p)) if self.skin is not None else self.bone)
        return len(self.P) - 1

    def grid(self, P, UV, C, outward=None, closed_u=False):
        """P: (nu, nv, 3) rows of points; quads between neighbours. outward(points) gives the
        direction each face should face (else as wound)."""
        nu, nv = P.shape[0], P.shape[1]
        ids = np.zeros((nu, nv), dtype=np.int64)
        for i in range(nu):
            for j in range(nv):
                ids[i, j] = self.add(P[i, j], UV[i, j], C[i, j])
        for i in range(nu - 1):
            for j in range(nv - 1):
                a, b, c, d = ids[i, j], ids[i + 1, j], ids[i + 1, j + 1], ids[i, j + 1]
                self.tri(a, b, c, outward)
                self.tri(a, c, d, outward)
        return ids

    def tri(self, a, b, c, outward=None):
        if outward is not None:
            pa, pb, pc = (np.asarray(self.P[k]) for k in (a, b, c))
            n = np.cross(pb - pa, pc - pa)
            if np.linalg.norm(n) < 1e-14:
                return
            o = outward((pa + pb + pc) / 3.0)
            if np.dot(n, o) < 0:
                b, c = c, b
        self.T.append((a, b, c))

    def finish(self, bone=HEAD_BONE, weld=1e-5):
        self.pos = np.array(self.P, dtype=np.float32)
        self.uv = np.array(self.UV, dtype=np.float32)
        self.col = np.array(self.C, dtype=np.float32)
        self.idx = np.array(self.T, dtype=np.int32).reshape(-1, 3)
        self.nrm = smooth_normals(self.pos.astype(np.float64), self.idx, weld).astype(np.float32)
        self.bones = np.zeros((len(self.pos), 4), dtype=np.int32)
        self.weights = np.zeros((len(self.pos), 4), dtype=np.float32)
        for i, b in enumerate(self.B):
            if isinstance(b, tuple):
                self.bones[i] = b[0]
                self.weights[i] = b[1]
            else:
                self.bones[i, 0] = bone if b is None else b
                self.weights[i, 0] = 1.0
        return self


def smooth_normals(pos, tris, weld=1e-5):
    """Area-weighted normals, shared by coincident points (so seams of a closed grid stay smooth)."""
    key = np.round(pos / weld).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3))
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(acc, inv[tris[:, k]], fn)
    n = acc[inv]
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    return n / ln


def axis_angle(axis, ang):
    axis = np.asarray(axis, dtype=np.float64)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s_, C = np.cos(ang), np.sin(ang), 1 - np.cos(ang)
    return np.array([[c + x * x * C, x * y * C - z * s_, x * z * C + y * s_],
                     [y * x * C + z * s_, c + y * y * C, y * z * C - x * s_],
                     [z * x * C - y * s_, z * y * C + x * s_, c + z * z * C]])


def rgba(hexstr, a=1.0):
    h = hexstr.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [a]


class Hull:
    """What a hat or scarf must stay outside of: points of the skin, hair and clothes."""

    def __init__(self, pts):
        self.p = np.asarray(pts, dtype=np.float64)

    def radius(self, c, dirs, cone_deg=7.0):
        """Distance from c to the outermost point of the hull in each direction (0 if none)."""
        v = self.p - c
        d = np.linalg.norm(v, axis=1)
        u = v / np.maximum(d, 1e-9)[:, None]
        out = np.zeros(len(dirs))
        cmin = np.cos(np.radians(cone_deg))
        for s in range(0, len(dirs), 256):
            cs = dirs[s:s + 256] @ u.T
            proj = np.where(cs > cmin, cs * d[None, :], 0.0)
            out[s:s + 256] = proj.max(axis=1)
        return out

    def push_out(self, pts, c, clearance):
        """Moves points that are inside the hull (seen from c) out to its surface + clearance."""
        v = pts - c
        d = np.linalg.norm(v, axis=1)
        u = v / np.maximum(d, 1e-9)[:, None]
        r = self.radius(c, u, 6.0) + clearance
        k = np.maximum(r, d)
        return c + u * k[:, None]

    def ring_radius(self, axis_xz, a, y0, y1, half_deg=6.0):
        """Horizontal distance from a vertical axis to the hull at angle a (0 = +Z, pi/2 = +X),
        over heights y0..y1."""
        q = self.p
        sel = (q[:, 1] >= y0) & (q[:, 1] <= y1)
        q = q[sel]
        dx, dz = q[:, 0] - axis_xz[0], q[:, 2] - axis_xz[1]
        ang = np.arctan2(dx, dz)
        rr = np.hypot(dx, dz)
        diff = np.abs((ang - a + np.pi) % (2 * np.pi) - np.pi)
        m = diff < np.radians(half_deg)
        if not m.any():
            return 0.0
        return float((rr[m] * np.cos(diff[m])).max())


def _dir(a):
    return np.array([np.sin(a), 0.0, np.cos(a)])


def hat_band(meta, kind):
    """Height of the hat's band around the head: y(a) for a in radians (0 = front, +pi/2 = the
    figure's left)."""
    brow = meta["head"]["brow"]
    if kind == "beret":
        # level across the brow, low over the right ear, down at the back
        return lambda a: brow + 0.004 + 0.014 * np.cos(a) + 0.008 * np.sin(a)
    if kind == "helmet":
        # low over the brow, down over the ears and the nape
        return lambda a: brow + 0.008 * (1 + np.cos(a)) * 0.5 - 0.034 * (1 - np.cos(a)) * 0.5 - 0.016 * np.sin(a) ** 2
    if kind == "service":
        return lambda a: brow + 0.012 + 0.006 * np.cos(a)
    if kind == "flat":
        # a flat cap sits low: on the brow at the front, round the back of the skull behind
        return lambda a: brow + 0.003 + 0.008 * np.cos(a) - 0.004 * (1 - np.cos(a)) * 0.5
    if kind == "sailor":
        # a sailor's cap sits high and level on the head, the band round the upper skull
        return lambda a: brow + 0.046 + 0.003 * np.cos(a)
    if kind == "hood":
        # a hood covers all the hair: low over the brow, down to the nape behind
        return lambda a: brow - 0.012 - 0.05 * (1 - np.cos(a)) * 0.5
    if kind in ("knit", "beanie"):
        # a knitted cap pulled well down: just above the brows in front, over the tops of the ears, the nape behind
        return lambda a: brow + 0.016 * (1 + np.cos(a)) * 0.5 - 0.040 * ((1 - np.cos(a)) * 0.5) ** 1.3
    if kind == "earflap":
        return lambda a: brow + 0.020 * (1 + np.cos(a)) * 0.5 - 0.058 * ((1 - np.cos(a)) * 0.5) ** 1.3
    if kind == "fedora":
        # a felt hat sits level on the forehead, a finger above the brows, round the back of the skull
        return lambda a: brow + 0.014 + 0.004 * np.cos(a) - 0.004 * (1 - np.cos(a)) * 0.5
    if kind == "headscarf":
        # a headscarf hides the hair but for a little at the front: its edge back from the forehead, the nape behind
        return lambda a: brow + 0.044 * ((1 + np.cos(a)) * 0.5) ** 2 - 0.075 * ((1 - np.cos(a)) * 0.5) ** 1.2
    if kind == "peaked":
        return lambda a: brow + 0.010 + 0.006 * np.cos(a)
    return lambda a: brow + 0.002 + 0.016 * np.cos(a)


def hood(hull, meta, color, rim="c9cdd2"):
    """A snow anorak's hood, up: it hugs the skull over the crown, falls loose round the jaw and the nape and
    drapes onto the shoulders, and leaves the face open from the chin to the brow (UVs in metres, for a
    tiling twill). Vertex alpha 1: cloth."""
    part = Part("hat")
    h = meta["head"]
    c = head_axis(meta)
    axis = (0.0, c[2])
    top, brow, chin = h["top"], h["brow"], h["chin"]
    A = 72
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    face = np.radians(57.0)
    col = np.array(rgba(color))
    rcol = np.array(rgba(rim))

    def hull_ring(y, extra):
        R = np.array([hull.ring_radius(axis, a, y - 0.012, y + 0.012, 8.0) for a in a_s])
        R = np.maximum(R, 0.055)
        R[-1] = R[0]
        return R + extra

    rows = []
    # the drape over the shoulders and round the neck: plain ellipses, the hull (head and hair) does not reach so low
    for y, rx, rf, rb in ((1.452, 0.15, 0.062, 0.125), (1.478, 0.125, 0.064, 0.112), (1.505, 0.106, 0.068, 0.104)):
        rz = np.where(np.cos(a_s) > 0, rf, rb)
        rows.append(np.stack([np.sin(a_s) * rx, np.full(A + 1, y), axis[1] - 0.012 + np.cos(a_s) * rz], 1))
    # loose round the jaw, closer at the cheekbones and the brow
    for y, extra in ((chin - 0.006, 0.032), ((chin + brow) * 0.5, 0.026), (brow + 0.004, 0.02)):
        R = hull_ring(y, extra)
        rows.append(np.stack([np.sin(a_s) * R, np.full(A + 1, y), axis[1] + np.cos(a_s) * R], 1))
    # over the crown: a dome from the brow ring, kept just outside the skull and hair
    ring = rows[-1]
    centre = np.array([0.0, brow + 0.004, axis[1]])
    for t in (0.22, 0.45, 0.66, 0.84, 0.95, 1.0):
        ang = t * np.pi * 0.5
        q = centre + (ring - centre) * np.cos(ang)
        q[:, 1] = brow + 0.004 + (top - brow + 0.016) * np.sin(ang)
        rows.append(q)
    P = np.stack(rows, axis=1)
    lift = c + np.array([0, -0.02, 0])
    upper = P[:, 3:].reshape(-1, 3)
    P[:, 3:] = hull.push_out(upper, lift, 0.014).reshape(P[:, 3:].shape)
    nv = P.shape[1]
    UV = arc_uv(P)
    # folds: the cloth bunches where it is loose, a darker band round the face opening
    C = np.tile(col, (A + 1, nv, 1))
    for i, a in enumerate(a_s):
        k = 0.9 + 0.1 * np.cos(7 * a + 0.4) * np.cos(3 * a)
        C[i, :3, :3] *= k
        edge = abs(abs(a) - face) < 0.18
        if edge:
            C[i, 3:6] = rcol
    ids = np.zeros((A + 1, nv), dtype=np.int64)
    for i in range(A + 1):
        for j in range(nv):
            ids[i, j] = part.add(P[i, j], UV[i, j], C[i, j])

    def outward(p):
        return p - np.array([0.0, min(p[1], c[1]), axis[1]])
    for i in range(A):
        mid_a = 0.5 * (a_s[i] + a_s[i + 1])
        for j in range(nv - 1):
            # the face is open between the jaw row and the brow row
            if abs(mid_a) < face and 3 <= j < 5:
                continue
            a, b, cc, d = ids[i, j], ids[i + 1, j], ids[i + 1, j + 1], ids[i, j + 1]
            part.tri(a, b, cc, outward)
            part.tri(a, cc, d, outward)
    return part.finish()


def head_axis(meta):
    h = meta["head"]
    return np.array([0.0, (h["brow"] + h["top"]) * 0.5, 0.5 * (h["front"] + h["back"])])


def tuck_hair(p, skin_pts, meta, kind):
    """Hair that would show above the hat's band is pressed flat against the scalp (inside the
    hat), so no cut edges show under the brim. Returns the moved points."""
    yb = hat_band(meta, kind)
    c = head_axis(meta)
    out = p.copy()
    a = np.arctan2(p[:, 0], p[:, 2] - c[2])
    # fully pressed above the band, eased in over the 2.5 cm below it (no stretched cards)
    t = smooth(p[:, 1] - (yb(a) - 0.010), 0.0, 0.014)
    under = t > 0
    if not under.any():
        return out
    hull = Hull(skin_pts)
    q = p[under]
    for i, idx in enumerate(np.nonzero(under)[0]):
        y = q[i, 1]
        r = hull.ring_radius((0.0, c[2]), a[idx], y - 0.006, y + 0.006, 10.0)
        cur = np.hypot(q[i, 0], q[i, 2] - c[2])
        k = min(1.0, (r + 0.0015) / max(cur, 1e-6)) if r > 0 else 0.0
        k = 1.0 + (k - 1.0) * t[idx]
        out[idx, 0] = q[i, 0] * k
        out[idx, 2] = c[2] + (q[i, 2] - c[2]) * k
    return out


def arc_uv(P):
    """UVs in metres along the two directions of a grid of points (nu, nv, 3)."""
    du = np.linalg.norm(np.diff(P, axis=0), axis=2)
    dv = np.linalg.norm(np.diff(P, axis=1), axis=2)
    u = np.concatenate([np.zeros((1, P.shape[1])), np.cumsum(du, axis=0)], axis=0)
    v = np.concatenate([np.zeros((P.shape[0], 1)), np.cumsum(dv, axis=1)], axis=1)
    return np.stack([u, v], axis=-1)


def field_cap(hull, meta, color):
    """A soft field cap: a band, a crown that puffs out a little above it, a rounded top and a
    short curved peak (UVs in metres, for a tiling twill)."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "cap")
    top = meta["head"]["top"]
    A = 56
    a_s = np.linspace(-np.pi, np.pi, A + 1)  # seam at the back
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.03) for a in a_s]) + 0.005
    R[-1] = R[0]
    front = (1.0 + np.cos(a_s)) * 0.5
    y_band = yb(a_s)
    y_edge = top + 0.000 + 0.004 * front
    lean = 0.45  # the crown's walls lean back with the forehead
    rings = [  # (fraction up the wall, extra radius, radius scale)
        (-0.09, 0.0, 1.0),
        (0.10, 0.001, 1.0),
        (0.13, 0.003, 1.0),
        (0.40, 0.003, 1.01),
        (0.70, 0.002, 1.0),
        (0.90, 0.0, 0.975),
        (1.0, -0.004, 0.90),
    ]
    disc = [(0.75, 0.003), (0.5, 0.005), (0.25, 0.006), (0.0, 0.006)]
    nv = len(rings) + len(disc)
    P = np.zeros((A + 1, nv, 3))
    C = np.zeros((A + 1, nv, 4))
    col = np.array(rgba(color))
    wob = 0.0025 * np.sin(3 * a_s + 0.7) + 0.0015 * np.sin(7 * a_s)
    H = y_edge - y_band
    for j, (f, extra, sc) in enumerate(rings):
        y = y_band + H * f
        rr = R * sc + extra + (wob if j >= 3 else 0.0)
        zc = axis[1] - lean * max(f, 0.0) * 0.06
        P[:, j, 0] = np.sin(a_s) * rr
        P[:, j, 1] = y
        P[:, j, 2] = zc + np.cos(a_s) * rr
        shade = 0.82 if j < 2 else 1.0
        C[:, j] = col * [shade, shade, shade, 1.0]
    edge = P[:, len(rings) - 1]
    centre = edge.mean(axis=0)
    for k, (f, dome) in enumerate(disc):
        j = len(rings) + k
        P[:, j] = centre + (edge - centre) * f
        P[:, j, 1] = edge[:, 1] * f + (1 - f) * (top + 0.010) + dome * 0.4
        C[:, j] = col
    # a crease down the front of the crown
    crease = np.exp(-(a_s / 0.18) ** 2)
    for j in range(3, nv):
        P[:, j, 1] -= 0.004 * crease * (1.0 if j >= len(rings) - 1 else 0.5)
    flat = P.reshape(-1, 3)
    flat = hull.push_out(flat, c + np.array([0, -0.02, 0]), 0.004)
    P = flat.reshape(P.shape)
    UV = arc_uv(P)

    def out_from_axis(p):
        v = p - np.array([0.0, c[1] - 0.03, axis[1]])
        return v
    part.grid(P, UV, C, out_from_axis)
    # the band's lower edge turned in, so the cap has thickness when seen from below
    inner = P[:, 0].copy()
    inner[:, 0] -= np.sin(a_s) * 0.003
    inner[:, 2] -= np.cos(a_s) * 0.003
    inner[:, 1] += 0.006
    P2 = np.stack([inner, P[:, 0]], axis=1)
    UV2 = np.stack([UV[:, 0] + [0, 0.01], UV[:, 0]], axis=1)
    C2 = np.stack([C[:, 0] * [0.6, 0.6, 0.6, 1], C[:, 0]], axis=1)
    part.grid(P2, UV2, C2, lambda p: np.array([0, -1.0, 0]))
    # the peak
    sel = np.nonzero(np.abs(a_s) <= np.radians(72))[0]
    pitch = 0.17
    nt = 6
    PT = np.zeros((len(sel), nt, 3))
    for ii, i in enumerate(sel):
        a = a_s[i]
        L = 0.046 * max(np.cos(a / np.radians(72) * np.pi / 2), 0.0) ** 0.55
        base = P[i, 0] + np.array([0, 0.002, 0])
        d = _dir(a)
        for t in range(nt):
            s = t / (nt - 1)
            p = base + d * (L * s * np.cos(pitch)) - np.array([0, 1, 0]) * (L * s * np.sin(pitch) + 0.008 * s * s * L / 0.056)
            PT[ii, t] = p
    UVT = np.stack([PT[..., 0], PT[..., 2]], axis=-1)
    dark = col * [0.72, 0.72, 0.68, 1.0]
    CT = np.tile(dark, (len(sel), nt, 1))
    thick = np.array([0, 0.0045, 0])
    part.grid(PT, UVT, np.tile(col * [0.92, 0.92, 0.9, 1], (len(sel), nt, 1)), lambda p: np.array([0, 1.0, 0.25]))
    part.grid(PT - thick, UVT, CT, lambda p: np.array([0, -1.0, -0.2]))
    rim = np.stack([PT[:, -1], PT[:, -1] - thick], axis=1)
    part.grid(rim, np.stack([UVT[:, -1], UVT[:, -1] + [0, 0.005]], axis=1), np.tile(dark, (len(sel), 2, 1)),
              lambda p: np.array([p[0], -0.2, p[2] - axis[1]]))
    # two buttons over the peak, holding the fold-down flap
    for sx in (1.0, -1.0):
        a = sx * 0.16
        i = int(np.argmin(np.abs(a_s - a)))
        _button(part, P[i, 2] + np.array([0, 0.004, 0]), _dir(a), 0.0055, rgba("4a4434"))
    return part.finish()


def flat_cap(hull, meta, color, band="2b2925", badge=False, big=False):
    """A docker's flat cap: a low crown whose top panel is drawn forward over a short stiff peak and
    puffs out a little at the sides, a button on top (UVs in metres, for a tweed twill). With `badge`, a
    tram company's small brass oval pinned to the front of the crown above the peak. With `big`, a cap a size
    too big for the boy under it: looser all round, sitting down over the ears, fuller, its peak longer and
    drooping."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "flat")
    A = 60
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.025) for a in a_s]) + 0.005
    R[-1] = R[0]
    cosa = np.cos(a_s)
    front = (1.0 + cosa) * 0.5
    y_band = yb(a_s)
    if big:
        R = R + 0.011
        y_band = y_band - 0.013 * (1.0 - front) + 0.004 * front
    col = np.array(rgba(color))
    # the crown covers the skull, but the top panel is a slope: just over the crown of the head at the back,
    # coming down in front almost to the peak (a wedge seen from the side), rounded and a little puffed at the sides
    top = meta["head"]["top"]
    brow = meta["head"]["brow"]
    lift = 0.008 if not big else 0.017
    y_edge = (top + lift) - ((top + lift) - (brow + (0.032 if not big else 0.042))) * front ** 1.7
    H = y_edge - y_band
    rings = [  # (fraction up, extra radius, forward pull, side puff)
        (-0.06, 0.000, 0.000, 0.00),
        (0.10, 0.001, 0.000, 0.00),
        (0.30, 0.005, 0.003, 0.40),
        (0.62, 0.008, 0.007, 1.00),
        (0.86, 0.006, 0.011, 0.90),
        (1.00, -0.002, 0.014, 0.50),
    ]
    disc = [(0.72, 0.003), (0.45, 0.005), (0.2, 0.006), (0.0, 0.006)]
    nv = len(rings) + len(disc)
    P = np.zeros((A + 1, nv, 3))
    C = np.zeros((A + 1, nv, 4))
    wob = 0.0018 * np.sin(4 * a_s + 0.4) + 0.0012 * np.sin(9 * a_s)
    for j, (f, extra, pull, puff) in enumerate(rings):
        y = y_band + H * f
        side = np.abs(np.sin(a_s)) ** 1.5
        rr = R + extra + puff * (0.006 * side + 0.006 * front ** 2) * (1.8 if big else 1.0) + (wob if j >= 2 else 0.0)
        P[:, j, 0] = np.sin(a_s) * rr
        P[:, j, 1] = y
        P[:, j, 2] = axis[1] + pull * (1.6 if big else 1.0) + np.cos(a_s) * rr
        C[:, j] = col * ([0.78, 0.78, 0.78, 1.0] if j == 0 else [1.0, 1.0, 1.0, 1.0])
    edge = P[:, len(rings) - 1]
    centre = edge.mean(axis=0)
    for k, (f, dome) in enumerate(disc):
        j = len(rings) + k
        P[:, j] = centre + (edge - centre) * f
        P[:, j, 1] = edge[:, 1] * f + (1 - f) * max(edge[:, 1].mean() + 0.010, top + 0.012) + dome * (1 - f) * 0.6
        C[:, j] = col
    flat = hull.push_out(P.reshape(-1, 3), c + np.array([0, -0.02, 0]), 0.004)
    P = flat.reshape(P.shape)
    UV = arc_uv(P)
    part.grid(P, UV, C, lambda p: p - np.array([0.0, c[1] - 0.03, axis[1]]))
    # the band's lower edge turned in
    inner = P[:, 0].copy()
    inner[:, 0] -= np.sin(a_s) * 0.003
    inner[:, 2] -= np.cos(a_s) * 0.003
    inner[:, 1] += 0.006
    P2 = np.stack([inner, P[:, 0]], axis=1)
    part.grid(P2, np.stack([UV[:, 0] + [0, 0.01], UV[:, 0]], axis=1), np.stack([C[:, 0] * [0.5, 0.5, 0.5, 1], C[:, 0]], axis=1),
              lambda p: np.array([0, -1.0, 0]))
    # the short stiff peak, tucked under the panel
    sel = np.nonzero(np.abs(a_s) <= np.radians(64))[0]
    pitch = 0.30 if not big else 0.36
    nt = 5
    PT = np.zeros((len(sel), nt, 3))
    for ii, i in enumerate(sel):
        a = a_s[i]
        L = (0.040 if not big else 0.052) * max(np.cos(a / np.radians(64) * np.pi / 2), 0.0) ** 0.5
        base = P[i, 0] + np.array([0, 0.003, 0])
        d = _dir(a)
        for t in range(nt):
            q = t / (nt - 1)
            PT[ii, t] = base + d * (L * q * np.cos(pitch)) - np.array([0, 1, 0]) * (L * q * np.sin(pitch))
    thick = np.array([0, 0.004, 0])
    dark = col * [0.70, 0.70, 0.68, 1.0]
    UVT = np.stack([PT[..., 0], PT[..., 2]], axis=-1)
    part.grid(PT, UVT, np.tile(col * [0.9, 0.9, 0.88, 1], (len(sel), nt, 1)), lambda p: np.array([0, 1.0, 0.3]))
    part.grid(PT - thick, UVT, np.tile(dark, (len(sel), nt, 1)), lambda p: np.array([0, -1.0, -0.2]))
    rim = np.stack([PT[:, -1], PT[:, -1] - thick], axis=1)
    part.grid(rim, np.stack([UVT[:, -1], UVT[:, -1] + [0, 0.005]], axis=1), np.tile(dark, (len(sel), 2, 1)),
              lambda p: np.array([p[0], -0.2, p[2] - axis[1]]))
    # the cloth button on top
    top = P[:, -1].mean(axis=0)
    _button(part, top + np.array([0, 0.001, 0]), np.array([0, 1.0, 0.1]), 0.006, rgba(band))
    if badge:
        # on the front of the cap, where the panel slopes back from the peak: found by height along the front
        # profile, square to the cloth there
        i = int(np.argmin(np.abs(a_s)))
        col_p = P[i]
        want = col_p[0, 1] + 0.027
        j = int(np.searchsorted(col_p[:, 1], want))
        j = min(max(j, 1), len(col_p) - 1)
        t = (want - col_p[j - 1, 1]) / max(col_p[j, 1] - col_p[j - 1, 1], 1e-6)
        at = col_p[j - 1] + (col_p[j] - col_p[j - 1]) * np.clip(t, 0.0, 1.0)
        tv = col_p[j] - col_p[j - 1]
        tu = P[i + 1, j] - P[i - 1, j]
        n = np.cross(tu, tv)
        if n[2] < 0:
            n = -n
        n /= np.linalg.norm(n)
        _tram_badge(part, at + n * 0.0012, n)
    return part.finish()


def _tram_badge(part, at, normal):
    """An invented tram company's cap badge: a small brass oval, wider than it is tall, with a raised rim, a
    dark enamelled field and a brass bar across it (vertex alpha 0 = metal; the enamel is cloth-dark, alpha 1)."""
    n = normal / np.linalg.norm(normal)
    e1 = np.cross([0, 1, 0], n)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    seg = 22
    brass = rgba("c49a4a", 0.0)
    shade = rgba("8e6c2c", 0.0)
    enamel = rgba("1d2230")
    for (rx, ry, lift, colr, dome) in ((0.0165, 0.0118, 0.0006, shade, 0.0), (0.0150, 0.0104, 0.0016, brass, 0.0006),
                                       (0.0118, 0.0076, 0.0024, enamel, 0.0004)):
        centre = part.add(at + n * (lift + dome), [0, 0], colr)
        ring = []
        for k in range(seg + 1):
            t = 2 * np.pi * k / seg
            ring.append(part.add(at + n * lift + e1 * np.cos(t) * rx + e2 * np.sin(t) * ry, [np.cos(t) * rx, np.sin(t) * ry], colr))
        for k in range(seg):
            part.tri(centre, ring[k], ring[k + 1], lambda p: n)
    # the bar across the middle, and a small boss at its centre (a wheel's hub, nothing more)
    q = [part.add(at + n * 0.0031 + e1 * sx * 0.0122 + e2 * sy * 0.0019, [sx * 0.012, sy * 0.002], brass) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    part.tri(q[0], q[1], q[2], lambda p: n)
    part.tri(q[0], q[2], q[3], lambda p: n)
    _button(part, at + n * 0.0030, n, 0.0036, brass, 12)


def sailor_cap(hull, meta, color, band="121212", tally="5a5444"):
    """A sailor's round cap: a black band (its tally lettering a faint line), a flat round top wider than the
    band, and the two black ribbons hanging down behind."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "sailor")
    A = 56
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.03) for a in a_s]) + 0.005
    R[-1] = R[0]
    R = np.maximum(R, np.median(R) * 0.96)
    y_band = yb(a_s)
    cb, ct, cc = np.array(rgba(band)), np.array(rgba(tally)), np.array(rgba(color))
    band_h = 0.030
    top = meta["head"]["top"]
    top_r = np.median(R) * 1.30 + 0.010
    # the dish rises from the band to a rim just under the crown of the head's height, the top over it
    rim = max(top - 0.006 - float(np.mean(y_band)), band_h + 0.012)
    rings = [  # (y offset, radius, colour)
        (-0.004, R, cb), (band_h * 0.42, R + 0.0015, cb), (band_h * 0.48, R + 0.0015, ct), (band_h * 0.56, R + 0.0015, cb),
        (band_h, R + 0.0015, cb), (band_h + 0.002, R + 0.003, cc),
        (rim - 0.006, np.full_like(R, top_r * 0.94), cc), (rim, np.full_like(R, top_r), cc),
        (rim + 0.005, np.full_like(R, top_r * 0.97), cc)]
    disc = [(0.66, 0.002), (0.33, 0.003), (0.0, 0.003)]
    P = np.zeros((A + 1, len(rings) + len(disc), 3))
    C = np.zeros((A + 1, len(rings) + len(disc), 4))
    for j, (dy, r, colr) in enumerate(rings):
        # the top sits a touch further back than the band: worn on the back of the head
        back = -0.006 * min(max(dy - band_h, 0.0) / 0.02, 1.0)
        P[:, j] = np.stack([np.sin(a_s) * r, y_band + dy, axis[1] + back + np.cos(a_s) * r], 1)
        C[:, j] = colr
    edge = P[:, len(rings) - 1]
    centre = edge.mean(axis=0)
    for k, (f, dome) in enumerate(disc):
        j = len(rings) + k
        P[:, j] = centre + (edge - centre) * f
        P[:, j, 1] = edge[:, 1] * f + (1 - f) * max(edge[:, 1].mean(), top + 0.006) + dome
        C[:, j] = cc
    part.grid(P, arc_uv(P), C, lambda p: p - np.array([0.0, c[1] - 0.03, axis[1]]))
    # the underside of the top, from the band out to the rim (seen from below)
    under = np.stack([P[:, 5], P[:, 7]], 1)
    part.grid(under, arc_uv(under), np.tile(cc * [0.55, 0.55, 0.6, 1], (A + 1, 2, 1)), lambda p: np.array([0, -1.0, 0]))
    # two ribbons from the back of the band, hanging down and a little apart
    rib = np.array(rgba(band))
    i_back = 0
    base = P[i_back, 2] + np.array([0, 0, -0.004])
    for sgn in (1.0, -1.0):
        pts = []
        for t in np.linspace(0.0, 1.0, 7):
            pts.append(base + np.array([sgn * (0.008 + 0.022 * t), -0.15 * t, -0.012 * t - 0.03 * t * t]))
        pts = np.array(pts)
        w = np.array([0.011, 0, 0])
        Pr = np.stack([pts - w, pts + w], 1)
        part.grid(Pr, arc_uv(Pr), np.tile(rib, (len(pts), 2, 1)), lambda p: np.array([0, 0.2, -1.0]))
        part.grid(Pr[:, ::-1], arc_uv(Pr[:, ::-1]), np.tile(rib * [0.7, 0.7, 0.7, 1], (len(pts), 2, 1)), lambda p: np.array([0, 0.2, 1.0]))
    return part.finish()


def _button(part, at, normal, r, color, seg=10):
    n = normal / np.linalg.norm(normal)
    e1 = np.cross(n, [0, 1, 0])
    if np.linalg.norm(e1) < 1e-6:
        e1 = np.array([1.0, 0, 0])
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    centre = part.add(at + n * 0.0022, [0, 0], color)
    ring = []
    for k in range(seg + 1):
        t = 2 * np.pi * k / seg
        ring.append(part.add(at + n * 0.0008 + (e1 * np.cos(t) + e2 * np.sin(t)) * r, [0, 0], color))
    for k in range(seg):
        part.tri(centre, ring[k], ring[k + 1], lambda p: n)


def beret(hull, meta, color, band_color="2a2119", badge=True):
    """A soft wool beret: the band straight across the brow, the crown pulled over to the right
    and down over the right ear, a badge over the left eye."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "beret")
    top = meta["head"]["top"]
    A = 64
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.02) for a in a_s]) + 0.004
    R[-1] = R[0]
    y_band = yb(a_s)
    col = np.array(rgba(color))
    bcol = np.array(rgba(band_color))
    circ = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(np.stack([np.sin(a_s) * R, np.cos(a_s) * R], 1), axis=0), axis=1))])
    # leather band: a short wall with a rolled lower edge
    band = [(y_band - 0.006, R - 0.001), (y_band - 0.004, R + 0.0015), (y_band + 0.006, R + 0.0015), (y_band + 0.008, R + 0.001)]
    P = np.zeros((A + 1, len(band), 3))
    for j, (y, r) in enumerate(band):
        P[:, j] = np.stack([np.sin(a_s) * r, y, axis[1] + np.cos(a_s) * r], 1)
    UVb = np.stack([np.tile(circ[:, None], (1, len(band))), np.tile(np.arange(len(band))[None] * 0.004, (A + 1, 1))], -1)
    part.grid(P, UVb, np.tile(bcol, (A + 1, len(band), 1)), lambda p: p - np.array([0, p[1], axis[1]]))
    # the crown: from the band, out under the overhang to the rim, round it, and over the top
    lean = np.array([-0.42, 1.0, 0.12])
    n_rim = lean / np.linalg.norm(lean)
    rim_c = np.array([-0.032, top - 0.036, axis[1] + 0.012])
    dome = 0.032
    fwd = np.array([0, 0, 1.0]) - n_rim * n_rim[2]
    fwd /= np.linalg.norm(fwd)
    left = np.cross(n_rim, fwd)
    rho = 0.124 - 0.010 * np.sin(a_s) + 0.004 * np.cos(a_s) + 0.005 * np.sin(3 * a_s + 0.4) + 0.003 * np.sin(5 * a_s + 1.3)
    rim = rim_c + rho[:, None] * (np.cos(a_s)[:, None] * fwd + np.sin(a_s)[:, None] * left)
    # the overhang on the right droops down over the ear
    right = np.clip(-np.sin(a_s), 0, 1) ** 1.6 * np.clip(0.6 - np.cos(a_s) * 0.4, 0, 1)
    rim[:, 1] -= 0.020 * right
    start = P[:, -1]
    rows = []
    # underside: band top -> rim, sagging a little
    for s in (0.0, 0.25, 0.5, 0.75, 0.92):
        mid = 0.5 * (start + rim) - n_rim * 0.008
        q = (1 - s) ** 2 * start + 2 * (1 - s) * s * mid + s * s * rim
        rows.append(q)
    # round the edge
    out = rim - rim_c
    out /= np.linalg.norm(out, axis=1, keepdims=True)
    rows.append(rim + out * 0.005 + n_rim * 0.005)
    rows.append(rim + n_rim * 0.011 + out * 0.001)
    # top: a soft dome from the rim over the crown of the head
    rim_top = rim + n_rim * 0.011
    centre = rim_top.mean(axis=0)
    for f in (0.86, 0.70, 0.52, 0.34, 0.17, 0.0):
        q = centre + (rim_top - centre) * f + n_rim * (dome * (1.0 - f * f))
        fold = 0.0025 * np.sin(4 * a_s + 0.3)[:, None] * n_rim * np.sin(np.pi * f)
        rows.append(q + fold)
    P = np.stack(rows, axis=1)
    flat = hull.push_out(P.reshape(-1, 3), c + np.array([0, -0.025, 0]), 0.0045)
    P = flat.reshape(P.shape)
    nv = P.shape[1]
    UV = arc_uv(P)
    shade = np.ones(nv)
    shade[:5] = np.linspace(0.62, 0.8, 5)
    C = np.tile(col, (A + 1, nv, 1)) * np.concatenate([np.tile(shade[None, :, None], (A + 1, 1, 3)), np.ones((A + 1, nv, 1))], -1)

    def outward(p):
        return p - (c + np.array([0, -0.03, 0]))
    ids = part.grid(P, UV, C, outward)
    if badge:
        a = 0.42
        i = int(np.argmin(np.abs(a_s - a)))
        at = P[i, 1] * 0.5 + P[i, 0] * 0.5 + np.array([0, 0.018, 0])
        n = outward(at)
        n[1] *= 0.3
        _badge(part, at + n / np.linalg.norm(n) * 0.003, n, meta)
    return part.finish()


def _badge(part, at, normal, meta):
    """A cap badge: a dark cloth backing and a small brass oval on it (vertex alpha 0 = metal)."""
    n = normal / np.linalg.norm(normal)
    e1 = np.cross([0, 1, 0], n)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    seg = 18
    backing = rgba("3a2a24")
    brass = rgba("b08a3e", 0.0)
    for (rx, ry, lift, colr, dome) in ((0.017, 0.020, 0.0008, backing, 0.0), (0.010, 0.013, 0.0024, brass, 0.0016), (0.0062, 0.0085, 0.0034, rgba("8a6a2c", 0.0), 0.0012)):
        centre = part.add(at + n * (lift + dome), [0, 0], colr)
        ring = []
        for k in range(seg + 1):
            t = 2 * np.pi * k / seg
            ring.append(part.add(at + n * lift + e1 * np.cos(t) * rx + e2 * np.sin(t) * ry, [np.cos(t) * rx, np.sin(t) * ry], colr))
        for k in range(seg):
            part.tri(centre, ring[k], ring[k + 1], lambda p: n)


def dense_points(pos, faces, keep, n=6):
    """Points spread over the faces whose vertices all pass keep(points) (a mask over pos)."""
    out = []
    grid = [(i / (n - 1), j / (n - 1)) for i in range(n) for j in range(n)]
    for f in faces:
        if len(f) != 4 or not all(keep[v] for v in f):
            if len(f) == 3 and all(keep[v] for v in f):
                a, b, c = pos[f[0]], pos[f[1]], pos[f[2]]
                for u, v in grid:
                    if u + v <= 1:
                        out.append(a + (b - a) * u + (c - a) * v)
            continue
        a, b, c, d = (pos[v] for v in f)
        for u, v in grid:
            out.append((a * (1 - u) + b * u) * (1 - v) + (d * (1 - u) + c * u) * v)
    return np.array(out)


def _circ_smooth(v, k):
    """Moving average of a closed loop sampled with v[-1] == v[0]."""
    body = v[:-1]
    n = len(body)
    out = np.zeros(n)
    for d in range(-k, k + 1):
        out += np.roll(body, d)
    out /= 2 * k + 1
    return np.concatenate([out, out[:1]])


def scarf(hull, meta, color, neck_pts, high=False, back_pts=None, roll=False, front_pts=None, stripe=None):
    """A knitted scarf wound twice round the neck, its end tucked down into the jacket. `high`: wound up to the
    jaw and thicker, three turns of it. With `back_pts` (the coat's points), one end is thrown back over the left
    shoulder and hangs down the back. `roll`: not a scarf but a jumper's roll neck, a snug knitted tube from inside
    the collar up the throat, turned over at the top. With `front_pts` (the jacket's), a long scarf wound once
    whose two ends hang down the chest, one longer than the other, striped across in `stripe` all their length."""
    part = Part("scarf")
    col = np.array(rgba(color))
    lm = meta["landmarks"]
    chin = lm["chin"][1]
    # the neck's axis: its centre at each height, from the skin around it
    def centre_at(y):
        q = neck_pts[np.abs(neck_pts[:, 1] - y) < 0.008]
        return 0.5 * (q[:, 2].max() + q[:, 2].min()) if len(q) else 0.0
    # what the scarf wraps: the neck and the collar close round it, not the shoulders
    near = []
    for q in hull.p:
        zc0 = centre_at(q[1])
        if np.hypot(q[0], q[2] - zc0) < 0.085:
            near.append(q)
    neck_hull = Hull(np.array(near))
    skin_hull = Hull(neck_pts)
    cp = hull.p[len(neck_pts):]
    collar_hull = Hull(cp[np.abs(cp[:, 0]) < 0.085])
    A = 56
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    front = (1 + np.cos(a_s)) * 0.5
    back = (1 - np.cos(a_s)) * 0.5
    sides = (1 - front - back ** 1.5).clip(0)
    if roll:
        # close round the throat, from inside the collar to a finger under the chin, the top turned over
        top_y = (chin - 0.016) * front + (chin + 0.032) * back ** 1.5 + (chin + 0.004) * sides
        bot_y = (chin - 0.078) * front + (chin - 0.026) * back ** 1.5 + (chin - 0.056) * sides
        rows = [(0.0, 0.002, 0.0), (0.15, 0.0055, 0.0), (0.5, 0.0065, 0.0), (0.8, 0.0080, 0.0), (0.9, 0.0105, 0.0),
                (0.96, 0.0100, 0.0), (1.0, 0.0050, 0.0)]
    elif high:
        # up under the jaw at the front and the ears at the sides, over the nape behind; down over the collar
        top_y = (chin + 0.002) * front + (chin + 0.060) * back ** 1.5 + (chin + 0.030) * sides
        bot_y = (chin - 0.066) * front + (chin - 0.020) * back ** 1.5 + (chin - 0.044) * sides
        rows = [(0.0, 0.002, 0.0), (0.10, 0.015, 0.5), (0.30, 0.028, 1.0), (0.50, 0.033, 1.0), (0.70, 0.031, 1.0),
                (0.86, 0.025, 0.7), (0.95, 0.017, 0.4), (1.0, 0.008, 0.2)]
    else:
        top_y = (chin - 0.008) * front + (chin + 0.044) * back ** 1.5 + (chin + 0.012) * sides
        bot_y = (chin - 0.046) * front + (chin - 0.012) * back ** 1.5 + (chin - 0.030) * sides
        # (fraction up, distance out from the neck, fold depth)
        rows = [(0.0, 0.002, 0.0), (0.12, 0.010, 0.4), (0.35, 0.019, 1.0), (0.58, 0.022, 1.0), (0.80, 0.020, 0.8),
                (0.93, 0.016, 0.5), (1.0, 0.008, 0.2)]
    P = np.zeros((A + 1, len(rows), 3))
    for j, (f, out, fold) in enumerate(rows):
        y = bot_y + (top_y - bot_y) * f
        zc = np.array([centre_at(v) for v in y])
        r = np.array([skin_hull.ring_radius((0.0, z), a, v - 0.008, v + 0.008, 9.0) for a, v, z in zip(a_s, y, zc)])
        rc = np.array([collar_hull.ring_radius((0.0, z), a, v - 0.010, v + 0.010, 12.0) for a, v, z in zip(a_s, y, zc)])
        r = _circ_smooth(r, 3)
        rc = _circ_smooth(rc, 4)
        r[-1] = r[0]
        rc[-1] = rc[0]
        twist = 2.2 * f
        folds = 0.006 * fold * (np.sin(6 * a_s + twist) * 0.7 + np.sin(11 * a_s - twist * 1.7) * 0.3)
        bunch = 0.010 * fold * np.exp(-((a_s - 0.4) / 0.45) ** 2)  # gathered at the front left
        rr = r + out + folds + bunch
        # the bottom tucks inside the jacket's collar; above it, stand clear of the collar
        rr = np.where(rc > 0, np.where(j == 0, np.minimum(rr, rc - 0.004), np.maximum(rr, rc + 0.004 * f)), rr)
        P[:, j, 0] = np.sin(a_s) * rr
        P[:, j, 1] = y + 0.002 * fold * np.sin(5 * a_s + 1.0)
        P[:, j, 2] = zc + np.cos(a_s) * rr
    UV = arc_uv(P)[:, :, ::-1]
    Cc = np.tile(col, (A + 1, len(rows), 1))
    Cc[:, 0] *= [0.7, 0.7, 0.7, 1]
    Cc[:, -1] *= [0.85, 0.85, 0.85, 1]
    axis_pts = np.stack([np.zeros(len(rows)), [r[0] for r in rows], np.zeros(len(rows))], 1)

    def outward(p):
        return np.array([p[0], 0.0, p[2] - centre_at(p[1])])
    if roll:
        # the turned-over top a shade lighter where the light catches its fold; no shadow under it
        Cc[:, 0] = col * [0.8, 0.8, 0.8, 1]
        Cc[:, -3:-1] *= [1.06, 1.06, 1.06, 1]
    part.grid(P, UV, Cc, outward)
    if front_pts is not None:
        # both ends come off the turn at the front, a little apart, and hang down over the jacket
        for a0, x1, hang, k in ((0.30, 0.040, 0.985, 0), (-0.22, -0.050, 1.105, 1)):
            i0 = int(np.argmin(np.abs(a_s - a0)))
            _scarf_front_end(part, P[i0, 3], np.concatenate([front_pts, P.reshape(-1, 3)]), col, np.array(rgba(stripe or "2a2420")),
                             x1, hang, phase=0.37 * k)
    if back_pts is not None:
        # where the wound scarf's outer turn is, round the back of the left side of the neck: the end leaves it there
        i0 = int(np.argmin(np.abs(a_s - 2.35)))
        _scarf_end(part, P[i0, 4], np.concatenate([back_pts, P.reshape(-1, 3)]), col)
    return part.finish(bone=2)


def _scarf_end(part, start, back_pts, col, width=0.070, thick=0.010, hang=1.10):
    """One end of a scarf thrown back over the shoulder: from the turn at the back of the neck it lies down the back
    of the coat, a little to the left of the spine and slanting in, to `hang` (metres up); a flat knitted band with
    some thickness, two darker stripes across it near the end. Above the chest joint it rides the chest; lower down
    it is shared with the spine, so the back can bend under it."""
    q = np.asarray(back_pts, dtype=np.float64)
    # rows along it; each stripe's edges are doubled, so the colour changes sharply there
    edges = np.array([0.74, 0.79, 0.85, 0.90])
    ts = np.sort(np.concatenate([np.linspace(0.0, 1.0, 19), edges, edges]))
    n_t = len(ts)
    y0 = float(start[1])
    xs = 0.075 * (1 - ts) + 0.045 * ts + 0.004 * np.sin(ts * 7.0)
    ys = y0 - (y0 - hang) * ts
    half = width * 0.5

    def back_z(x, y, r=0.016):
        """The back of the coat (its collar, near the top) at (x, y): None where there is none."""
        for rr in (r, 2 * r):
            sel = (np.abs(q[:, 0] - x) < rr) & (np.abs(q[:, 1] - y) < rr)
            if sel.any():
                return float(q[sel, 2].min())
        return None

    # the surface it lies on, across its width (the coat's back curves away to the sides); it bridges hollows
    zs = np.full((n_t, 3), np.nan)
    for k, (x, y) in enumerate(zip(xs, ys)):
        for m, dx in enumerate((-half, 0.0, half)):
            z = back_z(x + dx, y)
            if z is not None:
                zs[k, m] = z
    for m in range(3):
        col_z = zs[:, m]
        good = ~np.isnan(col_z)
        col_z[~good] = np.interp(np.nonzero(~good)[0], np.nonzero(good)[0], col_z[good]) if good.any() else -0.10
        col_z = np.minimum.accumulate(col_z) * 0.25 + col_z * 0.75
        zs[:, m] = np.convolve(np.pad(col_z, 2, mode="edge"), np.ones(5) / 5.0, mode="valid")
    # the first stretch comes off the neck's turn and settles on to the collar; nowhere does it go under the coat
    blend = np.clip(ts / 0.22, 0.0, 1.0)
    outer = np.zeros((n_t, 2, 3))
    inner = np.zeros((n_t, 2, 3))
    for k in range(n_t):
        for s_i, (m, dx) in enumerate(((0, -half), (2, half))):
            lie = np.array([xs[k] + dx, ys[k], zs[k, m] - 0.006 - thick])
            off = np.array([start[0] + dx * 0.8, start[1] - 0.004, start[2] - 0.004])
            p = off + (lie - off) * blend[k] ** 0.7 if k < n_t - 1 else lie
            p[1] = ys[k] + 0.003 * np.sin(ts[k] * 34.0) * (1 - blend[k] * 0.5)
            under = back_z(p[0], p[1], 0.012)
            if under is not None:
                p[2] = min(p[2], under - 0.004 - thick)
            outer[k, s_i] = p
            inner[k, s_i] = p + np.array([0, 0, thick])
    def stripe(t):
        return 0.58 if (0.74 <= t < 0.79 or 0.85 <= t < 0.90) else 1.0
    # the first of a doubled row takes the colour before the edge, the second the colour after it
    shade = [stripe(t - 1e-6) if (k + 1 < n_t and ts[k + 1] == t) else stripe(t + 1e-6) for k, t in enumerate(ts)]
    C = np.array([[col * [f, f, f, 1.0]] * 2 for f in shade])

    def skin(p):
        w = float(np.clip((1.24 - p[1]) / 0.16, 0.0, 0.7))
        return ((2, 1, 0, 0), (1.0 - w, w, 0.0, 0.0))
    part.skin = skin
    UVo = arc_uv(outer)
    part.grid(outer, UVo, C, lambda p: np.array([0, 0.1, -1.0]))
    part.grid(inner, UVo, C * [0.6, 0.6, 0.6, 1.0], lambda p: np.array([0, 0.1, 1.0]))
    for s_i, sgn in ((0, -1.0), (1, 1.0)):
        edge = np.stack([outer[:, s_i], inner[:, s_i]], 1)
        part.grid(edge, arc_uv(edge), np.stack([C[:, s_i], C[:, s_i] * [0.8, 0.8, 0.8, 1]], 1), lambda p, s=sgn: np.array([s, 0, 0]))
    end = np.stack([outer[-1], inner[-1]], 1)
    part.grid(end, arc_uv(end), np.tile(col * [0.7, 0.7, 0.7, 1], (2, 2, 1)), lambda p: np.array([0, -1.0, 0]))
    part.skin = None


def _scarf_front_end(part, start, front_pts, col, scol, x1, hang, width=0.064, thick=0.008, phase=0.0):
    """One end of a long scarf hanging down the front from the turn round the neck to `hang` (metres up), drifting
    to `x1` across: a flat knitted band lying on the jacket's front (it bridges the hollows), striped across all its
    length in `scol`, a fringe of darker tufts at its end. It rides the chest, shared with the spine lower down."""
    q = np.asarray(front_pts, dtype=np.float64)
    # the stripes come in pairs, narrow, a hand apart
    period, bands = 0.115, ((0.0, 0.011), (0.022, 0.033))
    y0 = float(start[1])
    L = y0 - hang
    # rows along it, every stripe's edges doubled so the colour changes sharply there
    edges = []
    d = (phase % 1.0) * period
    while d < L:
        for b0, b1 in bands:
            for e in (d + b0, d + b1):
                if 0.0 < e < L:
                    edges.append(e / L)
        d += period
    edges = np.array(edges)
    ts = np.sort(np.concatenate([np.linspace(0.0, 1.0, 23), edges, edges]))
    n_t = len(ts)
    xs = start[0] * (1 - ts) + x1 * ts + 0.004 * np.sin(ts * 6.0 + phase * 9)
    ys = y0 - L * ts
    half = width * 0.5

    def front_z(x, y, r=0.016):
        for rr in (r, 2 * r, 4 * r):
            sel = (np.abs(q[:, 0] - x) < rr) & (np.abs(q[:, 1] - y) < rr)
            if sel.any():
                return float(q[sel, 2].max())
        return None

    zs = np.full((n_t, 3), np.nan)
    for k, (x, y) in enumerate(zip(xs, ys)):
        for m, dx in enumerate((-half, 0.0, half)):
            z = front_z(x + dx, y)
            if z is not None:
                zs[k, m] = z
    for m in range(3):
        col_z = zs[:, m]
        good = ~np.isnan(col_z)
        col_z[~good] = np.interp(np.nonzero(~good)[0], np.nonzero(good)[0], col_z[good]) if good.any() else 0.15
        zs[:, m] = np.convolve(np.pad(col_z, 2, mode="edge"), np.ones(5) / 5.0, mode="valid")
    blend = np.clip(ts / 0.18, 0.0, 1.0)
    outer = np.zeros((n_t, 2, 3))
    inner = np.zeros((n_t, 2, 3))
    for k in range(n_t):
        for s_i, (m, dx) in enumerate(((0, -half), (2, half))):
            lie = np.array([xs[k] + dx, ys[k], zs[k, m] + 0.005 + thick])
            off = np.array([start[0] + dx * 0.7, start[1], start[2] + 0.004])
            p = off + (lie - off) * blend[k] ** 0.7
            over = front_z(p[0], p[1], 0.012)
            if over is not None:
                p[2] = max(p[2], over + 0.004 + thick)
            outer[k, s_i] = p
            inner[k, s_i] = p - np.array([0, 0, thick])

    def stripe(t):
        dd = (t * L - (phase % 1.0) * period) % period
        return any(b0 <= dd < b1 for b0, b1 in bands)
    is_s = [stripe(t - 1e-7) if (k + 1 < n_t and ts[k + 1] == t) else stripe(t + 1e-7) for k, t in enumerate(ts)]
    C = np.array([[scol if s else col] * 2 for s in is_s])
    C[-2:] *= [0.75, 0.75, 0.75, 1]

    def skin(p):
        w = float(np.clip((1.24 - p[1]) / 0.16, 0.0, 0.7))
        return ((2, 1, 0, 0), (1.0 - w, w, 0.0, 0.0))
    part.skin = skin
    UVo = arc_uv(outer)
    part.grid(outer, UVo, C, lambda p: np.array([0, 0.1, 1.0]))
    part.grid(inner, UVo, C * [0.6, 0.6, 0.6, 1.0], lambda p: np.array([0, 0.1, -1.0]))
    for s_i, sgn in ((0, -1.0), (1, 1.0)):
        edge = np.stack([outer[:, s_i], inner[:, s_i]], 1)
        part.grid(edge, arc_uv(edge), np.stack([C[:, s_i], C[:, s_i] * [0.8, 0.8, 0.8, 1]], 1), lambda p, s=sgn: np.array([s, 0, 0]))
    # the fringe: a row of short tufts below the end
    for f in np.linspace(-0.8, 0.8, 7):
        top = 0.5 * (outer[-1, 0] + outer[-1, 1]) + (outer[-1, 1] - outer[-1, 0]) * 0.5 * f
        tuft = np.stack([np.stack([top - [0.0035, 0, 0], top + [0.0035, 0, 0]]),
                         np.stack([top + [-0.002, -0.022, 0.002], top + [0.002, -0.022, 0.002]])])
        part.grid(tuft, arc_uv(tuft), np.tile(scol * [0.8, 0.8, 0.8, 1], (2, 2, 1)), lambda p: np.array([0, 0, 1.0]))
    part.skin = None


def moustache(meta, skin, spec, kind="walrus"):
    """A moustache with body: a thick, slightly drooping brush over the upper lip, its hairs
    combed down and out, the lower edge breaking into tips (alpha-cut)."""
    part = Part("tache")
    lm = meta["landmarks"]
    head = skin.pos[(skin.bones[:, 0] == HEAD_BONE) & (skin.weights[:, 0] > 0.9) & (skin.pos[:, 2] > 0.05)]

    def face_z(x, y):
        d = (head[:, 0] - x) ** 2 + (head[:, 1] - y) ** 2
        near = d < 0.0035 ** 2
        if near.sum() < 3:
            near = np.argsort(d)[:6]
        return float(head[near, 2].max())

    nb, mo, cx = lm["nose_base"][1], lm["mouth"][1], abs(lm["corner"][0])
    walrus = kind == "walrus"
    pencil = kind == "pencil"
    half = cx * (1.38 if walrus else (1.04 if pencil else 1.30))
    nu, nv = 25, 9
    P = np.zeros((nu, nv, 3))
    UV = np.zeros((nu, nv, 2))
    thick = spec.get("tache_thick", 0.0058 if walrus else (0.0022 if pencil else 0.0042))
    for i in range(nu):
        u = (i / (nu - 1)) * 2.0 - 1.0
        au = abs(u)
        x = u * half
        if walrus:
            y_top = nb - 0.0008 - 0.0125 * au ** 1.3
            y_bot = mo - 0.0028 - 0.0075 * au ** 1.7
        elif pencil:
            # a thin dark line close along the upper lip, out to the corners of the mouth
            lip = lm["upper_lip"][1]
            y_bot = lip + 0.0006 - 0.0032 * au ** 1.6
            y_top = y_bot + 0.0048 - 0.0016 * au
        else:
            # a full chevron moustache, out past the corners of the mouth, its lower edge on the lip
            y_top = nb - 0.0010 - 0.0105 * au ** 1.3
            y_bot = mo - 0.0012 - 0.0045 * au ** 1.7
        for j in range(nv):
            v = j / (nv - 1)
            y = y_top + (y_bot - y_top) * v
            body = np.sin(np.pi * min(v * 1.08, 1.0)) ** 0.55 * (1.0 - 0.65 * au ** 2.5) * (1.0 + 0.25 * np.exp(-(u / 0.12) ** 2) * 0)
            z = face_z(x, y) + 0.0006 + thick * body
            # the brush bulges forward and down at its lower edge
            P[i, j] = [x * (1.0 + 0.08 * v * au), y - 0.0015 * v * v, z]
            UV[i, j] = [0.5 + u * 0.46 + 0.10 * u * v, 0.02 + 0.96 * v]
    C = np.ones((nu, nv, 4))
    part.grid(P, UV, C, lambda p: np.array([p[0] * 4.0, -0.2, 1.0]))
    return part.finish()


# --- tiling cloth textures -----------------------------------------------------------------------
def _tile_noise(size, cutoff, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((size, size)))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    r = np.sqrt(fx * fx + fy * fy)
    f *= np.exp(-(r / cutoff) ** 2)
    n = np.real(np.fft.ifft2(f))
    return (n - n.mean()) / (n.std() + 1e-9)


def _normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-gx, gy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def weave_textures(kind, size=256):
    """(detail L image with 0.5 = as dyed, normal RGB image) for 'felt', 'twill' or 'knit'."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    if kind == "felt":
        h = 0.6 * _tile_noise(size, 0.25, 1) + 0.4 * _tile_noise(size, 0.06, 2)
        d = 1.0 + 0.10 * _tile_noise(size, 0.03, 3) + 0.05 * h
        nm = _normal_from_height(h, 0.35)
    elif kind == "twill":
        period = 5.0
        ph = (x + y) / period * 2 * np.pi
        ridge = np.sin(ph) * 0.5 + 0.5
        h = ridge + 0.25 * _tile_noise(size, 0.2, 4)
        d = 1.0 + 0.10 * (ridge - 0.5) + 0.06 * _tile_noise(size, 0.04, 5)
        nm = _normal_from_height(h, 0.8)
    elif kind == "steel":
        h = 0.3 * _tile_noise(size, 0.05, 8) + 0.1 * _tile_noise(size, 0.015, 9)
        d = 1.0 + 0.035 * _tile_noise(size, 0.03, 10) + 0.02 * h
        nm = _normal_from_height(h, 0.12)
    elif kind == "leather":
        h = 0.5 * _tile_noise(size, 0.08, 11) + 0.25 * np.sin(y / size * 2 * np.pi * 9 + 2.0 * _tile_noise(size, 0.02, 12)) 
        d = 1.0 + 0.06 * _tile_noise(size, 0.04, 13) + 0.04 * h
        nm = _normal_from_height(h, 0.6)
    else:  # knit: stockinette, columns of V stitches
        cw, rh = 16.0, 14.0  # px per stitch
        u = (x % cw) / cw  # 0..1 across a column
        v = ((y + (x // cw) * 0.0) % rh) / rh
        # each stitch: two leaning lobes forming a V
        lobe = np.where(u < 0.5, u * 2.0, (1.0 - u) * 2.0)
        slant = np.abs((v - lobe * 0.45) - 0.35)
        h = np.clip(1.0 - slant * 2.8, 0, 1) * np.sin(np.pi * np.where(u < 0.5, u * 2, (u - 0.5) * 2)) ** 0.5
        h = h + 0.15 * _tile_noise(size, 0.15, 6)
        d = 0.78 + 0.32 * h + 0.06 * _tile_noise(size, 0.03, 7)
        nm = _normal_from_height(h, 2.2)
    d = np.clip(d * 0.5, 0, 1)
    return Image.fromarray((d * 255).astype(np.uint8), "L"), Image.fromarray(nm, "RGB")


def strand_texture(size=256, seed=5):
    """A moustache's hair: dark strands running down the texture, tips ragged at the bottom."""
    rng = np.random.default_rng(seed)
    img = np.zeros((size, size, 4))
    lum = 0.30 + 0.16 * rng.standard_normal(size)
    cols = np.convolve(lum, np.ones(2) / 2, mode="same")
    tips = 0.80 + 0.17 * rng.random(size)
    tips = np.minimum(tips, np.convolve(tips, np.ones(3) / 3, mode="same") + 0.04)
    v = np.linspace(0, 1, size)[:, None]
    l = np.clip(cols[None, :] * (0.75 + 0.35 * (1 - v)), 0.02, 1)
    img[..., 0] = l * 1.0
    img[..., 1] = l * 0.85
    img[..., 2] = l * 0.72
    alpha = (v < tips[None, :]).astype(np.float64)
    top = np.clip(v / 0.04, 0, 1)
    img[..., 3] = alpha * top
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")


# --- legs: trousers bloused into canvas anklets ---------------------------------------------------
SHIN_L, SHIN_R = 11, 14


def leg_axis(skin, side_bone, y):
    """Centre (x, z) and radius of the leg's skin at height y."""
    leg = np.isin(skin.bones[:, 0], [side_bone - 1, side_bone, side_bone + 1])
    side = skin.pos[:, 0] * (1.0 if side_bone == SHIN_L else -1.0) > 0.0
    q = None
    for win in (0.01, 0.025, 0.05):
        q = skin.pos[leg & side & (np.abs(skin.pos[:, 1] - y) < win)]
        if len(q) >= 4:
            break
    if q is None or len(q) < 4:
        return None
    cx, cz = 0.5 * (q[:, 0].max() + q[:, 0].min()), 0.5 * (q[:, 2].max() + q[:, 2].min())
    r = np.hypot(q[:, 0] - cx, q[:, 2] - cz).max()
    return cx, cz, r


def tuck_trousers(suit, skin, top_y, blouse=0.018):
    """Pulls the trouser legs in round the shins below top_y (they go into the anklets) and lets
    them blouse a little over the anklets' tops."""
    pos = suit.pos.astype(np.float64)
    for bone in (SHIN_L, SHIN_R):
        sel = (suit.bones[:, 0] == bone) & (pos[:, 1] < top_y + 0.06)
        for i in np.nonzero(sel)[0]:
            y = pos[i, 1]
            ax = leg_axis(skin, bone, min(max(y, 0.12), top_y))
            if ax is None:
                continue
            cx, cz, r = ax
            d = np.array([pos[i, 0] - cx, pos[i, 2] - cz])
            cur = np.linalg.norm(d)
            if cur < 1e-6:
                continue
            tight = r + 0.007
            if y < top_y:
                want = tight
                t = 1.0
            else:
                t = 1.0 - (y - top_y) / 0.06
                want = cur * (1 - t) + (tight + blouse * np.sin(np.pi * t)) * t
            new = min(cur, want) if y < top_y else want
            pos[i, 0] = cx + d[0] / cur * new
            pos[i, 2] = cz + d[1] / cur * new
    suit.pos = pos.astype(np.float32)
    suit.nrm = smooth_normals(pos, suit.idx.astype(np.int64), 1e-5).astype(np.float32)


def anklets(skin, boots, color, strap="3a3024", height=0.095, straps=True, name="gaiters", flare=0.004, straight=False):
    """Canvas anklets (gaiters) over the tops of the boots, two straps and buckles on the outside;
    or, taller and without straps, the shafts of jackboots. `straight`: rubber boots, whose shafts stand
    straight up from the calf to the top, as wide as the calf all the way."""
    part = Part(name)
    col = np.array(rgba(color))
    scol = np.array(rgba(strap))
    A = 28
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    tops = []
    for bone, sgn in ((SHIN_L, 1.0), (SHIN_R, -1.0)):
        part.bone = bone
        bq = boots.pos[(boots.pos[:, 0] * sgn > 0)]
        # the shoe's collar (shoes03 carries socks up the shin: they stay inside)
        shoe_top = min(float(np.percentile(bq[:, 1], 99.5)), 0.125)
        y0, y1 = shoe_top - 0.018, shoe_top + height
        tops.append(y1)
        rows = []
        fs = (0.0, 0.08, 0.5, 0.92, 1.0) if height < 0.15 else (0.0, 0.05, 0.18, 0.35, 0.55, 0.75, 0.92, 1.0)
        widest = 0.0
        for f in fs:
            y = y0 + (y1 - y0) * f
            ax = leg_axis(skin, bone, max(y, 0.10))
            cx, cz, r = ax
            if straight:
                widest = max(widest, r) if f >= 0.3 else widest
                r = max(r, widest)
            # boot collar below, the trouser cloth bunched inside above
            ring = []
            for a in a_s:
                d = np.array([np.sin(a), 0, np.cos(a)])
                rr = r + 0.011 + flare * f + (0.003 if f in (0.0, 1.0) else 0.0)
                rr = max(rr, _ring_r(bq, cx, cz, a, y) + 0.003)
                ring.append([cx + d[0] * rr, y, cz + d[2] * rr])
            rows.append(ring)
        P = np.array(rows).transpose(1, 0, 2)
        UV = arc_uv(P)
        C = np.tile(col, (A + 1, len(fs), 1))
        C[:, 0] *= [0.8, 0.8, 0.8, 1]
        C[:, -1] *= [0.85, 0.85, 0.85, 1]
        ctr = P.mean(axis=(0, 1))

        def outward(p, cx=cx, cz=cz):
            return np.array([p[0] - cx, 0.0, p[2] - cz])
        part.grid(P, UV, C, outward)
        # two straps round the outside, each with a buckle
        for fy in ((0.28, 0.72) if straps else ()):
            y = y0 + (y1 - y0) * fy
            band = []
            for a in np.linspace(sgn * 0.35, sgn * 2.4, 9):
                d = np.array([np.sin(a), 0, np.cos(a)])
                ax = leg_axis(skin, bone, y)
                rr = ax[2] + 0.012 + 0.004 * fy + 0.0025
                band.append([ax[0] + d[0] * rr, y, ax[1] + d[2] * rr])
            band = np.array(band)
            Pb = np.stack([band - [0, 0.008, 0], band + [0, 0.008, 0]], axis=1)
            part.grid(Pb, arc_uv(Pb), np.tile(scol, (len(band), 2, 1)), lambda p, cx=ax[0], cz=ax[1]: np.array([p[0] - cx, 0, p[2] - cz]))
            mid = band[len(band) // 2]
            out = np.array([mid[0] - ax[0], 0, mid[2] - ax[1]])
            _button(part, mid + out / np.linalg.norm(out) * 0.0015, out, 0.0055, rgba("8c7a4c", 0.0), 4)
    part.bone = None
    return part.finish(), min(tops)


def _ring_r(pts, cx, cz, a, y, half_deg=12.0):
    q = pts[np.abs(pts[:, 1] - y) < 0.006]
    if len(q) == 0:
        return 0.0
    dx, dz = q[:, 0] - cx, q[:, 2] - cz
    ang = np.arctan2(dx, dz)
    diff = np.abs((ang - a + np.pi) % (2 * np.pi) - np.pi)
    m = diff < np.radians(half_deg)
    return float(np.hypot(dx[m], dz[m]).max()) if m.any() else 0.0


# --- the garrison's kit ---------------------------------------------------------------------------
def helmet(hull, meta, color, tilt=0.0, roll=0.0):
    """A steel helmet: a deep bowl low over the brow, a short visor, the skirt flaring out over the
    ears and the back of the neck, a rolled edge and a chin strap. `tilt` pushes it back (+) or
    down over the eyes (-), `roll` cants it to one side (radians)."""
    part = Part("hat")
    col = np.array(rgba(color))
    c = head_axis(meta)
    hc = c + np.array([0.0, -0.012, -0.004])
    yb = hat_band(meta, "helmet")
    A = 48
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    S = [0.0, 0.12, 0.26, 0.40, 0.54, 0.66, 0.76, 0.84, 0.90, 0.95, 1.0]
    P = np.zeros((A + 1, len(S), 3))
    for i, a in enumerate(a_s):
        y_rim = yb(a)
        # how far down from the crown this azimuth's rim sits (angle from straight up)
        R0 = 0.118
        th_r = np.arccos(np.clip((y_rim - hc[1]) / R0, -0.95, 0.99))
        th = np.array(S) * th_r
        d = np.stack([np.sin(th) * np.sin(a), np.cos(th), np.sin(th) * np.cos(a)], 1)
        d[0] = [0, 1, 0]
        r = hull.radius(hc, d, 9.0) + 0.012
        r = np.maximum(r, 0.085)
        # the skirt flares out below the step; the visor juts at the front
        front = max(np.cos(a), 0.0) ** 2
        flare = np.clip((np.array(S) - 0.80) / 0.20, 0, 1) ** 1.4 * (0.020 + 0.008 * (1 - front))
        P[i] = hc + d * (r + flare)[:, None]
        # the visor and the skirt's lip run more level than the bowl
        P[i, -2:, 1] += np.array([0.002, 0.006]) * (0.5 + 0.5 * front)
    # smooth the crown radially (the hull is lumpy where the hair was)
    for _ in range(2):
        inner = P[:-1, 1:6].copy()
        P[:-1, 1:6] = 0.5 * inner + 0.25 * (np.roll(inner, 1, axis=0) + np.roll(inner, -1, axis=0))
        P[-1] = P[0]
    P[:, 0] = P[:, 0].mean(axis=0)
    # cant and tilt about the crown
    R = axis_angle([1, 0, 0], -tilt) @ axis_angle([0, 0, 1], roll)
    P = (P - hc) @ R.T + hc
    UV = arc_uv(P)
    C = np.tile(col, (A + 1, len(S), 1))

    def outward(p):
        return p - hc
    part.grid(P, UV, C, outward)
    # rolled edge: back up inside the rim
    rim = P[:, -1]
    toward = hc - rim
    toward /= np.linalg.norm(toward, axis=1, keepdims=True)
    inner = rim + toward * 0.004 + np.array([0, 0.004, 0])
    P2 = np.stack([rim, inner], 1)
    part.grid(P2, arc_uv(P2), np.tile(col * [0.55, 0.55, 0.55, 1], (A + 1, 2, 1)), lambda p: np.array([0, -1.0, 0]))
    # chin strap: from inside the skirt over each ear, under the chin
    lm = meta["landmarks"]
    chin = np.array(lm["chin"]) + np.array([0, -0.004, -0.012])
    strap = np.array(rgba("1d1b18"))
    for sgn in (1.0, -1.0):
        i = int(np.argmin(np.abs(a_s - sgn * np.pi * 0.5)))
        top = P[i, -3] + np.array([-sgn * 0.004, 0, 0.004])
        pts = []
        for t in np.linspace(0, 1, 7):
            q = top * (1 - t) + chin * t
            q[0] = top[0] * (1 - t) ** 0.6 + chin[0] * (1 - (1 - t) ** 0.6)
            pts.append(q)
        pts = np.array(pts)
        flat = hull.push_out(pts, hc + np.array([0, -0.05, 0.01]), 0.003)
        side = np.array([0, 0, 0.0055])
        Ps = np.stack([flat - side, flat + side], 1)
        part.grid(Ps, arc_uv(Ps), np.tile(strap, (len(pts), 2, 1)), lambda p, s=sgn: np.array([s * 1.0, -0.3, 0.2]))
    return part.finish()


def service_cap(hull, meta, crown, band="2c322e", visor="141312", piping="b9bab3", soft=False, disc=None):
    """A peaked service cap: a dark band, the crown rising high at the front over it, a steep
    glossy visor and a silver chin cord. `soft`: a soft cap of one cloth all over, its crown low and
    unstiffened, no piping, a black leather chin strap; with `disc` (a colour), a plain round metal disc on the
    front of the crown over the band, and nothing on it."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "service" if not soft else "peaked")
    top = meta["head"]["top"]
    A = 56
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.03) for a in a_s]) + 0.005
    R[-1] = R[0]
    front = (1 + np.cos(a_s)) * 0.5
    y_band = yb(a_s)
    cb, cc, cp = np.array(rgba(band)), np.array(rgba(crown)), np.array(rgba(piping, 0.0))
    if soft:
        # the crown sags a little over the band at the sides, rises only a little in front
        crown_top = np.maximum(top + 0.004, y_band + 0.038) + 0.010 * front ** 2 - 0.003 * np.sin(a_s) ** 2
        rings = [
            (y_band - 0.004, R, cb), (y_band + 0.026, R + 0.002, cb), (y_band + 0.029, R + 0.003, cc),
            (y_band + 0.036, R * 1.08 + 0.004, cc), (crown_top - 0.012, R * 1.24 + 0.012 * front, cc),
            (crown_top - 0.004, R * 1.26 + 0.013 * front, cc), (crown_top, R * 1.20 + 0.010 * front, cc)]
    else:
        crown_top = np.maximum(top + 0.006, y_band + 0.050) + 0.024 * front ** 2
        rings = [  # (y, radius, colour)
            (y_band - 0.004, R, cb), (y_band + 0.032, R + 0.002, cb), (y_band + 0.035, R + 0.004, cp), (y_band + 0.038, R + 0.004, cc),
            (y_band + 0.048, R * 1.07 + 0.004, cc), (crown_top - 0.012, R * 1.20 + 0.010 * front, cc), (crown_top - 0.004, R * 1.24 + 0.012 * front, cp),
            (crown_top, R * 1.20 + 0.010 * front, cc)]
    P = np.zeros((A + 1, len(rings) + 3, 3))
    C = np.zeros((A + 1, len(rings) + 3, 4))
    for j, (y, r, colr) in enumerate(rings):
        P[:, j] = np.stack([np.sin(a_s) * r, y, axis[1] + 0.006 * j / len(rings) + np.cos(a_s) * r], 1)
        C[:, j] = colr
    edge = P[:, len(rings) - 1]
    centre = edge.mean(axis=0)
    for k, f in enumerate((0.66, 0.33, 0.0)):
        j = len(rings) + k
        P[:, j] = centre + (edge - centre) * f
        P[:, j, 1] = edge[:, 1] * f + (1 - f) * (crown_top.mean() - 0.004)
        C[:, j] = cc
    flat = hull.push_out(P.reshape(-1, 3), c + np.array([0, -0.02, 0]), 0.004)
    P = flat.reshape(P.shape)
    part.grid(P, arc_uv(P), C, lambda p: p - np.array([0.0, c[1] - 0.03, axis[1]]))
    # the visor: steep and glossy (alpha 0.5 = lacquer)
    sel = np.nonzero(np.abs(a_s) <= np.radians(68))[0]
    vc = np.array(rgba(visor, 0.5))
    nt = 5
    PT = np.zeros((len(sel), nt, 3))
    for ii, i in enumerate(sel):
        a = a_s[i]
        L = 0.050 * max(np.cos(a / np.radians(68) * np.pi / 2), 0.0) ** 0.5
        base = P[i, 0] + np.array([0, 0.003, 0])
        d = _dir(a)
        for t in range(nt):
            s = t / (nt - 1)
            PT[ii, t] = base + d * (L * s * np.cos(0.62)) - np.array([0, 1, 0]) * (L * s * np.sin(0.62))
    thick = np.array([0, 0.003, 0])
    part.grid(PT, arc_uv(PT), np.tile(vc, (len(sel), nt, 1)), lambda p: np.array([0, 1.0, 0.5]))
    part.grid(PT - thick, arc_uv(PT), np.tile(vc, (len(sel), nt, 1)), lambda p: np.array([0, -1.0, -0.3]))
    # chin cord across the front of the band, a button at each end (the soft cap: a black leather strap)
    cord = np.array(rgba(piping, 0.0)) if not soft else np.array(rgba("17150f", 0.5))
    sel2 = np.nonzero(np.abs(a_s) <= np.radians(58))[0]
    pts = P[sel2, 0] + np.array([0, 0.010, 0])
    out = pts - np.array([0, pts[0, 1], axis[1]])
    out[:, 1] = 0
    out /= np.linalg.norm(out, axis=1, keepdims=True)
    pts = pts + out * 0.0025
    hw = 0.0022 if not soft else 0.0034
    Pc = np.stack([pts - [0, hw, 0], pts + [0, hw, 0]], 1)
    part.grid(Pc, arc_uv(Pc), np.tile(cord, (len(pts), 2, 1)), lambda p: np.array([p[0], 0, p[2] - axis[1]]))
    for e in (0, -1):
        _button(part, pts[e] + out[e] * 0.001, out[e], 0.004, cord if not soft else np.array(rgba("6e7173", 0.0)), 8)
    if disc is not None:
        # on the front of the crown, just over the band: found on the front profile, square to the cloth there
        i = int(np.argmin(np.abs(a_s)))
        col_p = P[i]
        want = col_p[0, 1] + (0.046 if soft else 0.050)
        j = int(np.searchsorted(col_p[:len(rings), 1], want))
        j = min(max(j, 1), len(rings) - 1)
        t = (want - col_p[j - 1, 1]) / max(col_p[j, 1] - col_p[j - 1, 1], 1e-6)
        at = col_p[j - 1] + (col_p[j] - col_p[j - 1]) * np.clip(t, 0.0, 1.0)
        n = np.cross(P[i + 1, j] - P[i - 1, j], col_p[j] - col_p[j - 1])
        if n[2] < 0:
            n = -n
        n /= np.linalg.norm(n)
        _plain_disc(part, at + n * 0.0012, n, np.array(rgba(disc, 0.0)))
    return part.finish()


def _plain_disc(part, at, normal, colr, r=0.0115):
    """A plain round metal disc with a raised rim, nothing on it (vertex alpha 0 = metal)."""
    n = normal / np.linalg.norm(normal)
    e1 = np.cross([0, 1, 0], n)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    seg = 22
    for (rr, lift, shade, dome) in ((r, 0.0005, 0.62, 0.0), (r * 0.86, 0.0016, 1.0, 0.0010)):
        cc = colr * [shade, shade, shade, 1.0]
        centre = part.add(at + n * (lift + dome), [0, 0], cc)
        ring = [part.add(at + n * lift + (e1 * np.cos(t) + e2 * np.sin(t)) * rr, [np.cos(t) * rr, np.sin(t) * rr], cc)
                for t in np.linspace(0, 2 * np.pi, seg + 1)]
        for k in range(seg):
            part.tri(centre, ring[k], ring[k + 1], lambda p: n)


HIPS_B, THIGH_L_B, THIGH_R_B = 0, 10, 13


def coat_skirt(suit_pts, color, top_y=1.06, hem=0.42, belt=None, window=0.0, narrow=1.0, fine=False, room=0.0):
    """A greatcoat's skirt from the waist to below the knee, cut wide enough to walk in. Skinned
    to the hips, its lower part following each thigh (the halves meet at the front and back). With
    `belt` (a colour), the coat's own cloth belt round the waist over the join, a covered buckle in front.
    `window` (metres): each row stands outside the body over that much above and below it too, so that a
    jacket's flared hem between two rows stays inside the skirt."""
    part = Part("coat")
    col = np.array(rgba(color))
    A = 40
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    if hem > 0.7:
        # a tunic's skirt: over the belt to the top of the thigh
        ys = [top_y, 1.02, 0.97, 0.92, hem + 0.025, hem]
        blends = {top_y: 0.0, 1.02: 0.0, 0.97: 0.1, 0.92: 0.22, hem + 0.025: 0.32, hem: 0.36}
    elif fine:
        # more rows over the hips, so that the skirt follows a jacket's flared hem and a woman's hips closely
        ys = [top_y, 1.035, 1.0, 0.965, 0.93, 0.87, 0.80, 0.70, 0.58, hem + 0.04, hem]
        blends = {top_y: 0.0, 1.035: 0.0, 1.0: 0.02, 0.965: 0.08, 0.93: 0.16, 0.87: 0.28, 0.80: 0.42, 0.70: 0.58, 0.58: 0.70,
                  hem + 0.04: 0.76, hem: 0.78}
    else:
        ys = [top_y, 0.99, 0.92, 0.82, 0.70, 0.58, hem + 0.04, hem]
        blends = {top_y: 0.0, 0.99: 0.0, 0.92: 0.18, 0.82: 0.40, 0.70: 0.58, 0.58: 0.70, hem + 0.04: 0.76, hem: 0.78}
    zc = float(np.median(suit_pts[np.abs(suit_pts[:, 1] - 1.0) < 0.02][:, 2])) if len(suit_pts) else 0.0
    P = np.zeros((A + 1, len(ys), 3))
    for j, y in enumerate(ys):
        t = (top_y - y) / (top_y - hem)
        for i, a in enumerate(a_s):
            r_body = _ring_r(suit_pts, 0.0, zc, a, y, 14.0) if window <= 0.0 else \
                max(_ring_r(suit_pts, 0.0, zc, a, y + dy, 14.0) for dy in np.linspace(-window, window, 5))
            ell = np.hypot(np.sin(a) * (0.175 + 0.045 * t), np.cos(a) * (0.13 + 0.04 * t)) * (narrow + (1.0 - narrow) * min(t / 0.3, 1.0)) \
                if hem < 0.7 else 0.0
            # soft vertical folds, deeper towards the hem
            rr = max(r_body + 0.010 + 0.006 * t, ell) + room * t + (0.0035 * np.sin(9 * a + 1.0) + 0.002 * np.sin(14 * a + 0.3)) * t
            P[i, j] = [np.sin(a) * rr, y, zc + np.cos(a) * rr]
    P[-1] = P[0]
    C = np.tile(col, (A + 1, len(ys), 1))
    C[:, -1] *= [0.75, 0.75, 0.75, 1]

    def skin(p):
        b = blends[min(blends, key=lambda yy: abs(yy - p[1]))]
        mid = abs(p[0]) < 0.02
        if mid:
            return ((HIPS_B, THIGH_L_B, THIGH_R_B, 0), (1 - b, b * 0.5, b * 0.5, 0))
        return ((HIPS_B, THIGH_L_B if p[0] > 0 else THIGH_R_B, 0, 0), (1 - b, b, 0, 0))
    part.skin = skin
    part.grid(P, arc_uv(P), C, lambda p: np.array([p[0], 0, p[2] - zc]))
    # the hem turned up inside
    hem_pts = P[:, -1]
    inner = hem_pts.copy()
    inner[:, 1] += 0.03
    inner[:, 0] *= 0.97
    inner[:, 2] = zc + (inner[:, 2] - zc) * 0.97
    P2 = np.stack([hem_pts, inner], 1)
    part.grid(P2, arc_uv(P2), np.tile(col * [0.5, 0.5, 0.5, 1], (A + 1, 2, 1)), lambda p: np.array([-p[0], 0, -(p[2] - zc)]))
    part.skin = None
    if belt is not None:
        _coat_belt(part, suit_pts, P[:, 0], zc, a_s, np.array(rgba(belt)))
    return part.finish()


def _coat_belt(part, suit_pts, skirt_top, zc, a_s, bcol, y0=1.034, y1=1.078):
    """A cloth belt round an overcoat's waist: standing just off the skirt's top and the jacket above it, its
    edges rolled in, and a cloth-covered buckle at the front. Shared between the hips and the spine."""
    r_top = np.hypot(skirt_top[:, 0], skirt_top[:, 2] - zc)
    r_up = np.array([_ring_r(suit_pts, 0.0, zc, a, y1, 14.0) for a in a_s])
    r = _circ_smooth(np.maximum(r_top, r_up) + 0.005, 2)
    r[-1] = r[0]
    rows = [(y0, r - 0.004), (y0 + 0.003, r), (y1 - 0.003, r), (y1, r - 0.004)]
    P = np.stack([np.stack([np.sin(a_s) * rr, np.full_like(a_s, y), zc + np.cos(a_s) * rr], 1) for y, rr in rows], 1)
    C = np.tile(bcol, (len(a_s), len(rows), 1))
    C[:, 0] *= [0.7, 0.7, 0.7, 1]
    C[:, -1] *= [0.8, 0.8, 0.8, 1]
    part.skin = lambda p: ((0, 1, 0, 0), (0.55, 0.45, 0, 0))
    part.grid(P, arc_uv(P), C, lambda p: np.array([p[0], 0, p[2] - zc]))
    # the buckle: a squarish frame of the same cloth standing a little proud of the belt at the front
    i = int(np.argmin(np.abs(a_s)))
    front = np.array([0.0, 0.5 * (y0 + y1), zc + r[i] + 0.002])
    out = np.array([0, 0, 1.0])
    for (hx, hy, lift, shade) in ((0.030, 0.027, 0.003, 0.85), (0.019, 0.016, 0.0045, 1.12)):
        q = [part.add(front + np.array([sx * hx, sy * hy, lift]), [sx * hx, sy * hy], bcol * [shade, shade, shade, 1])
             for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        part.tri(q[0], q[1], q[2], lambda p: out)
        part.tri(q[0], q[2], q[3], lambda p: out)
    part.skin = None


# --- Operation Riachuelo: La Boca's winter clothes, 1958 -------------------------------------------
def _wall(hull, axis, a_s, ys, clear, smooth_k=2, floor=0.05):
    """A ring of points standing `clear` off the hull at each angle, at heights ys (one per angle)."""
    r = np.array([hull.ring_radius(axis, a, y - 0.008, y + 0.008, 8.0) for a, y in zip(a_s, ys)])
    r = _circ_smooth(np.maximum(r, floor), smooth_k)
    r[-1] = r[0]
    return np.stack([np.sin(a_s) * (r + clear), ys, axis[1] + np.cos(a_s) * (r + clear)], 1)


def knit_cap(hull, meta, color, flaps=False):
    """A knitted wool cap pulled down snug over the skull, the crown gathered a little above the head (UVs in
    metres, for the knit). Without `flaps`, a sailor's beanie with its cuff turned up all round; with them, a
    lineman's cap whose sides come down over the ears as two flaps to the jaw, a tie of yarn hanging from each."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "earflap" if flaps else "knit")
    top = meta["head"]["top"]
    A = 64
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    y_band = yb(a_s)
    col = np.array(rgba(color))
    clear = 0.0065
    y_edge = top - 0.028
    rows = [_wall(hull, axis, a_s, y_band + (y_edge - y_band) * f, clear) for f in (0.0, 0.22, 0.45, 0.7, 1.0)]
    edge = rows[-1]
    centre = edge.mean(axis=0)
    apex = top + (0.024 if not flaps else 0.016)
    for f in (0.86, 0.68, 0.48, 0.28, 0.1, 0.0):
        q = centre + (edge - centre) * f
        q[:, 1] = edge[:, 1] + (apex - edge[:, 1]) * np.sqrt(max(1.0 - f * f, 0.0))
        rows.append(q)
    P = np.stack(rows, axis=1)
    P = hull.push_out(P.reshape(-1, 3), c + np.array([0, -0.02, 0]), 0.0055).reshape(P.shape)
    nv = P.shape[1]
    C = np.tile(col, (A + 1, nv, 1))
    # the stitches gathered into the crown: ribs of shade running up to it
    for j in range(nv):
        C[:, j, :3] *= (0.94 + 0.06 * np.cos(12 * a_s))[:, None] if j >= 4 else 1.0
    UV = arc_uv(P)

    def outward(p):
        return p - np.array([0.0, c[1] - 0.03, axis[1]])
    part.grid(P, UV, C, outward)
    rb = np.hypot(P[:, 0, 0], P[:, 0, 2] - axis[1])
    if flaps:
        # a rolled rib round the edge, and a bobble on top
        roll = [(-0.003, 0.001, 0.62), (-0.001, 0.0062, 0.80), (0.010, 0.0068, 0.92), (0.016, 0.0020, 0.85)]
        Q = np.stack([np.stack([np.sin(a_s) * (rb + d), y_band + dy, axis[1] + np.cos(a_s) * (rb + d)], 1) for dy, d, _ in roll], 1)
        Cq = np.stack([np.tile(col * [k, k, k, 1], (A + 1, 1)) * np.array([0.9 + 0.1 * np.cos(40 * a_s), ] * 3 + [np.ones(A + 1)]).T for _, _, k in roll], 1)
        part.grid(Q, arc_uv(Q), Cq, outward)
        apex_p = P[:, -1].mean(axis=0)
        bob = np.zeros((15, 9, 3))
        for ii, th in enumerate(np.linspace(0, 2 * np.pi, 15)):
            for jj, ph in enumerate(np.linspace(-np.pi / 2, np.pi / 2, 9)):
                rr = 0.021 * (1.0 + 0.10 * np.sin(5 * th + 3 * ph) * np.cos(ph))
                bob[ii, jj] = apex_p + [rr * np.cos(ph) * np.cos(th), 0.016 + rr * np.sin(ph), rr * np.cos(ph) * np.sin(th)]
        part.grid(bob, arc_uv(bob) * 0.6, np.tile(col * [1.12, 1.12, 1.12, 1], (15, 9, 1)), lambda p, cc=apex_p + [0, 0.016, 0]: p - cc)
    if not flaps:
        # the turned-up cuff: a second thickness of knit round the bottom, its lower edge rolled
        cuff = [(-0.004, 0.002, 0.70), (-0.001, 0.0085, 0.86), (0.034, 0.0095, 0.95), (0.040, 0.0040, 0.80)]
        Q = np.stack([np.stack([np.sin(a_s) * (rb + d), y_band + dy, axis[1] + np.cos(a_s) * (rb + d)], 1) for dy, d, _ in cuff], 1)
        Cq = np.stack([np.tile(col * [k, k, k, 1], (A + 1, 1)) for _, _, k in cuff], 1)
        part.grid(Q, arc_uv(Q), Cq, outward)
        return part.finish()
    # the flaps: each side of the cap carried on down over the ear to the jaw, hanging straight off the ear, rounded
    # at the bottom; the cap's edge across the forehead and the nape stays where it is
    chin = meta["head"]["chin"]
    for sgn in (1.0, -1.0):
        mid = sgn * np.pi * 0.5 + sgn * 0.10
        half = 0.66
        sel = np.nonzero(np.abs(a_s - mid) <= half)[0]
        nf = 7
        F = np.zeros((len(sel), nf, 3))
        for ii, i in enumerate(sel):
            a = a_s[i]
            w = np.cos((a - mid) / half * np.pi * 0.5)
            L = (y_band[i] - (chin + 0.010)) * max(w, 0.0) ** 0.45
            prev = None
            for k in range(nf):
                y = y_band[i] + 0.006 - (L + 0.006) * k / (nf - 1)
                r = hull.ring_radius(axis, a, y - 0.010, y + 0.010, 9.0)
                r = max(r, 0.055) + clear + 0.002
                if prev is not None:
                    r = max(r, prev - 0.003)
                prev = r
                F[ii, k] = [np.sin(a) * r, y, axis[1] + np.cos(a) * r]
        Cf = np.tile(col, (len(sel), nf, 1))
        Cf[:, -1] *= [0.82, 0.82, 0.82, 1]
        part.grid(F, arc_uv(F), Cf, outward)
        # its inside, and the thickness along the bottom
        inner = F.copy()
        inner[..., 0] -= np.sin(a_s[sel])[:, None] * 0.0045
        inner[..., 2] -= np.cos(a_s[sel])[:, None] * 0.0045
        part.grid(inner, arc_uv(inner), Cf * [0.55, 0.55, 0.55, 1], lambda p: -outward(p))
        rim = np.stack([F[:, -1], inner[:, -1]], 1)
        part.grid(rim, arc_uv(rim), np.tile(col * [0.7, 0.7, 0.7, 1], (len(sel), 2, 1)), lambda p: np.array([0, -1.0, 0]))
        # the tie: a twist of yarn from the bottom of the flap, hanging loose
        b = F[len(sel) // 2, -1]
        o = np.array([np.sin(mid), 0, np.cos(mid)])
        pts = np.array([b + np.array([0, -0.065 * t, 0]) + o * (0.002 + 0.006 * t * t) + np.array([0, 0, 0.004 * t]) for t in np.linspace(0, 1, 6)])
        side = np.cross(o, [0, 1, 0]) * 0.0042
        T = np.stack([pts - side, pts + side], 1)
        part.grid(T, arc_uv(T), np.tile(col * [0.9, 0.9, 0.9, 1], (len(pts), 2, 1)), lambda p, o=o: o)
        part.grid(T[:, ::-1], arc_uv(T[:, ::-1]), np.tile(col * [0.6, 0.6, 0.6, 1], (len(pts), 2, 1)), lambda p, o=o: -o)
    return part.finish()


def fedora(hull, meta, color, band="221f1c"):
    """A felt hat with a brim: an oval crown a little roomier than the head, pinched at the front and creased down
    the middle of the top, a dark ribbon band, the brim snapped down at the front and turned up a little at the
    sides and back (UVs in metres, for the felt)."""
    part = Part("hat")
    c = head_axis(meta)
    axis = (0.0, c[2])
    yb = hat_band(meta, "fedora")
    top = meta["head"]["top"]
    A = 64
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    R = np.array([hull.ring_radius(axis, a, yb(a) - 0.004, yb(a) + 0.03) for a in a_s]) + 0.0075
    R = _circ_smooth(R, 3)
    R[-1] = R[0]
    y_band = yb(a_s)
    cosa, sina = np.cos(a_s), np.sin(a_s)
    front = (1 + cosa) * 0.5
    back = (1 - cosa) * 0.5
    col, bcol = np.array(rgba(color)), np.array(rgba(band))
    y_rim = np.maximum(y_band + 0.084 - 0.008 * front, top + 0.024)
    pinch = np.exp(-((np.abs(a_s) - 0.48) / 0.24) ** 2)
    # the crown's wall, the band round its foot
    walls = [(0.0, 0.0, bcol), (0.0, 0.0018, bcol), (0.26, 0.0018, bcol), (0.27, 0.0, col), (0.55, -0.003, col), (0.82, -0.006, col),
             (0.95, -0.008, col), (1.0, -0.010, col)]
    rows, cols = [], []
    for f, d, cc in walls:
        rr = R * (1.0 - 0.05 * f) + d - 0.013 * pinch * smooth(np.full_like(R, f), 0.35, 1.0)
        y = y_band + (y_rim - y_band) * f
        rows.append(np.stack([sina * rr, y, axis[1] + cosa * rr], 1))
        cols.append(np.tile(cc, (A + 1, 1)))
    # the top: in from the rim of the crown, creased down the middle from the front to the back
    edge = rows[-1]
    centre = edge.mean(axis=0)
    zc = centre[2]
    for g in (0.82, 0.62, 0.42, 0.22, 0.0):
        q = centre + (edge - centre) * g
        q[:, 1] = edge[:, 1] * g + (1 - g) * (y_rim.mean() + 0.008)
        dent = 0.017 * np.exp(-(q[:, 0] / 0.026) ** 2) * np.clip(1.0 - ((q[:, 2] - zc) / 0.115) ** 2, 0.0, 1.0)
        q[:, 1] -= dent
        rows.append(q)
        cols.append(np.tile(col, (A + 1, 1)))
    P = np.stack(rows, axis=1)
    C = np.stack(cols, axis=1)
    P = hull.push_out(P.reshape(-1, 3), c + np.array([0, -0.02, 0]), 0.006).reshape(P.shape)

    def outward(p):
        return p - np.array([0.0, c[1] - 0.04, axis[1]])
    part.grid(P, arc_uv(P), C, outward)
    # the brim: out from the foot of the crown, snapped down in front, curled up at the sides and back
    W = 0.056 - 0.008 * back
    base = P[:, 0]
    nt = 5
    B = np.zeros((A + 1, nt, 3))
    for k in range(nt):
        t = k / (nt - 1)
        rr = np.hypot(base[:, 0], base[:, 2] - axis[1]) + W * t
        dy = -0.017 * t ** 1.4 * front ** 2.5 + 0.010 * t ** 2 * sina ** 2 + 0.012 * t ** 2 * back ** 2
        B[:, k] = np.stack([sina * rr, base[:, 1] - 0.001 + dy, axis[1] + cosa * rr], 1)
    thick = np.array([0, 0.0035, 0])
    UVb = np.stack([B[..., 0], B[..., 2]], -1)
    part.grid(B, UVb, np.tile(col, (A + 1, nt, 1)), lambda p: np.array([0, 1.0, 0]))
    part.grid(B - thick, UVb, np.tile(col * [0.62, 0.62, 0.62, 1], (A + 1, nt, 1)), lambda p: np.array([0, -1.0, 0]))
    rim = np.stack([B[:, -1], B[:, -1] - thick], 1)
    part.grid(rim, arc_uv(rim), np.tile(bcol * [1.2, 1.2, 1.2, 1], (A + 1, 2, 1)), lambda p: np.array([p[0], 0, p[2] - axis[1]]))
    # the bow on the band, on the left side
    i = int(np.argmin(np.abs(a_s - 1.75)))
    at = P[i, 1] * 0.5 + P[i, 2] * 0.5
    o = np.array([sina[i], 0, cosa[i]])
    for dz in (-0.006, 0.006):
        q = [part.add(at + o * 0.002 + np.array([0, sy * 0.010, 0]) + np.cross(o, [0, 1, 0]) * (dz + sx * 0.005), [0, 0], bcol * [0.9, 0.9, 0.9, 1])
             for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        part.tri(q[0], q[1], q[2], lambda p, o=o: o)
        part.tri(q[0], q[2], q[3], lambda p, o=o: o)
    return part.finish()


def headscarf(hull, meta, color, neck_pts):
    """A headscarf tied under the chin: the cloth over the head from the top of the forehead, round the face over the
    ears, falling loose from the back of the skull to a point over the nape (it stands off the neck, it does not
    cling), its two ends brought under the jaw and knotted there (UVs in metres, for a woven wool). The face is open
    from the chin to the forehead; a darker hem runs round the cloth's edges."""
    part = Part("hat")
    h = meta["head"]
    lm = meta["landmarks"]
    c = head_axis(meta)
    axis = (0.0, c[2])
    top, brow, chin = h["top"], h["brow"], h["chin"]
    A = 72
    a_s = np.linspace(-np.pi, np.pi, A + 1)
    col = np.array(rgba(color))
    nh = Hull(np.concatenate([hull.p, neck_pts]))
    face = np.radians(50.0)
    # the face's opening is the same columns on every row, but each row spreads its columns so the opening is round:
    # narrow round the chin, widest across the cheekbones and the forehead
    widths = [0.60, 0.62, 0.78, 0.86, 0.84]

    def spread(w):
        b = np.abs(a_s)
        return np.sign(a_s) * np.where(b <= face, b * w / face, w + (b - face) * (np.pi - w) / (np.pi - face))
    angles = [spread(w) for w in widths]
    heights = []
    for j, aj in enumerate(angles):
        fb = ((1 + np.cos(aj)) * 0.5) ** 1.6
        point = np.exp(-((np.pi - np.abs(aj)) / 0.55) ** 2)
        # rows from the bottom edge up to the edge across the forehead, as heights at each angle
        heights.append([
            (chin - 0.030) * fb + (1.525 - 0.055 * point) * (1 - fb),    # under the jaw; the point over the nape behind
            (chin - 0.010) * fb + (1.575 - 0.020 * point) * (1 - fb),
            (chin + 0.028) * fb + 1.625 * (1 - fb),
            0.5 * (chin + brow) * fb + 1.672 * (1 - fb),
            (brow + 0.046) * fb + (brow + 0.004) * (1 - fb),
        ][j])
    clears = [0.012, 0.010, 0.009, 0.009, 0.009]
    R = []
    for ys, cl, aj in zip(heights, clears, angles):
        r = np.array([nh.ring_radius(axis, a, y - 0.010, y + 0.010, 10.0) for a, y in zip(aj, ys)])
        r = np.maximum(_circ_smooth(np.maximum(r, 0.050), 1), r)
        r[-1] = r[0]
        R.append(r + cl)
    # behind the face the cloth hangs from the widest part of the skull: never in again going down
    hang = smooth(np.abs(a_s), 0.95, 1.45)
    for j in range(len(R) - 2, -1, -1):
        R[j] = R[j] * (1 - hang) + np.maximum(R[j], R[j + 1] + 0.002 * (len(R) - 1 - j)) * hang
    rows = [np.stack([np.sin(aj) * r, ys, axis[1] + np.cos(aj) * r], 1) for r, ys, aj in zip(R, heights, angles)]
    ring = rows[-1]
    centre = np.array([0.0, ring[:, 1].mean(), axis[1]])
    for t in (0.25, 0.48, 0.68, 0.85, 0.96, 1.0):
        ang = t * np.pi * 0.5
        q = centre + (ring - centre) * np.cos(ang)
        q[:, 1] = ring[:, 1] + (top + 0.013 - ring[:, 1]) * np.sin(ang)
        rows.append(q)
    P = np.stack(rows, axis=1)
    P[:, 1:] = hull.push_out(P[:, 1:].reshape(-1, 3), c + np.array([0, -0.02, 0]), 0.008).reshape(P[:, 1:].shape)
    nv = P.shape[1]
    UV = arc_uv(P)
    C = np.tile(col, (A + 1, nv, 1))
    for i, a in enumerate(a_s):
        # soft folds where it is gathered, the hem darker along the face and the bottom edge
        C[i, :, :3] *= 0.93 + 0.07 * np.cos(9 * a + 0.5) * np.cos(4 * a)
        if abs(abs(a) - face) < 0.12:
            C[i, 1:5, :3] *= 0.78
    C[:, 0, :3] *= 0.78
    ids = np.zeros((A + 1, nv), dtype=np.int64)
    for i in range(A + 1):
        for j in range(nv):
            ids[i, j] = part.add(P[i, j], UV[i, j], C[i, j])

    def outward(p):
        return p - np.array([0.0, min(p[1], c[1]), axis[1]])
    for i in range(A):
        mid_a = 0.5 * (a_s[i] + a_s[i + 1])
        for j in range(nv - 1):
            # the face is open from under the chin to the forehead
            if abs(mid_a) < face and 1 <= j < 4:
                continue
            a, b, cc, d = ids[i, j], ids[i + 1, j], ids[i + 1, j + 1], ids[i, j + 1]
            part.tri(a, b, cc, outward)
            part.tri(a, cc, d, outward)
    # the inside of the cloth, seen round the face and under the hanging back
    inner = P.copy()
    out_a = np.arctan2(P[..., 0], P[..., 2] - axis[1])
    inner[..., 0] -= np.sin(out_a) * 0.003
    inner[..., 2] -= np.cos(out_a) * 0.003
    for i in range(A):
        mid_a = 0.5 * (a_s[i] + a_s[i + 1])
        for j in range(4):
            if abs(mid_a) < face and 1 <= j < 4:
                continue
            q = [part.add(inner[ii, jj], UV[ii, jj], col * [0.55, 0.55, 0.55, 1]) for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            part.tri(q[0], q[1], q[2], lambda p: -outward(p))
            part.tri(q[0], q[2], q[3], lambda p: -outward(p))
    # the knot under the chin and its two short ends
    k0 = np.array([0.0, chin - 0.028, lm["chin"][2] - 0.016])
    for dx, rx, ry, rz in ((-0.008, 0.011, 0.009, 0.010), (0.008, 0.011, 0.009, 0.010)):
        Q = np.zeros((13, 7, 3))
        for ii, th in enumerate(np.linspace(0, 2 * np.pi, 13)):
            for jj, ph in enumerate(np.linspace(-np.pi / 2, np.pi / 2, 7)):
                Q[ii, jj] = k0 + [dx + rx * np.cos(ph) * np.cos(th), ry * np.sin(ph), rz * np.cos(ph) * np.sin(th)]
        part.grid(Q, arc_uv(Q), np.tile(col * [0.85, 0.85, 0.85, 1], (13, 7, 1)), lambda p, cc=k0 + [dx, 0, 0]: p - cc)
    for sx in (-1.0, 1.0):
        pts = np.array([k0 + [sx * (0.004 + 0.012 * t), -0.008 - 0.038 * t, 0.008 + 0.004 * t] for t in np.linspace(0, 1, 5)])
        T = np.stack([pts - [0.0075, 0, 0], pts + [0.0075, 0, 0]], 1)
        part.grid(T, arc_uv(T), np.tile(col * [0.88, 0.88, 0.88, 1], (5, 2, 1)), lambda p: np.array([0, 0, 1.0]))
        part.grid(T[:, ::-1], arc_uv(T[:, ::-1]), np.tile(col * [0.55, 0.55, 0.55, 1], (5, 2, 1)), lambda p: np.array([0, 0, -1.0]))
    return part.finish()


CHEST_B, SPINE_B, ARM_L_B, ARM_R_B = 2, 1, 4, 7


def cape(suit_pts, color, hem=1.02, gap=0.20, zc=0.02):
    """A short cape over the greatcoat's shoulders: a turned-down collar round the neck, then the cape falling
    straight off the shoulders to `hem` (metres up), open down the front (`gap`: half the opening, radians).
    Its middle rides the chest and spine; its sides partly follow the upper arms, so they swing a little under it
    (UVs in metres, for the felt). Surface "cape"."""
    part = Part("cape")
    col = np.array(rgba(color))
    A = 44
    a_s = np.linspace(gap, 2 * np.pi - gap, A + 1)
    ys = [1.530, 1.505, 1.478, 1.452, 1.425, 1.39, 1.33, 1.25, 1.17, hem + 0.03, hem]
    q = np.asarray(suit_pts, dtype=np.float64)
    P = np.zeros((A + 1, len(ys), 3))
    prev = None
    for j, y in enumerate(ys):
        r = np.array([_ring_r(q, 0.0, zc, a, y, 12.0) for a in a_s])
        if (r <= 0).any():
            r[r <= 0] = r[r > 0].mean() if (r > 0).any() else 0.12
        r = np.convolve(np.pad(r, 2, mode="edge"), np.ones(5) / 5.0, mode="valid")
        t = max(0.0, (1.45 - y) / (1.45 - hem))
        r = r + 0.010 + 0.006 * (j <= 1) + 0.055 * t ** 1.2
        if prev is not None and y < 1.46:
            # below the shoulders it hangs, and flares: never in again
            r = np.maximum(r, prev + 0.004)
        prev = r
        folds = 0.004 * t * np.sin(11 * a_s + 0.6)
        P[:, j] = np.stack([np.sin(a_s) * (r + folds), np.full(A + 1, y), zc + np.cos(a_s) * (r + folds)], 1)
    # round over the shoulders: each radius of the rows that turn the shoulder eased towards its neighbours'
    for _ in range(2):
        rr = np.hypot(P[:, :, 0], P[:, :, 2] - zc)
        sm = rr.copy()
        sm[:, 2:6] = 0.25 * rr[:, 1:5] + 0.5 * rr[:, 2:6] + 0.25 * rr[:, 3:7]
        k = sm / np.maximum(rr, 1e-6)
        P[:, :, 0] *= k
        P[:, :, 2] = zc + (P[:, :, 2] - zc) * k
    C = np.tile(col, (A + 1, len(ys), 1))
    C[:, 1] *= [0.72, 0.72, 0.72, 1]   # the collar's edge
    C[:, -1] *= [0.8, 0.8, 0.8, 1]

    def skin(p):
        a = np.arctan2(p[0], p[2] - zc)
        side = np.sin(a) ** 2
        down = float(np.clip((1.44 - p[1]) / 0.14, 0.0, 1.0))
        arm = 0.42 * side * down
        spine = 0.35 * (1.0 - side) * float(np.clip((1.26 - p[1]) / 0.2, 0.0, 1.0))
        return ((CHEST_B, ARM_L_B if p[0] > 0 else ARM_R_B, SPINE_B, 0), (1.0 - arm - spine, arm, spine, 0.0))
    part.skin = skin
    part.grid(P, arc_uv(P), C, lambda p: np.array([p[0], 0, p[2] - zc]))
    # the inside (seen at the opening and from below), the hem's thickness, the front edges
    inner = P.copy()
    inner[..., 0] -= np.sin(a_s)[:, None] * 0.004
    inner[..., 2] -= np.cos(a_s)[:, None] * 0.004
    part.grid(inner, arc_uv(inner), C * [0.45, 0.45, 0.45, 1], lambda p: -np.array([p[0], 0, p[2] - zc]))
    hemr = np.stack([P[:, -1], inner[:, -1]], 1)
    part.grid(hemr, arc_uv(hemr), np.tile(col * [0.6, 0.6, 0.6, 1], (A + 1, 2, 1)), lambda p: np.array([0, -1.0, 0]))
    for i, sgn in ((0, 1.0), (A, -1.0)):
        e = np.stack([P[i], inner[i]], 1)
        part.grid(e, arc_uv(e), np.tile(col * [0.7, 0.7, 0.7, 1], (len(ys), 2, 1)), lambda p, s=sgn: np.array([-s, 0, 0.6]))
    part.skin = None
    return part.finish()
