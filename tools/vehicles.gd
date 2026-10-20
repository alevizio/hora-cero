extends SceneTree
## Dev tool, run when the vehicle models change: the friends' models as received (art/vehicles/) made game-ready in
## godot/assets/vehicles/, one ArrayMesh each (plaza_vehicle.gdshader draws its body: one draw a model, or one a
## multimesh of them; a near copy's glass, and the rules' colectivo's, is a second surface, plaza_vehicle_glass.gdshader).
##   godot --headless --path godot --script ../tools/vehicles.gd
##
## Every surface of a model becomes vertex data: COLOR its material's colour (linear), UV2.x what it is (KIND_*), UV the
## lettering's own coordinates. On the way:
##  - the Línea 60 colectivo (colectivo60_lod1.glb, 43k triangles) loses the three-pointed star on its grille and the
##    round badge on its bonnet (a car maker's trademark); it is mirrored, so that its door is on the right, the kerb
##    side since Argentina has driven on the right (1945), its lettering turned back to read the right way; and it is
##    simplified part by part (meshoptimizer, through ImporterMesh.generate_lods; its lamps, route boards and lettering
##    apart, so they survive). The rules' colectivo, stranded at the kerb ("colectivo60_open", about 24,600 triangles):
##    its door leaves folded open, its doorway lit, its wheels in more detail, its inside kept (the seats, the rails) and
##    lit behind see-through glass, a lining round it (ceiling, walls); a lighter one for the streets beyond the map
##    (about 5,500: "colectivo60_far"), its windows lit panes; each with a snow cap over it (below); the lettering atlas
##    copied at half size;
##  - the two cars of the time from the retro pack (models/07_microcar, a small rear-engined saloon; 08_work_pickup, a
##    light pickup) and the six of the forties and fifties made on the pack's generator (source/build_vehicles_1950s.py:
##    a big sedan, the same as a taxi, a small saloon, a pickup, a van, a coupé), their paint marked to take each car's
##    own colour, their flat faces shaded smooth (creases kept) and welded. Each in two copies: a far one for the city's
##    streets (about 3,000 triangles, no interior, no fine details, opaque glass), and a near one ("<name>_near", for
##    the cars parked in the plaza's streets, the ones a camera comes close to: about 7,500 to 10,500) with its interior
##    (seats, dashboard, steering wheel) and its fine details kept whole, its body and wheels simplified a little, its
##    glass a second surface the inside shows through;
##  - every car's number plates: the plate's box kept as its frame, a quad of the second atlas's plate on its face
##    (eight invented registrations in the style of the time; the shader gives each car one of them).

const SRC_DIR := "../art/vehicles"
## The generated cars of the time: [source, game mesh, a far copy's triangles kept (about)].
const CARS_1950S := [["11_sedan_49", "sedan49", 3200], ["12_taxi_49", "taxi49", 3200], ["13_saloon_53", "saloon53", 2800],
	["14_pickup_51", "pickup51", 3000], ["15_van_51", "van51", 3000], ["16_coupe_48", "coupe48", 3200]]
const OUT := "res://assets/vehicles/"

const KIND_PAINT := 0.0
const KIND_RECOLOUR := 1.0
const KIND_METAL := 2.0
const KIND_RUBBER := 3.0
const KIND_GLASS := 4.0
const KIND_HEADLAMP := 5.0
const KIND_TAIL := 6.0
const KIND_LETTERING := 7.0
const KIND_SIGN := 9.0
const KIND_AMBER := 10.0
const KIND_FILETE := 11.0
const KIND_SNOWCAP := 12.0
## A taxi's yellow roof (kept clear of the cap: the driver brushes it off, and it says what the car is).
const KIND_TAXI_ROOF := 13.0
## A car's inside, seen through its glass (no snow on it; its own colour), and the painted dashboard (the car's paint).
const KIND_INTERIOR := 14.0
const KIND_INTERIOR_PAINT := 16.0
## A number plate (the second atlas's plate cell, one of eight registrations picked per car by the shader).
const KIND_PLATE := 15.0
const PLATE_CELL := Rect2(0.0, 596.0, 128.0, 40.0)
## The second atlas's size and its cell for the colectivo's fileteado (tools/gen_plaza_textures.py ATLAS_B).
const ATLAS_B := Vector2(1024.0, 640.0)
const FILETE_REAR := Rect2(256.0, 400.0, 256.0, 128.0)

