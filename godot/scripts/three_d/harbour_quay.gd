extends RefCounted
## The river quay: granite coping along the edge with its bollards, rings and ladders, the crane rails and the
## quay line let into the setts, two portal cranes (one working the ship's forward hold, one parked), the
## harbour lamps, the transformer house that feeds the lamps, the searchlight and the siren (the mission's
## optional "radio": its main switch is the thing to pull), and the stone steps down to the water where the
## canoe waits.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Site = preload("res://scripts/three_d/structures_site.gd")
const WATER_Y := -2.3
const IRON := Color(0.22, 0.22, 0.22)
const CRANE := Color(0.36, 0.38, 0.34)        # weathered grey-green paint
const BRICK := Color(0.82, 0.78, 0.74)
const LAMP_WARM := Color(1.0, 0.70, 0.40)

var h: Node3D
var site: Site
var rng := RandomNumberGenerator.new()
var edge: float = 13.0
var rails: Array = [15.3, 20.1]
var track: float = 17.7

func _init(harbour: Node3D, s: Site, seed_value: int) -> void:
	h = harbour
	site = s
	rng.seed = seed_value

func build() -> void:
	var spec: Dictionary = h.sim.data.get("harbour", {})
	edge = float(spec.get("quayEdge", 13.0))
	rails = spec.get("craneRails", [15.3, 20.1])
	track = float(spec.get("quayTrack", 17.7))
	_coping()
	_rails()
	var cranes: Array = spec.get("cranes", [])
	for i: int in range(cranes.size()):
		var crane: Dictionary = cranes[i]
		_portal_crane(float(crane.z0), float(crane.z1), float(crane.get("jib", 180.0)), i == 0)
	_lamps()
	_switch_house()
	_steps_and_canoe()

# ---------------------------------------------------------------------------------------------------------------
# Quay edge
# ---------------------------------------------------------------------------------------------------------------
func _coping() -> void:
	for piece: int in range(6):
		var z0 := -40.0 + float(piece) * 20.0
		var kit := Kit.new()
		var z := z0
		while z < z0 + 20.0:
			var l := rng.randf_range(1.0, 1.5)
			var g := rng.randf_range(0.78, 0.96)
			kit.box("granite", Vector3(edge + 0.32, 0.03, z + l * 0.5), Vector3(0.66, 0.1, l - 0.02), Color(0.5, 0.5, 0.48) * g, Color(0.86, 0.85, 0.82) * g, Vector2(rng.randf(), rng.randf()))
			z += l
		# bollards, mooring rings and ladders down the wall
		for bz: float in [-6.0, 2.0, 9.5, 18.0, 26.0, 34.0, 38.5, 44.0, 46.5, 52.0, 58.0, 63.0, 70.5]:
			if bz < z0 or bz >= z0 + 20.0: continue
			kit.lathe("steel", Vector3(edge + 0.75, 0.0, bz), PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.2, 0.12), Vector2(0.16, 0.45), Vector2(0.22, 0.52), Vector2(0.26, 0.6), Vector2(0.18, 0.66), Vector2(0.0, 0.68)]), 12, IRON * 0.6, IRON * 1.3)
		for rz: float in [-2.0, 5.5, 13.0, 22.0, 30.0, 40.0, 49.0, 56.0, 66.0]:
			if rz < z0 or rz >= z0 + 20.0: continue
			kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(edge - 0.06, -0.7, rz)))
			kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.22, -0.02), Vector2(0.25, 0.0), Vector2(0.22, 0.02)]), 12, IRON * 0.5, IRON)
			kit.pop()
		for lz: float in [-10.0, 21.0, 46.0, 61.0]:
			if lz < z0 or lz >= z0 + 20.0: continue
			for s: float in [-0.22, 0.22]:
				kit.beam("steel", Vector3(edge - 0.08, WATER_Y - 1.0, lz + s), Vector3(edge - 0.08, 0.35, lz + s), 0.04, 0.04, IRON * 0.5, IRON)
			var y := WATER_Y - 0.8
			while y < 0.1:
				kit.beam("steel", Vector3(edge - 0.1, y, lz - 0.22), Vector3(edge - 0.1, y, lz + 0.22), 0.03, 0.03, IRON * 0.5, IRON)
				y += 0.3
		h.commit(kit, h, "Coping%d" % piece, true)

