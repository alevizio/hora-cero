"""Original score for the cinematic Hora Cero trailer (hc2_compose.py), synthesised from scratch with numpy and scipy:
no samples, no loops, nothing from any other game, film or library. In E minor.
  the cold:      a low drone (detuned saws under a sine an octave down, slowly breathing) and the wind;
  the snow:      a slow celesta motif (a bell of two FM partials), a few piano notes high up;
  the opening:   under the drone, a slow pulse (a soft low stroke every two seconds);
  the snow's cold: glassy high tones (a glass harmonica's beating sines) over the motif;
  the falls:     one heavy heartbeat on "caía" and its faint echo, the drone gone, then nearly nothing (the beat of silence);
  the neighbours: a warmer swell, strings in C and G, the motif answered a sixth up;
  Juan Salvo:    the cellos take up a steady ostinato, rising;
  the trembling: the music drops out to a sub rumble and heavy footfalls;
  the cascarudos: a building, threatening pulse (3+3+2 in the low strings, a cluster swelling, heavy dissonant
                 brass-like swells cut off on the bar, the chitter of their legs), a riser into
  the title:     a big hit (a boom, the low strings and brass-like reeds on E, the bell), and the quiet tail under the
                 end card.
The times come from the edit (a cue sheet, JSON: see CUES); the cut's length from "total".
usage: hc2_music.py <out.wav> <cues.json>
"""
import json
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 48000
rng = np.random.default_rng(1958)
OUT = sys.argv[1]
CUES = json.load(open(sys.argv[2]))
TOTAL = float(CUES["total"])
N = int(SR * (TOTAL + 4.0))
dry = np.zeros((N, 2))
wet = np.zeros((N, 2))


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12.0)


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, min(cutoff, SR * 0.45) / (SR / 2), output="sos"), x)


def highpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff / (SR / 2), btype="high", output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], btype="band", output="sos"), x)


def env(n, a, d, s, r, hold):
    a, d, r, hold = int(a * SR), int(d * SR), int(r * SR), int(hold * SR)
    out = np.zeros(max(n, hold + r))
    k = min(a, hold)
    if k > 0:
        out[:k] = np.linspace(0, 1, k, endpoint=False)
    k2 = min(a + d, hold)
    if k2 > a:
        out[a:k2] = np.linspace(1, s, k2 - a, endpoint=False)
    if hold > a + d:
        out[a + d:hold] = s
    level = out[hold - 1] if hold > 0 else 0
    out[hold:hold + r] = level * np.linspace(1, 0, r) ** 2
    return out[:n]


def add(buf, sig, at, gain=1.0, pan=0.0):
    i = int(round(at * SR))
    if i < 0:
        sig = sig[-i:]
        i = 0
    if i >= buf.shape[0]:
        return
    n = min(len(sig), buf.shape[0] - i)
    buf[i:i + n, 0] += sig[:n] * gain * np.cos((pan + 1) * np.pi / 4)
    buf[i:i + n, 1] += sig[:n] * gain * np.sin((pan + 1) * np.pi / 4)


def saw(freq, n, harmonics=14, bright=1.0, phase=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n)
    k = 1
    while k <= harmonics and freq * k < SR * 0.45:
        out += np.sin(2 * np.pi * freq * k * t + phase * k) / (k ** (2.0 - bright))
        k += 1
    return out


# ------------------------------------------------------------------ instruments
def drone(t0, t1, note, gain, bright=220.0, breathe=0.09):
    """Detuned saws, filtered low, a sine an octave under them, breathing slowly."""
    n = int((t1 - t0 + 2.0) * SR)
    t = np.arange(n) / SR
    f = hz(note)
    sig = sum(saw(f * d, n, 8, 0.4, p) for d, p in ((0.997, 0.0), (1.0, 1.1), (1.0035, 2.3))) / 3
    sig = lowpass(sig, bright, 2) + 0.7 * np.sin(2 * np.pi * f * 0.5 * t)
    sig *= 1.0 + breathe * np.sin(2 * np.pi * 0.11 * t + note)
    e = env(n, 2.0, 0.1, 1.0, 2.0, t1 - t0)
    add(dry, sig * e, t0, gain)
    add(wet, sig * e, t0, gain * 0.4, 0.15)


