extends RefCounted
## Icons for doors and keys, the canoe, the dossier, the binding cord, the revolver, the tripwire, the signal flag,
## the charge, the knife switch, the cigarette, the cosh, the bottle and the pebble (rendered by studio.gd).
const Kit := preload("res://scripts/three_d/structures_kit.gd")
const NAMES := ["key", "cell", "boat", "brief", "bind", "revolver", "tripwire", "flag", "charge", "switch", "cigarette",
	"gate", "cosh", "bottle", "throw"]

## Long objects lie on this diagonal: local +X turned this far about Y points up and to the right in the icon.
const DIAG := 35.0

# ---------------------------------------------------------------------------------------------------------------
# Materials of this module, added to the studio's table once
# ---------------------------------------------------------------------------------------------------------------
func _materials(s) -> void:
	var mats: Dictionary = s.mats
	if mats.has("a_bright"):
		return
	# cloth, card and paper: the canvas weave brightened so pale colours (paper, buff card, a yellow flag) come out
	mats["a_bright"] = _brightened("canvas", 0.45)
	mats["a_cord"] = _brightened("burlap", 1.0)
	mats["a_leather"] = _textured("canvas", 0.0, 0.52, 0.5)
	mats["a_pebble"] = _textured("steel", 0.0, 0.5, 0.3)
	mats["a_copper"] = s._metal(Color(0.92, 0.56, 0.38), 0.55, 0.36)
	mats["a_tin"] = s._metal(Color(0.88, 0.89, 0.88), 0.35, 0.34)
	# glass and ebonite: smooth, glossy, coloured by the vertices
	var gloss := StandardMaterial3D.new()
	gloss.vertex_color_use_as_albedo = true
	gloss.roughness = 0.12
	gloss.metallic_specular = 0.75
	mats["a_gloss"] = gloss

## A kit texture made grey, light and low in contrast, so the vertex colours alone give the hue (paper, buff card,
## a yellow flag, a pale cord).
func _brightened(tex: String, normal: float) -> StandardMaterial3D:
	var img: Image = (load(Kit.TEX_DIR + tex + "_a.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var v := clampf(0.68 + ((c.r + c.g + c.b) / 3.0 - 0.47) * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.metallic_specular = 0.3
	m.normal_enabled = true
	m.normal_texture = load(Kit.TEX_DIR + tex + "_n.png")
	m.normal_scale = normal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _textured(tex: String, metallic: float, roughness: float, normal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(Kit.TEX_DIR + tex + "_a.png")
	m.vertex_color_use_as_albedo = true
	m.metallic = metallic
	m.roughness = roughness
	m.normal_enabled = true
	m.normal_texture = load(Kit.TEX_DIR + tex + "_n.png")
	m.normal_scale = normal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ---------------------------------------------------------------------------------------------------------------
# Shared shapes
# ---------------------------------------------------------------------------------------------------------------
## A ring: the circle of radius `big` lies in the X-Z plane of `b` round `at`, the tube is `small` thick.
func _torus(k: Kit, key: String, at: Vector3, b: Basis, big: float, small: float, segs: int, sides: int, lo: Color, hi: Color) -> void:
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(sides + 1):
		var th := TAU * float(i) / float(sides)
		for j: int in range(segs + 1):
			var ph := TAU * float(j) / float(segs)
			var radial := Vector3(cos(ph), 0.0, -sin(ph))
			pts.append(at + b * (radial * (big + small * cos(th)) + Vector3.UP * small * sin(th)))
			uvs.append(Vector2(ph * big, th * small) * Kit.UV_M * 2.0)
			cols.append(lo.lerp(hi, 0.5 + 0.5 * sin(th)))
	k.patch(key, sides + 1, segs + 1, pts, uvs, cols, true, false, true)

## A flat plate cut to `outline` (x, y in the local X-Y plane), `thick` deep in Z round z0. smooth: rounded edges.
func _slab(k: Kit, key: String, outline: PackedVector2Array, z0: float, thick: float, lo: Color, hi: Color, smooth: bool = false) -> void:
	var pts := outline.duplicate()
	var n := pts.size()
	var area := 0.0
	var y_min := INF
	var y_max := -INF
	for i: int in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
		y_min = minf(y_min, a.y)
		y_max = maxf(y_max, a.y)
	if area < 0.0:
		pts.reverse()
	var span := maxf(y_max - y_min, 1e-4)
	var hz := thick * 0.5
	var tris := Geometry2D.triangulate_polygon(pts)
	for t: int in range(0, tris.size(), 3):
		var a2 := pts[tris[t]]
		var b2 := pts[tris[t + 1]]
		var c2 := pts[tris[t + 2]]
		if (b2 - a2).cross(c2 - a2) < 0.0:
			var sw := b2
			b2 = c2
			c2 = sw
		var ca := lo.lerp(hi, (a2.y - y_min) / span)
		var cb := lo.lerp(hi, (b2.y - y_min) / span)
		var cc := lo.lerp(hi, (c2.y - y_min) / span)
		var ua := Vector2(a2.x, -a2.y) * Kit.UV_M
		var ub := Vector2(b2.x, -b2.y) * Kit.UV_M
		var uc := Vector2(c2.x, -c2.y) * Kit.UV_M
		k.tri(key, Vector3(a2.x, a2.y, z0 + hz), Vector3(b2.x, b2.y, z0 + hz), Vector3(c2.x, c2.y, z0 + hz), ua, ub, uc, ca, cb, cc)
		k.tri(key, Vector3(a2.x, a2.y, z0 - hz), Vector3(c2.x, c2.y, z0 - hz), Vector3(b2.x, b2.y, z0 - hz), ua + Vector2(0.3, 0.1), uc + Vector2(0.3, 0.1), ub + Vector2(0.3, 0.1), ca, cc, cb)
	if smooth:
		var spts := PackedVector3Array()
		var suvs := PackedVector2Array()
		var scols := PackedColorArray()
		for r: int in range(2):
			var z := z0 - hz + thick * float(r)
			var run := 0.0
			for i: int in range(n + 1):
				var p := pts[i % n]
				if i > 0:
					run += p.distance_to(pts[i - 1])
				spts.append(Vector3(p.x, p.y, z))
				suvs.append(Vector2(run, z) * Kit.UV_M)
				scols.append(lo.lerp(hi, (p.y - y_min) / span))
		k.patch(key, 2, n + 1, spts, suvs, scols, true)
	else:
		var run2 := 0.0
		for i: int in range(n):
			var p0 := pts[i]
			var p1 := pts[(i + 1) % n]
			var seg := p0.distance_to(p1)
			var c0 := lo.lerp(hi, (p0.y - y_min) / span)
			var c1 := lo.lerp(hi, (p1.y - y_min) / span)
			k.quad4(key, Vector3(p0.x, p0.y, z0 - hz), Vector3(p1.x, p1.y, z0 - hz), Vector3(p1.x, p1.y, z0 + hz), Vector3(p0.x, p0.y, z0 + hz),
				Vector2(run2, 0.0) * Kit.UV_M, Vector2(run2 + seg, 0.0) * Kit.UV_M, Vector2(run2 + seg, thick) * Kit.UV_M, Vector2(run2, thick) * Kit.UV_M, c0, c1, c1, c0)
			run2 += seg

## A soft canvas block standing on `base` (centre of its underside): rounded edges of radius `edge`.
func _softbox(k: Kit, key: String, base: Vector3, size: Vector3, edge: float, lo: Color, hi: Color, segs: int = 48) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var rows_d: Array[float] = [-1.0]
	var rows_y: Array[float] = [0.0]
	for i: int in range(5):
		var th := PI * 0.5 * float(i) / 4.0
		rows_d.append(edge * (1.0 - sin(th)))
		rows_y.append(edge * (1.0 - cos(th)))
	for i: int in range(5):
		var th := PI * 0.5 * float(4 - i) / 4.0
		rows_d.append(edge * (1.0 - sin(th)))
		rows_y.append(h - edge * (1.0 - cos(th)))
	rows_d.append(-1.0)
	rows_y.append(h)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var expo := 2.0 / 7.0
	for i: int in range(rows_d.size()):
		var d: float = rows_d[i]
		var y: float = rows_y[i]
		var ax := 0.0 if d < 0.0 else hx - d
		var az := 0.0 if d < 0.0 else hz - d
		# a slight belly on the sides
		var belly := 1.0 + 0.035 * sin(PI * clampf(y / h, 0.0, 1.0))
		for j: int in range(segs + 1):
			var ang := TAU * float(j) / float(segs)
			var c := cos(ang)
			var sn := sin(ang)
			var x := ax * belly * signf(c) * pow(absf(c), expo)
			var z := -az * belly * signf(sn) * pow(absf(sn), expo)
			pts.append(base + Vector3(x, y, z))
			uvs.append(Vector2(ang * (hx + hz) * 0.5, -y) * Kit.UV_M * 1.6)
			cols.append(lo.lerp(hi, y / h))
	k.patch(key, rows_d.size(), segs + 1, pts, uvs, cols, true)

## A strap round a soft box (as _softbox makes it, standing at y = 0 and centred on z = 0) in the Y-Z plane at x.
func _strap(k: Kit, key: String, x: float, half_z: float, height: float, corner: float, width: float, col: Color) -> void:
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	var steps := 6
	var hz := half_z - corner
	var centres := [Vector2(hz, height - corner), Vector2(-hz, height - corner), Vector2(-hz, corner), Vector2(hz, corner)]
	for c: int in range(4):
		for i: int in range(steps + 1):
			var a := PI * 0.5 * (float(c) + float(i) / float(steps))
			var nrm := Vector2(cos(a), sin(a))
			var cen: Vector2 = centres[c]
			var po := cen + nrm * (corner + 0.016)
			var pn := cen + nrm * (corner - 0.01)
			outer.append(Vector3(0.0, po.y, po.x))
			inner.append(Vector3(0.0, pn.y, pn.x))
	outer.append(outer[0])
	inner.append(inner[0])
	var rows := outer.size()
	var face := PackedVector3Array()
	var face_uv := PackedVector2Array()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var edge_uv := PackedVector2Array()
	var run := 0.0
	for i: int in range(rows):
		if i > 0:
			run += outer[i].distance_to(outer[i - 1])
		var o := outer[i]
		var n := inner[i]
		face.append(o + Vector3(x - width * 0.5, 0, 0))
		face.append(o + Vector3(x + width * 0.5, 0, 0))
		face_uv.append(Vector2(0.0, run) * Kit.UV_M * 2.0)
		face_uv.append(Vector2(width, run) * Kit.UV_M * 2.0)
		left.append(n + Vector3(x - width * 0.5, 0, 0))
		left.append(o + Vector3(x - width * 0.5, 0, 0))
		right.append(n + Vector3(x + width * 0.5, 0, 0))
		right.append(o + Vector3(x + width * 0.5, 0, 0))
		edge_uv.append(Vector2(0.0, run) * Kit.UV_M)
		edge_uv.append(Vector2(0.02, run) * Kit.UV_M)
	var cols := PackedColorArray([col])
	k.patch(key, rows, 2, face, face_uv, cols)
	k.patch(key, rows, 2, left, edge_uv, PackedColorArray([col * 0.8]))
	k.patch(key, rows, 2, right, edge_uv, PackedColorArray([col * 0.8]), false, true)

## A little mound of earth with grass blades, standing on `at`.
func _tuft(k: Kit, at: Vector3, radius: float, blades: int, rng_seed: int, tall: float = 0.2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	k.lathe("concrete", at + Vector3(0, -0.01, 0), PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.88, 0.035), Vector2(radius * 0.6, 0.08), Vector2(radius * 0.25, 0.105), Vector2(0.0, 0.11)]), 22, Color(0.3, 0.24, 0.17), Color(0.45, 0.37, 0.26))
	for i: int in range(blades):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius * 0.85
		var f := rr / radius
		var base := at + Vector3(cos(a) * rr, 0.1 * (1.0 - f * f) - 0.02, -sin(a) * rr)
		var out := Vector3(cos(a), 0.0, -sin(a))
		var tip := base + Vector3(0.0, rng.randf_range(0.45, 1.0) * tall, 0.0) + out * rng.randf_range(0.02, 0.1) + Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.03, 0.03))
		var b := rng.randf() * PI
		var side := Vector3(cos(b), 0.0, -sin(b)) * rng.randf_range(0.012, 0.022)
		var g := rng.randf_range(0.8, 1.1)
		var c0 := Color(0.26, 0.31, 0.14) * g
		var c1 := Color(0.62, 0.62, 0.32) * g
		k.tri("canvas", base - side, base + side, tip, Vector2(0.0, 0.1), Vector2(0.02, 0.1), Vector2(0.01, 0.0), c0, c0, c1)
		k.tri("canvas", base + side, base - side, tip, Vector2(0.02, 0.1), Vector2(0.0, 0.1), Vector2(0.01, 0.0), c0, c0, c1)

