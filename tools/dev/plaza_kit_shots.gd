extends SceneTree
## Dev-only: lays the whole Plaza de Mayo kit (scripts/three_d/plaza_kit.gd) out as a mock Plaza de Mayo at blue hour
## in the snow, under La Boca's atmosphere and grade, and photographs it: a hero shot (high oblique from the west, the
## Casa Rosada at the back, the Pirámide in the middle, the palms and the lamps), a close-up of each landmark and a
## line-up of the vehicles. Prints each builder's triangles and draw calls, and the frame's totals.
## Run (rendered, not headless):
##   cd godot && xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     --script ../tools/dev/plaza_kit_shots.gd -- <out dir> [shot ...]
## No shot names: every shot. The mock layout is not the level's (that is the level's own business): x east, z south,
## the square 150 x 90 m round the Pirámide at the origin.
const PlazaKit = preload("res://scripts/three_d/plaza_kit.gd")
const Atmosphere = preload("res://scripts/three_d/atmosphere.gd")
## The showcase's ground: La Boca's snow (boca_ground.gdshader) reworked for an overview: the snow's texture at two
## scales so its ripples never line up into a grid from high up, the slush and the setts on the streets, trodden paths.
const GROUND_CODE := """
shader_type spatial;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D slush_tex : filter_linear, repeat_disable;
uniform sampler2D rails_tex : filter_linear, repeat_disable;
uniform sampler2D occl_tex : filter_linear, repeat_disable;
uniform sampler2D road_tex : filter_linear, repeat_disable;
uniform sampler2D dir_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect;
uniform vec3 haze_color : source_color = vec3(0.5, 0.49, 0.58);
uniform vec3 snow_tint : source_color = vec3(0.89, 0.88, 0.93);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void fragment() {
	vec2 p = wpos.xz;
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	float slush = 0.0; float rails = 0.0; float occl = 0.0; float road = 0.0; float alongx = 0.0;
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		slush = texture(slush_tex, muv).r; rails = texture(rails_tex, muv).r; occl = texture(occl_tex, muv).r; road = texture(road_tex, muv).r;
		alongx = texture(dir_tex, muv).r;
	}
	float m1 = texture(macro_tex, p * 0.011).r;
	float m2 = texture(macro_tex, p * 0.047 + 0.37).g;
	float fine = texture(macro_tex, p * 0.31 + 0.11).b;
	vec3 s1 = texture(snow_tex, p * 0.11).rgb;
	vec3 s2 = texture(snow_tex, vec2(p.y, -p.x) * 0.037 + 0.5).rgb;
	vec3 snow = mix(s1, s2, 0.55) * snow_tint * (0.9 + 0.1 * m1 + 0.05 * m2);
	vec2 suv = p * 0.5;
	vec3 setts = texture(setts_tex, suv).rgb;
	float lum = dot(setts, vec3(0.333));
	vec3 stone = mix(setts * vec3(0.5, 0.51, 0.56), vec3(0.36, 0.37, 0.43), 0.45);
	stone = mix(stone, snow * 0.86, smoothstep(0.42, 0.28, lum) * 0.75);
	vec3 crust = texture(packed_tex, p * 0.22).rgb * vec3(0.88, 0.88, 0.93);
	// the traffic's tyre tracks along the streets: two wet dark bands a lane, the setts showing through
	float across = mix(p.x, p.y, alongx) + (fine - 0.5) * 0.35 + (m2 - 0.5) * 0.6;
	float lane = fract(across / 3.4);
	float tracks = (smoothstep(0.1, 0.0, abs(lane - 0.27)) + smoothstep(0.1, 0.0, abs(lane - 0.73))) * road;
	float cover = clamp(smoothstep(0.2, 0.6, m2 * 0.5 + fine * 0.35 + (1.0 - road) * 0.5 + 0.48) - tracks * 0.75, 0.0, 1.0);
	vec3 trodden = mix(stone, crust, cover);
	trodden = mix(mix(snow * vec3(0.84, 0.86, 0.94), crust * 1.05, 0.45 + 0.3 * fine), trodden, road);
	float s = clamp(slush * (0.85 + 0.3 * m2), 0.0, 1.0);
	vec3 col = mix(snow, trodden, s);
	col = mix(col, stone * 0.7, rails * 0.8);
	col *= 1.0 - 0.38 * occl;
	float haze = smoothstep(150.0, 320.0, length(p));
	ALBEDO = mix(col, haze_color, haze);
	NORMAL_MAP = mix(texture(snow_nrm, p * 0.11).rgb, mix(texture(setts_nrm, suv).rgb, vec3(0.5, 0.5, 1.0), cover * 0.7), s);
	NORMAL_MAP_DEPTH = mix(0.35, 1.0, s);
	float wet = s * road * (1.0 - cover) + rails;
	ROUGHNESS = mix(0.82, 0.3, clamp(wet, 0.0, 1.0));
	SPECULAR = mix(0.38, 0.6, clamp(wet, 0.0, 1.0));
	vec2 cell = floor(p * 38.0);
	float h = hash(cell);
	vec3 face = normalize(vec3(hash(cell + 3.1) - 0.5, 1.2, hash(cell + 7.7) - 0.5));
	vec3 vn = normalize((VIEW_MATRIX * vec4(face, 0.0)).xyz);
	EMISSION = vec3(0.75, 0.82, 1.0) * step(0.93, h) * pow(max(dot(vn, VIEW), 0.0), 60.0) * 0.5 * (1.0 - s) * (1.0 - haze);
}
"""

