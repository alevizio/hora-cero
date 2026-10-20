extends SceneTree
## Dev-only: renders candidates for the game's icon from the friends' licensed cascarudo (the art pack's model, as
## cutout.gd and creature_body.gd pose and dress it) in the game's own scene: the Plaza de Mayo at night (the operation
## "plaza"), its lamps, its falling snow, the Casa Rosada far behind. Each candidate: a low lens close on its head and
## front claws, a warm lamp behind it on the edge of its shell, the cold night in front; the city beyond a few metres
## behind it drawn out of focus (the same view rendered small, without the creature, and spread on a screen behind it).
## Candidates D, E and F ("studio"): the same model and the game's own night (its sky's ambient light, its tone and
## glow) with only the creature in the picture, lit for a small size: warm sodium-amber lamps behind it tracing its
## whole outline (its shell's edge, its claws, its legs' tips), the cold of the night as a fill from the other side, a
## lamp's glints on its plates; behind it a backdrop drawn in the engine (deep navy to black, a soft cold glow behind it,
## a few big out-of-focus lamps), and snow falling (big soft flakes close to the lens, small ones behind it).
## Nothing is drawn or painted over the render. Run (rendered, square window):
##   xvfb-run -a -s "-screen 0 1280x1280x24" godot --path godot --rendering-driver opengl3 --resolution 1024x1024 \
##     --script ../tools/dev/creature_icon.gd -- <out dir> [candidate letters, e.g. ABC]
const Missions = preload("res://scripts/missions.gd")
const Cutout := preload("res://scripts/three_d/cutout.gd")
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const DT: float = 1.0 / 30.0
## The creature's own render layer (the blurred backdrop's camera leaves it out), the backdrop's.
const BEAST_LAYER: int = 1 << 18
const SCREEN_LAYER: int = 1 << 19
## The studio candidates' snowflakes.
const FLAKE_LAYER: int = 1 << 17

