extends Node3D
## The ground of Vemork (Operation Gunnerside): the snow on the plateau and the ledge, trodden to a crust on the
## roads, the railway and the plant's yard; the gorge of the Mana between them, its walls dropping to the frozen river;
## the mountain rising behind the plant; spruce and pine under snow, the pine thickets you can hide in, the drifts and
## the boulders; the footprints the operatives leave, as the rules lay them; snow falling; mist in the gorge.
## Built once by world.gd in the slot the outpost's nature module fills: set `sim`, add to the tree, build().

const Nature = preload("res://scripts/three_d/nature.gd")
const GroundShader := preload("res://shaders/snow_ground.gdshader")
const RockShader := preload("res://shaders/snow_rock.gdshader")
const FoliageShader := preload("res://shaders/snow_foliage.gdshader")
const IceShader := preload("res://shaders/snow_ice.gdshader")
const FallShader := preload("res://shaders/snow_fall.gdshader")
const PrintShader := preload("res://shaders/snow_prints.gdshader")
const MistShader := preload("res://shaders/harbour_mist.gdshader")
const TEX := "res://assets/tex/snow/"
const NATURE := "res://assets/tex/nature/"
const HARBOUR := "res://assets/tex/harbour/"
## Colour the night dissolves into far outside the map.
const HAZE := Color(0.045, 0.06, 0.095)
const WORLD_MIN := Vector2(-70.0, -70.0)
const WORLD_MAX := Vector2(134.0, 124.0)
const MASK_SIZE := 512
const MAX_PRINTS := 360
const FLAKES := 1400

var sim: RefCounted
var map_size := Vector2(64.0, 52.0)
## The gorge: its two lips (z, metres), how far down the river lies, how far out each wall flares at its foot.
var gorge_n: float = 20.0
var gorge_s: float = 28.5
var depth: float = 9.0
var wall_run: float = 1.8
var _w: Dictionary = {}
var _mask_rect := Rect2(-8.0, -8.0, 80.0, 68.0)
var _mask := PackedFloat32Array()
var _ground_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _foliage_mat: ShaderMaterial
var _prints: MultiMesh
## How big a print is drawn (La Boca draws them larger, to read from its higher camera).
var print_scale: float = 1.0
var _fall_mat: ShaderMaterial
var _nature: Nature
var _macro: Texture2D

func build() -> void:
	_w = sim.data.get("snowWorld", {})
	map_size = Vector2(float(sim.data.width) / 32.0, float(sim.data.height) / 32.0)
	gorge_n = float(_w.get("gorgeN", 20.0))
	gorge_s = float(_w.get("gorgeS", 28.5))
	depth = float(_w.get("depth", 9.0))
	_macro = load(NATURE + "macro_noise.png")
	# the outpost's tree and boulder makers, borrowed (never added to the scene)
	_nature = Nature.new()
	_build_materials()
	_build_mask()
	_build_ground()
	_build_gorge()
	_build_rocks()
	_build_trees()
	_build_pines()
	_build_drifts()
	_build_prints()
	_build_snowfall()
	_build_mist()
	_nature.free()
	_nature = null
	_mask = PackedFloat32Array()

# ---------------------------------------------------------------------------------------------------------------
# Shape of the land
# ---------------------------------------------------------------------------------------------------------------
## Height of the snow surface outside the gorge (metres). Everything anyone walks on is at 0: the slopes start where
## the mines do, and outside the map the plateau rolls a little and the mountain climbs behind the plant.
func land_y(x: float, z: float) -> float:
	var h := 0.0
	var zs: float = float(_w.get("minesW", 44.0)) if x < 28.3 else (float(_w.get("minesS", 47.6)) if x < 46.8 else 47.0)
	if z > zs:
		var d := z - zs
		h += minf(d * 0.62 + d * d * 0.03, 24.0) + _noise(x * 0.09, z * 0.09) * minf(d * 0.25, 2.0)
	var out := maxf(maxf(-x, x - map_size.x), -z)
	if out > 0.0:
		h += smoothstep(0.0, 18.0, out) * (1.2 + 2.2 * _noise(x * 0.035 + 3.0, z * 0.035))
	return h

