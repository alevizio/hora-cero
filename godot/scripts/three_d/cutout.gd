extends Node3D
## A paper cut-out: a figure made from a flat drawing (the art pack's, art_pack.gd), standing in the 3D world on a
## card that turns about the vertical to face the camera, cut out round its edge with a thick ink outline and a rim of
## white paper (shaders/cutout.gdshader). operative.gd keeps its invisible rig and every rule of the figure's life
## (walking, crouching, carrying, being carried, falling, hiding) and hands this the result each frame (pose()):
##  - walking, the card bobs at each step, rocks from foot to foot like a puppet and leans into the way it goes;
##  - it shows the drawing turned the way he walks (mirrored for the other way), the back view when he walks away from
##    the camera, the crouch drawing crouched and the drawing of him down when he lies, if the slot has them; without
##    them the front drawing is squashed for a crouch and laid flat on the ground for a fall;
##  - carried, it lies across the bearer's shoulder; in cover it is dulled.
## A slot with a model (.glb / .gltf) instead stands the model there, scaled to the slot's height, stood on the ground,
## its front ("forward") turned the way he walks, laid down when he falls (a creature rolls onto its side). A model with
## animations plays its own (idle, walk or run, crawl, crouch, down or death: by name, any case; a single one is the
## walk); a static one, as a fan's sculpt usually is, is moved here: a person steps, sways and leans into his walk and
## breathes standing still, a creature crawls (a quick low bob, a roll from side to side, a nod) and heaves at rest.
## A person whose model has a person's skeleton (Juan Salvo's) is moved on its own bones (rig_person.gd): its clips by his
## speed, and its bones turned for what they do not have (crouching, carrying someone, aiming and firing, knocked down
## and getting up), its prop (his rifle) kept in his hands; the flash of a shot comes from the prop's muzzle (muzzle()).
## A creature that is one piece (the cascarudo) is moved whole (creature_body.gd: its crawl, its rush, rearing over the
## one it knocks down, a stagger when shot, its death roll), its legs walked on the skeleton tools/art_pack.py
## rig-creature gave it (a tripod over the ground it has covered, its feet set down where they belong), and drawn from a
## lighter copy of itself (the slot's "lod", rigged alike) while the camera is far.
## A slot's "finish" ("cloth", "chitin") dresses a model for our night (shaders/art_model.gdshader; a beetle's carapace,
## shaders/art_chitin.gdshader): its own colours, its texture kept sharp, wet and snowed on as the night goes on
## (weather()), a cold rim against the snow.
## A slot whose art is not here yet shows the neutral stand-in, with its plate: LICENSED ART PENDING and the slot's name;
## a creature's with a length (length_m) is a plain grey block that size, lying the way it walks, its plate turned to
## the camera.
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const RigPerson = preload("res://scripts/three_d/rig_person.gd")
const CreatureBody = preload("res://scripts/three_d/creature_body.gd")
const ModelShader: Shader = preload("res://shaders/art_model.gdshader")
## A beetle's carapace (the finish "chitin"): its own shader, over the colours the rigging tool baked into the model.
const ChitinShader: Shader = preload("res://shaders/art_chitin.gdshader")
const CardShader: Shader = preload("res://shaders/cutout.gdshader")
const XrayShader: Shader = preload("res://shaders/cutout_xray.gdshader")
const MarkShader: Shader = preload("res://shaders/cutout_xray_mark.gdshader")
const Kit = preload("res://scripts/three_d/action_slot.gd")
const Lang = preload("res://scripts/lang.gd")
## The ink outline and the paper rim round a card, in metres for a figure of ordinary height (scaled by the root of
## its height: a giant's outline is thicker, not twelve times so).
const OUTLINE_M: float = 0.055
const RIM_M: float = 0.03
## A crouch drawing is shown this much of the standing height; without one the front drawing is squashed to it.
const CROUCH: float = 0.72
## A model with a lighter copy (the slot's "lod") is drawn from it once it is this few pixels long on screen (and from
## the full one again past a fifth more).
const LOD_PX: float = 150.0
## The finishes a slot may ask for (shaders/art_model.gdshader's settings): snow_high is the share of its height above
## which snow settles, snow_scale_m the size of its patches (per metre), snow_k how much of the night's snow stays on
## it (a creature on the move sheds some), ink_dark how much darker it is printed in comic ink.
const FINISHES := {
	# cloth, leather and canvas: matt, darker wet, the snow on the hood and shoulders; the atlas kept sharp
	"cloth": {"darken": 1.0, "tex_bias": -0.7, "roughness_dry": 0.86, "roughness_wet": 0.55, "specular_value": 0.32,
		"metallic_value": 0.0, "sky_fill": 0.22, "rim_color": Color(0.62, 0.72, 0.92), "rim_strength": 0.26, "rim_power": 3.0,
		"sheen": 0.0, "snow_up": 0.5, "wet_dark": 0.3, "snow_high": 0.7, "snow_scale_m": 9.0, "snow_k": 0.9},
	# a model that brings its own physical maps (colour, normal, occlusion-roughness-metal: Juan Salvo's blue-hood model):
	# each of its materials kept, read through the same shader for our night (its normal map and packed maps sampled as
	# they are), the snow on the hood and shoulders, wet as the night goes on; its glass left as it is
	"pbr": {"darken": 1.0, "tex_bias": -0.4, "roughness_dry": 0.8, "roughness_wet": 0.42, "specular_value": 0.42,
		"metallic_value": 0.0, "sky_fill": 0.22, "rim_color": Color(0.62, 0.72, 0.92), "rim_strength": 0.2, "rim_power": 3.0,
		"sheen": 0.0, "snow_up": 0.5, "wet_dark": 0.28, "snow_high": 0.7, "snow_scale_m": 9.0, "snow_k": 0.9},
	# a beetle's carapace (shaders/art_chitin.gdshader): a very dark olive-brown, polished on the crown, matte in the
	# joints, a thin-film sheen at grazing angles, worn edges, a cold rim against the snow, the snow dusting its back
	"chitin": {"shader": ChitinShader, "darken": 0.85, "under_dark": 0.3, "roughness_crown": 0.16, "roughness_joint": 0.78,
		"specular_value": 0.6, "film": 0.9, "wear": 1.0, "rim_color": Color(0.55, 0.7, 0.98), "rim_strength": 0.3,
		"rim_power": 3.0, "sheen": 0.4, "snow_up": 0.62, "snow_high": 0.45, "snow_scale_m": 4.5, "snow_k": 0.55, "ink_dark": 0.55},
}
const PAPER := Color(0.93, 0.91, 0.85)
const INK := Color(0.055, 0.05, 0.048)
const COVER := Color(0.56, 0.62, 0.52)

