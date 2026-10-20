extends SceneTree
## The sound module (scripts/three_d/audio.gd) on its own: every file of its cue table and of the levels' loops on disk
## and sound (16-bit mono PCM, a standard rate, no clipping, no DC offset, no click at the ends; a loop's padding
## repeating the loop); Riachuelo's events heard, unknown and empty ones ignored, the voice pool never growing; and the
## Plaza de Mayo: Hornero's tram bell, and Juan Salvo's rifle heard as a rifle (a cascarudo hit makes off: no body falls).
## Headless (dummy audio driver): nothing is heard, everything must still run without a script error.
## Run: godot --headless --path godot --script res://tests/audio_events.gd
const Simulation = preload("res://scripts/simulation.gd")
const AudioScript = preload("res://scripts/three_d/audio.gd")
const DIR: String = "res://assets/audio/"
## The loops the module plays outside its cue table: the alarm's siren and the tension under an alert.
const LOOPS: Array[String] = ["alarm_siren", "tension_loop"]
const LEVELS: Array[String] = ["plaza", "riachuelo"]
## Riachuelo's events with a typical payload (GAMEPLAY_API.md section 11), each heard at once or shortly after.
const EVENTS: Array[Dictionary] = [
	{"type": "checkpoint", "action": "save", "label": "start", "auto": true},
	{"type": "heard", "guards": ["north"], "x": 600.0, "y": 700.0, "noise": "voice"},
	{"type": "takedown", "by": "bigua", "target": "north", "lethal": false},
	{"type": "takedown", "by": "lechuza", "target": "west", "lethal": false},
	{"type": "pickup", "by": "bigua", "body": "north"},
	{"type": "drop", "by": "bigua", "body": "north", "hidden": true},
	{"type": "unlock", "by": "hornero"},
	{"type": "rescued", "by": "hornero"},
	{"type": "boarded", "id": "asset"},
	{"type": "spotted", "guard": "middle", "target": "benteveo"},
	{"type": "alarm_start", "reason": "spotted", "x": 500.0, "y": 600.0, "count": 1},
	{"type": "alarm_end"},
	{"type": "won", "time": 147.0},
]
## Events that start no sound of their own at once (the alarm drives the siren through the state; the heave of a
## pickup comes from the action clock).
const SILENT_EVENTS: Array[String] = ["alarm_start", "alarm_end", "pickup"]
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func run() -> void:
	_files()
	await _riachuelo()
	await _boca()
	await _plaza()
	print("AUDIO_EVENTS_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

func _samples(stream: AudioStreamWAV) -> PackedInt32Array:
	var data: PackedByteArray = stream.data
	var out: PackedInt32Array = []
	out.resize(data.size() >> 1)
	for i: int in range(out.size()): out[i] = data.decode_s16(i * 2)
	return out

# ---------------------------------------------------------------- the files

func _files() -> void:
	var wanted: Dictionary = {}
	for cue: StringName in AudioScript.CUES:
		for file: String in AudioScript.CUES[cue][0]: wanted[file] = false
	for file: String in LOOPS: wanted[file] = true
	for level: String in LEVELS:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % level))
		var ambience: Dictionary = data.get("ambience", {})
		for key: String in ["water", "hum"]:
			var loop: String = str(ambience.get(key, ""))
			if loop != "": wanted[loop] = true
	var on_disk: int = 0
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".wav"): continue
		on_disk += 1
		check(wanted.has(file.get_basename()), "No stray sound file: " + file)
	check(on_disk == wanted.size(), "Every sound of the cue table and the levels' loops is on disk (%d of %d)" % [on_disk, wanted.size()])
	for file: String in wanted:
		var path: String = DIR + file + ".wav"
		if not ResourceLoader.exists(path):
			check(false, "Missing sound " + path)
			continue
		var stream := load(path) as AudioStreamWAV
		check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo, file + " is 16-bit mono PCM")
		if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS: continue
		check(stream.mix_rate == 44100 or stream.mix_rate == 22050, "%s has a standard rate (%d)" % [file, stream.mix_rate])
		var samples: PackedInt32Array = _samples(stream)
		var peak: int = 0
		var total: float = 0.0
		for value: int in samples:
			peak = maxi(peak, absi(value))
			total += value
		check(peak <= int(32768.0 * db_to_linear(-1.0)), "%s peaks below -1 dBFS (%.1f)" % [file, linear_to_db(peak / 32768.0)])
		check(peak >= int(32768.0 * db_to_linear(-24.0)), "%s is not near silent (%.1f)" % [file, linear_to_db(maxf(peak, 1.0) / 32768.0)])
		check(absf(total / samples.size()) < 40.0, "%s has no DC offset (%.1f)" % [file, total / samples.size()])
		if wanted[file]:
			var pad: int = AudioScript.LOOP_PAD
			var length: int = samples.size() - 2 * pad
			var exact: bool = length > 20000
			for k: int in range(pad):
				if not exact: break
				if samples[k] != samples[length + k] or samples[pad + length + k] != samples[pad + k]: exact = false
			check(exact, file + ": a loop long enough, its padding repeating the loop sample for sample")
		else:
			check(absi(samples[0]) <= 2 and absi(samples[samples.size() - 1]) <= 2, "%s starts and ends at zero (%d, %d)" % [file, samples[0], samples[samples.size() - 1]])

