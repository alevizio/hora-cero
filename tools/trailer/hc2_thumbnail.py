"""The YouTube thumbnail of the cinematic Hora Cero trailer: a still of the game's own scene (hc2_director.gd's "thumb"
take, rendered large) graded like the film, with the title in the game's stencil as on its launch screen.
usage: hc2_thumbnail.py <still.png> <out.jpg> [title side: left|right]
1280 x 720, JPEG. The comic's title never appears: HORA CERO, its line "Invasión Buenos Aires".
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.normpath(os.path.join(HERE, "..", "..", "godot", "assets", "fonts")) + "/"
IVORY = (236, 230, 210)
BRASS = (224, 173, 76)
KHAKI = (179, 166, 125)
W, H = 1280, 720

src, out = sys.argv[1], sys.argv[2]
side = sys.argv[3] if len(sys.argv) > 3 else "left"
img = Image.open(src).convert("RGB")
# fill 16:9, then the film's grade: the darks cooled, the lights warmed, a firmer S, the vignette
img = img.resize((W, int(round(img.height * W / img.width))), Image.LANCZOS)
if img.height > H:
    top = (img.height - H) // 2
    img = img.crop((0, top, W, top + H))
f = np.asarray(img, np.float32) / 255.0
f = np.power(f, 1 / 1.12)
lum = f.mean(axis=2, keepdims=True)
f = f + (1 - lum) * np.array([-0.025, -0.005, 0.04]) * 0.8 + lum * np.array([0.04, 0.012, -0.03])
f = np.clip(f, 0, 1)
f = f * f * (3 - 2 * f) * 0.35 + f * 0.65
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
f *= (1.0 - 0.38 * np.clip((r - 0.5) / 0.9, 0, 1) ** 1.5)[..., None]
img = Image.fromarray((np.clip(f, 0, 1) * 255).astype(np.uint8))
img = ImageEnhance.Contrast(img).enhance(1.06)
# the title's side darkened a little more, for the type to stand on
shade = Image.new("L", (W, H), 0)
sd = ImageDraw.Draw(shade)
for x in range(W):
    k = (1.0 - x / (W * 0.55)) if side == "left" else ((x - W * 0.45) / (W * 0.55))
    sd.line([(x, 0), (x, H)], fill=int(255 * 0.55 * max(0.0, min(1.0, k)) ** 1.3))
img = Image.composite(Image.new("RGB", (W, H), (4, 6, 10)), img, shade)

layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
f_title = ImageFont.truetype(FONTS + "BigShouldersStencilDisplay-wght.ttf", 170)
try:
    f_title.set_variation_by_axes([760])
except Exception:
    pass
f_line = ImageFont.truetype(FONTS + "BarlowCondensed-SemiBold.ttf", 36)


def tracked(xy, text, fnt, fill, tracking):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=fnt, fill=fill)
        x += d.textlength(ch, font=fnt) + tracking
    return x


def width(text, fnt, tracking):
    return sum(d.textlength(ch, font=fnt) for ch in text) + tracking * (len(text) - 1)


lines = ["HORA", "CERO"]
# the block (the name and its line under it) kept whole inside the frame, 64 px from the side it stands on
block = max(max(width(t, f_title, 6) for t in lines), width("INVASIÓN BUENOS AIRES", f_line, 6))
x0 = 64 if side == "left" else W - 64 - block
y = 150
for t in lines:
    tracked((x0, y), t, f_title, IVORY + (255,), 6)
    y += 150
d.rectangle([x0 + 4, y + 38, x0 + 74, y + 44], fill=BRASS + (255,))
tracked((x0 + 4, y + 60), "INVASIÓN BUENOS AIRES", f_line, KHAKI + (255,), 6)
shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(10))
dark = Image.new("RGBA", (W, H), (0, 0, 0, 255))
base = img.convert("RGBA")
base.paste(dark, (0, 0), shadow.point(lambda v: int(v * 0.85)))
base = Image.alpha_composite(base, layer)
base.convert("RGB").save(out, quality=92, optimize=True)
print("thumbnail", out, os.path.getsize(out) // 1024, "KB")
