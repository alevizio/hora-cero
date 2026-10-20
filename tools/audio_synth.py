#!/usr/bin/env python3
"""Synthesis helpers for tools/gen_audio.py (the sound set of Hora Cero).

Everything is plain numpy/scipy: noise, filters, envelopes, modal (struck object) synthesis, grain clouds,
stiff strings, a small formant voice, FFT-shaped periodic noise for seamless loops, and WAV output.
No samples are read from anywhere: every sound is built from these functions and fixed seeds."""
import struct
import zlib

import numpy as np
from scipy import signal

HI = 44100
LO = 22050
#: Loop files are written as [last PAD samples of the loop][the loop][first PAD samples of the loop], so the
#: engine's interpolation reads valid neighbours on both sides of the seam. audio.gd sets
#: loop_begin = PAD and loop_end = frames - PAD.
LOOP_PAD = 64


def rng_for(name):
    """One fixed random stream per sound name: regenerating gives the same files."""
    return np.random.default_rng(zlib.crc32(name.encode()) & 0x7FFFFFFF)


def n_of(dur, sr):
    return int(round(dur * sr))


def tt(dur, sr):
    return np.arange(n_of(dur, sr)) / sr


def db(x):
    return 10.0 ** (x / 20.0)


# ---------------------------------------------------------------- filters

def lp(x, f, sr, order=2):
    return signal.sosfilt(signal.butter(order, min(f, sr * 0.49), "lowpass", fs=sr, output="sos"), x)


def hp(x, f, sr, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=sr, output="sos"), x)


def bp(x, lo, hi, sr, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, sr * 0.49)], "bandpass", fs=sr, output="sos"), x)


def reson(x, f, q, sr):
    """Two-pole resonator (unity gain at f)."""
    b, a = signal.iirpeak(min(f, sr * 0.48), q, fs=sr)
    return signal.lfilter(b, a, x)


# ---------------------------------------------------------------- envelopes

def env_ad(dur, sr, attack, tau):
    """Smooth attack (seconds to ~full) and exponential decay (time constant tau)."""
    t = tt(dur, sr)
    a = 1.0 - np.exp(-t / max(attack / 3.0, 1e-5))
    return a * np.exp(-t / tau)


def hump(dur, sr, skew=0.5, power=1.0):
    """Raised-cosine hump over the whole duration; skew < 0.5 puts the peak earlier."""
    t = np.linspace(0.0, 1.0, n_of(dur, sr), endpoint=False)
    warped = np.where(t < skew, 0.5 * t / skew, 0.5 + 0.5 * (t - skew) / (1.0 - skew))
    return (0.5 - 0.5 * np.cos(2.0 * np.pi * warped)) ** power


