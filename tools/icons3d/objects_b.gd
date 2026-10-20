extends RefCounted
## Icons batch B for studio.gd: the uniform, snowsuit, skis, field telephone, Sten, window, duct, stopwatch and bush
## glyphs, plus the 1958 Buenos Aires props (lamplighter's key, tram bell, newspapers, oars).
const Kit := preload("res://scripts/three_d/structures_kit.gd")
const NAMES := ["uniform", "snowsuit", "skis", "phone", "smg", "window", "duct", "clock", "hide", "lampkey", "bell",
	"papers", "oars"]

const FOLIAGE := "res://assets/tex/nature/foliage_atlas.png"
## foliage_atlas.png cells (as in nature.gd)
const UV_BROADLEAF := Rect2(0.0, 0.5, 0.5, 0.5)
const UV_SHRUB := Rect2(0.5, 0.5, 0.25, 0.25)
const UV_SMALL := Rect2(0.75, 0.75, 0.25, 0.25)
const UV_BIRCH := Rect2(0.75, 0.5, 0.25, 0.25)

## Garment bodies hanging from the hanger: rows of [height, half width, half depth] from the hem to the neck.
const TUNIC := [[0.0, 0.70, 0.30], [0.32, 0.70, 0.31], [0.72, 0.63, 0.29], [1.1, 0.67, 0.31], [1.45, 0.71, 0.32],
	[1.66, 0.72, 0.30], [1.79, 0.60, 0.26], [1.89, 0.42, 0.22], [1.95, 0.25, 0.18]]
const TUNIC_POWER := 3.2
const SMOCK := [[0.0, 0.8, 0.37], [0.28, 0.79, 0.38], [0.62, 0.72, 0.35], [0.74, 0.67, 0.33], [0.86, 0.72, 0.35],
	[1.3, 0.77, 0.38], [1.6, 0.77, 0.36], [1.75, 0.63, 0.31], [1.86, 0.45, 0.26], [1.93, 0.27, 0.21]]
const SMOCK_POWER := 2.8

# ---------------------------------------------------------------------------------------------------------------
# Materials this batch adds to the studio's set (keys prefixed b_)
# ---------------------------------------------------------------------------------------------------------------
func _b_materials(s) -> void:
	var m: Dictionary = s.mats
	if m.has("b_glass"):
		return
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.58, 0.64)
	glass.vertex_color_use_as_albedo = true
	glass.metallic = 0.3
	glass.roughness = 0.06
	glass.metallic_specular = 1.0
	m["b_glass"] = glass
	m["b_white"] = _b_cloth(_b_lightened("canvas", 0.5, 0.62), 0.95, 1.0)
	m["b_paper"] = _b_cloth(_b_lightened("canvas", 0.58, 0.5), 0.9, 0.3)
	m["b_leather"] = _b_cloth(load(Kit.TEX_DIR + "canvas_a.png"), 0.5, 0.5)
	var enamel := StandardMaterial3D.new()
	enamel.vertex_color_use_as_albedo = true
	enamel.roughness = 0.22
	enamel.metallic_specular = 0.7
	m["b_enamel"] = enamel
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.07, 0.07, 0.08)
	ink.vertex_color_use_as_albedo = true
	ink.roughness = 0.4
	ink.metallic = 0.3
	m["b_ink"] = ink
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.9, 0.7, 0.4)
	brass.vertex_color_use_as_albedo = true
	brass.metallic = 0.95
	brass.roughness = 0.17
	brass.normal_enabled = true
	brass.normal_texture = load(Kit.TEX_DIR + "steel_n.png")
	brass.normal_scale = 0.12
	m["b_brass"] = brass
	var sheet := StandardMaterial3D.new()
	sheet.albedo_texture = _b_newsprint()
	sheet.vertex_color_use_as_albedo = true
	sheet.roughness = 0.92
	sheet.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m["b_print"] = sheet
	var leaf := StandardMaterial3D.new()
	leaf.albedo_texture = load(FOLIAGE)
	leaf.vertex_color_use_as_albedo = true
	leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf.alpha_scissor_threshold = 0.4
	leaf.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	leaf.roughness = 0.92
	leaf.metallic_specular = 0.15
	leaf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m["b_leaf"] = leaf
	var core: StandardMaterial3D = leaf.duplicate()
	core.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m["b_leafcore"] = core

func _b_cloth(albedo: Texture2D, roughness: float, normal_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.vertex_color_use_as_albedo = true
	m.normal_enabled = true
	m.normal_texture = load(Kit.TEX_DIR + "canvas_n.png")
	m.normal_scale = normal_scale
	m.roughness = roughness
	m.metallic_specular = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## A kit texture desaturated and lifted toward white (white cloth, newsprint): v' = base + gain * luminance.
func _b_lightened(key: String, base: float, gain: float) -> ImageTexture:
	var img: Image = (load(Kit.TEX_DIR + key + "_a.png") as Texture2D).get_image()
	img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			var v := minf(1.0, base + gain * l)
			img.set_pixel(x, y, Color(v, v * 0.99, v * 0.95))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The top sheet of a folded newspaper: masthead blocks, rules, headline bars, four columns of grey lines and a
## photograph. Nothing readable.
func _b_newsprint() -> ImageTexture:
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.91, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	var dark := Color(0.3, 0.3, 0.3)
	var mid := Color(0.5, 0.5, 0.49)
	var faint := Color(0.68, 0.68, 0.66)
	var x := 70
	while x < 440:
		var w := rng.randi_range(16, 32)
		img.fill_rect(Rect2i(x, 28 + rng.randi_range(0, 4), w, 44), dark)
		x += w + rng.randi_range(5, 9)
	img.fill_rect(Rect2i(24, 90, 464, 4), dark)
	img.fill_rect(Rect2i(24, 98, 464, 2), dark)
	img.fill_rect(Rect2i(24, 112, 330, 15), mid)
	img.fill_rect(Rect2i(24, 133, 250, 15), mid)
	var gap := 12
	var cw := int((464 - gap * 3) / 4.0)
	for c: int in range(4):
		var x0 := 24 + c * (cw + gap)
		if c > 0:
			img.fill_rect(Rect2i(x0 - 6, 160, 1, 340), faint)
		var y := 162
		if c == 2:
			# a photograph across the two right-hand columns
			img.fill_rect(Rect2i(x0, y, cw * 2 + gap, 120), Color(0.56, 0.56, 0.55))
			img.fill_rect(Rect2i(x0, y + 70, cw * 2 + gap, 50), Color(0.42, 0.42, 0.41))
			img.fill_rect(Rect2i(x0 + 40, y + 30, 46, 70), Color(0.33, 0.33, 0.33))
			img.fill_rect(Rect2i(x0 + 120, y + 18, 60, 52), Color(0.68, 0.68, 0.66))
		if c >= 2:
			y += 128
		while y < 496:
			var length := cw if rng.randf() > 0.12 else rng.randi_range(int(cw / 3.0), cw - 10)
			img.fill_rect(Rect2i(x0, y, length, 2), faint)
			y += 6
			if rng.randf() < 0.05:
				y += 6
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------------------------------------------
static func _b_mul(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

## Closed superellipse loop, counter-clockwise: power 2 = ellipse, higher = squarer. ripple adds `waves` folds.
static func _b_loop(n: int, power: float = 2.0, ripple: float = 0.0, waves: int = 0, phase: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in range(n):
		var a := TAU * float(i) / float(n)
		var c := cos(a)
		var s := sin(a)
		var p := Vector2(signf(c) * pow(absf(c), 2.0 / power), signf(s) * pow(absf(s), 2.0 / power))
		out.append(p * (1.0 + ripple * sin(a * float(waves) + phase)))
	return out

## Every point twice: hard edges at each corner of a swept section.
static func _b_crisp(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(p)
		out.append(p)
	return out

## Frame with +X running from a toward b and +Y as close to `up` as it can be.
static func _b_along(a: Vector3, b: Vector3, up: Vector3 = Vector3.UP) -> Transform3D:
	var x := (b - a).normalized()
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x, y, z), a)

## A solid swept along `path`: the closed counter-clockwise loop `section` (x across, y up) is scaled by sizes[i]
## and stood in a frame whose up leans toward ups[i]. One entry in sizes / ups / cols serves every station.
## grain: planks UVs (texture U along the path inside one board row); otherwise world-scale UVs.
func _b_sweep(k: Kit, key: String, path: PackedVector3Array, section: PackedVector2Array, sizes: Array, ups: Array, cols: Array, caps: bool = true, grain: bool = false, closed: bool = false, uv0: Vector2 = Vector2.ZERO) -> void:
	var rows := path.size()
	var n := section.size()
	var columns := n + 1
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var run := 0.0
	for i: int in range(rows):
		var t: Vector3
		if closed and (i == 0 or i == rows - 1):
			t = path[1] - path[rows - 2]
		elif i == 0:
			t = path[1] - path[0]
		elif i == rows - 1:
			t = path[i] - path[i - 1]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		var up: Vector3 = ups[i] if ups.size() == rows else ups[0]
		var side := up.cross(t)
		if side.length_squared() < 1e-8:
			side = Vector3.BACK.cross(t)
		side = side.normalized()
		var u2 := t.cross(side).normalized()
		if i > 0:
			run += path[i].distance_to(path[i - 1])
		var sz: Vector2 = sizes[i] if sizes.size() == rows else sizes[0]
		var col: Color = cols[i] if cols.size() == rows else cols[0]
		var per := 0.0
		for j: int in range(columns):
			var q := section[j % n]
			if j > 0:
				per += ((section[j % n] - section[j - 1]) * sz).length()
			pts.append(path[i] + side * q.x * sz.x + u2 * q.y * sz.y)
			if grain:
				uvs.append(uv0 + Vector2(run * Kit.UV_M, Kit.PLANK_ROW * (0.1 + 0.8 * float(j) / float(n))))
			else:
				uvs.append(uv0 + Vector2(run * Kit.UV_M, per * Kit.UV_M))
			colours.append(col)
	k.patch(key, rows, columns, pts, uvs, colours, true)
	if not caps or closed:
		return
	for e: int in [0, rows - 1]:
		var centre := path[e]
		var col: Color = cols[e] if cols.size() == rows else cols[0]
		col = _b_mul(col, 0.8)
		for j: int in range(n):
			var a := pts[e * columns + j]
			var b := pts[e * columns + j + 1]
			var ua := uvs[e * columns + j]
			if e == 0:
				k.tri(key, centre, b, a, ua, ua, ua, col, col, col)
			else:
				k.tri(key, centre, a, b, ua, ua, ua, col, col, col)

## A small domed button facing +Z at `at` (in the current frame).
func _b_button(k: Kit, at: Vector3, r: float, key: String = "paint", col: Color = Color(0.5, 0.52, 0.48)) -> void:
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at))
	k.lathe(key, Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.006), Vector2(r, -0.006), Vector2(r, 0.006), Vector2(r * 0.75, 0.017), Vector2(0.0, 0.021)]), 14, _b_mul(col, 0.75), col)
	k.pop()

