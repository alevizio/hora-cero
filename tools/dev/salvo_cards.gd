extends SceneTree
## Dev-only: Juan Salvo's pose cards for the Figma kit, as the game dresses and moves him (cutout.gd with his finish,
## rig_person.gd on his own skeleton): walking at the squad's pace, carrying someone (his arm up over the one on his
## shoulder, the rifle hanging from the other hand) and aiming, each caught at its widest moment, seen at three-quarters
## from his right front by an orthographic camera under a three-light studio rig (a warm key from the upper left, a cool
## fill from the right, a rim from behind) on a transparent background (the kit lays them on its own grey stage). Each
## card is framed as the kit's earlier ones: his height 0.79 of the card's, his feet at 0.925 of the way down and his back
## at 0.26 from its left (the rifle reaching to the right, to the card's edge at most).
## Run (rendered):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/salvo_cards.gd -- <out dir> [width] [height]
## The cards go to <out dir>/juan - walk.png, juan - carry.png, juan - aim.png.
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const DT: float = 1.0 / 60.0
## The lens: from his right front (his front +z, his left +x), a little above him.
const FROM := Vector3(-0.64, 0.0, 0.77)
const DOWN: float = 8.0
## Where he sits on the card (shares of its height and width).
const HEIGHT: float = 0.79
const FEET: float = 0.925
const BACK: float = 0.26
## The rifle may reach as far as RIGHT across the card (his back moved left for it if need be), and he is never wider
## than WIDEST of it.
const RIGHT: float = 0.985
const WIDEST: float = 0.79

## Each pose: what the game tells his figure, how long it plays before the card, and whether to wait for his stride at
## its longest.
const POSES := [
	{"name": "walk", "p": {"move": 1.0, "speed": 2.625}, "t": 1.5, "stride": true},
	{"name": "carry", "p": {"move": 1.0, "speed": 1.56, "hold": 1.0}, "t": 1.5, "stride": true},
	{"name": "aim", "p": {"aim": 1.0, "pitch": 0.05}, "t": 1.2, "stride": false},
]

var vp: SubViewport
var cam: Camera3D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var size := Vector2i(int(args[1]) if args.size() > 1 else 640, int(args[2]) if args.size() > 2 else 960)
	DirAccess.make_dir_recursive_absolute(out)
	_stage(size)
	Cutout.weather(0.0, 0.0)
	for pose: Dictionary in POSES:
		var fig: Node3D = Cutout.new()
		vp.add_child(fig)
		fig.setup(ArtPack.slot("juan_salvo"))
		fig.set_shadows(true)
		_smooth(fig)
		var clock: Array[float] = [0.0]
		var step := func() -> void:
			clock[0] += DT
			var p := {"root": Vector3.ZERO, "offset": Vector3.ZERO, "yaw": 0.0, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0,
				"lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": clock[0],
				"camera": cam, "speed": 0.0, "aim": 0.0, "pitch": 0.0, "recoil": -1.0, "hold": 0.0, "down": 0.0, "state": "", "hits": 0}
			p.merge(pose.p, true)
			fig.pose(p)
		while clock[0] < float(pose.t): step.call()
		if bool(pose.stride):
			# held at the long reach of a stride: the widest the feet come apart over a cycle, then the next time they do
			var widest: float = 0.0
			for i: int in range(60):
				step.call()
				widest = maxf(widest, _spread(fig))
			for i: int in range(120):
				step.call()
				if _spread(fig) >= widest * 0.97: break
		_aim(Vector3(0.0, 0.95, 0.1), 4.0)
		for pass_i: int in range(3):
			var im: Image = await _shot()
			var box: Rect2i = _outline(im)
			if box.size.x <= 0: break
			var px: float = cam.size / float(size.y)
			var b: Basis = cam.global_transform.basis
			if pass_i == 0:
				# his height to its share (unless the rifle would then run off the card)
				cam.size *= maxf(float(box.size.y) / (float(size.y) * HEIGHT), float(box.size.x) / (float(size.x) * WIDEST))
				var mid := Vector2(box.position) + Vector2(box.size) * 0.5 - Vector2(size) * 0.5
				cam.global_position += (b.x * mid.x - b.y * mid.y) * px
			else:
				# his back and his feet where the kit has them
				var left: float = minf(BACK * size.x, RIGHT * size.x - float(box.size.x))
				var shift := Vector2(float(box.position.x) - left, float(box.end.y) - FEET * size.y)
				cam.global_position += (b.x * shift.x - b.y * shift.y) * px
		var card: Image = await _shot()
		var path: String = out.path_join("juan - %s.png" % str(pose.name))
		card.save_png(path)
		print("card ", path, " ", card.get_size(), " outline ", _outline(card))
		fig.queue_free()
		await process_frame
	quit()

