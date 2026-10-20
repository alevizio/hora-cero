"""Original score for the Hora Cero trailers, synthesised from scratch (numpy/scipy only: no samples, no loops).
A tango of the snow at 100 BPM in E minor: a bandoneón (two free reeds an octave apart, the bellows' breath), strings
played marcato on every beat with the bass dragged into the downbeats (arrastre), the scratch of a chicharra, a
clock ticking (the zero hour), a piano's high notes for the flakes, low drums and hits for the cuts, an insect
chitter under the cascarudos, and a bell at the end.
Two cuts (the picture's edit is in compose_horacero.py; the times here are its beats):
  wide (55.2 s): 0 intro, the clock and the bandoneón alone | 12.0 hit: LA NIEVE MATA, the marcato (the four at
     work) | 24.0 the lift in G (the subte, Juan Salvo, the carry) | 32.4 the drop: the cascarudos, the síncopa
     low down, the chitter | 40.8 the strike (the rifle) | 42.0 Riachuelo, the theme | 46.8 end card, the bell.
  upright (27.6 s): the same in short: 2.4 hit, 9.6 lift, 14.4 drop, 20.4 strike, 20.4 Riachuelo, 22.8 end card.
usage: horacero_music.py <out.wav> [wide|upright]
"""
import sys
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt
from scipy.io import wavfile

SR = 48000
BPM = 100.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
CUT = sys.argv[2] if len(sys.argv) > 2 else "wide"
rng = np.random.default_rng(1958)


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12.0)


def env(n, a, d, s, r, hold):
    a, d, r, hold = int(a * SR), int(d * SR), int(r * SR), int(hold * SR)
    out = np.zeros(max(n, hold + r))
    k = min(a, hold)
    out[:k] = np.linspace(0, 1, k, endpoint=False)
    k2 = min(a + d, hold)
    if k2 > a:
        out[a:k2] = np.linspace(1, s, k2 - a, endpoint=False)
    if hold > a + d:
        out[a + d:hold] = s
    level = out[hold - 1] if hold > 0 else 0
    out[hold:hold + r] = level * np.linspace(1, 0, r) ** 2
    return out[:n] if n < len(out) else out


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, min(cutoff, SR * 0.45) / (SR / 2), output="sos"), x)


def highpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff / (SR / 2), btype="high", output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], btype="band", output="sos"), x)


def saw(freq, n, harmonics=14, bright=1.0, phase=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n)
    k = 1
    while k <= harmonics and freq * k < SR * 0.45:
        out += np.sin(2 * np.pi * freq * k * t + phase * k) / (k ** (2.0 - bright))
        k += 1
    return out


