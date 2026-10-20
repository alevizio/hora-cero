"""MakeHuman (CC0) asset reading for the figure baker of Hora Cero (dev tool, not shipped).

Reads the base mesh, morph targets, skeleton, skin weights and proxy/clothes fitting files of
MakeHuman 1.x. Coordinates are MakeHuman's: decimetres, +Y up, the figure facing +Z, its left +X.
"""
import json
import os
import urllib.request
import zipfile

import numpy as np

CORE = "https://raw.githubusercontent.com/makehumancommunity/makehuman/master/makehuman/data/"
SYSTEM_ZIP = "http://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip"
CACHE = os.environ.get("MH_CACHE", os.path.expanduser("~/.cache/horacero-mh"))


def fetch(rel):
    """A file from the MakeHuman core data (targets, base mesh, rig), cached."""
    path = os.path.join(CACHE, "core", rel)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(CORE + rel, timeout=120) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    return path


def system(rel):
    """A file from the CC0 system asset pack (skins, clothes, hair, eyes), cached and unpacked."""
    root = os.path.join(CACHE, "system")
    if not os.path.exists(os.path.join(root, "skins")):
        os.makedirs(root, exist_ok=True)
        zpath = os.path.join(CACHE, "system.zip")
        if not os.path.exists(zpath):
            urllib.request.urlretrieve(SYSTEM_ZIP, zpath)
        with zipfile.ZipFile(zpath) as z:
            z.extractall(root)
    return os.path.join(root, rel)


class Obj:
    """Wavefront OBJ as MakeHuman writes it: positions, UVs and polygon faces with groups."""

    def __init__(self, path):
        v, vt, faces, fuv, groups = [], [], [], [], []
        group = ""
        for line in open(path, encoding="utf-8", errors="ignore"):
            if line.startswith("v "):
                v.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("vt "):
                vt.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("g "):
                group = line.split(None, 1)[1].strip()
            elif line.startswith("f "):
                fi, ti = [], []
                for tok in line.split()[1:]:
                    parts = tok.split("/")
                    fi.append(int(parts[0]) - 1)
                    ti.append(int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1)
                faces.append(fi)
                fuv.append(ti)
                groups.append(group)
        self.v = np.array(v, dtype=np.float64)
        self.vt = np.array(vt, dtype=np.float64) if vt else np.zeros((0, 2))
        self.faces = faces
        self.fuv = fuv
        self.groups = groups


_targets = {}


def target(rel):
    """Sparse morph target: (indices, offsets)."""
    if rel not in _targets:
        idx, off = [], []
        for line in open(fetch("targets/" + rel)):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            idx.append(int(p[0]))
            off.append([float(p[1]), float(p[2]), float(p[3])])
        _targets[rel] = (np.array(idx, dtype=np.int64), np.array(off, dtype=np.float64).reshape(-1, 3))
    return _targets[rel]


def _split(value):
    """A 0..1 slider with 0.5 neutral: weights of the (min, average, max) targets."""
    if value >= 0.5:
        hi = (value - 0.5) * 2.0
        return {"min": 0.0, "average": 1.0 - hi, "max": hi}
    lo = (0.5 - value) * 2.0
    return {"min": lo, "average": 1.0 - lo, "max": 0.0}


def macro_targets(age_years=25.0, muscle=0.5, weight=0.5, height=0.5, proportions=0.5, gender=1.0, caucasian=1.0):
    """The weighted macro targets MakeHuman would apply for these sliders (adults only)."""
    out = []
    a = min(max((age_years - 25.0) / 65.0, 0.0), 1.0)
    ages = {"young": 1.0 - a, "old": a}
    genders = {"male": gender, "female": 1.0 - gender}
    muscles = {k + "muscle": w for k, w in _split(muscle).items()}
    weights = {k + "weight": w for k, w in _split(weight).items()}
    for g, gw in genders.items():
        for ag, aw in ages.items():
            if gw * aw <= 0.0:
                continue
            if caucasian > 0.0:
                out.append(("macrodetails/caucasian-%s-%s.target" % (g, ag), gw * aw * caucasian))
            for m, mw in muscles.items():
                for wt, ww in weights.items():
                    w = gw * aw * mw * ww
                    if w <= 0.0:
                        continue
                    out.append(("macrodetails/universal-%s-%s-%s-%s.target" % (g, ag, m, wt), w))
                    if height != 0.5:
                        side = "maxheight" if height > 0.5 else "minheight"
                        out.append(("macrodetails/height/%s-%s-%s-%s-%s.target" % (g, ag, m, wt, side), w * abs(height - 0.5) * 2.0))
                    if proportions != 0.5:
                        side = "idealproportions" if proportions > 0.5 else "uncommonproportions"
                        out.append(("macrodetails/proportions/%s-%s-%s-%s-%s.target" % (g, ag, m, wt, side), w * abs(proportions - 0.5) * 2.0))
    return out


_modifiers = None


