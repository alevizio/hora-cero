extends SceneTree
## Dev tool (not shipped): renders the game's icons as 3D objects, modelled with the structures kit and lit like
## the game's overcast day, on a transparent background. tools/icons3d/finish.py turns the renders into the HUD
## sizes, adds the outline and makes the comparison sheets.
##   cd godot && xvfb-run -a -s "-screen 0 1280x1024x24" <godot 4.7> --path . --rendering-driver opengl3 \
##     --script ../tools/icons3d/studio.gd -- <out_dir> [name ...]
## Objects are modelled about three times life size so the kit's tiling textures (200 px a metre) keep their grain
## at icon scale. Each icon is framed automatically from its bounding box.
const Kit := preload("res://scripts/three_d/structures_kit.gd")

const SIZE := 1024
## Modelled here; objects_*.gd next to this file add more (each lists its own in NAMES).
const OWN := ["knife", "pistol", "radio", "limpet", "cutters", "rope", "marker_objective", "app_beret"]
const BADGES := ["ghost", "clean_hands", "not_a_shot", "saboteur", "swift"]
const MODULES := ["objects_a.gd", "objects_b.gd", "objects_c.gd"]

var out_dir := "/tmp/icons3d"
var vp: SubViewport
var cam: Camera3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var holder: Node3D
var mats: Dictionary = {}
var modules: Array = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		out_dir = args[0]
	var here: String = ProjectSettings.globalize_path("res://").path_join("../tools/icons3d").simplify_path()
	for file: String in MODULES:
		var path := here.path_join(file)
		if FileAccess.file_exists(path):
			modules.append(load(path).new())
	var names: Array = Array(args.slice(1))
	if names.is_empty():
		names = OWN.duplicate()
		for m: Object in modules:
			names.append_array(m.get("NAMES"))
		for b: String in BADGES:
			names.append("badge_" + b)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_stage()
	for name: String in names:
		await _render(name)
	quit()

# ---------------------------------------------------------------------------------------------------------------
# Stage: the day's sky ambient and tonemap, a key light from the upper left, a cool fill and a rim
# ---------------------------------------------------------------------------------------------------------------
func _stage() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.66, 0.71, 0.77)
	sky_material.sky_horizon_color = Color(0.80, 0.81, 0.79)
	sky_material.sky_curve = 0.25
	sky_material.ground_bottom_color = Color(0.20, 0.21, 0.17)
	sky_material.ground_horizon_color = Color(0.52, 0.53, 0.48)
	sky_material.ground_curve = 0.12
	sky_material.sun_angle_max = 0.0
	sky_material.energy_multiplier = 0.75
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	settings.sky = sky
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_sky_contribution = 1.0
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 1.08
	settings.tonemap_white = 1.6
	env.environment = settings
	vp.add_child(env)
	key_light = DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.955, 0.86)
	key_light.light_energy = 1.05
	key_light.light_specular = 0.8
	key_light.shadow_enabled = true
	key_light.shadow_opacity = 0.85
	key_light.shadow_blur = 1.4
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key_light.directional_shadow_max_distance = 12.0
	key_light.shadow_bias = 0.02
	key_light.shadow_normal_bias = 0.6
	vp.add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(0.78, 0.85, 0.95)
	fill_light.light_energy = 0.28
	fill_light.light_specular = 0.2
	vp.add_child(fill_light)
	rim_light = DirectionalLight3D.new()
	rim_light.light_color = Color(1.0, 0.93, 0.8)
	rim_light.light_energy = 0.55
	rim_light.light_specular = 1.0
	vp.add_child(rim_light)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 60.0
	vp.add_child(cam)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	mats = Kit.make_materials()
	mats["blade"] = _metal(Color(0.80, 0.82, 0.83), 0.92, 0.3)
	mats["blued"] = _metal(Color(0.32, 0.34, 0.37), 0.75, 0.42)
	mats["brass"] = _metal(Color(0.80, 0.62, 0.32), 0.9, 0.36)
	mats["paint"] = _paint()

