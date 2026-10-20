extends SceneTree
## The rules of the Plaza de Mayo prologue (data/plaza.json), one at a time, mostly on a quiet square (nobody out in the
## snow unless a check needs them): the layout and the grid (every shelter, every person and every flee point can be
## reached, the service stair only once its gate is open), the snowfall's schedule, waves and lulls, the cold (out in
## the snow, under cover, under a cloth), falling and being helped up or carried in, being lost to the snow, leading
## people in (the chain, the lead limit, the dark arcade), panics, Benteveo's voice and Hornero's bell, the tram, the
## arcade's lights and the service gate, the end (won early, won or lost at the burial, lost with too few or with the
## whole squad), the medals, every order of every operative answered without a crash, checkpoints, what the HUD is told,
## and the operation's place on file. Juan Salvo: out of play until he comes, then in from the edge; his suit (no cold,
## not even in a wave; knocked down, up again by himself), his carrying, his rifle. The cascarudos: when they come and
## from where, what they sense and go for, knocking people down, the ground they keep to (out of every shelter and every
## vehicle, round everything solid), noise drawing them (the bell, a shout, a shot), a hit driving one off and three
## killing it, and their place in a checkpoint and in what the HUD is told.
## Run: godot --headless --path godot --script res://tests/plaza_rules.gd
const Simulation = preload("res://scripts/simulation.gd")
const Missions = preload("res://scripts/missions.gd")

var data: Dictionary
var world: Dictionary
var checks: int = 0
var failures: int = 0
var section: String = ""

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/plaza.json"))
	world = data.plazaWorld
	call_deferred("_run")

