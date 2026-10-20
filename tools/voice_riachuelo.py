#!/usr/bin/env python3
"""Makes the voices of Operation Riachuelo's four neighbours (Hornero, Lechuza, Benteveo, Biguá): porteños of
Buenos Aires in 1958, in Rioplatense Spanish and in English with their accent. Nothing recorded, nobody's voice
copied: each voice is designed from a written description (Qwen3-TTS VoiceDesign, Apache-2.0), and every line,
Spanish and English, is cloned from that one design take with Qwen3-TTS Base, so the English carries the accent.

    python3 tools/voice_riachuelo.py design <work> <VoiceDesign model dir> [who ...] [variants=AB n=4 seed=1958]
    python3 tools/voice_riachuelo.py audition <work> [who ...]                         # words, accent, pitch
    python3 tools/voice_riachuelo.py split <work>                                      # calm / urgent references
    python3 tools/voice_riachuelo.py clone <work> <Base model dir> [who ...]           # three takes a line
    python3 tools/voice_riachuelo.py judge <work> [who ...]                            # words, voice match, pitch
    python3 tools/voice_riachuelo.py pick <work>                                       # best take a line
    python3 tools/voice_riachuelo.py install <work>                                    # into the game
    python3 tools/voice_riachuelo.py sheet <work> <casting.html>                       # a page to listen to

`design` makes candidates of the descriptions named by `variants` (see `instructs`: A, B, Z for everyone, C to F
for Benteveo) into <work>/design/<who>/; `design <work> <model> _calib variants=MX n=2` makes the Madrid and
Mexico City voices the accent check is calibrated on. CHOSEN below names the design take each voice is cloned
from, after `audition` and a look at pitch and timbre; the casting notes are tools/voices/riachuelo/notes.json.

`install` writes ONLY the four neighbours' files (godot/assets/audio/voice/en|es/<id>_<kind>_<n>.wav, through
tools/voice_prep.py: same trimming, level and format as every other line); the only file it removes is a
neighbour's line that has been taken out of CAST. (The passenger's lines, asset_*, were made apart, with Kokoro in
English and Qwen3-TTS in Spanish, and are not touched.)
Provenance goes to tools/voices/riachuelo/ (voices.csv: the designs; en/clips.csv, es/clips.csv: every line).

Needs a Python with qwen-tts, torch, soundfile, librosa, faster-whisper and speechbrain; `audition` also uses
allosaurus (a universal phone recogniser) when it can be imported. On two CPU cores a batch of eight short takes
takes about as long as one, so takes are made in batches.

The accent check (`audition`) is crude and says so: Whisper's language and words; for every ll/y word, whether
there is hiss in it at all (a [ʒ] or [ʃ] hisses, a [j] or [ʝ] of Spain or Mexico does not: the strongest 3-8 kHz
share of energy in the word, against an /s/ of the same take) and whether that hiss is voiced (energy under
400 Hz alongside it: [ʒ] buzzes, the modern [ʃ] does not); allosaurus' phones over the same word; [θ] anywhere
(Spain; allosaurus never reported one, not even for the Madrid voice, so that part proves nothing); the pitch and
how much it moves (the Italian rise and fall).
"""
import csv
import difflib
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROVENANCE = os.path.join(HERE, "voices", "riachuelo")
LANGUAGE = {"en": "English", "es": "Spanish"}
TAKES = 3
LOUD = ("spotted", "hurt")

# What every design says about the accent (Spanish, as the text is): concrete sounds, not "an accent".
ACCENT = ("Pronuncia la 'll' y la 'y' como una 'zh' sonora y zumbante, como la 's' de 'measure' en inglés o la 'j' "
          "francesa: 'calle' suena 'cazhe', 'yo' suena 'zho', 'llueve' suena 'zhueve'. Aspira la 's' antes de "
          "consonante: 'esto' suena 'ehto', 'mismo' suena 'mihmo'. La 'c' y la 'z' suenan siempre como 's'. Habla "
          "de vos. Entonación cantada, a la italiana: el tono sube sobre la sílaba acentuada y baja en escalones "
          "al final de cada frase.")
ACCENT_SHORT = ("Habla de vos, con la melodía cantada de los hijos de italianos: sube en la sílaba fuerte y cae en "
                "escalones al final. La 'll' y la 'y' muy sonoras y zumbadas, como 'zh' ('cazhe', 'zho'). Las eses "
                "antes de consonante se aspiran.")
OPENING = "Español rioplatense de Buenos Aires, Argentina, con el acento porteño de los años cincuenta. "

