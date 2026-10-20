"""Edit, grade, title, subtitle and mix the cinematic Hora Cero trailer from the takes of hc2_director.gd, the
narrator's lines (tools/voice_trailer.py clean) and the score (hc2_music.py).
usage: hc2_compose.py <wide|upright> <takes dir> <narration dir> <out dir> [--upto S] [--sheet]
  wide:    1920 x 1080, 24 fps, the film shots letterboxed to 2.39:1, the game's own shots opened to the full frame.
           Writes <out>/master_wide.mkv (picture), <out>/mix_wide.wav (sound), and the films:
           "Hora Cero - trailer cinematic 16x9.mp4", "Hora Cero - trailer cinematic 16x9 (English subtitles).mp4" and a
           light copy for WhatsApp (under 16 MB): "Hora Cero - trailer cinematic 16x9 (WhatsApp).mp4".
  upright: 1080 x 1920, its own takes (framed upright), Spanish captions burned in, big, kept clear of the apps'
           buttons (the bottom fifth and the right 15 %): "Hora Cero - trailer 9x16.mp4".
The edit is cut to the narration: each line has its start, each shot its in and out; the score is made for those times
(a cue sheet handed to hc2_music.py). The sound is the narrator on top, the score ducked under him, and the game's own
sound files (wind, the tram's bell, steps in the snow, the rifle, a fall) laid where the picture has them; the mix is
brought to -14 LUFS integrated and -1 dBTP, stereo 48 kHz, AAC. Video: H.264 High, yuv420p.
--sheet writes a contact sheet (one frame from the middle of each shot) instead of the films; --sound-only stops after the
mix; --keep-picture reuses a master picture already made.
The comic's title never appears: the game is HORA CERO, its line "Invasión Buenos Aires".
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CUT = sys.argv[1]
TAKES = sys.argv[2]
VOICE = sys.argv[3]
OUTDIR = sys.argv[4]
UPTO = float(sys.argv[sys.argv.index("--upto") + 1]) if "--upto" in sys.argv else None
SHEET = "--sheet" in sys.argv
W, H = (1920, 1080) if CUT == "wide" else (1080, 1920)
FPS = 24
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FONTS = os.path.join(ROOT, "godot", "assets", "fonts") + "/"
AUDIO = os.path.join(ROOT, "godot", "assets", "audio") + "/"
ICON = os.path.join(ROOT, "tools", "preview_og", "buenosaires_icon.png")
IVORY = (236, 230, 210)
BRASS = (224, 173, 76)
KHAKI = (179, 166, 125)
# the film's frame: 2.39:1 inside 16:9 (bars of 138 px top and bottom); the game's shots open to the whole frame
SCOPE_BAR = int(round((H - W / 2.39) / 2)) if CUT == "wide" else 0
os.makedirs(OUTDIR, exist_ok=True)

# ------------------------------------------------------------------ the narration and the edit
# (key, start in the film, Spanish, English); the starts are where the lines sit against the pictures below.
LINES = {
    "01": ("Buenos Aires. Invierno de mil novecientos cincuenta y ocho.", "Buenos Aires. Winter, 1958."),
    "02": ("Esa noche nevó. Por primera vez en cuarenta años, nevó en la ciudad.", "That night it snowed. For the first time in forty years, it snowed in the city."),
    "03": ("La gente salió a verla. Y la nieve los fue tocando, uno por uno.", "People came out to see it. And the snow touched them, one by one."),
    "04": ("Quien la tocaba, caía.", "Whoever it touched, fell."),
    "05a": ("Quedaban unos pocos bajo techo.", "A few were left under cover."),
    "05b": ("Un motorman.", "A motorman."),
    "05c": ("Un liniero.", "A lineman."),
    "05d": ("Un canillita.", "A paperboy."),
    "05e": ("Un botero.", "A boatman."),
    "06": ("Y una sola idea: llevar a todos a cubierto.", "And one thought: get everyone under cover."),
    "07": ("Afuera, en plena nevada, un hombre sellado en su traje. El único que podía ir a buscarlos.",
           "Out there, in the snowfall, a man sealed in his suit. The only one who could go and get them."),
    "08": ("Y entonces, desde las avenidas, llegaron ellos.", "And then, from the avenues, they came."),
    "09": ("Hora Cero.", "Hora Cero."),
}
# A subtitle that is long is broken where the line breathes (a full stop or a comma near its middle).
SUB_BREAK = {
    "02": ("That night it snowed.", "For the first time in forty years, it snowed in the city."),
    "03": ("People came out to see it.", "And the snow touched them, one by one."),
    "07": ("Out there, in the snowfall, a man sealed in his suit.", "The only one who could go and get them."),
}
# Where each upright caption sits (the height of its middle, a share of the frame), kept off what the shot is about:
# the woman going down (over the snow at her feet), Juan Salvo coming (over his legs), the cascarudos (over the street
# above them); always above the bottom fifth. Default 0.60.
CAP_Y = {("04", 0): 0.745, ("07", 0): 0.725, ("08", 0): 0.36}
CAP_BREAK = {   # the upright cut's Spanish captions, short lines broken where they are said
    "02": [("Esa noche nevó.",), ("Por primera vez", "en cuarenta años,", "nevó en la ciudad.")],
    "04": [("Quien la tocaba,", "caía.")],
    "07": [("Afuera, en plena nevada,", "un hombre sellado", "en su traje."), ("El único que podía", "ir a buscarlos.")],
    "08": [("Y entonces,", "desde las avenidas,", "llegaron ellos.")],
}

if CUT == "wide":
    # narration: key -> start (s), set against the cleaned lines (tools/voice_trailer.py clean): "caía" lands as the woman
    # by the Pirámide goes down (the fall take's collapse is a second into it), "llegaron ellos" as the cascarudos fill
    # the lens
    SAY = {"01": 1.2, "02": 12.6, "03": 20.6, "04": 27.4, "05a": 33.0, "05b": 35.8, "05c": 37.95, "05d": 40.05, "05e": 42.2,
           "06": 44.75, "07": 49.0, "08": 58.6, "09": 69.4}
    # shots: (start, length, take, in-point s, kind); kind: cine (letterboxed), game (the full frame, the HUD), title, end
    EDIT = [
        (0.0, 6.0, "open", 0.4, "cine"),
        (6.0, 3.6, "cabildo", 0.6, "cine"),
        (9.6, 2.6, "tram", 0.4, "cine"),
        (12.2, 4.4, "flakes", 0.3, "cine"),
        (16.6, 3.8, "lookup", 0.5, "cine"),
        (20.4, 4.2, "people", 0.3, "cine"),
        (24.6, 3.4, "touch", 0.1, "cine"),
        (28.0, 4.8, "fall", 0.0, "cine"),
        (32.8, 2.8, "shelter", 0.4, "cine"),
        (35.6, 2.1, "hornero", 0.4, "cine"),
        (37.7, 2.1, "lechuza", 0.4, "cine"),
        (39.8, 2.15, "benteveo", 0.4, "cine"),
        (41.95, 2.45, "bigua", 0.4, "cine"),
        (44.4, 4.0, "g_lead", 0.4, "game"),
        (48.4, 5.3, "juan", 0.3, "cine"),
        (53.7, 3.7, "g_carry", 0.3, "game"),
        (57.4, 6.2, "beasts", 0.4, "cine"),
        (63.6, 1.8, "legs", 0.6, "cine"),
        (65.4, 1.4, "fire", "shot-0.7", "cine"),
        (66.8, 1.4, "rear", "rear+0.0", "cine"),
        (68.2, 4.0, "title_bg", 0.5, "title"),
        (72.2, 2.8, None, 0.0, "end"),
    ]
    TOTAL = 75.0
else:
    SAY = {"02": 0.5, "04": 6.6, "07": 10.9, "08": 19.4, "09": 25.8}
    EDIT = [
        (0.0, 3.2, "flakes", 0.3, "cine"),
        (3.2, 4.0, "lookup", 0.4, "cine"),
        (7.2, 3.4, "fall", 0.0, "cine"),
        (10.6, 5.0, "juan", 0.3, "cine"),
        (15.6, 3.4, "g_carry", 0.3, "game"),
        (19.0, 4.6, "beasts", 1.0, "cine"),
        (23.6, 1.4, "fire", "shot-0.7", "cine"),
        (25.0, 3.0, "title_bg", 0.5, "title"),
        (28.0, 2.0, None, 0.0, "end"),
    ]
    TOTAL = 30.0
FULL_EDIT, FULL_TOTAL = list(EDIT), TOTAL
if UPTO:
    EDIT = [e for e in EDIT if e[0] < UPTO - 0.01]
    TOTAL = min(TOTAL, UPTO)
NFRAMES = int(round(TOTAL * FPS))


def line_len(key):
    import soundfile as sf
    info = sf.info(os.path.join(VOICE, "line_%s.wav" % key))
    return info.frames / info.samplerate


# ------------------------------------------------------------------ takes
marks, events = {}, {}
for name in os.listdir(TAKES):
    if name.endswith(".log"):
        for row in open(os.path.join(TAKES, name)):
            p = row.split()
            if len(p) == 3 and p[0] == "MARK":
                marks[p[1]] = int(p[2])
            if len(p) == 4 and p[0] == "EVENT":
                events[(p[1], p[2])] = int(p[3])


def in_point(take, value):
    """Seconds into a take: a number, or "<event>+x" / "<event>-x" from the frame an event of the take happened on."""
    if isinstance(value, str):
        for sign in "+-":
            if sign in value:
                ev, off = value.split(sign)
                f = events.get((take, ev))
                if f is None:
                    print("no event", take, ev)
                    f = 24
                return f / FPS + (float(off) if sign == "+" else -float(off))
    return float(value)


# The grade (the film's shots): the shadows cooled, the highlights warmed, a gentle S, colour held back a touch; per
# take, light lifted (gamma) where the night came out too deep to read.
LIFT = {"open": 1.12, "cabildo": 1.18, "tram": 1.1, "flakes": 1.0, "lookup": 1.2, "people": 1.12, "touch": 1.15, "fall": 1.15,
        "shelter": 1.18, "hornero": 1.25, "lechuza": 1.3, "benteveo": 1.2, "bigua": 1.1, "juan": 1.15, "beasts": 1.15,
        "legs": 1.2, "fire": 1.12, "rear": 1.18, "title_bg": 1.0}
GRADE = ("colorbalance=rs=-0.035:gs=-0.01:bs=0.06:rm=-0.01:gm=0.0:bm=0.025:rh=0.05:gh=0.015:bh=-0.04,"
         "curves=master='0/0.012 0.16/0.12 0.5/0.5 0.84/0.87 1/0.985',eq=saturation=0.9")
GAME_GRADE = "eq=saturation=0.97"


def take_frames(take, start_s, n, kind):
    if take is None or take not in marks:
        if take is not None:
            print("missing take", take)
        for _ in range(n):
            yield np.zeros((H, W, 3), np.uint8)
        return
    first = int(round(start_s * FPS))
    have = max(1, min(n, marks[take] - first))
    chain = "select='gte(n\\,%d)',setpts=N/FRAME_RATE/TB,scale=%d:%d:flags=lanczos" % (first, W, H)
    if kind != "game":
        g = LIFT.get(take, 1.0)
        if g != 1.0:
            chain += ",lutrgb=r='255*pow(val/255\\,1/%s)':g='255*pow(val/255\\,1/%s)':b='255*pow(val/255\\,1/%s)'" % (g, g, g)
        chain += "," + GRADE
    else:
        chain += "," + GAME_GRADE
    cmd = ["ffmpeg", "-v", "error", "-i", os.path.join(TAKES, take + ".mkv"), "-vf", chain, "-frames:v", str(have),
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    frame = None
    for i in range(n):
        if i < have:
            raw = p.stdout.read(W * H * 3)
            if len(raw) == W * H * 3:
                frame = np.frombuffer(raw, np.uint8).reshape(H, W, 3)
        if frame is None:
            frame = np.zeros((H, W, 3), np.uint8)
        yield frame
    p.stdout.close()
    p.wait()
    if have < n:
        print("short take", take, "has", have, "of", n)


# ------------------------------------------------------------------ the film look (numpy)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
_r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
VIGNETTE = (1.0 - 0.32 * np.clip((_r - 0.45) / 0.9, 0, 1) ** 1.6)[..., None].astype(np.float32)
del yy, xx, _r
_grain_rng = np.random.default_rng(1958)
GRAIN = [(_grain_rng.standard_normal((H // 2, W // 2)).astype(np.float32)) for _ in range(12)]


def film_look(x, i):
    """Halation round the lights (a warm bloom from what is near white), the vignette, a fine grain."""
    f = x.astype(np.float32)
    lum = f.mean(axis=2)
    hot = np.clip((lum - 170.0) / 85.0, 0, 1)
    small = Image.fromarray((hot * 255).astype(np.uint8)).resize((W // 8, H // 8), Image.BILINEAR)
    glow = np.asarray(small.filter(ImageFilter.GaussianBlur(5)).resize((W, H), Image.BILINEAR), np.float32) / 255.0
    f += glow[..., None] * np.array([46.0, 26.0, 12.0], np.float32)
    f *= VIGNETTE
    g = GRAIN[i % len(GRAIN)]
    g = np.repeat(np.repeat(g, 2, axis=0), 2, axis=1)[:H, :W]
    f += g[..., None] * (3.2 + 2.0 * (1.0 - np.clip(lum[..., None] / 200.0, 0, 1)))
    return np.clip(f, 0, 255).astype(np.uint8)


def letterbox(x, bar):
    if bar <= 0:
        return x
    x = x.copy()
    x[:bar] = 0
    x[H - bar:] = 0
    return x


# ------------------------------------------------------------------ type
def font(kind, px):
    if kind == "stencil":
        f = ImageFont.truetype(FONTS + "BigShouldersStencilDisplay-wght.ttf", int(px))
        try:
            f.set_variation_by_axes([760])
        except Exception:
            pass
        return f
    if kind == "semi":
        return ImageFont.truetype(FONTS + "BarlowCondensed-SemiBold.ttf", int(px))
    return ImageFont.truetype(FONTS + "BarlowCondensed-Medium.ttf", int(px))


def tracked(d, xy, text, f, fill, tracking=0.0, anchor="l"):
    widths = [d.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    for ch, wd in zip(text, widths):
        d.text((x, y), ch, font=f, fill=fill)
        x += wd + tracking
    return total


def shadowed(img, blur=8, strength=0.9):
    a = img.split()[3]
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dark = Image.new("RGBA", img.size, (4, 6, 10, 255))
    spread = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: min(255, int(v * 1.8 * strength)))
    sh.paste(dark, (0, 0), spread)
    return Image.alpha_composite(sh, img)


class Layer:
    def __init__(self, img):
        box = img.getbbox() or (0, 0, 1, 1)
        arr = np.asarray(img.crop(box), np.float32) / 255.0
        self.x0, self.y0, self.x1, self.y1 = box
        self.a = arr[..., 3:4]
        self.rgb = arr[..., :3] * 255.0

    def blend(self, frame, alpha=1.0):
        if alpha <= 0.003:
            return frame
        a = self.a * alpha
        region = frame[self.y0:self.y1, self.x0:self.x1].astype(np.float32)
        frame[self.y0:self.y1, self.x0:self.x1] = np.clip(region * (1 - a) + self.rgb * a + 0.5, 0, 255).astype(np.uint8)
        return frame


def title_card(sub_alpha_only=False):
    """HORA CERO in the game's stencil (as on its launch screen: ivory, the brass rule under it), then its line."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    px = 250 if CUT == "wide" else 172
    f = font("stencil", px)
    cy = H * (0.45 if CUT == "wide" else 0.42)
    cx = W / 2 if CUT == "wide" else W * 0.47   # upright: clear of the apps' buttons down the right
    # where the stencil's letters really end (its baseline), for the brass rule under them (as on the launch screen:
    # a short rule a little below the name) and the line under that
    top = cy - px * 0.62
    base = top + d.textbbox((0, 0), "HORA CERO", font=f)[3]
    if not sub_alpha_only:
        wd = tracked(d, (cx, top), "HORA CERO", f, IVORY + (255,), 10 if CUT == "wide" else 7, "m")
        d.rectangle([cx - 46, base + px * 0.24, cx + 46, base + px * 0.24 + 5], fill=BRASS + (255,))
    else:
        fs = font("semi", 46 if CUT == "wide" else 42)
        tracked(d, (cx, base + px * 0.24 + 24), "INVASIÓN BUENOS AIRES", fs, KHAKI + (255,), 12 if CUT == "wide" else 9, "m")
    return shadowed(img, 14, 1.0)


