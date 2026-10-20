extends "res://scripts/three_d/harbour.gd"
## Everything standing in La Boca on the snowy night of Operation Riachuelo, as a blockout: the tenements
## (conventillos) of corrugated iron and wood in their faded boat-paint colours, the squad's courtyard with the washing
## out, the house fronts of the blocks, the café on the Vuelta de Rocha with its cellar door, the railway cutting's two
## bridges and Lechuza's ladder, the tram standing on the avenue's rails, crates and the coal heap on the quay, the
## boat shed and Biguá's boat, the transporter bridge (its towers, the girder, the gondola) and its machine house, the
## river launch with its searchlight, the far bank's sheds and the cart, and the lamps.
##
## It stands in for the harbour's structures module (it extends it, for the lamps, the faders, the searchlight and the
## rules props) and keeps the same interface for world.gd: build(), update(), on_sim_event(), trap_yaw(), gate (the
## cellar door's leaf, swung by world.gd), buildings, door_point, generator_point; and ground_height() for the actors on
## the ladder and in the boat. It does not build Cockle's ships, bunker, quay or yard. Every solid thing stands where
## the rules' obstacle is (the layout script writes both); surfaces take snow where they face up.

const SurfaceShader := preload("res://shaders/boca_surface.gdshader")
const FacadeShader := preload("res://shaders/boca_facade.gdshader")
const LatticeShader := preload("res://shaders/boca_lattice.gdshader")
const ShadeShader := preload("res://shaders/boca_shade.gdshader")
const SnowShader := preload("res://shaders/boca_snow.gdshader")
const WallsShader := preload("res://shaders/boca_walls.gdshader")
## The kit's tiling materials that share one array texture (boca_walls.gdshader), by layer.
const WALL_LAYERS := ["chapa", "stucco", "brick", "planks", "corrugated", "stone", "steel", "snow", "slate", "leaves"]
const Plan = preload("res://scripts/three_d/boca_plan.gd")
const Houses = preload("res://scripts/three_d/boca_houses.gd")
const Street = preload("res://scripts/three_d/boca_street.gd")
const Bridge = preload("res://scripts/three_d/boca_bridge.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")
const TEX_B := "res://assets/tex/boca/"
const LAMP := Color(1.0, 0.72, 0.42)
const LIT := Color(1.0, 0.74, 0.44)
const DARK_GLASS := Color(0.05, 0.06, 0.08)
const IRON := Color(0.16, 0.17, 0.17)
## Boat paint left over from the yards: what La Boca painted its iron walls with, faded and dimmed by the night.
const PAINT: Array[Color] = [Color(0.36, 0.52, 0.66), Color(0.72, 0.30, 0.24), Color(0.80, 0.66, 0.30), Color(0.38, 0.58, 0.42),
	Color(0.62, 0.42, 0.52), Color(0.82, 0.78, 0.66), Color(0.30, 0.42, 0.56), Color(0.70, 0.50, 0.30)]
## Where the boat and the gondola rest, and the river's water line (the harbour's).
const BOAT_SIT := 0.05

var w: Dictionary = {}
## The ground (boca_ground.gd), for the cutting's depth.
var ground: Node3D
## Lechuza's ladder down the cutting (shown once it is set).
var ladder_node: Node3D
## The gondola, hung from its trolley on the girder: rides across with whoever is on it.
var gondola: Node3D
var gondola_z: float = 0.0
## Biguá's boat: on the slip until it is launched, then under him as he rows.
var boat: Node3D
var _boat_at := Vector3.ZERO
var _macro: Texture2D
var _cut := Vector2(30.0, 38.0)
var _cut_depth: float = 4.0
var _river := Vector2(110.0, 134.0)
var _paint_i: int = 0
## The plan of the houses (shared with the ground) and their builder.
var plan: Plan
var houses: Houses
var street: Street
## Light that has no lamp of its own: pools under the street lamps and spill from lit doorways, added on the snow.
var _pools := Kit.new()
## The quay's lamps' own pools: they die with the board.
var _powered_pools := Kit.new()
var pool_material: StandardMaterial3D
var powered_pool_material: StandardMaterial3D
var spill_material: StandardMaterial3D
var deco_bulb_material: StandardMaterial3D
var _deco := Kit.new()
## Halos of the lamps that need no switching: [position, colour, size], drawn as one multimesh.
var _halos: Array = []
## Smoke, every puff of every chimney in one multimesh: {at, first, count, size}.
var _smoke_mm: MultiMesh
var _smoke_list: Array = []

func build() -> void:
	rng.seed = 19580716
	fade_for_guards = false
	w = sim.data.get("bocaWorld", {})
	ground = get_parent().get_node_or_null("Ground") if get_parent() != null else null
	_cut = Vector2(float(w.get("cut", [30.0, 38.0])[0]), float(w.get("cut", [30.0, 38.0])[1]))
	_cut_depth = float(w.get("cutDepth", 4.0))
	_river = Vector2(float(w.get("river", [110.0, 134.0])[0]), float(w.get("river", [110.0, 134.0])[1]))
	_macro = load("res://assets/tex/nature/macro_noise.png")
	materials = Kit.make_materials()
	_harbour_materials()
	_boca_materials()
	# while La Boca builds, the tiling surfaces of every kit go into one surface (the walls array)
	var aliases := {}
	for i: int in range(WALL_LAYERS.size()): aliases[WALL_LAYERS[i]] = ["walls", i]
	# and the facade atlas's cut-outs and lit windows into one surface too (lit where UV2.x is 1)
	aliases["facade"] = ["facade_all", 0]
	aliases["facade_cut"] = ["facade_all", 0]
	aliases["facade_lit"] = ["facade_all", 1]
	Kit.aliases = aliases
	# indoors (the café's floor, its bar and tables): the planks as they are, no snow
	materials["indoor"] = materials["planks"]
	_snow_materials()
	_props = Props.new(19580717)
	_rules = Rules.new(_props, 19580718)
	var guardia: Array = w.get("guardia", [178.0, 46.0, 200.0, 64.0])
	door_point = Vector3(float(guardia[0]) - 0.6, 0.0, (float(guardia[1]) + float(guardia[3])) * 0.5)
	generator_point = Vector3(float(sim.data.radio.x) / 32.0, 0.0, float(sim.data.radio.y) / 32.0)
	plan = Plan.new(sim.data)
	houses = Houses.new(self, plan)
	var pt: Array = w.get("patio", [102.0, 4.0, 118.0, 16.0])
	houses.courtyard = Rect2(float(pt[0]), float(pt[1]), float(pt[2]) - float(pt[0]), float(pt[3]) - float(pt[1]))
	houses.build()
	street = Street.new(self, sim.data)
	street.build()
	street.trees(houses.trees, houses.palms, houses.tree_room)
	_build_signs()
	_build_courtyard()
	_build_cafe()
	_build_bridges()
	_build_ladder()
	_build_tram()
	_build_quay()
	_build_boat()
	_build_transporter()
	_build_launch()
	_build_far_bank()
	_build_lamps()
	_build_dark_shade()
	_build_city_lamps()
	_build_wall_lamps()
	_snow_play()
	_build_smoke()
	_build_smoke_mesh()
	_commit_pools()
	_build_charges()
	_build_traps()
	Kit.aliases = {}
	_sync_rules(1.0)
	_sync_power(1.0, true)

## Every built surface takes snow where it faces up (as at Vemork): the kit's textured materials become snow_surface
## shaders over the same textures; glass, decals and the lamps stay as they are.
func _snow_materials() -> void:
	for key: String in materials.keys():
		var source: Material = materials[key]
		if not source is StandardMaterial3D: continue
		var sm := source as StandardMaterial3D
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or sm.emission_enabled: continue
		if sm.albedo_texture == null or key in ["indoor", "indoor_stone", "tiles", "facade_cloth"]: continue
		var m := ShaderMaterial.new()
		m.shader = SurfaceShader
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
		m.set_shader_parameter("macro_tex", _macro)
		if sm.normal_enabled and sm.normal_texture != null:
			m.set_shader_parameter("normal_tex", sm.normal_texture)
			m.set_shader_parameter("use_normal", true)
			m.set_shader_parameter("normal_scale", sm.normal_scale)
		else:
			m.set_shader_parameter("use_normal", false)
		m.set_shader_parameter("rough_alpha", sm.roughness_texture != null)
		m.set_shader_parameter("roughness", sm.roughness)
		m.set_shader_parameter("uv_scale", Vector2(sm.uv1_scale.x, sm.uv1_scale.y))
		m.set_shader_parameter("specular", sm.metallic_specular)
		materials[key] = m

## Height of the ground under an actor: 0, except down Lechuza's ladder in the cutting and in Biguá's boat on the river.
func ground_height(x: float, z: float) -> float:
	var p := Vector2(x, z) * 32.0
	for passage: Dictionary in sim.passages():
		if not sim.rigged.has(str(passage.id)) or not sim.rect_of(passage).has_point(p): continue
		match str(passage.get("kind", "")):
			"ladder":
				var from_n := z - _cut.x
				var from_s := _cut.y - z
				var run := 1.2
				var s := 1.0
				if from_n < run: s = clampf(from_n / run, 0.0, 1.0)
				elif from_s < run: s = clampf(from_s / run, 0.0, 1.0)
				return -_cut_depth * s
			"boat":
				if z > _river.x: return WATER_Y + BOAT_SIT
	return 0.0

func _m(item: Dictionary) -> Rect2:
	var r: Rect2 = sim.rect_of(item)
	return Rect2(r.position / 32.0, r.size / 32.0)

func _paint() -> Color:
	_paint_i += 1
	return PAINT[(_paint_i * 5 + rng.randi_range(0, 2)) % PAINT.size()] * rng.randf_range(0.82, 1.0)

