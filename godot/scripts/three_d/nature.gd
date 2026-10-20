extends Node3D
## Terrain, shoreline, water and vegetation for the coastal outpost.
## Built once by world.gd: set `sim`, add to the tree, then call build().
##
## Everything here is static after build(): one terrain mesh, one sea plane, one merged rock mesh, one merged
## bush mesh, and MultiMeshes for trees / ground cover (14 nodes, about 175k triangles in total).
## Motion (wind, swell, surf) lives in the shaders, so update() has nothing to do.
##
## Layout rules that follow the mission data (so they survive level edits):
##  - obstacles  -> contact shadows, worn aprons, no ground cover inside them
##  - `cell-*`   -> the walled yard is trodden bare
##  - buildings  -> a worn patch at the door (east gable, as built by structures.gd)
##  - guards     -> faint footpaths along the patrol routes
##  - bushes     -> one dense shrub patch per rectangle, at most ~1.1 m tall
## Trees never stand inside the walkable interior; forest height ramps up with distance from the map
## edge so foreground trees do not hide playable ground at any of the eight camera yaws.
var sim: RefCounted

const TEX := "res://assets/tex/nature/"
const TerrainShader := preload("res://shaders/terrain.gdshader")
const WaterShader := preload("res://shaders/water.gdshader")
const FoliageShader := preload("res://shaders/nature_foliage.gdshader")
const RockShader := preload("res://shaders/nature_rock.gdshader")

## Playable map in metres (sim coordinates / 32).
const MAP := Rect2(5.0, 0.0, 35.0, 25.0)
const WATER_Y := -0.19
## Colour the world dissolves into far outside the map (also used by atmosphere.gd as clear colour).
const HAZE := Color(0.165, 0.205, 0.205)
## Ground / sea extents: far enough that no camera position, yaw or zoom can see an edge.
const WORLD_MIN := Vector2(-96.0, -98.0)
const WORLD_MAX := Vector2(138.0, 123.0)
## Layout mask (see terrain.gdshader): world rectangle covered and resolution.
const MASK_SIZE := 512
const MASK_RECT := Rect2(-4.0, -19.5, 64.0, 64.0)
const CH_WORN := 0
const CH_OCC := 1
const CH_LUSH := 2
const CH_ROCK := 3
## Structures that are not in mission.json but need vegetation kept clear: [x, z, radius].
const KEEP_CLEAR: Array[Vector3] = [Vector3(38.5, 3.5, 2.1), Vector3(5.8, 22.0, 1.6), Vector3(4.0, 22.0, 2.0)]

# foliage_atlas.png cells (uv rectangles)
const UV_BOUGH_A := Rect2(0.0, 0.0, 0.25, 0.5)
const UV_BOUGH_B := Rect2(0.25, 0.0, 0.25, 0.5)
const UV_LEADER := Rect2(0.5, 0.0, 0.25, 0.5)
const UV_BARK_SPRUCE := Rect2(0.754, 0.004, 0.0545, 0.492)
const UV_BARK_PINE := Rect2(0.8165, 0.004, 0.0545, 0.492)
const UV_BARK_BIRCH := Rect2(0.879, 0.004, 0.0545, 0.492)
const UV_BARK_WOOD := Rect2(0.9415, 0.004, 0.0545, 0.492)
const UV_BROADLEAF := Rect2(0.0, 0.5, 0.5, 0.5)
const UV_SHRUB := Rect2(0.5, 0.5, 0.25, 0.25)
const UV_BIRCH := Rect2(0.75, 0.5, 0.25, 0.25)
const UV_PINE := Rect2(0.5, 0.75, 0.25, 0.25)
const UV_SMALL := Rect2(0.75, 0.75, 0.25, 0.25)

enum Kind { SPRUCE, SPRUCE_YOUNG, PINE, BIRCH, BROADLEAF, SHRUB, FAR_SPRUCE, FAR_BROADLEAF }
const TREE_HEIGHT: Array[float] = [6.0, 4.2, 7.0, 6.2, 5.0, 1.3, 8.0, 6.5]

var _mk := PackedFloat32Array()
var _mscale: float = MASK_SIZE / MASK_RECT.size.x
var _mask_tex: ImageTexture
var _trees: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _foliage_mat: ShaderMaterial
var _cover_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _rock_mat: ShaderMaterial