var world: Node3D
var atm: Node3D
var cam: Camera3D
var pk: PlazaKit
var lights_node: Node3D
var out_dir := ""
## The roads (slush, setts showing) and the trodden paths of the square, the buildings' footprints, the tram rails.
var roads: Array[Rect2] = []
var paths: Array[Rect2] = []
var blocks: Array[Rect2] = []
var rails: Array[Rect2] = []
var holes: Array[Rect2] = []
## Nodes some shots hide (a front between the camera and its subject), by name.
var named: Dictionary = {}
const HIDE := {"colectivo_door": ["front1"], "lineup_transit": ["front1"], "vehicles_top": ["front1"]}
const MASK := Rect2(-280.0, -200.0, 560.0, 400.0)

## name: [target, yaw (deg, the camera's bearing from the target as in the game), pitch (deg), ortho size (0 = a
## perspective lens), distance, fov]
const SHOTS := {
	"hero": [Vector3(16, 3, 0), -90.0, 25.0, 0.0, 132.0, 40.0],
	"hero_ortho": [Vector3(14, 0, -4), -90.0, 36.0, 118.0, 320.0, 0.0],
	"hero_high": [Vector3(4, 0, -6), -125.0, 50.0, 150.0, 320.0, 0.0],
	"casa_rosada": [Vector3(80, 10, 0), -90.0, 12.0, 0.0, 105.0, 46.0],
	"casa_rosada_arch": [Vector3(73, 8, 0), -78.0, 9.0, 0.0, 38.0, 40.0],
	"piramide": [Vector3(0, 9, 0), -90.0, 7.0, 0.0, 30.0, 42.0],
	"cabildo": [Vector3(-80, 8, 2), 70.0, 12.0, 0.0, 56.0, 42.0],
	"catedral": [Vector3(-36, 12, -58), 20.0, 12.0, 0.0, 82.0, 46.0],
	"banco": [Vector3(42, 12, -58), -20.0, 14.0, 0.0, 90.0, 46.0],
	"ministerios": [Vector3(0, 14, 56), 170.0, 14.0, 0.0, 95.0, 46.0],
	"avenida": [Vector3(-140, 8, -23), 88.0, 5.0, 0.0, 60.0, 50.0],
	"belgrano": [Vector3(48, 5.2, 0), -62.0, 8.0, 0.0, 17.0, 40.0],
	"belgrano_close": [Vector3(48, 6.4, 0), -55.0, 6.0, 0.0, 8.0, 40.0],
	"furniture": [Vector3(-53, 1.8, -20), -140.0, 20.0, 0.0, 20.0, 46.0],
	"lawn": [Vector3(-40, 1.0, 18), -120.0, 25.0, 0.0, 18.0, 46.0],
	"vehicles": [Vector3(-130, 1.4, -17.5), 107.0, 11.0, 0.0, 30.0, 46.0],
	"car_close": [Vector3(-134.5, 0.9, -16.8), 140.0, 12.0, 0.0, 8.0, 40.0],
	"taxi_close": [Vector3(-127.5, 0.9, -16.8), 215.0, 12.0, 0.0, 7.5, 40.0],
	"saloon_close": [Vector3(-121.0, 0.8, -16.8), 140.0, 12.0, 0.0, 6.5, 40.0],
	"truck_close": [Vector3(-113.0, 1.2, -17.0), 210.0, 14.0, 0.0, 10.0, 40.0],
	"lineup_cars": [Vector3(-122, 0.9, -17), 175.0, 10.0, 0.0, 20.0, 40.0],
	"lineup_transit": [Vector3(-151, 1.8, -20.5), 22.0, 8.0, 0.0, 21.0, 44.0],
	"colectivo_door": [Vector3(-143.5, 1.3, -16.9), -30.0, 9.0, 0.0, 10.0, 44.0],
	"subte": [Vector3(-55.5, 1.6, -24), 200.0, 22.0, 0.0, 9.0, 44.0],
	"kiosk": [Vector3(-56, 1.4, 12), 70.0, 12.0, 0.0, 8.0, 42.0],
	"vehicles_top": [Vector3(-133, 0, -19), 20.0, 48.0, 34.0, 120.0, 0.0],
}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://plaza_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var wanted: Array = []
	for i: int in range(1, args.size()): wanted.append(args[i])
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	atm = Atmosphere.new()
	atm.night = true
	atm.snow = true
	atm.boca = true
	world.add_child(atm)
	atm.build()
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	seed(1958)
	var t0 := Time.get_ticks_msec()
	pk = PlazaKit.new(world, 1.0, 0.55, 1958)
	_layout()
	pk.finish()
	print("built in %d ms" % (Time.get_ticks_msec() - t0))
	_ground()
	_report()
	for name: String in SHOTS:
		if not wanted.is_empty() and not name in wanted: continue
		await _shot(name, SHOTS[name])
	quit()

