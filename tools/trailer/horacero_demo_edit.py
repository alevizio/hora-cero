"""The gameplay demonstration for the rights holders, put together from the recordings of horacero_demo.gd: an opening
card, the launch screen and level 1 (in two recordings that join at the same instant of the same night), its end
report, the briefing and the first minute of level 2, a closing card. The game's own picture and sound, nothing added
but the cards, two small chapter lower-thirds ("Nivel 1 · Plaza de Mayo", "Nivel 2 · Riachuelo") and, at the top in the
middle (the HUD holds all four corners), "x2" or "x3" while the waits run faster than the game.
usage: horacero_demo_edit.py <plaza A dir> <plaza B dir> <riachuelo dir> <out dir> [--opening <dir>] [--sheet]
       [--films-only [--new-sound] [--keep-video]]  (from the master already made; a new sound; films made keep their picture)
       [--resound]  (no master: the game's mix made again from the recordings, every film made keeps its picture)
--opening: a recording of the same start with its own camera (the whole square as the snow begins), used up to where
it stops, the plaza's first recording picking up from that same instant.
Writes "Hora Cero - gameplay para aprobación.mp4" (1920x1080, 30 fps, H.264, AAC 192k), its 1280x720 copy for mail
or Drive (under 60 MB) and a light copy for WhatsApp (under 16 MB); each film's sound brought to -16 to -15 LUFS, -1 dBTP
or under, as it reads in the film itself (after its AAC).
--sheet writes a contact sheet (a frame every 8 s, with its time) of the finished film instead.
"""
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

A, B, R, OUT = sys.argv[1:5]
HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.normpath(os.path.join(HERE, "..", "..", "godot", "assets", "fonts")) + "/"
W, H, FPS = 1920, 1080, 30
NAME = "Hora Cero - gameplay para aprobación"
IVORY, BRASS, KHAKI = (236, 230, 210), (224, 173, 76), (179, 166, 125)
OPEN_S, CLOSE_S = 3.0, 4.0
os.makedirs(OUT, exist_ok=True)


def font(kind, px):
    if kind == "stencil":
        f = ImageFont.truetype(FONTS + "BigShouldersStencilDisplay-wght.ttf", px)
        f.set_variation_by_axes([760])
        return f
    return ImageFont.truetype(FONTS + ("BarlowCondensed-SemiBold.ttf" if kind == "semi" else "BarlowCondensed-Medium.ttf"), px)


def log_of(d, part):
    """MARK name -> (frame, game time); SPEED lines as (frame, game time, speed)."""
    marks, speeds = {}, []
    for row in open(os.path.join(d, "%s_record.log" % part)):
        p = row.split()
        if len(p) >= 4 and p[0] == "MARK":
            marks.setdefault(p[1], (int(p[2]), float(p[3][2:])))
        if len(p) >= 4 and p[0] == "SPEED":
            speeds.append((int(p[2]), float(p[3][2:]), int(p[1])))
    return marks, speeds


def frame_at(marks, speeds, t):
    """The frame of a recording at a moment of the game's clock (from its MARK play and SPEED lines)."""
    pts = sorted([(marks["play"][0], marks["play"][1], 1)] + speeds)
    base = pts[0]
    for e in pts:
        if e[1] <= t + 1e-6:
            base = e
    return int(round(base[0] + (t - base[1]) * FPS / base[2]))


