extends RefCounted
## Mesh kit for the structures module: accumulates quads / boxes / lathes / patches into one vertex stream per
## material key and commits them as a single multi-surface ArrayMesh (one draw call per material).
## Conventions: 1 unit = 1 m, tiling textures are 512 px = 2.56 m (UV_M), vertex colour = baked AO / dirt / tint.
## Quad corners are given bottom-left, bottom-right, top-right, top-left as seen from the visible side.

const TEX_DIR := "res://assets/tex/structures/"
## Metres -> UV for the tiling 512 px surface textures (200 px per metre).
const UV_M := 1.0 / 2.56
## One board row of the planks texture (16 rows per tile); beams use a single row so no gap lines show.
const PLANK_ROW := 1.0 / 16.0
## box() UV modes.
const AUTO := 0
const BEAM := 1
const UPRIGHT := 2

## Trim sheet rectangles in pixels (x, y, w, h) on the 1024 px atlas. Mirrors TRIM in tools/gen_structures_textures.py.
const TRIM := {
	"sign0": Rect2(0, 0, 512, 112), "sign1": Rect2(0, 112, 512, 112), "sign2": Rect2(0, 224, 512, 112),
	"plate_arrow": Rect2(0, 336, 128, 88), "plate_no": Rect2(128, 336, 128, 88), "plate_warn": Rect2(256, 336, 128, 88),
	"plate_blank": Rect2(384, 336, 128, 88), "board_blank": Rect2(0, 424, 512, 88),
	"door_plank": Rect2(512, 0, 256, 512), "door_glazed": Rect2(768, 0, 256, 512), "slide_door": Rect2(0, 512, 320, 512),
	"window_a": Rect2(320, 512, 256, 256), "window_b": Rect2(576, 512, 256, 256), "shutter": Rect2(832, 512, 96, 256),
	"vent": Rect2(928, 512, 96, 96), "lock": Rect2(928, 608, 96, 96), "tabletop": Rect2(320, 768, 256, 256),
	"grille": Rect2(576, 768, 128, 192), "lens": Rect2(704, 768, 64, 64), "glass": Rect2(704, 832, 64, 64),
	"drum_lid": Rect2(768, 768, 128, 128), "cable_drum": Rect2(768, 896, 128, 128), "panel": Rect2(896, 768, 128, 128),
	"blanket": Rect2(896, 896, 128, 128),
}
## Crate atlas cells (2 x 2 on 512 px).
const CRATE := {"braced": Vector2i(0, 0), "stencil": Vector2i(1, 0), "lid": Vector2i(0, 1), "end": Vector2i(1, 1)}
## Ground decal atlas cells (2 x 2 on 512 px).
const DECAL := {"blob": Vector2i(0, 0), "skirt": Vector2i(1, 0), "oil": Vector2i(0, 1), "dirt": Vector2i(1, 1)}
## Wire cut-out bands: V ranges on the 512 px atlas; U tiles (2.56 m per repeat).
const WIRE_MESH := Vector2(2.0 / 512.0, 254.0 / 512.0)
const WIRE_BARB := Vector2(264.0 / 512.0, 312.0 / 512.0)
const WIRE_COIL := Vector2(326.0 / 512.0, 506.0 / 512.0)

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	## Several material keys drawn as one surface (see aliases): the layer of each vertex, in UV2.x.
	var uv2 := PackedVector2Array()
	var layered := false

## Optional: material keys drawn as layers of one surface, {key: [surface key, layer]}. Empty unless a builder sets it
## for the time it builds (La Boca's houses share one array texture); every kit then writes those keys into that one
## surface, the layer in UV2.x.
static var aliases: Dictionary = {}
var _layer: float = 0.0

var surfs: Dictionary = {}
## Current local -> output transform (rigid; use push/pop).
var xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
## Multiplied into every vertex colour (per-object tint variation).
var tint := Color.WHITE
var _tint_stack: Array[Color] = []

