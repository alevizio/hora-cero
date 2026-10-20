extends RefCounted
## Icons batch C for studio.gd: La Boca's own kit and places (the tram's controller handle, the lineman's cord, his
## folding ladder, the café's cellar hatch, the lamp sector board, the transporter's gondola, a rowing boat, the
## motorman's and the newsboy's caps, a helping hand) and the Plaza de Mayo's (a tram, a subte entrance, a tarpaulin,
## a stretcher). Built with the structures kit and batches A and B's helpers, lit and framed by studio.gd.
const Kit := preload("res://scripts/three_d/structures_kit.gd")
const NAMES := ["handle", "cord", "ladder", "cellar", "lampboard", "gondola", "rowboat", "flatcap", "motorcap", "hand", "tram",
	"subte", "tarp", "stretcher"]

## Batch A (slabs, rings) and batch B (swept solids, loops, balls), found among the studio's modules.
var _a: Object
var _b: Object

# ---------------------------------------------------------------------------------------------------------------
# Materials of this batch (keys prefixed c_)
# ---------------------------------------------------------------------------------------------------------------
func _c_materials(s) -> void:
	for m: Object in s.modules:
		if m.has_method("_slab"): _a = m
		if m.has_method("_b_sweep"): _b = m
	_b._b_materials(s)
	if _a.has_method("_materials"): _a.call("_materials", s)
	var mats: Dictionary = s.mats
	if mats.has("c_skin"):
		return
	var skin := StandardMaterial3D.new()
	skin.vertex_color_use_as_albedo = true
	skin.roughness = 0.62
	skin.metallic_specular = 0.35
	mats["c_skin"] = skin
	# glossy black: a cap's peak, enamel paint, ebonite
	var gloss := StandardMaterial3D.new()
	gloss.vertex_color_use_as_albedo = true
	gloss.roughness = 0.16
	gloss.metallic_specular = 0.8
	mats["c_gloss"] = gloss
	mats["c_copper"] = s._metal(Color(0.95, 0.58, 0.4), 0.85, 0.3)
	# the dark inside of a hole: a stairwell, a cabin, a window
	var dark := StandardMaterial3D.new()
	dark.vertex_color_use_as_albedo = true
	dark.roughness = 1.0
	dark.metallic_specular = 0.0
	mats["c_dark"] = dark
	# wool and tweed: the canvas weave lightened to grey (the vertex colours give the hue), the burlap's nap, matt
	var wool := StandardMaterial3D.new()
	wool.albedo_texture = _b._b_lightened("canvas", 0.42, 0.62)
	wool.vertex_color_use_as_albedo = true
	wool.normal_enabled = true
	wool.normal_texture = load(Kit.TEX_DIR + "burlap_n.png")
	wool.normal_scale = 0.8
	wool.roughness = 0.97
	wool.metallic_specular = 0.25
	wool.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["c_wool"] = wool

static func _mul(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

## A round rod (lathe along +Y turned onto a -> b) of radius r: rungs, poles, rails.
func _rod(k: Kit, key: String, a: Vector3, b: Vector3, r: float, lo: Color, hi: Color, sides: int = 10, wood: bool = false) -> void:
	k.push(_frame_y(a, b))
	k.lathe(key, Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(r, a.distance_to(b)), Vector2(0.0, a.distance_to(b))]), sides, lo, hi, Vector2.ZERO, PackedFloat32Array(), -1.0, wood)
	k.pop()

## Frame at a whose +Y runs toward b.
static func _frame_y(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), a)

# ---------------------------------------------------------------------------------------------------------------
# La Boca
# ---------------------------------------------------------------------------------------------------------------
## The tram's controller handle, lifted off its spindle: a bronze boss with the square socket, a flat arm and the
## turned black grip standing up at its end.
func _handle(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(28.0)), Vector3.ZERO))
	var lo := Color(0.62, 0.55, 0.46)
	var hi := Color(0.95, 0.9, 0.82)
	# the boss
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.19, 0.03), Vector2(0.19, 0.16), Vector2(0.16, 0.2), Vector2(0.12, 0.215), Vector2(0.0, 0.215)]), 28, lo, hi)
	var q := 0.055
	k.quad4("c_dark", Vector3(-q, 0.217, q), Vector3(q, 0.217, q), Vector3(q, 0.217, -q), Vector3(-q, 0.217, -q), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.06, 0.05, 0.04), Color(0.06, 0.05, 0.04), Color(0.06, 0.05, 0.04), Color(0.06, 0.05, 0.04))
	# the arm: a flat bar tapering out from the boss, a little cranked up toward the grip
	var path := PackedVector3Array([Vector3(0.05, 0.1, 0.0), Vector3(0.3, 0.1, 0.0), Vector3(0.6, 0.12, 0.0), Vector3(0.88, 0.15, 0.0), Vector3(1.02, 0.16, 0.0)])
	var sizes := [Vector2(0.11, 0.065), Vector2(0.09, 0.055), Vector2(0.075, 0.05), Vector2(0.07, 0.05), Vector2(0.075, 0.055)]
	_b._b_sweep(k, "brass", path, _b._b_rounded_rect(1.0, 1.0, 0.45, 3), sizes, [Vector3.UP], [_mul(hi, 0.85)], true)
	# the grip: turned ebonite on a brass ferrule
	k.lathe("brass", Vector3(1.02, 0.18, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.075, 0.02), Vector2(0.06, 0.06), Vector2(0.045, 0.08), Vector2(0.0, 0.08)]), 18, lo, hi)
	k.lathe("c_gloss", Vector3(1.02, 0.25, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.058, 0.04), Vector2(0.07, 0.14), Vector2(0.075, 0.24), Vector2(0.068, 0.32), Vector2(0.05, 0.37), Vector2(0.025, 0.39), Vector2(0.0, 0.392)]), 20, Color(0.07, 0.06, 0.06), Color(0.16, 0.14, 0.13))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 34.0, "yaw": 0.0, "margin": 0.06}

## The lineman's cord: a hank of twin flex, its two cloth-braided strands twisted round each other, wound in three
## loose loops and taped on one side; the free end runs out with its strands parted and the bare copper showing.
func _cord(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(8.0)), Vector3.ZERO))
	var path := PackedVector3Array()
	var loops := 3
	var per := 80
	for l: int in range(loops):
		var c := Vector3(-0.08 + 0.08 * float(l), 0.0, -0.04 + 0.04 * float(l))
		for i: int in range(per):
			var a := PI + TAU * float(i) / float(per)
			var t := (float(l) + float(i) / float(per)) / float(loops)
			path.append(c + Vector3(cos(a) * 0.44, 0.045 + 0.06 * t + 0.025 * sin(a * 2.0 + float(l)), sin(a) * 0.34))
	# the free end leaves the last loop on the left and runs out toward the lower right
	var last := path[path.size() - 1]
	var tail := PackedVector3Array()
	for i: int in range(1, 41):
		var t := float(i) / 40.0
		tail.append(last + Vector3(0.05 * t + 0.95 * t * t, 0.03 * sin(t * PI) - 0.02 * t, 0.26 * t + 0.32 * t * t))
	var full := path.duplicate()
	full.append_array(tail)
	var strand := 0.03
	var gap := strand * 0.92
	var twist := 0.22
	var cols := [Color(0.3, 0.2, 0.13), Color(0.16, 0.13, 0.11)]
	var ends: Array = []
	var count := full.size()
	for side: int in range(2):
		var pts := PackedVector3Array()
		var run := 0.0
		for i: int in range(count):
			if i > 0: run += full[i].distance_to(full[i - 1])
			var dir: Vector3 = (full[mini(i + 1, count - 1)] - full[maxi(i - 1, 0)]).normalized()
			var side_v := dir.cross(Vector3.UP).normalized()
			var up := side_v.cross(dir).normalized()
			var ph := run / twist * TAU + PI * float(side)
			# the last few centimetres part: each strand leans away from the other
			var part := smoothstep(0.93, 1.0, float(i) / float(count - 1))
			var off := (side_v * cos(ph) + up * sin(ph)) * gap * (1.0 - part) + side_v * (0.06 * part * (1.0 if side == 0 else -1.0))
			pts.append(full[i] + off)
		var cut := count - 5
		k.tube("canvas", pts.slice(0, cut + 1), strand, 7, cols[side], Vector2(0.0, 0.3 * float(side)), 0.05, 5.0)
		ends.append([pts[cut], pts[count - 1]])
	for e: Array in ends:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var d := (b - a).normalized()
		k.tube("c_copper", PackedVector3Array([a - d * 0.005, b + d * 0.09]), strand * 0.55, 7, Color(1.0, 0.95, 0.9))
	# black tape round the hank, on its left side
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.52, 0.09, -0.02)))
	k.lathe("rubber", Vector3(0.0, -0.07, 0.0), PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.085, 0.01), Vector2(0.085, 0.13), Vector2(0.075, 0.14)]), 16, Color(0.1, 0.1, 0.1), Color(0.2, 0.2, 0.2))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 52.0, "yaw": 0.0, "margin": 0.05}

