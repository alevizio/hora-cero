#!/usr/bin/env python3
"""Bakes the cast of Hora Cero from MakeHuman CC0 assets (dev tool, not shipped).

For each figure: morph the MakeHuman base mesh (age, build, face), fit clothes, hair, eyebrows,
eyelashes and eyes to it, curl the fingers into a relaxed grip, and bring the whole thing into the
game's bind pose and skeleton (19 bones, arms hanging, metres, joints exactly where operative.gd
expects them). Skin weights come from MakeHuman's own rig, folded into the game's bones.

Writes godot/assets/figures/<name>.fig (meshes, weights, measurements) and the shared textures.
    python3 tools/mh/mhbake.py [name ...]
"""
import json
import os
import struct
import sys
import types
import zlib

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import mhlib  # noqa: E402
import mhgear  # noqa: E402
from figures import FIGURES  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "figures")

# the game's bones (operative.gd) and bind-pose joints (metres)
HIPS, SPINE, CHEST, HEAD, ARM_L, FORE_L, HAND_L, ARM_R, FORE_R, HAND_R, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R = range(16)
BONE_COUNT = 19
Y_HIPS, Y_SPINE, Y_CHEST, Y_HEAD = 0.95, 1.08, 1.24, 1.525
Y_SHOULDER, Y_ELBOW, Y_WRIST = 1.445, 1.15, 0.885
X_HIP, Y_HIPJ, Y_KNEE, Y_ANKLE = 0.095, 0.93, 0.50, 0.085


def game_bones(sk, name):
    """Which game bones a MakeHuman bone's weight goes to: [(bone, share)]."""
    side = 0 if name.endswith(".L") else 1
    chain = sk.ancestors(name)
    if name == "neck01":
        return [(CHEST, 0.75), (HEAD, 0.25)]
    if name == "neck02":
        return [(CHEST, 0.3), (HEAD, 0.7)]
    if "neck03" in chain or "head" in chain:
        return [(HEAD, 1.0)]
    if any(b.startswith(("wrist", "metacarpal", "finger")) for b in chain):
        return [(HAND_L + 3 * side, 1.0)]
    if any(b.startswith("lowerarm") for b in chain):
        return [(FORE_L + 3 * side, 1.0)]
    if any(b.startswith("upperarm") for b in chain):
        return [(ARM_L + 3 * side, 1.0)]
    if name.startswith("shoulder01"):
        return [(CHEST, 0.45), (ARM_L + 3 * side, 0.55)]
    if name.startswith(("clavicle", "breast")) or name in ("spine01", "spine02"):
        return [(CHEST, 1.0)]
    if name == "spine03":
        return [(SPINE, 0.55), (CHEST, 0.45)]
    if name == "spine04":
        return [(SPINE, 1.0)]
    if name == "spine05":
        return [(HIPS, 0.6), (SPINE, 0.4)]
    if any(b.startswith(("foot", "toe")) for b in chain):
        return [(FOOT_L + 3 * side, 1.0)]
    if any(b.startswith("lowerleg") for b in chain):
        return [(SHIN_L + 3 * side, 1.0)]
    if any(b.startswith("upperleg") for b in chain):
        return [(THIGH_L + 3 * side, 1.0)]
    return [(HIPS, 1.0)]  # root, pelvis


