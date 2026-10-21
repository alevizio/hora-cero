extends RefCounted
## The Plaza de Mayo kit's monuments and street furniture (plaza_kit.gd builds through this): the Pirámide de Mayo, the
## Belgrano monument, Canary palms, bare plane trees, lawns behind their low iron hoops, benches, the cast-iron lamp
## posts with their globes, the Subte's stairs down, a newspaper kiosk, a flagpole. The repeated things (lamp posts,
## palms, trees, benches) are gathered and drawn as multimeshes when the kit finishes.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")

var pk: RefCounted
var rng := RandomNumberGenerator.new()

func _init(owner: RefCounted) -> void:
	pk = owner
	rng.seed = 5810

# ---------------------------------------------------------------------------------------------------------------
# The Pirámide de Mayo
# ---------------------------------------------------------------------------------------------------------------
## The Pirámide de Mayo as it stood in 1958: in the middle of the square since 1912, with none of its four corner
## statues (taken away that year, back only in 2018). White: three steps, the pedestal with the golden sun on its east
## face and laurel crowns in relief on the other three, a plinth, the obelisk's shaft tapering to its capital, and on
## top the Liberty (3.6 m) on her little pedestal; 18.76 m to the tip of her cap (the notes). Round it the iron railing
## with a lamp at each corner (the 1856 fence had gas lamps there; whether they stood in 1958 the notes do not say).
## `face`: where the sun looks (east, at the Casa Rosada). The statue is a simple robed figure in a Phrygian cap with a
## staff and a shield: dignified massing, not a copy of Dubourdieu's.
func piramide(pos: Vector3, face: Vector3, fence: bool = true, corner_lamps: bool = true) -> Node3D:
	var pxf: Transform3D = pk.placed(pos, face)
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var white := Color(0.94, 0.93, 0.91)
	var stone := Color(0.8, 0.79, 0.77)
	# the steps, snow on each tread
	for i: int in range(3):
		var s := 9.6 - float(i) * 0.9
		var y := float(i) * 0.3
		k.push_tint(stone)
		k.box("marble", Vector3(0, y + 0.15, 0), Vector3(s, 0.3, s), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		var tread := s - 0.45
		for c: int in range(4):
			var a := Vector2(-tread * 0.5, tread * 0.5).rotated(-float(c) * PI * 0.5)
			var b := Vector2(tread * 0.5, tread * 0.5).rotated(-float(c) * PI * 0.5)
			pk.ridge(k, Vector3(a.x, y + 0.3, a.y), Vector3(b.x, y + 0.3, b.y), Vector3.UP, 0.36, 0.1, 0.04)
	# the pedestal: a moulded foot, the die with its reliefs, a cornice
	var y0 := 0.9
	pk.frustum(k, "marble", Vector3.ZERO, y0, 5.1, y0 + 0.3, 4.6, white, false)
	k.push_tint(white)
	k.box("marble", Vector3(0, y0 + 0.3 + 1.55, 0), Vector3(4.4, 3.1, 4.4), Color(0.78, 0.78, 0.78), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	var yc := y0 + 3.4
	pk.frustum(k, "marble", Vector3.ZERO, yc, 4.4, yc + 0.28, 5.0, white, false)
	k.push_tint(white)
	k.box("marble", Vector3(0, yc + 0.38, 0), Vector3(5.0, 0.2, 5.0), Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop_tint()
	for c: int in range(4):
		var a := Vector2(-2.3, 2.3).rotated(-float(c) * PI * 0.5)
		var b := Vector2(2.3, 2.3).rotated(-float(c) * PI * 0.5)
		pk.ridge(k, Vector3(a.x, yc + 0.48, a.y), Vector3(b.x, yc + 0.48, b.y), Vector3.UP, 0.5, 0.14, 0.05)
	for c: int in range(4):
		var yaw := float(c) * PI * 0.5
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var r := Vector3(n.z, 0, -n.x)
		var o := n * 2.215 + Vector3(0, y0 + 1.85, 0)
		var cell := "sun_relief" if c == 0 else "laurel"
		var sz := 0.95 if c == 0 else 0.8
		kd.quad_rect(pk.SOLID, o - r * sz - Vector3(0, sz, 0), o + r * sz - Vector3(0, sz, 0), o + r * sz + Vector3(0, sz, 0), o - r * sz + Vector3(0, sz, 0), pk.uv(cell), Color.WHITE, Color.WHITE)
	# the plinth over it, and the shaft
	var yp := yc + 0.48
	k.push_tint(white)
	k.box("marble", Vector3(0, yp + 0.5, 0), Vector3(3.0, 1.0, 3.0), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	pk.frustum(k, "marble", Vector3.ZERO, yp + 1.0, 3.0, yp + 1.18, 3.3, white)
	for c: int in range(4):
		var a := Vector2(-1.55, 1.55).rotated(-float(c) * PI * 0.5)
		var b := Vector2(1.55, 1.55).rotated(-float(c) * PI * 0.5)
		pk.ridge(k, Vector3(a.x, yp + 1.18, a.y), Vector3(b.x, yp + 1.18, b.y), Vector3.UP, 0.4, 0.12, 0.04)
	var ys := yp + 1.18
	var ytop := 14.25
	pk.frustum(k, "marble", Vector3.ZERO, ys, 2.1, ytop, 1.35, white, false)
	# the shaft's capital, a small cornice under the statue's pedestal
	pk.frustum(k, "marble", Vector3.ZERO, ytop, 1.35, ytop + 0.28, 1.8, white, false)
	k.push_tint(white)
	k.box("marble", Vector3(0, ytop + 0.36, 0), Vector3(1.8, 0.16, 1.8), Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop_tint()
	pk.box_top(k, Vector3(0, ytop + 0.44, 0), Vector2(1.75, 1.75), 0.12)
	pk.frustum(k, "marble", Vector3.ZERO, ytop + 0.44, 1.2, ytop + 0.9, 1.05, white)
	_liberty(k, Vector3(0, ytop + 0.9, 0), 18.76 - (ytop + 0.9), white)
	# the railing round it, and its corner lamps
	if fence:
		var half := 6.2
		var iron := Color(0.12, 0.13, 0.13)
		k.push_tint(Color(0.55, 0.54, 0.52))
		for c: int in range(4):
			var a := Vector2(-half, half).rotated(-float(c) * PI * 0.5)
			var b := Vector2(half, half).rotated(-float(c) * PI * 0.5)
			k.beam("ashlar", Vector3(a.x, 0.12, a.y), Vector3(b.x, 0.12, b.y), 0.4, 0.24, Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		for c: int in range(4):
			var a := Vector2(-half, half).rotated(-float(c) * PI * 0.5)
			var b := Vector2(half, half).rotated(-float(c) * PI * 0.5)
			var a3 := Vector3(a.x, 0.24, a.y)
			var b3 := Vector3(b.x, 0.24, b.y)
			pk.ridge(k, a3 + Vector3(0, 0.0, 0), b3, Vector3.UP, 0.42, 0.1, 0.03)
			var length := a3.distance_to(b3)
			var s := 0.0
			while s < length - 0.01:
				var t := minf(2.6, length - s)
				var p0 := a3.lerp(b3, s / length)
				var p1 := a3.lerp(b3, (s + t) / length)
				kd.quad_rect(pk.CUT, p0, p1, p1 + Vector3(0, 1.25, 0), p0 + Vector3(0, 1.25, 0), pk.uv_part("rail_ornate", 0.0, t / 2.6), iron, iron * 1.3)
				s += t
			var post := Vector3(a.x, 0.24, a.y)
			k.push_tint(iron)
			k.lathe("metal", post, PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.1, 0.2), Vector2(0.06, 0.3), Vector2(0.06, 1.3), Vector2(0.1, 1.38), Vector2(0.0, 1.5)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
			k.pop_tint()
			if corner_lamps:
				lantern_post(k, kd, post + Vector3(a.x, 0, a.y).normalized() * 0.0, 3.0)
	var node: Node3D = pk.piece("Piramide", pxf, k, kd)
	pk.end()
	return node

## The Liberty on top: a robed standing figure at `base`, `h` tall, facing +z: the gown flaring to the plinth, a
## girdle, the cloak from her shoulders, her head in a Phrygian cap whose crown falls forward, the right hand raised on
## a tall staff, the left resting on an oval shield at her side. Snow on her shoulders, her cap, the shield's rim.
func _liberty(k: Kit, base: Vector3, h: float, tint: Color) -> void:
	var s := h / 3.6
	k.push(Transform3D(Basis.from_scale(Vector3(s, s, s)), base))
	k.push_tint(tint)
	# the gown and the body
	k.lathe("marble", Vector3.ZERO, PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.6, 0.12), Vector2(0.5, 0.6), Vector2(0.42, 1.2), Vector2(0.36, 1.75), Vector2(0.31, 1.95),
		Vector2(0.34, 2.15), Vector2(0.4, 2.5), Vector2(0.44, 2.72), Vector2(0.36, 2.86), Vector2(0.14, 2.92), Vector2(0.12, 3.0)]), 12, Color(0.72, 0.72, 0.72), Color.WHITE)
	# the folds of the gown: a few long ribs down the front and sides
	for i: int in range(7):
		var a := -1.2 + float(i) * 0.4
		var top := Vector3(sin(a) * 0.36, 1.9, cos(a) * 0.36)
		var foot := Vector3(sin(a) * 0.6, 0.05, cos(a) * 0.6)
		k.beam("marble", foot, top, 0.08, 0.06, Color(0.75, 0.75, 0.75), Color.WHITE)
	# the cloak hanging behind from the shoulders
	k.beam("marble", Vector3(0, 2.75, -0.32), Vector3(0, 0.2, -0.62), 0.7, 0.16, Color(0.7, 0.7, 0.7), Color.WHITE)
	# the head, the cap
	k.lathe("marble", Vector3(0, 2.98, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.15, 0.06), Vector2(0.19, 0.22), Vector2(0.16, 0.38), Vector2(0.0, 0.44)]), 10, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.push(Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0, 3.26, -0.02)))
	k.lathe("marble", Vector3.ZERO, PackedVector2Array([Vector2(0.21, 0.0), Vector2(0.2, 0.14), Vector2(0.14, 0.3), Vector2(0.07, 0.42), Vector2(0.0, 0.46)]), 10, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop()
	# the right arm raised on the staff, the left down on the shield
	var sh_r := Vector3(0.4, 2.72, 0.02)
	var el_r := Vector3(0.62, 3.0, 0.12)
	var ha_r := Vector3(0.62, 3.42, 0.14)
	k.beam("marble", sh_r, el_r, 0.18, 0.18, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.beam("marble", el_r, ha_r, 0.15, 0.15, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.lathe("marble", Vector3(0.62, 0.0, 0.14), PackedVector2Array([Vector2(0.045, 0.0), Vector2(0.04, 4.0), Vector2(0.08, 4.05), Vector2(0.0, 4.35)]), 6, Color(0.8, 0.8, 0.8), Color.WHITE)
	var sh_l := Vector3(-0.4, 2.72, 0.02)
	var el_l := Vector3(-0.56, 2.25, 0.08)
	var ha_l := Vector3(-0.66, 1.85, 0.16)
	k.beam("marble", sh_l, el_l, 0.17, 0.17, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.beam("marble", el_l, ha_l, 0.15, 0.15, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.push(Transform3D(Basis(Vector3.UP, -0.5) * Basis(Vector3.BACK, -0.12) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.35)), Vector3(-0.8, 1.15, 0.12)))
	k.lathe("marble", Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.52, 0.06), Vector2(0.4, 0.14), Vector2(0.0, 0.16)]), 14, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop()
	k.pop_tint()
	# snow on her shoulders and cap, on the shield's top
	pk.ridge(k, Vector3(-0.42, 2.78, 0.0), Vector3(-0.12, 2.92, 0.0), Vector3.UP, 0.22, 0.06, 0.02)
	pk.ridge(k, Vector3(0.12, 2.92, 0.0), Vector3(0.4, 2.78, 0.0), Vector3.UP, 0.22, 0.06, 0.02)
	pk.cone(k, Vector3(0, 3.62, 0.12), 0.12, 0.06)
	pk.ridge(k, Vector3(-0.98, 1.66, 0.0), Vector3(-0.62, 1.66, 0.26), Vector3.UP, 0.12, 0.05, 0.02)
	k.pop()

## A lamp standard with a glass lantern (the Pirámide's corners, the Subte's stairs): `foot` on the ground or a curb.
func lantern_post(k: Kit, kd: Kit, foot: Vector3, height: float) -> void:
	var iron := Color(0.11, 0.12, 0.12)
	k.push_tint(iron)
	k.lathe("metal", foot, PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.2, 0.18), Vector2(0.14, 0.28), Vector2(0.13, 0.5), Vector2(0.08, 0.66), Vector2(0.065, height - 0.6),
		Vector2(0.1, height - 0.52), Vector2(0.1, height - 0.44), Vector2(0.05, height - 0.4)]), 8, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var g := foot + Vector3(0, height - 0.4, 0)
	pk.glow_lathe(kd, g, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.17, 0.08), Vector2(0.2, 0.25), Vector2(0.15, 0.42), Vector2(0.0, 0.47)]), 8)
	k.push_tint(iron)
	k.lathe("metal", g + Vector3(0, 0.45, 0), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.03, 0.12), Vector2(0.0, 0.2)]), 6, Color.WHITE, Color.WHITE)
	k.pop_tint()
	var world: Vector3 = pk.xf * (g + Vector3(0, 0.22, 0))
	pk.halo(world, pk.LAMP, 1.0)
	pk.pool(Vector3(world.x, 0.0, world.z), 4.0, Color(1.0, 0.58, 0.28) * 0.3)