## Lechuza's folding ladder: two pine flights on iron hinges, lying open, the upper flight lifted a little at the fold.
func _ladder(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-34.0)), Vector3.ZERO))
	var wood := Color(0.86, 0.68, 0.46)
	var wlo := _mul(wood, 0.72)
	var half := 1.05
	var width := 0.5
	var iron := Color(0.34, 0.33, 0.32)
	for flight: int in range(2):
		# the near flight lies flat; the far one rises from the hinge
		var lift := deg_to_rad(0.0 if flight == 0 else 14.0)
		var x0 := -half if flight == 0 else 0.0
		k.push(Transform3D(Basis(Vector3.BACK, lift), Vector3(0.0 if flight == 0 else 0.0, 0.0, 0.0)))
		for zs: float in [-1.0, 1.0]:
			var z := zs * width * 0.5
			k.beam("planks", Vector3(x0 + (0.0 if flight == 0 else 0.02), 0.04, z), Vector3(x0 + half - (0.02 if flight == 0 else 0.0), 0.04, z), 0.06, 0.08, wlo, wood, Vector2(0.1 * float(flight), 0.3 + 0.2 * zs))
			# iron shoe on the foot of each stile
			var foot := x0 + (0.06 if flight == 0 else half - 0.06)
			k.box("blued", Vector3(foot, 0.04, z), Vector3(0.1, 0.09, 0.07), _mul(iron, 1.3), _mul(iron, 1.8))
		for r: int in range(4):
			var x := x0 + half * (float(r) + 0.6) / 4.2
			_rod(k, "planks", Vector3(x, 0.05, -width * 0.5 + 0.03), Vector3(x, 0.05, width * 0.5 - 0.03), 0.026, _mul(wood, 0.8), wood, 10, true)
		k.pop()
	# the hinges at the fold
	for zs: float in [-1.0, 1.0]:
		var z := zs * (width * 0.5 + 0.035)
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.05, z)))
		k.lathe("blued", Vector3(0.0, -0.03, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.06), Vector2(0.0, 0.06)]), 12, _mul(iron, 1.4), _mul(iron, 2.0))
		k.pop()
		k.box("blued", Vector3(-0.1, 0.05, z - zs * 0.005), Vector3(0.2, 0.07, 0.012), _mul(iron, 1.3), _mul(iron, 1.8))
		k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(14.0)), Vector3.ZERO))
		k.box("blued", Vector3(0.1, 0.05, z - zs * 0.005), Vector3(0.2, 0.07, 0.012), _mul(iron, 1.3), _mul(iron, 1.8))
		k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 56.0, "yaw": 0.0, "margin": 0.05}