# Each neighbour: how he sounds (two wordings of the design), what the design take says (a calm part full of
# ll/y, voseo, c/z and s+consonant, then an urgent part that starts at `cut`), the words the accent check
# listens to, and his lines (kind, English, Spanish) in take order.
CAST = {
    "hornero": {
        "name": "Hornero", "who": "Aldo Ferrante, the motorman (about 42; the leader)",
        "persona": ("Hombre de unos cuarenta años, conductor de tranvía del barrio de La Boca, hijo de genoveses. "
                    "Voz de barítono grave y cálida, tranquila y seca; habla poco, sin apuro, con un dejo cansado. "),
        "persona_short": ("Un porteño de 1958 de unos cuarenta años, motorman de tranvía en La Boca: voz grave y "
                          "cálida de barítono, calma, de pocas palabras, algo cansado y con humor seco. "),
        "calm": "Che, vení, que llueve y yo me voy a la calle. Esto mismo te dije ayer: el tranvía de las cinco ya no pasa por acá.",
        "urgent": "¡Guarda, nos vieron! ¡Abajo, rápido!", "cut": "guarda",
        "zh": ["llueve", "yo", "calle", "ayer", "ya"], "s": ["pasa", "esto"],
        "lines": [
            ("select", "Go on, then.", "Decime, che."),
            ("select", "Right here.", "Acá estoy."),
            ("move", "Next stop.", "Próxima parada."),
            ("move", "Off we go. Gently.", "Vamos, despacito."),
            ("attack", "This one gets off here.", "Este se baja acá."),
            ("attack", "Bedtime, friend.", "A dormir, amigo."),
            ("work", "Leave it to me.", "Dejámelo a mí."),
            ("work", "I'll sort it out.", "Ya lo arreglo."),
            ("done", "There. All mended.", "Ya está. Arreglado."),
            ("done", "Done. On we go.", "Listo. Sigamos."),
            ("refuse", "I can't get through there.", "Por ahí no paso."),
            ("refuse", "That can't be done.", "Eso no se puede, che."),
            ("refuse", "No tram runs that way.", "Ese recorrido no existe."),
            ("spotted", "Look out, they've seen us!", "¡Guarda, nos vieron!"),
            ("spotted", "Blast, they've spotted me!", "¡La pucha, me junaron!"),
            ("hurt", "Ah! I'm hit!", "¡Uy, me dieron!"),
            ("hurt", "Not dead yet.", "Aguanto, aguanto."),
        ],
    },
    "lechuza": {
        "name": "Lechuza", "who": "Ernesto Saravia, the night lineman (about 55)",
        "persona": ("Hombre mayor, de unos cincuenta y cinco años, electricista de guardia nocturna de la compañía de "
                    "luz. Voz seca, algo ronca y gastada, más fina que grave, irónica; habla despacio y con precisión. "),
        "persona_short": ("Un porteño de 1958 de unos cincuenta y cinco años, electricista que trabaja de noche: voz "
                          "fina, seca y un poco ronca de hombre mayor, irónica, lenta y precisa. "),
        "calm": "Mirá vos, pibe: la luz de la calle se apagó otra vez allá en la esquina. Yo ya sabía que era el fusible; hace cinco noches que falla.",
        "urgent": "¡Araca, la cana! ¡Me dieron, carajo!", "cut": "araca",
        "zh": ["calle", "allá", "yo", "ya"], "s": ["se", "sabía"],
        "lines": [
            ("select", "I'm listening, lad.", "Te escucho, pibe."),
            ("select", "Now what?", "¿Y ahora qué?"),
            ("move", "Coming, coming. No hurry.", "Voy, voy. Sin apuro."),
            ("move", "Through the dark, as always.", "Por lo oscuro, como siempre."),
            ("attack", "Two turns of cord and that's him.", "Dos vueltas de cable y listo."),
            ("attack", "Hold still now. I'll tie you.", "Quieto ahí, que te ato."),
            ("work", "Easy as changing a fuse.", "Esto es como cambiar un fusible."),
            ("work", "I know this by heart.", "Esto lo conozco de memoria."),
            ("done", "Lights out.", "Se cortó la luz."),
            ("done", "Neat and tidy.", "Hecho. Limpito."),
            ("refuse", "At my age? Not a chance.", "¿A mi edad? Minga."),
            ("refuse", "There's no way through there.", "Por ahí no hay paso."),
            ("refuse", "That won't work.", "Eso no anda, che."),
            ("spotted", "Look out, they've seen me!", "¡Araca, me vieron!"),
            ("spotted", "Oh no, the law!", "¡Uy, la cana!"),
            ("hurt", "Oh, my old bones!", "¡Ay, mis huesos!"),
            ("hurt", "They got me, damn it!", "¡Me dieron, carajo!"),
        ],
    },
    "benteveo": {
        "name": "Benteveo", "who": "\"Tito\" Gaudino, the newspaper seller (about 16)",
        "persona": ("Muchacho de dieciséis años, canillita que vende diarios en la parada del tranvía. Voz joven de "
                    "tenor liviano, clara, de varón adolescente; habla rápido, pícaro y atrevido, y se come las eses "
                    "del final. "),
        "persona_short": ("Un pibe porteño de 1958, de dieciséis años, canillita del barrio: voz de muchacho, tenor "
                          "liviano, rápida, pícara y atrevida, que se come las eses del final. "),
        "calm": "¡Che, vos! ¿Sabés que llueve allá en la plaza? Yo me voy rajando, que los diarios de la Sexta ya están en la calle.",
        "urgent": "¡Cana, cana! ¡Rajemos, rápido!", "cut": "cana",
        "zh": ["llueve", "allá", "yo", "ya", "calle"], "s": ["sabés", "sexta"],
        "lines": [
            ("select", "Here, boss!", "¡Presente, jefe!"),
            ("select", "What's the game, then?", "¿Qué hacemos, che?"),
            ("move", "Come on, come on!", "¡Vamo, vamo!"),
            ("move", "Off I go, quick as you like!", "¡Ahí voy, rapidito!"),
            ("work", "Late edition! Read all about it!", "¡Diario, diario! ¡La Sexta!"),
            ("work", "I could do that blindfold!", "¡Eso lo hago con los ojos cerrados!"),
            ("refuse", "Me? Not a chance!", "¿Yo? ¡Minga!"),
            ("refuse", "Not on your life, boss!", "¡Ni loco, jefe!"),
            ("refuse", "Can't get through there.", "Por ahí no se pasa, che."),
            ("spotted", "Coppers! Leg it!", "¡Cana, cana! ¡Rajemos!"),
            ("spotted", "Uh-oh, they've seen me!", "¡Uy, me junaron!"),
            ("hurt", "Ow! Rotten luck!", "¡Ay! ¡Qué yeta!"),
            ("hurt", "Ow, ow, they got me!", "¡Ay, ay, me dieron!"),
        ],
    },
    "bigua": {
        "name": "Biguá", "who": "Cosme Ledesma, the boatman (about 35)",
        "persona": ("Hombre de unos treinta y cinco años, botero del Riachuelo, fuerte y callado. Voz muy grave, "
                    "profunda y oscura, baja y tranquila; habla lento, con pocas palabras, y aspira mucho las eses. "),
        "persona_short": ("Un porteño de 1958 de unos treinta y cinco años, botero que cruza gente por el Riachuelo: "
                          "voz de bajo, muy grave y oscura, tranquila, de pocas palabras, lenta. "),
        "calm": "Yo cruzo la gente a la otra orilla. Esta noche llueve, la marea está alta y el bote ya está listo, ¿viste?",
        "urgent": "¡Ojo, nos vieron! ¡Al agua, rápido!", "cut": "ojo",
        "zh": ["yo", "orilla", "llueve", "ya"], "s": ["cruzo", "gente"],
        "lines": [
            ("select", "I'm here.", "Acá ando."),
            ("select", "What d'you need?", "¿Qué precisás?"),
            ("move", "Slow, like the tide.", "Despacito, como la marea."),
            ("move", "Let's go. No noise.", "Vamos, sin ruido."),
            ("attack", "I'll do it. Quiet.", "Lo hago yo, callado."),
            ("attack", "The current takes him.", "Se lo lleva la corriente."),
            ("work", "I'll see to it.", "Yo me encargo."),
            ("work", "Steady. Like rowing.", "Con calma, como remar."),
            ("done", "That's it, brother.", "Listo, hermano."),
            ("done", "Done. On to the far bank.", "Hecho. A la otra orilla."),
            ("refuse", "Not that way.", "Por ahí, no."),
            ("refuse", "Not even the river gets through there.", "Ni el río pasa por ahí."),
            ("refuse", "Can't be done, brother.", "Imposible, hermano."),
            ("spotted", "I'm seen. Quick.", "Me vieron. Rápido."),
            ("spotted", "Watch it, the Guardia!", "¡Ojo, la Guardia!"),
            ("hurt", "I'm hit. I'll hold.", "Me dieron. Aguanto."),
            ("hurt", "Still going. Still going.", "Sigo, sigo."),
        ],
    },
}
ORDER = ["hornero", "lechuza", "benteveo", "bigua"]
# The design candidates kept for each neighbour after `audition` and listening (filled in by hand):
# who: (chosen candidate, [runners-up for the casting sheet])
CHOSEN = {
    "hornero": ("Z2", ["A1", "Z3"]),
    "lechuza": ("A1", ["Z4", "A2"]),
    "benteveo": ("C3", ["B2", "E2"]),
    "bigua": ("A4", ["A1", "A2"]),
}


