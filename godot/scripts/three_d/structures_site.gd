extends RefCounted
## Everything on the site that is not a building or the truck: the holding-cell compound and its gate, crate stacks,
## the sandbag post, drums, the perimeter fence, utility poles, the watchtower and the landing stage with its boat.
## All positions are world space unless a function says otherwise.
const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Props = preload("res://scripts/three_d/structures_props.gd")

var props: Props
var rng := RandomNumberGenerator.new()

const STONE_AO := Color(0.6, 0.57, 0.52)
const GATE_PAINT := Color(0.3, 0.33, 0.31)
const WIRE_COL := Color(0.75, 0.72, 0.68)

func _init(p: Props, seed_value: int) -> void:
	props = p
	rng.seed = seed_value

# ---------------------------------------------------------------------------------------------------------------
# Holding-cell compound
# ---------------------------------------------------------------------------------------------------------------
## walls: Array[Rect2] in metres (x, z). door: Rect2 of the gate opening. `wire` receives the non-shadowing parts.
func compound(k: Kit, wire: Kit, flat: Kit, walls: Array[Rect2], door: Rect2) -> void:
	if walls.is_empty():
		return
	var bounds: Rect2 = walls[0]
	for r: Rect2 in walls:
		bounds = bounds.merge(r)
	var wall_h := 1.5
	var thick := 0.62
	for r: Rect2 in walls:
		var along_x := r.size.x >= r.size.y
		var length := r.size.x if along_x else r.size.y
		var c := r.get_center()
		# local frame: X along the wall, Z across it
		var xf := Transform3D(Basis.IDENTITY if along_x else Basis(Vector3.UP, PI * 0.5), Vector3(c.x, 0, c.y))
		k.push(xf)
		var hl := length * 0.5
		var u0 := rng.randf() * 5.0
		# stepped plinth across the whole obstacle footprint, then the wall proper
		k.box("stone", Vector3(0, 0.17, 0), Vector3(length, 0.34, r.size.y if along_x else r.size.x), STONE_AO, Kit.grey(0.92), Vector2(u0 * Kit.UV_M, 1.0), Kit.UPRIGHT, 0b110111)
		for s: float in [1.0, -1.0]:
			k.wall("stone", Vector3(-hl * s, 0.34, thick * 0.5 * s), Vector3(s, 0, 0), length, wall_h - 0.34, [], u0 + (0.0 if s > 0.0 else 7.3), 0.34, 0.0, Color(0.78, 0.75, 0.7), Color(0.8, 0.8, 0.82), 0.3, 0.12)
		# coping stones: overhanging concrete slabs with open joints
		var n := int(round(length / 0.9))
		for i: int in range(n):
			var x0 := -hl + length * float(i) / float(n)
			var x1 := -hl + length * float(i + 1) / float(n)
			var g := rng.randf_range(0.82, 1.0)
			k.box("concrete", Vector3((x0 + x1) * 0.5, wall_h + 0.045 + rng.randf() * 0.008, 0), Vector3(x1 - x0 - 0.018, 0.09, thick + 0.14), Color(0.6, 0.58, 0.54) * Kit.grey(g), Color(0.86, 0.84, 0.8) * Kit.grey(g), Vector2(rng.randf(), rng.randf()))
		# buttresses on both faces
		var nb := maxi(0, int(floor(length / 2.4)) - 1)
		for i: int in range(nb):
			var bx := -hl + length * float(i + 1) / float(nb + 1)
			for s: float in [1.0, -1.0]:
				k.box("stone", Vector3(bx, 0.6, s * 0.4), Vector3(0.46, 1.2, 0.2), STONE_AO, Kit.grey(0.95), Vector2(rng.randf(), 1.0), Kit.UPRIGHT, 0b110111)
				# weathered sloping cap
				k.quad_m("concrete", Vector3(bx - 0.25 * s, 1.2, s * 0.52), Vector3(bx + 0.25 * s, 1.2, s * 0.52), Vector3(bx + 0.25 * s, 1.36, s * 0.3), Vector3(bx - 0.25 * s, 1.36, s * 0.3), Vector2(rng.randf(), rng.randf()), Kit.grey(0.85), Kit.grey(0.95))
		_wall_wire(k, wire, length, wall_h + 0.09)
		k.pop()
		# ground contact
		var out_col := Color(0.07, 0.06, 0.04, 0.5)
		var sr := Kit.cell_uv(Kit.DECAL["skirt"], 3.0)
		for s: float in [1.0, -1.0]:
			var a := xf * Vector3(-hl * s, 0.03, (r.size.y if along_x else r.size.x) * 0.5 * s)
			var b := xf * Vector3(hl * s, 0.03, (r.size.y if along_x else r.size.x) * 0.5 * s)
			var o := xf.basis * Vector3(0, 0, 0.6 * s)
			flat.quad4("decal", a + o, b + o, b, a, Vector2(sr.position.x, sr.end.y), sr.end, Vector2(sr.end.x, sr.position.y), sr.position, out_col, out_col, out_col, out_col)
	# corner piers
	for cx: float in [bounds.position.x + 0.5, bounds.end.x - 0.5]:
		for cz: float in [bounds.position.y + 0.5, bounds.end.y - 0.5]:
			_pier(k, Vector3(cx, 0, cz), Vector2(1.04, 1.04), 1.82)
	# gate piers at the ends of the opening
	var gz := door.get_center().y
	_pier(k, Vector3(door.position.x - 0.27, 0, gz), Vector2(0.56, 1.04), 1.95)
	_pier(k, Vector3(door.end.x + 0.27, 0, gz), Vector2(0.56, 1.04), 1.95)
	# threshold slab, worn earth in the gateway, a notice by the gate and a lamp on the pier
	k.box("concrete", Vector3(door.get_center().x, 0.02, gz), Vector3(door.size.x, 0.04, 1.0), Kit.grey(0.7), Kit.grey(0.85), Vector2(0.2, 0.3), Kit.AUTO, 0b000100)
	flat.decal(Kit.DECAL["dirt"], door.get_center().x, gz + 1.2, Vector2(2.6, 2.2), 0.3, Color(0.8, 0.76, 0.68, 0.75))
	flat.decal(Kit.DECAL["dirt"], door.get_center().x, gz - 1.3, Vector2(2.4, 2.4), 2.0, Color(0.8, 0.76, 0.68, 0.6))
	var pr := Kit.trim_uv("plate_warn")
	var px := door.end.x + 0.95
	var pz := bounds.end.y - 0.5 + 0.315
	k.quad_rect("trim", Vector3(px, 0.95, pz), Vector3(px + 0.42, 0.95, pz), Vector3(px + 0.42, 1.24, pz), Vector3(px, 1.24, pz), pr)
	props.wall_lamp(k, Vector3(door.position.x - 0.27, 1.9, gz + 0.52), 0.0, 0.28)

