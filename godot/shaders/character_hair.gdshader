shader_type spatial;
// Hair, eyebrows and eyelashes of a baked figure: alpha-cut cards, recoloured to the man's hair.
render_mode diffuse_lambert_wrap, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 hair_color : source_color = vec3(0.16, 0.13, 0.10);
uniform float recolor : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(t.rgb, hair_color * (0.45 + 1.3 * lum), recolor) * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.45;
}
