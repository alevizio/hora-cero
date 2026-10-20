extends SceneTree
## Dev: a painted-portrait style render of baked figures (warm key light, dark ground), for
## comparing against concept art. godot --path godot --script ../tools/dev/fig_portrait.gd -- <out.png> <fig:yaw:y> ...
const Figure := preload("res://scripts/three_d/figure.gd")
const HAIR := {"hornero": "2a211b", "lechuza": "8f8a83",
	"benteveo": "3a2a1e", "bigua": "1e1a17"}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 900)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.12, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.36, 0.33, 0.26)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.70)
	key.light_energy = 1.05
	key.rotation = Vector3(-0.55, -0.75, 0)
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.75, 0.80, 0.70)
	rim.light_energy = 0.6
	rim.rotation = Vector3(-0.2, 2.6, 0)
	vp.add_child(rim)
	var shots: Array = []
	for spec: String in args.slice(1):
		var p := spec.split(":")
		var mi := MeshInstance3D.new()
		mi.mesh = Figure.mesh(p[0], HAIR.get(p[0], "3a2a1e"))
		mi.rotation.y = float(p[1])
		vp.add_child(mi)
		var cam := Camera3D.new()
		cam.fov = 22
		cam.position = Vector3(0, float(p[2]), 1.15)
		cam.rotation.x = -0.05
		vp.add_child(cam)
		cam.current = true
		for f: int in range(6): await process_frame
		var im := vp.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		shots.append(im)
		mi.queue_free()
		cam.queue_free()
		await process_frame
	var sheet := Image.create(900 * shots.size(), 900, false, Image.FORMAT_RGBA8)
	for i: int in range(shots.size()):
		sheet.blit_rect(shots[i], Rect2i(0, 0, 900, 900), Vector2i(i * 900, 0))
	sheet.save_png(out)
	quit()