# ---------------------------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------------------------
## key: [has normal map, roughness in albedo alpha, constant roughness, normal strength]
const MATERIAL_SPECS := {
	"siding": [true, false, 0.9, 1.0], "brick": [true, false, 0.93, 1.0], "render": [true, false, 0.93, 0.9],
	"stone": [true, false, 0.95, 1.1], "concrete": [true, false, 0.92, 0.9], "corrugated": [true, true, 1.0, 1.0],
	"rooftile": [true, false, 0.9, 1.0], "slate": [true, true, 1.0, 1.0], "planks": [true, false, 0.9, 1.0],
	"canvas": [true, false, 0.95, 1.0], "burlap": [true, false, 0.97, 1.0], "steel": [true, true, 1.0, 0.8],
	"rubber": [true, false, 0.9, 1.0], "trim": [true, true, 1.0, 0.9], "crate": [true, false, 0.9, 1.0],
}

static func make_materials() -> Dictionary:
	var out: Dictionary = {}
	for key: String in MATERIAL_SPECS:
		var spec: Array = MATERIAL_SPECS[key]
		var m := StandardMaterial3D.new()
		var albedo: Texture2D = load(TEX_DIR + key + "_a.png")
		m.albedo_texture = albedo
		m.vertex_color_use_as_albedo = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if spec[0]:
			m.normal_enabled = true
			m.normal_texture = load(TEX_DIR + key + "_n.png")
			m.normal_scale = spec[3]
		m.roughness = spec[2]
		if spec[1]:
			m.roughness_texture = albedo
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
		m.metallic_specular = 0.4
		out[key] = m
	# Barbed wire / netting cut-outs: alpha scissor, both sides.
	var wire := StandardMaterial3D.new()
	wire.albedo_texture = load(TEX_DIR + "wire_a.png")
	wire.vertex_color_use_as_albedo = true
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	wire.alpha_scissor_threshold = 0.16
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	wire.roughness = 0.8
	wire.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	out["wire"] = wire
	# Ground "decals": blended quads lying just above the terrain (the GL Compatibility renderer has no Decal nodes).
	var ground := StandardMaterial3D.new()
	ground.albedo_texture = load(TEX_DIR + "decal_a.png")
	ground.vertex_color_use_as_albedo = true
	ground.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground.roughness = 1.0
	ground.metallic_specular = 0.0
	ground.render_priority = -1
	out["decal"] = ground
	# Lamp glass and lit openings: flat colour straight from the vertices, untouched by sun and shadow.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	out["glow"] = glow
	return out

# ---------------------------------------------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------------------------------------------
func push(local: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * local

func push_at(at: Vector3, yaw: float = 0.0) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw), at))

func pop() -> void:
	xf = _stack.pop_back()

func push_tint(c: Color) -> void:
	_tint_stack.append(tint)
	tint = tint * c

func pop_tint() -> void:
	tint = _tint_stack.pop_back()

func _surf(key: String) -> Surf:
	var layered := false
	if not aliases.is_empty() and aliases.has(key):
		var alias: Array = aliases[key]
		key = alias[0]
		_layer = float(alias[1])
		layered = true
	var sf: Surf = surfs.get(key)
	if sf == null:
		sf = Surf.new()
		sf.layered = layered
		surfs[key] = sf
	return sf

static func grey(g: float) -> Color:
	return Color(g, g, g)

## UV rectangle of a trim cell (inset half a texel against bleeding).
static func trim_uv(cell: String) -> Rect2:
	var r: Rect2 = TRIM[cell]
	return Rect2((r.position + Vector2(1.5, 1.5)) / 1024.0, (r.size - Vector2(3, 3)) / 1024.0)

static func cell_uv(cell: Vector2i, inset: float = 2.0) -> Rect2:
	return Rect2((Vector2(cell) * 256.0 + Vector2(inset, inset)) / 512.0, Vector2(256.0 - inset * 2.0, 256.0 - inset * 2.0) / 512.0)

# ---------------------------------------------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------------------------------------------
func _push_vertex(sf: Surf, p: Vector3, n: Vector3, t: Vector3, w: float, uv: Vector2, c: Color) -> void:
	sf.v.append(p)
	sf.n.append(n)
	sf.t.append(t.x)
	sf.t.append(t.y)
	sf.t.append(t.z)
	sf.t.append(w)
	sf.uv.append(uv)
	sf.c.append(c * tint)
	if sf.layered: sf.uv2.append(Vector2(_layer, 0.0))