# ---------------------------------------------------------------------------------------------------------------
# Materials, light pools
# ---------------------------------------------------------------------------------------------------------------
## La Boca's own surfaces: painted corrugated iron and lime render (white enough for the paint to show), the facade
## atlas in its three uses, washing on the lines, snow in a layer of its own; light pools added on the snow.
func _boca_materials() -> void:
	for key: String in ["chapa", "stucco"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEX_B + key + "_a.png")
		m.vertex_color_use_as_albedo = true
		m.normal_enabled = true
		m.normal_texture = load(TEX_B + key + "_n.png")
		m.normal_scale = 0.8 if key == "stucco" else 1.0
		m.roughness = 0.9
		if key == "chapa":
			m.roughness_texture = m.albedo_texture
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
			m.roughness = 1.0
		m.metallic_specular = 0.4
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		materials[key] = m
	var walls := ShaderMaterial.new()
	walls.shader = WallsShader
	walls.set_shader_parameter("albedo_tex", load(TEX_B + "walls_a.webp"))
	walls.set_shader_parameter("normal_tex", load(TEX_B + "walls_n.webp"))
	walls.set_shader_parameter("macro_tex", _macro)
	# roughness per layer (< 0: in the texture's alpha) and normal strength
	walls.set_shader_parameter("roughness", PackedFloat32Array([-1.0, 0.9, 0.93, 0.9, -1.0, 0.95, -1.0, 0.8, -1.0, 0.6]))
	walls.set_shader_parameter("normal_scale", PackedFloat32Array([1.0, 0.8, 1.0, 1.0, 1.0, 1.1, 0.8, 0.5, 1.0, 1.0]))
	materials["walls"] = walls
	var atlas: Texture2D = load(TEX_B + "facade_a.png")
	for key: String in ["facade", "facade_cut", "facade_lit", "facade_all"]:
		var f := ShaderMaterial.new()
		f.shader = FacadeShader
		f.set_shader_parameter("atlas", atlas)
		f.set_shader_parameter("cutout", key == "facade_cut")
		f.set_shader_parameter("lit", key == "facade_lit")
		f.set_shader_parameter("layered", key == "facade_all")
		# lit windows bright enough to bloom: a warm halo round each against the blue
		f.set_shader_parameter("energy", 3.4)
		materials[key] = f
	var cloth := StandardMaterial3D.new()
	cloth.albedo_texture = load(Kit.TEX_DIR + "canvas_a.png")
	cloth.vertex_color_use_as_albedo = true
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.95
	materials["facade_cloth"] = cloth
	var snow := ShaderMaterial.new()
	snow.shader = SnowShader
	snow.set_shader_parameter("snow_tex", load("res://assets/tex/snow/snow_a.png"))
	snow.set_shader_parameter("macro_tex", _macro)
	materials["snowcap"] = snow
	pool_material = _pool_material(true)
	powered_pool_material = _pool_material(true)
	spill_material = _pool_material(false)
	materials["pool"] = pool_material
	materials["powered_pool"] = powered_pool_material
	materials["spill"] = spill_material
	deco_bulb_material = _emissive(Color(1.0, 0.78, 0.5), 5.0)
	materials["decobulb"] = deco_bulb_material
	var lattice := ShaderMaterial.new()
	lattice.shader = LatticeShader
	lattice.set_shader_parameter("atlas", load(TEX_B + "lattice_a.png"))
	materials["lattice"] = lattice
	var tiles := StandardMaterial3D.new()
	tiles.albedo_texture = load(TEX_B + "tiles_a.png")
	tiles.vertex_color_use_as_albedo = true
	tiles.roughness = 0.35
	tiles.metallic_specular = 0.6
	tiles.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials["tiles"] = tiles
	var marble := StandardMaterial3D.new()
	marble.albedo_texture = load(Kit.TEX_DIR + "stone_a.png")
	marble.vertex_color_use_as_albedo = true
	marble.roughness = 0.3
	marble.metallic_specular = 0.6
	materials["indoor_stone"] = marble
	var twigs := ShaderMaterial.new()
	twigs.shader = FacadeShader
	twigs.set_shader_parameter("atlas", load(TEX_B + "twigs_a.png"))
	twigs.set_shader_parameter("cutout", true)
	materials["twigs"] = twigs

## Light thrown on the snow with no lamp to throw it: a soft disc (round) or a fan out of a doorway, added to what is
## there. The vertex colour carries its colour and strength.
func _pool_material(round: bool) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.45, Color(1, 1, 1, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL if round else GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.5) if round else Vector2(0.5, 0.0)
	texture.fill_to = Vector2(1.0, 0.5) if round else Vector2(0.5, 1.0)
	texture.width = 64
	texture.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.render_priority = 0
	m.no_depth_test = false
	return m

## A pool of lamplight on the ground (no light: added on the snow).
func pool(at: Vector3, radius: float, col: Color, powered: bool = false) -> void:
	var k := _powered_pools if powered else _pools
	# (callers scale the colour for strength: that scales its alpha too, which would dim an added pool twice)
	col.a = 1.0
	var y := 0.045
	var r := radius
	k.quad_rect("powered_pool" if powered else "pool", Vector3(at.x - r, y, at.z + r), Vector3(at.x + r, y, at.z + r), Vector3(at.x + r, y, at.z - r), Vector3(at.x - r, y, at.z - r), Rect2(0, 0, 1, 1), col, col)

## Light from a lit doorway or window spilling out over the snow in front of it.
func spill(at: Vector3, right: Vector3, out: Vector3, width: float, length: float, strength: float) -> void:
	var y := 0.05
	var c := Color(1.0, 0.62, 0.3) * strength * 0.5
	c.a = 1.0
	var a := at - right * width * 0.6 + Vector3(0, y, 0)
	var bb := at + right * width * 0.6 + Vector3(0, y, 0)
	var cc := at + right * width * 1.1 + out * length + Vector3(0, y, 0)
	var d := at - right * width * 1.1 + out * length + Vector3(0, y, 0)
	_pools.quad_rect("spill", d, cc, bb, a, Rect2(0, 0, 1, 1), Color.BLACK, c)

## The little lamp over a corner shop's sign.
func sign_lamp(at: Vector3, out: Vector3) -> void:
	_props.wall_lamp(_deco, at - out * 0.45, atan2(out.x, out.z), 0.45)
	_deco.lathe("decobulb", at + Vector3(0, -0.12, 0), PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.07, 0.0), Vector2(0.07, 0.04)]), 8)
	_halo(at + Vector3(0, -0.15, 0), Color(1.0, 0.74, 0.46), 0.9)
	spill(Vector3(at.x, 0.0, at.z) - out * 0.45, Vector3(out.z, 0, -out.x), out, 1.4, 2.6, 0.7)

## Children's tracks round the snowman: two small meandering trails of boot prints.
func kid_tracks(at: Vector3, into: Kit = null) -> void:
	var k := into if into != null else Kit.new()
	for t: int in range(2):
		var a := rng.randf() * TAU
		var r := 1.2 + 0.4 * float(t)
		for i: int in range(26):
			var ang := a + float(i) * 0.24
			var p := Vector3(at.x + cos(ang) * r * (1.0 + 0.15 * sin(float(i) * 0.7)), 0.0, at.z + sin(ang) * r)
			var side := 0.07 if i % 2 == 0 else -0.07
			var dir := Vector3(-sin(ang), 0, cos(ang))
			var q := p + Vector3(dir.z, 0, -dir.x) * side
			k.decal(Kit.DECAL["blob"], q.x, q.z, Vector2(0.11, 0.22), atan2(dir.x, dir.z), Color(0.35, 0.42, 0.62, 0.5), 0.03)
		# the ring they trod, soft enough to read from high up
		k.decal(Kit.DECAL["blob"], at.x, at.z, Vector2(r * 2.6, r * 2.6), 0.0, Color(0.38, 0.4, 0.62, 0.22), 0.028)
	if into == null: _commit(k, self, "KidTracks", false)

## A trail of boot prints along a path (in the patios and on the pavements round the map, where nobody plays):
## blue-shadowed hollows, left and right.
func trail(k: Kit, pts: PackedVector2Array, stride: float = 0.42) -> void:
	for i: int in range(pts.size() - 1):
		var a := pts[i]
		var bb := pts[i + 1]
		var d := bb - a
		var n := int(d.length() / stride)
		if n < 1: continue
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		# the trodden band under the prints, which is what reads from high up
		var mid := (a + bb) * 0.5
		k.decal(Kit.DECAL["blob"], mid.x, mid.y, Vector2(0.7, d.length() + 0.5), atan2(dir.x, dir.y), Color(0.36, 0.4, 0.62, 0.3), 0.029)
		for j: int in range(n):
			var p := a + d * (float(j) + 0.5) / float(n) + side * (0.09 if j % 2 == 0 else -0.09) + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
			k.decal(Kit.DECAL["blob"], p.x, p.y, Vector2(0.13, 0.27), atan2(dir.x, dir.y), Color(0.32, 0.38, 0.58, 0.42), 0.03)

## The barrio out in the snow, as it left the ground: a snowball fight frozen as three trampled camps on the pavement
## before the café's block and the runs between them, sled runs along the quay, a ring trodden round a lamp. Only
## marks in the snow (nobody walks into a mark); the snowmen and the sleds themselves stand in the patios, against
## the fronts and in the streets round the map.
func _snow_play() -> void:
	var k := Kit.new()
	var camps: Array[Vector2] = [Vector2(87.0, 96.8), Vector2(99.5, 97.6), Vector2(113.0, 96.6)]
	for c: Vector2 in camps: _trampled(k, c, rng.randf_range(1.3, 1.8))
	for i: int in range(16):
		var a: Vector2 = camps[rng.randi() % camps.size()]
		var bb: Vector2 = camps[rng.randi() % camps.size()]
		if a == bb: continue
		var mid := (a + bb) * 0.5 + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.2, 1.2))
		mid.y = clampf(mid.y, 95.4, 99.0)
		trail(k, PackedVector2Array([a + _jit(1.0), mid, bb + _jit(1.0)]), 0.48)
	# sled runs: two runners 0.34 apart, drawn along the quay's open snow and back
	for run: Array in [[Vector2(63.0, 107.6), Vector2(78.0, 108.4), Vector2(90.0, 107.2)], [Vector2(112.0, 108.6), Vector2(122.0, 107.4), Vector2(130.0, 108.2)]]:
		_sled_run(k, run)
	_commit(k, self, "SnowPlay", false)

func _jit(r: float) -> Vector2:
	return Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))

## A patch of snow trodden flat where a gang stood throwing: a soft hollow and a scatter of prints.
func _trampled(k: Kit, c: Vector2, r: float) -> void:
	k.decal(Kit.DECAL["blob"], c.x, c.y, Vector2(r * 2.4, r * 2.0), rng.randf() * TAU, Color(0.36, 0.38, 0.6, 0.42), 0.028)
	for i: int in range(34):
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
		k.decal(Kit.DECAL["blob"], p.x, p.y, Vector2(0.13, 0.27), rng.randf() * TAU, Color(0.32, 0.36, 0.58, 0.45), 0.031)

## A sled's two runner lines through a few points, and the puller's prints beside them.
func _sled_run(k: Kit, pts: Array) -> void:
	for i: int in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var bb: Vector2 = pts[i + 1]
		var d := bb - a
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		var n := int(d.length() / 0.5)
		for j: int in range(n):
			var p := a + d * (float(j) + 0.5) / float(n)
			for sx: float in [-0.17, 0.17]:
				var q := p + side * sx
				k.decal(Kit.DECAL["blob"], q.x, q.y, Vector2(0.1, 0.62), atan2(dir.x, dir.y), Color(0.3, 0.34, 0.56, 0.6), 0.03)
			k.decal(Kit.DECAL["blob"], p.x, p.y, Vector2(0.5, 0.62), atan2(dir.x, dir.y), Color(0.38, 0.42, 0.64, 0.2), 0.029)
	var path := PackedVector2Array()
	for p2: Vector2 in pts: path.append(p2 + Vector2(0.0, -0.9))
	trail(k, path, 0.5)

