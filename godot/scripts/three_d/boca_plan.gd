extends RefCounted
## The plan of La Boca's houses: every building rectangle of the rules, and the blocks of the city round the map, cut
## into lots, each with its outline, its height, its style and what each of its walls faces (a street, a neighbour, a
## patio). Shared by the ground (boca_ground.gd: the dark foot of the street walls, the patios inside the blocks, the
## steps at the chamfered corners) and the houses (boca_houses.gd), so both agree. The same data gives the same plan.
##
## A lot's outline runs poly[i] -> poly[i + 1]; the outward normal of an edge (dx, dz) is (-dz, dx), so a rectangle is
## listed south-west, south-east, north-east, north-west and its edges are south, east, north, west. Nothing here is
## solid for the rules: the houses stand only inside the rules' building rectangles (or outside the map).

class Lot:
	extends RefCounted
	var poly := PackedVector2Array()
	## Per edge: "front" (a street or a courtyard you can walk in), "chamfer" (the cut corner, the shop door), "party"
	## (against a neighbour), "back" (onto the patio inside the block).
	var edges: Array[String] = []
	var style: String = "ital"
	var floors: int = 2
	var height: float = 8.0
	var roof: String = "flat"
	## The edge the house fronts (the ridge of a gable runs along it).
	var front: int = 0
	var seed: int = 0
	## Lots committed together (about 25 m of a block).
	var group: String = ""
	## On a chamfered corner: the shop there ("almacen", "bar", "despacho") or "".
	var corner: String = ""
	## Outside the playable map: built with fewer details.
	var outer: bool = false
	## Which side of the block the lot stands on, for the deeper patio houses ("s", "e", "n", "w", "" = the whole depth).
	var side: String = ""

const DEPTH := 9.0
const CHAMFER := 2.6
const SHOPS := ["almacen", "bar", "despacho", "almacen", "bar"]

var lots: Array = []
## The open patios inside the blocks (metres, x and z): snow nobody walks on, a tree, a shed, washing, a snowman.
var patios: Array[Rect2] = []
## The steps across each cut corner: [PackedVector2Array triangle].
var steps: Array = []
## Outside the map: the blocks of the city that goes on beyond it, as Rect2 (for the ground and the houses).
var outer_blocks: Array[Rect2] = []
var map_size := Vector2(240.0, 150.0)
var _solids: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
var _shop: int = 0

func _init(data: Dictionary) -> void:
	_rng.seed = 19580801
	map_size = Vector2(float(data.width), float(data.height)) / 32.0
	var w: Dictionary = data.get("bocaWorld", {})
	var blocks: Array = []
	for o: Dictionary in data.get("obstacles", []):
		if str(o.kind) in ["building", "wall"]:
			_solids.append(_rect(o))
		if str(o.kind) == "building": blocks.append(o)
	for r: Rect2 in _outer(w): _solids.append(r)
	# the café is walls in the rules; for its neighbours it is a building
	var cafe: Array = w.get("cafe", [])
	if cafe.size() == 4: _solids.append(Rect2(float(cafe[0]), float(cafe[1]), float(cafe[2]) - float(cafe[0]), float(cafe[3]) - float(cafe[1])))
	for o: Dictionary in blocks:
		var id := str(o.id)
		var style := "mixed"
		if id.begins_with("row-"): style = "conv"
		elif id.begins_with("conv-"): style = "convent"
		elif id.begins_with("sheds-"): style = "shed"
		elif id in ["guardia", "machine-house", "boat-shed"]: style = id
		_block(_rect(o), id, style, false)
	var i := 0
	for r: Rect2 in outer_blocks:
		_block(r, "outer-%d" % i, "shed" if r.position.y > map_size.y - 10.0 and r.position.y < map_size.y else "mixed", true)
		i += 1

static func _rect(o: Dictionary) -> Rect2:
	return Rect2(float(o.x) / 32.0, float(o.y) / 32.0, float(o.w) / 32.0, float(o.h) / 32.0)