# ---------------------------------------------------------------------------------------------------------------
# The Belgrano monument
# ---------------------------------------------------------------------------------------------------------------
## The equestrian monument to General Belgrano in front of the Casa Rosada (1873): a bronze rider on a horse at a walk,
## one foreleg raised, holding up the flag he created; a granite pedestal with its cornice and bronze plaques. Simple,
## respectful massing: no likeness, no inscription. `face`: where horse and rider look (away from the Casa Rosada,
## over the square). The bronze flag is a cast one, not cloth.
func belgrano(pos: Vector3, face: Vector3) -> Node3D:
	var pxf: Transform3D = pk.placed(pos, face)
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var granite: Color = pk.hexc("c4b8ae")
	var bronze := Color(1.0, 0.96, 0.9)
	# the pedestal: a step, the die, a cornice, the plinth under the hooves
	k.push_tint(granite * 0.9)
	k.box("ashlar", Vector3(0, 0.25, 0), Vector3(4.2, 0.5, 7.4), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	pk.box_top(k, Vector3(0, 0.5, 0), Vector2(4.2, 7.4), 0.12)
	k.push_tint(granite)
	k.box("ashlar", Vector3(0, 0.5 + 1.3, 0), Vector3(3.2, 2.6, 6.4), Color(0.72, 0.72, 0.72), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	pk.moulding(k, "ashlar", PackedVector2Array([Vector2(-1.6, 3.2), Vector2(1.6, 3.2), Vector2(1.6, -3.2), Vector2(-1.6, -3.2)]), 3.1, pk.prof_cornice(0.35, 0.5), granite, true)
	k.push_tint(granite)
	k.box("ashlar", Vector3(0, 3.72, 0), Vector3(2.9, 0.24, 6.0), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	pk.box_top(k, Vector3(0, 3.84, 0), Vector2(2.9, 6.0), 0.14)
	for side: float in [-1.0, 1.0]:
		kd.quad_rect(pk.SOLID, Vector3(side * 1.605, 1.2, -1.4 * side), Vector3(side * 1.605, 1.2, 1.4 * side), Vector3(side * 1.605, 2.4, 1.4 * side), Vector3(side * 1.605, 2.4, -1.4 * side), pk.uv("plaque"), Color(0.75, 0.6, 0.35), Color(0.75, 0.6, 0.35))
	# the horse and the rider, nearly twice as big as life
	k.push(Transform3D(Basis.from_scale(Vector3(1.9, 1.9, 1.9)), Vector3(0, 3.84, -0.2)))
	k.push_tint(bronze)
	_horse(k)
	_rider(k)
	k.pop_tint()
	k.pop()
	pk.flood(k, 0.7, 9.0, -9.0, 9.0)
	var node: Node3D = pk.piece("Belgrano", pxf, k, kd)
	pk.end()
	return node

## A lathe along a segment (a limb, a neck): radii r0 at a, r1 at b.
func _limb(k: Kit, a: Vector3, b: Vector3, r0: float, r1: float, segs: int = 7) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001: return
	var y := d / length
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	k.push(Transform3D(Basis(x, y, z), a))
	k.lathe("bronze", Vector3.ZERO, PackedVector2Array([Vector2(r0 * 0.9, -r0 * 0.3), Vector2(r0, 0.0), Vector2(lerpf(r0, r1, 0.5) * 1.04, length * 0.5), Vector2(r1, length), Vector2(r1 * 0.8, length + r1 * 0.4)]), segs, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop()

## An ellipsoid of bronze centred at `c`. (Its points are laid out directly rather than a sphere pushed through a
## non-uniform scale: the kit carries normals through its transform as they are, and a squashed sphere's would lie.)
func _ellipsoid(k: Kit, c: Vector3, radii: Vector3, segs: int = 14, rows: int = 9) -> void:
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i: int in range(rows):
		var a := PI * float(i) / float(rows - 1)
		var y := -cos(a)
		var r := sin(a)
		for j: int in range(segs + 1):
			var b := TAU * float(j) / float(segs)
			pts.append(c + Vector3(cos(b) * r * radii.x, y * radii.y, -sin(b) * r * radii.z))
			uvs.append(Vector2(float(j) / float(segs), 1.0 - float(i) / float(rows - 1)) * 0.6)
			cols.append(Color(0.78, 0.78, 0.78).lerp(Color.WHITE, float(i) / float(rows - 1)))
	k.patch("bronze", rows, segs + 1, pts, uvs, cols, true)

## The horse (life size, standing on y = 0, looking toward +z): barrel, chest and quarters, neck and head, legs with one
## foreleg raised, tail, the snow along its back.
func _horse(k: Kit) -> void:
	# the body as three overlapping ellipsoids (barrel, chest, quarters): round everywhere, never a box
	_ellipsoid(k, Vector3(0, 1.24, 0.0), Vector3(0.34, 0.4, 0.92))
	_ellipsoid(k, Vector3(0, 1.22, 0.6), Vector3(0.33, 0.42, 0.42))
	_ellipsoid(k, Vector3(0, 1.3, -0.6), Vector3(0.36, 0.42, 0.46))
	# the neck, deep and flattened sideways, rising from the chest; the head bowed a little toward the chest
	_limb(k, Vector3(0, 1.42, 0.8), Vector3(0, 2.02, 1.1), 0.24, 0.15, 10)
	_ellipsoid(k, Vector3(0, 1.62, 0.86), Vector3(0.2, 0.3, 0.26), 12, 7)
	_limb(k, Vector3(0, 2.06, 1.08), Vector3(0, 1.66, 1.5), 0.15, 0.09, 8)
	_ellipsoid(k, Vector3(0, 2.0, 1.12), Vector3(0.13, 0.15, 0.17))
	for side: float in [-1.0, 1.0]:
		_limb(k, Vector3(side * 0.06, 2.06, 0.98), Vector3(side * 0.08, 2.2, 0.94), 0.035, 0.012, 4)
	k.beam("bronze", Vector3(0, 1.72, 0.7), Vector3(0, 2.18, 1.02), 0.05, 0.1, Color(0.75, 0.75, 0.75), Color.WHITE)
	# the legs: the right foreleg raised and bent, the others planted
	for leg: Array in [[0.17, 0.62, false], [-0.17, 0.62, true], [0.18, -0.62, false], [-0.18, -0.62, false]]:
		var x: float = leg[0]
		var z: float = leg[1]
		var raised: bool = leg[2]
		var top := Vector3(x, 1.0, z)
		if raised:
			var knee := Vector3(x, 0.72, z + 0.28)
			var hoof := Vector3(x, 0.48, z + 0.12)
			_limb(k, top, knee, 0.14, 0.08, 8)
			_limb(k, knee, hoof, 0.07, 0.06, 8)
		else:
			var knee := Vector3(x, 0.5, z + (0.02 if z > 0.0 else -0.06))
			_limb(k, top, knee, 0.14, 0.075, 8)
			_limb(k, knee, Vector3(x, 0.04, z + (0.04 if z > 0.0 else -0.02)), 0.065, 0.06, 8)
			k.lathe("bronze", Vector3(x, 0.0, z + 0.04), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.065, 0.06), Vector2(0.05, 0.1)]), 6, Color.WHITE, Color.WHITE)
	# the tail
	k.tube("bronze", PackedVector3Array([Vector3(0, 1.56, -0.98), Vector3(0, 1.3, -1.13), Vector3(0, 0.9, -1.12), Vector3(0.02, 0.55, -1.04)]), 0.07, 6, Color.WHITE)
	pk.ridge(k, Vector3(0, 1.69, -0.78), Vector3(0, 1.63, -0.3), Vector3.UP, 0.3, 0.06, 0.03)

## The rider: legs along the horse's flanks, the coat and its cape, shoulders, a head under a bicorne hat worn
## crosswise, the right arm raising the staff of the bronze flag, the left on the reins.
func _rider(k: Kit) -> void:
	for side: float in [-1.0, 1.0]:
		_limb(k, Vector3(side * 0.16, 1.66, 0.0), Vector3(side * 0.36, 1.4, 0.24), 0.1, 0.075, 6)
		_limb(k, Vector3(side * 0.36, 1.4, 0.24), Vector3(side * 0.36, 1.0, 0.14), 0.07, 0.06, 6)
		k.box("bronze", Vector3(side * 0.36, 0.98, 0.2), Vector3(0.1, 0.08, 0.26), Color.WHITE, Color.WHITE)
	k.lathe("bronze", Vector3(0, 1.6, 0.0), PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.22, 0.2), Vector2(0.19, 0.45), Vector2(0.22, 0.62), Vector2(0.2, 0.7), Vector2(0.08, 0.76), Vector2(0.06, 0.82)]), 10, Color(0.8, 0.8, 0.8), Color.WHITE)
	# the cape falling behind over the horse's back
	k.beam("bronze", Vector3(0, 2.28, -0.1), Vector3(0, 1.62, -0.42), 0.5, 0.06, Color(0.75, 0.75, 0.75), Color.WHITE)
	k.lathe("bronze", Vector3(0, 2.4, 0.02), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.03), Vector2(0.11, 0.12), Vector2(0.09, 0.22), Vector2(0.0, 0.25)]), 8, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.push(Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 0.45)), Vector3(0, 2.62, 0.02)))
	k.lathe("bronze", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.24, 0.18), Vector2(0.0, 0.3)]), 10, Color(0.85, 0.85, 0.85), Color.WHITE)
	k.pop()
	# the left hand on the reins, the right raising the flag
	_limb(k, Vector3(-0.2, 2.2, 0.02), Vector3(-0.22, 1.95, 0.24), 0.06, 0.05, 6)
	_limb(k, Vector3(-0.22, 1.95, 0.24), Vector3(-0.06, 1.85, 0.46), 0.05, 0.04, 6)
	k.beam("bronze", Vector3(-0.06, 1.85, 0.46), Vector3(0, 1.85, 1.0), 0.02, 0.02, Color.WHITE, Color.WHITE)
	_limb(k, Vector3(0.2, 2.2, 0.02), Vector3(0.34, 2.32, 0.24), 0.06, 0.05, 6)
	_limb(k, Vector3(0.34, 2.32, 0.24), Vector3(0.38, 2.62, 0.3), 0.05, 0.04, 6)
	var staff_a := Vector3(0.38, 1.7, 0.26)
	var staff_b := Vector3(0.44, 3.9, 0.36)
	k.beam("bronze", staff_a, staff_b, 0.035, 0.035, Color.WHITE, Color.WHITE)
	# the cast flag: a few waves along it, flying back over his shoulder
	var rows := 5
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(rows):
		var t := float(i) / float(rows - 1)
		var p := staff_b.lerp(staff_a, 0.0) + Vector3(0.0, -0.02, -t * 1.0) + Vector3(sin(t * PI * 1.6) * 0.12, -t * t * 0.15, 0)
		for j: int in range(2):
			pts.append(p + Vector3(0, -0.62 * float(j), 0))
			uvs.append(Vector2(t, float(j)) * 0.4)
	k.patch("bronze", rows, 2, pts, uvs, PackedColorArray([Color.WHITE]))
	k.patch("bronze", rows, 2, pts, uvs, PackedColorArray([Color(0.8, 0.8, 0.8)]), false, true)
	pk.ridge(k, staff_b + Vector3(0, -0.01, 0), staff_b + Vector3(0.1, -0.06, -0.9), Vector3.UP, 0.05, 0.04, 0.01)
	pk.ridge(k, Vector3(-0.22, 2.36, 0.0), Vector3(0.22, 2.36, 0.0), Vector3.UP, 0.18, 0.05, 0.02)
	pk.cone(k, Vector3(0, 2.78, 0.02), 0.16, 0.06)