def frames_in(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries",
                          "stream=nb_read_packets", "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return int(out.strip())


# ------------------------------------------------------------------ the pieces and where they join
ma, sa = log_of(A, "plaza")
mb, sb = log_of(B, "plaza")
mr, sr = log_of(R, "riachuelo")
F = lambda m: m[0]
sp = lambda speeds: [(f, k) for f, _, k in speeds]
# Shortened as they go by: a briefing card is held 6 s (it is all there to read in the PDF), the level's report 7 s,
# Riachuelo played to 78 s of its clock (the ladder set and the four over the cutting).
BRIEF_KEEP, REPORT_KEEP, RIA_TO = 6.0, 7.0, 78.0
K = lambda s: int(round(s * FPS))
mkv_a, mkv_b, mkv_r = (os.path.join(A, "plaza.mkv"), os.path.join(B, "plaza.mkv"), os.path.join(R, "riachuelo.mkv"))
pieces = [  # (file, first frame, last frame + 1, speed changes as (frame, speed), role)
    (mkv_a, F(ma["launch"]), F(ma["briefing"]) + K(BRIEF_KEEP), [], "first"),
    (mkv_a, F(ma["begin"]) - K(0.7), F(ma["end_play"]), sp(sa), "mid"),
    (mkv_b, F(mb["play"]), min(F(mb["report"]) + K(REPORT_KEEP), frames_in(mkv_b)), sp(sb), "out"),
    (mkv_r, F(mr["briefing"]), F(mr["briefing"]) + K(BRIEF_KEEP), [], "in"),
    (mkv_r, F(mr["begin"]) - K(0.7), frame_at(mr, sr, RIA_TO), sp(sr), "last"),
]
play_mark = (F(ma["briefing"]) + K(BRIEF_KEEP) - F(ma["launch"])) + (F(ma["play"]) - (F(ma["begin"]) - K(0.7)))
if "--opening" in sys.argv:
    A0 = sys.argv[sys.argv.index("--opening") + 1]
    m0, s0 = log_of(A0, "plaza")
    join = frame_at(ma, sa, m0["end_play"][1])
    mkv_0 = os.path.join(A0, "plaza.mkv")
    pieces = [(mkv_0, F(m0["launch"]), F(m0["briefing"]) + K(BRIEF_KEEP), [], "first"),
              (mkv_0, F(m0["begin"]) - K(0.7), F(m0["end_play"]), sp(s0), "mid"),
              (mkv_a, join, F(ma["end_play"]), sp(sa), "mid")] + pieces[2:]
    play_mark = (F(m0["briefing"]) + K(BRIEF_KEEP) - F(m0["launch"])) + (F(m0["play"]) - (F(m0["begin"]) - K(0.7)))
    print("opening: to t=%.2f, the first recording from its frame %d" % (m0["end_play"][1], join))
# where each piece starts in the film, and the fast stretches in film time
t = OPEN_S
starts, fast = [], []
for path, a, b, speeds, _ in pieces:
    starts.append(t)
    k_now, since = 1, a
    for frame, k in sorted(speeds) + [(b, 1)]:
        frame = min(max(frame, a), b)
        if k_now > 1 and frame > since:
            fast.append((t + (since - a) / FPS, t + (frame - a) / FPS, k_now))
        if frame >= b:
            break
        k_now, since = k, frame
    t += (b - a) / FPS
TOTAL = t + CLOSE_S
# the chapters: level 1 as its play begins (A's "play" mark), level 2 with its briefing
chapters = [("Nivel 1 · Plaza de Mayo", OPEN_S + play_mark / FPS + 0.4),
            ("Nivel 2 · Riachuelo", starts[[r for _, _, _, _, r in pieces].index("in")] + 0.4)]
print("pieces", [(os.path.basename(p), a, b, r) for p, a, b, _, r in pieces], "total %.1f s" % TOTAL)
print("fast", [(round(a, 1), round(b, 1), k) for a, b, k in fast])


# ------------------------------------------------------------------ the type
def shadow(img, blur=6, strength=0.85):
    a = img.split()[3].filter(ImageFilter.GaussianBlur(blur)).point(lambda v: min(255, int(v * strength * 1.6)))
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", img.size, (3, 4, 6, 255)), (0, 0), a)
    return Image.alpha_composite(sh, img)


def card(lines, path):
    """A card on black: lines of (text, kind, px, colour, gap above)."""
    img = Image.new("RGB", (W, H), (8, 9, 11))
    d = ImageDraw.Draw(img)
    heights = sum(px * 1.15 + gap for _, _, px, _, gap in lines)
    y = H / 2 - heights / 2
    for text, kind, px, colour, gap in lines:
        y += gap
        if text == "—rule—":
            d.rectangle([W / 2 - 34, y, W / 2 + 34, y + 4], fill=BRASS)
            y += 4
            continue
        f = font(kind, px)
        d.text((W / 2 - d.textlength(text, font=f) / 2, y), text, font=f, fill=colour)
        y += px * 1.15
    img.save(path)


def tag(text, path):
    """The speed tag: small, in the top middle of the frame (between the HUD's clock and its menu)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font("semi", 34)
    tw = d.textlength(text, font=f)
    x0, y0 = W / 2 - tw / 2 - 18, 30
    d.rounded_rectangle([x0, y0, x0 + tw + 36, y0 + 48], radius=8, fill=(14, 16, 14, 205), outline=BRASS + (255,), width=2)
    d.text((x0 + 18, y0 + 4), text, font=f, fill=IVORY + (255,))
    img.save(path)


def lower_third(text, path):
    """A chapter's lower-third: low on the left, over the frame, above the HUD's cards."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font("semi", 44)
    tw = d.textlength(text, font=f)
    x0, y0 = 48, H * 0.66
    d.rectangle([x0, y0, x0 + tw + 56, y0 + 70], fill=(10, 12, 10, 215))
    d.rectangle([x0, y0, x0 + 6, y0 + 70], fill=BRASS + (255,))
    d.text((x0 + 28, y0 + 9), text, font=f, fill=IVORY + (255,))
    shadow(img, 8, 0.5).save(path)


# ------------------------------------------------------------------ the film
def build():
    tmp = os.path.join(OUT, "parts")
    os.makedirs(tmp, exist_ok=True)
    card([("Hora Cero · Invasión Buenos Aires", "semi", 74, IVORY, 0), ("—rule—", "", 0, None, 26),
          ("— demostración de juego (versión privada, octubre de 2026)", "medium", 40, KHAKI, 30)], os.path.join(tmp, "open.png"))
    card([("Versión de prueba privada · saboteurs.app/preview/ba-xa0wg23ype", "medium", 46, IVORY, 0)], os.path.join(tmp, "close.png"))
    tag("x2", os.path.join(tmp, "x2.png"))
    tag("x3", os.path.join(tmp, "x3.png"))
    for j, (text, _) in enumerate(chapters):
        lower_third(text, os.path.join(tmp, "ch%d.png" % j))
    # 1. the pieces cut out and joined, with the cards, the sound faded a moment at each join
    inputs, chains, cat = [], [], []
    k = 0
    for name, dur in (("open", OPEN_S),):
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % dur, "-i", os.path.join(tmp, name + ".png"),
                   "-f", "lavfi", "-t", "%.3f" % dur, "-i", "anullsrc=r=48000:cl=stereo"]
        chains.append("[%d:v]format=yuv420p,fade=t=out:st=%.3f:d=0.5,setsar=1[v%d]" % (k, dur - 0.5, k))
        chains.append("[%d:a]anull[a%d]" % (k + 1, k))
        cat.append("[v%d][a%d]" % (k, k))
        k += 2
    for j, (path, a, b, _, role) in enumerate(pieces):
        inputs += ["-i", path]
        d = (b - a) / FPS
        vf = "trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,format=yuv420p,setsar=1" % (a, b)
        af = "atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,aresample=48000" % (a / FPS, b / FPS)
        # in: from the opening card, from black (level 2), or a moment's fade of the sound at a join
        if role == "first":
            vf += ",fade=t=in:st=0:d=0.5"
            af += ",afade=t=in:d=0.8"
        elif role == "in":
            vf += ",fade=t=in:st=0:d=0.6"
            af += ",afade=t=in:d=0.6"
        else:
            af += ",afade=t=in:d=0.12"
        # out: to black (the end of level 1), to the closing card, or the moment's fade at a join
        if role == "out":
            vf += ",fade=t=out:st=%.3f:d=0.6" % (d - 0.6)
            af += ",afade=t=out:st=%.3f:d=0.6" % (d - 0.6)
        elif role == "last":
            vf += ",fade=t=out:st=%.3f:d=0.8" % (d - 0.8)
            af += ",afade=t=out:st=%.3f:d=1.2" % (d - 1.2)
        else:
            af += ",afade=t=out:st=%.3f:d=0.12" % (d - 0.12)
        chains.append("[%d:v]%s[v%d]" % (k, vf, k))
        chains.append("[%d:a]%s[a%d]" % (k, af, k))
        cat.append("[v%d][a%d]" % (k, k))
        k += 1
    inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % CLOSE_S, "-i", os.path.join(tmp, "close.png"),
               "-f", "lavfi", "-t", "%.3f" % CLOSE_S, "-i", "anullsrc=r=48000:cl=stereo"]
    chains.append("[%d:v]format=yuv420p,fade=t=in:st=0:d=0.5,fade=t=out:st=%.3f:d=0.6,setsar=1[v%d]" % (k, CLOSE_S - 0.6, k))
    chains.append("[%d:a]anull[a%d]" % (k + 1, k))
    cat.append("[v%d][a%d]" % (k, k))
    k += 2
    chains.append("%sconcat=n=%d:v=1:a=1[vc][ac]" % ("".join(cat), len(cat)))
    # 2. the overlays: the speed tags and the chapters
    last = "vc"
    n_ov = 0
    for name in ("x2", "x3", "ch0", "ch1"):
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % TOTAL, "-i", os.path.join(tmp, name + ".png")]
        if name.startswith("x"):
            spans = [(a, b) for a, b, kk in fast if "x%d" % kk == name]
            if not spans:
                k += 1
                continue
            enable = "+".join("between(t,%.3f,%.3f)" % (a, b) for a, b in spans)
            chains.append("[%s][%d:v]overlay=0:0:enable='%s'[o%d]" % (last, k, enable, n_ov))
        else:
            at = chapters[int(name[2])][1]
            chains.append("[%d:v]format=rgba,fade=t=in:st=%.3f:d=0.4:alpha=1,fade=t=out:st=%.3f:d=0.5:alpha=1[f%d]" % (
                k, at, at + 3.6, n_ov))
            chains.append("[%s][f%d]overlay=0:0:enable='between(t,%.3f,%.3f)'[o%d]" % (last, n_ov, at, at + 4.2, n_ov))
        last = "o%d" % n_ov
        n_ov += 1
        k += 1
    master = os.path.join(OUT, "master.mkv")
    if "--resound" in sys.argv:
        # the game's mix alone, from the recordings (the picture not drawn), and every film's sound made again from it
        mix = os.path.join(OUT, "mix.wav")
        achains = [c for c in chains if re.match(r"\[\d+:a\]", c)]
        acat = "".join(c.split("]")[1] + "]" for c in cat)
        subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(achains + [
            "%sconcat=n=%d:v=0:a=1[ac]" % (acat, len(cat))]), "-map", "[ac]", "-c:a", "pcm_s16le", "-t", "%.3f" % TOTAL, mix],
            check=True)
        sound = os.path.join(OUT, "sound.wav")
        make_sound(mix, sound)
        os.remove(mix)
        films(None, sound)
        return
    if "--films-only" in sys.argv and os.path.exists(master):
        sound = os.path.join(OUT, "sound.wav")
        if "--new-sound" in sys.argv or not os.path.exists(sound):
            make_sound(master, sound)
        films(master, sound)
        return
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains), "-map", "[%s]" % last,
                    "-map", "[ac]", "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
                    "-c:a", "pcm_s16le", "-t", "%.3f" % TOTAL, master], check=True)
    print("master", master)
    sound = os.path.join(OUT, "sound.wav")
    make_sound(master, sound)
    films(master, sound)


