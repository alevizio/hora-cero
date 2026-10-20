extends RefCounted
## Behind the quay: the rail yard with its two sidings and the wagons standing on them, the two brick
## warehouses (the harbour guard sleeps in Hangar 14), the building site's wire with the span Rook can cut, the
## gravel and sand heaps and the concrete batching plant, the cargo stacked on the quay, and every hiding place
## of the mission (tarpaulins, camouflage nets, sacking) built to the mission's rectangles.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Site = preload("res://scripts/three_d/structures_site.gd")
const Props = preload("res://scripts/three_d/structures_props.gd")
const IRON := Color(0.22, 0.22, 0.22)
const OXIDE := Color(0.46, 0.27, 0.2)         # wagon red
const TIMBER := Color(0.62, 0.56, 0.46)
const LAMP_WARM := Color(1.0, 0.70, 0.40)
const FLOOD := Color(0.84, 0.90, 1.0)

var h: Node3D
var site: Site
var rng := RandomNumberGenerator.new()
var tracks: Array = [21.4, 25.6]

func _init(harbour: Node3D, s: Site, seed_value: int) -> void:
	h = harbour
	site = s
	rng.seed = seed_value

func build() -> void:
	tracks = h.sim.data.get("harbour", {}).get("yardTracks", [21.4, 25.6])
	_tracks()
	for item: Dictionary in h.sim.data.obstacles:
		var r: Rect2 = h.sim.rect_of(item)
		r = Rect2(r.position / 32.0, r.size / 32.0)
		match str(item.get("kind", "")):
			"wagon": _wagon(r, str(item.get("style", "box")), str(item.id))
			"building":
				var id := str(item.id)
				if id.begins_with("hangar"): _hangar(r, str(item.get("label", "")), id == "hangar-a")
				elif id == "batching": _batching_plant(r)
			"crates": _cases(r)
			"drums": _drums(r)
			"heap": _heap(r, str(item.get("material", "gravel")))
	for bush: Dictionary in h.sim.data.get("bushes", []):
		var r: Rect2 = h.sim.rect_of(bush)
		r = Rect2(r.position / 32.0, r.size / 32.0)
		_cover(r, str(bush.get("cover", "tarp")), str(bush.get("id", "")))
	_fence()
	_site_lights()

