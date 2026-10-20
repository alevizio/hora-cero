extends Node3D
## Juan Salvo and the cascarudos on the Plaza de Mayo (the rules: simulation.gd, units[].arrive / suit, data "creatures"):
## what the square shows of them beyond their figures. Their figures are the world's actors like everyone's
## (operative.gd), dressed from the art pack's licensed slots ("art:juan_salvo", "art:cascarudo": the models made for
## the game, moved by cutout.gd): nothing of their look is drawn or modelled here.
##  - Who is not in the square is not seen: Juan Salvo until he comes, a cascarudo until it comes and while it is away
##    (driven off the map by a shot).
##  - In ink on the ground, for each cascarudo in the square: a red ring round it (dashed while it roams, whole once it
##    has sensed someone, beating while it stands over one it knocked down, pale while it runs off), the reach of its
##    senses as a faint dashed circle (plainer while the clock is stopped), a red line to the one it is going for, a
##    pale dashed line to the noise that draws it.
##  - What is coming: a few seconds before a cascarudo comes up an avenue, a red beat at the edge where it will come in;
##    before Juan Salvo comes, a brass ring where he will walk to and a dashed line from where he comes in.
##  - The night on their models (the art pack's, cutout.gd weather()): the snow settling on Juan Salvo's hood and
##    shoulders and on the cascarudos' backs as it builds up on the square, and both of them wetter as the night goes on.
## plaza.gd makes it (build) and moves it on (update); it only reads the rules.

const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const Cutout := preload("res://scripts/three_d/cutout.gd")
const PlazaGround := preload("res://scripts/three_d/plaza_ground.gd")
const DANGER := Color(1.0, 0.34, 0.24)
const PALE := Color(0.95, 0.93, 0.84)
const BRASS := Color(0.88, 0.68, 0.3)
## Marks lie just over the ground, as the world's own (world.gd INK_Y).
const MARK_Y: float = 0.1
## Seconds before a cascarudo or Juan Salvo comes that the square shows where.
const WARN: float = 10.0

var sim: RefCounted
var structures: Node3D
var world: Node
var marks: MeshInstance3D
var _ink: ImmediateMesh
var _clock: float = 0.0
## Ring radius round each cascarudo (metres), from its slot's size.
var _ring_m: float = 2.4

func setup(owner_structures: Node3D) -> void:
	structures = owner_structures
	sim = structures.get("sim")
	var spec: Dictionary = ArtPack.parse_look(str(sim.data.get("creatures", {}).get("look", "")))
	if not spec.is_empty():
		# round the whole of it, a little clear of its legs
		_ring_m = maxf(maxf(float(spec.get("length_m", 0.0)), float(spec.get("width_m", 0.0))), float(spec.height_m)) * 0.5 + 0.8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.render_priority = 3
	_ink = ImmediateMesh.new()
	marks = MeshInstance3D.new()
	marks.name = "CreatureMarks"
	marks.mesh = _ink
	marks.material_override = material
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.set_meta("no_batch", true)
	add_child(marks)

## Every frame (plaza.gd update): who shows, and the marks.
func update(dt: float, paused: bool) -> void:
	if sim == null: return
	if not paused: _clock += dt
	if world == null: world = _find_world()
	var cover: float = PlazaGround.snow_cover(sim)
	Cutout.weather(cover, 0.3 + 0.55 * cover)
	_show_who_is_here()
	_draw(paused)

func _find_world() -> Node:
	var n: Node = get_parent()
	while n != null:
		if "actors" in n: return n
		n = n.get_parent()
	return null

## Juan Salvo before he comes, a cascarudo before it comes and while it is off the map: not seen.
func _show_who_is_here() -> void:
	if world == null: return
	var actors: Dictionary = world.get("actors")
	for unit: Dictionary in sim.units:
		if not unit.has("arrive") or not actors.has(unit.id): continue
		var model: Node3D = actors[unit.id]
		var here: bool = not bool(unit.get("away", false)) and not bool(unit.get("buried", false))
		if model.visible != here: model.visible = here
	for guard: Dictionary in sim.guards:
		if not bool(guard.get("creature", false)) or not actors.has(guard.id): continue
		var model: Node3D = actors[guard.id]
		var here: bool = not str(guard.state) in ["waiting", "away"]
		if model.visible != here: model.visible = here

func _ground(point: Vector2) -> Vector3:
	var x: float = point.x / 32.0
	var z: float = point.y / 32.0
	var y: float = MARK_Y
	if structures != null and structures.has_method("ground_height"): y += float(structures.call("ground_height", x, z))
	return Vector3(x, y, z)

