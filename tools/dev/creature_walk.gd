extends SceneTree
## Dev-only: an art-pack creature (cutout.gd, creature_body.gd) put through its paces on snow under a night sky (a cold
## moon, two warm lamps), filmed frame by frame: it walks, turns on the spot, stands, is alerted and rushes with its
## claws up, rears over someone, is shot, walks off, and is shot dead. Run (rendered, not headless):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/creature_walk.gd -- <out dir> [slot] [width] [height] [fps] [camera] [from s] [to s] [snow]
## camera: "close" (a low lens beside it, following), "game" (the game's orthographic view from above), "low" (a fixed
## low lens). The frames go to <out dir>/f0000.png ...; tools/dev/creature_walk.sh makes them a film.
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")

## The script: [until (s), state, speed (m/s along its heading), turn (rad/s), hits].
const SCRIPT := [
	[2.6, "prowl", 1.25, 0.0, 0],
	[4.2, "prowl", 0.0, 1.9, 0],
	[5.2, "prowl", 0.0, 0.0, 0],
	[6.6, "stalk", 2.2, 0.0, 0],
	[9.4, "stay", 0.0, 0.0, 0],
	[10.4, "driven", 3.0, 0.0, 1],
	[11.0, "driven", 3.0, 0.9, 1],
	[14.0, "dead", 0.0, 0.0, 3],
]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var slot_id: String = args[1] if args.size() > 1 else "cascarudo"
	var size := Vector2i(int(args[2]) if args.size() > 2 else 960, int(args[3]) if args.size() > 3 else 540)
	var fps: float = float(args[4]) if args.size() > 4 else 30.0
	var view: String = args[5] if args.size() > 5 else "close"
	var t_from: float = float(args[6]) if args.size() > 6 else 0.0
	var t_to: float = float(args[7]) if args.size() > 7 else 14.0
	var snow: float = float(args[8]) if args.size() > 8 else 0.45
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	_night(world)
	Cutout.weather(snow, 0.3 + 0.55 * snow)
	var beast: Node3D = Cutout.new()
	world.add_child(beast)
	beast.setup(ArtPack.slot(slot_id))
	beast.set_shadows(true)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var pos := Vector3(-4.0, 0.0, 0.0)
	var yaw: float = PI / 2.0
	var t: float = 0.0
	var dt: float = 1.0 / fps
	var frame: int = 0
	var move: float = 0.0
	while t < t_to:
		var step: Array = SCRIPT[SCRIPT.size() - 1]
		for s: Array in SCRIPT:
			if t < float(s[0]):
				step = s
				break
		var speed: float = float(step[2])
		var turn: float = float(step[3])
		yaw += turn * dt
		pos += Vector3(sin(yaw), 0.0, cos(yaw)) * speed * dt
		move = move_toward(move, 1.0 if speed > 0.0 else 0.0, dt / 0.25)
		beast.pose({"root": pos, "offset": Vector3.ZERO, "yaw": yaw, "phase": 0.0, "move": move, "run": 0.0, "crouch": 0.0,
			"lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t, "camera": cam,
			"speed": speed, "state": str(step[1]), "hits": int(step[4])})
		var at: Vector3 = pos + Vector3(0, 1.4, 0)
		match view:
			"game":
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.size = 16.0
				var cy: float = deg_to_rad(35.0)
				var cp: float = deg_to_rad(52.0)
				cam.position = at + Vector3(sin(cy) * cos(cp), sin(cp), cos(cy) * cos(cp)) * 40.0
				cam.look_at(at, Vector3.UP)
			"head":
				# low, three-quarter on its head and front claws
				cam.fov = 30.0
				var fwd2 := Vector3(sin(yaw), 0.0, cos(yaw))
				var side2 := Vector3(cos(yaw), 0.0, -sin(yaw))
				var head: Vector3 = pos + fwd2 * 1.6 + Vector3(0, 1.0, 0)
				cam.position = head + fwd2 * 4.2 - side2 * 2.6 + Vector3(0, -0.45, 0)
				cam.look_at(head + Vector3(0, 0.3, 0), Vector3.UP)
			"low":
				cam.fov = 38.0
				cam.position = Vector3(1.0, 1.1, 9.0)
				cam.look_at(Vector3(0.5, 1.2, 0), Vector3.UP)
			_:
				cam.fov = 34.0
				var side := Vector3(cos(yaw), 0.0, -sin(yaw))
				var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
				cam.position = cam.position.lerp(pos + side * 7.5 + fwd * 4.0 + Vector3(0, 1.3, 0), 1.0 if frame == 0 else 0.06)
				cam.look_at(at, Vector3.UP)
		await process_frame
		if t >= t_from:
			await RenderingServer.frame_post_draw
			var im: Image = vp.get_texture().get_image()
			im.save_png(out.path_join("f%04d.png" % frame))
			frame += 1
		t += dt
	print("frames ", frame, " in ", out)
	quit()

## Snow on the ground under a night sky: a cold moon, two warm street lamps, the sky's fill.
func _night(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.045, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.36, 0.44, 0.62)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.13, 0.2)
	e.fog_density = 0.012
	env.environment = e
	world.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.45
	moon.rotation = Vector3(-0.95, -0.6, 0)
	moon.shadow_enabled = true
	world.add_child(moon)
	for at: Vector3 in [Vector3(6, 5.5, -5), Vector3(-9, 5.5, 6)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.74, 0.44)
		lamp.light_energy = 3.2
		lamp.omni_range = 26.0
		lamp.position = at
		lamp.shadow_enabled = true
		world.add_child(lamp)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.84, 0.9)
	m.roughness = 0.95
	ground.material_override = m
	world.add_child(ground)
