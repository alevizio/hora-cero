extends RefCounted
## Buenos Aires round the Plaza de Mayo on a snowy night in 1958, beyond the square's own rows of the kit (plaza.gd
## builds those): the blocks behind them and the blocks beyond the streets that leave the map, five to nine storeys of
## rendered fronts with balconies, mansards and corner cupolas; the two Diagonales opening north-west and south-west,
## lined with their tall even fronts; the Avenida de Mayo going on west past the Palacio Barolo's tower to the Plaza
## del Congreso and the Congreso's dome (a distant skyline in a low view); the port behind the Casa Rosada beyond
## Paseo Colón, its sheds, its cranes over the black water of the dock and a ship at the quay. The sizes and places are
## the city's, drawn close (the avenue is shortened to a third).
##
## All of it is one material (plaza_city.gdshader: the fronts' windows, shops, balconies and snow are drawn by it, not
## modelled), committed as meshes of its own a district at a time (so what is out of view is culled), casting no
## shadow: a handful of draws for the whole city. Every vertex carries what the shader needs: UV (m) along a front and
## up it, UV2 (its lot's seed, what the surface is: KIND_*), COLOR (the render's colour; alpha the cornice's height).
##
## furnish() adds what the kit draws (plane trees on the avenues, lamps, parked cars and taxis under snow, trams and
## colectivos on the streets beyond the map) to the square's kit before it finishes; fold() then folds all of the
## kit's pieces out in the city into two meshes a district.

const CityShader := preload("res://shaders/plaza_city.gdshader")
const PlazaGround = preload("res://scripts/three_d/plaza_ground.gd")
const UP := Vector3.UP

const KIND_FRONT := 0.0
const KIND_PARTY := 1.0
const KIND_COURT := 2.0
const KIND_ROOF := 3.0
const KIND_MANSARD := 4.0
const KIND_DOME := 5.0
const KIND_IRON := 6.0
const KIND_WATER := 7.0
const KIND_STONE := 8.0
const KIND_LIGHT := 9.0
const KIND_STREET := 10.0

## The meshes are cut into districts this many metres on a side (the kit's pieces folded smaller: they are dense).
const CHUNK := 110.0
const FOLD_CHUNK := 50.0
## A storey, and the ground floor with its shops (metres), as the shader draws them (about).
const STOREY := 3.4
const GROUND := 4.6
const CORNICE := 0.95
## The Avenida de Mayo beyond the map: where its fronts end, the Plaza del Congreso, the Congreso, the Barolo.
const AVENUE_END := -560.0
const CONGRESO_X := -640.0
const BAROLO_X := -430.0
## Along the Diagonal Norte (metres from its start): where the city's grid ends and its own blocks begin, and the
## Obelisco at its end in the Plaza de la República (drawn close: a third of the way).
const DIAGONAL_GRID_END := 240.0
## The vehicles' game meshes (tools/vehicles.gd), the cars of the time that stand for the kit's sedans, their paints.
const VEHICLES := "res://assets/vehicles/"
const PERIOD_SEDANS := ["sedan49", "saloon53", "coupe48", "sedan49", "saloon53", "sedan49"]
const CAR_PAINTS := ["15171a", "24382c", "1e2a40", "4a1c1a", "d8cfb4", "5e6266", "2c3a30", "3a2224", "8a9aa4"]
const WORK_PAINTS := ["5a6a52", "3a4a5a", "7a6a4a", "4a4a44", "6e6656"]
const TAXI_BLACK := "131416"
const OBELISCO_S := 580.0

## The renders of the city's fronts (1958: stone, pale ochre, cream, grey, a pink, a little brick).
const PALETTE := ["d6c7a6", "c9a875", "e0d3b4", "b8b0a2", "d4b6a2", "a9a99c", "c4b08a", "9a8a78", "8e5a46", "cfc2ae"]

class Batch:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	## A quad a, b, c, d counter-clockwise seen from outside (bottom-left, bottom-right, top-right, top-left), as the
	## kit lays them; normals per corner (or one for all).
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Array, uvs: Array, col: Color, ks: Vector2) -> void:
		var base := v.size()
		v.append_array(PackedVector3Array([a, b, cc, d]))
		for i: int in range(4):
			n.append(nrm[i] if nrm.size() == 4 else nrm[0])
			c.append(col)
			uv.append(uvs[i])
			uv2.append(ks)
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))

	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, uvs: Array, col: Color, ks: Vector2) -> void:
		var base := v.size()
		v.append_array(PackedVector3Array([a, b, cc]))
		for i: int in range(3):
			n.append(nrm)
			c.append(col)
			uv.append(uvs[i])
			uv2.append(ks)
		idx.append_array(PackedInt32Array([base, base + 2, base + 1]))

	func commit(parent: Node3D, material: Material, node_name: String) -> MeshInstance3D:
		if idx.is_empty(): return null
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var node := MeshInstance3D.new()
		node.name = node_name
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		return node

var parent: Node3D
var material: ShaderMaterial
var rng := RandomNumberGenerator.new()
var pw: Dictionary
var W: float
var H: float
var nodes: Array[MeshInstance3D] = []
var _batches: Dictionary = {}
var _batch: Batch
## The Diagonales: [start (x, z), direction, half width], their streets cut through the blocks.
var diagonals: Array = []
var triangles: int = 0
## Every lot's outline and height as built (for tests and tools): [outline, top].
var lots: Array = []

func _init(p_parent: Node3D, p_pw: Dictionary, p_w: float, p_h: float, macro: Texture2D) -> void:
	parent = p_parent
	pw = p_pw
	W = p_w
	H = p_h
	rng.seed = 1958052501
	material = ShaderMaterial.new()
	material.shader = CityShader
	material.set_shader_parameter("macro_tex", macro)
	diagonals = diagonal_lines()

## The two Diagonales (PlazaGround's: their streets are the ground's too).
static func diagonal_lines() -> Array:
	return PlazaGround.diagonal_lines()

func build() -> void:
	for block: Dictionary in _blocks():
		var pieces: Array = [block]
		for d: Array in diagonals: pieces = _cut(pieces, d)
		for piece: Dictionary in pieces:
			# (a sliver left by a Diagonal's cut is left open: a little square of snow, not a wedge of wall)
			if _thickness(piece.poly) < 11.0: continue
			_lots(_chamfer(piece))
	for block: Dictionary in _diagonal_blocks(): _lots(_chamfer(block))
	_avenue_far()
	_barolo()
	_congreso()
	_obelisco()
	_port()
	_far_streets()
	_ring()
	for key: Vector2i in _batches:
		var b: Batch = _batches[key]
		triangles += b.idx.size() / 3
		var node := b.commit(parent, material, "City_%d_%d" % [key.x, key.y])
		if node != null: nodes.append(node)
	_batches.clear()

## How much of the night's snow lies on the city (the plaza's _sync_snow, with the kit's).
func set_snow(amount: float) -> void:
	material.set_shader_parameter("snow_amount", amount)

func _use(at: Vector2) -> void:
	var key := Vector2i(int(floor(at.x / CHUNK)), int(floor(at.y / CHUNK)))
	if not _batches.has(key): _batches[key] = Batch.new()
	_batch = _batches[key]

# ---------------------------------------------------------------------------------------------------------------
# The blocks
# ---------------------------------------------------------------------------------------------------------------
## A block: its outline (convex, counter-clockwise in x, z), and per edge (from point i to i + 1) whether a street runs
## along it ("street": the lots face it; otherwise it backs onto something already built, a row of the kit, a landmark
## or another block, and nothing is built along it) and whether that street is a Diagonal ("diag": the fronts there tall
## and even, as the Diagonales' ordinance had them).
static func block(r: Rect2, street: Array, style: Dictionary) -> Dictionary:
	return {"poly": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		"street": street.duplicate(), "diag": [false, false, false, false], "style": style}