## Each candidate: name; the creature where (metres) and facing; its state and the seconds into it; the lens: where
## (from the creature's head, in its own frame: x its left, y up, z its front), field of view, the focus (metres from
## the lens, beyond which the city is out of focus); the warm lamp behind it (its own frame) and its strength.
const CANDIDATES := {
	# reared over someone, its claws up, the Casa Rosada's glow far behind
	"A": {"name": "claws raised", "at": Vector2(212.0, 72.0), "facing": -1.85, "state": "stay", "t": 1.25, "walk": 0.0,
		"lens": Vector3(-1.2, -1.3, 4.3), "aim": Vector3(0.0, 0.75, -0.5), "fov": 46.0, "focus": 9.0, "fill": 0.9,
		"rim": Vector3(1.8, 4.6, -3.0), "rim_energy": 11.0},
	# head on, low, lunging: the cold of the night behind it (looking north over the square)
	"B": {"name": "head on", "at": Vector2(190.0, 100.0), "facing": PI + 0.12, "state": "stalk", "t": 0.3, "walk": 0.0,
		"lens": Vector3(0.3, -1.15, 4.6), "aim": Vector3(0.0, -0.05, 0.0), "fov": 46.0, "focus": 9.0,
		"rim": Vector3(-1.5, 4.2, -3.0), "rim_energy": 11.0},
	# three-quarter, the lamp catching on its shell, lamps out of focus beyond
	"C": {"name": "shell in lamplight", "at": Vector2(178.0, 99.0), "facing": -2.35, "state": "prowl", "t": 2.0, "walk": 1.25,
		"lens": Vector3(-2.7, -1.0, 4.3), "aim": Vector3(-0.2, 0.2, -1.0), "fov": 46.0, "focus": 9.5,
		"rim": Vector3(-2.0, 4.6, -2.6), "rim_energy": 12.0},
	# --- the studio candidates (off the map, away from the square's lamps): lens as above; the amber lamps behind it
	# ([where, energy] in its own frame), the key lamp for the glints on its plates, the cold fill's energy; the
	# backdrop's glow where (the picture's 0..1, y down) and how strong, the big lamps out of focus behind it ([x, y,
	# radius, strength, warm 0..1])
	# head on from low down, claws open to the sides framing its shell, rushing
	"D": {"name": "head on, claws open", "style": "studio", "at": Vector2(-400.0, -400.0), "facing": PI, "state": "stalk",
		"t": 0.28, "walk": 0.0, "lens": Vector3(0.0, -1.1, 5.3), "aim": Vector3(0.0, 0.1, 0.0), "fov": 50.0,
		"lamps": [[Vector3(-4.6, 3.6, -1.6), 20.0], [Vector3(4.6, 3.4, -1.6), 20.0], [Vector3(0.0, 0.6, -3.4), 12.0],
			[Vector3(0.0, 5.6, -3.4), 14.0]],
		"key": [Vector3(0.6, 3.6, 2.2), 1.0], "fill": 0.6, "glow": Vector2(0.5, 0.45), "glow_k": 1.45,
		"bokeh": [[0.14, 0.2, 0.07, 0.5, 1.0], [0.86, 0.26, 0.05, 0.35, 1.0], [0.78, 0.1, 0.035, 0.25, 0.0]]},
	# rearing over the one it struck, its claws raised at the lens
	"E": {"name": "strike, claws raised", "style": "studio", "at": Vector2(-400.0, -400.0), "facing": PI, "state": "stay",
		"t": 1.0, "walk": 0.0, "lens": Vector3(0.2, -0.75, 2.9), "aim": Vector3(0.0, 0.55, 0.0), "fov": 60.0,
		"lamps": [[Vector3(-3.0, 5.0, -2.8), 19.2], [Vector3(3.0, 4.6, -2.8), 19.2], [Vector3(0.0, 0.8, -3.6), 12.0]],
		"key": [Vector3(-1.0, 4.4, 2.6), 0.8], "fill": 0.6, "glow": Vector2(0.5, 0.42), "glow_k": 1.3,
		"bokeh": [[0.13, 0.3, 0.06, 0.45, 1.0], [0.88, 0.16, 0.05, 0.35, 1.0], [0.84, 0.62, 0.04, 0.22, 0.0]]},
	# tight on its head and one claw, three-quarter
	"F": {"name": "head and claw", "style": "studio", "at": Vector2(-400.0, -400.0), "facing": PI, "state": "prowl",
		"t": 1.0, "walk": 0.0, "lens": Vector3(-2.3, -0.75, 2.4), "aim": Vector3(-0.45, -0.3, 0.4), "fov": 46.0,
		"lamps": [[Vector3(1.6, 4.4, -2.6), 21.6], [Vector3(-3.4, 3.2, -1.0), 9.0], [Vector3(0.5, 0.6, -2.4), 9.6]],
		"key": [Vector3(-2.6, 3.4, 2.6), 0.3], "fill": 0.45, "glow": Vector2(0.6, 0.4), "glow_k": 1.2,
		"bokeh": [[0.86, 0.18, 0.065, 0.5, 1.0], [0.15, 0.12, 0.04, 0.3, 1.0], [0.9, 0.7, 0.035, 0.2, 0.0]]},
}

