extends SceneTree
## Dev-only, for the website: the friends' vehicles as the game draws them (plaza_vehicle.gdshader, their paint of the
## time, a dusting of snow on their caps, the colectivo lit), each seen broadside on a transparent background under the
## turntables' lights: the cutouts of the landing page's line of cars (tools/dev/car_cutouts.py makes the strip).
## Run (rendered, not headless):
##   godot --path godot --rendering-driver opengl3 --script ../tools/dev/car_cutouts.gd -- <out dir> [width px]
## Writes <out dir>/<model>.png, the vehicle's front to the left, all to one scale (pixels per metre).
const Plaza = preload("res://scripts/three_d/plaza.gd")
const PlazaCity = preload("res://scripts/three_d/plaza_city.gd")
## model, paint index (PlazaCity.period_paint), in service (lit)
const MODELS := [["sedan49_near", 0, 0.0], ["taxi49_near", 0, 1.0], ["saloon53_near", 1, 0.0], ["coupe48_near", 2, 0.0],
	["pickup51_near", 0, 0.0], ["van51_near", 1, 0.0], ["microcar_near", 3, 0.0], ["work_pickup_near", 2, 0.0],
	["colectivo60_open", 0, 1.0]]
const PX_PER_M := 110.0
const MARGIN := 0.35

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.45, 0.5)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.3
	key.rotation = Vector3(-0.7, -1.1, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.74, 1.0)
	rim.light_energy = 1.0
	rim.rotation = Vector3(-0.3, 1.6, 0)
	root.add_child(rim)
	var macro: Texture2D = load("res://assets/tex/nature/macro_noise.png")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(cam)
	cam.current = true
	for spec: Array in MODELS:
		var model: String = str(spec[0])
		var path := "res://assets/vehicles/" + model + ".res"
		if not ResourceLoader.exists(path):
			print("no model ", model)
			continue
		var node := MeshInstance3D.new()
		node.mesh = load(path)
		var mats: Array[ShaderMaterial] = Plaza.vehicle_materials(node.mesh, false, 0.12, macro)
		var paint: Color = PlazaCity.period_paint(model.trim_suffix("_near"), int(spec[1]))
		for i: int in range(node.mesh.get_surface_count()):
			var m: ShaderMaterial = mats[mini(i, mats.size() - 1)]
			m.set_shader_parameter("paint", paint)
			m.set_shader_parameter("in_service", float(spec[2]))
			m.set_shader_parameter("snow_amount", 0.4)
			node.set_surface_override_material(i, m)
		root.add_child(node)
		var box: AABB = node.get_aabb()
		# broadside: the camera off to -x looking along +x, so the model's front (-z) is to the left; the colectivo's
		# front is +z (tools/vehicles.gd mirrors it for its door), so it is taken from +x
		var width_m: float = box.size.z + MARGIN * 2.0
		var height_m: float = box.size.y + MARGIN * 2.0
		root.size = Vector2i(int(round(width_m * PX_PER_M)), int(round(height_m * PX_PER_M)))
		cam.size = width_m
		var from_right: bool = model.begins_with("colectivo")
		cam.rotation = Vector3(0, PI * 0.5 if from_right else -PI * 0.5, 0)
		cam.position = Vector3(box.end.x + 20.0 if from_right else box.position.x - 20.0, box.get_center().y, box.get_center().z)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, model])
		print(model, " ", root.size, " ", box.size)
		node.queue_free()
		await process_frame
	quit()
