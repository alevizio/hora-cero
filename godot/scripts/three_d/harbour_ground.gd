extends Node3D
## Ground and water of the Bordeaux harbour (Operation Cockle): the paved quay, the cinder rail yard, the
## concrete of the building site, the road; the Garonne and the basin below their stone quay walls; low mist.
## Built once by world.gd in the slot the outpost's nature module fills: set `sim`, add to the tree, build().
## The lamp list (positions and colours of every lamp the harbour builder put up) arrives through set_lamps()
## and drives the light columns on the water and the glow in the mist; both fade when the power is cut.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const GroundShader := preload("res://shaders/harbour_ground.gdshader")
const WaterShader := preload("res://shaders/harbour_water.gdshader")
const MistShader := preload("res://shaders/harbour_mist.gdshader")
const TEX := "res://assets/tex/harbour/"
const NATURE := "res://assets/tex/nature/"
const STRUCT := "res://assets/tex/structures/"
## Half tide: the water lies this far below the quay.
const WATER_Y := -2.3
const MASK_SIZE := 512
const MASK_RECT := Rect2(-34.0, -44.0, 128.0, 128.0)
const CH_A := 0
const CH_B := 1
const CH_C := 2
const CH_D := 3

var sim: RefCounted
var water_material: ShaderMaterial
var mist_material: ShaderMaterial
var ground_material: ShaderMaterial
var _zone := PackedFloat32Array()
var _wear := PackedFloat32Array()
var _mscale: float = MASK_SIZE / MASK_RECT.size.x
var _lamps_on: float = 1.0
var _flicker: float = 0.0
var _was_cut: bool = false
var _h: Dictionary = {}

func build() -> void:
	_h = sim.data.get("harbour", {})
	_build_masks()
	_build_ground()
	_build_walls()
	_build_water()
	_build_mist()

## Every lamp of the harbour as [Vector3 position, Color colour, strength]; fed to the water and the mist.
func set_lamps(all: Array) -> void:
	# The shaders take 16: the lamps nearest the water are the ones whose light the river and the basin show.
	var edge: float = float(_h.get("quayEdge", 13.0))
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	var pool := Rect2(float(basin[0]), float(basin[1]), float(basin[2]) - float(basin[0]), float(basin[3]) - float(basin[1]))
	var list: Array = all.duplicate()
	var reach := func(entry: Array) -> float:
		var at: Vector3 = entry[0]
		var p := Vector2(at.x, at.z)
		var to_basin := Vector2(clampf(p.x, pool.position.x, pool.end.x), clampf(p.y, pool.position.y, pool.end.y)).distance_to(p)
		return minf(maxf(0.0, at.x - edge), to_basin)
	list.sort_custom(func(a: Array, b: Array) -> bool: return reach.call(a) < reach.call(b))
	var lamps := PackedVector4Array()
	var colours := PackedVector4Array()
	for entry: Array in list:
		if lamps.size() >= 16: break
		var at: Vector3 = entry[0]
		var c: Color = entry[1]
		lamps.append(Vector4(at.x, at.y, at.z, float(entry[2])))
		colours.append(Vector4(c.r, c.g, c.b, float(entry[3]) if entry.size() > 3 else 1.0))
	while lamps.size() < 16:
		lamps.append(Vector4(0, -100, 0, 0))
		colours.append(Vector4(0, 0, 0, 1))
	for m: ShaderMaterial in [water_material, mist_material]:
		m.set_shader_parameter("lamps", lamps)
		m.set_shader_parameter("lamp_colors", colours)
		m.set_shader_parameter("lamp_count", mini(list.size(), 16))

## Called every frame from world.update_visuals. When the power goes the reflections die with a stutter.
func update(dt: float, _paused: bool) -> void:
	var cut: bool = bool(sim.radio_cut)
	if cut != _was_cut:
		_was_cut = cut
		_flicker = 0.9 if cut else 0.0
		if not cut: _lamps_on = 1.0
	var want: float = 0.0 if cut else 1.0
	if _flicker > 0.0:
		_flicker = maxf(0.0, _flicker - dt)
		var stutter: float = 1.0 if fposmod(_flicker * 13.0, 1.0) > 0.45 else 0.25
		_lamps_on = stutter * smoothstep(0.0, 0.9, _flicker)
	else:
		_lamps_on = move_toward(_lamps_on, want, dt * 3.0)
	water_material.set_shader_parameter("lamps_on", _lamps_on)
	mist_material.set_shader_parameter("lamps_on", _lamps_on)

