shader_type spatial;
// Splatted outpost ground: meadow, worn earth, vehicle tracks, shingle beach, forest floor.
// World-space mapped; `mask_tex` is built at load by nature.gd from the mission layout:
//   R = worn / bare earth, G = contact-shadow occlusion, B = lush (untrodden) growth, A = rocks (water foam).
render_mode cull_back;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // rgb + blade height
uniform sampler2D grass_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // rgb + height
uniform sampler2D dirt_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shingle_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;                           // 4 noise channels
uniform sampler2D track_tex : filter_linear_mipmap_anisotropic, repeat_enable;               // see gen_nature_textures.py
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-4.0, -19.5, 0.015625, 0.015625);   // origin.xz, 1/size
uniform vec4 map_rect = vec4(5.0, 0.0, 40.0, 25.0);              // playable min.xz, max.xz
uniform vec3 haze_color : source_color = vec3(0.16, 0.20, 0.20);
uniform vec3 grass_tint = vec3(0.92, 0.95, 1.22);
uniform vec3 dirt_tint = vec3(0.96, 0.98, 1.10);
uniform float ao_strength = 1.0;
uniform float gain = 0.80;              // linear albedo gain (exposure trim for this material)

const float TRACK_W = 2.4667;   // (19.4 - 12.0) / 3 so both east-west tracks share one continuous U

varying vec3 wpos;
varying vec3 wnrm;

