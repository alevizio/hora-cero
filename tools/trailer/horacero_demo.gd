extends SceneTree
## Hora Cero gameplay demonstration (dev tool, not shipped): the real game, played to a win by the scripted plans of
## tests/plaza_playthrough.gd and riachuelo_playthrough.gd (horacero_plans.gd, given through the HUD's own
## select-and-perform), recorded with its HUD, its Spanish UI and its own sound by Godot's movie writer, for the comic's
## rights holders to see what the game really is. From the launch screen: JUGAR, the briefing, the level played out,
## the end report.
##   tools/trailer/horacero_demo.sh <timeline|record> <plaza|riachuelo> <out dir> [w h]
## timeline: the level played through without drawing (a step of the rules at a time, as the recording takes them),
##   printing what happens and when: the plan's orders, the snow, everybody's state, the cascarudos, the falls.
## record: the movie (<out>/<part>.avi, 30 fps), the camera kept as a player keeps it: on whoever has something to do,
##   the key moments held at the game's own speed and the waits between them run 2 or 3 times as fast (each drawn frame
##   then two or three steps of the rules: their sound is heard as it happens). It prints "MARK <name> <frame>" and
##   "SPEED <k> <frame>" (movie frames) for the edit, which tags the fast stretches.
## Juan Salvo, on the plaza, does what the plan has him do (the first cascarudo driven off by the tram, the second at the
## Casa Rosada's gates, the two who ran there led to the colectivo) and one thing more, as a player would: whoever has
## fallen in the snow and is in reach, he carries in.
## VARIANT=juan (the recording's): Biguá leaves the two by the Casa Rosada for later (the plan's step for them
## skipped), so that the snow takes them, and Juan Salvo, who alone can cross it, carries them in.
const Missions = preload("res://scripts/missions.gd")
const Front = preload("res://scripts/three_d/front.gd")
const DT: float = 1.0 / 30.0

var mode: String = "timeline"
var part: String = "plaza"
var out: String = ""
var main: Node3D
var sim: RefCounted
var plan: RefCounted
var speed: int = 1
var frames: int = 0
## The camera: on whom, until when (game time), and why.
var focus_id: String = ""
var focus_until: float = 0.0
var cam_at: Vector2 = Vector2.INF
var cam_zoom: float = 26.0
var want_zoom: float = 26.0
## The moments kept at the game's own speed: [from, to] in game time, and who the camera is on (filled from the
## timeline: see PLAZA_MOMENTS).
var moments: Array = []
var last_steps: Dictionary = {}
var states: Dictionary = {}
var snow: String = ""
var carry: Dictionary = {"state": 0, "who": ""}
var play_limit: float = 9999.0
var base_yaw: float = 999.0

func _init() -> void:
	call_deferred("boot")

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func boot() -> void:
	var args := OS.get_cmdline_user_args()
	mode = args[0] if args.size() > 0 else "timeline"
	part = args[1] if args.size() > 1 else "plaza"
	out = args[2] if args.size() > 2 else "/tmp/horacero_demo"
	play_limit = float(_env("PLAY_LIMIT", "9999"))
	DirAccess.make_dir_recursive_absolute(out)
	Front.force = 1
	if part == "riachuelo":
		# straight to the second level, as a player who has won the plaza comes back to it
		var cfg := ConfigFile.new()
		cfg.load(Missions.progress_path())
		cfg.set_value("won", "plaza", true)
		cfg.set_value("best_plaza", "time", 208.0)
		cfg.save(Missions.progress_path())
		Missions.choose("riachuelo", true, Missions.progress_path())
	RenderingServer.frame_post_draw.connect(func() -> void: frames += 1)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.world.adaptive_quality = false
	sim = main.sim
	for i in range(4): await process_frame
	if mode == "timeline":
		await timeline()
	else:
		await record()
	print("DONE ", mode, " ", part, " frames ", frames)
	quit()

func mark(name: String) -> void:
	print("MARK %s %d t=%.2f" % [name, frames, float(sim.time)])

func set_speed(k: int) -> void:
	if k == speed: return
	speed = k
	print("SPEED %d %d t=%.2f" % [k, frames, float(sim.time)])