## A soft halo round a lamp that has no light of its own.
func _halo(at: Vector3, col: Color, size: float, parent: Node3D = null) -> MeshInstance3D:
	if parent == null:
		# a halo that never moves nor goes out: one instance among all of them (one draw)
		_halos.append([at, col, size])
		return null
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	halo.mesh = quad
	var m: StandardMaterial3D = halo_material.duplicate()
	m.albedo_color = Color(col.r, col.g, col.b, 0.8)
	halo.material_override = m
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = at
	halo.set_meta("no_batch", true)
	(parent if parent != null else self).add_child(halo)
	return halo

## A lit window far off (the road bridge's towers): a small glowing pane, no light.
func add_window_glow(at: Vector3, size: float, strength: float) -> void:
	_deco.box("decobulb", at, Vector3(size * 0.6, size, size * 0.6) * strength)

func _commit_pools() -> void:
	_commit(_pools, self, "LightPools", false)
	_commit(_powered_pools, self, "QuayLampPools", false)
	commit(_deco, self, "LampFittings", true)
	if not _halos.is_empty():
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = _halos.size()
		for i: int in range(_halos.size()):
			var h: Array = _halos[i]
			var s: float = h[2]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), h[0]))
			var c: Color = h[1]
			mm.set_instance_color(i, Color(c.r, c.g, c.b, 0.8))
		var node := MultiMeshInstance3D.new()
		node.name = "Halos"
		node.multimesh = mm
		var m: StandardMaterial3D = halo_material.duplicate()
		m.albedo_color = Color.WHITE
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(700, 80, 600))
		add_child(node)
		# and round each street lamp's (not the little bulbs'), the wide faint glow of its light in the damp air
		var big: Array = []
		for h: Array in _halos:
			if float(h[2]) >= 1.2: big.append(h)
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.mesh = quad
		mm2.instance_count = big.size()
		for i: int in range(big.size()):
			var h: Array = big[i]
			var s: float = float(h[2]) * 3.4
			mm2.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), h[0]))
			var c: Color = h[1]
			mm2.set_instance_color(i, Color(c.r, c.g * 0.85, c.b * 0.7, 1.0))
		var node2 := MultiMeshInstance3D.new()
		node2.name = "FogGlow"
		node2.multimesh = mm2
		node2.material_override = _fog_glow_material()
		node2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node2.custom_aabb = node.custom_aabb
		add_child(node2)

## A lamp's light in the damp air: a wide, faint, warm glow, added over everything (no depth test: it is the air in
## front of the lamp that glows); one shared material.
var _fog_glow: StandardMaterial3D
func _fog_glow_material() -> StandardMaterial3D:
	if _fog_glow != null: return _fog_glow
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.55))
	gradient.add_point(0.18, Color(1, 1, 1, 0.3))
	gradient.add_point(0.5, Color(1, 1, 1, 0.08))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_fog_glow = StandardMaterial3D.new()
	_fog_glow.albedo_texture = texture
	_fog_glow.albedo_color = Color(1.0, 0.62, 0.32, 0.32)
	_fog_glow.vertex_color_use_as_albedo = true
	_fog_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fog_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fog_glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fog_glow.billboard_keep_scale = true
	_fog_glow.no_depth_test = true
	_fog_glow.disable_fog = true
	_fog_glow.render_priority = 7
	return _fog_glow

## Smoke from a chimney (as the harbour's, but every puff in one multimesh).
func add_smoke(at: Vector3, count: int = 6, size: float = 1.2) -> void:
	_smoke_list.append({"at": at, "count": count, "size": size})

func _build_smoke_mesh() -> void:
	var total := 0
	for s: Dictionary in _smoke_list:
		s.first = total
		total += int(s.count)
	if total == 0: return
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_smoke_mm = MultiMesh.new()
	_smoke_mm.transform_format = MultiMesh.TRANSFORM_3D
	_smoke_mm.use_colors = true
	_smoke_mm.mesh = quad
	_smoke_mm.instance_count = total
	var node := MultiMeshInstance3D.new()
	node.name = "Smoke"
	node.multimesh = _smoke_mm
	var m := _sprite_material(Color(1, 1, 1, 1), false)
	m.vertex_color_use_as_albedo = true
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(700, 80, 600))
	add_child(node)
	_sync_smoke()

func _sync_smoke() -> void:
	if _smoke_mm == null: return
	for smoke: Dictionary in _smoke_list:
		var n: int = smoke.count
		for i: int in range(n):
			var t := fposmod(_clock * 0.06 + float(i) / float(n), 1.0)
			var p: Vector3 = (smoke.at as Vector3) + Vector3(1.8 * t + 0.25 * sin(_clock * 0.3 + float(i)), 3.2 * t, -1.2 * t)
			var grow := float(smoke.size) * (0.6 + 2.2 * t)
			_smoke_mm.set_instance_transform(int(smoke.first) + i, Transform3D(Basis.from_scale(Vector3(grow, grow, grow)), p))
			_smoke_mm.set_instance_color(int(smoke.first) + i, Color(0.7, 0.7, 0.76, 0.45 * sin(PI * minf(1.0, t * 1.1)) * (1.0 - t * 0.6)))

## Signs on the post of the Guardia and on the machine house.
func _build_signs() -> void:
	var g: Array = w.get("guardia", [178.0, 46.0, 200.0, 64.0])
	_sign(Vector3(float(g[0]) - 0.08, 4.6, 55.0), Vector3(-1, 0, 0), "GUARDIA DE EMERGENCIA", 6.0)
	var m: Array = w.get("machine", [134.0, 105.0, 145.0, 110.0])
	_sign(Vector3((float(m[0]) + float(m[2])) * 0.5, 4.6, float(m[1]) - 0.08), Vector3(0, 0, -1), "SALA DE MÁQUINAS", 5.2)

## Lamps on brackets on the house fronts (none where the quay's lamps light the ground: there the board decides).
func _build_wall_lamps() -> void:
	for entry: Array in houses.wall_lamps:
		var at: Vector3 = entry[0]
		var n: Vector3 = entry[1]
		if _near_powered(at, 7.0): continue
		_props.wall_lamp(_deco, at, atan2(n.x, n.z), 0.55)
		Snow.cone(_deco, at + n * 0.55 + Vector3(0, -0.03, 0), 0.12, 0.07)
		var bulb := at + n * 0.55 + Vector3(0, -0.13, 0)
		_deco.lathe("decobulb", bulb, PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.08, 0.0), Vector2(0.08, 0.05)]), 8)
		_halo(bulb, Color(1.0, 0.74, 0.46), 1.3)
		pool(Vector3(bulb.x, 0.0, bulb.z) + n * 0.6, 3.6, Color(1.0, 0.58, 0.28) * 0.36)

func _near_powered(at: Vector3, margin: float) -> bool:
	for f: Array in sim.data.get("floodlit", []):
		if f.size() > 4 and str(f[4]) == "powered":
			var r := Rect2(float(f[0]) / 32.0, float(f[1]) / 32.0, float(f[2]) / 32.0, float(f[3]) / 32.0).grow(margin)
			if r.has_point(Vector2(at.x, at.z)): return true
	return false

## Smoke from a few of the chimneys and stovepipes: the stoves are lit tonight.
func _build_smoke() -> void:
	var picked := 0
	var r := RandomNumberGenerator.new()
	r.seed = 1958
	for top: Vector3 in houses.chimneys:
		if top.x < -10.0 or top.x > 250.0 or top.z < -12.0 or top.z > 160.0: continue
		if r.randf() < 0.12 and picked < 16:
			add_smoke(top, 6, 0.9)
			picked += 1


## A painted name on a wall: world signage, never translated.
func _sign(at: Vector3, facing: Vector3, words: String, width: float) -> void:
	var text := Label3D.new()
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.text = words
	text.font_size = 64
	text.pixel_size = width / (maxf(1.0, float(words.length())) * 44.0)
	text.modulate = Color(0.92, 0.88, 0.76)
	text.outline_size = 0
	text.shaded = true
	text.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	text.position = at
	text.rotation.y = atan2(facing.x, facing.z)
	add_child(text)

# ---------------------------------------------------------------------------------------------------------------
# The courtyard, the café
# ---------------------------------------------------------------------------------------------------------------
## The squad's courtyard: the washing out on the line, the stone trough.
func _build_courtyard() -> void:
	var k := Kit.new()
	for item: Dictionary in sim.data.obstacles:
		if str(item.id) == "trough":
			var r := _m(item)
			k.box("concrete", Vector3(r.get_center().x, 0.42, r.get_center().y), Vector3(r.size.x, 0.84, r.size.y), Color(0.5, 0.5, 0.5), Color(0.85, 0.85, 0.85))
	for bush: Dictionary in sim.data.bushes:
		if str(bush.get("kind", "")) != "washing": continue
		var r := _m(bush)
		var a := Vector3(r.position.x, 2.2, r.get_center().y)
		var b := Vector3(r.end.x, 2.2, r.get_center().y)
		for p: Vector3 in [a, b]:
			k.beam("planks", Vector3(p.x, 0.0, p.z), p + Vector3(0, 0.15, 0), 0.08, 0.08, Props.WOOD_GREY, Props.WOOD_GREY)
		_props.wire(k, a, b, 0.15, 0.01, Color(0.7, 0.7, 0.66), 8)
		# sheets and shirts pegged out, drooping in the wet snow
		var x := r.position.x + 0.3
		while x < r.end.x - 0.5:
			var wide := rng.randf_range(0.5, 1.1)
			var drop := rng.randf_range(0.6, 1.4)
			var col: Color = [Color(0.86, 0.86, 0.84), Color(0.62, 0.68, 0.78), Color(0.78, 0.6, 0.56)][rng.randi_range(0, 2)]
			var z := r.get_center().y
			k.quad_m("canvas", Vector3(x, 2.15 - drop, z), Vector3(x + wide, 2.15 - drop, z), Vector3(x + wide, 2.15, z), Vector3(x, 2.15, z), Vector2.ZERO, col * 0.8, col)
			k.quad_m("canvas", Vector3(x + wide, 2.15 - drop, z), Vector3(x, 2.15 - drop, z), Vector3(x, 2.15, z), Vector3(x + wide, 2.15, z), Vector2.ZERO, col * 0.7, col * 0.9)
			x += wide + 0.15
	# a bulb on a wire across the courtyard, over the trough
	var pt0: Array = w.get("patio", [102.0, 4.0, 118.0, 16.0])
	var mid_z := (float(pt0[1]) + float(pt0[3])) * 0.5 - 1.0
	var bulb := Vector3((float(pt0[0]) + float(pt0[2])) * 0.5, 3.9, mid_z)
	_props.wire(k, Vector3(float(pt0[0]), 4.6, mid_z), Vector3(float(pt0[2]), 4.6, mid_z), 0.5, 0.008, Color(0.15, 0.15, 0.15), 8)
	k.lathe("steel", bulb + Vector3(0, 0.1, 0), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.08, 0.1), Vector2(0.02, 0.14)]), 8, Color(0.2, 0.26, 0.22), Color(0.3, 0.36, 0.3))
	k.lathe("decobulb", bulb, PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.07, 0.0), Vector2(0.06, 0.08)]), 8)
	_halo(bulb, Color(1.0, 0.76, 0.48), 1.2)
	pool(Vector3(bulb.x, 0.0, bulb.z), 3.4, Color(1.0, 0.6, 0.3) * 0.3)
	# the outside stair up to the gallery, in the courtyard's north-east corner, against the wall
	var pt: Array = w.get("patio", [102.0, 4.0, 118.0, 16.0])
	var corner := Vector3(float(pt[2]), 0.0, float(pt[1]))
	houses.stair(k, corner + Vector3(-0.6, 0.0, 0.5), corner + Vector3(-4.4, 3.7, 0.5), 0.85)
	commit(k, self, "Courtyard", true)