def rot_between(a, b):
    """Smallest rotation matrix turning unit vector a onto unit vector b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.999999:
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return axis_angle(axis, np.pi)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def axis_angle(axis, ang):
    axis = np.asarray(axis, dtype=np.float64)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


class Figure:
    def __init__(self, name, spec, base, sk):
        self.name = name
        self.spec = spec
        self.base = base
        self.sk = sk
        weighted = mhlib.macro_targets(**spec["macro"])
        for mod, value in spec.get("mods", {}).items():
            weighted += mhlib.modifier_targets(mod, value)
        self.v = mhlib.apply_targets(base.v, weighted)
        self.mh_weights()

    # --- skin weights -----------------------------------------------------------------------
    def mh_weights(self):
        """Game-bone weights for every base vertex (dense N x BONE_COUNT)."""
        n = len(self.base.v)
        W = np.zeros((n, BONE_COUNT))
        for bone, lst in self.sk.weights.items():
            if len(lst) == 0:
                continue
            idx = lst[:, 0].astype(np.int64)
            w = lst[:, 1]
            for gb, share in game_bones(self.sk, bone):
                W[idx, gb] += w * share
        s = W.sum(axis=1, keepdims=True)
        s[s == 0] = 1
        self.W = W / s
        # MakeHuman weights per own bone, for curling the fingers
        self.mhW = {b: lst for b, lst in self.sk.weights.items()}

    # --- joints -----------------------------------------------------------------------------
    def J(self, bone, end="head"):
        return self.sk.head(self.v, bone) if end == "head" else self.sk.tail(self.v, bone)

    # --- a relaxed hand -----------------------------------------------------------------------
    def curl_fingers(self, pts, W_mh_fn, amount):
        """Bends the fingers towards the palm (MakeHuman space). pts: points to move; W_mh_fn(bone)
        gives each point's weight for a MakeHuman bone."""
        out = pts.copy()
        for side in ("L", "R"):
            wrist = self.J("wrist." + side)
            index = self.J("finger2-1." + side)
            pinky = self.J("finger5-1." + side)
            mid = self.J("finger3-1." + side)
            along = mid - wrist
            along /= np.linalg.norm(along)
            palm = np.cross(index - wrist, pinky - wrist)
            palm /= np.linalg.norm(palm)
            # the palm normal should point to the side the fingers close towards: the thumb's side
            # of the hand faces forward in A-pose, the palm faces down/back; flip so it points to
            # where the fingertips go when the fist closes
            thumb = self.J("finger1-2." + side)
            if np.dot(palm, thumb - wrist) < 0:
                palm = -palm
            for f in range(1, 6):
                chain = ["finger%d-%d.%s" % (f, j, side) for j in (1, 2, 3)]
                angles = [amount * a for a in ((0.25, 0.35, 0.3) if f == 1 else (0.55, 0.75, 0.6))]
                # each joint rotates everything distal to it: compose from the root of the finger
                M = [np.eye(4)]
                for j, bone in enumerate(chain):
                    head = self.J(bone)
                    seg = self.J(bone, "tail") - head
                    if f == 1:
                        axis = np.cross(seg, palm)
                    else:
                        axis = np.cross(palm, seg)
                    if np.linalg.norm(axis) < 1e-9:
                        M.append(M[-1])
                        continue
                    R = axis_angle(axis, angles[j] * (1 if f != 1 else 1))
                    T = np.eye(4)
                    T[:3, :3] = R
                    T[:3, 3] = head - R @ head
                    M.append(M[-1] @ T)
                for j, bone in enumerate(chain):
                    w = W_mh_fn(bone)
                    if w is None:
                        continue
                    sel = np.nonzero(w)[0]
                    if len(sel) == 0:
                        continue
                    Mj = M[j + 1]
                    moved = (Mj[:3, :3] @ pts[sel].T).T + Mj[:3, 3]
                    out[sel] += (moved - pts[sel]) * w[sel, None]
        return out

    # --- MakeHuman space to the game's bind pose ---------------------------------------------
    def build_transforms(self):
        J = self.J
        s = self.spec
        ank = 0.5 * (J("foot.L")[1] + J("foot.R")[1])
        hipj = 0.5 * (J("upperleg01.L")[1] + J("upperleg01.R")[1])
        shoulder = 0.5 * (J("upperarm01.L")[1] + J("upperarm01.R")[1])
        neck = J("neck01")[1]
        # horizontal scale: arms and head keep MakeHuman's proportions at this scale
        upper = np.linalg.norm(J("lowerarm01.L") - J("upperarm01.L"))
        fore = np.linalg.norm(J("wrist.L") - J("lowerarm01.L"))
        self.s = (0.295 + 0.265) / (upper + fore)
        sc = self.s
        self.z0 = 0.5 * (J("upperleg01.L")[2] + J("upperleg01.R")[2])
        # vertical map for the trunk: ankle, hip joint and shoulder land on the rig's joints, and
        # from the neck up nothing is stretched
        self.yk = [(ank, Y_ANKLE), (hipj, Y_HIPJ), (shoulder, Y_SHOULDER)]
        y_neck = Y_SHOULDER + (neck - shoulder) * sc
        self.yk.append((neck, y_neck))
        self.y_neck_mh = neck
        self.y_neck_game = y_neck
        self.shoulder_x = sc * 0.5 * (J("upperarm01.L")[0] - J("upperarm01.R")[0])
        report = {"scale": sc, "trunk_stretch": (Y_SHOULDER - Y_HIPJ) / ((shoulder - hipj) * sc), "leg_stretch": (Y_HIPJ - Y_ANKLE) / ((hipj - ank) * sc)}
        self.report = report

    def ymap(self, y):
        ys = [k[0] for k in self.yk]
        gs = [k[1] for k in self.yk]
        out = np.interp(y, ys, gs)
        above = y > self.y_neck_mh
        out[above] = self.y_neck_game + (y[above] - self.y_neck_mh) * self.s
        below = y < ys[0]
        out[below] = gs[0] + (y[below] - ys[0]) * self.s
        return out

    def trunk_map(self, p):
        q = np.empty_like(p)
        q[:, 0] = p[:, 0] * self.s
        q[:, 1] = self.ymap(p[:, 1])
        q[:, 2] = (p[:, 2] - self.z0) * self.s
        return q

    def limb_map(self, p, a_mh, b_mh, a_game, b_game, twist=None):
        """Rotates a limb segment from MakeHuman's pose onto the game's, stretching it along its
        length to fit, keeping its girth."""
        u = b_mh - a_mh
        w = b_game - a_game
        L_mh = np.linalg.norm(u) * self.s
        L_g = np.linalg.norm(w)
        R = rot_between(u, w)
        if twist is not None:
            R = axis_angle(w, twist) @ R
        wn = w / L_g
        local = (p - a_mh) @ R.T * self.s
        along = local @ wn
        local += np.outer(along * (L_g / L_mh - 1.0), wn)
        return local + a_game

    def to_game(self, p, W):
        """p: MakeHuman positions, W: game-bone weights (N x BONE_COUNT)."""
        J = self.J
        out = np.zeros_like(p)
        trunk = self.trunk_map(p)
        sx = self.shoulder_x
        head_mh = J("neck01")
        head_game = self.trunk_map(head_mh[None])[0]
        for gb in range(16):
            w = W[:, gb]
            sel = np.nonzero(w > 1e-6)[0]
            if len(sel) == 0:
                continue
            pp = p[sel]
            if gb in (HIPS, SPINE, CHEST, HEAD):
                q = trunk[sel]
            else:
                side = "L" if gb in (ARM_L, FORE_L, HAND_L, THIGH_L, SHIN_L, FOOT_L) else "R"
                sgn = 1.0 if side == "L" else -1.0
                if gb in (ARM_L, ARM_R):
                    q = self.limb_map(pp, J("upperarm01." + side), J("lowerarm01." + side), np.array([sgn * sx, Y_SHOULDER, 0]), np.array([sgn * sx, Y_ELBOW, 0]), self.arm_twist[side])
                elif gb in (FORE_L, FORE_R):
                    q = self.limb_map(pp, J("lowerarm01." + side), J("wrist." + side), np.array([sgn * sx, Y_ELBOW, 0]), np.array([sgn * sx, Y_WRIST, 0]), self.fore_twist[side])
                elif gb in (HAND_L, HAND_R):
                    q = self.limb_map(pp, J("wrist." + side), J("finger3-1." + side), np.array([sgn * sx, Y_WRIST, 0]), np.array([sgn * sx, Y_WRIST - 0.09, 0]), self.hand_twist[side])
                elif gb in (THIGH_L, THIGH_R):
                    q = self.limb_map(pp, J("upperleg01." + side), J("lowerleg01." + side), np.array([sgn * X_HIP, Y_HIPJ, 0]), np.array([sgn * X_HIP, Y_KNEE, 0]))
                elif gb in (SHIN_L, SHIN_R):
                    q = self.limb_map(pp, J("lowerleg01." + side), J("foot." + side), np.array([sgn * X_HIP, Y_KNEE, 0]), np.array([sgn * X_HIP, Y_ANKLE, 0]))
                else:
                    # the foot: carried rigidly, its sole kept flat
                    a = J("foot." + side)
                    q = (pp - a) * self.s + np.array([sgn * X_HIP, Y_ANKLE, 0])
            out[sel] += q * w[sel, None]
        return out

    def solve_twists(self):
        """Turns the arms about their own length so that, hanging, the palms face the thighs and
        the thumbs point forward (the bind pose operative.gd animates from)."""
        self.arm_twist, self.fore_twist, self.hand_twist = {}, {}, {}
        for side in ("L", "R"):
            sgn = 1.0 if side == "L" else -1.0
            J = self.J
            down = np.array([0.0, -1.0, 0.0])
            wrist = J("wrist." + side)
            hand_dir = J("finger3-1." + side) - wrist
            R = rot_between(hand_dir, down)
            thumb = R @ (J("finger1-2." + side) - wrist)
            thumb[1] = 0
            ang = np.arctan2(thumb[0], thumb[2]) if np.linalg.norm(thumb) > 1e-9 else 0.0
            # want the thumb pointing +Z (forward), a little towards the body
            twist = -ang + sgn * -0.25
            self.hand_twist[side] = twist
            self.fore_twist[side] = twist
            # the upper arm: the elbow's crease faces forward when the forearm hangs straight
            ua = J("lowerarm01." + side) - J("upperarm01." + side)
            fa = J("wrist." + side) - J("lowerarm01." + side)
            R = rot_between(ua, down)
            bend = R @ fa
            bend[1] = 0
            if np.linalg.norm(bend) > 1e-6:
                angb = np.arctan2(bend[0], bend[2])
                self.arm_twist[side] = -angb
            else:
                self.arm_twist[side] = 0.0