def reed(freq, n, duty=0.32, harmonics=24):
    """A free reed: a narrow pulse (odd and even partials), band-limited, its partials rolling off gently."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    k = 1
    while k <= harmonics and freq * k < SR * 0.42:
        amp = np.sin(np.pi * k * duty) / k
        out += amp * np.cos(2 * np.pi * freq * k * t)
        k += 1
    return out


N_TOTAL = {"wide": 55.2, "upright": 27.6}[CUT]
N = int(SR * (N_TOTAL + 3.0))
dry = np.zeros((N, 2))
wet = np.zeros((N, 2))


def add(buf, sig, at, gain=1.0, pan=0.0):
    i = int(round(at * SR))
    if i < 0:
        sig = sig[-i:]
        i = 0
    if i >= buf.shape[0]:
        return
    n = min(len(sig), buf.shape[0] - i)
    l = gain * np.cos((pan + 1) * np.pi / 4)
    r = gain * np.sin((pan + 1) * np.pi / 4)
    buf[i:i + n, 0] += sig[:n] * l
    buf[i:i + n, 1] += sig[:n] * r


# ------------------------------------------------------------------ instruments
def bandoneon(note, length, vel=1.0, octave=True, breath=0.05):
    """Two reeds an octave apart (the bandoneón's), the bellows' swell and a little air; vel shapes the brightness."""
    n = int((length + 0.35) * SR)
    f = hz(note)
    sig = reed(f, n, 0.30) + (0.55 * reed(f * 2.0 * 1.0015, n, 0.36) if octave else 0)
    t = np.arange(n) / SR
    sig *= 1.0 + 0.025 * np.sin(2 * np.pi * 4.6 * t + note)          # bellows shake
    e = env(n, 0.045, 0.12, 0.82, 0.18, length)
    bright = 1800 + 2600 * vel
    sig = lowpass(sig, bright, 2)
    air = bandpass(rng.standard_normal(n), 1500, 6000, 1) * breath
    return (sig * 0.22 + air) * e * (0.6 + 0.4 * vel)


def strings_short(note, length=0.22, bright=0.75):
    n = int((length + 0.25) * SR)
    f = hz(note)
    sig = sum(saw(f * d, n, 12, bright, p) for d, p in ((0.996, 0.0), (1.0, 1.3), (1.005, 2.1))) / 3
    return sig * env(n, 0.008, 0.07, 0.45, 0.18, length)


def strings_long(note, length, bright=0.55):
    n = int((length + 0.8) * SR)
    f = hz(note)
    sig = sum(saw(f * d, n, 10, bright, p) for d, p in ((0.994, 0.0), (1.0, 0.9), (1.006, 2.3), (0.5, 0.4))) / 4
    t = np.arange(n) / SR
    sig *= 1.0 + 0.05 * np.sin(2 * np.pi * 5.3 * t)
    return sig * env(n, 0.3, 0.3, 0.8, 0.8, length)


def pizz_bass(note, length=0.35, drag=False):
    """Plucked double bass; with drag (arrastre) a slide up into the note from a fourth below over an eighth."""
    n = int((length + 0.4) * SR)
    t = np.arange(n) / SR
    f = hz(note)
    if drag:
        slide = int(BEAT * 0.5 * SR)
        fr = np.full(n, f)
        fr[:slide] = np.linspace(f * 0.75, f, slide)
        ph = 2 * np.pi * np.cumsum(fr) / SR
    else:
        ph = 2 * np.pi * f * t
    sig = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    e = np.exp(-t * (5.0 if not drag else 3.0))
    if drag:
        e = np.minimum(1.0, t / (BEAT * 0.5)) ** 1.5 * np.exp(-np.maximum(0, t - BEAT * 0.5) * 5.0)
    return lowpass(sig, 900) * e


def chicharra(length=0.18):
    """The violin scraped below the bridge: a dry, pitched scratch."""
    n = int(length * SR)
    t = np.arange(n) / SR
    buzz = np.sign(np.sin(2 * np.pi * 95 * t)) * 0.4 + rng.standard_normal(n)
    return bandpass(buzz, 900, 4200, 2) * np.exp(-t * 14) * np.minimum(1, t / 0.004)


def piano(note, length=1.6, vel=0.7):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(note)
    out = np.zeros(n)
    for k, (amp, dec) in enumerate(((1.0, 1.6), (0.45, 2.4), (0.25, 3.5), (0.12, 5.0), (0.06, 7.0)), start=1):
        fk = f * k * (1 + 0.0004 * k * k)
        out += amp * np.sin(2 * np.pi * fk * t) * np.exp(-t * dec)
    hammer = bandpass(rng.standard_normal(n), 2000, 7000, 1) * np.exp(-t * 90) * 0.15
    return (out + hammer) * vel * np.minimum(1, t / 0.002)


def tick(freq=2600.0, gain=1.0):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    click = np.sin(2 * np.pi * freq * t) * np.exp(-t * 140) + bandpass(rng.standard_normal(n), 3000, 9000, 1) * np.exp(-t * 300) * 0.5
    return click * gain


def drum_low(strength=1.0, tune=58.0, length=1.4):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = tune * (1 + 1.1 * np.exp(-t * 26))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.4)
    thump = lowpass(rng.standard_normal(n), 450) * np.exp(-t * 32) * 0.8
    return (body + thump) * strength


def boom(length=5.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = 32 + 38 * np.exp(-t * 6)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 0.9)
    crack = bandpass(rng.standard_normal(n), 80, 2500) * np.exp(-t * 9) * 0.7
    air = lowpass(rng.standard_normal(n), 300) * np.exp(-t * 1.6) * 0.5
    return body + crack + air


def bell(note, length=6.0):
    """A tower clock's bell: inharmonic partials, each dying at its own rate."""
    n = int(length * SR)
    t = np.arange(n) / SR
    f0 = hz(note)
    out = np.zeros(n)
    for ratio, amp, decay in ((0.5, 0.6, 0.5), (1.0, 0.8, 0.9), (1.183, 0.45, 1.3), (1.506, 0.3, 1.7),
                              (2.0, 0.5, 1.9), (2.514, 0.2, 2.6), (2.662, 0.16, 3.0), (3.011, 0.12, 3.6)):
        out += amp * np.sin(2 * np.pi * f0 * ratio * t + ratio) * np.exp(-t * decay)
    strike = bandpass(rng.standard_normal(n), 900, 5000) * np.exp(-t * 55.0) * 0.3
    return (out + strike) * np.minimum(1.0, t / 0.002)


def wind(length):
    n = int(length * SR)
    t = np.arange(n) / SR
    lo = lowpass(rng.standard_normal(n), 360, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.27 * t + 1.0))
    hi = bandpass(rng.standard_normal(n), 900, 2600, 1) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.19 * t)) * 0.35
    fade = np.minimum(1.0, t / 0.8) * np.minimum(1.0, (length - t) / 0.8)
    return (lo + hi) * fade


