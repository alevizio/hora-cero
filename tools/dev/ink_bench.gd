extends SceneTree
## Dev-only: what comic ink (scripts/three_d/ink.gd) costs a frame. One still view, the clock stopped; frames drawn in
## turns with ink off, on, and on without its two passes ("scene": what ink leaves out of the scene, the mist and the
## glows, without the drawing and the printing), and for each the frame's wall time and the renderer's own measure of
## its CPU and GPU time (RenderingServer.viewport_get_measured_render_time_*). The minimum of each set is the figure
## to compare: other work on the machine only ever adds to a frame. "passes" (on - scene) is what the two full-screen
## passes cost. A software renderer (llvmpipe) gives the cost relative to the rest of the frame, not what a phone's GPU
## takes.
## Run: HORACERO_MISSION=riachuelo xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x720 \
##        --script ../tools/dev/ink_bench.gd -- [x z zoom] [rounds] [frames]       (INK_LITE=1: the phones' version)
const Missions = preload("res://scripts/missions.gd")
var main: Node3D

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0] == "synthetic":
		await synthetic(int(args[1]) if args.size() >= 2 else 6, int(args[2]) if args.size() >= 3 else 8)
		return
	var mission: String = OS.get_environment("HORACERO_MISSION")
	if mission != "": Missions.choose(mission, false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	for i in range(3): await process_frame
	main._command("begin")
	main.hud.overlay.hide()
	main.hud.visible = false
	if not main.sim.paused: main.sim.toggle_pause()
	main.set_process(false)
	var at: Vector3 = Vector3(float(args[0]), 0, float(args[1])) if args.size() >= 3 else main.camera_home
	var zoom: float = float(args[2]) if args.size() >= 3 else main.zoom_home
	var rounds: int = int(args[3]) if args.size() >= 4 else 3
	var frames: int = int(args[4]) if args.size() >= 5 else 6
	main.desired_target = at; main.target = at
	main.desired_zoom = zoom; main.zoom = zoom
	main._update_camera(1.0, true)
	var vp: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var sets: Dictionary = {}
	for mode: String in ["off", "on", "scene"]: sets[mode] = {"wall": [], "cpu": [], "gpu": []}
	var ink: Node = main.world.comic_ink
	# INK_LITE=1: the phones' drawing pass (fewer samples)
	if OS.get_environment("INK_LITE") == "1": ink.lines_material.set_shader_parameter("lite", true)
	for r in range(rounds):
		for mode: String in ["off", "on", "scene"]:
			main.world.set_ink(mode != "off")
			ink.quad.visible = mode == "on"
			ink.paper_layer.visible = mode == "on"
			for i in range(3):
				main.world.update_visuals(0.0)
				await RenderingServer.frame_post_draw
			for i in range(frames):
				var t0 := Time.get_ticks_usec()
				main.world.update_visuals(0.0)
				await RenderingServer.frame_post_draw
				(sets[mode].wall as Array).append(float(Time.get_ticks_usec() - t0) / 1000.0)
				# the renderer's measures come a frame late: the first of a set may be nought
				var cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(vp)
				var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
				if cpu > 0.0: (sets[mode].cpu as Array).append(cpu)
				if gpu > 0.0: (sets[mode].gpu as Array).append(gpu)
	var size: Vector2i = root.get_visible_rect().size
	print("ink bench %s at (%.1f, %.1f) zoom %.1f, %dx%d, %d rounds of %d frames" % [mission if mission != "" else "plaza", at.x, at.z, zoom, size.x, size.y, rounds, frames])
	for key: String in ["wall", "cpu", "gpu"]:
		var row: Dictionary = {}
		for mode: String in ["off", "on", "scene"]:
			var values: Array = sets[mode][key]
			values.sort()
			row[mode] = [values[0] if not values.is_empty() else 0.0, values[values.size() / 2] if not values.is_empty() else 0.0]
		print("  %s ms (min / median): off %.1f / %.1f | on %.1f / %.1f | scene %.1f / %.1f | passes %.1f / %.1f | ink in all %.1f / %.1f" % [key,
			row.off[0], row.off[1], row.on[0], row.on[1], row.scene[0], row.scene[1], row.on[0] - row.scene[0], row.on[1] - row.scene[1],
			row.on[0] - row.off[0], row.on[1] - row.off[1]])
	quit(0)

## "synthetic": the passes on their own, over a plain little scene that costs next to nothing (a ground, some boxes, a
## light), so that their own cost is most of a frame; and, to compare, the colour grade the game already draws every
## frame (shaders/post_grade.gdshader, a canvas pass of one sample). Rounds of: nothing; the grade; ink's drawing
## pass; drawing and printing (ink as the game has it); the same in the phones' version.
func synthetic(rounds: int, frames: int) -> void:
	const Ink = preload("res://scripts/three_d/ink.gd")
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.3, 0.35)
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	scene.add_child(ground)
	for i in range(30):
		var box := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(2.0, 1.0 + float(i % 5), 2.0)
		box.mesh = m
		box.position = Vector3(float(i % 6) * 5.0 - 12.0, m.size.y * 0.5, float(i / 6) * 5.0 - 10.0)
		scene.add_child(box)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26.0
	cam.rotation_degrees = Vector3(-52, 45, 0)
	cam.position = Vector3(30, 40, 30)
	cam.current = true
	scene.add_child(cam)
	var grade_layer := CanvasLayer.new()
	var grade_rect := ColorRect.new()
	grade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grade_mat := ShaderMaterial.new()
	grade_mat.shader = preload("res://shaders/post_grade.gdshader")
	grade_rect.material = grade_mat
	grade_layer.add_child(grade_rect)
	scene.add_child(grade_layer)
	var ink: Node3D = Ink.new()
	scene.add_child(ink)
	ink.build("boca")
	var modes: Array[String] = ["nothing", "grade", "drawing", "ink", "ink lite"]
	var times: Dictionary = {}
	for mode: String in modes: times[mode] = []
	for r in range(rounds):
		for mode: String in modes:
			grade_layer.visible = mode == "grade"
			ink.quad.visible = mode in ["drawing", "ink", "ink lite"]
			ink.paper_layer.visible = mode in ["ink", "ink lite"]
			ink.lines_material.set_shader_parameter("lite", mode == "ink lite")
			for i in range(3): await RenderingServer.frame_post_draw
			for i in range(frames):
				var t0 := Time.get_ticks_usec()
				await RenderingServer.frame_post_draw
				(times[mode] as Array).append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var size: Vector2i = root.get_visible_rect().size
	print("ink bench, synthetic scene, %dx%d, %d rounds of %d frames (ms a frame, min / median)" % [size.x, size.y, rounds, frames])
	var base: float = 0.0
	var grade: float = 0.0
	for mode: String in modes:
		var t: Array = times[mode]
		t.sort()
		if mode == "nothing": base = t[0]
		if mode == "grade": grade = t[0] - base
		print("  %-8s %.1f / %.1f  (+%.1f over nothing%s)" % [mode, t[0], t[t.size() / 2], t[0] - base, "" if mode in ["nothing", "grade"] or grade <= 0.0 else ", %.1fx the grade" % ((t[0] - base) / grade)])
	quit(0)

