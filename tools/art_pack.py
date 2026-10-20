#!/usr/bin/env python3
"""The art pack's tool (godot/art_pack/, docs/ART_PACK.md): checks the manifest and the files it names, converts models
to GLB, and draws the neutral test drawings the pipeline is tested with.

    python3 tools/art_pack.py check                     # the manifest and every file it names; exit 1 on an error
    python3 tools/art_pack.py check --strict            # warnings count as errors too
    python3 tools/art_pack.py convert in.stl out.glb    # STL, OBJ (and what trimesh reads) to GLB; FBX via Blender or assimp
    python3 tools/art_pack.py decimate in.glb out.glb --faces 40000   # a sculpt brought down to a budget of triangles
    python3 tools/art_pack.py refine-person                # Juan Salvo's model rounded, its atlas redrawn, its bake (below)
    python3 tools/art_pack.py test-art                  # (re)draws art_pack/test/*.png: a man in a coat and cap, a blob
    python3 tools/art_pack.py test-models               # (re)makes art_pack/test/*.glb: a capsule, a long block, a rigged post

check looks at, for each slot: its id (lower case, digits and _), name, kind (person, creature, prop), height (metres,
sensible for the kind), the files (there, PNG or GLB/GLTF, inside the pack), and for a PNG: its size (big enough to
read, not wastefully big), that it has an alpha channel with a transparent background and transparent margins, that
the figure fills its canvas, that a figure stands on the bottom of it; for every slot with a file (test drawings
aside): the author, the licence and the permission note filled in, and a warning on licences that rarely allow this
use (personal use only, non-commercial, no derivatives, "all rights reserved") and on files from model shops.

For a model (GLB/GLTF) check reads the file itself: its triangles against the kind's budget (a fan's sculpt is often a
million; a figure in the game wants tens of thousands: a warning over the budget, an error far over it, each with the
ratio to decimate by), its size as modelled and which way up and along it lies (the game scales it to height_m, stands
it on the ground and turns it the way it walks: "forward" names the model's front, +z by glTF's custom), and whether it
has a skeleton and the animations the game plays (idle, walk or run, crawl, crouch, down or death: by name, any case);
a static model is moved by the game itself (a step and a sway for a person, a crawl for a creature).
Pillow is needed for the PNG checks; trimesh for convert (pip install trimesh); decimate needs Blender on the PATH, or
trimesh with fast_simplification (pip install fast_simplification).
"""
import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PACK = os.path.join(ROOT, "godot", "art_pack")
KINDS = {"person": (1.0, 2.4), "creature": (0.3, 30.0), "prop": (0.2, 20.0)}
# triangles a model of each kind may have before check warns (and errors at ERROR_OVER times as many): the game may show
# a dozen figures at once on a phone, and a web build carries every file
BUDGET = {"person": 40000, "creature": 60000, "prop": 20000}
ERROR_OVER = 8
FORWARDS = ("+z", "-z", "+x", "-x")
# the animations the game looks for in a model (any case, as part of the name)
ANIMS = ("idle", "walk", "run", "crawl", "crouch", "down", "death", "die")
VIEWS = ("back", "crouch", "down")
# words in a licence or note that usually mean the file may not be used here, or not without more permission
RISKY = [
    (r"personal use|uso personal|private use|uso privado", "personal use only: not for a game shown to others"),
    (r"\bnc\b|non[- ]?commercial|no comercial", "non-commercial: check that a preview and the game qualify"),
    (r"\bnd\b|no deriv|sin deriv", "no derivatives: cutting it out and outlining it is a derivative"),
    (r"all rights reserved|todos los derechos reservados", "all rights reserved: needs the holder's written permission"),
    (r"cults3d|cults 3d", "Cults3D files are usually sold for personal (printing) use only"),
    (r"sketchfab", "Sketchfab models each carry their own licence: name it exactly (e.g. CC BY 4.0) and credit the author"),
    (r"fan ?art|fanart", "fan art: needs the rights holder's permission as well as the artist's"),
]


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.notes = []

    def error(self, where, text):
        self.errors.append(f"{where}: {text}")

    def warn(self, where, text):
        self.warnings.append(f"{where}: {text}")

    def note(self, where, text):
        self.notes.append(f"{where}: {text}")


def load_manifest(pack, rep):
    path = os.path.join(pack, "manifest.json")
    if not os.path.isfile(path):
        rep.error("manifest.json", f"not found in {pack}")
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        rep.error("manifest.json", f"not valid JSON: {e}")
        return None
    if not isinstance(data, dict) or not isinstance(data.get("slots"), dict):
        rep.error("manifest.json", 'needs an object with "slots": {"<id>": {...}}')
        return None
    return data


def check(pack, strict=False):
    rep = Report()
    data = load_manifest(pack, rep)
    if data is not None:
        for sid, s in sorted(data["slots"].items()):
            check_slot(pack, sid, s, rep)
    for line in rep.notes:
        print("  ok   ", line)
    for line in rep.warnings:
        print("  WARN ", line)
    for line in rep.errors:
        print("  ERROR", line)
    n = len(data["slots"]) if data else 0
    print(f"{n} slots, {len(rep.errors)} errors, {len(rep.warnings)} warnings")
    return 1 if rep.errors or (strict and rep.warnings) else 0


def check_slot(pack, sid, s, rep):
    where = f"slot {sid}"
    if not re.fullmatch(r"[a-z0-9_]+", sid):
        rep.error(where, "the id may only have lower-case letters, digits and _ (it is written in the data as art:<id>)")
    if not isinstance(s, dict):
        rep.error(where, "is not an object")
        return
    if not str(s.get("name", "")).strip():
        rep.error(where, 'has no "name" (shown on its stand-in and in the credits)')
    kind = s.get("kind", "person")
    if kind not in KINDS:
        rep.error(where, f'kind "{kind}" is not one of {", ".join(KINDS)}')
        kind = "person"
    h = s.get("height_m")
    if not isinstance(h, (int, float)):
        rep.warn(where, f'no "height_m": the game uses its kind\'s default')
    else:
        lo, hi = KINDS[kind]
        if not lo <= h <= hi:
            rep.warn(where, f"height_m {h} is unusual for a {kind} ({lo} to {hi} m)")
    if s.get("faces", "right") not in ("right", "left", "front"):
        rep.error(where, 'faces must be "right", "left" or "front"')
    if s.get("forward", "+z") not in FORWARDS:
        rep.error(where, f'forward (the model\'s front) must be one of {", ".join(FORWARDS)}')
    for key in ("length_m", "width_m"):
        v = s.get(key)
        if v is not None and (not isinstance(v, (int, float)) or v <= 0):
            rep.error(where, f"{key} must be a length in metres")
    if kind == "creature" and isinstance(s.get("length_m"), (int, float)) and isinstance(h, (int, float)) and s["length_m"] < h * 0.3:
        rep.warn(where, f"length_m {s['length_m']} is very short for a creature {h} m high")
    portrait = str(s.get("portrait", "") or "")
    if portrait:
        check_file(pack, f"{where} portrait", portrait, kind, rep, main=False, view="portrait")
    file = str(s.get("file", "") or "")
    test = bool(s.get("test", False))
    if not file:
        rep.note(where, "no file yet: the game shows the neutral stand-in")
    else:
        check_file(pack, where, file, kind, rep, main=True, slot=s)
        views = s.get("views", {}) or {}
        if not isinstance(views, dict):
            rep.error(where, '"views" must be an object {"back": ..., "crouch": ..., "down": ...}')
            views = {}
        for v, vf in views.items():
            if v not in VIEWS:
                rep.warn(where, f'unknown view "{v}" (the game uses {", ".join(VIEWS)})')
            elif vf:
                check_file(pack, f"{where} view {v}", str(vf), kind, rep, main=False, view=v)
        if not test:
            check_credit(where, s.get("credit"), rep)
        check_model_extras(pack, where, s, file, kind, rep)
    if test:
        rep.note(where, "a test file: kept out of the game's credits")