func _init() -> void:
	var src := ProjectSettings.globalize_path("res://").path_join(SRC_DIR).simplify_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_bus(src)
	_car(src.path_join("models/07_microcar.glb"), "microcar", 3000)
	_car(src.path_join("models/08_work_pickup.glb"), "work_pickup", 3200)
	# the cars of the forties and fifties (source/build_vehicles_1950s.py, on the friends' generator)
	for car: Array in CARS_1950S: _car(src.path_join("models/%s.glb" % car[0]), str(car[1]), int(car[2]))
	var img := Image.load_from_file(src.path_join("colectivo60_lettering.png"))
	img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(OUT + "colectivo60_lettering.png"))
	print("lettering 1024")
	quit()

# ---------------------------------------------------------------------------------------------------------------
## The parts of a model: [name, transform to the model's root, mesh].
func _parts(path: String) -> Array:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		return []
	var scene: Node = doc.generate_scene(state)
	var out: Array = []
	_collect(scene, Transform3D.IDENTITY, out)
	scene.free()
	return out

func _collect(n: Node, parent: Transform3D, out: Array) -> void:
	var xf := parent
	if n is Node3D: xf = parent * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: out.append([str(n.name), xf, (n as MeshInstance3D).mesh])
	for c: Node in n.get_children(): _collect(c, xf, out)

## What a material is, by its name: [kind, colour (linear), keep]; `near`: a near copy's (its interior kept).
func _classify(mat: Material, near: bool = false) -> Array:
	var name := mat.resource_name.to_lower() if mat != null else ""
	var col := Color(0.5, 0.5, 0.5)
	if mat is StandardMaterial3D: col = (mat as StandardMaterial3D).albedo_color
	col = col.srgb_to_linear()
	col.a = 1.0
	if "interior_paint" in name: return [KIND_INTERIOR_PAINT, Color(0.8, 0.8, 0.8), near]
	if "interior" in name or "seat" in name: return [KIND_INTERIOR, col, near]
	if "plate" in name: return [KIND_PLATE, col, true]
	if "well" in name: return [KIND_RUBBER, col, true]
	if "lettering" in name: return [KIND_LETTERING, Color.WHITE, true]
	if "sign" in name: return [KIND_SIGN, col, true]
	if "glass" in name: return [KIND_GLASS, col, true]
	if "ivory lens" in name or "headlamp" in name: return [KIND_HEADLAMP, col, true]
	if "ruby" in name or "tail" in name: return [KIND_TAIL, col, true]
	if "amber" in name or "indicator" in name: return [KIND_AMBER, col, true]
	if "chrome" in name or "aluminium" in name or "steel" in name or "reflector" in name or "metal" in name: return [KIND_METAL, col, true]
	if "rubber" in name or "tire" in name or ("trim" in name and not "black trim" in name): return [KIND_RUBBER, col, true]
	if "taxi" in name: return [KIND_TAXI_ROOF, col, true]
	if name == "paint": return [KIND_RECOLOUR, Color(1, 1, 1), true]
	if name == "paint_dark": return [KIND_RECOLOUR, Color(0.75, 0.75, 0.75), true]
	return [KIND_PAINT, col, true]

