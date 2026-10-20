extends RefCounted
## The small things that make the square and its streets Buenos Aires on a snowy night in 1958 (plaza.gd builds them
## after the kit): the enamel plates with the streets' names on iron posts at the corners (Rivadavia, Hipólito
## Yrigoyen, Bolívar, Balcarce, Defensa, Reconquista, San Martín, 25 de Mayo, Avenida de Mayo, Perú, the Diagonales);
## the kiosks' evening papers (their names invented) and their fascias painted by a fileteador; a second kiosk on the
## avenue; the café tables left out on the avenue's pavements under the snow; the traffic policeman's podium in the
## middle of the avenue at Perú, empty; the Línea A's round plates over the subte's stairs; the works hoarding across
## Hipólito Yrigoyen at Bolívar (the street beyond is shut) and the wall of the Cabildo's patio behind it.
##
## Two meshes: the solid things in the city's material (plaza_city.gdshader: its render colours, its snow on whatever
## faces up), the plates, papers and paintings in the second atlas (plaza/plaza_b.png, plaza_detail.gdshader); and the
## kiosks' dressings each a mesh of their own, so they fade with their kiosk.

const PlazaCity = preload("res://scripts/three_d/plaza_city.gd")
const DetailShader := preload("res://shaders/plaza_detail.gdshader")
const UP := Vector3.UP
const ATLAS_B := Vector2(1024.0, 640.0)
## The second atlas's cells (tools/gen_plaza_textures.py ATLAS_B).
const CELLS := {
	"st_rivadavia": [0, 0, 256, 64], "st_yrigoyen": [256, 0, 256, 64], "st_bolivar": [512, 0, 256, 64], "st_balcarce": [768, 0, 256, 64],
	"st_defensa": [0, 64, 256, 64], "st_reconquista": [256, 64, 256, 64], "st_25mayo": [512, 64, 256, 64], "st_avmayo": [768, 64, 256, 64],
	"st_diagnorte": [0, 128, 256, 64], "st_diagsur": [256, 128, 256, 64], "st_sanmartin": [512, 128, 256, 64], "st_peru": [768, 128, 256, 64],
	"paper0": [0, 192, 160, 208], "paper1": [160, 192, 160, 208], "paper2": [320, 192, 160, 208], "paper3": [480, 192, 160, 208],
	"filete_fascia": [640, 192, 384, 96], "filete_strip": [640, 288, 384, 48], "subte_linea": [640, 336, 384, 64],
	"poster_tango": [0, 400, 128, 192], "poster_cine": [128, 400, 128, 192], "filete_bus_rear": [256, 400, 256, 128],
	"obras": [256, 528, 256, 64], "disc_a": [512, 400, 128, 128], "hoarding": [640, 400, 384, 192], "podium": [512, 528, 128, 64],
}
## The detail shader's uses (UV2.x): solid (front faces), cut-out and two-sided, lit from inside, glowing.
const SOLID := 0.0
const CUT := 1.0
const LIT := 2.0
const GLOW := 3.0

var city: PlazaCity
var parent: Node3D
var detail_material: ShaderMaterial
var solid := PlazaCity.Batch.new()
var decal := PlazaCity.Batch.new()
var rng := RandomNumberGenerator.new()
## The nodes made, for the plaza's snow and the tests.
var nodes: Array[MeshInstance3D] = []

func _init(p_parent: Node3D, p_city: PlazaCity, macro: Texture2D) -> void:
	parent = p_parent
	city = p_city
	rng.seed = 1958061
	detail_material = ShaderMaterial.new()
	detail_material.shader = DetailShader
	detail_material.set_shader_parameter("atlas", load("res://assets/tex/plaza/plaza_b.png"))
	detail_material.set_shader_parameter("macro_tex", macro)

static func uv(cell: String) -> Rect2:
	var c: Array = CELLS[cell]
	return Rect2(Vector2(float(c[0]), float(c[1])) / ATLAS_B, Vector2(float(c[2]), float(c[3])) / ATLAS_B)

