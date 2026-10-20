# Operative voice lines

The game answers the player in the operatives' own voices: when one of the squad is selected, when he is given an
order, when he cannot carry one out, when his work is done and when things go wrong. Riachuelo's passenger has a few
lines of his own.

The shipped lines are synthesised, not recorded, and nobody's voice is copied. The four neighbours of La Boca
(Hornero, Lechuza, Benteveo, Biguá) are porteños of 1958, made by `tools/voice_riachuelo.py`: each voice is designed
with Qwen3-TTS VoiceDesign (Apache-2.0) from a Spanish description of the man and of the old Buenos Aires sound (the
buzzing "zh" for ll/y, the aspirated s, the Italian rise and fall, vos), several candidates are judged by
ear-substitutes (Whisper's words and language, a crude hiss-and-voicing check of every ll/y, the pitch) and one is
kept; then every line, Spanish and English, is cloned from that one design take with Qwen3-TTS Base, so the English
carries the accent. Its `install` step adds or replaces those four's files only. What made each line (the design
text, the take, what Whisper heard) is in `tools/voices/riachuelo/` (`voices.csv`, `en/clips.csv`, `es/clips.csv`).
The passenger's lines (`asset_*`) were made apart: Kokoro (Apache-2.0) in English, Qwen3-TTS in Spanish.
Do not use audio from any other game, film or library unless you hold a licence for it.

## How it works

- Files live in `godot/assets/audio/voice/<language>/` (`en/` or `es/`) and are named
  `<operative>_<kind>_<n>.wav`, for example `voice/es/hornero_select_1.wav`. The game plays the lines of the
  language the player chose; a line missing in Spanish falls back to the English one, then to a file left in
  `voice/` itself (the old flat folder).
