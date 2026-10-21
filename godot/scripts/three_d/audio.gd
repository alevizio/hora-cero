extends Node
## All sound of the 3D game: ambience, movement, actions, guns, awareness and alarm, results and UI.
## world.gd builds this node, feeds it every simulation event (on_sim_event) and calls update() each frame;
## the HUD may call play_ui(). Every sound is one of the synthesised files in res://assets/audio
## (tools/gen_audio.py). There are no audio buses beyond Master, so all gain staging is per player:
##   volume = MASTER_DB + category + cue gain (+ distance, zoom and pause ducking for sounds in the world).
## The files all have the same loudness (the two loud guns excepted), so the cue gains below are the mix.
## Sounds in the world are placed by hand: quieter beyond the edge of the screen, panned by screen x.
## Nothing here touches the simulation; state is read fresh every frame (actor dictionaries are never kept).

const MASTER_DB: float = -3.0
const AMBIENCE_DB: float = -13.0
const SFX_DB: float = 2.0
const ALARM_DB: float = 0.0
const UI_DB: float = 0.0
## Everything off (loops stopped, events ignored) while false.
var enabled: bool = true: set = set_enabled
## The operatives' voices (Settings); the rest of the sound plays on without them.
var voices_on: bool = true
var sim: RefCounted

const DIR: String = "res://assets/audio/"
## Loop files carry this many wrap-around samples before and after the loop (see tools/audio_synth.py).
const LOOP_PAD: int = 64
const POOL_SIZE: int = 12
const FLAT_SIZE: int = 4
const LATER_SIZE: int = 16
## A safety net on the Master bus for the rare pile-up (three rifles and the siren); removed again on exit.
const LIMIT_MASTER: bool = true
const SETTLE_STEPS: int = 100
## How far a sound carries past the edge of the screen: [reach in metres, level at and beyond that reach].
const NEAR: int = 0
const MID: int = 1
const FAR: int = 2
const REACH_M: Array[float] = [7.0, 16.0, 34.0]
const FAR_DB: Array[float] = [-36.0, -22.0, -9.0]
## Share of the signal moved to one side for a sound two half-screens off centre (0.5 would be hard left/right).
const PAN_WIDTH: float = 0.35
const PAUSE_DUCK_DB: float = -8.0
const ZOOM_DUCK_DB: float = -5.0
const STRIDE_WALK: float = 1.15
const STRIDE_SNEAK: float = 0.9
const STRIDE_CARRY: float = 0.8
const STRIDE_GUARD: float = 0.75
## One pull on the rope hand over hand.
const STRIDE_ROPE: float = 0.7
const GUARD_STEP_RADIUS: float = 6.0
## A cascarudo sets one tripod of its legs down every STRIDE_CREATURE metres (half a cycle of its gait, creature_body.gd:
## a stride of 0.3 of its 4 m length), heard further off than a man's boots. One rasps again after RASP_AGAIN seconds
## at the soonest.
const STRIDE_CREATURE: float = 0.6
const CREATURE_STEP_RADIUS: float = 14.0
const RASP_AGAIN: float = 3.0
const TENSION_FROM: float = 0.3
const DOWN: Array[String] = ["dead", "bound", "stunned", "held"]

## cue: [files, gain dB, carry (NEAR / MID / FAR), random pitch spread]
const CUES: Dictionary = {
	&"step": [["foot_step_1", "foot_step_2", "foot_step_3", "foot_step_4"], -5.0, NEAR, 0.05],
	&"gravel": [["foot_gravel_1", "foot_gravel_2", "foot_gravel_3"], -12.0, NEAR, 0.07],
	# Boots in snow.
	&"snow": [["foot_snow_1", "foot_snow_2", "foot_snow_3"], -6.0, NEAR, 0.06],
	&"scuffle": [["act_scuffle_1", "act_scuffle_2"], -5.0, NEAR, 0.05],
	&"rope": [["act_rope_creak"], -5.0, NEAR, 0.06],
	&"cinch": [["act_rope_cinch"], -2.0, MID, 0.03],
	&"knife": [["act_knife"], 0.0, MID, 0.03],
	&"body_fall": [["act_body_fall"], -2.0, MID, 0.04],
	&"heave": [["act_heave"], -5.0, NEAR, 0.04],
	&"body_drop": [["act_body_drop"], -3.0, MID, 0.04],
	&"bush": [["act_bush_rustle"], -4.0, NEAR, 0.05],
	&"throw": [["act_pebble_throw"], -8.0, NEAR, 0.05],
	&"pebble": [["act_pebble_land"], -2.0, MID, 0.04],
	&"pick": [["act_pick_1", "act_pick_2", "act_pick_3"], -9.0, NEAR, 0.05],
	&"unlock": [["act_unlock"], -1.0, MID, 0.0],
	&"snip": [["act_snip_1", "act_snip_2"], -7.0, NEAR, 0.04],
	&"fence": [["act_fence_twang"], -1.0, MID, 0.0],
	&"peg": [["act_peg_tap_1", "act_peg_tap_2"], -6.0, NEAR, 0.02],
	&"tink": [["act_wire_tink"], -9.0, NEAR, 0.03],
	&"trap": [["act_trap_sprung"], 0.0, MID, 0.0],
	&"tool": [["act_tool_1", "act_tool_2"], -8.0, NEAR, 0.04],
	&"generator_die": [["act_generator_die"], 0.0, FAR, 0.0],
	&"rescue": [["act_rescue"], -5.0, NEAR, 0.0],
	&"boat": [["act_boat_knock"], -1.0, MID, 0.0],
	&"match": [["act_match"], -3.0, NEAR, 0.04],
	&"cosh": [["act_cosh"], -2.0, NEAR, 0.05],
	&"bottle": [["act_bottle_smash"], 0.0, MID, 0.05],
	&"clank": [["amb_clank_1", "amb_clank_2"], 0.0, FAR, 0.06],
	&"pistol": [["gun_pistol"], -3.0, MID, 0.02],
	&"revolver": [["gun_revolver"], -3.0, FAR, 0.015],
	&"rifle": [["gun_rifle"], -5.0, FAR, 0.03],
	&"bolt": [["gun_rifle_bolt"], -6.0, NEAR, 0.03],
	&"hit": [["gun_hit"], 0.0, MID, 0.05],
	&"ricochet": [["gun_ricochet"], -3.0, MID, 0.08],
	&"miss": [["gun_miss"], -4.0, MID, 0.06],
	&"bark": [["alert_bark_1", "alert_bark_2"], -1.0, MID, 0.0],
	&"query": [["alert_query"], -5.0, MID, 0.0],
	&"aim": [["alert_aim"], -4.0, MID, 0.04],
	&"reinforcements": [["alert_reinforcements"], -1.0, FAR, 0.0],
	&"bell": [["alarm_bell"], 0.0, FAR, 0.0],
	&"creak": [["amb_creak_1", "amb_creak_2"], -2.0, MID, 0.08],
	# The cascarudos (the Plaza de Mayo): a tripod of its legs set down, its stridulation (sensing someone, going for
	# him, hit), the long rattle of one coming into the square, a bullet on its shell, its strike, its death.
	&"claws": [["cascarudo_step_1", "cascarudo_step_2", "cascarudo_step_3"], -5.0, MID, 0.05],
	&"rasp": [["cascarudo_rasp_1", "cascarudo_rasp_2"], -2.0, MID, 0.03],
	&"rattle": [["cascarudo_rattle"], 0.0, FAR, 0.03],
	&"call": [["cascarudo_call_1", "cascarudo_call_2"], 3.0, FAR, 0.03],
	&"shell": [["cascarudo_shell"], 0.0, MID, 0.04],
	&"lunge": [["cascarudo_lunge"], -1.0, MID, 0.03],
	&"overturn": [["cascarudo_overturn"], 0.0, MID, 0.0],
	# Not in the world (no position, never ducked): stingers, results, UI.
	&"hurt": [["gun_hurt"], 2.0, 0, 0.0],
	&"spotted": [["alert_spotted"], 2.0, 0, 0.0],
	&"body_found": [["alert_body"], 2.0, 0, 0.0],
	&"objective": [["res_objective"], -1.0, 0, 0.0],
	&"checkpoint": [["res_checkpoint"], -3.0, 0, 0.0],
	&"page": [["ui_page"], -5.0, 0, 0.0],
	&"win": [["res_win"], 2.0, 0, 0.0],
	&"lose": [["res_lose"], 2.0, 0, 0.0],
	&"ui_tap": [["ui_tap"], -5.0, 0, 0.0],
	&"ui_arm": [["ui_arm"], -2.0, 0, 0.0],
	&"ui_deny": [["ui_deny"], -2.0, 0, 0.0],
	&"ui_confirm": [["ui_confirm"], -2.0, 0, 0.0],
}
## Loops: file and gain at full level. A level names its own water and hum loops (data "ambience": "water", "hum");
## a loop whose file is missing stays silent.
const LOOP_SEA: String = ""
const LOOP_WIND: String = "amb_wind"
const LOOP_HUM: String = ""
const LOOP_SIREN: String = "alarm_siren"
const LOOP_TENSION: String = "tension_loop"
## The sea as a whole (turned down 4 dB on 7 Oct 2026), then how much quieter it is away from the shore.
const SEA_DB: float = -4.0
const SEA_INLAND_DB: float = -9.0
const WIND_DB: float = -3.0
const HUM_DB: float = -5.0
const SIREN_DB: float = 0.0
const TENSION_DB: float = -3.0
## Small sounds during the timed part of an action: action -> [[seconds into it, cue], ...].
## What ends the action (the clunk, the twang, the thump) comes from its simulation event.
const ACTION_TICKS: Dictionary = {
	"takedown": [[0.0, &"scuffle"], [0.75, &"rope"], [1.2, &"scuffle"], [1.6, &"rope"]],
	"pickup": [[0.0, &"heave"]],
	"trap": [[0.25, &"peg"], [0.65, &"peg"], [1.05, &"peg"]],
	"trap_pickup": [[0.1, &"scuffle"], [0.6, &"tink"]],
	"cut": [[0.5, &"snip"], [1.4, &"snip"], [2.3, &"snip"]],
	"sabotage": [[0.3, &"tool"], [1.1, &"tool"], [1.9, &"tool"], [2.5, &"tool"]],
	"unlock": [[0.15, &"pick"], [0.5, &"pick"], [0.8, &"pick"], [1.1, &"pick"]],
	"rescue": [[0.05, &"scuffle"]],
}
const NO_TICKS: Array = []
const SOFT_ACTIONS: Array[String] = ["trap_pickup", "rescue"]
const RESULT_CUES: Array[StringName] = [&"win", &"lose"]
const UI_KINDS: Dictionary = {"tap": &"ui_tap", "arm": &"ui_arm", "deny": &"ui_deny", "confirm": &"ui_confirm"}