## Crane rails and the quay line, flush with the setts: a polished head in a dark groove.
func _rails() -> void:
	for piece: int in range(4):
		var z0 := -40.0 + float(piece) * 30.0
		var z1 := z0 + 30.0
		var kit := Kit.new()
		var lines: Array[float] = []
		for x: float in rails: lines.append(float(x))
		lines.append(track - 0.72)
		lines.append(track + 0.72)
		for x: float in lines:
			kit.box("steel", Vector3(x, 0.004, (z0 + z1) * 0.5), Vector3(0.16, 0.012, z1 - z0), Color(0.05, 0.05, 0.05), Color(0.06, 0.06, 0.06))
			kit.box("steel", Vector3(x + 0.03, 0.012, (z0 + z1) * 0.5), Vector3(0.06, 0.014, z1 - z0), Color(0.55, 0.55, 0.56), Color(0.62, 0.62, 0.64))
		h.commit(kit, h, "QuayRails%d" % piece, false)

# ---------------------------------------------------------------------------------------------------------------
# Portal cranes
# ---------------------------------------------------------------------------------------------------------------
## A level-luffing portal crane straddling the quay line: four legs on bogies, the portal girders, the slewing
## house, an A-frame and a lattice jib. `slew` is the jib's direction in degrees (0 = east, 180 = west); the
## working crane has its hook down over the ship's hatch with a sling of cases on it.
func _portal_crane(z0: float, z1: float, slew: float, working: bool) -> void:
	var xw: float = float(rails[0])
	var xe: float = float(rails[1])
	var top := 6.3
	var cz := (z0 + z1) * 0.5
	var cxm := (xw + xe) * 0.5
	var base := Kit.new()
	for x: float in [xw, xe]:
		for z: float in [z0, z1]:
			# bogie with two wheels on the rail, then the tapered leg
			base.box("steel", Vector3(x, 0.32, z), Vector3(0.5, 0.42, 1.5), CRANE * 0.5, CRANE * 0.8)
			for dz: float in [-0.45, 0.45]:
				base.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.22, z + dz)))
				base.lathe("steel", Vector3(0, -0.12, 0), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.22, 0.24)]), 10, IRON * 0.6, IRON)
				base.pop()
			var lean := Vector3(signf(cxm - x) * 0.25, 0, signf(cz - z) * 0.2)
			base.beam("steel", Vector3(x, 0.5, z), Vector3(x, top, z) + lean, 0.42, 0.42, CRANE * 0.55, CRANE, Vector2.ZERO, false)
	# portal: side girders along the rails, cross girders over the track, knee braces up in the corners
	for x: float in [xw, xe]:
		var lean := signf(cxm - x) * 0.25
		base.box("steel", Vector3(x + lean, top + 0.35, cz), Vector3(0.5, 0.7, z1 - z0 + 0.4), CRANE * 0.6, CRANE)
		for z: float in [z0, z1]:
			var dz := signf(cz - z)
			base.beam("steel", Vector3(x + lean * 0.6, top - 1.6, z + dz * 0.15), Vector3(x + lean, top, z + dz * 1.2), 0.18, 0.18, CRANE * 0.6, CRANE, Vector2.ZERO, false)
	for z: float in [z0, z1]:
		var dz := signf(cz - z) * 0.2
		base.box("steel", Vector3(cxm, top + 0.35, z + dz), Vector3(xe - xw - 0.1, 0.7, 0.5), CRANE * 0.6, CRANE)
		base.beam("steel", Vector3(xw + 0.25, top - 1.4, z + dz), Vector3(xw + 1.4, top, z + dz), 0.18, 0.18, CRANE * 0.6, CRANE, Vector2.ZERO, false)
		base.beam("steel", Vector3(xe - 0.25, top - 1.4, z + dz), Vector3(xe - 1.4, top, z + dz), 0.18, 0.18, CRANE * 0.6, CRANE, Vector2.ZERO, false)
	# a ladder up the landward leg
	h._props.ladder(base, Vector3(xe + 0.35, 0.0, z1 - 0.2), Vector3(xe + 0.12, top, z1 - 0.3), 0.42, CRANE)
	h.commit(base, h, "CranePortal", true, true)
	# a lamp under the portal lights the line and the cases waiting there
	h.add_lamp(Vector3(cxm, top - 0.25, cz), LAMP_WARM, 2.0, 8.0, true, 0.8, 1.0)
	var lk := Kit.new()
	lk.lathe("steel", Vector3(cxm, top - 0.1, cz), PackedVector2Array([Vector2(0.32, -0.16), Vector2(0.12, 0.0), Vector2(0.04, 0.06)]), 12, Color(0.25, 0.28, 0.25), Color(0.35, 0.38, 0.35))
	lk.lathe("bulb", Vector3(cxm, top - 0.22, cz), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.1, -0.02), Vector2(0.12, 0.04)]), 10)
	h.commit(lk, h, "PortalLamp", false)
	# the slewing upper works
	var up := Kit.new()
	var ring := Vector3(cxm, top + 0.7, cz)
	up.lathe("steel", ring, PackedVector2Array([Vector2(1.5, 0.0), Vector2(1.5, 0.3), Vector2(1.3, 0.4)]), 16, CRANE * 0.5, CRANE * 0.8)
	var yaw := deg_to_rad(-slew)
	var dir := Vector3(cos(deg_to_rad(slew)), 0, sin(deg_to_rad(slew)))
	var side := Vector3(-dir.z, 0, dir.x)
	up.push(Transform3D(Basis(Vector3.UP, yaw), ring + Vector3(0, 0.4, 0)))
	# machinery house with the driver's cab at its front, the counterweight behind
	up.box("steel", Vector3(-0.6, 1.3, 0), Vector3(3.6, 2.6, 2.6), CRANE * 0.6, CRANE)
	up.quad_m("corrugated", Vector3(-2.45, 2.6, 1.35), Vector3(1.25, 2.6, 1.35), Vector3(1.25, 2.9, 0.0), Vector3(-2.45, 2.9, 0.0), Vector2.ZERO, Kit.grey(0.6), Kit.grey(0.8))
	up.quad_m("corrugated", Vector3(1.25, 2.6, -1.35), Vector3(-2.45, 2.6, -1.35), Vector3(-2.45, 2.9, 0.0), Vector3(1.25, 2.9, 0.0), Vector2.ZERO, Kit.grey(0.6), Kit.grey(0.8))
	up.box("steel", Vector3(1.6, 1.1, 0.7), Vector3(1.2, 2.2, 1.1), CRANE * 0.55, CRANE * 0.95)
	up.quad4("window", Vector3(2.21, 1.3, 1.2), Vector3(2.21, 1.3, 0.2), Vector3(2.21, 2.0, 0.2), Vector3(2.21, 2.0, 1.2), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.03, 0.035, 0.04), Color(0.03, 0.035, 0.04), Color(0.05, 0.06, 0.07), Color(0.05, 0.06, 0.07))
	up.box("mass", Vector3(-2.7, 0.8, 0), Vector3(0.9, 1.6, 2.2), Color(0.45, 0.45, 0.42), Color(0.6, 0.6, 0.56))
	# A-frame
	var apex := Vector3(-0.4, 6.0, 0)
	for s: float in [-1.0, 1.0]:
		up.beam("steel", Vector3(0.9, 2.6, s * 1.1), apex + Vector3(0, 0, s * 0.3), 0.22, 0.22, CRANE * 0.6, CRANE, Vector2.ZERO, false)
		up.beam("steel", Vector3(-1.9, 2.6, s * 1.1), apex + Vector3(0, 0, s * 0.3), 0.18, 0.18, CRANE * 0.6, CRANE, Vector2.ZERO, false)
	up.pop()
	# the jib, luffed up: a tapering box lattice from its heel at the cab front
	var luff := deg_to_rad(52.0 if working else 72.0)
	var heel := ring + Vector3(0, 1.0, 0) + dir * 1.9
	var length := 15.0
	var tip := heel + dir * cos(luff) * length + Vector3.UP * sin(luff) * length
	var axis := (tip - heel).normalized()
	var normal := axis.cross(side).normalized()
	var chords: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var segs := 12
	for c: Vector2 in chords:
		up.beam("steel", heel + side * c.x * 0.6 + normal * c.y * 0.45, tip + side * c.x * 0.18 + normal * c.y * 0.15, 0.09, 0.09, CRANE * 0.6, CRANE, Vector2.ZERO, false)
	for i: int in range(segs):
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var w0 := lerpf(0.6, 0.18, t0)
		var w1 := lerpf(0.6, 0.18, t1)
		var d0 := lerpf(0.45, 0.15, t0)
		var d1 := lerpf(0.45, 0.15, t1)
		var p0 := heel.lerp(tip, t0)
		var p1 := heel.lerp(tip, t1)
		for s: float in [-1.0, 1.0]:
			up.beam("steel", p0 + side * s * w0 - normal * d0, p1 + side * s * w1 + normal * d1, 0.04, 0.04, CRANE * 0.6, CRANE, Vector2.ZERO, false)
		for n: float in [-1.0, 1.0]:
			up.beam("steel", p0 - side * w0 + normal * n * d0, p1 + side * w1 + normal * n * d1, 0.04, 0.04, CRANE * 0.6, CRANE, Vector2.ZERO, false)
	# luffing wire from the A-frame head, hoist wire down from the jib head to the hook
	var apex_w := ring + Vector3(0, 0.4, 0) + Basis(Vector3.UP, yaw) * apex
	h._props.wire(up, apex_w, tip, 0.15, 0.025, Color(0.15, 0.15, 0.15), 8)
	var hook := Vector3(tip.x, 7.2 if working else 13.0, tip.z)
	h._props.wire(up, tip, hook, 0.0, 0.02, Color(0.15, 0.15, 0.15), 2)
	up.lathe("steel", hook - Vector3(0, 0.6, 0), PackedVector2Array([Vector2(0.18, 0.0), Vector2(0.3, 0.25), Vector2(0.3, 0.5), Vector2(0.1, 0.6)]), 8, Color(0.6, 0.45, 0.1), Color(0.7, 0.55, 0.15))
	if working:
		# a sling of cases hanging over the hatch, waiting for the morning
		var sling := hook - Vector3(0, 2.6, 0)
		for k: int in range(4):
			var c := Vector3(-0.5 + 1.0 * float(k % 2), 0.0, -0.4 + 0.8 * floorf(float(k) * 0.5))
			h._props.wire(up, hook - Vector3(0, 0.6, 0), sling + c * 1.2 + Vector3(0, 0.95, 0), 0.0, 0.012, Color(0.6, 0.55, 0.45), 2)
		h._props.crate(up, sling, Vector3(1.6, 0.9, 1.3), 0.3, 1, Color(0.9, 0.86, 0.76))
		h._props.crate(up, sling + Vector3(0.1, 0.9, 0.0), Vector3(1.2, 0.6, 1.0), 0.1, 0, Color(0.85, 0.82, 0.72))
	h.commit(up, h, "CraneTop", true, true)
	h.add_beacon(tip + Vector3(0, 0.3, 0))

