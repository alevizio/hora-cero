extends SceneTree
## Dev-only: films a cascarudo on the Plaza de Mayo (the operation "plaza", the game's own scene and rules), frame by
## frame, for a look at its walk (a lens to the south of it, its left side to us): it prowls west along the middle of a
## walk (clear of the benches either side), stops and stands, senses a man out in the snow behind it (a shudder), turns,
## rushes him (towards us) with its claws up and knocks him down, and rears over him. Run (rendered):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --script ../tools/dev/plaza_film.gd -- <out dir> [seconds] [camera: low | game]
## then: ffmpeg -framerate 30 -i <out dir>/f%04d.png -c:v libx264 -pix_fmt yuv420p -crf 20 film.mp4
const Missions = preload("res://scripts/missions.gd")
const DT: float = 1.0 / 30.0
var main: Node3D
var sim: RefCounted

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var seconds: float = float(args[1]) if args.size() > 1 else 8.0
	var view: String = args[2] if args.size() > 2 else "low"
	DirAccess.make_dir_recursive_absolute(out)
	Missions.choose("plaza", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	sim = main.sim
	main.hud.hints_enabled = false
	for i in range(3): await process_frame
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	main.hud.visible = false
	main.hud.overlay.hide()
	# two and a half minutes in, everyone kept warm till then
	while float(sim.time) < 150.0:
		ff(2.0)
		for q: Dictionary in sim.people():
			q.exposure = minf(float(q.exposure), 0.3)
			q.panic = {}
		for u: Dictionary in sim.units: u.exposure = 0.0
	var beasts: Dictionary = {}
	for g: Dictionary in sim.guards:
		if bool(g.get("creature", false)):
			if str(g.state) == "waiting": sim._creature_enters(g, true)
			beasts[str(g.id)] = g
	for id: String in ["c2", "c3"]: place(beasts[id], Vector2(60.0, 60.0 + (40.0 if id == "c3" else 0.0)))
	# the man it will find, and nobody else near
	var man: Dictionary = {}
	for q: Dictionary in sim.people():
		if str(q.get("group", "")) == "piramide-e": man = q if man.is_empty() else man
	for q: Dictionary in sim.people():
		if q != man and Vector2(float(q.x), float(q.y)).distance_to(Vector2(176.0, 92.0) * 32.0) < 30.0 * 32.0:
			q.x = 120.0 * 32.0
			q.y = 60.0 * 32.0
			q.path = []
	# he stands out in the snow off the walk, behind it as it goes (it is kept from him till it has walked a while)
	var man_at := Vector2(179.5, 91.5)
	man.x = man_at.x * 32.0
	man.y = man_at.y * 32.0
	man.path = []
	var c1: Dictionary = beasts.c1
	place(c1, Vector2(181.0, 84.0))
	c1.angle = PI
	for u: Dictionary in sim.units:
		u.x = 60.0 * 32.0
		u.y = 120.0 * 32.0
		u.path = []
	ff(0.2)
	main.set_process(false)
	# the picture only: the creatures' rings and the line of their rush (the game's marks over the scene) left out
	var marks: Variant = main.world.structures.get("creatures") if main.world.structures != null else null
	if marks != null and (marks as Node).get("marks") != null: (marks.marks as Node3D).visible = false
	main.world.draw_vision = false
	var cam: Camera3D = main.camera
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40.0
	cam.near = 0.3
	cam.far = 400.0
	var t: float = 0.0
	var frame: int = 0
	var loosed: bool = false
	var look := Vector3(181.0, 1.4, 84.0)
	# its walk: west along the middle of the walk (the benches at z 78.2 and 89.8 well clear of its legs); then it
	# senses him, behind it
	c1.path = [Vector2(170.0, 84.0) * 32.0, Vector2(166.5, 88.0) * 32.0]
	c1.think = 99.0
	sim._set_state(c1, "prowl")
	while t < seconds:
		if not loosed and t > seconds * 0.42:
			# let it choose for itself: it senses him
			loosed = true
			c1.think = 0.0
		if str(man.state) == "crowd":
			# he stands there, out in the snow
			man.x = man_at.x * 32.0
			man.y = man_at.y * 32.0
			man.path = []
		ff(DT)
		var at: Vector3 = Vector3(float(c1.x) / 32.0, 1.4, float(c1.y) / 32.0)
		look = look.lerp(at, 0.04)
		if view == "game":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 26.0
			cam.position = look + Vector3(sin(deg_to_rad(-40.0)) * cos(deg_to_rad(52.0)), sin(deg_to_rad(52.0)), cos(deg_to_rad(-40.0)) * cos(deg_to_rad(52.0))) * 55.0
		else:
			cam.position = look + Vector3(1.0, 1.2, 11.0)
		cam.look_at(look, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var im: Image = root.get_viewport().get_texture().get_image()
		im.save_png(out.path_join("f%04d.png" % frame))
		frame += 1
		t += DT
	print("frames ", frame, " c1 ", c1.state, " man ", man.state)
	Missions.choose("plaza", false)
	quit()

func ff(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		sim.update(DT)
		main.world.update_visuals(DT)

func place(actor: Dictionary, at: Vector2) -> void:
	actor.x = at.x * 32.0
	actor.y = at.y * 32.0
	actor.path = []
	actor.think = 0.0
