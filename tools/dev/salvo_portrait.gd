extends SceneTree
## Dev-only: renders the HUD portrait of an art-pack person from his own model, in the engine, to sit with the squad's
## painted portraits (assets/operatives.webp). His face is a small drawing on a plate, which cannot stand up to their
## painted faces head-on, so each way of taking him plays to what the model has instead: its hood, visor, respirator,
## harness and pack, in hard night light. Three ways (the last argument):
##   p1 "chiaroscuro" (the game's): head and shoulders at three-quarters, pulled back for the coat's collar, the harness
##      and the pack's straps; a hard warm light from a street lamp to the side and behind, the face plate in shadow and
##      only the visor's rim and the respirator catching it; snow on the hood;
##   p2 "profile": his profile against the dark ground, lit from behind at the edges; the hood, the visor and the
##      respirator make the shape, the face plate edge on;
##   p3 "over the shoulder": from behind at three-quarters, the hood, the pack and the rifle, his head turned a little
##      to us, snow falling between.
## His model as cutout.gd dresses it (its finish), standing as his own Idle clip stands him (rig_person.gd), the night's
## snow on him (the finish's, and flakes resting where they fell). The render is then painted over by
## tools/dev/salvo_portrait_paint.py (an oil filter, the squad's own canvas and backdrop, their grade and grain): a
## render of the model, not a drawing.
## Run (rendered, not headless):
##   xvfb-run -a -s "-screen 0 1600x1600x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/salvo_portrait.gd -- <out.png> [slot] [size] [p1|p2|p3]
## The game's is art_pack/juan_salvo/portrait.png (p1, slot juan_salvo, 768 x 768); p2 and p3 are kept beside the
## friends' source in art/juan_salvo/portraits/. The render itself is kept in user://salvo_portrait.render.png.
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const STYLES := ["p1", "p2", "p3", "p4"]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://art_pack/juan_salvo/portrait.png"
	var slot_id: String = args[1] if args.size() > 1 else "juan_salvo"
	var side: int = int(args[2]) if args.size() > 2 else 768
	var style: String = args[3] if args.size() > 3 and args[3] in STYLES else "p1"
	var s: Dictionary = ArtPack.slot(slot_id)
	# rendered twice as large (the paint pass works at that size), on a clear ground: the backdrop is the paint pass's
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side) * 2
	vp.msaa_3d = Viewport.MSAA_8X
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.6)
	e.ambient_light_energy = {"p1": 0.11, "p2": 0.08, "p3": 0.16, "p4": 0.2}[style]
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	env.environment = e
	world.add_child(env)
	Cutout.weather(0.55, 0.25)
	var figure: Node3D = Cutout.new()
	world.add_child(figure)
	figure.setup(s)
	figure.set_shadows(true)
	# lit hard (and its atlas read smooth)
	_smooth(figure)
	var h: float = float(s.height_m)
	var cam := Camera3D.new()
	cam.fov = 19.0
	vp.add_child(cam)
	# where he is taken from: the point looked at, the camera's bearing round him (his front is +z; positive is his
	# left), its rise and its distance
	var shot: Dictionary = {
		"p1": {"look": Vector3(0.0, h * 0.875, 0.03), "yaw": 30.0, "rise": 0.12, "dist": 1.78},
		"p2": {"look": Vector3(0.0, h * 0.895, 0.05), "yaw": 80.0, "rise": 0.05, "dist": 1.55},
		"p3": {"look": Vector3(0.15, h * 0.76, 0.0), "yaw": 155.0, "rise": 0.4, "dist": 3.1},
		# p4 "mugshot" (for a model with a face: the hooded survivor): head and shoulders near enough to front, the eyes a
		# little above the middle, framed as the squad's painted portraits are
		"p4": {"look": Vector3(0.0, h * 0.895, 0.04), "yaw": 24.0, "rise": 0.07, "dist": 1.56},
	}[style]
	var look: Vector3 = shot.look
	var yaw: float = deg_to_rad(float(shot.yaw))
	cam.position = look + Vector3(sin(yaw), float(shot.rise), cos(yaw)).normalized() * float(shot.dist)
	cam.look_at(look, Vector3.UP)
	cam.current = true
	_light(world, style, cam, look)
	var t: float = 0.0
	for f: int in range(48):
		t += 1.0 / 30.0
		figure.pose({"root": Vector3.ZERO, "offset": Vector3.ZERO, "yaw": 0.0, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0,
			"lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t, "camera": cam,
			"speed": 0.0, "aim": 0.0, "pitch": 0.0, "recoil": -1.0, "hold": 0.0, "down": 0.0, "state": "", "hits": 0})
		# over the shoulder: his head turned a little toward us
		if style == "p3": _turn_head(figure, deg_to_rad(26.0))
		await process_frame
	_flakes(figure, world, h)
	if style == "p3": _falling(world, cam, look)
	for f: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var im: Image = vp.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	var render_path: String = ProjectSettings.globalize_path("user://salvo_portrait.render.png")
	im.save_png(render_path)
	# the paint pass
	var paint: String = ProjectSettings.globalize_path("res://").path_join("../tools/dev/salvo_portrait_paint.py").simplify_path()
	var squad: String = ProjectSettings.globalize_path("res://assets/operatives.webp")
	var said: Array = []
	var code: int = OS.execute("python3", [paint, render_path, ProjectSettings.globalize_path(out), squad, str(side), style], said, true)
	print("portrait ", out, " (", style, ", ", side, " px) paint pass exit ", code)
	for line: Variant in said: print(str(line).strip_edges())
	quit()

