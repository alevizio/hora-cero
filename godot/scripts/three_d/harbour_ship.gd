extends RefCounted
## A ship at the river quay, built from a spec in the mission's harbour data. The blockade runner Tannenfels:
## moored starboard side to, bow downstream (south), a 1930s cargo liner with a raised forecastle, two hatches
## and a derrick mast forward, the bridge house and funnel amidships. Only the forward half is ever in view; the
## rest runs on past the top of the map into the dark. The freighter Dresden is the same kind of ship lying bow
## upstream (style "freighter"), and the Sperrbrecher alongside her is a smaller, harder grey ship with a gun on
## her forecastle and her bridge well forward (style "sperrbrecher").
## Geometry is laid out in the Tannenfels' own frame (metres, bow at z = 31, bow toward +z) and the ship's node
## carries it to where the spec puts her: moved along the quay, or mirrored to lie bow upstream. Lamps and smoke,
## which live in the world, go through the same transform. The hull is committed in sections so lamps light it.

const Kit = preload("res://scripts/three_d/structures_kit.gd")
const Site = preload("res://scripts/three_d/structures_site.gd")
const WATER_Y := -2.3
## The design frame's bow: every station below is laid out against it.
const DESIGN_BOW := 31.0
const BOOT := Color(0.40, 0.17, 0.12)          # boot-topping at the waterline
const BELOW := Color(0.20, 0.11, 0.08)
const DECK := Color(0.30, 0.29, 0.27)
const RUST := Color(0.42, 0.28, 0.2)
const BLACK := Color(0.07, 0.07, 0.07)

var GREY := Color(0.31, 0.32, 0.33)          # hull: dark wartime grey
var LIGHT_GREY := Color(0.52, 0.53, 0.52)    # superstructure
var h: Node3D
var rng := RandomNumberGenerator.new()
## The ship's own node, and the transform from the design frame to the world (also the node's transform).
var root: Node3D
var xf := Transform3D.IDENTITY
var spec: Dictionary = {}
var style: String = "liner"
## Bow upstream: the design frame is mirrored, so lettering is flipped back to read right.
var mirrored: bool = false
var cx: float = 7.2
var hb: float = 5.0
var bow: float = 31.0
var stern: float = -50.0
var fc_z: float = 24.0          # forecastle break
var fc_h: float = 2.3           # forecastle height above the well deck
var gang_z: float = 14.4
var upper: Node3D               # everything above the hull, taken away when the camera looks from the river side

func _init(harbour: Node3D, seed_value: int) -> void:
	h = harbour
	rng.seed = seed_value

## Builds the ship described by `s` (an entry of harbour.ships; empty: the mission's single "ship").
func build(s: Dictionary = {}) -> Node3D:
	spec = s if not s.is_empty() else h.sim.data.get("harbour", {}).get("ship", {})
	var x0: float = float(spec.get("x0", 2.2))
	var x1: float = float(spec.get("x1", 12.2))
	cx = (x0 + x1) * 0.5
	hb = (x1 - x0) * 0.5
	style = str(spec.get("style", "liner"))
	bow = DESIGN_BOW
	var world_bow: float = float(spec.get("bow", DESIGN_BOW))
	mirrored = int(spec.get("dir", 1)) < 0
	if mirrored:
		xf = Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3(0, 0, world_bow + DESIGN_BOW))
	else:
		xf = Transform3D(Basis.IDENTITY, Vector3(0, 0, world_bow - DESIGN_BOW))
	gang_z = design_z(float(spec.get("gangway", 14.4)))
	match style:
		"freighter":
			GREY = Color(0.29, 0.28, 0.27)
			LIGHT_GREY = Color(0.56, 0.54, 0.49)
		"sperrbrecher":
			GREY = Color(0.34, 0.36, 0.38)
			LIGHT_GREY = Color(0.46, 0.48, 0.5)
			fc_h = 1.9
	var node_name := str(spec.get("name", "")).capitalize().replace(" ", "")
	root = h.node(node_name if node_name != "" else "Sperrbrecher")
	root.transform = xf
	upper = Node3D.new()
	upper.name = "Upper"
	root.add_child(upper)
	_hull()
	_decks()
	_forecastle()
	if style == "sperrbrecher":
		_gun()
		_sperr_bridge(design_z(float(spec.get("bridge", 53.6))))
		_sperr_lights()
	else:
		_hatches()
		_foremast()
		_bridge()
		_gangway()
		_name_and_marks()
		_lights()
	_moorings()
	return root

## A world z on the quay, in the design frame of this ship.
func design_z(world_z: float) -> float:
	return (xf.affine_inverse() * Vector3(0, 0, world_z)).z

## A lamp of the ship's own (her dynamo, never the harbour supply), placed in the world.
func _lamp(at: Vector3, col: Color, energy: float, reach: float, halo: float, streak: float) -> void:
	h.add_lamp(xf * at, col, energy, reach, false, halo, streak)

# ---------------------------------------------------------------------------------------------------------------
# Lines
# ---------------------------------------------------------------------------------------------------------------
## The well deck rises a little toward the bow (sheer).
func deck_y(z: float) -> float:
	return 3.0 + 0.45 * smoothstep(18.0, bow, z)

## Top of the bulwark: a metre over the deck, plus the forecastle's height forward of the break.
func top_y(z: float) -> float:
	return deck_y(z) + 1.05 + fc_h * smoothstep(fc_z - 0.15, fc_z + 0.15, z)

## Half-breadth at station z and height y: parallel sides aft, the bow drawing in to the stem, finer at the
## waterline than at the deck (flare), and the stem raked forward toward the top.
func half(z: float, y: float) -> float:
	var up := clampf((y - (WATER_Y - 2.5)) / (top_y(z) - (WATER_Y - 2.5)), 0.0, 1.0)
	var stem := bow - 1.8 + 1.8 * up
	var start := 15.0
	if z <= start: return hb
	var t := clampf((z - start) / (stem - start), 0.0, 1.0)
	var p := lerpf(1.55, 2.6, up)
	return hb * maxf(0.0, 1.0 - pow(t, p)) * (1.0 - 0.04 * (1.0 - up))

