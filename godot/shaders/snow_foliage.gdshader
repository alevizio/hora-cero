shader_type spatial;
// Spruce and pine under snow: the outpost's alpha cut-out foliage (nature_foliage.gdshader), with snow lying on every
// bough that faces up (by the card's hand-set volume normal) and the dark green showing beneath and inside.
// Vertex COLOR.rgb = baked depth shading (x per-instance tint), COLOR.a = wind weight (0 = rigid).
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float wind_amp = 0.02;
uniform float wrap = 0.45;
uniform float brightness = 0.55;
uniform float mip_bias = -0.6;
uniform float snow_amount = 1.0;
uniform vec3 snow_color : source_color = vec3(0.80, 0.85, 0.93);
uniform vec4 map_rect = vec4(0.0, 0.0, 64.0, 52.0);
uniform vec3 haze_color : source_color = vec3(0.05, 0.065, 0.10);

varying float snow_lie;
varying float haze;
varying vec3 wpos;

void vertex() {
	float ph = VERTEX.x * 0.37 + VERTEX.z * 0.29;
	float sway = sin(TIME * 1.15 + ph) * 0.6 + sin(TIME * 2.7 + ph * 2.3) * 0.4;
	VERTEX += vec3(0.8, 0.12, 0.6) * (sway * wind_amp * COLOR.a);
	snow_lie = smoothstep(0.4, 0.95, NORMAL.y) * 0.9;
	wpos = VERTEX;
	vec2 outside = max(max(map_rect.xy - VERTEX.xz, VERTEX.xz - map_rect.zw), vec2(0.0));
	haze = smoothstep(16.0, 72.0, length(outside)) * 0.9;
}

void fragment() {
	vec4 t = texture(atlas, UV, mip_bias);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float n = texture(macro_tex, wpos.xz * 0.7 + wpos.y * 0.3).r;
	float s = clamp(snow_lie * snow_amount * (0.75 + 0.6 * n), 0.0, 1.0);
	vec3 green = t.rgb * COLOR.rgb * brightness;
	vec3 col = mix(green, snow_color * (0.75 + 0.3 * COLOR.r), smoothstep(0.35, 0.75, s));
	ALBEDO = mix(col, haze_color, haze);
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.9;
	SPECULAR = mix(0.12, 0.3, s);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
