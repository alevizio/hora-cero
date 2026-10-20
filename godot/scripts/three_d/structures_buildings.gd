extends RefCounted
## The three outpost buildings. Each is built around its own centre (ground at y = 0, ridge along X) into two kits:
## `body` (walls, joinery, dressing that hugs the walls) and `roof` (everything above the wall plate).
const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Props = preload("res://scripts/three_d/structures_props.gd")

var props: Props
var rng := RandomNumberGenerator.new()
## label text -> trim cell holding its painted sign (baked by tools/gen_structures_textures.py).
var sign_cells: Dictionary = {}
## Signs whose text is not baked: [{"at": Vector3, "basis": Basis, "text": String, "width": float}] in building space.
var loose_signs: Array[Dictionary] = []
## Trampled ground in front of doors: Vector3(x, z, size) in building space; the caller lays the decals.
var wear: Array[Vector3] = []
## Doors that swing (their leaf is a node of its own, see structures.gd), in building space:
## [{"hinge": Vector3, "along": Vector3 (the closed leaf runs this way), "out": Vector3, "w", "h", "cell"}]
var hinged: Array[Dictionary] = []
## Where the generator set stands on the radio post's north wall (face-local X of its middle).
const GENERATOR_X := 2.75

const CASING := Color(0.98, 0.96, 0.86)
const PLINTH_AO := Color(0.5, 0.48, 0.44)

func _init(p: Props, seed_value: int) -> void:
	props = p
	rng.seed = seed_value

# ---------------------------------------------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------------------------------------------
## Transform of a wall face: local X runs to the viewer's right, Y up, Z out of the wall; origin = bottom-left.
static func face(which: String, sx: float, sz: float, cx: float = 0.0) -> Transform3D:
	match which:
		"S": return Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), Vector3(cx - sx * 0.5, 0, sz * 0.5))
		"N": return Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(cx + sx * 0.5, 0, -sz * 0.5))
		"E": return Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), Vector3(cx + sx * 0.5, 0, sz * 0.5))
	return Transform3D(Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT), Vector3(cx - sx * 0.5, 0, -sz * 0.5))

static func win(x: float, y: float, w: float, h: float, cell: String = "window_a", shutters: int = 0) -> Dictionary:
	return {"t": "win", "x": x, "y": y, "w": w, "h": h, "cell": cell, "sh": shutters}

static func door(x: float, w: float = 0.9, h: float = 2.0, cell: String = "door_plank", y: float = 0.16) -> Dictionary:
	return {"t": "door", "x": x, "y": y, "w": w, "h": h, "cell": cell, "sh": 0}

## One wall face with its openings cut and dressed. opt: u0, v_base, plinth (height), plinth_key, plinth_tint,
## foot (AO height), ao_lo.
func side(k: Kit, xf: Transform3D, width: float, height: float, wall_key: String, specs: Array, opt: Dictionary = {}) -> void:
	k.push(xf)
	var rects: Array = []
	for s: Dictionary in specs:
		rects.append(Rect2(s.x, s.y, s.w, s.h))
	k.wall(wall_key, Vector3.ZERO, Vector3.RIGHT, width, height, rects, opt.get("u0", 0.0), opt.get("v_base", 0.0), 0.1, opt.get("ao_lo", Color(0.8, 0.77, 0.72)), Color(0.74, 0.74, 0.76), 0.4)
	var ph: float = opt.get("plinth", 0.0)
	if ph > 0.0:
		var cuts: Array[Vector2] = []
		for s: Dictionary in specs:
			if s.y < ph:
				cuts.append(Vector2(s.x - 0.05, s.x + s.w + 0.05))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		cuts.append(Vector2(width + 0.04, width + 0.04))
		var x := -0.04
		k.push_tint(opt.get("plinth_tint", Color.WHITE))
		for cut: Vector2 in cuts:
			if cut.x - x > 0.02:
				k.box(opt.get("plinth_key", "concrete"), Vector3((x + cut.x) * 0.5, ph * 0.5, 0.0), Vector3(cut.x - x, ph, 0.08), PLINTH_AO, Kit.grey(0.95), Vector2(x * Kit.UV_M, 1.0), Kit.UPRIGHT, 0b110111)
			x = cut.y
		k.pop_tint()
	for s: Dictionary in specs:
		match str(s.t):
			"win": _window(k, s)
			"door": _door(k, s)
	k.pop()

func _casing(k: Kit, x: float, y: float, w: float, h: float, sill: bool) -> void:
	k.push_tint(CASING)
	var uv := Vector2(rng.randf(), rng.randf())
	k.box("planks", Vector3(x - 0.035, y + h * 0.5, 0.012), Vector3(0.07, h + 0.14, 0.03), Kit.grey(0.8), Kit.grey(0.95), uv, Kit.BEAM, 0b110111)
	k.box("planks", Vector3(x + w + 0.035, y + h * 0.5, 0.012), Vector3(0.07, h + 0.14, 0.03), Kit.grey(0.8), Kit.grey(0.95), uv, Kit.BEAM, 0b110111)
	k.box("planks", Vector3(x + w * 0.5, y + h + 0.035, 0.014), Vector3(w + 0.18, 0.07, 0.034), Kit.grey(0.85), Kit.grey(0.9), uv, Kit.BEAM)
	if sill:
		k.box("planks", Vector3(x + w * 0.5, y - 0.03, 0.045), Vector3(w + 0.22, 0.05, 0.1), Kit.grey(0.7), Color.WHITE, uv, Kit.BEAM)
	k.pop_tint()

func _window(k: Kit, s: Dictionary) -> void:
	var x: float = s.x
	var y: float = s.y
	var w: float = s.w
	var h: float = s.h
	k.quad_rect("trim", Vector3(x, y, -0.07), Vector3(x + w, y, -0.07), Vector3(x + w, y + h, -0.07), Vector3(x, y + h, -0.07), Kit.trim_uv(str(s.cell)), Kit.grey(0.9), Kit.grey(0.72))
	_casing(k, x, y, w, h, true)
	var mode: int = s.sh
	if mode == 0:
		return
	var sr := Kit.trim_uv("shutter")
	var edge := Rect2(sr.position, Vector2(sr.size.x * 0.08, sr.size.y))
	var sw := w * 0.5
	# 1: both folded back, 2: left only, 3: both closed, 4: left closed + right folded back, 5: right only
	var slots: Array = []
	match mode:
		1: slots = [x - 0.08 - sw * 0.5, x + w + 0.08 + sw * 0.5]
		2: slots = [x - 0.08 - sw * 0.5]
		3: slots = [x + sw * 0.5, x + w - sw * 0.5]
		4: slots = [x + sw * 0.5, x + w + 0.08 + sw * 0.5]
		5: slots = [x + w + 0.08 + sw * 0.5]
	for cx: float in slots:
		var g := rng.randf_range(0.85, 1.0)
		k.box_rects("trim", Vector3(cx, y + h * 0.5 - rng.randf() * 0.012, 0.045), Vector3(sw - 0.01, h, 0.035), [edge, edge, edge, null, sr, null], Kit.grey(0.8 * g), Kit.grey(g))

