extends RefCounted
## The streets and the river of La Boca between the houses: the tram's overhead wires on their bracket poles along the
## quay and their span wires up the tram street; lamps hung over the crossings; the curfew barriers of sawhorses and
## the braziers where the Guardia warm their hands (a fire that flickers), and the one the neighbours stand round to
## watch the snow; iron bollards along the quay's edge; the red pillar box; boats moored in the river (a tug with its
## portholes lit, a lighter, an old freighter at the far bank, a floating crane); cars and a colectivo parked under
## snow in the streets round the map; bare plane trees and palms, snow on every branch.
##
## Nothing here stands where the rules let anyone walk: the poles stand on the quay's edge stone, the barriers and the
## braziers against house fronts, the boats in the river, the cars and the street trees outside the map, the rest in
## the patios or overhead.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Houses = preload("res://scripts/three_d/boca_houses.gd")
const Snow = preload("res://scripts/three_d/boca_snow.gd")
const WIRE := Color(0.14, 0.14, 0.15)
const IRON := Color(0.15, 0.16, 0.17)
const WATER_Y := -2.3

var b: Node3D
var w: Dictionary
var rng := RandomNumberGenerator.new()
var map_size := Vector2(240.0, 150.0)
var river := Vector2(110.0, 134.0)
## The fires: {light, flames: [Node3D], energy, at, phase}.
var fires: Array = []
var _clock: float = 0.0
var flame_material: StandardMaterial3D

func _init(owner: Node3D, data: Dictionary) -> void:
	b = owner
	w = data.get("bocaWorld", {})
	map_size = Vector2(float(data.width), float(data.height)) / 32.0
	var rv: Array = w.get("river", [110.0, 134.0])
	river = Vector2(float(rv[0]), float(rv[1]))
	rng.seed = 19580905

func _pair(key: String, fallback: Vector2) -> Vector2:
	var v: Array = w.get(key, [fallback.x, fallback.y])
	return Vector2(float(v[0]), float(v[1]))

func build() -> void:
	_flame_material()
	_tram_wires()
	_crossing_lamps()
	_barricades()
	_bollards()
	_moored()
	_post_box()
	_parked()
	_wagons()

# ---------------------------------------------------------------------------------------------------------------
# Wires and lamps overhead
# ---------------------------------------------------------------------------------------------------------------
## The trolley wires: along the avenue over both tracks, hung from bracket arms on poles at the quay's edge; up the tram
## street, hung from span wires between the house fronts.
func _tram_wires() -> void:
	var rails: Array = w.get("rails", [101.5, 103.5])
	var quay := _pair("quay", Vector2(105, 110))
	var y := 5.6
	var k := Kit.new()
	var x := -58.0
	var poles: Array[float] = []
	while x < map_size.x + 58.0:
		var skip := (x > 38.0 and x < 52.0) or (x > 130.0 and x < 160.0) or (x > map_size.x - 4.0 and x < map_size.x + 14.0)
		if not skip: poles.append(x)
		x += 22.0
	for px: float in poles:
		var foot := Vector3(px, 0.0, quay.y + 0.12)
		k.lathe("steel", foot, PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.15, 0.5), Vector2(0.11, 0.62), Vector2(0.09, 7.2), Vector2(0.05, 7.35)]), 8, IRON * 0.7, IRON * 1.3)
		var arm_end := Vector3(px, 6.3, float(rails[0]) - 1.0)
		k.beam("steel", foot + Vector3(0, 6.6, 0), arm_end, 0.07, 0.08, IRON, IRON * 1.3)
		k.beam("steel", foot + Vector3(0, 7.25, 0), arm_end + Vector3(0, 0.05, 0), 0.025, 0.025, IRON, IRON)
		for z: Variant in rails:
			b._props.wire(k, Vector3(px, 6.3 - (float(z) - arm_end.z) * 0.02, float(z)), Vector3(px, y + 0.02, float(z)), 0.0, 0.01, WIRE, 2)
		if k.triangle_count() > 3000:
			b.commit(k, b, "TramPoles", true, false)
			k = Kit.new()
	b.commit(k, b, "TramPoles", true, false)
	# the contact wires themselves, sagging a little between supports
	var wk := Kit.new()
	for z: Variant in rails:
		for i: int in range(poles.size() - 1):
			if poles[i + 1] - poles[i] > 30.0:
				b._props.wire(wk, Vector3(poles[i], y, float(z)), Vector3(poles[i] + 22.0, y, float(z)), 0.12, 0.012, WIRE, 6)
				b._props.wire(wk, Vector3(poles[i + 1] - 22.0, y, float(z)), Vector3(poles[i + 1], y, float(z)), 0.12, 0.012, WIRE, 6)
				b._props.wire(wk, Vector3(poles[i] + 22.0, y, float(z)), Vector3(poles[i + 1] - 22.0, y, float(z)), 0.25, 0.012, WIRE, 8)
			else:
				b._props.wire(wk, Vector3(poles[i], y, float(z)), Vector3(poles[i + 1], y, float(z)), 0.15, 0.012, WIRE, 6)
	# up the tram street: span wires from front to front, the two contact wires on them
	var mid := _pair("midSt", Vector2(120, 126))
	var south := _pair("southSt", Vector2(38, 46))
	var plaza := _pair("plaza", Vector2(94, 100))
	var cross := _pair("crossSt", Vector2(64, 70))
	var tx: Array[float] = [mid.x + 1.5, mid.y - 1.5]
	var z := south.y + 1.0
	var spans: Array[float] = []
	while z < plaza.x:
		if z < cross.x - 0.5 or z > cross.y + 0.5: spans.append(z)
		z += 9.0
	for zz: float in spans:
		b._props.wire(wk, Vector3(mid.x, 6.6, zz), Vector3(mid.y, 6.6, zz), 0.25, 0.01, WIRE, 6)
		for cap: float in [mid.x + 0.06, mid.y - 0.06]:
			wk.lathe("steel", Vector3(cap, 6.55, zz), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.1, 0.1), Vector2(0.0, 0.11)]), 6, IRON, IRON)
	for xx: float in tx:
		b._props.wire(wk, Vector3(xx, y, south.y), Vector3(xx, y, plaza.x), 0.0, 0.012, WIRE, 2)
		b._props.wire(wk, Vector3(xx, y, plaza.x), Vector3(xx + (60.0 - xx) * 0.0, y, float(rails[0])), 0.0, 0.012, WIRE, 2)
	b.commit(wk, b, "TramWires", false, false)

