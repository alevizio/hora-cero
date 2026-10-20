extends RefCounted
## The U-boat bunker in the Bassin a flot, December 1942: the western pens finished, a slab of concrete twelve
## metres high whose dark mouths open on the basin;
## the eastern pens still a building site, their piers standing open to the sky, girders and formwork going
## over them, scaffolding up their faces and a tower crane over the lot. Three Type VII U-boats are there tonight. The searchlight crew watches the basin
## and the site from the south-east corner of the roof.
## Everything above head height is a cut-away part: seen from the north it would hide the ground in front.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const WATER_Y := -2.3
const FOOT := -4.6            # where the walls go into the water
const TOP := 12.0             # roof
const MOUTH := 7.4            # head of the pen openings
const BUILT := 9.0            # how high the unfinished piers have got
const CUT := 2.6              # the cut-away line
const BACK := -42.0
const CONCRETE := Color(0.74, 0.73, 0.70)
const DARK := Color(0.10, 0.10, 0.10)
const STEEL := Color(0.30, 0.29, 0.28)
const TIMBER := Color(0.62, 0.56, 0.46)

var h: Node3D
var rng := RandomNumberGenerator.new()
var facade: float = 11.0
var finished: Array = []
var building: Array = []
var upper: Node3D

func _init(harbour: Node3D, seed_value: int) -> void:
	h = harbour
	rng.seed = seed_value

func build() -> void:
	var spec: Dictionary = h.sim.data.get("harbour", {})
	facade = float(spec.get("facadeZ", 11.0))
	var pens: Dictionary = spec.get("pens", {})
	finished = pens.get("finished", [[24.5, 26.3], [33.0, 34.8], [41.0, 42.8]])
	building = pens.get("building", [[49.4, 51.2], [57.8, 59.6]]).duplicate()
	# the building site goes on past the edge of the map
	var last: Array = building[building.size() - 1]
	var _bay: float = float(last[0]) - float(building[0][1]) + float(building[0][1]) - float(building[0][0])
	var step: float = float(building[1][0]) - float(building[0][0]) if building.size() > 1 else 8.4
	for i: int in range(3):
		building.append([float(last[0]) + step * (i + 1), float(last[1]) + step * (i + 1)])
	upper = h.node("BunkerUpper")
	_finished_block()
	_pen_interiors()
	_roof_furniture()
	_submarine()
	_building_site()
	_tower_crane()

# ---------------------------------------------------------------------------------------------------------------
# The finished pens
# ---------------------------------------------------------------------------------------------------------------
func _finished_block() -> void:
	var x0: float = float(finished[0][0])
	var x1: float = float(finished[finished.size() - 1][1])
	var width := x1 - x0
	# openings in facade coordinates (x from the west end, y from FOOT)
	var openings: Array = []
	for i: int in range(finished.size() - 1):
		var a: float = float(finished[i][1]) - x0
		var b: float = float(finished[i + 1][0]) - x0
		openings.append(Rect2(a, 0.0, b - a, MOUTH - FOOT))
	for part: int in range(2):
		var kit := Kit.new()
		var lo := FOOT if part == 0 else CUT
		var hi := CUT if part == 0 else TOP
		var holes: Array = []
		for o: Rect2 in openings:
			var top := minf(o.end.y, hi - FOOT) - (lo - FOOT)
			if top > 0.0: holes.append(Rect2(o.position.x, 0.0, o.size.x, top))
		# south facade over the basin
		kit.wall("mass", Vector3(x0, lo, facade), Vector3(1, 0, 0), width, hi - lo, holes, 0.0, lo, 0.0, CONCRETE * 0.62, CONCRETE, 0.0, 0.0)
		# west flank on the quay (ground level up), east flank above the first building pen
		var gy := maxf(lo, 0.0)
		if hi > gy:
			kit.wall("mass", Vector3(x0, gy, BACK), Vector3(0, 0, 1), facade - BACK, hi - gy, [], 3.1, gy, 0.0, CONCRETE * 0.6, CONCRETE, 0.0, 0.0)
			kit.wall("mass", Vector3(x1, gy, facade), Vector3(0, 0, -1), facade - BACK, hi - gy, [], 5.7, gy, 0.0, CONCRETE * 0.6, CONCRETE, 0.0, 0.0)
		h.commit(kit, h if part == 0 else upper, "BunkerFace%d" % part, true, part == 1)
	# the roof slab: a projecting edge and the top, in pieces
	var roof := Kit.new()
	roof.box("mass", Vector3((x0 + x1) * 0.5, TOP - 0.45, facade + 0.18), Vector3(width + 0.36, 0.9, 0.36), CONCRETE * 0.7, CONCRETE)
	roof.box("mass", Vector3(x0 - 0.18, TOP - 0.45, (facade + BACK) * 0.5), Vector3(0.36, 0.9, facade - BACK), CONCRETE * 0.7, CONCRETE)
	for z0: float in [BACK, -14.0]:
		var z1 := -14.0 if z0 == BACK else facade + 0.36
		roof.quad_m("mass", Vector3(x0 - 0.36, TOP, z1), Vector3(x1, TOP, z1), Vector3(x1, TOP, z0), Vector3(x0 - 0.36, TOP, z0), Vector2(0.3, 0.7), CONCRETE * 0.78, CONCRETE * 0.84)
	# low parapet and a drainage gutter along the south edge
	roof.box("mass", Vector3((x0 + x1) * 0.5, TOP + 0.3, facade + 0.2), Vector3(width + 0.3, 0.6, 0.3), CONCRETE * 0.75, CONCRETE)
	h.commit(roof, upper, "BunkerRoof", true, true)
	# pen numbers painted over the mouths, steel rungs up the pier noses, mooring bitts on the sills
	var marks := Kit.new()
	for i: int in range(finished.size()):
		var px := (float(finished[i][0]) + float(finished[i][1])) * 0.5
		var n := int((MOUTH + 3.0 - WATER_Y) / 0.32)
		for k: int in range(n):
			var y := WATER_Y + 0.3 + float(k) * 0.32
			marks.box("steel", Vector3(px, y, facade + 0.09), Vector3(0.44, 0.03, 0.03), STEEL, STEEL * 1.3)
			for s: float in [-0.22, 0.22]:
				marks.box("steel", Vector3(px + s, y, facade + 0.05), Vector3(0.03, 0.03, 0.1), STEEL, STEEL)
	h.commit(marks, upper, "Rungs", false, true)
	for i: int in range(finished.size() - 1):
		var mid := (float(finished[i][1]) + float(finished[i + 1][0])) * 0.5
		var label := Label3D.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
		label.font = h.stencil_font
		label.text = str(i + 1)
		label.font_size = 160
		label.pixel_size = 0.012
		label.modulate = Color(0.85, 0.84, 0.78, 0.55)
		label.shaded = true
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.position = Vector3(mid, MOUTH + 1.7, facade + 0.02)
		upper.add_child(label)