## A flat round cap closing a tube end at `at`, facing along `dir`.
func _cap(k: Kit, key: String, at: Vector3, dir: Vector3, radius: float, col: Color) -> void:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	k.push(Transform3D(Basis(x, y, x.cross(y)), at))
	k.disc(key, Vector3.ZERO, radius, 10, Rect2(0.1, 0.1, 0.05, 0.05), col)
	k.pop()

## A revolver cylinder along local +Y from `at`, with `flutes` grooves down most of its length.
func _fluted(k: Kit, key: String, at: Vector3, radius: float, length: float, flutes: int, lo: Color, hi: Color) -> void:
	var ys: Array[float] = [0.0, 0.0, 0.01, 0.025, length * 0.3, length * 0.42, length - 0.035, length - 0.025, length - 0.01, length, length]
	var sc: Array[float] = [0.0, 0.84, 0.96, 1.0, 1.0, 1.0, 1.0, 1.0, 0.96, 0.86, 0.0]
	var fl: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0]
	var segs := 60
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(ys.size()):
		for j: int in range(segs + 1):
			var ang := TAU * float(j) / float(segs)
			var groove := pow(maxf(0.0, cos(float(flutes) * ang)), 2.0)
			var r: float = radius * sc[i] * (1.0 - 0.22 * fl[i] * groove)
			pts.append(at + Vector3(cos(ang) * r, ys[i], -sin(ang) * r))
			uvs.append(Vector2(ang * radius, -ys[i]) * Kit.UV_M)
			var c := lo.lerp(hi, 0.5 + 0.5 * sin(ang)) * (1.0 - 0.5 * fl[i] * groove)
			c.a = 1.0
			cols.append(c)
	k.patch(key, ys.size(), segs + 1, pts, uvs, cols, true)

# ---------------------------------------------------------------------------------------------------------------
# The objects
# ---------------------------------------------------------------------------------------------------------------

## A big old iron door key lying flat: a ring bow, collars, a long shank and a toothed bit.
func _key(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var lo := Color(0.42, 0.4, 0.38)
	var hi := Color(0.6, 0.57, 0.53)
	var y := 0.045
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(DIAG)), Vector3.ZERO))
	_torus(k, "steel", Vector3(-0.44, y, 0.0), Basis.IDENTITY, 0.19, 0.045, 36, 10, lo, hi)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.29, y, 0.0)))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.036, 0.0), Vector2(0.036, 0.08), Vector2(0.053, 0.095), Vector2(0.053, 0.13), Vector2(0.036, 0.145), Vector2(0.04, 0.17), Vector2(0.047, 0.18), Vector2(0.047, 0.2), Vector2(0.034, 0.215), Vector2(0.031, 0.24), Vector2(0.031, 0.76), Vector2(0.036, 0.77), Vector2(0.041, 0.79), Vector2(0.041, 0.82), Vector2(0.03, 0.835), Vector2(0.0, 0.84)]), 14, lo, hi)
	k.pop()
	# the bit: a plate off the end of the shank, its wards cut into the far edge (local y here = toward the viewer)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	_slab(k, "steel", PackedVector2Array([Vector2(0.32, -0.02), Vector2(0.54, -0.02), Vector2(0.54, 0.25), Vector2(0.5, 0.25), Vector2(0.5, 0.18), Vector2(0.47, 0.18), Vector2(0.47, 0.25), Vector2(0.43, 0.25), Vector2(0.43, 0.13), Vector2(0.395, 0.13), Vector2(0.395, 0.25), Vector2(0.355, 0.25), Vector2(0.355, 0.2), Vector2(0.32, 0.2)]), -y, 0.05, lo, hi)
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 50.0, "yaw": 0.0}

