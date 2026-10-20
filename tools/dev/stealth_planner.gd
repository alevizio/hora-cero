extends SceneTree
## Dev-only: finds unseen routes through a mission (not shipped).
## Replays the patrols with nobody about, then searches cells x time for a crouched route from A to B that no
## guard sees (near zones, sight blocked as the rules block it). Prints the route as timed way-points and
## draws it over the map.
## Usage: godot --headless --path godot --script ../tools/dev/stealth_planner.gd -- <res://data/riachuelo.json> <out.png>
##          <start x> <start y> <start time s> <goal x> <goal y> [more goals ...]   (mission units)
## Several goals are chained: the route to each starts where (and when) the last one ended. Add "+N" after a goal
## to stand there N seconds (planting a charge, say) before going on.
## Orders for another operative during the replay (a cigarette that stops a guard, say) go before the start, as
## "order:<unit>:<order>:<target>:<seconds>"; that operative stays in the world (the rest are taken off the map).
const Simulation = preload("res://scripts/simulation.gd")
const SLOT: float = 1.0 / 7.0
const HORIZON: float = 300.0
const CROUCH: float = 56.0          # units per second
var sim: RefCounted
var slots: int
var cols: int
var rows: int
var frames: Array = []              # per slot: Array of guard dictionaries
var seen := PackedByteArray()       # cells x slots: 0 unknown, 1 clear, 2 seen
var walk := PackedByteArray()

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out: String = args[1]
	sim = Simulation.new(mission)
	sim.start()
	sim.toggle_pause()
	if args.size() > 2 and args[2] == "cut":
		sim.fence_cut = true
		args = args.slice(0, 2) + args.slice(3)
	if args.size() > 2 and args[2] == "dark":
		sim.radio_cut = true
		sim._cut_power()
		args = args.slice(0, 2) + args.slice(3)
	# scripted orders for someone else (a neighbour drawing a guard off): [time, unit, order, target]
	var scripted: Array = []
	while args.size() > 2 and args[2].begins_with("order:"):
		var bits: PackedStringArray = args[2].split(":")
		scripted.append([float(bits[4]), bits[1], bits[2], bits[3]])
		args = args.slice(0, 2) + args.slice(3)
	var keep: Array = []
	for order: Array in scripted: keep.append(order[1])
	for unit: Dictionary in sim.units:
		if str(unit.id) in keep: continue
		unit.x = -5000.0
		unit.y = -5000.0
	cols = int(ceil(float(sim.data.width) / 32.0))
	rows = int(ceil(float(sim.data.height) / 32.0))
	slots = int(HORIZON / SLOT)
	var t: float = 0.0
	for s: int in range(slots):
		var snap: Array = []
		for g: Dictionary in sim.guards: snap.append(g.duplicate(true))
		frames.append(snap)
		var target: float = float(s + 1) * SLOT
		while sim.time < target - 0.0001:
			for order: Array in scripted:
				if order.size() == 4 and sim.time >= float(order[0]):
					sim.select(str(order[1]))
					var ok: bool = sim.perform(str(order[2]), str(order[3]) if str(order[3]) != "" else null)
					print("  replay: %s %s %s at %.1f s: %s" % [order[1], order[2], order[3], sim.time, "ok" if ok else sim.message])
					order.append(true)
			sim.update(0.05)
	seen.resize(cols * rows * slots)
	seen.fill(0)
	walk.resize(cols * rows)
	for i: int in range(cols * rows):
		walk[i] = 0 if sim.is_blocked(_centre(i)) else 1
	var at := Vector2(float(args[2]), float(args[3]))
	var slot: int = int(float(args[4]) / SLOT)
	var img := _base_image()
	var k: int = 5
	var total_route: Array = []
	while k + 1 < args.size():
		var goal := Vector2(float(args[k]), float(args[k + 1]))
		k += 2
		var hold: float = 0.0
		if k < args.size() and args[k].begins_with("+"):
			hold = float(args[k].substr(1))
			k += 1
		var route: Array = _search(at, slot, goal, hold)
		if route.is_empty():
			print("NO UNSEEN ROUTE from %s at %.1f s to %s" % [at, slot * SLOT, goal])
			break
		var last: Array = route[route.size() - 1]
		print("route to %s: arrive %.2f s%s" % [goal, float(last[1]) * SLOT, ("  (then %.1f s there)" % hold) if hold > 0.0 else ""])
		_print_waypoints(route)
		total_route.append_array(route)
		at = _centre(int(last[0]))
		slot = int(last[1]) + int(ceil(hold / SLOT))
	_draw_route(img, total_route)
	img.save_png(out)
	quit()

func _centre(i: int) -> Vector2:
	return Vector2((float(i % cols) + 0.5) * 32.0, (float(i / cols) + 0.5) * 32.0)