## Growable vertex buffer -> ArrayMesh (position, normal, uv, colour, indices).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, t: Vector2, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		uv.append(t)
		c.append(col)
		return v.size()-1

	func tri(a: int, b: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(d)

	## Append another buffer transformed by `xf`, colours multiplied by `tint`.
	func merge(other: Buf, xf: Transform3D, tint: Color = Color.WHITE) -> void:
		var base := v.size()
		var nb := xf.basis.inverse().transposed()
		for i: int in range(other.v.size()):
			v.append(xf*other.v[i])
			n.append((nb*other.n[i]).normalized())
			uv.append(other.uv[i])
			c.append(other.c[i]*tint)
		for i: int in other.idx:
			idx.append(base+i)

	func mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


func build() -> void:
	_collect_rocks()
	_collect_trees()
	_build_mask()
	_build_materials()
	_build_terrain()
	_build_water()
	_build_rocks()
	_build_trees()
	_build_bushes()
	_build_groundcover()
	_mk = PackedFloat32Array()   # only needed while building

## Called every frame from world.update_visuals (dt is real time; paused = command mode).
## Wind, swell and surf are driven by shader TIME, so there is nothing to do per frame.
func update(_dt: float, _paused: bool) -> void:
	pass

# ------------------------------------------------------------------------------------------------ shared shape maths
static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## Shoreline X for a given Z: straight along the playable beach, wandering headlands beyond it.
## Mirrored in terrain.gdshader and water.gdshader - keep the three in sync.
static func coast_x(z: float) -> float:
	var o := maxf(maxf(-1.0-z, z-26.0), 0.0)
	var w := smoothstep(0.0, 14.0, o)
	return 4.85+sin(z*0.9)*0.10+sin(z*0.37+1.3)*0.14+w*(sin(z*0.085+0.6)*5.5+sin(z*0.21+2.0)*2.2)

## Ground height for a signed shore distance (0 inland, sloping under the sea). Mirrored in water.gdshader.
static func beach_height(sd: float) -> float:
	return -0.30*smoothstep(0.45, -0.55, sd)-1.3*smoothstep(-0.5, -4.0, sd)

static func ground_y(x: float, z: float) -> float:
	return beach_height(x-coast_x(z))

static func out_dist(x: float, z: float) -> float:
	var dx := maxf(maxf(MAP.position.x-x, x-MAP.end.x), 0.0)
	var dz := maxf(maxf(MAP.position.y-z, z-MAP.end.y), 0.0)
	return sqrt(dx*dx+dz*dz)

## Approximate bare-earth cover of the three vehicle tracks (same centre lines as the terrain shader).
static func track_cover(x: float, z: float) -> float:
	var da := absf(x-(20.4+sin(z*0.23+0.8)*0.28+sin(z*0.071)*0.22))
	var zo := sin(x*0.19+2.1)*0.25
	var db := absf(z-12.0-zo)
	var dc := absf(z-19.4-zo)
	var a := 1.0-smoothstep(0.80, 1.2, da)
	var b := (1.0-smoothstep(0.80, 1.2, db))*smoothstep(5.8, 8.0, x)*(1.0-smoothstep(28.4, 30.4, x))
	var c := (1.0-smoothstep(0.80, 1.2, dc))*smoothstep(7.0, 9.5, x)
	return maxf(a, maxf(b, c))

func _clear_of_structures(x: float, z: float, margin: float) -> bool:
	for k: Vector3 in KEEP_CLEAR:
		if Vector2(x-k.x, z-k.y).length() < k.z+margin: return false
	return true

# ------------------------------------------------------------------------------------------------ layout mask
func _mask_at(ch: int, x: float, z: float) -> float:
	var px := int((x-MASK_RECT.position.x)*_mscale)
	var py := int((z-MASK_RECT.position.y)*_mscale)
	if px < 0 or py < 0 or px >= MASK_SIZE or py >= MASK_SIZE: return 0.0
	return _mk[(py*MASK_SIZE+px)*4+ch]

## Max-blend a soft box into a mask channel: `strength` inside `r`, fading to zero `fall` metres outside.
func _stamp_box(ch: int, r: Rect2, fall: float, strength: float, power: float = 2.0) -> void:
	var px0 := maxi(0, int(floor((r.position.x-fall-MASK_RECT.position.x)*_mscale)))
	var px1 := mini(MASK_SIZE-1, int(ceil((r.end.x+fall-MASK_RECT.position.x)*_mscale)))
	var py0 := maxi(0, int(floor((r.position.y-fall-MASK_RECT.position.y)*_mscale)))
	var py1 := mini(MASK_SIZE-1, int(ceil((r.end.y+fall-MASK_RECT.position.y)*_mscale)))
	for py: int in range(py0, py1+1):
		var wz := MASK_RECT.position.y+(py+0.5)/_mscale
		var dz := maxf(maxf(r.position.y-wz, wz-r.end.y), 0.0)
		var row := py*MASK_SIZE
		for px: int in range(px0, px1+1):
			var wx := MASK_RECT.position.x+(px+0.5)/_mscale
			var dx := maxf(maxf(r.position.x-wx, wx-r.end.x), 0.0)
			var d := sqrt(dx*dx+dz*dz)
			if d >= fall: continue
			var value := strength*pow(1.0-d/fall, power)
			var i := (row+px)*4+ch
			if value > _mk[i]: _mk[i] = value

## Max-blend a soft capsule (a disc when a == b).
func _stamp_line(ch: int, a: Vector2, b: Vector2, radius: float, fall: float, strength: float, power: float = 2.0) -> void:
	var reach := radius+fall
	var px0 := maxi(0, int(floor((minf(a.x, b.x)-reach-MASK_RECT.position.x)*_mscale)))
	var px1 := mini(MASK_SIZE-1, int(ceil((maxf(a.x, b.x)+reach-MASK_RECT.position.x)*_mscale)))
	var py0 := maxi(0, int(floor((minf(a.y, b.y)-reach-MASK_RECT.position.y)*_mscale)))
	var py1 := mini(MASK_SIZE-1, int(ceil((maxf(a.y, b.y)+reach-MASK_RECT.position.y)*_mscale)))
	var ab := b-a
	var len2 := maxf(ab.length_squared(), 0.000001)
	for py: int in range(py0, py1+1):
		var wz := MASK_RECT.position.y+(py+0.5)/_mscale
		var row := py*MASK_SIZE
		for px: int in range(px0, px1+1):
			var wp := Vector2(MASK_RECT.position.x+(px+0.5)/_mscale, wz)
			var t := clampf((wp-a).dot(ab)/len2, 0.0, 1.0)
			var d := maxf(wp.distance_to(a+ab*t)-radius, 0.0)
			if d >= fall: continue
			var value := strength*pow(1.0-d/fall, power)
			var i := (row+px)*4+ch
			if value > _mk[i]: _mk[i] = value

func _build_mask() -> void:
	_mk.resize(MASK_SIZE*MASK_SIZE*4)
	_mk.fill(0.0)
	var cell := Rect2()
	for obstacle: Dictionary in sim.data.obstacles:
		var kind := str(obstacle.get("kind", "wall"))
		if kind == "water": continue
		var r: Rect2 = sim.rect_of(obstacle)
		r = Rect2(r.position/32.0, r.size/32.0)
		# contact shadow: a tight dark seam plus a wide soft skirt, scaled by how tall the thing is
		var reach: float = {"building": 1.9, "wall": 1.25, "truck": 1.2, "crates": 1.1, "sandbags": 0.8}.get(kind, 1.0)
		var solid: bool = kind in ["building", "wall"]             # props do not fill their whole rectangle
		_stamp_box(CH_OCC, r if solid else r.grow(-0.35), reach, 0.52 if solid else 0.42, 2.2)
		_stamp_box(CH_OCC, r.grow(-0.05) if solid else r.grow(-0.5), 0.34 if solid else 0.6, 0.86 if solid else 0.6, 1.5)
		_stamp_box(CH_LUSH, r, 1.1, 0.75, 1.4)
		match kind:
			"building":
				# people walk round it and mill about at the door (east gable, see structures.gd)
				_stamp_box(CH_WORN, r, 0.75, 0.42, 1.0)
				var entrance := Vector2(r.end.x, r.get_center().y)
				_stamp_line(CH_WORN, entrance+Vector2(0.3, 0), entrance+Vector2(1.5, 0), 0.55, 1.5, 0.95, 1.3)
			"truck":
				_stamp_box(CH_WORN, r.grow(0.2), 1.1, 0.9, 1.4)
			"wall":
				_stamp_box(CH_WORN, r, 0.9, 0.5, 1.2)
				if str(obstacle.get("id", "")).begins_with("cell-"):
					cell = r if cell.size == Vector2.ZERO else cell.merge(r)
			_:
				_stamp_box(CH_WORN, r, 0.7, 0.55, 1.2)
	if cell.size != Vector2.ZERO:
		# the walled holding yard is trodden bare
		_stamp_box(CH_WORN, cell.grow(-0.4), 0.6, 0.95, 1.0)
	var door: Dictionary = sim.data.door
	var gate := Vector2(float(door.x)+float(door.w)*0.5, float(door.y)+float(door.h)*0.5)/32.0
	var gate_out := Vector2(float(door.interactX), float(door.interactY))/32.0
	_stamp_line(CH_WORN, gate, gate_out, 0.7, 1.5, 0.95, 1.3)
	# landing place and the footpath up from the boat to the southern track
	var e: Dictionary = sim.data.extraction
	var landing := Vector2(float(e.x), float(e.y))/32.0
	_stamp_line(CH_WORN, landing+Vector2(-0.6, 0), landing+Vector2(0.5, -0.3), 0.6, 1.5, 0.75, 1.4)
	_stamp_line(CH_WORN, landing+Vector2(0.5, -0.3), Vector2(9.6, 19.5), 0.25, 0.8, 0.7, 1.3)
	# sentries wear faint paths along their beats
	for guard: Dictionary in sim.data.guards:
		var route: Array = guard.route
		for i: int in range(route.size()):
			var a := Vector2(float(route[i][0]), float(route[i][1]))/32.0
			var b := Vector2(float(route[(i+1)%route.size()][0]), float(route[(i+1)%route.size()][1]))/32.0
			_stamp_line(CH_WORN, a, b, 0.10, 0.60, 0.42, 1.5)
	for patch: Dictionary in sim.data.bushes:
		var r: Rect2 = sim.rect_of(patch)
		r = Rect2(r.position/32.0, r.size/32.0)
		_stamp_box(CH_OCC, r.grow(-0.25), 0.75, 0.62, 1.6)
		_stamp_box(CH_LUSH, r, 1.6, 1.0, 1.3)
	for t: Dictionary in _trees:
		if bool(t.far): continue
		var p := Vector2(t.p.x, t.p.z)
		if not MASK_RECT.grow(-2.0).has_point(p): continue
		var crown: float = float(t.h)*0.24
		_stamp_line(CH_OCC, p, p, 0.10, 0.45, 0.70, 1.6)
		_stamp_line(CH_OCC, p, p, 0.0, crown*1.25, 0.30, 1.5)
		if int(t.kind) in [Kind.SPRUCE, Kind.SPRUCE_YOUNG, Kind.PINE]:
			_stamp_line(CH_WORN, p, p, crown*0.25, crown*0.9, 0.62, 1.2)   # needle litter, no grass under conifers
		_stamp_line(CH_LUSH, p, p, crown*0.8, 1.6, 0.8, 1.3)
	for rock: Dictionary in _rocks:
		var p := Vector2(rock.p.x, rock.p.z)
		var rad: float = rock.r
		if rad < 0.25 or not MASK_RECT.grow(-2.0).has_point(p): continue
		_stamp_line(CH_OCC, p, p, rad*0.75, 0.55, 0.60, 1.6)
		_stamp_line(CH_ROCK, p, p, rad*0.80, 0.60, 1.0, 1.0)
	var image := Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBAF, _mk.to_byte_array())
	image.convert(Image.FORMAT_RGBA8)
	_mask_tex = ImageTexture.create_from_image(image)

