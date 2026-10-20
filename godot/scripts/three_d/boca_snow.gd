extends RefCounted
## Snow lying in a layer of its own, as geometry: wet snow a hand deep, rounded on top, hanging a little over every
## edge it lies on. Ledges, rails, sills, cornices, parapets and kerbs get a ridge; flat roofs and car roofs a pillow;
## pitched roofs a sheet that curls over the eaves; walls a drift at their foot. Everything goes into the kit under
## KEY, which La Boca draws as the snow layer of its walls array (one surface with the walls it lies on).

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const KEY := "snow"
## Vertex colour: the snow's own brightness (the layer is white snow; the shader adds no snow on snow).
const WHITE := Color(0.95, 0.95, 0.98, 1.0)

## A rounded strip of snow along a ledge from a to b (on the ledge's top), `up` the ledge's normal: `width` across,
## `height` at its crown, hanging `lip` over both edges and drooping `droop` x height below them. With an rng, the
## crown rises and falls a little along the way. Its ends are left open unless `caps` (too small to see from the
## game's camera; a car's or a girder's are closed).
static func ridge(k: Kit, a: Vector3, b: Vector3, up: Vector3, width: float, height: float, lip: float = 0.04, rng: RandomNumberGenerator = null, droop: float = 0.5, caps: bool = false) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.04 or width < 0.01: return
	var dir := along / length
	var across := dir.cross(up).normalized()
	if across.length_squared() < 0.5: return
	up = across.cross(dir).normalized()
	var hw := width * 0.5
	var prof: Array[Vector2] = [Vector2(-hw - lip, -height * droop), Vector2(-hw - lip * 0.7, height * 0.3), Vector2(-hw * 0.55, height * 0.9),
		Vector2(hw * 0.55, height * 0.9), Vector2(hw + lip * 0.7, height * 0.3), Vector2(hw + lip, -height * droop)]
	if width < 0.36 and not caps:
		# a sill's or a rail's: a few pixels from the game's camera, four points round are enough
		prof = [Vector2(-hw - lip, -height * droop), Vector2(-hw * 0.6, height * 0.85), Vector2(hw * 0.6, height * 0.85), Vector2(hw + lip, -height * droop)]
	# rows along the ledge: enough for the crown to rise and fall a little where it is long
	var rows := 2 if (rng == null or length < 1.6 or prof.size() == 4) else clampi(int(length / 4.5) + 2, 3, 5)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var t := float(i) / float(rows - 1)
		var s := 1.0
		if rng != null and i > 0 and i < rows - 1: s = rng.randf_range(0.8, 1.18)
		var p := a + along * t
		for q: Vector2 in prof:
			pts.append(p + across * q.x + up * (q.y * s if q.y > 0.0 else q.y))
			uvs.append(Vector2(q.x * 0.4, t * length * 0.4))
	k.patch(KEY, rows, prof.size(), pts, uvs, PackedColorArray([WHITE]))
	if not caps: return
	# the two ends
	for e: int in range(2):
		var base := a if e == 0 else b
		var c := base + up * height * 0.3
		for j: int in range(prof.size() - 1):
			var p0: Vector3 = base + across * prof[j].x + up * prof[j].y
			var p1: Vector3 = base + across * prof[j + 1].x + up * prof[j + 1].y
			if e == 0: k.tri(KEY, c, p1, p0, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), WHITE, WHITE, WHITE)
			else: k.tri(KEY, c, p0, p1, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), WHITE, WHITE, WHITE)

## A ridge on a horizontal axis-aligned or edge-aligned top: centre of the top face, the direction it runs, its
## length and its depth across.
static func cap(k: Kit, top: Vector3, run: Vector3, length: float, depth: float, height: float, lip: float = 0.04, rng: RandomNumberGenerator = null) -> void:
	var d := run.normalized() * length * 0.5
	ridge(k, top - d, top + d, Vector3.UP, depth, height, lip, rng)