def end_card():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = 112 if CUT == "wide" else 120
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255)
    top = H * (0.36 if CUT == "wide" else 0.36)
    cx = W / 2 if CUT == "wide" else W * 0.47
    img.paste(icon, (int(cx - size / 2), int(top)), mask)
    fp = font("semi", 64 if CUT == "wide" else 66)
    fu = font("semi", 40 if CUT == "wide" else 44)
    y = top + size + 44
    tracked(d, (cx, y), "JUGALO GRATIS", fp, IVORY + (255,), 14, "m")
    d.rectangle([cx - 34, y + 92, cx + 34, y + 95], fill=BRASS + (255,))
    tracked(d, (cx, y + 116), "HORACERO.APP", fu, KHAKI + (255,), 10, "m")
    return img


def subtitle_img(lines, upright=False, low_band=True, y_mid=0.60):
    """A clean subtitle: ivory Barlow Condensed with a soft dark edge; in the film's lower bar, or over the picture on a
    faint plate (the game's shots, with their HUD; the upright cut's captions)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    px = 46 if not upright else 72
    f = font("medium" if not upright else "semi", px)
    lh = px * 1.12
    # the upright captions: big, wrapped to at most 790 px, centred a little left of the middle so that they stay clear
    # of the apps' buttons down the right 15 % of the frame (and of the bottom fifth, where the caption text sits)
    cx = W / 2 if not upright else W * 0.465
    if upright:
        wrapped = []
        for t in lines:
            words, cur = t.split(), ""
            for wd in words:
                trial = (cur + " " + wd).strip()
                if cur and d.textlength(trial, font=f) > 790:
                    wrapped.append(cur)
                    cur = wd
                else:
                    cur = trial
            wrapped.append(cur)
        lines = wrapped
    heights = len(lines) * lh
    if upright:
        y0 = H * y_mid - heights / 2
    elif low_band:
        y0 = H - SCOPE_BAR / 2 - heights / 2 - px * 0.12
    else:
        # over the game's own shots: clear above the HUD's cards and buttons (which start at 0.71 of the height)
        y0 = H * 0.655 - heights / 2
    widths = [d.textlength(t, font=f) for t in lines]
    if not low_band or upright:
        pad = 18 if not upright else 24
        plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        pd = ImageDraw.Draw(plate)
        pd.rounded_rectangle([cx - max(widths) / 2 - pad, y0 - pad * 0.55, cx + max(widths) / 2 + pad, y0 + heights + pad * 0.35],
                             radius=12, fill=(6, 8, 12, 150 if not upright else 140))
        img = Image.alpha_composite(img, plate)
        d = ImageDraw.Draw(img)
    for k, t in enumerate(lines):
        d.text((cx - widths[k] / 2, y0 + k * lh), t, font=f, fill=IVORY + (255,))
    return shadowed(img, 4, 0.8)


# ------------------------------------------------------------------ picture
def shot_at(t):
    for e in EDIT:
        if e[0] <= t < e[0] + e[1]:
            return e
    return None


def captions():
    """(start, end, lines, height of its middle) for the upright cut's Spanish captions."""
    out = []
    for key, start in SAY.items():
        if key not in CAP_BREAK:
            continue
        dur = line_len(key)
        parts = CAP_BREAK[key]
        if len(parts) == 1:
            out.append((start, start + dur + 0.25, parts[0], CAP_Y.get((key, 0), 0.60)))
        else:
            # split where he breathes, near the share of characters
            n0 = sum(len(s) for s in parts[0])
            n1 = sum(len(s) for s in parts[1])
            mid = start + pause_in(key, n0 / (n0 + n1))
            out.append((start, mid, parts[0], CAP_Y.get((key, 0), 0.60)))
            out.append((mid, start + dur + 0.3, parts[1], CAP_Y.get((key, 1), 0.60)))
    return no_overlap(out)


