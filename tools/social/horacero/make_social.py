"""Hora Cero launch posts: the Instagram carousel (7 x 1080x1350), two stories (1080x1920), three pictures for X and
link previews (1600x900), a square Instagram post (1080x1080), a LinkedIn / link card (1200x627) and the key art
(3840x2160, no HUD), from stills of the real game (horacero_director.gd's "probe" shot, rendered at each format's own
size by stills.sh) with a light typographic layer only where it helps: the game's name on the first and last and on
the cards, a short line in Spanish on some, nothing on the key art.
usage: make_social.py <stills dir> <out dir>
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "godot"))
FONTS = os.path.join(GODOT, "assets", "fonts") + "/"
ICON = os.path.join(GODOT, "icon.png")
PAPER = (236, 226, 200)
BRASS = (224, 173, 76)
RED = (217, 72, 47)


def font(kind, px):
    if kind == "stencil":
        f = ImageFont.truetype(FONTS + "BigShouldersStencilDisplay-wght.ttf", px)
        try:
            f.set_variation_by_axes([800])
        except Exception:
            pass
        return f
    if kind == "semi":
        return ImageFont.truetype(FONTS + "BarlowCondensed-SemiBold.ttf", px)
    return ImageFont.truetype(FONTS + "SpecialElite-Regular.ttf", px)


def tracked(d, xy, text, f, fill, tr=0.0, anchor="l"):
    widths = [d.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tr * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=f, fill=fill)
        x += w + tr
    return total


def width(text, f, tr=0.0):
    d = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    return sum(d.textlength(ch, font=f) for ch in text) + tr * (len(text) - 1)


def shade(img, box, top_alpha, bottom_alpha):
    """A vertical gradient of dark over a band of the picture (for type to sit on)."""
    x0, y0, x1, y1 = box
    h, w = y1 - y0, x1 - x0
    a = np.linspace(top_alpha, bottom_alpha, h)[:, None] * np.ones((1, w))
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 8, 10, 18
    arr[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    img.alpha_composite(Image.fromarray(arr, "RGBA"), (x0, y0))


def soft_shadow(layer, blur):
    a = layer.split()[3].filter(ImageFilter.GaussianBlur(blur)).point(lambda v: min(255, int(v * 1.6)))
    sh = Image.new("RGBA", layer.size, (6, 8, 14, 0))
    sh.putalpha(a)
    return Image.alpha_composite(sh, layer)


def logo(img, cx, top, scale=1.0, line=True):
    """The game's lock-up: the clock icon, HORA CERO in the stencil, INVASIÓN BUENOS AIRES under a rule."""
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    size = int(118 * scale)
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255)
    lay.paste(icon, (int(cx - size / 2), int(top)), mask)
    fm = font("stencil", int(150 * scale))
    y = top + size + 14 * scale
    wd = width("HORA CERO", fm, 6 * scale)
    tracked(d, (cx, y), "HORA CERO", fm, PAPER + (255,), 6 * scale, "m")
    y += 152 * scale
    if line:
        d.rectangle([cx - wd / 2, y, cx + wd / 2, y + max(2, int(3 * scale))], fill=PAPER + (230,))
        tracked(d, (cx, y + 16 * scale), "INVASIÓN BUENOS AIRES", font("semi", int(36 * scale)), BRASS + (255,), 9 * scale, "m")
    img.alpha_composite(soft_shadow(lay, 14 * scale))
    return y + 70 * scale


def caption(img, text, y, px=40, align="m", x=None, strip=True):
    """A short typewriter line on a dark strip."""
    f = font("type", px)
    lines = text.split("\n")
    d0 = ImageDraw.Draw(img)
    w = max(d0.textlength(ln, font=f) for ln in lines)
    lh = px * 1.3
    h = lh * len(lines)
    cx = img.width / 2 if x is None else x
    left = cx - w / 2 if align == "m" else cx
    if strip:
        pad = px * 0.55
        band = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(band).rectangle([left - pad, y - pad * 0.7, left + w + pad, y + h + pad * 0.5], fill=(10, 12, 20, 178))
        img.alpha_composite(band)
        ImageDraw.Draw(img).rectangle([left - pad, y - pad * 0.7, left - pad + 5, y + h + pad * 0.5], fill=BRASS + (255,))
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k, ln in enumerate(lines):
        lx = left if align != "m" else cx - d.textlength(ln, font=f) / 2
        d.text((lx, y + k * lh), ln, font=f, fill=PAPER + (255,))
    img.alpha_composite(lay)


def cta(img, y, scale=1.0, cx=None, line="Jugalo gratis en el navegador"):
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    cx = img.width / 2 if cx is None else cx
    f = font("type", int(40 * scale))
    d.text((cx - d.textlength(line, font=f) / 2, y), line, font=f, fill=PAPER + (255,))
    tracked(d, (cx, y + 58 * scale), "HORACERO.APP", font("semi", int(44 * scale)), BRASS + (255,), 8 * scale, "m")
    img.alpha_composite(soft_shadow(lay, 10 * scale))