## The café on the corner of the square and the alley, cut away so the room shows (the rules' walls, no roof): cream
## render over a green dado, a capping that holds the snow; on the square its lit windows under striped awnings, the
## door, the painted sign "CAFÉ LA BRUMA" and its lamp; inside, the black-and-white marble floor, the bar with the
## bottles lit behind it, marble tables; the cellar's barrels; the cellar door's leaf.
func _build_cafe() -> void:
	var cafe: Array = w.get("cafe", [56.0, 80.0, 80.0, 94.0])
	var c0 := Vector2(float(cafe[0]), float(cafe[1]))
	var c1 := Vector2(float(cafe[2]), float(cafe[3]))
	var cellar: Array = w.get("cellar", [56.5, 80.5, 66.0, 86.0])
	var front: Array = w.get("cafeFront", [66.0, 68.0])
	var top := 3.6
	var walls := Kit.new()
	var det := Kit.new()
	var cream := Houses.hexc("e6d8b8")
	var green := Houses.hexc("2f4a3a")
	for item: Dictionary in sim.data.obstacles:
		if str(item.kind) != "wall": continue
		var r := _m(item)
		var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
		walls.push_tint(cream)
		walls.box("stucco", c + Vector3(0, top * 0.5, 0), Vector3(r.size.x, top, r.size.y), Color(0.62, 0.6, 0.58), Color(0.95, 0.95, 0.95), Vector2(r.position.x + r.position.y, 0.0) * Kit.UV_M, Kit.UPRIGHT)
		walls.pop_tint()
		walls.push_tint(green)
		walls.box("stucco", c + Vector3(0, 0.48, 0), Vector3(r.size.x + 0.05, 0.96, r.size.y + 0.05), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
		walls.pop_tint()
		walls.push_tint(Color(0.86, 0.84, 0.8))
		walls.box("stone", c + Vector3(0, top + 0.07, 0), Vector3(r.size.x + 0.14, 0.14, r.size.y + 0.14), Color(0.8, 0.8, 0.8), Color.WHITE)
		walls.pop_tint()
	# pilasters at the corners of the front
	walls.push_tint(cream.lightened(0.15))
	for x: float in [c0.x + 0.25, c1.x - 0.25]:
		walls.box("stucco", Vector3(x, top * 0.5, c1.y - 0.2), Vector3(0.62, top + 0.3, 0.62), Color(0.7, 0.7, 0.7), Color.WHITE)
	walls.pop_tint()
	# the front on the square: lit windows with frames and sills, striped awnings with snow on them
	var z := c1.y + 0.012
	var lit := Color(1.0, 0.86, 0.64)
	for wx: float in [59.0, 62.5, 71.0, 74.5, 77.5]:
		det.quad_rect("facade_lit", Vector3(wx - 0.85, 0.95, z), Vector3(wx + 0.85, 0.95, z), Vector3(wx + 0.85, 2.45, z), Vector3(wx - 0.85, 2.45, z), Houses.uv("shop_lit"), lit, lit)
		det.push_tint(Color(0.25, 0.18, 0.12))
		for fx: float in [wx - 0.85, wx, wx + 0.85]:
			det.box("planks", Vector3(fx, 1.7, z + 0.02), Vector3(0.07, 1.5, 0.04), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
		det.box("planks", Vector3(wx, 1.8, z + 0.02), Vector3(1.7, 0.06, 0.04), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
		det.pop_tint()
		walls.push_tint(Color(0.85, 0.83, 0.8))
		walls.box("stone", Vector3(wx, 0.9, z + 0.08), Vector3(1.9, 0.08, 0.18), Color(0.8, 0.8, 0.8), Color.WHITE)
		walls.pop_tint()
		_awning(det, Vector3(wx - 1.0, 2.95, z), Vector3(wx + 1.0, 2.95, z), 1.15, "awning_green")
		spill(Vector3(wx, 0.0, c1.y), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.6, 2.4, 0.75)
	# the door: a frame round the opening, the light falling out of it
	var dx0 := float(front[0])
	var dx1 := float(front[1])
	det.push_tint(Color(0.25, 0.18, 0.12))
	for fx: float in [dx0 + 0.05, dx1 - 0.05]:
		det.box("planks", Vector3(fx, 1.45, c1.y - 0.25), Vector3(0.1, 2.9, 0.52), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
	det.box("planks", Vector3((dx0 + dx1) * 0.5, 2.92, c1.y - 0.25), Vector3(dx1 - dx0, 0.12, 0.52), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
	det.pop_tint()
	spill(Vector3((dx0 + dx1) * 0.5, 0.0, c1.y), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.8, 3.6, 1.0)
	# the painted sign over the door, on a board above the wall, with its lamp
	var sw := 5.2
	var sx := (dx0 + dx1) * 0.5
	walls.push_tint(Color(0.2, 0.16, 0.12))
	walls.box("planks", Vector3(sx, top + 0.62, c1.y - 0.2), Vector3(sw + 0.2, 1.42, 0.12), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
	walls.pop_tint()
	det.quad_rect("facade", Vector3(sx - sw * 0.5, top - 0.02, c1.y - 0.13), Vector3(sx + sw * 0.5, top - 0.02, c1.y - 0.13), Vector3(sx + sw * 0.5, top + 1.28, c1.y - 0.13), Vector3(sx - sw * 0.5, top + 1.28, c1.y - 0.13), Houses.uv("sign_cafe"), Color(0.95, 0.95, 0.95), Color.WHITE)
	Snow.ridge(walls, Vector3(sx - sw * 0.5 - 0.1, top + 1.33, c1.y - 0.2), Vector3(sx + sw * 0.5 + 0.1, top + 1.33, c1.y - 0.2), Vector3.UP, 0.16, 0.08, 0.03, rng)
	sign_lamp(Vector3(sx, top + 1.6, c1.y + 0.4), Vector3(0, 0, 1))
	# windows on the side street, lit
	for wz: float in [88.4, 91.4]:
		det.quad_rect("facade_lit", Vector3(c0.x - 0.012, 1.0, wz + 0.6), Vector3(c0.x - 0.012, 1.0, wz - 0.6), Vector3(c0.x - 0.012, 2.4, wz - 0.6), Vector3(c0.x - 0.012, 2.4, wz + 0.6), Houses.uv("win_lit1"), lit, lit)
		spill(Vector3(c0.x, 0.0, wz), Vector3(0, 0, -1), Vector3(-1, 0, 0), 1.0, 1.8, 0.6)
	commit(walls, self, "CafeWalls", true, true)
	commit(det, self, "CafeFront", false, true)
	var inside := Kit.new()
	# indoors: nothing here holds snow (alpha 0 in the tint)
	inside.push_tint(Color(1, 1, 1, 0))
	# the marble floor of the room; the cellar's boards
	var room := Rect2(c0.x + 0.5, float(cellar[3]) + 0.5, c1.x - c0.x - 1.0, c1.y - float(cellar[3]) - 1.0)
	var back := Rect2(float(cellar[2]) + 0.5, c0.y + 0.5, c1.x - float(cellar[2]) - 1.0, float(cellar[3]) + 0.5 - c0.y - 0.5)
	for r: Rect2 in [room, back]:
		inside.quad_rect("tiles", Vector3(r.position.x, 0.02, r.end.y), Vector3(r.end.x, 0.02, r.end.y), Vector3(r.end.x, 0.02, r.position.y), Vector3(r.position.x, 0.02, r.position.y), Rect2(r.position.x * 0.39, r.position.y * 0.39, r.size.x * 0.39, r.size.y * 0.39), Color(0.9, 0.88, 0.84), Color(0.9, 0.88, 0.84))
	inside.push_tint(Color(0.42, 0.34, 0.26))
	inside.box("indoor", Vector3((float(cellar[0]) + float(cellar[2])) * 0.5, 0.02, (float(cellar[1]) + float(cellar[3])) * 0.5), Vector3(float(cellar[2]) - float(cellar[0]), 0.04, float(cellar[3]) - float(cellar[1])), Color.WHITE, Color.WHITE)
	inside.pop_tint()
	for item: Dictionary in sim.data.obstacles:
		if str(item.id) == "bar":
			var r := _m(item)
			inside.push_tint(Color(0.34, 0.2, 0.12))
			inside.box("indoor", Vector3(r.get_center().x, 0.52, r.get_center().y), Vector3(r.size.x, 1.04, r.size.y), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
			inside.pop_tint()
			inside.push_tint(Color(0.92, 0.9, 0.86))
			inside.box("indoor_stone", Vector3(r.get_center().x, 1.08, r.get_center().y), Vector3(r.size.x + 0.1, 0.06, r.size.y + 0.12), Color.WHITE, Color.WHITE)
			inside.pop_tint()
			# the back shelf against the wall, its bottles lit by the lamp over the bar
			var shelf_z := c0.y + 0.62
			inside.push_tint(Color(0.3, 0.18, 0.1))
			inside.box("indoor", Vector3(r.get_center().x, 1.2, shelf_z), Vector3(r.size.x, 2.2, 0.24), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
			inside.pop_tint()
			inside.quad_rect("facade_lit", Vector3(r.position.x + 0.3, 1.1, shelf_z + 0.13), Vector3(r.end.x - 0.3, 1.1, shelf_z + 0.13), Vector3(r.end.x - 0.3, 2.1, shelf_z + 0.13), Vector3(r.position.x + 0.3, 2.1, shelf_z + 0.13), Houses.uv_part("door_shop_lit", 0.05, 0.95, 0.25, 0.7), Color(0.9, 0.75, 0.55), Color(0.9, 0.75, 0.55))
	for t: Vector2 in [Vector2(70.0, 86.5), Vector2(74.5, 88.0), Vector2(70.5, 91.5), Vector2(76.5, 91.5), Vector2(64.0, 91.0), Vector2(60.0, 89.0)]:
		inside.lathe("steel", Vector3(t.x, 0.0, t.y), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.04, 0.06), Vector2(0.04, 0.7)]), 8, Color(0.12, 0.12, 0.12), Color(0.2, 0.2, 0.2))
		inside.push_tint(Color(0.92, 0.9, 0.86))
		inside.lathe("indoor_stone", Vector3(t.x, 0.7, t.y), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.38, 0.0), Vector2(0.38, 0.05), Vector2(0.0, 0.05)]), 12, Color.WHITE, Color.WHITE)
		inside.pop_tint()
		for a: float in [0.6, 2.4, 4.2]:
			var cp := Vector3(t.x + cos(a) * 0.62, 0.0, t.y + sin(a) * 0.62)
			inside.push_tint(Color(0.3, 0.2, 0.12))
			inside.box("indoor", cp + Vector3(0, 0.45, 0), Vector3(0.4, 0.05, 0.4), Color.WHITE, Color.WHITE)
			inside.box("indoor", cp + Vector3(0, 0.22, 0), Vector3(0.36, 0.44, 0.36), Color(0.6, 0.6, 0.6), Color.WHITE)
			inside.pop_tint()
	# the cellar: barrels and crates, a bare bulb
	for i: int in range(5):
		_props.barrel(inside, Vector3(float(cellar[0]) + 0.6 + float(i) * 0.75, 0.0, float(cellar[1]) + 0.55), Color(0.45, 0.32, 0.22), 0.0)
	_props.crate(inside, Vector3(float(cellar[2]) - 0.9, 0.0, float(cellar[3]) - 0.8), Vector3(0.9, 0.7, 0.8), 0.2)
	# pendant lamps over the room
	for at: Vector3 in [Vector3(64.0, 2.9, 89.5), Vector3(73.0, 2.9, 89.0), Vector3(73.5, 2.9, 83.5)]:
		inside.lathe("steel", at + Vector3(0, 0.1, 0), PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.12, 0.16), Vector2(0.02, 0.22)]), 10, Color(0.2, 0.3, 0.24), Color(0.3, 0.4, 0.32))
		inside.lathe("decobulb", at, PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.09, 0.0), Vector2(0.08, 0.08)]), 8)
		pool(Vector3(at.x, 0.0, at.z), 3.2, Color(1.0, 0.66, 0.36) * 0.25)
	inside.pop_tint()
	commit(inside, self, "CafeInside", true)
	fade_points.append(Vector3(72.0, 0.9, 88.0))
	for at: Vector3 in [Vector3(64.0, 2.75, 89.5), Vector3(73.0, 2.75, 89.0), Vector3(61.0, 2.6, 83.0)]:
		var lamp := add_lamp(at, LAMP, 1.6, 8.0, false, 0.5, 0.5)
		lamp.name = "CafeLamp"

