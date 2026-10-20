extends SceneTree
## Whole-mission playthrough of Operation Riachuelo (data/riachuelo.json) with all four, played the way the HUD plays it
## (select, then perform) on the full roster, waiting on what the guards do rather than on the clock.
##   crossing: once the sergeant has gone by along the far side, all four slip out of the courtyard to the edge of the
##             cutting and Lechuza sets his ladder; down, over the rails and up. Lechuza and Benteveo go down the tram street behind its patrolman while he is off along
##             the cross street (they wait in the scrub on the lip until he is), and Lechuza puts the quay's lamps out at
##             the board; the two of them wait in a doorway by the gondola's landing. Hornero and Biguá wait at the top of the alley for its patrolman to turn
##             south, follow him down, and Biguá's knife takes him from behind by the café's back door; his body goes
##             into a doorway. Hornero opens the cellar, Biguá brings the passenger out. Hornero goes on alone: up the
##             alley, along the cross street, and upright down the tram lines like a motorman going to work, to the
##             gondola's landing, dark now, where he works the controls a few steps from the posted man's back. The
##             three ride across. Biguá takes the passenger up the alley, along the cross street and down the west
##             street to the boats drawn up by the shed, launches his boat when the launch's beam has swung away and
##             rows him over. Everyone along the far shore to the lane where friends wait. One killed (the alley's
##             patrolman), no alarm.
##   spanish:  every line the crossing put in the notice strip, read in Rioplatense Spanish (locale/es.json).
## Run: godot --headless --path godot --script res://tests/riachuelo_playthrough.gd [-- verbose] [upto=<stage>]
## Stages: cutting, lamps, cellar, gondola, boat.

const Kit = preload("res://tests/playthrough_kit.gd")
const Lang = preload("res://scripts/lang.gd")

var mission: Dictionary
var checks: int = 0
var failures: int = 0
var verbose: bool = false
var upto: String = ""
var section: String = ""
var _beam_last: float = 0.0
## The lines the player read on the way (the notice strip), for the Spanish read at the end.
var said: Dictionary = {}

func _init() -> void:
	mission = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	for arg: String in OS.get_cmdline_user_args():
		if arg == "verbose": verbose = true
		elif arg.begins_with("upto="): upto = arg.substr(5)
	call_deferred("_run")

