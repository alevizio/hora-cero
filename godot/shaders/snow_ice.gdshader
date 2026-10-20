shader_type spatial;
// The Mana at the bottom of the gorge in February: ice, drifted snow on it, and a black thread of open water where the
// current keeps it from freezing, moving under a skin of steam.
render_mode cull_back;

uniform sampler2D ice_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ice_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float center_z = 24.25;
uniform float open_width = 0.55;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.22;
	vec4 ice = texture(ice_tex, uv);
	float wander = (texture(macro_tex, vec2(wpos.x * 0.012, 0.3)).r - 0.5) * 3.2;
	float d = abs(wpos.z - center_z - wander);
	float open = 1.0 - smoothstep(open_width * 0.6, open_width, d);
	float ripple = texture(macro_tex, vec2(wpos.x * 0.3 - TIME * 0.35, wpos.z * 0.6)).g;
	vec3 water = vec3(0.012, 0.018, 0.024) + ripple * 0.02;
	ALBEDO = mix(ice.rgb * 0.85, water, open);
	NORMAL_MAP = mix(texture(ice_nrm, uv).rgb, vec3(0.5 + (ripple - 0.5) * 0.2, 0.5, 1.0), open);
	ROUGHNESS = mix(mix(0.35, 0.8, ice.a), 0.08, open);
	SPECULAR = mix(0.55, 0.6, open);
}