def modifier_targets(name, value):
    """A modelling modifier ('group/target-name' as in modeling_modifiers.json) at -1..1."""
    global _modifiers
    if _modifiers is None:
        _modifiers = {}
        for grp in json.load(open(fetch("modifiers/modeling_modifiers.json"))):
            for mod in grp["modifiers"]:
                if "target" in mod:
                    key = grp["group"] + "/" + mod["target"]
                    if "min" in mod:
                        key += "|" + mod["min"] + "|" + mod["max"]
                    _modifiers.setdefault(grp["group"] + "/" + mod["target"], []).append(mod)
    group, tname = name.split("/", 1)
    want = None
    if "|" in tname:
        tname, want = tname.split("|")[0], tname.split("|")[1]
    mods = _modifiers[group + "/" + tname]
    mod = mods[0]
    if want is not None:
        mod = [m for m in mods if m.get("min") == want or m.get("max") == want][0]
    if "min" not in mod:
        return [("%s/%s.target" % (group, tname), max(value, 0.0))]
    side = mod["max"] if value > 0 else mod["min"]
    return [("%s/%s-%s.target" % (group, tname, side), abs(value))]


def apply_targets(base, weighted):
    v = base.copy()
    for rel, w in weighted:
        if w == 0.0:
            continue
        idx, off = target(rel)
        v[idx] += off * w
    return v


class Skeleton:
    def __init__(self):
        sk = json.load(open(fetch("rigs/default.mhskel")))
        self.bones = sk["bones"]
        self.joints = sk["joints"]
        w = json.load(open(fetch("rigs/default_weights.mhw")))["weights"]
        self.weights = {b: np.array(lst, dtype=np.float64) for b, lst in w.items()}

    def joint(self, v, name):
        return v[self.joints[name]].mean(axis=0)

    def head(self, v, bone):
        return self.joint(v, self.bones[bone]["head"])

    def tail(self, v, bone):
        return self.joint(v, self.bones[bone]["tail"])

    def ancestors(self, bone):
        out = []
        while bone:
            out.append(bone)
            bone = self.bones[bone]["parent"]
        return out


class Proxy:
    """A clothes / hair / eyebrow / eye file fitted to the base mesh (.mhclo + .obj)."""

    def __init__(self, mhclo_path):
        self.dir = os.path.dirname(mhclo_path)
        self.refs = []  # (indices[3], weights[3], offset[3])
        self.delete = []
        self.scales = {}
        self.obj_file = None
        self.material = None
        mode = None
        for raw in open(mhclo_path, encoding="utf-8", errors="ignore"):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            words = line.split()
            key = words[0]
            if key == "verts":
                mode = "verts"
                continue
            if key == "delete_verts":
                mode = "delete"
                continue
            if mode == "verts" and (key[0].isdigit() or key[0] == "-"):
                nums = [float(x) for x in words]
                if len(nums) == 1:
                    self.refs.append(([int(nums[0])] * 3, [1.0, 0.0, 0.0], [0.0, 0.0, 0.0]))
                else:
                    self.refs.append(([int(nums[0]), int(nums[1]), int(nums[2])], nums[3:6], nums[6:9]))
                continue
            if mode == "delete" and (key[0].isdigit()):
                i = 0
                while i < len(words):
                    if words[i] == "-":
                        a = self.delete[-1]
                        b = int(words[i + 1])
                        self.delete.extend(range(a + 1, b + 1))
                        i += 2
                    else:
                        self.delete.append(int(words[i]))
                        i += 1
                continue
            if key == "obj_file":
                self.obj_file = os.path.join(self.dir, words[1])
            elif key == "material":
                self.material = os.path.join(self.dir, words[1])
            elif key in ("x_scale", "y_scale", "z_scale"):
                self.scales[key[0]] = (int(words[1]), int(words[2]), float(words[3]))
        self.obj = Obj(self.obj_file)
        self.ref_idx = np.array([r[0] for r in self.refs], dtype=np.int64)
        self.ref_w = np.array([r[1] for r in self.refs], dtype=np.float64)
        self.ref_off = np.array([r[2] for r in self.refs], dtype=np.float64)

    def fit(self, base_v):
        scale = np.ones(3)
        for axis, i in (("x", 0), ("y", 1), ("z", 2)):
            if axis in self.scales:
                a, b, d = self.scales[axis]
                scale[i] = abs(base_v[a][i] - base_v[b][i]) / d
        pos = (base_v[self.ref_idx] * self.ref_w[:, :, None]).sum(axis=1)
        return pos + self.ref_off * scale

    def material_textures(self):
        tex = {}
        if not self.material or not os.path.exists(self.material):
            return tex
        for line in open(self.material, encoding="utf-8", errors="ignore"):
            words = line.split()
            if len(words) >= 2 and words[0] in ("diffuseTexture", "normalmapTexture", "aomapTexture", "specularmapTexture"):
                tex[words[0]] = os.path.join(os.path.dirname(self.material), words[1])
        return tex