def riser(length, lo=300.0, hi=6000.0):
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


def chitter(length, rate=38.0):
    """Many hard little legs and mandibles: dense resonant clicks, swelling and falling."""
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    count = int(length * rate)
    for k in rng.integers(0, max(1, n - 900), count):
        f = rng.uniform(1800, 4200)
        m = 700
        tt = np.arange(m) / SR
        out[k:k + m] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * rng.uniform(400, 900)) * rng.uniform(0.4, 1.0)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * 0.7 * t - 1.5)
    return highpass(out, 1200) * swell * np.minimum(1, t / 0.3) * np.minimum(1, (length - t) / 0.3)


def heartbeat():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    one = np.sin(2 * np.pi * 52 * t) * np.exp(-t * 16)
    two = np.zeros(n)
    k = int(0.19 * SR)
    two[k:] = (np.sin(2 * np.pi * 46 * t) * np.exp(-t * 20))[:n - k] * 0.75
    return one + two


# ------------------------------------------------------------------ harmony (E minor)
E1, B1, E2, G2, A2, B2, C3, D3, Ds3, E3, Fs3, G3, A3, B3, C4, D4, Ds4, E4, Fs4, G4, A4, B4, C5, D5, E5, Fs5, G5 = (
    28, 35, 40, 43, 45, 47, 48, 50, 51, 52, 54, 55, 57, 59, 60, 62, 63, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79)
CHORDS = {   # (bass, voicing)
    "Em": (E2, [E3, G3, B3, E4]),
    "Am": (A2, [E3, A3, C4, E4]),
    "B7": (B2, [Ds3, A3, B3, Fs4]),
    "C": (C3, [E3, G3, C4, E4]),
    "G": (G2, [D3, G3, B3, D4]),
    "D7": (D3, [Fs3, A3, C4, D4]),
    "D": (D3, [Fs3, A3, D4, Fs4]),
    "Am6": (A2, [Fs3, A3, C4, E4]),
}


def pad(t0, t1, chord, gain=0.3, bright=0.45):
    bassn, voice = CHORDS[chord]
    for i, note in enumerate(voice):
        add(wet, strings_long(note, t1 - t0, bright), t0, gain * 0.22, -0.4 + 0.27 * i)
    add(wet, strings_long(bassn, t1 - t0, bright * 0.7), t0, gain * 0.25, 0.0)


def drone(t0, t1, note, gain):
    n = int((t1 - t0 + 0.8) * SR)
    sig = lowpass(saw(hz(note), n, 6, 0.3), 220) * env(n, 0.8, 0.3, 0.9, 0.8, t1 - t0)
    add(dry, sig, t0, gain)
    add(wet, strings_long(note + 12, t1 - t0, 0.3), t0, gain * 0.5, 0.2)