## Height of the ground under an actor (for the renderer): 0 except on a rope down the gorge, where it follows the
## wall down to the ice and up the far side.
func ground_height(x: float, z: float) -> float:
	if z <= gorge_n or z >= gorge_s:
		return 0.0
	var from_n := z - gorge_n
	var from_s := gorge_s - z
	var s := 1.0
	if from_n < wall_run: s = pow(from_n / wall_run, 1.0 / 1.6)
	elif from_s < wall_run: s = pow(from_s / wall_run, 1.0 / 1.6)
	return -depth * s

static func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 127.1 + z * 311.7) * 43758.5453, 1.0)

## Smooth value noise in 0..1.
static func _noise(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := _hash(ix, iz)
	var b := _hash(ix + 1.0, iz)
	var c := _hash(ix, iz + 1.0)
	var d := _hash(ix + 1.0, iz + 1.0)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

# ---------------------------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------------------------
func _build_materials() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GroundShader
	_ground_mat.set_shader_parameter("snow_tex", load(TEX + "snow_a.png"))
	_ground_mat.set_shader_parameter("snow_nrm", load(TEX + "snow_n.png"))
	_ground_mat.set_shader_parameter("packed_tex", load(TEX + "packed_a.png"))
	_ground_mat.set_shader_parameter("packed_nrm", load(TEX + "packed_n.png"))
	_ground_mat.set_shader_parameter("ballast_tex", load(HARBOUR + "cinder_a.png"))
	_ground_mat.set_shader_parameter("macro_tex", _macro)
	_ground_mat.set_shader_parameter("map_rect", Vector4(0.0, 0.0, map_size.x, map_size.y))
	_ground_mat.set_shader_parameter("haze_color", HAZE)
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = RockShader
	_rock_mat.set_shader_parameter("rock_tex", load(NATURE + "rock_albedo.png"))
	_rock_mat.set_shader_parameter("rock_nrm", load(NATURE + "rock_normal.png"))
	_rock_mat.set_shader_parameter("macro_tex", _macro)
	_rock_mat.set_shader_parameter("map_rect", Vector4(0.0, 0.0, map_size.x, map_size.y))
	_rock_mat.set_shader_parameter("haze_color", HAZE)
	_rock_mat.set_shader_parameter("depth_dark", depth)
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = FoliageShader
	_foliage_mat.set_shader_parameter("atlas", load(NATURE + "foliage_atlas.png"))
	_foliage_mat.set_shader_parameter("macro_tex", _macro)
	_foliage_mat.set_shader_parameter("map_rect", Vector4(0.0, 0.0, map_size.x, map_size.y))
	_foliage_mat.set_shader_parameter("haze_color", HAZE)

func _add_mesh(mesh: Mesh, material: Material, shadows: bool, label: String) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	item.mesh = mesh
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	return item

# ---------------------------------------------------------------------------------------------------------------
# Layout mask: R trodden snow, G railway ballast, B occlusion (shader snow_ground.gdshader)
# ---------------------------------------------------------------------------------------------------------------
func _build_mask() -> void:
	_mask.resize(MASK_SIZE * MASK_SIZE * 4)
	_mask.fill(0.0)
	for box: Array in sim.data.get("snow", {}).get("packed", []):
		_stamp(0, _rect_m(box), 0.35, 1.0)
	var rail_z: float = float(_w.get("railZ", 30.8))
	var fence_x: float = float(_w.get("fenceX", 28.5))
	_stamp(1, Rect2(-8.0, rail_z - 0.9, fence_x + 18.0 + 8.0, 1.8), 0.25, 1.0)
	for obstacle: Dictionary in sim.data.get("obstacles", []):
		var kind: String = str(obstacle.kind)
		if kind == "gorge": continue
		var r := _rect_m([obstacle.x, obstacle.y, obstacle.w, obstacle.h])
		_stamp(2, r.grow(0.15), 0.9 if kind in ["building", "wall"] else 0.6, 0.55 if kind in ["building", "wall"] else 0.4)
	for bush: Dictionary in sim.data.get("bushes", []):
		if str(bush.get("kind", "")) == "pines":
			_stamp(2, _rect_m([bush.x, bush.y, bush.w, bush.h]).grow(-0.3), 0.8, 0.35)
	var img := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(MASK_SIZE):
		for x: int in range(MASK_SIZE):
			var i := (y * MASK_SIZE + x) * 4
			img.set_pixel(x, y, Color(_mask[i], _mask[i + 1], _mask[i + 2], 1.0))
	var tex := ImageTexture.create_from_image(img)
	_ground_mat.set_shader_parameter("mask_tex", tex)
	_ground_mat.set_shader_parameter("mask_rect", Vector4(_mask_rect.position.x, _mask_rect.position.y, 1.0 / _mask_rect.size.x, 1.0 / _mask_rect.size.y))

static func _rect_m(box: Array) -> Rect2:
	return Rect2(float(box[0]) / 32.0, float(box[1]) / 32.0, float(box[2]) / 32.0, float(box[3]) / 32.0)

## Max-blends a soft box into one channel: `strength` inside, fading to nothing `fall` metres outside.
func _stamp(ch: int, r: Rect2, fall: float, strength: float) -> void:
	var scale := float(MASK_SIZE) / _mask_rect.size.x
	var x0 := clampi(int((r.position.x - fall - _mask_rect.position.x) * scale), 0, MASK_SIZE - 1)
	var x1 := clampi(int((r.end.x + fall - _mask_rect.position.x) * scale) + 1, 0, MASK_SIZE - 1)
	var y0 := clampi(int((r.position.y - fall - _mask_rect.position.y) * MASK_SIZE / _mask_rect.size.y), 0, MASK_SIZE - 1)
	var y1 := clampi(int((r.end.y + fall - _mask_rect.position.y) * MASK_SIZE / _mask_rect.size.y) + 1, 0, MASK_SIZE - 1)
	for y: int in range(y0, y1 + 1):
		var wz := _mask_rect.position.y + (float(y) + 0.5) * _mask_rect.size.y / MASK_SIZE
		for x: int in range(x0, x1 + 1):
			var wx := _mask_rect.position.x + (float(x) + 0.5) / scale
			var dx := maxf(maxf(r.position.x - wx, wx - r.end.x), 0.0)
			var dz := maxf(maxf(r.position.y - wz, wz - r.end.y), 0.0)
			var d := sqrt(dx * dx + dz * dz)
			var v := strength * (1.0 - smoothstep(0.0, maxf(fall, 0.001), d))
			var i := (y * MASK_SIZE + x) * 4 + ch
			if v > _mask[i]: _mask[i] = v

# ---------------------------------------------------------------------------------------------------------------
# The ground: two sheets, the plateau north of the gorge and the ledge south of it
# ---------------------------------------------------------------------------------------------------------------
## Sample positions along one axis: one metre apart over the map, wider and wider beyond it.
static func _axis(lo: float, hi: float, fine_lo: float, fine_hi: float, step: float) -> Array[float]:
	var out: Array[float] = []
	var v := lo
	while v < fine_lo:
		out.append(v)
		var gap := fine_lo - v
		v += clampf(gap * 0.35, step, 8.0)
	v = fine_lo
	while v < fine_hi - 0.001:
		out.append(v)
		v += step
	out.append(fine_hi)
	v = fine_hi
	while v < hi:
		var gap := v - fine_hi
		v = minf(hi, v + clampf(gap * 0.35 + step, step, 8.0))
		out.append(v)
	return out

func _build_ground() -> void:
	var xs := _axis(WORLD_MIN.x, WORLD_MAX.x, -6.0, map_size.x + 6.0, 1.0)
	var north := _axis(WORLD_MIN.y, gorge_n, -6.0, gorge_n, 1.0)
	var south := _axis(gorge_s, WORLD_MAX.y, gorge_s, map_size.y + 8.0, 1.0)
	# in pieces about 16 m across, so that no piece is lit by more of the plant's lamps than the renderer allows
	var cuts_x: Array[float] = [10.0, 26.0, 42.0, 58.0]
	_chunks(xs, north, cuts_x, [8.0], "GroundNorth", false)
	_chunks(xs, south, cuts_x, [36.0, 44.0], "GroundSouth", true)

func _chunks(xs: Array[float], zs: Array[float], cuts_x: Array[float], cuts_z: Array[float], label: String, shadows: bool) -> void:
	var col_ranges := _ranges(xs, cuts_x)
	var row_ranges := _ranges(zs, cuts_z)
	for r: Vector2i in row_ranges:
		for c: Vector2i in col_ranges:
			var sub_x: Array[float] = xs.slice(c.x, c.y + 1)
			var sub_z: Array[float] = zs.slice(r.x, r.y + 1)
			if sub_x.size() < 2 or sub_z.size() < 2: continue
			_add_mesh(_sheet(sub_x, sub_z), _ground_mat, shadows, "%s_%d_%d" % [label, c.x, r.x])

## Index ranges [first, last] of the samples between the cuts (neighbouring ranges share their edge sample).
static func _ranges(values: Array[float], cuts: Array[float]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := 0
	for cut: float in cuts:
		var i := start
		while i < values.size() - 1 and values[i] < cut: i += 1
		if i > start:
			out.append(Vector2i(start, i))
			start = i
	out.append(Vector2i(start, values.size() - 1))
	return out

func _sheet(xs: Array[float], zs: Array[float]) -> ArrayMesh:
	var b := Nature.Buf.new()
	var cols := xs.size()
	for z: float in zs:
		for x: float in xs:
			var y := land_y(x, z)
			var e := 0.3
			var nx := land_y(x - e, z) - land_y(x + e, z)
			var nz := land_y(x, z - e) - land_y(x, z + e)
			b.add(Vector3(x, y, z), Vector3(nx, 2.0 * e, nz).normalized(), Vector2(x, z), Color.WHITE)
	for r: int in range(zs.size() - 1):
		for c: int in range(cols - 1):
			var i := r * cols + c
			b.tri(i, i + 1, i + cols)
			b.tri(i + 1, i + cols + 1, i + cols)
	return b.mesh()

# ---------------------------------------------------------------------------------------------------------------
# The gorge
# ---------------------------------------------------------------------------------------------------------------
func _build_gorge() -> void:
	var xs := _axis(WORLD_MIN.x, WORLD_MAX.x, -6.0, map_size.x + 6.0, 0.5)
	var rows: Array[float] = [0.0, 0.025, 0.07, 0.16, 0.3, 0.46, 0.62, 0.76, 0.88, 0.96, 1.0]
	var b := Nature.Buf.new()
	for side: int in range(2):
		var base := b.v.size()
		for s: float in rows:
			for x: float in xs:
				var bulge := (_noise(x * 0.55 + float(side) * 9.0, s * 3.0) - 0.5) * 1.1 + (_noise(x * 1.7, s * 7.0 + float(side)) - 0.5) * 0.35
				var run := wall_run * pow(s, 1.6) + bulge * sin(PI * s) * 0.9
				var y := -depth * s + (_noise(x * 0.8, 5.0 + float(side)) - 0.5) * 0.6 * sin(PI * s)
				var z := gorge_n + run if side == 0 else gorge_s - run
				b.add(Vector3(x, y, z), Vector3.UP, Vector2(x, y), Color.WHITE)
		var cols := xs.size()
		for r: int in range(rows.size() - 1):
			for c: int in range(cols - 1):
				var i := base + r * cols + c
				if side == 0:
					b.tri(i, i + 1, i + cols)
					b.tri(i + 1, i + cols + 1, i + cols)
				else:
					b.tri(i, i + cols, i + 1)
					b.tri(i + 1, i + cols, i + cols + 1)
	# the floor between the two walls: snow banks along the foot, the river between them
	var floor_n := gorge_n + wall_run
	var floor_s := gorge_s - wall_run
	var base := b.v.size()
	var zs: Array[float] = []
	var steps := 8
	for k: int in range(steps + 1): zs.append(lerpf(floor_n, floor_s, float(k) / float(steps)))
	for z: float in zs:
		for x: float in xs:
			var bank := 1.0 - smoothstep(0.0, 1.3, minf(z - floor_n, floor_s - z))
			b.add(Vector3(x, -depth + bank * 0.45 + _noise(x * 0.6, z * 0.6) * 0.08, z), Vector3.UP, Vector2(x, z), Color.WHITE)
	var cols := xs.size()
	for r: int in range(zs.size() - 1):
		for c: int in range(cols - 1):
			var i := base + r * cols + c
			b.tri(i, i + 1, i + cols)
			b.tri(i + 1, i + cols + 1, i + cols)
	_smooth_normals(b)
	_add_mesh(b.mesh(), _rock_mat, true, "Gorge")
	# the ice
	var ice := PlaneMesh.new()
	ice.size = Vector2(WORLD_MAX.x - WORLD_MIN.x, floor_s - floor_n - 1.2)
	var ice_mat := ShaderMaterial.new()
	ice_mat.shader = IceShader
	ice_mat.set_shader_parameter("ice_tex", load(TEX + "ice_a.png"))
	ice_mat.set_shader_parameter("ice_nrm", load(TEX + "ice_n.png"))
	ice_mat.set_shader_parameter("macro_tex", _macro)
	ice_mat.set_shader_parameter("center_z", (gorge_n + gorge_s) * 0.5)
	var river := _add_mesh(ice, ice_mat, false, "River")
	river.position = Vector3((WORLD_MIN.x + WORLD_MAX.x) * 0.5, -depth + 0.06, (gorge_n + gorge_s) * 0.5)

## Normals from the triangles around each vertex (area weighted).
static func _smooth_normals(b: Nature.Buf) -> void:
	var acc := PackedVector3Array()
	acc.resize(b.v.size())
	for t: int in range(0, b.idx.size(), 3):
		var i0 := b.idx[t]
		var i1 := b.idx[t + 1]
		var i2 := b.idx[t + 2]
		var nrm := (b.v[i2] - b.v[i0]).cross(b.v[i1] - b.v[i0])
		acc[i0] += nrm
		acc[i1] += nrm
		acc[i2] += nrm
	for i: int in range(acc.size()):
		b.n[i] = acc[i].normalized() if acc[i].length_squared() > 1e-12 else Vector3.UP

# ---------------------------------------------------------------------------------------------------------------
# Boulders, trees, the pine thickets, the drifts
# ---------------------------------------------------------------------------------------------------------------
func _build_rocks() -> void:
	var b := Nature.Buf.new()
	var shapes: Array = [_nature._rock_shape(71, 2), _nature._rock_shape(72, 2), _nature._rock_shape(73, 2)]
	var i := 0
	for obstacle: Dictionary in sim.data.get("obstacles", []):
		if str(obstacle.kind) != "rock" or str(obstacle.id) == "penstocks": continue
		var r := _rect_m([obstacle.x, obstacle.y, obstacle.w, obstacle.h])
		var c := r.get_center()
		var shape: Nature.Buf = shapes[i % shapes.size()]
		var xf := Transform3D(Basis(Vector3.UP, float(i) * 1.9) * Basis.from_scale(Vector3(r.size.x * 0.56, 1.35 + 0.25 * float(i % 3), r.size.y * 0.56)), Vector3(c.x, -0.15, c.y))
		b.merge(shape, xf)
		# a smaller stone or two at its foot
		var small: Nature.Buf = shapes[(i + 1) % shapes.size()]
		b.merge(small, Transform3D(Basis(Vector3.UP, float(i) * 0.7) * Basis.from_scale(Vector3(0.45, 0.35, 0.4)), Vector3(c.x + r.size.x * 0.55, -0.05, c.y + r.size.y * 0.3)))
		i += 1
	if b.v.is_empty(): return
	_add_mesh(b.mesh(), _rock_mat, true, "Boulders")

## Trees outside the playable ground: the forest on the plateau beyond the map, along the far side of the gorge, and
## thinning out up the mountain. They grow taller the further they stand from the map, so none hides anyone.
func _build_trees() -> void:
	var variants: Array = [
		_nature._make_spruce(141, 6.0, 1.55, 8, 0.95, Vector2(6, 4), true),
		_nature._make_spruce(142, 4.2, 1.35, 7, 0.40, Vector2(6, 4), true),
		_nature._make_pine(143, 7.0),
		_nature._make_spruce(147, 8.0, 2.0, 4, 1.6, Vector2(4, 3), false),
	]
	var heights: Array[float] = [6.0, 4.2, 7.0, 8.0]
	var lists: Array = [[], [], [], []]
	var r := RandomNumberGenerator.new()
	r.seed = 19430227
	var placed := 0
	var tries := 0
	while placed < 900 and tries < 9000:
		tries += 1
		var x := r.randf_range(-40.0, map_size.x + 40.0)
		var z := r.randf_range(-40.0, map_size.y + 36.0)
		var out := maxf(maxf(-x, x - map_size.x), maxf(-z, z - map_size.y))
		if z > gorge_n - 1.0 and z < gorge_s + 1.0: continue          # not in the gorge
		if out < 1.5:
			# on the map only on the mined slopes, and sparsely
			var zs: float = float(_w.get("minesW", 44.0)) if x < 28.3 else 99.0
			if z < zs + 2.5 or r.randf() > 0.25: continue
		var density := smoothstep(1.0, 10.0, out) * 0.85 + 0.15
		if z > map_size.y + 4.0: density *= 0.55                   # the mountain: thinner
		if r.randf() > density: continue
		var h := lerpf(2.6, 8.5, smoothstep(1.0, 16.0, out)) * r.randf_range(0.8, 1.15)
		var kind := 3 if out > 18.0 else (0 if h > 4.6 else 1)
		lists[kind].append({"p": Vector3(x, land_y(x, z) - 0.1, z), "h": h, "yaw": r.randf() * TAU, "tint": _tree_tint(r)})
		placed += 1
	for kind: int in range(variants.size()):
		var list: Array = lists[kind]
		if list.is_empty(): continue
		_multi(variants[kind], heights[kind], list, "Trees%d" % kind, kind < 3)

func _tree_tint(r: RandomNumberGenerator) -> Color:
	var v := r.randf_range(0.82, 1.08)
	return Color(v * r.randf_range(0.95, 1.03), v, v * r.randf_range(0.95, 1.05))

func _multi(buf: Nature.Buf, unit_h: float, list: Array, label: String, shadows: bool) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = buf.mesh()
	multi.instance_count = list.size()
	for i: int in range(list.size()):
		var t: Dictionary = list[i]
		var s: float = float(t.h) / unit_h
		multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(t.yaw)) * Basis.from_scale(Vector3(s, s, s)), t.p))
		multi.set_instance_color(i, t.tint)
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	node.material_override = _foliage_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## A pine thicket you can hide in: a handful of young spruces under snow, no taller than a man and a half, close
## enough that a crouching man disappears among them, on a low mound of snow.
func _build_pines() -> void:
	var young: Nature.Buf = _nature._make_spruce(151, 2.0, 0.85, 6, 0.15, Vector2(5, 3), true)
	var list: Array = []
	var mound := Nature.Buf.new()
	var r := RandomNumberGenerator.new()
	r.seed = 1943
	for bush: Dictionary in sim.data.get("bushes", []):
		if str(bush.get("kind", "")) != "pines": continue
		var rect := _rect_m([bush.x, bush.y, bush.w, bush.h])
		var count := clampi(int(round(rect.get_area() / 1.6)), 3, 9)
		var golden := PI * (3.0 - sqrt(5.0))
		for k: int in range(count):
			var t := sqrt((float(k) + 0.5) / float(count))
			var a := golden * float(k) + r.randf() * 0.5
			var p := rect.get_center() + Vector2(cos(a), sin(a)) * t * rect.size * 0.42
			list.append({"p": Vector3(p.x, 0.0, p.y), "h": r.randf_range(1.45, 2.15), "yaw": r.randf() * TAU, "tint": _tree_tint(r)})
		_dome(mound, rect.grow(0.2), 0.32)
	if not list.is_empty(): _multi(young, 2.0, list, "PineThickets", true)
	if not mound.v.is_empty(): _add_mesh(mound.mesh(), _ground_mat, false, "ThicketMounds")  # the ground's own snow: no seam at the rim