# ------------------------------------------------------------------------------------------------ materials
func _build_materials() -> void:
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = FoliageShader
	_foliage_mat.set_shader_parameter("atlas", load(TEX+"foliage_atlas.png"))
	_foliage_mat.set_shader_parameter("haze_color", HAZE)
	_cover_mat = ShaderMaterial.new()
	_cover_mat.shader = FoliageShader
	_cover_mat.set_shader_parameter("atlas", load(TEX+"groundcover_atlas.png"))
	_cover_mat.set_shader_parameter("haze_color", HAZE)
	_cover_mat.set_shader_parameter("use_cells", 1.0)
	_cover_mat.set_shader_parameter("flat_normal", 1.0)
	_cover_mat.set_shader_parameter("wind_amp", 0.035)
	_cover_mat.set_shader_parameter("alpha_cut", 0.30)
	_cover_mat.set_shader_parameter("wrap", 0.0)
	_cover_mat.set_shader_parameter("brightness", 0.92)

func _mask_uniform() -> Vector4:
	return Vector4(MASK_RECT.position.x, MASK_RECT.position.y, 1.0/MASK_RECT.size.x, 1.0/MASK_RECT.size.y)

func _add_mesh(mesh: Mesh, material: Material, shadows: bool, label: String) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	item.mesh = mesh
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	return item

# ------------------------------------------------------------------------------------------------ terrain + sea
func _build_terrain() -> void:
	# Columns follow the shoreline (dense across the beach slope), then relax to a coarse absolute grid.
	var shore: Array[float] = [-5.0, -4.0, -3.2, -2.5, -1.9, -1.4, -1.0, -0.7, -0.45, -0.25, -0.05, 0.15, 0.35, 0.55, 0.9, 1.6, 3.0]
	var inland: Array[float] = [22.0, 28.0, 34.0, 40.0, 48.0, 60.0, 80.0, 108.0, WORLD_MAX.x]
	var rows: Array[float] = []
	var z := WORLD_MIN.y
	while z < WORLD_MAX.y:
		rows.append(z)
		z += 0.8 if z > -6.0 and z < 31.0 else 2.6
	rows.append(WORLD_MAX.y)
	var b := Buf.new()
	var columns := shore.size()+3+inland.size()
	for rz: float in rows:
		var cx := coast_x(rz)
		for i: int in range(columns):
			var x: float
			if i < shore.size(): x = cx+shore[i]
			elif i < shore.size()+3: x = lerpf(cx+3.0, 18.0, float(i-shore.size()+1)/3.0)
			else: x = inland[i-shore.size()-3]
			var y := ground_y(x, rz)
			var slope := (ground_y(x+0.1, rz)-ground_y(x-0.1, rz))/0.2
			b.add(Vector3(x, y, rz), Vector3(-slope, 1.0, 0.0).normalized(), Vector2(x, rz), Color.WHITE)
	for r: int in range(rows.size()-1):
		for i: int in range(columns-1):
			var a := r*columns+i
			b.tri(a, a+1, a+columns+1)
			b.tri(a, a+columns+1, a+columns)
	var m := ShaderMaterial.new()
	m.shader = TerrainShader
	for key: String in ["grass_tex:grass_albedo", "grass_nrm:grass_normal", "dirt_tex:dirt_albedo", "dirt_nrm:dirt_normal", "shingle_tex:shingle_albedo", "macro_tex:macro_noise", "track_tex:track_strip"]:
		m.set_shader_parameter(key.get_slice(":", 0), load(TEX+key.get_slice(":", 1)+".png"))
	m.set_shader_parameter("mask_tex", _mask_tex)
	m.set_shader_parameter("mask_rect", _mask_uniform())
	m.set_shader_parameter("haze_color", HAZE)
	_terrain_mat = m
	_add_mesh(b.mesh(), m, false, "Terrain")

func _build_water() -> void:
	var size := Vector2(20.0-WORLD_MIN.x, WORLD_MAX.y-WORLD_MIN.y)
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = int(size.x/2.5)
	plane.subdivide_depth = int(size.y/2.5)
	var m := ShaderMaterial.new()
	m.shader = WaterShader
	m.set_shader_parameter("normal_tex", load(TEX+"water_normal.png"))
	m.set_shader_parameter("detail_tex", load(TEX+"water_detail.png"))
	m.set_shader_parameter("mask_tex", _mask_tex)
	m.set_shader_parameter("mask_rect", _mask_uniform())
	m.set_shader_parameter("haze_color", HAZE)
	m.set_shader_parameter("water_level", WATER_Y)
	m.render_priority = -1          # drawn before every other blended thing (sight cones, markers, decals)
	_water_mat = m
	var sea := _add_mesh(plane, m, false, "Sea")
	sea.position = Vector3(WORLD_MIN.x+size.x*0.5, WATER_Y, WORLD_MIN.y+size.y*0.5)

