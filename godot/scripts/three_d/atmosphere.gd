extends Node3D
## Sun, sky ambient, tonemap and the finishing colour grade for the outpost: hazy, bright-overcast daylight.
## Built once by world.gd: add to the tree, then call build().
var sim: RefCounted
var sun: DirectionalLight3D
var environment: WorldEnvironment
## Night instead of overcast day (the harbour): moonlight, dark sky, a glow on the lamps and low height fog.
## Set before build().
var night: bool = false
## Night in the snow (Vemork): set with `night` before build(). The snow throws the moonlight back, so the night is
## paler and bluer than the harbour's, with a thin haze of falling snow instead of river mist.
var snow: bool = false
## La Boca under snow (Operation Riachuelo): set with `night` and `snow` before build(). Not the dead of night but the
## blue hour: a lavender sky that lights the snow, haze over the river and the far bank, the lamps and windows warm
## against it, and a slight tilt-shift on the finished picture.
var boca: bool = false
## Night only: dawn (0..1) for the closing scene; atmosphere.dawn = t moves sky and moon toward first light.
var dawn: float = 0.0:
	set(value):
		dawn = clampf(value, 0.0, 1.0)
		if night and environment != null: _apply_dawn()
var _night_settings: Environment
var _sky_material: ProceduralSkyMaterial
## Full-screen colour grade (one canvas pass under the HUD). Set false to disable it completely.
@export var grade_enabled: bool = true:
	set(value):
		grade_enabled = value
		if _grade_layer != null: _grade_layer.visible = value and not ink_on
## Comic ink (ink.gd) prints the picture in place of the grade: the grade's layer stays hidden while it is on.
var ink_on: bool = false:
	set(value):
		ink_on = value
		if _grade_layer != null: _grade_layer.visible = grade_enabled and not value

const GradeShader := preload("res://shaders/post_grade.gdshader")
## Tallest thing that can stand between the camera and the visible ground (forest trees), in metres.
const MAX_CASTER_HEIGHT := 12.5
var _grade_layer: CanvasLayer
var _fit_size: float = -1.0
var _fit_height: float = -1.0

func build() -> void:
	if night:
		_build_night()
		return
	environment = WorldEnvironment.new()
	var settings := Environment.new()
	# The camera never sees the horizon; the sky only feeds ambient light and reflections, so up-facing
	# surfaces get cool sky light, walls get the paler horizon and undersides get dim ground bounce.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.66, 0.71, 0.77)
	sky_material.sky_horizon_color = Color(0.80, 0.81, 0.79)
	sky_material.sky_curve = 0.25
	sky_material.ground_bottom_color = Color(0.20, 0.21, 0.17)
	sky_material.ground_horizon_color = Color(0.52, 0.53, 0.48)
	sky_material.ground_curve = 0.12
	sky_material.sun_angle_max = 0.0
	sky_material.use_debanding = false
	# In GL Compatibility the sky's own energy sets the ambient level (ambient_light_energy is not applied to it).
	sky_material.energy_multiplier = 0.75
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	settings.sky = sky
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.165, 0.205, 0.205)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_sky_contribution = 1.0
	settings.ambient_light_energy = 1.0
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 1.08
	settings.tonemap_white = 1.6
	environment.environment = settings
	add_child(environment)
	sun = DirectionalLight3D.new()
	# Low-ish south-westerly sun through thin cloud: soft but definite shadows falling toward +X / -Z.
	sun.rotation_degrees = Vector3(-47, -37, 0)
	sun.light_color = Color(1.0, 0.955, 0.86)
	sun.light_energy = 0.85
	sun.light_specular = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.92
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 95.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 30.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# The project default drops to hard shadows on mobile; ask for the cheap soft filter everywhere.
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	_build_grade()