func _cell(p: Vector2) -> int:
	return clampi(int(p.y / 32.0), 0, rows - 1) * cols + clampi(int(p.x / 32.0), 0, cols - 1)

func _visible(cell: int, slot: int) -> bool:
	if slot >= slots: return true
	var i: int = slot * cols * rows + cell
	var v: int = seen[i]
	if v == 0:
		v = 1
		var p: Vector2 = _centre(cell)
		for g: Dictionary in frames[slot]:
			if sim.zone_at(g, p, false) > 0:
				v = 2
				break
		seen[i] = v
	return v == 2

## Cells x slots search (Dijkstra on time): move to a neighbour cell in as many slots as crouching takes, or wait.
## While holding at the goal (planting) the cell must stay unseen for the whole hold.
func _search(from: Vector2, slot0: int, goal: Vector2, hold: float) -> Array:
	var start: int = _cell(from)
	var target: int = _cell(goal)
	var hold_slots: int = int(ceil(hold / SLOT))
	var best: Dictionary = {}
	var parent: Dictionary = {}
	var open: Array = [[slot0, start]]
	best[Vector2i(start, slot0)] = true
	var orth: int = int(ceil(32.0 / CROUCH / SLOT))
	var diag: int = int(ceil(45.25 / CROUCH / SLOT))
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var head: int = 0
	while head < open.size():
		var cur: Array = open[head]
		head += 1
		var s: int = cur[0]
		var c: int = cur[1]
		if c == target:
			var ok: bool = true
			for h: int in range(hold_slots + 1):
				if _visible(c, s + h): ok = false
			if ok:
				var route: Array = []
				var key := Vector2i(c, s)
				while true:
					route.push_front([key.x, key.y])
					if not parent.has(key): break
					key = parent[key]
				return route
		if s + diag + 1 >= slots: continue
		# wait a slot
		var wkey := Vector2i(c, s + 1)
		if not best.has(wkey) and not _visible(c, s + 1):
			best[wkey] = true
			parent[wkey] = Vector2i(c, s)
			open.append([s + 1, c])
		var cx: int = c % cols
		var cy: int = c / cols
		for d: Vector2i in dirs:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows: continue
			var n: int = ny * cols + nx
			if walk[n] == 0: continue
			if d.x != 0 and d.y != 0 and (walk[cy * cols + nx] == 0 or walk[ny * cols + cx] == 0): continue
			var cost: int = diag if d.x != 0 and d.y != 0 else orth
			var ns: int = s + cost
			var key := Vector2i(n, ns)
			if best.has(key): continue
			var clear: bool = true
			for k: int in range(1, cost + 1):
				if _visible(c if k < cost / 2 else n, s + k):
					clear = false
					break
			if not clear: continue
			best[key] = true
			parent[key] = Vector2i(c, s)
			open.append([ns, n])
	return []

func _print_waypoints(route: Array) -> void:
	# merge runs in the same direction; print where the route waits
	var line: String = ""
	var prev: int = -1
	var prev_slot: int = -1
	var dir := Vector2i(99, 99)
	for k: int in range(route.size()):
		var c: int = route[k][0]
		var s: int = route[k][1]
		if prev >= 0:
			if c == prev:
				if not line.ends_with("wait "):
					line += "[%d,%d]@%.1f wait " % [int(_centre(c).x), int(_centre(c).y), prev_slot * SLOT]
			else:
				var d := Vector2i(c % cols - prev % cols, c / cols - prev / cols)
				if d != dir:
					line += "[%d,%d]@%.1f " % [int(_centre(prev).x), int(_centre(prev).y), prev_slot * SLOT]
					dir = d
		prev = c
		prev_slot = s
	line += "[%d,%d]@%.1f" % [int(_centre(prev).x), int(_centre(prev).y), prev_slot * SLOT]
	print("  ", line)

func _base_image() -> Image:
	var img := Image.create(cols * 8, rows * 8, false, Image.FORMAT_RGB8)
	for i: int in range(cols * rows):
		var c := Color(0.5, 0.53, 0.48) if walk[i] == 1 else Color(0.18, 0.18, 0.2)
		if sim.in_bush(_centre(i)): c = Color(0.2, 0.45, 0.25)
		img.fill_rect(Rect2i((i % cols) * 8, (i / cols) * 8, 7, 7), c)
	return img

func _draw_route(img: Image, route: Array) -> void:
	for k: int in range(route.size()):
		var c: int = route[k][0]
		var s: int = route[k][1]
		var t: float = clampf(float(s) * SLOT / 200.0, 0.0, 1.0)
		img.fill_rect(Rect2i((c % cols) * 8 + 2, (c / cols) * 8 + 2, 4, 4), Color(1.0, 1.0 - t, 0.2 + t * 0.6))
