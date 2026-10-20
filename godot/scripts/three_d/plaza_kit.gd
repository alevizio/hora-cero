extends RefCounted
## The Plaza de Mayo kit: the square's landmarks as they stood on a snowy winter night in 1958, its street furniture,
## and unbranded Buenos Aires vehicles of the time, built procedurally as merged meshes (the structures kit's
## primitives, La Boca's snow), at La Boca's quality and under its blue-hour light.
##
## Use: var pk := PlazaKit.new(parent, snow, lit, seed), then call the builders with footprints in metres on the ground
## plane (Rect2: x = world x, y = world z) and the direction the main front faces (NORTH = -z, as on the game's maps),
## then pk.finish() once (it commits what is shared: lamp halos and light pools, the lamp posts, palms, trees and
## benches as multimeshes). Every builder returns the Node3D it made under `parent`, already placed.
##
## Every landmark is one node with two meshes: "Body" (the tiling surfaces of one array texture, plaza_walls.gdshader,
## one draw, casts shadows) and "Detail" (the atlas, plaza_detail.gdshader, one draw, no shadows): windows lit and dark,
## doors, signs, railings, fronds. Snow lies as geometry on every ledge (boca_snow.gd) and in the shader wherever a
## surface faces up; `snow` scales both (0 = a dry night). `lit` is the share of windows lit from inside.
##
## Facts from the research notes on Buenos Aires in 1958 (buenos_aires_1958_visuals.md):
## the Pirámide 18.76 m to the tip of its 3.6 m Liberty, no corner statues (removed 1912, back only in 2018), the sun on
## its east face and laurel crowns on the others; the Cabildo as restored in 1940 with five arches left in all and its
## tower rebuilt, red colonial tiles, iron window bars; the Casa Rosada pink, three storeys on Balcarce, Tamburini's
## central arch; eight Canary Island date palms; Avenida de Mayo's 24 m cornice line; tungsten light only (warm).
## Where the notes are thin the forms are from general knowledge of the buildings (said so at each builder).

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")
const Props = preload("res://scripts/three_d/plaza_kit_props.gd")
const Buildings = preload("res://scripts/three_d/plaza_kit_buildings.gd")
const Vehicles = preload("res://scripts/three_d/plaza_kit_vehicles.gd")
const WallsShader := preload("res://shaders/plaza_walls.gdshader")
const DetailShader := preload("res://shaders/plaza_detail.gdshader")
const FlagShader := preload("res://shaders/plaza_flag.gdshader")
const GrimeShader := preload("res://shaders/plaza_grime.gdshader")
const TEX := "res://assets/tex/plaza/"

## The directions a front can face (the game's maps: -z is north).
const NORTH := Vector3(0, 0, -1)
const SOUTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const WEST := Vector3(-1, 0, 0)

## Recommended footprints in metres (width along the main front x depth). The real ones are larger (the Casa Rosada's
## front on Balcarce is about 110 m); the builders fit whatever rect they are given, within reason.
const SIZE := {
	"casa_rosada": Vector2(96.0, 40.0), "cabildo": Vector2(30.0, 18.0), "catedral": Vector2(44.0, 60.0),
	"banco_nacion": Vector2(64.0, 44.0), "ministerios": Vector2(80.0, 30.0), "avenida_de_mayo": Vector2(120.0, 14.0),
	"subte_entrance": Vector2(3.0, 7.5), "piramide": Vector2(12.0, 12.0), "belgrano": Vector2(8.0, 4.0),
}

## The array texture's layers (tools/gen_plaza_textures.py LAYERS), and per layer: roughness (< 0: in the albedo's
## alpha), normal strength, metallic, specular, whether the alpha says where snow catches.
const WALL_LAYERS := ["render", "rustic", "ashlar", "marble", "teja", "slate", "metal", "bronze", "snow", "planks",
	"paint", "bark", "leaves", "rubber", "stucco", "stone"]
const LAYER_SPEC := {
	"render": [0.9, 0.8, 0.0, 0.4, 0.0], "rustic": [0.9, 1.0, 0.0, 0.4, 0.0], "ashlar": [0.88, 1.0, 0.0, 0.4, 0.0],
	"marble": [0.42, 0.6, 0.0, 0.5, 0.0], "teja": [0.8, 1.2, 0.0, 0.4, 1.0], "slate": [-1.0, 1.0, 0.0, 0.45, 0.0],
	"metal": [-1.0, 0.8, 0.35, 0.5, 0.0], "bronze": [0.5, 0.7, 0.12, 0.5, 0.0], "snow": [0.8, 0.5, 0.0, 0.35, 0.0],
	"planks": [0.9, 1.0, 0.0, 0.4, 0.0], "paint": [0.26, 0.3, 0.0, 0.7, 0.0], "bark": [0.95, 1.2, 0.0, 0.3, 0.0],
	"leaves": [0.6, 1.0, 0.0, 0.4, 0.0], "rubber": [0.9, 0.8, 0.0, 0.3, 0.0], "stucco": [0.93, 0.7, 0.0, 0.36, 0.0],
	"stone": [0.82, 0.9, 0.0, 0.42, 0.0],
}
## The atlas's uses (plaza_detail.gdshader), as keys.
const SOLID := "d_solid"
const CUT := "d_cut"
const LIT := "d_lit"
const GLOW := "d_glow"
const LEAF := "d_leaf"
const GLASS := "d_glass"
const DETAIL_MODES := {"d_solid": 0, "d_cut": 1, "d_lit": 2, "d_glow": 3, "d_leaf": 4, "d_glass": 5}

## The atlas (tools/gen_plaza_textures.py ATLAS): x, y, w, h in pixels of 2048 x 1024.
const ATLAS_SIZE := Vector2(2048.0, 1024.0)
const ATLAS := {
	"win_lit0": [0, 0, 128, 256], "win_lit1": [128, 0, 128, 256], "win_lit2": [256, 0, 128, 256],
	"win_lit3": [384, 0, 128, 256], "win_lit4": [512, 0, 128, 256],
	"win_dark0": [640, 0, 128, 256], "win_dark1": [768, 0, 128, 256], "win_dark2": [896, 0, 128, 256],
	"arch_lit0": [1024, 0, 128, 256], "arch_lit1": [1152, 0, 128, 256], "arch_dark0": [1280, 0, 128, 256],
	"modern_lit": [1408, 0, 128, 256], "modern_dark": [1536, 0, 128, 256],
	"reja_lit": [1664, 0, 128, 256], "reja_dark": [1792, 0, 128, 256], "shutter": [1920, 0, 128, 256],
	"door_panel": [0, 256, 128, 256], "door_gate_lit": [128, 256, 128, 256], "door_cabildo": [256, 256, 128, 256],
	"door_church": [384, 256, 128, 256], "door_bank_lit": [512, 256, 128, 256], "door_shop_lit": [640, 256, 128, 256],
	"arch_lit2": [768, 256, 128, 256], "arch_dark1": [896, 256, 128, 256],
	"frond0": [1024, 256, 256, 128], "frond1": [1024, 384, 256, 128], "twigs": [1280, 256, 256, 256],
	"papers": [1536, 256, 256, 128], "rail_ornate": [1536, 384, 256, 128],
	"fence_hoop": [1792, 256, 256, 64], "balustrade": [1792, 320, 128, 64], "grille": [1920, 320, 128, 64],
	"car_glass": [1792, 384, 128, 64], "bus_win_lit": [1920, 384, 128, 64], "tram_win_lit": [1792, 448, 128, 64],
	"shop_strip_lit": [1920, 448, 128, 64],
	"sign_subte": [0, 512, 512, 128], "sign_cafe": [512, 512, 512, 128], "sign_confiteria": [1024, 512, 512, 128],
	"sign_bar": [1536, 512, 512, 128],
	"filete_side": [0, 640, 256, 128], "filete_rear": [256, 640, 256, 128], "sign_soderia": [512, 640, 512, 128],
	"bus_dest": [1024, 640, 256, 64], "tram_dest": [1024, 704, 256, 64], "tram_company": [1280, 640, 256, 64],
	"kiosk_sign": [1280, 704, 256, 64], "clock": [1536, 640, 128, 128], "taxi_sign": [1664, 640, 128, 64],
	"libre": [1664, 704, 64, 64], "plate": [1728, 704, 64, 64], "sun_relief": [1792, 640, 128, 128],
	"laurel": [1920, 640, 128, 128],
	"cafe_lit": [0, 768, 256, 128], "shop_lit": [256, 768, 256, 128], "awning_cream": [512, 768, 256, 128],
	"awning_green": [768, 768, 256, 128], "relief": [1024, 768, 512, 128], "bus_num": [1536, 768, 128, 64],
	"plaque": [1536, 832, 128, 64], "headlamp": [1664, 768, 64, 64], "taillamp": [1728, 768, 64, 64],
	"hubcap": [1664, 832, 64, 64], "oculus_lit": [1728, 832, 64, 64], "dormer_lit": [1792, 768, 128, 128],
	"dormer_dark": [1920, 768, 128, 128],
	"glow": [0, 896, 64, 64], "white": [64, 896, 64, 64], "dark": [0, 960, 64, 64], "oculus_dark": [64, 960, 64, 64],
	"flag": [128, 896, 256, 128], "magazines": [384, 896, 256, 128], "tiles_lit": [640, 896, 128, 128],
	"tram_num": [768, 896, 128, 64], "grille_truck": [768, 960, 128, 64], "crate_side": [896, 896, 128, 64],
	"siphons": [896, 960, 128, 64], "cafe_glass": [1024, 896, 256, 128], "bench_iron": [1280, 896, 256, 128],
	"lamp_glass": [1536, 896, 64, 64], "spokes": [1600, 896, 64, 64],
	"frond_dry": [1664, 896, 256, 128], "bars": [1920, 896, 128, 128],
}

## Lamplight: tungsten at reduced voltage (the notes: 2,200-2,700 K, no mercury, no sodium).
const LAMP := Color(1.0, 0.72, 0.42)
const WARM := Color(1.0, 0.84, 0.62)
const IRON := Color(0.11, 0.12, 0.12)

static func hexc(h: String) -> Color:
	return Color.html(h).srgb_to_linear()

var root: Node3D
## 0 .. 1: how much snow lies (geometry and shader); 0 is a dry night.
var snow: float = 1.0
## 0 .. 1: the share of windows lit from inside.
var lit: float = 0.5
var rng := RandomNumberGenerator.new()
var materials: Dictionary = {}
## What each builder made: name -> {"triangles", "draws" (surfaces), "meshes", "instances"}.
var stats: Dictionary = {}
## Lamps the level may want real lights for: [world position, colour, strength 0..1, reach m].
var lights: Array = []
## The world transform of the piece being built (its node's), for what is gathered in world space.
var xf := Transform3D.IDENTITY
var props: Props
var buildings: Buildings
var vehicles: Vehicles

var _aliases: Dictionary = {}
var _saved_aliases: Dictionary = {}
var _halos: Array = []
var _pools := Kit.new()
var _lamp_posts: Array = []
var _palms: Array = []
var _trees: Array = []
var _benches: Array = []
var _snowmen: Array = []
var _trails: Array = []
var _flag_material: ShaderMaterial
## The layer the trims are drawn in (balustrades, window surrounds and pediments, balconies, archivolts): the render,
## unless a builder sets its own while it builds (the Casa Rosada: its cream stone).
var trim_layer := "render"
## The palms' crowns as committed (plaza_kit_props.gd sync_palms fades them): {node, index, at, radius, top, alpha, want}.
var palm_crowns: Array[Dictionary] = []

func _init(parent: Node3D, snow_amount: float = 1.0, lit_ratio: float = 0.5, seed_value: int = 1958) -> void:
	root = parent
	snow = clampf(snow_amount, 0.0, 1.0)
	lit = clampf(lit_ratio, 0.0, 1.0)
	rng.seed = seed_value
	for i: int in range(WALL_LAYERS.size()): _aliases[WALL_LAYERS[i]] = ["pwalls", i]
	for key: String in DETAIL_MODES: _aliases[key] = ["pdetail", DETAIL_MODES[key]]
	_make_materials()
	props = Props.new(self)
	buildings = Buildings.new(self)
	vehicles = Vehicles.new(self)