# ------------------------------------------------------------------ the launch screen and the briefing
func launch_and_brief() -> void:
	mark("launch")
	for i in range(int(float(_env("LAUNCH_S", "5.0")) * 30.0)): await process_frame
	# JUGAR: the item lit (as under the finger), a beat, then pressed
	var item: Control = main.front.items["continue"]
	item.grab_focus()
	for i in range(18): await process_frame
	mark("play_pressed")
	main._front_command("continue")
	for i in range(6): await process_frame
	mark("briefing")
	print("briefing: '%s' / '%s'" % [main.hud.modal_title.text.replace("\n", " "), main.hud.begin_button.text])
	for i in range(int(float(_env("BRIEF_S", "9.0")) * 30.0)): await process_frame
	mark("begin")
	main.hud._primary_pressed()
	for i in range(2): await process_frame
	if sim.paused: sim.toggle_pause()

# ------------------------------------------------------------------ playing
func start_plan() -> void:
	plan = load(get_script().resource_path.get_base_dir().path_join("horacero_plans.gd")).new(sim, part)
	plan.chatty = true
	for who: String in plan.step: last_steps[who] = int(plan.step[who])

## One step of the rules as the recording takes it: the plan's orders, the rules, the plan's way-points.
func _orders() -> void:
	_variant()
	plan.tick()
	_juan_carry()

func _step(draw_side: bool) -> void:
	_orders()
	if not draw_side:
		sim.update(DT)
		main.world.update_visuals(DT)
	plan.trails()

func timeline() -> void:
	# the launch screen and the briefing for exactly as many frames as the recording gives them (the people of the
	# square go on with their own business on the launch screen: the same frames, the same night)
	await launch_and_brief()
	start_plan()
	main.set_process(false)
	var next_print: float = 0.0
	while sim.phase == "playing" and float(sim.time) < minf(play_limit, 700.0):
		_step(false)
		_watch()
		if float(sim.time) >= next_print:
			next_print += 10.0
			print("  t=%6.1f snow %s counts %s" % [sim.time, sim.snow_level(), str(sim.rescue_counts())])
	print("END %s t=%.1f phase %s counts %s" % [part, sim.time, sim.phase, str(sim.rescue_counts())])
	main.set_process(true)

## What happens, printed as it happens: the snow, people's states, the cascarudos, the units' away/back and actions.
func _watch() -> void:
	var lvl: String = sim.snow_level() if part == "plaza" else ""
	if lvl != snow:
		print("  t=%6.1f SNOW %s" % [sim.time, lvl])
		snow = lvl
	for g: Dictionary in sim.guards:
		var key: String = str(g.id)
		var st: String = str(g.state)
		if states.get(key, "") != st:
			if bool(g.get("creature", false)) or st in ["fallen", "safe", "lost", "dead", "follow", "coming", "panic"]:
				var p: Vector2 = sim.position_of(g) / 32.0
				print("  t=%6.1f %s %s -> %s at (%.0f, %.0f)" % [sim.time, key, states.get(key, "-"), st, p.x, p.y])
			states[key] = st
	for u: Dictionary in sim.units:
		var key2: String = "u:" + str(u.id)
		var st2: String = "away" if bool(u.get("away", false)) else ("carrying " + str(u.carrying) if str(u.get("carrying", "")) != "" else "here")
		if states.get(key2, "") != st2:
			print("  t=%6.1f %s %s" % [sim.time, u.id, st2])
			states[key2] = st2

const ROSADA_WATCH := Vector2(232.0, 107.0)

func _variant() -> void:
	if part != "plaza" or _env("VARIANT", "") != "juan": return
	# Biguá, the Belgrano's group in, would go out for the Casa Rosada's two: he waits for the lull instead
	if int(plan.step.bigua) == 2 and not bool(carry.get("skipped", false)):
		var g: Array = plan._group("belgrano")
		if plan._all(g, "safe") and plan.k.arrived("bigua"):
			plan.step.bigua = 5
			carry["skipped"] = true
			print("  t=%6.1f bigua: leaves the Casa Rosada's two for later" % sim.time)
	# Juan Salvo, the cascarudo on Rivadavia driven off, goes to stand by the two left out by the Casa Rosada (instead
	# of the Banco's porch): the snow cannot touch him, and when they go down he is there to carry them in
	if int(plan.step.salvo) == 5 and not bool(carry.get("watch", false)):
		carry["watch"] = true
		plan.step.salvo = 6
		plan.k.order("salvo", "move", ROSADA_WATCH * 32.0)
		print("  t=%6.1f salvo: out to stand by the Casa Rosada's two" % sim.time)

