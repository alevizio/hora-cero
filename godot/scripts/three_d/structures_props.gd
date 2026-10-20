extends RefCounted
## Small reusable props for the structures module (drums, crates, sandbags, tarps, cans, benches, ladders ...).
## Every function appends geometry to the Kit passed in, in the kit's current transform.
const Kit = preload("res://scripts/three_d/structures_kit.gd")

const WOOD_GREY := Color(0.78, 0.76, 0.72)
const WOOD_DARK := Color(0.44, 0.38, 0.32)
const WOOD_PALE := Color(1.0, 0.96, 0.86)
const WOOD_CREAM := Color(0.98, 0.96, 0.86)
const IRON := Color(0.34, 0.33, 0.32)
const IRON_RUST := Color(0.46, 0.36, 0.3)
const DRAB := Color(0.52, 0.56, 0.43)
const DRAB_DARK := Color(0.4, 0.44, 0.35)
const GALV := Color(0.8, 0.82, 0.82)
const AO := Color(0.55, 0.53, 0.5)

var rng := RandomNumberGenerator.new()

func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value

func jitter(amount: float) -> float:
	return rng.randf_range(-amount, amount)

func tone(spread: float = 0.1) -> Color:
	var g := 1.0 - rng.randf() * spread
	return Color(g, g * rng.randf_range(0.97, 1.0), g * rng.randf_range(0.93, 1.0))

# ---------------------------------------------------------------------------------------------------------------
# Oil drum: ribbed 200 litre barrel, 0.58 m across, 0.88 m tall. at = centre of the base.
# ---------------------------------------------------------------------------------------------------------------
func barrel(k: Kit, at: Vector3, tint: Color, yaw: float = 0.0, lying: bool = false, open_top: bool = false) -> void:
	var r := 0.29
	var prof := PackedVector2Array([Vector2(r - 0.02, 0.0), Vector2(r, 0.02), Vector2(r, 0.275), Vector2(r + 0.014, 0.29), Vector2(r + 0.014, 0.305), Vector2(r, 0.32),
		Vector2(r, 0.56), Vector2(r + 0.014, 0.575), Vector2(r + 0.014, 0.59), Vector2(r, 0.605), Vector2(r, 0.86), Vector2(r - 0.004, 0.88), Vector2(r - 0.02, 0.88), Vector2(r - 0.02, 0.862)])
	var xform := Transform3D(Basis(Vector3.UP, yaw), at)
	if lying:
		xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3.UP * (r + 0.014))
	k.push(xform)
	k.push_tint(tint)
	var lo := Color(0.52, 0.5, 0.47) if not lying else Color(0.8, 0.8, 0.8)
	k.lathe("steel", Vector3.ZERO, prof, 14, lo, Color.WHITE, Vector2(rng.randf(), rng.randf()))
	if open_top:
		# empty drum: dark inside
		k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(r - 0.02, 0.862), Vector2(r - 0.03, 0.3)]), 14, Kit.grey(0.12), Kit.grey(0.5))
		k.disc("steel", Vector3(0, 0.3, 0), r - 0.03, 14, Rect2(0.1, 0.1, 0.1, 0.1), Kit.grey(0.1))
	else:
		k.disc("trim", Vector3(0, 0.862, 0), r - 0.02, 14, Kit.trim_uv("drum_lid"), Kit.grey(0.92))
	if lying:
		k.disc("trim", Vector3.ZERO, r - 0.02, 14, Kit.trim_uv("drum_lid"), Kit.grey(0.7), true)
	k.pop_tint()
	k.pop()