## Metal: the kit's steel texture for wear, metallic and rougher in the scratches.
func _metal(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(Kit.TEX_DIR + "steel_a.png")
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.metallic = metallic
	m.roughness = roughness
	m.normal_enabled = true
	m.normal_texture = load(Kit.TEX_DIR + "steel_n.png")
	m.normal_scale = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Painted sheet metal (the limpet, the radio case): the steel texture under a satin coat.
func _paint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(Kit.TEX_DIR + "steel_a.png")
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.1
	m.roughness = 0.55
	m.normal_enabled = true
	m.normal_texture = load(Kit.TEX_DIR + "steel_n.png")
	m.normal_scale = 0.7
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ---------------------------------------------------------------------------------------------------------------
# Render one icon
# ---------------------------------------------------------------------------------------------------------------
func _render(name: String) -> void:
	if holder != null:
		holder.queue_free()
	holder = Node3D.new()
	vp.add_child(holder)
	var view: Dictionary = {}
	if name.begins_with("badge_"):
		view = _badge(holder, name.substr(6))
	elif has_method("_" + name):
		view = call("_" + name, holder)
	else:
		for m: Object in modules:
			if m.has_method("_" + name):
				view = m.call("_" + name, self, holder)
				break
	if view.is_empty():
		push_error("no icon called " + name)
		return
	var pitch: float = deg_to_rad(float(view.get("pitch", 38.0)))
	var yaw: float = deg_to_rad(float(view.get("yaw", 0.0)))
	var margin: float = float(view.get("margin", 0.08))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	# Fit: the object's bounding box seen from the camera, centred, with a margin all round.
	var box := AABB()
	var first := true
	for child: Node in holder.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var inv := basis.inverse()
	for i: int in range(8):
		var p: Vector3 = inv * box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var centre2 := (lo + hi) * 0.5
	var extent := maxf(hi.x - lo.x, hi.y - lo.y)
	cam.size = extent * (1.0 + 2.0 * margin)
	cam.transform = Transform3D(basis, basis * Vector3(centre2.x, centre2.y, 0.0) + basis.z * 20.0)
	# Key from the upper left and a little in front, fill from the lower right, rim from behind.
	key_light.transform = Transform3D(_aim(basis, Vector3(0.55, -0.75, -0.45)), Vector3.ZERO)
	fill_light.transform = Transform3D(_aim(basis, Vector3(-0.6, 0.2, -0.6)), Vector3.ZERO)
	rim_light.transform = Transform3D(_aim(basis, Vector3(-0.3, -0.45, 0.85)), Vector3.ZERO)
	for i: int in range(6):
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

## A light shining along `dir` given in camera space (x right, y up, z toward the viewer).
func _aim(cam_basis: Basis, dir: Vector3) -> Basis:
	var d := (cam_basis * dir).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	return Basis.looking_at(d, up)

func _commit(k: Kit, parent: Node3D) -> void:
	k.commit(parent, mats, "Mesh", true)

# ---------------------------------------------------------------------------------------------------------------
# The objects. Each lies on an imaginary table along the X axis (pointing up-right in the icon) unless it says.
# ---------------------------------------------------------------------------------------------------------------

## Wren's fighting knife: a double-edged blade with a raised spine, an oval guard, a ribbed grip and a pommel.
func _knife(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-38.0)), Vector3.ZERO))
	_blade(k, Vector3(0.0, 0.0, 0.0), 0.92, 0.1, 0.022)
	# guard: a flattened oval bar across the blade root
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.015, 0.0, 0.0)))
	k.lathe("blued", Vector3(0, -0.13, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.022, 0.006), Vector2(0.026, 0.13), Vector2(0.022, 0.254), Vector2(0.0, 0.26)]), 14, Color(0.55, 0.55, 0.55), Color(0.85, 0.85, 0.85))
	k.pop()
	_grip(k, Vector3(-0.03, 0, 0), 0.4, 0.05)
	k.pop()
	_commit(k, parent)
	return {"pitch": 40.0, "yaw": 0.0}