## The café's cellar: a planked hatch standing open on its strap hinges in a brick floor, an iron ring on it, worn
## steps going down into the dark.
func _cellar(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var w := 0.78
	var d := 0.66
	var floor_w := 1.6
	var floor_d := 1.36
	var t := 0.26
	var blo := Color(0.5, 0.39, 0.33)
	var bhi := Color(0.78, 0.64, 0.56)
	# the floor round the opening (four boxes), the opening a little toward the back
	var oz := 0.08
	k.box("brick", Vector3(0.0, -t * 0.5, oz - d * 0.5 - (floor_d * 0.5 - d * 0.5 + oz) * 0.5), Vector3(floor_w, t, floor_d * 0.5 - d * 0.5 + oz), blo, bhi)
	k.box("brick", Vector3(0.0, -t * 0.5, oz + d * 0.5 + (floor_d * 0.5 - d * 0.5 - oz) * 0.5), Vector3(floor_w, t, floor_d * 0.5 - d * 0.5 - oz), blo, bhi)
	for xs: float in [-1.0, 1.0]:
		k.box("brick", Vector3(xs * (w * 0.5 + (floor_w * 0.5 - w * 0.5) * 0.5), -t * 0.5, oz), Vector3(floor_w * 0.5 - w * 0.5, t, d), blo, bhi)
	# a stone kerb round the opening
	var stone := Color(0.72, 0.7, 0.66)
	for xs: float in [-1.0, 1.0]:
		k.box("stone", Vector3(xs * (w * 0.5 + 0.04), 0.01, oz), Vector3(0.08, 0.04, d + 0.16), _mul(stone, 0.8), stone)
	for zs: float in [-1.0, 1.0]:
		k.box("stone", Vector3(0.0, 0.01, oz + zs * (d * 0.5 + 0.04)), Vector3(w, 0.04, 0.08), _mul(stone, 0.8), stone)
	# the well: dark walls, steps going down away from the viewer, darker as they go
	var deep := t - 0.02
	var top := Color(0.16, 0.13, 0.11)
	var bot := Color(0.02, 0.02, 0.02)
	var z0 := oz - d * 0.5
	var z1 := oz + d * 0.5
	var xl := -w * 0.5
	var xr := w * 0.5
	k.quad4("c_dark", Vector3(xl, -deep, z1), Vector3(xl, -deep, z0), Vector3(xl, -0.01, z0), Vector3(xl, -0.01, z1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, top, top)
	k.quad4("c_dark", Vector3(xr, -deep, z0), Vector3(xr, -deep, z1), Vector3(xr, -0.01, z1), Vector3(xr, -0.01, z0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, top, top)
	k.quad4("c_dark", Vector3(-w * 0.5, -deep, oz - d * 0.5), Vector3(w * 0.5, -deep, oz - d * 0.5), Vector3(w * 0.5, -0.01, oz - d * 0.5), Vector3(-w * 0.5, -0.01, oz - d * 0.5),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.01, 0.01, 0.01), Color(0.01, 0.01, 0.01), Color(0.1, 0.08, 0.07), Color(0.1, 0.08, 0.07))
	k.quad4("c_dark", Vector3(xl, -deep, z1), Vector3(xr, -deep, z1), Vector3(xr, -deep, z0), Vector3(xl, -deep, z0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, bot, bot)
	var steps := 3
	for i: int in range(steps):
		var y := -0.05 - 0.065 * float(i)
		var z := z1 - 0.1 - 0.17 * float(i)
		var shade := 1.0 - 0.28 * float(i)
		k.box("stone", Vector3(0.0, y - 0.05, z), Vector3(w - 0.02, 0.1, 0.2), _mul(stone, 0.45 * shade), _mul(stone, 0.9 * shade))
	# the hatch: planks with two ledges behind, hinged at the back edge, standing open
	var open := deg_to_rad(72.0)
	k.push(Transform3D(Basis(Vector3.RIGHT, -open), Vector3(0.0, 0.03, oz - d * 0.5 - 0.02)))
	var wood := Color(0.62, 0.44, 0.3)
	var boards := 4
	for i: int in range(boards):
		var bx := -w * 0.5 - 0.02 + (w + 0.04) * (float(i) + 0.5) / float(boards)
		k.box("planks", Vector3(bx, 0.03, d * 0.5 + 0.02), Vector3((w + 0.04) / float(boards) - 0.012, 0.06, d + 0.04), _mul(wood, 0.75 + 0.05 * float(i % 2)), _mul(wood, 1.0 - 0.06 * float(i % 3)), Vector2(0.3 * float(i), 0.1 * float(i)), Kit.BEAM)
	# ledges on the underside (the side facing the viewer when open)
	for z: float in [0.16, d - 0.12]:
		k.box("planks", Vector3(0.0, -0.025, z), Vector3(w - 0.06, 0.05, 0.1), _mul(wood, 0.6), _mul(wood, 0.8), Vector2(0.5, 0.2), Kit.BEAM)
	# strap hinges and the ring, on the top face (toward the back when open)
	var iron := Color(0.3, 0.3, 0.3)
	for x: float in [-w * 0.3, w * 0.3]:
		k.box("blued", Vector3(x, 0.066, 0.2), Vector3(0.06, 0.012, 0.42), _mul(iron, 1.4), _mul(iron, 2.0))
	_a._torus(k, "blued", Vector3(0.0, 0.07, d * 0.68), Basis.IDENTITY, 0.07, 0.013, 24, 8, _mul(iron, 1.4), _mul(iron, 2.2))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 48.0, "yaw": -22.0, "margin": 0.05}

## The lamp sector board: a cast-iron cabinet on its fluted pedestal, painted green, the door swung open on the
## porcelain fuses and the brass knife lever that puts the quay's lamps out.
func _lampboard(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var green := Color(0.24, 0.36, 0.28)
	var glo := _mul(green, 0.6)
	# the pedestal
	var ped := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.06), Vector2(0.24, 0.1), Vector2(0.2, 0.16), Vector2(0.17, 0.2), Vector2(0.15, 0.62), Vector2(0.18, 0.66), Vector2(0.2, 0.7), Vector2(0.0, 0.7)])
	k.lathe("paint", Vector3.ZERO, ped, 24, glo, green)
	# the cabinet: back, sides, top and bottom; its front open
	var cw := 0.66
	var ch := 0.9
	var cd := 0.34
	var y0 := 0.7
	var wall := 0.035
	k.box("paint", Vector3(0.0, y0 + ch * 0.5, -cd * 0.5 + wall * 0.5), Vector3(cw, ch, wall), glo, green)
	for xs: float in [-1.0, 1.0]:
		k.box("paint", Vector3(xs * (cw * 0.5 - wall * 0.5), y0 + ch * 0.5, 0.0), Vector3(wall, ch, cd), glo, green)
	k.box("paint", Vector3(0.0, y0 + wall * 0.5, 0.0), Vector3(cw, wall, cd), glo, green)
	# the cap: a moulded roof overhanging all round, a ball finial
	k.box("paint", Vector3(0.0, y0 + ch + 0.025, 0.0), Vector3(cw + 0.08, 0.05, cd + 0.08), green, _mul(green, 1.2))
	k.box("paint", Vector3(0.0, y0 + ch + 0.075, 0.0), Vector3(cw - 0.04, 0.05, cd - 0.04), green, _mul(green, 1.25))
	_b._b_ball(k, "paint", Vector3(0.0, y0 + ch + 0.15, 0.0), 0.05, green, _mul(green, 1.3))
	# the slate panel inside, the fuses and the lever
	var slate := Color(0.36, 0.37, 0.38)
	k.box("slate", Vector3(0.0, y0 + ch * 0.5, -cd * 0.5 + wall + 0.012), Vector3(cw - wall * 2.0 - 0.02, ch - 0.08, 0.024), _mul(slate, 0.8), slate)
	var pz := -cd * 0.5 + wall + 0.024
	for i: int in range(3):
		var x := -0.17 + 0.17 * float(i)
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y0 + ch - 0.2, pz)))
		_a._softbox(k, "b_enamel", Vector3.ZERO, Vector3(0.1, 0.07, 0.18), 0.025, Color(0.72, 0.7, 0.66), Color(0.97, 0.96, 0.92), 24)
		k.pop()
		k.box("brass", Vector3(x, y0 + ch - 0.2, pz + 0.075), Vector3(0.03, 0.12, 0.01), Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95))
	# the knife lever: two brass blades on a pivot, a black handle, thrown down
	var piv := Vector3(0.0, y0 + 0.28, pz + 0.04)
	k.box("c_gloss", piv + Vector3(0.0, 0.0, -0.01), Vector3(0.3, 0.1, 0.04), Color(0.1, 0.1, 0.1), Color(0.18, 0.18, 0.18))
	var tip := piv + Vector3(0.0, -0.06, 0.22)
	for xs: float in [-0.06, 0.06]:
		k.beam("brass", piv + Vector3(xs, 0.0, 0.0), tip + Vector3(xs, 0.0, 0.0), 0.02, 0.05, Color(0.75, 0.75, 0.75), Color(1, 1, 1), Vector2.ZERO, false)
	_rod(k, "c_gloss", tip + Vector3(-0.1, 0.0, 0.0), tip + Vector3(0.1, 0.0, 0.0), 0.028, Color(0.08, 0.08, 0.08), Color(0.2, 0.2, 0.2), 12)
	# cables down into the pedestal
	for x: float in [-0.2, 0.2]:
		k.tube("rubber", PackedVector3Array([Vector3(x, y0 + ch - 0.32, pz + 0.01), Vector3(x, y0 + 0.4, pz + 0.01), Vector3(x * 0.5, y0 + 0.06, pz + 0.01)]), 0.016, 6, Color(0.15, 0.15, 0.15))
	# the door, swung open to the viewer's right on its hinge
	var hinge := Vector3(cw * 0.5, y0, cd * 0.5)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-118.0)), hinge))
	k.box("paint", Vector3(-cw * 0.5, ch * 0.5, 0.018), Vector3(cw, ch, 0.036), glo, green)
	# a raised panel and the keyhole boss on the door's outside
	k.box("paint", Vector3(-cw * 0.5, ch * 0.5, 0.045), Vector3(cw - 0.14, ch - 0.16, 0.02), green, _mul(green, 1.15))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-cw + 0.07, ch * 0.5, 0.036)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.03, 0.02), Vector2(0.0, 0.025)]), 12, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 14.0, "yaw": 26.0, "margin": 0.05}