func _pier(k: Kit, at: Vector3, size: Vector2, height: float) -> void:
	k.box("stone", at + Vector3(0, height * 0.5, 0), Vector3(size.x, height, size.y), STONE_AO, Kit.grey(0.98), Vector2(rng.randf(), 1.0), Kit.UPRIGHT, 0b110011)
	k.box("concrete", at + Vector3(0, height + 0.05, 0), Vector3(size.x + 0.12, 0.1, size.y + 0.12), Color(0.62, 0.6, 0.56), Color(0.86, 0.84, 0.8), Vector2(rng.randf(), rng.randf()))
	# shallow pyramid cap
	var y0 := height + 0.1
	var hx := size.x * 0.5 + 0.02
	var hz := size.y * 0.5 + 0.02
	var apex := at + Vector3(0, y0 + 0.14, 0)
	var c: Array[Vector3] = [at + Vector3(-hx, y0, hz), at + Vector3(hx, y0, hz), at + Vector3(hx, y0, -hz), at + Vector3(-hx, y0, -hz)]
	for i: int in range(4):
		k.tri("concrete", c[i], c[(i + 1) % 4], apex, Vector2(0.1, 0.3), Vector2(0.1 + hx * Kit.UV_M * 2.0, 0.3), Vector2(0.1 + hx * Kit.UV_M, 0.2), Color(0.78, 0.76, 0.72), Color(0.78, 0.76, 0.72), Color(0.9, 0.88, 0.84))

## Barbed wire along a wall top (wall-local frame: X along, y = top of coping): angle-iron stanchions, three taut
## strands and a concertina coil drawn as two crossed cut-out cards.
func _wall_wire(k: Kit, wire: Kit, length: float, y: float) -> void:
	var hl := length * 0.5
	var n := maxi(1, int(round(length / 1.7)))
	var iron := Props.IRON_RUST
	for i: int in range(n + 1):
		var x := -hl + 0.2 + (length - 0.4) * float(i) / float(n)
		k.beam("steel", Vector3(x, y - 0.02, 0), Vector3(x, y + 0.52, 0), 0.035, 0.035, iron * Kit.grey(0.8), iron, Vector2(rng.randf(), rng.randf()), false)
	wire.push(k.xf)
	for h: float in [0.2, 0.35, 0.5]:
		wire.tube("steel", PackedVector3Array([Vector3(-hl + 0.2, y + h, 0), Vector3(hl - 0.2, y + h, 0)]), 0.009, 3, Color(0.3, 0.28, 0.27))
	var u1 := length / 1.9
	var v := Kit.WIRE_COIL
	for tilt: float in [-0.75, 0.75]:
		var up := Vector3(0, cos(tilt), sin(tilt)) * 0.22
		var c := Vector3(0, y + 0.2, 0)
		wire.quad4("wire", c + Vector3(-hl + 0.1, 0, 0) - up, c + Vector3(hl - 0.1, 0, 0) - up, c + Vector3(hl - 0.1, 0, 0) + up, c + Vector3(-hl + 0.1, 0, 0) + up,
			Vector2(0, v.y), Vector2(u1, v.y), Vector2(u1, v.x), Vector2(0, v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
	wire.pop()

## Barred iron gate, built in gate-local space: hinge on the origin, leaf extends 2 m along +X.
func gate(k: Kit, width: float = 2.0) -> void:
	var h := 1.74
	k.push_tint(GATE_PAINT)
	var lo := Kit.grey(0.7)
	# frame
	for x: float in [0.03, width - 0.03]:
		k.box("steel", Vector3(x, h * 0.5 + 0.05, 0), Vector3(0.06, h, 0.06), lo, Color.WHITE, Vector2(rng.randf(), rng.randf()))
	for y: float in [0.11, 0.92, h + 0.02]:
		k.box("steel", Vector3(width * 0.5, y, 0), Vector3(width - 0.12, 0.055, 0.05), Kit.grey(0.8), Color.WHITE, Vector2(rng.randf(), rng.randf()))
	# round bars with spear points
	var bars := 12
	for i: int in range(bars):
		var x := 0.12 + (width - 0.24) * float(i) / float(bars - 1)
		k.lathe("steel", Vector3(x, 0.11, 0), PackedVector2Array([Vector2(0.014, 0.0), Vector2(0.014, h + 0.02), Vector2(0.024, h + 0.05), Vector2(0.002, h + 0.14)]), 5, lo, Color.WHITE, Vector2(rng.randf(), 0.0))
	# plated lower third, diagonal brace, lock box and hinge knuckles
	k.box("steel", Vector3(width * 0.5, 0.52, 0), Vector3(width - 0.14, 0.76, 0.014), Kit.grey(0.62), Kit.grey(0.9), Vector2(0.3, 0.1))
	k.beam("steel", Vector3(0.08, 0.16, 0.03), Vector3(width - 0.08, 0.88, 0.03), 0.012, 0.05, Kit.grey(0.8), Color.WHITE, Vector2.ZERO, false)
	k.pop_tint()
	var lock := Kit.trim_uv("lock")
	var edge := Rect2(lock.position, Vector2(0.01, 0.01))
	k.box_rects("trim", Vector3(width - 0.2, 1.02, 0), Vector3(0.24, 0.24, 0.09), [edge, edge, edge, edge, lock, lock], Kit.grey(0.8), Color.WHITE)
	for y: float in [0.3, 1.5]:
		k.lathe("steel", Vector3(0.0, y - 0.07, 0), PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.035, 0.14)]), 6, Props.IRON, Props.IRON)

## Sparse furniture inside the yard. inner = the open rectangle inside the walls (metres).
func yard(k: Kit, flat: Kit, inner: Rect2, door: Rect2) -> void:
	var x0 := inner.position.x
	var z0 := inner.position.y
	var x1 := inner.end.x
	var z1 := inner.end.y
	# two cots along the west wall, the northern one under a scrap-iron shelter
	_cot(k, Vector3(x0 + 0.48, 0, z0 + 1.05), 0.0, 0)
	_cot(k, Vector3(x0 + 0.48, 0, z0 + 3.9), 0.0, 1)
	k.push_tint(Props.WOOD_GREY)
	for z: float in [z0 + 0.1, z0 + 2.15]:
		k.box("planks", Vector3(x0 + 1.25, 0.86, z), Vector3(0.09, 1.72, 0.09), Props.AO, Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110011)
	k.box("planks", Vector3(x0 + 1.25, 1.75, z0 + 1.12), Vector3(0.08, 0.1, 2.3), Kit.grey(0.7), Kit.grey(0.9), Vector2(0.2, 0.5), Kit.BEAM)
	k.pop_tint()
	_scrap_roof(k, x0 - 0.2, 2.02, x0 + 1.45, 1.74, z0 - 0.05, z0 + 2.3)
	# table and stool by the east wall, a slop bucket, a bench on the north wall
	_table(k, Vector3(x1 - 0.5, 0, z0 + 1.6), 0.0)
	k.push_tint(Props.WOOD_GREY)
	k.box("planks", Vector3(x1 - 1.2, 0.2, z0 + 1.75), Vector3(0.3, 0.4, 0.3), Props.AO, Kit.grey(0.95), Vector2(0.3, 0.3))
	k.pop_tint()
	props.bucket(k, Vector3(x1 - 0.3, 0, z1 - 0.4), Props.GALV)
	props.bench(k, Vector3(x0 + 3.6, 0, z0 + 0.24), 0.0, 1.6)
	# duckboards inside the gate and a worn patch where the prisoner paces
	props.duckboard(k, Vector3(door.get_center().x, 0, z1 - 0.95), PI * 0.5, 1.7, 0.75)
	flat.decal(Kit.DECAL["dirt"], inner.get_center().x + 0.2, inner.get_center().y - 0.4, Vector2(3.4, 3.0), 0.8, Color(0.82, 0.78, 0.7, 0.7))
	flat.decal(Kit.DECAL["oil"], x1 - 0.5, z1 - 0.5, Vector2(0.9, 0.9), 1.0, Color(0.5, 0.5, 0.45, 0.5))