# ---------------------------------------------------------------------------------------------------------------
# Hull
# ---------------------------------------------------------------------------------------------------------------
func _hull() -> void:
	var stations: Array[float] = []
	var z := stern
	while z < 14.0:
		stations.append(z)
		z += 6.0
	for s: float in [14.0, 16.5, 18.5, 20.5, 22.0, 23.2, fc_z - 0.15, fc_z + 0.15, 25.2, 26.4, 27.5, 28.4, 29.2, 29.8, 30.3, 30.7, 31.0]:
		stations.append(s)
	var heights: Array[float] = [WATER_Y - 3.0, WATER_Y - 0.32, WATER_Y - 0.26, WATER_Y + 0.74, WATER_Y + 0.80, -0.2, 1.4]
	var sections: Array[Vector2] = [Vector2(stern, -14.0), Vector2(-14.0, 8.0), Vector2(8.0, 20.5), Vector2(20.5, 32.0)]
	for part: int in range(sections.size()):
		var lo: float = sections[part].x
		var hi: float = sections[part].y
		var rows: Array[float] = []
		for s: float in stations:
			if s >= lo - 0.001 and s <= hi + 0.001: rows.append(s)
		if rows.size() < 2: continue
		var kit := Kit.new()
		for side: float in [1.0, -1.0]:
			var pts := PackedVector3Array()
			var uvs := PackedVector2Array()
			var cols := PackedColorArray()
			for r: float in rows:
				var hs: Array[float] = heights.duplicate()
				hs.append(deck_y(r) - 0.05)
				hs.append(top_y(r))
				for y: float in hs:
					var w := half(r, y)
					pts.append(Vector3(cx + side * w, y, r))
					uvs.append(Vector2(r * Kit.UV_M * 0.92 + (0.37 if side < 0.0 else 0.0), -y * Kit.UV_M))
					cols.append(_hull_colour(y, r))
			kit.patch("hull", rows.size(), heights.size() + 2, pts, uvs, cols, false, side < 0.0)
		# the flat of the stern is never in view; close it anyway
		if part == 0:
			kit.quad_m("hull", Vector3(cx + hb, WATER_Y - 3.0, stern), Vector3(cx - hb, WATER_Y - 3.0, stern), Vector3(cx - hb, top_y(stern), stern), Vector3(cx + hb, top_y(stern), stern), Vector2.ZERO, BELOW, GREY)
		h.commit(kit, root, "Hull%d" % part, true)

func _hull_colour(y: float, z: float) -> Color:
	var c: Color
	if y < WATER_Y - 0.3: c = BELOW
	elif y < WATER_Y + 0.77: c = BOOT
	else: c = GREY * (0.9 + 0.12 * smoothstep(-1.0, 3.0, y))
	# salt and grime collect toward the bow and at the waterline
	c = c * (1.0 - 0.12 * smoothstep(26.0, 31.0, z))
	if absf(y - (WATER_Y + 0.8)) < 0.6: c = c * 0.85
	return c

# ---------------------------------------------------------------------------------------------------------------
# Decks and bulwarks
# ---------------------------------------------------------------------------------------------------------------
## Steel deck between the bulwarks, the inner face of the bulwarks, the rail cap and the scuppers' rust.
func _decks() -> void:
	var inset := 0.14
	var zs: Array[float] = []
	var z := stern
	while z < fc_z - 0.2:
		zs.append(z)
		z += 3.0
	zs.append(fc_z - 0.2)
	var kit := Kit.new()
	var cols_n := 7
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for r: float in zs:
		var y := deck_y(r)
		var w := half(r, y) - inset
		for j: int in range(cols_n):
			var x := lerpf(-w, w, float(j) / float(cols_n - 1))
			pts.append(Vector3(cx + x, y + 0.02 * cos(x / w * 1.5), r))
			uvs.append(Vector2(x * Kit.UV_M, r * Kit.UV_M))
			cols.append(DECK * (0.8 + 0.25 * (1.0 - absf(x) / w)))
	kit.patch("steel", zs.size(), cols_n, pts, uvs, cols, false, true)
	# inner bulwark faces and the rail cap along both sides (well deck)
	for side: float in [1.0, -1.0]:
		var ipts := PackedVector3Array()
		var iuvs := PackedVector2Array()
		var icols := PackedColorArray()
		for r: float in zs:
			var y0 := deck_y(r)
			var y1 := top_y(r)
			var w := half(r, y1) - inset
			ipts.append(Vector3(cx + side * w, y0, r))
			ipts.append(Vector3(cx + side * w, y1, r))
			iuvs.append(Vector2(r * Kit.UV_M, 0.4))
			iuvs.append(Vector2(r * Kit.UV_M, 0.0))
			icols.append(LIGHT_GREY * 0.55)
			icols.append(LIGHT_GREY * 0.8)
		kit.patch("steel", zs.size(), 2, ipts, iuvs, icols, false, side > 0.0)
		for i: int in range(zs.size() - 1):
			var a := Vector3(cx + side * (half(zs[i], top_y(zs[i])) - inset * 0.5), top_y(zs[i]) + 0.04, zs[i])
			var b := Vector3(cx + side * (half(zs[i + 1], top_y(zs[i + 1])) - inset * 0.5), top_y(zs[i + 1]) + 0.04, zs[i + 1])
			kit.beam("steel", a, b, 0.24, 0.08, LIGHT_GREY * 0.8, LIGHT_GREY)
	h.commit(kit, upper, "WellDeck", true, true)