## A striped canvas awning over a window: sloping out from the wall, a skin of snow on it.
func _awning(k: Kit, a: Vector3, bb: Vector3, depth: float, cell: String) -> void:
	var out := Vector3(0, -0.45, depth) if absf(a.z - bb.z) < 0.01 else Vector3(-depth, -0.45, 0)
	k.quad_rect("facade_cut", a + out, bb + out, bb, a, Houses.uv(cell), Color(0.8, 0.8, 0.8), Color.WHITE)
	var drop := Vector3(0, -0.28, 0)
	k.quad_rect("facade_cut", bb + out + drop, a + out + drop, a + out, bb + out, Houses.uv_part(cell, 0.0, 1.0, 0.7, 1.0), Color(0.8, 0.8, 0.8), Color.WHITE)
	var up := Vector3(0, 0.025, 0)
	var along := (bb - a).normalized()
	var n := along.cross(-out).normalized()
	if n.y < 0.0: n = -n
	Snow.slope(k, a + out * 0.95 + along * 0.05, bb + out * 0.95 - along * 0.05, a + along * 0.05 + up, bb - along * 0.05 + up, n, 0.1, 0.12, rng)

	# the cellar door: its own node, hinged at the west jamb (world.gd swings it open when the rules open it)
	var d: Dictionary = sim.data.door
	var dr := _m(d)
	gate = Node3D.new()
	gate.name = "CellarDoor"
	gate.position = Vector3(dr.position.x, 0.0, dr.get_center().y)
	add_child(gate)
	var leaf := Kit.new()
	leaf.push_tint(Color(0.42, 0.3, 0.2))
	leaf.box("planks", Vector3(dr.size.x * 0.5, 1.05, 0.0), Vector3(dr.size.x - 0.05, 2.1, 0.08), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	leaf.pop_tint()
	leaf.box("steel", Vector3(dr.size.x - 0.25, 1.05, 0.06), Vector3(0.08, 0.16, 0.04), IRON, IRON)
	_commit(leaf, gate, "DoorLeaf", true)

# ---------------------------------------------------------------------------------------------------------------
# The cutting's bridges, Lechuza's ladder, the tram
# ---------------------------------------------------------------------------------------------------------------
func _build_bridges() -> void:
	var k := Kit.new()
	# the footbridge in the west: planks on iron joists, iron railings
	var fb: Array = w.get("footbridge", [30.0, 34.0])
	var x0: float = float(fb[0])
	var x1: float = float(fb[1])
	k.push_tint(Props.WOOD_GREY)
	k.box("planks", Vector3((x0 + x1) * 0.5, -0.06, (_cut.x + _cut.y) * 0.5), Vector3(x1 - x0, 0.12, _cut.y - _cut.x + 0.8), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	for x: float in [x0 + 0.05, x1 - 0.05]:
		k.box("steel", Vector3(x, -0.35, (_cut.x + _cut.y) * 0.5), Vector3(0.12, 0.5, _cut.y - _cut.x + 0.8), IRON, IRON)
		k.beam("steel", Vector3(x, 1.0, _cut.x - 0.4), Vector3(x, 1.0, _cut.y + 0.4), 0.05, 0.06, IRON, IRON)
		var z := _cut.x - 0.4
		while z <= _cut.y + 0.4:
			k.beam("steel", Vector3(x, 0.0, z), Vector3(x, 1.0, z), 0.04, 0.04, IRON, IRON)
			z += 1.2
	# the road bridge in the east: a stone deck with parapets
	var rb: Array = w.get("roadbridge", [160.0, 168.0])
	x0 = float(rb[0])
	x1 = float(rb[1])
	k.box("stone", Vector3((x0 + x1) * 0.5, -0.4, (_cut.x + _cut.y) * 0.5), Vector3(x1 - x0, 0.8, _cut.y - _cut.x + 0.6), Color(0.5, 0.5, 0.5), Color(0.85, 0.85, 0.85))
	for x: float in [x0 + 0.2, x1 - 0.2]:
		k.box("stone", Vector3(x, 0.45, (_cut.x + _cut.y) * 0.5), Vector3(0.4, 0.9, _cut.y - _cut.x + 0.6), Color(0.6, 0.6, 0.6), Color(0.9, 0.9, 0.9), Vector2.ZERO, Kit.UPRIGHT)
	commit(k, self, "Bridges", true)

func _build_ladder() -> void:
	var lad: Array = w.get("ladder", [104.0, 106.0])
	var x := (float(lad[0]) + float(lad[1])) * 0.5
	ladder_node = node("Ladder")
	var k := Kit.new()
	_props.ladder(k, Vector3(x, -_cut_depth, _cut.x + 1.1), Vector3(x, 0.6, _cut.x - 0.2), 0.5, Props.WOOD_GREY)
	_props.ladder(k, Vector3(x, -_cut_depth, _cut.y - 1.1), Vector3(x, 0.6, _cut.y + 0.2), 0.5, Props.WOOD_GREY)
	commit(k, ladder_node, "Mesh", true)
	ladder_node.visible = false

## The tram standing on the avenue's rails by the café (the rules' screen to stand behind), and the rails themselves.
func _build_tram() -> void:
	var k := Kit.new()
	var rails: Array = w.get("rails", [101.5, 103.5])
	var mid: Array = w.get("midSt", [120.0, 126.0])
	var south: Array = w.get("southSt", [38.0, 46.0])
	for z: Variant in rails:
		for dz: float in [-0.72, 0.72]:
			k.box("steel", Vector3(float(sim.data.width) / 64.0, 0.02, float(z) + dz), Vector3(float(sim.data.width) / 32.0 + 120.0, 0.04, 0.07), IRON, Color(0.4, 0.4, 0.4))
	for x: float in [float(mid[0]) + 1.5, float(mid[1]) - 1.5]:
		for dx: float in [-0.72, 0.72]:
			k.box("steel", Vector3(x + dx, 0.02, (float(south[0]) + float(rails[0])) * 0.5), Vector3(0.07, 0.04, float(rails[0]) - float(south[0])), IRON, Color(0.4, 0.4, 0.4))
	commit(k, self, "TramRails", false)
	for bush: Dictionary in sim.data.bushes:
		if str(bush.get("kind", "")) != "tram": continue
		_tram(_m(bush))

## The tram standing on the avenue (the rules' screen to stand behind): a car of the fifties in an invented company's
## dark green and cream, rounded at both ends, its windows lit, the destination board over the motorman's window, a
## clerestory roof under a long cap of snow, the trolley pole up to the wire.
func _tram(r: Rect2) -> void:
	var c := r.get_center()
	var t := Kit.new()
	var td := Kit.new()
	var L := (r.size.x - 0.6) * 0.5
	var hw := 1.2
	var green := Houses.hexc("2f4f3a")
	var cream := Houses.hexc("d9cca6")
	var plan := PackedVector2Array([Vector2(-L, 0.75), Vector2(-L + 0.45, hw), Vector2(L - 0.45, hw), Vector2(L, 0.75), Vector2(L, -0.75), Vector2(L - 0.45, -hw), Vector2(-L + 0.45, -hw), Vector2(-L, -0.75)])
	var lit := Color(1.0, 0.86, 0.62)
	for i: int in range(plan.size()):
		var a := plan[i]
		var bb := plan[(i + 1) % plan.size()]
		var o := Vector3(c.x + a.x, 0.0, c.y + a.y)
		var right := Vector3(bb.x - a.x, 0.0, bb.y - a.y)
		var width := right.length()
		right = right / width
		var nrm := Vector3(-right.z, 0.0, right.x)
		var long := width > 3.0
		var openings: Array = []
		if long:
			var n := int(floor((width - 0.6) / 1.15))
			for j: int in range(n):
				openings.append(Rect2(0.3 + float(j) * (width - 0.6) / float(n) + 0.08, 0.2, (width - 0.6) / float(n) - 0.16, 0.95))
		elif absf(a.x) > L - 0.01 and absf(bb.x) > L - 0.01:
			openings.append(Rect2(0.15, 0.2, width - 0.3, 0.95))
		t.push_tint(green)
		t.wall("stucco", o + Vector3(0, 0.6, 0), right, width, 1.05, [], (a.x + a.y), 0.0, 0.0, Color(0.6, 0.6, 0.6), Color.WHITE, 0.3, 0.0)
		t.pop_tint()
		t.push_tint(cream)
		t.wall("stucco", o + Vector3(0, 1.65, 0), right, width, 1.35, openings, (a.x + a.y), 1.0, 0.06, Color.WHITE, Color(0.85, 0.85, 0.85), 0.0, 0.2)
		t.pop_tint()
		t.push_tint(Color(0.82, 0.7, 0.3))
		t.quad_m("stucco", o + Vector3(0, 1.6, 0) + nrm * 0.012, o + right * width + Vector3(0, 1.6, 0) + nrm * 0.012, o + right * width + Vector3(0, 1.68, 0) + nrm * 0.012, o + Vector3(0, 1.68, 0) + nrm * 0.012)
		t.pop_tint()
		for op: Rect2 in openings:
			var p0 := o + right * op.position.x + Vector3(0, 1.65 + op.position.y, 0) - nrm * 0.05
			td.quad_rect("facade_lit", p0, p0 + right * op.size.x, p0 + right * op.size.x + Vector3(0, op.size.y, 0), p0 + Vector3(0, op.size.y, 0), Houses.uv("tram_win_lit"), lit, lit)
	# the roof: eaves round the body, the clerestory along the middle, snow on it all
	t.push_tint(Color(0.42, 0.42, 0.4))
	t.box("corrugated", Vector3(c.x, 3.05, c.y), Vector3(L * 2.0 - 0.3, 0.12, hw * 2.0 + 0.12), Color(0.7, 0.7, 0.7), Color.WHITE)
	t.box("corrugated", Vector3(c.x, 3.28, c.y), Vector3(L * 2.0 - 2.4, 0.36, 1.2), Color(0.7, 0.7, 0.7), Color.WHITE)
	t.pop_tint()
	for s2: float in [-1.0, 1.0]:
		var x := c.x - L + 1.3
		while x < c.x + L - 1.4:
			td.quad_rect("facade_lit", Vector3(x, 3.14, c.y + s2 * 0.61), Vector3(x + 0.6 * s2, 3.14, c.y + s2 * 0.61), Vector3(x + 0.6 * s2, 3.38, c.y + s2 * 0.61), Vector3(x, 3.38, c.y + s2 * 0.61), Houses.uv("tram_win_lit"), lit * 0.8, lit * 0.8)
			x += 0.9
	Snow.box_top(t, Vector3(c.x, 3.46, c.y), Vector2(L * 2.0 - 2.5, 1.25), 0.16, rng)
	Snow.ridge(t, Vector3(c.x - L + 0.5, 3.11, c.y + 0.92), Vector3(c.x + L - 0.5, 3.11, c.y + 0.92), Vector3.UP, 0.55, 0.12, 0.05, rng, 0.5, true)
	Snow.ridge(t, Vector3(c.x - L + 0.5, 3.11, c.y - 0.92), Vector3(c.x + L - 0.5, 3.11, c.y - 0.92), Vector3.UP, 0.55, 0.12, 0.05, rng, 0.5, true)
	# the destination boards at both ends, the headlamps, the lifeguard
	for e: float in [-1.0, 1.0]:
		var ex := c.x + e * (L + 0.01)
		var a2 := Vector3(ex, 2.85, c.y - 0.65 * e)
		var b2 := Vector3(ex, 2.85, c.y + 0.65 * e)
		td.quad_rect("facade_lit", a2, b2, b2 + Vector3(0, 0.26, 0), a2 + Vector3(0, 0.26, 0), Houses.uv("tram_dest"), Color(1.0, 0.92, 0.75), Color(1.0, 0.92, 0.75))
		t.lathe("decobulb", Vector3(ex + e * 0.02, 1.3, c.y), PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.12, -0.08), Vector2(0.12, 0.08)]), 8)
		t.box("steel", Vector3(ex + e * 0.35, 0.35, c.y), Vector3(0.5, 0.08, 2.0), IRON, IRON * 1.4)
	# trucks and wheels under the body
	for wx: float in [c.x - L * 0.55, c.x + L * 0.55]:
		t.box("steel", Vector3(wx, 0.45, c.y), Vector3(2.2, 0.35, 1.8), IRON, IRON * 1.3)
		for dx: float in [-0.7, 0.7]:
			for s3: float in [-0.75, 0.75]:
				t.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx + dx, 0.38, c.y + s3)))
				t.lathe("steel", Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.38, 0.1), Vector2(0.0, 0.1)]), 10, IRON, IRON * 1.3)
				t.pop()
	# the trolley pole, up to the wire over its track
	var rails: Array = w.get("rails", [101.5, 103.5])
	var wire_z: float = float(rails[0]) if absf(float(rails[0]) - c.y) < absf(float(rails[1]) - c.y) else float(rails[1])
	var base := Vector3(c.x + L * 0.35, 3.48, c.y)
	t.box("steel", base, Vector3(0.6, 0.12, 0.5), IRON, IRON)
	t.beam("steel", base, Vector3(c.x - L * 0.25, 5.58, wire_z), 0.05, 0.05, IRON, IRON * 1.4)
	var node3 := node("Tram", Vector3.ZERO)
	commit(t, node3, "Car", true, true)
	commit(td, node3, "Lights", false, true)
	spill(Vector3(c.x, 0.0, c.y + hw), Vector3(1, 0, 0), Vector3(0, 0, 1), L * 1.6, 2.2, 0.45)
	spill(Vector3(c.x, 0.0, c.y - hw), Vector3(-1, 0, 0), Vector3(0, 0, -1), L * 1.6, 2.2, 0.45)

