extends SceneTree
## Dev-only: an art-pack creature's cards for the Figma kit, as the game dresses it (cutout.gd with its finish, posed
## by creature_body.gd): standing (prowl), seen from four sides (side, three quarter, top, front) by an orthographic
## camera under a three-light studio rig (a warm key from the upper left, a cool fill from the right, a rim from
## behind), on a transparent background (the kit lays them on its own grey stage). Each card is framed from a first
## render: the creature's outline measured and the camera fitted to it, the same share of the card each time.
## Run (rendered):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path godot --rendering-driver opengl3 \
##     --script ../tools/dev/creature_cards.gd -- <out dir> [slot] [width] [height]
## The cards go to <out dir>/<slot> - <view>.png.
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const DT: float = 1.0 / 30.0

## Each view: where the lens is (from the creature, its front +z, its left +x), how far up it looks down (degrees), and
## how much of the card's height and width the creature takes (the old cards' shares).
const VIEWS := [
	{"name": "side", "from": Vector3(-1.0, 0.0, 0.0), "down": 12.0, "h": 0.55, "w": 0.51},
	{"name": "three quarter", "from": Vector3(-1.0, 0.0, 1.0), "down": 20.0, "h": 0.63, "w": 0.53},
	{"name": "top", "from": Vector3(0.0, 1.0, 0.0), "down": 90.0, "h": 0.64, "w": 0.41},
	{"name": "front", "from": Vector3(0.0, 0.0, 1.0), "down": 15.0, "h": 0.66, "w": 0.6},
]

var vp: SubViewport
var cam: Camera3D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var slot_id: String = args[1] if args.size() > 1 else "cascarudo"
	var size := Vector2i(int(args[2]) if args.size() > 2 else 1200, int(args[3]) if args.size() > 3 else 900)
	DirAccess.make_dir_recursive_absolute(out)
	_stage(size)
	Cutout.weather(0.0, 0.0)
	var beast: Node3D = Cutout.new()
	vp.add_child(beast)
	beast.setup(ArtPack.slot(slot_id))
	beast.set_shadows(true)
	# standing, a moment into it (its breath, before it shifts a leg)
	var t: float = 0.0
	while t < 0.6:
		beast.pose({"root": Vector3.ZERO, "offset": Vector3.ZERO, "yaw": 0.0, "phase": 0.0, "move": 0.0, "run": 0.0,
			"crouch": 0.0, "lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false,
			"clock": t, "camera": cam, "speed": 0.0, "state": "prowl", "hits": 0})
		t += DT
	var centre := Vector3(0.0, 1.5, 0.3)
	for v: Dictionary in VIEWS:
		_aim(v, centre, 9.0)
		var first: Image = await _shot()
		var box: Rect2i = _outline(first)
		if box.size.x > 0:
			# fit: the outline's centre to the card's, its height (or width, if that is the tighter) to its share
			var px: float = cam.size / float(size.y)
			var mid := Vector2(box.position) + Vector2(box.size) * 0.5 - Vector2(size) * 0.5
			var b: Basis = cam.global_transform.basis
			cam.global_position += (b.x * mid.x - b.y * mid.y) * px
			var k: float = maxf(float(box.size.y) / (float(size.y) * float(v.h)), float(box.size.x) / (float(size.x) * float(v.w)))
			cam.size *= k
		var im: Image = await _shot()
		var path: String = out.path_join("%s - %s.png" % [slot_id, str(v.name)])
		im.save_png(path)
		print("card ", path, " ", im.get_size())
	quit()

## The stage: a transparent background, a soft grey studio ambient, the three lights (a low key, the rim strong: a
## dark glossy shell exposed for its highlights, as it reads in the game, its outline clear on the kit's grey), the
## orthographic lens.
func _stage(size: Vector2i) -> void:
	vp = SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.58, 0.6, 0.64)
	e.ambient_light_energy = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.72
	e.tonemap_white = 4.0
	env.environment = e
	vp.add_child(env)
	key = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 0.36
	key.shadow_enabled = true
	key.shadow_blur = 1.2
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 20.0
	vp.add_child(key)
	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.8, 0.95)
	fill.light_energy = 0.12
	vp.add_child(fill)
	rim = DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.95, 0.88)
	rim.light_energy = 1.3
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.1
	cam.far = 80.0
	cam.current = true
	vp.add_child(cam)

## The lens for a view (looking at `centre`, `size` metres high), the lights turned with it.
func _aim(v: Dictionary, centre: Vector3, size: float) -> void:
	var down: float = deg_to_rad(float(v.down))
	var from: Vector3 = v.from
	var up := Vector3.UP
	var dir: Vector3
	if from.y > 0.5:
		dir = Vector3.UP
		# from straight above, its front to the bottom of the card
		up = Vector3(0.0, 0.0, -1.0)
	else:
		var flat := Vector3(from.x, 0.0, from.z).normalized()
		dir = (flat * cos(down) + Vector3.UP * sin(down)).normalized()
	cam.global_position = centre + dir * 30.0
	cam.look_at(centre, up)
	cam.size = size
	var b: Basis = cam.global_transform.basis
	# the key from the upper left in front, the fill from the right, the rim from behind and above
	_point(key, b, Vector3(-0.8, 0.9, 0.7))
	_point(fill, b, Vector3(1.0, 0.1, 0.5))
	_point(rim, b, Vector3(0.4, 0.7, -1.0))

## A light shining from `toward` (the lens's own frame: x right, y up, z towards the lens).
func _point(l: DirectionalLight3D, b: Basis, toward: Vector3) -> void:
	var d: Vector3 = (b * toward).normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	l.global_transform = Transform3D(Basis.looking_at(-d, up), Vector3.ZERO)

func _shot() -> Image:
	for i: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()

## The creature's outline on a card: the box round what is not transparent.
func _outline(im: Image) -> Rect2i:
	var w: int = im.get_width()
	var h: int = im.get_height()
	var x0: int = w
	var y0: int = h
	var x1: int = -1
	var y1: int = -1
	for y: int in range(0, h, 2):
		for x: int in range(0, w, 2):
			if im.get_pixel(x, y).a > 0.1:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0: return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