## Juan Salvo, idle between the plan's orders, goes for whoever has fallen in the snow and is in reach, carries them in
## to the nearest cover and goes back to where the plan had him: what a player does with him.
func _juan_carry() -> void:
	if part != "plaza" or _env("JUAN_CARRY", "1") != "1": return
	var juan: Dictionary = sim.unit_by_id("salvo")
	if juan.is_empty() or bool(juan.get("away", false)): return
	match int(carry.state):
		0:
			if int(plan.step.salvo) < 1 or not plan.k.idle("salvo"): return
			var best: Dictionary = {}
			var best_d: float = 1e9
			for p: Dictionary in sim.people():
				if str(p.state) != "fallen" or str(p.get("carried_by", "")) != "": continue
				var d: float = sim.position_of(p).distance_to(sim.position_of(juan))
				if d < best_d: best_d = d; best = p
			if best.is_empty() or best_d > 60.0 * 32.0: return
			carry.who = str(best.id)
			plan.k.order("salvo", "pickup", carry.who)
			carry.state = 1
			print("  t=%6.1f salvo: goes for %s, fallen in the snow (%.0f m)" % [sim.time, carry.who, best_d / 32.0])
		1:
			if str(juan.get("carrying", "")) == carry.who and plan.k.idle("salvo"):
				var to: Vector2 = _nearest_cover(sim.position_of(juan))
				plan.k.order("salvo", "move", to)
				carry.state = 2
				print("  t=%6.1f salvo: carries %s in to (%.0f, %.0f)" % [sim.time, carry.who, to.x / 32.0, to.y / 32.0])
			elif plan.k.idle("salvo") and str(juan.get("carrying", "")) == "" and str(sim.guard_by_id(carry.who).state) != "fallen":
				carry.state = 0
		2:
			if plan.k.idle("salvo"):
				plan.k.order("salvo", "drop", sim.position_of(juan))
				carry.state = 3
				print("  t=%6.1f salvo: sets %s down under cover" % [sim.time, carry.who])
		3:
			if plan.k.idle("salvo") and str(juan.get("carrying", "")) == "":
				# back to where the plan had him (along Rivadavia, toward the tram), unless somebody else is down
				carry.state = 0
				var other: bool = false
				for p: Dictionary in sim.people():
					if str(p.state) == "fallen" and str(p.get("carried_by", "")) == "": other = true
				if not other and int(plan.step.salvo) <= 1:
					plan.k.order("salvo", "move", Vector2(165.0, 45.0) * 32.0)
					print("  t=%6.1f salvo: back to Rivadavia" % sim.time)
				elif not other and bool(carry.get("watch", false)):
					for p2: Dictionary in sim.people():
						if str(p2.state) == "crowd":
							plan.k.order("salvo", "move", ROSADA_WATCH * 32.0)
							print("  t=%6.1f salvo: back to stand by the one still out" % sim.time)
							break

func _nearest_cover(from: Vector2) -> Vector2:
	var best: Vector2 = from
	var best_d: float = 1e12
	for s: Dictionary in sim.data.get("shelters", []):
		var at: Vector2 = sim.shelter_inside(s)
		var d: float = at.distance_to(from)
		if d < best_d: best_d = d; best = at
	return best

