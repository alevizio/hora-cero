extends "res://scripts/three_d/boca_ground.gd"
## The ground of the Plaza de Mayo on the night the snow begins (Plaza de Mayo, 1958): the carriageways of granite
## setts round the square (Rivadavia with the tram rails, Hipólito Yrigoyen, Bolívar and Balcarce) and the streets that
## leave it (the Avenida de Mayo west, San Martín and Reconquista north, Defensa south), the stone walks and the lawns
## of the plaza, kerbs between pavement and street, the three stairs of the subte left open in the ground; and over it
## all the snow, laid by the rules' own clock: a dusting at the start (the lawns white, the stone wet), whitening as the
## snow falls (the lawns first, the carriageways last; the busy streets go to grey slush), until it lies everywhere. From Vemork's ground
## (snow_ground.gd, as a child) it keeps the footprints; the falling snow is its own, thick or thin as the rules say.
## Built once by world.gd in the nature slot: set `sim`, add to the tree, build().

const PlazaGroundShader := preload("res://shaders/plaza_ground.gdshader")
const SnowfallShader := preload("res://shaders/plaza_snowfall.gdshader")
## The falling snow in two layers, each one draw: the field (a box of flakes over the ground the camera looks at,
## sized to the view so the snow reads at every zoom) and the near one (bigger, softer flakes between the camera and
## the ground; in a low view, drifting past the lens). How many of each at the heaviest; the steady part of the fall.
const FIELD_FLAKES := 14000
const NEAR_FLAKES := 3000
const BASE_FALL := 0.9
## The lamps a flake can catch the light of (the nearest to the view; plaza_snowfall.gdshader's arrays).
const FLAKE_LAMPS := 12
## Tonight's tracks in the snow: a map over the square and its streets (metres; TRAMPLE_PX pixels a metre) of the
## cover the snow had when somebody last walked there; the ground shader tramples it grey and lets the falling snow
## fill it in. Stamped from the rules' people and squad a few times a second.
const TRAMPLE_RECT := Rect2(-10.0, -10.0, 300.0, 186.0)
const TRAMPLE_PX := 2.0
const TRAMPLE_EVERY := 0.25
const MASK_PX := Vector2i(2048, 1200)
## The city's streets beyond the map (metres): the two running north-south west of it (their west kerb), the one
## behind the north row (its north kerb); the blocks between them (west of the map, and along the avenue).
const WEST_STREETS: Array[float] = [-86.0, -12.0]
const NORTH_STREET := -72.0
const WEST_SPANS: Array[Vector2] = [Vector2(-150.0, -88.0), Vector2(-76.0, -14.0)]

var _p: Dictionary = {}
## The stairs down into the subte (metres): holes in the ground, built by the structures (plaza.gd).
var stairs: Array[Rect2] = []
## The falling snow's layers: [multimesh, material, flakes] (field, near); the fall and the wind added up so far; the
## lamps for the flakes' light (lamp_list of the structures), and the clock of the next pick of the nearest.
var _falls: Array = []
var _drift := Vector3.ZERO
var _fall_lamps: Array = []
var _lamp_clock: float = 0.0
var _ink: bool = false
var _gust: float = 0.0
var _trample := PackedByteArray()
var _trample_size := Vector2i.ZERO
var _trample_tex: ImageTexture
var _trample_clock: float = 0.0
var _trample_time: float = 0.0
var _kerb_snow: Array[Node3D] = []
var _cover: float = -1.0

func build() -> void:
	_p = sim.data.get("plazaWorld", {})
	_h = {}
	_b = {}
	map_size = Vector2(float(sim.data.width), float(sim.data.height)) / 32.0
	mask_rect = Rect2(-150.0, -90.0, map_size.x + 300.0, map_size.y + 174.0)
	for key: String in ["subteN", "subteS", "subteService"]:
		stairs.append(rect_of(_p, key))
	_build_ground_material()
	_build_land()
	_build_kerbs()
	snow = SnowGround.new()
	snow.name = "Snow"
	snow.sim = sim
	snow.map_size = map_size
	add_child(snow)
	snow._build_prints()
	snow.print_scale = 1.1
	(snow.get_node("Footprints") as MultiMeshInstance3D).material_override.set_shader_parameter("snow_shadow", Color(0.6, 0.6, 0.7))
	_build_fall()
	update(0.0, true)

## A rectangle of the layout's world data, [x0, z0, x1, z1] in metres.
static func rect_of(p: Dictionary, key: String, fallback: Array = [0.0, 0.0, 1.0, 1.0]) -> Rect2:
	var v: Array = p.get(key, fallback)
	return Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))

