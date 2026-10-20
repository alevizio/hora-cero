#!/usr/bin/env python3
"""Generates the sound set of Hora Cero into godot/assets/audio/ (16-bit mono WAV).

Every sound is synthesised here from noise, sines and filters with fixed seeds: no samples, nothing recorded,
nothing borrowed. Run it again and the same files come out.

    python3 tools/gen_audio.py            # write all files, print the level table
    python3 tools/gen_audio.py pistol     # only names containing "pistol"

Afterwards: `godot --headless --path godot --import`, then `python3 tools/audio_fix_imports.py` and import again
(first time only), and `python3 tools/audio_qa.py` for the level table and spectrogram sheets.

Loops are exactly periodic and are written with LOOP_PAD wrap-around samples at both ends (see audio_synth.py);
audio.gd sets the loop points in code. Loops are 22.05 kHz, sharp one-shots 44.1 kHz, dull ones 22.05 kHz.

Levels: every file is scaled to the same A-weighted loudness, LOUDNESS dB (the loudest 50 ms of a one-shot, the
whole of a loop), so the gains in audio.gd's cue table are the mix. The exceptions are the two loud guns, which
are peak-normalised (PEAK_ONLY) and so come out about 10 dB louder than everything else. No file peaks above
-1.5 dBFS."""
import os
import sys

import numpy as np

from audio_synth import (HI, LO, band_shape, bp, burst, click, db, echoes, env_ad, fade, finish, finish_loop,
                         grains, hp, hump, lp, modal, n_of, outdoor_ir, periodic_filter, periodic_lfo,
                         periodic_noise, place, reson, rng_for, softclip, stick_slip, stiff_string, thud, thump, to_loudness, tone,
                         tt, voice, white, with_tail, wrapped, write_wav)

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "audio"))

SOUNDS = {}
## Recipes this set keeps but Hora Cero's levels do not use (a closing scene, skis, charges, a canoe, gulls, other
## waters and engines): not written unless asked for by name.
NOT_SHIPPED = {"fin_bell", "fin_blast", "fin_boom", "fin_crash", "fin_creak", "fin_fire", "fin_underwater", "act_ski_1",
               "act_ski_2", "act_limpet", "act_satchel", "act_charge", "act_dip", "act_hull_scrape", "act_fuse", "act_switch",
               "act_paddle", "amb_gull_1", "amb_gull_2", "amb_horn", "amb_sea", "amb_river", "amb_torrent", "amb_hydro",
               "amb_generator"}
LOUDNESS = -24.0
PEAK_ONLY = ("gun_revolver", "gun_rifle", "fin_underwater", "fin_blast", "fin_boom", "fin_crash")
PEAK_LIMIT = -1.5


def sound(name, sr=HI, loop=False):
    def register(fn):
        SOUNDS[name] = (fn, sr, loop)
        return fn
    return register


def buf(dur, sr):
    return np.zeros(n_of(dur, sr))


# ================================================================ ambience loops

@sound("amb_sea", LO, loop=True)
def amb_sea(sr, rng):
    """Sea on a shingle beach: two unequal waves in ten seconds. Each one surges and breaks (broad, low-mid),
    then drags the pebbles back down the slope (high, grainy hiss). A low surf bed never quite stops."""
    n = n_of(10.0, sr)
    out = 0.13 * periodic_noise(n, sr, rng, band_shape(220, 800, 0.8, -3.0)) * (0.7 + 0.3 * periodic_lfo(n, rng, [1, 2, 3]))
    for centre, size in [(1.9, 1.0), (7.2, 0.72)]:
        u = wrapped(n, sr, centre)
        surge = np.where(u < 0.0, np.exp(u / 0.75), np.exp(-u / 0.55))
        wash = np.where(u < 0.25, np.exp((u - 0.25) / 0.22), np.exp(-(u - 0.25) / 1.15))
        drag = np.clip((u - 0.5) / 0.9, 0.0, 1.0) * np.exp(-np.maximum(u - 1.4, 0.0) / 0.95)
        out += size * 0.55 * surge * periodic_noise(n, sr, rng, band_shape(260, 1700, 1.0, -2.0))
        out += size * 0.34 * wash * periodic_noise(n, sr, rng, band_shape(900, 4200, 1.0, -1.5))
        hiss = periodic_noise(n, sr, rng, band_shape(2200, 7500, 0.8, 0.0))
        rattle = periodic_noise(n, sr, rng, band_shape(1500, 4500, 0.6, 0.0))
        # Pebbles knocking: the hiss is broken up by a fast irregular flutter (periodic as well).
        flutter = 0.45 + 0.55 * periodic_lfo(n, rng, [37, 53, 71, 97, 131, 173], 1.6)
        out += size * (0.2 * drag * hiss + 0.17 * drag * flutter * rattle)
    return finish_loop(out, -5.0)


@sound("amb_wind", LO, loop=True)
def amb_wind(sr, rng):
    """Wind in conifers: a soft body that swells in gusts, needle hiss riding the gusts, and a faint
    moving 'whistle' band that shifts between two pitches."""
    n = n_of(7.0, sr)
    gust = 0.35 + 0.65 * periodic_lfo(n, rng, [1, 2, 3, 5])
    lag = np.roll(gust, int(0.35 * sr))
    drift = periodic_lfo(n, rng, [1, 3, 4])
    out = 0.6 * gust * periodic_noise(n, sr, rng, band_shape(240, 1000, 0.9, -3.0))
    out += 0.34 * lag ** 2.2 * periodic_noise(n, sr, rng, band_shape(1500, 5200, 1.0, -3.0))
    out += 0.17 * gust * (1.0 - drift) * periodic_noise(n, sr, rng, band_shape(430, 620, 0.35, 0.0))
    out += 0.15 * gust * drift * periodic_noise(n, sr, rng, band_shape(700, 980, 0.35, 0.0))
    return finish_loop(out, -6.0)


def engine_pulses(n, sr, rng, rate, amp_jitter=0.15, time_jitter=0.0004):
    """Firing pulses of a small single-cylinder engine over a whole number of cycles."""
    count = int(round(rate * n / sr))
    x = np.zeros(n)
    for k in range(count):
        at = k / rate + rng.uniform(-time_jitter, time_jitter)
        x[int(round(at * sr)) % n] += 1.0 + rng.uniform(-amp_jitter, amp_jitter)
    return x


ENGINE_BODY = [(105, 4.0, 0.45), (210, 5.0, 0.65), (335, 6.0, 1.0), (520, 5.0, 0.9), (880, 4.0, 0.6), (1420, 3.0, 0.34)]


@sound("amb_generator", LO, loop=True)
def amb_generator(sr, rng):
    """The generator set by the radio post: a steady putter (22 firings a second) ringing the casing,
    mains-like hum from the dynamo and a rattle that follows each firing."""
    n = n_of(1.5, sr)
    t = np.arange(n) / sr
    pulses = engine_pulses(n, sr, rng, 22.0)
    out = periodic_filter(pulses, sr, ENGINE_BODY) * 4.0
    for k, amp in enumerate([0.2, 0.34, 0.36, 0.3, 0.18, 0.1], start=1):
        out += amp * 0.3 * np.sin(2.0 * np.pi * 100.0 * k * t + 0.9 * k)
    rattle_env = np.fft.irfft(np.fft.rfft(pulses) * np.fft.rfft(np.exp(-t / 0.018)), n)
    out += 0.11 * rattle_env * periodic_noise(n, sr, rng, band_shape(1300, 3600, 0.8, -2.0))
    return finish_loop(out, -6.0)


@sound("alarm_siren", LO, loop=True)
def alarm_siren(sr, rng):
    """A hand-cranked siren at full speed: one rotor, two rows of ports a minor third apart, chopping air.
    One second, exactly periodic. audio.gd spins it up, wails it and winds it down with pitch_scale."""
    n = n_of(1.0, sr)
    t = np.arange(n) / sr
    wobble = 0.004 * np.sin(2.0 * np.pi * 3.0 * t) + 0.002 * np.sin(2.0 * np.pi * 7.0 * t + 1.0)
    out = np.zeros(n)
    chop = np.zeros(n)
    for freq, amp in [(520.0, 1.0), (624.0, 0.8)]:
        phase = 2.0 * np.pi * freq * (t + wobble / 3.0)
        port = np.maximum(0.0, np.sin(phase)) ** 1.6   # air let through as a port passes
        chop += amp * port
        out += amp * (port - np.mean(port))
    out = out + 0.5 * periodic_filter(out, sr, [(1400, 3.0, 1.0), (2800, 4.0, 0.6)])   # the horn
    out *= 1.0 + 0.06 * np.sin(2.0 * np.pi * 52.0 * t)                                 # rotor out of true
    out += 0.07 * chop * periodic_noise(n, sr, rng, band_shape(900, 4200, 1.0, -2.0))  # rushing air
    return finish_loop(out, -5.0)