# --- mesh assembly --------------------------------------------------------------------------
class Surface:
    def __init__(self, name):
        self.name = name
        self.pos = []
        self.nrm = []
        self.uv = []
        self.col = []
        self.bones = []
        self.weights = []
        self.idx = []


def top4(W):
    order = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, order, axis=1)
    s = w.sum(axis=1, keepdims=True)
    s[s == 0] = 1
    return order.astype(np.int32), (w / s).astype(np.float32)


def vertex_normals(pos, tris):
    n = np.zeros_like(pos)
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    return n / ln


def build_surface(name, pos, faces, fuv, vt, W, keep_face=None, color=None, flip_v=True):
    """Unwelds by (vertex, uv) pair, triangulates, smooth normals over shared positions."""
    tris_pos = []
    key = {}
    out_pos, out_uv, out_src = [], [], []
    tris = []
    for fi, (f, t) in enumerate(zip(faces, fuv)):
        if keep_face is not None and not keep_face[fi]:
            continue
        ids = []
        for vi, ti in zip(f, t):
            k = (vi, ti)
            if k not in key:
                key[k] = len(out_src)
                out_src.append(vi)
                uv = vt[ti] if ti >= 0 else (0.0, 0.0)
                out_uv.append((uv[0], 1.0 - uv[1] if flip_v else uv[1]))
            ids.append(key[k])
        for j in range(1, len(ids) - 1):
            tris.append((ids[0], ids[j], ids[j + 1]))
            tris_pos.append((f[0], f[j], f[j + 1]))
    src = np.array(out_src, dtype=np.int64)
    tris = np.array(tris, dtype=np.int64).reshape(-1, 3)
    tris_pos = np.array(tris_pos, dtype=np.int64).reshape(-1, 3)
    nrm_pos = vertex_normals(pos, tris_pos)
    surf = Surface(name)
    surf.pos = pos[src].astype(np.float32)
    surf.nrm = nrm_pos[src].astype(np.float32)
    surf.uv = np.array(out_uv, dtype=np.float32)
    b, w = top4(W[src])
    surf.bones = b
    surf.weights = w
    surf.src = src
    surf.idx = tris.astype(np.int32)
    if color is not None:
        surf.col = color[src].astype(np.float32) if np.ndim(color) == 2 else np.tile(np.array(color, dtype=np.float32), (len(src), 1))
    else:
        surf.col = np.ones((len(src), 4), dtype=np.float32)
    return surf


