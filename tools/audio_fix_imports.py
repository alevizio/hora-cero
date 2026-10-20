#!/usr/bin/env python3
"""Patches the Godot .import files of the sound set: uncompressed 16-bit PCM (the engine's default would be QOA),
mono left as it is, no trimming or normalising (both would break the loop padding and the level table), and no
loop detection (audio.gd sets the loop points in code). Run after the first `godot --import`, then import again."""
import glob
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "audio"))
WANTED = {"force/8_bit": "false", "force/mono": "false", "force/max_rate": "false", "edit/trim": "false",
          "edit/normalize": "false", "edit/loop_mode": "0", "compress/mode": "0"}
for path in sorted(glob.glob(os.path.join(ROOT, "*.wav.import"))):
    text = open(path).read()
    new = text
    for key, value in WANTED.items():
        new = re.sub(r"(?m)^%s=.*$" % re.escape(key), "%s=%s" % (key, value), new)
    if new != text:
        open(path, "w").write(new)
        print("patched", os.path.basename(path))
