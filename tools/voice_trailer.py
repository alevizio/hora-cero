#!/usr/bin/env python3
"""The narrator of the Hora Cero trailer (tools/trailer/hc2_*): an older porteño telling the night of the snow, in
Rioplatense Spanish. Nothing recorded, nobody's voice copied: the voice is designed from a written description
(Qwen3-TTS VoiceDesign, Apache-2.0) that names no one, and every line of the narration is cloned from that one
design take with Qwen3-TTS Base, as the game's own voices are made (tools/voice_riachuelo.py).

    python3 tools/voice_trailer.py design <work> <VoiceDesign model dir> [variants=ABC n=4 seed=1958]
    python3 tools/voice_trailer.py audition <work>                      # words, ll/y hiss, pitch, pace
    python3 tools/voice_trailer.py clone <work> <Base model dir> [takes=6 batch=6]
    python3 tools/voice_trailer.py accent <work> <Base model dir>       # "calle", "llegaron ellos" in the cloned voice
    python3 tools/voice_trailer.py judge <work>                         # words, voice match, ll/y, pace
    python3 tools/voice_trailer.py pick <work>                          # best take a line
    python3 tools/voice_trailer.py clean <work> <out dir>               # trimmed, de-clicked, breaths down
    python3 tools/voice_trailer.py provenance <work>                    # tools/voices/trailer/

`design` writes candidates into <work>/design/; CHOSEN below names the design take the lines are cloned from, after
`audition`. `clone` makes `takes` takes of each line (seeded, in batches); `judge` scores them: what Whisper hears
against the text, the voice against the design take (ECAPA), the pace, and in "llegaron" the hiss of its ll (the
porteño [ʃ]/[ʒ]: energy at 3-8 kHz against an /s/ of the same take; see voice_riachuelo.py); for the "y" of the
narration (always the conjunction, a vowel [i]) that it did not turn into a hiss. `pick` keeps the take heard right
(a statement, not heard as a question), nearest the design voice, not rushed. `clean` makes the chosen takes ready for
the mix: 48 kHz mono, the silence trimmed, clicks (sudden one-sample jumps) smoothed over, the breaths between phrases
brought down 18 dB, the pauses inside a line let breathe a little longer and the whole slowed 5 % (the pitch kept): the
storyteller's measure.
Provenance goes to tools/voices/trailer/ (narrator.csv: the design; lines.csv: every take of every line and the
chosen one).

Needs the Python of the game's voices (qwen-tts, torch, soundfile, librosa, faster-whisper, speechbrain).
"""
import csv
import difflib
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voice_riachuelo as vr  # noqa: E402  (the shared helpers: model loading, Whisper, the hiss measure)

PROVENANCE = os.path.join(HERE, "voices", "trailer")

# The design, in Spanish as the text is. A generic voice: an age, a timbre, a pace, a manner, an accent, a period
# (the radio storytelling of the 1950s): no actor, announcer or any real person is named or meant.
OPENING = "Español rioplatense de Buenos Aires, Argentina, con el acento porteño. "
PERSONA = ("Narrador: un hombre porteño de unos sesenta años. Voz masculina grave, profunda y cálida, apenas ronca y "
           "gastada por los años. Habla lento y medido, con pausas entre las frases, como un narrador de los radioteatros "
           "de los años cincuenta que cuenta una historia de noche: serio, contenido, sin dramatizar ni exagerar, en voz "
           "baja y con autoridad tranquila. ")
PERSONA_SHORT = ("Un hombre porteño de sesenta años narra una historia: voz grave, cálida y un poco ronca, lenta, "
                 "medida y seria, contenida, sin dramatismo, como el narrador de un radioteatro antiguo. ")
PERSONA_DEEP = ("Narrador de unos sesenta años, porteño, de voz de bajo profunda y cálida, con un leve carraspeo. Lee "
                "despacio, con calma y gravedad, dejando respirar cada frase; nunca grita ni sobreactúa. ")
ACCENT = ("Pronuncia la 'll' y la 'y' a la porteña, como 'sh' o 'zh': 'calle' suena 'cashe', 'llegaron' suena "
          "'shegaron', 'yo' suena 'sho'. La 'c' y la 'z' suenan como 's'. Entonación porteña que cae al final de cada frase.")