def clock(t0, t1, gain=0.18):
    t = t0
    i = 0
    while t < t1 - 0.01:
        add(dry, tick(2700 if i % 2 == 0 else 2050), t, gain, 0.35 if i % 2 == 0 else -0.35)
        add(wet, tick(2700 if i % 2 == 0 else 2050), t, gain * 0.4)
        t += BEAT
        i += 1


def flakes(t0, t1, notes=(E5, B4, G5, Fs5, B4, E5, D5), every=1.5, gain=0.12):
    t = t0
    i = 0
    while t < t1 - 0.2:
        add(wet, piano(notes[i % len(notes)], 2.2, 0.6), t + rng.uniform(-0.05, 0.05), gain, rng.uniform(-0.6, 0.6))
        t += every * BEAT
        i += 1


def melody(t0, notes, gain=0.5, pan=0.15, vel=0.8, octave=True):
    """(note, beat, length in beats) from t0, on the bandoneón."""
    for note, b, length in notes:
        s = bandoneon(note, length * BEAT * 0.96, vel, octave)
        add(dry, s, t0 + b * BEAT, gain * 0.55, pan)
        add(wet, s, t0 + b * BEAT, gain * 0.5, pan)


def marcato_bar(t0, chord, gain=1.0, drag=True, syncopa=False, octave_up=False, half=None):
    """One bar of tango marcato: the chord short on every beat, the first and third heavier; the bass on 1 and 3,
    dragged into them; a chicharra on 2 and 4. With syncopa the accents fall 3-3-2 instead. half=0 or 1 plays only
    that half of the bar (two chords to a bar)."""
    bassn, voice = CHORDS[chord]
    up = 12 if octave_up else 0
    beats = [0, 1, 2, 3] if not syncopa else [0, 1.5, 3]
    if half is not None:
        beats = [b for b in beats if (b < 2) == (half == 0)]
    for b in beats:
        acc = 1.25 if b in (0, 2) or syncopa else 0.85
        for i, note in enumerate(voice):
            s = strings_short(note + up, 0.18, 0.85)
            add(dry, s, t0 + b * BEAT, gain * acc * 0.20, -0.45 + 0.3 * i)
            add(wet, s, t0 + b * BEAT, gain * acc * 0.14, -0.45 + 0.3 * i)
        rb = bandoneon(voice[1] + up, 0.16, 0.9, True, 0.03) + bandoneon(voice[2] + up, 0.16, 0.9, False, 0.0)
        add(dry, rb, t0 + b * BEAT, gain * acc * 0.32, 0.25)
    for b in ([b for b in ([0, 2] if not syncopa else [0, 1.5, 3]) if b in beats]):
        if drag:
            add(dry, pizz_bass(bassn, 0.4, True), t0 + b * BEAT - BEAT * 0.5, gain * 0.55)
        else:
            add(dry, pizz_bass(bassn, 0.4), t0 + b * BEAT, gain * 0.55)
    if not syncopa:
        for b in (1, 3):
            if b in beats: add(dry, chicharra(), t0 + b * BEAT, gain * 0.10, -0.3)


def low_drums(t0, beats, gain=0.6, tune=56.0):
    for b in beats:
        add(dry, drum_low(1.0, tune), t0 + b * BEAT, gain * 0.6)
        add(wet, drum_low(1.0, tune), t0 + b * BEAT, gain * 0.3)


def hit(t, gain=1.0, chord="Em"):
    add(dry, boom(4.0), t, 0.85 * gain)
    add(wet, boom(4.0), t, 0.45 * gain)
    bassn, voice = CHORDS[chord]
    for i, note in enumerate(voice):
        add(wet, strings_long(note + 12, 1.4, 0.8), t, 0.10 * gain, -0.4 + 0.27 * i)
        add(dry, bandoneon(note, 1.2, 1.0, True, 0.06), t, 0.20 * gain, -0.3 + 0.2 * i)
    add(dry, pizz_bass(bassn - 12, 1.0), t, 0.7 * gain)


