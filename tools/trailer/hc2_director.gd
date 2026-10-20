extends "res://../tools/trailer/horacero_director.gd"
## The cinematic Hora Cero trailer's director (dev tool, not shipped): camera moves through the Plaza de Mayo at night,
## filmed frame by frame from the game's own scene and rules, as the Hora Cero preview in Spanish. Built on the launch
## trailer's director (horacero_director.gd: its setups, staged moments and scripted wins are used as they are).
##   tools/trailer/hc2_run.sh <take> <width> <height> <out.mkv>             (1080 1920 for the upright cut)
## What is new here:
##  - a lens moved along paths (dollies, cranes, orbits): each take gives a pose for every instant ({"pos", "look",
##    "fov", "focus", "blur", "roll"}), or the game's own camera with its HUD ({"game": [x, z, zoom, yaw, pitch]});
##  - 24 frames a second, each the mean of SUB frames drawn across its whole interval (motion blur, a 360-degree
##    shutter at SUB 2): every drawn frame is one step of the rules of 1 / (24 * SUB) s (Godot runs with --fixed-fps);
##  - depth of field (hc2_dof.gdshader: the scene's depth read back, the blur by the circle of confusion);
##  - big soft flakes falling close to the lens (hc2_bokeh.gdshader), over the game's own two layers of snow;
##  - the night a little deeper for the lens (the ambient and the exposure down, the lamps as they are): CINE;
##  - the dry square before the snow (the ground's cover held back) and people looking up at it (their heads tipped
##    back on their own rigs, after the game has posed them);
##  - frames piped straight into ffmpeg (no frame dumps on the disk): <out.mkv>, H.264 CRF 12, 4:4:4.
## The game's sound is off (the trailer's sound is laid in compose: hc2_compose.py).
## PROBE=0,0.5,1 renders stills of a take at those points of it (<out dir>/<take>_<u>.png) instead of filming it.
## Each take prints "MARK <take> <frames>" and "EVENT <take> <name> <frame>" (output frames) for the edit, and
## "DRAWCHECK <take> ok" when every step of the game had its frame drawn; "bad" means the window stopped being drawn for
## a while (covered or not yet shown: macOS stops drawing a hidden window) and the game ran on unfilmed: film it again.

var FPS: float = 24.0
var SUB: int = 2
var out_path: String = ""
var pipe: FileAccess = null
var pipe_pid: int = -1
var probe_us: Array = []
var probe_dir: String = ""
var take_name: String = ""
var out_frames: int = 0
var dof_quad: MeshInstance3D
var dof_mat: ShaderMaterial
var bokeh_node: MultiMeshInstance3D
var bokeh_mat: ShaderMaterial
var bokeh_on: float = 0.0
var pose_now: Dictionary = {}
## Heads tipped back (people looking up at the snow): actor id -> degrees.
var look_up: Dictionary = {}
## The ground's cover held at this (-1: as the rules have it): the dry square before the snow.
var hold_cover: float = -1.0
var hide_snowfall: bool = false
## The mound the game grows over somebody down in the snow (a sign for the player) left out of the picture.
var hide_mounds: bool = true
var env_base: Dictionary = {}
var cine: float = 1.0
var clock: float = 0.0
## Frames the game has stepped through (main.gd steps the rules once a frame, drawn or not) and the steps a take
## took without a frame drawn for them: a window the system stops drawing (covered, minimised, not yet shown) lets the
## rules run on while nothing is filmed, and the take is no longer the one written here.
var procs: int = 0
var undrawn: int = 0

func boot() -> void:
	Plans = load(get_script().resource_path.get_base_dir().path_join("horacero_plans.gd"))
	var args := OS.get_cmdline_user_args()
	var shot: String = args[0] if args.size() > 0 else "probe"
	out_path = args[1] if args.size() > 1 else "/tmp/hc2/%s.mkv" % shot
	take_name = shot
	portrait = root.size.y > root.size.x
	SUB = int(_env("SUB", "2"))
	if _env("TAKE_MAX", "") != "": take_max = int(round(float(_env("TAKE_MAX", "0")) * FPS))
	if _env("PROBE", "") != "":
		for s: String in _env("PROBE", "").split(","): probe_us.append(float(s))
		probe_dir = out_path.get_base_dir()
	cine = float(_env("CINE", "1"))
	level = "plaza"
	if Missions.index_of(level) < 0:
		for entry: Dictionary in Missions.IN_PROGRESS:
			if str(entry.id) == level: Missions.LIST.append(entry)
	Missions.choose(level, false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	root.mesh_lod_threshold = 0.0
	root.msaa_3d = Viewport.MSAA_4X if _env("MSAA", "2") == "4" else Viewport.MSAA_2X
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://trailer_progress.cfg"))
	main.hud.progress_path = "user://trailer_progress.cfg"
	main.hud.load_progress()
	sim = main.sim
	main.hud.hints_enabled = false
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	lens_cam = Camera3D.new()
	lens_cam.name = "TrailerLens"
	main.add_child(lens_cam)
	_build_dof()
	_build_bokeh()
	var hook := LateHook.new()
	hook.process_priority = 1000
	hook.call_back = _late
	root.add_child(hook)
	# the frames the game steps through, counted before anything else in a frame (the draw check in film())
	var counter := LateHook.new()
	counter.process_priority = -1000
	counter.call_back = func() -> void: procs += 1
	root.add_child(counter)
	main.camera.current = true
	for i in range(3): await tick()
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	main.hud.overlay.hide()
	main.hud.visible = false
	main.world.draw_vision = false
	sound(false)
	_read_env()
	await call("shot_" + shot)
	_close_pipe()
	print("DONE ", shot, " frames ", out_frames)
	quit()

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

## The game's sound stays off: the trailer's sound is laid in compose.
func sound(_on: bool) -> void:
	if main.world.audio != null: main.world.audio.enabled = false

# ------------------------------------------------------------------ the lens, the depth of field, the near snow
func _build_dof() -> void:
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("hc2_dof.gdshader"))
	dof_mat = ShaderMaterial.new()
	dof_mat.shader = shader
	dof_mat.render_priority = Material.RENDER_PRIORITY_MIN
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	dof_quad = MeshInstance3D.new()
	dof_quad.mesh = quad
	dof_quad.material_override = dof_mat
	dof_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dof_quad.extra_cull_margin = 16384.0
	dof_quad.position = Vector3(0, 0, -1.0)
	dof_quad.visible = false
	lens_cam.add_child(dof_quad)