## The blocks to fill (rectangles; street sides north, east, south, west): behind the square's own rows, beyond the
## streets round the map, west of it along Rivadavia and Yrigoyen, south of the ministries. The streets between them
## are the ground's (PlazaGround.roads), the rows on them the kit's (plaza.gd).
func _blocks() -> Array:
	var town := {"floors": Vector2i(3, 6), "mansard": 0.35, "dome": 0.18, "depth": 14.0}
	var tall := {"floors": Vector2i(4, 8), "mansard": 0.45, "dome": 0.3, "depth": 15.0}
	var out: Array = []
	var nb := PlazaGround.NORTH_STREET + 10.0
	# the band north of Rivadavia, behind the north row, the Catedral and the Banco (their backs not streets)
	out.append(block(Rect2(-150, nb, 62, 6 - nb), [true, true, false, true], tall))
	out.append(block(Rect2(-76, nb, 62, 6 - nb), [true, true, false, true], tall))
	out.append(block(Rect2(-4, nb, 48, 6 - nb), [true, false, false, true], tall))
	out.append(block(Rect2(44, nb, 52, -22 - nb), [true, true, false, false], tall))
	out.append(block(Rect2(104, nb, 76, 6 - nb), [true, true, false, true], tall))
	out.append(block(Rect2(188, nb, 54, 0 - nb), [true, true, false, true], tall))
	out.append(block(Rect2(256, nb, 28, 6 - nb), [true, true, false, true], tall))
	# beyond the street behind it
	for span: Vector2 in [Vector2(-150, -88), Vector2(-76, -14), Vector2(-4, 96), Vector2(104, 180), Vector2(188, 242), Vector2(256, 284)]:
		out.append(block(Rect2(span.x, PlazaGround.NORTH_STREET - 58.0, span.y - span.x, 56.0), [true, true, true, true], town))
	# west of the map, south of Yrigoyen, behind its rows
	for span: Vector2 in PlazaGround.WEST_SPANS:
		out.append(block(Rect2(span.x, 163.0, span.y - span.x, 37.0), [false, true, true, true], town))
	# south of Yrigoyen, west of the ministries: its front on Yrigoyen (the corner the rules call south-w), the street
	# behind the ministries
	var yri := PlazaGround.pair_of(pw, "yrigoyen", Vector2(132.0, 146.0))
	var mw := PlazaGround.rect_of(pw, "ministryW", [28.0, 146.0, 120.0, 166.0])
	out.append(block(Rect2(PlazaGround.WEST_STREETS[1] + 8.0, yri.y, mw.position.x - PlazaGround.WEST_STREETS[1] - 8.0, H + 36.0 - yri.y), [true, false, true, true], town))
	# south of the ministries, behind the south rows
	out.append(block(Rect2(mw.position.x, mw.end.y + 1.0, mw.size.x, H + 36.0 - mw.end.y - 1.0), [false, true, true, false], tall))
	var me := PlazaGround.rect_of(pw, "ministryE", [128.0, 146.0, 242.0, 166.0])
	out.append(block(Rect2(me.position.x, me.end.y + 1.0, me.size.x, H + 36.0 - me.end.y - 1.0), [false, true, true, true], tall))
	out.append(block(Rect2(256.0, 163.0, 28.0, H + 36.0 - 163.0), [false, true, true, true], town))
	# beyond the street behind them
	for span: Vector2 in [Vector2(-150, -88), Vector2(-76, -14), Vector2(-4, 120), Vector2(128, 242), Vector2(256, 284)]:
		out.append(block(Rect2(span.x, H + 46.0, span.y - span.x, 40.0), [true, true, true, true], town))
	return out

## The city going on beyond all that: a plain grid of low blocks wherever nothing stands yet, north, west and south
## (the port and the river are east), out as far as the widest view reaches (on the web the view grows with the
## window: a 250 m-tall view at the camera's farthest), so no bare ground shows at the edge of the picture. Built
## last: each cell is tried against the lots already there, keeps off the avenue's carriageway west of the map and
## the Plaza de la República, and is cut by the Diagonales like any block.
func _ring() -> void:
	var low := {"floors": Vector2i(2, 4), "mansard": 0.2, "dome": 0.0, "depth": 13.0}
	var inner := Rect2(-150.0, PlazaGround.NORTH_STREET - 58.0, W + 4.0 + 150.0, H + 86.0 - (PlazaGround.NORTH_STREET - 58.0)).grow(6.0)
	var avenue := Rect2(-720.0, 20.0, 570.0, 128.0)
	var dn: Array = diagonals[0]
	var obelisco: Vector2 = (dn[0] as Vector2) + (dn[1] as Vector2) * OBELISCO_S
	var taken: Array[Rect2] = []
	for lot: Array in lots:
		var poly: PackedVector2Array = lot[0]
		var box := Rect2(poly[0], Vector2.ZERO)
		for q: Vector2 in poly: box = box.expand(q)
		taken.append(box.grow(3.0))
	var gx := -310.0
	while gx + 62.0 <= W + 4.0:
		var gz := PlazaGround.NORTH_STREET - 270.0
		while gz < H + 330.0:
			var r := Rect2(gx, gz, 62.0, 42.0)
			var free := not r.intersects(inner) and not r.intersects(avenue) and r.get_center().distance_to(obelisco) > 110.0
			if free:
				for t: Rect2 in taken:
					if r.intersects(t):
						free = false
						break
			if free:
				var pieces: Array = [block(r, [true, true, true, true], low)]
				for d: Array in diagonals: pieces = _cut(pieces, d)
				for piece: Dictionary in pieces:
					if _thickness(piece.poly) >= 11.0: _lots(_chamfer(piece))
			gz += 52.0
		gx += 72.0

## The Diagonal Norte's own blocks beyond the city's grid, out to the Plaza de la República: on both sides of it, a
## block between each cross street, its front on the Diagonal (eight storeys and a mansard, all alike), its ends on the
## cross streets, its back on the blocks behind (not built).
func _diagonal_blocks() -> Array:
	var out: Array = []
	var d: Array = diagonals[0]
	var o: Vector2 = d[0]
	var dir: Vector2 = d[1]
	var hw: float = d[2]
	var m := Vector2(-dir.y, dir.x)
	var style := {"floors": Vector2i(8, 8), "mansard": 1.0, "dome": 0.5, "depth": 16.0}
	var s := DIAGONAL_GRID_END
	while s < OBELISCO_S - 50.0:
		var s1 := minf(s + 78.0, OBELISCO_S - 50.0)
		for side: float in [-1.0, 1.0]:
			var near := hw + 1.5
			var far := near + 22.0
			var pts := [o + dir * s + m * side * near, o + dir * s1 + m * side * near, o + dir * s1 + m * side * far, o + dir * s + m * side * far]
			# edges: the Diagonal, the far cross street, the back, the near cross street
			var b := {"poly": PackedVector2Array(pts), "street": [true, true, false, true], "diag": [true, false, false, false], "style": style}
			out.append(_ccw(b))
		s = s1 + 14.0
	return out