# ---------------------------------------------------------------------------------------------------------------
# Crates (atlas mapped). at = centre of the base; size = full extents; side faces along local X.
# ---------------------------------------------------------------------------------------------------------------
func crate(k: Kit, at: Vector3, size: Vector3, yaw: float = 0.0, style: int = 0, tint: Color = Color.WHITE) -> void:
	var side: Rect2 = Kit.cell_uv(Kit.CRATE["braced"] if style % 2 == 0 else Kit.CRATE["stencil"])
	var side_b: Rect2 = Kit.cell_uv(Kit.CRATE["stencil"] if style % 3 != 1 else Kit.CRATE["braced"])
	var end: Rect2 = Kit.cell_uv(Kit.CRATE["end"] if style < 4 else Kit.CRATE["braced"])
	var lid: Rect2 = Kit.cell_uv(Kit.CRATE["lid"])
	k.push_at(at, yaw)
	k.push_tint(tint)
	k.box_rects("crate", Vector3(0, size.y * 0.5, 0), size, [end, end, lid, null, side, side_b], Color(0.58, 0.55, 0.5), Color.WHITE)
	k.pop_tint()
	k.pop()

## Small steel ammunition / tool box.
func steel_box(k: Kit, at: Vector3, size: Vector3, yaw: float, tint: Color) -> void:
	k.push_at(at, yaw)
	k.push_tint(tint)
	k.box("steel", Vector3(0, size.y * 0.5, 0), size, Kit.grey(0.6), Color.WHITE, Vector2(rng.randf(), rng.randf()), Kit.AUTO, 0b110111)
	k.box("steel", Vector3(0, size.y + 0.012, 0), Vector3(size.x * 0.4, 0.024, 0.03), Kit.grey(0.6), Kit.grey(0.8))
	k.pop_tint()
	k.pop()

func jerrycan(k: Kit, at: Vector3, yaw: float, tint: Color = DRAB, lying: bool = false) -> void:
	var xform := Transform3D(Basis(Vector3.UP, yaw), at)
	if lying:
		xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), at + Vector3.UP * 0.085)
	k.push(xform)
	k.push_tint(tint)
	var uv := Vector2(rng.randf(), rng.randf())
	k.box("steel", Vector3(0, 0.2, 0), Vector3(0.34, 0.4, 0.16), Kit.grey(0.55), Color.WHITE, uv, false, 0b110111)
	k.box("steel", Vector3(0, 0.42, 0), Vector3(0.3, 0.04, 0.13), Color.WHITE, Color.WHITE, uv)
	for z: float in [-0.045, 0.0, 0.045]:
		k.box("steel", Vector3(-0.02, 0.465, z), Vector3(0.17, 0.022, 0.018), Kit.grey(0.7), Kit.grey(0.95), uv)
	k.box("steel", Vector3(0.13, 0.46, 0), Vector3(0.05, 0.06, 0.05), Kit.grey(0.5), Kit.grey(0.8), uv)
	k.pop_tint()
	k.pop()

func bucket(k: Kit, at: Vector3, tint: Color, r: float = 0.14, h: float = 0.26) -> void:
	k.push_at(at, rng.randf() * TAU)
	k.push_tint(tint)
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(r * 0.72, 0.0), Vector2(r, h), Vector2(r - 0.012, h), Vector2(r * 0.72 - 0.01, 0.03)]), 10, Kit.grey(0.6), Color.WHITE,
		Vector2(rng.randf(), rng.randf()), PackedFloat32Array([1.0, 1.0, 0.75, 0.2]))
	k.disc("steel", Vector3(0, 0.03, 0), r * 0.72 - 0.01, 10, Rect2(0.3, 0.3, 0.05, 0.05), Kit.grey(0.16))
	var arc := PackedVector3Array()
	for i: int in range(7):
		var a := PI * float(i) / 6.0
		arc.append(Vector3(cos(a) * r, h - 0.01 + sin(a) * 0.05, sin(a) * r * 0.9))
	k.tube("steel", arc, 0.006, 3, Kit.grey(0.5))
	k.pop_tint()
	k.pop()

