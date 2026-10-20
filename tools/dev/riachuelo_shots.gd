extends SceneTree
## Dev-only: photographs Operation Riachuelo from a list of camera positions, to look at La Boca by eye.
## Run (rendered, not headless):
##   HORACERO_MISSION=riachuelo xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/riachuelo_shots.gd -- <probe file> [setup]
## The probe file has one shot per line: "name x z zoom yaw pitch [hud] [novision] [perf] [ink]" (metres, degrees); the
## pictures go next to it as <name>.png. "perf" also prints the frame's draw calls, objects and primitives and the mean
## time of 30 frames (a software renderer here, so only good for comparing one build with another); "ink" draws it in
## comic ink (scripts/three_d/ink.gd). Setups: "" (the start, after a few seconds), "cafe" (the cellar open, the squad at the
## café and the board), "crossing" (the lamps out, three on the gondola over the river, Biguá rowing the passenger),
## "square" (Benteveo walking across the square among the neighbours, Lechuza by the café),
## "dark" (the start, with only the quay's lamps cut at the board), "hero" / "hero_dark" (three of the squad have just
## walked along the fresh snow of the quay and the west street, leaving their tracks; with the lamps cut or not).
const Missions = preload("res://scripts/missions.gd")
const DT: float = 1.0 / 30.0
var main: Node3D
var sim: RefCounted

func _init() -> void:
	call_deferred("run")