func _door(k: Kit, s: Dictionary) -> void:
	var x: float = s.x
	var y: float = s.y
	var w: float = s.w
	var h: float = s.h
	if s.get("hinged", false):
		# an open doorway: lamplit boards inside, darker up under the lintel; the leaf hangs on the far jamb
		k.quad_m("glow", Vector3(x, y, -0.1), Vector3(x + w, y, -0.1), Vector3(x + w, y + h, -0.1), Vector3(x, y + h, -0.1), Vector2.ZERO, Color(0.36, 0.29, 0.19), Color(0.07, 0.065, 0.06))
		hinged.append({"hinge": k.xf * Vector3(x + w, y, 0.0), "along": k.xf.basis * Vector3.LEFT, "out": k.xf.basis * Vector3.BACK, "w": w, "h": h, "cell": str(s.cell)})
	else:
		k.quad_rect("trim", Vector3(x, y, -0.06), Vector3(x + w, y, -0.06), Vector3(x + w, y + h, -0.06), Vector3(x, y + h, -0.06), Kit.trim_uv(str(s.cell)), Kit.grey(0.78), Kit.grey(0.9))
	_casing(k, x, y, w, h, false)
	if y > 0.02:
		k.box("concrete", Vector3(x + w * 0.5, y * 0.5, 0.2), Vector3(w + 0.5, y, 0.46), PLINTH_AO, Color.WHITE, Vector2(rng.randf(), rng.randf()))
	var foot := k.xf * Vector3(x + w * 0.5, 0, 1.2)
	wear.append(Vector3(foot.x, foot.z, 2.6))

## Painted name board, centred at (cx, cy) on the current face. Uses the baked sign when the label has one.
func sign_board(k: Kit, cx: float, cy: float, width: float, label: String, z: float = 0.02) -> void:
	var cell: String = sign_cells.get(label, "board_blank")
	var r := Kit.trim_uv(cell)
	var h := width * r.size.y / r.size.x
	var edge := Rect2(r.position + Vector2(0.004, 0.004), Vector2(0.01, 0.01))
	k.box_rects("trim", Vector3(cx, cy, z + 0.02), Vector3(width, h, 0.04), [edge, edge, edge, edge, r, null], Kit.grey(0.9), Color.WHITE)
	for dx: float in [-width * 0.36, width * 0.36]:
		k.box("steel", Vector3(cx + dx, cy, z + 0.005), Vector3(0.05, h + 0.1, 0.012), Props.IRON, Props.IRON)
	if cell == "board_blank" and label != "":
		loose_signs.append({"at": k.xf * Vector3(cx, cy, z + 0.045), "basis": k.xf.basis, "text": label, "width": width})

## Louvred vent in a gable peak (face-local).
func gable_vent(k: Kit, cx: float, cy: float, size: float = 0.28) -> void:
	var r := Kit.trim_uv("vent")
	var edge := Rect2(r.position + Vector2(0.002, 0.002), Vector2(0.006, 0.006))
	k.box_rects("trim", Vector3(cx, cy, 0.02), Vector3(size, size, 0.04), [edge, edge, edge, edge, r, null], Kit.grey(0.8), Kit.grey(0.9))

## Gable triangle above a wall face (same face-local frame as side()). boards = vertical planks instead of the wall texture.
func gable(k: Kit, xf: Transform3D, width: float, he: float, hr: float, key: String, u0: float = 0.0, tint: Color = Color.WHITE, boards: bool = false) -> void:
	k.push(xf)
	k.push_tint(tint)
	var a := Vector3(0, he, 0)
	var b := Vector3(width, he, 0)
	var c := Vector3(width * 0.5, hr, 0)
	if boards:
		k.tri(key, a, b, c, Vector2(he * Kit.UV_M, u0 * Kit.UV_M), Vector2(he * Kit.UV_M, (u0 + width) * Kit.UV_M), Vector2(hr * Kit.UV_M, (u0 + width * 0.5) * Kit.UV_M), Color.WHITE, Color.WHITE, Kit.grey(0.78))
	else:
		# continue the courses but sample the clean middle of the anchored wall texture
		var vb := -1.28
		k.tri(key, a, b, c, Vector2(u0 * Kit.UV_M, 1.0 - (vb + he) * Kit.UV_M), Vector2((u0 + width) * Kit.UV_M, 1.0 - (vb + he) * Kit.UV_M), Vector2((u0 + width * 0.5) * Kit.UV_M, 1.0 - (vb + hr) * Kit.UV_M), Color.WHITE, Color.WHITE, Kit.grey(0.78))
	k.pop_tint()
	k.pop()