func pallet(k: Kit, at: Vector3, yaw: float, size: Vector2 = Vector2(1.2, 1.0)) -> void:
	k.push_at(at, yaw)
	k.push_tint(WOOD_GREY * tone(0.15))
	for z: float in [-size.y * 0.5 + 0.05, 0.0, size.y * 0.5 - 0.05]:
		k.box("planks", Vector3(0, 0.05, z), Vector3(size.x, 0.1, 0.09), Kit.grey(0.5), Kit.grey(0.8), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	var n := 6
	for i: int in range(n):
		var x := -size.x * 0.5 + 0.06 + (size.x - 0.12) * float(i) / float(n - 1)
		k.box("planks", Vector3(x, 0.112, 0), Vector3(0.1, 0.024, size.y), Kit.grey(0.8), Color.WHITE, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	k.pop()

# ---------------------------------------------------------------------------------------------------------------
# Sandbag: a sagging filled sack lying along local X. at = centre of its underside.
# ---------------------------------------------------------------------------------------------------------------
func sandbag(k: Kit, at: Vector3, yaw: float, length: float = 0.66, width: float = 0.34, height: float = 0.2, tint: Color = Color.WHITE, roll: float = 0.0) -> void:
	var rows := 7
	var columns := 9
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var bulge := rng.randf_range(0.9, 1.08)
	var skew := jitter(0.03)
	var u_off := rng.randf()
	for i: int in range(rows):
		var t := -1.0 + 2.0 * float(i) / float(rows - 1)
		var s := pow(maxf(0.0, 1.0 - pow(absf(t), 3.2)), 0.42)
		var end_pinch := 0.35 + 0.65 * s
		for j: int in range(columns):
			var a := TAU * float(j) / float(columns - 1)
			var ca := cos(a)
			var sa := sin(a)
			# squared-off cross section, flatter underneath, fuller in the middle of the bag
			var px := signf(ca) * pow(absf(ca), 0.62) * width * 0.5 * s * bulge
			var py := signf(sa) * pow(absf(sa), 0.7) * height * 0.5 * end_pinch
			if py < 0.0:
				py *= 0.82
				px *= 1.06
			var y := py + height * 0.41 - (1.0 - s) * height * 0.12
			pts.append(Vector3(t * length * 0.5 * (0.93 + 0.07 * absf(ca)) + skew * sa, y, px))
			uvs.append(Vector2(u_off + 0.5 + t * 0.5, float(j) / float(columns - 1) * 2.0))
			var g := 0.5 + 0.5 * clampf(y / height + 0.12, 0.0, 1.0)
			cols.append(Color(g * tint.r, g * tint.g, g * tint.b))
	k.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, roll), at))
	k.patch("burlap", rows, columns, pts, uvs, cols, true, true)
	k.pop()

## A straight run of stacked sandbags from a to b (ground points), `courses` high, staggered like brickwork.
func sandbag_wall(k: Kit, a: Vector3, b: Vector3, courses: int, bag_len: float = 0.62, depth: int = 1) -> void:
	var d := b - a
	var total := d.length()
	var dir := d / total
	var yaw := atan2(-dir.z, dir.x)
	var side := Vector3(-dir.z, 0, dir.x)
	var n := maxi(1, int(round(total / bag_len)))
	var step := total / float(n)
	for c: int in range(courses):
		var off := 0.5 if c % 2 == 1 else 0.0
		var count := n - (1 if c % 2 == 1 else 0)
		for row: int in range(depth):
			for i: int in range(count):
				var along := (float(i) + 0.5 + off) * step
				var p := a + dir * along + side * ((float(row) - float(depth - 1) * 0.5) * 0.33 + jitter(0.025))
				p.y = a.y + float(c) * 0.185
				var g := rng.randf_range(0.82, 1.0)
				sandbag(k, p, yaw + jitter(0.09), step * rng.randf_range(1.0, 1.08), 0.35, 0.2, Color(g, g * rng.randf_range(0.95, 1.0), g * rng.randf_range(0.86, 0.98)), jitter(0.06))