# ---------------------------------------------------------------------------------------------------------------
# Lawns, the Subte, the kiosk, a flagpole
# ---------------------------------------------------------------------------------------------------------------
## A lawn of the square under the snow: a granite kerb, the lawn raised a hand under its snow, a low fence of iron
## hoops round it (the atlas's cut-out) with posts at the corners, a few clipped evergreen shrubs; `gaps` leave its
## middle open on the two short sides (a path through).
func lawn(rect: Rect2, fence: bool = true, shrubs: int = 0) -> Node3D:
	var pxf := Transform3D(Basis.IDENTITY, Vector3(rect.position.x, 0, rect.position.y))
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var w := rect.size.x
	var d := rect.size.y
	var kerb: Color = pk.hexc("9a968e")
	k.push_tint(kerb)
	for e: Array in [[Vector3(0, 0, 0), Vector3(w, 0, 0)], [Vector3(w, 0, 0), Vector3(w, 0, d)], [Vector3(w, 0, d), Vector3(0, 0, d)], [Vector3(0, 0, d), Vector3(0, 0, 0)]]:
		k.beam("ashlar", (e[0] as Vector3) + Vector3(0, 0.08, 0), (e[1] as Vector3) + Vector3(0, 0.08, 0), 0.24, 0.16, Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	k.push_tint(pk.hexc("3a4a30"))
	k.box("leaves", Vector3(w * 0.5, 0.03, d * 0.5), Vector3(w - 0.2, 0.06, d - 0.2), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.AUTO, 4)
	k.pop_tint()
	pk.pillow(k, pk.rect_poly(0.1, 0.1, w - 0.1, d - 0.1), 0.06, 0.06, 1.0)
	if fence:
		var iron := Color(0.13, 0.15, 0.13)
		var inset := 0.35
		var corners := [Vector3(inset, 0.06, inset), Vector3(w - inset, 0.06, inset), Vector3(w - inset, 0.06, d - inset), Vector3(inset, 0.06, d - inset)]
		for i: int in range(4):
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var length := a.distance_to(b)
			var s2 := 0.0
			while s2 < length - 0.01:
				var t := minf(2.0, length - s2)
				var p0 := a.lerp(b, s2 / length)
				var p1 := a.lerp(b, (s2 + t) / length)
				kd.quad_rect(pk.CUT, p0, p1, p1 + Vector3(0, 0.42, 0), p0 + Vector3(0, 0.42, 0), pk.uv_part("fence_hoop", 0.0, t / 2.0), iron, iron * 1.4)
				s2 += t
			k.push_tint(iron)
			k.lathe("metal", a, PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.03, 0.5), Vector2(0.05, 0.52), Vector2(0.0, 0.6)]), 5, Color.WHITE, Color.WHITE)
			k.pop_tint()
			pk.cone(k, a + Vector3(0, 0.56, 0), 0.06, 0.05)
	for i: int in range(shrubs):
		var c := Vector3(rng.randf_range(1.5, w - 1.5), 0.06, rng.randf_range(1.5, d - 1.5)) if i >= 2 else (Vector3(1.4, 0.06, 1.4) if i == 0 else Vector3(w - 1.4, 0.06, d - 1.4))
		k.push_tint(Color(0.95, 1.1, 0.85))
		k.lathe("leaves", c, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.55, 0.05), Vector2(0.62, 0.4), Vector2(0.45, 0.8), Vector2(0.0, 0.9)]), 8, Color(0.7, 0.7, 0.7), Color.WHITE, Vector2(rng.randf(), rng.randf()))
		k.pop_tint()
	# (flat and low: it casts no shadow worth its cost, and a wide flat caster speckles itself)
	var node: Node3D = pk.piece("Lawn", pxf, k, kd, null, false)
	pk.end()
	return node

