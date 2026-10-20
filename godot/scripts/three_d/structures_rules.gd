extends RefCounted
## Props whose look follows the rules: the cuttable span of the wire (whole / cut), the generator behind the radio
## post (running / sabotaged), the tripwire (armed / sprung), the barracks door leaf and the alarm horn.
## structures.gd builds each state into its own node and switches between them from the simulation.
const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Props = preload("res://scripts/three_d/structures_props.gd")

var props: Props
var rng := RandomNumberGenerator.new()

const WIRE_COL := Color(0.75, 0.72, 0.68)
const STRAND := Color(0.3, 0.28, 0.27)
## Tripwire: distance between the pegs (the rules trip a guard within 18 units = 0.56 m of its middle).
const TRIP_SPAN := 1.0

func _init(p: Props, seed_value: int) -> void:
	props = p
	rng.seed = seed_value

# ---------------------------------------------------------------------------------------------------------------
# Cuttable fence span (world space). fa / fb: feet of the two posts, a / b: their tops. u0: texture offset.
# ---------------------------------------------------------------------------------------------------------------
## The span before it is cut: the same wire as its neighbours, hanging a little slacker.
func span_whole(wire: Kit, fa: Vector3, a: Vector3, fb: Vector3, b: Vector3, u0: float) -> void:
	var length := fa.distance_to(fb)
	var u1 := u0 + length * Kit.UV_M
	var um := (u0 + u1) * 0.5
	var v := Kit.WIRE_MESH
	var ma := fa.lerp(a, 0.63)
	var mb := fb.lerp(b, 0.63)
	# woven wire in two panels, its top edge dipping in the middle
	var fm := fa.lerp(fb, 0.5)
	var mm := ma.lerp(mb, 0.5) + Vector3(0, -0.06, 0.03)
	wire.quad4("wire", fa, fm, mm, ma, Vector2(u0, v.y), Vector2(um, v.y), Vector2(um, v.x), Vector2(u0, v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
	wire.quad4("wire", fm, fb, mb, mm, Vector2(um, v.y), Vector2(u1, v.y), Vector2(u1, v.x), Vector2(um, v.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
	var barb := Kit.WIRE_BARB
	for t: float in [0.78, 0.93]:
		var pa := fa.lerp(a, t)
		var pb := fb.lerp(b, t)
		var sag := 0.09 + 0.03 * (t - 0.78) / 0.15
		props.wire(wire, pa, pb, sag, 0.008, STRAND, 6)
		var pm := pa.lerp(pb, 0.5) + Vector3(0, -sag, 0)
		var up := Vector3(0, 0.05, 0)
		var out := Vector3(0, 0, 0.05)
		for half: Array in [[pa, pm, u0, um], [pm, pb, um, u1]]:
			var p: Vector3 = half[0]
			var q: Vector3 = half[1]
			var ua: float = float(half[2]) * 2.0
			var ub: float = float(half[3]) * 2.0
			wire.quad4("wire", p - up, q - up, q + up, p + up, Vector2(ua, barb.y), Vector2(ub, barb.y), Vector2(ub, barb.x), Vector2(ua, barb.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)
			wire.quad4("wire", p + out, q + out, q - out, p - out, Vector2(ua, barb.y), Vector2(ub, barb.y), Vector2(ub, barb.x), Vector2(ua, barb.x), WIRE_COL, WIRE_COL, WIRE_COL, WIRE_COL)

## The span after Rook's cutters: both halves of the netting peeled back and rolled against their posts (one to
## each side of the fence line, so the gap shows from every camera yaw), the barbed strands hanging cut, and the
## grass trodden where people slip through.
func span_cut(wire: Kit, fa: Vector3, a: Vector3, fb: Vector3, b: Vector3, u0: float) -> void:
	var length := fa.distance_to(fb)
	var v := Kit.WIRE_MESH
	var sides: Array = [[fa, a, 1.0, -1.0, u0], [fb, b, -1.0, 1.0, u0 + length * Kit.UV_M]]
	for side: Array in sides:
		var foot: Vector3 = side[0]
		var top: Vector3 = side[1]
		var toward: float = side[2]          # +1: the gap lies toward +X of this post
		var swing: float = side[3]           # which side of the fence line the flap curls to
		var u_post: float = side[4]
		var flap := length * 0.47
		var steps := 7
		var height := (top.y - foot.y) * 0.63
		var p := Vector3(foot.x, 0.0, foot.z)
		var lean := (top - foot) / maxf(top.y - foot.y, 0.01)
		var prev_lo := foot
		var prev_hi := foot + lean * height
		var prev_u := u_post
		for i: int in range(steps):
			var s := (float(i) + 1.0) / float(steps)
			# the heading turns away from the fence line and on round, like a roll of netting let go
			var heading := deg_to_rad(38.0 + 150.0 * s * s)
			var dir := Vector3(cos(heading) * toward, 0, sin(heading) * swing)
			p += dir * flap / float(steps) * lerpf(1.0, 0.55, s)
			var lo := Vector3(p.x, 0.03 + 0.10 * s, p.z)
			var hi := Vector3(p.x, 0.03 + height * (1.0 - 0.42 * s * s), p.z) + lean * 0.02
			var u := u_post + toward * flap * s * Kit.UV_M
			var shade := WIRE_COL * Kit.grey(lerpf(1.0, 0.8, s))
			shade.a = 1.0
			wire.quad4("wire", prev_lo, lo, hi, prev_hi, Vector2(prev_u, v.y), Vector2(u, v.y), Vector2(u, v.x), Vector2(prev_u, v.x), shade, shade, shade, shade)
			prev_lo = lo
			prev_hi = hi
			prev_u = u
		# the two barbed strands: cut, sprung back and hanging down the post to the ground
		for t: float in [0.78, 0.93]:
			var from := foot.lerp(top, t)
			var reach := 0.3 + (t - 0.78) * 1.6
			var path := PackedVector3Array([from,
				from + Vector3(toward * reach * 0.45, -from.y * 0.35, -swing * 0.05),
				Vector3(from.x + toward * reach * 0.8, from.y * 0.22, from.z - swing * 0.12),
				Vector3(from.x + toward * reach, 0.035, from.z - swing * 0.2),
				Vector3(from.x + toward * (reach + 0.22), 0.03, from.z - swing * 0.11)])
			wire.tube("steel", path, 0.009, 3, STRAND)
	# trodden earth through the gap and a few snipped ends lying in it
	var mid := fa.lerp(fb, 0.5)
	wire.decal(Kit.DECAL["dirt"], mid.x, mid.z, Vector2(1.9, 2.3), 0.4, Color(0.78, 0.73, 0.64, 0.8), 0.034)
	for i: int in range(5):
		var at := Vector3(mid.x + rng.randf_range(-0.55, 0.55), 0.035, mid.z + rng.randf_range(-0.3, 0.3))
		var yaw := rng.randf() * TAU
		var d := Vector3(cos(yaw), 0, sin(yaw)) * rng.randf_range(0.08, 0.16)
		wire.tube("steel", PackedVector3Array([at - d, at + Vector3(0, 0.02, 0), at + d]), 0.007, 3, Color(0.42, 0.4, 0.38))

# ---------------------------------------------------------------------------------------------------------------
# Tripwire, built round the origin with the wire along local X.
# ---------------------------------------------------------------------------------------------------------------
func tripwire(k: Kit, sprung: bool) -> void:
	var half := TRIP_SPAN * 0.5
	var wood := Props.WOOD_PALE * Kit.grey(0.9)
	var steel := Color(0.86, 0.84, 0.78)
	if not sprung:
		for s: float in [-1.0, 1.0]:
			k.beam("planks", Vector3(s * half, -0.05, 0), Vector3(s * (half + 0.05), 0.2, 0), 0.05, 0.05, wood * Kit.grey(0.6), wood, Vector2(rng.randf(), rng.randf()), true, Vector3.BACK)
			# a turn of wire round the peg
			k.lathe("steel", Vector3(s * (half + 0.03), 0.12, 0), PackedVector2Array([Vector2(0.036, 0.0), Vector2(0.036, 0.03)]), 5, steel * Kit.grey(0.7), steel)
		props.wire(k, Vector3(-half - 0.03, 0.135, 0), Vector3(half + 0.03, 0.135, 0), 0.012, 0.008, steel, 4)
		return
	# sprung: one peg still standing with the wire trailing from it, the other torn out and lying in the grass
	k.beam("planks", Vector3(-half, -0.05, 0), Vector3(-half - 0.05, 0.2, 0), 0.05, 0.05, wood * Kit.grey(0.6), wood, Vector2(0.3, 0.2), true, Vector3.BACK)
	k.tube("steel", PackedVector3Array([Vector3(-half - 0.03, 0.135, 0), Vector3(-half + 0.14, 0.03, 0.06), Vector3(-0.1, 0.02, 0.22), Vector3(0.12, 0.02, 0.1), Vector3(0.2, 0.02, 0.24)]), 0.008, 3, steel)
	k.beam("planks", Vector3(half - 0.08, 0.03, -0.16), Vector3(half + 0.17, 0.035, -0.05), 0.05, 0.05, wood * Kit.grey(0.7), wood, Vector2(0.6, 0.4))
	k.tube("steel", PackedVector3Array([Vector3(half + 0.15, 0.04, -0.06), Vector3(half - 0.05, 0.02, 0.08), Vector3(half - 0.3, 0.02, 0.0)]), 0.008, 3, steel)

# ---------------------------------------------------------------------------------------------------------------
# Generator set against a wall. Built in the wall's face frame (X along the wall, Y up, Z out of it); `cx` is the
# middle of the set along the wall. Returns the points structures.gd animates: {"exhaust", "lamp"} (face space).
# ---------------------------------------------------------------------------------------------------------------
const GEN_PAINT := Color(0.4, 0.44, 0.35)

## Everything that does not change: plinth, skids, the housing (open on top, the hood is part of the state), the
## engine inside it, fuel tank, exhaust stack, and the feed running up the wall. `feed_to`: where the conduit ends.
func generator_base(k: Kit, cx: float, feed_to: Array[Vector3]) -> Dictionary:
	var paint := GEN_PAINT
	k.box("concrete", Vector3(cx, 0.05, 0.34), Vector3(1.56, 0.1, 0.68), Color(0.5, 0.48, 0.44), Kit.grey(0.9))
	for z: float in [0.16, 0.52]:
		k.box("steel", Vector3(cx, 0.13, z), Vector3(1.34, 0.06, 0.07), Props.IRON, Props.IRON * Kit.grey(1.2))
	# housing: four sides, no lid
	k.push_tint(paint)
	k.box("steel", Vector3(cx, 0.47, 0.34), Vector3(1.1, 0.62, 0.46), Kit.grey(0.58), Color.WHITE, Vector2(0.2, 0.7), Kit.AUTO, 0b110011)
	k.pop_tint()
	var grille := Kit.trim_uv("grille")
	k.push_tint(paint)
	k.quad_rect("trim", Vector3(cx + 0.06, 0.22, 0.572), Vector3(cx + 0.46, 0.22, 0.572), Vector3(cx + 0.46, 0.72, 0.572), Vector3(cx + 0.06, 0.72, 0.572), grille, Kit.grey(0.8), Color.WHITE)
	k.pop_tint()
	k.quad_rect("trim", Vector3(cx - 0.46, 0.3, 0.572), Vector3(cx - 0.06, 0.3, 0.572), Vector3(cx - 0.06, 0.7, 0.572), Vector3(cx - 0.46, 0.7, 0.572), Kit.trim_uv("panel"), Kit.grey(0.8), Color.WHITE)
	# what the open hood shows: a dark well, the engine block, the flywheel
	var dark := Kit.grey(0.07)
	k.quad_m("steel", Vector3(cx - 0.54, 0.62, 0.56), Vector3(cx + 0.54, 0.62, 0.56), Vector3(cx + 0.54, 0.62, 0.12), Vector3(cx - 0.54, 0.62, 0.12), Vector2(0.4, 0.4), dark, dark)
	for inner: Array in [[Vector3(cx - 0.54, 0.62, 0.12), Vector3(cx + 0.54, 0.62, 0.12)], [Vector3(cx + 0.54, 0.62, 0.56), Vector3(cx - 0.54, 0.62, 0.56)],
			[Vector3(cx - 0.54, 0.62, 0.56), Vector3(cx - 0.54, 0.62, 0.12)], [Vector3(cx + 0.54, 0.62, 0.12), Vector3(cx + 0.54, 0.62, 0.56)]]:
		var p: Vector3 = inner[0]
		var q: Vector3 = inner[1]
		k.quad_m("steel", p, q, q + Vector3(0, 0.16, 0), p + Vector3(0, 0.16, 0), Vector2(0.1, 0.1), dark, Kit.grey(0.3) * paint)
	k.box("steel", Vector3(cx + 0.2, 0.68, 0.34), Vector3(0.44, 0.12, 0.26), Kit.grey(0.3), Color(0.56, 0.55, 0.52), Vector2(0.6, 0.2))
	k.disc("trim", Vector3(cx - 0.26, 0.69, 0.34), 0.17, 12, Kit.trim_uv("drum_lid"), Color(0.7, 0.62, 0.5))
	for x: float in [cx + 0.08, cx + 0.2, cx + 0.32]:
		k.lathe("steel", Vector3(x, 0.74, 0.34), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.03, 0.035), Vector2(0.012, 0.04)]), 6, Props.IRON_RUST, Props.GALV)
	# fuel tank on a stand at the far end, with its filler cap and feed pipe
	var tx := cx + 0.86
	for z: float in [0.2, 0.44]:
		k.box("steel", Vector3(tx, 0.3, z), Vector3(0.05, 0.5, 0.05), Props.IRON, Props.IRON * Kit.grey(1.2))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx, 0.7, 0.07)))
	k.push_tint(Color(0.55, 0.42, 0.34))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.15, 0.02), Vector2(0.16, 0.06), Vector2(0.16, 0.46), Vector2(0.15, 0.5), Vector2(0.0, 0.52)]), 10, Kit.grey(0.85), Color.WHITE, Vector2(0.3, 0.2))
	k.pop_tint()
	k.pop()
	k.lathe("steel", Vector3(tx, 0.85, 0.3), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.03, 0.04), Vector2(0.0, 0.045)]), 6, Props.IRON, Props.GALV)
	k.tube("steel", PackedVector3Array([Vector3(tx - 0.1, 0.58, 0.32), Vector3(tx - 0.2, 0.52, 0.34), Vector3(cx + 0.55, 0.5, 0.34)]), 0.014, 4, Props.IRON_RUST)
	# exhaust: out of the end of the housing, up the wall and clear of the eaves, with a rain cap
	var ex := cx - 0.72
	var rust := Props.IRON_RUST
	k.tube("steel", PackedVector3Array([Vector3(cx - 0.55, 0.52, 0.2), Vector3(ex, 0.52, 0.2), Vector3(ex, 0.72, 0.5), Vector3(ex, 2.2, 0.5), Vector3(ex, 2.95, 0.5)]), 0.045, 6, rust)
	k.lathe("steel", Vector3(ex, 2.95, 0.5), PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.065, 0.03), Vector2(0.065, 0.1)]), 8, rust * Kit.grey(0.8), rust)
	k.lathe("steel", Vector3(ex, 3.09, 0.5), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.02, 0.05)]), 8, rust, rust * Kit.grey(1.2))
	for y: float in [1.1, 2.1]:
		k.box("steel", Vector3(ex, y, 0.25), Vector3(0.03, 0.03, 0.5), Props.IRON, Props.IRON)
	# junction box on the wall and the armoured feed up to the eaves and away to the aerial
	var jx := cx + 1.2
	k.box("steel", Vector3(jx, 1.25, 0.05), Vector3(0.24, 0.3, 0.1), Props.IRON * Kit.grey(0.9), Props.GALV * Kit.grey(0.7), Vector2(0.5, 0.5))
	var feed := PackedVector3Array([Vector3(jx, 1.4, 0.04), Vector3(jx, 2.18, 0.04)])
	for point: Vector3 in feed_to:
		feed.append(point)
	k.tube("steel", feed, 0.02, 4, Props.IRON)
	return {"exhaust": Vector3(ex, 3.14, 0.5), "lamp": Vector3(jx, 1.45, 0.11), "socket": Vector3(jx, 1.12, 0.09), "terminal": Vector3(cx + 0.55, 0.42, 0.34)}