## Pitched roof with the ridge along X. style: "corrugated", "rooftile" or "slate".
func roof(k: Kit, sx: float, sz: float, he: float, hr: float, style: String, cx: float = 0.0, sag: float = 0.0, og_w: float = 0.2, og_e: float = 0.2) -> void:
	var run := sz * 0.5
	var oe := 0.3
	var th := 0.06
	var slope := (hr - he) / run
	var cosp := 1.0 / sqrt(1.0 + slope * slope)
	var sinp := slope * cosp
	var x0 := cx - sx * 0.5 - og_w
	var x1 := cx + sx * 0.5 + og_e
	var width := x1 - x0
	var y_e := he + th - oe * slope
	var length := (run + oe) / cosp
	for s: float in [1.0, -1.0]:
		var right := Vector3(s, 0, 0)
		var up := Vector3(0, sinp, -s * cosp)
		var xf := Transform3D(Basis(right, up, right.cross(up)), Vector3(x0 if s > 0.0 else x1, y_e, s * (run + oe)))
		k.push(xf)
		match style:
			"corrugated": _roof_sheets(k, width, length)
			_: _roof_tiles(k, width, length, style, sag)
		# thickness: eave edge, verges, soffit, fascia and barge boards
		var edge_col := Kit.grey(0.55)
		k.quad_m(style, Vector3(0, 0, -th), Vector3(width, 0, -th), Vector3(width, 0, 0), Vector3(0, 0, 0), Vector2(0, 0.96), edge_col, Kit.grey(0.8))
		k.quad_m(style, Vector3(0, length, -th), Vector3(0, 0, -th), Vector3(0, 0, 0), Vector3(0, length, 0), Vector2(0.3, 0.9), edge_col, Kit.grey(0.8))
		k.quad_m(style, Vector3(width, 0, -th), Vector3(width, length, -th), Vector3(width, length, 0), Vector3(width, 0, 0), Vector2(0.6, 0.9), edge_col, Kit.grey(0.8))
		k.quad_m("planks", Vector3(width, 0, -th), Vector3(0, 0, -th), Vector3(0, length, -th), Vector3(width, length, -th), Vector2.ZERO, Kit.grey(0.3), Kit.grey(0.22))
		k.push_tint(Props.WOOD_GREY)
		k.box("planks", Vector3(width * 0.5, 0.012, -th - 0.07), Vector3(width, 0.025, 0.14), Kit.grey(0.75), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
		for bx: float in [0.012, width - 0.012]:
			k.box("planks", Vector3(bx, length * 0.5, -th - 0.075), Vector3(0.026, length, 0.15), Kit.grey(0.8), Kit.grey(0.95), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
		k.pop_tint()
		k.pop()
	# ridge
	var y_r := hr + th
	match style:
		"corrugated":
			for s: float in [1.0, -1.0]:
				var a := Vector3(x0 - 0.02, y_r + 0.03, 0)
				var b := Vector3(x1 + 0.02, y_r + 0.03, 0)
				var down := Vector3(0, -sinp, s * cosp) * 0.2
				var col := Props.GALV * Kit.grey(0.82)
				if s > 0.0:
					k.quad_m("steel", a + down, b + down, b, a, Vector2(0.1, 0.3), col, col)
				else:
					k.quad_m("steel", b + down, a + down, a, b, Vector2(0.5, 0.6), col, col)
			k.tube("steel", PackedVector3Array([Vector3(x0 - 0.03, y_r + 0.035, 0), Vector3(x1 + 0.03, y_r + 0.035, 0)]), 0.04, 6, Props.GALV * Kit.grey(0.9))
		"rooftile":
			var n := int(ceil(width / 0.36))
			for i: int in range(n):
				var t0 := float(i) / float(n)
				var t1 := float(i + 1) / float(n)
				var ya := y_r + 0.01 - sag * sin(PI * t0)
				var yb := y_r + 0.01 - sag * sin(PI * t1)
				var g := rng.randf_range(0.78, 1.0)
				var path := PackedVector3Array([Vector3(lerpf(x0, x1, t0) - 0.02, ya + 0.012, 0), Vector3(lerpf(x0, x1, t1), yb, 0)])
				k.tube("rooftile", path, 0.105, 7, Color(g, g * 0.97, g * 0.95), Vector2(rng.randf(), rng.randf()), 0.2)
		_:
			var lead := Color(0.5, 0.52, 0.55)
			var path := PackedVector3Array()
			for i: int in range(9):
				var t := float(i) / 8.0
				path.append(Vector3(lerpf(x0 - 0.02, x1 + 0.02, t), y_r + 0.03 - sag * sin(PI * t), 0))
			k.tube("steel", path, 0.05, 6, lead)
			for s: float in [1.0, -1.0]:
				var down := Vector3(0, -sinp, s * cosp) * 0.17
				for i: int in range(8):
					var a := path[i] + Vector3(0, -0.015, 0)
					var b := path[i + 1] + Vector3(0, -0.015, 0)
					if s > 0.0:
						k.quad_m("steel", a + down, b + down, b, a, Vector2(0.1 * i, 0.3), lead * Kit.grey(0.85), lead)
					else:
						k.quad_m("steel", b + down, a + down, a, b, Vector2(0.1 * i, 0.6), lead * Kit.grey(0.85), lead)

## Corrugated iron laid as individual sheets (0.64 m wide, 1.28 m long, lapped), each with its own weathering tint.
## Works in the slope frame: X along the eave, Y up the slope, Z out of the roof.
func _roof_sheets(k: Kit, width: float, length: float, sheet_len: float = 1.28) -> void:
	var sw := 0.64
	var n := int(ceil(width / sw))
	var rows := int(ceil(length / sheet_len))
	for row: int in range(rows):
		for i: int in range(n):
			var xa := float(i) * sw
			var xb := minf(width, xa + sw)
			var d0 := float(row) * sheet_len - (0.1 if row > 0 else rng.randf() * 0.035)
			var d1 := minf(length, float(row + 1) * sheet_len)
			var z := 0.013 * float(row)
			var col := _sheet_tint()
			var v0 := 1.0 - (d0 - float(row) * sheet_len) * Kit.UV_M - 0.5 * float(row % 2)
			var v1 := v0 - (d1 - d0) * Kit.UV_M
			var u_off := 0.25 * float(rng.randi() % 4)
			k.quad("corrugated", Vector3(xa, d0, z), Vector3(xb, d0, z), Vector3(xb, d1, z), Vector3(xa, d1, z),
				Vector2(u_off, v0), Vector2(u_off + (xb - xa) * Kit.UV_M, v0), Vector2(u_off + (xb - xa) * Kit.UV_M, v1), Vector2(u_off, v1), col * Kit.grey(0.9), col)
			if row > 0:
				# thin shadowed lip where this sheet laps over the one below
				k.quad("corrugated", Vector3(xa, d0, 0.0), Vector3(xb, d0, 0.0), Vector3(xb, d0, z), Vector3(xa, d0, z), Vector2(0, 0.5), Vector2(0.2, 0.5), Vector2(0.2, 0.49), Vector2(0, 0.49), Kit.grey(0.3), Kit.grey(0.3))

func _sheet_tint() -> Color:
	var r := rng.randf()
	var g := rng.randf_range(0.86, 1.0)
	if r < 0.14:
		return Color(0.95, 0.8, 0.66) * Kit.grey(g)     # rust washed
	if r < 0.24:
		return Color(0.62, 0.63, 0.62) * Kit.grey(g)    # old tarred sheet
	if r < 0.34:
		return Color(0.84, 0.87, 0.8) * Kit.grey(g)     # faded drab paint
	return Kit.grey(g)

func _roof_tiles(k: Kit, width: float, length: float, style: String, sag: float) -> void:
	var nx := 10
	var ny := 4
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var u_off := rng.randf()
	for j: int in range(ny):
		var d := length * float(j) / float(ny - 1)
		for i: int in range(nx):
			var t := float(i) / float(nx - 1)
			var x := width * t
			# old roofs dip between the gables and belly a little between plate and ridge
			var z := -sag * sin(PI * t) * (0.35 + 0.65 * d / length) - sag * 0.5 * sin(PI * d / length) * sin(PI * t)
			pts.append(Vector3(x, d, z))
			uvs.append(Vector2(u_off + x * Kit.UV_M, 1.0 - d * Kit.UV_M))
			var g := 0.9 + 0.1 * d / length + rng.randf_range(-0.04, 0.04)
			cols.append(Kit.grey(g))
	# rows run up the slope: d/dcolumn (x) x d/drow (y) = +Z, the outward normal
	k.patch(style, ny, nx, pts, uvs, cols)

## Lean-to (mono-pitch) corrugated roof: high edge along x = xh at height yh, falling toward x = xl (height yl).
func roof_lean(k: Kit, xh: float, yh: float, xl: float, yl: float, z0: float, z1: float) -> void:
	var dx := xl - xh
	var length := sqrt(dx * dx + (yh - yl) * (yh - yl))
	var up := Vector3(-dx, yh - yl, 0) / length
	var s := signf(dx)
	# slope frame: X along the low eave (viewer's right when looking at the slope from the low side)
	var right := Vector3(0, 0, -s)
	var xf := Transform3D(Basis(right, up, right.cross(up)), Vector3(xl, yl, z1 if s > 0.0 else z0))
	k.push(xf)
	var width := z1 - z0
	_roof_sheets(k, width, length, 1.28)
	k.quad_m("corrugated", Vector3(0, 0, -0.04), Vector3(width, 0, -0.04), Vector3(width, 0, 0), Vector3(0, 0, 0), Vector2(0, 0.96), Kit.grey(0.5), Kit.grey(0.75))
	k.quad_m("planks", Vector3(width, 0, -0.04), Vector3(0, 0, -0.04), Vector3(0, length, -0.04), Vector3(width, length, -0.04), Vector2.ZERO, Kit.grey(0.3), Kit.grey(0.2))
	k.push_tint(Props.WOOD_GREY)
	for d: float in [0.12, length * 0.5, length - 0.08]:
		k.box("planks", Vector3(width * 0.5, d, -0.09), Vector3(width + 0.1, 0.07, 0.1), Kit.grey(0.6), Kit.grey(0.85), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	k.pop()

func chimney(body: Kit, k: Kit, x: float, z: float, y0: float, y1: float) -> void:
	k.box("brick", Vector3(x, (y0 + y1) * 0.5, z), Vector3(0.56, y1 - y0, 0.46), Kit.grey(0.7), Kit.grey(0.95), Vector2(0.3, 0.55), Kit.UPRIGHT, 0b110011)
	k.box("concrete", Vector3(x, y1 + 0.04, z), Vector3(0.68, 0.08, 0.58), Kit.grey(0.7), Color.WHITE)
	for dx: float in [-0.13, 0.13]:
		k.lathe("rooftile", Vector3(x + dx, y1 + 0.08, z), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.075, 0.26), Vector2(0.085, 0.3), Vector2(0.06, 0.3), Vector2(0.055, 0.1)]), 8, Kit.grey(0.75), Kit.grey(0.95),
			Vector2(rng.randf(), rng.randf()), PackedFloat32Array([1.0, 1.0, 1.0, 0.3, 0.1]))
	# lead flashing where the stack meets the roof
	body.box("steel", Vector3(x, y0 + 0.02, z), Vector3(0.62, 0.3, 0.52), Color(0.42, 0.44, 0.46), Color(0.5, 0.52, 0.55), Vector2(0.2, 0.2), Kit.AUTO, 0b110011)