## The Subte's stairs down (Línea A, under Avenida de Mayo since 1913): the stairwell open in the pavement (the level's
## ground must leave `rect` open), its white-tiled walls, the granite steps going down from the entry side (`face`
## looks out of it) with snow on the top ones, the lit passage at the foot; an iron railing on a kerb round the other
## three sides, and over the entry two lamp standards carrying the enamel sign SUBTERRÁNEO · PLAZA DE MAYO (the kit's
## own lettering).
func subte_entrance(rect: Rect2, face: Vector3) -> Node3D:
	var fr: Array = pk.frame(rect, face)
	var pxf: Transform3D = fr[0]
	var W: float = fr[1]
	var D: float = fr[2]
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var tile := Color(0.92, 0.9, 0.86)
	var depth := 4.2
	var steps := int(depth / 0.17)
	var run := minf(D - 1.6, float(steps) * 0.29)
	var tread := run / float(steps)
	for i: int in range(steps):
		var y := -float(i + 1) * depth / float(steps)
		var z := -0.15 - float(i) * tread
		k.push_tint(Color(0.62, 0.6, 0.58))
		k.box("ashlar", Vector3(W * 0.5, y + depth / float(steps) * 0.5, z - tread * 0.5), Vector3(W - 0.1, depth / float(steps), tread), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.AUTO, 61)
		k.pop_tint()
		if i < 4: pk.box_top(k, Vector3(W * 0.5, y + depth / float(steps), z - tread * 0.5), Vector2(W - 0.3, tread - 0.02), 0.06 * float(4 - i) / 4.0)
	# the landing at the foot and the walls
	k.push_tint(Color(0.55, 0.53, 0.5))
	k.box("ashlar", Vector3(W * 0.5, -depth - 0.05, -0.15 - run - (D - run) * 0.5), Vector3(W, 0.1, D - run), Color.WHITE, Color.WHITE)
	k.pop_tint()
	# (inside faces, toward the stairwell)
	k.push_tint(tile)
	k.quad4("render", Vector3(0, -depth - 0.1, 0), Vector3(0, -depth - 0.1, -D), Vector3(0, 0, -D), Vector3(0, 0, 0), Vector2(0, 1), Vector2(D * Kit.UV_M, 1), Vector2(D * Kit.UV_M, 1.0 - depth * Kit.UV_M), Vector2(0, 1.0 - depth * Kit.UV_M), Color(0.3, 0.3, 0.32), Color(0.3, 0.3, 0.32), Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8))
	k.quad4("render", Vector3(W, -depth - 0.1, -D), Vector3(W, -depth - 0.1, 0), Vector3(W, 0, 0), Vector3(W, 0, -D), Vector2(0, 1), Vector2(D * Kit.UV_M, 1), Vector2(D * Kit.UV_M, 1.0 - depth * Kit.UV_M), Vector2(0, 1.0 - depth * Kit.UV_M), Color(0.3, 0.3, 0.32), Color(0.3, 0.3, 0.32), Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8))
	k.quad4("render", Vector3(0, -depth - 0.1, -D), Vector3(W, -depth - 0.1, -D), Vector3(W, 0, -D), Vector3(0, 0, -D), Vector2(0, 1), Vector2(W * Kit.UV_M, 1), Vector2(W * Kit.UV_M, 1.0 - depth * Kit.UV_M), Vector2(0, 1.0 - depth * Kit.UV_M), Color(0.3, 0.3, 0.32), Color(0.3, 0.3, 0.32), Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8))
	k.pop_tint()
	# the lit passage at the foot, on the back wall
	kd.quad_rect(pk.LIT, Vector3(0.2, -depth, -D + 0.02), Vector3(W - 0.2, -depth, -D + 0.02), Vector3(W - 0.2, -depth + 2.6, -D + 0.02), Vector3(0.2, -depth + 2.6, -D + 0.02), pk.uv("tiles_lit"), pk.WARM * 0.9, pk.WARM * 0.9)
	pk.lights.append([pxf * Vector3(W * 0.5, -depth + 2.4, -D + 0.6), pk.LAMP, 0.5, 6.0])
	pk.halo(pxf * Vector3(W * 0.5, -1.0, -D * 0.6), Color(1.0, 0.8, 0.55), 1.6)
	# the kerb and the railing round three sides
	var iron := Color(0.12, 0.13, 0.13)
	var granite: Color = pk.hexc("9a968e")
	var sides := [[Vector3(0, 0, 0), Vector3(0, 0, -D)], [Vector3(0, 0, -D), Vector3(W, 0, -D)], [Vector3(W, 0, -D), Vector3(W, 0, 0)]]
	for e: Array in sides:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		k.push_tint(granite)
		k.beam("ashlar", a + Vector3(0, 0.15, 0), b + Vector3(0, 0.15, 0), 0.32, 0.3, Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		pk.ridge(k, a + Vector3(0, 0.3, 0), b + Vector3(0, 0.3, 0), Vector3.UP, 0.34, 0.08, 0.03)
		var length := a.distance_to(b)
		var s2 := 0.0
		while s2 < length - 0.01:
			var t := minf(2.6, length - s2)
			var p0 := a.lerp(b, s2 / length) + Vector3(0, 0.3, 0)
			var p1 := a.lerp(b, (s2 + t) / length) + Vector3(0, 0.3, 0)
			kd.quad_rect(pk.CUT, p0, p1, p1 + Vector3(0, 1.0, 0), p0 + Vector3(0, 1.0, 0), pk.uv_part("rail_ornate", 0.0, t / 2.6), iron, iron * 1.3)
			s2 += t
		k.push_tint(iron)
		k.beam("metal", a + Vector3(0, 1.3, 0), b + Vector3(0, 1.3, 0), 0.06, 0.05, Color.WHITE, Color.WHITE)
		k.pop_tint()
		pk.ridge(k, a + Vector3(0, 1.33, 0), b + Vector3(0, 1.33, 0), Vector3.UP, 0.07, 0.04, 0.01)
	# the two lamp standards at the entry and the enamel sign between them
	for x: float in [0.0, W]:
		lantern_post(k, kd, Vector3(x, 0.0, 0.0), 3.4)
	k.push_tint(iron)
	k.box("metal", Vector3(W * 0.5, 2.35, 0.0), Vector3(W + 0.1, 0.08, 0.08), Color.WHITE, Color.WHITE)
	k.box("metal", Vector3(W * 0.5, 2.35 + W * 0.25 + 0.1, 0.0), Vector3(W + 0.1, 0.08, 0.08), Color.WHITE, Color.WHITE)
	k.pop_tint()
	var sr: Rect2 = pk.uv("sign_subte")
	var sy0 := 2.4
	var sy1 := 2.4 + W * 0.25
	kd.quad_rect(pk.SOLID, Vector3(0.05, sy0, 0.03), Vector3(W - 0.05, sy0, 0.03), Vector3(W - 0.05, sy1, 0.03), Vector3(0.05, sy1, 0.03), sr, Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.SOLID, Vector3(W - 0.05, sy0, -0.03), Vector3(0.05, sy0, -0.03), Vector3(0.05, sy1, -0.03), Vector3(W - 0.05, sy1, -0.03), sr, Color.WHITE, Color.WHITE)
	pk.ridge(k, Vector3(0.0, sy1 + 0.16, 0), Vector3(W, sy1 + 0.16, 0), Vector3.UP, 0.1, 0.05, 0.02)
	var node: Node3D = pk.piece("SubteEntrance", pxf, k, kd)
	pk.end()
	return node

## A newspaper kiosk (puesto de diarios): a little booth of boards painted dark green under a roof that overhangs on
## every side, the counter open and lit by its bulb, the papers and magazines pegged on cords round it (nothing
## legible: invented), the fascia DIARIOS · REVISTAS; snow on its roof.
func kiosk(pos: Vector3, face: Vector3) -> Node3D:
	var pxf: Transform3D = pk.placed(pos, face)
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var green: Color = pk.hexc("3a6446")
	var w := 2.4
	var d := 1.7
	var h := 2.3
	k.push_tint(green)
	k.box("planks", Vector3(0, 0.55, 0), Vector3(w, 1.1, d), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.box("planks", Vector3(0, (1.1 + h) * 0.5 + 0.0, -d * 0.5 + 0.08), Vector3(w, h - 1.1, 0.16), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	for x: float in [-w * 0.5 + 0.08, w * 0.5 - 0.08]:
		k.box("planks", Vector3(x, (1.1 + h) * 0.5, 0), Vector3(0.16, h - 1.1, d), Color(0.8, 0.8, 0.8), Color.WHITE, Vector2.ZERO, Kit.UPRIGHT)
	k.pop_tint()
	# the counter's lit inside, its bulb
	kd.quad_rect(pk.LIT, Vector3(-w * 0.5 + 0.18, 1.1, -d * 0.5 + 0.17), Vector3(w * 0.5 - 0.18, 1.1, -d * 0.5 + 0.17), Vector3(w * 0.5 - 0.18, h, -d * 0.5 + 0.17), Vector3(-w * 0.5 + 0.18, h, -d * 0.5 + 0.17), pk.uv("shop_strip_lit"), pk.WARM, pk.WARM)
	k.push_tint(Color(0.5, 0.42, 0.34))
	k.box("planks", Vector3(0, 1.12, d * 0.5 - 0.15), Vector3(w, 0.06, 0.4), Color.WHITE, Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	pk.glow_lathe(kd, Vector3(0, h - 0.3, -0.1), PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.07, 0.0), Vector2(0.06, 0.07)]), 8)
	pk.halo(pxf * Vector3(0, h - 0.3, 0.2), pk.LAMP, 0.9)
	pk.spill_at(Vector3(0, 0, d * 0.5), Vector3(0, 0, 1), w * 0.8, 2.5, 0.6)
	pk.lights.append([pxf * Vector3(0, h - 0.3, 0.3), pk.LAMP, 0.4, 5.0])
	# the roof and its fascia
	k.push_tint(green * 0.8)
	k.box("planks", Vector3(0, h + 0.08, 0), Vector3(w + 0.7, 0.16, d + 0.7), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	pk.box_top(k, Vector3(0, h + 0.16, 0), Vector2(w + 0.7, d + 0.7), 0.16)
	for e: int in range(4):
		var yaw := float(e) * PI * 0.5
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var r := Vector3(n.z, 0, -n.x)
		var half := (w + 0.7) * 0.5 if e % 2 == 0 else (d + 0.7) * 0.5
		var out := (d + 0.7) * 0.5 if e % 2 == 0 else (w + 0.7) * 0.5
		var o := n * (out + 0.005)
		kd.quad_rect(pk.SOLID, o - r * half + Vector3(0, h, 0), o + r * half + Vector3(0, h, 0), o + r * half + Vector3(0, h + 0.16, 0), o - r * half + Vector3(0, h + 0.16, 0), pk.uv_part("kiosk_sign", 0.0, 1.0, 0.2, 0.8) if e == 0 else pk.uv("dark"), Color.WHITE, Color.WHITE)
	k.push_tint(green)
	k.box("planks", Vector3(0, h + 0.55, d * 0.5 + 0.3), Vector3(w * 0.9, 0.5, 0.06), Color.WHITE, Color.WHITE)
	k.pop_tint()
	kd.quad_rect(pk.SOLID, Vector3(-w * 0.43, h + 0.32, d * 0.5 + 0.34), Vector3(w * 0.43, h + 0.32, d * 0.5 + 0.34), Vector3(w * 0.43, h + 0.78, d * 0.5 + 0.34), Vector3(-w * 0.43, h + 0.78, d * 0.5 + 0.34), pk.uv("kiosk_sign"), Color.WHITE, Color.WHITE)
	pk.ridge(k, Vector3(-w * 0.45, h + 0.82, d * 0.5 + 0.3), Vector3(w * 0.45, h + 0.82, d * 0.5 + 0.3), Vector3.UP, 0.08, 0.05, 0.02)
	# papers and magazines pegged on the front's posts and down the sides
	kd.quad_rect(pk.CUT, Vector3(-w * 0.5 - 0.01, 1.2, d * 0.5 + 0.02), Vector3(-w * 0.5 - 0.01, 1.2, -d * 0.5), Vector3(-w * 0.5 - 0.01, 2.2, -d * 0.5), Vector3(-w * 0.5 - 0.01, 2.2, d * 0.5 + 0.02), pk.uv("magazines"), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.CUT, Vector3(w * 0.5 + 0.01, 1.2, -d * 0.5), Vector3(w * 0.5 + 0.01, 1.2, d * 0.5 + 0.02), Vector3(w * 0.5 + 0.01, 2.2, d * 0.5 + 0.02), Vector3(w * 0.5 + 0.01, 2.2, -d * 0.5), pk.uv("papers"), Color.WHITE, Color.WHITE)
	kd.quad_rect(pk.CUT, Vector3(-w * 0.5 + 0.1, 0.15, d * 0.5 + 0.01), Vector3(w * 0.5 - 0.1, 0.15, d * 0.5 + 0.01), Vector3(w * 0.5 - 0.1, 1.05, d * 0.5 + 0.01), Vector3(-w * 0.5 + 0.1, 1.05, d * 0.5 + 0.01), pk.uv("papers"), Color.WHITE, Color.WHITE)
	var node: Node3D = pk.piece("Kiosk", pxf, k, kd)
	pk.end()
	return node

## A flagpole on the ground: a stepped stone base, the white pole, the gilt finial, the flag waving (into `wind`, the
## direction it flies toward).
func flagpole(pos: Vector3, height: float, wind: Vector3) -> Node3D:
	var pxf: Transform3D = pk.placed(pos, Vector3(-wind.z, 0, wind.x))
	pk.begin(pxf)
	var k := Kit.new()
	var kd := Kit.new()
	var stone: Color = pk.hexc("c8c0b0")
	for i: int in range(3):
		var s := 2.4 - float(i) * 0.6
		k.push_tint(stone)
		k.box("ashlar", Vector3(0, float(i) * 0.35 + 0.175, 0), Vector3(s, 0.35, s), Color(0.7, 0.7, 0.7), Color.WHITE)
		k.pop_tint()
		pk.box_top(k, Vector3(0, float(i + 1) * 0.35, 0), Vector2(s, s), 0.08)
	k.push_tint(Color(0.6, 0.48, 0.3))
	k.lathe("bronze", Vector3(0, 1.05, 0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.24, 0.3), Vector2(0.16, 0.5)]), 10, Color.WHITE, Color.WHITE)
	k.pop_tint()
	var node: Node3D = pk.piece("Flagpole", pxf, k, kd)
	var f: MeshInstance3D = pk.flagpole_on(node, Vector3(0, 1.5, 0), height, height * 0.22)
	f.rotation.y = 0.0
	pk.end()
	return node