## Comic ink (ink.gd): the mist's veils are left out of the drawing (they would show in the depth it is drawn from).
func set_ink(on: bool) -> void:
	for child: Node in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override == mist_material:
			(child as MeshInstance3D).visible = not on

func set_dawn(t: float) -> void:
	water_material.set_shader_parameter("dawn", t)
	mist_material.set_shader_parameter("dawn", t)

# ------------------------------------------------------------------------------------------------ masks
func _stamp_box(buf: PackedFloat32Array, ch: int, r: Rect2, fall: float, strength: float, power: float = 2.0) -> void:
	var px0 := maxi(0, int(floor((r.position.x - fall - MASK_RECT.position.x) * _mscale)))
	var px1 := mini(MASK_SIZE - 1, int(ceil((r.end.x + fall - MASK_RECT.position.x) * _mscale)))
	var py0 := maxi(0, int(floor((r.position.y - fall - MASK_RECT.position.y) * _mscale)))
	var py1 := mini(MASK_SIZE - 1, int(ceil((r.end.y + fall - MASK_RECT.position.y) * _mscale)))
	for py: int in range(py0, py1 + 1):
		var wz := MASK_RECT.position.y + (py + 0.5) / _mscale
		var dz := maxf(maxf(r.position.y - wz, wz - r.end.y), 0.0)
		var row := py * MASK_SIZE
		for px: int in range(px0, px1 + 1):
			var wx := MASK_RECT.position.x + (px + 0.5) / _mscale
			var dx := maxf(maxf(r.position.x - wx, wx - r.end.x), 0.0)
			var d := sqrt(dx * dx + dz * dz)
			if fall <= 0.0:
				if d > 0.0: continue
			elif d >= fall: continue
			var value := strength * (pow(1.0 - d / fall, power) if fall > 0.0 else 1.0)
			var i := (row + px) * 4 + ch
			if value > buf[i]: buf[i] = value

func _stamp_line(buf: PackedFloat32Array, ch: int, a: Vector2, b: Vector2, radius: float, fall: float, strength: float, power: float = 2.0) -> void:
	var reach := radius + fall
	var px0 := maxi(0, int(floor((minf(a.x, b.x) - reach - MASK_RECT.position.x) * _mscale)))
	var px1 := mini(MASK_SIZE - 1, int(ceil((maxf(a.x, b.x) + reach - MASK_RECT.position.x) * _mscale)))
	var py0 := maxi(0, int(floor((minf(a.y, b.y) - reach - MASK_RECT.position.y) * _mscale)))
	var py1 := mini(MASK_SIZE - 1, int(ceil((maxf(a.y, b.y) + reach - MASK_RECT.position.y) * _mscale)))
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.000001)
	for py: int in range(py0, py1 + 1):
		var wz := MASK_RECT.position.y + (py + 0.5) / _mscale
		var row := py * MASK_SIZE
		for px: int in range(px0, px1 + 1):
			var wp := Vector2(MASK_RECT.position.x + (px + 0.5) / _mscale, wz)
			var t := clampf((wp - a).dot(ab) / len2, 0.0, 1.0)
			var d := maxf(wp.distance_to(a + ab * t) - radius, 0.0)
			if d >= fall: continue
			var value := strength * pow(1.0 - d / fall, power)
			var i := (row + px) * 4 + ch
			if value > buf[i]: buf[i] = value

func _rect_m(item: Dictionary) -> Rect2:
	var r: Rect2 = sim.rect_of(item)
	return Rect2(r.position / 32.0, r.size / 32.0)

