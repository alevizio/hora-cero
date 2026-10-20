extends SceneTree
## Operative voice lines (scripts/three_d/audio.gd): recordings answered to selection, orders and events. The
## shipped lines (assets/audio/voice/en and es: the four neighbours made by tools/voice_riachuelo.py, the passenger's
## from the informant's set) are checked for every person of both levels; the timing rules are checked on stand-in
## streams, in Riachuelo.
## Headless (dummy audio driver): nothing is heard, everything must still run without a script error.
const Simulation = preload("res://scripts/simulation.gd")
const AudioScript = preload("res://scripts/three_d/audio.gd")
var failures: int = 0
var checks: int = 0
var mission: Dictionary

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

## A short silent 16-bit mono stream of the given length.
func _line(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(int(seconds * 22050.0) * 2)
	stream.data = data
	return stream

func _module(with_lines: bool) -> Array:
	var sim: RefCounted = Simulation.new(mission)
	var audio: Node = AudioScript.new()
	audio.name = "Audio"
	audio.sim = sim
	root.add_child(audio)
	audio.build()
	if with_lines:
		for unit: String in ["hornero", "lechuza"]:
			for kind: String in AudioScript.VOICE_KINDS:
				audio.voice_bank["%s/%s" % [unit, kind]] = [_line(0.5), _line(0.5)]
	sim.start()
	if sim.paused: sim.toggle_pause()
	for i: int in range(10): audio.update(0.05, false)
	return [sim, audio]

func _run(audio: Node, sim: RefCounted, seconds: float) -> void:
	for i: int in range(int(round(seconds / 0.05))):
		sim.update(0.05)
		audio.update(0.05, sim.paused)

func run() -> void:
	mission = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	_without()
	_with()
	_refusals()
	_rewind()
	print("VOICE_LINES_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

## The shipped lines: every person of both levels has what he needs, in English and in Spanish, and a language
## without a line of its own falls back to English. Then, with the bank empty, nobody speaks.
const NEEDED: Dictionary = {
	# the four neighbours also say when the work is done (Benteveo never strikes and has nothing to finish)
	"hornero": ["select", "move", "attack", "work", "done", "refuse", "spotted", "hurt"],
	"lechuza": ["select", "move", "attack", "work", "done", "refuse", "spotted", "hurt"],
	"benteveo": ["select", "move", "work", "refuse", "spotted", "hurt"],
	"bigua": ["select", "move", "attack", "work", "done", "refuse", "spotted", "hurt"],
	"asset": ["freed", "spotted", "hurt"],
}

func _paths(audio: Node, key: String) -> Array[String]:
	var out: Array[String] = []
	for line: AudioStream in audio.voice_bank.get(key, []): out.append(line.resource_path)
	return out

func _without() -> void:
	var made: Array = _module(false)
	var sim: RefCounted = made[0]
	var audio: Node = made[1]
	var plaza: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/plaza.json"))
	var riachuelo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	var heard: Dictionary = {}
	for lang: String in ["en", "es"]:
		var missing: Array[String] = []
		var wrong: Array[String] = []
		for data: Dictionary in [plaza, riachuelo]:
			audio.sim = Simulation.new(data)
			audio.load_voices(lang)
			for who: String in NEEDED:
				if who == "asset" and not bool(audio.sim.has_prisoner): continue
				if who != "asset" and audio.sim.unit_by_id(who).is_empty(): continue
				heard[who] = true
				for kind: String in NEEDED[who]:
					var paths: Array[String] = _paths(audio, "%s/%s" % [who, kind])
					if paths.is_empty(): missing.append("%s/%s" % [who, kind])
					for path: String in paths:
						if not path.contains("/voice/%s/" % lang): wrong.append(path)
		check(missing.is_empty(), "%s: every person has every line he needs (missing %s)" % [lang, str(missing)])
		check(wrong.is_empty(), "%s: the lines come from the %s folder (%s)" % [lang, lang, str(wrong)])
	check(heard.size() == NEEDED.size(), "Every person of the list is in some level (%s)" % str(heard.keys()))
	# the neighbours are porteños: their own Spanish lines, not a fallback
	audio.sim = Simulation.new(riachuelo)
	audio.load_voices("es")
	check(_paths(audio, "benteveo/select").size() >= 2 and _paths(audio, "hornero/done").size() >= 2, "The neighbours of La Boca have their lines in Spanish")
	audio.sim = Simulation.new(mission)
	audio.load_voices("es")
	var spanish: Array[String] = _paths(audio, "hornero/select")
	audio.load_voices("xx")
	check(not spanish.is_empty() and _paths(audio, "hornero/select").all(func(p: String) -> bool: return p.contains("/voice/en/")), "A language with no lines of its own falls back to English")
	audio.load_voices("en")
	check(audio.voice_bank.has("asset/freed"), "Riachuelo's bank holds the passenger's lines")
	audio.sim = Simulation.new(plaza)
	audio.load_voices("en")
	check(not audio.voice_bank.has("asset/freed") and audio.voice_bank.has("hornero/select"), "The bank holds this level's people only")
	audio.queue_free()
	# with nothing in the bank, nothing is said and nothing breaks
	made = _module(false)
	sim = made[0]
	audio = made[1]
	audio.voice_bank.clear()
	sim.select("lechuza")
	sim.select("hornero")
	sim.move_to(sim.position_of(sim.selected()) + Vector2(60, 0))
	_run(audio, sim, 1.0)
	check(audio.voice_log.is_empty(), "With nothing recorded nobody speaks")
	check(not audio.say("hornero", "select"), "say() reports that no line started")
	audio.queue_free()

## A refused order is answered with a refusal; the passenger has a word of his own when he is brought up.
func _refusals() -> void:
	var made: Array = _module(true)
	var sim: RefCounted = made[0]
	var audio: Node = made[1]
	audio.voice_bank["asset/freed"] = [_line(0.5)]
	_run(audio, sim, AudioScript.VOICE_REPEAT)
	audio.refuse("hornero")
	check(audio.voice_log.size() > 0 and audio.voice_log[audio.voice_log.size() - 1] == "hornero/refuse#0", "A refused order is answered (%s)" % str(audio.voice_log))
	_run(audio, sim, AudioScript.VOICE_REPEAT)
	audio.on_sim_event({"type": "rescued", "by": "lechuza"})
	_run(audio, sim, 1.0)
	check(audio.voice_log[audio.voice_log.size() - 1] == "asset/freed#0", "The passenger speaks when he is brought up (%s)" % str(audio.voice_log))
	audio.queue_free()

func _with() -> void:
	var made: Array = _module(true)
	var sim: RefCounted = made[0]
	var audio: Node = made[1]
	check(audio.voice_log.is_empty(), "Nobody speaks just because the mission began (%s)" % str(audio.voice_log))
	# selection
	var other: String = "lechuza" if sim.selected_id == "hornero" else "hornero"
	sim.select(other)
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == 1 and audio.voice_log[0] == other + "/select#0", "The operative answers when selected (%s)" % str(audio.voice_log))
	# an order while the first line is still playing waits its turn; after it, orders are answered
	sim.move_to(sim.position_of(sim.selected()) + Vector2(40, 0))
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == 1, "A second line does not talk over the first")
	_run(audio, sim, 1.2)
	sim.move_to(sim.position_of(sim.selected()) + Vector2(60, 10))
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == 2 and audio.voice_log[1] == other + "/move#0", "A move order is answered (%s)" % str(audio.voice_log))
	# the same kind again at once is not repeated, later it is, with the next take
	_run(audio, sim, 1.2)
	sim.move_to(sim.position_of(sim.selected()) + Vector2(30, 30))
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == 2, "He does not say the same kind of thing twice in a row")
	_run(audio, sim, AudioScript.VOICE_REPEAT)
	sim.move_to(sim.position_of(sim.selected()) + Vector2(20, 0))
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == 3 and audio.voice_log[2] == other + "/move#1", "Later he answers again, with the next take (%s)" % str(audio.voice_log))
	# urgent lines cut in; finished work is reported a moment after its event
	_run(audio, sim, 0.1)
	audio.on_sim_event({"type": "spotted", "guard": "north", "target": "hornero"})
	check(audio.voice_log[audio.voice_log.size() - 1] == "hornero/spotted#0", "Being seen cuts in over a line still playing")
	_run(audio, sim, 1.5)
	audio.on_sim_event({"type": "unlock", "by": "lechuza"})
	_run(audio, sim, 0.3)
	check(not audio.voice_log[audio.voice_log.size() - 1].begins_with("lechuza/done"), "The work is not reported before it has sunk in")
	_run(audio, sim, 0.6)
	check(audio.voice_log[audio.voice_log.size() - 1] == "lechuza/done#0", "Finished work is reported (%s)" % str(audio.voice_log))
	audio.on_sim_event({"type": "hurt", "id": "lechuza", "hp": 66, "by": "north"})
	check(audio.voice_log[audio.voice_log.size() - 1] == "lechuza/hurt#0", "A hit is voiced at once")
	# command mode: orders given in the pause are still answered
	_run(audio, sim, AudioScript.VOICE_REPEAT + 1.0)
	sim.toggle_pause()
	sim.select("hornero")
	_run(audio, sim, 1.5)
	var before: int = audio.voice_log.size()
	sim.move_to(sim.position_of(sim.selected()) + Vector2(50, 0))
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == before + 1 and audio.voice_log[before].begins_with("hornero/move"), "Orders in command mode are answered (%s)" % str(audio.voice_log))
	sim.toggle_pause()
	# switched off: silent
	audio.enabled = false
	before = audio.voice_log.size()
	sim.select("lechuza")
	_run(audio, sim, 0.2)
	check(audio.voice_log.size() == before and not audio.say("lechuza", "select"), "Sound off means no voices")
	audio.queue_free()

## A restart puts orders and selection back: nobody answers to that.
func _rewind() -> void:
	var made: Array = _module(true)
	var sim: RefCounted = made[0]
	var audio: Node = made[1]
	sim.select("lechuza")
	sim.move_to(sim.position_of(sim.selected()) + Vector2(40, 0))
	_run(audio, sim, 2.0)
	var before: int = audio.voice_log.size()
	sim.restart()
	if sim.paused: sim.toggle_pause()
	_run(audio, sim, AudioScript.VOICE_REPEAT)
	check(audio.voice_log.size() == before, "A restart is not answered (%s)" % str(audio.voice_log))
	sim.select("hornero" if sim.selected_id == "lechuza" else "lechuza")
	_run(audio, sim, 0.1)
	check(audio.voice_log.size() == before + 1, "After it, selection is answered again")
	audio.queue_free()