## Operative voice lines: any file VOICE_DIR/<language>/<operative>_<kind>_<n>.wav that exists is used
## (n = 1..VOICE_MAX); a language without its own recording of a line falls back to English, and with nothing
## recorded this part of the module does nothing at all. The informant speaks too (his id, kinds freed, spotted,
## hurt). docs/VOICE_LINES.md lists the lines; tools/voice_prep.py trims and levels the takes.
const VOICE_DIR: String = "res://assets/audio/voice/"
const VOICE_KINDS: Array[String] = ["select", "move", "attack", "work", "done", "refuse", "spotted", "hurt", "freed"]
## The language of the lines (a folder under VOICE_DIR); set before build(), or call load_voices() to switch.
var voice_lang: String = "en"
const VOICE_MAX: int = 8
const VOICE_DB: float = 1.0
## Silence kept after a line before the next may start, and how soon the same operative may answer the same way.
const VOICE_GAP: float = 0.4
const VOICE_REPEAT: float = 4.0
## These cut in over a line already playing.
const VOICE_URGENT: Array[String] = ["spotted", "hurt"]
## Order type -> kind of answer; any other order is "work".
const ORDER_VOICE: Dictionary = {"move": "move", "extract": "move", "drop": "move", "takedown": "attack", "shoot": "attack"}
## Event type -> seconds until the operative who did it says so.
const DONE_VOICE: Dictionary = {"takedown": 0.9, "unlock": 0.7, "rescued": 0.7, "fence_cut": 0.6, "radio_cut": 1.4, "trap_set": 0.5, "planted": 0.8, "rigged": 0.8, "calmed": 0.6}
## "<operative>/<kind>" -> streams. Filled by build(); tests may fill it themselves.
var voice_bank: Dictionary = {}
## The last lines started, oldest first ("wren/select#0"), for tests and debugging.
var voice_log: Array[String] = []

## Dev only (tools/audio_trace.gd): with tracing on, every sound started and the loop levels are logged here.
var tracing: bool = false
var trace: Array[Dictionary] = []

var _built: bool = false
var _host: Node
var _rng := RandomNumberGenerator.new()
var _limiter: AudioEffect
var _listener: AudioListener2D
var _streams: Dictionary = {}
var _names: Dictionary = {}
var _turn: Dictionary = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_db: PackedFloat32Array = []
var _pool_serial: PackedInt32Array = []
var _pool_fade: PackedFloat32Array = []
## When each voice is done, on our own clock: the engine's `playing` flag lags a frame and never clears
## when nothing pumps frames (scripted tests), so the pool keeps its own books.
var _pool_until: PackedFloat64Array = []
var _flat: Array[AudioStreamPlayer] = []
var _flat_serial: PackedInt32Array = []
var _flat_until: PackedFloat64Array = []
var _flat_cue: Array[StringName] = []
var _serial: int = 0
var _later_time: PackedFloat32Array = []
var _later_cue: Array[StringName] = []
var _later_at: PackedVector2Array = []
var _later_db: PackedFloat32Array = []
var _later_pitch: PackedFloat32Array = []
var _later_flat: PackedByteArray = []
var _sea: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _clock: float = 0.0
var _trace_clock: float = 0.0
var _focus := Vector3(19.5, 0.0, 13.0)
var _zoom: float = 29.0
var _aspect: float = 16.0 / 9.0
var _right := Vector3.RIGHT
var _up := Vector3(0.0, 0.62, -0.79)
var _zoom_db: float = 0.0
var _loc_db: float = 0.0
var _loc_pan: float = 0.0
var _duck: float = 0.0
var _ambience_duck: float = 0.0
var _ambience_in: float = 0.0
var _sea_db: float = SEA_INLAND_DB
var _hum_level: float = 0.0
var _hum_near: float = 0.0
var _siren_speed: float = 0.0
var _siren_clock: float = 0.0
var _tension_level: float = 0.0
var _bell_timer: float = 0.0
var _bell_second: bool = false
var _hush: float = 0.0
var _last_time: float = 0.0
var _last_phase: String = ""
var _last_paused: bool = true
var _last_selected: String = ""
var _ui_recent: float = 1.0
var _stinger_wait: float = 0.0
var _bark_wait: float = 0.0
var _aim_wait: float = 0.0
var _aiming: int = 0
var _step_id: String = ""
var _step_pos := Vector2.ZERO
var _step_travel: float = 0.0
var _step_rest: float = 1.0
var _guard_id: String = ""
var _guard_pos := Vector2.ZERO
var _guard_travel: float = 0.0
var _beast_id: String = ""
var _beast_pos := Vector2.ZERO
var _beast_travel: float = 0.0
## Each cascarudo's state as last seen, and when it last rasped (by id).
var _beast_state: Dictionary = {}
var _beast_rasp: Dictionary = {}
var _act_name: PackedStringArray = ["", "", "", ""]
var _act_time: PackedFloat64Array = [-1.0, -1.0, -1.0, -1.0]
var _wildlife_timer: float = 6.0
## Extra level (dB) on the world's ambience, set by a scripted scene (a closing scene may dip it to near silence).
var scene_db: float = 0.0
## The mission's own ambience (data "ambience"): water and hum loops, where the water is, what calls out
## now and then. Missing: the breakwater's sea, wind, generator, gulls and creaks.
var _ambience: Dictionary = {}
var _radio_cue: StringName = &"generator_die"
var _voice: AudioStreamPlayer
var _voice_until: float = 0.0
var _voice_turn: Dictionary = {}
var _voice_last: Dictionary = {}
var _voice_orders: Dictionary = {}
var _voice_selected: String = ""
var _voice_synced: bool = false
var _voice_due: float = -1.0
var _voice_due_who: String = ""
var _voice_due_kind: String = "done"
var _radio := Vector2(840.0, 134.0)
## Where the hum comes from (ambience "humAt", metres; else the radio), and whether cutting the radio silences
## it and the siren (ambience "radioIsPower", true unless a mission says its radio is only a telephone line).
var _hum_spots: Array[Vector2] = []
var _radio_is_power: bool = true
var _door := Vector2(552.0, 248.0)