# ---------------------------------------------------------------- Riachuelo's events

func _riachuelo() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	var sim: RefCounted = Simulation.new(data)
	var audio: Node = AudioScript.new()
	audio.name = "RiachueloAudio"
	audio.sim = sim
	root.add_child(audio)
	audio.build()
	audio.tracing = true
	var players: int = audio.get_child_count()
	check(players >= AudioScript.POOL_SIZE, "Riachuelo: the module builds its players (%d)" % players)
	sim.start()
	for i: int in range(4): audio.update(0.05, false)
	for event: Dictionary in EVENTS:
		var before: int = audio.trace.size()
		audio.on_sim_event(event)
		for i: int in range(24): audio.update(0.05, false)
		var started: int = 0
		for k: int in range(before, audio.trace.size()):
			if audio.trace[k].has("file"): started += 1
		check(started > 0 or event.type in SILENT_EVENTS, "Riachuelo: event %s is heard" % event.type)
		audio.on_sim_event({"type": event.type})
	audio.on_sim_event({"type": "something_new", "x": 1.0})
	audio.on_sim_event({})
	check(true, "Unknown and empty events are ignored")
	for i: int in range(10):
		for event: Dictionary in EVENTS: audio.on_sim_event(event)
		audio.update(0.02, false)
		check(audio.active_voices() <= AudioScript.POOL_SIZE, "Voices stay within the pool (%d)" % audio.active_voices())
	check(audio.get_child_count() == players, "A burst of events adds no players")
	audio.queue_free()
	await process_frame

# ---------------------------------------------------------------- the Plaza de Mayo

## Riachuelo: the river lapping at La Boca's quay, and the transporter bridge's machine house humming on after Lechuza
## puts the quay's lamps out (the lamp board is not the power).
func _boca() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	var sim: RefCounted = Simulation.new(data)
	var audio: Node = AudioScript.new()
	audio.name = "BocaAudio"
	audio.sim = sim
	root.add_child(audio)
	audio.build()
	audio.tracing = true
	# the listener follows the selected operative: Lechuza in the street by the machine house, on the quay
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	lechuza.x = 139.5 * 32.0
	lechuza.y = 104.0 * 32.0
	sim.select("lechuza")
	for i: int in range(40): audio.update(0.05, false)
	check(audio.loop_playing("amb_harbour") and not audio.loop_playing("amb_sea"), "La Boca: the Riachuelo laps at the quay, no sea")
	check(audio.loop_playing("amb_hum") and audio._hum_level > 0.9, "La Boca: the machine house hums")
	sim.radio_cut = true
	audio.on_sim_event({"type": "radio_cut", "by": "lechuza"})
	for i: int in range(40): audio.update(0.05, false)
	check(_exact(audio.trace, "act_snip_1") + _exact(audio.trace, "act_snip_2") > 0 and audio.loop_playing("amb_hum") and audio._hum_level > 0.9,
		"La Boca: the quay's lamps go out, the machine house hums on")
	audio.queue_free()
	await process_frame