def tangents(s):
    """Per-vertex tangents (xyz, sign) for normal mapping."""
    pos, uv, nrm, tri = s.pos.astype(np.float64), s.uv.astype(np.float64), s.nrm.astype(np.float64), s.idx
    t1 = np.zeros_like(pos)
    t2 = np.zeros_like(pos)
    p0, p1, p2 = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    w0, w1, w2 = uv[tri[:, 0]], uv[tri[:, 1]], uv[tri[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = w1 - w0, w2 - w0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r[np.abs(r) < 1e-12] = 1e-12
    r = 1.0 / r
    sdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r[:, None]
    tdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * r[:, None]
    for k in range(3):
        np.add.at(t1, tri[:, k], sdir)
        np.add.at(t2, tri[:, k], tdir)
    t = t1 - nrm * np.sum(nrm * t1, axis=1, keepdims=True)
    ln = np.linalg.norm(t, axis=1, keepdims=True)
    bad = ln[:, 0] < 1e-9
    ln[bad] = 1
    t = t / ln
    t[bad] = [1, 0, 0]
    sign = np.where(np.sum(np.cross(nrm, t) * t2, axis=1) < 0.0, -1.0, 1.0)
    return np.concatenate([t, sign[:, None]], axis=1).astype(np.float32)


def write_fig(path, surfaces, meta):
    """SFG2: the header, then each surface's arrays as one zlib (deflate) block."""
    with open(path, "wb") as f:
        head = json.dumps(meta).encode("utf-8")
        f.write(b"SFG2")
        f.write(struct.pack("<II", len(head), len(surfaces)))
        f.write(head)
        for s in surfaces:
            name = s.name.encode("utf-8")
            n = len(s.pos)
            raw = b"".join([np.ascontiguousarray(s.pos, dtype="<f4").tobytes(), np.ascontiguousarray(s.nrm, dtype="<f4").tobytes(),
                            np.ascontiguousarray(s.tan, dtype="<f4").tobytes(), np.ascontiguousarray(s.uv, dtype="<f4").tobytes(),
                            np.ascontiguousarray(s.col, dtype="<f4").tobytes(), np.ascontiguousarray(s.bones, dtype="<i4").tobytes(),
                            np.ascontiguousarray(s.weights, dtype="<f4").tobytes(), np.ascontiguousarray(s.idx, dtype="<i4").tobytes()])
            packed = zlib.compress(raw, 9)
            f.write(struct.pack("<IIIII", len(name), n, len(s.idx) * 3, len(raw), len(packed)))
            f.write(name)
            f.write(packed)


_skins_done = set()


def bake(name, base, sk):
    spec = dict(FIGURES[name])
    spec["name"] = name
    fig = Figure(name, spec, base, sk)
    fig.build_transforms()
    fig.solve_twists()
    nbase = len(base.v)
    # MakeHuman per-bone weight arrays (dense) for the finger curl
    dense = {}

    def mh_w(bone):
        if bone not in fig.mhW or len(fig.mhW[bone]) == 0:
            return None
        if bone not in dense:
            arr = np.zeros(nbase)
            lst = fig.mhW[bone]
            arr[lst[:, 0].astype(np.int64)] = lst[:, 1]
            dense[bone] = arr
        return dense[bone]

    # proxies fitted in MakeHuman space
    proxies = {}
    for slot in ("suit", "boots", "hair", "brows", "lashes", "eyes"):
        rel = spec.get(slot)
        if rel:
            proxies[slot] = mhlib.Proxy(mhlib.system(rel))
    hidden = set()
    for slot in ("suit", "boots"):
        if slot in proxies:
            hidden.update(proxies[slot].delete)
    surfaces = []
    later_hair = None
    meta = {"name": name, "report": {}}
    curled = fig.curl_fingers(fig.v, mh_w, spec.get("grip", 1.0))
    game_body = fig.to_game(curled, fig.W)
    meta["report"].update(fig.report)
    meta["shoulder_x"] = float(fig.shoulder_x)
    # skin: the body group, less what clothes cover
    keep = [g == "body" and not any(v in hidden for v in f) for f, g in zip(base.faces, base.groups)]
    gloves = None
    if spec.get("gloves"):
        # gloves: the hands and the wrists up under the sleeve, taken out of the skin and made a little fuller
        hand = (fig.W[:, HAND_L] + fig.W[:, HAND_R]) > 0.5
        wrist = ((fig.W[:, FORE_L] + fig.W[:, FORE_R]) > 0.3) & (game_body[:, 1] < Y_WRIST + 0.04)
        if spec.get("gloves_cut"):
            # fingerless: the fingers bare from the first joint (and the thumb's tip)
            tips = np.zeros(len(game_body))
            for side in ("L", "R"):
                for f in range(1, 6):
                    for j in (2, 3):
                        w = mh_w("finger%d-%d.%s" % (f, j, side))
                        if w is not None:
                            tips += w
            hand &= tips < 0.35
        gloved = hand | wrist
        glove_faces = [k and all(gloved[v] for v in f) for k, f in zip(keep, base.faces)]
        keep = [k and not g for k, g in zip(keep, glove_faces)]
        gloves = (glove_faces, wrist)
    skin = build_surface("skin", game_body, base.faces, base.fuv, base.vt, fig.W, keep)
    surfaces.append(skin)
    if gloves is not None:
        surfaces.append(glove_surface(game_body, base, fig.W, gloves, spec["gloves"]))
    for slot, px in proxies.items():
        p_mh = px.fit(fig.v)
        W = (fig.W[px.ref_idx] * px.ref_w[:, :, None]).sum(axis=1)
        keep_faces = None
        if slot == "eyes":
            W = np.zeros_like(W)
            W[:, HEAD] = 1.0
        p_game = fig.to_game(p_mh, W)
        color = None
        if slot == "suit":
            color = suit_regions(px, spec)
        if slot == "hair" and spec.get("hat") and spec["hat"] != "bare":
            # trimmed to what shows under the hat, once the head is measured
            later_hair = (px, p_game, W)
            continue
        if slot == "hair" and spec.get("hat_band"):
            # under a hat only the hair below its band shows; the rest would poke through
            cut = head_top(game_body, fig.W) - spec["hat_band"]
            keep_faces = [all(p_game[i][1] < cut + 0.012 * (1.0 if p_game[i][2] < 0.02 else 0.0) for i in f) for f in px.obj.faces]
        surf = build_surface(slot, p_game, px.obj.faces, px.obj.fuv, px.obj.vt, W, keep_faces, color)
        surfaces.append(surf)
    lm = {}
    for key, bone, end in (("nose_tip", "levator06.L", "head"), ("nose_base", "oris06", "head"), ("upper_lip", "oris05", "head"),
                           ("mouth", "oris01", "tail"), ("lower_lip", "oris01", "head"), ("corner", "oris03.L", "tail"), ("chin", "special04", "head")):
        q = fig.trunk_map(fig.J(bone, end)[None])[0]
        lm[key] = [round(float(x), 4) for x in q]
    meta["landmarks"] = lm
    measure(meta, surfaces)
    byname = {s.name: s for s in surfaces}
    if spec.get("tache"):
        surfaces.append(mhgear.moustache(meta, byname["skin"], spec, spec["tache"]))
    head_pts = skin.pos[skin.weights[:, 0] * (skin.bones[:, 0] == HEAD) > 0.5]
    if later_hair is not None:
        px, p_game, W = later_hair
        p_game = mhgear.tuck_hair(p_game, head_pts, meta, spec["hat"])
        surfaces.append(build_surface("hair", p_game, px.obj.faces, px.obj.fuv, px.obj.vt, W))
        hull = mhgear.Hull(np.concatenate([head_pts, p_game]))
        kind = spec["hat"]
        if kind == "beret":
            surfaces.append(mhgear.beret(hull, meta, spec["hat_color"], badge=spec.get("hat_badge", True)))
        elif kind == "helmet":
            surfaces.append(mhgear.helmet(hull, meta, spec["hat_color"], spec.get("hat_tilt", 0.0), spec.get("hat_roll", 0.0)))
        elif kind == "service":
            surfaces.append(mhgear.service_cap(hull, meta, spec["hat_color"], spec.get("cap_band", "2c322e"), spec.get("cap_visor", "141312"),
                                               spec.get("cap_piping", "b9bab3")))
        elif kind == "flat":
            surfaces.append(mhgear.flat_cap(hull, meta, spec["hat_color"], badge=spec.get("cap_badge", False), big=spec.get("cap_big", False)))
        elif kind == "sailor":
            surfaces.append(mhgear.sailor_cap(hull, meta, spec["hat_color"]))
        elif kind == "hood":
            surfaces.append(mhgear.hood(hull, meta, spec["hat_color"], spec.get("hood_rim", "c9cdd2")))
        elif kind in ("beanie", "earflap"):
            surfaces.append(mhgear.knit_cap(hull, meta, spec["hat_color"], flaps=kind == "earflap"))
        elif kind == "fedora":
            surfaces.append(mhgear.fedora(hull, meta, spec["hat_color"], spec.get("hat_ribbon", "221f1c")))
        elif kind == "headscarf":
            surfaces.append(mhgear.headscarf(hull, meta, spec["hat_color"], neck_points(game_body, base)))
        elif kind == "peaked":
            surfaces.append(mhgear.service_cap(hull, meta, spec["hat_color"], spec.get("cap_band", spec["hat_color"]), spec.get("cap_visor", "121211"),
                                               soft=True, disc=spec.get("cap_disc")))
        else:
            surfaces.append(mhgear.field_cap(hull, meta, spec["hat_color"]))
    if spec.get("scarf"):
        suit = byname["suit"]
        body_ids = np.unique(np.concatenate([np.array(f) for f, g in zip(base.faces, base.groups) if g == "body"]))
        gp = game_body
        region = (gp[:, 1] > 1.40) & (gp[:, 1] < 1.62) & (np.abs(gp[:, 0]) < 0.10)
        neck = mhgear.dense_points(gp, [f for f, g in zip(base.faces, base.groups) if g == "body"], region)
        collar = suit.pos[suit.pos[:, 1] > 1.40]
        chest = suit.pos[(suit.pos[:, 1] > 1.25) & (suit.pos[:, 2] > 0.0)]
        hull = mhgear.Hull(np.concatenate([neck, collar]))
        front = suit.pos[(suit.pos[:, 2] > 0.0) & (suit.pos[:, 1] > 0.9) & (np.abs(suit.pos[:, 0]) < 0.16)] if spec.get("scarf_long") else None
        surfaces.append(mhgear.scarf(hull, meta, spec["scarf"], neck, high=spec.get("scarf_high", False),
                                     back_pts=suit.pos[suit.pos[:, 2] < 0.0] if spec.get("scarf_end") else None,
                                     roll=spec.get("scarf_roll", False), front_pts=front, stripe=spec.get("scarf_stripe")))
    if spec.get("anklets") or spec.get("jackboots") or spec.get("socks"):
        # the whole body, including the skin the clothes hide, to find the legs by
        body_ids = np.unique(np.concatenate([np.array(f) for f, g in zip(base.faces, base.groups) if g == "body"]))
        whole = types.SimpleNamespace(pos=game_body[body_ids].astype(np.float32), bones=np.argmax(fig.W[body_ids], axis=1)[:, None])
        if spec.get("jackboots"):
            g, top = mhgear.anklets(whole, byname["boots"], spec["jackboots"], height=spec.get("boot_height", 0.26), straps=False,
                                    name="jackboots", flare=0.012, straight=spec.get("boot_straight", False))
            mhgear.tuck_trousers(byname["suit"], whole, top - 0.012, blouse=0.004)
        elif spec.get("socks"):
            # trousers tucked into wool socks pulled up over them
            g, top = mhgear.anklets(whole, byname["boots"], spec["socks"], height=spec.get("socks_height", 0.115), straps=False,
                                    name="socks", flare=0.002)
            mhgear.tuck_trousers(byname["suit"], whole, top - 0.006, blouse=0.012)
        else:
            g, top = mhgear.anklets(whole, byname["boots"], spec["anklets"])
            mhgear.tuck_trousers(byname["suit"], whole, top - 0.004)
        surfaces.append(g)
    if spec.get("collar"):
        tunic_marks(byname["suit"], meta)
    if spec.get("coat") or spec.get("tunic_skirt"):
        # a greatcoat's or a tunic's skirt is more of the suit's cloth: same material, its weave
        # mirrored out of a small plain patch of the suit's texture (spec skirt_patch; the folds are its own)
        if spec.get("coat"):
            fit = byname["suit"].pos
            window = 0.0
            if spec.get("coat_fit") == "trunk":
                # cut to the body alone: the arms hanging beside the hips are not part of the coat's girth
                s = byname["suit"]
                arms = (s.weights * ((s.bones >= ARM_L) & (s.bones <= HAND_R))).sum(axis=1)
                fit = s.pos[arms < 0.3]
                window = spec.get("coat_window", 0.035)
            skirt = mhgear.coat_skirt(fit, spec["coat"], hem=spec.get("coat_hem", 0.42), belt=spec.get("coat_belt"), window=window,
                                      narrow=spec.get("coat_ell", 1.0), fine=spec.get("coat_fine", False), room=spec.get("coat_room", 0.0))
        else:
            skirt = mhgear.coat_skirt(byname["suit"].pos, spec["tunic_skirt"], top_y=1.075, hem=spec.get("skirt_hem", 0.855))
        u = skirt.uv[:, 0] / 0.12
        v = skirt.uv[:, 1] / 0.12
        tri = lambda x: 1.0 - np.abs((x % 2.0) - 1.0)
        pu, pv = spec.get("skirt_patch", (0.203, 0.875))
        skirt.uv = np.stack([pu + 0.06 * tri(u), pv + 0.06 * tri(v)], 1).astype(np.float32)
        skirt.col[:, 3] = 0.0
        if spec.get("coat_fine"):
            # under a long coat only the stockings below its hem show: the legs above it are drawn in a little, so
            # that no knee comes through the cloth
            su = byname["suit"]
            legs = (np.abs(su.col[:, 3] - 2.0) < 0.01) & (su.pos[:, 1] > spec.get("coat_hem", 0.42) + 0.03) & (su.pos[:, 1] < 0.98)
            cx = np.sign(su.pos[legs, 0]) * X_HIP
            k = 0.86
            su.pos[legs, 0] = cx + (su.pos[legs, 0] - cx) * k
            su.pos[legs, 2] = su.pos[legs, 2] * k
        if spec.get("coat_belt"):
            # where the coat's belt stands at the front (the procedural kit hangs things from it)
            fr = skirt.pos[(np.abs(skirt.pos[:, 0]) < 0.03) & (skirt.pos[:, 1] > 1.03) & (skirt.pos[:, 1] < 1.08)]
            if len(fr):
                meta["coat_belt"] = [round(float(fr[:, 1].mean()), 4), round(float(fr[:, 2].max()), 4)]
        merge_into(byname["suit"], skirt)
    if spec.get("cape"):
        # over the greatcoat, the arms hanging inside it
        rows = [r for r in meta["torso"] if abs(r[0] - 1.40) < 0.011]
        surfaces.append(mhgear.cape(byname["suit"].pos, spec["cape"], hem=spec.get("cape_hem", 1.02), zc=rows[0][3] if rows else 0.02))

    for s in surfaces:
        s.tan = tangents(s)
    meta["surfaces"] = [{"name": s.name, "verts": len(s.pos), "tris": len(s.idx)} for s in surfaces]
    slots = ["skin", "tache", "hat", "scarf", "gaiters", "jackboots", "coat"] + (["gloves"] if spec.get("gloves") else [])
    slots += [s for s in ("cape", "socks") if spec.get(s)]
    meta["textures"] = {slot: texture_name(slot, spec) for slot in slots + list(proxies)}
    meta["skin_mul"] = spec.get("skin_mul", [1.0, 1.0, 1.0])
    if spec.get("suit_gloss"):
        meta["suit_gloss"] = spec["suit_gloss"]
    if spec.get("tints"):
        # what each recolourable part was baked in, for figure.gd's colour variants (the ratio is applied)
        meta["tints"] = dict(spec["colors"], **{k: spec[k] for k in ("hat_color", "scarf", "cape") if spec.get(k)})
    os.makedirs(OUT, exist_ok=True)
    write_fig(os.path.join(OUT, name + ".fig"), surfaces, meta)
    export_textures(spec)
    skin_png_out = os.path.join(TEX, texture_name("skin", spec) + ".png")
    if spec.get("skin_reuse") and os.path.exists(skin_png_out):
        # a shared skin painted for an earlier figure (the garrison's three): left exactly as it is
        _skins_done.add(texture_name("skin", spec))
    if "weather" in spec and texture_name("skin", spec) not in _skins_done:
        _skins_done.add(texture_name("skin", spec))
        byname = {s.name: s for s in surfaces}
        cav = mhgear.cavity(game_body, [f for f, g in zip(base.faces, base.groups) if g == "body"])
        skin_png = _mat_tex(mhlib.system(spec["skin"]))["diffuseTexture"]
        os.makedirs(TEX, exist_ok=True)
        dbg = mhgear.weather_skin(skin_png, os.path.join(TEX, texture_name("skin", spec) + ".png"), spec.get("skin_size", 2048),
                                  skin, cav[skin.src], meta, spec, byname.get("eyes"))
        if os.environ.get("MH_DEBUG"):
            front_view(dbg, os.path.join(TEX, texture_name("skin", spec) + ".png"), meta, os.environ["MH_DEBUG"] + "/" + name + "_face.png")
    print(name, json.dumps(meta["report"]), [(s.name, len(s.pos)) for s in surfaces])
    return meta


def merge_into(a, b):
    """Appends surface b's vertices and triangles to surface a."""
    off = len(a.pos)
    for f in ("pos", "nrm", "uv", "col", "bones", "weights"):
        setattr(a, f, np.concatenate([getattr(a, f), getattr(b, f).astype(getattr(a, f).dtype)]))
    a.idx = np.concatenate([a.idx, (b.idx + off).astype(a.idx.dtype)])


def neck_points(game_body, base):
    """Points spread over the skin of the neck and the top of the shoulders (what a scarf or a headscarf wraps)."""
    gp = game_body
    region = (gp[:, 1] > 1.40) & (gp[:, 1] < 1.62) & (np.abs(gp[:, 0]) < 0.10)
    return mhgear.dense_points(gp, [f for f, g in zip(base.faces, base.groups) if g == "body"], region)


def glove_surface(game_body, base, W, gloves, color):
    """Leather gloves: the hand's own skin faces pushed out a little along their normals (more at the cuff, which
    stands off the wrist up under the sleeve), in one dark colour, the leather tiled over them (UVs in metres)."""
    glove_faces, wrist = gloves
    tris = []
    for f, g in zip(base.faces, base.groups):
        if g == "body":
            for j in range(1, len(f) - 1):
                tris.append((f[0], f[j], f[j + 1]))
    nrm = vertex_normals(game_body, np.array(tris, dtype=np.int64))
    push = np.where(wrist, 0.0034, 0.0016)
    pos = game_body + nrm * push[:, None]
    col = np.tile(np.array(hex_rgb(color) + [1.0]), (len(pos), 1))
    # the cuff a shade darker than the hand
    col[wrist, :3] *= 0.86
    surf = build_surface("gloves", pos, base.faces, base.fuv, base.vt, W, glove_faces, col)
    p = surf.pos.astype(np.float64)
    surf.uv = np.stack([p[:, 0] + p[:, 2], p[:, 1]], 1).astype(np.float32)
    return surf


def tunic_marks(suit, meta):
    """Where the insignia go: the fronts of the collar (its own region of the suit) and the line
    along the tops of the shoulders, for operative.gd."""
    p = suit.pos
    collar = np.abs(suit.col[:, 3] - 1.0) < 0.01
    tabs = []
    for sgn in (1.0, -1.0):
        q = p[collar & (p[:, 0] * sgn > 0.015)]
        if len(q):
            zf = q[:, 2].max()
            front = q[q[:, 2] > zf - 0.015]
            c = front.mean(axis=0)
            tabs.append([round(float(x), 4) for x in c])
    if len(tabs) == 2:
        meta["collar"] = {"tabs": tabs}
    neck = meta.get("neck", {})
    zc = 0.02
    line = []
    for x in np.arange(0.07, 0.235, 0.025):
        q = p[(np.abs(p[:, 0] - x) < 0.012) & (np.abs(p[:, 2] - zc) < 0.035) & ~collar & (p[:, 1] > 1.3)]
        if len(q):
            line.append([round(float(x), 3), round(float(q[:, 1].max()), 4), round(float(q[q[:, 1] > q[:, 1].max() - 0.01][:, 2].mean()), 4)])
    meta["shoulder_line"] = line


def moustache(meta, skin, spec):
    """A moustache of real hairs: two curved cards along the upper lip carrying the eyebrow texture
    (whose brow shapes, thick at one end and tapering, make the two halves of a moustache)."""
    lm = meta["landmarks"]
    head = skin.pos[(skin.bones[:, 0] == HEAD) & (skin.weights[:, 0] > 0.9) & (skin.pos[:, 2] > 0.05)]

    def face_z(x, y):
        d = (head[:, 0] - x) ** 2 + (head[:, 1] - y) ** 2
        near = np.argsort(d)[:6]
        return float(head[near, 2].max())

    top, bottom, half = lm["nose_base"][1], lm["mouth"][1], lm["corner"][0]
    kind = spec["tache"]
    h = (top - bottom) * (1.25 if kind == "walrus" else 0.75)
    reach = 1.28 if kind == "walrus" else 1.0
    droop = 0.55 if kind == "walrus" else 0.15
    line = brow_line(spec)
    nu, nv = 11, 4
    pos, uv, nrm, tris = [], [], [], []
    for layer in range(2):
        for side in (1.0, -1.0):
            first = len(pos)
            for i in range(nu):
                u = i / (nu - 1)
                x = side * (0.001 + u * half * reach * (1.0 - 0.08 * layer))
                y_mid = top - h * 0.45 - (u ** 2) * h * droop
                tu, cy, ht = line(u)
                for j in range(nv):
                    v = j / (nv - 1)
                    y = y_mid + h * 0.5 - v * h
                    z = face_z(x, y) + 0.0020 + 0.0016 * layer + 0.0016 * (1.0 - u) * (1.0 - abs(v - 0.5) * 2)
                    pos.append([x, y, z])
                    uv.append([tu, cy + (v - 0.5) * 2.0 * ht * (1.05 + 0.15 * layer)])
                    n = np.array([x * 6.0, 0.25, 1.0])
                    nrm.append(n / np.linalg.norm(n))
            for i in range(nu - 1):
                for j in range(nv - 1):
                    a = first + i * nv + j
                    b, c, d = a + nv, a + nv + 1, a + 1
                    if side > 0:
                        tris += [(a, d, c), (a, c, b)]
                    else:
                        tris += [(a, b, c), (a, c, d)]
    s = Surface("tache")
    s.pos = np.array(pos, dtype=np.float32)
    s.nrm = np.array(nrm, dtype=np.float32)
    s.uv = np.array(uv, dtype=np.float32)
    s.col = np.ones((len(pos), 4), dtype=np.float32)
    s.bones = np.tile(np.array([HEAD, 0, 0, 0], dtype=np.int32), (len(pos), 1))
    s.weights = np.tile(np.array([1, 0, 0, 0], dtype=np.float32), (len(pos), 1))
    s.idx = np.array(tris, dtype=np.int32)
    return s


def head_top(pos, W):
    head = pos[W[:, HEAD] > 0.9]
    return float(head[:, 1].max())


def brow_line(spec):
    """The upper brow in an eyebrow texture as a function of u (0 = thick end, 1 = tip):
    (texture u, centre v, half thickness), so a card can carry it straightened."""
    d = os.path.dirname(mhlib.system(spec["brows"]))
    png = [f for f in os.listdir(d) if f.endswith(".png") and "thumb" not in f][0]
    a = np.asarray(Image.open(os.path.join(d, png)).convert("RGBA"), dtype=np.float64)[..., 3] / 255.0
    h, w = a.shape
    top = a[: h // 2 + h // 10]
    cols = np.nonzero(top.sum(axis=0) > 2.0)[0]
    x0, x1 = cols.min(), cols.max()
    ys = np.arange(top.shape[0])[:, None]

    def at(u):
        x = int(round(x0 + (x1 - x0) * (0.02 + 0.96 * u)))
        col = top[:, max(x - 3, 0):x + 4].mean(axis=1)
        m = col.sum()
        if m < 1e-6:
            return x / w, 0.4, 0.01
        cy = float((col * ys[:, 0]).sum() / m)
        spread = float(np.sqrt((col * (ys[:, 0] - cy) ** 2).sum() / m))
        return x / w, cy / h, max(spread * 1.9, 3.0) / h
    return at


def texture_name(slot, spec):
    hats = {"beret": "weave_felt", "cap": "weave_twill", "helmet": "weave_steel", "service": "weave_twill", "flat": "weave_twill", "sailor": "weave_felt", "hood": "weave_twill",
            "beanie": "weave_knit", "earflap": "weave_knit", "fedora": "weave_felt", "headscarf": "weave_twill", "peaked": "weave_twill"}
    return {"skin": "skin_" + (spec.get("skin_share", spec["name"]) if "weather" in spec else spec["skin_tex"]),
            "hat": hats.get(spec.get("hat"), "weave_twill"), "jackboots": "weave_leather", "gloves": spec.get("gloves_tex", "weave_leather"), "coat": "weave_felt",
            "cape": "weave_twill", "socks": "weave_knit", "suit": "suit_" + os.path.basename(os.path.dirname(spec["suit"])),
            "boots": "boots_" + os.path.basename(os.path.dirname(spec["boots"])), "hair": "hair_" + os.path.basename(os.path.dirname(spec["hair"])),
            "brows": "brows_" + os.path.basename(os.path.dirname(spec["brows"])), "tache": "tache_strands", "scarf": "weave_knit", "gaiters": "weave_twill", "lashes": "lashes", "eyes": "eye_" + spec["eye_color"]}.get(slot, slot)


_suit_tex = {}


def suit_regions(px, spec):
    """Per-vertex colour for a suit: which part of the outfit each vertex belongs to, read from
    the suit's own diffuse texture, recoloured to this figure's uniform."""
    tex = px.material_textures().get("diffuseTexture")
    key = tex
    if key not in _suit_tex:
        _suit_tex[key] = np.asarray(Image.open(tex).convert("RGB"), dtype=np.float64) / 255.0
    img = _suit_tex[key]
    h, w = img.shape[:2]
    obj = px.obj
    if "casualsuit01" in tex:
        colors = spec["colors"]
        pal = [hex_rgb(colors["jacket"]), hex_rgb(colors["shirt"]), hex_rgb(colors["trousers"])]
        region = np.zeros(len(obj.v), dtype=np.int64)
        for f, t in zip(obj.faces, obj.fuv):
            for vi, ti in zip(f, t):
                if ti < 0:
                    continue
                u, v = obj.vt[ti]
                if 0.35 <= u < 0.72:
                    region[vi] = 2      # trousers
                elif 0.72 <= u < 0.80 and 0.52 <= 1.0 - v < 0.72:
                    region[vi] = 1      # the collar (the "shirt" colour: a tunic's dark collar)
        return np.array([pal[r] + [float(r)] for r in region])
    region = np.zeros(len(obj.v), dtype=np.int64)
    votes = np.zeros((len(obj.v), 3))
    for f, t in zip(obj.faces, obj.fuv):
        for vi, ti in zip(f, t):
            if ti < 0:
                continue
            u, v = obj.vt[ti]
            x = min(max(int(u * (w - 1)), 0), w - 1)
            y = min(max(int((1.0 - v) * (h - 1)), 0), h - 1)
            r, g, b = img[y, x]
            if b > r + 0.08 and b > g + 0.02:
                votes[vi, 2] += 1  # denim: trousers
            elif r > g + 0.08:
                votes[vi, 1] += 1  # striped shirt
            else:
                votes[vi, 0] += 1  # the jacket
    region = votes.argmax(axis=1)
    colors = spec["colors"]
    pal = [hex_rgb(colors["jacket"]), hex_rgb(colors["shirt"]), hex_rgb(colors["trousers"])]
    out = np.array([pal[r] + [float(r)] for r in region])
    return out


def hex_rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def measure(meta, surfaces):
    """Sizes the procedural kit needs: the torso's cross-sections (from the jacket), the head."""
    byname = {s.name: s for s in surfaces}
    rows = []
    suit = byname.get("suit")
    if suit is not None:
        pos = suit.pos
        trunk = (suit.weights * np.isin(suit.bones, [HIPS, SPINE, CHEST])).sum(axis=1) > 0.6
        for y in np.arange(0.80, 1.52, 0.02):
            sel = trunk & (np.abs(pos[:, 1] - y) < 0.012)
            if sel.sum() < 6:
                continue
            p = pos[sel]
            rx = float(np.abs(p[:, 0]).max())
            front, back = float(p[:, 2].max()), float(p[:, 2].min())
            rows.append([round(float(y), 3), rx, (front - back) * 0.5, (front + back) * 0.5])
    meta["torso"] = rows
    skin = byname["skin"]
    head = skin.pos[(skin.bones[:, 0] == HEAD) & (skin.weights[:, 0] > 0.9)]
    if len(head):
        band = head[np.abs(head[:, 1] - (head[:, 1].max() - 0.075)) < 0.01]
        meta["head"] = {"top": float(head[:, 1].max()), "chin": float(head[:, 1].min()), "half_width": float(np.abs(band[:, 0]).max()),
                        "front": float(band[:, 2].max()), "back": float(band[:, 2].min())}
        if "brows" in byname:
            meta["head"]["brow"] = float(byname["brows"].pos[:, 1].mean())
        # the front of the face as a depth grid (x across, y up), for whatever is drawn on it
        xs = np.arange(-0.05, 0.0501, 0.005)
        ys = np.arange(1.50, 1.7801, 0.005)
        front = head[head[:, 2] > 0.0]
        grid = []
        for y in ys:
            row = []
            for x in xs:
                d = (front[:, 0] - x) ** 2 + (front[:, 1] - y) ** 2
                near = d < 0.006 ** 2
                if near.sum() == 0:
                    near = d <= np.partition(d, 3)[3]
                row.append(round(float(front[near, 2].max()), 4))
            grid.append(row)
        meta["face"] = {"x0": -0.05, "y0": 1.50, "step": 0.005, "nx": len(xs), "ny": len(ys), "z": grid}
    neck = skin.pos[np.isin(skin.bones[:, 0], [CHEST, HEAD]) & (np.abs(skin.pos[:, 1] - 1.50) < 0.01)]
    if len(neck):
        meta["neck"] = {"rx": float(np.abs(neck[:, 0]).max()), "front": float(neck[:, 2].max()), "back": float(neck[:, 2].min())}


def main():
    base = mhlib.Obj(mhlib.fetch("3dobjs/base.obj"))
    sk = mhlib.Skeleton()
    names = sys.argv[1:] or list(FIGURES)
    for name in names:
        bake(name, base, sk)



# --- textures --------------------------------------------------------------------------------
TEX = os.path.join(OUT, "tex")


def _save(img, name, size):
    os.makedirs(TEX, exist_ok=True)
    path = os.path.join(TEX, name + ".png")
    if img.size[0] != size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path, optimize=True)
    return path


def _mat_tex(mhmat):
    out = {}
    for line in open(mhmat, encoding="utf-8", errors="ignore"):
        w = line.split()
        if len(w) >= 2 and w[0] in ("diffuseTexture", "normalmapTexture", "aomapTexture"):
            out[w[0]] = os.path.join(os.path.dirname(mhmat), w[1])
    return out


def front_view(dbg, tex_png, meta, out):
    """A quick orthographic look at the painted face (no renderer needed)."""
    img = np.asarray(Image.open(tex_png).convert("RGB"))
    P, cov = dbg["P"], dbg["cov"]
    ys, xs = np.nonzero(cov)
    p = P[ys, xs, 0:3]
    zc = 0.5 * (meta["head"]["front"] + meta["head"]["back"])
    keep = (p[:, 1] > meta["head"]["chin"] - 0.06) & (p[:, 2] > zc - 0.02)
    p, ys, xs = p[keep], ys[keep], xs[keep]
    res = 0.0007
    x0, y1 = -0.10, meta["head"]["top"] + 0.01
    W, H = int(0.20 / res), int((y1 - (meta["head"]["chin"] - 0.07)) / res)
    cx = ((p[:, 0] + 0.10) / res).astype(int)
    cy = ((y1 - p[:, 1]) / res).astype(int)
    ok = (cx >= 0) & (cx < W) & (cy >= 0) & (cy < H)
    order = np.argsort(p[ok, 2])
    out_img = np.zeros((H, W, 3), dtype=np.uint8)
    out_img[cy[ok][order], cx[ok][order]] = img[ys[ok][order], xs[ok][order]]
    Image.fromarray(out_img).save(out)


def export_textures(spec):
    """The shared textures this figure uses (written once, overwritten harmlessly)."""
    if "weather" not in spec:
        skin = _mat_tex(mhlib.system(spec["skin"]))["diffuseTexture"]
        _save(Image.open(skin).convert("RGB"), "skin_" + spec["skin_tex"], 1024)
    suit_dir = os.path.dirname(mhlib.system(spec["suit"]))
    sname = os.path.basename(suit_dir)
    st = _mat_tex(os.path.join(suit_dir, sname + ".mhmat"))
    if not os.path.exists(os.path.join(TEX, "suit_" + sname + "_detail.png")):
        img = np.asarray(Image.open(st["diffuseTexture"]).convert("RGB"), dtype=np.float64) / 255.0
        r, g, b = img[..., 0], img[..., 1], img[..., 2]
        lum = 0.3 * r + 0.59 * g + 0.11 * b
        denim = (b > r + 0.08) & (b > g + 0.02)
        shirt = (r > g + 0.08) & ~denim
        if sname == "male_casualsuit01":
            # all one blue: the trousers are the islands in the middle of the sheet
            u = np.arange(img.shape[1])[None, :] / img.shape[1]
            denim = np.broadcast_to((u >= 0.35) & (u < 0.72), lum.shape)
            shirt = np.zeros_like(denim)
        from PIL import ImageFilter
        m = Image.fromarray((shirt * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.MinFilter(9))
        shirt = (np.asarray(m) > 127) & ~denim
        detail = np.ones_like(lum)
        used = lum > 0.04
        for mask, contrast in ((~denim & ~shirt, 1.0 if sname != "male_casualsuit01" else 0.7), (denim, 0.45 if sname != "male_casualsuit01" else 0.22), (shirt, 0.08)):
            if (mask & used).sum() == 0:
                continue
            med = np.median(lum[mask & used])
            detail[mask] = 1.0 + (lum[mask] / max(med, 1e-3) - 1.0) * contrast
        if "aomapTexture" in st:
            ao = np.asarray(Image.open(st["aomapTexture"]).convert("L").resize((img.shape[1], img.shape[0])), dtype=np.float64) / 255.0
            detail *= 0.35 + 0.65 * ao
        out = np.clip(detail * 0.5, 0.0, 1.0)
        _save(Image.fromarray((out * 255).astype(np.uint8), "L"), "suit_" + sname + "_detail", 1024)
        nm = np.asarray(Image.open(st["normalmapTexture"]).convert("RGB").resize((img.shape[1], img.shape[0])), dtype=np.float64)
        flat = np.array([128.0, 128.0, 255.0])
        if shirt.any():
            nm[shirt] = nm[shirt] * 0.25 + flat * 0.75
        _save(Image.fromarray(nm.astype(np.uint8), "RGB"), "suit_" + sname + "_normal", 1024)
    for slot, size in (("boots", 512), ("hair", 512), ("brows", 256), ("lashes", 256)):
        if not spec.get(slot):
            continue
        mhclo = mhlib.system(spec[slot])
        d = os.path.dirname(mhclo)
        mats = [f for f in os.listdir(d) if f.endswith(".mhmat")]
        tex = _mat_tex(os.path.join(d, mats[0]))
        img = Image.open(tex["diffuseTexture"])
        img = img.convert("RGBA" if slot != "boots" else "RGB")
        _save(img, texture_name(slot, spec), size)
        if slot == "hair" and "normalmapTexture" in tex:
            _save(Image.open(tex["normalmapTexture"]).convert("RGB"), texture_name(slot, spec) + "_normal", size)
    for kind in ("felt", "twill", "knit", "steel", "leather"):
        d, nm = mhgear.weave_textures(kind)
        _save(d, "weave_" + kind, 256)
        _save(nm, "weave_" + kind + "_normal", 256)
    _save(mhgear.strand_texture(), "tache_strands", 256)
    eye = os.path.join(mhlib.system("eyes/materials"), spec["eye_color"] + "_eye.png")
    _save(Image.open(eye).convert("RGBA"), "eye_" + spec["eye_color"], 256)


if __name__ == "__main__":
    main()