def wind(t0, length, gain):
    n = int(length * SR)
    t = np.arange(n) / SR
    lo = lowpass(rng.standard_normal(n), 320, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.21 * t + 1.0))
    hi = bandpass(rng.standard_normal(n), 900, 2800, 1) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t)) * 0.3
    fade = np.minimum(1.0, t / 1.5) * np.minimum(1.0, (length - t) / 1.5)
    add(wet, (lo + hi) * fade, t0, gain * 0.7, -0.3)
    add(dry, (lo * 0.6 + hi) * fade, t0, gain * 0.4, 0.35)


def celesta(note, length=3.0, vel=0.7):
    """A celesta's bell: a struck sine with a quick FM shimmer, an octave partial, a soft hammer."""
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(note)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 1.6 * np.exp(-t * 9.0)
    body = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 1.6)
    body += 0.32 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 2.8)
    body += 0.12 * np.sin(2 * np.pi * f * 4.01 * t) * np.exp(-t * 5.0)
    hammer = bandpass(rng.standard_normal(n), 2500, 9000, 1) * np.exp(-t * 120) * 0.08
    return (body + hammer) * vel * np.minimum(1.0, t / 0.003)


def piano(note, length=3.0, vel=0.6):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(note)
    out = np.zeros(n)
    for k, (amp, dec) in enumerate(((1.0, 1.1), (0.45, 1.8), (0.22, 2.8), (0.1, 4.0)), start=1):
        out += amp * np.sin(2 * np.pi * f * k * (1 + 0.0004 * k * k) * t) * np.exp(-t * dec)
    hammer = bandpass(rng.standard_normal(n), 1800, 6000, 1) * np.exp(-t * 90) * 0.1
    return (out + hammer) * vel * np.minimum(1, t / 0.002)


def strings(note, length, bright=0.5, attack=0.8, release=1.4):
    n = int((length + release + 0.2) * SR)
    t = np.arange(n) / SR
    f = hz(note)
    sig = sum(saw(f * d, n, 10, bright, p) for d, p in ((0.994, 0.0), (1.0, 0.9), (1.006, 2.3))) / 3
    sig *= 1.0 + 0.04 * np.sin(2 * np.pi * 5.1 * t + note)
    sig = lowpass(sig, 600 + 2600 * bright)
    return sig * env(n, attack, 0.3, 0.85, release, length)


def short(note, length=0.22, bright=0.7, gain=1.0):
    """A low string stroke (the ostinato and the pulse): marcato, a bite at the front."""
    n = int((length + 0.3) * SR)
    f = hz(note)
    sig = sum(saw(f * d, n, 12, bright, p) for d, p in ((0.995, 0.0), (1.0, 1.3), (1.005, 2.1))) / 3
    sig = lowpass(sig, 1800)
    return sig * env(n, 0.006, 0.08, 0.5, 0.2, length) * gain


def reeds(note, length, vel=0.8):
    """Brass-like reeds for the hit: a pulse wave whose filter opens with the swell."""
    n = int((length + 1.0) * SR)
    t = np.arange(n) / SR
    f = hz(note)
    sig = np.zeros(n)
    k = 1
    while k <= 30 and f * k < SR * 0.42:
        sig += np.sin(np.pi * k * 0.35) / k * np.cos(2 * np.pi * f * k * t)
        k += 1
    e = env(n, 0.05, 0.4, 0.6, 0.9, length)
    out = np.zeros(n)
    step = 2048
    for i in range(0, n, step):
        cut = 500 + 3800 * vel * e[i]
        out[i:i + step] = lowpass(sig[i:i + step], cut, 1)
    return out * e * 0.3