## A block turned counter-clockwise (its edge flags following their edges).
static func _ccw(b: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = b.poly
	if _area(poly) >= 0.0: return b
	var n := poly.size()
	var rp := PackedVector2Array()
	var rs: Array = []
	var rd: Array = []
	for i: int in range(n):
		rp.append(poly[n - 1 - i])
	# (reversed, the edge from new point i to i + 1 is the old edge from n - 2 - i to n - 1 - i)
	for i: int in range(n):
		var old := (n - 2 - i + n) % n
		rs.append(b.street[old])
		rd.append(b.diag[old])
	return {"poly": rp, "street": rs, "diag": rd, "style": b.style}

## The blocks less a Diagonal's street: past its start, each block cut along the strip (the cut a street of the
## Diagonal's); short of it, untouched.
func _cut(pieces: Array, diag: Array) -> Array:
	var o: Vector2 = diag[0]
	var d: Vector2 = diag[1]
	var hw: float = diag[2]
	var m := Vector2(-d.y, d.x)
	var out: Array = []
	for b: Dictionary in pieces:
		var poly: PackedVector2Array = b.poly
		var ahead := false
		var through := false
		for p: Vector2 in poly:
			if d.dot(p - o) > 0.0: ahead = true
			if absf(m.dot(p - o)) < hw: through = true
		var lo := 1e9
		var hi := -1e9
		for p: Vector2 in poly:
			lo = minf(lo, m.dot(p - o))
			hi = maxf(hi, m.dot(p - o))
		if not ahead or (lo > hw or hi < -hw):
			out.append(b)
			continue
		# behind the Diagonal's start: kept whole (the line across it no street)
		var behind := _clip_block(b, -d, o, 0.0, false, false)
		if not behind.is_empty() and absf(_area(behind.poly)) > 30.0: out.append(behind)
		var front := _clip_block(b, d, o, 0.0, false, false)
		if front.is_empty(): continue
		for side: float in [-1.0, 1.0]:
			var piece := _clip_block(front, m * side, o, hw, true, true)
			if not piece.is_empty() and absf(_area(piece.poly)) > 30.0: out.append(piece)
	return out

## The part of a convex block where dot(n, p - o) >= k, the new edge along the cut flagged as given.
static func _clip_block(b: Dictionary, n: Vector2, o: Vector2, k: float, street: bool, diag: bool) -> Dictionary:
	var poly: PackedVector2Array = b.poly
	var count := poly.size()
	var pts := PackedVector2Array()
	var st: Array = []
	var dg: Array = []
	for i: int in range(count):
		var a := poly[i]
		var c := poly[(i + 1) % count]
		var da := n.dot(a - o) - k
		var dc := n.dot(c - o) - k
		if da >= 0.0:
			pts.append(a)
			st.append(b.street[i])
			dg.append(b.diag[i])
			if dc < 0.0:
				pts.append(a.lerp(c, da / (da - dc)))
				st.append(street)
				dg.append(diag)
		elif dc >= 0.0:
			pts.append(a.lerp(c, da / (da - dc)))
			st.append(b.street[i])
			dg.append(b.diag[i])
	if pts.size() < 3: return {}
	return {"poly": pts, "street": st, "diag": dg, "style": b.style}

## Every corner where two streets meet cut back in an ochava, as the city's corners all are: a short front of its
## own, the longer the sharper the corner (a Diagonal's corners are cut deep), never more than a third of either side.
static func _chamfer(b: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = b.poly
	var n := poly.size()
	var pts := PackedVector2Array()
	var st: Array = []
	var dg: Array = []
	for i: int in range(n):
		var prev := (i - 1 + n) % n
		var p := poly[i]
		var a := poly[prev]
		var c := poly[(i + 1) % n]
		if bool(b.street[prev]) and bool(b.street[i]):
			var e0 := (a - p)
			var e1 := (c - p)
			var ang := rad_to_deg(e0.angle_to(e1))
			ang = absf(ang)
			var cut := 3.0 if ang >= 80.0 else 3.0 + (80.0 - ang) / 35.0 * 7.0
			cut = minf(cut, minf(e0.length(), e1.length()) * 0.33)
			if cut > 0.5:
				pts.append(p + e0.normalized() * cut)
				st.append(true)
				dg.append(false)
				pts.append(p + e1.normalized() * cut)
				st.append(b.street[i])
				dg.append(b.diag[i])
				continue
		pts.append(p)
		st.append(b.street[i])
		dg.append(b.diag[i])
	return {"poly": pts, "street": st, "diag": dg, "style": b.style}

## The part of a convex polygon where dot(m, p - o) >= k (Sutherland-Hodgman against one line).
static func _clip(poly: PackedVector2Array, m: Vector2, o: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var da := m.dot(a - o) - k
		var db := m.dot(b - o) - k
		if da >= 0.0: out.append(a)
		if (da >= 0.0) != (db >= 0.0): out.append(a.lerp(b, da / (da - db)))
	return out

static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i: int in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

## How thick a convex outline is at its thinnest: the least, over its sides, of how far its far point lies from that side.
static func _thickness(poly: PackedVector2Array) -> float:
	var best := 1e9
	var n := poly.size()
	for i: int in range(n):
		var a := poly[i]
		var e := (poly[(i + 1) % n] - a)
		if e.length() < 0.5: continue
		var inn := Vector2(-e.y, e.x).normalized()
		var far := 0.0
		for p: Vector2 in poly: far = maxf(far, inn.dot(p - a))
		best = minf(best, far)
	return best

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Vector2 in poly: c += p
	return c / float(maxi(poly.size(), 1))

## A block's lots: along each of its streets a band `depth` deep, the bands of two streets meeting along the line
## halfway between them (so the corner lot takes its corner whole, and a block too narrow for two bands is built through
## from one street to the other); each band cut across into lots nine to nineteen metres wide (fourteen to twenty-two on
## a Diagonal), never a sliver; behind the bands the courtyard, open. Each lot its own height, render and roof.
func _lots(b: Dictionary) -> void:
	var poly: PackedVector2Array = b.poly
	var n := poly.size()
	if n < 3 or absf(_area(poly)) < 60.0: return
	var style: Dictionary = b.style
	var depth: float = style.get("depth", 14.0)
	_use(_centroid(poly))
	var edges: Array = []
	for i: int in range(n):
		var a := poly[i]
		var c := poly[(i + 1) % n]
		var e := c - a
		edges.append({"a": a, "dir": e.normalized(), "len": e.length(), "in": Vector2(-e.y, e.x).normalized(), "street": bool(b.street[i]), "diag": bool(b.diag[i])})
	for i: int in range(n):
		var ed: Dictionary = edges[i]
		if not ed.street or float(ed.len) < 2.5: continue
		var a: Vector2 = ed.a
		var dir: Vector2 = ed.dir
		var inn: Vector2 = ed["in"]
		# the band: within the block, `depth` in from this street, nearer this street than any other
		var region := _clip(poly, -inn, a, -depth)
		for j: int in range(n):
			var ej: Dictionary = edges[j]
			if j == i or not ej.street or float(ej.len) < 2.5: continue
			var nj: Vector2 = ej["in"]
			var normal := nj - inn
			if normal.length() < 0.01: continue
			# d_i(p) <= d_j(p): dot(inn, p - a) <= dot(nj, p - a_j), that is dot(nj - inn, p) >= dot(nj, a_j) - dot(inn, a)
			var aj: Vector2 = ej.a
			region = _clip(region, normal, Vector2.ZERO, nj.dot(aj) - inn.dot(a))
			if region.size() < 3: break
		if region.size() < 3 or absf(_area(region)) < 25.0: continue
		var t_lo := 1e9
		var t_hi := -1e9
		for p: Vector2 in region:
			t_lo = minf(t_lo, dir.dot(p - a))
			t_hi = maxf(t_hi, dir.dot(p - a))
		var span := t_hi - t_lo
		var diag: bool = ed.diag
		var corner := float(ed.len) < 9.0
		var cuts: Array[float] = [t_lo]
		if not corner:
			while cuts[cuts.size() - 1] < t_hi - 0.01:
				var want := rng.randf_range(14.0, 22.0) if diag else rng.randf_range(9.0, 19.0)
				var t1 := cuts[cuts.size() - 1] + want
				if t_hi - t1 < 7.0: t1 = t_hi
				cuts.append(minf(t1, t_hi))
		else:
			cuts.append(t_hi)
		for k: int in range(cuts.size() - 1):
			var lot := _clip(_clip(region, dir, a + dir * cuts[k], 0.0), -dir, a + dir * cuts[k + 1], 0.0)
			if lot.size() < 3 or absf(_area(lot)) < 20.0: continue
			var floors := rng.randi_range(style.floors.x, style.floors.y)
			var mansard: bool = rng.randf() < float(style.mansard)
			if corner: floors += 1
			if diag:
				floors = 8
				mansard = true
			_lot(lot, a, dir, inn, depth, floors, mansard, cuts[k])
			if corner and rng.randf() < float(style.get("dome", 0.2)):
				var mid := a + dir * float(ed.len) * 0.5 + inn * 3.2
				_cupola(mid, GROUND + float(floors) * STOREY + CORNICE + (2.8 if mansard else 0.0), 2.6 if not diag else 3.2)
	# behind the bands, the block's inside built low (workshops, garages, the backs of the houses), light wells between
	var inner := poly
	for ed: Dictionary in edges:
		# (an edge of no length, where a cut met a corner, has no side to keep)
		if float(ed.len) < 0.05: continue
		inner = _clip(inner, ed["in"], ed.a, depth + 1.0 if ed.street else 1.5)
		if inner.size() < 3: return
	if absf(_area(inner)) < 60.0: return
	var u := Vector2.RIGHT
	var longest := 0.0
	for i: int in range(inner.size()):
		var e := inner[(i + 1) % inner.size()] - inner[i]
		if e.length() > longest:
			longest = e.length()
			u = e.normalized()
	var lo := 1e9
	var hi := -1e9
	for p: Vector2 in inner:
		lo = minf(lo, u.dot(p))
		hi = maxf(hi, u.dot(p))
	var t := lo
	while t < hi - 5.0:
		var t1 := minf(t + rng.randf_range(12.0, 24.0), hi)
		if hi - t1 < 6.0: t1 = hi
		var piece := _clip(_clip(inner, u, u * t, 0.0), -u, u * t1, 0.0)
		if piece.size() >= 3 and absf(_area(piece)) > 30.0 and _thickness(piece) > 4.0:
			_back_building(piece, rng.randf_range(4.2, 8.5))
		t = t1 + rng.randf_range(2.0, 4.0)

## A low building in a block's inside: plain walls, a flat roof of tar (white with the snow), a skylight's hump.
func _back_building(poly: PackedVector2Array, h: float) -> void:
	var tint := Color.html("a39a8a") * rng.randf_range(0.75, 0.95)
	tint.a = h / 100.0
	var seed := rng.randf()
	var mid := _centroid(poly)
	lots.append([poly, h])
	for i: int in range(poly.size()):
		_wall(poly[i], poly[(i + 1) % poly.size()], 0.0, h, KIND_PARTY, seed, tint, mid, 0.0)
	_roof(poly, h, tint, seed)
	if rng.randf() < 0.4:
		_box(Vector3(mid.x, h + 0.4, mid.y), Vector3(2.4, 0.8, 1.6), KIND_PARTY, Color(0.5, 0.48, 0.45, h / 100.0), seed)

## One lot (a convex outline): its front on the street (the outline's part along the street line through `a`), a
## projecting cornice along it with snow on it, its other sides party walls, or the courtyard's face where the band
## ends; `floors` storeys over the shops, a flat roof or a mansard sloping back from the cornice behind its party
## walls' parapets; chimneys and a water tank.
func _lot(lot: PackedVector2Array, a: Vector2, dir: Vector2, inn: Vector2, depth: float, floors: int, mansard: bool, u0: float) -> void:
	var top := GROUND + float(floors) * STOREY + CORNICE
	var tint := _tint()
	tint.a = top / 100.0
	var seed := rng.randf()
	var mid := _centroid(lot)
	lots.append([lot, top])
	var y_top := top + (2.8 if mansard else 0.0)
	var n := lot.size()
	for i: int in range(n):
		var p := lot[i]
		var q := lot[(i + 1) % n]
		if p.distance_to(q) < 0.05: continue
		var dp := inn.dot(p - a)
		var dq := inn.dot(q - a)
		var up := dir.dot(p - a)
		if absf(dp) < 0.05 and absf(dq) < 0.05:
			_wall(p, q, 0.0, top, KIND_FRONT, seed, tint, mid, minf(up, dir.dot(q - a)))
			_ledge(p, q, mid, top - 0.62, 0.5, 0.42, tint, seed)
		elif absf(dp - depth) < 0.05 and absf(dq - depth) < 0.05:
			_wall(p, q, 0.0, top - 0.4, KIND_COURT, seed, tint, mid, 0.0)
			if mansard: _wall(p, q, top - 0.4, y_top, KIND_PARTY, seed, tint, mid, 0.0)
		else:
			_wall(p, q, 0.0, y_top, KIND_PARTY, seed, tint, mid, 0.0)
	var roof := lot
	if mansard:
		# the slate from the cornice back 1.6 m and up 2.8 m, its dormers drawn on it
		var back := _clip(lot, inn, a, 1.6)
		var fr: Array = []
		for i: int in range(n):
			var p := lot[i]
			var q := lot[(i + 1) % n]
			if absf(inn.dot(p - a)) < 0.05 and absf(inn.dot(q - a)) < 0.05: fr.append([p, q])
		for pq: Array in fr:
			var p: Vector2 = pq[0]
			var q: Vector2 = pq[1]
			var p1 := p + inn * 1.6
			var q1 := q + inn * 1.6
			var length := p.distance_to(q)
			var nrm := (Vector3(-inn.x, 0.0, -inn.y) * 2.8 + UP * 1.6).normalized()
			var slant := sqrt(1.6 * 1.6 + 2.8 * 2.8)
			var uu := dir.dot(p - a) if dir.dot(q - p) > 0.0 else dir.dot(q - a)
			_quad_out(Vector3(p.x, top, p.y), Vector3(q.x, top, q.y), Vector3(q1.x, y_top, q1.y), Vector3(p1.x, y_top, p1.y), nrm,
				[Vector2(uu, top), Vector2(uu + length, top), Vector2(uu + length, top + slant), Vector2(uu, top + slant)], tint, Vector2(seed, KIND_MANSARD))
		# the parapets of the party walls rise to its top: the slope's ends close against them
		roof = back
	_roof(roof, y_top, tint, seed)
	# chimneys and a water tank
	var count := rng.randi_range(0, 3)
	var inner := _clip(roof, inn, a, 2.6) if roof.size() >= 3 else roof
	if inner.size() >= 3:
		for i: int in range(count):
			var at := _centroid(inner).lerp(inner[rng.randi() % inner.size()], rng.randf_range(0.1, 0.7))
			var h := rng.randf_range(0.8, 1.6)
			_box(Vector3(at.x, y_top + h * 0.5, at.y), Vector3(0.7, h, 0.7), KIND_PARTY, Color(0.45, 0.4, 0.38, y_top / 100.0), seed)
		if rng.randf() < 0.22:
			var at := _centroid(inner)
			_box(Vector3(at.x, y_top + 1.2, at.y), Vector3(2.2, 1.6, 2.2), KIND_PARTY, Color(0.4, 0.33, 0.3, y_top / 100.0), seed)

## A cornice along a front from p to q: a slab `out` metres proud at height y, `h` thick, facing away from `inside`; the
## snow lies on its top (the shader whitens what faces up).
func _ledge(p: Vector2, q: Vector2, inside: Vector2, y: float, out: float, h: float, tint: Color, seed: float) -> void:
	var o2 := _out2(p, q, inside)
	var e := (q - p).normalized()
	var p0 := p - e * 0.2
	var q0 := q + e * 0.2
	var p1 := p0 + o2 * out
	var q1 := q0 + o2 * out
	var c := tint * 1.12
	c.a = tint.a
	var ks := Vector2(seed, KIND_PARTY)
	var o3 := Vector3(o2.x, 0.0, o2.y)
	var length := p0.distance_to(q0)
	_quad_out(Vector3(p1.x, y, p1.y), Vector3(q1.x, y, q1.y), Vector3(q1.x, y + h, q1.y), Vector3(p1.x, y + h, p1.y), o3, [Vector2(0, y), Vector2(length, y), Vector2(length, y + h), Vector2(0, y + h)], c, ks)
	_quad_out(Vector3(p0.x, y + h, p0.y), Vector3(q0.x, y + h, q0.y), Vector3(q1.x, y + h, q1.y), Vector3(p1.x, y + h, p1.y), UP, [Vector2(0, 0), Vector2(length, 0), Vector2(length, out), Vector2(0, out)], c, ks)
	var dark := tint * 0.55
	dark.a = tint.a
	_quad_out(Vector3(p0.x, y, p0.y), Vector3(q0.x, y, q0.y), Vector3(q1.x, y, q1.y), Vector3(p1.x, y, p1.y), -UP, [Vector2(0, 0), Vector2(length, 0), Vector2(length, out), Vector2(0, out)], dark, ks)
	for end: Array in [[p0, p1, -e], [q0, q1, e]]:
		var b0: Vector2 = end[0]
		var b1: Vector2 = end[1]
		var en: Vector2 = end[2]
		_quad_out(Vector3(b0.x, y, b0.y), Vector3(b1.x, y, b1.y), Vector3(b1.x, y + h, b1.y), Vector3(b0.x, y + h, b0.y), Vector3(en.x, 0, en.y), [Vector2(0, y), Vector2(out, y), Vector2(out, y + h), Vector2(0, y + h)], c, ks)

## A wall from a to b (on the ground plan) between y0 and y1, facing away from `inside`; u along it from u0.
func _wall(a: Vector2, b: Vector2, y0: float, y1: float, kind: float, seed: float, tint: Color, inside: Vector2, u0: float) -> void:
	var length := a.distance_to(b)
	if length < 0.05 or y1 <= y0: return
	var out := _out2(a, b, inside)
	var nrm := Vector3(out.x, 0.0, out.y)
	_quad_out(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), nrm,
		[Vector2(u0, y0), Vector2(u0 + length, y0), Vector2(u0 + length, y1), Vector2(u0, y1)], tint, Vector2(seed, kind))

static func _out2(a: Vector2, b: Vector2, inside: Vector2) -> Vector2:
	var e := (b - a).normalized()
	var out := Vector2(e.y, -e.x)
	if out.dot((a + b) * 0.5 - inside) < 0.0: out = -out
	return out

## A quad with its face toward `facing` whatever the order it was given in (the corners' uvs follow them).
func _quad_out(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, facing: Vector3, uvs: Array, tint: Color, ks: Vector2, nrms: Array = []) -> void:
	var nrm := (b - a).cross(d - a)
	if nrm.dot(facing) < 0.0:
		var flipped: Array = [uvs[1], uvs[0], uvs[3], uvs[2]]
		var fn: Array = nrms if nrms.size() != 4 else [nrms[1], nrms[0], nrms[3], nrms[2]]
		_batch.quad(b, a, d, cc, fn if fn.size() == 4 else [facing.normalized()], flipped, tint, ks)
	else:
		_batch.quad(a, b, cc, d, nrms if nrms.size() == 4 else [facing.normalized()], uvs, tint, ks)

func _tri_out(a: Vector3, b: Vector3, cc: Vector3, facing: Vector3, tint: Color, ks: Vector2) -> void:
	var nrm := (b - a).cross(cc - a)
	var uvs: Array = [Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(cc.x + cc.z, cc.y)]
	if nrm.dot(facing) < 0.0: _batch.tri(a, cc, b, facing.normalized(), [uvs[0], uvs[2], uvs[1]], tint, ks)
	else: _batch.tri(a, b, cc, facing.normalized(), uvs, tint, ks)

## A flat roof over a convex polygon at a height.
func _roof(poly: PackedVector2Array, y: float, tint: Color, seed: float) -> void:
	if poly.size() < 3: return
	var p0 := Vector3(poly[0].x, y, poly[0].y)
	for i: int in range(1, poly.size() - 1):
		var pa := Vector3(poly[i].x, y, poly[i].y)
		var pb := Vector3(poly[i + 1].x, y, poly[i + 1].y)
		if (pa - p0).cross(pb - p0).length_squared() < 1e-6: continue
		_tri_out(p0, pa, pb, UP, Color(tint, y / 100.0), Vector2(seed, KIND_ROOF))

## A box: its sides of one kind, its top a roof.
func _box(center: Vector3, size: Vector3, kind: float, tint: Color, seed: float, top_kind: float = KIND_ROOF) -> void:
	var h := size * 0.5
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	var mid := Vector2(center.x, center.z)
	for e: Array in [[Vector2(x0, z1), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x0, z0)], [Vector2(x0, z0), Vector2(x0, z1)]]:
		_wall(e[0], e[1], y0, y1, kind, seed, tint, mid, (e[0] as Vector2).x + (e[0] as Vector2).y)
	_roof(PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]), y1, tint, seed)
	if top_kind != KIND_ROOF:
		pass