## Flat quad with one colour per corner. Corners: bottom-left, bottom-right, top-right, top-left (seen from outside).
func quad4(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var sf := _surf(key)
	a = xf * a
	b = xf * b
	c = xf * c
	d = xf * d
	var e1 := b - a
	var e2 := d - a
	var n := e1.cross(e2).normalized()
	var du1 := ub.x - ua.x
	var dv1 := ub.y - ua.y
	var du2 := ud.x - ua.x
	var dv2 := ud.y - ua.y
	var det := du1 * dv2 - du2 * dv1
	var t := e1.normalized()
	var w := 1.0
	if absf(det) > 1e-10:
		var tu := (e1 * dv2 - e2 * dv1) / det
		var bv := (e2 * du1 - e1 * du2) / det
		tu = tu - n * n.dot(tu)
		if tu.length_squared() > 1e-12:
			t = tu.normalized()
			# Godot's bitangent points toward decreasing V (image up).
			w = 1.0 if n.cross(t).dot(-bv) >= 0.0 else -1.0
	var base := sf.v.size()
	_push_vertex(sf, a, n, t, w, ua, ca)
	_push_vertex(sf, b, n, t, w, ub, cb)
	_push_vertex(sf, c, n, t, w, uc, cc)
	_push_vertex(sf, d, n, t, w, ud, cd)
	sf.idx.append(base)
	sf.idx.append(base + 2)
	sf.idx.append(base + 1)
	sf.idx.append(base)
	sf.idx.append(base + 3)
	sf.idx.append(base + 2)

## Flat quad, colour lo on the bottom edge (a, b) and hi on the top edge (c, d).
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, lo: Color = Color.WHITE, hi: Color = Color.WHITE) -> void:
	quad4(key, a, b, c, d, ua, ub, uc, ud, lo, lo, hi, hi)

## Flat quad mapped to a UV rectangle (image top on the c-d edge).
func quad_rect(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, r: Rect2, lo: Color = Color.WHITE, hi: Color = Color.WHITE) -> void:
	quad4(key, a, b, c, d, Vector2(r.position.x, r.end.y), r.end, Vector2(r.end.x, r.position.y), r.position, lo, lo, hi, hi)

## Flat quad with world-scale UVs derived from its own edges (u along a->b, v up a->d), offset by uv0 (in UV units).
func quad_m(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2 = Vector2.ZERO, lo: Color = Color.WHITE, hi: Color = Color.WHITE, swap: bool = false) -> void:
	var w := a.distance_to(b) * UV_M
	var h := a.distance_to(d) * UV_M
	if swap:
		# texture U runs up the quad (boards / corrugations running vertically)
		quad4(key, a, b, c, d, uv0 + Vector2(0, 0), uv0 + Vector2(0, w), uv0 + Vector2(h, w), uv0 + Vector2(h, 0), lo, lo, hi, hi)
	else:
		quad4(key, a, b, c, d, uv0 + Vector2(0, h), uv0 + Vector2(w, h), uv0 + Vector2(w, 0), uv0, lo, lo, hi, hi)

func tri(key: String, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ca: Color = Color.WHITE, cb: Color = Color.WHITE, cc: Color = Color.WHITE) -> void:
	# a, b, c counter-clockwise seen from outside (a-b is the base, c the apex).
	var sf := _surf(key)
	a = xf * a
	b = xf * b
	c = xf * c
	var e1 := b - a
	var e2 := c - a
	var n := e1.cross(e2).normalized()
	var du1 := ub.x - ua.x
	var dv1 := ub.y - ua.y
	var du2 := uc.x - ua.x
	var dv2 := uc.y - ua.y
	var det := du1 * dv2 - du2 * dv1
	var t := e1.normalized()
	var w := 1.0
	if absf(det) > 1e-10:
		var tu := (e1 * dv2 - e2 * dv1) / det
		var bv := (e2 * du1 - e1 * du2) / det
		tu = tu - n * n.dot(tu)
		if tu.length_squared() > 1e-12:
			t = tu.normalized()
			w = 1.0 if n.cross(t).dot(-bv) >= 0.0 else -1.0
	var base := sf.v.size()
	_push_vertex(sf, a, n, t, w, ua, ca)
	_push_vertex(sf, b, n, t, w, ub, cb)
	_push_vertex(sf, c, n, t, w, uc, cc)
	sf.idx.append(base)
	sf.idx.append(base + 2)
	sf.idx.append(base + 1)