def pause_in(key, share, edge="mid"):
    """Where the narrator breathes in a line: the middle of the quiet stretch (under -32 dB of the line's loudest 20 ms)
    nearest `share` of the way through it, in seconds from its start; by the share itself if he does not stop."""
    import soundfile as sf
    x, rate = sf.read(os.path.join(VOICE, "line_%s.wav" % key))
    if x.ndim > 1:
        x = x.mean(axis=1)
    hop = int(0.02 * rate)
    n = len(x) // hop
    env = np.array([np.sqrt(np.mean(x[k * hop:(k + 1) * hop] ** 2)) for k in range(n)]) + 1e-9
    quiet = 20 * np.log10(env / env.max()) < -32
    runs, k = [], 0
    while k < n:
        if quiet[k]:
            j = k
            while j < n and quiet[j]:
                j += 1
            if j - k >= 4 and k > 0 and j < n:
                runs.append(((k + j) / 2 * hop / rate, (j - k) * hop / rate))
            k = j
        else:
            k += 1
    want = share * len(x) / rate
    if not runs:
        return want
    mid, length = min(runs, key=lambda r: abs(r[0] - want) - 0.5 * r[1])
    return mid + (length / 2 if edge == "end" else 0.0)


def subtitles_en():
    out = []
    for key, start in SAY.items():
        es, en = LINES[key]
        if key == "09":
            continue
        dur = line_len(key)
        if key in SUB_BREAK:
            a, b = SUB_BREAK[key]
            mid = start + pause_in(key, len(a) / (len(a) + len(b)))
            out.append((start, mid, [a]))
            out.append((mid, start + dur + 0.35, [b]))
        else:
            out.append((start, start + dur + 0.35, [en]))
    # the end card's word, in English
    end = [e for e in EDIT if e[4] == "end"]
    if end:
        out.append((end[0][0] + 0.5, end[0][0] + end[0][1] - 0.4, ["PLAY IT FREE"]))
    return no_overlap(out)


