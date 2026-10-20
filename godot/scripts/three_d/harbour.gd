extends "res://scripts/three_d/structures.gd"
## Everything standing in the Bordeaux harbour (Operation Cockle): the blockade runner at the quay, the U-boat
## bunker, the portal cranes, the rail yard and its wagons, the warehouses, the building site in the unfinished
## pens, the cargo, the lamps and the searchlight, the canoe at the river steps, and the charges as they are set.
##
## It stands in for the outpost's structures module (it extends it, so the tripwires, the cuttable span of the
## wire and the rules props behave exactly the same) and keeps the same interface for world.gd: build(),
## update(), on_sim_event(), trap_yaw(), gate (none here), buildings, door_point, generator_point.
## The geometry itself comes from four builders: harbour_ship.gd, harbour_bunker.gd, harbour_quay.gd and
## harbour_yard.gd. Each commits its objects separately and small, so no mesh is lit by more lamps than the
## renderer allows per object.

const Ship = preload("res://scripts/three_d/harbour_ship.gd")
const Bunker = preload("res://scripts/three_d/harbour_bunker.gd")
const Quay = preload("res://scripts/three_d/harbour_quay.gd")
const Yard = preload("res://scripts/three_d/harbour_yard.gd")
const BeamShader := preload("res://shaders/harbour_beam.gdshader")
const MassShader := preload("res://shaders/harbour_mass.gdshader")
const TEX_H := "res://assets/tex/harbour/"
const WATER_Y := -2.3
## All lamp energies are given as relative strengths; this turns them into the light's energy.
const LAMP_GAIN := 2.8

## Lamps: {light: OmniLight3D, halo: MeshInstance3D, at: Vector3, color: Color, energy: float, powered: bool, streak}.
var lamps: Array[Dictionary] = []
## Lettering: stencilled numbers and marks, painted signs and the ship's name.
const STENCIL_FONT = preload("res://assets/fonts/BigShouldersStencilDisplay-wght.ttf")
const SIGN_FONT = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
var stencil_font: FontVariation = _heavy(STENCIL_FONT, 780)