## The parts that change. Running: hood shut, lead plugged into the junction box. Dead: hood thrown open against
## the wall, the lead pulled out and lying on the ground.
func generator_state(k: Kit, cx: float, running: bool, points: Dictionary) -> void:
	var paint := GEN_PAINT
	var terminal: Vector3 = points.terminal
	var socket: Vector3 = points.socket
	var cable := Color(0.14, 0.14, 0.15)
	if running:
		k.push_tint(paint)
		k.box("steel", Vector3(cx, 0.795, 0.34), Vector3(1.14, 0.035, 0.5), Kit.grey(0.75), Color.WHITE, Vector2(0.1, 0.3))
		k.pop_tint()
		for x: float in [cx - 0.35, cx + 0.35]:
			k.box("steel", Vector3(x, 0.822, 0.5), Vector3(0.12, 0.02, 0.03), Props.IRON, Props.GALV)
		# the lead: along the ground under the tank and up the wall into the junction box
		k.tube("steel", PackedVector3Array([terminal, terminal + Vector3(0.08, -0.3, 0.14), Vector3(socket.x - 0.2, 0.035, 0.38), Vector3(socket.x, 0.04, 0.1), socket + Vector3(0, -0.5, 0.0), socket]), 0.02, 4, cable)
		k.box("steel", socket + Vector3(0, -0.02, 0.01), Vector3(0.08, 0.08, 0.06), Props.IRON, Props.GALV)
		return
	# hood hinged on the wall side, thrown right back
	k.push(Transform3D(Basis(Vector3.RIGHT, -1.7), Vector3(cx, 0.8, 0.1)))
	k.push_tint(paint)
	k.box("steel", Vector3(0, 0.0, 0.25), Vector3(1.14, 0.035, 0.5), Kit.grey(0.6), Color.WHITE, Vector2(0.1, 0.3))
	k.pop_tint()
	k.pop()
	# the lead: still on the generator's terminal, its plug end out on the ground
	k.tube("steel", PackedVector3Array([terminal, terminal + Vector3(0.12, -0.2, 0.1), Vector3(terminal.x + 0.2, 0.04, 0.62), Vector3(terminal.x + 0.05, 0.03, 0.86), Vector3(terminal.x + 0.38, 0.03, 0.98), Vector3(terminal.x + 0.62, 0.03, 0.84)]), 0.02, 4, cable)
	k.box("steel", Vector3(terminal.x + 0.66, 0.045, 0.82), Vector3(0.1, 0.07, 0.07), Props.IRON, Props.GALV)
	# a spanner and the pulled plug leads left where he worked
	k.box("steel", Vector3(cx - 0.2, 0.108, 0.62), Vector3(0.22, 0.012, 0.03), Props.GALV * Kit.grey(0.7), Props.GALV)