## A flat picture of the second atlas: centred at `at` (its foot's middle), facing `n` (horizontal), `size` wide and
## high; both faces when `two` (a plate on a post seen from either side), else its front only.
func plate(batch: PlazaCity.Batch, at: Vector3, n: Vector3, size: Vector2, r: Rect2, mode: float = SOLID, two: bool = true, col: Color = Color.WHITE) -> void:
	var right := UP.cross(n).normalized()
	var a := at - right * size.x * 0.5
	var b := at + right * size.x * 0.5
	var uvs: Array = [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)]
	batch.quad(a, b, b + UP * size.y, a + UP * size.y, [n], uvs, col, Vector2(mode, 0.0))
	if two and mode != CUT:
		var a2 := at + right * size.x * 0.5 - n * 0.006
		var b2 := at - right * size.x * 0.5 - n * 0.006
		batch.quad(a2, b2, b2 + UP * size.y, a2 + UP * size.y, [-n], uvs, col, Vector2(mode, 0.0))

## Solid geometry in the city's material (its builders, on this mesh).
func _solid() -> void:
	city._batch = solid

# ---------------------------------------------------------------------------------------------------------------
# The street plates
# ---------------------------------------------------------------------------------------------------------------
## An iron post at a corner with its enamel plates at the top, each along its street (`signs`: [cell, the street's
## direction on the ground]); the plates read from both sides.
func corner_post(at: Vector2, signs: Array) -> void:
	_solid()
	var iron := Color(0.11, 0.12, 0.12, 0.03)
	city._lathe(Vector3(at.x, 0.0, at.y), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.06, 0.3), Vector2(0.045, 0.34), Vector2(0.04, 2.95), Vector2(0.0, 3.05)]), 6, PlazaCity.KIND_IRON, iron)
	var y := 2.42
	for s: Array in signs:
		var along: Vector2 = (s[1] as Vector2).normalized()
		var n := Vector3(-along.y, 0.0, along.x)
		var centre := Vector3(at.x, y, at.y) + Vector3(along.x, 0.0, along.y) * 0.5
		plate(decal, centre, n, Vector2(0.9, 0.225), uv(str(s[0])))
		# its bracket to the post
		city._beam(Vector3(at.x, y + 0.11, at.y), centre + Vector3(along.x, 0, along.y) * 0.46 + UP * 0.11, 0.03, iron)
		y -= 0.27

# ---------------------------------------------------------------------------------------------------------------
# Kiosks
# ---------------------------------------------------------------------------------------------------------------
## A kiosk of the kit dressed (its transform as the kit placed it; its sizes): the fileteado fascia over its own on the
## front, a band of ornament along its eaves, the evening papers pegged across its front and down its sides. A mesh
## of its own under the kiosk, returned (to fade with it).
func kiosk_dressing(kiosk: Node3D) -> MeshInstance3D:
	var b := PlazaCity.Batch.new()
	var xf := kiosk.transform
	var w := 2.4
	var d := 1.7
	var h := 2.3
	var fwd := xf.basis.z.normalized()
	var right := xf.basis.x.normalized()
	var o := xf.origin
	# the fascia on the board over the front
	plate(b, o + fwd * (d * 0.5 + 0.375) + UP * (h + 0.32), fwd, Vector2(w * 0.88, 0.46), uv("filete_fascia"), SOLID, false)
	# ornament along the eaves, front and sides
	var eave := uv("filete_strip")
	for k: int in range(3):
		var x := (float(k) - 1.0) * (w + 0.7) / 3.0
		plate(b, o + fwd * ((d + 0.7) * 0.5 + 0.012) + right * x + UP * (h - 0.0), fwd, Vector2((w + 0.7) / 3.0, 0.16), eave, CUT, false)
	for side: float in [-1.0, 1.0]:
		for k: int in range(2):
			var z := (float(k) - 0.5) * (d + 0.7) / 2.0
			plate(b, o + right * side * ((w + 0.7) * 0.5 + 0.012) + fwd * z + UP * h, right * side, Vector2((d + 0.7) / 2.0, 0.16), eave, CUT, false)
	# the papers: four across the front under the counter, two down each side
	for k: int in range(4):
		var x := (float(k) - 1.5) * 0.56
		plate(b, o + fwd * (d * 0.5 + 0.02) + right * x + UP * 0.28, fwd, Vector2(0.5, 0.65), uv("paper%d" % ((k + kiosk.get_instance_id()) % 4)), SOLID, false, Color(0.92, 0.9, 0.86))
	for side: float in [-1.0, 1.0]:
		for k: int in range(2):
			var z := (float(k) - 0.5) * 0.62
			plate(b, o + right * side * (w * 0.5 + 0.02) + fwd * z + UP * 1.32, right * side, Vector2(0.48, 0.62), uv("paper%d" % ((k * 2 + (1 if side > 0.0 else 0)) % 4)), SOLID, false, Color(0.92, 0.9, 0.86))
	var node := b.commit(kiosk, null, "Dressing")
	if node == null: return null
	node.transform = xf.affine_inverse()
	node.mesh.surface_set_material(0, detail_material.duplicate())
	nodes.append(node)
	return node

