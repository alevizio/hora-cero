# Launch images and videos

Dev tools (not part of the game) that made Hora Cero's launch posts and trailers out of the real game. Nothing they
render is kept in the repository (it is large); they need Python 3 with NumPy, SciPy and Pillow, ffmpeg, and xvfb-run
to render Godot off-screen. Set `GODOT` to the Godot 4.7 binary.

- `horacero/stills.sh <dir>` renders the launch stills from the real game, each at its format's own size
  (`tools/trailer/horacero_director.gd`'s "probe" shot, one Godot run per setup: carry, rush, rescue, play, aim,
  buried, ria_crossing...; each run with an empty HOME and, on a Mac, no network), and `horacero/make_social.py
  <stills dir> <out dir>` lays the light type over them (the game's name on the first and last and on the cards, a
  short line in Spanish on a few): the Instagram carousel (7 × 1080×1350), two stories (1080×1920), three pictures for
  X and link previews (1600×900), a square post (1080×1080), a LinkedIn / link card (1200×627) and the key art
  (3840×2160, no HUD). The probe takes PROBE_SHOOT (Juan Salvo holds his aim at a cascarudo), PROBE_SELECT,
  PROBE_CANVAS (a still bigger than the screen) and AIM_JUAN / AIM_BEAST / AIM_FACE; the director's header and
  `shot_probe()` say how.
- The trailers are `tools/trailer/horacero_*`: `horacero_takes.sh` renders every take of `horacero_takes.txt` (one
  `horacero_run.sh` run each, recorded by Godot's movie writer: hours on a CPU-only machine), and
  `horacero_finish.sh <wide takes> <upright takes> <out dir>` writes the score (`horacero_music.py`, synthesised from
  scratch), cuts both edits (`compose_horacero.py`: 16:9 and 9:16) and a light copy.
- `tools/trailer/horacero_playtest.gd` plays both levels through from the launch screen as a player would, taking
  pictures on the way and flagging anyone stuck or inside a wall (its header says how to run it).

- The cinematic Hora Cero trailer (75 s 16:9, its English-subtitled copy, a 30 s 9:16 cut, the thumbnail) is
  `tools/trailer/hc2_*`: `hc2_director.gd` films the takes from the game's own scene (lens moves, depth of field,
  near snow, motion blur; the gameplay inserts with the real HUD), piped straight into ffmpeg by `hc2_run.sh <take>
  <w> <h> <out.mkv>`; `hc2_compose.py <wide|upright> <takes> <narration> <out>` cuts them to the narration, grades,
  titles, subtitles and mixes (to -14 LUFS, -1 dBTP) with the score of `hc2_music.py` (original, synthesised) and the
  game's own sound files; `hc2_thumbnail.py` makes the thumbnail from the "thumb" take. The narrator is
  `tools/voice_trailer.py` (a designed voice, Qwen3-TTS VoiceDesign + Base; provenance in `tools/voices/trailer/`).

- The gameplay demonstration is `tools/trailer/horacero_demo.sh` + `horacero_demo.gd` (the real game played to a win
  by the scripted plans, recorded with its HUD and its own sound by Godot's movie writer, the camera kept as a player
  keeps it, the waits run x2/x3; `timeline` mode prints what happens when, `PLAY_FROM` picks a second recording up at
  the same instant) and `horacero_demo_edit.py` (the cards, the chapter lower-thirds, the x2/x3 tags, the sound to -16
  LUFS, the 1080p, 720p and WhatsApp films).