func _cot(k: Kit, at: Vector3, yaw: float, variant: int) -> void:
	# iron bedstead 0.75 x 1.9 m lying along local Z
	k.push_at(at, yaw)
	var iron := Props.IRON * Kit.grey(1.1)
	for x: float in [-0.36, 0.36]:
		k.beam("steel", Vector3(x, 0.4, -0.93), Vector3(x, 0.4, 0.93), 0.03, 0.03, iron, iron, Vector2.ZERO, false)
		for z: float in [-0.93, 0.93]:
			k.box("steel", Vector3(x, 0.3 if z > 0.0 else 0.38, z), Vector3(0.03, 0.6 if z > 0.0 else 0.76, 0.03), iron * Kit.grey(0.6), iron)
	for z: float in [-0.93, 0.93]:
		k.beam("steel", Vector3(-0.36, 0.58 if z > 0.0 else 0.74, z), Vector3(0.36, 0.58 if z > 0.0 else 0.74, z), 0.025, 0.025, iron, iron, Vector2.ZERO, false)
	# thin mattress, grey blanket, a lumpy pillow
	k.box("canvas", Vector3(0, 0.45, 0), Vector3(0.7, 0.09, 1.82), Kit.grey(0.6), Color(0.95, 0.92, 0.82), Vector2(0.1, 0.2), Kit.AUTO, 0b110111)
	var br := Kit.trim_uv("blanket")
	var z_a := -0.2 if variant == 0 else -0.5
	k.quad_rect("trim", Vector3(-0.36, 0.5, 0.9), Vector3(0.36, 0.5, 0.9), Vector3(0.36, 0.5, z_a), Vector3(-0.36, 0.5, z_a), br, Kit.grey(0.9), Color.WHITE)
	k.quad_rect("trim", Vector3(-0.36, 0.42, 0.9), Vector3(-0.36, 0.42, z_a), Vector3(-0.36, 0.5, z_a), Vector3(-0.36, 0.5, 0.9), Rect2(br.position, Vector2(br.size.x, br.size.y * 0.15)), Kit.grey(0.6), Kit.grey(0.9))
	k.quad_rect("trim", Vector3(0.36, 0.42, z_a), Vector3(0.36, 0.42, 0.9), Vector3(0.36, 0.5, 0.9), Vector3(0.36, 0.5, z_a), Rect2(br.position, Vector2(br.size.x, br.size.y * 0.15)), Kit.grey(0.6), Kit.grey(0.9))
	props.sandbag(k, Vector3(0, 0.49, -0.68), PI * 0.5 + 0.1, 0.46, 0.3, 0.13, Color(0.95, 0.93, 0.9))
	k.pop()

func _table(k: Kit, at: Vector3, yaw: float) -> void:
	k.push_at(at, yaw)
	k.push_tint(Props.WOOD_GREY)
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.48, 0.48]:
			k.box("planks", Vector3(x, 0.36, z), Vector3(0.06, 0.72, 0.06), Props.AO, Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110011)
	k.box("planks", Vector3(0, 0.735, 0), Vector3(0.74, 0.04, 1.1), Kit.grey(0.6), Kit.grey(0.85), Vector2(0.4, 0.4), Kit.BEAM, 0b111011)
	k.pop_tint()
	var top_uv := Kit.trim_uv("tabletop")
	k.quad_rect("trim", Vector3(-0.37, 0.757, 0.55), Vector3(0.37, 0.757, 0.55), Vector3(0.37, 0.757, -0.55), Vector3(-0.37, 0.757, -0.55), top_uv)
	k.pop()

## A few lapped corrugated sheets on a rough frame: high edge at (xh, yh), low edge at (xl, yl), spanning z0..z1.
func _scrap_roof(k: Kit, xh: float, yh: float, xl: float, yl: float, z0: float, z1: float) -> void:
	var dx := xl - xh
	var length := sqrt(dx * dx + (yh - yl) * (yh - yl))
	var up := Vector3(-dx, yh - yl, 0) / length
	var right := Vector3(0, 0, -signf(dx))
	k.push(Transform3D(Basis(right, up, right.cross(up)), Vector3(xl, yl, z1 if dx > 0.0 else z0)))
	var width := z1 - z0
	var n := int(ceil(width / 0.64))
	for i: int in range(n):
		var xa := float(i) * 0.64
		var xb := minf(width, xa + 0.66)
		var g := rng.randf_range(0.8, 1.0)
		var col := Color(g, g * rng.randf_range(0.92, 1.0), g * rng.randf_range(0.84, 1.0))
		var d0 := -rng.randf() * 0.12
		var z := 0.012 * float(i % 2)
		var uo := 0.25 * float(rng.randi() % 4)
		k.quad("corrugated", Vector3(xa, d0, z), Vector3(xb, d0, z), Vector3(xb, length, z), Vector3(xa, length, z), Vector2(uo, 1.0), Vector2(uo + (xb - xa) * Kit.UV_M, 1.0), Vector2(uo + (xb - xa) * Kit.UV_M, 1.0 - (length - d0) * Kit.UV_M), Vector2(uo, 1.0 - (length - d0) * Kit.UV_M), col * Kit.grey(0.9), col)
		k.quad("corrugated", Vector3(xb, d0, z - 0.01), Vector3(xa, d0, z - 0.01), Vector3(xa, length, z - 0.01), Vector3(xb, length, z - 0.01), Vector2(uo, 1.0), Vector2(uo + 0.25, 1.0), Vector2(uo + 0.25, 0.4), Vector2(uo, 0.4), Kit.grey(0.3), Kit.grey(0.25))
	k.pop()