## The transporter bridge's gondola: a length of the high girder with the trolley running under it, the hanging
## cables fanning down to the deck, its railings and the little cabin the operator works it from.
func _gondola(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var iron := Color(0.36, 0.36, 0.37)
	var ilo := _mul(iron, 0.6)
	var length := 2.6
	var top := 2.5
	# the girder: two chords and a zig-zag of struts between them, on both faces
	for z: float in [-0.22, 0.22]:
		k.box("paint", Vector3(0.0, top + 0.32, z), Vector3(length, 0.07, 0.07), ilo, iron)
		k.box("paint", Vector3(0.0, top, z), Vector3(length, 0.08, 0.08), ilo, iron)
		var bays := 7
		for i: int in range(bays):
			var x0 := -length * 0.5 + length * float(i) / float(bays)
			var x1 := x0 + length / float(bays)
			var up := i % 2 == 0
			k.beam("paint", Vector3(x0, top + (0.0 if up else 0.32), z), Vector3(x1, top + (0.32 if up else 0.0), z), 0.035, 0.04, ilo, iron, Vector2.ZERO, false)
			k.beam("paint", Vector3(x0, top, z), Vector3(x0, top + 0.32, z), 0.03, 0.035, ilo, iron, Vector2.ZERO, false)
	for x: float in [-length * 0.5, length * 0.5]:
		k.box("paint", Vector3(x, top + 0.16, 0.0), Vector3(0.05, 0.38, 0.5), ilo, iron)
	# the trolley under the girder: a frame with its wheels on the bottom chords
	k.box("paint", Vector3(0.0, top - 0.12, 0.0), Vector3(1.3, 0.1, 0.56), ilo, iron)
	for x: float in [-0.5, -0.17, 0.17, 0.5]:
		for z: float in [-0.22, 0.22]:
			k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, top - 0.02, z - 0.05)))
			k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.08, 0.1), Vector2(0.0, 0.1)]), 14, Color(0.5, 0.5, 0.5), Color(0.75, 0.75, 0.75))
			k.pop()
	# the deck
	var deck_y := 0.45
	var dl := 2.2
	var dw := 1.0
	var wood := Color(0.66, 0.55, 0.42)
	k.box("planks", Vector3(0.0, deck_y, 0.0), Vector3(dl, 0.06, dw), _mul(wood, 0.8), wood, Vector2.ZERO, Kit.AUTO)
	k.box("paint", Vector3(0.0, deck_y - 0.09, 0.0), Vector3(dl + 0.04, 0.12, dw + 0.04), ilo, iron)
	# railings along both sides
	for zs: float in [-1.0, 1.0]:
		var z := zs * (dw * 0.5 - 0.02)
		var posts := 7
		for i: int in range(posts):
			var x := -dl * 0.5 + 0.05 + (dl - 0.1) * float(i) / float(posts - 1)
			k.box("paint", Vector3(x, deck_y + 0.22, z), Vector3(0.03, 0.4, 0.03), ilo, iron)
		_rod(k, "paint", Vector3(-dl * 0.5 + 0.04, deck_y + 0.42, z), Vector3(dl * 0.5 - 0.04, deck_y + 0.42, z), 0.022, ilo, iron, 8)
		_rod(k, "paint", Vector3(-dl * 0.5 + 0.04, deck_y + 0.22, z), Vector3(dl * 0.5 - 0.04, deck_y + 0.22, z), 0.014, ilo, iron, 8)
	# the operator's cabin on the near end: boarded, a window band, a little roof
	var cab := Vector3(dl * 0.5 - 0.3, deck_y + 0.03, 0.0)
	var cream := Color(0.86, 0.82, 0.7)
	k.box("siding", cab + Vector3(0.0, 0.32, 0.0), Vector3(0.44, 0.64, 0.6), _mul(cream, 0.7), cream)
	var glass_lo := Color(0.25, 0.3, 0.33)
	var glass_hi := Color(0.45, 0.5, 0.52)
	for zs: float in [-1.0, 1.0]:
		var x0 := -0.17 * zs
		k.quad4("b_glass", cab + Vector3(x0, 0.42, zs * 0.302), cab + Vector3(-x0, 0.42, zs * 0.302), cab + Vector3(-x0, 0.58, zs * 0.302), cab + Vector3(x0, 0.58, zs * 0.302),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, glass_lo, glass_lo, glass_hi, glass_hi)
	k.quad4("b_glass", cab + Vector3(0.222, 0.42, 0.2), cab + Vector3(0.222, 0.42, -0.2), cab + Vector3(0.222, 0.58, -0.2), cab + Vector3(0.222, 0.58, 0.2),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.25, 0.3, 0.33), Color(0.25, 0.3, 0.33), Color(0.45, 0.5, 0.52), Color(0.45, 0.5, 0.52))
	k.box("paint", cab + Vector3(0.0, 0.67, 0.0), Vector3(0.54, 0.05, 0.7), ilo, iron)
	# the cables: from the trolley frame fanning down to the deck's edges
	for zs: float in [-1.0, 1.0]:
		for i: int in range(4):
			var u := float(i) / 3.0
			var from := Vector3(lerpf(-0.55, 0.55, u), top - 0.17, zs * 0.24)
			var to := Vector3(lerpf(-dl * 0.5 + 0.08, dl * 0.5 - 0.08, u), deck_y + 0.05, zs * (dw * 0.5 - 0.02))
			k.tube("steel", PackedVector3Array([from, to]), 0.016, 6, Color(0.85, 0.85, 0.87))
	s._commit(k, parent)
	return {"pitch": 14.0, "yaw": -12.0, "margin": 0.05}

## A clinker rowing boat, a working skiff of the Riachuelo: painted planking, a white top strake, natural wood inside,
## two thwarts, the oars shipped along them. No name on her.
func _rowboat(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)), Vector3.ZERO))
	var length := 2.6
	var beam := 0.5
	var rows := 25
	var columns := 9
	var paint := Color(0.25, 0.42, 0.42)
	var wood := Color(0.78, 0.6, 0.4)
	# half-breadth along the hull (u: 0 stern, 1 bow), the transom a third of the beam wide
	var hb := func(u: float) -> float:
		return beam * (pow(maxf(0.0, 1.0 - pow((u - 0.42) / 0.58, 2.0)), 0.55) if u > 0.42 else lerpf(0.68, 1.0, sin(u / 0.42 * PI * 0.5)))
	var sheer := func(u: float) -> float:
		return 0.36 + 0.12 * pow(absf(u - 0.45) / 0.55, 2.2)
	var keel := func(u: float) -> float:
		return 0.03 + 0.05 * pow(absf(u - 0.5) * 2.0, 3.0)
	var outer: Array = []
	for side: float in [1.0, -1.0]:
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var ipts := PackedVector3Array()
		var icols := PackedColorArray()
		for i: int in range(rows):
			var u := float(i) / float(rows - 1)
			var x := (u - 0.5) * length
			var b: float = hb.call(u)
			var top: float = sheer.call(u)
			var bot: float = keel.call(u)
			for j: int in range(columns):
				var sv := float(j) / float(columns - 1)
				# clinker: each strake's lower edge stands proud of the one below
				var strake := sv * 4.0
				var lap := 0.012 * (1.0 - (strake - floorf(strake)))
				var ang := sv * PI * 0.5
				var p := Vector3(x, bot + (top - bot) * (1.0 - cos(ang)), side * (b * pow(sin(ang), 0.75) + lap * b / beam))
				pts.append(p)
				uvs.append(Vector2(x * Kit.UV_M, Kit.PLANK_ROW * (floorf(strake) + 0.1 + 0.8 * (strake - floorf(strake)))))
				var c := Color(0.92, 0.9, 0.84) if sv > 0.84 else paint * (0.7 + 0.3 * sv)
				cols.append(c)
				ipts.append(p - Vector3(0.0, 0.0, side * 0.025) + Vector3(0.0, 0.0 if j > 0 else 0.02, 0.0))
				icols.append(wood * (0.55 + 0.35 * sv))
		# (rows run along +X here, so the outside faces out with the patch flipped on the +Z side)
		k.patch("planks", rows, columns, pts, uvs, cols, false, side > 0.0)
		k.patch("planks", rows, columns, ipts, uvs, icols, false, side < 0.0)
		outer.append(pts)
	# the transom: a flat board closing the stern
	var sp: PackedVector3Array = outer[0]
	var spn: PackedVector3Array = outer[1]
	for j: int in range(columns - 1):
		var a := spn[j]
		var b2 := spn[j + 1]
		var c2 := sp[j + 1]
		var d2 := sp[j]
		k.quad4("planks", a, d2, c2, b2, Vector2(a.z, a.y) * Kit.UV_M, Vector2(d2.z, d2.y) * Kit.UV_M, Vector2(c2.z, c2.y) * Kit.UV_M, Vector2(b2.z, b2.y) * Kit.UV_M, paint * 0.75, paint * 0.75, paint * 0.9, paint * 0.9)
	# gunwales: a rubbing strake along each sheer
	for side: float in [1.0, -1.0]:
		var rail := PackedVector3Array()
		for i: int in range(rows):
			var u := float(i) / float(rows - 1)
			rail.append(Vector3((u - 0.5) * length, float(sheer.call(u)) + 0.01, side * (float(hb.call(u)) + 0.008)))
		k.tube("planks", rail, 0.028, 6, Color(0.62, 0.46, 0.3))
	# stem post at the bow
	var bow_top: float = sheer.call(1.0)
	k.beam("planks", Vector3(length * 0.5 - 0.02, 0.02, 0.0), Vector3(length * 0.5 + 0.03, bow_top + 0.05, 0.0), 0.05, 0.06, Color(0.55, 0.42, 0.3), Color(0.7, 0.55, 0.4))
	# floor boards and two thwarts
	k.box("planks", Vector3(0.0, 0.08, 0.0), Vector3(length * 0.62, 0.025, beam * 0.9), wood * 0.75, wood * 0.85, Vector2(0.2, 0.0), Kit.BEAM)
	for u: float in [0.32, 0.62]:
		var x := (u - 0.5) * length
		var b3: float = hb.call(u)
		k.box("planks", Vector3(x, float(sheer.call(u)) - 0.08, 0.0), Vector3(0.2, 0.035, b3 * 2.0 - 0.04), wood * 0.85, wood, Vector2(0.4 * u, 0.3), Kit.BEAM)
	# a stern seat
	k.box("planks", Vector3(-length * 0.5 + 0.22, float(sheer.call(0.08)) - 0.1, 0.0), Vector3(0.3, 0.035, float(hb.call(0.08)) * 2.0 - 0.06), wood * 0.85, wood, Vector2(0.7, 0.1), Kit.BEAM)
	# the oars, shipped: lying on the thwarts along the boat
	var oak := Color(0.9, 0.74, 0.52)
	for zs: float in [-1.0, 1.0]:
		var y := float(sheer.call(0.47)) - 0.04
		k.push(_b._b_along(Vector3(-length * 0.42, y, zs * 0.14), Vector3(length * 0.42, y + 0.03, zs * 0.2)))
		k.push(Transform3D(Basis.from_scale(Vector3(0.78, 0.8, 0.8)), Vector3.ZERO))
		_b._b_oar(k, oak)
		k.pop()
		k.pop()
	# brass rowlocks on the gunwales
	for zs: float in [-1.0, 1.0]:
		var u := 0.5
		var at := Vector3((u - 0.5) * length + 0.1, float(sheer.call(u)) + 0.04, zs * float(hb.call(u)))
		k.lathe("brass", at, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.05), Vector2(0.0, 0.05)]), 8, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 40.0, "yaw": 0.0, "margin": 0.04}