func _build_bokeh() -> void:
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("hc2_bokeh.gdshader"))
	bokeh_mat = ShaderMaterial.new()
	bokeh_mat.shader = shader
	bokeh_mat.render_priority = 20
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = quad
	multi.instance_count = 900
	var r := RandomNumberGenerator.new()
	r.seed = 1958
	for i: int in range(multi.instance_count):
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(r.randf(), r.randf(), r.randf())))
	bokeh_node = MultiMeshInstance3D.new()
	bokeh_node.multimesh = multi
	bokeh_node.material_override = bokeh_mat
	bokeh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bokeh_node.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 400, 4000))
	bokeh_node.visible = false
	main.add_child(bokeh_node)

## The night's settings as the game has them, to deepen for the lens and give back for the game's camera.
func _read_env() -> void:
	var env := _environment()
	if env == null: return
	env_base = {"exposure": env.tonemap_exposure, "ambient": env.ambient_light_energy, "sky": env.ambient_light_sky_contribution,
		"glow": env.glow_intensity, "bg": env.background_color}
	print("env: exposure %.2f ambient %.2f sky %.2f glow %.2f fog %.3f %.1f-%.1f" % [env.tonemap_exposure, env.ambient_light_energy,
		env.ambient_light_sky_contribution, env.glow_intensity, env.fog_density, env.fog_depth_begin, env.fog_depth_end])

func _environment() -> Environment:
	var holder: WorldEnvironment = main.world.atmosphere.get("environment") as WorldEnvironment
	return holder.environment if holder != null else null

func _cine_env(on: bool) -> void:
	var env := _environment()
	if env == null or env_base.is_empty(): return
	var k: float = cine if on else 0.0
	env.tonemap_exposure = float(env_base.exposure) * lerpf(1.0, 0.8, k)
	env.ambient_light_sky_contribution = float(env_base.sky) * lerpf(1.0, 0.75, k)
	env.glow_intensity = float(env_base.glow) * lerpf(1.0, 1.35, k)

## The pose of the lens (or the game's camera) for this instant. The upright cut (1080 x 1920) takes the pose's "v"
## (whatever of it differs upright), else the same lens opened up half again (Godot's field of view is vertical, so the
## same one upright would show a sliver of the width).
func apply(p: Dictionary) -> void:
	if portrait and not p.has("game"):
		var up: Dictionary = p.duplicate()
		if p.has("v"): up.merge(p.v, true)
		else: up["fov"] = float(p.get("fov", 40.0)) * 1.5
		p = up
	pose_now = p
	if p.has("game"):
		cam(p.game)
		_cine_env(false)
		dof_quad.visible = false
		bokeh_node.visible = false
		return
	lens = [0.0]
	solid_buildings(true)
	_cine_env(true)
	lens_cam.current = true
	lens_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	lens_cam.fov = float(p.get("fov", 40.0))
	lens_cam.near = float(p.get("near", 0.12))
	lens_cam.far = 1500.0
	var at: Vector3 = p.pos
	var look: Vector3 = p.look
	lens_cam.look_at_from_position(at, look, Vector3.UP)
	if p.has("roll"): lens_cam.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(float(p.roll)))
	var focus: float = float(p.get("focus", at.distance_to(look)))
	var blur: float = float(p.get("blur", 0.0))
	dof_quad.visible = blur > 0.05
	dof_mat.set_shader_parameter("focus", maxf(0.3, focus))
	dof_mat.set_shader_parameter("blur_px", blur)
	dof_mat.set_shader_parameter("max_px", float(p.get("max_blur", blur * 2.2)))
	dof_mat.set_shader_parameter("near_gain", float(p.get("near_gain", 1.0)))
	dof_mat.set_shader_parameter("mode", int(p.get("dof_mode", 0)))
	var env := _environment()
	dof_mat.set_shader_parameter("gain", float(p.get("dof_gain", pow(maxf(0.01, env.tonemap_exposure), -0.5))))
	bokeh_on = float(p.get("bokeh", 0.0))
	bokeh_node.visible = bokeh_on > 0.01
	bokeh_mat.set_shader_parameter("focus", maxf(0.3, focus))
	bokeh_mat.set_shader_parameter("blur_px", maxf(blur, 6.0))
	bokeh_mat.set_shader_parameter("strength", 0.42 * bokeh_on)

func _pre_draw() -> void:
	super._pre_draw()
	clock += 1.0 / (FPS * SUB)
	var nature: Object = main.world.get("nature")
	if hold_cover >= 0.0 and nature != null and nature.get("snow_material") != null:
		(nature.snow_material as ShaderMaterial).set_shader_parameter("cover", hold_cover)
	if nature != null:
		for n: Node in (nature as Node).get_children():
			if str(n.name).begins_with("Snowfall"): (n as Node3D).visible = not hide_snowfall
	if bokeh_node.visible:
		var forward := -lens_cam.global_transform.basis.z
		bokeh_mat.set_shader_parameter("box_center", lens_cam.global_position + forward * 2.6)
		bokeh_mat.set_shader_parameter("box_size", Vector3(6.0, 4.5, 6.0))
		bokeh_mat.set_shader_parameter("clock", clock)
		bokeh_mat.set_shader_parameter("screen", Vector2(root.size))
		var falls: Variant = nature.get("_falls") if nature != null else null
		if falls is Array and not (falls as Array).is_empty():
			var m: ShaderMaterial = (falls as Array)[0][1]
			bokeh_mat.set_shader_parameter("lamps", m.get_shader_parameter("lamps"))
			bokeh_mat.set_shader_parameter("lamp_colors", m.get_shader_parameter("lamp_colors"))
			bokeh_mat.set_shader_parameter("lamp_count", m.get_shader_parameter("lamp_count"))
	var site: Variant = main.world.get("structures")
	if hide_mounds and not lens.is_empty() and site != null and site.get("_mounds") != null:
		(site._mounds as MultiMesh).visible_instance_count = 0
	# the game's live marks (noise rings, pulses, a queued shot's line of fire, tracers) are the player's signs, not the
	# picture's: off in the lens shots, as the ink layer is
	if not lens.is_empty():
		for pool_name: String in ["_slow_marks", "_fast_marks", "_beams"]:
			var pool: Variant = main.world.get(pool_name)
			if pool != null:
				for n: Node in pool.nodes: (n as Node3D).visible = false