func _blade(k: Kit, root: Vector3, length: float, width: float, thick: float) -> void:
	# blade along +X from root: flat diamond section, the edges converge on the tip
	var steps := 12
	var hw := width * 0.5
	for side: float in [1.0, -1.0]:
		for face: float in [1.0, -1.0]:
			for i: int in range(steps):
				var t0 := float(i) / float(steps)
				var t1 := float(i + 1) / float(steps)
				var w0 := hw * _blade_taper(t0)
				var w1 := hw * _blade_taper(t1)
				var h0 := thick * 0.5 * _blade_taper(t0)
				var h1 := thick * 0.5 * _blade_taper(t1)
				var x0 := root.x + length * t0
				var x1 := root.x + length * t1
				var edge0 := Vector3(x0, 0.0, side * w0)
				var edge1 := Vector3(x1, 0.0, side * w1)
				var ridge0 := Vector3(x0, face * h0, 0.0)
				var ridge1 := Vector3(x1, face * h1, 0.0)
				var c_edge := Color(1.0, 1.0, 1.0)
				var c_ridge := Color(0.82, 0.84, 0.86)
				# wind so the face looks outward (up for face = 1, down for -1; +Z side vs -Z side)
				if side * face > 0.0:
					k.quad4("blade", ridge0, ridge1, edge1, edge0, Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 0.1), Vector2(t0, 0.1), c_ridge, c_ridge, c_edge, c_edge)
				else:
					k.quad4("blade", edge0, edge1, ridge1, ridge0, Vector2(t0, 0.1), Vector2(t1, 0.1), Vector2(t1, 0), Vector2(t0, 0), c_edge, c_edge, c_ridge, c_ridge)

func _blade_taper(t: float) -> float:
	# full width for the first fifth, then a long straight taper to the point
	return 1.0 if t < 0.2 else maxf(0.0, 1.0 - (t - 0.2) / 0.8)

## A ribbed grip along -X from `at`, ending in a pommel.
func _grip(k: Kit, at: Vector3, length: float, radius: float) -> void:
	k.push(Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), at))
	var profile := PackedVector2Array()
	var rings := 9
	for i: int in range(rings * 2 + 1):
		var t := float(i) / float(rings * 2)
		var swell := 0.82 + 0.3 * sin(t * PI)
		var rib := 1.0 if i % 2 == 0 else 0.86
		profile.append(Vector2(radius * swell * rib, t * length))
	profile.append(Vector2(radius * 0.6, length + 0.012))
	profile.append(Vector2(radius * 1.05, length + 0.03))
	profile.append(Vector2(radius * 1.02, length + 0.07))
	profile.append(Vector2(radius * 0.5, length + 0.09))
	profile.append(Vector2(0.0, length + 0.095))
	k.lathe("brass", Vector3.ZERO, profile, 16, Color(0.5, 0.42, 0.32), Color(0.78, 0.7, 0.6))
	k.pop()

## The silenced pistol: a long tube with the grip hanging under its rear third and a small trigger guard.
func _pistol(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	# on its side with the grip toward the viewer, the muzzle up and to the right (as the revolver lies)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(14.0)) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	# tube along +X (lathe axis turned onto X)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.35, 0, 0)))
	k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.075, 0.005), Vector2(0.08, 0.04), Vector2(0.08, 1.02), Vector2(0.072, 1.06), Vector2(0.03, 1.07), Vector2(0.0, 1.07)]), 18, Color(0.6, 0.6, 0.62), Color(0.9, 0.9, 0.92))
	for y: float in [0.24, 0.62, 0.98]:
		k.lathe("blued", Vector3(0, y, 0), PackedVector2Array([Vector2(0.081, 0.0), Vector2(0.086, 0.01), Vector2(0.086, 0.03), Vector2(0.081, 0.04)]), 18, Color(0.45, 0.45, 0.48), Color(0.6, 0.6, 0.62))
	k.pop()
	# grip: a rubber-gripped block below the rear, raked back
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-14.0)), Vector3(-0.2, -0.22, 0)))
	k.box("rubber", Vector3(0, 0, 0), Vector3(0.13, 0.36, 0.1), Color(0.35, 0.33, 0.3), Color(0.5, 0.48, 0.44))
	k.box("blued", Vector3(0, -0.19, 0), Vector3(0.15, 0.03, 0.11), Color(0.6, 0.6, 0.62), Color(0.7, 0.7, 0.72))
	k.pop()
	# trigger guard and trigger
	k.tube("blued", PackedVector3Array([Vector3(-0.1, -0.08, 0), Vector3(-0.08, -0.16, 0), Vector3(0.0, -0.17, 0), Vector3(0.06, -0.12, 0), Vector3(0.07, -0.07, 0)]), 0.012, 6, Color(0.7, 0.7, 0.72))
	k.beam("blued", Vector3(-0.02, -0.07, 0), Vector3(-0.04, -0.13, 0), 0.02, 0.012, Color(0.7, 0.7, 0.72), Color(0.8, 0.8, 0.82))
	k.pop()
	_commit(k, parent)
	return {"pitch": 62.0, "yaw": 0.0}

