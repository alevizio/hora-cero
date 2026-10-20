"""Edit, title and finish the Hora Cero trailers (Spanish, Rioplatense) from the takes of horacero_director.gd.
usage: compose_horacero.py <takes_dir> <out.mp4> [wide|upright] [--music music.wav]
  wide:    1920 x 1080, 55.2 s.   upright: 1080 x 1920 (Reels, TikTok, Stories), 27.6 s, its own takes (framed upright).
Takes are <shot>.mkv (or .avi) with "MARK <take> <first> <last>" lines in <shot>.log. The score is horacero_music.py's
(its beats are this edit's cuts: 100 BPM, a beat 0.6 s); the game's own sound comes from the takes, cut like the
picture, with a few of the game's sound files and voice lines laid on top; the music sits under the effects and the
mix is brought to -14 LUFS (integrated), -1 dBTP.
The comic's title never appears: the game is HORA CERO, its line "Invasión Buenos Aires".
"""
import subprocess, sys, os, re, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = sys.argv[1]
OUT = sys.argv[2]
CUT = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else "wide"
MUSIC = sys.argv[sys.argv.index("--music") + 1] if "--music" in sys.argv else None
W, H = (1920, 1080) if CUT == "wide" else (1080, 1920)
FPS = 30
S = min(W, H) / 1080.0
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", "..", "godot"))
FONTS = os.path.join(GODOT, "assets", "fonts") + "/"
AUDIO = os.path.join(GODOT, "assets", "audio") + "/"
ICON = os.path.join(GODOT, "icon.png")
PAPER = (236, 226, 200)
BRASS = (224, 173, 76)
RED = (217, 72, 47)
COLD = (184, 207, 230)
INK = (14, 18, 26)

# ------------------------------------------------------------------ takes
marks = {}
shots = {}      # the frame of a take on which Juan Salvo's shot went off (horacero_director.gd's "SHOT" line)
for name in os.listdir(SRC):
    if name.endswith(".log"):
        shot = name[:-4]
        for line in open(os.path.join(SRC, name)):
            m = re.match(r"MARK (\w+) (\d+) (\d+)", line)
            if m:
                marks[m.group(1)] = (shot, int(m.group(2)), int(m.group(3)))
            m = re.match(r"SHOT (\w+) (\d+)", line)
            if m:
                shots[m.group(1)] = int(m.group(2))


def in_point(take, in_s):
    """Seconds into a take: a number, or "shot+x" / "shot-x" from the moment the shot went off in it."""
    if isinstance(in_s, str) and in_s.startswith("shot"):
        return shots.get(take, 30) / FPS + float(in_s[4:] or 0)
    return float(in_s)


def take_file(shot):
    for ext in (".mkv", ".avi", ".mp4"):
        p = os.path.join(SRC, shot + ext)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(shot)


# (start, duration, take, in-point seconds, caption) on the beat (100 BPM: 0.6 s). Captions: "c:" a typed line, "t:" a
# stencil title slammed in, "who:" a character's tag, "strike" the rifle's flash, "end" the end card.
if CUT == "wide":
    EDIT = [
        (0.0, 4.8, "open", 0.4, "c:Buenos Aires, 1958."),
        (4.8, 3.6, "rosada", 0.4, "c:Una noche de invierno."),
        (8.4, 1.8, "cabildo", 0.4, ""),
        (10.2, 1.8, "people", 0.3, "c:Empieza a nevar."),
        (12.0, 2.4, "wave2", 0.8, "t:LA NIEVE\nMATA"),
        (14.4, 2.4, "hornero", 0.6, "who:hornero"),
        (16.8, 2.4, "benteveo", 0.3, "who:benteveo"),
        (19.2, 2.4, "lechuza", 0.2, "who:lechuza"),
        (21.6, 2.4, "bigua", 0.2, "who:bigua"),
        (24.0, 2.4, "subte", 0.2, "t:NADIE\nSALE SOLO"),
        (26.4, 2.4, "juan_in", 0.3, "who:salvo"),
        (28.8, 1.8, "carry_hud", 0.3, "c:La nieve no lo toca."),
        (30.6, 1.8, "carry", 0.9, ""),
        (32.4, 2.4, "rush", 0.3, "c:Algo sube por las avenidas."),
        (34.8, 2.4, "rush_hud", 0.3, ""),
        (37.2, 2.4, "bell", 0.1, "c:La campana los llama."),
        (39.6, 1.2, "aim", "shot-1.2", ""),
        (40.8, 1.2, "aim", "shot-0.04", "strike"),
        (42.0, 2.4, "ria_boca", 0.3, "c:Y la noche sigue en La Boca."),
        (44.4, 2.4, "ria_gondola", 0.3, ""),
        (46.8, 8.4, "end", 0.5, "end"),
    ]
    TOTAL = 55.2
