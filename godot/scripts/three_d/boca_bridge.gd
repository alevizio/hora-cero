extends RefCounted
## The transporter bridge over the Riachuelo (the Transbordador, 1914), La Boca's landmark, almost 40 m of riveted iron:
## on each bank two lattice pylons, each standing on a leg at the quay's edge and a leg on a concrete drum in the river,
## tapering up to a deep lattice girder that runs out a little past them over both banks; portal girders between the
## pylons of a bank; on the girder the trolley, and hanging from it on a fan of cables some 33 m long the gondola (a
## deck with railings, the operator's cabin lit, lamps at its corners), which rides across with whoever is on it
## (boca.gd moves it). Snow lies along the chords and the cross members. Downstream, in the haze, the road bridge of
## 1940: two towers almost 50 m tall and the steel lift span between them.
##
## Only the pylons' quay legs stand on the ground, inside the rules' post rectangles at the quay's edge; the river legs
## stand in the water, the rest high overhead. The river legs splay out so the gondola passes between them.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Houses = preload("res://scripts/three_d/boca_houses.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")
## The girder's bottom and top chords (m above the quay).
const LOW := 34.0
const HIGH := 38.5
const STEEL := Color(0.56, 0.6, 0.6)
const STEEL_LIT := Color(0.68, 0.72, 0.72)

var b: Node3D
var gx0: float
var gx1: float
var river := Vector2(110.0, 134.0)
var water_y: float = -2.3
## Where the girder ends over each bank (z).
var z_north: float
var z_south: float
var rng := RandomNumberGenerator.new()

func _init(owner: Node3D, g: Array, river_band: Vector2, water: float) -> void:
	b = owner
	gx0 = float(g[0]) - 0.5
	gx1 = float(g[1]) + 0.5
	river = river_band
	water_y = water
	z_north = river.x - 5.0
	z_south = river.y + 5.0
	rng.seed = 1914

func build() -> Node3D:
	var root: Node3D = b.node("Transporter")
	for bank: int in range(2):
		var k := Kit.new()
		var into := 1.0 if bank == 0 else -1.0
		var z_in := river.x - 0.75 if bank == 0 else river.y + 0.75
		var z_out := z_in + into * 4.35
		for x: float in [gx0, gx1]:
			_pylon(k, x, z_in, z_out, 1.0 if x > (gx0 + gx1) * 0.5 else -1.0)
		_portals(k, z_in, into)
		b.commit(k, root, "Towers%d" % bank, true, true)
	var g := Kit.new()
	for x: float in [gx0, gx1]:
		_truss(g, x)
	_bracing(g)
	b.commit(g, root, "Girder", true, true)
	return root

## A lattice card, cut-out, both sides: v runs a->b (v0 to v1, half the texture), the panels repeat along a->d.
func _card(k: Kit, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, v0: float, v1: float, panels: float, col: Color) -> void:
	k.quad4("lattice", a, bb, c, d, Vector2(0.0, v0), Vector2(0.0, v1), Vector2(panels * 0.25, v1), Vector2(panels * 0.25, v0), col, col, col, col)

