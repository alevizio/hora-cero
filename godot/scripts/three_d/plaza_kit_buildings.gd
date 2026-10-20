extends RefCounted
## The Plaza de Mayo kit's buildings round the square besides the Casa Rosada (plaza_kit.gd builds through this): the
## Cabildo as restored in 1940, the Catedral Metropolitana, the Banco de la Nación, the ministry block on the south
## side, and Avenida de Mayo's fronts, which tile along any street edge. All in the local frame of plaza_kit.frame():
## x along the front left to right, y up, the front on z = 0, the building at z < 0.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")

var pk: RefCounted
var rng := RandomNumberGenerator.new()

func _init(owner: RefCounted) -> void:
	pk = owner
	rng.seed = 1810

func _face(o: Vector3, r: Vector3, w: float) -> RefCounted:
	return pk.face(o, r, w)

# ---------------------------------------------------------------------------------------------------------------
# The Cabildo
# ---------------------------------------------------------------------------------------------------------------
## The Cabildo as the 1940 restoration left it (the notes: five of its original eleven arches remain, three lost on
## the north to Avenida de Mayo in 1889 and three on the south to the diagonal in 1931; the tower rebuilt from
## replicas; red colonial tiles put back; iron bars at the windows; wooden doors and windows). White lime-washed: an
## arcade on the ground floor and a gallery of arches over it with its railing, `each_side` arches either side of the
## central bay (2 in 1958: five in all), the tower rising behind the central bay (a clock, a belfry, a small dome and
## its vane, from general knowledge), the hipped roof of red tiles with the snow lying in their channels. The arcade
## is lit by iron lanterns hung in its arches.
func cabildo(rect: Rect2, face: Vector3, each_side: int = 2, floodlit: float = 0.6) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var white := Color(0.96, 0.95, 0.91)
	var shade_w := Color(0.86, 0.85, 0.82)
	var green: Color = pk.hexc("2f4a34")
	var n := each_side * 2 + 1
	var bay := W / float(n)
	var G := 5.6
	var T := 10.8
	var f = pk.face(Vector3.ZERO, Vector3.RIGHT, W)
	# the ground floor: the arcade, its back wall with doors and barred windows, a stone floor, a beamed ceiling
	var deep := 3.4
	var g_opens: Array = []
	for i: int in range(n):
		var x := (float(i) + 0.5) * bay
		var w := bay * (0.66 if i != n / 2 else 0.7)
		g_opens.append({"x": x, "y": 0.0, "w": w, "h": 3.3 + w * 0.5, "arch": true, "reveal": 0.8, "moulding": false, "trim": white})
	pk.band(k, kd, f, "stucco", white, 0.0, W, 0.0, G, g_opens, 0.7, 0.95)
	# its lime wash weathered: damp rising up the piers, soot under the gallery's floor
	pk.grime_run(kd, f, pk.GRIME_DAMP, 0.0, W, 0.0, 1.3, g_opens, 0.8)
	pk.grime_run(kd, f, pk.GRIME_SOOT, 0.0, W, G - 1.1, G - 0.3, g_opens, 0.5)
	var back = pk.face(Vector3(0, 0, -deep), Vector3.RIGHT, W)
	var b_opens: Array = []
	for i: int in range(n):
		var x := (float(i) + 0.5) * bay
		var door := i % 2 == 0
		var l: bool = pk.is_lit() or i == n / 2
		if door: b_opens.append({"x": x, "y": 0.0, "w": 1.6, "h": 3.2, "cell": "door_cabildo", "key": pk.SOLID, "col": Color.WHITE, "reveal": 0.25})
		else: b_opens.append({"x": x, "y": 0.9, "w": 1.4, "h": 2.2, "cell": "reja_lit" if l else "reja_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.25})
	pk.band(k, kd, back, "stucco", shade_w, 0.0, W, 0.0, G - 0.4, b_opens, 0.7, 0.75)
	pk.grime_run(kd, back, pk.GRIME_BLOTCH, 0.0, W, 0.0, G - 0.4, b_opens, 0.45)
	pk.grime_run(kd, back, pk.GRIME_DAMP, 0.0, W, 0.0, 1.2, b_opens, 0.7)
	k.push_tint(Color(0.55, 0.53, 0.5))
	k.box("ashlar", Vector3(W * 0.5, 0.04, -deep * 0.5), Vector3(W, 0.08, deep), Color.WHITE, Color.WHITE)
	k.pop_tint()
	k.push_tint(Color(0.32, 0.24, 0.18))
	k.box("planks", Vector3(W * 0.5, G - 0.3, -deep * 0.5), Vector3(W, 0.12, deep), Color(0.6, 0.6, 0.6), Color(0.6, 0.6, 0.6), Vector2.ZERO, Kit.BEAM)
	for i: int in range(int(W / 1.2)):
		k.box("planks", Vector3(0.6 + float(i) * 1.2, G - 0.42, -deep * 0.5), Vector3(0.16, 0.2, deep), Color(0.6, 0.6, 0.6), Color(0.7, 0.7, 0.7), Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	for x: float in [0.0, W]:
		k.push_tint(white)
		k.box("render", Vector3(x + (0.2 if x < 1.0 else -0.2), G * 0.5, -deep * 0.5), Vector3(0.4, G, deep), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
	# lanterns hung in the arcade
	for i: int in range(n):
		var at := Vector3((float(i) + 0.5) * bay, G - 0.5, -deep * 0.45)
		_hanging_lantern(k, kd, at)
	# piers' bases: a dark plinth
	for i: int in range(n + 1):
		var x := float(i) * bay
		pk.fbox(k, f, "render", clampf(x, 0.3, W - 0.3), 0.35, 0.03, bay * 0.36, 0.7, 0.08, Color(0.62, 0.62, 0.6))
	# the floor of the gallery over the arcade, a string course
	pk.moulding(k, "render", PackedVector2Array([Vector2(0, 0), Vector2(W, 0)]), G - 0.3, pk.prof_string(0.32, 0.4), white)
	# the upper gallery: arches with their railing, the rooms' doors and windows at its back
	var u_opens: Array = []
	for i: int in range(n):
		var x := (float(i) + 0.5) * bay
		var w := bay * 0.6
		u_opens.append({"x": x, "y": G + 0.15, "w": w, "h": 2.7 + w * 0.5, "arch": true, "reveal": 0.6, "moulding": false, "trim": white})
	pk.band(k, kd, f, "stucco", white, 0.0, W, G, T, u_opens, 0.9, 0.9)
	pk.grime_run(kd, f, pk.GRIME_SOOT, 0.0, W, T - 1.2, T - 0.35, u_opens, 0.55)
	var deep2 := 2.8
	var back2 = pk.face(Vector3(0, 0, -deep2), Vector3.RIGHT, W)
	var b2: Array = []
	for i: int in range(n):
		var x := (float(i) + 0.5) * bay
		var l: bool = pk.is_lit()
		b2.append({"x": x, "y": G + 0.2, "w": 1.4, "h": 2.9, "cell": "reja_lit" if l else "reja_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.2})
	pk.band(k, kd, back2, "stucco", shade_w, 0.0, W, G, T - 0.3, b2, 0.8, 0.75)
	pk.grime_run(kd, back2, pk.GRIME_SOOT, 0.0, W, T - 1.5, T - 0.3, b2, 0.6)
	k.push_tint(Color(0.32, 0.24, 0.18))
	k.box("planks", Vector3(W * 0.5, T - 0.35, -deep2 * 0.5), Vector3(W, 0.12, deep2), Color(0.6, 0.6, 0.6), Color(0.6, 0.6, 0.6), Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	for x: float in [0.0, W]:
		k.push_tint(white)
		k.box("render", Vector3(x + (0.2 if x < 1.0 else -0.2), (G + T) * 0.5, -deep2 * 0.5), Vector3(0.4, T - G, deep2), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
	for o: Dictionary in u_opens:
		var x0 := float(o.x) - float(o.w) * 0.5
		var x1 := float(o.x) + float(o.w) * 0.5
		var a: Vector3 = f.at(x0, G + 0.15, -0.3)
		var b: Vector3 = f.at(x1, G + 0.15, -0.3)
		kd.quad_rect(pk.CUT, a, b, b + Vector3(0, 1.0, 0), a + Vector3(0, 1.0, 0), pk.uv_part("rail_ornate", 0.0, (x1 - x0) / 2.6), green, green * 1.2)
		k.push_tint(green)
		k.beam("planks", a + Vector3(0, 1.02, 0), b + Vector3(0, 1.02, 0), 0.08, 0.06, Color.WHITE, Color.WHITE)
		k.pop_tint()
		pk.ridge(k, a + Vector3(0, 1.06, 0), b + Vector3(0, 1.06, 0), Vector3.UP, 0.1, 0.05, 0.02)
		pk.ridge(k, f.at(x0, G + 0.15, -0.55), f.at(x1, G + 0.15, -0.55), Vector3.UP, 0.5, 0.1, 0.03)
	# the cornice under the eaves
	pk.moulding(k, "render", PackedVector2Array([Vector2(0, -D), Vector2(0, 0), Vector2(W, 0), Vector2(W, -D)]), T - 0.35, pk.prof_string(0.3, 0.35), white, false, false)
	# the ends and the back: the walls the demolitions left, plain, a few barred windows
	for sf: RefCounted in [pk.face(Vector3(0, 0, -D), Vector3(0, 0, 1), D), pk.face(Vector3(W, 0, 0), Vector3(0, 0, -1), D), pk.face(Vector3(W, 0, -D), Vector3.LEFT, W)]:
		pk.plain_wall(k, kd, sf, "stucco", white, 0.0, T, [Vector2(1.0, 2.4), Vector2(G + 0.6, 2.6)], 4.5, 1.3, "reja")
		pk.grime(kd, sf, pk.GRIME_DAMP, 0.0, sf.w, 0.0, 0.95, 0.8)
		pk.grime(kd, sf, pk.GRIME_SOOT, 0.0, sf.w, T - 1.0, T, 0.6)
	_tile_roof(k, Vector3(-0.6, T, 0.6), W + 1.2, D + 1.2, 0.48, Color(1.0, 0.96, 0.94))
	_cabildo_tower(k, kd, W * 0.5, -D * 0.42, bay * 0.98, T, white)
	pk.spill_at(Vector3(W * 0.5, 0, 0), Vector3(0, 0, 1), W * 0.4, 3.0, 0.7)
	pk.flood(k, floodlit, T + 14.0)
	var node: Node3D = pk.piece("Cabildo", pxf, k, kd)
	pk.end()
	return node

## An iron lantern hung from a ceiling on a short rod (the Cabildo's arcade).
func _hanging_lantern(k: Kit, kd: Kit, at: Vector3) -> void:
	k.push_tint(pk.IRON)
	k.beam("metal", at + Vector3(0, 0.4, 0), at + Vector3(0, 0.12, 0), 0.03, 0.03, Color.WHITE, Color.WHITE)
	k.lathe("metal", at + Vector3(0, 0.02, 0), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.06, 0.1), Vector2(0.0, 0.12)]), 4, Color.WHITE, Color.WHITE)
	k.pop_tint()
	pk.glow_lathe(kd, at + Vector3(0, -0.42, 0), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.15, 0.1), Vector2(0.15, 0.36), Vector2(0.18, 0.42), Vector2(0.0, 0.44)]), 4)
	var world: Vector3 = pk.xf * at
	pk.halo(world + Vector3(0, -0.2, 0), pk.LAMP, 0.9)
	pk.lights.append([world + Vector3(0, -0.3, 0), pk.LAMP, 0.5, 6.0])

## A hipped roof of colonial tiles over a rectangle (corner `o` front-left at the eaves' height, `w` along x, `d` back
## along -z), the ridge along the long side; snow in the tiles' channels (the shader), a line of it on the ridge and
## the hips, and a little along the eaves.
func _tile_roof(k: Kit, o: Vector3, w: float, d: float, pitch: float, tint: Color) -> void:
	var rise := d * 0.5 * pitch
	var inset := minf(d * 0.5, w * 0.5)
	var r0 := o + Vector3(inset, rise, -d * 0.5)
	var r1 := o + Vector3(w - inset, rise, -d * 0.5)
	var e0 := o
	var e1 := o + Vector3(w, 0, 0)
	var e2 := o + Vector3(w, 0, -d)
	var e3 := o + Vector3(0, 0, -d)
	k.push_tint(tint)
	k.quad_m("teja", e0, e1, r1, r0)
	k.quad_m("teja", e2, e3, r0, r1)
	k.tri("teja", e1, e2, r1, Vector2(0, 0), Vector2(d * Kit.UV_M, 0), Vector2(d * 0.5 * Kit.UV_M, rise * 2.0 * Kit.UV_M))
	k.tri("teja", e3, e0, r0, Vector2(0, 0), Vector2(d * Kit.UV_M, 0), Vector2(d * 0.5 * Kit.UV_M, rise * 2.0 * Kit.UV_M))
	k.pop_tint()
	# the eaves' soffit
	k.push_tint(Color(0.4, 0.3, 0.24))
	k.quad4("planks", e1 + Vector3(0, -0.02, 0), e0 + Vector3(0, -0.02, 0), e0 + Vector3(0.6, -0.02, -0.6), e1 + Vector3(-0.6, -0.02, -0.6), Vector2(0, 0), Vector2(w * Kit.UV_M, 0), Vector2(w * Kit.UV_M, 0.2), Vector2(0, 0.2), Color.WHITE, Color.WHITE, Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5))
	k.pop_tint()
	# ridge tiles and their snow
	k.push_tint(tint * 0.85)
	k.beam("teja", r0 + Vector3(0, 0.05, 0), r1 + Vector3(0, 0.05, 0), 0.3, 0.16, Color.WHITE, Color.WHITE)
	for pair: Array in [[e0, r0], [e1, r1], [e2, r1], [e3, r0]]:
		k.beam("teja", (pair[0] as Vector3) + Vector3(0, 0.05, 0), (pair[1] as Vector3) + Vector3(0, 0.05, 0), 0.26, 0.14, Color.WHITE, Color.WHITE)
	k.pop_tint()
	pk.ridge(k, r0 + Vector3(0, 0.14, 0), r1 + Vector3(0, 0.14, 0), Vector3.UP, 0.38, 0.12, 0.04)
	for pair: Array in [[e0, r0], [e1, r1], [e2, r1], [e3, r0]]:
		pk.ridge(k, (pair[0] as Vector3) + Vector3(0, 0.13, 0), (pair[1] as Vector3) + Vector3(0, 0.13, 0), Vector3.UP, 0.3, 0.1, 0.03)

## The Cabildo's tower behind the central bay: a square shaft with the clock, the belfry with an arch on each face and
## its bell, small urns at the corners, an eight-sided drum and a little dome with its weathervane.
func _cabildo_tower(k: Kit, kd: Kit, cx: float, cz: float, s: float, base: float, white: Color) -> void:
	var y0 := base - 0.5
	var y1 := base + 6.2
	var h := s * 0.5
	k.push_tint(white)
	k.box("render", Vector3(cx, (y0 + y1) * 0.5, cz), Vector3(s, y1 - y0, s), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	# pilasters at its corners, the clock on its front, a cornice
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		k.push_tint(white)
		k.box("render", Vector3(cx + c.x * (h - 0.2), (y0 + y1) * 0.5, cz + c.y * (h - 0.2)), Vector3(0.5, y1 - y0, 0.5), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
	var cy := y1 - 1.9
	var fz := cz + h + 0.27
	kd.quad_rect(pk.SOLID, Vector3(cx - 1.0, cy - 1.0, fz), Vector3(cx + 1.0, cy - 1.0, fz), Vector3(cx + 1.0, cy + 1.0, fz), Vector3(cx - 1.0, cy + 1.0, fz), pk.uv("clock"), Color.WHITE, Color.WHITE)
	k.push_tint(white * 0.95)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx, cy, fz - 0.15)))
	k.lathe("render", Vector3(0, -0.1, 0), PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.18, 0.0), Vector2(1.18, 0.2), Vector2(1.0, 0.24)]), 16, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop()
	k.pop_tint()
	var path := PackedVector2Array([Vector2(cx - h, cz - h), Vector2(cx - h, cz + h), Vector2(cx + h, cz + h), Vector2(cx + h, cz - h)])
	pk.moulding(k, "render", path, y1, pk.prof_string(0.35, 0.45), white, true)
	# the belfry: narrower, an arch on each face, the bell inside
	var s2 := s * 0.84
	var h2 := s2 * 0.5
	var b0 := y1 + 0.45
	var b1 := b0 + 4.2
	for e: int in range(4):
		var yaw := float(e) * PI * 0.5
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var r := Vector3(n.z, 0, -n.x)
		var o := Vector3(cx, 0, cz) + n * h2 - r * h2
		var bf = pk.face(o, r, s2)
		pk.band(k, kd, bf, "render", white, 0.0, s2, b0, b1, [{"x": s2 * 0.5, "y": b0 + 0.4, "w": s2 * 0.48, "h": 2.4 + s2 * 0.24, "arch": true, "reveal": 0.5, "trim": white}], 0.9, 0.9)
	k.push_tint(Color(0.12, 0.11, 0.1))
	k.box("render", Vector3(cx, (b0 + b1) * 0.5, cz), Vector3(s2 - 1.0, b1 - b0 - 0.2, s2 - 1.0), Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5))
	k.pop_tint()
	k.push_tint(Color(0.5, 0.42, 0.26))
	k.lathe("bronze", Vector3(cx, b0 + 2.0, cz), PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.55, 0.12), Vector2(0.4, 0.6), Vector2(0.3, 1.0), Vector2(0.0, 1.1)]), 10, Color.WHITE, Color.WHITE)
	k.pop_tint()
	var path2 := PackedVector2Array([Vector2(cx - h2, cz - h2), Vector2(cx - h2, cz + h2), Vector2(cx + h2, cz + h2), Vector2(cx + h2, cz - h2)])
	pk.moulding(k, "render", path2, b1, pk.prof_cornice(0.4, 0.55), white, true)
	# urns at the corners of the belfry's cornice
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var u := Vector3(cx + c.x * (h2 + 0.05), b1 + 0.55, cz + c.y * (h2 + 0.05))
		k.push_tint(white)
		k.lathe("render", u, PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.14, 0.1), Vector2(0.26, 0.35), Vector2(0.2, 0.6), Vector2(0.06, 0.75), Vector2(0.12, 0.85), Vector2(0.0, 1.0)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		pk.cone(k, u + Vector3(0, 0.62, 0), 0.18, 0.08)
	# the drum and the little dome, the vane
	var d0 := b1 + 0.55
	k.push_tint(white)
	k.lathe("render", Vector3(cx, d0, cz), PackedVector2Array([Vector2(h2 * 0.78, 0.0), Vector2(h2 * 0.78, 1.5), Vector2(h2 * 0.86, 1.62), Vector2(h2 * 0.86, 1.78)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var dome := PackedVector2Array()
	for q: int in range(7):
		var a := PI * 0.5 * float(q) / 6.0
		dome.append(Vector2(cos(a) * h2 * 0.8, 1.78 + sin(a) * h2 * 0.95))
	k.push_tint(Color(0.92, 0.9, 0.86))
	k.lathe("render", Vector3(cx, d0, cz), dome, 8, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var cap := PackedVector2Array()
	for q: int in range(5):
		var a := PI * 0.5 * (0.35 + 0.65 * float(q) / 4.0)
		cap.append(Vector2(cos(a) * (h2 * 0.8 + 0.06), 1.78 + sin(a) * (h2 * 0.95 + 0.06)))
	if pk.snow > 0.04: k.lathe("snow", Vector3(cx, d0, cz), cap, 8, Snow.WHITE, Snow.WHITE)
	var top := Vector3(cx, d0 + 1.78 + h2 * 0.95, cz)
	k.push_tint(pk.IRON)
	k.lathe("metal", top, PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.05, 0.3), Vector2(0.03, 1.6), Vector2(0.0, 1.7)]), 6, Color.WHITE, Color.WHITE)
	k.beam("metal", top + Vector3(-0.5, 1.25, 0), top + Vector3(0.6, 1.25, 0), 0.03, 0.18, Color.WHITE, Color.WHITE)
	k.pop_tint()

# ---------------------------------------------------------------------------------------------------------------
# The Catedral Metropolitana
# ---------------------------------------------------------------------------------------------------------------
## The Metropolitan Cathedral: its neoclassical front a portico of twelve Corinthian columns in a row on a broad flight
## of steps, under a triangular pediment whose sculpture is here only massing; the wall behind with its three doors;
## the long body behind under a low roof, and the dome on its drum over the crossing, set back, with its lantern. No
## bell towers (it has none). Grey-ochre stone. (The notes name it but give no detail: the form is from general
## knowledge of the building.)
func catedral(rect: Rect2, face: Vector3, floodlit: float = 0.6) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var stone: Color = pk.hexc("d6c9ae")
	var stone_d: Color = pk.hexc("b8aa90")
	# the steps across the whole front
	var ns := 8
	var step_d := 0.45
	for i: int in range(ns):
		var y := float(i + 1) * 0.2
		var z0 := -float(i) * step_d
		# (each step runs back under the portico to the wall with the doors, 1.4 + 6 m behind the top step)
		k.push_tint(stone_d)
		k.box("ashlar", Vector3(W * 0.5, y * 0.5, z0 - (float(ns) * step_d - float(i) * step_d + 7.4) * 0.5), Vector3(W, y, float(ns) * step_d - float(i) * step_d + 7.4), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		pk.ridge(k, Vector3(0.2, y, z0 - 0.22), Vector3(W - 0.2, y, z0 - 0.22), Vector3.UP, 0.4, 0.08, 0.03)
	var st := float(ns) * 0.2
	var zc := -float(ns) * step_d - 1.4
	# the twelve columns
	var xm := W * 0.04
	var sp := (W - xm * 2.0) / 11.0
	var rc := minf(0.8, sp * 0.22)
	var hc := minf(16.0, rc * 20.0)
	for i: int in range(12):
		pk.column(k, "ashlar", Vector3(xm + float(i) * sp, st, zc), hc, rc, stone, true, 14)
	var et := st + hc
	# the entablature over them, on the front and returning down the sides of the portico
	var zw := zc - 6.0
	k.push_tint(stone)
	k.box("ashlar", Vector3(W * 0.5, et + 0.9, (zc + 1.0 + zw) * 0.5), Vector3(W - xm * 2.0 + rc * 3.0, 1.8, zc + 1.0 - zw), Color(0.75, 0.75, 0.75), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	var ex0 := xm - rc * 1.6
	var ex1 := W - xm + rc * 1.6
	var ez := zc + rc * 1.6
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(ex0, zw), Vector2(ex0, ez), Vector2(ex1, ez), Vector2(ex1, zw)]), et + 1.8, pk.prof_cornice(0.6, 0.8), stone)
	# the pediment: its tympanum with the sculpture's massing, the raking cornices, the roof behind it
	var pb := et + 2.6
	var ph := W * 0.13
	var a := Vector3(ex0 + 0.4, pb, ez - 0.3)
	var b := Vector3(ex1 - 0.4, pb, ez - 0.3)
	var c := Vector3(W * 0.5, pb + ph, ez - 0.3)
	k.push_tint(stone)
	k.tri("ashlar", a, b, c, Vector2(0, 1), Vector2(W * Kit.UV_M, 1), Vector2(W * 0.5 * Kit.UV_M, 1.0 - ph * Kit.UV_M))
	k.pop_tint()
	var rr: Rect2 = pk.uv("relief")
	kd.tri(pk.SOLID, a + Vector3(1.4, 0.15, 0.05), b + Vector3(-1.4, 0.15, 0.05), c + Vector3(0, -0.7, 0.05), Vector2(rr.position.x, rr.end.y), rr.end, Vector2(rr.get_center().x, rr.position.y), stone * 1.1, stone * 1.1, stone * 1.1)
	k.push_tint(stone)
	k.beam("ashlar", a + Vector3(-0.5, 0, 0.35), c + Vector3(0, 0.4, 0.35), 0.9, 0.55, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.beam("ashlar", c + Vector3(0, 0.4, 0.35), b + Vector3(0.5, 0, 0.35), 0.9, 0.55, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop_tint()
	pk.ridge(k, a + Vector3(-0.5, 0.3, 0.35), c + Vector3(0, 0.7, 0.35), Vector3.UP, 0.8, 0.16, 0.05)
	pk.ridge(k, c + Vector3(0, 0.7, 0.35), b + Vector3(0.5, 0.3, 0.35), Vector3.UP, 0.8, 0.16, 0.05)
	var back_z := zw - 4.0
	k.push_tint(pk.hexc("8a8a86"))
	k.quad_m("slate", Vector3(ex0, pb, back_z), Vector3(ex0, pb, ez - 0.4), Vector3(W * 0.5, pb + ph, ez - 0.4), Vector3(W * 0.5, pb + ph, back_z))
	k.quad_m("slate", Vector3(ex1, pb, ez - 0.4), Vector3(ex1, pb, back_z), Vector3(W * 0.5, pb + ph, back_z), Vector3(W * 0.5, pb + ph, ez - 0.4))
	k.pop_tint()
	pk.slope(k, Vector3(ex0, pb + 0.02, back_z), Vector3(ex0, pb + 0.02, ez - 0.4), Vector3(W * 0.5, pb + ph + 0.02, back_z), Vector3(W * 0.5, pb + ph + 0.02, ez - 0.4), Vector3(-ph, W * 0.5 - ex0, 0).normalized(), 0.2, 0.2)
	pk.slope(k, Vector3(ex1, pb + 0.02, ez - 0.4), Vector3(ex1, pb + 0.02, back_z), Vector3(W * 0.5, pb + ph + 0.02, ez - 0.4), Vector3(W * 0.5, pb + ph + 0.02, back_z), Vector3(ph, ex1 - W * 0.5, 0).normalized(), 0.2, 0.2)
	# the portico's ceiling, and the wall behind the columns with its three doors and two niches
	k.push_tint(stone_d)
	k.box("ashlar", Vector3(W * 0.5, et - 0.1, (zc + zw) * 0.5), Vector3(W - xm * 2.0, 0.2, zc - zw), Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.6))
	k.pop_tint()
	var wall = pk.face(Vector3(0, 0, zw), Vector3.RIGHT, W)
	var opens: Array = []
	for i: int in range(3):
		var x := W * (0.3 + 0.2 * float(i))
		opens.append({"x": x, "y": st, "w": 3.2 if i == 1 else 2.6, "h": 7.0 if i == 1 else 5.8, "cell": "door_church", "key": pk.SOLID, "col": Color.WHITE, "reveal": 0.6})
	pk.band(k, kd, wall, "ashlar", stone, xm, W - xm, st, et, opens, 0.7, 0.75)
	# the stone's weather in the portico's shelter: damp at the wall's foot, soot under its ceiling
	pk.grime_run(kd, wall, pk.GRIME_DAMP, xm, W - xm, st, st + 1.4, opens, 0.7)
	pk.grime_run(kd, wall, pk.GRIME_SOOT, xm, W - xm, et - 1.6, et - 0.2, opens, 0.65)
	for o: Dictionary in opens:
		pk.fbox(k, wall, "ashlar", float(o.x), st + float(o.h) + 0.4, 0.15, float(o.w) + 1.0, 0.6, 0.3, stone)
		pk.ridge(k, wall.at(float(o.x) - float(o.w) * 0.5 - 0.5, st + float(o.h) + 0.7, 0.15), wall.at(float(o.x) + float(o.w) * 0.5 + 0.5, st + float(o.h) + 0.7, 0.15), Vector3.UP, 0.3, 0.08)
	if opens.size() > 0: pk.spill_at(Vector3(W * 0.5, 0, 0), Vector3(0, 0, 1), 4.0, 3.0, 0.25)
	# the body behind, under a low roof
	var bx0 := W * 0.08
	var bx1 := W * 0.92
	var bz0 := zw
	var bz1 := -D
	var bh := et + 1.0
	for sf: RefCounted in [pk.face(Vector3(bx0, 0, bz1), Vector3(0, 0, 1), bz0 - bz1), pk.face(Vector3(bx1, 0, bz0), Vector3(0, 0, -1), bz0 - bz1), pk.face(Vector3(bx1, 0, bz1), Vector3.LEFT, bx1 - bx0)]:
		var sopen: Array = []
		var nb := int(sf.w / 7.0)
		for i: int in range(nb):
			var l: bool = pk.is_lit() and rng.randf() < 0.4
			sopen.append({"x": (float(i) + 0.5) * sf.w / float(nb), "y": 6.0, "w": 2.2, "h": 7.0, "arch": true, "cell": "arch_lit2" if l else "arch_dark1", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() * 0.6 if l else Color.WHITE, "reveal": 0.5, "trim": stone})
		pk.band(k, kd, sf, "ashlar", stone, 0.0, sf.w, 0.0, bh, sopen, 0.7, 0.8)
		pk.grime(kd, sf, pk.GRIME_DAMP, 0.0, sf.w, 0.0, 1.5, 0.85)
		pk.grime_run(kd, sf, pk.GRIME_SOOT, 0.0, sf.w, bh - 1.3, bh, sopen, 0.7)
		for o: Dictionary in sopen: pk.grime(kd, sf, pk.GRIME_SILL, float(o.x) - 1.3, float(o.x) + 1.3, 3.8, 5.95, 0.6)
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(bx0, bz0), Vector2(bx0, bz1), Vector2(bx1, bz1), Vector2(bx1, bz0)]), bh, pk.prof_cornice(0.5, 0.7), stone, false)
	pk.roof_slab(k, pk.rect_poly(bx0, bz1, bx1, bz0), bh + 0.6, Color(0.5, 0.48, 0.45))
	# the dome over the crossing: a drum with pilasters and windows, the dome, its ribs, the lantern and its cross
	var dc := Vector3(W * 0.5, bh + 0.6, -D * 0.6)
	var rd := minf(9.0, W * 0.19)
	var dh := 7.0
	k.push_tint(stone)
	k.lathe("ashlar", dc, PackedVector2Array([Vector2(rd + 0.6, 0.0), Vector2(rd + 0.6, 1.2), Vector2(rd, 1.4), Vector2(rd, dh), Vector2(rd + 0.5, dh + 0.3), Vector2(rd + 0.5, dh + 0.8)]), 16, Color(0.75, 0.75, 0.75), Color.WHITE, Vector2.ZERO, PackedFloat32Array(), 6.0)
	k.pop_tint()
	pk.ridge(k, dc + Vector3(0, 1.2, 0), dc + Vector3(0.001, 1.2, 0), Vector3.UP, 0.1, 0.01)
	for i: int in range(16):
		var a2 := TAU * (float(i) + 0.5) / 16.0
		var dir := Vector3(cos(a2), 0, -sin(a2))
		var right := Vector3(-dir.z, 0, dir.x)
		var p := dc + dir * (rd + 0.02) + Vector3(0, 2.2, 0)
		if i % 2 == 0:
			var l2: bool = pk.is_lit() and rng.randf() < 0.5
			kd.quad_rect(pk.LIT if l2 else pk.SOLID, p - right * 0.75, p + right * 0.75, p + right * 0.75 + Vector3(0, 3.6, 0), p - right * 0.75 + Vector3(0, 3.6, 0), pk.uv("arch_lit0" if l2 else "arch_dark0"), pk.warm() * 0.6 if l2 else Color.WHITE, pk.warm() * 0.6 if l2 else Color.WHITE)
		else:
			k.push_tint(stone)
			k.box("ashlar", dc + dir * (rd + 0.2) + Vector3(0, (1.4 + dh) * 0.5, 0), Vector3(0.6, dh - 1.4, 0.6), Color(0.8, 0.8, 0.8), Color.WHITE)
			k.pop_tint()
	var dome := PackedVector2Array()
	for q: int in range(9):
		var a3 := PI * 0.5 * float(q) / 8.0
		dome.append(Vector2(cos(a3) * (rd + 0.2), dh + 0.8 + sin(a3) * rd * 1.05))
	var lead: Color = pk.hexc("7a8a84")
	k.push_tint(lead)
	k.lathe("metal", dc, dome, 16, Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, PackedFloat32Array(), 8.0)
	k.pop_tint()
	for i: int in range(8):
		var a4 := TAU * float(i) / 8.0
		var path := PackedVector3Array()
		for q: int in range(8):
			var t := PI * 0.5 * float(q) / 8.0
			path.append(dc + Vector3(cos(a4) * cos(t) * (rd + 0.32), dh + 0.8 + sin(t) * (rd * 1.05 + 0.12), -sin(a4) * cos(t) * (rd + 0.32)))
		k.push_tint(stone)
		k.tube("ashlar", path, 0.18, 4, Color.WHITE)
		k.pop_tint()
	var lt := dc + Vector3(0, dh + 0.8 + rd * 1.05, 0)
	k.push_tint(stone)
	k.lathe("ashlar", lt - Vector3(0, 0.3, 0), PackedVector2Array([Vector2(1.5, 0.0), Vector2(1.3, 0.3), Vector2(1.3, 2.4), Vector2(1.6, 2.6), Vector2(1.6, 2.8)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	k.push_tint(lead)
	k.lathe("metal", lt + Vector3(0, 2.5, 0), PackedVector2Array([Vector2(1.5, 0.0), Vector2(1.1, 0.6), Vector2(0.5, 1.2), Vector2(0.15, 1.5), Vector2(0.0, 1.6)]), 8, Color.WHITE, Color.WHITE)
	k.pop_tint()
	for i: int in range(8):
		var a5 := TAU * (float(i) + 0.5) / 8.0
		var p2 := lt + Vector3(cos(a5) * 1.31, 1.0, -sin(a5) * 1.31)
		var r2 := Vector3(sin(a5), 0, cos(a5))
		kd.quad_rect(pk.SOLID, p2 - r2 * 0.3, p2 + r2 * 0.3, p2 + r2 * 0.3 + Vector3(0, 1.1, 0), p2 - r2 * 0.3 + Vector3(0, 1.1, 0), pk.uv("arch_dark0"), Color.WHITE, Color.WHITE)
	k.push_tint(Color(0.5, 0.45, 0.3))
	var ct := lt + Vector3(0, 4.1, 0)
	k.beam("bronze", ct, ct + Vector3(0, 1.6, 0), 0.12, 0.12, Color.WHITE, Color.WHITE)
	k.beam("bronze", ct + Vector3(-0.45, 1.1, 0), ct + Vector3(0.45, 1.1, 0), 0.12, 0.12, Color.WHITE, Color.WHITE)
	k.pop_tint()
	pk.flood(k, floodlit, pb + ph)
	var node: Node3D = pk.piece("Catedral", pxf, k, kd)
	pk.end()
	return node

# ---------------------------------------------------------------------------------------------------------------
# The Banco de la Nación
# ---------------------------------------------------------------------------------------------------------------
## The Banco de la Nación Argentina on the square's north-east corner (Bustillo's building, finished in the fifties;
## the notes leave its date open): monumental and stripped classical in pale stone, a rusticated granite base, a
## colossal order of square piers with tall windows between them through three floors, a recessed entrance bay behind
## four great columns with the bronze doors lit, a heavy cornice, an attic storey, and over the banking hall the wide
## low dome that shows from above. (Form from general knowledge, simplified.)
func banco_nacion(rect: Rect2, face: Vector3) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var stone: Color = pk.hexc("d4d0c6")
	var granite: Color = pk.hexc("8e8a86")
	var B := 6.5
	var C := 22.5
	var A := 27.0
	var bay := 5.4
	var nb := maxi(5, int(round(W / bay)))
	if nb % 2 == 0: nb += 1
	bay = W / float(nb)
	var mid := nb / 2
	var portico := [mid - 2, mid - 1, mid, mid + 1, mid + 2] if nb >= 9 else [mid - 1, mid, mid + 1]
	var f = pk.face(Vector3.ZERO, Vector3.RIGHT, W)
	var recess := 4.0
	# the base: rusticated granite with the ground floor's windows behind bronze grilles
	var g_opens: Array = []
	for i: int in range(nb):
		if i in portico: continue
		var x := (float(i) + 0.5) * bay
		var l: bool = pk.is_lit()
		g_opens.append({"x": x, "y": 1.2, "w": 2.2, "h": 4.2, "cell": "door_bank_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() * 0.8 if l else Color.WHITE, "reveal": 0.5})
	var px0 := float(portico[0]) * bay
	var px1 := float(portico[portico.size() - 1] + 1) * bay
	pk.band(k, kd, f, "rustic", granite, 0.0, px0, 0.0, B, g_opens.filter(func(o: Dictionary) -> bool: return float(o.x) < px0), 0.6, 0.9)
	pk.band(k, kd, f, "rustic", granite, px1, W, 0.0, B, g_opens.filter(func(o: Dictionary) -> bool: return float(o.x) > px1), 0.6, 0.9)
	# the colossal order: piers and the windows between them, two tiers with spandrels
	var m_opens: Array = []
	for i: int in range(nb):
		if i in portico: continue
		var x := (float(i) + 0.5) * bay
		for tier: Vector2 in [Vector2(B + 1.0, 6.2), Vector2(B + 8.4, 6.0)]:
			var l: bool = pk.is_lit()
			m_opens.append({"x": x, "y": tier.x, "w": bay * 0.5, "h": tier.y, "cell": "modern_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.6})
	pk.band(k, kd, f, "ashlar", stone, 0.0, px0, B, C, m_opens.filter(func(o: Dictionary) -> bool: return float(o.x) < px0), 0.85, 0.9)
	pk.band(k, kd, f, "ashlar", stone, px1, W, B, C, m_opens.filter(func(o: Dictionary) -> bool: return float(o.x) > px1), 0.85, 0.9)
	for i: int in range(nb + 1):
		var x := float(i) * bay
		if x > px0 + 0.1 and x < px1 - 0.1: continue
		pk.fbox(k, f, "ashlar", clampf(x, 0.6, W - 0.6), (B + C) * 0.5, 0.25, 1.2, C - B, 0.5, stone, 0.8)
	for o: Dictionary in m_opens:
		var x0 := float(o.x) - float(o.w) * 0.5
		pk.ridge(k, f.at(x0, float(o.y), 0.05), f.at(x0 + float(o.w), float(o.y), 0.05), Vector3.UP, 0.2, 0.06)
		if float(o.y) > B + 2.0: pk.fbox(k, f, "ashlar", float(o.x), float(o.y) - 0.6, -0.2, float(o.w), 1.0, 0.1, stone * 0.85)
	pk.moulding(k, "rustic", PackedVector2Array([Vector2(0, -D), Vector2(0, 0), Vector2(px0, 0), Vector2(px0, -recess)]), B - 0.3, pk.prof_string(0.3, 0.4), granite)
	pk.moulding(k, "rustic", PackedVector2Array([Vector2(px1, -recess), Vector2(px1, 0), Vector2(W, 0), Vector2(W, -D)]), B - 0.3, pk.prof_string(0.3, 0.4), granite)
	# the entrance bay: set back, the bronze doors lit, four great columns in front of it, steps
	var rf = pk.face(Vector3(0, 0, -recess), Vector3.RIGHT, W)
	var d_opens: Array = []
	var nd := portico.size() + 1
	for i: int in range(nd):
		var x := px0 + (float(i) + 0.5) * (px1 - px0) / float(nd)
		d_opens.append({"x": x, "y": 1.0, "w": 2.6, "h": 6.4, "cell": "door_bank_lit", "key": pk.LIT, "col": pk.WARM * 0.85, "reveal": 0.6})
		d_opens.append({"x": x, "y": 9.5, "w": 2.6, "h": 9.0, "cell": "modern_lit", "key": pk.LIT, "col": pk.WARM * 0.7, "reveal": 0.6})
		pk.spill_at(Vector3(x, 0, 0), Vector3(0, 0, 1), 2.6, 5.0, 0.5)
	pk.band(k, kd, rf, "ashlar", stone * 0.9, px0, px1, 0.0, C, d_opens, 0.7, 0.8)
	for sf: RefCounted in [pk.face(Vector3(px0, 0, -recess), Vector3(0, 0, 1), recess), pk.face(Vector3(px1, 0, 0), Vector3(0, 0, -1), recess)]:
		pk.plain_wall(k, kd, sf, "ashlar", stone * 0.9, 0.0, C, [], 9.0, 1.0)
	for i: int in range(1, portico.size()):
		var x := px0 + float(i) * bay
		pk.column(k, "ashlar", Vector3(x, 1.0, -0.8), C - 1.0, 0.95, stone, false, 14)
	for i: int in range(5):
		k.push_tint(granite)
		k.box("ashlar", Vector3((px0 + px1) * 0.5, float(i) * 0.2 + 0.1, -recess * 0.5 + 0.3 - float(i) * 0.25), Vector3(px1 - px0, 0.2, recess + 0.6 - float(i) * 0.5), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
	k.push_tint(stone)
	k.box("ashlar", Vector3((px0 + px1) * 0.5, C + 0.6, -recess * 0.5), Vector3(px1 - px0, 1.2, recess), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	# the cornice, the attic with its small windows, its own cornice; the ends and the back
	var outline := PackedVector2Array([Vector2(0, -D), Vector2(0, 0), Vector2(W, 0), Vector2(W, -D)])
	pk.moulding(k, "ashlar", outline, C + 1.2, pk.prof_cornice(1.1, 1.3), stone)
	var at = pk.face(Vector3(0, 0, -0.6), Vector3.RIGHT, W)
	var a_opens: Array = []
	for i: int in range(nb):
		var l: bool = pk.is_lit() and rng.randf() < 0.5
		a_opens.append({"x": (float(i) + 0.5) * bay, "y": C + 3.0, "w": 1.4, "h": 1.4, "cell": "dormer_lit" if l else "dormer_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.3})
	pk.band(k, kd, at, "ashlar", stone, 0.0, W, C + 2.5, A, a_opens, 0.85, 0.9)
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(0, -D), Vector2(0, -0.6), Vector2(W, -0.6), Vector2(W, -D)]), A, pk.prof_string(0.45, 0.6), stone)
	for sf: RefCounted in [pk.face(Vector3(0, 0, -D), Vector3(0, 0, 1), D), pk.face(Vector3(W, 0, 0), Vector3(0, 0, -1), D), pk.face(Vector3(W, 0, -D), Vector3.LEFT, W)]:
		pk.plain_wall(k, kd, sf, "ashlar", stone, 0.0, A, [Vector2(B + 1.0, 6.2), Vector2(B + 8.4, 6.0)], bay, bay * 0.5, "modern")
	pk.roof_slab(k, pk.rect_poly(0.0, -D, W, -0.6), A + 0.6, Color(0.5, 0.5, 0.5))
	# the dome over the banking hall
	var dc := Vector3(W * 0.5, A + 0.6, -D * 0.5)
	var rd := minf(16.0, minf(W, D) * 0.34)
	k.push_tint(stone)
	k.lathe("ashlar", dc, PackedVector2Array([Vector2(rd + 0.8, 0.0), Vector2(rd + 0.8, 2.2), Vector2(rd + 0.3, 2.5)]), 24, Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, PackedFloat32Array(), 12.0)
	k.pop_tint()
	var dome := PackedVector2Array()
	for q: int in range(8):
		var a := PI * 0.5 * float(q) / 7.0
		dome.append(Vector2(cos(a) * (rd + 0.3), 2.5 + sin(a) * rd * 0.42))
	k.push_tint(pk.hexc("8a948e"))
	k.lathe("metal", dc, dome, 24, Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, PackedFloat32Array(), 12.0)
	k.pop_tint()
	k.push_tint(stone)
	k.lathe("ashlar", dc + Vector3(0, 2.5 + rd * 0.42 - 0.1, 0), PackedVector2Array([Vector2(2.4, 0.0), Vector2(2.4, 1.4), Vector2(2.7, 1.6), Vector2(1.2, 2.4), Vector2(0.0, 2.6)]), 12, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var node: Node3D = pk.piece("BancoNacion", pxf, k, kd)
	pk.end()
	return node

# ---------------------------------------------------------------------------------------------------------------
# The ministry block
# ---------------------------------------------------------------------------------------------------------------
## The ministry block on the south side of the square (in 1958 the Ministry of Finance's building of the late thirties
## faces it): ten storeys of stone, a rusticated two-storey base with its tall openings and the bronze doors, then
## piers rising unbroken between bays of steel windows over dark spandrels, a cornice, and a set-back top floor. Most
## windows are dark at night. (The bombing's scars are not modelled.)
func ministerios(rect: Rect2, face: Vector3, floors: int = 10) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var stone: Color = pk.hexc("e2d8c4")
	var base_c: Color = pk.hexc("b4ac9c")
	var B := 8.2
	var fh := 3.4
	var C := B + float(floors - 3) * fh
	var bay := 4.2
	var nb := maxi(3, int(round(W / bay)))
	bay = W / float(nb)
	var f = pk.face(Vector3.ZERO, Vector3.RIGHT, W)
	var mid := nb / 2
	var g_opens: Array = []
	for i: int in range(nb):
		var x := (float(i) + 0.5) * bay
		var door := absi(i - mid) <= (0 if nb % 2 == 1 else 1) and (nb % 2 == 1 or i != mid + 1)
		var l: bool = pk.is_lit()
		if door:
			g_opens.append({"x": x, "y": 0.6, "w": bay * 0.62, "h": 6.2, "cell": "door_bank_lit", "key": pk.LIT, "col": pk.WARM * 0.8, "reveal": 0.7})
			pk.spill_at(Vector3(x, 0, 0), Vector3(0, 0, 1), 2.4, 4.0, 0.45)
		else:
			g_opens.append({"x": x, "y": 1.4, "w": bay * 0.5, "h": 5.4, "cell": "modern_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.5})
	pk.band(k, kd, f, "rustic", base_c, 0.0, W, 0.0, B, g_opens, 0.65, 0.9)
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(0, -D), Vector2(0, 0), Vector2(W, 0), Vector2(W, -D)]), B - 0.25, pk.prof_string(0.4, 0.5), stone, true)
	var s_opens: Array = []
	for fl: int in range(floors - 3):
		for i: int in range(nb):
			var x := (float(i) + 0.5) * bay
			var l: bool = pk.is_lit() and rng.randf() < 0.55
			s_opens.append({"x": x, "y": B + 0.5 + float(fl) * fh, "w": bay * 0.5, "h": fh - 1.1, "cell": "modern_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.35})
	pk.band(k, kd, f, "ashlar", stone, 0.0, W, B, C, s_opens, 0.85, 0.9)
	for o: Dictionary in s_opens:
		var x0 := float(o.x) - float(o.w) * 0.5
		pk.fbox(k, f, "ashlar", float(o.x), float(o.y) - 0.3, 0.02, float(o.w) + 0.1, 0.6, 0.06, stone * 0.7)
		pk.ridge(k, f.at(x0, float(o.y), 0.04), f.at(x0 + float(o.w), float(o.y), 0.04), Vector3.UP, 0.12, 0.05)
	for i: int in range(nb + 1):
		pk.fbox(k, f, "ashlar", clampf(float(i) * bay, 0.4, W - 0.4), (B + C) * 0.5, 0.18, 0.8, C - B, 0.36, stone * 1.04, 0.85)
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(0, -D), Vector2(0, 0), Vector2(W, 0), Vector2(W, -D)]), C, pk.prof_cornice(0.8, 1.0), stone, true)
	# the set-back top floors
	var tf = pk.face(Vector3(1.5, 0, -2.0), Vector3.RIGHT, W - 3.0)
	var t_opens: Array = []
	for i: int in range(nb - 1):
		var l: bool = pk.is_lit() and rng.randf() < 0.4
		t_opens.append({"x": (float(i) + 0.5) * (W - 3.0) / float(nb - 1), "y": C + 1.5, "w": 1.5, "h": 2.2, "cell": "modern_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.25})
	pk.band(k, kd, tf, "ashlar", stone, 0.0, W - 3.0, C + 1.0, C + 4.6, t_opens, 0.85, 0.9)
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(1.5, -D + 2.0), Vector2(1.5, -2.0), Vector2(W - 1.5, -2.0), Vector2(W - 1.5, -D + 2.0)]), C + 4.6, pk.prof_string(0.3, 0.4), stone)
	# the attic's back and ends, plain, a few windows
	for af: RefCounted in [pk.face(Vector3(1.5, 0, -D + 2.0), Vector3(0, 0, 1), D - 4.0), pk.face(Vector3(W - 1.5, 0, -2.0), Vector3(0, 0, -1), D - 4.0), pk.face(Vector3(W - 1.5, 0, -D + 2.0), Vector3.LEFT, W - 3.0)]:
		pk.plain_wall(k, kd, af, "ashlar", stone * 0.95, C + 1.0, C + 4.6, [Vector2(C + 1.5, 2.2)], bay * 2.0, 1.5, "modern")
	pk.roof_slab(k, pk.rect_poly(0.0, -D, W, 0.0), C + 1.0, Color(0.5, 0.5, 0.5), 0.2)
	pk.roof_slab(k, pk.rect_poly(1.5, -D + 2.0, W - 1.5, -2.0), C + 5.0, Color(0.5, 0.5, 0.5), 0.2)
	# lift houses and water tanks on the roof
	for i: int in range(maxi(1, int(W / 30.0))):
		var hx := (float(i) + 0.5) * W / float(maxi(1, int(W / 30.0)))
		pk.fbox(k, pk.face(Vector3.ZERO, Vector3.RIGHT, W), "ashlar", hx, C + 6.2, -D * 0.5, 4.0, 2.4, 3.6, stone * 0.85)
		pk.box_top(k, Vector3(hx, C + 7.4, -D * 0.5), Vector2(4.0, 3.6), 0.14)
	# the ends, plain walls with their windows
	for sf: RefCounted in [pk.face(Vector3(0, 0, -D), Vector3(0, 0, 1), D), pk.face(Vector3(W, 0, 0), Vector3(0, 0, -1), D)]:
		var fls: Array = []
		for fl: int in range(floors - 1): fls.append(Vector2(1.4 + float(fl) * fh + (2.0 if fl > 0 else 0.0), fh - 1.1))
		pk.plain_wall(k, kd, sf, "ashlar", stone, 0.0, C + 1.0, fls, bay, bay * 0.5, "modern")
	# the back on the street behind, a front of its own: the rusticated base with its doors shut, the stone above with
	# its pilasters, sills and windows lit here and there; never a blank grid
	var bf = pk.face(Vector3(W, 0, -D), Vector3.LEFT, W)
	var b_g: Array = []
	for i: int in range(nb):
		var x := (float(i) + 0.5) * bay
		if i == mid: b_g.append({"x": x, "y": 0.0, "w": bay * 0.55, "h": 4.6, "cell": "door_panel", "key": pk.SOLID, "col": Color(0.7, 0.66, 0.6), "reveal": 0.6})
		else: b_g.append({"x": x, "y": 1.6, "w": bay * 0.44, "h": 4.4, "cell": "modern_dark", "key": pk.SOLID, "col": Color.WHITE, "reveal": 0.45})
	pk.band(k, kd, bf, "rustic", base_c, 0.0, W, 0.0, B, b_g, 0.65, 0.9)
	var b_s: Array = []
	for fl: int in range(floors - 3):
		for i: int in range(nb):
			var l: bool = pk.is_lit() and rng.randf() < 0.4
			b_s.append({"x": (float(i) + 0.5) * bay, "y": B + 0.5 + float(fl) * fh, "w": bay * 0.5, "h": fh - 1.1, "cell": "modern_lit" if l else "modern_dark", "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.35})
	pk.band(k, kd, bf, "ashlar", stone, 0.0, W, B, C, b_s, 0.85, 0.9)
	for i: int in range(0, nb + 1, 2):
		pk.fbox(k, bf, "ashlar", clampf(float(i) * bay, 0.4, W - 0.4), (B + C) * 0.5, 0.18, 0.8, C - B, 0.36, stone * 1.04, 0.85)
	for o: Dictionary in b_s:
		pk.fbox(k, bf, "ashlar", float(o.x), float(o.y) - 0.3, 0.02, float(o.w) + 0.1, 0.6, 0.06, stone * 0.7)
	var node: Node3D = pk.piece("Ministerios", pxf, k, kd)
	pk.end()
	return node

# ---------------------------------------------------------------------------------------------------------------
# Avenida de Mayo
# ---------------------------------------------------------------------------------------------------------------
## A run of Avenida de Mayo's fronts along the rect's street edge (the side `face` looks out of), cut into lots 11 to
## 19 m wide: Beaux-Arts and Art Nouveau buildings of four to six storeys under the avenue's 24 m cornice line (the
## notes), each with its mansard of slate and its dormers or oeils-de-boeuf, balconies with iron railings, an
## Art Nouveau bow window here and there; a domed corner turret at the ends when `corners`; at street level cafés with
## their gilded signs, striped awnings and lit windows, shops, a hotel's door. The names are trades only, no real
## business. Tiles along any street edge: call it again for the next stretch.
func avenida_de_mayo(rect: Rect2, face: Vector3, corners: bool = true, seed_value: int = 0) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = minf(fr[2], 16.0)
	pk.begin(pxf)
	if seed_value != 0: rng.seed = seed_value
	var k := Kit.new()
	var kd := Kit.new()
	var lots: Array[float] = [0.0]
	while lots[lots.size() - 1] < W - 0.1:
		var w := rng.randf_range(11.0, 19.0)
		if W - lots[lots.size() - 1] - w < 9.0: w = W - lots[lots.size() - 1]
		lots.append(minf(lots[lots.size() - 1] + w, W))
	var colours := ["e2d6bc", "d8c7a4", "cfc9bc", "e6dcc8", "d6b892", "c9bfae", "ddd0b6", "c8b49a"]
	var prev_h := 0.0
	for i: int in range(lots.size() - 1):
		var x0: float = lots[i]
		var x1: float = lots[i + 1]
		var floors := rng.randi_range(4, 6)
		var tint: Color = pk.hexc(colours[rng.randi() % colours.size()])
		var corner := corners and i == 0 and x1 - x0 > 12.0
		var h := _lot(k, kd, x0, x1, D, floors, tint, corner, i == 0)
		# the party wall where this lot rises over the one before
		if i > 0 and absf(h - prev_h) > 0.5:
			var xs := x0
			var lo := minf(h, prev_h)
			var hi := maxf(h, prev_h)
			var sf = pk.face(Vector3(xs, 0, 0), Vector3(0, 0, -1), D) if h > prev_h else pk.face(Vector3(xs, 0, -D), Vector3(0, 0, 1), D)
			k.push_tint(pk.hexc("b8a890"))
			k.quad4("render", sf.at(0, lo), sf.at(D, lo), sf.at(D, hi), sf.at(0, hi), Vector2(0, 0), Vector2(D * Kit.UV_M, 0), Vector2(D * Kit.UV_M, (hi - lo) * Kit.UV_M), Vector2(0, (hi - lo) * Kit.UV_M), Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE)
			k.pop_tint()
		prev_h = h
	# the ends of the run
	for sf: RefCounted in [pk.face(Vector3(0, 0, -D), Vector3(0, 0, 1), D), pk.face(Vector3(W, 0, 0), Vector3(0, 0, -1), D)]:
		pk.plain_wall(k, kd, sf, "render", pk.hexc("cfc4b0"), 0.0, 24.0, [Vector2(6.0, 2.0), Vector2(9.6, 2.0), Vector2(13.2, 2.0), Vector2(16.8, 2.0)], 4.5, 1.2)
	var node: Node3D = pk.piece("AvenidaDeMayo", pxf, k, kd)
	pk.end()
	return node

## One lot of the avenue: returns the height of its front's top (the mansard's ridge).
func _lot(k: Kit, kd: Kit, x0: float, x1: float, D: float, floors: int, tint: Color, corner: bool, first: bool) -> float:
	var f = pk.face(Vector3.ZERO, Vector3.RIGHT, x1)
	var w := x1 - x0
	var G := 5.2
	var fh := 3.5
	var H := minf(G + float(floors - 1) * fh, 24.0)
	fh = (H - G) / float(floors - 1)
	var nb := maxi(3, int(round(w / 3.3)))
	var bay := w / float(nb)
	var light := tint.lightened(0.12)
	var nouveau := rng.randf() < 0.35
	# the ground floor: a café, a shop or a hotel's door between them
	var g_opens: Array = []
	var kind := rng.randi() % 3
	var sign: String = ["sign_cafe", "sign_confiteria", "sign_bar"][rng.randi() % 3]
	for i: int in range(nb):
		var x := x0 + (float(i) + 0.5) * bay
		if i == nb / 2 and kind == 2:
			g_opens.append({"x": x, "y": 0.0, "w": bay * 0.6, "h": 3.6, "cell": "door_panel", "key": pk.SOLID, "col": Color.WHITE, "reveal": 0.4})
		else:
			g_opens.append({"x": x, "y": 0.5, "w": bay * 0.82, "h": 3.2, "cell": "cafe_lit" if kind == 0 else ("shop_lit" if rng.randf() < 0.6 else "cafe_glass"), "key": pk.LIT, "col": pk.warm(), "reveal": 0.3})
			pk.spill_at(Vector3(x, 0, 0), Vector3(0, 0, 1), bay * 0.8, 3.0, 0.6 if kind == 0 else 0.4)
	pk.band(k, kd, f, "rustic" if not nouveau else "render", tint * 0.9, x0, x1, 0.0, G, g_opens, 0.7, 0.9)
	# the fascia with its gilded sign, the striped awnings over the café
	var sw := minf(w - 1.0, 7.0)
	var sx := (x0 + x1) * 0.5
	pk.fquad(kd, f, pk.SOLID, sx - sw * 0.5, sx + sw * 0.5, 3.95, 3.95 + sw * 0.18, 0.08, pk.uv(sign))
	if kind != 2:
		var cell := "awning_cream" if rng.randf() < 0.5 else "awning_green"
		for o: Dictionary in g_opens:
			var ax0 := float(o.x) - float(o.w) * 0.5 - 0.1
			var ax1 := float(o.x) + float(o.w) * 0.5 + 0.1
			if absf(float(o.x) - sx) < sw * 0.5 + 0.5 and false: continue
			var a: Vector3 = f.at(ax0, 3.85, 0.02)
			var b: Vector3 = f.at(ax1, 3.85, 0.02)
			var out := Vector3(0, -0.6, 1.4)
			kd.quad_rect(pk.CUT, a + out, b + out, b, a, pk.uv(cell), Color(0.85, 0.85, 0.85), Color.WHITE)
			kd.quad_rect(pk.CUT, b + out + Vector3(0, -0.3, 0), a + out + Vector3(0, -0.3, 0), a + out, b + out, pk.uv_part(cell, 0.0, 1.0, 0.7, 1.0), Color(0.85, 0.85, 0.85), Color.WHITE)
			pk.slope(k, a + out * 0.95 + Vector3(0.05, 0.03, 0), b + out * 0.95 + Vector3(-0.05, 0.03, 0), a + Vector3(0.05, 0.04, 0), b + Vector3(-0.05, 0.04, 0), Vector3(0, 1.4, 0.6).normalized(), 0.08, 0.1)
	# the upper floors: windows in surrounds, balconies (a long one on the first floor)
	var u_opens: Array = []
	for fl: int in range(floors - 1):
		for i: int in range(nb):
			var x := x0 + (float(i) + 0.5) * bay
			var l: bool = pk.is_lit()
			u_opens.append({"x": x, "y": G + 0.5 + float(fl) * fh, "w": minf(1.3, bay * 0.5), "h": fh - 1.1, "cell": pk.window_cell(l), "key": pk.LIT if l else pk.SOLID, "col": pk.warm() if l else Color.WHITE, "reveal": 0.25, "fl": fl,
				"arch": fl == floors - 2 and nouveau})
	pk.band(k, kd, f, "render", tint, x0, x1, G, H, u_opens, 0.85, 0.85)
	for o: Dictionary in u_opens:
		var x := float(o.x)
		var ww := float(o.w)
		var y := float(o.y)
		if not bool(o.arch):
			pk.fbox(k, f, "render", x, y + float(o.h) + 0.14, 0.06, ww + 0.4, 0.2, 0.14, light)
			pk.ridge(k, f.at(x - ww * 0.5 - 0.2, y + float(o.h) + 0.24, 0.07), f.at(x + ww * 0.5 + 0.2, y + float(o.h) + 0.24, 0.07), Vector3.UP, 0.16, 0.06)
		if int(o.fl) > 0 and rng.randf() < 0.45:
			_iron_balcony(k, kd, f, x - ww * 0.5 - 0.25, x + ww * 0.5 + 0.25, y, light)
		else:
			pk.fbox(k, f, "render", x, y - 0.06, 0.06, ww + 0.3, 0.12, 0.18, light)
	_iron_balcony(k, kd, f, x0 + 0.4, x1 - 0.4, G + 0.5, light, 0.9)
	# string course, the cornice and the mansard
	pk.moulding(k, "render", PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0)]), G - 0.2, pk.prof_string(0.24, 0.32), light, false)
	pk.moulding(k, "render", PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0)]), H, pk.prof_cornice(0.7, 0.8), light, false)
	if nouveau:
		# an Art Nouveau bow window rising through the middle floors
		var bx := (x0 + x1) * 0.5
		var by0 := G + fh * 0.9
		var by1 := G + fh * float(mini(floors - 2, 3)) + 0.4
		k.push_tint(light)
		k.box("render", Vector3(bx, (by0 + by1) * 0.5, 0.55), Vector3(2.8, by1 - by0, 1.1), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		var fl2 := 0
		var yy := by0 + 0.4
		while yy + 2.0 < by1:
			var l: bool = pk.is_lit()
			kd.quad_rect(pk.LIT if l else pk.SOLID, Vector3(bx - 1.1, yy, 1.11), Vector3(bx + 1.1, yy, 1.11), Vector3(bx + 1.1, yy + 2.0, 1.11), Vector3(bx - 1.1, yy, 1.11) + Vector3(0, 2.0, 0), pk.uv(pk.window_cell(l)), pk.warm() if l else Color.WHITE, pk.warm() if l else Color.WHITE)
			yy += fh
			fl2 += 1
		pk.box_top(k, Vector3(bx, by1, 0.55), Vector2(2.8, 1.1), 0.12)
	# the back of the lot (a light well's wall, seen from the next street)
	pk.plain_wall(k, kd, pk.face(Vector3(x1, 0, -D), Vector3.LEFT, w), "render", tint * 0.92, 0.0, H + 0.8, [Vector2(1.2, 2.2), Vector2(G + 0.6, 2.2), Vector2(G + 0.6 + fh, 2.2), Vector2(G + 0.6 + fh * 2.0, 2.2)], 3.6, 1.1)
	var mh := rng.randf_range(3.0, 4.2)
	var base: PackedVector2Array = pk.rect_poly(x0 + 0.3, -D + 0.5, x1 - 0.3, -0.4)
	var top := Snow.inset(base, 1.6)
	var slate := Color(0.36, 0.38, 0.42) if rng.randf() < 0.7 else Color(0.42, 0.4, 0.38)
	k.push_tint(slate)
	for i: int in range(4):
		var j := (i + 1) % 4
		k.quad_m("slate", Vector3(base[i].x, H + 0.8, base[i].y), Vector3(base[j].x, H + 0.8, base[j].y), Vector3(top[j].x, H + 0.8 + mh, top[j].y), Vector3(top[i].x, H + 0.8 + mh, top[i].y))
	k.pop_tint()
	pk.roof_slab(k, top, H + 0.8 + mh, Color(0.4, 0.4, 0.42), 0.18)
	var nd := maxi(1, int(w / 4.5))
	var round_dormers := rng.randf() < 0.5
	for i: int in range(nd):
		var x := x0 + (float(i) + 0.5) * w / float(nd)
		var yb := H + 1.4
		var zf := -0.4 - 0.55
		var l: bool = pk.is_lit()
		k.push_tint(light)
		k.box("render", Vector3(x, yb + 0.8, zf - 0.4), Vector3(1.4, 1.6, 1.0), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		if round_dormers:
			kd.quad_rect(pk.LIT if l else pk.SOLID, Vector3(x - 0.45, yb + 0.4, zf + 0.11), Vector3(x + 0.45, yb + 0.4, zf + 0.11), Vector3(x + 0.45, yb + 1.3, zf + 0.11), Vector3(x - 0.45, yb + 1.3, zf + 0.11), pk.uv("oculus_lit" if l else "oculus_dark"), pk.warm() if l else Color.WHITE, pk.warm() if l else Color.WHITE)
		else:
			kd.quad_rect(pk.LIT if l else pk.SOLID, Vector3(x - 0.42, yb + 0.15, zf + 0.11), Vector3(x + 0.42, yb + 0.15, zf + 0.11), Vector3(x + 0.42, yb + 1.35, zf + 0.11), Vector3(x - 0.42, yb + 1.35, zf + 0.11), pk.uv("dormer_lit" if l else "dormer_dark"), pk.warm() if l else Color.WHITE, pk.warm() if l else Color.WHITE)
		pk.box_top(k, Vector3(x, yb + 1.6, zf - 0.4), Vector2(1.5, 1.05), 0.14)
	# chimneys on the mansard
	for i: int in range(maxi(1, int(w / 8.0))):
		var c := Vector3(rng.randf_range(x0 + 2.0, x1 - 2.0), H + 0.8 + mh, rng.randf_range(-D + 3.0, -3.5))
		k.push_tint(pk.hexc("b8a48c"))
		k.box("render", c + Vector3(0, 0.7, 0), Vector3(0.7, 1.4, 1.4), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		pk.box_top(k, c + Vector3(0, 1.4, 0), Vector2(0.75, 1.45), 0.12)
	if corner:
		# a domed turret over the corner, on its drum, with oculi and a lantern
		var cx := x0 + 2.6 if first else x1 - 2.6
		var c2 := Vector3(cx, H + 0.8, -2.6)
		k.push_tint(light)
		k.lathe("render", c2, PackedVector2Array([Vector2(2.3, 0.0), Vector2(2.3, 2.6), Vector2(2.55, 2.8), Vector2(2.55, 3.1)]), 12, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		for q: int in range(6):
			var a := TAU * (float(q) + 0.5) / 6.0
			var dir := Vector3(cos(a), 0, -sin(a))
			var rt := Vector3(-dir.z, 0, dir.x)
			var p := c2 + dir * 2.32 + Vector3(0, 1.3, 0)
			var l: bool = pk.is_lit()
			kd.quad_rect(pk.LIT if l else pk.SOLID, p - rt * 0.45 - Vector3(0, 0.45, 0), p + rt * 0.45 - Vector3(0, 0.45, 0), p + rt * 0.45 + Vector3(0, 0.45, 0), p - rt * 0.45 + Vector3(0, 0.45, 0), pk.uv("oculus_lit" if l else "oculus_dark"), pk.warm() if l else Color.WHITE, pk.warm() if l else Color.WHITE)
		var dome := PackedVector2Array()
		for q: int in range(8):
			var a := PI * 0.5 * float(q) / 7.0
			dome.append(Vector2(cos(a) * 2.4, 3.1 + sin(a) * 3.0))
		k.push_tint(Color(0.38, 0.4, 0.44))
		k.lathe("slate", c2, dome, 12, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.lathe("metal", c2 + Vector3(0, 6.0, 0), PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.9), Vector2(0.65, 1.0), Vector2(0.1, 1.6), Vector2(0.03, 2.4), Vector2(0.0, 2.5)]), 8, Color.WHITE, Color.WHITE)
		k.pop_tint()
	return H + 0.8 + mh

## An iron balcony on a face: the stone slab under its snow, the railing round it (the atlas's ornate cut-out).
func _iron_balcony(k: Kit, kd: Kit, f: RefCounted, x0: float, x1: float, y: float, slab: Color, depth: float = 0.6) -> void:
	pk.fbox(k, f, "render", (x0 + x1) * 0.5, y - 0.09, depth * 0.5, x1 - x0, 0.18, depth, slab, 0.7)
	pk.pillow(k, pk.face_poly(f, x0 + 0.04, x1 - 0.04, 0.04, depth - 0.04), y, 0.1, 0.18)
	var iron := Color(0.12, 0.13, 0.13)
	var h := 1.0
	var a: Vector3 = f.at(x0 + 0.03, y, depth - 0.04)
	var b: Vector3 = f.at(x1 - 0.03, y, depth - 0.04)
	var length := a.distance_to(b)
	var s := 0.0
	while s < length - 0.01:
		var t := minf(2.6, length - s)
		var p0 := a.lerp(b, s / length)
		var p1 := a.lerp(b, (s + t) / length)
		kd.quad_rect(pk.CUT, p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), pk.uv_part("rail_ornate", 0.0, t / 2.6), iron, iron * 1.3)
		s += t
	for x: float in [x0 + 0.03, x1 - 0.03]:
		kd.quad_rect(pk.CUT, f.at(x, y, 0.0), f.at(x, y, depth - 0.04), f.at(x, y + h, depth - 0.04), f.at(x, y + h, 0.0), pk.uv_part("rail_ornate", 0.0, depth / 2.6), iron, iron * 1.3)
	k.push_tint(iron)
	k.beam("metal", a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.05, 0.04, Color.WHITE, Color.WHITE)
	k.pop_tint()
	pk.ridge(k, a + Vector3(0, h + 0.02, 0), b + Vector3(0, h + 0.02, 0), Vector3.UP, 0.07, 0.04, 0.012, 0.3)
