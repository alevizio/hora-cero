extends "res://scripts/three_d/harbour_ground.gd"
## The ground of La Boca (Operation Riachuelo), a snowy night: wet snow lying on the cobbles, trodden to slush on the
## busy streets, the tram rails and the square (the rules' packed snow); the railway cutting sunk between its brick
## retaining walls; the quay walls and the Riachuelo, laid from the mission's own rectangles (its water obstacles and
## the water-closed passages, the gondola's run and the boat's crossing); low mist on the river; and, borrowed from
## Vemork's ground (snow_ground.gd, as a child of this one), the footprints the rules lay and the falling snow.
## Built once by world.gd in the nature slot: set `sim`, add to the tree, build(). The harbour ground it extends keeps
## the water's and the mist's lamp reflections, faded when the quay's lamp board is cut.

const SnowGround = preload("res://scripts/three_d/snow_ground.gd")
const BocaGroundShader := preload("res://shaders/boca_ground.gdshader")
const SurfaceShader := preload("res://shaders/boca_surface.gdshader")
const Plan = preload("res://scripts/three_d/boca_plan.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")
const SnowLayerShader := preload("res://shaders/boca_snow.gdshader")
const SNOW_TEX := "res://assets/tex/snow/"
const BOCA_TEX := "res://assets/tex/boca/"
## Colour the city dissolves into far beyond its last blocks: the blue-hour haze (the fog's colour).
const HAZE := Color(0.5, 0.49, 0.58)
const MASK_W := 1024
const MASK_H := 1024

var map_size := Vector2(240.0, 150.0)
var _b: Dictionary = {}
## The river band (z, metres) and the cutting's two lips and depth.
var river := Vector2(110.0, 134.0)
var cut := Vector2(30.0, 38.0)
var cut_depth: float = 4.0
## The layout maps cover the map and the city round it.
var mask_rect := Rect2(-60.0, -45.0, 360.0, 245.0)
var snow_material: ShaderMaterial
var plan: Plan
## Vemork's ground, kept as a child for its footprints and its snowfall only.
var snow: Node3D

func build() -> void:
	_b = sim.data.get("bocaWorld", {})
	_h = {}
	map_size = Vector2(float(sim.data.width), float(sim.data.height)) / 32.0
	river = Vector2(float(_b.get("river", [110.0, 134.0])[0]), float(_b.get("river", [110.0, 134.0])[1]))
	cut = Vector2(float(_b.get("cut", [30.0, 38.0])[0]), float(_b.get("cut", [30.0, 38.0])[1]))
	cut_depth = float(_b.get("cutDepth", 4.0))
	plan = Plan.new(sim.data)
	_build_snow_material()
	_build_land()
	_build_cutting()
	_build_banks()
	_build_kerbs()
	_build_ruts()
	_build_water()
	_build_mist()
	snow = SnowGround.new()
	snow.name = "Snow"
	snow.sim = sim
	snow.map_size = map_size
	add_child(snow)
	snow._build_prints()
	# boot prints as violet hollows, a little larger than the plateau's: they must read from the high camera
	snow.print_scale = 1.3
	(snow.get_node("Footprints") as MultiMeshInstance3D).material_override.set_shader_parameter("snow_shadow", Color(0.34, 0.35, 0.56))
	snow._build_snowfall()
	# wet flakes, a little bigger than the plateau's dry snow, white against the dusk
	snow._fall_mat.set_shader_parameter("flake_size", 0.085)
	snow._fall_mat.set_shader_parameter("strength", 0.85)

func update(dt: float, paused: bool) -> void:
	super.update(dt, paused)
	if snow != null: snow.update(dt, paused)