# ---------------------------------------------------------------------------------------------------------------
# The avenue's cafés, the policeman's podium
# ---------------------------------------------------------------------------------------------------------------
## A café's table left out on the pavement: a round marble top on its iron foot, two bentwood chairs pushed in, the snow
## on the top and the seats.
func cafe_table(at: Vector2, yaw: float) -> void:
	_solid()
	var marble := Color(0.86, 0.84, 0.8, 0.01)
	var iron := Color(0.1, 0.1, 0.1, 0.01)
	var wood := Color(0.24, 0.15, 0.1, 0.01)
	city._lathe(Vector3(at.x, 0.0, at.y), PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.2, 0.04), Vector2(0.04, 0.1), Vector2(0.035, 0.7), Vector2(0.0, 0.7)]), 6, PlazaCity.KIND_IRON, iron)
	city._lathe(Vector3(at.x, 0.7, at.y), PackedVector2Array([Vector2(0.33, 0.0), Vector2(0.33, 0.035), Vector2(0.0, 0.035)]), 10, PlazaCity.KIND_PARTY, marble)
	for side: float in [-1.0, 1.0]:
		var dir := Vector2(cos(yaw), sin(yaw)) * side
		var c := at + dir * 0.48
		var seat := Vector3(c.x, 0.46, c.y)
		city._box(seat, Vector3(0.38, 0.04, 0.38), PlazaCity.KIND_PARTY, wood, 0.3)
		var back := Vector3(c.x + dir.x * 0.19, 0.72, c.y + dir.y * 0.19)
		city._box(back, Vector3(0.06 if absf(dir.x) > 0.5 else 0.36, 0.48, 0.36 if absf(dir.x) > 0.5 else 0.06), PlazaCity.KIND_PARTY, wood, 0.3)
		for lx: float in [-0.16, 0.16]:
			for lz: float in [-0.16, 0.16]:
				city._beam(Vector3(c.x + lx, 0.0, c.y + lz), Vector3(c.x + lx, 0.45, c.y + lz), 0.025, wood)

## The traffic policeman's podium in the middle of a crossing, empty on this night: a drum painted white with a black
## band (the second atlas), a round iron sunshade over it on its pole, snow on the shade and the drum.
func podium(at: Vector2) -> void:
	_solid()
	city._lathe(Vector3(at.x, 0.0, at.y), PackedVector2Array([Vector2(0.95, 0.0), Vector2(0.95, 0.14), Vector2(0.0, 0.14)]), 12, PlazaCity.KIND_PARTY, Color(0.62, 0.6, 0.57, 0.01))
	var r := uv("podium")
	var segs := 14
	for s: int in range(segs):
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := Vector3(at.x, 0.14, at.y) + d0 * 0.62
		var p1 := Vector3(at.x, 0.14, at.y) + d1 * 0.62
		var u0 := r.position.x + r.size.x * float(s) / float(segs)
		var u1 := r.position.x + r.size.x * float(s + 1) / float(segs)
		var nrm := (d0 + d1).normalized()
		# (counter-clockwise seen from outside: from p1 round to p0)
		decal.quad(p1, p0, p0 + UP * 1.0, p1 + UP * 1.0, [nrm], [Vector2(u1, r.end.y), Vector2(u0, r.end.y), Vector2(u0, r.position.y), Vector2(u1, r.position.y)], Color.WHITE, Vector2(SOLID, 0.0))
	city._lathe(Vector3(at.x, 1.14, at.y), PackedVector2Array([Vector2(0.64, 0.0), Vector2(0.64, 0.04), Vector2(0.0, 0.04)]), 14, PlazaCity.KIND_PARTY, Color(0.9, 0.88, 0.84, 0.02))
	city._lathe(Vector3(at.x, 1.18, at.y), PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.035, 1.5), Vector2(0.0, 1.52)]), 6, PlazaCity.KIND_IRON, Color(0.12, 0.12, 0.12, 0.03))
	city._lathe(Vector3(at.x, 2.55, at.y), PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.92, 0.08), Vector2(0.5, 0.26), Vector2(0.0, 0.36)]), 12, PlazaCity.KIND_DOME, Color(0.16, 0.24, 0.18, 0.03))