## Inside the finished pens: the pier walls, the ledges along them, the soffit of the roof and the dark back.
func _pen_interiors() -> void:
	for i: int in range(finished.size() - 1):
		var a: float = float(finished[i][1])
		var b: float = float(finished[i + 1][0])
		var kit := Kit.new()
		var deep := -24.0
		# side walls, facing into the pen
		kit.wall("mass", Vector3(a, FOOT, facade), Vector3(0, 0, -1), facade - deep, MOUTH - FOOT, [], 1.3, FOOT, 0.0, DARK, CONCRETE * 0.45, 0.0, 0.0)
		kit.wall("mass", Vector3(b, FOOT, deep), Vector3(0, 0, 1), facade - deep, MOUTH - FOOT, [], 2.9, FOOT, 0.0, DARK, CONCRETE * 0.45, 0.0, 0.0)
		# soffit, then the back of the pen lost in the dark
		kit.quad_m("mass", Vector3(a, MOUTH, deep), Vector3(b, MOUTH, deep), Vector3(b, MOUTH, facade), Vector3(a, MOUTH, facade), Vector2.ZERO, Kit.grey(0.08), Kit.grey(0.3))
		kit.quad_m("mass", Vector3(a, FOOT, deep), Vector3(b, FOOT, deep), Vector3(b, MOUTH, deep), Vector3(a, MOUTH, deep), Vector2.ZERO, Kit.grey(0.03), Kit.grey(0.05))
		# working ledges along both walls, a metre above half tide
		for side: float in [0.0, 1.0]:
			var x := a + 0.6 if side == 0.0 else b - 0.6
			kit.box("mass", Vector3(x, WATER_Y + 0.5, (facade + deep) * 0.5), Vector3(1.2, 1.0, facade - deep), DARK, CONCRETE * 0.4)
			for z: float in [8.0, 1.0, -6.0]:
				kit.lathe("steel", Vector3(x + (0.35 if side == 0.0 else -0.35), WATER_Y + 1.0, z), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.12, 0.4), Vector2(0.17, 0.44), Vector2(0.0, 0.46)]), 8, DARK, STEEL)
		h.commit(kit, h, "Pen%d" % (i + 1), false)
	# one caged work lamp burning deep in the second pen
	var at := Vector3((float(finished[1][1]) + float(finished[2][0])) * 0.5 - 2.0, MOUTH - 0.6, 2.0)
	h.add_lamp(at, Color(1.0, 0.74, 0.46), 1.6, 9.0, true, 0.7, 0.8)
	var lamp := Kit.new()
	lamp.beam("steel", at + Vector3(0, 0.1, 0), at + Vector3(0, 0.6, 0), 0.02, 0.02, STEEL, STEEL)
	lamp.lathe("bulb", at, PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.09, 0.0), Vector2(0.08, 0.12)]), 8)
	h.commit(lamp, h, "PenLamp", false)
	# and a work lamp bolted over the mouth of pen 2, throwing its light on the basin
	var over := Vector3((float(finished[1][1]) + float(finished[2][0])) * 0.5, MOUTH + 0.7, facade + 0.55)
	h.add_lamp(over + Vector3(0, -0.15, 0), Color(1.0, 0.76, 0.48), 2.6, 11.0, true, 1.0, 1.4)
	var wl := Kit.new()
	h._props.wall_lamp(wl, over + Vector3(0, 0.12, -0.45), 0.0, 0.45)
	wl.lathe("bulb", over + Vector3(0, 0.0, 0.0), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.1, -0.02), Vector2(0.1, 0.03)]), 8)
	h.commit(wl, upper, "MouthLamp", false)

