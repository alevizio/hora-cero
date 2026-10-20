extends RefCounted
## The houses of La Boca on the snowy night of Operation Riachuelo, built lot by lot from the plan (boca_plan.gd):
## conventillos of corrugated iron painted in strong boat colours, with wooden galleries and tin stovepipes; Italianate
## fronts of lime render with plinths, string courses, cornices, balustraded parapets, iron balconies and louvred
## shutters; brick workshops and the far bank's warehouses; the chamfered corners with the almacén's or the bar's lit
## door and its painted sign; flat roofs (azoteas) with chimneys, stair huts and water tanks; the patios inside the
## blocks with a shed, the washing, a snowman. Snow lies on every surface that faces up (boca_surface.gdshader).
##
## Every lot is committed with the others of its group (about 25 m of a block): the walls and roofs, which cast
## shadows, and the details (windows, signs, railings), which do not; both thin out when somebody stands behind them.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Plan = preload("res://scripts/three_d/boca_plan.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")

## The facade atlas (tools/gen_boca_textures.py, ATLAS): x, y, w, h in pixels of 1024.
const ATLAS := {
	"win_lit0": [0, 0, 128, 256], "win_lit1": [128, 0, 128, 256], "win_lit2": [256, 0, 128, 256],
	"win_lit3": [384, 0, 128, 256], "win_lit4": [512, 0, 128, 256],
	"win_dark0": [640, 0, 128, 256], "win_dark1": [768, 0, 128, 256], "win_dark2": [896, 0, 128, 256],
	"shutter_louvre": [0, 256, 128, 256], "shutter_panel": [128, 256, 128, 256], "door_double": [256, 256, 128, 256],
	"door_zaguan": [384, 256, 128, 256], "door_shop_lit": [512, 256, 128, 256], "door_roller": [640, 256, 128, 256],
	"win_small_lit": [768, 256, 128, 128], "win_small_dark": [768, 384, 128, 128],
	"win_conv_lit": [896, 256, 128, 128], "win_conv_dark": [896, 384, 128, 128],
	"sign_cafe": [0, 512, 512, 128], "sign_almacen": [512, 512, 512, 128], "sign_bar": [0, 640, 512, 128],
	"sign_despacho": [512, 640, 512, 128],
	"rail_iron": [0, 768, 256, 128], "rail_wood": [256, 768, 256, 128], "awning_green": [512, 768, 256, 128],
	"awning_red": [768, 768, 256, 128],
	"filete_band": [0, 896, 256, 128], "poster_baile": [256, 896, 128, 128], "poster_alquila": [384, 896, 128, 128],
	"tram_dest": [512, 896, 256, 64], "tram_win_lit": [512, 960, 128, 64], "shop_lit": [640, 960, 128, 64],
	"porthole_lit": [768, 896, 64, 64], "porthole_dark": [832, 896, 64, 64], "balustrade": [896, 896, 128, 64],
	"arch_lit": [768, 960, 64, 64], "arch_dark": [832, 960, 64, 64], "plate_guardia": [896, 960, 128, 64],
}

## Washing on the line: a plain patch of the atlas (the poster's paper margin), tinted by the vertex colour.
const CLOTH_UV := Rect2(386.0 / 1024.0, 898.0 / 1024.0, 6.0 / 1024.0, 6.0 / 1024.0)
## La Boca's paint in 1958 (sRGB): before the 1959 ordinance and Quinquela's commission, the iron houses were painted
## "mainly red and green" with what the shipyards left over, one colour a house, next to galvanised iron gone grey
## and bare timber; a blue or an ochre here and there. The rendered fronts inland: creams, sands, faded pinks, greys.
const CONV_PAINT := ["b5584a", "c46a50", "9c4a3e", "5d8a68", "6f9c78", "84a888", "a6b0aa", "b8bcb4", "c0a07c", "9a8468", "6a8aa8",
	"d0a85a", "b5584a", "6f9c78", "c46a50", "5d8a68"]
const ITAL_PAINT := ["d8ccb0", "c9b48a", "c49a86", "b8b4a4", "a8a090", "d0c098", "b07a5e", "9aa88e", "c6bca8", "c8b8a0"]
const TRIM := ["e8e2d4", "2f5a3c", "8e3328", "2d4e7a", "c8a040", "e8e2d4", "1f3a2c", "5a4a3a"]
const SHUTTER := ["4f7a52", "6a4a34", "6f8296", "2f5a3e", "8a8f88", "3e5f7a"]
const ROOF := ["8a8a86", "7a4a3a", "6a706a", "8a5a3e", "5a6a72", "9a9690"]

var b: Node3D
var plan: Plan
var rng := RandomNumberGenerator.new()
## The squad's courtyard (walkable): the conventillo's galleries all face it.
var courtyard := Rect2()
## Cars standing in workshop yards inside the blocks: [position, yaw] (the street module builds them with the rest).
var yard_cars: Array = []
## Chimney tops (for smoke), wall lamps [position, outward normal], the tree spots in the patios.
var chimneys: Array[Vector3] = []
var wall_lamps: Array = []
var trees: Array[Vector3] = []
var tree_room: Array[float] = []
var palms: Array[Vector3] = []
## Triangles built, for the record.
var triangles: int = 0

func _init(owner: Node3D, p: Plan) -> void:
	b = owner
	plan = p

static func hexc(h: String, linear: bool = true) -> Color:
	var c := Color.html(h)
	return c.srgb_to_linear() if linear else c

static func uv(cell: String) -> Rect2:
	var r: Array = ATLAS[cell]
	return Rect2((float(r[0]) + 1.0) / 1024.0, (float(r[1]) + 1.0) / 1024.0, (float(r[2]) - 2.0) / 1024.0, (float(r[3]) - 2.0) / 1024.0)

## A part of an atlas cell (u0..u1 across, v0..v1 down, 0..1 of the cell).
static func uv_part(cell: String, u0: float, u1: float, v0: float = 0.0, v1: float = 1.0) -> Rect2:
	var r := uv(cell)
	return Rect2(r.position.x + r.size.x * u0, r.position.y + r.size.y * v0, r.size.x * (u1 - u0), r.size.y * (v1 - v0))

func build() -> void:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for lot: Plan.Lot in plan.lots:
		if not groups.has(lot.group):
			groups[lot.group] = []
			order.append(lot.group)
		(groups[lot.group] as Array).append(lot)
	for key: String in order:
		var k := Kit.new()
		var kd := Kit.new()
		for lot: Plan.Lot in groups[key]:
			rng.seed = lot.seed
			_lot(lot, k, kd)
		var piece: Node3D = b.node("Block_" + key)
		triangles += k.triangle_count() + kd.triangle_count()
		b.commit(k, piece, "Walls", true, not (groups[key][0] as Plan.Lot).outer)
		b.commit(kd, piece, "Detail", false, not (groups[key][0] as Plan.Lot).outer)
		b.buildings.append({"node": piece, "roof": piece, "id": key})
	var pk := Kit.new()
	var pd := Kit.new()
	var n := 0
	for patio: Rect2 in plan.patios:
		rng.seed = 7700 + n
		_patio(patio, pk, pd, n)
		n += 1
		if pk.triangle_count() > 9000 or n == plan.patios.size():
			triangles += pk.triangle_count() + pd.triangle_count()
			b.commit(pk, b, "Patios", true, false)
			b.commit(pd, b, "PatioDetail", false, false)
			pk = Kit.new()
			pd = Kit.new()
	_steps()

# ---------------------------------------------------------------------------------------------------------------
# A lot
# ---------------------------------------------------------------------------------------------------------------
class Edge:
	extends RefCounted
	var o := Vector3.ZERO
	var r := Vector3.RIGHT
	var n := Vector3.BACK
	var w: float = 1.0
	var kind: String = "party"
	var index: int = 0
	func at(x: float, y: float, out: float = 0.0) -> Vector3:
		return o + r * x + Vector3.UP * y + n * out

func _edge(lot: Plan.Lot, i: int) -> Edge:
	var e := Edge.new()
	var a: Vector2 = lot.poly[i]
	var d: Vector2 = lot.poly[(i + 1) % lot.poly.size()]
	e.o = Vector3(a.x, 0.0, a.y)
	e.r = Vector3(d.x - a.x, 0.0, d.y - a.y).normalized()
	e.n = Vector3(-e.r.z, 0.0, e.r.x)
	e.w = a.distance_to(d)
	e.kind = lot.edges[i]
	e.index = i
	return e

func _lot(lot: Plan.Lot, k: Kit, kd: Kit) -> void:
	var paint: Color
	var paint2: Color
	var wall_key := "stucco"
	match lot.style:
		"conv":
			wall_key = "chapa"
			paint = hexc(CONV_PAINT[rng.randi() % CONV_PAINT.size()])
			paint2 = hexc(CONV_PAINT[rng.randi() % CONV_PAINT.size()]) if rng.randf() < 0.55 else paint
		"ital":
			paint = hexc(ITAL_PAINT[rng.randi() % ITAL_PAINT.size()])
			paint2 = paint
		"brick", "shed", "machine-house":
			wall_key = "brick"
			paint = Color(1.0, 0.97, 0.94) * rng.randf_range(0.8, 1.0)
			if lot.style == "shed" and rng.randf() < 0.5:
				# a warehouse of corrugated iron, painted long ago
				wall_key = "chapa"
				paint = hexc(["a8564a", "8a9a8a", "c0a060", "7a8a9a", "9a7a64"][rng.randi() % 5])
			paint2 = paint
		"guardia":
			paint = hexc("b9b2a0")
			paint2 = paint
		"boat-shed":
			wall_key = "planks"
			paint = hexc("b4936e")
			paint2 = paint
	paint.a = 1.0
	var trim := hexc(TRIM[rng.randi() % TRIM.size()])
	var spec := {"paint": paint, "paint2": paint2, "trim": trim, "wall": wall_key,
		"shutter": hexc(SHUTTER[rng.randi() % SHUTTER.size()]), "lit": _lit_chance(lot), "f1": _f1(lot)}
	for i: int in range(lot.poly.size()):
		var e := _edge(lot, i)
		match e.kind:
			"front": _front(lot, e, k, kd, spec)
			"chamfer": _chamfer_face(lot, e, k, kd, spec)
			"back": _back(lot, e, k, kd, spec)
			_: _party(lot, e, k, spec)
	match lot.roof:
		"flat": _roof_flat(lot, k, kd, spec)
		"gable": _roof_gable(lot, k, spec, false)
		"gable_end": _roof_gable(lot, k, spec, true)

func _lit_chance(lot: Plan.Lot) -> float:
	match lot.style:
		"conv": return 0.56
		"ital": return 0.5
		"guardia": return 0.62
		"machine-house": return 0.9
		"shed": return 0.3
	return 0.5 if lot.style == "boat-shed" else 0.2

## Height of the first floor.
func _f1(lot: Plan.Lot) -> float:
	if lot.floors <= 1: return lot.height
	return clampf(lot.height / float(lot.floors) + 0.25, 3.4, 4.6)

## A wall without openings (against a neighbour): only its top shows, over a lower roof.
func _party(lot: Plan.Lot, e: Edge, k: Kit, spec: Dictionary) -> void:
	if e.w < 0.05: return
	var key := "brick" if lot.style in ["ital", "guardia"] and rng.randf() < 0.5 else str(spec.wall)
	k.push_tint(spec.paint if key != "brick" else Color(0.9, 0.86, 0.82))
	k.quad_m(key, e.at(0, 0), e.at(e.w, 0), e.at(e.w, lot.height), e.at(0, lot.height), Vector2(e.o.x * Kit.UV_M + e.o.z * Kit.UV_M, 0.0), Color(0.55, 0.53, 0.5), Color.WHITE)
	k.pop_tint()