## Ball (round lathe) of radius r centred at `at`.
func _b_ball(k: Kit, key: String, at: Vector3, r: float, lo: Color, hi: Color, segments: int = 14) -> void:
	var prof := PackedVector2Array()
	for i: int in range(9):
		var a := -PI * 0.5 + PI * float(i) / 8.0
		prof.append(Vector2(cos(a) * r, sin(a) * r))
	prof[0] = Vector2(0.0, -r)
	prof[8] = Vector2(0.0, r)
	k.lathe(key, at, prof, segments, lo, hi)

## Rounded rectangle loop (half sizes hx, hy, corner radius r) in 2D, counter-clockwise from the bottom middle.
static func _b_rounded_rect(hx: float, hy: float, r: float, steps: int = 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [Vector2(hx - r, -hy + r), Vector2(hx - r, hy - r), Vector2(-hx + r, hy - r), Vector2(-hx + r, -hy + r)]
	var start := [-PI * 0.5, 0.0, PI * 0.5, PI]
	out.append(Vector2(0.0, -hy))
	for c: int in range(4):
		var o: Vector2 = corners[c]
		for i: int in range(steps + 1):
			var a: float = start[c] + PI * 0.5 * float(i) / float(steps)
			out.append(o + Vector2(cos(a), sin(a)) * r)
	out.append(Vector2(0.0, -hy))
	return out

# ---------------------------------------------------------------------------------------------------------------
# Garments on a hanger
# ---------------------------------------------------------------------------------------------------------------
static func _b_station(st: Array, y: float) -> Vector2:
	for i: int in range(st.size() - 1):
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if y <= float(b[0]):
			var t := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = st[st.size() - 1]
	return Vector2(last[1], last[2])

## The front surface's z at (x, y) on a body built by _body.
static func _b_front(st: Array, x: float, y: float, power: float) -> float:
	var wd := _b_station(st, y)
	var u := clampf(absf(x) / wd.x, 0.0, 1.0)
	return wd.y * pow(maxf(1.0 - pow(u, power), 0.0), 1.0 / power)

## Height of the shoulder ridge at |x| (where the body's half width equals x above the chest).
static func _b_shoulder(st: Array, x: float) -> float:
	for i: int in range(st.size() - 1, 0, -1):
		var hi: Array = st[i]
		var lo: Array = st[i - 1]
		if float(lo[1]) >= x and float(hi[1]) <= x:
			var t := (x - float(hi[1])) / maxf(float(lo[1]) - float(hi[1]), 1e-4)
			return lerpf(hi[0], lo[0], t)
	return float(st[st.size() - 1][0])

## The body: a superellipse tube from the hem up to the neck, the neck closed by a shadowed cap.
func _b_body(k: Kit, key: String, st: Array, power: float, col: Color, ripple: float, waves: int) -> void:
	var path := PackedVector3Array()
	var sizes := []
	var cols := []
	var top: float = st[st.size() - 1][0]
	for row: Array in st:
		path.append(Vector3(0.0, row[0], 0.0))
		sizes.append(Vector2(row[1], row[2]))
		var h: float = float(row[0]) / top
		cols.append(_b_mul(col, lerpf(0.66, 1.0, minf(1.0, h * 1.3))))
	_b_sweep(k, key, path, _b_loop(56, power, ripple, waves, PI * 0.5), sizes, [Vector3.BACK], cols, false)
	var last: Array = st[st.size() - 1]
	k.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, float(last[2]) / float(last[1]))), Vector3(0.0, float(last[0]) - 0.005, 0.0)))
	k.disc(key, Vector3.ZERO, last[1], 24, Rect2(0, 0, 0.3, 0.3), _b_mul(col, 0.3))
	k.pop()

## Sleeves hanging from the shoulders, a little away from the body, cuffs closed.
func _b_sleeves(k: Kit, key: String, col: Color, top: float, r0: float, r1: float, ripple: float, out: float, length: float) -> void:
	for sx: float in [1.0, -1.0]:
		var path := PackedVector3Array([Vector3(0.5 * sx, top, 0.0), Vector3(0.66 * sx, top - 0.1, 0.0), Vector3((0.76 + out * 0.3) * sx, top - 0.45, 0.02), Vector3((0.82 + out * 0.65) * sx, top - length * 0.7, 0.04), Vector3((0.86 + out) * sx, top - length, 0.05)])
		var sizes := [Vector2(r0, r0), Vector2(r0 * 1.12, r0 * 1.08), Vector2(r0 * 1.04, r0), Vector2(r1 * 1.05, r1), Vector2(r1, r1)]
		var cols := [col, col, _b_mul(col, 0.92), _b_mul(col, 0.8), _b_mul(col, 0.7)]
		_b_sweep(k, key, path, _b_loop(28, 2.3, ripple, 5), sizes, [Vector3.BACK], cols, true)

## A band collar round the neck, a little lower in front and flaring out at the top.
func _b_collar(k: Kit, key: String, rx: float, rz: float, y: float, h: float, col: Color, thick: float = 0.04, flare: float = 0.025) -> void:
	var path := PackedVector3Array()
	var n := 40
	for i: int in range(n + 1):
		var a := TAU * float(i) / float(n)
		path.append(Vector3(cos(a) * rx, y - 0.035 * maxf(sin(a), 0.0), sin(a) * rz))
	var sec := _b_crisp(PackedVector2Array([Vector2(-thick * 0.5, 0.0), Vector2(thick * 0.5, 0.0), Vector2(thick * 0.5 + flare, h), Vector2(-thick * 0.5 + flare, h)]))
	_b_sweep(k, key, path, sec, [Vector2.ONE], [Vector3.UP], [col], false, false, true)

## A patch pocket with a pointed flap and a button, on the body's front at (x, y).
func _b_pocket(k: Kit, key: String, st: Array, power: float, at: Vector2, size: Vector2, col: Color, button_col: Color) -> void:
	var z := _b_front(st, at.x, at.y, power)
	var slope := (_b_front(st, at.x + 0.01, at.y, power) - _b_front(st, at.x - 0.01, at.y, power)) / 0.02
	k.push(Transform3D(Basis(Vector3.UP, atan(-slope)), Vector3(at.x, at.y, z)))
	k.box(key, Vector3(0.0, 0.0, 0.006), Vector3(size.x, size.y, 0.03), _b_mul(col, 0.8), col)
	var top := size.y * 0.5
	var fw := size.x + 0.03
	k.box(key, Vector3(0.0, top - 0.04, 0.02), Vector3(fw, 0.1, 0.03), _b_mul(col, 0.72), _b_mul(col, 1.04))
	var zf := 0.0351
	k.tri(key, Vector3(fw * 0.5, top - 0.09, zf), Vector3(-fw * 0.5, top - 0.09, zf), Vector3(0.0, top - 0.14, zf), Vector2.ZERO, Vector2(0.1, 0), Vector2(0.05, 0.05), _b_mul(col, 0.8), _b_mul(col, 0.8), _b_mul(col, 0.7))
	_b_button(k, Vector3(0.0, top - 0.085, 0.036), 0.03, "paint", button_col)
	k.pop()

## The wooden hanger's neck inside the collar and its steel hook rising out of it.
func _b_hanger(k: Kit, y: float, z: float, rise: float) -> void:
	k.beam("planks", Vector3(-0.2, y - 0.03, 0.0), Vector3(0.2, y - 0.03, 0.0), 0.09, 0.06, Color(0.6, 0.43, 0.3), Color(0.8, 0.6, 0.42))
	var path := PackedVector3Array([Vector3(0.0, y - 0.03, 0.0), Vector3(0.0, y + 0.02, z * 0.5), Vector3(0.0, y + 0.1, z), Vector3(0.0, y + rise * 0.5, z), Vector3(0.0, y + rise, z)])
	var r := 0.13
	var c := Vector3(r, y + rise, z)
	for i: int in range(1, 19):
		var a := PI - (PI + 0.8) * float(i) / 18.0
		path.append(c + Vector3(cos(a), sin(a), 0.0) * r)
	k.tube("blade", path, 0.021, 8, Color(0.82, 0.82, 0.84))
	_b_ball(k, "blade", path[path.size() - 1], 0.027, Color(0.7, 0.7, 0.72), Color(0.9, 0.9, 0.92), 10)
	# the brass ferrule where the hook leaves the wood
	k.lathe("brass", Vector3(0.0, y - 0.01, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.03), Vector2(0.026, 0.05), Vector2(0.0, 0.05)]), 12, Color(0.7, 0.7, 0.7), Color(1, 1, 1))