## The blocks of the city round the map: across a lane behind the north row, west and east of the map along its own
## streets, and beyond the sheds of the far bank. Laid on the same lines as the map's streets.
func _outer(w: Dictionary) -> Array[Rect2]:
	var W := map_size.x
	var H := map_size.y
	var west: Array = w.get("westSt", [50.0, 56.0])
	var mid: Array = w.get("midSt", [120.0, 126.0])
	var east: Array = w.get("eastSt", [172.0, 178.0])
	var row_s: float = float(w.get("rowS", 20.0))
	var block_n: Array = w.get("blockN", [46.0, 64.0])
	var block_s: Array = w.get("blockS", [70.0, 94.0])
	var far: Array = w.get("far", [134.0, 150.0])
	var xs: Array = [[-52.0, -8.0], [0.0, float(west[0])], [float(west[1]), float(mid[0])], [float(mid[1]), float(east[0])], [float(east[1]), W], [W + 8.0, W + 52.0]]
	# the lane behind the north row (z -7..0), then a block of houses
	for span: Array in xs:
		outer_blocks.append(Rect2(float(span[0]), -34.0, float(span[1]) - float(span[0]), 27.0))
	# west and east of the map, across a street 8 m wide, in the map's own bands
	for band: Vector2 in [Vector2(0.0, row_s), Vector2(float(block_n[0]), float(block_n[1])), Vector2(float(block_s[0]), float(block_s[1]))]:
		outer_blocks.append(Rect2(-52.0, band.x, 44.0, band.y - band.x))
		outer_blocks.append(Rect2(W + 8.0, band.x, 44.0, band.y - band.x))
	# the far bank: sheds on beyond the map's west and east edges, and warehouses beyond the street behind them
	outer_blocks.append(Rect2(-52.0, H - 8.0, 44.0, 8.0))
	# (east of the map the far bank's sheds leave room for the road bridge's approach)
	outer_blocks.append(Rect2(W + 24.0, H - 8.0, 28.0, 8.0))
	for span: Array in [[-52.0, -8.0], [0.0, 46.0], [54.0, 98.0], [106.0, 150.0], [158.0, W], [W + 8.0, W + 52.0]]:
		outer_blocks.append(Rect2(float(span[0]), H + 8.0, float(span[1]) - float(span[0]), 26.0))
	# a second ring, for the view from high up: more of the far bank, and the city on west and east
	for span: Array in [[-96.0, -60.0], [-52.0, -8.0], [0.0, 46.0], [54.0, 98.0], [106.0, 150.0], [158.0, W], [W + 8.0, W + 52.0], [W + 60.0, W + 96.0]]:
		outer_blocks.append(Rect2(float(span[0]), H + 42.0, float(span[1]) - float(span[0]), 24.0))
	for band: Vector2 in [Vector2(-34.0, -7.0), Vector2(0.0, row_s), Vector2(float(block_n[0]), float(block_n[1])), Vector2(float(block_s[0]), float(block_s[1])), Vector2(H - 8.0, H), Vector2(H + 8.0, H + 34.0)]:
		outer_blocks.append(Rect2(-96.0, band.x, 36.0, band.y - band.x))
		outer_blocks.append(Rect2(W + 60.0, band.x, 36.0, band.y - band.x))
	return outer_blocks

## Is the ground just outside this point taken by another building (a neighbour) or open (a street, a courtyard)?
func _solid_at(p: Vector2, own: Rect2) -> bool:
	for r: Rect2 in _solids:
		if r == own: continue
		if r.has_point(p): return true
	return false

## Which sides of a block face the open (south, east, north, west).
func _fronts(r: Rect2) -> Array[bool]:
	var out: Array[bool] = []
	var probes: Array = [
		[Vector2(r.position.x, r.end.y + 0.6), Vector2(1, 0), r.size.x],
		[Vector2(r.end.x + 0.6, r.end.y), Vector2(0, -1), r.size.y],
		[Vector2(r.end.x, r.position.y - 0.6), Vector2(-1, 0), r.size.x],
		[Vector2(r.position.x - 0.6, r.position.y), Vector2(0, 1), r.size.y],
	]
	for probe: Array in probes:
		var open := 0
		for t: float in [0.2, 0.5, 0.8]:
			if not _solid_at((probe[0] as Vector2) + (probe[1] as Vector2) * float(probe[2]) * t, r): open += 1
		out.append(open >= 2)
	return out