def make_sound(master, sound):
    """The game's own mix is quiet (about -30 LUFS) with loud short sounds (the bell, the shot, the UI): a gentle
    compressor, then the gain that brings it to about -16 LUFS, and a limiter that keeps its true peaks near -2.4 dBFS before AAC
    (each film then fits it to itself: fit_sound)."""
    pre = "acompressor=threshold=-26dB:ratio=2.5:attack=15:release=250:makeup=1"
    tmp = sound + ".pre.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", master, "-vn", "-af", pre, "-ar", "48000", "-c:a", "pcm_f32le", tmp], check=True)
    i, tp = loudness(tmp)
    gain = -15.5 - i
    # the limiter works four times oversampled, so that it holds the true peaks (between the samples) too
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "volume=%.2fdB,aresample=192000,alimiter=limit=0.76:attack=3:release=120:"
                    "level=disabled,aresample=48000" % gain, "-ar", "48000", "-c:a", "pcm_s24le", sound], check=True)
    os.remove(tmp)
    i2, tp2 = loudness(sound)
    print("sound: %.1f LUFS after the compressor, %+.1f dB: %.1f LUFS %.1f dBTP" % (i, gain, i2, tp2))


def films(master, sound):
    film(master, sound, os.path.join(OUT, NAME + ".mp4"), None, crf=17, maxrate=14000, abr="192k")
    film(master, sound, os.path.join(OUT, NAME + " (720p).mp4"), (1280, 720), kbps=int(56 * 8000 / TOTAL) - 160, abr="128k")
    film(master, sound, os.path.join(OUT, NAME + " (WhatsApp).mp4"), (960, 540), kbps=int(15.0 * 8000 / TOTAL) - 96, abr="80k")


