extends SceneTree
## Dev-only: Juan Salvo's gait against the neighbours', measured in the game (the operation "plaza"): Juan and Biguá
## walking side by side at the squad's pace, then each carrying a fallen woman; for each, the steps a second, the step
## length, how far a foot on the ground slides per metre walked, the hips' height and bob, and which of Juan's clips is
## playing (his run weight). Prints one line per case. Not shipped.
## Run: godot --headless --path godot --script ../tools/dev/salvo_gait.gd
const Missions = preload("res://scripts/missions.gd")
const Operative = preload("res://scripts/three_d/operative.gd")
const DT: float = 1.0 / 60.0
var main: Node3D
var sim: RefCounted

func _init() -> void:
	call_deferred("run")

func run() -> void:
	Missions.choose("plaza", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://gait_progress.cfg"))
	main.hud.progress_path = "user://gait_progress.cfg"
	main.hud.load_progress()
	sim = main.sim
	main.hud.hints_enabled = false
	for i in range(3): await process_frame
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	warm(40.0)
	for g: Dictionary in sim.guards:
		if bool(g.get("creature", false)):
			g.x = 40.0 * 32.0
			g.y = 150.0 * 32.0
			g.path = []
	# --- walking side by side, east across the square
	put("salvo", Vector2(150.0, 84.0))
	put("bigua", Vector2(150.0, 86.0))
	for id: String in ["salvo", "bigua"]:
		sim.select(id)
		var u: Dictionary = sim.unit_by_id(id)
		sim.move_to(Vector2(float(u.x), float(u.y)) + Vector2(30.0, 0.0) * 32.0)
	ff(1.5)
	await measure("walking", 3.0)
	# --- each carrying a fallen woman
	var fallen: Array = []
	for p: Dictionary in sim.people():
		if fallen.size() < 2 and str(p.get("state", "")) != "safe": fallen.append(p)
	var spots := {"salvo": Vector2(150.0, 100.0), "bigua": Vector2(150.0, 104.0)}
	var k: int = 0
	for id: String in ["salvo", "bigua"]:
		var p: Dictionary = fallen[k]
		k += 1
		p.x = (spots[id] as Vector2).x * 32.0 + 20.0
		p.y = (spots[id] as Vector2).y * 32.0
		p.path = []
		sim._person_falls(p)
		put(id, spots[id])
		sim.select(id)
		sim.perform("pickup", str(p.id))
	ff(2.5)
	for id: String in ["salvo", "bigua"]:
		sim.select(id)
		var u: Dictionary = sim.unit_by_id(id)
		sim.move_to(Vector2(float(u.x), float(u.y)) + Vector2(-30.0, 0.0) * 32.0)
	ff(1.5)
	print("carrying: salvo has ", sim.unit_by_id("salvo").get("carrying", ""), ", bigua has ", sim.unit_by_id("bigua").get("carrying", ""))
	await measure("carrying", 3.0)
	Missions.choose("plaza", false)
	quit()

## Over `seconds` of the game: per figure, its feet in the world each frame, the ground it covered, its hips.
func measure(label: String, seconds: float) -> void:
	var ops := {"salvo": main.world.actors["salvo"], "bigua": main.world.actors["bigua"]}
	var rec := {}
	for id: String in ops: rec[id] = {"feet": [], "hips": [], "root": [], "phase": [], "run": [], "gait": []}
	var n: int = int(seconds / DT)
	for i: int in range(n):
		sim.update(DT)
		main.world.update_visuals(DT)
		for id: String in ops:
			var op: Node3D = ops[id]
			var r: Dictionary = rec[id]
			var feet: Array = []
			var hips: Vector3
			if op.cutout != null and op.cutout.rig != null:
				var rig: Variant = op.cutout.rig
				var sk: Skeleton3D = rig.skel
				for role: String in ["foot_l", "foot_r"]:
					feet.append(sk.global_transform * sk.get_bone_global_pose(int(rig.roles[role])).origin)
				hips = sk.global_transform * sk.get_bone_global_pose(int(rig.roles.hips)).origin
				r.run.append(float(rig._run))
				r.gait.append(float(rig._gait))
			else:
				var sk: Skeleton3D = op.skel
				for b: int in [Operative.FOOT_L, Operative.FOOT_R]:
					feet.append(sk.global_transform * sk.get_bone_global_pose(b).origin)
				hips = sk.global_transform * sk.get_bone_global_pose(Operative.HIPS).origin
				r.phase.append(float(op.phase))
			r.feet.append(feet)
			r.hips.append(hips)
			r.root.append(op.global_position)
	for id: String in ops:
		var r: Dictionary = rec[id]
		var dist: float = (r.root[r.root.size() - 1] as Vector3).distance_to(r.root[0])
		var speed: float = dist / seconds
		# steps: each foot's touchdowns (it comes within 2 cm of its lowest after being 4 cm above it)
		var steps: int = 0
		var slide: float = 0.0
		var planted_len: float = 0.0
		for side: int in [0, 1]:
			var low: float = INF
			for f: Array in r.feet: low = minf(low, (f[side] as Vector3).y)
			var up: bool = false
			for i: int in range(1, r.feet.size()):
				var a: Vector3 = r.feet[i - 1][side]
				var b: Vector3 = r.feet[i][side]
				if b.y > low + 0.04: up = true
				if up and b.y < low + 0.02:
					steps += 1
					up = false
				if a.y < low + 0.02 and b.y < low + 0.02:
					slide += Vector2(b.x - a.x, b.z - a.z).length()
					planted_len += (r.root[i] as Vector3).distance_to(r.root[i - 1])
		var hy: Array = []
		for h: Vector3 in r.hips: hy.append(h.y)
		var line := "%s %-6s: %.2f m/s, %.2f steps/s, step %.2f m, planted foot slides %.2f m per metre, hips %.2f..%.2f m" % [label, id,
			speed, steps / seconds, dist / maxf(steps, 1), slide / maxf(planted_len, 0.001), hy.min(), hy.max()]
		if not r.run.is_empty():
			var run_max: float = 0.0
			for v: float in r.run: run_max = maxf(run_max, v)
			line += ", run weight up to %.2f" % run_max
		print(line)
	await process_frame

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

func put(id: String, at: Vector2) -> void:
	var u: Dictionary = sim.unit_by_id(id)
	u.x = at.x * 32.0
	u.y = at.y * 32.0
	u.stance = "walk"
	u.path = []