func _expect(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL [%s]: %s" % [section, explanation])

func _run() -> void:
	for part: String in ["layout", "reachable", "snowfall", "cold", "falling", "leading", "dark_arcade", "panic", "voice", "bell",
			"tram", "carrying", "canvas", "lights_and_gate", "the_end", "burial", "medals", "every_order", "checkpoints",
			"hud_queries", "salvo", "suit", "salvo_carries", "rifle", "creatures_come", "creature_senses", "creature_ground",
			"creature_noise", "creature_checkpoint", "other_operations", "on_file"]:
		section = part
		call("_" + part)
	print("Plaza rules: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## A started, running mission; quiet: nobody out in the snow (the people taken away) unless asked, but for one
## stand-by in the far corner, so that a check that brings everyone else in does not end the night; nobody needed.
func _fresh(quiet: bool = true) -> RefCounted:
	var sim: RefCounted = Simulation.new(data)
	sim.start()
	sim.toggle_pause()
	if quiet:
		sim.guards.clear()
		sim.data.snowfall["need"] = 0
		_person(sim, STANDBY, m(238.0, 129.0), 0.0)
	return sim

const STANDBY := "p26"

## The people of a quiet square but the stand-by.
func _others(sim: RefCounted) -> Array:
	return sim.people().filter(func(p: Dictionary) -> bool: return str(p.id) != STANDBY)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _put(sim: RefCounted, id: String, at: Vector2) -> void:
	var actor: Dictionary = sim.unit_by_id(id)
	if actor.is_empty(): actor = sim.guard_by_id(id)
	actor.x = at.x
	actor.y = at.y
	actor.path = []

func _run_for(sim: RefCounted, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.001 and sim.phase == "playing":
		sim.update(0.05)
		t += 0.05

func _until(sim: RefCounted, done: Callable, limit: float) -> bool:
	var t: float = 0.0
	while t < limit and sim.phase == "playing":
		if done.call(): return true
		sim.update(0.05)
		t += 0.05
	return done.call()

func _events(sim: RefCounted, type: String) -> Array:
	var list: Array = []
	for event: Dictionary in sim.events:
		if str(event.get("type", "")) == type: list.append(event)
	return list

func _objective_done(sim: RefCounted, id: String) -> bool:
	for o: Dictionary in sim.objectives:
		if str(o.id) == id: return bool(o.done)
	return false

## A person of the data put back on the square (the quiet square has none), standing where he is told.
func _person(sim: RefCounted, id: String, at: Vector2 = Vector2.INF, chill: float = 0.0) -> Dictionary:
	for spec: Dictionary in data.people:
		if str(spec.id) == id:
			var p: Dictionary = sim._make_person(spec)
			if at.is_finite():
				p.x = at.x
				p.y = at.y
			p.exposure = chill
			sim.guards.append(p)
			return sim.guard_by_id(id)
	return {}

## Everyone of the squad but these parked under the Catedral's portico, out of the way.
func _park(sim: RefCounted, keep: Array) -> void:
	var i: int = 0
	for unit: Dictionary in sim.units:
		if str(unit.id) in keep: continue
		_put(sim, str(unit.id), m(60.0 + 3.0 * float(i), 15.5))
		i += 1

func _shelter_of(sim: RefCounted, point: Vector2) -> String:
	return sim.shelter_at(point, true)

func _rig(sim: RefCounted, id: String, by: String) -> void:
	sim.rigged[id] = by
	sim._geometry_dirty = true

## Snow of a fixed strength for a check (the schedule replaced by one flat line).
func _steady(sim: RefCounted, strength: float) -> void:
	sim.data.snowfall.schedule = [[0.0, strength], [10000.0, strength]]

# --- the layout ----------------------------------------------------------------------------------------------
func _layout() -> void:
	var sim: RefCounted = _fresh(false)
	_expect(str(data.theme) == "plaza" and str(data.id) == "plaza-05" and sim.rescue_on, "the plaza theme, a rescue")
	_expect(sim.units.size() == 5 and sim.unit_by_id("hornero").name == "Hornero" and sim.unit_by_id("bigua").name == "Biguá", "the four neighbours of Riachuelo")
	_expect(sim.unit_by_id("salvo").name == "Juan Salvo" and str(sim.unit_by_id("salvo").look) == "art:juan_salvo", "and Juan Salvo, dressed from the art pack's slot")
	_expect(sim.people().size() == data.people.size() and data.people.size() >= 24, "the people of the square on the guards' list (%d)" % sim.people().size())
	_expect(not sim.has_prisoner and not data.has("door") and not data.has("extraction"), "no prisoner, no cell, no boat")
	for person: Dictionary in sim.people():
		_expect(str(person.state) == "crowd" and str(person.kind) == "person" and bool(person.civilian) and not str(person.state) in [] , "%s stands in the square" % person.id)
		_expect(not sim.is_blocked(Simulation.position_of(person)), "%s stands on open ground" % person.id)
		_expect(sim.shelter_at(Simulation.position_of(person), false) == "", "%s is out in the snow" % person.id)
		_expect(str(person.get("look", "")).begins_with("vecin"), "%s wears one of the barrio's figures (%s)" % [person.id, person.look])
		var flee: Array = person.get("flee", [])
		if flee.size() >= 2:
			var to := Vector2(float(flee[0]), float(flee[1]))
			_expect(not sim.is_blocked(to) and sim.shelter_at(to, false) == "", "%s's flee point is open ground out in the snow" % person.id)
	for unit: Dictionary in sim.units:
		if bool(unit.get("away", false)): continue  # Juan Salvo, not here yet (_salvo)
		_expect(sim.shelter_at(Simulation.position_of(unit), false) != "", "%s starts under cover (%s)" % [unit.id, sim.shelter_at(Simulation.position_of(unit), false)])
		_expect(not sim.is_blocked(Simulation.position_of(unit)), "%s starts on open ground" % unit.id)
		_expect(str(unit.stance) == "walk", "%s starts upright: nobody to hide from" % unit.id)
	_expect(sim.shelter_at(Simulation.position_of(sim.unit_by_id("hornero")), false) == "tram", "Hornero at the tram's controls")
	_expect(sim.shelter_at(Simulation.position_of(sim.unit_by_id("lechuza")), false) == "cabildo", "Lechuza under the Cabildo's arcade")
	_expect(sim.shelter_at(Simulation.position_of(sim.unit_by_id("benteveo")), false) == "catedral", "Benteveo on the Catedral's portico")
	_expect(sim.shelter_at(Simulation.position_of(sim.unit_by_id("bigua")), false) == "colectivo", "Biguá on the colectivo")
	for shelter: Dictionary in sim.shelters():
		var inside: Vector2 = sim.shelter_inside(shelter)
		_expect(sim.shelter_rect(shelter).has_point(inside), "%s's inside point is inside it" % shelter.id)
		_expect(not sim.is_blocked(inside), "%s's inside point is open ground" % shelter.id)
	for canvas: Dictionary in sim.canvases():
		_expect(not sim.is_blocked(Vector2(float(canvas.x), float(canvas.y))), "the %s lies on open ground" % canvas.id)
	# the landmarks where they stand in the square, and as big as they are
	var by_id: Dictionary = {}
	for o: Dictionary in data.obstacles: by_id[str(o.id)] = o
	var pyramid: Rect2 = Simulation.rect_of(by_id.piramide)
	_expect(pyramid.get_center().distance_to(m(142.0, 84.0)) < 2.0, "the Pirámide in the middle of the square")
	_expect(Simulation.rect_of(by_id["casa-rosada"]).position.x >= m(256.0, 0.0).x, "the Casa Rosada along the east side, beyond Balcarce")
	_expect(Simulation.rect_of(by_id.cabildo).end.x <= m(28.0, 0.0).x and Simulation.rect_of(by_id.catedral).position.y < m(0.0, 22.0).y, "the Cabildo on the west, the Catedral on the north")
	var palms: int = 0
	var columns: int = 0
	for o: Dictionary in data.obstacles:
		if str(o.id).begins_with("palm-"): palms += 1
		if str(o.id).begins_with("column-"): columns += 1
	_expect(palms == 8 and columns == 12, "eight palms and the portico's twelve columns (%d, %d)" % [palms, columns])
	_expect(world.archPiers.size() == 6, "five arches between six piers")
	var w: float = float(data.plazaWorld.plaza[2]) - float(data.plazaWorld.plaza[0])
	var h: float = float(data.plazaWorld.plaza[3]) - float(data.plazaWorld.plaza[1])
	_expect(absf(w - 200.0) < 1.0 and absf(h - 96.0) < 5.0, "the square about 200 x 100 m (%.0f x %.0f)" % [w, h])

## Every shelter, person, flee point and cloth can be reached from the middle of the square; the service stair only
## once its gate is open.
func _reachable() -> void:
	var sim: RefCounted = _fresh()
	var from: Vector2 = m(142.0, 70.0)
	for shelter: Dictionary in sim.shelters():
		var inside: Vector2 = sim.shelter_inside(shelter)
		var open: bool = not sim.find_path(from, inside).is_empty()
		if str(shelter.id) == "subte-service": _expect(not open, "the service stair is shut behind its gate")
		else: _expect(open, "%s can be reached from the square" % shelter.id)
	for spec: Dictionary in data.people:
		_expect(not sim.find_path(from, Vector2(float(spec.x), float(spec.y))).is_empty(), "%s can be reached" % spec.id)
	for canvas: Dictionary in sim.canvases():
		_expect(not sim.find_path(from, Vector2(float(canvas.x), float(canvas.y))).is_empty(), "the %s can be reached" % canvas.id)
	_rig(sim, "subte-gate", "lechuza")
	_expect(not sim.find_path(from, sim.shelter_inside(sim.shelter_by_id("subte-service"))).is_empty(), "the gate open, the service stair can be reached")
	# the Casa Rosada's gates are shut: nobody walks in under its arch
	_expect(sim.is_blocked(m(258.0, 85.0)), "the Casa Rosada's arch is shut")

# --- the snow ------------------------------------------------------------------------------------------------
func _snowfall() -> void:
	var sim: RefCounted = _fresh()
	var schedule: Array = data.snowfall.schedule
	_expect(is_equal_approx(sim.snow_intensity(0.0), float(schedule[0][1])), "the first flakes at the start")
	for point: Array in schedule:
		_expect(is_equal_approx(sim.snow_intensity(float(point[0])), float(point[1])), "the schedule at %.0f s" % float(point[0]))
	var mid: float = (float(schedule[1][0]) + float(schedule[2][0])) * 0.5
	_expect(sim.snow_intensity(mid) > float(schedule[1][1]) and sim.snow_intensity(mid) < float(schedule[2][1]), "in between, in between")
	var waves: int = 0
	var lulls: int = 0
	var was: String = ""
	var t: float = 0.0
	while t < sim.bury_time():
		var level: String = sim.snow_level(t)
		if level != was:
			if level == "wave": waves += 1
			if level == "lull": lulls += 1
			was = level
		t += 1.0
	_expect(waves >= 3 and lulls >= 2, "heavier waves and lulls to wait for (%d waves, %d lulls)" % [waves, lulls])
	_expect(sim.next_wave() > 0.0 and sim.snow_level(sim.time + sim.next_wave() + 0.05) == "wave", "the next wave can be seen coming (%.1f s)" % sim.next_wave())
	_expect(absf(sim.bury_time() - float(data.snowfall.bury)) < 0.01 and sim.bury_left() > 400.0, "the square is buried at %.0f s" % sim.bury_time())
	# the snow's messages as it turns
	sim.time = float(schedule[3][0]) + 2.0
	sim.update(0.05)
	sim.events.clear()
	_run_for(sim, float(schedule[4][0]) - float(schedule[3][0]))
	_expect(not _events(sim, "snowfall").is_empty() and str(_events(sim, "snowfall")[0].level) == "wave", "a wave comes: event snowfall wave")
	_expect(not data.has("guards") or (data.guards as Array).is_empty(), "nobody on guard: no cones, no alarms")

func _cold() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 1.0)
	var hornero: Dictionary = sim.unit_by_id("hornero")
	_put(sim, "hornero", m(142.0, 60.0))
	_run_for(sim, 10.0)
	var rate: float = float(data.snowfall.rate.unit)
	_expect(absf(float(hornero.exposure) - 10.0 / rate) < 0.02, "out in steady snow the cold rises: %.3f after 10 s (rate %.0f)" % [float(hornero.exposure), rate])
	_steady(sim, 2.0)
	var before: float = float(hornero.exposure)
	_run_for(sim, 5.0)
	_expect(absf(float(hornero.exposure) - before - 10.0 / rate) < 0.02, "twice as fast in a wave twice as strong")
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	before = float(lechuza.exposure)
	_expect(is_zero_approx(before), "Lechuza under the arcade has taken no cold")
	_put(sim, "hornero", m(70.0, 14.0))
	var cold: float = float(hornero.exposure)
	_run_for(sim, 5.0)
	_expect(float(hornero.exposure) < cold - 0.1, "under cover it drains (%.2f -> %.2f)" % [cold, float(hornero.exposure)])
	# the dark arcade keeps the snow off the squad all the same
	_put(sim, "hornero", m(25.8, 108.0))
	cold = float(hornero.exposure)
	_run_for(sim, 2.0)
	_expect(float(hornero.exposure) < cold, "the dark arcade keeps the snow off the squad")
	# people take it more slowly than the squad, and the HUD can read it
	var p: Dictionary = _person(sim, "p1", m(142.0, 60.0), 0.0)
	_steady(sim, 1.0)
	_run_for(sim, 10.0)
	_expect(absf(float(p.exposure) - 10.0 / float(data.snowfall.rate.person)) < 0.02, "a person out in the snow: %.3f after 10 s" % float(p.exposure))

func _falling() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 1.0)
	var bigua: Dictionary = sim.unit_by_id("bigua")
	_put(sim, "bigua", m(150.0, 60.0))
	bigua.exposure = 0.99
	sim.events.clear()
	_run_for(sim, 1.0)
	_expect(bool(bigua.fallen) and bool(bigua.alive) and float(bigua.fall_left) > 40.0, "full of cold, he falls: alive, %.0f s to get him up" % float(bigua.fall_left))
	_expect(not _events(sim, "fallen").is_empty() and bool(_events(sim, "fallen")[0].unit), "event fallen")
	sim.select("bigua")
	_expect(not sim.move_to(m(160.0, 60.0)) and sim.message.contains("down"), "a fallen man takes no orders (%s)" % sim.message)
	# a mate helps him up
	_put(sim, "hornero", m(146.0, 60.0))
	sim.select("hornero")
	_expect(sim.perform("help", "bigua"), "Hornero goes to help him up")
	_run_for(sim, 3.0)
	_expect(not bool(bigua.fallen) and bool(bigua.alive) and absf(float(bigua.exposure) - float(data.snowfall.get("helped", 0.7))) < 0.08, "on his feet again, chilled through (%.2f)" % float(bigua.exposure))
	# nobody comes: lost to the snow
	bigua.exposure = 0.999
	_run_for(sim, 0.5)
	_expect(bool(bigua.fallen), "he falls again")
	sim.unit_by_id("hornero").x = m(70.0, 14.0).x
	sim.unit_by_id("hornero").y = m(70.0, 14.0).y
	sim.events.clear()
	_run_for(sim, float(data.snowfall.grace.unit) + 1.0)
	_expect(not bool(bigua.alive) and bool(bigua.buried) and not bool(bigua.fallen), "nobody got to him: the snow covered him")
	_expect(not _events(sim, "buried").is_empty() and int(sim.stats.squad_lost) == 1, "event buried, one of the squad lost")
	_expect(sim.phase == "playing", "the operation goes on without him")

func _leading() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	# group "nw" by the Catedral: three of them
	var ids: Array = []
	for spec: Dictionary in data.people:
		if str(spec.group) == "nw":
			ids.append(str(spec.id))
			_person(sim, str(spec.id), Vector2.INF, 0.1)
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	sim.select("benteveo")
	_expect(sim.perform("guide", ids[0]), "Benteveo goes to lead %s in" % ids[0])
	_until(sim, func() -> bool: return sim.followers_of("benteveo").size() > 0, 30.0)
	var chain: Array = sim.followers_of("benteveo")
	_expect(chain.size() == ids.size(), "the whole group falls in behind him (%d)" % chain.size())
	_expect(str(chain[0].id) == ids[0], "the one he went to first, first behind him")
	sim.perform("move", m(70.0, 14.0))
	_until(sim, func() -> bool: return sim.rescue_counts().saved == ids.size(), 60.0)
	_expect(int(sim.rescue_counts().saved) == ids.size(), "under the portico, all three saved (%d)" % int(sim.rescue_counts().saved))
	for id: String in ids:
		var p: Dictionary = sim.guard_by_id(id)
		_expect(str(p.state) == "safe" and str(p.shelter) == "catedral", "%s is under the Catedral's portico" % id)
	_run_for(sim, 4.0)
	var spots: Dictionary = {}
	for id: String in ids:
		var p: Dictionary = sim.guard_by_id(id)
		spots[Vector2i(Simulation.position_of(p) / 8.0)] = true
		_expect(sim.shelter_at(Simulation.position_of(p), true) == "catedral" and not sim.is_blocked(Simulation.position_of(p)), "%s went in to a spot of his own" % id)
	_expect(spots.size() == ids.size(), "each on a spot of his own")
	_expect(not _events(sim, "saved").is_empty() and not _events(sim, "guided").is_empty(), "events guided and saved")
	# a person under cover gets warm again
	var p1: Dictionary = sim.guard_by_id(ids[0])
	_expect(float(p1.exposure) < 0.1, "warm again under cover (%.2f)" % float(p1.exposure))
	_expect(not sim.perform("guide", ids[0]) and sim.message.contains("already"), "nobody leads someone already under cover in again")
	# as many as he can lead and no more
	var sim2: RefCounted = _fresh()
	_steady(sim2, 0.5)
	var lechuza: Dictionary = sim2.unit_by_id("lechuza")
	var n: int = 0
	for spec: Dictionary in data.people:
		if str(spec.id) == STANDBY: continue
		_person(sim2, str(spec.id), m(60.0 + 2.0 * float(n % 6), 100.0 + 2.0 * float(n / 6)), 0.0)
		n += 1
		if n >= 6: break
	sim2.guard_by_id("p1").group = "solo"
	_put(sim2, "lechuza", m(58.0, 98.0))
	sim2.select("lechuza")
	var people: Array = _others(sim2)
	for p: Dictionary in people:
		p.group = ""
	for i: int in range(people.size()):
		var ok: bool = sim2.perform("guide", str(people[i].id))
		if i < int(data.units[1].get("lead", 4)):
			_expect(ok, "Lechuza can lead %d" % (i + 1))
			_until(sim2, func() -> bool: return lechuza.order.is_empty(), 10.0)
		else:
			_expect(not ok and sim2.message.contains("as many"), "but not %d at once (%s)" % [i + 1, sim2.message])
	# the chain: each walks behind the one in front of him
	sim2.perform("move", m(120.0, 100.0))
	_run_for(sim2, 6.0)
	var chain2: Array = sim2.followers_of("lechuza")
	var orderly: bool = true
	for i: int in range(1, chain2.size()):
		var gap: float = Simulation.position_of(chain2[i]).distance_to(Simulation.position_of(chain2[i - 1]))
		if gap > 60.0: orderly = false
	_expect(chain2.size() == 4 and orderly, "they walk one behind the other (%d)" % chain2.size())
	_expect(Simulation.position_of(chain2[0]).distance_to(Simulation.position_of(lechuza)) < 50.0, "the first close behind him")
	# another operative can take one over
	_put(sim2, "hornero", Simulation.position_of(chain2[3]) + Vector2(20.0, 0.0))
	sim2.select("hornero")
	_expect(sim2.perform("guide", str(chain2[3].id)), "Hornero takes over the last of them")
	_run_for(sim2, 1.5)
	_expect(sim2.followers_of("hornero").size() == 1 and sim2.followers_of("lechuza").size() == 3, "one behind Hornero now, three behind Lechuza")
	# the leader falls: they stand where they are
	lechuza.exposure = 0.999
	_steady(sim2, 1.0)
	_run_for(sim2, 0.3)
	_expect(bool(lechuza.fallen) and sim2.followers_of("lechuza").is_empty(), "Lechuza falls: nobody follows him now")
	for p: Dictionary in _others(sim2):
		if str(p.id) != str(chain2[3].id): _expect(str(p.state) == "crowd", "%s stands where he was left" % p.id)

func _dark_arcade() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	var ids: Array = []
	for spec: Dictionary in data.people:
		if str(spec.group) == "sw":
			ids.append(str(spec.id))
			_person(sim, str(spec.id), Vector2.INF, 0.1)
	_expect(not sim.shelter_open(sim.shelter_by_id("cabildo")) and sim._dark_at(m(25.8, 108.0)), "the arcade is dark")
	sim.select("lechuza")
	_put(sim, "lechuza", m(66.0, 112.0))
	_expect(sim.perform("guide", ids[0]), "Lechuza leads the group by the Cabildo")
	_until(sim, func() -> bool: return sim.followers_of("lechuza").size() == ids.size(), 20.0)
	sim.perform("move", m(25.8, 112.0))
	_run_for(sim, 30.0)
	var outside: bool = true
	for id: String in ids:
		var p: Dictionary = sim.guard_by_id(id)
		if str(p.state) != "follow" or sim._dark_at(Simulation.position_of(p)): outside = false
	_expect(outside, "nobody follows him into the dark: they stop at its edge, out in the snow")
	_expect(int(sim.rescue_counts().saved) == 0, "nobody saved in the dark")
	# Lechuza puts the lights back
	sim.select("lechuza")
	_expect(sim.perform("rig", "cabildo-lights"), "Lechuza goes to the fuse box")
	_until(sim, func() -> bool: return sim.rigged.has("cabildo-lights"), 20.0)
	_expect(sim.shelter_open(sim.shelter_by_id("cabildo")) and _objective_done(sim, "lights"), "the arcade's lamps are on (objective lights)")
	sim.perform("move", m(25.6, 116.0))
	_until(sim, func() -> bool: return sim.rescue_counts().saved == ids.size(), 30.0)
	_expect(int(sim.rescue_counts().saved) == ids.size(), "now they go in under the arches (%d)" % int(sim.rescue_counts().saved))
	for id: String in ids:
		_expect(str(sim.guard_by_id(id).shelter) == "cabildo", "%s under the Cabildo's arcade" % id)
	sim.select("benteveo")
	_expect(not sim.perform("rig", "cabildo-lights"), "only Lechuza knows the fuse box")

func _panic() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	# a scheduled panic: he runs off to his flee point when his time comes, if nobody has him yet
	var runner: Dictionary = {}
	for spec: Dictionary in data.people:
		if spec.has("panic"):
			runner = _person(sim, str(spec.id))
			break
	_expect(not runner.is_empty(), "somebody in the square panics at a set time")
	sim.time = float(runner.panic.at) - 0.5
	sim.events.clear()
	_run_for(sim, 1.0)
	_expect(str(runner.state) == "panic" and not _events(sim, "panic").is_empty(), "he runs (%s)" % runner.state)
	var flee := Vector2(float(runner.flee[0]), float(runner.flee[1]))
	_until(sim, func() -> bool: return str(runner.state) == "crowd", 60.0)
	_expect(Simulation.position_of(runner).distance_to(flee) < 24.0 and str(runner.state) == "crowd", "and stands at his flee point, out in the snow")
	_run_for(sim, 20.0)
	_expect(str(runner.state) == "crowd", "he panics once only")
	# in a heavy wave a chilled follower breaks away; under a lighter snow, or warm enough, he keeps on
	var sim2: RefCounted = _fresh()
	_steady(sim2, 1.0)
	var p: Dictionary = _person(sim2, "p2", m(126.0, 70.0), 0.6)
	_put(sim2, "hornero", m(124.0, 70.0))
	sim2.select("hornero")
	sim2.perform("guide", "p2")
	_run_for(sim2, 1.0)
	_expect(str(p.state) == "follow", "a chilled man follows in steady snow")
	_steady(sim2, float(data.snowfall.panic) + 0.2)
	_run_for(sim2, 0.2)
	_expect(str(p.state) in ["panic", "crowd"] and sim2.followers_of("hornero").is_empty(), "a heavy wave: he breaks away (%s)" % p.state)
	var q: Dictionary = _person(sim2, "p3", m(126.0, 72.0), 0.2)
	sim2.perform("guide", "p3")
	_run_for(sim2, 1.5)
	_expect(str(q.state) == "follow", "one still warm keeps following in the wave")

func _voice() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	for spec: Dictionary in data.people:
		if str(spec.group) in ["piramide-w", "palms-n"]: _person(sim, str(spec.id), Vector2.INF, 0.1)
	_put(sim, "benteveo", m(124.0, 72.0))
	sim.select("benteveo")
	var radius: float = float(benteveo.call.radius)
	var near: int = 0
	for p: Dictionary in sim.people():
		if Simulation.position_of(p).distance_to(m(124.0, 72.0)) <= radius: near += 1
	sim.events.clear()
	_expect(sim.perform("call"), "Benteveo shouts")
	_run_for(sim, 0.1)
	_expect(sim.followers_of("benteveo").size() == mini(near, int(benteveo.lead)) and near > 1, "everyone near him follows him at once (%d of %d near)" % [sim.followers_of("benteveo").size(), near])
	_expect(not _events(sim, "call").is_empty() and str(_events(sim, "call")[0].mode) == "follow", "event call")
	_expect(float(benteveo.cooldown) > 0.0 and not sim.perform("call"), "and then he needs his breath back")
	_expect(not sim.unit_by_id("hornero").is_empty() and sim.unit_by_id("lechuza").get("call", {}).is_empty(), "Lechuza has no call")
	sim.select("lechuza")
	_expect(not sim.perform("call"), "Lechuza cannot call")

func _bell() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	var hornero: Dictionary = sim.unit_by_id("hornero")
	sim.select("hornero")
	_put(sim, "hornero", m(110.0, 40.0))
	_expect(not sim.perform("call") and sim.message.contains("tram"), "off the tram, no bell (%s)" % sim.message)
	_put(sim, "hornero", sim.vehicle_rect("tram").get_center())
	# a few near the tram (within the bell's reach), one too far off to hear it
	var at: Vector2 = sim.vehicle_rect("tram").get_center()
	_person(sim, "p1", at + m(6.0, 14.0), 0.1)
	_person(sim, "p2", at + m(-12.0, 20.0), 0.1)
	_person(sim, "p3", at + m(20.0, 26.0), 0.1)
	_person(sim, "p4", at + m(50.0, 50.0), 0.1)
	var radius: float = float(hornero.call.radius)
	var near: Array = []
	for p: Dictionary in sim.people():
		if Simulation.position_of(p).distance_to(sim.vehicle_rect("tram").get_center()) <= radius: near.append(str(p.id))
	_expect(sim.perform("call"), "Hornero rings the tram's bell")
	_run_for(sim, 0.1)
	var coming: int = 0
	for p: Dictionary in sim.people():
		if str(p.state) == "coming": coming += 1
	_expect(coming == near.size() and near.size() == 3, "everyone near the tram comes running by himself (%d of %d)" % [coming, near.size()])
	_expect(str(sim.guard_by_id("p4").state) == "crowd", "one too far off did not hear it")
	_until(sim, func() -> bool: return sim.rescue_counts().saved == near.size(), 60.0)
	_expect(int(sim.rescue_counts().saved) == near.size(), "they climb aboard the tram (%d)" % int(sim.rescue_counts().saved))
	for id: String in near: _expect(str(sim.guard_by_id(id).shelter) == "tram", "%s in the tram" % id)
	_expect(int(hornero.calls) == int(hornero.call.count) - 1, "one ring fewer left")

func _tram() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	var stops: Array = data.vehicles[0].stops
	var start: Rect2 = sim.vehicle_rect("tram")
	_expect(is_equal_approx(start.position.x, float(stops[0])), "the tram stands at its first stop")
	_expect(not sim.is_blocked(start.get_center()), "the tram's doors are open: people can climb in")
	var p: Dictionary = _person(sim, "p1", start.get_center() + Vector2(64.0, 0.0), 0.0)
	sim._save(p, "tram")
	_run_for(sim, 3.0)
	var rel: float = float(p.x) - start.position.x
	sim.select("benteveo")
	_expect(not sim.perform("drive") and sim.message.contains("Hornero"), "only Hornero drives the tram (%s)" % sim.message)
	sim.select("hornero")
	_expect(sim.perform("drive"), "Hornero takes the controller")
	sim.events.clear()
	_until(sim, func() -> bool: return int(sim.vehicles.tram.to) >= 0, 10.0)
	_expect(int(sim.vehicles.tram.to) == 1 and not _events(sim, "drive").is_empty(), "the tram sets off for the next stop")
	var hornero: Dictionary = sim.unit_by_id("hornero")
	_until(sim, func() -> bool: return int(sim.vehicles.tram.to) < 0 and hornero.order.is_empty(), 60.0)
	var now: Rect2 = sim.vehicle_rect("tram")
	_expect(is_equal_approx(now.position.x, float(stops[1])), "it stops at the next stop (%.0f)" % now.position.x)
	_expect(now.has_point(Simulation.position_of(hornero)) and hornero.order.is_empty(), "Hornero rode it there")
	_expect(absf(float(p.x) - now.position.x - rel) < 4.0 and str(p.state) == "safe", "the man aboard came with it")
	_expect(not _events(sim, "arrived").is_empty(), "event arrived")
	_expect(sim.perform("drive"), "on again")
	_until(sim, func() -> bool: return int(sim.vehicles.tram.to) < 0 and sim.unit_by_id("hornero").order.is_empty(), 80.0)
	_expect(is_equal_approx(sim.vehicle_rect("tram").position.x, float(stops[2])), "to the last stop")
	sim.perform("drive")
	_until(sim, func() -> bool: return int(sim.vehicles.tram.to) >= 0, 10.0)
	_expect(int(sim.vehicles.tram.to) == 1, "from the end of the line it goes back")
	_expect(not sim.perform("drive") or true, "a second order while it moves is answered")
	sim.select("bigua")
	_expect(not sim.perform("drive", "colectivo"), "the colectivo goes nowhere")

func _carrying() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	var p: Dictionary = _person(sim, "p5", m(196.0, 120.0), 1.0)
	_run_for(sim, 0.5)
	_expect(str(p.state) == "fallen" and float(p.fall_left) > 30.0, "full of cold, a person falls: %.0f s to bring him in" % float(p.fall_left))
	_expect(not sim.perform("guide", "p5"), "nobody leads a fallen man")
	sim.select("hornero")
	_put(sim, "hornero", m(194.0, 120.0))
	_expect(not sim.perform("pickup", "p5") and sim.message.contains("Biguá"), "only Biguá is strong enough to carry him (%s)" % sim.message)
	var bigua: Dictionary = sim.unit_by_id("bigua")
	_put(sim, "bigua", m(198.0, 124.0))
	sim.select("bigua")
	_expect(sim.perform("pickup", "p5"), "Biguá lifts him")
	_until(sim, func() -> bool: return str(bigua.carrying) == "p5", 5.0)
	var left: float = float(p.fall_left)
	_run_for(sim, 4.0)
	_expect(str(bigua.carrying) == "p5" and absf(float(p.fall_left) - left) < 0.01, "on Biguá's shoulders his time stands still")
	_expect(not sim.perform("guide", "p1") and sim.message.contains("down"), "carrying, Biguá does nothing else (%s)" % sim.message)
	sim.perform("move", m(203.0, 138.2))
	_until(sim, func() -> bool: return str(p.state) == "safe", 40.0)
	_expect(str(p.state) == "safe" and str(p.shelter) == "colectivo" and str(bigua.carrying) == "", "in the colectivo Biguá sets him down: saved")
	# set down in the open, the snow goes on covering him
	var q: Dictionary = _person(sim, "p6", m(196.0, 110.0), 1.0)
	_run_for(sim, 0.3)
	_put(sim, "bigua", m(196.0, 112.0))
	sim.perform("pickup", "p6")
	_until(sim, func() -> bool: return str(bigua.carrying) == "p6", 5.0)
	sim.perform("drop")
	_run_for(sim, 1.0)
	_expect(str(q.state) == "fallen" and str(bigua.carrying) == "", "set down in the open: still fallen")
	sim.events.clear()
	_run_for(sim, float(data.snowfall.grace.person) + 1.0)
	_expect(str(q.state) == "lost" and not _events(sim, "buried").is_empty(), "nobody brought him in: lost to the snow")
	_expect(not sim.perform("pickup", "p6"), "nobody carries the lost")

func _canvas() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 1.0)
	var hornero: Dictionary = sim.unit_by_id("hornero")
	var cloth: Dictionary = data.canvases[1]
	var at := Vector2(float(cloth.x), float(cloth.y))
	_put(sim, "hornero", at + Vector2(-40.0, 40.0))
	hornero.exposure = 0.2
	sim.select("hornero")
	_expect(sim.perform("canvas", str(cloth.id)), "Hornero goes for the %s" % cloth.id)
	_until(sim, func() -> bool: return not (hornero.canvas as Dictionary).is_empty(), 10.0)
	_expect(str(hornero.canvas.id) == str(cloth.id) and sim.canvases_taken.has(str(cloth.id)), "he holds it")
	_expect(not sim.perform("canvas"), "one at a time")
	var cold: float = float(hornero.exposure)
	var ids: Array = ["p1", "p2", "p3", "p4"]
	for i: int in range(ids.size()):
		var p: Dictionary = _person(sim, ids[i], Simulation.position_of(hornero) + Vector2(20.0 * float(i + 1), 0.0), 0.3)
		p.group = ""
	for id: String in ids:
		sim.perform("guide", id)
		_until(sim, func() -> bool: return hornero.order.is_empty(), 10.0)
	sim.perform("move", Simulation.position_of(hornero) + Vector2(-96.0, 160.0))
	_run_for(sim, 5.0)
	_expect(absf(float(hornero.exposure) - cold) < 0.005, "under the cloth he takes no cold (%.3f -> %.3f)" % [cold, float(hornero.exposure)])
	var chain: Array = sim.followers_of("hornero")
	var warm: int = 0
	for p: Dictionary in chain:
		if bool(p.warm): warm += 1
	_expect(warm == int(cloth.holds) and chain.size() == 4, "nor do the %d closest behind him; the last one does (%d warm of %d)" % [int(cloth.holds), warm, chain.size()])
	_expect(not bool(chain[3].warm) and float(chain[3].exposure) > 0.31, "the fourth is out in it (%.3f)" % float(chain[3].exposure))
	# back under cover: the cloth's one crossing is done
	_put(sim, "hornero", sim.vehicle_rect("tram").get_center())
	_run_for(sim, 0.2)
	_expect((hornero.canvas as Dictionary).is_empty(), "under cover again: the cloth is spent")
	_expect(sim.canvases_taken.has(str(cloth.id)) and not sim.perform("canvas", str(cloth.id)), "and gone")
	# soaked through after its time
	var sim2: RefCounted = _fresh()
	var lechuza: Dictionary = sim2.unit_by_id("lechuza")
	lechuza["canvas"] = {"id": "awning", "left": 2.0, "holds": 3, "out": false}
	_put(sim2, "lechuza", m(60.0, 100.0))
	_run_for(sim2, 3.0)
	_expect((lechuza.canvas as Dictionary).is_empty(), "a cloth soaks through after its time")

