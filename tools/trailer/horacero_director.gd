extends SceneTree
## Hora Cero trailer director (dev tool, not shipped): camera moves and gameplay for the trailer, run under Godot's movie
## writer, one take per run, in Spanish:
##   tools/trailer/horacero_run.sh <shot> 1920 1080 <outdir>      (1080 1920 for the upright cut)
## Every frame the process draws is recorded, so each take prints "MARK <name> <first> <last>" (frame numbers in the
## movie) for the editor to cut on. "probe" saves stills for framing instead (PROBE_SETUP names a setup_ function).
## Two cameras: the game's own (orthographic, [x, z, zoom, yaw, pitch] in metres and degrees, the HUD over it when
## wanted) and a lens for the low, wide views ([x, z, distance, yaw, pitch, look height, fov]: from `distance` metres
## off the point `look height` over (x, z)). Yaw 0 looks north from the south, 90 looks west from the east.
## The gameplay takes are real play: the scripted wins of tests/plaza_playthrough.gd and riachuelo_playthrough.gd
## (horacero_plans.gd) run from the start and fast-forwarded to the moment, or a setup that stages one (after
## tools/dev/plaza_shots.gd), and then the rules run on live while the camera rolls.
const Missions = preload("res://scripts/missions.gd")
const DT: float = 1.0 / 30.0
var Plans: GDScript
var main: Node3D
var sim: RefCounted
var plan: RefCounted = null
var frame: int = 0
var take_start: int = 0
var level: String = "plaza"
## The upright frame (a story or a reel): the shots are framed differently for it.
var portrait: bool = false
## TAKE_MAX (seconds) cuts a take short without changing its camera move.
var take_max: int = 0
## The lens camera's pose while a lens shot rolls ([] for the game's own camera). A camera of its own, made current
## for the lens shots: main.gd goes on steering the game's camera every frame, out of the picture.
var lens: Array = []
var lens_cam: Camera3D
## Keep the cold off everyone (and the panic) while a staged moment is set and filmed.
var warm_all: bool = false
## Marks over the ground (the plan's rings and paths) off the picture.
var no_ink: bool = true
var keep_notice: bool = false
## The order's marks (a queued shot's reticle and line of fire) off the lens stills.
var hide_marks: bool = false

func _init() -> void:
	call_deferred("boot")

func tick() -> void:
	frame += 1
	await process_frame

