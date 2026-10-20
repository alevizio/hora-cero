extends SceneTree
## Whole-mission playthrough of the Plaza de Mayo prologue (data/plaza.json) with the whole squad, played the way the HUD
## plays it (select, then perform) on the full square, each of them going about his own work at once and waiting on the
## snow (and the cascarudos) rather than on the clock.
##   rescue: in the first light snow, Benteveo walks out of the Catedral's portico to the group by the Catedral and
##           shouts them over, and leads them back in; Hornero takes the tram along Rivadavia to the next stop, rings
##           its bell for the group under the palms and drives straight on (they run after the tram and climb aboard) to
##           the stop by the Banco Nación, where he rings again for the group by the flagpole: the bell draws the
##           cascarudo that came along Rivadavia a quarter of a minute in away from them to the tram, and the two in the
##           bell's reach get in ahead of it (the third, out of its reach, is left by the flagpole); Lechuza puts the
##           arcade's lights back, opens the subte's service gate and brings the group by the Cabildo down the service
##           stair; Biguá leaves the colectivo for the group by the Belgrano monument and then the two by the Casa
##           Rosada, and leads each back to it, the last of them in as the second cascarudo comes up Hipólito Yrigoyen.
##           Juan Salvo comes in off Avenida de Mayo half a minute in and walks along the north of the square toward the
##           tram; the cascarudo leaves it for him, and he drives it off with his rifle before it reaches him. Through
##           the first wave (the snow does not touch him), while the squad waits it out under cover, he crosses to the
##           Casa Rosada's shut gates, where a man from the Pirámide and the one left by the flagpole have run in a
##           panic, and drives the second cascarudo off as it goes for them. In the lull: Juan Salvo leads the two from
##           the gates to the colectivo; Benteveo walks out to the Pirámide, shouts over the group on its west side and
##           the two left on its east side, and leads all six to the tram, which Hornero has brought back to the middle
##           stop; Lechuza fetches the two in the south of the square to the service stair, ahead of the third
##           cascarudo, just in off Avenida de Mayo. The first two come back up their avenues with nobody left near
##           them. Everyone in, the squad under cover: won with every medal, before the second wave, on two of Juan
##           Salvo's six rounds.
##   spanish: every line the rescue put in the notice strip, read in Rioplatense Spanish (locale/es.json).
## Run: godot --headless --path godot --script res://tests/plaza_playthrough.gd [-- verbose]

const Kit = preload("res://tests/playthrough_kit.gd")
const Lang = preload("res://scripts/lang.gd")

var mission: Dictionary
var checks: int = 0
var failures: int = 0
var verbose: bool = false
var section: String = ""
## The lines the player read on the way (the notice strip), for the Spanish read at the end.
var said: Dictionary = {}
## Each operative's step in his own plan (see _tick), and the highest cold each of the four took.
var step: Dictionary = {"benteveo": 0, "hornero": 0, "lechuza": 0, "bigua": 0, "salvo": 0}
## Seconds Juan Salvo spent out in the open while a wave fell.
var salvo_in_wave: float = 0.0
var coldest: Dictionary = {}

func _init() -> void:
	mission = JSON.parse_string(FileAccess.get_file_as_string("res://data/plaza.json"))
	for arg: String in OS.get_cmdline_user_args():
		if arg == "verbose": verbose = true
	call_deferred("_run")

