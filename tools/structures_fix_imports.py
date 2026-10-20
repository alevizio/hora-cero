#!/usr/bin/env python3
"""Patches the Godot .import files of the structure textures after a first `godot --import` run:
mipmaps on, *_n.png flagged as normal maps, lossless kept, no automatic 3D re-compression, and no alpha-border
fixing (the albedo alpha channel carries roughness on most of these). Re-run the importer afterwards."""
import glob, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'structures'))
CUTOUT = {'wire_a.png', 'decal_a.png'}
for path in sorted(glob.glob(os.path.join(SRC, '*.png.import'))):
    name = os.path.basename(path)[:-len('.import')]
    text = open(path).read()
    def setv(key, value):
        global text
        text, n = re.subn(r'(?m)^%s=.*$' % re.escape(key), '%s=%s' % (key, value), text)
        assert n == 1, (name, key)
    setv('mipmaps/generate', 'true')
    setv('compress/mode', '0')
    setv('compress/normal_map', '1' if name.endswith('_n.png') else '2')
    setv('detect_3d/compress_to', '0')
    setv('process/fix_alpha_border', 'true' if name in CUTOUT else 'false')
    open(path, 'w').write(text)
    print('patched', name)
