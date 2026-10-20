#!/usr/bin/env python3
"""Offline mix-down of a mission, for looking at instead of listening to.

    godot --headless --path godot --script ../tools/audio_trace.gd -- trace.json alarm_recovery
    python3 tools/audio_mixdown.py trace.json out_prefix [from_seconds to_seconds]

Reads the trace written by tools/audio_trace.gd (every sound audio.gd started, with its level, pan and pitch,
and the loop levels ten times a second), renders it exactly as the game would mix it (same gains, same pan law,
linear resampling; the Master limiter is NOT modelled, so overs show up as overs) and writes
<out_prefix>.wav (stereo, 44.1 kHz) and <out_prefix>.png: the event timeline, level (A-weighted, short-term)
with the peak, and a spectrogram. Prints the peak, the number of samples over full scale and the loudness."""
import json
import os
import sys

import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from audio_synth import LOOP_PAD, a_weight, read_wav, to_pcm

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
AUDIO = os.path.join(ROOT, "godot", "assets", "audio")
RATE = 44100
PAN_WIDTH = 0.35   # audio.gd PAN_WIDTH
CACHE = {}


def stream(name):
    if name not in CACHE:
        CACHE[name] = read_wav(os.path.join(AUDIO, name + ".wav"))
    return CACHE[name]


def resampled(x, sr, pitch):
    step = sr * pitch / RATE
    at = np.arange(int(len(x) / step)) * step
    return np.interp(at, np.arange(len(x)), x)


def render(trace, start, end):
    n = int((end - start) * RATE)
    left = np.zeros(n)
    right = np.zeros(n)
    shots = [row for row in trace if "file" in row]
    for row in shots:
        x, sr = stream(row["file"])
        y = resampled(x, sr, row["pitch"]) * 10.0 ** (row["db"] / 20.0)
        at = int(round((row["t"] - start) * RATE))
        if at >= n or at + len(y) <= 0:
            continue
        if at < 0:
            y = y[-at:]
            at = 0
        y = y[:n - at]
        if row.get("world"):
            l, r = 0.5 - row["pan"] * PAN_WIDTH, 0.5 + row["pan"] * PAN_WIDTH
            scale = 1.0 / max(l, r)   # the louder side at full level (audio.gd)
            left[at:at + len(y)] += y * l * scale
            right[at:at + len(y)] += y * r * scale
        else:
            left[at:at + len(y)] += y
            right[at:at + len(y)] += y
    # Loops: level and pitch are piecewise linear between the trace rows.
    rows = [row for row in trace if "loops" in row]
    times = np.array([row["t"] for row in rows])
    t = start + np.arange(n) / RATE
    for name in sorted({key for row in rows for key in row["loops"]}):
        gain = np.array([10.0 ** (row["loops"][name][0] / 20.0) if name in row["loops"] else 0.0 for row in rows])
        pitch = np.array([row["loops"][name][1] if name in row["loops"] else 1.0 for row in rows])
        x, sr = stream(name)
        body = x[LOOP_PAD:-LOOP_PAD]
        position = np.cumsum(np.interp(t, times, pitch) * sr / RATE) % len(body)
        index = position.astype(np.int64)
        frac = position - index
        y = (body[index] * (1.0 - frac) + body[(index + 1) % len(body)] * frac) * np.interp(t, times, gain)
        left += y
        right += y
    return left, right


def short_level(x, window=0.4, hop=0.1):
    win = int(window * RATE)
    step = int(hop * RATE)
    weighted = a_weight(x, RATE)
    frames = range(0, max(1, len(x) - win), step)
    level = np.array([10 * np.log10(max(np.mean(weighted[i:i + win] ** 2), 1e-10)) for i in frames])
    peak = np.array([20 * np.log10(max(np.max(np.abs(x[i:i + win])), 1e-5)) for i in frames])
    return np.array([i / RATE for i in frames]), level, peak