# ---------------------------------------------------------------------------------------------------------------
# The mock square
# ---------------------------------------------------------------------------------------------------------------
func _layout() -> void:
	# the square (x -58..58, z -38..38) and its streets: Balcarce (east), Rivadavia (north), Hipólito Yrigoyen (south),
	# Bolívar (west), Avenida de Mayo running west from the square's west side, north of the Cabildo
	roads = [Rect2(60, -130, 10, 260), Rect2(-240, -50, 310, 10), Rect2(-240, 40, 310, 10), Rect2(-70, -130, 10, 260), Rect2(-240, -32, 172, 18)]
	rails = [Rect2(-240, -24.94, 172, 0.44), Rect2(-240, -23.5, 172, 0.44)]
	paths = [Rect2(-58, -5, 116, 10), Rect2(-5, -38, 10, 76), Rect2(-58, -38, 116, 4.5), Rect2(-58, 33.5, 116, 4.5), Rect2(-58, -38, 4, 76), Rect2(54, -38, 4, 76),
		Rect2(-31, -38, 3.5, 76), Rect2(27.5, -38, 3.5, 76)]
	var casa := Rect2(73, -48, 38, 96)
	var cabildo := Rect2(-91, -10, 18, 24)
	var catedral := Rect2(-58, -112, 44, 60)
	var banco := Rect2(12, -98, 60, 46)
	var minis := Rect2(-40, 52, 80, 30)
	for r: Rect2 in [casa, cabildo, catedral, banco, minis]: blocks.append(r)
	pk.casa_rosada(casa, PlazaKit.WEST)
	pk.cabildo(cabildo, PlazaKit.EAST)
	pk.catedral(catedral, PlazaKit.SOUTH)
	pk.banco_nacion(banco, PlazaKit.SOUTH)
	pk.ministerios(minis, PlazaKit.NORTH)
	# Avenida de Mayo's two sides, and the city round the square (the same fronts)
	var fronts: Array = [[Rect2(-240, -50, 168, 16), PlazaKit.SOUTH], [Rect2(-240, -14, 147, 16), PlazaKit.NORTH],
		[Rect2(-14, -68, 26, 16), PlazaKit.SOUTH], [Rect2(-150, -112, 80, 16), PlazaKit.SOUTH],
		[Rect2(40, 52, 32, 16), PlazaKit.NORTH], [Rect2(-72, 52, 32, 16), PlazaKit.NORTH], [Rect2(-170, 52, 98, 16), PlazaKit.NORTH],
		[Rect2(-91, 16, 18, 24), PlazaKit.EAST], [Rect2(72, -130, 40, 16), PlazaKit.SOUTH]]
	var sd := 11
	for fr: Array in fronts:
		blocks.append(fr[0])
		named["front%d" % (sd / 7 - 1)] = pk.avenida_de_mayo(fr[0], fr[1], true, sd)
		sd += 7
	pk.piramide(Vector3(0, 0, 0), PlazaKit.EAST)
	pk.belgrano(Vector3(48, 0, 0), PlazaKit.WEST)
	# the lawns behind their hoops, four a side of the cross of paths
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for span: Vector2 in [Vector2(8.0, 26.0), Vector2(32.0, 52.0)]:
				var x0 := span.x if sx > 0.0 else -span.y
				var z0 := 7.5 if sz > 0.0 else -32.5
				pk.lawn(Rect2(x0, z0, span.y - span.x, 25.0), true)
	# the eight palms, flanking the Pirámide in the lawns
	var i := 0
	for x: float in [-21.0, -12.5, 12.5, 21.0]:
		for z: float in [-14.0, 14.0]:
			pk.palm(Vector3(x, 0, z + (2.0 if absf(x) > 15.0 else -2.0) * signf(z)), 1.0 + 0.07 * sin(float(i) * 2.3))
			i += 1
	# the lamps along the paths
	for x: float in [-44.0, -22.0, 22.0, 44.0]:
		for z: float in [-6.0, 6.0]:
			pk.lamp_post(Vector3(x, 0, z), 4)
	for z: float in [-26.0, -14.0, 14.0, 26.0]:
		for x: float in [-6.0, 6.0]:
			pk.lamp_post(Vector3(x, 0, z), 4)
	for x: float in [-56.0, -29.0, 29.0, 56.0]:
		pk.lamp_post(Vector3(x, 0, -36.0), 4)
		pk.lamp_post(Vector3(x, 0, 36.0), 4)
	# plane trees along the square's edges, benches by the paths
	for x: float in [-50.0, -42.0, -36.0, -22.0, -14.0, 14.0, 22.0, 36.0, 42.0, 50.0]:
		pk.plane_tree(Vector3(x, 0, -35.8), 0.9)
		pk.plane_tree(Vector3(x + 2.0, 0, 35.8), 0.85)
	for x: float in [-38.0, -16.0, 16.0, 38.0]:
		pk.bench(Vector3(x, 0, -5.4), 0.0)
		pk.bench(Vector3(x, 0, 5.4), PI)
	# the children's snowmen in the lawns, and the trails trodden across them
	for sm: Vector3 in [Vector3(-40, 0.1, 19), Vector3(17, 0.1, -24), Vector3(40, 0.1, 24), Vector3(-17, 0.1, -25), Vector3(-44, 0.1, -18)]:
		pk.snowman(sm, randf_range(0.9, 1.1))
	for t: PackedVector2Array in [PackedVector2Array([Vector2(-58, 30), Vector2(-42, 21), Vector2(-40, 19.5), Vector2(-29, 10)]),
			PackedVector2Array([Vector2(8, -6), Vector2(14, -18), Vector2(17, -23.5), Vector2(25, -33)]),
			PackedVector2Array([Vector2(31, 8), Vector2(38, 18), Vector2(40, 23), Vector2(50, 33)]),
			PackedVector2Array([Vector2(-27, -6), Vector2(-20, -16), Vector2(-17, -24), Vector2(-9, -33)]),
			PackedVector2Array([Vector2(-54, -8), Vector2(-46, -15), Vector2(-44, -17.5)])]:
		pk.trail(t, 0.12)
	# the Subte's stairs by the mouth of Avenida de Mayo, a kiosk, the flagpole
	var subte := Rect2(-57.0, -30.0, 3.0, 7.5)
	holes.append(subte)
	pk.subte_entrance(subte, PlazaKit.SOUTH)
	pk.kiosk(Vector3(-56.0, 0, 12.0), PlazaKit.EAST)
	pk.flagpole(Vector3(40.0, 0, -16.0), 14.0, PlazaKit.SOUTH)
	# the traffic: cars parked along Balcarce, a taxi rank on Bolívar by the Cabildo, a colectivo on Rivadavia
	var kinds := ["sedan", "saloon", "sedan", "sedan", "saloon", "sedan"]
	for j: int in range(6):
		pk.car(Vector3(62.2, 0, -30.0 + float(j) * 6.4), PI, kinds[j])
	pk.car(Vector3(-67.8, 0, -6.0), PI, "taxi", Color(0, 0, 0, 0), [1], true, false)
	pk.car(Vector3(-67.8, 0, 0.5), PI, "taxi")
	pk.car(Vector3(-67.8, 0, 7.0), PI, "taxi")
	pk.colectivo(Vector3(-30.0, 0, -47.6), -PI * 0.5, Color(0, 0, 0, 0), Color(0, 0, 0, 0), true, false)
	pk.car(Vector3(-12.0, 0, -42.5), PI * 0.5, "sedan", Color(0, 0, 0, 0), [], true, false)
	pk.truck(Vector3(26.0, 0, -47.8), -PI * 0.5)
	# the line-up on Avenida de Mayo, before the cafés: the tram on its rails, the colectivo at its stop, the cars,
	# the soda truck (all heading east, at the south kerb, as the traffic kept to the right)
	pk.tram(Vector3(-160.0, 0, -24.0), PI * 0.5)
	pk.colectivo(Vector3(-145.0, 0, -16.9), PI * 0.5, Color(0, 0, 0, 0), Color(0, 0, 0, 0), true, true)
	pk.car(Vector3(-134.5, 0, -16.8), PI * 0.5, "sedan", PlazaKit.hexc("3e5a46"), [0])
	pk.car(Vector3(-127.5, 0, -16.8), PI * 0.5, "taxi", Color(0, 0, 0, 0), [], true, false)
	pk.car(Vector3(-121.0, 0, -16.8), PI * 0.5, "saloon", PlazaKit.hexc("d8cfb4"))
	pk.truck(Vector3(-113.0, 0, -17.0), PI * 0.5, Color(0, 0, 0, 0), true)
	pk.car(Vector3(-104.5, 0, -16.8), PI * 0.5, "sedan", PlazaKit.hexc("4a1c1a"), [], false, false)