def no_overlap(subs):
    """Each subtitle off a moment before the next comes on."""
    subs = sorted(subs, key=lambda s: s[0])
    return [(s[0], min(s[1], subs[k + 1][0] - 0.04) if k + 1 < len(subs) else s[1]) + tuple(s[2:]) for k, s in enumerate(subs)]


def bars_for(t):
    """The letterbox at time t: the film's bars, drawn back over a quarter second as the game's shot comes in, and out
    again as it ends."""
    if CUT != "wide":
        return 0
    e = shot_at(t)
    if e is None:
        return SCOPE_BAR
    start, dur, take, _, kind = e
    if kind != "game":
        return SCOPE_BAR
    k = min(1.0, (t - start) / 0.28, (start + dur - t) / 0.28)
    k = max(0.0, k)
    k = k * k * (3 - 2 * k)
    return int(round(SCOPE_BAR * (1.0 - k)))


def render_picture(path, caps=None):
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS),
                            "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "11", "-pix_fmt", "yuv420p", path], stdin=subprocess.PIPE)
    title_l = Layer(title_card())
    sub_l = Layer(title_card(True))
    end_l = Layer(end_card())
    cap_layers = [(a, b, Layer(subtitle_img(list(lines), upright=True, y_mid=y))) for (a, b, lines, y) in (caps or [])]
    n = 0
    for (start, dur, take, in_s, kind) in EDIT:
        frames = int(round((start + dur) * FPS)) - int(round(start * FPS))
        for i, f in enumerate(take_frames(take, in_point(take, in_s) if take else 0.0, frames, kind)):
            t = (int(round(start * FPS)) + i) / FPS
            ts = i / FPS
            x = f if f.flags.writeable else f.copy()
            if kind in ("cine", "title"):
                x = film_look(x, n)
            if kind == "title":
                # a hit to black and the title on it; its line after it; then the buried square in the blizzard
                # comes up faintly behind them
                dim = 0.34 * min(1.0, max(0.0, (ts - 0.7) / 1.6)) ** 1.5
                x = (x.astype(np.float32) * dim).astype(np.uint8)
                hit = min(1.0, ts / 0.06)
                x = title_l.blend(x, hit)
                x = sub_l.blend(x, min(1.0, max(0.0, (ts - 0.9) / 0.6)))
                fade = min(1.0, max(0.0, (dur - ts) / 0.5))
                x = (x.astype(np.float32) * fade).astype(np.uint8)
            elif kind == "end":
                x = np.zeros((H, W, 3), np.uint8)
                x = end_l.blend(x, min(1.0, ts / 0.6) * min(1.0, max(0.0, (dur - ts) / 0.7)))
            if n < 24 and start == 0.0:
                x = (x.astype(np.float32) * (n / 24.0) ** 1.5).astype(np.uint8)
            x = letterbox(x, bars_for(t) if kind != "end" else 0)
            for (a, b, lay) in cap_layers:
                if a <= t < b:
                    fa = min(1.0, (t - a) / 0.12, (b - t) / 0.12)
                    x = lay.blend(x, max(0.0, fa))
            enc.stdin.write(np.ascontiguousarray(x).tobytes())
            n += 1
    enc.stdin.close()
    enc.wait()
    print("picture", path, n, "frames of", NFRAMES)