var main: Node3D
var sim: RefCounted

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "ABC"
	DirAccess.make_dir_recursive_absolute(out)
	Missions.choose("plaza", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	main.world.adaptive_quality = false
	sim = main.sim
	main.hud.hints_enabled = false
	for i in range(3): await process_frame
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	main.hud.visible = false
	main.hud.overlay.hide()
	# three and a half minutes into the night: the snow lying and falling
	while float(sim.time) < 210.0:
		ff(2.0)
		for q: Dictionary in sim.people():
			q.exposure = minf(float(q.exposure), 0.3)
			q.panic = {}
		for u: Dictionary in sim.units: u.exposure = 0.0
	main.set_process(false)
	# nobody else in the picture: everyone moved off across the square, the game's figures and their marks hidden
	for q: Dictionary in sim.people() + sim.units:
		q.x = 60.0 * 32.0
		q.y = 60.0 * 32.0
		q.path = []
	ff(0.1)
	for id: Variant in main.world.actors: (main.world.actors[id] as Node3D).visible = false
	var marks: Variant = main.world.structures.get("creatures") if main.world.structures != null else null
	if marks != null and (marks as Node).get("marks") != null: (marks.marks as Node3D).visible = false
	main.world.draw_vision = false
	for letter: String in which.split(""):
		if not CANDIDATES.has(letter): continue
		await _render(letter, CANDIDATES[letter], out)
	Missions.choose("plaza", false)
	quit()

func _render(letter: String, c: Dictionary, out: String) -> void:
	if str(c.get("style", "")) == "studio":
		await _render_studio(letter, c, out)
		return
	var world3d: World3D = root.get_viewport().world_3d
	var holder := Node3D.new()
	main.world.add_child(holder)
	var beast: Node3D = Cutout.new()
	holder.add_child(beast)
	beast.setup(ArtPack.slot("cascarudo"))
	beast.set_shadows(true)
	for mi: MeshInstance3D in beast.call("_model_meshes"): mi.layers = BEAST_LAYER
	var at := Vector3((c.at as Vector2).x, 0.0, (c.at as Vector2).y)
	at.y = float(main.world.structures.call("ground_height", at.x, at.z)) if main.world.structures.has_method("ground_height") else 0.0
	var yaw: float = float(c.facing)
	var cam: Camera3D = main.camera
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = float(c.fov)
	cam.near = 0.2
	cam.cull_mask = cam.cull_mask | BEAST_LAYER | SCREEN_LAYER
	# play its state up to the moment (its legs walk if it walks)
	var t: float = 0.0
	var pos: Vector3 = at - Vector3(sin(yaw), 0.0, cos(yaw)) * float(c.walk) * float(c.t)
	var basis := Basis(Vector3.UP, yaw)
	var head: Vector3 = at + basis * Vector3(0.0, 1.5, 1.7)
	var lens: Vector3 = head + basis * (c.lens as Vector3)
	var aim: Vector3 = head + basis * (c.aim as Vector3)
	cam.global_position = lens
	cam.look_at(aim, Vector3.UP)
	# (first as it walks in, so its state starts now, not as if long under way)
	beast.pose({"root": pos, "offset": Vector3.ZERO, "yaw": yaw, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": cam, "speed": 0.0,
		"state": "prowl", "hits": 0})
	t = DT
	while t < float(c.t):
		pos += Vector3(sin(yaw), 0.0, cos(yaw)) * float(c.walk) * DT
		beast.pose({"root": pos, "offset": Vector3.ZERO, "yaw": yaw, "phase": 0.0, "move": 1.0 if float(c.walk) > 0.0 else 0.0, "run": 0.0,
			"crouch": 0.0, "lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t,
			"camera": cam, "speed": float(c.walk), "state": str(c.state), "hits": 0})
		t += DT
	# the warm lamp behind it, on the edge of its shell
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.72, 0.42)
	rim.light_energy = float(c.rim_energy)
	rim.omni_range = 14.0
	rim.omni_attenuation = 1.2
	rim.position = at + basis * (c.rim as Vector3)
	holder.add_child(rim)
	# the cold of the night in front of it
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.66, 1.0)
	fill.light_energy = float(c.get("fill", 0.35))
	holder.add_child(fill)
	fill.look_at_from_position(lens + Vector3(0, 3, 0), at + Vector3(0, 1, 0), Vector3.UP)
	# the city out of focus: the same view, small and without the creature, on a screen beyond the focus
	var focus: float = float(c.focus)
	var bg := SubViewport.new()
	bg.size = Vector2i(512, 512)
	bg.world_3d = world3d
	bg.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(bg)
	var bg_cam := Camera3D.new()
	bg.add_child(bg_cam)
	bg_cam.fov = cam.fov
	bg_cam.near = focus * 0.9
	bg_cam.far = 500.0
	bg_cam.cull_mask = cam.cull_mask & ~BEAST_LAYER & ~SCREEN_LAYER
	bg_cam.global_transform = cam.global_transform
	bg_cam.current = true
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var d: float = focus * 1.6
	var half: float = d * tan(deg_to_rad(cam.fov) * 0.5)
	quad.size = Vector2(half * 2.0, half * 2.0) * 1.02
	screen.mesh = quad
	screen.layers = SCREEN_LAYER
	var sm := ShaderMaterial.new()
	sm.shader = _blur_shader()
	sm.set_shader_parameter("view", bg.get_texture())
	screen.material_override = sm
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(screen)
	screen.position = Vector3(0, 0, -d)
	cam.far = d * 1.01
	cam.current = true
	for f: int in range(6):
		main.world.update_visuals(DT)
		await process_frame
	await RenderingServer.frame_post_draw
	var im: Image = root.get_viewport().get_texture().get_image()
	im.convert(Image.FORMAT_RGB8)
	var path: String = out.path_join("icon %s - %s.png" % [letter, str(c.name)])
	im.save_png(path)
	print("icon ", letter, " ", path, " ", im.get_size())
	bg.queue_free()
	screen.queue_free()
	holder.queue_free()
	cam.far = 400.0
	await process_frame

