#!/usr/bin/env python3
"""Dev-only: what is in a GLB before it goes through the art tools. For each file: its triangles (and per mesh), its
materials with the kind the vehicle converter would read from their names (tools/vehicles.gd), its textures and their
sizes, its skins (bones, the names the person rig looks for), its animation clips, and its bounds in the file's units
with which way is up and along. No dependencies beyond Python; Pillow adds the texture sizes.

    python3 tools/dev/glb_facts.py [--vehicle] <file.glb> [more.glb ...]

--vehicle adds, for each material, the part the vehicle converter would make of it from its name.
"""
import io
import json
import struct
import sys

VEHICLE_KINDS = [("interior_paint", "interior paint"), ("interior", "interior"), ("seat", "interior"),
    ("plate", "number plate"), ("well", "rubber"), ("lettering", "lettering"), ("sign", "sign"), ("glass", "glass"),
    ("ivory lens", "headlamp"), ("headlamp", "headlamp"), ("ruby", "tail lamp"), ("tail", "tail lamp"),
    ("amber", "amber lamp"), ("indicator", "amber lamp"), ("chrome", "metal"), ("aluminium", "metal"),
    ("steel", "metal"), ("reflector", "metal"), ("metal", "metal"), ("rubber", "rubber"), ("tire", "rubber"),
    ("trim", "rubber (unless 'black trim')")]
PERSON_BONES = ("hips", "spine", "chest", "neck", "head", "shoulder", "arm", "forearm", "hand", "upleg", "thigh",
    "leg", "shin", "foot")

def read_glb(path):
    with open(path, "rb") as f:
        magic, version, length = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            sys.exit(f"{path}: not a GLB (a .gltf with separate files is not read here)")
        chunks = {}
        while f.tell() < length:
            clen, ctype = struct.unpack("<II", f.read(8))
            chunks[ctype] = f.read(clen)
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b"")

def accessor_values(j, bin_data, index):
    acc = j["accessors"][index]
    view = j["bufferViews"][acc["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
    size = struct.calcsize(fmt) * n
    stride = view.get("byteStride", size)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from("<" + fmt * n, bin_data, start + i * stride))
    return out

def vehicle_kind(name):
    n = name.lower()
    for key, kind in VEHICLE_KINDS:
        if key in n:
            return kind
    return "paint (the car's own colour)"

def facts(path, vehicle=False):
    j, bin_data = read_glb(path)
    print(f"== {path}")
    print(f"generator: {j.get('asset', {}).get('generator', '?')}")
    # a mesh without a name (gltfpack drops them) is named by the nodes that use it
    used_by = {}
    for n in j.get("nodes", []):
        if "mesh" in n:
            used_by.setdefault(n["mesh"], []).append(n.get("name", "?"))
    total = 0
    for k, m in enumerate(j.get("meshes", [])):
        tris = 0
        for p in m["primitives"]:
            if p.get("mode", 4) != 4:
                continue
            if "indices" in p:
                tris += j["accessors"][p["indices"]]["count"] // 3
            else:
                tris += j["accessors"][p["attributes"]["POSITION"]]["count"] // 3
        total += tris
        name = m.get("name") or "/".join(used_by.get(k, ["?"]))
        print(f"mesh {name!r}: {tris:,} triangles, {len(m['primitives'])} surface(s)")
    print(f"triangles in all: {total:,}")
    for mat in j.get("materials", []):
        name = mat.get("name", "?")
        pbr = mat.get("pbrMetallicRoughness", {})
        col = pbr.get("baseColorFactor", [1, 1, 1, 1])
        maps = [k for k in ("baseColorTexture", "metallicRoughnessTexture") if k in pbr]
        maps += [k for k in ("normalTexture", "occlusionTexture", "emissiveTexture") if k in mat]
        part = f"; as a vehicle part: {vehicle_kind(name)}" if vehicle else ""
        print(f"material {name!r}: colour {tuple(round(c, 2) for c in col[:3])}, maps {maps or 'none'}{part}")
    images = j.get("images", [])
    if images:
        try:
            from PIL import Image
        except ImportError:
            Image = None
        for im in images:
            size = ""
            if Image and "bufferView" in im:
                view = j["bufferViews"][im["bufferView"]]
                start = view.get("byteOffset", 0)
                try:
                    pic = Image.open(io.BytesIO(bin_data[start:start + view["byteLength"]]))
                    size = f" {pic.width}x{pic.height} {pic.mode}"
                except Exception:
                    size = " (unreadable)"
            print(f"image {im.get('name', im.get('uri', '?'))!r}: {im.get('mimeType', '')}{size}")
    for s in j.get("skins", []):
        names = [j["nodes"][i].get("name", "?") for i in s["joints"]]
        known = sorted({b for n in names for b in PERSON_BONES if b in n.lower()})
        print(f"skin {s.get('name', '?')!r}: {len(names)} bones, e.g. {names[:6]}; person-rig names found: {known}")
    for a in j.get("animations", []):
        t_max = 0.0
        for smp in a["samplers"]:
            acc = j["accessors"][smp["input"]]
            t_max = max(t_max, acc.get("max", [0])[0])
        print(f"clip {a.get('name', '?')!r}: {t_max:.2f} s, {len(a['channels'])} channels")
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            acc = j["accessors"][p["attributes"]["POSITION"]]
            if "min" in acc and "max" in acc:
                lo = [min(a, b) for a, b in zip(lo, acc["min"])]
                hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    if lo[0] < float("inf"):
        size = [h - l for l, h in zip(lo, hi)]
        axes = "xyz"
        up = axes[size.index(max(size))]
        print(f"bounds (file units, before any node transform): {tuple(round(v, 3) for v in size)}, "
              f"tallest along {up} (glTF wants +y up, the front toward +z); bottom at y {lo[1]:.3f}")
    print()

if __name__ == "__main__":
    args = sys.argv[1:]
    vehicle = "--vehicle" in args
    paths = [a for a in args if a != "--vehicle"] or sys.exit(__doc__)
    for p in paths:
        facts(p, vehicle)