def fade(x, sr, in_ms=1.0, out_ms=12.0):
    """Cosine fades so every one-shot starts and ends at exactly zero."""
    y = np.array(x, dtype=np.float64)
    a = min(len(y) // 2, int(in_ms * sr / 1000.0))
    r = min(len(y) // 2, int(out_ms * sr / 1000.0))
    if a > 0:
        y[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if r > 0:
        y[-r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return y


# ---------------------------------------------------------------- sources

def white(n, rng):
    return rng.standard_normal(n)


def burst(dur, sr, rng, lo, hi, attack, tau, order=2):
    """Band-limited noise burst with an attack/decay envelope."""
    return bp(white(n_of(dur, sr), rng), lo, hi, sr, order) * env_ad(dur, sr, attack, tau)


def thud(dur, sr, f0, f1, tau, drive=2.0, tau_f=0.03):
    """Pitch-dropping sine through a soft clipper: the odd harmonics carry it on small speakers."""
    t = tt(dur, sr)
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    x = np.sin(2.0 * np.pi * np.cumsum(f) / sr) * np.exp(-t / tau)
    return np.tanh(drive * x) / np.tanh(drive)


def thump(dur, sr, rng, low, tau=0.03, knock=0.8, pitch=0.35):
    """Dull impact of something heavy and soft. Mostly band noise, so it does not ring like a drum;
    the knock two octaves up is what a phone speaker (nothing below 300 Hz) actually plays."""
    x = burst(dur, sr, rng, low, low * 5.0, 0.002, tau)
    x += knock * burst(dur, sr, rng, low * 3.2, low * 13.0, 0.001, tau * 0.6)
    x += pitch * thud(dur, sr, low * 2.4, low * 1.3, tau * 0.6, 2.5, 0.02)
    return x


def modal(dur, sr, modes, rng=None, spread=0.0):
    """Struck object: a sum of decaying sines. modes = [(freq, tau, amp), ...]."""
    t = tt(dur, sr)
    out = np.zeros(len(t))
    for f, tau, amp in modes:
        if rng is not None and spread > 0.0:
            f *= 1.0 + rng.uniform(-spread, spread)
        if f < sr * 0.47:
            out += amp * np.sin(2.0 * np.pi * f * t) * np.exp(-t / tau)
    return out


def click(sr, rng, hi_from=1500.0, length_ms=1.5):
    """A very short broadband tick (the contact transient of an impact)."""
    n = max(8, int(length_ms * sr / 1000.0) * 4)
    x = white(n, rng) * np.exp(-np.arange(n) / (length_ms * sr / 1000.0))
    return hp(x, hi_from, sr)


def grains(dur, sr, rng, rate, lo, hi, sigma=0.6):
    """Poisson cloud of tiny impulses in a band: grit, gravel, leaves, sparks of friction.
    rate is grains per second (a number or an array over time)."""
    n = n_of(dur, sr)
    p = np.broadcast_to(np.asarray(rate, dtype=np.float64) / sr, (n,))
    hits = (rng.random(n) < p) * rng.lognormal(0.0, sigma, n) * rng.choice([-1.0, 1.0], n)
    return bp(hits, lo, hi, sr)


def stiff_string(dur, sr, f0, partials, tau, inharm=0.0006, pluck=0.13, tilt=0.7, glide=0.0, glide_tau=0.05, tau_slope=0.12):
    """Plucked taut wire: stretched partials, pitch settling after the release."""
    t = tt(dur, sr)
    bend = 1.0 + glide * np.exp(-t / glide_tau)
    phase = 2.0 * np.pi * np.cumsum(bend) / sr
    out = np.zeros(len(t))
    for k in range(1, partials + 1):
        fk = f0 * k * np.sqrt(1.0 + inharm * k * k)
        if fk * (1.0 + glide) > sr * 0.46:
            break
        amp = abs(np.sin(k * np.pi * pluck)) / k ** tilt
        out += amp * np.sin(phase * fk) * np.exp(-t / (tau / (1.0 + tau_slope * k)))
    return out


def tone(dur, sr, freq, partial_amps, attack, tau, detune=0.0012, tau_slope=0.35):
    """Warm struck tone: a few harmonics, each a slightly detuned pair for a slow shimmer."""
    t = tt(dur, sr)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (len(t),))
    phase = 2.0 * np.pi * np.cumsum(f) / sr
    out = np.zeros(len(t))
    for k, amp in enumerate(partial_amps, start=1):
        decay = np.exp(-t / (tau / (1.0 + tau_slope * (k - 1))))
        out += amp * 0.5 * (np.sin(phase * k * (1.0 - detune)) + np.sin(phase * k * (1.0 + detune) + 0.6 * k)) * decay
    return out * (1.0 - np.exp(-t / max(attack / 3.0, 1e-5)))


def stick_slip(dur, sr, rng, rate_from, rate_to, resonances, jitter=0.25, rate_mid=None):
    """Creak: an irregular pulse train (fibres or timber letting go) ringing a few resonances."""
    n = n_of(dur, sr)
    t = np.arange(n) / sr
    if rate_mid is None:
        rate = rate_from + (rate_to - rate_from) * t / dur
    else:
        rate = np.interp(t, [0.0, dur * 0.5, dur], [rate_from, rate_mid, rate_to])
    pulses = np.zeros(n)
    at = 0.0
    while at < dur:
        i = int(at * sr)
        if i < n:
            pulses[i] = rng.uniform(0.5, 1.0) * rng.choice([-1.0, 1.0])
        at += (1.0 / rate[min(i, n - 1)]) * (1.0 + rng.uniform(-jitter, jitter))
    out = np.zeros(n)
    for f, q, amp in resonances:
        out += amp * reson(pulses, f, q, sr)
    return out


def voice(dur, sr, rng, f0_points, formants_a, formants_b=None, tilt=1.1, breath=0.06, jitter=0.012):
    """Non-verbal vocal blip: harmonic source with a pitch contour through formant resonators
    (formants = [(freq, q, gain), ...]); formants_b, if given, is glided to over the duration."""
    n = n_of(dur, sr)
    t = np.arange(n) / sr
    f0 = np.interp(t, [p[0] * dur for p in f0_points], [p[1] for p in f0_points])
    f0 = f0 * (1.0 + jitter * lp(white(n, rng), 30.0, sr))
    phase = 2.0 * np.pi * np.cumsum(f0) / sr
    src = np.zeros(n)
    for k in range(1, int(5200.0 / f0.max()) + 1):
        src += np.sin(phase * k + rng.uniform(0.0, 0.3)) / k ** tilt
    src += breath * hp(white(n, rng), 800.0, sr) * (0.6 + 0.4 * np.sin(phase))
    mix = np.linspace(0.0, 1.0, n) ** 0.8
    out = np.zeros(n)
    for index, (f, q, g) in enumerate(formants_a):
        part = g * reson(src, f, q, sr)
        if formants_b is not None:
            fb, qb, gb = formants_b[index]
            part = part * (1.0 - mix) + gb * reson(src, fb, qb, sr) * mix
        out += part
    return out


# ---------------------------------------------------------------- space

def outdoor_ir(dur, sr, rng, bands):
    """Impulse response of open ground with a few hard surfaces: decaying noise that darkens with time.
    bands = [(lo, hi, tau, gain), ...]; the first 12 ms are left empty so the direct sound stays dry."""
    n = n_of(dur, sr)
    t = np.arange(n) / sr
    ir = np.zeros(n)
    for lo, hi, tau, gain in bands:
        ir += gain * bp(white(n, rng), lo, hi, sr) * np.exp(-t / tau)
    ir *= 1.0 - np.exp(-np.maximum(t - 0.012, 0.0) / 0.01)
    return ir / np.sqrt(np.sum(ir * ir))


def with_tail(x, sr, ir, gain_db, total, low_cut=0.0):
    """Dry signal plus its convolution with an impulse response, padded to `total` seconds.
    low_cut keeps the lows of the source out of the tail."""
    n = n_of(total, sr)
    out = np.zeros(n)
    out[:min(n, len(x))] += x[:n]
    wet = signal.fftconvolve(hp(x, low_cut, sr) if low_cut > 0.0 else x, ir)[:n] * db(gain_db)
    out[:len(wet)] += wet
    return out


def echoes(x, sr, taps, total, low_cut=0.0):
    """Discrete slap echoes: taps = [(delay, gain_db, lowpass_hz), ...]. Walls send back the mids:
    low_cut keeps the boom out of the echoes."""
    n = n_of(total, sr)
    out = np.zeros(n)
    out[:min(n, len(x))] += x[:n]
    source = hp(x, low_cut, sr) if low_cut > 0.0 else x
    for delay, gain_db, cutoff in taps:
        at = int(delay * sr)
        part = lp(source, cutoff, sr)[:max(0, n - at)] * db(gain_db)
        out[at:at + len(part)] += part
    return out


def place(buffer, x, at, sr, gain=1.0):
    """Mixes x into buffer at `at` seconds (clipped to the buffer)."""
    i = int(round(at * sr))
    if i >= len(buffer):
        return buffer
    part = x[:len(buffer) - i]
    buffer[i:i + len(part)] += gain * part
    return buffer


def softclip(x, drive):
    return np.tanh(drive * x) / np.tanh(drive)


# ---------------------------------------------------------------- periodic (loop) building blocks

def periodic_noise(n, sr, rng, shape):
    """White noise shaped in the frequency domain: exactly periodic over n samples.
    shape(freqs) returns the gain per frequency (array)."""
    spectrum = np.fft.rfft(white(n, rng))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    x = np.fft.irfft(spectrum * shape(freqs), n)
    return x / np.sqrt(np.mean(x * x))


def band_shape(lo, hi, slope=1.0, tilt=0.0):
    """Band with smooth skirts (log-frequency raised cosine over `slope` octaves) and a dB/octave tilt."""
    def shape(freqs):
        f = np.maximum(freqs, 1.0)
        octs_lo = np.clip((np.log2(f / lo) + slope) / slope, 0.0, 1.0)
        octs_hi = np.clip((np.log2(hi / f) + slope) / slope, 0.0, 1.0)
        gain = (0.5 - 0.5 * np.cos(np.pi * octs_lo)) * (0.5 - 0.5 * np.cos(np.pi * octs_hi))
        return gain * (f / np.sqrt(lo * hi)) ** (tilt / 6.02)
    return shape


def periodic_filter(x, sr, resonances):
    """Circular (steady-state) filtering through parallel resonators: resonances = [(freq, q, gain), ...]."""
    n = len(x)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    response = np.zeros(len(freqs), dtype=np.complex128)
    for f, q, gain in resonances:
        b, a = signal.iirpeak(f, q, fs=sr)
        _, h = signal.freqz(b, a, worN=freqs, fs=sr)
        response += gain * h
    return np.fft.irfft(np.fft.rfft(x) * response, n)


def periodic_lfo(n, rng, cycles, sharp=1.0):
    """Smooth 0..1 wobble that repeats exactly over n samples (sum of whole-cycle sines)."""
    phase = 2.0 * np.pi * np.arange(n) / n
    x = np.zeros(n)
    for c in cycles:
        x += np.sin(phase * c + rng.uniform(0.0, 2.0 * np.pi)) / np.sqrt(c)
    x = (x - x.min()) / (x.max() - x.min())
    return x ** sharp


def wrapped(n, sr, centre):
    """Time in seconds relative to `centre`, wrapped into [-loop/2, loop/2): for periodic envelopes."""
    t = np.arange(n) / sr
    loop = n / sr
    return (t - centre + loop * 0.5) % loop - loop * 0.5


# ---------------------------------------------------------------- output

def finish(x, sr, peak_db, in_ms=1.0, out_ms=12.0, dc_cut=30.0):
    """One-shot: remove DC and sub-bass, fade the ends to zero, normalise the peak."""
    y = hp(np.asarray(x, dtype=np.float64), dc_cut, sr) if dc_cut > 0.0 else np.asarray(x, dtype=np.float64)
    y = fade(y, sr, in_ms, out_ms)
    return y * (db(peak_db) / np.max(np.abs(y)))


def finish_loop(x, peak_db):
    """Loop: remove the mean (the body is already periodic) and normalise the peak."""
    y = np.asarray(x, dtype=np.float64)
    y = y - np.mean(y)
    return y * (db(peak_db) / np.max(np.abs(y)))


def a_weight(x, sr):
    """A-weighting (roughly what the ear makes of level at moderate volume), applied in the frequency domain."""
    spectrum = np.fft.rfft(x)
    f2 = np.maximum(np.fft.rfftfreq(len(x), 1.0 / sr), 1e-3) ** 2
    ra = (12194.0 ** 2 * f2 * f2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2))
    return np.fft.irfft(spectrum * ra * 1.2589, len(x))


def level_db(x):
    return 10.0 * np.log10(max(float(np.mean(x * x)), 1e-12))


def loudest_db(x, sr, window=0.05):
    """Level of the loudest `window` seconds."""
    n = max(1, int(window * sr))
    if len(x) <= n:
        return level_db(x)
    power = np.convolve(x * x, np.ones(n) / n, mode="valid")
    return 10.0 * np.log10(max(float(power.max()), 1e-12))


def to_loudness(x, sr, target_db, loop=False):
    """Scales a sound so that its A-weighted level is target_db: the loudest 50 ms of a one-shot,
    the whole body of a loop. The cue table in audio.gd then sets the mix in plain dB."""
    weighted = a_weight(np.asarray(x, dtype=np.float64), sr)
    now = level_db(weighted) if loop else loudest_db(weighted, sr)
    return np.asarray(x, dtype=np.float64) * db(target_db - now)


def to_pcm(x):
    return np.clip(np.round(np.asarray(x) * 32767.0), -32768, 32767).astype("<i2")


def write_wav(path, x, sr, loop=False):
    """16-bit mono PCM. With loop=True the periodic body is wrapped in LOOP_PAD samples on each side."""
    data = np.asarray(x, dtype=np.float64)
    if loop:
        data = np.concatenate([data[-LOOP_PAD:], data, data[:LOOP_PAD]])
    pcm = to_pcm(data).tobytes()
    header = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)
    header += b"data" + struct.pack("<I", len(pcm))
    with open(path, "wb") as handle:
        handle.write(header + pcm)


def read_wav(path):
    """Returns (float array, sample rate) of a 16-bit mono PCM file written by write_wav."""
    with open(path, "rb") as handle:
        raw = handle.read()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
    at = 12
    sr = 0
    channels = 0
    while at < len(raw):
        tag, size = raw[at:at + 4], struct.unpack("<I", raw[at + 4:at + 8])[0]
        if tag == b"fmt ":
            _, channels, sr, _, _, bits = struct.unpack("<HHIIHH", raw[at + 8:at + 24])
            assert bits == 16, path
        elif tag == b"data":
            assert channels == 1, path
            return np.frombuffer(raw[at + 8:at + 8 + size], dtype="<i2").astype(np.float64) / 32768.0, sr
        at += 8 + size + (size & 1)
    raise ValueError("no data chunk in " + path)