else:
    EDIT = [
        (0.0, 2.4, "rosada", 0.2, "c:Buenos Aires, 1958."),
        (2.4, 2.4, "wave2", 0.8, "t:LA NIEVE\nMATA"),
        (4.8, 2.4, "benteveo", 0.2, "who:benteveo"),
        (7.2, 2.4, "hornero", 0.2, "who:hornero"),
        (9.6, 2.4, "subte", 0.2, "t:NADIE\nSALE SOLO"),
        (12.0, 2.4, "carry_hud", 0.2, "who:salvo_carry"),
        (14.4, 4.8, "rush", 0.2, "c:Algo sube por\nlas avenidas."),
        (19.2, 1.2, "aim", "shot-1.2", ""),
        (20.4, 2.4, "aim", "shot-0.04", "strike"),
        (22.8, 4.8, "end", 0.5, "end"),
    ]
    TOTAL = 27.6
# --upto S: only the first S seconds (to look at a part of the edit quickly), --only a,b: those shots alone
if "--upto" in sys.argv:
    upto = float(sys.argv[sys.argv.index("--upto") + 1])
    EDIT = [e for e in EDIT if e[0] < upto - 0.01]
    TOTAL = min(TOTAL, upto)
    last = EDIT[-1]
    EDIT[-1] = (last[0], min(last[1], TOTAL - last[0]), last[2], last[3], last[4])
NFRAMES = int(round(TOTAL * FPS))

WHO = {   # kicker (role), name, line
    "hornero": ("MOTORMAN", "HORNERO", "Lleva el tranvía y toca la campana."),
    "benteveo": ("CANILLITA", "BENTEVEO", "Un grito y lo siguen."),
    "lechuza": ("LINIERO", "LECHUZA", "Abre la reja del subte."),
    "bigua": ("BOTERO", "BIGUÁ", "Los lleva hasta el colectivo."),
    "salvo": ("CON SU TRAJE AISLANTE", "JUAN SALVO", "Entra por la Avenida de Mayo."),
    "salvo_carry": ("CON SU TRAJE AISLANTE", "JUAN SALVO", "La nieve no lo toca."),
}

# ------------------------------------------------------------------ grade
GRADE = ("curves=all='0/0 0.22/0.19 0.5/0.5 0.78/0.81 1/1',"
         "colorbalance=rs=-0.02:bs=0.03:rh=0.02:bh=-0.02,eq=saturation=1.06,vignette=angle=PI/5.6")


# A little more light on the darkest takes (gamma: above 1 lifts the shadows and mid-tones, the highlights stay).
LIFT = {"ria_boca": 1.35, "ria_gondola": 1.4, "juan_in": 1.15, "carry": 1.1}