## Moonlit harbour, a little after midnight: cold blue sky light, a hard moon from the south-west that throws
## long shadows, and every lamp left to make its own pool. Glow lifts the lamps and the searchlight.
func _build_night() -> void:
	environment = WorldEnvironment.new()
	var settings := Environment.new()
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = Color(0.085, 0.115, 0.190)
	_sky_material.sky_horizon_color = Color(0.130, 0.150, 0.200)
	_sky_material.sky_curve = 0.2
	_sky_material.ground_bottom_color = Color(0.020, 0.024, 0.030)
	_sky_material.ground_horizon_color = Color(0.060, 0.070, 0.090)
	_sky_material.ground_curve = 0.12
	_sky_material.sun_angle_max = 0.0
	_sky_material.use_debanding = false
	_sky_material.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	settings.sky = sky
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.012, 0.016, 0.024)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_sky_contribution = 1.0
	settings.ambient_light_energy = 1.0
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 1.35
	settings.tonemap_white = 3.0
	settings.glow_enabled = true
	settings.glow_intensity = 0.62
	settings.glow_strength = 1.0
	settings.glow_bloom = 0.0
	settings.glow_hdr_threshold = 0.9
	settings.glow_hdr_scale = 1.6
	settings.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: int in range(7): settings.set_glow_level(level, level in [1, 2, 3, 4])
	# Mist that pools low: the fog thickens toward the water and thins up the bunker face.
	settings.fog_enabled = true
	settings.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	settings.fog_light_color = Color(0.10, 0.13, 0.19)
	settings.fog_light_energy = 1.0
	settings.fog_density = 0.0
	settings.fog_height = 0.6
	settings.fog_height_density = 0.20
	settings.fog_sky_affect = 0.0
	settings.fog_aerial_perspective = 0.0
	environment.environment = settings
	_night_settings = settings
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Moon"
	# A high moon in the west-south-west: shadows fall north-east, away from the camera's side, and the ship's
	# quay side is left to the lamps.
	sun.rotation_degrees = Vector3(-50, -50, 0)
	sun.light_color = Color(0.64, 0.73, 0.96)
	sun.light_energy = 0.72
	sun.light_specular = 0.9
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 40.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if snow:
		_sky_material.sky_top_color = Color(0.10, 0.14, 0.24)
		_sky_material.sky_horizon_color = Color(0.18, 0.22, 0.30)
		_sky_material.ground_horizon_color = Color(0.16, 0.19, 0.25)
		_sky_material.ground_bottom_color = Color(0.10, 0.12, 0.16)
		settings.background_color = Color(0.03, 0.04, 0.065)
		settings.tonemap_exposure = 1.18
		settings.fog_light_color = Color(0.16, 0.2, 0.28)
		settings.fog_density = 0.004
		settings.fog_height = -2.0
		settings.fog_height_density = 0.06
		sun.light_color = Color(0.7, 0.8, 1.0)
		sun.light_energy = 0.62
		sun.rotation_degrees = Vector3(-42, -35, 0)
	if boca: _boca(settings)
	_build_grade()
	var material := (_grade_layer.get_child(0) as ColorRect).material as ShaderMaterial
	if boca:
		_boca_grade(material)
		return
	# Night grade: keep the blues in the darks, the lamps amber, a deeper vignette.
	material.set_shader_parameter("shadow_tint", Vector3(0.40, 0.48, 0.62))
	material.set_shader_parameter("highlight_tint", Vector3(0.60, 0.52, 0.40))
	material.set_shader_parameter("tint_amount", 0.16)
	material.set_shader_parameter("saturation", 0.92)
	material.set_shader_parameter("lift", 0.012)
	material.set_shader_parameter("vignette", 0.34)
	material.set_shader_parameter("contrast", 0.18)

## The blue hour over La Boca: the sky still holds a lavender light after sunset, so the snow carries the picture and
## the shadows stay blue, never black; a soft key from the south-west (low enough to model the fronts, its shadows
## light and soft); depth haze toward the far bank and mist lying on the river.
func _boca(settings: Environment) -> void:
	# a dusky sky, grey-violet rather than blue, low enough that the snow stays under the glow's threshold
	_sky_material.sky_top_color = Color(0.25, 0.26, 0.36)
	_sky_material.sky_horizon_color = Color(0.50, 0.48, 0.55)
	_sky_material.sky_curve = 0.18
	# the snow underfoot throws light back up: walls and soffits see a pale lower hemisphere
	_sky_material.ground_horizon_color = Color(0.54, 0.52, 0.60)
	_sky_material.ground_bottom_color = Color(0.48, 0.47, 0.55)
	_sky_material.energy_multiplier = 0.66
	settings.background_color = Color(0.30, 0.30, 0.38)
	# part of the ambient comes from every side alike: the walls get the snow's and the sky's glow, not only the roofs
	settings.ambient_light_color = Color(0.54, 0.54, 0.66)
	settings.ambient_light_sky_contribution = 0.42
	# ACES: the lamps and windows burn orange against snow that stays grey-white and blue
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = 0.58
	settings.tonemap_white = 6.0
	# bloom on what is brighter than the snow: lamps, lanterns, windows, fires (it works in Compatibility too)
	settings.glow_intensity = 1.3
	settings.glow_strength = 1.0
	settings.glow_bloom = 0.0
	settings.glow_hdr_threshold = 0.8
	settings.glow_hdr_scale = 2.0
	settings.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: int in range(7): settings.set_glow_level(level, level in [1, 2, 3, 4, 5])
	settings.fog_mode = Environment.FOG_MODE_DEPTH
	settings.fog_light_color = Color(0.42, 0.42, 0.50)
	settings.fog_light_energy = 1.0
	settings.fog_density = 0.6
	settings.fog_depth_begin = 60.0
	settings.fog_depth_end = 150.0
	settings.fog_depth_curve = 1.3
	settings.fog_height = -1.2
	settings.fog_height_density = 0.12
	settings.fog_sky_affect = 0.0
	sun.light_color = Color(0.80, 0.80, 0.92)
	sun.light_energy = 0.62
	sun.light_specular = 0.5
	sun.rotation_degrees = Vector3(-40, -20, 0)
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 2.0