# ---------------------------------------------------------------------------------------------------------------
# Lamps
# ---------------------------------------------------------------------------------------------------------------
## Cast-iron harbour lamp posts along the landward side of the quay (data harbour.lamps, metres down the quay).
## The stretch by the river steps has none: that is why the canoe is there.
func _lamps() -> void:
	for z: Variant in h.sim.data.get("harbour", {}).get("lamps", [16.0, 28.0]):
		var foot := Vector3(float(h.sim.data.get("harbour", {}).get("lampX", 24.1)), 0.0, float(z))
		var kit := Kit.new()
		kit.lathe("steel", foot, PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.22, 0.3), Vector2(0.14, 0.4), Vector2(0.11, 1.2), Vector2(0.08, 4.6), Vector2(0.1, 4.7), Vector2(0.04, 4.8)]), 10, IRON * 0.6, IRON * 1.2)
		var path := PackedVector3Array()
		for i: int in range(8):
			var a := PI * 0.6 * float(i) / 7.0
			path.append(foot + Vector3(-sin(a) * 0.9, 4.6 + cos(a) * 0.4 - 0.4 + 0.4, 0))
		kit.tube("steel", path, 0.045, 5, IRON)
		var head: Vector3 = path[path.size() - 1]
		kit.lathe("steel", head + Vector3(0, -0.12, 0), PackedVector2Array([Vector2(0.36, -0.12), Vector2(0.3, -0.08), Vector2(0.12, 0.08), Vector2(0.05, 0.14)]), 12, Color(0.18, 0.22, 0.2), Color(0.28, 0.32, 0.3))
		kit.lathe("bulb", head + Vector3(0, -0.28, 0), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.11, -0.02), Vector2(0.13, 0.06)]), 10)
		h.commit(kit, h, "LampPost", true)
		h.add_lamp(head + Vector3(0, -0.4, 0), LAMP_WARM, 2.6, 9.5, true, 1.0, 1.2)