# ---------------------------------------------------------------- setup

## Creates every player and loads every stream once; nothing is allocated after this.
func build() -> void:
	if _built: return
	_built = true
	_host = get_parent().get_parent() if get_parent() != null else null
	_rng.seed = 0x5AB07E
	for cue: StringName in CUES:
		var list: Array[AudioStream] = []
		var names: PackedStringArray = []
		for file: String in CUES[cue][0]:
			var stream: AudioStream = _load(file)
			if stream == null: continue
			list.append(stream)
			names.append(file)
		_streams[cue] = list
		_names[cue] = names
		_turn[cue] = 0
	# Sounds in the world: 2D players around our own listener, so pan is ours to set (x = pan * screen width).
	_listener = AudioListener2D.new()
	_listener.name = "Listener"
	add_child(_listener)
	_listener.make_current()
	var strength: float = float(ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5))
	for i: int in range(POOL_SIZE):
		var voice := AudioStreamPlayer2D.new()
		voice.name = "World%d" % i
		voice.max_distance = 1000000.0
		voice.attenuation = 0.00001
		voice.area_mask = 0
		voice.panning_strength = PAN_WIDTH / maxf(0.5 * strength, 0.001)
		add_child(voice)
		_pool.append(voice)
	_pool_db.resize(POOL_SIZE)
	_pool_serial.resize(POOL_SIZE)
	_pool_fade.resize(POOL_SIZE)
	_pool_until.resize(POOL_SIZE)
	for i: int in range(FLAT_SIZE):
		var flat := AudioStreamPlayer.new()
		flat.name = "Flat%d" % i
		add_child(flat)
		_flat.append(flat)
	_flat_serial.resize(FLAT_SIZE)
	_flat_until.resize(FLAT_SIZE)
	_flat_cue.resize(FLAT_SIZE)
	_later_time.resize(LATER_SIZE)
	_later_cue.resize(LATER_SIZE)
	_later_at.resize(LATER_SIZE)
	_later_db.resize(LATER_SIZE)
	_later_pitch.resize(LATER_SIZE)
	_later_flat.resize(LATER_SIZE)
	for i: int in range(LATER_SIZE): _later_time[i] = -1.0
	if sim != null:
		_ambience = sim.data.get("ambience", {})
		var radio_cue := StringName(str(sim.data.get("radio", {}).get("sound", "generator_die")))
		if CUES.has(radio_cue): _radio_cue = radio_cue
	_sea = _loop_player(str(_ambience.get("water", LOOP_SEA)))
	_wind = _loop_player(LOOP_WIND)
	_hum = _loop_player(str(_ambience.get("hum", LOOP_HUM)))
	_siren = _loop_player(LOOP_SIREN)
	_tension = _loop_player(LOOP_TENSION)
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	load_voices(voice_lang)
	if LIMIT_MASTER and not _master_has_limiter():
		_limiter = AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(0, _limiter)
	if sim != null:
		# Fixed places of the mission (the data is read-only): the generator and the barracks door.
		var radio: Dictionary = sim.data.get("radio", {})
		_radio = Vector2(float(radio.get("x", _radio.x)), float(radio.get("y", _radio.y)))
		_radio_is_power = bool(_ambience.get("radioIsPower", true))
		_hum_spots.clear()
		for spot: Array in _ambience.get("humAt", []): _hum_spots.append(Vector2(float(spot[0]), float(spot[1])) * 32.0)
		if _hum_spots.is_empty(): _hum_spots.append(_radio)
		var spawn: Array = sim.data.get("reinforcements", {}).get("spawn", [])
		if not spawn.is_empty(): _door = Vector2(float(spawn[0][0]), float(spawn[0][1]))
		_last_phase = sim.phase
		_last_paused = sim.paused
		_last_selected = sim.selected_id
		_last_time = sim.time
		_hum_level = 0.0 if sim.radio_cut and _radio_is_power else 1.0
	set_enabled(enabled)

func _exit_tree() -> void:
	if _limiter != null:
		for i: int in range(AudioServer.get_bus_effect_count(0)):
			if AudioServer.get_bus_effect(0, i) == _limiter:
				AudioServer.remove_bus_effect(0, i)
				break
		_limiter = null
	if not _built: return
	for voice: AudioStreamPlayer2D in _pool: voice.stop()
	for flat: AudioStreamPlayer in _flat: flat.stop()
	for player: AudioStreamPlayer in [_sea, _wind, _hum, _siren, _tension]: player.stop()
	if _voice != null: _voice.stop()
	# Headless runs (the tests) quit one frame after freeing the scene. The dummy driver mixes only about
	# ten times a second, and a stopped voice is let go of in a mix step: wait for one, or the engine
	# reports the streams as still in use at exit. Never taken with a real audio driver.
	if AudioServer.get_driver_name() != "Dummy": return
	var before: float = AudioServer.get_time_since_last_mix()
	for i: int in range(SETTLE_STEPS):
		OS.delay_msec(4)
		var since: float = AudioServer.get_time_since_last_mix()
		if since < before: break
		before = since
	OS.delay_msec(12)

func _master_has_limiter() -> bool:
	for i: int in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter: return true
	return false

func _load(file: String) -> AudioStream:
	var path: String = DIR + file + ".wav"
	if not ResourceLoader.exists(path): return null
	return load(path) as AudioStream