func _build_masks() -> void:
	_zone.resize(MASK_SIZE * MASK_SIZE * 4)
	_zone.fill(0.0)
	_wear.resize(MASK_SIZE * MASK_SIZE * 4)
	_wear.fill(0.0)
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	var facade: float = float(_h.get("facadeZ", 11.0))
	var tracks: Array = _h.get("yardTracks", [21.4, 25.6])
	# --- surfaces: cinders in the rail yard, tar on the road and the lane, concrete on the building site and the
	# basin apron, mud where the site lorries churn it; setts everywhere else (the quays).
	_stamp_box(_zone, CH_A, Rect2(24.5, float(tracks[0]) - 2.4, 90.0, float(tracks[1]) - float(tracks[0]) + 4.8), 0.6, 1.0, 1.0)
	# any siding further down the yard gets its own strip of cinders
	for k: int in range(2, tracks.size()):
		_stamp_box(_zone, CH_A, Rect2(24.5, float(tracks[k]) - 1.8, 90.0, 3.6), 0.6, 1.0, 1.0)
	var deep: float = float(sim.data.height) / 32.0
	if deep > 45.0:
		# the road across the middle, the lane on south between the sheds, the southern road out to the gate
		_stamp_box(_zone, CH_B, Rect2(13.0, 37.6, 90.0, 2.6), 0.5, 1.0, 1.0)
		_stamp_box(_zone, CH_B, Rect2(38.4, 37.6, 5.8, deep - 37.6), 0.4, 1.0, 1.0)
		_stamp_box(_zone, CH_B, Rect2(24.5, deep - 2.6, 90.0, 40.0), 0.5, 1.0, 1.0)
	else:
		_stamp_box(_zone, CH_B, Rect2(13.0, 37.6, 90.0, 30.0), 0.5, 1.0, 1.0)
	_stamp_box(_zone, CH_B, Rect2(38.4, 28.6, 5.8, 9.4), 0.4, 1.0, 1.0)
	_stamp_box(_zone, CH_C, Rect2(42.8, -40.0, 60.0, 58.7), 0.4, 1.0, 1.0)
	_stamp_box(_zone, CH_C, Rect2(float(basin[0]) - 1.3, float(basin[3]), float(basin[2]) - float(basin[0]) + 1.3, 1.6), 0.5, 0.9, 1.0)
	_stamp_box(_zone, CH_D, Rect2(43.5, 14.5, 9.0, 4.0), 2.2, 0.9, 1.4)
	_stamp_box(_zone, CH_D, Rect2(52.0, 16.5, 7.0, 2.0), 1.6, 0.8, 1.4)
	_stamp_line(_zone, CH_D, Vector2(46.0, 16.5), Vector2(46.0, 21.0), 0.6, 1.4, 0.7, 1.3)
	# --- wear: contact occlusion round everything solid, the quay edge wet, grime where cranes and wagons drip
	for obstacle: Dictionary in sim.data.obstacles:
		var kind := str(obstacle.get("kind", "wall"))
		if kind == "water": continue
		var r := _rect_m(obstacle)
		var reach: float = {"building": 1.7, "wagon": 1.1, "crates": 0.9, "drums": 0.8, "heap": 1.3, "leg": 0.6, "mast": 0.7, "post": 0.3, "buffer": 0.5, "skip": 0.5, "formwork": 0.4, "scaffold": 0.5, "silo": 0.8}.get(kind, 0.9)
		var solid: bool = kind in ["building"]
		_stamp_box(_wear, CH_A, r if solid else r.grow(-0.2), reach, 0.5 if solid else 0.42, 2.2)
		_stamp_box(_wear, CH_A, r.grow(-0.05) if solid else r.grow(-0.35), 0.3, 0.8 if solid else 0.55, 1.5)
		if kind in ["wagon", "leg", "drums"]:
			_stamp_box(_wear, CH_C, r, 1.4, 0.75, 1.5)
		if kind == "heap":
			_stamp_box(_zone, CH_D, r, 1.8, 0.85, 1.2)
	for patch: Dictionary in sim.data.get("bushes", []):
		var r := _rect_m(patch)
		_stamp_box(_wear, CH_A, r.grow(-0.2), 0.6, 0.55, 1.6)
	var edge: float = float(_h.get("quayEdge", 13.0))
	# the quay edge stays wettest; the river side of the setts is dark with spray and slime
	_stamp_box(_wear, CH_B, Rect2(edge - 1.0, -40.0, 1.0, 120.0), 2.4, 0.9, 1.3)
	_stamp_box(_wear, CH_D, Rect2(edge - 1.0, -40.0, 1.0, 120.0), 0.5, 0.7, 1.0)
	_stamp_box(_wear, CH_B, Rect2(float(basin[0]), float(basin[1]), float(basin[2]) - float(basin[0]), float(basin[3]) - float(basin[1])), 1.6, 0.7, 1.3)
	_stamp_box(_wear, CH_B, Rect2(42.8, 11.0, 20.0, 7.5), 0.8, 0.85, 1.0)        # the site: puddles everywhere
	_stamp_box(_wear, CH_B, Rect2(42.8, -40.0, 20.0, 51.0), 0.4, 0.6, 1.0)       # dry dock floors
	_stamp_box(_wear, CH_A, Rect2(24.5, -40.0, 36.0, 40.0 + facade), 2.0, 0.55, 1.6)   # the bunker's foot
	# guards' beats and the crane rails gather oil and grime
	for guard: Dictionary in sim.data.guards:
		var route: Array = guard.route
		for i: int in range(route.size()):
			var a := Vector2(float(route[i][0]), float(route[i][1])) / 32.0
			var b := Vector2(float(route[(i + 1) % route.size()][0]), float(route[(i + 1) % route.size()][1])) / 32.0
			_stamp_line(_wear, CH_C, a, b, 0.1, 0.6, 0.3, 1.5)
	for x: float in _h.get("craneRails", []):
		_stamp_box(_wear, CH_C, Rect2(float(x) - 0.2, -40.0, 0.4, 120.0), 0.5, 0.55, 1.2)
	var image := Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBAF, _zone.to_byte_array())
	image.convert(Image.FORMAT_RGBA8)
	ground_material = ShaderMaterial.new()
	ground_material.shader = GroundShader
	ground_material.set_shader_parameter("zone_tex", ImageTexture.create_from_image(image))
	image = Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBAF, _wear.to_byte_array())
	image.convert(Image.FORMAT_RGBA8)
	ground_material.set_shader_parameter("wear_tex", ImageTexture.create_from_image(image))
	ground_material.set_shader_parameter("mask_rect", Vector4(MASK_RECT.position.x, MASK_RECT.position.y, 1.0 / MASK_RECT.size.x, 1.0 / MASK_RECT.size.y))
	ground_material.set_shader_parameter("map_rect", Vector4(edge, 0.0, float(sim.data.width) / 32.0, float(sim.data.height) / 32.0))
	ground_material.set_shader_parameter("setts_tex", load(TEX + "setts_a.png"))
	ground_material.set_shader_parameter("setts_nrm", load(TEX + "setts_n.png"))
	ground_material.set_shader_parameter("cinder_tex", load(TEX + "cinder_a.png"))
	ground_material.set_shader_parameter("cinder_nrm", load(TEX + "cinder_n.png"))
	ground_material.set_shader_parameter("tar_tex", load(TEX + "tarmac_a.png"))
	ground_material.set_shader_parameter("tar_nrm", load(TEX + "tarmac_n.png"))
	ground_material.set_shader_parameter("concrete_tex", load(STRUCT + "concrete_a.png"))
	ground_material.set_shader_parameter("concrete_nrm", load(STRUCT + "concrete_n.png"))
	ground_material.set_shader_parameter("mud_tex", load(NATURE + "dirt_albedo.png"))
	ground_material.set_shader_parameter("mud_nrm", load(NATURE + "dirt_normal.png"))
	ground_material.set_shader_parameter("macro_tex", load(NATURE + "macro_noise.png"))
	_zone = PackedFloat32Array()
	_wear = PackedFloat32Array()

