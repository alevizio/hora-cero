extends RefCounted
## The Plaza de Mayo kit's vehicles (plaza_kit.gd builds through this): Buenos Aires traffic of 1958, all unbranded
## (no badge, no maker's name, no real model; period-plausible shapes only) and all our own: a big rounded sedan of
## the late forties in the American manner, a small two-door European saloon, a taxi of the time (a plain dark car
## with a small roof sign and its meter's flag: the black-and-yellow livery came only in 1966, the notes), a colectivo
## of the fifties with an invented line number and fileteado of its own, a tram in an invented company's dark green
## and cream, and a soda-delivery truck. Each can stand parked under the evening's snow (a pillow on its roof, drifts
## round its wheels) with its doors shut or standing open.
##
## The bodies are lofts: cross-sections (a rounded box: flat underneath, the sides bellied, the shoulder rolling into
## the top) at stations along the car, raised over the wheels to make the arches, smooth-shaded; the glasshouse is a
## second loft from the belt to the roof, its glass from the atlas, pillars and roof laid over it. Local frame: the
## vehicle's front toward +z, x to its right... as built, +x is the driver's left (Argentina drives on the right).

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")

var pk: RefCounted
var rng := RandomNumberGenerator.new()

## Paints of the time (sRGB): dark green, maroon, black, cream, grey-blue, beige, a two-tone's second colour.
const PAINTS := ["1e2a22", "4a1c1a", "15171a", "d8cfb4", "5e7286", "b8a888", "2c3a4e", "6a6a62", "7a3a2a", "3e5a46"]

func _init(owner: RefCounted) -> void:
	pk = owner
	rng.seed = 1958

# ---------------------------------------------------------------------------------------------------------------
# Lofts
# ---------------------------------------------------------------------------------------------------------------
## A station of a body: z along the vehicle, its bottom, the shoulder (where the side rolls into the top), the top,
## the half width.
class Station:
	extends RefCounted
	var z: float
	var b: float
	var s: float
	var t: float
	var w: float
	func _init(z_: float, b_: float, s_: float, t_: float, w_: float) -> void:
		z = z_
		b = b_
		s = s_
		t = t_
		w = w_

static func st(z: float, b: float, s: float, t: float, w: float) -> Station:
	return Station.new(z, b, s, t, w)

## The cross-section at a station: a closed loop from the bottom's middle round the right side (+x), over the top and
## down the left side. `belt` (0..1 of the way from the bottom to the shoulder) marks where the two tones meet: its
## indices are returned in the last two places of the loop's metadata.
static func ring(s: Station, round_top: float = 0.62) -> PackedVector2Array:
	var b := s.b
	var t := s.t
	var sh := s.s
	var w := s.w
	var half := PackedVector2Array([Vector2(0.0, b), Vector2(w * 0.8, b), Vector2(w * 0.96, b + minf(0.07, (sh - b) * 0.2)), Vector2(w, b + (sh - b) * 0.45),
		Vector2(w * 0.995, b + (sh - b) * 0.8), Vector2(w * 0.97, sh), Vector2(w * 0.88, sh + (t - sh) * 0.55), Vector2(w * round_top, t - (t - sh) * 0.06), Vector2(w * 0.3, t), Vector2(0.0, t)])
	var out := PackedVector2Array()
	for p: Vector2 in half: out.append(p)
	for i: int in range(half.size() - 2, 0, -1): out.append(Vector2(-half[i].x, half[i].y))
	return out

## Lofts the stations (rear to front) into a smooth body on `key`, the ring's points from `i0` to `i1` (indices into
## ring(); the whole loop when i1 < 0), tinted `tint`. Closes both ends with fans when the loop is whole.
func loft(k: Kit, key: String, stations: Array, tint: Color, i0: int = 0, i1: int = -1, round_top: float = 0.62, caps: bool = true) -> void:
	var rows := stations.size()
	var full := i1 < 0
	var r0: PackedVector2Array = ring(stations[0], round_top)
	var n := r0.size()
	var cols := n + 1 if full else i1 - i0 + 1
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for si: int in range(rows):
		var s: Station = stations[si]
		var r := ring(s, round_top)
		for c: int in range(cols):
			var idx := (c % n) if full else (i0 + c)
			var p := r[idx]
			pts.append(Vector3(p.x, p.y, s.z))
			uvs.append(Vector2(s.z * Kit.UV_M, 1.0 - p.y * Kit.UV_M) if absf(p.x) > s.w * 0.85 else Vector2(p.x * Kit.UV_M, s.z * Kit.UV_M))
	k.push_tint(tint)
	k.patch(key, rows, cols, pts, uvs, PackedColorArray([Color.WHITE]), full)
	if full and caps:
		for e: int in [0, rows - 1]:
			var s2: Station = stations[e]
			var r2 := ring(s2, round_top)
			var c := Vector3(0, (s2.b + s2.t) * 0.5, s2.z)
			for i: int in range(n):
				var a := Vector3(r2[i].x, r2[i].y, s2.z)
				var bb := Vector3(r2[(i + 1) % n].x, r2[(i + 1) % n].y, s2.z)
				var want := Vector3(0, 0, -1) if e == 0 else Vector3(0, 0, 1)
				if (a - c).cross(bb - c).dot(want) >= 0.0: k.tri(key, c, a, bb, Vector2(0.5, 0.5), Vector2(0.5, 0.4), Vector2(0.6, 0.4))
				else: k.tri(key, c, bb, a, Vector2(0.5, 0.5), Vector2(0.5, 0.4), Vector2(0.6, 0.4))
	k.pop_tint()

## The ring index of the belt line on the right side (where a two-tone's colours meet), for a ring() loop.
const BELT_R := 4
const BELT_L := 14

## Raised bottoms over the wheels: stations round each wheel's arch.
static func arch(z: float, r: float, b: float, s: float, t: float, w: float) -> Array:
	var out: Array = []
	for i: int in range(7):
		var a := PI * float(i) / 6.0
		var zz := z + cos(a) * (r + 0.08)
		var top := r + 0.04 + sin(a) * (r + 0.08)
		out.append(Station.new(zz, maxf(b, minf(top, s - 0.12)), s, t, w))
	out.reverse()
	return out

# ---------------------------------------------------------------------------------------------------------------
# Common parts
# ---------------------------------------------------------------------------------------------------------------
func wheel(k: Kit, kd: Kit, at: Vector3, r: float, width: float, side: float, cap: String = "hubcap") -> void:
	k.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * side), at))
	k.lathe("rubber", Vector3(0, -width * 0.5, 0), PackedVector2Array([Vector2(r * 0.62, 0.0), Vector2(r * 0.95, 0.0), Vector2(r, width * 0.2), Vector2(r, width * 0.8), Vector2(r * 0.95, width), Vector2(r * 0.62, width)]), 14, Color(0.1, 0.1, 0.1), Color(0.14, 0.14, 0.14))
	k.pop()
	# the hubcap (and the whitewall) on the outer face
	kd.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * side), at))
	kd.disc(pk.SOLID, Vector3(0, width * 0.5 + 0.005, 0), r * 0.92, 14, pk.uv(cap))
	kd.pop()

func chrome(k: Kit, path: PackedVector3Array, radius: float) -> void:
	k.push_tint(Color(0.86, 0.88, 0.9))
	k.tube("metal", path, radius, 6, Color.WHITE)
	k.pop_tint()

## A lamp's glass facing `dir` (a headlamp lit or dark, a tail lamp).
func lamp(kd: Kit, at: Vector3, dir: Vector3, r: float, cell: String, glowing: bool) -> void:
	var y := dir.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.01: x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	kd.push(Transform3D(Basis(x, y, z), at))
	kd.disc(pk.GLOW if glowing else pk.SOLID, Vector3.ZERO, r, 10, pk.uv(cell), pk.WARM if glowing and cell == "headlamp" else Color.WHITE)
	kd.pop()

