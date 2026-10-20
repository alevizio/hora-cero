extends "res://scripts/three_d/boca.gd"
## Everything standing round the Plaza de Mayo on the night the snow begins (Plaza de Mayo, 1958), built from the Plaza
## de Mayo kit (plaza_kit.gd, with its buildings, props and vehicles): the Casa Rosada across the east side, pink and
## floodlit, the national flag over Tamburini's arch; the Cabildo on the west, white, its arcade and its tower; the
## Catedral's portico of twelve columns over its steps on Rivadavia; the Banco de la Nación; the ministries along
## Hipólito Yrigoyen; Avenida de Mayo's fronts, the Palacio Municipal's corner among them, and the city's round the
## square; in the square the Pirámide de Mayo, the Belgrano, the flagpole and its flag, the eight palms, the cast-iron
## lamps, the benches, the newspaper kiosk and the subte's three stairs down; the tram on Rivadavia, the colectivo on
## Yrigoyen, cars of the time parked at the kerbs. Each stands on the rules' own rectangles (data plazaWorld, written
## by tools/dev/plaza_layout.py), which follow the kit's footprints: what stands where is where the walk and the cover
## are.
##
## Its own builders only for what the kit has not: the tram line's rails and wires, the subte's service gate, the
## café's front and its awning, the vendor's cart, the cloths (on their frames, then held up), the drifts against the
## walls and the mounds over the fallen, the darkness in the arcade until its lanterns are mended.
##
## It stands in for La Boca's structures (it extends them, for their materials, lights, light pools and faders) and
## keeps the same interface for world.gd: build(), update(), on_sim_event(), and ground_height() (down the subte's
## stairs, up into the tram and the colectivo, on the Catedral's stylobate and its steps, the Banco's porch, the
## Cabildo's arcade). The night's snow builds up with the rules' clock: on the kit's walls, ledges, palms and statues
## (its shaders' snow_amount), in drifts against the walls, in mounds over whoever has fallen. The tram runs with the
## rules' vehicle, the cloths go when they are taken, the arcade's lanterns light when Lechuza mends them, the service
## gate swings open when he unlocks it, and the square's lamps stutter now and then, more in a wave.

const PlazaGround = preload("res://scripts/three_d/plaza_ground.gd")
const PlazaKit = preload("res://scripts/three_d/plaza_kit.gd")
const PlazaCity = preload("res://scripts/three_d/plaza_city.gd")
const PlazaDetails = preload("res://scripts/three_d/plaza_details.gd")
## The vehicles made from the friends' models (tools/vehicles.gd), and their shader.
const VehicleShader := preload("res://shaders/plaza_vehicle.gdshader")
const VehicleGlassShader := preload("res://shaders/plaza_vehicle_glass.gdshader")
const VEHICLES := "res://assets/vehicles/"
const DriftShader := preload("res://shaders/plaza_drift.gdshader")
## Juan Salvo and the cascarudos: who of them shows, and their marks on the ground (plaza_creatures.gd).
const PlazaCreatures := preload("res://scripts/three_d/plaza_creatures.gd")
## The national flag's cloth (the kit's: on the Casa Rosada and on the square's flagpole).
const FlagShader := PlazaKit.FlagShader
const UP := Vector3.UP
## How much snow the kit lays as geometry on ledges, roofs, statues and cars (its shaders whiten the rest as the snow
## falls), and the share of the windows round the square lit from inside at ten past nine.
const KIT_SNOW := 0.6
const KIT_LIT := 0.5
## The tram line's contact wires (metres up), and the kit's tram (2.4 x 11.6 m) before it is fitted to the rules' car.
const WIRE_Y := 5.9
const KIT_TRAM := Vector2(2.4, 11.6)

var pw: Dictionary = {}
var stair_rects: Array[Rect2] = []
var stair_depth: float = 4.2
## The kit the square is built from, and the tram's own (its light on the snow and its headlamp go with it).
var pk: PlazaKit
var tram_kit: PlazaKit
## The tram (moved with the rules' vehicle).
var tram: Node3D
## The cloths on their frames, by canvas id (gone once taken), and the ones held up over the operatives who took them.
var cloths: Dictionary = {}
var _held: Array[MeshInstance3D] = []
var _flags: Array[ShaderMaterial] = []
var _mounds: MultiMesh
var _drifts: Array[Node3D] = []
## The banks of snow against the walls (one material: their `grow` follows the night) and the one being gathered.
var _drift_material: ShaderMaterial
var _bank_v := PackedVector3Array()
var _bank_n := PackedVector3Array()
var _bank_c := PackedColorArray()
var _bank_uv2 := PackedVector2Array()
var _bank_i := PackedInt32Array()
var _gate_leaf: Node3D
var _gate_angle: float = 0.0
var _arcade_shade: MeshInstance3D
## The arcade's lanterns: their glass taken out of the Cabildo's detail as the kit made it (lit), and its unlit twin.
var _lanterns_lit: MeshInstance3D
var _lanterns_dark: MeshInstance3D
## The kit's halos and their glow in the damp air (a multimesh each), and every instance's own colour, so that a lamp
## can stutter or stay dark (each lamp's instances: its entry's "halos" and "fogs").
var _halo_mm: MultiMesh
var _fog_mm: MultiMesh
var _halo_base := PackedColorArray()
var _fog_base := PackedColorArray()
var _snow_set: float = -1.0
var _wave: float = 0.0
var creatures: Node3D
## The city beyond the square's rows (plaza_city.gd: the blocks, the far avenue to the Congreso, the Diagonales, the
## port), and the kit's traffic out there before it is folded into a few meshes.
var city: PlazaCity
var _far_kit: Array[Node3D] = []
## The city's small things (plaza_details.gd); the kiosks to dress; the subte's stairs ([node, sign width]).
var details: PlazaDetails
var _kiosks: Array[Node3D] = []
var _stairs: Array = []
## The friends' vehicles: the rules' colectivo (the Línea 60, lit, its door open; the kit's own colectivo in a build
## without its model), and the fleet out in the city (model -> [[transform, paint, in service]]) drawn as a multimesh a
## district; their materials (for the snow).
var bus: Node3D
var _fleet: Dictionary = {}
var _vehicle_mats: Array[ShaderMaterial] = []
## The night's haze as the atmosphere set it ([depth fog begin, density, colour]), thickened in a wave (_sync_veil).
var _haze_base: Array = []
var _veil: float = 0.0
var _veil_set: bool = false

func build() -> void:
	rng.seed = 19580525
	# the people of the square must show through what stands between them and the camera too
	fade_for_guards = true
	pw = sim.data.get("plazaWorld", {})
	w = pw
	ground = get_parent().get_node_or_null("Ground") if get_parent() != null else null
	stair_depth = float(pw.get("stairDepth", 4.2))
	for key: String in ["subteN", "subteS", "subteService"]:
		stair_rects.append(PlazaGround.rect_of(pw, key))
	_macro = load("res://assets/tex/nature/macro_noise.png")
	materials = Kit.make_materials()
	_harbour_materials()
	_boca_materials()
	var aliases := {}
	for i: int in range(WALL_LAYERS.size()): aliases[WALL_LAYERS[i]] = ["walls", i]
	aliases["facade"] = ["facade_all", 0]
	aliases["facade_cut"] = ["facade_all", 0]
	aliases["facade_lit"] = ["facade_all", 1]
	Kit.aliases = aliases
	materials["indoor"] = materials["planks"]
	_snow_materials()
	_props = Props.new(19580526)
	_rules = Rules.new(_props, 19580527)
	var gate_at: Array = (sim.passage_by_id("subte-gate").get("anchor", [1696, 4144]) as Array)
	door_point = Vector3(float(gate_at[0]) / 32.0, 0.0, float(gate_at[1]) / 32.0)
	generator_point = door_point
	# the kit: the landmarks, the city round the square, the furniture, the traffic
	pk = PlazaKit.new(self, KIT_SNOW, KIT_LIT, 1958)
	_landmarks()
	_municipal()
	_city()
	_furniture()
	_traffic()
	_cafe_front()
	_surroundings()
	var before := get_child_count()
	pk.finish()
	_kit_batches(before)
	_fold_city(before)
	_build_fleet()
	_dress_city()
	_build_plaza_tram()
	# what the kit has not
	_service_gate()
	_tram_line()
	_cart(_r("cart", [88.0, 140.0, 92.0, 142.2]))
	_cafe_awning(_pair2("awning", Vector2(22.0, 73.6)))
	_kiosk_tarp(_r("kiosk", [150.3, 33.4, 152.7, 35.1]))
	_kit_lights()
	_cabildo_lights()
	_build_drifts()
	_build_mounds()
	_build_held()
	_commit_pools()
	_build_traps()
	Kit.aliases = {}
	_sync_rules(1.0)
	_sync_power(1.0, true)
	_sync_snow(true)
	creatures = PlazaCreatures.new()
	creatures.name = "Creatures"
	add_child(creatures)
	creatures.setup(self)

func _r(key: String, fallback: Array) -> Rect2:
	return PlazaGround.rect_of(pw, key, fallback)

func _pair2(key: String, fallback: Vector2) -> Vector2:
	return PlazaGround.pair_of(pw, key, fallback)