# ---------------------------------------------------------------------------------------------------------------
# Lamp posts, palms, trees, benches: one mesh each, many instances
# ---------------------------------------------------------------------------------------------------------------
## The square's cast-iron candelabra, the porteño type of the plazas (the five-globe "farola" of the Plaza de Mayo,
## Avenida de Mayo and the parks): a moulded base in steps, a tall fluted shaft, a collar, and a capital from which
## `arms` scrolled arms dip and sweep up, each to a stem with a cast cup, an opal globe and a small cast cap, a hoop
## joining the arms; the fifth globe on the column's own stem above them; tungsten-warm. About 5.7 m to the top globe.
## (The notes found no source for the 1950s models: this is the familiar type, from general knowledge.)
func lamp_post_kit(arms: int) -> Array:
	var k := Kit.new()
	var kd := Kit.new()
	var iron := Color(0.1, 0.11, 0.11)
	k.push_tint(iron)
	# the column: the base in steps, the shaft tapering, the collar, the capital, the stem of the top globe
	k.lathe("metal", Vector3.ZERO, PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.16), Vector2(0.42, 0.22), Vector2(0.4, 0.5), Vector2(0.33, 0.6),
		Vector2(0.3, 0.88), Vector2(0.23, 0.98), Vector2(0.19, 1.12), Vector2(0.15, 1.3), Vector2(0.125, 3.95), Vector2(0.17, 4.03), Vector2(0.17, 4.14),
		Vector2(0.13, 4.22), Vector2(0.13, 4.36), Vector2(0.24, 4.46), Vector2(0.25, 4.56), Vector2(0.09, 4.64), Vector2(0.07, 5.0), Vector2(0.12, 5.06),
		Vector2(0.12, 5.12), Vector2(0.06, 5.18)]), 16)
	# the flutes: thin ribs up the shaft
	for i: int in range(10):
		var a := TAU * float(i) / 10.0
		k.beam("metal", Vector3(cos(a) * 0.145, 1.35, sin(a) * 0.145), Vector3(cos(a) * 0.125, 3.9, sin(a) * 0.125), 0.03, 0.03, Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var globes: Array[Vector3] = []
	for i: int in range(arms):
		var a := TAU * float(i) / float(arms) + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		k.push_tint(iron)
		# the arm: out of the capital, a dip, then the sweep up to its stem
		k.tube("metal", PackedVector3Array([Vector3(0, 4.5, 0) + d * 0.2, Vector3(0, 4.44, 0) + d * 0.42, Vector3(0, 4.46, 0) + d * 0.62,
			Vector3(0, 4.58, 0) + d * 0.78, Vector3(0, 4.76, 0) + d * 0.86, Vector3(0, 4.96, 0) + d * 0.87]), 0.045, 6, Color.WHITE)
		# the scroll: a curl from the collar up under the arm's dip
		k.tube("metal", PackedVector3Array([Vector3(0, 4.08, 0) + d * 0.15, Vector3(0, 4.2, 0) + d * 0.4, Vector3(0, 4.38, 0) + d * 0.52,
			Vector3(0, 4.44, 0) + d * 0.42]), 0.028, 4, Color.WHITE)
		# the cup the globe sits in
		var cup := Vector3(0, 4.96, 0) + d * 0.87
		k.lathe("metal", cup, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.11, 0.06), Vector2(0.12, 0.12), Vector2(0.09, 0.14)]), 8, Color.WHITE, Color.WHITE)
		k.pop_tint()
		globes.append(cup + Vector3(0, 0.14, 0))
		pk.ridge(k, Vector3(0, 4.5, 0) + d * 0.45, Vector3(0, 4.62, 0) + d * 0.76, Vector3.UP, 0.08, 0.04, 0.01)
	# the hoop that joins the arms
	if arms >= 3:
		var hoop := PackedVector3Array()
		for j: int in range(25):
			var t := TAU * float(j) / 24.0
			hoop.append(Vector3(cos(t) * 0.62, 4.47, sin(t) * 0.62))
		k.push_tint(iron)
		k.tube("metal", hoop, 0.022, 4, Color.WHITE)
		k.pop_tint()
	# the fifth globe, on the column's own stem
	var top := Vector3(0, 5.18, 0)
	k.push_tint(iron)
	k.lathe("metal", top, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.13, 0.06), Vector2(0.14, 0.13), Vector2(0.1, 0.15)]), 8, Color.WHITE, Color.WHITE)
	k.pop_tint()
	globes.append(top + Vector3(0, 0.15, 0))
	# the opal globes (their bottoms at `globes`), each with its cast cap
	for g: Vector3 in globes:
		var r := 0.23 if g.y > 5.3 else 0.2
		var prof := PackedVector2Array()
		for j: int in range(7):
			var t := -PI * 0.5 + PI * float(j) / 6.0
			prof.append(Vector2(maxf(cos(t), 0.0) * r, r + sin(t) * r))
		pk.glow_lathe(kd, g, prof, 12)
		k.push_tint(iron)
		k.lathe("metal", g + Vector3(0, 2.0 * r - 0.02, 0), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.05, 0.04), Vector2(0.0, 0.07)]), 8, Color.WHITE, Color.WHITE)
		k.pop_tint()
	# snow on the capital
	pk.cone(k, Vector3(0, 4.56, 0), 0.25, 0.06)
	return [k, kd, globes]

