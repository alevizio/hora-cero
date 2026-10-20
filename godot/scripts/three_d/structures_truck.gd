extends RefCounted
## Generic 1940s light 4x2 cargo truck (no maker, no markings). Built in its own frame: +X forward, Y up, Z right,
## origin on the ground under the middle of the vehicle. About 3.4 m long and 1.8 m wide.
const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Props = preload("res://scripts/three_d/structures_props.gd")

var props: Props
var rng := RandomNumberGenerator.new()

const PAINT := Color(0.47, 0.5, 0.39)
const PAINT_DARK := Color(0.36, 0.39, 0.31)
const TILT := Color(0.86, 0.85, 0.8)
const UNDER := Color(0.2, 0.2, 0.19)

func _init(p: Props, seed_value: int) -> void:
	props = p
	rng.seed = seed_value

func build(k: Kit, flat: Kit, at: Vector3, yaw: float) -> void:
	k.push_at(at, yaw)
	_chassis(k)
	_bonnet(k)
	_cab(k)
	_bed(k)
	for x: float in [1.05, -0.88]:
		for s: float in [-1.0, 1.0]:
			_wheel(k, Vector3(x, 0.42, s * 0.74), s)
	for s: float in [-1.0, 1.0]:
		_mudguard(k, s)
	k.pop()
	var fwd := Vector3(cos(yaw), 0, -sin(yaw))
	flat.decal(Kit.DECAL["blob"], at.x, at.z, Vector2(4.6, 2.9), yaw, Color(0.04, 0.035, 0.03, 0.72))
	flat.decal(Kit.DECAL["oil"], at.x + fwd.x * 0.9, at.z + fwd.z * 0.9, Vector2(1.3, 1.1), yaw + 0.6, Color(0.75, 0.75, 0.7, 0.75))

func _chassis(k: Kit) -> void:
	for z: float in [-0.36, 0.36]:
		k.box("steel", Vector3(-0.05, 0.6, z), Vector3(3.3, 0.12, 0.07), UNDER, UNDER)
	for x: float in [1.05, -0.88]:
		k.tube("steel", PackedVector3Array([Vector3(x, 0.42, -0.72), Vector3(x, 0.42, 0.72)]), 0.05, 5, UNDER)
	k.lathe("steel", Vector3(-0.88, 0.3, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.13, 0.04), Vector2(0.16, 0.12), Vector2(0.13, 0.2), Vector2(0.0, 0.24)]), 8, UNDER, UNDER)
	# front bumper with dumb irons, tow hooks, rear cross member
	k.push_tint(PAINT_DARK)
	k.box("steel", Vector3(1.69, 0.62, 0), Vector3(0.06, 0.13, 1.66), Kit.grey(0.7), Color.WHITE, Vector2(0.2, 0.2))
	for z: float in [-0.36, 0.36]:
		k.box("steel", Vector3(1.6, 0.62, z), Vector3(0.16, 0.08, 0.06), Kit.grey(0.6), Kit.grey(0.9))
	k.box("steel", Vector3(-1.69, 0.66, 0), Vector3(0.05, 0.14, 1.5), Kit.grey(0.6), Kit.grey(0.9), Vector2(0.5, 0.2))
	k.pop_tint()
	# fuel tank and exhaust under the right side, spare wheel under the tail
	k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.05, 0.56, 0.6)))
	k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.15, 0.02), Vector2(0.16, 0.06), Vector2(0.16, 0.5), Vector2(0.15, 0.54), Vector2(0.0, 0.56)]), 8, PAINT_DARK * Kit.grey(0.7), PAINT_DARK, Vector2(0.3, 0.1))
	k.pop()
	k.tube("steel", PackedVector3Array([Vector3(1.0, 0.56, -0.3), Vector3(-0.3, 0.5, -0.52), Vector3(-1.5, 0.5, -0.52)]), 0.03, 4, Props.IRON_RUST)