# ---------------------------------------------------------------------------------------------------------------
# Rail yard
# ---------------------------------------------------------------------------------------------------------------
func _tracks() -> void:
	var gauge := 1.435
	for z: float in tracks:
		var x := 22.4
		var piece := 0
		while x < 100.0:
			var x1 := minf(x + 20.0, 100.0)
			var kit := Kit.new()
			for s: float in [-0.5, 0.5]:
				var rz: float = float(z) + s * gauge
				kit.box("steel", Vector3((x + x1) * 0.5, 0.13, rz), Vector3(x1 - x, 0.13, 0.07), Color(0.18, 0.15, 0.13), Color(0.26, 0.22, 0.19))
				kit.box("steel", Vector3((x + x1) * 0.5, 0.2, rz), Vector3(x1 - x, 0.02, 0.07), Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.62))
			var sx := x + 0.3
			while sx < x1:
				var g := rng.randf_range(0.6, 0.9)
				kit.box("planks", Vector3(sx + h._props.jitter(0.03), 0.04, float(z) + h._props.jitter(0.04)), Vector3(0.24, 0.13, 2.5), Color(0.3, 0.27, 0.22) * g, Color(0.42, 0.37, 0.3) * g, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
				sx += 0.65
			h.commit(kit, h, "Track%d" % piece, true)
			x = x1
			piece += 1
		# buffer stop at the western end of each siding (where the mission has one: not under the cargo)
		var bx: float = float(h.sim.data.get("harbour", {}).get("bufferX", 22.6))
		var stands: bool = false
		for spot: Rect2 in h.footprints("buffer"):
			if spot.has_point(Vector2(bx + 0.8, float(z))): stands = true
		if not stands:
			continue
		var b := Kit.new()
		for s: float in [-0.5, 0.5]:
			var rz: float = float(z) + s * gauge
			b.beam("steel", Vector3(bx + 1.6, 0.2, rz), Vector3(bx, 1.0, rz), 0.12, 0.12, IRON * 0.6, IRON)
			b.beam("steel", Vector3(bx, 0.15, rz), Vector3(bx, 1.05, rz), 0.14, 0.14, IRON * 0.6, IRON)
		b.box("planks", Vector3(bx - 0.08, 0.95, float(z)), Vector3(0.3, 0.36, 2.4), OXIDE * 0.6, OXIDE)
		h.commit(b, h, "BufferStop", true)

## A goods wagon on the siding: "box" (a covered van), "tank" or "flat" (cases under a sheet).
func _wagon(r: Rect2, style: String, id: String) -> void:
	var kit := Kit.new()
	var c := r.get_center()
	var length := r.size.x
	var floor_y := 1.2
	var z := c.y
	# underframe, axles and wheels, buffers, couplers
	kit.box("steel", Vector3(c.x, floor_y - 0.25, z), Vector3(length - 0.2, 0.3, 2.3), Color(0.12, 0.11, 0.1), Color(0.2, 0.18, 0.16))
	for dx: float in [-length * 0.32, length * 0.32]:
		for s: float in [-0.72, 0.72]:
			kit.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x + dx, 0.5, z + s)))
			kit.lathe("steel", Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.5, 0.03), Vector2(0.5, 0.1), Vector2(0.15, 0.12)]), 14, Color(0.1, 0.09, 0.08), Color(0.25, 0.22, 0.2))
			kit.pop()
		kit.box("steel", Vector3(c.x + dx, 0.75, z), Vector3(0.5, 0.35, 2.0), Color(0.1, 0.1, 0.09), Color(0.18, 0.16, 0.15))
	for end: float in [-1.0, 1.0]:
		var ex := c.x + end * (length * 0.5 - 0.05)
		kit.box("steel", Vector3(ex, floor_y - 0.25, z), Vector3(0.18, 0.35, 2.5), Color(0.15, 0.12, 0.1), Color(0.3, 0.24, 0.2))
		for s: float in [-0.85, 0.85]:
			kit.push(Transform3D(Basis(Vector3.BACK, -end * PI * 0.5), Vector3(ex, floor_y - 0.25, z + s)))
			kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.08, 0.35), Vector2(0.2, 0.37), Vector2(0.2, 0.42)]), 10, IRON * 0.6, IRON)
			kit.pop()
	match style:
		"tank":
			kit.box("steel", Vector3(c.x, floor_y - 0.05, z), Vector3(length - 0.3, 0.1, 2.4), Color(0.15, 0.14, 0.13), Color(0.22, 0.2, 0.18))
			kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(c.x, floor_y + 1.15, z)))
			var half := length * 0.5 - 0.5
			kit.lathe("steel", Vector3(0, -half, 0), PackedVector2Array([Vector2(0.0, -0.35), Vector2(0.7, -0.25), Vector2(1.05, 0.0), Vector2(1.08, 0.2), Vector2(1.08, half * 2.0 - 0.2), Vector2(1.05, half * 2.0), Vector2(0.7, half * 2.0 + 0.25), Vector2(0.0, half * 2.0 + 0.35)]), 18, Color(0.16, 0.16, 0.16), Color(0.32, 0.31, 0.3), Vector2.ZERO, PackedFloat32Array(), 3.0)
			kit.pop()
			kit.lathe("steel", Vector3(c.x, floor_y + 2.15, z), PackedVector2Array([Vector2(0.45, 0.0), Vector2(0.45, 0.45), Vector2(0.5, 0.48), Vector2(0.0, 0.55)]), 12, Color(0.2, 0.2, 0.2), Color(0.32, 0.32, 0.31))
			for s: float in [-1.0, 1.0]:
				kit.box("planks", Vector3(c.x, floor_y + 2.25, z + s * 0.6), Vector3(length * 0.5, 0.05, 0.45), Color(0.3, 0.27, 0.22), Color(0.4, 0.36, 0.3))
			h._props.ladder(kit, Vector3(c.x + 0.6, 0.6, z + 1.25), Vector3(c.x + 0.6, floor_y + 2.3, z + 1.05), 0.45, IRON * 2.0)
		"flat":
			kit.box("planks", Vector3(c.x, floor_y, z), Vector3(length - 0.2, 0.12, 2.6), TIMBER * 0.5, TIMBER * 0.8, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
			for k: int in range(int(length / 1.4)):
				var sx := c.x - length * 0.5 + 0.7 + float(k) * 1.4
				for s: float in [-1.28, 1.28]:
					kit.beam("planks", Vector3(sx, floor_y, z + s), Vector3(sx, floor_y + 0.9, z + s), 0.09, 0.09, TIMBER * 0.5, TIMBER * 0.8)
			for k: int in range(3):
				var cx := c.x - length * 0.3 + float(k) * length * 0.3
				h._props.crate(kit, Vector3(cx, floor_y + 0.06, z), Vector3(1.6, 1.1, 2.0), h._props.jitter(0.05), k, Props.WOOD_PALE * h._props.tone(0.12))
			h._props.tarp(kit, Vector3(c.x, floor_y + 1.2, z), Vector2(length * 0.82, 2.0), 0.9, Color(0.36, 0.38, 0.3), [0.2, 0.2, 0.25, 0.25], int(c.x))
		_:
			# a covered van: planked sides on a steel frame, a sliding door, a curved roof
			var body := Rect2(c.x - length * 0.5 + 0.15, z - 1.3, length - 0.3, 2.6)
			kit.box("planks", Vector3(c.x, floor_y - 0.05, z), Vector3(body.size.x, 0.1, body.size.y), TIMBER * 0.3, TIMBER * 0.5)
			var wall_h := 2.3
			var faces: Array = [
				[Vector3(body.position.x, floor_y, body.end.y), Vector3(1, 0, 0), body.size.x],
				[Vector3(body.end.x, floor_y, body.end.y), Vector3(0, 0, -1), body.size.y],
				[Vector3(body.end.x, floor_y, body.position.y), Vector3(-1, 0, 0), body.size.x],
				[Vector3(body.position.x, floor_y, body.position.y), Vector3(0, 0, 1), body.size.y],
			]
			kit.push_tint(OXIDE * h._props.tone(0.15))
			for face: Array in faces:
				kit.wall("planks", face[0], face[1], face[2], wall_h, [], rng.randf() * 4.0, 0.0, 0.0, Kit.grey(0.6), Kit.grey(0.9))
			kit.pop_tint()
			# steel strapping on the long sides, the door with its runner
			for s: float in [-1.0, 1.0]:
				var fz := z + s * (body.size.y * 0.5 + 0.02)
				for k: int in range(5):
					var sx := body.position.x + float(k) * body.size.x / 4.0
					kit.box("steel", Vector3(sx, floor_y + wall_h * 0.5, fz), Vector3(0.1, wall_h, 0.03), IRON * 0.6, IRON)
				kit.beam("steel", Vector3(body.position.x, floor_y + 0.1, fz), Vector3(c.x - 1.1, floor_y + wall_h - 0.1, fz), 0.08, 0.03, IRON * 0.6, IRON)
				kit.beam("steel", Vector3(body.end.x, floor_y + 0.1, fz), Vector3(c.x + 1.1, floor_y + wall_h - 0.1, fz), 0.08, 0.03, IRON * 0.6, IRON)
				kit.box("planks", Vector3(c.x, floor_y + wall_h * 0.48, fz + s * 0.04), Vector3(2.0, wall_h * 0.94, 0.06), OXIDE * 0.5, OXIDE * 0.85)
				kit.box("steel", Vector3(c.x, floor_y + wall_h + 0.05, fz + s * 0.06), Vector3(4.2, 0.08, 0.06), IRON * 0.6, IRON)
			# curved roof
			var rows := 2
			var columns := 9
			var pts := PackedVector3Array()
			var uvs := PackedVector2Array()
			var cols := PackedColorArray()
			for i: int in range(rows):
				var x := body.position.x - 0.1 + float(i) * (body.size.x + 0.2)
				for j: int in range(columns):
					var a := lerpf(-1.0, 1.0, float(j) / float(columns - 1))
					pts.append(Vector3(x, floor_y + wall_h + 0.45 * (1.0 - a * a), z + a * (body.size.y * 0.5 + 0.12)))
					uvs.append(Vector2(x * Kit.UV_M, a))
					cols.append(Color(0.28, 0.28, 0.27))
			kit.patch("canvas", rows, columns, pts, uvs, cols, false, false)
			# stencilled reporting marks
			for s: float in [-1.0, 1.0]:
				var mark := Label3D.new()
				mark.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
				mark.font = h.stencil_font
				mark.text = "SNCF\n%s" % ("4 0%02d 113" % (int(c.x * 7.0) % 97))
				mark.font_size = 36
				mark.pixel_size = 0.005
				mark.modulate = Color(0.8, 0.78, 0.7, 0.8)
				mark.outline_size = 0
				mark.shaded = true
				mark.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				mark.transform = Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(body.position.x + 1.6 if s > 0.0 else body.end.x - 1.6, floor_y + 1.6, z + s * (body.size.y * 0.5 + 0.05)))
				h.add_child(mark)
	h.commit(kit, h, "Wagon_" + id, true, true)