## A prison cell door: flat-bar frame, round bars through a heavy crossbar, the lock box on the latch side, hinges.
func _cell(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var lo := Color(0.3, 0.3, 0.3)
	var hi := Color(0.44, 0.43, 0.42)
	var w := 1.1
	var h := 1.5
	for x: float in [-w * 0.5 + 0.04, w * 0.5 - 0.04]:
		k.box("steel", Vector3(x, h * 0.5, 0.0), Vector3(0.08, h, 0.06), lo, hi)
	for yy: float in [0.04, h - 0.04]:
		k.box("steel", Vector3(0.0, yy, 0.0), Vector3(w, 0.08, 0.06), lo, hi)
	var n := 5
	for i: int in range(n):
		var x := lerpf(-w * 0.5 + 0.08, w * 0.5 - 0.08, float(i + 1) / float(n + 1))
		k.lathe("steel", Vector3(x, 0.07, 0.0), PackedVector2Array([Vector2(0.036, 0.0), Vector2(0.036, h - 0.14)]), 12, lo, hi)
	# crossbar: two flat straps sandwiching the bars, riveted at each bar
	for z: float in [0.034, -0.034]:
		k.box("steel", Vector3(0.0, 0.74, z), Vector3(w, 0.12, 0.024), lo, hi)
	for i: int in range(n):
		var x := lerpf(-w * 0.5 + 0.08, w * 0.5 - 0.08, float(i + 1) / float(n + 1))
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.74, 0.044)))
		k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.022, 0.0), Vector2(0.018, 0.01), Vector2(0.0, 0.015)]), 10, lo, hi)
		k.pop()
	# lock box on the latch side, keyhole, the bolt shooting out past the stile
	var lx := w * 0.5 - 0.2
	k.box("blued", Vector3(lx, 0.74, 0.095), Vector3(0.32, 0.4, 0.1), Color(0.7, 0.7, 0.7), Color(0.9, 0.9, 0.9))
	k.box("blued", Vector3(w * 0.5 + 0.04, 0.68, 0.06), Vector3(0.14, 0.06, 0.04), Color(0.7, 0.7, 0.7), Color(0.8, 0.8, 0.8))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(lx, 0.72, 0.145)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.05, 0.008), Vector2(0.04, 0.014), Vector2(0.0, 0.016)]), 16, Color(0.75, 0.75, 0.75), Color(0.95, 0.95, 0.95))
	k.pop()
	k.box("rubber", Vector3(lx, 0.705, 0.162), Vector3(0.016, 0.045, 0.004), Color(0.1, 0.1, 0.1), Color(0.1, 0.1, 0.1))
	k.box("rubber", Vector3(lx, 0.732, 0.162), Vector3(0.03, 0.03, 0.004), Color(0.1, 0.1, 0.1), Color(0.1, 0.1, 0.1))
	# hinges on the left stile
	for yy: float in [0.28, 1.2]:
		k.lathe("steel", Vector3(-w * 0.5 - 0.035, yy - 0.09, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.18), Vector2(0.0, 0.18)]), 12, lo, hi)
	s._commit(k, parent)
	return {"pitch": 12.0, "yaw": 24.0}

## The Cockle Mk II folding canoe: canvas hull, a crowned deck, two cockpits and a double paddle laid across.
func _boat(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 + DIAG)), Vector3.ZERO))
	var length := 3.3
	var rows := 17
	var columns := 7
	var beam := 0.3
	for side: float in [1.0, -1.0]:
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for i: int in range(rows):
			var t := float(i) / float(rows - 1)
			var z := (t - 0.5) * length
			var breadth := beam * pow(sin(PI * t), 0.7)
			var sheer := _sheer(t)
			for j: int in range(columns):
				var sv := float(j) / float(columns - 1)
				var ang := lerpf(0.0, PI * 0.5, sv)
				pts.append(Vector3(side * breadth * sin(ang), -0.06 + (sheer + 0.06) * (1.0 - cos(ang)), z))
				uvs.append(Vector2(z * Kit.UV_M, sv * 0.3))
				cols.append(Color(0.42, 0.45, 0.36) * (0.72 + 0.38 * sv))
		k.patch("canvas", rows, columns, pts, uvs, cols, false, side < 0.0)
	# deck: a crowned patch from gunwale to gunwale
	var drows := 17
	var dcols := 7
	var dpts := PackedVector3Array()
	var duvs := PackedVector2Array()
	var dcol := PackedColorArray()
	for i: int in range(drows):
		var t := float(i) / float(drows - 1)
		var z := (t - 0.5) * length
		var breadth := beam * pow(sin(PI * t), 0.7)
		for j: int in range(dcols):
			var c := lerpf(-1.0, 1.0, float(j) / float(dcols - 1))
			dpts.append(Vector3(c * breadth, _sheer(t) + 0.06 * (1.0 - c * c) * breadth / beam, z))
			duvs.append(Vector2(z, c * breadth) * Kit.UV_M)
			dcol.append(Color(0.56, 0.56, 0.46) * (0.9 + 0.1 * (1.0 - c * c)))
	k.patch("canvas", drows, dcols, dpts, duvs, dcol, false, true)
	# the two cockpits: oval wooden coamings round a dark well
	for t: float in [0.36, 0.62]:
		var z := (t - 0.5) * length
		var y := _sheer(t) + 0.05
		k.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.75)), Vector3(0.0, y, z)))
		k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.19, -0.02), Vector2(0.19, 0.035), Vector2(0.175, 0.045), Vector2(0.16, 0.04)]), 20, Color(0.45, 0.36, 0.25), Color(0.6, 0.48, 0.33))
		k.disc("canvas", Vector3(0.0, 0.012, 0.0), 0.165, 20, Rect2(0.2, 0.2, 0.1, 0.1), Color(0.09, 0.09, 0.08))
		k.pop()
	# the double paddle lying across, between the cockpits
	var pc := Vector3(0.0, _sheer(0.5) + 0.1, (0.49 - 0.5) * length)
	var pdir := Vector3(cos(deg_to_rad(28.0)), 0.0, sin(deg_to_rad(28.0)))
	var plen := 1.9
	k.push(Transform3D(Basis(pdir, Vector3.UP, pdir.cross(Vector3.UP)).orthonormalized(), pc))
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-plen * 0.5, 0.0, 0.0)))
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.024, plen), Vector2(0.0, plen)]), 10, Color(0.62, 0.5, 0.34), Color(0.7, 0.57, 0.4), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	k.pop()
	# the blades: flat spoons at each end (local X along the shaft, slab lying in the X-Z plane)
	for e: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(e * (plen * 0.5 - 0.2), 0.0, 0.0)))
		var blade := PackedVector2Array()
		for i: int in range(20):
			var a := TAU * float(i) / 20.0
			blade.append(Vector2(cos(a) * 0.24, sin(a) * 0.085 * (1.0 + 0.25 * cos(a) * e)))
		_slab(k, "planks", blade, 0.0, 0.018, Color(0.6, 0.48, 0.32), Color(0.7, 0.56, 0.38), true)
		k.pop()
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 42.0, "yaw": 0.0, "margin": 0.04}

func _sheer(t: float) -> float:
	return 0.2 + 0.07 * pow(absf(t - 0.5) * 2.0, 2.0)