func _bonnet(k: Kit) -> void:
	# lofted hood: wide at the scuttle, narrowing and dropping slightly toward the radiator
	var rows := 3
	var columns := 9
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var xs: Array[float] = [0.72, 1.2, 1.56]
	var halfw: Array[float] = [0.5, 0.44, 0.38]
	var tops: Array[float] = [1.42, 1.39, 1.34]
	for i: int in range(rows):
		for j: int in range(columns):
			var t := float(j) / float(columns - 1)
			var a := PI * t
			# rounded shoulders: superellipse from the left sill over the top to the right sill
			var cz := -cos(a)
			var sy := sin(a)
			var z := signf(cz) * pow(absf(cz), 0.45) * halfw[i]
			var y := 0.78 + pow(sy, 0.5) * (tops[i] - 0.78)
			pts.append(Vector3(xs[i], y, z))
			uvs.append(Vector2(xs[i] * Kit.UV_M, t * 0.7))
			cols.append(PAINT * Kit.grey(0.62 + 0.38 * pow(sy, 0.5)))
	# columns run from the left sill over the top to the right sill, rows forward: d/dcolumn x d/drow points outward
	k.patch("steel", rows, columns, pts, uvs, cols)
	# radiator shell and grille, filler cap
	k.push_tint(PAINT)
	k.box("steel", Vector3(1.58, 1.02, 0), Vector3(0.07, 0.72, 0.8), Kit.grey(0.65), Color.WHITE, Vector2(0.6, 0.6))
	var gr := Kit.trim_uv("grille")
	k.quad_rect("trim", Vector3(1.617, 0.7, 0.3), Vector3(1.617, 0.7, -0.3), Vector3(1.617, 1.3, -0.3), Vector3(1.617, 1.3, 0.3), gr, Kit.grey(0.75), Color.WHITE)
	k.pop_tint()
	k.lathe("steel", Vector3(1.56, 1.36, 0), PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.035, 0.04), Vector2(0.0, 0.05)]), 6, Props.GALV, Props.GALV)
	# scuttle / firewall block between bonnet and cab, and the engine side valances
	k.push_tint(PAINT)
	k.box("steel", Vector3(1.14, 0.74, 0), Vector3(0.86, 0.14, 0.74), Kit.grey(0.5), Kit.grey(0.7), Vector2(0.1, 0.5))
	k.pop_tint()
	# headlamps on stalks either side of the radiator
	for s: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(1.42, 1.06, s * 0.56)))
		k.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.1, 0.06), Vector2(0.115, 0.15), Vector2(0.12, 0.17)]), 10, PAINT_DARK * Kit.grey(0.8), PAINT_DARK)
		k.disc("trim", Vector3(0, 0.165, 0), 0.112, 10, Kit.trim_uv("lens"), Kit.grey(0.95))
		k.pop()
		k.tube("steel", PackedVector3Array([Vector3(1.44, 0.8, s * 0.56), Vector3(1.44, 0.98, s * 0.56)]), 0.018, 4, PAINT_DARK)