func _lights_and_gate() -> void:
	var sim: RefCounted = _fresh()
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	sim.select("benteveo")
	_put(sim, "benteveo", m(56.0, 129.5))
	_expect(not sim.perform("rig", "subte-gate") and sim.message.contains("Lechuza"), "the service gate is Lechuza's (%s)" % sim.message)
	sim.select("lechuza")
	_put(sim, "lechuza", m(60.0, 120.0))
	_expect(sim.perform("rig", "subte-gate"), "Lechuza goes to the service gate")
	_until(sim, func() -> bool: return sim.rigged.has("subte-gate"), 30.0)
	_expect(_objective_done(sim, "gate") and not sim.is_blocked(m(51.5, 129.5)), "the gate is open (objective gate)")
	var p: Dictionary = _person(sim, "p20", m(60.0, 126.0), 0.2)
	p.group = ""
	sim.perform("guide", "p20")
	_until(sim, func() -> bool: return lechuza.order.is_empty(), 10.0)
	sim.perform("move", m(44.5, 129.5))
	_until(sim, func() -> bool: return str(p.state) == "safe", 30.0)
	_expect(str(p.shelter) == "subte-service", "down the service stair into the subte")
	_expect(not sim.checkpoint.is_empty(), "a checkpoint")

func _the_end() -> void:
	# everyone in, the squad under cover: won early
	var sim: RefCounted = _fresh(false)
	for p: Dictionary in sim.people(): sim._save(p, "catedral")
	sim.events.clear()
	sim.update(0.05)
	_expect(sim.phase == "won" and _objective_done(sim, "people") and _objective_done(sim, "shelter"), "everyone in and the four under cover: won (%s)" % sim.phase)
	_expect(not _events(sim, "won").is_empty(), "event won")
	# the squad not yet in: not yet
	var sim2: RefCounted = _fresh(false)
	for p: Dictionary in sim2.people(): sim2._save(p, "catedral")
	_put(sim2, "hornero", m(142.0, 60.0))
	sim2.update(0.05)
	_expect(sim2.phase == "playing", "not while one of the four is out in the snow")
	_put(sim2, "hornero", sim2.vehicle_rect("tram").get_center())
	sim2.update(0.05)
	_expect(sim2.phase == "won", "then won")
	# too many lost to reach the need: lost at once
	var sim3: RefCounted = _fresh(false)
	var need: int = int(data.snowfall.need)
	var total: int = sim3.people().size()
	var i: int = 0
	for p: Dictionary in sim3.people():
		if i <= total - need: sim3._person_lost(p)
		i += 1
	sim3.update(0.05)
	_expect(sim3.phase == "lost" and sim3.lost_reason.contains("lost"), "too many lost to bring in enough: lost (%s)" % sim3.lost_reason)
	# all four of the squad lost
	var sim4: RefCounted = _fresh(false)
	for unit: Dictionary in sim4.units: sim4._unit_lost(unit)
	sim4.update(0.05)
	_expect(sim4.phase == "lost" and sim4.lost_reason.contains("squad"), "the whole squad lost: over (%s)" % sim4.lost_reason)
	# the four lost before Juan Salvo comes: the night goes on, he is on his way
	var sim6: RefCounted = _fresh(false)
	for unit: Dictionary in sim6.units:
		if str(unit.id) != "salvo": sim6._unit_lost(unit)
	sim6.update(0.05)
	_expect(sim6.phase == "playing", "the four lost, Juan Salvo still to come: not over yet")
	# all in or lost, enough saved, the squad in: won without everyone
	var sim5: RefCounted = _fresh(false)
	i = 0
	for p: Dictionary in sim5.people():
		if i < total - need: sim5._person_lost(p)
		else: sim5._save(p, "catedral")
		i += 1
	sim5.update(0.05)
	_expect(sim5.phase == "won", "enough saved and the rest lost: won all the same")
	_expect(not sim5.badge_earned("everyone") and sim5.badge_earned("all_four"), "without the medal for everyone")