def check_credit(where, credit, rep):
    if not isinstance(credit, dict):
        rep.error(where, 'needs a "credit": {"author", "licence", "permission", "source"}')
        return
    for field, why in (("author", "who made it"), ("licence", "the licence it is used under"),
                       ("permission", "the written permission it is shown under (who gave it, when, where it is kept)")):
        if not str(credit.get(field, "")).strip():
            rep.error(where, f'credit.{field} is empty: {why}')
    text = " ".join(str(v) for v in credit.values()).lower()
    for pattern, why in RISKY:
        if re.search(pattern, text):
            rep.warn(where, why)


def check_file(pack, where, file, kind, rep, main, view="", slot=None):
    if os.path.isabs(file) or file.startswith("res://"):
        rep.error(where, f"{file}: give the path relative to the art pack's folder")
        return
    path = os.path.normpath(os.path.join(pack, file))
    if not path.startswith(os.path.normpath(pack) + os.sep):
        rep.error(where, f"{file} is outside the art pack's folder")
        return
    if not os.path.isfile(path):
        rep.error(where, f"{file} is not there")
        return
    ext = os.path.splitext(file)[1].lower()
    if ext == ".png":
        check_png(where, path, file, kind, rep, view)
    elif ext in (".glb", ".gltf"):
        if not main:
            rep.error(where, "views and portraits are drawings (PNG); a model has one file")
        check_model(where, path, file, rep, kind, slot or {})
    elif ext in (".stl", ".obj", ".fbx"):
        rep.error(where, f"{file}: convert it to GLB first (python3 tools/art_pack.py convert {file} out.glb)")
    else:
        rep.error(where, f"{file}: the game reads PNG drawings and GLB/GLTF models")