## The flak position, the searchlight crew's sandbagged platform and the vents on the roof.
func _roof_furniture() -> void:
	var kit := Kit.new()
	# 2 cm flak on its pedestal in a concrete ring
	var flak := Vector3(29.0, TOP, 2.0)
	kit.lathe("mass", flak, PackedVector2Array([Vector2(2.2, 0.0), Vector2(2.2, 0.9), Vector2(1.9, 0.95), Vector2(1.9, 0.1)]), 20, CONCRETE * 0.6, CONCRETE)
	kit.lathe("steel", flak, PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.3, 0.6), Vector2(0.2, 0.8)]), 10, STEEL * 0.6, STEEL)
	kit.box("steel", flak + Vector3(0, 1.0, 0), Vector3(0.7, 0.4, 0.5), STEEL * 0.7, STEEL)
	kit.beam("steel", flak + Vector3(0.2, 1.1, 0), flak + Vector3(1.6, 2.4, -0.4), 0.06, 0.06, STEEL * 0.5, STEEL * 0.8)
	kit.box("steel", flak + Vector3(-0.1, 1.0, 0), Vector3(0.05, 0.6, 0.9), STEEL * 0.7, STEEL)
	# ventilation stacks and the stair head
	for p: Vector3 in [Vector3(27.0, TOP, -8.0), Vector3(35.5, TOP, -4.0), Vector3(39.0, TOP, -12.0)]:
		kit.box("mass", p + Vector3(0, 0.6, 0), Vector3(1.0, 1.2, 1.0), CONCRETE * 0.6, CONCRETE)
		kit.box("steel", p + Vector3(0, 1.3, 0), Vector3(1.2, 0.12, 1.2), STEEL, STEEL)
	kit.box("mass", Vector3(32.0, TOP + 1.3, -1.0), Vector3(3.0, 2.6, 2.4), CONCRETE * 0.6, CONCRETE)
	kit.quad_rect("trim", Vector3(31.0, TOP, 0.21), Vector3(32.0, TOP, 0.21), Vector3(32.0, TOP + 2.0, 0.21), Vector3(31.0, TOP, 0.21) + Vector3(0, 2.0, 0), Kit.trim_uv("door_plank"), Kit.grey(0.4), Kit.grey(0.6))
	h.commit(kit, upper, "RoofKit", true, true)
	# the searchlight platform: a ring of sandbags, the pedestal and the drum (its own node, it turns)
	var at := Vector3(41.6, TOP, 10.2)
	for guard: Dictionary in h.sim.data.guards:
		if str(guard.get("kind", "")) == "searchlight":
			at = Vector3(float(guard.route[0][0]) / 32.0, float(guard.get("elevation", TOP)), float(guard.route[0][1]) / 32.0)
	var bags := Kit.new()
	for i: int in range(16):
		var a := TAU * float(i) / 16.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.5: continue        # the crew's way in, from the north
		var p := at + Vector3(cos(a) * 1.9, 0, sin(a) * 1.9)
		h._props.sandbag(bags, p, -a + PI * 0.5, 0.7, 0.36, 0.22, Color(0.62, 0.6, 0.5))
		h._props.sandbag(bags, p + Vector3(0, 0.22, 0), -a + PI * 0.5 + 0.2, 0.66, 0.34, 0.2, Color(0.6, 0.58, 0.48))
	h.commit(bags, upper, "SearchlightBags", true, true)
	var rig := Node3D.new()
	rig.name = "SearchlightRig"
	rig.position = at + Vector3(0.9, 0, 0.0)
	upper.add_child(rig)
	var base := Kit.new()
	base.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.45, 0.0), Vector2(0.35, 0.1), Vector2(0.14, 0.2), Vector2(0.12, 0.85)]), 10, STEEL * 0.6, STEEL)
	for z: float in [-0.5, 0.5]:
		base.box("steel", Vector3(0, 1.1, z), Vector3(0.08, 0.6, 0.04), STEEL * 0.8, STEEL)
	h.commit(base, rig, "Yoke", true)
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.position = Vector3(0, 1.25, 0)
	# aim the drum down toward the ground about ten metres off
	tilt.rotation.z = -0.75
	rig.add_child(tilt)
	var drum := Kit.new()
	drum.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO))
	drum.lathe("steel", Vector3(0, -0.45, 0), PackedVector2Array([Vector2(0.18, 0.0), Vector2(0.4, 0.1), Vector2(0.42, 0.75), Vector2(0.46, 0.77), Vector2(0.46, 0.84), Vector2(0.4, 0.84)]), 16, STEEL * 0.6, STEEL)
	drum.disc("steel", Vector3(0, -0.45, 0), 0.18, 12, Rect2(0.2, 0.2, 0.02, 0.02), STEEL * 0.5, true)
	drum.pop()
	h.commit(drum, tilt, "Drum", true)
	var glass := Kit.new()
	glass.push(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO))
	glass.disc("bulb", Vector3(0, 0.38, 0), 0.4, 16, Rect2(0, 0, 0.01, 0.01))
	glass.pop()
	var lens: MeshInstance3D = h.commit(glass, tilt, "Lens", false)
	h.set_searchlight(rig, Vector3(0.42, 0, 0), lens)
	# the power runs up the bunker's west flank from the switch house to the roof
	var cable := Kit.new()
	var house_top := Vector3(24.0, 4.9, 2.6)
	h._props.wire(cable, house_top, Vector3(24.45, 6.0, 2.8), 0.1, 0.02, Color(0.12, 0.12, 0.12), 4)
	cable.beam("steel", Vector3(24.47, 6.0, 2.8), Vector3(24.47, TOP + 0.3, 2.8), 0.05, 0.05, Color(0.12, 0.12, 0.12), Color(0.15, 0.15, 0.15))
	# over the parapet and along the roof, lying on it, to the searchlight's sandbags
	h._props.wire(cable, Vector3(24.47, TOP + 0.3, 2.8), Vector3(24.9, TOP + 0.05, 2.8), 0.05, 0.02, Color(0.12, 0.12, 0.12), 4)
	var bend := Vector3(at.x - 1.6, TOP + 0.05, 2.8)
	cable.beam("steel", Vector3(24.9, TOP + 0.05, 2.8), bend, 0.045, 0.045, Color(0.1, 0.1, 0.1), Color(0.13, 0.13, 0.13))
	cable.beam("steel", bend, Vector3(at.x - 1.6, TOP + 0.05, at.z - 1.2), 0.045, 0.045, Color(0.1, 0.1, 0.1), Color(0.13, 0.13, 0.13))
	h.commit(cable, upper, "PowerCable", false, true)

# ---------------------------------------------------------------------------------------------------------------
# The Italian submarine in pen 1
# ---------------------------------------------------------------------------------------------------------------
## The U-boats (data harbour.uboats): Type VIIs of the Kriegsmarine, one moored in the basin, two up on keel blocks
## in the open pens for refit, one backed into pen 1. Each is a node of its own (local +Z is the bow) so the closing
## scene can sink them; the harbour keeps them in `uboats`.
func _submarine() -> void:
	for spec: Dictionary in h.sim.data.get("harbour", {}).get("uboats", []):
		var boat := uboat(spec)
		h.uboats[str(spec.get("id", ""))] = boat
		h.uboat_rest[str(spec.get("id", ""))] = boat.transform