def take_frames(take, in_s, dur, blur=False):
    n = int(round(dur * FPS))
    if take not in marks:          # a take not rendered yet: black, so the edit can be looked at before it is whole
        print("missing take", take)
        black = np.zeros((H, W, 3), np.uint8)
        for i in range(n):
            yield black
        return
    shot, first, last = marks[take]
    start = first + int(round(in_point(take, in_s) * FPS))
    n = int(round(dur * FPS))
    have = max(1, min(n, last - start + 1))
    chain = f"select='gte(n\\,{start})',setpts=N/FRAME_RATE/TB,scale={W}:{H}:flags=lanczos"
    if blur:
        chain += f",gblur=sigma={12 * S:.1f}"
    if take in LIFT:
        chain += f",lutrgb=r='255*pow(val/255\\,1/{LIFT[take]})':g='255*pow(val/255\\,1/{LIFT[take]})':b='255*pow(val/255\\,1/{LIFT[take]})'"
    chain += "," + GRADE
    cmd = ["ffmpeg", "-v", "error", "-i", take_file(shot), "-vf", chain, "-frames:v", str(have), "-f", "rawvideo",
           "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    frame = None
    for i in range(n):
        if i < have:
            raw = p.stdout.read(W * H * 3)
            if len(raw) == W * H * 3:
                frame = np.frombuffer(raw, np.uint8).reshape(H, W, 3)
        yield frame
    p.stdout.close()
    p.wait()


# ------------------------------------------------------------------ type
def font(kind, px):
    px = max(6, int(round(px * S)))
    if kind == "stencil":
        f = ImageFont.truetype(FONTS + "BigShouldersStencilDisplay-wght.ttf", px)
        try:
            f.set_variation_by_axes([800])
        except Exception:
            pass
        return f
    if kind == "semi":
        return ImageFont.truetype(FONTS + "BarlowCondensed-SemiBold.ttf", px)
    if kind == "medium":
        return ImageFont.truetype(FONTS + "BarlowCondensed-Medium.ttf", px)
    return ImageFont.truetype(FONTS + "SpecialElite-Regular.ttf", px)


def tracked(draw, xy, text, fnt, fill, tracking=0.0, anchor="l"):
    tr = tracking * S
    widths = [draw.textlength(ch, font=fnt) for ch in text]
    total = sum(widths) + tr * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    elif anchor == "r":
        x -= total
    for ch, wd in zip(text, widths):
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += wd + tr
    return total


def text_width(text, fnt, tracking=0.0):
    d = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    return sum(d.textlength(ch, font=fnt) for ch in text) + tracking * S * (len(text) - 1)


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def shadowed(img, blur=10, strength=0.85):
    alpha = img.split()[3]
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dark = Image.new("RGBA", img.size, (6, 8, 14, 255))
    spread = alpha.filter(ImageFilter.GaussianBlur(blur * S)).point(lambda v: min(255, int(v * 2.2 * strength)))
    sh.paste(dark, (0, 0), spread)
    return Image.alpha_composite(sh, img)


# Takes with the game's HUD over them: a typed line goes higher there, clear of the portraits and the action bar.
HUD_TAKES = {"hornero", "benteveo", "lechuza", "bigua", "carry_hud", "cross", "rush_hud", "bell"}


def typed_card(text, n_chars, hud=False):
    """A typewriter line (or two), centred low: the first n_chars characters showing."""
    img = layer()
    d = ImageDraw.Draw(img)
    f = font("type", 60 if CUT == "wide" else 62)
    lines = text.split("\n")
    y0 = H * ((0.81 if not hud else 0.56) if CUT == "wide" else (0.14 if not hud else 0.50))
    shown = n_chars
    for k, ln in enumerate(lines):
        full = d.textlength(ln, font=f)
        part = ln[:max(0, shown)]
        d.text((W / 2 - full / 2, y0 + k * 74 * S), part, font=f, fill=PAPER + (255,))
        shown -= len(ln)
    return shadowed(img, 14, 1.0)


def big_title(text):
    img = layer()
    d = ImageDraw.Draw(img)
    lines = text.split("\n")
    px = 200 if CUT == "wide" else 190
    f = font("stencil", px)
    lh = px * 0.92 * S
    # high in the frame, over the sky and the buildings: the action (somebody going down, people on a stair) stays clear
    y0 = H * (0.30 if CUT == "wide" else 0.24) - lh * len(lines) / 2
    for k, ln in enumerate(lines):
        tracked(d, (W / 2, y0 + k * lh), ln, f, PAPER + (255,), 6, "m")
    wd = max(text_width(ln, f, 6) for ln in lines)
    d.rectangle([W / 2 - wd / 2, y0 - 22 * S, W / 2 + wd / 2, y0 - 16 * S], fill=RED + (235,))
    return shadowed(img, 22, 1.0)


def who_tag(key):
    kicker, name, line = WHO[key]
    img = layer()
    d = ImageDraw.Draw(img)
    fk, fn, fl = font("semi", 30), font("stencil", 104), font("type", 30)
    if CUT == "wide":
        x, y = 92 * S, 380 * S
    else:
        x, y = 70 * S, 560 * S
    nh = 100 * S
    d.rectangle([x - 26 * S, y + 4 * S, x - 20 * S, y + 34 * S + nh + 56 * S], fill=BRASS + (255,))
    tracked(d, (x, y), kicker, fk, BRASS + (255,), 5)
    tracked(d, (x, y + 30 * S), name, fn, PAPER + (255,), 3)
    d.text((x, y + 34 * S + nh + 10 * S), line, font=fl, fill=PAPER + (240,))
    return shadowed(img, 14, 1.0)


def end_card():
    img = layer()
    d = ImageDraw.Draw(img)
    cx = W / 2
    top = 210 * S if CUT == "wide" else 560 * S
    size = int(170 * S)
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255)
    img.paste(icon, (int(cx - size / 2), int(top)), mask)
    fm = font("stencil", 230 if CUT == "wide" else 200)
    fs, fk, fu = font("semi", 46), font("type", 38), font("semi", 40)
    y = top + size + 26 * S
    wd = text_width("HORA CERO", fm, 8)
    tracked(d, (cx, y), "HORA CERO", fm, PAPER + (255,), 8, "m")
    y += (236 if CUT == "wide" else 206) * S
    d.rectangle([cx - wd / 2, y, cx + wd / 2, y + 3 * S], fill=PAPER + (220,))
    tracked(d, (cx, y + 22 * S), "INVASIÓN BUENOS AIRES", fs, BRASS + (255,), 12, "m")
    y += 120 * S
    line = "Jugalo gratis en el navegador"
    d.text((cx - d.textlength(line, font=fk) / 2, y), line, font=fk, fill=PAPER + (245,))
    tracked(d, (cx, y + 58 * S), "HORACERO.APP", fu, PAPER + (255,), 8, "m")
    return shadowed(img, 20, 1.0)