## A building of the kit fades to a dither while somebody stands behind it (as La Boca's do), its body and detail
## together (and, in comic ink, goes altogether).
func _fade(piece: Node3D) -> Node3D:
	for child: Node in piece.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null and not str(child.name) in ["Flag", "Pole"]:
			_make_fader(child as MeshInstance3D)
	return piece

# ---------------------------------------------------------------------------------------------------------------
# The landmarks
# ---------------------------------------------------------------------------------------------------------------
## The square's landmarks, each from the kit on the layout's footprint: the Casa Rosada (floodlit, the flag on its
## attic), the Cabildo (its arcade's lanterns dark until mended), the Catedral (its steps' foot on Rivadavia's
## pavement), the Banco, the two ministries, the Pirámide (its sun toward the Casa Rosada), the Belgrano (looking out
## over the square), the flagpole, the kiosk, the subte's stairs (going down west, the ground open over them).
func _landmarks() -> void:
	var casa := pk.casa_rosada(_r("casaRosada", [256.0, 36.0, 280.0, 132.0]), PlazaKit.WEST, 1.0)
	_fade(casa)
	var cabildo := pk.cabildo(_r("cabildo", [4.0, 100.0, 28.0, 126.0]), PlazaKit.EAST, 2, 0.6)
	_split_lanterns(cabildo)
	_fade(cabildo)
	_fade(pk.catedral(_r("catedral", [44.0, -22.0, 96.0, 22.0]), PlazaKit.SOUTH, 1.0))
	_fade(pk.banco_nacion(_r("banco", [188.0, 0.0, 242.0, 22.0]), PlazaKit.SOUTH))
	# the ministry between Bolívar and Defensa, with an older building of the avenue's kind on the corner beside it
	var mw := _r("ministryW", [28.0, 146.0, 120.0, 166.0])
	var split := mw.position.x + 22.0
	var corner := pk.avenida_de_mayo(Rect2(mw.position.x, mw.position.y, split - mw.position.x, 16.0), PlazaKit.NORTH, true, 1911)
	corner.name = "MinisterioCorner"
	_fade(corner)
	var west := pk.ministerios(Rect2(split, mw.position.y, mw.end.x - split, mw.size.y), PlazaKit.NORTH, 9)
	west.name = "Ministerio"
	_fade(west)
	var east := pk.ministerios(_r("ministryE", [128.0, 146.0, 242.0, 166.0]), PlazaKit.NORTH, 10)
	east.name = "Hacienda"
	_fade(east)
	var c := _pair2("piramide", Vector2(142.0, 84.0))
	pk.piramide(Vector3(c.x, 0.0, c.y), PlazaKit.EAST)
	var b := _pair2("belgrano", Vector2(229.0, 84.0))
	pk.belgrano(Vector3(b.x, 0.0, b.y), PlazaKit.WEST)
	var f := _pair2("flagpole", Vector2(196.0, 56.0))
	var pole := pk.flagpole(Vector3(f.x, 0.0, f.y), 14.0, PlazaKit.SOUTH)
	var kiosk := _r("kiosk", [150.3, 33.4, 152.7, 35.1])
	var kn := pk.kiosk(Vector3(kiosk.get_center().x, 0.0, kiosk.get_center().y), PlazaKit.SOUTH)
	_fade(kn)
	_kiosks.append(kn)
	for r: Rect2 in stair_rects:
		var stair := pk.subte_entrance(r, PlazaKit.EAST)
		stair.name = "Subte_%d_%d" % [int(r.position.x), int(r.position.y)]
		_stairs.append([stair, r.size.y])
	# both flags fly harder in a wave (_sync_snow)
	for holder: Node3D in [casa, pole]:
		var flag := holder.get_node_or_null("Flag") as MeshInstance3D
		if flag != null and flag.material_override is ShaderMaterial: _flags.append(flag.material_override as ShaderMaterial)

## The arcade's lanterns: the kit hangs them lit in the Cabildo's detail; their glass (the atlas's glowing use) is taken
## out here into a mesh of its own, with an unlit twin (the same glass, solid and smoky), so that they stay dark until
## Lechuza mends their fuses.
func _split_lanterns(cabildo: Node3D) -> void:
	var detail := cabildo.get_node_or_null("Detail") as MeshInstance3D
	if detail == null: return
	var mesh := detail.mesh as ArrayMesh
	# (the atlas's surface: the detail mesh also has the weathering's, plaza_grime.gdshader)
	var si := 0
	for i: int in range(mesh.get_surface_count()):
		if mesh.surface_get_name(i) == "pdetail": si = i
	var arrays: Array = mesh.surface_get_arrays(si)
	var material := mesh.surface_get_material(si)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var glow := float(PlazaKit.DETAIL_MODES[PlazaKit.GLOW])
	var keep := PackedInt32Array()
	var glass := PackedInt32Array()
	for t: int in range(0, idx.size(), 3):
		for v: int in range(3):
			if absf(uv2[idx[t]].x - glow) < 0.1: glass.append(idx[t + v])
			else: keep.append(idx[t + v])
	if glass.is_empty(): return
	arrays[Mesh.ARRAY_INDEX] = keep
	var rest := _surface(arrays, material)
	rest.surface_set_name(0, "pdetail")
	for i: int in range(mesh.get_surface_count()):
		if i == si: continue
		rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		rest.surface_set_material(rest.get_surface_count() - 1, mesh.surface_get_material(i))
		rest.surface_set_name(rest.get_surface_count() - 1, mesh.surface_get_name(i))
	detail.mesh = rest
	arrays[Mesh.ARRAY_INDEX] = glass
	_lanterns_lit = _lantern_node(cabildo, "ArcadeLanterns", _surface(arrays, material))
	var dark_uv2 := uv2.duplicate()
	var cols: PackedColorArray = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	for i: int in glass:
		dark_uv2[i] = Vector2(float(PlazaKit.DETAIL_MODES[PlazaKit.SOLID]), dark_uv2[i].y)
		cols[i] = Color(0.2, 0.19, 0.17, cols[i].a)
	arrays[Mesh.ARRAY_TEX_UV2] = dark_uv2
	arrays[Mesh.ARRAY_COLOR] = cols
	_lanterns_dark = _lantern_node(cabildo, "ArcadeLanternsDark", _surface(arrays, material))