## Axis-aligned box in the current transform. UVs are world-scale; on every face the texture U axis follows the
## box's longest dimension where it can (so board grain runs along beams and planks).
## lo / hi: vertex colour at the bottom / top (baked ground occlusion). faces: bit mask +X -X +Y -Y +Z -Z.
## mode: AUTO as above; BEAM squeezes V into a single board row of the planks texture (no gap lines);
## UPRIGHT keeps texture U horizontal on the side faces with V = uv0.y at the box's base (masonry courses).
func box(key: String, center: Vector3, size: Vector3, lo: Color = Color.WHITE, hi: Color = Color.WHITE, uv0: Vector2 = Vector2.ZERO, mode: int = AUTO, faces: int = 63) -> void:
	var squeeze := mode == BEAM
	var h := size * 0.5
	var longest := 0
	if size.y >= size.x and size.y >= size.z:
		longest = 1
	elif size.z >= size.x and size.z >= size.y:
		longest = 2
	# face: [normal axis, sign, right axis, up axis]
	var defs: Array = [[0, 1.0, 2, 1], [0, -1.0, 2, 1], [1, 1.0, 0, 2], [1, -1.0, 0, 2], [2, 1.0, 0, 1], [2, -1.0, 0, 1]]
	for f: int in range(6):
		if (faces & (1 << f)) == 0:
			continue
		var def: Array = defs[f]
		var na: int = def[0]
		var sgn: float = def[1]
		var ra: int = def[2]
		var ua: int = def[3]
		var nrm := Vector3.ZERO
		nrm[na] = sgn
		var right := Vector3.ZERO
		right[ra] = 1.0
		var up := Vector3.ZERO
		up[ua] = 1.0
		# make (right x up) = normal
		if right.cross(up).dot(nrm) < 0.0:
			right = -right
		var o := center + nrm * h[na]
		var a := o - right * h[ra] - up * h[ua]
		var b := o + right * h[ra] - up * h[ua]
		var c := o + right * h[ra] + up * h[ua]
		var d := o - right * h[ra] + up * h[ua]
		var ca := lo.lerp(hi, clampf((a.y - (center.y - h.y)) / maxf(size.y, 1e-5), 0.0, 1.0))
		var cb := lo.lerp(hi, clampf((b.y - (center.y - h.y)) / maxf(size.y, 1e-5), 0.0, 1.0))
		var cc := lo.lerp(hi, clampf((c.y - (center.y - h.y)) / maxf(size.y, 1e-5), 0.0, 1.0))
		var cd := lo.lerp(hi, clampf((d.y - (center.y - h.y)) / maxf(size.y, 1e-5), 0.0, 1.0))
		var along_up: bool = (ua == longest) or (ra != longest and size[ua] > size[ra])
		var su: float = size[ra] * UV_M
		var sv: float = size[ua] * UV_M
		var q := uv0 + Vector2(f * 0.137, f * 0.071)
		if mode == UPRIGHT:
			if na == 1:
				quad4(key, a, b, c, d, q + Vector2(0, sv), q + Vector2(su, sv), q + Vector2(su, 0), q, ca, cb, cc, cd)
			else:
				var qu := uv0.x + f * 0.137
				quad4(key, a, b, c, d, Vector2(qu, uv0.y), Vector2(qu + su, uv0.y), Vector2(qu + su, uv0.y - sv), Vector2(qu, uv0.y - sv), ca, cb, cc, cd)
		elif along_up:
			var vs: float = su
			if squeeze:
				vs = PLANK_ROW * 0.8
				q.y = floorf(q.y / PLANK_ROW) * PLANK_ROW + PLANK_ROW * 0.1
			quad4(key, a, b, c, d, q, q + Vector2(0, vs), q + Vector2(sv, vs), q + Vector2(sv, 0), ca, cb, cc, cd)
		else:
			var vs2: float = sv
			if squeeze:
				vs2 = PLANK_ROW * 0.8
				q.y = floorf(q.y / PLANK_ROW) * PLANK_ROW + PLANK_ROW * 0.1
			quad4(key, a, b, c, d, q + Vector2(0, vs2), q + Vector2(su, vs2), q + Vector2(su, 0), q, ca, cb, cc, cd)

