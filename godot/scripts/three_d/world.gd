extends Node3D
## Authored 3D outpost built from original geometry. Simulation coordinates map to X/Z (32 units = 1 m).
## This script is the orchestrator: it owns the character models, the sight cones, the plan and marker overlays
## drawn on the ground and the short effects that show simulation events; the scenery comes from atmosphere,
## nature and structures.
## Every simulation event (see GAMEPLAY_API.md) is re-emitted here once, in order, for visuals, HUD and audio.
signal sim_event(event: Dictionary)
const Operative = preload("res://scripts/three_d/operative.gd")
const Atmosphere = preload("res://scripts/three_d/atmosphere.gd")
## Comic ink: the view drawn as black ink on newsprint (off unless main.gd turns it on: set_ink).
const ComicInk = preload("res://scripts/three_d/ink.gd")
## La Boca on a snowy night (Operation Riachuelo): the ground, the cutting and the river, and everything standing.
const BocaGround = preload("res://scripts/three_d/boca_ground.gd")
const Boca = preload("res://scripts/three_d/boca.gd")
## The Plaza de Mayo the night the snow begins (Plaza de Mayo, 1958): the ground and its snow, and the square's buildings.
const PlazaGround = preload("res://scripts/three_d/plaza_ground.gd")
const Plaza = preload("res://scripts/three_d/plaza.gd")
## A closing scene played after the win, for a level that has one (a node with start(main, hud), skip(), reset(),
## `running`, `clock` and a `finished` signal); no level of Hora Cero has one yet, so it stays null.
var finale: Node3D
const ConeShader: Shader = preload("res://shaders/world_cone.gdshader")
const MarkShader: Shader = preload("res://shaders/world_mark.gdshader")
const BeamShader: Shader = preload("res://shaders/world_beam.gdshader")

var sim: RefCounted
## Character models by actor id (operatives, guards, the informant) and sight cones by guard id.
var actors: Dictionary = {}
var cone_nodes: Dictionary = {}
var buildings: Array[Dictionary] = []
var gate: Node3D
## The "ink" layer: routes, range rings, outlines. One mesh, redrawn about ten times a second.
var overlays: MeshInstance3D
var visual_clock: float = 0.0
## Cones, and the ring under the selected operative (off for the closing scene and the launch screen).
var draw_vision: bool = true
## Set by the controls while the pebble is being aimed (the same as armed_action == "distract").
var aiming: bool = false
var aim_point: Vector2 = Vector2.ZERO
## Set by the controls while an action waits for its target: "", "shoot" or "distract".
var armed_action: String = ""
## Guards the selected operative could shoot right now (in range, clear line); filled while "shoot" is armed.
var valid_targets: Array[String] = []
## Order previews drawn by the last plan refresh: operative id -> order type ("move", "takedown", ...).
var plan_previews: Dictionary = {}
var root_static: Node3D
## Phones only: if the frame rate stays low, the 3D view (not the HUD) is rendered at a lower resolution.
const ADAPT_TARGET_FPS: float = 48.0
const ADAPT_STEP: float = 0.15
const ADAPT_MIN_SCALE: float = 0.55
var adaptive_quality: bool = OS.has_feature("mobile")
var _adapt_time: float = 0.0
var _adapt_frames: int = 0
var _adapt_slow_seconds: int = 0
var atmosphere: Node3D
var comic_ink: Node3D
var nature: Node3D
var structures: Node3D
## Optional sound module (scripts/three_d/audio.gd): built if the file exists, fed every sim event.
const AUDIO_SCRIPT: String = "res://scripts/three_d/audio.gd"
const Lang = preload("res://scripts/lang.gd")
var audio: Node

# --- sight cones -------------------------------------------------------------------------------------------
const CONE_RAYS: int = 40
## Cone layers lie just above the ground litter (0.025) and below the characters' selection rings (0.04), which
## they would otherwise hide: near zones on the upper band of layers, far zones on the lower, one layer per cone
## (see world_cone.gdshader). Neither band touches 0.032, the top of the duckboards and ground decals.
const CONE_NEAR_Y: float = 0.0335
const CONE_FAR_Y: float = 0.0262
const CONE_LAYERS: int = 12
## Per frame at most this many cones are re-traced, casting at most this many sight rays between them; a frame
## of 0.09 s or longer (tests, captures, a hitch) re-traces every cone.
const CONE_BUDGET: int = 3
const CONE_RAY_BUDGET: int = 48
const C_CALM := Color(0.80, 0.97, 0.34)
const C_WARY := Color(1.0, 0.74, 0.16)
const C_ALARM := Color(1.0, 0.27, 0.19)
## How strongly a figure shows through what hides him (shaders/xray.gdshader).
const XRAY_ALPHA := 0.62
const C_HOT := Color(1.0, 0.34, 0.24)

## One guard's cone: its two materials (near and far zone), where its rays stop, and the values last sent to the
## shader so that nothing is uploaded twice.
class ConeState:
	var material: ShaderMaterial
	var far_material: ShaderMaterial
	var far_node: MeshInstance3D
	var lengths := PackedFloat32Array()
	var traced: bool = false
	var at := Vector2.ZERO
	var angle: float = 0.0
	var reach: float = 0.0
	var fov: float = 0.0
	var door: bool = false
	var coarse: bool = false
	var look: int = -1
	var near: float = -1.0
	var suspicion: float = -1.0
	var far_strength: float = -1.0
	var pulse: float = -1.0
	var drift: float = 0.0
	func put(uniform: StringName, value: Variant) -> void:
		material.set_shader_parameter(uniform, value)
		far_material.set_shader_parameter(uniform, value)

var _cones: Dictionary = {}
var _cone_mesh: ArrayMesh
var _cone_cursor: int = 0
var _cone_depth := PackedFloat32Array()
var _cone_order := PackedInt32Array()
## What can stop a sight ray (simulation rectangles): everything solid / buildings only, for the elevated sentry.
## Only used to skip rays that cannot hit anything; where a ray really stops is always asked of the simulation.
var _blockers: Array[Rect2] = []
var _blockers_tall: Array[Rect2] = []
var _blockers_door: int = -1
var _spans := PackedFloat32Array()
var _bush_uniform := PackedVector4Array()
var _camera: Camera3D

# --- ink, markers, effects ---------------------------------------------------------------------------------
const INK := Color(0.95, 0.93, 0.84)
const CAUTION := Color(1.0, 0.78, 0.22)
const DANGER := Color(1.0, 0.34, 0.24)
const INK_Y: float = 0.09
const MARK_Y: float = 0.105
const PATH_DASH: float = 0.34
const PATH_GAP: float = 0.2
const RING: int = 0
const BRACKET: int = 1
const RETICLE: int = 2
const WAVES: int = 3
const PUFF: int = 4

## A fixed set of marker or beam quads handed out in order each refresh; the rest are hidden.
class Pool:
	var nodes: Array[MeshInstance3D] = []
	var used: int = 0
	func rewind() -> void:
		used = 0
	func hide_rest() -> void:
		for i: int in range(used, nodes.size()):
			nodes[i].visible = false

var _ink: ImmediateMesh
var _plan_clock: float = 1.0
## Markers laid out with the plan (ten times a second) / every frame (things that follow actors, effects).
var _slow_marks := Pool.new()
var _fast_marks := Pool.new()
var _beams := Pool.new()
## Markers that follow an actor, decided with the plan and placed every frame: [id, shape, half, colour, p, line].
var _attached: Array = []
## Running effects: {kind, t, ttl, ...}; advanced in real time so they finish even in command mode.
var _effects: Array[Dictionary] = []
## Reinforcements stepping out of the barracks door: id -> seconds since they appeared.
var _arrivals: Dictionary = {}
var _last_time: float = 0.0
## Bush patches in metres; the cuttable span of the wire in simulation units (empty if the mission has none).
var _bush_rects: Array[Rect2] = []
var _water_uniform := PackedVector4Array()
var _span_rect := Rect2()
var _plan_selected: String = ""
var _plan_armed_action: String = ""
var _plan_aiming: bool = false
var _plan_paused: bool = false

func _ready() -> void:
	if ResourceLoader.exists(AUDIO_SCRIPT):
		audio = load(AUDIO_SCRIPT).new()
		audio.name = "Audio"
		audio.sim = sim
		# the operatives speak the player's language when their lines exist in it (voice/<lang>/), else English
		audio.voice_lang = Lang.current
		add_child(audio)
		audio.build()
		sim_event.connect(audio.on_sim_event)
	# The work spots the character models turn to belong to the mission: look them up afresh.
	Operative.sites.clear()
	Operative.sites_known = false
	# Hora Cero's two worlds: La Boca under snow (Riachuelo, theme "boca") and the Plaza de Mayo the night the snow
	# begins (theme "plaza", built on La Boca's world: the same snowy night in the same city, lit and graded alike)
	var theme: String = str(sim.data.get("theme", ""))
	var plaza: bool = theme == "plaza"
	if not theme in ["plaza", "boca"]: push_error("world.gd: a level's theme is \"plaza\" or \"boca\", not \"%s\"" % theme)
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.sim = sim
	atmosphere.night = true
	atmosphere.snow = true
	atmosphere.boca = true
	add_child(atmosphere)
	atmosphere.build()
	# the Plaza de Mayo's light comes high from the north-north-west, so the buildings round the square throw their
	# shadows behind them (or across their own street), not over the square
	if plaza: atmosphere.sun.rotation_degrees = Vector3(-58, -150, 0)
	comic_ink = ComicInk.new()
	comic_ink.name = "ComicInk"
	comic_ink.atmosphere = atmosphere
	add_child(comic_ink)
	comic_ink.build(theme)
	root_static = Node3D.new()
	root_static.name = "PlazaGeometry" if plaza else "LaBocaGeometry"
	add_child(root_static)
	nature = PlazaGround.new() if plaza else BocaGround.new()
	nature.name = "Ground"
	nature.sim = sim
	root_static.add_child(nature)
	nature.build()
	structures = Plaza.new() if plaza else Boca.new()
	structures.name = "PlazaDeMayo" if plaza else "LaBoca"
	structures.sim = sim
	root_static.add_child(structures)
	structures.build()
	# the river and the mist show the lamps (the ground was built first, so it is told now)
	if nature.has_method("set_lamps") and structures.has_method("lamp_list"): nature.set_lamps(structures.lamp_list())
	gate = structures.gate
	buildings = structures.buildings
	_batch_static()
	_build_overlays()
	for unit: Dictionary in sim.units:
		_spawn_actor(unit, false)
	_sync_guards()
	if sim.has_prisoner: _spawn_actor(sim.prisoner, false)