func _burial() -> void:
	var sim: RefCounted = _fresh(false)
	var need: int = int(data.snowfall.need)
	var i: int = 0
	for p: Dictionary in sim.people():
		if i < need: sim._save(p, "catedral")
		i += 1
	_put(sim, "bigua", m(150.0, 100.0))
	sim.unit_by_id("bigua").exposure = 0.0
	sim.time = sim.bury_time() - 0.1
	sim.events.clear()
	sim.update(0.05)
	sim.update(0.05)
	_expect(sim.buried_square and not _events(sim, "square_buried").is_empty(), "the snow buries the square")
	_expect(not bool(sim.unit_by_id("bigua").alive), "Biguá was out in it: lost")
	var out: int = 0
	for p: Dictionary in sim.people():
		if str(p.state) != "safe" and str(p.state) != "lost": out += 1
	_expect(out == 0, "everyone out in the square is lost")
	_expect(sim.phase == "won" and int(sim.rescue_counts().saved) == need, "enough were in: won (%s)" % sim.phase)
	_expect(not sim.badge_earned("all_four") and not sim.badge_earned("everyone"), "without the squad's medal or everyone's")
	var sim2: RefCounted = _fresh(false)
	i = 0
	for p: Dictionary in sim2.people():
		if i < need - 1: sim2._save(p, "catedral")
		i += 1
	sim2.time = sim2.bury_time() - 0.05
	sim2.update(0.05)
	sim2.update(0.05)
	_expect(sim2.phase == "lost" and sim2.lost_reason.contains("too few"), "too few in when it buries the square: lost (%s)" % sim2.lost_reason)

