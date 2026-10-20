extends RefCounted
## The scripted wins of Hora Cero's two levels, given order by order through the HUD's own select-and-perform, for the
## trailer director (horacero_director.gd) and the playtest (horacero_playtest.gd) to play in the real 3D scene. They are
## the plans of tests/plaza_playthrough.gd and tests/riachuelo_playthrough.gd (the source of truth: change those first),
## turned into steps that are looked at once per tick, so a caller that steps the rules itself (one frame, or a
## fast-forward) can drive them: call tick() before each step of the rules and trails() after it.
## Riachuelo's first part (the sergeant past, the ladder, over the cutting) waits in its test; here it is steps too.
const Kit = preload("res://tests/playthrough_kit.gd")

var sim: RefCounted
var k: Kit
var level: String = ""
## Print each step as it is taken.
var chatty: bool = true

func _init(game: RefCounted, which: String) -> void:
	sim = game
	level = which
	k = Kit.new({}, which, false, game)
	plan_reset()

## Kit.step()'s way-points for operatives sent off with follow(), advanced the same way (the kit does not step here).
func trails() -> void:
	for id: String in k.trails.keys():
		if k.idle(id):
			var point: Vector2 = k.trails[id].pop_front()
			if k.trails[id].is_empty(): k.trails.erase(id)
			k.order(id, "move", point)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

var step: Dictionary = {}
var _beam_last: float = 0.0
var cutting: int = 0

func plan_reset() -> void:
	step = {"benteveo": 0, "hornero": 0, "lechuza": 0, "bigua": 0, "salvo": 0, "lamps": 0, "rhornero": 0, "rbigua": 0}
	cutting = 0

func tick() -> void:
	if sim.phase != "playing": return
	if level == "plaza":
		_benteveo(); _hornero(); _lechuza(); _bigua(); _salvo()
	else:
		if cutting < 4: _cutting()
		else:
			_lamp_team(); _r_hornero(); _r_bigua()
			_beam_last = _heading("launch")

func _next(who: String, text: String) -> void:
	step[who] = int(step[who]) + 1
	if chatty: print("  t=%6.1f %s %d: %s  (%s)" % [sim.time, who, int(step[who]), text, sim.message])

func _group(name: String) -> Array:
	var ids: Array = []
	for p: Dictionary in sim.data.people:
		if str(p.group) == name: ids.append(str(p.id))
	return ids

func _all(ids: Array, state: String) -> bool:
	for id: String in ids:
		if str(sim.guard_by_id(id).state) != state: return false
	return true

func _lull() -> bool:
	return sim.snow_level() == "lull"

# --- the plaza (tests/plaza_playthrough.gd)
func _benteveo() -> void:
	var nw: Array = _group("nw")
	match int(step.benteveo):
		0:
			k.order("benteveo", "move", m(66.0, 46.0)); _next("benteveo", "out to the group by the Catedral")
		1:
			if k.arrived("benteveo"): k.order("benteveo", "call"); _next("benteveo", "shouts them over")
		2:
			if sim.followers_of("benteveo").size() == nw.size(): k.order("benteveo", "move", m(70.0, 14.0)); _next("benteveo", "leads them to the portico")
		3:
			if _all(nw, "safe") and k.arrived("benteveo"): _next("benteveo", "the Catedral's group under the portico")
		4:
			if _lull() and float(k.unit("benteveo").exposure) < 0.05: k.order("benteveo", "move", m(124.5, 78.0)); _next("benteveo", "out to the Pirámide in the lull")
		5:
			if k.arrived("benteveo"): k.order("benteveo", "call"); _next("benteveo", "shouts over the Pirámide's west side")
		6:
			if sim.followers_of("benteveo").size() >= 4: k.order("benteveo", "move", m(149.0, 84.0)); _next("benteveo", "round to its east side")
		7:
			if k.arrived("benteveo") and float(k.unit("benteveo").cooldown) <= 0.0: k.order("benteveo", "call"); _next("benteveo", "shouts over the east side")
		8:
			if sim.followers_of("benteveo").size() >= 6 and sim.vehicles.tram.to < 0 and sim.vehicle_rect("tram").position.x < m(140.0, 0.0).x:
				k.order("benteveo", "move", sim.vehicle_rect("tram").get_center() + m(2.0, 0.0)); _next("benteveo", "leads all six to the tram")
		9:
			if k.arrived("benteveo") and sim.followers_of("benteveo").is_empty(): _next("benteveo", "all six in the tram")