# ---------------------------------------------------------------------------------------------------------------
# The quay, the boat shed and Biguá's boat
# ---------------------------------------------------------------------------------------------------------------
func _build_quay() -> void:
	var solid := Kit.new()
	var flat := Kit.new()
	var site := Site.new(_props, 19580720)
	var n := 0
	for item: Dictionary in sim.data.obstacles:
		if str(item.kind) != "crates": continue
		var r := _m(item)
		var count := maxi(1, int(round(r.size.x / 2.2)))
		for i: int in range(count):
			var at := Vector3(r.position.x + (float(i) + 0.5) * r.size.x / float(count), 0.0, r.get_center().y)
			site.crate_stack(solid, flat, at, n % 2)
			n += 1
	for bush: Dictionary in sim.data.bushes:
		var kind := str(bush.get("kind", ""))
		var r := _m(bush)
		match kind:
			"coal":
				# the coal heap under its cap of snow
				solid.push_tint(Color(0.16, 0.15, 0.15))
				solid.lathe("concrete", Vector3(r.get_center().x, 0.0, r.get_center().y), PackedVector2Array([Vector2(minf(r.size.x, r.size.y) * 0.62, 0.0), Vector2(minf(r.size.x, r.size.y) * 0.45, 0.6), Vector2(0.4, 1.3), Vector2(0.0, 1.4)]), 12, Color(0.13, 0.12, 0.12), Color(0.2, 0.19, 0.18))
				solid.pop_tint()
			"hulls":
				# boats drawn up and turned over for the winter
				for i: int in range(2):
					var at := Vector3(r.position.x + 1.4 + float(i) * 2.4, 0.55, r.get_center().y)
					solid.push(Transform3D(Basis(Vector3.BACK, PI) * Basis(Vector3.UP, 0.05 * float(i)), at))
					site.boat(solid, Vector3.ZERO, 0.0, 0.0)
					solid.pop()
			"reeds":
				for i: int in range(int(r.get_area() * 2.5)):
					var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0.0, rng.randf_range(r.position.y, r.end.y))
					var lean := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(1.0, 1.7), rng.randf_range(-0.25, 0.25))
					solid.beam("burlap", p, p + lean, 0.03, 0.03, Color(0.3, 0.28, 0.2), Color(0.55, 0.5, 0.36))
			"scrub", "doorway":
				if kind == "doorway":
					# a dark doorway: the step and the recess the rules count as cover
					flat.decal(Kit.DECAL["blob"], r.get_center().x, r.get_center().y, r.size * 1.1, 0.0, Color(0.03, 0.03, 0.04, 0.55))
				else:
					for i: int in range(maxi(3, int(r.get_area() * 0.4))):
						var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0.0, rng.randf_range(r.position.y, r.end.y))
						solid.push_tint(Color(0.28, 0.32, 0.24))
						solid.lathe("burlap", p, PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.55, 0.35), Vector2(0.3, 0.75), Vector2(0.0, 0.8)]), 7, Color.WHITE, Color.WHITE)
						solid.pop_tint()
	# the slip down from the boat shed into the river
	var boat_x: Array = w.get("boat", [42.0, 48.0])
	var shed: Array = w.get("boatShed", [36.0, 104.0, 50.0, 108.0])
	solid.push_tint(Props.WOOD_GREY)
	solid.box("planks", Vector3((float(boat_x[0]) + float(boat_x[1])) * 0.5, -0.9, _river.x + 0.6), Vector3(3.2, 0.12, 3.6), Color(0.5, 0.5, 0.5), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	solid.pop_tint()
	commit(solid, self, "QuayProps", true)
	_commit(flat, self, "QuayFlat", false)
	_sign(Vector3((float(shed[0]) + float(shed[2])) * 0.5, 3.0, float(shed[3]) + 0.06), Vector3(0, 0, 1), "BOTES", 2.0)

## Biguá's boat: drawn up on the slip until he launches it, then on the water under him wherever he rows it.
func _build_boat() -> void:
	var boat_x: Array = w.get("boat", [42.0, 48.0])
	_boat_at = Vector3((float(boat_x[0]) + float(boat_x[1])) * 0.5, WATER_Y, _river.x + 1.6)
	boat = node("Boat", _boat_at, PI)
	var k := Kit.new()
	var site := Site.new(_props, 19580721)
	site.boat(k, Vector3.ZERO, 0.0, 0.0)
	# two oars across the thwarts
	for s: float in [-0.5, 0.5]:
		k.beam("planks", Vector3(-0.9, 0.42, s), Vector3(0.9, 0.42, s * 1.6), 0.05, 0.04, Props.WOOD_GREY, Props.WOOD_GREY)
	commit(k, boat, "Hull", true)

# ---------------------------------------------------------------------------------------------------------------
# The transporter bridge
# ---------------------------------------------------------------------------------------------------------------
## The transporter bridge (boca_bridge.gd): its towers and girder, the road bridge downstream in the haze, and the gondola
## (with its trolley and cables) as its own node, which rides across with whoever is on it.
func _build_transporter() -> void:
	var g: Array = w.get("gondola", [146.0, 154.0])
	var gx0: float = float(g[0]) - 0.5
	var gx1: float = float(g[1]) + 0.5
	var bridge := Bridge.new(self, g, _river, WATER_Y)
	bridge.build()
	bridge.road_bridge(float(sim.data.width) / 32.0 + 4.0)
	gondola_z = _river.x + 2.6
	gondola = node("Gondola", Vector3((gx0 + gx1) * 0.5, 0.0, gondola_z))
	var gk := Kit.new()
	var gd := Kit.new()
	var half := Vector2((gx1 - gx0) * 0.5 - 0.7, 2.4)
	var lamps := bridge.gondola(gk, gd, half)
	commit(gk, gondola, "Gondola", true, false)
	commit(gd, gondola, "GondolaLights", false, false)
	for at: Vector3 in lamps: _halo(at, Color(1.0, 0.8, 0.55), 0.9, gondola)
	# lamps on the towers' heads and along the girder, red lights at its ends for the river traffic
	var k := Kit.new()
	for z: float in [_river.x - 0.75, _river.y + 0.75]:
		for x: float in [gx0, gx1]:
			var at := Vector3(x, Bridge.LOW + 0.4, z)
			k.lathe("decobulb", at, PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.12, 0.0), Vector2(0.1, 0.12)]), 8)
			_halo(at, Color(1.0, 0.78, 0.5), 1.8)
	for z: float in [bridge.z_north, bridge.z_south]:
		for x: float in [gx0, gx1]:
			_halo(Vector3(x, Bridge.HIGH + 0.3, z), Color(1.0, 0.22, 0.12), 1.3)
	var zz := bridge.z_north + 4.0
	while zz < bridge.z_south - 3.0:
		_halo(Vector3((gx0 + gx1) * 0.5, Bridge.LOW - 0.2, zz), Color(1.0, 0.8, 0.55), 0.9)
		k.lathe("decobulb", Vector3((gx0 + gx1) * 0.5, Bridge.LOW - 0.2, zz), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.08, 0.0), Vector2(0.06, 0.08)]), 6)
		zz += 6.0
	commit(k, self, "TransporterLamps", false)