func _medals() -> void:
	var sim: RefCounted = _fresh(false)
	for p: Dictionary in sim.people(): sim._save(p, "catedral")
	sim.time = float(data.parTime) - 10.0
	sim.update(0.05)
	var badges: Array = sim.result_badges()
	_expect(badges.size() == data.medals.size() and badges.size() == 3, "three medals")
	for b: Dictionary in badges:
		_expect(bool(b.earned), "%s earned" % b.id)
		_expect(b.has("art") and str(b.label) != "" and str(b.text) != "", "%s has its art and its words" % b.id)
	var swift: Dictionary = badges.filter(func(b: Dictionary) -> bool: return str(b.id) == "swift")[0]
	_expect(str(swift.text).contains("%d:%02d" % [floori(float(data.parTime) / 60.0), int(data.parTime) % 60]), "the time is in Swift's words (%s)" % swift.text)
	var sim2: RefCounted = _fresh(false)
	for p: Dictionary in sim2.people(): sim2._save(p, "catedral")
	sim2.stats["squad_lost"] = 1
	sim2.time = float(data.parTime) + 10.0
	sim2.update(0.05)
	_expect(sim2.badge_earned("everyone") and not sim2.badge_earned("all_four") and not sim2.badge_earned("swift"), "everyone in, one of the squad lost, slow")

func _every_order() -> void:
	for paused: bool in [true, false]:
		var sim: RefCounted = _fresh(false)
		if paused and not sim.paused: sim.toggle_pause()
		for unit: Dictionary in sim.units:
			var id: String = str(unit.id)
			sim.select(id)
			var here: Vector2 = Simulation.position_of(unit)
			var actions: Array = ["move", "stance", "stance", "distract", "takedown", "shoot", "pickup", "drop", "trap", "trap_pickup", "cut", "sabotage",
				"unlock", "rescue", "extract", "plant", "chat", "uniform", "rig", "talk", "guide", "call", "drive", "canvas", "help", "interact", "cancel"]
			for a: Dictionary in sim.available_actions(id):
				actions.append(str(a.id))
			for thing: Dictionary in sim.interactables():
				actions.append(str(thing.order))
			for action: String in actions:
				for target: Variant in [null, "p1", "p12", here + Vector2(64.0, 0.0), "cabildo-lights", "subte-gate", "tram", "colectivo", "awning", "lechuza", "nobody"]:
					var answer: Variant = sim.perform(action, target)
					_expect(typeof(answer) == TYPE_BOOL, "%s: %s %s answered (%s)" % [id, action, str(target), str(answer)])
					_expect(sim.message != "", "%s: %s says something" % [id, action])
				sim.perform("cancel")
			if not paused: _run_for(sim, 0.5)
		_run_for(sim, 2.0)
		_expect(sim.phase in ["playing", "lost", "won"], "the night goes on")
	# a fallen man refuses everything, and says why
	var sim2: RefCounted = _fresh()
	var bigua: Dictionary = sim2.unit_by_id("bigua")
	_put(sim2, "bigua", m(150.0, 60.0))
	bigua.exposure = 1.0
	sim2._unit_falls(bigua)
	sim2.select("bigua")
	for action: String in ["move", "guide", "call", "drive", "canvas", "help", "pickup", "stance"]:
		var answer: bool = sim2.perform(action, m(140.0, 60.0) if action == "move" else "p1")
		_expect(not answer or action == "stance", "fallen, %s is refused" % action)
	for a: Dictionary in sim2.available_actions("bigua"):
		_expect(not bool(a.enabled), "fallen, his bar is dark: %s" % a.id)

func _checkpoints() -> void:
	var sim: RefCounted = _fresh(false)
	var saved: Dictionary = sim.snapshot()
	sim.select("hornero")
	sim.perform("drive")
	_run_for(sim, 6.0)
	_rig(sim, "cabildo-lights", "lechuza")
	sim.canvases_taken["awning"] = "lechuza"
	sim._save(sim.guard_by_id("p1"), "catedral")
	var x_moved: float = float(sim.vehicles.tram.x)
	var later: Dictionary = sim.snapshot()
	sim.restore(saved)
	_expect(is_equal_approx(float(sim.vehicles.tram.x), float(data.vehicles[0].x)) and int(sim.vehicles.tram.to) < 0, "restored: the tram at its stop")
	_expect(sim.rigged.is_empty() and sim.canvases_taken.is_empty() and str(sim.guard_by_id("p1").state) == "crowd", "the arcade dark, the awning up, p1 out in the square")
	_expect(not sim.shelter_open(sim.shelter_by_id("cabildo")), "the arcade dark again")
	sim.restore(later)
	_expect(is_equal_approx(float(sim.vehicles.tram.x), x_moved) and sim.rigged.has("cabildo-lights") and str(sim.guard_by_id("p1").state) == "safe", "and back")
	var bare: Dictionary = Simulation.new(data).snapshot()
	_expect(bare.has("vehicles") and bare.has("canvases_taken") and bare.has("buried_square"), "the rescue's state is in a snapshot")

func _hud_queries() -> void:
	var sim: RefCounted = _fresh(false)
	var bars: Dictionary = {}
	for unit: Dictionary in sim.units:
		var ids: Array = []
		for a: Dictionary in sim.available_actions(str(unit.id)):
			ids.append(str(a.id))
		bars[unit.id] = ids
	for unit: Dictionary in sim.units:
		var bar: Array = bars[unit.id]
		var gun: bool = str(unit.id) == "salvo"
		_expect("guide" in bar and "stance" in bar and not "takedown" in bar and ("shoot" in bar) == gun and not "extract" in bar and not "rescue" in bar, "%s: lead people in; no knife, %s, no boat (%s)" % [unit.id, "his rifle" if gun else "no gun", str(bar)])
	_expect("pickup" in bars.salvo, "Juan Salvo's bar: carry")
	_expect("call" in bars.hornero and "drive" in bars.hornero, "Hornero's bar: the bell, the tram (%s)" % str(bars.hornero))
	_expect("call" in bars.benteveo and not "drive" in bars.benteveo, "Benteveo's bar: his voice")
	_expect("rig" in bars.lechuza and not "call" in bars.lechuza, "Lechuza's bar: the lights and the gate")
	_expect(not "call" in bars.bigua and "pickup" in bars.bigua, "Biguá's bar: carry")
	var labels: Dictionary = {}
	for a: Dictionary in sim.available_actions("hornero"):
		labels[a.id] = str(a.label)
	_expect(labels.get("call", "") == "Bell" and labels.get("guide", "") == "Lead in", "Hornero's words: %s" % str(labels))
	sim.select("benteveo")
	var types: Dictionary = {}
	for t: Dictionary in sim.interactables():
		types[str(t.type)] = int(types.get(str(t.type), 0)) + 1
	_expect(int(types.get("person", 0)) == sim.people().size(), "every person in the square can be tapped (%s)" % str(types))
	_expect(types.has("canvas") and types.has("lights") and types.has("service"), "the cloths, the fuse box and the service gate (%s)" % str(types))
	sim.select("hornero")
	types.clear()
	for t: Dictionary in sim.interactables():
		types[str(t.type)] = true
	_expect(types.has("tram"), "Hornero can tap the tram")
	var counts: Dictionary = sim.rescue_counts()
	_expect(int(counts.total) == sim.people().size() and int(counts.out) == int(counts.total) and int(counts.need) == int(data.snowfall.need), "the HUD's tally: %s" % str(counts))
	_expect(sim.objective_progress("people") == [0, sim.people().size()], "the people objective's tally")