@sound("tension_loop", LO, loop=True)
def tension_loop(sr, rng):
    """Being watched: two soft tones a tritone apart, each a slowly beating pair. audio.gd raises level
    and pitch with the highest suspicion."""
    n = n_of(2.0, sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for freq, beat, amp in [(392.0, 2.5, 1.0), (554.5, 1.5, 0.6), (196.0, 1.0, 0.5), (784.0, 2.5, 0.12)]:
        for f in (freq, freq + beat):
            out += amp * (np.sin(2.0 * np.pi * f * t) + 0.12 * np.sin(4.0 * np.pi * f * t))
    out += 0.05 * periodic_noise(n, sr, rng, band_shape(500, 1800, 1.0, -3.0)) * (0.5 + 0.5 * np.sin(2.0 * np.pi * 2.5 * t))
    return finish_loop(out, -8.0)


# ================================================================ ambience one-shots

def gull_note(sr, rng, dur, f_points, rough=0.3):
    n = n_of(dur, sr)
    t = np.arange(n) / sr
    f = np.interp(t / dur, [p[0] for p in f_points], [p[1] for p in f_points])
    phase = 2.0 * np.pi * np.cumsum(f) / sr
    x = np.sin(phase) + 0.5 * np.sin(2.0 * phase + 0.4) + 0.22 * np.sin(3.0 * phase + 1.1)
    x *= 1.0 + rough * lp(white(n, rng), 140.0, sr) * 6.0
    return x * hump(dur, sr, 0.3)


def far_away(x, sr, rng, total, tail_db=-7.0):
    """Distance: the top rolled off, and more echo than direct sound."""
    ir = outdoor_ir(0.9, sr, rng, [(700, 3500, 0.28, 1.0)])
    return with_tail(lp(x, 4200.0, sr), sr, ir, tail_db, total)


@sound("amb_gull_1", LO)
def amb_gull_1(sr, rng):
    """A distant gull: four falling cries, each shorter than the last."""
    x = buf(1.3, sr)
    at = 0.0
    for k in range(4):
        dur = 0.24 - 0.025 * k
        scale = 1.0 - 0.03 * k
        place(x, gull_note(sr, rng, dur, [(0, 1500 * scale), (0.25, 2250 * scale), (1.0, 1350 * scale)]), at, sr, 1.0 - 0.14 * k)
        at += dur + 0.06
    return finish(far_away(x, sr, rng, 1.5), sr, -6.0, 3.0, 150.0)


@sound("amb_gull_2", LO)
def amb_gull_2(sr, rng):
    """A distant gull: one long mewing cry and a short answer."""
    x = buf(1.2, sr)
    place(x, gull_note(sr, rng, 0.62, [(0, 1250), (0.3, 1900), (0.7, 1750), (1.0, 1150)], 0.22), 0.0, sr)
    place(x, gull_note(sr, rng, 0.2, [(0, 1700), (0.3, 2100), (1.0, 1500)]), 0.78, sr, 0.5)
    return finish(far_away(x, sr, rng, 1.5), sr, -6.0, 3.0, 150.0)


TIMBER = [(180, 9.0, 0.5), (340, 12.0, 0.9), (620, 14.0, 1.0), (1100, 12.0, 0.7), (1700, 9.0, 0.4)]


@sound("amb_creak_1", LO)
def amb_creak_1(sr, rng):
    """A timber of the landing stage working against its pile: a slow groan."""
    x = stick_slip(0.85, sr, rng, 14.0, 17.0, TIMBER, 0.3, 34.0) * hump(0.85, sr, 0.45)
    return finish(with_tail(x, sr, outdoor_ir(0.3, sr, rng, [(300, 2000, 0.07, 1.0)]), -12.0, 1.05), sr, -6.0, 3.0, 60.0)


@sound("amb_creak_2", LO)
def amb_creak_2(sr, rng):
    """A shorter, higher creak (a door or the watchtower's frame), in two pulls."""
    higher = [(f * 1.35, q, a) for f, q, a in TIMBER]
    x = buf(0.8, sr)
    place(x, stick_slip(0.3, sr, rng, 22.0, 40.0, higher, 0.3) * hump(0.3, sr, 0.5), 0.0, sr)
    place(x, stick_slip(0.36, sr, rng, 36.0, 18.0, higher, 0.3) * hump(0.36, sr, 0.35), 0.36, sr, 0.8)
    return finish(with_tail(x, sr, outdoor_ir(0.3, sr, rng, [(300, 2500, 0.07, 1.0)]), -12.0, 0.95), sr, -6.0, 3.0, 60.0)


# ================================================================ movement

def footstep(sr, rng, heel_hz, toe_delay, grit, weight):
    """Boot on packed earth: the heel (a dull, short thump), then the sole rolling onto grit."""
    x = buf(0.22, sr)
    place(x, thump(0.12, sr, rng, heel_hz, 0.016, 0.9, 0.25), 0.0, sr, weight)
    place(x, burst(0.1, sr, rng, 500, 2000, 0.004, 0.022), toe_delay, sr, 0.36)
    rate = 1800.0 * np.exp(-tt(0.14, sr) / 0.04)
    place(x, grains(0.14, sr, rng, rate, 900, 3800) * env_ad(0.14, sr, 0.006, 0.04), toe_delay, sr, grit)
    return x


for _i, (_heel, _toe, _grit, _weight) in enumerate([(84, 0.045, 0.5, 1.0), (92, 0.055, 0.42, 0.9), (78, 0.038, 0.56, 1.05), (88, 0.062, 0.46, 0.95)], start=1):
    @sound("foot_step_%d" % _i, LO)
    def _foot(sr, rng, heel=_heel, toe=_toe, grit=_grit, weight=_weight):
        """Soft boot-on-earth footstep (four variants)."""
        return finish(footstep(sr, rng, heel, toe, grit, weight), sr, -6.0, 0.5, 30.0)


def gravel(sr, rng, body):
    """A boot sole on gravel: a crush of grains, a few stones knocking, a soft body."""
    x = buf(0.28, sr)
    rate = 2600.0 * env_ad(0.24, sr, 0.012, 0.055)
    place(x, grains(0.24, sr, rng, rate, 1200, 6000), 0.0, sr, 0.8)
    place(x, burst(0.2, sr, rng, 280, 1000, 0.008, 0.045), 0.0, sr, 0.9 * body)
    for _ in range(int(rng.integers(6, 10))):
        f = rng.uniform(2000, 4800)
        place(x, modal(0.02, sr, [(f, 0.003, 1.0), (f * 1.62, 0.002, 0.5)]), rng.uniform(0.0, 0.13), sr, rng.uniform(0.15, 0.4))
    return x


for _i, _body in enumerate([1.0, 0.8, 1.15], start=1):
    @sound("foot_gravel_%d" % _i, LO)
    def _gravel(sr, rng, body=_body):
        """Gravel crunch under a guard's boot (three variants)."""
        return finish(gravel(sr, rng, body), sr, -6.0, 1.0, 40.0)


def snow_step(sr, rng, body, squeak, length):
    """A boot sinking into cold, dry snow: a muffled heel, then the crust giving way in a run of soft crunches
    and the squeak of packed crystals (a slower, lower grain than gravel, and no stones)."""
    x = buf(0.36, sr)
    place(x, thump(0.12, sr, rng, 70, 0.02, 0.6, 0.2), 0.0, sr, 0.7 * body)
    rate = 900.0 * env_ad(length, sr, 0.03, length * 0.4)
    place(x, lp(grains(length, sr, rng, rate, 500, 2600, 0.9), 3200.0, sr), 0.01, sr, 1.0)
    # the squeak: a few short, pitched rubs of crystal on crystal
    for _ in range(int(rng.integers(2, 4))):
        f = rng.uniform(1100, 1900)
        d = rng.uniform(0.025, 0.05)
        place(x, reson(white(n_of(d, sr), rng), f, 18.0, sr) * hump(d, sr, 0.4), rng.uniform(0.03, length * 0.7), sr, 0.5 * squeak)
    place(x, burst(length, sr, rng, 300, 1100, 0.02, length * 0.35), 0.0, sr, 0.5 * body)
    return x


for _i, (_body, _squeak, _len) in enumerate([(1.0, 1.0, 0.22), (0.85, 0.7, 0.18), (1.1, 1.2, 0.25)], start=1):
    @sound("foot_snow_%d" % _i, LO)
    def _snow(sr, rng, body=_body, squeak=_squeak, length=_len):
        """A footstep in deep, dry snow (three variants): the operatives on the plateau at Vemork."""
        return finish(snow_step(sr, rng, body, squeak, length), sr, -6.0, 3.0, 40.0)


for _i, (_dur, _lo, _hi) in enumerate([(0.42, 1400, 5200), (0.36, 1200, 4600)], start=1):
    @sound("act_ski_%d" % _i, LO)
    def _ski(sr, rng, dur=_dur, lo=_lo, hi=_hi):
        """One kick and glide on skis (two variants): a long hiss of the running surface over snow, a soft crunch as
        the kick bites, and the pole planted with a dull tick."""
        x = buf(dur + 0.1, sr)
        n = n_of(dur, sr)
        glide = bp(white(n, rng), lo, hi, sr) * hump(dur, sr, 0.2, 0.8)
        place(x, glide, 0.0, sr, 0.8)
        place(x, lp(grains(0.12, sr, rng, 700.0 * env_ad(0.12, sr, 0.01, 0.05), 400, 2000), 2800.0, sr), 0.0, sr, 0.6)
        place(x, modal(0.05, sr, [(820, 0.012, 1.0), (1730, 0.008, 0.4)]) + 0.3 * burst(0.05, sr, rng, 300, 1200, 0.002, 0.01), dur * 0.55, sr, 0.35)
        return finish(x, sr, -6.0, 6.0, 60.0)


# ================================================================ cloth, rope, bodies

def swish(sr, rng, dur, lo, hi, skew=0.35):
    """One movement of heavy cloth: band noise with a friction grain, a quick hump."""
    n = n_of(dur, sr)
    grain = 0.55 + 0.45 * np.clip(lp(white(n, rng), 160.0, sr) * 9.0, -1.0, 1.0)
    return bp(white(n, rng), lo, hi, sr) * grain * hump(dur, sr, skew, 1.3)


def scuffle(sr, rng, moves):
    x = buf(0.5, sr)
    for at, dur, lo, hi, amp in moves:
        place(x, swish(sr, rng, dur, lo, hi), at, sr, amp)
    place(x, burst(0.08, sr, rng, 250, 900, 0.004, 0.02), moves[1][0] + 0.02, sr, 0.5)   # a boot shifting
    return x


@sound("act_scuffle_1", LO)
def act_scuffle_1(sr, rng):
    """Cloth scuffle: three quick movements and a boot shifting."""
    return finish(scuffle(sr, rng, [(0.0, 0.11, 600, 2400, 0.9), (0.1, 0.09, 900, 3600, 1.0), (0.22, 0.14, 500, 2000, 0.7), (0.37, 0.08, 800, 3000, 0.35)]), sr, -6.0, 2.0, 40.0)


@sound("act_scuffle_2", LO)
def act_scuffle_2(sr, rng):
    """Cloth scuffle, second variant."""
    return finish(scuffle(sr, rng, [(0.0, 0.09, 800, 3200, 0.8), (0.12, 0.13, 550, 2200, 1.0), (0.27, 0.1, 700, 2800, 0.8), (0.39, 0.07, 900, 3400, 0.3)]), sr, -6.0, 2.0, 40.0)


ROPE = [(720, 10.0, 0.7), (1250, 14.0, 1.0), (2100, 12.0, 0.8), (3300, 8.0, 0.4)]


@sound("act_rope_creak", LO)
def act_rope_creak(sr, rng):
    """Rope under strain: fibres letting go in a quickening run."""
    x = stick_slip(0.32, sr, rng, 34.0, 72.0, ROPE, 0.25) * hump(0.32, sr, 0.55)
    return finish(x + 0.2 * swish(sr, rng, 0.32, 700, 2500), sr, -6.0, 2.0, 30.0)


@sound("act_rope_cinch", LO)
def act_rope_cinch(sr, rng):
    """The knot pulled tight: a creak rising in pitch, a tug, the bound man settling."""
    x = buf(0.6, sr)
    place(x, stick_slip(0.26, sr, rng, 40.0, 125.0, ROPE, 0.2) * hump(0.26, sr, 0.7), 0.0, sr, 3.0)
    place(x, thump(0.14, sr, rng, 120, 0.02, 1.0, 0.2), 0.26, sr, 0.8)
    place(x, swish(sr, rng, 0.2, 500, 2200), 0.34, sr, 0.35)
    return finish(x, sr, -6.0, 2.0, 40.0)


@sound("act_knife", LO)
def act_knife(sr, rng):
    """Knife takedown, heard as cloth and weight only: a quick movement, one dull thump."""
    x = buf(0.42, sr)
    place(x, swish(sr, rng, 0.07, 1000, 4000, 0.6), 0.0, sr, 0.3)
    place(x, thump(0.3, sr, rng, 78, 0.04, 0.9, 0.3), 0.06, sr, 1.0)
    place(x, burst(0.1, sr, rng, 800, 2600, 0.001, 0.014), 0.06, sr, 0.3)
    place(x, swish(sr, rng, 0.16, 500, 1800), 0.2, sr, 0.2)
    return finish(x, sr, -4.0, 2.0, 40.0)


def body_impact(sr, rng, x, at, weight, low):
    place(x, thump(0.3, sr, rng, low, 0.045 * weight, 0.85, 0.3), at, sr, weight)
    place(x, burst(0.1, sr, rng, 700, 2400, 0.002, 0.016), at, sr, 0.25 * weight)


def gear_rattle(sr, rng, x, start, count, amp):
    """Webbing, buckles and a slung rifle settling."""
    for _ in range(count):
        f = rng.uniform(1700, 3600)
        place(x, modal(0.04, sr, [(f, 0.006, 1.0), (f * 1.48, 0.004, 0.5)]), start + rng.uniform(0.0, 0.14), sr, amp * rng.uniform(0.5, 1.0))


@sound("act_body_fall", LO)
def act_body_fall(sr, rng):
    """A man going down: knees, then the full weight, kit settling."""
    x = buf(0.6, sr)
    body_impact(sr, rng, x, 0.0, 0.7, 72)
    body_impact(sr, rng, x, 0.15, 1.0, 58)
    gear_rattle(sr, rng, x, 0.16, 4, 0.12)
    place(x, swish(sr, rng, 0.2, 500, 2200), 0.2, sr, 0.25)
    return finish(x, sr, -4.0, 1.0, 60.0)


@sound("act_heave", LO)
def act_heave(sr, rng):
    """Lifting a body onto the shoulders: cloth dragged up, webbing creaking, a boot bracing."""
    x = buf(0.62, sr)
    place(x, swish(sr, rng, 0.42, 450, 2600, 0.6), 0.0, sr, 1.0)
    place(x, stick_slip(0.2, sr, rng, 30.0, 55.0, ROPE, 0.3) * hump(0.2, sr), 0.14, sr, 0.22)
    place(x, grains(0.14, sr, rng, 1500.0, 400, 1500) * hump(0.14, sr, 0.3), 0.32, sr, 0.8)
    place(x, burst(0.1, sr, rng, 220, 900, 0.004, 0.022), 0.44, sr, 0.6)
    gear_rattle(sr, rng, x, 0.36, 3, 0.1)
    return finish(x, sr, -6.0, 3.0, 50.0)


@sound("act_body_drop", LO)
def act_body_drop(sr, rng):
    """A body put down on open ground: one soft heavy thud and cloth."""
    x = buf(0.42, sr)
    body_impact(sr, rng, x, 0.0, 0.95, 62)
    gear_rattle(sr, rng, x, 0.02, 2, 0.08)
    place(x, swish(sr, rng, 0.18, 500, 2000), 0.05, sr, 0.3)
    return finish(x, sr, -5.0, 1.0, 60.0)


@sound("act_bush_rustle", LO)
def act_bush_rustle(sr, rng):
    """A body pushed into a bush: leaves parting and closing, one twig."""
    x = buf(0.75, sr)
    shape = np.maximum(hump(0.7, sr, 0.25, 1.2), 0.5 * np.roll(hump(0.7, sr, 0.3, 2.0), int(0.3 * sr)))
    place(x, grains(0.7, sr, rng, 5200.0 * shape, 2400, 9000) * shape, 0.0, sr, 1.0)
    flutter = 0.6 + 0.4 * np.clip(lp(white(n_of(0.7, sr), rng), 45.0, sr) * 14.0, -1.0, 1.0)
    place(x, bp(white(n_of(0.7, sr), rng), 1300, 5500, sr) * shape * flutter, 0.0, sr, 0.55)
    place(x, burst(0.3, sr, rng, 300, 1000, 0.03, 0.08), 0.05, sr, 0.25)
    place(x, modal(0.04, sr, [(1500, 0.006, 1.0), (2900, 0.004, 0.6)]), 0.27, sr, 0.3)
    return finish(x, sr, -6.0, 4.0, 80.0)


# ================================================================ pebble

@sound("act_pebble_throw", LO)
def act_pebble_throw(sr, rng):
    """The throw: a short rising whoosh of the arm and the stone leaving."""
    dur = 0.24
    n = n_of(dur, sr)
    move = np.linspace(0.0, 1.0, n)
    noise = white(n, rng)
    x = bp(noise, 600, 1500, sr) * (1.0 - move) ** 1.5 + bp(noise, 1300, 3000, sr) * np.sin(np.pi * move) + bp(noise, 2600, 5200, sr) * move ** 1.5 * 0.7
    return finish(x * hump(dur, sr, 0.62, 1.4), sr, -8.0, 3.0, 30.0)


STONE = [(1100, 0.006, 0.5), (2350, 0.004, 1.0), (3900, 0.003, 0.7), (5600, 0.002, 0.4)]


@sound("act_pebble_land")
def act_pebble_land(sr, rng):
    """The pebble landing: a bounce of quickening stone clicks, then a short roll."""
    x = buf(0.56, sr)
    for k, (at, amp) in enumerate([(0.0, 1.0), (0.12, 0.6), (0.21, 0.42), (0.275, 0.3), (0.32, 0.2), (0.352, 0.14)]):
        place(x, modal(0.06, sr, STONE, rng, 0.09), at, sr, amp)
        place(x, click(sr, rng, 2000.0, 0.7), at, sr, 0.5 * amp)
        if k < 2:
            place(x, burst(0.06, sr, rng, 300, 900, 0.001, 0.012), at, sr, 0.5 * amp)
    place(x, grains(0.12, sr, rng, 700.0, 2000, 6000) * env_ad(0.12, sr, 0.01, 0.04), 0.37, sr, 0.5)
    return finish(x, sr, -4.0, 0.3, 30.0)


# ================================================================ Rook's tools

def metal_click(sr, rng, scale, amp_low=0.5):
    pick = [(1400 * scale, 0.005, amp_low), (3100 * scale, 0.007, 1.0), (4750 * scale, 0.005, 0.7), (6900 * scale, 0.003, 0.4), (9200 * scale, 0.002, 0.2)]
    x = modal(0.06, sr, pick, rng, 0.04)
    place(x, click(sr, rng, 2500.0, 0.5), 0.0, sr, 0.35)
    return x


for _i, (_scale, _second) in enumerate([(1.0, 0.0), (1.12, 0.027), (0.9, 0.0)], start=1):
    @sound("act_pick_%d" % _i)
    def _pick(sr, rng, scale=_scale, second=_second):
        """Lock pick on the pins: a tiny metallic click (three variants, one a double)."""
        x = buf(0.1, sr)
        place(x, metal_click(sr, rng, scale), 0.0, sr)
        if second > 0.0:
            place(x, metal_click(sr, rng, scale * 1.08), second, sr, 0.7)
        return finish(x, sr, -8.0, 0.2, 15.0)


@sound("act_unlock")
def act_unlock(sr, rng):
    """The lock gives: a last click, the bolt thrown with a clunk, the gate's bars answering."""
    x = buf(0.55, sr)
    place(x, metal_click(sr, rng, 0.95), 0.0, sr, 0.45)
    bolt = [(310, 0.06, 1.0), (520, 0.045, 0.75), (840, 0.035, 0.65), (1320, 0.025, 0.5), (2150, 0.015, 0.3)]
    place(x, modal(0.3, sr, bolt), 0.04, sr, 0.9)
    place(x, thud(0.12, sr, 190, 110, 0.022, 2.5), 0.04, sr, 0.6)
    place(x, burst(0.05, sr, rng, 500, 3000, 0.0005, 0.007), 0.04, sr, 0.8)
    bars = modal(0.4, sr, [(690, 0.14, 1.0), (1730, 0.09, 0.6), (2890, 0.05, 0.35)])
    place(x, bars * (1.0 + 0.6 * np.sin(2.0 * np.pi * 28.0 * tt(0.4, sr))), 0.1, sr, 0.22)
    return finish(x, sr, -4.0, 0.2, 40.0)


for _i, _scale in enumerate([1.0, 1.1], start=1):
    @sound("act_snip_%d" % _i)
    def _snip(sr, rng, scale=_scale):
        """Wire cutters: the handles squeezed, the jaws snapping through a strand (two variants)."""
        x = buf(0.15, sr)
        place(x, modal(0.04, sr, [(900 * scale, 0.008, 1.0), (1500 * scale, 0.005, 0.5)]), 0.0, sr, 0.14)
        place(x, click(sr, rng, 1500.0, 1.2), 0.036, sr, 0.9)
        place(x, modal(0.1, sr, [(2600 * scale, 0.009, 1.0), (4100 * scale, 0.006, 0.7), (6800 * scale, 0.004, 0.4), (3350 * scale, 0.03, 0.25)]), 0.036, sr, 0.8)
        place(x, burst(0.03, sr, rng, 700, 2200, 0.0005, 0.006), 0.036, sr, 0.5)
        return finish(x, sr, -5.0, 0.3, 20.0)


def twang(sr, rng, dur, f0, tau, glide, flutter_hz, rattles):
    """A taut wire let go: its pitch settling, a flutter against the post, the mesh rattling."""
    t = tt(dur, sr)
    x = stiff_string(dur, sr, f0, 30, tau, 0.0006, 0.13, 0.65, glide, 0.05)
    x += 0.35 * stiff_string(dur, sr, f0 * 1.52, 20, tau * 0.7, 0.0009, 0.21, 0.8, glide * 0.7, 0.04)
    x *= 1.0 + 0.55 * np.sin(2.0 * np.pi * flutter_hz * t) * np.exp(-t / 0.2)
    x = hp(x, 150.0, sr) * 0.5
    place(x, click(sr, rng, 1200.0, 1.0), 0.0, sr, 0.5)
    for k in range(rattles):
        f = rng.uniform(1700, 3000)
        place(x, modal(0.05, sr, [(f, 0.008, 1.0), (f * 1.7, 0.005, 0.5)]), (k + 0.5) / flutter_hz + rng.uniform(0.0, 0.006), sr, 0.22 * np.exp(-k / 3.0))
    return x


@sound("act_fence_twang")
def act_fence_twang(sr, rng):
    """The last strand of the fence parts and springs back."""
    return finish(twang(sr, rng, 0.9, 205.0, 0.42, 0.18, 31.0, 6), sr, -4.0, 0.2, 80.0)


for _i, _scale in enumerate([1.0, 1.06], start=1):
    @sound("act_peg_tap_%d" % _i)
    def _peg(sr, rng, scale=_scale):
        """A tripwire peg tapped into the earth with the pliers' handle (two variants)."""
        x = modal(0.16, sr, [(520 * scale, 0.018, 1.0), (1180 * scale, 0.012, 0.75), (2050 * scale, 0.008, 0.5), (3400 * scale, 0.005, 0.3)])
        place(x, thud(0.08, sr, 200, 120, 0.014, 2.0), 0.0, sr, 0.5)
        place(x, click(sr, rng, 1500.0, 0.6), 0.0, sr, 0.3)
        return finish(x, sr, -6.0, 0.2, 30.0)


@sound("act_wire_tink")
def act_wire_tink(sr, rng):
    """Thin wire drawn taut and tested with a finger."""
    x = stiff_string(0.24, sr, 880.0, 10, 0.09, 0.002, 0.2, 0.8, 0.04, 0.02, 0.2)
    return finish(x, sr, -8.0, 0.3, 40.0)


@sound("act_trap_sprung")
def act_trap_sprung(sr, rng):
    """A boot catches the tripwire: a short high twang, the peg pulling, a stumble."""
    x = twang(sr, rng, 0.45, 340.0, 0.16, 0.3, 44.0, 3)
    place(x, burst(0.05, sr, rng, 2000, 6000, 0.002, 0.012), 0.0, sr, 0.3)
    place(x, grains(0.12, sr, rng, 1800.0, 500, 2500) * hump(0.12, sr, 0.3), 0.07, sr, 0.9)
    place(x, burst(0.1, sr, rng, 220, 900, 0.004, 0.025), 0.1, sr, 0.5)
    return finish(x, sr, -4.0, 0.2, 60.0)


for _i, _kind in enumerate(["clink", "ratchet"], start=1):
    @sound("act_tool_%d" % _i)
    def _tool(sr, rng, kind=_kind):
        """Working on the generator: a spanner touching metal / a short ratchet."""
        x = buf(0.22, sr)
        if kind == "clink":
            place(x, modal(0.2, sr, [(1850, 0.045, 1.0), (3120, 0.03, 0.6), (4900, 0.018, 0.4), (7300, 0.01, 0.2)]), 0.0, sr)
            place(x, click(sr, rng, 2000.0, 0.6), 0.0, sr, 0.4)
            place(x, burst(0.05, sr, rng, 500, 1500, 0.0005, 0.008), 0.0, sr, 0.3)
        else:
            for k in range(4):
                place(x, modal(0.03, sr, [(2400, 0.004, 1.0), (3900, 0.003, 0.6), (1300, 0.004, 0.4)], rng, 0.05), 0.03 * k, sr, 0.7 + 0.1 * k)
                place(x, click(sr, rng, 2200.0, 0.4), 0.03 * k, sr, 0.3)
        return finish(x, sr, -7.0, 0.2, 25.0)


@sound("act_generator_die", LO)
def act_generator_die(sr, rng):
    """Sabotage done: a lever thrown with a heavy clunk, then the engine coughing to a stop."""
    x = buf(1.2, sr)
    place(x, modal(0.4, sr, [(240, 0.09, 1.0), (430, 0.07, 0.8), (760, 0.05, 0.65), (1250, 0.035, 0.45), (2100, 0.02, 0.3)]), 0.0, sr, 0.9)
    place(x, thud(0.15, sr, 170, 90, 0.03, 2.5), 0.0, sr, 0.7)
    place(x, burst(0.05, sr, rng, 600, 3500, 0.0005, 0.008), 0.0, sr, 0.8)
    for at, amp in [(0.1, 0.8), (0.16, 0.75), (0.235, 0.66), (0.33, 0.58), (0.45, 0.46), (0.61, 0.34), (0.83, 0.2)]:
        cough = np.zeros(n_of(0.3, sr))
        cough[0] = 1.0
        ring = np.zeros(len(cough))
        for f, q, gain in ENGINE_BODY:
            ring += gain * reson(cough, f, q, sr)
        place(x, ring * 8.0 + 0.5 * burst(0.3, sr, rng, 1300, 3600, 0.001, 0.02), at, sr, amp * 0.55)
    place(x, burst(0.5, sr, rng, 380, 1300, 0.12, 0.14), 0.7, sr, 0.16)
    return finish(x, sr, -4.0, 0.2, 80.0)


@sound("act_rescue")
def act_rescue(sr, rng):
    """The informant's bonds off: cloth, a latch let go, a few links."""
    x = buf(0.45, sr)
    place(x, swish(sr, rng, 0.16, 600, 2600), 0.0, sr, 0.5)
    for at, scale, amp in [(0.12, 1.0, 0.8), (0.2, 0.84, 1.0)]:
        place(x, modal(0.12, sr, [(1500 * scale, 0.025, 1.0), (2700 * scale, 0.018, 0.7), (4300 * scale, 0.01, 0.4)]), at, sr, amp)
        place(x, click(sr, rng, 2000.0, 0.5), at, sr, 0.3 * amp)
    for _ in range(5):
        f = rng.uniform(3000, 6000)
        place(x, modal(0.02, sr, [(f, 0.004, 1.0)]), 0.24 + rng.uniform(0.0, 0.12), sr, rng.uniform(0.1, 0.25))
    return finish(x, sr, -7.0, 2.0, 40.0)


@sound("act_boat_knock", LO)
def act_boat_knock(sr, rng):
    """Stepping down into the boat: two hollow knocks on the planking, water slapping the hull."""
    x = buf(0.8, sr)
    hull = [(165, 0.11, 1.0), (285, 0.09, 0.95), (470, 0.07, 0.8), (760, 0.045, 0.55), (1240, 0.025, 0.3)]
    for at, scale, amp in [(0.0, 1.0, 1.0), (0.17, 1.07, 0.62)]:
        place(x, modal(0.5, sr, [(f * scale, tau, a) for f, tau, a in hull]), at, sr, amp)
        place(x, burst(0.04, sr, rng, 800, 3000, 0.0005, 0.005), at, sr, 0.6 * amp)
    slap = bp(white(n_of(0.45, sr), rng), 280, 1900, sr) * hump(0.45, sr, 0.3, 1.2)
    place(x, slap * (0.7 + 0.3 * np.sin(2.0 * np.pi * 9.0 * tt(0.45, sr))), 0.22, sr, 0.3)
    return finish(x, sr, -4.0, 0.3, 80.0)


# ================================================================ guns

@sound("gun_pistol")
def gun_pistol(sr, rng):
    """Wren's muffled pistol: a dry thump with no crack and no tail, then the slide's small clack."""
    x = buf(0.26, sr)
    place(x, lp(burst(0.12, sr, rng, 320, 3800, 0.001, 0.016), 3800.0, sr, 4), 0.0, sr, 1.0)
    place(x, thump(0.12, sr, rng, 130, 0.016, 0.6, 0.3), 0.0, sr, 0.55)
    place(x, burst(0.2, sr, rng, 2000, 6000, 0.004, 0.045), 0.004, sr, 0.1)
    place(x, modal(0.05, sr, [(2300, 0.007, 1.0), (3700, 0.005, 0.7), (5900, 0.003, 0.4)]), 0.062, sr, 0.3)
    place(x, click(sr, rng, 2500.0, 0.4), 0.062, sr, 0.12)
    return finish(x, sr, -5.0, 0.2, 30.0)


def report(sr, rng, crack, blast, body, boom, tail, tail_db, taps, total):
    """A gunshot in the open: the crack (the loudest instant), the blast, a chest of low-mid body and a
    short boom under it, then the post and the shore answering. crack = (highpass, level),
    blast / body = (low, high, decay, level), boom = (from Hz, to Hz, decay, level)."""
    x = buf(0.5, sr)
    place(x, hp(white(n_of(0.03, sr), rng), crack[0], sr) * env_ad(0.03, sr, 0.0002, 0.0025), 0.0, sr, crack[1])
    place(x, softclip(burst(0.3, sr, rng, blast[0], blast[1], 0.0004, blast[2]) * 1.6, 2.5), 0.0, sr, blast[3])
    place(x, burst(0.4, sr, rng, body[0], body[1], 0.001, body[2]), 0.0, sr, body[3])
    place(x, thud(0.5, sr, boom[0], boom[1], boom[2], 3.0, 0.03), 0.001, sr, boom[3])
    x = softclip(x / np.max(np.abs(x)) * 1.4, 1.6)
    ir = outdoor_ir(total - 0.1, sr, rng, tail)
    return hp(echoes(with_tail(x, sr, ir, tail_db, total, 220.0), sr, taps, total, 220.0), 70.0, sr)


@sound("gun_revolver")
def gun_revolver(sr, rng):
    """Rook's revolver: a loud sharp crack and a tail off the buildings. Unmistakably a mistake."""
    x = report(sr, rng, (1500.0, 1.3), (450, 8000, 0.013, 1.0), (180, 900, 0.03, 0.45), (160, 88, 0.04, 0.3),
               [(2500, 7000, 0.06, 0.7), (800, 3000, 0.15, 1.0), (300, 1200, 0.28, 0.8)], -12.0,
               [(0.095, -11.0, 3200.0), (0.23, -16.0, 2200.0), (0.41, -21.0, 1400.0)], 1.1)
    return finish(x, sr, -1.5, 0.1, 250.0)


@sound("gun_rifle")
def gun_rifle(sr, rng):
    """A guard's rifle: heavier and lower than the revolver, with a longer roll."""
    x = report(sr, rng, (900.0, 0.9), (260, 6000, 0.022, 0.9), (150, 850, 0.05, 0.8), (115, 56, 0.07, 0.5),
               [(2000, 5500, 0.09, 0.6), (600, 2600, 0.22, 1.0), (220, 1000, 0.42, 1.0)], -9.5,
               [(0.13, -9.0, 2800.0), (0.3, -13.0, 2000.0), (0.52, -18.0, 1300.0), (0.8, -23.0, 900.0)], 1.35)
    return finish(x, sr, -1.5, 0.1, 300.0)


@sound("gun_rifle_bolt")
def gun_rifle_bolt(sr, rng):
    """Working the bolt: lift, back, forward, down."""
    x = buf(0.5, sr)

    def clack(scale, low):
        y = modal(0.08, sr, [(1500 * scale, 0.01, 1.0), (2700 * scale, 0.007, 0.7), (4400 * scale, 0.004, 0.45), (320, 0.012, low)])
        return place(y, click(sr, rng, 2000.0, 0.5), 0.0, sr, 0.3)

    def scrape(dur):
        return grains(dur, sr, rng, 5000.0, 2000, 6500) * hump(dur, sr, 0.6)

    place(x, clack(1.0, 0.0), 0.0, sr, 0.5)
    place(x, scrape(0.085), 0.07, sr, 0.5)
    place(x, clack(0.85, 0.6), 0.16, sr, 0.85)
    place(x, scrape(0.075), 0.24, sr, 0.5)
    place(x, clack(0.92, 0.8), 0.32, sr, 1.0)
    place(x, clack(1.15, 0.0), 0.385, sr, 0.6)
    return finish(x, sr, -5.0, 0.2, 40.0)


@sound("gun_hit", LO)
def gun_hit(sr, rng):
    """A bullet striking a man: a slap of cloth and kit and a dull knock."""
    x = buf(0.2, sr)
    place(x, burst(0.08, sr, rng, 500, 3500, 0.0005, 0.009), 0.0, sr, 0.9)
    place(x, thump(0.18, sr, rng, 110, 0.024, 1.0, 0.3), 0.0, sr, 1.0)
    return finish(x, sr, -4.0, 0.3, 40.0)


@sound("gun_hurt", LO)
def gun_hurt(sr, rng):
    """One of yours is hit: two dull pulses, close and inside the head (not positional)."""
    x = buf(0.45, sr)
    for at, amp in [(0.0, 1.0), (0.17, 0.7)]:
        place(x, thump(0.25, sr, rng, 95, 0.042, 1.0, 0.45), at, sr, amp)
    return finish(x, sr, -4.0, 1.0, 60.0)


@sound("gun_ricochet")
def gun_ricochet(sr, rng):
    """A miss glancing off stone: a tick and a falling whine."""
    dur = 0.42
    t = tt(dur, sr)
    f = (1500.0 + 2300.0 * np.exp(-t / 0.09)) * (1.0 + 0.035 * np.sin(2.0 * np.pi * np.cumsum(20.0 + 45.0 * np.exp(-t / 0.15)) / sr))
    phase = 2.0 * np.pi * np.cumsum(f) / sr
    x = (np.sin(phase) + 0.35 * np.sin(2.0 * phase) + 0.15 * np.sin(3.0 * phase)) * env_ad(dur, sr, 0.004, 0.085)
    x *= 1.0 + 0.5 * np.clip(lp(white(len(t), rng), 220.0, sr) * 7.0, -1.0, 1.0)   # a tumbling, uneven whine
    x += 0.4 * burst(dur, sr, rng, 1500, 5000, 0.002, 0.06)
    place(x, click(sr, rng, 1200.0, 1.5), 0.0, sr, 0.7)
    place(x, burst(0.05, sr, rng, 800, 4000, 0.0005, 0.006), 0.0, sr, 0.8)
    return finish(x, sr, -6.0, 0.3, 80.0)


@sound("gun_miss", LO)
def gun_miss(sr, rng):
    """A miss into the ground: a thup and a spray of dirt."""
    x = buf(0.24, sr)
    place(x, thud(0.1, sr, 230, 120, 0.016, 2.4), 0.0, sr, 0.8)
    place(x, burst(0.1, sr, rng, 600, 2500, 0.0005, 0.018), 0.0, sr, 0.9)
    place(x, grains(0.2, sr, rng, 3200.0 * env_ad(0.2, sr, 0.004, 0.05), 1000, 5200), 0.01, sr, 0.9)
    return finish(x, sr, -6.0, 0.3, 40.0)


# ================================================================ awareness and alarm

def struck(sr, dur, freq, tau, attack=0.003, partials=10, tilt=1.2):
    """A bright struck string (not brass, not a sample): harmonics that die faster the higher they are."""
    t = tt(dur, sr)
    x = np.zeros(len(t))
    for k in range(1, partials + 1):
        fk = freq * k * np.sqrt(1.0 + 0.0003 * k * k)
        x += np.sin(2.0 * np.pi * fk * t + 0.5 * k) / k ** tilt * np.exp(-t / (tau / (1.0 + 0.15 * k)))
    return x * (1.0 - np.exp(-t / (attack / 3.0)))


@sound("alert_spotted", LO)
def alert_spotted(sr, rng):
    """Spotted: one sharp struck cluster (a semitone under a fifth), a woody tick on top. Short."""
    x = buf(0.8, sr)
    place(x, modal(0.1, sr, [(880, 0.03, 1.0), (1320, 0.02, 0.7), (2640, 0.01, 0.4)]), 0.0, sr, 0.35)
    for freq, amp in [(329.63, 0.9), (349.23, 1.0), (493.88, 0.8)]:
        place(x, struck(sr, 0.8, freq, 0.34), 0.0, sr, 0.5 * amp)
    ir = outdoor_ir(0.4, sr, rng, [(400, 3000, 0.12, 1.0)])
    return finish(with_tail(x, sr, ir, -15.0, 0.86), sr, -4.0, 0.3, 120.0)


@sound("alert_body", LO)
def alert_body(sr, rng):
    """A body is found: a low knock and a darker cluster that sinks a semitone."""
    x = buf(1.1, sr)
    place(x, thud(0.4, sr, 150, 78, 0.11, 3.0), 0.0, sr, 0.6)
    place(x, burst(0.2, sr, rng, 220, 800, 0.003, 0.05), 0.0, sr, 0.3)
    place(x, struck(sr, 1.0, 311.13, 0.4, 0.012, 8, 1.3), 0.0, sr, 0.5)
    place(x, struck(sr, 1.0, 440.0, 0.45, 0.012, 8, 1.4), 0.0, sr, 0.36)
    place(x, struck(sr, 0.9, 293.66, 0.5, 0.015, 8, 1.3), 0.2, sr, 0.55)
    ir = outdoor_ir(0.5, sr, rng, [(300, 2400, 0.16, 1.0)])
    return finish(with_tail(x, sr, ir, -14.0, 1.15), sr, -4.0, 0.5, 160.0)


def bark(sr, rng, dur, f0_points, vowel_a, vowel_b, attack, tau, breath_ms=30.0):
    """A wordless shout: breath onset, one open vowel that closes a little, hard decay."""
    x = voice(dur, sr, rng, f0_points, vowel_a, vowel_b, 0.9, 0.08)
    x *= env_ad(dur, sr, attack, tau)
    onset = bp(white(n_of(breath_ms / 1000.0, sr), rng), 900, 3500, sr) * hump(breath_ms / 1000.0, sr, 0.6)
    out = buf(dur + breath_ms / 1000.0, sr)
    place(out, onset, 0.0, sr, 0.1 * np.max(np.abs(x)))
    place(out, x, breath_ms / 1000.0 * 0.6, sr)
    ir = outdoor_ir(0.3, sr, rng, [(500, 3000, 0.08, 1.0)])
    return with_tail(out, sr, ir, -14.0, dur + 0.3)


@sound("alert_bark_1", LO)
def alert_bark_1(sr, rng):
    """Guard's alarm bark: a short forceful open shout, no word in it."""
    x = bark(sr, rng, 0.2, [(0, 185), (0.25, 245), (1.0, 180)],
             [(700, 6.0, 1.0), (1220, 8.0, 0.8), (2500, 9.0, 0.4)], [(560, 6.0, 1.0), (1500, 8.0, 0.7), (2500, 9.0, 0.35)], 0.012, 0.085)
    return finish(x, sr, -5.0, 2.0, 80.0)


@sound("alert_bark_2", LO)
def alert_bark_2(sr, rng):
    """Guard's alarm bark, second voice: lower and rounder."""
    x = bark(sr, rng, 0.23, [(0, 150), (0.3, 205), (1.0, 150)],
             [(600, 6.0, 1.0), (900, 8.0, 0.8), (2400, 9.0, 0.35)], [(480, 6.0, 1.0), (1050, 8.0, 0.7), (2400, 9.0, 0.3)], 0.014, 0.095)
    return finish(x, sr, -5.0, 2.0, 80.0)


@sound("alert_query", LO)
def alert_query(sr, rng):
    """'What was that?' without words: a closed-mouth hum that rises."""
    x = voice(0.3, sr, rng, [(0, 135), (0.5, 150), (1.0, 215)], [(310, 4.0, 1.0), (1100, 7.0, 0.45), (2300, 8.0, 0.12)], None, 1.4, 0.03)
    x = lp(x, 2600.0, sr) * hump(0.3, sr, 0.55, 0.8)
    ir = outdoor_ir(0.25, sr, rng, [(300, 2000, 0.07, 1.0)])
    return finish(with_tail(x, sr, ir, -15.0, 0.5), sr, -7.0, 3.0, 80.0)


@sound("alert_aim")
def alert_aim(sr, rng):
    """A rifle coming up to the shoulder: sling and stock, the safety clicking off."""
    x = buf(0.24, sr)
    place(x, swish(sr, rng, 0.09, 700, 2800), 0.0, sr, 0.35)
    place(x, modal(0.06, sr, [(1900, 0.009, 1.0), (3200, 0.006, 0.7), (5100, 0.004, 0.4), (420, 0.012, 0.5)]), 0.06, sr, 0.9)
    place(x, click(sr, rng, 2200.0, 0.5), 0.06, sr, 0.3)
    for at, amp in [(0.11, 0.35), (0.14, 0.28), (0.18, 0.2)]:
        f = rng.uniform(2200, 3600)
        place(x, modal(0.03, sr, [(f, 0.005, 1.0), (f * 1.5, 0.003, 0.5)]), at, sr, amp)
    return finish(x, sr, -6.0, 1.0, 30.0)


@sound("alarm_bell")
def alarm_bell(sr, rng):
    """A hand bell, one stroke: what is left to raise the post with once the generator is dead."""
    f0 = 1180.0
    parts = [(1.0, 0.5, 1.0), (2.0, 0.36, 0.6), (2.76, 0.25, 0.5), (4.07, 0.16, 0.35), (5.4, 0.1, 0.25), (6.8, 0.07, 0.15)]
    modes = []
    for ratio, tau, amp in parts:
        modes += [(f0 * ratio, tau, amp * 0.78), (f0 * ratio * 1.0022, tau * 0.9, amp * 0.22)]
    x = modal(1.1, sr, modes)
    place(x, burst(0.03, sr, rng, 2000, 8000, 0.0003, 0.004), 0.0, sr, 0.5)
    place(x, modal(0.05, sr, [(640, 0.012, 1.0)]), 0.0, sr, 0.25)   # the clapper's knock
    return finish(x, sr, -4.0, 0.1, 200.0)


@sound("alert_reinforcements", LO)
def alert_reinforcements(sr, rng):
    """The barracks door thrown open and two men running out: boards first, then gravel."""
    x = buf(1.72, sr)
    door = [(120, 0.14, 1.0), (205, 0.11, 0.95), (360, 0.08, 0.85), (610, 0.055, 0.65), (980, 0.035, 0.45)]
    place(x, modal(0.6, sr, door), 0.0, sr, 0.9)
    place(x, burst(0.15, sr, rng, 300, 2500, 0.0005, 0.025), 0.0, sr, 0.9)
    for at in (0.045, 0.1):
        place(x, modal(0.08, sr, [(1700, 0.025, 1.0), (2900, 0.015, 0.6)]), at, sr, 0.22)
    for runner, offset in enumerate([0.26, 0.335]):
        for k in range(5 if runner == 0 else 4):
            at = offset + 0.3 * k + rng.uniform(-0.012, 0.012)
            fall = 1.0 - 0.1 * k
            foot = footstep(sr, rng, 80 + 8 * runner, 0.03, 0.3, 1.25)
            if k < 2:
                place(foot, modal(0.15, sr, [(260, 0.04, 1.0), (430, 0.03, 0.7), (700, 0.02, 0.4)]), 0.0, sr, 0.8)
            else:
                place(foot, gravel(sr, rng, 0.8)[:len(foot)], 0.02, sr, 0.5)
            place(x, foot, at, sr, 0.62 * fall)
    return finish(x, sr, -4.0, 0.2, 80.0)


# ================================================================ results and UI

WARM = [1.0, 0.24, 0.07, 0.11]


def warm(sr, dur, freq, tau, amp=1.0, attack=0.014):
    """A soft mallet tone with a little held breath of pure sine under it."""
    t = tt(dur, sr)
    return amp * (tone(dur, sr, freq, WARM, attack, tau) + 0.22 * np.sin(2.0 * np.pi * freq * t) * (1.0 - np.exp(-t / 0.08)) * np.exp(-t / (tau * 1.2)))


@sound("res_win", LO)
def res_win(sr, rng):
    """Mission won: two warm tones, a rising fifth, left to ring. Nothing triumphant."""
    x = buf(2.15, sr)
    place(x, warm(sr, 2.1, 392.0, 0.8), 0.0, sr, 1.0)
    place(x, warm(sr, 1.7, 587.33, 0.7), 0.44, sr, 0.95)
    place(x, warm(sr, 1.7, 196.0, 0.85, 1.0, 0.03), 0.44, sr, 0.3)
    ir = outdoor_ir(0.9, sr, rng, [(300, 3000, 0.3, 1.0)])
    return finish(with_tail(x, sr, ir, -17.0, 2.2), sr, -5.0, 1.0, 400.0)


@sound("res_lose", LO)
def res_lose(sr, rng):
    """Mission lost: one low padded blow and a minor third sinking away."""
    dur = 1.8
    x = buf(dur, sr)
    place(x, thud(0.7, sr, 120, 58, 0.13, 3.2, 0.05), 0.0, sr, 0.7)
    place(x, thump(0.5, sr, rng, 85, 0.07, 1.0, 0.0), 0.0, sr, 1.0)
    sink = 2.0 ** (-0.35 * tt(1.7, sr) / 1.7 / 12.0)
    place(x, tone(1.7, sr, 146.83 * sink, [0.5, 1.0, 0.8, 0.5, 0.3, 0.12], 0.04, 0.6, 0.0012, 0.2), 0.02, sr, 0.5)
    place(x, tone(1.7, sr, 174.61 * sink, [0.5, 1.0, 0.7, 0.4, 0.2], 0.05, 0.55, 0.0012, 0.2), 0.02, sr, 0.4)
    ir = outdoor_ir(0.8, sr, rng, [(200, 2000, 0.3, 1.0)])
    return finish(with_tail(x, sr, ir, -15.0, 1.9), sr, -3.0, 0.5, 400.0)


@sound("res_objective", LO)
def res_objective(sr, rng):
    """An objective done: one warm tone with its fifth, small."""
    x = buf(0.8, sr)
    place(x, warm(sr, 0.8, 587.33, 0.3), 0.0, sr, 1.0)
    place(x, warm(sr, 0.7, 880.0, 0.22), 0.07, sr, 0.4)
    return finish(x, sr, -8.0, 1.0, 150.0)


@sound("res_checkpoint")
def res_checkpoint(sr, rng):
    """Checkpoint: a pencil tick on the map board. The point touches, a short stroke down, a longer one up."""
    x = buf(0.34, sr)
    place(x, modal(0.03, sr, [(2400, 0.004, 1.0), (4100, 0.003, 0.6), (900, 0.006, 0.6)]), 0.0, sr, 0.35)

    def stroke(dur, rise):
        n = n_of(dur, sr)
        tooth = 0.5 + 0.5 * np.clip(lp(white(n, rng), 320.0, sr) * 8.0, -1.0, 1.0)
        move = np.linspace(0.0, 1.0, n)
        noise = white(n, rng)
        y = bp(noise, 2200, 5200, sr) * (1.0 - rise * move) + bp(noise, 3600, 8500, sr) * rise * move
        return (y + 0.5 * bp(noise, 650, 1300, sr)) * tooth * hump(dur, sr, 0.6, 0.7)   # the board under the paper

    place(x, stroke(0.065, 0.2), 0.012, sr, 0.7)
    place(x, stroke(0.17, 1.0), 0.115, sr, 1.0)
    return finish(x, sr, -8.0, 0.3, 25.0)


@sound("ui_page")
def ui_page(sr, rng):
    """Back to the checkpoint: a page of the notebook turned back."""
    dur = 0.3
    n = n_of(dur, sr)
    x = bp(white(n, rng), 1400, 7000, sr) * hump(dur, sr, 0.55, 1.2) * (0.7 + 0.3 * np.sin(2.0 * np.pi * 38.0 * tt(dur, sr)))
    x += 0.4 * bp(white(n, rng), 500, 1400, sr) * hump(dur, sr, 0.5, 1.5)
    place(x, modal(0.03, sr, [(1900, 0.005, 1.0), (3300, 0.003, 0.5)]), 0.25, sr, 0.4)
    return finish(x, sr, -10.0, 3.0, 30.0)


@sound("ui_tap")
def ui_tap(sr, rng):
    """Any button: a soft rounded tick."""
    x = modal(0.07, sr, [(1500, 0.009, 1.0), (3000, 0.005, 0.3), (750, 0.008, 0.4)])
    return finish(x, sr, -10.0, 0.3, 15.0)


@sound("ui_arm")
def ui_arm(sr, rng):
    """A weapon or tool armed: a small two-stage metallic click."""
    x = buf(0.17, sr)
    place(x, modal(0.06, sr, [(2100 * 1.2, 0.01, 1.0), (3400 * 1.2, 0.007, 0.7), (5600 * 1.2, 0.004, 0.4)]), 0.0, sr, 0.55)
    place(x, modal(0.1, sr, [(2100, 0.018, 1.0), (3400, 0.012, 0.7), (5600, 0.007, 0.4), (980, 0.014, 0.6)]), 0.048, sr, 1.0)
    place(x, click(sr, rng, 2000.0, 0.4), 0.048, sr, 0.3)
    return finish(x, sr, -8.0, 0.2, 25.0)


def blip(sr, dur, freq, odd):
    t = tt(dur, sr)
    x = np.sin(2.0 * np.pi * freq * t) + 0.18 * np.sin(4.0 * np.pi * freq * t)
    if odd:
        x += sum(np.sin(2.0 * np.pi * freq * k * t) / k ** 2 for k in (3, 5, 7))
    return x * hump(dur, sr, 0.25, 0.8)


@sound("ui_deny")
def ui_deny(sr, rng):
    """Not possible: two flat falling notes."""
    x = buf(0.2, sr)
    place(x, blip(sr, 0.07, 392.0, True), 0.0, sr, 1.0)
    place(x, blip(sr, 0.09, 311.13, True), 0.09, sr, 0.9)
    return finish(lp(x, 2600.0, sr), sr, -10.0, 1.0, 20.0)


@sound("ui_confirm")
def ui_confirm(sr, rng):
    """Confirmed: two soft rising notes (the same fifth as the win motif)."""
    x = buf(0.2, sr)
    place(x, blip(sr, 0.07, 784.0, False), 0.0, sr, 0.9)
    place(x, blip(sr, 0.1, 1174.66, False), 0.075, sr, 1.0)
    return finish(x, sr, -10.0, 1.0, 30.0)


# ================================================================ harbour sounds (recipes kept; see NOT_SHIPPED)

def wrap_add(buffer, x, at, sr, gain=1.0):
    """Mixes x into a loop buffer at `at` seconds, wrapping round the end: the seam stays invisible."""
    n = len(buffer)
    i = int(round(at * sr)) % n
    idx = (np.arange(min(len(x), n)) + i) % n
    np.add.at(buffer, idx, gain * x[:len(idx)])


def bubble(sr, dur, f0, rise=0.6):
    """One bubble: a tiny sine that slides up as it rises and dies quickly."""
    t = tt(dur, sr)
    f = f0 * (1.0 + rise * t / dur)
    return np.sin(2.0 * np.pi * np.cumsum(f) / sr) * np.exp(-t / (dur * 0.35)) * (1.0 - np.exp(-t / 0.002))


@sound("amb_river", LO, loop=True)
def amb_river(sr, rng):
    """The Garonne on the ebb against a granite quay at night: a dark, moving body of water, small waves
    slapping the stones at uneven intervals (a hollow clop and a short wash back), and gurgles where the
    water sucks at the joints of the wall. Nine seconds, exactly periodic."""
    n = n_of(9.0, sr)
    swell = 0.55 + 0.45 * periodic_lfo(n, rng, [1, 2, 3])
    out = 0.15 * swell * periodic_noise(n, sr, rng, band_shape(110, 600, 1.0, -4.0))
    out += 0.045 * (0.6 + 0.4 * swell) * periodic_noise(n, sr, rng, band_shape(1300, 5200, 1.0, -3.0))
    for at, size in [(0.4, 1.0), (1.55, 0.5), (2.3, 0.8), (3.9, 0.42), (4.6, 0.95), (5.9, 0.55), (6.7, 0.85), (8.1, 0.48)]:
        event = buf(1.0, sr)
        place(event, modal(0.3, sr, [(rng.uniform(190, 260), 0.03, 1.0), (rng.uniform(380, 520), 0.02, 0.6),
                                     (rng.uniform(800, 1100), 0.012, 0.3)]), 0.0, sr, 0.45)
        place(event, burst(0.12, sr, rng, 500, 2600, 0.003, 0.03), 0.0, sr, 0.7)
        place(event, burst(0.9, sr, rng, 700, 3800, 0.08, 0.28), 0.05, sr, 0.24)
        wrap_add(out, event, at, sr, 0.5 * size)
    for _ in range(16):
        dur = rng.uniform(0.04, 0.1)
        wrap_add(out, bubble(sr, dur, rng.uniform(300, 750)), rng.uniform(0.0, 9.0), sr, rng.uniform(0.04, 0.09))
    return finish_loop(out, -6.0)


@sound("amb_transformer", LO, loop=True)
def amb_transformer(sr, rng):
    """The switch house on the quay: a transformer on 50 Hz mains humming at twice the mains (the core's
    magnetostriction), with a thin buzz of loose laminations at every peak. One second, exactly periodic."""
    n = n_of(1.0, sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for k, amp in enumerate([1.0, 0.6, 0.46, 0.32, 0.2, 0.14, 0.08, 0.05], start=1):
        out += amp * np.sin(2.0 * np.pi * 100.0 * k * t + 0.7 * k)
    chatter = np.maximum(0.0, np.sin(2.0 * np.pi * 100.0 * t)) ** 8
    out += 0.6 * periodic_filter(chatter - np.mean(chatter), sr, [(1800, 4.0, 1.0), (3100, 5.0, 0.6)])
    out *= 1.0 + 0.05 * np.sin(2.0 * np.pi * 3.0 * t)
    out += 0.03 * periodic_noise(n, sr, rng, band_shape(300, 3000, 1.0, -3.0))
    return finish_loop(out, -6.0)


@sound("amb_torrent", LO, loop=True)
def amb_torrent(sr, rng):
    """The Måna far down in its gorge in February: low water running fast between stones and shelves of ice. A
    steady rush with a slow swell, a brighter spray riding on it, and water burbling over stones at random.
    Eight seconds, exactly periodic."""
    n = n_of(8.0, sr)
    swell = 0.7 + 0.3 * periodic_lfo(n, rng, [1, 2, 3, 5])
    out = 0.32 * swell * periodic_noise(n, sr, rng, band_shape(120, 900, 0.9, -3.5))
    out += 0.08 * (0.5 + 0.5 * periodic_lfo(n, rng, [2, 3, 7])) * periodic_noise(n, sr, rng, band_shape(1600, 6000, 1.0, -2.0))
    for _ in range(70):
        dur = rng.uniform(0.03, 0.09)
        wrap_add(out, bubble(sr, dur, rng.uniform(260, 900), rng.uniform(0.3, 0.9)), rng.uniform(0.0, 8.0), sr, rng.uniform(0.03, 0.08))
    return finish_loop(out, -6.0)


@sound("amb_hydro", LO, loop=True)
def amb_hydro(sr, rng):
    """A hydroelectric station at night, heard from outside: the generators' deep 50 Hz hum and its harmonics,
    the whine of the turbines turning, and water roaring down the penstocks under it all. Two seconds, exactly
    periodic (the whine on a whole number of cycles)."""
    n = n_of(2.0, sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for k, amp in enumerate([1.0, 0.7, 0.42, 0.3, 0.18, 0.1], start=1):
        out += 0.28 * amp * np.sin(2.0 * np.pi * 50.0 * k * t + 0.9 * k)
    whine = sum(a * np.sin(2.0 * np.pi * f * t + p) for f, a, p in [(431.0, 1.0, 0.3), (862.0, 0.35, 1.1), (1293.0, 0.12, 2.0)])
    out += 0.12 * whine * (1.0 + 0.15 * np.sin(2.0 * np.pi * 0.5 * t))
    out += 0.4 * periodic_noise(n, sr, rng, band_shape(40, 420, 1.0, -4.0))
    out += 0.07 * periodic_noise(n, sr, rng, band_shape(900, 3500, 1.0, -3.0))
    return finish_loop(out, -6.0)


@sound("amb_clank_1", LO)
def amb_clank_1(sr, rng):
    """Far off on the building site: a steel shuttering plate let fall onto others, ringing, and a smaller knock."""
    x = buf(1.6, sr)
    plate = [(310, 0.35, 1.0), (523, 0.28, 0.8), (811, 0.22, 0.7), (1290, 0.15, 0.5), (1935, 0.1, 0.35), (2710, 0.06, 0.2)]
    place(x, modal(1.4, sr, plate, rng, 0.02), 0.0, sr, 1.0)
    place(x, burst(0.05, sr, rng, 600, 4000, 0.0005, 0.01), 0.0, sr, 0.8)
    place(x, modal(0.8, sr, [(f * 1.12, tau * 0.6, a) for f, tau, a in plate]), 0.34, sr, 0.4)
    return finish(far_away(x, sr, rng, 2.2), sr, -6.0, 1.0, 150.0)


@sound("amb_clank_2", LO)
def amb_clank_2(sr, rng):
    """A chain paying out somewhere on the river: a run of links over a steel lip, slowing to a stop."""
    x = buf(1.6, sr)
    at, gap = 0.0, 0.07
    for k in range(11):
        f = rng.uniform(1100, 1700)
        place(x, modal(0.12, sr, [(f, 0.03, 1.0), (f * 1.63, 0.02, 0.5), (f * 0.51, 0.04, 0.6)]), at, sr,
              rng.uniform(0.5, 1.0) * (1.0 - k / 14.0))
        place(x, click(sr, rng, 1500.0, 0.6), at, sr, 0.3)
        at += gap
        gap *= 1.12
    return finish(far_away(x, sr, rng, 2.2), sr, -6.0, 1.0, 150.0)


@sound("amb_horn", LO)
def amb_horn(sr, rng):
    """A tug's steam whistle far down the Garonne: one long note from three pipes not quite in tune with each
    other, breathy at the start and sagging a little as the pressure drops."""
    dur = 2.4
    t = tt(dur, sr)
    env = (1.0 - np.exp(-t / 0.12)) * np.clip((dur - t) / 0.5, 0.0, 1.0) ** 1.5
    sag = 1.0 - 0.012 * t / dur + 0.002 * lp(white(len(t), rng), 6.0, sr) * 20.0
    x = np.zeros(len(t))
    for f0, amp in [(185.0, 1.0), (220.0, 0.7), (277.2, 0.5)]:
        ph = 2.0 * np.pi * np.cumsum(f0 * sag) / sr
        x += amp * (np.sin(ph) + 0.45 * np.sin(2.0 * ph) + 0.25 * np.sin(3.0 * ph) + 0.1 * np.sin(4.0 * ph))
    x += 0.5 * bp(white(len(t), rng), 300, 2400, sr) * np.exp(-t / 0.25)   # steam before the note settles
    x *= env
    ir = outdoor_ir(2.2, sr, rng, [(150, 1500, 0.7, 1.0)])
    return finish(with_tail(lp(x, 2200.0, sr), sr, ir, -3.0, 4.6), sr, -6.0, 5.0, 300.0)


@sound("act_fuse")
def act_fuse(sr, rng):
    """A time pencil set: the copper tube squeezed until the glass ampoule inside cracks (a small muffled
    crunch), then the safety strip drawn out (a thin metal slide and a tick)."""
    x = buf(0.6, sr)
    place(x, grains(0.06, sr, rng, 9000, 900, 9000, 0.7) * env_ad(0.06, sr, 0.001, 0.02), 0.0, sr, 1.0)
    place(x, modal(0.05, sr, [(4200, 0.006, 1.0), (6100, 0.004, 0.6)]), 0.004, sr, 0.25)
    place(x, thump(0.08, sr, rng, 300, 0.012, 0.6, 0.2), 0.0, sr, 0.35)
    place(x, swish(sr, rng, 0.12, 2500, 7000, 0.6), 0.32, sr, 0.25)
    place(x, modal(0.04, sr, [(3300, 0.006, 1.0), (5200, 0.004, 0.5)]), 0.44, sr, 0.5)
    place(x, click(sr, rng, 2500.0, 0.4), 0.44, sr, 0.3)
    return finish(x, sr, -7.0, 0.3, 30.0)


@sound("act_dip", LO)
def act_dip(sr, rng):
    """A placing rod (or a paddle blade) slipped into still water: a soft plunge, bubbles, drips off the shaft."""
    x = buf(1.0, sr)
    place(x, burst(0.25, sr, rng, 300, 1800, 0.01, 0.06), 0.0, sr, 0.6)
    place(x, thud(0.15, sr, 260, 180, 0.04, 1.5), 0.0, sr, 0.2)
    for _ in range(6):
        place(x, bubble(sr, rng.uniform(0.03, 0.07), rng.uniform(450, 1000)), rng.uniform(0.04, 0.3), sr, rng.uniform(0.15, 0.35))
    for at in (0.5, 0.68, 0.83):
        place(x, bubble(sr, 0.025, rng.uniform(1300, 1900), 0.3), at, sr, 0.18)
    return finish(x, sr, -6.0, 3.0, 60.0)


@sound("act_hull_scrape", LO)
def act_hull_scrape(sr, rng):
    """The limpet on its rod finding the hull below the waterline: steel sliding on steel through water,
    a dull scrape with the big plate ringing low under it."""
    x = buf(1.0, sr)
    scrape = stick_slip(0.5, sr, rng, 60.0, 35.0, [(420, 6.0, 1.0), (760, 7.0, 0.7), (1300, 6.0, 0.4)], 0.4)
    place(x, scrape * hump(0.5, sr, 0.4), 0.0, sr, 0.6)
    place(x, modal(0.9, sr, [(190, 0.25, 0.6), (304, 0.2, 0.8), (462, 0.15, 0.6), (680, 0.1, 0.4)]), 0.05, sr, 0.25)
    return finish(lp(x, 1800.0, sr), sr, -6.0, 5.0, 80.0)


@sound("act_limpet", LO)
def act_limpet(sr, rng):
    """The limpet's magnets take the hull: a heavy flat clonk through the water and the ship's plating
    answering, low and long, the way a bell sounds under a blanket."""
    x = buf(1.6, sr)
    plating = [(144, 0.5, 0.8), (236, 0.42, 0.9), (342, 0.35, 1.0), (492, 0.28, 0.8), (704, 0.2, 0.55), (1010, 0.13, 0.35)]
    place(x, modal(1.5, sr, plating, rng, 0.01), 0.0, sr, 1.0)
    place(x, thud(0.2, sr, 240, 120, 0.04, 3.0), 0.0, sr, 0.8)
    place(x, burst(0.04, sr, rng, 400, 2200, 0.0005, 0.008), 0.0, sr, 0.6)
    return finish(lp(x, 1600.0, sr), sr, -4.0, 0.3, 120.0)


@sound("act_satchel", LO)
def act_satchel(sr, rng):
    """A canvas satchel of explosive set down against concrete: a heavy soft thump, the canvas settling."""
    x = buf(0.6, sr)
    place(x, thump(0.3, sr, rng, 95, 0.05, 0.7, 0.3), 0.0, sr, 1.0)
    place(x, swish(sr, rng, 0.25, 700, 3000), 0.05, sr, 0.35)
    gear_rattle(sr, rng, x, 0.04, 2, 0.25)
    return finish(x, sr, -5.0, 2.0, 40.0)


@sound("act_charge", LO)
def act_charge(sr, rng):
    """The charge strapped tight against the pier: a strap pulled hard through its buckle, the buckle
    biting, and a flat slap of the hand on the packed charge."""
    x = buf(0.7, sr)
    place(x, swish(sr, rng, 0.18, 1200, 5000, 0.7), 0.0, sr, 0.5)
    place(x, modal(0.06, sr, [(2300, 0.01, 1.0), (3700, 0.007, 0.6), (1100, 0.012, 0.5)]), 0.17, sr, 0.6)
    place(x, click(sr, rng, 2000.0, 0.5), 0.17, sr, 0.3)
    place(x, thump(0.25, sr, rng, 120, 0.035, 0.9, 0.25), 0.34, sr, 1.0)
    return finish(x, sr, -5.0, 2.0, 40.0)


@sound("act_switch")
def act_switch(sr, rng):
    """The harbour's main switch pulled: a big knife switch breaking under load. The blades jump out of their
    jaws with a heavy clack, an arc spits for a moment, the transformer's hum sinks away, and contactors drop
    out one after another down the quay."""
    x = buf(2.6, sr)
    place(x, modal(0.4, sr, [(330, 0.07, 1.0), (590, 0.05, 0.8), (980, 0.04, 0.6), (1620, 0.025, 0.45), (2600, 0.015, 0.3)]), 0.0, sr, 0.9)
    place(x, burst(0.04, sr, rng, 1500, 9000, 0.0003, 0.006), 0.0, sr, 0.9)
    arc = 0.3
    t = tt(arc, sr)
    crackle = grains(arc, sr, rng, 2500.0 * np.exp(-t / 0.1), 1500, 10000, 0.9)
    buzz = sum(np.sin(2.0 * np.pi * 100.0 * k * t) / k for k in range(1, 13)) * np.exp(-t / 0.08)
    place(x, crackle / max(np.max(np.abs(crackle)), 1e-9) + 0.3 * buzz, 0.005, sr, 0.6)
    t = tt(1.6, sr)
    hum = sum(a * np.sin(2.0 * np.pi * 100.0 * k * t) for k, a in enumerate([1.0, 0.6, 0.45, 0.3], start=1))
    place(x, hum * np.exp(-t / 0.35), 0.05, sr, 0.22)
    for at, amp in [(0.45, 0.4), (0.8, 0.3), (1.25, 0.22)]:
        c = modal(0.15, sr, [(900, 0.02, 1.0), (1500, 0.015, 0.6), (2600, 0.008, 0.3)], rng, 0.08)
        place(x, lp(c, 2500.0, sr), at, sr, amp)
    ir = outdoor_ir(0.6, sr, rng, [(300, 3000, 0.15, 1.0)])
    return finish(with_tail(x, sr, ir, -10.0, 2.8), sr, -3.0, 0.2, 200.0)


@sound("act_paddle", LO)
def act_paddle(sr, rng):
    """Two strokes of a double paddle, careful and close: the blade slipping in, the pull swirling along the
    canvas hull, the blade lifting out with a trickle of drips. One side, then the other."""
    x = buf(2.6, sr)
    for at, gain in [(0.0, 1.0), (1.25, 0.85)]:
        place(x, burst(0.12, sr, rng, 500, 2400, 0.02, 0.04), at, sr, 0.45 * gain)
        t = tt(0.6, sr)
        swirl = bp(white(len(t), rng), 250, 1200, sr) * hump(0.6, sr, 0.3) * (1.0 + 0.4 * np.sin(2.0 * np.pi * 7.0 * t))
        place(x, swirl, at + 0.05, sr, 0.35 * gain)
        place(x, burst(0.2, sr, rng, 1200, 5000, 0.01, 0.05), at + 0.62, sr, 0.3 * gain)
        for _ in range(4):
            place(x, bubble(sr, 0.025, rng.uniform(1200, 2000), 0.3), at + rng.uniform(0.7, 1.1), sr, 0.15 * gain)
    return finish(x, sr, -6.0, 3.0, 80.0)


@sound("act_match")
def act_match(sr, rng):
    """A match struck for two cigarettes: the head dragged hard along the box (a rasp), the flare catching with a
    soft roar, then a slow breath of smoke let out."""
    x = buf(1.4, sr)
    d = 0.11
    t = tt(d, sr)
    rasp = grains(d, sr, rng, 4000.0 + 18000.0 * t / d, 1800, 9000, 0.8)
    rasp = rasp / max(np.max(np.abs(rasp)), 1e-9) * hump(d, sr, 0.6)
    place(x, rasp, 0.0, sr, 0.8)
    place(x, burst(0.45, sr, rng, 500, 6000, 0.006, 0.12), 0.10, sr, 0.9)       # the flare
    place(x, burst(0.30, sr, rng, 150, 900, 0.01, 0.10), 0.10, sr, 0.4)
    t = tt(0.6, sr)
    breath = bp(white(len(t), rng), 300, 2600, sr) * hump(0.6, sr, 0.25, 1.5)
    place(x, breath, 0.75, sr, 0.18)
    return finish(x, sr, -6.0, 0.5, 120.0)


@sound("act_cosh", LO)
def act_cosh(sr, rng):
    """A leather cosh on the back of a cap: a short swing, one deadened smack (lead shot in leather, no ring
    at all), a grunt of breath going out of him."""
    x = buf(0.5, sr)
    place(x, swish(sr, rng, 0.09, 600, 2600, 0.7), 0.0, sr, 0.35)
    place(x, thump(0.25, sr, rng, 110, 0.03, 0.9, 0.35), 0.08, sr, 1.0)
    place(x, burst(0.05, sr, rng, 1500, 4500, 0.0008, 0.008), 0.08, sr, 0.5)       # leather on cloth
    place(x, burst(0.18, sr, rng, 250, 900, 0.01, 0.06), 0.12, sr, 0.25)           # breath knocked out
    return finish(x, sr, -4.0, 2.0, 40.0)


@sound("act_bottle_smash")
def act_bottle_smash(sr, rng):
    """An empty wine bottle landing on setts: the bright crack of the glass going, then shards skittering and
    tinkling out across the stones."""
    x = buf(1.1, sr)
    glass = [(2350.0, 0.05, 1.0), (3460.0, 0.04, 0.7), (5120.0, 0.03, 0.5), (6900.0, 0.02, 0.35)]
    place(x, burst(0.04, sr, rng, 2500, 11000, 0.0004, 0.01), 0.0, sr, 1.0)        # the crack
    place(x, modal(0.2, sr, glass, rng, 0.06), 0.0, sr, 0.7)
    place(x, thump(0.12, sr, rng, 180, 0.02, 0.8, 0.2), 0.0, sr, 0.35)
    for _ in range(14):
        at = rng.uniform(0.03, 0.75)
        f = rng.uniform(3200.0, 8800.0)
        place(x, modal(0.07, sr, [(f, 0.012, 1.0), (f * 1.53, 0.008, 0.5)]), at, sr, rng.uniform(0.08, 0.3) * (1.0 - at))
    return finish(x, sr, -5.0, 0.3, 30.0)


@sound("fin_underwater", LO)
def fin_underwater(sr, rng):
    """A limpet going off against a ship's bottom, heard from the quay: the shock as a deep blunt whump
    through the water and the hull, the plates ringing, then the column of water thrown up roaring and
    coming down again like a cloudburst."""
    total = 5.0
    x = buf(total, sr)
    place(x, thud(1.2, sr, 95, 38, 0.35, 3.5, 0.06), 0.0, sr, 1.0)
    place(x, burst(0.8, sr, rng, 60, 400, 0.004, 0.18), 0.0, sr, 0.9)
    place(x, burst(0.4, sr, rng, 300, 1600, 0.002, 0.07), 0.0, sr, 1.1)
    place(x, modal(1.6, sr, [(118, 0.6, 0.6), (171, 0.5, 0.6), (246, 0.4, 0.5), (352, 0.3, 0.4), (505, 0.2, 0.3)], rng, 0.02), 0.02, sr, 0.3)
    d = 4.4
    t = tt(d, sr)
    rise = np.clip(t / 0.25, 0.0, 1.0) * np.exp(-t / 0.9)
    fall = np.exp(-((t - 2.0) / 1.0) ** 2)
    place(x, bp(white(len(t), rng), 400, 5000, sr) * rise, 0.08, sr, 0.55)
    rain = grains(d, sr, rng, 6000.0 * fall + 200.0, 700, 7000, 0.8)
    rain = rain / max(np.max(np.abs(rain)), 1e-9) + 0.4 * bp(white(len(t), rng), 500, 3000, sr) * fall
    place(x, rain * fall, 0.08, sr, 0.35)
    ir = outdoor_ir(2.5, sr, rng, [(80, 800, 0.8, 1.0), (500, 2500, 0.4, 0.5)])
    x = echoes(with_tail(x, sr, ir, -6.0, total), sr, [(0.32, -8.0, 900.0), (0.71, -12.0, 700.0)], total)
    return finish(x, sr, PEAK_LIMIT, 0.5, 400.0)


@sound("fin_blast", LO)
def fin_blast(sr, rng):
    """A demolition charge against a concrete pier, close: a hard crack, the blast, a long roll of thunder off
    the walls of the pens, then grit and lumps of concrete raining down on the apron."""
    total = 5.5
    x = buf(0.7, sr)
    place(x, hp(white(n_of(0.03, sr), rng), 1500, sr) * env_ad(0.03, sr, 0.0002, 0.003), 0.0, sr, 1.0)
    place(x, softclip(burst(0.5, sr, rng, 150, 4000, 0.0005, 0.06) * 1.8, 2.5), 0.0, sr, 0.9)
    place(x, thud(0.7, sr, 110, 42, 0.22, 3.5, 0.04), 0.0, sr, 0.9)
    place(x, burst(0.7, sr, rng, 50, 300, 0.002, 0.2), 0.0, sr, 0.8)
    x = softclip(x / np.max(np.abs(x)) * 1.3, 1.5)
    ir = outdoor_ir(3.2, sr, rng, [(60, 500, 1.1, 1.0), (300, 2400, 0.5, 0.6)])
    y = with_tail(x, sr, ir, -3.0, total)
    y = echoes(y, sr, [(0.09, -6.0, 2500.0), (0.23, -9.0, 1600.0), (0.47, -12.0, 1100.0), (0.9, -16.0, 800.0)], total, 200.0)
    d = 4.2
    t = tt(d, sr)
    patter = grains(d, sr, rng, 140.0 * np.exp(-((t - 1.0) / 0.9) ** 2) + 30.0 * np.exp(-t / 2.0), 500, 5000, 0.9)
    place(y, patter / max(np.max(np.abs(patter)), 1e-9), 0.5, sr, 0.18 * np.max(np.abs(y)))
    for _ in range(6):
        place(y, thump(0.2, sr, rng, rng.uniform(110, 190), 0.03, 0.9, 0.2), rng.uniform(0.8, 2.6), sr,
              rng.uniform(0.05, 0.12) * np.max(np.abs(y)))
    return finish(y, sr, PEAK_LIMIT, 0.3, 500.0)


@sound("fin_bell", LO)
def fin_bell(sr, rng):
    """Seven o'clock from a church tower across the city: one stroke of a big bronze bell (the hum, prime,
    minor third, fifth and nominal of a tuned bell, each a slowly beating pair), far off across the roofs."""
    f = 233.0
    modes = []
    for ratio, tau, amp in [(0.5, 4.0, 0.6), (1.0, 2.6, 0.8), (1.2, 2.0, 0.7), (1.5, 1.5, 0.45), (2.0, 1.4, 1.0),
                            (2.5, 0.9, 0.35), (3.0, 0.7, 0.3), (4.0, 0.5, 0.2)]:
        modes += [(f * ratio, tau, amp * 0.8), (f * ratio * 1.0018, tau * 0.92, amp * 0.25)]
    x = modal(5.0, sr, modes) * (1.0 - np.exp(-tt(5.0, sr) / 0.004))
    place(x, burst(0.04, sr, rng, 800, 4000, 0.0005, 0.008), 0.0, sr, 0.25)
    return finish(far_away(x, sr, rng, 5.6, -5.0), sr, -6.0, 1.0, 300.0)


@sound("fin_fire", LO)
def fin_fire(sr, rng):
    """Fire taking hold in a forward hold: a low roar of burning, crackle and the odd sharp pop, swelling and
    then settling. Eight seconds."""
    d = 8.0
    t = tt(d, sr)
    env = np.clip(t / 1.5, 0.0, 1.0) ** 1.5 * np.clip((d - t) / 2.5, 0.0, 1.0)
    flicker = 0.7 + 0.3 * np.clip(lp(white(len(t), rng), 3.0, sr) * 40.0, -1.0, 1.0)
    roar = lp(white(len(t), rng), 450.0, sr)
    roar /= np.max(np.abs(roar))
    crackle = grains(d, sr, rng, 70.0 + 50.0 * flicker, 1400, 7000, 1.0)
    crackle /= np.max(np.abs(crackle))
    x = (0.55 * roar * flicker + 0.6 * crackle) * env
    for _ in range(9):
        at = rng.uniform(1.0, d - 2.0)
        place(x, thump(0.08, sr, rng, rng.uniform(300, 600), 0.01, 1.0, 0.1), at, sr, 0.5 * env[int(at * sr)])
    return finish(x, sr, -6.0, 50.0, 500.0)


@sound("fin_boom", LO)
def fin_boom(sr, rng):
    """A ship's cargo or a U-boat's torpedoes going up: a split-second crack, then an enormous low detonation that
    shoves the air, the fireball roaring as it climbs, thunder rolling back off the pens and the city for seconds,
    and the rain of steel and water coming down after it. Eight seconds."""
    total = 8.0
    x = buf(1.2, sr)
    place(x, hp(white(n_of(0.04, sr), rng), 1200, sr) * env_ad(0.04, sr, 0.0002, 0.006), 0.0, sr, 1.0)
    place(x, softclip(burst(0.9, sr, rng, 80, 3500, 0.0008, 0.12) * 2.2, 3.0), 0.0, sr, 1.0)
    place(x, thud(1.2, sr, 70, 26, 0.45, 4.0, 0.08), 0.0, sr, 1.3)
    place(x, thud(1.0, sr, 140, 48, 0.25, 3.0, 0.03), 0.004, sr, 0.8)
    place(x, burst(1.1, sr, rng, 30, 220, 0.004, 0.35), 0.0, sr, 1.0)
    x = softclip(x / np.max(np.abs(x)) * 1.5, 1.8)
    ir = outdoor_ir(4.5, sr, rng, [(40, 400, 1.6, 1.0), (200, 1800, 0.8, 0.6), (1500, 5000, 0.3, 0.2)])
    y = with_tail(x, sr, ir, -2.0, total)
    y = echoes(y, sr, [(0.18, -5.0, 1800.0), (0.44, -8.0, 1200.0), (0.83, -11.0, 900.0), (1.4, -14.0, 700.0), (2.2, -18.0, 500.0)], total, 120.0)
    # the fireball: a low roar swelling and dying away
    d = 3.5
    t = tt(d, sr)
    roar = lp(white(len(t), rng), 300.0, sr)
    roar /= max(np.max(np.abs(roar)), 1e-9)
    place(y, roar * np.clip(t / 0.15, 0.0, 1.0) * np.exp(-t / 1.1), 0.05, sr, 0.35 * np.max(np.abs(y)))
    # what was thrown up coming down: clangs, splashes, patter
    d2 = 5.0
    t2 = tt(d2, sr)
    patter = grains(d2, sr, rng, 220.0 * np.exp(-((t2 - 1.6) / 1.2) ** 2) + 20.0 * np.exp(-t2 / 2.5), 600, 6000, 0.9)
    place(y, patter / max(np.max(np.abs(patter)), 1e-9), 0.9, sr, 0.14 * np.max(np.abs(y)))
    for _ in range(9):
        f = rng.uniform(300, 900)
        place(y, modal(0.6, sr, [(f, 0.12, 1.0), (f * 2.31, 0.07, 0.5), (f * 3.7, 0.04, 0.3)]), rng.uniform(1.0, 3.6), sr,
              rng.uniform(0.03, 0.08) * np.max(np.abs(y)))
    for _ in range(7):
        place(y, thump(0.25, sr, rng, rng.uniform(90, 170), 0.05, 0.9, 0.25), rng.uniform(1.0, 3.8), sr,
              rng.uniform(0.05, 0.12) * np.max(np.abs(y)))
    return finish(y, sr, PEAK_LIMIT, 0.3, 400.0)


@sound("fin_creak", LO)
def fin_creak(sr, rng):
    """Steel giving way: the tower crane's mast, cut through at its foot, groaning as it starts to lean, rivets
    letting go one after another. Three seconds."""
    d = 3.0
    t = tt(d, sr)
    groan = stick_slip(d, sr, rng, 14.0, 70.0, [(95, 7.0, 1.0), (151, 6.0, 0.8), (233, 5.0, 0.6), (390, 4.0, 0.35)], 0.35)
    groan /= max(np.max(np.abs(groan)), 1e-9)
    env = np.clip(t / 0.6, 0.0, 1.0) * np.clip((d - t) / 0.4, 0.0, 1.0)
    x = groan * env * (0.6 + 0.4 * t / d)
    for _ in range(6):
        f = rng.uniform(700, 1600)
        place(x, modal(0.25, sr, [(f, 0.06, 1.0), (f * 1.7, 0.03, 0.4)]) * 0.5, rng.uniform(0.3, d - 0.4), sr, 0.4)
    ir = outdoor_ir(1.5, sr, rng, [(80, 1200, 0.7, 1.0)])
    return finish(with_tail(x, sr, ir, -8.0, d + 1.0), sr, -6.0, 5.0, 200.0)


@sound("fin_crash", LO)
def fin_crash(sr, rng):
    """The tower crane coming down across the yard: the jib and the mast landing in a long crumpling crash of steel
    lattice, a deep thud through the ground, then the clatter of loose pieces and a cloud of grit. Five seconds."""
    total = 5.0
    x = buf(2.5, sr)
    place(x, thud(1.0, sr, 85, 32, 0.35, 3.5, 0.05), 0.0, sr, 1.0)
    place(x, burst(0.8, sr, rng, 60, 2500, 0.001, 0.2), 0.0, sr, 0.9)
    # the lattice hitting along its length, a few tenths apart
    for k in range(14):
        at = 0.02 + k * 0.07 + rng.uniform(0.0, 0.05)
        f = rng.uniform(180, 600)
        place(x, modal(0.9, sr, [(f, 0.25, 1.0), (f * 1.93, 0.16, 0.6), (f * 2.87, 0.1, 0.45), (f * 4.1, 0.06, 0.3)], rng, 0.02), at, sr,
              rng.uniform(0.35, 0.7) * np.exp(-k / 9.0))
        place(x, burst(0.12, sr, rng, 800, 6000, 0.0005, 0.03), at, sr, 0.3 * np.exp(-k / 9.0))
    x = softclip(x / np.max(np.abs(x)) * 1.3, 1.5)
    ir = outdoor_ir(2.8, sr, rng, [(60, 600, 1.0, 1.0), (400, 3000, 0.5, 0.5)])
    y = with_tail(x, sr, ir, -4.0, total)
    y = echoes(y, sr, [(0.2, -8.0, 1500.0), (0.5, -12.0, 1000.0)], total, 150.0)
    d = 3.5
    t = tt(d, sr)
    rattle = grains(d, sr, rng, 160.0 * np.exp(-t / 1.0) + 15.0, 900, 7000, 0.9)
    place(y, rattle / max(np.max(np.abs(rattle)), 1e-9), 0.4, sr, 0.12 * np.max(np.abs(y)))
    return finish(y, sr, PEAK_LIMIT, 0.3, 400.0)


# ================================================================ La Boca (Operation Riachuelo)

@sound("amb_harbour", LO, loop=True)
def amb_harbour(sr, rng):
    """The Riachuelo at La Boca on a still night of falling snow: dark, heavy water with hardly any current, lapping in
    slow, low slops at the timber piles of the quay and the hulls moored along it, running back down the wood and
    sucking between the piles. The snow takes the top off everything: darker and quieter than the Garonne. Nine
    seconds, exactly periodic."""
    n = n_of(9.0, sr)
    swell = 0.5 + 0.5 * periodic_lfo(n, rng, [1, 2, 3])
    out = 0.17 * swell * periodic_noise(n, sr, rng, band_shape(90, 520, 1.0, -4.0))
    out += 0.045 * (0.5 + 0.5 * swell) * periodic_noise(n, sr, rng, band_shape(900, 3000, 1.0, -4.0))
    for at, size in [(0.2, 1.0), (1.45, 0.6), (2.75, 0.85), (4.3, 0.5), (5.35, 0.95), (6.8, 0.55), (7.85, 0.75)]:
        event = buf(1.6, sr)
        # the slop against a pile: a soft, low, wooden knock that hardly rings, the mass of water behind it,
        # a muffled splash where it breaks on the wood, then the water running back down it
        place(event, modal(0.3, sr, [(rng.uniform(105, 140), 0.05, 1.0), (rng.uniform(230, 300), 0.03, 0.55),
                                     (rng.uniform(470, 600), 0.016, 0.25)]), 0.03, sr, 0.4)
        place(event, burst(0.6, sr, rng, 160, 900, 0.05, 0.13), 0.0, sr, 0.9)
        place(event, burst(0.15, sr, rng, 450, 2000, 0.012, 0.04), 0.04, sr, 0.45)
        place(event, burst(1.4, sr, rng, 380, 2200, 0.15, 0.4), 0.12, sr, 0.24)
        wrap_add(out, event, at, sr, 0.5 * size)
        for _ in range(int(rng.integers(1, 4))):
            wrap_add(out, bubble(sr, rng.uniform(0.05, 0.12), rng.uniform(180, 420), rng.uniform(0.3, 0.7)),
                     at + rng.uniform(0.35, 0.9), sr, rng.uniform(0.04, 0.08) * size)
    return finish_loop(out, -6.0)


@sound("amb_hum", LO, loop=True)
def amb_hum(sr, rng):
    """The transporter bridge's machine house standing by through the night, heard through its doors: the electric
    motor that winds the gondola across, idling on the mains. A deep hum (the 50 Hz and its harmonics, the 100 Hz
    strongest), the armature turning 25 times a second (a slight throb, the soft whine of its 37 commutator bars,
    the brushes' hiss) and the breath of its cooling fan (eight blades). Two seconds, exactly periodic (50 turns)."""
    n = n_of(2.0, sr)
    t = np.arange(n) / sr
    turn = 25.0
    out = np.zeros(n)
    for k, amp in enumerate([0.2, 0.55, 0.3, 0.45, 0.2, 0.25, 0.08, 0.1], start=1):
        out += amp * np.sin(2.0 * np.pi * 50.0 * k * t + 0.8 * k)
    out *= 1.0 + 0.1 * np.sin(2.0 * np.pi * turn * t)
    whine = np.sin(2.0 * np.pi * 37.0 * turn * t + 0.4) + 0.35 * np.sin(2.0 * np.pi * 74.0 * turn * t + 1.7)
    out += 0.06 * whine * (1.0 + 0.25 * np.sin(2.0 * np.pi * turn * t + 0.5))
    pulse = np.maximum(0.0, np.sin(2.0 * np.pi * turn * t)) ** 2
    out += 0.05 * (0.6 + 0.4 * pulse) * periodic_noise(n, sr, rng, band_shape(1800, 4800, 0.8, -3.0))
    out += 0.16 * (0.75 + 0.25 * np.sin(2.0 * np.pi * 8.0 * turn * t)) * periodic_noise(n, sr, rng, band_shape(220, 1300, 1.0, -3.0))
    return finish_loop(out, -6.0)


# ================================================================ the cascarudos (the Plaza de Mayo)

#: A cascarudo is a beetle the size of a car: hard, dry chitin over a hollow body. Its shell's few low modes die fast;
#: the file it stridulates with rings the body's resonances (CHITIN, and LOW_CHITIN for the whole of it), and the
#: rim of the shell grinds on stone through GRIND.
SHELL = [(150, 0.07, 1.0), (265, 0.05, 0.9), (430, 0.035, 0.75), (690, 0.022, 0.55), (1100, 0.014, 0.4), (1750, 0.009, 0.28)]
CHITIN = [(420, 5.0, 0.7), (780, 7.0, 1.0), (1350, 8.0, 0.85), (2300, 9.0, 0.55), (3600, 8.0, 0.3)]
LOW_CHITIN = [(260, 4.0, 0.8), (520, 6.0, 1.0), (980, 7.0, 0.8), (1700, 8.0, 0.5), (2800, 8.0, 0.25)]
GRIND = [(240, 6.0, 0.7), (450, 8.0, 1.0), (820, 9.0, 0.8), (1400, 9.0, 0.5)]


def norm(x):
    return x / max(np.max(np.abs(x)), 1e-9)


def stroke(sr, rng, dur, rate_from, rate_to, body=CHITIN):
    """One stroke of the file under the scraper: its ridges struck one after another (rate_from to rate_to a second),
    each ringing the body. Strokes in a row are the cascarudo's rasp."""
    return norm(stick_slip(dur, sr, rng, rate_from, rate_to, body, 0.12) * hump(dur, sr, 0.35, 0.7))


def hiss(sr, rng, dur, lo=1300, hi=5200, skew=0.3):
    """Air forced out of the spiracles along its sides."""
    return norm(bp(white(n_of(dur, sr), rng), lo, hi, sr) * hump(dur, sr, skew, 1.2))


def joint(sr, rng, lo=1800, hi=3200):
    """A joint of a leg or a claw clicking: chitin on chitin, tiny and dry."""
    f = rng.uniform(lo, hi)
    return norm(modal(0.03, sr, [(f, 0.005, 1.0), (f * 1.6, 0.003, 0.5)]))


def mandibles(sr, rng):
    """The mandibles snapping shut: two hard edges meeting, a short dry ring."""
    x = modal(0.06, sr, [(1250, 0.012, 1.0), (2050, 0.008, 0.7), (3300, 0.005, 0.45), (480, 0.015, 0.35)], rng, 0.04)
    return norm(place(x, click(sr, rng, 1800.0, 0.4), 0.0, sr, 0.35))


def stab(sr, rng, low, crunch):
    """A pointed foot or a claw driven down through the snow: the weight behind it, the snow crushed, the tip knocking
    on the cobbles under it."""
    x = buf(0.16, sr)
    place(x, norm(thump(0.14, sr, rng, low, 0.035, 0.6, 0.3)), 0.0, sr, 0.8)
    place(x, norm(lp(grains(0.09, sr, rng, 1100.0 * env_ad(0.09, sr, 0.006, 0.03), 500, 2600, 0.9), 3000.0, sr)), 0.0, sr, crunch)
    f = rng.uniform(1050, 1450)
    place(x, norm(modal(0.05, sr, [(f, 0.009, 1.0), (f * 1.71, 0.006, 0.6), (f * 2.63, 0.004, 0.35)])), 0.004, sr, 0.35)
    return x


def tripod(sr, rng, weight, spread, crunch):
    """One tripod of a cascarudo's legs set down (a front and a hind leg on one side, the middle one on the other), a
    few hundredths of a second apart, with the joints of the three lifting clicking."""
    x = buf(0.32, sr)
    for at, amp in [(0.0, 1.0), (spread * 0.55, 0.7), (spread, 0.85)]:
        place(x, stab(sr, rng, rng.uniform(58, 72), crunch), at, sr, weight * amp)
    for _ in range(int(rng.integers(2, 4))):
        place(x, joint(sr, rng, 2200, 3600), rng.uniform(0.02, 0.2), sr, rng.uniform(0.08, 0.18))
    return x


for _i, (_weight, _spread, _crunch) in enumerate([(1.0, 0.07, 0.8), (0.9, 0.055, 0.95), (1.1, 0.085, 0.7)], start=1):
    @sound("cascarudo_step_%d" % _i, LO)
    def _cascarudo_step(sr, rng, weight=_weight, spread=_spread, crunch=_crunch):
        """A cascarudo's footfall (three variants): one tripod of its legs set down in the snow."""
        return finish(tripod(sr, rng, weight, spread, crunch), sr, -6.0, 0.5, 40.0)


@sound("cascarudo_rasp_1", LO)
def cascarudo_rasp_1(sr, rng):
    """A cascarudo senses someone: it stridulates, two strokes of the file (a short one, then a longer one slowing
    down), a breath of hiss under them."""
    x = buf(0.62, sr)
    place(x, stroke(sr, rng, 0.13, 95.0, 140.0), 0.0, sr, 0.8)
    place(x, stroke(sr, rng, 0.27, 130.0, 70.0), 0.17, sr, 1.0)
    place(x, hiss(sr, rng, 0.5), 0.04, sr, 0.22)
    ir = outdoor_ir(0.3, sr, rng, [(300, 2500, 0.08, 1.0)])
    return finish(with_tail(x, sr, ir, -14.0, 0.75), sr, -6.0, 1.0, 60.0)


@sound("cascarudo_rasp_2", LO)
def cascarudo_rasp_2(sr, rng):
    """A cascarudo goes for someone: its mandibles snap twice, then one long stroke of the file that quickens, hissing."""
    x = buf(0.62, sr)
    place(x, mandibles(sr, rng), 0.0, sr, 0.7)
    place(x, mandibles(sr, rng), 0.085, sr, 0.9)
    place(x, stroke(sr, rng, 0.38, 60.0, 150.0), 0.16, sr, 1.0)
    place(x, hiss(sr, rng, 0.42, 1500, 6000, 0.6), 0.18, sr, 0.25)
    ir = outdoor_ir(0.3, sr, rng, [(300, 2500, 0.08, 1.0)])
    return finish(with_tail(x, sr, ir, -14.0, 0.75), sr, -6.0, 1.0, 60.0)


@sound("cascarudo_rattle", LO)
def cascarudo_rattle(sr, rng):
    """A cascarudo coming into the square, still a street away: a long, low stridulation, five strokes that quicken
    and then slow, a hiss under them, carried along the avenue (the top rolled off, the fronts answering)."""
    x = buf(1.9, sr)
    at = 0.0
    for dur, rate_from, rate_to, amp in [(0.18, 50, 75, 0.6), (0.22, 60, 95, 0.8), (0.3, 70, 120, 1.0), (0.32, 110, 70, 0.9), (0.4, 80, 45, 0.7)]:
        place(x, stroke(sr, rng, dur, rate_from, rate_to, LOW_CHITIN), at, sr, amp)
        at += dur + rng.uniform(0.03, 0.07)
    place(x, hiss(sr, rng, 1.5, 900, 4200, 0.4), 0.1, sr, 0.25)
    return finish(far_away(x, sr, rng, 2.8), sr, -6.0, 3.0, 200.0)


@sound("cascarudo_shell")
def cascarudo_shell(sr, rng):
    """A rifle bullet striking a cascarudo's shell: a hard crack, the hollow body under it booming short and dry,
    a spray of chips."""
    x = buf(0.5, sr)
    place(x, hp(white(n_of(0.02, sr), rng), 2500.0, sr) * env_ad(0.02, sr, 0.0002, 0.0018), 0.0, sr, 1.0)
    place(x, norm(modal(0.45, sr, SHELL, rng, 0.03)), 0.0005, sr, 0.8)
    place(x, norm(burst(0.06, sr, rng, 900, 5000, 0.0005, 0.006)), 0.0, sr, 0.5)
    place(x, norm(grains(0.12, sr, rng, 2500.0 * env_ad(0.12, sr, 0.002, 0.03), 2500, 9000)), 0.004, sr, 0.3)
    return finish(x, sr, -4.0, 0.1, 60.0)


@sound("cascarudo_lunge", LO)
def cascarudo_lunge(sr, rng):
    """A cascarudo strikes: its front claws flung up with a clatter of joints and driven down into the snow, two
    heavy stabs, then it rears up over the one it has knocked down, stridulating slowly and hissing."""
    x = buf(1.5, sr)
    for _ in range(4):
        place(x, joint(sr, rng), rng.uniform(0.0, 0.07), sr, rng.uniform(0.3, 0.5))
    place(x, norm(swish(sr, rng, 0.12, 300, 1600, 0.7)), 0.0, sr, 0.3)
    for at, amp in [(0.1, 1.0), (0.135, 0.8)]:
        place(x, stab(sr, rng, 62, 0.6), at, sr, amp)
    place(x, stroke(sr, rng, 0.5, 45.0, 85.0, LOW_CHITIN), 0.42, sr, 0.7)
    place(x, hiss(sr, rng, 0.8, 900, 4500, 0.35), 0.4, sr, 0.3)
    ir = outdoor_ir(0.4, sr, rng, [(250, 2500, 0.1, 1.0)])
    return finish(with_tail(x, sr, ir, -13.0, 1.6), sr, -5.0, 0.5, 80.0)


@sound("cascarudo_overturn", LO)
def cascarudo_overturn(sr, rng):
    """A cascarudo's last shot has hit it: it goes over onto its back, the rim of its shell grinding on the cobbles and
    its legs scrabbling, lands with a hollow boom, rasps once, weakly, and its legs twitch less and less."""
    x = buf(3.2, sr)
    land = 1.0
    place(x, norm(stick_slip(0.8, sr, rng, 30.0, 60.0, GRIND, 0.35) * hump(0.8, sr, 0.75, 0.8)), 0.1, sr, 0.45)
    for _ in range(7):
        place(x, joint(sr, rng, 1500, 3200), rng.uniform(0.1, 0.85), sr, rng.uniform(0.15, 0.35))
    place(x, norm(modal(0.9, sr, [(f * 0.8, tau * 1.6, a) for f, tau, a in SHELL])), land, sr, 1.0)
    place(x, norm(thump(0.3, sr, rng, 52, 0.07, 1.0, 0.5)), land, sr, 0.6)
    place(x, norm(lp(grains(0.25, sr, rng, 1600.0 * env_ad(0.25, sr, 0.005, 0.07), 400, 2400), 2800.0, sr)), land, sr, 0.6)
    place(x, stroke(sr, rng, 0.35, 40.0, 22.0, LOW_CHITIN), land + 0.45, sr, 0.3)
    at, gap = land + 0.3, 0.12
    while at < 3.0:
        place(x, joint(sr, rng, 1300, 2800), at, sr, 0.3 * np.exp(-(at - land) / 0.8))
        at += gap + rng.uniform(0.0, 0.08)
        gap += 0.1
    ir = outdoor_ir(0.6, sr, rng, [(200, 2000, 0.15, 1.0)])
    return finish(with_tail(x, sr, ir, -12.0, 3.4), sr, -5.0, 0.5, 200.0)


# ================================================================ main

def render(name):
    fn, sr, loop = SOUNDS[name]
    x = fn(sr, rng_for(name))
    if name not in PEAK_ONLY:
        x = to_loudness(x, sr, LOUDNESS, loop)
    return x, sr, loop


def main():
    wanted = sys.argv[1:]
    os.makedirs(OUT, exist_ok=True)
    total = 0
    print("%-24s %6s %7s %7s %7s  %s" % ("file", "rate", "sec", "peak", "rms", "loop"))
    for name in SOUNDS:
        if wanted and not any(part in name for part in wanted):
            continue
        if name in NOT_SHIPPED and name not in wanted:
            continue
        x, sr, loop = render(name)
        assert np.max(np.abs(x)) <= db(PEAK_LIMIT) + 1e-9, (name, 20 * np.log10(np.max(np.abs(x))))
        path = os.path.join(OUT, name + ".wav")
        write_wav(path, x, sr, loop)
        total += os.path.getsize(path)
        print("%-24s %6d %7.2f %7.1f %7.1f  %s" % (name + ".wav", sr, len(x) / sr, 20 * np.log10(np.max(np.abs(x))),
                                                  10 * np.log10(np.mean(x * x)), "loop" if loop else ""))
    print("%.2f MB written" % (total / 1e6))


if __name__ == "__main__":
    main()