static func _surface(arrays: Array, material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

static func _lantern_node(parent: Node3D, node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## The Palacio Municipal on the corner of Bolívar and the Avenida de Mayo (the kit has no Palacio of its own): the
## kit's avenue fronts round its block, the domed turret on the corner over the avenue, the café below it (_cafe_front).
func _municipal() -> void:
	var r := _r("municipal", [0.0, 36.0, 28.0, 72.0])
	var d := 16.0
	var x0 := PlazaGround.WEST_STREETS[1] + 8.0
	var front := pk.avenida_de_mayo(Rect2(r.end.x - d, r.position.y, d, r.size.y), PlazaKit.EAST, true, 1903)
	front.name = "Municipal"
	_fade(front)
	var avenue := pk.avenida_de_mayo(Rect2(x0, r.end.y - d, r.end.x - d - x0, d), PlazaKit.SOUTH, false, 1904)
	avenue.name = "MunicipalAvenida"
	_fade(avenue)
	var north := pk.avenida_de_mayo(Rect2(x0, r.position.y, r.end.x - d - x0, d), PlazaKit.NORTH, false, 1905)
	north.name = "MunicipalRivadavia"

## The city round the square from the kit's avenue fronts, a run along each street edge: the rows across Rivadavia
## and Yrigoyen and at the square's corners (the rules' own buildings: they fade like the landmarks), the avenue's
## south side up to the Cabildo, and beyond the map, west, both sides of Rivadavia, the avenue and Yrigoyen.
func _city() -> void:
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	var riv := _pair2("rivadavia", Vector2(22.0, 36.0))
	var yri := _pair2("yrigoyen", Vector2(132.0, 146.0))
	var avm := _pair2("avMayo", Vector2(72.0, 100.0))
	var bol := _pair2("bolivar", Vector2(28.0, 42.0))
	var sm := _pair2("sanMartin", Vector2(96.0, 104.0))
	var rq := _pair2("reconquista", Vector2(180.0, 188.0))
	var bal := _pair2("balcarce", Vector2(242.0, 256.0))
	var cat := _r("catedral", [44.0, -22.0, 96.0, 22.0])
	var cab := _r("cabildo", [4.0, 100.0, 28.0, 126.0])
	var d := 16.0
	var x0 := PlazaGround.WEST_STREETS[1] + 8.0
	# [name, footprint, facing, a domed corner, fades]
	var runs: Array = [
		["NorthW", Rect2(x0, riv.x - d, cat.position.x - x0, d), PlazaKit.SOUTH, true, true],
		["NorthMid", Rect2(sm.y, riv.x - d, rq.x - sm.y, d), PlazaKit.SOUTH, true, true],
		["NorthE", Rect2(bal.y, riv.x - d, W + 4.0 - bal.y, d), PlazaKit.SOUTH, false, true],
		["SouthE", Rect2(bal.y, yri.y, W + 4.0 - bal.y, d), PlazaKit.NORTH, false, true],
	]
	# (the Cabildo stands free: Avenida de Mayo on its north, its patio behind it, Hipólito Yrigoyen on its south: the
	# corner block beyond Yrigoyen is the city's, plaza_city.gd; _cabildo_surroundings)
	for span: Vector2 in PlazaGround.WEST_SPANS:
		var wide := span.y - span.x
		runs.append(["Rivadavia", Rect2(span.x, riv.x - d, wide, d), PlazaKit.SOUTH, true, false])
		runs.append(["Rivadavia", Rect2(span.x, riv.y, wide, d), PlazaKit.NORTH, true, false])
		runs.append(["AvenidaDeMayo", Rect2(span.x, avm.x - d, wide, d), PlazaKit.SOUTH, true, false])
		runs.append(["AvenidaDeMayo", Rect2(span.x, avm.y, wide, d), PlazaKit.NORTH, true, false])
		runs.append(["Yrigoyen", Rect2(span.x, yri.x - d, wide, d), PlazaKit.SOUTH, true, false])
		runs.append(["Yrigoyen", Rect2(span.x, yri.y, wide, d), PlazaKit.NORTH, true, false])
	var seed_value := 1880
	var far: Array[Node3D] = []
	for run: Array in runs:
		var node := pk.avenida_de_mayo(run[1], run[2], bool(run[3]), seed_value)
		node.name = str(run[0])
		if bool(run[4]): _fade(node)
		elif node.position.x < -10.0 or run[1].position.x < -10.0: far.append(node)
		seed_value += 7
	# the rows beyond the map never fade: folded with the rest of the kit's city (_fold_city)
	_far_kit.append_array(far)

## Buenos Aires beyond the square's rows (plaza_city.gd): the blocks behind them and beyond the streets that leave the
## map, the Diagonales, the Avenida de Mayo on west past the Barolo to the Congreso, the port behind the Casa Rosada;
## and, from the kit, the avenue's plane trees and lamps, the cars parked under the snow out there, trams and
## colectivos stopped on the streets beyond the map.
func _surroundings() -> void:
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	city = PlazaCity.new(self, pw, W, H, _macro)
	city.build()
	_far_kit.append_array(PlazaCity.furnish(pk, pw, W, H, _fleet))
	# a second kiosk on the avenue's pavement, west of Perú
	var avm := _pair2("avMayo", Vector2(72.0, 100.0))
	var k2 := pk.kiosk(Vector3(-26.0, 0.0, avm.y - 2.6), PlazaKit.NORTH)
	k2.name = "KioskAvenida"
	_kiosks.append(k2)

## The square's furniture from the kit (drawn as multimeshes when it finishes): the eight palms round the Pirámide,
## the cast-iron lamps where the layout has them (their lights: _kit_lights), the benches by the walks; and the city's
## lamps beyond the map (one globe each, double lanterns down the avenue: they glow and pool, no lights of their own).
func _furniture() -> void:
	var i := 0
	for spot: Array in pw.get("palms", []):
		pk.palm(Vector3(float(spot[0]), 0.0, float(spot[1])), 1.0 + 0.07 * sin(float(i) * 2.3))
		i += 1
	for spot: Array in pw.get("lamps", []):
		pk.lamp_post(Vector3(float(spot[0]), 0.0, float(spot[1])), 4)
	for b: Array in pw.get("benches", []):
		pk.bench(Vector3(float(b[0]), 0.0, float(b[1])), deg_to_rad(float(b[2])))
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	var riv := _pair2("rivadavia", Vector2(22.0, 36.0))
	var yri := _pair2("yrigoyen", Vector2(132.0, 146.0))
	var x := -140.0
	while x < W + 140.0:
		if x < -2.0 or x > W + 2.0:
			pk.lamp_post(Vector3(x, 0, riv.x + 1.2), 0)
			pk.lamp_post(Vector3(x + 9.0, 0, yri.y - 1.2), 0)
		x += 32.0
	var z := -80.0
	while z < H + 80.0:
		pk.lamp_post(Vector3(W + 7.0, 0, z), 0)
		pk.lamp_post(Vector3(W + 19.0, 0, z + 10.0), 0)
		if z < 0.0 or z > H:
			for sx: float in [_pair2("balcarce", Vector2(242, 256)).x + 1.0, _pair2("sanMartin", Vector2(96, 104)).x + 0.8, _pair2("reconquista", Vector2(180, 188)).y - 0.8]:
				if (z < 0.0 and sx < 200.0) or z > H: pk.lamp_post(Vector3(sx, 0, z), 0)
		z += 32.0
	var avm := _pair2("avMayo", Vector2(72.0, 100.0))
	x = -16.0
	while x > -150.0:
		for zz: float in [avm.x + 3.2, avm.y - 3.2]:
			pk.lamp_post(Vector3(x, 0, zz), 2)
		x -= 24.0

## The traffic of the time, unbranded: the cars parked at the kerbs where the layout has them (the rules' "car"
## obstacles), snowed in (their near copies, "<model>_near", where the build has them: their insides through their
## glass, their detail kept for the cameras that come close); the colectivo stranded on Yrigoyen (the rules' vehicle:
## lit, its door open at the kerb); beyond the map, a second tram on Rivadavia's other track and a colectivo coming up
## the avenue. The cars and the
## colectivos are the friends' models and those made on their generator (PlazaCity.period_car); where a model's file
## is not in the build, the kit's own car or colectivo stands in.
func _traffic() -> void:
	# the cars at the kerbs: the big sedans, coupés and small saloons of the forties and fifties, the taxis black and
	# yellow, the friends' small saloon and pickup among them (their front is -z: turned half round), the soda truck
	var i := 0
	for c: Array in pw.get("parked", []):
		var at := Vector3(float(c[0]), 0.0, float(c[1]))
		var yaw := deg_to_rad(float(c[2]))
		var kind := str(c[3])
		var model := PlazaCity.period_car(kind, i)
		if kind == "truck": pk.truck(at, yaw)
		elif PlazaCity.has_vehicle(model):
			var near := model + "_near" if PlazaCity.has_vehicle(model + "_near") else model
			park(near, at, yaw + PI, PlazaCity.period_paint(model, i), 0.0)
		else: pk.car(at, yaw, kind)
		i += 1
	# the rules' colectivo stranded on Yrigoyen: the Línea 60, lit, its door open at the kerb
	var r := _r("colectivo", [199.7, 137.08, 207.3, 139.32])
	var at_bus := Vector3(r.get_center().x, 0.0, r.get_center().y)
	if PlazaCity.has_vehicle("colectivo60_open"):
		bus = _single("colectivo60_open", at_bus, -PI * 0.5, Color(0, 0, 0), 1.0, 0.14)
		bus.name = "Colectivo"
	else:
		bus = _fade(pk.colectivo(at_bus, -PI * 0.5, Color(0, 0, 0, 0), Color(0, 0, 0, 0), true, true, false))
	var tracks: Array = pw.get("tracksZ", [27.5, 30.5])
	var other := pk.tram(Vector3(-46.0, 0.0, float(tracks[1])), -PI * 0.5, true, WIRE_Y)
	other.name = "TramWest"
	# another 60 coming up the avenue, lit
	var avm := _pair2("avmRoad", Vector2(77.0, 95.0))
	if PlazaCity.has_vehicle("colectivo60_far"): park("colectivo60_far", Vector3(-38.0, 0.0, avm.y - 2.6), PI * 0.5, Color(0, 0, 0), 1.0)
	else: pk.colectivo(Vector3(-34.0, 0.0, avm.y - 2.6), PI * 0.5, PlazaKit.hexc("2c4a6e"), PlazaKit.hexc("e2d6b8"), true, false, false).name = "ColectivoAvenida"

## One of the friends' vehicles out in the city (drawn with its kind in a multimesh: _build_fleet): its model, where it
## stands, which way its front faces (yaw about y, the model's own front), its paint, whether it is in service (lit).
func park(model: String, at: Vector3, yaw: float, paint: Color, service: float) -> void:
	if not _fleet.has(model): _fleet[model] = []
	(_fleet[model] as Array).append([Transform3D(Basis(UP, yaw), at), paint, service])

## A vehicle's materials, a surface each: its body (plaza_vehicle.gdshader: the lettering, the fileteado and the
## plates in the second atlas) and, on a near copy of a car (a second surface), its glass (plaza_vehicle_glass.gdshader).
static func vehicle_materials(mesh: Mesh, per_instance: bool, cap: float, macro: Texture2D) -> Array[ShaderMaterial]:
	var m := ShaderMaterial.new()
	m.shader = VehicleShader
	m.set_shader_parameter("lettering", load(VEHICLES + "colectivo60_lettering.png"))
	m.set_shader_parameter("filete", load("res://assets/tex/plaza/plaza_b.png"))
	m.set_shader_parameter("macro_tex", macro)
	m.set_shader_parameter("per_instance", per_instance)
	m.set_shader_parameter("cap_depth", cap)
	var out: Array[ShaderMaterial] = [m]
	if mesh != null and mesh.get_surface_count() > 1:
		var g := ShaderMaterial.new()
		g.shader = VehicleGlassShader
		g.set_shader_parameter("macro_tex", macro)
		g.set_shader_parameter("per_instance", per_instance)
		out.append(g)
	return out

## A vehicle of its own (the rules' colectivo): a mesh and a material of its own, fading like the buildings when
## somebody stands behind it.
func _single(model: String, at: Vector3, yaw: float, paint: Color, service: float, cap: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = load(VEHICLES + model + ".res")
	# (its body, and its glass when it has its own: the lit inside shows through it)
	var mats := vehicle_materials(node.mesh, false, cap, _macro)
	_vehicle_mats.append_array(mats)
	for i: int in range(node.mesh.get_surface_count()):
		var m: ShaderMaterial = mats[mini(i, mats.size() - 1)]
		m.set_shader_parameter("paint", paint)
		m.set_shader_parameter("in_service", service)
		node.set_surface_override_material(i, m)
	node.transform = Transform3D(Basis(UP, yaw), at)
	add_child(node)
	faders.append({"node": node, "aabb": node.transform * node.get_aabb(), "mats": mats, "alpha": 1.0, "want": 1.0})
	return node

## The fleet out in the city, a multimesh a district for each model (each instance its paint and whether it is lit).
func _build_fleet() -> void:
	var caps := {"colectivo60_far": 0.14, "microcar": 0.1, "work_pickup": 0.1, "sedan49": 0.07, "taxi49": 0.07, "saloon53": 0.07,
		"coupe48": 0.07, "pickup51": 0.07, "van51": 0.07}
	for model: String in _fleet:
		var mesh: Mesh = load(VEHICLES + model + ".res")
		var mats := vehicle_materials(mesh, true, float(caps.get(model.trim_suffix("_near"), 0.1)), _macro)
		_vehicle_mats.append_array(mats)
		var mat: ShaderMaterial = mats[0]
		# (a near copy's glass on its own surface: its materials set on the mesh, a multimesh takes no material a
		# surface)
		if mats.size() > 1:
			for s: int in range(mesh.get_surface_count()): mesh.surface_set_material(s, mats[mini(s, mats.size() - 1)])
		var groups: Dictionary = {}
		for item: Array in _fleet[model]:
			var xf: Transform3D = item[0]
			var key := Vector2i(int(floor(xf.origin.x / 100.0)), int(floor(xf.origin.z / 100.0)))
			if not groups.has(key): groups[key] = []
			(groups[key] as Array).append(item)
		for key: Vector2i in groups:
			var list: Array = groups[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			# (white instance colours: the GL Compatibility renderer multiplies the vertex colours, which carry the
			# models' materials, by the instance colour, black when there is none)
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = list.size()
			for j: int in range(list.size()):
				var item: Array = list[j]
				var c: Color = item[1]
				mm.set_instance_transform(j, item[0])
				mm.set_instance_color(j, Color.WHITE)
				mm.set_instance_custom_data(j, Color(c.r, c.g, c.b, float(item[2])))
			var node := MultiMeshInstance3D.new()
			node.name = "Fleet_%s_%d_%d" % [model, key.x, key.y]
			node.multimesh = mm
			if mats.size() == 1: node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)

## The small things that make it Buenos Aires (plaza_details.gd): the corner posts with the streets' names, the
## kiosks dressed, the café tables on the avenue, the policeman's podium, the Línea A's plates, the works hoarding
## across Yrigoyen beyond Bolívar and the wall of the Cabildo's patio.
func _dress_city() -> void:
	details = PlazaDetails.new(self, city, _macro)
	var corners: Array = [
		[Vector2(28.7, 35.3), [["st_rivadavia", Vector2.RIGHT], ["st_bolivar", Vector2.DOWN]]],
		[Vector2(28.7, 72.7), [["st_avmayo", Vector2.RIGHT], ["st_bolivar", Vector2.DOWN]]],
		[Vector2(28.7, 99.3), [["st_bolivar", Vector2.DOWN], ["st_avmayo", Vector2.RIGHT]]],
		[Vector2(95.6, 22.4), [["st_rivadavia", Vector2.RIGHT], ["st_sanmartin", Vector2.DOWN]]],
		[Vector2(179.6, 22.4), [["st_rivadavia", Vector2.RIGHT], ["st_reconquista", Vector2.DOWN]]],
		[Vector2(256.4, 21.6), [["st_25mayo", Vector2.DOWN], ["st_rivadavia", Vector2.RIGHT]]],
		[Vector2(255.4, 35.4), [["st_balcarce", Vector2.DOWN], ["st_rivadavia", Vector2.RIGHT]]],
		[Vector2(119.6, 145.6), [["st_defensa", Vector2.DOWN], ["st_yrigoyen", Vector2.RIGHT]]],
		[Vector2(242.4, 145.6), [["st_balcarce", Vector2.DOWN], ["st_yrigoyen", Vector2.RIGHT]]],
		[Vector2(-3.6, 72.6), [["st_avmayo", Vector2.RIGHT], ["st_peru", Vector2.DOWN]]],
		[Vector2(-3.2, 126.9), [["st_yrigoyen", Vector2.RIGHT], ["st_peru", Vector2.DOWN]]],
	]
	var dl := PlazaGround.diagonal_lines()
	for k: int in range(dl.size()):
		var o: Vector2 = dl[k][0]
		var dir: Vector2 = dl[k][1]
		var hw: float = dl[k][2]
		var at := o + dir * 24.0 + Vector2(-dir.y, dir.x) * (hw + 1.0)
		corners.append([at, [["st_diagnorte" if k == 0 else "st_diagsur", dir]]])
	for c: Array in corners: details.corner_post(c[0], c[1])
	for kn: Node3D in _kiosks:
		var dressing := details.kiosk_dressing(kn)
		if dressing != null and kn.name != "KioskAvenida": _make_fader(dressing)
	var avm := _pair2("avMayo", Vector2(72.0, 100.0))
	for x: float in [-40.0, -43.2, -46.4, -49.6, -62.0, -65.2]:
		details.cafe_table(Vector2(x, avm.y - 1.5), 0.0)
	for x: float in [-52.0, -55.2, -58.4]:
		details.cafe_table(Vector2(x, avm.x + 1.5), 0.0)
	details.podium(Vector2((PlazaGround.WEST_STREETS[1] + PlazaGround.WEST_STREETS[1] + 8.0) * 0.5, (_pair2("avmRoad", Vector2(77.0, 95.0)).x + _pair2("avmRoad", Vector2(77.0, 95.0)).y) * 0.5))
	for st: Array in _stairs: details.subte_disc(st[0], float(st[1]))
	# Hipólito Yrigoyen beyond Bolívar shut for works (the rules' corner block south-w stands across it): the hoarding
	# along Bolívar's kerb from the Cabildo's corner to the far pavement
	var cab := _r("cabildo", [4.0, 100.0, 28.0, 126.0])
	var yri := _pair2("yrigoyen", Vector2(132.0, 146.0))
	details.hoarding(Vector2(cab.end.x - 0.15, cab.end.y + 0.4), Vector2(cab.end.x - 0.15, yri.y), 2.4, Vector2(cab.end.x + 10.0, (cab.end.y + yri.y) * 0.5))
	# the wall of the Cabildo's patio, behind it beyond the map's edge, its gate
	details.patio_wall([Vector2(-1.0, cab.position.y + 0.4), Vector2(-1.0, cab.end.y - 0.4)], 3.2, Vector2(2.0, (cab.position.y + cab.end.y) * 0.5), Vector2(10.5, 14.0))
	details.commit()

## The café on the avenue's corner, in the Municipal's corner building: its lit front, its door and its sign on the
## corner lot's side (the kit's run leaves that wall plain), under the awning that is one of the cloths.
func _cafe_front() -> void:
	var r := _r("municipal", [0.0, 36.0, 28.0, 72.0])
	var a := _pair2("awning", Vector2(22.0, 73.6))
	var x0 := r.end.x - 16.0
	var f = PlazaKit.face(Vector3(x0, 0.0, r.end.y), Vector3.RIGHT, 16.0)
	var mid := a.x - x0
	pk.begin(Transform3D.IDENTITY)
	var k := Kit.new()
	var kd := Kit.new()
	var stone := PlazaKit.hexc("c9bba0")
	pk.fbox(k, f, "rustic", 8.0, 0.25, 0.04, 16.0, 0.5, 0.08, stone * 0.8)
	pk.fbox(k, f, "render", mid, 4.35, 0.06, 11.6, 1.0, 0.12, stone)
	pk.fquad(kd, f, PlazaKit.SOLID, mid - 1.8, mid + 1.8, 3.92, 4.82, 0.13, PlazaKit.uv("sign_cafe"))
	for x: float in [mid - 3.6, mid, mid + 3.6]:
		pk.fquad(kd, f, PlazaKit.LIT, x - 1.5, x + 1.5, 0.5, 3.45, 0.03, PlazaKit.uv("cafe_lit"), pk.warm())
		pk.spill_at(f.at(x, 0.0, 0.0), f.n, 3.0, 3.2, 0.6)
	pk.fquad(kd, f, PlazaKit.LIT, mid - 6.3, mid - 5.2, 0.0, 3.0, 0.03, PlazaKit.uv("door_shop_lit"), PlazaKit.WARM * 0.8)
	pk.piece("CafeFront", Transform3D.IDENTITY, k, kd, null, false)
	pk.end()

# ---------------------------------------------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------------------------------------------
## The kit's halos and their glow, committed when it finished (its newest children): kept, with their colours.
func _kit_batches(before: int) -> void:
	for i: int in range(before, get_child_count()):
		var n := get_child(i)
		if not n is MultiMeshInstance3D: continue
		if str(n.name).begins_with("Halos"): _halo_mm = (n as MultiMeshInstance3D).multimesh
		elif str(n.name).begins_with("FogGlow"): _fog_mm = (n as MultiMeshInstance3D).multimesh
	if _halo_mm != null:
		for i: int in range(_halo_mm.instance_count): _halo_base.append(_halo_mm.get_instance_color(i))
	if _fog_mm != null:
		for i: int in range(_fog_mm.instance_count): _fog_base.append(_fog_mm.get_instance_color(i))

## Everything the kit made out in the city (the rows beyond the map, the parked cars and the far traffic, the plane
## trees down the avenues, the city's lamps) folded into two meshes a district ("CityKit_x_z"), culled with it; only
## the districts over the map cast shadows (the moon's shadows reach no further).
func _fold_city(before: int) -> void:
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	# (the kit's batches found first: freeing the pieces before them moves the children's indices)
	var found: Array[MultiMeshInstance3D] = []
	for i: int in range(before, get_child_count()):
		var n := get_child(i)
		if n is MultiMeshInstance3D and (str(n.name).begins_with("PlaneTrees") or str(n.name) in ["LampPosts0", "LampPosts2"]):
			found.append(n as MultiMeshInstance3D)
	var parts := PlazaCity.parts_of(_far_kit)
	_far_kit.clear()
	for node: MultiMeshInstance3D in found: parts.append_array(PlazaCity.parts_of_multimesh(node))
	PlazaCity.fold(parts, self, "CityKit", Rect2(-30.0, -40.0, W + 60.0, H + 80.0))

## Real lights where the kit asks for them (pk.lights) and the game needs them: each lamp of the square (they stutter
## now and then, their halos with them), the arcade's five lanterns (out until mended), the lit passages at the foot
## of the subte's stairs, the kiosk's bulb, the lamp in the Casa Rosada's arch. The city's own lamps only glow, pool on
## the snow and haze the air.
func _kit_lights() -> void:
	var arcade := _r("arcade", [24.6, 100.0, 28.0, 126.0]).grow(0.6)
	var square: Array[Vector2] = []
	for spot: Array in pw.get("lamps", []): square.append(Vector2(float(spot[0]), float(spot[1])))
	for entry: Array in pk.lights:
		var at: Vector3 = entry[0]
		var col: Color = entry[1]
		var strength: float = float(entry[2])
		var reach: float = float(entry[3])
		var p := Vector2(at.x, at.z)
		var on_square := false
		for s: Vector2 in square: on_square = on_square or s.distance_to(p) < 0.5
		var lamp: Dictionary
		if on_square:
			lamp = _light(at, col, 5.6, 17.0)
			lamp["steady"] = false
			lamp["seed"] = float(lamps.size()) * 0.618
			lamp["halos"] = _instances(_halo_mm, at, 1.4)
			lamp["fogs"] = _instances(_fog_mm, at, 1.4)
		elif arcade.has_point(p) and at.y > 2.0:
			lamp = _light(at, col, 2.2, 7.5)
			lamp["arcade"] = true
			lamp["halos"] = _instances(_halo_mm, at, 0.6)
			lamp["fogs"] = _instances(_fog_mm, at, 0.6)
		elif strength < 0.95:
			_light(at, col, 4.2 * strength, reach * 1.3)

## A light of the square's (no shadow), in the lamp list.
func _light(at: Vector3, col: Color, energy: float, reach: float) -> Dictionary:
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % lamps.size()
	light.position = at
	light.light_color = col
	light.light_energy = energy
	light.light_specular = 0.8
	light.omni_range = reach
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	add_child(light)
	var entry := {"light": light, "halo": null, "at": at, "color": col, "energy": energy, "powered": false, "streak": 1.0, "steady": true}
	lamps.append(entry)
	return entry

## The instances of a multimesh within `radius` (across) and a metre (up or down) of a point.
static func _instances(mm: MultiMesh, at: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	if mm == null: return out
	for i: int in range(mm.instance_count):
		var o := mm.get_instance_transform(i).origin
		if Vector2(o.x - at.x, o.z - at.z).length() < radius and absf(o.y - at.y) < 1.0: out.append(i)
	return out

## The arcade's darkness while its lanterns are out (a cold veil over its floor), and the fuse box on the house's wall
## inside it where Lechuza works (the rules' passage "cabildo-lights"). The lanterns are the kit's (_split_lanterns).
func _cabildo_lights() -> void:
	var arcade := _r("arcade", [24.6, 100.0, 28.0, 126.0])
	var k := Kit.new()
	var passage: Dictionary = sim.passage_by_id("cabildo-lights")
	if not passage.is_empty():
		var pr: Rect2 = sim.rect_of(passage)
		var c := pr.get_center() / 32.0
		k.box("steel", Vector3(arcade.position.x + 0.12, 1.5, c.y), Vector3(0.2, 0.7, 0.5), Color(0.3, 0.33, 0.3), Color(0.38, 0.42, 0.38))
		k.box("steel", Vector3(arcade.position.x + 0.24, 1.5, c.y), Vector3(0.04, 0.5, 0.3), Color(0.5, 0.52, 0.46), Color(0.6, 0.62, 0.55))
	commit(k, self, "FuseBox", false)
	var shade := Kit.new()
	var outer := arcade.grow(0.6)
	var inner := arcade.grow(-0.6)
	var y := 0.12
	var o4 := [Vector3(outer.position.x, y, outer.end.y), Vector3(outer.end.x, y, outer.end.y), Vector3(outer.end.x, y, outer.position.y), Vector3(outer.position.x, y, outer.position.y)]
	var i4 := [Vector3(inner.position.x, y, inner.end.y), Vector3(inner.end.x, y, inner.end.y), Vector3(inner.end.x, y, inner.position.y), Vector3(inner.position.x, y, inner.position.y)]
	var on := Color(1, 1, 1, 1)
	var off := Color(1, 1, 1, 0)
	shade.quad4("shade", i4[0], i4[1], i4[2], i4[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, on, on, on, on)
	for i: int in range(4):
		var j := (i + 1) % 4
		shade.quad4("shade", o4[i], o4[j], i4[j], i4[i], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, off, off, on, on)
	var material := ShaderMaterial.new()
	material.shader = ShadeShader
	material.set_shader_parameter("amount", 1.0)
	material.set_shader_parameter("strength", 0.78)
	materials["shade"] = material
	_arcade_shade = _commit(shade, self, "ArcadeDark", false)
	if _arcade_shade != null:
		_arcade_shade.material_override = material
		_arcade_shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------------------------------------------------------
# The tram, the gate, the cart, the awning, the cloths
# ---------------------------------------------------------------------------------------------------------------
## The tram (the rules' vehicle "tram"): the kit's car, lit, fitted to the rules' 14 m, built by a kit of its own so
## its light on the snow and its headlamp's halo go with it along Rivadavia; a lamp inside for whoever is aboard.
func _build_plaza_tram() -> void:
	var spec: Dictionary = sim.vehicle_spec("tram")
	if spec.is_empty(): return
	tram = node("Tram")
	tram_kit = PlazaKit.new(tram, KIT_SNOW, 1.0, 214)
	var car := tram_kit.tram(Vector3.ZERO, PI * 0.5, true, WIRE_Y)
	car.name = "Car"
	car.scale = Vector3(float(spec.h) / 32.0 / KIT_TRAM.x, 1.0, float(spec.w) / 32.0 / KIT_TRAM.y)
	tram_kit.finish()
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.2, 0)
	light.light_color = LIT
	light.light_energy = 1.4
	light.omni_range = 7.0
	tram.add_child(light)
	_sync_tram()

## Rivadavia's tram line: the two tracks laid in the setts, poles along the square's side of the street with span
## wires out over both tracks and the contact wires on them.
func _tram_line() -> void:
	var tracks: Array = pw.get("tracksZ", [27.5, 30.5])
	var riv := PlazaGround.pair_of(pw, "rivadavia", Vector2(22.0, 36.0))
	var k := Kit.new()
	var x := -150.0
	while x < float(sim.data.width) / 32.0 + 150.0:
		for z: Variant in tracks:
			for dz: float in [-0.72, 0.72]:
				k.box("steel", Vector3(x + 30.0, 0.015, float(z) + dz), Vector3(60.0, 0.03, 0.07), IRON, Color(0.42, 0.42, 0.42))
		x += 60.0
	commit(k, self, "TramRails", false)
	var poles := Kit.new()
	var wires := Kit.new()
	var px: Array[float] = []
	x = -140.0
	while x < float(sim.data.width) / 32.0 + 140.0:
		px.append(x)
		x += 32.0
	for p: float in px:
		var foot := Vector3(p, 0, riv.y - 0.6)
		poles.lathe("steel", foot, PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.15, 0.5), Vector2(0.11, 0.62), Vector2(0.09, 7.0), Vector2(0.05, 7.2)]), 8, IRON * 0.7, IRON * 1.3)
		_props.wire(wires, foot + UP * 6.6, Vector3(p, 6.4, riv.x + 0.3), 0.3, 0.01, Color(0.14, 0.14, 0.15), 6)
		for z: Variant in tracks:
			_props.wire(wires, Vector3(p, 6.45, float(z)), Vector3(p, WIRE_Y + 0.02, float(z)), 0.0, 0.01, Color(0.14, 0.14, 0.15), 2)
	for z: Variant in tracks:
		for i: int in range(px.size() - 1):
			_props.wire(wires, Vector3(px[i], WIRE_Y, float(z)), Vector3(px[i + 1], WIRE_Y, float(z)), 0.14, 0.012, Color(0.14, 0.14, 0.15), 8)
	commit(poles, self, "TramPoles", true)
	commit(wires, self, "TramWires", false)

## The service gate across the head of the service stair: an iron grille hinged at its north post, swung open when
## Lechuza unlocks it (the rules' passage "subte-gate").
func _service_gate() -> void:
	var passage: Dictionary = sim.passage_by_id("subte-gate")
	if passage.is_empty(): return
	var pr: Rect2 = sim.rect_of(passage)
	var r := Rect2(pr.position / 32.0, pr.size / 32.0)
	var x := r.get_center().x
	var post := Kit.new()
	var dark := Color(0.12, 0.14, 0.13)
	for z: float in [r.position.y, r.end.y]:
		post.box("steel", Vector3(x, 0.85, z), Vector3(0.14, 1.7, 0.14), dark, dark * 1.5)
		post.lathe("steel", Vector3(x, 1.7, z), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.0, 0.18)]), 6, dark, dark)
	commit(post, self, "GatePosts", true)
	_gate_leaf = node("ServiceGate", Vector3(x, 0, r.position.y + 0.08))
	var leaf := Kit.new()
	var width := r.size.y - 0.16
	for y: float in [0.15, 0.85, 1.5]:
		leaf.box("steel", Vector3(0, y, width * 0.5), Vector3(0.05, 0.05, width), dark, dark * 1.6)
	var bars := int(width / 0.12)
	for i: int in range(bars + 1):
		var z := width * float(i) / float(bars)
		leaf.box("steel", Vector3(0, 0.82, z), Vector3(0.025, 1.5, 0.025), dark, dark * 1.6)
	commit(leaf, _gate_leaf, "Leaf", true)