# --- Juan Salvo -----------------------------------------------------------------------------------------------
## Out of play until his time: not selectable, no orders, no cold, nobody's prey, not keeping the night from ending;
## then in off Avenida de Mayo, walking on to the square, a checkpoint taken.
func _salvo() -> void:
	var spec: Dictionary = {}
	for u: Dictionary in data.units:
		if str(u.id) == "salvo": spec = u
	_expect(not spec.is_empty() and bool(spec.suit) and bool(spec.carries) and spec.has("gun") and spec.has("arrive"), "Juan Salvo: sealed suit, carries, a rifle, comes later")
	_expect(float(spec.arrive.at) > 0.0 and float(spec.arrive.at) < float(data.snowfall.schedule[4][0]), "he comes early in the night, before the first wave (%.0f s)" % float(spec.arrive.at))
	var sim: RefCounted = _fresh()
	_steady(sim, 1.0)
	var juan: Dictionary = sim.unit_by_id("salvo")
	var edge: Vector2 = Simulation.position_of(juan)
	_expect(bool(juan.away) and (edge.x < m(3.0, 0.0).x) and edge.y > m(0, 72.0).y and edge.y < m(0, 100.0).y, "not here yet: at the head of Avenida de Mayo, the edge of the map (%s)" % str(edge / 32.0))
	sim.select("salvo")
	_expect(sim.selected_id != "salvo", "he cannot be chosen before he comes")
	_expect(not sim._issue(juan, {"type": "move", "x": m(60, 86).x, "y": m(60, 86).y}) and sim.message.contains("not here yet"), "nor given an order (%s)" % sim.message)
	for a: Dictionary in sim.available_actions("salvo"):
		_expect(not bool(a.enabled), "his bar is dark before he comes: %s" % a.id)
	_run_for(sim, 10.0)
	_expect(is_zero_approx(float(juan.exposure)) and bool(juan.away) and Simulation.position_of(juan) == edge, "away, he takes no cold and does not move")
	# the night may end without him while he is away (everyone else in)
	var early: RefCounted = _fresh(false)
	for p: Dictionary in early.people(): early._save(p, "catedral")
	early.update(0.05)
	_expect(early.phase == "won", "with everyone in before he comes, the night is won all the same")
	# he comes
	sim.time = float(spec.arrive.at) - 0.1
	sim.events.clear()
	sim.checkpoint = {}
	_run_for(sim, 0.3)
	_expect(not bool(juan.away) and not _events(sim, "arrival").is_empty() and str(_events(sim, "arrival")[0].id) == "salvo", "at %.0f s he comes in: event arrival" % float(spec.arrive.at))
	_expect(sim.message.contains("Juan Salvo") and sim.message.contains("suit"), "the notice says so: %s" % sim.message)
	var to := Vector2(float(spec.arrive.to[0]), float(spec.arrive.to[1]))
	_until(sim, func() -> bool: return (juan.path as Array).is_empty(), 40.0)
	_expect(Simulation.position_of(juan).distance_to(to) < 4.0, "he walks in to the edge of the square (%s)" % str(Simulation.position_of(juan) / 32.0))
	_expect(str(sim.checkpoint.get("label", "")) == "salvo", "a checkpoint as he comes (%s)" % str(sim.checkpoint.get("label", "")))
	sim.select("salvo")
	_expect(sim.selected_id == "salvo" and sim.perform("move", m(80.0, 86.0)), "now he is the player's like the others")

## The suit: out in the heaviest wave for a minute, no cold and no fall; Lechuza beside him would fall. Knocked down, he
## gets up again by himself; a mate can still help him up sooner.
func _suit() -> void:
	var sim: RefCounted = _fresh()
	sim.time = 31.0
	sim.update(0.05)
	_steady(sim, 3.2)
	var juan: Dictionary = sim.unit_by_id("salvo")
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	_put(sim, "salvo", m(142.0, 60.0))
	_put(sim, "lechuza", m(146.0, 60.0))
	sim.events.clear()
	_run_for(sim, 60.0)
	_expect(is_zero_approx(float(juan.exposure)) and not bool(juan.fallen) and bool(juan.alive), "Juan Salvo out in the heaviest snow for a minute: no cold at all")
	_expect(bool(lechuza.fallen) or not bool(lechuza.alive), "Lechuza beside him fell long since")
	var falls: Array = _events(sim, "fallen").filter(func(e: Dictionary) -> bool: return str(e.id) == "salvo")
	_expect(falls.is_empty(), "the snow never brought him down")
	# knocked down: up again by himself, still with no cold
	sim._unit_falls(juan)
	_expect(bool(juan.fallen) and is_zero_approx(float(juan.exposure)), "knocked down, he is down (and still not cold)")
	_run_for(sim, float(data.snowfall.get("suitUp", 8.0)) + 0.5)
	_expect(not bool(juan.fallen) and bool(juan.alive) and is_zero_approx(float(juan.exposure)), "and gets up again by himself (%s)" % sim.message)
	# a fallen man with the suit is not lost to the snow, but the buried square takes anyone out in it
	_expect(int(sim.stats.get("squad_lost", 0)) <= 1, "nobody lost but perhaps Lechuza")
	var sim2: RefCounted = _fresh(false)
	sim2.time = float(data.units[4].arrive.at) + 1.0
	sim2.update(0.05)
	_put(sim2, "salvo", m(150.0, 100.0))
	sim2.time = sim2.bury_time() - 0.05
	sim2.update(0.05)
	sim2.update(0.05)
	_expect(not bool(sim2.unit_by_id("salvo").alive), "the buried square takes him too: the suit keeps the snow off, not a square buried deep")
	# the cold readout: none for him
	_expect(bool(juan.suit), "his photo shows his health, not the cold (hud.gd reads units[].suit)")

## He carries the fallen in, one at a time; he leads only two.
func _salvo_carries() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 2.0)
	sim.time = 31.0
	sim.update(0.05)
	var juan: Dictionary = sim.unit_by_id("salvo")
	var p: Dictionary = _person(sim, "p5", m(196.0, 120.0), 1.0)
	var q: Dictionary = _person(sim, "p6", m(198.0, 118.0), 1.0)
	_run_for(sim, 0.5)
	_expect(str(p.state) == "fallen" and str(q.state) == "fallen", "two fall in a wave")
	_put(sim, "salvo", m(194.0, 121.0))
	sim.select("salvo")
	_expect(sim.perform("pickup", "p5"), "Juan Salvo lifts one of them")
	_until(sim, func() -> bool: return str(juan.carrying) == "p5", 5.0)
	_expect(not sim.perform("pickup", "p6") and sim.message.contains("set"), "one at a time (%s)" % sim.message)
	sim.perform("move", m(203.0, 138.2))
	_until(sim, func() -> bool: return str(p.state) == "safe", 40.0)
	_expect(str(p.state) == "safe" and str(p.shelter) == "colectivo" and is_zero_approx(float(juan.exposure)), "in the colectivo: saved, and Juan Salvo crossed in the wave without cold")
	_expect(sim.perform("pickup", "p6"), "back for the other")
	_until(sim, func() -> bool: return str(juan.carrying) == "p6", 30.0)
	sim.perform("move", m(203.0, 138.2))
	_until(sim, func() -> bool: return str(q.state) == "safe", 40.0)
	_expect(str(q.state) == "safe", "both in")
	# he leads two at a time
	var sim2: RefCounted = _fresh()
	_steady(sim2, 0.5)
	sim2.time = 31.0
	sim2.update(0.05)
	_put(sim2, "salvo", m(60.0, 100.0))
	sim2.select("salvo")
	for i: int in range(3):
		var r: Dictionary = _person(sim2, "p%d" % (10 + i), m(62.0 + 2.0 * i, 100.0), 0.1)
		r.group = ""
	_expect(sim2.perform("guide", "p10"), "he leads one")
	_until(sim2, func() -> bool: return sim2.unit_by_id("salvo").order.is_empty(), 10.0)
	_expect(sim2.perform("guide", "p11"), "and a second")
	_until(sim2, func() -> bool: return sim2.unit_by_id("salvo").order.is_empty(), 10.0)
	_expect(not sim2.perform("guide", "p12") and sim2.message.contains("as many"), "but not a third (%s)" % sim2.message)

## A cascarudo of the data put in the square now (a quiet square has none), in its first state there.
func _beast(sim: RefCounted, id: String, at: Vector2) -> Dictionary:
	for spec: Dictionary in data.creatures.arrivals:
		if str(spec.id) == id:
			var b: Dictionary = sim._make_creature(spec)
			sim.guards.append(b)
			b = sim.guard_by_id(id)
			sim._creature_enters(b, true)
			b.x = at.x
			b.y = at.y
			b.path = []
			b.think = 0.0
			return b
	return {}