## The grade for the blue hour: slate blue in the darks, amber in the lights, colour held back (a dusk, not a
## postcard), a firmer S, a vignette, and the miniature look: top and bottom soft (on this grade's own pass).
func _boca_grade(material: ShaderMaterial) -> void:
	material.set_shader_parameter("shadow_tint", Vector3(0.44, 0.43, 0.62))
	material.set_shader_parameter("highlight_tint", Vector3(0.62, 0.54, 0.46))
	material.set_shader_parameter("tint_amount", 0.18)
	material.set_shader_parameter("saturation", 0.82)
	# the darks never go black: a violet haze over them, as in the blue hour
	material.set_shader_parameter("lift", 0.09)
	material.set_shader_parameter("lift_color", Vector3(0.86, 0.84, 1.0))
	material.set_shader_parameter("vignette", 0.3)
	material.set_shader_parameter("contrast", 0.2)
	material.set_shader_parameter("grain", 0.012)
	material.set_shader_parameter("tilt_shift", 1.0)

## Seven in the morning, 12 December: an hour and a half before sunrise, so not daylight but the blue hour. The sky
## lifts from black to deep blue with a bruised glow low in the south-east, the moon gives way to that cold glow,
## and the fires and flashes of the closing scene own the picture.
func _apply_dawn() -> void:
	var t: float = dawn
	_sky_material.sky_top_color = Color(0.085, 0.115, 0.190).lerp(Color(0.12, 0.16, 0.28), t)
	_sky_material.sky_horizon_color = Color(0.130, 0.150, 0.200).lerp(Color(0.34, 0.29, 0.34), t)
	_sky_material.ground_horizon_color = Color(0.060, 0.070, 0.090).lerp(Color(0.13, 0.13, 0.17), t)
	_night_settings.background_color = Color(0.012, 0.016, 0.024).lerp(Color(0.05, 0.06, 0.09), t)
	_night_settings.fog_light_color = Color(0.10, 0.13, 0.19).lerp(Color(0.19, 0.21, 0.29), t)
	_night_settings.tonemap_exposure = lerpf(1.35, 1.3, t)
	sun.light_color = Color(0.64, 0.73, 0.96).lerp(Color(0.80, 0.72, 0.84), t)
	sun.light_energy = lerpf(0.72, 0.5, t)
	sun.rotation_degrees = Vector3(lerpf(-50.0, -14.0, t), lerpf(-50.0, 35.0, t), 0)

func _build_grade() -> void:
	_grade_layer = CanvasLayer.new()
	_grade_layer.name = "ColourGrade"
	_grade_layer.layer = 0          # the HUD lives on layer 1 and is drawn after this, untouched
	_grade_layer.visible = grade_enabled and not ink_on
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = GradeShader
	rect.material = material
	_grade_layer.add_child(rect)
	add_child(_grade_layer)

## Called every frame from world.update_visuals (dt is real time; paused = command mode).
## Fits the camera near plane and the sun's shadow range to what the orthographic camera can actually see,
## so the single 2048 shadow map is spent on the visible slab instead of the whole 0.1..95 m range.
func update(_dt: float, _paused: bool) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL: return
	var forward := -camera.global_transform.basis.z
	if forward.y > -0.2: return
	# Re-fit only when the zoom (or camera height) really changes: a stable range keeps shadow texels from crawling.
	if absf(camera.size-_fit_size) < _fit_size*0.015 and absf(camera.global_position.y-_fit_height) < 0.05: return
	_fit_size = camera.size
	_fit_height = camera.global_position.y
	var to_ground := camera.global_position.y/-forward.y                      # along the view axis, screen centre
	var spread := camera.size*0.5*sqrt(1.0-forward.y*forward.y)/-forward.y     # nearer / farther at screen bottom / top
	var tallest: float = MAX_CASTER_HEIGHT if not night else (52.0 if boca else (26.0 if snow else 21.0))     # the harbour's cranes and bunker roof; the mountain behind Vemork; the transporter bridge (and the road bridge's towers)
	camera.near = clampf(to_ground-spread-tallest/-forward.y-1.0, 0.1, to_ground*0.8)
	sun.directional_shadow_max_distance = to_ground+spread+3.0
	if boca and _grade_layer != null:
		# the miniature look grows with the view: hardly there close in, plain from high up
		var grade := (_grade_layer.get_child(0) as ColorRect).material as ShaderMaterial
		grade.set_shader_parameter("tilt_radius", lerpf(2.0, 5.0, smoothstep(24.0, 110.0, camera.size)))
