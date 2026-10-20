#!/usr/bin/env python3
"""Patch Godot .import files of the nature textures: mip-maps on, normal-map flag for *_normal, lossless,
and no automatic "detect 3D" re-compression. Run after the first `godot --import`, then import again."""
import glob
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "tex", "nature"))
for path in sorted(glob.glob(os.path.join(ROOT, "*.png.import"))):
    text = open(path).read()
    is_normal = path.endswith("_normal.png.import")
    new = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", text)
    new = re.sub(r"compress/normal_map=\d", "compress/normal_map=%d" % (1 if is_normal else 2), new)
    new = re.sub(r"compress/mode=\d", "compress/mode=0", new)
    new = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", new)
    new = re.sub(r"process/fix_alpha_border=\w+", "process/fix_alpha_border=false", new)
    if new != text:
        open(path, "w").write(new)
        print("patched", os.path.basename(path))