## The rifle: six rounds; never at a person; a hit drives a cascarudo off the way it came, off the map for a while, and
## it comes back; the third kills it; out of sight, no shot.
func _rifle() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.5)
	sim.time = 31.0
	sim.update(0.05)
	var juan: Dictionary = sim.unit_by_id("salvo")
	_expect(int(juan.ammo) == 6, "six rounds")
	_put(sim, "salvo", m(150.0, 60.0))
	sim.select("salvo")
	var p: Dictionary = _person(sim, "p3", m(160.0, 60.0), 0.0)
	_expect(not sim.perform("shoot", "p3") and sim.message.contains("civilian"), "never at a person (%s)" % sim.message)
	var beast: Dictionary = _beast(sim, "c1", m(172.0, 62.0))
	_expect(not beast.is_empty() and str(beast.state) == "prowl", "a cascarudo in the square")
	var others: Array = []
	for t: Dictionary in sim.interactables():
		if str(t.type) == "creature": others.append(t)
	_expect(others.size() == 1 and str(others[0].order) == "shoot" and str(others[0].target) == "c1", "Juan Salvo can tap it to fire (%s)" % str(others))
	sim.select("hornero")
	var none: bool = true
	for t: Dictionary in sim.interactables():
		if str(t.type) == "creature": none = false
	_expect(none, "the others have nothing to do it with")
	_put(sim, "hornero", m(150.0, 64.0))
	_expect(not sim.perform("shoot", "c1") and sim.message.contains("nothing to fight"), "and say so (%s)" % sim.message)
	sim.select("salvo")
	sim.events.clear()
	_expect(sim.perform("shoot", "c1"), "Juan Salvo fires")
	_until(sim, func() -> bool: return int(juan.ammo) < 6, 5.0)
	_expect(int(juan.ammo) == 5 and int(beast.hits) == 1 and str(beast.state) == "driven", "a hit: it is driven off (%s, %d hits)" % [beast.state, int(beast.hits)])
	_expect(not _events(sim, "creature_hit").is_empty() and sim.message.contains("makes off"), "event creature_hit: %s" % sim.message)
	var home: Vector2 = beast.home
	_until(sim, func() -> bool: return str(beast.state) == "away", 60.0)
	_expect(str(beast.state) == "away" and Simulation.position_of(beast) == home and not _events(sim, "creature_gone").is_empty(), "off the map the way it came")
	var gone: float = sim.time
	_until(sim, func() -> bool: return str(beast.state) != "away", float(data.creatures.away) + 2.0)
	_expect(str(beast.state) == "prowl" and absf(sim.time - gone - float(data.creatures.away)) < 0.2, "back after %.0f s" % float(data.creatures.away))
	# out of sight: he will not have a shot through the Pirámide
	beast.x = m(142.0, 92.0).x
	beast.y = m(142.0, 92.0).y
	_put(sim, "salvo", m(142.0, 76.0))
	_expect(not sim._has_shot(juan, beast), "no line of fire through the Pirámide")
	# three hits kill it
	_put(sim, "salvo", m(150.0, 60.0))
	for k: int in range(2):
		beast.x = m(160.0, 60.0).x
		beast.y = m(160.0, 60.0).y
		sim._set_state(beast, "prowl")
		beast.path = []
		juan.weapon_cooldown = 0.0
		sim.perform("shoot", "c1")
		_until(sim, func() -> bool: return int(juan.ammo) <= 4 - k, 5.0)
	_expect(int(beast.hits) == 3 and str(beast.state) == "dead" and int(sim.stats.creatures_killed) == 1, "the third hit kills it (%s)" % beast.state)
	_expect(not sim.perform("shoot", "c1") and not sim.perform("pickup", "c1"), "dead: nothing more to shoot, nothing to carry")
	var bodies: bool = false
	for t: Dictionary in sim.interactables():
		if str(t.target) == "c1": bodies = true
	_expect(not bodies, "and nothing to tap")
	_run_for(sim, 60.0)
	_expect(str(beast.state) == "dead", "it stays dead")
	p.exposure = 0.0

## When each comes and from where: waiting off the map, then in along an avenue to the square.
func _creatures_come() -> void:
	var arrivals: Array = data.creatures.arrivals
	_expect(arrivals.size() >= 2 and arrivals.size() <= 4, "two to four cascarudos (%d)" % arrivals.size())
	var first: float = INF
	for spec: Dictionary in arrivals:
		first = minf(first, float(spec.at))
		var from := Vector2(float(spec.from[0]), float(spec.from[1]))
		_expect(from.x < m(3.0, 0).x or from.x > m(277.0, 0).x, "%s comes in from the edge of the map (%s)" % [spec.id, str(from / 32.0)])
		_expect(str(spec.text).contains("cascarudo"), "and the notice says where: %s" % spec.text)
	_expect(is_equal_approx(first, 15.0) and first < float(data.units[4].arrive.at), "the first a quarter of a minute in, before Juan Salvo (%.0f s; he comes at %.0f s)" % [first, float(data.units[4].arrive.at)])
	var sim: RefCounted = Simulation.new(data)
	sim.start()
	sim.toggle_pause()
	var beasts: Array = sim.guards.filter(func(g: Dictionary) -> bool: return bool(g.get("creature", false)))
	_expect(beasts.size() == arrivals.size(), "they are on the guards' list as creatures")
	for b: Dictionary in beasts:
		_expect(str(b.state) == "waiting" and str(b.look) == "art:cascarudo" and str(b.title) == "CASCARUDO" and str(b.kind) == "creature", "%s waits off the map, dressed from the art pack's slot" % b.id)
		_expect(str(b.state) in sim.DOWN_STATES and not bool(b.get("civilian", false)), "%s has no cone and is nobody's to talk to" % b.id)
	_expect(sim.creatures_about().is_empty(), "nobody in the square at the start")
	var c1: Dictionary = sim.guard_by_id("c1")
	sim.time = float(c1.at) - 0.1
	sim.events.clear()
	_run_for(sim, 0.3)
	_expect(str(c1.state) == "prowl" and not _events(sim, "creature").is_empty() and sim.message == str(arrivals[0].text), "at %.0f s the first comes in (%s)" % [float(c1.at), sim.message])
	_expect(Simulation.position_of(c1).distance_to(Vector2(float(arrivals[0].from[0]), float(arrivals[0].from[1]))) < 32.0, "at its avenue's end of the map")
	_expect(sim.creatures_about().size() == 1, "one in the square")

## What a cascarudo goes for: the nearest out in the open within its senses, at a rush; with nobody that near, it roams
## toward the nearest out anywhere; nobody under cover. It knocks down whoever it reaches, stands over them, then moves
## on, and leaves alone the one it knocked down a moment ago.
func _creature_senses() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.4)
	var sense: float = float(data.creatures.sense)
	var beast: Dictionary = _beast(sim, "c1", m(150.0, 70.0))
	var near: Dictionary = _person(sim, "p1", m(150.0, 70.0) + Vector2(sense - 64.0, 0.0), 0.0)
	var far: Dictionary = _person(sim, "p2", m(150.0, 70.0) + Vector2(-sense - 200.0, 0.0), 0.0)
	var under: Dictionary = _person(sim, "p3", m(70.0, 14.0), 0.0)
	sim._save(under, "catedral")
	near.group = ""
	far.group = ""
	_run_for(sim, 0.2)
	_expect(str(beast.state) == "stalk" and str(beast.target_id) == "p1", "it goes for the one within its senses (%s -> %s)" % [beast.state, beast.target_id])
	var before: Vector2 = Simulation.position_of(beast)
	_run_for(sim, 1.0)
	var rush: float = Simulation.position_of(beast).distance_to(before)
	_expect(absf(rush - float(data.creatures.charge)) < 8.0, "at a rush (%.0f units a second)" % rush)
	# it reaches him: down in the snow
	sim.events.clear()
	_until(sim, func() -> bool: return str(near.state) == "fallen", 20.0)
	_expect(str(near.state) == "fallen" and not _events(sim, "struck").is_empty() and sim.message.contains("knocked"), "it knocks him down in the snow (%s)" % sim.message)
	_expect(str(beast.state) == "stay", "and stands over him")
	_run_for(sim, float(data.creatures.pause) + 0.6)
	_expect(str(beast.state) == "prowl" and str(beast.target_id) == "", "then moves on, toward the one out in the open far off (%s)" % beast.state)
	var d0: float = Simulation.position_of(beast).distance_to(Simulation.position_of(far))
	_run_for(sim, 2.0)
	var d1: float = Simulation.position_of(beast).distance_to(Simulation.position_of(far))
	_expect(d1 < d0 - 60.0 and d1 > d0 - 110.0, "roaming toward him at a walk (%.0f -> %.0f)" % [d0, d1])
	_expect(str(under.state) == "safe", "the one under the portico is not touched")
	# with nobody out at all it wanders the square
	sim._save(far, "catedral")
	_run_for(sim, 3.0)
	var roam: Array = data.creatures.roam
	var area := Rect2(float(roam[0]), float(roam[1]), float(roam[2]), float(roam[3]))
	_expect(str(beast.state) == "prowl" and area.has_point(beast.goal), "nobody out: it wanders the square (%s)" % str(beast.goal / 32.0))
	# one of the squad knocked down: he falls, and is left alone a while once he is up
	var sim2: RefCounted = _fresh()
	_steady(sim2, 0.4)
	var b2: Dictionary = _beast(sim2, "c2", m(150.0, 70.0))
	var hornero: Dictionary = sim2.unit_by_id("hornero")
	_put(sim2, "hornero", m(150.0, 70.0) + Vector2(40.0, 0.0))
	_run_for(sim2, 1.0)
	_expect(bool(hornero.fallen) and float(hornero.fall_left) > 30.0, "Hornero knocked down: he has fallen (%.0f s to get him up)" % float(hornero.fall_left))
	_put(sim2, "lechuza", m(150.0, 70.0) + Vector2(60.0, 300.0))
	sim2._help_up(hornero, sim2.unit_by_id("lechuza"))
	_run_for(sim2, float(data.creatures.pause) + 1.0)
	_expect(not bool(hornero.fallen) and str(b2.target_id) != "hornero", "up again, it leaves him alone for a while (%s -> %s)" % [b2.state, b2.target_id])