func uboat(spec: Dictionary) -> Node3D:
	var afloat: bool = bool(spec.get("afloat", true))
	var length: float = float(spec.get("length", 10.0))
	var beam_w: float = float(spec.get("beam", 2.1))
	var n: Node3D = h.node("UBoat_" + str(spec.get("id", "")), Vector3(float(spec.x), 0.0, float(spec.z)), deg_to_rad(float(spec.get("yaw", 0.0))))
	var half := length * 0.5
	var rw := beam_w * 0.5
	var rh := rw * 0.92
	# afloat she rides with her casing a hand above the water; on the blocks her keel is a man's knee off the floor
	var cy := WATER_Y + 0.42 if afloat else rh + 0.55
	var grey := Color(0.36, 0.38, 0.39)
	var light := Color(0.52, 0.54, 0.55)
	var red := Color(0.36, 0.17, 0.12)
	# She is built in two pieces that meet where Rook's charge goes (along her, local z), so that in the closing
	# scene she can break her back there; each piece hangs on a pivot at the keel under the break. The keel blocks
	# and the shores stay where they are.
	var cut := 0.0
	for c: Dictionary in h.sim.data.get("charges", []):
		if str(c.get("boat", "")) == str(spec.get("id", "")):
			var w := Vector3(float(c.get("tx", c.x)) / 32.0, 0.0, float(c.get("ty", c.y)) / 32.0)
			cut = (n.transform.affine_inverse() * w).z
	cut = clampf(cut, -half * 0.6, half * 0.6)
	var pivot := Vector3(0.0, cy - rh, cut)
	var fore := Kit.new()
	var aft := Kit.new()
	var stay := Kit.new()
	for k: Kit in [fore, aft]: k.push(Transform3D(Basis.IDENTITY, -pivot))
	var part := func(z: float) -> Kit: return fore if z >= cut else aft
	# the pressure hull and saddle tanks: a fine stern, the tanks swelling amidships, a sharp bow that rises a little;
	# each piece closed off at the break by a torn, scorched bulkhead
	var tc := (cut + half) / length
	_uboat_hull(aft, 0.0, tc, false, true, length, rw, rh, cy, grey, red)
	_uboat_hull(fore, tc, 1.0, true, false, length, rw, rh, cy, grey, red)
	# the deck casing along the top, wooden slats
	var deck := cy + rh * 0.86
	var d0 := half * 0.1 - length * 0.39
	var d1 := half * 0.1 + length * 0.39
	if cut > d0: aft.box("planks", Vector3(0, deck, (d0 + cut) * 0.5), Vector3(rw * 0.9, 0.08, cut - d0), Color(0.3, 0.28, 0.25), Color(0.44, 0.41, 0.36), Vector2.ZERO, Kit.BEAM)
	if cut < d1: fore.box("planks", Vector3(0, deck, (cut + d1) * 0.5), Vector3(rw * 0.9, 0.08, d1 - cut), Color(0.3, 0.28, 0.25), Color(0.44, 0.41, 0.36), Vector2.ZERO, Kit.BEAM)
	# the conning tower, its bridge and the "winter garden" behind it, periscope standards
	var tz := -length * 0.04
	var tl := length * 0.24
	var tower: Kit = part.call(tz)
	tower.lathe("steel", Vector3(0, deck, tz), PackedVector2Array([Vector2(0.72 * rw, 0.0), Vector2(0.66 * rw, 1.3), Vector2(0.62 * rw, 1.55)]), 12, grey * 0.9, light)
	tower.box("steel", Vector3(0, deck + 0.8, tz), Vector3(rw * 1.05, 1.5, tl), grey * 0.85, light)
	tower.box("steel", Vector3(0, deck + 1.58, tz + tl * 0.08), Vector3(rw * 1.15, 0.12, tl * 1.05), grey, light * 1.05)
	tower.box("steel", Vector3(0, deck + 1.0, tz - tl * 0.62), Vector3(rw * 0.95, 0.12, tl * 0.4), grey, light)
	for dz: float in [0.0, -0.35]:
		tower.lathe("steel", Vector3(0, deck + 1.6, tz + dz), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.05, 1.2), Vector2(0.03, 1.4)]), 8, grey, light)
	# rails round the winter garden
	for sx: float in [-1.0, 1.0]:
		tower.beam("steel", Vector3(sx * rw * 0.45, deck + 1.35, tz - tl * 0.45), Vector3(sx * rw * 0.45, deck + 1.35, tz - tl * 0.85), 0.03, 0.03, grey, light)
	# the 8.8 cm deck gun forward of the tower
	var gun := Vector3(0, deck, tz + tl * 0.5 + length * 0.12)
	var gk: Kit = part.call(gun.z)
	gk.lathe("steel", gun, PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.12, 0.42)]), 8, grey, light)
	gk.box("steel", gun + Vector3(0, 0.52, -0.05), Vector3(0.36, 0.22, 0.42), grey * 0.9, light)
	gk.beam("steel", gun + Vector3(0, 0.58, 0.1), gun + Vector3(0, 0.66, 1.25), 0.06, 0.06, grey * 0.8, light)
	# the net cutter at the bow, the jumping wire to the tower (it parts when she breaks)
	fore.beam("steel", Vector3(0, deck + 0.15, half * 0.88), Vector3(0, deck + 0.55, half * 0.98), 0.03, 0.08, grey, light)
	h._props.wire(fore, Vector3(0, deck + 0.55, half * 0.97), Vector3(0, deck + 1.55, tz + tl * 0.5), 0.0, 0.012, Color(0.32, 0.32, 0.32), 2)
	h._props.wire(aft, Vector3(0, deck + 1.55, tz - tl * 0.5), Vector3(0, deck + 0.3, -half * 0.9), 0.0, 0.012, Color(0.32, 0.32, 0.32), 2)
	# rudder, stern planes and the twin screws (seen when she is up on the blocks)
	aft.box("steel", Vector3(0, cy - rh * 0.1, -half - 0.12), Vector3(0.05, rh * 1.3, 0.4), red, red * 1.2)
	aft.box("steel", Vector3(0, cy, -half + 0.25), Vector3(rw * 2.2, 0.04, 0.36), red, red * 1.2)
	for sx: float in [-1.0, 1.0]:
		var hub := Vector3(sx * rw * 0.42, cy - rh * 0.35, -half + 0.15)
		aft.beam("steel", hub + Vector3(0, 0, 0.6), hub, 0.06, 0.06, Color(0.5, 0.4, 0.25), Color(0.65, 0.52, 0.3))
		for k: int in range(3):
			var a := TAU * float(k) / 3.0 + sx * 0.4
			aft.beam("steel", hub, hub + Vector3(cos(a) * 0.32, sin(a) * 0.32, 0.03), 0.12, 0.02, Color(0.55, 0.42, 0.24), Color(0.72, 0.56, 0.3))
	# bow planes
	fore.box("steel", Vector3(0, cy + rh * 0.15, half * 0.78), Vector3(rw * 2.3, 0.04, 0.32), grey, light)
	if afloat and spec.has("lamp"):
		# a work lamp on a pole at the quay edge over her (on the harbour supply: it dies with the power)
		var pole := Vector3(float(spec.lamp[0]), 0.0, float(spec.lamp[1]))
		var kit2 := Kit.new()
		kit2.beam("steel", pole, pole + Vector3(0, 4.2, 0), 0.08, 0.08, STEEL * 0.6, STEEL)
		kit2.beam("steel", pole + Vector3(0, 4.15, 0), pole + Vector3(0, 4.15, -0.9), 0.05, 0.05, STEEL * 0.6, STEEL)
		kit2.lathe("bulb", pole + Vector3(0, 3.95, -0.9), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.11, -0.02), Vector2(0.1, 0.04)]), 8)
		h.commit(kit2, h, "UBoatLamp", true)
		h.add_lamp(pole + Vector3(0, 3.85, -0.9), Color(1.0, 0.78, 0.5), 2.4, 10.0, true, 1.0, 1.2)
	if afloat:
		# a couple of lines to the quay or the pen ledge (local x: +1 to starboard)
		var side := float(spec.get("lines", 1.0))
		for zz: float in [half * 0.6, -half * 0.6]:
			h._props.wire(part.call(zz), Vector3(side * rw * 0.6, deck + 0.1, zz), Vector3(side * (rw + 1.4), 0.15, zz + 0.8), 0.25, 0.025, Color(0.6, 0.55, 0.44), 6)
	else:
		# keel blocks under her and timber shores against both sides
		var count := int(length / 1.6)
		for k: int in range(count):
			var zz := lerpf(-half * 0.8, half * 0.75, float(k) / float(maxi(1, count - 1)))
			for y: float in [0.12, 0.36]:
				stay.box("planks", Vector3(0, y, zz), Vector3(rw * 0.9, 0.22, 0.4), TIMBER * 0.55, TIMBER * 0.8, Vector2(float(k) * 0.3, y), Kit.BEAM)
			if k % 2 == 0:
				for sx: float in [-1.0, 1.0]:
					stay.beam("planks", Vector3(sx * (rw + 0.18), 0.0, zz), Vector3(sx * rw * 0.82, cy + 0.15, zz), 0.14, 0.14, TIMBER * 0.5, TIMBER * 0.8)
		h.commit(stay, n, "Blocks", true)
	for pair: Array in [["Aft", aft], ["Fore", fore]]:
		var piece := Node3D.new()
		piece.name = str(pair[0])
		piece.position = pivot
		piece.set_meta("pivot", pivot)
		n.add_child(piece)
		var kit: Kit = pair[1]
		kit.pop()
		h.commit(kit, piece, "Hull", true)
	return n

