extends SceneTree
## Hora Cero playtest (dev tool, not shipped): the game played through as a player would, in the real 3D scene, from the
## launch screen to the end of the second level, photographed on the way to look at by eye.
##   launch screen -> PLAY -> the Plaza de Mayo's briefing -> BEGIN -> the plaza played out (the plan of
##   tests/plaza_playthrough.gd, given through the HUD's own select-and-perform) -> the debrief -> the real story's pages
##   -> NEXT OPERATION -> (the scene built again, as a reload does) -> Riachuelo's briefing -> BEGIN -> the crossing (the
##   plan of tests/riachuelo_playthrough.gd) -> the debrief.
## Run (rendered, not headless) from godot/, in Spanish, with the launch screen and a fresh player's user data:
##   HORACERO_LANG=es HORACERO_TITLE=1 XDG_DATA_HOME=<empty dir> \
##   xvfb-run -a -s "-screen 0 2000x1200x24" <godot> --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --resolution 1280x720 --script res://../tools/trailer/horacero_playtest.gd -- <out dir> [plaza|riachuelo|both]
## (the project's window override wins over --resolution: an override.cfg with the size, as horacero_run.sh does.)
## The game runs as a time-lapse: every drawn frame is STEPS steps of 1/30 s, the plan given its orders between steps.
## Pictures: <out>/<level>_<nnnn>_<mm.ss>.jpg every SHOT_EVERY seconds of game time (the camera on whoever is busy, as a
## player keeps it), a whole-map view every MAP_EVERY, and the screens on the way (launch, briefing, debrief, story).
## It prints what it watched for: "STUCK" (somebody with somewhere to go, not moving for 3 s), "SOLID" (somebody
## standing inside something solid of the rules), "HITCH" (a step of the rules and the visuals taking over 40 ms), the
## events of the run, and a summary per level.
const Missions = preload("res://scripts/missions.gd")
const Front = preload("res://scripts/three_d/front.gd")
const DT: float = 1.0 / 30.0
const STEPS: int = 5
var SHOT_EVERY: float = float(OS.get_environment("SHOT_EVERY")) if OS.get_environment("SHOT_EVERY") != "" else 2.0
var MAP_EVERY: float = float(OS.get_environment("MAP_EVERY")) if OS.get_environment("MAP_EVERY") != "" else 20.0

var out: String = ""
var main: Node3D
var sim: RefCounted
var plan: RefCounted
var level: String = ""
var shot_index: int = 0
var next_shot: float = 0.0
var next_map: float = 0.0
var next_watch: float = 0.0
var focus_id: String = ""
var focus_until: float = 0.0
## Where each actor was at the last watch, and since when it has not moved while it had somewhere to go.
var last_at: Dictionary = {}
var still_since: Dictionary = {}
var flagged: Dictionary = {}
var hitch_ms: Array[float] = []
var worst_ms: float = 0.0
var stuck_count: int = 0
var solid_count: int = 0

func _init() -> void:
	call_deferred("boot")

func frame() -> void:
	await process_frame

func boot() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/horacero_playtest"
	var which: String = args[1] if args.size() > 1 else "both"
	DirAccess.make_dir_recursive_absolute(out)
	Front.force = 1
	print("list ", Missions.LIST.map(func(e: Dictionary) -> String: return str(e.id)), " current ", Missions.current)
	if which == "riachuelo":
		# straight to the second level: the plaza marked as won in the progress file, as a player who won it has
		var cfg := ConfigFile.new()
		cfg.load(Missions.progress_path())
		cfg.set_value("won", "plaza", true)
		cfg.set_value("best_plaza", "time", 208.0)
		cfg.save(Missions.progress_path())
		Missions.choose("riachuelo", true, Missions.progress_path())
	await build()
	if which in ["plaza", "both"] and Missions.current == "plaza":
		await play_level("plaza")
		if which == "both":
			await story_to_next()
	if Missions.current == "riachuelo" and which in ["riachuelo", "both"]:
		if main == null or str(main.sim.data.get("id", "")) != "riachuelo": await build()
		await play_level("riachuelo")
	print("DONE playtest")
	quit()