## The enemy's field tunic: field grey, dark green collar, five buttons, four pleated pockets with pointed flaps,
## plain shoulder straps. No insignia.
func _uniform(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var grey := Color(0.72, 0.77, 0.79)
	var button := Color(0.55, 0.58, 0.52)
	_b_body(k, "canvas", TUNIC, TUNIC_POWER, grey, 0.008, 9)
	_b_sleeves(k, "canvas", grey, 1.64, 0.15, 0.13, 0.012, 0.03, 1.28)
	_b_collar(k, "canvas", 0.265, 0.2, 1.9, 0.16, Color(0.36, 0.48, 0.42))
	# the front opening: a placket down the middle and its buttons
	for i: int in range(TUNIC.size() - 2):
		var a: Array = TUNIC[i]
		var b: Array = TUNIC[i + 1]
		k.beam("canvas", Vector3(0.0, a[0], float(a[2]) + 0.004), Vector3(0.0, b[0], float(b[2]) + 0.004), 0.085, 0.012, _b_mul(grey, 0.8), _b_mul(grey, 0.92), Vector2.ZERO, false, Vector3.BACK)
	for y: float in [0.3, 0.64, 0.98, 1.32, 1.66]:
		_b_button(k, Vector3(0.0, y, _b_front(TUNIC, 0.0, y, TUNIC_POWER) + 0.01), 0.038, "paint", button)
	for sx: float in [1.0, -1.0]:
		_b_pocket(k, "canvas", TUNIC, TUNIC_POWER, Vector2(0.34 * sx, 1.3), Vector2(0.28, 0.3), grey, button)
		_b_pocket(k, "canvas", TUNIC, TUNIC_POWER, Vector2(0.38 * sx, 0.36), Vector2(0.36, 0.42), grey, button)
		# shoulder strap along the ridge, buttoned by the collar
		var x0 := 0.3
		var x1 := 0.6
		k.beam("canvas", Vector3(x0 * sx, _b_shoulder(TUNIC, x0) + 0.012, 0.0), Vector3(x1 * sx, _b_shoulder(TUNIC, x1) + 0.012, 0.0), 0.12, 0.024, _b_mul(grey, 0.85), grey)
	_b_hanger(k, 1.93, 0.0, 0.32)
	s._commit(k, parent)
	return {"pitch": 12.0, "yaw": 0.0, "margin": 0.05}

## A point on the hood's shell: an ellipsoid round the polar axis +Z (the face opening), its lower half flaring out
## over the shoulders and its crown drawn up into a soft peak at the back.
static func _b_hood_point(c: Vector3, r: Vector3, al: float, be: float, scale: float) -> Vector3:
	var d := Vector3(sin(al) * cos(be), sin(al) * sin(be), cos(al))
	var low := maxf(-d.y, 0.0)
	var p := Vector3(d.x * r.x * (1.0 + 0.55 * low * low), d.y * r.y, d.z * r.z * (1.0 + 0.25 * low * low))
	p.y -= 0.1 * low * low
	var crown := maxf(d.y, 0.0)
	p.y += 0.07 * pow(crown, 4.0) * clampf(0.5 - d.z, 0.0, 1.0)
	return c + p * scale

## The hood up as if round a head: cloth outside, shadow inside, a rolled hem round the face opening.
func _b_hood(k: Kit, key: String, c: Vector3, r: Vector3, col: Color, inside: Color, open_deg: float = 55.0) -> void:
	var rows := 14
	var columns := 33
	var a0 := deg_to_rad(open_deg)
	for shell: int in range(2):
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colours := PackedColorArray()
		var scale := 1.0 if shell == 0 else 0.9
		for i: int in range(rows):
			var al := lerpf(a0, PI, float(i) / float(rows - 1))
			for j: int in range(columns):
				var be := TAU * float(j) / float(columns - 1)
				pts.append(_b_hood_point(c, r, al, be, scale))
				uvs.append(Vector2(be * 0.3, al * 0.3))
				var up := sin(al) * sin(be)
				if shell == 0:
					colours.append(_b_mul(col, lerpf(0.7, 1.0, 0.5 + 0.5 * up)))
				else:
					colours.append(_b_mul(inside, lerpf(1.0, 0.35, minf(1.0, float(i) / float(rows - 1) * 1.6))))
		k.patch(key, rows, columns, pts, uvs, colours, true, shell == 0)
	var hem := PackedVector3Array()
	for j: int in range(columns):
		hem.append(_b_hood_point(c, r, a0, TAU * float(j) / float(columns - 1), 0.95))
	k.tube(key, hem, r.x * 0.08, 8, _b_mul(col, 0.95))

## A white snow smock: loose, hooded, drawn in at the waist, with big patch pockets.
func _snowsuit(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var white := Color(0.95, 0.97, 1.0)
	var button := Color(0.8, 0.8, 0.78)
	_b_body(k, "b_white", SMOCK, SMOCK_POWER, white, 0.03, 11)
	_b_sleeves(k, "b_white", white, 1.62, 0.17, 0.155, 0.045, 0.05, 1.3)
	_b_hood(k, "b_white", Vector3(0.0, 2.13, -0.1), Vector3(0.36, 0.36, 0.34), white, Color(0.36, 0.38, 0.42), 50.0)
	for sx: float in [1.0, -1.0]:
		_b_pocket(k, "b_white", SMOCK, SMOCK_POWER, Vector2(0.4 * sx, 0.34), Vector2(0.42, 0.44), white, button)
		_b_pocket(k, "b_white", SMOCK, SMOCK_POWER, Vector2(0.33 * sx, 1.3), Vector2(0.3, 0.32), white, button)
	# the waist drawcord and its two ends hanging in front with toggles
	var cord := PackedVector3Array()
	var wd := _b_station(SMOCK, 0.74)
	for i: int in range(33):
		var a := TAU * float(i) / 32.0
		cord.append(Vector3(cos(a) * wd.x * 1.02, 0.74, sin(a) * wd.y * 1.03))
	k.tube("b_white", cord, 0.016, 6, Color(0.8, 0.82, 0.86))
	for sx: float in [1.0, -1.0]:
		var z0 := _b_front(SMOCK, 0.06, 0.74, SMOCK_POWER) + 0.02
		var end := Vector3(0.1 * sx, 0.52, z0 + 0.03)
		k.tube("b_white", PackedVector3Array([Vector3(0.05 * sx, 0.74, z0), Vector3(0.08 * sx, 0.64, z0 + 0.02), end]), 0.014, 6, Color(0.8, 0.82, 0.86))
		k.lathe("rubber", end - Vector3(0, 0.07, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.03, 0.035), Vector2(0.026, 0.07), Vector2(0.0, 0.07)]), 10, Color(0.5, 0.5, 0.5), Color(0.7, 0.7, 0.7))
	# the short buttoned neck opening
	for i: int in range(3):
		var y0 := 1.5 + 0.12 * float(i)
		k.beam("b_white", Vector3(0.0, y0, _b_front(SMOCK, 0.0, y0, SMOCK_POWER) + 0.004), Vector3(0.0, y0 + 0.12, _b_front(SMOCK, 0.0, y0 + 0.12, SMOCK_POWER) + 0.004), 0.08, 0.012, _b_mul(white, 0.78), _b_mul(white, 0.9), Vector2.ZERO, false, Vector3.BACK)
	for y: float in [1.56, 1.72]:
		_b_button(k, Vector3(0.0, y, _b_front(SMOCK, 0.0, y, SMOCK_POWER) + 0.012), 0.03, "paint", button)
	_b_hanger(k, 1.92, 0.16, 0.56)
	s._commit(k, parent)
	return {"pitch": 12.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Skis and poles
# ---------------------------------------------------------------------------------------------------------------
## One old wooden ski along +X from its tail at the origin, bottom on y = 0, the tip curling up; toe irons, a
## leather toe strap, a heel strap and a ribbed foot plate.
func _b_ski(k: Kit, wood: Color) -> void:
	var length := 2.2
	var s0 := length * 0.8
	var bend := 0.42
	var path := PackedVector3Array()
	var sizes := []
	var cols := []
	var ts := []
	for i: int in range(19):
		ts.append(0.9 * float(i) / 18.0)
	for i: int in range(1, 9):
		ts.append(0.9 + 0.1 * sin(PI * 0.5 * float(i) / 8.0))
	for t: float in ts:
		var sl := length * t
		var p := Vector3(sl, 0.0, 0.0)
		if sl > s0:
			var th := (sl - s0) / bend
			p = Vector3(s0 + bend * sin(th), bend * (1.0 - cos(th)), 0.0)
		var w := lerpf(0.085, 0.074, clampf(t / 0.5, 0.0, 1.0))
		if t > 0.5:
			w = lerpf(0.074, 0.09, clampf((t - 0.5) / 0.33, 0.0, 1.0))
		if t > 0.9:
			w = 0.09 * sqrt(maxf(1.0 - pow((t - 0.9) / 0.1, 2.0), 0.0)) + 0.004
		var h := 0.022 if t < 0.85 else lerpf(0.022, 0.009, (t - 0.85) / 0.15)
		if t < 0.05:
			h = lerpf(0.016, 0.022, t / 0.05)
		path.append(p + Vector3(0.0, 0.022, 0.0))
		sizes.append(Vector2(w, h))
		cols.append(_b_mul(wood, lerpf(0.82, 1.0, t)))
	_b_sweep(k, "planks", path, _b_loop(20, 7.0), sizes, [Vector3.UP], cols, true, true)
	var leather := Color(0.42, 0.27, 0.17)
	var iron := Color(0.62, 0.62, 0.64)
	var toe := 1.06
	var top := 0.044
	# foot plate
	k.box("rubber", Vector3(toe - 0.2, top + 0.004, 0.0), Vector3(0.34, 0.008, 0.12), Color(0.45, 0.4, 0.36), Color(0.55, 0.5, 0.45))
	# toe irons on both edges
	for sz: float in [1.0, -1.0]:
		k.box("blued", Vector3(toe, top + 0.03, sz * 0.085), Vector3(0.14, 0.07, 0.012), _b_mul(iron, 0.7), iron)
	# toe strap arching over the boot's place
	var arch := PackedVector3Array()
	var ups := []
	for i: int in range(11):
		var a := PI * float(i) / 10.0
		arch.append(Vector3(toe, top + 0.045 + 0.06 * sin(a), 0.09 * cos(a)))
		ups.append(Vector3(0.0, sin(a), cos(a)))
	_b_sweep(k, "b_leather", arch, _b_crisp(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])), [Vector2(0.035, 0.008)], ups, [leather], true)
	# heel strap: a loop lying back from the irons round the heel
	var heel := PackedVector3Array()
	for i: int in range(13):
		var a := PI * 0.5 + PI * float(i) / 12.0
		heel.append(Vector3(toe - 0.3 + 0.12 * cos(a) * (1.0 if cos(a) < 0.0 else 0.0), top + 0.05 + 0.02 * absf(cos(a)), 0.09 * sin(a)))
	heel.insert(0, Vector3(toe - 0.04, top + 0.05, 0.095))
	heel.append(Vector3(toe - 0.04, top + 0.05, -0.095))
	_b_sweep(k, "b_leather", heel, _b_crisp(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])), [Vector2(0.007, 0.022)], [Vector3.UP], [_b_mul(leather, 0.9)], true)