// Shoreline X for a given Z. Mirrored in nature.gd (coast_x) and water.gdshader - keep the three in sync.
float coast_x(float z) {
	float o = max(max(-1.0 - z, z - 26.0), 0.0);
	float w = smoothstep(0.0, 14.0, o);
	return 4.85 + sin(z * 0.9) * 0.10 + sin(z * 0.37 + 1.3) * 0.14 + w * (sin(z * 0.085 + 0.6) * 5.5 + sin(z * 0.21 + 2.0) * 2.2);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 m1 = texture(macro_tex, p * 0.0213);
	vec4 m2 = texture(macro_tex, p.yx * 0.0871 + vec2(0.37, 0.11));
	vec4 m3 = texture(macro_tex, p * 0.337 + vec2(0.61, 0.23));      // clump-scale mottling (3 m period)
	// Occlusion is read straight (it must hug the footprints); wear and growth are read through a small
	// warp so trodden patches get ragged, natural outlines instead of the stamped rectangles.
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	vec4 mk = texture(mask_tex, muv + ((m3.rg - 0.5) * 0.55 + (m2.ba - 0.5) * 0.5) * mask_rect.zw);
	mk.g = texture(mask_tex, muv).g;
	float sd = p.x - coast_x(p.y);
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float out_d = length(outside);

	// ---- vehicle tracks (north-south one, then the two east-west ones) ----
	float ax = 20.4 + sin(p.y * 0.23 + 0.8) * 0.28 + sin(p.y * 0.071) * 0.22;
	float ua = (p.x - ax) / TRACK_W;
	vec4 ta = texture(track_tex, vec2(ua + 0.5, p.y / (TRACK_W * 2.0)));
	float wa = step(abs(ua), 0.5);
	float ub = (p.y - 12.0 - sin(p.x * 0.19 + 2.1) * 0.25) / TRACK_W;
	vec4 tb = texture(track_tex, vec2(ub + 0.5, p.x / (TRACK_W * 2.0) + 0.31));
	float wb = step(abs(ub), 0.5) * smoothstep(5.8, 8.0, p.x) * (1.0 - smoothstep(28.4, 30.4, p.x))
			+ step(abs(ub - 3.0), 0.5) * smoothstep(7.0, 9.5, p.x);
	float cover_a = ta.a * wa;
	float cover_b = tb.a * wb;
	float cover = max(cover_a, cover_b);
	float sel = cover_a / (cover_a + cover_b + 0.0001);
	float t_dark = mix(tb.r, ta.r, sel) - 0.5;
	float t_wet = mix(tb.g, ta.g, sel) * cover;

	// ---- layer samples ----
	vec2 warp = (m2.rg - 0.5) * 0.30;
	vec2 uvg = p * 0.25 + warp;
	vec2 uvd = p * 0.27 + warp.yx;
	vec4 g = texture(grass_tex, uvg);
	vec4 d = texture(dirt_tex, uvd);
	vec4 s = texture(shingle_tex, p * 0.42);
	vec2 gn = texture(grass_nrm, uvg).rg * 2.0 - 1.0;
	vec2 dn = texture(dirt_nrm, uvd).rg * 2.0 - 1.0;

	// ---- weights ----
	float raw = max(cover, mk.r);
	float w_dirt = smoothstep(0.30, 0.62, raw * (1.0 + (0.5 - g.a) * 1.3 + (m2.b - 0.5) * 0.7));
	float trampled = smoothstep(0.06, 0.45, raw);
	float forest = smoothstep(1.2, 6.0, out_d + (m2.r - 0.5) * 3.0);
	float w_shore = smoothstep(1.85, 0.85, sd + (m2.b - 0.5) * 1.5 + (m3.r - 0.5) * 1.5 + (g.a - 0.5) * 0.6);
	float pebbly = smoothstep(-0.7, 0.35, sd + (m2.r - 0.5) * 0.9 + (m3.g - 0.5) * 0.8 + (s.a - 0.5) * 0.5);
	float wet = smoothstep(0.80, 0.10, sd + (m2.g - 0.5) * 0.35);

	// ---- colours ----
	float lush = clamp(m1.r * 0.9 + m2.g * 0.55 - 0.42 + mk.b * 0.7 + (m3.b - 0.5) * 0.55, 0.0, 1.0);
	vec3 grass = g.rgb * grass_tint * mix(vec3(1.08, 1.02, 0.86), vec3(0.86, 0.95, 0.88), lush) * (0.92 + 0.14 * m1.g) * (0.94 + 0.12 * m3.g);
	float lum = dot(g.rgb, vec3(0.3, 0.55, 0.15));
	grass = mix(grass, vec3(1.45, 1.28, 0.86) * lum * (0.85 + 0.3 * m2.a), trampled * 0.62);   // short, bleached, trodden
	vec3 dirt = d.rgb * dirt_tint * mix(vec3(0.84, 0.82, 0.80), vec3(1.06, 1.0, 0.93), m1.b);
	dirt *= 1.0 + t_dark * 1.15 * cover;
	dirt *= 1.0 - 0.22 * t_wet;
	vec3 col = mix(grass, dirt, w_dirt);
	// forest floor: needle litter and moss, in permanent canopy shade
	vec3 litter = d.rgb * vec3(0.40, 0.36, 0.30);
	vec3 moss = g.rgb * vec3(0.50, 0.66, 0.44);
	vec3 floor_col = mix(litter, moss, smoothstep(0.42, 0.62, m2.g + (g.a - 0.5) * 0.4));
	col = mix(col, floor_col * mix(1.0, 0.62, smoothstep(6.0, 18.0, out_d)), forest * (1.0 - 0.75 * cover));
	// beach: shingle over damp sand, a dark wrack line at high water
	vec3 sand = d.rgb * vec3(0.93, 0.93, 0.90) * (0.92 + 0.16 * m2.a);
	vec3 beach = mix(sand, s.rgb, pebbly * (0.55 + 0.45 * smoothstep(0.35, 0.6, m2.b)));
	float wrack = (1.0 - smoothstep(0.0, 0.15, abs(sd - 0.60 - (m2.r - 0.5) * 0.5 - (m3.b - 0.5) * 0.45))) * smoothstep(0.42, 0.62, m2.a) * smoothstep(0.35, 0.65, m3.a);
	beach = mix(beach, vec3(0.055, 0.050, 0.030), wrack * 0.55);
	beach *= mix(1.0, 0.60, wet);
	col = mix(col, beach, w_shore);

	// ---- grounding: contact shadow / AO from the layout mask ----
	float ao = 1.0 - mk.g * ao_strength;
	col *= mix(vec3(0.34, 0.36, 0.42), vec3(1.0), ao);

	// ---- distance haze so the world dissolves into dark forest instead of ending ----
	float haze = smoothstep(16.0, 72.0, out_d) * 0.92;
	col = mix(col * gain, haze_color, haze);

	// ---- normal, roughness ----
	float n_scale = mix(0.75, 1.0, w_dirt);
	vec2 nxy = mix(gn * 1.25, dn, max(w_dirt, w_shore));
	nxy *= mix(1.0, 1.6, w_shore * pebbly) * (1.0 - haze) * n_scale;
	vec3 n = normalize(wnrm);
	n.x += nxy.x + (ta.b - 0.5) * 1.6 * cover_a;
	n.z += -nxy.y + (tb.b - 0.5) * 1.6 * cover_b;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
	ALBEDO = col;
	float rough = mix(0.96, 0.88, w_dirt);
	rough = mix(rough, 0.52, t_wet * w_dirt);
	rough = mix(rough, mix(0.86, 0.34, wet), w_shore);
	ROUGHNESS = rough;
	SPECULAR = mix(0.18, 0.5, max(w_shore * wet, t_wet * w_dirt));
}
