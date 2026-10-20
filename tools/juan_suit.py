#!/usr/bin/env python3
"""Juan Salvo's game model from a friend's blue-suit survivor (October 2026): a Meshy AI biped on a Mixamo skeleton
(60 bones), one skinned mesh of 10,390 triangles, 2K textures and nine clips, put into Godot's format by a friend of
Ale's. Made ready for the game without changing what it is, and with Juan's rifle in his hands:

  1. metres and Y up: the conversion's wrapper nodes (a turn from Z up, a scale of 100 and one of 0.0104, a turn of
     1.6 degrees to face +z) are baked into the bones, the clips and the mesh (stored as it stood when bound), so that
     the game's rig (rig_person.gd) measures him in metres, as it does every person;
  2. a rest pose to move him from: standing straight, the rifle across his chest in both hands as the blue-hood Juan
     held it. The model's own rest was a frame of its walk, one foot in the air, and the game's fall, sit and kneel are
     turns away from the rest. Only the rest changes: the bind is kept, so the mesh is untouched. The grip of his hands
     and his fingers come from the RunShoot clip, which holds a rifle; the clips leave his fingers alone, so they stay
     closed on it;
  3. the rifle (art/juan_salvo/source/rifle.glb, the blue-hood Juan's, written by --rifle) on a bone of its own under
     his chest, its mesh named "Rifle" (the slot's prop);
  4. the mesh indexed (it came as loose triangles), only the clips the game plays (Idle, Walk, Run, Jump), the colour
     map kept at 2048 (one atlas for the whole of him, his face in it), the normals at 1024, metal and roughness at 512;
  5. every name in it Juan Salvo's own, and a check that nothing in the file names the comic.

    python3 tools/juan_suit.py <the friend's .glb> [out.glb]
    python3 tools/juan_suit.py --rifle <the blue-hood juan_salvo.glb>      # writes art/juan_salvo/source/rifle.glb

The friend's package is not kept in the repository (its .glb is under characters/). The output goes to
godot/art_pack/juan_salvo/juan_salvo.glb, and the speeds its walk and run were made for (from how fast a planted foot
goes back) are printed for the slot's clip_speed. Needs numpy and Pillow.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "godot", "art_pack", "juan_salvo", "juan_salvo.glb")
RIFLE = os.path.join(ROOT, "art", "juan_salvo", "source", "rifle.glb")
# the comic's title, spelled out of letters so that it is not written here either
FORBIDDEN = "".join(chr(c) for c in (101, 116, 101, 114, 110, 97, 117, 116, 97))
CLIPS = ["Idle", "Walk", "Run", "Jump"]
# the clip and the moment whose hands hold a rifle: the grip and the fingers come from there
GRIP = ("RunShoot", 0.0)
# the largest side kept for each of his maps
SIDES = {"colour": 2048, "normal": 1024, "metal": 512}
# his bones by the part they play here (Mixamo's names)
P = "mixamorig"
SPINE = [P + "Spine", P + "Spine1", P + "Spine2", P + "Neck", P + "Head"]
LEGS = {"R": [P + "RightUpLeg", P + "RightLeg", P + "RightFoot", P + "RightToeBase", P + "RightToe_End"],
        "L": [P + "LeftUpLeg", P + "LeftLeg", P + "LeftFoot", P + "LeftToeBase", P + "LeftToe_End"]}
ARMS = {"R": [P + "RightArm", P + "RightForeArm", P + "RightHand"], "L": [P + "LeftArm", P + "LeftForeArm", P + "LeftHand"]}
CHEST = P + "Spine2"
FOOT_DOWN = np.array([0.0, -0.45, 1.0])   # a standing foot, from the ankle to the ball: forward and a little down

COMPONENTS = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


# ------------------------------------------------------------------------------------------------ reading and writing

def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", data[off:off + 4])[0]
    return j, data[off + 8:off + 8 + blen]


def accessor(j, blob, index):
    """An accessor's values as an array of rows (float for normalised integers)."""
    a = j["accessors"][index]
    view = j["bufferViews"][a["bufferView"]]
    dtype = np.dtype(COMPONENTS[a["componentType"]])
    width = WIDTHS[a["type"]]
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    if stride == dtype.itemsize * width:
        out = np.frombuffer(blob, dtype, a["count"] * width, start).reshape(a["count"], width)
    else:
        out = np.array([np.frombuffer(blob, dtype, width, start + i * stride) for i in range(a["count"])])
    if a.get("normalized"):
        out = out.astype(np.float64) / np.iinfo(dtype).max
    return out