## A Canary Island date palm (Phoenix canariensis) as in the square (eight planted 1900-04 by Thays, about 55 years
## old in 1958, so shorter than today's 22-26 m): a thick straight trunk patterned with the diamonds of the old leaf
## bases, swelling a little into the crown's boot of them; a dense round crown of long pinnate fronds, the young ones
## standing up in its heart, the rest arching out and drooping at their tips, their leaflets held in a V along the
## rachis (the geometry folds the frond's two halves up), dull olive and blue-green; under them a skirt of a few dry
## brown fronds hanging against the trunk. The crown about 7.5 m across, as a palm that age (their fronds up to 6 m on
## today's old palms). Snow on the fronds' upper faces (plaza_detail.gdshader, LEAF), a cap of it in the crown's heart.
## The crown fades over whoever stands under it (sync_palms), and sways in the wind (the palms' own materials).
func palm_kit(seed_value: int, height: float = 10.4) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var k := Kit.new()
	var kd := Kit.new()
	var trunk := Color(0.98, 0.88, 0.74)
	var prof := PackedVector2Array()
	for i: int in range(12):
		var t := float(i) / 11.0
		prof.append(Vector2(0.52 - 0.07 * t + 0.012 * sin(t * 23.0) + 0.1 * smoothstep(0.78, 1.0, t), t * height))
	k.lathe("bark", Vector3.ZERO, prof, 14, trunk * 0.72, trunk, Vector2.ZERO, PackedFloat32Array(), 1.0)
	# the boot: the crown's leaf bases packed tight, dark, a little wider than the trunk, closing over the heart
	var boot := PackedVector2Array([Vector2(0.55, height - 0.05), Vector2(0.66, height + 0.3), Vector2(0.62, height + 0.62), Vector2(0.4, height + 0.9), Vector2(0.0, height + 1.0)])
	k.lathe("bark", Vector3.ZERO, boot, 14, Color(0.3, 0.27, 0.2), Color(0.22, 0.22, 0.16), Vector2.ZERO, PackedFloat32Array(), 1.0)
	pk.cone(k, Vector3(0, height + 0.92, 0), 0.42, 0.22)
	var live: Rect2 = pk.uv("frond0")
	var live2: Rect2 = pk.uv("frond1")
	var dry: Rect2 = pk.uv("frond_dry")
	# tiers: [count, elevation at the base (rad), how much it bends down along its length, length, half width, rise of
	# its base over the trunk's top, tint, snow it holds, cell]
	var tiers := [
		[8, 1.3, 0.45, 2.9, 0.4, 0.95, Color(0.92, 1.0, 0.95), 0.9, live2],
		[15, 0.88, 0.95, 3.7, 0.52, 0.8, Color(1.0, 1.0, 1.0), 1.0, live],
		[19, 0.42, 1.25, 4.0, 0.56, 0.6, Color(0.95, 0.98, 0.94), 1.0, live2],
		[14, 0.02, 1.3, 3.7, 0.52, 0.4, Color(1.0, 0.97, 0.86), 1.0, live],
		[10, -1.2, 0.25, 3.3, 0.36, 0.1, Color(0.8, 0.76, 0.7), 0.35, dry],
	]
	var golden := PI * (3.0 - sqrt(5.0))
	var count := 0
	for tier: Array in tiers:
		for i: int in range(int(tier[0])):
			var az := float(count) * golden + r.randf_range(-0.1, 0.1)
			count += 1
			var elev: float = float(tier[1]) + r.randf_range(-0.12, 0.12)
			var curl: float = float(tier[2]) * r.randf_range(0.85, 1.15)
			var length: float = float(tier[3]) * r.randf_range(0.9, 1.08)
			var g := r.randf_range(0.86, 1.08)
			var col: Color = tier[6]
			_frond(kd, Vector3(0, height + float(tier[5]), 0), az, elev, curl, length, float(tier[4]), Color(col.r * g, col.g * g, col.b * g, float(tier[7])), tier[8])
	return [k, kd]

## One frond from the crown: from `base` out along `az`, rising at `elev` and bending down along its length by
## `curl`, its leaflets `half` wide each side and raised into a V about the rachis.
func _frond(kd: Kit, base: Vector3, az: float, elev: float, curl: float, length: float, half: float, col: Color, cell: Rect2) -> void:
	var dir := Vector3(cos(az), 0.0, sin(az))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var rows := 9
	var step := length / float(rows - 1)
	var p := base + dir * 0.3
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j: int in range(rows):
		var t := float(j) / float(rows - 1)
		var a := elev - curl * pow(t, 1.5)
		if j > 0:
			var am := elev - curl * pow(t - 0.5 / float(rows - 1), 1.5)
			p += (dir * cos(am) + Vector3.UP * sin(am)) * step
		# the leaflets: spines near the base, longest a third of the way out, short at the tip
		var wd := half * (0.35 if t < 0.12 else pow(sin(PI * (0.08 + 0.86 * t)), 0.6))
		var up := -dir * sin(a) + Vector3.UP * cos(a)
		for c: int in range(3):
			var cc := float(c) - 1.0
			pts.append(p + side * wd * cc + up * absf(cc) * wd * 0.55)
			uvs.append(Vector2(cell.position.x + cell.size.x * t, cell.position.y + cell.size.y * (0.5 + cc * 0.5)))
	kd.patch(pk.LEAF, rows, 3, pts, uvs, PackedColorArray([col]))

