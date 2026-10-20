#!/usr/bin/env python3
"""Looks at the generated sound set, since nobody can listen to it here.

    python3 tools/audio_qa.py [out_dir] [name filter...]

Prints one line per file (rate, length, peak, RMS, DC, A-weighted level of the loudest 50 ms and of the whole
file, how much level a phone speaker loses (4th-order high-pass at 300 Hz), spectral centroid, first/last
sample, and for loops the mismatch across the seam), then the mix table (how loud audio.gd plays each cue),
and writes contact sheets of waveform + log-frequency spectrogram (dB re full scale) to out_dir (default: ../qa)."""
import glob
import os
import re
import sys

import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from audio_synth import LOOP_PAD, a_weight, level_db as level, loudest_db as short_max, read_wav

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
AUDIO = os.path.join(ROOT, "godot", "assets", "audio")
LOOPS = ("amb_sea", "amb_wind", "amb_generator", "alarm_siren", "tension_loop", "amb_river", "amb_transformer", "amb_harbour", "amb_hum")


def measure(path):
    x, sr = read_wav(path)
    name = os.path.basename(path)[:-4]
    loop = name in LOOPS
    body = x[LOOP_PAD:-LOOP_PAD] if loop else x
    weighted = a_weight(body, sr)
    phone = signal.sosfilt(signal.butter(4, 300.0, "highpass", fs=sr, output="sos"), body)
    spectrum = np.abs(np.fft.rfft(body)) ** 2
    freqs = np.fft.rfftfreq(len(body), 1.0 / sr)
    row = {
        "name": name, "sr": sr, "sec": len(body) / sr, "peak": 20 * np.log10(np.max(np.abs(x))), "rms": level(body),
        "dc": float(np.mean(body)), "a_max": short_max(weighted, sr), "a_all": level(weighted),
        "phone": level(phone) - level(body), "centroid": float(np.sum(freqs * spectrum) / np.sum(spectrum)),
        "first": x[0], "last": x[-1], "loop": loop, "bytes": os.path.getsize(path), "seam": "",
    }
    if loop:
        n = len(body)
        pre = np.max(np.abs(x[:LOOP_PAD] - x[n:n + LOOP_PAD]))
        post = np.max(np.abs(x[LOOP_PAD + n:] - x[LOOP_PAD:2 * LOOP_PAD]))
        step = abs(body[0] - body[-1])
        typical = np.percentile(np.abs(np.diff(body)), 99)
        row["seam"] = "pad %.0e/%.0e, step %.4f (p99 step %.4f)" % (pre, post, step, typical)
    return row, x, sr