static func _heavy(base: Font, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f
## The searchlight on the bunker roof follows the guard of that kind: its drum, its light and its beam.
var searchlight_rig: Node3D
var searchlight_light: SpotLight3D
var searchlight_beam: MeshInstance3D
var searchlight_glass: MeshInstance3D
var _beam_material: ShaderMaterial
var _searchlight_id: String = ""
## Shared emissive materials: lamp bulbs on the harbour supply / on the ship's own dynamo.
var bulb_material: StandardMaterial3D
var ship_bulb_material: StandardMaterial3D
var halo_material: StandardMaterial3D
## Props of the charges, by site id: hidden until the site is planted.
var charge_props: Dictionary = {}
## The blockade runner (everything of hers, under one node: the closing scene makes her list).
var ship: Node3D
## The U-boats by id (data harbour.uboats) and where each one lies until the closing scene sinks her.
var uboats: Dictionary = {}
var uboat_rest: Dictionary = {}
## Every ship at the quay by name (TANNENFELS, DRESDEN, Sperrbrecher), and where each lies when all is calm.
var ships: Dictionary = {}
var ship_rest: Dictionary = {}
## The deck sentries' torches, by guard id: {rig, light, beam}. They run off batteries, not the harbour supply.
var torches: Dictionary = {}
## Floating things: the canoe, and anything else that rides the tide.
var canoe: Node3D
var _canoe_at := Vector3.ZERO
## Red warning lamps on the crane tops and the like: blink regardless of the power (they run off batteries).
var beacons: Array[Node3D] = []
var _power: float = 1.0
## Set while the closing scene plays: the finale moves the canoe and the ship and owns the lamps.
var finale_running: bool = false
var _was_cut: bool = false
var _flicker: float = 0.0
var _h: Dictionary = {}
var _fixed_seed: int = 19421211

func build() -> void:
	rng.seed = _fixed_seed
	_h = sim.data.get("harbour", {})
	materials = Kit.make_materials()
	_harbour_materials()
	_props = Props.new(_fixed_seed + 1)
	_rules = Rules.new(_props, _fixed_seed + 2)
	var site := Site.new(_props, _fixed_seed + 3)
	var specs: Array = _h.get("ships", [])
	if specs.is_empty(): specs = [_h.get("ship", {})]
	for i: int in range(specs.size()):
		var spec: Dictionary = specs[i]
		var built: Node3D = Ship.new(self, _fixed_seed + 10 + i * 100).build(spec)
		var key: String = str(spec.get("name", "")) if str(spec.get("name", "")) != "" else str(spec.get("style", "ship%d" % i)).to_upper()
		ships[key] = built
		ship_rest[key] = built.transform
		if i == 0: ship = built
	_build_torches()
	Bunker.new(self, _fixed_seed + 20).build()
	Quay.new(self, site, _fixed_seed + 30).build()
	Yard.new(self, site, _fixed_seed + 40).build()
	_build_charges()
	_build_traps()
	_sync_rules(1.0)
	_sync_power(1.0, true)

# ---------------------------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------------------------
func _harbour_materials() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_texture = load(TEX_H + "hull_a.png")
	hull.vertex_color_use_as_albedo = true
	hull.normal_enabled = true
	hull.normal_texture = load(TEX_H + "hull_n.png")
	hull.roughness_texture = hull.albedo_texture
	hull.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	hull.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	hull.metallic_specular = 0.45
	materials["hull"] = hull
	var granite := StandardMaterial3D.new()
	granite.albedo_texture = load(TEX_H + "setts_a.png")
	granite.vertex_color_use_as_albedo = true
	granite.normal_enabled = true
	granite.normal_texture = load(TEX_H + "setts_n.png")
	granite.uv1_scale = Vector3(0.42, 0.42, 1.0)
	granite.roughness = 0.7
	granite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials["granite"] = granite
	var shingle := StandardMaterial3D.new()
	shingle.albedo_texture = load("res://assets/tex/nature/shingle_albedo.png")
	shingle.vertex_color_use_as_albedo = true
	shingle.roughness = 0.95
	shingle.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials["shingle"] = shingle
	# The bunker's mass concrete: the board-formed texture with leaching streaks laid over it in world space.
	var mass := ShaderMaterial.new()
	mass.shader = MassShader
	mass.set_shader_parameter("albedo_tex", load(Kit.TEX_DIR + "concrete_a.png"))
	mass.set_shader_parameter("normal_tex", load(Kit.TEX_DIR + "concrete_n.png"))
	mass.set_shader_parameter("streak_tex", load(TEX_H + "streaks.png"))
	materials["mass"] = mass
	bulb_material = _emissive(Color(1.0, 0.78, 0.5), 6.0)
	ship_bulb_material = _emissive(Color(1.0, 0.82, 0.58), 4.0)
	materials["bulb"] = bulb_material
	materials["shipbulb"] = ship_bulb_material
	materials["beacon"] = _emissive(Color(1.0, 0.16, 0.08), 5.0)
	materials["window"] = _emissive(Color(1.0, 0.72, 0.42), 1.6)
	halo_material = StandardMaterial3D.new()
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
	halo_material.albedo_texture = texture
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.billboard_keep_scale = true
	halo_material.vertex_color_use_as_albedo = true
	halo_material.no_depth_test = false
	halo_material.render_priority = 6

func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m

## Commits a kit as one object (and counts its triangles). fade: the object thins out to a dither whenever
## somebody stands behind it (from the camera's point of view): the bunker, the ship's upper works, cranes,
## sheds and wagons would otherwise hide the people the player is commanding.
func commit(kit: Kit, parent: Node3D, node_name: String, shadows: bool = true, fade: bool = false) -> MeshInstance3D:
	var m := _commit(kit, parent, node_name, shadows)
	if fade and m != null: _make_fader(m)
	return m

## Objects that fade: {node, aabb (world), mats, alpha}.
var faders: Array[Dictionary] = []
## In the closing scene: what must not be hidden from the camera (metres), in place of the people. The girders over
## the pens fade off the U-boats while the camera is on them.
var fade_focus: Array[Vector3] = []
## False: only the operatives make things fade (at Vemork the guards keep to the yard behind the big buildings, and
## the player does not need the plant thinning out every time one walks past).
var fade_for_guards: bool = true
## Places that are always kept in view as if somebody stood there (Vemork's hall of cells, cut away for the camera).
var fade_points: Array[Vector3] = []
var _fade_clock: float = 0.0
const FADED := 0.22
## Comic ink (ink.gd) draws from what is solid on screen: a dithered, half-there building would come out as a mess of
## ink, so while it is on a building in the way is taken out altogether (set_ink).
var _ink_cutaway: bool = false

func set_ink(on: bool) -> void:
	_ink_cutaway = on
	_fade_clock = 1.0

func _make_fader(m: MeshInstance3D) -> void:
	var mats: Array[Material] = []
	for i: int in range(m.mesh.get_surface_count()):
		var source: Material = m.mesh.surface_get_material(i)
		if source == null: continue
		var copy: Material = source.duplicate()
		if copy is StandardMaterial3D:
			var sm := copy as StandardMaterial3D
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
				sm.alpha_hash_scale = 1.0
		m.set_surface_override_material(i, copy)
		mats.append(copy)
	faders.append({"node": m, "aabb": m.global_transform * m.get_aabb(), "mats": mats, "alpha": 1.0, "want": 1.0})

## Ten times a second: which faders stand between the camera and a person (an operative, or a guard on his
## feet); every frame: ease their opacity toward what is wanted.
func _sync_faders(dt: float) -> void:
	if faders.is_empty(): return
	_fade_clock += dt
	if _fade_clock >= 0.1:
		_fade_clock = 0.0
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera != null:
			var back: Vector3 = camera.global_transform.basis.z
			var people: Array[Vector3] = []
			if finale_running:
				people = fade_focus
			else:
				for unit: Dictionary in sim.units:
					if bool(unit.alive): people.append(Vector3(float(unit.x) / 32.0, 0.9, float(unit.y) / 32.0))
				people.append_array(fade_points)
				for guard: Dictionary in sim.guards:
					if not fade_for_guards: break
					if guard.state in ["dead", "bound"] or str(guard.carried_by) != "": continue
					people.append(Vector3(float(guard.x) / 32.0, float(guard.elevation) + 0.9, float(guard.y) / 32.0))
			for fader: Dictionary in faders:
				var box: AABB = fader.aabb
				var hidden := false
				# the tower crane coming down stays solid
				if finale_running and str((fader.node as Node).name) == "TowerCrane":
					fader.want = 1.0
					continue
				for p: Vector3 in people:
					if box.has_point(p): continue
					if _ray_hits(p, back, box):
						hidden = true
						break
				fader.want = (0.0 if _ink_cutaway else FADED) if hidden else 1.0
			if _ink_cutaway:
				# in ink a building goes whole: its windows and shutters (a fader of their own) with its walls (the faders
				# of one small group node: La Boca's blocks)
				var gone: Dictionary = {}
				for fader: Dictionary in faders:
					var group: Node = (fader.node as Node).get_parent()
					if float(fader.want) < 1.0 and group != self and group.get_child_count() <= 4: gone[group] = true
				for fader: Dictionary in faders:
					if gone.has((fader.node as Node).get_parent()): fader.want = 0.0
	for fader: Dictionary in faders:
		var a: float = float(fader.alpha)
		var want: float = float(fader.want)
		if absf(a - want) < 0.001: continue
		a = move_toward(a, want, dt * 3.5)
		fader.alpha = a
		for mat: Material in fader.mats:
			if mat is StandardMaterial3D: (mat as StandardMaterial3D).albedo_color.a = a
			elif mat is ShaderMaterial: (mat as ShaderMaterial).set_shader_parameter("fade", a)

## Slab test: does the ray from p along dir pass through the box?
static func _ray_hits(p: Vector3, dir: Vector3, box: AABB) -> bool:
	var t0 := 0.0
	var t1 := 1e9
	for axis: int in range(3):
		var lo: float = box.position[axis]
		var hi: float = box.end[axis]
		var d: float = dir[axis]
		if absf(d) < 1e-6:
			if p[axis] < lo or p[axis] > hi: return false
			continue
		var a := (lo - p[axis]) / d
		var b := (hi - p[axis]) / d
		if a > b:
			var t := a
			a = b
			b = t
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1: return false
	return t1 > 0.0

## The footprints (metres, x and z) of the mission's obstacles of one kind, or the one with this id.
func footprints(kind: String, id: String = "") -> Array[Rect2]:
	var out: Array[Rect2] = []
	for item: Dictionary in sim.data.get("obstacles", []):
		if (id != "" and str(item.get("id", "")) == id) or (id == "" and str(item.get("kind", "")) == kind):
			var r: Rect2 = sim.rect_of(item)
			out.append(Rect2(r.position / 32.0, r.size / 32.0))
	return out

## A node of its own under the harbour (for objects that are moved, hidden or cut away as a whole).
func node(node_name: String, at: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = at
	n.rotation.y = yaw
	add_child(n)
	return n

# ---------------------------------------------------------------------------------------------------------------
# Lamps
# ---------------------------------------------------------------------------------------------------------------
## A lamp: a real light (no shadow), a halo and its bulb in the lamp list the water and the mist reflect.
## powered lamps die with the harbour supply. Returns the light.
func add_lamp(at: Vector3, col: Color, energy: float, reach: float, powered: bool = true, halo_size: float = 0.9, streak: float = 1.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	energy *= LAMP_GAIN
	reach *= 1.25
	light.name = "Lamp%d" % lamps.size()
	light.position = at
	light.light_color = col
	light.light_energy = energy
	light.light_specular = 1.0
	light.omni_range = reach
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	add_child(light)
	var halo := MeshInstance3D.new()
	halo.name = "Halo%d" % lamps.size()
	var quad := QuadMesh.new()
	quad.size = Vector2(halo_size, halo_size)
	halo.mesh = quad
	var m: StandardMaterial3D = halo_material.duplicate()
	m.albedo_color = Color(col.r, col.g, col.b, 0.85)
	halo.material_override = m
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = at
	add_child(halo)
	lamps.append({"light": light, "halo": halo, "at": at, "color": col, "energy": energy, "powered": powered, "streak": streak})
	return light

## The harbour's lamps for the water and the mist: [position, colour, strength, streak length].
func lamp_list() -> Array:
	var out: Array = []
	for lamp: Dictionary in lamps:
		out.append([lamp.at, lamp.color, clampf(float(lamp.energy) / (3.0 * LAMP_GAIN), 0.2, 1.6), float(lamp.streak), bool(lamp.powered)])
	return out

## Slow smoke from a chimney or a funnel: a handful of soft puffs rising and drifting off with the wind.
var _smokes: Array[Dictionary] = []
func add_smoke(at: Vector3, count: int = 6, size: float = 1.2) -> void:
	var puffs: Array[MeshInstance3D] = []
	for i: int in range(count):
		var puff := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		puff.mesh = quad
		var m := _sprite_material(Color(0.32, 0.33, 0.36, 0.0), false)
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		puffs.append(puff)
	_smokes.append({"at": at, "puffs": puffs, "size": size})

func _sync_smoke() -> void:
	for smoke: Dictionary in _smokes:
		var puffs: Array[MeshInstance3D] = smoke.puffs
		for i: int in range(puffs.size()):
			var t := fposmod(_clock * 0.06 + float(i) / float(puffs.size()), 1.0)
			var puff := puffs[i]
			puff.position = (smoke.at as Vector3) + Vector3(1.8 * t + 0.25 * sin(_clock * 0.3 + float(i)), 3.2 * t, -1.2 * t)
			var grow := float(smoke.size) * (0.6 + 2.2 * t)
			puff.scale = Vector3(grow, grow, grow)
			(puff.material_override as StandardMaterial3D).albedo_color.a = 0.32 * sin(PI * minf(1.0, t * 1.1)) * (1.0 - t * 0.6)

func add_beacon(at: Vector3) -> void:
	var b := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 8
	sphere.rings = 4
	b.mesh = sphere
	b.material_override = materials["beacon"]
	b.position = at
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	halo.mesh = quad
	var m: StandardMaterial3D = halo_material.duplicate()
	m.albedo_color = Color(1.0, 0.2, 0.1, 0.9)
	halo.material_override = m
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(halo)
	beacons.append(b)

## The searchlight drum (built by the bunker at `at`, facing local +X), its spot and the beam through the mist.
func set_searchlight(rig: Node3D, lens: Vector3, glass: MeshInstance3D) -> void:
	searchlight_rig = rig
	searchlight_glass = glass
	for guard: Dictionary in sim.data.guards:
		if str(guard.get("kind", "")) == "searchlight": _searchlight_id = str(guard.id)
	searchlight_light = SpotLight3D.new()
	searchlight_light.name = "Searchlight"
	searchlight_light.position = lens
	searchlight_light.light_color = Color(0.86, 0.92, 1.0)
	searchlight_light.light_energy = 34.0
	searchlight_light.light_specular = 1.0
	searchlight_light.spot_range = 30.0
	searchlight_light.spot_angle = 8.5
	searchlight_light.spot_angle_attenuation = 0.6
	searchlight_light.spot_attenuation = 0.6
	searchlight_light.shadow_enabled = true
	searchlight_light.shadow_bias = 0.05
	# the light points along local -Z: turn it to the drum's +X
	searchlight_light.rotation.y = -PI * 0.5
	rig.get_node("Tilt").add_child(searchlight_light)
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BeamShader
	_beam_material.render_priority = 7
	var cone := CylinderMesh.new()
	cone.top_radius = 2.4
	cone.bottom_radius = 0.24
	cone.height = 18.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	searchlight_beam = MeshInstance3D.new()
	searchlight_beam.name = "Beam"
	searchlight_beam.mesh = cone
	searchlight_beam.material_override = _beam_material
	searchlight_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# cylinder axis is Y: lay it along +X, the narrow end at the lens
	searchlight_beam.transform = Transform3D(Basis(Vector3.BACK, -PI * 0.5), lens + Vector3(9.0, 0, 0))
	rig.get_node("Tilt").add_child(searchlight_beam)

# ---------------------------------------------------------------------------------------------------------------
# Charges
# ---------------------------------------------------------------------------------------------------------------
func _build_charges() -> void:
	for site: Dictionary in sim.charge_sites():
		var at := Vector3(float(site.get("tx", site.x)) / 32.0, 0.0, float(site.get("ty", site.y)) / 32.0)
		var from := Vector3(float(site.x) / 32.0, 0.0, float(site.y) / 32.0)
		var facing := Vector2(at.x - from.x, at.z - from.z)
		var yaw := atan2(-facing.y, facing.x)
		var prop := node("Charge_" + str(site.id), at, yaw)
		var kit := Kit.new()
		if str(site.get("prop", site.get("kind", ""))) == "limpet":
			_limpet(kit)
		else:
			_satchel(kit)
		commit(kit, prop, "Mesh", true)
		prop.visible = false
		charge_props[str(site.id)] = prop

## A limpet on the hull just above the waterline (local +X = into the hull), its placing rod left leaning.
func _limpet(k: Kit) -> void:
	k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.08, WATER_Y + 0.28, 0)))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.17, 0.05), Vector2(0.13, 0.11), Vector2(0.05, 0.14), Vector2(0.0, 0.145)]), 12, Color(0.2, 0.22, 0.2), Color(0.32, 0.34, 0.3))
	k.pop()
	k.beam("steel", Vector3(-0.25, WATER_Y + 0.25, 0.1), Vector3(-0.62, 0.05, 0.25), 0.02, 0.02, Color(0.28, 0.25, 0.2), Color(0.35, 0.32, 0.26))