## A vendor's cart at the kerb of Yrigoyen, its canvas cover over it (one of the cloths: gone once taken).
func _cart(r: Rect2) -> void:
	var k := Kit.new()
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	k.push_tint(Houses.hexc("7a3a2a"))
	k.box("planks", c + UP * 0.85, Vector3(r.size.x - 0.8, 0.7, r.size.y - 0.4), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	for s: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0.4, 0.55, s * (r.size.y * 0.5 - 0.1))))
		k.lathe("planks", Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.55, 0.1), Vector2(0.0, 0.1)]), 12, Props.WOOD_GREY, Props.WOOD_GREY)
		k.pop()
	k.beam("planks", c + Vector3(-r.size.x * 0.5 + 0.4, 0.8, -0.3), c + Vector3(-r.size.x * 0.5 - 0.6, 0.4, -0.3), 0.06, 0.06, Props.WOOD_GREY, Props.WOOD_GREY)
	k.beam("planks", c + Vector3(-r.size.x * 0.5 + 0.4, 0.8, 0.3), c + Vector3(-r.size.x * 0.5 - 0.6, 0.4, 0.3), 0.06, 0.06, Props.WOOD_GREY, Props.WOOD_GREY)
	commit(k, self, "Cart", true, true)
	_cloth("cart-cover", c + UP * 1.2, Vector2(r.size.x - 0.6, r.size.y - 0.2), Color(0.5, 0.46, 0.36), false)