# ------------------------------------------------------------------------------------------------ ground
## Flat ground at y = 0 in cells cut along the quay lines, so no single mesh is lit by more lamps than the
## renderer allows per object; nothing where the river, the basin or the finished pens are.
func _build_ground() -> void:
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	var edge: float = float(_h.get("quayEdge", 13.0))
	var facade: float = float(_h.get("facadeZ", 11.0))
	var xs: Array[float] = [edge, 18.5, 24.5, float(basin[0]), 34.0, float(basin[2]), 51.0, 60.0, 75.0, 100.0]
	var zs: Array[float] = [-40.0, -15.0, 0.0, facade, float(basin[3]), 28.0, 40.0, 55.0, 70.0, 100.0]
	var holes: Array[Rect2] = [Rect2(float(basin[0]), float(basin[1]), float(basin[2]) - float(basin[0]), float(basin[3]) - float(basin[1])),
		Rect2(24.5, -60.0, float(basin[2]) - 24.5, 60.0 + facade)]
	var count := 0
	for i: int in range(xs.size() - 1):
		for j: int in range(zs.size() - 1):
			var cell := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
			var skip := false
			for hole: Rect2 in holes:
				if hole.encloses(cell): skip = true
			if skip: continue
			var mesh := PlaneMesh.new()
			mesh.size = cell.size
			var node := MeshInstance3D.new()
			node.name = "Ground%d" % count
			node.mesh = mesh
			node.material_override = ground_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = Vector3(cell.get_center().x, 0.0, cell.get_center().y)
			add_child(node)
			count += 1