## A bamboo ski pole along +X from the grip at the origin (axis on y = 0): leather grip and wrist loop, a cane
## basket on leather spokes, a steel spike.
func _b_pole(k: Kit, length: float) -> void:
	var bamboo := Color(1.0, 0.86, 0.58)
	var leather := Color(0.45, 0.29, 0.18)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.021, 0.0)])
	var node := 0.36
	while node < length - 0.25:
		prof.append(Vector2(0.021, node - 0.014))
		prof.append(Vector2(0.026, node))
		prof.append(Vector2(0.021, node + 0.014))
		node += 0.32
	prof.append(Vector2(0.019, length - 0.1))
	prof.append(Vector2(0.0, length - 0.095))
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
	k.lathe("planks", Vector3.ZERO, prof, 10, _b_mul(bamboo, 0.8), bamboo, Vector2(0.3, 0.0), PackedFloat32Array(), -1.0, true)
	k.lathe("b_leather", Vector3(0.0, -0.012, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.034, 0.02), Vector2(0.033, 0.28), Vector2(0.024, 0.3), Vector2(0.021, 0.31)]), 12, _b_mul(leather, 0.8), leather)
	k.lathe("blade", Vector3(0.0, length - 0.11, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.023, 0.0), Vector2(0.023, 0.04), Vector2(0.012, 0.1), Vector2(0.0, 0.17)]), 10, Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95))
	k.pop()
	# basket: a cane ring on four leather spokes
	var xb := length - 0.2
	var ring := PackedVector3Array()
	for i: int in range(25):
		var a := TAU * float(i) / 24.0
		ring.append(Vector3(xb, cos(a) * 0.125, sin(a) * 0.125))
	k.tube("planks", ring, 0.013, 6, Color(0.85, 0.66, 0.42), Vector2(0.1, 0.0))
	for i: int in range(4):
		var a := PI * 0.25 + PI * 0.5 * float(i)
		var d := Vector3(0.0, cos(a), sin(a))
		k.beam("b_leather", Vector3(xb, 0.0, 0.0) + d * 0.015, Vector3(xb, 0.0, 0.0) + d * 0.122, 0.024, 0.007, leather, leather, Vector2.ZERO, false, Vector3.RIGHT)
	# wrist loop lying beside the grip
	var loop := PackedVector3Array([Vector3(0.05, 0.0, -0.022)])
	for i: int in range(17):
		var a := -PI * 0.8 + PI * 1.6 * float(i) / 16.0
		loop.append(Vector3(-0.1 - 0.1 * cos(a), -0.01, 0.075 * sin(a)))
	loop.append(Vector3(0.05, 0.0, 0.022))
	_b_sweep(k, "b_leather", loop, _b_crisp(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])), [Vector2(0.016, 0.005)], [Vector3.UP], [_b_mul(leather, 0.9)], true)

