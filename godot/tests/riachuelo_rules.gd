extends SceneTree
## The rules of Operation Riachuelo (data/riachuelo.json), one at a time, mostly on a quiet La Boca (nobody on duty
## unless a check needs them): the layout and the grid (everything that matters can be reached, and only the right way),
## every round walkable, the cellar door and the passenger, the lamp board and the quay's lamps, Lechuza's ladder,
## Hornero's gondola, Biguá's boat (his alone, and the passenger's with him), the covers on the tram lines and in the
## crowds, the neighbours and the informer, the bell and the papers, footprints, the launch's searchlight, every order
## of every operative answered without a crash, checkpoints, what the HUD is told, and the operation's place on file.
## Run: godot --headless --path godot --script res://tests/riachuelo_rules.gd
const Simulation = preload("res://scripts/simulation.gd")
const Missions = preload("res://scripts/missions.gd")

var data: Dictionary
var world: Dictionary
var checks: int = 0
var failures: int = 0
var section: String = ""

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	world = data.bocaWorld
	call_deferred("_run")

func _expect(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL [%s]: %s" % [section, explanation])

func _run() -> void:
	for part: String in ["layout", "reachable", "rounds", "the_cellar", "the_passenger", "lamp_board", "floodlights", "ladder", "gondola",
			"boat", "covers", "neighbours", "informer", "throws", "tracks", "searchlight", "every_order", "checkpoints", "hud_queries",
			"on_file"]:
		section = part
		call("_" + part)
	print("Riachuelo rules: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## A started, running mission; quiet: nobody on duty.
func _fresh(quiet: bool = true) -> RefCounted:
	var sim: RefCounted = Simulation.new(data)
	sim.start()
	sim.toggle_pause()
	if quiet: sim.guards.clear()
	return sim

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _put(sim: RefCounted, id: String, at: Vector2) -> void:
	var unit: Dictionary = sim.unit_by_id(id)
	unit.x = at.x
	unit.y = at.y
	unit.path = []

## Everyone but these out of the way, in the far north-east corner of the north street.
func _park(sim: RefCounted, keep: Array) -> void:
	var i: int = 0
	for unit: Dictionary in sim.units:
		if str(unit.id) in keep: continue
		_put(sim, str(unit.id), m(232.0 - 2.0 * float(i), 24.0))
		i += 1

func _run_for(sim: RefCounted, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.001 and sim.phase == "playing":
		sim.update(0.05)
		t += 0.05

func _events(sim: RefCounted, type: String) -> Array:
	var list: Array = []
	for event: Dictionary in sim.events:
		if str(event.get("type", "")) == type: list.append(event)
	return list

func _objective_done(sim: RefCounted, id: String) -> bool:
	for o: Dictionary in sim.objectives:
		if str(o.id) == id: return bool(o.done)
	return false

func _only(sim: RefCounted, keep: Array) -> void:
	for guard: Dictionary in sim.guards.duplicate():
		if not str(guard.id) in keep: sim.guards.erase(guard)

## One guard of the mission's own, standing still facing `angle` (degrees) at `at`, nothing else on duty.
func _watcher(sim: RefCounted, id: String, at: Vector2, angle: float) -> Dictionary:
	var spec: Dictionary = {}
	for g: Dictionary in data.guards:
		if str(g.id) == id: spec = g.duplicate(true)
	spec.erase("route")
	spec["post"] = [at.x, at.y, angle]
	spec.erase("scan")
	var guard: Dictionary = sim._make_guard(spec)
	sim.guards.append(guard)
	return guard

func _rig(sim: RefCounted, id: String, by: String) -> void:
	sim.rigged[id] = by
	sim._geometry_dirty = true

func _cellar_open(sim: RefCounted) -> void:
	sim.door_open = true

## The places that matter, in sim units.
func _door_spot() -> Vector2:
	return Vector2(float(data.door.interactX), float(data.door.interactY))

func _passenger() -> Vector2:
	return Vector2(float(data.prisoner.x), float(data.prisoner.y))

func _anchor(sim: RefCounted, id: String) -> Vector2:
	return sim.passage_anchor(sim.passage_by_id(id))

func _far_bank() -> Vector2:
	return Vector2(float(data.extraction.x), float(data.extraction.y))

func _start() -> Vector2:
	return m(float(world.start[0]), float(world.start[1]))

# ---------------------------------------------------------------------------------------------------------------

func _layout() -> void:
	var sim: RefCounted = _fresh(false)
	var ids: Array = []
	for unit: Dictionary in sim.units: ids.append(str(unit.id))
	_expect(ids == ["hornero", "lechuza", "benteveo", "bigua"], "the squad of four, Hornero leading: %s" % str(ids))
	for unit: Dictionary in sim.units:
		var id: String = str(unit.id)
		_expect(id == id.to_lower() and id.to_ascii_buffer().get_string_from_ascii() == id, "%s: a lowercase ASCII id" % id)
		# each of the four has a figure of his own (operative.gd dresses the id) and his own photo in the atlas
		var cell: int = {"hornero": 0, "lechuza": 1, "benteveo": 2, "bigua": 3}.get(id, -1)
		_expect(not unit.has("look") and int(unit.get("portrait", -1)) == cell, "%s wears his own figure and has his own photo (cell %d)" % [id, cell])
		var here: Vector2 = Simulation.position_of(unit)
		_expect(not sim.is_blocked(here), "%s starts on open ground" % id)
		_expect(Rect2(m(world.patio[0], world.patio[1]), m(world.patio[2] - world.patio[0], world.patio[3] - world.patio[1])).has_point(here), "%s starts in the courtyard" % id)
		_expect(sim.fresh_snow(here), "%s starts in fresh snow" % id)
	var hornero: Dictionary = sim.unit_by_id("hornero")
	_expect(bool(hornero.tools) and hornero.has("cover") and str(hornero.throw.icon) == "bell" and float(hornero.melee.stun) > 0.0 and not bool(hornero.melee.lethal), "Hornero: tools, the motorman's cover, the bell, the controller handle (a cosh)")
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	_expect(not bool(lechuza.tools) and not bool(lechuza.melee.lethal) and float(lechuza.melee.get("stun", 0.0)) == 0.0, "Lechuza binds")
	_expect(sim.can_sabotage(lechuza) and not sim.can_sabotage(hornero), "the lamp board is Lechuza's")
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	_expect(benteveo.has("cover") and str(benteveo.throw.icon) == "papers" and not benteveo.has("melee") and not benteveo.has("gun"), "Benteveo: the crowd, the papers, no weapon")
	var bigua: Dictionary = sim.unit_by_id("bigua")
	_expect(bool(bigua.melee.lethal) and str(bigua.melee.icon) == "knife", "Biguá's knife kills (as in the other operations)")
	for unit: Dictionary in sim.units:
		_expect(not unit.has("gun"), "%s carries no gun" % unit.id)
	_expect(sim.has_prisoner and str(sim.prisoner.name) == "The passenger" and data.has("door"), "a passenger behind a door")
	_expect(not sim.is_blocked(_door_spot()), "the cellar door can be worked from the café")
	_expect(not sim.is_blocked(_passenger()), "the passenger stands on open ground")
	_expect(sim.is_blocked(Simulation.rect_of(data.door).get_center()), "the closed door is in the way")
	_expect(not sim.line_of_sight(_door_spot(), _passenger()), "and nobody sees through it")
	_expect(not sim.is_blocked(Vector2(float(data.radio.x), float(data.radio.y))), "the lamp board can be stood at")
	for id: String in ["ladder", "gondola", "boat"]:
		_expect(not sim.is_blocked(_anchor(sim, id)), "the %s's anchor is open ground" % id)
	_expect(not sim.is_blocked(_far_bank()), "the far bank's lane is open ground")
	_expect(data.theme == "boca" and data.has("bocaWorld") and data.has("tracks"), "the boca world, and its own rails for the recon map")
	_expect(not sim.ready_to_leave(), "not before the cellar is open and the passenger out")
	_expect(sim.guards.size() >= 20, "a strong night (%d on the street)" % sim.guards.size())
	var lit: int = 0
	for r: Array in data.floodlit:
		if r.size() > 4 and str(r[4]) == "powered": lit += 1
	_expect(lit >= 2 and lit < data.floodlit.size(), "some lamps hang from the board, some not")

## Everything that matters is on the grid, and only the right ways join it up.
func _reachable() -> void:
	var sim: RefCounted = _fresh()
	var start: Vector2 = _start()
	var south: Vector2 = m(105.0, 42.0)
	_expect(not sim.find_path(start, south).is_empty(), "the courtyard and the far side of the cutting are joined (by the bridges)")
	var long_way: float = sim._path_length(start, sim.find_path(start, south))
	_rig(sim, "ladder", "lechuza")
	var short_way: float = sim._path_length(start, sim.find_path(start, south))
	_expect(short_way < long_way * 0.5, "the ladder saves the long way round by a bridge (%.0f m against %.0f m)" % [short_way / 32.0, long_way / 32.0])
	for spot: Array in [["the cellar door", _door_spot()], ["the lamp board", Vector2(float(data.radio.x), float(data.radio.y))],
			["the gondola's landing", _anchor(sim, "gondola")], ["the boat's slip", _anchor(sim, "boat")]]:
		_expect(not sim.find_path(start, spot[1]).is_empty(), "%s can be reached from the courtyard" % spot[0])
	_expect(sim.find_path(start, _passenger()).is_empty(), "the passenger cannot be reached while the cellar is locked")
	_cellar_open(sim)
	_expect(not sim.find_path(start, _passenger()).is_empty(), "and can once it is open")
	_expect(sim.find_path(start, _far_bank()).is_empty(), "the far bank cannot be reached: the river is the river")
	_rig(sim, "boat", "bigua")
	_expect(sim.find_path(start, _far_bank()).is_empty(), "not by the boat either, for everyone else")
	_rig(sim, "gondola", "hornero")
	_expect(not sim.find_path(start, _far_bank()).is_empty(), "the gondola joins the two banks")
	# the café: by the front door on the square and by the back door on the alley
	var room: Vector2 = m(72.0, 91.0)
	_expect(not sim.find_path(m(67.0, 97.0), room).is_empty() and not sim.find_path(m(82.0, 87.0), room).is_empty(), "the café has a front door and a back door")
	_expect(sim._path_length(m(82.0, 87.0), sim.find_path(m(82.0, 87.0), room)) < m(12.0, 0.0).x, "the back door is a short step from the alley")

## Every walking guard can walk his round, and the reinforcements theirs: each point on open ground, a way from each to
## the next.
func _rounds() -> void:
	var sim: RefCounted = _fresh(false)
	var rounds: Array = []
	for guard: Dictionary in sim.guards:
		if bool(guard.static) or float(guard.elevation) > 0.0 or str(guard.state) == "calm":
			continue
		_expect(not sim.is_blocked(Simulation.position_of(guard)), "guard %s starts on open ground" % guard.id)
		rounds.append([str(guard.id), guard.get("route", [])])
	for i: int in range(data.reinforcements.routes.size()):
		rounds.append(["reinforcement %d" % (i + 1), data.reinforcements.routes[i]])
	for entry: Array in rounds:
		var route: Array = entry[1]
		for i: int in range(route.size()):
			var a := Vector2(float(route[i][0]), float(route[i][1]))
			var b := Vector2(float(route[(i + 1) % route.size()][0]), float(route[(i + 1) % route.size()][1]))
			_expect(not sim.is_blocked(a), "%s: round point %d is open ground" % [entry[0], i])
			_expect(a.distance_to(b) < 4.0 or not sim.find_path(a, b).is_empty(), "%s: a way from round point %d to the next" % [entry[0], i])
	for spawn: Array in data.reinforcements.spawn:
		_expect(not sim.is_blocked(Vector2(float(spawn[0]), float(spawn[1]))), "reinforcements turn out on open ground")
	# a minute of the night: every walker moves and nobody is stuck
	var before: Dictionary = {}
	for guard: Dictionary in sim.guards: before[guard.id] = Simulation.position_of(guard)
	_park(sim, [])
	_run_for(sim, 60.0)
	for guard: Dictionary in sim.guards:
		if bool(guard.has_post) or str(guard.state) == "calm" or bool(guard.static): continue
		_expect(Simulation.position_of(guard).distance_to(before[guard.id]) > 32.0 or not guard.path.is_empty(), "%s is on his round" % guard.id)
	_expect(int(sim.alarm.count) == 0, "with the squad out of the way, a quiet minute")

## The cellar door: Hornero's keys only; it opens the way to the passenger.
func _the_cellar() -> void:
	var sim: RefCounted = _fresh()
	_park(sim, ["lechuza", "hornero"])
	_put(sim, "lechuza", _door_spot())
	sim.select("lechuza")
	_expect(not sim.order_unlock() and sim.message.contains("Hornero"), "only Hornero opens the cellar (%s)" % sim.message)
	_expect(not sim.interact() and sim.message.contains("Hornero"), "the old context order says so too")
	_put(sim, "lechuza", m(232.0, 26.0))
	_put(sim, "hornero", _door_spot() + Vector2(40.0, 30.0))
	sim.select("hornero")
	_expect(sim.order_unlock() and sim.message.contains("cellar door"), "Hornero goes to the cellar door (%s)" % sim.message)
	_run_for(sim, 4.0)
	_expect(sim.door_open and _objective_done(sim, "cell"), "the cellar is open")
	_expect(sim.message.contains("passenger"), "and the player is told about the passenger, not an informant (%s)" % sim.message)
	_expect(not sim.order_unlock() and sim.message.contains("already open"), "only once")
	_expect(not sim.is_blocked(Simulation.rect_of(data.door).get_center()), "the doorway is open ground now")
	_expect(sim.line_of_sight(_door_spot(), _passenger()), "and open to the eye")

## The passenger: freed, he follows; he cannot crouch; on the far bank he is safe. Every word about him is the data's.
func _the_passenger() -> void:
	var sim: RefCounted = _fresh()
	_park(sim, ["benteveo"])
	_put(sim, "benteveo", _door_spot())
	sim.select("benteveo")
	_expect(not sim.order_rescue() and sim.message.contains("still locked"), "a locked cellar: %s" % sim.message)
	_cellar_open(sim)
	_expect(sim.order_rescue() and sim.message.contains("passenger") and not sim.message.contains("informant"), "Benteveo goes for him: %s" % sim.message)
	_run_for(sim, 4.0)
	_expect(bool(sim.prisoner.freed) and str(sim.prisoner.follow_id) == "benteveo", "freed, with Benteveo")
	_expect(sim.message.contains("passenger") and _objective_done(sim, "informant"), "the passenger follows: %s" % sim.message)
	_expect(not sim.order_rescue() and sim.message.contains("already following"), "already with him")
	sim.select("benteveo")
	sim.move_to(m(72.0, 91.0))
	_run_for(sim, 8.0)
	_expect(Simulation.position_of(sim.prisoner).distance_to(m(72.0, 91.0)) < 50.0, "he follows Benteveo into the café room")
	_expect(sim.is_exposed(sim.prisoner) or bool(sim.prisoner.hidden), "he cannot crouch")
	# on the far bank: safe, the player told in the data's words
	sim = _fresh()
	_cellar_open(sim)
	_rig(sim, "gondola", "hornero")
	_park(sim, ["hornero"])
	sim.prisoner.freed = true
	sim.prisoner.follow_id = "hornero"
	_put(sim, "hornero", m(100.0, 139.0))
	sim.prisoner.x = m(100.0, 138.0).x
	sim.prisoner.y = m(100.0, 138.0).y
	sim.select("hornero")
	sim.move_to(_far_bank())
	_run_for(sim, 5.0)
	_expect(bool(sim.prisoner.aboard) and sim.message.contains("far bank"), "on the far bank with friends: %s" % sim.message)
	_expect(not sim.order_rescue() and sim.message.contains("already across"), "and nobody takes him back: %s" % sim.message)
	# a prisoner without a door (a mission that has none) can be freed at once
	var doorless: Dictionary = data.duplicate(true)
	doorless.erase("door")
	var free: RefCounted = Simulation.new(doorless)
	free.start()
	free.toggle_pause()
	free.guards.clear()
	free.unit_by_id("lechuza").x = _passenger().x + 20.0
	free.unit_by_id("lechuza").y = _passenger().y
	free.select("lechuza")
	_expect(free.order_rescue(), "with no door there is nothing to unlock")
	_run_for(free, 2.0)
	_expect(bool(free.prisoner.freed), "and he is freed")
	_expect(not free.interactables().any(func(t: Dictionary) -> bool: return str(t.type) == "gate"), "no door to tap")

## The lamp board: Lechuza's key; the quay's lamps go out, the road bridge's stay lit; the patrolmen under them see
## less; an alarm brings nobody from the post.
func _lamp_board() -> void:
	var sim: RefCounted = _fresh(false)
	var board: Vector2 = Vector2(float(data.radio.x), float(data.radio.y))
	var quay: Vector2 = m(75.0, 107.5)
	var landing: Vector2 = m(150.0, 108.0)
	var bridge: Vector2 = m(164.0, 34.0)
	_expect(sim.floodlit(quay) and sim.floodlit(landing) and sim.floodlit(bridge), "the quay, the landing and the road bridge are lit")
	_park(sim, ["hornero", "lechuza"])
	_put(sim, "hornero", board + Vector2(0.0, 12.0))
	sim.select("hornero")
	_expect(not sim.order_sabotage() and sim.message.contains("Lechuza"), "only Lechuza has the key (%s)" % sim.message)
	_put(sim, "hornero", m(230.0, 24.0))
	_put(sim, "lechuza", board + Vector2(-40.0, 10.0))
	var landing_man: Dictionary = sim.guard_by_id("landing")
	var range_lit: float = float(landing_man.base_range)
	sim.guards = [landing_man]
	sim.select("lechuza")
	_expect(sim.order_sabotage() and sim.message.contains("lamp column"), "Lechuza climbs the column (%s)" % sim.message)
	_run_for(sim, 5.0)
	_expect(sim.radio_cut and _objective_done(sim, "radio"), "the board is cut")
	_expect(sim.message.contains("quay's lamps go out"), "the player is told (%s)" % sim.message)
	_expect(not sim.floodlit(quay) and not sim.floodlit(landing), "the quay and the landing go dark")
	_expect(sim.floodlit(bridge), "the road bridge keeps its lamp: another board")
	_expect(bool(landing_man.get("dark", false)) and float(landing_man.base_range) < range_lit, "the man on the landing sees less in the dark (%.0f of %.0f)" % [float(landing_man.base_range), range_lit])
	_expect(sim.badge_earned("saboteur"), "the Saboteur badge")
	var badge: Dictionary = {}
	for b: Dictionary in sim.result_badges():
		if str(b.id) == "saboteur": badge = b
	_expect(str(badge.text).contains("quay"), "for the quay's lamps (%s)" % str(badge.text))
	var available: Dictionary = {}
	for a: Dictionary in sim.available_actions("lechuza"):
		if str(a.id) == "sabotage": available = a
	_expect(not available.is_empty() and str(available.label) == "Lamp board" and not bool(available.enabled) and str(available.reason).contains("out"), "the bar says the lamps are out")
	# an alarm now calls nobody out of the post
	sim._raise_alarm("spotted", m(75.0, 100.0))
	_expect(int(sim.alarm.reinforce_pending) == 0, "no men from the post with the lamps out")

## Under the quay's lamps a crouching man in a guard's far zone is seen; with the board cut he is not.
func _floodlights() -> void:
	var sim: RefCounted = _fresh()
	var guard: Dictionary = _watcher(sim, "quay", m(70.0, 108.4), 0.0)
	_park(sim, ["bigua"])
	_put(sim, "bigua", m(70.0, 108.4) + Vector2(150.0, 0.0))
	var bigua: Dictionary = sim.unit_by_id("bigua")
	_expect(str(bigua.stance) == "sneak" and Vector2(150.0, 0.0).length() > float(guard.near), "Biguá crouched, in the far zone")
	_expect(sim.visibility(guard, bigua) == 1, "under the lamps he is seen all the same")
	sim.radio_cut = true
	_expect(sim.visibility(guard, bigua) == 0, "in the dark the far zone does not see a crouching man")
	sim.radio_cut = false
	_run_for(sim, 3.0)
	_expect(int(sim.alarm.count) > 0, "lit, he is spotted")

## Lechuza's ladder: down the cutting by the courtyard and up the far side; his alone to set, anyone's to climb.
func _ladder() -> void:
	var sim: RefCounted = _fresh()
	var anchor: Vector2 = _anchor(sim, "ladder")
	var cut_middle: Vector2 = m((float(world.ladder[0]) + float(world.ladder[1])) / 2.0, (float(world.cut[0]) + float(world.cut[1])) / 2.0)
	_expect(sim.is_blocked(cut_middle), "the cutting is sheer until the ladder is down")
	_expect(sim.line_of_sight(m(105.0, 28.0), m(105.0, 40.0)), "it stops feet, not eyes")
	_put(sim, "benteveo", anchor)
	sim.select("benteveo")
	_expect(not sim.order_rig("ladder") and sim.message.contains("Lechuza"), "only Lechuza sets it (%s)" % sim.message)
	_put(sim, "benteveo", m(110.0, 10.0))
	_put(sim, "lechuza", anchor + Vector2(30.0, -30.0))
	sim.select("lechuza")
	_expect(sim.order_rig(""), "Lechuza: the nearest of his jobs")
	_run_for(sim, 6.0)
	_expect(sim.rigged.has("ladder") and _events(sim, "rigged").size() == 1, "the ladder is set")
	_expect(not sim.is_blocked(cut_middle), "the stretch can be climbed now")
	_expect(sim.is_blocked(cut_middle + Vector2(64.0, 0.0)) and sim.is_blocked(cut_middle - Vector2(64.0, 0.0)), "only that stretch")
	_expect(str(sim.checkpoint.get("label", "")) == "ladder" or sim._pending_checkpoint == "ladder", "a checkpoint")
	_put(sim, "benteveo", m(105.0, 29.5))
	sim.select("benteveo")
	sim.toggle_stance()
	sim.move_to(m(105.0, 40.0))
	_run_for(sim, 1.5)
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	_expect(sim.climbing(benteveo), "on the ladder")
	var y0: float = float(benteveo.y)
	_run_for(sim, 1.0)
	_expect(float(benteveo.y) - y0 < Simulation.WALK_SPEED * 0.6, "climbing slowly (%.0f units a second)" % (float(benteveo.y) - y0))
	_run_for(sim, 10.0)
	_expect(float(benteveo.y) > m(0.0, 38.5).y, "Benteveo is across the cutting")

## Hornero's gondola: worked from the landing's controls, by him alone; then anyone rides across, slowly.
func _gondola() -> void:
	var sim: RefCounted = _fresh()
	var anchor: Vector2 = _anchor(sim, "gondola")
	var mid_river: Vector2 = m((float(world.gondola[0]) + float(world.gondola[1])) / 2.0, 122.0)
	_expect(sim.is_blocked(mid_river), "the river under the bridge is water until the gondola runs")
	for id: String in ["lechuza", "benteveo", "bigua"]:
		_put(sim, id, anchor)
		sim.select(id)
		_expect(not sim.order_rig("gondola") and sim.message.contains("Hornero"), "%s cannot work it (%s)" % [id, sim.message])
		_put(sim, id, m(230.0 - 3.0 * float(["lechuza", "benteveo", "bigua"].find(id)), 24.0))
	_put(sim, "hornero", anchor + Vector2(-60.0, -60.0))
	sim.select("hornero")
	_expect(sim.order_rig("gondola") and sim.message.contains("controls"), "Hornero works the controls (%s)" % sim.message)
	_run_for(sim, 4.0)
	_expect(not sim.rigged.has("gondola"), "it takes him a while")
	_run_for(sim, 4.0)
	_expect(sim.rigged.has("gondola") and str(sim.rigged.gondola) == "hornero", "the gondola runs")
	_expect(not sim.is_blocked(mid_river), "the gondola's run is open")
	_expect(sim.is_blocked(mid_river + Vector2(m(6.0, 0.0).x, 0.0)), "and only under the bridge")
	_put(sim, "lechuza", anchor)
	sim.select("lechuza")
	_expect(sim.move_to(m(150.0, 136.0)), "Lechuza rides across")
	_run_for(sim, 4.0)
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	_expect(sim.climbing(lechuza), "slowly, on the gondola")
	_run_for(sim, 30.0)
	_expect(float(lechuza.y) > m(0.0, 134.0).y, "and is on the far bank")

## Biguá's boat: only he launches it and only he rows it, with whoever he is escorting; for everyone else the river is
## still the river.
func _boat() -> void:
	var sim: RefCounted = _fresh()
	var anchor: Vector2 = _anchor(sim, "boat")
	var far_side: Vector2 = m((float(world.boat[0]) + float(world.boat[1])) / 2.0, 136.0)
	_put(sim, "hornero", anchor)
	sim.select("hornero")
	_expect(not sim.order_rig("boat") and sim.message.contains("Biguá"), "Hornero cannot launch it (%s)" % sim.message)
	_put(sim, "hornero", m(230.0, 24.0))
	_put(sim, "bigua", anchor + Vector2(40.0, -20.0))
	sim.select("bigua")
	_expect(sim.order_rig("boat"), "Biguá runs the boat down the slip")
	_run_for(sim, 5.0)
	_expect(sim.rigged.has("boat"), "the boat is in the water")
	# everyone else: the river is the river
	_expect(sim.is_blocked(m(45.0, 122.0)), "for everyone else the boat's water is still water")
	_put(sim, "hornero", anchor)
	_expect(sim.find_path(anchor, far_side).is_empty(), "no way across for anyone else")
	sim.select("hornero")
	var refused: bool = not sim.move_to(far_side)
	_expect(refused or float(sim.unit_by_id("hornero").order.get("y", 0.0)) < m(0.0, 110.0).y, "Hornero cannot be sent over the water")
	_put(sim, "hornero", m(230.0, 24.0))
	# Biguá rows over with the passenger behind him
	_cellar_open(sim)
	sim.prisoner.freed = true
	sim.prisoner.follow_id = "bigua"
	sim.prisoner.x = anchor.x + 20.0
	sim.prisoner.y = anchor.y - 16.0
	_put(sim, "bigua", anchor)
	sim.select("bigua")
	_expect(sim.move_to(far_side), "Biguá rows for the far bank")
	_run_for(sim, 2.0)
	var bigua: Dictionary = sim.unit_by_id("bigua")
	_expect(sim.climbing(bigua), "rowing: slow")
	_run_for(sim, 40.0)
	_expect(float(bigua.y) > m(0.0, 134.0).y, "Biguá is over")
	_expect(float(sim.prisoner.y) > m(0.0, 133.0).y, "and the passenger with him (%s)" % str(Simulation.position_of(sim.prisoner) / 32.0))
	_expect(sim.passage_open_to(sim.passage_by_id("boat"), bigua) and sim.passage_open_to(sim.passage_by_id("boat"), sim.prisoner), "the boat is open to the two of them")
	_expect(not sim.passage_open_to(sim.passage_by_id("boat"), sim.unit_by_id("lechuza")), "and to nobody else")
	# behind another escort the passenger stays on the quay
	sim = _fresh()
	_rig(sim, "boat", "bigua")
	_cellar_open(sim)
	sim.prisoner.freed = true
	sim.prisoner.follow_id = "lechuza"
	sim.prisoner.x = anchor.x + 20.0
	sim.prisoner.y = anchor.y - 16.0
	_put(sim, "lechuza", anchor)
	sim.select("lechuza")
	sim.move_to(far_side)
	_run_for(sim, 20.0)
	_expect(float(sim.prisoner.y) < m(0.0, 110.0).y and float(sim.unit_by_id("lechuza").y) < m(0.0, 110.0).y, "behind Lechuza nobody crosses by the boat")
	# the crew's ground and everyone's stay apart through a checkpoint
	sim = _fresh()
	var saved: Dictionary = sim.snapshot()
	_rig(sim, "boat", "bigua")
	sim.select("bigua")
	_put(sim, "bigua", anchor)
	_expect(sim.move_to(far_side), "rigged: Biguá may go")
	sim.restore(saved)
	_put(sim, "bigua", anchor)
	sim.select("bigua")
	_expect(not sim.move_to(far_side) or float(sim.unit_by_id("bigua").order.get("y", 0.0)) < m(0.0, 110.0).y, "restored to before the launch: not even Biguá")

## Hornero on the tram lines and Benteveo in the crowds pass unremarked, upright; off them, or before those who know
## them, they are men out after the curfew.
func _covers() -> void:
	var sim: RefCounted = _fresh()
	var hornero: Dictionary = sim.unit_by_id("hornero")
	sim.select("hornero")
	sim.toggle_stance()
	_expect(str(hornero.stance) == "walk", "Hornero upright")
	for spot: Vector2 in [m(100.0, 102.5), m(200.0, 103.0), m(123.0, 60.0), m(123.0, 98.0)]:
		_expect(sim.covered_at(hornero, spot), "a motorman on the tram lines at %s" % str(spot / 32.0))
	for spot: Vector2 in [m(110.0, 10.0), m(53.0, 70.0), m(75.0, 108.0), m(70.0, 90.0), m(150.0, 108.0)]:
		_expect(not sim.covered_at(hornero, spot), "a man out after the curfew at %s" % str(spot / 32.0))
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	sim.select("benteveo")
	sim.toggle_stance()
	for spot: Vector2 in [m(75.0, 97.0), m(72.0, 90.0), m(110.0, 23.0)]:
		_expect(sim.covered_at(benteveo, spot), "one of the crowd at %s" % str(spot / 32.0))
	for spot: Vector2 in [m(75.0, 108.0), m(100.0, 102.5), m(53.0, 70.0), m(62.0, 83.0)]:
		_expect(not sim.covered_at(benteveo, spot), "on his own at %s" % str(spot / 32.0))
	# walked past a patrolman on the avenue, Hornero is let be
	sim = _fresh()
	_park(sim, ["hornero"])
	var avenue: Dictionary = _watcher(sim, "avenue", m(110.0, 102.5), 180.0)
	_put(sim, "hornero", m(108.0, 102.5))
	sim.select("hornero")
	sim.toggle_stance()
	_expect(sim.visibility(avenue, sim.unit_by_id("hornero")) > 0, "a patrolman who sees him plainly")
	sim.move_to(m(80.0, 102.5))
	_run_for(sim, 10.0)
	_expect(int(sim.alarm.count) == 0 and not bool(sim.unit_by_id("hornero").blown), "Hornero walks the avenue past him")
	# the sergeant knows him
	sim = _fresh()
	_park(sim, ["hornero"])
	var sergeant: Dictionary = _watcher(sim, "sergeant", m(110.0, 102.5), 180.0)
	_put(sim, "hornero", m(104.0, 102.5))
	sim.select("hornero")
	sim.toggle_stance()
	_expect(sim.sees_through(sergeant, sim.unit_by_id("hornero")), "the sergeant knows Hornero")
	_run_for(sim, 3.0)
	_expect(int(sim.alarm.count) > 0, "and gives the alarm")
	# the informer knows Benteveo
	sim = _fresh(false)
	_only(sim, ["informer"])
	_park(sim, ["benteveo"])
	var informer: Dictionary = sim.guard_by_id("informer")
	informer.has_scan = false
	informer.angle = 0.0
	informer.post_angle = 0.0
	_put(sim, "benteveo", Simulation.position_of(informer) + Vector2(90.0, 10.0))
	sim.select("benteveo")
	sim.toggle_stance()
	_expect(sim.covered(sim.unit_by_id("benteveo")) and sim.sees_through(informer, sim.unit_by_id("benteveo")), "in the crowd, but the informer knows him")
	_run_for(sim, 3.0)
	_expect(int(sim.alarm.count) > 0, "and he shouts")

## The neighbours out in the snow: calm, they see nothing, raise nothing, and nobody lays a hand on them.
func _neighbours() -> void:
	var sim: RefCounted = _fresh(false)
	var calm: Array = []
	for guard: Dictionary in sim.guards:
		if bool(guard.get("calm", false)): calm.append(guard)
	_expect(calm.size() >= 8, "neighbours out to see the snow (%d)" % calm.size())
	for guard: Dictionary in calm:
		_expect(str(guard.state) == "calm" and bool(guard.civilian), "%s is calm" % guard.id)
		_expect(sim.zone_at(guard, Simulation.position_of(guard) + Vector2.from_angle(float(guard.angle)) * 40.0, true) == 0, "%s draws no cone" % guard.id)
	var n2: Dictionary = sim.guard_by_id("n2")
	_only(sim, ["n2"])
	_park(sim, ["bigua", "lechuza", "hornero"])
	_put(sim, "bigua", Simulation.position_of(n2) + Vector2(20.0, 0.0))
	sim.select("bigua")
	sim.toggle_stance()
	_expect(not sim.order_takedown("n2") and sim.message.contains("snow"), "Biguá leaves the neighbour be (%s)" % sim.message)
	_put(sim, "lechuza", Simulation.position_of(n2) + Vector2(-20.0, 0.0))
	sim.select("lechuza")
	_expect(not sim.order_takedown("n2"), "nobody ties up a neighbour watching the snow")
	_put(sim, "hornero", Simulation.position_of(n2) + Vector2(0.0, 20.0))
	sim.select("hornero")
	_expect(not sim.order_takedown("n2"), "nor coshes him")
	_expect(not sim.order_pickup("n2"), "he is not a body")
	_run_for(sim, 5.0)
	_expect(int(sim.alarm.count) == 0, "three strangers stand beside him and he only watches the snow")
	var listed: Array = []
	for thing: Dictionary in sim.interactables():
		listed.append(str(thing.id))
	_expect(not "n2" in listed, "nothing to tap on him")
	# the snapshot keeps them calm
	var saved: Dictionary = sim.snapshot()
	var other: RefCounted = _fresh()
	other.restore(saved)
	_expect(str(other.guard_by_id("n2").state) == "calm", "calm through a checkpoint")

## The informer on the square: a civilian with no gun who shouts at what he sees; no knife for him, but a cord or the
## controller handle will do.
func _informer() -> void:
	var sim: RefCounted = _fresh(false)
	_only(sim, ["informer"])
	_park(sim, ["lechuza"])
	var informer: Dictionary = sim.guard_by_id("informer")
	_expect(bool(informer.civilian) and bool(informer.alarm_hold) and not bool(informer.get("calm", false)), "a civilian, on watch, who stays put")
	informer.has_scan = false
	informer.angle = PI
	informer.post_angle = PI
	_put(sim, "lechuza", Simulation.position_of(informer) + Vector2(-90.0, 0.0))
	sim.select("lechuza")
	sim.toggle_stance()
	_run_for(sim, 3.0)
	_expect(int(sim.alarm.count) == 1, "he sees Lechuza and raises the alarm")
	_expect(_events(sim, "guard_shot").is_empty() and int(sim.unit_by_id("lechuza").hp) == 100, "he has no gun")
	_expect(str(informer.state) == "hunt" and informer.path.is_empty(), "he stays where he is")
	# the knife is refused, the cord is not
	sim = _fresh(false)
	_only(sim, ["informer"])
	_park(sim, ["bigua", "lechuza"])
	informer = sim.guard_by_id("informer")
	informer.has_scan = false
	informer.angle = 0.0
	informer.post_angle = 0.0
	_put(sim, "bigua", Simulation.position_of(informer) + Vector2(-20.0, 0.0))
	sim.select("bigua")
	_expect(not sim.order_takedown("informer") and sim.message.contains("neighbour"), "Biguá will not knife him (%s)" % sim.message)
	_put(sim, "bigua", m(230.0, 24.0))
	_put(sim, "lechuza", Simulation.position_of(informer) + Vector2(-20.0, 0.0))
	sim.select("lechuza")
	_expect(sim.order_takedown("informer"), "Lechuza ties him up")
	_run_for(sim, 3.0)
	_expect(str(informer.state) == "bound" and int(sim.alarm.count) == 0, "bound and gagged, from behind, quietly")

## Hornero's bell and Benteveo's papers draw the guards; the sergeant pays them no mind.
func _throws() -> void:
	var sim: RefCounted = _fresh(false)
	_only(sim, ["alley"])
	var alley: Dictionary = sim.guard_by_id("alley")
	_park(sim, ["hornero", "benteveo"])
	_put(sim, "hornero", m(82.0, 61.0))
	sim.select("hornero")
	var spot: Vector2 = Simulation.position_of(alley) + Vector2(0.0, 90.0)
	_expect(sim.distract(spot), "Hornero rings the bell")
	_run_for(sim, 0.2)
	var rung: Array = _events(sim, "pebble")
	_expect(rung.size() == 1 and str(rung[0].noise) == "bell", "a bell, not a pebble")
	_expect(str(alley.state) == "investigate", "the alley man goes to look (%s)" % alley.state)
	_expect(sim.message.contains("bell"), "the player is told (%s)" % sim.message)
	_expect(int(sim.unit_by_id("hornero").throws) == int(data.units[0].throw.count) - 1, "one ring fewer")
	sim = _fresh(false)
	_only(sim, ["alley"])
	alley = sim.guard_by_id("alley")
	_park(sim, ["benteveo"])
	_put(sim, "benteveo", m(82.0, 61.0))
	sim.select("benteveo")
	_expect(sim.distract(Simulation.position_of(alley) + Vector2(0.0, 90.0)), "Benteveo throws a bundle of papers")
	_run_for(sim, 0.2)
	_expect(str(_events(sim, "pebble")[0].noise) == "papers" and str(alley.state) == "investigate", "and shouts the late edition: he comes")
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	benteveo.throws = 0
	benteveo.cooldown = 0.0
	_expect(not sim.distract(m(80.0, 60.0)) and sim.message.contains("no papers"), "until he has none left (%s)" % sim.message)
	_expect(not sim.unit_by_id("lechuza").has("throw") and sim.throw_spec(sim.unit_by_id("lechuza")).is_empty(), "Lechuza throws nothing")
	sim = _fresh(false)
	_only(sim, ["sergeant"])
	var sergeant: Dictionary = sim.guard_by_id("sergeant")
	_park(sim, ["hornero"])
	_put(sim, "hornero", Simulation.position_of(sergeant) + Vector2(0.0, -300.0))
	sim.select("hornero")
	sim.distract(Simulation.position_of(sergeant) + Vector2(60.0, 0.0))
	_run_for(sim, 0.3)
	_expect(str(sergeant.state) != "investigate", "the sergeant is not drawn by a bell")

## Footprints: in the courtyard, on the quay, in the cutting; not on the trodden streets, the tram rails or indoors.
func _tracks() -> void:
	for case: Array in [["the courtyard", m(104.0, 6.0), m(116.0, 6.0), true], ["the quay", m(64.0, 109.0), m(90.0, 109.0), true],
			["the alley", m(82.0, 75.0), m(82.0, 85.0), true], ["the avenue", m(60.0, 102.5), m(90.0, 102.5), false],
			["the north street", m(60.0, 25.0), m(90.0, 25.0), false], ["the café", m(68.0, 89.0), m(76.0, 89.0), false],
			["the tram street", m(123.0, 50.0), m(123.0, 62.0), false]]:
		var sim: RefCounted = _fresh()
		_park(sim, ["lechuza"])
		_put(sim, "lechuza", case[1])
		sim.select("lechuza")
		sim.toggle_stance()
		sim.move_to(case[2])
		_run_for(sim, 6.0)
		var mine: int = 0
		for p: Dictionary in sim.live_tracks():
			if str(p.by) == "lechuza": mine += 1
		if bool(case[3]): _expect(mine >= 4, "footprints in %s (%d)" % [case[0], mine])
		else: _expect(mine == 0, "no footprints in %s (%d)" % [case[0], mine])
	var sim: RefCounted = _fresh()
	_expect(sim.data.snow.has("seen") and str(sim.data.snow.seen).contains("footprints"), "the player is told in the data's words")

## The river launch's searchlight: inside its beam crouching hides nobody; it sweeps the boat's water but never the far
## half of it, and nobody can reach it.
func _searchlight() -> void:
	var sim: RefCounted = _fresh(false)
	_only(sim, ["launch"])
	var launch: Dictionary = sim.guard_by_id("launch")
	_expect(str(launch.kind) == "searchlight" and bool(launch.static) and bool(launch.lure_immune) and bool(launch.melee_immune) and float(launch.elevation) > 0.0, "a searchlight nobody draws off or reaches")
	launch.has_scan = false
	var slip: Vector2 = m(45.0, 112.0)
	launch.angle = (slip - Simulation.position_of(launch)).angle()
	launch.post_angle = launch.angle
	_park(sim, ["bigua"])
	_put(sim, "bigua", m(45.0, 109.2))
	_expect(str(sim.unit_by_id("bigua").stance) == "sneak", "Biguá crouched at the slip")
	_expect(sim.visibility(launch, sim.unit_by_id("bigua")) > 0, "in the beam crouching does not hide him")
	_run_for(sim, 2.0)
	_expect(int(sim.alarm.count) > 0, "and he is seen")
	# the sweep never reaches the far half of the boat's water
	var far_half: Vector2 = m(45.0, 128.0)
	var bearing: float = fposmod(rad_to_deg((far_half - Simulation.position_of(launch)).angle()), 360.0)
	var scan: Dictionary = data.guards.filter(func(g: Dictionary) -> bool: return str(g.id) == "launch")[0].scan
	_expect(bearing < float(scan.from) - 6.0, "the far half of the crossing is out of the sweep (%.0f°)" % bearing)
	# and the café's front on the quay is inside it
	var quay: Vector2 = m(67.0, 108.0)
	var to_quay: float = fposmod(rad_to_deg((quay - Simulation.position_of(launch)).angle()), 360.0)
	_expect(to_quay > float(scan.from) and to_quay < float(scan.to) and Simulation.position_of(launch).distance_to(quay) < float(launch.range), "the quay in front of the café is swept (%.0f°)" % to_quay)

## Every order each operative can be given, paused and running, aimed at the nearest guard, a point beside him or
## nothing: the game answers (accepted or refused) and never falls over. Includes the wire cutters with no wire.
func _every_order() -> void:
	for paused: bool in [true, false]:
		var sim: RefCounted = _fresh(false)
		if paused and not sim.paused: sim.toggle_pause()
		for unit: Dictionary in sim.units:
			var id: String = str(unit.id)
			sim.select(id)
			var here: Vector2 = Simulation.position_of(unit)
			var nearest: String = ""
			var best: float = INF
			for guard: Dictionary in sim.guards:
				var d: float = here.distance_to(Simulation.position_of(guard))
				if d < best:
					best = d
					nearest = str(guard.id)
			var actions: Array = ["move", "stance", "stance", "distract", "takedown", "shoot", "pickup", "drop", "trap", "trap_pickup", "cut", "sabotage",
				"unlock", "rescue", "extract", "plant", "chat", "uniform", "rig", "talk", "interact", "cancel"]
			for a: Dictionary in sim.available_actions(id):
				actions.append(str(a.id))
			for thing: Dictionary in sim.interactables():
				actions.append(str(thing.order))
			for action: String in actions:
				for target: Variant in [null, nearest, here + Vector2(64.0, 0.0), "ladder", "gondola", "boat", "n1", "informer"]:
					var answer: Variant = sim.perform(action, target)
					_expect(typeof(answer) == TYPE_BOOL, "%s: %s %s answered (%s)" % [id, action, str(target), str(answer)])
					_expect(sim.message != "", "%s: %s says something" % [id, action])
				sim.perform("cancel")
			if not paused: _run_for(sim, 0.5)
		# the wire cutters with no wire, either way
		for id: String in ["hornero", "lechuza"]:
			sim.select(id)
			var cut: Variant = sim.order_cut_fence()
			_expect(typeof(cut) == TYPE_BOOL and cut == false and sim.message.contains("no wire"), "%s: no wire to cut here (%s)" % [id, sim.message])
		_run_for(sim, 2.0)
		_expect(sim.phase in ["playing", "lost"], "the night goes on")

func _checkpoints() -> void:
	var sim: RefCounted = _fresh()
	var saved: Dictionary = sim.snapshot()
	_rig(sim, "ladder", "lechuza")
	_rig(sim, "gondola", "hornero")
	sim.door_open = true
	sim.radio_cut = true
	var later: Dictionary = sim.snapshot()
	sim.restore(saved)
	_expect(sim.rigged.is_empty() and not sim.door_open and not sim.radio_cut, "restored: nothing rigged, the cellar shut, the lamps lit")
	_expect(sim.is_blocked(m(105.0, 34.0)) and sim.floodlit(m(75.0, 107.5)), "the cutting sheer and the quay lit again")
	sim.restore(later)
	_expect(not sim.is_blocked(m(105.0, 34.0)) and not sim.floodlit(m(75.0, 107.5)) and sim.door_open, "and back")
	_expect(not sim.is_blocked(m(150.0, 122.0)), "the gondola running")

func _hud_queries() -> void:
	var sim: RefCounted = _fresh(false)
	var bars: Dictionary = {}
	for unit: Dictionary in sim.units:
		var ids: Array = []
		for a: Dictionary in sim.available_actions(str(unit.id)):
			ids.append(str(a.id))
		bars[unit.id] = ids
	_expect("unlock" in bars.hornero and "rig" in bars.hornero and "distract" in bars.hornero and "takedown" in bars.hornero and not "cut" in bars.hornero, "Hornero's bar: the cellar door, the gondola, the bell, the handle, no wire (%s)" % str(bars.hornero))
	_expect("sabotage" in bars.lechuza and "rig" in bars.lechuza and "takedown" in bars.lechuza and not "unlock" in bars.lechuza, "Lechuza's bar: the lamp board, the ladder, the cord (%s)" % str(bars.lechuza))
	_expect("distract" in bars.benteveo and not "takedown" in bars.benteveo and not "rig" in bars.benteveo, "Benteveo's bar: the papers (%s)" % str(bars.benteveo))
	_expect("rig" in bars.bigua and "takedown" in bars.bigua and not "sabotage" in bars.bigua, "Biguá's bar: the boat, the knife (%s)" % str(bars.bigua))
	for unit: Dictionary in sim.units:
		_expect("rescue" in bars[unit.id] and "extract" in bars[unit.id], "%s can take the passenger and head for the far bank" % unit.id)
	var labels: Dictionary = {}
	for a: Dictionary in sim.available_actions("hornero"):
		labels[a.id] = str(a.label)
	_expect(labels.get("unlock", "") == "Cellar" and labels.get("rig", "") == "Gondola" and labels.get("extract", "") == "Far bank" and labels.get("takedown", "") == "Handle", "Hornero's words: %s" % str(labels))
	sim.select("benteveo")
	var things: Dictionary = {}
	for t: Dictionary in sim.interactables():
		things["%s:%s" % [t.type, t.order]] = t
	_expect(things.has("gate:unlock") and not bool(things["gate:unlock"].enabled) and str(things["gate:unlock"].reason).contains("Hornero"), "Benteveo sees the cellar door, but it is Hornero's job")
	_expect(things.has("lamps:sabotage") and things.has("ladder:rig") and things.has("gondola:rig") and things.has("boat:rig"), "the lamp board, the ladder, the gondola and the boat can be tapped (%s)" % str(things.keys()))
	_expect(str(things["gate:unlock"].label) == "Cellar", "the door is the cellar's")

## The level's place on file: second, after the Plaza de Mayo, opened by winning it.
func _on_file() -> void:
	var i: int = Missions.index_of("riachuelo")
	var entry: Dictionary = Missions.LIST[i] if i >= 0 else {}
	_expect(i == 1 and str(entry.number) == "02" and str(entry.tab) == "RIACHUELO" and str(entry.best) == "best_" + str(data.progressKey), "on file as the second level: %s" % str(entry))
	_expect(str(entry.path) == "res://data/riachuelo.json" and str(Missions.load_data("riachuelo").get("id", "")) == str(data.id), "its data on file")
	var won := ConfigFile.new()
	_expect(not Missions.unlocked("riachuelo", won) and Missions.needs("riachuelo") == "Plaza de Mayo", "shut until the Plaza de Mayo is won")
	won.set_value("won", "plaza", true)
	_expect(Missions.unlocked("riachuelo", won) and Missions.next_of("riachuelo") == "", "open once it is, and the last")
