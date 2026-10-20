shader_type spatial;
// Rock under snow: the walls of the gorge, boulders on the plateau, the mountain behind the plant. The rock texture
// is laid on by world position (whichever axis the face looks along), snow lies on every ledge that faces up, and
// the gorge darkens and turns blue toward its floor, where the moon hardly reaches.
render_mode cull_back;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 snow_color : source_color = vec3(0.84, 0.88, 0.95);
uniform vec3 rock_tint : source_color = vec3(0.62, 0.62, 0.64);
uniform float scale = 0.32;
uniform float depth_dark = 9.0;       // metres below the ground at which the gorge is darkest
uniform vec4 map_rect = vec4(0.0, 0.0, 64.0, 52.0);
uniform vec3 haze_color : source_color = vec3(0.05, 0.065, 0.10);
uniform float fade = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = y * 4 + x;
	float m = 0.0;
	if (i == 0) m = 0.0; else if (i == 1) m = 8.0; else if (i == 2) m = 2.0; else if (i == 3) m = 10.0;
	else if (i == 4) m = 12.0; else if (i == 5) m = 4.0; else if (i == 6) m = 14.0; else if (i == 7) m = 6.0;
	else if (i == 8) m = 3.0; else if (i == 9) m = 11.0; else if (i == 10) m = 1.0; else if (i == 11) m = 9.0;
	else if (i == 12) m = 15.0; else if (i == 13) m = 7.0; else if (i == 14) m = 13.0; else m = 5.0;
	return (m + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) discard;
	vec3 an = abs(wnrm);
	vec2 uv = an.x > an.z ? wpos.zy : wpos.xy;
	if (an.y > 0.75) uv = wpos.xz;
	uv *= scale;
	vec3 rock = texture(rock_tex, uv).rgb * rock_tint * COLOR.rgb;
	float n = texture(macro_tex, wpos.xz * 0.11 + wpos.y * 0.05).r;
	float n2 = texture(macro_tex, wpos.xz * 0.43 - wpos.y * 0.13).g;
	float lie = smoothstep(0.35, 0.7, wnrm.y + (n - 0.5) * 0.4 + (n2 - 0.5) * 0.25);
	vec3 col = mix(rock, snow_color * (0.9 + 0.12 * n2), lie);
	float deep = smoothstep(0.0, depth_dark, -wpos.y);
	col *= mix(vec3(1.0), vec3(0.5, 0.58, 0.74), deep * 0.7);
	vec2 outside = max(max(map_rect.xy - wpos.xz, wpos.xz - map_rect.zw), vec2(0.0));
	float haze = smoothstep(14.0, 70.0, length(outside));
	ALBEDO = mix(col, haze_color, haze * 0.85);
	NORMAL_MAP = mix(texture(rock_nrm, uv).rgb, vec3(0.5, 0.5, 1.0), lie * 0.8);
	NORMAL_MAP_DEPTH = 1.2;
	// the snow all round throws a little moonlight into the shade, so a wall facing away from the moon is not black
	EMISSION = col * 0.07 * (1.0 - haze);
	ROUGHNESS = mix(0.9, 0.8, lie);
	SPECULAR = mix(0.25, 0.38, lie);
}