## A lamp hung over a street crossing from four span wires, its enamel shade, the bulb, its pool on the snow.
func _crossing_lamps() -> void:
	var xs: Array[Vector2] = [_pair("westSt", Vector2(50, 56)), _pair("alley", Vector2(80, 84)), _pair("midSt", Vector2(120, 126)), _pair("eastSt", Vector2(172, 178))]
	var zs: Array[Vector2] = [_pair("southSt", Vector2(38, 46)), _pair("crossSt", Vector2(64, 70))]
	var spots: Array[Vector3] = []
	for xr: Vector2 in xs:
		for zr: Vector2 in zs:
			spots.append(Vector3((xr.x + xr.y) * 0.5, 6.2, (zr.x + zr.y) * 0.5 + (2.0 if zr.y - zr.x > 7.0 else 0.0)))
	var zg: Array = w.get("zaguan", [109.0, 111.0])
	var north := _pair("northSt", Vector2(20, 30))
	spots.append(Vector3((float(zg[0]) + float(zg[1])) * 0.5, 6.0, north.x + 3.2))
	var east := _pair("eastSt", Vector2(172, 178))
	spots.append(Vector3((east.x + east.y) * 0.5, 6.2, _pair("plaza", Vector2(94, 100)).x + 1.5))
	var k := Kit.new()
	for at: Vector3 in spots:
		var half := 4.0
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			b._props.wire(k, at + Vector3(0, 0.6, 0), at + Vector3(c.x * half, 1.6, c.y * half), 0.15, 0.01, WIRE, 4)
		k.beam("steel", at + Vector3(0, 0.6, 0), at + Vector3(0, 0.2, 0), 0.02, 0.02, WIRE, WIRE)
		k.lathe("steel", at, PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.36, 0.06), Vector2(0.14, 0.2), Vector2(0.05, 0.24), Vector2(0.0, 0.25)]), 12, Color(0.18, 0.26, 0.22), Color(0.26, 0.34, 0.3))
		k.disc("steel", at + Vector3(0, 0.005, 0), 0.4, 12, Rect2(0.3, 0.3, 0.05, 0.05), Color(0.9, 0.88, 0.8), true)
		Snow.cone(k, at + Vector3(0, 0.06, 0), 0.38, 0.24)
		k.lathe("decobulb", at + Vector3(0, -0.02, 0), PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.1, -0.04), Vector2(0.09, 0.04)]), 8)
		b._halo(at + Vector3(0, -0.1, 0), Color(1.0, 0.74, 0.46), 1.6)
		b.pool(Vector3(at.x, 0.0, at.z), 4.6, Color(1.0, 0.6, 0.3) * 0.26)
	b.commit(k, b, "CrossingLamps", false, false)

# ---------------------------------------------------------------------------------------------------------------
# Fires, barriers
# ---------------------------------------------------------------------------------------------------------------
func _flame_material() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	gradient.add_point(0.35, Color(1.0, 0.62, 0.18, 0.85))
	gradient.add_point(0.7, Color(0.9, 0.28, 0.06, 0.35))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.5, 0.1, 0.02, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 1.0)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 128
	flame_material = StandardMaterial3D.new()
	flame_material.albedo_texture = texture
	flame_material.albedo_color = Color(1.6, 1.25, 0.9)
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	flame_material.render_priority = 6

## A brazier: an iron drum on legs, coals glowing, flames licking out of it, a warm flickering light.
func brazier(at: Vector3, k: Kit, light: bool = true) -> void:
	k.lathe("steel", at + Vector3(0, 0.25, 0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.32, 0.55), Vector2(0.33, 0.58), Vector2(0.29, 0.6)]), 12, Color(0.12, 0.1, 0.09), Color(0.3, 0.2, 0.14))
	for i: int in range(3):
		var a := TAU * float(i) / 3.0
		k.beam("steel", at + Vector3(cos(a) * 0.26, 0.28, sin(a) * 0.26), at + Vector3(cos(a) * 0.36, 0.0, sin(a) * 0.36), 0.03, 0.03, IRON, IRON)
	k.disc("decobulb", at + Vector3(0, 0.8, 0), 0.28, 10, Rect2(0.3, 0.3, 0.05, 0.05))
	var flames: Array[Node3D] = []
	for i: int in range(3):
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.75, 1.25)
		f.mesh = q
		f.material_override = flame_material
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = at + Vector3((float(i) - 1.0) * 0.08, 1.2, (float(i % 2) - 0.5) * 0.08)
		f.set_meta("no_batch", true)
		b.add_child(f)
		flames.append(f)
	b._halo(at + Vector3(0, 1.1, 0), Color(1.0, 0.5, 0.18), 4.2)
	var omni: OmniLight3D = null
	if light:
		omni = OmniLight3D.new()
		omni.light_color = Color(1.0, 0.56, 0.24)
		omni.light_energy = 4.5
		omni.omni_range = 9.0
		omni.omni_attenuation = 1.4
		omni.shadow_enabled = false
		omni.position = at + Vector3(0, 1.3, 0)
		b.add_child(omni)
	b.pool(Vector3(at.x, 0.0, at.z), 5.5, Color(1.0, 0.45, 0.16) * 0.5)
	b.add_smoke(at + Vector3(0, 1.8, 0), 5, 0.7)
	fires.append({"light": omni, "flames": flames, "energy": 4.5, "at": at, "phase": rng.randf() * 10.0})

## A curfew barrier: sawhorses with striped boards, set along a house front.
func sawhorse(k: Kit, kd: Kit, at: Vector3, along: Vector3, length: float = 2.2) -> void:
	var side := Vector3(-along.z, 0, along.x)
	var wood := Color(0.55, 0.46, 0.36)
	for end: float in [-length * 0.42, length * 0.42]:
		var c := at + along * end
		for s: float in [-1.0, 1.0]:
			k.beam("planks", c + side * 0.32 * s, c + Vector3(0, 0.95, 0), 0.06, 0.06, wood * 0.7, wood)
	var top := at + Vector3(0, 0.98, 0)
	var a := top - along * length * 0.5
	var bb := top + along * length * 0.5
	k.beam("planks", a, bb, 0.06, 0.08, wood, wood)
	# the striped board across the face
	var h := 0.24
	var o := side * 0.06
	kd.quad_rect("facade", a + o + Vector3(0, -0.12, 0), bb + o + Vector3(0, -0.12, 0), bb + o + Vector3(0, -0.12 + h, 0), a + o + Vector3(0, -0.12 + h, 0), Houses.uv_part("awning_red", 0.0, 0.5, 0.1, 0.5), Color(0.9, 0.9, 0.9), Color.WHITE)
	kd.quad_rect("facade", bb - o + Vector3(0, -0.12, 0), a - o + Vector3(0, -0.12, 0), a - o + Vector3(0, -0.12 + h, 0), bb - o + Vector3(0, -0.12 + h, 0), Houses.uv_part("awning_red", 0.0, 0.5, 0.1, 0.5), Color(0.9, 0.9, 0.9), Color.WHITE)
	Snow.ridge(k, a + Vector3(0, 0.05, 0), bb + Vector3(0, 0.05, 0), Vector3.UP, 0.12, 0.07, 0.03, rng, 0.4, true)

