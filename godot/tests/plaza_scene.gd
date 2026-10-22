extends SceneTree
## The Plaza de Mayo through the real 3D scene (the operation "plaza"; it puts itself on the list): the plaza builders
## make the world, a snowy night; the squad wear their own figures and the square's people theirs, none of them with
## a cone; every landmark is built from the Plaza de Mayo kit on the rules' footprints (the blockout's builders gone),
## the stairs open in the ground; the national flag flies; the square's lamps are lit and stutter now and then, the
## arcade's lanterns stay dark until Lechuza mends them; the
## snow builds up with the rules' clock (the ground, the walls, the drifts) and falls thicker in a wave; the tram runs
## with the rules' vehicle and carries whoever is aboard; the stairs go down into the subte; a cloth goes from its frame
## to over the operative who takes it; somebody fallen kneels under a growing mound, and somebody lost shows only the
## mound; the service gate swings open; the HUD shows the cold on the photos and over the people; and a checkpoint
## from before it all puts it back. Juan Salvo and the cascarudos: their figures are the art pack's licensed models
## (Juan on his own skeleton, his rifle in his hands, one draw; a cascarudo 4 m long, a lighter copy of it far off, no
## stand-in plate on either), and the neutral stand-ins with their plates in a build without them; either way they throw no shadow from the sky as no figure does here, nobody sees them
## before they come or while one is off the map, his photo is his portrait or a plain plate with his name, and the
## square's ink marks them; and the test models of the art pack (a static capsule, a static block, a rigged post) worn
## in their place load, stand at the slot's size, turn the way they walk and move as they walk. The vehicles: the
## friends' Línea 60, microcar and pickup and the cars of the time made on their generator (the taxis black, every fleet
## in its models' colours), the kit's own colectivo and cars in a build without their files.
## Run: godot --headless --path godot --script res://tests/plaza_scene.gd
const Missions = preload("res://scripts/missions.gd")
const Plaza = preload("res://scripts/three_d/plaza.gd")
const PlazaKit = preload("res://scripts/three_d/plaza_kit.gd")
const PlazaGround = preload("res://scripts/three_d/plaza_ground.gd")
const PlazaCity = preload("res://scripts/three_d/plaza_city.gd")
const Operative = preload("res://scripts/three_d/operative.gd")
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const PlazaCreatures = preload("res://scripts/three_d/plaza_creatures.gd")
var main: Node3D
## Whether the build has the licensed models (Juan Salvo, the cascarudo) and the vehicles' models (README.md).
var licensed: bool = false
var vehicles: bool = false
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
	for i: int in range(int(round(seconds / 0.05))):
		main.sim.update(0.05)
		main.world.update_visuals(0.05)

static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

func _put(actor: Dictionary, at: Vector2) -> void:
	actor.x = at.x
	actor.y = at.y
	actor.path = []

func _node(s: Node, name_part: String) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in s.get_children():
		if name_part in str(child.name): out.append(child)
	return out