## A pylon: four corner angles from its two feet (the quay leg at z_in, the river leg at z_out) up to the girder,
## lattice on all four faces, battens every few metres; the river leg on its concrete drum.
func _pylon(k: Kit, x: float, z_in: float, z_out: float, side: float) -> void:
	var splay := 0.45 * side
	var hx0 := 0.5
	var hx1 := 0.36
	var zc := (z_in + z_out) * 0.5
	var zt0 := zc - 0.85
	var zt1 := zc + 0.85
	var top := LOW
	# corners: [bottom, top] for (x-, z_in side), (x+, z_in side), (x+, z_out side), (x-, z_out side)
	var b_in := Vector3(x, 0.45, z_in)
	var b_out := Vector3(x + splay, water_y + 1.6, z_out)
	var t_in := Vector3(x, top, zt0 if z_out > z_in else zt1)
	var t_out := Vector3(x, top, zt1 if z_out > z_in else zt0)
	var corners: Array = []
	for c: Array in [[b_in, t_in, -1.0], [b_in, t_in, 1.0], [b_out, t_out, 1.0], [b_out, t_out, -1.0]]:
		var bot: Vector3 = c[0]
		var tp: Vector3 = c[1]
		var sx: float = c[2]
		corners.append([bot + Vector3(sx * hx0, 0, 0), tp + Vector3(sx * hx1, 0, 0)])
	for c: Array in corners:
		k.beam("steel", c[0], c[1], 0.24, 0.24, STEEL, STEEL_LIT)
	# the lattice faces: the two broad faces (facing -x and +x) and the two narrow ones
	var col := Color.WHITE
	for f: Array in [[0, 3], [1, 2], [0, 1], [3, 2]]:
		var ca: Array = corners[f[0]]
		var cb: Array = corners[f[1]]
		var width := ((ca[0] as Vector3).distance_to(cb[0]) + (ca[1] as Vector3).distance_to(cb[1])) * 0.5
		var height := (ca[0] as Vector3).distance_to(ca[1])
		_card(k, ca[0], cb[0], cb[1], ca[1], 0.0, 0.5, height / maxf(0.6, width * 0.75), col)
	# battens across the broad faces every 4 m, with snow on them
	var y := 4.0
	while y < top - 1.0:
		var t := y / top
		for f2: Array in [[0, 3], [1, 2]]:
			var pa: Vector3 = (corners[f2[0]][0] as Vector3).lerp(corners[f2[0]][1], t)
			var pb: Vector3 = (corners[f2[1]][0] as Vector3).lerp(corners[f2[1]][1], t)
			k.beam("steel", pa, pb, 0.16, 0.16, STEEL, STEEL_LIT)
			Snow.ridge(k, pa + Vector3(0, 0.08, 0), pb + Vector3(0, 0.08, 0), Vector3.UP, 0.16, 0.06, 0.02, rng, 0.3)
		y += 4.0
	# the river leg's drum, 4 m round in the books (here smaller), its top under snow; the quay leg's shoe
	k.push_tint(Color(0.66, 0.64, 0.6))
	k.lathe("stone", Vector3(b_out.x, water_y - 1.5, z_out), PackedVector2Array([Vector2(1.2, 0.0), Vector2(1.2, 3.1), Vector2(1.05, 3.25), Vector2(0.0, 3.27)]), 14, Color(0.3, 0.32, 0.3), Color(0.8, 0.8, 0.78))
	k.box("stone", Vector3(x, 0.22, z_in), Vector3(1.0, 0.45, 0.9), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	Snow.pillow(k, _circle(Vector2(b_out.x, z_out), 1.05, 10), water_y + 1.77, 0.18, 0.5, rng)
	# a cap where the pylon meets the girder
	k.box("steel", Vector3(x, top - 0.2, zc), Vector3(hx1 * 2.0 + 0.4, 0.4, 2.2), STEEL, STEEL_LIT)

static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in range(n):
		var a := -TAU * float(i) / float(n)
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p

## The portal girders between a bank's two pylons: one under the main girder and one lower down, both on the quay
## side of the pylons (the gondola's cables pass on the river side); lattice between their chords.
func _portals(k: Kit, z_in: float, into: float) -> void:
	for band: Vector2 in [Vector2(LOW - 3.4, LOW - 0.6), Vector2(13.0, 14.6)]:
		var t := band.y / LOW
		var z := lerpf(z_in, z_in + into * 1.6, t) - into * 0.15
		var a := gx0 + 0.45
		var bb := gx1 - 0.45
		for yy: float in [band.x, band.y]:
			k.beam("steel", Vector3(a, yy, z), Vector3(bb, yy, z), 0.18, 0.22, STEEL, STEEL_LIT)
		_card(k, Vector3(a, band.x, z), Vector3(a, band.y, z), Vector3(bb, band.y, z), Vector3(bb, band.x, z), 1.0, 0.5, (bb - a) / ((band.y - band.x) * 0.5), Color.WHITE)
		Snow.ridge(k, Vector3(a, band.y + 0.11, z), Vector3(bb, band.y + 0.11, z), Vector3.UP, 0.2, 0.08, 0.03, rng)
		# knee braces into the pylons
		k.beam("steel", Vector3(a, band.x - 2.0, z), Vector3(a + 2.0, band.x, z), 0.12, 0.12, STEEL, STEEL_LIT)
		k.beam("steel", Vector3(bb, band.x - 2.0, z), Vector3(bb - 2.0, band.x, z), 0.12, 0.12, STEEL, STEEL_LIT)

## One of the girder's two trusses, in the plane x: chords from bank to bank, the lattice between them, end posts.
func _truss(k: Kit, x: float) -> void:
	for yy: float in [LOW, HIGH]:
		k.beam("steel", Vector3(x, yy, z_north), Vector3(x, yy, z_south), 0.4, 0.42, STEEL, STEEL_LIT)
		Snow.ridge(k, Vector3(x, yy + 0.21, z_north), Vector3(x, yy + 0.21, z_south), Vector3.UP, 0.4, 0.12, 0.04, rng, 0.5, true)
	var length := z_south - z_north
	_card(k, Vector3(x, LOW, z_north), Vector3(x, HIGH, z_north), Vector3(x, HIGH, z_south), Vector3(x, LOW, z_south), 1.0, 0.5, length / ((HIGH - LOW) * 0.5), Color.WHITE)
	for z: float in [z_north, z_south]:
		k.beam("steel", Vector3(x, LOW - 0.2, z), Vector3(x, HIGH + 0.2, z), 0.36, 0.36, STEEL, STEEL_LIT)

## Cross members and diagonals between the two trusses, top and bottom; the trolley's rails along the top.
func _bracing(k: Kit) -> void:
	var n := int(round((z_south - z_north) / 2.6))
	for i: int in range(n + 1):
		var z := lerpf(z_north, z_south, float(i) / float(n))
		k.beam("steel", Vector3(gx0, HIGH, z), Vector3(gx1, HIGH, z), 0.14, 0.16, STEEL, STEEL_LIT)
		k.beam("steel", Vector3(gx0, LOW, z), Vector3(gx1, LOW, z), 0.14, 0.16, STEEL, STEEL_LIT)
		if i % 2 == 0: Snow.ridge(k, Vector3(gx0 + 0.2, HIGH + 0.08, z), Vector3(gx1 - 0.2, HIGH + 0.08, z), Vector3.UP, 0.16, 0.07, 0.03, rng)
		if i < n:
			var z1 := lerpf(z_north, z_south, float(i + 1) / float(n))
			k.beam("steel", Vector3(gx0, HIGH, z), Vector3(gx1, HIGH, z1), 0.07, 0.07, STEEL, STEEL_LIT)
			k.beam("steel", Vector3(gx1, LOW, z), Vector3(gx0, LOW, z1), 0.07, 0.07, STEEL, STEEL_LIT)
	for x: float in [gx0 + 1.4, gx1 - 1.4]:
		k.beam("steel", Vector3(x, HIGH + 0.2, z_north), Vector3(x, HIGH + 0.2, z_south), 0.14, 0.12, Color(0.3, 0.3, 0.3), Color(0.4, 0.4, 0.4))

## The gondola, its trolley up on the girder and the cables between, built in the gondola node's own space (its deck
## at y = 0 under the node). Returns the lamp spots on it (for boca.gd's halos).
func gondola(k: Kit, kd: Kit, half: Vector2) -> Array[Vector3]:
	var lamps: Array[Vector3] = []
	var wood := Color(0.55, 0.48, 0.4)
	# the deck: a steel frame under planks
	k.push_tint(wood)
	k.box("planks", Vector3(0, -0.08, 0), Vector3(half.x * 2.0, 0.16, half.y * 2.0), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	k.box("steel", Vector3(0, -0.32, 0), Vector3(half.x * 2.0 + 0.2, 0.32, half.y * 2.0 + 0.1), STEEL, STEEL_LIT)
	# railings along both sides, gates open at the ends
	for s: float in [-1.0, 1.0]:
		var x := s * (half.x - 0.05)
		for yy: float in [0.5, 1.05]:
			k.beam("steel", Vector3(x, yy, -half.y), Vector3(x, yy, half.y), 0.05, 0.05, STEEL, STEEL_LIT)
		var z := -half.y
		while z <= half.y + 0.01:
			k.beam("steel", Vector3(x, 0.0, z), Vector3(x, 1.08, z), 0.05, 0.05, STEEL, STEEL_LIT)
			z += half.y * 0.5
	# the operator's cabin on the east side, lit
	var cab := Vector3(half.x - 1.0, 0.0, 0.0)
	k.push_tint(Color(0.32, 0.42, 0.36))
	k.box("planks", cab + Vector3(0, 1.15, 0), Vector3(1.3, 2.3, 1.9), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.AUTO)
	k.pop_tint()
	k.push_tint(Color(0.7, 0.68, 0.64))
	k.box("corrugated", cab + Vector3(0, 2.38, 0), Vector3(1.6, 0.12, 2.2), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	Snow.box_top(k, cab + Vector3(0, 2.44, 0), Vector2(1.56, 2.16), 0.16, rng)
	# snow along the top rails (the deck itself is swept by the passengers' boots)
	for s2: float in [-1.0, 1.0]:
		var x2 := s2 * (half.x - 0.05)
		Snow.ridge(k, Vector3(x2, 1.08, -half.y), Vector3(x2, 1.08, half.y), Vector3.UP, 0.08, 0.05, 0.02, rng, 0.3, false)
	var lit := Color(1.0, 0.86, 0.62)
	for side: float in [-1.0, 1.0]:
		var zz := side * 0.96
		var p := cab + Vector3(0, 0, zz)
		kd.quad_rect("facade_lit", p + Vector3(0.45 * side, 1.25, 0), p + Vector3(-0.45 * side, 1.25, 0), p + Vector3(-0.45 * side, 1.95, 0), p + Vector3(0.45 * side, 1.95, 0), Houses.uv("tram_win_lit"), lit, lit)
	kd.quad_rect("facade_lit", cab + Vector3(-0.66, 1.25, 0.6), cab + Vector3(-0.66, 1.25, -0.6), cab + Vector3(-0.66, 1.95, -0.6), cab + Vector3(-0.66, 1.95, 0.6), Houses.uv("tram_win_lit"), lit, lit)
	# lamps on short posts at the four corners
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var at := Vector3(c.x * (half.x - 0.1), 0.0, c.y * (half.y - 0.1))
		k.beam("steel", at, at + Vector3(0, 2.0, 0), 0.06, 0.06, STEEL, STEEL_LIT)
		k.lathe("steel", at + Vector3(0, 2.0, 0), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.06, 0.14), Vector2(0.0, 0.16)]), 8, Color(0.2, 0.24, 0.22), Color(0.3, 0.34, 0.3))
		kd.lathe("bulb", at + Vector3(0, 1.94, 0), PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.08, 0.0), Vector2(0.08, 0.06)]), 8)
		lamps.append(at + Vector3(0, 1.9, 0))
	# the trolley on the girder: a frame on wheels across both trusses, its winding house in the middle
	var ty := HIGH + 0.35
	var tw := gx1 - gx0
	k.box("steel", Vector3(0, ty + 0.2, 0), Vector3(tw + 0.4, 0.3, 2.6), STEEL, STEEL_LIT)
	k.push_tint(Color(0.34, 0.38, 0.36))
	k.box("planks", Vector3(0, ty + 0.9, 0), Vector3(2.4, 1.1, 1.8), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	Snow.box_top(k, Vector3(0, ty + 1.45, 0), Vector2(2.36, 1.76), 0.14, rng)
	for s: float in [-1.0, 1.0]:
		for zz: float in [-0.9, 0.9]:
			k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * (tw * 0.5 - 1.4), ty, zz)))
			k.lathe("steel", Vector3(0, -0.06, 0), PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.25, 0.12), Vector2(0.0, 0.12)]), 10, STEEL, STEEL_LIT)
			k.pop()
	# the cables: a fan from the trolley down to each side of the deck
	for s: float in [-1.0, 1.0]:
		for i: int in range(6):
			var t := float(i) / 5.0
			var low := Vector3(s * (half.x - 0.1), 1.08, lerpf(-half.y + 0.1, half.y - 0.1, t))
			var high := Vector3(s * (tw * 0.5 - 0.6), LOW - 0.1, lerpf(-1.1, 1.1, t))
			k.beam("steel", low, high, 0.035, 0.035, Color(0.16, 0.17, 0.18), Color(0.2, 0.21, 0.22))
		# a stiff frame of hangers at the deck's ends
		for zz: float in [-half.y + 0.1, half.y - 0.1]:
			k.beam("steel", Vector3(s * (half.x - 0.1), 1.08, zz), Vector3(s * (tw * 0.5 - 0.6), LOW - 0.1, 0.0), 0.05, 0.05, STEEL, STEEL_LIT)
	return lamps

