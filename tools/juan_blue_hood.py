#!/usr/bin/env python3
"""Juan Salvo's game model from Ale's "Blue Hood Survivor v4" (made in Codex, 2026-10-19; 308,215 triangles, 4K/2K
textures, 25 bones, clips Idle, Walk, Run, Jump, Fall and Inspect): made light enough for the web game without changing
what it is.

  1. gltfpack (meshoptimizer) simplifies every mesh to about an eighth of its triangles, keeping the skin, the UV seams,
     the named nodes (the rifle is "Rifle") and materials, and the six clips;
  2. its textures are scaled down to what the game's camera can show (colour 1024 or 512, normal maps half that,
     occlusion/roughness/metal 256) and written back into the GLB.

    python3 tools/juan_blue_hood.py <blue_hood_survivor.glb> [out.glb]

The source (95 MB) is not kept in the repository: it is in Ale's blue-hood-survivor-v4 folder
(characters/blue_hood/blue_hood_survivor.glb). The output goes to godot/art_pack/juan_salvo/juan_salvo.glb.
This was Juan's model on 19 and 20 October 2026; tools/juan_suit.py makes the one after it, and running this puts the
blue-hood Juan back.
Needs gltfpack 0.25 (npm install -g gltfpack@0.25.0) and Pillow.
"""
import io
import json
import os
import struct
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "godot", "art_pack", "juan_salvo", "juan_salvo.glb")
# gltfpack: about 41k triangles from 308k, within 2% of the shape
SIMPLIFY = ["-si", "0.12", "-se", "0.02", "-noq", "-kn", "-km"]
# the largest side kept for each image's colour map (its name's start); normal maps get half, packed maps a quarter
COLOUR = {"coat": 1024, "hood": 1024, "mature_skin": 1024, "sleeves": 1024, "backpack": 1024, "trousers": 512,
          "boots": 512, "rifle": 512, "survivor": 512, "gloves": 256, "harness": 256, "eyes": 256}
DEFAULT = 512


def side_for(name: str) -> int:
    n = name.lower()
    if "nrm" in n or "normal" in n:
        kind = "normal"
    elif "orm" in n:
        kind = "orm"
    else:
        kind = "colour"
    base = DEFAULT
    for key, size in COLOUR.items():
        if n.startswith(key) or (key == "mature_skin" and "skin" in n):
            base = size
            break
    if kind == "normal":
        return max(256, base // 2)
    if kind == "orm":
        return 256
    return base


def read_glb(path: str):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", data[off:off + 4])[0]
    return j, bytearray(data[off + 8:off + 8 + blen])


def write_glb(path: str, j: dict, chunks: list) -> None:
    """The JSON with one buffer made of `chunks` (bytes, each padded to 4)."""
    blob = bytearray()
    for c in chunks:
        blob += c
        while len(blob) % 4:
            blob += b"\0"
    j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)


def shrink_images(src: str, dst: str) -> list:
    j, buf = read_glb(src)
    views = j["bufferViews"]
    image_views = {im["bufferView"] for im in j.get("images", [])}
    new_views = []
    chunks = []
    pos = 0
    report = []
    for i, v in enumerate(views):
        raw = bytes(buf[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
        if i in image_views:
            im = next(x for x in j["images"] if x["bufferView"] == i)
            pic = Image.open(io.BytesIO(raw))
            side = side_for(im.get("name", ""))
            if max(pic.size) > side:
                mode = "RGBA" if pic.mode in ("RGBA", "LA", "P") else "RGB"
                pic = pic.convert(mode).resize((side, side) if pic.size[0] == pic.size[1] else
                                               (side, max(1, round(pic.size[1] * side / pic.size[0]))), Image.LANCZOS)
            out = io.BytesIO()
            pic.save(out, "PNG", optimize=True)
            raw = out.getvalue()
            im["mimeType"] = "image/png"
            report.append((im.get("name", ""), pic.size, len(raw)))
        nv = dict(v)
        nv["buffer"] = 0
        nv["byteOffset"] = pos
        nv["byteLength"] = len(raw)
        new_views.append(nv)
        chunks.append(raw)
        pos += len(raw)
        while pos % 4:
            pos += 1
    j["bufferViews"] = new_views
    write_glb(dst, j, chunks)
    return report


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else OUT
    with tempfile.TemporaryDirectory() as tmp:
        simple = os.path.join(tmp, "simple.glb")
        subprocess.run(["gltfpack", "-i", src, "-o", simple] + SIMPLIFY, check=True)
        report = shrink_images(simple, dst)
    j, _ = read_glb(dst)
    tris = sum(j["accessors"][p["indices"]]["count"] // 3 for m in j["meshes"] for p in m["primitives"])
    print(f"{dst}: {tris} triangles, {len(j['materials'])} materials, {len(j.get('animations', []))} clips, "
          f"{os.path.getsize(dst) / 1e6:.1f} MB")
    for name, size, n in report:
        print(f"  {name}: {size[0]}x{size[1]} {n // 1024} KB")


if __name__ == "__main__":
    main()