static func pair_of(p: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var v: Array = p.get(key, [fallback.x, fallback.y])
	return Vector2(float(v[0]), float(v[1]))

## The snow lying already when the operation begins (it began to fall a few minutes before ten past nine): the lawns
## white, the walks dusted, the carriageways only wet. The night's snow lays the rest on top of it (laid()).
const DUSTING := 0.3

## How white the ground lies once a share of the night's snow has fallen (snow_cover): the dusting, then the rest.
static func laid(cover: float) -> float:
	return DUSTING + (1.0 - DUSTING) * clampf(cover, 0.0, 1.0)

## How much of the night's snow has fallen (0 at the start, 1 when it buries the square): the schedule of the rules'
## snowfall (data snowfall.schedule, strength by time) summed up to now, over the sum up to the burial.
static func snow_cover(rules: RefCounted) -> float:
	var spec: Dictionary = rules.data.get("snowfall", {})
	if spec.is_empty(): return 1.0
	if bool(rules.get("buried_square")): return 1.0
	var schedule: Array = spec.get("schedule", [])
	var bury: float = float(spec.get("bury", 480.0))
	if schedule.is_empty(): return clampf(float(rules.time) / maxf(1.0, bury), 0.0, 1.0)
	return clampf(fallen(schedule, float(rules.time)) / maxf(0.001, fallen(schedule, bury)), 0.0, 1.0)

## The snow fallen by time t: the strength of the schedule (piecewise linear between its [time, strength] points,
## flat before the first and after the last) summed over the seconds.
static func fallen(schedule: Array, t: float) -> float:
	var total := 0.0
	var t0 := 0.0
	var v0 := float(schedule[0][1])
	for entry: Array in schedule:
		var t1 := float(entry[0])
		var v1 := float(entry[1])
		if t1 <= t0:
			v0 = v1
			continue
		if t <= t1:
			var vt := lerpf(v0, v1, (t - t0) / (t1 - t0))
			return total + (v0 + vt) * 0.5 * (t - t0)
		total += (v0 + v1) * 0.5 * (t1 - t0)
		t0 = t1
		v0 = v1
	return total + v0 * maxf(0.0, t - t0)

## The carriageways (metres): the four streets round the square, the avenue and the streets that leave it, and the
## city's streets beyond the map. Shared with the structures (plaza.gd), which build the blocks between them.
static func roads(p: Dictionary, W: float, H: float) -> Array[Rect2]:
	var x0 := -150.0
	var x1 := W + 150.0
	var z0 := -90.0
	var z1 := H + 84.0
	var riv := pair_of(p, "rivRoad", Vector2(25.5, 32.5))
	var yri := pair_of(p, "yriRoad", Vector2(135.5, 142.5))
	var bol := pair_of(p, "bolRoad", Vector2(31.0, 39.0))
	var bal := pair_of(p, "balRoad", Vector2(245.0, 253.0))
	var avm := pair_of(p, "avmRoad", Vector2(77.0, 95.0))
	var sm := pair_of(p, "sanMartin", Vector2(96.0, 104.0))
	var rq := pair_of(p, "reconquista", Vector2(180.0, 188.0))
	var df := pair_of(p, "defensa", Vector2(120.0, 128.0))
	var out: Array[Rect2] = []
	out.append(Rect2(x0, riv.x, x1 - x0, riv.y - riv.x))
	out.append(Rect2(x0, yri.x, x1 - x0, yri.y - yri.x))
	out.append(Rect2(bol.x, riv.y, bol.y - bol.x, yri.x - riv.y))
	out.append(Rect2(bal.x, z0, bal.y - bal.x, z1 - z0))
	out.append(Rect2(x0, avm.x, bol.x - x0, avm.y - avm.x))
	out.append(Rect2(sm.x + 1.0, z0, sm.y - sm.x - 2.0, riv.x - z0))
	out.append(Rect2(rq.x + 1.0, z0, rq.y - rq.x - 2.0, riv.x - z0))
	out.append(Rect2(df.x + 1.0, yri.y, df.y - df.x - 2.0, z1 - yri.y))
	# beyond the map: Paseo Colón behind the Casa Rosada, two streets west, the street behind the north row and the
	# one behind the ministries
	out.append(Rect2(W + 6.0, z0, 14.0, z1 - z0))
	for x: float in WEST_STREETS: out.append(Rect2(x, z0, 8.0, z1 - z0))
	out.append(Rect2(x0, NORTH_STREET, x1 - x0, 8.0))
	out.append(Rect2(x0, H + 36.0, x1 - x0, 8.0))
	return out

## The two Diagonales leaving the square's corners (metres): Norte from behind its north-west row toward the north-west,
## Sur from beyond its south-west corner toward the south-west; [start, direction, half width]. Their carriageways
## are drawn on the ground here, their blocks built by the city (plaza_city.gd).
static func diagonal_lines() -> Array:
	return [[Vector2(30.0, 0.0), Vector2(-1.0, -1.0).normalized(), 9.0], [Vector2(-8.0, 166.0), Vector2(-1.0, 1.0).normalized(), 9.0]]

## The lawns of the plaza (metres): the square inside its walk, less the paved ways across it: the promenade from the
## avenue to the Casa Rosada, the walk from Rivadavia to Yrigoyen, the four diagonals from the corners, the oval round
## the Pirámide, the rounds of the Belgrano and the flagstaff. As an image of the mask's size (1 lawn, 0 paved).
func _lawns(img: Image, paved: float = 0.0) -> void:
	var plaza := rect_of(_p, "plaza", [42.0, 36.0, 242.0, 132.0])
	var inner := plaza.grow(-5.0)
	if paved > 0.0: _fill(img, plaza, paved)
	_fill(img, inner, 1.0)
	var c := pair_of(_p, "piramide", Vector2(142.0, 84.0))
	_fill(img, Rect2(plaza.position.x, c.y - 5.0, plaza.size.x, 10.0), paved)
	_fill(img, Rect2(c.x - 4.0, plaza.position.y, 8.0, plaza.size.y), paved)
	for corner: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.end]:
		_stroke(img, corner, c, 2.4, paved)
	_ellipse(img, c, Vector2(21.0, 14.5), paved)
	_ellipse(img, pair_of(_p, "belgrano", Vector2(229.0, 84.0)), Vector2(9.5, 9.5), paved)
	_ellipse(img, pair_of(_p, "flagpole", Vector2(196.0, 56.0)), Vector2(4.0, 4.0), paved)