# ---------------------------------------------------------------------------------------------------------------
# Warehouses
# ---------------------------------------------------------------------------------------------------------------
## A brick goods shed under a shallow corrugated roof, its big doors on the rail-yard side. Hangar 14 houses
## the harbour guard: its personnel door is the one the reinforcements come out of.
func _hangar(r: Rect2, label: String, guardhouse: bool) -> void:
	var eave := 5.4
	var ridge := 7.0
	var kit := Kit.new()
	var doors: Array[float] = [r.size.x * 0.28, r.size.x * 0.72]
	var north_open: Array = []
	for d: float in doors: north_open.append(Rect2(d - 1.8, 0.0, 3.6, 4.2))
	var faces: Array = [
		[Vector3(r.position.x, 0, r.end.y), Vector3(1, 0, 0), r.size.x, [Rect2(r.size.x * 0.5 - 1.0, 2.6, 2.0, 1.2)]],
		[Vector3(r.end.x, 0, r.end.y), Vector3(0, 0, -1), r.size.y, [Rect2(2.0, 2.8, 1.4, 1.0), Rect2(r.size.y - 3.4, 2.8, 1.4, 1.0)]],
		[Vector3(r.end.x, 0, r.position.y), Vector3(-1, 0, 0), r.size.x, north_open],
		[Vector3(r.position.x, 0, r.position.y), Vector3(0, 0, 1), r.size.y, [Rect2(2.0, 2.8, 1.4, 1.0), Rect2(r.size.y - 3.4, 2.8, 1.4, 1.0)]],
	]
	for f: int in range(4):
		var face: Array = faces[f]
		kit.wall("brick", face[0], face[1], face[2], eave, face[3], float(f) * 4.1, 0.0, 0.25)
	# gable ends up to the ridge (the ridge runs east-west)
	for s: float in [-1.0, 1.0]:
		var gx := r.position.x if s < 0.0 else r.end.x
		var a := Vector3(gx, eave, r.end.y if s > 0.0 else r.position.y)
		var b := Vector3(gx, eave, r.position.y if s > 0.0 else r.end.y)
		var top := Vector3(gx, ridge, r.get_center().y)
		kit.tri("brick", a, b, top, Vector2(a.z * Kit.UV_M, 0.0), Vector2(b.z * Kit.UV_M, 0.0), Vector2(top.z * Kit.UV_M, -(ridge - eave) * Kit.UV_M), Kit.grey(0.85), Kit.grey(0.85), Kit.grey(0.75))
	# roof: two slopes of corrugated iron with a little overhang, then the ridge cap
	var ov := 0.35
	for s: float in [-1.0, 1.0]:
		var ez := (r.position.y - ov) if s < 0.0 else (r.end.y + ov)
		var x0 := r.position.x - ov
		var x1 := r.end.x + ov
		var mid := r.get_center().y
		if s < 0.0:
			kit.quad_m("corrugated", Vector3(x1, eave - 0.1, ez), Vector3(x0, eave - 0.1, ez), Vector3(x0, ridge, mid), Vector3(x1, ridge, mid), Vector2(rng.randf(), 0.0), Kit.grey(0.55), Kit.grey(0.75), true)
		else:
			kit.quad_m("corrugated", Vector3(x0, eave - 0.1, ez), Vector3(x1, eave - 0.1, ez), Vector3(x1, ridge, mid), Vector3(x0, ridge, mid), Vector2(rng.randf(), 0.0), Kit.grey(0.55), Kit.grey(0.75), true)
	kit.box("steel", Vector3(r.get_center().x, ridge + 0.04, r.get_center().y), Vector3(r.size.x + ov * 2.0, 0.08, 0.5), Kit.grey(0.4), Kit.grey(0.6))
	# the big sliding doors: one shut, one open a crack on the dark inside
	for i: int in range(doors.size()):
		var dx := r.end.x - doors[i]
		var shut := i == 0 or not guardhouse
		var leaf_x := dx + (0.0 if shut else 1.4)
		kit.quad_rect("trim", Vector3(leaf_x + 1.8, 0.0, r.position.y - 0.12), Vector3(leaf_x - 1.8, 0.0, r.position.y - 0.12), Vector3(leaf_x - 1.8, 4.2, r.position.y - 0.12), Vector3(leaf_x + 1.8, 4.2, r.position.y - 0.12), Kit.trim_uv("slide_door"), Kit.grey(0.55), Kit.grey(0.8))
		kit.box("steel", Vector3(dx, 4.35, r.position.y - 0.14), Vector3(7.6, 0.1, 0.08), IRON * 0.6, IRON)
		if not shut:
			kit.quad4("glow", Vector3(dx - 0.4, 0.0, r.position.y + 0.3), Vector3(dx - 1.8, 0.0, r.position.y + 0.3), Vector3(dx - 1.8, 4.2, r.position.y + 0.3), Vector3(dx - 0.4, 4.2, r.position.y + 0.3), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.012, 0.012, 0.014), Color(0.012, 0.012, 0.014), Color(0.02, 0.02, 0.022), Color(0.02, 0.02, 0.022))
	# windows: dark, the office one lit behind its blackout curtain's edge
	var glass := Kit.new()
	for f: int in [1, 3]:
		var face: Array = faces[f]
		for o: Rect2 in face[3]:
			var origin: Vector3 = face[0]
			var right: Vector3 = face[1]
			var n: Vector3 = right.cross(Vector3.UP)
			var a: Vector3 = origin + right * o.position.x + Vector3.UP * o.position.y - n * 0.2
			var lit: bool = guardhouse and f == 3 and o.position.x < 3.0
			var col := Color(0.4, 0.24, 0.1) if lit else Color(0.025, 0.03, 0.035)
			glass.quad4("window", a, a + right * o.size.x, a + right * o.size.x + Vector3.UP * o.size.y, a + Vector3.UP * o.size.y, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, col, col * 1.3, col * 1.3)
	h.commit(glass, h, "HangarGlass", false)
	h.commit(kit, h, "Hangar_" + label.replace(" ", ""), true, true)
	# the number painted big on the north wall, a lamp over the doors
	var text := Label3D.new()
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
	text.font = h.stencil_font
	text.text = label
	text.font_size = 140
	text.pixel_size = 0.011
	text.modulate = Color(0.86, 0.84, 0.76, 0.7)
	text.outline_size = 0
	text.shaded = true
	text.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	text.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(r.get_center().x, 4.75, r.position.y - 0.04))
	h.add_child(text)
	var lamp_x := r.get_center().x
	var lk := Kit.new()
	h._props.wall_lamp(lk, Vector3(lamp_x, 4.55, r.position.y), PI, 0.45)
	lk.lathe("bulb", Vector3(lamp_x, 4.47, r.position.y - 0.45), PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.1, -0.02), Vector2(0.11, 0.03)]), 8)
	h.commit(lk, h, "HangarLamp", false)
	h.add_lamp(Vector3(lamp_x, 4.3, r.position.y - 0.5), LAMP_WARM, 2.2, 9.0, true, 0.8, 1.0)
	if guardhouse:
		# the guard's own door, in the wall beside the big ones: it swings open when the men turn out
		var door_x := float(h.sim.data.get("reinforcements", {}).get("spawn", [[1024, 905]])[0][0]) / 32.0
		var hinge := Vector3(door_x - 0.5, 0.0, r.position.y - 0.05)
		var cut := Kit.new()
		cut.quad4("glow", Vector3(door_x + 0.5, 0.0, r.position.y - 0.02), Vector3(door_x - 0.5, 0.0, r.position.y - 0.02), Vector3(door_x - 0.5, 2.1, r.position.y - 0.02), Vector3(door_x + 0.5, 2.1, r.position.y - 0.02), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.3, 0.18, 0.08), Color(0.3, 0.18, 0.08), Color(0.22, 0.13, 0.06), Color(0.22, 0.13, 0.06))
		h.commit(cut, h, "GuardDoorway", false)
		h.barracks_door = Node3D.new()
		h.barracks_door.name = "GuardDoor"
		h.barracks_door.position = hinge
		h.add_child(h.barracks_door)
		var leaf := Kit.new()
		leaf.quad_rect("trim", Vector3(1.0, 0.0, -0.04), Vector3(0.0, 0.0, -0.04), Vector3(0.0, 2.1, -0.04), Vector3(1.0, 2.1, -0.04), Kit.trim_uv("door_plank"), Kit.grey(0.5), Kit.grey(0.75))
		leaf.quad_rect("trim", Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 2.1, 0.0), Vector3(0.0, 2.1, 0.0), Kit.trim_uv("door_plank"), Kit.grey(0.4), Kit.grey(0.6))
		h.commit(leaf, h.barracks_door, "Leaf", true)
		h._door_closed = Basis.IDENTITY
		h._door_sign = 1.0
		h.door_point = Vector3(door_x, 0.0, r.position.y - 0.4)
		h.buildings.append({"node": h.barracks_door, "roof": h.barracks_door, "id": "hangar-a"})