## The night's light for each way of taking him, set about the camera (its right, its forward) and the point looked at.
func _light(world: Node3D, style: String, cam: Camera3D, look: Vector3) -> void:
	var right: Vector3 = cam.global_basis.x
	var fwd: Vector3 = -cam.global_basis.z
	match style:
		"p1":
			# the street lamp: hard and warm, to the left of the picture and behind him, a little above his head, so the
			# face plate turned toward it is in shadow and only what stands out of it (the visor's rim, the respirator)
			# and the hood's edge catch the light
			_lamp(world, look - right * 1.45 + fwd * 1.2 + Vector3.UP * 0.75, Color(1.0, 0.7, 0.4), 15.0, 6.0, true)
			# the snow's cold under the shadow side, faint, and the sky's on what faces up (the snow on his hood)
			_sun(world, (right * 0.4 + fwd * 0.6 + Vector3.UP * 0.5).normalized(), Color(0.55, 0.62, 0.78), 0.1, false)
			_sun(world, (fwd * 0.15 - Vector3.UP).normalized(), Color(0.62, 0.7, 0.88), 0.35, false)
		"p2":
			# his edge lit from behind: a warm lamp high behind his back, a cold one low behind his face
			_lamp(world, look + fwd * 1.3 + right * 0.7 + Vector3.UP * 0.6, Color(1.0, 0.72, 0.42), 11.0, 6.0, true)
			_lamp(world, look + fwd * 1.1 - right * 1.0 + Vector3.UP * 0.1, Color(0.62, 0.72, 0.95), 2.5, 5.0, false)
			_sun(world, (fwd * 0.3 - right * 0.2 - Vector3.UP * 0.5).normalized(), Color(0.55, 0.6, 0.72), 0.06, false)
			_sun(world, (fwd * 0.15 - Vector3.UP).normalized(), Color(0.62, 0.7, 0.88), 0.25, false)
		"p3":
			# the lamp beyond him to the right, catching the hood, the pack and the rifle at their edges; the sky's cold
			# over his back
			_lamp(world, look + right * 1.6 + fwd * 1.7 + Vector3.UP * 1.0, Color(1.0, 0.72, 0.42), 6.5, 6.0, true)
			_sun(world, (fwd * 0.5 + right * 0.2 - Vector3.UP * 0.8).normalized(), Color(0.6, 0.68, 0.85), 0.3, false)
		"p4":
			# lit as the painted portraits are: a warm key from the picture's upper left, in front of him, the face in
			# it; a cold fill from the right and below so the shadow side keeps its shape
			_lamp(world, look - right * 1.1 - fwd * 1.3 + Vector3.UP * 0.9, Color(1.0, 0.8, 0.58), 9.0, 6.0, true)
			_sun(world, (-right * 0.6 - fwd * 0.3 + Vector3.UP * 0.35).normalized(), Color(0.58, 0.64, 0.8), 0.22, false)
			_sun(world, (fwd * 0.15 - Vector3.UP).normalized(), Color(0.62, 0.7, 0.88), 0.25, false)