# ---------------------------------------------------------------------------------------------------------------
# Crate stacks, sandbag post, drums
# ---------------------------------------------------------------------------------------------------------------
## Supply dump filling a 2 x 2 m footprint centred on `at`. variant 0 / 1 give two different arrangements.
func crate_stack(k: Kit, flat: Kit, at: Vector3, variant: int) -> void:
	k.push_at(at, 0.0)
	var pale := Props.WOOD_PALE
	if variant == 0:
		props.pallet(k, Vector3(-0.42, 0, -0.45), 0.0, Vector2(1.14, 1.0))
		props.crate(k, Vector3(-0.42, 0.13, -0.45), Vector3(1.06, 0.82, 0.92), 0.03, 0, pale)
		props.crate(k, Vector3(0.56, 0, -0.52), Vector3(0.8, 0.7, 0.86), -0.05, 1, pale * Kit.grey(0.9))
		props.crate(k, Vector3(-0.3, 0, 0.52), Vector3(1.32, 0.5, 0.86), 0.02, 3, pale * Kit.grey(0.94))
		props.crate(k, Vector3(0.64, 0, 0.5), Vector3(0.62, 0.6, 0.72), 0.12, 4, pale * Kit.grey(0.86))
		props.crate(k, Vector3(-0.36, 0.95, -0.42), Vector3(0.78, 0.52, 0.7), 0.22, 1, pale * Kit.grey(0.95))
		props.crate(k, Vector3(-0.5, 0.5, 0.5), Vector3(0.7, 0.42, 0.6), -0.14, 0, pale)
		props.steel_box(k, Vector3(0.52, 0.7, -0.5), Vector3(0.46, 0.2, 0.22), 0.4, Props.DRAB)
		props.steel_box(k, Vector3(0.66, 0.6, 0.48), Vector3(0.44, 0.2, 0.2), -0.2, Props.DRAB_DARK)
		props.tarp(k, Vector3(-0.36, 1.47, -0.42), Vector2(0.74, 0.66), 0.7, Color(0.9, 0.9, 0.84), [0.3, 0.3, 0.3, 0.3], 3)
		_lashing(k, Vector3(-0.42, 0.13, -0.45), Vector3(1.08, 0.83, 0.94))
		props.jerrycan(k, Vector3(0.3, 0.5, 0.75), 0.3, Props.DRAB, true)
	else:
		props.crate(k, Vector3(-0.48, 0, -0.5), Vector3(0.92, 0.9, 0.9), 0.02, 1, pale * Kit.grey(0.92))
		props.crate(k, Vector3(-0.5, 0, 0.47), Vector3(0.9, 0.62, 0.92), -0.04, 0, pale)
		props.crate(k, Vector3(0.12, 0.0, 0.0), Vector3(0.36, 0.34, 0.6), 0.5, 5, pale * Kit.grey(0.8))
		props.crate(k, Vector3(-0.5, 0.62, 0.46), Vector3(0.8, 0.5, 0.66), 0.1, 3, pale * Kit.grey(0.88))
		props.crate(k, Vector3(-0.46, 0.9, -0.5), Vector3(0.62, 0.4, 0.56), -0.3, 0, pale * Kit.grey(0.96))
		# fuel drums on the east half: three standing on a pallet, one lying on chocks
		props.pallet(k, Vector3(0.52, 0, -0.42), PI * 0.5, Vector2(1.12, 0.92))
		props.barrel(k, Vector3(0.33, 0.13, -0.7), Props.DRAB * props.tone(0.2), 0.3)
		props.barrel(k, Vector3(0.7, 0.13, -0.3), Color(0.55, 0.43, 0.35) * props.tone(0.2), 1.3)
		props.barrel(k, Vector3(0.2, 0.13, -0.2), Props.DRAB_DARK * props.tone(0.2), 2.2)
		props.barrel(k, Vector3(0.6, 0.0, 0.14), Color(0.5, 0.56, 0.6) * props.tone(0.15), 0.06, true)
		for x: float in [0.33, 0.87]:
			k.box("planks", Vector3(x, 0.04, 0.58), Vector3(0.1, 0.08, 0.5), Props.AO, Props.WOOD_GREY, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
		props.tarp(k, Vector3(-0.5, 1.13, 0.46), Vector2(0.72, 0.6), 0.55, Color(0.84, 0.86, 0.8), [0.3, 0.1, 0.1, 0.3], 5)
		props.rope_coil(k, Vector3(-0.46, 1.3, -0.5), 0.17, 3)
	k.pop()
	flat.decal(Kit.DECAL["blob"], at.x, at.z, Vector2(3.5, 3.5), 0.0, Color(0.06, 0.05, 0.03, 0.62))

func _lashing(k: Kit, base: Vector3, size: Vector3) -> void:
	# two rope turns round a crate
	var col := Color(0.82, 0.76, 0.62)
	for dx: float in [-0.28, 0.24]:
		var x := base.x + dx * size.x
		var hz := size.z * 0.5 + 0.012
		var y0 := base.y
		var y1 := base.y + size.y + 0.012
		k.tube("burlap", PackedVector3Array([Vector3(x, y0, base.z + hz), Vector3(x, y1, base.z + hz), Vector3(x, y1, base.z - hz), Vector3(x, y0, base.z - hz)]), 0.014, 4, col, Vector2.ZERO, 0.25, 6.0)

## Roofed sandbag sentry post filling a 2 x 2 m footprint. The firing slit faces local -X.
func sandbag_post(k: Kit, flat: Kit, at: Vector3, yaw: float = 0.0) -> void:
	k.push_at(at, yaw)
	var e := 0.8
	# three walls five courses high, an extra layer across the front, two courses flanking the entrance
	props.sandbag_wall(k, Vector3(-e, 0, -0.98), Vector3(-e, 0, 0.98), 5, 0.62)
	props.sandbag_wall(k, Vector3(-e + 0.2, 0, -e), Vector3(0.98, 0, -e), 5, 0.6)
	props.sandbag_wall(k, Vector3(-e + 0.2, 0, e), Vector3(0.98, 0, e), 5, 0.6)
	props.sandbag_wall(k, Vector3(e, 0, -0.62), Vector3(e, 0, -0.1), 2, 0.52)
	# floor boards, an ammunition box and a field telephone crate inside
	props.duckboard(k, Vector3(0.05, 0, 0.0), 0.0, 1.2, 1.2)
	props.steel_box(k, Vector3(-0.2, 0.04, 0.35), Vector3(0.46, 0.22, 0.22), 0.2, Props.DRAB)
	props.crate(k, Vector3(0.1, 0.04, -0.3), Vector3(0.5, 0.36, 0.4), -0.2, 5, Props.WOOD_PALE * Kit.grey(0.85))
	# timber frame and a low corrugated cover over the front two thirds, weighted with bags
	k.push_tint(Props.WOOD_GREY * Kit.grey(0.85))
	for x: float in [-0.52, 0.5]:
		for z: float in [-0.52, 0.52]:
			k.box("planks", Vector3(x, 0.72, z), Vector3(0.09, 1.44, 0.09), Props.AO, Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110011)
	for z: float in [-0.52, 0.52]:
		k.beam("planks", Vector3(-0.98, 1.4, z), Vector3(0.6, 1.5, z), 0.08, 0.09, Kit.grey(0.7), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()))
	k.pop_tint()
	_scrap_roof(k, 0.62, 1.58, -1.0, 1.46, -0.98, 0.98)
	var slope := (1.58 - 1.46) / 1.62
	for p: Vector2 in [Vector2(-0.62, -0.5), Vector2(-0.5, 0.45), Vector2(0.25, -0.05)]:
		var g := rng.randf_range(0.8, 1.0)
		props.sandbag(k, Vector3(p.x, 1.47 + (p.x + 1.0) * slope + 0.012, p.y), rng.randf() * PI, 0.6, 0.34, 0.15, Color(g * 0.9, g * 0.88, g * 0.82))
	k.pop()
	flat.decal(Kit.DECAL["blob"], at.x, at.z, Vector2(3.6, 3.6), 0.0, Color(0.06, 0.05, 0.03, 0.6))
	flat.decal(Kit.DECAL["dirt"], at.x + cos(yaw) * 1.3, at.z - sin(yaw) * 1.3, Vector2(1.8, 1.8), 0.5, Color(0.8, 0.76, 0.68, 0.7))