# ---------------------------------------------------------------------------------------------------------------
# Building site
# ---------------------------------------------------------------------------------------------------------------
## The concrete plant: a shed at the foot (the solid part of its footprint), the mixer, the hopper and the
## cement silo up on their steel legs, and the skip hoist running up the side.
func _batching_plant(r: Rect2) -> void:
	var kit := Kit.new()
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var faces: Array = [
		[Vector3(r.position.x, 0, r.end.y), Vector3(1, 0, 0), r.size.x],
		[Vector3(r.end.x, 0, r.end.y), Vector3(0, 0, -1), r.size.y],
		[Vector3(r.end.x, 0, r.position.y), Vector3(-1, 0, 0), r.size.x],
		[Vector3(r.position.x, 0, r.position.y), Vector3(0, 0, 1), r.size.y],
	]
	for f: int in range(4):
		var face: Array = faces[f]
		kit.wall("corrugated", face[0], face[1], face[2], 3.0, [Rect2(0.6, 0.0, 1.4, 2.4)] if f == 0 else [], float(f), 0.0, 0.1, Kit.grey(0.45), Kit.grey(0.7))
	kit.quad_m("corrugated", Vector3(r.position.x - 0.2, 3.1, r.end.y + 0.2), Vector3(r.end.x + 0.2, 3.1, r.end.y + 0.2), Vector3(r.end.x + 0.2, 3.4, r.position.y - 0.2), Vector3(r.position.x - 0.2, 3.4, r.position.y - 0.2), Vector2.ZERO, Kit.grey(0.5), Kit.grey(0.6))
	# legs and the platform
	for dx: float in [-1.4, 1.4]:
		for dz: float in [-1.2, 1.2]:
			kit.beam("steel", c + Vector3(dx, 0, dz), c + Vector3(dx * 0.9, 9.0, dz * 0.9), 0.2, 0.2, IRON * 0.7, IRON * 1.2, Vector2.ZERO, false)
	kit.box("planks", c + Vector3(0, 6.0, 0), Vector3(3.2, 0.12, 2.8), TIMBER * 0.5, TIMBER * 0.8)
	# hopper: an upturned pyramid of plate
	var top := 9.0
	var mouth := 5.0
	var hw := 1.5
	for k: int in range(4):
		var a := Basis(Vector3.UP, PI * 0.5 * float(k))
		var p0 := c + a * Vector3(-hw, top, hw)
		var p1 := c + a * Vector3(hw, top, hw)
		var p2 := c + a * Vector3(0.3, mouth + 1.2, 0.3)
		var p3 := c + a * Vector3(-0.3, mouth + 1.2, 0.3)
		kit.quad_m("steel", p3, p2, p1, p0, Vector2(float(k), 0.0), Color(0.4, 0.38, 0.34), Color(0.55, 0.53, 0.48))
	# the cement silo beside it and its feed screw
	var silo := c + Vector3(-r.size.x * 0.5 - 1.3, 0, -0.4)
	for spot: Rect2 in h.footprints("", "silo"):
		silo = Vector3(spot.get_center().x, 0.0, spot.get_center().y)
	for dx: float in [-0.8, 0.8]:
		for dz: float in [-0.8, 0.8]:
			kit.beam("steel", silo + Vector3(dx, 0, dz), silo + Vector3(dx * 0.7, 3.2, dz * 0.7), 0.16, 0.16, IRON * 0.7, IRON * 1.2, Vector2.ZERO, false)
	kit.lathe("steel", silo + Vector3(0, 2.6, 0), PackedVector2Array([Vector2(0.15, 0.0), Vector2(1.15, 1.5), Vector2(1.15, 9.5), Vector2(0.9, 9.9), Vector2(0.3, 10.0)]), 16, Color(0.45, 0.45, 0.43), Color(0.6, 0.6, 0.57), Vector2.ZERO, PackedFloat32Array(), 3.0)
	kit.beam("steel", silo + Vector3(0.5, 3.2, 0), c + Vector3(-0.8, 8.2, -0.3), 0.28, 0.28, Color(0.4, 0.4, 0.38), Color(0.55, 0.55, 0.52), Vector2.ZERO, false)
	# skip hoist rails and the skip halfway up
	for s: float in [-0.5, 0.5]:
		kit.beam("steel", c + Vector3(r.size.x * 0.5 + 2.2, 0.0, s), c + Vector3(1.0, 9.6, s), 0.1, 0.1, IRON * 0.7, IRON * 1.2, Vector2.ZERO, false)
	kit.box("steel", c + Vector3(r.size.x * 0.5 + 0.9, 4.2, 0), Vector3(1.0, 0.8, 1.1), Color(0.4, 0.35, 0.3), Color(0.5, 0.44, 0.38))
	h.commit(kit, h, "BatchingPlant", true, true)
	var board := Label3D.new()
	board.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
	board.font = h.SIGN_FONT
	board.text = "BAUSTELLE\nZUTRITT VERBOTEN"
	board.font_size = 34
	board.pixel_size = 0.006
	board.modulate = Color(0.85, 0.82, 0.72, 0.85)
	board.outline_size = 0
	board.shaded = true
	board.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	board.position = Vector3(c.x + 0.6, 2.2, r.end.y + 0.03)
	h.add_child(board)