# ------------------------------------------------------------------ compositing
class Layer:
    def __init__(self, img):
        box = img.getbbox() or (0, 0, 1, 1)
        arr = np.asarray(img.crop(box), np.float32) / 255.0
        self.x0, self.y0, self.x1, self.y1 = box
        self.a = arr[..., 3:4]
        self.rgb = arr[..., :3] * self.a * 255.0

    def blend(self, frame, alpha=1.0, dx=0):
        if alpha <= 0.003:
            return
        x0, x1 = self.x0 + dx, self.x1 + dx
        sx0 = max(0, -x0)
        x0c, x1c = max(0, x0), min(W, x1)
        if x1c <= x0c:
            return
        a = self.a[:, sx0:sx0 + (x1c - x0c)] * alpha
        region = frame[self.y0:self.y1, x0c:x1c].astype(np.float32)
        region = region * (1 - a) + self.rgb[:, sx0:sx0 + (x1c - x0c)] * alpha
        frame[self.y0:self.y1, x0c:x1c] = np.clip(region + 0.5, 0, 255).astype(np.uint8)


def scaled(img, scale):
    w2, h2 = int(W * scale), int(H * scale)
    big = img.resize((w2, h2), Image.BILINEAR)
    left, top = (w2 - W) // 2, (h2 - H) // 2
    return big.crop((left, top, left + W, top + H))


def gain(frame, g):
    lut = np.clip(np.arange(256, dtype=np.float32) * g, 0, 255).astype(np.uint8)
    return lut[frame]


def lift(frame, amount):
    lut = np.clip(np.arange(256, dtype=np.float32) + amount * 255.0, 0, 255).astype(np.uint8)
    return lut[frame]


def shake(frame, dx, dy, z=1.025):
    h, w = frame.shape[:2]
    big = np.asarray(Image.fromarray(frame).resize((int(w * z), int(h * z)), Image.BILINEAR))
    x0 = int(round((big.shape[1] - w) / 2 + dx))
    y0 = int(round((big.shape[0] - h) / 2 + dy))
    x0 = max(0, min(big.shape[1] - w, x0))
    y0 = max(0, min(big.shape[0] - h, y0))
    return np.ascontiguousarray(big[y0:y0 + h, x0:x0 + w])


def ease_out(t):
    t = min(1.0, max(0.0, t))
    return 1 - (1 - t) ** 3


yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
if CUT == "wide":
    WASH_WHO = np.clip(1.0 - xx / (W * 0.42), 0, 1) * np.clip(1.0 - np.abs(yy - H * 0.46) / (H * 0.24), 0, 1) * 0.62
else:
    WASH_WHO = np.clip(1.0 - xx / (W * 0.85), 0, 1) * np.clip(1.0 - np.abs(yy - H * 0.36) / (H * 0.13), 0, 1) * 0.62
WASH_LOW = (np.clip((yy - H * 0.58) / (H * 0.30), 0, 1) * np.clip(1 - (yy - H * 0.9) / (H * 0.1), 0, 1) * 0.55 if CUT == "wide"
            else np.clip(1 - np.abs(yy - H * 0.17) / (H * 0.09), 0, 1) * 0.5)