## The mission dossier: a manila card folder lying a little open, the typed top sheet half out, the red cord loose.
func _brief(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(8.0)), Vector3.ZERO))
	var buff_lo := Color(0.72, 0.58, 0.38)
	var buff_hi := Color(0.8, 0.65, 0.43)
	var paper_lo := Color(0.86, 0.85, 0.8)
	var paper_hi := Color(0.92, 0.91, 0.86)
	var wd := 0.8
	var dp := 1.04
	k.box("a_bright", Vector3(wd * 0.5, 0.006, 0.0), Vector3(wd, 0.012, dp), buff_lo, buff_hi, Vector2(-0.26, 0.0))
	# the sheets inside, their edges showing
	for i: int in range(2):
		k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(2.5 - 4.5 * float(i))), Vector3(wd * 0.5 + 0.03 + 0.02 * float(i), 0.016 + 0.005 * float(i), 0.01 - 0.02 * float(i))))
		k.box("a_bright", Vector3.ZERO, Vector3(wd - 0.06, 0.004, dp - 0.08), paper_lo * (0.96 - 0.03 * float(i)), paper_hi * (0.96 - 0.03 * float(i)))
		k.pop()
	# the top sheet, slid half out towards the front right, typed (grey lines, no letters) with a red stamp box
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-9.0)), Vector3(wd * 0.5 + 0.2, 0.03, 0.2)))
	k.box("a_bright", Vector3.ZERO, Vector3(wd - 0.06, 0.004, dp - 0.08), paper_lo, paper_hi)
	var ink := Color(0.34, 0.34, 0.37)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	k.box("a_bright", Vector3(-0.12, 0.0025, -0.4), Vector3(0.36, 0.001, 0.02), ink, ink)
	for r: int in range(13):
		var z := -0.3 + 0.058 * float(r)
		if r == 4 or r == 9:
			continue
		var x1 := 0.3 - (rng.randf_range(0.05, 0.3) if r == 3 or r == 8 or r == 12 else 0.0)
		k.box("a_bright", Vector3((x1 - 0.3) * 0.5, 0.0025, z), Vector3(x1 + 0.3, 0.001, 0.016), ink, ink)
	var red := Color(0.7, 0.16, 0.12)
	var sc := Vector3(0.2, 0.0028, -0.4)
	for e: Vector3 in [Vector3(0.0, 0.0, -0.045), Vector3(0.0, 0.0, 0.045)]:
		k.box("a_bright", sc + e, Vector3(0.2, 0.001, 0.012), red, red)
	for e: Vector3 in [Vector3(-0.094, 0.0, 0.0), Vector3(0.094, 0.0, 0.0)]:
		k.box("a_bright", sc + e, Vector3(0.012, 0.001, 0.1), red, red)
	# a paper clip over the right edge
	var clip := PackedVector3Array()
	for p: Vector2 in [Vector2(0.3, -0.12), Vector2(0.39, -0.12), Vector2(0.405, -0.09), Vector2(0.39, -0.06), Vector2(0.27, -0.06), Vector2(0.255, -0.085), Vector2(0.27, -0.11), Vector2(0.37, -0.11), Vector2(0.38, -0.09), Vector2(0.37, -0.075), Vector2(0.31, -0.075)]:
		clip.append(Vector3(p.x, 0.008, p.y))
	k.tube("blade", clip, 0.007, 5, Color(0.85, 0.86, 0.88))
	k.pop()
	# the front cover, hinged at the spine (x = 0) and lifted a little
	var cover := Transform3D(Basis(Vector3.BACK, deg_to_rad(16.0)), Vector3(0.0, 0.036, 0.0))
	k.push(cover)
	k.box("a_bright", Vector3(wd * 0.5, 0.006, 0.0), Vector3(wd, 0.012, dp), buff_lo * 1.03, buff_hi * 1.03, Vector2(-0.26, 0.0))
	k.lathe("brass", Vector3(wd - 0.1, 0.012, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.006), Vector2(0.0, 0.008)]), 16, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.pop()
	# the spine fold
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.024, -dp * 0.5)))
	k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.024, dp), Vector2(0.0, dp)]), 10, buff_lo * 0.92, buff_lo * 0.92)
	k.pop()
	# the red cord: wound round the button, then loose over the edge and onto the table
	var cord := PackedVector3Array()
	var bx := wd - 0.1
	for i: int in range(13):
		var a := TAU * 1.3 * float(i) / 12.0
		cord.append(cover * Vector3(bx + cos(a) * 0.05, 0.022, -sin(a) * 0.05))
	var last := cord[cord.size() - 1]
	var edge := cover * Vector3(wd + 0.01, 0.02, -0.12)
	cord.append(last.lerp(edge, 0.5) + Vector3(0, 0.01, 0))
	cord.append(edge)
	cord.append(Vector3(edge.x + 0.07, 0.06, -0.16))
	cord.append(Vector3(edge.x + 0.14, 0.05, -0.2))
	cord.append(Vector3(edge.x + 0.2, 0.05, -0.12))
	k.tube("a_bright", cord, 0.014, 6, Color(0.72, 0.13, 0.1))
	_cap(k, "a_bright", cord[cord.size() - 1], cord[cord.size() - 1] - cord[cord.size() - 2], 0.014, Color(0.6, 0.1, 0.08))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 52.0, "yaw": 0.0}

## A short binding cord tied in a loop, the knot standing up with its two ends.
func _bind(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var col := Color(0.74, 0.69, 0.57)
	var r := 0.036
	var big := 0.34
	var a0 := deg_to_rad(40.0)
	var out := Vector3(cos(a0), 0.0, -sin(a0))
	var knot := out * big + Vector3(0.0, r, 0.0)
	var loop := PackedVector3Array()
	var steps := 48
	for i: int in range(steps + 1):
		var a := a0 + 0.12 + (TAU - 0.24) * float(i) / float(steps)
		var rr := big * (1.0 + 0.05 * sin(a * 3.0 + 0.7))
		loop.append(Vector3(cos(a) * rr, r + 0.012 * sin(a * 2.0), -sin(a) * rr))
	loop.insert(0, knot + Vector3(0.0, 0.02, 0.0) - Vector3(-out.z, 0.0, out.x) * 0.05)
	loop.append(knot + Vector3(0.0, 0.02, 0.0) + Vector3(-out.z, 0.0, out.x) * 0.05)
	k.tube("a_cord", loop, r, 8, col, Vector2.ZERO, 0.25, 3.0)
	# the knot: a tight trefoil lying across the join
	var side := Vector3(-out.z, 0.0, out.x)
	var tre := PackedVector3Array()
	for i: int in range(73):
		var t := TAU * float(i) / 72.0
		var p := Vector3(sin(t) + 2.0 * sin(2.0 * t), cos(t) - 2.0 * cos(2.0 * t), -sin(3.0 * t)) * 0.032
		tre.append(knot + Vector3(0.0, 0.035, 0.0) + side * p.x + out * p.y + Vector3.UP * p.z)
	k.tube("a_cord", tre, r * 0.95, 8, col * 0.94, Vector2(0.3, 0.0), 0.25, 3.0)
	# the two ends, splaying out of the knot
	for e: float in [1.0, -1.0]:
		var tail := PackedVector3Array()
		for i: int in range(8):
			var t := float(i) / 7.0
			tail.append(knot + Vector3(0.0, 0.04 * (1.0 - t), 0.0) + out * (0.04 + 0.3 * t) + side * e * (0.03 + 0.09 * t * t))
		k.tube("a_cord", tail, r * 0.92, 8, col * 0.97, Vector2(0.6 * e, 0.0), 0.25, 3.0)
		var end := tail[tail.size() - 1]
		var d := (end - tail[tail.size() - 2]).normalized()
		_cap(k, "a_cord", end, d, r * 0.92, col * 0.7)
	s._commit(k, parent)
	return {"pitch": 52.0, "yaw": 0.0}

## A British service revolver (Webley / Enfield): top-break frame, fluted cylinder, bird's-head grip, lanyard ring.
## It lies on its right side, muzzle to the right, seen from above.
func _revolver(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var lo := Color(0.82, 0.83, 0.87)
	var hi := Color(1.0, 1.0, 1.0)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(14.0)) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.1, 0.0)))
	# frame, grip frame and top strap in one plate
	_slab(k, "blued", _grip_squash(PackedVector2Array([Vector2(0.115, 0.122), Vector2(-0.12, 0.125), Vector2(-0.15, 0.09), Vector2(-0.165, 0.04), Vector2(-0.175, -0.01), Vector2(-0.215, -0.1), Vector2(-0.265, -0.2), Vector2(-0.305, -0.28), Vector2(-0.33, -0.33), Vector2(-0.335, -0.37), Vector2(-0.32, -0.4), Vector2(-0.29, -0.415), Vector2(-0.25, -0.41), Vector2(-0.22, -0.395), Vector2(-0.2, -0.36), Vector2(-0.175, -0.29), Vector2(-0.145, -0.21), Vector2(-0.11, -0.14), Vector2(-0.085, -0.112), Vector2(-0.05, -0.105), Vector2(0.08, -0.105), Vector2(0.13, -0.095), Vector2(0.15, -0.07), Vector2(0.15, -0.04), Vector2(0.115, 0.02)])), 0.0, 0.08, lo, hi)
	# grip stocks (chequered vulcanite)
	_slab(k, "rubber", _grip_squash(PackedVector2Array([Vector2(-0.185, -0.04), Vector2(-0.225, -0.12), Vector2(-0.27, -0.21), Vector2(-0.305, -0.29), Vector2(-0.318, -0.345), Vector2(-0.3, -0.375), Vector2(-0.255, -0.38), Vector2(-0.215, -0.355), Vector2(-0.19, -0.29), Vector2(-0.16, -0.21), Vector2(-0.125, -0.14), Vector2(-0.13, -0.08)])), 0.0, 0.13, Color(0.5, 0.38, 0.28), Color(0.62, 0.48, 0.36), true)
	# hammer, the barrel latch on the left side, the hinge screw
	_slab(k, "blued", PackedVector2Array([Vector2(-0.11, 0.1), Vector2(-0.122, 0.138), Vector2(-0.15, 0.162), Vector2(-0.18, 0.172), Vector2(-0.196, 0.165), Vector2(-0.19, 0.15), Vector2(-0.162, 0.128), Vector2(-0.148, 0.085)]), 0.0, 0.04, lo, hi)
	_slab(k, "blued", PackedVector2Array([Vector2(-0.14, 0.11), Vector2(-0.095, 0.11), Vector2(-0.095, 0.085), Vector2(-0.16, 0.035), Vector2(-0.175, 0.045)]), 0.046, 0.014, lo, hi)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.128, -0.07, 0.04)))
	k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.022, 0.0), Vector2(0.02, 0.006), Vector2(0.0, 0.008)]), 12, hi, hi)
	k.pop()
	# barrel, its rib and front sight, the lug underneath
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.095, 0.052, 0.0)))
	k.lathe("blued", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.037, 0.44), Vector2(0.041, 0.45), Vector2(0.041, 0.48), Vector2(0.026, 0.486), Vector2(0.0, 0.486)]), 18, lo, hi)
	k.pop()
	k.box("blued", Vector3(0.34, 0.094, 0.0), Vector3(0.47, 0.022, 0.026), lo, hi)
	k.box("blued", Vector3(0.555, 0.115, 0.0), Vector3(0.035, 0.035, 0.012), lo, hi)
	_slab(k, "blued", PackedVector2Array([Vector2(0.095, 0.03), Vector2(0.095, -0.06), Vector2(0.135, -0.085), Vector2(0.17, -0.07), Vector2(0.3, 0.02), Vector2(0.3, 0.035)]), 0.0, 0.075, lo, hi)
	# the cylinder
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.085, 0.0, 0.0)))
	_fluted(k, "blued", Vector3.ZERO, 0.092, 0.18, 6, lo, hi)
	k.pop()
	# trigger guard and trigger
	var guard := PackedVector3Array()
	for i: int in range(17):
		var a := PI * (1.0 + float(i) / 16.0)
		guard.append(Vector3(-0.02 + cos(a) * 0.075, -0.1 + sin(a) * 0.115, 0.0))
	k.tube("blued", guard, 0.014, 6, hi)
	k.beam("blued", Vector3(-0.02, -0.1, 0.0), Vector3(-0.04, -0.175, 0.0), 0.022, 0.016, lo, hi, Vector2.ZERO, false, Vector3.BACK)
	# lanyard ring at the butt
	_torus(k, "blued", Vector3(-0.29, -0.395, 0.0), Basis(Vector3.RIGHT, PI * 0.5), 0.044, 0.011, 20, 6, hi, hi)
	k.pop()
	s._commit(k, parent)
	return {"pitch": 62.0, "yaw": 0.0}