## The Guardia's barriers and fires: at the landing of the transporter bridge against the machine house, and before the
## post's door; the neighbours' fire in front of the tenements, where they stand watching the snow.
func _barricades() -> void:
	var k := Kit.new()
	var kd := Kit.new()
	var m: Array = w.get("machine", [134.0, 105.0, 145.0, 110.0])
	var mx := float(m[2]) + 0.42
	sawhorse(k, kd, Vector3(mx, 0.0, 106.9), Vector3(0, 0, 1), 2.4)
	brazier(Vector3(mx + 0.1, 0.0, 105.4), k)
	# and round the machine house's west end, where the patrol turns
	var wx := float(m[0]) - 0.42
	sawhorse(k, kd, Vector3(wx, 0.0, 108.0), Vector3(0, 0, 1), 2.2)
	brazier(Vector3(wx - 0.05, 0.0, 106.0), k)
	var g: Array = w.get("guardia", [178.0, 46.0, 200.0, 64.0])
	var gx := float(g[0]) - 0.42
	sawhorse(k, kd, Vector3(gx, 0.0, 49.5), Vector3(0, 0, 1), 2.4)
	sawhorse(k, kd, Vector3(gx, 0.0, 60.5), Vector3(0, 0, 1), 2.4)
	brazier(Vector3(gx - 0.05, 0.0, 52.2), k)
	var row_s := float(w.get("rowS", 20.0))
	brazier(Vector3(100.6, 0.0, row_s + 0.45), k)
	# where the west street meets the avenue: the sergeant's corner
	var plaza := _pair("plaza", Vector2(94, 100))
	var west := _pair("westSt", Vector2(50, 56))
	sawhorse(k, kd, Vector3(west.x - 3.6, 0.0, plaza.x + 0.42), Vector3(1, 0, 0), 2.4)
	brazier(Vector3(west.x - 1.6, 0.0, plaza.x + 0.45), k)
	b.commit(k, b, "Barriers", true, false)
	b.commit(kd, b, "BarrierBoards", false, false)

func update(dt: float) -> void:
	_clock += dt
	for f: Dictionary in fires:
		var t: float = _clock * 9.0 + float(f.phase)
		var flick := 0.82 + 0.12 * sin(t) + 0.08 * sin(t * 2.37 + 1.3) + 0.06 * sin(t * 5.1)
		if f.light != null: (f.light as OmniLight3D).light_energy = float(f.energy) * flick
		var i := 0
		for flame: Node3D in f.flames:
			var s := 0.8 + 0.25 * sin(t * (1.0 + 0.3 * float(i)) + float(i) * 2.0)
			flame.scale = Vector3(0.9 + 0.1 * sin(t * 1.7 + float(i)), s, 1.0)
			flame.position.y = (f.at as Vector3).y + 1.15 + 0.55 * s * 0.5
			i += 1

# ---------------------------------------------------------------------------------------------------------------
# The quay's edge, the river
# ---------------------------------------------------------------------------------------------------------------
## Iron bollards on the quay's edge stone (half over the water), every few metres, not where the boat or the gondola
## comes in.
func _bollards() -> void:
	var quay := _pair("quay", Vector2(105, 110))
	var boat := _pair("boat", Vector2(42, 48))
	var gon := _pair("gondola", Vector2(146, 154))
	var k := Kit.new()
	var x := -56.0
	var n := 0
	while x < map_size.x + 56.0:
		var clear := (x > boat.x - 2.0 and x < boat.y + 2.0) or (x > gon.x - 3.0 and x < gon.y + 3.0)
		if not clear:
			k.lathe("steel", Vector3(x, 0.0, quay.y + 0.06), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.15, 0.32), Vector2(0.12, 0.42), Vector2(0.2, 0.5), Vector2(0.2, 0.56), Vector2(0.0, 0.6)]), 10, IRON * 0.7, IRON * 1.4)
			Snow.cone(k, Vector3(x, 0.57, quay.y + 0.06), 0.19, 0.12)
			n += 1
		x += 7.5
		if n % 10 == 9:
			b.commit(k, b, "Bollards", true, false)
			k = Kit.new()
			n += 1
	b.commit(k, b, "Bollards", true, false)

## Boats moored in the river, clear of the boat's crossing, the gondola's run and the launch.
func _moored() -> void:
	var quay := _pair("quay", Vector2(105, 110))
	_tug(Vector3(14.0, WATER_Y, quay.y + 3.0), 0.0)
	_lighter(Vector3(186.0, WATER_Y, quay.y + 2.6))
	_freighter(Vector3(118.0, WATER_Y, river.y - 3.4))
	_crane(Vector3(214.0, WATER_Y, river.y - 5.0))

## A hull: a lathe stretched along x, flat on top. Returns the deck height.
func _hull(k: Kit, at: Vector3, length: float, beam: float, freeboard: float, col: Color) -> float:
	k.push(Transform3D(Basis.from_scale(Vector3(length * 0.5, 1.0, beam * 0.5)), at))
	k.lathe("hull", Vector3(0, -0.6, 0), PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.92, 0.4), Vector2(1.0, 0.6 + freeboard * 0.5), Vector2(1.0, 0.6 + freeboard), Vector2(0.0, 0.6 + freeboard + 0.01)]), 18, col * 0.5, col)
	k.pop()
	return at.y + freeboard

func _portholes(kd: Kit, start: Vector3, along: Vector3, out: Vector3, count: int, gap: float, lit_chance: float) -> void:
	for i: int in range(count):
		var p := start + along * gap * float(i)
		var lit := rng.randf() < lit_chance
		var s := 0.2
		var key := "facade_lit" if lit else "facade"
		var col := Color(1.0, 0.82, 0.55) if lit else Color.WHITE
		kd.quad_rect(key, p - along * s + Vector3(0, -s, 0) + out * 0.02, p + along * s + Vector3(0, -s, 0) + out * 0.02, p + along * s + Vector3(0, s, 0) + out * 0.02, p - along * s + Vector3(0, s, 0) + out * 0.02, Houses.uv("porthole_lit" if lit else "porthole_dark"), col, col)