## Snow on a parked vehicle: pillows on the flat tops it is given, drifts banked along both sides and heaped at its ends
## (snowed in), all scaled by the kit's snow.
func snowed(k: Kit, tops: Array, half_len: float, half_w: float, snowed_in: bool) -> void:
	for t: Array in tops:
		var r: Rect2 = t[0]
		pk.pillow(k, Snow.rect_poly(r), float(t[1]), float(t[2]), minf(r.size.x, r.size.y) * 0.3)
	if snowed_in:
		# banks of snow along its sills and heaped at its ends, ploughed up round it
		# soft banks of snow along its sides, half under the sills, and heaped at its ends
		for side: float in [-1.0, 1.0]:
			pk.mound(k, Vector3(side * (half_w + 0.12), 0, -half_len + 0.2), Vector3(side * (half_w + 0.12), 0, half_len - 0.2), 0.24, 0.5)
		for e: float in [-1.0, 1.0]:
			pk.mound(k, Vector3(-half_w * 0.8, 0, e * (half_len + 0.15)), Vector3(half_w * 0.8, 0, e * (half_len + 0.15)), 0.2, 0.45)

## The finished vehicle as a node: the body and the details, placed at `pos` facing `yaw` (0: toward +z).
func _place(name: String, pos: Vector3, yaw: float, k: Kit, kd: Kit) -> Node3D:
	var node: Node3D = pk.piece(name, Transform3D(Basis(Vector3.UP, yaw), pos), k, kd)
	pk.end()
	return node

# ---------------------------------------------------------------------------------------------------------------
# Cars
# ---------------------------------------------------------------------------------------------------------------
## A car: kind "sedan" (a big rounded fastback four-door of the late forties, American in manner: separate swelling
## wings, a tall domed glasshouse sloping into the tail, skirts over the rear wheels, a wide chrome grille), "saloon" (a
## small rounded two-door, European in manner) or "taxi" (the sedan in dark paint with its small roof sign and the
## meter's flag up: LIBRE). paint: a colour (or transparent for one of PAINTS); open: the doors standing open, by index
## (0 front left, 1 front right, 2 rear left, 3 rear right); lights: the headlamps on (a car waiting, not one parked);
## snowed_in: drifts round it. Returns the node.
func car(pos: Vector3, yaw: float, kind: String = "sedan", paint: Color = Color(0, 0, 0, 0), open: Array = [], lights: bool = false, snowed_in: bool = true) -> Node3D:
	pk.begin(Transform3D(Basis(Vector3.UP, yaw), pos))
	var k := Kit.new()
	var kd := Kit.new()
	if paint.a < 0.5:
		paint = pk.hexc(PAINTS[rng.randi() % PAINTS.size()]) if kind != "taxi" else pk.hexc(["15171a", "1e2a22", "2a2030"][rng.randi() % 3])
	paint.a = 1.0
	var spec := _sedan_spec() if kind != "saloon" else _saloon_spec()
	_car_body(k, kd, spec, paint, open, lights)
	if kind == "taxi": _taxi_parts(k, kd, spec, lights)
	var hw: float = spec.hw
	var roof: Rect2 = spec.roof_snow
	# (the hood, the wings and the fastback take their snow in the shader: only the roof holds a cushion of it)
	var tops: Array = []
	if kind != "taxi": tops.append([roof, float(spec.roof_y) - 0.06, 0.12])
	else:
		tops.append([Rect2(roof.position.x, roof.position.y, roof.size.x, roof.size.y * 0.35), float(spec.roof_y) - 0.06, 0.1])
	snowed(k, tops, float(spec.L) * 0.5, hw, snowed_in)
	# snow along the wings' crowns
	for f: Array in spec.fenders:
		var fx: float = f[0]
		for side: float in [-1.0, 1.0]:
			pk.ridge(k, Vector3(side * fx, float(f[2]) + 0.01, float(f[1]) - 0.35), Vector3(side * fx, float(f[2]) + 0.01, float(f[1]) + 0.35), Vector3.UP, 0.2, 0.06, 0.02, 0.5, true)
	return _place({"sedan": "Sedan", "saloon": "Saloon", "taxi": "Taxi"}.get(kind, "Car"), pos, yaw, k, kd)

func _sedan_spec() -> Dictionary:
	var hw := 0.84
	var r := 0.36
	var wf := 1.48
	var wr := -1.45
	var b := 0.32
	var stations: Array = [st(-2.5, 0.46, 0.7, 0.82, 0.6), st(-2.4, 0.38, 0.76, 0.9, 0.74), st(-2.2, 0.34, 0.8, 0.95, 0.82)]
	stations.append_array(arch(wr, r, b, 0.8, 0.96, hw))
	stations.append_array([st(-0.8, b, 0.8, 0.97, hw), st(0.3, b, 0.8, 0.97, hw)])
	stations.append_array(arch(wf, r, b, 0.8, 0.97, hw * 0.98))
	stations.append_array([st(2.2, 0.36, 0.76, 0.94, 0.78), st(2.42, 0.4, 0.7, 0.86, 0.66), st(2.52, 0.46, 0.64, 0.78, 0.52)])
	# the glasshouse, rear to front: a fastback sloping into the tail, the windscreen standing up at the cowl
	var house: Array = [[-2.32, 0.97, 0.62], [-1.9, 1.17, 0.68], [-1.4, 1.42, 0.7], [-0.9, 1.6, 0.71], [-0.3, 1.67, 0.71], [0.3, 1.66, 0.71], [0.62, 1.56, 0.73], [0.95, 0.97, 0.8]]
	return {"L": 5.05, "width": 1.92, "hw": hw, "r": r, "wheels": [wf, wr], "skirts": [wr], "stations": stations, "house": house, "belt": 0.96,
		"fenders": [[0.78, wf, 1.0, "front"], [0.78, wr, 0.97, "rear"]],
		"windows": [[0.64, 0.93, "ws"], [-1.45, -1.0, "rear"], [-0.45, 0.5, "side"], [-1.25, -0.55, "side"]],
		"doors": [[0.52, -0.5], [-0.55, -1.32]], "roof_y": 1.67, "roof_snow": Rect2(-0.42, -0.8, 0.84, 1.05),
		"hood_z0": 1.0, "hood_z1": 2.15, "hood_y": 0.97, "front": 2.52, "rear": -2.5,
		"lamp": Vector3(0.78, 0.82, 2.46), "tail": Vector3(0.8, 0.74, -2.45), "grille": Rect2(-0.56, 0.42, 1.12, 0.3), "bumper_y": 0.42}

func _saloon_spec() -> Dictionary:
	var hw := 0.72
	var r := 0.31
	var wf := 1.2
	var wr := -1.15
	var b := 0.3
	var stations: Array = [st(-1.97, 0.42, 0.6, 0.74, 0.5), st(-1.9, 0.35, 0.68, 0.84, 0.62), st(-1.7, 0.31, 0.72, 0.9, 0.69)]
	stations.append_array(arch(wr, r, b, 0.74, 0.92, hw))
	stations.append_array([st(-0.4, b, 0.74, 0.92, hw), st(0.3, b, 0.74, 0.92, hw)])
	stations.append_array(arch(wf, r, b, 0.72, 0.9, hw))
	stations.append_array([st(1.7, 0.33, 0.68, 0.86, 0.68), st(1.88, 0.38, 0.62, 0.78, 0.58), st(1.97, 0.45, 0.56, 0.7, 0.44)])
	var house: Array = [[-1.82, 0.92, 0.54], [-1.5, 1.08, 0.58], [-1.0, 1.31, 0.6], [-0.5, 1.45, 0.6], [0.1, 1.48, 0.6], [0.45, 1.4, 0.62], [0.75, 0.92, 0.68]]
	return {"L": 3.95, "width": 1.56, "hw": hw, "r": r, "wheels": [wf, wr], "skirts": [], "stations": stations, "house": house, "belt": 0.91,
		"fenders": [[0.64, wf, 0.92, "front"]],
		"windows": [[0.48, 0.73, "ws"], [-1.4, -1.02, "rear"], [-0.55, 0.42, "side"], [-1.12, -0.65, "side"]],
		"doors": [[0.44, -0.6]], "roof_y": 1.48, "roof_snow": Rect2(-0.36, -0.5, 0.72, 0.85),
		"hood_z0": 0.8, "hood_z1": 1.7, "hood_y": 0.9, "front": 1.97, "rear": -1.97,
		"lamp": Vector3(0.62, 0.74, 1.92), "tail": Vector3(0.62, 0.66, -1.93), "grille": Rect2(-0.3, 0.4, 0.6, 0.24), "bumper_y": 0.38}