# ------------------------------------------------------------------------------------------------ rocks
func _collect_rocks() -> void:
	var r := _rng(20201)
	var z := -64.0
	while z < 90.0:
		z += r.randf_range(0.5, 1.15)
		var in_map := z > -1.5 and z < 26.5
		var cx := coast_x(z)
		var gate := sin(z*0.83+0.4)+sin(z*0.31+2.0)*0.8      # boulders gather in runs with open beach between
		var roll := r.randf()
		var size_roll := r.randf()
		var rad := lerpf(0.26, 0.95, size_roll*size_roll) if in_map else lerpf(0.4, 1.4, size_roll)   # mostly small, a few big
		var x := cx+r.randf_range(-1.35, 0.20)
		var far_out := cx-r.randf_range(1.3, 5.0)
		var far_rad := r.randf_range(0.35, 1.1)
		var far_roll := r.randf()
		var spin := Vector3(r.randf_range(-0.35, 0.35), r.randf()*TAU, r.randf_range(-0.35, 0.35))
		var squash := Vector3(r.randf_range(0.85, 1.25), r.randf_range(0.55, 0.85), r.randf_range(0.85, 1.25))
		var tone := r.randf()
		var shape := r.randi_range(0, 3)
		if z > 20.2 and z < 23.8: continue                    # jetty and boat
		if gate > -0.15 or roll < 0.22:
			if in_map: x = minf(x, 5.32-rad*0.85)
			var y := ground_y(x, z)-rad*squash.y*0.42
			_rocks.append({"p": Vector3(x, y, z), "r": rad, "scale": squash*rad, "rot": spin, "shape": shape if in_map else 5+shape%2, "tone": tone, "moss": 0.3+0.7*tone, "tide": 1.0})
		if far_roll < 0.20:
			_rocks.append({"p": Vector3(far_out, WATER_Y-far_rad*0.30, z+0.4), "r": far_rad, "scale": Vector3(squash.z, squash.y*0.9, squash.x)*far_rad, "rot": spin*0.8, "shape": (shape+1)%4 if in_map else 5+(shape+1)%2, "tone": tone*0.6, "moss": 0.0, "tide": 1.0})
	# loose stones along the top of the beach
	for i: int in range(150):
		var sz := r.randf_range(-3.0, 28.0)
		var sx := coast_x(sz)+r.randf_range(-0.3, 1.6)
		var srad := r.randf_range(0.04, 0.11)
		var spin := Vector3(r.randf()*TAU, r.randf()*TAU, 0)
		var tone := r.randf_range(0.5, 1.0)
		if sz > 21.0 and sz < 23.0 and sx < 7.0: continue
		_rocks.append({"p": Vector3(sx, ground_y(sx, sz)+srad*0.2, sz), "r": srad, "scale": Vector3(1.2, 0.7, 1.0)*srad, "rot": spin, "shape": 4, "tone": tone, "moss": 0.0, "tide": 0.0})

## Unit boulder: displaced icosphere, chiselled by random cutting planes. `detail` = subdivision level.
func _rock_shape(seed_value: int, detail: int) -> Buf:
	var r := _rng(seed_value)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.9
	var phi := (1.0+sqrt(5.0))*0.5
	var verts: Array[Vector3] = []
	for s: Vector3 in [Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0), Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi), Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1)]:
		verts.append(s.normalized())
	var faces: Array[Vector3i] = [Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11), Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9), Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for level: int in range(detail):
		var cache: Dictionary = {}
		var next: Array[Vector3i] = []
		for f: Vector3i in faces:
			var mid: Array[int] = []
			for pair: Vector2i in [Vector2i(f.x, f.y), Vector2i(f.y, f.z), Vector2i(f.z, f.x)]:
				var key := Vector2i(mini(pair.x, pair.y), maxi(pair.x, pair.y))
				if not cache.has(key):
					verts.append(((verts[pair.x]+verts[pair.y])*0.5).normalized())
					cache[key] = verts.size()-1
				mid.append(cache[key])
			next.append_array([Vector3i(f.x, mid[0], mid[2]), Vector3i(f.y, mid[1], mid[0]), Vector3i(f.z, mid[2], mid[1]), Vector3i(mid[0], mid[1], mid[2])])
		faces = next
	var planes: Array[Plane] = []
	for i: int in range(7):
		var pn := Vector3(r.randf_range(-1, 1), r.randf_range(-0.5, 1), r.randf_range(-1, 1)).normalized()
		planes.append(Plane(pn, r.randf_range(0.62, 0.86)))
	for i: int in range(verts.size()):
		var d := verts[i]
		var p := d*(1.0+0.22*noise.get_noise_3dv(d*1.6)+0.10*noise.get_noise_3dv(d*4.1+Vector3(7, 3, 1)))
		for pl: Plane in planes:
			var over := pl.distance_to(p)
			if over > 0.0: p -= pl.normal*over*0.92
		verts[i] = p
	# smooth normals softened toward the face normal: weathered but still angular
	var smooth: Array[Vector3] = []
	smooth.resize(verts.size())
	smooth.fill(Vector3.ZERO)
	for f: Vector3i in faces:
		var fn := (verts[f.y]-verts[f.x]).cross(verts[f.z]-verts[f.x])
		smooth[f.x] += fn
		smooth[f.y] += fn
		smooth[f.z] += fn
	var b := Buf.new()
	for f: Vector3i in faces:
		var fn := (verts[f.y]-verts[f.x]).cross(verts[f.z]-verts[f.x]).normalized()
		var order: Array[int] = [f.x, f.z, f.y]              # clockwise seen from outside = front face
		var first := b.v.size()
		for k: int in order:
			var p := verts[k]
			var ao := clampf(0.70+p.y*0.5, 0.35, 1.0)            # darker toward the buried underside
			b.add(p, (smooth[k].normalized()*0.55+fn*0.45).normalized(), Vector2.ZERO, Color(ao, 1, 1, 1))
		b.tri(first, first+1, first+2)
	return b

func _build_rocks() -> void:
	var shapes: Array[Buf] = []
	for i: int in range(4): shapes.append(_rock_shape(7300+i*17, 2))    # 0-3: boulders on the playable shore
	shapes.append(_rock_shape(7411, 0))                                 # 4: loose stones
	for i: int in range(2): shapes.append(_rock_shape(7500+i*13, 1))    # 5-6: distant boulders
	var b := Buf.new()
	for rock: Dictionary in _rocks:
		var frame := Basis.from_euler(rock.rot)*Basis.from_scale(rock.scale)
		b.merge(shapes[int(rock.shape)], Transform3D(frame, rock.p), Color(1.0, float(rock.tone), float(rock.moss), float(rock.tide)))
	var m := ShaderMaterial.new()
	m.shader = RockShader
	m.set_shader_parameter("rock_tex", load(TEX+"rock_albedo.png"))
	m.set_shader_parameter("rock_nrm", load(TEX+"rock_normal.png"))
	m.set_shader_parameter("haze_color", HAZE)
	m.set_shader_parameter("water_level", WATER_Y)
	_rock_mat = m
	_add_mesh(b.mesh(), m, true, "ShoreRocks")