## One part's surfaces as one set of arrays in the model's frame, the surfaces that are dropped left out; `skip` a
## callable (kind, centroid) -> bool for triangles to delete.
func _part_arrays(xf: Transform3D, mesh: Mesh, skip: Callable, near: bool = false) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for s: int in range(mesh.get_surface_count()):
		var info := _classify(mesh.surface_get_material(s), near)
		if not bool(info[2]): continue
		var kind: float = info[0]
		var c: Color = info[1]
		var arr: Array = mesh.surface_get_arrays(s)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var suv = arr[Mesh.ARRAY_TEX_UV]
		var si = arr[Mesh.ARRAY_INDEX]
		if si == null:
			si = PackedInt32Array()
			for i: int in range(sv.size()): si.append(i)
		var base := v.size()
		for i: int in range(sv.size()):
			v.append(xf * sv[i])
			nrm.append((xf.basis * sn[i]).normalized())
			col.append(c)
			uv.append(suv[i] if suv != null else Vector2.ZERO)
			uv2.append(Vector2(kind, 0.0))
		for t: int in range(0, si.size(), 3):
			var cen := (v[base + si[t]] + v[base + si[t + 1]] + v[base + si[t + 2]]) / 3.0
			if skip.is_valid() and bool(skip.call(kind, cen)): continue
			idx.append_array(PackedInt32Array([base + si[t], base + si[t + 1], base + si[t + 2]]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays

## The arrays simplified to about `target` triangles (meshoptimizer's level nearest to it).
func _simplify(arrays: Array, target: int) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.size() / 3 <= target or idx.is_empty(): return arrays
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(60.0, 25.0, [])
	if OS.get_environment("VEHICLE_LODS") != "":
		var counts: Array = [idx.size() / 3]
		for l: int in range(im.get_surface_lod_count(0)): counts.append(im.get_surface_lod_indices(0, l).size() / 3)
		print("    lods ", counts)
	var out: Array = im.get_surface_arrays(0)
	var best: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	var gap := absi(best.size() / 3 - target)
	for l: int in range(im.get_surface_lod_count(0)):
		var lod := im.get_surface_lod_indices(0, l)
		if absi(lod.size() / 3 - target) < gap:
			gap = absi(lod.size() / 3 - target)
			best = lod
	out[Mesh.ARRAY_INDEX] = best
	return out

## Several arrays as one (indices offset), unused vertices dropped.
func _join(list: Array) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for arrays: Array in list:
		var used: Dictionary = {}
		var si: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var sc: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var su: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var su2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i: int in si:
			if used.has(i): continue
			used[i] = v.size()
			v.append(sv[i])
			nrm.append(sn[i])
			col.append(sc[i])
			uv.append(su[i])
			uv2.append(su2[i])
		for i: int in si: idx.append(int(used[i]))
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = nrm
	out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	return out

## Mirrored across x (the winding turned back), the lettering's quads read the right way again (each triangle's u
## reflected within its own span: a quad's two triangles each reach both its ends).
func _mirror(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i: int in range(v.size()):
		v[i] = Vector3(-v[i].x, v[i].y, v[i].z)
		nrm[i] = Vector3(-nrm[i].x, nrm[i].y, nrm[i].z)
	var flipped: Dictionary = {}
	for t: int in range(0, idx.size(), 3):
		var a := idx[t]
		idx[t] = idx[t + 1]
		idx[t + 1] = a
		if absf(uv2[idx[t]].x - KIND_LETTERING) > 0.1: continue
		var u0 := minf(uv[idx[t]].x, minf(uv[idx[t + 1]].x, uv[idx[t + 2]].x))
		var u1 := maxf(uv[idx[t]].x, maxf(uv[idx[t + 1]].x, uv[idx[t + 2]].x))
		for k: int in range(3):
			var i := idx[t + k]
			if flipped.has(i): continue
			flipped[i] = true
			uv[i] = Vector2(u0 + u1 - uv[i].x, uv[i].y)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays

## Saved: one surface, or (a near copy) the body and its glass.
func _save(arrays: Array, name: String, glass: Array = []) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "body")
	var tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if not glass.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
		mesh.surface_set_name(1, "glass")
		tris += (glass[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	mesh.resource_name = name
	var err := ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
	var aabb := mesh.get_aabb()
	print("%s: %d triangles, %d surfaces, %d vertices, %s (%s)" % [name, tris, mesh.get_surface_count(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), str(aabb), error_string(err)])

# ---------------------------------------------------------------------------------------------------------------
## The badge on the grille (a ring with three spokes, in front of the grille's bars) and the round one on the bonnet,
## by where they are: metal, at the grille's middle and in front of its surround; on the bonnet's crown.
static func _badge(kind: float, c: Vector3) -> bool:
	if kind != KIND_METAL: return false
	if absf(c.x) < 0.19 and c.y > 1.05 and c.y < 1.44 and c.z > 4.70: return true
	if absf(c.x) < 0.075 and c.y > 1.56 and c.y < 1.71 and c.z > 4.60 and c.z < 4.64: return true
	return false

## The kinds that light up or carry writing (kept apart when the body is simplified), and their triangles kept:
## [at full detail, far].
const LIGHTS: Array[float] = [KIND_HEADLAMP, KIND_TAIL, KIND_AMBER, KIND_SIGN, KIND_LETTERING]
const LIGHTS_BUDGET := [1800, 360]

## Only the triangles of the given kinds (`inside`), or only the others.
func _only(arrays: Array, kinds: Array[float], inside: bool) -> Array:
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t: int in range(0, idx.size(), 3):
		var k := uv2[idx[t]].x
		var hit := false
		for want: float in kinds:
			if absf(k - want) < 0.1: hit = true
		if hit == inside: kept.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	var out := arrays.duplicate()
	out[Mesh.ARRAY_INDEX] = kept
	if OS.get_environment("VEHICLE_LODS") != "": print("    ", "lights" if inside else "rest", " ", kept.size() / 3)
	return out

func _bus(src: String) -> void:
	var parts := _parts(src.path_join("colectivo60_lod1.glb"))
	# triangles kept per part: [name, at full detail, far]
	var budget := {"Body": [10400, 4000], "Glazing": [600, 200], "Door_1": [500, 140], "Door_2": [500, 140]}
	var wheel := [1500, 300]
	for variant: Array in [["colectivo60_open", 0, true], ["colectivo60_far", 1, false]]:
		var list: Array = []
		for p: Array in parts:
			var name: String = p[0]
			var xf: Transform3D = p[1]
			if name == "Interior":
				# (the rules' colectivo's inside, lit, shows through its glass: its seats, its rails; the far one's
				# windows are lit panes)
				if not bool(variant[2]): continue
				var inside := _part_arrays(xf, p[2], Callable(), true)
				var k2: PackedVector2Array = inside[Mesh.ARRAY_TEX_UV2]
				for i: int in range(k2.size()): k2[i] = Vector2(KIND_INTERIOR, 0.0)
				inside[Mesh.ARRAY_TEX_UV2] = k2
				list.append(_simplify(inside, 2400))
				continue
			if bool(variant[2]) and name.begins_with("Door_"):
				# the leaves folded in, each about its outer edge (the front one's front, the back one's back)
				var leaf := 1.35 if name == "Door_1" else -1.35
				var hinge := Vector3(0.0, 0.0, 0.0 if name == "Door_1" else -0.357)
				xf = xf * Transform3D(Basis(Vector3.UP, leaf), hinge) * Transform3D(Basis.IDENTITY, -hinge)
			var skip := Callable(self, "_badge") if name == "Body" else Callable()
			var arrays := _part_arrays(xf, p[2], skip)
			var b: Array = budget.get(name, wheel)
			if name == "Body":
				# (its lamps, route boards and lettering simplified on their own, so the far one keeps its headlamps)
				list.append(_simplify(_only(arrays, LIGHTS, true), int(LIGHTS_BUDGET[int(variant[1])])))
				list.append(_simplify(_only(arrays, LIGHTS, false), int(b[int(variant[1])])))
			else:
				list.append(_simplify(arrays, int(b[int(variant[1])])))
		if bool(variant[2]):
			list.append(_doorway())
			list.append(_lining())
		list.append(_filete_rear())
		var joined := _with_cap(_mirror(_join(list)), 0.62)
		if bool(variant[2]):
			var glass := _glass_heights(_join([_only(joined, [KIND_GLASS], true)]))
			_save(_join([_only(joined, [KIND_GLASS], false)]), str(variant[0]), glass)
		else:
			_save(joined, str(variant[0]))

## The rules' colectivo's cabin round its seats, facing in (so that only its far side and its ceiling show through the
## glass): the ceiling cream, the walls varnished wood below the windows, dark across the far windows.
func _lining() -> Array:
	var x := 1.13
	var y0 := 0.97
	var yw := 1.98
	var yt := 2.78
	var yc := 2.86
	var zb := -4.25
	var zf := 3.35
	var wood := Color(0.2, 0.11, 0.055)
	var dark := Color(0.02, 0.024, 0.03)
	var cream := Color(0.62, 0.56, 0.45)
	var quads: Array = [
		# [corners, inward normal, colour]
		[[Vector3(-x, yc, zb), Vector3(x, yc, zb), Vector3(x, yc, zf), Vector3(-x, yc, zf)], Vector3.DOWN, cream],
		[[Vector3(x, y0, zb), Vector3(x, yw, zb), Vector3(x, yw, zf), Vector3(x, y0, zf)], Vector3.LEFT, wood],
		[[Vector3(x, yw, zb), Vector3(x, yt, zb), Vector3(x, yt, zf), Vector3(x, yw, zf)], Vector3.LEFT, dark],
		[[Vector3(x, yt, zb), Vector3(x, yc, zb), Vector3(x, yc, zf), Vector3(x, yt, zf)], Vector3.LEFT, cream],
		[[Vector3(-x, y0, zb), Vector3(-x, yw, zb), Vector3(-x, yw, zf), Vector3(-x, y0, zf)], Vector3.RIGHT, wood],
		[[Vector3(-x, yw, zb), Vector3(-x, yt, zb), Vector3(-x, yt, zf), Vector3(-x, yw, zf)], Vector3.RIGHT, dark],
		[[Vector3(-x, yt, zb), Vector3(-x, yc, zb), Vector3(-x, yc, zf), Vector3(-x, yt, zf)], Vector3.RIGHT, cream],
		[[Vector3(-x, y0, zb), Vector3(x, y0, zb), Vector3(x, yw, zb), Vector3(-x, yw, zb)], Vector3.BACK, wood],
		[[Vector3(-x, yw, zb), Vector3(x, yw, zb), Vector3(x, yc, zb), Vector3(-x, yc, zb)], Vector3.BACK, dark],
	]
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for q: Array in quads:
		var c: Array = q[0]
		var n: Vector3 = q[1]
		var b := v.size()
		for k: int in range(4):
			v.append(c[k])
			nrm.append(n)
			col.append(q[2])
			uv.append(Vector2.ZERO)
			uv2.append(Vector2(KIND_INTERIOR, 0.0))
		# (clockwise seen from the side it faces: that side's normal is minus (b - a) x (c - a))
		var c0: Vector3 = c[0]
		var c1: Vector3 = c[1]
		var c2: Vector3 = c[2]
		var fn := (c1 - c0).cross(c2 - c0)
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]) if fn.dot(n) < 0.0 else PackedInt32Array([b, b + 2, b + 1, b, b + 3, b + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays

## The fileteado on the colectivo's back, between its number plate and its window: a panel of the second atlas
## (cut-out), the motto SIN APURO PERO SIN PAUSA (invented, as the fileteadores' sayings are). (Before the mirror: its
## u runs the other way, and _mirror turns it back.)
func _filete_rear() -> Array:
	var z := -4.496
	var x0 := -0.68
	var x1 := 0.68
	var y0 := 1.36
	var y1 := 1.36 + 0.68
	var r := Rect2(FILETE_REAR.position / ATLAS_B, FILETE_REAR.size / ATLAS_B)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	# seen from behind (-z): its left is +x
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x1, y0, z), Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK * -1.0, Vector3.BACK * -1.0, Vector3.BACK * -1.0, Vector3.BACK * -1.0])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	# (u reversed here: the mirror reflects it back)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(KIND_FILETE, 0), Vector2(KIND_FILETE, 0), Vector2(KIND_FILETE, 0), Vector2(KIND_FILETE, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	return arrays

## The snow that settles on a vehicle through the night, as geometry: a copy of every face that looks up (the roof,
## the bonnet, the boot, the wings; not the tyres, the glass or the lamps) over `min_y`, its edge closed down to the
## paint by a skirt. UV2.y says how far a vertex rises with the night's snow (plaza_vehicle.gdshader): 1 the cap's
## top, less at its edge (a cushion, rounded off), 0 the foot of its skirt. Its normals follow the panel under it,
## turned up; COLOR.r is 1 inside the cap and 0 at its edge, COLOR.g 1 on the skirt (the shader shades the edge).
func _with_cap(arrays: Array, min_y: float) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cap_v := PackedVector3Array()
	var cap_n := PackedVector3Array()
	var cap_i := PackedInt32Array()
	var edges: Dictionary = {}
	var key_of := func(p: Vector3) -> Vector3i: return Vector3i(roundi(p.x * 200.0), roundi(p.y * 200.0), roundi(p.z * 200.0))
	for t: int in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var fn := (b - a).cross(c - a)
		if fn.length_squared() < 1e-10: continue
		fn = fn.normalized()
		# (the winding is clockwise seen from outside: the outward normal is minus that)
		if -fn.y < 0.78 or (a.y + b.y + c.y) / 3.0 < min_y: continue
		# (only the painted panels: the chrome and the trim are too small and scattered to hold a cushion)
		if not float(uv2[idx[t]].x) in [KIND_PAINT, KIND_RECOLOUR]: continue
		var base := cap_v.size()
		cap_v.append_array(PackedVector3Array([a, b, c]))
		cap_n.append_array(PackedVector3Array([nrm[idx[t]], nrm[idx[t + 1]], nrm[idx[t + 2]]]))
		cap_i.append_array(PackedInt32Array([base, base + 1, base + 2]))
		for tri: Array in [[a, b, c], [b, c, a], [c, a, b]]:
			var ka: Vector3i = key_of.call(tri[0])
			var kb: Vector3i = key_of.call(tri[1])
			var k2 := [ka, kb] if str(ka) < str(kb) else [kb, ka]
			var ks := str(k2)
			if edges.has(ks): edges[ks][3] += 1
			else: edges[ks] = [tri[0], tri[1], tri[2], 1]
	var out_v := v.duplicate()
	var out_n := nrm.duplicate()
	var out_c: PackedColorArray = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	var out_uv: PackedVector2Array = (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate()
	var out_uv2 := uv2.duplicate()
	var out_i := idx.duplicate()
	# the cap's edge: the ends of the edges that only one of its faces has
	var rim: Dictionary = {}
	for ks: String in edges:
		var e: Array = edges[ks]
		if int(e[3]) != 1: continue
		rim[key_of.call(e[0])] = true
		rim[key_of.call(e[1])] = true
	const EDGE_RISE := 0.35
	var base := out_v.size()
	for i: int in range(cap_v.size()):
		var on_rim := rim.has(key_of.call(cap_v[i]))
		out_v.append(cap_v[i])
		out_n.append((cap_n[i] + Vector3.UP * 0.8).normalized())
		out_c.append(Color(0.0 if on_rim else 1.0, 0.0, 0.0))
		out_uv.append(Vector2.ZERO)
		out_uv2.append(Vector2(KIND_SNOWCAP, EDGE_RISE if on_rim else 1.0))
	out_i.append_array(_offset(cap_i, base))
	var skirts := 0
	for ks: String in edges:
		var e: Array = edges[ks]
		if int(e[3]) != 1: continue
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		var r: Vector3 = e[2]
		# outward: away from the cap's own triangle on that edge
		var side := Vector3(q.z - p.z, 0.0, -(q.x - p.x))
		if side.length_squared() < 1e-10: continue
		side = side.normalized()
		if side.dot(r - p) > 0.0: side = -side
		# (bottom-left, bottom-right, top-right, top-left seen from outside: its outward normal (B - A) x (D - A))
		var lift := Vector3(0, 0.05, 0)
		if (q - p).cross(lift).dot(side) < 0.0:
			var t2 := p
			p = q
			q = t2
		var b0 := out_v.size()
		out_v.append_array(PackedVector3Array([p, q, q, p]))
		for k: int in range(4):
			out_n.append((side + Vector3.UP * 0.9).normalized())
			out_c.append(Color(0.0, 1.0, 0.0))
			out_uv.append(Vector2.ZERO)
		out_uv2.append_array(PackedVector2Array([Vector2(KIND_SNOWCAP, 0.0), Vector2(KIND_SNOWCAP, 0.0), Vector2(KIND_SNOWCAP, EDGE_RISE), Vector2(KIND_SNOWCAP, EDGE_RISE)]))
		out_i.append_array(PackedInt32Array([b0, b0 + 2, b0 + 1, b0, b0 + 3, b0 + 2]))
		skirts += 1
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	arrays[Mesh.ARRAY_TEX_UV] = out_uv
	arrays[Mesh.ARRAY_TEX_UV2] = out_uv2
	arrays[Mesh.ARRAY_INDEX] = out_i
	print("  snow cap: %d faces, %d skirt quads" % [cap_i.size() / 3, skirts])
	return arrays

static func _offset(idx: PackedInt32Array, base: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in idx: out.append(i + base)
	return out

## The open doorway's inside, a little in from the side: the cabin's light where the leaves stood (the inside's kind:
## lit warm on a bus in service), so that nothing shows through the bus there.
func _doorway() -> Array:
	var x := 1.08
	var z0 := 1.9
	var z1 := 2.65
	var y0 := 0.7
	var y1 := 2.68
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x, y0, z1), Vector3(x, y0, z0), Vector3(x, y1, z0), Vector3(x, y1, z1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT])
	var lit := Color(0.3, 0.26, 0.2)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([lit, lit, lit, lit])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(KIND_INTERIOR, 0), Vector2(KIND_INTERIOR, 0), Vector2(KIND_INTERIOR, 0), Vector2(KIND_INTERIOR, 0)])
	# (counter-clockwise seen from +x, the door's side before the mirror)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	return arrays