func _expect(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL [%s]: %s" % [section, explanation])

func _run() -> void:
	section = "rescue"
	_rescue()
	section = "spanish"
	_spanish()
	print("Plaza playthroughs: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _log(k: Kit, text: String) -> void:
	if not verbose: return
	var line: String = "  -- %6.2f snow %.2f %s:" % [k.game.time, k.game.snow_intensity(), text]
	for id: String in ["hornero", "lechuza", "benteveo", "bigua", "salvo"]:
		var u: Dictionary = k.unit(id)
		line += " %s(%.0f,%.0f c%.2f)" % [id, float(u.x) / 32.0, float(u.y) / 32.0, float(u.exposure)]
	for g: Dictionary in k.game.guards:
		if bool(g.get("creature", false)) and str(g.state) != "waiting":
			line += " %s:%s(%.0f,%.0f)" % [g.id, g.state, float(g.x) / 32.0, float(g.y) / 32.0]
	var counts: Dictionary = k.game.rescue_counts()
	line += "  saved %d out %d fallen %d lost %d" % [int(counts.saved), int(counts.out), int(counts.fallen), int(counts.lost)]
	print(line)

func _next(k: Kit, who: String, text: String) -> void:
	step[who] = int(step[who]) + 1
	_log(k, "%s %d: %s" % [who, int(step[who]), text])

func _state(k: Kit, id: String) -> String:
	return str(k.game.guard_by_id(id).state)

func _all(k: Kit, ids: Array, state: String) -> bool:
	for id: String in ids:
		if _state(k, id) != state: return false
	return true

func _level(k: Kit) -> String:
	return k.game.snow_level()

func _lull(k: Kit) -> bool:
	return _level(k) == "lull"

func _group(name: String) -> Array:
	var ids: Array = []
	for p: Dictionary in mission.people:
		if str(p.group) == name: ids.append(str(p.id))
	return ids

## Benteveo: the group by the Catedral first, with his voice; in the lull, the Pirámide's two groups to the tram.
func _benteveo(k: Kit) -> void:
	var nw: Array = _group("nw")
	match int(step.benteveo):
		0:
			k.order("benteveo", "move", m(66.0, 46.0))
			_next(k, "benteveo", "out to the group by the Catedral")
		1:
			if k.arrived("benteveo"):
				k.order("benteveo", "call")
				_next(k, "benteveo", "shouts them over")
		2:
			if k.game.followers_of("benteveo").size() == nw.size():
				k.order("benteveo", "move", m(70.0, 14.0))
				_next(k, "benteveo", "leads them to the portico")
		3:
			if _all(k, nw, "safe") and k.arrived("benteveo"):
				_next(k, "benteveo", "the Catedral's group under the portico")
		4:
			if _lull(k) and float(k.unit("benteveo").exposure) < 0.05:
				k.order("benteveo", "move", m(124.5, 78.0))
				_next(k, "benteveo", "out to the Pirámide in the lull")
		5:
			if k.arrived("benteveo"):
				k.order("benteveo", "call")
				_next(k, "benteveo", "shouts over the Pirámide's west side")
		6:
			if k.game.followers_of("benteveo").size() >= 4:
				k.order("benteveo", "move", m(149.0, 84.0))
				_next(k, "benteveo", "round to its east side")
		7:
			if k.arrived("benteveo") and float(k.unit("benteveo").cooldown) <= 0.0:
				k.order("benteveo", "call")
				_next(k, "benteveo", "shouts over the east side")
		8:
			if k.game.followers_of("benteveo").size() >= 6 and k.game.vehicles.tram.to < 0 and k.game.vehicle_rect("tram").position.x < m(140.0, 0.0).x:
				k.order("benteveo", "move", k.game.vehicle_rect("tram").get_center() + m(2.0, 0.0))
				_next(k, "benteveo", "leads all six to the tram")
		9:
			if k.arrived("benteveo") and k.game.followers_of("benteveo").is_empty():
				_next(k, "benteveo", "all six in the tram")

## Hornero: the tram to the next stop and the bell for the palms; straight on to the bank's stop (they run after it) and
## the bell for the flagpole, which draws the first cascarudo to the tram; back to the middle stop in the lull for the
## Pirámide's people.
func _hornero(k: Kit) -> void:
	match int(step.hornero):
		0:
			k.order("hornero", "drive")
			_next(k, "hornero", "takes the tram on")
		1:
			if k.arrived("hornero"):
				k.order("hornero", "call")
				_next(k, "hornero", "rings for the palms")
		2:
			if k.arrived("hornero"):
				k.order("hornero", "drive")
				_next(k, "hornero", "straight on to the bank's stop")
		3:
			if k.arrived("hornero") and float(k.unit("hornero").cooldown) <= 0.0:
				k.order("hornero", "call")
				_next(k, "hornero", "rings for the flagpole")
		4:
			if _lull(k):
				k.order("hornero", "drive")
				_next(k, "hornero", "back to the middle stop in the lull")
		5:
			if k.arrived("hornero"):
				_next(k, "hornero", "waits at the middle stop")

## Lechuza: the arcade's lights, the service gate, the Cabildo's group down the service stair; in the lull, the two in
## the south of the square.
func _lechuza(k: Kit) -> void:
	match int(step.lechuza):
		0:
			k.order("lechuza", "rig", "cabildo-lights")
			_next(k, "lechuza", "the arcade's fuse box")
		1:
			if k.arrived("lechuza"):
				k.order("lechuza", "rig", "subte-gate")
				_next(k, "lechuza", "to the service gate")
		2:
			if k.arrived("lechuza"):
				k.order("lechuza", "guide", _group("sw")[0])
				_next(k, "lechuza", "to the Cabildo's group")
		3:
			if k.arrived("lechuza") and k.game.followers_of("lechuza").size() == _group("sw").size():
				k.order("lechuza", "move", m(45.0, 129.5))
				_next(k, "lechuza", "leads them down the service stair")
		4:
			if _all(k, _group("sw"), "safe") and k.arrived("lechuza"):
				_next(k, "lechuza", "the Cabildo's group in the subte")
		5:
			if _lull(k) and float(k.unit("lechuza").exposure) < 0.05:
				k.order("lechuza", "guide", _group("south")[0])
				_next(k, "lechuza", "out to the two in the south of the square")
		6:
			if k.arrived("lechuza") and k.game.followers_of("lechuza").size() == _group("south").size():
				k.order("lechuza", "move", m(45.0, 129.5))
				_next(k, "lechuza", "leads them to the service stair")
		7:
			if _all(k, _group("south"), "safe") and k.arrived("lechuza"):
				_next(k, "lechuza", "the south's two in the subte")

## Biguá: the Belgrano monument's group and the two by the Casa Rosada to the colectivo.
func _bigua(k: Kit) -> void:
	var colectivo: Vector2 = m(203.5, 138.2)
	match int(step.bigua):
		0:
			k.order("bigua", "guide", _group("belgrano")[0])
			_next(k, "bigua", "out to the Belgrano monument")
		1:
			if k.arrived("bigua") and k.game.followers_of("bigua").size() == _group("belgrano").size():
				k.order("bigua", "move", colectivo)
				_next(k, "bigua", "leads them to the colectivo")
		2:
			if _all(k, _group("belgrano"), "safe") and k.arrived("bigua"):
				k.order("bigua", "guide", _group("rosada")[0])
				_next(k, "bigua", "out to the two by the Casa Rosada")
		3:
			if k.arrived("bigua") and k.game.followers_of("bigua").size() == _group("rosada").size():
				k.order("bigua", "move", colectivo)
				_next(k, "bigua", "leads them to the colectivo")
		4:
			if _all(k, _group("rosada"), "safe") and k.arrived("bigua"):
				_next(k, "bigua", "the Casa Rosada's two in the colectivo")

## Juan Salvo: along the north of the square toward the tram, and the first cascarudo driven off as it comes at him;
## through the first wave to the Casa Rosada's gates, and the second driven off as it goes for the two who ran there; in
## the lull, those two to the colectivo.
func _salvo(k: Kit) -> void:
	var juan: Dictionary = k.unit("salvo")
	match int(step.salvo):
		0:
			if not bool(juan.away):
				k.order("salvo", "move", m(165.0, 45.0))
				_next(k, "salvo", "along the north of the square toward the tram")
		1:
			if _in_range(k, "c1", 28.0):
				k.order("salvo", "shoot", "c1")
				_next(k, "salvo", "fires at the cascarudo coming at him from the tram")
		2:
			if str(k.guard("c1").state) == "driven" and k.idle("salvo"):
				k.order("salvo", "move", m(240.0, 92.0))
				_next(k, "salvo", "through the wave to the Casa Rosada's gates")
		3:
			if _in_range(k, "c2", 28.0):
				k.order("salvo", "shoot", "c2")
				_next(k, "salvo", "fires at the cascarudo going for the ones at the gates")
		4:
			var runners: Array = _runners(k)
			if str(k.guard("c2").state) in ["driven", "away"] and k.idle("salvo") and runners.size() >= 2:
				k.order("salvo", "guide", runners[0])
				_next(k, "salvo", "to the two at the gates")
		5:
			var runners: Array = _runners(k)
			if k.arrived("salvo") and not k.game.followers_of("salvo").is_empty():
				if runners.is_empty():
					k.order("salvo", "move", m(203.5, 138.2))
					_next(k, "salvo", "leads them to the colectivo")
				else:
					k.order("salvo", "guide", runners[0])
		6:
			if k.arrived("salvo") and k.game.followers_of("salvo").is_empty():
				_next(k, "salvo", "the two from the gates in the colectivo")

## True when the creature is in the square, within `metres` of Juan Salvo, with nothing solid between them.
func _in_range(k: Kit, id: String, metres: float) -> bool:
	var beast: Dictionary = k.guard(id)
	if beast.is_empty() or not str(beast.state) in ["prowl", "stalk", "drawn", "stay"]: return false
	var here: Vector2 = k.at("salvo")
	return here.distance_to(k.at(id)) <= metres * 32.0 and k.game.line_of_sight(here, k.at(id))

## Those who panicked in the first wave and ran to the Casa Rosada's shut gates, still standing there.
func _runners(k: Kit) -> Array:
	var out: Array = []
	for p: Dictionary in k.game.people():
		var flee: Array = p.get("flee", [])
		if bool(p.panicked) and flee.size() >= 2 and float(flee[0]) > m(240.0, 0.0).x and str(p.state) == "crowd": out.append(str(p.id))
	return out

func _tick(k: Kit) -> void:
	_said(k)
	_benteveo(k)
	_hornero(k)
	_lechuza(k)
	_bigua(k)
	_salvo(k)
	for unit: Dictionary in k.game.units:
		coldest[str(unit.id)] = maxf(float(coldest.get(str(unit.id), 0.0)), float(unit.exposure))
	var juan: Dictionary = k.unit("salvo")
	if k.game.snow_level() == "wave" and not bool(juan.away) and k.game.shelter_at(Kit.Simulation.position_of(juan), false) == "":
		salvo_in_wave += Kit.STEP
	_said(k)

func _rescue() -> void:
	var k := Kit.new(mission, "rescue", verbose)
	k.after_step = _tick.bind(k)
	_tick(k)
	k.until(func() -> bool: return k.game.phase != "playing", float(mission.snowfall.bury) + 5.0, "the end")
	_log(k, "the end")
	_expect(k.problems.is_empty(), "every order taken: %s" % str(k.problems))
	_expect(k.game.phase == "won", "won (%s: %s)" % [k.game.phase, k.game.lost_reason])
	var counts: Dictionary = k.game.rescue_counts()
	_expect(int(counts.saved) == int(counts.total) and int(counts.lost) == 0, "everyone in the square brought in (%d of %d)" % [int(counts.saved), int(counts.total)])
	_expect(int(k.game.stats.get("fallen", 0)) == 0, "nobody fell (%d)" % int(k.game.stats.get("fallen", 0)))
	for unit: Dictionary in k.game.units:
		_expect(bool(unit.alive) and not bool(unit.fallen) and k.game.shelter_at(Kit.Simulation.position_of(unit), false) != "", "%s under cover at the end" % unit.id)
		_expect(float(coldest.get(str(unit.id), 0.0)) < 0.95, "%s never near falling (%.2f)" % [unit.id, float(coldest.get(str(unit.id), 0.0))])
	_expect(k.game.rigged.has("cabildo-lights") and k.game.rigged.has("subte-gate"), "the arcade lit and the service gate open")
	var where: Dictionary = {}
	for p: Dictionary in k.game.people(): where[str(p.shelter)] = int(where.get(str(p.shelter), 0)) + 1
	_expect(where.has("catedral") and where.has("tram") and where.has("subte-service") and where.has("colectivo"), "in the portico, the tram, the subte and the colectivo: %s" % str(where))
	_expect(not k.events_of("panic").is_empty(), "somebody panicked on the way")
	_expect(k.events_of("call").size() >= 4 and k.events_of("drive").size() >= 3, "the voice and the bell, the tram driven (%d calls, %d drives)" % [k.events_of("call").size(), k.events_of("drive").size()])
	# Juan Salvo and the cascarudos
	_expect(not k.events_of("arrival").is_empty() and str(k.events_of("arrival")[0].id) == "salvo", "Juan Salvo came in")
	_expect(salvo_in_wave > 20.0 and is_zero_approx(float(coldest.get("salvo", 1.0))), "he crossed the square in the first wave (%.0f s out in it) and took no cold (%.2f)" % [salvo_in_wave, float(coldest.get("salvo", 1.0))])
	var came: Array = []
	for e: Dictionary in k.events_of("creature"):
		if not bool(e.again): came.append(str(e.id))
	_expect(came == ["c1", "c2", "c3"], "the three cascarudos came up the avenues: %s" % str(came))
	var drawn_by_bell: bool = false
	for e: Dictionary in k.events_of("drawn"): drawn_by_bell = drawn_by_bell or (str(e.noise) == "bell" and "c1" in (e.ids as Array))
	_expect(drawn_by_bell, "the bell drew the first one to the tram")
	var hit: Array = []
	for e: Dictionary in k.events_of("creature_hit"): hit.append(str(e.id))
	_expect(hit == ["c1", "c2"] and int(k.game.stats.shots) == hit.size(), "Juan Salvo's rifle drove off the first and then the second, never missing (%s, %d shots)" % [str(hit), int(k.game.stats.shots)])
	var gone: Array = []
	for e: Dictionary in k.events_of("creature_gone"): gone.append(str(e.id))
	_expect("c1" in gone and "c2" in gone, "each went off the way it came: %s" % str(gone))
	var led: Array = []
	for e: Dictionary in k.events_of("guided"):
		if str(e.by) == "salvo": led.append_array(e.ids)
	_expect(led.size() == 2 and _all(k, led, "safe"), "he led the two from the Casa Rosada's gates in: %s" % str(led))
	_expect(k.events_of("struck").is_empty(), "nobody was knocked down")
	_expect(int(k.unit("salvo").ammo) == int(mission.units[4].gun.ammo) - int(k.game.stats.shots), "rounds left: %d" % int(k.unit("salvo").ammo))
	var earned: Array[String] = k.badges()
	_expect("everyone" in earned and "all_four" in earned and "swift" in earned, "every medal: %s" % str(earned))
	_expect(k.game.time < float(mission.parTime) and k.game.time < float(mission.snowfall.bury), "inside par (%.0f s of %d)" % [k.game.time, int(mission.parTime)])
	_expect(not k.game.buried_square, "done before the snow buried the square")
	print("rescue: %s in %d:%02d, saved %d of %d, medals %s" % [k.game.phase, floori(k.game.time / 60.0), int(k.game.time) % 60, int(counts.saved), int(counts.total), str(earned)])

func _said(k: Kit) -> void:
	said[str(k.game.message)] = true

## Everything the rescue said, as the Spanish game shows it: each line has its Spanish, and no piece of one is left in
## English.
func _spanish() -> void:
	Lang.use("es")
	Lang.record = true
	Lang.misses.clear()
	var english: Array[String] = []
	for message: String in said:
		if message != "" and Lang._wordy(message) and Lang.lookup(message) == message: english.append(message)
	_expect(said.size() > 12, "plenty of lines on the way (%d)" % said.size())
	_expect(english.is_empty() and Lang.misses.is_empty(), "every line of the rescue reads in Spanish: %s %s" % [str(english), str(Lang.misses.keys())])
	if verbose:
		for message: String in said: print("  ES  ", Lang.lookup(message))
	Lang.record = false
	Lang.use("en")