## A studio candidate: only the creature drawn (the camera sees its layer, the backdrop's and the flakes'), lit by our
## lamps alone (the square's own leave it out), in the game's night (its ambient light, its tone and glow).
func _render_studio(letter: String, c: Dictionary, out: String) -> void:
	var holder := Node3D.new()
	main.world.add_child(holder)
	var beast: Node3D = Cutout.new()
	holder.add_child(beast)
	beast.setup(ArtPack.slot("cascarudo"))
	beast.set_shadows(true)
	var meshes: Array = beast.call("_model_meshes")
	for mi: MeshInstance3D in meshes: mi.layers = BEAST_LAYER
	var at := Vector3((c.at as Vector2).x, 0.0, (c.at as Vector2).y)
	var yaw: float = float(c.facing)
	var basis := Basis(Vector3.UP, yaw)
	var cam: Camera3D = main.camera
	var cull: int = cam.cull_mask
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = float(c.fov)
	cam.near = 0.2
	cam.far = 60.0
	cam.cull_mask = BEAST_LAYER | SCREEN_LAYER | FLAKE_LAYER
	var head: Vector3 = at + basis * Vector3(0.0, 1.5, 1.7)
	var lens: Vector3 = head + basis * (c.lens as Vector3)
	cam.global_position = lens
	cam.look_at(head + basis * (c.aim as Vector3), Vector3.UP)
	cam.current = true
	# the square's own lights leave it alone: its light is ours (put back after; ours are on its layer, as a light the
	# camera does not see lights nothing)
	var lights: Array[Light3D] = []
	var masks: Array[int] = []
	for n: Node in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		lights.append(l)
		masks.append(l.light_cull_mask)
		l.light_cull_mask = l.light_cull_mask & ~BEAST_LAYER
	beast.pose({"root": at, "offset": Vector3.ZERO, "yaw": yaw, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": cam, "speed": 0.0,
		"state": "prowl", "hits": 0})
	var t: float = DT
	while t < float(c.t):
		beast.pose({"root": at, "offset": Vector3.ZERO, "yaw": yaw, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
			"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t, "camera": cam, "speed": 0.0,
			"state": str(c.state), "hits": 0})
		t += DT
	# the sodium-amber lamps behind it, tracing its outline
	for lamp: Array in c.lamps:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.6, 0.26)
		o.light_energy = float(lamp[1])
		o.omni_range = 12.0
		o.omni_attenuation = 1.0
		o.light_cull_mask = BEAST_LAYER
		o.layers = BEAST_LAYER
		o.position = at + basis * (lamp[0] as Vector3)
		holder.add_child(o)
	# a lamp's glints on its plates, from above and in front
	var key: Array = c.key
	var k := OmniLight3D.new()
	k.light_color = Color(1.0, 0.82, 0.62)
	k.light_energy = float(key[1])
	k.omni_range = 9.0
	k.light_cull_mask = BEAST_LAYER
	k.layers = BEAST_LAYER
	k.position = at + basis * (key[0] as Vector3)
	holder.add_child(k)
	# the cold of the night, filling from the other side
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = float(c.fill)
	fill.light_cull_mask = BEAST_LAYER
	fill.layers = BEAST_LAYER
	holder.add_child(fill)
	fill.look_at_from_position(lens + basis * Vector3(2.0, 2.5, 0.0), head, Vector3.UP)
	# the backdrop, far behind it
	var d: float = 40.0
	var half: float = d * tan(deg_to_rad(cam.fov) * 0.5)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(half * 2.0, half * 2.0) * 1.02
	screen.mesh = quad
	screen.layers = SCREEN_LAYER
	var sm := ShaderMaterial.new()
	sm.shader = _backdrop_shader()
	sm.set_shader_parameter("glow_at", c.glow)
	sm.set_shader_parameter("glow_color", Vector3(0.09, 0.17, 0.36) * float(c.get("glow_k", 1.0)))
	var spots: Array[Vector4] = []
	var tints: Array[Vector3] = []
	for b: Array in c.bokeh:
		spots.append(Vector4(float(b[0]), float(b[1]), float(b[2]), float(b[3])))
		tints.append(Vector3(1.0, 0.62, 0.3).lerp(Vector3(0.5, 0.66, 1.0), 1.0 - float(b[4])) * 0.7)
	sm.set_shader_parameter("bokeh", spots)
	sm.set_shader_parameter("bokeh_color", tints)
	sm.set_shader_parameter("bokeh_count", spots.size())
	screen.material_override = sm
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(screen)
	screen.position = Vector3(0, 0, -d)
	# the snow: small flakes behind it, big soft ones out of focus close to the lens (none over its middle)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(letter) + 7
	var flakes := Node3D.new()
	cam.add_child(flakes)
	var fm := ShaderMaterial.new()
	fm.shader = _flake_shader()
	for i: int in range(90):
		var near: bool = i < 12
		var depth: float = rng.randf_range(0.9, 2.2) if near else rng.randf_range(9.0, 26.0)
		var span: float = depth * tan(deg_to_rad(cam.fov) * 0.5)
		var u := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if near and u.length() < 0.55: u = u.normalized() * rng.randf_range(0.6, 0.95)
		var size: float = rng.randf_range(0.05, 0.09) if near else rng.randf_range(0.035, 0.07)
		var fl := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		fl.mesh = q
		fl.layers = FLAKE_LAYER
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: ShaderMaterial = fm.duplicate()
		# close to the lens: a soft disc, faint; far: small and crisp
		mat.set_shader_parameter("soft", 0.85 if near else 0.35)
		mat.set_shader_parameter("opacity", 0.45 if near else rng.randf_range(0.55, 0.9))
		fl.material_override = mat
		fl.position = Vector3(u.x * span, u.y * span, -depth)
		flakes.add_child(fl)
	for f: int in range(6):
		main.world.update_visuals(DT)
		await process_frame
	await RenderingServer.frame_post_draw
	var im: Image = root.get_viewport().get_texture().get_image()
	im.convert(Image.FORMAT_RGB8)
	var path: String = out.path_join("icon %s - %s.png" % [letter, str(c.name)])
	im.save_png(path)
	print("icon ", letter, " ", path, " ", im.get_size())
	for i: int in range(lights.size()):
		if is_instance_valid(lights[i]): lights[i].light_cull_mask = masks[i]
	screen.queue_free()
	flakes.queue_free()
	holder.queue_free()
	cam.far = 400.0
	cam.cull_mask = cull
	await process_frame