func build() -> void:
	if main != null:
		main.queue_free()
		await frame()
		await frame()
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.world.adaptive_quality = false
	sim = main.sim
	for i in range(4): await frame()

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_jpg(out.path_join("%s_%04d_%s.jpg" % [level if level != "" else "menu", shot_index, name]), 0.86)
	shot_index += 1

## A few frames on (the scene drawn, the pages laid out), then a picture.
func hold(frames: int, name: String) -> void:
	for i in range(frames): await frame()
	await snap(name)

func play_level(id: String) -> void:
	level = id
	shot_index = 0
	# the launch screen: the scene behind it, the camera drifting
	print("LEVEL ", id, " landing on mode ", main.mode, " front visible ", main.front.visible)
	await hold(20, "launch")
	await hold(60, "launch_drift")
	print("launch: continue item '%s' / '%s'" % [main.front.items["continue"].caption, main.front.items["continue"].sub])
	main._front_command("continue")
	await hold(12, "briefing")
	print("briefing: '%s' / '%s'" % [main.hud.modal_title.text.replace("\n", " "), main.hud.begin_button.text])
	main.hud._primary_pressed()
	await hold(10, "begin")
	print("begin: phase ", sim.phase, " paused ", sim.paused, " camera ", main.desired_target, " zoom ", main.desired_zoom)
	plan = load(get_script().resource_path.get_base_dir().path_join("horacero_plans.gd")).new(sim, id)
	focus_id = ""
	focus_until = 0.0
	var fast: bool = OS.get_environment("PLAYTEST_FAST").contains(id)
	next_shot = SHOT_EVERY
	next_map = 4.0
	next_watch = 0.5
	last_at.clear(); still_since.clear(); flagged.clear()
	hitch_ms.clear(); worst_ms = 0.0
	stuck_count = 0; solid_count = 0
	var limit: float = 620.0
	while sim.phase == "playing" and float(sim.time) < limit:
		# (fast: the level played through without drawing, a second of it per frame)
		for i in range(30 if fast else STEPS):
			if sim.phase != "playing": break
			plan.tick()
			var t0: int = Time.get_ticks_usec()
			sim.update(DT)
			main.world.update_visuals(DT)
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			worst_ms = maxf(worst_ms, ms)
			if ms > 40.0: hitch_ms.append(ms)
			plan.trails()
			watch()
		if sim.phase != "playing": break
		plan.tick()
		if fast:
			# (a picture now and then all the same, the camera on whoever is busy)
			if float(sim.time) >= next_shot:
				next_shot += SHOT_EVERY
				player_camera()
				main._update_camera(1.0, true)
				await frame()
				await snap("%02d.%02d" % [floori(float(sim.time) / 60.0), int(sim.time) % 60])
			else:
				await frame()
			continue
		player_camera()
		await frame()
		if float(sim.time) >= next_map:
			next_map += MAP_EVERY
			await map_view()
		elif float(sim.time) >= next_shot:
			next_shot += SHOT_EVERY
			await snap("%02d.%02d" % [floori(float(sim.time) / 60.0), int(sim.time) % 60])
	print("END ", id, ": ", plan.k.summary() if id == "riachuelo" else "%s in %d:%02d %s" % [sim.phase, floori(float(sim.time) / 60.0), int(sim.time) % 60, str(sim.rescue_counts())], " badges ", plan.k.badges())
	print("watch ", id, ": stuck ", stuck_count, " solid ", solid_count, " hitches>40ms ", hitch_ms.size(), " worst step ", snappedf(worst_ms, 0.1), " ms")
	print("problems ", plan.k.problems)
	# the closing of the level: the debrief (after its closing scene, where it has one)
	for i in range(240):
		if main.hud.overlay.visible and main.hud.current_modal == "won": break
		await frame()
	await hold(30, "debrief")
	print("debrief: '%s' second '%s' first '%s'" % [main.hud.modal_title.text.replace("\n", " "), main.hud.second_button.text, main.hud.begin_button.text])
	print("debrief body: ", main.hud.modal_body.text.replace("\n", " | "))