# ---------------------------------------------------------------------------------------------------------------
# Tarpaulin draped over a block: covers the rectangle centre/size at top_y and hangs `drop` down the sides.
# sides: how far the cloth reaches beyond each edge (x-, x+, z-, z+) in metres; 0 = stops at the edge.
# ---------------------------------------------------------------------------------------------------------------
func tarp(k: Kit, centre: Vector3, size: Vector2, drop: float, tint: Color, sides: Array = [0.25, 0.25, 0.25, 0.25], seed_value: int = 0) -> void:
	var n := 11
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var noise := FastNoiseLite.new()
	noise.seed = 7919 + seed_value
	noise.frequency = 2.2
	var x0: float = -size.x * 0.5 - float(sides[0])
	var x1: float = size.x * 0.5 + float(sides[1])
	var z0: float = -size.y * 0.5 - float(sides[2])
	var z1: float = size.y * 0.5 + float(sides[3])
	for i: int in range(n):
		var z := lerpf(z0, z1, float(i) / float(n - 1))
		for j: int in range(n):
			var x := lerpf(x0, x1, float(j) / float(n - 1))
			# distance outside the supported rectangle
			var ox := maxf(0.0, absf(x) - size.x * 0.5)
			var oz := maxf(0.0, absf(z) - size.y * 0.5)
			var o := sqrt(ox * ox + oz * oz)
			var reach := 0.3
			var hang := clampf(o / reach, 0.0, 1.0)
			var wr := noise.get_noise_2d(x, z)
			var w2 := noise.get_noise_2d(x * 2.3 + 9.0, z * 2.3 - 4.0)
			# cloth lies lumpy over what is underneath, then falls away in uneven folds
			var y := centre.y + 0.03 + (wr * 0.05 + w2 * 0.02) * (1.0 - hang) - drop * pow(hang, 1.5) * (0.8 + 0.5 * w2)
			var px := x
			var pz := z
			if ox > 0.0:
				px = signf(x) * (size.x * 0.5 + ox * (0.5 + 0.35 * w2))
			if oz > 0.0:
				pz = signf(z) * (size.y * 0.5 + oz * (0.5 + 0.35 * wr))
			pts.append(Vector3(centre.x + px, y, centre.z + pz))
			uvs.append(Vector2(x, z) * Kit.UV_M + Vector2(seed_value * 0.37, seed_value * 0.21))
			var g := 1.0 - 0.3 * hang + 0.16 * w2
			cols.append(Color(tint.r * g, tint.g * g, tint.b * g))
	k.patch("canvas", n, n, pts, uvs, cols, false, true)

## Coil of rope lying on a surface.
func rope_coil(k: Kit, at: Vector3, radius: float = 0.18, turns: int = 4) -> void:
	var path := PackedVector3Array()
	var steps := turns * 10
	for i: int in range(steps + 1):
		var a := TAU * float(i) / 10.0
		var r := radius * (0.55 + 0.45 * float(i) / float(steps))
		path.append(at + Vector3(cos(a) * r, 0.02 + 0.012 * float(i % 20) / 20.0, sin(a) * r))
	k.tube("burlap", path, 0.016, 4, Color(0.8, 0.74, 0.6), Vector2.ZERO, 0.25, 6.0)

func ladder(k: Kit, base: Vector3, top: Vector3, width: float = 0.42, tint: Color = WOOD_GREY) -> void:
	var d := top - base
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	k.push_tint(tint)
	for s: float in [-0.5, 0.5]:
		k.beam("planks", base + side * width * s, top + side * width * s, 0.035, 0.07, Kit.grey(0.75), Color.WHITE, Vector2(rng.randf(), rng.randf()))
	var count := int(d.length() / 0.29)
	for i: int in range(1, count):
		var p := base + d * (float(i) / float(count))
		k.beam("planks", p - side * width * 0.5, p + side * width * 0.5, 0.03, 0.03, Kit.grey(0.7), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()))
	k.pop_tint()