def check_png(where, path, file, kind, rep, view):
    try:
        from PIL import Image
    except ImportError:
        rep.warn(where, "Pillow is not installed: the PNG is not checked (pip install pillow)")
        return
    try:
        im = Image.open(path)
        im.load()
    except Exception as e:  # noqa: BLE001 - any unreadable file is an error here
        rep.error(where, f"{file} cannot be read: {e}")
        return
    w, h = im.size
    if view == "portrait":
        # the HUD's ID photo: a square (cropped to the middle if not), any background, a few hundred pixels
        if min(w, h) < 256:
            rep.warn(where, f"{file} is small ({w}x{h}): a portrait wants at least 384 px square")
        if max(w, h) > 1.4 * min(w, h):
            rep.warn(where, f"{file} is {w}x{h}: the photo is cut to a square from its middle")
        rep.note(where, f"{file} {w}x{h}, the HUD's photo")
        return
    if im.mode not in ("RGBA", "LA") and not (im.mode == "P" and "transparency" in im.info):
        rep.error(where, f"{file} has no transparency ({im.mode}): export it as a PNG with a transparent background")
        return
    alpha = im.convert("RGBA").getchannel("A")
    long_side = max(w, h)
    if long_side < 512:
        rep.warn(where, f"{file} is small ({w}x{h}): draw it at least 1024 px on its long side")
    if long_side > 4096:
        rep.warn(where, f"{file} is {w}x{h}: 2048 px on the long side is plenty (the game shows it far smaller)")
    box = alpha.point(lambda a: 255 if a > 127 else 0).getbbox()
    if box is None:
        rep.error(where, f"{file} is empty: everything is transparent")
        return
    hist = alpha.histogram()
    transparent = sum(hist[:8]) / (w * h)
    if transparent < 0.05:
        rep.error(where, f"{file} has almost no transparent pixels: the background must be transparent")
    edge = [alpha.getpixel((x, 0)) for x in range(0, w, max(1, w // 64))] + [alpha.getpixel((0, y)) for y in range(0, h, max(1, h // 64))]
    if max(edge) > 127:
        rep.warn(where, f"{file}: the drawing touches the top or left edge of the canvas; leave a margin of a few pixels")
    bw, bh = box[2] - box[0], box[3] - box[1]
    fill = (bw * bh) / (w * h)
    if fill < 0.25:
        rep.warn(where, f"{file}: the drawing fills only {fill:.0%} of the canvas; crop the canvas closer round it")
    if kind == "person" and view in ("", "back") and h - box[3] > 0.06 * h:
        rep.warn(where, f"{file}: the feet are {h - box[3]} px above the bottom of the canvas; the figure stands on the "
                        "bottom of what is drawn, so trim the canvas there")
    semi = sum(hist[16:240]) / max(1, sum(hist[8:]))
    if semi > 0.25:
        rep.warn(where, f"{file}: much of it is half transparent ({semi:.0%}); the cut-out keeps what is over half "
                        "opaque, so soft shadows and glows inside the figure are lost")
    rep.note(where, f"{file} {w}x{h}, drawn {bw}x{bh}")


FINISHES = ("cloth", "chitin", "pbr")
ORIGINS = ("centre", "model")


def check_model_extras(pack, where, s, file, kind, rep):
    """A model slot's own fields: its lighter copy (lod), its clips' names and speeds, its prop, origin and finish."""
    model = os.path.splitext(file)[1].lower() in (".glb", ".gltf")
    extras = [k for k in ("lod", "clips", "clip_speed", "prop", "origin", "finish") if s.get(k)]
    if extras and not model:
        rep.warn(where, f"{', '.join(extras)}: only a model uses these")
        return
    if not model:
        return
    path = os.path.join(pack, file)
    try:
        info = model_info(read_gltf(path)[0])
    except (ValueError, OSError):
        return
    lod = str(s.get("lod", "") or "")
    if lod:
        lod_path = os.path.normpath(os.path.join(pack, lod))
        if not os.path.isfile(lod_path):
            rep.error(where, f"lod {lod} is not there")
        else:
            try:
                low = model_info(read_gltf(lod_path)[0])
            except ValueError as e:
                rep.error(where, f"lod {lod}: {e}")
            else:
                if low["triangles"] >= info["triangles"]:
                    rep.warn(where, f"lod {lod} has {low['triangles']} triangles, no fewer than the model's {info['triangles']}")
                else:
                    rep.note(where, f"lod {lod}: {low['triangles']} triangles (the model {info['triangles']}), drawn while the camera is far")
    clips = s.get("clips", {}) or {}
    if not isinstance(clips, dict):
        rep.error(where, '"clips" must be an object {"idle": "...", "walk": "...", "run": "..."}')
    else:
        for role, name in clips.items():
            if name and name not in info["animations"]:
                rep.error(where, f'clips: "{name}" ({role}) is not one of its animations ({", ".join(info["animations"]) or "none"})')
    speeds = s.get("clip_speed", {}) or {}
    if not isinstance(speeds, dict) or any(not isinstance(v, (int, float)) or v <= 0 for v in speeds.values()):
        rep.error(where, '"clip_speed" must be {"walk": m/s, "run": m/s}, speeds above 0')
    prop = str(s.get("prop", "") or "")
    if prop and prop not in info["meshes"]:
        rep.error(where, f'prop "{prop}" is not a mesh in {file}')
    if s.get("origin", "centre") not in ORIGINS:
        rep.error(where, f'origin must be one of {", ".join(ORIGINS)}')
    if s.get("finish", "") and s.get("finish") not in FINISHES:
        rep.error(where, f'finish must be one of {", ".join(FINISHES)} (or none: its own materials)')


def check_model(where, path, file, rep, kind="person", slot=None):
    slot = slot or {}
    size = os.path.getsize(path)
    if size > 20 * 1024 * 1024:
        rep.warn(where, f"{file} is {size // (1024 * 1024)} MB: a web build wants models of a few MB")
    try:
        gltf, _ = read_gltf(path)
    except ValueError as e:
        rep.error(where, f"{file}: {e}")
        return
    if path.lower().endswith(".gltf"):
        for buf in gltf.get("buffers", []):
            uri = buf.get("uri", "")
            if uri and not uri.startswith("data:") and not os.path.isfile(os.path.join(os.path.dirname(path), uri)):
                rep.error(where, f"{file} needs {uri} beside it")
    info = model_info(gltf)
    tris = info["triangles"]
    budget = BUDGET.get(kind, BUDGET["person"])
    if tris > budget:
        ratio = budget / tris
        how = (f"decimate it to about {budget} triangles (ratio {ratio:.3f}): python3 tools/art_pack.py decimate {file} out.glb "
               f"--faces {budget}, or in Blender a Decimate modifier (Collapse, ratio {ratio:.3f}) before exporting")
        if tris > budget * ERROR_OVER:
            rep.error(where, f"{file} has {tris} triangles, far over the {budget} a {kind} may have: {how}")
        else:
            rep.warn(where, f"{file} has {tris} triangles, over the {budget} a {kind} may have: {how}")
    lo, hi = info["min"], info["max"]
    dims = [hi[k] - lo[k] for k in range(3)] if lo is not None else [0.0, 0.0, 0.0]
    if lo is None:
        rep.error(where, f"{file} has no mesh with positions in it")
        return
    if dims[1] <= 0.0:
        rep.error(where, f"{file} is flat: nothing stands up in it")
    else:
        if kind == "person" and dims[2] > dims[1] * 1.2 and dims[2] >= dims[0]:
            rep.warn(where, f"{file} is longer front to back ({dims[2]:.2f}) than it is high ({dims[1]:.2f}): exported with Z up? "
                            "Export with +Y up (Blender's glTF exporter does by default)")
        if kind == "creature" and dims[0] > dims[2] * 1.3 and slot.get("forward", "+z") in ("+z", "-z"):
            rep.warn(where, f"{file} lies along X ({dims[0]:.2f} long, {dims[2]:.2f} deep): if its head is that way, set "
                            '"forward": "+x" (or "-x") so that it walks head first')
        height = slot.get("height_m")
        if isinstance(height, (int, float)) and height > 0:
            scale = height / dims[1]
            rep.note(where, f"{file} {dims[0]:.2f} x {dims[1]:.2f} x {dims[2]:.2f} as modelled: shown at {scale:.3g} times, "
                            f"{dims[0] * scale:.2f} x {height:.2f} x {dims[2] * scale:.2f} m")
            length = slot.get("length_m")
            if isinstance(length, (int, float)) and length > 0:
                along = dims[0] if slot.get("forward", "+z") in ("+x", "-x") else dims[2]
                if abs(along * scale - length) > 0.25 * length:
                    rep.warn(where, f"{file} comes out {along * scale:.2f} m long at {height} m high, not the {length} m of "
                                    "length_m: the game keeps the height; check the slot or the model's proportions")
    names = [str(a) for a in info["animations"]]
    used = [n for n in names if any(k in n.lower() for k in ANIMS)]
    legs = [n for n in info["meshes"] + info.get("nodes", []) if str(n).endswith("_coxa")]
    if info["skins"] and not names and not legs:
        rep.warn(where, f"{file} has a skeleton but no animations: the game moves it as a static model")
    if names and not used:
        rep.warn(where, f"{file} has animations ({', '.join(names)}) but none the game knows by name "
                        f"({', '.join(ANIMS)}); with one only, it is played as the walk")
    motion = (f"animations {', '.join(names)}" if names else f"its {len(legs)} legs rigged (rig-creature): the game walks them" if legs
              else "static: the game gives it a step and a sway" if kind == "person"
              else "static: the game gives it a crawl" if kind == "creature" else "static")
    rep.note(where, f"{file} {size // 1024} KB, {tris} triangles, {'a skeleton, ' if info['skins'] else ''}{motion}")


def read_gltf(path):
    """The glTF JSON of a .glb or .gltf file, and the GLB's binary chunk (b"" for a .gltf)."""
    if path.lower().endswith(".glb"):
        with open(path, "rb") as f:
            data = f.read()
        if len(data) < 20 or data[:4] != b"glTF":
            raise ValueError("not a binary glTF (GLB) file")
        version = struct.unpack("<I", data[4:8])[0]
        if version != 2:
            raise ValueError(f"glTF version {version}; the game reads glTF 2")
        length, kind = struct.unpack("<II", data[12:20])
        if kind != 0x4E4F534A:
            raise ValueError("the GLB's first chunk is not its JSON")
        gltf = json.loads(data[20:20 + length].decode("utf-8"))
        rest = data[20 + length:]
        binary = b""
        if len(rest) >= 8:
            blen, bkind = struct.unpack("<II", rest[:8])
            if bkind == 0x004E4942:
                binary = rest[8:8 + blen]
        return gltf, binary
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f), b""
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise ValueError(f"not a valid .gltf (JSON) file: {e}") from e


def _node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[0][0] * sx, r[0][1] * sy, r[0][2] * sz, t[0]], [r[1][0] * sx, r[1][1] * sy, r[1][2] * sz, t[1]],
            [r[2][0] * sx, r[2][1] * sy, r[2][2] * sz, t[2]], [0, 0, 0, 1]]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def model_info(gltf):
    """Triangles (every mesh as often as nodes use it), the bounds of everything as placed by its nodes (a skinned mesh
    as bound), the skins and the animations' names."""
    accessors = gltf.get("accessors", [])
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    out = {"triangles": 0, "min": None, "max": None, "skins": len(gltf.get("skins", [])),
           "animations": [a.get("name", f"animation {i}") for i, a in enumerate(gltf.get("animations", []))],
           "meshes": [n.get("name", "") for n in nodes if "mesh" in n] + [m.get("name", "") for m in meshes],
           "nodes": [n.get("name", "") for n in nodes]}
    children = {c for n in nodes for c in n.get("children", [])}
    scenes = gltf.get("scenes", [])
    roots = scenes[gltf.get("scene", 0)].get("nodes", []) if scenes else [i for i in range(len(nodes)) if i not in children]
    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    stack = [(i, ident) for i in roots]
    seen = 0
    while stack and seen < 100000:
        seen += 1
        i, parent = stack.pop()
        node = nodes[i]
        world = _mul(parent, _node_matrix(node))
        if "mesh" in node and node["mesh"] < len(meshes):
            for prim in meshes[node["mesh"]].get("primitives", []):
                mode = prim.get("mode", 4)
                pos = prim.get("attributes", {}).get("POSITION")
                count = accessors[prim["indices"]]["count"] if "indices" in prim else (accessors[pos]["count"] if pos is not None else 0)
                out["triangles"] += count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
                if pos is None or "min" not in accessors[pos]:
                    continue
                a, b = accessors[pos]["min"], accessors[pos]["max"]
                use = ident if "skin" in node else world
                for cx in (a[0], b[0]):
                    for cy in (a[1], b[1]):
                        for cz in (a[2], b[2]):
                            p = [sum(use[r][k] * v for k, v in enumerate((cx, cy, cz, 1.0))) for r in range(3)]
                            out["min"] = p if out["min"] is None else [min(out["min"][k], p[k]) for k in range(3)]
                            out["max"] = p if out["max"] is None else [max(out["max"][k], p[k]) for k in range(3)]
        for c in node.get("children", []):
            stack.append((c, world))
    return out