# ---------------------------------------------------------------------------------------------------------------
# Fronts
# ---------------------------------------------------------------------------------------------------------------
## The openings of a front: [{rect, kind, floor, cell, lit}] in wall coordinates (x along, y up).
func _openings(lot: Plan.Lot, e: Edge, spec: Dictionary, back: bool) -> Array:
	var out: Array = []
	var W := e.w
	if W < 2.2: return out
	var f1: float = spec.f1
	var bay := 2.4 if lot.style == "ital" or lot.style == "guardia" else 2.2
	if lot.style == "shed": bay = 4.2
	var n := maxi(1, int(floor((W - 0.6) / bay)))
	var lit: float = spec.lit
	var door_i := -1 if back else (n / 2 if n > 2 else 0)
	if lot.corner != "" and not back: door_i = -1
	for f: int in range(lot.floors):
		for i: int in range(n):
			var x := (float(i) + 0.5) * W / float(n)
			if back and rng.randf() < 0.45: continue
			var o := {"floor": f, "lit": rng.randf() < lit * (1.25 if f > 0 else 0.85)}
			match lot.style:
				"ital", "guardia":
					if f == 0 and i == door_i:
						o.kind = "door"
						o.rect = Rect2(x - 0.68, 0.0, 1.36, minf(3.0, f1 - 0.6))
						o.cell = "door_zaguan" if rng.randf() < 0.4 else "door_double"
						o.lit = false
					elif f == 0:
						o.kind = "win"
						o.rect = Rect2(x - 0.55, 0.75, 1.1, minf(2.3, f1 - 1.3))
					else:
						var y0 := f1 + float(f - 1) * (lot.height - f1) / float(lot.floors - 1) + 0.3
						o.kind = "win"
						o.balcony = rng.randf() < 0.55 and not back
						o.rect = Rect2(x - 0.55, y0, 1.1, minf(2.4, (lot.height - f1) / float(lot.floors - 1) - 0.6))
						if back:
							o.rect = Rect2(x - 0.45, y0 + 0.5, 0.9, 1.3)
				"conv":
					# on its piles: the floor a metre up, steps to the door
					var up0 := PILES if _on_piles(lot, back) else 0.0
					if f == 0 and i == door_i:
						o.kind = "door"
						o.rect = Rect2(x - 0.5, up0, 1.0, minf(2.25, f1 - up0 - 0.25))
						o.cell = "door_double"
						o.lit = false
					elif f == 0:
						o.kind = "win"
						o.rect = Rect2(x - 0.45, up0 + 0.85, 0.9, minf(1.3, f1 - up0 - 1.05))
					else:
						var fh := (lot.height - f1) / float(maxi(1, lot.floors - 1))
						o.kind = "win"
						o.rect = Rect2(x - 0.45, f1 + float(f - 1) * fh + 0.85, 0.9, 1.3)
				"brick", "machine-house":
					if f == 0 and i == door_i and lot.style == "brick":
						o.kind = "door"
						o.rect = Rect2(x - 1.2, 0.0, 2.4, minf(3.2, lot.height - 1.4))
						o.cell = "door_roller"
						o.lit = false
					else:
						o.kind = "arch"
						o.rect = Rect2(x - 0.6, 1.8, 1.2, minf(2.0, lot.height - 2.6))
						o.lit = rng.randf() < lit
				"shed":
					if i % 2 == 0 and f == 0 and not back:
						o.kind = "door"
						o.rect = Rect2(x - 1.6, 0.0, 3.2, minf(3.8, lot.height - 1.6))
						o.cell = "door_roller"
						o.lit = false
					else:
						o.kind = "arch"
						o.rect = Rect2(x - 0.7, 2.2, 1.4, minf(2.2, lot.height - 3.0))
				"boat-shed":
					if f == 0 and i == door_i:
						o.kind = "door"
						o.rect = Rect2(x - 1.5, 0.0, 3.0, 3.0)
						o.cell = "door_roller"
						o.lit = false
					else:
						o.kind = "win"
						o.rect = Rect2(x - 0.45, 1.3, 0.9, 1.0)
			if o.has("rect"): out.append(o)
	# the corner shop's windows: the bay next to the cut corner shows its counter
	if lot.corner != "" and not back and out.size() > 0:
		var near: Dictionary = out[0] if _edge_meets_chamfer(lot, e, true) else out[_last_ground(out)]
		if int(near.floor) == 0:
			near.kind = "shopwin"
			near.lit = true
	return out

## How high a sheet-iron house stands on its timber piles (Página/12, M2: "a metre or more above the ground").
const PILES := 0.9

func _on_piles(lot: Plan.Lot, back: bool) -> bool:
	return lot.style == "conv" and not back and not lot.outer and lot.floors >= 2

static func _last_ground(list: Array) -> int:
	var j := 0
	for i: int in range(list.size()):
		if int(list[i].floor) == 0: j = i
	return j

## Does this edge start (at_start) or end at the lot's chamfer?
static func _edge_meets_chamfer(lot: Plan.Lot, e: Edge, at_start: bool) -> bool:
	var prev := (e.index + lot.edges.size() - 1) % lot.edges.size()
	return lot.edges[prev] == "chamfer" if at_start else lot.edges[(e.index + 1) % lot.edges.size()] == "chamfer"

func _front(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary) -> void:
	var openings := _openings(lot, e, spec, false)
	_wall_with(lot, e, k, kd, spec, openings, false)
	match lot.style:
		"ital", "guardia": _ital_dress(lot, e, k, kd, spec, true)
		"conv": _conv_dress(lot, e, k, kd, spec, openings)
		"brick", "shed", "machine-house": _brick_dress(lot, e, k, spec)
	if not lot.outer: _drifts(lot, e, k, openings)
	if not lot.outer and e.w > 5.0 and rng.randf() < 0.36 and lot.style != "shed":
		wall_lamps.append([e.at(e.w * (0.15 if rng.randf() < 0.5 else 0.85), minf(3.7, spec.f1 - 0.3), 0.0), e.n])
	if not lot.outer and e.w > 4.0 and rng.randf() < 0.1 and lot.style in ["conv", "brick"]:
		_poster(e, kd, rng.randf_range(0.8, e.w - 0.8))

## Snow banked against the foot of a front, in stretches, clear of the doors and their steps.
func _drifts(lot: Plan.Lot, e: Edge, k: Kit, openings: Array) -> void:
	var gaps: Array[Vector2] = []
	for o: Dictionary in openings:
		if str(o.kind) in ["door", "shopwin"] and int(o.floor) == 0:
			var r: Rect2 = o.rect
			gaps.append(Vector2(r.position.x - 0.5, r.end.x + 0.5))
	var x := rng.randf_range(0.0, 0.8)
	var out0 := -0.1 if _on_piles(lot, false) else 0.0
	if not lot.outer and e.w > 5.0 and rng.randf() < 0.07 and not _on_piles(lot, false):
		# a sled stood up against the front, out of the way
		var xs := rng.randf_range(0.8, e.w - 0.8)
		var clear := true
		for g: Vector2 in gaps:
			if xs > g.x - 0.5 and xs < g.y + 0.5: clear = false
		if clear: sled(k, e.at(xs, 0.0, 0.3), atan2(-e.n.x, -e.n.z), 1.1)
	while x < e.w - 0.6:
		var l := rng.randf_range(1.2, 3.6)
		var x1 := minf(x + l, e.w - 0.05)
		var blocked := false
		for g: Vector2 in gaps:
			if x1 > g.x and x < g.y:
				blocked = true
				x = g.y
				break
		if not blocked:
			if rng.randf() < 0.75:
				Snow.drift(k, e.at(x, 0.0, out0), e.at(x1, 0.0, out0), e.n, rng.randf_range(0.16, 0.34), rng.randf_range(0.32, 0.55), rng)
			x = x1 + rng.randf_range(0.2, 1.2)

func _back(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary) -> void:
	var openings := _openings(lot, e, spec, true)
	_wall_with(lot, e, k, kd, spec, openings, true)
	if lot.style == "conv" and lot.floors > 1 and e.w > 4.0 and rng.randf() < 0.5 and not lot.outer:
		_gallery(lot, e, k, kd, spec, openings)

## The wall of a front or a back with its openings cut out, each opening filled (glass, a door, shutters), sills and
## caps that hold the snow.
func _wall_with(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, openings: Array, back: bool) -> void:
	if lot.outer or back:
		# (the backs onto the patios are seen only from high up, and the city round the map from afar)
		_flat_wall(lot, e, k, kd, spec, openings)
		return
	var rects: Array = []
	for o: Dictionary in openings: rects.append(o.rect)
	var key: String = spec.wall
	var reveal := 0.16 if key != "chapa" else 0.08
	var u0 := e.o.x + e.o.z
	var f1: float = spec.f1
	if _on_piles(lot, back):
		_piles(lot, e, k, spec, openings)
		var low2: Array = []
		var high2: Array = []
		for r: Rect2 in rects:
			if r.position.y < f1: low2.append(Rect2(r.position.x, r.position.y - PILES, r.size.x, r.size.y))
			else: high2.append(Rect2(r.position.x, r.position.y - f1, r.size.x, r.size.y))
		k.push_tint(spec.paint)
		k.wall(key, e.o + Vector3.UP * PILES, e.r, e.w, f1 - PILES, low2, u0, PILES, reveal, Color(0.7, 0.68, 0.66), Color.WHITE, 0.3, 0.0)
		k.pop_tint()
		k.push_tint(spec.paint2)
		k.wall(key, e.o + Vector3.UP * f1, e.r, e.w, lot.height - f1, high2, u0, f1, reveal, Color.WHITE, Color(0.78, 0.78, 0.8), 0.0, 0.3)
		k.pop_tint()
	elif lot.style == "conv" and lot.floors > 1 and spec.paint2 != spec.paint:
		# two colours: the ground floor and the floor above
		var low: Array = []
		var high: Array = []
		for r: Rect2 in rects:
			if r.position.y < f1: low.append(r)
			else: high.append(Rect2(r.position.x, r.position.y - f1, r.size.x, r.size.y))
		k.push_tint(spec.paint)
		k.wall(key, e.o, e.r, e.w, f1, low, u0, 0.0, reveal, Color(0.62, 0.6, 0.58), Color.WHITE, 0.5, 0.0)
		k.pop_tint()
		k.push_tint(spec.paint2)
		k.wall(key, e.o + Vector3.UP * f1, e.r, e.w, lot.height - f1, high, u0, f1, reveal, Color.WHITE, Color(0.78, 0.78, 0.8), 0.0, 0.3)
		k.pop_tint()
	else:
		k.push_tint(spec.paint)
		k.wall(key, e.o, e.r, e.w, lot.height, rects, u0, 0.0, reveal, Color(0.62, 0.6, 0.58), Color(0.8, 0.8, 0.82))
		k.pop_tint()
	for o: Dictionary in openings:
		_fill(lot, e, k, kd, spec, o, reveal, back)