# The second round leans on the buzz of the old [ʒ] (the first gave mostly the modern, voiceless [ʃ]).
BUZZ = " Es una 'zh' con zumbido de voz, sonora, como en la palabra francesa 'jour'."
# Benteveo's first round came out as children and women: say plainly that his voice has broken.
BOY = ("Muchacho varón de diecisiete años, con la voz ya cambiada: voz masculina joven de tenor liviano, clara, de "
       "hombre joven y no de niño. Canillita que vende diarios en la parada del tranvía; habla rápido, pícaro y "
       "atrevido, y se come las eses del final. ")
BOY_SHORT = ("Un muchacho porteño de 1958, de diecisiete años, varón con la voz ya cambiada: voz masculina joven de "
             "tenor, rápida, pícara y atrevida, de canillita de barrio, que se come las eses del final. ")
# The third try: a young man rather than a boy (the model hears "muchacho" and "canillita" as a child's voice).
YOUNG_MAN = ("Hombre joven de dieciocho años, de voz masculina de tenor, clara y juvenil pero de hombre adulto. Vende "
             "diarios en la parada del tranvía; habla rápido, con picardía y descaro, y se come las eses del final. ")
YOUNG_MAN_SHORT = ("Un hombre joven porteño de 1958, de dieciocho años, voz masculina de tenor claro, rápida y "
                   "descarada, de vendedor de diarios del barrio, que se come las eses del final. ")
# Calibration of the accent check, never cast: the same text read by a voice of Madrid and one of Mexico City,
# whose ll/y is [ʝ]/[j] (no hiss), to see that the check tells them from the porteños.
CALIBRATION = {
    "madrid": "Español de Madrid, España. Hombre de unos cuarenta años, voz de barítono grave y cálida, tranquila.",
    "mexico": "Español de la Ciudad de México. Hombre de unos cuarenta años, voz de barítono grave y cálida, tranquila.",
}


def instructs(who):
    if who == "_calib":
        return {"M": CALIBRATION["madrid"], "X": CALIBRATION["mexico"]}
    c = CAST[who]
    out = {"A": OPENING + c["persona"] + ACCENT, "B": OPENING + c["persona_short"] + ACCENT_SHORT,
           "Z": OPENING + c["persona"] + ACCENT + BUZZ}
    if who == "benteveo":
        out.update({"C": OPENING + BOY + ACCENT + BUZZ, "D": OPENING + BOY_SHORT + ACCENT_SHORT,
                    "E": OPENING + YOUNG_MAN + ACCENT + BUZZ, "F": OPENING + YOUNG_MAN_SHORT + ACCENT_SHORT})
    return out


def design_text(who):
    who = "hornero" if who == "_calib" else who
    return CAST[who]["calm"] + " " + CAST[who]["urgent"]


def _quiet_warnings():
    import warnings
    warnings.filterwarnings("ignore")