## Box whose faces each show a whole UV rectangle (atlas cells). rects order: +X -X +Y -Y +Z -Z; null skips a face.
func box_rects(key: String, center: Vector3, size: Vector3, rects: Array, lo: Color = Color.WHITE, hi: Color = Color.WHITE) -> void:
	var h := size * 0.5
	var defs: Array = [[0, 1.0, 2, 1], [0, -1.0, 2, 1], [1, 1.0, 0, 2], [1, -1.0, 0, 2], [2, 1.0, 0, 1], [2, -1.0, 0, 1]]
	for f: int in range(6):
		if rects[f] == null:
			continue
		var def: Array = defs[f]
		var nrm := Vector3.ZERO
		nrm[def[0]] = def[1]
		var right := Vector3.ZERO
		right[def[2]] = 1.0
		var up := Vector3.ZERO
		up[def[3]] = 1.0
		if right.cross(up).dot(nrm) < 0.0:
			right = -right
		var o: Vector3 = center + nrm * h[def[0]]
		var a: Vector3 = o - right * h[def[2]] - up * h[def[3]]
		var b: Vector3 = o + right * h[def[2]] - up * h[def[3]]
		var c: Vector3 = o + right * h[def[2]] + up * h[def[3]]
		var d: Vector3 = o - right * h[def[2]] + up * h[def[3]]
		var top_face: bool = def[0] == 1
		var c_lo := hi if (top_face and def[1] > 0.0) else lo
		var c_hi := lo if (top_face and def[1] < 0.0) else hi
		quad_rect(key, a, b, c, d, rects[f], c_lo, c_hi)

