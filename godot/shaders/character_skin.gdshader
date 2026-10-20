shader_type spatial;
// Textured parts of a baked figure (tools/mh/mhbake.py): skin, boots, eyes. Lit like the vertex-
// coloured kit (character_body.gdshader) so the two read as one figure.
render_mode diffuse_lambert_wrap;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 color_mul : source_color = vec3(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.62;
uniform float specular_value : hint_range(0.0, 1.0) = 0.35;
uniform float sky_fill : hint_range(0.0, 1.0) = 0.24;
uniform float sheen : hint_range(0.0, 0.5) = 0.08;
uniform vec3 tint : source_color = vec3(1.0);   // dulled for a body lying hidden in cover

varying float shade;

void vertex() {
	float up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
	shade = mix(1.0 - sky_fill, 1.0, up * 0.5 + 0.5);
}

void fragment() {
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = texture(albedo_tex, UV).rgb * color_mul * tint * shade * (1.0 + sheen * rim * rim);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