func _hornero() -> void:
	match int(step.hornero):
		0:
			k.order("hornero", "drive"); _next("hornero", "takes the tram on")
		1:
			if k.arrived("hornero"): k.order("hornero", "call"); _next("hornero", "rings for the palms")
		2:
			if k.arrived("hornero"): k.order("hornero", "drive"); _next("hornero", "straight on to the bank's stop")
		3:
			if k.arrived("hornero") and float(k.unit("hornero").cooldown) <= 0.0: k.order("hornero", "call"); _next("hornero", "rings for the flagpole")
		4:
			if _lull(): k.order("hornero", "drive"); _next("hornero", "back to the middle stop in the lull")
		5:
			if k.arrived("hornero"): _next("hornero", "waits at the middle stop")

func _lechuza() -> void:
	match int(step.lechuza):
		0:
			k.order("lechuza", "rig", "cabildo-lights"); _next("lechuza", "the arcade's fuse box")
		1:
			if k.arrived("lechuza"): k.order("lechuza", "rig", "subte-gate"); _next("lechuza", "to the service gate")
		2:
			if k.arrived("lechuza"): k.order("lechuza", "guide", _group("sw")[0]); _next("lechuza", "to the Cabildo's group")
		3:
			if k.arrived("lechuza") and sim.followers_of("lechuza").size() == _group("sw").size(): k.order("lechuza", "move", m(45.0, 129.5)); _next("lechuza", "leads them down the service stair")
		4:
			if _all(_group("sw"), "safe") and k.arrived("lechuza"): _next("lechuza", "the Cabildo's group in the subte")
		5:
			if _lull() and float(k.unit("lechuza").exposure) < 0.05: k.order("lechuza", "guide", _group("south")[0]); _next("lechuza", "out to the two in the south")
		6:
			if k.arrived("lechuza") and sim.followers_of("lechuza").size() == _group("south").size(): k.order("lechuza", "move", m(45.0, 129.5)); _next("lechuza", "leads them to the service stair")
		7:
			if _all(_group("south"), "safe") and k.arrived("lechuza"): _next("lechuza", "the south's two in the subte")

func _bigua() -> void:
	var colectivo: Vector2 = m(203.5, 138.2)
	match int(step.bigua):
		0:
			k.order("bigua", "guide", _group("belgrano")[0]); _next("bigua", "out to the Belgrano monument")
		1:
			if k.arrived("bigua") and sim.followers_of("bigua").size() == _group("belgrano").size(): k.order("bigua", "move", colectivo); _next("bigua", "leads them to the colectivo")
		2:
			if _all(_group("belgrano"), "safe") and k.arrived("bigua"): k.order("bigua", "guide", _group("rosada")[0]); _next("bigua", "out to the two by the Casa Rosada")
		3:
			if k.arrived("bigua") and sim.followers_of("bigua").size() == _group("rosada").size(): k.order("bigua", "move", colectivo); _next("bigua", "leads them to the colectivo")
		4:
			if _all(_group("rosada"), "safe") and k.arrived("bigua"): _next("bigua", "the Casa Rosada's two in the colectivo")

func _salvo() -> void:
	var juan: Dictionary = k.unit("salvo")
	match int(step.salvo):
		0:
			if not bool(juan.away): k.order("salvo", "move", m(165.0, 45.0)); _next("salvo", "along the north of the square toward the tram")
		1:
			if _in_range("c1", 28.0): k.order("salvo", "shoot", "c1"); _next("salvo", "fires at the cascarudo coming at him from the tram")
		2:
			if str(k.guard("c1").state) == "driven" and k.idle("salvo"): k.order("salvo", "move", m(240.0, 92.0)); _next("salvo", "through the wave to the Casa Rosada's gates")
		3:
			if _in_range("c2", 28.0): k.order("salvo", "shoot", "c2"); _next("salvo", "fires at the cascarudo going for the ones at the gates")
		4:
			var runners: Array = _runners()
			if str(k.guard("c2").state) in ["driven", "away"] and k.idle("salvo") and runners.size() >= 2: k.order("salvo", "guide", runners[0]); _next("salvo", "to the two at the gates")
		5:
			var runners: Array = _runners()
			if k.arrived("salvo") and not sim.followers_of("salvo").is_empty():
				if runners.is_empty(): k.order("salvo", "move", m(203.5, 138.2)); _next("salvo", "leads them to the colectivo")
				else: k.order("salvo", "guide", runners[0])
		6:
			if k.arrived("salvo") and sim.followers_of("salvo").is_empty(): _next("salvo", "the two from the gates in the colectivo")