## Run after the game has posed everyone in a frame (after main.gd's _process: a later process priority) and before the
## skeletons are drawn from their poses: the heads tipped back.
class LateHook extends Node:
	var call_back: Callable
	func _process(_dt: float) -> void:
		if call_back.is_valid(): call_back.call()

func _late() -> void:
	for id: String in look_up:
		_tip_head(id, float(look_up[id]))

## A figure's head (and a little of its chest) tipped back by `deg`: looking up into the snow. Laid over the pose the game
## gave it this frame (operative.gd's flat rig: each bone posed in the model's space, the head about the neck).
func _tip_head(id: String, deg: float) -> void:
	var model: Variant = main.world.actors.get(id)
	if model == null: return
	var sk: Skeleton3D = (model as Node).get("skel")
	if sk == null or sk.get_bone_count() < 4: return
	for bone_k: Array in [[3, 1.0], [2, 0.25]]:
		var bone: int = int(bone_k[0])
		var pose_t: Transform3D = sk.get_bone_pose(bone)
		var side: Vector3 = pose_t.basis.x.normalized()
		var turn := Basis(side, -deg_to_rad(deg * float(bone_k[1])))
		sk.set_bone_pose(bone, Transform3D(turn * pose_t.basis, pose_t.origin))

# ------------------------------------------------------------------ filming
## One step of the rules and the visuals without drawing (a probe's way to the moment it pictures).
func _sub_step() -> void:
	var dt: float = 1.0 / (FPS * SUB)
	if plan != null: plan.tick()
	sim.update(dt)
	if plan != null: plan.trails()
	if warm_all: _pre_draw_warm()
	main.world.update_visuals(dt)

## Films a take: `seconds` long (TAKE_MAX cuts it short), the camera from `pose` (u 0..1 through the take, t seconds in),
## `each` called before every drawn frame with the output frame and the sub-frame.
func film(name: String, seconds: float, pose: Callable, each: Callable = Callable()) -> void:
	var n: int = int(round(seconds * FPS))
	if take_max > 0: n = mini(n, take_max)
	if not probe_us.is_empty():
		var done := 0
		for u: float in probe_us:
			var f: int = clampi(int(round(u * float(n - 1))), 0, n - 1)
			while done < f:
				for s in range(SUB):
					if each.is_valid(): each.call(done, s)
					_sub_step()
				done += 1
			apply(pose.call(float(f) / maxf(1.0, seconds * FPS - 1.0), float(f) / FPS))
			await process_frame
			await RenderingServer.frame_post_draw
			apply(pose.call(float(f) / maxf(1.0, seconds * FPS - 1.0), float(f) / FPS))
			await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png(probe_dir.path_join("%s_%03d.png" % [name, int(round(u * 100.0))]))
			print("probe %s u=%.2f t=%.1f" % [name, u, sim.time])
		return
	# the draw check: one step of the game for every frame drawn, from the take's first frame on
	var p0: int = -1
	var drawn: int = 0
	for f in range(n):
		for s in range(SUB):
			var t: float = (float(f) + float(s) / float(SUB)) / FPS
			apply(pose.call(clampf(t / seconds, 0.0, 1.0), t))
			if each.is_valid(): each.call(f, s)
			await process_frame
			if p0 < 0: p0 = procs
			await RenderingServer.frame_post_draw
			drawn += 1
			var extra: int = procs - p0 - drawn
			if extra != 0:
				print("DRAWCHECK %s frame %d sub %d: %d steps for %d frames drawn" % [name, f, s, drawn + extra, drawn])
				undrawn += extra
				p0 += extra
			_write_frame()
			if plan != null:
				plan.tick()
				plan.trails()
		if f % 24 == 23: print("frame %d of %d (%d ms)" % [f + 1, n, Time.get_ticks_msec()])
	out_frames += n
	print("DRAWCHECK %s %s" % [name, "ok" if undrawn == 0 else "bad: %d steps undrawn" % undrawn])
	print("MARK %s %d" % [name, n])

func event(name: String, f: int) -> void:
	print("EVENT %s %s %d" % [take_name, name, f])

func _write_frame() -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if pipe == null: _open_pipe(img)
	pipe.store_buffer(img.get_data())

func _open_pipe(img: Image) -> void:
	var fmt := "rgba" if img.get_format() == Image.FORMAT_RGBA8 else "rgb24"
	var vf := "null" if SUB == 1 else "tmix=frames=%d,select='eq(mod(n\\,%d)\\,%d)',setpts=N/(%d*TB)" % [SUB, SUB, SUB - 1, int(FPS)]
	var args := ["-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", fmt, "-s", "%dx%d" % [img.get_width(), img.get_height()],
		"-r", str(int(FPS) * SUB), "-i", "-", "-vf", vf, "-r", str(int(FPS)), "-c:v", "libx264", "-preset", "faster", "-crf", "12",
		"-pix_fmt", "yuv444p", out_path]
	var res: Dictionary = OS.execute_with_pipe("ffmpeg", args)
	pipe = res.get("stdio")
	pipe_pid = int(res.get("pid", -1))
	print("pipe: ffmpeg pid %d, %s %dx%d -> %s" % [pipe_pid, fmt, img.get_width(), img.get_height(), out_path])