## The studio backdrop: deep navy to black, a soft cold glow behind the creature, a few big out-of-focus lamps, a fine
## grain so the gradient does not band.
func _backdrop_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 top_color = vec3(0.012, 0.024, 0.06);
uniform vec3 bottom_color = vec3(0.0, 0.0, 0.004);
uniform vec3 glow_color = vec3(0.09, 0.17, 0.36);
uniform vec2 glow_at = vec2(0.5, 0.45);
uniform float glow_size = 0.36;
uniform vec4 bokeh[6];
uniform vec3 bokeh_color[6];
uniform int bokeh_count = 0;
void fragment() {
	vec2 uv = UV;
	vec3 c = mix(top_color, bottom_color, smoothstep(0.1, 1.0, uv.y));
	float d = length(uv - glow_at);
	c += glow_color * exp(-d * d / (glow_size * glow_size));
	for (int i = 0; i < 6; i++) {
		if (i >= bokeh_count) break;
		float r = length(uv - bokeh[i].xy) / bokeh[i].z;
		float disc = (1.0 - smoothstep(0.6, 1.0, r)) * (0.85 + 0.15 * smoothstep(0.4, 0.9, r));
		c += bokeh_color[i] * bokeh[i].w * disc;
	}
	c *= 1.0 - 0.6 * smoothstep(0.4, 0.8, length(uv - vec2(0.5)));
	c += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 400.0;
	ALBEDO = max(c, vec3(0.0));
}
"""
	return s

## A snowflake: a disc, crisp or soft (out of focus), lit a cold white.
func _flake_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mix;
uniform float soft = 0.35;
uniform float opacity = 0.8;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = 1.0 - smoothstep(1.0 - soft, 1.0, r);
	ALBEDO = vec3(0.92, 0.94, 1.0);
	ALPHA = a * opacity;
}
"""
	return s

func _blur_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform sampler2D view : source_color, filter_linear, repeat_disable;
uniform float radius = 0.03;
// a wide soft blur: many taps on a spiral, turned at random from pixel to pixel (no pattern left in it)
void fragment() {
	vec2 uv = UV;
	float turn = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 96; i++) {
		float a = float(i) * 2.39996 + turn;
		float r = sqrt((float(i) + 0.5) / 96.0) * radius;
		acc += texture(view, clamp(uv + vec2(cos(a), sin(a)) * r, vec2(0.001), vec2(0.999))).rgb;
	}
	ALBEDO = acc / 96.0;
}
"""
	return s

func ff(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		sim.update(DT)
		main.world.update_visuals(DT)