def image_bytes(j, blob, index):
    view = j["bufferViews"][j["images"][index]["bufferView"]]
    return blob[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]


class Builder:
    """A new glTF: its JSON and one binary buffer."""

    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "tools/juan_suit.py"}, "scene": 0, "scenes": [], "nodes": [],
                  "meshes": [], "materials": [], "textures": [], "images": [], "samplers": [], "accessors": [],
                  "bufferViews": [], "buffers": []}
        self.blob = bytearray()

    def view(self, data, target=None):
        while len(self.blob) % 4:
            self.blob += b"\0"
        v = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target is not None:
            v["target"] = target
        self.blob += data
        self.j["bufferViews"].append(v)
        return len(self.j["bufferViews"]) - 1

    def accessor(self, rows, kind, component=5126, target=None, bounds=False):
        rows = np.ascontiguousarray(rows, dtype=COMPONENTS[component])
        a = {"bufferView": self.view(rows.tobytes(), target), "componentType": component, "count": len(rows), "type": kind}
        if bounds:
            flat = rows.reshape(len(rows), -1)
            a["min"] = [float(v) for v in flat.min(axis=0)]
            a["max"] = [float(v) for v in flat.max(axis=0)]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def texture(self, png, name):
        if not self.j["samplers"]:
            self.j["samplers"].append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
        self.j["images"].append({"bufferView": self.view(png), "mimeType": "image/png", "name": name})
        self.j["textures"].append({"sampler": 0, "source": len(self.j["images"]) - 1})
        return len(self.j["textures"]) - 1

    def save(self, path):
        while len(self.blob) % 4:
            self.blob += b"\0"
        self.j["buffers"] = [{"byteLength": len(self.blob)}]
        for key in [k for k, v in self.j.items() if v == []]:
            del self.j[key]
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        if FORBIDDEN in js.decode().lower() or FORBIDDEN.encode() in bytes(self.blob).lower():
            sys.exit("the comic's title is in the model: not written")
        total = 12 + 8 + len(js) + 8 + len(self.blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.blob), 0x004E4942))
            f.write(self.blob)


def png(data, side=None):
    """An image as PNG, its largest side brought down to `side`."""
    pic = Image.open(io.BytesIO(data))
    pic = pic.convert("RGBA" if pic.mode in ("RGBA", "LA", "P") else "RGB")
    if side and max(pic.size) > side:
        k = side / max(pic.size)
        pic = pic.resize((max(1, round(pic.size[0] * k)), max(1, round(pic.size[1] * k))), Image.LANCZOS)
    out = io.BytesIO()
    pic.save(out, "PNG", optimize=True)
    return out.getvalue()


# ------------------------------------------------------------------------------------------------ turns and frames

def quat_matrix(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def matrix_quat(m):
    """The unit quaternion (x, y, z, w) of a rotation matrix."""
    t = np.trace(m)
    if t > 0.0:
        s = 2.0 * np.sqrt(t + 1.0)
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = 2.0 * np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2])
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = 2.0 * np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2])
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = 2.0 * np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1])
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def arc(a, b):
    """The shortest turn taking direction a to direction b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c > 1.0 - 1e-9:
        return np.eye(3)
    if c < -1.0 + 1e-9:
        axis = np.cross(a, [1.0, 0.0, 0.0] if abs(a[0]) < 0.9 else [0.0, 1.0, 0.0])
        axis /= np.linalg.norm(axis)
        return 2.0 * np.outer(axis, axis) - np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1.0 + c)


def frame(origin_dir, up):
    """A frame with x along origin_dir and y toward up."""
    x = origin_dir / np.linalg.norm(origin_dir)
    y = up - x * np.dot(x, up)
    y /= np.linalg.norm(y)
    return np.column_stack([x, y, np.cross(x, y)])


def rigid(rot, at):
    m = np.eye(4)
    m[:3, :3] = rot
    m[:3, 3] = at
    return m


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = quat_matrix(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]), float)
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def worlds(nodes, local):
    """Every node's world matrix from its local one (`local`: index -> 4x4)."""
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    out = {}

    def w(i):
        if i not in out:
            out[i] = (w(parent[i]) @ local[i]) if i in parent else local[i]
        return out[i]
    for i in range(len(nodes)):
        w(i)
    return out