## The raised forecastle: its deck, the break bulkhead facing aft with its doors and ladders, the windlass and
## the anchor gear, the jack staff and the bell.
func _forecastle() -> void:
	var kit := Kit.new()
	var inset := 0.14
	var zs: Array[float] = [fc_z, 25.2, 26.4, 27.5, 28.4, 29.2, 29.8, 30.3, 30.7]
	var cols_n := 7
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for r: float in zs:
		var y := deck_y(r) + fc_h
		var w := maxf(0.05, half(r, y + 1.0) - inset)
		for j: int in range(cols_n):
			var x := lerpf(-w, w, float(j) / float(cols_n - 1))
			pts.append(Vector3(cx + x, y, r))
			uvs.append(Vector2(r * Kit.UV_M, x * Kit.UV_M))
			cols.append(Color(0.5, 0.46, 0.4) * (0.85 + 0.15 * rng.randf()))
	kit.patch("planks", zs.size(), cols_n, pts, uvs, cols, false, true)
	# inner faces of the forecastle bulwarks
	for side: float in [1.0, -1.0]:
		var ipts := PackedVector3Array()
		var iuvs := PackedVector2Array()
		var icols := PackedColorArray()
		for r: float in zs:
			var y0 := deck_y(r) + fc_h
			var y1 := top_y(r)
			var w := maxf(0.05, half(r, y1) - inset)
			ipts.append(Vector3(cx + side * w, y0, r))
			ipts.append(Vector3(cx + side * w, y1, r))
			iuvs.append(Vector2(r * Kit.UV_M, 0.4))
			iuvs.append(Vector2(r * Kit.UV_M, 0.0))
			icols.append(LIGHT_GREY * 0.5)
			icols.append(LIGHT_GREY * 0.8)
		kit.patch("steel", zs.size(), 2, ipts, iuvs, icols, false, side > 0.0)
	# break bulkhead (faces aft, toward -Z), two doors and the ladders up
	var yb := deck_y(fc_z)
	var wb := half(fc_z, yb + fc_h) - inset
	kit.wall("steel", Vector3(cx + wb, yb, fc_z - 0.01), Vector3(-1, 0, 0), wb * 2.0, fc_h, [Rect2(1.0, 0.0, 0.8, 1.9), Rect2(wb * 2.0 - 1.8, 0.0, 0.8, 1.9)], 0.0, 0.0, 0.08, LIGHT_GREY * 0.55, LIGHT_GREY * 0.9)
	for d: float in [1.4, wb * 2.0 - 1.4]:
		var x := cx + wb - d
		kit.quad_rect("trim", Vector3(x + 0.4, yb, fc_z - 0.06), Vector3(x - 0.4, yb, fc_z - 0.06), Vector3(x - 0.4, yb + 1.9, fc_z - 0.06), Vector3(x + 0.4, yb + 1.9, fc_z - 0.06), Kit.trim_uv("door_plank"), LIGHT_GREY * 0.5, LIGHT_GREY * 0.8)
	for s: float in [-1.0, 1.0]:
		var lx := cx + s * (wb - 0.6)
		h._props.ladder(kit, Vector3(lx, yb, fc_z - 1.3), Vector3(lx, yb + fc_h, fc_z - 0.05), 0.5, LIGHT_GREY)
		kit.beam("steel", Vector3(lx - 0.3, yb + fc_h, fc_z), Vector3(lx - 0.3, yb + fc_h + 1.0, fc_z), 0.04, 0.04, LIGHT_GREY, LIGHT_GREY)
	# rail along the break
	kit.beam("steel", Vector3(cx - wb, yb + fc_h + 1.0, fc_z + 0.05), Vector3(cx + wb, yb + fc_h + 1.0, fc_z + 0.05), 0.05, 0.05, LIGHT_GREY, LIGHT_GREY)
	kit.beam("steel", Vector3(cx - wb, yb + fc_h + 0.5, fc_z + 0.05), Vector3(cx + wb, yb + fc_h + 0.5, fc_z + 0.05), 0.03, 0.03, LIGHT_GREY, LIGHT_GREY)
	# windlass: two warping drums, the gypsies and the chain running to the hawse pipes
	var yf := deck_y(27.0) + fc_h
	kit.box("steel", Vector3(cx, yf + 0.35, 26.6), Vector3(1.6, 0.7, 0.9), GREY * 0.6, GREY)
	for s: float in [-1.0, 1.0]:
		kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(cx + s * 1.15, yf + 0.5, 26.6)))
		kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.32, -0.35), Vector2(0.24, -0.3), Vector2(0.22, 0.0), Vector2(0.24, 0.3), Vector2(0.32, 0.35)]), 12, BLACK, GREY * 0.7)
		kit.pop()
		var chain := PackedVector3Array()
		for i: int in range(9):
			var t := float(i) / 8.0
			chain.append(Vector3(cx + s * lerpf(0.9, 2.2, t), yf + 0.05 + 0.02 * sin(t * 9.0), lerpf(26.9, 29.0, t)))
		kit.tube("steel", chain, 0.06, 4, RUST * 0.6)
	# bitts on both sides, the bell on its post, the jack staff at the stem
	for p: Vector3 in [Vector3(cx + 2.4, yf, 25.4), Vector3(cx - 2.4, yf, 25.4), Vector3(cx + 1.4, yf, 28.8), Vector3(cx - 1.4, yf, 28.8)]:
		for dz: float in [-0.25, 0.25]:
			kit.lathe("steel", p + Vector3(0, 0, dz), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.14, 0.5), Vector2(0.19, 0.53), Vector2(0.19, 0.6), Vector2(0.0, 0.61)]), 8, BLACK, GREY * 0.6)
	kit.lathe("steel", Vector3(cx, yf, 29.6), PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.03, 1.4)]), 6, LIGHT_GREY, LIGHT_GREY)
	kit.lathe("steel", Vector3(cx, yf + 1.1, 29.6), PackedVector2Array([Vector2(0.11, -0.2), Vector2(0.09, 0.0), Vector2(0.03, 0.06)]), 8, Color(0.6, 0.48, 0.25), Color(0.7, 0.56, 0.3))
	kit.lathe("planks", Vector3(cx, yf + 1.0, 30.4), PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.03, 3.2)]), 6, Color(0.5, 0.45, 0.38), Color(0.6, 0.55, 0.46), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
	# anchors stowed in the hawse pipes, starboard and port
	for s: float in [1.0, -1.0]:
		var ax := cx + s * (half(28.6, 1.6) + 0.05)
		kit.push(Transform3D(Basis(Vector3.UP, -s * 0.28), Vector3(ax, 1.4, 28.6)))
		kit.box("steel", Vector3(0, 0.05, 0), Vector3(0.18, 1.3, 0.28), BLACK, GREY * 0.5)
		kit.box("steel", Vector3(0, -0.6, 0), Vector3(0.2, 0.22, 1.1), BLACK, GREY * 0.5)
		kit.pop()
		kit.lathe("steel", Vector3(ax - s * 0.02, 2.3, 28.8), PackedVector2Array([Vector2(0.28, -0.1), Vector2(0.24, 0.1)]), 10, BLACK, BLACK)
	h.commit(kit, upper, "Forecastle", true, true)

# ---------------------------------------------------------------------------------------------------------------
# Cargo hatches, derricks, foremast
# ---------------------------------------------------------------------------------------------------------------
func _hatches() -> void:
	var kit := Kit.new()
	for span: Vector2 in [Vector2(15.9, 21.6), Vector2(6.4, 11.9), Vector2(-21.5, -15.5)]:
		var y := deck_y((span.x + span.y) * 0.5)
		var w := 2.55
		var hatch_len := span.y - span.x
		var c := Vector3(cx, y, (span.x + span.y) * 0.5)
		# coaming with its stiffener and the tarpaulins over the boards, battened and wedged
		kit.box("steel", c + Vector3(0, 0.45, 0), Vector3(w * 2.0, 0.9, hatch_len), GREY * 0.55, GREY * 0.95, Vector2(rng.randf(), rng.randf()))
		kit.box("steel", c + Vector3(0, 0.82, 0), Vector3(w * 2.0 + 0.12, 0.08, hatch_len + 0.12), GREY * 0.8, GREY)
		h._props.tarp(kit, c + Vector3(0, 0.96, 0), Vector2(w * 2.0 - 0.1, hatch_len - 0.1), 0.62, Color(0.36, 0.38, 0.30), [0.12, 0.12, 0.12, 0.12], int(span.x * 10.0))
		for k: int in range(1, int(hatch_len / 1.4)):
			var z := span.x + float(k) * hatch_len / float(int(hatch_len / 1.4))
			kit.box("steel", Vector3(cx, y + 1.03, z), Vector3(w * 2.0 + 0.16, 0.05, 0.08), BLACK, GREY * 0.5)
		for s: float in [-1.0, 1.0]:
			kit.box("steel", Vector3(cx + s * (w + 0.06), y + 0.72, c.z), Vector3(0.05, 0.14, hatch_len - 0.1), BLACK, GREY * 0.5)
	h.commit(kit, upper, "Hatches", true, true)