## The glasshouse's station at a z (interpolated).
func _house_at(hs: Array, z: float) -> Station:
	for i: int in range(hs.size() - 1):
		var a: Station = hs[i]
		var b: Station = hs[i + 1]
		if z >= a.z and z <= b.z:
			var t := (z - a.z) / maxf(b.z - a.z, 0.001)
			return Station.new(z, lerpf(a.b, b.b, t), lerpf(a.s, b.s, t), lerpf(a.t, b.t, t), lerpf(a.w, b.w, t))
	return hs[0] if z < (hs[0] as Station).z else hs[hs.size() - 1]

## A pane of glass laid on the glasshouse: rows from z0 to z1, the ring's points from c0 to c1, a hair outside it.
func _pane(kd: Kit, hs: Array, z0: float, z1: float, c0: int, c1: int, key: String, cell: String, col: Color = Color.WHITE) -> void:
	var rows := 4
	var cols := c1 - c0 + 1
	var rr: Rect2 = pk.uv(cell)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var z := lerpf(z0, z1, float(i) / float(rows - 1))
		var s := _house_at(hs, z)
		var r := ring(s, 0.55)
		var cy := (s.b + s.t) * 0.5
		for c: int in range(cols):
			var p: Vector2 = r[(c0 + c) % r.size()]
			var d := Vector2(p.x, p.y - cy)
			var o := p + (d.normalized() * 0.02 if d.length() > 0.001 else Vector2.ZERO)
			pts.append(Vector3(o.x, o.y, z))
			uvs.append(Vector2(rr.position.x + rr.size.x * (0.08 + 0.84 * float(c) / float(maxi(cols - 1, 1))), rr.position.y + rr.size.y * (0.08 + 0.84 * float(i) / float(rows - 1))))
	kd.patch(key, rows, cols, pts, uvs, PackedColorArray([col]))

## A wing over a wheel, beside the body: a loft of its own centred at x = fx, swelling over the wheel's arch (or, with a
## skirt, coming down over the wheel's top), running out to a rounded nose or tail.
func _fender(k: Kit, fx: float, wz: float, r: float, top: float, front: bool, skirt: bool, paint: Color) -> void:
	var st_list: Array = []
	if front:
		st_list = [st(wz - 1.0, 0.56, top - 0.18, top - 0.13, 0.04), st(wz - 0.82, 0.44, top - 0.12, top - 0.05, 0.12)]
		for a in arch(wz, r, 0.42, top - 0.08, top, 0.16): st_list.append(a)
		st_list.append_array([st(wz + 0.78, 0.4, top - 0.12, top - 0.04, 0.15), st(wz + 0.94, 0.44, top - 0.22, top - 0.13, 0.12), st(wz + 1.02, 0.52, top - 0.3, top - 0.24, 0.06)])
	else:
		st_list = [st(wz - 1.02, 0.44, top - 0.2, top - 0.14, 0.05), st(wz - 0.88, 0.38, top - 0.12, top - 0.05, 0.13)]
		if skirt: st_list.append_array([st(wz - 0.4, 0.34, top - 0.08, top, 0.16), st(wz + 0.4, 0.34, top - 0.08, top, 0.16)])
		else:
			for a in arch(wz, r, 0.38, top - 0.08, top, 0.16): st_list.append(a)
		st_list.append_array([st(wz + 0.85, 0.38, top - 0.12, top - 0.05, 0.12), st(wz + 1.05, 0.5, top - 0.18, top - 0.13, 0.04)])
	for side: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis.IDENTITY, Vector3(side * fx, 0, 0)))
		loft(k, "paint", st_list, paint, 0, -1, 0.7)
		k.pop()

func _car_body(k: Kit, kd: Kit, spec: Dictionary, paint: Color, open: Array, lights: bool) -> void:
	var stations: Array = spec.stations
	loft(k, "paint", stations, paint)
	# the wings
	for f: Array in spec.fenders:
		_fender(k, float(f[0]), float(f[1]), float(spec.r), float(f[2]), str(f[3]) == "front", float(f[1]) in spec.skirts, paint)
	# the glasshouse, in the paint, and the glass laid on it where the windows are
	var belt: float = spec.belt
	var hs: Array = []
	for h: Array in spec.house:
		hs.append(Station.new(float(h[0]), belt - 0.04, belt + (float(h[1]) - belt) * 0.16, float(h[1]), float(h[2])))
	loft(k, "paint", hs, paint, 0, -1, 0.55)
	for w: Array in spec.windows:
		var z0: float = w[0]
		var z1: float = w[1]
		match str(w[2]):
			"ws", "rear": _pane(kd, hs, z0, z1, 5, 13, pk.GLASS, "car_glass")
			"side":
				_pane(kd, hs, z0, z1, 4, 7, pk.GLASS, "car_glass")
				_pane(kd, hs, z1, z0, 11, 14, pk.GLASS, "car_glass")
	# the drip rails over the side windows, in chrome: the glasshouse's roof edge
	for side: float in [-1.0, 1.0]:
		var rail := PackedVector3Array()
		# (from the back of the rear side window to the front of the front one: not round onto the windscreen)
		var zz: float = float(spec.windows[3][0]) - 0.05
		while zz <= float(spec.windows[2][1]) + 0.06:
			var hsz := _house_at(hs, zz)
			var rr := ring(hsz, 0.55)
			var p: Vector2 = rr[7] if side > 0.0 else rr[11]
			rail.append(Vector3(p.x * 1.02, p.y + 0.01, zz))
			zz += 0.3
		if rail.size() >= 2: chrome(k, rail, 0.014)
	# chrome: the moulding along the body, the bumpers with their overriders, the grille, the lamps in their bezels
	var hw: float = spec.hw
	var front: float = spec.front
	var rear: float = spec.rear
	var by: float = spec.bumper_y
	var W: float = float(spec.width) * 0.5
	for side: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		var z := rear + 0.5
		while z < front - 0.5:
			path.append(Vector3(side * (_width_at(stations, z) + 0.006), belt - 0.16, z))
			z += 0.45
		chrome(k, path, 0.012)
	chrome(k, PackedVector3Array([Vector3(-W, by, front - 0.32), Vector3(-W * 0.9, by, front + 0.04), Vector3(W * 0.9, by, front + 0.04), Vector3(W, by, front - 0.32)]), 0.08)
	chrome(k, PackedVector3Array([Vector3(-W, by, rear + 0.32), Vector3(-W * 0.9, by, rear - 0.04), Vector3(W * 0.9, by, rear - 0.04), Vector3(W, by, rear + 0.32)]), 0.08)
	for side: float in [-1.0, 1.0]:
		for e: float in [front + 0.06, rear - 0.06]:
			k.push_tint(Color(0.86, 0.88, 0.9))
			k.box("metal", Vector3(side * W * 0.42, by + 0.1, e), Vector3(0.07, 0.3, 0.08), Color.WHITE, Color.WHITE)
			k.pop_tint()
	var g: Rect2 = spec.grille
	kd.quad_rect(pk.SOLID, Vector3(g.end.x, g.position.y, front - 0.04), Vector3(g.position.x, g.position.y, front - 0.04), Vector3(g.position.x, g.end.y, front - 0.07), Vector3(g.end.x, g.end.y, front - 0.07), pk.uv("grille"), Color.WHITE, Color.WHITE)
	var lp: Vector3 = spec.lamp
	var tp: Vector3 = spec.tail
	for side: float in [-1.0, 1.0]:
		lamp(kd, Vector3(side * lp.x, lp.y, lp.z + 0.01), Vector3(0, 0, 1), 0.11, "headlamp", lights)
		k.push_tint(Color(0.86, 0.88, 0.9))
		k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * lp.x, lp.y, lp.z - 0.14)))
		k.lathe("metal", Vector3.ZERO, PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.13, 0.1), Vector2(0.14, 0.14), Vector2(0.11, 0.15)]), 10, Color.WHITE, Color.WHITE)
		k.pop()
		k.pop_tint()
		lamp(kd, Vector3(side * tp.x, tp.y, tp.z - 0.01), Vector3(0, 0, -1), 0.06, "taillamp", false)
	if lights:
		var world: Vector3 = pk.xf * Vector3(0, lp.y, front + 0.2)
		pk.halo(world, pk.WARM, 0.7)
		pk.spill_at(Vector3(0, 0, front + 0.3), Vector3(0, 0, 1), 1.0, 6.0, 0.6)
	# plates: blank enamel, front and back
	kd.quad_rect(pk.SOLID, Vector3(0.2, by + 0.1, front + 0.12), Vector3(-0.2, by + 0.1, front + 0.12), Vector3(-0.2, by + 0.24, front + 0.12), Vector3(0.2, by + 0.24, front + 0.12), pk.uv("plate"), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.SOLID, Vector3(-0.2, by + 0.12, rear - 0.12), Vector3(0.2, by + 0.12, rear - 0.12), Vector3(0.2, by + 0.26, rear - 0.12), Vector3(-0.2, by + 0.26, rear - 0.12), pk.uv("plate"), Color.WHITE, Color.WHITE)
	# the wheels
	var r: float = spec.r
	for wz: float in spec.wheels:
		for side: float in [-1.0, 1.0]:
			wheel(k, kd, Vector3(side * (hw - 0.08), r, wz), r, 0.2, side)
	# the doors: shut (their seams and handles) or standing open on their front hinges
	var di := 0
	for d: Array in spec.doors:
		for side: float in [1.0, -1.0]:
			var idx := di * 2 + (0 if side > 0.0 else 1)
			var z0: float = d[0]
			var z1: float = d[1]
			if idx in open: _open_door(k, kd, stations, hs, spec, z0, z1, side, paint)
			else: _door_seams(kd, stations, spec, z0, z1, side)
		di += 1

