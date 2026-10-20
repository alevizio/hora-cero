extends SceneTree
## Dev: renders one baked figure alone (bind pose) from several sides, close on a point.
## godot --path godot --script ../tools/dev/fig_view.gd -- <fig> <out.png> <y> <dist>
const Figure := preload("res://scripts/three_d/figure.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fig: String = args[0]
	var out: String = args[1]
	var y := float(args[2]) if args.size() > 2 else 1.5
	var dist := float(args[3]) if args.size() > 3 else 0.6
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 800)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	vp.add_child(sun)
	var views := [0.0, PI * 0.25, PI * 0.5, PI]
	var imgs: Array = []
	var mesh := Figure.mesh(fig, "3a2a1e")
	var only := OS.get_environment("FIG_ONLY")
	if only != "":
		var keep := ArrayMesh.new()
		var meta: Dictionary = Figure.load_fig(fig).meta
		for i: int in range(mesh.get_surface_count()):
			if str(meta.surfaces[i].name) in only.split(","):
				keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
				keep.surface_set_material(keep.get_surface_count() - 1, mesh.surface_get_material(i))
		mesh = keep
	for i: int in range(views.size()):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation.y = -views[i]
		vp.add_child(mi)
		var cam := Camera3D.new()
		cam.fov = 30
		cam.position = Vector3(0, y, dist)
		vp.add_child(cam)
		cam.current = true
		for f: int in range(4): await process_frame
		imgs.append(vp.get_texture().get_image())
		mi.queue_free()
		cam.queue_free()
	var sheet := Image.create(1600, 1600, false, Image.FORMAT_RGBA8)
	for i: int in range(imgs.size()):
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		var half := im.get_region(Rect2i(400, 0, 800, 800))
		sheet.blit_rect(half, Rect2i(0, 0, 800, 800), Vector2i((i % 2) * 800, (i / 2) * 800))
	sheet.save_png(out)
	quit()