var slot: Dictionary = {}
var height_m: float = 1.75
var width_m: float = 0.6
## No art yet: the grey stand-in with its plate.
var pending: bool = false
var card: MeshInstance3D
var model: Node3D
var plate: Node3D
## view -> {"mesh", "material", "mark", "w", "h"}; the views a slot has: front always, back / crouch / down if drawn.
var views: Dictionary = {}
var view: String = ""
var flipped: bool = false
var from_back: bool = false
var _xray: bool = true
var _xray_tint := Color(0, 0, 0, 0)
var _tint := Color(1, 1, 1, 1)
var _anim: AnimationPlayer
var _model_scale: float = 1.0
## The turn that sets the model's front facing the way he walks (the slot's "forward").
var _turn: float = 0.0
## The stand-in block of a creature (its size, metres), or zero.
var block_size: Vector3 = Vector3.ZERO
## Half the width of a model or block across its front, metres: what a creature rolled onto its side rests on.
var _flank: float = 0.0
## What the model shows this frame: an animation of its own ("" for the procedural motion).
var playing: String = ""
## A person moved on his own skeleton (rig_person.gd), a creature moved whole (creature_body.gd); or null.
var rig: RigPerson
## The model's prop (his rifle) and whether the rig read it: shown or put away by show_prop().
var _prop_mesh: MeshInstance3D
var _prop_held: bool = false
var beast: CreatureBody
## The model's mesh drawn from its lighter copy while far (lod_far), and the two meshes.
var lod_far: bool = false
var _lod_node: MeshInstance3D
var _lod_near: Mesh
var _lod_mesh: Mesh
var _shadows: bool = true

## Materials by drawing and card size, shared by every figure of the same slot.
static var _materials: Dictionary = {}
## The finish materials (shaders/art_model.gdshader), shared by every figure of a slot, and the night's weather on them.
static var _finishes: Dictionary = {}
static var _snow: float = 0.0
static var _wet: float = 0.0

## Comic ink (ink.gd, through operative.gd ink_cues): no rim or sheen of light on the models (the drawing outlines them
## and its tone is cut from their brightness: a dark chitin is hatched dark, not lit to paper white).
static var _ink: bool = false
static func ink_mode(on: bool) -> void:
	_ink = on
	for m: Variant in _finishes.values():
		if is_instance_valid(m): _ink_look(m as ShaderMaterial)

static func _ink_look(m: ShaderMaterial) -> void:
	m.set_shader_parameter("rim_strength", 0.0 if _ink else float(m.get_meta("rim", 0.0)))
	m.set_shader_parameter("sheen", 0.0 if _ink else float(m.get_meta("sheen", 0.0)))
	m.set_shader_parameter("darken", float(m.get_meta("darken", 1.0)) * (float(m.get_meta("ink_dark", 1.0)) if _ink else 1.0))

## The night's snow on every model with a finish (0..1: none, as much as it holds) and how wet they are (0..1).
static func weather(snow_amount: float, wetness: float) -> void:
	if absf(snow_amount - _snow) < 0.002 and absf(wetness - _wet) < 0.002: return
	_snow = clampf(snow_amount, 0.0, 1.0)
	_wet = clampf(wetness, 0.0, 1.0)
	for m: Variant in _finishes.values():
		if not is_instance_valid(m): continue
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("snow", _snow * float(sm.get_meta("snow_k", 1.0)))
		sm.set_shader_parameter("wet", _wet)

