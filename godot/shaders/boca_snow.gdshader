shader_type spatial;
// Snow lying in a layer of its own (a drift on a roof's eaves, the cap on a wall, a heap against a kerb, a snowman):
// white on top, a little bluer down its sides and in the hollows, a faint sparkle. Dithered away with its building.
render_mode cull_back;

uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
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
	vec2 p = abs(wnrm.y) > 0.6 ? wpos.xz : (abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy);
	float t = texture(snow_tex, p * 0.35).r;
	float n = texture(macro_tex, wpos.xz * 0.2 + wpos.y * 0.1).r;
	float up = clamp(wnrm.y, 0.0, 1.0);
	// wind-worked snow: broad patches a little greyer and bluer, finer crust between them
	float m = texture(macro_tex, wpos.xz * 0.075 + wpos.y * 0.05).g;
	float patch = smoothstep(0.3, 0.72, m * 0.7 + n * 0.3);
	vec3 c = snow_color * (0.86 + 0.12 * t + 0.06 * n) * mix(vec3(0.84, 0.87, 0.97), vec3(1.0), patch);
	c *= mix(vec3(0.82, 0.87, 1.0), vec3(1.0), up);
	// on a pitched roof the iron's ribs still print through the snow, running down the slope
	float pitch = smoothstep(0.995, 0.9, up) * smoothstep(0.35, 0.6, up);
	vec2 across = normalize(vec2(-wnrm.z, wnrm.x) + vec2(1e-4));
	float rib = 0.5 + 0.5 * sin(dot(wpos.xz, across) * 8.9);
	c *= 1.0 - pitch * rib * 0.09;
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
}