def sheet(path):
    tiles = []
    for idx, (start, dur, take, in_s, kind) in enumerate(EDIT):
        mid = int(round(dur * FPS / 2))
        f = None
        for i, fr in enumerate(take_frames(take, in_point(take, in_s) if take else 0.0, mid + 1, kind)):
            f = fr
        if kind in ("cine", "title"):
            f = film_look(f, idx)
        f = letterbox(f, SCOPE_BAR if kind in ("cine", "title") else 0)
        im = Image.fromarray(f).resize((W // 5, H // 5))
        d = ImageDraw.Draw(im)
        d.text((6, 4), "%02d %s %.1fs" % (idx + 1, take or "end", start), fill=(255, 220, 120), font=font("semi", 22))
        tiles.append(im)
    cols = 5 if CUT == "wide" else 6
    tw, th = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet_img = Image.new("RGB", (cols * tw, rows * th), (20, 20, 20))
    for k, im in enumerate(tiles):
        sheet_img.paste(im, ((k % cols) * tw, (k // cols) * th))
    sheet_img.save(path, quality=90)
    print("sheet", path)


# ------------------------------------------------------------------ sound
SR = 48000


def cues():
    """The score's cue sheet: the times its sections start (hc2_music.py)."""
    def shot_start(take, nth=0):
        hits = [e[0] for e in FULL_EDIT if e[2] == take]
        return hits[nth] if len(hits) > nth else None
    c = {"total": FULL_TOTAL}
    if CUT == "wide":
        c.update({"snow": SAY["02"] - 0.4, "people": SAY["03"], "fall": SAY["04"], "silence_end": SAY["05a"] - 0.3,
                  "neighbours": SAY["05a"] - 0.2, "juan": shot_start("juan"), "tremble": shot_start("beasts"),
                  "beasts": SAY["08"], "title": shot_start("title_bg"), "end": shot_start(None)})
    else:
        c.update({"snow": 0.4, "people": 3.6, "fall": SAY["04"], "silence_end": SAY["07"] - 0.6, "neighbours": SAY["07"] - 0.5,
                  "juan": shot_start("juan"), "tremble": SAY["08"] - 1.6, "beasts": SAY["08"], "title": shot_start("title_bg"),
                  "end": shot_start(None)})
    # the word "caía" (the heartbeat's hit): where the narrator takes it up again after "Quien la tocaba,"
    if "04" in SAY:
        c["caia"] = SAY["04"] + pause_in("04", 0.62, "end")
    fire = [e for e in FULL_EDIT if e[2] == "fire"]
    if fire:
        e = fire[0]
        c["shot"] = e[0] + (in_point("fire", "shot+0") - in_point("fire", e[3]))
    return c


def sfx_list(c):
    """The game's own sound files where the picture has them: (time, file, gain dB, speed)."""
    out = []
    ev = lambda take, name: events.get((take, name))
    for e in EDIT:
        start, dur, take, in_s, kind = e
        t_in = in_point(take, in_s) if take else 0.0
        if take == "tram":
            out += [(start + 0.9, "alarm_bell.wav", -4.0, 1.0), (start + 1.22, "alarm_bell.wav", -8.0, 0.985)]
        if take == "fall" and ev("fall", "fallen") is not None:
            at = start + ev("fall", "fallen") / FPS - t_in
            if start <= at < start + dur:
                out += [(at + 0.25, "act_body_fall.wav", -12.0, 0.9)]
        if take == "juan":
            for k, at in enumerate(np.arange(start + 0.25, start + dur, 0.52)):
                out.append((float(at), "foot_snow_%d.wav" % (k % 3 + 1), -13.0, 0.92))
        if take in ("beasts", "legs", "rear"):
            # its steps: the game's own steps in the snow, slowed into something heavy; the click of its legs
            step = 0.42 if take != "legs" else 0.36
            for k, at in enumerate(np.arange(start + (0.6 if take == "beasts" and t_in < 1.0 else 0.15), start + dur, step)):
                out.append((float(at), "foot_snow_%d.wav" % (k % 3 + 1), -9.0, 0.55))
                if k % 2 == 1:
                    out.append((float(at) + 0.11, "act_peg_tap_%d.wav" % (k % 2 + 1), -17.0, 0.7))
            if take == "rear":
                out.append((start + 0.15, "act_heave.wav", -10.0, 0.6))
        if take == "fire" and "shot" in c:
            out += [(c["shot"], "gun_rifle.wav", -6.0, 1.0), (c["shot"] + 0.05, "gun_hit.wav", -8.0, 0.8),
                    (c["shot"] + 0.62, "gun_rifle_bolt.wav", -9.0, 1.0)]
        if kind == "game":
            out.append((start + 0.3, "ui_tap.wav", -18.0, 1.0))
        if take == "g_lead":
            # Lechuza at the subte's service gate (his card says ABRIR LA REJA): the picks, then the gate giving, off
            for k, at in enumerate((0.9, 1.25, 1.6, 1.9)):
                out.append((start + at, "act_pick_%d.wav" % (k % 3 + 1), -20.0, 1.0))
            out.append((start + 2.35, "act_unlock.wav", -13.0, 1.0))
        if take == "shelter":
            out.append((start + 0.2, "foot_snow_2.wav", -20.0, 1.0))
    return [o for o in out if o[0] < TOTAL - 0.1]


def mix(out_wav, cue_path):
    music = os.path.join(OUTDIR, "music_%s.wav" % CUT)
    subprocess.run([sys.executable, os.path.join(HERE, "hc2_music.py"), music, cue_path], check=True)
    c = json.load(open(cue_path))
    inputs, chains = [], []
    k = 0
    # the narration: each line at its start, as one track
    voice_parts = []
    for key, start in SAY.items():
        inputs += ["-i", os.path.join(VOICE, "line_%s.wav" % key)]
        ms = int(start * 1000)
        chains.append("[%d:a]aresample=48000,aformat=channel_layouts=mono,adelay=%d,volume=1.0[v%d]" % (k, ms, k))
        voice_parts.append("[v%d]" % k)
        k += 1
    chains.append("%samix=inputs=%d:normalize=0:duration=longest,apad=whole_dur=%.3f,atrim=duration=%.3f,"
                  "highpass=f=70,equalizer=f=180:t=q:w=1.0:g=1.5,equalizer=f=3200:t=q:w=1.2:g=2.0,"
                  "acompressor=threshold=0.08:ratio=3:attack=8:release=180:makeup=1.6,pan=stereo|c0=c0|c1=c0[voice]" % (
                      "".join(voice_parts), len(voice_parts), TOTAL, TOTAL))
    # the game's sound: the wind under it all, the effects where the picture has them
    sfx_parts = []
    inputs += ["-stream_loop", "-1", "-i", AUDIO + "amb_wind.wav"]
    wind_end = c.get("title", TOTAL)
    chains.append("[%d:a]aresample=48000,atrim=duration=%.3f,afade=t=in:d=2.5,afade=t=out:st=%.3f:d=1.5,volume=-17dB,aformat=channel_layouts=stereo[w]" % (
        k, wind_end + 1.0, max(0.0, wind_end - 0.5)))
    sfx_parts.append("[w]")
    k += 1
    for (at, f, gain, speed) in sfx_list(c):
        inputs += ["-i", AUDIO + f]
        ms = int(at * 1000)
        rate = int(48000 * speed)
        # the rifle's crack softened above 10 kHz: its first edge is what an AAC encoder overshoots by dBs
        soft = ",lowpass=f=10000:p=2" if f == "gun_rifle.wav" else ""
        chains.append("[%d:a]aresample=48000,asetrate=%d,aresample=48000%s,volume=%.1fdB,aformat=channel_layouts=stereo,adelay=%d|%d[s%d]" % (
            k, rate, soft, gain, ms, ms, k))
        sfx_parts.append("[s%d]" % k)
        k += 1
    chains.append("%samix=inputs=%d:normalize=0:duration=longest,apad=whole_dur=%.3f,atrim=duration=%.3f[sfx]" % (
        "".join(sfx_parts), len(sfx_parts), TOTAL, TOTAL))
    inputs += ["-i", music]
    chains.append("[%d:a]aresample=48000,volume=-4dB[mus]" % k)
    k += 1
    # the score and the effects give way under the narrator
    chains.append("[voice]asplit=3[vo][key1][key2]")
    chains.append("[mus][key1]sidechaincompress=threshold=0.015:ratio=5:attack=25:release=450:makeup=1[mduck]")
    chains.append("[sfx][key2]sidechaincompress=threshold=0.02:ratio=2.5:attack=20:release=300:makeup=1[sduck]")
    chains.append("[vo][mduck][sduck]amix=inputs=3:normalize=0:duration=longest,atrim=duration=%.3f[out]" % TOTAL)
    pre = os.path.join(OUTDIR, "premix_%s.wav" % CUT)
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains), "-map", "[out]", "-ar", "48000",
                                                               "-ac", "2", "-c:a", "pcm_f32le", pre], check=True)
    # -14 LUFS; the peaks held to -2.2 dBFS before AAC, which overshoots a little: -1 dBTP or under in the films
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", pre, "-af", "loudnorm=I=-14:TP=-2.0:LRA=11:print_format=json",
                            "-f", "null", "-"], capture_output=True, text=True).stderr
    js = json.loads(probe[probe.rindex("{"):probe.rindex("}") + 1])
    ln = ("loudnorm=I=-14:TP=-2.0:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true" % (
        js["input_i"], js["input_tp"], js["input_lra"], js["input_thresh"], js["target_offset"]))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", pre, "-af", ln + ",alimiter=limit=0.775:attack=2:release=60:level=disabled,aresample=48000",
                    "-ar", "48000", "-c:a", "pcm_s24le", out_wav], check=True)
    os.remove(pre)
    print("mix", out_wav, "premix", js["input_i"], "LUFS", js["input_tp"], "dBTP")


