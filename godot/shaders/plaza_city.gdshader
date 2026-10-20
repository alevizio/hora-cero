shader_type spatial;
// Buenos Aires round the Plaza de Mayo, 1958, beyond the square's own rows (plaza_city.gd): blocks of five to nine
// storeys, the Avenida de Mayo out to the Congreso, the Diagonales, the port behind the Casa Rosada; all of it one
// material, the façades drawn here rather than modelled. Per vertex: UV2.x the lot's seed, UV2.y what the surface is
// (0 a street front, 1 a party wall, 2 a front on a courtyard, 3 a flat roof, 4 a mansard's slate, 5 a dome, 6 iron,
// 7 the dock's water, 8 floodlit stone, 9 a light), COLOR.rgb its render's colour, COLOR.a the height of its cornice
// (metres / 100); UV (m) along a front and up it. A front is drawn as storeys of windows, a third or so lit warm
// behind their curtains, balconies on some floors with snow on their slabs, snow on the sills and along the cornice,
// a ground floor of shopfronts (most of them still lit, under painted signboards with no word on them that can be
// read) between doors; a roof takes the night's snow (snow_amount) over its tar or slate, a mansard its dormers.
render_mode cull_back;

uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float snow_amount = 0.5;
uniform float lit_ratio = 0.38;
uniform vec3 snow_color : source_color = vec3(0.84, 0.85, 0.92);
uniform vec3 window_warm : source_color = vec3(1.0, 0.7, 0.4);
uniform float window_energy = 2.4;
uniform float flood_energy = 0.5;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;
varying flat float seed;
varying flat float top;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	kind = UV2.y;
	seed = UV2.x;
	top = COLOR.a * 100.0;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// a box between lo and hi with soft edges (aa: half a pixel or so)
float boxf(vec2 q, vec2 lo, vec2 hi, vec2 aa) {
	vec2 a = smoothstep(lo - aa, lo + aa, q) * (1.0 - smoothstep(hi - aa, hi + aa, q));
	return a.x * a.y;
}