## The real story's pages after the plaza, then NEXT OPERATION; the scene is built again as a reload would.
func story_to_next() -> void:
	var pages: int = 0
	while pages < 12:
		var before: String = main.hud.current_modal
		main.hud._second_pressed()
		await hold(8, "story%d" % pages)
		print("story %d: modal %s '%s' second '%s' current %s" % [pages, main.hud.current_modal, main.hud.modal_title.text.replace("\n", " "), main.hud.second_button.text, Missions.current])
		pages += 1
		if Missions.current != "plaza": break
		if before == "history" and main.hud.current_modal != "history": break
	print("next: current ", Missions.current, " unlocked ", Missions.unlocked("riachuelo", main.hud.progress), " resume_to ", Front.resume_to)
	level = "riachuelo"
	await build()

# ------------------------------------------------------------------ watching
func actors() -> Array:
	var list: Array = []
	for u: Dictionary in sim.units: list.append(u)
	# (on the plaza the people and the cascarudos are guards of the rules too)
	for g: Dictionary in sim.guards: list.append(g)
	return list

func watch() -> void:
	if float(sim.time) < next_watch: return
	next_watch += 0.5
	for a: Dictionary in actors():
		var id: String = str(a.id)
		var here: Vector2 = sim.position_of(a)
		var path: Array = a.get("path", [])
		var state: String = str(a.get("state", ""))
		var busy: bool = not path.is_empty() and not state in ["dead", "waiting", "away", "safe", "fallen", "lost"] and not bool(a.get("acting", false))
		if busy and last_at.has(id) and here.distance_to(last_at[id]) < 3.0:
			if not still_since.has(id): still_since[id] = float(sim.time)
			elif float(sim.time) - float(still_since[id]) > 3.0 and not flagged.has("stuck:" + id):
				flagged["stuck:" + id] = true
				stuck_count += 1
				print("STUCK %s t=%.1f at (%.1f, %.1f) m, state %s, %d way-points left, next (%.1f, %.1f)" % [id, sim.time, here.x / 32.0, here.y / 32.0, state, path.size(), Vector2(path[0]).x / 32.0, Vector2(path[0]).y / 32.0])
		else:
			still_since.erase(id)
		last_at[id] = here
		# standing in something solid of the rules (the tram, the shelters and the boat excepted)
		if state in ["dead", "waiting", "away", "lost"] or bool(a.get("aboard", false)) or bool(a.get("riding", false)): continue
		# (the river launch rides on the water, which is solid to walkers)
		if id == "launch": continue
		if a.has("shelter") and str(a.shelter) != "": continue
		if level == "plaza" and sim.vehicle_at(here) != "": continue
		if sim.climbing(a): continue
		if sim.is_blocked(here, 2.0):
			var key: String = "solid:%s:%d:%d" % [id, int(here.x / 64.0), int(here.y / 64.0)]
			if not flagged.has(key):
				flagged[key] = true
				solid_count += 1
				print("SOLID %s t=%.1f at (%.1f, %.1f) m, state %s" % [id, sim.time, here.x / 32.0, here.y / 32.0, state])

## The camera as a player keeps it: on whoever has just been given something to do, for a few seconds, then the next.
func player_camera() -> void:
	var t: float = float(sim.time)
	if t >= focus_until or focus_id == "":
		var order: Array = ["salvo", "benteveo", "hornero", "lechuza", "bigua"] if level == "plaza" else ["lechuza", "hornero", "bigua", "benteveo"]
		var start: int = (order.find(focus_id) + 1) % order.size()
		for j in range(order.size()):
			var id: String = order[(start + j) % order.size()]
			var u: Dictionary = sim.unit_by_id(id)
			if u.is_empty() or bool(u.get("away", false)): continue
			if not plan.k.idle(id) or j == order.size() - 1:
				focus_id = id
				break
		focus_until = t + 6.0
	var u2: Dictionary = sim.unit_by_id(focus_id)
	if u2.is_empty(): return
	var p: Vector2 = sim.position_of(u2) / 32.0
	main.desired_target = Vector3(p.x, 0, p.y)
	main.desired_zoom = 30.0

func map_view() -> void:
	var keep := [main.desired_target, main.desired_zoom]
	main._fit_camera()
	main._update_camera(1.0, true)
	await frame()
	await frame()
	await snap("map_%02d.%02d" % [floori(float(sim.time) / 60.0), int(sim.time) % 60])
	main.desired_target = keep[0]
	main.desired_zoom = keep[1]
	main._update_camera(1.0, true)