def sample(j, blob, clip, t, nodes):
    """Local matrices of every node at time t of a clip (linear, slerp), over their rest."""
    local = {i: node_matrix(n) for i, n in enumerate(nodes)}
    anim = next(a for a in j["animations"] if a.get("name") == clip)
    trs = {}
    for ch in anim["channels"]:
        smp = anim["samplers"][ch["sampler"]]
        times = accessor(j, blob, smp["input"])[:, 0]
        vals = accessor(j, blob, smp["output"]).astype(np.float64)
        i = int(np.clip(np.searchsorted(times, t, side="right") - 1, 0, len(times) - 1))
        k = min(i + 1, len(times) - 1)
        u = 0.0 if k == i else (t - times[i]) / (times[k] - times[i])
        if ch["target"]["path"] == "rotation":
            a, b = vals[i], vals[k] * (1 if np.dot(vals[i], vals[k]) >= 0 else -1)
            v = (1 - u) * a + u * b
            v /= np.linalg.norm(v)
        else:
            v = (1 - u) * vals[i] + u * vals[k]
        trs.setdefault(ch["target"]["node"], {})[ch["target"]["path"]] = v
    for node, parts in trs.items():
        n = nodes[node]
        m = np.eye(4)
        m[:3, :3] = quat_matrix(parts.get("rotation", n.get("rotation", [0, 0, 0, 1]))) * np.array(parts.get("scale", n.get("scale", [1, 1, 1])), float)
        m[:3, 3] = parts.get("translation", n.get("translation", [0, 0, 0]))
        local[node] = m
    return local


# ------------------------------------------------------------------------------------------------ the rifle

def extract_rifle(src):
    """The blue-hood Juan's rifle as he held it at rest (world, metres), with where his chest, wrists and elbows were."""
    j, blob = read_glb(src)
    nodes = j["nodes"]
    w = worlds(nodes, {i: node_matrix(n) for i, n in enumerate(nodes)})
    names = {n.get("name"): i for i, n in enumerate(nodes) if "mesh" not in n}
    mesh_node = next(i for i, n in enumerate(nodes) if n.get("name") == "Rifle" and "mesh" in n)
    skin = j["skins"][nodes[mesh_node]["skin"]]
    ibm = accessor(j, blob, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    prim = j["meshes"][nodes[mesh_node]["mesh"]]["primitives"][0]
    at = prim["attributes"]
    pos = accessor(j, blob, at["POSITION"]).astype(np.float64)
    nrm = accessor(j, blob, at["NORMAL"]).astype(np.float64)
    tan = accessor(j, blob, at["TANGENT"]).astype(np.float64)
    joints = accessor(j, blob, at["JOINTS_0"]).astype(int)
    weights = accessor(j, blob, at["WEIGHTS_0"]).astype(np.float64)
    skinning = np.array([w[skin["joints"][k]] @ ibm[k] for k in range(len(skin["joints"]))])
    mats = np.einsum("vk,vkij->vij", weights, skinning[joints])
    pos_w = np.einsum("vij,vj->vi", mats[:, :3, :3], pos) + mats[:, :3, 3]
    nrm_w = np.einsum("vij,vj->vi", mats[:, :3, :3], nrm)
    tan_w = np.einsum("vij,vj->vi", mats[:, :3, :3], tan[:, :3])
    gun = w[names["Rifle"]]
    inv = np.linalg.inv(gun)
    out = Builder()
    out.j["asset"]["extras"] = {"about": "Juan Salvo's rifle (the blue-hood Juan's, made in Codex) as he held it at rest; "
                                         "Chest, Grip.R/L (his wrists) and Elbow.R/L where they were. tools/juan_suit.py"}
    attrs = {"POSITION": out.accessor((pos_w @ inv[:3, :3].T) + inv[:3, 3], "VEC3", target=34962, bounds=True),
             "NORMAL": out.accessor(_unit(nrm_w @ inv[:3, :3].T), "VEC3", target=34962),
             "TANGENT": out.accessor(np.column_stack([_unit(tan_w @ inv[:3, :3].T), tan[:, 3]]), "VEC4", target=34962),
             "TEXCOORD_0": out.accessor(accessor(j, blob, at["TEXCOORD_0"]), "VEC2", target=34962)}
    material = _copy_material(j, blob, prim["material"], out)
    indices = accessor(j, blob, prim["indices"])[:, 0]
    out.j["meshes"].append({"name": "Rifle", "primitives": [{"attributes": attrs, "material": material,
                            "indices": out.accessor(indices, "SCALAR", 5123 if indices.max() < 65536 else 5125, 34963)}]})
    out.j["nodes"].append({"name": "Rifle", "mesh": 0, "translation": list(gun[:3, 3]), "rotation": list(matrix_quat(gun[:3, :3]))})
    for mark, bone in [("Chest", "Chest"), ("Grip.R", "Hand.R"), ("Grip.L", "Hand.L"), ("Elbow.R", "Forearm.R"), ("Elbow.L", "Forearm.L")]:
        out.j["nodes"].append({"name": mark, "translation": list(w[names[bone]][:3, 3])})
    out.j["scenes"].append({"nodes": list(range(len(out.j["nodes"])))})
    os.makedirs(os.path.dirname(RIFLE), exist_ok=True)
    out.save(RIFLE)
    print(f"{RIFLE}: {len(indices) // 3} triangles, {os.path.getsize(RIFLE) // 1024} KB")


def _unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-12)


