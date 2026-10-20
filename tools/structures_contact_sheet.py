#!/usr/bin/env python3
"""Dev helper: tiles the generated albedo (or normal) maps into one preview image.
Usage: python3 tools/structures_contact_sheet.py out.png [a|n] [name ...]"""
import os, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex', 'structures'))
dst = sys.argv[1]
kind = sys.argv[2] if len(sys.argv) > 2 else 'a'
names = sys.argv[3:] or sorted(f[:-6] for f in os.listdir(SRC) if f.endswith('_%s.png' % kind))
cell = 384
cols = min(4, len(names))
rows = (len(names) + cols - 1) // cols
sheet = Image.new('RGB', (cols * cell, rows * cell), (40, 40, 40))
for i, nm in enumerate(names):
    im = Image.open(os.path.join(SRC, '%s_%s.png' % (nm, kind))).convert('RGB').resize((cell - 4, cell - 4), Image.LANCZOS)
    sheet.paste(im, ((i % cols) * cell + 2, (i // cols) * cell + 2))
sheet.save(dst)
print('sheet', dst, names)
