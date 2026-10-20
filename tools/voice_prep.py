#!/usr/bin/env python3
"""Turns raw voice takes into game-ready operative lines.

    python3 tools/voice_prep.py <folder of takes>              # writes godot/assets/audio/voice/en/
    python3 tools/voice_prep.py <folder of takes> --lang=es    # Spanish lines: godot/assets/audio/voice/es/
    python3 tools/voice_prep.py <folder of takes> --radio      # with a field-radio band limit

Name each take <operative>_<kind>_<n>.<anything ffmpeg reads>, for example hornero_select_1.m4a:
    operative  hornero | lechuza | benteveo | bigua | asset (Riachuelo's passenger)
    kind       select | move | attack | work | done | refuse | spotted | hurt | freed
    n          1 to 8, counted up without gaps (the game stops at the first missing number)
docs/VOICE_LINES.md has the lines to record. Only record your own voices saying your own lines.

Each take is trimmed of silence at both ends, cleaned of rumble, evened out, brought to the loudness of the
rest of the sound set and written as 16-bit mono 22.05 kHz WAV that starts and ends at zero. A voice listed in
PITCH is first moved by its semitones (ffmpeg's rubberband filter).
Open the project in Godot afterwards so the new files are imported. Needs ffmpeg on the PATH."""
import os
import re
import shutil
import subprocess
import sys

OPERATIVES = ("asset", "hornero", "lechuza", "benteveo", "bigua")
KINDS = ("select", "move", "attack", "work", "done", "refuse", "spotted", "hurt", "freed")
MAX_TAKES = 8
MAX_SECONDS = 2.5
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "godot", "assets", "audio", "voice")
NAME = re.compile(r"^(%s)_(%s)_([1-%d])\.[A-Za-z0-9]+$" % ("|".join(OPERATIVES), "|".join(KINDS), MAX_TAKES))

TRIM = ("silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.02,areverse,"
        "silenceremove=start_periods=1:start_threshold=-42dB:start_silence=0.06,areverse")
CLEAN = "highpass=f=110,lowpass=f=9500,acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=2"
RADIO = "highpass=f=380,lowpass=f=3400,acompressor=threshold=-26dB:ratio=6:attack=2:release=80:makeup=4"
# The synthesised set sits at about -24 dB A-weighted; speech at -20 LUFS reads as the same level beside it.
LEVEL = "loudnorm=I=-20:TP=-2.5:LRA=7"
EDGES = "afade=t=in:d=0.008,areverse,afade=t=in:d=0.03,areverse"
# A voice moved down (or up) some semitones before the rest, its formants kept so it sounds deeper rather than
# bigger: (operative, language): semitones. The long window and smooth transients keep every line heard right.
# Benteveo (the newspaper boy, tools/voice_riachuelo.py): his designed voice speaks his exclamations at about 230 Hz,
# high enough to risk sounding like a boy whose voice has not broken; down two, about 205 Hz, he should pass for
# seventeen, still the highest of the four and well clear of Lechuza (about 165).
PITCH = {("benteveo", "en"): -2.0, ("benteveo", "es"): -2.0}
SHIFT = "rubberband=pitch=%.6f:formant=preserved:pitchq=quality:window=long:transients=smooth"


def seconds(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    radio = "--radio" in sys.argv
    lang = "en"
    for a in sys.argv[1:]:
        if a.startswith("--lang="): lang = a.split("=", 1)[1].strip().lower()
    out = os.path.join(OUT, lang)
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__)
        return 2
    if shutil.which("ffmpeg") is None:
        print("ffmpeg was not found on the PATH.")
        return 2
    takes = sorted(f for f in os.listdir(args[0]) if not f.startswith("."))
    good = [f for f in takes if NAME.match(f)]
    for f in takes:
        if f not in good:
            print("skipped (name is not <operative>_<kind>_<n>): " + f)
    if not good:
        print("No takes to process.")
        return 1
    os.makedirs(out, exist_ok=True)
    chain = ",".join([TRIM, RADIO if radio else CLEAN, LEVEL, EDGES])
    written = {}
    for f in good:
        operative, kind, n = NAME.match(f).groups()
        target = os.path.join(out, "%s_%s_%s.wav" % (operative, kind, n))
        shift = PITCH.get((operative, lang), 0.0)
        line = chain if shift == 0.0 else (SHIFT % (2.0 ** (shift / 12.0))) + "," + chain
        done = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(args[0], f), "-af", line,
                               "-ac", "1", "-ar", "22050", "-c:a", "pcm_s16le", target], capture_output=True, text=True)
        if done.returncode != 0 or not os.path.exists(target):
            print("failed: %s  %s" % (f, done.stderr.strip().splitlines()[-1] if done.stderr.strip() else ""))
            continue
        length = seconds(target)
        note = ""
        if length < 0.15:
            note = "  (almost nothing left after trimming: was the take silent?)"
        elif length > MAX_SECONDS:
            note = "  (long for an acknowledgement: aim for under %.1f s)" % MAX_SECONDS
        print("%-22s %.2f s%s" % (os.path.basename(target), length, note))
        written.setdefault((operative, kind), []).append(int(n))
    for (operative, kind), numbers in sorted(written.items()):
        have = sorted(int(m.group(3)) for m in (NAME.match(x) for x in os.listdir(out)) if m and m.group(1) == operative and m.group(2) == kind)
        if have != list(range(1, len(have) + 1)):
            print("gap in %s_%s: have %s, the game only plays up to the first missing number" % (operative, kind, have))
    print("Written to " + out + ". Open the project in Godot once so the files are imported.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