func bench(k: Kit, at: Vector3, yaw: float, length: float = 1.5, tint: Color = WOOD_GREY) -> void:
	k.push_at(at, yaw)
	k.push_tint(tint)
	k.box("planks", Vector3(0, 0.44, 0), Vector3(length, 0.045, 0.28), Kit.grey(0.75), Color.WHITE, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	for x: float in [-length * 0.5 + 0.16, length * 0.5 - 0.16]:
		k.box("planks", Vector3(x, 0.21, 0), Vector3(0.05, 0.42, 0.24), AO, Kit.grey(0.85), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.box("planks", Vector3(0, 0.2, 0), Vector3(length - 0.34, 0.07, 0.03), Kit.grey(0.6), Kit.grey(0.8), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	k.pop()

## Stack of split firewood against a wall: logs lie along local Z, the stack runs along local X.
func firewood(k: Kit, at: Vector3, yaw: float, length: float, courses: int = 4) -> void:
	k.push_at(at, yaw)
	var r := 0.07
	for c: int in range(courses):
		var count := int(length / (r * 2.0)) - (c % 2)
		for i: int in range(count):
			if c == courses - 1 and rng.randf() < 0.35:
				continue
			var x := -length * 0.5 + r + (float(i) + 0.5 * float(c % 2)) * r * 2.0 + jitter(0.01)
			var y := r + float(c) * r * 1.74
			var rr := r * rng.randf_range(0.8, 1.05)
			var zl := 0.19 + jitter(0.03)
			var g := rng.randf_range(0.6, 0.95)
			var col := Color(g, g * 0.92, g * 0.8)
			k.tube("planks", PackedVector3Array([Vector3(x, y, -zl), Vector3(x, y, zl)]), rr, 6, col * Kit.grey(0.75), Vector2(rng.randf(), rng.randf()), Kit.PLANK_ROW * 0.8)
			# pale end grain facing out
			k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, zl)))
			k.disc("planks", Vector3.ZERO, rr, 6, Rect2(rng.randf() * 0.9, rng.randf() * 0.9, 0.03, 0.03), Color(1.0, 0.93, 0.74) * Kit.grey(g))
			k.pop()
	k.pop()

## Wooden cable drum standing on its rims, axle along local Z.
func cable_drum(k: Kit, at: Vector3, yaw: float, r: float = 0.5, width: float = 0.5) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3.UP * r))
	var uv := Kit.trim_uv("cable_drum")
	for s: float in [-1.0, 1.0]:
		var y := s * width * 0.5
		k.lathe("planks", Vector3(0, y - 0.025, 0), PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.05)]), 16, WOOD_GREY * Kit.grey(0.8), WOOD_GREY, Vector2(rng.randf(), 0.0), PackedFloat32Array(), -1.0, true)
		k.disc("trim", Vector3(0, y + s * 0.025, 0), r, 16, uv, Kit.grey(0.9), s < 0.0)
	# wound cable
	var prof := PackedVector2Array()
	for i: int in range(9):
		var t := float(i) / 8.0
		prof.append(Vector2(r * 0.62 + (0.012 if i % 2 == 1 else 0.0), lerpf(-width * 0.5 + 0.025, width * 0.5 - 0.025, t)))
	k.lathe("rubber", Vector3.ZERO, prof, 12, Kit.grey(0.7), Kit.grey(0.9), Vector2.ZERO, PackedFloat32Array(), 3.0)
	k.pop()

## Wall lamp on a swan-neck bracket (unlit). The bracket leaves the wall along local +Z.
func wall_lamp(k: Kit, at: Vector3, yaw: float, reach: float = 0.35) -> void:
	k.push_at(at, yaw)
	var path := PackedVector3Array()
	for i: int in range(7):
		var a := PI * float(i) / 6.0
		path.append(Vector3(0, 0.12 * sin(a), reach * 0.5 * (1.0 - cos(a))))
	k.tube("steel", path, 0.014, 4, IRON)
	k.lathe("steel", Vector3(0, -0.1, reach), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.05, 0.07), Vector2(0.03, 0.11)]), 10, DRAB_DARK * Kit.grey(0.8), DRAB_DARK)
	k.disc("steel", Vector3(0, -0.095, reach), 0.125, 10, Rect2(0.2, 0.2, 0.05, 0.05), Kit.grey(0.9), true)
	k.pop()