## A canvas-wrapped demolition charge packed against the pier foot (local +X = into the pier), detonating cord
## coiled beside it and the time pencil sticking out of the primer.
func _satchel(k: Kit) -> void:
	k.box("canvas", Vector3(-0.2, 0.17, 0), Vector3(0.36, 0.34, 0.5), Color(0.34, 0.36, 0.28), Color(0.46, 0.48, 0.38))
	k.box("canvas", Vector3(-0.22, 0.42, 0.05), Vector3(0.3, 0.16, 0.36), Color(0.34, 0.36, 0.28), Color(0.5, 0.52, 0.4))
	for z: float in [-0.16, 0.16]:
		k.box("rubber", Vector3(-0.2, 0.25, z), Vector3(0.37, 0.03, 0.04), Color(0.25, 0.2, 0.14), Color(0.3, 0.24, 0.17))
	k.beam("steel", Vector3(-0.32, 0.5, 0.05), Vector3(-0.4, 0.64, 0.08), 0.012, 0.012, Color(0.6, 0.5, 0.3), Color(0.75, 0.62, 0.36))
	_props.rope_coil(k, Vector3(-0.55, 0.0, 0.2), 0.13, 3)

# ---------------------------------------------------------------------------------------------------------------
# Per frame
# ---------------------------------------------------------------------------------------------------------------
func update(dt: float, paused: bool) -> void:
	_sync_rules(dt)
	if not finale_running:
		for id: String in charge_props:
			(charge_props[id] as Node3D).visible = sim.planted.has(id)
	_sync_power(dt, false)
	_sync_searchlight(dt)
	_sync_torches(dt)
	if not finale_running: _sync_faders(dt)
	_clock += 0.0 if paused else dt
	_sync_smoke()
	var blink: bool = fposmod(_clock * 0.8, 1.0) < 0.5
	for b: Node3D in beacons: b.visible = blink
	if canoe != null and not paused and not finale_running:
		canoe.position.y = _canoe_at.y + sin(_clock * 1.1) * 0.03
		canoe.rotation.z = sin(_clock * 0.8 + 0.5) * 0.03
		canoe.rotation.x = sin(_clock * 0.6) * 0.012