## Inset a convex polygon (the lots' outlines run counter-clockwise seen from above) by d.
static func inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i: int in range(n):
		var p := poly[i]
		var prev := poly[(i + n - 1) % n]
		var next := poly[(i + 1) % n]
		var e1 := (p - prev).normalized()
		var e2 := (next - p).normalized()
		# inward normals: the outward normal of (dx, dz) is (-dz, dx)
		var n1 := Vector2(e1.y, -e1.x)
		var n2 := Vector2(e2.y, -e2.x)
		var m := n1 + n2
		var den := 1.0 + n1.dot(n2)
		out.append(p + (m * d / den if den > 0.05 else n1 * d))
	return out

## A pillow of snow on a flat roof or a flat top (a convex outline at height y): `t` thick at the crown, rounded
## down to nothing at the outline over `edge` metres; with an rng, a little uneven.
static func pillow(k: Kit, poly: PackedVector2Array, y: float, t: float, edge: float, rng: RandomNumberGenerator = null) -> void:
	if poly.size() < 3: return
	var r0 := poly
	var r1 := inset(poly, edge * 0.3)
	var r2 := inset(poly, edge)
	var h1 := t * 0.72
	var n := poly.size()
	var c := Vector2.ZERO
	for p: Vector2 in r2: c += p
	c /= float(n)
	var crown := y + t * (rng.randf_range(1.0, 1.25) if rng != null else 1.1)
	for i: int in range(n):
		var j := (i + 1) % n
		k.quad4(KEY, Vector3(r0[i].x, y, r0[i].y), Vector3(r0[j].x, y, r0[j].y), Vector3(r1[j].x, y + h1, r1[j].y), Vector3(r1[i].x, y + h1, r1[i].y),
			r0[i] * 0.4, r0[j] * 0.4, r1[j] * 0.4, r1[i] * 0.4, WHITE, WHITE, WHITE, WHITE)
		k.quad4(KEY, Vector3(r1[i].x, y + h1, r1[i].y), Vector3(r1[j].x, y + h1, r1[j].y), Vector3(r2[j].x, y + t, r2[j].y), Vector3(r2[i].x, y + t, r2[i].y),
			r1[i] * 0.4, r1[j] * 0.4, r2[j] * 0.4, r2[i] * 0.4, WHITE, WHITE, WHITE, WHITE)
		k.tri(KEY, Vector3(c.x, crown, c.y), Vector3(r2[i].x, y + t, r2[i].y), Vector3(r2[j].x, y + t, r2[j].y), c * 0.4, r2[i] * 0.4, r2[j] * 0.4, WHITE, WHITE, WHITE)

static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([Vector2(r.position.x, r.end.y), r.end, Vector2(r.end.x, r.position.y), r.position])

## A pillow on an axis-aligned box top.
static func box_top(k: Kit, centre_top: Vector3, size: Vector2, t: float, rng: RandomNumberGenerator = null) -> void:
	var r := Rect2(centre_top.x - size.x * 0.5, centre_top.z - size.y * 0.5, size.x, size.y)
	pillow(k, rect_poly(r), centre_top.y, t, minf(size.x, size.y) * 0.3, rng)