# ------------------------------------------------------------------------------------------------ the streets
## The carriageways (metres): where the setts are, under slush or under snow. East-west streets run out past the map
## to the city round it.
func _roads() -> Array[Rect2]:
	var W := map_size.x
	var out: Array[Rect2] = []
	var x0 := mask_rect.position.x
	var x1 := mask_rect.end.x
	for z: Vector2 in [_kerbed("northSt", 1.8, 1.4), _kerbed("southSt", 1.4, 1.6), _kerbed("crossSt", 1.4, 1.4)]:
		out.append(Rect2(x0, z.x, x1 - x0, z.y - z.x))
	var avenue := _pair("avenue", Vector2(100.0, 105.0))
	var quay := _pair("quay", Vector2(105.0, 110.0))
	out.append(Rect2(x0, avenue.x, x1 - x0, quay.y - avenue.x))
	for key: String in ["westSt", "midSt", "eastSt"]:
		var x := _kerbed(key, 1.4, 1.4)
		out.append(Rect2(x.x, mask_rect.position.y, x.y - x.x, avenue.x - mask_rect.position.y))
	var alley := _pair("alley", Vector2(80.0, 84.0))
	out.append(Rect2(alley.x, 46.0, alley.y - alley.x, 48.0))
	# round the map: the lane behind the north row, the streets west and east, the street behind the far bank's sheds
	out.append(Rect2(x0, -6.2, x1 - x0, 5.4))
	out.append(Rect2(-6.8, mask_rect.position.y, 5.6, river.x - mask_rect.position.y))
	out.append(Rect2(W + 1.2, mask_rect.position.y, 5.6, river.x - mask_rect.position.y))
	out.append(Rect2(x0, map_size.y + 1.2, x1 - x0, 5.6))
	for x: float in [46.0, 98.0, 150.0]:
		out.append(Rect2(x + 1.2, map_size.y, 5.6, 40.0))
	return out

func _pair(key: String, fallback: Vector2) -> Vector2:
	var v: Array = _b.get(key, [fallback.x, fallback.y])
	return Vector2(float(v[0]), float(v[1]))

## A street's carriageway between its two pavements.
func _kerbed(key: String, pave_a: float, pave_b: float) -> Vector2:
	var v := _pair(key, Vector2(0, 10))
	return Vector2(v.x + pave_a, v.y - pave_b)

# ------------------------------------------------------------------------------------------------ layout maps
func _map() -> Image:
	var img := Image.create(MASK_W, MASK_H, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	return img

func _px(r: Rect2) -> Rect2i:
	var sx := float(MASK_W) / mask_rect.size.x
	var sz := float(MASK_H) / mask_rect.size.y
	var x0 := clampi(int(round((r.position.x - mask_rect.position.x) * sx)), 0, MASK_W)
	var x1 := clampi(int(round((r.end.x - mask_rect.position.x) * sx)), 0, MASK_W)
	var y0 := clampi(int(round((r.position.y - mask_rect.position.y) * sz)), 0, MASK_H)
	var y1 := clampi(int(round((r.end.y - mask_rect.position.y) * sz)), 0, MASK_H)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))

func _fill(img: Image, r: Rect2, v: float) -> void:
	img.fill_rect(_px(r), Color(v, v, v))