## The café's awning on the avenue's corner: its iron frame out from the Municipal's corner over the café's windows,
## its striped cloth on it (one of the cloths: gone once taken, the bare frame left).
func _cafe_awning(pos: Vector2) -> void:
	var k := Kit.new()
	var wall_z := _r("municipal", [0.0, 36.0, 28.0, 72.0]).end.y
	var x0 := pos.x - 3.0
	var x1 := pos.x + 3.0
	var depth := 2.4
	for x: float in [x0, x1]:
		k.beam("steel", Vector3(x, 3.8, wall_z), Vector3(x, 3.3, wall_z + depth), 0.04, 0.04, IRON, IRON)
	k.beam("steel", Vector3(x0, 3.3, wall_z + depth), Vector3(x1, 3.3, wall_z + depth), 0.04, 0.04, IRON, IRON)
	commit(k, self, "AwningFrame", true)
	var cloth := node("Cloth_awning")
	var kc := Kit.new()
	_awning_cloth(kc, Vector3(x0, 3.8, wall_z + 0.04), Vector3(x1, 3.8, wall_z + 0.04), depth)
	commit(kc, cloth, "Awning", true)
	cloths["awning"] = cloth

func _awning_cloth(k: Kit, a: Vector3, bb: Vector3, depth: float) -> void:
	var out := Vector3(0, -0.5, depth)
	k.quad_rect("facade_cut", a + out, bb + out, bb, a, Houses.uv("awning_green"), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.quad_rect("facade_cut", bb + out, a + out, a, bb, Houses.uv("awning_green"), Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.6))
	var drop := Vector3(0, -0.3, 0)
	k.quad_rect("facade_cut", bb + out + drop, a + out + drop, a + out, bb + out, Houses.uv_part("awning_green", 0.0, 1.0, 0.7, 1.0), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.quad_rect("facade_cut", a + out + drop, bb + out + drop, bb + out, a + out, Houses.uv_part("awning_green", 0.0, 1.0, 0.7, 1.0), Color(0.8, 0.8, 0.8), Color.WHITE)
	var n := (bb - a).cross(-out).normalized()
	if n.y < 0.0: n = -n
	Snow.slope(k, a + out * 0.95 + (bb - a).normalized() * 0.05, bb + out * 0.95 - (bb - a).normalized() * 0.05, a + Vector3(0, 0.025, 0) + (bb - a).normalized() * 0.05, bb + Vector3(0, 0.025, 0) - (bb - a).normalized() * 0.05, n, 0.08, 0.1, rng)

## The kiosk's tarpaulin, folded over the bundles of papers before its counter (one of the cloths: gone once taken).
func _kiosk_tarp(r: Rect2) -> void:
	_cloth("tarpaulin", Vector3(r.get_center().x, 0.0, r.end.y + 0.75), Vector2(1.6, 1.0), Color(0.42, 0.4, 0.3), true)

## A cloth on its frame or folded over something (canvas id): a node of its own, hidden once somebody takes it.
func _cloth(id: String, centre: Vector3, size: Vector2, tint: Color, folded: bool) -> void:
	var holder := node("Cloth_" + id)
	var k := Kit.new()
	if folded:
		# bundles of papers under it
		_props.crate(k, centre + Vector3(-0.35, 0.0, 0.0), Vector3(0.6, 0.45, 0.5), 0.2, 1, Color(0.7, 0.66, 0.58))
		_props.crate(k, centre + Vector3(0.35, 0.0, 0.05), Vector3(0.6, 0.38, 0.5), -0.1, 1, Color(0.7, 0.66, 0.58))
		_props.tarp(k, centre + UP * 0.5, size, 0.4, tint)
	else:
		_props.tarp(k, centre, size, 0.5, tint)
	commit(k, holder, "Cloth", true)
	cloths[id] = holder

## The cloths held up by the operatives who carry one (data canvases): a sheet over his head and shoulders.
func _build_held() -> void:
	var quad := Kit.new()
	_props.tarp(quad, Vector3.ZERO, Vector2(2.2, 1.6), 0.35, Color(0.5, 0.46, 0.36))
	var holder := Node3D.new()
	var m: MeshInstance3D = quad.commit(holder, materials, "Tmp", true)
	var mesh: ArrayMesh = m.mesh
	holder.free()
	for i: int in range(4):
		var held := MeshInstance3D.new()
		held.name = "HeldCloth%d" % i
		held.mesh = mesh
		held.visible = false
		held.set_meta("no_batch", true)
		add_child(held)
		_held.append(held)

# ---------------------------------------------------------------------------------------------------------------
# The snow that builds up: drifts, mounds
# ---------------------------------------------------------------------------------------------------------------
## Snow banked against the walls round the square, broken here and there, wherever a wall faces open ground on the
## map: soft-edged banks (plaza_drift.gdshader) whose toes fade into the snow on the ground, each vertex knowing the
## foot of its wall (UV2), so the banks swell out from the walls and up as the night's snow falls (_sync_snow sets
## their `grow`). (Raised by scaling they lay flat on the pavement early in the night, white sheets with ragged edges.)
func _build_drifts() -> void:
	_drift_material = ShaderMaterial.new()
	_drift_material.shader = DriftShader
	_drift_material.set_shader_parameter("snow_tex", load("res://assets/tex/snow/snow_a.png"))
	_drift_material.set_shader_parameter("snow_nrm", load("res://assets/tex/snow/snow_n.png"))
	_drift_material.set_shader_parameter("macro_tex", _macro)
	var W := float(sim.data.width) / 32.0
	var H := float(sim.data.height) / 32.0
	var rects: Array[Rect2] = []
	for o: Dictionary in sim.data.get("obstacles", []):
		if str(o.get("kind", "")) in ["building", "monument"]: rects.append(_m(o))
	# (and none under a roof: the portico, the arcade, the porch, the stairs: data snow.indoors)
	var indoors: Array[Rect2] = []
	for box: Array in (sim.data.get("snow", {}) as Dictionary).get("indoors", []):
		indoors.append(Rect2(float(box[0]) / 32.0, float(box[1]) / 32.0, float(box[2]) / 32.0, float(box[3]) / 32.0))
	var count := 0
	for r: Rect2 in rects:
		for side: Array in _sides(r):
			var a: Vector3 = side[0]
			var b: Vector3 = side[1]
			var length := a.distance_to(b)
			var right := (b - a) / length
			var out := right.cross(UP)
			var s := 0.0
			while s < length - 1.0:
				var e := minf(s + rng.randf_range(3.0, 9.0), length)
				var lay := rng.randf() < 0.75
				var h := rng.randf_range(0.35, 0.7)
				var d := rng.randf_range(1.0, 1.8)
				# only where this stretch of wall faces open ground on the map
				var probe := a + right * ((s + e) * 0.5) + out * 1.2
				var open := probe.x > 0.0 and probe.z > 0.0 and probe.x < W and probe.z < H
				for other: Rect2 in rects:
					if other.has_point(Vector2(probe.x, probe.z)): open = false
				for roof: Rect2 in indoors:
					if roof.grow(0.5).has_point(Vector2(probe.x, probe.z)): open = false
				if lay and open:
					_bank(a + right * s + out * 0.02, a + right * e + out * 0.02, out, h, d)
					count += 1
				s = e + rng.randf_range(0.5, 2.5)
			if count > 60:
				_commit_banks()
				count = 0
	_commit_banks()

## One bank along a wall from a to b (on the ground), `h` high against the wall and `d` out from it: a row across it
## every 0.4 m, its crest and its reach swelling and shrinking smoothly along it, both coming to nothing at its ends;
## its toe and its ends transparent (the vertex alpha).
func _bank(a: Vector3, b: Vector3, out: Vector3, h: float, d: float) -> void:
	var along := b - a
	var length := along.length()
	if length < 1.0: return
	# across: (out of d, up of h, opacity)
	var prof: Array[Vector3] = [Vector3(-0.03, 1.0, 1.0), Vector3(0.1, 0.97, 1.0), Vector3(0.26, 0.84, 1.0), Vector3(0.44, 0.58, 0.92),
		Vector3(0.62, 0.32, 0.66), Vector3(0.8, 0.12, 0.3), Vector3(1.0, 0.0, 0.0)]
	var cols := prof.size()
	var rows := maxi(4, int(length / 0.4) + 1)
	var phase := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	var base := _bank_v.size()
	var pts: Array[Vector3] = []
	for i: int in range(rows):
		var t := float(i) / float(rows - 1)
		var taper := smoothstep(0.0, 0.22, t) * smoothstep(1.0, 0.78, t)
		var x := t * length
		var crest := h * taper * (0.86 + 0.14 * sin(x * 0.9 + phase.x) + 0.07 * sin(x * 2.3 + phase.y))
		var reach := d * (0.3 + 0.7 * taper) * (0.92 + 0.1 * sin(x * 0.7 + phase.z))
		var fade := smoothstep(0.0, 0.45, taper)
		var foot := a + along * t
		for q: Vector3 in prof:
			var v := foot + out * (q.x * reach) + UP * (q.y * crest - (0.02 if q.y <= 0.0 else 0.0))
			pts.append(v)
			_bank_v.append(v)
			_bank_uv2.append(Vector2(foot.x, foot.z))
			_bank_c.append(Color(1, 1, 1, q.z * fade))
	for i: int in range(rows):
		for j: int in range(cols):
			var ta := pts[mini(i + 1, rows - 1) * cols + j] - pts[maxi(i - 1, 0) * cols + j]
			var to := pts[i * cols + mini(j + 1, cols - 1)] - pts[i * cols + maxi(j - 1, 0)]
			var n := ta.cross(to)
			if n.y < 0.0: n = -n
			_bank_n.append(n.normalized() if n.length_squared() > 1e-8 else UP)
	for i: int in range(rows - 1):
		for j: int in range(cols - 1):
			var c := base + i * cols + j
			_bank_i.append_array(PackedInt32Array([c, c + cols, c + 1, c + 1, c + cols, c + cols + 1]))

## The banks gathered so far, as one mesh of their own ("Drift").
func _commit_banks() -> void:
	if _bank_i.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _bank_v
	arrays[Mesh.ARRAY_NORMAL] = _bank_n
	arrays[Mesh.ARRAY_COLOR] = _bank_c
	arrays[Mesh.ARRAY_TEX_UV2] = _bank_uv2
	arrays[Mesh.ARRAY_INDEX] = _bank_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _drift_material)
	var node := MeshInstance3D.new()
	node.name = "Drift"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_drifts.append(node)
	_bank_v = PackedVector3Array()
	_bank_n = PackedVector3Array()
	_bank_c = PackedColorArray()
	_bank_uv2 = PackedVector2Array()
	_bank_i = PackedInt32Array()