func _foremast() -> void:
	var kit := Kit.new()
	var z := 13.9
	var y := deck_y(z)
	# mast house with the winches on either side
	kit.box("steel", Vector3(cx, y + 1.1, z), Vector3(2.6, 2.2, 1.6), LIGHT_GREY * 0.55, LIGHT_GREY * 0.9, Vector2(rng.randf(), rng.randf()))
	for s: float in [-1.0, 1.0]:
		for dz: float in [-1.7, 1.7]:
			var at := Vector3(cx + s * 0.75, y, z + dz)
			kit.box("steel", at + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.6), BLACK, GREY * 0.6)
			kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), at + Vector3(0, 0.75, 0)))
			kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.28, -0.45), Vector2(0.2, -0.4), Vector2(0.2, 0.4), Vector2(0.28, 0.45)]), 10, BLACK, GREY * 0.5)
			kit.pop()
	# the mast
	var foot := Vector3(cx, y + 2.2, z)
	var head := Vector3(cx, y + 15.0, z)
	kit.lathe("steel", foot, PackedVector2Array([Vector2(0.26, 0.0), Vector2(0.24, 6.0), Vector2(0.17, 11.5), Vector2(0.12, 12.8), Vector2(0.05, 12.85)]), 10, LIGHT_GREY * 0.6, LIGHT_GREY * 0.95)
	# crosstree and the topmast
	kit.box("steel", head + Vector3(0, -2.4, 0), Vector3(2.6, 0.12, 0.3), LIGHT_GREY * 0.8, LIGHT_GREY)
	kit.box("steel", head + Vector3(0, -2.25, 0.25), Vector3(0.6, 0.35, 0.5), LIGHT_GREY * 0.7, LIGHT_GREY)
	# derricks: one each way, resting in their crutches over the hatches
	for dir: float in [1.0, -1.0]:
		var heel := Vector3(cx + dir * 0.3, y + 2.6, z + dir * 0.7)
		var tip := Vector3(cx + dir * 0.4, y + 3.4, z + dir * 7.6)
		kit.beam("steel", heel, tip, 0.22, 0.22, LIGHT_GREY * 0.7, LIGHT_GREY)
		kit.beam("steel", Vector3(tip.x, y, tip.z - dir * 0.4), Vector3(tip.x, tip.y - 0.12, tip.z - dir * 0.4), 0.1, 0.1, GREY * 0.6, GREY)
		h._props.wire(kit, head + Vector3(0, -2.6, dir * 0.2), tip, 0.4, 0.018, Color(0.22, 0.22, 0.2), 8)
		h._props.wire(kit, tip, Vector3(tip.x + 0.3, y + 1.0, z + dir * 1.2), 0.6, 0.012, Color(0.2, 0.2, 0.18), 8)
	# stays and shrouds
	var stem_top := Vector3(cx, deck_y(30.0) + fc_h + 0.3, 30.0)
	h._props.wire(kit, head + Vector3(0, -0.2, 0), stem_top, 0.5, 0.02, Color(0.2, 0.2, 0.19), 14)
	for s: float in [-1.0, 1.0]:
		for dz: float in [-0.9, 0.0, 0.9]:
			var to := Vector3(cx + s * (hb - 0.2), top_y(z + dz), z + dz)
			h._props.wire(kit, head + Vector3(s * 1.2, -2.4, 0), to, 0.08, 0.015, Color(0.2, 0.2, 0.19), 6)
			kit.beam("steel", to, to + Vector3(0, -0.6, 0), 0.04, 0.04, BLACK, GREY)
	# wireless aerial back to the bridge
	h._props.wire(kit, head, Vector3(cx, deck_y(0.0) + 9.4, -3.0), 1.4, 0.008, Color(0.2, 0.2, 0.19), 16)
	h.commit(kit, upper, "Foremast", true, true)
	_lamp(head + Vector3(0, 0.2, 0.15), Color(1.0, 0.9, 0.7), 0.5, 4.0, 0.8, 0.8)
	var bulb := Kit.new()
	bulb.lathe("shipbulb", head + Vector3(0, 0.12, 0.15), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.11, 0.1), Vector2(0.0, 0.22)]), 8)
	h.commit(bulb, upper, "MastLamp", false)