func _skis(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var cross := 1.42
	var spread := deg_to_rad(38.0)
	var woods := [Color(0.8, 0.56, 0.4), Color(0.75, 0.52, 0.38)]
	for i: int in range(2):
		# tails toward the viewer, tips away to either side, crossing between the bindings and the tips
		var side := 1.0 if i == 0 else -1.0
		var dir := Vector3(side * cos(spread), 0.0, -sin(spread))
		var tail := -dir * cross
		var rise := 0.0 if i == 0 else 0.044 / cross
		k.push(_b_along(tail, tail + dir + Vector3.UP * rise))
		_b_ski(k, woods[i])
		k.pop()
	# the poles lie together across the crossing, baskets toward the viewer
	var plen := 1.95
	for i: int in range(2):
		var x := -0.08 + 0.15 * float(i)
		var grip := Vector3(x - 0.05 + 0.1 * float(i), 0.12, -0.95)
		var basket := Vector3(x + 0.05 - 0.06 * float(i), 0.125, 0.95)
		k.push(_b_along(grip, basket))
		_b_pole(k, plen)
		k.pop()
	s._commit(k, parent)
	return {"pitch": 50.0, "yaw": 0.0, "margin": 0.04}

# ---------------------------------------------------------------------------------------------------------------
# Field telephone
# ---------------------------------------------------------------------------------------------------------------
func _phone(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-26.0)), Vector3.ZERO))
	var leather := Color(0.52, 0.31, 0.18)
	var bakelite := Color(0.16, 0.15, 0.14)
	var hw := 0.5
	var hd := 0.3
	var hh := 0.21
	# the case: a leather box with soft edges
	var path := PackedVector3Array([Vector3(-hw, hh, 0.0), Vector3(hw, hh, 0.0)])
	_b_sweep(k, "b_leather", path, _b_loop(36, 7.0), [Vector2(hd, hh)], [Vector3.UP], [leather], true)
	# stitched welts round the ends
	for x: float in [-hw + 0.02, hw - 0.02]:
		_b_sweep(k, "b_leather", PackedVector3Array([Vector3(x - 0.012, hh, 0.0), Vector3(x + 0.012, hh, 0.0)]), _b_loop(36, 7.0), [Vector2(hd + 0.008, hh + 0.008)], [Vector3.UP], [_b_mul(leather, 0.8)], true)
	# the instrument panel inside the open top
	k.box("paint", Vector3(0.0, hh * 2.0 + 0.002, 0.0), Vector3(hw * 2.0 - 0.1, 0.012, hd * 2.0 - 0.08), bakelite, _b_mul(bakelite, 1.3))
	# the lid, open and leaning back on its hinge
	k.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-106.0)), Vector3(0.0, hh * 2.0, -hd)))
	_b_sweep(k, "b_leather", PackedVector3Array([Vector3(-hw - 0.01, 0.045, hd + 0.01), Vector3(hw + 0.01, 0.045, hd + 0.01)]), _b_loop(36, 6.0), [Vector2(hd + 0.012, 0.045)], [Vector3.UP], [_b_mul(leather, 0.9)], true, false, false, Vector2(0.37, 0.21))
	# the lid's lining, a shade lighter
	k.box("b_leather", Vector3(0.0, -0.002, hd + 0.01), Vector3(hw * 2.0 - 0.06, 0.006, hd * 2.0 - 0.06), _b_mul(leather, 0.95), _b_mul(leather, 0.95))
	k.pop()
	# the buckle on the case front
	var zf := hd + 0.004
	k.box("b_leather", Vector3(0.0, hh * 1.25, zf), Vector3(0.11, 0.26, 0.012), _b_mul(leather, 0.65), _b_mul(leather, 0.8))
	for r: Array in [[Vector3(0.0, hh * 1.5 + 0.045, zf + 0.012), Vector3(0.15, 0.018, 0.016)], [Vector3(0.0, hh * 1.5 - 0.045, zf + 0.012), Vector3(0.15, 0.018, 0.016)], [Vector3(0.066, hh * 1.5, zf + 0.012), Vector3(0.018, 0.09, 0.016)], [Vector3(-0.066, hh * 1.5, zf + 0.012), Vector3(0.018, 0.09, 0.016)]]:
		k.box("brass", r[0], r[1], Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	# cradle forks
	var top := hh * 2.0 + 0.008
	var hz := 0.02
	for x: float in [-0.2, 0.2]:
		for dz: float in [-0.07, 0.07]:
			k.box("paint", Vector3(x, top + 0.04, hz + dz), Vector3(0.04, 0.08, 0.025), bakelite, _b_mul(bakelite, 1.4))
		k.box("paint", Vector3(x, top + 0.008, hz), Vector3(0.05, 0.016, 0.16), bakelite, _b_mul(bakelite, 1.3))
	# the handset across the cradle: a handle with the receiver and transmitter cups at its ends
	var hy := top + 0.1
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.33, hy, hz)))
	k.lathe("paint", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.046, 0.08), Vector2(0.046, 0.58), Vector2(0.04, 0.66), Vector2(0.0, 0.66)]), 16, _b_mul(bakelite, 0.8), _b_mul(bakelite, 1.2))
	k.pop()
	k.box("paint", Vector3(-0.05, hy + 0.045, hz), Vector3(0.09, 0.02, 0.05), Color(0.3, 0.3, 0.3), Color(0.4, 0.4, 0.4))
	for e: Array in [[0.34, 0.11], [-0.34, 0.1]]:
		var x: float = e[0]
		var r: float = e[1]
		k.lathe("paint", Vector3(x, top + 0.005, hz), PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.85, 0.0), Vector2(r, 0.02), Vector2(r * 1.02, 0.07), Vector2(r * 0.85, 0.12), Vector2(r * 0.45, 0.15), Vector2(0.0, 0.155)]), 24, _b_mul(bakelite, 0.7), _b_mul(bakelite, 1.4))
	# the cord from the transmitter end down into the panel
	k.tube("rubber", PackedVector3Array([Vector3(-0.42, top + 0.06, hz - 0.06), Vector3(-0.44, top + 0.04, hz - 0.13), Vector3(-0.42, top + 0.02, hz - 0.2), Vector3(-0.36, top + 0.01, hz - 0.23)]), 0.016, 6, Color(0.35, 0.3, 0.26))
	# line terminals: two brass posts
	for x: float in [0.3, 0.4]:
		k.lathe("brass", Vector3(x, top, -0.19), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.02), Vector2(0.015, 0.025), Vector2(0.015, 0.05), Vector2(0.032, 0.055), Vector2(0.032, 0.075), Vector2(0.0, 0.08)]), 6, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	# the generator crank on the right end: boss, arm, knob
	var bx := hw
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(bx, hh, 0.04)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.03), Vector2(0.045, 0.05), Vector2(0.045, 0.07), Vector2(0.0, 0.07)]), 18, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
	k.pop()
	var tip := Vector3(bx + 0.08, hh - 0.2, 0.17)
	k.beam("blued", Vector3(bx + 0.06, hh, 0.04), tip, 0.04, 0.02, Color(0.6, 0.6, 0.62), Color(0.8, 0.8, 0.82), Vector2.ZERO, false, Vector3.RIGHT)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), tip + Vector3(0.0, 0.0, 0.0)))
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.036, 0.04), Vector2(0.034, 0.12), Vector2(0.024, 0.14), Vector2(0.0, 0.142)]), 12, Color(0.35, 0.22, 0.15), Color(0.5, 0.32, 0.2), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 30.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Sten
# ---------------------------------------------------------------------------------------------------------------
## The Sten Mk II on its right side, magazine up: tube receiver, barrel nut and barrel, side magazine, trigger
## housing, skeleton stock of welded rod with a flat butt plate. Built along +X (muzzle) with the gun's top on +Y
## and its left on +Z, then laid down.
func _smg(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.06, 0.0)))
	var lo := Color(0.55, 0.55, 0.58)
	var hi := Color(0.85, 0.85, 0.88)
	var r := 0.052
	# receiver tube with its end cap, the barrel nut, the barrel
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.42, 0.0, 0.0)))
	k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.058, 0.012), Vector2(0.059, 0.055), Vector2(r, 0.062), Vector2(r, 0.8), Vector2(0.047, 0.81), Vector2(0.0, 0.81)]), 20, lo, hi)
	k.lathe("blued", Vector3(0.0, 0.8, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.058, 0.0), Vector2(0.06, 0.012), Vector2(0.06, 0.07), Vector2(0.05, 0.08), Vector2(0.0, 0.08)]), 12, _b_mul(lo, 0.9), hi)
	k.lathe("blued", Vector3(0.0, 0.88, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.024, 0.18), Vector2(0.028, 0.19), Vector2(0.028, 0.215), Vector2(0.014, 0.22), Vector2(0.0, 0.22)]), 12, lo, hi)
	# the magazine housing's collar round the tube
	k.lathe("blued", Vector3(0.0, 0.4, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.059, 0.0), Vector2(0.06, 0.006), Vector2(0.06, 0.15), Vector2(0.059, 0.156), Vector2(0.0, 0.156)]), 20, lo, hi)
	k.pop()
	# magazine housing and magazine sticking out to the left (up, as it lies)
	var mx := 0.058
	k.box("blued", Vector3(mx, 0.0, 0.09), Vector3(0.14, 0.085, 0.08), lo, hi)
	k.box("blued", Vector3(mx, 0.0, 0.36), Vector3(0.1, 0.064, 0.48), _b_mul(lo, 1.08), _b_mul(hi, 1.06))
	k.box("blued", Vector3(mx, 0.0, 0.61), Vector3(0.112, 0.074, 0.025), lo, hi)
	# sights
	k.box("blued", Vector3(0.35, 0.066, 0.0), Vector3(0.025, 0.035, 0.016), lo, hi)
	k.box("blued", Vector3(-0.34, 0.064, 0.0), Vector3(0.04, 0.032, 0.034), lo, hi)
	# trigger housing, trigger and guard
	k.box("blued", Vector3(-0.13, -0.08, 0.0), Vector3(0.24, 0.07, 0.062), lo, hi)
	k.box("blued", Vector3(-0.21, -0.128, 0.0), Vector3(0.09, 0.04, 0.056), lo, hi)
	k.tube("blued", PackedVector3Array([Vector3(-0.02, -0.11, 0.0), Vector3(-0.025, -0.18, 0.0), Vector3(-0.065, -0.21, 0.0), Vector3(-0.12, -0.205, 0.0), Vector3(-0.16, -0.145, 0.0)]), 0.012, 6, hi)
	k.beam("blued", Vector3(-0.075, -0.11, 0.0), Vector3(-0.09, -0.175, 0.0), 0.02, 0.014, lo, hi, Vector2.ZERO, false, Vector3.RIGHT)
	# skeleton stock: two rods from the receiver to the butt plate
	var bx := -0.92
	k.tube("blued", PackedVector3Array([Vector3(-0.4, 0.0, 0.0), Vector3(-0.66, -0.018, 0.0), Vector3(bx, -0.035, 0.0)]), 0.019, 8, Color(0.75, 0.75, 0.78))
	k.tube("blued", PackedVector3Array([Vector3(-0.24, -0.12, 0.0), Vector3(-0.58, -0.18, 0.0), Vector3(bx, -0.24, 0.0)]), 0.019, 8, Color(0.75, 0.75, 0.78))
	k.box("blued", Vector3(bx - 0.016, -0.14, 0.0), Vector3(0.034, 0.32, 0.085), lo, hi)
	k.pop()
	s._commit(k, parent)
	return {"pitch": 36.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Window
# ---------------------------------------------------------------------------------------------------------------
func _b_pane(k: Kit, r: Rect2, z: float) -> void:
	var a := Vector3(r.position.x, r.position.y, z)
	var b := Vector3(r.end.x, r.position.y, z)
	var c := Vector3(r.end.x, r.end.y, z)
	var d := Vector3(r.position.x, r.end.y, z)
	k.quad4("b_glass", a, b, c, d, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.62, 0.66, 0.7), Color(0.48, 0.52, 0.58), Color(0.78, 0.82, 0.86), Color(0.95, 0.97, 1.0))
	# two glints running up to the right
	for g: Array in [[0.12, 0.1], [0.32, 0.045]]:
		var u0: float = g[0]
		var gw: float = g[1]
		var p := func(u: float, v: float) -> Vector3: return Vector3(r.position.x + r.size.x * u, r.position.y + r.size.y * v, z + 0.002)
		k.quad4("b_enamel", p.call(u0, 0.14), p.call(u0 + gw, 0.14), p.call(u0 + gw + 0.36, 0.86), p.call(u0 + 0.36, 0.86), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.7, 0.74, 0.78), Color(0.7, 0.74, 0.78), Color(0.86, 0.9, 0.94), Color(0.86, 0.9, 0.94))

## Distance from c along dir to the border of r (c inside r).
static func _b_to_border(c: Vector2, dir: Vector2, r: Rect2) -> float:
	var t := INF
	if dir.x > 1e-6:
		t = minf(t, (r.end.x - c.x) / dir.x)
	elif dir.x < -1e-6:
		t = minf(t, (r.position.x - c.x) / dir.x)
	if dir.y > 1e-6:
		t = minf(t, (r.end.y - c.y) / dir.y)
	elif dir.y < -1e-6:
		t = minf(t, (r.position.y - c.y) / dir.y)
	return t

## A broken pane: jagged shards left round the edges of a hole.
func _b_broken_pane(k: Kit, r: Rect2, z: float) -> void:
	var c := r.get_center() + Vector2(0.03, -0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var angles: Array[float] = []
	var n := 23
	for i: int in range(n):
		angles.append(fposmod(TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n), TAU))
	var corner_angles: Array[float] = []
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var a := fposmod((corner - c).angle(), TAU)
		angles.append(a)
		corner_angles.append(a)
	angles.sort()
	var inner: Array[Vector2] = []
	var outer: Array[Vector2] = []
	for i: int in range(angles.size()):
		var a: float = angles[i]
		var dir := Vector2(cos(a), sin(a))
		var t := _b_to_border(c, dir, r)
		outer.append(c + dir * t)
		var f := rng.randf_range(0.12, 0.4) if i % 2 == 0 else rng.randf_range(0.55, 0.92)
		if a in corner_angles:
			f = rng.randf_range(0.5, 0.65)
		inner.append(c + dir * t * f)
	var edge := Color(1.0, 1.0, 1.0)
	var rim := Color(0.55, 0.6, 0.66)
	for i: int in range(angles.size()):
		var j := (i + 1) % angles.size()
		k.quad4("b_glass", Vector3(inner[i].x, inner[i].y, z), Vector3(outer[i].x, outer[i].y, z), Vector3(outer[j].x, outer[j].y, z), Vector3(inner[j].x, inner[j].y, z), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, edge, rim, rim, edge)