func setup(s: Dictionary) -> void:
	slot = s
	height_m = float(s.get("height_m", 1.75))
	pending = not bool(s.get("ready", false))
	_turn = ArtPack.forward_turn(s)
	if not pending and bool(s.get("model", false)):
		var scene: PackedScene = ArtPack.model(str(s.file))
		if scene != null:
			_setup_model(scene)
			return
		pending = true
	if pending and str(s.get("kind", "")) == "creature" and float(s.get("length_m", 0.0)) > 0.0:
		_setup_block()
		return
	card = MeshInstance3D.new()
	card.name = "Card"
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.extra_cull_margin = 1.0
	add_child(card)
	var front: Dictionary = ArtPack.stand_in(str(s.kind)) if pending else ArtPack.drawing(str(s.file))
	if front.is_empty(): front = ArtPack.stand_in(str(s.kind))
	var aspect: float = float(front.aspect)
	width_m = height_m * aspect
	_add_view("front", front, height_m * aspect, height_m)
	if not pending:
		var v: Dictionary = s.get("views", {})
		var back: Dictionary = ArtPack.drawing(str(v.get("back", "")))
		if not back.is_empty(): _add_view("back", back, height_m * float(back.aspect), height_m)
		var crouch: Dictionary = ArtPack.drawing(str(v.get("crouch", "")))
		if not crouch.is_empty(): _add_view("crouch", crouch, height_m * CROUCH * float(crouch.aspect), height_m * CROUCH)
		var down: Dictionary = ArtPack.drawing(str(v.get("down", "")))
		if not down.is_empty():
			# drawn lying: its long side is his height
			var a: float = float(down.aspect)
			_add_view("down", down, height_m if a >= 1.0 else height_m * a, height_m / a if a >= 1.0 else height_m)
	_show("front")
	if pending:
		_tint = Color(1, 1, 1, 1)
		_build_plate()

func _add_view(name_: String, drawing: Dictionary, w: float, h: float) -> void:
	var k: float = sqrt(height_m / 1.75)
	var o: float = OUTLINE_M * k
	var r: float = RIM_M * k
	var m: float = o + r + 0.01
	var key: String = "%s|%d|%.3f|%.3f|%.3f" % [str(drawing.texture.get_instance_id()), int(pending), w, h, k]
	if not _materials.has(key):
		var card_m := ShaderMaterial.new()
		card_m.shader = CardShader
		var mark := ShaderMaterial.new()
		mark.shader = MarkShader
		var tint := ShaderMaterial.new()
		tint.shader = XrayShader
		mark.next_pass = tint
		# drawn before every x-ray and every blended ground layer, as the figures' marks are (operative.gd)
		mark.render_priority = -3
		for mat: ShaderMaterial in [card_m, mark, tint]:
			var used: Rect2 = drawing.used
			mat.set_shader_parameter("art", drawing.texture)
			mat.set_shader_parameter("used", Vector4(used.position.x, used.position.y, used.size.x, used.size.y))
			mat.set_shader_parameter("outline_uv", Vector2(o / w, o / h))
			mat.set_shader_parameter("rim_uv", Vector2(r / w, r / h))
		_materials[key] = [card_m, mark]
	var mats: Array = _materials[key]
	views[name_] = {"mesh": _quad(w, h, m), "material": mats[0], "mark": mats[1], "w": w, "h": h}

## The card: the drawing's rectangle w x h standing on its bottom edge, centred, with room round it for the outline.
static func _quad(w: float, h: float, m: float) -> ArrayMesh:
	var mx: float = m / w
	var my: float = m / h
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-w * 0.5 - m, -m, 0), Vector3(w * 0.5 + m, -m, 0), Vector3(w * 0.5 + m, h + m, 0), Vector3(-w * 0.5 - m, h + m, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-mx, 1.0 + my), Vector2(1.0 + mx, 1.0 + my), Vector2(1.0 + mx, -my), Vector2(-mx, -my)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _show(name_: String) -> void:
	if name_ == view or not views.has(name_): return
	view = name_
	var v: Dictionary = views[name_]
	card.mesh = v.mesh
	card.material_override = v.material
	card.material_overlay = v.mark if _xray else null
	card.set_instance_shader_parameter("flip", 1.0 if flipped else 0.0)
	card.set_instance_shader_parameter("tint", _tint)
	card.set_instance_shader_parameter("xray_tint", _xray_tint)

