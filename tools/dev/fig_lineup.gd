extends SceneTree
## Dev-only: stands characters in a row as the game builds them (baked figure plus kit, posed by the game's own
## animation code) and renders them, for checking new looks. Not shipped.
## Usage: godot --path godot --rendering-driver opengl3 --script ../tools/dev/fig_lineup.gd -- <out.png> <spec> ...
##   spec = id[:enemy 0/1[:kind[:look[:action[:facing degrees]]]]]   e.g. hornero  q1:1:patrol:guardia0  benteveo:0:::chat
const Operative = preload("res://scripts/three_d/operative.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var specs: Array = args.slice(1)
	root.size = Vector2i(380 * specs.size(), 760)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.11, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.52)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.76)
	key.light_energy = 1.25
	key.rotation = Vector3(-0.7, 0.5, 0)
	key.shadow_enabled = true
	root.add_child(key)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 10)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.24, 0.22)
	floor.material_override = fm
	root.add_child(floor)
	var gap := 1.0
	var models: Array = []
	for i: int in range(specs.size()):
		var p: PackedStringArray = str(specs[i]).split(":")
		var id: String = p[0]
		var enemy: bool = p.size() > 1 and p[1] == "1"
		var kind: String = p[2] if p.size() > 2 else ""
		var look: String = p[3] if p.size() > 3 else ""
		var action: String = p[4] if p.size() > 4 else ""
		var facing: float = deg_to_rad(float(p[5])) if p.size() > 5 else PI * 0.5
		var m := Operative.new()
		root.add_child(m)
		m.build(id, enemy, kind, look)
		var actor := {"id": id, "x": (float(i) - (specs.size() - 1) * 0.5) * gap * 32.0, "y": 0.0, "angle": facing,
			"state": "patrol", "stance": "walk", "alive": true, "hp": 100, "kind": kind, "look": look,
			"action": action, "acting": action != "", "action_time": 1.0, "action_total": 8.0, "order": {}, "carrying": "",
			"exposed": true, "suspicion": 0.0, "path": [], "ammo": 0, "cooldown": 0.0, "weapon_cooldown": 0.0}
		models.append([m, actor])
	for f: int in range(40):
		for pair: Array in models: (pair[0] as Node3D).call("sync", pair[1], false, 0.05, false)
		await process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.4
	cam.position = Vector3(0, 1.75, 6.0)
	cam.rotation = Vector3(-0.12, 0, 0)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	root.add_child(cam)
	cam.current = true
	cam.size = 2.25
	for f: int in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