# ------------------------------------------------------------------ recording
func record() -> void:
	await launch_and_brief()
	start_plan()
	# PLAY_FROM: the level played on without drawing to that moment first (the rules have no chance in them: the same
	# orders give the same night, so a second recording picks up where a first one stopped)
	var from: float = float(_env("PLAY_FROM", "0"))
	if from > 0.0:
		main.set_process(false)
		while sim.phase == "playing" and float(sim.time) < from - 0.001:
			_step(false)
			_watch()
		main.set_process(true)
		print("  ff to t=%.2f" % sim.time)
	mark("play")
	cam_at = Vector2.INF
	var limit: float = minf(play_limit, 700.0)
	while sim.phase == "playing" and float(sim.time) < limit:
		var k: int = _wanted_speed()
		set_speed(k)
		# the extra steps of a fast stretch, then the one main.gd takes as it draws
		for i in range(k - 1):
			_step(false)
			_watch()
		_orders()
		_camera()
		await process_frame
		plan.trails()
		_watch()
	set_speed(1)
	mark("end_play")
	if part == "plaza" and sim.phase != "playing":
		# the closing of the level and its report
		for i in range(900):
			if main.hud.overlay.visible and main.hud.current_modal == "won": break
			await process_frame
		mark("report")
		print("report: '%s' | %s" % [main.hud.modal_title.text.replace("\n", " "), main.hud.modal_body.text.replace("\n", " | ")])
		for i in range(int(float(_env("REPORT_S", "8.0")) * 30.0)): await process_frame
	mark("end")

## The game's own speed inside the key moments (MOMENTS: "from,to,who,zoom[,yaw];..." in game time, who an id or
## "@x:z", yaw in degrees), two or three times as fast between them.
func _wanted_speed() -> int:
	var t: float = float(sim.time)
	for m: Array in _moments():
		if t >= float(m[0]) - 0.2 and t < float(m[1]): return 1
	var next: float = 1e9
	for m: Array in _moments():
		if float(m[0]) > t: next = minf(next, float(m[0]))
	# a short wait: twice as fast; a long one: three times
	return 2 if next - t < 12.0 else 3

func _moments() -> Array:
	if moments.is_empty():
		var spec: String = _env("MOMENTS", "")
		for chunk: String in spec.split(";", false):
			var p: PackedStringArray = chunk.split(",")
			moments.append([float(p[0]), float(p[1]), p[2] if p.size() > 2 else "", float(p[3]) if p.size() > 3 else 24.0,
				float(p[4]) if p.size() > 4 else 999.0])
	return moments

## The camera as a player keeps it, smoothly: inside a moment on whoever it names, else on whoever was last given
## something to do.
func _camera() -> void:
	var t: float = float(sim.time)
	var who: String = ""
	want_zoom = 26.0
	if base_yaw > 900.0: base_yaw = float(main.desired_yaw)
	var yaw: float = base_yaw
	for m: Array in _moments():
		if t >= float(m[0]) - 0.6 and t < float(m[1]) and str(m[2]) != "":
			who = str(m[2])
			want_zoom = float(m[3])
			# the view turned, as a player turns it with the HUD's arrows (the Cabildo's arcade faces the square)
			if float(m[4]) < 900.0: yaw = deg_to_rad(float(m[4]))
	main.desired_yaw = lerp_angle(float(main.desired_yaw), yaw, 0.05)
	if who == "":
		if t >= focus_until or focus_id == "":
			for id: String in plan.step:
				if int(plan.step[id]) != int(last_steps.get(id, 0)) and sim.unit_by_id(id).size() > 0:
					focus_id = id
					focus_until = t + 5.0
			for id2: String in plan.step: last_steps[id2] = int(plan.step[id2])
			if focus_id == "": focus_id = "benteveo"
		who = focus_id
	var target: Vector2
	if who.begins_with("@"):
		var xy: PackedStringArray = who.substr(1).split(":")
		target = Vector2(float(xy[0]), float(xy[1]))
	else:
		var a: Dictionary = sim.unit_by_id(who)
		if a.is_empty(): a = sim.guard_by_id(who)
		if a.is_empty(): return
		target = sim.position_of(a) / 32.0
	if not cam_at.is_finite(): cam_at = target
	cam_at = cam_at.lerp(target, 0.06 * float(speed))
	cam_zoom = lerpf(cam_zoom, want_zoom, 0.04)
	main.desired_target = Vector3(cam_at.x, 0, cam_at.y)
	main.desired_zoom = cam_zoom