del yy, xx


class Wash:
    def __init__(self, field):
        ys, xs = np.where(field > 0.004)
        self.y0, self.y1, self.x0, self.x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        self.f = field[self.y0:self.y1, self.x0:self.x1][..., None]

    def apply(self, frame, amount):
        if amount <= 0.003:
            return
        region = frame[self.y0:self.y1, self.x0:self.x1].astype(np.float32) * (1 - self.f * amount)
        frame[self.y0:self.y1, self.x0:self.x1] = (region + 0.5).astype(np.uint8)


W_WHO, W_LOW = Wash(WASH_WHO), Wash(WASH_LOW)
END = end_card()
END_L = Layer(END)
_cache = {}


def cached(key, make):
    if key not in _cache:
        _cache[key] = Layer(make())
    return _cache[key]


def render():
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-vf", "noise=c0s=5:c0f=t+u", "-c:v", "libx264", "-preset", "slow",
                            "-crf", "19", "-maxrate", "11M", "-bufsize", "22M", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                            OUT + ".video.mp4"],
                           stdin=subprocess.PIPE)
    n = 0
    for start, dur, take, in_s, cap in EDIT:
        for i, f in enumerate(take_frames(take, in_s, dur, blur=(cap == "end"))):
            t = i / FPS
            x = f.copy()
            if cap == "end":
                x = gain(x, 0.34)
                a = ease_out(t / 0.6)
                sc = 1.05 - 0.05 * ease_out(t / 0.45)
                (Layer(scaled(END, sc)) if sc > 1.002 else END_L).blend(x, a)
                if t < 0.10:
                    x = lift(x, 0.45 * (1 - t / 0.10))
                x = gain(x, min(1.0, max(0.0, (dur - t) / 1.4)) ** 1.2)
            elif cap.startswith("c:"):
                text = cap[2:]
                if start == 0.0:
                    x = gain(x, min(1.0, (t / 1.2) ** 1.4))        # up from black
                t_in = 0.5 if start == 0.0 else 0.25
                chars = int(max(0, (t - t_in)) * 26)
                fade = min(1.0, max(0.0, (dur - t) / 0.25))
                if chars > 0:
                    hud = take in HUD_TAKES
                    if not hud:
                        W_LOW.apply(x, 0.8 * fade)
                    cached(("c", text, min(chars, len(text)), hud), lambda: typed_card(text, chars, hud)).blend(x, fade)
            elif cap.startswith("t:"):
                text = cap[2:]
                hit = ease_out(t / 0.18)
                fade = min(1.0, max(0.0, (dur - t) / 0.2))
                x = gain(x, 0.62)
                sc = 1.12 - 0.12 * hit
                lay = Layer(scaled(big_title(text), sc)) if sc > 1.002 else cached(("t", text), lambda: big_title(text))
                lay.blend(x, hit * fade)
                if t < 0.12:
                    x = lift(x, 0.45 * (1 - t / 0.12))
                if t < 0.35:
                    amp = 10 * S * (1 - t / 0.35) ** 1.5
                    x = shake(x, amp * np.sin(t * 71.0), amp * 0.7 * np.cos(t * 53.0))
            elif cap.startswith("who:"):
                key = cap[4:]
                a_in = ease_out(t / 0.27)
                a_out = min(1.0, max(0.0, (dur - t) / 0.17))
                a = a_in * a_out
                W_WHO.apply(x, a)
                cached(("w", key), lambda: who_tag(key)).blend(x, a, dx=-int(round((1 - a_in) * 46 * S)))
            elif cap == "strike":
                if t < 0.8:
                    k = (1 - t / 0.8) ** 2
                    x = np.clip(x.astype(np.int16) + (np.array([40, 26, 6]) * k).astype(np.int16), 0, 255).astype(np.uint8)
                if t < 0.5:
                    amp = 14 * S * (1 - t / 0.5) ** 1.5
                    x = shake(x, amp * np.sin(t * 71.0), amp * 0.7 * np.cos(t * 53.0))
                if t < 0.2:
                    x = lift(x, 0.5 * (1 - t / 0.2) ** 2)
            if start > 0 and cap != "end" and t < 0.07:
                x = lift(x, 0.12 * (1 - t / 0.07))
            enc.stdin.write(x.tobytes())
            n += 1
    enc.stdin.close()
    enc.wait()
    print("video frames", n, "of", NFRAMES)