def loudness(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vn", "-af", "ebur128=peak=true:framelog=quiet",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    tail = err[err.rindex("Summary"):]
    return float(tail.split("I:")[1].split("LUFS")[0]), float(tail.split("Peak:")[1].split("dBFS")[0])


def resound(out, sound, abr, af=None):
    """The film's sound replaced from sound.wav (through af), the picture kept as it is."""
    tmp = out + ".tmp.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", out, "-i", sound, "-map", "0:v", "-map", "1:a", "-c:v", "copy"] +
                   (["-af", af] if af else []) + ["-c:a", "aac", "-b:a", abr, "-ar", "48000", "-ac", "2", "-movflags", "+faststart",
                                                  "-shortest", tmp], check=True)
    os.replace(tmp, out)


def fit_sound(out, sound, abr):
    """The film's sound made again from sound.wav until it reads -16 to -15 LUFS with true peaks at -1.2 dBTP or under. The
    AAC changes both a little, more at a low rate: it loses some of the top (the loudness falls, about 1 LU at 80k) and
    it overshoots a sharp sound (the peaks rise). The gain follows the loudness, the limiter's ceiling the peaks."""
    gain, ceiling = 0.0, 0.76
    i, tp = loudness(out)
    for attempt in range(4):
        # a little room under -1 dBTP: the meter reads to a tenth, and a player's decoder is not the same AAC decoder
        if -16.0 <= i <= -15.0 and tp <= -1.2:
            break
        gain += -15.5 - i
        if tp > -1.2:
            ceiling *= 10 ** (-(tp + 1.5) / 20)
        resound(out, sound, abr, "volume=%.2fdB,aresample=192000,alimiter=limit=%.3f:attack=3:release=120:level=disabled,"
                                 "aresample=48000" % (gain, ceiling))
        i, tp = loudness(out)
    return i, tp