ACCENT_SHORT = "La 'll' y la 'y' suenan 'sh', a la porteña ('cashe', 'shegaron'); la entonación cae al final de cada frase."
INSTRUCTS = {"A": OPENING + PERSONA + ACCENT, "B": OPENING + PERSONA_SHORT + ACCENT_SHORT, "C": OPENING + PERSONA_DEEP + ACCENT}

# What every design candidate reads: a narration of its own (not the trailer's), full of ll/y, with /s/ to compare.
DESIGN_TEXT = ("Yo me acuerdo bien de aquella noche. La calle estaba callada, y allá en la plaza ya brillaban los faroles. "
               "Llegaron de todos lados a mirar el cielo.")
ZH_WORDS = ["yo", "calle", "callada", "alla", "ya", "llegaron"]
S_WORDS = ["cielo", "plaza", "lados"]

# The narration, as written for the trailer (rioplatense, voseo): key, Spanish, the English subtitle.
LINES = [
    ("01", "Buenos Aires. Invierno de mil novecientos cincuenta y ocho.", "Buenos Aires. Winter, 1958."),
    ("02", "Esa noche nevó. Por primera vez en cuarenta años, nevó en la ciudad.",
     "That night it snowed. For the first time in forty years, it snowed in the city."),
    ("03", "La gente salió a verla. Y la nieve los fue tocando, uno por uno.",
     "People came out to see it. And the snow touched them, one by one."),
    ("04", "Quien la tocaba, caía.", "Whoever it touched, fell."),
    ("05", "Quedaban unos pocos bajo techo. Un motorman. Un liniero. Un canillita. Un botero.",
     "A few were left under cover. A motorman. A lineman. A paperboy. A boatman."),
    ("06", "Y una sola idea: llevar a todos a cubierto.", "And one thought: get everyone under cover."),
    ("07", "Afuera, en plena nevada, un hombre sellado en su traje. El único que podía ir a buscarlos.",
     "Out there, in the snowfall, a man sealed in his suit. The only one who could go and get them."),
    ("08", "Y entonces, desde las avenidas, llegaron ellos.", "And then, from the avenues, they came."),
    ("09", "Hora Cero.", "Hora Cero."),
]
# Line 5 is four short beats after its first sentence: it is also cloned in parts, so the edit can space them.
PARTS = [
    ("05a", "Quedaban unos pocos bajo techo."),
    ("05b", "Un motorman."),
    ("05c", "Un liniero."),
    ("05d", "Un canillita."),
    ("05e", "Un botero."),
]
# The ll/y words of the narration the judge listens to (the hissing consonant), and the "y"s that must stay a vowel.
LL_WORDS = {"06": ["llevar"], "08": ["llegaron", "ellos"]}
Y_VOWEL = {"03": "y", "06": "y", "08": "y"}

NUMBERS = {"1958": "mil novecientos cincuenta y ocho", "40": "cuarenta"}

# The design take the lines are cloned from (after `audition`), and the runners-up.
CHOSEN = ("A2", ["C3", "A4"])
# A2 (the first wording): the deepest of the warm ones (84 Hz), the darkest timbre (spectral centroid 1.2 kHz, the
# most energy under 1 kHz), restrained (5 semitones of melody), a slow pace (4.3 syllables a second), every word
# heard right, and the ll of "llegaron" hissing as an /s/ does. C3: deeper (80 Hz) and huskier, but quicker (4.9) and
# its "llegaron" hisses less. A4: the huskiest and the most sing-song (12 semitones), "yo" and "llegaron" both hissing.


# The accent check of the narrator's own voice (cloned, as the lines are) on the words that matter most: "calle" and
# "llegaron ellos" (the porteño [ʃ]/[ʒ] for ll), with /s/ words to compare against.
ACCENT_TEXT = "Yo lo vi desde la calle. Y entonces, de pronto, llegaron ellos."
ACCENT_ZH = ["yo", "calle", "llegaron", "ellos"]
ACCENT_S = ["desde", "entonces"]