## A harbour tug at the quay: black hull, a deckhouse with its portholes lit, a tall funnel smoking, a mast.
func _tug(at: Vector3, _yaw: float) -> void:
	var k := Kit.new()
	var kd := Kit.new()
	var deck := _hull(k, at, 15.0, 4.4, 2.6, Color(0.16, 0.16, 0.17))
	k.push_tint(Color(0.72, 0.68, 0.6))
	k.box("planks", Vector3(at.x, deck + 0.05, at.z), Vector3(13.0, 0.1, 3.8), Color(0.6, 0.6, 0.6), Color.WHITE, Vector2.ZERO, Kit.BEAM)
	k.pop_tint()
	k.push_tint(Color(0.86, 0.82, 0.74))
	k.box("planks", Vector3(at.x - 0.8, deck + 1.1, at.z), Vector3(5.6, 2.0, 2.6), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.box("planks", Vector3(at.x + 0.6, deck + 2.6, at.z), Vector3(2.2, 1.0, 2.2), Color(0.7, 0.7, 0.7), Color.WHITE)
	k.pop_tint()
	for s: float in [-1.0, 1.0]:
		_portholes(kd, Vector3(at.x - 3.0, deck + 1.2, at.z + s * 1.31), Vector3(1, 0, 0), Vector3(0, 0, s), 5, 1.0, 0.7)
	_portholes(kd, Vector3(at.x + 0.0, deck + 2.7, at.z + 1.11), Vector3(1, 0, 0), Vector3(0, 0, 1), 2, 1.1, 0.9)
	k.lathe("steel", Vector3(at.x - 1.6, deck + 2.0, at.z), PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.42, 2.4), Vector2(0.38, 2.5), Vector2(0.0, 2.52)]), 12, Color(0.12, 0.12, 0.12), Color(0.2, 0.18, 0.16))
	k.lathe("steel", Vector3(at.x - 1.6, deck + 3.6, at.z), PackedVector2Array([Vector2(0.43, 0.0), Vector2(0.43, 0.35)]), 12, Color(0.7, 0.16, 0.12), Color(0.8, 0.2, 0.14))
	k.beam("steel", Vector3(at.x + 3.5, deck, at.z), Vector3(at.x + 3.5, deck + 6.5, at.z), 0.08, 0.08, IRON, IRON)
	b.add_smoke(Vector3(at.x - 1.6, deck + 4.8, at.z), 6, 1.1)
	b._halo(Vector3(at.x + 3.5, deck + 6.6, at.z), Color(1.0, 0.8, 0.55), 0.8)
	b.commit(k, b, "Tug", true, false)
	b.commit(kd, b, "TugLights", false, false)

## A lighter moored at the quay: a long low hull, hatch covers under snow, a little wheelhouse aft, one window lit.
func _lighter(at: Vector3) -> void:
	var k := Kit.new()
	var kd := Kit.new()
	var deck := _hull(k, at, 24.0, 4.2, 1.9, Color(0.3, 0.26, 0.22))
	for i: int in range(4):
		k.push_tint(Color(0.3, 0.32, 0.28))
		k.box("canvas", Vector3(at.x - 7.5 + float(i) * 4.4, deck + 0.35, at.z), Vector3(3.6, 0.6, 2.6), Color(0.6, 0.6, 0.6), Color.WHITE)
		k.pop_tint()
	k.push_tint(Color(0.6, 0.54, 0.46))
	k.box("planks", Vector3(at.x + 9.6, deck + 1.0, at.z), Vector3(2.4, 2.0, 2.4), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	var lit := Color(1.0, 0.82, 0.55)
	kd.quad_rect("facade_lit", Vector3(at.x + 9.0, deck + 1.0, at.z + 1.22), Vector3(at.x + 10.0, deck + 1.0, at.z + 1.22), Vector3(at.x + 10.0, deck + 1.6, at.z + 1.22), Vector3(at.x + 9.0, deck + 1.6, at.z + 1.22), Houses.uv("win_small_lit"), lit, lit)
	b.commit(k, b, "Lighter", true, false)
	b.commit(kd, b, "LighterLights", false, false)

## An old freighter laid up at the far bank: rust-streaked hull, her bridge house aft with a few portholes lit, a mast.
func _freighter(at: Vector3) -> void:
	var k := Kit.new()
	var kd := Kit.new()
	var deck := _hull(k, at, 30.0, 5.6, 3.4, Color(0.32, 0.2, 0.16))
	k.push_tint(Color(0.82, 0.78, 0.7))
	k.box("planks", Vector3(at.x + 9.0, deck + 1.4, at.z), Vector3(6.0, 2.8, 4.2), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.box("planks", Vector3(at.x + 9.6, deck + 3.6, at.z), Vector3(3.6, 1.6, 3.6), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	for s: float in [-1.0, 1.0]:
		_portholes(kd, Vector3(at.x + 6.8, deck + 1.6, at.z + s * 2.11), Vector3(1, 0, 0), Vector3(0, 0, s), 5, 1.0, 0.45)
	k.lathe("steel", Vector3(at.x + 7.6, deck + 2.8, at.z), PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.6, 2.6), Vector2(0.0, 2.62)]), 12, Color(0.16, 0.16, 0.16), Color(0.24, 0.22, 0.2))
	for mx: float in [at.x - 8.0, at.x + 2.0]:
		k.beam("steel", Vector3(mx, deck, at.z), Vector3(mx, deck + 9.0, at.z), 0.12, 0.12, IRON, IRON)
		k.beam("steel", Vector3(mx, deck + 6.0, at.z), Vector3(mx - 3.5, deck + 1.0, at.z), 0.08, 0.08, IRON, IRON)
	b._halo(Vector3(at.x + 2.0, deck + 9.1, at.z), Color(1.0, 0.8, 0.55), 0.8)
	b.commit(k, b, "Freighter", true, false)
	b.commit(kd, b, "FreighterLights", false, false)

## A floating crane: a pontoon, the machinery house, the lattice jib raised over the water, its hook hanging.
func _crane(at: Vector3) -> void:
	var k := Kit.new()
	var kd := Kit.new()
	k.push_tint(Color(0.24, 0.24, 0.24))
	k.box("steel", at + Vector3(0, 0.6, 0), Vector3(12.0, 2.0, 7.0), Color(0.5, 0.5, 0.5), Color.WHITE)
	k.pop_tint()
	var d := at.y + 1.6
	k.push_tint(Color(0.5, 0.42, 0.3))
	k.box("planks", Vector3(at.x + 2.5, d + 1.4, at.z), Vector3(4.0, 2.8, 4.0), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	var lit := Color(1.0, 0.82, 0.55)
	kd.quad_rect("facade_lit", Vector3(at.x + 1.0, d + 1.4, at.z - 2.02), Vector3(at.x + 0.0, d + 1.4, at.z - 2.02), Vector3(at.x + 0.0, d + 2.2, at.z - 2.02), Vector3(at.x + 1.0, d + 2.2, at.z - 2.02), Houses.uv("win_small_lit"), lit, lit)
	var foot := Vector3(at.x - 1.0, d, at.z)
	var tip := Vector3(at.x - 9.0, d + 15.0, at.z - 6.0)
	for s: float in [-0.8, 0.8]:
		k.beam("steel", foot + Vector3(0, 0, s), tip + Vector3(0, 0, s * 0.3), 0.14, 0.14, Color(0.5, 0.3, 0.16), Color(0.6, 0.36, 0.2))
	for i: int in range(10):
		var t0 := float(i) / 10.0
		var t1 := float(i + 1) / 10.0
		var p0 := foot.lerp(tip, t0)
		var p1 := foot.lerp(tip, t1)
		k.beam("steel", p0 + Vector3(0, 0, -0.8 * (1.0 - t0 * 0.6)), p1 + Vector3(0, 0, 0.8 * (1.0 - t1 * 0.6)), 0.05, 0.05, Color(0.5, 0.3, 0.16), Color(0.6, 0.36, 0.2))
	b._props.wire(k, tip, Vector3(at.x + 4.0, d + 3.0, at.z), 0.0, 0.03, WIRE, 2)
	b._props.wire(k, tip, tip + Vector3(0, -12.0, 0), 0.0, 0.02, WIRE, 2)
	k.box("steel", tip + Vector3(0, -12.2, 0), Vector3(0.3, 0.4, 0.3), IRON, IRON)
	b._halo(tip + Vector3(0, 0.2, 0), Color(1.0, 0.3, 0.15), 0.9)
	b.commit(k, b, "FloatingCrane", true, false)
	b.commit(kd, b, "FloatingCraneLights", false, false)

## The red pillar box on the café's side street, black at its foot.
func _post_box() -> void:
	var cafe: Array = w.get("cafe", [56.0, 80.0, 80.0, 94.0])
	var at := Vector3(float(cafe[0]) - 0.36, 0.0, float(cafe[3]) - 5.5)
	var k := Kit.new()
	k.lathe("steel", at, PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.24, 0.3), Vector2(0.2, 0.32), Vector2(0.2, 1.2), Vector2(0.28, 1.25), Vector2(0.28, 1.36), Vector2(0.2, 1.46), Vector2(0.0, 1.53)]), 12, Color(0.08, 0.08, 0.08), Color(0.62, 0.06, 0.05))
	b.commit(k, b, "PostBox", true, false)