## How far apart his feet are this frame (his skeleton's), to catch a stride at its longest.
func _spread(fig: Node3D) -> float:
	var rig: Variant = fig.get("rig")
	if rig == null: return 0.0
	var sk: Skeleton3D = rig.skel
	return sk.get_bone_global_pose(int(rig.roles.foot_l)).origin.distance_to(sk.get_bone_global_pose(int(rig.roles.foot_r)).origin)

## The stage: a transparent background, a soft grey studio ambient, the three lights, the orthographic lens.
func _stage(size: Vector2i) -> void:
	vp = SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.58, 0.6, 0.64)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 2.0
	env.environment = e
	vp.add_child(env)
	key = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.shadow_blur = 1.2
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 20.0
	vp.add_child(key)
	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.8, 0.95)
	fill.light_energy = 0.4
	vp.add_child(fill)
	rim = DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.95, 0.88)
	rim.light_energy = 0.7
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.1
	cam.far = 80.0
	cam.current = true
	vp.add_child(cam)

## The lens looking at `centre` from FROM, DOWN degrees above him, `size` metres high; the lights turned with it.
func _aim(centre: Vector3, size: float) -> void:
	var flat := Vector3(FROM.x, 0.0, FROM.z).normalized()
	var dir: Vector3 = (flat * cos(deg_to_rad(DOWN)) + Vector3.UP * sin(deg_to_rad(DOWN))).normalized()
	cam.global_position = centre + dir * 30.0
	cam.look_at(centre, Vector3.UP)
	cam.size = size
	var b: Basis = cam.global_transform.basis
	# the key from the upper left in front, the fill from the right, the rim from behind and above
	_point(key, b, Vector3(-0.8, 0.9, 0.7))
	_point(fill, b, Vector3(1.0, 0.1, 0.5))
	_point(rim, b, Vector3(0.4, 0.7, -1.0))

## A light shining from `toward` (the lens's own frame: x right, y up, z towards the lens).
func _point(l: DirectionalLight3D, b: Basis, toward: Vector3) -> void:
	var d: Vector3 = (b * toward).normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	l.global_transform = Transform3D(Basis.looking_at(-d, up), Vector3.ZERO)

func _shot() -> Image:
	for i: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()

## His outline on a card: the box round what is not transparent.
func _outline(im: Image) -> Rect2i:
	var w: int = im.get_width()
	var h: int = im.get_height()
	var x0: int = w
	var y0: int = h
	var x1: int = -1
	var y1: int = -1
	for y: int in range(0, h, 2):
		for x: int in range(0, w, 2):
			if im.get_pixel(x, y).a > 0.1:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0: return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## His atlas read smooth up close (the finish samples it so too; kept here should that change).
func _smooth(fig: Node3D) -> void:
	for mi: MeshInstance3D in fig.call("_model_meshes"):
		var m: Material = mi.material_override
		if not m is ShaderMaterial: continue
		var copy := (m as ShaderMaterial).duplicate() as ShaderMaterial
		var shader := Shader.new()
		shader.code = (m as ShaderMaterial).shader.code.replace("filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic")
		copy.shader = shader
		mi.material_override = copy