## Stove pipe through a roof slope: base point on the roof surface.
func stove_pipe(k: Kit, at: Vector3, height: float) -> void:
	var col := Props.IRON_RUST
	k.lathe("steel", at + Vector3(0, -0.12, 0), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.1, 0.16), Vector2(0.075, 0.2), Vector2(0.075, height), Vector2(0.09, height + 0.01), Vector2(0.09, height + 0.05)]), 10, col * Kit.grey(0.7), col, Vector2(rng.randf(), rng.randf()))
	k.lathe("steel", at + Vector3(0, height + 0.02, 0), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.02, 0.09)]), 10, col, col * Kit.grey(1.2))
	for a: float in [0.6, 2.7, 4.8]:
		var top := at + Vector3(cos(a) * 0.075, height - 0.14, sin(a) * 0.075)
		k.tube("steel", PackedVector3Array([top, top + Vector3(cos(a) * 0.09, 0.14, sin(a) * 0.09)]), 0.008, 3, col)

## Half-round gutter under an eave plus a downpipe at one end. s = +1 south eave, -1 north eave.
func gutter(k: Kit, sx: float, sz: float, he: float, hr: float, s: float, pipe_end: float, cx: float = 0.0) -> Vector3:
	var slope := (hr - he) / (sz * 0.5)
	var y := he + 0.06 - 0.3 * slope - 0.1
	var z := s * (sz * 0.5 + 0.3 + 0.045)
	var col := Props.IRON
	k.tube("steel", PackedVector3Array([Vector3(cx - sx * 0.5 - 0.26, y + 0.012, z), Vector3(cx + sx * 0.5 + 0.26, y - 0.012, z)]), 0.055, 6, col)
	var x := cx + pipe_end * (sx * 0.5 - 0.12)
	var zw := s * (sz * 0.5 + 0.06)
	k.tube("steel", PackedVector3Array([Vector3(x, y - 0.03, z), Vector3(x, y - 0.14, z), Vector3(x, y - 0.4, zw), Vector3(x, 0.75, zw)]), 0.04, 6, col)
	return Vector3(x, 0, zw)