# ------------------------------------------------------------------------------------------------ trees
func _collect_trees() -> void:
	var r := _rng(30301)
	# The tree line along the north edge and the column on the east edge (kept clear of the tracks).
	# Operatives walk the path outside the wire (Z 1.3-2.3) and the strip east of the compound (X 38.3-39.7), and
	# the camera looks at them from every side: the northern row stands back on the map edge and is kept to
	# saplings with a low thicket between them, the eastern row stands outside the strip. The tall forest
	# begins behind both.
	var under := _rng(30302)
	for i: int in range(15):
		var tx := 7.1+i*2.25+r.randf_range(-0.25, 0.25)
		var tz := 0.70+r.randf_range(-0.15, 0.2)
		var h := r.randf_range(4.4, 6.0)
		var pick := r.randf()
		if track_cover(tx, tz) > 0.05 or absf(tx-20.4) < 1.7: continue
		_add_tree(Vector3(tx, 0, minf(tz-0.66, 0.2)), remap(h, 4.4, 6.0, 1.7, 2.4), Kind.SPRUCE_YOUNG if pick < 0.7 else Kind.SHRUB, r)
		_add_tree(Vector3(tx+1.12+under.randf_range(-0.2, 0.2), 0, 0.28+under.randf_range(-0.12, 0.12)), under.randf_range(0.95, 1.25), Kind.SHRUB, under)
	for i: int in range(7):
		var tx := 39.15+r.randf_range(-0.15, 0.2)
		var tz := 2.5+i*2.8+r.randf_range(-0.3, 0.3)
		var h := r.randf_range(3.7, 4.8)
		var pick := r.randf()
		if absf(tz-19.4) < 1.7 or not _clear_of_structures(tx, tz, 0.0): continue
		_add_tree(Vector3(tx+1.3, 0, tz), remap(h, 3.7, 4.8, 1.8, 2.4), _edge_kind(minf(pick, 0.86), 3.0), r)       # saplings, slender kinds only
	# Forest all round the landward sides, on a jittered grid. Height is capped near the map edge so that
	# foreground trees never hide the playable ground (a point h metres up covers 0.78 h of ground behind it).
	var cell := 2.3
	var z := -80.0
	while z < 106.0:
		var x := -8.0
		while x < 120.0:
			var px := x+r.randf()*cell*0.85
			var pz := z+r.randf()*cell*0.85
			var roll := r.randf()
			var pick := r.randf()
			var tall := r.randf()
			x += cell
			var d := out_dist(px, pz)
			if d < 1.3 or d > 80.0: continue
			var sd := px-coast_x(pz)
			if sd < 1.7+roll*1.6: continue
			if track_cover(px, pz) > 0.0 or absf(px-(20.4+sin(pz*0.23+0.8)*0.28+sin(pz*0.071)*0.22)) < 1.75: continue
			if px > MAP.end.x and absf(pz-19.4-sin(px*0.19+2.1)*0.25) < 1.75: continue
			if roll > 1.0-0.5*smoothstep(40.0, 78.0, d): continue
			# ... and lower still north and east of the map, where the walked strips lie right on its edge
			var hmax := (d+(0.3 if pz < MAP.position.y or px > MAP.end.x else 1.5))/0.78
			if d >= 10.0:
				_trees.append({"p": Vector3(px, 0, pz), "h": lerpf(7.5, 11.5, tall) if pick < 0.84 else lerpf(6.0, 8.0, tall), "kind": Kind.FAR_SPRUCE if pick < 0.84 else Kind.FAR_BROADLEAF, "far": true, "yaw": roll*TAU*7.0, "tint": _tint(r, 0.07)*Color(0.86, 0.88, 0.90)})
			elif d < 2.5:
				if pick < 0.50: _add_tree(Vector3(px, 0, pz), lerpf(0.9, 1.5, tall), Kind.SHRUB, r)
				elif pick < 0.78: _add_tree(Vector3(px, 0, pz), minf(lerpf(1.8, 3.2, tall), hmax), Kind.SPRUCE_YOUNG, r)
			else:
				var h := minf(lerpf(4.8, 9.6, tall), hmax)
				var kind := Kind.PINE if (sd < 6.0 and pick < 0.6) else _edge_kind(pick, h)
				if kind == Kind.BIRCH or kind == Kind.BROADLEAF: h = minf(h, TREE_HEIGHT[kind]*lerpf(0.85, 1.25, tall))
				_add_tree(Vector3(px, 0, pz), h, kind, r)
		z += cell

func _edge_kind(pick: float, h: float) -> int:
	if pick < 0.56: return Kind.SPRUCE if h > 5.0 else Kind.SPRUCE_YOUNG
	if pick < 0.70: return Kind.PINE if h > 4.6 else Kind.SPRUCE_YOUNG
	if pick < 0.87: return Kind.BIRCH
	return Kind.BROADLEAF

func _tint(r: RandomNumberGenerator, spread: float) -> Color:
	var v := 1.0+r.randf_range(-spread, spread)
	return Color(v*(1.0+r.randf_range(-spread, spread)*0.6), v, v*(1.0+r.randf_range(-spread, spread)), 1.0)

func _add_tree(p: Vector3, h: float, kind: int, r: RandomNumberGenerator) -> void:
	_trees.append({"p": p, "h": h, "kind": kind, "far": false, "yaw": r.randf()*TAU, "tint": _tint(r, 0.08)})

## Tapered trunk through `pts` (base first). Bark strip runs once round and once up.
func _trunk(b: Buf, pts: Array[Vector3], radii: Array[float], uv: Rect2, sides: int, shade_top: float = 0.8) -> void:
	var first := b.v.size()
	for i: int in range(pts.size()):
		var t := float(i)/float(pts.size()-1)
		var shade := lerpf(0.72, shade_top, minf(t*3.0, 1.0))
		for s: int in range(sides+1):
			var a := TAU*float(s)/float(sides)
			var dir := Vector3(cos(a), 0, sin(a))
			b.add(pts[i]+dir*radii[i], dir, Vector2(uv.position.x+uv.size.x*float(s)/float(sides), uv.end.y-uv.size.y*t), Color(shade, shade, shade, 0.0))
	for i: int in range(pts.size()-1):
		for s: int in range(sides):
			var k := first+i*(sides+1)+s
			b.tri(k, k+sides+1, k+sides+2)
			b.tri(k, k+sides+2, k+1)

## Bent bough card: starts at `base`, grows along `dir`, droops toward `dir2`. Texture base is at the trunk.
func _bough(b: Buf, base: Vector3, dir: Vector3, dir2: Vector3, length: float, width: float, uv: Rect2, shade_n: Vector3, c_base: Color, c_tip: Color, roll: float, bent: bool = true) -> void:
	var side := dir.cross(Vector3.UP).normalized().rotated(dir, roll)*width*0.5
	var mid := base+dir*length*0.5
	var pts: Array[Vector3] = [base, mid, mid+dir2*length*0.5]
	if not bent: pts = [base, base+(dir+dir2).normalized()*length]
	var first := b.v.size()
	var rows := pts.size()
	for i: int in range(rows):
		var t := float(i)/float(rows-1)
		var col := c_base.lerp(c_tip, t)
		var vv := uv.end.y-uv.size.y*t
		b.add(pts[i]-side, shade_n, Vector2(uv.position.x, vv), col)
		b.add(pts[i]+side, shade_n, Vector2(uv.end.x, vv), col)
	for i: int in range(rows-1):
		var k := first+i*2
		b.tri(k, k+1, k+3)
		b.tri(k, k+3, k+2)

## Flat card centred at `center`, facing `normal`. With a horizontal normal the texture stands upright.
func _card(b: Buf, center: Vector3, normal: Vector3, size: Vector2, uv: Rect2, roll: float, shade_n: Vector3, col: Color, col_low: Color = Color(-1, 0, 0)) -> void:
	var t := normal.cross(Vector3.UP)
	t = Vector3.RIGHT if t.length() < 0.01 else t.normalized()
	t = t.rotated(normal, roll)
	var down := normal.cross(t)
	var low := col if col_low.r < 0.0 else col_low
	var first := b.v.size()
	b.add(center-t*size.x*0.5-down*size.y*0.5, shade_n, uv.position, col)
	b.add(center+t*size.x*0.5-down*size.y*0.5, shade_n, Vector2(uv.end.x, uv.position.y), col)
	b.add(center+t*size.x*0.5+down*size.y*0.5, shade_n, uv.end, low)
	b.add(center-t*size.x*0.5+down*size.y*0.5, shade_n, Vector2(uv.position.x, uv.end.y), low)
	b.tri(first, first+1, first+2)
	b.tri(first, first+2, first+3)

func _grey(v: float, wind: float) -> Color:
	return Color(v, v, v, wind)