# ------------------------------------------------------------------------------------------------ convert
def convert(src, dst):
    if not dst.lower().endswith(".glb"):
        sys.exit(f"{dst}: the converted model is written as GLB (name it .glb)")
    ext = os.path.splitext(src)[1].lower()
    if not os.path.isfile(src):
        sys.exit(f"{src} is not there")
    if ext == ".fbx":
        return convert_fbx(src, dst)
    try:
        import trimesh
    except ImportError:
        sys.exit("trimesh is needed to convert models: pip install trimesh")
    scene = trimesh.load(src, force="scene")
    if ext == ".stl":
        # STL has no units and is usually in millimetres, Z up: stand it up, Y up, in metres-ish (the game rescales
        # it to the slot's height anyway)
        scene.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
    data = scene.export(file_type="glb")
    with open(dst, "wb") as f:
        f.write(data)
    print(f"{src} -> {dst} ({len(data) // 1024} KB)")
    return 0


def convert_fbx(src, dst):
    blender = shutil.which("blender")
    if blender:
        expr = ("import bpy,sys; bpy.ops.wm.read_factory_settings(use_empty=True); "
                f"bpy.ops.import_scene.fbx(filepath={src!r}); bpy.ops.export_scene.gltf(filepath={dst!r}, export_format='GLB')")
        subprocess.run([blender, "-b", "--python-expr", expr], check=True)
        print(f"{src} -> {dst} (Blender)")
        return 0
    assimp = shutil.which("assimp")
    if assimp:
        subprocess.run([assimp, "export", src, dst, "-fglb2"], check=True)
        print(f"{src} -> {dst} (assimp)")
        return 0
    sys.exit("FBX needs Blender (blender on the PATH) or the assimp tool to convert; or export GLB from the program "
             "it was made in")


def decimate(src, dst, faces):
    """A model brought down to about `faces` triangles: in Blender if it is on the PATH (a Decimate modifier on every
    mesh, skeleton and animations kept), else with trimesh and fast_simplification (meshes only: a rig is lost)."""
    if not dst.lower().endswith(".glb"):
        sys.exit(f"{dst}: the decimated model is written as GLB (name it .glb)")
    if not os.path.isfile(src):
        sys.exit(f"{src} is not there")
    total = model_info(read_gltf(src)[0])["triangles"] if src.lower().endswith((".glb", ".gltf")) else 0
    if total and total <= faces:
        print(f"{src} has {total} triangles, within {faces}: copied as it is")
        shutil.copyfile(src, dst)
        return 0
    blender = shutil.which("blender")
    if blender:
        ratio = faces / total if total else 0.1
        expr = ("import bpy; bpy.ops.wm.read_factory_settings(use_empty=True); "
                f"bpy.ops.import_scene.gltf(filepath={os.path.abspath(src)!r}); "
                "obs=[o for o in bpy.data.objects if o.type=='MESH']\n"
                "for o in obs:\n"
                f" m=o.modifiers.new('decimate','DECIMATE'); m.ratio={ratio!r}; bpy.context.view_layer.objects.active=o; "
                "bpy.ops.object.modifier_apply(modifier=m.name)\n"
                f"bpy.ops.export_scene.gltf(filepath={os.path.abspath(dst)!r}, export_format='GLB')")
        subprocess.run([blender, "-b", "--python-expr", expr], check=True)
        print(f"{src} -> {dst} (Blender, ratio {ratio:.3f})")
        return 0
    try:
        import trimesh
        import fast_simplification  # noqa: F401 - trimesh's decimation needs it
    except ImportError:
        sys.exit("decimate needs Blender on the PATH, or: pip install trimesh fast_simplification. Or in Blender by hand: "
                 f"a Decimate modifier (Collapse) with ratio {faces / total if total else 0.1:.3f} on each mesh, then "
                 "File > Export > glTF 2.0 (.glb)")
    scene = trimesh.load(src, force="scene")
    count = sum(len(g.faces) for g in scene.geometry.values()) or 1
    ratio = min(1.0, faces / count)
    for name, g in list(scene.geometry.items()):
        low = g.simplify_quadric_decimation(face_count=max(4, int(len(g.faces) * ratio)))
        # keep its material (a mesh without UVs keeps its colours, roughness and metal) and smooth normals
        material = getattr(g.visual, "material", None)
        if material is not None:
            low.visual = trimesh.visual.TextureVisuals(material=material)
        low.fix_normals()
        scene.geometry[name] = low
    data = scene.export(file_type="glb", include_normals=True)
    with open(dst, "wb") as f:
        f.write(data)
    print(f"{src} -> {dst} ({count} -> about {int(count * ratio)} triangles; a skeleton or animations are not kept this way)")
    return 0