def _finger(name):
    """A finger's bone (Mixamo names them after the hand: mixamorigLeftHandThumb1, ...)."""
    return "Hand" in name and any(f in name for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"))


def _copy_material(j, blob, index, out):
    """A material and its textures, into `out` (images as they are)."""
    mat = json.loads(json.dumps(j["materials"][index]))
    mat.pop("extras", None)

    def redo(ref):
        if ref is not None:
            img = j["textures"][ref["index"]]["source"]
            ref["index"] = out.texture(bytes(image_bytes(j, blob, img)), j["images"][img].get("name", "rifle"))
    pbr = mat.get("pbrMetallicRoughness", {})
    redo(pbr.get("baseColorTexture"))
    redo(pbr.get("metallicRoughnessTexture"))
    redo(mat.get("normalTexture"))
    redo(mat.get("occlusionTexture"))
    out.j["materials"].append(mat)
    return len(out.j["materials"]) - 1


# ------------------------------------------------------------------------------------------------ the model

class Rig:
    """The new skeleton: its bones (the skin's joints and the rifle's), parents, rest (local translation and turn)."""

    def __init__(self, names, parent):
        self.names = names
        self.index = {n: i for i, n in enumerate(names)}
        self.parent = parent
        self.t = [np.zeros(3) for _ in names]
        self.q = [np.array([0.0, 0.0, 0.0, 1.0]) for _ in names]
        self.order = []
        placed = set()
        while len(self.order) < len(names):
            for i in range(len(names)):
                if i not in placed and (parent[i] < 0 or parent[i] in placed):
                    self.order.append(i)
                    placed.add(i)

    def world(self):
        w = [None] * len(self.names)
        for i in self.order:
            m = rigid(quat_matrix(self.q[i]), self.t[i])
            w[i] = m if self.parent[i] < 0 else w[self.parent[i]] @ m
        return w

    def set_world(self, i, m):
        """Sets bone i's local rest so that it stands at world matrix m (its parent as it is now)."""
        local = m if self.parent[i] < 0 else np.linalg.inv(self.world()[self.parent[i]]) @ m
        self.t[i] = local[:3, 3].copy()
        self.q[i] = matrix_quat(local[:3, :3])

    def turn(self, name, rot):
        """Turns a bone about its own head by `rot` (world)."""
        i = self.index[name]
        m = self.world()[i]
        self.set_world(i, rigid(rot @ m[:3, :3], m[:3, 3]))

    def aim(self, name, child, direction):
        """Turns a bone the shortest way so that its child lies in `direction` from it."""
        w = self.world()
        self.turn(name, arc(w[self.index[child]][:3, 3] - w[self.index[name]][:3, 3], np.asarray(direction, float)))

    def at(self, name):
        return self.world()[self.index[name]][:3, 3]


def convert(src, dst):
    j, blob = read_glb(src)
    nodes = j["nodes"]
    skin = j["skins"][0]
    joints = skin["joints"]
    mesh_node = next(i for i, n in enumerate(nodes) if "mesh" in n and "skin" in n)
    parent_of = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    w_old = worlds(nodes, {i: node_matrix(n) for i, n in enumerate(nodes)})
    # 1. the wrappers above the skeleton: one turn, one move, one scale (s), baked into everything below
    root = next(k for k in joints if parent_of.get(k) not in joints)
    wrap = w_old[parent_of[root]] if root in parent_of else np.eye(4)
    s = float(np.cbrt(np.linalg.det(wrap[:3, :3])))
    turn = wrap[:3, :3] / s
    assert np.allclose(turn @ turn.T, np.eye(3), atol=1e-4), "the wrappers do not scale evenly"
    unscale = np.diag([1 / s, 1 / s, 1 / s, 1.0])
    ibm = accessor(j, blob, skin["inverseBindMatrices"]).astype(np.float64).reshape(-1, 4, 4).transpose(0, 2, 1)
    # the mesh where it stood when bound (world, metres): its node's place (the exporter's inverse binds are each bone's
    # inverse at bind times the mesh's bind matrix). Its bones' rest is another pose (a frame of the walk).
    bind = w_old[mesh_node]
    prim = j["meshes"][nodes[mesh_node]["mesh"]]["primitives"][0]
    at = prim["attributes"]
    pos = accessor(j, blob, at["POSITION"]).astype(np.float64)
    nrm = accessor(j, blob, at["NORMAL"]).astype(np.float64)
    tan = accessor(j, blob, at["TANGENT"]).astype(np.float64)
    uv = accessor(j, blob, at["TEXCOORD_0"]).astype(np.float64)
    jnt = accessor(j, blob, at["JOINTS_0"]).astype(int)
    wgt = accessor(j, blob, at["WEIGHTS_0"]).astype(np.float64)
    wgt /= np.maximum(wgt.sum(axis=1, keepdims=True), 1e-9)
    lin = bind[:3, :3]
    pos = pos @ lin.T + bind[:3, 3]
    nrm = _unit(nrm @ lin.T)
    tan = np.column_stack([_unit(tan[:, :3] @ lin.T), np.sign(tan[:, 3]) + (tan[:, 3] == 0)])
    # bones: the skin's, then the rifle's under the chest
    names = [nodes[k]["name"] for k in joints] + ["Rifle"]
    chest = next(i for i, n in enumerate(nodes) if n.get("name") == CHEST)
    parent = [joints.index(parent_of[k]) if parent_of.get(k) in joints else -1 for k in joints] + [joints.index(chest)]
    rig = Rig(names, parent)
    # bound as before, in the new space: each joint's inverse bind with the scale taken out and the mesh's bind put in
    rescale = np.diag([s, s, s, 1.0])
    inv_bind = [rescale @ ibm[n] @ np.linalg.inv(bind) for n in range(len(joints))]

    def new_world(local):
        """Joint world matrices (new space) for the old nodes' locals."""
        w = worlds(nodes, local)
        return [w[k] @ unscale for k in joints]

    # 2. the rest: from the first moment of Idle (parents first), standing straight
    idle = new_world(sample(j, blob, "Idle", 0.0, nodes))
    for n in rig.order:
        if n < len(joints):
            rig.set_world(n, idle[n])
    _stand(rig)
    # standing on the ground: his lowest point (the mesh as he stands at rest) on y = 0, over the middle of his feet
    low = _posed(rig, inv_bind, pos, jnt, wgt)[:, 1].min()
    hips = rig.index[P + "Hips"]
    feet = (rig.at(LEGS["R"][2]) + rig.at(LEGS["L"][2])) / 2.0
    rig.t[hips] = rig.t[hips] - np.array([feet[0], low, feet[2]])
    # the rifle as the blue-hood Juan held it, moved with his chest; his hands on it, gripping as in RunShoot
    rj, rblob = read_glb(RIFLE)
    marks = {n["name"]: np.array(n.get("translation", [0, 0, 0])) for n in rj["nodes"]}
    gun_old = node_matrix(next(n for n in rj["nodes"] if n.get("name") == "Rifle"))
    shift = rig.at(CHEST) - marks["Chest"]
    gun = gun_old.copy()
    gun[:3, 3] += shift
    grip_old = new_world(sample(j, blob, GRIP[0], GRIP[1], nodes))
    gi = {nodes[k]["name"]: n for n, k in enumerate(joints)}
    hand_r, hand_l = grip_old[gi[ARMS["R"][2]]], grip_old[gi[ARMS["L"][2]]]
    held = frame(hand_l[:3, 3] - hand_r[:3, 3], np.array([0.0, 1.0, 0.0]))
    wrist = {"R": marks["Grip.R"] + shift, "L": marks["Grip.L"] + shift}
    holding = frame(wrist["L"] - wrist["R"], np.array([0.0, 1.0, 0.0]))
    reach = {}
    for side, hand in (("R", hand_r), ("L", hand_l)):
        reach[side] = _arm(rig, side, wrist[side], marks["Elbow." + side] + shift, holding @ held.T @ hand[:3, :3])
    for n, k in enumerate(joints):
        if _finger(nodes[k]["name"]):
            local = np.linalg.inv(grip_old[parent[n]]) @ grip_old[n]
            rig.q[n] = matrix_quat(local[:3, :3])
    rig.set_world(rig.index["Rifle"], gun)
    # 3. the clips the game plays, without the wrappers (the root carries them) and without the fingers
    out = Builder()
    clips = []
    turn_q = matrix_quat(turn)
    for anim in j["animations"]:
        if anim.get("name") not in CLIPS:
            continue
        channels, samplers = [], []
        for ch in anim["channels"]:
            node = ch["target"]["node"]
            if node not in joints or ch["target"]["path"] == "scale":
                continue
            if _finger(nodes[node]["name"]):
                continue
            smp = anim["samplers"][ch["sampler"]]
            times = accessor(j, blob, smp["input"])[:, 0]
            vals = accessor(j, blob, smp["output"]).astype(np.float64)
            if node == root:
                if ch["target"]["path"] == "rotation":
                    vals = np.array([quat_mul(turn_q, v) for v in vals])
                else:
                    vals = vals * s @ turn.T + wrap[:3, 3]
            elif ch["target"]["path"] == "translation":
                vals = vals * s
            samplers.append({"input": out.accessor(times, "SCALAR", bounds=True), "interpolation": smp.get("interpolation", "LINEAR"),
                             "output": out.accessor(vals, "VEC4" if ch["target"]["path"] == "rotation" else "VEC3")})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": 1 + joints.index(node), "path": ch["target"]["path"]}})
        clips.append({"name": anim["name"], "channels": channels, "samplers": samplers})
    # 4. the mesh, indexed (each corner that repeats another in everything becomes one vertex, in the order they came);
    # the rifle on its bone
    rows = np.column_stack([pos, nrm, tan, uv, jnt, wgt]).round(7)
    _, first, inverse = np.unique(rows, axis=0, return_index=True, return_inverse=True)
    rank = np.empty(len(first), int)
    rank[np.argsort(first)] = np.arange(len(first))
    order = np.sort(first)
    index = rank[inverse.reshape(-1)]
    suit = {"POSITION": out.accessor(pos[order], "VEC3", target=34962, bounds=True),
            "NORMAL": out.accessor(nrm[order], "VEC3", target=34962),
            "TANGENT": out.accessor(tan[order], "VEC4", target=34962),
            "TEXCOORD_0": out.accessor(uv[order], "VEC2", target=34962),
            "JOINTS_0": out.accessor(jnt[order], "VEC4", 5123, 34962),
            "WEIGHTS_0": out.accessor(wgt[order], "VEC4", target=34962)}
    src_mat = j["materials"][prim["material"]]
    pbr = src_mat.get("pbrMetallicRoughness", {})
    tex = {}
    for key, ref, side, name in (("colour", pbr.get("baseColorTexture"), SIDES["colour"], "suit_basecolor"),
                                 ("normal", src_mat.get("normalTexture"), SIDES["normal"], "suit_normal"),
                                 ("metal", pbr.get("metallicRoughnessTexture"), SIDES["metal"], "suit_metallic_roughness")):
        if ref is not None:
            tex[key] = out.texture(png(image_bytes(j, blob, j["textures"][ref["index"]]["source"]), side), name)
    mat = {"name": "Juan Salvo / suit", "pbrMetallicRoughness": {"baseColorTexture": {"index": tex["colour"]},
                                                                   "metallicFactor": float(pbr.get("metallicFactor", 1.0)),
                                                                   "roughnessFactor": float(pbr.get("roughnessFactor", 1.0))}}
    if "metal" in tex:
        mat["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": tex["metal"]}
    if "normal" in tex:
        mat["normalTexture"] = {"index": tex["normal"]}
    out.j["materials"].append(mat)
    out.j["meshes"].append({"name": "Suit", "primitives": [{"attributes": suit, "material": 0, "indices":
                            out.accessor(index, "SCALAR", 5123 if len(order) < 65536 else 5125, 34963)}]})
    rmesh = rj["meshes"][0]["primitives"][0]
    ra = rmesh["attributes"]
    gun_pos = accessor(rj, rblob, ra["POSITION"]).astype(np.float64) @ gun[:3, :3].T + gun[:3, 3]
    gun_rot = gun[:3, :3]
    rifle = {"POSITION": out.accessor(gun_pos, "VEC3", target=34962, bounds=True),
             "NORMAL": out.accessor(_unit(accessor(rj, rblob, ra["NORMAL"]) @ gun_rot.T), "VEC3", target=34962),
             "TANGENT": out.accessor(np.column_stack([_unit(accessor(rj, rblob, ra["TANGENT"])[:, :3] @ gun_rot.T), accessor(rj, rblob, ra["TANGENT"])[:, 3]]), "VEC4", target=34962),
             "TEXCOORD_0": out.accessor(accessor(rj, rblob, ra["TEXCOORD_0"]), "VEC2", target=34962),
             "JOINTS_0": out.accessor(np.tile([len(joints), 0, 0, 0], (len(gun_pos), 1)), "VEC4", 5123, 34962),
             "WEIGHTS_0": out.accessor(np.tile([1.0, 0.0, 0.0, 0.0], (len(gun_pos), 1)), "VEC4", target=34962)}
    gun_mat = _copy_material(rj, rblob, rmesh["material"], out)
    rifle_index = accessor(rj, rblob, rmesh["indices"])[:, 0]
    out.j["meshes"].append({"name": "Rifle", "primitives": [{"attributes": rifle, "material": gun_mat, "indices":
                            out.accessor(rifle_index, "SCALAR", 5123 if rifle_index.max() < 65536 else 5125, 34963)}]})
    # the nodes: the rig, its bones (rest), the two meshes; the skin binds the suit as it was bound and the rifle as it rests
    count = len(names)
    out.j["nodes"].append({"name": "SalvoRig", "children": [1 + hips, 1 + count, 2 + count]})
    for n in range(count):
        node = {"name": names[n], "translation": [float(v) for v in rig.t[n]], "rotation": [float(v) for v in rig.q[n]]}
        kids = [1 + k for k in range(count) if parent[k] == n]
        if kids:
            node["children"] = kids
        out.j["nodes"].append(node)
    out.j["nodes"].append({"name": "Suit", "mesh": 0, "skin": 0})
    out.j["nodes"].append({"name": "Rifle", "mesh": 1, "skin": 0})
    rest = rig.world()
    ibms = inv_bind + [np.linalg.inv(rest[rig.index["Rifle"]])]
    out.j["skins"] = [{"joints": [1 + n for n in range(count)], "skeleton": 1 + hips,
                       "inverseBindMatrices": out.accessor(np.array([m.T.reshape(16) for m in ibms]), "MAT4")}]
    out.j["animations"] = clips
    out.j["scenes"].append({"nodes": [0]})
    out.save(dst)
    tris = (len(index) + len(rifle_index)) // 3
    print(f"{dst}: {tris} triangles ({len(index) // 3} suit, {len(rifle_index) // 3} rifle), {len(order)} vertices "
          f"(from {len(pos)}), {count} bones, clips {', '.join(c['name'] for c in clips)}, {os.path.getsize(dst) / 1e6:.1f} MB")
    print(f"  baked: scale {s:.4f}; rest: hips {rig.at(P + 'Hips')[1]:.3f} m, "
          f"hands short of the rifle by {reach['R'] * 100:.1f} / {reach['L'] * 100:.1f} cm (right / left)")
    for clip in ("Walk", "Run"):
        print(f"  {clip.lower()} made for {_clip_speed(j, blob, nodes, joints, unscale, clip):.3f} m/s")


def _stand(rig):
    """Straightens him up from his idle: hips level and square, back and head upright, legs straight down, feet flat."""
    hips = P + "Hips"
    across = rig.at(LEGS["L"][0]) - rig.at(LEGS["R"][0])
    up = rig.at(SPINE[0]) - rig.at(hips)
    now = frame(across, up)
    want = frame(np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0]))
    rig.turn(hips, want @ now.T)
    for bone, child in zip(SPINE, SPINE[1:] + [P + "HeadTop_End"]):
        rig.aim(bone, child, [0.0, 1.0, 0.0])
    # square to his front (a turn about the upright, so his back stays upright)
    across = rig.at(P + "LeftShoulder") - rig.at(P + "RightShoulder")
    rig.turn(CHEST, arc(np.array([across[0], 0.0, across[2]]), np.array([1.0, 0.0, 0.0])))
    for chain in LEGS.values():
        rig.aim(chain[0], chain[1], [0.0, -1.0, 0.0])
        rig.aim(chain[1], chain[2], [0.0, -1.0, 0.0])
        rig.aim(chain[2], chain[3], FOOT_DOWN)
        rig.aim(chain[3], chain[4], [0.0, 0.0, 1.0])