func boot() -> void:
	Plans = load(get_script().resource_path.get_base_dir().path_join("horacero_plans.gd"))
	var args := OS.get_cmdline_user_args()
	var shot: String = args[0] if args.size() > 0 else "open"
	portrait = root.size.y > root.size.x
	if OS.get_environment("TAKE_MAX") != "": take_max = int(round(float(OS.get_environment("TAKE_MAX")) / DT))
	level = "riachuelo" if shot.begins_with("ria") or OS.get_environment("PROBE_LEVEL") == "riachuelo" else "plaza"
	Missions.choose(level, false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	if OS.get_environment("LOD_OFF") == "1": root.mesh_lod_threshold = 0.0
	if main.world.audio != null and OS.get_environment("TRAILER_VOICES") == "0": main.world.audio.voices_on = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://trailer_progress.cfg"))
	main.hud.progress_path = "user://trailer_progress.cfg"
	main.hud.load_progress()
	sim = main.sim
	main.hud.hints_enabled = false
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	lens_cam = Camera3D.new()
	lens_cam.name = "TrailerLens"
	main.add_child(lens_cam)
	main.camera.current = true
	for i in range(3): await tick()
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	main.hud.overlay.hide()
	main.hud.visible = false
	main.world.draw_vision = false
	await call("shot_" + shot)
	print("DONE ", shot, " frames ", frame)
	quit()

## Right before the frame is drawn (after every _process): the HUD's passing words off, the lens camera put in place.
func _pre_draw() -> void:
	var ink: Variant = main.world.get("overlays")
	if ink is Node3D: (ink as Node3D).visible = not no_ink
	var hud: Control = main.hud
	var hide: Array = ["hint_label", "hint_plate", "toast", "toast_plate"]
	if not keep_notice: hide += ["notice", "notice_plate"]
	for name: String in hide:
		var node: Variant = hud.get(name)
		if node is CanvasItem: (node as CanvasItem).visible = false
	var site: Variant = main.world.get("structures")
	if site is Node and "creatures" in site and site.creatures != null and site.creatures.marks != null:
		(site.creatures.marks as Node3D).visible = lens.is_empty()
	if hide_marks and not lens.is_empty():
		for pool_name: String in ["_slow_marks", "_fast_marks", "_beams"]:
			var pool: Variant = main.world.get(pool_name)
			if pool != null:
				for n: MeshInstance3D in pool.nodes: n.visible = false
	if warm_all:
		for p: Dictionary in sim.people():
			p.exposure = minf(float(p.exposure), 0.3)
			p.panic = {}
		for u: Dictionary in sim.units: u.exposure = 0.0

## The lens camera put where `c` says: [x, z, distance, yaw, pitch, look height, fov].
func _place_lens(c: Array) -> void:
	var yaw := deg_to_rad(float(c[3]))
	var pitch := deg_to_rad(float(c[4]))
	var look := Vector3(float(c[0]), float(c[5]), float(c[1]))
	lens_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	lens_cam.fov = float(c[6])
	lens_cam.near = 0.3
	lens_cam.far = 1000.0
	lens_cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(c[2])
	lens_cam.look_at(look, Vector3.UP)
	lens_cam.current = true

# ------------------------------------------------------------------ helpers
static func m(x: float, z: float) -> Vector2:
	return Vector2(x * 32.0, z * 32.0)

## A point in metres from the environment ("x,z"), or `fallback`.
func _env_at(name: String, fallback: Vector2) -> Vector2:
	var v: PackedStringArray = OS.get_environment(name).split(",", false)
	return Vector2(float(v[0]), float(v[1])) if v.size() == 2 else fallback

func sound(on: bool) -> void:
	if main.world.audio != null: main.world.audio.enabled = on

## The rules and the visuals run on for `seconds` inside one frame (the plan giving its orders, if one runs).
func ff(seconds: float) -> void:
	sound(false)
	for i in range(int(round(seconds / DT))):
		_step()
	sound(true)

func _step() -> void:
	if plan != null: plan.tick()
	sim.update(DT)
	if plan != null: plan.trails()
	if warm_all: _pre_draw_warm()
	main.world.update_visuals(DT)

func _pre_draw_warm() -> void:
	for p: Dictionary in sim.people():
		p.exposure = minf(float(p.exposure), 0.3)
		p.panic = {}
	for u: Dictionary in sim.units: u.exposure = 0.0

func ff_until(test: Callable, limit: float = 20.0) -> void:
	sound(false)
	var t := 0.0
	while t < limit and not test.call():
		_step()
		t += DT
	sound(true)

## To `when` on the rules' clock.
func ff_to(when: float) -> void:
	ff_until(func() -> bool: return float(sim.time) >= when, when + 1.0)

func place(actor: Dictionary, at: Vector2) -> void:
	actor.x = at.x * 32.0
	actor.y = at.y * 32.0
	actor.path = []
	actor.think = 0.0

func put(id: String, at: Vector2, stance: String = "walk") -> Dictionary:
	var u: Dictionary = sim.unit_by_id(id)
	u.x = at.x * 32.0
	u.y = at.y * 32.0
	u.stance = stance
	u.path = []
	return u

## The clock run on to `until`, everyone kept warm (the rules' own tests see to the cold).
func warm(until: float) -> void:
	while float(sim.time) < until - 0.01:
		ff(minf(2.0, until - float(sim.time)))
		_pre_draw_warm()

func beasts() -> Dictionary:
	var found: Dictionary = {}
	for g: Dictionary in sim.guards:
		if bool(g.get("creature", false)):
			if str(g.state) == "waiting": sim._creature_enters(g, true)
			found[str(g.id)] = g
	return found

func group(name: String) -> Array:
	var list: Array = []
	for q: Dictionary in sim.people():
		if str(q.get("group", "")) == name: list.append(q)
	return list

## Camera: 5 numbers for the game's own, 7 for the lens.
func cam(c: Array) -> void:
	if c.size() >= 7:
		lens = c
		_place_lens(c)
		solid_buildings(true)
		return
	lens = []
	main.camera.current = true
	solid_buildings(false)
	main.desired_target = Vector3(c[0], 0, c[1]); main.target = main.desired_target
	main.desired_zoom = c[2]; main.zoom = c[2]
	main.desired_yaw = deg_to_rad(c[3]); main.yaw = main.desired_yaw
	main.pitch = deg_to_rad(c[4])
	main._update_camera(1.0, true)

## The buildings never fade in a lens shot: the game fades whatever stands between its own camera and somebody, which
## from low down is half the city. (Their faders are set aside, the buildings solid, and given back for the game's view.)
var _faders_aside: Array = []
func solid_buildings(on: bool) -> void:
	var site: Node = main.world.get("structures")
	if site == null or not "faders" in site: return
	if on and _faders_aside.is_empty() and not (site.faders as Array).is_empty():
		_faders_aside = (site.faders as Array).duplicate()
		for f: Dictionary in _faders_aside:
			f.alpha = 1.0
			f.want = 1.0
			for mat: Material in f.mats:
				if mat is StandardMaterial3D: (mat as StandardMaterial3D).albedo_color.a = 1.0
				elif mat is ShaderMaterial: (mat as ShaderMaterial).set_shader_parameter("fade", 1.0)
		(site.faders as Array).clear()
	elif not on and not _faders_aside.is_empty():
		(site.faders as Array).append_array(_faders_aside)
		_faders_aside = []

func mix(a: Array, b: Array, t: float) -> Array:
	var out: Array = []
	for i in range(a.size()): out.append(lerpf(a[i], b[i], t))
	return out

func begin_take() -> void:
	take_start = frame + 1

func end_take(name: String) -> void:
	print("MARK ", name, " ", take_start, " ", frame)

func roll(seconds: float, a: Array, b: Array, ease_kind: int = 0, each: Callable = Callable()) -> void:
	var n: int = int(round(seconds / DT))
	for i in range(n):
		if take_max > 0 and i >= take_max: break
		var t: float = float(i) / float(maxi(1, n - 1))
		if ease_kind == 1: t = t * t * (3.0 - 2.0 * t)
		elif ease_kind == 2: t = 1.0 - (1.0 - t) * (1.0 - t)
		cam(mix(a, b, t))
		if each.is_valid(): each.call(i)
		await tick()
		if plan != null:
			# the plan gives its orders between the frames too (main steps the rules once a frame)
			plan.tick()
			plan.trails()

## The camera on somebody: a and b are offsets from where he is (x and z added), the rest as given.
func follow(seconds: float, at: Callable, a: Array, b: Array, each: Callable = Callable()) -> void:
	var n: int = int(round(seconds / DT))
	var held := Vector2.INF
	for i in range(n):
		if take_max > 0 and i >= take_max: break
		var t: float = float(i) / float(maxi(1, n - 1))
		t = t * t * (3.0 - 2.0 * t)
		var p: Vector2 = at.call()
		held = p if not held.is_finite() else held.lerp(p, 0.2)
		var c: Array = mix(a, b, t)
		c[0] = held.x / 32.0 + c[0]
		c[1] = held.y / 32.0 + c[1]
		cam(c)
		if each.is_valid(): each.call(i)
		await tick()
		if plan != null:
			plan.tick()
			plan.trails()

func at_unit(id: String) -> Callable:
	return func() -> Vector2: return sim.position_of(sim.unit_by_id(id))

func at_guard(id: String) -> Callable:
	return func() -> Vector2: return sim.position_of(sim.guard_by_id(id))

## The HUD as a player sees it, one operative selected.
func hud_on(selected: String = "") -> void:
	main.hud.visible = true
	keep_notice = true
	if selected != "": sim.select(selected)
	main.hud.refresh()

## The camera for a take: landscape or upright.
func pick(name: String) -> Array:
	var table: Dictionary = CAMS_UP if portrait and CAMS_UP.has(name) else CAMS
	return table[name]

## Cameras [a, b] per take.
const CAMS := {
	"open": [[140.0, 83.0, 178.0, 270.0, 23.0, 2.0, 40.0], [148.0, 83.0, 132.0, 270.0, 17.0, 2.0, 40.0]],
	"rosada": [[240.0, 80.0, 66.0, 270.0, 3.5, 11.0, 36.0], [240.0, 80.0, 56.0, 270.0, 5.0, 12.0, 36.0]],
	"cabildo": [[40.0, 80.0, 66.0, 92.0, 11.0, 6.0, 42.0], [40.0, 82.0, 57.0, 98.0, 10.0, 6.0, 42.0]],
	"people": [[66.0, 50.0, 10.5, 165.0, 8.0, 1.6, 40.0], [66.0, 50.0, 9.0, 150.0, 7.0, 1.7, 40.0]],
	"fall": [[0.0, 0.0, 9.0, 205.0, 9.0, 1.0, 40.0], [0.0, 0.0, 7.5, 195.0, 8.0, 0.9, 40.0]],
	"fall2": [[0.0, 0.0, 7.5, 78.0, 9.0, 1.0, 40.0], [0.0, 0.0, 6.0, 70.0, 7.0, 0.8, 40.0]],
	"hornero": [[4.0, 8.0, 26.0, -45.0, 52.0], [4.0, 8.0, 23.0, -40.0, 52.0]],
	"benteveo": [[0.0, 2.0, 22.0, -45.0, 52.0], [0.0, 2.0, 20.0, -38.0, 52.0]],
	"lechuza": [[0.0, 0.0, 18.0, -45.0, 52.0], [0.0, 0.0, 16.5, -52.0, 52.0]],
	"bigua": [[0.0, 0.0, 18.0, -45.0, 52.0], [0.0, 0.0, 16.5, -38.0, 52.0]],
	"cross": [[0.0, 0.0, 19.0, -45.0, 52.0], [0.0, 0.0, 17.0, -40.0, 52.0]],
	"juan_in": [[0.0, 0.0, 10.0, 86.0, 6.0, 1.3, 40.0], [0.0, 0.0, 8.0, 93.0, 5.0, 1.3, 40.0]],
	"carry": [[0.0, 0.0, 14.0, 205.0, 15.0, 1.0, 40.0], [0.0, 0.0, 12.0, 192.0, 13.0, 1.0, 40.0]],
	"carry_hud": [[0.0, 0.0, 18.0, -45.0, 52.0], [0.0, 0.0, 16.5, -40.0, 52.0]],
	"beast_in": [[247.0, 49.0, 19.0, 318.0, 6.0, 1.8, 40.0], [246.0, 50.0, 15.0, 322.0, 5.0, 1.8, 40.0]],
	"rush": [[159.0, 85.0, 16.0, 265.0, 6.0, 1.2, 40.0], [160.0, 85.0, 13.0, 258.0, 5.0, 1.3, 40.0]],
	"rush_hud": [[158.0, 88.0, 22.0, -30.0, 50.0], [158.0, 88.0, 20.0, -24.0, 50.0]],
	"bell": [[134.0, 38.0, 36.0, -45.0, 52.0], [134.0, 38.0, 33.0, -40.0, 52.0]],
	"aim": [[3.0, 2.0, 9.0, 232.0, 6.0, 1.4, 40.0], [3.0, 2.0, 8.0, 236.0, 6.0, 1.4, 40.0]],
	"fire": [[4.0, 5.0, 11.0, 325.0, 7.0, 1.2, 42.0], [4.0, 5.0, 10.5, 328.0, 7.0, 1.2, 42.0]],
	"subte": [[2.0, 1.0, 11.0, 285.0, 16.0, 0.0, 42.0], [2.0, 1.0, 9.5, 280.0, 14.0, 0.0, 42.0]],
	"ria_boca": [[150.0, 120.0, 60.0, 240.0, 8.0, 14.0, 42.0], [150.0, 120.0, 52.0, 236.0, 7.0, 15.0, 42.0]],
	"ria_gondola": [[148.0, 122.0, 45.0, 160.0, 10.0, 12.0, 42.0], [148.0, 122.0, 40.0, 166.0, 9.0, 11.0, 42.0]],
	"end": [[140.0, 83.0, 190.0, 270.0, 26.0, 2.0, 40.0], [146.0, 83.0, 160.0, 270.0, 22.0, 2.0, 40.0]],
}
## The upright cut (1080 x 1920): the lens taller (its fov is vertical), the game's camera as an upright phone has it.
const CAMS_UP := {
	"rosada": [[244.0, 82.0, 50.0, 270.0, 4.0, 12.0, 58.0], [244.0, 82.0, 43.0, 270.0, 5.0, 13.0, 58.0]],
	"fall": [[0.0, 0.0, 8.0, 205.0, 9.0, 1.0, 55.0], [0.0, 0.0, 6.5, 195.0, 8.0, 0.9, 55.0]],
	"fall2": [[0.0, 0.0, 7.0, 78.0, 9.0, 1.1, 55.0], [0.0, 0.0, 5.8, 70.0, 7.0, 0.9, 55.0]],
	"hornero": [[2.0, 6.0, 20.0, -45.0, 52.0], [2.0, 6.0, 18.0, -40.0, 52.0]],
	"benteveo": [[0.0, 1.0, 16.0, -45.0, 52.0], [0.0, 1.0, 15.0, -38.0, 52.0]],
	"subte": [[2.0, 1.0, 9.5, 285.0, 18.0, 0.5, 58.0], [2.0, 1.0, 8.5, 280.0, 16.0, 0.5, 58.0]],
	"carry_hud": [[0.0, 0.0, 16.0, -45.0, 52.0], [0.0, 0.0, 15.0, -40.0, 52.0]],
	"beast_in": [[247.0, 49.0, 17.0, 318.0, 6.0, 2.2, 58.0], [246.0, 50.0, 13.5, 322.0, 5.0, 2.2, 58.0]],
	"rush": [[159.0, 85.0, 15.0, 265.0, 6.0, 1.4, 58.0], [160.0, 85.0, 12.5, 258.0, 5.0, 1.5, 58.0]],
	"aim": [[3.0, 2.0, 8.0, 232.0, 6.0, 1.6, 58.0], [3.0, 2.0, 7.2, 236.0, 6.0, 1.6, 58.0]],
	"fire": [[4.0, 5.0, 10.0, 325.0, 7.0, 1.4, 58.0], [4.0, 5.0, 9.5, 328.0, 7.0, 1.4, 58.0]],
	"end": [[244.0, 82.0, 70.0, 270.0, 6.0, 12.0, 58.0], [244.0, 82.0, 60.0, 270.0, 6.0, 13.0, 58.0]],
}

# ------------------------------------------------------------------ probes
## Stills for framing. Each line of the probe file: "name x z zoom yaw pitch [hud]" (the game's camera) or
## "name L x z dist yaw pitch look_h fov" (the lens); "@id" in place of x for offsets from somebody.
func shot_probe() -> void:
	var file: String = OS.get_cmdline_user_args()[1]
	var lines: PackedStringArray = FileAccess.get_file_as_string(file).split("\n", false)
	var setup: String = OS.get_environment("PROBE_SETUP")
	# PROBE_CANVAS=<w>x<h>: the stills drawn at that size, whatever window the screen allows (a 4K still on a
	# laptop): the root viewport renders at it and the window shows it scaled down
	if OS.get_environment("PROBE_CANVAS") != "":
		var wh: PackedStringArray = OS.get_environment("PROBE_CANVAS").split("x")
		if root.size_changed.is_connected(main._resize): root.size_changed.disconnect(main._resize)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		root.content_scale_size = Vector2i(int(wh[0]), int(wh[1]))
		for i in range(3): await tick()
	if setup != "": await call("setup_" + setup)
	else: ff(float(OS.get_environment("PROBE_FF")) if OS.get_environment("PROBE_FF") != "" else 3.0)
	if OS.get_environment("SOME_IN") != "": _some_in(int(OS.get_environment("SOME_IN")))
	# PROBE_SELECT=<id>: the one whose plate is lit in the HUD
	if OS.get_environment("PROBE_SELECT") != "": sim.select(OS.get_environment("PROBE_SELECT"))
	# PROBE_SHOOT=<cascarudo>: Juan Salvo takes aim at it, and the rules stop before the shot goes off (the stills
	# hold the aim; PROBE_SHOOT_FF, the seconds from the order, under the rifle's 0.8 s aim)
	if OS.get_environment("PROBE_SHOOT") != "":
		sim.select("salvo")
		hide_marks = true
		print("probe: order ", sim.order_shoot(OS.get_environment("PROBE_SHOOT")), " ", sim.message)
		ff(float(OS.get_environment("PROBE_SHOOT_FF")) if OS.get_environment("PROBE_SHOOT_FF") != "" else 0.6)
		sim.paused = true
	for line: String in lines:
		if line.begins_with("#"): continue
		var p: PackedStringArray = line.split(" ", false)
		var flags: Array = []
		while p.size() > 0 and p[p.size() - 1] in ["hud", "vision", "ink", "noink", "quiet"]:
			flags.append(p[p.size() - 1])
			p.remove_at(p.size() - 1)
		if p.size() < 6: continue
		main.hud.visible = "hud" in flags
		# "quiet": the HUD without the passing notice over the picture
		keep_notice = "hud" in flags and not "quiet" in flags
		main.world.draw_vision = "vision" in flags
		if "ink" in flags: main.world.set_ink(true)
		if "noink" in flags: main.world.set_ink(false)
		var nums: Array = []
		var i0: int = 2 if p[1] == "L" else 1
		for j in range(i0, p.size()):
			if p[j].begins_with("@"):
				var who: String = p[j].substr(1)
				var actor: Dictionary = sim.unit_by_id(who)
				if actor.is_empty(): actor = sim.guard_by_id(who)
				var u: Vector2 = sim.position_of(actor) / 32.0
				nums.append(u.x); nums.append(u.y)
			else: nums.append(float(p[j]))
		# "@id dx dz": the offsets added
		if p[i0].begins_with("@"):
			nums[0] += nums[2]; nums[1] += nums[3]
			nums.remove_at(2); nums.remove_at(2)
		cam(nums)
		for i in range(6):
			main.world.update_visuals(DT)
			await tick()
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(file.get_base_dir().path_join(p[0] + ".png"))
		print("probe ", p[0], " t=", snappedf(sim.time, 0.1))

# ------------------------------------------------------------------ setups (the plaza)
## The scripted win from the start, run on to `when` on the rules' clock.
func setup_play(when: float = -1.0) -> void:
	if when < 0.0: when = float(OS.get_environment("PLAY_AT")) if OS.get_environment("PLAY_AT") != "" else 10.0
	plan = Plans.new(sim, level)
	plan.chatty = OS.get_environment("PLAN_CHATTY") == "1"
	ff_to(when)

## The first flakes: a few seconds in, everybody still out in the square.
func setup_start() -> void:
	ff(float(OS.get_environment("START_AT")) if OS.get_environment("START_AT") != "" else 4.0)

## Half a minute in, the snow taking hold, the people still out in the square.
func setup_hero() -> void:
	ff(26.0)

## A wave on the square: Benteveo leads a group down the subte's north stair, the snow thick about them.
func setup_rescue() -> void:
	ff(88.0)
	warm_all = true
	var crowd: Array = group("piramide-w") + group("sw")
	put("benteveo", Vector2(15.2, 74.6), "walk")
	var rank := 0
	for p: Dictionary in crowd:
		p.x = (17.0 + 1.1 * float(rank)) * 32.0
		p.y = (74.4 + 0.5 * float(rank % 2)) * 32.0
		p.path = []
		p.exposure = 0.35 + 0.08 * float(rank)
		rank += 1
		sim._join(sim.unit_by_id("benteveo"), p)
	sim.select("benteveo")
	sim.move_to(Vector2(7.2, 74.6) * 32.0)
	ff(float(OS.get_environment("RESCUE_FF")) if OS.get_environment("RESCUE_FF") != "" else 0.4)

## A few seconds before Juan Salvo comes in off Avenida de Mayo.
func setup_arrive() -> void:
	ff(float(sim.unit_by_id("salvo").arrive.at) - float(OS.get_environment("ARRIVE_LEAD") if OS.get_environment("ARRIVE_LEAD") != "" else "2.0"))

## The first lull with the cascarudos in (everyone kept warm till then).
func _to_lull() -> void:
	warm_all = true
	warm(126.0)

## A wave: Juan Salvo, taking no cold, carries in a woman a cascarudo knocked down by the palms.
func setup_carry() -> void:
	_to_lull()
	_some_in(int(OS.get_environment("CARRY_IN")) if OS.get_environment("CARRY_IN") != "" else 0)
	var b: Dictionary = beasts()
	sim.time = 236.0
	var down: Dictionary = group("south")[0]
	down.x = 106.0 * 32.0
	down.y = 108.0 * 32.0
	sim._person_falls(down)
	place(b.c1, Vector2(110.5, 106.0))
	sim._set_state(b.c1, "stay")
	b.c1.pause_left = 30.0
	b.c1.angle = PI * 0.9
	place(b.c2, Vector2(150.0, 122.0))
	place(b.c3, Vector2(214.0, 102.0))
	put("salvo", Vector2(104.6, 108.6))
	sim.select("salvo")
	sim.perform("pickup", str(down.id))
	ff(1.2)
	sim.perform("move", Vector2(60.0, 112.0) * 32.0)
	ff(float(OS.get_environment("CARRY_FF")) if OS.get_environment("CARRY_FF") != "" else 0.5)

## The tram at the middle stop in the lull, Hornero at its bell, Juan Salvo in the north-east with his rifle, the three
## cascarudos in: one for the group by the Pirámide, one in the north (the bell draws it), one in the south-east.
func setup_salvo() -> void:
	_to_lull()
	var b: Dictionary = beasts()
	sim.vehicles.tram.x = float(sim.vehicle_spec("tram").stops[1])
	sim._beast_dirty = true
	put("hornero", sim.vehicle_rect("tram").get_center() / 32.0)
	put("salvo", Vector2(191.0, 83.0))
	place(b.c1, Vector2(204.0, 95.0))
	place(b.c2, Vector2(128.0, 58.0))
	place(b.c3, Vector2(214.0, 76.0))
	sim.select("salvo")
	ff(0.4)

## The group by the Pirámide's east side with a cascarudo coming for them, Juan Salvo out of it.
func _pyramid_group(salvo_at: Vector2) -> Dictionary:
	warm_all = true
	warm(150.0)
	var b: Dictionary = beasts()
	place(b.c2, Vector2(60.0, 60.0))
	place(b.c3, Vector2(70.0, 120.0))
	var rank := 0
	for q: Dictionary in group("piramide-e"):
		q.x = (151.0 + 1.3 * float(rank)) * 32.0
		q.y = (83.0 + 0.9 * float(rank % 2)) * 32.0
		q.path = []
		sim._set_state(q, "crowd")
		rank += 1
	put("salvo", salvo_at)
	sim.select("salvo")
	return b

## A cascarudo just starting its rush at the group by the Pirámide.
func setup_rush() -> void:
	var b: Dictionary = _pyramid_group(Vector2(140.0, 70.0))
	var x: float = float(OS.get_environment("RUSH_X")) if OS.get_environment("RUSH_X") != "" else 172.0
	var z: float = float(OS.get_environment("RUSH_Z")) if OS.get_environment("RUSH_Z") != "" else 100.0
	place(b.c1, Vector2(x, z))
	b.c1.angle = PI * 1.2 if OS.get_environment("RUSH_X") == "" else atan2(84.0 - z, 152.5 - x)
	for i in range(150):
		ff(DT)
		if str(b.c1.state) == "stalk": break

## Juan Salvo a few metres from a cascarudo by the Pirámide's group, about to take aim (the take gives the order).
## AIM_JUAN and AIM_BEAST ("x,z" in metres) put them elsewhere, AIM_FACE (degrees) turns the cascarudo.
func setup_aim() -> void:
	var b: Dictionary = _pyramid_group(_env_at("AIM_JUAN", Vector2(170.0, 96.0)))
	place(b.c1, _env_at("AIM_BEAST", Vector2(181.0, 104.0)))
	b.c1.angle = deg_to_rad(float(OS.get_environment("AIM_FACE"))) if OS.get_environment("AIM_FACE") != "" else PI * 0.95
	for q: Dictionary in group("piramide-e"): (b.c1.spared as Dictionary)[str(q.id)] = sim.time + 60.0
	(b.c1.spared as Dictionary)["salvo"] = sim.time + 60.0
	b.c1.think = 9.0
	ff(0.3)

## The end of a night that went well: everyone under cover, the square buried.
func setup_buried() -> void:
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
	sim.time = 470.0
	for k in range(30): main.world.update_visuals(DT)

# ------------------------------------------------------------------ setups (Riachuelo)
## The lamps out, three on the gondola over the river, Biguá rowing the passenger.
func setup_ria_crossing() -> void:
	sim.alarm.radius = 0.0
	# a quiet moment: nobody of the Guardia looking their way
	for g: Dictionary in sim.guards:
		g.range = 0
		g.near = 0
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

# ------------------------------------------------------------------ takes
func shot_open() -> void:
	ff(3.0)
	begin_take()
	await roll(5.6, pick("open")[0], pick("open")[1], 1)
	end_take("open")

func shot_rosada() -> void:
	ff(9.0)
	begin_take()
	await roll(4.2, pick("rosada")[0], pick("rosada")[1], 1)
	end_take("rosada")

func shot_cabildo() -> void:
	ff(12.0)
	begin_take()
	await roll(2.8, pick("cabildo")[0], pick("cabildo")[1], 1)
	end_take("cabildo")

func shot_people() -> void:
	ff(18.0)
	begin_take()
	await roll(2.8, pick("people")[0], pick("people")[1], 1)
	end_take("people")

## Somebody of the square, standing in a wave, a breath before the snow brings him down.
func setup_fall() -> void:
	var limit: float = float(OS.get_environment("FALL_LIMIT")) if OS.get_environment("FALL_LIMIT") != "" else 330.0
	var target: float = float(OS.get_environment("FALL_AT")) if OS.get_environment("FALL_AT") != "" else 0.985
	fall_target = target
	ff_until(_someone_falling, limit)
	var worst: Dictionary = {}
	for p: Dictionary in sim.people():
		if str(p.state) in ["crowd", "panic"] and (worst.is_empty() or float(p.exposure) > float(worst.exposure)): worst = p
	faller = str(worst.get("id", ""))
	print("fall: %s at t=%.1f exposure %.3f state %s at %s" % [faller, sim.time, float(worst.get("exposure", 0.0)), str(worst.get("state", "")), sim.position_of(worst) / 32.0])

var faller: String = ""
var fall_target: float = 0.985

func _someone_falling() -> bool:
	for p: Dictionary in sim.people():
		if str(p.state) in ["crowd", "panic"] and float(p.exposure) >= fall_target: return true
	return false

func shot_wave() -> void:
	await setup_fall()
	begin_take()
	await follow(3.4, at_guard(faller), pick("fall")[0], pick("fall")[1])
	end_take("wave")
	print("wave: %s %s" % [faller, sim.guard_by_id(faller).state])

## The scripted win run to `when`, then the camera on one of the four with the HUD up, his plate lit.
func _play_take(name: String, who: String, when: float, seconds: float) -> void:
	await setup_play(when)
	hud_on(who)
	begin_take()
	await follow(seconds, at_unit(who), pick(name)[0], pick(name)[1])
	end_take(name)

func shot_hornero() -> void:
	await _play_take("hornero", "hornero", 26.6, 4.0)

func shot_benteveo() -> void:
	await _play_take("benteveo", "benteveo", 11.6, 4.0)

func shot_lechuza() -> void:
	await _play_take("lechuza", "lechuza", float(OS.get_environment("LECHUZA_AT")) if OS.get_environment("LECHUZA_AT") != "" else 38.0, 4.5)

func shot_bigua() -> void:
	await _play_take("bigua", "bigua", float(OS.get_environment("BIGUA_AT")) if OS.get_environment("BIGUA_AT") != "" else 22.0, 4.0)

## Juan Salvo across the open square in the first wave (the scripted win), the HUD on him.
func shot_cross() -> void:
	await _play_take("cross", "salvo", 97.0, 4.5)

func shot_juan_in() -> void:
	ff(31.0)
	begin_take()
	await follow(3.4, at_unit("salvo"), pick("juan_in")[0], pick("juan_in")[1])
	end_take("juan_in")

## Some of the square already under cover (a staged moment should not read 0 of 26 four minutes in).
func _some_in(count: int) -> void:
	var spots: Array = ["catedral", "banco", "subte-n", "subte-s", "colectivo"]
	var i := 0
	for p: Dictionary in sim.people():
		if i >= count: break
		if str(p.get("group", "")) in ["piramide-e", "south", "piramide-w"]: continue
		var shelter: Dictionary = sim.shelter_by_id(str(spots[i % spots.size()]))
		var at: Vector2 = sim.shelter_inside(shelter) + Vector2(float(i % 4) * 20.0 - 30.0, float(i / 4 % 2) * 14.0)
		p.x = at.x
		p.y = at.y
		p.path = []
		sim._set_state(p, "safe")
		p.shelter = str(shelter.id)
		i += 1

func shot_carry() -> void:
	await setup_carry()
	begin_take()
	await follow(4.2, at_unit("salvo"), pick("carry")[0], pick("carry")[1])
	end_take("carry")

func shot_carry_hud() -> void:
	await setup_carry()
	_some_in(16)
	hud_on("salvo")
	begin_take()
	await follow(4.2, at_unit("salvo"), pick("carry_hud")[0], pick("carry_hud")[1])
	end_take("carry_hud")

## The first cascarudo coming into the square at its north-east corner (everyone kept warm till then): the lens low in
## the square, looking up Rivadavia toward the corner it comes round.
func shot_beast_in() -> void:
	_to_lull()
	var b: Dictionary = beasts()
	var at := Vector2(float(OS.get_environment("BEAST_X")) if OS.get_environment("BEAST_X") != "" else 252.0, float(OS.get_environment("BEAST_Z")) if OS.get_environment("BEAST_Z") != "" else 42.0)
	place(b.c1, at)
	b.c1.angle = atan2(60.0 - at.y, 225.0 - at.x)
	place(b.c2, Vector2(60.0, 60.0))
	place(b.c3, Vector2(70.0, 120.0))
	ff(0.3)
	print("beast_in: c1 %s at %s" % [b.c1.state, sim.position_of(b.c1) / 32.0])
	begin_take()
	await roll(3.6, pick("beast_in")[0], pick("beast_in")[1], 1)
	end_take("beast_in")
	print("beast_in: c1 %s at %s" % [b.c1.state, sim.position_of(b.c1) / 32.0])

func shot_end() -> void:
	await setup_buried()
	ff(1.0)
	begin_take()
	await roll(8.8, pick("end")[0], pick("end")[1], 2)
	end_take("end")

## A cascarudo rushing the group by the Pirámide (the lens behind the group, the Casa Rosada beyond).
func shot_rush() -> void:
	await setup_rush()
	begin_take()
	await roll(float(OS.get_environment("RUSH_SECONDS")) if OS.get_environment("RUSH_SECONDS") != "" else 4.0, pick("rush")[0], pick("rush")[1], 1)
	end_take("rush")
	print("rush: c1 %s, struck %s" % [sim.guard_by_id("c1").state, str(sim.stats.get("fallen", 0))])

func shot_rush_hud() -> void:
	await setup_rush()
	_some_in(14)
	hud_on("salvo")
	begin_take()
	await roll(4.0, pick("rush_hud")[0], pick("rush_hud")[1], 1)
	end_take("rush_hud")

## The lull: Hornero rings the tram's bell and the cascarudo in the north turns for it (its mark shows the bell).
func shot_bell() -> void:
	await setup_salvo()
	_some_in(14)
	var b: Dictionary = beasts()
	place(b.c2, Vector2(140.0, 47.0))
	ff(0.2)
	hud_on("hornero")
	begin_take()
	var rung := [false]
	await roll(4.0, pick("bell")[0], pick("bell")[1], 1, func(i: int) -> void:
		if i == 8 and not rung[0]:
			rung[0] = true
			sim.select("hornero")
			print("bell: call ", sim.perform("call"), " ", sim.message))
	end_take("bell")
	print("bell: c2 %s noise %s" % [b.c2.state, str(b.c2.get("noise_kind", ""))])

## Juan Salvo takes aim at a cascarudo by the Pirámide's group and fires (the order given as the take starts); the
## take's log says on which of its frames the shot went off ("SHOT <take> <frame>"), for the cut.
func _aim_take(name: String) -> void:
	await setup_aim()
	_some_in(14)
	var juan: Dictionary = sim.unit_by_id("salvo")
	var ammo: int = int(juan.ammo)
	sim.select("salvo")
	begin_take()
	var fired := [false]
	var seconds: float = float(OS.get_environment("AIM_SECONDS")) if OS.get_environment("AIM_SECONDS") != "" else 3.0
	await follow(seconds, at_unit("salvo"), pick(name)[0], pick(name)[1], func(i: int) -> void:
		if i == 20: print(name, ": order ", sim.order_shoot("c1"), " ", sim.message)
		if not fired[0] and int(juan.ammo) < ammo:
			fired[0] = true
			print("SHOT ", name, " ", i))
	end_take(name)
	print(name, ": c1 ", sim.guard_by_id("c1").state, " ammo ", juan.ammo)

func shot_aim() -> void:
	await _aim_take("aim")

func shot_fire() -> void:
	await _aim_take("fire")

## The subte's north stair in a wave: Benteveo leading a group down it, out of the snow.
func shot_subte() -> void:
	await setup_rescue()
	begin_take()
	await follow(3.6, at_unit("benteveo"), pick("subte")[0], pick("subte")[1])
	end_take("subte")

func shot_ria_boca() -> void:
	await setup_ria_crossing()
	begin_take()
	await roll(3.4, pick("ria_boca")[0], pick("ria_boca")[1], 1)
	end_take("ria_boca")

func shot_ria_gondola() -> void:
	await setup_ria_crossing()
	begin_take()
	await roll(3.4, pick("ria_gondola")[0], pick("ria_gondola")[1], 1)
	end_take("ria_gondola")

## The first wave, the cascarudos not come yet: a woman of the group by the Pirámide, the cold almost full in her, goes
## down in the snow a second into the take (the Pirámide behind her).
func shot_wave2() -> void:
	var who: String = OS.get_environment("FALLER") if OS.get_environment("FALLER") != "" else "p5"
	ff(float(OS.get_environment("WAVE_AT")) if OS.get_environment("WAVE_AT") != "" else 101.0)
	var p: Dictionary = sim.guard_by_id(who)
	p.exposure = float(OS.get_environment("FALL_AT")) if OS.get_environment("FALL_AT") != "" else 0.992
	faller = who
	print("wave2: %s at t=%.1f snow %.2f state %s" % [who, sim.time, sim.snow_intensity(), p.state])
	begin_take()
	await follow(3.4, at_guard(who), pick("fall2")[0], pick("fall2")[1])
	end_take("wave2")
	print("wave2: %s %s" % [who, sim.guard_by_id(who).state])