## Soft edges: shrink the map and grow it back.
func _soften(img: Image, metres: float) -> ImageTexture:
	var f := clampf(metres * float(MASK_W) / mask_rect.size.x, 1.0, 64.0)
	if f > 1.5:
		img.resize(maxi(8, int(MASK_W / f)), maxi(8, int(MASK_H / f)), Image.INTERPOLATE_LANCZOS)
		img.resize(MASK_W, MASK_H, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(img)

static func _rect_of_units(box: Array) -> Rect2:
	return Rect2(float(box[0]) / 32.0, float(box[1]) / 32.0, float(box[2]) / 32.0, float(box[3]) / 32.0)

func _build_snow_material() -> void:
	var W := map_size.x
	# slush: the rules' packed snow (the full-width bands run on past the map), and the busy streets round the map
	var slush := _map()
	for box: Array in sim.data.get("snow", {}).get("packed", []):
		var r := _rect_of_units(box)
		if r.position.x <= 0.01 and r.end.x >= W - 0.01: r = Rect2(mask_rect.position.x, r.position.y, mask_rect.size.x, r.size.y)
		_fill(slush, r, 1.0)
	_fill(slush, Rect2(mask_rect.position.x, -6.2, mask_rect.size.x, 5.4), 1.0)
	_fill(slush, Rect2(-6.8, mask_rect.position.y, 5.6, river.x - mask_rect.position.y), 1.0)
	_fill(slush, Rect2(W + 1.2, mask_rect.position.y, 5.6, river.x - mask_rect.position.y), 1.0)
	_fill(slush, Rect2(mask_rect.position.x, map_size.y + 1.2, mask_rect.size.x, 5.6), 1.0)
	# the rails: the railway down the cutting, the tram tracks
	var rails := _map()
	for track: Array in sim.data.get("tracks", []):
		var a := Vector2(float(track[0][0]), float(track[0][1])) / 32.0
		var b := Vector2(float(track[1][0]), float(track[1][1])) / 32.0
		if absf(a.y - b.y) < 0.01:
			var xa := mask_rect.position.x if minf(a.x, b.x) <= 0.01 else minf(a.x, b.x)
			var xb := mask_rect.end.x if maxf(a.x, b.x) >= W - 0.01 else maxf(a.x, b.x)
			for dz: float in [-0.72, 0.72]: _fill(rails, Rect2(xa, a.y + dz - 0.22, xb - xa, 0.44), 1.0)
		else:
			for dx: float in [-0.72, 0.72]: _fill(rails, Rect2(a.x + dx - 0.22, minf(a.y, b.y), 0.44, absf(b.y - a.y)), 1.0)
	# the foot of the walls: every building and wall, the city round the map, with the patios inside the blocks open
	var occl := _map()
	for o: Dictionary in sim.data.get("obstacles", []):
		if str(o.get("kind", "")) in ["building", "wall"]:
			_fill(occl, _rect_of_units([o.x, o.y, o.w, o.h]), 1.0)
	for r: Rect2 in plan.outer_blocks: _fill(occl, r, 1.0)
	for r: Rect2 in plan.patios: _fill(occl, r, 0.0)
	var road := _map()
	for r: Rect2 in _roads(): _fill(road, r, 1.0)
	snow_material = ShaderMaterial.new()
	snow_material.shader = BocaGroundShader
	snow_material.set_shader_parameter("snow_tex", load(SNOW_TEX + "snow_a.png"))
	snow_material.set_shader_parameter("snow_nrm", load(SNOW_TEX + "snow_n.png"))
	snow_material.set_shader_parameter("packed_tex", load(BOCA_TEX + "slush_a.png"))
	snow_material.set_shader_parameter("setts_tex", load(TEX + "setts_a.png"))
	snow_material.set_shader_parameter("setts_nrm", load(TEX + "setts_n.png"))
	snow_material.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	snow_material.set_shader_parameter("slush_tex", _soften(slush, 1.2))
	snow_material.set_shader_parameter("rails_tex", _soften(rails, 0.5))
	snow_material.set_shader_parameter("occl_tex", _soften(occl, 1.6))
	snow_material.set_shader_parameter("road_tex", _soften(road, 0.4))
	snow_material.set_shader_parameter("mask_rect", Vector4(mask_rect.position.x, mask_rect.position.y, 1.0 / mask_rect.size.x, 1.0 / mask_rect.size.y))
	snow_material.set_shader_parameter("map_rect", Vector4(-56.0, -40.0, map_size.x + 56.0, map_size.y + 40.0))
	snow_material.set_shader_parameter("haze_color", HAZE)
	snow_material.set_shader_parameter("snow_tint", Color(0.89, 0.88, 0.93))

# ------------------------------------------------------------------------------------------------ the land
## Flat snowy ground at y = 0 in pieces about 30 m across (so no piece is lit by more lamps than the renderer allows),
## with the cutting and the river left open: north of the cutting, between the cutting and the river, the far bank.
func _build_land() -> void:
	# 30 m pieces where the real lamps and fires are (no piece lit by more of them than the renderer takes), bigger
	# ones in the blocks' band between the streets, big ones beyond the map
	var fine: Array[float] = [-150.0, -30.0]
	var x := 0.0
	while x < map_size.x:
		fine.append(x)
		x += 30.0
	fine.append_array([map_size.x, map_size.x + 30.0, map_size.x + 150.0])
	var coarse: Array[float] = [-150.0, -30.0, 0.0, 60.0, 120.0, 180.0, map_size.x, map_size.x + 150.0]
	var wide: Array[float] = [-150.0, 0.0, 120.0, map_size.x, map_size.x + 150.0]
	var bands: Array = [[Vector2(-100.0, 0.0), wide], [Vector2(0.0, cut.x), fine], [Vector2(cut.y, 70.0), coarse], [Vector2(70.0, river.x), fine],
		[Vector2(river.y, map_size.y), coarse], [Vector2(map_size.y, map_size.y + 100.0), wide]]
	var count := 0
	for entry: Array in bands:
		var band: Vector2 = entry[0]
		var xs: Array[float] = entry[1]
		for i: int in range(xs.size() - 1):
			var cell := Rect2(xs[i], band.x, xs[i + 1] - xs[i], band.y - band.x)
			var mesh := PlaneMesh.new()
			mesh.size = cell.size
			var node := MeshInstance3D.new()
			node.name = "Land%d" % count
			node.mesh = mesh
			node.material_override = snow_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = Vector3(cell.get_center().x, 0.0, cell.get_center().y)
			node.set_meta("no_batch", true)
			add_child(node)
			count += 1

## The railway cutting: brick retaining walls down to its floor of ballast, the track along it, snow on the sleepers.
func _build_cutting() -> void:
	var brick := StandardMaterial3D.new()
	brick.albedo_texture = load(STRUCT + "brick_a.png")
	brick.normal_enabled = true
	brick.normal_texture = load(STRUCT + "brick_n.png")
	brick.vertex_color_use_as_albedo = true
	brick.roughness = 0.9
	brick.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var ballast := StandardMaterial3D.new()
	ballast.albedo_texture = load(TEX + "cinder_a.png")
	ballast.normal_enabled = true
	ballast.normal_texture = load(TEX + "cinder_n.png")
	ballast.vertex_color_use_as_albedo = true
	ballast.roughness = 0.95
	ballast.uv1_scale = Vector3(0.5, 0.5, 1.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.31, 0.3)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var mats := {"wall": brick, "floor": ballast, "rail": steel}
	var x0 := -60.0
	var x1 := map_size.x + 60.0
	var piece := 60.0
	var x := x0
	while x < x1:
		var k := Kit.new()
		var xa := x
		var xb := minf(x + piece, x1)
		var lo := Color(0.35, 0.33, 0.33)
		var hi := Color(0.78, 0.74, 0.72)
		# the north wall faces south into the cutting, the south wall north
		k.quad_m("wall", Vector3(xa, -cut_depth, cut.x), Vector3(xb, -cut_depth, cut.x), Vector3(xb, 0.0, cut.x), Vector3(xa, 0.0, cut.x), Vector2(xa * 0.39, 0.0), lo, hi)
		k.quad_m("wall", Vector3(xb, -cut_depth, cut.y), Vector3(xa, -cut_depth, cut.y), Vector3(xa, 0.0, cut.y), Vector3(xb, 0.0, cut.y), Vector2(xa * 0.39, 0.0), lo, hi)
		# copings along the lips
		for z: float in [cut.x - 0.25, cut.y + 0.25]:
			k.box("wall", Vector3((xa + xb) * 0.5, 0.06, z), Vector3(xb - xa, 0.12, 0.5), Color(0.6, 0.58, 0.56), Color(0.86, 0.86, 0.88))
		k.quad_m("floor", Vector3(xa, -cut_depth, cut.y), Vector3(xb, -cut_depth, cut.y), Vector3(xb, -cut_depth, cut.x), Vector3(xa, -cut_depth, cut.x), Vector2.ZERO, Color(0.55, 0.55, 0.58), Color(0.62, 0.62, 0.66))
		var rail_z: float = float(_b.get("railZ", (cut.x + cut.y) * 0.5))
		for dz: float in [-0.72, 0.72]:
			k.box("rail", Vector3((xa + xb) * 0.5, -cut_depth + 0.12, rail_z + dz), Vector3(xb - xa, 0.08, 0.08), Color(0.5, 0.5, 0.5), Color(0.8, 0.8, 0.8))
		var s := xa
		while s < xb:
			k.box("floor", Vector3(s + 0.3, -cut_depth + 0.05, rail_z), Vector3(0.24, 0.1, 2.3), Color(0.35, 0.3, 0.26), Color(0.5, 0.45, 0.4))
			s += 0.7
		k.commit(self, mats, "Cutting", true)
		x = xb

## The quay walls: wherever the mission has water, its edges against the land are dressed granite walls down into the
## river (greener toward the waterline). Laid from the water rectangles and the water-closed passages, merged.
func _build_banks() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load(TEX + "setts_a.png")
	stone.normal_enabled = true
	stone.normal_texture = load(TEX + "setts_n.png")
	stone.normal_scale = 1.2
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 0.62
	stone.uv1_scale = Vector3(0.36, 0.5, 1.0)
	stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var materials := {"wall": stone}
	var band := _water_band()
	var bottom := WATER_Y - 2.2
	var runs: Array = [
		# left end -> right end of each face as seen from the water: the north bank faces south, the far bank north
		[Vector3(-60.0, 0, band.position.y), Vector3(map_size.x + 60.0, 0, band.position.y)],
		[Vector3(map_size.x + 60.0, 0, band.end.y), Vector3(-60.0, 0, band.end.y)],
	]
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var length := a.distance_to(b)
		var pieces := maxi(1, int(ceil(length / 60.0)))
		for k: int in range(pieces):
			var kit := Kit.new()
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var weed := Color(0.34, 0.38, 0.30)
			var wet := Color(0.40, 0.42, 0.43)
			var dry := Color(0.78, 0.78, 0.78)
			kit.quad_m("wall", Vector3(p0.x, bottom, p0.z), Vector3(p1.x, bottom, p1.z), Vector3(p1.x, WATER_Y + 0.35, p1.z), Vector3(p0.x, WATER_Y + 0.35, p0.z), Vector2(k * 0.37, 0), Color(0.12, 0.13, 0.11), weed)
			kit.quad_m("wall", Vector3(p0.x, WATER_Y + 0.35, p0.z), Vector3(p1.x, WATER_Y + 0.35, p1.z), Vector3(p1.x, WATER_Y + 1.25, p1.z), Vector3(p0.x, WATER_Y + 1.25, p0.z), Vector2(k * 0.37, -0.35), weed, wet)
			kit.quad_m("wall", Vector3(p0.x, WATER_Y + 1.25, p0.z), Vector3(p1.x, WATER_Y + 1.25, p1.z), Vector3(p1.x, -0.12, p1.z), Vector3(p0.x, -0.12, p0.z), Vector2(k * 0.37, -0.7), wet, dry)
			kit.commit(self, materials, "QuayWall", false)

## Granite kerbs between the pavements and the carriageways, broken where the streets cross; snow along their tops.
func _build_kerbs() -> void:
	var m := ShaderMaterial.new()
	m.shader = SurfaceShader
	m.set_shader_parameter("albedo_tex", load(STRUCT + "stone_a.png"))
	m.set_shader_parameter("normal_tex", load(STRUCT + "stone_n.png"))
	m.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("roughness", 0.85)
	m.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	var snow_m := ShaderMaterial.new()
	snow_m.shader = SnowLayerShader
	snow_m.set_shader_parameter("snow_tex", load(SNOW_TEX + "snow_a.png"))
	snow_m.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	var mats := {"kerb": m, Snow.KEY: snow_m}
	var r := RandomNumberGenerator.new()
	r.seed = 19580712
	var W := map_size.x
	# the gaps where the north-south streets cross (x) and the east-west ones (z)
	var gaps_x: Array[Vector2] = [_pair("westSt", Vector2(50, 56)), _pair("alley", Vector2(80, 84)), _pair("midSt", Vector2(120, 126)), _pair("eastSt", Vector2(172, 178)), Vector2(-8.0, 0.0), Vector2(W, W + 8.0)]
	var gaps_z: Array[Vector2] = [_pair("southSt", Vector2(38, 46)), _pair("crossSt", Vector2(64, 70)), _pair("plaza", Vector2(94, 100))]
	var lines: Array = []
	var north := _kerbed("northSt", 1.8, 1.4)
	# [along x, where, from, to, gaps, which side the carriageway is (+1 / -1)]
	lines.append([true, north.x, -8.0, W + 8.0, [], 1.0])
	var south := _kerbed("southSt", 1.4, 1.6)
	lines.append([true, south.y, -8.0, W + 8.0, gaps_x, -1.0])
	var cross := _kerbed("crossSt", 1.4, 1.4)
	lines.append([true, cross.x, -8.0, W + 8.0, gaps_x, 1.0])
	lines.append([true, cross.y, -8.0, W + 8.0, gaps_x, -1.0])
	var avenue := _pair("avenue", Vector2(100, 105))
	lines.append([true, avenue.x, -60.0, W + 60.0, gaps_x, 1.0])
	for key: String in ["westSt", "midSt", "eastSt"]:
		var x := _kerbed(key, 1.4, 1.4)
		lines.append([false, x.x, _pair("southSt", Vector2(38, 46)).y, _pair("plaza", Vector2(94, 100)).x, gaps_z, 1.0])
		lines.append([false, x.y, _pair("southSt", Vector2(38, 46)).y, _pair("plaza", Vector2(94, 100)).x, gaps_z, -1.0])
	var k := Kit.new()
	var count := 0
	for line: Array in lines:
		var along_x: bool = line[0]
		var at: float = line[1]
		var spans := _spans(float(line[2]), float(line[3]), line[4])
		for span: Vector2 in spans:
			var a := span.x
			while a < span.y - 0.05:
				var bb := minf(a + 12.0, span.y)
				var c := (a + bb) * 0.5
				if along_x: k.box("kerb", Vector3(c, 0.07, at), Vector3(bb - a, 0.14, 0.22), Color(0.55, 0.55, 0.57), Color(0.85, 0.85, 0.86), Vector2(a * Kit.UV_M, 0.0))
				else: k.box("kerb", Vector3(at, 0.07, c), Vector3(0.22, 0.14, bb - a), Color(0.55, 0.55, 0.57), Color(0.85, 0.85, 0.86), Vector2(a * Kit.UV_M, 0.0))
				# snow on the kerb's top, and the slush the wheels threw against it banked on the road side, broken
				var road: float = line[5]
				var p0 := Vector3(a, 0.14, at) if along_x else Vector3(at, 0.14, a)
				var p1 := Vector3(bb, 0.14, at) if along_x else Vector3(at, 0.14, bb)
				Snow.ridge(k, p0, p1, Vector3.UP, 0.2, 0.05, 0.02)
				var off := (Vector3(0, 0, road) if along_x else Vector3(road, 0, 0)) * 0.36
				var s0 := a + r.randf_range(0.0, 1.5)
				while s0 < bb - 1.0:
					var s1 := minf(s0 + r.randf_range(1.5, 4.5), bb)
					if r.randf() < 0.7:
						var q0 := (Vector3(s0, 0.0, at) if along_x else Vector3(at, 0.0, s0)) + off
						var q1 := (Vector3(s1, 0.0, at) if along_x else Vector3(at, 0.0, s1)) + off
						Snow.ridge(k, q0, q1, Vector3.UP, 0.5, r.randf_range(0.1, 0.17), 0.04, r, 0.2)
					s0 = s1 + r.randf_range(0.5, 2.5)
				a = bb
				count += 1
				if count % 60 == 0:
					k.commit(self, mats, "Kerbs", true)
					k = Kit.new()
	k.commit(self, mats, "Kerbs", true)

static func _spans(a: float, b: float, gaps: Array) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(a, b)]
	for g: Vector2 in gaps:
		var next: Array[Vector2] = []
		for s: Vector2 in out:
			if g.y <= s.x or g.x >= s.y:
				next.append(s)
				continue
			if g.x > s.x: next.append(Vector2(s.x, g.x))
			if g.y < s.y: next.append(Vector2(g.y, s.y))
		out = next
	return out