func _close_pipe() -> void:
	if pipe == null: return
	pipe.close()
	pipe = null
	var waited := 0
	while pipe_pid > 0 and OS.is_process_running(pipe_pid) and waited < 600000:
		OS.delay_msec(100)
		waited += 100

# ------------------------------------------------------------------ paths
static func ease_io(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

## A smooth path through points (Catmull-Rom), u 0..1 along it.
static func path(points: Array, u: float) -> Vector3:
	var n := points.size()
	if n == 1: return points[0]
	if n == 2: return (points[0] as Vector3).lerp(points[1], u)
	var x: float = clampf(u, 0.0, 1.0) * float(n - 1)
	var i: int = mini(int(x), n - 2)
	var t: float = x - float(i)
	var p0: Vector3 = points[maxi(0, i - 1)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(n - 1, i + 2)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

func actor_at(id: String, height: float = 0.0) -> Vector3:
	var a: Dictionary = sim.unit_by_id(id)
	if a.is_empty(): a = sim.guard_by_id(id)
	var p: Vector2 = sim.position_of(a) / 32.0
	return Vector3(p.x, height, p.y)

# ------------------------------------------------------------------ looking around
## Stills from a list of lens poses, for framing: each line "name px py pz lx ly lz fov [blur] [bokeh]" (metres,
## degrees; "@id" in place of px or lx for offsets from somebody), after PROBE_SETUP (a setup_ function) or PROBE_FF s.
func shot_view() -> void:
	var file: String = OS.get_cmdline_user_args()[2]
	var setup: String = _env("PROBE_SETUP", "")
	if setup != "": await call("setup_" + setup)
	else: ff(float(_env("PROBE_FF", "3.0")))
	if _env("COVER", "") != "": hold_cover = float(_env("COVER", "-1"))
	if _env("NOFALL", "") == "1": hide_snowfall = true
	if _env("LOOKUP", "") != "":
		for q: Dictionary in sim.people(): look_up[str(q.id)] = float(_env("LOOKUP", "0"))
	for line: String in FileAccess.get_file_as_string(file).split("\n", false):
		if line.begins_with("#"): continue
		var p: PackedStringArray = line.split(" ", false)
		if p.size() < 8: continue
		var nums: Array = []
		var i := 1
		while i < p.size():
			if p[i].begins_with("@"):
				var at: Vector3 = actor_at(p[i].substr(1))
				nums.append(at.x + float(p[i + 1])); nums.append(float(p[i + 2])); nums.append(at.z + float(p[i + 3]))
				i += 4
			else:
				nums.append(float(p[i]))
				i += 1
		var pose := {"pos": Vector3(nums[0], nums[1], nums[2]), "look": Vector3(nums[3], nums[4], nums[5]), "fov": nums[6]}
		if nums.size() > 7: pose["blur"] = nums[7]
		if nums.size() > 8: pose["bokeh"] = nums[8]
		if nums.size() > 9: pose["dof_mode"] = int(nums[9])
		if nums.size() > 10: pose["dof_gain"] = nums[10]
		for k in range(3):
			apply(pose)
			await process_frame
			await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(file.get_base_dir().path_join(p[0] + ".png"))
		print("view ", p[0], " t=", snappedf(sim.time, 0.1))

# ------------------------------------------------------------------ staging
## A light of the take's own (cinematography, as on a set: where a lamp, a lit window or the tram would throw it), for
## the close shots the square's own lamps leave too dark to read a face.
func key_light(at: Vector3, color: Color, energy: float, reach: float, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.position = at
	main.add_child(l)
	return l

## Somebody of the squad put at `at` (metres), turned to face `face`, standing still.
func stand(id: String, at: Vector2, face: Vector2) -> Dictionary:
	var u: Dictionary = put(id, at)
	u.angle = (face - at).angle()
	return u

## One of the square's people put at `at`, turned to face `face`, standing in the crowd.
func person(id: String, at: Vector2, face: Vector2) -> Dictionary:
	var p: Dictionary = sim.guard_by_id(id)
	p.x = at.x * 32.0
	p.y = at.y * 32.0
	p.path = []
	p.angle = (face - at).angle()
	return p

## The four at their posts for their portraits, a few seconds into the night (the first flakes): Hornero by the front
## of his tram, Lechuza under the Cabildo's arcade with its lanterns lit, Benteveo on the Catedral's steps, Biguá by
## the colectivo on Yrigoyen.
func setup_posts() -> void:
	ff(float(_env("START_AT", "6.0")))
	sim.rigged["cabildo-lights"] = "lechuza"
	stand("hornero", Vector2(113.2, 31.4), Vector2(118.0, 40.0))
	stand("lechuza", Vector2(26.6, 111.6), Vector2(36.0, 108.0))
	stand("benteveo", Vector2(70.5, 23.6), Vector2(73.0, 34.0))
	stand("bigua", Vector2(204.6, 135.3), Vector2(201.0, 127.0))
	stand("salvo", Vector2(-20.0, 86.0), Vector2(0.0, 86.0))
	ff(0.3)

## The lull, the three cascarudos in: Juan Salvo out in the square by a lamp, the cascarudos away (or where a take puts
## them), everybody kept warm.
func setup_lull() -> void:
	_to_lull()
	var b: Dictionary = beasts()
	place(b.c1, Vector2(270.0, 31.0))
	place(b.c2, Vector2(279.0, 139.0))
	place(b.c3, Vector2(10.0, 150.0))
	for g: Dictionary in b.values():
		g.think = 99.0
	ff(0.3)

# ------------------------------------------------------------------ the takes (16:9; the upright cut's in CAMS_V below)
## The square from high up, before the snow: the lamps lit, the lawns frosted, nobody hurrying; the crane comes down
## over the Pirámide toward the Cabildo and the Avenida de Mayo.
func shot_open() -> void:
	hold_cover = 0.0
	hide_snowfall = true
	ff(2.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u * 0.9 + 0.1 * u * u)
		return {"pos": path([Vector3(176.0, 62.0, 78.0), Vector3(132.0, 34.0, 88.0), Vector3(98.0, 13.0, 96.0)], k),
			"look": path([Vector3(40.0, 0.0, 100.0), Vector3(34.0, 3.0, 104.0), Vector3(28.0, 6.0, 110.0)], k), "fov": 38.0}
	await film("open", 6.5, pose)

## Low by a lamp, the Cabildo across Bolívar: a slow dolly to the side, the lamp's post slipping past close.
func shot_cabildo() -> void:
	hold_cover = 0.0
	hide_snowfall = true
	ff(3.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(52.8, 1.0, 95.2).lerp(Vector3(52.3, 1.2, 101.6), k), "look": Vector3(26.0, 9.2, 110.0).lerp(Vector3(26.0, 9.0, 114.0), k),
			"fov": 38.0, "blur": 1.5, "focus": 27.0}
	await film("cabildo", 5.0, pose)

## The tram at its stop on Rivadavia, its windows lit, the street still dry: the bell (laid in compose) rings.
func shot_tram() -> void:
	hold_cover = 0.0
	hide_snowfall = true
	ff(3.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(89.0, 0.65, 34.5).lerp(Vector3(91.0, 0.75, 33.4), k), "look": Vector3(100.0, 2.2, 28.0).lerp(Vector3(101.0, 2.3, 28.0), k),
			"fov": 35.0, "blur": 2.0}
	await film("tram", 3.4, pose)

## The first flakes in lamplight: low under the lamp at the square's west side, the lens turning slowly about its globes.
func shot_flakes() -> void:
	ff(5.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		var a: float = deg_to_rad(lerpf(52.0, 30.0, k))
		var lamp := Vector3(48.0, 4.5, 98.0)
		return {"pos": Vector3(48.0 + cos(a) * 3.6, 1.0 + 0.3 * k, 98.0 + sin(a) * 3.6), "look": lamp + Vector3(0.0, -0.2 * k, 0.0),
			"fov": 32.0, "blur": 6.0, "bokeh": 1.0}
	await film("flakes", 5.0, pose)

## People out under a lamp on the north walk, looking up at it snowing; the lens low among them, pushing in.
func _lookup_group() -> void:
	var spots: Array = [Vector2(94.0, 43.0), Vector2(96.9, 44.6), Vector2(95.3, 46.8), Vector2(98.4, 42.4)]
	var faces: Array = [Vector2(95.0, 40.0), Vector2(94.0, 40.5), Vector2(97.0, 39.0), Vector2(94.5, 41.0)]
	var ids: Array = ["p22", "p23", "p24", "p10"]
	for i in range(ids.size()):
		person(ids[i], spots[i], faces[i])
		look_up[ids[i]] = 34.0 - 5.0 * float(i)

func shot_lookup() -> void:
	ff(8.0)
	warm_all = true
	_lookup_group()
	ff(0.2)
	# from under the lamp, their faces turned up into its light and the snow coming down through it
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(96.9, 0.95, 39.6).lerp(Vector3(96.6, 1.0, 40.4), k), "look": Vector3(95.7, 1.8, 44.6).lerp(Vector3(95.8, 1.85, 44.5), k),
			"fov": 34.0, "blur": 5.0, "bokeh": 0.9, "focus": 4.4,
			"v": {"look": Vector3(94.3, 1.9, 43.2), "fov": 44.0, "focus": 4.0}}
	await film("lookup", 5.0, pose)

## The square full of people out in the snow, the Casa Rosada floodlit beyond the Belgrano: a slow dolly in, low.
func shot_people() -> void:
	ff(46.0)
	warm_all = true
	# more of the square's people out on the promenade before the Casa Rosada, some looking up
	var spots: Array = [["p11", Vector2(214.0, 86.5)], ["p12", Vector2(216.2, 87.6)], ["p13", Vector2(219.5, 81.0)], ["p8", Vector2(222.4, 90.2)],
		["p9", Vector2(224.0, 88.6)], ["p10", Vector2(226.8, 94.0)], ["p14", Vector2(212.0, 95.5)], ["p15", Vector2(218.6, 97.4)],
		["p16", Vector2(230.5, 92.0)], ["p17", Vector2(233.0, 79.5)], ["p18", Vector2(235.2, 81.6)]]
	var i := 0
	for sp: Array in spots:
		var at: Vector2 = sp[1]
		person(str(sp[0]), at, at + Vector2(cos(float(i) * 2.1), sin(float(i) * 2.1)) * 3.0)
		if i % 3 == 0: look_up[str(sp[0])] = 26.0
		i += 1
	ff(0.2)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(198.0, 1.1, 93.0).lerp(Vector3(203.0, 1.0, 92.0), k), "look": Vector3(240.0, 5.5, 88.0).lerp(Vector3(240.0, 5.2, 88.0), k),
			"fov": 36.0, "blur": 1.5, "focus": 16.0, "bokeh": 0.5}
	await film("people", 5.0, pose)

## The snow thick now (the first wave), on the group by the Pirámide, the Pirámide behind them: close, slow.
func shot_touch() -> void:
	ff(96.0)
	warm_all = true
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(159.4, 1.2, 89.2).lerp(Vector3(158.6, 1.15, 88.6), k), "look": Vector3(152.6, 1.6, 84.4),
			"fov": 30.0, "blur": 5.0, "bokeh": 1.0}
	await film("touch", 3.6, pose)

## Somebody of the square, standing out in the first wave, goes down in the snow, quietly; the lens low beside her
## stays, the snow falling on (the game's mound over her left out: it is the player's sign, not the picture's).
func shot_fall() -> void:
	var who: String = _env("FALLER", "p6")
	warm_all = true
	warm(100.0)
	warm_all = false
	var p: Dictionary = person(who, Vector2(160.5, 90.0), Vector2(170.0, 86.0))
	sim._set_state(p, "crowd")
	p.panic = {}
	p.exposure = float(_env("FALL_AT", "0.994"))
	for q: Dictionary in sim.people():
		if q != p: q.exposure = 0.2
	faller = who
	print("fall: %s at %s state %s t=%.1f" % [who, actor_at(who), p.state, sim.time])
	var fell := [false]
	var each := func(f: int, _s: int) -> void:
		if not fell[0] and str(sim.guard_by_id(who).state) == "fallen":
			fell[0] = true
			event("fallen", f)
		for q: Dictionary in sim.people():
			if q != p: q.exposure = minf(float(q.exposure), 0.3)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		var c: Vector3 = actor_at(who)
		return {"pos": c + Vector3(3.4, 0.55, 3.0).lerp(Vector3(2.9, 0.45, 2.6), k), "look": c + Vector3(0.0, 1.05, 0.0).lerp(Vector3(0.0, 0.6, 0.0), smoothstep(0.12, 0.5, u)),
			"fov": 30.0, "blur": 6.0, "bokeh": 0.9}
	await film("fall", 6.6, pose, each)

## The few under cover: people in the Cabildo's arcade, its lanterns lit, looking out at the snow.
func shot_shelter() -> void:
	ff(60.0)
	warm_all = true
	sim.rigged["cabildo-lights"] = "lechuza"
	var ids: Array = ["p19", "p20", "p21"]
	var spots: Array = [Vector2(26.2, 106.4), Vector2(26.6, 108.0), Vector2(26.0, 109.4)]
	for i in range(ids.size()):
		person(ids[i], spots[i], Vector2(40.0, 106.0))
		sim._set_state(sim.guard_by_id(ids[i]), "safe")
		sim.guard_by_id(ids[i]).shelter = "cabildo"
	stand("lechuza", Vector2(26.4, 103.6), Vector2(40.0, 102.0))
	ff(0.3)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(37.5, 1.3, 112.5).lerp(Vector3(36.0, 1.25, 111.4), k), "look": Vector3(26.4, 1.7, 106.6),
			"fov": 30.0, "blur": 4.0, "bokeh": 0.9}
	await film("shelter", 4.2, pose)