func _cab(k: Kit) -> void:
	k.push_tint(PAINT)
	var uv := Vector2(0.3, 0.3)
	# lower body with door, upper cab narrowing slightly toward the roof
	k.box("steel", Vector3(0.3, 1.02, 0), Vector3(0.86, 0.68, 1.62), Kit.grey(0.6), Color.WHITE, uv)
	k.box("steel", Vector3(0.26, 1.63, 0), Vector3(0.78, 0.56, 1.54), Kit.grey(0.95), Color.WHITE, uv + Vector2(0.3, 0.1), Kit.AUTO, 0b110011)
	# door seams and handles
	for s: float in [-1.0, 1.0]:
		for x: float in [-0.08, 0.66]:
			k.box("steel", Vector3(x, 1.02, s * 0.812), Vector3(0.012, 0.62, 0.006), Kit.grey(0.35), Kit.grey(0.45))
		k.box("steel", Vector3(0.0, 1.22, s * 0.822), Vector3(0.1, 0.02, 0.016), Props.IRON, Props.GALV)
		# running board
		k.box("steel", Vector3(0.28, 0.6, s * 0.83), Vector3(0.74, 0.03, 0.2), PAINT_DARK * Kit.grey(0.6), PAINT_DARK * Kit.grey(1.1), Vector2(0.7, 0.2))
	k.pop_tint()
	# glazing: split windscreen, door windows, small rear light
	var gl := Kit.trim_uv("glass")
	var dim := Kit.grey(0.75)
	for s: float in [-1.0, 1.0]:
		var za := s * 0.06
		var zb := s * 0.7
		var z0 := minf(za, zb)
		var z1 := maxf(za, zb)
		k.quad_rect("trim", Vector3(0.653, 1.42, z1), Vector3(0.653, 1.42, z0), Vector3(0.653, 1.84, z0), Vector3(0.653, 1.84, z1), gl, dim, Color.WHITE)
		if s > 0.0:
			k.quad_rect("trim", Vector3(-0.05, 1.42, 0.773), Vector3(0.57, 1.42, 0.773), Vector3(0.57, 1.84, 0.773), Vector3(-0.05, 1.84, 0.773), gl, dim, Color.WHITE)
		else:
			k.quad_rect("trim", Vector3(0.57, 1.42, -0.773), Vector3(-0.05, 1.42, -0.773), Vector3(-0.05, 1.84, -0.773), Vector3(0.57, 1.84, -0.773), gl, dim, Color.WHITE)
	k.quad_rect("trim", Vector3(-0.133, 1.5, -0.3), Vector3(-0.133, 1.5, 0.3), Vector3(-0.133, 1.8, 0.3), Vector3(-0.133, 1.8, -0.3), gl, dim, Kit.grey(0.9))
	# cambered roof with a canvas-covered centre panel
	var rows := 4
	var columns := 7
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(rows):
		var tx := float(i) / float(rows - 1)
		var x := lerpf(-0.16, 0.7, tx)
		for j: int in range(columns):
			var tz := float(j) / float(columns - 1)
			var z := lerpf(-0.8, 0.8, tz)
			var crown := 1.0 - pow(absf(tz * 2.0 - 1.0), 2.4)
			var fall := 1.0 - pow(absf(tx * 2.0 - 1.0), 3.0)
			pts.append(Vector3(x, 1.9 + 0.07 * crown * (0.6 + 0.4 * fall), z))
			uvs.append(Vector2(x, z) * Kit.UV_M + Vector2(0.37, 0.11))
			cols.append(TILT * Kit.grey(0.8 + 0.2 * crown))
	# rows run forward (+X), columns to the right (+Z): d/dcolumn x d/drow = Z x X = +Y
	k.patch("canvas", rows, columns, pts, uvs, cols)
	k.push_tint(PAINT)
	k.box("steel", Vector3(0.27, 1.91, 0), Vector3(0.88, 0.035, 1.62), Kit.grey(0.8), Color.WHITE, uv, Kit.AUTO, 0b110011)
	k.pop_tint()
	# wing mirror and a wiper
	k.tube("steel", PackedVector3Array([Vector3(0.6, 1.5, 0.78), Vector3(0.72, 1.6, 0.98)]), 0.01, 3, Props.IRON)
	k.box("steel", Vector3(0.73, 1.64, 1.0), Vector3(0.02, 0.14, 0.09), Props.IRON, Props.GALV)

