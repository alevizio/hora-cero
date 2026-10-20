extends SceneTree
## Operation Riachuelo through the real 3D scene (it chooses the level itself):
## the La Boca builders make the world, a snowy night; every guard and the passenger have a model and the guards on duty
## a cone; the squad wear the figures their data names; footprints show in the snow; a man on Lechuza's ladder goes down
## into the cutting; the cellar door swings open with the rules; the quay's lamps die with the lamp board while the road
## bridge's stays lit and the launch's searchlight keeps turning with its crew; the gondola rides across with whoever
## is on it; Biguá's boat leaves the slip and carries him and the passenger over the water; and a checkpoint from
## before it all puts it back.
## Run: godot --headless --path godot --script res://tests/riachuelo_scene.gd
const Missions = preload("res://scripts/missions.gd")
const Boca = preload("res://scripts/three_d/boca.gd")
const BocaGround = preload("res://scripts/three_d/boca_ground.gd")
var main: Node3D
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func _frames(n: int) -> void:
	for i: int in range(n): await process_frame

func _step(seconds: float) -> void:
	for i: int in range(int(seconds / 0.05)):
		main.sim.update(0.05)
		main.world.update_visuals(0.05)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _put(id: String, at: Vector2) -> void:
	var unit: Dictionary = main.sim.unit_by_id(id)
	unit.x = at.x
	unit.y = at.y
	unit.path = []