# ---------------------------------------------------------------------------------------------------------------
# The subte's plates
# ---------------------------------------------------------------------------------------------------------------
## The Línea A's round plate over a stair's enamel sign (the stair's node as the kit placed it, the sign's width).
func subte_disc(stair: Node3D, width: float) -> void:
	var xf := stair.transform
	var sy1 := 2.4 + width * 0.25
	var at := xf * Vector3(width * 0.5, sy1 + 0.08, 0.0)
	plate(decal, at, xf.basis.z.normalized(), Vector2(0.62, 0.62), uv("disc_a"), CUT, false)

# ---------------------------------------------------------------------------------------------------------------
# The works on Hipólito Yrigoyen, the Cabildo's patio
# ---------------------------------------------------------------------------------------------------------------
## A works hoarding from a to b on the ground, `h` high, its painted face toward `face_point`: boards on posts, the
## second atlas's boards and posters on its face, a red enamel PELIGRO · OBRAS at its middle and a red lamp over it;
## inside it, a heap of setts under the snow and two trestles.
func hoarding(a: Vector2, b: Vector2, h: float, face_point: Vector2) -> void:
	_solid()
	var along := (b - a).normalized()
	var n2 := Vector2(-along.y, along.x)
	if n2.dot(face_point - a) < 0.0: n2 = -n2
	var n := Vector3(n2.x, 0.0, n2.y)
	var green := Color(0.17, 0.27, 0.2, h / 100.0)
	var length := a.distance_to(b)
	# the boards' back and top (the city's plain render) and the posts
	var back_a := a - n2 * 0.06
	var back_b := b - n2 * 0.06
	city._wall(back_b, back_a, 0.0, h, PlazaCity.KIND_PARTY, 0.4, green, back_a + n2 * 5.0, 0.0)
	city._quad_out(Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(back_b.x, h, back_b.y), Vector3(back_a.x, h, back_a.y), UP, [Vector2.ZERO, Vector2(length, 0), Vector2(length, 0.06), Vector2(0, 0.06)], green, Vector2(0.4, PlazaCity.KIND_PARTY))
	var s := 0.0
	while s <= length + 0.01:
		var p := a + along * minf(s, length) - n2 * 0.12
		city._box(Vector3(p.x, h * 0.5 + 0.05, p.y), Vector3(0.12, h + 0.1, 0.12), PlazaCity.KIND_PARTY, Color(0.14, 0.2, 0.15, h / 100.0), 0.4)
		s += 2.4
	# the painted face, a panel of the atlas every four metres
	var r := uv("hoarding")
	var panel := 4.0
	s = 0.0
	while s < length - 0.05:
		var e := minf(s + panel, length)
		var mid := a + along * ((s + e) * 0.5)
		var rr := Rect2(r.position, Vector2(r.size.x * (e - s) / panel, r.size.y))
		plate(decal, Vector3(mid.x, 0.0, mid.y) + n * 0.005, n, Vector2(e - s, h), rr, SOLID, false, Color(0.8, 0.8, 0.8))
		s = e
	var centre := (a + b) * 0.5
	plate(decal, Vector3(centre.x, h * 0.58, centre.y) + n * 0.02, n, Vector2(1.2, 0.3), uv("obras"), SOLID, false)
	# the red lamp on top, and the snow along it
	city._lathe(Vector3(centre.x, h, centre.y), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.11, 0.1), Vector2(0.0, 0.24)]), 6, PlazaCity.KIND_LIGHT, Color(1.0, 0.12, 0.06))
	# inside: a heap of setts under the snow, two trestles
	var inside := centre - n2 * 4.0
	city._lathe(Vector3(inside.x, 0.0, inside.y), PackedVector2Array([Vector2(2.2, 0.0), Vector2(1.6, 0.45), Vector2(0.7, 0.8), Vector2(0.0, 0.9)]), 9, PlazaCity.KIND_ROOF, Color(0.4, 0.4, 0.42, 0.01))
	for k: float in [-1.0, 1.0]:
		var t := centre - n2 * 2.2 + along * k * 3.0
		var tr := Color(0.7, 0.2, 0.15, 0.01)
		city._box(Vector3(t.x, 0.85, t.y), Vector3(0.1 if absf(along.x) < 0.5 else 1.4, 0.18, 1.4 if absf(along.x) < 0.5 else 0.1), PlazaCity.KIND_PARTY, tr, 0.5)
		for f: float in [-0.6, 0.6]:
			var lp := t + along * f
			city._beam(Vector3(lp.x, 0.0, lp.y) - n * 0.2, Vector3(lp.x, 0.85, lp.y), 0.05, Color(0.3, 0.22, 0.15, 0.01))
			city._beam(Vector3(lp.x, 0.0, lp.y) + n * 0.2, Vector3(lp.x, 0.85, lp.y), 0.05, Color(0.3, 0.22, 0.15, 0.01))