## A beam (iron) from a to b, `w` across.
func _beam(a: Vector3, b: Vector3, w: float, tint: Color) -> void:
	var d := (b - a)
	var length := d.length()
	if length < 0.01: return
	var y := d / length
	var x := y.cross(UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized() * w * 0.5
	var z := x.cross(y).normalized() * w * 0.5
	var corners := [x + z, -x + z, -x - z, x - z]
	for i: int in range(4):
		var c0: Vector3 = corners[i]
		var c1: Vector3 = corners[(i + 1) % 4]
		var face := (c0 + c1).normalized()
		_quad_out(a + c0, a + c1, b + c1, b + c0, face, [Vector2(0, 0), Vector2(w, 0), Vector2(w, length), Vector2(0, length)], tint, Vector2(0.5, KIND_IRON))

## A solid of revolution round a vertical axis at `at`: profile (radius, height) from the bottom up; smooth normals.
func _lathe(at: Vector3, prof: PackedVector2Array, segs: int, kind: float, tint: Color, seed: float = 0.5) -> void:
	for j: int in range(prof.size() - 1):
		var p0 := prof[j]
		var p1 := prof[j + 1]
		var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for s: int in range(segs):
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var v00 := at + d0 * p0.x + UP * p0.y
			var v10 := at + d1 * p0.x + UP * p0.y
			var v11 := at + d1 * p1.x + UP * p1.y
			var v01 := at + d0 * p1.x + UP * p1.y
			var n0 := (d0 * slope.x + UP * slope.y).normalized()
			var n1 := (d1 * slope.x + UP * slope.y).normalized()
			var u0 := float(s) / float(segs) * TAU * maxf(p0.x, 0.5)
			var u1 := float(s + 1) / float(segs) * TAU * maxf(p0.x, 0.5)
			if p1.x < 0.01:
				_tri_out(v00, v10, v01, (n0 + n1).normalized(), tint, Vector2(seed, kind))
			else:
				_quad_out(v00, v10, v11, v01, (n0 + n1).normalized(), [Vector2(u0, p0.y), Vector2(u1, p0.y), Vector2(u1, p1.y), Vector2(u0, p1.y)], tint, Vector2(seed, kind), [n0, n1, n1, n0])

## A corner cupola: a short drum, a slate dome, a finial.
func _cupola(at: Vector2, base_y: float, r: float) -> void:
	var tint := Color(0.24, 0.25, 0.28, (base_y + r * 2.4) / 100.0)
	var stone := _tint()
	stone.a = (base_y + r) / 100.0
	_lathe(Vector3(at.x, base_y, at.y), PackedVector2Array([Vector2(r, 0.0), Vector2(r, r * 0.95)]), 8, KIND_PARTY, stone)
	_lathe(Vector3(at.x, base_y + r * 0.95, at.y), PackedVector2Array([Vector2(r * 1.05, 0.0), Vector2(r * 0.98, r * 0.45), Vector2(r * 0.75, r * 0.95), Vector2(r * 0.35, r * 1.3), Vector2(0.0, r * 1.42)]), 10, KIND_DOME, tint)
	_lathe(Vector3(at.x, base_y + r * 2.35, at.y), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.06, 1.2), Vector2(0.0, 1.4)]), 4, KIND_IRON, Color(0.2, 0.2, 0.21, 0.5))