# ------------------------------------------------------------------------------------------------ quay walls
## Dressed granite walls from the quay down into the water: the river frontage and the basin's three sides.
## Greener and darker toward the waterline, where the tide leaves its weed.
func _build_walls() -> void:
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
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	var edge: float = float(_h.get("quayEdge", 13.0))
	var bottom := WATER_Y - 2.2
	var runs: Array = [
		# left end -> right end of each face as seen from the water
		[Vector3(edge, 0, -40.0), Vector3(edge, 0, 104.0)],
		[Vector3(float(basin[0]), 0, float(basin[3])), Vector3(float(basin[0]), 0, float(basin[1]))],
		[Vector3(float(basin[2]), 0, float(basin[3])), Vector3(float(basin[0]), 0, float(basin[3]))],
		[Vector3(float(basin[2]), 0, float(basin[1])), Vector3(float(basin[2]), 0, float(basin[3]))],
	]
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var length := a.distance_to(b)
		var pieces := maxi(1, int(ceil(length / 12.0)))
		for k: int in range(pieces):
			var kit := Kit.new()
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var weed := Color(0.36, 0.40, 0.30)
			var wet := Color(0.42, 0.44, 0.44)
			var dry := Color(0.80, 0.80, 0.78)
			# below the tide line, the wet band, then dry granite to the coping
			kit.quad_m("wall", Vector3(p0.x, bottom, p0.z), Vector3(p1.x, bottom, p1.z), Vector3(p1.x, WATER_Y + 0.35, p1.z), Vector3(p0.x, WATER_Y + 0.35, p0.z), Vector2(k * 0.37, 0), Color(0.12, 0.13, 0.11), weed)
			kit.quad_m("wall", Vector3(p0.x, WATER_Y + 0.35, p0.z), Vector3(p1.x, WATER_Y + 0.35, p1.z), Vector3(p1.x, WATER_Y + 1.25, p1.z), Vector3(p0.x, WATER_Y + 1.25, p0.z), Vector2(k * 0.37, -0.35), weed, wet)
			kit.quad_m("wall", Vector3(p0.x, WATER_Y + 1.25, p0.z), Vector3(p1.x, WATER_Y + 1.25, p1.z), Vector3(p1.x, -0.12, p1.z), Vector3(p0.x, -0.12, p0.z), Vector2(k * 0.37, -0.7), wet, dry)
			kit.commit(self, materials, "QuayWall", false)

# ------------------------------------------------------------------------------------------------ water, mist
func _build_water() -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = WaterShader
	water_material.set_shader_parameter("normal_tex", load(NATURE + "water_normal.png"))
	water_material.set_shader_parameter("detail_tex", load(NATURE + "water_detail.png"))
	water_material.set_shader_parameter("water_y", WATER_Y)
	water_material.set_shader_parameter("map_rect", Vector4(float(_h.get("quayEdge", 13.0)), 0.0, float(sim.data.width) / 32.0, float(sim.data.height) / 32.0))
	water_material.render_priority = -1
	var edge: float = float(_h.get("quayEdge", 13.0))
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	# The river, in strips along its length (the lamps reach only so far), and the basin running into the pens.
	var parts: Array[Rect2] = []
	for z0: float in [-60.0, -10.0, 15.0, 40.0, 65.0]:
		parts.append(Rect2(-110.0, z0, 110.0 + edge, 25.0 if z0 > -60.0 else 50.0))
	parts.append(Rect2(-110.0, 90.0, 110.0 + edge, 30.0))
	parts.append(Rect2(float(basin[0]), -30.0, float(basin[2]) - float(basin[0]), float(basin[3]) + 30.0))
	var i := 0
	for r: Rect2 in parts:
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
		add_child(node)
		i += 1

## Thin drifting mist just above the water, lit from inside by the lamps nearby.
func _build_mist() -> void:
	mist_material = ShaderMaterial.new()
	mist_material.shader = MistShader
	mist_material.set_shader_parameter("noise_tex", load(NATURE + "macro_noise.png"))
	mist_material.render_priority = 1
	var edge: float = float(_h.get("quayEdge", 13.0))
	var basin: Array = _h.get("basin", [25.8, 11.0, 42.8, 17.6])
	var sheets: Array = [
		[Rect2(-40.0, -40.0, 40.0 + edge - 0.2, 60.0), WATER_Y + 0.55],
		[Rect2(-40.0, 20.0, 40.0 + edge - 0.2, 60.0), WATER_Y + 0.55],
		[Rect2(-40.0, 80.0, 40.0 + edge - 0.2, 30.0), WATER_Y + 0.55],
		[Rect2(float(basin[0]) + 0.2, float(basin[1]), float(basin[2]) - float(basin[0]) - 0.4, float(basin[3]) - float(basin[1]) - 0.2), WATER_Y + 0.5],
	]
	var k := 0
	for sheet: Array in sheets:
		var r: Rect2 = sheet[0]
		var plane := PlaneMesh.new()
		plane.size = r.size
		var node := MeshInstance3D.new()
		node.name = "Mist%d" % k
		node.mesh = plane
		node.material_override = mist_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(r.get_center().x, float(sheet[1]), r.get_center().y)
		add_child(node)
		k += 1