## Timber utility pole with crossarms and insulators. Returns the wire attachment points in the kit's space.
func utility_pole(k: Kit, at: Vector3, yaw: float, height: float = 6.5, arms: int = 1, lean: float = 0.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var local := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean), at)
	k.push(local)
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.13, -0.3), Vector2(0.125, 0.6), Vector2(0.1, height * 0.6), Vector2(0.08, height), Vector2(0.03, height + 0.06)]), 8,
		WOOD_DARK * Kit.grey(0.6), WOOD_DARK, Vector2(rng.randf(), 0.0), PackedFloat32Array(), -1.0, true)
	for i: int in range(arms):
		var y := height - 0.35 - float(i) * 0.45
		k.box("planks", Vector3(0, y, 0.1), Vector3(0.09, 0.09, 1.5), WOOD_DARK * Kit.grey(0.7), WOOD_DARK, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
		k.beam("steel", Vector3(0, y - 0.3, 0.02), Vector3(0, y - 0.04, 0.55), 0.012, 0.03, IRON, IRON)
		k.beam("steel", Vector3(0, y - 0.3, 0.02), Vector3(0, y - 0.04, -0.35), 0.012, 0.03, IRON, IRON)
		for z: float in [-0.55, 0.75]:
			k.lathe("steel", Vector3(0, y + 0.045, z), PackedVector2Array([Vector2(0.012, 0.0), Vector2(0.012, 0.05), Vector2(0.04, 0.06), Vector2(0.045, 0.1), Vector2(0.02, 0.13)]), 6, Color(0.92, 0.9, 0.84), Color(0.98, 0.97, 0.92))
			out.append(k.xf * Vector3(0, y + 0.15, z))
	k.pop()
	return out

## Sagging wire between two points (same space as the kit transform).
func wire(k: Kit, a: Vector3, b: Vector3, sag: float, radius: float = 0.012, col: Color = Color(0.2, 0.2, 0.2), segments: int = 10) -> void:
	var path := PackedVector3Array()
	for i: int in range(segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		path.append(p)
	k.tube("steel", path, radius, 3, col)

## Rectangular duckboard lying on the ground (walkable dressing): slats across two runners.
func duckboard(k: Kit, at: Vector3, yaw: float, length: float = 1.6, width: float = 0.6) -> void:
	k.push_at(at, yaw)
	k.push_tint(WOOD_GREY * tone(0.12))
	var n := int(length / 0.13)
	for i: int in range(n):
		var x := -length * 0.5 + 0.06 + float(i) * (length - 0.12) / float(n - 1)
		k.box("planks", Vector3(x, 0.022, jitter(0.012)), Vector3(0.1, 0.02, width), Kit.grey(0.6), Kit.grey(rng.randf_range(0.8, 1.0)), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110111)
	k.pop_tint()
	k.pop()

## Tyre as a torus patch (U round the tread, V across the profile). With an identity basis it lies flat with its
## underside on the transform origin; rotate the basis to stand it up.
func tyre(k: Kit, xf: Transform3D, big: float = 0.31, small: float = 0.1, squash: float = 1.1) -> void:
	var rows := 8
	var columns := 15
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(rows):
		var b := TAU * float(i) / float(rows - 1)
		for j: int in range(columns):
			var a := TAU * float(j) / float(columns - 1)
			var r := big + cos(b) * small * squash
			pts.append(Vector3(cos(a) * r, small + sin(b) * small, -sin(a) * r))
			uvs.append(Vector2(float(j) / float(columns - 1) * 5.0, 0.5 - float(i) / float(rows - 1)))
			cols.append(Kit.grey(0.62 + 0.38 * (0.5 + 0.5 * sin(b))))
	k.push(xf)
	k.patch("rubber", rows, columns, pts, uvs, cols, true, false, true)
	k.pop()