## One piece of a U-boat's hull, from `t0` to `t1` along her (0 the stern, 1 the bow), with a torn bulkhead closing
## the end at the break (`cap_start` at t0, `cap_end` at t1).
func _uboat_hull(kit: Kit, t0: float, t1: float, cap_start: bool, cap_end: bool, length: float, rw: float, rh: float, cy: float, grey: Color, red: Color) -> void:
	var half := length * 0.5
	var columns := 17
	var steps := maxi(4, int(round(26.0 * (t1 - t0))))
	var ts: Array[float] = []
	if cap_start: ts.append(t0)
	for i: int in range(steps + 1): ts.append(lerpf(t0, t1, float(i) / float(steps)))
	if cap_end: ts.append(t1)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for r: int in range(ts.size()):
		var t: float = ts[r]
		var capped: bool = (cap_start and r == 0) or (cap_end and r == ts.size() - 1)
		var z := lerpf(-half, half, t)
		var g := pow(sin(PI * clampf(0.02 + t * 0.965, 0.0, 1.0)), 0.62 if t > 0.5 else 0.5)
		g *= 1.0 + 0.1 * exp(-pow((t - 0.5) / 0.2, 2.0))
		var lift := 0.22 * smoothstep(0.82, 1.0, t)
		for j: int in range(columns):
			var ang := TAU * float(j) / float(columns - 1)
			# the torn bulkhead: the ring drawn in to a ragged point a little inside the hull
			var k: float = 0.0 if not capped else 1.0
			var p := Vector3(cos(ang) * rw * g * (1.0 - k), cy + lift + sin(ang) * rh * g * (1.0 - k), z + (0.08 * sin(ang * 5.0) * k if capped else 0.0))
			pts.append(p)
			uvs.append(Vector2(z * Kit.UV_M, ang * 0.4))
			var c := red if p.y < cy - rh * 0.35 else grey * (0.85 + 0.25 * clampf(sin(ang), 0.0, 1.0))
			cols.append(Color(0.06, 0.055, 0.05) if capped else c)
	kit.patch("hull", ts.size(), columns, pts, uvs, cols, true, false)