func _block(r: Rect2, id: String, style: String, outer: bool) -> void:
	var fronts := _fronts(r)
	var special := style in ["guardia", "machine-house", "boat-shed"]
	if special:
		var lot := _lot(Rect2(r), id, style, outer)
		for e: int in range(4): lot.edges[e] = "front" if fronts[e] else "party"
		lot.front = 0
		lot.group = id
		lots.append(lot)
		return
	# houses about 9 m deep round a patio, if the block is deep enough to leave one at least 3 m across
	var depth := clampf((minf(r.size.x, r.size.y) - 3.0) * 0.5, 7.0, DEPTH)
	var patio := style != "shed" and r.size.x >= depth * 2.0 + 3.0 and r.size.y >= depth * 2.0 + 3.0
	if patio:
		patios.append(r.grow(-depth))
		# the south and north rows take the full width; the west and east rows fill between them
		_row(Rect2(r.position.x, r.end.y - depth, r.size.x, depth), 0, fronts, r, id + "s", style, outer, "s")
		_row(Rect2(r.position.x, r.position.y, r.size.x, depth), 2, fronts, r, id + "n", style, outer, "n")
		_row(Rect2(r.position.x, r.position.y + depth, depth, r.size.y - depth * 2.0), 3, fronts, r, id + "w", style, outer, "w")
		_row(Rect2(r.end.x - depth, r.position.y + depth, depth, r.size.y - depth * 2.0), 1, fronts, r, id + "e", style, outer, "e")
	else:
		# a narrow block: houses through from one street to the other, along its longer side
		var along_x := r.size.x >= r.size.y
		var main := 0 if along_x else 1
		if along_x and not fronts[0] and fronts[2]: main = 2
		if not along_x and not fronts[1] and fronts[3]: main = 3
		_row(r, main, fronts, r, id, style, outer, "")

## One row of houses along a side of a block (or through it): lots 6 to 10 m wide, the ends cut at the block's corners
## where two streets meet.
func _row(strip: Rect2, side: int, fronts: Array[bool], block: Rect2, id: String, style: String, outer: bool, where: String) -> void:
	if strip.size.x < 1.0 or strip.size.y < 1.0: return
	var along_x := side == 0 or side == 2
	var length := strip.size.x if along_x else strip.size.y
	var widths: Vector2 = Vector2(9.0, 15.0) if style == "shed" else Vector2(5.5, 9.5)
	var cuts: Array[float] = [0.0]
	var pos := 0.0
	while pos < length - 0.01:
		var step := _rng.randf_range(widths.x, widths.y)
		if length - (pos + step) < widths.x: step = length - pos
		pos = minf(pos + step, length)
		cuts.append(pos)
	var group_start := 0.0
	var group := 0
	for i: int in range(cuts.size() - 1):
		var a := cuts[i]
		var b := cuts[i + 1]
		var seg := Rect2(strip.position.x + a, strip.position.y, b - a, strip.size.y) if along_x else Rect2(strip.position.x, strip.position.y + a, strip.size.x, b - a)
		var lot := _lot(seg, id, _pick_style(style), outer)
		lot.side = where
		lot.front = side
		# what each edge faces: the block's own street sides where the lot touches them; the rest neighbours or patio
		for e: int in range(4):
			var on_edge := _on_block_edge(seg, e, block)
			if on_edge and fronts[e]: lot.edges[e] = "front"
			elif on_edge: lot.edges[e] = "party"
			elif where != "" and e == (side + 2) % 4: lot.edges[e] = "back"
			else: lot.edges[e] = "party"
		# out of the map a whole block goes as one piece (nothing fades there, no lamp of the board reaches it)
		lot.group = "%s_%d" % [id, group] if not outer else id.trim_suffix(where)
		if b - group_start > 28.0:
			group_start = b
			group += 1
		_chamfer(lot, block, fronts)
		lots.append(lot)

## Is there a street (open ground at least 5 m deep) beyond this side of the block, along its middle half?
func _street_beyond(block: Rect2, e: int) -> bool:
	var n: Vector2 = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][e]
	var mid: Vector2 = [Vector2(block.get_center().x, block.end.y), Vector2(block.end.x, block.get_center().y),
		Vector2(block.get_center().x, block.position.y), Vector2(block.position.x, block.get_center().y)][e]
	var along := Vector2(-n.y, n.x)
	var half := (block.size.x if e % 2 == 0 else block.size.y) * 0.35
	for t: float in [-1.0, 0.0, 1.0]:
		var p := mid + along * half * t
		for d: float in [1.0, 3.0, 5.0]:
			if _solid_at(p + n * d, block): return false
	return true

static func _on_block_edge(seg: Rect2, e: int, block: Rect2) -> bool:
	match e:
		0: return absf(seg.end.y - block.end.y) < 0.01
		1: return absf(seg.end.x - block.end.x) < 0.01
		2: return absf(seg.position.y - block.position.y) < 0.01
		_: return absf(seg.position.x - block.position.x) < 0.01