func _build_drifts() -> void:
	var b := Nature.Buf.new()
	for bush: Dictionary in sim.data.get("bushes", []):
		if str(bush.get("kind", "")) != "drift": continue
		_dome(b, _rect_m([bush.x, bush.y, bush.w, bush.h]).grow(0.25), 0.95)
	if b.v.is_empty(): return
	_add_mesh(b.mesh(), _rock_mat, true, "Drifts")

## A low snow dome over a rectangle (a drift, the mound under a thicket): a smooth bump, `height` metres at its crown.
func _dome(b: Nature.Buf, r: Rect2, height: float) -> void:
	var n := 10
	var base := b.v.size()
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var u := float(i) / float(n) * 2.0 - 1.0
			var v := float(j) / float(n) * 2.0 - 1.0
			var d := clampf(sqrt(u * u + v * v), 0.0, 1.0)
			var y := height * pow(maxf(0.0, 1.0 - d * d), 1.3) * (0.85 + 0.3 * _noise(r.position.x + u * 3.0, r.position.y + v * 3.0)) - 0.04
			b.add(Vector3(r.get_center().x + u * r.size.x * 0.5, y, r.get_center().y + v * r.size.y * 0.5), Vector3.UP, Vector2(u, v), Color.WHITE)
	for j: int in range(n):
		for i: int in range(n):
			var k := base + j * (n + 1) + i
			b.tri(k, k + 1, k + n + 1)
			b.tri(k + 1, k + n + 2, k + n + 1)
	_dome_normals(b, base, n)