func skirt(k: Kit, cx: float, cz: float, sx: float, sz: float, reach: float = 0.7, strength: float = 0.55) -> void:
	# soft dark band on the ground round the footprint (stands in for ambient occlusion)
	var col := Color(0.07, 0.06, 0.04, strength)
	var r := Kit.cell_uv(Kit.DECAL["skirt"], 3.0)
	var hx := sx * 0.5
	var hz := sz * 0.5
	var y := 0.03
	var corners: Array[Vector3] = [Vector3(cx - hx, y, cz + hz), Vector3(cx + hx, y, cz + hz), Vector3(cx + hx, y, cz - hz), Vector3(cx - hx, y, cz - hz)]
	var outs: Array[Vector3] = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
	for i: int in range(4):
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var o := outs[i] * reach
		var o_prev := outs[(i + 3) % 4] * reach
		var o_next := outs[(i + 1) % 4] * reach
		# mitred strip: opaque edge on the wall line (image top), fading outward
		k.quad4("decal", a + o + o_prev, b + o + o_next, b, a, Vector2(r.position.x, r.end.y), r.end, Vector2(r.end.x, r.position.y), r.position, col, col, col, col)

# ---------------------------------------------------------------------------------------------------------------
# Barracks: timber weatherboard hut, corrugated iron roof, stove, shuttered windows.
# ---------------------------------------------------------------------------------------------------------------
func barracks(body: Kit, top: Kit, sx: float, sz: float, label: String) -> void:
	var he := 2.3
	var hr := 3.25
	var opt := {"plinth": 0.3, "plinth_key": "concrete"}
	opt["u0"] = 0.0
	side(body, face("S", sx, sz), sx, he, "siding", [win(0.85, 0.95, 0.9, 1.05, "window_a", 1), win(3.75, 0.95, 0.9, 1.05, "window_b", 4)], opt)
	opt["u0"] = sx
	# the east door is where reinforcements turn out: its leaf swings (structures.gd)
	var turnout := door(sz * 0.5 - 0.45)
	turnout["hinged"] = true
	side(body, face("E", sx, sz), sz, he, "siding", [turnout], opt)
	opt["u0"] = sx + sz
	side(body, face("N", sx, sz), sx, he, "siding", [win(0.9, 0.95, 0.9, 1.05, "window_b", 3), win(3.7, 0.95, 0.9, 1.05, "window_a", 2)], opt)
	opt["u0"] = sx * 2.0 + sz
	side(body, face("W", sx, sz), sz, he, "siding", [win(sz * 0.5 - 0.45, 0.95, 0.9, 1.05, "window_a", 1)], opt)
	gable(body, face("E", sx, sz), sz, he, hr, "siding", sx)
	gable(body, face("W", sx, sz), sz, he, hr, "siding", sx * 2.0 + sz)
	# corner boards
	body.push_tint(CASING * Kit.grey(0.9))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			body.box("planks", Vector3(cx * (sx * 0.5 + 0.012), 0.3 + (he - 0.3) * 0.5, cz * (sz * 0.5 + 0.012)), Vector3(0.11, he - 0.3, 0.11), Kit.grey(0.75), Kit.grey(0.85), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110011)
	body.pop_tint()
	# gable ends: name boards, louvre vents, lamp over the door
	body.push(face("E", sx, sz))
	sign_board(body, sz * 0.5, 2.4, 1.4, label)
	gable_vent(body, sz * 0.5, 2.76)
	props.wall_lamp(body, Vector3(sz * 0.5 - 0.85, 1.9, 0.0), 0.0, 0.3)
	body.pop()
	body.push(face("W", sx, sz))
	sign_board(body, sz * 0.5, 2.4, 1.4, label)
	gable_vent(body, sz * 0.5, 2.76)
	body.pop()
	# south wall: bench under the eaves and a rack of fire buckets
	body.push(face("S", sx, sz))
	props.bench(body, Vector3(2.72, 0, 0.22), 0.0, 1.5)
	body.box("planks", Vector3(2.72, 1.42, 0.02), Vector3(1.1, 0.07, 0.04), Kit.grey(0.7), Kit.grey(0.9), Vector2(0.4, 0.2), Kit.BEAM)
	for i: int in range(3):
		var bx := 2.36 + float(i) * 0.36
		body.tube("steel", PackedVector3Array([Vector3(bx, 1.42, 0.04), Vector3(bx, 1.42, 0.16), Vector3(bx, 1.37, 0.17)]), 0.008, 3, Props.IRON)
		props.bucket(body, Vector3(bx, 1.1, 0.19), Color(0.72, 0.24, 0.18), 0.12, 0.24)
	body.pop()
	# north wall: firewood, a water butt under the downpipe
	body.push(face("N", sx, sz))
	props.firewood(body, Vector3(2.75, 0, 0.24), 0.0, 1.5, 5)
	body.lathe("planks", Vector3(1.55, 0, 0.3), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.19, 0.42), Vector2(0.0, 0.43)]), 9, Props.WOOD_DARK, Props.WOOD_GREY, Vector2(0.3, 0.0), PackedFloat32Array([1.0, 1.0, 1.25]), -1.0, true)
	body.beam("planks", Vector3(1.5, 0.44, 0.3), Vector3(1.92, 0.78, 0.18), 0.035, 0.035, Props.WOOD_GREY, Props.WOOD_PALE, Vector2(0.6, 0.2))
	body.box("steel", Vector3(1.53, 0.47, 0.3), Vector3(0.16, 0.09, 0.03), Props.IRON, Props.GALV)
	body.pop()
	var foot := gutter(body, sx, sz, he, hr, -1.0, 1.0)
	props.barrel(body, foot + Vector3(-0.05, 0, -0.27), Color(0.5, 0.55, 0.5), 0.3, false, true)
	gutter(body, sx, sz, he, hr, 1.0, -1.0)
	# west gable: a ladder left leaning on the wall
	props.ladder(body, Vector3(-sx * 0.5 - 0.42, 0, 1.25), Vector3(-sx * 0.5 - 0.06, 2.2, 1.25), 0.4)
	props.duckboard(body, Vector3(sx * 0.5 + 1.25, 0, 0), 0.0, 1.5, 0.8)
	roof(top, sx, sz, he, hr, "corrugated")
	var slope := (hr - he) / (sz * 0.5)
	stove_pipe(top, Vector3(-1.3, hr + 0.06 - 0.9 * slope, -0.9), 0.95)
	# a couple of spare sheets weighted down with timbers
	top.push(Transform3D(Basis(Vector3.RIGHT, atan(slope)), Vector3(1.2, hr + 0.075 - 1.1 * slope, 1.1)))
	top.box("planks", Vector3(0, 0.03, 0), Vector3(1.5, 0.05, 0.11), Kit.grey(0.6), Props.WOOD_GREY, Vector2(0.3, 0.4), Kit.BEAM)
	top.pop()

