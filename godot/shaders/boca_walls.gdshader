shader_type spatial;
// La Boca's houses in one draw: the tiling surfaces (painted iron, lime render, brick, planks, corrugated iron,
// granite, iron, snow, slate, leaves) are layers of one array texture, the layer chosen per vertex (UV2.x). Otherwise boca_surface: the
// vertex colour tints, its alpha says how much snow a thing holds, snow lies wherever a surface faces up, and the
// whole thing is dithered away ("fade" < 1) when somebody stands behind it.
render_mode cull_back;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// per layer: roughness in the albedo's alpha (iron), else this constant; normal strength
uniform float roughness[10];
uniform float normal_scale[10];
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;
// how much of the night's snow has settled (1: all of it, as in La Boca; the Plaza de Mayo raises it as it falls)
uniform float snow_amount = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float layer;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	layer = UV2.x;
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
	int li = clamp(int(layer + 0.5), 0, 9);
	vec3 uvw = vec3(UV, float(li));
	vec4 t = texture(albedo_tex, uvw);
	vec3 base = t.rgb * COLOR.rgb;
	float rough = roughness[li] < 0.0 ? t.a : roughness[li];
	float n = texture(macro_tex, wpos.xz * 0.21 + wpos.y * 0.07).r;
	float n2 = texture(macro_tex, wpos.xz * 0.9 + wpos.y * 0.3).g;
	float lie = smoothstep(0.42, 0.78, wnrm.y + (n - 0.5) * 0.35);
	float thin = smoothstep(0.25, 0.75, n2) * 0.25;
	float drift = (1.0 - smoothstep(0.0, 0.55, wpos.y)) * smoothstep(0.2, 0.0, abs(wnrm.y)) * 0.55;
	float s = clamp(max(lie - thin * lie * (1.0 - COLOR.a * 0.5), drift * step(0.45, n)) * COLOR.a, 0.0, 1.0);
	if (snow_amount < 0.999) {
		// the snow lying in a layer of its own builds up in patches; on everything else it settles thinly first
		// (a roof at a time, from a very broad noise: no pattern within one)
		if (li == 7 && texture(macro_tex, wpos.xz * 0.031).r > (snow_amount - 0.2) * 1.6) discard;
		s *= smoothstep(0.0, 0.8, snow_amount + (n - 0.5) * 0.3);
	}
	if (li == 9) {
		// foliage: snow caught in clumps on everything that faces up a little, the dark leaves showing between
		float speck = texture(macro_tex, wpos.xz * 1.7 + wpos.y * 0.9).r * 0.6 + texture(macro_tex, wpos.zx * 4.3 - wpos.y).g * 0.4;
		s = smoothstep(0.54, 0.82, wnrm.y * 0.62 + speck * 0.6 - 0.05) * COLOR.a * smoothstep(0.0, 0.8, snow_amount);
		base *= 1.7;
	}
	vec3 snow = snow_color * (0.9 + 0.12 * n);
	ALBEDO = mix(base, snow, s);
	NORMAL_MAP = mix(texture(normal_tex, uvw).rgb, vec3(0.5, 0.5, 1.0), s * 0.9);
	NORMAL_MAP_DEPTH = normal_scale[li];
	ROUGHNESS = mix(rough, 0.8, s);
	SPECULAR = mix(0.4, 0.35, s);
}