def accent(work, model_dir, takes=4):
    """Clones ACCENT_TEXT `takes` times from the chosen design take and measures the hiss of each ll/y word (the same
    measure as `audition`): <work>/accent/, accent.json."""
    import soundfile as sf
    import torch
    vr._quiet_warnings()
    folder = os.path.join(work, "accent")
    os.makedirs(folder, exist_ok=True)
    if len(glob.glob(os.path.join(folder, "*.wav"))) < takes:
        model = vr._load(model_dir)
        prompt = model.create_voice_clone_prompt(ref_audio=os.path.join(work, "design", CHOSEN[0] + ".wav"), ref_text=DESIGN_TEXT)
        torch.manual_seed(1958)
        wavs, rate = model.generate_voice_clone(text=[ACCENT_TEXT] * takes, language=["Spanish"] * takes,
                                                voice_clone_prompt=[prompt[0]] * takes, max_new_tokens=200)
        for k, wav in enumerate(wavs):
            sf.write(os.path.join(folder, "accent_%d.wav" % k), wav, rate)
        del model
    asr = vr._asr("small")
    out = {}
    for wav in sorted(glob.glob(os.path.join(folder, "*.wav"))):
        r = _analyse(wav, ACCENT_TEXT, asr, ACCENT_ZH, ACCENT_S)
        out[os.path.basename(wav)] = {"heard": r["heard"], "match": r["match"], "seed": 1958,
                                      "hiss_vs_s": {z["word"]: z.get("rel") for z in r["zh"] if z["found"]}}
        print(os.path.basename(wav), out[os.path.basename(wav)]["hiss_vs_s"], "|", r["heard"], flush=True)
    json.dump(out, open(os.path.join(work, "accent.json"), "w"), ensure_ascii=False, indent=1)


def _all_lines():
    return [(k, es) for k, es, _ in LINES] + PARTS


