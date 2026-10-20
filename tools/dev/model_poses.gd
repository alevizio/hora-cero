extends SceneTree
## Dev-only: a contact sheet of an art-pack model in the poses the game gives it (cutout.gd, rig_person.gd,
## creature_body.gd), on snow under a night light, seen from the game's camera (orthographic, 52 degrees down) and from
## low down. Run (rendered, not headless):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/model_poses.gd -- <out.png> <slot> [snow] [ink]
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const DT: float = 1.0 / 30.0
const CELL := Vector2i(420, 470)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var slot_id: String = args[1] if args.size() > 1 else "juan_salvo"
	var snow: float = float(args[2]) if args.size() > 2 else 0.5
	var s: Dictionary = ArtPack.slot(slot_id)
	var person: bool = str(s.kind) == "person"
	var poses: Array = _person_poses() if person else _creature_poses()
	var spacing: float = 3.2 if person else 7.5
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * poses.size(), CELL.y * 2)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	_night(world)
	Cutout.weather(snow, 0.25 + 0.5 * snow)
	var figures: Array = []
	for i: int in range(poses.size()):
		var c: Node3D = Cutout.new()
		world.add_child(c)
		c.setup(s)
		c.set_shadows(true)
		figures.append(c)
	# play each pose's history up to its moment
	var frames: int = 0
	for pose: Dictionary in poses: frames = maxi(frames, int(float(pose.t) / DT))
	var cams: Array = []
	for row: int in range(2):
		for i: int in range(poses.size()):
			var sub := SubViewport.new()
			sub.size = CELL
			sub.msaa_3d = Viewport.MSAA_4X
			sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			sub.world_3d = vp.world_3d
			root.add_child(sub)
			var cam := Camera3D.new()
			sub.add_child(cam)
			var at := Vector3(i * spacing, (0.9 if person else 1.6), 0)
			if row == 0:
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.size = 3.6 if person else 8.5
				var yaw: float = deg_to_rad(35.0)
				var pitch: float = deg_to_rad(52.0)
				cam.position = at + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 40.0
			else:
				cam.fov = 30.0
				var yaw2: float = deg_to_rad(-30.0)
				cam.position = at + Vector3(sin(yaw2), 0.25, cos(yaw2)) * (5.2 if person else 13.0)
			cam.look_at(at, Vector3.UP)
			cam.current = true
			cams.append(sub)
	for f: int in range(frames + 2):
		var t: float = f * DT
		for i: int in range(poses.size()):
			var pose: Dictionary = poses[i]
			var start: float = float(pose.t) - frames * DT
			var local: float = t + start
			var p: Dictionary = (pose.at as Callable).call(maxf(local, 0.0))
			p.merge({"root": Vector3(i * spacing, 0, 0), "offset": Vector3.ZERO, "yaw": float(pose.get("yaw", 0.6)), "phase": 0.0,
				"move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0,
				"covered": false, "clock": t, "camera": null, "speed": 0.0, "aim": 0.0, "pitch": 0.0, "recoil": -1.0, "hold": 0.0,
				"down": 0.0, "state": "", "hits": 0}, false)
			if p.has("speed"): p["phase"] = float(p.get("phase", 0.0)) if float(p.get("phase", 0.0)) != 0.0 else t * float(p.speed) / (1.2 if person else 2.2)
			figures[i].pose(p)
		await process_frame
	for f: int in range(4): await process_frame
	var sheet := Image.create(CELL.x * poses.size(), CELL.y * 2, false, Image.FORMAT_RGBA8)
	for k: int in range(cams.size()):
		var im: Image = (cams[k] as SubViewport).get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		var col: int = k % poses.size()
		var row: int = k / poses.size()
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	sheet.save_png(out)
	print("saved ", out, " poses: ", poses.map(func(x: Dictionary) -> String: return str(x.name)))
	quit()

func _person_poses() -> Array:
	return [
		{"name": "idle", "t": 1.0, "at": func(_t: float) -> Dictionary: return {}},
		{"name": "walk", "t": 1.3, "at": func(_t: float) -> Dictionary: return {"move": 1.0, "speed": 1.1}},
		{"name": "run", "t": 1.3, "at": func(_t: float) -> Dictionary: return {"move": 1.0, "speed": 2.62}},
		{"name": "crouch", "t": 1.0, "at": func(_t: float) -> Dictionary: return {"crouch": 1.0}},
		{"name": "sneak", "t": 1.25, "at": func(_t: float) -> Dictionary: return {"crouch": 1.0, "move": 1.0, "speed": 1.75}},
		{"name": "carry", "t": 1.4, "at": func(_t: float) -> Dictionary: return {"hold": 1.0, "move": 1.0, "speed": 1.56}},
		{"name": "aim", "t": 1.0, "at": func(_t: float) -> Dictionary: return {"aim": 1.0, "pitch": 0.05}},
		{"name": "fire", "t": 1.05, "at": func(t: float) -> Dictionary: return {"aim": 1.0, "pitch": 0.05, "recoil": maxf(t - 1.0, -1.0) if t >= 1.0 else -1.0}},
		{"name": "down", "t": 2.0, "at": func(_t: float) -> Dictionary: return {"down": 1.0}},
		{"name": "rising", "t": 2.75, "at": func(t: float) -> Dictionary: return {"down": 1.0 if t < 2.0 else 0.0}},
	]

func _creature_poses() -> Array:
	return [
		{"name": "stand", "t": 1.0, "at": func(_t: float) -> Dictionary: return {"state": "prowl"}},
		{"name": "crawl", "t": 1.2, "at": func(_t: float) -> Dictionary: return {"state": "prowl", "move": 1.0, "speed": 1.25}},
		{"name": "rush", "t": 1.1, "at": func(t: float) -> Dictionary: return {"state": "stalk" if t > 0.9 else "prowl", "move": 1.0, "speed": 2.2}},
		{"name": "rear", "t": 2.2, "at": func(t: float) -> Dictionary: return {"state": "stay" if t > 1.0 else "stalk"}},
		{"name": "shot", "t": 1.15, "at": func(t: float) -> Dictionary: return {"state": "driven" if t > 1.0 else "stalk", "hits": 1 if t > 1.0 else 0}},
		{"name": "rolling", "t": 1.7, "at": func(t: float) -> Dictionary: return {"state": "dead" if t > 1.0 else "stalk", "hits": 3 if t > 1.0 else 2}},
		{"name": "dead", "t": 4.0, "at": func(t: float) -> Dictionary: return {"state": "dead" if t > 1.0 else "stalk", "hits": 3 if t > 1.0 else 2}},
	]

## Snow on the ground under a night sky: a cold moon, a warm lamp, the sky's fill.
func _night(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.62)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.55
	moon.rotation = Vector3(-0.9, -0.5, 0)
	moon.shadow_enabled = true
	world.add_child(moon)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 2.2
	lamp.omni_range = 60.0
	lamp.position = Vector3(10, 6, 8)
	world.add_child(lamp)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.87, 0.92)
	m.roughness = 0.95
	ground.material_override = m
	world.add_child(ground)