# ---------------------------------------------------------------------------------------------------------------
# Bridge house, funnel, boats
# ---------------------------------------------------------------------------------------------------------------
func _bridge() -> void:
	var kit := Kit.new()
	var y0 := deck_y(0.0)
	var front := 3.6
	var back := -9.0
	# tier 1: the main deckhouse with portholes, some lit
	var w1 := hb - 1.0
	_house(kit, Rect2(cx - w1, back, w1 * 2.0, front - back), y0, 2.6, true)
	# boat deck overhang and the tier 2 house
	kit.box("steel", Vector3(cx, y0 + 2.66, (front + back) * 0.5 - 0.6), Vector3(w1 * 2.0 + 0.6, 0.12, front - back + 1.8), LIGHT_GREY * 0.6, LIGHT_GREY)
	var w2 := hb - 1.6
	_house(kit, Rect2(cx - w2, back + 2.0, w2 * 2.0, front - 0.6 - (back + 2.0)), y0 + 2.72, 2.5, false)
	# bridge deck with its wings reaching out over the sides
	var yb := y0 + 5.22
	kit.box("steel", Vector3(cx, yb + 0.06, front - 1.6), Vector3(hb * 2.0 + 0.2, 0.12, 2.0), LIGHT_GREY * 0.6, LIGHT_GREY)
	for s: float in [-1.0, 1.0]:
		var edge := cx + s * (hb + 0.1)
		kit.box("canvas", Vector3(edge - s * 0.02, yb + 0.6, front - 1.6), Vector3(0.05, 1.0, 2.0), Color(0.42, 0.42, 0.38), Color(0.55, 0.55, 0.5))
		kit.beam("steel", Vector3(edge, yb, front - 0.6), Vector3(edge - s * 1.4, yb - 2.4, front - 0.6), 0.08, 0.08, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.box("canvas", Vector3(cx, yb + 0.6, front - 0.6), Vector3(hb * 2.0 + 0.2, 1.0, 0.05), Color(0.42, 0.42, 0.38), Color(0.55, 0.55, 0.5))
	# wheelhouse with its row of windows facing forward
	var ww := 2.3
	var wz0 := front - 4.8
	var wz1 := front - 0.9
	var wy := yb + 0.12
	var wh := 2.3
	var openings: Array = []
	for i: int in range(5):
		openings.append(Rect2(0.35 + float(i) * 0.86, 1.05, 0.62, 0.78))
	kit.wall("steel", Vector3(cx - ww, wy, wz1), Vector3(1, 0, 0), ww * 2.0, wh, openings, 0.0, 0.0, 0.08, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.wall("steel", Vector3(cx + ww, wy, wz0), Vector3(-1, 0, 0), ww * 2.0, wh, [], 1.0, 0.0, 0.0, LIGHT_GREY * 0.6, LIGHT_GREY)
	for s: float in [-1.0, 1.0]:
		var o := Vector3(cx + s * ww, wy, wz1 if s > 0.0 else wz0)
		kit.wall("steel", o, Vector3(0, 0, -s), wz1 - wz0, wh, [Rect2(1.2, 0.0, 0.7, 1.9), Rect2(2.4, 1.05, 0.55, 0.7)], 2.0, 0.0, 0.08, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.box("steel", Vector3(cx, wy + wh + 0.06, (wz0 + wz1) * 0.5), Vector3(ww * 2.0 + 0.5, 0.12, wz1 - wz0 + 0.5), LIGHT_GREY * 0.6, LIGHT_GREY)
	# the windows: dark glass with the faint glow of the binnacle and the chart table behind
	var glass := Kit.new()
	for i: int in range(5):
		var x := cx - ww + 0.35 + float(i) * 0.86
		var lit := Color(0.22, 0.17, 0.10) if i in [1, 3] else Color(0.05, 0.06, 0.07)
		glass.quad4("window", Vector3(x, wy + 1.05, wz1 - 0.06), Vector3(x + 0.62, wy + 1.05, wz1 - 0.06), Vector3(x + 0.62, wy + 1.83, wz1 - 0.06), Vector3(x, wy + 1.83, wz1 - 0.06), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, lit, lit, lit * 1.4, lit * 1.4)
	h.commit(glass, upper, "BridgeGlass", false, true)
	# monkey island: compass, signal lamp, the small mast with its yard
	var yr := wy + wh + 0.12
	kit.lathe("steel", Vector3(cx, yr, (wz0 + wz1) * 0.5 + 0.6), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.14, 0.9), Vector2(0.22, 1.0), Vector2(0.18, 1.2), Vector2(0.0, 1.25)]), 10, Color(0.5, 0.42, 0.28), Color(0.62, 0.52, 0.32))
	kit.lathe("steel", Vector3(cx, yr, wz0 + 0.5), PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.06, 4.5), Vector2(0.03, 4.6)]), 8, LIGHT_GREY * 0.7, LIGHT_GREY)
	kit.box("steel", Vector3(cx, yr + 3.6, wz0 + 0.5), Vector3(2.4, 0.07, 0.07), LIGHT_GREY * 0.7, LIGHT_GREY)
	# railings round the boat deck
	for s: float in [-1.0, 1.0]:
		var x := cx + s * (w1 + 0.25)
		for y: float in [y0 + 3.2, y0 + 3.7]:
			kit.beam("steel", Vector3(x, y, back - 0.2), Vector3(x, y, front - 1.0), 0.03, 0.03, LIGHT_GREY, LIGHT_GREY)
		var n := int((front - 1.0 - back) / 1.5)
		for i: int in range(n + 1):
			var z := back - 0.2 + float(i) * (front - 0.8 - back) / float(n)
			kit.beam("steel", Vector3(x, y0 + 2.72, z), Vector3(x, y0 + 3.72, z), 0.03, 0.03, LIGHT_GREY, LIGHT_GREY)
	# cowl ventilators on the boat deck
	for p: Vector3 in [Vector3(cx + 2.0, y0 + 2.72, -1.0), Vector3(cx - 2.0, y0 + 2.72, -1.0), Vector3(cx + 1.2, y0, 5.2), Vector3(cx - 1.2, y0, 5.2)]:
		_ventilator(kit, p, 0.0 if p.x > cx else PI)
	h.commit(kit, upper, "Bridge", true, true)
	_funnel(y0 + 2.72, back + 1.6)
	_lifeboats(y0 + 2.72)

## A deckhouse of plated steel: walls with portholes (a few lit) and a door, under the deck above.
func _house(kit: Kit, r: Rect2, y: float, height: float, doors: bool) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var faces: Array = [
		[Vector3(x0, y, z1), Vector3(1, 0, 0), x1 - x0],
		[Vector3(x1, y, z1), Vector3(0, 0, -1), z1 - z0],
		[Vector3(x1, y, z0), Vector3(-1, 0, 0), x1 - x0],
		[Vector3(x0, y, z0), Vector3(0, 0, 1), z1 - z0],
	]
	var glass := Kit.new()
	for f: int in range(4):
		var face: Array = faces[f]
		var o: Vector3 = face[0]
		var right: Vector3 = face[1]
		var length: float = face[2]
		var openings: Array = []
		if doors and f in [1, 3]:
			openings.append(Rect2(length * 0.62, 0.0, 0.75, 1.9))
		kit.wall("steel", o, right, length, height, openings, float(f) * 1.7, 0.0, 0.08, LIGHT_GREY * 0.55, LIGHT_GREY * 0.95)
		var normal: Vector3 = right.cross(Vector3.UP)
		var count := int(length / 1.6)
		for i: int in range(count):
			var along := (float(i) + 0.5) * length / float(count)
			if doors and f in [1, 3] and absf(along - length * 0.62 - 0.37) < 0.8: continue
			var p: Vector3 = o + right * along + Vector3.UP * (height * 0.6) + normal * 0.02
			var lit: bool = rng.randf() < 0.22
			var col := Color(0.55, 0.38, 0.2) if lit else Color(0.04, 0.05, 0.06)
			glass.push(Transform3D(Basis.looking_at(-normal, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), p))
			glass.disc("window", Vector3.ZERO, 0.17, 10, Rect2(0, 0, 0.01, 0.01), col)
			glass.pop()
			kit.push(Transform3D(Basis.looking_at(-normal, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), p - normal * 0.01))
			kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.22, 0.02), Vector2(0.22, 0.05), Vector2(0.18, 0.06)]), 10, Color(0.5, 0.42, 0.28), Color(0.6, 0.5, 0.32))
			kit.pop()
	if doors:
		for f: int in [1, 3]:
			var face: Array = faces[f]
			var o: Vector3 = face[0]
			var right: Vector3 = face[1]
			var length: float = face[2]
			var normal: Vector3 = right.cross(Vector3.UP)
			var a: Vector3 = o + right * (length * 0.62) - normal * 0.05
			kit.quad_rect("trim", a, a + right * 0.75, a + right * 0.75 + Vector3.UP * 1.9, a + Vector3.UP * 1.9, Kit.trim_uv("door_plank"), LIGHT_GREY * 0.45, LIGHT_GREY * 0.7)
	h.commit(glass, upper, "Portholes", false, true)
	kit.box("steel", Vector3((x0 + x1) * 0.5, y + height + 0.02, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.1, 0.06, z1 - z0 + 0.1), LIGHT_GREY * 0.6, LIGHT_GREY * 0.8)

func _ventilator(kit: Kit, at: Vector3, yaw: float) -> void:
	kit.lathe("steel", at, PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.18, 1.1)]), 10, LIGHT_GREY * 0.6, LIGHT_GREY)
	var path := PackedVector3Array()
	for i: int in range(6):
		var a := PI * 0.5 * float(i) / 5.0
		path.append(at + Basis(Vector3.UP, yaw) * Vector3(0.35 - 0.35 * cos(a), 1.1 + 0.35 * sin(a), 0))
	kit.tube("steel", path, 0.2, 10, LIGHT_GREY)
	var mouth: Vector3 = path[path.size() - 1]
	kit.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5), mouth))
	kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.34, 0.25)]), 10, LIGHT_GREY, LIGHT_GREY)
	kit.disc("steel", Vector3(0, 0.05, 0), 0.2, 10, Rect2(0.1, 0.1, 0.02, 0.02), BLACK)
	kit.pop()