## Gravel or sand, tipped in a heap and shovelled at: a lumpy mound filling its rectangle.
func _heap(r: Rect2, material: String) -> void:
	var kit := Kit.new()
	var rows := 9
	var columns := 11
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var noise := FastNoiseLite.new()
	noise.seed = int(r.position.x * 13.0)
	noise.frequency = 0.9
	var peak: float = {"gravel": 1.9, "coal": 2.2}.get(material, 1.5)
	var tint: Color = {"gravel": Color(0.62, 0.6, 0.56), "coal": Color(0.16, 0.16, 0.17)}.get(material, Color(0.82, 0.74, 0.58))
	for i: int in range(rows):
		var v := float(i) / float(rows - 1)
		for j: int in range(columns):
			var u := float(j) / float(columns - 1)
			var x := r.position.x - 0.3 + u * (r.size.x + 0.6)
			var z := r.position.y - 0.3 + v * (r.size.y + 0.6)
			var dx := (u - 0.5) * 2.0
			var dz := (v - 0.5) * 2.0
			var d := clampf(sqrt(dx * dx * 0.9 + dz * dz), 0.0, 1.0)
			var y := peak * pow(1.0 - d, 1.25) * (0.85 + 0.3 * noise.get_noise_2d(x * 2.0, z * 2.0))
			if d >= 0.999: y = -0.05
			pts.append(Vector3(x, y, z))
			uvs.append(Vector2(x, z) * 0.6)
			cols.append(tint * (0.6 + 0.4 * clampf(y / peak + 0.3, 0.0, 1.0)))
	kit.patch("shingle", rows, columns, pts, uvs, cols, false, true)
	# a shovel stuck in it and a barrow by the foot
	var foot := Vector3(r.end.x - 0.2, 0, r.end.y + 0.25)
	kit.beam("planks", foot + Vector3(-0.6, 0.9, -0.6), foot + Vector3(-0.2, 2.0, -0.2), 0.04, 0.04, TIMBER * 0.6, TIMBER)
	_barrow(kit, foot + Vector3(0.6, 0, 0.4), 0.6)
	h.commit(kit, h, "Heap", true)