## A thick line drawn into a mask: small squares stamped along it.
func _stroke(img: Image, a: Vector2, b: Vector2, half: float, v: float = 0.0) -> void:
	var n := int(a.distance_to(b) / 0.4) + 1
	for i: int in range(n + 1):
		var q := a.lerp(b, float(i) / float(n))
		_fill(img, Rect2(q.x - half, q.y - half, half * 2.0, half * 2.0), v)

## A filled ellipse in a mask, row by row.
func _ellipse(img: Image, c: Vector2, r: Vector2, v: float) -> void:
	var rows := int(r.y * 4.0)
	for i: int in range(-rows, rows + 1):
		var dz := float(i) / 4.0
		var half := r.x * sqrt(maxf(0.0, 1.0 - (dz * dz) / (r.y * r.y)))
		_fill(img, Rect2(c.x - half, c.y + dz - 0.13, half * 2.0, 0.26), v)

func _map() -> Image:
	var img := Image.create(MASK_PX.x, MASK_PX.y, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	return img

func _px(r: Rect2) -> Rect2i:
	var sx := float(MASK_PX.x) / mask_rect.size.x
	var sz := float(MASK_PX.y) / mask_rect.size.y
	var x0 := clampi(int(round((r.position.x - mask_rect.position.x) * sx)), 0, MASK_PX.x)
	var x1 := clampi(int(round((r.end.x - mask_rect.position.x) * sx)), 0, MASK_PX.x)
	var y0 := clampi(int(round((r.position.y - mask_rect.position.y) * sz)), 0, MASK_PX.y)
	var y1 := clampi(int(round((r.end.y - mask_rect.position.y) * sz)), 0, MASK_PX.y)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))