# ------------------------------------------------------------------ the theme
# The tango of the snow (original): a falling, mournful phrase and its answer climbing back to the leading tone.
THEME_A = [(B3, -0.5, 0.5), (E4, 0, 2.0), (Ds4, 2, 0.5), (E4, 2.5, 0.5), (G4, 3, 1.0),
           (Fs4, 4, 1.5), (E4, 5.5, 0.5), (C4, 6, 1.0), (B3, 7, 1.0),
           (A3, 8, 1.5), (B3, 9.5, 0.5), (C4, 10, 1.0), (E4, 11, 1.0),
           (Ds4, 12, 3.0), (Fs4, 15, 1.0)]
THEME_B = [(E4, 0, 0.5), (G4, 0.5, 0.5), (B4, 1, 1.5), (A4, 2.5, 0.5), (G4, 3, 1.0),
           (Fs4, 4, 0.5), (A4, 4.5, 0.5), (C5, 5, 1.5), (B4, 6.5, 0.5), (A4, 7, 1.0),
           (G4, 8, 0.5), (B4, 8.5, 0.5), (D5, 9, 1.5), (C5, 10.5, 0.5), (B4, 11, 1.0),
           (A4, 12, 1.0), (G4, 13, 0.5), (Fs4, 13.5, 0.5), (Ds4, 14, 1.0), (B3, 15, 1.0)]
LIFT = [(B4, 0, 2.0), (D5, 2, 1.0), (C5, 3, 1.0), (B4, 4, 1.5), (A4, 5.5, 0.5), (Fs4, 6, 2.0),
        (G4, 8, 1.0), (A4, 9, 1.0), (B4, 10, 1.0), (C5, 11, 1.0), (B4, 12, 3.0)]
RIACHUELO = [(G4, 0, 1.5), (Fs4, 1.5, 0.5), (E4, 2, 1.0), (B3, 3, 1.0), (C4, 4, 1.5), (B3, 5.5, 0.5), (A3, 6, 1.0),
             (Ds4, 7, 1.0)]