def rig_creature(src, dst, lod, lod_faces, forward):
    """A creature sculpt in one piece rigged for its legs (tools/creature_rig.py): its shape kept exactly, a skeleton for
    its body, shell, head and each limb, skin weights blended at every joint, and its occlusion, convexity and how much
    of it is leg or underside baked into its vertex colours; with --lod, a lighter copy rigged the same."""
    if not os.path.isfile(src):
        sys.exit(f"{src} is not there")
    try:
        import creature_rig
    except ImportError as e:
        sys.exit(f"rig-creature needs numpy, scipy and trimesh (and fast_simplification for --lod): {e}")
    axis = {"+z": (0.0, 0.0, 1.0), "-z": (0.0, 0.0, -1.0), "+x": (1.0, 0.0, 0.0), "-x": (-1.0, 0.0, 0.0)}[forward]
    rigged = creature_rig.rig(src, forward=axis)
    gen = "tools/art_pack.py rig-creature"
    creature_rig.write_glb(dst, rigged, rigged["v"], rigged["n"], rigged["f"], rigged["joints"], rigged["weights"], rigged["colours"], gen)
    print(f"{src} -> {dst}: {len(rigged['f'])} triangles, {len(rigged['bones'])} bones")
    for name, limb in sorted(rigged["report"].items()):
        print(f"  {name}: hip {limb['hip']}, knee {limb['knee']}, ankle {limb['ankle']}, foot {limb['tip']} ({limb['vertices']} vertices)")
    if lod:
        v, n, f = creature_rig.lighter(rigged["v"], rigged["n"], rigged["f"], lod_faces)
        joints, weights, colours = creature_rig.transfer(rigged, v, n)
        creature_rig.write_glb(lod, rigged, v, n, f, joints, weights, colours, gen + " (lighter copy)")
        print(f"  lighter copy -> {lod}: {len(f)} triangles, the same bones")
    return 0


# ------------------------------------------------------------------------------------------------ refine-person
# Juan Salvo: the friends' model as they made it (kept untouched as the source) and what is made from it for the game.
PERSON_SOURCE = os.path.normpath(os.path.join(ROOT, "art", "juan_salvo", "source", "snowfall_survivor.glb"))
PERSON_OUT = os.path.normpath(os.path.join(PACK, "juan_salvo", "juan_salvo.glb"))


def refine_person(src, dst, lod, atlas_out):
    """A low-poly rigged person (the friends' Juan Salvo) brought up to the cast's fidelity without changing what it is
    (tools/person_refine.py): its parts welded and read back as the polygons they were modelled as, subdivided (limbs,
    hood and coat rounded; hems, soles, the visor and the face plate kept sharp; straps, backpack, boots, respirator and
    rifle bevelled; the smallest details left as they are), its skin weights and texture charts carried down exactly,
    its normals smooth where it was rounded; its occlusion, mud, wear and folds baked into its vertex colours; its atlas
    redrawn four times as large with the grain of each swatch's material and that material named in its alpha; and,
    with --lod, a lighter copy for far off (rounded once, one mesh, its rest place in TEXCOORD_2 / TEXCOORD_3)."""
    if not os.path.isfile(src):
        sys.exit(f"{src} is not there")
    try:
        import person_refine
    except ImportError as e:
        sys.exit(f"refine-person needs numpy, scipy, trimesh, Pillow and opencv-python: {e}")
    print(f"{src} -> {dst}")
    person_refine.refine(src, dst, lod, atlas_out)
    return 0


# ------------------------------------------------------------------------------------------------ test models
class Gltf:
    """Just enough of a glTF 2.0 writer for the neutral test models: meshes, nodes, a skin, animations."""

    def __init__(self):
        self.doc = {"asset": {"version": "2.0", "generator": "tools/art_pack.py test-models"}, "scene": 0,
                    "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [], "accessors": [],
                    "bufferViews": [], "buffers": []}
        self.bin = bytearray()

    def _view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.bin.extend(data)
        self.doc["bufferViews"].append(view)
        return len(self.doc["bufferViews"]) - 1

    def accessor(self, values, kind, comp="f", target=None, bounds=False):
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
        flat = [v for item in values for v in (item if isinstance(item, (list, tuple)) else [item])]
        fmt, ctype = {"f": ("f", 5126), "H": ("H", 5123), "I": ("I", 5125)}[comp]
        data = struct.pack("<%d%s" % (len(flat), fmt), *flat)
        acc = {"bufferView": self._view(data, target), "componentType": ctype, "count": len(flat) // width, "type": kind}
        if bounds:
            acc["min"] = [min(flat[k::width]) for k in range(width)]
            acc["max"] = [max(flat[k::width]) for k in range(width)]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def material(self, name, rgba):
        self.doc["materials"].append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": rgba, "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        return len(self.doc["materials"]) - 1

    def mesh(self, name, parts):
        """parts: [(positions, normals, triangles, material, joints or None, weights or None)]"""
        prims = []
        for pos, nor, tris, mat, joints, weights in parts:
            attrs = {"POSITION": self.accessor(pos, "VEC3", target=34962, bounds=True), "NORMAL": self.accessor(nor, "VEC3", target=34962)}
            if joints is not None:
                attrs["JOINTS_0"] = self.accessor(joints, "VEC4", "H", target=34962)
                attrs["WEIGHTS_0"] = self.accessor(weights, "VEC4", target=34962)
            prims.append({"attributes": attrs, "indices": self.accessor([i for t in tris for i in t], "SCALAR", "I", target=34963), "material": mat})
        self.doc["meshes"].append({"name": name, "primitives": prims})
        return len(self.doc["meshes"]) - 1

    def node(self, root=False, **spec):
        self.doc["nodes"].append(spec)
        index = len(self.doc["nodes"]) - 1
        if root:
            self.doc["scenes"][0]["nodes"].append(index)
        return index

    def save(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.doc["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.doc, separators=(",", ":")).encode("utf-8")
        js += b" " * ((4 - len(js) % 4) % 4)
        body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)
        print(" ", os.path.relpath(path, ROOT), f"{len(body) // 1024 + 1} KB")


def box_part(lo, hi):
    """A box from corner lo to corner hi: 24 vertices (flat normals), 12 triangles."""
    pos, nor, tris = [], [], []
    for axis in range(3):
        for sign in (-1, 1):
            n = [0.0, 0.0, 0.0]
            n[axis] = float(sign)
            u, v = [(1, 2), (2, 0), (0, 1)][axis]
            base = len(pos)
            for a, b in ((0, 0), (1, 0), (1, 1), (0, 1)):
                p = [0.0, 0.0, 0.0]
                p[axis] = hi[axis] if sign > 0 else lo[axis]
                p[u] = hi[u] if a else lo[u]
                p[v] = hi[v] if b else lo[v]
                pos.append(p)
                nor.append(n)
            # wound counter-clockwise seen from outside
            tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)] if sign > 0 else [(base, base + 2, base + 1), (base, base + 3, base + 2)]
    return pos, nor, tris