def encode(picture, sound, out, kbps, overlay_subs=None):
    """H.264 High, yuv420p, two passes at `kbps`, AAC 48 kHz stereo; subtitles laid over from PNGs if given."""
    passlog = os.path.join(OUTDIR, "pass_" + CUT)
    vf_inputs, fc = [], None
    if overlay_subs:
        chain = "[0:v]null[b0]"
        for j, (a, b, png) in enumerate(overlay_subs):
            vf_inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % TOTAL, "-i", png]
            chain += ";[b%d][%d:v]overlay=0:0:enable='between(t,%.3f,%.3f)'[b%d]" % (j, j + 1, a, b, j + 1)
        fc = chain
        last = "[b%d]" % len(overlay_subs)
    common = ["-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-b:v", "%dk" % kbps, "-maxrate", "%dk" % int(kbps * 1.5),
              "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", "-r", str(FPS), "-g", "48", "-passlogfile", passlog]
    base = ["ffmpeg", "-v", "error", "-y", "-i", picture] + vf_inputs
    maps = (["-filter_complex", fc, "-map", last] if fc else ["-map", "0:v"])
    subprocess.run(base + maps + common + ["-pass", "1", "-an", "-f", "mp4", "/dev/null"], check=True)
    audio_idx = 1 + len(vf_inputs) // 8 if overlay_subs else 1
    subprocess.run(base + ["-i", sound] + maps + ["-map", "%d:a" % (1 + (len(overlay_subs) if overlay_subs else 0))] + common +
                   ["-pass", "2", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-shortest", out], check=True)
    for ext in ("-0.log", "-0.log.mbtree"):
        if os.path.exists(passlog + ext):
            os.remove(passlog + ext)
    peak_guard(out, sound)
    print("encoded", out, "%.1f MB" % (os.path.getsize(out) / 1e6))


def loudness(path):
    """Integrated loudness (LUFS) and true peak (dBTP) of a file's sound, as ffmpeg's ebur128 measures them."""
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vn", "-af", "ebur128=peak=true:framelog=quiet",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    tail = err[err.rindex("Summary"):]
    i = float(tail.split("I:")[1].split("LUFS")[0])
    tp = float(tail.split("Peak:")[1].split("dBFS")[0])
    return i, tp


def peak_guard(out, sound, ceiling=-1.0):
    """The AAC encoder overshoots the mix's peaks a little (most on a sharp transient): if the film's true peak is over
    `ceiling`, its sound is made again that much quieter (and a hair more) and put back with the picture untouched."""
    i, tp = loudness(out)
    if tp <= ceiling:
        print("sound", os.path.basename(out), "%.1f LUFS %.1f dBTP" % (i, tp))
        return
    tmp = out + ".tmp.mp4"
    cut = tp - ceiling + 0.3
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", out, "-i", sound, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                    "-af", "volume=-%.2fdB" % cut, "-c:a", "aac", "-b:a", "256k" if "WhatsApp" not in out else "128k",
                    "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-shortest", tmp], check=True)
    os.replace(tmp, out)
    i2, tp2 = loudness(out)
    print("sound", os.path.basename(out), "was %.1f dBTP, down %.1f dB: %.1f LUFS %.1f dBTP" % (tp, cut, i2, tp2))