## The field radio: an olive case with a handle on top, two dials, a meter, a speaker grille and a whip antenna.
func _radio(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(28.0)), Vector3.ZERO))
	var olive := Color(0.42, 0.45, 0.32)
	k.box("paint", Vector3(0, 0.27, 0), Vector3(0.78, 0.54, 0.4), olive * 0.7, olive)
	k.box("paint", Vector3(0, 0.555, 0), Vector3(0.8, 0.03, 0.42), olive * 0.9, olive * 1.05)
	# front panel (+Z): two knobs and a meter
	for x: float in [-0.22, 0.04]:
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.24, 0.2)))
		k.lathe("rubber", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.05), Vector2(0.055, 0.07), Vector2(0.0, 0.072)]), 16, Color(0.3, 0.3, 0.3), Color(0.5, 0.5, 0.5))
		k.pop()
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.24, 0.32, 0.2)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.085, 0.0), Vector2(0.09, 0.02), Vector2(0.075, 0.025), Vector2(0.0, 0.02)]), 18, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.pop()
	k.box("paint", Vector3(-0.2, 0.42, 0.205), Vector3(0.26, 0.15, 0.012), olive * 0.45, olive * 0.5)
	for i: int in range(5):
		k.box("paint", Vector3(-0.2, 0.36 + 0.03 * float(i), 0.213), Vector3(0.24, 0.012, 0.012), olive * 0.95, olive * 1.1)
	# handle: a leather strap arching over the top
	var handle := PackedVector3Array()
	for i: int in range(9):
		var t := float(i) / 8.0
		handle.append(Vector3(-0.2 + 0.4 * t, 0.57 + sin(t * PI) * 0.1, 0.0))
	k.tube("rubber", handle, 0.022, 6, Color(0.45, 0.34, 0.24))
	# whip antenna from the rear corner, leaning back
	k.tube("blued", PackedVector3Array([Vector3(0.32, 0.56, -0.13), Vector3(0.36, 0.9, -0.17), Vector3(0.4, 1.3, -0.21)]), 0.008, 5, Color(0.8, 0.8, 0.8))
	k.lathe("blued", Vector3(0.32, 0.56, -0.13), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.05), Vector2(0.0, 0.06)]), 10, Color(0.7, 0.7, 0.7), Color(0.9, 0.9, 0.9))
	k.pop()
	_commit(k, parent)
	return {"pitch": 26.0, "yaw": 0.0, "margin": 0.06}

## The limpet: a dark green dome on its magnet ring, the time pencil in its socket and the placing rod beside it.
func _limpet(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	var green := Color(0.3, 0.36, 0.26)
	k.lathe("paint", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.52, 0.05), Vector2(0.5, 0.12), Vector2(0.44, 0.22), Vector2(0.3, 0.33), Vector2(0.12, 0.38), Vector2(0.0, 0.385)]), 28, green * 0.6, green * 1.1)
	# the magnet ring: a darker band round the foot
	k.lathe("blued", Vector3(0, -0.04, 0), PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.54, 0.0), Vector2(0.54, 0.06), Vector2(0.48, 0.06)]), 28, Color(0.5, 0.5, 0.5), Color(0.7, 0.7, 0.7))
	# the time pencil socket and pencil
	k.lathe("brass", Vector3(0.0, 0.36, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.06), Vector2(0.045, 0.07), Vector2(0.0, 0.07)]), 14, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-62.0)), Vector3(0.02, 0.42, 0.0)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.34), Vector2(0.03, 0.36), Vector2(0.03, 0.4), Vector2(0.0, 0.41)]), 10, Color(0.75, 0.6, 0.45), Color(0.9, 0.8, 0.7))
	k.pop()
	_commit(k, parent)
	return {"pitch": 34.0, "yaw": 0.0}