func _soften(img: Image, metres: float) -> ImageTexture:
	var f := clampf(metres * float(MASK_PX.x) / mask_rect.size.x, 1.0, 64.0)
	if f > 1.5:
		img.resize(maxi(8, int(MASK_PX.x / f)), maxi(8, int(MASK_PX.y / f)), Image.INTERPOLATE_LANCZOS)
		img.resize(MASK_PX.x, MASK_PX.y, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(img)

func _build_ground_material() -> void:
	var W := map_size.x
	var slush := _map()
	for box: Array in sim.data.get("snow", {}).get("packed", []):
		var r := _rect_of_units(box)
		if r.position.x <= 0.01 and r.end.x >= W - 0.01: r = Rect2(mask_rect.position.x, r.position.y, mask_rect.size.x, r.size.y)
		_fill(slush, r, 1.0)
	# the rails: the bed between them at half, the steel full
	var rails := _map()
	for track: Array in sim.data.get("tracks", []):
		var a := Vector2(float(track[0][0]), float(track[0][1])) / 32.0
		var b := Vector2(float(track[1][0]), float(track[1][1])) / 32.0
		var xa := mask_rect.position.x if minf(a.x, b.x) <= 0.01 else minf(a.x, b.x)
		var xb := mask_rect.end.x if maxf(a.x, b.x) >= W - 0.01 else maxf(a.x, b.x)
		_fill(rails, Rect2(xa, a.y - 0.62, xb - xa, 1.24), 0.5)
	for track: Array in sim.data.get("tracks", []):
		var a := Vector2(float(track[0][0]), float(track[0][1])) / 32.0
		var b := Vector2(float(track[1][0]), float(track[1][1])) / 32.0
		var xa := mask_rect.position.x if minf(a.x, b.x) <= 0.01 else minf(a.x, b.x)
		var xb := mask_rect.end.x if maxf(a.x, b.x) >= W - 0.01 else maxf(a.x, b.x)
		for dz: float in [-0.72, 0.72]: _fill(rails, Rect2(xa, a.y + dz - 0.12, xb - xa, 0.24), 1.0)
	var occl := _map()
	var yri_s := pair_of(_p, "yrigoyen", Vector2(132.0, 146.0)).y
	for o: Dictionary in sim.data.get("obstacles", []):
		if str(o.get("kind", "")) in ["building", "wall"]:
			var orr := _rect_of_units([o.x, o.y, o.w, o.h])
			# (the corner block south-w stands across Yrigoyen in the rules: the street beyond the hoarding is drawn
			# open, its building south of it)
			if str(o.get("id", "")) == "south-w" and orr.position.y < yri_s:
				orr = Rect2(orr.position.x, yri_s, orr.size.x, orr.end.y - yri_s)
			_fill(occl, orr, 1.0)
	for r: Rect2 in city_blocks(_p, map_size.x, map_size.y): _fill(occl, r, 1.0)
	for entry: Array in avenue_blocks(_p): _fill(occl, entry[0], 1.0)
	# the carriageways: the north-south ones at 0.6, the east-west ones (drawn over them) full, so the shader knows
	# which way the wheels run
	var road := _map()
	var all_roads := roads(_p, map_size.x, map_size.y)
	for r: Rect2 in all_roads:
		if r.size.x < r.size.y: _fill(road, r, 0.6)
	for r: Rect2 in all_roads:
		if r.size.x >= r.size.y: _fill(road, r, 1.0)
	for d: Array in diagonal_lines():
		var o: Vector2 = d[0]
		var dir: Vector2 = d[1]
		_stroke(road, o, o + dir * 260.0, float(d[2]), 0.6)
	# the square: its paved walks at half, its lawns full
	var lawn := _map()
	_lawns(lawn, 0.5)
	snow_material = ShaderMaterial.new()
	snow_material.shader = PlazaGroundShader
	snow_material.set_shader_parameter("powder_tex", load("res://assets/tex/plaza/powder_n.png"))
	snow_material.set_shader_parameter("packed_tex", load(BOCA_TEX + "slush_a.png"))
	snow_material.set_shader_parameter("setts_tex", load(TEX + "setts_a.png"))
	snow_material.set_shader_parameter("setts_nrm", load(TEX + "setts_n.png"))
	snow_material.set_shader_parameter("flags_tex", load(STRUCT + "concrete_a.png"))
	snow_material.set_shader_parameter("grass_tex", load(NATURE + "grass_albedo.png"))
	snow_material.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	snow_material.set_shader_parameter("slush_tex", _soften(slush, 1.0))
	snow_material.set_shader_parameter("rails_tex", _soften(rails, 0.2))
	snow_material.set_shader_parameter("occl_tex", _soften(occl, 1.6))
	snow_material.set_shader_parameter("road_tex", _soften(road, 0.3))
	snow_material.set_shader_parameter("lawn_tex", _soften(lawn, 0.4))
	_build_trample()
	snow_material.set_shader_parameter("trample_tex", _trample_tex)
	snow_material.set_shader_parameter("trample_rect", Vector4(TRAMPLE_RECT.position.x, TRAMPLE_RECT.position.y, 1.0 / TRAMPLE_RECT.size.x, 1.0 / TRAMPLE_RECT.size.y))
	snow_material.set_shader_parameter("mask_rect", Vector4(mask_rect.position.x, mask_rect.position.y, 1.0 / mask_rect.size.x, 1.0 / mask_rect.size.y))
	snow_material.set_shader_parameter("map_rect", Vector4(-640.0, -128.0, map_size.x + 140.0, map_size.y + 88.0))
	snow_material.set_shader_parameter("haze_color", HAZE)
	snow_material.set_shader_parameter("snow_tint", Color(0.89, 0.88, 0.93))

## The city's blocks round the map (metres): between the streets beyond its edges, where the structures stand
## façades and the ground is dark at their feet (the avenue's own blocks are avenue_blocks()).
static func city_blocks(p: Dictionary, W: float, H: float) -> Array[Rect2]:
	var riv := pair_of(p, "rivadavia", Vector2(22.0, 36.0))
	var yri := pair_of(p, "yrigoyen", Vector2(132.0, 146.0))
	var sm := pair_of(p, "sanMartin", Vector2(96.0, 104.0))
	var rq := pair_of(p, "reconquista", Vector2(180.0, 188.0))
	var df := pair_of(p, "defensa", Vector2(120.0, 128.0))
	var bal := pair_of(p, "balcarce", Vector2(242.0, 256.0))
	var out: Array[Rect2] = []
	# north, beyond the street behind the square's own north row
	for span: Vector2 in [WEST_SPANS[0], WEST_SPANS[1], Vector2(-4.0, sm.x), Vector2(sm.y, rq.x), Vector2(rq.y, bal.x), Vector2(bal.y, W + 4.0)]:
		out.append(Rect2(span.x, NORTH_STREET - 58.0, span.y - span.x, 56.0))
	# west of the map: north of Rivadavia and south of Yrigoyen (between them, the avenue's)
	for span: Vector2 in WEST_SPANS:
		out.append(Rect2(span.x, NORTH_STREET + 10.0, span.y - span.x, riv.x - NORTH_STREET - 10.0))
		out.append(Rect2(span.x, yri.y, span.y - span.x, H + 34.0 - yri.y))
	# south, beyond the street behind the ministries
	for span: Vector2 in [WEST_SPANS[0], WEST_SPANS[1], Vector2(-4.0, df.x), Vector2(df.y, bal.x), Vector2(bal.y, W + 4.0)]:
		out.append(Rect2(span.x, H + 46.0, span.y - span.x, 40.0))
	# east, beyond Paseo Colón: the port's long low sheds
	for z: Vector2 in [Vector2(-100.0, 20.0), Vector2(30.0, 110.0), Vector2(120.0, 210.0)]:
		out.append(Rect2(W + 24.0, z.x, 36.0, z.y - z.x))
	return out

## The blocks along the Avenida de Mayo west of the map, between Rivadavia and Yrigoyen: [rect, on the north side].
static func avenue_blocks(p: Dictionary) -> Array:
	var riv := pair_of(p, "rivadavia", Vector2(22.0, 36.0))
	var yri := pair_of(p, "yrigoyen", Vector2(132.0, 146.0))
	var avm := pair_of(p, "avMayo", Vector2(72.0, 100.0))
	var out: Array = []
	for span: Vector2 in WEST_SPANS:
		out.append([Rect2(span.x, riv.y, span.y - span.x, avm.x - riv.y), true])
		out.append([Rect2(span.x, avm.y, span.y - span.x, yri.x - avm.y), false])
	return out

# ------------------------------------------------------------------------------------------------ the land
## Flat ground at y = 0 in pieces about 28 m across over the map and its edge streets (so no piece is lit by more
## lamps than the renderer takes), and four big ones round it under the city, out west to the Congreso (no lamp of
## the game's own lights them: one draw each); the subte's stairs left open.
func _build_land() -> void:
	var xs: Array[float] = [0.0]
	var x := 28.0
	while x < map_size.x - 1.0:
		xs.append(x)
		x += 28.0
	xs.append(map_size.x)
	var zs: Array[float] = [-30.0, 0.0, 22.0, 46.0, 72.0, 100.0, 116.0, 132.0, 146.0, map_size.y]
	var cells: Array[Rect2] = []
	for i: int in range(xs.size() - 1):
		for j: int in range(zs.size() - 1):
			cells.append(Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j]))
	var z0 := -140.0
	var z1 := map_size.y + 96.0
	cells.append(Rect2(-700.0, z0, 700.0, z1 - z0))
	cells.append(Rect2(map_size.x, z0, 150.0, z1 - z0))
	cells.append(Rect2(0.0, z0, map_size.x, -30.0 - z0))
	cells.append(Rect2(0.0, map_size.y, map_size.x, z1 - map_size.y))
	var count := 0
	for cell: Rect2 in cells:
		for piece: Rect2 in _without(cell, stairs):
			var mesh := PlaneMesh.new()
			mesh.size = piece.size
			var node := MeshInstance3D.new()
			node.name = "Land%d" % count
			node.mesh = mesh
			node.material_override = snow_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = Vector3(piece.get_center().x, 0.0, piece.get_center().y)
			node.set_meta("no_batch", true)
			add_child(node)
			count += 1