# ---------------------------------------------------------------------------------------------------------------
# Cars and the colectivo, round the map
# ---------------------------------------------------------------------------------------------------------------
func _parked() -> void:
	var k := Kit.new()
	var kd := Kit.new()
	var W := map_size.x
	var spots: Array = [
		[Vector3(32.0, 0, -1.9), 0.0], [Vector3(74.0, 0, -1.9), PI], [Vector3(152.0, 0, -1.9), 0.0], [Vector3(207.0, 0, -1.9), PI],
		[Vector3(-2.2, 0, 12.0), PI * 0.5], [Vector3(-2.2, 0, 56.0), -PI * 0.5], [Vector3(-2.2, 0, 84.0), PI * 0.5],
		[Vector3(W + 2.2, 0, 14.0), -PI * 0.5], [Vector3(W + 2.2, 0, 52.0), PI * 0.5], [Vector3(W + 2.2, 0, 86.0), -PI * 0.5],
		[Vector3(22.0, 0, map_size.y + 2.2), 0.0], [Vector3(78.0, 0, map_size.y + 2.2), PI], [Vector3(184.0, 0, map_size.y + 2.2), 0.0],
		[Vector3(134.0, 0, map_size.y + 2.2), 0.0], [Vector3(146.5, 0, map_size.y + 2.2), PI], [Vector3(203.0, 0, map_size.y + 2.2), 0.0],
		[Vector3(216.0, 0, map_size.y + 2.2), PI],
		[Vector3(-26.0, 0, 103.6), 0.0], [Vector3(-44.0, 0, 101.4), PI],
	]
	var paints := ["1c1e22", "2c3a30", "5a1e1a", "d8ceb0", "6a8aa0", "3a3a40", "7a6a4a", "203048"]
	# and the cars in the workshop yards inside the blocks
	var houses: Variant = b.get("houses")
	if houses != null: spots.append_array(houses.yard_cars)
	for s: Array in spots:
		_car(k, kd, s[0], s[1], Houses.hexc(paints[rng.randi() % paints.size()]))
	# the colectivo waits in the street behind the far bank, where the hero view can see it
	_colectivo(k, kd, Vector3(166.0, 0.0, map_size.y + 2.5), PI)
	b.commit(k, b, "Cars", true, false)
	b.commit(kd, b, "CarLights", false, false)

## Goods wagons left standing in the railway cutting since the line went quiet: wooden box vans and an open wagon
## heaped with snow, on the track at the cutting's floor (inside the gorge nobody walks), clear of the footbridge,
## the road bridge and the ladder. Their roofs sit just under the street, white.
func _wagons() -> void:
	var cut := _pair("cut", Vector2(30, 38))
	var depth := float(w.get("cutDepth", 4.0))
	var rz := float(w.get("railZ", (cut.x + cut.y) * 0.5))
	var k := Kit.new()
	var y0 := -depth + 0.2
	var x := 46.0
	for i: int in range(3):
		_wagon(k, Vector3(x, y0, rz), i == 1)
		x += 8.6
	_wagon(k, Vector3(122.0, y0, rz), false)
	_wagon(k, Vector3(130.6, y0, rz), true)
	_wagon(k, Vector3(196.0, y0, rz), false)
	_wagon(k, Vector3(-24.0, y0, rz), false)
	_wagon(k, Vector3(-32.6, y0, rz), false)
	b.commit(k, b, "Wagons", true, false)

func _wagon(k: Kit, at: Vector3, open: bool) -> void:
	var body := Houses.hexc(["7a3328", "6a3a2c", "5e4a3a", "7a4a30"][rng.randi() % 4]) * rng.randf_range(0.9, 1.05)
	body.a = 1.0
	var iron := Color(0.16, 0.16, 0.17)
	var L := 7.8
	var hw := 1.32
	k.push(Transform3D(Basis.IDENTITY, at))
	# bogies, wheels, the frame and buffers
	for bx: float in [-2.6, 2.6]:
		k.box("steel", Vector3(bx, 0.42, 0), Vector3(2.2, 0.3, 1.9), iron, iron * 1.5)
		for wx: float in [-0.75, 0.75]:
			for sz: float in [-0.72, 0.72]:
				k.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bx + wx, 0.42, sz)))
				k.lathe("steel", Vector3(0, -0.06, 0), PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.42, 0.12), Vector2(0.0, 0.12)]), 8, iron, iron * 1.3)
				k.pop()
	k.box("steel", Vector3(0, 0.82, 0), Vector3(L, 0.26, hw * 2.0 - 0.1), iron, iron * 1.4)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.62, 0.62]:
			k.beam("steel", Vector3(sx * L * 0.5, 0.82, sz), Vector3(sx * (L * 0.5 + 0.45), 0.82, sz), 0.12, 0.12, iron, iron * 1.4)
	var h := 2.5 if not open else 1.2
	k.push_tint(body)
	k.box("planks", Vector3(0, 0.95 + h * 0.5, 0), Vector3(L, h, hw * 2.0), Color(0.75, 0.75, 0.75), Color.WHITE)
	k.pop_tint()
	# iron strapping on the planks
	for sx: float in [-3.6, -1.8, 0.0, 1.8, 3.6]:
		for sz: float in [-1.0, 1.0]:
			k.box("steel", Vector3(sx, 0.95 + h * 0.5, sz * (hw + 0.02)), Vector3(0.1, h, 0.03), iron, iron * 1.3)
	if open:
		# heaped with snow
		Snow.pillow(k, Snow.rect_poly(Rect2(-L * 0.5 + 0.1, -hw + 0.1, L - 0.2, hw * 2.0 - 0.2)), 0.95 + h - 0.15, 0.32, 0.6, rng)
	else:
		# a sliding door half open on one side, the low arched roof under its snow
		k.box("planks", Vector3(0.6, 0.95 + h * 0.5, hw + 0.06), Vector3(1.9, h - 0.2, 0.06), body * 0.8, body)
		k.box("steel", Vector3(0, 0.95 + h + 0.08, 0), Vector3(L + 0.1, 0.16, hw * 2.0 + 0.12), Color(0.3, 0.3, 0.31), Color(0.4, 0.4, 0.42))
		Snow.box_top(k, Vector3(0, 0.95 + h + 0.16, 0), Vector2(L + 0.06, hw * 2.0 + 0.1), 0.22, rng)
	k.pop()