func _draw(paused: bool) -> void:
	_ink.clear_surfaces()
	_ink.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# (never an empty surface: one triangle of nothing first)
	_pen(PALE, 0.0)
	for i: int in range(3): _ink.surface_add_vertex(Vector3.ZERO)
	var beat: float = 0.5 + 0.5 * sin(_clock * 6.0)
	var sense: float = float(sim.data.get("creatures", {}).get("sense", 640.0)) / 32.0
	for beast: Dictionary in sim.guards:
		if not bool(beast.get("creature", false)): continue
		var state: String = str(beast.state)
		var at: Vector3 = _ground(sim.position_of(beast))
		match state:
			"waiting", "away":
				# about to come up the avenue: a red beat at the edge of the map where it will
				var left: float = float(beast.at) - float(sim.time) if state == "waiting" else float(beast.away_left)
				if left > 0.0 and left <= WARN and sim.phase == "playing":
					var home: Vector3 = _ground(beast.home)
					_pen(DANGER, 0.45 + 0.45 * beat)
					_ring(home, 1.6 + 0.6 * beat, 0.16, 10, 0.55, _clock * 0.6)
					_dashes(home, _ground(beast.entry), 0.12, 0.9, 0.7)
				continue
			"dead":
				continue
			"driven":
				_pen(PALE, 0.55)
				_ring(at, _ring_m, 0.12, 14, 0.5, -_clock * 0.8)
				continue
		var tone: float = 0.95 if state in ["stalk", "stay"] else 0.75
		_pen(DANGER, tone * (0.55 + 0.45 * beat) if state == "stay" else tone)
		if state == "prowl": _ring(at, _ring_m, 0.16, 16, 0.6, _clock * 0.25)
		else: _ring(at, _ring_m, 0.2 if state == "stalk" else 0.16)
		# how far it senses people out in the open
		if state in ["prowl", "stalk"]:
			_pen(DANGER, 0.42 if paused else 0.22)
			_ring(at, sense, 0.1, 48, 0.45, _clock * 0.05)
		# the one it is going for
		var target: String = str(beast.get("target_id", ""))
		if state == "stalk" and target != "":
			var prey: Dictionary = sim.unit_by_id(target)
			if prey.is_empty(): prey = sim.guard_by_id(target)
			if not prey.is_empty():
				_pen(DANGER, 0.85)
				_dashes(at, _ground(sim.position_of(prey)), 0.14, 0.7, 0.35, _clock * 2.0)
		# the noise that draws it
		if state == "drawn":
			var path: Array = beast.get("path", [])
			if not path.is_empty():
				_pen(PALE, 0.7)
				_dashes(at, _ground(path.back()), 0.12, 0.5, 0.5, _clock * 1.5)
	# Juan Salvo (or anyone of the squad who comes later): where he comes in and walks to
	for unit: Dictionary in sim.units:
		if not bool(unit.get("away", false)) or not unit.has("arrive") or sim.phase != "playing": continue
		var left: float = float(unit.arrive.get("at", 0.0)) - float(sim.time)
		if left > WARN or left < 0.0: continue
		var to: Array = unit.arrive.get("to", [])
		if to.size() < 2: continue
		var goal: Vector3 = _ground(Vector2(float(to[0]), float(to[1])))
		_pen(BRASS, 0.55 + 0.4 * beat)
		_ring(goal, 1.2 + 0.3 * beat, 0.14)
		_pen(BRASS, 0.6)
		_dashes(_ground(sim.position_of(unit)), goal, 0.12, 0.8, 0.6, -_clock * 1.5)
	_ink.surface_end()

# --- ink on the ground (as world.gd draws its own) ---
func _pen(color: Color, alpha: float = 1.0) -> void:
	_ink.surface_set_color(Color(color.r, color.g, color.b, color.a * alpha))

func _ribbon(a: Vector3, b: Vector3, width: float) -> void:
	var along: Vector3 = b - a
	if along.length_squared() < 0.000001: return
	var side: Vector3 = Vector3(-along.z, 0, along.x).normalized() * width * 0.5
	for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]: _ink.surface_add_vertex(v)

func _arc(center: Vector3, radius: float, from: float, to: float, width: float) -> void:
	var pieces: int = maxi(1, int(ceil(absf(to - from) * radius / 0.3)))
	var previous: Vector3 = center + Vector3(cos(from), 0, sin(from)) * radius
	for i: int in range(1, pieces + 1):
		var a: float = lerpf(from, to, float(i) / pieces)
		var next: Vector3 = center + Vector3(cos(a), 0, sin(a)) * radius
		_ribbon(previous, next, width)
		previous = next

func _ring(center: Vector3, radius: float, width: float, dashes: int = 0, duty: float = 0.6, turn: float = 0.0) -> void:
	if dashes <= 0:
		_arc(center, radius, 0.0, TAU, width)
		return
	for i: int in range(dashes):
		var from: float = turn + TAU * float(i) / dashes
		_arc(center, radius, from, from + TAU * duty / dashes, width)

func _dashes(a: Vector3, b: Vector3, width: float, dash: float, gap: float, offset: float = 0.0) -> void:
	var length: float = a.distance_to(b)
	if length < 0.0001: return
	var cursor: float = -fposmod(offset, dash + gap)
	while cursor < length:
		var from: float = maxf(cursor, 0.0)
		var to: float = minf(cursor + dash, length)
		if to > from: _ribbon(a.lerp(b, from / length), a.lerp(b, to / length), width)
		cursor += dash + gap