## The stand-in's plate on its chest: LICENSED ART PENDING and the slot's name, in ink on white paper with an ink edge.
func _build_plate() -> void:
	plate = Node3D.new()
	plate.name = "Plate"
	var person: bool = str(slot.get("kind", "person")) == "person"
	var pw: float = clampf(width_m * (1.5 if person else 0.86), 0.95, 3.2)
	if card != null:
		card.add_child(plate)
		plate.position = Vector3(0, height_m * (0.6 if person else 0.52), 0.035)
	else:
		# a block's plate: placed and turned to the camera every frame (pose())
		add_child(plate)
		pw = clampf(minf(block_size.z, height_m * 1.6), 0.95, 3.2)
	var ph: float = pw * 0.36
	for layer: int in range(2):
		var quad := QuadMesh.new()
		var edge: float = 0.035 * pw if layer == 0 else 0.0
		quad.size = Vector2(pw + edge * 2.0, ph + edge * 2.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = INK if layer == 0 else PAPER
		var node := MeshInstance3D.new()
		node.name = "PlateEdge" if layer == 0 else "PlatePaper"
		node.mesh = quad
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(0, 0, 0.004 * layer)
		plate.add_child(node)
	var head: String = tr("LICENSED ART PENDING")
	var who: String = ArtPack.display_name(slot, Lang.current)
	_line(head, Vector3(0, ph * 0.2, 0.012), pw * 0.9, ph * 0.24, 44)
	_line(who.to_upper(), Vector3(0, -ph * 0.17, 0.012), pw * 0.9, ph * 0.3, 60)

func _line(text: String, at: Vector3, max_w: float, max_h: float, px: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.font = Kit.face("semi", 1)
	label.font_size = px
	label.outline_size = 0
	label.modulate = INK
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# as large as fits the plate: a long name gets smaller letters
	var size: Vector2 = label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	label.pixel_size = minf(max_h / maxf(size.y, 1.0), max_w / maxf(size.x, 1.0))
	label.position = at
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(label)

# ------------------------------------------------------------------------------------------------ the frame
## Places the card (or the model) for this frame. `p` (from operative.gd):
##   root (Vector3, the figure's place, world), offset (root-space nudge toward a partner), yaw (where he faces),
##   phase (gait cycles walked), move (0..1), run (0..1), crouch (0..1), lie (0..1), carried (0..1) and carry (the
##   Rig's global transform while carried), hidden (0..1), covered (bool), clock (s), camera (Camera3D or null).
func pose(p: Dictionary) -> void:
	var cam: Camera3D = p.get("camera")
	var to_cam := Vector3(0, 0, 1)
	if cam != null:
		var z: Vector3 = cam.global_basis.z
		to_cam = Vector3(z.x, 0.0, z.z)
		to_cam = to_cam.normalized() if to_cam.length_squared() > 0.0001 else Vector3(0, 0, 1)
	var right: Vector3 = Vector3.UP.cross(to_cam).normalized()
	var yaw: float = float(p.yaw)
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	var side: float = facing.dot(right)
	var toward: float = facing.dot(to_cam)
	if model != null:
		_pose_model(p, yaw)
		if plate != null and card == null: _turn_plate(to_cam, right, yaw)
		return
	# which way the drawing looks, with a little hysteresis so it does not flicker walking straight at the camera
	var faces: String = str(slot.get("faces", "right"))
	var screen: float = -side if faces == "left" else side
	var flip: bool = flipped
	if screen < -0.18: flip = true
	elif screen > 0.18: flip = false
	if toward < -0.45: from_back = true
	elif toward > -0.2: from_back = false
	var lie: float = float(p.lie)
	var crouch: float = float(p.crouch)
	var want: String = "front"
	if lie > 0.5 and views.has("down"): want = "down"
	elif crouch > 0.55 and views.has("crouch"): want = "crouch"
	elif from_back and views.has("back"): want = "back"
	_show(want)
	if flip != flipped:
		flipped = flip
		card.set_instance_shader_parameter("flip", 1.0 if flip else 0.0)
	# --- the puppet's walk: a bob at each step, a rock from foot to foot, a lean into the way he goes
	var move: float = float(p.move)
	var cyc: float = float(p.phase) * TAU
	var h_scale: float = height_m / 1.75
	var bob: float = absf(sin(cyc)) * 0.035 * move * h_scale
	var dir: float = -1.0 if flipped else 1.0
	if faces == "left": dir = -dir
	var lean: float = -dir * (0.06 + 0.07 * float(p.run)) * move + sin(cyc) * 0.05 * move
	# breathing while he stands
	var clock: float = float(p.clock)
	var breath: float = 1.0 + 0.012 * sin(clock * 1.7) * (1.0 - move)
	# --- crouched: squashed and spread a little (unless there is a drawing of it)
	var squash: float = crouch if want != "crouch" else 0.0
	var sy: float = lerpf(1.0, CROUCH, squash) * breath
	var sx: float = lerpf(1.0, 1.07, squash)
	# --- down: the card falls back flat on the ground, face up, away from the camera
	var fall: float = lie * lie * (3.0 - 2.0 * lie)
	var face := Basis(right, Vector3.UP, to_cam)
	var b: Basis = Basis(right, -fall * PI * 0.5) * face * Basis(Vector3.BACK, lean * (1.0 - fall)) * Basis.from_scale(Vector3(sx, sy, 1.0))
	var hidden: float = float(p.hidden)
	var sink: float = 0.08 * hidden * h_scale if bool(p.get("covered", false)) else 0.0
	var origin: Vector3 = (p.root as Vector3) + (p.offset as Vector3) + Vector3(0, bob + 0.01 + 0.02 * fall - sink, 0)
	var own := Transform3D(b, origin)
	var carried: float = float(p.carried)
	if carried > 0.0:
		# over a shoulder: across the bearer, lying along the camera's right, a little smaller
		var rig: Transform3D = p.carry
		var hips: Vector3 = rig * Vector3(0, 0.95, 0)
		var across := Basis(to_cam, PI * 0.5 * dir) * face * Basis.from_scale(Vector3(0.9, 0.9, 1.0))
		var on := Transform3D(across, hips - across * Vector3(0, height_m * 0.5, 0) + Vector3(0, 0.12 * h_scale, 0))
		own = own.interpolate_with(on, carried * carried * (3.0 - 2.0 * carried))
	global_transform = own
	# --- in cover: dulled, as the modelled figures are
	var t: Color = Color(1, 1, 1, 1).lerp(COVER, clampf(hidden, 0.0, 1.0) * (0.85 if bool(p.get("covered", false)) else 0.45))
	if t != _tint:
		_tint = t
		card.set_instance_shader_parameter("tint", t)

## A model slot (or a creature's stand-in block): stood on the ground, its front turned the way he walks; laid down as he
## falls (a creature rolls onto its side); carried with the bearer. Its own animation for what he is doing if it has one,
## else the procedural motion (_motion).
func _pose_model(p: Dictionary, yaw: float) -> void:
	var lie: float = float(p.lie)
	var fall: float = lie * lie * (3.0 - 2.0 * lie)
	var creature: bool = str(slot.get("kind", "")) == "creature"
	if rig != null:
		_pose_rig(p, yaw, fall)
		return
	if beast != null:
		var body: Transform3D = beast.motion(p)
		var place := Transform3D(Basis(Vector3.UP, yaw), (p.root as Vector3) + (p.offset as Vector3))
		var own := Transform3D(Basis(Vector3.UP, _turn).scaled(Vector3.ONE * _model_scale), Vector3.ZERO)
		global_transform = place * body * own
		# its legs walk under it (the feet stay where they are put on the ground)
		beast.pose_legs(p, place * own, global_transform)
		_pick_lod(p.get("camera"))
		return
	playing = _play(p) if _anim != null else ""
	var m: Dictionary = _motion(p) if playing == "" else {"bob": 0.0, "roll": 0.0, "pitch": 0.0, "wiggle": 0.0, "breath": 1.0}
	var turned := Basis(Vector3.UP, yaw + float(m.wiggle))
	# down: a person tips back flat; a creature rolls over onto its side (about the way it faces) and settles
	var down: Basis = Basis(Vector3.FORWARD, fall * PI * 0.55) if creature else Basis(Vector3.RIGHT, -fall * PI * 0.5)
	var sway := Basis(Vector3.BACK, float(m.roll)) * Basis(Vector3.RIGHT, float(m.pitch))
	var b: Basis = turned * down * sway * Basis(Vector3.UP, _turn) * Basis.from_scale(Vector3(_model_scale, _model_scale * float(m.breath), _model_scale))
	var lift: float = float(m.bob) * (1.0 - fall)
	# rolled onto its side, it rests on its flank: half its width up
	if creature: lift += fall * _flank
	var own := Transform3D(b, (p.root as Vector3) + (p.offset as Vector3) + Vector3(0, lift, 0))
	var carried: float = float(p.carried)
	if carried > 0.0:
		var rig: Transform3D = p.carry
		var on := Transform3D(rig.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * _model_scale), rig * Vector3(0, 0.6, 0))
		own = own.interpolate_with(on, carried)
	global_transform = own

## A person on his own skeleton: his bones posed (rig_person.gd), the model stood where he is and turned his way. Knocked
## down, the skeleton lies him down itself; dead (no pose of its own for it), he tips back flat as any model does.
func _pose_rig(p: Dictionary, yaw: float, fall: float) -> void:
	rig.pose(p)
	var flat: float = 0.0 if float(p.get("down", 0.0)) > 0.5 or float(p.lie) < 0.3 else fall
	var b: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -flat * PI * 0.5) * Basis(Vector3.UP, _turn) * Basis.from_scale(Vector3.ONE * _model_scale)
	var own := Transform3D(b, (p.root as Vector3) + (p.offset as Vector3))
	var carried: float = float(p.carried)
	if carried > 0.0:
		var rig_xf: Transform3D = p.carry
		var on := Transform3D(rig_xf.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * _model_scale), rig_xf * Vector3(0, 0.6, 0))
		own = own.interpolate_with(on, carried)
	global_transform = own