## Loose group of fuel drums hugging a wall. `along` is the unit direction the row runs in.
func drum_row(k: Kit, flat: Kit, at: Vector3, along: Vector3, layout: int) -> void:
	var tints: Array[Color] = [Props.DRAB, Color(0.55, 0.43, 0.35), Props.DRAB_DARK, Color(0.5, 0.56, 0.6)]
	var side := Vector3(-along.z, 0, along.x)
	if layout == 0:
		props.barrel(k, at, tints[0] * props.tone(0.2), 0.4)
		props.barrel(k, at + along * 0.62, tints[1] * props.tone(0.2), 1.9)
		props.barrel(k, at + along * 1.24 + side * 0.03, tints[2] * props.tone(0.2), 3.0)
	else:
		props.pallet(k, at + along * 0.3, atan2(-along.z, along.x), Vector2(1.2, 0.64))
		props.barrel(k, at + Vector3(0, 0.13, 0), tints[2] * props.tone(0.2), 0.7)
		props.barrel(k, at + along * 0.61 + Vector3(0, 0.13, 0), tints[0] * props.tone(0.2), 2.6)
		props.barrel(k, at + along * 1.5, tints[3] * props.tone(0.15), atan2(-along.z, along.x) + PI * 0.5, true)
		k.box("planks", at + along * 1.5 + side * 0.24 + Vector3(0, 0.035, 0), Vector3(0.12, 0.07, 0.12), Props.AO, Props.WOOD_GREY)
	var c := at + along * 0.8
	flat.decal(Kit.DECAL["blob"], c.x, c.z, Vector2(2.9, 1.7) if absf(along.x) > 0.5 else Vector2(1.7, 2.9), 0.0, Color(0.06, 0.05, 0.03, 0.5))
	flat.decal(Kit.DECAL["oil"], c.x + side.x * 0.1, c.z + side.z * 0.1, Vector2(1.3, 1.1), rng.randf() * TAU, Color(0.7, 0.7, 0.66, 0.6))

