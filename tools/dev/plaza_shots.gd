extends SceneTree
## Dev-only: photographs the Plaza de Mayo (the operation "plaza") from a list of camera positions, to look at it by eye.
## Run (rendered, not headless):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/plaza_shots.gd -- <probe file> [setup]
## The probe file has one shot per line: "name x z zoom yaw pitch [hud] [novision] [noactors] [far] [persp] [perf]
## [census]" (metres, degrees); the pictures go next to it as <name>.png. "persp": a lens (42 degrees) in place of the
## game's orthographic camera, `zoom` metres from a point 6 m over the target (the low views, where the orthographic
## view would look up from under the ground; with "ground" from a point 1.2 m over it, for the small things, with
## "eye" from 1.3 m); "brief": the briefing page over the view (the squad's cards, Juan Salvo's with his portrait);
## "perf": the frame's draw calls, objects and primitives; "census": what
## is in view, by node (frustum against bounds: drawn surfaces, and whether each casts a shadow); "solid": the buildings
## that would fade for somebody behind them kept whole (as the trailer's lens shots keep them); "asis": the camera
## where the game put it when the operation began (the numbers are ignored: the player's first view). Setups: "" (the start, a few seconds in: the first flakes),
## "hero" (half a minute in, the snow taking hold, the people still out in the square), "rescue" (Benteveo leading a
## group down the subte's stair in a wave, Hornero's tram at its stop, Biguá carrying someone in), "buried" (the end:
## the square buried, everyone under cover), "late" (four minutes in, mid-wave, a man down in the snow), "lit" (the
## hero's moment with the arcade's lanterns mended), "salvo" (the first lull: Juan Salvo in the square with his rifle up,
## the three cascarudos in: one going for a group by the Pirámide, one drawn to the tram's bell, one driven off by a shot),
## "carry" (Juan Salvo carrying a fallen woman in across the square in a wave, a cascarudo standing where it knocked her
## down), "arrive" (a few seconds before Juan Salvo comes in off Avenida de Mayo), "walk" (three minutes in: two of the
## squad have just crossed a lawn, their tracks fresh in the snow). Juan Salvo's and the cascarudos' models, two and a
## half minutes in: "palm" (a cascarudo standing under a palm by the Pirámide, Juan near it), "stroll" (Juan jogging across the square), "aim" (his rifle up at a cascarudo), "fire" (the moment
## after his shot: its kick and its flash; use the "quick" flag), "rush" (a cascarudo rushing the group by the Pirámide),
## "struck" (one rearing over a man it has just knocked down), "juan_down" (Juan knocked down by one), "dead" (one
## rolled over dead by his third shot). "quick": no settling frames before the picture (a flash lasts a few hundredths);
## "eye": a "persp" view looking at a point at eye height rather than 6 m up (close on a figure).
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
	Missions.choose("plaza", false)
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
	match setup:
		"hero":
			ff(26.0)
		"lit":
			# the hero's moment with the arcade's lanterns mended
			ff(26.0)
			sim.rigged["cabildo-lights"] = "lechuza"
		"rescue":
			# a wave on the square: Benteveo leads a group down the subte's north stair, the snow thick about them
			ff(88.0)
			var group: Array = []
			for p: Dictionary in sim.people():
				if str(p.get("group", "")) in ["piramide-w", "sw"]: group.append(p)
			put("benteveo", Vector2(15.2, 74.6), "walk")
			var rank := 0
			for p: Dictionary in group:
				p.x = (17.0 + 1.1 * float(rank)) * 32.0
				p.y = (74.4 + 0.5 * float(rank % 2)) * 32.0
				p.path = []
				p.exposure = 0.35 + 0.08 * float(rank)
				rank += 1
				sim._join(sim.unit_by_id("benteveo"), p)
			sim.select("benteveo")
			sim.move_to(Vector2(7.2, 74.6) * 32.0)
			ff(2.2)
		"late":
			ff(250.0)
		"arrive":
			ff(float(sim.unit_by_id("salvo").arrive.at) - 6.0)
		"salvo", "carry":
			# everyone kept warm while the clock runs to the first lull (the rules' own tests see to the cold)
			for k in range(int(126.0 / 2.0)):
				ff(2.0)
				for p: Dictionary in sim.people():
					p.exposure = minf(float(p.exposure), 0.3)
					p.panic = {}
				for u: Dictionary in sim.units: u.exposure = 0.0
			for g: Dictionary in sim.guards:
				if bool(g.get("creature", false)) and str(g.state) == "waiting": sim._creature_enters(g, true)
			var beasts: Dictionary = {}
			for g: Dictionary in sim.guards:
				if bool(g.get("creature", false)): beasts[str(g.id)] = g
			if setup == "salvo":
				# the tram at the middle stop, its bell about to be rung
				sim.vehicles.tram.x = float(sim.vehicle_spec("tram").stops[1])
				sim._beast_dirty = true
				put("hornero", sim.vehicle_rect("tram").get_center() / 32.0)
				put("salvo", Vector2(191.0, 83.0))
				place(beasts.c1, Vector2(204.0, 95.0))
				place(beasts.c2, Vector2(128.0, 58.0))
				place(beasts.c3, Vector2(214.0, 76.0))
				sim.select("salvo")
				ff(0.6)
				# the bell rung from the tram draws the one in the north; a shot drives the one in the south-east off
				var bell: Vector2 = sim.vehicle_rect("tram").get_center()
				sim.noise.append({"x": bell.x, "y": bell.y, "radius": 400.0, "ttl": 2.4, "max_ttl": 2.4, "kind": "bell"})
				sim._creature_shot(sim.unit_by_id("salvo"), beasts.c3, true)
				for n: Dictionary in sim.noise:
					if str(n.kind) == "rifle": n["beasts"] = true
				ff(1.6)
				main._arm("shoot", true)
			else:
				# a wave: Juan Salvo, taking no cold, carries in a woman a cascarudo knocked down by the palms
				sim.time = 236.0
				var down: Dictionary = {}
				for p: Dictionary in sim.people():
					if str(p.get("group", "")) == "south": down = p
				down.x = 106.0 * 32.0
				down.y = 108.0 * 32.0
				sim._person_falls(down)
				place(beasts.c1, Vector2(110.5, 106.0))
				sim._set_state(beasts.c1, "stay")
				beasts.c1.pause_left = 30.0
				beasts.c1.angle = PI * 0.9
				place(beasts.c2, Vector2(150.0, 122.0))
				place(beasts.c3, Vector2(214.0, 102.0))
				put("salvo", Vector2(104.6, 108.6))
				sim.select("salvo")
				sim.perform("pickup", str(down.id))
				ff(1.2)
				sim.perform("move", Vector2(60.0, 112.0) * 32.0)
				ff(2.0)
		"palm":
			# two and a half minutes in: a cascarudo standing under the palm south-east of the Pirámide, Juan Salvo
			# (selected) and the group by the Pirámide near it: what the crowns must not hide
			warm(150.0)
			var beasts: Dictionary = {}
			for g: Dictionary in sim.guards:
				if bool(g.get("creature", false)):
					if str(g.state) == "waiting": sim._creature_enters(g, true)
					beasts[str(g.id)] = g
			place(beasts.c2, Vector2(60.0, 60.0))
			place(beasts.c3, Vector2(70.0, 120.0))
			place(beasts.c1, Vector2(151.6, 101.4))
			sim._set_state(beasts.c1, "stay")
			beasts.c1.pause_left = 30.0
			beasts.c1.angle = PI * 1.1
			for q: Dictionary in sim.people(): (beasts.c1.spared as Dictionary)[str(q.id)] = sim.time + 60.0
			(beasts.c1.spared as Dictionary)["salvo"] = sim.time + 60.0
			put("salvo", Vector2(140.0, 98.0))
			sim.select("salvo")
			ff(0.3)
		"stroll", "aim", "fire", "rush", "struck", "juan_down", "dead":
			warm(150.0)
			var beasts: Dictionary = {}
			for g: Dictionary in sim.guards:
				if bool(g.get("creature", false)):
					if str(g.state) == "waiting": sim._creature_enters(g, true)
					beasts[str(g.id)] = g
			# out of the way unless wanted
			place(beasts.c2, Vector2(60.0, 60.0))
			place(beasts.c3, Vector2(70.0, 120.0))
			var group: Array = []
			for q: Dictionary in sim.people():
				if str(q.get("group", "")) == "piramide-e": group.append(q)
			var rank := 0
			for q: Dictionary in group:
				q.x = (151.0 + 1.3 * float(rank)) * 32.0
				q.y = (83.0 + 0.9 * float(rank % 2)) * 32.0
				q.path = []
				sim._set_state(q, "crowd")
				rank += 1
			sim.select("salvo")
			match setup:
				"stroll":
					place(beasts.c1, Vector2(214.0, 116.0))
					put("salvo", Vector2(174.0, 76.0))
					sim.select("salvo")
					sim.move_to(Vector2(200.0, 96.0) * 32.0)
					ff(1.6)
					# held at the long reach of a stride (use "quick")
					var op: Node3D = main.world.actors["salvo"]
					var widest: float = 0.0
					for k in range(18): widest = maxf(widest, stride(op))
					for k in range(24):
						if stride(op) >= widest * 0.95: break
				"aim", "fire", "dead":
					put("salvo", Vector2(170.0, 96.0))
					place(beasts.c1, Vector2(181.0, 104.0))
					beasts.c1.angle = PI * 0.95
					for q: Dictionary in group: (beasts.c1.spared as Dictionary)[str(q.id)] = sim.time + 60.0
					(beasts.c1.spared as Dictionary)["salvo"] = sim.time + 60.0
					beasts.c1.think = 9.0
					if setup == "dead":
						beasts.c1.hits = 2
					sim.select("salvo")
					sim.order_shoot("c1")
					if setup == "aim":
						# half way through taking aim (use "quick")
						ff(0.45)
					else:
						# to the shot itself
						var ammo: int = int(sim.unit_by_id("salvo").ammo)
						for i in range(90):
							ff(DT)
							if int(sim.unit_by_id("salvo").ammo) < ammo: break
						if setup == "dead": ff(1.4)
				"rush":
					place(beasts.c1, Vector2(167.0, 96.0))
					beasts.c1.angle = PI * 1.2
					put("salvo", Vector2(140.0, 70.0))
					for i in range(120):
						ff(DT)
						if str(beasts.c1.state) == "stalk": break
					ff(0.1)
				"struck":
					var man: Dictionary = group[0]
					man.x = 172.0 * 32.0
					man.y = 98.0 * 32.0
					place(beasts.c1, Vector2(178.0, 102.0))
					put("salvo", Vector2(150.0, 70.0))
					for i in range(240):
						ff(DT)
						if str(man.state) == "fallen": break
					ff(0.6)
				"juan_down":
					put("salvo", Vector2(172.0, 98.0))
					place(beasts.c1, Vector2(178.0, 102.0))
					for q: Dictionary in group: (beasts.c1.spared as Dictionary)[str(q.id)] = sim.time + 60.0
					for i in range(240):
						ff(DT)
						if bool(sim.unit_by_id("salvo").get("fallen", false)): break
					ff(1.2)
		"walk":
			# three minutes into the night, the snow lying deep: Hornero crosses the lawn north-west of the Pirámide,
			# Benteveo after him on a line of his own, both leaving their tracks in it
			ff(190.0)
			put("hornero", Vector2(118.0, 62.0), "walk")
			sim.select("hornero")
			sim.move_to(Vector2(100.0, 50.0) * 32.0)
			ff(9.0)
			put("benteveo", Vector2(121.0, 57.0), "walk")
			sim.select("benteveo")
			sim.move_to(Vector2(103.0, 64.0) * 32.0)
			ff(9.0)
		"buried":
			# the end of a night that went well: everyone brought in, the four under cover, and the snow burying the
			# square (the rules' clock moved on to the burial; nothing else is simulated)
			var spots: Array = ["catedral", "banco", "subte-n", "subte-s", "cabildo"]
			sim.rigged["cabildo-lights"] = "lechuza"
			var i := 0
			for p: Dictionary in sim.people():
				var shelter: Dictionary = sim.shelter_by_id(str(spots[i % spots.size()]))
				var at: Vector2 = sim.shelter_inside(shelter) + Vector2(float(i % 4) * 20.0 - 30.0, float(i / 4 % 2) * 14.0)
				p.x = at.x
				p.y = at.y
				p.path = []
				sim._set_state(p, "safe")
				p.shelter = str(shelter.id)
				i += 1
			var homes: Dictionary = {"hornero": "catedral", "lechuza": "cabildo", "benteveo": "subte-n", "bigua": "banco"}
			for id: String in homes:
				var at2: Vector2 = sim.shelter_inside(sim.shelter_by_id(homes[id]))
				put(id, at2 / 32.0 + Vector2(1.0, 0.4))
			sim.time = 486.0
			sim.buried_square = true
			sim.phase = "won"
			for k in range(20): main.world.update_visuals(DT)
	if not setup in ["fire", "struck", "juan_down", "rush", "stroll", "aim", "palm"]: ff(0.5)
	var lines: PackedStringArray = FileAccess.get_file_as_string(file).split("\n", false)
	for line: String in lines:
		if line.begins_with("#"): continue
		var p: PackedStringArray = line.split(" ", false)
		var flags: Array = []
		while p.size() > 0 and p[p.size() - 1] in ["hud", "novision", "noactors", "far", "perf", "persp", "census", "asis", "brief", "quick", "eye", "ground", "solid"]:
			flags.append(p[p.size() - 1])
			p.remove_at(p.size() - 1)
		if p.size() < 6: continue
		main.hud.visible = "hud" in flags or "brief" in flags
		if "brief" in flags: main.hud.show_modal("briefing")
		else: main.hud.overlay.hide()
		for id: Variant in main.world.actors: (main.world.actors[id] as Node3D).visible = not "noactors" in flags
		main.world.draw_vision = not "novision" in flags
		if not "asis" in flags:
			main.desired_target = Vector3(float(p[1]), 0, float(p[2])); main.target = main.desired_target
			main.desired_zoom = float(p[3]); main.zoom = float(p[3])
			main.desired_yaw = deg_to_rad(float(p[4])); main.yaw = main.desired_yaw
			main.pitch = deg_to_rad(float(p[5]))
		main._update_camera(1.0, true)
		var env: Environment = (main.world.atmosphere.environment as WorldEnvironment).environment
		var fog0: Vector2 = Vector2(env.fog_depth_begin, env.fog_depth_end)
		if "persp" in flags:
			main.set_process(false)
			var yaw := deg_to_rad(float(p[4]))
			var pitch := deg_to_rad(float(p[5]))
			var look := Vector3(float(p[1]), 1.3 if "eye" in flags else (1.2 if "ground" in flags else 6.0), float(p[2]))
			main.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			main.camera.fov = 42.0
			main.camera.near = 0.3
			main.camera.far = 1000.0
			main.camera.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(p[3])
			main.camera.look_at(look, Vector3.UP)
		if "far" in flags:
			main.set_process(false)
			main.camera.position += main.camera.global_transform.basis.z * 90.0
			main.camera.far = 400.0
			env.fog_depth_begin += 90.0
			env.fog_depth_end += 90.0
		# "solid": the buildings that fade when somebody stands behind them kept whole (as the trailer's lens shots do)
		var aside: Array = []
		var site: Node = main.world.get("structures")
		if "solid" in flags and site != null and "faders" in site:
			aside = (site.faders as Array).duplicate()
			for f: Dictionary in aside:
				f.alpha = 1.0
				f.want = 1.0
				for mat: Material in f.mats:
					if mat is ShaderMaterial: (mat as ShaderMaterial).set_shader_parameter("fade", 1.0)
					elif mat is StandardMaterial3D: (mat as StandardMaterial3D).albedo_color.a = 1.0
			(site.faders as Array).clear()
		# (long enough for the buildings that fade when somebody stands behind them to settle for this camera)
		# (quick: the game held still for the picture, as the last frame left it)
		if "quick" in flags:
			main.set_process(false)
			if main.hud.visible: main.hud.refresh()
		for i in range(1 if "quick" in flags else 14):
			if not "quick" in flags: main.world.update_visuals(DT)
			await tick()
		if "perf" in flags:
			await RenderingServer.frame_post_draw
			print("perf %s: draw calls %d, objects %d, primitives %d" % [p[0], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		if "census" in flags: census(p[0])
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(file.get_base_dir().path_join(p[0] + ".png"))
		if not aside.is_empty(): (site.faders as Array).append_array(aside)
		env.fog_depth_begin = fog0.x
		env.fog_depth_end = fog0.y
		main.camera.far = 160.0
		main.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		main.set_process(true)
		print("shot ", p[0])
	Missions.choose("plaza", false)
	quit()

## One frame on, and how far apart a model's feet are (its skeleton's), to catch a stride at its longest.
func stride(op: Node3D) -> float:
	ff(DT)
	var rig: Variant = op.cutout.rig if op.cutout != null else null
	if rig == null: return 0.0
	var sk: Skeleton3D = rig.skel
	return sk.get_bone_global_pose(int(rig.roles.foot_l)).origin.distance_to(sk.get_bone_global_pose(int(rig.roles.foot_r)).origin)

## The clock run on to `until`, everyone kept warm (the rules' own tests see to the cold).
func warm(until: float) -> void:
	while float(sim.time) < until - 0.01:
		ff(minf(2.0, until - float(sim.time)))
		for q: Dictionary in sim.people():
			q.exposure = minf(float(q.exposure), 0.3)
			q.panic = {}
		for u: Dictionary in sim.units: u.exposure = 0.0

func ff(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		sim.update(DT)
		main.world.update_visuals(DT)

func place(actor: Dictionary, at: Vector2) -> void:
	actor.x = at.x * 32.0
	actor.y = at.y * 32.0
	actor.path = []
	actor.think = 0.0

func put(id: String, at: Vector2, stance: String = "walk") -> void:
	var u: Dictionary = sim.unit_by_id(id)
	u.x = at.x * 32.0
	u.y = at.y * 32.0
	u.stance = stance
	u.path = []

## What the camera has in view, by node (its bounds in the frustum): how many objects, surfaces and shadow casters
## under each top-level name, the most first.
func census(label: String) -> void:
	var planes: Array[Plane] = main.camera.get_frustum()
	var tally: Dictionary = {}
	var stack: Array[Node] = [main.world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children(): stack.append(c)
		if not n is GeometryInstance3D or not (n as Node3D).is_visible_in_tree(): continue
		var gi := n as GeometryInstance3D
		var box: AABB = gi.global_transform * gi.get_aabb()
		var inside := true
		for pl: Plane in planes:
			var far_corner := Vector3(box.end.x if pl.normal.x < 0.0 else box.position.x, box.end.y if pl.normal.y < 0.0 else box.position.y, box.end.z if pl.normal.z < 0.0 else box.position.z)
			if pl.is_point_over(far_corner): inside = false
		if not inside: continue
		var surfaces := 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null: surfaces = (gi as MeshInstance3D).mesh.get_surface_count()
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null: surfaces = (gi as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		var key := str(gi.name).rstrip("0123456789")
		var parent := gi.get_parent()
		if parent != null and parent.name != "PlazaGeometry" and parent != main.world: key = str(parent.name).rstrip("0123456789") + "/" + key
		var t: Array = tally.get(key, [0, 0, 0])
		t[0] += 1
		t[1] += surfaces
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: t[2] += surfaces
		tally[key] = t
	var keys: Array = tally.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(tally[a][1]) > int(tally[b][1]))
	var total := [0, 0, 0]
	for key: String in keys:
		for i: int in range(3): total[i] += int(tally[key][i])
	print("census %s: %d objects, %d surfaces, %d casting" % [label, total[0], total[1], total[2]])
	for key: String in keys.slice(0, 40):
		print("  %-40s %4d objects %4d surfaces %4d casting" % [key, int(tally[key][0]), int(tally[key][1]), int(tally[key][2])])