## A newsboy's flat cap: eight panels of brown tweed gathered to a button, swelling forward over a short peak.
func _flatcap(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var tweed := Color(0.54, 0.45, 0.34)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-62.0)), Vector3.ZERO))
	_cap_crown(k, tweed, 0.46, 0.34, true)
	_cap_peak(k, "c_wool", tweed * 0.8, 0.46, 0.3, 0.08)
	k.pop()
	s._commit(k, parent)
	return {"pitch": 28.0, "yaw": 0.0, "margin": 0.05}

## The crown of a soft cap: a band of radius r, a puffed top `h` high drawn forward over the peak, the panel seams
## and a button on top (panels: seams).
func _cap_crown(k: Kit, col: Color, r: float, h: float, panels: bool) -> void:
	var prof := PackedVector2Array([Vector2(r, 0.0), Vector2(r * 1.02, 0.06), Vector2(r * 1.1, 0.14), Vector2(r * 1.13, 0.2), Vector2(r * 1.1, 0.26), Vector2(r * 0.98, 0.31), Vector2(r * 0.74, h - 0.02), Vector2(r * 0.4, h + 0.005), Vector2(0.0, h + 0.01)])
	# the top pulled forward (toward +X) and down at the front
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-7.0)), Vector3(0.05, 0.0, 0.0)))
	k.lathe("c_wool", Vector3.ZERO, prof, 48, _mul(col, 0.55), col)
	if panels:
		for i: int in range(8):
			var a := TAU * (float(i) + 0.5) / 8.0
			var seam := PackedVector3Array()
			for p: Vector2 in prof:
				seam.append(Vector3(cos(a) * p.x * 1.004, p.y + 0.003, -sin(a) * p.x * 1.004))
			k.tube("c_wool", seam, 0.008, 4, _mul(col, 0.6))
		_b._b_ball(k, "c_wool", Vector3(0.0, h + 0.01, 0.0), 0.04, _mul(col, 0.8), col)
	k.pop()

## A cap's peak: a stiff half-oval brim on the front (+X) of a band of radius r.
func _cap_peak(k: Kit, key: String, col: Color, r: float, reach: float, droop: float) -> void:
	var rows := 2
	var cols := 21
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	for i: int in range(rows):
		for j: int in range(cols):
			var a := lerpf(-PI * 0.45, PI * 0.45, float(j) / float(cols - 1))
			var inner := Vector3(cos(a) * r * 1.02, 0.02, -sin(a) * r * 1.02)
			var ext := reach * cos(a * 1.05)
			var outer_p := inner + Vector3(cos(a), 0.0, -sin(a)) * ext + Vector3(0.0, -droop * (ext / reach), 0.0)
			var p := inner if i == 0 else outer_p
			pts.append(p)
			uvs.append(Vector2(p.x, p.z) * Kit.UV_M)
			colours.append(col)
	k.patch(key, rows, cols, pts, uvs, colours, false, false)
	k.patch(key, rows, cols, pts, uvs, colours, false, true)
	# the stiffened edge of the peak
	var edge := PackedVector3Array()
	for j: int in range(cols):
		edge.append(pts[cols + j])
	k.tube(key, edge, 0.014, 5, _mul(col, 0.8))

## The motorman's peaked cap: a dark blue crown on a black band, a glossy peak, the chin strap on two brass buttons
## and a plain brass badge (no insignia).
func _motorcap(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var blue := Color(0.3, 0.34, 0.46)
	var r := 0.42
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-58.0)), Vector3.ZERO))
	# the band
	k.lathe("c_wool", Vector3.ZERO, PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.16), Vector2(r * 1.01, 0.17)]), 48, Color(0.07, 0.07, 0.08), Color(0.13, 0.13, 0.14))
	# the crown: up from the band, flaring to a stiff flat top, a touch higher at the front
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-5.0)), Vector3(0.0, 0.16, 0.0)))
	k.lathe("c_wool", Vector3.ZERO, PackedVector2Array([Vector2(r * 1.01, 0.0), Vector2(r * 1.05, 0.06), Vector2(r * 1.17, 0.16), Vector2(r * 1.22, 0.2), Vector2(r * 1.2, 0.225), Vector2(r * 0.9, 0.235), Vector2(0.0, 0.24)]), 48, _mul(blue, 0.6), blue)
	# piping round the top edge
	var pipe := PackedVector3Array()
	for i: int in range(49):
		var a := TAU * float(i) / 48.0
		pipe.append(Vector3(cos(a) * r * 1.22, 0.2, -sin(a) * r * 1.22))
	k.tube("c_wool", pipe, 0.014, 5, _mul(blue, 1.2))
	k.pop()
	_cap_peak(k, "c_gloss", Color(0.05, 0.05, 0.06), r, 0.26, 0.09)
	# the chin strap across the front of the band and its buttons
	var strap := PackedVector3Array()
	for j: int in range(15):
		var a := lerpf(-PI * 0.42, PI * 0.42, float(j) / 14.0)
		strap.append(Vector3(cos(a) * (r + 0.012), 0.05, -sin(a) * (r + 0.012)))
	k.tube("c_gloss", strap, 0.018, 5, Color(0.06, 0.06, 0.06))
	for side: float in [-1.0, 1.0]:
		var a := side * PI * 0.42
		var at := Vector3(cos(a) * (r + 0.02), 0.05, -sin(a) * (r + 0.02))
		k.push(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, -PI * 0.5), at))
		k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.025, 0.015), Vector2(0.0, 0.02)]), 12, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
		k.pop()
	# the badge: a plain brass oval on the front of the crown
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-62.0)) * Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(r * 1.14, 0.27, 0.0)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.08, 0.012), Vector2(0.06, 0.025), Vector2(0.0, 0.03)]), 20, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 24.0, "yaw": 0.0, "margin": 0.05}