def sheet(items, path):
    cols = 4
    rows = (len(items) + cols - 1) // cols
    fig = plt.figure(figsize=(cols * 4.6, rows * 3.7), dpi=80)
    for index, (row, x, sr) in enumerate(items):
        base = fig.add_gridspec(rows * 4, cols, hspace=0.9, wspace=0.22, left=0.04, right=0.99, top=0.97, bottom=0.04)
        r, c = divmod(index, cols)
        wave = fig.add_subplot(base[r * 4, c])
        t = np.arange(len(x)) / sr
        wave.plot(t, x, lw=0.4, color="#234")
        wave.set_ylim(-1, 1)
        wave.set_xlim(0, t[-1])
        wave.set_xticks([])
        wave.set_yticks([-1, 0, 1])
        wave.tick_params(labelsize=6)
        wave.set_title("%s  %.2fs  pk %.1f  A50 %.1f  phone %+.1f" % (row["name"], row["sec"], row["peak"], row["a_max"], row["phone"]), fontsize=8)
        spec = fig.add_subplot(base[r * 4 + 1:r * 4 + 4, c])
        nper = 1024 if sr > 30000 else 512
        if len(x) > sr * 3:
            nper *= 2
        f, tm, s = signal.spectrogram(x, sr, nperseg=min(nper, len(x)), noverlap=min(nper, len(x)) * 15 // 16, scaling="spectrum", mode="magnitude")
        s_db = 20 * np.log10(np.maximum(s * 2.0, 1e-6))
        spec.pcolormesh(tm, f[1:], s_db[1:], vmin=-90, vmax=-12, cmap="magma", shading="auto")
        spec.set_yscale("log")
        spec.set_ylim(60, sr / 2)
        spec.axhline(300, color="w", lw=0.4, ls=":")
        spec.set_yticks([100, 300, 1000, 3000, 10000])
        spec.set_yticklabels(["100", "300", "1k", "3k", "10k"])
        spec.tick_params(labelsize=6)
    fig.savefig(path)
    plt.close(fig)


def mix_table(rows):
    """Reads the cue table and the category levels out of audio.gd and prints how loud each cue is played:
    file loudness + MASTER_DB + category + cue gain (on screen, not paused), and the peak that gives."""
    text = open(os.path.join(ROOT, "godot", "scripts", "three_d", "audio.gd")).read()
    const = {name: float(value) for name, value in re.findall(r"^const (\w+_DB): float = (-?[\d.]+)", text, re.M)}
    by_name = {row["name"]: row for row, _, _ in rows}
    flat_ui = ("objective", "checkpoint", "page", "win", "lose", "ui_tap", "ui_arm", "ui_deny", "ui_confirm")
    print("\nmix (dB): MASTER %+.0f, SFX %+.0f, AMBIENCE %+.0f, ALARM %+.0f, UI %+.0f" % (
        const["MASTER_DB"], const["SFX_DB"], const["AMBIENCE_DB"], const["ALARM_DB"], const["UI_DB"]))
    print("%-16s %-52s %5s %7s %7s" % ("cue", "files", "gain", "played", "peak"))
    for cue, files, gain, carry in re.findall(r'&"(\w+)": \[\[([^\]]+)\], (-?[\d.]+), (\w+),', text):
        names = re.findall(r'"(\w+)"', files)
        category = const["UI_DB"] if cue in flat_ui else const["ALARM_DB"] if cue == "bell" else const["AMBIENCE_DB"] if cue in ("gull", "creak") else const["SFX_DB"]
        total = const["MASTER_DB"] + category + float(gain)
        known = [by_name[n] for n in names if n in by_name]
        if not known:
            continue
        print("%-16s %-52s %+5.0f %7.1f %7.1f" % (cue, ", ".join(names), float(gain), np.mean([r["a_max"] for r in known]) + total,
                                                 max(r["peak"] for r in known) + total))
    for loop, key, extra in (("amb_sea", "AMBIENCE_DB", 0.0), ("amb_wind", "AMBIENCE_DB", const["WIND_DB"]), ("amb_generator", "AMBIENCE_DB", const["HUM_DB"]),
                             ("alarm_siren", "ALARM_DB", const["SIREN_DB"]), ("tension_loop", "SFX_DB", const["TENSION_DB"])):
        if loop in by_name:
            total = const["MASTER_DB"] + const[key] + extra
            print("%-16s %-52s %+5.0f %7.1f %7.1f" % ("(loop)", loop + " at full level", extra, by_name[loop]["a_all"] + total, by_name[loop]["peak"] + total))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "qa")
    wanted = sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    rows = []
    for path in sorted(glob.glob(os.path.join(AUDIO, "*.wav"))):
        if wanted and not any(part in os.path.basename(path) for part in wanted):
            continue
        rows.append(measure(path))
    print("%-22s %5s %5s %6s %6s %8s %6s %6s %6s %6s %8s %8s  %s" % ("name", "rate", "sec", "peak", "rms", "dc", "A50ms", "A-all", "phone", "centr", "first", "last", "loop seam"))
    for row, _, _ in rows:
        print("%-22s %5d %5.2f %6.1f %6.1f %8.5f %6.1f %6.1f %+6.1f %6.0f %8.5f %8.5f  %s" % (
            row["name"], row["sr"], row["sec"], row["peak"], row["rms"], row["dc"], row["a_max"], row["a_all"], row["phone"],
            row["centroid"], row["first"], row["last"], row["seam"]))
    print("%d files, %.2f MB, %.1f s" % (len(rows), sum(r["bytes"] for r, _, _ in rows) / 1e6, sum(r["sec"] for r, _, _ in rows)))
    if not wanted:
        mix_table(rows)
    for start in range(0, len(rows), 8):
        sheet(rows[start:start + 8], os.path.join(out, "sheet_%02d.png" % (start // 8 + 1)))
    print("sheets in", out)


if __name__ == "__main__":
    main()