func _barrow(kit: Kit, at: Vector3, yaw: float) -> void:
	kit.push_at(at, yaw)
	kit.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.55, 0.18, 0)))
	kit.lathe("rubber", Vector3(0, -0.04, 0), PackedVector2Array([Vector2(0.18, 0.0), Vector2(0.18, 0.08)]), 10, Kit.grey(0.3), Kit.grey(0.4))
	kit.pop()
	kit.lathe("steel", Vector3(0.0, 0.25, 0), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.38, 0.28), Vector2(0.4, 0.3)]), 10, Color(0.3, 0.32, 0.3), Color(0.4, 0.42, 0.38))
	for s: float in [-0.22, 0.22]:
		kit.beam("planks", Vector3(0.55, 0.2, s * 0.5), Vector3(-0.9, 0.55, s), 0.04, 0.04, TIMBER * 0.5, TIMBER * 0.8)
	kit.pop()

## The building site's wire along the rails of the yard: posts and mesh as in the outpost, its cuttable span
## built twice (whole, cut) for the rules; and the short stub closing the gap to the basin.
func _fence() -> void:
	var span: Dictionary = {}
	var z := 18.68
	for barrier: Dictionary in h.sim.data.get("barriers", []):
		if bool(barrier.get("cuttable", false)):
			span = barrier
			z = (float(barrier.y) + float(barrier.h) * 0.5) / 32.0
	var cut_x0 := float(span.get("x", 1440)) / 32.0
	var cut_w := float(span.get("w", 77)) / 32.0
	var spans := 13
	var x0 := cut_x0 - cut_w
	var x1 := x0 + cut_w * float(spans)
	var solid := Kit.new()
	var wire := Kit.new()
	var left: Array[Vector3] = site.fence(solid, wire, x0, x1, z, spans, 1)
	# the stub from the corner post north to the basin edge
	var corner := Vector3(x0 + 0.02, 0.0, z)
	var basin_end := Vector3(x0 + 0.02, 0.0, 17.45)
	solid.beam("planks", basin_end + Vector3(0, -0.1, 0), basin_end + Vector3(0, 1.45, 0), 0.12, 0.12, TIMBER * 0.5, TIMBER * 0.8)
	wire.quad4("wire", corner + Vector3(0, 0.03, 0), basin_end + Vector3(0, 0.03, 0), basin_end + Vector3(0, 0.95, 0), corner + Vector3(0, 0.95, 0), Vector2(0, Kit.WIRE_MESH.y), Vector2(0.5, Kit.WIRE_MESH.y), Vector2(0.5, Kit.WIRE_MESH.x), Vector2(0, Kit.WIRE_MESH.x), Site.WIRE_COL, Site.WIRE_COL, Site.WIRE_COL, Site.WIRE_COL)
	h.commit(solid, h, "SiteFencePosts", true)
	h.commit(wire, h, "SiteFenceWire", false)
	if left.size() >= 5:
		var whole := Kit.new()
		h._rules.span_whole(whole, left[0], left[1], left[2], left[3], left[4].x)
		h.fence_whole = h.commit(whole, h, "FenceSpanWhole", false)
		var cut := Kit.new()
		h._rules.span_cut(cut, left[0], left[1], left[2], left[3], left[4].x)
		h.fence_cut = h.commit(cut, h, "FenceSpanCut", false)
	# a plate on the wire, in two languages
	var plate := Label3D.new()
	plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
	plate.font = h.SIGN_FONT
	plate.text = "BAUSTELLE - BETRETEN VERBOTEN\nCHANTIER - DÉFENSE D'ENTRER"
	plate.font_size = 28
	plate.pixel_size = 0.005
	plate.modulate = Color(0.85, 0.8, 0.66, 0.9)
	plate.outline_size = 0
	plate.shaded = true
	plate.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	plate.position = Vector3(x0 + cut_w * 3.5, 1.05, z + 0.08)
	h.add_child(plate)