## The harbour supply: lamps, bulbs, the searchlight. Cutting it makes them stutter and die; a checkpoint load
## or a restart brings them back at once. In the closing scene (daylight) everything is off.
func set_finale(on: bool) -> void:
	finale_running = on
	fade_focus.clear()
	if not on:
		for key: String in ships: (ships[key] as Node3D).transform = ship_rest[key]
		for key: String in uboats:
			var boat: Node3D = uboats[key]
			boat.transform = uboat_rest[key]
			# her two pieces back together on their pivots
			for piece: Node in boat.get_children():
				if piece.has_meta("pivot"): (piece as Node3D).transform = Transform3D(Basis.IDENTITY, piece.get_meta("pivot"))
		if canoe != null:
			canoe.position = _canoe_at
			canoe.rotation = Vector3.ZERO
			canoe.visible = true
		for id: String in charge_props: (charge_props[id] as Node3D).visible = sim.planted.has(id)
	_was_cut = not _was_cut      # force a re-sync of the lamps
	_sync_power(1.0, true)

func _sync_power(dt: float, instant: bool) -> void:
	var cut: bool = bool(sim.radio_cut) or finale_running
	if cut != _was_cut:
		_was_cut = cut
		_flicker = 0.0 if (instant or not cut) else 0.9
		if not cut: _power = 1.0
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
	if searchlight_light != null:
		searchlight_light.light_energy = 34.0 * level
		searchlight_light.visible = level > 0.01
		searchlight_beam.visible = level > 0.01
		_beam_material.set_shader_parameter("strength", level)