## Spruce: whorls of drooping bough cards round a trunk, dark inside and low, light on top and at the tips.
func _make_spruce(seed_value: int, height: float, radius: float, tiers: int, first_y: float, per_tier: Vector2, detailed: bool) -> Buf:
	var r := _rng(seed_value)
	var b := Buf.new()
	if detailed:
		_trunk(b, [Vector3.ZERO, Vector3(0, height*0.45, 0), Vector3(0, height*0.96, 0)], [height*0.027, height*0.017, 0.012], UV_BARK_SPRUCE, 6, 0.6)
	for i: int in range(tiers):
		var t := float(i)/float(tiers-1)
		var y := lerpf(first_y, height*0.90, pow(t, 0.92))
		var rad := radius*pow(1.0-t, 0.80)*r.randf_range(0.92, 1.08)+height*0.045
		var count := int(round(lerpf(per_tier.x, per_tier.y, t)))
		var droop := deg_to_rad(lerpf(27.0, -16.0, t))
		var spin := r.randf()*TAU
		for k: int in range(count):
			var a := spin+TAU*float(k)/float(count)+r.randf_range(-0.22, 0.22)
			var out := Vector3(cos(a), 0, sin(a))
			var dp := droop+r.randf_range(-0.09, 0.09)
			var dir := out*cos(dp)-Vector3.UP*sin(dp)
			var dir2 := out*cos(dp+0.34)-Vector3.UP*sin(dp+0.34)
			var length := rad*r.randf_range(0.90, 1.14)
			var dark := lerpf(0.42, 0.70, t)
			var bright := lerpf(0.84, 1.08, t)*r.randf_range(0.93, 1.06)
			_bough(b, Vector3(0, y+r.randf_range(-0.07, 0.07), 0), dir, dir2, length, maxf(length*0.70, height*0.075), UV_BOUGH_A if (k+i)%2 == 0 else UV_BOUGH_B, (Vector3.UP*0.85+out*0.55).normalized(), _grey(dark, 0.04), _grey(bright, 0.45+0.5*t), r.randf_range(-0.22, 0.22), detailed)
	var lead_h := height*0.27
	for k: int in range(3 if detailed else 2):
		var a := PI*float(k)/(3.0 if detailed else 2.0)+0.4
		var nrm := Vector3(cos(a), 0, sin(a))
		_card(b, Vector3(0, height*1.01-lead_h*0.5, 0), nrm, Vector2(lead_h*0.52, lead_h), UV_LEADER, 0.0, (Vector3.UP*0.8+nrm*0.4).normalized(), _grey(1.08, 1.0), _grey(0.80, 0.6))
	return b

## Scots pine: tall bare stem and a dense, flat-topped cloud of needle tufts.
func _make_pine(seed_value: int, height: float) -> Buf:
	var r := _rng(seed_value)
	var b := Buf.new()
	var lean := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
	var top := Vector3(lean.x, height*0.90, lean.z)
	_trunk(b, [Vector3.ZERO, lean*0.35+Vector3(0, height*0.45, 0), top], [height*0.026, height*0.019, height*0.009], UV_BARK_PINE, 6, 0.8)
	var crown := Vector3(lean.x, height*0.82, lean.z)
	var rx := height*0.21
	var golden := PI*(3.0-sqrt(5.0))
	for i: int in range(24):
		# sunflower spiral: an even disc of overlapping tufts, domed in the middle, drooping at the rim
		var ring := sqrt((float(i)+0.5)/24.0)
		var a := golden*float(i)+r.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var up := lerpf(0.95, -0.45, ring*ring)+r.randf_range(-0.18, 0.18)
		var pos := crown+out*rx*ring*r.randf_range(0.9, 1.08)+Vector3.UP*up*height*0.085
		var nrm := (Vector3.UP*lerpf(1.0, 0.6, ring)+out*lerpf(0.05, 0.7, ring)).normalized()
		var size := height*r.randf_range(0.21, 0.27)
		var lightness := clampf(0.70+up*0.30, 0.45, 1.0)*r.randf_range(0.93, 1.05)
		_card(b, pos, nrm, Vector2(size, size), UV_PINE, r.randf()*TAU, (nrm+Vector3.UP*0.5).normalized(), _grey(lightness, 0.8))
	# dark underside so the crown has depth from below the rim
	for i: int in range(3):
		_card(b, crown-Vector3.UP*height*0.05+Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3)), Vector3.UP, Vector2(rx*1.5, rx*1.5), UV_PINE, r.randf()*TAU, Vector3.UP, _grey(0.38, 0.3))
	return b

## Broadleaf crown: leaf-cluster cards on an ellipsoid shell, facing outward and upward.
func _make_crown_tree(seed_value: int, height: float, trunk_r: float, bark: Rect2, leaf: Rect2, crown_c: float, crown_r: Vector2, cards: int, card_size: float, hang: float, detailed: bool = true) -> Buf:
	var r := _rng(seed_value)
	var b := Buf.new()
	var lean := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
	if detailed: _trunk(b, [Vector3.ZERO, lean*0.4+Vector3(0, height*0.4, 0), lean+Vector3(0, height*0.86, 0)], [trunk_r, trunk_r*0.7, trunk_r*0.2], bark, 6, 0.9)
	var center := lean*0.6+Vector3(0, height*crown_c, 0)
	var golden := PI*(3.0-sqrt(5.0))
	for i: int in range(cards):
		# fibonacci points over the upper 3/4 of a sphere
		var v := 1.0-(float(i)+0.5)/float(cards)*1.55
		var ring := sqrt(maxf(1.0-v*v, 0.0))
		var a := golden*float(i)+r.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a)*ring, v, sin(a)*ring)
		var shell := r.randf_range(0.72, 1.0)
		var pos := center+Vector3(dir.x*crown_r.x, dir.y*crown_r.y, dir.z*crown_r.x)*shell
		var nrm := (dir+Vector3.UP*lerpf(0.75, 0.25, hang)).normalized()
		var lightness := clampf(0.74+v*0.30, 0.48, 1.06)*r.randf_range(0.92, 1.06)*lerpf(0.82, 1.0, shell)
		var size := card_size*r.randf_range(0.85, 1.15)
		_card(b, pos, nrm, Vector2(size, size), leaf, r.randf()*TAU, (nrm+Vector3.UP*0.45).normalized(), _grey(lightness, 0.5+0.5*maxf(v, 0.0)))
	if not detailed: return b
	# dark heart so the sky never shows straight through the middle
	for i: int in range(3):
		_card(b, center+Vector3(r.randf_range(-0.3, 0.3), (i-1)*crown_r.y*0.35, r.randf_range(-0.3, 0.3)), Vector3.UP.rotated(Vector3.RIGHT, r.randf_range(-0.4, 0.4)), Vector2(crown_r.x*1.5, crown_r.x*1.5), leaf, r.randf()*TAU, Vector3.UP, _grey(0.40, 0.2))
	# limbs
	for i: int in range(4):
		var a := r.randf()*TAU
		var out := Vector3(cos(a), 0.7, sin(a)).normalized()
		var from := lean*0.4+Vector3(0, height*r.randf_range(0.36, 0.55), 0)
		var length := crown_r.x*r.randf_range(0.7, 1.0)
		_card(b, from+out*length*0.5, out.cross(Vector3.UP).normalized(), Vector2(length, trunk_r*0.9), Rect2(bark.position, Vector2(bark.size.x*0.3, bark.size.y)), atan2(out.y, Vector2(out.x, out.z).length()), Vector3.UP, _grey(0.62, 0.1))
	return b