# ---------------------------------------------------------------------------------------------------------------
# Radio post: rendered brick, clay tile roof, chimney, aerial mast with guys and a lead-in.
# ---------------------------------------------------------------------------------------------------------------
func radio(body: Kit, top: Kit, sx: float, sz: float, label: String) -> void:
	var he := 2.35
	var hr := 3.3
	var opt := {"plinth": 0.34, "plinth_key": "concrete", "plinth_tint": Color(0.5, 0.5, 0.5), "ao_lo": Color(0.86, 0.83, 0.76)}
	opt["u0"] = 0.3
	side(body, face("S", sx, sz), sx, he, "render", [win(0.75, 0.95, 0.95, 1.05, "window_a"), door(2.55, 0.9, 2.0, "door_glazed"), win(4.3, 0.95, 0.95, 1.05, "window_b")], opt)
	opt["u0"] = sx + 0.9
	side(body, face("E", sx, sz), sz, he, "render", [win(sz * 0.5 - 0.45, 1.0, 0.9, 1.0, "window_a")], opt)
	opt["u0"] = sx + sz + 1.7
	side(body, face("N", sx, sz), sx, he, "render", [win(0.9, 1.25, 0.8, 0.7, "window_b"), win(4.2, 1.25, 0.8, 0.7, "window_a")], opt)
	opt["u0"] = sx * 2.0 + sz + 0.4
	side(body, face("W", sx, sz), sz, he, "render", [win(sz * 0.5 - 0.45, 1.0, 0.9, 1.0, "window_a")], opt)
	gable(body, face("E", sx, sz), sz, he, hr, "render", sx + 0.9)
	gable(body, face("W", sx, sz), sz, he, hr, "render", sx * 2.0 + sz + 0.4)
	body.push(face("E", sx, sz))
	sign_board(body, sz * 0.5, 2.38, 1.45, label)
	body.pop()
	body.push(face("W", sx, sz))
	sign_board(body, sz * 0.5, 2.38, 1.45, label)
	body.pop()
	body.push(face("S", sx, sz))
	props.wall_lamp(body, Vector3(3.75, 1.95, 0.0), 0.0, 0.3)
	var pr := Kit.trim_uv("plate_no")
	body.quad_rect("trim", Vector3(3.62, 1.2, 0.012), Vector3(3.9, 1.2, 0.012), Vector3(3.9, 1.39, 0.012), Vector3(3.62, 1.39, 0.012), pr)
	props.bench(body, Vector3(1.22, 0, 0.2), 0.0, 1.1)
	body.pop()
	# north wall: the generator set is built by structures.gd (it has two states); spare fuel beside it
	body.push(face("N", sx, sz))
	props.jerrycan(body, Vector3(GENERATOR_X + 1.62, 0, 0.2), 0.2)
	props.jerrycan(body, Vector3(GENERATOR_X + 1.98, 0, 0.22), -0.3, Props.DRAB_DARK)
	body.pop()
	gutter(body, sx, sz, he, hr, 1.0, 1.0)
	props.cable_drum(body, Vector3(-sx * 0.5 - 0.33, 0, 1.25), PI * 0.5, 0.48, 0.46)
	# sandbag blast wall under the east window and round the south-east corner
	props.sandbag_wall(body, Vector3(sx * 0.5 + 0.24, 0, -1.25), Vector3(sx * 0.5 + 0.24, 0, 1.3), 4, 0.62)
	props.sandbag_wall(body, Vector3(sx * 0.5 - 1.5, 0, sz * 0.5 + 0.24), Vector3(sx * 0.5 + 0.42, 0, sz * 0.5 + 0.24), 4, 0.62)
	props.duckboard(body, Vector3(0.0, 0, sz * 0.5 + 1.25), PI * 0.5, 1.5, 0.8)
	roof(top, sx, sz, he, hr, "rooftile", 0.0, 0.045)
	chimney(body, top, sx * 0.5 - 0.5, 0.0, hr - 0.55, hr + 0.62)
	_mast(top, sx, sz, he, hr)

func _mast(k: Kit, sx: float, sz: float, he: float, hr: float) -> void:
	# tubular mast stepped against the west gable, guyed back to the roof
	var bx := -sx * 0.5 - 0.16
	var bz := -0.75
	var top_y := 7.4
	var col := Props.IRON * Kit.grey(1.15)
	k.lathe("steel", Vector3(bx, 0, bz), PackedVector2Array([Vector2(0.055, 0.0), Vector2(0.055, 3.2), Vector2(0.04, 3.25), Vector2(0.04, 5.6), Vector2(0.028, 5.65), Vector2(0.022, top_y)]), 6, col * Kit.grey(0.7), col)
	for y: float in [0.9, 2.2, 2.95]:
		k.box("steel", Vector3(bx + 0.08, y, bz), Vector3(0.18, 0.05, 0.12), Props.IRON, Props.IRON)
	k.box("concrete", Vector3(bx, 0.06, bz), Vector3(0.3, 0.12, 0.3), PLINTH_AO, Kit.grey(0.9))
	# crosstree and whip
	k.beam("steel", Vector3(bx, 6.6, bz - 0.6), Vector3(bx, 6.6, bz + 0.6), 0.03, 0.03, col, col)
	for z: float in [-0.6, 0.6]:
		k.lathe("steel", Vector3(bx, 6.6, bz + z), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.035, 0.05), Vector2(0.012, 0.09)]), 6, Color(0.9, 0.88, 0.82), Color(0.95, 0.94, 0.9))
	var anchors: Array[Vector3] = [Vector3(sx * 0.5 - 0.3, hr + 0.1, 0.0), Vector3(-sx * 0.5 + 0.1, he + 0.05, sz * 0.5 + 0.2), Vector3(-sx * 0.5 + 0.1, he + 0.05, -sz * 0.5 - 0.2)]
	for a: Vector3 in anchors:
		k.tube("steel", PackedVector3Array([Vector3(bx, 5.55, bz), a]), 0.009, 3, Color(0.25, 0.25, 0.25))
	# lead-in down to the west window
	k.tube("steel", PackedVector3Array([Vector3(bx, 6.6, bz + 0.6), Vector3(bx + 0.02, 3.4, bz + 0.5), Vector3(bx + 0.14, 2.0, 0.2), Vector3(bx + 0.15, 1.75, 0.0)]), 0.012, 3, Color(0.16, 0.16, 0.16))