# ---------------------------------------------------------------------------------------------------------------
# Perimeter fence and utility poles
# ---------------------------------------------------------------------------------------------------------------
## Stock fence along Z = z from x0 to x1: timber posts, strained end and mid posts, woven wire below, barbed on top.
## The wire of span `skip` is left out (the caller builds it as its own node, see structures_rules.gd); its
## posts are returned as [foot a, top a, foot b, top b, Vector3(texture u offset, 0, 0)].
func fence(k: Kit, wire: Kit, x0: float, x1: float, z: float, spans: int, skip: int = -1) -> Array[Vector3]:
	var left_out: Array[Vector3] = []
	var step := (x1 - x0) / float(spans)
	var tops: Array[Vector3] = []
	for i: int in range(spans + 1):
		var x := x0 + step * float(i)
		var strain := i == 0 or i == spans or i % 4 == 0
		var lean_x := props.jitter(0.035)
		var lean_z := props.jitter(0.05)
		var hgt := 1.42 + props.jitter(0.05) + (0.12 if strain else 0.0)
		var w := 0.13 if strain else 0.09
		var g := rng.randf_range(0.62, 0.86)
		var col := Color(g, g * 0.96, g * 0.9)
		var foot := Vector3(x, -0.1, z)
		var head := Vector3(x + lean_x, hgt, z + lean_z)
		k.beam("planks", foot, head, w, w, col * Kit.grey(0.6), col, Vector2(rng.randf(), rng.randf()), true, Vector3.BACK)
		tops.append(head)
		if strain:
			for s: float in [-1.0, 1.0]:
				if (i == 0 and s < 0.0) or (i == spans and s > 0.0):
					continue
				k.beam("planks", Vector3(x + s * 0.95, 0.0, z), Vector3(x + s * 0.05, 1.0, z), 0.07, 0.07, col * Kit.grey(0.6), col, Vector2(rng.randf(), rng.randf()))
		elif rng.randf() < 0.22:
			var pr := Kit.trim_uv("plate_warn" if rng.randf() < 0.6 else "plate_blank")
			k.quad_rect("trim", Vector3(x - 0.17, 0.92, z + 0.055), Vector3(x + 0.17, 0.92, z + 0.055), Vector3(x + 0.17, 1.16, z + 0.055), Vector3(x - 0.17, 1.16, z + 0.055), pr, Kit.grey(0.9), Color.WHITE)
	var mesh_v := Kit.WIRE_MESH
	var barb_v := Kit.WIRE_BARB
	for i: int in range(spans):
		var a := tops[i]
		var b := tops[i + 1]
		var fa := Vector3(x0 + step * float(i), 0.03, z)
		var fb := Vector3(x0 + step * float(i + 1), 0.03, z)
		var ma := fa.lerp(a, 0.63)
		var mb := fb.lerp(b, 0.63)
		var u0 := float(i) * step * Kit.UV_M
		var u1 := float(i + 1) * step * Kit.UV_M
		if i == skip:
			left_out = [fa, a, fb, b, Vector3(u0, 0, 0)]
			rng.randf()
			rng.randf()
			continue
		wire.quad4("wire", fa, fb, mb, ma, Vector2(u0, mesh_v.y), Vector2(u1, mesh_v.y), Vector2(u1, mesh_v.x), Vector2(u0, mesh_v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
		for t: float in [0.78, 0.93]:
			var pa := fa.lerp(a, t)
			var pb := fb.lerp(b, t)
			props.wire(wire, pa, pb, 0.035 + rng.randf() * 0.03, 0.008, Color(0.3, 0.28, 0.27), 4)
			# barbs: an upright and a flat cut-out strip so they show from every camera yaw
			var up := Vector3(0, 0.05, 0)
			var out := Vector3(0, 0, 0.05)
			var drop := Vector3(0, 0.02, 0)
			wire.quad4("wire", pa - up - drop, pb - up - drop, pb + up - drop, pa + up - drop, Vector2(u0 * 2.0, barb_v.y), Vector2(u1 * 2.0, barb_v.y), Vector2(u1 * 2.0, barb_v.x), Vector2(u0 * 2.0, barb_v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
			wire.quad4("wire", pa + out - drop, pb + out - drop, pb - out - drop, pa - out - drop, Vector2(u0 * 2.0, barb_v.y), Vector2(u1 * 2.0, barb_v.y), Vector2(u1 * 2.0, barb_v.x), Vector2(u0 * 2.0, barb_v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
	return left_out

## Telegraph line outside the northern map edge, with a spur to `drop_to` (the tower) and the aerial wire to `aerial`.
func pole_line(k: Kit, wire: Kit, z: float, xs: Array, aerial: Vector3, drop_to: Vector3) -> void:
	var prev: Array[Vector3] = []
	var nearest_aerial: Vector3 = Vector3.ZERO
	var nearest_drop: Vector3 = Vector3.ZERO
	var best_a := 1e9
	var best_d := 1e9
	for x: float in xs:
		var pts := props.utility_pole(k, Vector3(x, 0, z + props.jitter(0.15)), PI * 0.5 + props.jitter(0.05), 6.4 + props.jitter(0.25), 1, props.jitter(0.035))
		if not prev.is_empty():
			for i: int in range(mini(prev.size(), pts.size())):
				props.wire(wire, prev[i], pts[i], 0.55 + rng.randf() * 0.15, 0.011, Color(0.17, 0.17, 0.17), 10)
		prev = pts
		for p: Vector3 in pts:
			if p.distance_to(aerial) < best_a:
				best_a = p.distance_to(aerial)
				nearest_aerial = p
			if p.distance_to(drop_to) < best_d:
				best_d = p.distance_to(drop_to)
				nearest_drop = p
	if best_a < 1e8:
		props.wire(wire, aerial, nearest_aerial, 0.35, 0.01, Color(0.2, 0.19, 0.18), 10)
	if best_d < 1e8:
		props.wire(wire, drop_to, nearest_drop, 0.4, 0.01, Color(0.17, 0.17, 0.17), 10)

# ---------------------------------------------------------------------------------------------------------------
# Watchtower
# ---------------------------------------------------------------------------------------------------------------
## Open observation platform on battered legs. The legs stand on a 2 x 2 m footprint (the rules' movement barrier),
## the deck boards lie at DECK_TOP (the tower sentry's `elevation` in the mission data) and there is no roof:
## the man on it has to be seen from every camera yaw. Returns the top of the wire mast (for the telegraph spur).
const DECK_TOP := 2.6

func watchtower(k: Kit, flat: Kit, at: Vector3) -> Vector3:
	k.push_at(at, 0.0)
	var deck := DECK_TOP - 0.04
	var base := 1.0
	var topw := 0.74
	var wood := Props.WOOD_GREY * Kit.grey(0.82)
	k.push_tint(wood)
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	# battered legs carried up as the corner posts of the parapet; the north-west one runs on up as a wire mast
	var mast_top := deck + 2.7
	for c: Vector2 in corners:
		k.beam("planks", Vector3(c.x * base, -0.1, c.y * base), Vector3(c.x * topw, deck, c.y * topw), 0.15, 0.15, Kit.grey(0.55), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()), true, Vector3(c.x, 0, 0))
		var post_h := 1.12
		if c.x < 0.0 and c.y < 0.0:
			post_h = mast_top - deck
		k.box("planks", Vector3(c.x * (topw + 0.1), deck + post_h * 0.5, c.y * (topw + 0.1)), Vector3(0.1, post_h, 0.1), Kit.grey(0.8), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110111)
	# girts and cross bracing on all four sides, two tiers
	var tier_h := (deck - 0.2) * 0.5
	for i: int in range(4):
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		for tier: int in range(2):
			var y0 := 0.15 + float(tier) * tier_h
			var y1 := y0 + tier_h - 0.05
			var w0 := lerpf(base, topw, y0 / deck)
			var w1 := lerpf(base, topw, y1 / deck)
			var out := Vector3(a.x + b.x, 0, a.y + b.y) * 0.04
			k.beam("planks", Vector3(a.x * w1, y1, a.y * w1) + out, Vector3(b.x * w1, y1, b.y * w1) + out, 0.05, 0.11, Kit.grey(0.7), Kit.grey(0.92), Vector2(rng.randf(), rng.randf()))
			# leave the lower tier of the ladder side (+Z) open on one diagonal only
			k.beam("planks", Vector3(a.x * w0, y0, a.y * w0) + out, Vector3(b.x * w1, y1, b.y * w1) + out, 0.04, 0.09, Kit.grey(0.65), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()))
			if not (i == 2 and tier == 0):
				k.beam("planks", Vector3(b.x * w0, y0, b.y * w0) + out * 1.9, Vector3(a.x * w1, y1, a.y * w1) + out * 1.9, 0.04, 0.09, Kit.grey(0.65), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()))
	# platform: joists, deck boards with a ladder hatch
	var half := 1.05
	for z: float in [-0.8, 0.0, 0.8]:
		k.box("planks", Vector3(0, deck - 0.06, z), Vector3(half * 2.0, 0.12, 0.08), Kit.grey(0.55), Kit.grey(0.8), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	var boards := 12
	for i: int in range(boards):
		var x := -half + (float(i) + 0.5) * half * 2.0 / float(boards)
		var g := rng.randf_range(0.82, 1.0)
		var hatch := i >= 4 and i <= 7
		var z0 := -half
		var z1 := half - (0.62 if hatch else 0.0)
		k.box("planks", Vector3(x, deck + 0.02, (z0 + z1) * 0.5), Vector3(half * 2.0 / float(boards) - 0.012, 0.04, z1 - z0), Kit.grey(0.6 * g), Kit.grey(g), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	# boarded parapet (open above the ladder), top rail
	for i: int in range(4):
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var pa := Vector3(a.x * half, deck + 0.04, a.y * half)
		var pb := Vector3(b.x * half, deck + 0.04, b.y * half)
		var up := Vector3(0, 0.95, 0)
		k.beam("planks", pa + up, pb + up, 0.09, 0.05, Kit.grey(0.75), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()))
		var n := 9
		for j: int in range(n):
			if i == 2 and j >= 3 and j <= 5:
				continue
			var t0 := float(j) / float(n)
			var t1 := float(j + 1) / float(n)
			var g := rng.randf_range(0.78, 1.0)
			var q0 := pa.lerp(pb, t0 + 0.006)
			var q1 := pa.lerp(pb, t1 - 0.006)
			var hh := Vector3(0, 0.82 + rng.randf() * 0.04, 0)
			var uv := Vector2(rng.randf(), floorf(rng.randf() * 16.0) * Kit.PLANK_ROW + Kit.PLANK_ROW * 0.1)
			var w := Kit.PLANK_ROW * 0.8
			# vertical boards, both faces
			k.quad4("planks", q1, q0, q0 + hh, q1 + hh, uv + Vector2(0, w), uv, uv + Vector2(0.32, 0), uv + Vector2(0.32, w), Kit.grey(0.6 * g), Kit.grey(0.6 * g), Kit.grey(g), Kit.grey(g))
			k.quad4("planks", q0, q1, q1 + hh, q0 + hh, uv, uv + Vector2(0, w), uv + Vector2(0.32, w), uv + Vector2(0.32, 0), Kit.grey(0.5 * g), Kit.grey(0.5 * g), Kit.grey(0.8 * g), Kit.grey(0.8 * g))
	k.pop_tint()
	# ladder up the south side through the hatch, steep enough to stay inside the legs' footprint
	props.ladder(k, Vector3(0, 0, base + 0.1), Vector3(0, deck + 0.9, half - 0.42), 0.46, wood)
	# wire mast: crossarm, insulators, a stay back to the opposite post
	var mast := Vector3(-(topw + 0.1), mast_top, -(topw + 0.1))
	k.push_tint(wood)
	k.box("planks", mast + Vector3(0, -0.2, 0), Vector3(0.7, 0.07, 0.07), Kit.grey(0.7), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	for dx: float in [-0.28, 0.28]:
		k.lathe("steel", mast + Vector3(dx, -0.165, 0), PackedVector2Array([Vector2(0.012, 0.0), Vector2(0.012, 0.04), Vector2(0.035, 0.05), Vector2(0.04, 0.09), Vector2(0.018, 0.12)]), 6, Color(0.92, 0.9, 0.84), Color(0.98, 0.97, 0.92))
	k.tube("steel", PackedVector3Array([mast + Vector3(0, -0.5, 0), Vector3(topw + 0.1, deck + 1.1, topw + 0.1)]), 0.008, 3, Color(0.25, 0.25, 0.25))
	# searchlight on the south-east corner, a few sandbags on the parapet
	_searchlight(k, Vector3(half - 0.28, deck + 0.04, half - 0.28), -1.97)
	for p: Vector3 in [Vector3(half - 0.02, deck + 1.0, -0.4), Vector3(half - 0.02, deck + 1.0, 0.28), Vector3(-0.3, deck + 1.0, -half + 0.02)]:
		var g := rng.randf_range(0.82, 1.0)
		props.sandbag(k, p, (PI * 0.5 if absf(p.x) > 0.9 else 0.0) + props.jitter(0.1), 0.6, 0.32, 0.18, Color(g, g * 0.97, g * 0.9))
	var hook: Vector3 = k.xf * (mast + Vector3(0.28, -0.05, 0))
	k.pop()
	flat.decal(Kit.DECAL["blob"], at.x, at.z, Vector2(3.6, 3.6), 0.0, Color(0.06, 0.05, 0.03, 0.42))
	flat.decal(Kit.DECAL["dirt"], at.x, at.z + 1.5, Vector2(1.6, 1.3), 1.2, Color(0.8, 0.76, 0.68, 0.7))
	return hook

func _searchlight(k: Kit, at: Vector3, yaw: float) -> void:
	k.push_at(at, yaw)
	var paint := Props.DRAB_DARK
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.05, 0.04), Vector2(0.035, 0.95)]), 6, paint * Kit.grey(0.6), paint)
	# yoke
	for z: float in [-0.25, 0.25]:
		k.box("steel", Vector3(0, 1.17, z), Vector3(0.05, 0.46, 0.02), paint * Kit.grey(0.8), paint)
	k.box("steel", Vector3(0, 0.95, 0), Vector3(0.05, 0.03, 0.52), paint, paint)
	# drum tilted a little downward, lens facing local +X
	k.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5 - 0.22), Vector3(0, 1.25, 0)))
	k.lathe("steel", Vector3(0, -0.17, 0), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.22, 0.05), Vector2(0.23, 0.3), Vector2(0.245, 0.31), Vector2(0.245, 0.35), Vector2(0.22, 0.35), Vector2(0.21, 0.33)]), 12, paint * Kit.grey(0.75), paint, Vector2(rng.randf(), rng.randf()))
	k.disc("trim", Vector3(0, 0.16, 0), 0.21, 12, Kit.trim_uv("lens"), Kit.grey(0.9))
	k.disc("steel", Vector3(0, -0.17, 0), 0.13, 12, Rect2(0.3, 0.3, 0.05, 0.05), paint * Kit.grey(0.7), true)
	k.pop()
	k.pop()