## Low rounded shrub (forest edge filler, not a gameplay bush).
func _make_shrub(seed_value: int) -> Buf:
	var r := _rng(seed_value)
	var b := Buf.new()
	for i: int in range(9):
		var a := TAU*float(i)/9.0*1.7+r.randf_range(-0.3, 0.3)
		var low := i < 5
		var out := Vector3(cos(a), 0, sin(a))
		var pos := out*(0.45 if low else 0.2)+Vector3.UP*(0.45 if low else 0.95)
		var nrm := (out*(0.9 if low else 0.4)+Vector3.UP*(0.45 if low else 0.9)).normalized()
		_card(b, pos, nrm, Vector2(0.95, 0.95), UV_SMALL if i%2 == 0 else UV_SHRUB, r.randf()*TAU, (nrm+Vector3.UP*0.5).normalized(), _grey(0.66 if low else 0.98, 0.5), _grey(0.5 if low else 0.9, 0.2))
	return b

func _build_trees() -> void:
	var variants: Array[Buf] = [
		_make_spruce(41, TREE_HEIGHT[0], 1.55, 8, 0.95, Vector2(6, 4), true),
		_make_spruce(42, TREE_HEIGHT[1], 1.35, 7, 0.40, Vector2(6, 4), true),
		_make_pine(43, TREE_HEIGHT[2]),
		_make_crown_tree(44, TREE_HEIGHT[3], 0.085, UV_BARK_BIRCH, UV_BIRCH, 0.66, Vector2(1.15, 1.75), 24, 1.2, 0.6),
		_make_crown_tree(45, TREE_HEIGHT[4], 0.15, UV_BARK_WOOD, UV_BROADLEAF, 0.66, Vector2(1.7, 1.3), 22, 1.8, 0.0),
		_make_shrub(46),
		_make_spruce(47, TREE_HEIGHT[6], 2.0, 4, 1.6, Vector2(4, 3), false),
		_make_crown_tree(48, TREE_HEIGHT[7], 0.2, UV_BARK_WOOD, UV_BROADLEAF, 0.68, Vector2(2.2, 1.6), 13, 2.2, 0.0, false),
	]
	var by_kind: Array = []
	for i: int in range(variants.size()): by_kind.append([])
	for t: Dictionary in _trees: by_kind[int(t.kind)].append(t)
	for kind: int in range(variants.size()):
		var list: Array = by_kind[kind]
		if list.is_empty(): continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = variants[kind].mesh()
		multi.instance_count = list.size()
		for i: int in range(list.size()):
			var t: Dictionary = list[i]
			var s: float = float(t.h)/TREE_HEIGHT[kind]
			var girth := s*(0.92+0.16*fposmod(float(t.yaw)*3.7, 1.0))
			if kind == Kind.SHRUB: girth = s*1.25
			multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(t.yaw))*Basis.from_scale(Vector3(girth, s, girth)), t.p))
			multi.set_instance_color(i, t.tint)
		var node := MultiMeshInstance3D.new()
		node.name = "Trees%d" % kind
		node.multimesh = multi
		node.material_override = _foliage_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind < Kind.FAR_SPRUCE else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

# ------------------------------------------------------------------------------------------------ gameplay bushes
## One shrub clump: a dark leafy core dome with cut-out sprays all over it.
func _bush_clump(b: Buf, r: RandomNumberGenerator, at: Vector3, radius: float, height: float, tone: float) -> void:
	var core_uv := Rect2(UV_SHRUB.position+UV_SHRUB.size*0.40, UV_SHRUB.size*0.20)
	var first := b.v.size()
	var seg := 7
	for ring: int in range(3):
		var e := float(ring)/3.0*PI*0.5
		for s: int in range(seg):
			var a := TAU*float(s)/float(seg)
			var dir := Vector3(cos(a)*cos(e), sin(e), sin(a)*cos(e))
			var shade := lerpf(0.30, 0.50, float(ring)/2.0)*tone
			b.add(at+Vector3(dir.x*radius*0.80, dir.y*height*0.80, dir.z*radius*0.80), dir, core_uv.position+core_uv.size*Vector2(float(s%2), float(ring%2)), Color(shade, shade, shade, 0.0))
	var apex := b.add(at+Vector3(0, height*0.82, 0), Vector3.UP, core_uv.get_center(), Color(0.52*tone, 0.52*tone, 0.52*tone, 0.0))
	for ring: int in range(2):
		for s: int in range(seg):
			var k := first+ring*seg+s
			var k2 := first+ring*seg+(s+1)%seg
			b.tri(k, k+seg, k2+seg)
			b.tri(k, k2+seg, k2)
	for s: int in range(seg): b.tri(first+2*seg+s, apex, first+2*seg+(s+1)%seg)
	var spin := r.randf()*TAU
	for i: int in range(13):
		var tier := 0 if i < 6 else (1 if i < 11 else 2)
		var count: int = [6, 5, 2][tier]
		var a := spin+TAU*float(i)/float(count)+tier*0.5+r.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0, sin(a))
		var reach: float = [0.74, 0.50, 0.12][tier]
		var lift: float = [0.36, 0.72, 0.98][tier]
		var flare: float = [0.95, 0.60, 0.12][tier]
		var rise: float = [0.35, 0.80, 1.0][tier]
		var nrm := (out*flare+Vector3.UP*rise).normalized()
		var size := radius*r.randf_range(1.15, 1.45)
		var lightness: float = [0.58, 0.88, 1.0][tier]*tone*r.randf_range(0.90, 1.06)
		if tier == 2: nrm = (nrm+Vector3(r.randf_range(-0.45, 0.45), 0, r.randf_range(-0.45, 0.45))).normalized()
		_card(b, at+out*radius*reach+Vector3.UP*height*lift, nrm, Vector2(size, size), UV_SHRUB if (i+tier)%3 != 0 else UV_SMALL, r.randf()*TAU, (nrm+Vector3.UP*0.6).normalized(), _grey(lightness, 0.25+0.25*tier), _grey(lightness*0.8, 0.1))

func _build_bushes() -> void:
	var r := _rng(50501)
	var b := Buf.new()
	for patch: Dictionary in sim.data.bushes:
		var rect: Rect2 = sim.rect_of(patch)
		rect = Rect2(rect.position/32.0, rect.size/32.0)
		var nx := maxi(2, int(round(rect.size.x/0.72)))
		var nz := maxi(2, int(round(rect.size.y/0.72)))
		for ix: int in range(nx):
			for iz: int in range(nz):
				var u := absf((float(ix)+0.5)/float(nx)-0.5)*2.0       # 0 centre .. 1 edge, per axis
				var w := absf((float(iz)+0.5)/float(nz)-0.5)*2.0
				var rim := maxf(u, w)
				var corner := u*w                                       # corners are rounded off and lower
				var radius := r.randf_range(0.50, 0.62)*lerpf(1.0, 0.80, corner)
				# rim clumps sit just inside the rectangle so the foliage ends about on its edge
				var inset := radius*0.72+corner*0.22
				var x := lerpf(rect.position.x+inset, rect.end.x-inset, float(ix)/float(nx-1))+r.randf_range(-0.12, 0.12)
				var z := lerpf(rect.position.y+inset, rect.end.y-inset, float(iz)/float(nz-1))+r.randf_range(-0.12, 0.12)
				var height := lerpf(1.06, 0.80, rim*rim)*lerpf(1.0, 0.82, corner)*r.randf_range(0.82, 1.0)
				_bush_clump(b, r, Vector3(x, 0, z), radius, height, r.randf_range(0.84, 1.08))
	_add_mesh(b.mesh(), _foliage_mat, true, "Bushes")