## Box of cross-section (w across, h tall) running from a to b: struts, braces, rails, rafters.
## For near-vertical runs `side` picks the direction the h dimension faces.
func beam(key: String, a: Vector3, b: Vector3, w: float, h: float, lo: Color = Color.WHITE, hi: Color = Color.WHITE, uv0: Vector2 = Vector2.ZERO, grain: bool = true, side: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-5:
		return
	var x := d / length
	var ref := side
	if absf(x.dot(ref)) > 0.985:
		ref = Vector3.RIGHT if absf(x.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var z := x.cross(ref).normalized()
	var y := z.cross(x)
	push(Transform3D(Basis(x, y, z), (a + b) * 0.5))
	box(key, Vector3.ZERO, Vector3(length, h, w), lo, hi, uv0, BEAM if grain else AUTO)
	pop()

## Smooth-shaded grid patch. pts / uvs / cols are flattened rows x columns arrays (row-major).
## Normal = d/dcolumn x d/drow (flip = true reverses it and the winding). wrap_u: last column repeats the first.
func patch(key: String, rows: int, columns: int, pts: PackedVector3Array, uvs: PackedVector2Array, cols: PackedColorArray, wrap_u: bool = false, flip: bool = false, wrap_v: bool = false) -> void:
	var sf := _surf(key)
	var base := sf.v.size()
	var single := cols.size() == 1
	for i: int in range(rows):
		for j: int in range(columns):
			var k := i * columns + j
			var jl := j - 1
			var jr := j + 1
			if jl < 0:
				jl = columns - 2 if wrap_u else 0
			if jr >= columns:
				jr = 1 if wrap_u else columns - 1
			var iu := i - 1
			var id := i + 1
			if iu < 0:
				iu = rows - 2 if wrap_v else 0
			if id >= rows:
				id = 1 if wrap_v else rows - 1
			var du := pts[i * columns + jr] - pts[i * columns + jl]
			var dv := pts[id * columns + j] - pts[iu * columns + j]
			var n := du.cross(dv)
			if n.length_squared() < 1e-14:
				# degenerate (pole): borrow from the neighbouring row
				var i2 := i + 1 if i == 0 else i - 1
				du = pts[i2 * columns + jr] - pts[i2 * columns + jl]
				n = du.cross(dv)
			n = n.normalized()
			if flip:
				n = -n
			var duv := uvs[i * columns + jr] - uvs[i * columns + jl]
			var dvv := uvs[id * columns + j] - uvs[iu * columns + j]
			# tangent = dP/dU, bitangent = -dP/dV (Godot's convention), solved from the grid differences
			var det := duv.x * dvv.y - dvv.x * duv.y
			var t := du
			var bt := -dv
			if absf(det) > 1e-12:
				t = (du * dvv.y - dv * duv.y) / det
				bt = -(dv * duv.x - du * dvv.x) / det
			t = t - n * n.dot(t)
			t = t.normalized() if t.length_squared() > 1e-14 else n.cross(Vector3.UP).normalized()
			var w := 1.0 if n.cross(t).dot(bt) >= 0.0 else -1.0
			_push_vertex(sf, xf * pts[k], (xf.basis * n).normalized(), (xf.basis * t).normalized(), w, uvs[k], cols[0] if single else cols[k])
	for i: int in range(rows - 1):
		for j: int in range(columns - 1):
			var a := base + i * columns + j
			var b := a + 1
			var d := a + columns
			var c := d + 1
			if flip:
				sf.idx.append(a)
				sf.idx.append(b)
				sf.idx.append(c)
				sf.idx.append(a)
				sf.idx.append(c)
				sf.idx.append(d)
			else:
				sf.idx.append(a)
				sf.idx.append(c)
				sf.idx.append(b)
				sf.idx.append(a)
				sf.idx.append(d)
				sf.idx.append(c)

## Surface of revolution round the local Y axis through `at`. profile: (radius, y) pairs from bottom to top.
## Vertex colour runs from lo (lowest y) to hi (highest y); shade[i] optionally multiplies ring i.
## along = true maps the planks texture lengthways (posts, poles, logs).
func lathe(key: String, at: Vector3, profile: PackedVector2Array, segments: int = 12, lo: Color = Color.WHITE, hi: Color = Color.WHITE, uv0: Vector2 = Vector2.ZERO, shade: PackedFloat32Array = PackedFloat32Array(), u_repeat: float = -1.0, along: bool = false) -> void:
	var rows := profile.size()
	var columns := segments + 1
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var y_min := profile[0].y
	var y_max := profile[0].y
	var r_max := 0.0
	for p: Vector2 in profile:
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
		r_max = maxf(r_max, p.x)
	var u_total := u_repeat if u_repeat > 0.0 else TAU * r_max * UV_M
	var run := 0.0
	# rows go bottom -> top so that (d/dcolumn x d/drow) points outward with the angle increasing
	for i: int in range(rows):
		var p := profile[i]
		if i > 0:
			run += p.distance_to(profile[i - 1])
		var c := lo.lerp(hi, (p.y - y_min) / maxf(y_max - y_min, 1e-5))
		if shade.size() == rows:
			c = c * grey(shade[i])
			c.a = 1.0
		for j: int in range(columns):
			var ang := TAU * float(j) / float(segments)
			pts.append(at + Vector3(cos(ang) * p.x, p.y, -sin(ang) * p.x))
			if along:
				# round timber: grain (texture U) runs up the axis, V stays inside one board row
				uvs.append(uv0 + Vector2(run * UV_M, PLANK_ROW * (0.1 + 0.8 * float(j) / float(segments))))
			else:
				uvs.append(uv0 + Vector2(u_total * float(j) / float(segments), -run * UV_M))
			cols.append(c)
	patch(key, rows, columns, pts, uvs, cols, true)

## Flat disc (cap) facing +Y (or -Y) through `at`, mapped to a UV rectangle.
func disc(key: String, at: Vector3, radius: float, segments: int, r: Rect2, col: Color = Color.WHITE, down: bool = false) -> void:
	var sf := _surf(key)
	var base := sf.v.size()
	var n := xf.basis * (Vector3.DOWN if down else Vector3.UP)
	var t := xf.basis * Vector3.RIGHT
	var w := -1.0 if down else 1.0
	_push_vertex(sf, xf * at, n, t, w, r.get_center(), col)
	for j: int in range(segments):
		var ang := TAU * float(j) / float(segments)
		var dir := Vector3(cos(ang), 0, -sin(ang))
		_push_vertex(sf, xf * (at + dir * radius), n, t, w, r.get_center() + Vector2(cos(ang), -sin(ang) if not down else sin(ang)) * r.size * 0.5, col)
	for j: int in range(segments):
		var a := base + 1 + j
		var b := base + 1 + (j + 1) % segments
		sf.idx.append(base)
		if down:
			sf.idx.append(a)
			sf.idx.append(b)
		else:
			sf.idx.append(b)
			sf.idx.append(a)

## Round tube along a polyline (ropes, pipes, wires, rails). v_scale: UV repeats per metre along the tube.
func tube(key: String, path: PackedVector3Array, radius: float, sides: int = 5, col: Color = Color.WHITE, uv0: Vector2 = Vector2.ZERO, u_span: float = PLANK_ROW * 0.8, v_scale: float = UV_M) -> void:
	var rows := path.size()
	if rows < 2:
		return
	var columns := sides + 1
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var run := 0.0
	var prev_side := Vector3.ZERO
	for i: int in range(rows):
		var dir: Vector3
		if i == 0:
			dir = path[1] - path[0]
		elif i == rows - 1:
			dir = path[i] - path[i - 1]
		else:
			dir = path[i + 1] - path[i - 1]
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = prev_side if prev_side != Vector3.ZERO else dir.cross(Vector3.RIGHT)
		side = side.normalized()
		prev_side = side
		var up := side.cross(dir).normalized()
		if i > 0:
			run += path[i].distance_to(path[i - 1])
		for j: int in range(columns):
			var ang := TAU * float(j) / float(sides)
			pts.append(path[i] + (side * cos(ang) + up * sin(ang)) * radius)
			uvs.append(uv0 + Vector2(run * v_scale, PLANK_ROW * 0.1 + u_span * float(j) / float(sides)))
	# rows run along the tube and columns round it, so texture U follows the length (grain / strands along it)
	patch(key, rows, columns, pts, uvs, PackedColorArray([col]), true, true)

## A vertical wall rectangle with rectangular openings cut out, reveals included.
## origin = bottom-left corner seen from outside, right = unit vector to the viewer's right. openings are Rect2 in
## wall coordinates (x from the left edge, y from the base). UV: u world-scale from u0 (metres), V anchored so the
## wall base sits on the image bottom (plus v_base metres). ao_lo darkens the foot, ao_hi the strip under the eaves.
func wall(key: String, origin: Vector3, right: Vector3, width: float, height: float, openings: Array = [], u0: float = 0.0, v_base: float = 0.0, reveal: float = 0.1, ao_lo: Color = Color(0.6, 0.57, 0.52), ao_hi: Color = Color(0.74, 0.74, 0.76), foot: float = 0.5, eave: float = 0.32) -> void:
	var xs: Array[float] = [0.0, width]
	var ys: Array[float] = [0.0, height]
	if foot > 0.0 and foot < height:
		ys.append(foot)
	if eave > 0.0 and height - eave > foot:
		ys.append(height - eave)
	for o: Rect2 in openings:
		for x: float in [o.position.x, o.end.x]:
			if x > 0.001 and x < width - 0.001:
				xs.append(x)
		for y: float in [o.position.y, o.end.y]:
			if y > 0.001 and y < height - 0.001:
				ys.append(y)
	xs.sort()
	ys.sort()
	var normal := right.cross(Vector3.UP)
	for yi: int in range(ys.size() - 1):
		var y0: float = ys[yi]
		var y1: float = ys[yi + 1]
		if y1 - y0 < 0.0005:
			continue
		var c0 := _wall_ao(y0, height, foot, eave, ao_lo, ao_hi)
		var c1 := _wall_ao(y1, height, foot, eave, ao_lo, ao_hi)
		for xi: int in range(xs.size() - 1):
			var x0: float = xs[xi]
			var x1: float = xs[xi + 1]
			if x1 - x0 < 0.0005:
				continue
			var mid := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
			var hole := false
			for o: Rect2 in openings:
				if o.has_point(mid):
					hole = true
					break
			if hole:
				continue
			quad4(key, origin + right * x0 + Vector3.UP * y0, origin + right * x1 + Vector3.UP * y0, origin + right * x1 + Vector3.UP * y1, origin + right * x0 + Vector3.UP * y1,
				Vector2((u0 + x0) * UV_M, 1.0 - (v_base + y0) * UV_M), Vector2((u0 + x1) * UV_M, 1.0 - (v_base + y0) * UV_M), Vector2((u0 + x1) * UV_M, 1.0 - (v_base + y1) * UV_M), Vector2((u0 + x0) * UV_M, 1.0 - (v_base + y1) * UV_M), c0, c0, c1, c1)
	if reveal <= 0.0:
		return
	var dark := Color(0.5, 0.5, 0.5)
	var inn := -normal * reveal
	for o: Rect2 in openings:
		var bot_l := origin + right * o.position.x + Vector3.UP * o.position.y
		var bot_r := origin + right * o.end.x + Vector3.UP * o.position.y
		var top_r := origin + right * o.end.x + Vector3.UP * o.end.y
		var top_l := origin + right * o.position.x + Vector3.UP * o.end.y
		var ub := Vector2((u0 + o.position.x) * UV_M, 1.0 - (v_base + o.position.y) * UV_M)
		var rv := reveal * UV_M
		var sw := o.size.x * UV_M
		var sh := o.size.y * UV_M
		# sill (faces up), head (faces down), left jamb (faces right), right jamb (faces left)
		if o.position.y > 0.001:
			quad4(key, bot_l, bot_r, bot_r + inn, bot_l + inn, ub, ub + Vector2(sw, 0), ub + Vector2(sw, -rv), ub + Vector2(0, -rv), grey(0.85), grey(0.85), dark, dark)
		quad4(key, top_l + inn, top_r + inn, top_r, top_l, ub + Vector2(0, -sh + rv), ub + Vector2(sw, -sh + rv), ub + Vector2(sw, -sh), ub + Vector2(0, -sh), dark, dark, grey(0.6), grey(0.6))
		quad4(key, bot_l, bot_l + inn, top_l + inn, top_l, ub, ub + Vector2(rv, 0), ub + Vector2(rv, -sh), ub + Vector2(0, -sh), grey(0.75), dark, dark, grey(0.75))
		quad4(key, bot_r + inn, bot_r, top_r, top_r + inn, ub + Vector2(sw - rv, 0), ub + Vector2(sw, 0), ub + Vector2(sw, -sh), ub + Vector2(sw - rv, -sh), dark, grey(0.75), grey(0.75), dark)

func _wall_ao(y: float, height: float, foot: float, eave: float, ao_lo: Color, ao_hi: Color) -> Color:
	if foot > 0.0 and y < foot:
		return ao_lo.lerp(Color.WHITE, y / foot)
	if eave > 0.0 and y > height - eave:
		return Color.WHITE.lerp(ao_hi, (y - (height - eave)) / eave)
	return Color.WHITE

## Ground "decal" quad: flat on the terrain at height y, centred at (x, z), rotated by yaw, mapped to an atlas cell.
func decal(cell: Vector2i, x: float, z: float, size: Vector2, yaw: float, col: Color, y: float = 0.032) -> void:
	var r := cell_uv(cell, 3.0)
	var bx := Vector3(cos(yaw), 0, -sin(yaw)) * size.x * 0.5
	var bz := Vector3(sin(yaw), 0, cos(yaw)) * size.y * 0.5
	var o := Vector3(x, y, z)
	quad_rect("decal", o - bx + bz, o + bx + bz, o + bx - bz, o - bx - bz, r, col, col)

# ---------------------------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------------------------
func triangle_count() -> int:
	var total := 0
	for key: String in surfs:
		total += int((surfs[key] as Surf).idx.size() / 3.0)
	return total

## Builds one MeshInstance3D (one surface per material key used) under `parent`. Returns null when empty.
func commit(parent: Node3D, materials: Dictionary, node_name: String, shadows: bool = true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var keys: Array = surfs.keys()
	keys.sort()
	for key: String in keys:
		var sf: Surf = surfs[key]
		if sf.idx.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sf.v
		arrays[Mesh.ARRAY_NORMAL] = sf.n
		arrays[Mesh.ARRAY_TANGENT] = sf.t
		arrays[Mesh.ARRAY_TEX_UV] = sf.uv
		arrays[Mesh.ARRAY_COLOR] = sf.c
		arrays[Mesh.ARRAY_INDEX] = sf.idx
		if sf.layered: arrays[Mesh.ARRAY_TEX_UV2] = sf.uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		mesh.surface_set_name(mesh.get_surface_count() - 1, key)
	surfs.clear()
	if mesh.get_surface_count() == 0:
		return null
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