def _load(model_dir):
    """The model, with its codec decoding one take at a time: decoding a whole batch at once wants gigabytes of
    working memory (the weights themselves are mapped from disk), more than this machine spares."""
    import torch
    from qwen_tts import Qwen3TTSModel
    torch.set_num_threads(os.cpu_count() or 2)
    model = Qwen3TTSModel.from_pretrained(model_dir, dtype=torch.bfloat16, device_map="cpu")
    codec = model.model.speech_tokenizer
    whole = codec.decode

    def one_by_one(items):
        wavs, rate = [], None
        for item in items:
            w, rate = whole([item])
            wavs.extend(w)
        return wavs, rate
    codec.decode = one_by_one
    return model


def design(work, model_dir, people, per_variant=4, variants=("A", "B"), seed=1958, tag=""):
    import soundfile as sf
    import torch
    model = _load(model_dir)
    for who in people:
        folder = os.path.join(work, "design", who)
        os.makedirs(folder, exist_ok=True)
        meta_path = os.path.join(folder, "meta.json")
        meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
        ins = instructs(who)
        names, prompts = [], []
        for v in variants:
            for k in range(per_variant):
                name = "%s%s%d" % (v, tag, k + 1)
                if not os.path.exists(os.path.join(folder, name + ".wav")):
                    names.append(name)
                    prompts.append(ins[v])
        if not names:
            continue
        torch.manual_seed(seed)
        # 12 codec frames a second: a cap of 26 s, or one sample that never stops holds the whole batch for minutes
        wavs, rate = model.generate_voice_design(text=[design_text(who)] * len(names), language="Spanish", instruct=prompts, max_new_tokens=320)
        for name, prompt, wav in zip(names, prompts, wavs):
            sf.write(os.path.join(folder, name + ".wav"), wav, rate)
            meta[name] = {"instruct": prompt, "text": design_text(who), "seed": seed, "batch": names}
            print(who, name, "%.2f s" % (len(wav) / rate), flush=True)
        json.dump(meta, open(meta_path, "w"), ensure_ascii=False, indent=1)


def words(text):
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z ]+", " ", text).split()


def _asr(size="small"):
    from faster_whisper import WhisperModel
    return WhisperModel(size, device="cpu", compute_type="int8", cpu_threads=os.cpu_count() or 2)


# Phones allosaurus may give for the consonant of ll/y: hissing and voiced (the 1958 [ʒ]), hissing and voiceless
# (the modern [ʃ]), or no hiss at all (the [j]/[ʝ] of Spain, Mexico and most of the Spanish-speaking world).
ZH = {"ʒ", "ʑ", "d͡ʒ", "dʒ", "ʐ", "d͡ʑ", "dʑ", "ʒ̤", "d͡ʒ̤"}
SH = {"ʃ", "ɕ", "t͡ɕ", "tɕ", "tɕʰ", "t͡ʃ", "tʃ", "ʂ", "tʂ", "s", "z", "ç"}
YE = {"j", "ʝ", "i", "iː", "ɟ", "ɟʝ", "ʎ", "ɪ", "y", "ɨ", "e"}


def _phones(recognizer, y16, scratch):
    import soundfile as sf
    sf.write(scratch, y16, 16000)
    out = []
    for row in recognizer.recognize(scratch, timestamp=True).splitlines():
        parts = row.split()
        if len(parts) >= 3:
            out.append((float(parts[0]), float(parts[1]), parts[2]))
    return out


def _hiss(y, rate, a, b):
    """Strongest share of 3-8 kHz energy over 10 ms frames in [a, b] s, and the share under 400 Hz in those frames."""
    import numpy as np
    i, j = int(a * rate), int(b * rate)
    seg = y[max(0, i):max(i + 1, j)]
    hop = int(0.01 * rate)
    best, low = 0.0, 0.0
    for k in range(0, max(1, len(seg) - 2 * hop), hop):
        frame = seg[k:k + 2 * hop] * np.hanning(len(seg[k:k + 2 * hop]))
        if len(frame) < 2 * hop:
            break
        spec = np.abs(np.fft.rfft(frame)) ** 2
        freqs = np.fft.rfftfreq(len(frame), 1.0 / rate)
        total = spec[(freqs > 60)].sum() + 1e-12
        hf = spec[(freqs >= 3000) & (freqs <= 8000)].sum() / total
        if hf > best:
            best, low = hf, spec[(freqs > 60) & (freqs < 400)].sum() / total
    return best, low


def _word_spans(segments):
    out = []
    for s in segments:
        for w in (s.words or []):
            ws = words(w.word)
            if ws:
                out.append((ws[0], w.start, w.end))
    return out


def _where(word, spans, used):
    for i, (w, a, b) in enumerate(spans):
        if i not in used and (w == word or difflib.SequenceMatcher(None, w, word).ratio() >= 0.75):
            used.add(i)
            return a, b
    return None