## Comic ink on or off (main.gd: the settings file, or a level or a build that asks for it).
func set_ink(on: bool) -> void:
	if on == comic_ink.enabled: return
	comic_ink.set_enabled(on)
	_spot_on = on
	_plan_clock = 1.0
	Operative.ink_cues(on)
	for part: Node in [nature, structures]:
		if part != null and part.has_method("set_ink"): part.call("set_ink", on)
	# the scenery's added glows (lamp halos, pools of lamplight, flames) are colour on top of the drawing: in ink the
	# lamps are bare paper and their light is the snow's white, so the glows are left out
	if _glows.is_empty() and root_static != null: _glows = _added_glows(root_static)
	for node: GeometryInstance3D in _glows:
		if is_instance_valid(node): node.visible = not on

var _glows: Array[GeometryInstance3D] = []

## In comic ink the game's own marks on the map (routes, rings, markers, the squad's x-ray) are printed in a second
## colour over the black and white: the pale ones (cream, white) in vermilion, the others made vivid, and none of them
## blue (the print pass keeps only warm and green colour, so the scene's cold blue washes print in black).
const SPOT_INK := Color(0.86, 0.27, 0.13)
var _spot_on: bool = false

func _spot(c: Color) -> Color:
	if not _spot_on: return c
	if c.s < 0.22: return Color(SPOT_INK, c.a)
	var h: float = c.h
	# blue and violet move round to red-violet
	if h > 0.5 and h < 0.8: h = 0.9 + (h - 0.5) * 0.15
	return Color.from_hsv(h, maxf(c.s, 0.72), clampf(c.v, 0.62, 0.95), c.a)