## Wheel ruts in the slush of the busy streets: strips of wet track laid along their lanes.
func _build_ruts() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(BOCA_TEX + "ruts_a.png")
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.35
	m.metallic_specular = 0.6
	m.render_priority = -1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mats := {"ruts": m}
	var W := map_size.x
	var north := _kerbed("northSt", 1.8, 1.4)
	var south := _kerbed("southSt", 1.4, 1.6)
	var cross := _kerbed("crossSt", 1.4, 1.4)
	var lanes: Array = [
		[true, lerpf(north.x, north.y, 0.27), -60.0, W + 60.0], [true, lerpf(north.x, north.y, 0.73), -60.0, W + 60.0],
		[true, lerpf(south.x, south.y, 0.3), -60.0, W + 60.0], [true, lerpf(south.x, south.y, 0.72), -60.0, W + 60.0],
		[true, (cross.x + cross.y) * 0.5, -60.0, W + 60.0], [true, -3.5, -60.0, W + 60.0], [true, map_size.y + 4.0, -60.0, W + 60.0],
		[false, -4.0, -45.0, river.x - 6.0], [false, W + 4.0, -45.0, river.x - 6.0],
	]
	var r := RandomNumberGenerator.new()
	r.seed = 1958
	var k := Kit.new()
	for lane: Array in lanes:
		var along_x: bool = lane[0]
		var at: float = lane[1]
		var a: float = lane[2]
		while a < float(lane[3]) - 0.1:
			var bb := minf(a + 20.0, float(lane[3]))
			var hw := 0.95
			var y := 0.016
			var v0 := a / 3.0
			var v1 := bb / 3.0
			var c := Color(1, 1, 1, r.randf_range(0.75, 1.0))
			if along_x:
				var w0 := at + r.randf_range(-0.15, 0.15)
				k.quad4("ruts", Vector3(a, y, w0 + hw), Vector3(bb, y, w0 + hw), Vector3(bb, y, w0 - hw), Vector3(a, y, w0 - hw), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), Vector2(0, v0), c, c, c, c)
			else:
				k.quad4("ruts", Vector3(at - hw, y, bb), Vector3(at + hw, y, bb), Vector3(at + hw, y, a), Vector3(at - hw, y, a), Vector2(0, v1), Vector2(1, v1), Vector2(1, v0), Vector2(0, v0), c, c, c, c)
			a = bb
	k.commit(self, mats, "Ruts", false)