## The Plaza de Mayo: Hornero's tram bell, Juan Salvo's rifle heard as a rifle (and a cascarudo hit makes off: no
## body falls), and the cascarudos' own sounds, none of them a man's.
func _plaza() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/plaza.json"))
	var sim: RefCounted = Simulation.new(data)
	var audio: Node = AudioScript.new()
	audio.name = "PlazaAudio"
	audio.sim = sim
	root.add_child(audio)
	audio.build()
	audio.tracing = true
	sim.start()
	var tram: Vector2 = sim.vehicle_rect("tram").get_center()
	sim.unit_by_id("hornero").x = tram.x
	sim.unit_by_id("hornero").y = tram.y
	sim.select("hornero")
	for i: int in range(4): audio.update(0.05, false)
	audio.on_sim_event({"type": "call", "by": "hornero", "mode": "bell", "noise": "bell", "x": tram.x, "y": tram.y, "count": 3})
	audio.on_sim_event({"type": "call", "by": "benteveo", "mode": "voice", "noise": "voice", "x": 2240.0, "y": 461.0, "count": 3})
	for i: int in range(20): audio.update(0.05, false)
	check(_exact(audio.trace, "alarm_bell") == 2, "Plaza: the tram's bell, two strokes for Hornero's call and none for a shout (%d)" % _exact(audio.trace, "alarm_bell"))
	var juan: Dictionary = sim.unit_by_id("salvo")
	juan.x = tram.x
	juan.y = tram.y + 300.0
	var falls: int = _count(audio.trace, "act_body_fall")
	audio.on_sim_event({"type": "shot", "by": "salvo", "x": juan.x, "y": juan.y, "tx": juan.x + 400.0, "ty": juan.y, "loud": true, "hit_id": "c1"})
	for i: int in range(30): audio.update(0.05, false)
	check(_exact(audio.trace, "gun_rifle") == 1 and _exact(audio.trace, "gun_rifle_bolt") == 1 and _count(audio.trace, "gun_revolver") == 0,
		"Plaza: Juan Salvo's rifle and its bolt, not a revolver (%d rifle, %d bolt, %d revolver)" % [_exact(audio.trace, "gun_rifle"), _exact(audio.trace, "gun_rifle_bolt"), _count(audio.trace, "gun_revolver")])
	check(_count(audio.trace, "act_body_fall") == falls, "Plaza: a cascarudo hit makes off, nobody falls")
	check(_exact(audio.trace, "cascarudo_shell") == 1 and _exact(audio.trace, "gun_hit") == 0, "Plaza: the bullet strikes the cascarudo's shell, not a man")
	# One coming into the square, hit, knocking Hornero down, shot dead.
	audio.trace.clear()
	audio.on_sim_event({"type": "creature", "id": "c1", "x": 8912.0, "y": 1088.0, "again": false})
	audio.on_sim_event({"type": "creature_hit", "id": "c1", "by": "salvo", "hits": 1, "x": juan.x + 400.0, "y": juan.y})
	audio.on_sim_event({"type": "struck", "by": "c1", "id": "hornero", "unit": true, "x": tram.x, "y": tram.y})
	audio.on_sim_event({"type": "creature_dead", "id": "c1", "by": "salvo", "x": juan.x + 400.0, "y": juan.y})
	for i: int in range(80): audio.update(0.05, false)
	for file: String in ["cascarudo_rattle", "cascarudo_rasp_", "cascarudo_lunge", "act_body_fall", "cascarudo_overturn", "cascarudo_step_"]:
		check(_count(audio.trace, file) > 0, "Plaza: heard " + file)
	# One in the square that goes for somebody: it rasps (no rifle comes up), and its claws are heard as it comes on,
	# not a man's boots.
	audio.trace.clear()
	var beast: Dictionary = sim.guard_by_id("c2")
	beast.state = "prowl"
	beast.x = juan.x + 200.0
	beast.y = juan.y
	for i: int in range(4): audio.update(0.05, false)
	beast.state = "stalk"
	beast.target_id = "hornero"
	for i: int in range(20):
		beast.x = float(beast.x) - 3.5
		audio.update(0.05, false)
	check(_count(audio.trace, "cascarudo_rasp_") == 1 and _exact(audio.trace, "alert_aim") == 0, "Plaza: a cascarudo going for someone rasps, once (%d)" % _count(audio.trace, "cascarudo_rasp_"))
	check(_count(audio.trace, "cascarudo_step_") >= 2 and _count(audio.trace, "foot_") == 0, "Plaza: its claws in the snow, no boots (%d)" % _count(audio.trace, "cascarudo_step_"))
	audio.queue_free()
	await process_frame

func _exact(trace: Array, file: String) -> int:
	var count: int = 0
	for row: Dictionary in trace:
		if str(row.get("file", "")) == file: count += 1
	return count

func _count(trace: Array, prefix: String) -> int:
	var count: int = 0
	for row: Dictionary in trace:
		if str(row.get("file", "")).begins_with(prefix): count += 1
	return count