def main():
    data = json.load(open(sys.argv[1]))
    prefix = sys.argv[2]
    start = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    end = float(sys.argv[4]) if len(sys.argv) > 4 else float(data["seconds"])
    left, right = render(data["trace"], start, end)
    mono = 0.5 * (left + right)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    overs = int(np.sum(np.abs(left) > 1.0) + np.sum(np.abs(right) > 1.0))
    weighted = a_weight(mono, RATE)
    print("%s %.0f-%.0f s: peak %.1f dBFS, %d samples over full scale, A-weighted level %.1f dB, mid/side %.1f dB" % (
        data["plan"], start, end, 20 * np.log10(peak), overs, 10 * np.log10(np.mean(weighted ** 2)),
        10 * np.log10(np.mean(mono ** 2) / max(np.mean((0.5 * (left - right)) ** 2), 1e-12))))
    pcm = to_pcm(np.clip(np.stack([left, right], axis=1), -1.0, 1.0)).tobytes()
    import struct
    with open(prefix + ".wav", "wb") as handle:
        handle.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE" + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 2, RATE, RATE * 4, 4, 16) + b"data" + struct.pack("<I", len(pcm)) + pcm)

    span = end - start
    fig, axes = plt.subplots(3, 1, figsize=(16, 9), dpi=80, sharex=True, gridspec_kw={"height_ratios": [1.3, 1.2, 3.0], "hspace": 0.08})
    lanes = ["ambience", "movement", "action", "gun", "alert", "result / UI"]
    def lane(name):
        for key, index in (("amb_", 0), ("foot_", 1), ("act_", 2), ("gun_", 3), ("alert_", 4), ("alarm_", 4)):
            if name.startswith(key):
                return index
        return 5
    ax = axes[0]
    for row in data["trace"]:
        if "file" in row and start <= row["t"] <= end:
            ax.plot([row["t"]], [lane(row["file"])], "|", ms=9, color=plt.cm.viridis(np.clip((row["db"] + 40.0) / 40.0, 0, 1)))
    labelled = 0
    for event in data["events"]:
        if start <= event["t"] <= end and event["type"] != "checkpoint":
            ax.axvline(event["t"], color="#c33", lw=0.5, alpha=0.6)
            if span <= 90:
                ax.text(event["t"], 5.6 + 0.55 * (labelled % 3), event["type"], fontsize=7, rotation=0, color="#a22", va="bottom")
                labelled += 1
    ax.set_yticks(range(len(lanes)))
    ax.set_yticklabels(lanes, fontsize=8)
    ax.set_ylim(-0.6, 7.6 if span <= 90 else 5.6)
    ax.set_title("%s  %.0f-%.0f s   peak %.1f dBFS, %d overs (limiter not modelled)" % (data["plan"], start, end, 20 * np.log10(peak), overs), fontsize=10)
    tm, level, pk = short_level(mono)
    ax = axes[1]
    ax.plot(start + tm, level, color="#246", lw=1.0, label="A-weighted level, 0.4 s")
    ax.plot(start + tm, pk, color="#c80", lw=0.6, label="peak")
    ax.set_ylim(-60, 3)
    ax.axhline(0, color="k", lw=0.4)
    ax.legend(fontsize=7, loc="lower right", ncol=2)
    ax.grid(alpha=0.3)
    ax.set_ylabel("dBFS", fontsize=8)
    ax = axes[2]
    nper = 2048
    f, ts, s = signal.spectrogram(mono, RATE, nperseg=nper, noverlap=nper // 2 if span > 40 else nper * 7 // 8, scaling="spectrum", mode="magnitude")
    ax.pcolormesh(start + ts, f[2:], 20 * np.log10(np.maximum(s[2:] * 2.0, 1e-6)), vmin=-95, vmax=-20, cmap="magma", shading="auto")
    ax.set_yscale("log")
    ax.set_ylim(60, 16000)
    ax.axhline(300, color="w", lw=0.5, ls=":")
    ax.set_yticks([100, 300, 1000, 3000, 10000])
    ax.set_yticklabels(["100", "300", "1k", "3k", "10k"])
    ax.set_xlabel("seconds of play (wall clock of the run)", fontsize=8)
    fig.savefig(prefix + ".png", bbox_inches="tight")
    plt.close(fig)
    print("wrote %s.wav and %s.png" % (prefix, prefix))


if __name__ == "__main__":
    main()