## Where the flash of a shot is (world): a little past the muzzle of the prop in his hands; null without one.
func muzzle() -> Variant:
	if rig == null or not rig.has_prop: return null
	var tip: Vector3 = rig.muzzle_local()
	var butt: Vector3 = rig._g_prop * rig.butt_local
	var xf: Transform3D = rig.skel.global_transform
	return xf * tip + (xf.basis * (tip - butt)).normalized() * 0.06 * _model_scale

## The full mesh close up, the lighter copy far off: by how many pixels long the model is on screen.
func _pick_lod(cam: Variant) -> void:
	if _lod_node == null or _lod_mesh == null or not cam is Camera3D: return
	var c := cam as Camera3D
	var vp: Viewport = c.get_viewport()
	if vp == null: return
	var view_h: float = vp.get_visible_rect().size.y
	var px: float
	if c.projection == Camera3D.PROJECTION_ORTHOGONAL:
		px = width_m * view_h / maxf(c.size, 0.01)
	else:
		var dist: float = maxf(c.global_position.distance_to(global_position), 0.1)
		px = width_m * view_h / (2.0 * dist * tan(deg_to_rad(c.fov) * 0.5))
	var far: bool = lod_far
	if lod_far and px > LOD_PX * 1.2: far = false
	elif not lod_far and px < LOD_PX: far = true
	if far != lod_far:
		lod_far = far
		_lod_node.mesh = _lod_mesh if far else _lod_near

## Whether its model throws a shadow from the sky's light (off on the Plaza de Mayo, as every figure there).
func set_shadows(on: bool) -> void:
	_shadows = on
	if model == null: return
	for mi: MeshInstance3D in _model_meshes():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## The procedural motion of a model with no animation for what he is doing (a static sculpt, or the block): metres up