func run() -> void:
	Missions.choose("riachuelo", false)
	var t0: int = Time.get_ticks_msec()
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await _frames(8)
	print("La Boca built in %d ms" % (Time.get_ticks_msec() - t0))
	var sim: RefCounted = main.sim
	var data: Dictionary = sim.data
	var s: Node3D = main.world.structures
	check(str(data.get("id", "")) == "riachuelo-04", "the scene plays Operation Riachuelo")
	check(s.get_script() == Boca and main.world.nature.get_script() == BocaGround, "the La Boca builders made the world")
	check(main.world.atmosphere.night and main.world.atmosphere.snow, "a snowy night")
	check(main.world.actors.size() == data.units.size() + data.guards.size() + 1, "the squad, every guard and the passenger have 3D models (%d)" % main.world.actors.size())
	var watching: int = 0
	for g: Dictionary in sim.guards:
		if not str(g.state) in sim.DOWN_STATES: watching += 1
	check(main.world.cone_nodes.size() >= watching, "every guard on duty has a sight cone (%d of %d)" % [main.world.cone_nodes.size(), watching])
	check(main.hud.portrait_buttons.size() == 4, "a photo for each of the four")
	for unit: Dictionary in data.units:
		var model: Node3D = main.world.actors[str(unit.id)]
		# each of the four in a figure of his own, his kit his own
		check(str(model.look_key) == str(unit.id) and str(model.kind) == str(unit.id) and model.baked, "%s wears his own figure (%s), not Wren's kit" % [unit.id, model.look_key])
	# the Guardia de Emergencia, the informer, the barrio and the passenger: Riachuelo's own people, nobody from the war
	var cast: Dictionary = {}
	for g: Dictionary in data.guards:
		var model: Node3D = main.world.actors[str(g.id)]
		var look: String = str(g.get("look", ""))
		cast[look.rstrip("0123456789")] = true
		check(model.baked and str(model.look_key) == look, "%s wears the look %s (%s)" % [g.id, look, model.look_key])
	check(cast.keys().all(func(k: String) -> bool: return k in ["guardia", "guardia_sgt", "informer", "vecino", "vecina"]), "only the Guardia, the informer and the barrio: %s" % str(cast.keys()))
	var passenger: Node3D = main.world.actors[str(sim.prisoner.id)]
	check(str(passenger.look_key) == "pasajero" and passenger.baked, "the passenger in his borrowed overcoat (%s)" % passenger.look_key)
	check(s.gate != null and is_zero_approx(s.gate.rotation.y), "the cellar door is shut")
	check(s.ladder_node != null and not s.ladder_node.visible, "no ladder until Lechuza sets it")
	check(s.searchlight_rig != null and s.searchlight_light.visible, "the launch's searchlight")
	var powered: Array = []
	var other: Array = []
	for lamp: Dictionary in s.lamps:
		if bool(lamp.powered): powered.append(lamp)
		else: other.append(lamp)
	check(powered.size() == data.bocaWorld.lamps.size() and other.size() >= 2, "the quay's lamps on the board (%d), the bridge's and the Guardia's on their own (%d)" % [powered.size(), other.size()])
	var lit: bool = true
	for lamp: Dictionary in s.lamps: lit = lit and (lamp.light as OmniLight3D).visible
	check(lit, "every lamp lit")
	# every lamp stands where the rules light the ground
	var truthful: bool = true
	for lamp: Dictionary in s.lamps:
		var at: Vector3 = lamp.at
		if bool(lamp.powered) and not sim.floodlit(Vector2(at.x, at.z + 0.6) * 32.0): truthful = false
	check(truthful, "the quay's lamps stand over the rules' lit ground")
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	# footprints in the courtyard
	sim.guards = sim.guards.filter(func(g: Dictionary) -> bool: return str(g.id) == "launch" or bool(g.get("calm", false)))
	_put("lechuza", m(104.0, 6.0))
	sim.select("lechuza")
	sim.move_to(m(116.0, 6.0))
	_step(3.0)
	var prints: MultiMesh = (main.world.nature.get_node("Snow/Footprints") as MultiMeshInstance3D).multimesh
	check(prints.visible_instance_count == sim.live_tracks().size() and prints.visible_instance_count > 4, "his footprints show in the snow (%d)" % prints.visible_instance_count)
	var saved: Dictionary = sim.snapshot()
	# the ladder
	sim.rigged["ladder"] = "lechuza"
	sim._geometry_dirty = true
	_put("lechuza", m(105.0, 34.0))
	_step(0.2)
	check(s.ladder_node.visible, "the ladder is down the cutting once set")
	check((main.world.actors["lechuza"] as Node3D).position.y < -3.0, "Lechuza on the ladder is down in the cutting (%.1f m)" % (main.world.actors["lechuza"] as Node3D).position.y)
	check(absf((main.world.actors["hornero"] as Node3D).position.y) < 0.01, "Hornero in the courtyard stands on the snow")
	# the cellar door
	sim.door_open = true
	_step(1.0)
	check(absf(s.gate.rotation.y) > 1.0, "the cellar door swings open")
	# the lamp board
	var bridge_lamp: Dictionary = other[0]
	sim.radio_cut = true
	_step(1.5)
	var dark: bool = true
	for lamp: Dictionary in powered: dark = dark and not (lamp.light as OmniLight3D).visible
	check(dark, "the quay's lamps die with the board")
	check((bridge_lamp.light as OmniLight3D).visible, "the road bridge's lamp stays lit")
	check(s.searchlight_light.visible, "the launch's searchlight is on its own dynamo")
	var light: Dictionary = sim.guard_by_id("launch")
	_step(1.0)
	check(absf(wrapf(s.searchlight_rig.rotation.y + float(light.angle), -PI, PI)) < 0.2, "the searchlight points where its crew looks")
	# the gondola rides with whoever is on it
	var z0: float = s.gondola.position.z
	sim.rigged["gondola"] = "hornero"
	sim._geometry_dirty = true
	_put("hornero", m(150.0, 124.0))
	_step(2.0)
	check(s.gondola.position.z > z0 + 6.0 and absf(s.gondola.position.z - 124.0) < 1.5, "the gondola is out over the river with Hornero (%.1f m)" % s.gondola.position.z)
	# Biguá's boat
	var rest: Vector3 = s.boat.position
	sim.rigged["boat"] = "bigua"
	sim._geometry_dirty = true
	sim.door_open = true
	sim.prisoner.freed = true
	sim.prisoner.follow_id = "bigua"
	_put("bigua", m(45.0, 118.0))
	sim.prisoner.x = m(45.0, 117.2).x
	sim.prisoner.y = m(45.0, 117.2).y
	_step(0.3)
	check(s.boat.position.distance_to(rest) > 3.0 and absf(s.boat.position.z - 117.6) < 1.0, "the boat is off the slip and under Biguá (%s)" % str(s.boat.position))
	var bigua_y: float = (main.world.actors["bigua"] as Node3D).position.y
	check(bigua_y < -1.5, "Biguá sits in the boat on the water (%.1f m)" % bigua_y)
	check((main.world.actors["asset"] as Node3D).position.y < -1.5, "and the passenger with him")
	# a checkpoint from before puts it all back
	sim.restore(saved)
	_step(1.2)
	var back: bool = true
	for lamp: Dictionary in powered: back = back and (lamp.light as OmniLight3D).visible
	check(back and not s.ladder_node.visible and absf(s.gate.rotation.y) < 0.2, "restored: the lamps lit, no ladder, the cellar shut")
	check(absf(s.gondola.position.z - z0) < 0.5 and s.boat.position.distance_to(rest) < 0.5, "the gondola at its landing, the boat on its slip")
	Missions.choose("plaza", false)
	print("RIACHUELO_SCENE_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