## The four sides of a rectangle as walls: [a, b] on the ground, seen from outside (north, east, south, west).
static func _sides(r: Rect2) -> Array:
	return [
		[Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.position.y)],
		[Vector3(r.end.x, 0, r.end.y), Vector3(r.end.x, 0, r.position.y)],
		[Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y)],
		[Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y)],
	]

## The mounds the snow raises over whoever has fallen in it: one instance each, growing while they wait for help, a
## full mound once the snow has covered them (no figure shows under it).
func _build_mounds() -> void:
	var k := Kit.new()
	k.lathe("snowcap", Vector3.ZERO, PackedVector2Array([Vector2(1.0, -0.05), Vector2(0.95, 0.25), Vector2(0.78, 0.6), Vector2(0.5, 0.88), Vector2(0.2, 1.0), Vector2(0.0, 1.02)]), 12, Color(0.92, 0.92, 0.96), Color.WHITE)
	var holder := Node3D.new()
	var m: MeshInstance3D = k.commit(holder, materials, "Tmp", true)
	var mesh: ArrayMesh = m.mesh
	holder.free()
	_mounds = MultiMesh.new()
	_mounds.transform_format = MultiMesh.TRANSFORM_3D
	_mounds.mesh = mesh
	_mounds.instance_count = 40
	_mounds.visible_instance_count = 0
	var node3 := MultiMeshInstance3D.new()
	node3.name = "Mounds"
	node3.multimesh = _mounds
	node3.custom_aabb = AABB(Vector3(-20, -6, -20), Vector3(340, 10, 220))
	add_child(node3)

