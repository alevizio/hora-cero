extends Node3D
## Comic ink ("Modo historieta"): the 3D view drawn as black ink on newsprint, the HUD left in colour. Two passes:
##  - shaders/ink_lines.gdshader, on a quad over the whole view, drawn first of the blended passes: outlines from the
##    depth and from hard brightness steps, the tone posterised into paper, hatching, cross-hatching and solid black,
##    the hatching anchored on the surfaces. It reads the screen and depth textures, which the Compatibility renderer
##    (the game's, and the web build's) provides to blended passes.
##  - shaders/ink_paper.gdshader, a canvas pass in place of the colour grade: the grey printed on warm paper with grain,
##    a halftone for the washes, and strong colour (sight cones, routes, markers) kept as a second printing colour.
## While it is on, the scene's tonemapper is set to pass the drawing through untouched (linear, exposure 1, white 1)
## and glow is off; switching it off puts them back as they were.
## Built by world.gd; main.gd turns it on and off (wanted(): the settings file, or a level or a build that asks for
## it). Its frame cost is one full-screen pass of 9 depth and 5 colour samples (5 and 3 on a phone) and one of three.
const LinesShader: Shader = preload("res://shaders/ink_lines.gdshader")
const PaperShader: Shader = preload("res://shaders/ink_paper.gdshader")
## Drawn before every other blended pass (the x-ray's stencil mark is at -3 and only marks the stencil).
const PRIORITY: int = -2
## The settings file's key (section "settings").
const SETTING: String = "ink"

var atmosphere: Node3D
var enabled: bool = false
var quad: MeshInstance3D
var lines_material: ShaderMaterial
var paper_layer: CanvasLayer
var paper_material: ShaderMaterial
var _saved: Dictionary = {}

## Whether this run should be drawn in ink: forced on by the level's data (`"ink": true`), by the export's custom
## feature "comic_ink" (tools/web_site_build.py --ink) or by HORACERO_INK=1 (0 forces it off for tools); otherwise
## the player's choice in Settings (off by default).
static func forced(data: Dictionary) -> int:
	var env: String = OS.get_environment("HORACERO_INK")
	if env == "1": return 1
	if env == "0": return 0
	if bool(data.get("ink", false)): return 1
	if OS.has_feature("comic_ink"): return 1
	return -1

static func wanted(data: Dictionary, progress: ConfigFile) -> bool:
	var f: int = forced(data)
	if f >= 0: return f == 1
	return progress != null and bool(progress.get_value("settings", SETTING, false))

## The look each kind of operation is printed with: night scenes lifted before the tone is cut, a darker or lighter key.
static func look_for(theme: String) -> Dictionary:
	match theme:
		"boca":
			return {"exposure": 1.25, "gamma": 1.0, "levels": Vector4(0.25, 0.33, 0.44, 0.57), "color_edge": 0.3, "light": 0.95}
		"snow":
			return {"exposure": 1.45, "gamma": 0.85, "levels": Vector4(0.10, 0.22, 0.36, 0.54), "color_edge": 0.3, "light": 0.95}
		"harbour":
			return {"exposure": 1.9, "gamma": 0.8, "levels": Vector4(0.10, 0.22, 0.36, 0.54), "color_edge": 0.3, "light": 0.95}
	# daylight: the greens lifted and the brightness steps of the foliage left alone, or the woods turn to scribble
	return {"exposure": 1.2, "gamma": 0.9, "levels": Vector4(0.1, 0.22, 0.36, 0.52), "color_edge": 0.5, "light": 0.97}

func build(theme: String) -> void:
	lines_material = ShaderMaterial.new()
	lines_material.shader = LinesShader
	lines_material.render_priority = PRIORITY
	var look: Dictionary = look_for(theme)
	lines_material.set_shader_parameter("exposure", float(look.exposure))
	lines_material.set_shader_parameter("gamma_k", float(look.gamma))
	lines_material.set_shader_parameter("levels", look.levels)
	lines_material.set_shader_parameter("color_edge", float(look.color_edge))
	lines_material.set_shader_parameter("light", float(look.light))
	# a phone draws it with fewer samples (no diagonal creases): what it costs is per pixel
	lines_material.set_shader_parameter("lite", OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad = MeshInstance3D.new()
	quad.name = "InkQuad"
	quad.mesh = mesh
	quad.material_override = lines_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the quad is placed by its vertex shader over the whole view: never culled
	quad.extra_cull_margin = 16384.0
	quad.ignore_occlusion_culling = true
	quad.visible = false
	add_child(quad)
	paper_layer = CanvasLayer.new()
	paper_layer.name = "InkPaper"
	paper_layer.layer = 0          # where the colour grade is: under the HUD (layer 1), which stays in colour
	paper_layer.visible = false
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_material = ShaderMaterial.new()
	paper_material.shader = PaperShader
	rect.material = paper_material
	paper_layer.add_child(rect)
	add_child(paper_layer)

func set_enabled(on: bool) -> void:
	if on == enabled: return
	enabled = on
	quad.visible = on
	paper_layer.visible = on
	if atmosphere != null:
		atmosphere.set("ink_on", on)
	var env: Environment = _environment()
	if env == null: return
	if on:
		_saved = {"tonemap_mode": env.tonemap_mode, "tonemap_exposure": env.tonemap_exposure, "tonemap_white": env.tonemap_white,
			"glow_enabled": env.glow_enabled}
		_hold(env)
	else:
		for key: String in _saved: env.set(key, _saved[key])
		_saved.clear()

## Every frame while on: keeps the tonemapper passing the drawing through (the closing scene's dawn moves the exposure).
func update() -> void:
	if not enabled: return
	var env: Environment = _environment()
	if env != null and (env.tonemap_exposure != 1.0 or env.tonemap_mode != Environment.TONE_MAPPER_LINEAR or env.glow_enabled):
		if env.tonemap_exposure != 1.0: _saved["tonemap_exposure"] = env.tonemap_exposure
		_hold(env)

func _hold(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.glow_enabled = false

func _environment() -> Environment:
	if atmosphere == null: return null
	var we: Variant = atmosphere.get("environment")
	if we is WorldEnvironment: return (we as WorldEnvironment).environment
	return null