## The span of water across the map (metres): the union of the water obstacles and the water-closed passages.
func _water_band() -> Rect2:
	var band := Rect2()
	var first := true
	var items: Array = []
	for o: Dictionary in sim.data.get("obstacles", []):
		if str(o.get("kind", "")) == "water": items.append(o)
	for p: Dictionary in sim.data.get("passages", []):
		if str(p.get("closed", "")) == "water": items.append(p)
	for item: Dictionary in items:
		var r := _rect_of_units([item.x, item.y, item.w, item.h])
		band = r if first else band.merge(r)
		first = false
	if first: band = Rect2(0.0, river.x, map_size.x, river.y - river.x)
	return band

# ------------------------------------------------------------------------------------------------ water, mist
func _build_water() -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = WaterShader
	water_material.set_shader_parameter("normal_tex", load(NATURE + "water_normal.png"))
	water_material.set_shader_parameter("detail_tex", load(NATURE + "water_detail.png"))
	water_material.set_shader_parameter("water_y", WATER_Y)
	water_material.set_shader_parameter("map_rect", Vector4(0.0, 0.0, map_size.x, map_size.y))
	water_material.set_shader_parameter("flow", 0.02)
	# the blue hour in the river: the sky's lavender on the water, the far bank's snow faintly in it
	water_material.set_shader_parameter("sky_glow", Vector3(0.1, 0.1, 0.15))
	water_material.set_shader_parameter("deep_color", Color(0.025, 0.03, 0.04))
	water_material.render_priority = -1
	var band := _water_band()
	var i := 0
	var x := -150.0
	while x < map_size.x + 150.0:
		var r := Rect2(x, band.position.y, 30.0, band.size.y)
		var plane := PlaneMesh.new()
		plane.size = r.size
		plane.subdivide_width = int(r.size.x / 3.0)
		plane.subdivide_depth = int(r.size.y / 3.0)
		var node := MeshInstance3D.new()
		node.name = "Water%d" % i
		node.mesh = plane
		node.material_override = water_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(r.get_center().x, WATER_Y, r.get_center().y)
		node.set_meta("no_batch", true)
		add_child(node)
		i += 1
		x += 30.0

