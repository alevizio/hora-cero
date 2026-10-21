extends SceneTree
## Dev-only, for the website: one character as the game builds it (operative.gd: a baked figure and its kit, or an
## art-pack model, posed and moved by the game's own code), turning once on the spot on a transparent background, under
## a warm key from the front left and a cool rim from behind: the frames of a looping turntable video
## (tools/dev/turntable_encode.py makes the site's files from them). A person stands at ease; a creature turns on its
## feet ("prowl" with nowhere to go: its legs shuffle round as it turns).
## Run (rendered, not headless):
##   godot --path godot --rendering-driver opengl3 --script ../tools/dev/turntable.gd -- \
##     <id> <look|-> <out dir> <frames> [width height view_m centre_y] [enemy 0/1] [kind|-] [state]
## e.g. hornero - /tmp/tt/hornero 96          salvo art:juan_salvo /tmp/tt/salvo 96 400 720 2.3 0.98
##      c1 art:cascarudo /tmp/tt/cascarudo 96 960 720 4.6 1.7 1 creature prowl
## The frames go to <out dir>/f_000.png ... (the first turn settles the model and is not kept).
const Operative = preload("res://scripts/three_d/operative.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var look: String = args[1] if args[1] != "-" else ""
	var out_dir: String = args[2]
	var frames: int = int(args[3])
	var width: int = int(args[4]) if args.size() > 4 else 360
	var height: int = int(args[5]) if args.size() > 5 else 720
	var view_m: float = float(args[6]) if args.size() > 6 else 2.3
	var centre_y: float = float(args[7]) if args.size() > 7 else 0.98
	var enemy: bool = args.size() > 8 and args[8] == "1"
	var kind: String = args[9] if args.size() > 9 and args[9] != "-" else ""
	var state: String = args[10] if args.size() > 10 else "patrol"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(width, height)
	root.transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.45, 0.5)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.35
	key.rotation = Vector3(-0.62, 0.55, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.74, 1.0)
	rim.light_energy = 1.15
	rim.rotation = Vector3(-0.35, PI + 0.4, 0)
	root.add_child(rim)
	var m := Operative.new()
	root.add_child(m)
	m.build(id, enemy, kind, look)
	var actor := {"id": id, "x": 0.0, "y": 0.0, "angle": PI * 0.5, "state": state, "stance": "walk", "alive": true,
		"hp": 100, "kind": kind, "look": look, "action": "", "acting": false, "action_time": 0.0, "action_total": 1.0,
		"order": {}, "carrying": "", "exposed": true, "suspicion": 0.0, "path": [], "ammo": 3, "cooldown": 0.0,
		"weapon_cooldown": 0.0, "creature": kind == "creature", "hits": 0, "target_id": ""}
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = view_m
	# a little above the middle of the figure, looking a touch down
	cam.rotation = Vector3(-0.1, 0, 0)
	cam.position = Vector3(0, centre_y + 10.0 * sin(0.1), 10.0 * cos(0.1))
	root.add_child(cam)
	cam.current = true
	var dt := 1.0 / 24.0
	# one turn to settle (the model eases toward its facing as the game's does), then the turn that is kept
	for f: int in range(frames * 2):
		var t := float(f) / float(frames)
		actor.angle = PI * 0.5 + TAU * t
		m.call("sync", actor, false, dt, false)
		await process_frame
		if f >= frames:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/f_%03d.png" % [out_dir, f - frames])
	print("turntable ", id, " ", frames, " frames")
	quit()