## The grip part of an outline (below the frame) drawn up a little: a shorter, more raked butt.
func _grip_squash(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(Vector2(p.x, -0.1 + (p.y + 0.1) * 0.85) if p.y < -0.1 else p)
	return out

## A tripwire: a wooden peg in a grassy tuft, the wire taut to a second peg, a tin can hanging on it.
func _tripwire(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(44.0)), Vector3.ZERO))
	_tuft(k, Vector3.ZERO, 0.3, 26, 3)
	var wood_lo := Color(0.5, 0.42, 0.3)
	var wood_hi := Color(0.68, 0.58, 0.42)
	var wire := Color(0.9, 0.9, 0.88)
	var lean := Basis(Vector3.BACK, deg_to_rad(8.0))
	k.push(Transform3D(lean, Vector3.ZERO))
	k.box("planks", Vector3(0.0, 0.28, 0.0), Vector3(0.08, 0.56, 0.08), wood_lo, wood_hi)
	k.box("planks", Vector3(0.0, 0.59, 0.0), Vector3(0.1, 0.06, 0.1), wood_hi, wood_hi)
	k.box("planks", Vector3(0.05, 0.5, 0.0), Vector3(0.03, 0.035, 0.065), wood_lo * 0.6, wood_lo * 0.6)
	k.pop()
	var a := lean * Vector3(0.045, 0.5, 0.0)
	var far := Vector3(1.4, 0.0, 0.0)
	_tuft(k, far, 0.16, 10, 9, 0.12)
	k.box("planks", far + Vector3(0.0, 0.16, 0.0), Vector3(0.055, 0.34, 0.055), wood_lo, wood_hi)
	var b := far + Vector3(-0.028, 0.28, 0.0)
	var hang := a.lerp(b, 0.5) + Vector3(0, -0.015, 0)
	k.tube("steel", PackedVector3Array([a, hang, b]), 0.014, 5, wire)
	# the can on its wire hook, open at the top, a few pebbles inside to rattle
	var can_top := hang + Vector3(0.0, -0.085, 0.0)
	k.tube("steel", PackedVector3Array([hang + Vector3(-0.024, 0.014, 0), hang + Vector3(0.0, 0.026, 0), hang + Vector3(0.024, 0.0, 0), can_top + Vector3(0.0, 0.004, 0.0)]), 0.008, 4, wire)
	k.tube("steel", PackedVector3Array([can_top + Vector3(-0.094, -0.024, 0), can_top + Vector3(-0.036, -0.002, 0), can_top + Vector3(0.036, -0.002, 0), can_top + Vector3(0.094, -0.024, 0)]), 0.007, 4, wire)
	var cb := can_top + Vector3(0.0, -0.23, 0.0)
	var outer := PackedVector2Array()
	for p: Vector2 in [Vector2(0.0, 0.0), Vector2(0.072, 0.0), Vector2(0.076, 0.006), Vector2(0.076, 0.055), Vector2(0.08, 0.06), Vector2(0.076, 0.065), Vector2(0.076, 0.12), Vector2(0.08, 0.125), Vector2(0.076, 0.13), Vector2(0.076, 0.168), Vector2(0.08, 0.172), Vector2(0.075, 0.176), Vector2(0.071, 0.17)]:
		outer.append(p * 1.2)
	k.lathe("a_tin", cb, outer, 24, Color(0.68, 0.68, 0.66), Color(0.92, 0.92, 0.9))
	k.lathe("a_tin", cb, PackedVector2Array([Vector2(0.085, 0.204), Vector2(0.085, 0.012)]), 24, Color(0.32, 0.32, 0.31), Color(0.55, 0.55, 0.53))
	k.disc("a_tin", cb + Vector3(0.0, 0.012, 0.0), 0.085, 24, Rect2(0.1, 0.1, 0.1, 0.1), Color(0.3, 0.3, 0.29))
	for p: Vector3 in [Vector3(0.024, 0.03, 0.012), Vector3(-0.03, 0.026, -0.014), Vector3(0.0, 0.028, -0.036)]:
		k.lathe("a_pebble", cb + p, PackedVector2Array([Vector2(0.0, -0.014), Vector2(0.026, -0.01), Vector2(0.03, 0.0), Vector2(0.024, 0.012), Vector2(0.0, 0.016)]), 8, Color(0.45, 0.44, 0.42), Color(0.6, 0.59, 0.56))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 32.0, "yaw": 0.0}