## River fog: thin sheets just above the water, lit from inside by the quay's lamps.
func _build_mist() -> void:
	mist_material = ShaderMaterial.new()
	mist_material.shader = MistShader
	mist_material.set_shader_parameter("noise_tex", load(NATURE + "macro_noise.png"))
	mist_material.set_shader_parameter("mist_color", Color(0.46, 0.45, 0.54))
	mist_material.set_shader_parameter("density", 0.4)
	mist_material.render_priority = 1
	var band := _water_band()
	var k := 0
	var x := -120.0
	while x < map_size.x + 120.0:
		for level: float in [WATER_Y + 0.9]:
			var plane := PlaneMesh.new()
			plane.size = Vector2(60.0, band.size.y - 0.4)
			var node := MeshInstance3D.new()
			node.name = "Mist%d" % k
			node.mesh = plane
			node.material_override = mist_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = Vector3(x + 30.0, level, band.get_center().y)
			node.set_meta("no_batch", true)
			add_child(node)
			k += 1
		x += 60.0

## The lamps the river shows: those nearest the water (the quay's row, all on the board), strongest first.
func set_lamps(all: Array) -> void:
	var band := _water_band()
	var list: Array = []
	for entry: Array in all:
		if entry.size() > 4 and not bool(entry[4]): continue
		list.append(entry)
	list.sort_custom(func(a: Array, b: Array) -> bool:
		var za: float = minf(absf((a[0] as Vector3).z - band.position.y), absf((a[0] as Vector3).z - band.end.y))
		var zb: float = minf(absf((b[0] as Vector3).z - band.position.y), absf((b[0] as Vector3).z - band.end.y))
		return za < zb)
	var lamps := PackedVector4Array()
	var colours := PackedVector4Array()
	for entry: Array in list:
		if lamps.size() >= 16: break
		var at: Vector3 = entry[0]
		var c: Color = entry[1]
		lamps.append(Vector4(at.x, at.y, at.z, float(entry[2])))
		colours.append(Vector4(c.r, c.g, c.b, float(entry[3]) if entry.size() > 3 else 1.0))
	var count := lamps.size()
	while lamps.size() < 16:
		lamps.append(Vector4(0, -100, 0, 0))
		colours.append(Vector4(0, 0, 0, 1))
	for m: ShaderMaterial in [water_material, mist_material]:
		m.set_shader_parameter("lamps", lamps)
		m.set_shader_parameter("lamp_colors", colours)
		m.set_shader_parameter("lamp_count", count)