# ---------------------------------------------------------------------------------------------------------------
# The ground: La Boca's snow (boca_ground.gdshader) with this layout's masks
# ---------------------------------------------------------------------------------------------------------------
func _mask(list: Array[Rect2], soft: float) -> ImageTexture:
	var img := Image.create(1024, 1024, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	for r: Rect2 in list:
		var p := (r.position - MASK.position) / MASK.size * 1024.0
		var s := r.size / MASK.size * 1024.0
		img.fill_rect(Rect2i(int(p.x), int(p.y), maxi(1, int(ceil(s.x))), maxi(1, int(ceil(s.y)))), Color.WHITE)
	var px := int(round(soft / MASK.size.x * 1024.0))
	if px > 0:
		img.resize(1024 / (px + 1), 1024 / (px + 1), Image.INTERPOLATE_BILINEAR)
		img.resize(1024, 1024, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(img)

func _ground() -> void:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_CODE
	m.shader = sh
	m.set_shader_parameter("snow_tex", load("res://assets/tex/snow/snow_a.png"))
	m.set_shader_parameter("snow_nrm", load("res://assets/tex/snow/snow_n.png"))
	m.set_shader_parameter("packed_tex", load("res://assets/tex/boca/slush_a.png"))
	m.set_shader_parameter("setts_tex", load("res://assets/tex/harbour/setts_a.png"))
	m.set_shader_parameter("setts_nrm", load("res://assets/tex/harbour/setts_n.png"))
	m.set_shader_parameter("macro_tex", load("res://assets/tex/nature/macro_noise.png"))
	var slush: Array[Rect2] = []
	slush.append_array(roads)
	slush.append_array(paths)
	m.set_shader_parameter("slush_tex", _mask(slush, 1.2))
	m.set_shader_parameter("rails_tex", _mask(rails, 0.4))
	m.set_shader_parameter("occl_tex", _mask(blocks, 2.0))
	m.set_shader_parameter("road_tex", _mask(roads, 0.5))
	var along: Array[Rect2] = []
	for r: Rect2 in roads:
		if r.size.x > r.size.y: along.append(r)
	m.set_shader_parameter("dir_tex", _mask(along, 0.3))
	m.set_shader_parameter("mask_rect", Vector4(MASK.position.x, MASK.position.y, 1.0 / MASK.size.x, 1.0 / MASK.size.y))
	m.set_shader_parameter("haze_color", Color(0.5, 0.49, 0.58))
	m.set_shader_parameter("snow_tint", Color(0.89, 0.88, 0.93))
	# 40 m pieces (no piece lit by more lamps than the renderer takes), the Subte's stairwells left open
	var x := -400.0
	while x < 400.0:
		var z := -320.0
		while z < 320.0:
			var cell := Rect2(x, z, 40.0, 40.0)
			if absf(x) > 240.0 or absf(z) > 200.0: cell = Rect2(x, z, 40.0, 40.0)
			_land(cell, m)
			z += 40.0
		x += 40.0

func _land(cell: Rect2, m: ShaderMaterial) -> void:
	for h: Rect2 in holes:
		if cell.intersects(h):
			# split round the hole
			var parts: Array[Rect2] = [Rect2(cell.position.x, cell.position.y, h.position.x - cell.position.x, cell.size.y),
				Rect2(h.end.x, cell.position.y, cell.end.x - h.end.x, cell.size.y),
				Rect2(h.position.x, cell.position.y, h.size.x, h.position.y - cell.position.y),
				Rect2(h.position.x, h.end.y, h.size.x, cell.end.y - h.end.y)]
			for p: Rect2 in parts:
				if p.size.x > 0.01 and p.size.y > 0.01: _land(p, m)
			return
	var mesh := PlaneMesh.new()
	mesh.size = cell.size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(cell.get_center().x, 0.0, cell.get_center().y)
	world.add_child(node)

# ---------------------------------------------------------------------------------------------------------------
# Shots
# ---------------------------------------------------------------------------------------------------------------
func _shot(name: String, s: Array) -> void:
	for key: String in named: (named[key] as Node3D).visible = not key in HIDE.get(name, [])
	var target: Vector3 = s[0]
	var yaw := deg_to_rad(float(s[1]))
	var pitch := deg_to_rad(float(s[2]))
	var size: float = s[3]
	var dist: float = s[4]
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)
	if size > 0.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
		cam.near = maxf(1.0, dist - 260.0)
		cam.far = dist + 260.0
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = float(s[5])
		cam.near = 0.3
		cam.far = 900.0
	var env: Environment = (atm.environment as WorldEnvironment).environment
	# a perspective lens sees the horizon: let the sky go into the same haze as the far ground
	env.background_color = Color(0.36, 0.355, 0.43) if size <= 0.0 else Color(0.30, 0.30, 0.38)
	env.fog_sky_affect = 0.85 if size <= 0.0 else 0.0
	env.fog_depth_begin = dist * 0.75 if size > 0.0 else maxf(60.0, dist * 0.9)
	env.fog_depth_end = dist + 180.0 if size > 0.0 else dist + 220.0
	atm.sun.directional_shadow_max_distance = dist + (size if size > 0.0 else 120.0)
	_place_lights(target, 14 if size > 0.0 else 10)
	var grade := ((atm.get("_grade_layer") as CanvasLayer).get_child(0) as ColorRect).material as ShaderMaterial
	grade.set_shader_parameter("tilt_radius", 2.6 if size > 0.0 else 6.0)
	grade.set_shader_parameter("tilt_shift", 1.0 if size > 0.0 else 0.35)
	for i: int in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot %s: draw calls %d, objects %d, primitives %d" % [name, calls, objects, prims])

## Real lights for the lamps nearest the shot's target (the rest are halos and pools on the snow only).
func _place_lights(target: Vector3, count: int) -> void:
	if lights_node != null: lights_node.free()
	lights_node = Node3D.new()
	world.add_child(lights_node)
	var list: Array = pk.lights.duplicate()
	list.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector3).distance_squared_to(target) < (b[0] as Vector3).distance_squared_to(target))
	for i: int in range(mini(count, list.size())):
		var l: Array = list[i]
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = 4.0 * float(l[2])
		o.omni_range = float(l[3]) * 1.3
		o.omni_attenuation = 1.6
		o.shadow_enabled = false
		lights_node.add_child(o)

func _report() -> void:
	var keys: Array = pk.stats.keys()
	keys.sort()
	for key: String in keys:
		var s: Dictionary = pk.stats[key]
		print("budget %-18s %3d built, %7d triangles, %3d draws, %3d meshes%s" % [key, int(s.count), int(s.triangles), int(s.draws), int(s.meshes), (", %d instances" % int(s.instances)) if int(s.instances) > 0 else ""])
	var t: Dictionary = pk.totals()
	print("budget TOTAL %d triangles, %d draws (before shadows)" % [int(t.triangles), int(t.draws)])