## A bare London plane in winter (the notes: planes and tipas would be bare or sparse): a mottled bole, limbs forking
## twice, crowns of twig cards white with the snow along their tops (the atlas's twigs, La Boca's).
func tree_kit(seed_value: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var k := Kit.new()
	var kd := Kit.new()
	var bark := Color(0.58, 0.55, 0.48)
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.34, -0.2), Vector2(0.3, 0.5), Vector2(0.25, 1.8), Vector2(0.22, 3.2), Vector2(0.18, 3.6)]), 8, bark * 0.7, bark, Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	var tips: Array = []
	for i: int in range(5):
		var a := TAU * float(i) / 5.0 + r.randf_range(-0.4, 0.4)
		var start := Vector3(0, 3.2 + r.randf_range(0.0, 0.4), 0)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := start + dir * r.randf_range(1.6, 2.4) + Vector3(0, r.randf_range(2.4, 3.2), 0)
		k.tube("planks", PackedVector3Array([start, start.lerp(mid, 0.5) + Vector3(0, 0.2, 0), mid]), 0.15, 5, bark)
		pk.ridge(k, start.lerp(mid, 0.2) + Vector3(0, 0.14, 0), mid + Vector3(0, 0.12, 0), Vector3.UP, 0.18, 0.08, 0.02, 0.3)
		for j: int in range(2):
			var a2 := a + (float(j) - 0.5) * r.randf_range(0.7, 1.1)
			var tip := mid + Vector3(cos(a2), 0.0, sin(a2)) * r.randf_range(1.4, 2.2) + Vector3(0, r.randf_range(1.4, 2.2), 0)
			k.tube("planks", PackedVector3Array([mid, mid.lerp(tip, 0.5) + Vector3(0, 0.15, 0), tip]), 0.08, 4, bark)
			tips.append([tip, a2])
	var tw: Rect2 = pk.uv("twigs")
	for t: Array in tips:
		var tip: Vector3 = t[0]
		var a: float = t[1]
		for c: int in range(2):
			var yaw := a + PI * 0.5 + (float(c) - 0.5) * 0.9
			var right := Vector3(cos(yaw), 0, sin(yaw))
			var out := Vector3(cos(a), 0, sin(a))
			var s := r.randf_range(2.8, 3.6)
			var base := tip - Vector3(0, s * 0.35, 0) - out * 0.2
			var up := (Vector3.UP + out * 0.35).normalized()
			kd.quad_rect(pk.CUT, base - right * s * 0.5, base + right * s * 0.5, base + right * s * 0.5 + up * s, base - right * s * 0.5 + up * s, tw, Color.WHITE, Color.WHITE)
	for c: int in range(5):
		var yaw := r.randf() * TAU
		var right := Vector3(cos(yaw), 0, sin(yaw))
		var fwd := Vector3(-right.z, 0, right.x)
		var s := 4.8
		var base := Vector3(0, 7.2, 0) - fwd * s * 0.45
		var up := (fwd * 0.85 + Vector3.UP * 0.5).normalized()
		kd.quad_rect(pk.CUT, base - right * s * 0.5, base + right * s * 0.5, base + right * s * 0.5 + up * s, base - right * s * 0.5 + up * s, tw, Color.WHITE, Color.WHITE)
	return [k, kd]

## A plaza bench: wooden slats painted green on two cast-iron end frames, snow on the seat and along the back rail.
func bench_kit() -> Array:
	var k := Kit.new()
	var kd := Kit.new()
	var L := 1.9
	var green := Color(0.22, 0.32, 0.24)
	k.push_tint(green)
	for i: int in range(4):
		k.box("planks", Vector3(0, 0.44, -0.2 + float(i) * 0.13), Vector3(L, 0.035, 0.1), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	for i: int in range(3):
		k.push(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.62 + float(i) * 0.14, -0.27)))
		k.box("planks", Vector3.ZERO, Vector3(L, 0.1, 0.035), Color(0.7, 0.7, 0.7), Color.WHITE, Vector2.ZERO, Kit.BEAM)
		k.pop()
	k.pop_tint()
	var r: Rect2 = pk.uv("bench_iron")
	for x: float in [-L * 0.5 + 0.12, L * 0.5 - 0.12]:
		kd.quad_rect(pk.CUT, Vector3(x, 0.0, -0.36), Vector3(x, 0.0, 0.3), Vector3(x, 0.92, 0.3), Vector3(x, 0.92, -0.36), Rect2(r.end.x, r.position.y, -r.size.x, r.size.y), pk.IRON * 1.6, pk.IRON * 1.6)
	pk.box_top(k, Vector3(0, 0.46, -0.0), Vector2(L - 0.1, 0.48), 0.07)
	pk.ridge(k, Vector3(-L * 0.5, 0.92, -0.33), Vector3(L * 0.5, 0.92, -0.33), Vector3.UP, 0.08, 0.05, 0.01)
	return [k, kd]

func _mesh(k: Kit) -> ArrayMesh:
	var holder := Node3D.new()
	var m: MeshInstance3D = k.commit(holder, pk.materials, "Tmp", true)
	var mesh: ArrayMesh = m.mesh if m != null else null
	holder.free()
	return mesh

## One mesh of a body kit and a detail kit together (two surfaces).
func _joined(kits: Array) -> ArrayMesh:
	var k: Kit = kits[0]
	var kd: Kit = kits[1]
	for key: String in kd.surfs: k.surfs[key] = kd.surfs[key]
	return _mesh(k)