# ---------------------------------------------------------------------------------------------------------------
# The river launch, the far bank, the lamps
# ---------------------------------------------------------------------------------------------------------------
## The launch moored mid-river: a low hull, the wheelhouse, and on its roof the searchlight that turns with its crew.
func _build_launch() -> void:
	var at: Array = w.get("launch", [70.0, 124.0])
	var guard: Dictionary = {}
	for g: Dictionary in sim.data.guards:
		if str(g.get("kind", "")) == "searchlight": guard = g
	var deck := float(guard.get("elevation", 0.6))
	var base := Vector3(float(at[0]), WATER_Y, float(at[1]))
	var hull := Kit.new()
	var grey := Color(0.3, 0.33, 0.35)
	hull.push_at(base, 0.0)
	hull.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.4, -0.5), Vector2(1.1, -0.2), Vector2(1.25, 0.8), Vector2(1.2, 0.85)]), 14, grey * 0.6, grey)
	hull.pop()
	hull.push(Transform3D(Basis.from_scale(Vector3(3.2, 1.0, 1.0)), base))
	hull.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.35, -0.5), Vector2(1.0, -0.2), Vector2(1.1, 0.8), Vector2(0.0, 0.82)]), 14, grey * 0.6, grey)
	hull.pop()
	hull.push_tint(Color(0.55, 0.55, 0.52))
	hull.box("siding", Vector3(base.x - 0.6, (WATER_Y + 0.8 + deck) * 0.5, base.z), Vector3(2.4, deck - WATER_Y - 0.8, 1.9), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	hull.pop_tint()
	hull.box("steel", Vector3(base.x - 0.6, deck - 0.05, base.z), Vector3(2.6, 0.1, 2.1), grey, grey)
	commit(hull, self, "Launch", true)
	var rig := Node3D.new()
	rig.name = "SearchlightRig"
	rig.position = Vector3(base.x - 0.1, deck, base.z)
	add_child(rig)
	var yoke := Kit.new()
	yoke.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.12, 0.15), Vector2(0.1, 0.55)]), 10, IRON, IRON)
	_commit(yoke, rig, "Yoke", true)
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.position = Vector3(0, 0.8, 0)
	tilt.rotation.z = -0.2
	rig.add_child(tilt)
	var drum := Kit.new()
	drum.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO))
	drum.lathe("steel", Vector3(0, -0.3, 0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.28, 0.08), Vector2(0.3, 0.55), Vector2(0.27, 0.56)]), 14, IRON, IRON * 1.6)
	drum.pop()
	_commit(drum, tilt, "Drum", true)
	var glass := Kit.new()
	glass.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO))
	glass.disc("bulb", Vector3(0, 0.26, 0), 0.27, 14, Rect2(0, 0, 0.01, 0.01))
	glass.pop()
	var lens: MeshInstance3D = _commit(glass, tilt, "Lens", false)
	set_searchlight(rig, Vector3(0.28, 0, 0), lens)
	# the launch's beam reaches about as far as its crew sees (the rules' range)
	searchlight_light.spot_range = float(guard.get("range", 1050.0)) / 32.0 + 2.0
	searchlight_beam.set_meta("no_batch", true)

## The far bank: the friends' cart at the end of the lane.
func _build_far_bank() -> void:
	var cart: Array = w.get("cart", [98.4, 148.0, 101.6, 150.0])
	var r := Rect2(float(cart[0]), float(cart[1]), float(cart[2]) - float(cart[0]), float(cart[3]) - float(cart[1]))
	var k := Kit.new()
	var c := r.get_center()
	k.push_tint(Props.WOOD_GREY)
	k.box("planks", Vector3(c.x, 0.9, c.y), Vector3(r.size.x - 0.4, 0.12, r.size.y - 0.2), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	for s: float in [-1.0, 1.0]:
		k.box("planks", Vector3(c.x + s * (r.size.x * 0.5 - 0.25), 1.15, c.y), Vector3(0.06, 0.4, r.size.y - 0.2), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		k.beam("planks", Vector3(c.x + s * 0.5, 0.9, r.position.y + 0.2), Vector3(c.x + s * 0.55, 0.5, r.position.y - 2.0), 0.08, 0.08, Props.WOOD_GREY, Props.WOOD_GREY)
	k.pop_tint()
	for s: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(c.x + s * (r.size.x * 0.5 - 0.1), 0.62, c.y)))
		k.lathe("planks", Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.62, 0.1), Vector2(0.0, 0.1)]), 14, Props.WOOD_GREY, Props.WOOD_GREY)
		k.pop()
	commit(k, self, "Cart", true)

## The quay's lamps (on the board: they die when Lechuza cuts it), the road bridge's lamp (another supply), the lamp
## column with the board, a lamp over the Guardia's door. Lamps stand only where the rules light the ground.
func _build_lamps() -> void:
	for spot: Array in w.get("lamps", []):
		_lamp_post(Vector3(float(spot[0]), 0.0, float(spot[1])), true)
	var bl: Array = w.get("bridgeLamp", [])
	if bl.size() == 2: _lamp_post(Vector3(float(bl[0]), 0.0, float(bl[1])), false)
	# the column with the board at the foot of the tram street: its own lamp is on the board too
	var board := Vector3(float(sim.data.radio.x) / 32.0, 0.0, float(sim.data.radio.y) / 32.0 - 0.8)
	var k := Kit.new()
	k.lathe("steel", board, PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.2, 0.3), Vector2(0.11, 0.5), Vector2(0.08, 4.4), Vector2(0.04, 4.5)]), 10, IRON * 0.6, IRON * 1.2)
	k.box("steel", board + Vector3(0, 1.4, 0.16), Vector3(0.36, 0.5, 0.14), Color(0.25, 0.3, 0.28), Color(0.3, 0.36, 0.33))
	commit(k, self, "LampBoard", true)
	var guardia: Array = w.get("guardia", [178.0, 46.0, 200.0, 64.0])
	var door := Vector3(float(guardia[0]) - 0.25, 3.1, (float(guardia[1]) + float(guardia[3])) * 0.5)
	var wl := Kit.new()
	_props.wall_lamp(wl, door, -PI * 0.5)
	commit(wl, self, "GuardiaLamp", false)
	add_lamp(door + Vector3(-0.3, -0.2, 0), LAMP, 1.6, 6.0, false, 0.7, 0.8)