## A helping hand: a bare right hand held out open, palm up, fingers a little curled, from the cuff of a dark coat
## sleeve over a white shirt cuff.
func _hand(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var skin := Color(0.66, 0.42, 0.3)
	var slo := _mul(skin, 0.72)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(34.0)) * Basis(Vector3.BACK, deg_to_rad(8.0)), Vector3.ZERO))
	# the palm: a soft slab along +X from the wrist, wider at the knuckles
	var palm := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.12, 0.0, 0.0), Vector3(0.26, 0.005, 0.0), Vector3(0.38, 0.01, 0.0)])
	var sizes := [Vector2(0.15, 0.075), Vector2(0.18, 0.085), Vector2(0.2, 0.085), Vector2(0.21, 0.07)]
	_b._b_sweep(k, "c_skin", palm, _b._b_loop(28, 2.6), sizes, [Vector3.UP], [skin], true)
	# the fingers: index nearest the viewer (+Z), each three tapering joints curling up a little
	var fingers := [[0.15, 0.36, 0.034], [0.05, 0.4, 0.036], [-0.05, 0.37, 0.034], [-0.14, 0.29, 0.03]]
	for f: Array in fingers:
		var z: float = f[0]
		var length: float = f[1]
		var rad: float = f[2]
		var path := PackedVector3Array()
		var fs := []
		var fc := []
		var base := Vector3(0.37, 0.02, z)
		for i: int in range(9):
			var t := float(i) / 8.0
			var curl := 0.55 * t * t
			path.append(base + Vector3(length * t * cos(curl) * 0.95, length * sin(curl) * 0.45 * t, z * 0.12 * t))
			var tip := 1.0 - 0.55 * pow(t, 6.0)
			fs.append(Vector2(rad * tip, rad * 0.9 * tip))
			fc.append(skin.lerp(Color(0.74, 0.46, 0.36), t * 0.5))
		_b._b_sweep(k, "c_skin", path, _b._b_loop(12, 2.0), fs, [Vector3.UP], fc, true)
		# the nail, under the tip (the palm is up)
		var nail := path[7] + Vector3(0.0, -rad * 0.75, 0.0)
		_b._b_ball(k, "c_gloss", nail, rad * 0.55, Color(0.76, 0.56, 0.48), Color(0.86, 0.66, 0.58), 10)
	# the thumb: out from the heel of the palm toward the viewer and forward
	var thumb := PackedVector3Array()
	var ts := []
	for i: int in range(9):
		var t := float(i) / 8.0
		thumb.append(Vector3(0.06 + 0.26 * t, 0.03 + 0.06 * t * t, 0.09 + 0.16 * t - 0.06 * t * t))
		ts.append(Vector2(0.045 * (1.0 - 0.45 * pow(t, 5.0)), 0.04 * (1.0 - 0.45 * pow(t, 5.0))))
	_b._b_sweep(k, "c_skin", thumb, _b._b_loop(12, 2.0), ts, [Vector3.UP], [skin], true)
	# the wrist into a white shirt cuff and the coat sleeve
	k.push(Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.02, 0.0, 0.0)))
	k.lathe("c_skin", Vector3.ZERO, PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.08, 0.12), Vector2(0.0, 0.13)]), 18, slo, skin)
	k.lathe("b_white", Vector3(0.0, 0.1, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.105, 0.02), Vector2(0.105, 0.12), Vector2(0.0, 0.12)]), 20, Color(0.8, 0.8, 0.78), Color(0.97, 0.96, 0.94))
	k.lathe("c_wool", Vector3(0.0, 0.18, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.135, 0.0), Vector2(0.145, 0.02), Vector2(0.15, 0.08), Vector2(0.16, 0.26), Vector2(0.0, 0.26)]), 24, Color(0.2, 0.2, 0.23), Color(0.34, 0.34, 0.38))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 40.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# The Plaza de Mayo
# ---------------------------------------------------------------------------------------------------------------
## A city tram of the fifties on a stretch of track: a two-axle car, the lower panels dark green and the window band
## cream, the trolley pole up to its wire. No company, no route number.
func _tram(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var green := Color(0.2, 0.36, 0.28)
	var cream := Color(0.9, 0.86, 0.72)
	var length := 2.4
	var width := 0.82
	var floor_y := 0.34
	var waist := 0.78
	var eave := 1.28
	# rails and sleepers
	for z: float in [-0.3, 0.3]:
		k.box("blued", Vector3(0.0, 0.03, z), Vector3(length + 0.8, 0.05, 0.05), Color(0.5, 0.5, 0.52), Color(0.85, 0.85, 0.88))
	for i: int in range(9):
		k.box("planks", Vector3(-length * 0.5 - 0.3 + (length + 0.6) * float(i) / 8.0, 0.0, 0.0), Vector3(0.12, 0.04, 0.9), Color(0.3, 0.25, 0.2), Color(0.42, 0.34, 0.26), Vector2(0.1 * float(i), 0.0), Kit.BEAM)
	# the truck: frame and four wheels
	k.box("paint", Vector3(0.0, 0.2, 0.0), Vector3(1.2, 0.14, 0.7), Color(0.08, 0.08, 0.08), Color(0.16, 0.16, 0.16))
	for x: float in [-0.42, 0.42]:
		for z: float in [-0.3, 0.3]:
			k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.15, z + 0.04)))
			k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.13, 0.05), Vector2(0.0, 0.05)]), 18, Color(0.35, 0.35, 0.36), Color(0.55, 0.55, 0.57))
			k.pop()
	# the body: dark green below the waist, cream window band, a darker roof, ends rounded in plan
	var plan := PackedVector2Array()
	var end_r := width * 0.5
	var straight := length * 0.5 - end_r * 0.7
	for i: int in range(9):
		var a := -PI * 0.5 + PI * float(i) / 8.0
		plan.append(Vector2(straight + cos(a) * end_r * 0.7, sin(a) * end_r))
	for i: int in range(9):
		var a := PI * 0.5 + PI * float(i) / 8.0
		plan.append(Vector2(-straight + cos(a) * end_r * 0.7, sin(a) * end_r))
	var bands := [[floor_y, waist, green, "paint"], [waist, eave, cream, "paint"]]
	for band: Array in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		var col: Color = band[2]
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for r: int in range(2):
			var y := y0 if r == 0 else y1
			var run := 0.0
			for j: int in range(plan.size() + 1):
				var p := plan[j % plan.size()]
				if j > 0: run += p.distance_to(plan[(j - 1) % plan.size()])
				pts.append(Vector3(p.x, y, -p.y))
				uvs.append(Vector2(run, y) * Kit.UV_M)
				cols.append(_mul(col, 0.75 if r == 0 else 1.0))
		k.patch(str(band[3]), 2, plan.size() + 1, pts, uvs, cols, true, false)
	# the windows: dark glass panes along each side
	for side: float in [1.0, -1.0]:
		var bays := 5
		for i: int in range(bays):
			var x0 := -straight + 2.0 * straight * (float(i) + 0.1) / float(bays)
			var x1 := -straight + 2.0 * straight * (float(i) + 0.9) / float(bays)
			var z := side * (end_r + 0.004)
			var xa := x0 if side > 0.0 else x1
			var xb := x1 if side > 0.0 else x0
			k.quad4("b_glass", Vector3(xa, waist + 0.08, z), Vector3(xb, waist + 0.08, z), Vector3(xb, eave - 0.1, z), Vector3(xa, eave - 0.1, z),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.18, 0.22, 0.25), Color(0.18, 0.22, 0.25), Color(0.4, 0.45, 0.48), Color(0.4, 0.45, 0.48))
	# the front windscreen (the +X end): three panes round the rounded end
	for i: int in range(3):
		var a0 := -PI * 0.38 + PI * 0.76 * float(i) / 3.0 + 0.03
		var a1 := -PI * 0.38 + PI * 0.76 * float(i + 1) / 3.0 - 0.03
		var p0 := Vector2(straight + cos(a0) * end_r * 0.7 + 0.004, sin(a0) * (end_r + 0.004))
		var p1 := Vector2(straight + cos(a1) * end_r * 0.7 + 0.004, sin(a1) * (end_r + 0.004))
		k.quad4("b_glass", Vector3(p0.x, waist + 0.08, -p0.y), Vector3(p1.x, waist + 0.08, -p1.y), Vector3(p1.x, eave - 0.1, -p1.y), Vector3(p0.x, eave - 0.1, -p0.y),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.18, 0.22, 0.25), Color(0.18, 0.22, 0.25), Color(0.4, 0.45, 0.48), Color(0.4, 0.45, 0.48))
	# the roof: a low dome over the plan, grey
	var roof := PackedVector3Array()
	var ruv := PackedVector2Array()
	var rcol := PackedColorArray()
	var rings := 5
	for r: int in range(rings):
		var f := 1.0 - float(r) / float(rings - 1) * 0.92
		var y := eave + 0.14 * sin(float(r) / float(rings - 1) * PI * 0.5)
		for j: int in range(plan.size() + 1):
			var p := plan[j % plan.size()]
			var q := Vector2(p.x * (0.92 + 0.08 * f), p.y * f)
			roof.append(Vector3(q.x, y, -q.y))
			ruv.append(Vector2(q.x, q.y) * Kit.UV_M)
			rcol.append(Color(0.42, 0.42, 0.4) * (0.85 + 0.15 * float(r) / float(rings - 1)))
	k.patch("paint", rings, plan.size() + 1, roof, ruv, rcol, true, false)
	# the headlamp and the dash
	k.push(Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(straight + end_r * 0.7, 0.55, 0.0)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.1, 0.04), Vector2(0.0, 0.05)]), 18, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.disc("glow", Vector3(0.0, 0.051, 0.0), 0.075, 18, Rect2(0, 0, 1, 1), Color(1.0, 0.95, 0.8))
	k.pop()
	# the trolley pole: from a base on the roof back and up, its wheel at the top
	var pole0 := Vector3(-0.2, eave + 0.16, 0.0)
	var pole1 := Vector3(-1.25, eave + 0.95, 0.0)
	k.box("paint", pole0 + Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.06, 0.2), Color(0.1, 0.1, 0.1), Color(0.2, 0.2, 0.2))
	_rod(k, "paint", pole0 + Vector3(0.0, 0.05, 0.0), pole1, 0.022, Color(0.12, 0.12, 0.12), Color(0.22, 0.22, 0.22), 8)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), pole1 + Vector3(0.0, 0.02, -0.02)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.04), Vector2(0.0, 0.04)]), 14, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.pop()
	# a short stretch of the overhead wire it runs on
	k.tube("blade", PackedVector3Array([Vector3(-length * 0.5 - 0.4, pole1.y + 0.05, 0.0), Vector3(length * 0.5 + 0.2, pole1.y + 0.05, 0.0)]), 0.008, 5, Color(0.6, 0.6, 0.62))
	s._commit(k, parent)
	return {"pitch": 18.0, "yaw": -34.0, "margin": 0.04}