## A wall round a patio, through the points (open between `gap`'s two distances along it, an iron gate there): white
## render with a coping, the snow along its top.
func patio_wall(points: Array, h: float, inside: Vector2, gap: Vector2) -> void:
	_solid()
	var tint := Color(0.93, 0.9, 0.84, h / 100.0)
	var run := 0.0
	for i: int in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var pieces: Array = [[0.0, length]]
		if gap.y > run and gap.x < run + length:
			pieces = [[0.0, gap.x - run], [gap.y - run, length]]
		for pc: Array in pieces:
			var s0: float = clampf(pc[0], 0.0, length)
			var s1: float = clampf(pc[1], 0.0, length)
			if s1 - s0 < 0.1: continue
			var p := a + dir * s0
			var q := a + dir * s1
			var n2 := Vector2(-dir.y, dir.x)
			# its two faces and the coping
			city._wall(p, q, 0.0, h, PlazaCity.KIND_PARTY, 0.6, tint * 1.15, inside, 0.0)
			city._wall(q + n2 * 0.0, p, 0.0, h, PlazaCity.KIND_PARTY, 0.6, tint * 1.1, p - (inside - p).normalized() * 3.0, 0.0)
			city._box(Vector3((p.x + q.x) * 0.5, h + 0.08, (p.y + q.y) * 0.5), Vector3(absf(q.x - p.x) + 0.3, 0.16, absf(q.y - p.y) + 0.3), PlazaCity.KIND_PARTY, Color(0.82, 0.8, 0.75, h / 100.0), 0.6)
		if gap.y > run and gap.x < run + length:
			# the gate: iron bars between the two ends
			var g0 := a + dir * (gap.x - run)
			var g1 := a + dir * (gap.y - run)
			var bars := int(g0.distance_to(g1) / 0.14)
			for k: int in range(bars + 1):
				var bp := g0.lerp(g1, float(k) / float(maxi(bars, 1)))
				city._beam(Vector3(bp.x, 0.0, bp.y), Vector3(bp.x, h - 0.4, bp.y), 0.025, Color(0.1, 0.1, 0.1, 0.03))
			for y: float in [0.3, h - 0.5]:
				city._beam(Vector3(g0.x, y, g0.y), Vector3(g1.x, y, g1.y), 0.05, Color(0.1, 0.1, 0.1, 0.03))
		run += length

# ---------------------------------------------------------------------------------------------------------------
func commit() -> void:
	var s := solid.commit(parent, city.material, "CityDetails")
	if s != null: nodes.append(s)
	var d := decal.commit(parent, detail_material, "CityDetailPlates")
	if d != null: nodes.append(d)