def main():
    if SHEET:
        sheet(os.path.join(OUTDIR, "contact_%s.jpg" % CUT))
        return
    cue_path = os.path.join(OUTDIR, "cues_%s.json" % CUT)
    json.dump(cues(), open(cue_path, "w"), indent=1)
    sound = os.path.join(OUTDIR, "mix_%s.wav" % CUT)
    mix(sound, cue_path)
    if "--sound-only" in sys.argv:
        return
    if "--light-only" in sys.argv:
        light(os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9.mp4"), os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9 (WhatsApp).mp4"))
        return
    picture = os.path.join(OUTDIR, "master_%s.mkv" % CUT)
    if CUT == "wide":
        if not os.path.exists(picture) or "--keep-picture" not in sys.argv:
            render_picture(picture)
        encode(picture, sound, os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9.mp4"), 12000)
        subs = []
        for j, (a, b, lines) in enumerate(subtitles_en()):
            low = (shot_at(a) or (0, 0, None, 0, "cine"))[4] != "game" and (shot_at(min(b, TOTAL - 0.01)) or (0, 0, None, 0, "cine"))[4] != "game"
            png = os.path.join(OUTDIR, "sub_%02d.png" % j)
            subtitle_img(lines, upright=False, low_band=low).save(png)
            subs.append((a, b, png))
        encode(picture, sound, os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9 (English subtitles).mp4"), 12000, subs)
        for _, _, png in subs:
            os.remove(png)
        light(os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9.mp4"), os.path.join(OUTDIR, "Hora Cero - trailer cinematic 16x9 (WhatsApp).mp4"))
    else:
        if not os.path.exists(picture) or "--keep-picture" not in sys.argv:
            render_picture(picture, captions())
        encode(picture, sound, os.path.join(OUTDIR, "Hora Cero - trailer 9x16.mp4"), 10000)


def light(src, out, limit_mb=15.2):
    """A copy small enough for WhatsApp (16 MB): 1280 x 720, two passes at the rate that fits, AAC 128k."""
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src],
                               capture_output=True, text=True).stdout.strip())
    kbps = int(limit_mb * 8 * 1000 / dur * 0.96) - 128
    passlog = os.path.join(OUTDIR, "pass_light")
    common = ["-vf", "scale=1280:720:flags=lanczos", "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-b:v", "%dk" % kbps,
              "-maxrate", "%dk" % int(kbps * 1.6), "-bufsize", "%dk" % (kbps * 2), "-pix_fmt", "yuv420p", "-passlogfile", passlog]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src] + common + ["-pass", "1", "-an", "-f", "mp4", "/dev/null"], check=True)
    # the sound from the mix itself (not the film's AAC again)
    mixwav = os.path.join(OUTDIR, "mix_%s.wav" % CUT)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-i", mixwav, "-map", "0:v", "-map", "1:a"] + common +
                   ["-pass", "2", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-shortest", out],
                   check=True)
    for ext in ("-0.log", "-0.log.mbtree"):
        if os.path.exists(passlog + ext):
            os.remove(passlog + ext)
    peak_guard(out, os.path.join(OUTDIR, "mix_%s.wav" % CUT))
    print("encoded", out, "%.1f MB" % (os.path.getsize(out) / 1e6), "at", kbps, "kbps")


if __name__ == "__main__":
    main()