## The ground they keep to: no shelter (the portico, the arcade, the subte's three stairs, the bank's porch), no vehicle
## (the tram, the colectivo), nothing solid (the buildings, the Pirámide, the Belgrano). Told to go into the arcade or the
## tram it stops at the edge; across the square it walks round the Pirámide.
func _creature_ground() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.4)
	for shelter: Dictionary in sim.shelters():
		var inside: Vector2 = sim.shelter_inside(shelter)
		_expect(not sim.creature_ground_open(inside), "no cascarudo in the %s (%s)" % [shelter.id, str(inside / 32.0)])
		_expect(not sim.creature_ground_open(sim.shelter_rect(shelter).get_center()), "nor in the middle of it")
	for o: Dictionary in data.obstacles:
		if str(o.kind) in ["building", "monument"]:
			_expect(not sim.creature_ground_open(Simulation.rect_of(o).get_center()), "nor in the %s" % o.id)
	_expect(sim.creature_ground_open(m(142.0, 60.0)) and sim.creature_ground_open(m(35.0, 86.0)) and sim.creature_ground_open(m(120.0, 140.0)), "the square and the streets are its")
	var beast: Dictionary = _beast(sim, "c1", m(60.0, 110.0))
	for goal: Vector2 in [sim.shelter_inside(sim.shelter_by_id("cabildo")), sim.vehicle_rect("tram").get_center(), sim.shelter_inside(sim.shelter_by_id("subte-s")), sim.shelter_inside(sim.shelter_by_id("catedral"))]:
		var route: Array = sim._creature_path(Simulation.position_of(beast), goal)
		_expect(not route.is_empty(), "a way toward %s" % str(goal / 32.0))
		var end: Vector2 = route.back() if not route.is_empty() else Vector2.ZERO
		_expect(sim.shelter_at(end, false) == "" and end.distance_to(goal) < 12.0 * 32.0, "it ends by it, outside (%s)" % str(end / 32.0))
	# walked: it never sets foot under cover
	beast.path = sim._creature_path(Simulation.position_of(beast), sim.shelter_inside(sim.shelter_by_id("cabildo")))
	sim._set_state(beast, "drawn")
	beast.linger_left = 60.0
	var dry: bool = true
	for i: int in range(400):
		sim.update(0.05)
		if sim.shelter_at(Simulation.position_of(beast), false) != "": dry = false
	_expect(dry and Simulation.position_of(beast).distance_to(sim.shelter_inside(sim.shelter_by_id("cabildo"))) < 10.0 * 32.0, "walked to the arcade it stays outside it (%s)" % str(Simulation.position_of(beast) / 32.0))
	# round the Pirámide, not through it
	var pyramid: Rect2 = Rect2()
	for o: Dictionary in data.obstacles:
		if str(o.id) == "piramide": pyramid = Simulation.rect_of(o)
	var across: Array = sim._creature_path(m(110.0, 84.0), m(175.0, 84.0))
	var through: bool = false
	var last: Vector2 = m(110.0, 84.0)
	for point: Vector2 in across:
		for k: int in range(9):
			if pyramid.has_point(last.lerp(point, float(k) / 8.0)): through = true
		last = point
	_expect(not across.is_empty() and not through, "across the square it walks round the Pirámide")
	# the tram under way: it never stands inside the tram
	var sim2: RefCounted = _fresh()
	var b2: Dictionary = _beast(sim2, "c1", sim2.vehicle_rect("tram").get_center() + Vector2(600.0, 160.0))
	_put(sim2, "hornero", sim2.vehicle_rect("tram").get_center())
	var bait: Dictionary = _person(sim2, "p1", sim2.vehicle_rect("tram").get_center() + Vector2(1300.0, -100.0), 0.0)
	bait.group = ""
	sim2.select("hornero")
	sim2.perform("drive")
	var clear: bool = true
	for i: int in range(500):
		sim2.update(0.05)
		if sim2.vehicle_rect("tram").has_point(Simulation.position_of(b2)): clear = false
	_expect(clear, "the tram under way: the cascarudo is never inside it")

## Noise draws them: the tram's bell from as far as data creatures.hear.bell (it goes to the tram, stays by it a while,
## then roams again), a shout from close by, a shot from far across the square; one too far off does not hear it.
func _creature_noise() -> void:
	var sim: RefCounted = _fresh()
	_steady(sim, 0.4)
	var hear: Dictionary = data.creatures.hear
	var tram: Vector2 = sim.vehicle_rect("tram").get_center()
	var heard: Dictionary = _beast(sim, "c1", tram + Vector2(float(hear.bell) - 200.0, 900.0).limit_length(float(hear.bell) - 64.0))
	var deaf: Dictionary = _beast(sim, "c2", tram + Vector2(float(hear.bell) + 400.0, 600.0))
	_expect(Simulation.position_of(deaf).distance_to(tram) > float(hear.bell), "one beyond the bell's reach")
	_put(sim, "hornero", tram)
	sim.select("hornero")
	sim.events.clear()
	_expect(sim.perform("call"), "Hornero rings the bell")
	_run_for(sim, 0.2)
	_expect(str(heard.state) == "drawn" and str(heard.noise_kind) == "bell", "the bell draws the one within reach (%s)" % heard.state)
	_expect(str(deaf.state) != "drawn", "not the one too far off")
	var drawn: Array = _events(sim, "drawn")
	_expect(not drawn.is_empty() and str(drawn[0].noise) == "bell" and sim.message.contains("bell draws"), "event drawn: %s" % sim.message)
	_until(sim, func() -> bool: return (heard.path as Array).is_empty(), 60.0)
	_expect(Simulation.position_of(heard).distance_to(tram) < 8.0 * 32.0 and not sim.vehicle_rect("tram").grow(8.0).has_point(Simulation.position_of(heard)), "it comes to the tram and stays outside it (%.1f m off)" % (Simulation.position_of(heard).distance_to(tram) / 32.0))
	_run_for(sim, float(data.creatures.linger) + 1.0)
	_expect(str(heard.state) in ["prowl", "stalk"], "after a while it roams again (%s)" % heard.state)
	# a shout from close by draws one
	var sim2: RefCounted = _fresh()
	_steady(sim2, 0.4)
	_put(sim2, "benteveo", m(120.0, 60.0))
	var b: Dictionary = _beast(sim2, "c1", m(120.0, 60.0) + Vector2(float(hear.voice) - 40.0, 0.0))
	sim2._set_state(b, "prowl")
	b.think = 5.0
	sim2.select("benteveo")
	sim2.perform("call")
	_run_for(sim2, 0.2)
	_expect(str(b.state) in ["drawn", "stay"] and (str(b.noise_kind) == "voice" or str(b.state) == "stay"), "Benteveo's shout draws one close by (%s)" % b.state)
	# a shot draws the others to the one who fired
	var sim3: RefCounted = _fresh()
	_steady(sim3, 0.4)
	sim3.time = 31.0
	sim3.update(0.05)
	_put(sim3, "salvo", m(150.0, 60.0))
	var target: Dictionary = _beast(sim3, "c1", m(170.0, 60.0))
	var other: Dictionary = _beast(sim3, "c2", m(250.0, 100.0))
	_expect(Simulation.position_of(other).distance_to(m(150.0, 60.0)) < float(hear.rifle), "one within the shot's reach, on Balcarce")
	var other_far: Dictionary = _beast(sim3, "c3", m(1.5, 89.0))
	_expect(Simulation.position_of(other_far).distance_to(m(150.0, 60.0)) > float(hear.rifle), "one too far off to hear the shot")
	sim3.select("salvo")
	sim3.events.clear()
	sim3.perform("shoot", "c1")
	_until(sim3, func() -> bool: return str(target.state) == "driven", 5.0)
	_run_for(sim3, 0.1)
	_expect(str(other.state) == "drawn" and str(other.noise_kind) == "rifle", "the bang draws the other (%s)" % other.state)
	_expect((other.goal as Vector2).distance_to(m(150.0, 60.0)) < 6.0 * 32.0, "toward the one who fired")
	_expect(str(other_far.state) != "drawn", "not the one far off")
	_expect(sim3.message.contains("draws the other"), "the notice says so: %s" % sim3.message)

## Their state is in a checkpoint and comes back with it.
func _creature_checkpoint() -> void:
	var sim: RefCounted = _fresh(false)
	var saved: Dictionary = sim.snapshot()
	sim.time = maxf(float(data.creatures.arrivals[0].at), float(data.units[4].arrive.at)) + 5.0
	sim.update(0.05)
	var c1: Dictionary = sim.guard_by_id("c1")
	c1.hits = 2
	_expect(str(c1.state) != "waiting" and not bool(sim.unit_by_id("salvo").away), "later: the first cascarudo in, Juan Salvo here")
	var later: Dictionary = sim.snapshot()
	sim.restore(saved)
	_expect(str(sim.guard_by_id("c1").state) == "waiting" and int(sim.guard_by_id("c1").hits) == 0 and bool(sim.unit_by_id("salvo").away), "restored: the cascarudo not come yet, Juan Salvo away")
	sim.restore(later)
	_expect(str(sim.guard_by_id("c1").state) != "waiting" and int(sim.guard_by_id("c1").hits) == 2 and not bool(sim.unit_by_id("salvo").away), "and back, its hits with it")
	var route: Array = sim._creature_path(m(142.0, 60.0), m(142.0, 100.0))
	_expect(not route.is_empty(), "its ground rebuilt after a restore")

## Riachuelo plays exactly as before: nobody there has any of the rescue's keys.
func _other_operations() -> void:
	for path: String in ["res://data/riachuelo.json"]:
		var other: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sim: RefCounted = Simulation.new(other)
		sim.start()
		_expect(not sim.rescue_on and sim.people().is_empty() and sim.vehicles.is_empty() and is_zero_approx(sim.snow_intensity()), "%s: no rescue" % path)
		var ids: Array = []
		for a: Dictionary in sim.available_actions():
			ids.append(str(a.id))
		_expect(not "guide" in ids and not "call" in ids and "extract" in ids, "%s: the bar as before (%s)" % [path, str(ids)])
		_expect(sim.result_badges().size() == 5, "%s: the five badges" % path)

## The level's place on file: first, open from the start, Riachuelo after it.
func _on_file() -> void:
	var entry: Dictionary = Missions.LIST[0] if not Missions.LIST.is_empty() else {}
	_expect(str(entry.get("id", "")) == "plaza" and str(entry.number) == "01" and str(entry.best) == "best_" + str(data.progressKey) and str(entry.path) == "res://data/plaza.json", "on file as the first level: %s" % str(entry))
	var ids: Array = Missions.LIST.map(func(e: Dictionary) -> String: return str(e.id))
	_expect(ids == ["plaza", "riachuelo"], "the game: the plaza, then Riachuelo (%s)" % str(ids))
	_expect(Missions.unlocked("plaza", ConfigFile.new()) and Missions.next_of("plaza") == "riachuelo", "open from the start, Riachuelo next")