def design(work, model_dir, per_variant=4, variants="ABC", seed=1958, batch=6):
    import soundfile as sf
    import torch
    model = vr._load(model_dir)
    folder = os.path.join(work, "design")
    os.makedirs(folder, exist_ok=True)
    meta_path = os.path.join(folder, "meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    todo = []
    for v in variants:
        for k in range(per_variant):
            name = "%s%d" % (v, k + 1)
            if not os.path.exists(os.path.join(folder, name + ".wav")):
                todo.append((name, INSTRUCTS[v]))
    for i in range(0, len(todo), batch):
        group = todo[i:i + batch]
        s = seed + i
        torch.manual_seed(s)
        # 12 codec frames a second: a cap of 28 s for a text of about 12
        wavs, rate = model.generate_voice_design(text=[DESIGN_TEXT] * len(group), language="Spanish",
                                                 instruct=[p for _, p in group], max_new_tokens=340)
        for (name, prompt), wav in zip(group, wavs):
            sf.write(os.path.join(folder, name + ".wav"), wav, rate)
            meta[name] = {"instruct": prompt, "text": DESIGN_TEXT, "seed": s, "batch": [n for n, _ in group]}
            print(name, "%.2f s" % (len(wav) / rate), flush=True)
        json.dump(meta, open(meta_path, "w"), ensure_ascii=False, indent=1)


def _syllables(text):
    """Spanish syllables, roughly: vowel groups (a diphthong counted once)."""
    import re
    return len(re.findall(r"[aeiou]+", " ".join(vr.words(text))))


def _analyse(path, text, asr, zh_words, s_words):
    """Words heard, pace, pitch, and the hiss of each ll/y word (vr._hiss), as voice_riachuelo.accent_report does."""
    import librosa
    import numpy as np
    y, rate = librosa.load(path, sr=24000)
    y16 = librosa.resample(y, orig_sr=24000, target_sr=16000)
    pad = np.zeros(8000, dtype=np.float32)
    segments, info = asr.transcribe(np.concatenate([pad, y16, pad]), language="es", beam_size=5, word_timestamps=True)
    segments = list(segments)
    heard = " ".join(s.text for s in segments).strip()
    # Whisper writes numbers in figures: read back as the narration says them
    for fig, words_ in NUMBERS.items():
        heard = heard.replace(fig, words_)
    spans = [(w, a - 0.5, b - 0.5) for (w, a, b) in vr._word_spans(segments)]
    match = difflib.SequenceMatcher(None, " ".join(vr.words(text)), " ".join(vr.words(heard))).ratio()
    used = set()
    s_ref = []
    for w in s_words:
        at = vr._where(w, spans, used)
        if at:
            s_ref.append(vr._hiss(y, rate, at[0], at[1])[0])
    s_level = max(s_ref) if s_ref else None
    zh = []
    for w in zh_words:
        at = vr._where(w, spans, used)
        if not at:
            zh.append({"word": w, "found": False})
            continue
        a, b = at
        lo, hi = (a, a + 0.6 * (b - a)) if w[0] in "ly" else (a + 0.25 * (b - a), a + 0.8 * (b - a))
        hf, low = vr._hiss(y, rate, lo, hi)
        zh.append({"word": w, "found": True, "hiss": round(hf, 3), "rel": round(hf / s_level, 2) if s_level else None,
                   "low": round(low, 3)})
    f0, voiced, _ = librosa.pyin(y16, fmin=55, fmax=320, sr=16000)
    f0v = f0[voiced] if np.any(voiced) else np.array([np.nan])
    semis = 12 * np.log2(f0v / np.nanmedian(f0v))
    # speech time: from the first word's start to the last word's end; the pace in syllables a second of it
    speech = (spans[-1][2] - spans[0][1]) if spans else len(y) / rate
    return {"heard": heard, "lang": info.language, "lang_p": round(info.language_probability, 3), "match": round(match, 3),
            "zh": zh, "f0": round(float(np.nanmedian(f0v)), 1) if np.any(voiced) else None,
            "range_st": round(float(np.nanpercentile(semis, 90) - np.nanpercentile(semis, 10)), 1) if np.any(voiced) else None,
            "dur": round(len(y) / rate, 2), "speech": round(speech, 2),
            "pace": round(_syllables(text) / max(0.3, speech), 2), "spans": [(w, round(a, 2), round(b, 2)) for (w, a, b) in spans]}


def audition(work):
    vr._quiet_warnings()
    asr = vr._asr("small")
    path = os.path.join(work, "design_scores.json")
    scores = json.load(open(path)) if os.path.exists(path) else {}
    for wav in sorted(glob.glob(os.path.join(work, "design", "*.wav"))):
        name = os.path.basename(wav)[:-4]
        if name in scores:
            continue
        r = _analyse(wav, DESIGN_TEXT, asr, ZH_WORDS, S_WORDS)
        hissing = [z for z in r["zh"] if z["found"] and z["rel"] is not None and z["rel"] >= 0.3]
        r["hiss_share"] = round(len(hissing) / max(1, len(r["zh"])), 2)
        scores[name] = r
        zh = " ".join("%s:%s" % (z["word"], z.get("rel")) if z["found"] else z["word"] + ":-" for z in r["zh"])
        print("%-4s %s %.2f match %.2f f0 %s range %s st dur %s pace %s syl/s hiss %.2f | %s" % (
            name, r["lang"], r["lang_p"], r["match"], r["f0"], r["range_st"], r["dur"], r["pace"], r["hiss_share"], zh), flush=True)
        print("     heard:", r["heard"], flush=True)
        json.dump(scores, open(path, "w"), ensure_ascii=False, indent=1)


def clone(work, model_dir, takes=6, batch=6, only=None):
    import soundfile as sf
    import torch
    cand = CHOSEN[0]
    model = vr._load(model_dir)
    ref = os.path.join(work, "design", cand + ".wav")
    prompt = model.create_voice_clone_prompt(ref_audio=ref, ref_text=DESIGN_TEXT)
    folder = os.path.join(work, "clone")
    os.makedirs(folder, exist_ok=True)
    seeds_path = os.path.join(folder, "seeds.json")
    seeds = json.load(open(seeds_path)) if os.path.exists(seeds_path) else {}
    todo = []
    for key, text in _all_lines():
        if only and key not in only:
            continue
        # the parts of line 5 are a word or two: fewer takes of them
        for k in range(takes if len(key) == 2 else max(3, takes - 2)):
            path = os.path.join(folder, "%s_%d.wav" % (key, k))
            if not os.path.exists(path):
                todo.append((key, text, path))
    todo.sort(key=lambda t: len(t[1]))
    for i in range(0, len(todo), batch):
        group = todo[i:i + batch]
        s = 1958 + 7 * i + (sum(ord(c) for c in group[0][0]) if only else 0)
        torch.manual_seed(s)
        longest = max(len(t[1]) for t in group)
        # about 12 codec frames a second and 14 characters a second of slow speech: room for twice that
        cap = int(min(400, 40 + longest * 1.9))
        wavs, rate = model.generate_voice_clone(text=[t[1] for t in group], language=["Spanish"] * len(group),
                                                voice_clone_prompt=[prompt[0]] * len(group), max_new_tokens=cap)
        for (key, text, path), wav in zip(group, wavs):
            sf.write(path, wav, rate)
            seeds[os.path.basename(path)] = {"seed": s, "batch": [os.path.basename(t[2]) for t in group]}
            print(os.path.basename(path), text, "%.2f s" % (len(wav) / rate), flush=True)
        json.dump(seeds, open(seeds_path, "w"), indent=1)


def judge(work):
    import librosa
    import numpy as np
    import torch
    from speechbrain.inference.speaker import EncoderClassifier
    vr._quiet_warnings()
    asr = vr._asr("small")
    enc = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb", savedir=os.path.join(work, "ecapa"), run_opts={"device": "cpu"})

    def emb(y):
        with torch.inference_mode():
            e = enc.encode_batch(torch.tensor(y)[None])[0, 0].numpy()
        return e / np.linalg.norm(e)
    ref = emb(librosa.load(os.path.join(work, "design", CHOSEN[0] + ".wav"), sr=16000)[0])
    path_scores = os.path.join(work, "scores.json")
    old = {(r["file"], r.get("mtime")): r for r in (json.load(open(path_scores)) if os.path.exists(path_scores) else [])}
    rows = []
    for key, text in _all_lines():
        for path in sorted(glob.glob(os.path.join(work, "clone", "%s_*.wav" % key))):
            mtime = round(os.path.getmtime(path), 3)
            if (os.path.basename(path), mtime) in old:
                rows.append(old[(os.path.basename(path), mtime)])
                continue
            r = _analyse(path, text, asr, LL_WORDS.get(key, []), ["avenidas", "desde", "sola", "todos", "cubierto"] if key in ("06", "08") else [])
            y, _ = librosa.load(path, sr=16000)
            r.update({"file": os.path.basename(path), "key": key, "text": text, "voice": round(float(emb(y) @ ref), 3), "mtime": mtime})
            # the conjunction "y" (a vowel): the hiss in its span, which should be low (a sung [i], not a [ʃ])
            if key in Y_VOWEL:
                at = vr._where("y", [tuple(s) for s in r["spans"]], set())
                if at:
                    y24, rate = librosa.load(path, sr=24000)
                    r["y_hiss"] = round(vr._hiss(y24, rate, at[0], at[1])[0], 3)
            rows.append(r)
            zh = " ".join("%s:%s" % (z["word"], z.get("rel")) for z in r["zh"] if z["found"])
            print("%-10s match %.2f voice %.3f dur %.2f pace %.2f f0 %s %s y %s | %s" % (
                r["file"], r["match"], r["voice"], r["dur"], r["pace"], r["f0"], zh, r.get("y_hiss", "-"), r["heard"]), flush=True)
            json.dump(rows + [v for k, v in old.items() if v not in rows], open(path_scores, "w"), ensure_ascii=False, indent=1)
    json.dump(rows, open(path_scores, "w"), ensure_ascii=False, indent=1)


def pick(work):
    """The best take a line: heard right first (within 0.03 of the best heard), then near the design voice, at the
    narrator's slow pace (penalised over 4.6 syllables a second), the ll of "llegaron"/"llevar" hissing where it should."""
    rows = json.load(open(os.path.join(work, "scores.json")))
    chosen = {}
    for key, text in _all_lines():
        takes = [r for r in rows if r["key"] == key]
        if not takes:
            continue
        best_words = max(r["match"] for r in takes)

        def score(r):
            s = r["voice"] - 0.08 * max(0.0, r["pace"] - 4.6) - 0.05 * max(0.0, 2.6 - r["pace"])
            # the porteño ll of "llevar", "llegaron", "ellos": hissing as an /s/ does
            for z in r["zh"]:
                if z["found"] and z.get("rel") is not None:
                    s += 0.08 * min(1.0, z["rel"])
            # a statement heard as a question (its intonation rising): "¿Quién la tocaba?" is not the line
            if "?" not in text and ("?" in r["heard"] or "¿" in r["heard"]):
                s -= 0.15
            return s
        best = max((r for r in takes if r["match"] >= best_words - 0.03), key=score)
        chosen[key] = best
        print(key, "<-", best["file"], "| %s | match %.2f voice %.3f pace %.2f dur %.2f" % (best["heard"], best["match"], best["voice"], best["pace"], best["dur"]))
    json.dump(chosen, open(os.path.join(work, "chosen.json"), "w"), ensure_ascii=False, indent=1)


def _clean(x, rate):
    """Trim, de-click, breaths down. x: mono float at `rate`."""
    import numpy as np
    from scipy.signal import butter, sosfiltfilt
    x = x.astype(np.float64)
    x = sosfiltfilt(butter(2, 55 / (rate / 2), btype="high", output="sos"), x)
    # clicks: a sample far off the line through its neighbours (a jump much bigger than the local high-frequency
    # level) is replaced by the interpolation of the samples round it
    d2 = np.abs(x[2:] - 2 * x[1:-1] + x[:-2])
    hop = int(0.01 * rate)
    local = np.convolve(d2, np.ones(hop) / hop, mode="same") + 1e-6
    bad = np.where(d2 > 9.0 * local)[0] + 1
    for i in bad:
        a, b = max(0, i - 3), min(len(x) - 1, i + 3)
        x[a:b + 1] = np.linspace(x[a], x[b], b - a + 1)
    # the level, 10 ms frames; speech is where it is within 30 dB of the loudest part
    n = len(x) // hop
    env = np.array([np.sqrt(np.mean(x[k * hop:(k + 1) * hop] ** 2)) for k in range(n)]) + 1e-9
    db = 20 * np.log10(env / env.max())
    # a breath: a run of frames between -42 and -18 dB with the energy of a hiss (more above 2 kHz than voice has)
    spec_hi = []
    for k in range(n):
        f = x[k * hop:(k + 1) * hop]
        s = np.abs(np.fft.rfft(f * np.hanning(len(f)))) ** 2
        fr = np.fft.rfftfreq(len(f), 1.0 / rate)
        spec_hi.append(s[fr > 2000].sum() / (s.sum() + 1e-12))
    spec_hi = np.array(spec_hi)
    voiced = db > -24
    gain = np.ones(n)
    for k in range(n):
        if not voiced[k] and (spec_hi[k] > 0.45 or db[k] < -42):
            gain[k] = 10 ** (-18 / 20)
    # smoothed so nothing is cut sharp
    g = np.repeat(gain, hop)
    g = np.concatenate([g, np.full(len(x) - len(g), g[-1] if len(g) else 1.0)])
    k = int(0.02 * rate)
    g = np.convolve(g, np.ones(k) / k, mode="same")
    x = x * g
    # trim: 60 ms before the first frame above -36 dB, 160 ms after the last
    above = np.where(db > -36)[0]
    if above.size:
        a = max(0, above[0] * hop - int(0.06 * rate))
        b = min(len(x), (above[-1] + 1) * hop + int(0.16 * rate))
        x = x[a:b]
    fade = int(0.01 * rate)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade * 4:] *= np.linspace(1, 0, fade * 4)
    return x


