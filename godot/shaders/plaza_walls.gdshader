shader_type spatial;
// The Plaza de Mayo kit (plaza_kit.gd): every tiling surface of the square's landmarks, its street furniture and the
// city's vehicles in one draw. The layers of one array texture (render, rustication, ashlar, marble, colonial tiles,
// slate, iron, bronze, snow, planks, car paint, palm bark, leaves, rubber) are chosen per vertex (UV2.x). The vertex
// colour tints; its alpha says how much snow a thing holds; snow lies wherever a surface faces up, scaled by the
// kit's snow amount. Some layers keep their roughness in the albedo's alpha, some where the snow catches (the pans
// between the colonial tiles' caps). The palace's lime stucco takes a large blotchiness in world space (its wash
// laid unevenly over 120 years, so the tile never shows). Dithered away ("fade" < 1) when somebody stands behind it,
// like La Boca's; a palm's crown (a multimesh's instance, `instance_fade`) by its own instance's INSTANCE_CUSTOM.r,
// above `fade_above` metres of it.
render_mode cull_back;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// per layer: roughness (< 0: in the albedo's alpha), normal strength, metallic, specular, and whether the albedo's
// alpha says where snow catches (1) rather than the roughness
uniform float roughness[16];
uniform float normal_scale[16];
uniform float metallic[16];
uniform float specular[16];
uniform float catch_alpha[16];
uniform float snow_amount = 1.0;
// a warm wash of floodlight on the fronts that have it (the vertex's UV2.y: how much)
uniform vec3 flood_color : source_color = vec3(1.0, 0.8, 0.68);
uniform float flood_energy = 0.55;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;
uniform bool instance_fade = false;
uniform float fade_above = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float layer;
varying float flood;
varying float ifade;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	layer = UV2.x;
	flood = UV2.y;
	ifade = (instance_fade && VERTEX.y > fade_above) ? INSTANCE_CUSTOM.r : 1.0;
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
	float f = min(fade, ifade);
	if (f < 0.999 && bayer4(FRAGCOORD.xy) > f) discard;
	int li = clamp(int(layer + 0.5), 0, 15);
	vec3 uvw = vec3(UV, float(li));
	if (li == 8) {
		// the snow layer in world space, as on the ground: its ripples never line up into a grid on a wide surface
		vec2 p = abs(wnrm.y) > 0.6 ? wpos.xz * 0.11 : (abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy) * 0.3;
		uvw = vec3(p, 8.0);
	}
	vec4 t = texture(albedo_tex, uvw);
	vec3 base = t.rgb * COLOR.rgb;
	if (li == 14) {
		// the stucco's wash: blotches a few metres across and some tens, a shade lighter or darker, a touch warmer
		float b1 = texture(macro_tex, (wpos.xy + wpos.zy) * 0.031 + vec2(0.17, 0.53)).g;
		float b2 = texture(macro_tex, (wpos.xy + wpos.zy) * 0.0085 + vec2(0.61, 0.07)).r;
		float b = (b1 - 0.5) * 0.7 + (b2 - 0.5) * 0.5;
		base *= vec3(1.0 + b * 0.16, 1.0 + b * 0.13, 1.0 + b * 0.11);
	}
	bool catches = catch_alpha[li] > 0.5;
	float rough = (roughness[li] < 0.0 && !catches) ? t.a : abs(roughness[li]);
	float n = texture(macro_tex, wpos.xz * 0.21 + wpos.y * 0.07).r;
	float n2 = texture(macro_tex, wpos.xz * 0.9 + wpos.y * 0.3).g;
	float lie = smoothstep(0.42, 0.78, wnrm.y + (n - 0.5) * 0.35);
	float thin = smoothstep(0.25, 0.75, n2) * 0.25;
	float drift = (1.0 - smoothstep(0.0, 0.55, wpos.y)) * smoothstep(0.2, 0.0, abs(wnrm.y)) * 0.55;
	float s = clamp(max(lie - thin * lie * (1.0 - COLOR.a * 0.5), drift * step(0.45, n)) * COLOR.a, 0.0, 1.0);
	if (catches) {
		// the tiles' caps stay red where the snow has filled the pans between them
		float pan = t.a * (0.75 + 0.5 * n2);
		s = clamp(smoothstep(0.3, 0.75, wnrm.y + (n - 0.5) * 0.3) * smoothstep(0.45, 0.85, pan) * COLOR.a, 0.0, 1.0);
	}
	if (li == 12) {
		// foliage: snow caught in clumps on everything that faces up a little, the dark leaves showing between
		float speck = texture(macro_tex, wpos.xz * 1.7 + wpos.y * 0.9).r * 0.6 + texture(macro_tex, wpos.zx * 4.3 - wpos.y).g * 0.4;
		s = smoothstep(0.54, 0.82, wnrm.y * 0.62 + speck * 0.6 - 0.05) * COLOR.a;
		base *= 1.7;
	}
	// (a palm's crown fading over somebody sheds its snow cap with it: the cap itself goes the crown's dark)
	float keep = smoothstep(0.55, 0.98, ifade);
	s *= snow_amount * keep;
	if (li == 8) base = mix(vec3(0.16, 0.17, 0.12), base, keep);
	vec3 snow = snow_color * (0.9 + 0.12 * n);
	ALBEDO = mix(base, snow, s);
	NORMAL_MAP = mix(texture(normal_tex, uvw).rgb, vec3(0.5, 0.5, 1.0), s * 0.9);
	NORMAL_MAP_DEPTH = normal_scale[li];
	ROUGHNESS = mix(rough, 0.8, s);
	METALLIC = metallic[li] * (1.0 - s);
	EMISSION = ALBEDO * flood_color * flood * flood_energy;
	SPECULAR = mix(specular[li], 0.35, s);
}