## Top of the aerial mast in building space (the site code strings the long-wire aerial from here).
func mast_top(sx: float) -> Vector3:
	return Vector3(-sx * 0.5 - 0.16, 6.6, -1.35)

## Foot of the aerial mast in building space: the generator's feed ends there and the alarm horn is clamped to it.
func mast_foot(sx: float) -> Vector3:
	return Vector3(-sx * 0.5 - 0.16, 0.0, -0.75)

# ---------------------------------------------------------------------------------------------------------------
# Supply depot: brick store with timber gables and slate roof (5 m) plus an open lean-to bay (2 m) on the east end.
# ---------------------------------------------------------------------------------------------------------------
func depot(body: Kit, top: Kit, sx: float, sz: float, label: String) -> void:
	var he := 2.4
	var hr := 3.35
	var lean := 2.0
	var mx := sx - lean                 # main block length
	var cx := -lean * 0.5               # main block centre
	var xe := cx + mx * 0.5             # east wall of the main block
	var opt := {"plinth": 0.0, "ao_lo": Color(0.8, 0.76, 0.7)}
	opt["u0"] = 0.0
	side(body, face("S", mx, sz, cx), mx, he, "brick", [win(0.9, 1.2, 0.9, 0.62, "window_b"), win(3.2, 1.2, 0.9, 0.62, "window_a")], opt)
	opt["u0"] = mx + 0.3
	side(body, face("E", mx, sz, cx), sz, he, "brick", [], opt)
	opt["u0"] = mx + sz + 0.7
	var slide := {"t": "slide", "x": 1.1, "y": 0.0, "w": 2.8, "h": 2.2, "cell": "slide_door", "sh": 0}
	side(body, face("N", mx, sz, cx), mx, he, "brick", [slide], opt)
	opt["u0"] = mx * 2.0 + sz + 0.2
	side(body, face("W", mx, sz, cx), sz, he, "brick", [door(sz * 0.5 - 0.45, 0.9, 2.0, "door_plank", 0.12)], opt)
	gable(body, face("E", mx, sz, cx), sz, he, hr, "planks", 0.0, Props.WOOD_DARK * Kit.grey(1.25), true)
	gable(body, face("W", mx, sz, cx), sz, he, hr, "planks", 1.3, Props.WOOD_DARK * Kit.grey(1.25), true)
	# brick piers and a soldier course band
	for s: String in ["S", "N"]:
		body.push(face(s, mx, sz, cx))
		var xs: Array = [0.17, mx - 0.17] if s == "N" else [0.17, mx * 0.5, mx - 0.17]
		for px: float in xs:
			body.box("brick", Vector3(px, he * 0.5, 0.03), Vector3(0.34, he, 0.1), Color(0.55, 0.52, 0.48), Kit.grey(0.85), Vector2(px * Kit.UV_M + 0.11, 1.0), Kit.UPRIGHT, 0b110111)
		body.pop()
	for s: String in ["E", "W"]:
		body.push(face(s, mx, sz, cx))
		for px: float in [0.17, sz - 0.17]:
			body.box("brick", Vector3(px, he * 0.5, 0.03), Vector3(0.34, he, 0.1), Color(0.55, 0.52, 0.48), Kit.grey(0.85), Vector2(px * Kit.UV_M + 0.31, 1.0), Kit.UPRIGHT, 0b110111)
		# tie beam at the foot of the boarded gable
		body.box("planks", Vector3(sz * 0.5, he + 0.02, 0.03), Vector3(sz + 0.08, 0.16, 0.07), Props.WOOD_DARK * Kit.grey(0.8), Props.WOOD_DARK, Vector2(0.2, 0.3), Kit.BEAM)
		sign_board(body, sz * 0.5, 2.66, 1.25, label, 0.06)
		body.pop()
	# north: sliding doors on an overhead rail, one leaf pushed back a little; loading step
	body.push(face("N", mx, sz, cx))
	var sr := Kit.trim_uv("slide_door")
	var edge := Rect2(sr.position + Vector2(0.01, 0.2), Vector2(0.02, 0.2))
	body.quad_m("planks", Vector3(1.1, 0.0, -0.1), Vector3(3.9, 0.0, -0.1), Vector3(3.9, 2.2, -0.1), Vector3(1.1, 2.2, -0.1), Vector2.ZERO, Kit.grey(0.05), Kit.grey(0.03))
	body.box_rects("trim", Vector3(1.8 - 0.05, 1.17, 0.075), Vector3(1.5, 2.16, 0.06), [edge, edge, edge, null, sr, null], Kit.grey(0.7), Kit.grey(0.95))
	body.box_rects("trim", Vector3(3.62, 1.17, 0.14), Vector3(1.5, 2.16, 0.06), [edge, edge, edge, null, sr, null], Kit.grey(0.7), Kit.grey(0.95))
	body.box("steel", Vector3(2.75, 2.29, 0.12), Vector3(4.2, 0.07, 0.07), Props.IRON, Props.IRON * Kit.grey(1.2))
	for bx: float in [0.75, 2.1, 3.4, 4.75]:
		body.box("steel", Vector3(bx, 2.31, 0.05), Vector3(0.06, 0.12, 0.1), Props.IRON, Props.IRON)
	body.box("concrete", Vector3(2.5, 0.07, 0.24), Vector3(3.4, 0.14, 0.48), PLINTH_AO, Color.WHITE, Vector2(0.1, 0.3))
	var apron := body.xf * Vector3(2.5, 0, 1.5)
	wear.append(Vector3(apron.x, apron.z, 3.6))
	props.wall_lamp(body, Vector3(0.62, 1.95, 0.08), 0.0, 0.3)
	var arrow := Kit.trim_uv("plate_arrow")
	body.quad_rect("trim", Vector3(4.28, 1.3, 0.012), Vector3(4.62, 1.3, 0.012), Vector3(4.62, 1.53, 0.012), Vector3(4.28, 1.53, 0.012), arrow, Kit.grey(0.9), Color.WHITE)
	body.pop()
	# south: a short run of pallets and spare timber leaning on the wall
	body.push(face("S", mx, sz, cx))
	for i: int in range(3):
		body.push(Transform3D(Basis(Vector3.RIGHT, -1.36 + float(i) * 0.03), Vector3(2.1 + float(i) * 0.03, 0.02, 0.3 - float(i) * 0.09)))
		props.pallet(body, Vector3.ZERO, 0.0, Vector2(1.1, 0.95))
		body.pop()
	for i: int in range(4):
		var px := 3.55 + float(i) * 0.11
		body.beam("planks", Vector3(px, 0.0, 0.34 + rng.randf() * 0.08), Vector3(px + rng.randf_range(-0.04, 0.04), 1.9 + rng.randf() * 0.25, 0.04), 0.1, 0.035, Props.WOOD_GREY * Kit.grey(0.7), Props.WOOD_GREY, Vector2(rng.randf(), rng.randf()))
	body.pop()
	gutter(body, mx, sz, he, hr, 1.0, -1.0, cx)
	roof(top, mx, sz, he, hr, "slate", cx, 0.035, 0.2, 0.06)
	# cowl ventilator on the ridge
	top.lathe("steel", Vector3(cx - 0.8, hr + 0.02, 0), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.12, 0.1), Vector2(0.11, 0.34), Vector2(0.2, 0.36), Vector2(0.2, 0.42), Vector2(0.02, 0.52)]), 10, Props.GALV * Kit.grey(0.6), Props.GALV * Kit.grey(0.85), Vector2(0.4, 0.4))
	_lean_to(body, top, xe, sx * 0.5, sz)