## A rectangle less the holes in it, as rectangles.
static func _without(r: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = [r]
	for hole: Rect2 in holes:
		var next: Array[Rect2] = []
		for piece: Rect2 in out:
			var cut := piece.intersection(hole)
			if cut.size.x <= 0.001 or cut.size.y <= 0.001:
				next.append(piece)
				continue
			if cut.position.y > piece.position.y: next.append(Rect2(piece.position.x, piece.position.y, piece.size.x, cut.position.y - piece.position.y))
			if cut.end.y < piece.end.y: next.append(Rect2(piece.position.x, cut.end.y, piece.size.x, piece.end.y - cut.end.y))
			if cut.position.x > piece.position.x: next.append(Rect2(piece.position.x, cut.position.y, cut.position.x - piece.position.x, cut.size.y))
			if cut.end.x < piece.end.x: next.append(Rect2(cut.end.x, cut.position.y, piece.end.x - cut.end.x, cut.size.y))
		out = next
	return out

## Granite kerbs along every carriageway, broken where another crosses it; the snow on their tops grows with the
## night (its own nodes, raised out of the stone as the snow falls). (A kerb 14 cm high throws no shadow worth a draw.)
func _build_kerbs() -> void:
	var m := ShaderMaterial.new()
	m.shader = SurfaceShader
	m.set_shader_parameter("albedo_tex", load(STRUCT + "stone_a.png"))
	m.set_shader_parameter("normal_tex", load(STRUCT + "stone_n.png"))
	m.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("roughness", 0.85)
	m.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	m.set_shader_parameter("snow_amount", 0.0)
	var snow_m := ShaderMaterial.new()
	snow_m.shader = SnowLayerShader
	snow_m.set_shader_parameter("snow_tex", load(SNOW_TEX + "snow_a.png"))
	snow_m.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	var stone := {"kerb": m}
	var white := {Snow.KEY: snow_m}
	var list := roads(_p, map_size.x, map_size.y)
	var k := Kit.new()
	var ks := Kit.new()
	var count := 0
	for i: int in range(list.size()):
		var r: Rect2 = list[i]
		var along_x := r.size.x >= r.size.y
		var edges: Array[float] = []
		if along_x: edges.append_array([r.position.y, r.end.y])
		else: edges.append_array([r.position.x, r.end.x])
		for e: int in range(2):
			var at: float = edges[e]
			var gaps: Array = []
			for j: int in range(list.size()):
				if j == i: continue
				var o: Rect2 = list[j]
				if along_x and o.position.y <= at + 0.5 and o.end.y >= at - 0.5: gaps.append(Vector2(o.position.x - 1.5, o.end.x + 1.5))
				elif not along_x and o.position.x <= at + 0.5 and o.end.x >= at - 0.5: gaps.append(Vector2(o.position.y - 1.5, o.end.y + 1.5))
			var lo := r.position.x if along_x else r.position.y
			var hi := r.end.x if along_x else r.end.y
			for span: Vector2 in _spans(lo, hi, gaps):
				var a := span.x
				while a < span.y - 0.05:
					var bb := minf(a + 14.0, span.y)
					var c := (a + bb) * 0.5
					if along_x: k.box("kerb", Vector3(c, 0.07, at), Vector3(bb - a, 0.14, 0.24), Color(0.55, 0.55, 0.57), Color(0.85, 0.85, 0.86), Vector2(a * Kit.UV_M, 0.0))
					else: k.box("kerb", Vector3(at, 0.07, c), Vector3(0.24, 0.14, bb - a), Color(0.55, 0.55, 0.57), Color(0.85, 0.85, 0.86), Vector2(a * Kit.UV_M, 0.0))
					var p0 := Vector3(a, 0.14, at) if along_x else Vector3(at, 0.14, a)
					var p1 := Vector3(bb, 0.14, at) if along_x else Vector3(at, 0.14, bb)
					Snow.ridge(ks, p0, p1, Vector3.UP, 0.22, 0.06, 0.02)
					a = bb
					count += 1
					if count % 80 == 0:
						k.commit(self, stone, "Kerbs", false)
						var n := ks.commit(self, white, "KerbSnow", false)
						if n != null: _kerb_snow.append(n)
						k = Kit.new()
						ks = Kit.new()
	k.commit(self, stone, "Kerbs", false)
	var last := ks.commit(self, white, "KerbSnow", false)
	if last != null: _kerb_snow.append(last)

# ------------------------------------------------------------------------------------------------ tonight's tracks
func _build_trample() -> void:
	_trample_size = Vector2i(int(TRAMPLE_RECT.size.x * TRAMPLE_PX), int(TRAMPLE_RECT.size.y * TRAMPLE_PX))
	_trample = PackedByteArray()
	_trample.resize(_trample_size.x * _trample_size.y)
	_trample.fill(0)
	_trample_tex = ImageTexture.create_from_image(Image.create_from_data(_trample_size.x, _trample_size.y, false, Image.FORMAT_L8, _trample))

func _clear_tracks() -> void:
	if _trample_tex == null: return
	_trample.fill(0)
	_trample_tex.update(Image.create_from_data(_trample_size.x, _trample_size.y, false, Image.FORMAT_L8, _trample))

## Where everybody on foot stands now (the squad, the people, anyone the rules move), pressed into the snow with the
## cover of the moment; the ground shader does the rest. (Only once there is snow to press.)
func _stamp_tracks() -> void:
	if _trample_tex == null or sim == null: return
	var level := laid(snow_cover(sim))
	if level < 0.12: return
	var v := clampi(int(round(level * 255.0)), 1, 255)
	var changed := false
	var walkers: Array = []
	walkers.append_array(sim.units)
	walkers.append_array(sim.guards)
	for actor: Dictionary in walkers:
		if actor.has("alive") and not bool(actor.alive): continue
		if str(actor.get("state", "")) in ["safe", "lost", "dead"]: continue
		var at := Vector2(float(actor.x), float(actor.y)) / 32.0
		changed = _press(at, 1.0, v) or changed
	if changed:
		_trample_tex.update(Image.create_from_data(_trample_size.x, _trample_size.y, false, Image.FORMAT_L8, _trample))

## A round print of `radius` metres at a point on the map, raised to `v` where it lies lower.
func _press(at: Vector2, radius: float, v: int) -> bool:
	var c := (at - TRAMPLE_RECT.position) * TRAMPLE_PX
	var r := radius * TRAMPLE_PX
	var x0 := maxi(0, int(floor(c.x - r)))
	var x1 := mini(_trample_size.x - 1, int(ceil(c.x + r)))
	var y0 := maxi(0, int(floor(c.y - r)))
	var y1 := mini(_trample_size.y - 1, int(ceil(c.y + r)))
	var changed := false
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var d := Vector2(float(x) + 0.5 - c.x, float(y) + 0.5 - c.y).length() / r
			if d > 1.0: continue
			# (its rim pressed less: as if older, so the shader's edge comes out soft)
			var w := v - int(round((1.0 - smoothstep(1.0, 0.45, d)) * 22.0))
			var i := y * _trample_size.x + x
			if _trample[i] < w:
				_trample[i] = maxi(w, 1)
				changed = true
	return changed

# ------------------------------------------------------------------------------------------------ falling snow
## The falling snow (plaza_snowfall.gdshader): two layers of flakes, each one MultiMesh (one draw), moved entirely on
## the GPU; update() sets their boxes round the view, how many fall and how fast as the rules' snowfall says.
func _build_fall() -> void:
	var specs: Array = [["Snowfall", FIELD_FLAKES, 19580412], ["SnowfallNear", NEAR_FLAKES, 19580413]]
	for spec: Array in specs:
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var material := ShaderMaterial.new()
		material.shader = SnowfallShader
		material.render_priority = 8
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = quad
		multi.instance_count = int(spec[1])
		var r := RandomNumberGenerator.new()
		r.seed = int(spec[2])
		for i: int in range(multi.instance_count):
			multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(r.randf(), r.randf(), r.randf())))
		var node := MultiMeshInstance3D.new()
		node.name = str(spec[0])
		node.multimesh = multi
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-1200, -50, -1200), Vector3(2400, 400, 2400))
		add_child(node)
		_falls.append([multi, material, int(spec[1])])