def ramp_left(img, reach, alpha=215):
    """Dark from the left edge, fading out by `reach` pixels (for the name on the cards)."""
    w, h = img.size
    ramp = (alpha * np.clip(1 - np.arange(w) / float(reach), 0, 1) ** 1.3).astype(np.uint8)
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 8, 10, 18
    arr[..., 3] = ramp[None, :]
    img.alpha_composite(Image.fromarray(arr, "RGBA"))


def load(name, size):
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    if im.size != size:
        # a window rounds an odd height up: a pixel off is cropped, anything else scaled
        if abs(im.width - size[0]) <= 2 and abs(im.height - size[1]) <= 2:
            im = im.crop((0, 0, size[0], size[1]))
        else:
            im = im.resize(size, Image.LANCZOS)
    return im


def save(img, sub, name):
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    path = os.path.join(OUT, sub, name)
    img.convert("RGB").save(path, quality=93, optimize=True, subsampling=0)
    print("written", path)


IG = (1080, 1350)
ST = (1080, 1920)
XS = (1600, 900)
SQ = (1080, 1080)
LI = (1200, 627)
CAROUSEL = "instagram carousel"

# ---- Instagram carousel
im = load("ig1.png", IG)
shade(im, (0, 0, 1080, 560), 200, 0)
logo(im, 540, 70, 1.0)
save(im, CAROUSEL, "1 - Hora Cero.jpg")

im = load("ig2.png", IG)
caption(im, "Juan Salvo carga\na los que caen.", 700, 40, x=270)
save(im, CAROUSEL, "2 - Juan Salvo carga a los que caen.jpg")

im = load("ig3.png", IG)
caption(im, "Los cascarudos van por\nlos que quedan afuera.", 1160, 40)
save(im, CAROUSEL, "3 - Un cascarudo.jpg")

im = load("ig4.png", IG)
caption(im, "Bajalos al subte.", 770, 44)
save(im, CAROUSEL, "4 - El subte.jpg")

im = load("ig5.png", IG)
caption(im, "Modo historieta.", 770, 44)
save(im, CAROUSEL, "5 - Modo historieta.jpg")

im = load("ig6.png", IG)
caption(im, "Segundo nivel:\nel Riachuelo.", 1160, 44)
save(im, CAROUSEL, "6 - El Riachuelo.jpg")

im = load("ig7.png", IG)
shade(im, (0, 0, 1080, 520), 215, 0)
logo(im, 540, 56, 0.9)
shade(im, (0, 1050, 1080, 1350), 0, 230)
cta(im, 1192, 0.95)
save(im, CAROUSEL, "7 - Jugalo gratis.jpg")

# ---- Stories
im = load("story1.png", ST)
caption(im, "La nieve mata.\nLlevalos a cubierto.", 440, 50)
save(im, "instagram stories", "1 - La nieve mata.jpg")

im = load("story2.png", ST)
# the name below the story's own bar (its account name and progress line take the top ~180 px)
shade(im, (0, 0, 1080, 900), 225, 0)
y = logo(im, 540, 190, 0.86)
cta(im, y + 18, 1.0)
save(im, "instagram stories", "2 - Jugalo gratis.jpg")

# ---- X / link previews
im = load("x1.png", XS)
save(im, "x and link previews", "1 - Benteveo y los suyos.jpg")
im = load("x2.png", XS)
save(im, "x and link previews", "2 - Un cascarudo va por el grupo.jpg")
im = load("x3.png", XS)
ramp_left(im, 820, 225)
y = logo(im, 300, 235, 0.78)
cta(im, y + 16, 0.84, cx=300)
save(im, "x and link previews", "3 - Hora Cero (link preview).jpg")

# ---- the square post: the name over the sky, the launch at the foot
im = load("square.png", SQ)
shade(im, (0, 0, 1080, 430), 200, 0)
logo(im, 540, 40, 0.74)
shade(im, (0, 820, 1080, 1080), 0, 225)
cta(im, 948, 0.86, line="Ya se puede jugar gratis en el navegador")
save(im, "instagram post", "Hora Cero - ya se puede jugar (1080x1080).jpg")

# ---- LinkedIn and link card
im = load("linkedin.png", LI)
ramp_left(im, 700, 230)
y = logo(im, 250, 118, 0.62)
cta(im, y + 12, 0.7, cx=250)
save(im, "linkedin", "Hora Cero - LinkedIn y link card (1200x627).jpg")

# ---- key art, clean
im = load("keyart.png", (3840, 2160))
save(im, ".", "Hora Cero - key art (3840x2160).jpg")