## The road bridge of 1940 (Puente Nicolás Avellaneda), downstream: two towers almost 50 m tall standing in the
## river near each bank (twin concrete shafts, their faces cut by deep recesses, a machinery house across the top with
## its windows lit, a red light on each corner), the steel lift span lowered between them at the deck's height, and the
## concrete approach viaducts running off over the city on their piers, a lamp every few metres. Seen from afar.
func road_bridge(at_x: float) -> void:
	var k := Kit.new()
	var conc := Color(0.82, 0.8, 0.76)
	var deck := 14.0
	var mid := (river.x + river.y) * 0.5
	var tz: Array[float] = [river.x + 1.8, river.y - 1.8]
	for z: float in tz:
		for x: float in [at_x - 5.6, at_x + 5.6]:
			k.push_tint(conc)
			k.box("stucco", Vector3(x, (46.0 + water_y) * 0.5, z), Vector3(3.2, 46.0 - water_y, 3.2), Color(0.55, 0.55, 0.58), Color.WHITE)
			k.pop_tint()
			# the deep recesses down each face
			for f: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				var side := Vector3(f.z, 0, -f.x)
				var pp := Vector3(x, 0.0, z) + f * 1.61
				k.quad("stucco", pp - side * 0.3 + Vector3(0, 3.0, 0), pp + side * 0.3 + Vector3(0, 3.0, 0), pp + side * 0.3 + Vector3(0, 42.0, 0), pp - side * 0.3 + Vector3(0, 42.0, 0), Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Color(0.3, 0.3, 0.34), Color(0.36, 0.36, 0.4))
		# the bracing between the shafts and the machinery house across the top
		k.push_tint(conc)
		k.box("stucco", Vector3(at_x, deck + 9.0, z), Vector3(11.2, 1.4, 2.4), Color(0.6, 0.6, 0.62), Color.WHITE)
		k.box("stucco", Vector3(at_x, 47.6, z), Vector3(15.0, 4.2, 4.4), Color(0.6, 0.6, 0.62), Color.WHITE)
		k.box("stucco", Vector3(at_x, 49.9, z), Vector3(15.6, 0.4, 5.0), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		Snow.box_top(k, Vector3(at_x, 50.1, z), Vector2(15.6, 5.0), 0.25, rng)
		for sgn: float in [-1.0, 1.0]:
			var face := z + sgn * 2.21
			for wx: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
				if rng.randf() < 0.7:
					var c := Vector3(at_x + wx, 47.6, face)
					k.quad("decobulb", c + Vector3(-0.6, -0.8, 0), c + Vector3(0.6, -0.8, 0), c + Vector3(0.6, 0.8, 0), c + Vector3(-0.6, 0.8, 0), Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		for cx: float in [-7.4, 7.4]:
			b._halo(Vector3(at_x + cx, 50.5, z), Color(1.0, 0.22, 0.12), 2.2)
	# the lift span, lowered: a deep steel truss from tower to tower at the deck, with its counterweight cables
	for x: float in [at_x - 4.8, at_x + 4.8]:
		for yy: float in [deck, deck + 5.0]:
			k.beam("steel", Vector3(x, yy, tz[0]), Vector3(x, yy, tz[1]), 0.5, 0.5, STEEL_LIT, STEEL_LIT * 1.3)
		_card(k, Vector3(x, deck, tz[0]), Vector3(x, deck + 5.0, tz[0]), Vector3(x, deck + 5.0, tz[1]), Vector3(x, deck, tz[1]), 1.0, 0.5, (tz[1] - tz[0]) / 2.5, Color.WHITE)
		Snow.ridge(k, Vector3(x, deck + 5.25, tz[0]), Vector3(x, deck + 5.25, tz[1]), Vector3.UP, 0.5, 0.12, 0.04, rng)
		for z2: float in tz:
			k.beam("steel", Vector3(x, deck + 5.0, z2), Vector3(x, 45.0, z2), 0.08, 0.08, Color(0.15, 0.15, 0.15), Color(0.2, 0.2, 0.2))
	k.box("steel", Vector3(at_x, deck - 0.2, mid), Vector3(10.0, 0.4, tz[1] - tz[0]), STEEL_LIT, STEEL_LIT)
	# the approach viaducts: a concrete deck on piers, running off over the city on both banks, lamps along both sides
	for dir: float in [-1.0, 1.0]:
		var z0 := tz[0] if dir < 0.0 else tz[1]
		var z1 := z0 + dir * 120.0
		var zc := (z0 + z1) * 0.5
		k.push_tint(conc)
		k.box("stucco", Vector3(at_x, deck - 0.6, zc), Vector3(11.0, 1.2, absf(z1 - z0)), Color(0.6, 0.6, 0.62), Color.WHITE)
		k.box("stucco", Vector3(at_x - 5.3, deck + 0.5, zc), Vector3(0.4, 1.0, absf(z1 - z0)), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.box("stucco", Vector3(at_x + 5.3, deck + 0.5, zc), Vector3(0.4, 1.0, absf(z1 - z0)), Color(0.7, 0.7, 0.7), Color.WHITE)
		var zp := z0 + dir * 9.0
		while absf(zp - z0) < 118.0:
			var foot := 0.0 if absf(zp - mid) > (river.y - river.x) * 0.5 else water_y
			k.box("stucco", Vector3(at_x, (deck - 1.2 + foot) * 0.5, zp), Vector3(7.0, deck - 1.2 - foot, 1.6), Color(0.45, 0.45, 0.48), Color(0.85, 0.85, 0.85))
			zp += dir * 13.0
		k.pop_tint()
		for sx: float in [-5.3, 5.3]:
			Snow.ridge(k, Vector3(at_x + sx, deck + 1.0, z0), Vector3(at_x + sx, deck + 1.0, z1), Vector3.UP, 0.4, 0.1, 0.03, rng)
			var zl := z0 + dir * 4.0
			while absf(zl - z0) < 118.0:
				k.box("steel", Vector3(at_x + sx, deck + 2.0, zl), Vector3(0.12, 3.0, 0.12), STEEL, STEEL_LIT)
				b._halo(Vector3(at_x + sx * 0.9, deck + 3.6, zl), Color(1.0, 0.74, 0.44), 2.0)
				zl += dir * 12.0
		Snow.pillow(k, Snow.rect_poly(Rect2(at_x - 5.0, minf(z0, z1), 10.0, absf(z1 - z0))), deck, 0.12, 1.5, rng)
	b.commit(k, b, "RoadBridge", true, false)
