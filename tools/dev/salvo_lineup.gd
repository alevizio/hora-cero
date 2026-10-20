extends SceneTree
## Dev-only: Juan Salvo beside the four neighbours on the Plaza de Mayo (the operation "plaza", as the game builds it), to
## see whether he belongs with them: the five standing in a row, seen from the game's own camera and from a close lens
## at three-quarters; Juan walking beside one of them; and the squad's photos in the HUD. Not shipped.
## Run (rendered, not headless):
##   xvfb-run -a -s "-screen 0 2000x1200x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/salvo_lineup.gd -- <out dir> [seconds into the night] [walk | ink | hud <portrait.png> ...]
## Writes <out dir>/lineup_game.png, lineup_close.png, lineup_near.png, lineup_back.png, walk_game.png, walk_close.png,
## hud_strip.png and walk_frame_0..5.png (the walk beside Biguá every tenth of a second); with "walk", only the walk;
## with "ink", in comic ink, the row only (ink_game.png, ink_close.png); with "hud" and
## portraits, the HUD's photos with each of them in Juan Salvo's card in turn (hud_<name>.png), nothing else.
const Missions = preload("res://scripts/missions.gd")
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const DT: float = 1.0 / 30.0
const SQUAD := ["hornero", "lechuza", "benteveo", "bigua", "salvo"]
## Where the row stands (metres): an open stretch of the square east of the Pirámide.
const ROW := Vector2(176.0, 80.0)
const GAP: float = 1.25
var main: Node3D
var sim: RefCounted

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://lineup"
	var night: float = float(args[1]) if args.size() > 1 else 75.0
	var ink: bool = args.size() > 2 and args[2] == "ink"
	var walk_only: bool = args.size() > 2 and args[2] == "walk"
	var cards: Array = args.slice(3) if args.size() > 3 and args[2] == "hud" else []
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 1000)
	Missions.choose("plaza", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lineup_progress.cfg"))
	main.hud.progress_path = "user://lineup_progress.cfg"
	main.hud.load_progress()
	sim = main.sim
	main.hud.hints_enabled = false
	for i in range(3): await process_frame
	main._command("begin")
	main._arm("", true)
	if sim.paused: sim.toggle_pause()
	main.hud.overlay.hide()
	print("lineup: phase ", sim.phase, " paused ", sim.paused, " time ", sim.time)
	warm(night)
	print("lineup: phase ", sim.phase, " time ", sim.time, " salvo away ", sim.unit_by_id("salvo").get("away", false))
	# the creatures kept out of the way, the people of the square away from the row
	for g: Dictionary in sim.guards:
		if bool(g.get("creature", false)):
			g.x = 40.0 * 32.0
			g.y = 150.0 * 32.0
			g.path = []
	for q: Dictionary in sim.people():
		if Vector2(float(q.x), float(q.y)).distance_to(ROW * 32.0) < 14.0 * 32.0:
			q.x = 120.0 * 32.0
			q.y = 130.0 * 32.0
			q.path = []
	# --- the five in a row, turned three-quarters to the camera
	var yaw: float = deg_to_rad(-30.0)
	var to_cam := Vector2(sin(yaw), cos(yaw))
	var across := Vector2(cos(yaw), -sin(yaw))
	for i: int in range(SQUAD.size()):
		var at: Vector2 = ROW + across * (float(i) - 2.0) * GAP
		put(SQUAD[i], at, to_cam.rotated(deg_to_rad(-28.0)).angle())
	ff(2.0)
	main.hud.visible = false
	var mid := Vector3(ROW.x, 0.0, ROW.y)
	if walk_only:
		await walk(out, yaw)
		Missions.choose("plaza", false)
		quit()
		return
	if not cards.is_empty():
		# each portrait in his card, as the game draws the strip
		var slot: String = str(ArtPack.slot("juan_salvo").portrait)
		for png: String in cards:
			ArtPack._textures[slot] = ArtPack.drawing(png)
			main.hud._dress_photo(main.hud.portrait_buttons["salvo"], "salvo")
			await strip(out, "hud_" + png.get_file().get_basename())
		Missions.choose("plaza", false)
		quit()
		return
	if ink:
		main.world.call("set_ink", true)
		ff(0.2)
		await shot(out, "ink_game", mid + Vector3(0, 0.9, 0), 9.0, yaw, 52.0, false)
		await shot(out, "ink_close", mid + Vector3(0, 1.05, 0), 9.6, yaw, 8.0, true)
		Missions.choose("plaza", false)
		quit()
		return
	await shot(out, "lineup_game", mid + Vector3(0, 0.9, 0), 9.0, yaw, 52.0, false)
	await shot(out, "lineup_close", mid + Vector3(0, 1.05, 0), 9.6, yaw, 8.0, true)
	var pair_at: Vector2 = ROW + across * 1.5 * GAP
	await shot(out, "lineup_near", Vector3(pair_at.x, 1.3, pair_at.y), 5.2, yaw, 6.0, true)
	await shot(out, "lineup_back", mid + Vector3(0, 1.05, 0), 9.6, yaw + PI * 0.8, 10.0, true)
	# --- the HUD's photos
	await strip(out, "hud_strip")
	await walk(out, yaw)
	Missions.choose("plaza", false)
	quit()

## Juan walking beside Biguá, a body's width apart, the same way, at the squad's pace: the game's camera, a close lens,
## and six frames a tenth of a second apart from the close lens.
func walk(out: String, yaw: float) -> void:
	var start := ROW + Vector2(-6.0, 10.0)
	var heading := Vector2(1.0, -0.2).normalized()
	var side := Vector2(-heading.y, heading.x)
	for i: int in range(3): put(SQUAD[i], ROW + Vector2(-14.0 - 2.0 * i, -10.0), 0.0)
	put("salvo", start, heading.angle())
	put("bigua", start + side * 1.3, heading.angle())
	for id: String in ["salvo", "bigua"]:
		sim.select(id)
		var u: Dictionary = sim.unit_by_id(id)
		sim.move_to(Vector2(float(u.x), float(u.y)) + heading * 16.0 * 32.0)
	ff(3.2)
	var s: Dictionary = sim.unit_by_id("salvo")
	var b: Dictionary = sim.unit_by_id("bigua")
	var pair := Vector3((float(s.x) + float(b.x)) / 64.0, 0.0, (float(s.y) + float(b.y)) / 64.0)
	await shot(out, "walk_game", pair + Vector3(0, 0.9, 0), 8.0, yaw, 52.0, false)
	var front: Vector2 = heading.rotated(-0.75)
	await shot(out, "walk_close", pair + Vector3(heading.x, 1.0 / 0.6, heading.y) * 0.6, 6.5, atan2(front.x, front.y), 8.0, true)
	for i: int in range(6):
		await shot(out, "walk_frame_%d" % i, pair + Vector3(heading.x, 1.0 / 0.6, heading.y) * 0.6, 6.5, atan2(front.x, front.y), 8.0, true)
		ff(0.1 - DT * 0.1 * 10.0)
		var s2: Dictionary = sim.unit_by_id("salvo")
		var b2: Dictionary = sim.unit_by_id("bigua")
		pair = Vector3((float(s2.x) + float(b2.x)) / 64.0, 0.0, (float(s2.y) + float(b2.y)) / 64.0)

## The HUD's strip of the squad's photos, as the game draws it, cut out of the screen.
func strip(out: String, name: String) -> void:
	main.hud.visible = true
	main.hud.overlay.hide()
	main.hud.refresh()
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var full: Image = root.get_viewport().get_texture().get_image()
	var row: Control = main.hud.portrait_strip
	var xf: Transform2D = root.get_final_transform() * row.get_global_transform_with_canvas()
	var a: Vector2 = xf * Vector2(-6, -30)
	var z: Vector2 = xf * (row.size + Vector2(6, 6))
	var r := Rect2i(Vector2i(a), Vector2i(z - a)).intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	full.get_region(r).save_png(out.path_join(name + ".png"))
	main.hud.visible = false

## A picture: the game's orthographic camera (`zoom` metres across, `pitch` degrees down) or a 35-degree lens `dist`
## metres from `look`; the game held still for it.
func shot(out: String, name: String, look: Vector3, size: float, yaw: float, pitch_deg: float, lens: bool) -> void:
	main.set_process(false)
	var cam: Camera3D = main.camera
	var pitch: float = deg_to_rad(pitch_deg)
	if lens:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 35.0
		cam.near = 0.2
		cam.far = 400.0
		cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * size
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
		cam.far = 160.0
		cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 55.0
	cam.look_at(look, Vector3.UP)
	for i in range(10):
		main.world.update_visuals(DT * 0.1)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	main.set_process(true)
	print("shot ", name)

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

func put(id: String, at: Vector2, angle: float) -> void:
	var u: Dictionary = sim.unit_by_id(id)
	u.x = at.x * 32.0
	u.y = at.y * 32.0
	u.stance = "walk"
	u.path = []
	u.angle = angle