# ---------------------------------------------------------------------------------------------------------------
# The building site: unfinished pens
# ---------------------------------------------------------------------------------------------------------------
func _building_site() -> void:
	var east: float = float(finished[finished.size() - 1][1])
	for i: int in range(building.size()):
		var x0: float = float(building[i][0])
		var x1: float = float(building[i][1])
		var top := BUILT if i < 2 else BUILT - 1.4 * float(i - 1)
		for part: int in range(2):
			var kit := Kit.new()
			var lo := 0.0 if part == 0 else CUT
			var hi := minf(CUT, top) if part == 0 else top
			if hi <= lo: continue
			var c := Vector3((x0 + x1) * 0.5, (lo + hi) * 0.5, (facade + BACK) * 0.5)
			kit.box("mass", c, Vector3(x1 - x0, hi - lo, facade - BACK), CONCRETE * (0.62 if part == 0 else 0.8), CONCRETE, Vector2(float(i) * 0.37, 0.0), Kit.UPRIGHT)
			if part == 1:
				_starter_bars(kit, x0, x1, top)
			h.commit(kit, h if part == 0 else upper, "Pier%d_%d" % [i + 3, part], true, part == 1)
	# girders and formwork over the pens, the back of the poured roof, scaffolding up the pier faces
	var edges: Array[float] = [east]
	for p: Array in building: edges.append(float(p[0]))
	var girders := Kit.new()
	for i: int in range(edges.size() - 1):
		var x0: float = edges[i] if i == 0 else float(building[i - 1][1])
		var x1: float = float(building[i][0])
		var z := -22.0
		while z < 3.5:
			_i_beam(girders, Vector3(x0, BUILT - 0.3, z), Vector3(x1, BUILT - 0.3, z))
			z += 2.5
		# formwork decking already laid on the northern girders: the next pour
		girders.quad_m("planks", Vector3(x0, BUILT, -9.0), Vector3(x1, BUILT, -9.0), Vector3(x1, BUILT, -22.0), Vector3(x0, BUILT, -22.0), Vector2(float(i), 0.0), TIMBER * 0.8, TIMBER)
		girders.quad_m("planks", Vector3(x0, BUILT - 0.02, -22.0), Vector3(x1, BUILT - 0.02, -22.0), Vector3(x1, BUILT - 0.02, -9.0), Vector3(x0, BUILT - 0.02, -9.0), Vector2(float(i), 0.3), Kit.grey(0.15), Kit.grey(0.2))
		# timber end wall of the formwork, facing the camera's side of the pen
		girders.wall("planks", Vector3(x0, 0.0, -9.0), Vector3(1, 0, 0), x1 - x0, BUILT, [], float(i) * 2.1, 0.0, 0.0, TIMBER * 0.35, TIMBER * 0.7)
	h.commit(girders, upper, "Girders", true, true)
	# scaffolds on the faces nobody needs to reach (the charges go on the others)
	for i: int in range(mini(3, building.size())):
		var face: float = float(building[i][1])
		var out: float = 1.0
		for item: Dictionary in h.sim.data.obstacles:
			if str(item.get("kind", "")) == "scaffold" and absf(float(item.x) / 32.0 - face) < 0.1:
				out = float(item.get("out", 1.0))
		_scaffold(face, 1.0, out, 6.0, float(i) * 7.0)
	# on the pen floors: formwork panels, a rebar cage, timber stacks, the narrow-gauge track and its skips
	_pen_floor()

## Starter bars sticking up out of a pier waiting for the next lift.
func _starter_bars(kit: Kit, x0: float, x1: float, top: float) -> void:
	for side: float in [x0 + 0.25, x1 - 0.25]:
		var z := facade - 0.3
		while z > -8.0:
			var hgt := 0.9 + rng.randf() * 0.5
			kit.beam("steel", Vector3(side, top, z), Vector3(side + rng.randf_range(-0.04, 0.04), top + hgt, z + rng.randf_range(-0.04, 0.04)), 0.028, 0.028, Color(0.32, 0.22, 0.16), Color(0.42, 0.28, 0.2))
			z -= 0.45

func _i_beam(kit: Kit, a: Vector3, b: Vector3) -> void:
	var d := 0.5
	kit.beam("steel", a + Vector3(0, d * 0.5, 0), b + Vector3(0, d * 0.5, 0), 0.3, 0.04, STEEL, STEEL * 1.2, Vector2.ZERO, false)
	kit.beam("steel", a - Vector3(0, d * 0.5, 0), b - Vector3(0, d * 0.5, 0), 0.3, 0.04, STEEL * 0.8, STEEL, Vector2.ZERO, false)
	kit.beam("steel", a, b, 0.03, d, STEEL * 0.7, STEEL, Vector2.ZERO, false)

## Timber scaffolding up a pier face at x (dir: which way the face looks), from the facade back `bays` bays.
func _scaffold(x: float, dir: float, out: float, bays: float, seed_offset: float) -> void:
	var kit := Kit.new()
	var inner := x + dir * 0.35
	var outer := x + dir * (0.35 + out)
	var levels: Array[float] = [2.2, 4.4, 6.6, 8.6]
	var z := facade - 0.3
	var last_z := facade - 0.3 - 2.2 * (bays - 1.0)
	var col := TIMBER * (0.85 + 0.1 * sin(seed_offset))
	while z >= last_z - 0.01:
		for sx: float in [inner, outer]:
			kit.beam("planks", Vector3(sx, 0.0, z), Vector3(sx, levels[3] + 1.0, z), 0.1, 0.1, col * 0.6, col, Vector2(rng.randf(), rng.randf()))
		for y: float in levels:
			kit.beam("planks", Vector3(inner, y, z), Vector3(outer, y, z), 0.08, 0.08, col * 0.7, col, Vector2(rng.randf(), rng.randf()))
		z -= 2.2
	for y: float in levels:
		for sx: float in [inner, outer]:
			kit.beam("planks", Vector3(sx, y + 0.08, facade - 0.3), Vector3(sx, y + 0.08, last_z), 0.08, 0.08, col * 0.7, col, Vector2(rng.randf(), rng.randf()))
		# plank deck and the guard rail
		kit.box("planks", Vector3((inner + outer) * 0.5, y + 0.15, (facade - 0.3 + last_z) * 0.5), Vector3(absf(outer - inner) - 0.1, 0.05, facade - 0.3 - last_z), col * 0.6, col)
		kit.beam("planks", Vector3(outer, y + 1.0, facade - 0.3), Vector3(outer, y + 1.0, last_z), 0.05, 0.05, col * 0.8, col)
	# diagonal bracing on the outer face
	z = facade - 0.3
	var flip := 1.0
	while z - 2.2 >= last_z - 0.01:
		kit.beam("planks", Vector3(outer, 0.3 if flip > 0.0 else 4.4, z), Vector3(outer, 4.4 if flip > 0.0 else 8.6, z - 2.2), 0.06, 0.06, col * 0.7, col)
		z -= 2.2
		flip = -flip
	# ladders between the levels
	for k: int in range(levels.size() - 1):
		var lz := facade - 1.0 - 2.2 * float(k % 2)
		h._props.ladder(kit, Vector3((inner + outer) * 0.5, levels[k] + 0.18, lz), Vector3((inner + outer) * 0.5, levels[k + 1] + 0.9, lz - 0.6), 0.45, col)
	h._props.ladder(kit, Vector3((inner + outer) * 0.5, 0.0, facade - 1.6), Vector3((inner + outer) * 0.5, levels[0] + 0.9, facade - 2.3), 0.45, col)
	h.commit(kit, upper, "Scaffold", true, true)