## A small signal flag (red and yellow, halved on the diagonal) on a short pole stuck in a tuft.
func _flag(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	_tuft(k, Vector3.ZERO, 0.24, 22, 5, 0.16)
	k.lathe("planks", Vector3(0.0, 0.02, 0.0), PackedVector2Array([Vector2(0.026, 0.0), Vector2(0.024, 1.08), Vector2(0.034, 1.09), Vector2(0.034, 1.12), Vector2(0.0, 1.14)]), 10, Color(0.5, 0.42, 0.3), Color(0.68, 0.58, 0.42), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	var fw := 0.64
	var fh := 0.54
	var top := 1.08
	var n := 11
	for half: int in range(2):
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for i: int in range(n):
			var t := float(i) / float(n - 1)
			for j: int in range(n):
				var sv := float(j) / float(n - 1)
				var u := sv * t if half == 0 else t
				var v := t if half == 0 else sv * t
				var x := 0.03 + u * fw
				var y := top - fh + v * fh - 0.06 * u * u
				var z := sin(u * 4.6 - 0.4) * 0.07 * u + 0.02 * sin(v * 3.0) * u
				pts.append(Vector3(x, y, z))
				uvs.append(Vector2(u * 0.4, v * 0.35))
				var shade := 0.82 + 0.18 * v
				cols.append((Color(0.86, 0.15, 0.1) if half == 0 else Color(1.0, 0.84, 0.22)) * shade)
		k.patch("a_bright", n, n, pts, uvs, cols, false, false)
		k.patch("a_bright", n, n, pts, uvs, cols, false, true)
	# the toggle line down the hoist
	k.tube("a_bright", PackedVector3Array([Vector3(0.03, top + 0.01, 0.0), Vector3(0.03, top - fh - 0.01, 0.0)]), 0.012, 5, Color(0.85, 0.82, 0.74))
	s._commit(k, parent)
	return {"pitch": 22.0, "yaw": -22.0, "margin": 0.06}

## A made-up demolition charge: canvas-wrapped block, two leather straps, a time pencil, a coil of detonating cord.
func _charge(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-18.0)), Vector3.ZERO))
	var size := Vector3(0.82, 0.36, 0.54)
	_softbox(k, "canvas", Vector3.ZERO, size, 0.08, Color(0.4, 0.42, 0.3), Color(0.6, 0.62, 0.46))
	for x: float in [-0.22, 0.22]:
		_strap(k, "a_leather", x, size.z * 0.5, size.y, 0.08, 0.075, Color(0.45, 0.31, 0.19))
		k.box("blade", Vector3(x, size.y + 0.02, 0.1), Vector3(0.1, 0.012, 0.075), Color(0.55, 0.55, 0.55), Color(0.7, 0.7, 0.7))
		k.box("a_leather", Vector3(x, size.y + 0.025, 0.1), Vector3(0.076, 0.012, 0.05), Color(0.4, 0.28, 0.17), Color(0.4, 0.28, 0.17))
	# the time pencil, pushed into the top at the right end, leaning out
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(-38.0)), Vector3(0.36, size.y - 0.04, -0.04)))
	k.lathe("a_copper", Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.02), Vector2(0.03, -0.02), Vector2(0.03, 0.15), Vector2(0.028, 0.16)]), 14, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.028, 0.16), Vector2(0.033, 0.165), Vector2(0.033, 0.41), Vector2(0.038, 0.42), Vector2(0.038, 0.455), Vector2(0.0, 0.46)]), 14, Color(0.85, 0.85, 0.85), Color(1, 1, 1))
	k.box("paint", Vector3(0.0, 0.34, 0.0), Vector3(0.014, 0.04, 0.11), Color(0.75, 0.14, 0.1), Color(0.8, 0.16, 0.12))
	k.pop()
	# detonating cord: a coil on the table at the front left, its end running into the charge
	var coil := PackedVector3Array()
	var c0 := Vector3(-0.62, 0.0, 0.32)
	var turns := 4
	var per := 24
	for i: int in range(turns * per + 1):
		var a := TAU * float(i) / float(per)
		var t := float(i) / float(turns * per)
		var r := 0.2 - 0.1 * t + 0.008 * sin(a * 3.0)
		coil.append(c0 + Vector3(cos(a) * r, 0.022 + 0.018 * t + 0.008 * sin(a * 2.0), -sin(a) * r))
	coil.insert(0, c0 + Vector3(0.3, 0.025, 0.05))
	coil.insert(0, Vector3(-0.3, 0.05, 0.34))
	coil.insert(0, Vector3(-0.24, 0.15, size.z * 0.5 - 0.01))
	k.tube("a_bright", coil, 0.022, 6, Color(0.76, 0.47, 0.24), Vector2.ZERO, 0.25, 3.0)
	_cap(k, "a_bright", coil[coil.size() - 1], coil[coil.size() - 1] - coil[coil.size() - 2], 0.022, Color(0.66, 0.36, 0.16))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 34.0, "yaw": 0.0, "margin": 0.05}

## A knife switch on a slate base board: copper hinge clips and jaws, the twin blades lifted on their ebonite
## handle, a danger plate between the clips and the cables off each end.
func _switch(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var cu := Color(0.95, 0.95, 0.95)
	var ink := Color(0.08, 0.075, 0.07)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(24.0)), Vector3.ZERO))
	k.box("planks", Vector3(0.0, 0.025, 0.0), Vector3(1.14, 0.05, 0.62), Color(0.36, 0.23, 0.15), Color(0.46, 0.3, 0.2))
	k.box("paint", Vector3(0.0, 0.075, 0.0), Vector3(1.0, 0.05, 0.5), Color(0.2, 0.21, 0.22), Color(0.27, 0.28, 0.29))
	var top := 0.1
	for p: Vector2 in [Vector2(-0.45, -0.2), Vector2(0.45, -0.2), Vector2(-0.45, 0.2), Vector2(0.45, 0.2)]:
		k.lathe("brass", Vector3(p.x, top, p.y), PackedVector2Array([Vector2(0.024, 0.0), Vector2(0.02, 0.01), Vector2(0.0, 0.014)]), 12, Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95))
	var hinge_x := -0.3
	var jaw_x := 0.3
	for z: float in [-0.12, 0.12]:
		k.box("a_copper", Vector3(hinge_x, top + 0.0125, z), Vector3(0.14, 0.025, 0.11), cu * 0.8, cu)
		for dz: float in [-0.026, 0.026]:
			k.box("a_copper", Vector3(hinge_x, top + 0.06, z + dz), Vector3(0.08, 0.1, 0.014), cu * 0.8, cu)
		k.box("a_copper", Vector3(jaw_x, top + 0.0125, z), Vector3(0.12, 0.025, 0.11), cu * 0.8, cu)
		for dz: float in [-0.021, 0.021]:
			k.box("a_copper", Vector3(jaw_x, top + 0.065, z + dz), Vector3(0.07, 0.11, 0.012), cu * 0.8, cu)
		# terminals at the ends, copper straps to the clips, the cables away off the board
		for e: float in [-1.0, 1.0]:
			var tx := e * 0.43
			k.box("a_copper", Vector3((tx + e * 0.3) * 0.5, top + 0.005, z), Vector3(0.14, 0.01, 0.05), cu * 0.8, cu * 0.9)
			k.lathe("brass", Vector3(tx, top, z), PackedVector2Array([Vector2(0.034, 0.0), Vector2(0.034, 0.03), Vector2(0.026, 0.042), Vector2(0.0, 0.044)]), 12, Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95))
			k.tube("rubber", PackedVector3Array([Vector3(tx, top + 0.035, z), Vector3(tx + e * 0.08, top + 0.045, z), Vector3(tx + e * 0.17, top + 0.0, z + 0.03 * e), Vector3(tx + e * 0.24, 0.03, z + 0.09 * e), Vector3(tx + e * 0.3, 0.02, z + 0.17 * e)]), 0.024, 6, Color(0.55, 0.55, 0.55))
	# the danger plate lying on the slate between the clips: cream enamel with a red bolt
	k.box("a_bright", Vector3(0.0, top + 0.004, 0.0), Vector3(0.2, 0.008, 0.16), Color(0.9, 0.88, 0.82), Color(0.92, 0.9, 0.84))
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, top + 0.009, 0.0)))
	_slab(k, "a_bright", PackedVector2Array([Vector2(0.025, 0.065), Vector2(-0.03, -0.005), Vector2(0.0, -0.005), Vector2(-0.025, -0.065), Vector2(0.035, 0.012), Vector2(0.005, 0.012), Vector2(0.04, 0.065)]), 0.0, 0.006, Color(0.8, 0.12, 0.08), Color(0.8, 0.12, 0.08))
	k.pop()
	# the blades, lifted out of the jaws on the pivot
	k.push(Transform3D(Basis(Vector3.BACK, deg_to_rad(50.0)), Vector3(hinge_x, top + 0.075, 0.0)))
	for z: float in [-0.12, 0.12]:
		k.box("a_copper", Vector3(0.29, 0.0, z), Vector3(0.62, 0.065, 0.022), cu * 0.85, cu)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -0.17)))
	k.lathe("brass", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 0.34), Vector2(0.0, 0.34)]), 10, Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	k.pop()
	k.box("a_gloss", Vector3(0.52, 0.0, 0.0), Vector3(0.065, 0.07, 0.34), ink, ink * 1.4)
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.55, 0.0, 0.0)))
	k.lathe("a_gloss", Vector3.ZERO, PackedVector2Array([Vector2(0.028, 0.0), Vector2(0.032, 0.04), Vector2(0.042, 0.15), Vector2(0.04, 0.2), Vector2(0.026, 0.226), Vector2(0.0, 0.232)]), 14, ink, ink * 1.5)
	k.pop()
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 34.0, "yaw": 0.0, "margin": 0.05}