## Loop points are set here, not in the .import, so a re-import cannot lose them.
func _loop_player(file: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = file.to_pascal_case() if file != "" else "SilentLoop"
	var stream := _load(file) as AudioStreamWAV
	if stream != null:
		var frames: int = roundi(stream.get_length() * stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = LOOP_PAD
		stream.loop_end = frames - LOOP_PAD
		player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player

func set_enabled(value: bool) -> void:
	enabled = value
	if not _built: return
	_ambience_in = 0.0
	if enabled: return  # update() fades the ambience in
	for voice: AudioStreamPlayer2D in _pool: voice.stop()
	for flat: AudioStreamPlayer in _flat: flat.stop()
	for player: AudioStreamPlayer in [_sea, _wind, _hum, _siren, _tension]: player.stop()
	_voice.stop()
	_voice_until = 0.0
	_voice_due = -1.0
	_voice_synced = false
	for i: int in range(LATER_SIZE): _later_time[i] = -1.0
	_pool_until.fill(0.0)
	_flat_until.fill(0.0)

# ---------------------------------------------------------------- public: UI, events, per-frame update

## For the HUD's buttons: "tap", "arm" (a weapon or tool armed), "deny", "confirm"; any other name is a tap.
## Plays in any phase, paused or not.
func play_ui(kind: String) -> void:
	if not enabled or not _built or kind == "": return
	_ui_recent = 0.0
	_play_flat(UI_KINDS.get(kind, &"ui_tap"), UI_DB)

## One call per simulation event (GAMEPLAY_API.md section 11). Unknown types are ignored.
func on_sim_event(event: Dictionary) -> void:
	if not enabled or not _built or sim == null: return
	var by: Vector2 = _whereabouts(str(event.get("by", "")))
	var at := Vector2(float(event.get("x", by.x)), float(event.get("y", by.y)))
	var kind: String = str(event.get("type", ""))
	if kind == "rescued" and bool(sim.has_prisoner) and voice_bank.has("%s/freed" % str(sim.prisoner.get("id", ""))):
		# the informant has his own word for being let out
		_voice_due = 0.8
		_voice_due_who = str(sim.prisoner.id)
		_voice_due_kind = "freed"
	elif DONE_VOICE.has(kind):
		_voice_due = float(DONE_VOICE[kind])
		_voice_due_who = str(event.get("by", ""))
		_voice_due_kind = "done"
	elif kind == "spotted": say(str(event.get("target", "")), "spotted")
	elif kind == "hurt": say(str(event.get("id", "")), "hurt")
	match kind:
		"checkpoint":
			if str(event.get("action", "")) == "load":
				_hush_world()
				_play_flat(&"page", UI_DB)
			else:
				_play_flat(&"checkpoint", UI_DB)
		"pebble":
			_play(&"throw", by)
			_later(0.3 if str(event.get("noise", "")) == "bottle" else 0.2, &"bottle" if str(event.get("noise", "")) == "bottle" else &"pebble", at)
		"heard":
			var guards: Array = event.get("guards", [])
			if not guards.is_empty(): _bark(&"query", str(guards[0]), 0.3)
		"takedown":
			var victim: Vector2 = _whereabouts(str(event.get("target", "")))
			if bool(event.get("lethal", false)):
				_play(&"knife", victim)
				_later(0.3, &"body_fall", victim)
			elif bool(event.get("stun", false)):
				_play(&"cosh", victim)
				_later(0.25, &"body_fall", victim)
			else:
				_play(&"cinch", victim)
		"shot":
			var target := Vector2(float(event.get("tx", at.x)), float(event.get("ty", at.y)))
			# the gun's own sound where the data names one (Juan Salvo's rifle: a rifle and its bolt, not a revolver)
			var gun: Variant = sim.unit_by_id(str(event.get("by", ""))).get("gun", {})
			var rifle: bool = gun is Dictionary and str((gun as Dictionary).get("sound", "")) == "rifle"
			_play(&"rifle" if rifle else (&"revolver" if bool(event.get("loud", false)) else &"pistol"), at)
			if rifle: _later(0.6, &"bolt", at)
			var hit_id: String = str(event.get("hit_id", ""))
			if hit_id != "":
				# a cascarudo hit: the bullet on its shell, and it turns and makes off (nobody falls)
				var beast: bool = bool(sim.guard_by_id(hit_id).get("creature", false))
				_later(0.05, &"shell" if beast else &"hit", target)
				if not beast: _later(0.4, &"body_fall", target)
			else:
				_later(0.07, &"ricochet" if _serial % 2 == 0 else &"miss", target)
		"call":
			# Hornero's tram bell (a rescue's call with the noise "bell"): two strokes from the tram; a shout is a voice
			if str(event.get("noise", "")) == "bell":
				_play(&"bell", at, -2.0)
				_later(0.32, &"bell", at, -5.0, 0.985)
		"pickup":
			pass  # the heave is played as the lift starts (ACTION_TICKS)
		"took":
			# a rescue's gear taken: the rifle's bolt worked, the hood's strap pulled tight
			_play(&"bolt" if str(event.get("kind", "")) == "rifle" else &"cinch", by)
		"drop":
			_play(&"bush" if bool(event.get("hidden", false)) else &"body_drop", by)
		"trap_set":
			_play(&"tink", at)
		"trap_lifted":
			_play(&"tink", by, -3.0, 0.9)
		"trap_sprung":
			_play(&"trap", at)
			_later(0.25, &"body_fall", at)
		"woke":
			var sleeper: String = str(event.get("guard", ""))
			_play(&"scuffle", _whereabouts(sleeper), -2.0)
			_bark(&"query", sleeper, 0.35)
		"fence_cut":
			_play(&"fence", by)
		"radio_cut":
			_play(_radio_cue, _radio)
			_later(0.9, &"objective", Vector2.ZERO, 0.0, 1.0, true)
		"planted":
			_play(&"tink", at, 2.0, 0.8)
		"rigged":
			_play(&"cinch", at)
			_later(0.35, &"rope", at, -2.0, 0.9)
		"tracks":
			# a guard has found prints in the snow: a grunt of interest, the first time he picks the trail up
			if bool(event.get("first", false)): _bark(&"query", str(event.get("guard", "")), 0.2)
		"objective":
			_later(0.7, &"objective", Vector2.ZERO, 0.0, 1.0, true)
		"chat":
			_play(&"match", at)
		"unlock":
			_play(&"unlock", by)
			_later(0.5, &"objective", Vector2.ZERO, 0.0, 1.0, true)
		"rescued":
			_play(&"rescue", by)
			_later(0.45, &"objective", Vector2.ZERO, 0.0, 1.0, true)
		"escort":
			_play(&"scuffle", by, -3.0)
		"boarded":
			_play(&"boat", _whereabouts(str(event.get("id", "asset"))))
		"spotted":
			_stinger(&"spotted")
			_bark(&"bark", str(event.get("guard", "")), 0.08)
		"body_found":
			_stinger(&"body_found")
			_bark(&"bark", str(event.get("guard", "")), 0.25)
		"alarm_start":
			_siren_clock = 0.0
			_bell_timer = 0.3
			_bell_second = false
		"alarm_end":
			pass  # the siren winds down by itself: update() follows alarm.active, not this event
		"reinforcements":
			_play(&"reinforcements", at)
		"guard_shot":
			var mark := Vector2(float(event.get("tx", at.x)), float(event.get("ty", at.y)))
			_play(&"rifle", at)
			_later(0.5, &"bolt", at)
			if bool(event.get("hit", false)): _later(0.04, &"hit", mark)
			else: _later(0.06, &"ricochet" if _serial % 2 == 0 else &"miss", mark)
		"hurt":
			_play_flat(&"hurt", SFX_DB)
		"death":
			_later(0.15, &"body_fall", _whereabouts(str(event.get("id", ""))))
		"creature":
			# it announces itself as it comes in: the rattle from down the avenue, then its call, heard across the square
			_later(0.4, &"call", Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))), 0.0, _beast_pitch(str(event.get("id", ""))))
			# a cascarudo comes into the square (or back into it): its long rattle from the edge it comes in by
			_play(&"rattle", at, 0.0, _beast_pitch(str(event.get("id", ""))))
		"creature_hit":
			# the bullet on its shell is the shot's own: it rasps as it staggers and turns away
			_later(0.12, &"rasp", at, 2.0, _beast_pitch(str(event.get("id", ""))) * 1.12)
		"creature_dead":
			_later(0.2, &"overturn", at)
		"struck":
			# the claws come down where the one it reached stood, he falls, and it rears up and comes down again
			_play(&"lunge", at)
			_later(0.15, &"body_fall", at)
			_later(3.0, &"claws", _whereabouts(str(event.get("by", ""))), -2.0)
		"won":
			# A mission with a closing scene plays the motif when the scene is over (scene_over).
			if not sim.data.has("finale"): _later(0.4, &"win", Vector2.ZERO, 0.0, 1.0, true)
		"lost":
			_later(0.6, &"lose", Vector2.ZERO, 0.0, 1.0, true)