# ---------------------------------------------------------------------------------------------------------------
# Hinged door leaf: hinge on the origin, the leaf runs along local +X, its outer face toward local +Z.
# ---------------------------------------------------------------------------------------------------------------
func door_leaf(k: Kit, width: float, height: float, cell: String = "door_plank") -> void:
	var r := Kit.trim_uv(cell)
	var edge := Rect2(r.position + Vector2(0.01, 0.01), Vector2(0.01, 0.2))
	k.box_rects("trim", Vector3(width * 0.5, height * 0.5, 0.0), Vector3(width, height, 0.045), [edge, edge, edge, edge, r, r], Kit.grey(0.78), Kit.grey(0.92))
	for y: float in [0.25, height - 0.3]:
		k.box("steel", Vector3(0.14, y, 0.027), Vector3(0.3, 0.045, 0.012), Props.IRON, Props.IRON * Kit.grey(1.3))

# ---------------------------------------------------------------------------------------------------------------
# Alarm horn and beacon on a bracket (static parts). `at`: the bracket's foot on its mast; the horn faces local +Z.
# Returns the centre of the beacon's glass so the caller can light it.
# ---------------------------------------------------------------------------------------------------------------
func alarm_horn(k: Kit, at: Vector3) -> Vector3:
	var paint := Color(0.5, 0.52, 0.5)
	k.box("steel", at + Vector3(0, 0.0, 0.2), Vector3(0.05, 0.05, 0.44), Props.IRON, Props.IRON * Kit.grey(1.2))
	k.beam("steel", at + Vector3(0, -0.3, 0.02), at + Vector3(0, -0.02, 0.36), 0.025, 0.025, Props.IRON, Props.IRON, Vector2.ZERO, false)
	# flared horn on its driver, slung under the end of the arm
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.18), at + Vector3(0, -0.14, 0.34)))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.07, -0.12), Vector2(0.07, 0.0), Vector2(0.045, 0.03), Vector2(0.06, 0.18), Vector2(0.11, 0.32), Vector2(0.2, 0.42), Vector2(0.215, 0.43)]), 10, paint * Kit.grey(0.7), paint, Vector2(0.2, 0.3))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.2, 0.42), Vector2(0.1, 0.3), Vector2(0.05, 0.16)]), 10, Kit.grey(0.25), Kit.grey(0.1))
	k.pop()
	# beacon: a caged glass standing on the arm
	var foot := at + Vector3(0, 0.025, 0.24)
	k.lathe("steel", foot, PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.075, 0.05), Vector2(0.06, 0.07)]), 8, Props.IRON, Props.IRON * Kit.grey(1.3))
	k.lathe("steel", foot + Vector3(0, 0.27, 0), PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.02, 0.04)]), 8, Props.IRON, Props.IRON * Kit.grey(1.3))
	for i: int in range(4):
		var ang := TAU * float(i) / 4.0 + 0.4
		var o := Vector3(cos(ang), 0, sin(ang)) * 0.075
		k.tube("steel", PackedVector3Array([foot + o + Vector3(0, 0.06, 0), foot + o + Vector3(0, 0.27, 0)]), 0.006, 3, Props.IRON)
	return foot + Vector3(0, 0.165, 0)

## Glass of a lamp (unshaded): a small dome of the given colour.
func lamp_glass(k: Kit, at: Vector3, radius: float, col: Color) -> void:
	k.lathe("glow", at - Vector3(0, radius, 0), PackedVector2Array([Vector2(radius * 0.7, 0.0), Vector2(radius, radius), Vector2(radius * 0.7, radius * 1.8), Vector2(0.0, radius * 2.0)]), 8, col * Kit.grey(0.8), col)