def accent_report(path, who, asr, recognizer, scratch):
    """The crude accent check of one design take (see the module's docstring)."""
    import librosa
    import numpy as np
    y, rate = librosa.load(path, sr=24000)
    y16 = librosa.resample(y, orig_sr=24000, target_sr=16000)
    pad = np.zeros(8000, dtype=np.float32)
    segments, info = asr.transcribe(np.concatenate([pad, y16, pad]), beam_size=3, word_timestamps=True)
    segments = list(segments)
    heard = " ".join(s.text for s in segments).strip()
    spans = [(w, a - 0.5, b - 0.5) for (w, a, b) in _word_spans(segments)]
    c = CAST["hornero" if who == "_calib" else who]
    match = difflib.SequenceMatcher(None, " ".join(words(design_text(who))), " ".join(words(heard))).ratio()
    phones = _phones(recognizer, y16, scratch) if recognizer is not None else []
    used = set()
    s_ref = []
    for w in c["s"]:
        at = _where(w, spans, used)
        if at:
            s_ref.append(_hiss(y, rate, at[0], at[1])[0])
    s_level = max(s_ref) if s_ref else None
    zh = []
    for w in c["zh"]:
        at = _where(w, spans, used)
        if not at:
            zh.append({"word": w, "found": False})
            continue
        a, b = at
        # the consonant: the first 60% of a word that starts with it, the middle of one that has it inside
        lo, hi = (a, a + 0.6 * (b - a)) if w[0] in "ly" else (a + 0.25 * (b - a), a + 0.8 * (b - a))
        hf, low = _hiss(y, rate, lo, hi)
        ph = [p for (t, d, p) in phones if a - 0.03 <= t <= b + 0.03]
        kind = "zh" if any(p in ZH for p in ph) else "sh" if any(p in SH for p in ph) else "y" if any(p in YE for p in ph) else "?"
        zh.append({"word": w, "found": True, "hiss": round(hf, 3), "rel": round(hf / s_level, 2) if s_level else None,
                   "low": round(low, 3), "phones": " ".join(ph), "phone_class": kind})
    theta = sum(1 for (_, _, p) in phones if p in ("θ", "θ̪"))
    f0, voiced, _ = librosa.pyin(y16, fmin=60, fmax=400, sr=16000)
    f0v = f0[voiced] if np.any(voiced) else np.array([np.nan])
    semis = 12 * np.log2(f0v / np.nanmedian(f0v))
    calm_end = None
    used2 = set()
    at = _where(c["cut"], spans, used2)
    if at:
        calm_end = at[0]
    calm_f0 = f0[: int((calm_end or len(y16) / 16000) * 16000 / 512)]
    calm_f0 = calm_f0[~np.isnan(calm_f0)] if calm_f0.size else calm_f0
    # pyin can jump an octave: yin over the louder half of the frames as a second opinion
    f1 = librosa.yin(y16, fmin=50, fmax=500, sr=16000, frame_length=1024)
    rms = librosa.feature.rms(y=y16, frame_length=1024, hop_length=512)[0]
    f1 = f1[:len(rms)][rms[:len(f1)] > np.percentile(rms, 50)]
    hissing = [z for z in zh if z["found"] and z["rel"] is not None and z["rel"] >= 0.3]
    return {"heard": heard, "lang": info.language, "lang_p": round(info.language_probability, 3), "match": round(match, 2),
            "zh": zh, "theta": theta, "phones": " ".join(p for (_, _, p) in phones),
            "hiss_share": round(len(hissing) / max(1, len(zh)), 2),
            "voiced_share": round(sum(1 for z in hissing if z["low"] >= 0.12) / max(1, len(hissing)), 2) if hissing else 0.0,
            "f0_yin": round(float(np.median(f1)), 1) if f1.size else None,
            "f0_q": [round(float(v), 0) for v in np.nanpercentile(f0v, [10, 50, 90])] if np.any(voiced) else None,
            "f0": round(float(np.nanmedian(calm_f0)), 1) if calm_f0.size else None,
            "range_st": round(float(np.nanpercentile(semis, 90) - np.nanpercentile(semis, 10)), 1),
            "dur": round(len(y) / rate, 2)}


def _recognizer():
    try:
        from allosaurus.app import read_recognizer
        return read_recognizer()
    except Exception as e:  # the phone check is a bonus; the rest stands without it
        print("allosaurus not available (%s): no phone check" % e)
        return None


def audition(work, people):
    _quiet_warnings()
    asr = _asr("small")
    recognizer = _recognizer()
    scratch = os.path.join(work, "phones16k.wav")
    path = os.path.join(work, "design_scores.json")
    scores = json.load(open(path)) if os.path.exists(path) else {}
    for who in people:
        for wav in sorted(glob.glob(os.path.join(work, "design", who, "*.wav"))):
            name = who + "/" + os.path.basename(wav)[:-4]
            if name in scores:
                continue
            r = accent_report(wav, who, asr, recognizer, scratch)
            scores[name] = r
            zh = " ".join("%s:%s/%s/%s" % (z["word"], z.get("rel"), z.get("low"), z.get("phone_class")) if z["found"] else z["word"] + ":-" for z in r["zh"])
            print("%-16s %s %.2f match %.2f f0 %s (yin %s) range %s st theta %d hiss %.2f voiced %.2f | %s" % (
                name, r["lang"], r["lang_p"], r["match"], r["f0"], r["f0_yin"], r["range_st"], r["theta"], r["hiss_share"], r["voiced_share"], zh), flush=True)
            print("    heard:", r["heard"], flush=True)
            json.dump(scores, open(path, "w"), ensure_ascii=False, indent=1)
    if os.path.exists(scratch):
        os.remove(scratch)