## Every frame from world.update_visuals: dt is real time, paused is the tactical pause (command mode).
func update(dt: float, paused: bool) -> void:
	if not enabled or not _built or sim == null: return
	_clock += dt
	var phase: String = sim.phase
	var live: bool = phase == "playing" and not paused
	var holding: bool = phase == "playing" and paused
	# A restart or a checkpoint load rewinds the world: whatever was sounding in it stops quickly.
	if float(sim.time) < _last_time - 0.001 or (phase == "briefing" and _last_phase != "briefing"): _hush_world()
	_last_time = sim.time
	_hush = maxf(0.0, _hush - dt)
	_ui_recent += dt
	_stinger_wait = maxf(0.0, _stinger_wait - dt)
	_bark_wait = maxf(0.0, _bark_wait - dt)
	_aim_wait = maxf(0.0, _aim_wait - dt)
	_read_view()
	_update_voice(dt, phase)
	_auto_ui(phase, paused)
	# Tactical pause: sounds already in the air ring out lower, ambience drops a little, nothing new starts.
	_duck = move_toward(_duck, PAUSE_DUCK_DB if holding else 0.0, dt * 80.0)
	_ambience_duck = move_toward(_ambience_duck, PAUSE_DUCK_DB * 0.5 if holding else 0.0, dt * 40.0)
	_update_pool(dt)
	_update_later(dt, holding)
	_update_ambience(dt)
	_update_alarm(dt, phase, live)
	_update_tension(dt, live)
	if live:
		_update_steps(dt)
		_update_actions()
		_update_guards(dt)
		_update_creatures(dt)
	if tracing: _trace_loops(dt)