# ---------------------------------------------------------------------------------------------------------------
# The ground under the actors
# ---------------------------------------------------------------------------------------------------------------
## Height of the ground under an actor, as the kit built it: down the subte's stairs (24 steps from just inside the
## head, at most 0.29 m each, then the landing), up on the floor of the tram and the colectivo, on the Catedral's
## stylobate and its eight steps, up the Banco's five steps to its porch, on the Cabildo's arcade; 0 elsewhere.
func ground_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for r: Rect2 in stair_rects:
		if r.has_point(p):
			var run := minf(r.size.x - 1.6, 24.0 * 0.29)
			var down := r.end.x - 0.15 - x
			if down <= 0.0: return 0.0
			return -stair_depth * float(mini(int(down / (run / 24.0)) + 1, 24)) / 24.0
	for id: String in sim.vehicles:
		var vr: Rect2 = sim.vehicle_rect(id)
		if Rect2(vr.position / 32.0, vr.size / 32.0).has_point(p):
			return 0.82 if id == "tram" else 0.66
	var cat := _r("catedral", [44.0, -22.0, 96.0, 22.0])
	if x >= cat.position.x and x <= cat.end.x and z <= cat.end.y and z >= cat.end.y - 11.0:
		var back := cat.end.y - z
		return float(pw.get("stylobate", 1.6)) if back >= 3.6 else 0.2 * float(int(back / 0.45) + 1)
	var porch := _r("bancoPorch", [202.727, 18.0, 227.273, 22.0])
	if x >= porch.position.x and x <= porch.end.x and z >= porch.position.y and z <= porch.end.y + 0.6:
		return 0.2 * float(clampi(int((porch.end.y + 0.6 - z) / 0.5) + 1, 1, 5))
	if _r("arcade", [24.6, 100.0, 28.0, 126.0]).has_point(p): return 0.08
	return 0.0

# ---------------------------------------------------------------------------------------------------------------
# Per frame
# ---------------------------------------------------------------------------------------------------------------
func update(dt: float, paused: bool) -> void:
	_sync_rules(dt)
	_sync_power(dt, false)
	if not finale_running: _sync_faders(dt)
	_sync_palms(dt)
	_clock += 0.0 if paused else dt
	_sync_snow(false)
	_sync_veil(dt)
	_sync_tram()
	_sync_cloths()
	_sync_mounds()
	_sync_gate(dt)
	if creatures != null: creatures.update(dt, paused)

## The palms' crowns thin out over whoever stands under them, over the cursor, and wherever one hides an operative or
## a cascarudo from the camera (plaza_kit_props.gd sync_palms; decided ten times a second, eased every frame).
var _palm_clock: float = 0.0
func _sync_palms(dt: float) -> void:
	if pk == null or pk.palm_crowns.is_empty(): return
	_palm_clock += dt
	var decide := _palm_clock >= 0.1
	var under: Array = []
	var watched: Array = []
	var cursor: Variant = null
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if decide:
		_palm_clock = 0.0
		for unit: Dictionary in sim.units:
			if not bool(unit.alive): continue
			var p := Vector3(float(unit.x) / 32.0, 0.9, float(unit.y) / 32.0)
			under.append(p)
			watched.append(p)
		for guard: Dictionary in sim.guards:
			if guard.state in ["dead", "waiting"]: continue
			var p := Vector3(float(guard.x) / 32.0, 1.0, float(guard.y) / 32.0)
			under.append(p)
			if bool(guard.get("creature", false)): watched.append(p)
		if sim.has_method("people"):
			for q: Dictionary in sim.people(): under.append(Vector3(float(q.x) / 32.0, 0.9, float(q.y) / 32.0))
		if camera != null:
			var mouse := get_viewport().get_mouse_position()
			if get_viewport().get_visible_rect().has_point(mouse) and mouse != Vector2.ZERO:
				cursor = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	pk.props.sync_palms(dt, camera, under, watched, cursor, _ink_cutaway, decide)