def _arm(rig, side, wrist, pole, hand_rot):
    """Reaches an arm (two bones) for `wrist`, its elbow toward `pole`, and turns the hand to `hand_rot`. How far the
    wrist stays from where it was asked to go (m)."""
    arm, fore, hand = ARMS[side]
    top = rig.at(arm)
    l1 = np.linalg.norm(rig.at(fore) - top)
    l2 = np.linalg.norm(rig.at(hand) - rig.at(fore))
    to = wrist - top
    dist = float(np.clip(np.linalg.norm(to), abs(l1 - l2) + 0.001, (l1 + l2) * 0.999))
    d = to / np.linalg.norm(to)
    cos_a = np.clip((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1.0, 1.0)
    side_dir = pole - top
    side_dir -= d * np.dot(d, side_dir)
    side_dir /= np.linalg.norm(side_dir)
    elbow = top + d * l1 * cos_a + side_dir * l1 * np.sqrt(1 - cos_a * cos_a)
    rig.aim(arm, fore, elbow - top)
    rig.aim(fore, hand, top + d * dist - rig.at(fore))
    i = rig.index[hand]
    rig.set_world(i, rigid(hand_rot, rig.world()[i][:3, 3]))
    return float(np.linalg.norm(rig.at(hand) - wrist))


def _posed(rig, inv_bind, pos, jnt, wgt):
    """The mesh as the rig's rest has it."""
    w = rig.world()
    skinning = np.array([w[n] @ inv_bind[n] for n in range(len(inv_bind))])
    mats = np.einsum("vk,vkij->vij", wgt, skinning[jnt])
    return np.einsum("vij,vj->vi", mats[:, :3, :3], pos) + mats[:, :3, 3]


def _clip_speed(j, blob, nodes, joints, unscale, clip):
    """How fast a clip made in place goes: how fast a foot on the ground goes back under him, averaged over both feet."""
    anim = next(a for a in j["animations"] if a.get("name") == clip)
    length = max(float(accessor(j, blob, s["input"])[:, 0].max()) for s in anim["samplers"])
    steps = 120
    feet = [next(k for k in joints if nodes[k]["name"] == LEGS[side][3]) for side in ("R", "L")]
    track = []
    for i in range(steps):
        w = worlds(nodes, sample(j, blob, clip, length * i / steps, nodes))
        track.append([(w[f] @ unscale)[:3, 3] for f in feet])
    track = np.array(track)
    speeds = []
    for f in range(2):
        y = track[:, f, 1]
        down = y < y.min() + 0.015
        for i in range(steps):
            k = (i + 1) % steps
            if down[i] and down[k]:
                speeds.append((track[i, f, 2] - track[k, f, 2]) * steps / length)
    return float(np.median(speeds)) if speeds else 0.0


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--rifle":
        extract_rifle(sys.argv[2])
        return
    convert(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else OUT)


if __name__ == "__main__":
    main()