## For scripted scenes (a closing scene): a cue at a point on the ground (metres), or one with no place at all.
func play_at(cue: String, metres: Vector3, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not _built or not CUES.has(StringName(cue)): return
	_play(StringName(cue), Vector2(metres.x, metres.z) * 32.0, gain_db, pitch)

func play_far(cue: String, gain_db: float = 0.0) -> void:
	if not enabled or not _built or not CUES.has(StringName(cue)): return
	_play_flat(StringName(cue), SFX_DB, gain_db)

## The scene is over (or skipped): the ambience comes back and the result motif the "won" event held back plays.
func scene_over(skipped: bool) -> void:
	scene_db = 0.0
	if not enabled or not _built: return
	if skipped: _hush_world()
	_later(0.3 if skipped else 0.1, &"win", Vector2.ZERO, 0.0, 1.0, true)

## Fills the voice bank for this mission's people in `lang`, line by line falling back to English, then to the
## old flat folder. Lines a test put in the bank by hand are replaced.
func load_voices(lang: String) -> void:
	voice_lang = lang
	if sim == null: return
	voice_bank.clear()
	var people: Array[String] = []
	for unit: Dictionary in sim.units: people.append(str(unit.id))
	if bool(sim.has_prisoner): people.append(str(sim.prisoner.get("id", "asset")))
	for who: String in people:
		for kind: String in VOICE_KINDS:
			var lines: Array[AudioStream] = []
			for folder: String in [lang + "/", "en/", ""]:
				for n: int in range(1, VOICE_MAX + 1):
					var path: String = "%s%s%s_%s_%d.wav" % [VOICE_DIR, folder, who, kind, n]
					if not ResourceLoader.exists(path): break
					var line := load(path) as AudioStream
					if line != null: lines.append(line)
				if not lines.is_empty(): break
			if not lines.is_empty(): voice_bank["%s/%s" % [who, kind]] = lines

## An order this operative was given was refused: he says so (the HUD shows why).
func refuse(unit_id: String) -> void:
	say(unit_id, "refuse")

## For tests and debugging: world voices sounding right now (never more than POOL_SIZE), and whether one
## of the loops ("amb_sea", "amb_wind", "amb_generator", "alarm_siren", "tension_loop") is running.
func active_voices() -> int:
	var count: int = 0
	for i: int in range(POOL_SIZE):
		if _pool_until[i] > _clock: count += 1
	return count

func loop_playing(file: String) -> bool:
	for player: AudioStreamPlayer in [_sea, _wind, _hum, _siren, _tension]:
		if player != null and player.stream != null and player.stream.resource_path.get_file().get_basename() == file: return player.playing
	return false

# ---------------------------------------------------------------- where things are

## Camera target, zoom and screen-right, read defensively: main.gd has target and zoom; fall back to the camera.
func _read_view() -> void:
	var target: Variant = _host.get("target") if _host != null else null
	var zoom: Variant = _host.get("zoom") if _host != null else null
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		_right = camera.global_transform.basis.x
		_up = camera.global_transform.basis.y
		if not (zoom is float): zoom = camera.size
	if target is Vector3:
		_focus = target
	elif not sim.selected().is_empty():
		_focus = Vector3(float(sim.selected().x) / 32.0, 0.0, float(sim.selected().y) / 32.0)
	if zoom is float: _zoom = clampf(zoom, 6.0, 80.0)
	if viewport != null:
		var size: Vector2 = viewport.get_visible_rect().size
		if size.y > 0.0: _aspect = size.x / size.y
	_zoom_db = ZOOM_DUCK_DB * clampf((_zoom - 16.0) / 40.0, 0.0, 1.0)

## Level and pan of a point on the ground (simulation units). Anything on screen is at full level; past the
## edge of the screen it falls off over the cue's reach (metres on the ground). Pan follows screen x.
func _locate(point: Vector2, carry: int) -> void:
	var dx: float = point.x / 32.0 - _focus.x
	var dz: float = point.y / 32.0 - _focus.z
	var across: float = dx * _right.x + dz * _right.z
	var over_x: float = maxf(0.0, absf(across) - _zoom * _aspect * 0.5)
	# Screen-up on the ground is foreshortened by the camera's pitch: convert the overshoot back to metres.
	var over_y: float = maxf(0.0, absf(dx * _up.x + dz * _up.z) - _zoom * 0.5) / maxf(0.3, sqrt(_up.x * _up.x + _up.z * _up.z))
	var beyond: float = clampf(sqrt(over_x * over_x + over_y * over_y) / REACH_M[carry], 0.0, 1.0)
	_loc_db = FAR_DB[carry] * beyond + _zoom_db
	_loc_pan = clampf(across / maxf(_zoom * _aspect, 1.0), -1.0, 1.0)

## Position of an operative, the informant or a guard by id; the camera target if nobody has that id.
func _whereabouts(id: String) -> Vector2:
	if id != "":
		var actor: Dictionary = sim.unit_by_id(id)
		if actor.is_empty() and str(sim.prisoner.get("id", "")) == id: actor = sim.prisoner
		if actor.is_empty(): actor = sim.guard_by_id(id)
		if not actor.is_empty(): return Vector2(float(actor.x), float(actor.y))
	return Vector2(_focus.x, _focus.z) * 32.0

# ---------------------------------------------------------------- one-shots

func _pick(cue: StringName) -> AudioStream:
	var list: Array = _streams.get(cue, NO_TICKS)
	if list.is_empty(): return null
	_turn[cue] = (int(_turn[cue]) + 1) % list.size()
	return list[_turn[cue]]

## A sound at a point in the world: through the pool, quieter off screen, panned by screen x, ducked in a pause.
func _play(cue: StringName, point: Vector2, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _pick(cue)
	if stream == null: return
	var entry: Array = CUES[cue]
	var carry: int = entry[2]
	_locate(point, carry)
	var slot: int = -1
	var oldest: int = 0
	for i: int in range(POOL_SIZE):
		if _pool_until[i] <= _clock:
			slot = i
			break
		if _pool_serial[i] < _pool_serial[oldest]: oldest = i
	if slot < 0:
		# Full: small sounds give way, anything else takes the oldest voice.
		if carry == NEAR: return
		slot = oldest
	_serial += 1
	var spread: float = entry[3]
	var voice: AudioStreamPlayer2D = _pool[slot]
	var viewport: Viewport = get_viewport()
	var width: float = viewport.get_visible_rect().size.x / maxf((viewport.global_canvas_transform * viewport.canvas_transform).get_scale().x, 0.001) if viewport != null else 1280.0
	# The louder side always plays at the full level, the other side drops: nothing gets louder by being panned.
	_pool_db[slot] = MASTER_DB + SFX_DB + float(entry[1]) + gain_db + _loc_db - linear_to_db(0.5 + absf(_loc_pan) * PAN_WIDTH)
	_pool_serial[slot] = _serial
	_pool_fade[slot] = 0.0
	voice.stream = stream
	voice.position = Vector2(_loc_pan * width, 0.0)
	voice.pitch_scale = pitch * (1.0 + _rng.randf_range(-spread, spread))
	_pool_until[slot] = _clock + stream.get_length() / voice.pitch_scale + 0.05
	voice.volume_db = _pool_db[slot] + _duck
	voice.play()
	if tracing: trace.append({"t": _clock, "file": _names[cue][_turn[cue]], "db": voice.volume_db + linear_to_db(0.5 + absf(_loc_pan) * PAN_WIDTH), "pan": _loc_pan, "pitch": voice.pitch_scale, "world": true})

## A sound with no place in the world (stingers, results, UI): never panned, never ducked.
func _play_flat(cue: StringName, category_db: float, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _pick(cue)
	if stream == null: return
	var slot: int = 0
	for i: int in range(FLAT_SIZE):
		if _flat_until[i] <= _clock:
			slot = i
			break
		if _flat_serial[i] < _flat_serial[slot]: slot = i
	_serial += 1
	_flat_serial[slot] = _serial
	_flat_until[slot] = _clock + stream.get_length() / pitch + 0.05
	_flat_cue[slot] = cue
	var flat: AudioStreamPlayer = _flat[slot]
	flat.stream = stream
	flat.pitch_scale = pitch
	flat.volume_db = MASTER_DB + category_db + float(CUES[cue][1]) + gain_db
	flat.play()
	if tracing: trace.append({"t": _clock, "file": _names[cue][_turn[cue]], "db": flat.volume_db, "pan": 0.0, "pitch": pitch, "world": false})

## The same a little later. World entries wait out a tactical pause; flat ones run on real time.
func _later(delay: float, cue: StringName, point: Vector2, gain_db: float = 0.0, pitch: float = 1.0, flat: bool = false) -> void:
	for i: int in range(LATER_SIZE):
		if _later_time[i] >= 0.0: continue
		_later_time[i] = delay
		_later_cue[i] = cue
		_later_at[i] = point
		_later_db[i] = gain_db
		_later_pitch[i] = pitch
		_later_flat[i] = 1 if flat else 0
		return

func _update_later(dt: float, holding: bool) -> void:
	for i: int in range(LATER_SIZE):
		if _later_time[i] < 0.0 or (holding and _later_flat[i] == 0): continue
		_later_time[i] -= dt
		if _later_time[i] > 0.0: continue
		_later_time[i] = -1.0
		if _later_flat[i] == 1: _play_flat(_later_cue[i], UI_DB, _later_db[i], _later_pitch[i])
		else: _play(_later_cue[i], _later_at[i], _later_db[i], _later_pitch[i])

func _update_pool(dt: float) -> void:
	for i: int in range(POOL_SIZE):
		if _pool_until[i] <= _clock: continue
		var voice: AudioStreamPlayer2D = _pool[i]
		if _pool_fade[i] > 0.0:
			_pool_fade[i] -= dt
			_pool_db[i] -= dt * 600.0
			if _pool_fade[i] <= 0.0:
				voice.stop()
				_pool_until[i] = 0.0
				continue
		voice.volume_db = _pool_db[i] + _duck

## The world has been rewound (checkpoint load, restart): fades out everything sounding in it over a tenth
## of a second, forgets what was queued and cuts a result motif still ringing from the mission before.
func _hush_world() -> void:
	_hush = 0.3
	_last_time = sim.time
	for i: int in range(POOL_SIZE):
		if _pool_until[i] > _clock and _pool_fade[i] <= 0.0: _pool_fade[i] = 0.1
	for i: int in range(LATER_SIZE):
		if _later_flat[i] == 0 or _later_cue[i] in RESULT_CUES: _later_time[i] = -1.0
	for i: int in range(FLAT_SIZE):
		if _flat_until[i] > _clock and _flat_cue[i] in RESULT_CUES:
			_flat[i].stop()
			_flat_until[i] = 0.0
	for i: int in range(_act_time.size()): _act_time[i] = -1.0
	_step_id = ""
	_guard_id = ""
	_beast_id = ""
	_beast_state.clear()
	_aiming = 0
	if _voice != null:
		_voice.stop()
		_voice_until = 0.0
		_voice_due = -1.0
		_voice_synced = false

func _stinger(cue: StringName) -> void:
	if _stinger_wait > 0.0: return
	_stinger_wait = 1.5
	_play_flat(cue, SFX_DB)

## A guard's wordless voice; each guard keeps his own pitch and one of the two voices.
func _bark(cue: StringName, guard_id: String, delay: float) -> void:
	if _bark_wait > 0.0 or guard_id == "": return
	_bark_wait = 0.25
	var voice: int = absi(hash(guard_id))
	if cue == &"bark": _turn[cue] = voice % 2
	_later(delay, cue, _whereabouts(guard_id), 0.0, 0.92 + 0.04 * float(voice % 5))

# ---------------------------------------------------------------- operative voice lines

## Has an operative say one of his recorded lines of that kind. Returns whether a line started: false when
## nothing is recorded for it, when a line is still playing (unless this one is urgent), or when he said the
## same kind of thing a moment ago. Lines are flat (not placed in the world) and are heard in command mode too.
func say(unit_id: String, kind: String) -> bool:
	if not enabled or not voices_on or not _built or _voice == null or _hush > 0.0: return false
	var key: String = "%s/%s" % [unit_id, kind]
	var lines: Array = voice_bank.get(key, [])
	if lines.is_empty(): return false
	if not kind in VOICE_URGENT and _clock < _voice_until + VOICE_GAP: return false
	if _clock - float(_voice_last.get(key, -1000.0)) < VOICE_REPEAT: return false
	var turn: int = (int(_voice_turn.get(key, -1)) + 1) % lines.size()
	var line: AudioStream = lines[turn]
	_voice_turn[key] = turn
	_voice_last[key] = _clock
	_voice_until = _clock + line.get_length()
	_voice.stream = line
	_voice.volume_db = MASTER_DB + VOICE_DB
	_voice.play()
	voice_log.append("%s#%d" % [key, turn])
	if voice_log.size() > 32: voice_log.remove_at(0)
	if tracing: trace.append({"t": _clock, "file": "voice/%s_%d" % [key.replace("/", "_"), turn + 1], "db": _voice.volume_db, "pan": 0.0, "pitch": 1.0, "world": false})
	return true

## Answers to what the player does, read from the state: a change of operative and every new order.
## After a restart or a checkpoint load the first look only takes stock, so restored orders are not answered.
func _update_voice(dt: float, phase: String) -> void:
	if voice_bank.is_empty(): return
	if phase != "playing" or _hush > 0.0:
		_voice_synced = false
		_voice_due = -1.0
		return
	var fresh: bool = not _voice_synced
	_voice_synced = true
	if _voice_due >= 0.0:
		_voice_due -= dt
		if _voice_due < 0.0: say(_voice_due_who, _voice_due_kind)
	if sim.selected_id != _voice_selected:
		_voice_selected = sim.selected_id
		if not fresh: say(_voice_selected, "select")
	for unit: Dictionary in sim.units:
		var order: Dictionary = unit.order
		var id: String = unit.id
		if _voice_orders.has(id) and is_same(_voice_orders[id], order): continue
		_voice_orders[id] = order
		if fresh or order.is_empty() or not bool(unit.alive): continue
		say(id, str(ORDER_VOICE.get(str(order.get("type", "")), "work")))

# ---------------------------------------------------------------- loops

## Level 0..1 (linear) of a looping player at base_db; stopped while silent. Callers ramp the level themselves.
func _drive(player: AudioStreamPlayer, level: float, base_db: float, pitch: float) -> void:
	if player.stream == null: return
	if level <= 0.002:
		if player.playing: player.stop()
		return
	player.volume_db = base_db + linear_to_db(level)
	player.pitch_scale = pitch
	if not player.playing: player.play()

func _update_ambience(dt: float) -> void:
	var shore: float = _shore()
	_sea_db = move_toward(_sea_db, lerpf(SEA_INLAND_DB, 0.0, shore), dt * 30.0)
	_ambience_in = move_toward(_ambience_in, 1.0, dt / 1.5)
	var scene: float = scene_db + _ambience_duck
	_drive(_sea, _ambience_in, MASTER_DB + AMBIENCE_DB + SEA_DB + _sea_db + scene, 1.0)
	_drive(_wind, _ambience_in, MASTER_DB + AMBIENCE_DB + WIND_DB + float(_ambience.get("windDb", 0.0)) + 2.0 * (1.0 - shore) + scene, 1.0)
	# The generator hums until it is sabotaged: follows the state, so a checkpoint load brings it back. An
	# electric hum (a transformer) stops at once, at its own pitch; an engine coughs and winds down.
	var running: bool = not (sim.radio_cut and _radio_is_power)
	var electric: bool = bool(_ambience.get("electric", false))
	_hum_level = move_toward(_hum_level, 1.0 if running else 0.0, dt / (0.12 if _hush > 0.0 or electric else 0.4 if running else 1.1))
	var away: float = INF
	for spot: Vector2 in _hum_spots: away = minf(away, Vector2(spot.x / 32.0 - _focus.x, spot.y / 32.0 - _focus.z).length())
	var near: float = 1.0 - clampf((away - _zoom * 0.35) / 10.0, 0.0, 1.0)
	_hum_near = move_toward(_hum_near, near * near, dt * 4.0)
	_drive(_hum, _hum_level * _hum_near * _ambience_in, MASTER_DB + AMBIENCE_DB + HUM_DB + _zoom_db + scene, 1.0 if electric else lerpf(0.5, 1.0, _hum_level))
	# Now and then a timber working or a far clank (the level's "calls"), on a seeded timer.
	_wildlife_timer -= dt
	if _wildlife_timer > 0.0: return
	var calls: Array = _ambience.get("calls", [])
	if calls.is_empty():
		_wildlife_timer = _rng.randf_range(9.0, 24.0)
		_play(&"creak", Vector2(127.0, 706.0) if _rng.randf() < 0.6 else Vector2(1232.0, 112.0), scene + AMBIENCE_DB - SFX_DB)
		return
	var every: Array = _ambience.get("every", [9.0, 24.0])
	_wildlife_timer = _rng.randf_range(float(every[0]), float(every[1]))
	# calls: [{"cue", "weight", "at": [[x, y], ...] (mission units), "db"}], picked by weight
	var total: float = 0.0
	for entry: Dictionary in calls: total += float(entry.get("weight", 1.0))
	var roll: float = _rng.randf() * total
	for entry: Dictionary in calls:
		roll -= float(entry.get("weight", 1.0))
		if roll > 0.0: continue
		var cue := StringName(str(entry.get("cue", "")))
		var spots: Array = entry.get("at", [])
		if CUES.has(cue) and not spots.is_empty():
			var spot: Array = spots[_rng.randi() % spots.size()]
			_play(cue, Vector2(float(spot[0]), float(spot[1])), scene + AMBIENCE_DB - SFX_DB + float(entry.get("db", 0.0)))
		break

## 1 by the water, 0 inland. The breakwater's sea is on the west side: full by the shore (x 5 m), inland from
## x 16 m. A mission can give its water as rectangles in metres (ambience "waterRects") and a falloff.
func _shore() -> float:
	var rects: Array = _ambience.get("waterRects", [])
	if rects.is_empty(): return clampf((16.0 - _focus.x) / 11.0, 0.0, 1.0)
	var nearest: float = INF
	for r: Array in rects:
		var dx: float = maxf(maxf(float(r[0]) - _focus.x, _focus.x - float(r[2])), 0.0)
		var dz: float = maxf(maxf(float(r[1]) - _focus.z, _focus.z - float(r[3])), 0.0)
		nearest = minf(nearest, sqrt(dx * dx + dz * dz))
	return clampf(1.0 - nearest / float(_ambience.get("falloff", 11.0)), 0.0, 1.0)

## The siren is a rotor: it spins up when the alarm starts, wails with the cranking, winds down when it ends.
## With the generator dead there is no siren: somebody rings a hand bell instead (weaker, and it says the
## sabotage worked). Both follow alarm.active, so they stop on a checkpoint load without an alarm_end event.
func _update_alarm(dt: float, phase: String, live: bool) -> void:
	var active: bool = phase == "playing" and bool(sim.alarm.active)
	var aim: float = 0.0
	var powered: bool = not (sim.radio_cut and _radio_is_power)
	if active and powered:
		_siren_clock += dt
		aim = 0.86 + 0.14 * cos(_siren_clock * TAU / 5.0)
	var rate: float = 8.0 if _hush > 0.0 else 0.8 if aim > _siren_speed else 0.32
	_siren_speed = move_toward(_siren_speed, aim, dt * rate)
	_drive(_siren, _siren_speed * _siren_speed, MASTER_DB + ALARM_DB + SIREN_DB + _duck, lerpf(0.3, 1.0, _siren_speed))
	if not (active and live and not powered): return
	_bell_timer -= dt
	if _bell_timer > 0.0: return
	_play(&"bell", _door, ALARM_DB - SFX_DB - (3.0 if _bell_second else 0.0), 0.985 if _bell_second else 1.0)
	_bell_timer = 0.8 if _bell_second else 0.27
	_bell_second = not _bell_second

## A soft tone that rises in level and pitch with the highest suspicion, from TENSION_FROM up. Silent in a
## pause and during an alarm (the siren has taken over by then).
func _update_tension(dt: float, live: bool) -> void:
	var want: float = 0.0
	if live and not bool(sim.alarm.active):
		want = smoothstep(TENSION_FROM, 1.0, float(sim.max_suspicion()))
	_tension_level = move_toward(_tension_level, want, dt / (0.12 if want > _tension_level else 0.5))
	_drive(_tension, _tension_level, MASTER_DB + SFX_DB + TENSION_DB, 1.0 + 0.19 * _tension_level)

# ---------------------------------------------------------------- things polled from the state

## Footsteps of the selected operative only, by distance travelled: softer crouched, heavier under a body.
func _update_steps(dt: float) -> void:
	var unit: Dictionary = sim.selected()
	if unit.is_empty(): return
	var here := Vector2(float(unit.x), float(unit.y))
	var moved: float = here.distance_to(_step_pos) / 32.0
	var same: bool = _step_id == sim.selected_id and moved < 2.0
	_step_id = sim.selected_id
	_step_pos = here
	if not same or moved < 0.0005:
		_step_rest += dt
		return
	var carrying: bool = str(unit.carrying) != ""
	var sneaking: bool = str(unit.stance) == "sneak" and not carrying
	var stride: float = STRIDE_CARRY if carrying else STRIDE_SNEAK if sneaking else STRIDE_WALK
	# The ground decides the sound: hand over hand on a rope, boots in snow or on stone.
	var cue: StringName = &"snow" if sim.on_snow(here) else &"step"
	if sim.climbing(unit):
		cue = &"rope"
		stride = STRIDE_ROPE
	# Setting off from a standstill: the first footfall comes early.
	if _step_rest > 0.25: _step_travel = stride * 0.6
	_step_rest = 0.0
	_step_travel += moved
	if _step_travel < stride: return
	_step_travel = fmod(_step_travel, stride)
	if cue == &"rope":
		_play(cue, here, -4.0)
		return
	_play(cue, here, 2.0 if carrying else -5.0 if sneaking else 0.0, 0.9 if carrying else 1.0)

## The small sounds of a job in progress (lock picks, snips, peg taps…), from each operative's action clock.
func _update_actions() -> void:
	var count: int = mini(sim.units.size(), _act_time.size())
	for i: int in range(count):
		var unit: Dictionary = sim.units[i]
		var action: String = unit.action
		if not bool(unit.acting) or action == "":
			_act_time[i] = -1.0
			continue
		var now: float = unit.action_time
		var before: float = _act_time[i] if _act_name[i] == action and _act_time[i] <= now else -1.0
		_act_name[i] = action
		_act_time[i] = now
		var key: String = action
		if action == "plant":
			var site: Dictionary = sim.charge_site(str(unit.order.get("target", "")))
			key = "plant:" + str(site.get("kind", "charge"))
		var ticks: Array = ACTION_TICKS.get(key, NO_TICKS)
		for n: int in range(ticks.size()):
			var at: float = ticks[n][0]
			# Nothing in the last moments: the event that ends the action brings its own sound.
			if at <= before or at > now or at > float(unit.action_total) - 0.2: continue
			var cue: StringName = ticks[n][1]
			_play(cue, Vector2(float(unit.x), float(unit.y)), -3.0 if action in SOFT_ACTIONS else 0.0, 1.0 + 0.04 * n if cue == &"peg" else 1.0)

## Guards: a click of a rifle coming up when one starts to aim at somebody, and a gravel crunch from the
## guard walking nearest the camera target (none for the others). The cascarudos have their own (_update_creatures).
func _update_guards(dt: float) -> void:
	var aiming: int = 0
	var aimer := Vector2.ZERO
	var nearest: float = GUARD_STEP_RADIUS * 32.0
	var walker_id: String = ""
	var walker := Vector2.ZERO
	var focus := Vector2(_focus.x, _focus.z) * 32.0
	for guard: Dictionary in sim.guards:
		if guard.state in DOWN or bool(guard.get("creature", false)): continue
		var here := Vector2(float(guard.x), float(guard.y))
		if str(guard.target_id) != "":
			aiming += 1
			if float(guard.aim_time) < 0.25: aimer = here
		var away: float = here.distance_to(focus)
		if away < nearest and float(guard.elevation) <= 0.0:
			nearest = away
			walker_id = guard.id
			walker = here
	if aiming > _aiming and _aim_wait <= 0.0 and aimer != Vector2.ZERO:
		_aim_wait = 0.4
		_play(&"aim", aimer)
	_aiming = aiming
	if walker_id == "" or walker_id != _guard_id:
		_guard_id = walker_id
		_guard_pos = walker
		_guard_travel = 0.0
		return
	var moved: float = walker.distance_to(_guard_pos) / 32.0
	_guard_pos = walker
	if moved > 2.0 or moved / maxf(dt, 0.001) < 0.2: return
	_guard_travel += moved
	if _guard_travel < STRIDE_GUARD: return
	_guard_travel = fmod(_guard_travel, STRIDE_GUARD)
	_play(&"snow" if sim.on_snow(walker) else &"gravel", walker, -6.0 * nearest / (GUARD_STEP_RADIUS * 32.0) - (4.0 if sim.on_snow(walker) else 0.0))

## The cascarudos: the footfalls of the one walking nearest the camera target, and a rasp from one that senses somebody
## or is drawn by a noise (when creature_body.gd sends a shudder through it), each at its own pitch, a few at once a
## moment apart. The first look after a rewind only takes stock.
func _update_creatures(dt: float) -> void:
	var nearest: float = CREATURE_STEP_RADIUS * 32.0
	var walker_id: String = ""
	var walker := Vector2.ZERO
	var focus := Vector2(_focus.x, _focus.z) * 32.0
	var delay: float = 0.0
	for beast: Dictionary in sim.guards:
		if not bool(beast.get("creature", false)): continue
		var id: String = beast.id
		var state: String = beast.state
		var was: String = str(_beast_state.get(id, ""))
		_beast_state[id] = state
		var here := Vector2(float(beast.x), float(beast.y))
		var alerted: bool = (state == "stalk" and was in ["prowl", "drawn"]) or (state == "drawn" and was == "prowl")
		if alerted and _clock - float(_beast_rasp.get(id, -1000.0)) >= RASP_AGAIN:
			_beast_rasp[id] = _clock
			_later(delay, &"rasp", here, 0.0, _beast_pitch(id))
			delay += 0.18
		if not state in ["prowl", "stalk", "drawn", "driven"]: continue
		var away: float = here.distance_to(focus)
		if away < nearest:
			nearest = away
			walker_id = id
			walker = here
	if walker_id == "" or walker_id != _beast_id:
		_beast_id = walker_id
		_beast_pos = walker
		_beast_travel = 0.0
		return
	var moved: float = walker.distance_to(_beast_pos) / 32.0
	_beast_pos = walker
	if moved > 2.0 or moved / maxf(dt, 0.001) < 0.2: return
	_beast_travel += moved
	if _beast_travel < STRIDE_CREATURE: return
	_beast_travel = fmod(_beast_travel, STRIDE_CREATURE)
	_play(&"claws", walker, -6.0 * nearest / (CREATURE_STEP_RADIUS * 32.0))

## Each cascarudo keeps its own pitch for its rasp and its rattle, as each guard keeps his voice.
func _beast_pitch(id: String) -> float:
	return 0.9 + 0.05 * float(absi(hash(id)) % 4)

## Fallback feedback for the HUD's most used controls, in case nothing calls play_ui for them: a tick on
## entering and leaving command mode and on changing operative. Skipped right after a play_ui call.
func _auto_ui(phase: String, paused: bool) -> void:
	var quiet: bool = _ui_recent < 0.2 or _hush > 0.0
	if phase == "playing" and _last_phase == "playing":
		if paused != _last_paused and not quiet: _play_flat(&"ui_tap", UI_DB, -2.0, 0.8 if paused else 1.2)
		elif sim.selected_id != _last_selected and not quiet: _play_flat(&"ui_tap", UI_DB, -2.0)
	_last_phase = phase
	_last_paused = paused
	_last_selected = sim.selected_id

func _trace_loops(dt: float) -> void:
	_trace_clock -= dt
	if _trace_clock > 0.0: return
	_trace_clock = 0.1
	var row: Dictionary = {"t": _clock, "loops": {}}
	for player: AudioStreamPlayer in [_sea, _wind, _hum, _siren, _tension]:
		if player.playing: row.loops[str(player.stream.resource_path.get_file().get_basename())] = [player.volume_db, player.pitch_scale]
	trace.append(row)