func _pen_floor() -> void:
	var kit := Kit.new()
	var props: RefCounted = h._props
	var skips: Array[Vector3] = []
	# rebar cage being tied in pen 3 (its footprint is the mission's "rebar" obstacle), timber stacks, shuttering
	# panels leaning on the piers, the skips: each where its obstacle is
	for item: Dictionary in h.sim.data.obstacles:
		var r: Rect2 = h.sim.rect_of(item)
		r = Rect2(r.position / 32.0, r.size / 32.0)
		match str(item.get("kind", "")):
			"rebar":
				var hgt := 1.6
				var bx := r.position.x
				while bx <= r.end.x + 0.01:
					for y: float in [0.05, hgt]:
						kit.beam("steel", Vector3(bx, y, r.position.y), Vector3(bx, y, r.end.y), 0.025, 0.025, Color(0.3, 0.2, 0.15), Color(0.42, 0.28, 0.2))
					kit.beam("steel", Vector3(bx, 0.0, r.position.y), Vector3(bx, hgt, r.position.y), 0.025, 0.025, Color(0.3, 0.2, 0.15), Color(0.42, 0.28, 0.2))
					kit.beam("steel", Vector3(bx, 0.0, r.end.y), Vector3(bx, hgt, r.end.y), 0.025, 0.025, Color(0.3, 0.2, 0.15), Color(0.42, 0.28, 0.2))
					bx += 0.25
				for z: float in [r.position.y, r.end.y]:
					var y := 0.3
					while y < hgt:
						kit.beam("steel", Vector3(r.position.x, y, z), Vector3(r.end.x, y, z), 0.02, 0.02, Color(0.3, 0.2, 0.15), Color(0.42, 0.28, 0.2))
						y += 0.3
			"timber":
				var layers := 6
				for k: int in range(layers):
					var y := 0.06 + float(k) * 0.16
					if k % 2 == 0:
						var n := int(r.size.y / 0.24)
						for j: int in range(n):
							var z := r.position.y + (float(j) + 0.5) * r.size.y / float(n)
							kit.box("planks", Vector3(r.get_center().x + props.jitter(0.08), y, z), Vector3(r.size.x - 0.1, 0.14, 0.2), TIMBER * 0.7, TIMBER, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
					else:
						for xx: float in [r.position.x + 0.3, r.get_center().x, r.end.x - 0.3]:
							kit.box("planks", Vector3(xx, y, r.get_center().y), Vector3(0.12, 0.12, r.size.y), TIMBER * 0.6, TIMBER * 0.85, Vector2(rng.randf(), rng.randf()), Kit.BEAM)
			"formwork":
				# lean -1: the pier is to the east and the panels lean over onto it
				var lean: float = float(item.get("lean", -1))
				var at := Vector3(r.position.x + 0.1 if lean < 0.0 else r.end.x - 0.05, 0.0, r.position.y)
				for k: int in range(maxi(1, int(round(r.size.y / 1.25)))):
					var z := at.z + float(k) * 1.25
					kit.quad_m("planks", Vector3(at.x, 0.02, z), Vector3(at.x, 0.02, z + 1.2), Vector3(at.x - lean * 0.45, 2.4, z + 1.2), Vector3(at.x - lean * 0.45, 2.4, z), Vector2(rng.randf(), 0.0), TIMBER * 0.6, TIMBER)
					kit.quad_m("planks", Vector3(at.x - lean * 0.03, 0.02, z + 1.2), Vector3(at.x - lean * 0.03, 0.02, z), Vector3(at.x - lean * 0.48, 2.4, z), Vector3(at.x - lean * 0.48, 2.4, z + 1.2), Vector2(rng.randf(), 0.0), TIMBER * 0.4, TIMBER * 0.7)
			"skip":
				skips.append(Vector3(r.get_center().x, 0.0, r.get_center().y))
	h.commit(kit, h, "SiteFloor", true)
	var track := Kit.new()
	var tz := 11.7
	for s: float in [-0.3, 0.3]:
		track.box("steel", Vector3(55.0, 0.05, tz + s), Vector3(26.0, 0.06, 0.04), Color(0.25, 0.22, 0.2), Color(0.45, 0.42, 0.4))
	var x := 42.2
	while x < 68.0:
		track.box("planks", Vector3(x, 0.025, tz), Vector3(0.14, 0.05, 0.9), TIMBER * 0.4, TIMBER * 0.6, Vector2(rng.randf(), rng.randf()))
		x += 0.6
	for at: Vector3 in skips:
		_skip(track, at)
	h.commit(track, h, "Decauville", true)

## A tipping skip on the narrow-gauge track, half full of concrete gone off.
func _skip(kit: Kit, at: Vector3) -> void:
	kit.box("steel", at + Vector3(0, 0.25, 0), Vector3(1.2, 0.12, 0.7), STEEL * 0.6, STEEL)
	for dx: float in [-0.4, 0.4]:
		for s: float in [-0.3, 0.3]:
			kit.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(dx, 0.18, s)))
			kit.lathe("steel", Vector3(0, -0.03, 0), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.17, 0.06)]), 10, STEEL * 0.5, STEEL * 0.7)
			kit.pop()
	var prof := PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.45, 0.2), Vector2(0.55, 0.55), Vector2(0.52, 0.6)])
	kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 0.75)), at + Vector3(-0.5, 0.82, 0)))
	kit.lathe("steel", Vector3.ZERO, prof, 12, Color(0.35, 0.3, 0.25), Color(0.5, 0.42, 0.34))
	kit.pop()