def film(master, sound, out, size, crf=None, kbps=None, maxrate=None, abr="192k"):
    if master is None or ("--keep-video" in sys.argv and os.path.exists(out)):
        resound(out, sound, abr)
        i, tp = fit_sound(out, sound, abr)
        print("film", os.path.basename(out), "(picture kept)", "%.1f MB" % (os.path.getsize(out) / 1e6), "%.1f LUFS %.1f dBTP" % (i, tp))
        return
    vf =["-vf", "scale=%d:%d:flags=lanczos" % size] if size else []
    rate = ["-crf", str(crf), "-maxrate", "%dk" % maxrate, "-bufsize", "%dk" % (maxrate * 2)] if crf else \
        ["-b:v", "%dk" % kbps, "-maxrate", "%dk" % int(kbps * 1.5), "-bufsize", "%dk" % (kbps * 2)]
    common = ["-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-pix_fmt", "yuv420p", "-r", str(FPS), "-g", "60"] + rate
    passlog = os.path.join(OUT, "pass")
    if kbps:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", master] + vf + common + ["-pass", "1", "-passlogfile", passlog, "-an", "-f", "mp4",
                                                                                   "/dev/null"], check=True)
        common += ["-pass", "2", "-passlogfile", passlog]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", master, "-i", sound, "-map", "0:v", "-map", "1:a"] + vf + common +
                   ["-c:a", "aac", "-b:a", abr, "-ar", "48000", "-ac", "2", "-movflags", "+faststart", "-shortest", out], check=True)
    i, tp = fit_sound(out, sound, abr)
    for ext in ("-0.log", "-0.log.mbtree"):
        if os.path.exists(passlog + ext):
            os.remove(passlog + ext)
    print("film", os.path.basename(out), "%.1f MB" % (os.path.getsize(out) / 1e6), "%.1f LUFS %.1f dBTP" % (i, tp))


def sheet():
    from PIL import ImageDraw as D
    path = os.path.join(OUT, NAME + ".mp4")
    tiles = []
    t = 1.0
    while t < TOTAL:
        png = os.path.join(OUT, "sheet_%03d.png" % int(t))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "%.2f" % t, "-i", path, "-frames:v", "1", "-vf", "scale=384:216", png], check=True)
        im = Image.open(png).convert("RGB")
        D.Draw(im).text((6, 4), "%d:%02d" % (int(t) // 60, int(t) % 60), fill=(255, 220, 90), font=font("semi", 22))
        tiles.append(im)
        os.remove(png)
        t += 8.0
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    s = Image.new("RGB", (cols * 384, rows * 216), (16, 16, 16))
    for j, im in enumerate(tiles):
        s.paste(im, ((j % cols) * 384, (j // cols) * 216))
    s.save(os.path.join(OUT, "contact sheet.jpg"), quality=86)
    print("sheet", len(tiles))


if __name__ == "__main__":
    if "--sheet" in sys.argv:
        sheet()
    else:
        build()