func _expect(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL [%s]: %s" % [section, explanation])

func _run() -> void:
	section = "crossing"
	_crossing()
	section = "spanish"
	_spanish()
	print("Riachuelo playthroughs: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _there(k: Kit, ids: Array) -> bool:
	for id: String in ids:
		if not k.arrived(id): return false
	return true

## Where a guard is, in metres.
func _g(k: Kit, id: String) -> Vector2:
	return k.at(id) / 32.0

## The guard's heading in degrees, 0..360 (90 is south, towards the river).
func _heading(k: Kit, id: String) -> float:
	return fposmod(rad_to_deg(float(k.guard(id).angle)), 360.0)

## The launch's beam bearing, 0..360 (180 is due west, along the river towards the boat shed).
func _beam(k: Kit) -> float:
	return _heading(k, "launch")

func _log(k: Kit, text: String) -> void:
	if verbose:
		var line: String = "  -- %6.2f %s:" % [k.game.time, text]
		for id: String in ["hornero", "lechuza", "benteveo", "bigua", "asset"]:
			line += " %s(%.1f,%.1f)" % [id, k.at(id).x / 32.0, k.at(id).y / 32.0]
		print(line)

func _quiet(k: Kit, what: String) -> void:
	_expect(int(k.game.stats.alarms) == 0, "%s unseen" % what)

## The sergeant is past the courtyard's corner of the south street, walking east (his back to the cutting's ladder).
func _sergeant_gone_east(k: Kit, x: float) -> bool:
	var at: Vector2 = _g(k, "sergeant")
	return (absf(at.y - 42.0) < 1.0 and at.x > x) or (absf(at.x - 123.0) < 1.0 and at.y > 44.0 and at.y < 96.0)

## Out of the courtyard to the cutting's edge once the sergeant has gone by; Lechuza sets the ladder; all four down,
## over and up.
func _over_the_cutting(k: Kit) -> void:
	k.until(func() -> bool: return _sergeant_gone_east(k, 112.0), 90.0, "the sergeant past the courtyard")
	_log(k, "sergeant past")
	k.follow("lechuza", [m(110.0, 17.5), m(110.0, 21.0), m(105.0, 29.2)])
	k.follow("hornero", [m(109.6, 17.5), m(109.6, 21.0), m(103.8, 28.6)])
	k.follow("benteveo", [m(110.4, 17.5), m(110.4, 21.0), m(106.2, 28.6)])
	k.follow("bigua", [m(110.2, 17.5), m(110.2, 21.0), m(104.6, 28.0)])
	k.until(_there.bind(k, ["lechuza", "hornero", "benteveo", "bigua"]), 30.0, "the edge of the cutting")
	_log(k, "at the edge")
	k.do("lechuza", "rig", "ladder")
	_expect(k.game.rigged.has("ladder"), "the ladder is set")
	# Lechuza and Benteveo into the scrub on the far lip, Hornero and Biguá along the south street's far side
	k.follow("lechuza", [m(105.4, 38.6), m(114.0, 38.8)])
	k.follow("benteveo", [m(104.6, 38.6), m(116.4, 38.8)])
	k.follow("hornero", [m(105.0, 38.8), m(104.0, 45.4), m(84.0, 45.4), m(82.6, 47.0)])
	k.follow("bigua", [m(104.4, 38.8), m(103.4, 45.2), m(84.0, 45.0), m(81.6, 47.4)])
	k.until(_there.bind(k, ["lechuza", "hornero", "benteveo", "bigua"]), 60.0, "over the cutting")
	_log(k, "over the cutting")
	_quiet(k, "over the cutting")

## Each pair goes about its own work at once: per pair, the step it has reached (see _tick).
var lamps: int = 0
var hornero: int = 0
var bigua: int = 0

func _stage(k: Kit, who: String, value: int, text: String) -> void:
	match who:
		"lamps": lamps = value
		"hornero": hornero = value
		"bigua": bigua = value
	_log(k, "%s %d: %s" % [who, value, text])

## The patrolman walking round the machine house is well away from x (metres) along the avenue.
func _machine_away(k: Kit, x: float, gap: float = 8.0) -> bool:
	return absf(_g(k, "machine").x - x) > gap

## Lechuza and Benteveo: down the tram street once its patrolman has turned west along the cross street, the lamps out
## at the board, into the doorway by the gondola's landing; over the river once the gondola runs.
func _lamp_team(k: Kit) -> void:
	match lamps:
		0:
			if _g(k, "middle").y > 66.0 and _g(k, "middle").x < 119.0 and _heading(k, "middle") > 135.0 and _heading(k, "middle") < 225.0:
				k.follow("lechuza", [m(121.0, 46.5), m(121.0, 66.0), m(121.0, 95.6), m(122.2, 96.6)])
				k.follow("benteveo", [m(120.6, 46.5), m(120.6, 66.0), m(120.6, 95.0)])
				_stage(k, "lamps", 1, "down the tram street")
		1:
			if k.arrived("lechuza"):
				k.order("lechuza", "sabotage")
				_stage(k, "lamps", 2, "at the board")
		2:
			if k.game.radio_cut and k.idle("lechuza"):
				k.follow("lechuza", [m(130.0, 96.0), m(141.0, 95.0)])
				k.follow("benteveo", [m(130.0, 95.4), m(143.0, 94.8)])
				_stage(k, "lamps", 3, "lamps out")
		3:
			if _there(k, ["lechuza", "benteveo"]):
				_stage(k, "lamps", 4, "in the doorway by the landing")
		4:
			# the gondola runs: across the avenue behind the landing's sentry, while the machine house's man is away
			if k.game.rigged.has("gondola") and _machine_away(k, 146.0, 9.0):
				k.follow("lechuza", [m(144.6, 100.0), m(146.6, 108.6), m(148.0, 112.0), m(148.0, 136.0)])
				k.follow("benteveo", [m(145.2, 100.4), m(147.0, 108.8), m(149.0, 112.0), m(149.0, 136.4)])
				_stage(k, "lamps", 5, "to the gondola")
		5:
			if _there(k, ["lechuza", "benteveo"]):
				k.follow("lechuza", [m(140.0, 138.0), m(101.0, 139.0), m(99.0, 144.0)])
				k.follow("benteveo", [m(140.0, 138.6), m(101.6, 139.6), m(101.0, 144.6)])
				_stage(k, "lamps", 6, "on the far bank")

## Hornero: down the alley behind Biguá, the cellar door, then alone to the gondola's landing along the tram lines.
func _hornero_team(k: Kit) -> void:
	match hornero:
		0:
			if str(k.guard("alley").state) == "dead":
				k.follow("hornero", [m(82.6, 80.0), m(81.0, 87.0)])
				_stage(k, "hornero", 1, "to the café's back door")
		1:
			if k.arrived("hornero"):
				k.order("hornero", "unlock")
				_stage(k, "hornero", 2, "the cellar door")
		2:
			if k.game.door_open and k.idle("hornero"):
				k.follow("hornero", [m(75.0, 87.0)])
				_stage(k, "hornero", 3, "the cellar is open")
		3:
			# up the alley and along the cross street once the tram street's patrolman has gone on south down it
			var middle: Vector2 = _g(k, "middle")
			if k.arrived("hornero") and absf(middle.x - 123.0) < 1.0 and middle.y > 76.0 and _heading(k, "middle") > 45.0 and _heading(k, "middle") < 135.0:
				k.follow("hornero", [m(81.0, 87.0), m(82.4, 70.0), m(84.5, 67.0), m(119.5, 67.0)])
				_stage(k, "hornero", 4, "up the alley")
		4:
			if k.arrived("hornero"):
				# a motorman going to work: upright on the tram lines
				k.stance("hornero", "walk")
				k.follow("hornero", [m(121.6, 70.0), m(121.6, 102.0), m(144.6, 103.0)])
				_stage(k, "hornero", 5, "down the tram lines")
		5:
			if k.arrived("hornero") and k.game.radio_cut and lamps >= 4 and _machine_away(k, 146.0, 8.0):
				k.stance("hornero", "sneak")
				k.follow("hornero", [m(146.2, 106.4), m(147.2, 108.9)])
				_stage(k, "hornero", 6, "onto the dark landing")
		6:
			if k.arrived("hornero"):
				k.order("hornero", "rig", "gondola")
				_stage(k, "hornero", 7, "the gondola's controls")
		7:
			if k.game.rigged.has("gondola") and k.idle("hornero"):
				k.follow("hornero", [m(150.6, 112.0), m(150.4, 136.0), m(140.0, 139.0), m(102.0, 140.0), m(100.4, 145.6)])
				_stage(k, "hornero", 8, "across and along the far bank")

## Biguá: the alley's patrolman from behind, his body into a doorway, the passenger out of the cellar, and over the river
## in his boat.
func _bigua_team(k: Kit) -> void:
	match bigua:
		0:
			# the alley's patrolman has looked up the alley and turned back south: after him
			var alley: Vector2 = _g(k, "alley")
			if alley.y > 66.5 and alley.y < 70.0 and _heading(k, "alley") > 60.0 and _heading(k, "alley") < 120.0:
				k.order("bigua", "takedown", "alley")
				_stage(k, "bigua", 1, "after the alley's patrolman")
		1:
			if str(k.guard("alley").state) == "dead" and k.idle("bigua"):
				k.order("bigua", "pickup", "alley")
				_stage(k, "bigua", 2, "the knife")
		2:
			if str(k.unit("bigua").carrying) != "":
				k.order("bigua", "drop", m(83.3, 74.0))
				_stage(k, "bigua", 3, "carrying him to the doorway")
		3:
			if k.idle("bigua") and str(k.unit("bigua").carrying) == "" and k.game.door_open:
				k.order("bigua", "rescue")
				_stage(k, "bigua", 4, "the passenger")
		4:
			if bool(k.game.prisoner.freed) and k.idle("bigua"):
				# out of the back door and up the alley to the doorway where the patrolman lies
				k.follow("bigua", [m(78.0, 87.0), m(81.2, 87.0), m(83.2, 74.4)])
				_stage(k, "bigua", 5, "the passenger out, up the alley")
		5:
			# along the cross street and down the west street: the sergeant gone east along the south street or down the
			# tram street, and the west street's patrolman on his way back north
			var west: Vector2 = _g(k, "west")
			if k.arrived("bigua") and _sergeant_gone_east(k, 64.0) and west.y < 56.0 and _heading(k, "west") > 225.0 and _heading(k, "west") < 315.0:
				k.stance("bigua", "walk")
				k.follow("bigua", [m(82.2, 70.0), m(80.0, 67.4), m(56.4, 67.4), m(53.8, 70.0), m(53.8, 99.4), m(48.0, 102.6), m(36.0, 103.4), m(33.4, 107.0)])
				_stage(k, "bigua", 6, "the escort to the boats")
		6:
			if k.arrived("bigua") and bool(k.game.prisoner.hidden):
				k.stance("bigua", "sneak")
				_stage(k, "bigua", 7, "among the boats by the shed")
		7:
			# the launch's beam has just swung away north-east off the shed's water: launch the boat and row over
			if _beam(k) > 216.0 and _beam(k) < 240.0 and _beam(k) > _beam_last:
				k.order("bigua", "rig", "boat")
				_stage(k, "bigua", 8, "the boat down the slip")
		8:
			if k.game.rigged.has("boat") and k.idle("bigua"):
				k.stance("bigua", "walk")
				k.follow("bigua", [m(45.0, 111.0), m(45.0, 136.4), m(60.0, 139.0), m(97.0, 140.0), m(99.0, 145.0)])
				_stage(k, "bigua", 9, "rowing over")

## The end of the run, or of the stage asked for (upto=lamps, cellar, gondola, boat).
func _stop(k: Kit) -> bool:
	match upto:
		"lamps": return lamps >= 4
		"cellar": return hornero >= 3 and bigua >= 5
		"gondola": return hornero >= 8
		"boat": return bigua >= 9
	return k.game.phase != "playing"

## Where the passenger was (x, metres) whenever he was out on the river.
var river_xs: Array[float] = []

func _tick(k: Kit) -> void:
	var at: Vector2 = k.at("asset") / 32.0
	if at.y > 110.5 and at.y < 133.5: river_xs.append(at.x)
	_lamp_team(k)
	_hornero_team(k)
	_bigua_team(k)
	_beam_last = _beam(k)

func _crossing() -> void:
	var k := Kit.new(mission, "crossing", verbose)
	k.after_step = _said.bind(k)
	_over_the_cutting(k)
	if upto == "cutting": return _done(k)
	k.after_step = func() -> void:
		_said(k)
		_tick(k)
		_said(k)
	k.until(_stop.bind(k), 600.0, "the end")
	_log(k, "stopped")
	_quiet(k, "the night")
	_done(k)
	if upto != "": return
	_expect(k.game.phase == "won", "won (%s)" % k.game.phase)
	_expect(k.game.rigged.has("ladder") and k.game.rigged.has("gondola") and k.game.rigged.has("boat"), "the ladder, the gondola and the boat: %s" % str(k.game.rigged.keys()))
	_expect(k.game.radio_cut and k.game.door_open and bool(k.game.prisoner.aboard), "the lamps out, the cellar open, the passenger across")
	_expect(not river_xs.is_empty() and river_xs.min() > 41.5 and river_xs.max() < 48.5, "the passenger went over in Biguá's boat (x %.1f..%.1f m)" % [river_xs.min() if not river_xs.is_empty() else -1.0, river_xs.max() if not river_xs.is_empty() else -1.0])
	_expect(int(k.game.stats.kills) == 1 and str(k.guard("alley").state) == "dead" and bool(k.guard("alley").hidden), "one man killed, the alley's patrolman, hidden in a doorway")
	_expect(int(k.game.stats.bodies_found) == 0, "nobody found him")
	var earned: Array[String] = k.badges()
	_expect("ghost" in earned and "not_a_shot" in earned and "saboteur" in earned and "swift" in earned and not "clean_hands" in earned, "ghost, not a shot, saboteur, swift: %s" % str(earned))
	_expect(k.game.time < float(mission.parTime), "inside par (%.0f s of %d)" % [k.game.time, int(mission.parTime)])
	for unit: Dictionary in k.game.units:
		_expect(bool(unit.alive) and int(unit.hp) == 100 and not bool(unit.get("blown", false)), "%s home without a scratch, never marked" % unit.id)
	print(k.summary())

func _said(k: Kit) -> void:
	said[str(k.game.message)] = true

## Everything the crossing said, as the Spanish game shows it: each line has its Spanish, and no piece of one is left in
## English.
func _spanish() -> void:
	Lang.use("es")
	Lang.record = true
	Lang.misses.clear()
	var english: Array[String] = []
	for message: String in said:
		if message != "" and Lang._wordy(message) and Lang.lookup(message) == message: english.append(message)
	_expect(said.size() > 12, "plenty of lines on the way (%d)" % said.size())
	_expect(english.is_empty() and Lang.misses.is_empty(), "every line of the crossing reads in Spanish: %s %s" % [str(english), str(Lang.misses.keys())])
	if verbose:
		for message: String in said: print("  ES  ", Lang.lookup(message))
	Lang.record = false
	Lang.use("en")

func _done(k: Kit) -> void:
	if verbose and k.game.phase != "won": print(k.summary())
	_expect(k.problems.is_empty(), "every order taken: %s" % str(k.problems))