# ---------------------------------------------------------------------------------------------------------------
# Transformer house
# ---------------------------------------------------------------------------------------------------------------
func _switch_house() -> void:
	var r := Rect2(19.5, 0.6, 4.5, 4.0)
	for item: Dictionary in h.sim.data.obstacles:
		if str(item.get("id", "")) == "switch-house":
			r = h.sim.rect_of(item)
			r = Rect2(r.position / 32.0, r.size / 32.0)
	var kit := Kit.new()
	var height := 3.4
	var door_x: float = float(h.sim.data.get("radio", {}).get("x", 696)) / 32.0
	# brick walls, a steel door facing the quay, barred vents high up
	var faces: Array = [
		[Vector3(r.position.x, 0, r.end.y), Vector3(1, 0, 0), r.size.x],
		[Vector3(r.end.x, 0, r.end.y), Vector3(0, 0, -1), r.size.y],
		[Vector3(r.end.x, 0, r.position.y), Vector3(-1, 0, 0), r.size.x],
		[Vector3(r.position.x, 0, r.position.y), Vector3(0, 0, 1), r.size.y],
	]
	for f: int in range(4):
		var face: Array = faces[f]
		var openings: Array = []
		if f == 0: openings = [Rect2(door_x - r.position.x - 0.55, 0.0, 1.1, 2.2), Rect2(0.5, 2.5, 0.7, 0.4), Rect2(r.size.x - 1.2, 2.5, 0.7, 0.4)]
		if f == 3: openings = [Rect2(1.4, 2.5, 0.7, 0.4)]
		kit.wall("brick", face[0], face[1], face[2], height, openings, float(f) * 3.3, 0.0, 0.12)
	kit.box("concrete", Vector3(r.get_center().x, height + 0.12, r.get_center().y), Vector3(r.size.x + 0.4, 0.24, r.size.y + 0.4), Kit.grey(0.6), Kit.grey(0.85))
	var door := Kit.trim_uv("door_plank")
	kit.quad_rect("trim", Vector3(door_x - 0.55, 0.0, r.end.y - 0.08), Vector3(door_x + 0.55, 0.0, r.end.y - 0.08), Vector3(door_x + 0.55, 2.2, r.end.y - 0.08), Vector3(door_x - 0.55, 2.2, r.end.y - 0.08), door, Color(0.25, 0.27, 0.25), Color(0.35, 0.38, 0.34))
	for v: Rect2 in [Rect2(r.position.x + 0.5, 2.5, 0.7, 0.4), Rect2(r.end.x - 1.2, 2.5, 0.7, 0.4)]:
		for k: int in range(4):
			var x := v.position.x + 0.1 + float(k) * 0.17
			kit.beam("steel", Vector3(x, 2.5, r.end.y - 0.05), Vector3(x, 2.9, r.end.y - 0.05), 0.02, 0.02, IRON, IRON)
		kit.quad4("decal", Vector3(v.position.x, 2.5, r.end.y - 0.1), Vector3(v.end.x, 2.5, r.end.y - 0.1), Vector3(v.end.x, 2.9, r.end.y - 0.1), Vector3(v.position.x, 2.9, r.end.y - 0.1), Vector2(0.1, 0.1), Vector2(0.11, 0.1), Vector2(0.11, 0.11), Vector2(0.1, 0.11), Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.9))
	# porcelain bushings on the roof, the incoming line from a pole beyond the map and the feed up the bunker
	for i: int in range(3):
		var p := Vector3(r.position.x + 1.0 + float(i) * 1.2, height + 0.24, r.get_center().y)
		kit.lathe("steel", p, PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.08, 0.1), Vector2(0.16, 0.12), Vector2(0.08, 0.2), Vector2(0.15, 0.24), Vector2(0.07, 0.32), Vector2(0.12, 0.36), Vector2(0.04, 0.5)]), 8, Color(0.75, 0.72, 0.62), Color(0.88, 0.86, 0.78))
		h._props.wire(kit, p + Vector3(0, 0.5, 0), Vector3(15.0 + float(i) * 0.4, 7.4, -14.0), 0.9, 0.012, Color(0.1, 0.1, 0.1), 10)
	var pole := Vector3(15.6, 0, -14.6)
	h._props.utility_pole(kit, pole, 0.4, 7.0, 1, 0.02)
	h.commit(kit, h, "SwitchHouse", true, true)
	# warning plate and the lamp over the door
	var warning_sign := Label3D.new()
	warning_sign.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
	warning_sign.font = h.SIGN_FONT
	warning_sign.text = "HOCHSPANNUNG\nLEBENSGEFAHR"
	warning_sign.font_size = 40
	warning_sign.pixel_size = 0.004
	warning_sign.modulate = Color(0.75, 0.16, 0.12)
	warning_sign.outline_size = 0
	warning_sign.shaded = true
	warning_sign.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	warning_sign.position = Vector3(door_x + 1.1, 1.6, r.end.y + 0.01)
	h.add_child(warning_sign)
	var plate := Kit.new()
	plate.quad_rect("trim", Vector3(door_x + 0.75, 1.4, r.end.y + 0.005), Vector3(door_x + 1.45, 1.4, r.end.y + 0.005), Vector3(door_x + 1.45, 1.8, r.end.y + 0.005), Vector3(door_x + 0.75, 1.8, r.end.y + 0.005), Kit.trim_uv("plate_blank"), Kit.grey(0.9), Color.WHITE)
	h._props.wall_lamp(plate, Vector3(door_x, 2.75, r.end.y), 0.0, 0.4)
	plate.lathe("bulb", Vector3(door_x, 2.67, r.end.y + 0.4), PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.1, -0.02), Vector2(0.11, 0.03)]), 8)
	h.commit(plate, h, "SwitchSign", false)
	h.add_lamp(Vector3(door_x, 2.55, r.end.y + 0.45), LAMP_WARM, 1.8, 7.0, true, 0.8, 1.0)
	# the main switch in its cabinet beside the door: on (lever up, cabinet shut) and off (thrown, door open)
	h.generator_point = Vector3(door_x, 0.0, r.end.y + 0.3)
	var box_at := Vector3(door_x - 1.05, 1.15, r.end.y + 0.12)
	var shell := Kit.new()
	shell.box("steel", box_at, Vector3(0.6, 0.8, 0.22), Color(0.26, 0.3, 0.27), Color(0.36, 0.4, 0.36))
	h.commit(shell, h, "SwitchCabinet", true)
	var on_node: Node3D = h.node("SwitchOn")
	var on := Kit.new()
	on.box("steel", box_at + Vector3(0, 0, 0.12), Vector3(0.58, 0.78, 0.03), Color(0.3, 0.34, 0.3), Color(0.38, 0.42, 0.38))
	on.beam("steel", box_at + Vector3(0.36, 0.0, 0.0), box_at + Vector3(0.36, 0.45, 0.06), 0.04, 0.04, Color(0.6, 0.12, 0.08), Color(0.7, 0.15, 0.1))
	h.commit(on, on_node, "Mesh", true)
	var off_node: Node3D = h.node("SwitchOff")
	var off := Kit.new()
	off.box("steel", box_at + Vector3(-0.3, 0, 0.42), Vector3(0.03, 0.78, 0.58), Color(0.3, 0.34, 0.3), Color(0.38, 0.42, 0.38))
	off.beam("steel", box_at + Vector3(0.36, 0.0, 0.0), box_at + Vector3(0.36, -0.42, 0.08), 0.04, 0.04, Color(0.6, 0.12, 0.08), Color(0.7, 0.15, 0.1))
	for k: int in range(3):
		off.box("steel", box_at + Vector3(-0.15 + float(k) * 0.15, 0.1, 0.06), Vector3(0.06, 0.3, 0.04), Color(0.55, 0.45, 0.3), Color(0.65, 0.55, 0.36))
	h.commit(off, off_node, "Mesh", true)
	h.generator_running = on_node
	h.generator_dead = off_node