def score_wide():
    # 0-12.0: intro. Wind, the clock, the snow's piano notes; the bandoneón alone, the strings coming in under it
    add(wet, wind(14.0), 0.0, 0.10, -0.2)
    add(dry, wind(14.0), 0.0, 0.05, 0.3)
    clock(0.0, 12.0, 0.16)
    flakes(1.2, 11.0)
    drone(0.0, 12.0, E2, 0.18)
    melody(1.2 + 0.5 * BEAT, THEME_A, 0.55, 0.1, 0.55)
    pad(4.8, 9.6, "Am", 0.25)
    pad(9.6, 12.0, "B7", 0.32)
    add(wet, riser(1.6, 400, 7000), 10.4, 0.16)
    for i in range(4):
        add(dry, pizz_bass(B2 if i % 2 == 0 else Fs3, 0.3), 9.6 + i * BEAT, 0.35)
    # 12.0: LA NIEVE MATA. The marcato, the four at work (a cut on every fourth beat: a drum on it)
    hit(12.0, 1.0)
    prog = ["Em", "Am", "D7", "G", "C", "Am6", "B7", "B7"]
    for k in range(5):
        tb = 12.0 + k * BAR
        if k < 4:
            marcato_bar(tb, prog[2 * k], 0.95, half=0)
            marcato_bar(tb, prog[2 * k + 1], 0.95, half=1)
        else:
            marcato_bar(tb, "B7", 0.95, syncopa=True)
        low_drums(tb, (0, 2), 0.7)
        add(dry, drum_low(1.0, 48, 1.6), tb, 0.45)
    melody(12.0, THEME_B, 0.62, 0.15, 0.95)
    for k in range(4):
        add(wet, strings_long(CHORDS[prog[2 * k]][1][3] + 12, BAR * 0.95, 0.5), 12.0 + k * BAR, 0.05, -0.3)
    add(wet, riser(1.2, 500, 8000), 22.8, 0.18)
    # 24.0: the lift (the subte's stairs: NADIE SALE SOLO; Juan Salvo, his carry)
    hit(24.0, 0.8, "G")
    lift = [("G", 24.0), ("D", 26.4), ("C", 28.8), ("B7", 31.2)]
    for chord, tb in lift:
        pad(tb, tb + (BAR if chord != "B7" else BAR / 2), chord, 0.45, 0.6)
        marcato_bar(tb, chord, 0.7, drag=True)
        low_drums(tb, (0, 2), 0.6)
    melody(24.0, LIFT, 0.7, 0.1, 1.0)
    for note, b, length in LIFT:
        add(wet, strings_long(note + 12, length * BEAT * 0.9, 0.55), 24.0 + b * BEAT, 0.07, -0.3)
    for i in range(4):
        add(dry, drum_low(0.7 + 0.1 * i, 60), 31.2 + i * BEAT * 0.5, 0.35)
    # 32.4: the drop. The cascarudos: the síncopa low down, the chitter, a heart; the bell is the game's (37.2)
    add(dry, boom(3.0), 32.4, 0.6)
    drone(32.4, 40.8, E1 + 12, 0.30)
    add(dry, chitter(8.0), 32.6, 0.10, 0.3)
    add(wet, chitter(8.0, 22), 33.0, 0.07, -0.4)
    for k in range(3):
        tb = 32.4 + k * BAR
        for b in (0, 1.5, 3):
            add(dry, pizz_bass(E2, 0.4, True), tb + b * BEAT - BEAT * 0.5, 0.6)
            s = bandoneon(E3, 0.2, 0.7, True, 0.02) + bandoneon(G3 if k < 2 else Fs3, 0.2, 0.7, False, 0.0)
            add(dry, s, tb + b * BEAT, 0.28, -0.2)
        add(dry, heartbeat(), tb + 0.1, 0.4)
    clock(37.2, 40.8, 0.12)
    add(wet, riser(2.2, 300, 9000), 38.6, 0.22)
    for i in range(6):
        add(dry, drum_low(0.5 + 0.08 * i, 66), 39.6 + i * BEAT * 0.2, 0.3)
    # 40.8: the strike (the rifle: the game's shot sits on it)
    add(dry, boom(5.0), 40.8, 1.0)
    add(wet, boom(5.0), 40.8, 0.6)
    for i, note in enumerate((E3, B3, E4, G4)):
        add(wet, strings_long(note, 1.0, 0.9), 40.8, 0.14, -0.4 + 0.25 * i)
    # 42.0: Riachuelo: the theme, quieter, the strings round it
    pad(42.0, 44.4, "C", 0.35)
    pad(44.4, 46.8, "B7", 0.38)
    melody(42.0, RIACHUELO, 0.55, 0.1, 0.7)
    flakes(42.0, 46.8, (E5, G5, B4, E5), 1.0, 0.10)
    for tb in (42.0, 44.4):
        for b in (0, 2):
            add(dry, pizz_bass(CHORDS["C" if tb < 44 else "B7"][0], 0.4, True), tb + b * BEAT - BEAT * 0.5, 0.45)
    add(wet, riser(1.0), 45.8, 0.16)
    # 46.8: the end card: the last chord, the bandoneón's last word, the clock's bell twice
    hit(46.8, 1.1)
    pad(46.8, 54.0, "Em", 0.5, 0.5)
    melody(48.0, [(B3, 0, 1.0), (G3, 1, 1.0), (E3, 2, 6.0)], 0.5, 0.0, 0.6)
    add(wet, bell(E3, 6.0), 47.0, 0.16, -0.2)
    add(wet, bell(E3, 6.0), 49.4, 0.12, 0.2)
    add(wet, wind(8.0), 47.0, 0.06, 0.1)