## Snow on one plane of a pitched roof: a sheet `t` thick from just under the ridge down the slope, curling over the
## eave in a rounded nose that hangs `nose` below it. eave_a -> eave_b along the eave (seen from outside, left to
## right), ridge_a / ridge_b the ridge above them; n the roof's outward normal.
static func slope(k: Kit, eave_a: Vector3, eave_b: Vector3, ridge_a: Vector3, ridge_b: Vector3, n: Vector3, t: float, nose: float, rng: RandomNumberGenerator = null) -> void:
	var down := ((eave_a - ridge_a) + (eave_b - ridge_b)) * 0.5
	var run := down.length()
	if run < 0.05: return
	var dd := down / run
	# across the slope: from the ridge (u = 0) down to the eave (u = run) and over it
	var prof: Array[Vector2] = [Vector2(-0.02, t * 0.4), Vector2(0.08, t * 0.95), Vector2(run * 0.5, t * 1.05), Vector2(run * 0.92, t),
		Vector2(run + nose * 0.55, t * 0.55), Vector2(run + nose * 0.85, -nose * 0.35), Vector2(run + nose * 0.6, -nose * 0.95)]
	var along := eave_b - eave_a
	var length := along.length()
	var rows := clampi(int(length / 2.6) + 2, 2, 6)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var tt := float(i) / float(rows - 1)
		var s := rng.randf_range(0.85, 1.15) if (rng != null and i > 0 and i < rows - 1) else 1.0
		var top := ridge_a.lerp(ridge_b, tt)
		for q: Vector2 in prof:
			pts.append(top + dd * q.x + n * (q.y * s if q.y > 0.0 else q.y))
			uvs.append(Vector2(tt * length, q.x) * 0.4)
	# rows run along the eave, columns down the slope: normal = d/dcolumn x d/drow = dd x along
	var flip := dd.cross(along).dot(n) < 0.0
	k.patch(KEY, rows, prof.size(), pts, uvs, PackedColorArray([WHITE]), false, flip)
	# the gable ends of the sheet
	for e: int in range(2):
		var top2 := ridge_a if e == 0 else ridge_b
		var c := top2 + dd * run * 0.5
		for j: int in range(prof.size() - 1):
			var p0: Vector3 = top2 + dd * prof[j].x + n * prof[j].y
			var p1: Vector3 = top2 + dd * prof[j + 1].x + n * prof[j + 1].y
			var face_n := (p0 - c).cross(p1 - c)
			var want := -along if e == 0 else along
			if face_n.dot(want) >= 0.0: k.tri(KEY, c, p0, p1, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), WHITE, WHITE, WHITE)
			else: k.tri(KEY, c, p1, p0, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), WHITE, WHITE, WHITE)

## A drift of snow at the foot of a wall from a to b (on the ground), banked `h` high against it and running out
## `d` from it (`out`, the wall's outward normal).
static func drift(k: Kit, a: Vector3, b: Vector3, out: Vector3, h: float, d: float, rng: RandomNumberGenerator = null) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.2: return
	var prof: Array[Vector2] = [Vector2(-0.02, h), Vector2(d * 0.18, h * 0.86), Vector2(d * 0.5, h * 0.45), Vector2(d * 0.82, h * 0.12), Vector2(d, -0.02)]
	var rows := clampi(int(length / 1.6) + 2, 3, 6)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var t := float(i) / float(rows - 1)
		# the drift tapers to nothing at its two ends
		var taper := smoothstep(0.0, 0.18, t) * smoothstep(1.0, 0.82, t)
		var s := taper * (rng.randf_range(0.7, 1.25) if rng != null else 1.0)
		var p := a + along * t
		for q: Vector2 in prof:
			pts.append(p + out * q.x * (0.5 + 0.5 * s) + Vector3.UP * maxf(q.y * s, -0.02))
			uvs.append(Vector2(t * length, q.x) * 0.4)
	# columns run out from the wall, rows along it: normal = d/dcolumn x d/drow, up and out when out x along is up
	var flip := out.cross(along).dot(Vector3.UP) < 0.0
	k.patch(KEY, rows, prof.size(), pts, uvs, PackedColorArray([WHITE]), false, flip)

## A cone of snow on a lamp's cap or a post's top.
static func cone(k: Kit, at: Vector3, r: float, h: float) -> void:
	k.lathe(KEY, at, PackedVector2Array([Vector2(r * 1.08, -0.02), Vector2(r * 0.7, h * 0.7), Vector2(0.0, h)]), 5, WHITE, WHITE)

## A ball of snow (snowmen, snowballs, the lumps on a post).
static func ball(k: Kit, at: Vector3, r: float) -> void:
	var p := PackedVector2Array()
	for i: int in range(6):
		var a := -PI * 0.5 + PI * float(i) / 5.0
		p.append(Vector2(maxf(cos(a) * r, 0.0), r + sin(a) * r))
	k.lathe(KEY, at, p, 8, WHITE * 0.96, WHITE)