## Floodlights on the building site: night shifts were usual, tonight there is only the guard.
func _site_lights() -> void:
	var kit := Kit.new()
	var pole := Vector3(52.6, 0.0, 17.9)
	for spot: Rect2 in h.footprints("", "flood-mast"):
		pole = Vector3(spot.get_center().x, 0.0, spot.get_center().y)
	h._props.utility_pole(kit, pole, 0.0, 8.0, 0, 0.0)
	var heads: Array[Vector3] = [pole + Vector3(-0.35, 7.7, -0.25), pole + Vector3(0.35, 7.7, -0.25)]
	for head: Vector3 in heads:
		kit.box("steel", head, Vector3(0.5, 0.4, 0.3), Color(0.2, 0.22, 0.2), Color(0.3, 0.32, 0.3))
		kit.quad4("bulb", head + Vector3(-0.22, -0.18, -0.16), head + Vector3(0.22, -0.18, -0.16), head + Vector3(0.22, 0.18, -0.16), head + Vector3(-0.22, 0.18, -0.16), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE)
	h.commit(kit, h, "FloodMast", true)
	h.add_lamp(pole + Vector3(0, 7.2, -1.2), FLOOD, 3.2, 13.0, true, 1.4, 1.6)
	# a floodlight clamped to the top of the scaffold, turned into pen 4
	var fl := Vector3(52.2, 8.9, 9.6)
	var fk := Kit.new()
	fk.box("steel", fl, Vector3(0.5, 0.4, 0.3), Color(0.2, 0.22, 0.2), Color(0.3, 0.32, 0.3))
	fk.quad4("bulb", fl + Vector3(0.26, -0.18, 0.15), fl + Vector3(0.26, -0.18, -0.15), fl + Vector3(0.26, 0.18, -0.15), fl + Vector3(0.26, 0.18, 0.15), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE)
	h.commit(fk, h, "PenFlood", false)
	h.add_lamp(fl + Vector3(1.5, -1.0, -1.5), FLOOD, 2.6, 11.0, true, 1.1, 1.3)
	# a lamp on Hangar 15's west wall over the lane
	var ll := Vector3(44.5, 3.4, 36.6)
	var lk := Kit.new()
	h._props.wall_lamp(lk, ll, -PI * 0.5, 0.4)
	lk.lathe("bulb", ll + Vector3(-0.4, -0.08, 0), PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.1, -0.02), Vector2(0.11, 0.03)]), 8)
	h.commit(lk, h, "LaneLamp", false)
	h.add_lamp(ll + Vector3(-0.45, -0.25, 0), LAMP_WARM, 1.6, 7.0, true, 0.7, 1.0)

# ---------------------------------------------------------------------------------------------------------------
# Cargo and cover
# ---------------------------------------------------------------------------------------------------------------
## Shipping cases stacked two high, lashed, with stencilled marks.
func _cases(r: Rect2) -> void:
	var kit := Kit.new()
	var nx := maxi(1, int(r.size.x / 1.3))
	var nz := maxi(1, int(r.size.y / 1.2))
	var w := r.size.x / float(nx)
	var d := r.size.y / float(nz)
	for i: int in range(nx):
		for j: int in range(nz):
			var c := Vector3(r.position.x + (float(i) + 0.5) * w, 0.0, r.position.y + (float(j) + 0.5) * d)
			var hgt := rng.randf_range(0.9, 1.25)
			h._props.crate(kit, c, Vector3(w - 0.08, hgt, d - 0.08), h._props.jitter(0.04), (i + j) % 5, Props.WOOD_PALE * h._props.tone(0.15))
			if rng.randf() < 0.7:
				h._props.crate(kit, c + Vector3(h._props.jitter(0.1), hgt, h._props.jitter(0.1)), Vector3(w - 0.25, rng.randf_range(0.6, 0.9), d - 0.25), h._props.jitter(0.12), (i * 3 + j) % 5, Props.WOOD_PALE * h._props.tone(0.18))
	h.commit(kit, h, "Cases", true)

func _drums(r: Rect2) -> void:
	var kit := Kit.new()
	var tints: Array[Color] = [Props.DRAB, Color(0.55, 0.43, 0.35), Props.DRAB_DARK, Color(0.5, 0.56, 0.6), Color(0.25, 0.25, 0.27)]
	var x := r.position.x + 0.32
	var k := 0
	while x < r.end.x - 0.2:
		var z := r.position.y + 0.32
		while z < r.end.y - 0.2:
			h._props.barrel(kit, Vector3(x + h._props.jitter(0.04), 0.0, z + h._props.jitter(0.04)), tints[k % tints.size()] * h._props.tone(0.2), rng.randf() * TAU)
			z += 0.62
			k += 3
		x += 0.62
		k += 1
	h.commit(kit, h, "Drums", true)