func _funnel(y: float, z: float, r: float = 1.55) -> void:
	var kit := Kit.new()
	kit.push(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(cx, y, z)))
	kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(r + 0.15, 0.0), Vector2(r, 0.3), Vector2(r, 5.4)]), 16, LIGHT_GREY * 0.5, LIGHT_GREY * 0.9, Vector2.ZERO, PackedFloat32Array(), 4.0)
	kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(r, 5.4), Vector2(r, 6.9), Vector2(r + 0.06, 6.95), Vector2(r - 0.1, 7.0), Vector2(r - 0.25, 6.9)]), 16, BLACK, Color(0.1, 0.1, 0.1), Vector2.ZERO, PackedFloat32Array(), 4.0)
	kit.disc("steel", Vector3(0, 6.6, 0), r - 0.25, 16, Rect2(0.1, 0.1, 0.02, 0.02), Color(0.02, 0.02, 0.02))
	# steam pipe and the whistle up its forward side
	kit.lathe("steel", Vector3(0, 0, r + 0.15), PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.08, 7.3), Vector2(0.05, 7.4)]), 6, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.lathe("steel", Vector3(0, 6.2, r + 0.28), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.1, 0.3), Vector2(0.06, 0.45)]), 8, Color(0.55, 0.45, 0.26), Color(0.62, 0.52, 0.3))
	kit.pop()
	h.commit(kit, upper, "Funnel", true, true)

func _lifeboats(y: float) -> void:
	var kit := Kit.new()
	var site := Site.new(h._props, 77)
	for s: float in [1.0, -1.0]:
		for z: float in [-5.6, -1.2]:
			var at := Vector3(cx + s * (hb - 0.9), y + 1.3, z)
			kit.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 1.2)), at))
			site.boat(kit, Vector3.ZERO, 0.0, 0.0)
			h._props.tarp(kit, Vector3(0, 0.46, 0), Vector2(0.9, 3.6), 0.25, Color(0.6, 0.6, 0.55), [0.1, 0.1, 0.05, 0.05], int(z * 3.0 + s * 5.0))
			kit.pop()
			# davits
			for dz: float in [-1.9, 1.9]:
				var foot := Vector3(cx + s * (hb - 1.9), y, z + dz)
				var path := PackedVector3Array()
				for i: int in range(7):
					var a := PI * 0.5 * float(i) / 6.0
					path.append(foot + Vector3(s * (1.0 - cos(a)) * 1.1, 1.0 + sin(a) * 1.6 - (0.0 if i < 6 else 0.1), 0))
				kit.tube("steel", path, 0.07, 6, LIGHT_GREY)
				h._props.wire(kit, path[path.size() - 1], at + Vector3(0, 0.6, dz * 0.85), 0.02, 0.01, Color(0.2, 0.2, 0.19), 3)
	h.commit(kit, upper, "Lifeboats", true, true)

# ---------------------------------------------------------------------------------------------------------------
# Gangway, mooring lines, fenders
# ---------------------------------------------------------------------------------------------------------------
## The accommodation ladder from a gap in the bulwark down to the quay, at right angles to the hull: high
## enough above the quay edge for a man to walk under it.
func _gangway() -> void:
	var kit := Kit.new()
	var z := gang_z
	var edge: float = float(h.sim.data.get("harbour", {}).get("quayEdge", 13.0))
	var top := Vector3(cx + hb - 0.1, deck_y(z) + 0.55, z)
	var foot := Vector3(edge + 3.6, 0.06, z)
	var _along := (foot - top).normalized()
	var side := Vector3(0, 0, 1)
	var w := 0.62
	for s: float in [-1.0, 1.0]:
		kit.beam("planks", top + side * w * s, foot + side * w * s, 0.08, 0.22, Color(0.36, 0.33, 0.28), Color(0.5, 0.46, 0.4), Vector2.ZERO, true, Vector3.UP)
	var n := int(top.distance_to(foot) / 0.32)
	for i: int in range(1, n):
		var p := top.lerp(foot, float(i) / float(n))
		kit.box("planks", p + Vector3(0, 0.02, 0), Vector3(0.3, 0.04, w * 2.0), Color(0.4, 0.36, 0.3), Color(0.55, 0.5, 0.42))
	# hand ropes on stanchions
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for i: int in range(0, n + 1, 3):
			var p := top.lerp(foot, float(i) / float(n)) + side * w * s
			kit.beam("steel", p, p + Vector3(0, 0.95, 0), 0.03, 0.03, LIGHT_GREY, LIGHT_GREY)
			if i > 0: h._props.wire(kit, prev + Vector3(0, 0.95, 0), p + Vector3(0, 0.95, 0), 0.05, 0.015, Color(0.7, 0.66, 0.56), 4)
			prev = p
	# a canvas dodger with the ship's name would be peacetime: in wartime, a plain board at the foot
	kit.box("planks", foot + Vector3(0.4, 0.5, 0.0), Vector3(0.05, 1.0, 1.4), Color(0.3, 0.28, 0.25), Color(0.4, 0.37, 0.32))
	h.commit(kit, upper, "Gangway", true, true)
	_lamp(top + Vector3(0.1, 1.9, -0.9), Color(1.0, 0.82, 0.55), 1.4, 6.0, 0.7, 1.0)
	var bulb := Kit.new()
	bulb.beam("steel", top + Vector3(0, 0, -0.9), top + Vector3(0, 2.0, -0.9), 0.04, 0.04, LIGHT_GREY, LIGHT_GREY)
	bulb.lathe("steel", top + Vector3(0.1, 1.95, -0.9), PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.06, 0.1)]), 10, Color(0.2, 0.22, 0.2), Color(0.3, 0.32, 0.3))
	bulb.lathe("shipbulb", top + Vector3(0.1, 1.86, -0.9), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.04), Vector2(0.07, 0.1)]), 8)
	h.commit(bulb, upper, "GangwayLamp", false)