def score_upright():
    add(wet, wind(4.0), 0.0, 0.10, -0.2)
    clock(0.0, 2.4, 0.18)
    flakes(0.2, 2.4, (E5, B4), 1.0, 0.12)
    drone(0.0, 2.4, E2, 0.2)
    melody(0.0, [(E4, 0, 1.5), (Ds4, 1.5, 0.5), (Fs4, 2, 2.0)], 0.5, 0.1, 0.6)
    add(wet, riser(1.0, 400, 7000), 1.4, 0.16)
    # 2.4: LA NIEVE MATA, the marcato over three bars
    hit(2.4, 1.0)
    prog = [("Em", "Am"), ("D7", "G"), ("C", "B7")]
    for k, (c1, c2) in enumerate(prog):
        tb = 2.4 + k * BAR
        marcato_bar(tb, c1, 0.95, half=0)
        marcato_bar(tb, c2, 0.95, half=1)
        low_drums(tb, (0, 2), 0.7)
        add(dry, drum_low(1.0, 48, 1.6), tb, 0.45)
    melody(2.4, THEME_B[:15], 0.62, 0.15, 0.95)
    add(wet, riser(1.0, 500, 8000), 8.6, 0.18)
    # 9.6: the lift
    hit(9.6, 0.8, "G")
    for chord, tb in (("G", 9.6), ("C", 12.0)):
        pad(tb, tb + BAR, chord, 0.45, 0.6)
        marcato_bar(tb, chord, 0.7)
        low_drums(tb, (0, 2), 0.6)
    melody(9.6, LIFT[:8], 0.7, 0.1, 1.0)
    # 14.4: the drop, the cascarudos
    add(dry, boom(3.0), 14.4, 0.6)
    drone(14.4, 20.4, E1 + 12, 0.3)
    add(dry, chitter(6.0), 14.6, 0.10, 0.3)
    for k in range(2):
        tb = 14.4 + k * BAR
        for b in (0, 1.5, 3):
            add(dry, pizz_bass(E2, 0.4, True), tb + b * BEAT - BEAT * 0.5, 0.6)
            add(dry, bandoneon(E3, 0.2, 0.7, True, 0.02), tb + b * BEAT, 0.28, -0.2)
        add(dry, heartbeat(), tb + 0.1, 0.4)
    add(wet, riser(1.4, 300, 9000), 19.0, 0.22)
    # 20.4: the strike, then Riachuelo
    add(dry, boom(5.0), 20.4, 1.0)
    add(wet, boom(5.0), 20.4, 0.6)
    pad(20.4, 22.8, "C", 0.35)
    melody(20.8, RIACHUELO[:5], 0.5, 0.1, 0.7)
    # 22.8: the end card
    hit(22.8, 1.1)
    pad(22.8, 26.4, "Em", 0.5, 0.5)
    add(wet, bell(E3, 5.0), 23.0, 0.16, -0.2)
    add(wet, wind(4.6), 23.0, 0.06, 0.1)


score_wide() if CUT == "wide" else score_upright()

# ------------------------------------------------------------------ hall, mix, master
ir_len = int(2.6 * SR)
t = np.arange(ir_len) / SR
ir = np.stack([rng.standard_normal(ir_len), rng.standard_normal(ir_len)], axis=1) * np.exp(-t * 2.4)[:, None]
ir[: int(0.014 * SR)] = 0
ir = np.stack([lowpass(ir[:, 0], 6000), lowpass(ir[:, 1], 6000)], axis=1)
ir /= np.sqrt((ir ** 2).sum(axis=0))
hall = np.stack([fftconvolve(wet[:, c], ir[:, c])[:N] for c in range(2)], axis=1)
mix = dry + wet * 0.55 + hall * 0.45
mix = np.stack([highpass(mix[:, c], 30) for c in range(2)], axis=1)
low = np.stack([lowpass(mix[:, c], 140) for c in range(2)], axis=1)
mix = (mix - low) + low * 0.55
air = np.stack([highpass(mix[:, c], 1600) for c in range(2)], axis=1)
mix = mix + air * 0.35

ref = np.percentile(np.abs(mix), 99.95)
mix = mix * (0.80 / ref)
knee = 0.70
over = np.abs(mix) > knee
mix[over] = np.sign(mix[over]) * (knee + (1 - knee) * np.tanh((np.abs(mix[over]) - knee) / (1 - knee)))
mix *= 0.89 / np.abs(mix).max()
fade_in = int(0.05 * SR)
mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
end = int(N_TOTAL * SR)
tail = int(2.4 * SR)
mix[end - tail:end] *= (np.linspace(1, 0, tail) ** 1.4)[:, None]
mix = mix[:end]
out = sys.argv[1] if len(sys.argv) > 1 else "horacero_music.wav"
wavfile.write(out, SR, (mix * 32767).astype(np.int16))
rms = np.sqrt((mix ** 2).mean())
print("written", out, CUT, mix.shape, "peak", np.abs(mix).max().round(3), "rms dB", round(20 * np.log10(rms), 1))