## The ground the board's lamps light (the rules' powered light), darkened when they die: under a blue hour sky the
## snow stays pale, so without this the quay would hardly change when Lechuza cuts the board. One mesh, a soft-edged
## quad over each lit rect, shown only while the lamps are out (or flickering).
var _shade: MeshInstance3D
func _build_dark_shade() -> void:
	var k := Kit.new()
	for f: Array in sim.data.get("floodlit", []):
		if f.size() < 5 or str(f[4]) != "powered": continue
		var lit := Rect2(float(f[0]) / 32.0, float(f[1]) / 32.0, float(f[2]) / 32.0, float(f[3]) / 32.0)
		var outer := lit.grow(1.5)
		var inner := lit.grow(-2.5)
		var y := 0.12
		# a solid middle and a border fading out to nothing (vertex alpha), so the dark has no edge
		var o4 := [Vector3(outer.position.x, y, outer.end.y), Vector3(outer.end.x, y, outer.end.y), Vector3(outer.end.x, y, outer.position.y), Vector3(outer.position.x, y, outer.position.y)]
		var i4 := [Vector3(inner.position.x, y, inner.end.y), Vector3(inner.end.x, y, inner.end.y), Vector3(inner.end.x, y, inner.position.y), Vector3(inner.position.x, y, inner.position.y)]
		var on := Color(1, 1, 1, 1)
		var off := Color(1, 1, 1, 0)
		k.quad4("shade", i4[0], i4[1], i4[2], i4[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, on, on, on, on)
		for i: int in range(4):
			var j := (i + 1) % 4
			k.quad4("shade", o4[i], o4[j], i4[j], i4[i], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, off, off, on, on)
	var material := ShaderMaterial.new()
	material.shader = ShadeShader
	materials["shade"] = material
	_shade = _commit(k, self, "BoardShade", false)
	if _shade != null:
		_shade.material_override = material
		_shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shade.visible = false

## The city's lamps beyond the map: the same columns along the avenue, the lane behind the north row, the street
## behind the far bank and the streets east and west, every one lit (another sector's supply). No light, only the
## lantern, its halo and the pool on the snow, so they cost nothing; none stands on the map's own ground, where only
## the rules say what is lit.
func _build_city_lamps() -> void:
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	var spots: Array[Vector3] = []
	for x: float in [-10.0, -28.0, -46.0, W + 10.0, W + 28.0, W + 46.0]:
		spots.append(Vector3(x, 0.0, 104.6))
	var x := -43.5
	while x < W + 50.0:
		spots.append(Vector3(x, 0.0, -6.7))
		spots.append(Vector3(x + 11.0, 0.0, H + 7.3))
		x += 26.0
	var z := -30.0
	while z < 96.0:
		if z < 26.0 or z > 42.0:
			spots.append(Vector3(-7.4, 0.0, z))
			spots.append(Vector3(W + 7.4, 0.0, z + 5.0))
		z += 24.0
	var kit := Kit.new()
	var dark := Color(0.13, 0.16, 0.15)
	var lite := Color(0.24, 0.28, 0.26)
	for foot: Vector3 in spots:
		kit.lathe("steel", foot, PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.18, 0.4), Vector2(0.09, 0.7), Vector2(0.08, 3.5), Vector2(0.06, 3.7)]), 6, dark, lite)
		var lantern := foot + Vector3(0, 3.7, 0)
		kit.lathe("decobulb", lantern, PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.17, 0.5), Vector2(0.0, 0.52)]), 4)
		kit.lathe("steel", lantern + Vector3(0, 0.5, 0), PackedVector2Array([Vector2(0.26, 0.0), Vector2(0.05, 0.3), Vector2(0.0, 0.4)]), 4, dark, lite)
		Snow.cone(kit, lantern + Vector3(0, 0.54, 0), 0.18, 0.18)
		_halo(lantern + Vector3(0, 0.28, 0), Color(1.0, 0.72, 0.44), 1.8)
		pool(foot + Vector3(0, 0, 0.3), 5.5, Color(1.0, 0.58, 0.26) * 0.5)
	commit(kit, self, "CityLamps", false)
	# the city's children were out too: snowmen and sleds on the pavements round the map, their tracks round them
	var play := Kit.new()
	var marks := Kit.new()
	for i: int in range(spots.size()):
		if i % 3 != 1: continue
		var foot: Vector3 = spots[i]
		var along := Vector3(1, 0, 0) if absf(foot.z - 104.6) < 0.1 or absf(foot.z + 6.7) < 0.1 or absf(foot.z - H - 7.3) < 0.1 else Vector3(0, 0, 1)
		var at := foot + along * 2.6
		houses._snowman(play, play, at, rng.randf_range(0.85, 1.1), false)
		kid_tracks(at, marks)
		if rng.randf() < 0.5: houses.sled(play, foot - along * 2.2, atan2(along.x, along.z) + rng.randf_range(-0.4, 0.4))
	commit(play, self, "CitySnowmen", true)
	_commit(marks, self, "CityTracks", false)

## A cast-iron lamp column of the city: a moulded base, a fluted shaft, a collar, and on top a four-sided glass lantern
## under a pointed cap that holds a cone of snow. The lantern's glass is the bulb: on the board, it dies with it.
func _lamp_post(foot: Vector3, powered: bool) -> void:
	var kit := Kit.new()
	var dark := Color(0.13, 0.16, 0.15)
	var lite := Color(0.24, 0.28, 0.26)
	kit.lathe("steel", foot, PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.24, 0.18), Vector2(0.19, 0.24), Vector2(0.19, 0.5), Vector2(0.13, 0.62), Vector2(0.1, 0.72), Vector2(0.085, 3.4), Vector2(0.11, 3.48), Vector2(0.11, 3.56), Vector2(0.07, 3.62), Vector2(0.07, 3.72)]), 10, dark, lite)
	var lantern := foot + Vector3(0, 3.72, 0)
	kit.box("steel", lantern + Vector3(0, 0.02, 0), Vector3(0.34, 0.04, 0.34), dark, lite)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		kit.beam("steel", lantern + Vector3(c.x * 0.15, 0.03, c.y * 0.15), lantern + Vector3(c.x * 0.19, 0.58, c.y * 0.19), 0.03, 0.03, dark, lite)
	kit.lathe("bulb", lantern + Vector3(0, 0.04, 0), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.17, 0.54), Vector2(0.0, 0.55)]), 4)
	kit.lathe("steel", lantern + Vector3(0, 0.56, 0), PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.27, 0.04), Vector2(0.06, 0.3), Vector2(0.02, 0.42), Vector2(0.0, 0.44)]), 4, dark, lite)
	Snow.cone(kit, lantern + Vector3(0, 0.6, 0), 0.19, 0.2)
	commit(kit, self, "LampPost", true)
	# (the grade is darker than the first pass's: the lamps burn harder so the lit quay still reads as lit)
	add_lamp(lantern + Vector3(0, 0.3, 0), LAMP, 4.4, 12.0, powered, 1.9, 1.3)
	# the lamp's light hanging in the damp air round it: a wide faint glow that goes out with it
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(7.5, 7.5)
	glow.mesh = quad
	glow.material_override = _fog_glow_material()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_meta("no_batch", true)
	(lamps[lamps.size() - 1].halo as Node3D).add_child(glow)
	pool(foot + Vector3(0, 0, 0.3), 7.0, Color(1.0, 0.58, 0.26) * 0.8, powered)

# ---------------------------------------------------------------------------------------------------------------
# Per frame
# ---------------------------------------------------------------------------------------------------------------
## The quay's lamps hang from the lamp board: cut it and they stutter and die. The road bridge's lamp, the Guardia's
## and the café's, and the launch's searchlight (her own dynamo), stay lit. (Vemork keeps all its lamps; the harbour
## loses its searchlight with the power: neither is La Boca.)
func _sync_power(dt: float, instant: bool) -> void:
	var cut: bool = bool(sim.radio_cut)
	if cut != _was_cut:
		_was_cut = cut
		_flicker = 0.0 if (instant or not cut) else 0.9
		# back on (a checkpoint from before the board was cut): every lamp at once
		if not cut: instant = true
	var level: float
	if _flicker > 0.0:
		_flicker = maxf(0.0, _flicker - dt)
		level = (1.0 if fposmod(_flicker * 13.0, 1.0) > 0.45 else 0.2) * smoothstep(0.0, 0.9, _flicker)
	else:
		level = 0.0 if cut else 1.0
	if absf(level - _power) < 0.001 and not instant: return
	_power = level
	for lamp: Dictionary in lamps:
		if not bool(lamp.powered): continue
		(lamp.light as OmniLight3D).light_energy = float(lamp.energy) * level
		(lamp.light as OmniLight3D).visible = level > 0.01
		(lamp.halo as Node3D).visible = level > 0.01
	bulb_material.emission_energy_multiplier = 6.0 * level
	bulb_material.albedo_color = Color(1.0, 0.78, 0.5).lerp(Color(0.25, 0.22, 0.2), 1.0 - level)
	if powered_pool_material != null: powered_pool_material.albedo_color = Color(1, 1, 1, level)
	if _shade != null:
		_shade.visible = level < 0.99
		(_shade.material_override as ShaderMaterial).set_shader_parameter("amount", 1.0 - level)

## The launch's searchlight: the harbour's, kept lit whatever the board does.
func _sync_searchlight(dt: float) -> void:
	if searchlight_rig == null or _searchlight_id == "": return
	var guard: Dictionary = sim.guard_by_id(_searchlight_id)
	if guard.is_empty(): return
	searchlight_rig.rotation.y = lerp_angle(searchlight_rig.rotation.y, -float(guard.angle), minf(1.0, dt * 12.0))
	var on: bool = not guard.state in sim.DOWN_STATES
	searchlight_light.visible = on
	searchlight_beam.visible = on

func update(dt: float, paused: bool) -> void:
	super.update(dt, paused)
	if street != null: street.update(0.0 if paused else dt)
	if ladder_node != null: ladder_node.visible = sim.rigged.has("ladder")
	_sync_gondola(dt)
	_sync_boat(dt)

## The gondola rides with whoever is on its run; with nobody aboard it stays where it was left (at the north landing
## until Hornero works it). A checkpoint from before that puts it back there.
func _sync_gondola(dt: float) -> void:
	if gondola == null: return
	var passage: Dictionary = sim.passage_by_id("gondola")
	if passage.is_empty(): return
	var r: Rect2 = sim.rect_of(passage)
	var lo := _river.x + 2.6
	var hi := _river.y - 2.6
	if not sim.rigged.has("gondola"):
		gondola_z = lo
	else:
		var sum := 0.0
		var count := 0
		var riders: Array = sim.units.duplicate()
		if sim.has_prisoner: riders.append(sim.prisoner)
		for actor: Dictionary in riders:
			var p := Vector2(float(actor.x), float(actor.y))
			if r.has_point(p):
				sum += p.y / 32.0
				count += 1
		if count > 0: gondola_z = clampf(sum / float(count), lo, hi)
	gondola.position.z = move_toward(gondola.position.z, gondola_z, maxf(dt, 0.0) * 4.0) if absf(gondola.position.z - gondola_z) < 6.0 else gondola_z

## Biguá's boat: on the slip until launched; on the water under him (and the one he takes) while he rows; left where he
## steps out of it.
func _sync_boat(_dt: float) -> void:
	if boat == null: return
	var passage: Dictionary = sim.passage_by_id("boat")
	if passage.is_empty(): return
	if not sim.rigged.has("boat"):
		boat.position = _boat_at + Vector3(0, 1.45, -0.4)
		boat.rotation = Vector3(-0.32, PI, 0.0)
		return
	var r: Rect2 = sim.rect_of(passage)
	var crew: Array = []
	for unit: Dictionary in sim.units:
		if r.has_point(Vector2(float(unit.x), float(unit.y))) and float(unit.y) / 32.0 > _river.x: crew.append(unit)
	if sim.has_prisoner and r.has_point(Vector2(float(sim.prisoner.x), float(sim.prisoner.y))) and float(sim.prisoner.y) / 32.0 > _river.x:
		crew.append(sim.prisoner)
	boat.rotation = Vector3(0.0, PI, 0.0)
	if crew.is_empty():
		if boat.position.y > WATER_Y + 0.5: boat.position = _boat_at
		return
	var sum := Vector2.ZERO
	for actor: Dictionary in crew: sum += Vector2(float(actor.x), float(actor.y)) / 32.0
	sum /= float(crew.size())
	boat.position = Vector3(sum.x, WATER_Y, clampf(sum.y, _river.x + 1.6, _river.y - 1.6))