func _width_at(stations: Array, z: float) -> float:
	var best := 0.0
	for i: int in range(stations.size() - 1):
		var a: Station = stations[i]
		var b: Station = stations[i + 1]
		if z >= a.z and z <= b.z:
			return lerpf(a.w, b.w, (z - a.z) / maxf(b.z - a.z, 0.001))
		best = b.w
	return best

## A shut door: its seams down the side and a chrome handle.
func _door_seams(kd: Kit, stations: Array, spec: Dictionary, z0: float, z1: float, side: float) -> void:
	var belt: float = spec.belt
	var b := 0.38
	for z: float in [z0, z1]:
		var w := _width_at(stations, z) + 0.006
		kd.quad_rect(pk.SOLID, Vector3(side * w, b, z + 0.008 * side), Vector3(side * w, b, z - 0.008 * side), Vector3(side * w, belt - 0.03, z - 0.008 * side), Vector3(side * w, belt - 0.03, z + 0.008 * side), pk.uv("dark"), Color.WHITE, Color.WHITE)
	var hz := z1 + 0.16
	var w2 := _width_at(stations, hz) + 0.018
	kd.quad_rect(pk.SOLID, Vector3(side * w2, belt - 0.1, hz + 0.08 * side), Vector3(side * w2, belt - 0.1, hz - 0.08 * side), Vector3(side * w2, belt - 0.065, hz - 0.08 * side), Vector3(side * w2, belt - 0.065, hz + 0.08 * side), pk.uv("white"), Color.WHITE, Color.WHITE)