# ---------------------------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------------------------
func _make_materials() -> void:
	var macro: Texture2D = load("res://assets/tex/nature/macro_noise.png")
	var walls := ShaderMaterial.new()
	walls.shader = WallsShader
	walls.set_shader_parameter("albedo_tex", load(TEX + "pwalls_a.webp"))
	walls.set_shader_parameter("normal_tex", load(TEX + "pwalls_n.webp"))
	walls.set_shader_parameter("macro_tex", macro)
	var spec_arrays: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for name: String in WALL_LAYERS:
		var s: Array = LAYER_SPEC[name]
		for j: int in range(5): spec_arrays[j].append(float(s[j]))
	walls.set_shader_parameter("roughness", spec_arrays[0])
	walls.set_shader_parameter("normal_scale", spec_arrays[1])
	walls.set_shader_parameter("metallic", spec_arrays[2])
	walls.set_shader_parameter("specular", spec_arrays[3])
	walls.set_shader_parameter("catch_alpha", spec_arrays[4])
	walls.set_shader_parameter("snow_amount", snow)
	materials["pwalls"] = walls
	var atlas: Texture2D = load(TEX + "plaza_a.png")
	var detail := ShaderMaterial.new()
	detail.shader = DetailShader
	detail.set_shader_parameter("atlas", atlas)
	detail.set_shader_parameter("macro_tex", macro)
	detail.set_shader_parameter("snow_amount", snow)
	materials["pdetail"] = detail
	_flag_material = ShaderMaterial.new()
	_flag_material.shader = FlagShader
	_flag_material.set_shader_parameter("atlas", atlas)
	var r := uv("flag")
	_flag_material.set_shader_parameter("rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var grime_m := ShaderMaterial.new()
	grime_m.shader = GrimeShader
	grime_m.set_shader_parameter("grime", load(TEX + "grime.png"))
	materials["grime"] = grime_m
	materials["pool"] = _pool_material()
	var decal := StandardMaterial3D.new()
	decal.albedo_texture = load(Kit.TEX_DIR + "decal_a.png")
	decal.vertex_color_use_as_albedo = true
	decal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	decal.roughness = 1.0
	decal.metallic_specular = 0.0
	decal.render_priority = -1
	materials["decal"] = decal
	materials["halo"] = _halo_material()
	materials["fogglow"] = _fog_glow_material()

## Light thrown on the snow with no lamp to throw it: a soft disc, added to what is there (La Boca's pools).
func _pool_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.45, Color(1, 1, 1, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _halo_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.25, Color(1, 1, 1, 0.35))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.render_priority = 6
	return m

## A lamp's light in the damp air: a wide, faint, warm glow (La Boca's), added over everything.
func _fog_glow_material() -> StandardMaterial3D:
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
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = Color(1.0, 0.62, 0.32, 0.32)
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.disable_fog = true
	m.render_priority = 7
	return m

# ---------------------------------------------------------------------------------------------------------------
# Atlas, frames, committing
# ---------------------------------------------------------------------------------------------------------------
static func uv(cell: String) -> Rect2:
	var r: Array = ATLAS[cell]
	return Rect2((float(r[0]) + 1.0) / ATLAS_SIZE.x, (float(r[1]) + 1.0) / ATLAS_SIZE.y, (float(r[2]) - 2.0) / ATLAS_SIZE.x, (float(r[3]) - 2.0) / ATLAS_SIZE.y)

## A part of an atlas cell (u0..u1 across, v0..v1 down, 0..1 of the cell).
static func uv_part(cell: String, u0: float, u1: float, v0: float = 0.0, v1: float = 1.0) -> Rect2:
	var r := uv(cell)
	return Rect2(r.position.x + r.size.x * u0, r.position.y + r.size.y * v0, r.size.x * (u1 - u0), r.size.y * (v1 - v0))

## The local frame of a footprint: x along the main front from left to right as you face it, y up, z out of the front
## (the building stands at z < 0, its front on z = 0). Returns [transform, width, depth].
static func frame(rect: Rect2, facing: Vector3) -> Array:
	var f := Vector3(facing.x, 0.0, facing.z)
	if absf(f.x) >= absf(f.z): f = Vector3(signf(f.x) if f.x != 0.0 else 1.0, 0.0, 0.0)
	else: f = Vector3(0.0, 0.0, signf(f.z))
	var right := Vector3.UP.cross(f)
	var c := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var depth := absf(f.x) * rect.size.x + absf(f.z) * rect.size.y
	var width := absf(right.x) * rect.size.x + absf(right.z) * rect.size.y
	var origin := c + f * depth * 0.5 - right * width * 0.5
	return [Transform3D(Basis(right, Vector3.UP, f), origin), width, depth]

## A node placed at a point, turned so that its local +z looks along `face`.
static func placed(at: Vector3, facing: Vector3) -> Transform3D:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	if f.length_squared() < 0.5: f = SOUTH
	return Transform3D(Basis(Vector3.UP.cross(f), Vector3.UP, f), at)

## While a piece is built every kit writes its layers into the two shared surfaces (pwalls, pdetail).
func begin(piece_xf: Transform3D) -> void:
	_saved_aliases = Kit.aliases
	Kit.aliases = _aliases
	xf = piece_xf

func end() -> void:
	Kit.aliases = _saved_aliases
	xf = Transform3D.IDENTITY

## Commits a piece's body and detail kits as one node under the root (or `parent`), placed at `piece_xf`.
func piece(name: String, piece_xf: Transform3D, body: Kit, detail: Kit, parent: Node3D = null, shadows: bool = true) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.transform = piece_xf
	(parent if parent != null else root).add_child(node)
	var tris := body.triangle_count() + detail.triangle_count()
	var draws := 0
	var b := body.commit(node, materials, "Body", shadows)
	if b != null: draws += b.mesh.get_surface_count()
	var d := detail.commit(node, materials, "Detail", false)
	if d != null: draws += d.mesh.get_surface_count()
	_stat(name, tris, draws, (1 if b != null else 0) + (1 if d != null else 0))
	return node

func _stat(name: String, tris: int, draws: int, meshes: int, instances: int = 0) -> void:
	var key := name.rstrip("0123456789")
	var s: Dictionary = stats.get(key, {"triangles": 0, "draws": 0, "meshes": 0, "instances": 0, "count": 0})
	s.triangles += tris
	s.draws += draws
	s.meshes += meshes
	s.instances += instances
	s.count += 1
	stats[key] = s

func is_lit() -> bool:
	return rng.randf() < lit

func warm() -> Color:
	return Color(1.0, rng.randf_range(0.8, 0.94), rng.randf_range(0.58, 0.78)) * rng.randf_range(0.78, 1.05)

func window_cell(lit_now: bool) -> String:
	return ("win_lit%d" % rng.randi_range(0, 4)) if lit_now else ("win_dark%d" % rng.randi_range(0, 2))

# ---------------------------------------------------------------------------------------------------------------
# Snow (boca_snow.gd, scaled by the kit's snow)
# ---------------------------------------------------------------------------------------------------------------
func ridge(k: Kit, a: Vector3, b: Vector3, up: Vector3, width: float, height: float, lip: float = 0.04, droop: float = 0.5, caps: bool = false) -> void:
	if snow < 0.04: return
	Snow.ridge(k, a, b, up, width, height * (0.4 + 0.6 * snow), lip, rng, droop, caps)

func pillow(k: Kit, poly: PackedVector2Array, y: float, t: float, edge: float) -> void:
	if snow < 0.04: return
	Snow.pillow(k, poly, y, t * snow, edge, rng)

func box_top(k: Kit, centre_top: Vector3, size: Vector2, t: float) -> void:
	if snow < 0.04: return
	Snow.box_top(k, centre_top, size, t * snow, rng)

func slope(k: Kit, ea: Vector3, eb: Vector3, ra: Vector3, rb: Vector3, n: Vector3, t: float, nose: float) -> void:
	if snow < 0.04: return
	Snow.slope(k, ea, eb, ra, rb, n, t * snow, nose * snow, rng)

func drift(k: Kit, a: Vector3, b: Vector3, out: Vector3, h: float, d: float) -> void:
	if snow < 0.04: return
	Snow.drift(k, a, b, out, h * snow, d * (0.5 + 0.5 * snow), rng)

## A soft bank of snow lying along the ground from a to b: rising from nothing at both ends, `h` high at its crown,
## `d` out to either side, a little uneven (the kit's own: rounder than a drift against a wall).
func mound(k: Kit, a: Vector3, b: Vector3, h: float, d: float) -> void:
	if snow < 0.04: return
	var along := b - a
	var length := along.length()
	if length < 0.1: return
	var across := along.cross(Vector3.UP).normalized()
	var prof: Array[Vector2] = [Vector2(-d, -0.03), Vector2(-d * 0.62, h * 0.42), Vector2(-d * 0.28, h * 0.88), Vector2(0.0, h), Vector2(d * 0.28, h * 0.88), Vector2(d * 0.62, h * 0.42), Vector2(d, -0.03)]
	var rows := clampi(int(length / 0.4) + 2, 6, 14)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var t := float(i) / float(rows - 1)
		var taper := smoothstep(0.0, 0.22, t) * smoothstep(1.0, 0.78, t) * rng.randf_range(0.8, 1.15) * snow
		var p := a + along * t
		for q: Vector2 in prof:
			pts.append(p + across * q.x * (0.6 + 0.4 * taper) + Vector3.UP * maxf(q.y * taper, -0.03))
			uvs.append(Vector2(t * length, q.x) * 0.4)
	k.patch(Snow.KEY, rows, prof.size(), pts, uvs, PackedColorArray([Snow.WHITE]))

func cone(k: Kit, at: Vector3, r: float, h: float) -> void:
	if snow < 0.04: return
	Snow.cone(k, at, r, h * snow)

# ---------------------------------------------------------------------------------------------------------------
# Building blocks (local coordinates of the piece)
# ---------------------------------------------------------------------------------------------------------------
## A wall plane: o its bottom-left corner seen from outside (at y = 0), r its right; the outward normal n = r x up.
class Face:
	extends RefCounted
	var o := Vector3.ZERO
	var r := Vector3.RIGHT
	var n := Vector3.BACK
	var w: float = 1.0
	func _init(origin: Vector3, right: Vector3, width: float) -> void:
		o = origin
		r = right.normalized()
		n = r.cross(Vector3.UP)
		w = width
	func at(x: float, y: float, out: float = 0.0) -> Vector3:
		return o + r * x + Vector3.UP * y + n * out
	func basis() -> Basis:
		return Basis(r, Vector3.UP, n)

## A face from its bottom-left corner, its right and its width (for the kit's other scripts).
static func face(origin: Vector3, right: Vector3, width: float) -> Face:
	return Face.new(origin, right, width)

static func face_of(a: Vector2, b: Vector2) -> Face:
	return Face.new(Vector3(a.x, 0.0, a.y), Vector3(b.x - a.x, 0.0, b.y - a.y), a.distance_to(b))

## A box laid on a face: centre x along it, y up, out from it; its size along, up and out.
func fbox(k: Kit, f: Face, layer: String, x: float, y: float, out: float, along: float, up: float, depth: float, tint: Color, lo: float = 0.75, mode: int = Kit.AUTO, faces: int = 63) -> void:
	k.push(Transform3D(f.basis(), f.o))
	k.push_tint(tint)
	k.box(layer, Vector3(x, y, out), Vector3(along, up, depth), Color(lo, lo, lo), Color.WHITE, Vector2(f.o.x + f.o.z, 1.0 - (y - up * 0.5) * Kit.UV_M) if mode == Kit.UPRIGHT else Vector2((f.o.x + f.o.z) * Kit.UV_M, 0.0), mode, faces)
	k.pop_tint()
	k.pop()

## A quad of the atlas on a face (x0..x1 along, y0..y1 up, `out` from it).
func fquad(kd: Kit, f: Face, key: String, x0: float, x1: float, y0: float, y1: float, out: float, r: Rect2, col: Color = Color.WHITE) -> void:
	kd.quad_rect(key, f.at(x0, y0, out), f.at(x1, y0, out), f.at(x1, y1, out), f.at(x0, y1, out), r, col, col)

## A storey band of wall on a face, from y0 to y1 and x0 to x1, its openings cut out with reveals (the structures kit's
## wall); each opening a dictionary {x (centre), y (sill), w, h, cell, key (atlas use), col, arch (round head),
## reveal}. The glass or the door goes at the back of the reveal; an arched opening gets its spandrels and intrados.
func band(k: Kit, kd: Kit, f: Face, layer: String, tint: Color, x0: float, x1: float, y0: float, y1: float, opens: Array, ao_lo: float = 0.82, ao_hi: float = 0.9) -> void:
	var rects: Array = []
	var reveal := 0.25
	for o: Dictionary in opens:
		rects.append(Rect2(float(o.x) - float(o.w) * 0.5 - x0, float(o.y) - y0, float(o.w), float(o.h)))
		reveal = float(o.get("reveal", reveal))
	k.push_tint(tint)
	k.wall(layer, f.at(x0, y0), f.r, x1 - x0, y1 - y0, rects, f.o.x + f.o.z + x0, y0, reveal, Color(ao_lo, ao_lo, ao_lo * 0.98), Color(ao_hi, ao_hi, ao_hi), 0.0 if y0 > 0.1 else 0.6, 0.0)
	k.pop_tint()
	for o: Dictionary in opens:
		var rv := float(o.get("reveal", reveal))
		var ox0 := float(o.x) - float(o.w) * 0.5
		var ox1 := float(o.x) + float(o.w) * 0.5
		var oy0 := float(o.y)
		var oy1 := oy0 + float(o.h)
		if o.has("cell"):
			fquad(kd, f, str(o.get("key", SOLID)), ox0, ox1, oy0, oy1, -rv + 0.01, uv(str(o.cell)), o.get("col", Color.WHITE))
		if bool(o.get("arch", false)):
			arch_head(k, f, layer, tint, ox0, ox1, oy1 - float(o.w) * 0.5, rv, bool(o.get("moulding", true)), o.get("trim", tint.lightened(0.12)))

## The round head of an opening cut square in a wall: the spandrels fill the corners above the springing line, the
## intrados runs round under the arch into the reveal, an archivolt band and a keystone on the face.
func arch_head(k: Kit, f: Face, layer: String, tint: Color, x0: float, x1: float, ys: float, reveal: float, moulding: bool = true, trim: Color = Color.WHITE, segs: int = 8) -> void:
	var r := (x1 - x0) * 0.5
	var cx := x0 + r
	var top := ys + r
	var pts: Array[Vector2] = []
	for i: int in range(segs + 1):
		var a := PI - PI * float(i) / float(segs)
		pts.append(Vector2(cx + cos(a) * r, ys + sin(a) * r))
	var u0 := f.o.x + f.o.z
	k.push_tint(tint)
	var half := segs / 2
	for i: int in range(segs):
		var corner := Vector2(x0, top) if i < half else Vector2(x1, top)
		var p0 := pts[i]
		var p1 := pts[i + 1]
		k.tri(layer, f.at(corner.x, corner.y, 0.0), f.at(p0.x, p0.y, 0.0), f.at(p1.x, p1.y, 0.0),
			Vector2((u0 + corner.x) * Kit.UV_M, 1.0 - corner.y * Kit.UV_M), Vector2((u0 + p0.x) * Kit.UV_M, 1.0 - p0.y * Kit.UV_M), Vector2((u0 + p1.x) * Kit.UV_M, 1.0 - p1.y * Kit.UV_M))
		# the intrados, facing in under the arch
		var a3 := f.at(p0.x, p0.y, 0.0)
		var b3 := f.at(p1.x, p1.y, 0.0)
		var c3 := f.at(p1.x, p1.y, -reveal)
		var d3 := f.at(p0.x, p0.y, -reveal)
		var centre := f.at(cx, ys, 0.0)
		var nrm := (b3 - a3).cross(d3 - a3)
		var shade := Color(0.62, 0.62, 0.64)
		if nrm.dot(centre - (a3 + b3) * 0.5) >= 0.0:
			k.quad4(layer, a3, b3, c3, d3, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, reveal * Kit.UV_M), Vector2(0, reveal * Kit.UV_M), Color.WHITE, Color.WHITE, shade, shade)
		else:
			k.quad4(layer, b3, a3, d3, c3, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, reveal * Kit.UV_M), Vector2(0, reveal * Kit.UV_M), Color.WHITE, Color.WHITE, shade, shade)
	k.pop_tint()
	if not moulding: return
	var ml := trim_layer if trim_layer != "render" else layer
	k.push_tint(trim)
	var bw := clampf(r * 0.16, 0.1, 0.32)
	for i: int in range(segs):
		var a0 := PI - PI * float(i) / float(segs)
		var a1 := PI - PI * float(i + 1) / float(segs)
		var i0 := f.at(cx + cos(a0) * r, ys + sin(a0) * r, 0.04)
		var i1 := f.at(cx + cos(a1) * r, ys + sin(a1) * r, 0.04)
		var o0 := f.at(cx + cos(a0) * (r + bw), ys + sin(a0) * (r + bw), 0.04)
		var o1 := f.at(cx + cos(a1) * (r + bw), ys + sin(a1) * (r + bw), 0.04)
		k.quad4(ml, i0, i1, o1, o0, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.05), Vector2(0, 0.05), Color(0.85, 0.85, 0.85), Color(0.85, 0.85, 0.85), Color.WHITE, Color.WHITE)
		# its outer edge
		k.quad4(ml, o0, o1, o1 - f.n * 0.04, o0 - f.n * 0.04, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.02), Vector2(0, 0.02), Color.WHITE, Color.WHITE, Color(0.7, 0.7, 0.7), Color(0.7, 0.7, 0.7))
	k.pop_tint()
	fbox(k, f, ml, cx, top + bw * 0.3, 0.07, bw * 1.3, bw * 2.0, 0.14, trim)