func _in_range(id: String, metres: float) -> bool:
	var beast: Dictionary = k.guard(id)
	if beast.is_empty() or not str(beast.state) in ["prowl", "stalk", "drawn", "stay"]: return false
	var here: Vector2 = k.at("salvo")
	return here.distance_to(k.at(id)) <= metres * 32.0 and sim.line_of_sight(here, k.at(id))

func _runners() -> Array:
	var found: Array = []
	for p: Dictionary in sim.people():
		var flee: Array = p.get("flee", [])
		if bool(p.panicked) and flee.size() >= 2 and float(flee[0]) > m(240.0, 0.0).x and str(p.state) == "crowd": found.append(str(p.id))
	return found

# --- Riachuelo (tests/riachuelo_playthrough.gd), its first part as steps
func _g(id: String) -> Vector2:
	return k.at(id) / 32.0

func _heading(id: String) -> float:
	return fposmod(rad_to_deg(float(k.guard(id).angle)), 360.0)

func _there(ids: Array) -> bool:
	for id: String in ids:
		if not k.arrived(id): return false
	return true

func _sergeant_gone_east(x: float) -> bool:
	var at: Vector2 = _g("sergeant")
	return (absf(at.y - 42.0) < 1.0 and at.x > x) or (absf(at.x - 123.0) < 1.0 and at.y > 44.0 and at.y < 96.0)

func _machine_away(x: float, gap: float = 8.0) -> bool:
	return absf(_g("machine").x - x) > gap

func _cutting() -> void:
	match cutting:
		0:
			if _sergeant_gone_east(112.0):
				k.follow("lechuza", [m(110.0, 17.5), m(110.0, 21.0), m(105.0, 29.2)])
				k.follow("hornero", [m(109.6, 17.5), m(109.6, 21.0), m(103.8, 28.6)])
				k.follow("benteveo", [m(110.4, 17.5), m(110.4, 21.0), m(106.2, 28.6)])
				k.follow("bigua", [m(110.2, 17.5), m(110.2, 21.0), m(104.6, 28.0)])
				cutting = 1
				print("  t=%6.1f sergeant past: to the edge of the cutting" % sim.time)
		1:
			if _there(["lechuza", "hornero", "benteveo", "bigua"]):
				k.order("lechuza", "rig", "ladder")
				cutting = 2
				print("  t=%6.1f at the edge: the ladder" % sim.time)
		2:
			if k.idle("lechuza") and sim.rigged.has("ladder"):
				k.follow("lechuza", [m(105.4, 38.6), m(114.0, 38.8)])
				k.follow("benteveo", [m(104.6, 38.6), m(116.4, 38.8)])
				k.follow("hornero", [m(105.0, 38.8), m(104.0, 45.4), m(84.0, 45.4), m(82.6, 47.0)])
				k.follow("bigua", [m(104.4, 38.8), m(103.4, 45.2), m(84.0, 45.0), m(81.6, 47.4)])
				cutting = 3
				print("  t=%6.1f the ladder set: down, over and up" % sim.time)
		3:
			if _there(["lechuza", "hornero", "benteveo", "bigua"]):
				cutting = 4
				print("  t=%6.1f over the cutting (alarms %d)" % [sim.time, int(sim.stats.alarms)])

func _lamp_team() -> void:
	match int(step.lamps):
		0:
			if _g("middle").y > 66.0 and _g("middle").x < 119.0 and _heading("middle") > 135.0 and _heading("middle") < 225.0:
				k.follow("lechuza", [m(121.0, 46.5), m(121.0, 66.0), m(121.0, 95.6), m(122.2, 96.6)])
				k.follow("benteveo", [m(120.6, 46.5), m(120.6, 66.0), m(120.6, 95.0)])
				_next("lamps", "down the tram street")
		1:
			if k.arrived("lechuza"): k.order("lechuza", "sabotage"); _next("lamps", "at the board")
		2:
			if sim.radio_cut and k.idle("lechuza"):
				k.follow("lechuza", [m(130.0, 96.0), m(141.0, 95.0)])
				k.follow("benteveo", [m(130.0, 95.4), m(143.0, 94.8)])
				_next("lamps", "lamps out")
		3:
			if _there(["lechuza", "benteveo"]): _next("lamps", "in the doorway by the landing")
		4:
			if sim.rigged.has("gondola") and _machine_away(146.0, 9.0):
				k.follow("lechuza", [m(144.6, 100.0), m(146.6, 108.6), m(148.0, 112.0), m(148.0, 136.0)])
				k.follow("benteveo", [m(145.2, 100.4), m(147.0, 108.8), m(149.0, 112.0), m(149.0, 136.4)])
				_next("lamps", "to the gondola")
		5:
			if _there(["lechuza", "benteveo"]):
				k.follow("lechuza", [m(140.0, 138.0), m(101.0, 139.0), m(99.0, 144.0)])
				k.follow("benteveo", [m(140.0, 138.6), m(101.6, 139.6), m(101.0, 144.6)])
				_next("lamps", "on the far bank")