func _window(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var w := 1.3
	var h := 1.5
	var f := 0.12
	var dep := 0.1
	var bar := 0.065
	var wood := Color(0.9, 0.74, 0.56)
	var lo := _b_mul(wood, 0.78)
	k.box("planks", Vector3(-w * 0.5 + f * 0.5, h * 0.5, 0.0), Vector3(f, h, dep), lo, wood, Vector2(0.0, 0.1), Kit.BEAM)
	k.box("planks", Vector3(w * 0.5 - f * 0.5, h * 0.5, 0.0), Vector3(f, h, dep), lo, wood, Vector2(0.3, 0.4), Kit.BEAM)
	k.box("planks", Vector3(0.0, h - f * 0.5, 0.0), Vector3(w - 2.0 * f, f, dep), lo, wood, Vector2(0.5, 0.2), Kit.BEAM)
	k.box("planks", Vector3(0.0, f * 0.65, 0.0), Vector3(w - 2.0 * f, f * 1.3, dep), lo, wood, Vector2(0.1, 0.6), Kit.BEAM)
	# a drip moulding along the bottom rail
	k.box("planks", Vector3(0.0, 0.05, dep * 0.5 + 0.02), Vector3(w - 2.0 * f, 0.05, 0.04), _b_mul(lo, 0.85), wood, Vector2(0.2, 0.3), Kit.BEAM)
	# glazing bars
	k.box("planks", Vector3(0.0, h * 0.5, -0.008), Vector3(bar, h - 2.0 * f, dep * 0.7), lo, wood, Vector2(0.7, 0.5), Kit.BEAM)
	k.box("planks", Vector3(0.0, h * 0.5, -0.008), Vector3(w - 2.0 * f, bar, dep * 0.7), lo, wood, Vector2(0.4, 0.8), Kit.BEAM)
	var x0 := -w * 0.5 + f
	var x1 := -bar * 0.5
	var x2 := bar * 0.5
	var x3 := w * 0.5 - f
	var y0 := f * 1.3
	var y1 := h * 0.5 - bar * 0.5
	var y2 := h * 0.5 + bar * 0.5
	var y3 := h - f
	var zg := -0.012
	_b_pane(k, Rect2(x2, y2, x3 - x2, y3 - y2), zg)
	_b_pane(k, Rect2(x0, y0, x1 - x0, y1 - y0), zg)
	_b_pane(k, Rect2(x2, y0, x3 - x2, y1 - y0), zg)
	_b_broken_pane(k, Rect2(x0, y2, x1 - x0, y3 - y2), zg)
	s._commit(k, parent)
	return {"pitch": 10.0, "yaw": -24.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Duct
# ---------------------------------------------------------------------------------------------------------------
## A square sheet-metal duct running back from its open end, dark inside, the louvred grille swung open on its
## hinges at the right.
func _duct(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var h := 0.42
	var g := h - 0.02
	var length := 1.1
	var zinc := Color(0.86, 0.9, 0.92)
	var sh := _b_mul(zinc, 0.75)
	var z1 := -length
	# outside
	k.quad4("steel", Vector3(-h, h, 0.0), Vector3(h, h, 0.0), Vector3(h, h, z1), Vector3(-h, h, z1), Vector2(0, 0.4), Vector2(0.33, 0.4), Vector2(0.33, 0), Vector2(0, 0), zinc, zinc, sh, sh)
	k.quad4("steel", Vector3(-h, -h, z1), Vector3(h, -h, z1), Vector3(h, -h, 0.0), Vector3(-h, -h, 0.0), Vector2(0, 0.4), Vector2(0.33, 0.4), Vector2(0.33, 0), Vector2(0, 0), sh, sh, sh, sh)
	k.quad4("steel", Vector3(h, -h, 0.0), Vector3(h, -h, z1), Vector3(h, h, z1), Vector3(h, h, 0.0), Vector2(0.5, 0.4), Vector2(0.9, 0.4), Vector2(0.9, 0.07), Vector2(0.5, 0.07), _b_mul(zinc, 0.8), sh, sh, zinc)
	k.quad4("steel", Vector3(-h, -h, z1), Vector3(-h, -h, 0.0), Vector3(-h, h, 0.0), Vector3(-h, h, z1), Vector2(0.1, 0.8), Vector2(0.5, 0.8), Vector2(0.5, 0.47), Vector2(0.1, 0.47), sh, _b_mul(zinc, 0.8), zinc, sh)
	# inside, darkening into the depth, closed by a black back
	var near := Color(0.5, 0.52, 0.54)
	var far := Color(0.05, 0.05, 0.06)
	k.quad4("steel", Vector3(-g, g, z1), Vector3(g, g, z1), Vector3(g, g, 0.0), Vector3(-g, g, 0.0), Vector2(0, 0.4), Vector2(0.33, 0.4), Vector2(0.33, 0), Vector2(0, 0), far, far, _b_mul(near, 0.7), _b_mul(near, 0.7))
	k.quad4("steel", Vector3(-g, -g, 0.0), Vector3(g, -g, 0.0), Vector3(g, -g, z1), Vector3(-g, -g, z1), Vector2(0, 0.4), Vector2(0.33, 0.4), Vector2(0.33, 0), Vector2(0, 0), near, near, far, far)
	k.quad4("steel", Vector3(g, -g, z1), Vector3(g, -g, 0.0), Vector3(g, g, 0.0), Vector3(g, g, z1), Vector2(0, 0.4), Vector2(0.4, 0.4), Vector2(0.4, 0), Vector2(0, 0), far, _b_mul(near, 0.85), _b_mul(near, 0.85), far)
	k.quad4("steel", Vector3(-g, -g, 0.0), Vector3(-g, -g, z1), Vector3(-g, g, z1), Vector3(-g, g, 0.0), Vector2(0, 0.4), Vector2(0.4, 0.4), Vector2(0.4, 0), Vector2(0, 0), near, far, far, near)
	k.quad4("b_ink", Vector3(-g, -g, z1 + 0.01), Vector3(g, -g, z1 + 0.01), Vector3(g, g, z1 + 0.01), Vector3(-g, g, z1 + 0.01), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3))
	# the flange round the mouth, with rivets
	var fl := 0.05
	for b: Array in [[Vector3(0.0, h + fl * 0.5, -0.03), Vector3(2.0 * h + 2.0 * fl, fl, 0.06)], [Vector3(0.0, -h - fl * 0.5, -0.03), Vector3(2.0 * h + 2.0 * fl, fl, 0.06)], [Vector3(h + fl * 0.5, 0.0, -0.03), Vector3(fl, 2.0 * h, 0.06)], [Vector3(-h - fl * 0.5, 0.0, -0.03), Vector3(fl, 2.0 * h, 0.06)]]:
		k.box("steel", b[0], b[1], sh, zinc, Vector2(0.2, 0.6))
	# front face of the flange over the sheet edge
	for q: Array in [[Vector3(-h - fl, g, 0.0), Vector3(h + fl, g, 0.0), Vector3(h + fl, h + fl, 0.0), Vector3(-h - fl, h + fl, 0.0)], [Vector3(-h - fl, -h - fl, 0.0), Vector3(h + fl, -h - fl, 0.0), Vector3(h + fl, -g, 0.0), Vector3(-h - fl, -g, 0.0)], [Vector3(-h - fl, -g, 0.0), Vector3(-g, -g, 0.0), Vector3(-g, g, 0.0), Vector3(-h - fl, g, 0.0)], [Vector3(g, -g, 0.0), Vector3(h + fl, -g, 0.0), Vector3(h + fl, g, 0.0), Vector3(g, g, 0.0)]]:
		k.quad4("steel", q[0], q[1], q[2], q[3], Vector2(0.1, 0.12), Vector2(0.45, 0.12), Vector2(0.45, 0.1), Vector2(0.1, 0.1), zinc, zinc, zinc, zinc)
	for i: int in range(3):
		var t := -0.25 + 0.25 * float(i)
		for p: Vector3 in [Vector3(t * 2.0 * h / 0.5 * 0.5, h + 0.022, 0.0), Vector3(t * 2.0 * h / 0.5 * 0.5, -h - 0.022, 0.0), Vector3(h + 0.022, t * 2.0 * h / 0.5 * 0.5, 0.0), Vector3(-h - 0.022, t * 2.0 * h / 0.5 * 0.5, 0.0)]:
			_b_button(k, p, 0.014, "steel", zinc)
	# a joint band part way back and seams along the corners
	for b: Array in [[Vector3(0.0, h + 0.012, -0.7), Vector3(2.0 * h + 0.03, 0.024, 0.07)], [Vector3(0.0, -h - 0.012, -0.7), Vector3(2.0 * h + 0.03, 0.024, 0.07)], [Vector3(h + 0.012, 0.0, -0.7), Vector3(0.024, 2.0 * h + 0.03, 0.07)], [Vector3(-h - 0.012, 0.0, -0.7), Vector3(0.024, 2.0 * h + 0.03, 0.07)]]:
		k.box("steel", b[0], b[1], sh, zinc, Vector2(0.6, 0.2))
	for c: Vector2 in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]:
		k.box("steel", Vector3(c.x, c.y, -length * 0.5 - 0.03), Vector3(0.026, 0.026, length - 0.06), sh, zinc, Vector2(0.3, 0.7))
	# the grille, hinged on the right and swung open toward us
	var paint := Color(0.56, 0.6, 0.55)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(112.0)), Vector3(h + fl, 0.0, 0.03)))
	var gw := 2.0 * h + 0.08
	var gh := 2.0 * h + 0.08
	var bw := 0.065
	k.box("paint", Vector3(-gw * 0.5, gh * 0.5 - bw * 0.5, 0.015), Vector3(gw, bw, 0.03), _b_mul(paint, 0.8), paint)
	k.box("paint", Vector3(-gw * 0.5, -gh * 0.5 + bw * 0.5, 0.015), Vector3(gw, bw, 0.03), _b_mul(paint, 0.8), paint)
	k.box("paint", Vector3(-bw * 0.5, 0.0, 0.015), Vector3(bw, gh - 2.0 * bw, 0.03), _b_mul(paint, 0.8), paint)
	k.box("paint", Vector3(-gw + bw * 0.5, 0.0, 0.015), Vector3(bw, gh - 2.0 * bw, 0.03), _b_mul(paint, 0.8), paint)
	var n := 7
	for i: int in range(n):
		var y := lerpf(-gh * 0.5 + bw + 0.05, gh * 0.5 - bw - 0.05, float(i) / float(n - 1))
		k.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-42.0)), Vector3(-gw * 0.5, y, 0.015)))
		k.box("paint", Vector3.ZERO, Vector3(gw - 2.0 * bw + 0.01, 0.1, 0.012), _b_mul(paint, 0.7), _b_mul(paint, 1.05))
		k.pop()
	for y: float in [-0.26, 0.26]:
		k.lathe("blued", Vector3(0.0, y - 0.07, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.022, 0.0), Vector2(0.022, 0.14), Vector2(0.0, 0.14)]), 10, Color(0.6, 0.6, 0.6), Color(0.8, 0.8, 0.8))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 16.0, "yaw": -24.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Stopwatch
# ---------------------------------------------------------------------------------------------------------------
func _b_hand(k: Kit, at: Vector3, angle: float, length: float, tail: float, w0: float, w1: float) -> void:
	var dir := Vector3(sin(angle), 0.0, -cos(angle))
	var right := Vector3(cos(angle), 0.0, sin(angle))
	var base := at - dir * tail
	var tip := at + dir * length
	var c := Color(1, 1, 1)
	k.quad4("b_ink", base - right * w0, base + right * w0, tip + right * w1, tip - right * w1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, c, c, c, c)