## The structures' lamps (world.gd, once built: lamp_list, [position, colour, strength, ...]): the flakes near one catch
## its light.
func set_lamps(all: Array) -> void:
	_fall_lamps = all
	_lamp_clock = 0.0

## Comic ink: the flakes printed as white dots ringed in ink.
func set_ink(on: bool) -> void:
	super.set_ink(on)
	_ink = on
	for layer: Array in _falls: (layer[1] as ShaderMaterial).set_shader_parameter("ink", 1.0 if on else 0.0)

func set_dawn(_t: float) -> void:
	pass

func update(dt: float, paused: bool) -> void:
	if snow != null: snow.update(dt, paused)
	var cover := snow_cover(sim)
	if absf(cover - _cover) > 0.0005:
		_cover = cover
		snow_material.set_shader_parameter("cover", laid(cover))
		var lift := clampf(laid(cover) * 1.6, 0.02, 1.0)
		for n: Node3D in _kerb_snow: n.scale = Vector3(1.0, lift, 1.0)
		# prints show once there is snow to print in
		var prints := snow.get_node_or_null("Footprints") as Node3D if snow != null else null
		if prints != null: prints.visible = laid(cover) > 0.1
	# (the clock gone back, a restart or a checkpoint: tonight's tracks start again)
	if float(sim.time) < _trample_time - 0.001: _clear_tracks()
	_trample_time = float(sim.time)
	_trample_clock -= maxf(dt, 0.0)
	if _trample_clock <= 0.0:
		_trample_clock = TRAMPLE_EVERY
		_stamp_tracks()
	_update_fall(dt)