## (bob), radians of roll from side to side, of pitch (lean, nod) and of yaw (wiggle), and the breath (a height scale).
func _motion(p: Dictionary) -> Dictionary:
	var move: float = float(p.move)
	var cyc: float = float(p.phase) * TAU
	var clock: float = float(p.clock)
	var h: float = height_m / 1.75
	var still: float = 1.0 - move
	if str(slot.get("kind", "")) == "creature":
		# a crawl: many short steps, so a quick low bob and nod, the body rolling from side to side and its head
		# swinging a little; at rest it heaves slowly
		return {"bob": absf(sin(cyc * 2.0)) * 0.025 * h * move, "roll": sin(cyc) * 0.07 * move, "pitch": sin(cyc * 2.0 + 0.6) * 0.035 * move,
			"wiggle": sin(cyc + 0.4) * 0.06 * move, "breath": 1.0 + 0.02 * sin(clock * 1.25) * still}
	# a man's walk: a bob at each step, a sway from foot to foot, a lean into the way he goes; breathing standing still
	return {"bob": absf(sin(cyc)) * 0.035 * h * move, "roll": sin(cyc) * 0.045 * move, "pitch": (0.05 + 0.08 * float(p.run)) * move,
		"wiggle": 0.0, "breath": 1.0 + 0.012 * sin(clock * 1.7) * still}

## The model's own animation for what he is doing, if it has one (by name, any case; a single animation of any name is the
## walk, held still when he stops). Returns what it plays ("" for none: the procedural motion).
func _play(p: Dictionary) -> String:
	var names: PackedStringArray = _anim.get_animation_list()
	if names.is_empty(): return ""
	var move: float = float(p.move)
	var moving: bool = move > 0.3
	var creature: bool = str(slot.get("kind", "")) == "creature"
	var wants: Array = []
	if float(p.lie) > 0.5: wants = ["down", "death", "die", "dead"]
	elif float(p.crouch) > 0.55 and not creature: wants = ["crouch"]
	elif moving: wants = ["crawl", "walk", "run"] if creature else (["run", "walk"] if float(p.run) > 0.5 else ["walk", "run"])
	else: wants = ["idle"]
	var found: String = ""
	for want: Variant in wants:
		for name_: String in names:
			if name_.to_lower().contains(str(want)):
				found = name_
				break
		if found != "": break
	if found == "" and names.size() == 1 and moving and not wants.has("down"): found = names[0]
	if found == "":
		if names.size() == 1 and _anim.is_playing(): _anim.pause()
		return ""
	var looped: bool = not (wants.has("down") or wants.has("crouch"))
	var clip: Animation = _anim.get_animation(found)
	if clip != null and looped and clip.loop_mode == Animation.LOOP_NONE: clip.loop_mode = Animation.LOOP_LINEAR
	if _anim.current_animation != found or not _anim.is_playing(): _anim.play(found)
	_anim.speed_scale = lerpf(0.7, 1.4, clampf(move, 0.0, 1.0)) if moving else 1.0
	return found

## A creature's stand-in, while its art is not here: a plain grey block of the slot's size (width_m x height_m x
## length_m), its long side the way it walks, with an ink edge, and its plate (turned to the camera every frame).
func _setup_block() -> void:
	var length: float = float(slot.length_m)
	var wide: float = float(slot.get("width_m", 0.0))
	if wide <= 0.0: wide = minf(length, height_m) * 0.9
	block_size = Vector3(wide, height_m, length)
	width_m = maxf(wide, length)
	_flank = wide * 0.5
	_model_scale = 1.0
	model = Node3D.new()
	model.name = "Block"
	add_child(model)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = block_size
	body.mesh = box
	body.position = Vector3(0, height_m * 0.5, 0)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.6, 0.6, 0.585)
	grey.roughness = 0.95
	body.material_override = grey
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	model.add_child(body)
	# the ink edge: a little larger box, seen from inside
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	var edge := BoxMesh.new()
	var k: float = OUTLINE_M * sqrt(height_m / 1.75) * 1.6
	edge.size = block_size + Vector3.ONE * k * 2.0
	hull.mesh = edge
	hull.position = body.position
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = INK
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	hull.material_override = ink
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(hull)
	_build_plate()

## The block's plate: upright, turned to the camera, on the side of the block the camera sees, a little above its middle.
func _turn_plate(to_cam: Vector3, right: Vector3, yaw: float) -> void:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var reach: float = absf(to_cam.dot(fwd)) * block_size.z * 0.5 + absf(to_cam.dot(across)) * block_size.x * 0.5
	var centre: Vector3 = global_transform * Vector3(0, height_m * 0.5, 0)
	plate.global_transform = Transform3D(Basis(right, Vector3.UP, to_cam), Vector3(centre.x, maxf(centre.y, height_m * 0.25) + height_m * 0.05, centre.z) + to_cam * (reach + 0.08))