func _bed(k: Kit) -> void:
	var x0 := -1.68
	var x1 := -0.2
	var hw := 0.88
	var floor_y := 0.86
	var side_h := 0.46
	var wood := Color(0.62, 0.68, 0.52)
	# floor (underside dark), cross bearers
	k.box("planks", Vector3((x0 + x1) * 0.5, floor_y - 0.03, 0), Vector3(x1 - x0, 0.06, hw * 2.0), UNDER, Props.WOOD_GREY * Kit.grey(0.75), Vector2(0.2, 0.4))
	for x: float in [x0 + 0.15, (x0 + x1) * 0.5, x1 - 0.15]:
		k.box("steel", Vector3(x, floor_y - 0.1, 0), Vector3(0.07, 0.1, hw * 2.0), UNDER, UNDER)
	# drop sides: three boards each, steel strapping; headboard; tailgate hanging down
	k.push_tint(wood)
	for s: float in [-1.0, 1.0]:
		for b: int in range(3):
			var g := rng.randf_range(0.82, 1.0)
			k.box("planks", Vector3((x0 + x1) * 0.5, floor_y + 0.075 + float(b) * 0.153, s * (hw - 0.02)), Vector3(x1 - x0, 0.147, 0.035), Kit.grey(0.7 * g), Kit.grey(g), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	for b: int in range(4):
		var g := rng.randf_range(0.82, 1.0)
		k.box("planks", Vector3(x1 - 0.02, floor_y + 0.075 + float(b) * 0.153, 0), Vector3(0.035, 0.147, hw * 2.0), Kit.grey(0.7 * g), Kit.grey(g), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	for b: int in range(3):
		var g := rng.randf_range(0.82, 1.0)
		k.box("planks", Vector3(x0 - 0.03, floor_y - 0.08 - float(b) * 0.153, 0), Vector3(0.035, 0.147, hw * 2.0 - 0.08), Kit.grey(0.6 * g), Kit.grey(0.9 * g), Vector2(rng.randf(), rng.randf()), Kit.BEAM)
	k.pop_tint()
	k.push_tint(PAINT_DARK)
	for s: float in [-1.0, 1.0]:
		for x: float in [x0 + 0.05, (x0 + x1) * 0.5, x1 - 0.05]:
			k.box("steel", Vector3(x, floor_y + side_h * 0.5, s * (hw + 0.005)), Vector3(0.05, side_h + 0.04, 0.02), Kit.grey(0.7), Color.WHITE)
	k.pop_tint()
	# canvas tilt over three hoops; open at the back with the flap rolled up
	var rows := 7
	var columns := 11
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var top_y := 2.08
	var eave_y := floor_y + side_h - 0.06
	for i: int in range(rows):
		var tx := float(i) / float(rows - 1)
		var x := lerpf(x0 - 0.03, x1 + 0.02, tx)
		# canvas sags between the hoops (hoops sit at tx = 0, 0.5, 1)
		var sag := 0.03 * absf(sin(tx * TAU))
		for j: int in range(columns):
			var t := float(j) / float(columns - 1)
			var a := PI * t
			var cz := -cos(a)
			var sy := sin(a)
			var z := signf(cz) * pow(absf(cz), 0.5) * (hw + 0.035 - sag * 0.6 * sy)
			var y := eave_y + pow(sy, 0.62) * (top_y - eave_y - sag)
			pts.append(Vector3(x, y, z))
			uvs.append(Vector2(x * Kit.UV_M, t * 1.3))
			cols.append(TILT * Kit.grey(0.6 + 0.4 * pow(sy, 0.6) - 0.5 * sag / 0.03 * 0.12))
	k.patch("canvas", rows, columns, pts, uvs, cols)
	# front end sheet of the tilt
	_tilt_end(k, x1 + 0.02, hw, eave_y, top_y, 1.0, TILT * Kit.grey(0.75))
	# dark interior seen through the open tail, rolled flap, a little cargo
	_tilt_end(k, x0 + 0.02, hw - 0.02, eave_y, top_y - 0.02, -1.0, Kit.grey(0.07))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x0 - 0.03, top_y - 0.16, -0.7)))
	k.lathe("canvas", Vector3.ZERO, PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.085, 0.3), Vector2(0.08, 0.7), Vector2(0.085, 1.1), Vector2(0.075, 1.4)]), 7, TILT * Kit.grey(0.7), TILT * Kit.grey(0.7), Vector2(0.2, 0.2))
	k.pop()
	props.crate(k, Vector3(x0 + 0.38, floor_y, -0.36), Vector3(0.6, 0.5, 0.7), 0.05, 1, Props.WOOD_PALE * Kit.grey(0.8))
	props.jerrycan(k, Vector3(x0 + 0.2, floor_y, 0.3), 1.5, Props.DRAB_DARK)
	props.jerrycan(k, Vector3(x0 + 0.2, floor_y, 0.52), 1.62)
	# hoop ends showing below the canvas, lashing along the sides
	for s: float in [-1.0, 1.0]:
		k.tube("burlap", PackedVector3Array([Vector3(x0, eave_y - 0.02, s * (hw + 0.04)), Vector3((x0 + x1) * 0.5, eave_y - 0.07, s * (hw + 0.045)), Vector3(x1, eave_y - 0.02, s * (hw + 0.04))]), 0.012, 3, Color(0.8, 0.74, 0.6), Vector2.ZERO, 0.25, 6.0)