## A cigarette lying across an open matchbox, the tray pushed out with its matches.
func _cigarette(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var bl := 0.46
	var bw := 0.32
	var bh := 0.13
	var card := 0.01
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-14.0)), Vector3.ZERO))
	var sx := -0.1
	# the sleeve: top (with its label), bottom, two striking sides
	k.box("a_bright", Vector3(sx, bh - card * 0.5, 0.0), Vector3(bl, card, bw), Color(0.86, 0.8, 0.64), Color(0.9, 0.84, 0.68))
	k.box("a_bright", Vector3(sx, card * 0.5, 0.0), Vector3(bl, card, bw), Color(0.7, 0.64, 0.5), Color(0.7, 0.64, 0.5))
	for z: float in [bw * 0.5 - card * 0.5, -bw * 0.5 + card * 0.5]:
		k.box("a_bright", Vector3(sx, bh * 0.5, z), Vector3(bl, bh, card), Color(0.72, 0.66, 0.5), Color(0.8, 0.74, 0.58))
		k.box("concrete", Vector3(sx, bh * 0.5, z + signf(z) * 0.007), Vector3(bl - 0.04, bh * 0.66, 0.004), Color(0.34, 0.2, 0.15), Color(0.38, 0.22, 0.16))
	# label: a terracotta field crossed by a cream band
	k.box("a_bright", Vector3(sx, bh + 0.002, 0.0), Vector3(bl - 0.05, 0.003, bw - 0.05), Color(0.52, 0.27, 0.18), Color(0.52, 0.27, 0.18))
	k.box("a_bright", Vector3(sx, bh + 0.0045, 0.0), Vector3(bl - 0.05, 0.003, 0.07), Color(0.84, 0.78, 0.6), Color(0.84, 0.78, 0.6))
	# the tray, pushed out to the right
	var tx := sx + 0.2
	var wood_lo := Color(0.8, 0.7, 0.52)
	var wood_hi := Color(0.88, 0.78, 0.58)
	var ih := bh - card * 2.0 - 0.004
	k.box("a_bright", Vector3(tx, card + 0.003, 0.0), Vector3(bl - 0.01, 0.006, bw - card * 2.0 - 0.004), wood_lo, wood_hi)
	for z: float in [bw * 0.5 - card - 0.007, -bw * 0.5 + card + 0.007]:
		k.box("a_bright", Vector3(tx, card + ih * 0.5, z), Vector3(bl - 0.01, ih, 0.008), wood_lo, wood_hi)
	for x: float in [tx - bl * 0.5 + 0.009, tx + bl * 0.5 - 0.009]:
		k.box("a_bright", Vector3(x, card + ih * 0.5, 0.0), Vector3(0.008, ih, bw - card * 2.0 - 0.004), wood_lo, wood_hi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i: int in range(7):
		var z := lerpf(-0.105, 0.105, float(i) / 6.0) + rng.randf_range(-0.006, 0.006)
		var y := card + 0.02 + rng.randf_range(0.0, 0.03)
		_match(k, Vector3(tx - 0.2, y, z), 0.37, rng.randf_range(-3.0, 3.0))
	k.pop()
	# two loose matches on the table in front
	_match(k, Vector3(-0.3, 0.012, 0.3), 0.37, 8.0)
	_match(k, Vector3(-0.22, 0.012, 0.36), 0.37, -6.0)
	# the cigarette, across the sleeve
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(DIAG)), Vector3(-0.1, bh + 0.036, 0.02)))
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.36, 0.0, 0.0)))
	var cr := 0.034
	k.lathe("burlap", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(cr - 0.004, 0.0), Vector2(cr, 0.004)]), 16, Color(0.55, 0.36, 0.2), Color(0.6, 0.4, 0.22))
	k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(cr, 0.004), Vector2(cr, 0.58)]), 16, Color(0.95, 0.94, 0.9), Color(0.95, 0.94, 0.9))
	k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(cr + 0.001, 0.58), Vector2(cr + 0.001, 0.72), Vector2(cr - 0.004, 0.722), Vector2(0.0, 0.722)]), 16, Color(0.85, 0.62, 0.35), Color(0.85, 0.62, 0.35))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 44.0, "yaw": 0.0}

## A match along +X from `at` (its head at the far end), turned `yaw` degrees.
func _match(k: Kit, at: Vector3, length: float, yaw: float) -> void:
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at))
	k.box("a_bright", Vector3(length * 0.5, 0.0, 0.0), Vector3(length, 0.022, 0.022), Color(0.85, 0.74, 0.54), Color(0.9, 0.8, 0.6))
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(length - 0.01, 0.0, 0.0)))
	k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.02, 0.006), Vector2(0.022, 0.03), Vector2(0.016, 0.046), Vector2(0.0, 0.05)]), 10, Color(0.6, 0.12, 0.08), Color(0.7, 0.16, 0.1))
	k.pop()
	k.pop()

## A short section of an iron estate gate: spear-topped bars, rails, a ring row, a padlock on a chain.
func _gate(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var lo := Color(0.2, 0.21, 0.2)
	var hi := Color(0.3, 0.31, 0.3)
	var w := 1.2
	var h := 1.0
	k.box("paint", Vector3(-w * 0.5, (h + 0.12) * 0.5, 0.0), Vector3(0.075, h + 0.12, 0.075), lo, hi)
	k.lathe("paint", Vector3(-w * 0.5, h + 0.12, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.03, 0.02), Vector2(0.05, 0.05), Vector2(0.06, 0.09), Vector2(0.045, 0.13), Vector2(0.0, 0.15)]), 14, lo, hi)
	k.box("paint", Vector3(w * 0.5, (h + 0.06) * 0.5, 0.0), Vector3(0.055, h + 0.06, 0.055), lo, hi)
	for y: float in [0.07, 0.34, h - 0.2, h - 0.03]:
		k.box("paint", Vector3(0.0, y, 0.0), Vector3(w, 0.045, 0.035), lo, hi)
	var arch_n := 16
	for i: int in range(arch_n):
		var x0 := lerpf(-w * 0.5, w * 0.5, float(i) / float(arch_n))
		var x1 := lerpf(-w * 0.5, w * 0.5, float(i + 1) / float(arch_n))
		k.beam("paint", Vector3(x0, _arch(x0, w, h), 0.0), Vector3(x1, _arch(x1, w, h), 0.0), 0.035, 0.045, lo, hi, Vector2.ZERO, false)
	var n := 7
	var gap := w / float(n + 1)
	for i: int in range(n):
		var x := -w * 0.5 + gap * float(i + 1)
		var top := _arch(x, w, h)
		k.lathe("paint", Vector3(x, 0.07, 0.0), PackedVector2Array([Vector2(0.021, 0.0), Vector2(0.021, top + 0.02)]), 8, lo, hi)
		k.push(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(x, top + 0.12, 0.0)))
		k.lathe("paint", Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.026, -0.02), Vector2(0.055, 0.025), Vector2(0.0, 0.14)]), 4, lo, hi)
		k.pop()
	# dog bars below the low rail and rings between the two top rails, each between a pair of bars
	for i: int in range(n + 1):
		var x := -w * 0.5 + gap * (float(i) + 0.5)
		k.lathe("paint", Vector3(x, 0.07, 0.0), PackedVector2Array([Vector2(0.013, 0.0), Vector2(0.013, 0.27)]), 8, lo, hi)
		_torus(k, "paint", Vector3(x, h - 0.115, 0.0), Basis(Vector3.RIGHT, PI * 0.5), 0.048, 0.012, 18, 6, lo, hi)
	# the chain round the latch stile and the padlock hanging off it
	var cx := w * 0.5
	var steel_lo := Color(0.5, 0.5, 0.5)
	var steel_hi := Color(0.72, 0.72, 0.72)
	_torus(k, "blade", Vector3(cx, 0.66, 0.0), Basis(Vector3.RIGHT, deg_to_rad(8.0)), 0.06, 0.011, 18, 6, steel_lo, steel_hi)
	for i: int in range(3):
		var b := Basis(Vector3.FORWARD, PI * 0.5) if i % 2 == 0 else Basis(Vector3.RIGHT, PI * 0.5)
		_torus(k, "blade", Vector3(cx, 0.615 - 0.065 * float(i), 0.062), b, 0.035, 0.011, 14, 6, steel_lo, steel_hi)
	k.push(Transform3D(Basis.IDENTITY, Vector3(cx, 0.27, 0.07)))
	var body := PackedVector2Array()
	for i: int in range(28):
		var a := TAU * float(i) / 28.0
		body.append(Vector2(signf(cos(a)) * pow(absf(cos(a)), 0.4) * 0.1, signf(sin(a)) * pow(absf(sin(a)), 0.4) * 0.11))
	_slab(k, "brass", body, 0.0, 0.08, Color(0.8, 0.8, 0.8), Color(1.0, 1.0, 1.0), true)
	var shackle := PackedVector3Array()
	for i: int in range(13):
		var a := PI * float(i) / 12.0
		shackle.append(Vector3(cos(a) * 0.058, 0.125 + sin(a) * 0.08, 0.0))
	shackle.insert(0, Vector3(0.058, 0.09, 0.0))
	shackle.append(Vector3(-0.058, 0.09, 0.0))
	k.tube("blade", shackle, 0.016, 6, Color(0.75, 0.75, 0.75))
	k.box("rubber", Vector3(0.0, -0.04, 0.041), Vector3(0.018, 0.045, 0.003), Color(0.1, 0.1, 0.1), Color(0.1, 0.1, 0.1))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.01, 0.04)))
	k.lathe("rubber", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.016, 0.003), Vector2(0.0, 0.004)]), 10, Color(0.1, 0.1, 0.1), Color(0.1, 0.1, 0.1))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 12.0, "yaw": 22.0}