## A door standing open: the dark of the car's inside where it was, a seat's edge, and the door itself swung out on
## its front hinge, its window frame and glass with it.
func _open_door(k: Kit, kd: Kit, stations: Array, hs: Array, spec: Dictionary, z0: float, z1: float, side: float, paint: Color) -> void:
	var belt: float = spec.belt
	var b := 0.36
	var w0 := _width_at(stations, z0) + 0.012
	var w1 := _width_at(stations, z1) + 0.012
	if side > 0.0: kd.quad_rect(pk.SOLID, Vector3(w1, b, z1), Vector3(w0, b, z0), Vector3(w0, belt - 0.02, z0), Vector3(w1, belt - 0.02, z1), pk.uv("dark"), Color.WHITE, Color.WHITE)
	else: kd.quad_rect(pk.SOLID, Vector3(-w0, b, z0), Vector3(-w1, b, z1), Vector3(-w1, belt - 0.02, z1), Vector3(-w0, belt - 0.02, z0), pk.uv("dark"), Color.WHITE, Color.WHITE)
	_pane(kd, hs, minf(z0, z1), maxf(z0, z1), 4 if side > 0.0 else 11, 8 if side > 0.0 else 15, pk.SOLID, "dark", Color(0.6, 0.6, 0.6))
	# the seat's edge showing in the opening
	k.push_tint(Color(0.32, 0.22, 0.16))
	k.box("planks", Vector3(side * (w0 - 0.3), 0.52, (z0 + z1) * 0.5), Vector3(0.4, 0.14, absf(z0 - z1) * 0.7), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	# the door, hinged at its front edge
	var length := absf(z0 - z1)
	var top := _house_at(hs, (z0 + z1) * 0.5).t - 0.06
	var hinge := Vector3(side * (w0 + 0.02), 0.0, z0)
	# (a door's local -z runs back along the car: turning it by -side swings its free end out, away from the body)
	var swing := -1.0 * side
	k.push(Transform3D(Basis(Vector3.UP, swing), hinge))
	k.push_tint(paint)
	k.box("paint", Vector3(side * 0.035, (b + belt) * 0.5, -length * 0.5), Vector3(0.07, belt - b, length), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.beam("paint", Vector3(side * 0.035, belt, -0.03), Vector3(-side * 0.1, top, -0.08), 0.05, 0.04, Color.WHITE, Color.WHITE)
	k.beam("paint", Vector3(-side * 0.1, top, -0.08), Vector3(-side * 0.1, top, -length + 0.12), 0.05, 0.04, Color.WHITE, Color.WHITE)
	k.beam("paint", Vector3(-side * 0.1, top, -length + 0.12), Vector3(side * 0.035, belt, -length + 0.02), 0.05, 0.04, Color.WHITE, Color.WHITE)
	k.pop_tint()
	k.pop()
	kd.push(Transform3D(Basis(Vector3.UP, swing), hinge))
	var gr: Rect2 = pk.uv("car_glass")
	if side > 0.0: kd.quad_rect(pk.GLASS, Vector3(0.04, belt, -0.06), Vector3(0.04, belt, -length + 0.06), Vector3(-0.09, top - 0.02, -length + 0.14), Vector3(-0.09, top - 0.02, -0.1), gr, Color.WHITE, Color.WHITE)
	else: kd.quad_rect(pk.GLASS, Vector3(-0.04, belt, -length + 0.06), Vector3(-0.04, belt, -0.06), Vector3(0.09, top - 0.02, -0.1), Vector3(0.09, top - 0.02, -length + 0.14), gr, Color.WHITE, Color.WHITE)
	kd.pop()
	# the dome lamp's light on the snow by the door
	pk.spill_at(Vector3(side * (w0 + 0.1), 0, (z0 + z1) * 0.5), Vector3(side, 0, 0), 0.6, 1.2, 0.35)

## The taxi's own: the small lit roof sign and the meter's flag (LIBRE) up by the windscreen on the passenger's side.
func _taxi_parts(k: Kit, kd: Kit, spec: Dictionary, lit_sign: bool) -> void:
	var y: float = float(spec.roof_y) - 0.01
	var zc := 0.05
	var key: String = pk.GLOW if lit_sign else pk.SOLID
	var c := Color(0.28, 0.27, 0.25) if lit_sign else Color.WHITE
	k.push_tint(Color(0.9, 0.88, 0.8))
	k.box("paint", Vector3(0, y + 0.03, zc), Vector3(0.5, 0.06, 0.2), Color.WHITE, Color.WHITE)
	k.box("paint", Vector3(0, y + 0.16, zc), Vector3(0.48, 0.2, 0.16), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.AUTO, 51)
	k.box("paint", Vector3(0, y + 0.27, zc), Vector3(0.52, 0.02, 0.22), Color.WHITE, Color.WHITE)
	k.pop_tint()
	kd.quad_rect(key, Vector3(-0.24, y + 0.07, zc + 0.085), Vector3(0.24, y + 0.07, zc + 0.085), Vector3(0.24, y + 0.25, zc + 0.085), Vector3(-0.24, y + 0.25, zc + 0.085), pk.uv("taxi_sign"), c, c)
	kd.quad_rect(key, Vector3(0.24, y + 0.07, zc - 0.085), Vector3(-0.24, y + 0.07, zc - 0.085), Vector3(-0.24, y + 0.25, zc - 0.085), Vector3(0.24, y + 0.25, zc - 0.085), pk.uv("taxi_sign"), c, c)
	pk.box_top(k, Vector3(0, y + 0.28, zc), Vector2(0.5, 0.2), 0.06)
	if lit_sign: pk.halo(pk.xf * Vector3(0, y + 0.16, zc), Color(1.0, 0.85, 0.6), 0.5)
	# the meter's flag, raised: free
	var fz: float = float(spec.windows[0][1]) + 0.08
	var fx := -float(spec.hw) * 0.62
	var fy: float = float(spec.belt)
	k.push_tint(pk.IRON)
	k.beam("metal", Vector3(fx, fy - 0.05, fz), Vector3(fx, fy + 0.3, fz), 0.025, 0.025, Color.WHITE, Color.WHITE)
	k.pop_tint()
	kd.quad_rect(pk.SOLID, Vector3(fx - 0.01, fy + 0.18, fz + 0.1), Vector3(fx - 0.01, fy + 0.18, fz - 0.1), Vector3(fx - 0.01, fy + 0.38, fz - 0.1), Vector3(fx - 0.01, fy + 0.38, fz + 0.1), pk.uv("libre"), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.SOLID, Vector3(fx + 0.01, fy + 0.18, fz - 0.1), Vector3(fx + 0.01, fy + 0.18, fz + 0.1), Vector3(fx + 0.01, fy + 0.38, fz + 0.1), Vector3(fx + 0.01, fy + 0.38, fz - 0.1), pk.uv("libre"), Color.WHITE, Color.WHITE)

# ---------------------------------------------------------------------------------------------------------------
# The colectivo
# ---------------------------------------------------------------------------------------------------------------
## A colectivo of the fifties: a short bus with a rounded body on a truck's chassis, its bonnet out in front, painted
## in its line's two colours (invented: here deep red over cream, or `lower` / `upper`), chrome strips, fileteado
## panels on its flanks and its back with an invented motto, the line's number (212, invented) on the roof board and
## the destination over the windscreen; the door on the right at the front; its windows lit when `lit` (a bus in
## service), and the headlamps on. open: the door folded open.
func colectivo(pos: Vector3, yaw: float, lower: Color = Color(0, 0, 0, 0), upper: Color = Color(0, 0, 0, 0), lit: bool = true, open: bool = false, snowed_in: bool = false) -> Node3D:
	pk.begin(Transform3D(Basis(Vector3.UP, yaw), pos))
	var k := Kit.new()
	var kd := Kit.new()
	if lower.a < 0.5: lower = pk.hexc("b0342a")
	if upper.a < 0.5: upper = pk.hexc("e6dcc0")
	var L := 7.6
	var hw := 1.12
	var fz := L * 0.5
	var bonnet := 1.25
	var cab := fz - bonnet
	var r := 0.46
	var wf := cab + 0.35
	var wr := -L * 0.5 + 1.7
	# the body: from the rounded back to the windscreen, then the bonnet
	var body: Array = [st(-fz, 0.62, 2.2, 2.62, 0.95), st(-fz + 0.18, 0.56, 2.32, 2.78, 1.07), st(-fz + 0.5, 0.52, 2.36, 2.84, hw)]
	body.append_array(arch(wr, r, 0.52, 2.36, 2.86, hw))
	body.append_array([st(cab - 1.0, 0.52, 2.36, 2.86, hw), st(cab - 0.25, 0.52, 2.34, 2.8, hw), st(cab, 0.55, 2.2, 2.62, hw * 0.97)])
	# two tones: the lower loft and the upper, meeting at the belt
	loft(k, "paint", body, lower, 0, -1, 0.7)
	var upper_band: Array = []
	for s: Station in body:
		upper_band.append(Station.new(s.z, s.b, s.s, s.t, s.w + 0.006))
	_upper_tone(k, upper_band, upper, 1.5)
	var hood: Array = [st(cab - 0.05, 0.6, 1.18, 1.3, 0.86)]
	hood.append_array(arch(wf, r, 0.6, 1.18, 1.3, 0.92))
	hood.append_array([st(fz - 0.15, 0.62, 1.12, 1.24, 0.8), st(fz, 0.7, 1.02, 1.12, 0.66)])
	loft(k, "paint", hood, lower, 0, -1, 0.8)
	# wings over the front wheels, in the upper colour
	for side: float in [-1.0, 1.0]:
		var wing: Array = []
		for i: int in range(7):
			var a := PI * float(i) / 6.0
			wing.append(st(wf - cos(a) * 0.72, r + sin(a) * 0.58 - 0.1, r + sin(a) * 0.58 + 0.03, r + sin(a) * 0.58 + 0.11, 0.2))
		k.push(Transform3D(Basis.IDENTITY, Vector3(side * 0.98, 0, 0)))
		loft(k, "paint", wing, upper, 0, -1, 0.9)
		k.pop()
	# windows: the lit row down both flanks, the windscreen in two panes, the rear window
	var wl := Color(1.0, 0.86, 0.62) if lit else Color.WHITE
	var wkey: String = pk.LIT if lit else pk.GLASS
	var wcell := "bus_win_lit" if lit else "car_glass"
	for side: float in [-1.0, 1.0]:
		var x := side * (hw + 0.012)
		var z := -fz + 0.7
		while z < cab - 0.9:
			var zz := minf(z + 0.85, cab - 0.25)
			if side > 0.0: kd.quad_rect(wkey, Vector3(x, 1.62, zz), Vector3(x, 1.62, z), Vector3(x, 2.26, z), Vector3(x, 2.26, zz), pk.uv(wcell), wl, wl)
			else: kd.quad_rect(wkey, Vector3(x, 1.62, z), Vector3(x, 1.62, zz), Vector3(x, 2.26, zz), Vector3(x, 2.26, z), pk.uv(wcell), wl, wl)
			z += 0.98
		# the fileteado panel on the flank, under the windows at the back
		if side > 0.0: kd.quad_rect(pk.CUT, Vector3(x, 0.78, -fz + 3.1), Vector3(x, 0.78, -fz + 0.5), Vector3(x, 1.38, -fz + 0.5), Vector3(x, 1.38, -fz + 3.1), pk.uv("filete_side"), Color.WHITE, Color.WHITE)
		else: kd.quad_rect(pk.CUT, Vector3(x, 0.78, -fz + 0.5), Vector3(x, 0.78, -fz + 3.1), Vector3(x, 1.38, -fz + 3.1), Vector3(x, 1.38, -fz + 0.5), pk.uv("filete_side"), Color.WHITE, Color.WHITE)
		# chrome strips along the flank
		chrome(k, PackedVector3Array([Vector3(side * (hw + 0.01), 1.5, -fz + 0.4), Vector3(side * (hw + 0.01), 1.5, cab - 0.1)]), 0.02)
		chrome(k, PackedVector3Array([Vector3(side * (hw + 0.01), 0.72, -fz + 0.4), Vector3(side * (hw + 0.01), 0.72, wr - 0.6)]), 0.018)
	for px: Array in [[-1.0, -0.04], [0.04, 1.0]]:
		var x0: float = float(px[0]) * 0.98
		var x1: float = float(px[1]) * 0.98
		kd.quad_rect(pk.LIT if lit else pk.GLASS, Vector3(x0, 1.45, cab + 0.03), Vector3(x1, 1.45, cab + 0.03), Vector3(x1, 2.18, cab - 0.08), Vector3(x0, 2.18, cab - 0.08), pk.uv("bus_win_lit" if lit else "car_glass"), wl * 0.8, wl * 0.8)
	kd.quad_rect(pk.SOLID, Vector3(-0.95, 2.26, cab - 0.05), Vector3(0.95, 2.26, cab - 0.05), Vector3(0.95, 2.6, cab - 0.12), Vector3(-0.95, 2.6, cab - 0.12), pk.uv("bus_dest"), Color.WHITE, Color.WHITE)
	# the line's number on its board on the roof's front, both faces
	k.push_tint(pk.IRON)
	k.box("metal", Vector3(0, 2.98, cab - 0.5), Vector3(0.9, 0.42, 0.06), Color.WHITE, Color.WHITE)
	k.pop_tint()
	kd.quad_rect(pk.GLOW if lit else pk.SOLID, Vector3(-0.42, 2.79, cab - 0.465), Vector3(0.42, 2.79, cab - 0.465), Vector3(0.42, 3.17, cab - 0.465), Vector3(-0.42, 3.17, cab - 0.465), pk.uv("bus_num"), Color(0.3, 0.28, 0.25) if lit else Color.WHITE, Color(0.3, 0.28, 0.25) if lit else Color.WHITE)
	kd.quad_rect(pk.SOLID, Vector3(0.42, 2.79, cab - 0.535), Vector3(-0.42, 2.79, cab - 0.535), Vector3(-0.42, 3.17, cab - 0.535), Vector3(0.42, 3.17, cab - 0.535), pk.uv("bus_num"), Color.WHITE, Color.WHITE)
	# the back: its window, the fileteado with the motto
	kd.quad_rect(pk.LIT if lit else pk.GLASS, Vector3(0.7, 1.7, -fz - 0.01), Vector3(-0.7, 1.7, -fz - 0.01), Vector3(-0.6, 2.3, -fz + 0.1), Vector3(0.6, 2.3, -fz + 0.1), pk.uv(wcell), wl * 0.7, wl * 0.7)
	kd.quad_rect(pk.CUT, Vector3(0.75, 0.85, -fz - 0.02), Vector3(-0.75, 0.85, -fz - 0.02), Vector3(-0.75, 1.6, -fz - 0.02), Vector3(0.75, 1.6, -fz - 0.02), pk.uv("filete_rear"), Color.WHITE, Color.WHITE)
	# the door at the front on the right (the kerb side): shut, or folded open with the lit step inside
	var dx := -(hw + 0.015)
	var dz0 := cab - 0.25
	var dz1 := cab - 1.2
	if open:
		kd.quad_rect(pk.LIT if lit else pk.SOLID, Vector3(dx, 0.5, dz0), Vector3(dx, 0.5, dz1), Vector3(dx, 2.3, dz1), Vector3(dx, 2.3, dz0), pk.uv("tiles_lit" if lit else "dark"), Color(1.0, 0.8, 0.55) * 0.6, Color(1.0, 0.8, 0.55) * 0.6)
		k.push_tint(upper)
		k.box("paint", Vector3(dx - 0.25, 1.4, dz0 - 0.02), Vector3(0.48, 1.8, 0.05), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		pk.spill_at(Vector3(dx - 0.1, 0, (dz0 + dz1) * 0.5), Vector3(-1, 0, 0), 0.9, 2.2, 0.6 if lit else 0.2)
	else:
		kd.quad_rect(pk.LIT if lit else pk.GLASS, Vector3(dx, 1.0, dz0), Vector3(dx, 1.0, dz1), Vector3(dx, 2.26, dz1), Vector3(dx, 2.26, dz0), pk.uv(wcell), wl * 0.8, wl * 0.8)
		kd.quad_rect(pk.SOLID, Vector3(dx, 0.55, (dz0 + dz1) * 0.5 + 0.01), Vector3(dx, 0.55, (dz0 + dz1) * 0.5 - 0.01), Vector3(dx, 2.3, (dz0 + dz1) * 0.5 - 0.01), Vector3(dx, 2.3, (dz0 + dz1) * 0.5 + 0.01), pk.uv("dark"), Color.WHITE, Color.WHITE)
	# the nose: grille, bumper, lamps
	kd.quad_rect(pk.SOLID, Vector3(0.42, 0.72, fz + 0.01), Vector3(-0.42, 0.72, fz + 0.01), Vector3(-0.42, 1.06, fz + 0.01), Vector3(0.42, 1.06, fz + 0.01), pk.uv("grille_truck"), Color.WHITE, Color.WHITE)
	chrome(k, PackedVector3Array([Vector3(-1.0, 0.55, fz - 0.15), Vector3(-0.9, 0.55, fz + 0.12), Vector3(0.9, 0.55, fz + 0.12), Vector3(1.0, 0.55, fz - 0.15)]), 0.08)
	chrome(k, PackedVector3Array([Vector3(-1.05, 0.55, -fz + 0.2), Vector3(-0.95, 0.55, -fz - 0.08), Vector3(0.95, 0.55, -fz - 0.08), Vector3(1.05, 0.55, -fz + 0.2)]), 0.07)
	for side: float in [-1.0, 1.0]:
		lamp(kd, Vector3(side * 0.82, 1.0, wf + 0.42), Vector3(0, 0, 1), 0.13, "headlamp", lit)
		lamp(kd, Vector3(side * 0.85, 0.95, -fz - 0.03), Vector3(0, 0, -1), 0.07, "taillamp", false)
		for wz: float in [wf, wr]:
			wheel(k, kd, Vector3(side * (hw - 0.22), r, wz), r, 0.28, side, "spokes")
	if lit:
		pk.halo(pk.xf * Vector3(0, 1.0, fz + 0.3), pk.WARM, 0.8)
		pk.spill_at(Vector3(0, 0, fz + 0.3), Vector3(0, 0, 1), 1.6, 6.0, 0.7)
	snowed(k, [[Rect2(-hw + 0.15, -fz + 0.4, hw * 2.0 - 0.3, L - bonnet - 0.7), 2.86, 0.16], [Rect2(-0.7, cab + 0.1, 1.4, bonnet - 0.3), 1.3, 0.08]], fz, hw, snowed_in)
	return _place("Colectivo", pos, yaw, k, kd)

## The upper of two tones: the ring from the belt on one side over the top to the belt on the other, laid a hair
## outside the lower loft.
func _upper_tone(k: Kit, stations: Array, tint: Color, belt_y: float) -> void:
	var rows := stations.size()
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := 0
	for s: Station in stations:
		var r := ring(s, 0.7)
		var keep: Array[Vector2] = []
		# right side from the belt up, over the top, down the left side to the belt
		var n := r.size()
		var half := n / 2
		for i: int in range(n):
			var p := r[i]
			if p.y >= belt_y - 0.001 and i <= half: keep.append(p)
		var right_belt := Vector2(s.w * 1.0, belt_y)
		var pts_line: Array[Vector2] = [right_belt]
		for p: Vector2 in keep:
			if p.y > belt_y: pts_line.append(p)
		var mirrored: Array[Vector2] = []
		for i: int in range(pts_line.size() - 2, -1, -1): mirrored.append(Vector2(-pts_line[i].x, pts_line[i].y))
		pts_line.append_array(mirrored)
		# (resampled to the same count at every station: where the body rises over a wheel the ring keeps fewer of
		# its points above the belt, and a patch needs a regular grid)
		var line := _resample(pts_line, 33)
		cols = line.size()
		for p: Vector2 in line:
			pts.append(Vector3(p.x, p.y, s.z))
			uvs.append(Vector2(s.z * Kit.UV_M, 1.0 - p.y * Kit.UV_M))
	k.push_tint(tint)
	k.patch("paint", rows, cols, pts, uvs, PackedColorArray([Color.WHITE]))
	k.pop_tint()

## A polyline resampled to `count` points evenly along its length.
static func _resample(line: Array[Vector2], count: int) -> Array[Vector2]:
	var lengths: Array[float] = [0.0]
	for i: int in range(1, line.size()):
		lengths.append(lengths[i - 1] + line[i].distance_to(line[i - 1]))
	var total: float = lengths[lengths.size() - 1]
	var out: Array[Vector2] = []
	var j := 0
	for i: int in range(count):
		var d := total * float(i) / float(count - 1)
		while j < line.size() - 2 and lengths[j + 1] < d:
			j += 1
		var seg := maxf(lengths[j + 1] - lengths[j], 1e-6)
		out.append(line[j].lerp(line[j + 1], clampf((d - lengths[j]) / seg, 0.0, 1.0)))
	return out

# ---------------------------------------------------------------------------------------------------------------
# The tram
# ---------------------------------------------------------------------------------------------------------------
## A tram of the time in an invented company's colours (TRANVÍAS RIBERA, car 214: dark green below, cream above): a
## long single-deck car rounded at both ends, its windows lit, the destination box (PLAZA DE MAYO) over the motorman's
## window at each end, the company's name along its flanks, a clerestory roof under a long cap of snow, the trolley
## pole raised toward the wire at `wire_y` (0: lowered), two trucks and their wheels, the lifeguards.
func tram(pos: Vector3, yaw: float, lit: bool = true, wire_y: float = 5.6) -> Node3D:
	pk.begin(Transform3D(Basis(Vector3.UP, yaw), pos))
	var k := Kit.new()
	var kd := Kit.new()
	var green: Color = pk.hexc("2f4f3a")
	var cream: Color = pk.hexc("ddd0aa")
	var L := 11.6
	var hw := 1.2
	var fz := L * 0.5
	var stations: Array = []
	for i: int in range(5):
		var a := PI * 0.5 * float(i) / 4.0
		stations.append(st(-fz + (1.0 - sin(a)) * 0.9, 0.62, 2.6, 2.95, hw * (0.55 + 0.45 * sin(a))))
	stations.append(st(0.0, 0.62, 2.6, 2.95, hw))
	for i: int in range(4, -1, -1):
		var a := PI * 0.5 * float(i) / 4.0
		stations.append(st(fz - (1.0 - sin(a)) * 0.9, 0.62, 2.6, 2.95, hw * (0.55 + 0.45 * sin(a))))
	loft(k, "paint", stations, green, 0, -1, 0.85)
	var up: Array = []
	for s: Station in stations: up.append(Station.new(s.z, s.b, s.s, s.t, s.w + 0.006))
	_upper_tone(k, up, cream, 1.55)
	# a gold line at the belt
	for side: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		for s: Station in stations: path.append(Vector3(side * (s.w + 0.012), 1.52, s.z))
		k.push_tint(pk.hexc("c8a040"))
		k.tube("paint", path, 0.018, 4, Color.WHITE)
		k.pop_tint()
	# windows lit down both flanks, round the ends; the company's name under them, the number
	var wl := Color(1.0, 0.86, 0.62)
	var wkey: String = pk.LIT if lit else pk.GLASS
	var wcell := "tram_win_lit" if lit else "car_glass"
	for side: float in [-1.0, 1.0]:
		var x := side * (hw + 0.013)
		var z := -fz + 1.0
		while z < fz - 1.4:
			var zz := z + 0.95
			if side > 0.0: kd.quad_rect(wkey, Vector3(x, 1.68, zz), Vector3(x, 1.68, z), Vector3(x, 2.42, z), Vector3(x, 2.42, zz), pk.uv(wcell), wl, wl)
			else: kd.quad_rect(wkey, Vector3(x, 1.68, z), Vector3(x, 1.68, zz), Vector3(x, 2.42, zz), Vector3(x, 2.42, z), pk.uv(wcell), wl, wl)
			z += 1.08
		var cz0 := -1.6
		var cz1 := 1.6
		if side > 0.0: kd.quad_rect(pk.SOLID, Vector3(x, 0.95, cz1), Vector3(x, 0.95, cz0), Vector3(x, 1.35, cz0), Vector3(x, 1.35, cz1), pk.uv("tram_company"), Color.WHITE, Color.WHITE)
		else: kd.quad_rect(pk.SOLID, Vector3(x, 0.95, cz0), Vector3(x, 0.95, cz1), Vector3(x, 1.35, cz1), Vector3(x, 1.35, cz0), pk.uv("tram_company"), Color.WHITE, Color.WHITE)
	for e: float in [-1.0, 1.0]:
		var ez := e * (fz + 0.01)
		var a := Vector3(-0.7 * e, 2.62, ez)
		var b := Vector3(0.7 * e, 2.62, ez)
		kd.quad_rect(pk.GLOW if lit else pk.SOLID, a, b, b + Vector3(0, 0.26, 0), a + Vector3(0, 0.26, 0), pk.uv("tram_dest"), Color(0.8, 0.8, 0.75) if lit else Color.WHITE, Color(0.8, 0.8, 0.75) if lit else Color.WHITE)
		kd.quad_rect(wkey, Vector3(-0.55 * e, 1.7, ez), Vector3(0.55 * e, 1.7, ez), Vector3(0.55 * e, 2.45, ez), Vector3(-0.55 * e, 2.45, ez), pk.uv(wcell), wl * 0.8, wl * 0.8)
		kd.quad_rect(pk.SOLID, Vector3(-0.32 * e, 1.0, ez), Vector3(0.32 * e, 1.0, ez), Vector3(0.32 * e, 1.32, ez), Vector3(-0.32 * e, 1.32, ez), pk.uv("tram_num"), Color.WHITE, Color.WHITE)
		lamp(kd, Vector3(0, 0.82, ez + e * 0.01), Vector3(0, 0, e), 0.12, "headlamp", lit and e > 0.0)
		# the lifeguard and the fender
		k.push_tint(pk.IRON)
		k.box("metal", Vector3(0, 0.36, e * (fz + 0.25)), Vector3(1.6, 0.12, 0.4), Color.WHITE, Color.WHITE)
		k.pop_tint()
	# the roof: the clerestory with its little lit lights, under snow
	k.push_tint(Color(0.42, 0.42, 0.4))
	k.box("metal", Vector3(0, 3.1, 0), Vector3(1.3, 0.3, L - 2.6), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	for side: float in [-1.0, 1.0]:
		var z := -fz + 1.6
		while z < fz - 1.8:
			if side > 0.0: kd.quad_rect(wkey, Vector3(0.651, 2.99, z + 0.6), Vector3(0.651, 2.99, z), Vector3(0.651, 3.2, z), Vector3(0.651, 3.2, z + 0.6), pk.uv(wcell), wl * 0.7, wl * 0.7)
			else: kd.quad_rect(wkey, Vector3(-0.651, 2.99, z), Vector3(-0.651, 2.99, z + 0.6), Vector3(-0.651, 3.2, z + 0.6), Vector3(-0.651, 3.2, z), pk.uv(wcell), wl * 0.7, wl * 0.7)
			z += 0.9
	pk.box_top(k, Vector3(0, 3.25, 0), Vector2(1.3, L - 2.7), 0.18)
	for side: float in [-1.0, 1.0]:
		pk.ridge(k, Vector3(side * 0.95, 2.93, -fz + 1.0), Vector3(side * 0.95, 2.93, fz - 1.0), Vector3.UP, 0.5, 0.12, 0.05, 0.5, true)
	# the trucks and their wheels
	for tz: float in [-fz + 2.6, fz - 2.6]:
		k.push_tint(pk.IRON)
		k.box("metal", Vector3(0, 0.5, tz), Vector3(1.9, 0.32, 2.2), Color.WHITE, Color.WHITE)
		k.pop_tint()
		for dz: float in [-0.7, 0.7]:
			for side: float in [-1.0, 1.0]:
				wheel(k, kd, Vector3(side * 0.72, 0.38, tz + dz), 0.38, 0.12, side, "spokes")
	# the trolley pole, raised to the wire (or lowered along the roof)
	var base := Vector3(0, 3.28, -fz * 0.35)
	k.push_tint(pk.IRON)
	k.box("metal", base, Vector3(0.5, 0.12, 0.6), Color.WHITE, Color.WHITE)
	var tip := Vector3(0, wire_y, fz * 0.15) if wire_y > 3.5 else Vector3(0, 3.42, fz * 0.45)
	k.beam("metal", base, tip, 0.05, 0.05, Color.WHITE, Color.WHITE)
	k.pop_tint()
	if lit:
		pk.spill_at(Vector3(hw, 0, 0), Vector3(1, 0, 0), L * 0.4, 2.2, 0.45)
		pk.spill_at(Vector3(-hw, 0, 0), Vector3(-1, 0, 0), L * 0.4, 2.2, 0.45)
		pk.halo(pk.xf * Vector3(0, 0.82, fz + 0.2), pk.WARM, 0.7)
	return _place("Tram", pos, yaw, k, kd)

# ---------------------------------------------------------------------------------------------------------------
# The delivery truck
# ---------------------------------------------------------------------------------------------------------------
## A soda-delivery truck of the forties and fifties (the sodero's): a rounded cab behind a long bonnet and flowing
## front wings, a flatbed with slatted sides, crates of siphons stacked on it, the trade (no name) painted with
## fileteado on the cab's doors. open: the driver's door standing open.
func truck(pos: Vector3, yaw: float, paint: Color = Color(0, 0, 0, 0), open: bool = false, snowed_in: bool = true) -> Node3D:
	pk.begin(Transform3D(Basis(Vector3.UP, yaw), pos))
	var k := Kit.new()
	var kd := Kit.new()
	if paint.a < 0.5: paint = pk.hexc("2c4a5e")
	var L := 6.4
	var fz := L * 0.5
	var r := 0.45
	var wf := fz - 1.0
	var wr := -fz + 1.45
	# the bonnet and the wings
	var hood: Array = [st(fz - 2.3, 0.75, 1.4, 1.5, 0.62), st(fz - 0.6, 0.78, 1.34, 1.44, 0.6), st(fz - 0.1, 0.82, 1.24, 1.32, 0.52), st(fz, 0.9, 1.12, 1.2, 0.44)]
	loft(k, "paint", hood, paint, 0, -1, 0.8)
	for side: float in [-1.0, 1.0]:
		var wing: Array = []
		for i: int in range(7):
			var a := PI * float(i) / 6.0
			wing.append(st(wf - cos(a) * 0.75, r + sin(a) * 0.55 - 0.12, r + sin(a) * 0.55 + 0.02, r + sin(a) * 0.55 + 0.1, 0.24))
		k.push(Transform3D(Basis.IDENTITY, Vector3(side * 0.82, 0, 0)))
		loft(k, "paint", wing, paint * 0.9, 0, -1, 0.9)
		k.pop()
		lamp(kd, Vector3(side * 0.78, 1.08, fz - 0.3), Vector3(0, 0, 1), 0.12, "headlamp", false)
	# the cab
	var cab: Array = [st(fz - 3.3, 0.72, 1.7, 2.35, 0.95), st(fz - 3.15, 0.7, 1.8, 2.45, 1.0), st(fz - 2.45, 0.7, 1.8, 2.45, 1.0), st(fz - 2.25, 0.72, 1.6, 2.2, 0.98)]
	loft(k, "paint", cab, paint, 0, -1, 0.8)
	for side: float in [-1.0, 1.0]:
		var x := side * 1.012
		var a := Vector3(x, 1.65, fz - 2.5)
		var b := Vector3(x, 1.65, fz - 3.05)
		if side > 0.0: kd.quad_rect(pk.GLASS, a, b, b + Vector3(0, 0.6, 0), a + Vector3(0, 0.6, 0), pk.uv("car_glass"), Color.WHITE, Color.WHITE)
		else: kd.quad_rect(pk.GLASS, b, a, a + Vector3(0, 0.6, 0), b + Vector3(0, 0.6, 0), pk.uv("car_glass"), Color.WHITE, Color.WHITE)
		var c0 := Vector3(x, 0.95, fz - 2.45)
		var c1 := Vector3(x, 0.95, fz - 3.15)
		if side > 0.0: kd.quad_rect(pk.SOLID, c0 + Vector3(0, 0, 0), c1, c1 + Vector3(0, 0.6, 0), c0 + Vector3(0, 0.6, 0), pk.uv_part("sign_soderia", 0.05, 0.95), Color.WHITE, Color.WHITE)
		else: kd.quad_rect(pk.SOLID, c1, c0, c0 + Vector3(0, 0.6, 0), c1 + Vector3(0, 0.6, 0), pk.uv_part("sign_soderia", 0.05, 0.95), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.GLASS, Vector3(-0.85, 1.75, fz - 2.27), Vector3(0.85, 1.75, fz - 2.27), Vector3(0.82, 2.18, fz - 2.38), Vector3(-0.82, 2.18, fz - 2.38), pk.uv("car_glass"), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.SOLID, Vector3(0.36, 0.95, fz + 0.01), Vector3(-0.36, 0.95, fz + 0.01), Vector3(-0.36, 1.18, fz + 0.01), Vector3(0.36, 1.18, fz + 0.01), pk.uv("grille_truck"), Color.WHITE, Color.WHITE)
	chrome(k, PackedVector3Array([Vector3(-1.0, 0.6, fz + 0.05), Vector3(1.0, 0.6, fz + 0.05)]), 0.07)
	if open:
		var hinge := Vector3(-1.03, 0, fz - 2.45)
		kd.quad_rect(pk.SOLID, Vector3(-1.015, 0.8, fz - 3.1), Vector3(-1.015, 0.8, fz - 2.48), Vector3(-1.015, 2.2, fz - 2.48), Vector3(-1.015, 2.2, fz - 3.1), pk.uv("dark"), Color.WHITE, Color.WHITE)
		k.push(Transform3D(Basis(Vector3.UP, 1.1), hinge))
		k.push_tint(paint)
		k.box("paint", Vector3(-0.04, 1.5, -0.33), Vector3(0.07, 1.4, 0.66), Color(0.8, 0.8, 0.8), Color.WHITE)
		k.pop_tint()
		k.pop()
	# the chassis, the flatbed and its slatted sides, crates of siphons on it
	k.push_tint(pk.IRON)
	k.box("metal", Vector3(0, 0.7, -0.2), Vector3(1.1, 0.25, L - 0.6), Color.WHITE, Color.WHITE)
	k.pop_tint()
	var bed_z0 := -fz
	var bed_z1 := fz - 3.4
	k.push_tint(pk.hexc("6a5440"))
	k.box("planks", Vector3(0, 0.95, (bed_z0 + bed_z1) * 0.5), Vector3(2.1, 0.12, bed_z1 - bed_z0), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	for side: float in [-1.0, 1.0]:
		for yy: float in [1.2, 1.5]:
			k.box("planks", Vector3(side * 1.03, yy, (bed_z0 + bed_z1) * 0.5), Vector3(0.05, 0.16, bed_z1 - bed_z0), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		var z := bed_z0 + 0.05
		while z <= bed_z1:
			k.box("planks", Vector3(side * 1.03, 1.3, z), Vector3(0.07, 0.7, 0.08), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
			z += 0.75
	k.box("planks", Vector3(0, 1.3, bed_z1 + 0.02), Vector3(2.1, 0.7, 0.06), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	var cz := bed_z0 + 0.4
	var row := 0
	while cz < bed_z1 - 0.3:
		for cx: float in [-0.52, 0.0, 0.52]:
			var layers := 3 if (row + int(cx * 10.0)) % 2 == 0 else 2
			for ly: int in range(layers):
				var cb := Vector3(cx, 1.01 + float(ly) * 0.42 + 0.21, cz)
				k.push_tint(pk.hexc("8a3a28"))
				k.box("planks", cb, Vector3(0.48, 0.4, 0.5), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.AUTO, 47)
				k.pop_tint()
				for fside: float in [-1.0, 1.0]:
					var fzz := cz + fside * 0.252
					if fside > 0.0: kd.quad_rect(pk.SOLID, Vector3(cx - 0.24, cb.y - 0.2, fzz), Vector3(cx + 0.24, cb.y - 0.2, fzz), Vector3(cx + 0.24, cb.y + 0.2, fzz), Vector3(cx - 0.24, cb.y + 0.2, fzz), pk.uv("siphons"), Color.WHITE, Color.WHITE)
					else: kd.quad_rect(pk.SOLID, Vector3(cx + 0.24, cb.y - 0.2, fzz), Vector3(cx - 0.24, cb.y - 0.2, fzz), Vector3(cx - 0.24, cb.y + 0.2, fzz), Vector3(cx + 0.24, cb.y + 0.2, fzz), pk.uv("siphons"), Color.WHITE, Color.WHITE)
				if ly == layers - 1: pk.box_top(k, cb + Vector3(0, 0.2, 0), Vector2(0.46, 0.48), 0.09)
		cz += 0.56
		row += 1
	for side: float in [-1.0, 1.0]:
		wheel(k, kd, Vector3(side * 0.85, r, wf), r, 0.26, side, "spokes")
		wheel(k, kd, Vector3(side * 0.82, r, wr), r, 0.26, side, "spokes")
		wheel(k, kd, Vector3(side * 0.56, r, wr), r, 0.24, side, "spokes")
	snowed(k, [[Rect2(-0.85, fz - 3.2, 1.7, 0.85), 2.45, 0.14], [Rect2(-0.5, fz - 2.2, 1.0, 2.0), 1.5, 0.08]], fz, 1.05, snowed_in)
	return _place("Truck", pos, yaw, k, kd)