def capsule_part(radius, height, rings=10, sides=16, y0=0.0, x0=0.0):
    """A capsule standing on y0 (height including its rounded ends), its axis at x0."""
    pos, nor = [], []
    cyl = max(0.0, height - 2 * radius)
    rows = []
    for i in range(rings + 1):
        a = -math.pi / 2 + math.pi * i / rings
        r = math.cos(a) * radius
        y = math.sin(a) * radius + (radius if i <= rings // 2 else radius + cyl)
        rows.append((r, y, a))
        if i == rings // 2:
            rows.append((r, y + cyl, a))
    for r, y, a in rows:
        for k in range(sides):
            t = 2 * math.pi * k / sides
            pos.append([x0 + r * math.cos(t), y0 + y, r * math.sin(t)])
            nor.append([math.cos(a) * math.cos(t), math.sin(a), math.cos(a) * math.sin(t)])
    tris = []
    for i in range(len(rows) - 1):
        for k in range(sides):
            a, b = i * sides + k, i * sides + (k + 1) % sides
            c, d = a + sides, b + sides
            tris += [(a, c, b), (b, c, d)]
    return pos, nor, tris


def test_models(pack):
    """Neutral models for testing the model pipeline, made here from plain shapes (nothing from any comic or film): a
    static capsule modelled in centimetres, standing off its origin (the game must scale it, ground it and centre it);
    a static long block lying along X with a small block on its +X end for a front ("forward": "+x"); and a post with a
    two-bone skeleton and its own "Idle" and "Walk" animations."""
    out = os.path.join(pack, "test")
    os.makedirs(out, exist_ok=True)
    grey = [0.62, 0.62, 0.6, 1.0]
    dark = [0.3, 0.3, 0.29, 1.0]
    # the capsule: 170 units tall (centimetres), its foot 30 above the origin, 50 to the side; a small box on its front
    g = Gltf()
    body, front = g.material("grey", grey), g.material("dark", dark)
    cap = capsule_part(24.0, 170.0, y0=30.0, x0=50.0)
    nose = box_part([44.0, 150.0, 20.0], [56.0, 160.0, 30.0])
    g.node(root=True, name="Capsule", mesh=g.mesh("capsule", [(*cap, body, None, None), (*nose, front, None, None)]))
    g.save(os.path.join(out, "capsule.glb"))
    # the long block: 4 x 1.8 x 1.6 lying along X, its front (a smaller block) at +X
    g = Gltf()
    body, front = g.material("grey", grey), g.material("dark", dark)
    block = box_part([-2.0, 0.0, -0.8], [2.0, 1.8, 0.8])
    nose = box_part([2.0, 0.9, -0.3], [2.3, 1.4, 0.3])
    g.node(root=True, name="Block", mesh=g.mesh("block", [(*block, body, None, None), (*nose, front, None, None)]))
    g.save(os.path.join(out, "crawler.glb"))
    # the rigged post: 1.8 tall, two bones (the lower half on the root, the upper on the top), "Idle" and "Walk"
    g = Gltf()
    body = g.material("grey", grey)
    pos, nor, tris = capsule_part(0.22, 1.8, rings=12, sides=12)
    joints = [[0 if p[1] < 0.9 else 1, 0, 0, 0] for p in pos]
    weights = [[1.0, 0.0, 0.0, 0.0] for _ in pos]
    mesh = g.mesh("post", [(pos, nor, tris, body, joints, weights)])
    top = g.node(name="top", translation=[0.0, 0.9, 0.0])
    root = g.node(name="root", children=[top])
    ibm = g.accessor([[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -0.9, 0, 1]], "MAT4")
    g.doc["skins"] = [{"joints": [root, top], "inverseBindMatrices": ibm, "skeleton": root}]
    g.node(root=True, name="Post", mesh=mesh, skin=0)
    g.doc["scenes"][0]["nodes"].append(root)
    def turn(deg):
        a = math.radians(deg) / 2
        return [0.0, 0.0, math.sin(a), math.cos(a)]
    g.doc["animations"] = []
    for name, keys in (("Idle", [(0.0, 0.0), (1.0, 2.0), (2.0, 0.0)]), ("Walk", [(0.0, -14.0), (0.5, 14.0), (1.0, -14.0)])):
        times = g.accessor([t for t, _ in keys], "SCALAR", bounds=True)
        values = g.accessor([turn(d) for _, d in keys], "VEC4")
        g.doc["animations"].append({"name": name, "samplers": [{"input": times, "output": values, "interpolation": "LINEAR"}],
                                    "channels": [{"sampler": 0, "target": {"node": top, "path": "rotation"}}]})
    g.save(os.path.join(out, "rigged.glb"))
    print("made in", out)


# ------------------------------------------------------------------------------------------------ test drawings
def test_art(pack):
    """Neutral drawings for testing the pipeline, made here from plain shapes: a generic man in a long coat and a flat
    cap (front, back, crouched, lying) and a large round blob of a creature. Nothing from any comic or film."""
    from PIL import Image, ImageDraw, ImageFilter
    out = os.path.join(pack, "test")
    os.makedirs(out, exist_ok=True)
    walker = draw_walker(Image, ImageDraw, back=False)
    save(walker, os.path.join(out, "walker.png"), Image)
    save(draw_walker(Image, ImageDraw, back=True), os.path.join(out, "walker_back.png"), Image)
    save(draw_crouch(Image, ImageDraw), os.path.join(out, "walker_crouch.png"), Image)
    save(walker.rotate(90, expand=True), os.path.join(out, "walker_down.png"), Image)
    save(draw_blob(Image, ImageDraw), os.path.join(out, "blob.png"), Image)
    print("drawn in", out)
    stand = os.path.join(pack, "stand_in")
    os.makedirs(stand, exist_ok=True)
    draw_stand_ins(Image, ImageDraw, stand)
    print("drawn in", stand)


def draw_stand_ins(Image, ImageDraw, out):
    """The neutral stand-ins the game shows where licensed art is still to come (art_pack.gd): a plain grey artist's
    mannequin (head, trunk, arms, legs; no face, no clothes, nothing worn) and a plain grey rounded block. No outline:
    the card draws its own."""
    from PIL import ImageFilter
    k = 4
    W, H = 240, 640
    img = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    grey = (156, 156, 154, 255)
    def seg(a, b, ra, rb):
        # a rounded tapered limb from a to b
        steps = 24
        for i in range(steps + 1):
            t = i / steps
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            r = ra + (rb - ra) * t
            d.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], fill=grey)
    cx = W / 2
    d.ellipse([(cx - 30) * k, 10 * k, (cx + 30) * k, 88 * k], fill=grey)        # head
    seg((cx, 84), (cx, 104), 13, 14)                                               # neck
    seg((cx, 128), (cx, 300), 50, 40)                                              # trunk
    seg((cx, 300), (cx, 338), 42, 40)                                              # pelvis
    for side in (-1, 1):
        seg((cx + side * 64, 132), (cx + side * 74, 236), 15, 12)                  # upper arm
        seg((cx + side * 74, 240), (cx + side * 78, 336), 12, 10)                  # forearm
        d.ellipse([(cx + side * 78 - 11) * k, 330 * k, (cx + side * 78 + 11) * k, 362 * k], fill=grey)
        seg((cx + side * 26, 344), (cx + side * 26, 474), 19, 14)                  # thigh
        seg((cx + side * 26, 478), (cx + side * 27, 606), 14, 11)                  # shin
        d.ellipse([(cx + side * 25 - 14) * k, 598 * k, (cx + side * 25 + 18) * k, 630 * k], fill=grey)
    # a soft shade down one side, so the card reads as a shape
    shade = Image.new("L", img.size, 0)
    ImageDraw.Draw(shade).rectangle([cx * k, 0, W * k, H * k], fill=60)
    shade = shade.filter(ImageFilter.GaussianBlur(40 * k))
    dark = Image.new("RGBA", img.size, (120, 120, 118, 255))
    img = Image.composite(dark, img, Image.composite(shade, Image.new("L", img.size, 0), img.getchannel("A")))
    img = img.resize((W, H), Image.LANCZOS)
    img.save(os.path.join(out, "person.png"), optimize=True)
    print(" ", os.path.relpath(os.path.join(out, "person.png"), ROOT), img.size)
    W, H = 400, 500
    img = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([8 * k, 8 * k, (W - 8) * k, (H - 8) * k], radius=56 * k, fill=(150, 150, 148, 255))
    img = img.resize((W, H), Image.LANCZOS)
    img.save(os.path.join(out, "block.png"), optimize=True)
    print(" ", os.path.relpath(os.path.join(out, "block.png"), ROOT), img.size)