## Wire cutters, open: two long handles with rubber grips crossing at the pivot, the short jaws at the top.
func _cutters(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-40.0)), Vector3.ZERO))
	for s: float in [1.0, -1.0]:
		var spread := deg_to_rad(11.0) * s
		var b := Basis(Vector3.UP, spread)
		# handle from the pivot back along -X
		var tail := b * Vector3(-0.95, 0, 0)
		k.beam("blued", Vector3.ZERO, tail * 0.42, 0.06, 0.035, Color(0.6, 0.6, 0.62), Color(0.75, 0.75, 0.78))
		var grip := PackedVector3Array([tail * 0.42, tail * 0.7, tail])
		k.tube("rubber", grip, 0.05, 8, Color(0.62, 0.18, 0.12))
		# jaw: forward of the pivot, crossing to the other side
		var jaw_b := Basis(Vector3.UP, -spread * 1.6)
		k.beam("blued", Vector3(0.0, 0.006 * s, 0.0), jaw_b * Vector3(0.22, 0.0, 0.0), 0.07, 0.03, Color(0.65, 0.65, 0.68), Color(0.85, 0.85, 0.88))
	k.lathe("brass", Vector3(0, -0.03, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.045, 0.06), Vector2(0.0, 0.065)]), 14, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.pop()
	_commit(k, parent)
	return {"pitch": 42.0, "yaw": 0.0}

## A coil of hemp rope, the end trailing off.
func _rope(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	var path := PackedVector3Array()
	var turns := 4
	var per := 24
	for i: int in range(turns * per + 1):
		var a := TAU * float(i) / float(per)
		var t := float(i) / float(turns * per)
		var r := 0.42 + 0.05 * sin(a * 3.0 + t * 7.0)
		path.append(Vector3(cos(a) * r, 0.05 + 0.075 * t * float(turns) * 0.5 + 0.02 * sin(a * 2.0), sin(a) * r))
	# the loose end leaving the coil
	var last := path[path.size() - 1]
	for i: int in range(1, 9):
		var t := float(i) / 8.0
		path.append(last + Vector3(0.12 * t + 0.35 * t * t, -0.04 * t, 0.5 * t))
	k.tube("burlap", path, 0.055, 8, Color(0.86, 0.76, 0.56), Vector2.ZERO, 0.25, 2.0)
	_commit(k, parent)
	return {"pitch": 52.0, "yaw": 0.0}

## A debrief medal: a brass disc with a raised rim, the badge's own symbol struck into its face (the normal map is
## made from badges.png by finish.py prepare), seen almost face on.
func _badge(parent: Node3D, id: String) -> Dictionary:
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.53, 0.025), Vector2(0.53, 0.06), Vector2(0.5, 0.085), Vector2(0.47, 0.07)]), 48, Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95))
	var m: StandardMaterial3D = (mats["brass"] as StandardMaterial3D).duplicate()
	var prep := out_dir.path_join("prep")
	if FileAccess.file_exists(prep.path_join("badge_%s_n.png" % id)):
		m.normal_texture = ImageTexture.create_from_image(Image.load_from_file(prep.path_join("badge_%s_n.png" % id)))
		m.normal_scale = 1.4
		m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(prep.path_join("badge_%s_a.png" % id)))
	mats["medal"] = m
	k.disc("medal", Vector3(0, 0.07, 0), 0.47, 64, Rect2(0, 0, 1, 1), Color(0.95, 0.95, 0.95))
	k.pop()
	_commit(k, parent)
	return {"pitch": 8.0, "yaw": 0.0, "margin": 0.05}