## A moulding run along a plan path (local x, z points; the outward side to the left of the direction of travel, as a
## front runs left to right), mitred at the corners: profile (out, up) from its foot at the wall, y0 its base. Flat
## faces, so the light picks out each member. Snow lies along its top when `snowy`.
func moulding(k: Kit, layer: String, path: PackedVector2Array, y0: float, prof: PackedVector2Array, tint: Color, closed: bool = false, snowy: bool = true) -> void:
	var n := path.size()
	if n < 2: return
	var normals: Array[Vector2] = []
	var count := n if closed else n - 1
	for i: int in range(count):
		var d := (path[(i + 1) % n] - path[i]).normalized()
		normals.append(Vector2(-d.y, d.x))
	var miters: Array[Vector2] = []
	for i: int in range(n):
		var na: Vector2
		var nb: Vector2
		if closed:
			na = normals[(i + count - 1) % count]
			nb = normals[i % count]
		else:
			na = normals[maxi(i - 1, 0)]
			nb = normals[mini(i, count - 1)]
		var m := na + nb
		var den := 1.0 + na.dot(nb)
		miters.append(m / den if den > 0.05 else nb)
	k.push_tint(tint)
	var run := 0.0
	for j: int in range(count):
		var j2 := (j + 1) % n
		var seg_len := path[j].distance_to(path[j2])
		var v := 0.0
		for i: int in range(prof.size() - 1):
			var p0 := prof[i]
			var p1 := prof[i + 1]
			var a := Vector3(path[j].x + miters[j].x * p0.x, y0 + p0.y, path[j].y + miters[j].y * p0.x)
			var b := Vector3(path[j2].x + miters[j2].x * p0.x, y0 + p0.y, path[j2].y + miters[j2].y * p0.x)
			var c := Vector3(path[j2].x + miters[j2].x * p1.x, y0 + p1.y, path[j2].y + miters[j2].y * p1.x)
			var d := Vector3(path[j].x + miters[j].x * p1.x, y0 + p1.y, path[j].y + miters[j].y * p1.x)
			var step := p0.distance_to(p1)
			# lighter on the members that face up and out, darker under them
			var g := 1.0 if p1.y >= p0.y else 0.72
			var gc := Color(g, g, g)
			k.quad4(layer, a, b, c, d, Vector2(run, v) * Kit.UV_M, Vector2(run + seg_len, v) * Kit.UV_M, Vector2(run + seg_len, v + step) * Kit.UV_M, Vector2(run, v + step) * Kit.UV_M, gc, gc, gc, gc)
			v += step
		run += seg_len
	k.pop_tint()
	if not closed:
		for e: int in [0, n - 1]:
			var poly := PackedVector2Array()
			for p: Vector2 in prof: poly.append(p)
			var tris := Geometry2D.triangulate_polygon(poly)
			var mt := miters[e]
			var pos := path[e]
			k.push_tint(tint * 0.85)
			for t: int in range(0, tris.size(), 3):
				var q: Array[Vector3] = []
				for s: int in range(3):
					var pp := poly[tris[t + s]]
					q.append(Vector3(pos.x + mt.x * pp.x, y0 + pp.y, pos.y + mt.y * pp.x))
				var along := (path[1] - path[0]) if e == 0 else (path[n - 1] - path[n - 2])
				var want := Vector3(-along.x, 0, -along.y) if e == 0 else Vector3(along.x, 0, along.y)
				if (q[1] - q[0]).cross(q[2] - q[0]).dot(want) >= 0.0: k.tri(layer, q[0], q[1], q[2], Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1))
				else: k.tri(layer, q[0], q[2], q[1], Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1))
			k.pop_tint()
	if not snowy or snow < 0.04: return
	# the snow on its top: the widest member that faces up
	var best := -1
	var best_w := 0.0
	for i: int in range(prof.size() - 1):
		if absf(prof[i].y - prof[i + 1].y) < 0.01 and absf(prof[i].x - prof[i + 1].x) > best_w:
			best_w = absf(prof[i].x - prof[i + 1].x)
			best = i
	if best < 0 or best_w < 0.06: return
	var top_y := y0 + prof[best].y
	var mid_out := (prof[best].x + prof[best + 1].x) * 0.5
	for j: int in range(count):
		var j2 := (j + 1) % n
		var a2 := Vector3(path[j].x + miters[j].x * mid_out, top_y, path[j].y + miters[j].y * mid_out)
		var b2 := Vector3(path[j2].x + miters[j2].x * mid_out, top_y, path[j2].y + miters[j2].y * mid_out)
		ridge(k, a2, b2, Vector3.UP, best_w * 0.95, clampf(best_w * 0.28, 0.06, 0.18), 0.05)

## Profiles (out, up) for moulding(): a string course, a main cornice, a plinth, a small cap.
static func prof_string(depth: float = 0.18, h: float = 0.32) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(depth * 0.6, h * 0.25), Vector2(depth * 0.6, h * 0.55), Vector2(depth, h * 0.7), Vector2(depth, h), Vector2(0, h)])

static func prof_cornice(depth: float = 0.9, h: float = 1.1) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(depth * 0.12, h * 0.1), Vector2(depth * 0.12, h * 0.3), Vector2(depth * 0.3, h * 0.36),
		Vector2(depth * 0.3, h * 0.5), Vector2(depth * 0.55, h * 0.56), Vector2(depth * 0.86, h * 0.7), Vector2(depth, h * 0.78), Vector2(depth, h), Vector2(0, h)])

static func prof_plinth(depth: float = 0.25, h: float = 0.9) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(depth, 0), Vector2(depth, h * 0.75), Vector2(depth * 0.5, h), Vector2(0, h)])