SS = 2  # supersampling
INKC = (18, 16, 15, 255)
COAT = (118, 116, 110, 255)
COAT_DARK = (84, 82, 78, 255)
TROUSERS = (58, 56, 54, 255)
SKIN = (228, 222, 210, 255)
CAP = (48, 46, 44, 255)


def save(img, path, Image):
    small = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
    small.save(path, optimize=True)
    print(" ", os.path.relpath(path, ROOT), small.size)


def poly(d, pts, fill, width):
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)
    d.line([(x * SS, y * SS) for x, y in pts + [pts[0]]], fill=INKC, width=width * SS, joint="curve")


def ell(d, box, fill, width):
    d.ellipse([v * SS for v in box], fill=fill, outline=INKC, width=width * SS)


def hatch(img, mask_poly, Image, ImageDraw, spacing=14, width=3, angle=1.0):
    """Diagonal ink hatching on the shadow side: inside a polygon, and only where something is drawn already."""
    from PIL import ImageChops
    w, h = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for x in range(-h, w, spacing * SS):
        ld.line([(x, 0), (x + h * angle, h)], fill=INKC, width=width * SS)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon([(x * SS, y * SS) for x, y in mask_poly], fill=255)
    mask = ImageChops.multiply(mask, img.getchannel("A").point(lambda a: 255 if a > 200 else 0))
    img.alpha_composite(Image.composite(layer, Image.new("RGBA", img.size, (0, 0, 0, 0)), mask))


def draw_walker(Image, ImageDraw, back):
    """A man in a long coat and a flat cap, three-quarters to the right (or from behind), 512 x 1280."""
    W, H = 512, 1280
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = 9
    # legs and shoes
    poly(d, [(205, 880), (255, 880), (250, 1215), (212, 1215)], TROUSERS, lw)
    poly(d, [(268, 880), (318, 880), (322, 1205), (282, 1205)], TROUSERS, lw)
    ell(d, (192, 1196, 268, 1246), INKC, lw)
    ell(d, (270, 1186, 352, 1236), INKC, lw)
    # back arm
    poly(d, [(150, 300), (196, 300), (182, 640), (140, 640)], COAT_DARK, lw)
    ell(d, (138, 628, 184, 690), SKIN if not back else SKIN, lw)
    # the coat: shoulders to below the knee, a little flared
    coat = [(160, 268), (352, 262), (380, 600), (402, 905), (126, 912), (146, 600)]
    poly(d, coat, COAT, lw)
    if not back:
        # lapels and a row of buttons, the belt
        d.line([(x * SS, y * SS) for x, y in [(282, 270), (300, 420), (290, 905)]], fill=INKC, width=6 * SS)
        d.line([(x * SS, y * SS) for x, y in [(282, 270), (250, 360), (300, 420)]], fill=INKC, width=6 * SS)
        for y in (460, 560, 660):
            ell(d, (296, y, 314, y + 18), INKC, 2)
        d.line([(x * SS, y * SS) for x, y in [(140, 600), (384, 596)]], fill=INKC, width=8 * SS)
    else:
        # the back seam and the vent
        d.line([(x * SS, y * SS) for x, y in [(258, 290), (262, 905)]], fill=INKC, width=5 * SS)
        d.line([(x * SS, y * SS) for x, y in [(140, 600), (384, 596)]], fill=INKC, width=8 * SS)
    hatch(img, [(160, 290), (205, 290), (196, 905), (130, 905), (148, 600)], Image, ImageDraw)
    # the front arm, swinging a little forward
    poly(d, [(320, 290), (372, 300), (410, 640), (362, 650)], COAT, lw)
    ell(d, (360, 630, 414, 694), SKIN, lw)
    # collar, neck and head
    poly(d, [(196, 262), (322, 258), (316, 300), (204, 304)], COAT_DARK, lw)
    ell(d, (196, 110, 318, 262), SKIN if not back else (70, 66, 62, 255), lw)
    if not back:
        # nose, an eye, an ear: three strokes
        d.line([(x * SS, y * SS) for x, y in [(312, 178), (330, 206), (314, 212)]], fill=INKC, width=6 * SS, joint="curve")
        ell(d, (282, 172, 294, 184), INKC, 2)
        ell(d, (220, 168, 246, 206), SKIN, 5)
    # the flat cap with its brim to the right (to the back from behind)
    poly(d, [(186, 150), (218, 96), (300, 86), (330, 118), (336, 146)], CAP, lw)
    if not back:
        poly(d, [(296, 140), (362, 132), (366, 152), (300, 158)], CAP, lw)
    return img