## The objective marker: a pin with a small swallow-tailed flag, standing on a brass map tack.
func _marker_objective(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.22, 0.0), Vector2(0.24, 0.03), Vector2(0.2, 0.06), Vector2(0.05, 0.08), Vector2(0.0, 0.08)]), 28, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.lathe("blued", Vector3(0, 0.07, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 1.05), Vector2(0.03, 1.07), Vector2(0.0, 1.1)]), 10, Color(0.7, 0.7, 0.7), Color(0.9, 0.9, 0.9))
	# the flag: a waving cloth patch from the top of the pin
	var rows := 5
	var cols := 9
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	for i: int in range(rows):
		for j: int in range(cols):
			var u := float(j) / float(cols - 1)
			var v := float(i) / float(rows - 1)
			var notch := 0.0
			if u > 0.75:
				notch = (u - 0.75) / 0.25 * (1.0 - absf(v - 0.5) * 2.0) * 0.16
			var x := 0.02 + u * 0.62 - notch
			var y := 0.68 + v * 0.36
			var z := sin(u * 5.0) * 0.05 * u
			pts.append(Vector3(x, y, z))
			uvs.append(Vector2(u * 0.4, v * 0.25))
			colours.append(Color(0.78, 0.2, 0.14) * (0.85 + 0.15 * v))
	k.patch("canvas", rows, cols, pts, uvs, colours, false, false)
	k.patch("canvas", rows, cols, pts, uvs, colours, false, true)
	_commit(k, parent)
	return {"pitch": 24.0, "yaw": -24.0, "margin": 0.07}

## The app icon's subject in 3D: the beret with its cap badge, the fighting knife crossing in front of it.
func _app_beret(parent: Node3D) -> Dictionary:
	var k := Kit.new()
	var felt := Color(0.25, 0.29, 0.21)
	# the beret: a soft crown swelling well past the leather band, pulled down to the right as worn
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-16.0)) * Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0, 0.0, 0)))
	k.lathe("rubber", Vector3(0, -0.06, 0), PackedVector2Array([Vector2(0.46, 0.0), Vector2(0.48, 0.03), Vector2(0.48, 0.09), Vector2(0.46, 0.12)]), 48, Color(0.3, 0.22, 0.15), Color(0.42, 0.31, 0.21))
	var crown := PackedVector2Array([Vector2(0.46, 0.05), Vector2(0.6, 0.08), Vector2(0.74, 0.13), Vector2(0.82, 0.2), Vector2(0.83, 0.26), Vector2(0.76, 0.33), Vector2(0.6, 0.39), Vector2(0.4, 0.43), Vector2(0.18, 0.455), Vector2(0.0, 0.46)])
	k.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(4.0)), Vector3(0.12, 0.0, 0.0)))
	k.lathe("canvas", Vector3.ZERO, crown, 48, felt * 0.62, felt * 1.2)
	# the little stalk on top
	k.lathe("canvas", Vector3(0, 0.45, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.025, 0.05), Vector2(0.0, 0.055)]), 10, felt, felt * 1.1)
	k.pop()
	# cap badge over the left eye, on the band's edge
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.RIGHT, deg_to_rad(78.0)), Vector3(-0.26, 0.12, 0.42)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.13, 0.025), Vector2(0.1, 0.045), Vector2(0.0, 0.05)]), 24, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.pop()
	k.pop()
	# the knife, point up to the right, across the front of the beret
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(52.0)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.42, -0.42, 0.62)))
	_blade(k, Vector3(0.0, 0.0, 0.0), 1.25, 0.15, 0.035)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.02, 0.0, 0.0)))
	k.lathe("blued", Vector3(0, -0.19, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.008), Vector2(0.036, 0.19), Vector2(0.03, 0.37), Vector2(0.0, 0.38)]), 14, Color(0.55, 0.55, 0.55), Color(0.85, 0.85, 0.85))
	k.pop()
	_grip(k, Vector3(-0.04, 0, 0), 0.52, 0.07)
	k.pop()
	_commit(k, parent)
	return {"pitch": 30.0, "yaw": 0.0, "margin": 0.04}