func _r_hornero() -> void:
	match int(step.rhornero):
		0:
			if str(k.guard("alley").state) == "dead": k.follow("hornero", [m(82.6, 80.0), m(81.0, 87.0)]); _next("rhornero", "to the café's back door")
		1:
			if k.arrived("hornero"): k.order("hornero", "unlock"); _next("rhornero", "the cellar door")
		2:
			if sim.door_open and k.idle("hornero"): k.follow("hornero", [m(75.0, 87.0)]); _next("rhornero", "the cellar is open")
		3:
			var middle: Vector2 = _g("middle")
			if k.arrived("hornero") and absf(middle.x - 123.0) < 1.0 and middle.y > 76.0 and _heading("middle") > 45.0 and _heading("middle") < 135.0:
				k.follow("hornero", [m(81.0, 87.0), m(82.4, 70.0), m(84.5, 67.0), m(119.5, 67.0)]); _next("rhornero", "up the alley")
		4:
			if k.arrived("hornero"):
				k.stance("hornero", "walk")
				k.follow("hornero", [m(121.6, 70.0), m(121.6, 102.0), m(144.6, 103.0)]); _next("rhornero", "down the tram lines")
		5:
			if k.arrived("hornero") and sim.radio_cut and int(step.lamps) >= 4 and _machine_away(146.0, 8.0):
				k.stance("hornero", "sneak")
				k.follow("hornero", [m(146.2, 106.4), m(147.2, 108.9)]); _next("rhornero", "onto the dark landing")
		6:
			if k.arrived("hornero"): k.order("hornero", "rig", "gondola"); _next("rhornero", "the gondola's controls")
		7:
			if sim.rigged.has("gondola") and k.idle("hornero"):
				k.follow("hornero", [m(150.6, 112.0), m(150.4, 136.0), m(140.0, 139.0), m(102.0, 140.0), m(100.4, 145.6)]); _next("rhornero", "across and along the far bank")

func _r_bigua() -> void:
	match int(step.rbigua):
		0:
			var alley: Vector2 = _g("alley")
			if alley.y > 66.5 and alley.y < 70.0 and _heading("alley") > 60.0 and _heading("alley") < 120.0: k.order("bigua", "takedown", "alley"); _next("rbigua", "after the alley's patrolman")
		1:
			if str(k.guard("alley").state) == "dead" and k.idle("bigua"): k.order("bigua", "pickup", "alley"); _next("rbigua", "the knife")
		2:
			if str(k.unit("bigua").carrying) != "": k.order("bigua", "drop", m(83.3, 74.0)); _next("rbigua", "carrying him to the doorway")
		3:
			if k.idle("bigua") and str(k.unit("bigua").carrying) == "" and sim.door_open: k.order("bigua", "rescue"); _next("rbigua", "the passenger")
		4:
			if bool(sim.prisoner.freed) and k.idle("bigua"): k.follow("bigua", [m(78.0, 87.0), m(81.2, 87.0), m(83.2, 74.4)]); _next("rbigua", "the passenger out, up the alley")
		5:
			var west: Vector2 = _g("west")
			if k.arrived("bigua") and _sergeant_gone_east(64.0) and west.y < 56.0 and _heading("west") > 225.0 and _heading("west") < 315.0:
				k.stance("bigua", "walk")
				k.follow("bigua", [m(82.2, 70.0), m(80.0, 67.4), m(56.4, 67.4), m(53.8, 70.0), m(53.8, 99.4), m(48.0, 102.6), m(36.0, 103.4), m(33.4, 107.0)]); _next("rbigua", "the escort to the boats")
		6:
			if k.arrived("bigua") and bool(sim.prisoner.hidden): k.stance("bigua", "sneak"); _next("rbigua", "among the boats by the shed")
		7:
			var beam: float = _heading("launch")
			if beam > 216.0 and beam < 240.0 and beam > _beam_last: k.order("bigua", "rig", "boat"); _next("rbigua", "the boat down the slip")
		8:
			if sim.rigged.has("boat") and k.idle("bigua"):
				k.stance("bigua", "walk")
				k.follow("bigua", [m(45.0, 111.0), m(45.0, 136.4), m(60.0, 139.0), m(97.0, 140.0), m(99.0, 145.0)]); _next("rbigua", "rowing over")