# The narrator's measure: the takes come out a little brisk for a slow storyteller (4 to 4.5 syllables a second), so
# the cleaned line is slowed by TEMPO (ffmpeg's atempo: the pitch kept) and each pause inside it is let breathe
# longer (BREATHE: the quiet stretch lengthened by most of its own length, at most PAUSE_MAX s more).
TEMPO = 0.95
BREATHE = 0.8
PAUSE_MAX = 0.22


def _breathe(x, rate):
    """The pauses inside a line lengthened: each quiet stretch (under -36 dB of the loudest 10 ms, 60 ms or longer,
    not at the ends) gets its own quiet repeated in its middle, crossfaded."""
    import numpy as np
    hop = int(0.01 * rate)
    n = len(x) // hop
    env = np.array([np.sqrt(np.mean(x[k * hop:(k + 1) * hop] ** 2)) for k in range(n)]) + 1e-9
    quiet = 20 * np.log10(env / env.max()) < -36
    runs, k = [], 0
    while k < n:
        if quiet[k]:
            j = k
            while j < n and quiet[j]:
                j += 1
            if j - k >= 6 and k > 10 and j < n - 10:
                runs.append((k * hop, j * hop))
            k = j
        else:
            k += 1
    out, last = [], 0
    fade = int(0.01 * rate)
    for a, b in runs:
        mid = (a + b) // 2
        extra = int(min(PAUSE_MAX * rate, BREATHE * (b - a)))
        quiet_part = x[a + fade:b - fade]
        if len(quiet_part) < 2 * fade or extra < fade:
            continue
        fill = np.resize(quiet_part, extra).copy()
        fill[:fade] *= np.linspace(0, 1, fade)
        fill[-fade:] *= np.linspace(1, 0, fade)
        out += [x[last:mid], fill]
        last = mid
    out.append(x[last:])
    return np.concatenate(out)