def glass(note, length, gain=1.0):
    """A glassy, cold tone (a glass harmonica's): a pure sine and its octave, beating slowly against a twin a hair
    sharp, swelling in and out."""
    n = int((length + 1.5) * SR)
    t = np.arange(n) / SR
    f = hz(note)
    sig = (np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * f * 1.0025 * t + 1.0)) * 0.5
    sig += 0.25 * np.sin(2 * np.pi * f * 2.0 * t + 0.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.37 * t))
    return sig * env(n, length * 0.4, 0.1, 1.0, 1.5, length) * gain


def brass_swell(note, length, gain=1.0):
    """A heavy brass-like swell for the cascarudos: the reeds' pulse wave opening up as it grows, then cut short."""
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(note)
    sig = np.zeros(n)
    k = 1
    while k <= 24 and f * k < SR * 0.42:
        sig += np.sin(np.pi * k * 0.32) / k * np.cos(2 * np.pi * f * k * (1 + 0.0015 * np.sin(2 * np.pi * 4.7 * t)) * t)
        k += 1
    grow = (t / length) ** 1.8
    out = np.zeros(n)
    step = 2048
    for i in range(0, n, step):
        out[i:i + step] = lowpass(sig[i:i + step], 300 + 2600 * grow[i], 1)
    tail = np.minimum(1.0, (length - t) / 0.08)
    return out * grow * tail * 0.35 * gain


def heartbeat(gain=1.0):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    one = np.sin(2 * np.pi * 48 * t) * np.exp(-t * 14) + 0.3 * lowpass(rng.standard_normal(n), 200) * np.exp(-t * 40)
    two = np.zeros(n)
    k = int(0.21 * SR)
    two[k:] = (np.sin(2 * np.pi * 43 * t) * np.exp(-t * 18))[:n - k] * 0.7
    return (one + two) * gain


def boom(length=5.0, low=30.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = low + 40 * np.exp(-t * 6)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 0.8)
    crack = bandpass(rng.standard_normal(n), 80, 2500) * np.exp(-t * 10) * 0.6
    air = lowpass(rng.standard_normal(n), 260) * np.exp(-t * 1.4) * 0.5
    return body + crack + air


def thud(gain=1.0):
    """A heavy footfall felt more than heard."""
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    f = 26 + 30 * np.exp(-t * 12)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.0)
    dirt = lowpass(rng.standard_normal(n), 500) * np.exp(-t * 22) * 0.5
    return (body + dirt) * gain


def rumble(length, gain):
    n = int(length * SR)
    t = np.arange(n) / SR
    r = lowpass(rng.standard_normal(n), 70, 4) * 6.0
    r *= np.minimum(1.0, t / (length * 0.6)) * np.minimum(1.0, (length - t) / 0.4)
    return r * gain


def riser(length, lo=300.0, hi=7000.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    step = 2048
    for i in range(0, n, step):
        c = lo * (hi / lo) ** (i / n)
        seg = noise[i:i + step]
        out[i:i + len(seg)] = bandpass(seg, c * 0.7, min(c * 1.4, SR * 0.45), 1)
    return out * (t / length) ** 2.2


def reverse_swell(note_set, length):
    """A cluster of strings played backwards in time: it swells into the hit and stops dead on it."""
    sig = sum(strings(nt, length, 0.7, 0.05, 0.1) for nt in note_set) / len(note_set)
    sig = sig[:int(length * SR)][::-1]
    t = np.arange(len(sig)) / SR
    return sig * (t / length) ** 1.5


def chitter(length, rate=30.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in rng.integers(0, max(1, n - 900), int(length * rate)):
        f = rng.uniform(1600, 3800)
        m = 700
        tt = np.arange(m) / SR
        out[k:k + m] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * rng.uniform(400, 900)) * rng.uniform(0.4, 1.0)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * 0.6 * t - 1.5)
    return highpass(out, 1200) * swell * np.minimum(1, t / 0.4) * np.minimum(1, (length - t) / 0.4)