## The snow falling now: thick or thin with the rules' snowfall (a lull still shows it falling; the launch screen
## too), faster and blown aslant in a wave, in gusts; both layers' boxes round what the camera sees.
func _update_fall(dt: float) -> void:
	if _falls.is_empty(): return
	var strength: float = float(sim.snow_intensity()) if sim.has_method("snow_intensity") else 1.0
	if bool(sim.get("buried_square")): strength = maxf(strength, 3.0)
	strength = maxf(strength, 0.5)
	var heavy := clampf(strength - 0.8, 0.0, 2.4)
	_gust += maxf(dt, 0.0)
	var gust := 1.0 + 0.4 * sin(_gust * 0.71) * sin(_gust * 0.23 + 1.3)
	var wind := Vector2(0.3 + 0.95 * heavy, 0.12 + 0.35 * heavy) * gust
	var fall := 0.85 + 0.2 * strength
	_drift += Vector3(wind.x, -(fall - BASE_FALL), wind.y) * maxf(dt, 0.0)
	for i: int in range(3):
		if absf(_drift[i]) > 4096.0: _drift[i] = fposmod(_drift[i], 4096.0)
	var share := clampf(0.1 + strength * 0.28, 0.2, 1.0)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null: return
	var forward := -camera.global_transform.basis.z
	var eye := camera.global_position
	var focus := eye
	if forward.y < -0.05: focus += forward * (eye.y / -forward.y)
	focus.y = 0.0
	var ortho := camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var boxes: Array = []
	if ortho:
		# the view's height in metres: the boxes and the flakes scale with it, so a zoomed-out view keeps its snow
		var view := camera.size
		var high := minf(0.45 * view + 8.0, 40.0)
		var toward := (eye - focus).normalized()
		# (a flake high up shows over ground nearer the camera: the box moved toward it by half its height's worth)
		var flat := Vector3(toward.x, 0.0, toward.z).normalized()
		var lean := 1.0 / maxf(tan(asin(clampf(toward.y, 0.2, 1.0))), 0.3)
		var field_c := focus + flat * high * 0.5 * lean
		var near_c := focus + toward * minf(26.0, eye.distance_to(focus) * 0.5)
		var near_h := minf(0.4 * view + 6.0, 30.0)
		near_c.y = maxf(near_c.y, near_h * 0.5)
		boxes.append([Vector3(field_c.x, high * 0.5, field_c.z), Vector3(view * 2.4, high, view * 2.4), 3.4 * view / 720.0, Vector2.ZERO])
		boxes.append([near_c, Vector3(view * 2.1, near_h, view * 2.1), 6.5 * view / 720.0, Vector2.ZERO])
	else:
		var mid := eye + forward * 26.0
		boxes.append([Vector3(mid.x, 13.0, mid.z), Vector3(64.0, 26.0, 64.0), 0.055, Vector2.ZERO])
		boxes.append([eye + forward * 6.5, Vector3(13.0, 10.0, 13.0), 0.02, Vector2(0.35, 1.3)])
	_lamp_clock -= maxf(dt, 0.0)
	var pick_lamps := _lamp_clock <= 0.0
	if pick_lamps: _lamp_clock = 0.3
	var lamp_pos := PackedVector4Array()
	var lamp_col := PackedVector4Array()
	if pick_lamps: _nearest_lamps(focus, lamp_pos, lamp_col)
	for i: int in range(_falls.size()):
		var layer: Array = _falls[i]
		var multi := layer[0] as MultiMesh
		var m := layer[1] as ShaderMaterial
		var box: Array = boxes[i]
		multi.visible_instance_count = int(float(layer[2]) * share)
		m.set_shader_parameter("box_center", box[0])
		m.set_shader_parameter("box_size", box[1])
		m.set_shader_parameter("size_m", float(box[2]) * clampf(0.8 + 0.2 * strength, 0.9, 1.4))
		m.set_shader_parameter("near_fade", box[3])
		m.set_shader_parameter("drift", _drift)
		m.set_shader_parameter("base_fall", BASE_FALL)
		m.set_shader_parameter("velocity", Vector3(wind.x, -fall, wind.y))
		m.set_shader_parameter("streak", (0.02 + 0.018 * minf(heavy, 1.6)) * (1.0 if i == 0 else 0.55))
		m.set_shader_parameter("strength", clampf(0.8 + 0.1 * strength, 0.8, 1.0) * (1.0 if i == 0 else 0.8))
		m.set_shader_parameter("flake_color", Color(1.25, 1.3, 1.48))
		m.set_shader_parameter("min_px", 2.2 if _ink else 1.6)
		m.set_shader_parameter("ink", 1.0 if _ink else 0.0)
		m.set_shader_parameter("screen", get_viewport().get_visible_rect().size)
		# (as the grade's tilt-shift blurs at this zoom: atmosphere.gd; none in comic ink)
		m.set_shader_parameter("tilt_radius", 0.0 if _ink else (lerpf(2.0, 5.0, smoothstep(24.0, 110.0, camera.size)) if ortho else 2.0))
		if pick_lamps:
			m.set_shader_parameter("lamps", lamp_pos)
			m.set_shader_parameter("lamp_colors", lamp_col)
			m.set_shader_parameter("lamp_count", lamp_pos.size())

## The lamps nearest a point (up to FLAKE_LAMPS): their position and reach, their colour at their strength.
func _nearest_lamps(at: Vector3, pos: PackedVector4Array, col: PackedVector4Array) -> void:
	var lit: Array = []
	for entry: Array in _fall_lamps:
		var p: Vector3 = entry[0]
		lit.append([Vector2(p.x - at.x, p.z - at.z).length_squared(), entry])
	lit.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in range(mini(lit.size(), FLAKE_LAMPS)):
		var entry: Array = lit[i][1]
		var p: Vector3 = entry[0]
		var c: Color = entry[1]
		var k: float = clampf(float(entry[2]), 0.2, 1.6)
		pos.append(Vector4(p.x, p.y, p.z, 8.0 + 3.0 * k))
		col.append(Vector4(c.r * k * 2.2, c.g * k * 2.2, c.b * k * 2.2, 1.0))