## A hiding place: what is there to crouch under, filling the mission's rectangle.
func _cover(r: Rect2, cover: String, id: String) -> void:
	var kit := Kit.new()
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	match cover:
		"net":
			# crates under a camouflage net staked out to the ground
			h._props.crate(kit, c + Vector3(-0.35, 0, 0), Vector3(r.size.x * 0.5, 1.0, r.size.y * 0.6), 0.05, 1, Props.WOOD_PALE * 0.8)
			h._props.crate(kit, c + Vector3(r.size.x * 0.22, 0, 0.1), Vector3(r.size.x * 0.35, 0.8, r.size.y * 0.5), -0.1, 3, Props.WOOD_PALE * 0.75)
			_net(kit, r, 1.25)
		"sacks":
			for row: int in range(3):
				var y := float(row) * 0.2
				var n := int(r.size.x / 0.66) - row
				for i: int in range(n):
					for j: int in range(int(r.size.y / 0.4) - row):
						var p := Vector3(r.position.x + 0.4 + float(i) * 0.66 + 0.33 * float(row), y, r.position.y + 0.3 + float(j) * 0.4 + 0.2 * float(row))
						if p.x > r.end.x - 0.3 or p.z > r.end.y - 0.2: continue
						h._props.sandbag(kit, p, h._props.jitter(0.1), 0.62, 0.36, 0.2, Color(0.72, 0.66, 0.54) * h._props.tone(0.15))
			h._props.tarp(kit, c + Vector3(0.2, 0.62, -0.1), Vector2(r.size.x * 0.55, r.size.y * 0.6), 0.5, Color(0.32, 0.34, 0.28), [0.2, 0.3, 0.2, 0.3], int(c.x))
		"canvas":
			h._props.crate(kit, c, Vector3(r.size.x - 0.5, 1.1, r.size.y - 0.6), 0.02, 2, Props.WOOD_PALE * 0.7)
			h._props.tarp(kit, c + Vector3(0, 1.1, 0), Vector2(r.size.x - 0.5, r.size.y - 0.6), 1.0, Color(0.42, 0.42, 0.36), [0.25, 0.25, 0.25, 0.25], int(c.z * 3.0))
		_:
			# a stack of cases under a tarpaulin, its skirts not quite to the ground: room to crawl under
			var top := 1.35
			h._props.crate(kit, c + Vector3(-r.size.x * 0.18, 0, 0), Vector3(r.size.x * 0.5, top, r.size.y - 0.7), 0.03, 0, Props.WOOD_PALE * 0.8)
			h._props.crate(kit, c + Vector3(r.size.x * 0.25, 0, -0.1), Vector3(r.size.x * 0.32, top - 0.3, r.size.y - 0.9), -0.05, 2, Props.WOOD_PALE * 0.75)
			h._props.tarp(kit, c + Vector3(0, top, 0), Vector2(r.size.x - 0.6, r.size.y - 0.7), top - 0.25, Color(0.34, 0.36, 0.30), [0.3, 0.3, 0.35, 0.35], int(c.x * 7.0 + c.z))
			_lashing(kit, c, Vector2(r.size.x - 0.6, r.size.y - 0.7), top)
	h.commit(kit, h, "Cover_" + id, true)

func _lashing(kit: Kit, c: Vector3, size: Vector2, top: float) -> void:
	for dx: float in [-0.3, 0.3]:
		var x := c.x + dx * size.x
		var hz := size.y * 0.5 + 0.35
		kit.tube("burlap", PackedVector3Array([Vector3(x, 0.05, c.z + hz), Vector3(x, top + 0.04, c.z + size.y * 0.5), Vector3(x, top + 0.06, c.z - size.y * 0.5), Vector3(x, 0.05, c.z - hz)]), 0.016, 4, Color(0.7, 0.64, 0.5), Vector2.ZERO, 0.25, 6.0)

## A camouflage net: the wire material's mesh band, tinted, sagging between the high points and pegged down.
func _net(kit: Kit, r: Rect2, height: float) -> void:
	var rows := 8
	var columns := 9
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var noise := FastNoiseLite.new()
	noise.seed = int(r.position.x * 31.0)
	noise.frequency = 1.6
	for i: int in range(rows):
		var v := float(i) / float(rows - 1)
		for j: int in range(columns):
			var u := float(j) / float(columns - 1)
			var x := r.position.x - 0.2 + u * (r.size.x + 0.4)
			var z := r.position.y - 0.2 + v * (r.size.y + 0.4)
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v)) * 2.0
			var y := height * pow(clampf(edge * 1.6, 0.0, 1.0), 0.6) + 0.12 * noise.get_noise_2d(x * 3.0, z * 3.0)
			pts.append(Vector3(x, maxf(0.02, y), z))
			uvs.append(Vector2(x * Kit.UV_M * 1.5, lerpf(Kit.WIRE_MESH.y, Kit.WIRE_MESH.x, fposmod(z * 0.6, 1.0))))
			var g := 0.7 + 0.3 * noise.get_noise_2d(x * 7.0, z * 7.0)
			cols.append(Color(0.34, 0.36, 0.24) * g)
	kit.patch("wire", rows, columns, pts, uvs, cols, false, true)
	# burlap scrim garnish tied into it
	for k: int in range(14):
		var p := Vector3(r.position.x + rng.randf() * r.size.x, 0.0, r.position.y + rng.randf() * r.size.y)
		var u := (p.x - r.position.x) / r.size.x
		var v := (p.z - r.position.y) / r.size.y
		var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v)) * 2.0
		p.y = height * pow(clampf(edge * 1.6, 0.0, 1.0), 0.6) + 0.02
		kit.quad_m("burlap", p + Vector3(-0.25, 0, -0.1), p + Vector3(0.25, 0, -0.1), p + Vector3(0.25, 0.02, 0.15), p + Vector3(-0.25, 0.02, 0.15), Vector2(rng.randf(), rng.randf()), Color(0.4, 0.38, 0.26), Color(0.48, 0.46, 0.3))
