#!/usr/bin/env python3
"""Dev-only, for the Figma kit (Hora Cero · kit, the JUAN SALVO row): Juan Salvo's eight cards from the game's own renders
of him, laid on the kit's studio backdrops and framed as the kit's earlier cards were (measured from them: the figure
821 px tall on the 720x960 views, soles at row 898; the bust's hood from row 119, 3.63 times the views' head; the boots
4.6 times the views', soles at row 900, the pair centred at x 572 of 1242). The backdrops are the earlier cards' own
(tools/dev/kit_backdrops/*.png: each row's left and right edge colours; the floor's shadow under him is drawn afresh).

The renders first (rendered, not headless; a sandbox keeps Godot off the network):
  T="$GODOT --path godot --rendering-driver opengl3 --script ../tools/dev/turntable.gd -- salvo art:juan_salvo"
  $T <work>/full  48 1080 1440 2.3 0.98
  $T <work>/bust  48 1800 1800 0.9 1.45
  $T <work>/boots 48 1800 1800 0.6 0.3 0 - patrol 22
  $GODOT --path godot --rendering-driver opengl3 --script ../tools/dev/salvo_cards.gd -- <work>/poses 1280 1920
Then:
  python3 tools/dev/salvo_kit_cards.py <work> <out dir>
writes front, three-quarter, back (720x960), bust (872x960), boots (1242x960), walk, carry, aim (640x960, on the kit's
grey stage) as <out dir>/<name>.png, at twice the kit's layer sizes. In the kit, the image of each card takes the new
file as its fill (paste the PNG, copy its properties, paste them on the card's image layer), so the layers keep their
size and place.
"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GREY = (82, 87, 84)  # the kit's stage under the pose cards

def backdrop(name, width):
    """The plate's rows run from their left colour to their right colour across the card."""
    plate = np.asarray(Image.open(os.path.join(HERE, "kit_backdrops", name + ".png")).convert("RGB")).astype(float)
    xs = np.linspace(0, 1, width)[None, :, None]
    bg = plate[:, 0:1, :] * (1 - xs) + plate[:, 1:2, :] * xs
    return Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB")

def scaled(path, factor):
    im = Image.open(path).convert("RGBA")
    pm = im.convert("RGBa")  # premultiplied, so the resampling leaves no dark fringe
    return pm.resize((round(im.width * factor), round(im.height * factor)), Image.LANCZOS).convert("RGBA")

def alpha(im):
    return np.asarray(im)[:, :, 3] > 128

def runs(row):
    """Contiguous spans of a boolean row: [(x0, x1), ...]."""
    out, start = [], None
    for x, v in enumerate(list(row) + [False]):
        if v and start is None: start = x
        if not v and start is not None: out.append((start, x - 1)); start = None
    return out

def feet(im, rows_up):
    """The soles' row and the boots' spans in the rows just above it (two runs when the boots stand apart)."""
    a = alpha(im)
    bottom = np.where(a.any(axis=1))[0].max()
    spans = [s for s in runs(a[bottom - rows_up:bottom + 1].any(axis=0)) if s[1] - s[0] > 8]
    return bottom, spans

def shadow(size, blobs):
    """Soft shadows on the floor, (cx, cy, rx, ry, blur, opacity) each."""
    layer = np.zeros((size[1], size[0]), np.uint8)
    for cx, cy, rx, ry, blur, op in blobs:
        e = Image.new("L", size, 0)
        ImageDraw.Draw(e).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=int(255 * op))
        layer = np.maximum(layer, np.asarray(e.filter(ImageFilter.GaussianBlur(blur))))
    return Image.fromarray(layer)

def darken(bg, mask, colour):
    bg = np.asarray(bg).astype(float); m = np.asarray(mask).astype(float)[:, :, None] / 255.0
    return Image.fromarray(np.clip(bg * (1 - m) + np.array(colour)[None, None, :] * m, 0, 255).astype(np.uint8))

def place(bg, fig, x, y):
    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    layer.paste(fig, (int(round(x)), int(round(y))), fig)
    return Image.alpha_composite(bg.convert("RGBA"), layer).convert("RGB")

def main(work, out):
    os.makedirs(out, exist_ok=True)
    # the views: the frontal frame sets the scale, the three share the camera so they share it
    rows = np.where(alpha(Image.open(f"{work}/full/f_006.png").convert("RGBA")).any(axis=1))[0]
    S = 821.0 / (rows.max() - rows.min())
    bg = backdrop("views", 720)
    for name, f in (("front", 6), ("three-quarter", 0), ("back", 24)):
        fig = scaled(f"{work}/full/f_{f:03d}.png", S)
        bottom, spans = feet(fig, 30)
        x = 360 - (min(s[0] for s in spans) + max(s[1] for s in spans)) / 2.0
        blobs = [(360, 912, 175, 36, 26, 0.55)] + [((s0 + s1) / 2 + x, 900, (s1 - s0) * 0.62, 11, 7, 0.7) for s0, s1 in spans]
        place(darken(bg, shadow(bg.size, blobs), (14, 18, 22)), fig, x, 898 - bottom).save(f"{out}/{name}.png")
    # the bust, turned a little to our left like the earlier card: its hood's widest row centred at x 442
    fig = scaled(f"{work}/bust/f_004.png", S * 3.63 * (1440 / 2.3) / (1800 / 0.9))
    a = alpha(fig)
    top = np.where(a.any(axis=1))[0].min()
    hood = top + int(np.argmax(a.sum(axis=1)[top:top + int(446 * 0.6)]))
    xs = np.where(a[hood])[0]
    place(backdrop("bust", 872), fig, 442 - (xs.min() + xs.max()) / 2.0, 119 - top).save(f"{out}/bust.png")
    # the boots, from the front left and a little above
    fig = scaled(f"{work}/boots/f_001.png", S * 4.6 * (1440 / 2.3) / (1800 / 0.6))
    bottom, spans = feet(fig, 40)
    x = 572 - (min(s[0] for s in spans) + max(s[1] for s in spans)) / 2.0
    bg = backdrop("boots", 1242)
    blobs = [(572, 925, 390, 42, 36, 0.6)] + [((s0 + s1) / 2 + x, 904, (s1 - s0) * 0.6, 16, 10, 0.7) for s0, s1 in spans]
    place(darken(bg, shadow(bg.size, blobs), (36, 42, 46)), fig, x, 900 - bottom).save(f"{out}/boots.png")
    # the poses, halved onto the stage
    for name in ("walk", "carry", "aim"):
        fig = scaled(f"{work}/poses/juan - {name}.png", 0.5)
        stage = Image.new("RGBA", fig.size, GREY + (255,))
        stage.alpha_composite(fig)
        stage.convert("RGB").save(f"{out}/{name}.png")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