static func _dome_normals(b: Nature.Buf, base: int, n: int) -> void:
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var k := base + j * (n + 1) + i
			var l := base + j * (n + 1) + maxi(i - 1, 0)
			var rr := base + j * (n + 1) + mini(i + 1, n)
			var d := base + maxi(j - 1, 0) * (n + 1) + i
			var u := base + mini(j + 1, n) * (n + 1) + i
			var nrm := (b.v[u] - b.v[d]).cross(b.v[rr] - b.v[l])
			b.n[k] = nrm.normalized() if nrm.length_squared() > 1e-12 else Vector3.UP

# ---------------------------------------------------------------------------------------------------------------
# Footprints (the rules' snow tracks), snowfall, mist in the gorge
# ---------------------------------------------------------------------------------------------------------------
func _build_prints() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = PrintShader
	mat.set_shader_parameter("prints_tex", load(TEX + "prints.png"))
	mat.render_priority = -1
	_prints = MultiMesh.new()
	_prints.transform_format = MultiMesh.TRANSFORM_3D
	_prints.use_colors = true
	_prints.use_custom_data = true
	_prints.mesh = plane
	_prints.instance_count = MAX_PRINTS
	_prints.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "Footprints"
	node.multimesh = _prints
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-10, -1, -10), Vector3(map_size.x + 20, 2, map_size.y + 20))
	add_child(node)