- `<operative>` is `hornero`, `lechuza`, `benteveo`, `bigua` or `asset` (Riachuelo's passenger). `<n>` counts up
  from 1 with no gaps, up to 8 takes per kind.
- The game rotates through the takes, never talks over a line that is still playing, and does not repeat
  the same kind of answer from the same operative within four seconds.
- "Spotted" and "hurt" lines are urgent and cut in.
- Lines are heard in command mode too, so orders planned in the pause are acknowledged.

| Kind | When it plays |
| --- | --- |
| `select` | The operative is selected |
| `move` | A move, a carry or the order to head for the boat |
| `attack` | A takedown or a shot is ordered |
| `work` | Any other order: the bell, the papers, the cellar door, the lamp board, the ladder, the gondola, the boat, bringing the passenger up |
| `done` | A moment after a takedown, an opened door, the quay's lamps out, a ladder, gondola or boat made ready, the passenger brought up |
| `refuse` | An order he cannot carry out (no route, nothing left to throw, somebody else's job) |
| `spotted` | A guard has seen him |
| `hurt` | He has been hit |
| `freed` | The passenger only: the moment he is brought up |

## Recording

1. Use a phone's voice memo app in a quiet room, phone about a hand's width from the mouth.
2. Speak low and close, as if someone might hear. One line per recording, under two seconds.
3. Name each file as above (any audio format is fine: `hornero_select_1.m4a`).
4. Run `python3 tools/voice_prep.py <folder with the takes>` (English) or add `--lang=es` (Spanish). Add
   `--radio` for a field-radio sound.
5. Open the project in Godot once so the new files are imported, then play.

Three or four takes per kind is plenty. Start with `select` and `move`; they are heard the most.

## Lines

These are a starting set written for this game. Change them freely.

### Riachuelo: the four neighbours of La Boca, 1958

Porteños, so the Spanish is Rioplatense of the time: *vos* (vení, decime, precisás), *che*, and period
lunfardo only: *pibe* (lad), *cana* (the law), *junar* (to spot), *rajar* (to clear off), *minga* (no way),
*yeta* (bad luck), *¡araca!* (look out, an old man's word), *¡la pucha!* (blast), *¡guarda!* (look out). The
English is plain and a little British, as an Argentine of 1958 would have learned it, and is spoken with the
same voices, so it keeps their accent. Hornero says least and makes tram jokes; Lechuza is dry and technical;
Benteveo is quick and cheeky; Biguá speaks in river words. Benteveo never strikes and has nothing to finish, so
he has no `attack` or `done` lines. His voice is moved down two semitones in both languages (`PITCH` in
`tools/voice_prep.py`): as designed, his lines sat at about 230 Hz, high enough to risk sounding like a boy
whose voice has not broken. To change a line, edit `CAST`
in `tools/voice_riachuelo.py`, delete that line's takes and run its `clone`, `judge`, `pick` and `install` steps.

### Hornero (motorman: the tram's controller handle (stun), the tram bell, the keys; works the gondola) — the shipped lines

| Kind | English | Spanish |
| --- | --- | --- |
| select | "Go on, then." / "Right here." | "Decime, che." / "Acá estoy." |
| move | "Next stop." / "Off we go. Gently." | "Próxima parada." / "Vamos, despacito." |
| attack | "This one gets off here." / "Bedtime, friend." | "Este se baja acá." / "A dormir, amigo." |
| work | "Leave it to me." / "I'll sort it out." | "Dejámelo a mí." / "Ya lo arreglo." |
| done | "There. All mended." / "Done. On we go." | "Ya está. Arreglado." / "Listo. Sigamos." |
| refuse | "I can't get through there." / "That can't be done." / "No tram runs that way." | "Por ahí no paso." / "Eso no se puede, che." / "Ese recorrido no existe." |
| spotted | "Look out, they've seen us!" / "Blast, they've spotted me!" | "¡Guarda, nos vieron!" / "¡La pucha, me junaron!" |
| hurt | "Ah! I'm hit!" / "Not dead yet." | "¡Uy, me dieron!" / "Aguanto, aguanto." |

### Lechuza (night lineman: cord (bind), the lamp board key, the ladder) — the shipped lines

| Kind | English | Spanish |
| --- | --- | --- |
| select | "I'm listening, lad." / "Now what?" | "Te escucho, pibe." / "¿Y ahora qué?" |
| move | "Coming, coming. No hurry." / "Through the dark, as always." | "Voy, voy. Sin apuro." / "Por lo oscuro, como siempre." |
| attack | "Two turns of cord and that's him." / "Hold still now. I'll tie you." | "Dos vueltas de cable y listo." / "Quieto ahí, que te ato." |
| work | "Easy as changing a fuse." / "I know this by heart." | "Esto es como cambiar un fusible." / "Esto lo conozco de memoria." |
| done | "Lights out." / "Neat and tidy." | "Se cortó la luz." / "Hecho. Limpito." |
| refuse | "At my age? Not a chance." / "There's no way through there." / "That won't work." | "¿A mi edad? Minga." / "Por ahí no hay paso." / "Eso no anda, che." |
| spotted | "Look out, they've seen me!" / "Oh no, the law!" | "¡Araca, me vieron!" / "¡Uy, la cana!" |
| hurt | "Oh, my old bones!" / "They got me, damn it!" | "¡Ay, mis huesos!" / "¡Me dieron, carajo!" |

### Benteveo (newspaper seller: bundles of the late edition, the crowd; never strikes) — the shipped lines

| Kind | English | Spanish |
| --- | --- | --- |
| select | "Here, boss!" / "What's the game, then?" | "¡Presente, jefe!" / "¿Qué hacemos, che?" |
| move | "Come on, come on!" / "Off I go, quick as you like!" | "¡Vamo, vamo!" / "¡Ahí voy, rapidito!" |
| work | "Late edition! Read all about it!" / "I could do that blindfold!" | "¡Diario, diario! ¡La Sexta!" / "¡Eso lo hago con los ojos cerrados!" |
| refuse | "Me? Not a chance!" / "Not on your life, boss!" / "Can't get through there." | "¿Yo? ¡Minga!" / "¡Ni loco, jefe!" / "Por ahí no se pasa, che." |
| spotted | "Coppers! Leg it!" / "Uh-oh, they've seen me!" | "¡Cana, cana! ¡Rajemos!" / "¡Uy, me junaron!" |
| hurt | "Ow! Rotten luck!" / "Ow, ow, they got me!" | "¡Ay! ¡Qué yeta!" / "¡Ay, ay, me dieron!" |

### Biguá (boatman: knife, the boat) — the shipped lines

| Kind | English | Spanish |
| --- | --- | --- |
| select | "I'm here." / "What d'you need?" | "Acá ando." / "¿Qué precisás?" |
| move | "Slow, like the tide." / "Let's go. No noise." | "Despacito, como la marea." / "Vamos, sin ruido." |
| attack | "I'll do it. Quiet." / "The current takes him." | "Lo hago yo, callado." / "Se lo lleva la corriente." |
| work | "I'll see to it." / "Steady. Like rowing." | "Yo me encargo." / "Con calma, como remar." |
| done | "That's it, brother." / "Done. On to the far bank." | "Listo, hermano." / "Hecho. A la otra orilla." |
| refuse | "Not that way." / "Not even the river gets through there." / "Can't be done, brother." | "Por ahí, no." / "Ni el río pasa por ahí." / "Imposible, hermano." |
| spotted | "I'm seen. Quick." / "Watch it, the Guardia!" | "Me vieron. Rápido." / "¡Ojo, la Guardia!" |
| hurt | "I'm hit. I'll hold." / "Still going. Still going." | "Me dieron. Aguanto." / "Sigo, sigo." |