func _sync_searchlight(dt: float) -> void:
	if searchlight_rig == null or _searchlight_id == "": return
	var guard: Dictionary = sim.guard_by_id(_searchlight_id)
	if guard.is_empty(): return
	var want: float = -float(guard.angle)
	searchlight_rig.rotation.y = lerp_angle(searchlight_rig.rotation.y, want, minf(1.0, dt * 12.0))
	var down: bool = guard.state in sim.DOWN_STATES
	if down and searchlight_light.visible:
		searchlight_light.visible = false
		searchlight_beam.visible = false
	elif not down and _power > 0.01 and not searchlight_light.visible:
		searchlight_light.visible = true
		searchlight_beam.visible = true

# ---------------------------------------------------------------------------------------------------------------
# Torches
# ---------------------------------------------------------------------------------------------------------------
## A hand torch for each guard of kind "torch": a narrow warm beam from his hand height, swung with his gaze,
## and a faint shaft of it through the river mist. Battery light: the main switch does nothing to it.
func _build_torches() -> void:
	for guard: Dictionary in sim.data.guards:
		if str(guard.get("kind", "")) != "torch": continue
		var post: Array = guard.get("post", guard.route[0])
		var rig := node("Torch_" + str(guard.id), Vector3(float(post[0]) / 32.0, float(guard.get("elevation", 0.0)) + 1.35, float(post[1]) / 32.0))
		var tilt := Node3D.new()
		tilt.name = "Tilt"
		# aimed down at the quay edge, about twelve metres off
		tilt.rotation.z = -0.36
		rig.add_child(tilt)
		var light := SpotLight3D.new()
		light.name = "Light"
		light.light_color = Color(1.0, 0.86, 0.62)
		light.light_energy = 9.0
		light.light_specular = 0.6
		light.spot_range = 18.0
		light.spot_angle = 7.0
		light.spot_angle_attenuation = 0.8
		light.spot_attenuation = 0.9
		light.shadow_enabled = false
		light.rotation.y = -PI * 0.5
		tilt.add_child(light)
		var mat := ShaderMaterial.new()
		mat.shader = BeamShader
		mat.render_priority = 7
		mat.set_shader_parameter("strength", 0.18)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.9
		cone.bottom_radius = 0.06
		cone.height = 12.0
		cone.radial_segments = 12
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		beam.mesh = cone
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.transform = Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(6.0, 0, 0))
		tilt.add_child(beam)
		torches[str(guard.id)] = {"rig": rig, "light": light, "beam": beam}

func _sync_torches(dt: float) -> void:
	for id: String in torches:
		var t: Dictionary = torches[id]
		var guard: Dictionary = sim.guard_by_id(id)
		var on: bool = not guard.is_empty() and not (guard.state in sim.DOWN_STATES) and not finale_running
		(t.light as Node3D).visible = on
		(t.beam as Node3D).visible = on
		if not on: continue
		var rig: Node3D = t.rig
		rig.rotation.y = lerp_angle(rig.rotation.y, -float(guard.angle), minf(1.0, dt * 14.0))

## World.gd passes every simulation event on; the harbour adds nothing of its own yet beyond the outpost's.
func on_sim_event(event: Dictionary) -> void:
	super.on_sim_event(event)