def draw_crouch(Image, ImageDraw):
    """The same man crouched, knees bent, the coat bunched: 560 x 920."""
    W, H = 560, 920
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = 9
    poly(d, [(170, 640), (300, 640), (330, 860), (200, 870)], TROUSERS, lw)
    poly(d, [(300, 600), (430, 640), (420, 860), (330, 860)], TROUSERS, lw)
    ell(d, (180, 850, 262, 900), INKC, lw)
    ell(d, (380, 846, 470, 896), INKC, lw)
    coat = [(150, 230), (350, 210), (420, 470), (440, 700), (130, 720), (140, 460)]
    poly(d, coat, COAT, lw)
    d.line([(x * SS, y * SS) for x, y in [(140, 470), (424, 470)]], fill=INKC, width=8 * SS)
    hatch(img, [(150, 250), (200, 250), (190, 715), (132, 715), (142, 460)], Image, ImageDraw)
    poly(d, [(330, 250), (386, 262), (440, 520), (392, 532)], COAT, lw)
    ell(d, (392, 510, 446, 574), SKIN, lw)
    poly(d, [(200, 220), (322, 212), (318, 252), (206, 258)], COAT_DARK, lw)
    ell(d, (214, 70, 336, 222), SKIN, lw)
    d.line([(x * SS, y * SS) for x, y in [(330, 138), (348, 166), (332, 172)]], fill=INKC, width=6 * SS, joint="curve")
    ell(d, (298, 132, 310, 144), INKC, 2)
    poly(d, [(204, 110), (236, 56), (318, 46), (348, 78), (354, 106)], CAP, lw)
    poly(d, [(314, 100), (380, 92), (384, 112), (318, 118)], CAP, lw)
    return img


def draw_blob(Image, ImageDraw):
    """A large round blob of a creature, friendly and plain: a lumpy dome, two dot eyes, 1200 x 1000."""
    W, H = 1200, 1000
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(96):
        t = i / 96 * math.tau
        if math.sin(t) > 0.02:
            # the flat-ish bottom, with a few drips
            r_x = 540
            x = 600 + math.cos(t) * r_x
            y = 940 + math.sin(t) * 40 + (18 if (i % 9 == 0) else 0)
        else:
            lump = 1.0 + 0.045 * math.sin(t * 7) + 0.03 * math.sin(t * 13 + 1)
            x = 600 + math.cos(t) * 540 * lump
            y = 940 + math.sin(t) * 880 * lump
        pts.append((x, y))
    poly(d, pts, (150, 148, 142, 255), 14)
    hatch(img, [(40, 960), (90, 520), (250, 220), (400, 110), (400, 960)], Image, ImageDraw, spacing=22, width=5)
    # the outline again, over the hatching
    d.line([(x * SS, y * SS) for x, y in pts + [pts[0]]], fill=INKC, width=14 * SS, joint="curve")
    for cx in (520, 720):
        ell(d, (cx - 58, 360, cx + 58, 476), (238, 234, 224, 255), 10)
        ell(d, (cx - 18, 400, cx + 22, 448), INKC, 2)
    d.arc([v * SS for v in (500, 520, 740, 640)], 20, 160, fill=INKC, width=10 * SS)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="check the manifest and its files")
    c.add_argument("--pack", default=PACK, help="the art pack's folder (default godot/art_pack)")
    c.add_argument("--strict", action="store_true", help="warnings count as errors")
    v = sub.add_parser("convert", help="convert STL/OBJ/FBX to GLB")
    v.add_argument("src")
    v.add_argument("dst")
    d = sub.add_parser("decimate", help="bring a model down to a budget of triangles")
    d.add_argument("src")
    d.add_argument("dst")
    d.add_argument("--faces", type=int, default=BUDGET["person"], help="triangles to keep (default %(default)s)")
    r = sub.add_parser("rig-creature", help="give a one-piece creature sculpt a skeleton for its legs, skin weights and baked "
                                            "occlusion and convexity (tools/creature_rig.py); and its lighter copy")
    r.add_argument("src")
    r.add_argument("dst")
    r.add_argument("--lod", help="also write a lighter copy of it here, rigged the same")
    r.add_argument("--lod-faces", type=int, default=13500, help="triangles in the lighter copy (default %(default)s)")
    r.add_argument("--forward", default="-z", choices=FORWARDS, help="the sculpt's front (default %(default)s)")
    rp = sub.add_parser("refine-person", help="round a low-poly rigged person, redraw its atlas and bake its occlusion, mud, wear "
                                              "and folds (tools/person_refine.py); and its lighter copy")
    rp.add_argument("src", nargs="?", default=PERSON_SOURCE, help="the model as its makers made it (default: Juan Salvo's, art/juan_salvo/source)")
    rp.add_argument("dst", nargs="?", default=PERSON_OUT, help="the refined model (default %(default)s)")
    rp.add_argument("--lod", default="", help="also write a lighter copy here (rounded once, one mesh; the game switches to a lighter copy for creatures only)")
    rp.add_argument("--atlas", default="", help="also save the redrawn atlas here as a PNG, to look at")
    t = sub.add_parser("test-art", help="draw the neutral test drawings into art_pack/test/")
    t.add_argument("--pack", default=PACK)
    tm = sub.add_parser("test-models", help="make the neutral test models art_pack/test/*.glb")
    tm.add_argument("--pack", default=PACK)
    a = ap.parse_args()
    if a.cmd == "check":
        sys.exit(check(os.path.abspath(a.pack), a.strict))
    if a.cmd == "convert":
        sys.exit(convert(a.src, a.dst))
    if a.cmd == "decimate":
        sys.exit(decimate(a.src, a.dst, a.faces))
    if a.cmd == "rig-creature":
        sys.exit(rig_creature(a.src, a.dst, a.lod, a.lod_faces, a.forward))
    if a.cmd == "refine-person":
        sys.exit(refine_person(a.src, a.dst, a.lod or None, a.atlas or None))
    if a.cmd == "test-art":
        test_art(os.path.abspath(a.pack))
    if a.cmd == "test-models":
        test_models(os.path.abspath(a.pack))


if __name__ == "__main__":
    main()