func _lamp(world: Node3D, at: Vector3, colour: Color, energy: float, reach: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	l.shadow_blur = 0.4
	l.position = at
	world.add_child(l)

func _sun(world: Node3D, travel: Vector3, colour: Color, energy: float, shadow: bool) -> void:
	var d := DirectionalLight3D.new()
	d.light_color = colour
	d.light_energy = energy
	d.shadow_enabled = shadow
	world.add_child(d)
	d.look_at_from_position(Vector3.ZERO, travel, Vector3.UP if absf(travel.y) < 0.95 else Vector3.FORWARD)

## His head (and neck) turned about his own up, after his clip and his rig have set them this frame.
func _turn_head(figure: Node3D, angle: float) -> void:
	var rig: Variant = figure.get("rig")
	if rig == null: return
	var sk: Skeleton3D = rig.skel
	for role: Array in [["neck", 0.4], ["head", 0.6]]:
		var b: int = rig._r(role[0])
		if b < 0: continue
		var axis: Vector3 = rig._axis(b, Vector3.UP)
		sk.set_bone_pose_rotation(b, (sk.get_bone_pose_rotation(b) * Quaternion(axis, angle * float(role[1]))).normalized())

## Snow falling between us and him: flakes hanging in the air in front of the camera, some near and large.
func _falling(world: Node3D, cam: Camera3D, look: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1959
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.91, 0.95, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var flake := SphereMesh.new()
	flake.radius = 0.5
	flake.height = 1.0
	flake.radial_segments = 8
	flake.rings = 4
	var dist: float = cam.global_position.distance_to(look)
	var half: float = tan(deg_to_rad(cam.fov * 0.5))
	for i: int in range(48):
		var depth: float = rng.randf_range(0.45, dist - 0.25)
		var across: float = rng.randf_range(-1.0, 1.0) * half * depth
		var up: float = rng.randf_range(-1.0, 1.0) * half * depth
		var at: Vector3 = cam.global_position - cam.global_basis.z * depth + cam.global_basis.x * across + cam.global_basis.y * up
		var r: float = rng.randf_range(0.001, 0.002) * (1.0 + 1.5 * (1.0 - depth / dist))
		var m := MeshInstance3D.new()
		m.mesh = flake
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.scale = Vector3.ONE * r * 2.0
		m.position = at
		world.add_child(m)

## Snow resting on him where it fell: flakes on what faces up on his hood and shoulders, each a little sunk into the
## cloth, set on the skeleton as it stands now.
func _flakes(figure: Node3D, world: Node3D, h: float) -> void:
	var meshes: Array = figure.call("_model_meshes")
	if meshes.is_empty(): return
	var mi: MeshInstance3D = meshes[0]
	var sk: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if sk == null or mi.skin == null: return
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / verts.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	var flake := SphereMesh.new()
	flake.radius = 0.5
	flake.height = 0.8
	flake.radial_segments = 8
	flake.rings = 4
	# snow reads pale at night even out of the light
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.94, 0.97)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.58, 0.66)
	mat.emission_energy_multiplier = 0.45
	var picked: int = 0
	for tries: int in range(40000):
		if picked >= 90: break
		var i: int = rng.randi_range(0, verts.size() - 1)
		var v: Vector3 = verts[i]
		var nrm: Vector3 = normals[i]
		# on the crown of the hood, and across the shoulders and the top of the pack
		var crown: bool = v.y > h * 0.925 and nrm.y > 0.45
		var shoulder: bool = v.y > h * 0.7 and v.y < h * 0.83 and nrm.y > 0.72
		if not (crown or shoulder): continue
		# the bone that holds it most
		var best: int = 0
		for k: int in range(per):
			if weights[i * per + k] > weights[i * per + best]: best = k
		var bind: int = bones[i * per + best]
		var bone: int = mi.skin.get_bind_bone(bind)
		if bone < 0: bone = sk.find_bone(mi.skin.get_bind_name(bind))
		var xf: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind)
		var at: Vector3 = xf * v
		var up: Vector3 = (xf.basis * nrm).normalized()
		var r: float = rng.randf_range(0.0025, 0.0055)
		var m := MeshInstance3D.new()
		m.mesh = flake
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(m)
		m.global_transform = Transform3D(Basis.looking_at(up, Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).scaled(Vector3(r * 2.0, r * 2.0, r * 1.3)), at + up * r * 0.25)
		picked += 1

## The finish's shader lit hard for the portrait, as a lamp lights at night (plain Lambert: what faces away from the
## lamp gets none of it; in the game the light is wrapped round him, softer), its atlas sampled smooth.
func _smooth(figure: Node3D) -> void:
	for mi: MeshInstance3D in figure.call("_model_meshes"):
		var m: Material = mi.material_override
		if not m is ShaderMaterial: continue
		var copy := (m as ShaderMaterial).duplicate() as ShaderMaterial
		var shader := Shader.new()
		shader.code = (m as ShaderMaterial).shader.code.replace("filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic").replace("diffuse_lambert_wrap", "diffuse_lambert")
		copy.shader = shader
		mi.material_override = copy
