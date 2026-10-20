extends SceneTree
## Dev-only: draws a mission's layout to PNGs for level design (not shipped).
## Usage: godot --headless --path godot --script ../tools/dev/mission_map.gd -- <res://data/riachuelo.json> <out_dir> [times...]
## One picture per time (seconds into the mission): obstacles, wire, hiding places, charge sites, guards with
## their routes, and where they see: red = seen even crouched, orange = seen standing only.
## Paths from the start to every charge site are traced in white (a missing one is reported).
const Simulation = preload("res://scripts/simulation.gd")
const PX: float = 2.0     # mission units per pixel (16 px per metre)
var sim: RefCounted

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var file: String = args[0] if args.size() > 0 else "res://data/riachuelo.json"
	var out_dir: String = args[1] if args.size() > 1 else "/tmp/missionmap"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	sim = Simulation.new(mission)
	sim.start()
	sim.toggle_pause()
	var times: Array = []
	for i: int in range(2, args.size()):
		times.append(float(args[i]))
	if times.is_empty():
		times = [0.0]
	for t: float in times:
		while sim.time < t:
			sim.update(0.05)
		_frame(out_dir + "/t%03d.png" % int(t), t == times[0])
	quit()

func _base(p: Vector2) -> Color:
	for o: Dictionary in sim.get_obstacles():
		if sim.rect_of(o).has_point(p):
			match str(o.get("kind", "")):
				"water": return Color(0.18, 0.28, 0.42)
				"building": return Color(0.16, 0.16, 0.18)
				_: return Color(0.33, 0.30, 0.26)
	for b: Dictionary in sim.get_barriers():
		if sim.rect_of(b).grow(2).has_point(p):
			return Color(0.9, 0.85, 0.2) if bool(b.get("cuttable", false)) else Color(0.7, 0.7, 0.3)
	if sim.in_bush(p):
		return Color(0.2, 0.5, 0.25)
	return Color(0.52, 0.55, 0.5)

func _dot(img: Image, at: Vector2, r: float, c: Color) -> void:
	var cx: int = int(at.x / PX)
	var cy: int = int(at.y / PX)
	var ri: int = int(ceil(r))
	for dy: int in range(-ri, ri + 1):
		for dx: int in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r: continue
			var x: int = cx + dx
			var y: int = cy + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)

func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps: int = int(a.distance_to(b) / PX) + 1
	for i: int in range(steps + 1):
		_dot(img, a.lerp(b, float(i) / steps), 0.6, c)

func _frame(path: String, with_paths: bool) -> void:
	var w: int = int(float(sim.data.width) / PX)
	var h: int = int(float(sim.data.height) / PX)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for py: int in range(h):
		for px: int in range(w):
			var p := Vector2((px + 0.5) * PX, (py + 0.5) * PX)
			var c: Color = _base(p)
			if (px * int(PX)) % 32 == 0 or (py * int(PX)) % 32 == 0: c = c.darkened(0.08)
			if (px * int(PX)) % 320 == 0 or (py * int(PX)) % 320 == 0: c = c.darkened(0.2)
			var crouch: bool = false
			var stand: bool = false
			for g: Dictionary in sim.guards:
				if sim.zone_at(g, p, false) > 0: crouch = true
				elif sim.zone_at(g, p, true) > 0: stand = true
			if crouch: c = c.lerp(Color(1, 0.1, 0.1), 0.55)
			elif stand: c = c.lerp(Color(1, 0.65, 0.1), 0.4)
			img.set_pixel(px, py, c)
	for g: Dictionary in sim.guards:
		var route: Array = g.get("route", [])
		for i: int in range(route.size()):
			var a := Vector2(float(route[i][0]), float(route[i][1]))
			var b := Vector2(float(route[(i + 1) % route.size()][0]), float(route[(i + 1) % route.size()][1]))
			_line(img, a, b, Color(0.95, 0.6, 0.6))
	if with_paths:
		var starts: Array = []
		for unit: Dictionary in sim.units: starts.append(sim.position_of(unit))
		var was_cut: bool = sim.fence_cut
		sim.fence_cut = true
		for site: Dictionary in sim.charge_sites():
			var goal := Vector2(float(site.x), float(site.y))
			var route: Array = sim.find_path(starts[0], goal)
			if route.is_empty():
				print("NO PATH to ", site.id)
				continue
			var last: Vector2 = starts[0]
			for point: Vector2 in route:
				_line(img, last, point, Color(1, 1, 1))
				last = point
		if sim.data.has("radio"):
			var radio := Vector2(float(sim.data.radio.x), float(sim.data.radio.y))
			if sim.find_path(starts[0], radio).is_empty(): print("NO PATH to the radio/switch")
		sim.fence_cut = was_cut
	for site: Dictionary in sim.charge_sites():
		_dot(img, Vector2(float(site.x), float(site.y)), 4.0, Color(1, 0.85, 0.1))
		_dot(img, Vector2(float(site.get("tx", site.x)), float(site.get("ty", site.y))), 2.5, Color(1, 0.4, 0.0))
	if sim.data.has("radio"):
		_dot(img, Vector2(float(sim.data.radio.x), float(sim.data.radio.y)), 4.0, Color(0.3, 0.9, 1.0))
	var e: Dictionary = sim.data.extraction
	_dot(img, Vector2(float(e.x), float(e.y)), float(e.radius) / PX, Color(0.4, 0.8, 1.0))
	for unit: Dictionary in sim.units:
		_dot(img, sim.position_of(unit), 4.0, Color(1, 1, 1))
	for g: Dictionary in sim.guards:
		var at: Vector2 = sim.position_of(g)
		_dot(img, at, 4.5, Color(0.1, 0.1, 0.1))
		_dot(img, at, 3.0, Color(0.95, 0.2, 0.2))
		_line(img, at, at + Vector2.from_angle(float(g.angle)) * 24.0, Color(0, 0, 0))
	img.save_png(path)
	print("saved ", path)