# ---------------------------------------------------------------------------------------------------------------
# Tower crane over the site
# ---------------------------------------------------------------------------------------------------------------
func _tower_crane() -> void:
	var base := Vector3(58.9, 0.0, 13.2)
	for item: Dictionary in h.sim.data.obstacles:
		if str(item.get("kind", "")) == "mast":
			var r: Rect2 = h.sim.rect_of(item)
			base = Vector3(r.get_center().x / 32.0, 0.0, r.get_center().y / 32.0)
	var kit := Kit.new()
	var paint := Color(0.45, 0.36, 0.22)
	var height := 17.5
	var w := 0.6
	# ballasted base, the lattice mast
	kit.box("mass", base + Vector3(0, 0.3, 0), Vector3(2.6, 0.6, 2.6), CONCRETE * 0.6, CONCRETE * 0.9)
	var corners: Array[Vector3] = [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
	for c: Vector3 in corners:
		kit.beam("steel", base + c + Vector3(0, 0.6, 0), base + c + Vector3(0, height, 0), 0.1, 0.1, paint * 0.6, paint, Vector2.ZERO, false)
	var y := 0.6
	var flip := false
	while y < height - 0.1:
		var y2 := minf(y + 1.2, height)
		for i: int in range(4):
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			if flip: kit.beam("steel", base + a + Vector3(0, y, 0), base + b + Vector3(0, y2, 0), 0.05, 0.05, paint * 0.6, paint, Vector2.ZERO, false)
			else: kit.beam("steel", base + b + Vector3(0, y, 0), base + a + Vector3(0, y2, 0), 0.05, 0.05, paint * 0.6, paint, Vector2.ZERO, false)
			kit.beam("steel", base + a + Vector3(0, y2, 0), base + b + Vector3(0, y2, 0), 0.05, 0.05, paint * 0.6, paint, Vector2.ZERO, false)
		flip = not flip
		y = y2
	# slewing ring, the cab, the jib reaching north-west over the pens and the counter-jib with its weights
	var top := base + Vector3(0, height, 0)
	kit.box("steel", top + Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 1.6), paint * 0.6, paint)
	kit.box("steel", top + Vector3(0.9, 0.9, 0.9), Vector3(1.1, 1.4, 1.1), paint * 0.5, paint * 0.9)
	var dir := Vector3(-0.82, 0, -0.57).normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	var root := top + Vector3(0, 0.6, 0)
	var tip := root + dir * 19.0
	var back := root - dir * 6.0
	for s: float in [-0.35, 0.35]:
		kit.beam("steel", root + side * s, tip + side * s * 0.4, 0.07, 0.07, paint * 0.6, paint, Vector2.ZERO, false)
	kit.beam("steel", root + Vector3(0, 0.8, 0), tip + Vector3(0, 0.2, 0), 0.07, 0.07, paint * 0.6, paint, Vector2.ZERO, false)
	var n := 16
	for i: int in range(n):
		var p0 := root.lerp(tip, float(i) / float(n))
		var p1 := root.lerp(tip, float(i + 1) / float(n))
		var t0 := 1.0 - 0.6 * float(i) / float(n)
		var t1 := 1.0 - 0.6 * float(i + 1) / float(n)
		kit.beam("steel", p0 + side * 0.35 * t0, p1 + Vector3(0, 0.8 * t1, 0), 0.04, 0.04, paint * 0.6, paint, Vector2.ZERO, false)
		kit.beam("steel", p0 - side * 0.35 * t0, p1 + Vector3(0, 0.8 * t1, 0), 0.04, 0.04, paint * 0.6, paint, Vector2.ZERO, false)
		kit.beam("steel", p1 + side * 0.35 * t1, p1 - side * 0.35 * t1, 0.04, 0.04, paint * 0.6, paint, Vector2.ZERO, false)
	for s: float in [-0.35, 0.35]:
		kit.beam("steel", root + side * s, back + side * s, 0.08, 0.08, paint * 0.6, paint, Vector2.ZERO, false)
	kit.box("mass", back + Vector3(0, -0.3, 0), Vector3(1.4, 1.6, 1.2), CONCRETE * 0.5, CONCRETE * 0.8)
	# the peak, the stays down to both ends
	var peak := top + Vector3(0, 4.2, 0)
	kit.beam("steel", top + Vector3(-0.3, 0.5, -0.3), peak, 0.08, 0.08, paint * 0.6, paint, Vector2.ZERO, false)
	kit.beam("steel", top + Vector3(0.3, 0.5, 0.3), peak, 0.08, 0.08, paint * 0.6, paint, Vector2.ZERO, false)
	h._props.wire(kit, peak, tip + Vector3(0, 0.8 * 0.4, 0), 0.05, 0.02, Color(0.2, 0.2, 0.2), 6)
	h._props.wire(kit, peak, back, 0.05, 0.02, Color(0.2, 0.2, 0.2), 4)
	# trolley out over pen 4 with the hook and a concrete bucket hanging still
	var trolley := root.lerp(tip, 0.62)
	kit.box("steel", trolley + Vector3(0, -0.2, 0), Vector3(0.6, 0.3, 0.6), paint * 0.5, paint * 0.8)
	var hook := Vector3(trolley.x, 6.5, trolley.z)
	h._props.wire(kit, trolley, hook, 0.0, 0.015, Color(0.2, 0.2, 0.2), 2)
	kit.lathe("steel", hook - Vector3(0, 1.4, 0), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.55, 0.9), Vector2(0.6, 1.25), Vector2(0.55, 1.3)]), 12, Color(0.35, 0.33, 0.3), Color(0.5, 0.48, 0.44))
	h.commit(kit, upper, "TowerCrane", true, true)
	h.add_beacon(peak + Vector3(0, 0.25, 0))
	h.add_beacon(tip + Vector3(0, 0.5, 0))