static func _added_glows(from: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if not n is GeometryInstance3D or not (n as GeometryInstance3D).visible: continue
		var materials: Array[Material] = [(n as GeometryInstance3D).material_override]
		if materials[0] == null and n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			materials.clear()
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for i: int in range(mesh.get_surface_count()):
				var m: Material = (n as MeshInstance3D).get_surface_override_material(i)
				materials.append(m if m != null else mesh.surface_get_material(i))
		var added: bool = not materials.is_empty()
		for m: Material in materials:
			added = added and m is StandardMaterial3D and (m as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD
		if added: out.append(n)
	return out

func ink_enabled() -> bool:
	return comic_ink != null and comic_ink.enabled

func has_finale() -> bool:
	return finale != null

func finale_running() -> bool:
	return finale != null and finale.running

func _process(dt: float) -> void:
	if not adaptive_quality: return
	_adapt_time += dt
	_adapt_frames += 1
	if _adapt_time < 1.0: return
	var fps: float = _adapt_frames/_adapt_time
	_adapt_time = 0.0
	_adapt_frames = 0
	# Three slow seconds in a row, so load-time and shader-compile hitches don't trigger it.
	_adapt_slow_seconds = _adapt_slow_seconds+1 if fps < ADAPT_TARGET_FPS else 0
	if _adapt_slow_seconds < 3: return
	_adapt_slow_seconds = 0
	var viewport: Viewport = get_viewport()
	if viewport.scaling_3d_scale > ADAPT_MIN_SCALE+0.01:
		viewport.scaling_3d_scale = maxf(ADAPT_MIN_SCALE,viewport.scaling_3d_scale-ADAPT_STEP)
	elif atmosphere.grade_enabled:
		atmosphere.grade_enabled = false
	else:
		adaptive_quality = false

static func ground(point: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(point.x/32.0, y, point.y/32.0)

# ------------------------------------------------------------------------------------------------------------
# Models
# ------------------------------------------------------------------------------------------------------------
func _spawn_actor(actor: Dictionary, enemy: bool) -> void:
	var model := Operative.new()
	model.name = str(actor.id)
	add_child(model)
	var look: String = str(actor.id)
	if Callable(model, "build").get_argument_count() >= 4:
		# The character builder knows the guard kinds (patrol, tower, sentry, sergeant, reinforcement) and the
		# mission's own looks (data guards[].look: the navy, the Organisation Todt).
		model.callv("build", [look, enemy, str(actor.get("kind", "")), str(actor.get("look", ""))])
	elif Callable(model, "build").get_argument_count() >= 3:
		model.callv("build", [look, enemy, str(actor.get("kind", ""))])
	else:
		# Older builder: only the looks "g1".."g5" exist; the new kinds borrow one.
		if enemy and not look.trim_prefix("g").is_valid_int():
			look = "g%d" % (5 if actor.get("kind", "") == "sergeant" else 1+absi(hash(look))%4)
		model.callv("build", [look, enemy])
	model.sync(actor, false, 0.1, false)
	# (on the Plaza de Mayo the figures throw no shadow from the sky's light, only the soft one at their feet: the
	# square's thirty people's shadows were nearly half the frame's draw calls, too many for a phone)
	if str(sim.data.get("theme", "")) == "plaza" and model.get("body") is GeometryInstance3D:
		(model.get("body") as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# and an art-pack model in his place (Juan Salvo, a cascarudo) likewise
		if model.get("cutout") is Node3D and model.cutout.has_method("set_shadows"): model.cutout.set_shadows(false)
	actors[actor.id] = model

## Keeps exactly one character model and one sight cone per simulation guard, matched by id: reinforcements
## appear during an alarm, and a checkpoint restore can take them away again or bring others back.
func _sync_guards() -> void:
	var same: bool = sim.guards.size() == cone_nodes.size()
	if same:
		for guard: Dictionary in sim.guards:
			if not cone_nodes.has(guard.id):
				same = false
				break
	if same: return
	var present: Dictionary = {}
	for guard: Dictionary in sim.guards:
		present[guard.id] = true
		if cone_nodes.has(guard.id): continue
		_spawn_actor(guard, true)
		_spawn_cone(str(guard.id))
	for id: String in cone_nodes.keys():
		if present.has(id): continue
		cone_nodes[id].queue_free()
		cone_nodes.erase(id)
		_cones.erase(id)
		actors[id].queue_free()
		actors.erase(id)
		_arrivals.erase(id)

func update_visuals(dt: float) -> void:
	if not sim.paused:
		visual_clock += dt
	_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if float(sim.time) < _last_time-0.0001: _reset_transients()      # the clock went back: restart or restore
	elif finale != null and finale.clock > 0.0 and sim.phase != "won": _reset_transients()   # left the win behind
	_last_time = float(sim.time)
	_sync_guards()
	for event: Dictionary in sim.events:
		_on_event(event)
		sim_event.emit(event)
	sim.events.clear()
	atmosphere.update(dt, sim.paused)
	comic_ink.update()
	nature.update(dt, sim.paused)
	structures.update(dt, sim.paused)
	if audio != null: audio.update(dt, sim.paused)
	# the ground under a man is level everywhere but on a rope down the gorge (snow.gd), where it follows the wall
	var terrain: bool = structures.has_method("ground_height")
	for unit: Dictionary in sim.units:
		var model: Node3D = actors[unit.id]
		model.sync(unit, unit.id == sim.selected_id and draw_vision, dt, sim.paused)
		# an operative the snow has covered (a rescue): only the mound shows; back if a checkpoint takes it away
		if bool(unit.get("buried", false)) != model.has_meta("buried"):
			if bool(unit.get("buried", false)): model.set_meta("buried", true)
			else: model.remove_meta("buried")
			model.visible = not bool(unit.get("buried", false))
		if terrain: model.position.y = structures.ground_height(float(unit.x)/32.0, float(unit.y)/32.0)
	for guard: Dictionary in sim.guards:
		var model: Node3D = actors[guard.id]
		model.sync(guard, false, dt, sim.paused)
		# one of a rescue's people the snow has covered: only the mound shows (plaza.gd)
		if bool(guard.get("person", false)): model.visible = str(guard.state) != "lost"
		# The tower sentry stands on his platform; a carried body rides on its bearer's shoulders.
		model.position.y = float(guard.elevation)+(1.0 if str(guard.carried_by) != "" else 0.0)
		if terrain: model.position.y += structures.ground_height(float(guard.x)/32.0, float(guard.y)/32.0)
	if sim.has_prisoner:
		actors[sim.prisoner.id].sync(sim.prisoner, false, dt, sim.paused)
		# the passenger in Biguá's boat sits on the water with him (boca.gd)
		if terrain: (actors[sim.prisoner.id] as Node3D).position.y = structures.ground_height(float(sim.prisoner.x)/32.0, float(sim.prisoner.y)/32.0)
	_sync_xray()
	_step_arrivals(dt)
	if gate != null: gate.rotation.y = lerp_angle(gate.rotation.y, -PI/2 if sim.door_open else 0.0, minf(1.0, dt*6.0))
	var catch_up: bool = dt >= 0.09
	_update_cones(catch_up)
	# the plan layer follows at ten refreshes a second, and at once when the player changes what it shows
	_plan_clock += dt
	if _plan_clock >= 0.1 or sim.selected_id != _plan_selected or armed_action != _plan_armed_action or aiming != _plan_aiming or sim.paused != _plan_paused:
		_plan_clock = 0.0
		_plan_selected = sim.selected_id
		_plan_armed_action = armed_action
		_plan_aiming = aiming
		_plan_paused = sim.paused
		_update_plan()
	_update_fast(dt)

## Men turning out of the barracks: for the first moments a reinforcement is drawn stepping out of the doorway
## to the spot where the rules put him.
func _step_arrivals(dt: float) -> void:
	if _arrivals.is_empty(): return
	var door: Vector3 = structures.door_point
	for id: String in _arrivals.keys():
		var guard: Dictionary = sim.guard_by_id(id)
		var t: float = float(_arrivals[id])+(0.0 if sim.paused else dt)
		if guard.is_empty() or t >= 0.5 or not actors.has(id):
			_arrivals.erase(id)
			continue
		_arrivals[id] = t
		var model: Node3D = actors[id]
		var f: float = smoothstep(0.0, 1.0, t/0.5)
		model.position.x = lerpf(door.x, model.position.x, f)
		model.position.z = lerpf(door.z, model.position.z, f)

func _reset_transients() -> void:
	if finale != null and (finale.running or finale.clock > 0.0):
		finale.reset()
		finale.clock = 0.0
	_effects.clear()
	_arrivals.clear()
	for id: String in _cones: (_cones[id] as ConeState).traced = false
	_plan_clock = 1.0

# ------------------------------------------------------------------------------------------------------------
# Sight cones
# ------------------------------------------------------------------------------------------------------------
## One fan mesh shared by every cone: vertex UV = (ray index, 0 at the guard / 1 at the end of the ray). The
## shader places the vertices from the cone's `lengths`, so nothing is rebuilt when a guard moves.
func _build_cone_mesh() -> void:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var uvs := PackedVector2Array([Vector2(CONE_RAYS*0.5, 0.0)])
	var indices := PackedInt32Array()
	for ray: int in range(CONE_RAYS+1):
		vertices.append(Vector3(1.0, 0.0, float(ray)/CONE_RAYS-0.5))
		uvs.append(Vector2(ray, 1.0))
		if ray < CONE_RAYS: indices.append_array(PackedInt32Array([0, ray+1, ray+2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_cone_mesh = ArrayMesh.new()
	_cone_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The real extent comes from the shader: allow for the longest cone (the tower on edge, 14.4 m).
	_cone_mesh.custom_aabb = AABB(Vector3(-15.0, -0.2, -15.0), Vector3(30.0, 0.4, 30.0))
	# The cone shader knows up to four stretches of water (world X/Z), where no cone is drawn.
	var waters: Array[Rect2] = []
	for obstacle: Dictionary in sim.data.get("obstacles", []):
		if str(obstacle.get("kind", "")) == "water":
			var r: Rect2 = sim.rect_of(obstacle)
			waters.append(Rect2(r.position/32.0, r.size/32.0))
	for i: int in range(4):
		var rect := Rect2(-1000.0, -1000.0, 0.0, 0.0)
		if i < waters.size(): rect = waters[i]
		_water_uniform.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
	# The cone shader knows up to eight bush rectangles (world X/Z): a croucher inside is hidden beyond 72 units.
	for i: int in range(8):
		var rect := Rect2(-1000.0, -1000.0, 0.0, 0.0)
		if i < _bush_rects.size(): rect = _bush_rects[i]
		_bush_uniform.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))

func _spawn_cone(id: String) -> void:
	var state := ConeState.new()
	state.lengths.resize(CONE_RAYS+1)
	var cone := MeshInstance3D.new()
	cone.name = "Cone_"+id
	for far: bool in [false, true]:
		var material := ShaderMaterial.new()
		material.shader = ConeShader
		# near zones are drawn before far zones, both before the plan ink and the markers
		material.render_priority = 2 if far else 1
		material.set_shader_parameter("zone", 1 if far else 0)
		material.set_shader_parameter("bushes", _bush_uniform)
		material.set_shader_parameter("water", _water_uniform)
		material.set_shader_parameter("reveal_m", float(sim.BUSH_REVEAL)/32.0)
		var node: MeshInstance3D = MeshInstance3D.new() if far else cone
		node.mesh = _cone_mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if far:
			state.far_material = material
			state.far_node = node
			node.name = "Far"
			cone.add_child(node)
		else:
			state.material = material
	cone.visible = false
	add_child(cone)
	cone_nodes[id] = cone
	_cones[id] = state

## What the camera shows of the ground: Vector3(x, z, radius in metres).
func _focus() -> Vector3:
	if _camera == null: return Vector3(20.0, 12.5, 1000.0)
	var forward: Vector3 = -_camera.global_transform.basis.z
	if forward.y > -0.05: return Vector3(20.0, 12.5, 1000.0)
	var hit: Vector3 = _camera.global_position+forward*(_camera.global_position.y/-forward.y)
	var view: Vector2 = get_viewport().get_visible_rect().size
	var half_h: float = _camera.size*0.5/-forward.y
	var half_w: float = _camera.size*0.5*view.x/maxf(view.y, 1.0)
	return Vector3(hit.x, hit.z, sqrt(half_h*half_h+half_w*half_w))

## Where the sight rays of a guard's cone stop, in metres from him, left to right across his field of view
## (as last traced; empty for an unknown id).
func cone_lengths(id: String) -> PackedFloat32Array:
	return (_cones[id] as ConeState).lengths if _cones.has(id) else PackedFloat32Array()

## 0 calm (patrol, post, walking back), 1 wary (looking into a noise, jumpy), 2 alarm (hunting, on alert).
static func cone_look(guard: Dictionary) -> int:
	if guard.state in ["hunt", "alert"] or bool(guard.spotted): return 2
	if guard.state in ["investigate", "search"] or float(guard.jumpy) > 0.0: return 1
	return 0

## Every frame: cones follow their guards (position, facing, colours, the suspicion wave). The sight rays behind
## a cone's outline are re-traced only when the guard has moved or turned, a few cones per frame, in turn, and
## not at all for guards outside the view.
func _update_cones(everything: bool) -> void:
	var focus: Vector3 = _focus()
	var budget: int = 999 if everything else CONE_BUDGET
	var rays_left: int = 99999 if everything else CONE_RAY_BUDGET
	var count: int = sim.guards.size()
	if _blockers_door != int(sim.door_open): _refresh_blockers()
	var next_cursor: int = -1
	_cone_order.clear()
	_cone_depth.clear()
	var forward: Vector3 = -_camera.global_transform.basis.z if _camera != null else Vector3(0, -1, 0)
	for turn: int in range(count):
		var index: int = (turn+_cone_cursor)%count
		var guard: Dictionary = sim.guards[index]
		var node: MeshInstance3D = cone_nodes[guard.id]
		var shown: bool = draw_vision and not guard.state in sim.DOWN_STATES
		node.visible = shown
		if not shown: continue
		var state: ConeState = _cones[guard.id]
		var at: Vector2 = sim.position_of(guard)
		var angle: float = float(guard.angle)
		node.position = Vector3(at.x/32.0, CONE_NEAR_Y, at.y/32.0)
		node.rotation.y = -angle
		# insertion sort by distance down the view axis, farthest first (the order the renderer draws them in)
		var depth: float = node.position.dot(forward)
		var slot: int = _cone_order.size()
		_cone_order.append(index)
		_cone_depth.append(depth)
		while slot > 0 and _cone_depth[slot-1] < depth:
			_cone_order[slot] = _cone_order[slot-1]
			_cone_depth[slot] = _cone_depth[slot-1]
			slot -= 1
		_cone_order[slot] = index
		_cone_depth[slot] = depth
		var away: float = Vector2(at.x/32.0-focus.x, at.y/32.0-focus.y).length()
		_style_cone(guard, state, away, focus.z)
		var reach: float = float(guard.range)
		var fov: float = float(guard.fov)
		var stale: bool = not state.traced or state.door != bool(sim.door_open) or reach != state.reach or fov != state.fov \
			or at.distance_squared_to(state.at) > 4.0 or absf(angle_difference(angle, state.angle)) > 0.012
		var coarse: bool = away > focus.z*0.7 and fov <= float(guard.base_fov)
		if not stale and state.coarse and not coarse: stale = true
		if not stale: continue
		var in_view: bool = away < focus.z+reach/32.0
		if not everything and state.traced and not in_view: continue
		if budget <= 0 or rays_left <= 0:
			if next_cursor < 0: next_cursor = index
			continue
		budget -= 1
		rays_left -= _trace_cone(guard, state, at, angle, reach, fov, coarse)
	if next_cursor >= 0: _cone_cursor = next_cursor
	# Layers: the cone drawn first lies on top and hides what is under it, so overlapping cones never add up.
	for rank: int in range(_cone_order.size()):
		var guard: Dictionary = sim.guards[_cone_order[rank]]
		var layer: float = float(CONE_LAYERS-1-rank%CONE_LAYERS)
		var node: MeshInstance3D = cone_nodes[guard.id]
		node.position.y = CONE_NEAR_Y+0.0005*layer
		(_cones[guard.id] as ConeState).far_node.position.y = CONE_FAR_Y+0.00045*layer-node.position.y

## Everyone hidden behind something solid shows through it: guards in their cone colour (amber, red as they wake
## up to trouble), the squad in their own colours. Nothing while the cones are off (the launch screen, the
## closing scene) or for a man who is down.
func _sync_xray() -> void:
	# every figure marks where he is what the camera sees, even one who never shows through (a man who is down)
	for model: Node in actors.values(): model.call("use_xray", draw_vision)
	for unit: Dictionary in sim.units:
		var c := _spot(Color(str(unit.get("color", "#ffffff"))))
		(actors[unit.id] as Node).call("set_xray", Color(c.r, c.g, c.b, XRAY_ALPHA if draw_vision and bool(unit.alive) else 0.0))
	for guard: Dictionary in sim.guards:
		var up: bool = draw_vision and not guard.state in sim.DOWN_STATES and str(guard.carried_by) == ""
		var tint: Color = [C_CALM, C_WARY, C_ALARM][cone_look(guard)]
		(actors[guard.id] as Node).call("set_xray", Color(tint.r, tint.g, tint.b, XRAY_ALPHA if up else 0.0))
	if sim.has_prisoner:
		var free: bool = draw_vision and bool(sim.prisoner.get("freed", false)) and bool(sim.prisoner.alive) and not bool(sim.prisoner.aboard)
		(actors[sim.prisoner.id] as Node).call("set_xray", Color(1.0, 1.0, 1.0, XRAY_ALPHA if free else 0.0))

func _style_cone(guard: Dictionary, state: ConeState, away: float, view_radius: float) -> void:
	var look: int = cone_look(guard)
	var suspicion: float = clampf(float(guard.suspicion), 0.0, 1.0)
	if look != state.look or (look == 0 and suspicion != state.suspicion):
		if look != state.look: state.put("strength", 0.86 if look == 2 else 1.0)     # many wide red cones: go easier
		state.look = look
		# calm cones warm toward amber as the meter fills; the wave itself is one step hotter than the cone
		var tint: Color = [C_CALM.lerp(C_WARY, suspicion*0.55), C_WARY, C_ALARM][look]
		var warn: Color = [C_WARY, C_ALARM, C_HOT][look]
		state.put("tint", Vector3(tint.r, tint.g, tint.b))
		state.put("warn", Vector3(warn.r, warn.g, warn.b))
	if suspicion != state.suspicion:
		state.suspicion = suspicion
		state.put("suspicion", suspicion)
	var near: float = float(guard.near)/32.0
	if near != state.near:
		state.near = near
		state.put("near_m", near)
	# far zones of guards well away from the middle of the view are drawn lighter: less soup at the overview
	var far_strength: float = snappedf(lerpf(1.0, 0.62, smoothstep(0.45, 1.05, away/maxf(view_radius, 1.0))), 0.02)
	if look > 0: far_strength = 1.0
	if far_strength != state.far_strength:
		state.far_strength = far_strength
		state.put("far_strength", far_strength)
	var pulse: float = snappedf(0.5+0.5*sin(visual_clock*7.0), 0.05) if look == 2 else 0.0
	if pulse != state.pulse:
		state.pulse = pulse
		state.put("pulse", pulse)
	# the far bands flow outward on wary and alarmed cones (0.52 m is one band period)
	var drift: float = fposmod(visual_clock*(0.0 if look == 0 else (0.35 if look == 1 else 0.9)), 0.52)
	if drift != state.drift:
		state.drift = drift
		state.put("drift", drift)

func _refresh_blockers() -> void:
	_blockers_door = int(sim.door_open)
	_blockers.clear()
	_blockers_tall.clear()
	for obstacle: Dictionary in sim.get_obstacles():
		var kind: String = str(obstacle.get("kind", "wall"))
		if kind == "water" or bool(obstacle.get("see_through", false)): continue
		_blockers.append(sim.rect_of(obstacle))
		if kind == "building": _blockers_tall.append(sim.rect_of(obstacle))

## Re-traces one cone and returns the number of sight rays cast. Rays that point at nothing solid within reach
## simply run their full length; the others are asked of the simulation (sight_endpoint_for).
func _trace_cone(guard: Dictionary, state: ConeState, at: Vector2, angle: float, reach: float, fov: float, coarse: bool) -> int:
	var spread: float = deg_to_rad(fov)
	var stride: int = 2 if coarse else 1
	# bearings (relative to his facing) between which something could stop a ray
	_spans.clear()
	for rect: Rect2 in (_blockers_tall if float(guard.elevation) > 0.0 else _blockers):
		var dx: float = maxf(maxf(rect.position.x-at.x, at.x-rect.end.x), 0.0)
		var dy: float = maxf(maxf(rect.position.y-at.y, at.y-rect.end.y), 0.0)
		if dx*dx+dy*dy > reach*reach: continue
		var b0: float = angle_difference(angle, atan2(rect.position.y-at.y, rect.position.x-at.x))
		var b1: float = angle_difference(angle, atan2(rect.position.y-at.y, rect.end.x-at.x))
		var b2: float = angle_difference(angle, atan2(rect.end.y-at.y, rect.end.x-at.x))
		var b3: float = angle_difference(angle, atan2(rect.end.y-at.y, rect.position.x-at.x))
		var low: float = minf(minf(b0, b1), minf(b2, b3))
		var high: float = maxf(maxf(b0, b1), maxf(b2, b3))
		if high-low > PI or (dx == 0.0 and dy == 0.0):
			low = -PI
			high = PI
		_spans.append(low-0.03)
		_spans.append(high+0.03)
	var full: float = reach/32.0
	var cast: int = 0
	for ray: int in range(0, CONE_RAYS+1, stride):
		var bearing: float = spread*(float(ray)/CONE_RAYS-0.5)
		var blocked: bool = false
		for i: int in range(0, _spans.size(), 2):
			if bearing >= _spans[i] and bearing <= _spans[i+1]:
				blocked = true
				break
		if not blocked:
			state.lengths[ray] = full
			continue
		cast += 1
		var end: Vector2 = sim.sight_endpoint_for(guard, at+Vector2.from_angle(angle+bearing)*reach)
		state.lengths[ray] = at.distance_to(end)/32.0
	if coarse:
		for ray: int in range(1, CONE_RAYS, 2):
			state.lengths[ray] = (state.lengths[ray-1]+state.lengths[ray+1])*0.5
	state.put("lengths", state.lengths)
	if reach != state.reach:
		state.put("range_m", full)
	if fov != state.fov:
		state.put("fov", spread)
	state.traced = true
	state.coarse = coarse
	state.at = at
	state.angle = angle
	state.reach = reach
	state.fov = fov
	state.door = bool(sim.door_open)
	return cast

# ------------------------------------------------------------------------------------------------------------
# Overlay nodes: ink mesh, marker pools, beams
# ------------------------------------------------------------------------------------------------------------
func _build_overlays() -> void:
	for patch: Dictionary in sim.data.get("bushes", []):
		var rect: Rect2 = sim.rect_of(patch)
		_bush_rects.append(Rect2(rect.position/32.0, rect.size/32.0))
	for barrier: Dictionary in sim.data.get("barriers", []):
		if bool(barrier.get("cuttable", false)): _span_rect = sim.rect_of(barrier)
	_build_cone_mesh()
	var ink_material := StandardMaterial3D.new()
	ink_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink_material.vertex_color_use_as_albedo = true
	ink_material.render_priority = 3
	overlays = MeshInstance3D.new()
	overlays.name = "Ink"
	overlays.material_override = ink_material
	_ink = ImmediateMesh.new()
	overlays.mesh = _ink
	overlays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(overlays)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_fill_pool(_slow_marks, 28, plane, MarkShader, "Mark", 4)
	_fill_pool(_fast_marks, 36, plane, MarkShader, "LiveMark", 4)
	# beam quad: X runs 0..1 from source to target, Z across
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, -0.5), Vector3(1, 0, -0.5), Vector3(1, 0, 0.5), Vector3(0, 0, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var strip := ArrayMesh.new()
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fill_pool(_beams, 20, strip, BeamShader, "Beam", 5)

func _fill_pool(pool: Pool, count: int, shape: Mesh, shader: Shader, label: String, priority: int) -> void:
	for i: int in range(count):
		var material := ShaderMaterial.new()
		material.shader = shader
		material.render_priority = priority
		var node := MeshInstance3D.new()
		node.name = "%s%d" % [label, i]
		node.mesh = shape
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		pool.nodes.append(node)

## One marker from a pool. half: half-size of its quad in metres; p: the shape's parameters (see world_mark.gdshader).
func _mark(pool: Pool, shape: int, at: Vector3, half: float, color: Color, p: Vector4, line: float = 0.05, spin: float = 0.0) -> void:
	color = _spot(color)
	if pool.used >= pool.nodes.size() or color.a <= 0.01: return
	var node: MeshInstance3D = pool.nodes[pool.used]
	pool.used += 1
	node.position = at
	node.scale = Vector3(half, 1.0, half)
	node.visible = true
	var material: ShaderMaterial = node.material_override
	material.set_shader_parameter("shape", shape)
	material.set_shader_parameter("p", p)
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("size_m", half)
	material.set_shader_parameter("line_m", line)
	material.set_shader_parameter("spin", spin)

## One ribbon between two points. Flat on the ground by default; `facing` turns it toward the camera (tracers).
func _beam(a: Vector3, b: Vector3, width: float, color: Color, rest: Color, fill: float, dash: float, head: float = -1.0, tail: float = 0.35, facing: bool = false) -> void:
	color = _spot(color)
	rest = _spot(rest)
	var along: Vector3 = b-a
	var length: float = along.length()
	if _beams.used >= _beams.nodes.size() or length < 0.02: return
	var side: Vector3 = Vector3.UP.cross(along)
	if facing and _camera != null: side = along.cross(_camera.global_transform.basis.z)
	if side.length_squared() < 0.000001: side = Vector3.RIGHT
	side = side.normalized()
	var node: MeshInstance3D = _beams.nodes[_beams.used]
	_beams.used += 1
	node.transform = Transform3D(Basis(along, side.cross(along).normalized(), side*width), a)
	node.visible = true
	var material: ShaderMaterial = node.material_override
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("rest", rest)
	material.set_shader_parameter("length_m", length)
	material.set_shader_parameter("fill", fill)
	material.set_shader_parameter("dash_m", dash)
	material.set_shader_parameter("head", head)
	material.set_shader_parameter("tail", tail)

# ------------------------------------------------------------------------------------------------------------
# Ink primitives (all flat on the ground, in the mesh being drawn)
# ------------------------------------------------------------------------------------------------------------
func _pen(color: Color, alpha: float = 1.0) -> void:
	color = _spot(color)
	_ink.surface_set_color(Color(color.r, color.g, color.b, color.a*alpha))

## Flat ribbon between two ground points; lines would be hair-thin on a phone.
func _ribbon(a: Vector3, b: Vector3, width: float) -> void:
	var along: Vector3 = b-a
	if along.length_squared() < 0.000001: return
	var side: Vector3 = Vector3(-along.z, 0, along.x).normalized()*width*0.5
	for v: Vector3 in [a-side, a+side, b+side, a-side, b+side, b-side]: _ink.surface_add_vertex(v)

func _arc(center: Vector3, radius: float, from: float, to: float, width: float) -> void:
	var pieces: int = maxi(1, int(ceil(absf(to-from)*radius/0.24)))
	var previous: Vector3 = center+Vector3(cos(from), 0, sin(from))*radius
	for i: int in range(1, pieces+1):
		var a: float = lerpf(from, to, float(i)/pieces)
		var next: Vector3 = center+Vector3(cos(a), 0, sin(a))*radius
		_ribbon(previous, next, width)
		previous = next

## Circle; with `dashes` > 0 it is broken into that many dashes, each `duty` of its cell long.
func _ring(center: Vector3, radius: float, width: float, dashes: int = 0, duty: float = 0.6, turn: float = 0.0) -> void:
	if dashes <= 0:
		_arc(center, radius, 0.0, TAU, width)
		return
	for i: int in range(dashes):
		var from: float = turn+TAU*float(i)/dashes
		_arc(center, radius, from, from+TAU*duty/dashes, width)

## Dashes along a polyline; `carried` continues the pattern from the previous piece. Returns the new carry.
func _dashes(a: Vector3, b: Vector3, width: float, dash: float, gap: float, carried: float = 0.0) -> float:
	var length: float = a.distance_to(b)
	if length < 0.0001: return carried
	var cursor: float = -carried
	while cursor < length:
		var from: float = maxf(cursor, 0.0)
		var to: float = minf(cursor+dash, length)
		if to > from: _ribbon(a.lerp(b, from/length), a.lerp(b, to/length), width)
		cursor += dash+gap
	return fposmod(length+carried, dash+gap)

## Four corner brackets of a rectangle (half extents in metres).
func _bracket(center: Vector3, half: Vector2, arm: float, width: float) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner: Vector3 = center+Vector3(sx*half.x, 0, sz*half.y)
			_ribbon(corner+Vector3(sx*width*0.5, 0, 0), corner-Vector3(sx*arm, 0, 0), width)
			_ribbon(corner+Vector3(0, 0, sz*width*0.5), corner-Vector3(0, 0, sz*arm), width)

## Dashed outline of a rectangle with rounded corners (bush patches). rect in metres.
func _soft_rect(rect: Rect2, corner: float, width: float, dash: float, gap: float) -> void:
	var points: Array[Vector3] = []
	var centers: Array[Vector2] = [rect.position+Vector2(corner, corner), Vector2(rect.end.x-corner, rect.position.y+corner),
		rect.end-Vector2(corner, corner), Vector2(rect.position.x+corner, rect.end.y-corner)]
	for i: int in range(4):
		for piece: int in range(5):
			var a: float = PI+PI*0.5*i+PI*0.5*float(piece)/4.0
			points.append(Vector3(centers[i].x+cos(a)*corner, INK_Y, centers[i].y+sin(a)*corner))
	var carried: float = 0.0
	for i: int in range(points.size()):
		carried = _dashes(points[i], points[(i+1)%points.size()], width, dash, gap, carried)

# ------------------------------------------------------------------------------------------------------------
# The plan layer: everything that is decided about ten times a second
# ------------------------------------------------------------------------------------------------------------
func _update_plan() -> void:
	_ink.clear_surfaces()
	_ink.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ink.surface_set_normal(Vector3.UP)
	_slow_marks.rewind()
	_attached.clear()
	valid_targets.clear()
	plan_previews.clear()
	var playing: bool = sim.phase == "playing"
	var unit: Dictionary = sim.selected()
	var here: Vector2 = sim.position_of(unit)
	var carrying: bool = str(unit.carrying) != ""
	var escorting: bool = bool(sim.prisoner.freed) and not bool(sim.prisoner.aboard)
	# extraction ring: always findable, bright once the informant is out (or, with nobody to rescue, once the
	# work is done)
	# (a rescue has no way out to draw: the shelters are drawn instead, _plan_rescue)
	if sim.data.has("extraction"):
		var e: Dictionary = sim.data.extraction
		var boat := Vector2(float(e.x), float(e.y))
		_pen(INK, 0.85 if escorting or (not sim.has_prisoner and sim.ready_to_leave()) else 0.42)
		_ring(ground(boat, INK_Y), float(e.radius)/32.0, 0.055, 16, 0.72)
	# a local's own way out (data units[].exit): its ring, brightest for him once the work is done
	for u: Dictionary in sim.units:
		var exit: Dictionary = u.get("exit", {})
		if exit.is_empty(): continue
		var mine: bool = u.id == sim.selected_id
		_pen(INK, (0.85 if sim.ready_to_leave() else 0.5) if mine else 0.26)
		_ring(ground(Vector2(float(exit.x), float(exit.y)), INK_Y), float(exit.get("radius", 48.0))/32.0, 0.05, 14, 0.6)
	if playing and unit.has("cover"):
		# where his cover does not hold: the wire and the transformer yard, outlined in red
		_pen(DANGER, 0.5 if sim.paused else 0.28)
		for zone: Rect2 in sim.restricted_zones(unit):
			_soft_rect(Rect2(zone.position/32.0, zone.size/32.0).grow(-0.1), 0.4, 0.06, 0.5, 0.3)
	if bool(sim.get("rescue_on")): _plan_rescue(unit)
	if playing:
		var drop_bush: int = _plan_orders()
		_plan_bushes(unit, here, carrying, escorting, drop_bush)
		_plan_interactables(here)
		_plan_armed(unit, here)
		_plan_traps()
	_ink.surface_end()
	_slow_marks.hide_rest()

## A rescue (data "snowfall"): where the snow cannot reach, outlined on the ground: the shelters people will go into
## in ink, brighter while the selected operative leads people or carries someone; a dark one (its lights out) dashed
## in red; the cloths still to be taken, a faint ring each; whoever is down in the snow, a red ring.
func _plan_rescue(unit: Dictionary) -> void:
	var leading: bool = not unit.is_empty() and (not sim.followers_of(str(unit.id)).is_empty() or str(unit.get("carrying", "")) != "")
	for shelter: Dictionary in sim.shelters():
		var r: Rect2 = sim.shelter_rect(shelter)
		if r.size.x <= 0.0: continue
		var rect := Rect2(r.position/32.0, r.size/32.0)
		if sim.shelter_open(shelter):
			_pen(INK, 0.9 if leading else (0.62 if sim.paused else 0.45))
			_soft_rect(rect.grow(0.25), 0.5, 0.07 if leading else 0.055, 0.5, 0.22)
		else:
			_pen(DANGER, 0.6 if sim.paused else 0.42)
			_soft_rect(rect.grow(0.25), 0.5, 0.05, 0.22, 0.3)
	for canvas: Dictionary in sim.canvases():
		if sim.canvases_taken.has(str(canvas.id)): continue
		_pen(INK, 0.4 if sim.paused else 0.24)
		_ring(ground(Vector2(float(canvas.x), float(canvas.y)), INK_Y), 0.7, 0.04, 8, 0.6)
	for person: Dictionary in sim.people():
		if str(person.state) != "fallen" or str(person.get("carried_by", "")) != "": continue
		_pen(DANGER, 0.85)
		_ring(ground(sim.position_of(person), INK_Y), 0.95, 0.06, 10, 0.7, visual_clock*0.6)
	for u: Dictionary in sim.units:
		if not bool(u.get("fallen", false)): continue
		_pen(DANGER, 0.95)
		_ring(ground(sim.position_of(u), INK_Y), 1.05, 0.07, 10, 0.7, visual_clock*0.6)

## Bush patches hide crouched operatives, bodies and the informant: their outline is shown when that matters, and
## turns red while a guard is looking into the patch from close enough to see a croucher there.
func _plan_bushes(unit: Dictionary, here: Vector2, carrying: bool, escorting: bool, drop_bush: int) -> void:
	for i: int in range(_bush_rects.size()):
		var rect: Rect2 = _bush_rects[i]
		var nearest := Vector2(clampf(here.x/32.0, rect.position.x, rect.end.x), clampf(here.y/32.0, rect.position.y, rect.end.y))
		var away: float = nearest.distance_to(here/32.0)
		var strength: float = 0.0
		if sim.paused: strength = 0.34
		if unit.stance == "sneak": strength = maxf(strength, 0.75*(1.0-smoothstep(2.0, 5.0, away)))
		if escorting: strength = maxf(strength, 0.6)
		if carrying: strength = maxf(strength, 0.85)
		if bool(unit.hidden) and away < 0.01: strength = maxf(strength, 0.9)
		if i == drop_bush: strength = 1.0
		if strength <= 0.02: continue
		var inside: bool = away < 0.01
		var probe: Vector2 = here if inside else rect.get_center()*32.0
		var seen: bool = not sim.threats_at(probe, false).is_empty()
		_pen(DANGER if seen else INK, strength)
		_soft_rect(rect.grow(0.2), 0.55, 0.06 if strength > 0.5 else 0.05, 0.3, 0.2)

## Routes and order markers of both operatives. Returns the index of a bush an order will hide a body in (-1).
func _plan_orders() -> int:
	var drop_bush: int = -1
	for unit: Dictionary in sim.units:
		if not bool(unit.alive): continue
		var chosen: bool = unit.id == sim.selected_id
		var strength: float = (1.0 if chosen else 0.6)*(1.0 if sim.paused else 0.62)
		var tone: Color = Color.html(str(unit.color)).lerp(Color.WHITE, 0.2)
		var here: Vector2 = sim.position_of(unit)
		var order: Dictionary = unit.order
		var type: String = str(order.get("type", ""))
		var path: Array = unit.path
		# planned route as dashes
		_pen(tone, strength*0.92)
		var previous: Vector3 = ground(here, INK_Y)
		var carried: float = 0.0
		for point: Vector2 in path:
			var next: Vector3 = ground(point, INK_Y)
			carried = _dashes(previous, next, 0.085 if chosen else 0.06, PATH_DASH, PATH_GAP, carried)
			previous = next
		var end: Vector2 = here if path.is_empty() else (path.back() as Vector2)
		if type == "" and path.is_empty(): continue
		plan_previews[str(unit.id)] = type
		var spot: Vector2 = Vector2(float(order.get("x", end.x)), float(order.get("y", end.y)))
		var target: String = str(order.get("target", ""))
		match type:
			"", "move", "extract":
				_destination(unit, end, tone, strength)
			"takedown":
				_attached.append([target, BRACKET, 0.72, Color(tone, strength), Vector4(0.84, 0.36, 0.08, 0.0), 0.09])
			"shoot":
				_attached.append([target, RETICLE, 0.84, Color(tone, strength), Vector4(0.56, 0.4, 0.05, 0.0), 0.09])
				_attached.append([target, -1, 0.0, Color(tone, strength*0.9), Vector4.ZERO, 0.0, str(unit.id)])
			"pickup":
				_attached.append([target, BRACKET, 0.7, Color(tone, strength), Vector4(0.85, 0.32, 0.06, 0.0), 0.08])
			"distract":
				# where the pebble lands, how far it is heard, and the throw
				_mark(_slow_marks, RING, ground(spot, MARK_Y), 0.36, Color(tone, strength), Vector4(0.8, 0.0, 0.25, 0.08), 0.075)
				_pen(tone, strength*0.9)
				_ring(ground(spot, INK_Y), float(sim.DISTRACT_RADIUS)/32.0, 0.09, 30, 0.7)
				_pen(tone, strength*0.8)
				_dashes(ground(here, INK_Y), ground(spot, INK_Y), 0.06, 0.12, 0.14)
			"drop":
				_destination(unit, spot, tone, strength)
				for i: int in range(_bush_rects.size()):
					if _bush_rects[i].has_point(spot/32.0): drop_bush = i
			"trap":
				_pen(tone, strength)
				var across := Vector2.from_angle(float(unit.angle)+PI*0.5)*16.0
				_ribbon(ground(here-across, INK_Y), ground(here+across, INK_Y), 0.06)
				_ring(ground(here, INK_Y), float(sim.TRAP_RADIUS)/32.0, 0.045, 10, 0.6)
			"cut":
				_destination(unit, spot, tone, strength)
				_plan_fence(tone, strength)
			"sabotage":
				_destination(unit, spot, tone, strength)
				_mark(_slow_marks, BRACKET, _generator_spot(), 0.95, Color(tone, strength), Vector4(0.85, 0.28, 0.06, 0.0), 0.06)
			"unlock":
				_destination(unit, spot, tone, strength)
				_mark(_slow_marks, BRACKET, ground(sim.rect_of(sim.data.door).get_center(), MARK_Y), 1.25, Color(tone, strength), Vector4(0.86, 0.26, 0.05, 0.0), 0.06)
			"rescue":
				_attached.append([str(sim.prisoner.id), BRACKET, 0.62, Color(tone, strength), Vector4(0.82, 0.34, 0.05, 0.0), 0.06])
			"trap_pickup":
				_destination(unit, spot, tone, strength)
			"plant":
				_destination(unit, spot, tone, strength)
				var site: Dictionary = sim.charge_site(target)
				if not site.is_empty():
					_mark(_slow_marks, BRACKET, _site_spot(site), 0.7, Color(tone, strength), Vector4(0.85, 0.3, 0.06, 0.0), 0.06)
			_:
				_destination(unit, spot, tone, strength)
	return drop_bush

## Where a charge goes, on the ground in front of the operative's work spot (the hull side, the pier face).
func _site_spot(site: Dictionary) -> Vector3:
	return ground(Vector2(float(site.get("tx", site.x)), float(site.get("ty", site.y))), MARK_Y)

## Destination ring of an order, tinted by what the guards would see of the operative there right now:
## red = inside a near zone, amber = in a far zone while he will be standing.
func _destination(unit: Dictionary, point: Vector2, tone: Color, strength: float) -> void:
	var exposed: bool = unit.stance != "sneak" or str(unit.carrying) != ""
	var level: int = 0
	if not sim.covered_at(unit, point):
		for guard: Dictionary in sim.guards:
			level = maxi(level, int(sim.zone_at(guard, point, exposed)))
	var color: Color = [tone, CAUTION, DANGER][level]
	_mark(_slow_marks, RING, ground(point, MARK_Y), 0.46, Color(color, strength), Vector4(0.72, 6.0, 0.3 if level > 0 else 0.0, 0.07), 0.085, visual_clock*0.6)

func _generator_spot() -> Vector3:
	var at: Vector3 = structures.generator_point
	return Vector3(at.x, MARK_Y, at.z)

## The cuttable span, marked along the foot of the wire.
func _plan_fence(tone: Color, strength: float) -> void:
	var rect: Rect2 = _span_rect
	if rect.size.x <= 0.0: return
	var a: Vector3 = ground(Vector2(rect.position.x, rect.get_center().y), INK_Y)
	var b: Vector3 = ground(Vector2(rect.end.x, rect.get_center().y), INK_Y)
	_pen(tone, strength)
	for z: float in [-0.22, 0.22]:
		_dashes(a+Vector3(0.1, 0, z), b+Vector3(-0.1, 0, z), 0.05, 0.22, 0.14)
	for end: Vector3 in [a, b]:
		_ribbon(end+Vector3(0, 0, -0.36), end+Vector3(0, 0, 0.36), 0.06)

## Small ground markers for what the selected operative can use right now (the HUD carries the labels):
## the same four corner brackets everywhere, stronger when he is near.
func _plan_interactables(here: Vector2) -> void:
	for item: Dictionary in sim.interactables():
		if not bool(item.enabled): continue
		var at := Vector2(float(item.x), float(item.y))
		var close: float = 1.0-smoothstep(96.0, 260.0, at.distance_to(here))
		var strength: float = lerpf(0.42, 0.95, close)*(1.0 if sim.paused else 0.85)
		var color := Color(INK, strength)
		match str(item.type):
			"gate":
				_mark(_slow_marks, BRACKET, ground(at, MARK_Y), 1.25, color, Vector4(0.86, 0.2, 0.0, 0.0), 0.05)
			"fence":
				_plan_fence(INK, strength)
			"radio", "switch":
				_mark(_slow_marks, BRACKET, _generator_spot(), 0.95, color, Vector4(0.85, 0.22, 0.0, 0.0), 0.05)
			"limpet", "charge":
				_mark(_slow_marks, BRACKET, ground(at, MARK_Y), 0.6, color, Vector4(0.85, 0.24, 0.0, 0.0), 0.05)
			"trap":
				_mark(_slow_marks, BRACKET, ground(at, MARK_Y), 0.8, color, Vector4(0.85, 0.22, 0.0, 0.0), 0.05)
			"body":
				_mark(_slow_marks, BRACKET, ground(at, MARK_Y), 0.72, color, Vector4(0.85, 0.24, 0.0, 0.0), 0.05)
			"informant":
				_attached.append([str(sim.prisoner.id), BRACKET, 0.6, color, Vector4(0.82, 0.24, 0.0, 0.0), 0.05])
			"bush":
				# a place to put the body down out of sight
				_mark(_slow_marks, RING, ground(at, 1.2), 0.3, Color(INK, maxf(strength, 0.7)), Vector4(0.8, 0.0, 0.12, 0.07), 0.055)
			"extraction":
				_mark(_slow_marks, RING, ground(at, MARK_Y), 0.3, color, Vector4(0.8, 0.0, 0.0, 0.08), 0.05)

## An armed action waiting for its target: the operative's range ring, and for a gun every guard he could hit
## from where he stands (in range with a clear line), each with a reticle on the ground.
func _plan_armed(unit: Dictionary, here: Vector2) -> void:
	var armed: String = armed_action
	if armed == "" and aiming: armed = "distract"
	if armed == "": return
	var reach: float = 0.0
	for action: Dictionary in sim.available_actions(str(unit.id)):
		if action.id == armed: reach = float(action.range)
	if reach <= 0.0: return
	var tone: Color = Color.html(str(unit.color)).lerp(Color.WHITE, 0.45)
	_pen(tone, 0.92)
	_ring(ground(here, INK_Y), reach/32.0, 0.075, 40, 0.55, visual_clock*0.05)
	if armed != "shoot": return
	for guard: Dictionary in sim.guards:
		if guard.state in ["dead", "bound"] or str(guard.carried_by) != "": continue
		# nobody aims at a civilian (a rescue's people), nor at a creature not in the square
		if bool(guard.get("civilian", false)) or str(guard.state) in ["waiting", "away"]: continue
		if here.distance_to(sim.position_of(guard)) > reach or not sim.sight_clear_for(guard, here): continue
		valid_targets.append(str(guard.id))
		_attached.append([str(guard.id), RETICLE, 0.82, Color(1.0, 0.97, 0.9, 0.97), Vector4(0.54, 0.42, 0.0, 0.0), 0.08])

## Laid tripwires: the wire picked out on the ground and the circle a guard has to step into.
func _plan_traps() -> void:
	for trap: Dictionary in sim.traps:
		var at: Vector3 = ground(Vector2(float(trap.x), float(trap.y)), INK_Y)
		var yaw: float = structures.trap_yaw(str(trap.id))
		var along := Vector3(cos(yaw), 0, -sin(yaw))*0.5
		_pen(INK, 0.6)
		_ribbon(at-along, at+along, 0.05)
		_pen(INK, 0.38)
		_ring(at, float(sim.TRAP_RADIUS)/32.0, 0.04, 10, 0.55)

# ------------------------------------------------------------------------------------------------------------
# Every frame: things that follow actors, detection lines, noise, the alarm, effects
# ------------------------------------------------------------------------------------------------------------
func _actor_spot(id: String) -> Vector3:
	if id == str(sim.prisoner.id): return ground(sim.position_of(sim.prisoner), MARK_Y)
	var unit: Dictionary = sim.unit_by_id(id)
	if not unit.is_empty(): return ground(sim.position_of(unit), MARK_Y)
	var guard: Dictionary = sim.guard_by_id(id)
	if guard.is_empty(): return Vector3.INF
	return ground(sim.position_of(guard), float(guard.elevation)+MARK_Y)

func _update_fast(dt: float) -> void:
	_fast_marks.rewind()
	_beams.rewind()
	if sim.phase == "playing":
		for entry: Array in _attached:
			var at: Vector3 = _actor_spot(str(entry[0]))
			if not at.is_finite(): continue
			if int(entry[1]) >= 0:
				var spin: float = visual_clock*0.5 if int(entry[1]) == RETICLE else 0.0
				_mark(_fast_marks, int(entry[1]), at, float(entry[2]), entry[3], entry[4], float(entry[5]), spin)
			else:
				# line of fire of a queued shot, drawn only while he has the shot from where he stands
				var shooter: Dictionary = sim.unit_by_id(str(entry[6]))
				var guard: Dictionary = sim.guard_by_id(str(entry[0]))
				if shooter.is_empty() or guard.is_empty() or not shooter.has("gun"): continue
				var from: Vector2 = sim.position_of(shooter)
				if from.distance_to(sim.position_of(guard)) > float(shooter.gun.get("range", 240.0)) or not sim.sight_clear_for(guard, from): continue
				_beam(ground(from, MARK_Y), at, 0.06, entry[3], Color(1, 1, 1, 0), 1.0, 0.0)
		_draw_detection()
		_draw_alarm()
	_draw_noise()
	_draw_effects(dt)
	_fast_marks.hide_rest()
	_beams.hide_rest()

## Who sees whom: while a guard's meter is filling on somebody, a line runs from him toward that character and
## fills with his suspicion; once he is aiming, the line is red and fills with his aim.
func _draw_detection() -> void:
	for guard: Dictionary in sim.guards:
		if guard.state in sim.DOWN_STATES: continue
		var from: Vector3 = ground(sim.position_of(guard), MARK_Y+0.01)
		var aim_id: String = str(guard.target_id)
		var seen_id: String = str(guard.seen_id)
		if aim_id != "":
			var to: Vector3 = _actor_spot(aim_id)
			if not to.is_finite(): continue
			var fill: float = clampf(float(guard.aim_time)/maxf(float(guard.aim_total), 0.01), 0.0, 1.0)
			_beam(from, to, 0.17, Color(DANGER, 0.97), Color(1.0, 0.9, 0.86, 0.8), fill, 0.16)
			_mark(_fast_marks, RING, to, 0.74, Color(DANGER, 0.95), Vector4(0.86, 0.0, 0.16+0.2*fill, 0.0), 0.08)
		elif seen_id != "" and float(guard.suspicion) > 0.01:
			var to: Vector3 = _actor_spot(seen_id)
			if not to.is_finite(): continue
			var sure: bool = float(guard.suspicion) >= 1.0
			var color: Color = DANGER if sure or cone_look(guard) == 2 else CAUTION
			_beam(from, to, 0.15, Color(color, 0.97), Color(INK, 0.8), clampf(float(guard.suspicion), 0.0, 1.0), 0.16)
			_mark(_fast_marks, RING, to, 0.74, Color(color, 0.95), Vector4(0.86, 0.0, 0.14, 0.0), 0.075)
		elif float(guard.body_alert) > 0.01:
			# he is looking at a body lying in the open: the same line, filling until he raises the alarm
			for body: Dictionary in sim.guards:
				if not body.state in sim.BODY_STATES or bool(body.hidden) or bool(body.found) or str(body.carried_by) != "": continue
				if int(sim.zone_at(guard, sim.position_of(body), true)) == 0: continue
				var to: Vector3 = ground(sim.position_of(body), MARK_Y)
				_beam(from, to, 0.15, Color(CAUTION, 0.97), Color(INK, 0.8), clampf(float(guard.body_alert), 0.0, 1.0), 0.16)
				_mark(_fast_marks, BRACKET, to, 0.8, Color(CAUTION, 0.95), Vector4(0.86, 0.34, 0.1, 0.0), 0.075)
				break

## While guards hunt: the last known position they are making for.
func _draw_alarm() -> void:
	var alarm: Dictionary = sim.alarm
	if not bool(alarm.active): return
	var at: Vector3 = ground(Vector2(float(alarm.x), float(alarm.y)), MARK_Y+0.005)
	var beat: float = 0.5+0.5*sin(visual_clock*5.0)
	_mark(_fast_marks, RETICLE, at, 1.0, Color(DANGER, 0.78+0.2*beat), Vector4(0.62, 0.3, 0.09, 0.0), 0.075, visual_clock*0.9)
	_mark(_fast_marks, RING, at, 1.25, Color(DANGER, 0.5), Vector4(0.9, 14.0, 0.05, 0.0), 0.05, -visual_clock*0.35)

## Noise rings: wave fronts run out to the real hearing radius, drawn as a dashed circle while they travel.
func _draw_noise() -> void:
	for noise: Dictionary in sim.noise:
		var t: float = 1.0-float(noise.ttl)/maxf(float(noise.max_ttl), 0.01)
		var at: Vector3 = ground(Vector2(float(noise.x), float(noise.y)), MARK_Y)
		match str(noise.get("kind", "pebble")):
			"shot": _mark(_fast_marks, WAVES, at, float(noise.radius)/32.0, Color(0.82, 0.93, 1.0, 0.85), Vector4(t, 1.0, 22.0, 0.0), 0.05)
			"gunshot": _mark(_fast_marks, WAVES, at, float(noise.radius)/32.0, Color(1.0, 0.5, 0.3, 0.9), Vector4(t, 3.0, 0.0, 0.0), 0.11)
			_: _mark(_fast_marks, WAVES, at, float(noise.radius)/32.0, Color(1.0, 0.9, 0.55, 0.9), Vector4(t, 2.0, 40.0, 0.0), 0.06)

func _draw_effects(dt: float) -> void:
	var index: int = 0
	while index < _effects.size():
		var fx: Dictionary = _effects[index]
		var t: float = float(fx.t)+dt
		fx.t = t
		if t >= float(fx.ttl):
			_effects.remove_at(index)
			continue
		index += 1
		var f: float = t/float(fx.ttl)
		var color: Color = fx.color
		match str(fx.kind):
			"tracer":
				# the round crosses in the first third; a thin line of smoke hangs a moment longer
				_beam(fx.a, fx.b, float(fx.width), Color(color, color.a*(1.0-f*f)), Color(1, 1, 1, 0), 1.0, 0.0, f*3.6, 0.55, true)
				_beam(fx.a, fx.b, float(fx.width)*0.45, Color(color.lerp(Color.WHITE, 0.4), 0.3*(1.0-f)), Color(1, 1, 1, 0), minf(1.0, f*3.6), 0.0, -1.0, 0.35, true)
			"puff":
				_mark(_fast_marks, PUFF, fx.at, float(fx.size), color, Vector4(f, 0, 0, 0))
			"pulse":
				_mark(_fast_marks, WAVES, fx.at, float(fx.size), color, Vector4(f, float(fx.fronts), 0.0, 0.0), float(fx.get("line", 0.07)))
			"flash":
				var at: Vector3 = _actor_spot(str(fx.id))
				if at.is_finite():
					var blink: float = 0.5+0.5*cos(t*TAU*3.0)
					_mark(_fast_marks, BRACKET, at, 0.85, Color(color, (0.45+0.55*blink)*(1.0-f*f)), Vector4(0.86, 0.34, 0.12*blink, 0.0), 0.08)

func _fx(kind: String, ttl: float, color: Color, extra: Dictionary) -> void:
	if _effects.size() >= 24: return
	extra["kind"] = kind
	extra["t"] = 0.0
	extra["ttl"] = ttl
	extra["color"] = color
	_effects.append(extra)

func _pulse(point: Vector2, size: float, ttl: float, color: Color, fronts: int = 1, line: float = 0.07) -> void:
	_fx("pulse", ttl, color, {"at": ground(point, MARK_Y+0.01), "size": size, "fronts": fronts, "line": line})

## Height a bullet leaves or reaches somebody at.
func _chest(actor: Dictionary) -> float:
	if actor.is_empty(): return 1.0
	var standing: bool = sim.is_exposed(actor) or actor.has("kind")
	return float(actor.get("elevation", 0.0))+(1.3 if standing else 0.85)

## Scene effects for simulation events (sounds and HUD notices are other modules' business).
func _on_event(event: Dictionary) -> void:
	structures.on_sim_event(event)
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	match str(event.get("type", "")):
		"shot":
			var shooter: Dictionary = sim.unit_by_id(str(event.by))
			var victim: Dictionary = sim.guard_by_id(str(event.get("hit_id", "")))
			var loud: bool = bool(event.get("loud", false))
			var from: Vector3 = ground(at, _chest(shooter))
			var to: Vector3 = ground(Vector2(float(event.tx), float(event.ty)), 0.25 if victim.is_empty() else _chest(victim))
			# the muffled pistol: a thin pale streak; the revolver: a fat warm one and a puff of smoke
			_fx("tracer", 0.22 if loud else 0.16, Color(1.0, 0.74, 0.36, 1.0) if loud else Color(0.8, 0.93, 1.0, 0.9), {"a": from, "b": to, "width": 0.13 if loud else 0.06})
			if loud: _fx("puff", 0.6, Color(0.9, 0.88, 0.82, 0.6), {"at": from+(to-from).normalized()*0.5, "size": 0.55})
			_fx("puff", 0.35, Color(1.0, 0.95, 0.85, 0.9) if not victim.is_empty() else Color(0.74, 0.68, 0.56, 0.8), {"at": to, "size": 0.4})
		"guard_shot":
			var shooter: Dictionary = sim.guard_by_id(str(event.by))
			var hit: bool = bool(event.get("hit", false))
			var victim: Dictionary = sim.unit_by_id(str(event.target))
			if victim.is_empty() and str(event.target) == str(sim.prisoner.id): victim = sim.prisoner
			var from: Vector3 = ground(at, _chest(shooter))
			var aim := Vector2(float(event.tx), float(event.ty))
			var to: Vector3 = ground(aim, _chest(victim))
			if not hit:
				# a miss goes past him and kicks up dirt behind
				var past: Vector2 = aim+(aim-at).normalized()*58.0
				to = ground(past, 0.05)
			_fx("tracer", 0.2, Color(1.0, 0.9, 0.45, 1.0), {"a": from, "b": to, "width": 0.1})
			_fx("puff", 0.4, Color(1.0, 0.5, 0.4, 0.9) if hit else Color(0.74, 0.68, 0.56, 0.85), {"at": to, "size": 0.38 if hit else 0.5})
		"pebble":
			_fx("puff", 0.45, Color(0.82, 0.76, 0.62, 0.8), {"at": ground(at, 0.08), "size": 0.42})
		"trap_set":
			_pulse(at, 0.9, 0.5, Color(INK, 0.8))
		"trap_sprung":
			_pulse(at, 1.5, 0.55, Color(1.0, 1.0, 0.95, 0.95), 2)
			_fx("puff", 0.5, Color(0.8, 0.76, 0.64, 0.8), {"at": ground(at, 0.1), "size": 0.6})
		"fence_cut":
			if _span_rect.size.x > 0.0: _pulse(_span_rect.get_center(), 1.5, 0.6, Color(INK, 0.9))
		"radio_cut":
			_fx("pulse", 0.7, Color(INK, 0.9), {"at": _generator_spot(), "size": 1.5, "fronts": 1})
		"planted":
			var site: Dictionary = sim.charge_site(str(event.get("site", "")))
			if not site.is_empty(): _fx("pulse", 0.7, Color(INK, 0.9), {"at": _site_spot(site), "size": 1.1, "fronts": 1})
		"unlock":
			_pulse(sim.rect_of(sim.data.door).get_center(), 1.5, 0.6, Color(INK, 0.9))
		"spotted":
			var guard: Dictionary = sim.guard_by_id(str(event.guard))
			if not guard.is_empty(): _pulse(sim.position_of(guard), 1.3, 0.5, Color(DANGER, 0.95))
		"heard":
			# who is coming to look
			for id: String in event.get("guards", []):
				var guard: Dictionary = sim.guard_by_id(id)
				if not guard.is_empty(): _pulse(sim.position_of(guard), 1.1, 0.6, Color(CAUTION, 0.9))
		"woke":
			var guard: Dictionary = sim.guard_by_id(str(event.guard))
			if not guard.is_empty(): _pulse(sim.position_of(guard), 1.3, 0.6, Color(CAUTION, 0.95), 2)
		"hurt":
			var victim: Vector3 = _actor_spot(str(event.id))
			if victim.is_finite(): _fx("pulse", 0.5, Color(DANGER, 0.95), {"at": victim, "size": 1.2, "fronts": 2, "line": 0.09})
		"rescued", "escort":
			_pulse(sim.position_of(sim.prisoner), 1.3, 0.6, Color(INK, 0.9))
		"drop":
			if bool(event.get("hidden", false)):
				var body: Dictionary = sim.guard_by_id(str(event.body))
				if not body.is_empty(): _pulse(sim.position_of(body), 1.4, 0.7, Color(INK, 0.85))
		"alarm_start":
			_pulse(at, 4.5, 1.1, Color(DANGER, 0.95), 3, 0.11)
		"body_found":
			_pulse(at, 2.2, 0.8, Color(DANGER, 0.95), 2, 0.09)
			_fx("flash", 1.8, DANGER, {"id": str(event.body)})
		"reinforcements":
			for id: String in event.get("ids", []): _arrivals[id] = 0.0
			_pulse(at, 1.8, 0.7, Color(DANGER, 0.8))
		"checkpoint":
			if str(event.get("action", "")) == "load": _reset_transients()

func _batch_static() -> void:
	# Normalize repeated geometry into instanced batches for the phone renderer.
	var pending: Array[Node]=[root_static]
	var groups: Dictionary={}
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		for child: Node in node.get_children(): pending.append(child)
		# Only plain primitives with a material_override are batched; custom meshes are left alone.
		if not node is MeshInstance3D or node.mesh==null or node.material_override==null or node.has_meta("no_batch"): continue
		var source: Mesh=node.mesh
		var shape: Mesh
		var dimensions:=Vector3.ONE
		var key: String=""
		if source is BoxMesh:
			dimensions=source.size
			var unit:=BoxMesh.new()
			unit.size=Vector3.ONE
			shape=unit
			key="box"
		elif source is SphereMesh:
			shape=source
			key="sphere_%s_%s" % [source.radial_segments,source.rings]
		elif source is CylinderMesh:
			var unit:=CylinderMesh.new()
			unit.bottom_radius=1.0
			unit.top_radius=source.top_radius/source.bottom_radius
			unit.height=1.0
			unit.radial_segments=source.radial_segments
			shape=unit
			dimensions=Vector3(source.bottom_radius,source.height,source.bottom_radius)
			key="cylinder_%.4f_%d" % [unit.top_radius,unit.radial_segments]
		else: continue
		key+="_"+str(node.material_override.get_instance_id())+"_"+str(node.cast_shadow)
		if not groups.has(key): groups[key]={"mesh":shape,"material":node.material_override,"transforms":[],"shadow":node.cast_shadow}
		var placed: Transform3D=node.global_transform
		placed.basis=placed.basis*Basis.from_scale(dimensions)
		groups[key].transforms.append(placed)
		node.mesh=null
	for group: Dictionary in groups.values():
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=group.mesh
		batch.instance_count=group.transforms.size()
		for i: int in range(batch.instance_count): batch.set_instance_transform(i,group.transforms[i])
		var instance:=MultiMeshInstance3D.new()
		instance.multimesh=batch
		instance.material_override=group.material
		instance.cast_shadow=group.shadow
		root_static.add_child(instance)