void fragment() {
	int k = int(kind + 0.5);
	vec3 tint = COLOR.rgb;
	float n1 = texture(macro_tex, wpos.xz * 0.043 + wpos.y * 0.027 + seed * 3.1).r;
	float n2 = texture(macro_tex, vec2(UV.x * 0.29 + seed * 5.0, UV.y * 0.05)).g;
	vec3 albedo = tint;
	float rough = 0.88;
	float spec = 0.35;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float snow = 0.0;
	if (k == 0 || k == 2) {
		float u = UV.x;
		float v = UV.y;
		vec2 aa = max(fwidth(UV), vec2(0.004)) * 0.75;
		float P = 3.2 + 1.0 * hash(vec2(seed, 1.3));
		float G = 4.3 + 0.7 * hash(vec2(seed, 2.1));
		float F = 3.3 + 0.35 * hash(vec2(seed, 3.7));
		float ww = 1.15 + 0.35 * hash(vec2(seed, 4.4));
		float wh = 2.05 + 0.3 * hash(vec2(seed, 4.9));
		float col_i = floor(u / P);
		float cu = fract(u / P) * P;
		// the render, weathered, darker toward the pavement
		vec3 wall = tint * (0.84 + 0.2 * n1) * (1.0 - 0.14 * smoothstep(0.55, 0.95, n2));
		wall *= 0.86 + 0.14 * smoothstep(0.0, 5.0, v);
		albedo = wall;
		if (v > top - 0.95) {
			// the cornice: a band in light, its shadow under it, snow along its top
			albedo = tint * 1.1;
			if (v < top - 0.75) albedo = tint * 0.62;
			snow = smoothstep(top - 0.22, top - 0.1, v) * snow_amount;
		} else if (v > G) {
			float fl = floor((v - G) / F);
			float fv = (v - G) - fl * F;
			float storeys = floor((top - 0.95 - G) / F);
			if (fl >= storeys) {
				// the attic band under the cornice
				albedo = tint * 0.95;
			} else {
				vec2 q = vec2(cu - P * 0.5, fv);
				float win = boxf(q, vec2(-ww * 0.5, 0.6), vec2(ww * 0.5, 0.6 + wh), aa);
				float frame = boxf(q, vec2(-ww * 0.5 - 0.14, 0.48), vec2(ww * 0.5 + 0.14, 0.6 + wh + 0.18), aa) - win;
				albedo = mix(albedo, tint * 1.08, clamp(frame, 0.0, 1.0));
				float id = hash(vec2(col_i * 1.37 + seed * 31.0, fl * 2.11 + seed * 7.0));
				float lit = step(id, lit_ratio * (k == 2 ? 0.5 : 1.0));
				// mullions and a transom
				float bar = max(1.0 - smoothstep(0.03, 0.05, abs(q.x)), 1.0 - smoothstep(0.03, 0.05, abs(fv - 0.6 - wh * 0.68)));
				vec3 glass = vec3(0.05, 0.06, 0.085) + vec3(0.04, 0.05, 0.07) * smoothstep(0.6, 0.6 + wh, fv);
				float curtain = 0.55 + 0.45 * smoothstep(0.0, 0.6, abs(q.x) / ww) * hash(vec2(id, 9.0));
				vec3 light = window_warm * mix(vec3(1.0), vec3(1.05, 0.92, 0.8), hash(vec2(id, 5.0))) * window_energy * (0.55 + 0.6 * hash(vec2(id, 3.0))) * curtain;
				albedo = mix(albedo, mix(glass, vec3(0.06), lit), win * (1.0 - bar));
				albedo = mix(albedo, tint * 0.45, win * bar);
				emit += light * lit * win * (1.0 - bar);
				rough = mix(rough, 0.12, win * (1.0 - lit) * (1.0 - bar));
				spec = mix(spec, 0.6, win * (1.0 - lit));
				// the sill and its snow
				float sill = boxf(q, vec2(-ww * 0.5 - 0.18, 0.44), vec2(ww * 0.5 + 0.18, 0.58), aa);
				albedo = mix(albedo, tint * 1.12, sill);
				snow = max(snow, sill * smoothstep(0.5, 0.56, fv) * snow_amount);
				// balconies: on the first floor of a street front, on every floor of some
				float every = step(hash(vec2(seed, 5.1)), 0.42);
				if (k == 0 && (fl < 0.5 || every > 0.5)) {
					float slab = boxf(q, vec2(-ww * 0.5 - 0.5, 0.3), vec2(ww * 0.5 + 0.5, 0.5), aa);
					albedo = mix(albedo, tint * 0.6, slab);
					snow = max(snow, slab * smoothstep(0.44, 0.5, fv) * snow_amount);
					// its iron railing over the window's foot
					float rail = boxf(q, vec2(-ww * 0.5 - 0.5, 0.5), vec2(ww * 0.5 + 0.5, 1.45), aa);
					float bars = max(step(0.72, fract(q.x * 7.0)), max(step(1.36, fv), step(fv, 0.58)));
					albedo = mix(albedo, vec3(0.05, 0.05, 0.055), rail * bars);
					emit *= 1.0 - rail * bars;
					snow = max(snow, rail * step(1.4, fv) * snow_amount * 0.9);
				}
				// a string course between the storeys
				albedo = mix(albedo, tint * 1.06, (1.0 - smoothstep(0.1, 0.14, fv)) * (1.0 - win));
			}
		} else {
			// the ground floor: shopfronts two bays wide between doors, a painted signboard over each
			float sp = P * 2.0;
			float su = fract(u / sp) * sp;
			float sid = floor(u / sp) + seed * 17.0;
			vec2 q = vec2(su - sp * 0.5, v);
			float shop = boxf(q, vec2(-sp * 0.36, 0.4), vec2(sp * 0.36, G - 1.25), aa);
			float board = boxf(q, vec2(-sp * 0.42, G - 1.12), vec2(sp * 0.42, G - 0.38), aa);
			float door = boxf(q, vec2(sp * 0.4, 0.0), vec2(sp * 0.5, 2.6), aa) + boxf(q, vec2(-sp * 0.5, 0.0), vec2(-sp * 0.4, 2.6), aa);
			float h = hash(vec2(sid, 11.0));
			float open = step(h, k == 0 ? 0.62 : 0.0);
			vec3 inside = window_warm * window_energy * 0.8 * (0.7 + 0.5 * hash(vec2(sid, 2.0))) * (0.75 + 0.25 * smoothstep(0.4, G - 1.25, v));
			float ribs = 0.8 + 0.2 * step(0.5, fract(v * 7.0));
			vec3 shutter = vec3(0.2, 0.2, 0.21) * ribs;
			albedo = mix(albedo, mix(shutter, vec3(0.08), open), shop);
			emit += inside * open * shop;
			rough = mix(rough, 0.3, shop * open);
			int bc = int(floor(hash(vec2(sid, 4.0)) * 5.0));
			vec3 boardc = bc == 0 ? vec3(0.08, 0.2, 0.12) : (bc == 1 ? vec3(0.32, 0.06, 0.05) : (bc == 2 ? vec3(0.05, 0.08, 0.18) : (bc == 3 ? vec3(0.04) : vec3(0.36, 0.26, 0.1))));
			// gold strokes along it that read as lettering from afar, and say nothing
			float letters = step(0.45, fract(q.x * 2.3 + hash(vec2(sid, 8.0)))) * boxf(q, vec2(-sp * 0.3, G - 0.95), vec2(sp * 0.3, G - 0.55), aa);
			boardc = mix(boardc, vec3(0.75, 0.58, 0.25), letters * 0.8);
			albedo = mix(albedo, boardc, board);
			emit += boardc * board * open * 0.25;
			albedo = mix(albedo, vec3(0.07, 0.06, 0.06), clamp(door, 0.0, 1.0));
			// the plinth
			albedo = mix(albedo, tint * 0.55, 1.0 - smoothstep(0.32, 0.38, v));
			snow = max(snow, board * smoothstep(G - 0.42, G - 0.38, v) * snow_amount);
		}
	} else if (k == 1) {
		albedo = tint * 0.78 * (0.86 + 0.24 * n1);
	} else if (k == 3) {
		// a flat roof: tar and tiles, a water tank's rust here and there, under the night's snow
		float m = texture(macro_tex, wpos.xz * 0.11 + seed).b;
		albedo = mix(vec3(0.24, 0.22, 0.23), vec3(0.34, 0.27, 0.24), m);
		// (it whitens evenly as the night goes on: blotches of bare tar would read as dirt from above)
		snow = smoothstep(0.02, 0.32, snow_amount + (n1 - 0.5) * 0.1) * (0.94 + 0.06 * m);
	} else if (k == 4) {
		// a mansard's slate, the snow held on it in streaks; a row of dormers, some lit
		albedo = vec3(0.15, 0.16, 0.19) * (0.85 + 0.3 * n1);
		float s_on = smoothstep(0.2, 0.8, snow_amount * 0.9 + (n2 - 0.5) * 0.6);
		snow = s_on * 0.85;
		float P = (3.2 + 1.0 * hash(vec2(seed, 1.3))) * 2.0;
		float cu = fract(UV.x / P) * P;
		float id = hash(vec2(floor(UV.x / P) + seed * 13.0, 3.0));
		vec2 aa = max(fwidth(UV), vec2(0.004)) * 0.75;
		float dorm = boxf(vec2(cu - P * 0.5, UV.y - top), vec2(-0.55, 0.6), vec2(0.55, 1.9), aa);
		float lit = step(id, lit_ratio * 0.6);
		albedo = mix(albedo, vec3(0.05), dorm);
		emit += window_warm * window_energy * 0.7 * lit * dorm;
		snow *= 1.0 - dorm;
	} else if (k == 5) {
		// a dome: slate or zinc (or the Congreso's verdigris, its tint), snow on its shoulders
		albedo = tint * (0.85 + 0.3 * n1);
		rough = 0.6;
		spec = 0.45;
		snow = smoothstep(0.35, 0.8, wnrm.y + (n1 - 0.5) * 0.4) * snow_amount;
	} else if (k == 6) {
		albedo = tint * (0.8 + 0.3 * n1);
		rough = 0.6;
		metal = 0.3;
		snow = smoothstep(0.6, 0.9, wnrm.y) * snow_amount;
	} else if (k == 7) {
		// the dock's black water, a slow swell
		float sw = texture(macro_tex, wpos.xz * 0.07 + vec2(TIME * 0.004, 0.0)).r;
		albedo = vec3(0.02, 0.025, 0.035);
		rough = 0.05 + 0.12 * sw;
		spec = 0.7;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((sw - 0.5) * 0.12, 0.0, (n1 - 0.5) * 0.12, 0.0)).xyz);
	} else if (k == 8) {
		// floodlit stone: the light from below, fading up the height
		albedo = tint * (0.88 + 0.2 * n1);
		emit += tint * vec3(1.0, 0.86, 0.68) * flood_energy * (1.0 - 0.6 * smoothstep(0.0, max(top, 1.0), wpos.y));
		snow = smoothstep(0.7, 0.9, wnrm.y) * snow_amount;
	} else if (k == 10) {
		// a street beyond the ground's own map: grey slush, the wheel tracks wet and dark along it
		float lane = fract(UV.y / 3.4 + (n1 - 0.5) * 0.2);
		float wheel = max(1.0 - smoothstep(0.035, 0.1, abs(lane - 0.25)), 1.0 - smoothstep(0.035, 0.1, abs(lane - 0.72)));
		wheel *= smoothstep(0.25, 0.6, texture(macro_tex, vec2(UV.x * 0.021, UV.y * 0.11) + 0.5).r + 0.15);
		albedo = mix(vec3(0.5, 0.5, 0.53) * (0.85 + 0.25 * n1), vec3(0.2, 0.2, 0.22), wheel * 0.7);
		rough = mix(0.7, 0.22, wheel);
		spec = 0.55;
		snow = (1.0 - wheel) * smoothstep(0.3, 0.9, snow_amount + (n2 - 0.5) * 0.5) * 0.45;
	} else {
		albedo = tint * 0.2;
		emit += tint * 4.0;
	}
	// snow on whatever faces up (the tops of parapets, ledges built as geometry)
	if (k <= 2 || k == 8) snow = max(snow, smoothstep(0.75, 0.95, wnrm.y) * snow_amount);
	ALBEDO = mix(albedo, snow_color * (0.95 + 0.06 * n1), snow);
	ROUGHNESS = mix(rough, 0.82, snow);
	SPECULAR = mix(spec, 0.35, snow);
	METALLIC = metal * (1.0 - snow);
	EMISSION = emit * (1.0 - snow);
}