# ---------------------------------------------------------------------------------------------------------------
# Landing stage and boat
# ---------------------------------------------------------------------------------------------------------------
## Timber landing stage from x0 (water end) to x1, centred on z, `width` wide. The deck sits at walking height.
func dock(k: Kit, flat: Kit, x0: float, x1: float, z: float, width: float) -> Vector3:
	var top := 0.055
	var hw := width * 0.5
	var wet := Color(0.36, 0.33, 0.29)
	var dry := Props.WOOD_GREY * Kit.grey(0.8)
	# piles: tall mooring posts at the water end
	var bollard := Vector3.ZERO
	for i: int in range(3):
		var x := lerpf(x0 + 0.07, x1 - 0.07, float(i) / 2.0)
		for s: float in [-1.0, 1.0]:
			var tall := 0.78 if i == 0 else (0.3 if i == 1 else 0.42)
			var r := 0.085 if i == 0 else 0.07
			k.lathe("planks", Vector3(x + props.jitter(0.02), 0, z + s * (hw + 0.02)), PackedVector2Array([Vector2(r, -1.0), Vector2(r, -0.1), Vector2(r * 0.95, tall), Vector2(r * 0.7, tall + 0.03), Vector2(0.0, tall + 0.035)]), 7, wet, dry, Vector2(rng.randf(), 0.0),
				PackedFloat32Array([1.0, 1.0, 1.0, 1.05, 1.1]), -1.0, true)
			if i == 0 and s < 0.0:
				bollard = Vector3(x, tall - 0.2, z + s * (hw + 0.02))
	# stringers and deck boards laid across
	k.push_tint(dry)
	for s: float in [-1.0, 1.0]:
		k.box("planks", Vector3((x0 + x1) * 0.5, top - 0.085, z + s * (hw - 0.12)), Vector3(x1 - x0, 0.11, 0.1), Kit.grey(0.5), Kit.grey(0.75), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	var n := int(round((x1 - x0) / 0.165))
	var bw := (x1 - x0) / float(n)
	for i: int in range(n):
		var x := x0 + (float(i) + 0.5) * bw
		var g := rng.randf_range(0.74, 1.0)
		var col := Color(g, g * rng.randf_range(0.95, 1.0), g * rng.randf_range(0.9, 1.0))
		var zj := props.jitter(0.03)
		var lj := props.jitter(0.04)
		k.push(Transform3D(Basis(Vector3.UP, props.jitter(0.012)), Vector3(x, top - 0.016, z + zj)))
		k.box("planks", Vector3.ZERO, Vector3(bw - 0.014, 0.032, width + 0.08 + lj), col * Kit.grey(0.55), col, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
		k.pop()
	# kerb rails along both edges
	for s: float in [-1.0, 1.0]:
		k.box("planks", Vector3((x0 + x1) * 0.5 - 0.1, top + 0.035, z + s * (hw - 0.03)), Vector3(x1 - x0 - 0.5, 0.07, 0.08), Kit.grey(0.7), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	# old tyres as fenders on the water end, a coil of rope and a lifebelt-free, purely practical bollard hitch
	for s: float in [-0.3, 0.32]:
		props.tyre(k, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x0 - 0.02, -0.1, z + s)), 0.24, 0.085)
	props.rope_coil(k, Vector3(x0 + 0.33, top, z + hw - 0.3), 0.15, 3)
	flat.decal(Kit.DECAL["dirt"], x1 + 0.9, z, Vector2(2.4, 2.0), 0.4, Color(0.8, 0.76, 0.68, 0.7))
	return bollard

## Clinker-built pulling boat floating at `at` (y = waterline), bow toward local -Z. Returns the bow ring position.
func boat(k: Kit, at: Vector3, yaw: float, roll: float = 0.03) -> Vector3:
	k.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll), at))
	var stations := 10
	var strakes := 5
	var length := 3.7
	var paint := Color(0.4, 0.46, 0.45)
	var inside := Props.WOOD_GREY * Kit.grey(0.9)
	# section points: sec[i][j], j = 0 keel .. strakes = gunwale (starboard side, +X); port mirrors
	var sec: Array = []
	var floor_y := 0.0                 # sole boards: kept above the waterline so the sea never shows inside the hull
	var floor_half := PackedFloat32Array()
	for i: int in range(stations):
		var t := float(i) / float(stations - 1)           # 0 stern .. 1 bow
		var z := (0.5 - t) * length
		var breadth := 0.68 * pow(sin(PI * clampf(0.16 + t * 0.84, 0.0, 1.0)), 0.62)
		if t > 0.97:
			breadth = 0.02
		var sheer := 0.36 + 0.16 * pow(t, 2.2) + 0.05 * pow(1.0 - t, 2.0)
		var keel := -0.17 + 0.2 * pow(maxf(0.0, t - 0.75) / 0.25, 2.0) + 0.05 * pow(maxf(0.0, 0.2 - t) / 0.2, 2.0)
		var row: Array[Vector3] = []
		for j: int in range(strakes + 1):
			var s := float(j) / float(strakes)
			row.append(Vector3(breadth * pow(s, 0.55), lerpf(keel, sheer, pow(s, 1.7)), z - (0.12 * s * s if t > 0.9 else 0.0)))
		sec.append(row)
		var sf := pow(clampf((floor_y - keel) / (sheer - keel), 0.0, 1.0), 1.0 / 1.7)
		floor_half.append(breadth * pow(sf, 0.55) if keel < floor_y else 0.0)
	# strakes: each a strip with its own shading (dark under the lap above), lower edge stepped outward
	for side: float in [1.0, -1.0]:
		for j: int in range(strakes):
			var pts := PackedVector3Array()
			var uvs := PackedVector2Array()
			var cols_out := PackedColorArray()
			var cols_in := PackedColorArray()
			var row_v := float((j * 3 + (0 if side > 0.0 else 7)) % 16) * Kit.PLANK_ROW
			for e: int in range(2):
				for i: int in range(stations):
					var p: Vector3 = sec[i][j + e]
					var lap := 0.012 if e == 0 and j > 0 else 0.0
					pts.append(Vector3(side * (p.x + lap), p.y - lap * 0.5, p.z))
					uvs.append(Vector2(float(i) * 0.16 + float(j) * 0.37, row_v + Kit.PLANK_ROW * (0.9 - 0.8 * float(e))))
					var wet := 0.62 if p.y < 0.06 else 1.0
					cols_out.append(paint * Kit.grey((1.0 if e == 0 else 0.62) * wet))
					cols_in.append(inside * Kit.grey((0.66 + 0.07 * float(j)) * (1.0 if e == 1 else 0.82)))
			k.patch("planks", 2, stations, pts, uvs, cols_out, false, side < 0.0)
			k.patch("planks", 2, stations, pts, uvs, cols_in, false, side > 0.0)
	# transom
	var stern: Array[Vector3] = sec[0]
	for j: int in range(strakes):
		var a := stern[j]
		var b := stern[j + 1]
		var uva := Vector2(0.3, 0.2 + float(j) * 0.02)
		for face: float in [1.0, -1.0]:
			var col := paint * Kit.grey(0.8) if face > 0.0 else inside * Kit.grey(0.7)
			var z := a.z + 0.001 * face
			if face < 0.0:
				k.quad4("planks", Vector3(a.x, a.y, z), Vector3(-a.x, a.y, z), Vector3(-b.x, b.y, z), Vector3(b.x, b.y, z), uva, uva + Vector2(0.2, 0), uva + Vector2(0.2, -0.04), uva + Vector2(0, -0.04), col, col, col, col)
			else:
				k.quad4("planks", Vector3(-a.x, a.y, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(-b.x, b.y, z), uva, uva + Vector2(0.2, 0), uva + Vector2(0.2, -0.04), uva + Vector2(0, -0.04), col, col, col, col)
	# gunwales, stem post, ribs
	k.push_tint(Props.WOOD_GREY)
	for side: float in [1.0, -1.0]:
		var rail := PackedVector3Array()
		for i: int in range(stations):
			var p: Vector3 = sec[i][strakes]
			rail.append(Vector3(side * (p.x + 0.005), p.y + 0.012, p.z))
		k.tube("planks", rail, 0.03, 5, Kit.grey(0.95), Vector2(rng.randf(), 0.5))
		for i: int in range(1, stations - 2):
			var rib := PackedVector3Array()
			for j: int in range(1, strakes + 1):
				var p: Vector3 = sec[i][j]
				rib.append(Vector3(side * (p.x - 0.018), p.y + 0.008, p.z + 0.2))
			k.tube("planks", rib, 0.015, 3, Kit.grey(0.6), Vector2(rng.randf(), 0.2))
	var bow: Vector3 = sec[stations - 1][strakes]
	k.beam("planks", Vector3(0, -0.02, bow.z + 0.34), Vector3(0, bow.y + 0.1, bow.z - 0.05), 0.05, 0.07, Kit.grey(0.6), Kit.grey(0.95), Vector2(0.2, 0.2))
	# thwarts, stern sheets, bottom boards
	for t: float in [0.3, 0.52, 0.72]:
		var idx := t * float(stations - 1)
		var i0 := int(floor(idx))
		var p: Vector3 = (sec[i0][strakes] as Vector3).lerp(sec[i0 + 1][strakes], idx - float(i0))
		k.box("planks", Vector3(0, p.y - 0.13, p.z), Vector3(p.x * 2.0 - 0.06, 0.035, 0.22), Kit.grey(0.6), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	var st: Vector3 = sec[1][strakes]
	k.box("planks", Vector3(0, st.y - 0.14, (sec[0][0] as Vector3).z - 0.24), Vector3(st.x * 1.8, 0.03, 0.4), Kit.grey(0.6), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	# sole (floor) following the hull, five boards wide
	for i: int in range(stations - 1):
		var za: float = (sec[i][0] as Vector3).z
		var zb: float = (sec[i + 1][0] as Vector3).z
		var wa := floor_half[i]
		var wb := floor_half[i + 1]
		if wa <= 0.0 and wb <= 0.0:
			continue
		for b: int in range(5):
			var f0 := -1.0 + 0.4 * float(b)
			var f1 := f0 + 0.4
			var g := 0.62 + 0.07 * float((b * 3 + 1) % 4)
			var row_v := float((b * 5 + 2) % 16) * Kit.PLANK_ROW + Kit.PLANK_ROW * 0.1
			k.quad4("planks", Vector3(wa * f0, floor_y, za), Vector3(wa * f1, floor_y, za), Vector3(wb * f1, floor_y, zb), Vector3(wb * f0, floor_y, zb),
				Vector2(float(i) * 0.16, row_v + Kit.PLANK_ROW * 0.8), Vector2(float(i) * 0.16, row_v), Vector2(float(i + 1) * 0.16, row_v), Vector2(float(i + 1) * 0.16, row_v + Kit.PLANK_ROW * 0.8),
				Kit.grey(g), Kit.grey(g), Kit.grey(g), Kit.grey(g))
	# oars shipped along the thwarts
	for side: float in [1.0, -1.0]:
		var a := Vector3(side * 0.2, 0.3, 1.1)
		var b := Vector3(side * 0.33, 0.33, -1.25)
		k.tube("planks", PackedVector3Array([a, b]), 0.022, 5, Kit.grey(0.95), Vector2(rng.randf(), 0.3))
		k.beam("planks", b, b + (b - a).normalized() * 0.62, 0.13, 0.016, Kit.grey(0.85), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()))
	k.pop_tint()
	# a baler left on the stern sheets
	props.bucket(k, Vector3(0.22, floor_y, 0.9), Props.GALV, 0.1, 0.18)
	var ring: Vector3 = k.xf * Vector3(0, bow.y + 0.05, bow.z - 0.02)
	k.pop()
	return ring