func _tint() -> Color:
	var c := Color.html(PALETTE[rng.randi() % PALETTE.size()]) * rng.randf_range(0.82, 0.98)
	c.a = 1.0
	return c

# ---------------------------------------------------------------------------------------------------------------
# The Avenida de Mayo to the Congreso
# ---------------------------------------------------------------------------------------------------------------
## The avenue's two fronts going on west from the map's last block to the Plaza del Congreso, broken by its cross
## streets, five to eight storeys with mansards and corner cupolas (its domes against the sky in a low view), and a
## lower row behind each for depth; Rivadavia's and Yrigoyen's far rows beyond those.
func _avenue_far() -> void:
	var avm := PlazaGround.pair_of(pw, "avMayo", Vector2(72.0, 100.0))
	var riv := PlazaGround.pair_of(pw, "rivadavia", Vector2(22.0, 36.0))
	var yri := PlazaGround.pair_of(pw, "yrigoyen", Vector2(132.0, 146.0))
	var front := {"floors": Vector2i(5, 8), "mansard": 0.6, "dome": 0.4, "depth": 16.0}
	var back := {"floors": Vector2i(4, 9), "mansard": 0.3, "dome": 0.06, "depth": 12.0}
	var x := -162.0
	while x > AVENUE_END + 10.0:
		var x1 := maxf(x - rng.randf_range(96.0, 118.0), AVENUE_END)
		var span := Vector2(x1, x)
		# (the Barolo stands on the south front: leave its lot)
		var spans: Array = [span]
		if BAROLO_X > span.x and BAROLO_X < span.y:
			spans = [Vector2(span.x, BAROLO_X - 16.0), Vector2(BAROLO_X + 16.0, span.y)]
		_block_rect(Rect2(span.x, avm.x - 18.0, span.y - span.x, 18.0), front, [false, true, true, true])
		for sp: Vector2 in spans:
			# (the side against the Barolo's lot no street)
			var east: bool = sp.y >= span.y - 0.01
			var west: bool = sp.x <= span.x + 0.01
			if sp.y - sp.x > 12.0: _block_rect(Rect2(sp.x, avm.y, sp.y - sp.x, 18.0), front, [true, east, false, west])
		_block_rect(Rect2(span.x, riv.y + 2.0, span.y - span.x, avm.x - 18.0 - riv.y - 4.0), back, [true, true, false, true])
		_block_rect(Rect2(span.x, avm.y + 20.0, span.y - span.x, yri.x - avm.y - 22.0), back, [false, true, true, true])
		_block_rect(Rect2(span.x, riv.x - 30.0, span.y - span.x, 28.0), back, [true, true, true, true])
		_block_rect(Rect2(span.x, yri.y + 2.0, span.y - span.x, 28.0), back, [true, true, true, true])
		x = x1 - 12.0

func _block_rect(r: Rect2, style: Dictionary, street: Array) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0: return
	_lots(_chamfer(block(r, street, style)))

## The Palacio Barolo on the avenue's south front: a tall block of offices, cream, and over it its tower climbing in
## tiers to a domed lantern with a beacon at the top (about a hundred metres up).
func _barolo() -> void:
	var avm := PlazaGround.pair_of(pw, "avMayo", Vector2(72.0, 100.0))
	var x0 := BAROLO_X - 15.0
	var z0 := avm.y
	_use(Vector2(BAROLO_X, z0 + 18.0))
	var cream := Color.html("d9cdb0")
	var body := 58.0
	cream.a = body / 100.0
	var seed := 0.731
	var a := Vector2(x0, z0)
	var b := Vector2(x0 + 30.0, z0)
	var c := Vector2(x0 + 30.0, z0 + 36.0)
	var d := Vector2(x0, z0 + 36.0)
	var mid := Vector2(BAROLO_X, z0 + 18.0)
	_wall(a, b, 0.0, body, KIND_FRONT, seed, cream, mid, 0.0)
	_wall(b, c, 0.0, body, KIND_FRONT, seed, cream, mid, 30.0)
	_wall(c, d, 0.0, body, KIND_PARTY, seed, cream, mid, 0.0)
	_wall(d, a, 0.0, body, KIND_FRONT, seed, cream, mid, 0.0)
	_roof(PackedVector2Array([a, b, c, d]), body, cream, seed)
	# the tower over the front: two square tiers, an eight-sided one, the dome, the lantern
	var t := Vector3(BAROLO_X, body, z0 + 8.0)
	var tiers: Array = [[14.0, 12.0], [10.0, 10.0]]
	var y := body
	for tier: Array in tiers:
		var w: float = tier[0]
		var h: float = tier[1]
		var tc := cream
		tc.a = (y + h) / 100.0
		var s := 0.5 * w
		var p := [Vector2(t.x - s, t.z - s), Vector2(t.x + s, t.z - s), Vector2(t.x + s, t.z + s), Vector2(t.x - s, t.z + s)]
		for i: int in range(4): _wall(p[i], p[(i + 1) % 4], y, y + h, KIND_FRONT, seed + 0.1, tc, Vector2(t.x, t.z), float(i) * w)
		_roof(PackedVector2Array(p), y + h, tc, seed)
		y += h
	var oct := cream
	oct.a = (y + 9.0) / 100.0
	_lathe(Vector3(t.x, y, t.z), PackedVector2Array([Vector2(4.6, 0.0), Vector2(4.6, 8.0), Vector2(5.2, 8.6), Vector2(4.0, 9.2)]), 8, KIND_STONE, oct)
	y += 9.2
	_lathe(Vector3(t.x, y, t.z), PackedVector2Array([Vector2(4.0, 0.0), Vector2(3.6, 2.6), Vector2(2.4, 5.0), Vector2(1.0, 6.4), Vector2(0.0, 6.8)]), 10, KIND_DOME, Color(0.42, 0.4, 0.36, (y + 7.0) / 100.0))
	_lathe(Vector3(t.x, y + 6.6, t.z), PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.9, 1.4), Vector2(0.0, 2.2)]), 6, KIND_LIGHT, Color(1.0, 0.8, 0.55))