func _sync_prints() -> void:
	if _prints == null: return
	var live: Array = sim.live_tracks()
	var ttl: float = float(sim.data.get("snow", {}).get("ttl", 50.0))
	var count := mini(live.size(), MAX_PRINTS)
	var first := live.size() - count
	for i: int in range(count):
		var p: Dictionary = live[first + i]
		var a := float(p.angle)
		var yaw := atan2(-cos(a), -sin(a))
		var ski := str(p.get("kind", "boot")) == "ski"
		var size := (Vector3(0.62, 1.0, 0.62) if not ski else Vector3(0.62, 1.0, 0.82)) * Vector3(print_scale, 1.0, print_scale)
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), Vector3(float(p.x) / 32.0, 0.012, float(p.y) / 32.0))
		_prints.set_instance_transform(i, xf)
		var age := (float(sim.time) - float(p.t)) / ttl
		_prints.set_instance_color(i, Color(1, 1, 1, clampf(1.0 - age * age, 0.0, 1.0) * 0.9))
		_prints.set_instance_custom_data(i, Color(1.0 if ski else 0.0, 0, 0, 0))
	_prints.visible_instance_count = count

func _build_snowfall() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = FallShader
	_fall_mat.render_priority = 8
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = quad
	multi.instance_count = FLAKES
	var r := RandomNumberGenerator.new()
	r.seed = 280243
	for i: int in range(FLAKES):
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(r.randf() * 48.0, r.randf() * 18.0, r.randf() * 48.0)))
	var node := MultiMeshInstance3D.new()
	node.name = "Snowfall"
	node.multimesh = multi
	node.material_override = _fall_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
	add_child(node)