## A rounded car of the late forties under a cap of snow: a side profile extruded across, narrower at the roof.
## yaw 0: the car lies along x.
func _car(k: Kit, kd: Kit, at: Vector3, yaw: float, paint: Color) -> void:
	var prof := PackedVector2Array([Vector2(-2.35, 0.34), Vector2(-2.4, 0.62), Vector2(-2.2, 0.84), Vector2(-0.95, 0.96), Vector2(-0.48, 1.42),
		Vector2(0.55, 1.5), Vector2(1.25, 1.34), Vector2(2.05, 0.98), Vector2(2.36, 0.74), Vector2(2.32, 0.34)])
	var hw := 0.9
	k.push(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), at))
	paint.a = 1.0
	k.push_tint(paint)
	var half := func(y: float) -> float: return hw * (1.0 - 0.17 * smoothstep(0.95, 1.5, y))
	var c := Vector2(0.0, 0.85)
	for i: int in range(prof.size()):
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[(i + 1) % prof.size()]
		var h0: float = half.call(p0.y)
		var h1: float = half.call(p1.y)
		var glass := i == 3 or i == 5
		var key := "facade" if glass else "stucco"
		if glass:
			k.pop_tint()
			kd.quad_rect("facade", Vector3(-h0, p0.y, p0.x), Vector3(-h1, p1.y, p1.x), Vector3(h1, p1.y, p1.x), Vector3(h0, p0.y, p0.x), Houses.uv_part("win_dark0", 0.1, 0.9, 0.3, 0.7), Color.WHITE, Color.WHITE)
			k.push_tint(paint)
		else:
			k.quad_m(key, Vector3(-h0, p0.y, p0.x), Vector3(-h1, p1.y, p1.x), Vector3(h1, p1.y, p1.x), Vector3(h0, p0.y, p0.x))
		# the two sides
		var hc: float = half.call(c.y)
		k.tri("stucco", Vector3(hc, c.y, c.x), Vector3(h0, p0.y, p0.x), Vector3(h1, p1.y, p1.x), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1))
		k.tri("stucco", Vector3(-hc, c.y, c.x), Vector3(-h1, p1.y, p1.x), Vector3(-h0, p0.y, p0.x), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1))
	k.pop_tint()
	# side windows, chrome bumpers, wheels, snow on the roof and the bonnet
	for s: float in [-1.0, 1.0]:
		var hx: float = half.call(1.2)
		var x: float = s * (hx + 0.012)
		var q := [Vector3(x, 1.0, -0.55), Vector3(x, 1.0, 1.15), Vector3(x, 1.36, 0.95), Vector3(x, 1.38, -0.4)]
		if s < 0.0: kd.quad_rect("facade", q[1], q[0], q[3], q[2], Houses.uv_part("win_dark1", 0.1, 0.9, 0.3, 0.6), Color.WHITE, Color.WHITE)
		else: kd.quad_rect("facade", q[0], q[1], q[2], q[3], Houses.uv_part("win_dark1", 0.1, 0.9, 0.3, 0.6), Color.WHITE, Color.WHITE)
		for zz: float in [-1.45, 1.45]:
			k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.78, 0.36, zz)))
			k.lathe("rubber", Vector3(0, -0.11, 0), PackedVector2Array([Vector2(0.36, 0.0), Vector2(0.36, 0.22), Vector2(0.0, 0.22)]), 10, Color(0.12, 0.12, 0.12), Color(0.2, 0.2, 0.2))
			k.pop()
	for zz: float in [-2.42, 2.38]:
		k.box("steel", Vector3(0, 0.42, zz), Vector3(1.84, 0.12, 0.1), Color(0.6, 0.62, 0.64), Color(0.85, 0.86, 0.88))
	# a pillow of snow on the roof, the bonnet and the boot (the car has stood all evening)
	Snow.pillow(k, Snow.rect_poly(Rect2(-0.66, -0.44, 1.32, 0.98)), 1.44, 0.16, 0.32, rng)
	Snow.pillow(k, Snow.rect_poly(Rect2(-0.74, -2.2, 1.48, 1.16)), 0.9, 0.11, 0.3, rng)
	Snow.ridge(k, Vector3(-0.7, 1.1, 1.6), Vector3(0.7, 1.1, 1.6), Vector3.UP, 0.7, 0.1, 0.05, rng, 0.4, true)
	k.pop()

## A colectivo of the fifties: a rounded body in two colours, fileteado along its flank, its windows lit, the
## destination board, headlamps on: it waits on the avenue with its engine running.
func _colectivo(k: Kit, kd: Kit, at: Vector3, yaw: float) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), at))
	var red := Houses.hexc("9a2a22")
	var cream := Houses.hexc("e2d8bc")
	var L := 7.8
	var H := 2.7
	var hw := 1.15
	k.push_tint(red)
	k.box("stucco", Vector3(0, 0.95, 0), Vector3(hw * 2.0, 1.1, L), Color(0.6, 0.6, 0.6), Color.WHITE)
	k.pop_tint()
	k.push_tint(cream)
	k.box("stucco", Vector3(0, 2.05, 0), Vector3(hw * 2.0, 1.1, L - 0.2), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.box("stucco", Vector3(0, H - 0.02, 0), Vector3(hw * 2.0 - 0.3, 0.2, L - 0.6), Color(0.8, 0.8, 0.8), Color.WHITE)
	k.pop_tint()
	var lit := Color(1.0, 0.86, 0.62)
	for s: float in [-1.0, 1.0]:
		var x := s * (hw + 0.01)
		var z := -L * 0.5 + 0.9
		while z < L * 0.5 - 1.2:
			var a := Vector3(x, 1.65, z)
			var bb := Vector3(x, 1.65, z + 0.9)
			if s > 0.0: kd.quad_rect("facade_lit", bb, a, a + Vector3(0, 0.7, 0), bb + Vector3(0, 0.7, 0), Houses.uv("tram_win_lit"), lit, lit)
			else: kd.quad_rect("facade_lit", a, bb, bb + Vector3(0, 0.7, 0), a + Vector3(0, 0.7, 0), Houses.uv("tram_win_lit"), lit, lit)
			z += 1.05
		var fa := Vector3(x, 1.05, -L * 0.5 + 0.4)
		var fb := Vector3(x, 1.05, L * 0.5 - 0.4)
		if s > 0.0: kd.quad_rect("facade", fb, fa, fa + Vector3(0, 0.45, 0), fb + Vector3(0, 0.45, 0), Houses.uv("filete_band"), Color.WHITE, Color.WHITE)
		else: kd.quad_rect("facade", fa, fb, fb + Vector3(0, 0.45, 0), fa + Vector3(0, 0.45, 0), Houses.uv("filete_band"), Color.WHITE, Color.WHITE)
		for zz: float in [-L * 0.32, L * 0.3]:
			k.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 1.0, 0.45, zz)))
			k.lathe("rubber", Vector3(0, -0.14, 0), PackedVector2Array([Vector2(0.46, 0.0), Vector2(0.46, 0.28), Vector2(0.0, 0.28)]), 10, Color(0.12, 0.12, 0.12), Color(0.2, 0.2, 0.2))
			k.pop()
	var front := L * 0.5 + 0.01
	kd.quad_rect("facade_lit", Vector3(-0.9, 2.3, front), Vector3(0.9, 2.3, front), Vector3(0.9, 2.6, front), Vector3(-0.9, 2.6, front), Houses.uv("tram_dest"), Color(1.0, 0.9, 0.7), Color(1.0, 0.9, 0.7))
	kd.quad_rect("facade_lit", Vector3(-1.0, 1.55, front), Vector3(1.0, 1.55, front), Vector3(1.0, 2.2, front), Vector3(-1.0, 2.2, front), Houses.uv("tram_win_lit"), lit * 0.8, lit * 0.8)
	for s2: float in [-0.75, 0.75]:
		k.lathe("decobulb", Vector3(s2, 0.8, front - 0.02), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.02)]), 8)
	Snow.pillow(k, Snow.rect_poly(Rect2(-hw + 0.1, -L * 0.5 + 0.35, hw * 2.0 - 0.2, L - 0.7)), H + 0.08, 0.18, 0.4, rng)
	k.pop()
	var turn := Basis(Vector3.UP, yaw + PI * 0.5)
	var world_front := at + turn * Vector3(0, 0.8, front + 0.2)
	b.spill(Vector3(world_front.x, 0.0, world_front.z), turn * Vector3(1, 0, 0), turn * Vector3(0, 0, 1), 1.6, 7.0, 0.9)