## The timber piles under a sheet-iron house: a dark skirt of boards set back under the floor, the pile heads
## showing, the sole beam along the top; wooden steps up to each door; snow drifted against it all.
func _piles(lot: Plan.Lot, e: Edge, k: Kit, spec: Dictionary, openings: Array) -> void:
	var dark := Color(0.32, 0.27, 0.23)
	k.push_tint(dark)
	k.quad_m("planks", e.at(0, 0, -0.14), e.at(e.w, 0, -0.14), e.at(e.w, PILES, -0.14), e.at(0, PILES, -0.14), Vector2(e.o.x + e.o.z, 0.0) * Kit.UV_M, Color(0.5, 0.5, 0.5), Color(0.8, 0.8, 0.8), true)
	k.pop_tint()
	var wood := Color(0.48, 0.4, 0.33)
	k.push_tint(wood)
	var x := 0.12
	while x < e.w - 0.05:
		_ebox(k, e, "planks", x, PILES * 0.5, -0.04, 0.16, PILES, 0.16, Color(0.55, 0.55, 0.55), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		x += 1.45
	_ebox(k, e, "planks", e.w * 0.5, PILES - 0.08, -0.02, e.w, 0.16, 0.2, Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	for o: Dictionary in openings:
		if str(o.kind) != "door": continue
		var r: Rect2 = o.rect
		var cx := r.get_center().x
		var tread := Color(0.55, 0.47, 0.38)
		k.push_tint(tread)
		for i: int in range(1, 4):
			var top := PILES * float(i) / 4.0
			var depth := 0.22 * float(4 - i)
			_ebox(k, e, "planks", cx, top * 0.5, depth * 0.5, r.size.x + 0.2, top, depth, Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
			# snow on the tread, trodden at the middle
			Snow.ridge(k, e.at(cx - r.size.x * 0.5 - 0.08, top, depth - 0.12), e.at(cx - 0.18, top, depth - 0.12), Vector3.UP, 0.22, 0.05, 0.02)
			Snow.ridge(k, e.at(cx + 0.18, top, depth - 0.12), e.at(cx + r.size.x * 0.5 + 0.08, top, depth - 0.12), Vector3.UP, 0.22, 0.05, 0.02)
		k.pop_tint()

## Outside the map: a plain wall with its windows and doors laid on it (no reveals): far cheaper to build, the same
## from where the camera sees it.
func _flat_wall(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, openings: Array) -> void:
	var key: String = spec.wall
	var u0 := (e.o.x + e.o.z) * Kit.UV_M
	var f1: float = spec.f1
	var two: bool = lot.style == "conv" and lot.floors > 1 and spec.paint2 != spec.paint
	var bands: Array = [[0.0, f1, spec.paint], [f1, lot.height, spec.paint2]] if two else [[0.0, lot.height, spec.paint]]
	for band: Array in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		k.push_tint(band[2])
		k.quad4(key, e.at(0, y0), e.at(e.w, y0), e.at(e.w, y1), e.at(0, y1), Vector2(u0, 1.0 - y0 * Kit.UV_M), Vector2(u0 + e.w * Kit.UV_M, 1.0 - y0 * Kit.UV_M),
			Vector2(u0 + e.w * Kit.UV_M, 1.0 - y1 * Kit.UV_M), Vector2(u0, 1.0 - y1 * Kit.UV_M), Color(0.66, 0.64, 0.62) if y0 < 0.1 else Color.WHITE, Color(0.66, 0.64, 0.62) if y0 < 0.1 else Color.WHITE,
			Color.WHITE if y1 < lot.height - 0.1 else Color(0.8, 0.8, 0.82), Color.WHITE if y1 < lot.height - 0.1 else Color(0.8, 0.8, 0.82))
		k.pop_tint()
	for o: Dictionary in openings:
		var r: Rect2 = o.rect
		var lit: bool = o.lit
		var cell := ""
		var key2 := "facade_lit" if lit else "facade_cut"
		var col := Color(1.0, rng.randf_range(0.82, 0.95), rng.randf_range(0.62, 0.8)) * rng.randf_range(0.75, 1.05) if lit else Color.WHITE
		match str(o.kind):
			"door":
				cell = o.cell
				key2 = "facade_cut"
				col = Color(0.55, 0.45, 0.38)
			"shopwin":
				cell = "door_shop_lit"
			"arch":
				cell = "arch_lit" if lit else "arch_dark"
			_:
				cell = ("win_conv_lit" if lit else "win_conv_dark") if lot.style == "conv" else (("win_lit%d" % (rng.randi() % 5)) if lit else ("win_dark%d" % (rng.randi() % 3)))
		kd.quad_rect(key2, e.at(r.position.x, r.position.y, 0.02), e.at(r.end.x, r.position.y, 0.02), e.at(r.end.x, r.end.y, 0.02), e.at(r.position.x, r.end.y, 0.02), uv(cell), col, col)

## One opening: the glass or the door at the back of its reveal, then what goes round it.
func _fill(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, o: Dictionary, reveal: float, back: bool) -> void:
	var r: Rect2 = o.rect
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	var d := -reveal + 0.01
	var lit: bool = o.lit
	var kind: String = o.kind
	var ital := lot.style in ["ital", "guardia"]
	var cell := ""
	var key := "facade_cut"
	var col := Color.WHITE
	match kind:
		"door":
			cell = o.cell
			if cell == "door_double": col = spec.trim if lot.style == "conv" else hexc(["6a4a34", "4a5a48", "5a3a2a", "3a4a5a"][rng.randi() % 4])
			if cell == "door_roller": col = hexc(["8a8f88", "6a7a6a", "7a6a5a"][rng.randi() % 3])
		"shopwin":
			cell = "door_shop_lit"
			key = "facade_lit"
			col = Color(1.0, 0.86, 0.66) * 1.1
		"arch":
			cell = "arch_lit" if lit else "arch_dark"
			key = "facade_lit" if lit else "facade_cut"
			col = Color(1.0, 0.82, 0.6) * rng.randf_range(0.8, 1.05) if lit else Color.WHITE
		_:
			if lot.style == "conv" or (back and not ital):
				cell = "win_conv_lit" if lit else "win_conv_dark"
			elif back:
				cell = "win_small_lit" if lit else "win_small_dark"
			else:
				cell = ("win_lit%d" % (rng.randi() % 5)) if lit else ("win_dark%d" % (rng.randi() % 3))
			key = "facade_lit" if lit else "facade_cut"
			col = Color(1.0, rng.randf_range(0.82, 0.95), rng.randf_range(0.62, 0.8)) * rng.randf_range(0.75, 1.1) if lit else Color.WHITE
	# a dark window behind closed shutters, sometimes
	var closed := not lit and kind == "win" and ital and not back and rng.randf() < 0.45
	if closed:
		kd.quad_rect("facade_cut", e.at(x0, y0, d), e.at(x1, y0, d), e.at(x1, y1, d), e.at(x0, y1, d), uv("shutter_louvre"), spec.shutter * 0.85, spec.shutter)
	else:
		kd.quad_rect(key, e.at(x0, y0, d), e.at(x1, y0, d), e.at(x1, y1, d), e.at(x0, y1, d), uv(cell), col, col)
	if lot.outer: return
	var stone := Color(0.92, 0.9, 0.86)
	if kind == "win" or kind == "arch" or kind == "shopwin":
		# the sill, holding its line of snow
		k.push_tint(spec.paint.lightened(0.25) if ital else (spec.trim if lot.style == "conv" else Color(0.75, 0.72, 0.7)))
		_ebox(k, e, "planks" if lot.style == "conv" else "stucco", (x0 + x1) * 0.5, y0 - 0.05, 0.07, x1 - x0 + 0.24, 0.1, 0.2, Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		Snow.ridge(k, e.at(x0 - 0.12, y0, 0.08), e.at(x1 + 0.12, y0, 0.08), Vector3.UP, 0.2, 0.07, 0.03, rng)
	if ital and (kind == "win" or kind == "door" or kind == "shopwin"):
		# the surround: a raised band round the opening and a cap over it
		var band := 0.12
		var t: Color = (spec.paint as Color).lightened(0.3)
		k.push_tint(t)
		k.quad_m("stucco", e.at(x0 - band, y0, 0.03), e.at(x0, y0, 0.03), e.at(x0, y1, 0.03), e.at(x0 - band, y1, 0.03))
		k.quad_m("stucco", e.at(x1, y0, 0.03), e.at(x1 + band, y0, 0.03), e.at(x1 + band, y1, 0.03), e.at(x1, y1, 0.03))
		k.pop_tint()
		k.push_tint(t)
		_ebox(k, e, "stucco", (x0 + x1) * 0.5, y1 + 0.12, 0.08, x1 - x0 + 0.5, 0.24, 0.16, Color(0.75, 0.75, 0.75), Color.WHITE)
		var cap_top := y1 + 0.24
		var cap_d := 0.16
		if int(o.floor) > 0 and rng.randf() < 0.5:
			# a little pediment on the upper windows
			_ebox(k, e, "stucco", (x0 + x1) * 0.5, y1 + 0.3, 0.11, x1 - x0 + 0.7, 0.1, 0.22, Color(0.8, 0.8, 0.8), Color.WHITE)
			cap_top = y1 + 0.35
			cap_d = 0.22
		k.pop_tint()
		Snow.ridge(k, e.at(x0 - 0.3, cap_top, cap_d * 0.5), e.at(x1 + 0.3, cap_top, cap_d * 0.5), Vector3.UP, cap_d, 0.06, 0.025, rng)
		if kind == "win" and not closed and not back:
			# open shutters folded back against the wall either side
			var sw := (x1 - x0) * 0.5
			kd.quad_rect("facade_cut", e.at(x0 - band - sw, y0, 0.04), e.at(x0 - band, y0, 0.04), e.at(x0 - band, y1, 0.04), e.at(x0 - band - sw, y1, 0.04), uv_part("shutter_louvre", 0.0, 0.5), spec.shutter * 0.85, spec.shutter)
			kd.quad_rect("facade_cut", e.at(x1 + band, y0, 0.04), e.at(x1 + band + sw, y0, 0.04), e.at(x1 + band + sw, y1, 0.04), e.at(x1 + band, y1, 0.04), uv_part("shutter_louvre", 0.5, 1.0), spec.shutter * 0.85, spec.shutter)
		if o.get("balcony", false):
			_balcony(e, k, kd, x0 - 0.3, x1 + 0.3, y0, spec)
	elif lot.style == "conv":
		# a painted frame round the opening
		var t2: Color = spec.trim
		k.push_tint(t2)
		var fw := 0.09
		k.quad_m("planks", e.at(x0 - fw, y0 - fw, 0.025), e.at(x1 + fw, y0 - fw, 0.025), e.at(x1 + fw, y0, 0.025), e.at(x0 - fw, y0, 0.025))
		k.quad_m("planks", e.at(x0 - fw, y1, 0.025), e.at(x1 + fw, y1, 0.025), e.at(x1 + fw, y1 + fw, 0.025), e.at(x0 - fw, y1 + fw, 0.025))
		k.quad_m("planks", e.at(x0 - fw, y0, 0.025), e.at(x0, y0, 0.025), e.at(x0, y1, 0.025), e.at(x0 - fw, y1, 0.025))
		k.quad_m("planks", e.at(x1, y0, 0.025), e.at(x1 + fw, y0, 0.025), e.at(x1 + fw, y1, 0.025), e.at(x1, y1, 0.025))
		k.pop_tint()
		if kind == "win" and rng.randf() < 0.35:
			# plain board shutters, one open
			kd.quad_rect("facade_cut", e.at(x1 + fw, y0, 0.04), e.at(x1 + fw + (x1 - x0) * 0.5, y0, 0.04), e.at(x1 + fw + (x1 - x0) * 0.5, y1, 0.04), e.at(x1 + fw, y1, 0.04), uv_part("shutter_panel", 0.5, 1.0), t2 * 0.85, t2)
	# light from a lit opening on the ground floor spills on the snow outside
	if lit and int(o.floor) == 0 and e.kind != "back":
		b.spill(e.at((x0 + x1) * 0.5, 0.0, 0.0), e.r, e.n, x1 - x0, 1.6 if kind != "shopwin" else 2.6, 0.55 if kind != "shopwin" else 0.9)

## A box laid along an edge (the cut corners run diagonally): its centre x along the edge, y up, out from the wall;
## its size along, up and out.
func _ebox(k: Kit, e: Edge, key: String, x: float, y: float, out: float, along: float, up: float, depth: float, lo: Color = Color.WHITE, hi: Color = Color.WHITE, uv0: Vector2 = Vector2.ZERO, mode: int = Kit.AUTO) -> void:
	k.push(Transform3D(Basis(e.r, Vector3.UP, e.n), e.o))
	k.box(key, Vector3(x, y, out), Vector3(along, up, depth), lo, hi, uv0 + Vector2(e.o.x + e.o.z, 0.0) * Kit.UV_M, mode)
	k.pop()

## An iron balcony: a stone slab under the snow, the railing on three sides, its top rail.
func _balcony(e: Edge, k: Kit, kd: Kit, x0: float, x1: float, y: float, spec: Dictionary) -> void:
	var depth := 0.62
	k.push_tint(spec.paint.lightened(0.2))
	_ebox(k, e, "stucco", (x0 + x1) * 0.5, y - 0.08, depth * 0.5, x1 - x0, 0.16, depth, Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	var h := 0.95
	var w := x1 - x0
	var cell_w := 1.9
	var iron := Color(0.5, 0.5, 0.52)
	var s := 0.0
	while s < w - 0.01:
		var t := minf(cell_w, w - s)
		kd.quad_rect("facade_cut", e.at(x0 + s, y, depth - 0.03), e.at(x0 + s + t, y, depth - 0.03), e.at(x0 + s + t, y + h, depth - 0.03), e.at(x0 + s, y + h, depth - 0.03), uv_part("rail_iron", 0.0, t / cell_w), iron, iron)
		s += t
	for side: float in [x0 + 0.03, x1 - 0.03]:
		kd.quad_rect("facade_cut", e.at(side, y, 0.0) , e.at(side, y, depth - 0.03), e.at(side, y + h, depth - 0.03), e.at(side, y + h, 0.0), uv_part("rail_iron", 0.0, depth / cell_w), iron, iron)
	k.beam("stucco", e.at(x0, y + h, depth - 0.03), e.at(x1, y + h, depth - 0.03), 0.05, 0.04, Color(0.12, 0.12, 0.13), Color(0.16, 0.16, 0.17))
	Snow.ridge(k, e.at(x0 + 0.05, y, depth * 0.45), e.at(x1 - 0.05, y, depth * 0.45), Vector3.UP, depth * 0.85, 0.11, 0.03, rng)
	Snow.ridge(k, e.at(x0, y + h + 0.02, depth - 0.03), e.at(x1, y + h + 0.02, depth - 0.03), Vector3.UP, 0.07, 0.05, 0.015, rng, 0.3)

## The mouldings of a rendered front: plinth, string course, cornice, the parapet (balustraded or solid), pilasters.
func _ital_dress(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, full: bool) -> void:
	var H := lot.height
	var paint: Color = spec.paint
	var light := paint.lightened(0.18)
	var dark := paint.darkened(0.12)
	var w := e.w
	var mid := w * 0.5
	if not lot.outer:
		k.push_tint(Color(0.62, 0.6, 0.58))
		_ebox(k, e, "stucco", mid, 0.33, 0.03, w, 0.66, 0.06, Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
	k.push_tint(light)
	if lot.floors > 1:
		var f1: float = spec.f1
		_ebox(k, e, "stucco", mid, f1 - 0.02, 0.06, w, 0.22, 0.12, Color(0.7, 0.7, 0.7), Color.WHITE)
	# the cornice: a band and the projecting slab that carries the snow
	_ebox(k, e, "stucco", mid, H - 0.2, 0.09, w, 0.4, 0.18, Color(0.62, 0.62, 0.64), Color.WHITE)
	_ebox(k, e, "stucco", mid, H + 0.06, 0.2, w + 0.02, 0.14, 0.42, Color(0.7, 0.7, 0.72), Color.WHITE)
	k.pop_tint()
	if lot.floors > 1 and not lot.outer:
		var f1s: float = spec.f1
		Snow.ridge(k, e.at(0.02, f1s + 0.09, 0.07), e.at(w - 0.02, f1s + 0.09, 0.07), Vector3.UP, 0.12, 0.05, 0.02, rng)
	if not lot.outer: Snow.ridge(k, e.at(-0.01, H + 0.13, 0.22), e.at(w + 0.01, H + 0.13, 0.22), Vector3.UP, 0.4, 0.1, 0.04, rng)
	if not lot.outer:
		# pilasters at both ends of the front
		k.push_tint(light)
		for x: float in [0.22, w - 0.22]:
			if w < 3.0: break
			_ebox(k, e, "stucco", x, (0.66 + H - 0.4) * 0.5, 0.04, 0.44, H - 1.06, 0.08, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
	_parapet(lot, e, k, kd, light, w > 3.2 and rng.randf() < 0.55 and not lot.outer)

func _parapet(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, tint: Color, balusters: bool) -> void:
	var H := lot.height + 0.13
	var w := e.w
	var top := 0.95
	k.push_tint(tint)
	if balusters:
		_ebox(k, e, "stucco", w * 0.5, H + 0.09, -0.11, w, 0.18, 0.26, Color(0.75, 0.75, 0.75), Color.WHITE)
		_ebox(k, e, "stucco", w * 0.5, H + top - 0.07, -0.11, w, 0.14, 0.32, Color(0.8, 0.8, 0.8), Color.WHITE)
		# dados every few metres
		var n := maxi(1, int(round(w / 2.4)))
		for i: int in range(n + 1):
			var x := clampf(float(i) * w / float(n), 0.2, w - 0.2)
			_ebox(k, e, "stucco", x, H + top * 0.5, -0.11, 0.36, top - 0.1, 0.3, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		var cw := 0.95
		var s := 0.0
		while s < w - 0.01:
			var t := minf(cw, w - s)
			kd.quad_rect("facade_cut", e.at(s, H + 0.18, -0.1), e.at(s + t, H + 0.18, -0.1), e.at(s + t, H + top - 0.14, -0.1), e.at(s, H + top - 0.14, -0.1), uv_part("balustrade", 0.0, t / cw), tint, tint)
			s += t
		Snow.ridge(k, e.at(-0.02, H + top, -0.11), e.at(w + 0.02, H + top, -0.11), Vector3.UP, 0.32, 0.12, 0.04, rng)
	else:
		_ebox(k, e, "stucco", w * 0.5, H + top * 0.45, -0.11, w, top * 0.9, 0.22, Color(0.72, 0.72, 0.74), Color.WHITE)
		_ebox(k, e, "stucco", w * 0.5, H + top * 0.93, -0.11, w + 0.04, 0.1, 0.32, Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		Snow.ridge(k, e.at(-0.02, H + top * 0.93 + 0.05, -0.11), e.at(w + 0.02, H + top * 0.93 + 0.05, -0.11), Vector3.UP, 0.32, 0.12, 0.04, rng)

## A conventillo's front: the painted floor band and corner boards; sometimes the wooden gallery along the upper floor.
func _conv_dress(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, openings: Array) -> void:
	var trim: Color = spec.trim
	var f1: float = spec.f1
	if lot.outer: return
	k.push_tint(trim)
	if lot.floors > 1:
		_ebox(k, e, "planks", e.w * 0.5, f1, 0.04, e.w, 0.16, 0.08, Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		Snow.ridge(k, e.at(0.0, f1 + 0.08, 0.05), e.at(e.w, f1 + 0.08, 0.05), Vector3.UP, 0.1, 0.045, 0.02, rng)
	for x: float in [0.06, e.w - 0.06]:
		_ebox(k, e, "planks", x, lot.height * 0.5, 0.03, 0.12, lot.height, 0.06, Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	var court := courtyard.has_point(Vector2(e.at(e.w * 0.5, 0, 1.5).x, e.at(e.w * 0.5, 0, 1.5).z))
	if lot.floors > 1 and e.w > 2.5 and (court or (e.w > 4.0 and rng.randf() < 0.45)):
		_gallery(lot, e, k, kd, spec, openings)

## The wooden galleries along the upper floors: plank decks on brackets, the painted railings, posts the whole height,
## and a lean-to of corrugated iron over it all, under snow.
func _gallery(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary, _openings_list: Array) -> void:
	var f1: float = spec.f1
	var depth := 1.15
	var trim: Color = spec.trim
	var wood := Color(0.62, 0.54, 0.46)
	var x0 := 0.15
	var x1 := e.w - 0.15
	var fh := (lot.height - f1) / float(maxi(1, lot.floors - 1))
	var decks: Array[float] = []
	for f: int in range(1, lot.floors): decks.append(f1 + float(f - 1) * fh)
	k.push_tint(wood)
	var n := maxi(2, int(ceil((x1 - x0) / 2.4)) + 1)
	for y: float in decks:
		_ebox(k, e, "planks", (x0 + x1) * 0.5, y - 0.06, depth * 0.5, x1 - x0, 0.12, depth, Color(0.5, 0.5, 0.5), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		for i: int in range(n):
			var x := lerpf(x0 + 0.05, x1 - 0.05, float(i) / float(n - 1))
			k.beam("planks", e.at(x, y - 0.1, 0.0), e.at(x, y - 0.1, depth * 0.8), 0.08, 0.12, wood * 0.7, wood)
	for i: int in range(n):
		var x := lerpf(x0 + 0.05, x1 - 0.05, float(i) / float(n - 1))
		_ebox(k, e, "planks", x, (f1 + lot.height - 0.45) * 0.5, depth - 0.06, 0.1, lot.height - 0.45 - f1, 0.1, Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	var h := 0.95
	var cw := 1.9
	for y: float in decks:
		var s := x0
		while s < x1 - 0.01:
			var t := minf(cw, x1 - s)
			kd.quad_rect("facade_cut", e.at(s, y, depth - 0.04), e.at(s + t, y, depth - 0.04), e.at(s + t, y + h, depth - 0.04), e.at(s, y + h, depth - 0.04), uv_part("rail_wood", 0.0, t / cw), trim * 0.85, trim)
			s += t
		k.push_tint(trim)
		_ebox(k, e, "planks", (x0 + x1) * 0.5, y + h, depth - 0.04, x1 - x0, 0.06, 0.12, Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		k.pop_tint()
		Snow.ridge(k, e.at(x0, y + h + 0.03, depth - 0.04), e.at(x1, y + h + 0.03, depth - 0.04), Vector3.UP, 0.12, 0.06, 0.02, rng, 0.35)
	# the lean-to over the galleries
	var roof_c := hexc(ROOF[rng.randi() % ROOF.size()])
	var yt := lot.height - 0.25
	var yb := lot.height - 0.62
	k.push_tint(roof_c)
	k.quad_m("corrugated", e.at(x0 - 0.1, yb, depth + 0.25), e.at(x1 + 0.1, yb, depth + 0.25), e.at(x1 + 0.1, yt, 0.0), e.at(x0 - 0.1, yt, 0.0))
	k.quad_m("corrugated", e.at(x1 + 0.1, yb - 0.02, depth + 0.25), e.at(x0 - 0.1, yb - 0.02, depth + 0.25), e.at(x0 - 0.1, yt - 0.02, 0.0), e.at(x1 + 0.1, yt - 0.02, 0.0), Vector2.ZERO, Color(0.35, 0.35, 0.35), Color(0.45, 0.45, 0.45))
	k.pop_tint()
	var ln := _plane_n(e.r, e.at(0, yb, depth + 0.25) - e.at(0, yt, 0.0))
	Snow.slope(k, e.at(x0 - 0.1, yb, depth + 0.25), e.at(x1 + 0.1, yb, depth + 0.25), e.at(x0 - 0.1, yt, 0.02), e.at(x1 + 0.1, yt, 0.02), ln, rng.randf_range(0.12, 0.18), 0.16, rng)

func _brick_dress(lot: Plan.Lot, e: Edge, k: Kit, spec: Dictionary) -> void:
	if lot.outer: return
	# a brick string course and a dentil band under the eaves
	k.push_tint(Color(0.85, 0.8, 0.76))
	_ebox(k, e, "brick", e.w * 0.5, lot.height - 0.3, 0.05, e.w, 0.24, 0.1, Color(0.7, 0.7, 0.7), Color.WHITE)
	_ebox(k, e, "brick", e.w * 0.5, 0.35, 0.04, e.w, 0.7, 0.08, Color(0.6, 0.6, 0.6), Color(0.9, 0.9, 0.9))
	k.pop_tint()

func _poster(e: Edge, kd: Kit, x: float) -> void:
	var cell := "poster_baile" if rng.randf() < 0.5 else "poster_alquila"
	var s := 0.62
	var y := rng.randf_range(1.3, 1.7)
	kd.quad_rect("facade_cut", e.at(x - s * 0.5, y, 0.035), e.at(x + s * 0.5, y, 0.035), e.at(x + s * 0.5, y + s, 0.035), e.at(x - s * 0.5, y + s, 0.035), uv(cell), Color(0.9, 0.9, 0.88), Color.WHITE)

## The cut corner: the shop's lit door, its painted sign, a little canopy, the window over it.
func _chamfer_face(lot: Plan.Lot, e: Edge, k: Kit, kd: Kit, spec: Dictionary) -> void:
	var w := e.w
	var f1: float = spec.f1
	var door := Rect2(w * 0.5 - 0.75, 0.0, 1.5, 2.9)
	var up := Rect2(w * 0.5 - 0.55, f1 + 0.3, 1.1, minf(2.3, lot.height - f1 - 0.7))
	var openings: Array = [{"rect": door, "kind": "shopwin", "floor": 0, "lit": true, "cell": "door_shop_lit"},
		{"rect": up, "kind": "win", "floor": 1, "lit": rng.randf() < 0.7, "balcony": true}]
	_wall_with(lot, e, k, kd, spec, openings, false)
	_ital_dress(lot, e, k, kd, spec, false)
	var sign := "sign_" + lot.corner
	if ATLAS.has(sign):
		var sw := minf(w - 0.3, 3.2)
		var y0 := 3.05
		var y1 := y0 + sw * 0.25
		kd.quad_rect("facade_cut", e.at(w * 0.5 - sw * 0.5, y0, 0.06), e.at(w * 0.5 + sw * 0.5, y0, 0.06), e.at(w * 0.5 + sw * 0.5, y1, 0.06), e.at(w * 0.5 - sw * 0.5, y1, 0.06), uv(sign), Color(0.95, 0.95, 0.95), Color.WHITE)
		# a gooseneck lamp over the sign
		b.sign_lamp(e.at(w * 0.5, y1 + 0.25, 0.45), e.n)

# ---------------------------------------------------------------------------------------------------------------
# Roofs
# ---------------------------------------------------------------------------------------------------------------
## An azotea: the roof terrace under its pillow of snow inside the parapets, with chimneys, a water tank on its stand,
## sometimes a stair hut, a skylight, the washing left out; on the corner buildings a mansard of slate with dormers,
## and now and then a cupola over the cut corner.
func _roof_flat(lot: Plan.Lot, k: Kit, kd: Kit, spec: Dictionary) -> void:
	var H := lot.height + 0.12
	var p := lot.poly
	# the terrace's tiles under a layer of snow, thinner on some (a stove below, the wind)
	var thin := rng.randf() >= 0.75 and lot.style in ["ital", "conv"]
	k.push_tint(Color(0.7, 0.5, 0.42, rng.randf_range(0.45, 0.8) if thin else 1.0))
	for i: int in range(1, p.size() - 1):
		k.tri("stucco", Vector3(p[0].x, H, p[0].y), Vector3(p[i].x, H, p[i].y), Vector3(p[i + 1].x, H, p[i + 1].y), Vector2(p[0].x, p[0].y) * Kit.UV_M, Vector2(p[i].x, p[i].y) * Kit.UV_M, Vector2(p[i + 1].x, p[i + 1].y) * Kit.UV_M)
	k.pop_tint()
	# low walls on the party and back sides, so every terrace reads on its own
	for i: int in range(p.size()):
		var e := _edge(lot, i)
		if e.kind in ["front", "chamfer"] or e.w < 0.3: continue
		k.push_tint(spec.paint.darkened(0.05))
		_ebox(k, e, "stucco", e.w * 0.5, H + 0.2, -0.1, e.w, 0.4, 0.2, Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		if not lot.outer: Snow.ridge(k, e.at(0.0, H + 0.4, -0.1), e.at(e.w, H + 0.4, -0.1), Vector3.UP, 0.2, 0.1, 0.03, rng)
	var mansard := lot.style == "ital" and ((lot.corner != "" and rng.randf() < 0.75) or (not lot.outer and lot.corner == "" and rng.randf() < 0.1))
	if mansard:
		_mansard(lot, k, kd, spec, H)
		return
	# the snow on the terrace, trodden where somebody went up to the washing or the tank
	if not thin: Snow.pillow(k, Snow.inset(p, 0.22), H, rng.randf_range(0.12, 0.2), 0.7, null if lot.outer else rng)
	var c := _centroid(p)
	var box := _bounds(p)
	var inset := box.grow(-1.2)
	if inset.size.x < 0.5 or inset.size.y < 0.5: return
	var chim := 1 + (1 if rng.randf() < 0.45 and not lot.outer else 0)
	for i: int in range(chim):
		var at := Vector3(rng.randf_range(inset.position.x, inset.end.x), H, rng.randf_range(inset.position.y, inset.end.y))
		_chimney(k, at, rng.randf_range(0.9, 1.7), spec)
	if lot.outer:
		if rng.randf() < 0.35: _tank(k, Vector3(rng.randf_range(inset.position.x, inset.end.x), H, rng.randf_range(inset.position.y, inset.end.y)))
		return
	if rng.randf() < 0.35 and inset.size.x > 2.6 and inset.size.y > 2.6:
		# the stair hut (casilla) where the stairs come up onto the terrace
		var hc := Vector3(lerpf(inset.position.x + 1.0, inset.end.x - 1.0, rng.randf()), H, lerpf(inset.position.y + 1.0, inset.end.y - 1.0, rng.randf()))
		k.push_tint(spec.paint)
		k.box("stucco", hc + Vector3(0, 1.2, 0), Vector3(1.8, 2.4, 1.8), Color(0.65, 0.65, 0.65), Color.WHITE)
		k.pop_tint()
		k.push_tint(Color(0.8, 0.78, 0.75))
		k.box("stucco", hc + Vector3(0, 2.48, 0), Vector3(2.0, 0.16, 2.0), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		Snow.box_top(k, hc + Vector3(0, 2.56, 0), Vector2(2.0, 2.0), 0.16, rng)
		var dn := Vector3(0, 0, 1) if hc.z < c.y else Vector3(0, 0, -1)
		var dr := Vector3(1, 0, 0) if dn.z > 0 else Vector3(-1, 0, 0)
		var dp := hc + dn * 0.91
		var lit := rng.randf() < 0.25
		kd.quad_rect("facade_lit" if lit else "facade_cut", dp - dr * 0.45, dp + dr * 0.45, dp + dr * 0.45 + Vector3.UP * 2.0, dp - dr * 0.45 + Vector3.UP * 2.0, uv("win_small_lit" if lit else "door_double"), Color(0.6, 0.5, 0.4) if not lit else Color(1, 0.85, 0.65), Color(0.6, 0.5, 0.4) if not lit else Color(1, 0.85, 0.65))
	if rng.randf() < 0.6:
		_tank(k, Vector3(rng.randf_range(inset.position.x, inset.end.x), H, rng.randf_range(inset.position.y, inset.end.y)))
	if rng.randf() < 0.25 and inset.size.x > 2.0:
		# a skylight over the stairwell: a little glazed ridge, snow on its frame, a glow under it now and then
		var sc := Vector3(rng.randf_range(inset.position.x, inset.end.x), H, rng.randf_range(inset.position.y, inset.end.y))
		var lit2 := rng.randf() < 0.35
		var gl := Color(1.0, 0.8, 0.55) * 0.7 if lit2 else Color(0.5, 0.55, 0.65)
		for sgn: float in [-1.0, 1.0]:
			var lo := sc + Vector3(-0.7, 0.25, sgn * 0.5)
			var lo2 := sc + Vector3(0.7, 0.25, sgn * 0.5)
			var hi := sc + Vector3(-0.7, 0.62, 0.0)
			var hi2 := sc + Vector3(0.7, 0.62, 0.0)
			if sgn > 0.0: kd.quad_rect("facade_lit" if lit2 else "facade_cut", lo, lo2, hi2, hi, uv_part("win_small_lit" if lit2 else "win_small_dark", 0.1, 0.9, 0.1, 0.6), gl, gl)
			else: kd.quad_rect("facade_lit" if lit2 else "facade_cut", lo2, lo, hi, hi2, uv_part("win_small_lit" if lit2 else "win_small_dark", 0.1, 0.9, 0.1, 0.6), gl, gl)
		k.push_tint(Color(0.3, 0.3, 0.3))
		k.box("steel", sc + Vector3(0, 0.12, 0), Vector3(1.5, 0.25, 1.1), Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
		Snow.ridge(k, sc + Vector3(-0.72, 0.63, 0), sc + Vector3(0.72, 0.63, 0), Vector3.UP, 0.12, 0.06, 0.02, rng)
	if rng.randf() < 0.4 and inset.size.x > 3.0:
		# washing left out on the terrace, stiff with the cold
		var y := H + 1.7
		var a := Vector3(inset.position.x + 0.3, y, inset.get_center().y + rng.randf_range(-0.6, 0.6))
		var d := Vector3(inset.end.x - 0.3, y, a.z)
		for q: Vector3 in [a, d]:
			k.beam("stucco", Vector3(q.x, H, q.z), q, 0.05, 0.05, Color(0.2, 0.2, 0.2), Color(0.25, 0.25, 0.25))
			Snow.cone(k, q + Vector3(0, 0.02, 0), 0.05, 0.05)
		b._props.wire(k, a, d, 0.1, 0.008, Color(0.75, 0.75, 0.72), 6)
		var x := a.x + 0.4
		while x < d.x - 0.6:
			var ww := rng.randf_range(0.5, 0.9)
			var col: Color = [Color(0.92, 0.92, 0.9), Color(0.7, 0.75, 0.85), Color(0.85, 0.66, 0.6), Color(0.8, 0.82, 0.7)][rng.randi() % 4]
			var drop := rng.randf_range(0.5, 1.0)
			kd.quad_rect("facade_cut", Vector3(x, y - drop, a.z), Vector3(x + ww, y - drop, a.z), Vector3(x + ww, y - 0.05, a.z), Vector3(x, y - 0.05, a.z), CLOTH_UV, col * 0.85, col)
			x += ww + rng.randf_range(0.15, 0.5)
	if rng.randf() < 0.12:
		# the children were up here: a little snowman by the parapet
		_snowman(k, kd, Vector3(rng.randf_range(inset.position.x, inset.end.x), H + 0.12, rng.randf_range(inset.position.y, inset.end.y)), 0.6, false)

## A water tank (tanque) on the roof: a riveted iron drum on an angle-iron stand, or a rendered box; snow on its top.
func _tank(k: Kit, at: Vector3) -> void:
	var legs := rng.randf_range(0.6, 1.4)
	for dx: float in [-0.5, 0.5]:
		for dz: float in [-0.5, 0.5]:
			k.box("steel", at + Vector3(dx, legs * 0.5, dz), Vector3(0.09, legs, 0.09), Color(0.25, 0.25, 0.25), Color(0.35, 0.35, 0.35), Vector2.ZERO, Kit.AUTO, 51)
	k.box("steel", at + Vector3(0, legs, 0), Vector3(1.2, 0.08, 1.2), Color(0.3, 0.3, 0.3), Color(0.4, 0.4, 0.4))
	if rng.randf() < 0.6:
		var r := rng.randf_range(0.55, 0.7)
		var h := rng.randf_range(1.0, 1.5)
		k.push_tint([Color(0.45, 0.45, 0.44), Color(0.5, 0.36, 0.3), Color(0.55, 0.56, 0.54)][rng.randi() % 3])
		k.lathe("steel", at + Vector3(0, legs + 0.04, 0), PackedVector2Array([Vector2(r, 0.0), Vector2(r, h), Vector2(r * 0.4, h + 0.12), Vector2(0.0, h + 0.14)]), 8, Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
		Snow.cone(k, at + Vector3(0, legs + h + 0.02, 0), r * 1.02, 0.2)
	else:
		var hb := rng.randf_range(0.9, 1.2)
		k.push_tint(Color(0.78, 0.76, 0.72))
		k.box("stucco", at + Vector3(0, legs + hb * 0.5, 0), Vector3(1.2, hb, 1.2), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		Snow.box_top(k, at + Vector3(0, legs + hb, 0), Vector2(1.2, 1.2), 0.15, rng)

## A mansard over a corner building: slate rising steeply from behind the parapet to a flat top under snow, dormers
## with their windows (some lit) on the street sides, a cupola over the cut corner on some.
func _mansard(lot: Plan.Lot, k: Kit, kd: Kit, spec: Dictionary, H: float) -> void:
	var base := Snow.inset(lot.poly, 0.3)
	var top := Snow.inset(lot.poly, 1.25)
	var y0 := H + 0.1
	var y1 := H + rng.randf_range(2.2, 2.8)
	var n := base.size()
	var slate := Color(0.42, 0.44, 0.48) if rng.randf() < 0.7 else Color(0.38, 0.4, 0.36)
	k.push_tint(slate)
	for i: int in range(n):
		var j := (i + 1) % n
		k.quad_m("slate", Vector3(base[i].x, y0, base[i].y), Vector3(base[j].x, y0, base[j].y), Vector3(top[j].x, y1, top[j].y), Vector3(top[i].x, y1, top[i].y))
	k.pop_tint()
	k.push_tint(Color(0.55, 0.5, 0.46))
	for i: int in range(1, n - 1):
		k.tri("stucco", Vector3(top[0].x, y1, top[0].y), Vector3(top[i].x, y1, top[i].y), Vector3(top[i + 1].x, y1, top[i + 1].y), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1))
	k.pop_tint()
	# the curb (a zinc roll) round the top, then its snow
	for i: int in range(n):
		var j := (i + 1) % n
		k.beam("steel", Vector3(top[i].x, y1 + 0.03, top[i].y), Vector3(top[j].x, y1 + 0.03, top[j].y), 0.08, 0.08, Color(0.5, 0.52, 0.54), Color(0.6, 0.62, 0.64))
	Snow.pillow(k, Snow.inset(top, 0.05), y1 + 0.05, 0.18, 0.6, rng)
	# dormers on the street sides
	var cupola := lot.corner != "" and rng.randf() < 0.5
	for i: int in range(n):
		var e := _edge(lot, i)
		if not e.kind in ["front", "chamfer"] or e.w < 2.2: continue
		if e.kind == "chamfer" and cupola: continue
		var count := maxi(1, int(e.w / 2.8)) if e.kind == "front" else 1
		for d: int in range(count):
			var x := (float(d) + 0.5) * e.w / float(count)
			var ins := 0.3 + (1.25 - 0.3) * 0.45
			var yb := y0 + (y1 - y0) * 0.25
			var lit := rng.randf() < 0.5
			k.push_tint(Color(0.85, 0.82, 0.76))
			_ebox(k, e, "stucco", x, yb + 0.6, -ins + 0.25, 1.0, 1.2, 0.8, Color(0.7, 0.7, 0.7), Color.WHITE)
			k.pop_tint()
			var gl := Color(1.0, 0.84, 0.6) * rng.randf_range(0.8, 1.0) if lit else Color.WHITE
			kd.quad_rect("facade_lit" if lit else "facade_cut", e.at(x - 0.32, yb + 0.15, -ins + 0.66), e.at(x + 0.32, yb + 0.15, -ins + 0.66), e.at(x + 0.32, yb + 1.0, -ins + 0.66), e.at(x - 0.32, yb + 1.0, -ins + 0.66), uv("win_small_lit" if lit else "win_small_dark"), gl, gl)
			# its little pediment roof
			k.push_tint(slate)
			var ra := e.at(x - 0.6, yb + 1.2, -ins + 0.7)
			var rb := e.at(x + 0.6, yb + 1.2, -ins + 0.7)
			var rt := e.at(x, yb + 1.62, -ins + 0.7)
			var back_a := e.at(x - 0.6, yb + 1.2, -ins - 0.2)
			var back_b := e.at(x + 0.6, yb + 1.2, -ins - 0.2)
			var back_t := e.at(x, yb + 1.62, -ins - 0.2)
			k.quad_m("slate", ra, back_a, back_t, rt)
			k.quad_m("slate", back_b, rb, rt, back_t)
			k.tri("stucco", ra, rb, rt, Vector2.ZERO, Vector2(0.1, 0), Vector2(0.05, 0.1))
			k.pop_tint()
			Snow.ridge(k, rt + (back_t - rt) * -0.02, back_t, Vector3.UP, 0.22, 0.08, 0.04, rng)
			Snow.ridge(k, e.at(x - 0.45, yb + 0.15, -ins + 0.75), e.at(x + 0.45, yb + 0.15, -ins + 0.75), Vector3.UP, 0.16, 0.06, 0.02, rng)
	if cupola:
		for i: int in range(n):
			var e2 := _edge(lot, i)
			if e2.kind != "chamfer": continue
			var at := e2.at(e2.w * 0.5, y0 - 0.1, -1.3)
			var r := clampf(e2.w * 0.42, 0.9, 1.4)
			k.push_tint(Color(0.86, 0.82, 0.74))
			k.lathe("stucco", at, PackedVector2Array([Vector2(r, 0.0), Vector2(r, 1.6), Vector2(r + 0.12, 1.65), Vector2(r + 0.12, 1.8), Vector2(0.0, 1.81)]), 8, Color(0.75, 0.75, 0.75), Color.WHITE)
			k.pop_tint()
			# lit oculi round the drum
			for q: int in range(4):
				var ang := TAU * (float(q) + 0.5) / 8.0 + atan2(e2.n.x, e2.n.z) - PI * 0.25
				var dir := Vector3(sin(ang), 0, cos(ang))
				var side := Vector3(dir.z, 0, -dir.x)
				var cp := at + dir * (r + 0.01) + Vector3(0, 0.85, 0)
				var lit2 := rng.randf() < 0.6
				var gl2 := Color(1.0, 0.82, 0.55) if lit2 else Color.WHITE
				kd.quad_rect("facade_lit" if lit2 else "facade_cut", cp - side * 0.25 - Vector3(0, 0.35, 0), cp + side * 0.25 - Vector3(0, 0.35, 0), cp + side * 0.25 + Vector3(0, 0.35, 0), cp - side * 0.25 + Vector3(0, 0.35, 0), uv("arch_lit" if lit2 else "arch_dark"), gl2, gl2)
			var dome := PackedVector2Array()
			for q2: int in range(5):
				var aa := PI * 0.5 * float(q2) / 4.0
				dome.append(Vector2(cos(aa) * (r + 0.1), 1.8 + sin(aa) * (r * 0.95)))
			k.push_tint(slate * 1.1)
			k.lathe("slate", at, dome, 8, Color(0.8, 0.8, 0.8), Color.WHITE)
			k.pop_tint()
			# the snow sits on the dome's shoulders and crown
			var cap := PackedVector2Array()
			for q3: int in range(4):
				var aa2 := PI * 0.5 * (0.35 + 0.65 * float(q3) / 3.0)
				cap.append(Vector2(cos(aa2) * (r + 0.16), 1.8 + sin(aa2) * (r * 0.95 + 0.07)))
			k.lathe(Snow.KEY, at, cap, 8, Snow.WHITE, Snow.WHITE)
			k.push_tint(Color(0.3, 0.3, 0.3))
			k.lathe("steel", at + Vector3(0, 1.8 + r * 0.95, 0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.05, 0.3), Vector2(0.09, 0.42), Vector2(0.0, 0.7)]), 6, Color(0.6, 0.6, 0.6), Color.WHITE)
			k.pop_tint()
	# a chimney through the mansard
	var c2 := _centroid(top)
	_chimney(k, Vector3(c2.x + rng.randf_range(-0.5, 0.5), y1, c2.y + rng.randf_range(-0.5, 0.5)), rng.randf_range(0.8, 1.2), spec)

func Houses_chimney_tint() -> Color:
	return [Color(0.72, 0.42, 0.34), Color(0.86, 0.82, 0.76), Color(0.6, 0.56, 0.52)][rng.randi() % 3]

func _chimney(k: Kit, at: Vector3, height: float, spec: Dictionary) -> void:
	k.push_tint(Houses_chimney_tint())
	# (no bottom faces: they stand in the roof)
	k.box("stucco", at + Vector3(0, height * 0.5, 0), Vector3(0.55, height, 0.55), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.AUTO, 55)
	k.pop_tint()
	k.push_tint(Color(0.8, 0.78, 0.75))
	k.box("stucco", at + Vector3(0, height + 0.06, 0), Vector3(0.72, 0.12, 0.72), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.AUTO, 55)
	k.pop_tint()
	k.lathe("stucco", at + Vector3(0, height + 0.12, 0), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.12, 0.26), Vector2(0.0, 0.27)]), 6, Color(0.5, 0.26, 0.2), Color(0.66, 0.36, 0.26))
	# snow on the cap round the pot (the pot itself is warm)
	Snow.ridge(k, at + Vector3(-0.36, height + 0.12, -0.24), at + Vector3(0.36, height + 0.12, -0.24), Vector3.UP, 0.22, 0.08, 0.03)
	Snow.ridge(k, at + Vector3(-0.36, height + 0.12, 0.24), at + Vector3(0.36, height + 0.12, 0.24), Vector3.UP, 0.22, 0.08, 0.03)
	chimneys.append(at + Vector3(0, height + 0.45, 0))

## A wooden outside stair up to a gallery: two stringers, open treads, a handrail; snow on every tread.
func stair(k: Kit, foot: Vector3, top: Vector3, width: float) -> void:
	var run := top - foot
	var side := Vector3(-run.z, 0, run.x).normalized() * width * 0.5
	var wood := Color(0.5, 0.42, 0.34)
	for s: float in [-1.0, 1.0]:
		k.beam("planks", foot + side * s, top + side * s, 0.06, 0.22, wood * 0.7, wood)
		k.beam("planks", foot + side * s + Vector3(0, 0.95, 0), top + side * s + Vector3(0, 0.95, 0), 0.05, 0.05, wood, wood)
		k.beam("planks", foot + side * s, foot + side * s + Vector3(0, 0.95, 0), 0.06, 0.06, wood, wood)
	var steps := int(ceil(run.y / 0.2))
	for i: int in range(1, steps):
		var p := foot + run * (float(i) / float(steps))
		k.push(Transform3D(Basis(Vector3.UP, atan2(run.x, run.z)), p))
		k.box("planks", Vector3.ZERO, Vector3(width, 0.05, 0.26), wood, wood, Vector2.ZERO, Kit.BEAM)
		k.pop()

## A tin stovepipe through a conventillo's roof, with its conical hat.
func _stovepipe(k: Kit, at: Vector3, height: float) -> void:
	k.lathe("corrugated", at, PackedVector2Array([Vector2(0.09, -0.2), Vector2(0.09, height)]), 6, Color(0.3, 0.3, 0.3), Color(0.42, 0.42, 0.4))
	k.lathe("corrugated", at + Vector3(0, height + 0.12, 0), PackedVector2Array([Vector2(0.26, 0.0), Vector2(0.0, 0.18)]), 6, Color(0.35, 0.35, 0.35), Color(0.45, 0.45, 0.44))
	Snow.cone(k, at + Vector3(0, height + 0.13, 0), 0.25, 0.1)
	chimneys.append(at + Vector3(0, height + 0.4, 0))

## A gabled roof of corrugated iron (or the far bank's warehouses, their gable ends to the street): eaves overhanging the
## walls, the fascia boards, gable walls at the ends, and snow lying thick on it all.
func _roof_gable(lot: Plan.Lot, k: Kit, spec: Dictionary, ends: bool) -> void:
	if lot.poly.size() != 4:
		_roof_flat(lot, k, Kit.new(), spec)
		return
	var fe := _edge(lot, (lot.front + (1 if ends else 0)) % 4)
	var be := _edge(lot, (lot.front + (3 if ends else 2)) % 4)
	var length := fe.w
	var depth := absf((be.o - fe.o).dot(fe.n))
	var H := lot.height
	var rise := minf(depth * 0.5 * (0.26 if lot.style != "shed" else 0.36), 2.6)
	var o := 0.42 if lot.style != "shed" else 0.3
	var roof_c := hexc(ROOF[rng.randi() % ROOF.size()])
	if lot.style == "shed" or lot.style == "machine-house": roof_c = hexc(["7a7a76", "6a5a50", "70706a"][rng.randi() % 3])
	var snow := 1.0 if rng.randf() < 0.85 else 0.55
	# most roofs carry a thick slab of snow; on some the wind or a stove has thinned it and the iron shows in streaks
	var slab := snow > 0.9 and (not lot.outer or rng.randf() < 0.7) and rng.randf() < 0.75
	if snow > 0.9 and not slab: snow = rng.randf_range(0.62, 0.85)
	roof_c.a = snow
	# along the front edge's direction: x from -0.1 to length + 0.1; across: out from the front face (n) inward
	var xa := -0.12
	var xb := length + 0.12
	var front_out := o
	var back_out := -depth - o
	var ridge := -depth * 0.5
	var p0 := func(x: float, out: float, y: float) -> Vector3: return fe.o + fe.r * x + fe.n * out + Vector3.UP * y
	# (under a slab of snow the iron is never seen: only the snow is drawn there)
	if not slab:
		k.push_tint(roof_c)
		k.quad_m("corrugated", p0.call(xa, front_out, H - o * rise / (depth * 0.5)), p0.call(xb, front_out, H - o * rise / (depth * 0.5)), p0.call(xb, ridge, H + rise), p0.call(xa, ridge, H + rise))
		k.quad_m("corrugated", p0.call(xb, back_out, H - o * rise / (depth * 0.5)), p0.call(xa, back_out, H - o * rise / (depth * 0.5)), p0.call(xa, ridge, H + rise), p0.call(xb, ridge, H + rise))
		k.pop_tint()
	# fascia boards along both eaves, and the undersides of the overhang
	var fascia := Color(0.32, 0.27, 0.22) if lot.style != "conv" else (spec.trim as Color) * 0.8
	var ye := H - o * rise / (depth * 0.5)
	k.push_tint(fascia)
	for side: float in [front_out, back_out]:
		var y0 := ye - 0.18
		var a: Vector3 = p0.call(xa, side, y0)
		var bb: Vector3 = p0.call(xb, side, y0)
		var c: Vector3 = p0.call(xb, side, ye + 0.02)
		var d: Vector3 = p0.call(xa, side, ye + 0.02)
		if side < 0.0: k.quad_m("planks", bb, a, d, c)
		else: k.quad_m("planks", a, bb, c, d)
	k.pop_tint()
	k.push_tint(Color(0.3, 0.28, 0.27))
	k.quad_m("planks", p0.call(xb, front_out, ye - 0.01), p0.call(xa, front_out, ye - 0.01), p0.call(xa, 0.0, H - 0.01), p0.call(xb, 0.0, H - 0.01))
	k.quad_m("planks", p0.call(xa, back_out, ye - 0.01), p0.call(xb, back_out, ye - 0.01), p0.call(xb, -depth, H - 0.01), p0.call(xa, -depth, H - 0.01))
	k.pop_tint()
	# the gable ends: wall up to the ridge, a verge board
	var key: String = spec.wall
	var gt: Color = spec.paint2 if lot.style == "conv" else spec.paint
	for end: Array in [[0.0, -1.0], [length, 1.0]]:
		var x: float = end[0]
		var a: Vector3 = p0.call(x, 0.0, H)
		var bb: Vector3 = p0.call(x, -depth, H)
		var top: Vector3 = p0.call(x, ridge, H + rise - 0.04)
		if end[1] < 0.0: k.tri(key, bb, a, top, Vector2(0, 0), Vector2(depth * Kit.UV_M, 0), Vector2(depth * 0.5 * Kit.UV_M, -rise * Kit.UV_M), gt, gt, gt * 0.9)
		else: k.tri(key, a, bb, top, Vector2(0, 0), Vector2(depth * Kit.UV_M, 0), Vector2(depth * 0.5 * Kit.UV_M, -rise * Kit.UV_M), gt, gt, gt * 0.9)
	# a ridge cap
	k.push_tint(roof_c * 0.8)
	k.beam("corrugated", p0.call(xa, ridge, H + rise + 0.03), p0.call(xb, ridge, H + rise + 0.03), 0.22, 0.06, Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	# the snow on both slopes, curling over the eaves; on a warm roof (a stove under it) only the texture's dusting
	if slab:
		var t := rng.randf_range(0.13, 0.22)
		# no two roofs' snow quite the same white
		var g := rng.randf_range(0.9, 1.0)
		k.push_tint(Color(g, g, g * 1.02 if g < 0.98 else g))
		var front_n := _plane_n(fe.r, p0.call(xa, front_out, ye) - p0.call(xa, ridge, H + rise))
		Snow.slope(k, p0.call(xa - 0.02, front_out, ye), p0.call(xb + 0.02, front_out, ye), p0.call(xa - 0.02, ridge, H + rise), p0.call(xb + 0.02, ridge, H + rise), front_n, t, 0.2, rng)
		var back_n := _plane_n(fe.r, p0.call(xa, back_out, ye) - p0.call(xa, ridge, H + rise))
		Snow.slope(k, p0.call(xb + 0.02, back_out, ye), p0.call(xa - 0.02, back_out, ye), p0.call(xb + 0.02, ridge, H + rise), p0.call(xa - 0.02, ridge, H + rise), back_n, t * rng.randf_range(0.8, 1.1), 0.18, rng)
		Snow.ridge(k, p0.call(xa, ridge, H + rise + t * 0.7), p0.call(xb, ridge, H + rise + t * 0.7), Vector3.UP, 0.34, 0.07, 0.02, rng)
		k.pop_tint()
	# a gutter along the front eave and its downpipe crossing the front (as La Boca's do), on the iron houses
	if lot.style in ["conv", "brick"] and not lot.outer and not ends:
		var gy := ye - 0.06
		var g0: Vector3 = p0.call(xa + 0.05, front_out + 0.02, gy)
		var g1: Vector3 = p0.call(xb - 0.05, front_out + 0.02, gy)
		k.tube("steel", PackedVector3Array([g0, g1]), 0.065, 5, Color(0.42, 0.43, 0.44))
		Snow.ridge(k, g0 + Vector3.UP * 0.05, g1 + Vector3.UP * 0.05, Vector3.UP, 0.12, 0.06, 0.02, rng, 0.3, false)
		var from_end := rng.randf() < 0.5
		var xs := xb - 0.25 if from_end else xa + 0.25
		var xd := lerpf(xa, xb, rng.randf_range(0.3, 0.7))
		var mid_y: float = spec.f1 + rng.randf_range(0.2, 0.8)
		var path := PackedVector3Array([p0.call(xs, front_out + 0.02, gy - 0.02), p0.call(xs, 0.08, gy - 0.35), p0.call(xs, 0.08, mid_y + 0.9), p0.call(xd, 0.08, mid_y), p0.call(xd, 0.08, 0.25), p0.call(xd, 0.18, 0.08)])
		k.tube("steel", path, 0.045, 5, Color(0.4, 0.41, 0.42))
	if ends and lot.style == "shed" and not lot.outer:
		# a row of skylights down the warehouse roof
		pass
	# stovepipes and chimneys
	if lot.style == "conv":
		var n := 1 + (1 if length > 7.0 and rng.randf() < 0.5 else 0)
		for i: int in range(n):
			var at: Vector3 = p0.call(rng.randf_range(1.0, length - 1.0), -depth * rng.randf_range(0.25, 0.42), 0.0)
			at.y = H + rise * (1.0 - absf(-(at - fe.o).dot(fe.n) - depth * 0.5) / (depth * 0.5)) - 0.05
			_stovepipe(k, at, rng.randf_range(0.8, 1.3))
	elif lot.style == "machine-house":
		var at2: Vector3 = p0.call(length * 0.75, -depth * 0.3, 0.0)
		at2.y = H
		_chimney(k, at2, rise + 2.8, spec)
	elif rng.randf() < 0.4 and not lot.outer:
		var at3: Vector3 = p0.call(rng.randf_range(1.0, length - 1.0), -depth * 0.5, H + rise - 0.3)
		_chimney(k, at3, 1.0, spec)

## The outward (upward) normal of a roof plane through `along` and `down`.
static func _plane_n(along: Vector3, down: Vector3) -> Vector3:
	var n := along.cross(down).normalized()
	return -n if n.y < 0.0 else n

static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v: Vector2 in p: c += v
	return c / float(p.size())

static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v: Vector2 in p: r = r.expand(v)
	return r

# ---------------------------------------------------------------------------------------------------------------
# Patios, steps
# ---------------------------------------------------------------------------------------------------------------
## Inside a block: a shed against the back wall, washing on a line, a bare tree or a palm, firewood, barrels; in one
## or two of them the snowman the children made, and their tracks.
func _patio(r: Rect2, k: Kit, kd: Kit, index: int) -> void:
	var c := r.get_center()
	var tree_x := c.x
	if r.size.x > 3.5 and r.size.y > 3.0:
		var at := Vector3(c.x + rng.randf_range(-r.size.x * 0.3, r.size.x * 0.3), 0.0, c.y + rng.randf_range(-r.size.y * 0.2, r.size.y * 0.2))
		tree_x = at.x
		if index % 4 == 1: palms.append(at)
		else:
			trees.append(at)
			# how far its crown may spread: over the patio and the roofs round it, never out over a street
			tree_room.append(minf(r.size.x, r.size.y) * 0.5 + 5.5)
		if r.size.x > 14.0:
			trees.append(Vector3(r.position.x + rng.randf_range(2.0, 4.0), 0.0, c.y + rng.randf_range(-0.5, 0.5)))
			trees.append(Vector3(r.end.x - rng.randf_range(2.0, 4.0), 0.0, c.y + rng.randf_range(-0.5, 0.5)))
			tree_room.append(minf(r.size.x, r.size.y) * 0.5 + 5.5)
			tree_room.append(minf(r.size.x, r.size.y) * 0.5 + 5.5)
	# a few big patios are a workshop's yard: a car stands in it under the snow, along the south wall, away from the tree
	var yard := r.size.x > 9.0 and r.size.y > 6.0 and rng.randf() < 0.4
	if yard:
		var cx := r.end.x - 3.0 if tree_x < c.x else r.position.x + 3.0
		yard_cars.append([Vector3(cx, 0.0, r.end.y - 1.5), 0.0 if rng.randf() < 0.5 else PI])
	# somebody's path across the patio, from a back door to the far wall
	if r.size.x > 3.0 and r.size.y > 2.0 and rng.randf() < 0.7:
		var p0 := Vector2(rng.randf_range(r.position.x + 0.5, r.end.x - 0.5), r.end.y - 0.2)
		var p1 := Vector2(c.x + rng.randf_range(-1.0, 1.0), c.y)
		var p2 := Vector2(rng.randf_range(r.position.x + 0.5, r.end.x - 0.5), r.position.y + 0.3)
		b.trail(kd, PackedVector2Array([p0, p1, p2]))
	if r.size.x > 4.0 and rng.randf() < 0.6:
		# a lean-to shed against the patio's north wall
		var w := minf(rng.randf_range(2.0, 3.2), r.size.x - 1.0)
		var x := rng.randf_range(r.position.x + 0.2, r.end.x - w - 0.2)
		var z0 := r.position.y
		var d := minf(1.6, r.size.y * 0.4)
		var col := hexc(CONV_PAINT[rng.randi() % CONV_PAINT.size()])
		k.push_tint(col)
		k.box("chapa", Vector3(x + w * 0.5, 1.0, z0 + d * 0.5), Vector3(w, 2.0, d), Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
		k.push_tint(hexc(ROOF[rng.randi() % ROOF.size()]))
		k.quad_m("corrugated", Vector3(x - 0.1, 1.95, z0 + d + 0.25), Vector3(x + w + 0.1, 1.95, z0 + d + 0.25), Vector3(x + w + 0.1, 2.4, z0), Vector3(x - 0.1, 2.4, z0))
		k.pop_tint()
	if r.size.x > 5.0 and rng.randf() < 0.55:
		var y := 1.9
		var z := c.y + rng.randf_range(-r.size.y * 0.25, r.size.y * 0.25)
		var a := Vector3(r.position.x + 0.5, y, z)
		var d2 := Vector3(minf(r.end.x - 0.5, r.position.x + rng.randf_range(4.0, 9.0)), y, z)
		for q: Vector3 in [a, d2]:
			k.beam("planks", Vector3(q.x, 0.0, q.z), q + Vector3(0, 0.1, 0), 0.07, 0.07, Color(0.4, 0.36, 0.32), Color(0.5, 0.45, 0.4))
		b._props.wire(k, a, d2, 0.12, 0.008, Color(0.75, 0.75, 0.72), 6)
		var x2 := a.x + 0.3
		while x2 < d2.x - 0.5:
			var ww := rng.randf_range(0.4, 0.9)
			var col2: Color = [Color(0.92, 0.92, 0.9), Color(0.62, 0.68, 0.82), Color(0.86, 0.62, 0.56), Color(0.9, 0.86, 0.6)][rng.randi() % 4]
			var drop := rng.randf_range(0.5, 1.1)
			kd.quad_rect("facade_cut", Vector3(x2, y - drop, z), Vector3(x2 + ww, y - drop, z), Vector3(x2 + ww, y - 0.04, z), Vector3(x2, y - 0.04, z), CLOTH_UV, col2 * 0.85, col2)
			x2 += ww + rng.randf_range(0.1, 0.4)
	if rng.randf() < 0.5 and not yard:
		var at2 := Vector3(rng.randf_range(r.position.x + 0.6, r.end.x - 0.6), 0.0, r.end.y - 0.45)
		b._props.firewood(k, at2, 0.0, 1.4, 4)
	if rng.randf() < 0.5:
		b._props.barrel(k, Vector3(rng.randf_range(r.position.x + 0.5, r.end.x - 0.5), 0.0, r.position.y + 0.5), Color(0.5, 0.42, 0.34), 0.0)
	if index in [2, 5] or (index == 0 and plan.patios.size() < 3) or rng.randf() < 0.4:
		_snowman(k, kd, Vector3(c.x + 1.2, 0.0, c.y))
	if r.size.x > 3.0 and rng.randf() < 0.55:
		# a sled left leaning on the patio's south wall, or lying where it was dropped
		if rng.randf() < 0.6 and not yard:
			sled(k, Vector3(rng.randf_range(r.position.x + 0.6, r.end.x - 0.6), 0.0, r.end.y - 0.32), 0.0, 1.05)
		else:
			sled(k, Vector3(c.x - 1.0, 0.0, c.y + rng.randf_range(-0.8, 0.8)), rng.randf() * TAU)

## A child's sled of the fifties: two iron runners curled up at the front, wooden struts and slats painted red or
## green, a rope. lean > 0 stands it up against a wall behind it (radians from lying flat); 0 leaves it in the snow.
func sled(k: Kit, at: Vector3, yaw: float, lean: float = 0.0) -> void:
	var iron := Color(0.2, 0.2, 0.21)
	var wood := Color(0.42, 0.32, 0.22)
	var paint: Color = [Color(0.62, 0.16, 0.12), Color(0.2, 0.4, 0.26), Color(0.55, 0.42, 0.24)][rng.randi() % 3]
	# (leaning: its curled front end up against the wall on the local +z side, its back end on the ground)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -lean)
	k.push(Transform3D(basis, at + Vector3(0, 0.5 * sin(lean), 0)))
	for sx: float in [-0.17, 0.17]:
		k.beam("steel", Vector3(sx, 0.02, -0.5), Vector3(sx, 0.02, 0.36), 0.022, 0.026, iron, iron * 1.4)
		k.beam("steel", Vector3(sx, 0.02, 0.36), Vector3(sx, 0.17, 0.5), 0.022, 0.022, iron, iron * 1.4)
		for z: float in [-0.34, 0.24]:
			k.beam("planks", Vector3(sx, 0.03, z), Vector3(sx, 0.16, z), 0.03, 0.03, wood, wood)
	k.push_tint(paint)
	k.box("planks", Vector3(0, 0.175, -0.04), Vector3(0.44, 0.025, 0.84), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.AUTO, 55)
	k.pop_tint()
	if lean == 0.0:
		Snow.box_top(k, Vector3(0, 0.19, -0.04), Vector2(0.4, 0.78), 0.04, rng)
	k.pop()

## The children's snowman: three balls of wet snow, a scarf, coal eyes, a carrot, sticks for arms, an old hat; their
## tracks round it.
func _snowman(k: Kit, kd: Kit, at: Vector3, scale: float = 1.0, tracks: bool = true) -> void:
	var y := 0.0
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
	for r: float in [0.42, 0.32, 0.22]:
		Snow.ball(k, at + Vector3(0, y, 0) + lean * y, r * scale)
		y += r * 1.7 * scale
	var neck := at + Vector3(0, (0.84 + 0.28) * scale, 0) + lean * 1.1
	k.push_tint([Color(0.7, 0.14, 0.1), Color(0.2, 0.3, 0.6), Color(0.3, 0.45, 0.25)][rng.randi() % 3])
	k.lathe("planks", neck, PackedVector2Array([Vector2(0.27 * scale, 0.0), Vector2(0.27 * scale, 0.09 * scale), Vector2(0.0, 0.1 * scale)]), 7)
	k.pop_tint()
	var head := at + Vector3(0, 1.36 * scale, 0) + lean * 1.4
	var face := Vector3(sin(rng.randf() * TAU), 0, cos(rng.randf() * TAU)).normalized()
	for side: float in [-1.0, 1.0]:
		var arm := Vector3(face.z, 0, -face.x) * side
		k.beam("planks", at + Vector3(0, 0.98 * scale, 0) + arm * 0.26 * scale, at + Vector3(0, 1.25 * scale, 0) + arm * 0.72 * scale, 0.025, 0.025, Color(0.25, 0.2, 0.16), Color(0.3, 0.24, 0.2))
		k.box("steel", head + face * 0.19 * scale + arm * 0.07 * scale + Vector3(0, 0.06 * scale, 0), Vector3(0.04, 0.04, 0.04) * scale, Color(0.05, 0.05, 0.05), Color(0.08, 0.08, 0.08))
	k.push_tint(Color(0.9, 0.45, 0.15))
	k.beam("planks", head + face * 0.2 * scale, head + face * 0.36 * scale, 0.04 * scale, 0.04 * scale)
	k.pop_tint()
	if rng.randf() < 0.6:
		# an old hat on top
		k.push_tint(Color(0.18, 0.17, 0.17))
		k.lathe("planks", head + Vector3(0, 0.17 * scale, 0), PackedVector2Array([Vector2(0.2 * scale, 0.0), Vector2(0.2 * scale, 0.02), Vector2(0.12 * scale, 0.03), Vector2(0.12 * scale, 0.16 * scale), Vector2(0.0, 0.17 * scale)]), 7)
		k.pop_tint()
	if tracks: b.kid_tracks(at)

static func _ball(r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in range(9):
		var a := -PI * 0.5 + PI * float(i) / 8.0
		p.append(Vector2(maxf(cos(a) * r, 0.0), r + sin(a) * r))
	return p

## The steps across the cut corners: two granite treads filling the corner, so nobody stands where the house is.
func _steps() -> void:
	var k := Kit.new()
	for t: PackedVector2Array in plan.steps:
		var a := t[0]
		var p := t[1]
		var c := t[2]
		for s: Array in [[0.0, 0.12, 1.0], [0.12, 0.24, 0.6]]:
			var y0: float = s[0]
			var y1: float = s[1]
			var f: float = s[2]
			var aa := p.lerp(a, f)
			var cc := p.lerp(c, f)
			var A := Vector3(aa.x, y1, aa.y)
			var P := Vector3(p.x, y1, p.y)
			var C := Vector3(cc.x, y1, cc.y)
			k.push_tint(Color(0.78, 0.77, 0.76))
			k.tri("stone", A, P, C, Vector2(aa.x, aa.y) * Kit.UV_M, Vector2(p.x, p.y) * Kit.UV_M, Vector2(cc.x, cc.y) * Kit.UV_M)
			# the riser, facing the street
			k.quad_m("stone", Vector3(aa.x, y0, aa.y), Vector3(cc.x, y0, cc.y), Vector3(cc.x, y1, cc.y), Vector3(aa.x, y1, aa.y), Vector2.ZERO, Color(0.6, 0.6, 0.6), Color.WHITE)
			k.pop_tint()
	if not k.surfs.is_empty():
		triangles += k.triangle_count()
		b.commit(k, b, "CornerSteps", true, false)