func _build_mist() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = MistShader
	mat.set_shader_parameter("noise_tex", _macro)
	mat.set_shader_parameter("mist_color", Color(0.10, 0.13, 0.19))
	mat.set_shader_parameter("density", 0.3)
	mat.render_priority = 2
	for level: float in [-6.5, -3.5]:
		var plane := PlaneMesh.new()
		plane.size = Vector2(WORLD_MAX.x - WORLD_MIN.x, gorge_s - gorge_n - 0.6)
		var m := _add_mesh(plane, mat, false, "GorgeMist")
		m.position = Vector3((WORLD_MIN.x + WORLD_MAX.x) * 0.5, level, (gorge_n + gorge_s) * 0.5)

## The lamps of the plant, for the mist (the same list the harbour's mist takes).
func set_lamps(all: Array) -> void:
	var lamps := PackedVector4Array()
	var colours := PackedVector4Array()
	for entry: Array in all:
		if lamps.size() >= 16: break
		var at: Vector3 = entry[0]
		var col: Color = entry[1]
		lamps.append(Vector4(at.x, at.y, at.z, float(entry[2])))
		colours.append(Vector4(col.r, col.g, col.b, 1.0))
	for child: Node in get_children():
		if child.name.begins_with("GorgeMist"):
			var m := (child as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("lamps", lamps)
			m.set_shader_parameter("lamp_colors", colours)
			m.set_shader_parameter("lamp_count", lamps.size())
			break

## Called every frame from world.update_visuals (dt is real time; paused = command mode).
func update(_dt: float, _paused: bool) -> void:
	_sync_prints()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and _fall_mat != null:
		# the snow box follows the spot on the ground the camera looks at
		var forward := -camera.global_transform.basis.z
		var focus := camera.global_position
		if forward.y < -0.05:
			focus += forward * (camera.global_position.y / -forward.y)
		_fall_mat.set_shader_parameter("focus", Vector3(focus.x, 0.0, focus.z))