# ---------------------------------------------------------------------------------------------------------------
# Trees
# ---------------------------------------------------------------------------------------------------------------
## A bare plane tree in winter: a mottled trunk, four limbs forking twice, crowns of twig cards white with wet snow,
## snow along the tops of the limbs. As one mesh, for a MultiMesh.
func plane_tree(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var k := Kit.new()
	var bark := Color(0.5, 0.48, 0.42)
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.28, -0.2), Vector2(0.25, 0.4), Vector2(0.21, 1.6), Vector2(0.19, 3.0), Vector2(0.16, 3.4)]), 8, bark * 0.7, bark, Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	var tips: Array = []
	for i: int in range(5):
		var a := TAU * float(i) / 5.0 + r.randf_range(-0.4, 0.4)
		var start := Vector3(0, 3.0 + r.randf_range(0.0, 0.4), 0)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := start + dir * r.randf_range(1.5, 2.2) + Vector3(0, r.randf_range(2.2, 2.9), 0)
		k.tube("planks", PackedVector3Array([start, start.lerp(mid, 0.5) + Vector3(0, 0.2, 0), mid]), 0.13, 5, bark)
		Snow.ridge(k, start.lerp(mid, 0.2) + Vector3(0, 0.12, 0), mid + Vector3(0, 0.1, 0), Vector3.UP, 0.16, 0.08, 0.02, null, 0.3)
		for j: int in range(2):
			var a2 := a + (float(j) - 0.5) * r.randf_range(0.7, 1.1)
			var tip := mid + Vector3(cos(a2), 0.0, sin(a2)) * r.randf_range(1.3, 2.0) + Vector3(0, r.randf_range(1.3, 2.0), 0)
			k.tube("planks", PackedVector3Array([mid, mid.lerp(tip, 0.5) + Vector3(0, 0.15, 0), tip]), 0.07, 4, bark)
			tips.append([tip, a2])
	# crowns: twig cards fanned out from each tip, and a dome of them across the top for the view from above
	for t: Array in tips:
		var tip: Vector3 = t[0]
		var a: float = t[1]
		for c: int in range(2):
			var yaw := a + PI * 0.5 + (float(c) - 0.5) * 0.9
			var right := Vector3(cos(yaw), 0, sin(yaw))
			var out := Vector3(cos(a), 0, sin(a))
			var s := r.randf_range(2.6, 3.4)
			var base := tip - Vector3(0, s * 0.35, 0) - out * 0.2
			var up := (Vector3.UP + out * 0.35).normalized()
			k.quad_rect("twigs", base - right * s * 0.5, base + right * s * 0.5, base + right * s * 0.5 + up * s, base - right * s * 0.5 + up * s, Rect2(0, 0, 1, 1), Color.WHITE, Color.WHITE)
	for c: int in range(5):
		var yaw := r.randf() * TAU
		var right := Vector3(cos(yaw), 0, sin(yaw))
		var fwd := Vector3(-right.z, 0, right.x)
		var s := 4.4
		var base := Vector3(0, 6.6, 0) - fwd * s * 0.45
		var up := (fwd * 0.85 + Vector3.UP * 0.5).normalized()
		k.quad_rect("twigs", base - right * s * 0.5, base + right * s * 0.5, base + right * s * 0.5 + up * s, base - right * s * 0.5 + up * s, Rect2(0, 0, 1, 1), Color.WHITE, Color.WHITE)
	return _mesh(k)