def _tempo(x, rate, factor):
    """Slowed by `factor` (ffmpeg's atempo, the pitch kept)."""
    import subprocess
    import tempfile
    import soundfile as sf
    if abs(factor - 1.0) < 1e-3:
        return x
    with tempfile.TemporaryDirectory() as tmp:
        a, b = os.path.join(tmp, "a.wav"), os.path.join(tmp, "b.wav")
        sf.write(a, x.astype("float32"), rate, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a, "-af", "atempo=%.4f" % factor, "-c:a", "pcm_f32le", b], check=True)
        y, _ = sf.read(b)
    return y


def clean(work, out):
    import librosa
    import soundfile as sf
    chosen = json.load(open(os.path.join(work, "chosen.json")))
    os.makedirs(out, exist_ok=True)
    for key, r in chosen.items():
        x, rate = librosa.load(os.path.join(work, "clone", r["file"]), sr=48000, mono=True)
        y = _clean(x, rate)
        y = _tempo(_breathe(y, rate), rate, TEMPO)
        sf.write(os.path.join(out, "line_%s.wav" % key), y.astype("float32"), rate, subtype="PCM_24")
        print(key, r["file"], "%.2f s -> %.2f s" % (len(x) / rate, len(y) / rate))


def provenance(work):
    os.makedirs(PROVENANCE, exist_ok=True)
    meta = json.load(open(os.path.join(work, "design", "meta.json")))
    scores = json.load(open(os.path.join(work, "design_scores.json")))
    seeds = json.load(open(os.path.join(work, "clone", "seeds.json")))
    rows = json.load(open(os.path.join(work, "scores.json")))
    chosen = json.load(open(os.path.join(work, "chosen.json")))
    cand, runners = CHOSEN
    with open(os.path.join(PROVENANCE, "narrator.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["role", "candidate", "chosen", "synthesiser", "design_seed", "design_instruct", "design_text", "whisper_heard",
                    "words_match", "f0_hz", "pace_syll_s", "ll_y_hissing_share"])
        for name in sorted(meta):
            s = scores.get(name, {})
            w.writerow(["narrator", name, "chosen" if name == cand else ("runner-up" if name in runners else ""),
                        "Qwen3-TTS-12Hz-1.7B-VoiceDesign (Apache-2.0)", meta[name]["seed"], meta[name]["instruct"], meta[name]["text"],
                        s.get("heard", ""), s.get("match", ""), s.get("f0", ""), s.get("pace", ""), s.get("hiss_share", "")])
    with open(os.path.join(PROVENANCE, "lines.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["line", "text", "take", "chosen", "synthesiser", "clone_seed", "duration_s", "whisper_heard", "words_match",
                    "voice_match_ecapa", "pace_syll_s", "f0_hz", "ll_hiss_vs_s", "y_vowel_hiss"])
        for r in sorted(rows, key=lambda r: r["file"]):
            ll = " ".join("%s:%s" % (z["word"], z.get("rel")) for z in r["zh"] if z["found"])
            w.writerow([r["key"], r["text"], r["file"], "chosen" if chosen.get(r["key"], {}).get("file") == r["file"] else "",
                        "Qwen3-TTS-12Hz-1.7B-Base, cloned from the designed voice (VoiceDesign %s, narrator.csv)" % cand,
                        seeds.get(r["file"], {}).get("seed", ""), r["dur"], r["heard"], r["match"], r["voice"], r["pace"], r["f0"], ll,
                        r.get("y_hiss", "")])
    d = scores.get(cand, {})
    notes = {
        "what": "The narrator of the Hora Cero cinematic trailer (tools/trailer/hc2_*): synthetic, designed from a written "
                "description, never a copy of anyone. No recording of any person was used, and no actor, announcer or "
                "narrator is named or meant in the description.",
        "description_en": "A porteño man of about sixty. A deep, warm, slightly husky voice, slow and measured, like a "
                          "1950s radio storyteller; serious and restrained, not melodramatic. A clear Rioplatense accent: "
                          "ll and y as [ʃ]/[ʒ] ('calle', 'llegaron', 'ellos'), voseo.",
        "design_instruct_es": meta[cand]["instruct"],
        "design_text": meta[cand]["text"],
        "design_seed": meta[cand]["seed"],
        "chosen_design_take": cand,
        "runners_up": runners,
        "candidates": len(meta),
        "design_model": "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign (Apache-2.0)",
        "clone_model": "Qwen/Qwen3-TTS-12Hz-1.7B-Base (Apache-2.0), every line cloned from the chosen design take",
        "accent_check_design": {"calle": next((z.get("rel") for z in d.get("zh", []) if z["word"] == "calle"), None),
                                "llegaron": next((z.get("rel") for z in d.get("zh", []) if z["word"] == "llegaron"), None),
                                "note": "hiss of the ll/y consonant (3-8 kHz) relative to an /s/ of the same take; "
                                        ">= 0.3 counts as hissing ([ʃ]/[ʒ]), near 0 is the [ʝ]/[j] of other Spanish"},
        "accent_check_lines": {r["file"]: {z["word"]: z.get("rel") for z in r["zh"] if z["found"]}
                               for r in rows if r["key"] in LL_WORDS and chosen.get(r["key"], {}).get("file") == r["file"]},
        "accent_check_clone": json.load(open(os.path.join(work, "accent.json"))) if os.path.exists(os.path.join(work, "accent.json")) else None,
        "chosen_lines": {k: v["file"] for k, v in sorted(chosen.items())},
        "post": "clean(): trimmed, de-clicked, breaths down 18 dB, pauses inside a line lengthened (BREATHE %.1f, at most "
                "%.2f s), slowed to %.2f (ffmpeg atempo, pitch kept)" % (BREATHE, PAUSE_MAX, TEMPO),
        "caveat": "Judged by measurement (Whisper, ECAPA, the hiss measure), not by ear: listen before it ships.",
    }
    json.dump(notes, open(os.path.join(PROVENANCE, "notes.json"), "w"), ensure_ascii=False, indent=1)
    print("provenance in", PROVENANCE)


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__)
        return 2
    cmd, work = a[0], a[1]
    opts = dict(x.split("=", 1) for x in a[2:] if "=" in x)
    if cmd == "design":
        design(work, a[2], per_variant=int(opts.get("n", 4)), variants=opts.get("variants", "ABC"), seed=int(opts.get("seed", 1958)))
    elif cmd == "audition":
        audition(work)
    elif cmd == "clone":
        clone(work, a[2], takes=int(opts.get("takes", 6)), batch=int(opts.get("batch", 6)),
              only=opts["only"].split(",") if "only" in opts else None)
    elif cmd == "accent":
        accent(work, a[2], takes=int(opts.get("takes", 4)))
    elif cmd == "judge":
        judge(work)
    elif cmd == "pick":
        pick(work)
    elif cmd == "clean":
        clean(work, a[2])
    elif cmd == "provenance":
        provenance(work)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