func _pick_style(style: String) -> String:
	match style:
		"conv": return "conv" if _rng.randf() < 0.72 else "ital"
		"convent": return "conv"
		"shed": return "shed"
		_:
			var t := _rng.randf()
			return "ital" if t < 0.5 else ("conv" if t < 0.86 else "brick")

func _lot(r: Rect2, id: String, style: String, outer: bool) -> Lot:
	var lot := Lot.new()
	lot.poly = PackedVector2Array([Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)])
	lot.edges = ["party", "party", "party", "party"]
	lot.style = style
	lot.outer = outer
	lot.seed = _rng.randi()
	lot.group = id
	match style:
		"conv":
			# single-family iron houses of one or two floors; conventillos of three levels round their galleries
			var t := _rng.randf()
			lot.floors = 1 if t < 0.25 and not id.begins_with("conv-") else (3 if t > 0.75 or (id.begins_with("conv-") and t > 0.4) else 2)
			lot.height = [0.0, _rng.randf_range(4.4, 5.2), _rng.randf_range(7.0, 8.2), _rng.randf_range(9.8, 10.8)][lot.floors]
			lot.roof = "gable"
		"ital":
			lot.floors = 2 if _rng.randf() < 0.85 else 1
			lot.height = _rng.randf_range(7.6, 9.0) if lot.floors == 2 else _rng.randf_range(4.8, 5.6)
			lot.roof = "flat"
		"brick":
			lot.floors = 1
			lot.height = _rng.randf_range(5.0, 6.4)
			lot.roof = "gable"
		"shed":
			lot.floors = 1
			lot.height = _rng.randf_range(5.6, 7.0)
			lot.roof = "gable_end"
		"guardia":
			lot.floors = 2
			lot.height = 8.6
			lot.roof = "flat"
		"machine-house":
			lot.floors = 1
			lot.height = 6.2
			lot.roof = "gable"
		"boat-shed":
			lot.floors = 1
			lot.height = 4.6
			lot.roof = "gable"
	if outer and style != "shed" and _rng.randf() < 0.3:
		lot.floors = 3
		lot.height = _rng.randf_range(10.5, 12.0)
		lot.roof = "flat"
	return lot

## Cuts the corner of a lot that stands where two streets meet (an ochava): the chamfer becomes the shop's door.
func _chamfer(lot: Lot, block: Rect2, fronts: Array[bool]) -> void:
	if lot.style == "shed": return
	var corners: Array = [[0, 1, Vector2(block.end.x, block.end.y)], [1, 2, Vector2(block.end.x, block.position.y)],
		[2, 3, Vector2(block.position.x, block.position.y)], [3, 0, Vector2(block.position.x, block.end.y)]]
	for c: Array in corners:
		var ea: int = c[0]
		var eb: int = c[1]
		var at: Vector2 = c[2]
		if lot.edges[ea] != "front" or lot.edges[eb] != "front": continue
		# only where two real streets meet (not a hallway or a courtyard's corner)
		if not _street_beyond(block, ea) or not _street_beyond(block, eb): continue
		# the lot's own corner between those two edges must be the block's corner
		var k := eb
		if lot.poly[k].distance_to(at) > 0.01: continue
		var p := lot.poly[k]
		var prev := lot.poly[(k + lot.poly.size() - 1) % lot.poly.size()]
		var next := lot.poly[(k + 1) % lot.poly.size()]
		var a := p + (prev - p).normalized() * CHAMFER
		var b := p + (next - p).normalized() * CHAMFER
		var poly := PackedVector2Array()
		var edges: Array[String] = []
		for i: int in range(lot.poly.size()):
			if i == k:
				poly.append(a)
				edges.append("chamfer")
				poly.append(b)
				edges.append(lot.edges[i])
			else:
				poly.append(lot.poly[i])
				edges.append(lot.edges[i])
		lot.poly = poly
		lot.edges = edges
		if lot.front >= k: lot.front += 1
		lot.corner = SHOPS[_shop % SHOPS.size()]
		_shop += 1
		if lot.style == "conv" or lot.roof == "gable": lot.style = "ital"
		lot.roof = "flat"
		lot.floors = 2
		lot.height = maxf(lot.height, 7.8)
		steps.append(PackedVector2Array([a, p, b]))
		return