func _multi(mesh: ArrayMesh, items: Array, label: String, yaw_random: bool = true, custom: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	# (with custom data, white instance colours too: the GL Compatibility renderer multiplies the vertex colours by the
	# instance colour, black when there is none)
	mm.use_colors = custom
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i: int in range(items.size()):
		var it: Array = items[i]
		var s: float = it[1] if it.size() > 1 and it[1] is float else 1.0
		var yaw: float = rng.randf() * TAU if yaw_random else (float(it[2]) if it.size() > 2 else 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s)), it[0]))
		if custom:
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, Color(1, 0, 0, 0))
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pk.root.add_child(node)
	var tris := 0
	for si: int in range(mesh.get_surface_count()):
		tris += (mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	pk._stat(label, tris * items.size(), mesh.get_surface_count(), 1, items.size())
	return node

## The snowmen and the trodden snow: one mesh for every snowman (the snow layer of the walls), one for the prints.
func commit_play(snowmen: Array, trails: Array) -> void:
	if snowmen.is_empty() and trails.is_empty(): return
	var k := Kit.new()
	var marks := Kit.new()
	for sm: Array in snowmen:
		var at: Vector3 = sm[0]
		_snowman(k, at, float(sm[1]))
		_trampled(marks, Vector2(at.x, at.z), rng.randf_range(1.2, 1.7), at.y)
	for t: Array in trails: _trail(marks, t[0], 0.45, float(t[1]))
	var tris := k.triangle_count()
	var m := k.commit(pk.root, pk.materials, "Snowmen", true)
	if m != null: pk._stat("Snowmen", tris, m.mesh.get_surface_count(), 1, snowmen.size())
	var tris2 := marks.triangle_count()
	var m2 := marks.commit(pk.root, pk.materials, "SnowPrints", false)
	if m2 != null: pk._stat("SnowPrints", tris2, 1, 1)

## Three balls of wet snow, a scarf, coal eyes, a carrot, sticks for arms, now and then an old hat (La Boca's).
func _snowman(k: Kit, at: Vector3, scale: float) -> void:
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
	var a := rng.randf() * TAU
	var face := Vector3(sin(a), 0, cos(a))
	for side: float in [-1.0, 1.0]:
		var arm := Vector3(face.z, 0, -face.x) * side
		k.beam("planks", at + Vector3(0, 0.98 * scale, 0) + arm * 0.26 * scale, at + Vector3(0, 1.25 * scale, 0) + arm * 0.72 * scale, 0.025, 0.025, Color(0.25, 0.2, 0.16), Color(0.3, 0.24, 0.2))
		k.box("metal", head + face * 0.19 * scale + arm * 0.07 * scale + Vector3(0, 0.06 * scale, 0), Vector3(0.04, 0.04, 0.04) * scale, Color(0.05, 0.05, 0.05), Color(0.08, 0.08, 0.08))
	k.push_tint(Color(0.9, 0.45, 0.15))
	k.beam("planks", head + face * 0.2 * scale, head + face * 0.36 * scale, 0.04 * scale, 0.04 * scale)
	k.pop_tint()
	if rng.randf() < 0.6:
		k.push_tint(Color(0.18, 0.17, 0.17))
		k.lathe("planks", head + Vector3(0, 0.17 * scale, 0), PackedVector2Array([Vector2(0.2 * scale, 0.0), Vector2(0.2 * scale, 0.02), Vector2(0.12 * scale, 0.03), Vector2(0.12 * scale, 0.16 * scale), Vector2(0.0, 0.17 * scale)]), 7)
		k.pop_tint()

## A patch trodden flat round a snowman: a soft hollow and a scatter of small prints.
func _trampled(k: Kit, c: Vector2, r: float, y: float = 0.0) -> void:
	k.decal(Kit.DECAL["blob"], c.x, c.y, Vector2(r * 2.4, r * 2.2), rng.randf() * TAU, Color(0.36, 0.38, 0.6, 0.4), y + 0.03)
	for i: int in range(26):
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
		k.decal(Kit.DECAL["blob"], p.x, p.y, Vector2(0.13, 0.27), rng.randf() * TAU, Color(0.32, 0.36, 0.58, 0.45), y + 0.031)

## Boot prints along a path, left and right, over a faint trodden band (La Boca's).
func _trail(k: Kit, pts: PackedVector2Array, stride: float = 0.45, y: float = 0.0) -> void:
	for i: int in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var n := int(d.length() / stride)
		if n < 1: continue
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		var mid := (a + b) * 0.5
		k.decal(Kit.DECAL["blob"], mid.x, mid.y, Vector2(0.9, d.length() + 0.5), atan2(dir.x, dir.y), Color(0.34, 0.38, 0.62, 0.42), y + 0.029)
		for j: int in range(n):
			var p := a + d * (float(j) + 0.5) / float(n) + side * (0.09 if j % 2 == 0 else -0.09) + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
			k.decal(Kit.DECAL["blob"], p.x, p.y, Vector2(0.14, 0.28), atan2(dir.x, dir.y), Color(0.3, 0.36, 0.58, 0.55), y + 0.03)

## The kit's finish: every lamp post, palm, tree and bench as multimeshes, the lamps' halos and pools.
func commit_batches(lamps: Array, palms: Array, trees: Array, benches: Array) -> void:
	if not lamps.is_empty():
		var by_arms: Dictionary = {}
		for l: Array in lamps:
			var arms: int = l[1]
			if not by_arms.has(arms): by_arms[arms] = []
			(by_arms[arms] as Array).append(l)
		for arms: int in by_arms:
			var parts := lamp_post_kit(arms)
			var globes: Array = parts[2]
			var items: Array = []
			for l: Array in by_arms[arms]:
				var at: Vector3 = l[0]
				items.append([at, 1.0])
			var node := _multi(_joined(parts), items, "LampPosts%d" % arms, true)
			for i: int in range(items.size()):
				var t: Transform3D = node.multimesh.get_instance_transform(i)
				for g: Vector3 in globes:
					# a halo the size of the globe's own glow: the globe reads as opal glass, not as a ball of light
					pk.halo(t * (g + Vector3(0, 0.2, 0)), pk.LAMP, 0.55 if g.y < 5.3 else 0.7)
				var foot: Vector3 = items[i][0]
				pk.pool(foot, 7.0, Color(1.0, 0.58, 0.28) * 0.45)
				pk.lights.append([foot + Vector3(0, 5.2, 0), pk.LAMP, 1.0, 13.0])
	if not palms.is_empty():
		var kinds: Array[ArrayMesh] = [_joined(palm_kit(41)), _joined(palm_kit(42, 10.9)), _joined(palm_kit(43, 9.9))]
		var heights := [10.4, 10.9, 9.9]
		# the palms' own copies of the kit's two materials: their crowns fade one by one (the instance's custom
		# data), their fronds sway
		var pw: ShaderMaterial = (pk.materials["pwalls"] as ShaderMaterial).duplicate()
		var pd: ShaderMaterial = (pk.materials["pdetail"] as ShaderMaterial).duplicate()
		for m: ShaderMaterial in [pw, pd]:
			m.set_shader_parameter("instance_fade", true)
			m.set_shader_parameter("fade_above", PALM_FADE_ABOVE)
		pd.set_shader_parameter("sway", 0.6)
		pk.materials["palm_walls"] = pw
		pk.materials["palm_detail"] = pd
		var ghost_material := ShaderMaterial.new()
		ghost_material.shader = GhostShader
		ghost_material.set_shader_parameter("atlas", pd.get_shader_parameter("atlas"))
		ghost_material.set_shader_parameter("fade_above", PALM_FADE_ABOVE)
		ghost_material.set_shader_parameter("sway", 0.6)
		pk.materials["palm_ghost"] = ghost_material
		for mesh: ArrayMesh in kinds:
			for si: int in range(mesh.get_surface_count()):
				var m: Material = mesh.surface_get_material(si)
				if m == pk.materials["pwalls"]: mesh.surface_set_material(si, pw)
				elif m == pk.materials["pdetail"]: mesh.surface_set_material(si, pd)
		for v: int in range(kinds.size()):
			var items: Array = []
			for i: int in range(palms.size()):
				if i % kinds.size() == v: items.append(palms[i])
			if items.is_empty(): continue
			var node := _multi(kinds[v], items, "Palms%d" % v, true, true)
			# the see-through copy of the crowns, shown only while one of them is fading
			var ghost_mm := MultiMesh.new()
			ghost_mm.transform_format = MultiMesh.TRANSFORM_3D
			ghost_mm.use_custom_data = true
			ghost_mm.mesh = kinds[v]
			ghost_mm.instance_count = items.size()
			var ghost := MultiMeshInstance3D.new()
			ghost.name = "PalmCrownsFading%d" % v
			ghost.multimesh = ghost_mm
			ghost.material_override = ghost_material
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.visible = false
			pk.root.add_child(ghost)
			for j: int in range(items.size()):
				var s: float = float(items[j][1])
				var at: Vector3 = items[j][0]
				ghost_mm.set_instance_transform(j, Transform3D(Basis.from_scale(Vector3.ZERO), at))
				ghost_mm.set_instance_custom_data(j, Color(0, 0, 0, 0))
				pk.palm_crowns.append({"node": node, "index": j, "at": at, "radius": PALM_CROWN_RADIUS * s,
					"top": (float(heights[v]) + 0.6) * s, "alpha": 1.0, "want": 1.0, "ghost": ghost,
					"xf": node.multimesh.get_instance_transform(j)})
	if not trees.is_empty():
		var kinds2: Array[ArrayMesh] = [_joined(tree_kit(31)), _joined(tree_kit(32)), _joined(tree_kit(33))]
		for v: int in range(kinds2.size()):
			var items2: Array = []
			for i: int in range(trees.size()):
				if i % kinds2.size() == v: items2.append(trees[i])
			if not items2.is_empty(): _multi(kinds2[v], items2, "PlaneTrees%d" % v)
	if not benches.is_empty():
		var items3: Array = []
		for b: Array in benches: items3.append([b[0], 1.0, b[1]])
		_multi(_joined(bench_kit()), items3, "Benches", false)

# ---------------------------------------------------------------------------------------------------------------
# The palms' crowns over the people
# ---------------------------------------------------------------------------------------------------------------
## How far out a crown reaches from its trunk (m, at scale 1), the height (in the palm's own space) above which a
## crown fades, and how far it fades (comic ink: altogether).
const PALM_CROWN_RADIUS := 3.9
const PALM_FADE_ABOVE := 6.0
const PALM_FADED := 0.25
const GhostShader := preload("res://shaders/plaza_palm_ghost.gdshader")

## Ten times a second (the caller's clock): which crowns must thin out, under the game's own camera: one with
## somebody standing under it (`under`: everybody on the square, world positions), with the cursor on the ground
## beneath it (`cursor`, or null), or hiding from the camera one of `watched` (the squad and the cascarudos). Every
## frame (`decide` false): each crown eased toward what it wants. Under a lens (the trailer's shots) they stay whole.
func sync_palms(dt: float, camera: Camera3D, under: Array, watched: Array, cursor: Variant, ink: bool, decide: bool) -> void:
	if pk.palm_crowns.is_empty(): return
	if decide:
		var ortho := camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		var back := camera.global_transform.basis.z if camera != null else Vector3.UP
		for crown: Dictionary in pk.palm_crowns:
			var at: Vector3 = crown.at
			var c2 := Vector2(at.x, at.z)
			var rad: float = crown.radius
			var hide := false
			if ortho:
				for q: Vector3 in under:
					if Vector2(q.x, q.z).distance_to(c2) < rad:
						hide = true
						break
				if not hide and cursor is Vector3 and Vector2((cursor as Vector3).x, (cursor as Vector3).z).distance_to(c2) < rad: hide = true
				if not hide:
					var centre := at + Vector3(0, float(crown.top) - 0.8, 0)
					for q: Vector3 in watched:
						var w := centre - q
						var along := w.dot(back)
						if along > 0.0 and w.length_squared() - along * along < rad * rad * 0.8:
							hide = true
							break
			crown.want = (0.0 if ink else PALM_FADED) if hide else 1.0
	# a crown fading: the solid one away (its instance's custom data 0: the walls' and the detail's shaders drop what is
	# above PALM_FADE_ABOVE), its see-through copy shown in its place (plaza_palm_ghost.gdshader), as much as `alpha`
	var changed: Dictionary = {}
	for crown: Dictionary in pk.palm_crowns:
		var a: float = crown.alpha
		var want: float = crown.want
		if absf(a - want) < 0.001: continue
		a = move_toward(a, want, dt * 3.5)
		crown.alpha = a
		var solid := a >= 0.999
		((crown.node as MultiMeshInstance3D).multimesh as MultiMesh).set_instance_custom_data(int(crown.index), Color(1.0 if solid else 0.0, 0, 0, 0))
		var gmm: MultiMesh = (crown.ghost as MultiMeshInstance3D).multimesh
		gmm.set_instance_transform(int(crown.index), crown.xf if not solid and a > 0.01 else Transform3D(Basis.from_scale(Vector3.ZERO), crown.at))
		gmm.set_instance_custom_data(int(crown.index), Color(0, a, 0, 0))
		changed[crown.ghost] = true
	for ghost: MultiMeshInstance3D in changed:
		var any := false
		for crown: Dictionary in pk.palm_crowns:
			if crown.ghost == ghost and float(crown.alpha) < 0.999 and float(crown.alpha) > 0.01: any = true
		ghost.visible = any