## A balustrade along a straight run (local points a -> b, outward to the left of travel as for a front): plinth,
## balusters (the atlas's cut-out), the top rail, dados every few metres, urns on some; snow along the rail.
func balustrade(k: Kit, kd: Kit, a: Vector3, b: Vector3, h: float, tint: Color, dado: float = 3.2, urns: bool = false) -> void:
	var length := a.distance_to(b)
	if length < 0.3: return
	var dir := (b - a) / length
	k.push_tint(tint)
	k.beam(trim_layer, a + Vector3(0, 0.1, 0), b + Vector3(0, 0.1, 0), 0.36, 0.2, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.beam(trim_layer, a + Vector3(0, h - 0.07, 0), b + Vector3(0, h - 0.07, 0), 0.4, 0.14, Color(0.85, 0.85, 0.85), Color.WHITE)
	var nd := maxi(1, int(round(length / dado)))
	for i: int in range(nd + 1):
		var p := a + dir * clampf(float(i) * length / float(nd), 0.2, length - 0.2)
		k.box(trim_layer, p + Vector3(0, h * 0.5, 0), Vector3(0.38, h - 0.1, 0.38), Color(0.8, 0.8, 0.8), Color.WHITE)
		if urns and (i % 2 == 0 or i == nd):
			k.lathe(trim_layer, p + Vector3(0, h, 0), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.1, 0.08), Vector2(0.2, 0.25), Vector2(0.22, 0.4), Vector2(0.12, 0.55), Vector2(0.06, 0.62), Vector2(0.1, 0.68), Vector2(0.0, 0.8)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
			cone(k, p + Vector3(0, h + 0.62, 0), 0.12, 0.08)
	k.pop_tint()
	var cw := 0.95
	var s := 0.0
	while s < length - 0.01:
		var t := minf(cw, length - s)
		var p0 := a + dir * s
		var p1 := a + dir * (s + t)
		kd.quad_rect(CUT, p0 + Vector3(0, 0.2, 0), p1 + Vector3(0, 0.2, 0), p1 + Vector3(0, h - 0.14, 0), p0 + Vector3(0, h - 0.14, 0), uv_part("balustrade", 0.0, t / cw), tint, tint)
		s += t
	ridge(k, a + Vector3(0, h, 0), b + Vector3(0, h, 0), Vector3.UP, 0.4, 0.12, 0.04)

## A round column of the classical orders: a square plinth, a moulded base, the shaft with its swelling, and a capital
## (Corinthian: a flared bell under a square abacus; Tuscan: a plain cushion). Snow on the abacus.
func column(k: Kit, layer: String, at: Vector3, height: float, radius: float, tint: Color, corinthian: bool = true, segments: int = 12) -> void:
	k.push_tint(tint)
	var pl := radius * 2.5
	k.box(layer, at + Vector3(0, radius * 0.25, 0), Vector3(pl, radius * 0.5, pl), Color(0.7, 0.7, 0.7), Color.WHITE)
	var cap_h := radius * (2.4 if corinthian else 1.0)
	var shaft_top := height - cap_h - radius * 0.3
	var prof := PackedVector2Array([Vector2(radius * 1.2, radius * 0.5), Vector2(radius * 1.22, radius * 0.62), Vector2(radius * 1.05, radius * 0.78), Vector2(radius * 1.1, radius * 0.9),
		Vector2(radius, radius * 1.05), Vector2(radius * 1.0, height * 0.33), Vector2(radius * 0.86, shaft_top), Vector2(radius * 0.95, shaft_top + radius * 0.12), Vector2(radius * 0.88, shaft_top + radius * 0.22)])
	if corinthian:
		prof.append_array(PackedVector2Array([Vector2(radius * 0.9, shaft_top + cap_h * 0.3), Vector2(radius * 1.15, shaft_top + cap_h * 0.7), Vector2(radius * 1.4, shaft_top + cap_h * 0.95)]))
	else:
		prof.append_array(PackedVector2Array([Vector2(radius * 1.15, shaft_top + cap_h * 0.6)]))
	k.lathe(layer, at, prof, segments, Color(0.72, 0.72, 0.72), Color.WHITE)
	var ab := radius * (3.0 if corinthian else 2.5)
	k.box(layer, at + Vector3(0, height - radius * 0.15, 0), Vector3(ab, radius * 0.3, ab), Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop_tint()
	box_top(k, at + Vector3(0, height, 0), Vector2(ab, ab), 0.14)

## A square frustum (an obelisk's shaft, a pedestal's step): flat faces, its top capped.
func frustum(k: Kit, layer: String, at: Vector3, y0: float, s0: float, y1: float, s1: float, tint: Color, cap: bool = true) -> void:
	var h0 := s0 * 0.5
	var h1 := s1 * 0.5
	var c0 := [Vector2(-h0, h0), Vector2(h0, h0), Vector2(h0, -h0), Vector2(-h0, -h0)]
	var c1 := [Vector2(-h1, h1), Vector2(h1, h1), Vector2(h1, -h1), Vector2(-h1, -h1)]
	k.push_tint(tint)
	for i: int in range(4):
		var j := (i + 1) % 4
		var a := at + Vector3(c0[i].x, y0, c0[i].y)
		var b := at + Vector3(c0[j].x, y0, c0[j].y)
		var c := at + Vector3(c1[j].x, y1, c1[j].y)
		var d := at + Vector3(c1[i].x, y1, c1[i].y)
		k.quad4(layer, a, b, c, d, Vector2(0, 1.0 - y0 * Kit.UV_M), Vector2(s0 * Kit.UV_M, 1.0 - y0 * Kit.UV_M), Vector2(s0 * Kit.UV_M, 1.0 - y1 * Kit.UV_M), Vector2(0, 1.0 - y1 * Kit.UV_M), Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8), Color.WHITE, Color.WHITE)
	if cap:
		k.quad4(layer, at + Vector3(c1[0].x, y1, c1[0].y), at + Vector3(c1[1].x, y1, c1[1].y), at + Vector3(c1[2].x, y1, c1[2].y), at + Vector3(c1[3].x, y1, c1[3].y), Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.2), Vector2(0, 0.2), Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE)
	k.pop_tint()

## A flat roof's slab over a convex outline (local x, z), its snow on it.
func roof_slab(k: Kit, poly: PackedVector2Array, y: float, tint: Color, snow_t: float = 0.22) -> void:
	k.push_tint(tint)
	for i: int in range(1, poly.size() - 1):
		k.tri("render", Vector3(poly[0].x, y, poly[0].y), Vector3(poly[i].x, y, poly[i].y), Vector3(poly[i + 1].x, y, poly[i + 1].y), poly[0] * Kit.UV_M, poly[i] * Kit.UV_M, poly[i + 1] * Kit.UV_M)
	k.pop_tint()
	pillow(k, Snow.inset(poly, 0.15), y, snow_t, 0.8)