## A nickel stopwatch lying dial up: the crown and ring at twelve, a pusher beside it, a white dial with ticks, a
## sweep hand and a small minutes register.
func _clock(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var lo := Color(0.62, 0.62, 0.64)
	var hi := Color(0.95, 0.95, 0.97)
	var rd := 0.4
	k.lathe("blade", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.38, 0.0), Vector2(0.45, 0.015), Vector2(0.49, 0.05), Vector2(0.5, 0.09), Vector2(0.485, 0.125), Vector2(0.455, 0.15), Vector2(0.43, 0.16), Vector2(0.41, 0.155), Vector2(rd, 0.145)]), 72, lo, hi)
	var dy := 0.145
	k.disc("b_enamel", Vector3(0.0, dy, 0.0), rd + 0.003, 72, Rect2(0, 0, 1, 1), Color(0.95, 0.94, 0.9))
	var ty := dy + 0.003
	for i: int in range(60):
		var a := TAU * float(i) / 60.0
		var d := Vector3(sin(a), 0.0, -cos(a))
		var major := i % 5 == 0
		k.beam("b_ink", Vector3(0.0, ty, 0.0) + d * (0.37 if not major else 0.375), Vector3(0.0, ty, 0.0) + d * (0.335 if not major else 0.3), 0.01 if not major else 0.022, 0.004, Color(1, 1, 1), Color(1, 1, 1))
	# minutes register at six
	var reg := Vector3(0.0, ty, 0.17)
	var ring := PackedVector3Array()
	for i: int in range(33):
		var a := TAU * float(i) / 32.0
		ring.append(reg + Vector3(cos(a), 0.0, sin(a)) * 0.09)
	k.tube("b_ink", ring, 0.004, 4, Color(1, 1, 1))
	for i: int in range(12):
		var a := TAU * float(i) / 12.0
		var d := Vector3(sin(a), 0.0, -cos(a))
		k.beam("b_ink", reg + d * 0.085, reg + d * 0.065, 0.008, 0.004, Color(1, 1, 1), Color(1, 1, 1))
	_b_hand(k, reg + Vector3(0.0, 0.002, 0.0), deg_to_rad(130.0), 0.07, 0.015, 0.008, 0.002)
	# the sweep hand and its boss
	_b_hand(k, Vector3(0.0, ty + 0.008, 0.0), deg_to_rad(52.0), 0.355, 0.09, 0.012, 0.0025)
	k.lathe("b_ink", Vector3(0.0, ty, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.012), Vector2(0.015, 0.02), Vector2(0.0, 0.021)]), 14, Color(1, 1, 1), Color(1, 1, 1))
	# pendant, crown and the ring through it
	var cy := 0.08
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, cy, -0.46)))
	k.lathe("blade", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.05, 0.05), Vector2(0.035, 0.08), Vector2(0.0, 0.08)]), 16, lo, hi)
	k.pop()
	_b_sweep(k, "blade", PackedVector3Array([Vector3(0.0, cy, -0.53), Vector3(0.0, cy, -0.6)]), _b_loop(48, 2.0, 0.06, 24), [Vector2(0.07, 0.07)], [Vector3.UP], [hi], true)
	var bow := PackedVector3Array()
	var bc := Vector3(0.0, cy, -0.7)
	for i: int in range(37):
		var a := TAU * float(i) / 36.0
		bow.append(bc + Vector3(cos(a) * 0.17, 0.0, sin(a) * 0.15))
	k.tube("blade", bow, 0.03, 10, hi)
	# the reset pusher at one o'clock
	var pa := deg_to_rad(38.0)
	var pd := Vector3(sin(pa), 0.0, -cos(pa))
	k.push(_b_along(pd * 0.47 + Vector3(0.0, cy, 0.0), pd * 0.6 + Vector3(0.0, cy, 0.0)))
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
	k.lathe("blade", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.06), Vector2(0.045, 0.065), Vector2(0.045, 0.11), Vector2(0.03, 0.12), Vector2(0.0, 0.12)]), 14, lo, hi)
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 62.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Bush
# ---------------------------------------------------------------------------------------------------------------
## A leaf card, both faces, with a hand-set "volume" normal (as the game's bushes do).
func _b_card(k: Kit, key: String, centre: Vector3, normal: Vector3, size: float, uv: Rect2, roll: float, shade_n: Vector3, col: Color, low: Color) -> void:
	var t := normal.cross(Vector3.UP)
	t = Vector3.RIGHT if t.length() < 0.01 else t.normalized()
	t = t.rotated(normal, roll)
	var down := normal.cross(t)
	var h := size * 0.5
	var p := [centre - t * h - down * h, centre + t * h - down * h, centre + t * h + down * h, centre - t * h + down * h]
	var q := [uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)]
	var c := [col, col, low, low]
	var sf = k._surf(key)
	var n: Vector3 = (k.xf.basis * shade_n).normalized()
	var tg: Vector3 = (k.xf.basis * t).normalized()
	var base: int = sf.v.size()
	for i: int in range(4):
		k._push_vertex(sf, k.xf * (p[i] as Vector3), n, tg, 1.0, q[i], c[i])
	for idx: int in [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3]:
		sf.idx.append(base + idx)

## One clump: a dark leafy core dome with leaf sprays all over it (after nature.gd's bushes).
func _b_clump(k: Kit, r: RandomNumberGenerator, at: Vector3, radius: float, height: float, tone: float) -> void:
	var core := Rect2(0.13, 0.62, 0.24, 0.24)
	var rows := 5
	var seg := 12
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(rows):
		var e := float(i) / float(rows - 1) * PI * 0.5
		for j: int in range(seg + 1):
			var a := TAU * float(j) / float(seg)
			var dir := Vector3(cos(a) * cos(e), sin(e), -sin(a) * cos(e))
			pts.append(at + Vector3(dir.x * radius * 0.84, dir.y * height * 0.82, dir.z * radius * 0.84))
			uvs.append(core.position + core.size * Vector2(0.5 + 0.5 * cos(a) * cos(e), 0.5 + 0.5 * sin(a) * cos(e)))
			var g := lerpf(0.34, 0.6, float(i) / float(rows - 1)) * tone
			cols.append(Color(g, g, g))
	k.patch("b_leafcore", rows, seg + 1, pts, uvs, cols, true)
	var spin := r.randf() * TAU
	for i: int in range(16):
		var tier := 0 if i < 7 else (1 if i < 13 else 2)
		var count: int = [7, 6, 3][tier]
		var a := spin + TAU * float(i) / float(count) + float(tier) * 0.5 + r.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0.0, sin(a))
		var reach: float = [0.74, 0.5, 0.15][tier]
		var lift: float = [0.36, 0.72, 0.96][tier]
		var flare: float = [0.95, 0.6, 0.15][tier]
		var rise: float = [0.35, 0.8, 1.0][tier]
		var nrm := (out * flare + Vector3.UP * rise).normalized()
		if tier == 2:
			nrm = (nrm + Vector3(r.randf_range(-0.45, 0.45), 0.0, r.randf_range(-0.45, 0.45))).normalized()
		var size := radius * r.randf_range(1.15, 1.45)
		var light: float = [0.62, 0.9, 1.0][tier] * tone * r.randf_range(0.9, 1.06)
		var uv: Rect2 = (UV_SHRUB if (i + tier) % 3 != 0 else UV_SMALL).grow(-0.008)
		_b_card(k, "b_leaf", at + out * radius * reach + Vector3.UP * height * lift, nrm, size, uv, r.randf() * TAU, (nrm + Vector3.UP * 0.6).normalized(), Color(light, light, light), Color(light * 0.8, light * 0.8, light * 0.8))

func _hide(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var r := RandomNumberGenerator.new()
	r.seed = 50501
	var clumps := [[Vector3(0.05, 0.0, -0.45), 0.5, 0.95, 0.95], [Vector3(-0.55, 0.0, -0.12), 0.5, 0.84, 0.92], [Vector3(0.58, 0.0, -0.1), 0.5, 0.88, 1.0], [Vector3(0.0, 0.0, 0.05), 0.56, 1.08, 1.04], [Vector3(-0.32, 0.0, 0.42), 0.46, 0.66, 1.0], [Vector3(0.36, 0.0, 0.44), 0.44, 0.62, 0.94]]
	for c: Array in clumps:
		_b_clump(k, r, c[0], c[1], c[2], c[3])
	s._commit(k, parent)
	return {"pitch": 30.0, "yaw": 0.0, "margin": 0.05}

# ---------------------------------------------------------------------------------------------------------------
# Buenos Aires, 1958
# ---------------------------------------------------------------------------------------------------------------
## The lamplighter's key: a long iron rod, a T handle with turned wooden grips at the top, a square socket at the
## bottom end.
func _lampkey(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var iron := Color(0.4, 0.38, 0.37)
	var ilo := _b_mul(iron, 0.7)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-38.0)), Vector3(0.0, 0.074, 0.0)))
	var length := 1.6
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.03, -0.05), Vector2(0.05, -0.035), Vector2(0.052, 0.0), Vector2(0.044, 0.035), Vector2(0.036, 0.06), Vector2(0.033, 0.09), Vector2(0.033, length - 0.24), Vector2(0.04, length - 0.22), Vector2(0.04, length - 0.2), Vector2(0.07, length - 0.17), Vector2(0.074, length - 0.15), Vector2(0.074, length - 0.012), Vector2(0.068, length), Vector2(0.0, length)]), 18, ilo, iron)
	k.pop()
	# the square socket in the end face
	var q := 0.034
	var xe := length + 0.002
	k.quad4("b_ink", Vector3(xe, -q, q), Vector3(xe, -q, -q), Vector3(xe, q, -q), Vector3(xe, q, q), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4))
	# the T: an iron cross bar with two turned grips and knobbed ends
	var half := 0.27
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -half)))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.04, 0.015), Vector2(0.038, 0.04), Vector2(0.026, 0.05), Vector2(0.026, half * 2.0 - 0.05), Vector2(0.038, half * 2.0 - 0.04), Vector2(0.04, half * 2.0 - 0.015), Vector2(0.03, half * 2.0), Vector2(0.0, half * 2.0)]), 14, ilo, iron)
	var wood := Color(0.62, 0.4, 0.24)
	for z0: float in [0.06, half + 0.05]:
		k.lathe("planks", Vector3(0.0, z0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.053, 0.03), Vector2(0.055, half - 0.17), Vector2(0.042, half - 0.12), Vector2(0.0, half - 0.12)]), 14, _b_mul(wood, 0.7), wood, Vector2(0.2 * z0, 0.0), PackedFloat32Array(), -1.0, true)
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 40.0, "yaw": 0.0, "margin": 0.05}