func _setup_model(scene: PackedScene) -> void:
	model = scene.instantiate() as Node3D
	if model == null:
		model = Node3D.new()
	model.name = "Model"
	add_child(model)
	# its size, from every mesh in it: scaled to the slot's height, standing on the ground, centred (or on its own origin)
	var box := AABB()
	var first: bool = true
	var meshes: Array[MeshInstance3D] = []
	var skeleton: Skeleton3D = null
	var pending_nodes: Array[Node] = [model]
	while not pending_nodes.is_empty():
		var n: Node = pending_nodes.pop_back()
		pending_nodes.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			meshes.append(mi)
			var to_model: Transform3D = model.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _local_to(mi, model)
			var b: AABB = to_model * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if n is AnimationPlayer and _anim == null: _anim = n
		if n is Skeleton3D and skeleton == null: skeleton = n
	_model_scale = height_m / maxf(box.size.y, 0.01) if not first else 1.0
	width_m = maxf(box.size.x, box.size.z) * _model_scale if not first else 0.6
	# across its front (the model turned by its "forward"): its flank, for lying on its side
	_flank = (box.size.z if absf(sin(_turn)) > 0.5 else box.size.x) * _model_scale * 0.5 if not first else 0.3
	if str(slot.get("origin", "")) != "model":
		for child: Node in model.get_children():
			if child is Node3D: (child as Node3D).position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	meshes.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return str(a.name) < str(b.name))
	var kind: String = str(slot.get("kind", "person"))
	# a person with a person's skeleton: moved on his bones, his prop in his hands
	if kind == "person" and RigPerson.fits(skeleton):
		var prop: MeshInstance3D = null
		for mi: MeshInstance3D in meshes:
			if str(slot.get("prop", "")) != "" and str(mi.name) == str(slot.prop): prop = mi
		rig = RigPerson.new(skeleton, slot, _anim, prop)
		_prop_mesh = prop
		_prop_held = rig.has_prop
		_anim = null
	if kind == "creature":
		var along: float = box.size.x if absf(sin(_turn)) > 0.5 else box.size.z
		var across: float = box.size.z if absf(sin(_turn)) > 0.5 else box.size.x
		beast = CreatureBody.new(along * _model_scale, box.size.y * _model_scale, across * _model_scale)
		# its own skeleton for its legs (tools/art_pack.py rig-creature): walked on them
		if skeleton != null:
			var front: Vector3 = Basis(Vector3.UP, -_turn) * Vector3(0, 0, 1)
			beast.attach(skeleton, _local_to(skeleton, self), front, _model_scale)
	# dressed for our night
	var finish: String = str(slot.get("finish", ""))
	if finish == "pbr":
		# each surface its own material through the finish (a model of many materials); see-through ones (its visor's
		# glass) as they come
		for mi: MeshInstance3D in meshes:
			for s: int in range(mi.mesh.get_surface_count()):
				var src: Material = mi.get_active_material(s)
				if src is BaseMaterial3D and (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
				mi.set_surface_override_material(s, _finish_material(mi, finish, box, s))
	elif FINISHES.has(finish):
		for mi: MeshInstance3D in meshes: mi.material_override = _finish_material(mi, finish, box)
	# one draw for the whole figure where its pieces share a skeleton and a material (and, dressed, where each part of it
	# stood at rest: the snow stays where it settled, however he moves)
	var rest_snow: bool = FINISHES.has(finish) and skeleton != null and kind == "person"
	meshes = _merge(meshes, rest_snow)
	if rest_snow and meshes.size() == 1 and meshes[0].material_override is ShaderMaterial and (meshes[0].mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0:
		(meshes[0].material_override as ShaderMaterial).set_shader_parameter("rest_snow", true)
	# a lighter copy for far off
	var lod_path: String = str(slot.get("lod", ""))
	if lod_path != "" and meshes.size() == 1:
		var low: PackedScene = ArtPack.model(lod_path)
		if low != null:
			var copy: Node = low.instantiate()
			var found: Array[Node] = copy.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				_lod_node = meshes[0]
				_lod_near = _lod_node.mesh
				_lod_mesh = (found[0] as MeshInstance3D).mesh
			copy.free()
	for mi: MeshInstance3D in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0

## A model's finish material, one per slot and source material: its colour and texture, the finish's settings.
func _finish_material(mi: MeshInstance3D, finish: String, box: AABB, surface: int = 0) -> ShaderMaterial:
	var src: Material = mi.get_active_material(surface)
	var key: String = "%s|%s|%d" % [str(slot.get("id", "")), finish, src.get_instance_id() if src != null else 0]
	if _finishes.has(key) and is_instance_valid(_finishes[key]): return _finishes[key]
	var m := ShaderMaterial.new()
	var spec: Dictionary = FINISHES[finish]
	m.shader = spec.get("shader", ModelShader)
	var tex: Texture2D = null
	var colour := Color.WHITE
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
		colour = (src as BaseMaterial3D).albedo_color
	for k: String in spec:
		if k in ["snow_high", "snow_scale_m", "snow_k", "ink_dark", "shader"]: continue
		m.set_shader_parameter(k, spec[k])
	if finish == "pbr" and src is BaseMaterial3D:
		# its own normal map and its packed occlusion (R), roughness (G) and metal (B)
		var b := src as BaseMaterial3D
		if b.normal_enabled and b.normal_texture != null:
			m.set_shader_parameter("use_normal", true)
			m.set_shader_parameter("normal_tex", b.normal_texture)
			m.set_shader_parameter("normal_depth", b.normal_scale)
		var orm: Texture2D = (src as ORMMaterial3D).orm_texture if src is ORMMaterial3D else b.roughness_texture
		if orm != null:
			m.set_shader_parameter("use_orm", true)
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("orm_ao", src is ORMMaterial3D or b.ao_enabled or orm.resource_path.get_file().contains("orm"))
		else:
			m.set_shader_parameter("roughness_dry", b.roughness)
			m.set_shader_parameter("metallic_value", b.metallic)
	m.set_shader_parameter("use_tex", tex != null)
	if tex != null: m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", colour)
	# heights and patch sizes in the model's own units
	m.set_shader_parameter("snow_from", box.position.y + box.size.y * float(spec.snow_high))
	m.set_shader_parameter("snow_scale", float(spec.snow_scale_m) * _model_scale)
	m.set_meta("snow_k", float(spec.snow_k))
	m.set_meta("rim", float(spec.rim_strength))
	m.set_meta("sheen", float(spec.sheen))
	m.set_meta("darken", float(spec.darken))
	m.set_meta("ink_dark", float(spec.get("ink_dark", 1.0)))
	if finish == "chitin":
		# what the rigging tool baked into it: its occlusion, convexity and underside, where it stood at rest
		var fmt: int = mi.mesh.surface_get_format(0) if mi.mesh != null else 0
		m.set_shader_parameter("has_bake", (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0 and (fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0)
		m.set_shader_parameter("crown_from", box.position.y + box.size.y * 0.72)
		m.set_shader_parameter("axis_y", box.position.y + box.size.y * 0.47)
		m.set_shader_parameter("model_scale", _model_scale)
	_ink_look(m)
	m.set_shader_parameter("snow", _snow * float(spec.snow_k))
	m.set_shader_parameter("wet", _wet)
	_finishes[key] = m
	return m

## The pieces of a model that share a skeleton (the same skin), a material and a vertex layout, as one mesh: one draw
## call for a whole figure instead of one per garment. Anything else is left as it is.
## With `rest`, each vertex also keeps where it stood at rest and how far up it faced (CUSTOM0: x, y, z, normal's y) for
## the snow on a skinned figure (shaders/art_model.gdshader rest_snow).
static func _merge(meshes: Array[MeshInstance3D], rest: bool = false) -> Array[MeshInstance3D]:
	if meshes.is_empty() or (meshes.size() < 2 and not rest): return meshes
	var first: MeshInstance3D = meshes[0]
	var mask: int = Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var format: int = first.mesh.surface_get_format(0) & mask
	var material: Material = first.material_override if first.material_override != null else first.get_active_material(0)
	for mi: MeshInstance3D in meshes:
		if mi.mesh.get_surface_count() != 1 or mi.get_parent() != first.get_parent() or mi.transform != first.transform: return meshes
		if (mi.mesh.surface_get_format(0) & mask) != format or mi.skeleton != first.skeleton: return meshes
		if (mi.material_override if mi.material_override != null else mi.get_active_material(0)) != material: return meshes
		if (mi.skin == null) != (first.skin == null) or (mi.skin != null and _binds(mi.skin) != _binds(first.skin)): return meshes
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0: return meshes
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var index := PackedInt32Array()
	var offset: int = 0
	for mi: MeshInstance3D in meshes:
		var a: Array = mi.mesh.surface_get_arrays(0)
		var count: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for k: int in range(Mesh.ARRAY_MAX):
			if k == Mesh.ARRAY_INDEX or a[k] == null: continue
			if arrays[k] == null: arrays[k] = a[k].duplicate()
			else: arrays[k].append_array(a[k])
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			for i: int in range(count): index.append(offset + i)
		else:
			for i: int in idx: index.append(offset + i)
		offset += count
	arrays[Mesh.ARRAY_INDEX] = index
	var flags: int = format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	if rest and arrays[Mesh.ARRAY_NORMAL] != null:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 4)
		for i: int in range(verts.size()):
			custom[i * 4] = verts[i].x
			custom[i * 4 + 1] = verts[i].y
			custom[i * 4 + 2] = verts[i].z
			custom[i * 4 + 3] = normals[i].y
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, first.get_active_material(0))
	var merged := MeshInstance3D.new()
	merged.name = "Body"
	merged.mesh = mesh
	merged.skin = first.skin
	merged.material_override = first.material_override
	first.get_parent().add_child(merged)
	merged.owner = first.owner
	merged.transform = first.transform
	merged.skeleton = first.skeleton
	for mi: MeshInstance3D in meshes:
		mi.get_parent().remove_child(mi)
		mi.free()
	return [merged]

static func _binds(skin: Skin) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in range(skin.get_bind_count()): out.append("%s|%d" % [skin.get_bind_name(i), skin.get_bind_bone(i)])
	return out

static func _local_to(node: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != top:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

# ------------------------------------------------------------------------------------------------ x-ray
## The prop shown or put away: a neighbour in the hooded survivor's clothes carries its rifle only once he has found a
## gun of his own; put away, the rig's hands no longer reach for it and the clip has his arms.
func show_prop(on: bool) -> void:
	if _prop_mesh == null or rig == null: return
	_prop_mesh.visible = on
	rig.has_prop = on and _prop_held

func use_xray(on: bool, figure_mark: Material) -> void:
	_xray = on
	if card != null:
		var want: Material = (views[view].mark if views.has(view) else null) if on else null
		if card.material_overlay != want: card.material_overlay = want
	elif model != null:
		for mi: MeshInstance3D in _model_meshes():
			mi.material_overlay = figure_mark if on else null

func set_xray(tint: Color) -> void:
	_xray_tint = tint
	if card != null:
		card.set_instance_shader_parameter("xray_tint", tint)
	elif model != null:
		for mi: MeshInstance3D in _model_meshes():
			mi.set_instance_shader_parameter("xray_tint", tint)

func _model_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var pending_nodes: Array[Node] = [model]
	while not pending_nodes.is_empty():
		var n: Node = pending_nodes.pop_back()
		pending_nodes.append_array(n.get_children())
		if n is MeshInstance3D and str(n.name) != "Hull": out.append(n)
	return out
