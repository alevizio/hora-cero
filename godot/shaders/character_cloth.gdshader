shader_type spatial;
// A baked figure's clothes: the uniform's colour per vertex (COLOR), the weave, seams, folds and
// shading of the garment from its detail texture (grey, 0.5 = as dyed) and its normal map.
render_mode diffuse_lambert_wrap;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float sky_fill : hint_range(0.0, 1.0) = 0.26;
uniform float sheen : hint_range(0.0, 0.5) = 0.12;
uniform vec3 tint : source_color = vec3(1.0);
// an oilskin: how much the jacket's part (COLOR.a < 0.5) shines, like waxed cotton (0 for every other suit)
uniform float jacket_gloss : hint_range(0.0, 1.0) = 0.0;

varying float shade;

void vertex() {
	float up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
	shade = mix(1.0 - sky_fill, 1.0, up * 0.5 + 0.5);
}

void fragment() {
	float d = texture(detail_tex, UV).r * 2.0;
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = COLOR.rgb * d * tint * shade * (1.0 + sheen * rim * rim);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	float gloss = jacket_gloss * (1.0 - step(0.5, COLOR.a));
	ROUGHNESS = mix(roughness_value, 0.38, gloss);
	SPECULAR = mix(0.3, 0.55, gloss);
}