def split(work):
    """Each chosen design take into its calm reference and its urgent one, cut at the quietest 20 ms before `cut`."""
    import librosa
    import numpy as np
    import soundfile as sf
    asr = _asr("small")
    os.makedirs(os.path.join(work, "refs"), exist_ok=True)
    for who in ORDER:
        take = os.path.join(work, "design", who, CHOSEN[who][0] + ".wav")
        x, rate = sf.read(take, dtype="float32")
        segments, _ = asr.transcribe(librosa.resample(x, orig_sr=rate, target_sr=16000), language="es", word_timestamps=True)
        found = [w for s in segments for w in s.words]
        cut_word = CAST[who]["cut"]
        j = next(i for i, w in enumerate(found) if cut_word in words(w.word)[:1] or (words(w.word) and difflib.SequenceMatcher(None, words(w.word)[0], cut_word).ratio() > 0.75))
        a, b = int(found[j - 1].end * rate), int(found[j].start * rate)
        hop = int(0.02 * rate)
        frames = [(float(np.sqrt(np.mean(x[i:i + hop] ** 2))), i) for i in range(a, max(a + 1, b - hop), hop // 2)]
        cut = min(frames)[1] + hop // 2 if frames else (a + b) // 2
        sf.write(os.path.join(work, "refs", who + "_calm.wav"), x[:cut], rate)
        sf.write(os.path.join(work, "refs", who + "_urgent.wav"), x[cut:], rate)
        print(who, "cut at %.2f s of %.2f" % (cut / rate, len(x) / rate))


def lines(who):
    out = []
    for n, (kind, en, es) in enumerate(CAST[who]["lines"], 1):
        for lang, text in (("en", en), ("es", es)):
            out.append({"who": who, "lang": lang, "n": n, "kind": kind, "text": text, "ref": "urgent" if kind in LOUD else "calm"})
    return out


def clone(work, model_dir, people, batch=12):
    import soundfile as sf
    import torch
    model = _load(model_dir)
    for who in people:
        prompts = {}
        for ref, text in (("calm", CAST[who]["calm"]), ("urgent", CAST[who]["urgent"])):
            prompts[ref] = model.create_voice_clone_prompt(ref_audio=os.path.join(work, "refs", "%s_%s.wav" % (who, ref)), ref_text=text)
        folder = os.path.join(work, "clone", who)
        os.makedirs(folder, exist_ok=True)
        todo = []
        for line in lines(who):
            for k in range(TAKES):
                path = os.path.join(folder, "%s_%02d_%d.wav" % (line["lang"], line["n"], k))
                if not os.path.exists(path):
                    todo.append((line, path))
        # like with like: one reference and one language a batch, similar lengths together
        todo.sort(key=lambda t: (t[0]["ref"], t[0]["lang"], len(t[0]["text"])))
        for i in range(0, len(todo), batch):
            group = todo[i:i + batch]
            torch.manual_seed(1958 + i)
            items = [prompts[line["ref"]][0] for line, _ in group]
            # a line is under three seconds: a cap of six (12 codec frames a second) keeps a runaway take from holding the batch
            wavs, rate = model.generate_voice_clone(text=[line["text"] for line, _ in group], language=[LANGUAGE[line["lang"]] for line, _ in group],
                                                    voice_clone_prompt=items, max_new_tokens=72)
            for (line, path), wav in zip(group, wavs):
                sf.write(path, wav, rate)
                print(os.path.relpath(path, work), line["text"], "%.2f s" % (len(wav) / rate), flush=True)


def judge(work, people):
    import librosa
    import numpy as np
    import torch
    from speechbrain.inference.speaker import EncoderClassifier
    _quiet_warnings()
    asr = _asr("small")
    enc = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb", savedir=os.path.join(work, "ecapa"), run_opts={"device": "cpu"})

    def emb(y):
        with torch.inference_mode():
            e = enc.encode_batch(torch.tensor(y)[None])[0, 0].numpy()
        return e / np.linalg.norm(e)

    for who in people:
        refs = {ref: emb(librosa.load(os.path.join(work, "refs", "%s_%s.wav" % (who, ref)), sr=16000)[0]) for ref in ("calm", "urgent")}
        old_path = os.path.join(work, "scores_%s.json" % who)
        # a take already judged (same file, same text, not made again since) keeps its score
        old = {(r["path"], r["text"], r.get("mtime")): r for r in (json.load(open(old_path)) if os.path.exists(old_path) else [])}
        rows = []
        for line in lines(who):
            for path in sorted(glob.glob(os.path.join(work, "clone", who, "%s_%02d_*.wav" % (line["lang"], line["n"])))):
                key = (os.path.relpath(path, work), line["text"], round(os.path.getmtime(path), 3))
                if key in old:
                    rows.append(old[key])
                    continue
                y, rate = librosa.load(path, sr=16000)
                pad = np.zeros(8000, dtype=np.float32)
                segments, _ = asr.transcribe(np.concatenate([pad, y, pad]), language=line["lang"], beam_size=3)
                heard = " ".join(s.text for s in segments).strip()
                match = difflib.SequenceMatcher(None, " ".join(words(line["text"])), " ".join(words(heard))).ratio()
                f0, voiced, _ = librosa.pyin(y, fmin=60, fmax=450, sr=rate)
                rows.append({"path": os.path.relpath(path, work), "lang": line["lang"], "n": line["n"], "kind": line["kind"], "text": line["text"],
                             "heard": heard, "match": round(match, 2), "voice": round(float(emb(y) @ refs[line["ref"]]), 3),
                             "dur": round(len(y) / rate, 2), "f0": round(float(np.nanmedian(f0)), 1) if np.any(voiced) else None,
                             "mtime": key[2]})
                r = rows[-1]
                print(who, os.path.basename(path), line["text"], "|", heard, r["match"], r["voice"], r["dur"], r["f0"], flush=True)
        json.dump(rows, open(os.path.join(work, "scores_%s.json" % who), "w"), ensure_ascii=False, indent=1)


def pick(work):
    """The best take a line: the words first (a take heard wrong is out if another is heard right), then the voice
    (ECAPA against the design), short and clean, and not squeaking far above the voice's own pitch."""
    import numpy as np
    chosen = {}
    for who in ORDER:
        rows = json.load(open(os.path.join(work, "scores_%s.json" % who)))
        calm = [r["f0"] for r in rows if r["f0"] and r["kind"] not in LOUD]
        home = float(np.median(calm)) if calm else 120.0
        for line in lines(who):
            takes = [r for r in rows if r["lang"] == line["lang"] and r["n"] == line["n"]]
            best_words = max(r["match"] for r in takes)
            ceiling = home * (1.9 if line["kind"] in LOUD else 1.45)
            # 0.03: one word wrong in a short line ("Can be done" for "Can't be done") is out
            best = max((r for r in takes if r["match"] >= best_words - 0.03),
                       key=lambda r: r["voice"] - 0.3 * max(0.0, r["dur"] - 2.4) - 0.004 * max(0.0, (r["f0"] or 0.0) - ceiling))
            chosen["%s/%s/%d" % (who, line["lang"], line["n"])] = best
            print(who, line["lang"], line["n"], best["text"], "<-", os.path.basename(best["path"]), "|", best["heard"], best["match"], best["voice"], best["dur"], best["f0"])
    json.dump(chosen, open(os.path.join(work, "chosen.json"), "w"), ensure_ascii=False, indent=1)


def game_name(who, kind, n_line):
    """<id>_<kind>_<k>: k counts the lines of that kind for that neighbour, in CAST order."""
    k = 0
    for n, (kd, _, _) in enumerate(CAST[who]["lines"], 1):
        if kd == kind:
            k += 1
        if n == n_line:
            return "%s_%s_%d" % (who, kind, k)
    raise KeyError((who, kind, n_line))


def install(work):
    """Only the four neighbours' files, through voice_prep.py (which writes the files it is given and nothing else),
    then the provenance in tools/voices/riachuelo/."""
    chosen = json.load(open(os.path.join(work, "chosen.json")))
    scores = json.load(open(os.path.join(work, "design_scores.json")))
    for lang in ("en", "es"):
        target = os.path.join(ROOT, "godot", "assets", "audio", "voice", lang)
        with tempfile.TemporaryDirectory() as takes:
            for who in ORDER:
                # a file of a neighbour whose line was taken out must not linger (these four only); the files that
                # are written again keep their .import, so Godot reimports them under the same uid
                keep = {game_name(who, kind, n) + ".wav" for n, (kind, _, _) in enumerate(CAST[who]["lines"], 1)}
                for name in os.listdir(target):
                    if name.startswith(who + "_") and name.endswith(".wav") and name not in keep:
                        for stale in (name, name + ".import"):
                            if os.path.exists(os.path.join(target, stale)):
                                os.remove(os.path.join(target, stale))
                for n, (kind, _, _) in enumerate(CAST[who]["lines"], 1):
                    r = chosen["%s/%s/%d" % (who, lang, n)]
                    shutil.copyfile(os.path.join(work, r["path"]), os.path.join(takes, game_name(who, kind, n) + ".wav"))
            done = subprocess.run([sys.executable, os.path.join(HERE, "voice_prep.py"), takes, "--lang=" + lang])
            if done.returncode != 0:
                sys.exit(done.returncode)
    os.makedirs(os.path.join(PROVENANCE, "en"), exist_ok=True)
    os.makedirs(os.path.join(PROVENANCE, "es"), exist_ok=True)
    with open(os.path.join(PROVENANCE, "voices.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        sys.path.insert(0, HERE)
        from voice_prep import PITCH
        w.writerow(["operative", "character", "synthesiser", "design_candidate", "design_seed", "design_instruct", "design_text", "pitch_hz",
                    "game_shift_semitones", "whisper_language", "runners_up"])
        for who in ORDER:
            cand, runners = CHOSEN[who]
            meta = json.load(open(os.path.join(work, "design", who, "meta.json")))[cand]
            s = scores["%s/%s" % (who, cand)]
            w.writerow([who, CAST[who]["who"], "Qwen3-TTS-12Hz-1.7B-VoiceDesign (Apache-2.0)", cand, meta["seed"], meta["instruct"], meta["text"],
                        s["f0"], PITCH.get((who, "es"), 0.0), "%s %.2f" % (s["lang"], s["lang_p"]), " ".join(runners)])
    for lang, head in (("en", ["voice", "file", "text", "ai_voice", "duration_s", "take", "heard", "words_match", "voice_match", "f0_hz"]),
                       ("es", ["voz", "archivo", "texto", "voz_ia", "duracion_s", "toma", "oido", "palabras", "parecido_voz", "f0_hz"])):
        with open(os.path.join(PROVENANCE, lang, "clips.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(head)
            for who in ORDER:
                engine = ("Qwen3-TTS-12Hz-1.7B-Base, designed voice cloned (VoiceDesign %s/%s, see voices.csv)" if lang == "en"
                          else "Qwen3-TTS-12Hz-1.7B-Base, voz diseñada clonada (VoiceDesign %s/%s, ver voices.csv)") % (who, CHOSEN[who][0])
                for n, (kind, _, _) in enumerate(CAST[who]["lines"], 1):
                    r = chosen["%s/%s/%d" % (who, lang, n)]
                    w.writerow([who, game_name(who, kind, n) + ".wav", r["text"], engine, r["dur"], os.path.basename(r["path"]),
                                r["heard"], r["match"], r["voice"], r["f0"]])
    print("provenance in", PROVENANCE)


def _b64_audio(path, kbps=40):
    import base64
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "a.mp3")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", "22050", "-c:a", "libmp3lame", "-b:a", "%dk" % kbps, out], check=True)
        return "data:audio/mpeg;base64," + base64.b64encode(open(out, "rb").read()).decode("ascii")


def sheet(work, out):
    """The casting sheet: notes from tools/voices/riachuelo/notes.json, the design takes (chosen and runners-up),
    and every line in both languages as it is in the game."""
    import html
    notes = json.load(open(os.path.join(PROVENANCE, "notes.json"), encoding="utf-8"))
    scores = json.load(open(os.path.join(work, "design_scores.json")))
    voice_dir = os.path.join(ROOT, "godot", "assets", "audio", "voice")
    esc = html.escape
    parts = []
    for who in ORDER:
        c = CAST[who]
        cand, runners = CHOSEN[who]
        meta = json.load(open(os.path.join(work, "design", who, "meta.json")))
        n = notes["people"][who]
        rows = []
        for name in [cand] + runners:
            s = scores["%s/%s" % (who, name)]
            zh = ", ".join("%s %s" % (z["word"], z.get("phone_class", "?")) for z in s["zh"] if z["found"])
            rows.append('<div class="cand%s"><div class="cand-head"><b>%s</b> %s<span class="meta">%s Hz · Whisper: %s %.0f%% · ll/y: %s</span></div>'
                        '<audio controls preload="none" src="%s"></audio><p class="note">%s</p></div>' % (
                            " chosen" if name == cand else "", esc(name), "<span class=\"tag\">chosen</span>" if name == cand else "",
                            s["f0"], s["lang"], 100 * s["lang_p"], esc(zh), _b64_audio(os.path.join(work, "design", who, name + ".wav")),
                            esc(n["candidates"].get(name, ""))))
        line_rows = []
        for i, (kind, en, es) in enumerate(c["lines"], 1):
            g = game_name(who, kind, i)
            line_rows.append("<tr><td class=\"kind\">%s</td><td><div class=\"txt\">%s</div><audio controls preload=\"none\" src=\"%s\"></audio></td>"
                             "<td><div class=\"txt\">%s</div><audio controls preload=\"none\" src=\"%s\"></audio></td></tr>" % (
                                 kind, esc(es), _b64_audio(os.path.join(voice_dir, "es", g + ".wav"), 48), esc(en), _b64_audio(os.path.join(voice_dir, "en", g + ".wav"), 48)))
        parts.append("""<section id="%s"><h2>%s <span class="sub">%s</span></h2>
<p class="verdict">%s</p>
<details><summary>Design description (VoiceDesign, Spanish)</summary><p class="design">%s</p><p class="design"><i>Design take text:</i> %s</p></details>
<h3>Candidates</h3>%s
<h3>Lines in the game</h3><table><thead><tr><th>Kind</th><th>Español</th><th>English</th></tr></thead><tbody>%s</tbody></table></section>""" % (
            who, esc(c["name"]), esc(c["who"]), esc(n["verdict"]), esc(meta[cand]["instruct"]), esc(meta[cand]["text"]), "".join(rows), "".join(line_rows)))
    calib = "".join('<div class="cand"><div class="cand-head"><b>%s</b></div><audio controls preload="none" src="%s"></audio><p class="note">%s</p></div>' % (
        esc(name), _b64_audio(os.path.join(work, "design", "_calib", name + ".wav")), esc(text)) for name, text in notes.get("calibration", {}).items())
    if calib:
        parts.append('<section id="calibration"><h2>Calibration <span class="sub">the same model, not porteño</span></h2>%s</section>' % calib)
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Riachuelo Casting Sheet</title><style>
:root{--bg:#f6f3ee;--fg:#1f1d1a;--mute:#6b655c;--card:#fffdf9;--line:#e2dbd0;--accent:#8a4b2a}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#1a1917;--fg:#ece7df;--mute:#a59d90;--card:#23211e;--line:#3a3631;--accent:#e0a27c}}
:root[data-theme="dark"]{--bg:#1a1917;--fg:#ece7df;--mute:#a59d90;--card:#23211e;--line:#3a3631;--accent:#e0a27c}
body{background:var(--bg);color:var(--fg);font:16px/1.5 Georgia,serif;margin:0;padding:24px 16px 64px}
main{max-width:980px;margin:0 auto}h1{font-size:28px;margin:0 0 4px}h2{border-top:2px solid var(--line);padding-top:20px;margin-top:40px}
.sub,.meta{color:var(--mute);font-size:14px;font-weight:normal}.meta{display:block}.intro p,.verdict{max-width:70ch}
.cand{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin:8px 0}.cand.chosen{border-color:var(--accent)}
.tag{background:var(--accent);color:var(--bg);font:12px sans-serif;padding:1px 6px;border-radius:4px;margin-left:6px}
audio{width:100%%;max-width:420px;height:34px;margin-top:4px}.note{margin:6px 0 0;font-size:14px;color:var(--mute)}
table{width:100%%;border-collapse:collapse;font-size:15px}td,th{border-bottom:1px solid var(--line);padding:6px 4px;vertical-align:top;text-align:left}
.kind{font:13px monospace;color:var(--mute);white-space:nowrap}.txt{font-weight:bold}.design{font-size:14px;color:var(--mute)}
@media (max-width:640px){table,thead,tbody,tr,td,th{display:block}thead{display:none}td{border:0}tr{border-bottom:1px solid var(--line);padding:6px 0}}
</style></head><body><main><h1>Operation Riachuelo: the voices</h1><p class="sub">Casting sheet · Hornero, Lechuza, Benteveo, Biguá · %s</p>
<div class="intro">%s</div>%s</main></body></html>""" % (esc(notes["date"]), notes["intro_html"], "".join(parts))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(page)
    print(out, "%.1f MB" % (os.path.getsize(out) / 1e6))


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__)
        return 2
    cmd, work = a[0], a[1]
    who = lambda rest: [w for w in rest if w in CAST] or ORDER
    if cmd == "design":
        # design <work> <model> [who ...] [variants=AB] [n=4] [seed=1958] [tag=]
        opts = dict(x.split("=", 1) for x in a[3:] if "=" in x)
        people = [w for w in a[3:] if w in CAST or w == "_calib"] or ORDER
        design(work, a[2], people, per_variant=int(opts.get("n", 4)), variants=tuple(opts.get("variants", "AB")),
               seed=int(opts.get("seed", 1958)), tag=opts.get("tag", ""))
    elif cmd == "audition":
        audition(work, [w for w in a[2:] if w in CAST or w == "_calib"] or ORDER)
    elif cmd == "split":
        split(work)
    elif cmd == "clone":
        clone(work, a[2], who(a[3:]))
    elif cmd == "judge":
        judge(work, who(a[2:]))
    elif cmd == "pick":
        pick(work)
    elif cmd == "install":
        install(work)
    elif cmd == "sheet":
        sheet(work, a[2])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