## A subte entrance: the stair going down through the pavement between iron balustrades, and a blue enamel sign on
## two posts with a white arrow pointing down. No lettering, no line or company mark.
func _subte(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var w := 0.7
	var run := 1.0
	var pave := Color(0.66, 0.64, 0.6)
	var plo := _mul(pave, 0.75)
	var t := 0.24
	var pw := 1.7
	var pd := 1.7
	var z0 := -run * 0.5
	var z1 := run * 0.5
	# the pavement round the opening
	k.box("concrete", Vector3(0.0, -t * 0.5, z0 - (pd * 0.5 + z0) * 0.5), Vector3(pw, t, pd * 0.5 + z0), plo, pave)
	k.box("concrete", Vector3(0.0, -t * 0.5, z1 + (pd * 0.5 - z1) * 0.5), Vector3(pw, t, pd * 0.5 - z1), plo, pave)
	for xs: float in [-1.0, 1.0]:
		k.box("concrete", Vector3(xs * (w * 0.5 + (pw * 0.5 - w * 0.5) * 0.5), -t * 0.5, 0.0), Vector3(pw * 0.5 - w * 0.5, t, run), plo, pave)
	# the stairwell: dark sides and steps going down toward the back
	var top := Color(0.2, 0.19, 0.18)
	var bot := Color(0.02, 0.02, 0.02)
	var deep := t - 0.01
	k.quad4("c_dark", Vector3(-w * 0.5, -deep, z1), Vector3(-w * 0.5, -deep, z0), Vector3(-w * 0.5, -0.01, z0), Vector3(-w * 0.5, -0.01, z1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, top, top)
	k.quad4("c_dark", Vector3(w * 0.5, -deep, z0), Vector3(w * 0.5, -deep, z1), Vector3(w * 0.5, -0.01, z1), Vector3(w * 0.5, -0.01, z0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, top, top)
	k.quad4("c_dark", Vector3(-w * 0.5, -deep, z0), Vector3(w * 0.5, -deep, z0), Vector3(w * 0.5, -0.01, z0), Vector3(-w * 0.5, -0.01, z0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, bot, bot)
	k.quad4("c_dark", Vector3(-w * 0.5, -deep, z1), Vector3(w * 0.5, -deep, z1), Vector3(w * 0.5, -deep, z0), Vector3(-w * 0.5, -deep, z0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, bot, bot, bot, bot)
	var stone := Color(0.7, 0.68, 0.64)
	for i: int in range(4):
		var y := -0.04 - 0.05 * float(i)
		var z := z1 - 0.09 - 0.17 * float(i)
		var shade := 1.0 - 0.22 * float(i)
		k.box("stone", Vector3(0.0, y - 0.025, z), Vector3(w - 0.01, 0.05, 0.18), _mul(stone, 0.45 * shade), _mul(stone, 0.95 * shade))
	# balustrades along the two sides and across the back, dark green iron
	var iron := Color(0.16, 0.26, 0.2)
	var ilo := _mul(iron, 0.6)
	var rail_h := 0.48
	var sides := [[Vector3(-w * 0.5 - 0.04, 0.0, z1), Vector3(-w * 0.5 - 0.04, 0.0, z0 - 0.04)], [Vector3(w * 0.5 + 0.04, 0.0, z1), Vector3(w * 0.5 + 0.04, 0.0, z0 - 0.04)], [Vector3(-w * 0.5 - 0.04, 0.0, z0 - 0.04), Vector3(w * 0.5 + 0.04, 0.0, z0 - 0.04)]]
	for seg: Array in sides:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		_rod(k, "paint", a + Vector3(0.0, rail_h, 0.0), b + Vector3(0.0, rail_h, 0.0), 0.022, ilo, iron, 8)
		_rod(k, "paint", a + Vector3(0.0, 0.08, 0.0), b + Vector3(0.0, 0.08, 0.0), 0.014, ilo, iron, 8)
		var count := int(a.distance_to(b) / 0.09)
		for i: int in range(count + 1):
			var p := a.lerp(b, float(i) / float(count))
			_rod(k, "paint", p, p + Vector3(0.0, rail_h, 0.0), 0.009 if i % 4 != 0 else 0.022, ilo, iron, 6)
			if i % 4 == 0: _b._b_ball(k, "paint", p + Vector3(0.0, rail_h + 0.03, 0.0), 0.032, iron, _mul(iron, 1.4), 10)
	# the sign: an enamel plate on two posts behind the stair, facing the street (+Z)
	var sy := 0.95
	var sw := 0.86
	var sh := 0.36
	var sz := z0 - 0.12
	for xs: float in [-1.0, 1.0]:
		_rod(k, "paint", Vector3(xs * (sw * 0.5 - 0.05), 0.0, sz), Vector3(xs * (sw * 0.5 - 0.05), sy + sh * 0.5 + 0.02, sz), 0.026, ilo, iron, 8)
	k.box("paint", Vector3(0.0, sy, sz + 0.01), Vector3(sw, sh, 0.035), ilo, iron)
	var blue := Color(0.12, 0.22, 0.5)
	var white := Color(0.95, 0.95, 0.92)
	var fz := sz + 0.03
	k.quad4("c_gloss", Vector3(-sw * 0.5 + 0.02, sy - sh * 0.5 + 0.02, fz), Vector3(sw * 0.5 - 0.02, sy - sh * 0.5 + 0.02, fz), Vector3(sw * 0.5 - 0.02, sy + sh * 0.5 - 0.02, fz), Vector3(-sw * 0.5 + 0.02, sy + sh * 0.5 - 0.02, fz),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, white, white, white, white)
	k.quad4("c_gloss", Vector3(-sw * 0.5 + 0.045, sy - sh * 0.5 + 0.045, fz + 0.002), Vector3(sw * 0.5 - 0.045, sy - sh * 0.5 + 0.045, fz + 0.002), Vector3(sw * 0.5 - 0.045, sy + sh * 0.5 - 0.045, fz + 0.002), Vector3(-sw * 0.5 + 0.045, sy + sh * 0.5 - 0.045, fz + 0.002),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, blue, blue, blue, blue)
	# the arrow: a white shaft and head pointing down, and three steps beside it
	var az := fz + 0.004
	var ax := -0.2
	k.quad4("c_gloss", Vector3(ax - 0.03, sy - 0.02, az), Vector3(ax + 0.03, sy - 0.02, az), Vector3(ax + 0.03, sy + 0.12, az), Vector3(ax - 0.03, sy + 0.12, az), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, white, white, white, white)
	k.tri("c_gloss", Vector3(ax + 0.085, sy - 0.02, az), Vector3(ax - 0.085, sy - 0.02, az), Vector3(ax, sy - 0.12, az), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, white, white, white)
	for i: int in range(3):
		var x0 := 0.0 + 0.09 * float(i)
		var y0 := sy + 0.08 - 0.07 * float(i)
		k.quad4("c_gloss", Vector3(x0, y0 - 0.025, az), Vector3(x0 + 0.12, y0 - 0.025, az), Vector3(x0 + 0.12, y0, az), Vector3(x0, y0, az), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, white, white, white, white)
		k.quad4("c_gloss", Vector3(x0 + 0.095, y0 - 0.07, az), Vector3(x0 + 0.12, y0 - 0.07, az), Vector3(x0 + 0.12, y0, az), Vector3(x0 + 0.095, y0, az), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, white, white, white, white)
	s._commit(k, parent)
	return {"pitch": 30.0, "yaw": -26.0, "margin": 0.05}

## A tarpaulin: heavy olive canvas thrown over a load and roped down, its hem lying on the ground with brass eyelets.
func _tarp(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	var olive := Color(0.5, 0.5, 0.36)
	var n := 33
	var hx := 0.95
	var hz := 0.7
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var height := func(x: float, z: float) -> float:
		# the load: a rounded block, the canvas sagging between its corners, folds running down to the hem
		var ux := absf(x) / 0.62
		var uz := absf(z) / 0.42
		var inside := pow(pow(ux, 6.0) + pow(uz, 6.0), 1.0 / 6.0)
		var h := 0.52 * clampf(1.0 - smoothstep(0.85, 1.55, inside), 0.0, 1.0)
		h -= 0.035 * smoothstep(0.2, 0.0, absf(ux - uz) * 0.5) * float(inside < 0.95)
		var fold := 0.03 * sin(atan2(z, x) * 9.0) * smoothstep(0.9, 1.4, inside)
		return maxf(0.012, h + fold)
	for i: int in range(n):
		for j: int in range(n):
			var u := float(j) / float(n - 1) * 2.0 - 1.0
			var v := float(i) / float(n - 1) * 2.0 - 1.0
			# the hem wanders a little
			var x := u * hx * (1.0 + 0.05 * sin(v * 5.0 + 1.0))
			var z := v * hz * (1.0 + 0.06 * sin(u * 4.0))
			var y: float = height.call(x, z)
			pts.append(Vector3(x, y, z))
			uvs.append(Vector2(x, z) * Kit.UV_M * 1.5)
			cols.append(olive * (0.62 + 0.45 * clampf(y / 0.52, 0.0, 1.0)))
	k.patch("c_wool", n, n, pts, uvs, cols, false, true)
	# brass eyelets along the hem
	for e: int in range(4):
		for i: int in range(1, 6):
			var idx := 0
			var t := float(i) / 6.0
			var jj := int(t * float(n - 1))
			match e:
				0: idx = jj
				1: idx = (n - 1) * n + jj
				2: idx = jj * n
				3: idx = jj * n + n - 1
			var p := pts[idx]
			_a._torus(k, "brass", p + Vector3(0.0, 0.01, 0.0), Basis.IDENTITY, 0.022, 0.008, 12, 6, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	# the rope over the top, both ways
	var hemp := Color(0.9, 0.78, 0.58)
	for across: bool in [true, false]:
		var rope := PackedVector3Array()
		for i: int in range(41):
			var t := float(i) / 40.0 * 2.0 - 1.0
			var x := t * hx * 0.98 if across else 0.08
			var z := -0.05 if across else t * hz * 0.98
			rope.append(Vector3(x, float(height.call(x, z)) + 0.02, z))
		k.tube("burlap", rope, 0.02, 6, hemp, Vector2.ZERO, 0.25, 2.0)
	s._commit(k, parent)
	return {"pitch": 36.0, "yaw": -18.0, "margin": 0.05}

## Carrying someone: a canvas stretcher on two wooden poles with iron stirrup feet, a grey blanket folded on it.
func _stretcher(s, parent: Node3D) -> Dictionary:
	_c_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)), Vector3.ZERO))
	var length := 2.3
	var bed := 1.55
	var w := 0.56
	var y := 0.2
	var wood := Color(0.76, 0.58, 0.38)
	for zs: float in [-1.0, 1.0]:
		var z := zs * w * 0.5
		k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-length * 0.5, y, z)))
		k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.034, 0.03), Vector2(0.034, length - 0.03), Vector2(0.03, length), Vector2(0.0, length)]), 12, _mul(wood, 0.8), wood, Vector2.ZERO, PackedFloat32Array(), -1.0, true)
		k.pop()
		# worn handle grips
		for xs: float in [-1.0, 1.0]:
			k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(xs * length * 0.5 - (0.32 if xs > 0.0 else 0.0), y, z)))
			k.lathe("b_leather", Vector3.ZERO, PackedVector2Array([Vector2(0.038, 0.0), Vector2(0.04, 0.02), Vector2(0.04, 0.3), Vector2(0.038, 0.32)]), 12, Color(0.3, 0.2, 0.13), Color(0.42, 0.3, 0.2))
			k.pop()
	# the stirrups: iron hoops under each end of the bed, and the spreader bars across
	var iron := Color(0.3, 0.3, 0.31)
	for xs: float in [-1.0, 1.0]:
		var x := xs * bed * 0.5
		for zs: float in [-1.0, 1.0]:
			var z := zs * w * 0.5
			k.tube("blued", PackedVector3Array([Vector3(x - 0.08, y, z), Vector3(x - 0.06, y - 0.14, z), Vector3(x, y - 0.18, z), Vector3(x + 0.06, y - 0.14, z), Vector3(x + 0.08, y, z)]), 0.015, 6, _mul(iron, 2.0))
		_rod(k, "blued", Vector3(x, y + 0.01, -w * 0.5), Vector3(x, y + 0.01, w * 0.5), 0.014, _mul(iron, 1.4), _mul(iron, 2.0), 8)
	# the canvas bed, sagging a little between the poles
	var rows := 13
	var cols := 7
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var canvas := Color(0.62, 0.6, 0.46)
	for i: int in range(rows):
		var x := (float(i) / float(rows - 1) - 0.5) * bed
		for j: int in range(cols):
			var v := float(j) / float(cols - 1) * 2.0 - 1.0
			var sag := 0.05 * (1.0 - v * v)
			pts.append(Vector3(x, y + 0.025 - sag, v * (w * 0.5 + 0.01)))
			uvs.append(Vector2(x, v * w * 0.5) * Kit.UV_M * 2.0)
			colours.append(canvas * (0.8 + 0.2 * (1.0 - v * v)))
	k.patch("c_wool", rows, cols, pts, uvs, colours, false, false)
	k.patch("c_wool", rows, cols, pts, uvs, colours, false, true)
	# the folded blanket at the head end, a pillow roll
	_a._softbox(k, "c_wool", Vector3(-0.32, y - 0.02, 0.0), Vector3(0.62, 0.11, w * 0.82), 0.04, Color(0.32, 0.33, 0.34), Color(0.52, 0.53, 0.54), 32)
	for i: int in range(2):
		k.box("c_wool", Vector3(-0.32, y + 0.085, -0.12 + 0.24 * float(i)), Vector3(0.6, 0.012, 0.035), Color(0.62, 0.22, 0.16), Color(0.7, 0.26, 0.18))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-bed * 0.5 + 0.12, y + 0.06, -w * 0.4)))
	k.lathe("b_white", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.075, 0.03), Vector2(0.075, w * 0.8 - 0.03), Vector2(0.06, w * 0.8), Vector2(0.0, w * 0.8)]), 14, Color(0.78, 0.78, 0.75), Color(0.95, 0.95, 0.92))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 44.0, "yaw": 0.0, "margin": 0.04}