# ---------------------------------------------------------------------------------------------------------------
# River steps and the canoe
# ---------------------------------------------------------------------------------------------------------------
func _steps_and_canoe() -> void:
	var e: Dictionary = h.sim.data.get("extraction", {})
	var ez: float = float(e.get("y", 1203)) / 32.0
	var kit := Kit.new()
	var top_z := ez - 3.0
	var rise := 0.26
	var run := 0.42
	var n := int(ceil((0.0 - WATER_Y) / rise)) + 1
	for i: int in range(n):
		var y := -rise * float(i + 1)
		var z := top_z + run * float(i)
		var g := rng.randf_range(0.75, 0.92)
		kit.box("granite", Vector3(edge - 0.6, (y + WATER_Y - 1.5) * 0.5, z + run * 0.5), Vector3(1.2, y - (WATER_Y - 1.5), run), Color(0.3, 0.32, 0.28) * g, Color(0.7, 0.7, 0.66) * g, Vector2(rng.randf(), rng.randf()))
	var land_z := top_z + run * float(n)
	kit.box("granite", Vector3(edge - 0.6, WATER_Y - 0.6, land_z + 0.7), Vector3(1.2, 1.4, 1.4), Color(0.2, 0.24, 0.2), Color(0.42, 0.46, 0.4))
	# an iron hand rail down the open side of the flight
	for k: int in range(4):
		var t := float(k) / 3.0
		var p := Vector3(edge - 1.28, lerpf(0.0, WATER_Y + 0.4, t) + 0.9, lerpf(top_z, land_z, t))
		kit.beam("steel", p - Vector3(0, 0.9, 0), p, 0.03, 0.03, IRON, IRON)
	h._props.wire(kit, Vector3(edge - 1.28, 0.9, top_z), Vector3(edge - 1.28, WATER_Y + 1.3, land_z), 0.02, 0.025, IRON, 6)
	h.commit(kit, h, "RiverSteps", true)
	# the canoe: a folding Cockle Mk II, canvas over a wooden frame, lying alongside the landing
	h.canoe = h.node("Canoe", Vector3(edge - 2.15, WATER_Y + 0.02, land_z + 0.2))
	h._canoe_at = h.canoe.position
	var c := Kit.new()
	var length := 4.6
	var rows := 13
	var columns := 7
	for side: float in [1.0, -1.0]:
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for i: int in range(rows):
			var t := float(i) / float(rows - 1)
			var z := (t - 0.5) * length
			var breadth := 0.37 * pow(sin(PI * clampf(t, 0.0, 1.0)), 0.7)
			var sheer := 0.26 + 0.06 * pow(absf(t - 0.5) * 2.0, 2.0)
			for j: int in range(columns):
				var s := float(j) / float(columns - 1)
				var ang := lerpf(0.0, PI * 0.5, s)
				pts.append(Vector3(side * breadth * sin(ang), -0.08 + (sheer + 0.08) * (1.0 - cos(ang)) * 1.0, z))
				uvs.append(Vector2(z * Kit.UV_M, s * 0.3))
				var col := Color(0.42, 0.45, 0.37) * (0.75 + 0.3 * s)
				cols.append(col)
		c.patch("canvas", rows, columns, pts, uvs, cols, false, side < 0.0)
	# deck, the two cockpits with their covers, paddles laid fore and aft, the painter to the steps
	c.box("canvas", Vector3(0, 0.27, 0), Vector3(0.62, 0.03, length * 0.86), Color(0.22, 0.24, 0.2), Color(0.3, 0.32, 0.27))
	for cz: float in [-0.75, 0.6]:
		c.lathe("planks", Vector3(0, 0.27, cz), PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.28, 0.06), Vector2(0.24, 0.07)]), 12, Color(0.32, 0.27, 0.2), Color(0.42, 0.36, 0.26))
		c.disc("canvas", Vector3(0, 0.3, cz), 0.25, 12, Rect2(0.2, 0.2, 0.1, 0.1), Color(0.18, 0.2, 0.17))
	for s: float in [-0.12, 0.12]:
		c.beam("planks", Vector3(s, 0.33, -1.7), Vector3(s * 1.3, 0.33, 1.5), 0.04, 0.03, Color(0.36, 0.3, 0.22), Color(0.44, 0.37, 0.27))
		for end: float in [-1.75, 1.55]:
			c.box("planks", Vector3(s * 1.2, 0.33, end), Vector3(0.16, 0.012, 0.42), Color(0.3, 0.25, 0.18), Color(0.38, 0.32, 0.23))
	h.commit(c, h.canoe, "Hull", true)
	var painter := Kit.new()
	h._props.wire(painter, h.canoe.position + Vector3(0.2, 0.3, -2.1), Vector3(edge - 1.25, WATER_Y + 0.85, land_z - 0.9), 0.15, 0.015, Color(0.5, 0.46, 0.38), 6)
	h.commit(painter, h, "Painter", false)