## The four, one each: a slow push in close on each at his post (setup_posts), lit as his place would light him (the
## tram's windows, the arcade's lantern, the Catedral's lamps, the colectivo's windows): `key` beside the lens, `rim`
## behind him.
const WARM := Color(1.0, 0.72, 0.42)
const COLD := Color(0.55, 0.66, 1.0)

func _portrait(name: String, id: String, from: Vector3, to: Vector3, height: float, fov: float, seconds: float, key: Vector3, rim: Vector3, key_e: float = 2.2) -> void:
	await setup_posts()
	var c0: Vector3 = actor_at(id)
	key_light(c0 + key, WARM, key_e, 7.0)
	key_light(c0 + rim, COLD, 1.6, 6.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		var c: Vector3 = actor_at(id)
		return {"pos": c + from.lerp(to, k), "look": c + Vector3(0.0, height, 0.0), "fov": fov, "blur": 7.0, "bokeh": 0.8}
	await film(name, seconds, pose)

func shot_hornero() -> void:
	# by the front of his tram, its lit windows behind him
	await _portrait("hornero", "hornero", Vector3(1.2, 1.15, 3.2), Vector3(0.95, 1.2, 2.6), 1.5, 30.0, 3.2, Vector3(-1.2, 2.4, 1.6), Vector3(0.8, 2.2, -1.8), 3.2)

func shot_lechuza() -> void:
	await _portrait("lechuza", "lechuza", Vector3(3.2, 1.15, 1.3), Vector3(2.6, 1.2, 1.1), 1.5, 30.0, 3.2, Vector3(1.4, 2.6, -1.0), Vector3(-1.0, 2.2, 1.6), 1.6)

func shot_benteveo() -> void:
	await _portrait("benteveo", "benteveo", Vector3(1.0, 0.95, 3.2), Vector3(0.8, 1.0, 2.6), 1.5, 30.0, 3.2, Vector3(1.6, 2.6, 1.2), Vector3(-0.8, 2.4, -1.6))

func shot_bigua() -> void:
	await _portrait("bigua", "bigua", Vector3(-1.2, 1.2, -3.0), Vector3(-1.0, 1.25, -2.5), 1.5, 30.0, 3.2, Vector3(-1.8, 2.4, -0.8), Vector3(1.0, 2.2, 1.6), 1.5)

## The game itself, its HUD up: Benteveo leading a group of the square in under cover in the first minute (the scripted
## win of tests/plaza_playthrough.gd), the game's own camera on him.
func shot_g_lead() -> void:
	# 16 s in: the Catedral's group strung out behind him across the snow, on its way to the portico
	await setup_play(float(_env("PLAY_AT", "16.0")))
	hud_on("benteveo")
	# the passing words of the game (its notices) off: the HUD itself whole, the subtitles clear of them
	keep_notice = false
	var pose := func(u: float, _t: float) -> Dictionary:
		var p: Vector2 = sim.position_of(sim.unit_by_id("benteveo")) / 32.0
		var k := ease_io(u)
		return {"game": [p.x + 0.0, p.y + 2.0, lerpf(24.0, 21.0, k), lerpf(-45.0, -36.0, k), 50.0]}
	# Benteveo stays the one selected (the plan's orders to the others select them in passing): his card lit, his
	# objective ("llevalos a cubierto") on the HUD
	var keep := func(_f: int, _s: int) -> void:
		if str(sim.selected_id) != "benteveo": sim.select("benteveo")
	await film("g_lead", 5.4, pose, keep)

## Juan Salvo comes in off the Avenida de Mayo into the snow, sealed in his suit: the lens low ahead of him, going back
## as he comes; a warm light ahead of him (the square's lamps) catches his visor, a cold one behind him edges his hood.
func shot_juan() -> void:
	await setup_arrive()
	ff(float(_env("JUAN_FF", "4.0")))
	var key: OmniLight3D = key_light(Vector3.ZERO, WARM, 2.6, 9.0)
	var rim: OmniLight3D = key_light(Vector3.ZERO, COLD, 2.2, 8.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		var c: Vector3 = actor_at("salvo")
		key.position = c + Vector3(3.0, 2.6, -1.6)
		rim.position = c + Vector3(-2.4, 2.4, 0.6)
		return {"pos": c + Vector3(4.4, 0.6, 1.8).lerp(Vector3(2.9, 0.7, 1.2), k), "look": c + Vector3(0.0, 1.35, 0.0).lerp(Vector3(0.0, 1.5, 0.0), k),
			"fov": 30.0, "blur": 7.0, "bokeh": 1.0}
	await film("juan", 5.6, pose)

## The game, its HUD up: Juan Salvo carrying in a woman a cascarudo knocked down by the palms (the launch trailer's).
func shot_g_carry() -> void:
	await setup_carry()
	_some_in(16)
	hud_on("salvo")
	keep_notice = false
	var pose := func(u: float, _t: float) -> Dictionary:
		var p: Vector2 = sim.position_of(sim.unit_by_id("salvo")) / 32.0
		var k := ease_io(u)
		return {"game": [p.x - 0.3, p.y + 0.5, lerpf(float(_env("CARRY_ZOOM", "7.5")), float(_env("CARRY_ZOOM", "7.5")) - 0.8, k), lerpf(-45.0, -38.0, k), 52.0]}
	await film("g_carry", 4.6, pose)

## The cascarudos come up Hipólito Yrigoyen from the east, along the cars parked at its kerb, toward the lens low beside
## a parked sedan (the ground trembling first, in compose); one of the square's lamps over their path on their shells.
func _beasts_walk(delay: float) -> Dictionary:
	_to_lull()
	var b: Dictionary = beasts()
	place(b.c1, Vector2(191.0, 139.4))
	place(b.c3, Vector2(200.0, 137.4))
	place(b.c2, Vector2(279.0, 30.0))
	b.c1.path = [Vector2(182.0, 139.6) * 32.0, Vector2(172.0, 139.0) * 32.0, Vector2(166.0, 137.0) * 32.0, Vector2(160.0, 133.0) * 32.0]
	b.c3.path = [Vector2(190.0, 137.0) * 32.0, Vector2(180.0, 136.4) * 32.0, Vector2(172.0, 134.0) * 32.0, Vector2(166.0, 130.0) * 32.0]
	# a purposeful walk (the game's prowl, a little brisker for the picture)
	sim.data.creatures["speed"] = float(_env("BEAST_SPEED", "62"))
	for g: Dictionary in [b.c1, b.c3]:
		sim._set_state(g, "prowl")
		g.think = 99.0
		g.angle = PI
		# they keep to their way: nobody is theirs to go for while the lens rolls
		for q: Dictionary in sim.people(): (g.spared as Dictionary)[str(q.id)] = sim.time + 90.0
		for u: Dictionary in sim.units: (g.spared as Dictionary)[str(u.id)] = sim.time + 90.0
	for q: Dictionary in sim.people():
		if Vector2(float(q.x), float(q.y)).distance_to(Vector2(178.0, 136.0) * 32.0) < 34.0 * 32.0:
			q.x = 120.0 * 32.0
			q.y = 70.0 * 32.0
			q.path = []
	ff(delay)
	return b

## For framing (shot_view): the cascarudos BEAST_DELAY s into their walk.
func setup_beasts() -> void:
	_beasts_walk(float(_env("BEAST_DELAY", "3.0")))

func shot_beasts() -> void:
	var b: Dictionary = _beasts_walk(float(_env("BEAST_DELAY", "1.0")))
	key_light(Vector3(184.0, 4.0, 136.0), WARM, 2.0, 14.0)
	# low in the road beside a parked sedan (its flank soft in the right of the frame), the lit colectivo behind them
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		var at: Vector3 = Vector3(158.2, 0.55, 139.3).lerp(Vector3(160.2, 0.5, 138.3), k)
		return {"pos": at, "look": Vector3(192.0, 1.6, 139.2).lerp(Vector3(186.0, 1.9, 138.6), k),
			"fov": 30.0, "blur": 3.0, "focus": at.distance_to(actor_at("c1")), "bokeh": 0.6,
			"v": {"pos": Vector3(161.0, 0.5, 138.0).lerp(Vector3(162.5, 0.5, 137.6), k), "look": Vector3(190.0, 2.4, 139.0).lerp(Vector3(185.0, 2.4, 138.6), k), "fov": 46.0}}
	await film("beasts", 7.0, pose)
	print("beasts: c1 at %s c3 at %s" % [actor_at("c1"), actor_at("c3")])

## Close beside one as it walks: its legs, its shell in the lamplight (tracking with it, low).
func shot_legs() -> void:
	var b: Dictionary = _beasts_walk(float(_env("BEAST_DELAY", "3.0")))
	var key: OmniLight3D = key_light(Vector3.ZERO, WARM, 2.4, 9.0)
	var rim: OmniLight3D = key_light(Vector3.ZERO, COLD, 1.8, 9.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var c: Vector3 = actor_at("c1")
		var k := ease_io(u)
		key.position = c + Vector3(-1.0, 4.0, 3.0)
		rim.position = c + Vector3(2.0, 3.0, -3.5)
		return {"pos": c + Vector3(-2.4, 0.45, 4.4).lerp(Vector3(-3.0, 0.5, 3.9), k), "look": c + Vector3(0.0, 0.9, 0.0), "fov": 34.0, "blur": 6.0, "bokeh": 0.6}
	await film("legs", 3.0, pose)

## Juan Salvo takes aim at a cascarudo by the Pirámide's group and fires: the lens low behind his shoulder.
func shot_fire() -> void:
	await setup_aim()
	_some_in(14)
	var juan: Dictionary = sim.unit_by_id("salvo")
	var ammo: int = int(juan.ammo)
	var fired := [false, 0.0]
	# behind him and to his left: Juan on the right of the frame, the cascarudo across the snow on the left
	var j0: Vector3 = actor_at("salvo")
	var d: Vector3 = (actor_at("c1") - j0).normalized()
	var left := Vector3(d.z, 0.0, -d.x)
	# the muzzle flash, as a light (the game's own tracer and puff are its marks, off in the lens shots): a warm burst at
	# the rifle's muzzle for a few hundredths of a second, lighting him and the snow
	var flash: OmniLight3D = key_light(j0 + d * 1.0 + Vector3(0.0, 1.45, 0.0), Color(1.0, 0.78, 0.48), 0.0, 9.0)
	var each := func(f: int, s: int) -> void:
		if f == int(_env("ORDER_AT", "6")) and s == 0: print("fire: order ", sim.order_shoot("c1"), " ", sim.message)
		if not fired[0] and int(juan.ammo) < ammo:
			fired[0] = true
			event("shot", f)
		if fired[0]:
			flash.light_energy = 14.0 * maxf(0.0, 1.0 - float(fired[1]) / 0.07)
			fired[1] = float(fired[1]) + 1.0 / (FPS * SUB)
	key_light(j0 + left * 1.5 + Vector3(0.0, 2.6, 0.0) + d * 1.5, WARM, 1.6, 6.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var c: Vector3 = actor_at("salvo")
		var k := ease_io(u)
		var cam: Vector3 = j0 - d * lerpf(2.4, 2.1, k) + left * 1.25 + Vector3(0.0, 1.25, 0.0)
		var cam_v: Vector3 = j0 - d * lerpf(2.8, 2.5, k) + left * 0.55 + Vector3(0.0, 1.55, 0.0)
		return {"pos": cam, "look": j0 + d * 5.5 + Vector3(0.0, 1.3, 0.0), "fov": 36.0,
			"blur": 4.0, "focus": cam.distance_to(c) + 1.5, "bokeh": 0.6,
			"v": {"pos": cam_v, "look": j0 + d * 6.0 + Vector3(0.0, 0.7, 0.0), "fov": 56.0, "focus": cam_v.distance_to(c) + 2.0}}
	await film("fire", float(_env("FIRE_SECONDS", "3.0")), pose, each)
	print("fire: c1 ", sim.guard_by_id("c1").state, " ammo ", juan.ammo)

## A cascarudo rears up over the square, its claws raised: the lens low in front of it.
func shot_rear() -> void:
	setup_lull()
	var b: Dictionary = beasts()
	place(b.c1, Vector2(176.0, 99.0))
	b.c1.angle = PI * 0.82
	sim._set_state(b.c1, "prowl")
	b.c1.think = 99.0
	var reared := [false]
	var each := func(f: int, s: int) -> void:
		if f == int(_env("REAR_AT", "6")) and s == 0 and not reared[0]:
			reared[0] = true
			sim._set_state(b.c1, "stay")
			b.c1.pause_left = 4.0
			event("rear", f)
	var pose := func(u: float, _t: float) -> Dictionary:
		var c: Vector3 = actor_at("c1")
		var k := ease_io(u)
		return {"pos": c + Vector3(-6.8, 0.35, -1.3).lerp(Vector3(-6.0, 0.3, -1.1), k), "look": c + Vector3(0.0, 2.0, 0.0), "fov": 38.0,
			"blur": 5.0, "bokeh": 0.8}
	await film("rear", 3.0, pose, each)

## Behind the title: the square at the end of a night that went well, buried and empty in the blizzard; a slow push.
func shot_title_bg() -> void:
	await setup_buried()
	ff(1.0)
	var pose := func(u: float, _t: float) -> Dictionary:
		var k := ease_io(u)
		return {"pos": Vector3(150.0, 2.2, 112.0).lerp(Vector3(156.0, 2.1, 108.0), k), "look": Vector3(250.0, 9.0, 84.0), "fov": 40.0,
			"blur": 2.0, "focus": 40.0, "bokeh": 1.0}
	await film("title_bg", 5.0, pose)

## The thumbnail's picture (a still, PROBE=0.5): Juan Salvo taking aim at a cascarudo under the lamp south-east of the
## Pirámide, the lamp between them; the lens low behind his shoulder.
func shot_thumb() -> void:
	await setup_aim()
	_some_in(14)
	sim.order_shoot("c1")
	ff(0.45)
	var c0: Vector3 = actor_at("salvo")
	var b0: Vector3 = actor_at("c1")
	key_light(b0 + Vector3(-2.5, 3.2, -1.5), WARM, 3.0, 9.0)
	key_light(c0 + Vector3(-1.0, 2.6, 1.8), WARM, 1.6, 5.0)
	key_light(b0 + Vector3(2.8, 2.6, 2.0), COLD, 2.4, 9.0)
	var off: Vector3 = Vector3(_env("THUMB_DX", "-2.6").to_float(), _env("THUMB_DY", "1.05").to_float(), _env("THUMB_DZ", "-0.6").to_float())
	var pose := func(_u: float, _t: float) -> Dictionary:
		var c: Vector3 = actor_at("salvo")
		var b: Vector3 = actor_at("c1")
		return {"pos": c + off, "look": c.lerp(b, 0.55) + Vector3(0.0, 1.6, 0.0), "fov": float(_env("THUMB_FOV", "42")), "blur": 4.0,
			"focus": (c + off).distance_to(b) * 0.9, "bokeh": 0.7}
	await film("thumb", 0.5, pose)