func _moorings() -> void:
	var kit := Kit.new()
	var edge: float = float(h.sim.data.get("harbour", {}).get("quayEdge", 13.0))
	var rope := Color(0.62, 0.56, 0.44)
	if bool(spec.get("outboard", false)):
		# rafted alongside the next hull: short lines across and fenders between the two
		var other := cx + hb + 0.6
		for z: float in [28.0, 19.0, 8.0]:
			h._props.wire(kit, Vector3(cx + half(z, 4.0) - 0.15, deck_y(z) + 1.2, z), Vector3(other + 0.3, 4.2, z - 1.5), 0.25, 0.03, rope, 8)
		for z: float in [25.0, 16.0, 6.0]:
			kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(cx + hb + 0.3, WATER_Y + 0.6, z)))
			kit.lathe("planks", Vector3(0, -0.6, 0), PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.32, 0.2), Vector2(0.32, 1.0), Vector2(0.25, 1.2)]), 8, Color(0.3, 0.27, 0.22), Color(0.42, 0.38, 0.3), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
			kit.pop()
		h.commit(kit, root, "Moorings", true)
		return
	# [fairlead on the ship, bollard on the quay]
	var lines: Array = [
		[Vector3(cx + half(29.0, 5.6) - 0.2, deck_y(29.0) + fc_h + 0.4, 29.0), Vector3(edge + 0.75, 0.55, 34.0)],
		[Vector3(cx + half(27.0, 5.6) - 0.2, deck_y(27.0) + fc_h + 0.4, 27.0), Vector3(edge + 0.75, 0.55, 26.0)],
		[Vector3(cx + hb - 0.1, deck_y(10.0) + 0.6, 10.0), Vector3(edge + 0.75, 0.55, 9.5)],
		[Vector3(cx + hb - 0.1, deck_y(-6.0) + 0.6, -6.0), Vector3(edge + 0.75, 0.55, 2.0)],
	]
	for line: Array in lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		h._props.wire(kit, a, b, 0.35, 0.035, rope, 12)
		# rat guard on the line, a third of the way from the ship
		var p := a.lerp(b, 0.32)
		p.y -= 0.35 * 4.0 * 0.32 * 0.68
		var dir := (b - a).normalized()
		kit.push(Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), p))
		kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.03, -0.02), Vector2(0.38, 0.0), Vector2(0.38, 0.02), Vector2(0.03, 0.04)]), 12, Color(0.5, 0.5, 0.48), Color(0.6, 0.6, 0.56))
		kit.pop()
	# fenders: rope-bound timber camels hanging between hull and quay
	for z: float in [-2.0, 6.0, 17.5, 24.0]:
		kit.push(Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.0), Vector3(edge - 0.32, WATER_Y + 0.6, z)))
		kit.lathe("planks", Vector3(0, -0.9, 0), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.28, 0.2), Vector2(0.28, 1.6), Vector2(0.2, 1.8)]), 8, Color(0.3, 0.27, 0.22), Color(0.42, 0.38, 0.3), Vector2.ZERO, PackedFloat32Array(), -1.0, true)
		kit.pop()
		h._props.wire(kit, Vector3(edge - 0.32, WATER_Y + 1.0, z), Vector3(edge + 0.2, 0.05, z), 0.1, 0.02, rope, 5)
	h.commit(kit, root, "Moorings", true)

func _name_and_marks() -> void:
	var name := Label3D.new()
	name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
	name.font = h.SIGN_FONT
	name.text = str(spec.get("name", "TANNENFELS"))
	name.font_size = 96
	name.pixel_size = 0.0062
	# white paint on a black hull at night: drawn unshaded but dim, so it reads without glowing
	name.modulate = Color(0.46, 0.46, 0.43, 0.92)
	name.outline_size = 0
	name.shaded = false
	name.double_sided = false
	name.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	var z := 26.6
	var x := cx + half(z, 2.6) + 0.04
	var slope := atan2(half(z + 0.6, 2.6) - half(z - 0.6, 2.6), 1.2)
	name.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 + slope) * _unmirror(), Vector3(x, 2.7, z))
	root.add_child(name)
	# draught marks up the stem
	for i: int in range(4):
		var mark := Label3D.new()
		mark.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # signage in the world: never translated
		mark.font = h.SIGN_FONT
		mark.text = str(16 + i * 2)
		mark.font_size = 48
		mark.pixel_size = 0.005
		mark.modulate = Color(0.4, 0.4, 0.37, 0.9)
		mark.shaded = false
		mark.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		var y := WATER_Y + 0.1 + float(i) * 0.6
		var zz := 29.6 + 0.3 * float(i) / 3.0
		mark.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.55) * _unmirror(), Vector3(cx + half(zz, y) + 0.03, y, zz))
		root.add_child(mark)

## Lettering on a mirrored ship is flipped back along its own line, so it still reads left to right.
func _unmirror() -> Basis:
	return Basis.from_scale(Vector3(-1, 1, 1)) if mirrored else Basis.IDENTITY

## The ship's own lights (her dynamo, not the harbour's): a cluster lamp over the forward hatch where they
## were loading late, and a dim one at the break of the forecastle.
func _lights() -> void:
	var kit := Kit.new()
	var at := Vector3(cx + 1.0, deck_y(18.0) + 4.4, 18.5)
	h._props.wire(kit, at + Vector3(0, 0.2, 0), Vector3(cx, deck_y(13.9) + 12.0, 13.9), 0.3, 0.01, Color(0.2, 0.2, 0.18), 6)
	kit.lathe("steel", at, PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.12, 0.16), Vector2(0.03, 0.22)]), 12, Color(0.3, 0.32, 0.3), Color(0.4, 0.42, 0.4))
	kit.lathe("shipbulb", at + Vector3(0, -0.06, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.12, 0.04), Vector2(0.14, 0.08)]), 10)
	h.commit(kit, upper, "CargoLamp", false)
	_lamp(at + Vector3(0, -0.2, 0), Color(1.0, 0.8, 0.52), 2.2, 9.0, 1.1, 1.0)
	var fl := Vector3(cx - 2.0, deck_y(fc_z) + fc_h + 0.6, fc_z - 0.2)
	_lamp(fl, Color(1.0, 0.78, 0.5), 0.8, 5.0, 0.6, 0.9)
	var fk := Kit.new()
	h._props.wall_lamp(fk, fl + Vector3(0, 0.1, 0.25), PI)
	h.commit(fk, upper, "ForecastleLamp", false)
	# a wisp from the funnel: her fires are banked, not out
	h.add_smoke(xf * Vector3(cx, deck_y(-7.4) + 2.72 + 7.6, -7.4 - 0.9))

# ---------------------------------------------------------------------------------------------------------------
# Sperrbrecher: the gun forward, the bridge well forward, a funnel behind it
# ---------------------------------------------------------------------------------------------------------------
## A single gun on a raised tub on the forecastle, its shield and barrel trained fore and aft under a canvas
## muzzle cover, ready-use lockers either side.
func _gun() -> void:
	var kit := Kit.new()
	var z := 27.0
	var y := deck_y(z) + fc_h
	kit.lathe("steel", Vector3(cx, y, z), PackedVector2Array([Vector2(1.45, 0.0), Vector2(1.45, 0.75), Vector2(1.38, 0.8)]), 20, GREY * 0.6, GREY)
	kit.disc("steel", Vector3(cx, y + 0.42, z), 1.38, 20, Rect2(0.1, 0.1, 0.05, 0.05), GREY * 0.7)
	kit.lathe("steel", Vector3(cx, y + 0.42, z), PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.32, 0.7), Vector2(0.38, 0.8), Vector2(0.0, 0.85)]), 12, BLACK, GREY * 0.6)
	# the shield: a bent plate open at the back
	var pts := PackedVector3Array()
	for i: int in range(9):
		var a := lerpf(-1.25, 1.25, float(i) / 8.0)
		pts.append(Vector3(cx + sin(a) * 1.0, y + 0.85, z + cos(a) * 0.6 + 0.2))
	for i: int in range(pts.size() - 1):
		kit.quad_m("steel", pts[i], pts[i + 1], pts[i + 1] + Vector3(0, 1.5, 0), pts[i] + Vector3(0, 1.5, 0), Vector2.ZERO, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.06), Vector3(cx, y + 1.45, z + 0.5)))
	kit.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.1, 0.3), Vector2(0.085, 3.4), Vector2(0.1, 3.5)]), 10, GREY * 0.5, GREY * 0.8)
	kit.lathe("canvas", Vector3(0, 3.35, 0), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.13, 0.3), Vector2(0.0, 0.32)]), 10, Color(0.3, 0.32, 0.26), Color(0.4, 0.42, 0.34))
	kit.pop()
	for s: float in [-1.0, 1.0]:
		kit.box("steel", Vector3(cx + s * (half(z - 1.6, y) - 0.7), y + 0.35, z - 1.6), Vector3(0.6, 0.7, 1.0), GREY * 0.55, GREY * 0.9)
	h.commit(kit, upper, "Gun", true, true)