## The Plaza del Congreso at the avenue's end and, across it, the Congreso: its long front of floodlit stone, the
## portico at its middle, the drum and the great green-bronze dome over it, the lantern on top.
func _congreso() -> void:
	var avm := PlazaGround.pair_of(pw, "avMayo", Vector2(72.0, 100.0))
	var axis := (avm.x + avm.y) * 0.5
	var x0 := CONGRESO_X - 28.0
	var x1 := CONGRESO_X + 28.0
	_use(Vector2(CONGRESO_X, axis))
	var stone := Color.html("cbc2b0")
	var seed := 0.913
	var body := 24.0
	stone.a = body / 100.0
	var z0 := axis - 46.0
	var z1 := axis + 46.0
	var mid := Vector2(CONGRESO_X, axis)
	var p := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	for i: int in range(4): _wall(p[i], p[(i + 1) % 4], 0.0, body, KIND_STONE, seed, stone, mid, 0.0)
	_roof(PackedVector2Array(p), body, stone, seed)
	# the corner pavilions a little higher
	for cz: float in [z0 + 8.0, z1 - 8.0]:
		_box(Vector3(x1 - 8.0, body + 3.0, cz), Vector3(14.0, 6.0, 14.0), KIND_STONE, Color(stone, (body + 6.0) / 100.0), seed)
	# the portico toward the avenue: columns, the pediment
	var px := x1 + 7.0
	for i: int in range(8):
		var cz := axis - 12.6 + float(i) * 3.6
		_lathe(Vector3(px, 2.0, cz), PackedVector2Array([Vector2(0.75, 0.0), Vector2(0.65, 16.0)]), 8, KIND_STONE, Color(stone, 20.0 / 100.0))
	_box(Vector3(x1 + 3.5, 1.0, axis), Vector3(9.0, 2.0, 30.0), KIND_STONE, Color(stone, 0.04), seed)
	_box(Vector3(x1 + 3.5, 19.0, axis), Vector3(9.0, 2.0, 30.0), KIND_STONE, Color(stone, 0.21), seed)
	var ped0 := Vector3(px + 1.0, 20.0, axis - 15.0)
	var ped1 := Vector3(px + 1.0, 20.0, axis + 15.0)
	var apex := Vector3(px + 1.0, 26.0, axis)
	_tri_out(ped0, ped1, apex, Vector3.RIGHT, Color(stone, 0.26), Vector2(seed, KIND_STONE))
	var back0 := Vector3(x1, 20.0, axis - 15.0)
	var back1 := Vector3(x1, 20.0, axis + 15.0)
	var backa := Vector3(x1, 26.0, axis)
	_quad_out(ped0, back0, backa, apex, (Vector3(0, 6, -15)).cross(Vector3(-1, 0, 0)).normalized() * -1.0, [Vector2(0, 0), Vector2(8, 0), Vector2(8, 16), Vector2(0, 16)], Color(0.3, 0.32, 0.3, 0.26), Vector2(seed, KIND_ROOF))
	_quad_out(apex, backa, back1, ped1, Vector3(0, 6, 15).normalized(), [Vector2(0, 0), Vector2(8, 0), Vector2(8, 16), Vector2(0, 16)], Color(0.3, 0.32, 0.3, 0.26), Vector2(seed, KIND_ROOF))
	# the drum, the dome, the lantern
	var c := Vector3(CONGRESO_X, body, axis)
	_lathe(c, PackedVector2Array([Vector2(16.0, 0.0), Vector2(16.0, 3.0), Vector2(14.0, 3.0), Vector2(14.0, 15.0), Vector2(15.0, 16.0), Vector2(13.6, 17.0)]), 20, KIND_STONE, Color(stone, (body + 17.0) / 100.0))
	var verdigris := Color(0.36, 0.48, 0.42, (body + 47.0) / 100.0)
	_lathe(c + UP * 17.0, PackedVector2Array([Vector2(13.6, 0.0), Vector2(13.2, 5.0), Vector2(11.8, 11.0), Vector2(9.2, 17.0), Vector2(5.6, 22.0), Vector2(2.4, 25.0), Vector2(0.0, 25.8)]), 20, KIND_DOME, verdigris)
	_lathe(c + UP * 41.5, PackedVector2Array([Vector2(2.6, 0.0), Vector2(2.6, 4.5), Vector2(2.9, 5.0), Vector2(1.6, 6.6), Vector2(0.0, 7.6)]), 10, KIND_STONE, Color(stone, (body + 49.0) / 100.0))
	_lathe(c + UP * 49.0, PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.06, 2.6), Vector2(0.0, 3.0)]), 4, KIND_IRON, Color(0.3, 0.3, 0.28, 0.8))
	# the plaza in front: its lamps (a glow each) and a low wall round the lawns
	for i: int in range(5):
		for side: float in [-1.0, 1.0]:
			var lx := AVENUE_END - 8.0 - float(i) * 9.0
			_lathe(Vector3(lx, 0.0, axis + side * 14.0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.08, 4.0), Vector2(0.0, 4.1)]), 4, KIND_IRON, Color(0.1, 0.1, 0.1, 0.05))
			_lathe(Vector3(lx, 4.0, axis + side * 14.0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.34, 0.3), Vector2(0.0, 0.62)]), 6, KIND_LIGHT, Color(1.0, 0.72, 0.42))

## The Obelisco at the end of the Diagonal Norte, in the Plaza de la República: the white shaft of stone, square,
## tapering, floodlit, the pyramid at its top with a small light; the plaza round it open, its lamps glowing.
func _obelisco() -> void:
	var d: Array = diagonals[0]
	var o: Vector2 = d[0]
	var dir: Vector2 = d[1]
	var at := o + dir * OBELISCO_S
	_use(at)
	var stone := Color.html("e6e1d6")
	stone.a = 0.68
	# (square: four segments turned to sit square on the Diagonal)
	var base := Vector3(at.x, 0.0, at.y)
	_lathe(base, PackedVector2Array([Vector2(5.4, 0.0), Vector2(5.4, 1.2), Vector2(4.6, 1.2), Vector2(2.6, 63.5), Vector2(0.0, 67.5)]), 4, KIND_STONE, stone, 0.21)
	_lathe(base + UP * 67.0, PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.25, 0.4), Vector2(0.0, 0.7)]), 4, KIND_LIGHT, Color(1.0, 0.25, 0.12))
	# the lamps round the plaza
	for i: int in range(10):
		var a := TAU * float(i) / 10.0
		var lp := at + Vector2(cos(a), sin(a)) * 34.0
		_lathe(Vector3(lp.x, 0.0, lp.y), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.08, 4.2), Vector2(0.0, 4.3)]), 4, KIND_IRON, Color(0.1, 0.1, 0.1, 0.05))
		_lathe(Vector3(lp.x, 4.2, lp.y), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.34, 0.3), Vector2(0.0, 0.62)]), 6, KIND_LIGHT, Color(1.0, 0.72, 0.42))

# ---------------------------------------------------------------------------------------------------------------
# The port behind the Casa Rosada
# ---------------------------------------------------------------------------------------------------------------
## Beyond Paseo Colón: the port's long brick sheds with their snowed gables, the quay's edge, the black water of the
## dock, portal cranes along the quay with a red light on each jib, a cargo ship tied up with a few lit portholes.
func _port() -> void:
	var brick := Color.html("8a4c38")
	var sheds: Array = [Vector2(-100.0, 20.0), Vector2(30.0, 110.0), Vector2(120.0, 210.0)]
	var sx0 := W + 24.0
	var sx1 := W + 60.0
	for band: Vector2 in sheds:
		var z := band.x
		while z < band.y - 10.0:
			var z1 := minf(z + rng.randf_range(34.0, 46.0), band.y)
			_shed(Rect2(sx0, z + 1.0, sx1 - sx0, z1 - z - 2.0), brick * rng.randf_range(0.8, 1.05), 8.5)
			z = z1
	# the quay's edge and the water
	var qx := sx1 + 4.0
	_use(Vector2(qx + 20.0, 60.0))
	var water_x1 := qx + 64.0
	_quad_out(Vector3(qx, 0.03, -120.0), Vector3(water_x1, 0.03, -120.0), Vector3(water_x1, 0.03, 260.0), Vector3(qx, 0.03, 260.0), UP,
		[Vector2(0, 0), Vector2(64, 0), Vector2(64, 380), Vector2(0, 380)], Color(0.1, 0.1, 0.12, 0.01), Vector2(0.2, KIND_WATER))
	_box(Vector3(qx - 0.4, 0.25, 70.0), Vector3(0.8, 0.5, 380.0), KIND_PARTY, Color(0.5, 0.48, 0.45, 0.01), 0.3)
	# portal cranes along the quay
	var rust := Color(0.22, 0.14, 0.11, 0.3)
	var z := -80.0
	while z < 240.0:
		_use(Vector2(qx, z))
		_crane(Vector3(qx, 0.0, z), rust, rng.randf_range(-0.5, 0.5))
		z += rng.randf_range(24.0, 34.0)
	# a cargo ship at the quay
	_use(Vector2(qx + 14.0, 70.0))
	_ship(Vector3(qx + 12.0, 0.0, 70.0))
	# the far side of the dock: more sheds in the dark
	for zz: float in [-90.0, 0.0, 90.0, 180.0]:
		_shed(Rect2(water_x1 + 2.0, zz, 30.0, 80.0), brick * 0.85, 9.0)

## A port shed: brick walls, a pitched roof of corrugated iron under snow, its big doors drawn as a shop front.
func _shed(r: Rect2, tint: Color, h: float) -> void:
	_use(r.get_center())
	var seed := rng.randf()
	var c := r.get_center()
	tint.a = h / 100.0
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i: int in range(4): _wall(p[i], p[(i + 1) % 4], 0.0, h, KIND_PARTY if i % 2 == 0 else KIND_COURT, seed, tint, c, 0.0)
	# the roof's ridge runs along z
	var ridge := h + r.size.x * 0.22
	var a0 := Vector3(r.position.x, h, r.position.y)
	var a1 := Vector3(r.position.x, h, r.end.y)
	var b0 := Vector3(c.x, ridge, r.position.y)
	var b1 := Vector3(c.x, ridge, r.end.y)
	var d0 := Vector3(r.end.x, h, r.position.y)
	var d1 := Vector3(r.end.x, h, r.end.y)
	var roof := Color(0.3, 0.3, 0.3, ridge / 100.0)
	_quad_out(a0, a1, b1, b0, Vector3(-0.45, 1.0, 0.0).normalized(), [Vector2(0, 0), Vector2(r.size.y, 0), Vector2(r.size.y, 9), Vector2(0, 9)], roof, Vector2(seed, KIND_ROOF))
	_quad_out(d1, d0, b0, b1, Vector3(0.45, 1.0, 0.0).normalized(), [Vector2(0, 0), Vector2(r.size.y, 0), Vector2(r.size.y, 9), Vector2(0, 9)], roof, Vector2(seed, KIND_ROOF))
	_tri_out(a0, d0, b0, Vector3(0, 0, -1), tint, Vector2(seed, KIND_PARTY))
	_tri_out(d1, a1, b1, Vector3(0, 0, 1), tint, Vector2(seed, KIND_PARTY))