def tolling(note, length=7.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    f0 = hz(note)
    out = np.zeros(n)
    for ratio, amp, decay in ((0.5, 0.6, 0.45), (1.0, 0.8, 0.8), (1.183, 0.45, 1.2), (1.506, 0.3, 1.6), (2.0, 0.5, 1.8),
                              (2.514, 0.2, 2.5), (3.011, 0.12, 3.4)):
        out += amp * np.sin(2 * np.pi * f0 * ratio * t + ratio) * np.exp(-t * decay)
    strike = bandpass(rng.standard_normal(n), 900, 5000) * np.exp(-t * 55.0) * 0.25
    return (out + strike) * np.minimum(1.0, t / 0.002)


# ------------------------------------------------------------------ notes (E minor)
E1, B1, E2, Fs2, G2, A2, B2, C3, D3, E3, Fs3, G3, A3, B3, C4, D4, E4, Fs4, G4, A4, B4, C5, D5, E5, Fs5, G5, A5, B5 = (
    28, 35, 40, 42, 43, 45, 47, 48, 50, 52, 54, 55, 57, 59, 60, 62, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79, 81, 83)
# The snow's motif (original): four notes falling and one lifting, slow; and its answer, a sixth higher and warmer.
MOTIF = [(B4, 0.0), (G4, 0.9), (E5, 1.8), (D5, 3.0), (B4, 4.2)]
ANSWER = [(G5, 0.0), (E5, 0.9), (C5, 1.8), (D5, 3.0), (E5, 4.2)]


def motif(t0, notes, gain=0.32, stretch=1.0, inst=celesta):
    for note, b in notes:
        add(wet, inst(note, 3.4, 0.7), t0 + b * stretch, gain, rng.uniform(-0.4, 0.4))
        add(dry, inst(note, 3.4, 0.7), t0 + b * stretch, gain * 0.35, 0.0)


def chord(t0, t1, notes, gain=0.25, bright=0.45, attack=1.2, release=2.0):
    for i, nt in enumerate(notes):
        add(wet, strings(nt, t1 - t0, bright, attack, release), t0, gain * 0.24, -0.5 + i / max(1, len(notes) - 1))


def c(key, default=None):
    return float(CUES[key]) if key in CUES else default


# ------------------------------------------------------------------ the score
def score():
    snow, fall, silence_end = c("snow"), c("fall"), c("silence_end")
    neighbours, juan, tremble, beasts = c("neighbours"), c("juan"), c("tremble"), c("beasts")
    shot, title, end = c("shot"), c("title"), c("end")
    # the cold: drone and wind from the first frame to the trembling
    caia = c("caia", fall + 1.4)
    drone(0.0, caia, E1 + 12, 0.15, 200.0)
    wind(0.0, tremble + 1.0, 0.08)
    drone(0.4, snow + 2.0, B1 + 12, 0.05, 160.0)
    # the opening's slow pulse: a soft low stroke every two seconds, felt under the drone, fading as the snow comes
    at = 1.2
    while at < snow - 0.5:
        g = 0.42 * min(1.0, at / 3.0)
        add(dry, thud(0.32), at, g)
        add(dry, heartbeat(0.5), at, 0.25 * g)
        at += 2.1
    # the snow's glassy cold: high sines beating slowly over the motif
    for i, (note, off, ln) in enumerate(((B5, 0.0, 7.0), (E5 + 12, 2.2, 6.0), (Fs5, 4.6, 6.5))):
        add(wet, glass(note, ln, 0.5), snow - 0.6 + off, 0.05, -0.5 + 0.5 * i)
    # the snow: the motif, then again with the piano high up, the strings coming in under the people
    motif(snow - 0.3, MOTIF, 0.30, 1.0)
    for i, note in enumerate((E5, B4, G5, Fs5, B4, E5)):
        add(wet, piano(note, 3.0, 0.5), snow + 2.4 + 1.3 * i, 0.10, rng.uniform(-0.6, 0.6))
    people = c("people", snow + 8.0)
    chord(people - 1.0, fall + 0.6, [E3, B3, G4], 0.24, 0.35, 2.0, 1.5)
    motif(people + 1.4, MOTIF[:4], 0.22, 1.15)
    # the falls: the drone sinks under the line, one heavy heartbeat on "caía" (and its faint echo), then nearly
    # nothing but the wind until the neighbours
    drone(fall - 1.5, caia + 0.2, E1, 0.2, 120.0, 0.0)
    add(dry, heartbeat(1.0), caia - 0.02, 0.95)
    add(dry, boom(2.0, 30.0) * 0.5, caia - 0.02, 0.35)
    add(dry, heartbeat(0.45), caia + 1.15, 0.5)
    # the neighbours: the warmer swell (C, G, then A minor to D)
    # (in thirds of the time there is: the short cut goes straight from the falls to Juan Salvo, and skips them)
    span = juan - neighbours
    if span > 3.0:
        third = span / 3.0
        chord(neighbours - 0.6, neighbours + third, [C3, G3, E4, G4], 0.36, 0.5, 1.6, 1.4)
        chord(neighbours + third, neighbours + 2 * third, [G2, D3, B3, G4], 0.44, 0.55, 1.2, 1.4)
        chord(neighbours + 2 * third, juan, [A2, E3, C4, A4], 0.52, 0.6, 1.2, 1.6)
        add(dry, strings(C3 - 12, span, 0.3, 2.0, 1.4), neighbours - 0.4, 0.14)
        motif(neighbours + 0.6, ANSWER, 0.24, 1.25)
        for i, note in enumerate((G4, C5, E5, D5)):
            if neighbours + 5.2 + 1.6 * i < juan - 1.0:
                add(wet, piano(note, 3.2, 0.45), neighbours + 5.2 + 1.6 * i, 0.08, rng.uniform(-0.5, 0.5))
    # Juan Salvo: the cellos' ostinato, steady and rising (E, then G, then A) under a held chord
    beat_len = 0.5
    seq = [E2, E2, B2, E2, E2, B2, D3, B2]
    t = juan
    i = 0
    while t < tremble - 0.6:
        rise = (t - juan) / max(0.1, tremble - juan)
        add(dry, short(seq[i % len(seq)] + (3 if rise > 0.55 else 0), 0.24, 0.55 + 0.3 * rise, 0.55 + 0.4 * rise), t, 0.7, -0.2)
        t += beat_len
        i += 1
    chord(juan, tremble, [E3, B3, G4, B4], 0.56, 0.6, 2.4, 0.6)
    add(dry, strings(E2, tremble - juan, 0.4, 1.5, 0.5), juan, 0.22)
    motif(juan + 1.0, [(E4, 0.0), (G4, 1.0), (B4, 2.0), (D5, 3.4)], 0.18, 1.0, piano)
    # the trembling: the music drops to a sub rumble and the footfalls of something heavy
    add(dry, rumble(beasts - tremble + 1.0, 0.9), tremble - 0.2, 1.0)
    for j, at in enumerate(np.arange(tremble + 0.5, beasts + 0.3, 0.9)):
        add(dry, thud(0.6 + 0.12 * j), at, 0.85)
    # the cascarudos: the pulse (3+3+2 eighths at 128 bpm), the cluster swelling, their chitter, riser into the title
    eighth = 60.0 / 128.0 / 2.0
    t = beasts
    bar = 0
    while t < title - 0.05:
        for b in (0, 3, 6):
            at = t + b * eighth
            if at >= title - 0.05:
                break
            grow = (at - beasts) / max(0.1, title - beasts)
            add(dry, short(E2, 0.2, 0.7 + 0.25 * grow, 0.9 + 0.3 * grow), at, 0.85, -0.15)
            add(dry, short(E2 - 12, 0.2, 0.4, 0.8 + 0.3 * grow), at, 0.7, 0.15)
            add(dry, thud(0.6 + 0.3 * grow), at, 0.8)
        t += 8 * eighth
        bar += 1
    cl = [E3, E3 + 1, Fs3, B3]
    for i, nt in enumerate(cl):
        add(wet, strings(nt, title - beasts, 0.6, title - beasts - 0.5, 0.2), beasts, 0.14, -0.4 + 0.27 * i)
    # heavy, dissonant brass-like swells: F over E, then B flat over E, each cut off on the bar
    bar_len = 8 * eighth
    sw = beasts + 0.5 * bar_len
    j = 0
    while sw < title - 1.0:
        ln = min(bar_len * 2, title - sw)   # the last one swells right into the hit
        pair = ((E2, -0.3), (E2 + 1, 0.3)) if j % 2 == 0 else ((E2, -0.3), (E2 + 6, 0.3))
        for nt, pan in pair:
            add(dry, brass_swell(nt, ln, 1.0 + 0.3 * j), sw, 0.75, pan)
            add(wet, brass_swell(nt + 12, ln, 0.8), sw, 0.18, -pan)
        sw += ln
        j += 1
    # under it all, the strings in a nervous tremolo on a clustered E-F-B, growing to the hit
    span = title - beasts
    for i, nt in enumerate((E3, E3 + 1, B3, E4 + 1)):
        sig = strings(nt, span, 0.7, span * 0.35, 0.1)
        tt = np.arange(len(sig)) / SR
        sig = sig * (1.0 + 0.7 * np.sin(2 * np.pi * 11.0 * tt + i)) * np.minimum(1.0, (tt / span) ** 1.2 + 0.45)
        add(dry, sig[:int(span * SR)], beasts, 0.20, -0.45 + 0.3 * i)
    add(dry, chitter(title - beasts), beasts + 0.2, 0.09, 0.3)
    add(wet, chitter(title - beasts, 18), beasts + 0.6, 0.06, -0.4)
    if shot:
        add(dry, boom(3.0, 34.0), shot, 0.55)
    add(wet, riser(2.6, 250, 9000), title - 2.6, 0.22)
    add(dry, reverse_swell([E3, B3, E4, G4], 1.8), title - 1.8, 0.5)
    # the title: the hit
    add(dry, boom(6.0, 28.0), title, 1.1)
    add(wet, boom(6.0, 28.0), title, 0.6)
    for i, nt in enumerate((E2, B2, E3, G3, B3)):
        add(dry, reeds(nt, 1.6, 1.0), title, 0.22, -0.4 + 0.2 * i)
        add(wet, strings(nt + 12, 2.2, 0.75, 0.02, 2.0), title, 0.10, -0.4 + 0.2 * i)
    add(wet, tolling(E3, 7.0), title + 0.05, 0.22, -0.1)
    drone(title, TOTAL, E1 + 12, 0.22, 150.0)
    # the end card: a quiet tail, the motif's first notes on the celesta, the bell once more, the wind
    motif(end + 0.3, MOTIF[:3], 0.16, 1.2)
    add(wet, tolling(E3, 6.0), end + 1.4, 0.08, 0.2)
    wind(end - 0.5, TOTAL - end + 1.5, 0.06)


score()

# ------------------------------------------------------------------ hall, mix, master
ir_len = int(3.2 * SR)
t = np.arange(ir_len) / SR
ir = np.stack([rng.standard_normal(ir_len), rng.standard_normal(ir_len)], axis=1) * np.exp(-t * 1.9)[:, None]
ir[: int(0.02 * SR)] = 0
ir = np.stack([lowpass(ir[:, 0], 5000), lowpass(ir[:, 1], 5000)], axis=1)
ir /= np.sqrt((ir ** 2).sum(axis=0))
hall = np.stack([fftconvolve(wet[:, k], ir[:, k])[:N] for k in range(2)], axis=1)
mix = dry + wet * 0.45 + hall * 0.6
mix = np.stack([highpass(mix[:, k], 24) for k in range(2)], axis=1)
ref = np.percentile(np.abs(mix), 99.97)
mix = mix * (0.8 / ref)
knee = 0.72
over = np.abs(mix) > knee
mix[over] = np.sign(mix[over]) * (knee + (1 - knee) * np.tanh((np.abs(mix[over]) - knee) / (1 - knee)))
mix *= 0.89 / np.abs(mix).max()
fade_in = int(0.5 * SR)
mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
end = int(TOTAL * SR)
tail = int(2.0 * SR)
mix[end - tail:end] *= (np.linspace(1, 0, tail) ** 1.6)[:, None]
mix = mix[:end]
wavfile.write(OUT, SR, (mix * 32767).astype(np.int16))
print("written", OUT, mix.shape, "peak", np.abs(mix).max().round(3))
