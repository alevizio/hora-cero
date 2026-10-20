extends SceneTree
## Dev-only: photographs every icon an operation can show, to look at them by eye: the briefing's kit rows, each
## operative's action bar, the prompt of each action he aims, and the whole map (the MAP key) with every marker he can
## tap, once at the start and once with the cellar open, the passenger out and a man down in the street.
## Run (rendered, not headless):
##   HORACERO_LANG=es HORACERO_MISSION=riachuelo xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot \
##     --rendering-driver opengl3 --script ../tools/dev/icon_shots.gd -- <out dir> [<width> <height> [start,freed]]
## Writes <out dir>/<shot>.png and rects.json: where the bar, the prompt, the squad's cards and each marker (its kind and
## picture) are in each picture.
const Missions = preload("res://scripts/missions.gd")
const PROGRESS := "user://icon_shots_progress.cfg"
var main: Node3D
var sim: RefCounted
var hud: Control
var out: String
var rects: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/icon_shots"
	var dims := Vector2i(int(args[1]) if args.size() > 1 else 1280, int(args[2]) if args.size() > 2 else 720)
	var stages: PackedStringArray = args[3].split(",") if args.size() > 3 else PackedStringArray(["start", "freed"])
	DirAccess.make_dir_recursive_absolute(out)
	var id: String = OS.get_environment("HORACERO_MISSION") if OS.get_environment("HORACERO_MISSION") != "" else "riachuelo"
	Missions.choose(id, false)
	root.size = dims
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	hud = main.hud
	hud.progress_path = PROGRESS
	hud.load_progress()
	hud.hints_enabled = false
	sim = main.sim
	await frames(10)
	# the briefing: the squad's cards with their kit
	main._command("restart")
	await frames(8)
	await shot("briefing", {"cards": _rect(hud.operatives_row)})
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	# nobody raises the alarm while the pictures are taken
	sim.alarm.radius = 0.0
	for g: Dictionary in sim.guards:
		g.range = 0
		g.near = 0
	for stage: String in stages:
		if stage == "freed":
			sim.door_open = true
			sim._geometry_dirty = true
			if sim.has_prisoner:
				sim.prisoner.freed = true
				sim.prisoner.follow_id = ""
			# a man down in the open, to be carried off
			var g: Dictionary = sim.guards[0]
			g.state = "bound"
			g.hidden = false
			g.carried_by = ""
		for u: Dictionary in sim.units:
			sim.select(str(u.id))
			main._arm("", true)
			main._command("fit")
			main._update_camera(1.0, true)
			sim.update(0.05)
			hud.refresh()
			await frames(4)
			await shot("map_%s_%s" % [u.id, stage], {"bar": _rect(hud.action_strip), "pins": _pins()})
			if stage != "start": continue
			for action: String in ["takedown", "distract", "shoot"]:
				var entry: Dictionary = {}
				for e: Dictionary in sim.available_actions():
					if str(e.id) == action: entry = e
				if entry.is_empty(): continue
				main._arm(action, true)
				hud.refresh()
				await frames(3)
				await shot("prompt_%s_%s" % [u.id, action], {"prompt": _rect(hud.prompt), "bar": _rect(hud.action_strip)})
				main._arm("", true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	quit()

func frames(n: int) -> void:
	for i: int in range(n): await process_frame

## A control's rectangle in the picture's pixels (the HUD lays out on a canvas the window stretches).
func _rect(c: Variant) -> Array:
	if not (c is Control) or not (c as Control).is_visible_in_tree(): return []
	var r: Rect2 = (c as Control).get_global_rect()
	var k: Vector2 = _scale()
	return [r.position.x * k.x, r.position.y * k.y, r.size.x * k.x, r.size.y * k.y]

func _scale() -> Vector2:
	return Vector2(root.size) / hud.viewport_size

## The markers on screen: [type, x, y, icon] for each.
func _pins() -> Array:
	var out: Array = []
	for thing: Dictionary in sim.interactables():
		if not hud._pin_shown(thing): continue
		var at: Vector2 = hud._pin_point(thing) * _scale()
		if Rect2(Vector2.ZERO, Vector2(root.size)).has_point(at): out.append([str(thing.type), at.x, at.y, str(hud.thing_icons.get(thing.type, "tap"))])
	return out

func shot(name: String, where: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	rects[name] = where
	# written after every picture, so a run cut short still says where things are in the ones it took
	var f := FileAccess.open(out.path_join("rects.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rects, "  "))
	f.close()
	print("SHOT ", name)