## Height of the gate's arched top rail at x.
func _arch(x: float, w: float, h: float) -> float:
	var u := 2.0 * x / w
	return h + 0.03 + 0.16 * (1.0 - u * u)

## A leather cosh: a short stitched club swelling to a heavy head, the wrist strap looped from the butt.
func _cosh(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var lo := Color(0.46, 0.3, 0.18)
	var hi := Color(0.62, 0.42, 0.26)
	var y := 0.11
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(DIAG)), Vector3.ZERO))
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.052, 0.012), Vector2(0.055, 0.035), Vector2(0.046, 0.055), Vector2(0.042, 0.075), Vector2(0.043, 0.3), Vector2(0.05, 0.36), Vector2(0.068, 0.42), Vector2(0.09, 0.48), Vector2(0.104, 0.54), Vector2(0.11, 0.6), Vector2(0.106, 0.66), Vector2(0.092, 0.71), Vector2(0.066, 0.745), Vector2(0.034, 0.762), Vector2(0.0, 0.766)])
	k.push(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, y, 0.0)))
	k.lathe("a_leather", Vector3.ZERO, prof, 22, lo, hi)
	# binding rings where the grip meets the head
	for p: float in [0.28, 0.31]:
		k.lathe("a_leather", Vector3(0.0, p, 0.0), PackedVector2Array([Vector2(0.044, 0.0), Vector2(0.05, 0.006), Vector2(0.05, 0.016), Vector2(0.044, 0.022)]), 22, lo * 0.75, lo * 0.75)
	k.pop()
	# the stitched seam along the top
	var seam := PackedVector3Array()
	for i: int in range(6, prof.size() - 1):
		var p := prof[i]
		seam.append(Vector3(p.y, y + p.x + 0.002, 0.0))
	k.tube("a_bright", seam, 0.008, 5, Color(0.6, 0.48, 0.32))
	# wrist strap: a flat loop out of the butt
	k.push(Transform3D(Basis.from_scale(Vector3(1.0, 0.4, 1.0)), Vector3(0.0, y - 0.04, 0.0)))
	var strap := PackedVector3Array()
	for i: int in range(19):
		var t := float(i) / 18.0
		var a := TAU * t
		var r := 0.15 * (0.6 + 0.4 * sin(t * PI))
		strap.append(Vector3(-0.19 + cos(a) * 0.19, 0.0, sin(a) * r * 0.9))
	strap[0] = Vector3(0.02, 0.06, 0.012)
	strap[18] = Vector3(0.02, 0.06, -0.012)
	k.tube("a_leather", strap, 0.026, 8, Color(0.4, 0.26, 0.16))
	k.pop()
	k.pop()
	s._commit(k, parent)
	return {"pitch": 42.0, "yaw": 0.0}

## A dark green glass bottle lying on its side, corked, with a plain paper label.
func _bottle(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	var glo := Color(0.05, 0.17, 0.08)
	var ghi := Color(0.08, 0.26, 0.12)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(DIAG)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.5, 0.19, 0.0)))
	k.lathe("a_gloss", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.004), Vector2(0.17, 0.0), Vector2(0.185, 0.015), Vector2(0.19, 0.05), Vector2(0.19, 0.54), Vector2(0.178, 0.6), Vector2(0.14, 0.66), Vector2(0.085, 0.72), Vector2(0.058, 0.77), Vector2(0.055, 0.95), Vector2(0.066, 0.958), Vector2(0.068, 0.99), Vector2(0.05, 1.0)]), 32, glo, ghi)
	k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(0.193, 0.17), Vector2(0.193, 0.42)]), 32, Color(0.86, 0.8, 0.64), Color(0.88, 0.82, 0.66))
	for p: float in [0.19, 0.4]:
		k.lathe("a_bright", Vector3.ZERO, PackedVector2Array([Vector2(0.1945, p), Vector2(0.1945, p + 0.012)]), 32, Color(0.7, 0.14, 0.1), Color(0.7, 0.14, 0.1))
	k.lathe("concrete", Vector3.ZERO, PackedVector2Array([Vector2(0.05, 0.99), Vector2(0.052, 1.05), Vector2(0.046, 1.062), Vector2(0.0, 1.064)]), 16, Color(0.92, 0.7, 0.45), Color(1.0, 0.78, 0.5))
	k.pop()
	s._commit(k, parent)
	return {"pitch": 40.0, "yaw": 0.0}

## A smooth river pebble: a flattened, lopsided stone, mottled, a pale quartz vein across it.
func _throw(s, parent: Node3D) -> Dictionary:
	_materials(s)
	var k := Kit.new()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(16.0)), Vector3.ZERO))
	var rows := 40
	var cols := 73
	var vein := Vector3(0.78, 0.2, 0.6).normalized()
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	for i: int in range(rows):
		var th := lerpf(-PI * 0.5, PI * 0.5, float(i) / float(rows - 1))
		for j: int in range(cols):
			var ph := TAU * float(j) / float(cols - 1)
			# egg-shaped outline, broader at one end, a little lumpy
			var rim := 1.0 + 0.09 * cos(ph) + 0.045 * cos(2.0 * ph + 0.8) + 0.025 * sin(3.0 * ph + 0.3)
			var up := 0.2 * (1.0 + 0.12 * cos(ph - 0.6) * cos(th)) if th > 0.0 else 0.13
			var p := Vector3(cos(th) * cos(ph) * 0.46 * rim, sin(th) * up, -cos(th) * sin(ph) * 0.33 * rim)
			# the top tips a little toward the broad end
			p.y += 0.035 * cos(th) * cos(ph) * maxf(0.0, sin(th))
			pts.append(p)
			uvs.append(Vector2(atan2(p.y, p.z) * 0.2 + 0.3, p.x + 0.5) * Kit.UV_M)
			var mottle := 0.5 + 0.25 * sin(p.x * 9.0 + 1.0) * sin(p.z * 11.0 + 0.4) + 0.25 * sin(p.x * 23.0 - p.z * 17.0)
			var base := Color(0.5, 0.48, 0.45).lerp(Color(0.66, 0.64, 0.6), mottle)
			var d := absf(p.normalized().dot(vein) - 0.3)
			var w := clampf(1.3 - d / 0.075, 0.0, 1.0)
			colours.append(base.lerp(Color(0.95, 0.94, 0.9), smoothstep(0.0, 1.0, w)))
	k.patch("a_pebble", rows, cols, pts, uvs, colours, true)
	k.pop()
	s._commit(k, parent)
	return {"pitch": 42.0, "yaw": 0.0}