func run() -> void:
	Missions.choose("plaza", false)
	ArtPack.forget()
	licensed = bool(ArtPack.slot("juan_salvo").get("ready", false)) and bool(ArtPack.slot("cascarudo").get("ready", false))
	vehicles = true
	for model: String in ["colectivo60_open", "colectivo60_far", "microcar", "work_pickup", "sedan49", "taxi49", "saloon53", "coupe48", "pickup51", "van51"]:
		vehicles = vehicles and PlazaCity.has_vehicle(model)
	print("plaza_scene: licensed models %s, vehicles %s" % ["in the build" if licensed else "missing (stand-ins)", "in the build" if vehicles else "missing (the kit's own)"])
	var t0: int = Time.get_ticks_msec()
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await _frames(8)
	print("The Plaza de Mayo built in %d ms" % (Time.get_ticks_msec() - t0))
	var sim: RefCounted = main.sim
	var data: Dictionary = sim.data
	var s: Node3D = main.world.structures
	var g: Node3D = main.world.nature
	check(str(data.get("id", "")) == "plaza-05", "the scene plays the Plaza de Mayo (%s)" % str(data.get("id", "")))
	check(s.get_script() == Plaza and g.get_script() == PlazaGround, "the plaza builders made the world")
	check(main.world.atmosphere.night and main.world.atmosphere.snow, "a snowy night")
	check(main.world.actors.size() == data.units.size() + sim.guards.size(), "the squad and every one of the square's people have a model (%d)" % main.world.actors.size())
	check(main.hud.portrait_buttons.size() == 5, "a photo for each of the five")
	for unit: Dictionary in data.units:
		if str(unit.id) == "salvo": continue
		var model: Node3D = main.world.actors[str(unit.id)]
		check(str(model.look_key) == str(unit.id) and model.baked, "%s wears his own figure (%s)" % [unit.id, model.look_key])
	_licensed(sim)
	var looks: Dictionary = {}
	for p: Dictionary in sim.people():
		var model: Node3D = main.world.actors[str(p.id)]
		looks[str(p.get("look", "")).rstrip("0123456789")] = true
		check(model.baked and str(model.look_key) == str(p.get("look", "")), "%s wears the look %s" % [p.id, p.get("look", "")])
	check(looks.keys().all(func(k: String) -> bool: return k in ["vecino", "vecina"]), "only the city's own people: %s" % str(looks.keys()))
	main.world.update_visuals(0.05)
	var cones_up: int = 0
	for id: String in main.world.cone_nodes:
		if (main.world.cone_nodes[id] as Node3D).visible: cones_up += 1
	check(cones_up == 0, "nobody in the square has a sight cone (%d shown)" % cones_up)
	# every landmark, from the kit
	check(s.pk is PlazaKit, "the square is built from the Plaza de Mayo kit")
	# (the avenue's rows all stand beyond the map now, folded into the city's mesh: the kit's stats below say they were
	# built; the cars of the time are the friends' models and those made on their generator, in the fleet's
	# multimeshes; without their files, the kit's own sedans, taxis and saloons, and the kit's colectivo up the avenue)
	var parts: Array = ["CasaRosada", "Cabildo", "Catedral", "BancoNacion", "Ministerio", "Hacienda", "Municipal", "Piramide", "Belgrano", "Flagpole", "Palms", "LampPosts", "Benches", "Subte_", "Kiosk", "Cart", "Colectivo", "Truck", "Tram", "TramRails", "TramWires", "CafeFront", "Drift", "CityDetails", "CityDetailPlates"]
	parts.append_array(["Fleet_sedan49", "Fleet_taxi49", "Fleet_saloon53", "Fleet_coupe48", "Fleet_microcar", "Fleet_work_pickup", "Fleet_colectivo60_far"] if vehicles else ["Sedan", "Taxi", "Saloon", "ColectivoAvenida"])
	for part: String in parts:
		check(not _node(s, part).is_empty(), "built: %s" % part)
	if vehicles:
		var shown: bool = true
		for node: Node in _node(s, "Fleet_"):
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			# (instance colours on, white: the GL Compatibility renderer multiplies the vertex colours, which carry the
			# models' materials, by them)
			shown = shown and mm.use_colors and mm.use_custom_data
		check(shown, "every fleet shows its models' own colours")
		var black_taxis: bool = not (s._fleet.get("taxi49", []) as Array).is_empty()
		for item: Array in s._fleet.get("taxi49", []): black_taxis = black_taxis and (item[1] as Color).v < 0.15
		check(black_taxis, "the taxis are black (their roofs yellow in the model)")
		check(not s.pk.stats.has("Sedan") and _node(s, "Sedan").is_empty(), "no kit sedan stands in for the cars of the time")
		# the cars parked in the plaza's streets are the near copies: their glass a surface of its own, the inside
		# (seats, dashboard, steering wheel) showing through it; out in the city the far copies, one surface
		if PlazaCity.has_vehicle("sedan49_near"):
			var near_ok := false
			var far_ok := true
			for model: String in s._fleet:
				var mesh: Mesh = load(Plaza.VEHICLES + model + ".res")
				if model.ends_with("_near"):
					near_ok = mesh.get_surface_count() == 2 and mesh.surface_get_material(1) is ShaderMaterial and (mesh.surface_get_material(1) as ShaderMaterial).shader == Plaza.VehicleGlassShader
					if not near_ok: break
				else: far_ok = far_ok and mesh.get_surface_count() == 1
			check(near_ok and not _node(s, "Fleet_sedan49_near").is_empty(), "the cars parked in the plaza's streets are the near copies, their insides through their glass")
			check(far_ok, "out in the city the far copies, one surface each")
	else:
		check(_node(s, "Fleet_").is_empty(), "no vehicle model in the build: no fleet of them")
	var kit_pieces: Array = ["CasaRosada", "Cabildo", "Catedral", "BancoNacion", "Ministerios", "AvenidaDeMayo", "Piramide", "Belgrano", "Flagpole", "Kiosk", "SubteEntrance", "LampPosts", "Palms", "Benches", "Tram"]
	if not vehicles: kit_pieces.append("Sedan")
	for piece: String in kit_pieces:
		check(s.pk.stats.has(piece) or (s.tram_kit != null and s.tram_kit.stats.has(piece)), "the kit built: %s" % piece)
	var bus_rule: Rect2 = PlazaGround.rect_of(data.plazaWorld, "colectivo", [199.7, 137.08, 207.3, 139.32])
	if vehicles:
		# the rules' colectivo is the Línea 60 (the friends' model, its door open at the kerb), lit, its own material
		var bus_mesh: MeshInstance3D = s.bus as MeshInstance3D
		check(bus_mesh != null and bus_mesh.mesh != null and bus_mesh.mesh.resource_path.ends_with("colectivo60_open.res"), "the colectivo on Yrigoyen is the Línea 60")
		var bus_body: ShaderMaterial = bus_mesh.get_surface_override_material(0) if bus_mesh != null else null
		check(bus_body != null and float(bus_body.get_shader_parameter("in_service")) > 0.5, "the Línea 60 is lit, in service")
		var bus_glass: ShaderMaterial = bus_mesh.get_surface_override_material(1) if bus_mesh != null and bus_mesh.mesh.get_surface_count() > 1 else null
		check(bus_glass != null and bus_glass.shader == Plaza.VehicleGlassShader and float(bus_glass.get_shader_parameter("in_service")) > 0.5, "its inside lit behind its glass")
		var bus_box: AABB = bus_mesh.transform * bus_mesh.get_aabb() if bus_mesh != null else AABB()
		check(absf(bus_box.get_center().x - bus_rule.get_center().x) < 0.5 and absf(bus_box.get_center().z - bus_rule.get_center().y) < 0.5, "the Línea 60 stands where the rules have the colectivo")
	else:
		# without the Línea 60's model, the rules' colectivo is the kit's own (unbranded), its door open at the kerb, lit
		check(s.bus != null and not (s.bus is MeshInstance3D) and str(s.bus.name) == "Colectivo" and s.bus.get_child_count() > 0, "the colectivo on Yrigoyen is the kit's own")
		var at: Vector3 = s.bus.position if s.bus != null else Vector3.INF
		check(absf(at.x - bus_rule.get_center().x) < 0.5 and absf(at.z - bus_rule.get_center().y) < 0.5, "the kit's colectivo stands where the rules have it (%s)" % str(at))
		check(s.faders.any(func(f: Dictionary) -> bool: return s.bus != null and is_instance_valid(f.node) and (f.node as Node).get_parent() == s.bus), "…and fades like the buildings when somebody stands behind it")
	for fn: String in ["_casa_rosada", "_cabildo", "_catedral", "_piramide", "_belgrano", "_banco_nacion", "_ministerios", "_avenida_de_mayo", "_subte_entrance", "_palm", "_lamp", "_flagpole", "_tram_car", "_colectivo", "_kiosk", "_city_block", "_facade"]:
		check(not s.has_method(fn), "the blockout's %s() is gone" % fn)
	var tram_car: Node3D = s.tram.get_node_or_null("Car")
	check(tram_car != null and absf(tram_car.scale.z * Plaza.KIT_TRAM.y - float(sim.vehicle_spec("tram").w) / 32.0) < 0.01, "the kit's tram fitted to the rules' car")
	var stairs: int = 0
	for n: Node in _node(s, "Subte_"): stairs += 1
	check(stairs == 3, "three stairs down into the subte (%d)" % stairs)
	# the stairs open in the ground: no piece of the land over them
	for key: String in ["subteN", "subteS", "subteService"]:
		var hole: Rect2 = PlazaGround.rect_of(data.plazaWorld, key)
		var covered: bool = false
		for land: Node in _node(g, "Land"):
			var mi := land as MeshInstance3D
			var size: Vector2 = (mi.mesh as PlaneMesh).size
			var r := Rect2(mi.position.x - size.x * 0.5, mi.position.z - size.y * 0.5, size.x, size.y)
			if r.grow(-0.01).intersects(hole.grow(-0.05)): covered = true
		check(not covered, "the ground is open over the stair %s" % key)
	var flag: MeshInstance3D = s.get_node("Flagpole").get_node_or_null("Flag")
	check(flag != null and flag.material_override is ShaderMaterial and (flag.material_override as ShaderMaterial).shader == Plaza.FlagShader, "the national flag flies from the flagpole")
	var rosada_flag: MeshInstance3D = s.get_node("CasaRosada").get_node_or_null("Flag")
	check(rosada_flag != null and rosada_flag.global_position.y > 25.0, "and over the Casa Rosada (%.1f m up)" % (rosada_flag.global_position.y if rosada_flag != null else 0.0))
	# the walk and the cover where the kit built them: the portico's columns, the arcade's piers
	var cat: Rect2 = PlazaGround.rect_of(data.plazaWorld, "catedral")
	var columns_z: Array = data.plazaWorld.columnsZ
	var col_x: Array = data.plazaWorld.columnX
	var w_cat: float = cat.size.x
	check(absf(float(col_x[0]) - (cat.position.x + w_cat * 0.04)) < 0.01 and absf(float(col_x[11]) - (cat.end.x - w_cat * 0.04)) < 0.01 and absf((float(columns_z[0]) + float(columns_z[1])) * 0.5 - (cat.end.y - 5.0)) < 0.01, "the rules' columns stand where the kit's do")
	check(sim.is_blocked(m(float(col_x[5]), (float(columns_z[0]) + float(columns_z[1])) * 0.5)) and not sim.is_blocked(m((float(col_x[5]) + float(col_x[6])) * 0.5, (float(columns_z[0]) + float(columns_z[1])) * 0.5)), "between the columns a way in, at a column none")
	check(sim.shelter_at(m(26.0, 113.0), true) == "" and sim.shelter_at(m(26.0, 113.0), false) == "cabildo" and not sim.is_blocked(m(26.0, 113.0)) and sim.is_blocked(m(23.0, 113.0)), "the arcade is walkable cover in front of the Cabildo's wall")
	var palms: int = 0
	for spot: Array in data.plazaWorld.palms: palms += 1
	check(palms == 8, "eight palms round the Pirámide")
	# the palms: Canary date palms with crowns about as wide as a palm that age (not the wide cards they were), each
	# crown fading on its own over whoever stands under it, and back again
	check(s.pk.palm_crowns.size() == 8, "the eight palms' crowns are known to fade (%d)" % s.pk.palm_crowns.size())
	var widest: float = 0.0
	for node: Node in _node(s, "Palms"):
		var box: AABB = ((node as MultiMeshInstance3D).multimesh as MultiMesh).mesh.get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z))
	check(widest > 6.0 and widest < 9.5, "a palm's crown is some 7-9 m across (%.1f m)" % widest)
	var pd: ShaderMaterial = s.pk.materials.get("palm_detail")
	check(pd != null and bool(pd.get_shader_parameter("instance_fade")) and float(pd.get_shader_parameter("sway")) > 0.0, "the palms' fronds sway and their crowns fade one by one")
	if s.pk.palm_crowns.size() > 0:
		var crown: Dictionary = s.pk.palm_crowns[0]
		var cam: Camera3D = main.camera
		var under_it: Array = [crown.at + Vector3(1.0, 0.9, 0.5)]
		s.pk.props.sync_palms(0.1, cam, under_it, [], null, false, true)
		for i: int in range(10): s.pk.props.sync_palms(0.1, cam, under_it, [], null, false, false)
		# (the crown's own state: a headless run keeps no instance data to read back); while it fades its see-through
		# copy shows in its place
		var faded: float = float(crown.alpha)
		var ghost_shown: bool = (crown.ghost as MultiMeshInstance3D).visible
		var others_whole: bool = true
		for c: Dictionary in s.pk.palm_crowns:
			if c != crown and float(c.alpha) < 0.99: others_whole = false
		s.pk.props.sync_palms(0.1, cam, [], [], null, false, true)
		for i: int in range(10): s.pk.props.sync_palms(0.1, cam, [], [], null, false, false)
		var back: float = float(crown.alpha)
		check(faded < 0.3 and ghost_shown and others_whole and back > 0.99 and not (crown.ghost as MultiMeshInstance3D).visible, "a palm's crown thins out (see-through) over somebody under it, the others stay, and it comes back (%.2f, %.2f)" % [faded, back])
	# the Casa Rosada in its own stucco and stone, the weather on it
	var rosada: Node3D = s.get_node("CasaRosada")
	var body: ArrayMesh = (rosada.get_node("Body") as MeshInstance3D).mesh
	var layers_used: Dictionary = {}
	for si: int in range(body.get_surface_count()):
		var uv2: Variant = body.surface_get_arrays(si)[Mesh.ARRAY_TEX_UV2]
		if uv2 is PackedVector2Array:
			for u: Vector2 in uv2: layers_used[int(u.x + 0.5)] = true
	check(layers_used.has(PlazaKit.WALL_LAYERS.find("stucco")) and layers_used.has(PlazaKit.WALL_LAYERS.find("stone")), "the Casa Rosada in lime stucco with stone trims")
	var detail: ArrayMesh = (rosada.get_node("Detail") as MeshInstance3D).mesh
	var grimy: bool = false
	for si: int in range(detail.get_surface_count()):
		if detail.surface_get_name(si) == "grime": grimy = (detail.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 600
	check(grimy, "the weather on the Casa Rosada: streaks, soot and damp")
	# the lamps
	var square: Array = []
	var arcade: Array = []
	for lamp: Dictionary in s.lamps:
		if bool(lamp.get("arcade", false)): arcade.append(lamp)
		elif not bool(lamp.get("steady", true)): square.append(lamp)
	check(square.size() == data.plazaWorld.lamps.size(), "a lamp of the square at every spot the layout gives (%d)" % square.size())
	check(arcade.size() == 5, "a lantern in each of the Cabildo's five arches (%d)" % arcade.size())
	check(s._lanterns_dark.visible and not s._lanterns_lit.visible, "the arcade's lanterns hang dark")
	var lit: bool = true
	for lamp: Dictionary in square: lit = lit and (lamp.light as OmniLight3D).visible
	check(lit, "the square's lamps are lit")
	var dark: bool = true
	for lamp: Dictionary in arcade: dark = dark and not (lamp.light as OmniLight3D).visible
	check(dark and s._arcade_shade.visible, "the arcade is dark until its lights are mended")
	# the ground at the start: wet stone, the snow only beginning
	var ground_mat: ShaderMaterial = g.snow_material
	check(absf(float(ground_mat.get_shader_parameter("cover")) - PlazaGround.DUSTING) < 0.02, "only the first dusting lies on the ground (%.3f)" % float(ground_mat.get_shader_parameter("cover")))
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	var saved: Dictionary = sim.snapshot()
	var tram0: Vector3 = s.tram.position
	# the snow builds up with the clock, and falls thicker in a wave than in a lull
	var fall: MultiMesh = (g.get_node("Snowfall") as MultiMeshInstance3D).multimesh
	var flickered: bool = false
	var lull_flakes: int = fall.visible_instance_count
	var wave_flakes: int = 0
	var t_wave: float = 0.0
	for spec: Array in data.snowfall.schedule:
		if float(spec[1]) >= float(data.snowfall.heavy):
			t_wave = float(spec[0]) + 1.0
			break
	# (nobody out in it while it builds: the rules' own tests see to them)
	for p: Dictionary in sim.people(): p.exposure = 0.0
	while float(sim.time) < t_wave:
		_step(1.0)
		for p: Dictionary in sim.people():
			p.exposure = 0.0
			p.panic = {}
		for u: Dictionary in sim.units: u.exposure = 0.0
		for lamp: Dictionary in square:
			if (lamp.light as OmniLight3D).light_energy < float(lamp.energy) * 0.5: flickered = true
	wave_flakes = fall.visible_instance_count
	check(wave_flakes > lull_flakes + 400, "the snow falls thicker in a wave (%d flakes against %d)" % [wave_flakes, lull_flakes])
	var near_fall: MultiMeshInstance3D = g.get_node_or_null("SnowfallNear")
	check(near_fall != null and near_fall.multimesh.visible_instance_count > 0 and int((near_fall.material_override as ShaderMaterial).get_shader_parameter("lamp_count")) > 0, "a nearer layer of flakes falls too, and the flakes catch the lamps' light")
	var city_parts: int = _node(s, "City_").size()
	var city_kit: int = _node(s, "CityKit_").size()
	check(s.city != null and city_parts > 10 and city_kit > 4, "Buenos Aires stands round the square (%d districts of blocks, %d of the kit's)" % [city_parts, city_kit])
	# the city's buildings stand apart: the Cabildo free in its streets (nothing of the city within twelve metres of it),
	# no lot a sliver, no two lots in each other
	var cab_free: Rect2 = PlazaGround.rect_of(data.plazaWorld, "cabildo", [4.0, 100.0, 28.0, 126.0]).grow(12.0)
	var crowding: Array = []
	var slivers: int = 0
	var boxes: Array[Rect2] = []
	for lot: Array in s.city.lots:
		var outline: PackedVector2Array = lot[0]
		var box := Rect2(outline[0], Vector2.ZERO)
		for p: Vector2 in outline: box = box.expand(p)
		boxes.append(box)
		if box.intersects(cab_free) and not Geometry2D.intersect_polygons(outline, PackedVector2Array([cab_free.position, Vector2(cab_free.end.x, cab_free.position.y), cab_free.end, Vector2(cab_free.position.x, cab_free.end.y)])).is_empty(): crowding.append(box)
		if PlazaCity._thickness(outline) < 3.0: slivers += 1
	var overlaps: int = 0
	for i: int in range(boxes.size()):
		for j: int in range(i + 1, boxes.size()):
			if not boxes[i].grow(-0.3).intersects(boxes[j].grow(-0.3)): continue
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(s.city.lots[i][0], s.city.lots[j][0]):
				if absf(PlazaCity._area(piece)) > 1.0: overlaps += 1
	check(crowding.is_empty(), "nothing of the city crowds the Cabildo (%s)" % str(crowding))
	check(slivers == 0 and s.city.lots.size() > 300, "the city's %d lots and back buildings each a building, none a sliver (%d)" % [s.city.lots.size(), slivers])
	check(overlaps == 0, "no two of the city's buildings stand in each other (%d)" % overlaps)
	check(flickered, "now and then a lamp of the square stutters")
	var cover: float = float(ground_mat.get_shader_parameter("cover"))
	check(cover > PlazaGround.DUSTING + 0.05 and absf(cover - PlazaGround.laid(PlazaGround.snow_cover(sim))) < 0.01, "the ground whitens with the night's snow (%.2f)" % cover)
	var walls: ShaderMaterial = s.materials["walls"]
	check(float(walls.get_shader_parameter("snow_amount")) > 0.1 and float(walls.get_shader_parameter("snow_amount")) < 1.0, "snow is settling on what is built (%.2f)" % float(walls.get_shader_parameter("snow_amount")))
	var kit_walls: ShaderMaterial = s.pk.materials["pwalls"]
	var kit_snow: float = float(kit_walls.get_shader_parameter("snow_amount"))
	check(kit_snow > 0.3 and kit_snow < 1.0 and absf(float((s.pk.materials["pdetail"] as ShaderMaterial).get_shader_parameter("snow_amount")) - kit_snow) < 0.001, "and on the kit's landmarks and palms (%.2f)" % kit_snow)
	var faded_too: bool = true
	for fader: Dictionary in s.faders:
		for mat: Material in fader.mats:
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == PlazaKit.WallsShader: faded_too = faded_too and absf(float((mat as ShaderMaterial).get_shader_parameter("snow_amount")) - kit_snow) < 0.001
	check(faded_too, "the fading copies of the kit's walls take the snow too")
	var grow: float = float(s._drift_material.get_shader_parameter("grow"))
	check(not s._drifts.is_empty() and grow > 0.05 and grow < 1.0 and s._drifts[0].scale.y == 1.0, "the drifts against the walls are growing out and up (%.2f)" % grow)
	# the subte's stairs go down, the tram's floor and the portico's are up
	var stair: Rect2 = PlazaGround.rect_of(data.plazaWorld, "subteN")
	check(s.ground_height(stair.position.x + 0.5, stair.get_center().y) < -3.0 and absf(s.ground_height(stair.end.x - 0.1, stair.get_center().y)) < 0.3, "down the subte's stair (%.1f m at its foot)" % s.ground_height(stair.position.x + 0.5, stair.get_center().y))
	check(absf(s.ground_height(70.0, 14.0) - 1.6) < 0.01 and absf(s.ground_height(70.0, 21.9) - 0.2) < 0.01, "up on the Catedral's portico, its steps down to the pavement")
	check(absf(s.ground_height(215.0, 19.0) - 1.0) < 0.01, "up the Banco's steps to its porch")
	check(absf(s.ground_height(142.0, 84.0 - 30.0)) < 0.001, "the square itself is level")
	# the tram runs with the rules' vehicle, and whoever is aboard rides with it
	var hornero: Dictionary = sim.unit_by_id("hornero")
	var spec_t: Dictionary = sim.vehicle_spec("tram")
	var tr0: Rect2 = sim.vehicle_rect("tram")
	_put(hornero, tr0.get_center())
	var rider: Dictionary = sim.people()[0]
	_put(rider, tr0.get_center() + Vector2(48.0, 0.0))
	rider.state = "safe"
	rider.shelter = "tram"
	_step(0.1)
	check(absf((main.world.actors["hornero"] as Node3D).position.y - 0.82) < 0.05, "Hornero stands on the tram's floor")
	sim.select("hornero")
	check(sim.perform("drive", "tram"), "Hornero takes the tram on")
	_step(float(spec_t.get("time", 1.2)) + 8.0)
	check(s.tram.position.x > tram0.x + 4.0 and absf(s.tram.position.x - sim.vehicle_rect("tram").get_center().x / 32.0) < 0.05, "the tram moves along Rivadavia with the rules (%.1f m)" % s.tram.position.x)
	check(absf(sim.position_of(rider).x / 32.0 - s.tram.position.x - 1.5) < 0.2, "and the one aboard rides with it")
	# a cloth from its frame to over the operative who takes it
	var lechuza: Dictionary = sim.unit_by_id("lechuza")
	var awning: Dictionary = sim.canvas_by_id("awning")
	_put(lechuza, Vector2(float(awning.x), float(awning.y)) + Vector2(0.0, 40.0))
	sim.select("lechuza")
	check(s.cloths["awning"].visible, "the café's awning is on its frame")
	check(sim.perform("canvas", "awning"), "Lechuza goes for the awning")
	_step(float(awning.get("time", 50.0)) / 32.0 + 3.0)
	check(sim.canvases_taken.has("awning") and not s.cloths["awning"].visible, "the awning is gone from its frame once taken")
	var held: bool = false
	for h: MeshInstance3D in s._held:
		if h.visible and Vector2(h.position.x, h.position.z).distance_to(sim.position_of(lechuza) / 32.0) < 0.3 and h.position.y > 1.8: held = true
	check(held, "and held up over Lechuza's head")
	# somebody fallen kneels under a growing mound; somebody lost shows only the mound
	var fallen: Dictionary = sim.people()[3]
	var lost: Dictionary = sim.people()[4]
	sim._person_falls(fallen)
	_step(0.2)
	var model_f: Node3D = main.world.actors[str(fallen.id)]
	check(model_f.clip == Operative.CL_KNEEL, "the fallen one sinks to their knees (no lying sprawled)")
	check(s._mounds.visible_instance_count >= 1, "a mound of snow starts over them")
	sim._person_falls(lost)
	sim._person_lost(lost)
	_step(0.2)
	check(not (main.world.actors[str(lost.id)] as Node3D).visible and s._mounds.visible_instance_count >= 2, "the one the snow has covered shows only as a mound")
	var benteveo: Dictionary = sim.unit_by_id("benteveo")
	sim._unit_falls(benteveo)
	_step(0.3)
	var model_b: Node3D = main.world.actors["benteveo"]
	check(model_b.clip == Operative.CL_KNEEL and model_b.visible, "Benteveo down in the snow is on his knees, not fallen dead")
	main.hud.refresh()
	check(main.hud.portrait_buttons["benteveo"].health == 0, "his photo says he is down")
	check(main.hud.portrait_buttons["hornero"].cold >= 0.0, "the photos show the cold the four have taken")
	# the lights and the gate
	sim.rigged["cabildo-lights"] = "lechuza"
	sim.rigged["subte-gate"] = "lechuza"
	sim._geometry_dirty = true
	_step(1.5)
	var on: bool = true
	for lamp: Dictionary in arcade: on = on and (lamp.light as OmniLight3D).visible
	check(on and not s._arcade_shade.visible and s._lanterns_lit.visible and not s._lanterns_dark.visible, "the arcade's lanterns come on once mended")
	check(absf(s._gate_leaf.rotation.y) > 1.2, "the service gate swings open once unlocked")
	main.hud.refresh()
	check("/" in str(main.hud.status.text), "the readout counts who is under cover (%s)" % main.hud.status.text)
	# a checkpoint from before puts it all back
	sim.restore(saved)
	_step(1.5)
	check(s.tram.position.distance_to(tram0) < 0.1, "restored: the tram at its stop")
	check(s.cloths["awning"].visible and absf(s._gate_leaf.rotation.y) < 0.05 and s._arcade_shade.visible and s._lanterns_dark.visible, "the awning back on its frame, the gate shut, the arcade dark")
	check(s._mounds.visible_instance_count == 0 and (main.world.actors[str(lost.id)] as Node3D).visible, "no mounds, everyone standing")
	check(model_b.clip != Operative.CL_KNEEL, "Benteveo on his feet again")
	await _arrivals()
	await _test_models()
	Missions.choose("plaza", false)
	print("PLAZA_SCENE_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

## The words on a cut-out's plate.
static func _plate_words(cutout: Node3D) -> Array[String]:
	var words: Array[String] = []
	if cutout == null or cutout.get("plate") == null: return words
	for child: Node in (cutout.plate as Node3D).get_children():
		if child is Label3D: words.append((child as Label3D).text)
	return words

## Juan Salvo and the cascarudos dressed from the art pack's licensed slots: Juan's model on its own skeleton (his
## rifle in his hands, his own materials through the night's finish), the cascarudo's 4 m long with its lighter copy; no plate on either;
## no shadow from the sky; his photo his portrait; none of them seen before they come. Where the licensed models are
## not installed: the neutral stand-ins, each with its LICENSED ART PENDING plate, and a plain plate for his photo.
func _licensed(sim: RefCounted) -> void:
	if not licensed:
		_pending(sim)
		return
	var juan: Node3D = main.world.actors["salvo"]
	var cut: Node3D = juan.cutout
	check(cut != null and not cut.pending and cut.card == null and cut.model != null and cut.rig != null and not juan.body.visible, "Juan Salvo is his licensed model, moved on its own skeleton, his rig unseen")
	check(cut.plate == null and _plate_words(cut).is_empty(), "no LICENSED ART PENDING plate on him")
	check(absf(float(cut.height_m) - float(ArtPack.slot("juan_salvo").height_m)) < 0.001 and absf(float(cut.height_m) - 1.8) < 0.001, "as tall as his slot says (%.3f m)" % float(cut.height_m))
	var meshes: Array = cut.call("_model_meshes")
	var skinned: bool = not meshes.is_empty()
	for mi: MeshInstance3D in meshes:
		if mi.skin == null or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: skinned = false
	check(skinned and meshes.size() <= 14, "his model's parts on its skeleton, with no shadow from the sky (%d parts)" % meshes.size())
	# dressed for the night: each of his own materials (colour, normal map, packed maps) through the finish, his visor's
	# glass as it comes
	var dressed: int = 0
	var maps: int = 0
	var glass: int = 0
	for mi: MeshInstance3D in meshes:
		for k: int in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_surface_override_material(k)
			if m is ShaderMaterial:
				dressed += 1
				if (m as ShaderMaterial).get_shader_parameter("use_normal") == true and (m as ShaderMaterial).get_shader_parameter("use_orm") == true: maps += 1
			elif mi.get_active_material(k) is BaseMaterial3D and (mi.get_active_material(k) as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				glass += 1
	check(dressed >= 20 and maps >= 8 and glass >= 1, "dressed for the night: his own materials and maps (%d, %d with their maps), his visor's glass as it comes (%d)" % [dressed, maps, glass])
	check(cut.rig.has_prop and cut.muzzle() is Vector3, "his rifle in his hands, its muzzle known for the flash")
	var b: Node = main.hud.portrait_buttons["salvo"]
	var pic: Dictionary = ArtPack.portrait(ArtPack.slot("juan_salvo"))
	var region: Rect2 = b.photo_region
	check(b.photo != null and b.photo == pic.get("texture") and str(b.photo_plate) == "" and is_equal_approx(region.size.x, region.size.y) and region.position.y < region.size.y * 0.1,
		"his photo: his portrait, its head and shoulders (%s)" % str(region))
	main.world.update_visuals(0.05)
	check(not juan.visible, "not seen before he comes")
	var slot: Dictionary = ArtPack.slot("cascarudo")
	check(str(slot.kind) == "creature" and absf(float(slot.height_m) - 3.27) < 0.01 and absf(float(slot.length_m) - 4.0) < 0.01, "the cascarudo's slot: a creature 4 m long, %.2f m high" % float(slot.height_m))
	for g: Dictionary in sim.guards:
		if not bool(g.get("creature", false)): continue
		var model: Node3D = main.world.actors[str(g.id)]
		var c: Node3D = model.cutout
		check(c != null and not c.pending and c.card == null and c.model != null and c.beast != null and c.plate == null, "%s is the licensed model, moved whole, no plate" % g.id)
		check(c.get("_lod_mesh") is Mesh and c.get("_lod_near") is Mesh and (c.get("_lod_mesh") as Mesh).get_faces().size() < (c.get("_lod_near") as Mesh).get_faces().size() / 2,
			"%s has its lighter copy for far off" % g.id)
		check(not model.visible, "%s not seen before it comes" % g.id)
		check(not (main.world.cone_nodes[str(g.id)] as Node3D).visible, "%s has no sight cone" % g.id)
	var marks: Node = main.world.structures.get("creatures")
	check(marks != null and marks.get_script() == PlazaCreatures, "the square's own marks for them (plaza_creatures.gd)")

## Without the licensed models: Juan Salvo the neutral mannequin, the cascarudos plain blocks 4 m long, each with its
## plate (LICENSED ART PENDING and the name); his photo a plain plate with his name; none of them seen before they come,
## none with a sight cone.
func _pending(sim: RefCounted) -> void:
	var juan: Node3D = main.world.actors["salvo"]
	var cut: Node3D = juan.cutout
	check(cut != null and cut.pending and cut.model == null and not juan.body.visible, "Juan Salvo is the neutral stand-in, his rig unseen")
	check(_plate_words(cut) == ["LICENSED ART PENDING", "JUAN SALVO"], "…with its plate: %s" % str(_plate_words(cut)))
	check(absf(float(cut.height_m) - float(ArtPack.slot("juan_salvo").height_m)) < 0.001, "as tall as his slot says (%.3f m)" % float(cut.height_m))
	var b: Node = main.hud.portrait_buttons["salvo"]
	check(b.photo == null and str(b.photo_plate) == "JUAN SALVO", "his photo: a plain plate with his name (%s)" % str(b.photo_plate))
	main.world.update_visuals(0.05)
	check(not juan.visible, "not seen before he comes")
	for g: Dictionary in sim.guards:
		if not bool(g.get("creature", false)): continue
		var model: Node3D = main.world.actors[str(g.id)]
		var c: Node3D = model.cutout
		check(c != null and c.pending and c.model != null and str(c.model.name) == "Block" and c.plate != null, "%s is the neutral block, with its plate" % g.id)
		check(c != null and c.block_size.z > c.block_size.y and absf(maxf(c.block_size.x, c.block_size.z) - 4.0) < 0.2, "%s's block is as long as the creature (%s)" % [g.id, str(c.block_size if c != null else Vector3.ZERO)])
		check(not model.visible, "%s not seen before it comes" % g.id)
		check(not (main.world.cone_nodes[str(g.id)] as Node3D).visible, "%s has no sight cone" % g.id)
	var marks: Node = main.world.structures.get("creatures")
	check(marks != null and marks.get_script() == PlazaCreatures, "the square's own marks for them (plaza_creatures.gd)")

## Juan Salvo comes, a cascarudo comes: seen; one driven off the map is not; the ink marks the one in the square.
func _arrivals() -> void:
	var sim: RefCounted = main.sim
	var juan: Node3D = main.world.actors["salvo"]
	sim.time = float(sim.unit_by_id("salvo").arrive.at) - 0.05
	_step(0.5)
	check(juan.visible and not bool(sim.unit_by_id("salvo").away), "Juan Salvo is seen once he comes")
	main.hud.refresh()
	check(str(main.hud.portrait_buttons["salvo"].band) == "" and not main.hud.portrait_buttons["salvo"].disabled, "his photo can be tapped now")
	var c1: Dictionary = sim.guard_by_id("c1")
	sim.time = float(c1.at) - 0.05
	_step(0.5)
	var model: Node3D = main.world.actors["c1"]
	check(model.visible and str(c1.state) == "prowl", "the first cascarudo is seen once it comes")
	var marks: Node = main.world.structures.get("creatures")
	var ink: ImmediateMesh = marks.get("_ink")
	var drawn: int = (ink.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if ink.get_surface_count() > 0 else 0
	check(ink.get_surface_count() == 1 and drawn > 30, "its ring and its senses in ink on the ground (%d vertices)" % drawn)
	# head first the way it walks, 4 m long, on the ground; the lighter copy at the game's distance, the full one close up
	_put(c1, m(150.0, 60.0))
	# (nobody to go for: it only walks)
	for who: Dictionary in sim.units + sim.people(): (c1.spared as Dictionary)[str(who.id)] = float(sim.time) + 100.0
	c1.path = [m(170.0, 60.0)]
	c1.think = 5.0
	_step(0.6)
	var beast: Node3D = model.cutout
	if licensed:
		var front: Vector3 = (beast.global_basis * Vector3(0, 0, -1)).normalized()
		check(front.x > 0.9, "walking east, its head (-z as modelled) leads (%s)" % str(front))
		c1.path = []
		_step(0.4)
		var box: AABB = _bounds(beast.model)
		check(absf(box.size.x - 4.0) < 0.35 and absf(box.position.y - model.global_position.y) < 0.15, "4 m long, on the ground (%s)" % str(box))
		var zoom_was: float = main.desired_zoom
		main.zoom = 60.0
		main.desired_zoom = 60.0
		main._update_camera(0.05, true)
		_step(0.1)
		check(beast.lod_far, "far off, it is drawn from its lighter copy")
		main.zoom = 8.0
		main.desired_zoom = 8.0
		main._update_camera(0.05, true)
		_step(0.1)
		check(not beast.lod_far, "close up, from the full model")
		main.zoom = zoom_was
		main.desired_zoom = zoom_was
		main._update_camera(0.05, true)
		_step(0.1)
	else:
		# the stand-in block walks the way the creature goes, along its length, on the ground
		c1.path = []
		_step(0.4)
		check(beast.pending and absf(beast.global_position.y - model.global_position.y) < 0.15, "its stand-in block, on the ground")
	# driven off: off the map, unseen
	sim._set_state(c1, "away")
	c1.away_left = 30.0
	_step(0.2)
	check(not model.visible, "off the map, unseen")
	sim._set_state(c1, "prowl")
	_step(0.1)

## The art pack's test models in the scene: Juan Salvo dressed as the static capsule (modelled in centimetres, off its
## origin), a cascarudo as the static block whose front is +x, then Juan as the rigged post; each stands at its slot's
## height on the ground, faces the way it walks, and moves as it walks (a step and a sway, a crawl, its own "Walk").
func _test_models() -> void:
	var sim: RefCounted = main.sim
	var juan_d: Dictionary = sim.unit_by_id("salvo")
	var juan: Node3D = main.world.actors["salvo"]
	juan._dress(Operative._look("salvo", false, "", "art:test_capsule"), "salvo")
	var cut: Node3D = juan.cutout
	check(cut != null and cut.model != null and not cut.pending and cut.card == null, "a .glb in the slot loads as a model")
	_put(juan_d, m(120.0, 60.0))
	_step(0.3)
	var box: AABB = _bounds(cut.model)
	check(absf(box.size.y - 1.8) < 0.05 and absf(box.position.y - juan.global_position.y) < 0.05, "scaled to its slot's 1.8 m, standing on the ground (%s)" % str(box))
	check(Vector2(box.get_center().x - juan.global_position.x, box.get_center().z - juan.global_position.z).length() < 0.15, "centred where he stands, though modelled off its origin")
	juan_d.stance = "walk"
	sim.select("salvo")
	sim.perform("move", m(120.0, 75.0))
	var ys: Array[float] = []
	var rolls: Array[float] = []
	for i: int in range(30):
		_step(0.05)
		ys.append(cut.global_position.y - juan.global_position.y)
		rolls.append(cut.global_basis.x.normalized().y)
	check(ys.max() - ys.min() > 0.015 and rolls.max() - rolls.min() > 0.02, "a static figure steps and sways as he walks (%.3f m, %.3f)" % [ys.max() - ys.min(), rolls.max() - rolls.min()])
	var nose: Vector3 = cut.global_basis.z.normalized()
	check(nose.z > 0.9, "walking south, he faces south (%s)" % str(nose))
	# a creature as the static block (its front is +x: "forward": "+x")
	var c2d: Dictionary = sim.guard_by_id("c2")
	sim._creature_enters(c2d, true)
	var c2: Node3D = main.world.actors["c2"]
	c2._dress(Operative._look("c2", true, "creature", "art:test_crawler"), "c2")
	var crawl: Node3D = c2.cutout
	check(crawl.model != null and crawl.block_size == Vector3.ZERO, "the cascarudo's slot with a model: the model, not the block")
	_put(c2d, m(150.0, 100.0))
	c2d.think = 5.0
	_step(0.3)
	var standing: float = _bounds(crawl.model).size.y
	check(absf(standing - 2.0) < 0.08, "2 m high, as its slot says (%.2f)" % standing)
	c2d.path = [m(150.0, 125.0)]
	var heights: Array[float] = []
	for i: int in range(30):
		_step(0.05)
		heights.append(crawl.global_position.y - c2.global_position.y)
	var front: Vector3 = crawl.global_transform.basis * Vector3(1, 0, 0)
	check(front.normalized().z > 0.85, "its front (+x as modelled) leads the way it walks, south (%s)" % str(front.normalized()))
	check(heights.max() - heights.min() > 0.005, "it crawls: a low quick bob (%.3f m)" % (heights.max() - heights.min()))
	# killed: it rolls over onto its back
	sim._set_state(c2d, "dead")
	c2d.path = []
	_step(3.0)
	check(crawl.global_basis.y.normalized().y < -0.5, "killed, it rolls over onto its back (%.2f)" % crawl.global_basis.y.normalized().y)
	# Juan Salvo as the rigged post: its own animations
	juan._dress(Operative._look("salvo", false, "", "art:test_rigged"), "salvo")
	var rig: Node3D = juan.cutout
	check(rig.model != null and rig.get("_anim") != null, "a rigged model keeps its skeleton and animations")
	sim.perform("move", m(140.0, 75.0))
	_step(0.8)
	check(str(rig.playing) == "Walk", "walking, it plays its own \"Walk\" (%s)" % str(rig.playing))
	var anim: AnimationPlayer = rig.get("_anim")
	check(anim.is_playing() and anim.get_animation("Walk").loop_mode != Animation.LOOP_NONE, "looped")
	juan_d.path = []
	juan_d.order = {}
	_step(1.5)
	check(str(rig.playing) == "Idle", "standing still, its \"Idle\" (%s)" % str(rig.playing))

static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and str(n.name) != "Hull":
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box