func tick() -> void:
	await process_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var file: String = args[0]
	var setup: String = args[1] if args.size() > 1 else ""
	Missions.choose("riachuelo", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots_progress.cfg"))
	main.hud.progress_path = "user://shots_progress.cfg"
	main.hud.load_progress()
	sim = main.sim
	main.hud.hints_enabled = false
	for i in range(3): await tick()
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	main.hud.overlay.hide()
	# nobody raises the alarm while the scene is being set
	sim.alarm.radius = 0.0
	# SHOTS_LOOK="id=look;...": dress actors in another look (the art pack's cut-outs: "art:<slot>"), as data could
	for pair: String in OS.get_environment("SHOTS_LOOK").split(";", false):
		var kv := pair.split("=")
		if kv.size() != 2 or not main.world.actors.has(kv[0]): continue
		var actor: Dictionary = sim.unit_by_id(kv[0])
		if actor.is_empty(): actor = sim.guard_by_id(kv[0])
		if actor.is_empty(): continue
		actor["look"] = kv[1]
		var model: Node = main.world.actors[kv[0]]
		model.call("_dress", model.call("_look_of", actor, kv[0], model.get("enemy")), kv[0])
	ff(3.0)
	match setup:
		"hero", "hero_dark":
			if setup == "hero_dark":
				sim.radio_cut = true
				sim._cut_power()
			# a quiet moment: nobody looking their way while they walk
			for g: Dictionary in sim.guards:
				g.range = 0
				g.near = 0
			# (east of the café, out of the launch's reach)
			for walk: Array in [["benteveo", Vector2(103.0, 108.6), Vector2(126.0, 108.0)], ["bigua", Vector2(102.0, 107.0), Vector2(119.0, 106.6)],
					["lechuza", Vector2(53.0, 71.0), Vector2(52.6, 91.0)]]:
				put(str(walk[0]), walk[1], "walk")
				sim.select(str(walk[0]))
				sim.move_to((walk[2] as Vector2) * 32.0)
			ff(13.0)
		"square":
			# Benteveo walking across the square among the neighbours out to watch the snow, Lechuza standing by the
			# café's corner (dress them with SHOTS_LOOK to see cut-outs and stand-ins among the modelled figures)
			for g: Dictionary in sim.guards:
				g.range = 0
				g.near = 0
			put("benteveo", Vector2(64.0, 95.2), "walk")
			put("lechuza", Vector2(80.6, 92.4), "walk")
			put("bigua", Vector2(91.0, 91.6), "walk")
			sim.select("benteveo")
			sim.move_to(Vector2(98.0, 95.4) * 32.0)
			ff(5.5)
			for id: String in ["benteveo", "lechuza", "bigua"]:
				print("square: %s at %s" % [id, sim.position_of(sim.unit_by_id(id)) / 32.0])
		"dark":
			sim.radio_cut = true
			sim._cut_power()
		"cafe":
			sim.rigged["ladder"] = "lechuza"
			sim.door_open = true
			sim._geometry_dirty = true
			put("hornero", Vector2(63.0, 88.4))
			put("bigua", Vector2(61.0, 84.4))
			put("benteveo", Vector2(74.0, 97.0), "walk")
			put("lechuza", Vector2(122.2, 96.8))
			sim.prisoner.freed = true
			sim.prisoner.follow_id = "bigua"
		"crossing":
			sim.rigged["ladder"] = "lechuza"
			sim.rigged["gondola"] = "hornero"
			sim.rigged["boat"] = "bigua"
			sim.door_open = true
			sim.radio_cut = true
			sim._cut_power()
			sim._geometry_dirty = true
			put("hornero", Vector2(149.0, 121.0))
			put("lechuza", Vector2(150.5, 122.0))
			put("benteveo", Vector2(151.0, 120.4))
			put("bigua", Vector2(45.0, 120.0))
			sim.prisoner.freed = true
			sim.prisoner.follow_id = "bigua"
			sim.prisoner.x = 45.0 * 32.0
			sim.prisoner.y = 119.2 * 32.0
	ff(0.5)
	if OS.get_environment("SHOTS_STATS") != "": _stats()
	if OS.get_environment("SHOTS_PICK") != "": _pick(OS.get_environment("SHOTS_PICK"))
	if OS.get_environment("SHOTS_HIDE") != "":
		# hide the static nodes whose names hold one of these words (to see what a frame's time goes on)
		var words := OS.get_environment("SHOTS_HIDE").split(",", false)
		var pending: Array[Node] = [main.world]
		while not pending.is_empty():
			var n: Node = pending.pop_back()
			pending.append_array(n.get_children())
			if n is GeometryInstance3D:
				for word: String in words:
					if word in str(n.name): (n as GeometryInstance3D).visible = false
	if OS.get_environment("SHOTS_ENV") != "": _tune(OS.get_environment("SHOTS_ENV"))
	var lines: PackedStringArray = FileAccess.get_file_as_string(file).split("\n", false)
	for line: String in lines:
		if line.begins_with("#"): continue
		var p: PackedStringArray = line.split(" ", false)
		var flags: Array = []
		while p.size() > 0 and p[p.size() - 1] in ["hud", "novision", "perf", "noactors", "far", "ink"]:
			flags.append(p[p.size() - 1])
			p.remove_at(p.size() - 1)
		if p.size() < 6: continue
		main.hud.visible = "hud" in flags
		for id: Variant in main.world.actors: (main.world.actors[id] as Node3D).visible = not "noactors" in flags
		main.world.draw_vision = not "novision" in flags
		main.world.set_ink("ink" in flags)
		main.desired_target = Vector3(float(p[1]), 0, float(p[2])); main.target = main.desired_target
		main.desired_zoom = float(p[3]); main.zoom = float(p[3])
		main.desired_yaw = deg_to_rad(float(p[4])); main.yaw = main.desired_yaw
		main.pitch = deg_to_rad(float(p[5]))
		main._update_camera(1.0, true)
		var env: Environment = (main.world.atmosphere.environment as WorldEnvironment).environment
		var fog0: Vector2 = Vector2(env.fog_depth_begin, env.fog_depth_end)
		if "far" in flags:
			# a lower camera than the game's: stand the (orthographic) camera further back so nothing near falls behind it
			main.set_process(false)
			main.camera.position += main.camera.global_transform.basis.z * 70.0
			main.camera.far = 300.0
			env.fog_depth_begin += 70.0
			env.fog_depth_end += 70.0
		for i in range(5):
			# SHOTS_LIVE=1: the operation runs on between the pictures (the squad keeps walking), else only the visuals
			if OS.get_environment("SHOTS_LIVE") == "1": sim.update(DT)
			main.world.update_visuals(DT)
			await tick()
		if "perf" in flags:
			await RenderingServer.frame_post_draw
			var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			var t0 := Time.get_ticks_usec()
			for i in range(30):
				main.world.update_visuals(DT)
				await RenderingServer.frame_post_draw
			print("perf %s: draw calls %d, objects %d, primitives %d, %.1f ms a frame" % [p[0], calls, objects, prims, float(Time.get_ticks_usec() - t0) / 30000.0])
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(file.get_base_dir().path_join(p[0] + ".png"))
		env.fog_depth_begin = fog0.x
		env.fog_depth_end = fog0.y
		main.camera.far = 160.0
		main.set_process(true)
		print("shot ", p[0])
	Missions.choose("plaza", false)
	quit()

## Dev overrides for the lighting, "key=value;...": exposure, white, tonemap (0 linear .. 4 agx), sky (energy), sun
## (energy), shadow (opacity), glow, fog (density).
func _tune(spec: String) -> void:
	var a: Node = main.world.atmosphere
	var env: Environment = (a.environment as WorldEnvironment).environment
	for pair: String in spec.split(";", false):
		var kv := pair.split("=")
		if kv.size() != 2: continue
		var v := float(kv[1])
		match kv[0]:
			"exposure": env.tonemap_exposure = v
			"white": env.tonemap_white = v
			"tonemap": env.tonemap_mode = int(v)
			"sky": (env.sky.sky_material as ProceduralSkyMaterial).energy_multiplier = v
			"sun": a.sun.light_energy = v
			"shadow": a.sun.shadow_opacity = v
			"glow": env.glow_intensity = v
			"fog": env.fog_density = v
			"bloom": env.glow_bloom = v
			"thresh": env.glow_hdr_threshold = v
			"ambient": env.ambient_light_energy = v
			_:
				# g_<name>: a parameter of the finishing grade (saturation, contrast, lift, tint_amount, vignette...)
				if kv[0].begins_with("g_"):
					var grade := ((a.get("_grade_layer") as CanvasLayer).get_child(0) as ColorRect).material as ShaderMaterial
					grade.set_shader_parameter(kv[0].substr(2), v)
				# i_<name> / p_<name>: a parameter of comic ink's drawing / printing pass (ink.gd)
				elif kv[0].begins_with("i_") or kv[0].begins_with("p_"):
					var ink: Node = main.world.comic_ink
					var m: ShaderMaterial = ink.lines_material if kv[0].begins_with("i_") else ink.paper_material
					m.set_shader_parameter(kv[0].substr(2), int(v) if kv[0] == "i_debug_view" else v)
	print("tuned ", spec)

## The static world's size: meshes, multimeshes and their triangles, and the lights.
## Which visible meshes (and multimesh instances) cover a point "x,y,z" (metres): to find what draws something odd.
func _pick(spec: String) -> void:
	for one: String in spec.split(";", false): _pick_one(one)

func _pick_one(spec: String) -> void:
	var v := spec.split(",")
	var p := Vector3(float(v[0]), float(v[1]), float(v[2]))
	var pending: Array[Node] = [main.world]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
			var m := n as MeshInstance3D
			var box := m.global_transform * m.get_aabb()
			if box.grow(0.3).has_point(p) and box.size.length() < float(OS.get_environment("SHOTS_PICK_MAX") if OS.get_environment("SHOTS_PICK_MAX") != "" else "60"):
				print("pick ", spec, " ", m.get_path(), " ", box)
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			for i: int in range(mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count):
				var box2 := (n as MultiMeshInstance3D).global_transform * mm.get_instance_transform(i) * mm.mesh.get_aabb()
				if box2.grow(0.3).has_point(p): print("pick ", spec, " ", n.get_path(), " #", i, " ", box2)

func _stats() -> void:
	var tris := 0
	var meshes := 0
	var multis := 0
	var instances := 0
	var omni := 0
	var surfaces := 0
	var shadow_surfaces := 0
	var by_name: Dictionary = {}
	var tris_by: Dictionary = {}
	var pending: Array[Node] = [main.world.root_static]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes += 1
			tris += _tris((n as MeshInstance3D).mesh)
			var sc: int = (n as MeshInstance3D).mesh.get_surface_count()
			surfaces += sc
			if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: shadow_surfaces += sc
			var key := String(n.name).rstrip("0123456789")
			by_name[key] = int(by_name.get(key, 0)) + sc
			tris_by[key] = int(tris_by.get(key, 0)) + _tris((n as MeshInstance3D).mesh)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			multis += 1
			instances += mm.instance_count
			tris += _tris(mm.mesh) * mm.instance_count
			var key2 := String(n.name).rstrip("0123456789")
			tris_by[key2] = int(tris_by.get(key2, 0)) + _tris(mm.mesh) * mm.instance_count
		elif n is OmniLight3D or n is SpotLight3D:
			omni += 1
	print("stats: %d meshes, %d multimeshes (%d instances), %d triangles, %d lights, %d surfaces (%d casting shadows)" % [meshes, multis, instances, tris, omni, surfaces, shadow_surfaces])
	var keys: Array = by_name.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(by_name[a]) > int(by_name[b]))
	var top := ""
	for i: int in range(mini(14, keys.size())): top += "%s %d, " % [keys[i], by_name[keys[i]]]
	print("surfaces by node: ", top)
	var keys2: Array = tris_by.keys()
	keys2.sort_custom(func(a: String, b: String) -> bool: return int(tris_by[a]) > int(tris_by[b]))
	var top2 := ""
	for i: int in range(mini(16, keys2.size())): top2 += "%s %dk, " % [keys2[i], int(tris_by[keys2[i]]) / 1000]
	print("triangles by node: ", top2)

static func _tris(mesh: Mesh) -> int:
	var t := 0
	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		t += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

func ff(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		sim.update(DT)
		main.world.update_visuals(DT)

func put(id: String, at: Vector2, stance: String = "sneak") -> void:
	var u: Dictionary = sim.unit_by_id(id)
	u.x = at.x * 32.0
	u.y = at.y * 32.0
	u.stance = stance
	u.path = []