## A big evergreen of the patios (an old magnolia, a ficus, a laurel): a short trunk under a broad crown of leaf clumps,
## dark beneath and caught with snow on top, wider than it is tall. As one mesh, for a MultiMesh.
func evergreen(seed_value: int, clumps: int = 11) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var k := Kit.new()
	var bark := Color(0.34, 0.3, 0.26)
	k.lathe("planks", Vector3.ZERO, PackedVector2Array([Vector2(0.3, -0.2), Vector2(0.24, 1.0), Vector2(0.2, 2.4), Vector2(0.12, 3.2)]), 7, bark * 0.7, bark, Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	for i: int in range(3):
		var a := TAU * float(i) / 3.0 + r.randf()
		k.tube("planks", PackedVector3Array([Vector3(0, 2.0, 0), Vector3(cos(a) * 1.2, 3.3, sin(a) * 1.2)]), 0.1, 4, bark)
	var leaf := Color(1, 1, 1)
	for i: int in range(clumps):
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 2.4
		var h := 3.2 + (2.6 - d * 0.55) * r.randf_range(0.7, 1.15)
		var c := Vector3(cos(a) * d, h, sin(a) * d)
		var rad := r.randf_range(1.15, 1.7)
		var prof := PackedVector2Array()
		for j: int in range(5):
			var t := -PI * 0.5 + PI * float(j) / 4.0
			prof.append(Vector2(maxf(cos(t), 0.0) * rad * r.randf_range(0.9, 1.1), (sin(t) * 0.75 + 0.75) * rad))
		k.push_tint(leaf * r.randf_range(0.75, 1.1))
		k.lathe("leaves", c - Vector3(0, rad * 0.75, 0), prof, 6, Color(0.55, 0.55, 0.55), Color.WHITE, Vector2(r.randf(), r.randf()))
		k.pop_tint()
	return _mesh(k)

## A Canary palm, as in the plazas: a thick scaly trunk and a round head of fronds, the fronds' tops white with snow
## (in 2007 the photographs of palms under snow went round the country).
func palm(seed_value: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var k := Kit.new()
	var h := 5.6
	var trunk := Color(0.5, 0.42, 0.32)
	var prof := PackedVector2Array()
	for i: int in range(9):
		var t := float(i) / 8.0
		prof.append(Vector2(0.46 - 0.1 * t + 0.03 * sin(t * 30.0), t * h))
	prof.append(Vector2(0.55, h + 0.1))
	prof.append(Vector2(0.0, h + 0.5))
	k.lathe("stone", Vector3.ZERO, prof, 10, trunk * 0.7, trunk)
	var green := Color(0.18, 0.3, 0.14)
	for i: int in range(20):
		var a := TAU * float(i) / 20.0 + r.randf_range(-0.1, 0.1)
		var rise := r.randf_range(0.6, 1.4) if i % 2 == 0 else r.randf_range(-0.2, 0.6)
		var length := r.randf_range(2.6, 3.4)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var rows := 7
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for j: int in range(rows):
			var t := float(j) / float(rows - 1)
			var p := Vector3(0, h + 0.3, 0) + dir * (0.3 + length * t) + Vector3(0, rise * t * 2.0 - (rise + 1.6) * t * t, 0)
			var wd := 0.45 * sin(PI * minf(1.0, t * 1.15 + 0.1))
			for c: float in [-1.0, 0.0, 1.0]:
				pts.append(p + side * wd * c + Vector3(0, absf(c) * 0.12 - 0.04, 0))
				uvs.append(Vector2(c * 0.5 + 0.5, t))
		k.push_tint(green * r.randf_range(0.85, 1.15))
		k.patch("canvas", rows, 3, pts, uvs, PackedColorArray([Color.WHITE]), false, false)
		k.patch("canvas", rows, 3, pts, uvs, PackedColorArray([Color(0.6, 0.6, 0.6)]), false, true)
		k.pop_tint()
	return _mesh(k)

func _mesh(k: Kit) -> ArrayMesh:
	var holder := Node3D.new()
	var m: MeshInstance3D = k.commit(holder, b.materials, "Tmp", true)
	var mesh: ArrayMesh = m.mesh
	holder.free()
	return mesh

## Every tree: plane trees and evergreens in the patios, plane trees along the streets round the map (on their
## pavements, outside the map), palms in a few patios.
func trees(spots: Array[Vector3], palm_spots: Array[Vector3], room: Array[float] = []) -> void:
	var W := map_size.x
	var H := map_size.y
	var street: Array[Vector3] = []
	var x := -54.0
	while x < -10.0:
		street.append(Vector3(x, 0.0, 96.6))
		x += 9.0
	x = W + 12.0
	while x < W + 56.0:
		street.append(Vector3(x, 0.0, 96.6))
		x += 9.0
	# along the lane behind the north row, the streets west and east of the map, the street behind the far bank
	x = -50.0
	while x < W + 50.0:
		if fmod(x + 50.0, 27.0) > 3.0:
			street.append(Vector3(x, 0.0, -6.7))
			street.append(Vector3(x + 4.5, 0.0, H + 7.3))
		x += 13.0
	var z := -36.0
	while z < 100.0:
		if (z < 28.0 or z > 40.0):
			street.append(Vector3(-7.4, 0.0, z))
			street.append(Vector3(W + 7.4, 0.0, z + 5.0))
		z += 12.0
	var kinds: Array[ArrayMesh] = [plane_tree(31), plane_tree(32), plane_tree(33)]
	var greens: Array[ArrayMesh] = [evergreen(51), evergreen(52), evergreen(53)]
	var bare: Array[Vector3] = street.duplicate()
	var leafy: Array[Vector3] = []
	var leafy_scale: Array[float] = []
	for i: int in range(spots.size()):
		var limit := room[i] if i < room.size() else 6.0
		if i % 3 != 2:
			leafy.append(spots[i])
			# the crown is about 4 m round at scale 1
			leafy_scale.append(clampf(limit / 4.0, 0.75, 1.5) * rng.randf_range(0.85, 1.0))
		else: bare.append(spots[i])
	for i: int in range(kinds.size()):
		var list: Array[Vector3] = []
		for j: int in range(bare.size()):
			if j % kinds.size() == i: list.append(bare[j])
		_multi(kinds[i], list, "PlaneTrees%d" % i, 0.85, 1.15)
	for i: int in range(greens.size()):
		var list2: Array[Vector3] = []
		var sc2: Array[float] = []
		for j: int in range(leafy.size()):
			if j % greens.size() == i:
				list2.append(leafy[j])
				sc2.append(leafy_scale[j])
		_multi(greens[i], list2, "Evergreens%d" % i, 1.0, 1.0, sc2)
	if not palm_spots.is_empty():
		_multi(palm(41), palm_spots, "Palms", 0.9, 1.1)
	_cutting_growth()

## The railway cutting has gone wild since the trains stopped running often: young trees and bushes along the foot
## of its walls (inside the gorge the rules keep everyone out of), clear of the track, the bridges and the ladder.
func _cutting_growth() -> void:
	var cut := _pair("cut", Vector2(30, 38))
	var depth := float(w.get("cutDepth", 4.0))
	var keep: Array[Vector2] = [_pair("footbridge", Vector2(30, 34)), _pair("roadbridge", Vector2(160, 168)), _pair("ladder", Vector2(104, 106))]
	var young: Array[Vector3] = []
	var bush: Array[Vector3] = []
	var x := -50.0
	while x < map_size.x + 50.0:
		var clear := true
		for k: Vector2 in keep:
			if x > k.x - 3.0 and x < k.y + 3.0: clear = false
		if clear:
			for side: float in [cut.x + 0.9, cut.y - 0.9]:
				if rng.randf() < 0.4:
					var p := Vector3(x + rng.randf_range(-1.5, 1.5), -depth, side + rng.randf_range(-0.3, 0.3))
					if rng.randf() < 0.35: young.append(p)
					else: bush.append(p)
		x += 4.0
	_multi(plane_tree(34), young, "CuttingTrees", 0.5, 0.75)
	_multi(evergreen(54, 6), bush, "CuttingBushes", 0.3, 0.5)

func _multi(mesh: ArrayMesh, spots: Array[Vector3], label: String, s0: float, s1: float, scales: Array[float] = []) -> void:
	if spots.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for i: int in range(spots.size()):
		var s := scales[i] if i < scales.size() else rng.randf_range(s0, s1)
		multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s, s)), spots[i]))
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	b.add_child(node)