## A car's far copy (about `target` triangles, no interior) and its near copy (NEAR_BODY, NEAR_WHEEL).
func _car(path: String, name: String, target: int) -> void:
	var parts := _parts(path)
	for variant: Array in [[name, target, false], [name + "_near", 0, true]]:
		var near: bool = variant[2]
		var want: int = variant[1]
		var list: Array = []
		var names: Array = []
		for p: Array in parts:
			if str(p[0]) in ["Interior", "Fine_Details"] and not near: continue
			names.append(str(p[0]))
			var arrays := _smooth(_part_arrays(p[1], p[2], Callable(), near), 34.0)
			if str(p[0]) == "Interior":
				# (everything inside is the inside: its chrome takes no snow and gives back no sky)
				var k2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				for i: int in range(k2.size()):
					if absf(k2[i].x - KIND_INTERIOR_PAINT) > 0.1: k2[i] = Vector2(KIND_INTERIOR, 0.0)
				arrays[Mesh.ARRAY_TEX_UV2] = k2
			list.append(arrays)
		var out: Array = []
		var lamp_cap := 900 if near else 320
		# (a far copy's triangles shared by its parts as they have them, its bumpers, grille and lamps (the details'
		# part) weighing more and its wheels less: many small pieces, they go first when they are cut; a near copy's
		# body and wheels simplified, its small things and its inside kept whole)
		var weights: Array = []
		var wsum := 0.0
		for j: int in range(list.size()):
			var nm := str(names[j])
			var wt := 1.8 if nm == "Exterior_Details" else 0.55 if nm.begins_with("Wheel") else 1.0
			weights.append(wt * float((list[j][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3))
			wsum += float(weights[j])
		for j: int in range(list.size()):
			var arrays: Array = list[j]
			var nm := str(names[j])
			var n: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var keep := mini(n, maxi(24, int(float(want) * float(weights[j]) / maxf(wsum, 1.0))))
			if near:
				keep = n
				if nm == "Body": keep = int(n * NEAR_BODY)
				elif nm.begins_with("Wheel"): keep = int(n * NEAR_WHEEL)
			# (the lamps and the plates simplified on their own, so they stay round and whole)
			var lamps := _only(arrays, APART, true)
			var lamp_tris: int = (lamps[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if lamp_tris > 0:
				out.append(_simplify(lamps, mini(lamp_tris, lamp_cap)))
				out.append(_simplify(_only(arrays, APART, false), maxi(24, keep - mini(lamp_tris, lamp_cap))))
			else:
				out.append(_simplify(arrays, keep))
		var joined := _plates(_join(out))
		if near:
			var glass := _glass_heights(_join([_only(joined, [KIND_GLASS], true)]))
			_save(_with_cap(_join([_only(joined, [KIND_GLASS], false)]), 0.5), str(variant[0]), glass)
		else:
			_save(_with_cap(joined, 0.5), str(variant[0]))

## Smooth shading for a car made of flat faces (the pack's generator gives each face its own normal): each vertex's
## normal the mean of the faces' at that point, of its kind, that turn less than `crease` degrees from its own (so a
## wing's crown is round and its edge stays sharp).
func _smooth(arrays: Array, crease: float) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var at: Dictionary = {}
	for i: int in range(v.size()):
		var key := Vector4i(roundi(v[i].x * 4000.0), roundi(v[i].y * 4000.0), roundi(v[i].z * 4000.0), roundi(uv2[i].x))
		# (a packed array is a value: taken out, added to, put back)
		var list: PackedInt32Array = at.get(key, PackedInt32Array())
		list.append(i)
		at[key] = list
	var limit := cos(deg_to_rad(crease))
	var out := nrm.duplicate()
	for key: Vector4i in at:
		var list: PackedInt32Array = at[key]
		if list.size() < 2: continue
		for i: int in list:
			var sum := Vector3.ZERO
			for j: int in list:
				if nrm[i].dot(nrm[j]) >= limit: sum += nrm[j]
			if sum.length_squared() > 1e-8: out[i] = sum.normalized()
	arrays[Mesh.ARRAY_NORMAL] = out
	return _weld(arrays)

## The corners that are one point (the same place, kind, colour and normal) made one vertex, so that the faces are
## joined (the simplifier then keeps the surface whole, without cracks).
func _weld(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var first: Dictionary = {}
	var remap := PackedInt32Array()
	remap.resize(v.size())
	for i: int in range(v.size()):
		var key := [Vector3i(roundi(v[i].x * 4000.0), roundi(v[i].y * 4000.0), roundi(v[i].z * 4000.0)),
			Vector3i(roundi(nrm[i].x * 500.0), roundi(nrm[i].y * 500.0), roundi(nrm[i].z * 500.0)), roundi(uv2[i].x),
			col[i].to_rgba32()]
		var ks := str(key)
		if not first.has(ks): first[ks] = i
		remap[i] = int(first[ks])
	for k: int in range(idx.size()): idx[k] = remap[idx[k]]
	arrays[Mesh.ARRAY_INDEX] = idx
	return _join([arrays])

## How much of a near copy's body and wheels is kept (the rest of it whole).
const NEAR_BODY := 0.55
const NEAR_WHEEL := 0.6

## The kinds simplified apart from the rest of a car: its lamps, its plates.
const APART: Array[float] = [KIND_HEADLAMP, KIND_TAIL, KIND_AMBER, KIND_SIGN, KIND_LETTERING, KIND_PLATE]

## The plates: each plate's box (KIND_PLATE triangles; the front one's and the back one's apart) kept as its dark
## frame, and on its outward face (the front's toward -z, the back's toward +z) a quad of the second atlas's plate.
func _plates(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var boxes: Dictionary = {}
	for t: int in range(0, idx.size(), 3):
		if absf(uv2[idx[t]].x - KIND_PLATE) > 0.1: continue
		for k: int in range(3):
			var p := v[idx[t + k]]
			var key := 1 if p.z > 0.0 else -1
			if boxes.has(key): boxes[key] = (boxes[key] as AABB).expand(p)
			else: boxes[key] = AABB(p, Vector3.ZERO)
	for i: int in range(uv2.size()):
		if absf(uv2[i].x - KIND_PLATE) < 0.1:
			uv2[i] = Vector2(KIND_RUBBER, 0.0)
			col[i] = Color(0.02, 0.02, 0.022)
	var r := Rect2(PLATE_CELL.position / ATLAS_B, PLATE_CELL.size / ATLAS_B)
	var list: Array = [arrays]
	for key: int in boxes:
		var b: AABB = boxes[key]
		var z := b.end.z + 0.0015 if key > 0 else b.position.z - 0.0015
		var x0 := b.position.x + 0.004
		var x1 := b.end.x - 0.004
		var y0 := b.position.y + 0.004
		var y1 := b.end.y - 0.004
		# (read left to right by somebody facing it: from the front that is toward -x, from behind toward +x)
		var xl := x1 if key < 0 else x0
		var xr := x0 if key < 0 else x1
		var q: Array = []
		q.resize(Mesh.ARRAY_MAX)
		q[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(xl, y1, z), Vector3(xr, y1, z), Vector3(xr, y0, z), Vector3(xl, y0, z)])
		var nz := Vector3(0, 0, float(key))
		q[Mesh.ARRAY_NORMAL] = PackedVector3Array([nz, nz, nz, nz])
		q[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		q[Mesh.ARRAY_TEX_UV] = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var k2 := Vector2(KIND_PLATE, 0.0)
		q[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([k2, k2, k2, k2])
		# (clockwise seen from outside: the outward normal is minus (b - a) x (c - a))
		var a := Vector3(xl, y1, z)
		var fn := (Vector3(xr, y1, z) - a).cross(Vector3(xr, y0, z) - a)
		q[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3]) if fn.dot(nz) < 0.0 else PackedInt32Array([0, 2, 1, 0, 3, 2])
		list.append(q)
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	return _join(list)

## A near copy's glass: UV2.y how high up its windows a vertex is (0 at their feet, 1 at their heads: the snow dusts
## the glass from below, the shader).
func _glass_heights(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if v.is_empty(): return []
	var lo := INF
	var hi := -INF
	for p: Vector3 in v:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	for i: int in range(v.size()): uv2[i] = Vector2(KIND_GLASS, (v[i].y - lo) / maxf(hi - lo, 0.01))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	return arrays