## The square's lamps: lit, but the snow wind and the old cables make them stutter now and then (more in a wave), each
## on its own beat, their halos with them; the arcade's lanterns lit only once Lechuza has mended their fuses.
func _sync_power(_dt: float, instant: bool) -> void:
	var strength: float = float(sim.snow_intensity()) if sim.has_method("snow_intensity") else 1.0
	_wave = clampf((strength - 1.0) / 1.5, 0.0, 1.0)
	var mended: bool = sim.rigged.has("cabildo-lights")
	for lamp: Dictionary in lamps:
		var level := 1.0
		if bool(lamp.get("arcade", false)):
			level = 1.0 if mended else 0.0
		elif not bool(lamp.get("steady", true)):
			var seed: float = float(lamp.get("seed", 0.0))
			var beat := fposmod(_clock * (0.05 + 0.02 * fposmod(seed * 7.0, 1.0)) + seed, 1.0)
			var window := 0.03 + 0.06 * _wave
			if beat < window:
				level = 1.0 if fposmod(_clock * (11.0 + seed * 3.0), 1.0) > 0.45 else 0.18
		var light := lamp.light as OmniLight3D
		var want := float(lamp.energy) * level
		if absf(light.light_energy - want) < 0.001 and not instant: continue
		light.light_energy = want
		light.visible = level > 0.01
		_glow(lamp, level)
	if _arcade_shade != null: _arcade_shade.visible = not mended
	if _lanterns_lit != null: _lanterns_lit.visible = mended
	if _lanterns_dark != null: _lanterns_dark.visible = not mended

## A lamp's halos and its glow in the air, at `level` of their own brightness.
func _glow(lamp: Dictionary, level: float) -> void:
	var tone := Color(level, level, level, level)
	for i: int in lamp.get("halos", []): _halo_mm.set_instance_color(i, _halo_base[i] * tone)
	for i: int in lamp.get("fogs", []): _fog_mm.set_instance_color(i, _fog_base[i] * tone)

## The snow building up with the night, over the dusting that lay at the start (PlazaGround.laid): on everything
## built (snow_amount of the surfaces: La Boca's, and the kit's a little ahead since its ledges already hold their
## snow; the faders' copies too), in the drifts against the walls; and the wind of a wave in the flags.
func _sync_snow(force: bool) -> void:
	var cover := PlazaGround.laid(PlazaGround.snow_cover(sim))
	var amount := clampf(cover * 1.1, 0.0, 1.0)
	var kit_amount := clampf(0.15 + cover * 0.9, 0.0, 1.0)
	for flag: ShaderMaterial in _flags: flag.set_shader_parameter("wind", 0.6 + _wave * 1.4)
	if pk != null and pk.materials.has("palm_detail"):
		for key: String in ["palm_detail", "palm_ghost"]: (pk.materials[key] as ShaderMaterial).set_shader_parameter("sway", 0.45 + _wave * 1.1)
	if absf(amount - _snow_set) < 0.004 and not force: return
	_snow_set = amount
	var seen: Dictionary = {}
	var mats: Array = materials.values()
	for kit: PlazaKit in [pk, tram_kit]:
		if kit != null: mats.append_array(kit.materials.values())
	for fader: Dictionary in faders: mats.append_array(fader.mats)
	for mat: Variant in mats:
		if not mat is ShaderMaterial or seen.has(mat): continue
		seen[mat] = true
		var sm := mat as ShaderMaterial
		if sm.shader == SurfaceShader or sm.shader == WallsShader: sm.set_shader_parameter("snow_amount", amount)
		elif sm.shader == PlazaKit.WallsShader or sm.shader == PlazaKit.DetailShader: sm.set_shader_parameter("snow_amount", kit_amount)
	var lift := clampf(cover * 1.25, 0.03, 1.0)
	if _drift_material != null: _drift_material.set_shader_parameter("grow", lift)
	if city != null: city.set_snow(kit_amount)
	for vm: ShaderMaterial in _vehicle_mats: vm.set_shader_parameter("snow_amount", kit_amount)

## In a wave the falling snow thickens into a veil over the square: the night's depth haze drawn in closer and paler,
## easing off again in a lull (not in comic ink: the drawing keeps its paper).
func _sync_veil(dt: float) -> void:
	var world: Node = get_parent().get_parent() if get_parent() != null else null
	var atmosphere: Node = world.get("atmosphere") if world != null else null
	var holder: WorldEnvironment = atmosphere.get("environment") as WorldEnvironment if atmosphere != null else null
	if holder == null or holder.environment == null: return
	var env := holder.environment
	if _haze_base.is_empty(): _haze_base = [env.fog_depth_begin, env.fog_density, env.fog_light_color]
	var want := 0.0 if _ink_cutaway else _wave
	var was := _veil
	_veil = move_toward(_veil, want, maxf(dt, 0.0) * 0.25)
	# (left alone while it holds steady: a tool may move the haze for a picture of its own)
	if absf(_veil - was) < 0.00001 and _veil_set: return
	_veil_set = true
	env.fog_depth_begin = lerpf(float(_haze_base[0]), 14.0, _veil * 0.85)
	env.fog_density = lerpf(float(_haze_base[1]), 0.8, _veil)
	env.fog_light_color = (_haze_base[2] as Color).lerp(Color(0.6, 0.61, 0.7), _veil * 0.55)

## The tram where the rules have it (its middle over the rules' rectangle's).
func _sync_tram() -> void:
	if tram == null: return
	var vr: Rect2 = sim.vehicle_rect("tram")
	if vr.size == Vector2.ZERO: return
	var c := vr.get_center() / 32.0
	tram.position = Vector3(c.x, 0.0, c.y)

## The cloths still on their frames; the ones taken, held up over the operatives who carry them.
func _sync_cloths() -> void:
	for id: String in cloths:
		(cloths[id] as Node3D).visible = not sim.canvases_taken.has(id)
	var i := 0
	for unit: Dictionary in sim.units:
		if i >= _held.size(): break
		if (unit.get("canvas", {}) as Dictionary).is_empty() or not bool(unit.alive): continue
		var held := _held[i]
		held.visible = true
		var at := Vector3(float(unit.x) / 32.0, 2.15 + ground_height(float(unit.x) / 32.0, float(unit.y) / 32.0), float(unit.y) / 32.0)
		held.position = at
		held.rotation = Vector3(0.0, PI * 0.5 - float(unit.angle), 0.0)
		i += 1
	for j: int in range(i, _held.size()):
		_held[j].visible = false

## A mound over each one down in the snow: growing while they wait (their grace running out), whole once covered.
func _sync_mounds() -> void:
	if _mounds == null: return
	var spec: Dictionary = sim.data.get("snowfall", {})
	var grace: Dictionary = spec.get("grace", {})
	var n := 0
	var down: Array = []
	for person: Dictionary in sim.guards:
		if not bool(person.get("person", false)) or str(person.get("carried_by", "")) != "": continue
		var state := str(person.state)
		if state == "fallen": down.append([person, float(person.get("fall_left", 0.0)) / maxf(1.0, float(grace.get("person", 40.0))), false])
		elif state == "lost": down.append([person, 0.0, true])
	for unit: Dictionary in sim.units:
		# (sealed in his suit the snow does not cover Juan Salvo: knocked down, he gets up again by himself)
		if bool(unit.get("suit", false)): continue
		if bool(unit.get("fallen", false)): down.append([unit, float(unit.get("fall_left", 0.0)) / maxf(1.0, float(grace.get("unit", 45.0))), false])
		elif bool(unit.get("buried", false)): down.append([unit, 0.0, true])
	for entry: Array in down:
		if n >= _mounds.instance_count: break
		var actor: Dictionary = entry[0]
		var left: float = clampf(float(entry[1]), 0.0, 1.0)
		var whole: bool = entry[2]
		var x := float(actor.x) / 32.0
		var z := float(actor.y) / 32.0
		var grown := 1.0 if whole else 0.25 + 0.5 * (1.0 - left)
		var wide := 0.75 + 0.35 * grown
		var tall := 1.25 * grown
		var yaw := fposmod(x * 1.7 + z * 2.3, TAU)
		_mounds.set_instance_transform(n, Transform3D(Basis(UP, yaw) * Basis.from_scale(Vector3(wide, tall, wide * 0.85)), Vector3(x, ground_height(x, z), z)))
		n += 1
	_mounds.visible_instance_count = n

## The service gate: swung open once the rules' passage is rigged (shut again by a checkpoint from before).
func _sync_gate(dt: float) -> void:
	if _gate_leaf == null: return
	var want := -1.7 if sim.rigged.has("subte-gate") else 0.0
	_gate_angle = move_toward(_gate_angle, want, maxf(dt, 0.0) * 1.6) if absf(_gate_angle - want) < 1.8 else want
	_gate_leaf.rotation.y = _gate_angle