# ------------------------------------------------------------------------------------------------ ground cover
func _build_groundcover() -> void:
	var r := _rng(60601)
	var bush_rects: Array[Rect2] = []
	for patch: Dictionary in sim.data.bushes:
		var rect: Rect2 = sim.rect_of(patch)
		bush_rects.append(Rect2(rect.position/32.0, rect.size/32.0).grow(-0.15))
	var tufts: Array = []      # [Transform3D, tint, atlas cell]
	var decals: Array = []
	for i: int in range(15000):
		var x := r.randf_range(3.5, 47.0)
		var z := r.randf_range(-7.0, 32.0)
		var roll := r.randf()
		var pick := r.randf()
		var size := r.randf_range(0.65, 1.25)
		var yaw := r.randf()*TAU
		var tint := _tint(r, 0.08)*Color(1.0, 0.97, 0.86)
		var sd := x-coast_x(z)
		if sd < 0.5: continue
		var inside := MAP.has_point(Vector2(x, z))
		if inside and sim.is_blocked(Vector2(x, z)*32.0, 5.0): continue
		if not _clear_of_structures(x, z, -0.6): continue
		var in_bush := false
		for rect: Rect2 in bush_rects:
			if rect.has_point(Vector2(x, z)): in_bush = true
		if in_bush: continue
		var bare := maxf(track_cover(x, z), _mask_at(CH_WORN, x, z))
		var lush := _mask_at(CH_LUSH, x, z)
		var edge := out_dist(x, z)
		var beach := 1.0-smoothstep(1.2, 2.6, sd)
		# density: sparse in the open meadow, thick where nothing treads, none on bare earth
		var chance := 0.13+0.66*lush+(0.35 if not inside else 0.0)+0.25*smoothstep(3.0, 0.0, minf(z, 25.0-z) if inside else 0.0)
		chance *= pow(1.0-bare, 2.5)*(1.0-0.75*beach)
		if bare > 0.55 or roll > chance:
			# flat litter: pebbles on worn ground and the beach, the odd rosette in the meadow
			if roll > 0.985 and bare < 0.7 and beach < 0.5: decals.append([_flat(x, z, size*0.34, yaw), tint, _cell(3, 3)])
			elif roll > 0.955 and (beach > 0.3 or bare > 0.4): decals.append([_flat(x, z, size*0.45, yaw), Color(1, 1, 1), _cell(2, 3)])
			continue
		var cell := Color()
		var w := 0.42
		var h := 0.50
		if beach > 0.25:
			cell = _cell(2, 0, true) if pick < 0.7 else _cell(2, 2)           # sedge, thrift
			h = 0.50 if pick < 0.7 else 0.34
			w = 0.46 if pick < 0.7 else 0.34
			tint = tint*Color(1.0, 1.0, 0.95)
		elif not inside or edge > 0.0 or lush > 0.55:
			if pick < 0.50: cell = _cell(0, 0, true)
			elif pick < 0.62:
				cell = _cell(1, 0, true)
				h = 0.74
			elif pick < 0.80:
				cell = _cell(3, 2)                                               # fern
				w = 0.66
				h = 0.60
			elif pick < 0.92:
				cell = _cell(3, 0, true)                                         # dock
				w = 0.50
				h = 0.62
			else:
				cell = _cell(0, 2)
				w = 0.40
				h = 0.40
			size *= 1.0+0.25*lush
		else:
			if pick < 0.62: cell = _cell(0, 0, true)
			elif pick < 0.80:
				cell = _cell(1, 0, true)
				h = 0.70
			elif pick < 0.835:
				cell = _cell(0, 2)                                               # white umbels
				w = 0.38
				h = 0.38
			elif pick < 0.87:
				cell = _cell(1, 2)                                               # buttercups
				w = 0.36
				h = 0.36
			elif pick < 0.94: cell = _cell(0, 0, true)
			else:
				cell = _cell(3, 0, true)
				w = 0.46
				h = 0.52
			size *= 0.85
		var frame := Basis(Vector3.UP, yaw)*Basis.from_scale(Vector3(w*size, h*size, w*size))
		tufts.append([Transform3D(frame, Vector3(x, ground_y(x, z)-0.02, z)), tint, cell])
	# twigs and leaf litter under the trees that stand near the map
	for t: Dictionary in _trees:
		if bool(t.far) or out_dist(t.p.x, t.p.z) > 5.0 or int(t.kind) == Kind.SHRUB: continue
		for k: int in range(3):
			var a := r.randf()*TAU
			var d := r.randf_range(0.4, 1.9)
			var x: float = t.p.x+cos(a)*d
			var z: float = t.p.z+sin(a)*d
			var broad: bool = int(t.kind) in [Kind.BIRCH, Kind.BROADLEAF]
			var cell := _cell(1, 3) if (broad and k > 0) else _cell(0, 3)
			var size := r.randf_range(0.45, 0.8)
			var yaw := r.randf()*TAU
			if MAP.has_point(Vector2(x, z)) and sim.is_blocked(Vector2(x, z)*32.0, 4.0): continue
			if track_cover(x, z) > 0.3: continue
			decals.append([_flat(x, z, size, yaw), Color(1, 1, 1), cell])
	_add_cover(_upright_card_mesh(), tufts, "GroundCover")
	_add_cover(_flat_card_mesh(), decals, "GroundLitter")

func _flat(x: float, z: float, size: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw)*Basis.from_scale(Vector3(size, 1.0, size)), Vector3(x, ground_y(x, z)+0.025, z))

## Atlas cell of groundcover_atlas.png as (u, v, w, h). Columns are 128 px; `tall` cells span two rows.
func _cell(column: int, row: int, tall: bool = false) -> Color:
	return Color(column*0.25, row*0.25, 0.25, 0.5 if tall else 0.25)

func _upright_card_mesh() -> ArrayMesh:
	# three cards leaning outward round a hollow centre: reads as a clump from any yaw, never as a cross
	var b := Buf.new()
	for k: int in range(3):
		var a := TAU*float(k)/3.0+0.35
		var out := Vector3(cos(a), 0, sin(a))
		var side := out.cross(Vector3.UP)*0.5
		var foot := out*0.10
		var head := out*0.30+Vector3.UP
		var first := b.v.size()
		b.add(head-side, Vector3.UP, Vector2(0, 0), Color(1, 1, 1, 1.0))
		b.add(head+side, Vector3.UP, Vector2(1, 0), Color(1, 1, 1, 1.0))
		b.add(foot+side, Vector3.UP, Vector2(1, 1), Color(0.78, 0.78, 0.78, 0.0))
		b.add(foot-side, Vector3.UP, Vector2(0, 1), Color(0.78, 0.78, 0.78, 0.0))
		b.tri(first, first+1, first+2)
		b.tri(first, first+2, first+3)
	return b.mesh()

func _flat_card_mesh() -> ArrayMesh:
	var b := Buf.new()
	b.add(Vector3(-0.5, 0, -0.5), Vector3.UP, Vector2(0, 0), Color(1, 1, 1, 0))
	b.add(Vector3(0.5, 0, -0.5), Vector3.UP, Vector2(1, 0), Color(1, 1, 1, 0))
	b.add(Vector3(0.5, 0, 0.5), Vector3.UP, Vector2(1, 1), Color(1, 1, 1, 0))
	b.add(Vector3(-0.5, 0, 0.5), Vector3.UP, Vector2(0, 1), Color(1, 1, 1, 0))
	b.tri(0, 1, 2)
	b.tri(0, 2, 3)
	return b.mesh()

func _add_cover(mesh: Mesh, items: Array, label: String) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = items.size()
	for i: int in range(items.size()):
		multi.set_instance_transform(i, items[i][0])
		multi.set_instance_color(i, items[i][1])
		multi.set_instance_custom_data(i, items[i][2])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	node.material_override = _cover_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