## A tram's foot gong: a polished brass dome on an iron post and foot, the striker's hammer resting by its rim.
func _bell(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var iron := Color(0.62, 0.6, 0.58)
	var ilo := _b_mul(iron, 0.65)
	k.box("blued", Vector3(-0.08, 0.025, 0.0), Vector3(1.06, 0.05, 0.34), ilo, iron)
	for x: float in [-0.42, 0.34]:
		for z: float in [-0.1, 0.1]:
			k.lathe("blued", Vector3(x, 0.05, z), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.036, 0.0), Vector2(0.036, 0.025), Vector2(0.025, 0.032), Vector2(0.0, 0.032)]), 6, ilo, iron)
	var rim := 0.42
	var post := 0.3 + rim - 0.05
	k.lathe("blued", Vector3(0.0, 0.05, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.11, 0.0), Vector2(0.11, 0.02), Vector2(0.07, 0.06), Vector2(0.048, 0.11), Vector2(0.045, post - 0.02), Vector2(0.06, post), Vector2(0.0, post)]), 18, ilo, iron)
	# the gong: an open dome, lip turned down
	var dome := PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.16, 0.285), Vector2(0.3, 0.23), Vector2(0.41, 0.14), Vector2(0.47, 0.05), Vector2(0.49, 0.0), Vector2(0.53, 0.0), Vector2(0.538, 0.045), Vector2(0.505, 0.135), Vector2(0.43, 0.23), Vector2(0.31, 0.305), Vector2(0.16, 0.345), Vector2(0.0, 0.356)])
	k.lathe("b_brass", Vector3(0.0, rim, 0.0), dome, 56, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	# the centre nut
	k.lathe("blued", Vector3(0.0, rim + 0.35, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.04), Vector2(0.045, 0.05), Vector2(0.0, 0.05)]), 6, ilo, iron)
	# the striker: a pivot block on the foot, a spring arm, the hammer ball against the rim
	var pivot := Vector3(-0.54, 0.09, 0.0)
	k.box("blued", Vector3(-0.54, 0.075, 0.0), Vector3(0.09, 0.05, 0.12), ilo, iron)
	var ball := Vector3(-0.605, rim + 0.035, 0.0)
	k.beam("blued", pivot, ball + Vector3(0.0, -0.04, 0.0), 0.05, 0.03, ilo, iron, Vector2.ZERO, false, Vector3.RIGHT)
	# the return spring coiled round the pivot
	var coil := PackedVector3Array()
	for i: int in range(41):
		var a := TAU * 3.0 * float(i) / 40.0
		coil.append(pivot + Vector3(cos(a) * 0.04, sin(a) * 0.04, -0.06 + 0.12 * float(i) / 40.0))
	k.tube("blade", coil, 0.008, 5, Color(0.7, 0.7, 0.72))
	_b_ball(k, "blued", ball, 0.068, ilo, iron, 16)
	s._commit(k, parent)
	return {"pitch": 22.0, "yaw": 0.0, "margin": 0.05}

## One folded newspaper lying flat: a slab with the fold rounded along its back edge.
func _b_newspaper(k: Kit, w: float, d: float, t: float, col: Color, printed: bool) -> void:
	k.box("b_paper", Vector3(0.0, t * 0.5, t * 0.25), Vector3(w, t, d - t * 0.5), _b_mul(col, 0.62), col)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-w * 0.5, t * 0.5, -d * 0.5 + t * 0.5)))
	k.lathe("b_paper", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(t * 0.5, 0.0), Vector2(t * 0.5, w), Vector2(0.0, w)]), 10, _b_mul(col, 0.8), _b_mul(col, 0.8))
	k.pop()
	if printed:
		var y := t + 0.002
		k.quad_rect("b_print", Vector3(-w * 0.5 + 0.03, y, d * 0.5 - 0.03), Vector3(w * 0.5 - 0.03, y, d * 0.5 - 0.03), Vector3(w * 0.5 - 0.03, y, -d * 0.5 + 0.05), Vector3(-w * 0.5 + 0.03, y, -d * 0.5 + 0.05), Rect2(0, 0, 1, 1), col, col)

## A bundle of folded newspapers tied both ways with string, the knot on top.
func _papers(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-22.0)), Vector3.ZERO))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	var w := 1.3
	var d := 0.92
	var t := 0.05
	var count := 6
	for i: int in range(count):
		var tone := rng.randf_range(0.78, 0.92)
		var col := Color(tone, tone * 0.97, tone * 0.88)
		var top := i == count - 1
		k.push(Transform3D(Basis(Vector3.UP, 0.0 if top else rng.randf_range(-0.045, 0.045)), Vector3(0.0 if top else rng.randf_range(-0.03, 0.03), t * float(i), 0.0 if top else rng.randf_range(-0.025, 0.025))))
		_b_newspaper(k, w, d, t, Color(0.94, 0.92, 0.86) if top else col, top)
		k.pop()
	var height := t * float(count)
	var rs := 0.014
	var hemp := Color(0.9, 0.78, 0.58)
	# the strings: one round the length, one round the width, crossing at the middle
	for along_x: bool in [true, false]:
		var hx := (w * 0.5 + 0.04) if along_x else (d * 0.5 + 0.04)
		var loop := _b_rounded_rect(hx, height * 0.5 + rs, 0.05, 3)
		var path := PackedVector3Array()
		for p: Vector2 in loop:
			var y := p.y + height * 0.5
			path.append(Vector3(p.x, y, 0.0) if along_x else Vector3(0.0, y, -p.x))
		k.tube("burlap", path, rs, 6, hemp, Vector2.ZERO, 0.25, 2.0)
	# the knot and its loose ends
	var ky := height + rs
	_b_ball(k, "burlap", Vector3(0.0, ky + 0.01, 0.0), 0.032, _b_mul(hemp, 0.85), hemp, 10)
	k.tube("burlap", PackedVector3Array([Vector3(0.02, ky + 0.01, 0.02), Vector3(0.09, ky, 0.07), Vector3(0.16, ky - 0.002, 0.08), Vector3(0.22, ky - 0.004, 0.13)]), rs * 0.9, 6, hemp, Vector2.ZERO, 0.25, 2.0)
	k.tube("burlap", PackedVector3Array([Vector3(-0.02, ky + 0.01, 0.02), Vector3(-0.07, ky, 0.09), Vector3(-0.1, ky - 0.002, 0.17), Vector3(-0.17, ky - 0.004, 0.21)]), rs * 0.9, 6, hemp, Vector2.ZERO, 0.25, 2.0)
	k.pop()
	s._commit(k, parent)
	return {"pitch": 42.0, "yaw": 0.0, "margin": 0.05}

## One wooden oar along +X from the handle end at the origin, its axis on y = 0: handle, loom, leather button and
## collar, shaft, and a flat blade.
func _b_oar(k: Kit, wood: Color) -> void:
	var st := [[0.0, 0.0, 0.0], [0.004, 0.024, 0.024], [0.02, 0.038, 0.038], [0.04, 0.042, 0.042], [0.3, 0.042, 0.042], [0.33, 0.034, 0.034], [0.38, 0.055, 0.055], [1.05, 0.056, 0.056], [1.5, 0.045, 0.045], [1.6, 0.05, 0.035], [1.75, 0.085, 0.028], [1.95, 0.105, 0.022], [2.3, 0.115, 0.019], [2.55, 0.115, 0.017], [2.66, 0.1, 0.015], [2.72, 0.06, 0.013], [2.735, 0.0, 0.0]]
	var path := PackedVector3Array()
	var sizes := []
	var cols := []
	for row: Array in st:
		path.append(Vector3(row[0], 0.0, 0.0))
		sizes.append(Vector2(row[1], row[2]))
		cols.append(_b_mul(wood, lerpf(0.85, 1.0, float(row[0]) / 2.3)))
	_b_sweep(k, "planks", path, _b_loop(24, 2.0), sizes, [Vector3.UP], cols, false, true, false, Vector2(0.0, 0.35))
	var leather := Color(0.4, 0.26, 0.16)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.6, 0.0, 0.0)))
	k.lathe("b_leather", Vector3.ZERO, PackedVector2Array([Vector2(0.055, 0.0), Vector2(0.08, 0.008), Vector2(0.082, 0.035), Vector2(0.062, 0.045), Vector2(0.062, 0.3), Vector2(0.056, 0.31)]), 18, _b_mul(leather, 0.8), leather)
	k.pop()

func _oars(s, parent: Node3D) -> Dictionary:
	_b_materials(s)
	var k := Kit.new()
	var spread := deg_to_rad(31.0)
	var cross := 1.3
	var woods := [Color(0.95, 0.76, 0.54), Color(0.88, 0.7, 0.5)]
	for i: int in range(2):
		var side := 1.0 if i == 0 else -1.0
		var dir := Vector3(side * sin(spread), 0.0, -cos(spread))
		var handle := -dir * cross + Vector3(0.0, 0.056, 0.0)
		var rise := 0.0 if i == 0 else 0.1 / cross
		k.push(_b_along(handle, handle + dir + Vector3.UP * rise))
		_b_oar(k, woods[i])
		k.pop()
	s._commit(k, parent)
	return {"pitch": 48.0, "yaw": 0.0, "margin": 0.04}
