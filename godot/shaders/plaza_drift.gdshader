shader_type spatial;
// The snow banked against the walls round the Plaza de Mayo (plaza.gd, _build_drifts), grown with the night: every
// vertex knows the foot of its wall (UV2: x and z there), so as `grow` rises from 0 to 1 the bank swells out from the
// wall and up to its full height. Its toe fades (the vertex alpha, broken up by the macro noise) into the snow on the
// ground, so a bank never shows an edge of its own; the snow is the ground's (plaza_ground.gdshader), in world space.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 snow_tint : source_color = vec3(0.86, 0.87, 0.93);
uniform float grow = 1.0;

varying vec3 wpos;

void vertex() {
	// out from the wall and up: the bank's width comes before its height
	float out_k = clamp(0.3 + 0.7 * grow, 0.0, 1.0);
	float up_k = clamp(grow, 0.0, 1.0);
	VERTEX.xz = UV2 + (VERTEX.xz - UV2) * out_k;
	VERTEX.y *= up_k;
	NORMAL = normalize(vec3(NORMAL.x * up_k / out_k, NORMAL.y, NORMAL.z * up_k / out_k));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = texture(macro_tex, p * 0.013).r;
	float macro2 = texture(macro_tex, p * 0.051 + 0.37).g;
	float fine = texture(macro_tex, p * 0.7 + 0.11).b;
	vec3 snow = texture(snow_tex, p * 0.25).rgb * snow_tint * (0.92 + 0.1 * macro + 0.04 * macro2);
	// a bank in the open is whiter on its crest than the trodden ground round it
	ALBEDO = snow * (1.0 + 0.06 * COLOR.a);
	ALPHA = clamp(COLOR.a * (1.35 + 0.6 * (fine - 0.5)) - 0.15, 0.0, 1.0);
	NORMAL_MAP = texture(snow_nrm, p * 0.25).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.82;
	SPECULAR = 0.38;
}