# ------------------------------------------------------------------ sound
# The game's own files laid on top: (time in the film, file, gain). Voice lines in Spanish, from the four's own sets.
if CUT == "wide":
    LAYERED = [
        (14.75, "voice/es/hornero_move_1.wav", 0.9),      # "Próxima parada."
        (17.05, "voice/es/benteveo_move_1.wav", 0.9),     # "¡Vamo, vamo!"
        (19.55, "voice/es/lechuza_move_2.wav", 0.85),     # "Por lo oscuro, como siempre."
        (21.95, "voice/es/bigua_move_1.wav", 0.85),       # "Despacito, como la marea."
    ]
else:
    LAYERED = [
        (5.1, "voice/es/benteveo_move_1.wav", 0.9),
        (7.5, "voice/es/hornero_move_1.wav", 0.9),
    ]


def audio():
    """The game's sound from the takes, cut like the picture; its files on top; the score under them."""
    parts = []
    inputs = []
    k = 0
    for start, dur, take, in_s, cap in EDIT:
        if take not in marks:
            inputs += ["-f", "lavfi", "-t", f"{dur:.4f}", "-i", "anullsrc=r=48000:cl=stereo"]
            parts.append(f"[{k}:a]apad=whole_dur={dur:.4f}[a{k}]")
            k += 1
            continue
        shot, first, last = marks[take]
        t0 = (first + int(round(in_point(take, in_s) * FPS))) / FPS
        g = {"end": 0.8, "strike": 2.8}.get(cap, 2.4)
        inputs += ["-i", take_file(shot)]
        parts.append(f"[{k}:a]atrim=start={t0:.4f}:duration={dur:.4f},asetpts=PTS-STARTPTS,apad=whole_dur={dur:.4f},"
                     f"afade=t=in:d=0.04,afade=t=out:st={dur - 0.06:.4f}:d=0.06,volume={g}[a{k}]")
        k += 1
    n = len(EDIT)
    chain = ";".join(parts) + ";" + "".join(f"[a{j}]" for j in range(n)) + f"concat=n={n}:v=0:a=1[game]"
    lay = []
    for when, f, g in LAYERED:
        inputs += ["-i", AUDIO + f]
        chain += f";[{k}:a]aresample=48000,adelay={int(when * 1000)}|{int(when * 1000)},volume={g}[l{k}]"
        lay.append(f"[l{k}]")
        k += 1
    chain += ";[game]" + "".join(lay) + f"amix=inputs={1 + len(lay)}:normalize=0:duration=first[sfx]"
    if MUSIC:
        inputs += ["-i", MUSIC]
        # the score under the effects: it gives way a little whenever the game speaks up (a bell, a shot, a voice)
        chain += f";[sfx]asplit[sfx1][key];[{k}:a]volume=0.55[mus];[mus][key]sidechaincompress=threshold=0.05:ratio=3:attack=15:release=350:makeup=1[duck]"
        chain += ";[sfx1][duck]amix=inputs=2:normalize=0:duration=longest[mix]"
    else:
        chain += ";[sfx]anull[mix]"
    chain += ";[mix]atrim=duration=" + f"{TOTAL}" + ",alimiter=limit=0.9:attack=5:release=80:level=disabled[out]"
    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", chain, "-map", "[out]", "-ar", "48000",
                                                      "-ac", "2", OUT + ".premix.wav"]
    subprocess.run(cmd, check=True)
    # loudness: two passes of loudnorm to -14 LUFS, -1 dBTP
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", OUT + ".premix.wav", "-af",
                            "loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    js = json.loads(probe[probe.rindex("{"):probe.rindex("}") + 1])
    ln = (f"loudnorm=I=-14:TP=-1.0:LRA=11:measured_I={js['input_i']}:measured_TP={js['input_tp']}:"
          f"measured_LRA={js['input_lra']}:measured_thresh={js['input_thresh']}:offset={js['target_offset']}:linear=true")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", OUT + ".premix.wav", "-af", ln + ",aresample=48000",
                    OUT + ".audio.wav"], check=True)
    os.remove(OUT + ".premix.wav")


render()
audio()
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", OUT + ".video.mp4", "-i", OUT + ".audio.wav", "-c:v", "copy",
                "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", "-shortest", OUT], check=True)
os.remove(OUT + ".video.mp4")
os.remove(OUT + ".audio.wav")
print("written", OUT)