func _tilt_end(k: Kit, x: float, hw: float, eave_y: float, top_y: float, facing: float, col: Color) -> void:
	# fan-shaped end panel of the tilt (facing = +1 looks toward +X)
	var n := 10
	var prev := Vector3.ZERO
	var centre := Vector3(x, eave_y, 0)
	for j: int in range(n + 1):
		var t := float(j) / float(n)
		var a := PI * t
		var cz := -cos(a)
		var sy := sin(a)
		var p := Vector3(x, eave_y + pow(sy, 0.62) * (top_y - eave_y), signf(cz) * pow(absf(cz), 0.5) * (hw + 0.03))
		if j > 0:
			var uva := Vector2(prev.z, -prev.y) * Kit.UV_M
			var uvb := Vector2(p.z, -p.y) * Kit.UV_M
			var uvc := Vector2(0, -eave_y) * Kit.UV_M
			if facing > 0.0:
				k.tri("canvas", p, prev, centre, uvb, uva, uvc, col, col, col * Kit.grey(0.8))
			else:
				k.tri("canvas", prev, p, centre, uva, uvb, uvc, col, col, col)
		prev = p

func _wheel(k: Kit, at: Vector3, s: float) -> void:
	# tyre standing in the XY plane, hub dish facing outward (s = side sign along Z)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * s), at - Vector3(0, 0, s * 0.12)))
	props.tyre(k, Transform3D.IDENTITY, 0.3, 0.12, 1.0)
	k.lathe("steel", Vector3(0, 0.12, 0), PackedVector2Array([Vector2(0.21, 0.0), Vector2(0.2, 0.07), Vector2(0.11, 0.1), Vector2(0.09, 0.15), Vector2(0.0, 0.16)]), 10, PAINT_DARK * Kit.grey(0.75), PAINT_DARK, Vector2(rng.randf(), rng.randf()))
	k.pop()

func _mudguard(k: Kit, s: float) -> void:
	# front wing: an arc over the wheel sweeping back into the running board
	var rows := 2
	var columns := 9
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var cx := 1.05
	var cy := 0.42
	for i: int in range(rows):
		var z := s * (0.5 + 0.44 * float(i))
		for j: int in range(columns):
			var t := float(j) / float(columns - 1)
			var a := lerpf(-0.25, PI * 0.92, t)      # from the front lip over the top to the rear
			var r := 0.53 + 0.05 * t
			var p := Vector3(cx + cos(a) * r, cy + sin(a) * r * 0.98, z)
			if t > 0.86:
				p.y = maxf(p.y, 0.6)
			pts.append(p)
			uvs.append(Vector2(t * 0.5, float(i) * 0.17) + Vector2(0.1 if s > 0.0 else 0.6, 0.4))
			cols.append(PAINT * Kit.grey(0.7 + 0.3 * clampf(sin(a), 0.0, 1.0)))
	# a = angle from the front; columns advance toward the rear over the top. For the right side rows go outward (+Z).
	k.patch("steel", rows, columns, pts, uvs, cols, false, s < 0.0)
	var under := PackedColorArray([Kit.grey(0.12)])
	k.patch("steel", rows, columns, pts, uvs, under, false, s > 0.0)