## A portal crane: four legs over the quay's edge, the machine house on them, the jib reaching out over the water
## (turned a little), its counterweight behind, a red lamp at its tip.
func _crane(at: Vector3, tint: Color, turn: float) -> void:
	var legs: Array = [Vector3(-3.0, 0, -3.0), Vector3(3.0, 0, -3.0), Vector3(3.0, 0, 3.0), Vector3(-3.0, 0, 3.0)]
	var top := at + UP * 10.0
	for l: Vector3 in legs:
		_beam(at + l, top + l * 0.55, 0.45, tint)
	_beam(top + Vector3(-1.7, 0, -1.7), top + Vector3(1.7, 0, 1.7), 0.4, tint)
	_beam(top + Vector3(-1.7, 0, 1.7), top + Vector3(1.7, 0, -1.7), 0.4, tint)
	var house := top + UP * 1.8
	_box(house, Vector3(4.0, 3.4, 4.0), KIND_IRON, Color(0.32, 0.26, 0.22, 0.14), 0.4)
	var out := Vector3(cos(turn), 0.0, sin(turn))
	var root := house + UP * 1.2
	var tip := root + out * 24.0 + UP * 12.0
	_beam(root, tip, 0.7, tint)
	_beam(house + UP * 4.0, tip, 0.18, Color(0.1, 0.1, 0.1, 0.3))
	_beam(root, root + UP * 4.5, 0.4, tint)
	_beam(root, root - out * 7.0 + UP * 1.0, 0.6, tint)
	_box(root - out * 7.0 + UP * 0.6, Vector3(2.0, 1.6, 2.0), KIND_IRON, Color(0.2, 0.2, 0.2, 0.12), 0.4)
	# the hook's cable hanging from the tip
	_beam(tip, tip - UP * 9.0, 0.06, Color(0.08, 0.08, 0.08, 0.3))
	_lathe(tip + UP * 0.2, PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.3, 0.3), Vector2(0.0, 0.56)]), 6, KIND_LIGHT, Color(1.0, 0.16, 0.08))

## A cargo ship along the quay: a black hull pointed at its bow, its white superstructure aft with lit cabins (the
## front drawing), the funnel, the masts, a lamp at the masthead, portholes lit along the hull.
func _ship(at: Vector3) -> void:
	var hull := Color(0.08, 0.08, 0.09, 0.07)
	var half := 7.0
	var length := 86.0
	var z0 := at.z - length * 0.5
	var z1 := at.z + length * 0.5
	var bow := z1 + 10.0
	var deck := 6.5
	var plan: Array = [Vector2(at.x - half, z0), Vector2(at.x + half, z0), Vector2(at.x + half, z1), Vector2(at.x, bow), Vector2(at.x - half, z1)]
	var c := Vector2(at.x, at.z)
	for i: int in range(plan.size()):
		_wall(plan[i], plan[(i + 1) % plan.size()], -0.5, deck, KIND_PARTY, 0.2, hull, c, 0.0)
	_roof(PackedVector2Array(plan.slice(0, 3)), deck, Color(0.3, 0.27, 0.24, 0.07), 0.2)
	_roof(PackedVector2Array([plan[2], plan[3], plan[4], plan[0]]), deck, Color(0.3, 0.27, 0.24, 0.07), 0.2)
	var white := Color(0.78, 0.76, 0.7, (deck + 10.0) / 100.0)
	_box(Vector3(at.x, deck + 5.0, z0 + 14.0), Vector3(12.0, 10.0, 16.0), KIND_FRONT, white, 0.66)
	_lathe(Vector3(at.x, deck + 10.0, z0 + 11.0), PackedVector2Array([Vector2(2.2, 0.0), Vector2(2.0, 6.0)]), 10, KIND_PARTY, Color(0.12, 0.12, 0.12, 0.2))
	for mz: float in [z0 + 40.0, z0 + 70.0]:
		_beam(Vector3(at.x, deck, mz), Vector3(at.x, deck + 16.0, mz), 0.35, Color(0.18, 0.16, 0.14, 0.2))
		_beam(Vector3(at.x, deck + 9.0, mz), Vector3(at.x + 10.0, deck + 3.0, mz + 3.0), 0.22, Color(0.18, 0.16, 0.14, 0.2))
	_lathe(Vector3(at.x, deck + 16.2, z0 + 70.0), PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.28, 0.3), Vector2(0.0, 0.55)]), 6, KIND_LIGHT, Color(1.0, 0.85, 0.6))
	for i: int in range(9):
		var pz := z0 + 22.0 + float(i) * 6.0
		if rng.randf() < 0.55:
			_box(Vector3(at.x - half - 0.02, deck - 1.6, pz), Vector3(0.05, 0.5, 0.5), KIND_LIGHT, Color(1.0, 0.72, 0.4), 0.1)

# ---------------------------------------------------------------------------------------------------------------
# The streets beyond the ground's masks
# ---------------------------------------------------------------------------------------------------------------
## The avenue's carriageway and its cross streets west of where the ground's map ends, slush and wet setts, and the
## ground's own snow (PlazaGround) everywhere else.
func _far_streets() -> void:
	# the Diagonal Norte from where the ground's own streets end out to the Obelisco's plaza
	var d: Array = diagonals[0]
	var o: Vector2 = d[0]
	var dir: Vector2 = d[1]
	var hw: float = d[2]
	var m := Vector2(-dir.y, dir.x)
	var s0 := 110.0
	while s0 < OBELISCO_S - 30.0:
		var s1 := minf(s0 + 60.0, OBELISCO_S - 30.0)
		var a0 := o + dir * s0
		var a1 := o + dir * s1
		_use((a0 + a1) * 0.5)
		_quad_out(Vector3(a0.x - m.x * hw, 0.02, a0.y - m.y * hw), Vector3(a1.x - m.x * hw, 0.02, a1.y - m.y * hw), Vector3(a1.x + m.x * hw, 0.02, a1.y + m.y * hw), Vector3(a0.x + m.x * hw, 0.02, a0.y + m.y * hw), UP,
			[Vector2(s0, 0.0), Vector2(s1, 0.0), Vector2(s1, hw * 2.0), Vector2(s0, hw * 2.0)], Color(0.5, 0.5, 0.52, 0.0), Vector2(0.5, KIND_STREET))
		s0 = s1
	var avm := PlazaGround.pair_of(pw, "avmRoad", Vector2(77.0, 95.0))
	var riv := PlazaGround.pair_of(pw, "rivRoad", Vector2(25.5, 32.5))
	var yri := PlazaGround.pair_of(pw, "yriRoad", Vector2(135.5, 142.5))
	var x0 := -150.0
	var x1 := AVENUE_END - 50.0
	for band: Vector2 in [avm, riv, yri]:
		var x := x0
		while x > x1:
			var xe := maxf(x - CHUNK, x1)
			_use(Vector2((x + xe) * 0.5, band.x))
			_quad_out(Vector3(xe, 0.02, band.x), Vector3(x, 0.02, band.x), Vector3(x, 0.02, band.y), Vector3(xe, 0.02, band.y), UP,
				[Vector2(xe, 0.0), Vector2(x, 0.0), Vector2(x, band.y - band.x), Vector2(xe, band.y - band.x)], Color(0.5, 0.5, 0.52, 0.0), Vector2(0.5, KIND_STREET))
			x = xe