func _lean_to(body: Kit, top: Kit, x0: float, x1: float, sz: float) -> void:
	# open-sided store bay under a corrugated mono-pitch: posts, plates, and enough stacked stores to read as solid
	var yh := 2.2
	var yl := 1.82
	var hz := sz * 0.5
	body.push_tint(Props.WOOD_GREY * Kit.grey(0.85))
	for z: float in [-hz + 0.08, 0.0, hz - 0.08]:
		body.box("planks", Vector3(x1 - 0.08, (yl - 0.1) * 0.5, z), Vector3(0.13, yl - 0.1, 0.13), Props.AO, Kit.grey(0.9), Vector2(rng.randf(), rng.randf()), Kit.BEAM, 0b110011)
		body.beam("planks", Vector3(x1 - 0.08, 1.3, z), Vector3(x1 - 0.5, yl - 0.06, z), 0.07, 0.07, Kit.grey(0.7), Kit.grey(0.9), Vector2(rng.randf(), rng.randf()))
	body.box("planks", Vector3(x1 - 0.08, yl - 0.05, 0), Vector3(0.12, 0.14, sz), Kit.grey(0.7), Kit.grey(0.9), Vector2(0.5, 0.2), Kit.BEAM)
	body.box("planks", Vector3(x0 + 0.05, yh - 0.02, 0), Vector3(0.08, 0.14, sz), Kit.grey(0.7), Kit.grey(0.9), Vector2(0.1, 0.6), Kit.BEAM)
	for z: float in [-hz + 0.08, -hz * 0.5, 0.0, hz * 0.5, hz - 0.08]:
		body.beam("planks", Vector3(x0 + 0.02, yh - 0.03, z), Vector3(x1 + 0.12, yl - 0.11, z), 0.06, 0.1, Kit.grey(0.6), Kit.grey(0.8), Vector2(rng.randf(), rng.randf()))
	body.pop_tint()
	# low brick dwarf wall along the back (south) side keeps the stores in
	body.box("brick", Vector3((x0 + x1) * 0.5, 0.35, hz - 0.11), Vector3(x1 - x0, 0.7, 0.22), Color(0.55, 0.52, 0.48), Kit.grey(0.95), Vector2(0.3, 1.0), Kit.UPRIGHT, 0b110111)
	body.box("concrete", Vector3((x0 + x1) * 0.5, 0.73, hz - 0.11), Vector3(x1 - x0 + 0.02, 0.06, 0.27), Kit.grey(0.8), Color.WHITE)
	body.box("concrete", Vector3((x0 + x1) * 0.5, 0.03, -0.05), Vector3(x1 - x0, 0.06, sz - 0.1), Kit.grey(0.75), Kit.grey(0.8), Vector2(0.4, 0.1), Kit.AUTO, 0b000100)
	# stores: drums, tyres, cans, crates
	var tints: Array[Color] = [Props.DRAB, Props.DRAB_DARK, Color(0.55, 0.42, 0.34), Color(0.5, 0.56, 0.6)]
	var i := 0
	for z: float in [1.2, 0.6]:
		for x: float in [0.38, 1.0, 1.6]:
			if z < 0.8 and x > 1.3:
				continue
			props.barrel(body, Vector3(x0 + x, 0.06, z + props.jitter(0.03)), tints[i % 4] * props.tone(0.2), rng.randf() * TAU)
			i += 1
	props.barrel(body, Vector3(x0 + 0.7, 0.94, 0.9), tints[1] * props.tone(0.2), 1.0)
	props.crate(body, Vector3(x0 + 0.55, 0.06, -0.6), Vector3(0.9, 0.62, 0.7), 0.04, 1, Props.WOOD_PALE)
	props.crate(body, Vector3(x0 + 0.5, 0.68, -0.62), Vector3(0.7, 0.42, 0.55), -0.1, 0, Props.WOOD_PALE * Kit.grey(0.9))
	props.crate(body, Vector3(x0 + 0.5, 0.06, -1.32), Vector3(0.8, 0.5, 0.6), 0.0, 5, Props.WOOD_PALE * Kit.grey(0.85))
	# tyre stack
	for t: int in range(4):
		props.tyre(body, Transform3D(Basis.IDENTITY, Vector3(x0 + 1.45 + props.jitter(0.02), 0.06 + float(t) * 0.2, -1.12 + props.jitter(0.02))), 0.31, 0.1)
	props.tyre(body, Transform3D(Basis.IDENTITY, Vector3(x0 + 1.5, 0.06, -0.45)), 0.31, 0.1)
	props.jerrycan(body, Vector3(x0 + 1.72, 0.06, 0.3), 1.4)
	props.jerrycan(body, Vector3(x0 + 1.72, 0.06, -0.05), 1.7, Props.DRAB_DARK)
	props.rope_coil(body, Vector3(x0 + 0.5, 1.1, -0.62), 0.2, 4)
	roof_lean(top, x0 + 0.02, yh + 0.06, x1 + 0.28, yl - 0.02, -hz - 0.25, hz + 0.25)
