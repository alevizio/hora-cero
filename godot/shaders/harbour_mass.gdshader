shader_type spatial;
// Mass concrete of the U-boat bunker: the board-formed texture at its own scale, with leaching and rain streaks
// hanging below every pour line (a world-space 8 m overlay), darker and greener toward the foot.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D streak_tex : filter_linear_mipmap, repeat_enable;
uniform float streaks = 0.75;
uniform float roughness = 0.88;
uniform float wet_foot = 2.5;           // metres above the ground (or water) that stay damp
uniform float fade = 1.0;               // < 1: dithered away (somebody stands behind it)

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
	vec3 base = texture(albedo_tex, UV).rgb * COLOR.rgb;
	float wall = 1.0 - abs(wnrm.y);
	float u = (abs(wnrm.x) > 0.5 ? wpos.z : wpos.x) / 8.0;
	float s = texture(streak_tex, vec2(u, -wpos.y / 8.0)).r;
	base *= mix(1.0, clamp(s * 2.0, 0.35, 1.4), streaks * wall);
	float damp = (1.0 - smoothstep(-0.5, wet_foot, wpos.y)) * wall;
	base = mix(base, base * vec3(0.62, 0.66, 0.6), damp * 0.6);
	ALBEDO = base;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = mix(roughness, 0.55, damp * 0.6);
	SPECULAR = 0.4;
}