# ---------------------------------------------------------------------------------------------------------------
# What the kit draws: trees, lamps, the traffic
# ---------------------------------------------------------------------------------------------------------------
## Plane trees down the avenue and along Paseo Colón, lamps down the far avenue and the Diagonales, cars and taxis
## parked under the snow along the streets beyond the map, trams and colectivos stopped on them in the snow (lit),
## all from the square's kit (call before it finishes). Returns the vehicles' nodes, for fold().
static func furnish(pk: RefCounted, p_pw: Dictionary, p_w: float, p_h: float, fleet: Dictionary = {}) -> Array[Node3D]:
	var r := RandomNumberGenerator.new()
	r.seed = 19581224
	var avm := PlazaGround.pair_of(p_pw, "avmRoad", Vector2(77.0, 95.0))
	# plane trees on the avenue's pavements and on Paseo Colón's
	var x := -20.0
	while x > AVENUE_END + 6.0:
		for z: float in [avm.x - 2.0, avm.y + 2.0]:
			pk.plane_tree(Vector3(x + r.randf_range(-1.0, 1.0), 0.0, z), r.randf_range(0.85, 1.1))
		x -= r.randf_range(11.0, 14.0)
	var z := -80.0
	while z < p_h + 70.0:
		for px: float in [p_w + 4.5, p_w + 21.5]:
			if r.randf() < 0.85: pk.plane_tree(Vector3(px, 0.0, z + r.randf_range(-1.0, 1.0)), r.randf_range(0.85, 1.05))
		z += r.randf_range(12.0, 15.0)
	# the far avenue's double lanterns, single lamps down the Diagonales
	x = -162.0
	while x > AVENUE_END:
		for zz: float in [avm.x + 0.8, avm.y - 0.8]:
			pk.lamp_post(Vector3(x, 0.0, zz), 2)
		x -= 26.0
	for d: Array in diagonal_lines():
		var o: Vector2 = d[0]
		var dir: Vector2 = d[1]
		var hw: float = d[2]
		var m := Vector2(-dir.y, dir.x)
		var s := 20.0
		while s < 200.0:
			for side: float in [-1.0, 1.0]:
				var at := o + dir * s + m * side * (hw - 1.0)
				pk.lamp_post(Vector3(at.x, 0.0, at.y), 0)
			s += 28.0
	# parked: [start (x, z), step (x, z), count, yaw]
	var nb := PlazaGround.NORTH_STREET
	var rows: Array = [
		[Vector2(-140.0, nb + 1.3), Vector2(13.0, 0.0), 30, PI * 0.5], [Vector2(-130.0, nb + 6.7), Vector2(14.0, 0.0), 28, -PI * 0.5],
		[Vector2(-84.7, -60.0), Vector2(0.0, 14.0), 16, PI], [Vector2(-5.3, -50.0), Vector2(0.0, 15.0), 6, 0.0],
		[Vector2(-160.0, avm.x + 1.6), Vector2(-15.0, 0.0), 24, -PI * 0.5], [Vector2(-168.0, avm.y - 1.6), Vector2(-16.0, 0.0), 22, PI * 0.5],
		[Vector2(p_w + 7.3, -70.0), Vector2(0.0, 14.0), 22, PI], [Vector2(p_w + 18.7, -60.0), Vector2(0.0, 15.0), 20, 0.0],
		[Vector2(-140.0, p_h + 37.3), Vector2(16.0, 0.0), 26, PI * 0.5],
	]
	var kinds := ["sedan", "sedan", "taxi", "sedan", "saloon", "taxi", "microcar", "pickup", "van", "sedan", "work_pickup"]
	var out: Array[Node3D] = []
	var n := 0
	for row: Array in rows:
		var at: Vector2 = row[0]
		var step: Vector2 = row[1]
		for i: int in range(int(row[2])):
			var p := at + step * float(i) + step.normalized() * r.randf_range(-2.0, 2.0)
			if r.randf() < 0.3:
				var kind: String = kinds[r.randi() % kinds.size()]
				var model := period_car(kind, n)
				n += 1
				if has_vehicle(model):
					# the cars of the time (their front is -z: turned half round), parked, their lamps out
					if not fleet.has(model): fleet[model] = []
					(fleet[model] as Array).append([Transform3D(Basis(Vector3.UP, float(row[3]) + PI), Vector3(p.x, 0.0, p.y)), period_paint(model, n), 0.0])
				else:
					out.append(pk.car(Vector3(p.x, 0.0, p.y), float(row[3]), kind if kind in ["sedan", "taxi", "saloon"] else "sedan"))
	# the traffic stopped in the snow beyond the map: trams on Paseo Colón and the street behind the ministries,
	# colectivos, a taxi waiting with its lamps on
	out.append(pk.tram(Vector3(p_w + 11.5, 0.0, 30.0), PI, true, 5.9))
	out.append(pk.tram(Vector3(60.0, 0.0, p_h + 41.0), PI * 0.5, true, 5.9))
	# the Línea 60's colectivos stopped in the snow on the streets beyond, lit
	for bus: Array in [[Vector3(p_w + 15.0, 0.0, 120.0), 0.0], [Vector3(40.0, 0.0, nb + 4.0), -PI * 0.5], [Vector3(-300.0, 0.0, avm.x + 5.0), -PI * 0.5], [Vector3(-120.0, 0.0, avm.y - 4.0), PI * 0.5]]:
		if has_vehicle("colectivo60_far"):
			if not fleet.has("colectivo60_far"): fleet["colectivo60_far"] = []
			(fleet["colectivo60_far"] as Array).append([Transform3D(Basis(Vector3.UP, float(bus[1])), bus[0]), Color(0, 0, 0), 1.0])
		else:
			out.append(pk.colectivo(bus[0], float(bus[1]), Color(0, 0, 0, 0), Color(0, 0, 0, 0), true, false, true))
	# two taxis waiting, their lamps on
	for taxi: Array in [[Vector3(-44.0, 0.0, avm.y - 5.0), PI * 0.5], [Vector3(p_w + 10.0, 0.0, 150.0), PI]]:
		if has_vehicle("taxi49"):
			if not fleet.has("taxi49"): fleet["taxi49"] = []
			(fleet["taxi49"] as Array).append([Transform3D(Basis(Vector3.UP, float(taxi[1]) + PI), taxi[0]), Color.html(TAXI_BLACK), 0.5])
		else:
			out.append(pk.car(taxi[0], float(taxi[1]), "taxi", Color(0, 0, 0, 0), [], true, false))
	return out

## The cars of the time out in the streets (tools/vehicles.gd makes them: the friends' microcar and pickup, and the
## six made on their generator, art/vehicles/source/build_vehicles_1950s.py), for the kit's kinds of car: a taxi is
## the black and yellow one, the kit's small saloon the microcar, its sedans the big sedans, coupés and small saloons
## of the forties and fifties with now and then a pickup or a van. "" when the kind is none of theirs.
static func period_car(kind: String, i: int) -> String:
	match kind:
		"taxi": return "taxi49"
		"saloon", "microcar": return "microcar"
		"work_pickup": return "work_pickup"
		"pickup": return "pickup51"
		"van": return "van51"
		"sedan":
			if i % 5 == 1: return "work_pickup"
			return PERIOD_SEDANS[i % PERIOD_SEDANS.size()]
	return ""

## Whether a vehicle's model is in this build (the open one may come without the friends' models: the kit's own cars
## stand in for them).
static func has_vehicle(model: String) -> bool:
	return model != "" and ResourceLoader.exists(VEHICLES + model + ".res")

## A car's paint: a taxi black (its roof is yellow in the model), a working vehicle in work colours, the rest in the
## sober colours of the fifties: black, dark green, navy, maroon, cream, grey.
static func period_paint(model: String, i: int) -> Color:
	if model == "taxi49": return Color.html(TAXI_BLACK)
	if model in ["work_pickup", "pickup51", "van51"]: return Color.html(WORK_PAINTS[i % WORK_PAINTS.size()])
	return Color.html(CAR_PAINTS[(i * 7) % CAR_PAINTS.size()])

## Kit pieces (their "Body" and "Detail" meshes) as parts for fold(): [mesh, transform], the pieces freed.
static func parts_of(pieces: Array[Node3D]) -> Array:
	var out: Array = []
	for piece: Node3D in pieces:
		if piece == null or not is_instance_valid(piece): continue
		for child: Node in piece.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				out.append([(child as MeshInstance3D).mesh, piece.transform * (child as MeshInstance3D).transform])
		if piece.get_parent() != null: piece.get_parent().remove_child(piece)
		piece.queue_free()
	return out

## The instances of a multimesh as parts for fold(), the multimesh's node freed.
static func parts_of_multimesh(node: MultiMeshInstance3D) -> Array:
	var out: Array = []
	var mm := node.multimesh
	for i: int in range(mm.instance_count): out.append([mm.mesh, node.transform * mm.get_instance_transform(i)])
	if node.get_parent() != null: node.get_parent().remove_child(node)
	node.queue_free()
	return out

## Folds parts ([mesh, transform], from any number of the kit's pieces and multimeshes) into one mesh per district and
## material: the rows beyond the map, the parked cars and the far traffic, the avenues' trees and lamps, in two draws
## a district (they all share the kit's two materials). The districts over `near` cast shadows, the rest do not.
static func fold(parts: Array, into: Node3D, name_prefix: String, near: Rect2, chunk: float = FOLD_CHUNK) -> int:
	var groups: Dictionary = {}
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var key := Vector2i(int(floor(xf.origin.x / chunk)), int(floor(xf.origin.z / chunk)))
		for s: int in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			var gkey := "%d_%d_%d" % [key.x, key.y, mat.get_instance_id()]
			if not groups.has(gkey):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[gkey] = {"st": st, "mat": mat, "key": key, "tris": 0}
			var g: Dictionary = groups[gkey]
			(g.st as SurfaceTool).append_from(mesh, s, xf)
			g.tris = int(g.tris) + mesh.surface_get_array_index_len(s) / 3
	var tris := 0
	for gkey: String in groups:
		var g: Dictionary = groups[gkey]
		var st := g.st as SurfaceTool
		st.set_material(g.mat)
		var k: Vector2i = g.key
		var node := MeshInstance3D.new()
		node.name = "%s_%d_%d" % [name_prefix, k.x, k.y]
		node.mesh = st.commit()
		var area := Rect2(float(k.x) * chunk, float(k.y) * chunk, chunk, chunk)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if area.intersects(near) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		into.add_child(node)
		tris += int(g.tris)
	return tris