## A rectangle on a face's plan (x0..x1 along it, o0..o1 out from it) as an outline for the snow (Snow.inset's order).
static func face_poly(f: Face, x0: float, x1: float, o0: float, o1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector3 in [f.at(x0, 0, o0), f.at(x1, 0, o0), f.at(x1, 0, o1), f.at(x0, 0, o1)]: pts.append(Vector2(p.x, p.z))
	return ccw(pts)

## Orders a convex outline the way Snow.inset and Snow.pillow expect (counter-clockwise seen from above).
static func ccw(pts: PackedVector2Array) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p: Vector2 in pts: c += p
	c /= float(pts.size())
	var list: Array = []
	for p: Vector2 in pts: list.append(p)
	list.sort_custom(func(a: Vector2, b: Vector2) -> bool: return atan2(a.y - c.y, a.x - c.x) > atan2(b.y - c.y, b.x - c.x))
	return PackedVector2Array(list)

static func rect_poly(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	# counter-clockwise seen from above (x right, z down the screen): the order Snow.inset expects
	return PackedVector2Array([Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0)])

## A plain wall with a grid of windows laid flat on it (no reveals): the sides and backs nobody comes close to.
func plain_wall(k: Kit, kd: Kit, f: Face, layer: String, tint: Color, y0: float, y1: float, floors: Array, bay: float = 4.0, win_w: float = 1.4, cells: String = "win") -> void:
	k.push_tint(tint)
	k.quad4(layer, f.at(0, y0), f.at(f.w, y0), f.at(f.w, y1), f.at(0, y1), Vector2((f.o.x + f.o.z) * Kit.UV_M, 1.0 - y0 * Kit.UV_M), Vector2((f.o.x + f.o.z + f.w) * Kit.UV_M, 1.0 - y0 * Kit.UV_M),
		Vector2((f.o.x + f.o.z + f.w) * Kit.UV_M, 1.0 - y1 * Kit.UV_M), Vector2((f.o.x + f.o.z) * Kit.UV_M, 1.0 - y1 * Kit.UV_M), Color(0.66, 0.65, 0.64) if y0 < 0.1 else Color.WHITE, Color(0.66, 0.65, 0.64) if y0 < 0.1 else Color.WHITE, Color(0.9, 0.9, 0.9), Color(0.9, 0.9, 0.9))
	k.pop_tint()
	var nb := maxi(1, int(floor(f.w / bay)))
	for i: int in range(nb):
		var x := (float(i) + 0.5) * f.w / float(nb)
		for fl: Vector2 in floors:
			var l := is_lit()
			var cell := window_cell(l) if cells == "win" else ((cells + "_lit") if l else (cells + "_dark"))
			fquad(kd, f, LIT if l else SOLID, x - win_w * 0.5, x + win_w * 0.5, fl.x, fl.x + fl.y, 0.02, uv(cell), warm() if l else Color.WHITE)

## Light spilling from a lit opening onto the snow in front of it (world space, an added fan, as La Boca's).
func spill_at(local_at: Vector3, local_out: Vector3, width: float, length: float, strength: float) -> void:
	var at := xf * local_at
	var out := (xf.basis * local_out).normalized()
	var right := Vector3(-out.z, 0, out.x)
	var c := Color(1.0, 0.62, 0.3) * strength * 0.5
	c.a = 1.0
	var y := 0.05
	var a := at - right * width * 0.6 + Vector3(0, y, 0)
	var b := at + right * width * 0.6 + Vector3(0, y, 0)
	var cc := at + right * width * 1.1 + out * length + Vector3(0, y, 0)
	var d := at - right * width * 1.1 + out * length + Vector3(0, y, 0)
	a.y = y
	b.y = y
	cc.y = y
	d.y = y
	_pools.quad_rect("pool", d, cc, b, a, Rect2(0.5, 0.0, 0.0001, 0.5), Color.BLACK, c)

## Floodlight on a front: the walls of `k` that face the front (local +z) take a warm wash, strongest at the foot and
## fading up to `top` (plaza_walls.gdshader adds it as light). An art-direction choice for the landmarks that carry a
## view (the notes do not say whether they were floodlit in 1958); 0 turns it off. With `pools` (metres between the
## lamps along the front) it falls in pools, the wall between them left to the night's cold light.
func flood(k: Kit, strength: float, top: float, x0: float = -1e9, x1: float = 1e9, pools: float = 0.0, phase: float = 0.0) -> void:
	if strength <= 0.0: return
	var sf: Kit.Surf = k.surfs.get("pwalls")
	if sf == null or sf.uv2.size() != sf.v.size(): return
	for i: int in range(sf.v.size()):
		var p := sf.v[i]
		if p.x < x0 or p.x > x1 or p.y > top + 3.0: continue
		var n := sf.n[i]
		var facing := clampf(n.z * 0.85 + n.y * 0.5, 0.0, 1.0)
		if facing <= 0.0: continue
		var fall := 1.0 - 0.6 * clampf(p.y / top, 0.0, 1.0)
		if pools > 0.0:
			# a pool spreads wider as it climbs the wall; between the pools the wall dims gently toward the top
			var h := clampf(p.y / top, 0.0, 1.0)
			var c := cos(PI * (p.x - phase) / pools)
			var pool := pow(c * c, 1.0 + 1.5 * (1.0 - h))
			fall *= 0.66 + 0.34 * pool - 0.16 * (1.0 - pool) * h
		sf.uv2[i] = Vector2(sf.uv2[i].x, strength * facing * fall)

## A pool of lamplight on the snow (world position), and a halo round the lamp itself.
func pool(at: Vector3, radius: float, col: Color) -> void:
	col.a = 1.0
	var y := 0.045
	_pools.quad_rect("pool", Vector3(at.x - radius, y, at.z + radius), Vector3(at.x + radius, y, at.z + radius), Vector3(at.x + radius, y, at.z - radius), Vector3(at.x - radius, y, at.z - radius), Rect2(0, 0, 1, 1), col, col)

## A glowing lathe (a lamp's globe, a lantern, a headlamp): its UVs squeezed into an atlas cell (the warm "glow").
func glow_lathe(kd: Kit, at: Vector3, prof: PackedVector2Array, segments: int, col: Color = WARM, key: String = GLOW, cell: String = "glow") -> void:
	var sf: Kit.Surf = kd.surfs.get("pdetail")
	var start := sf.uv.size() if sf != null else 0
	kd.lathe(key, at, prof, segments, col, col)
	sf = kd.surfs.get("pdetail")
	if sf == null: return
	var r := uv(cell)
	for i: int in range(start, sf.uv.size()):
		var u := sf.uv[i]
		sf.uv[i] = r.position + Vector2(0.15 + 0.7 * fposmod(u.x, 1.0), 0.15 + 0.7 * fposmod(u.y, 1.0)) * r.size

func halo(world_at: Vector3, col: Color, size: float) -> void:
	_halos.append([world_at, col, size])

# ---------------------------------------------------------------------------------------------------------------
# Weathering and joinery (the Casa Rosada's; for any front that wants them)
# ---------------------------------------------------------------------------------------------------------------
## The grime sheet's strips (tools/gen_plaza_textures.py tex_grime): the rain's streaks under a sill, soot and damp
## under a cornice, rising damp at a wall's foot, blotches for the recesses.
const GRIME_SILL := 0
const GRIME_SOOT := 1
const GRIME_DAMP := 2
const GRIME_BLOTCH := 3

## Weathering on a front, multiplied over it (plaza_grime.gdshader, on the detail mesh: no shadow): a strip of the
## grime sheet a hair off face `f`, x0..x1 along it and y0..y1 up; `amount` how dark. A strip is 4 m of wall wide,
## each run starting at its own place in it.
func grime(kd: Kit, f: Face, row: int, x0: float, x1: float, y0: float, y1: float, amount: float = 1.0, out: float = 0.03, band0: float = NAN, band1: float = NAN, u_start: float = NAN) -> void:
	if x1 - x0 < 0.05 or y1 - y0 < 0.05: return
	# (a piece of a taller band: the strip's V spans the whole band, band0..band1, so the gradient runs on across it)
	var b0 := y0 if is_nan(band0) else band0
	var b1 := y1 if is_nan(band1) else band1
	var u0 := rng.randf() * 4.0 if is_nan(u_start) else u_start + x0 * 0.25
	var u1 := u0 + (x1 - x0) * 0.25
	var vt := (float(row) + 0.01 + 0.98 * (b1 - y1) / (b1 - b0)) * 0.25
	var vb := (float(row) + 0.01 + 0.98 * (b1 - y0) / (b1 - b0)) * 0.25
	var c := Color(1, 1, 1, amount)
	kd.quad4("grime", f.at(x0, y0, out), f.at(x1, y0, out), f.at(x1, y1, out), f.at(x0, y1, out), Vector2(u0, vb), Vector2(u1, vb), Vector2(u1, vt), Vector2(u0, vt), c, c, c, c)

## The same along a run of wall with openings in it (band()'s dictionaries): one band, broken only where an opening
## stands in it (it runs on above and below the opening), so that the dirt never hangs across the glass.
func grime_run(kd: Kit, f: Face, row: int, x0: float, x1: float, y0: float, y1: float, opens: Array, amount: float = 1.0) -> void:
	var cuts: Array = []
	for o: Dictionary in opens:
		var oy0 := float(o.y)
		var oy1 := oy0 + float(o.h)
		if oy1 <= y0 or oy0 >= y1: continue
		cuts.append(Vector4(float(o.x) - float(o.w) * 0.5 - 0.06, float(o.x) + float(o.w) * 0.5 + 0.06, oy0 - 0.04, oy1 + 0.06))
	cuts.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	var us := rng.randf() * 4.0
	var x := x0
	for c: Vector4 in cuts:
		if c.x > x: grime(kd, f, row, x, minf(c.x, x1), y0, y1, amount, 0.03, y0, y1, us)
		var cx0 := maxf(c.x, x)
		var cx1 := minf(c.y, x1)
		if cx1 > cx0:
			if c.z > y0: grime(kd, f, row, cx0, cx1, y0, minf(c.z, y1), amount, 0.03, y0, y1, us)
			if c.w < y1: grime(kd, f, row, cx0, cx1, maxf(c.w, y0), y1, amount, 0.03, y0, y1, us)
		x = maxf(x, c.y)
	if x < x1: grime(kd, f, row, x, x1, y0, y1, amount, 0.03, y0, y1, us)

## A window's joinery at the back of its reveal, standing just in front of the atlas's glass: the frame round it, the
## mullion between its two leaves and the transom under the fanlight, in dark painted wood (on a round-headed window
## the arch is the head; its transom at the springing). `depth` how far in the glass is.
func casement(k: Kit, f: Face, x: float, y: float, w: float, h: float, depth: float, arched: bool = false, col: Color = Color(0.08, 0.09, 0.08)) -> void:
	var z := -depth + 0.06
	var fw := 0.085
	var top := y + h - (w * 0.5 if arched else 0.0)
	var transom := top if arched else y + h * 0.74
	var faces := 1 | 2 | 4 | 16
	fbox(k, f, "paint", x - w * 0.5 + fw * 0.5, (y + top) * 0.5, z, fw, top - y, 0.08, col, 0.8, Kit.AUTO, faces)
	fbox(k, f, "paint", x + w * 0.5 - fw * 0.5, (y + top) * 0.5, z, fw, top - y, 0.08, col, 0.8, Kit.AUTO, faces)
	fbox(k, f, "paint", x, y + fw * 0.5, z, w, fw, 0.1, col, 0.8, Kit.AUTO, faces)
	if not arched: fbox(k, f, "paint", x, y + h - fw * 0.5, z, w, fw, 0.08, col, 0.8, Kit.AUTO, faces)
	fbox(k, f, "paint", x, (y + transom) * 0.5, z + 0.01, 0.06, transom - y, 0.08, col, 0.8, Kit.AUTO, faces)
	fbox(k, f, "paint", x, transom, z + 0.01, w, 0.07, 0.08, col, 0.8, Kit.AUTO, faces)

# ---------------------------------------------------------------------------------------------------------------
# The Casa Rosada
# ---------------------------------------------------------------------------------------------------------------
## The Casa de Gobierno on Balcarce, its front on the square: three storeys over a rusticated ground floor with
## round-arched windows behind iron bars; Tamburini's central block (1898) projecting, the great arch through it
## between paired columns, an iron gate across it and the passage lit warm behind, an attic over it with the flag on
## its pole; the wings' piano nobile of tall windows with pediments and balustraded balconies, their top floor an
## arcaded loggia; end pavilions under slate mansards with dormers; a main cornice and a balustrade with urns all
## along; flat roofs under snow. (The notes give the colour, the three storeys, the central arch and the iron
## grilles; the loggias, pavilions and mansards are from general knowledge of the building, simplified.)
## Its materials as a lime-stuccoed palace of the 1890s seen on a snowy night: the stucco washed a dusty rose (it was
## pink already then; not the salmon of a fresh paint), uneven over a façade's width (plaza_walls.gdshader); the
## banded rustication of the ground floor a shade deeper; the cornices, string courses, pilasters, surrounds and
## balustrades in a pale cream stone; the joinery dark, some windows shuttered, the lit ones warm and low; and the
## weather on all of it (plaza_grime.gdshader): rain streaks from every sill and balcony, soot and damp under the
## cornices and string courses, rising damp at the foot, grime in the loggias. Snow on every ledge. Fits fronts of
## about 60 to 130 m. Returns the node; its flag is a child ("Flag").
func casa_rosada(rect: Rect2, facing: Vector3 = WEST, floodlit: float = 1.0) -> Node3D:
	var fr := frame(rect, facing)
	var piece_xf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	begin(piece_xf)
	trim_layer = "stone"
	var k := Kit.new()
	var kd := Kit.new()
	var pink := ROSADA_STUCCO
	var pale := ROSADA_PILASTER
	var trim := ROSADA_STONE
	var G := 6.2
	var P := 12.4
	var T := 18.2
	var cw := clampf(W * 0.17, 14.0, 20.0)
	var pw := clampf(W * 0.12, 9.0, 15.0)
	var zc := 0.0
	var zp := -1.2
	var zw := -2.4
	var cl := W * 0.5 - cw * 0.5
	var cr := W * 0.5 + cw * 0.5
	# the wings
	for side: int in range(2):
		var x0 := pw if side == 0 else cr
		var x1 := cl if side == 0 else W - pw
		_rosada_wing(k, kd, Face.new(Vector3(0, 0, zw), Vector3.RIGHT, W), x0, x1, G, P, T, pink, pale, trim)
	# the pavilions at the ends, and the central block
	for side: int in range(2):
		var x0 := 0.0 if side == 0 else W - pw
		_rosada_pavilion(k, kd, x0, x0 + pw, zp, zw, G, P, T, pink, pale, trim, D)
	_rosada_centre(k, kd, cl, cr, zc, zw, G, P, T, pink, pale, trim)
	# the main cornice round the whole front and the ends, and the balustrade on it
	var path := PackedVector2Array([Vector2(0, -D), Vector2(0, zp), Vector2(pw, zp), Vector2(pw, zw), Vector2(cl, zw), Vector2(cl, zc), Vector2(cr, zc),
		Vector2(cr, zw), Vector2(W - pw, zw), Vector2(W - pw, zp), Vector2(W, zp), Vector2(W, -D)])
	moulding(k, "stone", path, T, prof_cornice(0.95, 1.05), trim)
	var left := PackedVector2Array([Vector2(0, -D), Vector2(0, zp), Vector2(pw, zp), Vector2(pw, zw), Vector2(cl, zw), Vector2(cl, zc)])
	var right := PackedVector2Array([Vector2(cr, zc), Vector2(cr, zw), Vector2(W - pw, zw), Vector2(W - pw, zp), Vector2(W, zp), Vector2(W, -D)])
	for half: PackedVector2Array in [left, right]:
		moulding(k, "stone", half, G - 0.18, prof_string(0.22, 0.36), trim)
		moulding(k, "stone", half, P - 0.12, prof_string(0.2, 0.3), trim)
		moulding(k, "rustic", half, 0.0, prof_plinth(0.18, 0.85), ROSADA_PLINTH, false, false)
	for seg: Array in [[Vector2(pw, zw), Vector2(cl, zw)], [Vector2(cr, zw), Vector2(W - pw, zw)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		balustrade(k, kd, Vector3(a.x, T + 1.05, a.y + 0.45), Vector3(b.x, T + 1.05, b.y + 0.45), 1.05, trim, 4.4, true)
	# the ends and the back: plain stuccoed walls with their windows, damp at the foot, soot under the cornice
	var floors := [Vector2(1.4, 3.0), Vector2(G + 0.9, 3.4), Vector2(P + 1.0, 3.0)]
	for pf: Face in [Face.new(Vector3(0, 0, -D), Vector3(0, 0, 1), D + zp), Face.new(Vector3(W, 0, zp), Vector3(0, 0, -1), D + zp), Face.new(Vector3(W, 0, -D), Vector3(-1, 0, 0), W)]:
		plain_wall(k, kd, pf, "stucco", pink, 0.0, T, floors, 5.0 if pf.w > 60.0 else 4.4, 1.5)
		grime(kd, pf, GRIME_DAMP, 0.0, pf.w, 0.0, 2.0, 1.0)
		grime(kd, pf, GRIME_SOOT, 0.0, pf.w, T - 3.0, T, 0.6)
		grime(kd, pf, GRIME_SOOT, 0.0, pf.w, P - 2.2, P - 0.1, 0.45)
		grime(kd, pf, GRIME_SOOT, 0.0, pf.w, G - 2.2, G - 0.1, 0.45)
	# the roofs: terraces under snow behind the balustrade, skylights and chimneys on them, soot round their tops
	roof_slab(k, rect_poly(pw, -D, W - pw, zw), T + 1.05, Color(0.3, 0.28, 0.28))
	for side: int in range(2):
		var x0 := 0.0 if side == 0 else W - pw
		roof_slab(k, rect_poly(x0, -D, x0 + pw, zp), T + 1.05, Color(0.3, 0.28, 0.28))
	for i: int in range(int(W / 18.0)):
		var at := Vector3(rng.randf_range(pw + 2.0, W - pw - 2.0), T + 1.05, rng.randf_range(-D + 3.0, zw - 4.0))
		k.push_tint(pink * 0.82)
		k.box("stucco", at + Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 0.9), Color(0.6, 0.6, 0.6), Color(0.45, 0.42, 0.4))
		k.pop_tint()
		k.push_tint(trim * 0.8)
		k.box("stone", at + Vector3(0, 1.86, 0), Vector3(0.86, 0.12, 1.06), Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.6))
		k.pop_tint()
		box_top(k, at + Vector3(0, 1.92, 0), Vector2(0.86, 1.06), 0.12)
	var flag_at := Vector3(W * 0.5, T + 5.0, zc - 3.5)
	# (in pools, one on the gate and one every few bays, the stucco between them cooler)
	flood(k, floodlit * 1.7, T + 5.0, -1e9, 1e9, W / 6.0, W * 0.5)
	trim_layer = "render"
	var node := piece("CasaRosada", piece_xf, k, kd)
	flagpole_on(node, flag_at, 9.0, 3.4)
	end()
	return node

## The Casa Rosada's colours (sRGB of the vertex tints over the near-white layers): the stucco's warm salmon pink,
## dusty (a little greyer than a fresh paint), the pilasters a shade paler, the rusticated ground floor a shade deeper, the plinth deeper still, the trims' cream stone,
## the joinery's dark green-black, the shutters' faded green.
var ROSADA_STUCCO := hexc("f7cbba")
var ROSADA_PILASTER := hexc("f9d9cc")
var ROSADA_RUSTIC := hexc("f0c3b2")
var ROSADA_PLINTH := hexc("a08780")
var ROSADA_STONE := hexc("efe3d1")
var ROSADA_JOINERY := hexc("1c201c")
var ROSADA_SHUTTER := hexc("6f7f6c")

## One of the palace's windows on a front: its cell (lit: warm and low, not blown out; dark: the glass, or now and then
## the shutters closed on it), for band().
func _rosada_window(x: float, y: float, w: float, h: float, reveal: float, arched: bool = false) -> Dictionary:
	# (the palace works late: three windows in four lit)
	var l := rng.randf() < 0.75
	var cell: String
	if arched: cell = ("arch_lit%d" % rng.randi_range(0, 2)) if l else "arch_dark%d" % rng.randi_range(0, 1)
	else: cell = window_cell(l)
	var o := {"x": x, "y": y, "w": w, "h": h, "cell": cell, "key": LIT if l else SOLID, "col": warm() * 1.2 if l else Color.WHITE, "reveal": reveal, "lit": l}
	if not l and not arched and rng.randf() < 0.3:
		o.cell = "shutter"
		o.col = Color(0.42, 0.5, 0.42)
		o["shut"] = true
	if arched:
		o["arch"] = true
		o["trim"] = ROSADA_STONE
	return o

## The joinery of a front's windows (band()'s dictionaries), and the iron bars over the ground floor's.
func _rosada_joinery(k: Kit, kd: Kit, f: Face, opens: Array, bars: bool = false) -> void:
	for o: Dictionary in opens:
		if bool(o.get("shut", false)): continue
		var arched := bool(o.get("arch", false))
		casement(k, f, float(o.x), float(o.y), float(o.w), float(o.h), float(o.reveal), arched, ROSADA_JOINERY)
		if bars:
			var top := float(o.y) + float(o.h) - (float(o.w) * 0.5 if arched else 0.0)
			fquad(kd, f, CUT, float(o.x) - float(o.w) * 0.5 + 0.02, float(o.x) + float(o.w) * 0.5 - 0.02, float(o.y) + 0.02, top, -0.08, uv("bars"), Color(0.75, 0.75, 0.75))

func _rosada_wing(k: Kit, kd: Kit, f: Face, x0: float, x1: float, G: float, P: float, T: float, pink: Color, pale: Color, trim: Color) -> void:
	var L := x1 - x0
	if L < 3.0: return
	var nb := maxi(1, int(round(L / 4.6)))
	var bay := L / float(nb)
	# ground floor: banded rustication, round-arched windows behind iron bars
	var g_opens: Array = []
	for i: int in range(nb):
		var x := x0 + (float(i) + 0.5) * bay
		var o := _rosada_window(x, 1.0, 1.7, 3.9, 0.4, true)
		g_opens.append(o)
		if bool(o.lit): spill_at(f.at(x, 0.0, 0.0), f.n, 1.7, 2.2, 0.32)
	band(k, kd, f, "rustic", ROSADA_RUSTIC, x0, x1, 0.0, G, g_opens, 0.7, 0.86)
	_rosada_joinery(k, kd, f, g_opens, true)
	for o: Dictionary in g_opens:
		ridge(k, f.at(float(o.x) - 0.95, 0.98, 0.1), f.at(float(o.x) + 0.95, 0.98, 0.1), Vector3.UP, 0.22, 0.07)
		fbox(k, f, "stone", float(o.x), 0.93, 0.06, 2.0, 0.14, 0.24, trim)
		grime(kd, f, GRIME_SILL, float(o.x) - 1.0, float(o.x) + 1.0, 0.1, 0.86, 0.7)
	grime_run(kd, f, GRIME_DAMP, x0, x1, 0.0, 2.1, g_opens, 0.8)
	grime_run(kd, f, GRIME_SOOT, x0, x1, G - 2.6, G - 0.18, g_opens, 0.55)
	# the piano nobile: tall windows with surrounds, pediments over them, balustraded balconies on every other bay
	var p_opens: Array = []
	for i: int in range(nb):
		p_opens.append(_rosada_window(x0 + (float(i) + 0.5) * bay, G + 0.8, 1.6, 3.7, 0.3))
	band(k, kd, f, "stucco", pink, x0, x1, G, P, p_opens)
	_rosada_joinery(k, kd, f, p_opens)
	for i: int in range(nb):
		var o: Dictionary = p_opens[i]
		var x := float(o.x)
		_surround(k, f, x, G + 0.8, 1.6, 3.7, trim, i % 2)
		if i % 2 == 0:
			_balcony(k, kd, f, x - 1.25, x + 1.25, G + 0.72, trim)
			# (stopping short of the ground floor's arched window under it, at 4.9 m)
			grime(kd, f, GRIME_SILL, x - 1.35, x + 1.35, G - 1.2, G + 0.2, 0.95)
		else:
			fbox(k, f, "stone", x, G + 0.74, 0.08, 2.0, 0.12, 0.24, trim)
			ridge(k, f.at(x - 1.0, G + 0.8, 0.12), f.at(x + 1.0, G + 0.8, 0.12), Vector3.UP, 0.22, 0.07)
			grime(kd, f, GRIME_SILL, x - 1.05, x + 1.05, G - 1.2, G + 0.66, 0.85)
	grime_run(kd, f, GRIME_SOOT, x0, x1, P - 2.6, P - 0.12, p_opens, 0.5)
	# pilasters between the bays on the upper floors
	for i: int in range(nb + 1):
		var x := x0 + float(i) * bay
		fbox(k, f, "stucco", x, (G + T) * 0.5, 0.07, 0.62, T - G, 0.14, pale, 0.8)
	# the top floor: an arcaded loggia, its back wall with the doors and windows of the rooms
	var depth := 2.0
	var l_opens: Array = []
	for i: int in range(nb):
		var x := x0 + (float(i) + 0.5) * bay
		l_opens.append({"x": x, "y": P + 0.25, "w": minf(2.6, bay - 1.3), "h": 4.2, "arch": true, "reveal": 0.32, "trim": trim})
	band(k, kd, f, "stucco", pink, x0, x1, P, T, l_opens)
	grime_run(kd, f, GRIME_SOOT, x0, x1, T - 3.0, T, l_opens, 0.6)
	var back := Face.new(f.o - f.n * depth, f.r, f.w)
	var b_opens: Array = []
	for i: int in range(nb):
		b_opens.append(_rosada_window(x0 + (float(i) + 0.5) * bay, P + 0.3, 1.3, 3.0, 0.12))
	band(k, kd, back, "stucco", pale * 0.82, x0, x1, P, T - 0.3, b_opens, 0.62, 0.5)
	_rosada_joinery(k, kd, back, b_opens)
	grime_run(kd, back, GRIME_BLOTCH, x0, x1, P, T - 0.3, b_opens, 0.55)
	grime_run(kd, back, GRIME_SOOT, x0, x1, T - 1.6, T - 0.3, b_opens, 0.8)
	# its floor, its ceiling, and the walls closing its ends
	k.push_tint(pale * 0.7)
	k.box("stone", Vector3((x0 + x1) * 0.5, P - 0.1 + 0.12, f.o.z - depth * 0.5 + 0.0), Vector3(x1 - x0, 0.2, depth), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.box("stucco", Vector3((x0 + x1) * 0.5, T - 0.25, f.o.z - depth * 0.5), Vector3(x1 - x0, 0.1, depth), Color(0.4, 0.4, 0.4), Color(0.5, 0.5, 0.5))
	k.pop_tint()
	for x: float in [x0, x1]:
		k.push_tint(pink * 0.8)
		k.box("stucco", Vector3(x, (P + T) * 0.5, f.o.z - depth * 0.5), Vector3(0.3, T - P, depth), Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
	# the snow on the loggia's floor at the arches, the rain's streaks down from them
	for o: Dictionary in l_opens:
		ridge(k, f.at(float(o.x) - float(o.w) * 0.5, P + 0.25, -0.12), f.at(float(o.x) + float(o.w) * 0.5, P + 0.25, -0.12), Vector3.UP, 0.34, 0.1)
		k.push_tint(trim)
		balustrade(k, kd, f.at(float(o.x) - float(o.w) * 0.5, P + 0.25, -0.16), f.at(float(o.x) + float(o.w) * 0.5, P + 0.25, -0.16), 0.95, trim, 9.0)
		k.pop_tint()
		grime(kd, f, GRIME_SILL, float(o.x) - float(o.w) * 0.5, float(o.x) + float(o.w) * 0.5, P - 1.6, P + 0.2, 0.8)

## A window's raised surround and its cap: a triangular or a segmental pediment (kind 0 / 1), or a plain cornice.
func _surround(k: Kit, f: Face, x: float, y: float, w: float, h: float, trim: Color, kind: int) -> void:
	var band_w := 0.16
	var tl := trim_layer
	fbox(k, f, tl, x - w * 0.5 - band_w * 0.5, y + h * 0.5, 0.04, band_w, h, 0.08, trim, 0.85)
	fbox(k, f, tl, x + w * 0.5 + band_w * 0.5, y + h * 0.5, 0.04, band_w, h, 0.08, trim, 0.85)
	fbox(k, f, tl, x, y + h + 0.12, 0.06, w + band_w * 2.0 + 0.1, 0.24, 0.12, trim, 0.85)
	var top := y + h + 0.24
	fbox(k, f, tl, x, top + 0.07, 0.14, w + 0.8, 0.14, 0.28, trim, 0.85)
	var pk := top + 0.14
	if kind == 0:
		# a triangular pediment: its two raking cornices and the tympanum
		var a := f.at(x - w * 0.5 - 0.4, pk, 0.02)
		var b := f.at(x + w * 0.5 + 0.4, pk, 0.02)
		var c := f.at(x, pk + 0.62, 0.02)
		k.push_tint(trim)
		k.tri(tl, a, b, c, Vector2(0, 0), Vector2(0.3, 0), Vector2(0.15, 0.1))
		k.beam(tl, a + f.n * 0.12, c + f.n * 0.12, 0.26, 0.14, Color(0.85, 0.85, 0.85), Color.WHITE)
		k.beam(tl, c + f.n * 0.12, b + f.n * 0.12, 0.26, 0.14, Color(0.85, 0.85, 0.85), Color.WHITE)
		k.pop_tint()
		ridge(k, a + f.n * 0.12 + Vector3(0, 0.07, 0), c + f.n * 0.12 + Vector3(0, 0.07, 0), Vector3.UP, 0.22, 0.07)
		ridge(k, c + f.n * 0.12 + Vector3(0, 0.07, 0), b + f.n * 0.12 + Vector3(0, 0.07, 0), Vector3.UP, 0.22, 0.07)
	else:
		ridge(k, f.at(x - w * 0.5 - 0.4, pk, 0.14), f.at(x + w * 0.5 + 0.4, pk, 0.14), Vector3.UP, 0.26, 0.1)

## A stone balcony on brackets: the slab under its snow, the balustrade round its front and ends.
func _balcony(k: Kit, kd: Kit, f: Face, x0: float, x1: float, y: float, trim: Color, depth: float = 0.7) -> void:
	fbox(k, f, trim_layer, (x0 + x1) * 0.5, y - 0.1, depth * 0.5, x1 - x0, 0.2, depth, trim, 0.7)
	for x: float in [x0 + 0.2, x1 - 0.2]:
		fbox(k, f, trim_layer, x, y - 0.45, depth * 0.35, 0.2, 0.5, depth * 0.6, trim, 0.7)
	pillow(k, face_poly(f, x0 + 0.05, x1 - 0.05, 0.05, depth - 0.05), y, 0.1, 0.2)
	var hb := 0.9
	balustrade(k, kd, f.at(x0 + 0.12, y, depth - 0.15), f.at(x1 - 0.12, y, depth - 0.15), hb, trim, 9.0)
	balustrade(k, kd, f.at(x0 + 0.12, y, 0.05), f.at(x0 + 0.12, y, depth - 0.15), hb, trim, 9.0)
	balustrade(k, kd, f.at(x1 - 0.12, y, depth - 0.15), f.at(x1 - 0.12, y, 0.05), hb, trim, 9.0)

## An end pavilion: projecting a little, quoins at its corners, the same storeys with pedimented windows, and over the
## cornice a dark slate mansard with dormers and an iron cresting, snow along its foot and on its top.
func _rosada_pavilion(k: Kit, kd: Kit, x0: float, x1: float, zp: float, zw: float, G: float, P: float, T: float, pink: Color, pale: Color, trim: Color, D: float) -> void:
	var f := Face.new(Vector3(0, 0, zp), Vector3.RIGHT, x1)
	var w := x1 - x0
	var nb := maxi(2, int(round(w / 4.4)))
	var bay := w / float(nb)
	var g_opens: Array = []
	var p_opens: Array = []
	var t_opens: Array = []
	for i: int in range(nb):
		var x := x0 + (float(i) + 0.5) * bay
		var o := _rosada_window(x, 1.0, 1.6, 3.8, 0.4, true)
		g_opens.append(o)
		if bool(o.lit): spill_at(f.at(x, 0.0, 0.0), f.n, 1.6, 2.2, 0.32)
		p_opens.append(_rosada_window(x, G + 0.8, 1.6, 3.7, 0.3))
		t_opens.append(_rosada_window(x, P + 0.8, 1.5, 3.2, 0.28))
	band(k, kd, f, "rustic", ROSADA_RUSTIC, x0, x1, 0.0, G, g_opens, 0.7, 0.86)
	band(k, kd, f, "stucco", pink, x0, x1, G, P, p_opens)
	band(k, kd, f, "stucco", pink, x0, x1, P, T, t_opens)
	_rosada_joinery(k, kd, f, g_opens, true)
	_rosada_joinery(k, kd, f, p_opens)
	_rosada_joinery(k, kd, f, t_opens)
	for i: int in range(nb):
		var gx := float(g_opens[i].x)
		_surround(k, f, float(p_opens[i].x), G + 0.8, 1.6, 3.7, trim, 0)
		_surround(k, f, float(t_opens[i].x), P + 0.8, 1.5, 3.2, trim, 1)
		ridge(k, f.at(gx - 0.9, 0.98, 0.1), f.at(gx + 0.9, 0.98, 0.1), Vector3.UP, 0.22, 0.07)
		fbox(k, f, "stone", gx, 0.93, 0.06, 1.9, 0.14, 0.24, trim)
		fbox(k, f, "stone", float(p_opens[i].x), G + 0.74, 0.08, 2.0, 0.12, 0.24, trim)
		fbox(k, f, "stone", float(t_opens[i].x), P + 0.74, 0.08, 1.9, 0.12, 0.24, trim)
		ridge(k, f.at(float(t_opens[i].x) - 0.95, P + 0.8, 0.12), f.at(float(t_opens[i].x) + 0.95, P + 0.8, 0.12), Vector3.UP, 0.22, 0.07)
		grime(kd, f, GRIME_SILL, gx - 1.0, gx + 1.0, 0.1, 0.86, 0.7)
		grime(kd, f, GRIME_SILL, float(t_opens[i].x) - 1.05, float(t_opens[i].x) + 1.05, P - 1.6, P + 0.66, 0.85)
	_balcony(k, kd, f, x0 + bay * 0.5 - 1.2, x1 - bay * 0.5 + 1.2, G + 0.72, trim, 0.9)
	grime(kd, f, GRIME_SILL, x0 + bay * 0.5 - 1.25, x1 - bay * 0.5 + 1.25, G - 1.2, G + 0.2, 0.95)
	grime_run(kd, f, GRIME_DAMP, x0, x1, 0.0, 2.1, g_opens, 0.8)
	grime_run(kd, f, GRIME_SOOT, x0, x1, G - 2.6, G - 0.18, g_opens, 0.55)
	grime_run(kd, f, GRIME_SOOT, x0, x1, P - 2.6, P - 0.12, p_opens, 0.5)
	grime_run(kd, f, GRIME_SOOT, x0, x1, T - 3.0, T, t_opens, 0.6)
	# quoins: rusticated blocks up both corners
	for x: float in [x0 + 0.45, x1 - 0.45]:
		var y := G
		var i := 0
		while y < T - 0.2:
			fbox(k, f, "rustic", x + (0.12 if (i % 2 == 0) == (x < (x0 + x1) * 0.5) else -0.12), y + 0.3, 0.06, 1.0 if i % 2 == 0 else 0.76, 0.56, 0.12, pale, 0.8)
			y += 0.62
			i += 1
	# the side wall of the projection
	var sf := Face.new(Vector3(x1, 0, zp), Vector3(0, 0, -1), zp - zw) if x0 < 1.0 else Face.new(Vector3(x0, 0, zw), Vector3(0, 0, 1), zp - zw)
	k.push_tint(pink)
	k.quad4("stucco", sf.at(0, 0), sf.at(sf.w, 0), sf.at(sf.w, T), sf.at(0, T), Vector2(0, 1), Vector2(sf.w * Kit.UV_M, 1), Vector2(sf.w * Kit.UV_M, 1.0 - T * Kit.UV_M), Vector2(0, 1.0 - T * Kit.UV_M), Color(0.62, 0.62, 0.62), Color(0.62, 0.62, 0.62), Color.WHITE, Color.WHITE)
	k.pop_tint()
	grime(kd, sf, GRIME_DAMP, 0.0, sf.w, 0.0, 2.1, 1.0)
	grime(kd, sf, GRIME_SOOT, 0.0, sf.w, T - 3.0, T, 0.6)
	# the mansard: dark slate rising steeply from behind the cornice to a flat top, dormers on its front
	var y0 := T + 1.05
	var y1 := T + 5.6
	var base := rect_poly(x0 + 0.5, -minf(D, 18.0), x1 - 0.5, zp - 0.5)
	var top := Snow.inset(base, 1.8)
	var slate := Color(0.2, 0.21, 0.24)
	k.push_tint(slate)
	for i: int in range(4):
		var j := (i + 1) % 4
		k.quad_m("slate", Vector3(base[i].x, y0, base[i].y), Vector3(base[j].x, y0, base[j].y), Vector3(top[j].x, y1, top[j].y), Vector3(top[i].x, y1, top[i].y))
	k.pop_tint()
	for i: int in range(4):
		var j := (i + 1) % 4
		ridge(k, Vector3(base[i].x, y0, base[i].y), Vector3(base[j].x, y0, base[j].y), Vector3.UP, 0.5, 0.16, 0.05)
	roof_slab(k, top, y1, Color(0.22, 0.22, 0.24), 0.24)
	k.push_tint(Color(0.32, 0.32, 0.34))
	for i: int in range(4):
		var j := (i + 1) % 4
		k.beam("metal", Vector3(top[i].x, y1 + 0.04, top[i].y), Vector3(top[j].x, y1 + 0.04, top[j].y), 0.1, 0.1, Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	# iron cresting along the top's front edge
	var ca := Vector3(top[3].x, y1 + 0.05, top[3].y)
	var cb := Vector3(top[2].x, y1 + 0.05, top[2].y)
	var cl2 := ca.distance_to(cb)
	var s := 0.0
	while s < cl2 - 0.01:
		var t := minf(2.0, cl2 - s)
		var p0 := ca.lerp(cb, s / cl2)
		var p1 := ca.lerp(cb, (s + t) / cl2)
		kd.quad_rect(CUT, p0, p1, p1 + Vector3(0, 0.55, 0), p0 + Vector3(0, 0.55, 0), uv_part("rail_ornate", 0.0, t / 2.0), Color(0.12, 0.12, 0.13), Color(0.15, 0.15, 0.16))
		s += t
	# dormers on the front slope
	var nd := maxi(1, int(round((x1 - x0 - 2.0) / 4.0)))
	for i: int in range(nd):
		var x := x0 + 0.5 + (float(i) + 0.5) * (x1 - x0 - 1.0) / float(nd)
		var zf := zp - 0.5 - 0.6
		var yb := y0 + 1.0
		k.push_tint(trim)
		k.box("stone", Vector3(x, yb + 0.85, zf - 0.4), Vector3(1.5, 1.7, 1.0), Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
		var l := is_lit()
		kd.quad_rect(LIT if l else SOLID, Vector3(x - 0.42, yb + 0.45, zf + 0.11), Vector3(x + 0.42, yb + 0.45, zf + 0.11), Vector3(x + 0.42, yb + 1.29, zf + 0.11), Vector3(x - 0.42, yb + 1.29, zf + 0.11), uv("oculus_lit" if l else "oculus_dark"), warm() * 0.6 if l else Color.WHITE, warm() * 0.6 if l else Color.WHITE)
		# a little triangular pediment over it, its slopes in slate under snow
		var pa := Vector3(x - 0.85, yb + 1.7, zf + 0.12)
		var pb := Vector3(x + 0.85, yb + 1.7, zf + 0.12)
		var pc := Vector3(x, yb + 2.3, zf + 0.12)
		k.push_tint(trim)
		k.tri("stone", pa, pb, pc, Vector2(0, 0), Vector2(0.4, 0), Vector2(0.2, 0.2))
		k.box("stone", Vector3(x, yb + 1.64, zf - 0.38), Vector3(1.8, 0.12, 1.06), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		k.push_tint(slate)
		k.quad_m("slate", pa + Vector3(0, 0, -1.0), pa, pc, pc + Vector3(0, 0, -1.0))
		k.quad_m("slate", pb, pb + Vector3(0, 0, -1.0), pc + Vector3(0, 0, -1.0), pc)
		k.pop_tint()
		ridge(k, pc + Vector3(0, 0.02, 0.0), pc + Vector3(0, 0.02, -1.0), Vector3.UP, 0.3, 0.1, 0.04)
		ridge(k, Vector3(x - 0.5, yb + 0.2, zf + 0.16), Vector3(x + 0.5, yb + 0.2, zf + 0.16), Vector3.UP, 0.16, 0.06)

## Tamburini's central block: the great arch through two storeys between paired columns on pedestals, an iron gate
## across it and the passage behind lit warm, the entablature over the columns, three balconied windows above, and the
## attic rising over the main cornice, the flag on top.
func _rosada_centre(k: Kit, kd: Kit, cl: float, cr: float, zc: float, zw: float, G: float, P: float, T: float, pink: Color, pale: Color, trim: Color) -> void:
	var f := Face.new(Vector3(0, 0, zc), Vector3.RIGHT, cr)
	var cw := cr - cl
	var cx := (cl + cr) * 0.5
	var aw := minf(7.0, cw * 0.4)
	var spring := 7.2
	var ent := P - 0.8
	# the arch through the ground floor and the piano nobile; the gate across it, the passage lit warm behind
	var opens: Array = [{"x": cx, "y": 0.0, "w": aw, "h": spring + aw * 0.5, "arch": true, "reveal": 2.6, "trim": trim}]
	band(k, kd, f, "rustic", ROSADA_RUSTIC, cl, cr, 0.0, ent, opens, 0.7, 0.86)
	fquad(kd, f, LIT, cx - aw * 0.5, cx + aw * 0.5, 0.0, spring + aw * 0.5, -2.58, uv("glow"), Color(1.0, 0.7, 0.42) * 0.62)
	_rosada_gate(k, f, cx, aw, spring, 0.7)
	spill_at(f.at(cx, 0.0, 0.0), f.n, aw, 4.5, 0.7)
	lights.append([xf * f.at(cx, 3.0, -1.0), LAMP, 0.7, 10.0])
	grime_run(kd, f, GRIME_DAMP, cl, cr, 0.0, 2.1, opens, 0.8)
	grime_run(kd, f, GRIME_SOOT, cl, cr, ent - 2.6, ent, opens, 0.5)
	# the passage's floor
	k.push_tint(Color(0.42, 0.4, 0.38))
	k.box("ashlar", Vector3(cx, 0.03, zc - 1.3), Vector3(aw, 0.06, 2.6), Color.WHITE, Color.WHITE)
	k.pop_tint()
	# paired columns on pedestals either side of the arch
	for s: float in [-1.0, 1.0]:
		for c: int in range(2):
			var x := cx + s * (aw * 0.5 + 1.3 + float(c) * 1.55)
			k.push_tint(trim)
			k.box("stone", Vector3(x, 1.1, zc + 0.75), Vector3(1.3, 2.2, 1.3), Color(0.55, 0.55, 0.55), Color.WHITE)
			k.pop_tint()
			box_top(k, Vector3(x, 2.2, zc + 0.75), Vector2(1.3, 1.3), 0.1)
			column(k, "stone", Vector3(x, 2.2, zc + 0.75), ent - 2.2, 0.42, trim * 0.97, true, 12)
			grime(kd, Face.new(Vector3(x - 0.65, 0, zc + 1.4), Vector3.RIGHT, 1.3), GRIME_DAMP, 0.0, 1.3, 0.0, 1.3, 0.8, 0.01)
	# the entablature over the columns, projecting with them
	var ent_path := PackedVector2Array([Vector2(cl + 0.4, zc), Vector2(cl + 0.4, zc + 1.4), Vector2(cr - 0.4, zc + 1.4), Vector2(cr - 0.4, zc)])
	k.push_tint(trim)
	k.box("stone", Vector3(cx, ent + 0.45, zc + 0.7), Vector3(cw - 0.8, 0.9, 1.4), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	moulding(k, "stone", ent_path, ent + 0.9, prof_string(0.35, 0.45), trim)
	# over the entablature: three tall windows with a balcony across them
	var u_opens: Array = []
	for i: int in range(3):
		var o := _rosada_window(cx + (float(i) - 1.0) * 3.0, P + 0.6, 1.6, 3.6, 0.3)
		if i == 1 and not bool(o.lit):
			o.cell = window_cell(true)
			o.key = LIT
			o.col = warm() * 1.2
			o.erase("shut")
		u_opens.append(o)
	band(k, kd, f, "stucco", pink, cl, cr, ent, T, u_opens)
	_rosada_joinery(k, kd, f, u_opens)
	for o: Dictionary in u_opens: _surround(k, f, float(o.x), P + 0.6, 1.6, 3.6, trim, 0)
	grime_run(kd, f, GRIME_SOOT, cl, cr, T - 3.0, T, u_opens, 0.6)
	balustrade(k, kd, Vector3(cl + 0.6, ent + 1.35, zc + 1.2), Vector3(cr - 0.6, ent + 1.35, zc + 1.2), 0.95, trim, 3.0)
	pillow(k, rect_poly(cl + 0.5, zc + 0.1, cr - 0.5, zc + 1.3), ent + 1.35, 0.12, 0.3)
	for s: float in [-1.0, 1.0]:
		fbox(k, f, "stucco", cx + s * (cw * 0.5 - 0.4), (ent + T) * 0.5, 0.08, 0.7, T - ent, 0.16, pale)
	# the sides of the projection
	for sf: Face in [Face.new(Vector3(cl, 0, zw), Vector3(0, 0, 1), zc - zw), Face.new(Vector3(cr, 0, zc), Vector3(0, 0, -1), zc - zw)]:
		k.push_tint(pink)
		k.quad4("stucco", sf.at(0, 0), sf.at(sf.w, 0), sf.at(sf.w, T + 5.2), sf.at(0, T + 5.2), Vector2(0, 1), Vector2(sf.w * Kit.UV_M, 1), Vector2(sf.w * Kit.UV_M, 1.0 - T * Kit.UV_M), Vector2(0, 1.0 - T * Kit.UV_M), Color(0.62, 0.62, 0.62), Color(0.62, 0.62, 0.62), Color.WHITE, Color.WHITE)
		k.pop_tint()
		grime(kd, sf, GRIME_DAMP, 0.0, sf.w, 0.0, 2.1, 1.0)
	# the attic over the main cornice: a panel between pilasters, its own cornice and balustrade
	var ya := T + 1.05
	var yt := T + 4.4
	var af := Face.new(Vector3(0, 0, zc - 0.5), Vector3.RIGHT, cr)
	k.push_tint(pink)
	k.box("stucco", Vector3(cx, (ya + yt) * 0.5, zc - 0.5 - 3.0), Vector3(cw - 1.2, yt - ya, 6.0), Color(0.62, 0.62, 0.62), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	fbox(k, af, "stone", cx, (ya + yt) * 0.5, 0.08, cw * 0.45, (yt - ya) * 0.6, 0.12, trim * 0.96)
	for s: float in [-1.0, 1.0]:
		fbox(k, af, "stucco", cx + s * (cw * 0.5 - 1.0), (ya + yt) * 0.5, 0.1, 0.8, yt - ya, 0.2, pale)
	grime(kd, af, GRIME_SOOT, cl + 0.6, cr - 0.6, yt - 1.8, yt, 0.6, 0.22)
	var attic_path := PackedVector2Array([Vector2(cl + 0.6, zc - 6.5), Vector2(cl + 0.6, zc - 0.5), Vector2(cr - 0.6, zc - 0.5), Vector2(cr - 0.6, zc - 6.5)])
	moulding(k, "stone", attic_path, yt, prof_cornice(0.5, 0.6), trim)
	balustrade(k, kd, Vector3(cl + 0.8, yt + 0.6, zc - 0.6), Vector3(cr - 0.8, yt + 0.6, zc - 0.6), 0.9, trim, 3.4, true)
	roof_slab(k, rect_poly(cl + 0.6, zc - 6.5, cr - 0.6, zc - 0.5), yt + 0.6, Color(0.3, 0.28, 0.28))

## The iron gate across the great arch, `depth` in from the front: square uprights from the ground to the arch, their
## spear points under it, rails across, the fanlight's bars radiating from a half-wheel over the springing; dark iron.
func _rosada_gate(k: Kit, f: Face, cx: float, aw: float, spring: float, depth: float) -> void:
	var r := aw * 0.5 - 0.06
	var z := -depth
	k.push_tint(Color(0.05, 0.05, 0.055))
	var n := int((aw - 0.3) / 0.26)
	for i: int in range(n + 1):
		var x := cx - r + 0.15 + (2.0 * r - 0.3) * float(i) / float(n)
		var dx := x - cx
		var top := minf(spring + sqrt(maxf(r * r - dx * dx, 0.0)) - 0.06, spring)
		k.box("metal", f.at(x, top * 0.5, z), Vector3(0.05, top, 0.05), Color(0.7, 0.7, 0.7), Color.WHITE)
	for y: float in [0.2, 1.1, 3.4, spring - 0.08]:
		k.box("metal", f.at(cx, y, z), Vector3(2.0 * r - 0.1, 0.08, 0.07), Color.WHITE, Color.WHITE)
	# the two leaves' meeting stiles, heavier
	k.box("metal", f.at(cx, spring * 0.5, z + 0.02), Vector3(0.12, spring, 0.09), Color(0.7, 0.7, 0.7), Color.WHITE)
	# the fanlight: a half-wheel and its spokes
	var hub := f.at(cx, spring, z)
	for j: int in range(1, 10):
		var a := PI * float(j) / 10.0
		k.beam("metal", hub, f.at(cx + cos(a) * r, spring + sin(a) * r, z), 0.05, 0.05)
	var prev := f.at(cx + r * 0.42, spring, z)
	for j: int in range(1, 9):
		var a := PI * float(j) / 8.0
		var p := f.at(cx + cos(a) * r * 0.42, spring + sin(a) * r * 0.42, z)
		k.beam("metal", prev, p, 0.06, 0.06)
		prev = p
	k.pop_tint()

## A flagpole standing on a roof (or the ground) with the flag waving from it: `at` the pole's foot in the node's space.
func flagpole_on(node: Node3D, at: Vector3, height: float, fly: float) -> MeshInstance3D:
	var k := Kit.new()
	var saved := Kit.aliases
	Kit.aliases = _aliases
	k.push_tint(Color(0.85, 0.85, 0.82))
	k.lathe("metal", at, PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.09, height * 0.5), Vector2(0.06, height)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	k.push_tint(Color(1.0, 0.8, 0.4))
	k.lathe("bronze", at + Vector3(0, height, 0), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.14, 0.12), Vector2(0.12, 0.25), Vector2(0.0, 0.3)]), 8, Color.WHITE, Color.WHITE)
	k.pop_tint()
	Kit.aliases = saved
	var m := k.commit(node, materials, "Pole", true)
	if m != null: _stat("Flagpole", m.mesh.get_faces().size() / 3, m.mesh.get_surface_count(), 1)
	return flag(node, at + Vector3(0, height - 0.15, 0), fly)

## The national flag in cloth, waving (plaza_flag.gdshader): its hoist at `at` (the node's space), flying along the
## node's +x turned by `yaw`. Light blue, white, light blue, the Sun of May.
func flag(node: Node3D, at: Vector3, fly: float = 2.4, yaw: float = 0.0) -> MeshInstance3D:
	var hoist := fly * 9.0 / 14.0
	var cols := 14
	var rows := 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in range(rows + 1):
		for i: int in range(cols + 1):
			var u := float(i) / float(cols)
			var v := float(j) / float(rows)
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(u * fly, -v * hoist, 0.0))
	for j: int in range(rows):
		for i: int in range(cols):
			var a := j * (cols + 1) + i
			st.add_index(a)
			st.add_index(a + cols + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + cols + 1)
			st.add_index(a + cols + 2)
	var mi := MeshInstance3D.new()
	mi.name = "Flag"
	mi.mesh = st.commit()
	var m: ShaderMaterial = _flag_material.duplicate()
	m.set_shader_parameter("fly", fly)
	m.set_shader_parameter("phase", rng.randf() * 10.0)
	mi.material_override = m
	mi.position = at
	mi.rotation.y = yaw
	mi.extra_cull_margin = fly
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mi)
	_stat("Flag", rows * cols * 2, 1, 1)
	return mi

# ---------------------------------------------------------------------------------------------------------------
# Shared batches
# ---------------------------------------------------------------------------------------------------------------
## Commits what the builders gathered: the light pools on the snow, the lamps' halos and their glow in the damp air,
## and the lamp posts, palms, plane trees and benches as multimeshes (one draw a surface for all of each).
func finish() -> void:
	var saved := Kit.aliases
	Kit.aliases = _aliases
	props.commit_batches(_lamp_posts, _palms, _trees, _benches)
	props.commit_play(_snowmen, _trails)
	Kit.aliases = saved
	if not _pools.surfs.is_empty():
		var tris := _pools.triangle_count()
		var m := _pools.commit(root, materials, "LightPools", false)
		if m != null: _stat("LightPools", tris, 1, 1)
		_pools = Kit.new()
	if not _halos.is_empty():
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		var big: Array = []
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
			if s >= 0.9: big.append(h)
		var node := MultiMeshInstance3D.new()
		node.name = "Halos"
		node.multimesh = mm
		node.material_override = materials["halo"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 120, 800))
		root.add_child(node)
		_stat("Halos", 2 * _halos.size(), 1, 1, _halos.size())
		if not big.is_empty():
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
			node2.material_override = materials["fogglow"]
			node2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node2.custom_aabb = node.custom_aabb
			root.add_child(node2)
			_stat("FogGlow", 2 * big.size(), 1, 1, big.size())
		_halos.clear()

## The kit's totals: {"triangles", "draws"} over everything built so far.
func totals() -> Dictionary:
	var t := 0
	var d := 0
	for key: String in stats:
		t += int(stats[key].triangles)
		d += int(stats[key].draws)
	return {"triangles": t, "draws": d}

# ---------------------------------------------------------------------------------------------------------------
# The rest of the kit, by name (plaza_kit_props.gd, plaza_kit_vehicles.gd)
# ---------------------------------------------------------------------------------------------------------------
func piramide(pos: Vector3, facing: Vector3 = EAST, fence: bool = true, corner_lamps: bool = true) -> Node3D:
	return props.piramide(pos, facing, fence, corner_lamps)

func cabildo(rect: Rect2, facing: Vector3 = EAST, each_side: int = 2, floodlit: float = 0.6) -> Node3D:
	return buildings.cabildo(rect, facing, each_side, floodlit)

func catedral(rect: Rect2, facing: Vector3 = SOUTH, floodlit: float = 0.6) -> Node3D:
	return buildings.catedral(rect, facing, floodlit)

func banco_nacion(rect: Rect2, facing: Vector3 = SOUTH) -> Node3D:
	return buildings.banco_nacion(rect, facing)

func ministerios(rect: Rect2, facing: Vector3 = NORTH, floors: int = 10) -> Node3D:
	return buildings.ministerios(rect, facing, floors)

func avenida_de_mayo(rect: Rect2, facing: Vector3 = SOUTH, corners: bool = true, seed_value: int = 0) -> Node3D:
	return buildings.avenida_de_mayo(rect, facing, corners, seed_value)

func car(pos: Vector3, yaw: float = 0.0, kind: String = "sedan", paint: Color = Color(0, 0, 0, 0), open: Array = [], lights: bool = false, snowed_in: bool = true) -> Node3D:
	return vehicles.car(pos, yaw, kind, paint, open, lights, snowed_in)

func colectivo(pos: Vector3, yaw: float = 0.0, lower: Color = Color(0, 0, 0, 0), upper: Color = Color(0, 0, 0, 0), lit_inside: bool = true, open: bool = false, snowed_in: bool = false) -> Node3D:
	return vehicles.colectivo(pos, yaw, lower, upper, lit_inside, open, snowed_in)

func tram(pos: Vector3, yaw: float = 0.0, lit_inside: bool = true, wire_y: float = 5.6) -> Node3D:
	return vehicles.tram(pos, yaw, lit_inside, wire_y)

func truck(pos: Vector3, yaw: float = 0.0, paint: Color = Color(0, 0, 0, 0), open: bool = false, snowed_in: bool = true) -> Node3D:
	return vehicles.truck(pos, yaw, paint, open, snowed_in)

func belgrano(pos: Vector3, facing: Vector3 = WEST) -> Node3D:
	return props.belgrano(pos, facing)

func lawn(rect: Rect2, fence: bool = true, shrubs: int = 0) -> Node3D:
	return props.lawn(rect, fence, shrubs)

func subte_entrance(rect: Rect2, facing: Vector3 = SOUTH) -> Node3D:
	return props.subte_entrance(rect, facing)

func kiosk(pos: Vector3, facing: Vector3 = SOUTH) -> Node3D:
	return props.kiosk(pos, facing)

func flagpole(pos: Vector3, height: float = 14.0, wind: Vector3 = EAST) -> Node3D:
	return props.flagpole(pos, height, wind)

func palm(pos: Vector3, scale: float = 1.0) -> void:
	_palms.append([pos, scale])

func plane_tree(pos: Vector3, scale: float = 1.0) -> void:
	_trees.append([pos, scale])

func lamp_post(pos: Vector3, arms: int = 4) -> void:
	_lamp_posts.append([pos, arms])

func bench(pos: Vector3, yaw: float = 0.0) -> void:
	_benches.append([pos, yaw])

## A snowman the children made (in 1918 the square filled with them and with snowball fights, the notes), with the
## ground trodden round it.
func snowman(pos: Vector3, scale: float = 1.0) -> void:
	_snowmen.append([pos, scale])

## A trail of boot prints through the snow along a path of world points (x, z) at a height y (0 on the ground, 0.12 on
## one of the kit's lawns): somebody's way across.
func trail(points: PackedVector2Array, y: float = 0.0) -> void:
	_trails.append([points, y])
