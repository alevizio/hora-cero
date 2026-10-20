shader_type spatial;
// A baked figure's hat and scarf (tools/mh/mhgear.py): the colour per vertex (COLOR; alpha 0 marks
// metal, such as a badge), the felt, twill or knit from a tiling detail texture and its normal map.
// UVs are in metres.
render_mode diffuse_lambert_wrap, cull_disabled;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 16.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float sky_fill : hint_range(0.0, 1.0) = 0.26;
uniform float sheen : hint_range(0.0, 0.5) = 0.18;
uniform vec3 tint : source_color = vec3(1.0);

varying float shade;

void vertex() {
	float up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
	shade = mix(1.0 - sky_fill, 1.0, up * 0.5 + 0.5);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	float metal = 1.0 - COLOR.a;
	float d = mix(texture(detail_tex, uv).r * 2.0, 1.0, metal);
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = COLOR.rgb * d * tint * shade * (1.0 + sheen * rim * rim * (1.0 - metal));
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), metal);
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(roughness_value, 0.32, metal);
	METALLIC = metal * 0.75;
	SPECULAR = mix(0.25, 0.6, metal);
}