## The bridge: a tall deckhouse with the open bridge deck on top reaching out to wings over both sides (the
## deck sentry stands out on the starboard wing, over the quay), the wheelhouse, a pole mast and the funnel.
func _sperr_bridge(zb: float) -> void:
	var kit := Kit.new()
	var y0 := deck_y(zb)
	var front := zb + 2.0
	var back := zb - 3.6
	var w1 := hb - 0.9
	_house(kit, Rect2(cx - w1, back, w1 * 2.0, front - back), y0, 3.2, true)
	var yb := y0 + 3.2
	kit.box("steel", Vector3(cx, yb + 0.06, zb - 0.4), Vector3(hb * 2.0 + 0.8, 0.12, 2.6), LIGHT_GREY * 0.6, LIGHT_GREY)
	for s: float in [-1.0, 1.0]:
		var edge := cx + s * (hb + 0.4)
		# canvas dodger along the wing ends, struts down to the deckhouse
		kit.box("canvas", Vector3(edge - s * 0.02, yb + 0.55, zb - 0.4), Vector3(0.05, 0.9, 2.6), Color(0.36, 0.38, 0.36), Color(0.48, 0.5, 0.47))
		kit.beam("steel", Vector3(edge - s * 0.1, yb, zb + 0.6), Vector3(cx + s * w1, yb - 1.6, zb + 0.6), 0.07, 0.07, LIGHT_GREY * 0.6, LIGHT_GREY)
		kit.beam("steel", Vector3(edge - s * 0.1, yb, zb - 1.4), Vector3(cx + s * w1, yb - 1.6, zb - 1.4), 0.07, 0.07, LIGHT_GREY * 0.6, LIGHT_GREY)
		for y: float in [yb + 0.5, yb + 1.0]:
			kit.beam("steel", Vector3(edge, y, zb + 0.9), Vector3(cx + s * 1.6, y, zb + 0.9), 0.03, 0.03, LIGHT_GREY, LIGHT_GREY)
	# the wheelhouse, its windows looking forward
	var ww := 1.6
	var wz0 := zb - 2.9
	var wz1 := zb - 0.4
	var wh := 2.1
	var openings: Array = []
	for i: int in range(4):
		openings.append(Rect2(0.3 + float(i) * 0.72, 1.0, 0.5, 0.7))
	kit.wall("steel", Vector3(cx - ww, yb + 0.12, wz1), Vector3(1, 0, 0), ww * 2.0, wh, openings, 0.0, 0.0, 0.08, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.wall("steel", Vector3(cx + ww, yb + 0.12, wz0), Vector3(-1, 0, 0), ww * 2.0, wh, [], 1.0, 0.0, 0.0, LIGHT_GREY * 0.6, LIGHT_GREY)
	for s: float in [-1.0, 1.0]:
		kit.wall("steel", Vector3(cx + s * ww, yb + 0.12, wz1 if s > 0.0 else wz0), Vector3(0, 0, -s), wz1 - wz0, wh, [Rect2(0.9, 0.0, 0.7, 1.9)], 2.0, 0.0, 0.08, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.box("steel", Vector3(cx, yb + 0.12 + wh + 0.06, (wz0 + wz1) * 0.5), Vector3(ww * 2.0 + 0.4, 0.12, wz1 - wz0 + 0.4), LIGHT_GREY * 0.6, LIGHT_GREY)
	# a range-finder and a small searchlight (dark: blackout) on the roof, a pole mast behind
	var yr := yb + 0.12 + wh + 0.12
	kit.lathe("steel", Vector3(cx - 0.6, yr, wz0 + 1.2), PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.25, 0.3), Vector2(0.3, 0.32), Vector2(0.0, 0.6)]), 10, GREY * 0.6, GREY)
	kit.box("steel", Vector3(cx + 0.5, yr + 0.3, wz0 + 1.2), Vector3(1.6, 0.18, 0.2), BLACK, GREY * 0.5)
	kit.lathe("steel", Vector3(cx, yr, wz0 + 0.3), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.09, 6.0), Vector2(0.04, 6.1)]), 8, LIGHT_GREY * 0.6, LIGHT_GREY)
	kit.box("steel", Vector3(cx, yr + 4.6, wz0 + 0.3), Vector3(2.8, 0.08, 0.08), LIGHT_GREY * 0.7, LIGHT_GREY)
	var glass := Kit.new()
	for i: int in range(4):
		var x := cx - ww + 0.3 + float(i) * 0.72
		var lit := Color(0.12, 0.1, 0.07) if i == 2 else Color(0.04, 0.05, 0.06)
		glass.quad4("window", Vector3(x, yb + 1.12, wz1 - 0.06), Vector3(x + 0.5, yb + 1.12, wz1 - 0.06), Vector3(x + 0.5, yb + 1.82, wz1 - 0.06), Vector3(x, yb + 1.82, wz1 - 0.06), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, lit, lit, lit, lit)
	h.commit(glass, upper, "BridgeGlass", false, true)
	# ladders from the well deck up the front of the house
	for s: float in [-1.0, 1.0]:
		var lx := cx + s * (w1 - 0.5)
		h._props.ladder(kit, Vector3(lx, y0, front + 1.2), Vector3(lx, yb, front + 0.05), 0.5, LIGHT_GREY)
	h.commit(kit, upper, "Bridge", true, true)
	_funnel(y0, back - 2.6, 0.95)

func _sperr_lights() -> void:
	# blackout: one dim blue lamp under the bridge wing, for the men on deck
	var at := Vector3(cx + hb - 0.6, deck_y(16.0) + 2.6, 16.0)
	_lamp(at, Color(0.55, 0.62, 0.9), 0.5, 4.0, 0.5, 0.6)
	h.add_smoke(xf * Vector3(cx, deck_y(10.0) + 7.6, 10.0 - 0.9), 4, 1.0)
