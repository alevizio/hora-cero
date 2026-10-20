shader_type spatial;
// The ground of the Plaza de Mayo on the night the snow begins (Plaza de Mayo, 1958): wet granite setts on the
// carriageways, the tram rails cut in them, pale stone flags on the plaza's walks and the pavements, the lawns dark
// with winter grass, dark at the foot of every wall. `cover` (0..1, how much snow lies of all that will) lays fresh
// powder over it: the lawns whiten first and lie deepest and smoothest, then the walks and the pavements, the
// carriageways last. The powder is a seamless tile of soft lumps and a fine grain (plaza/powder_n.png) laid three
// times, at scales turned against each other, under a broad tone of the macro noise, so no repeat or banding shows. Here and
// there a grain catches the light: a facet of its own, glassy, that flashes under the lamps (and faintly in the moon).
// The square's walks stay greyer, trodden through the evening; wherever somebody has walked tonight (trample_tex: the
// cover the snow had when they passed, so fresh snow fills the track as it falls) it is trampled grey; the busy
// streets are slush with darker wet setts in the wheel tracks, white banks along the kerbs, and the bed between the
// tram rails stays black and wet. Beyond the city it all goes into the haze.
render_mode cull_back;

uniform sampler2D powder_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flags_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// the layout, one map each: trodden (the rules' packed snow); rails (the bed between them at half, the steel full);
// the foot of the walls; carriageways (the north-south ones at 0.6, the east-west ones full: which way the wheels
// run); lawns (the square's paved walks at half, its lawns full)
uniform sampler2D slush_tex : filter_linear, repeat_disable;
uniform sampler2D rails_tex : filter_linear, repeat_disable;
uniform sampler2D occl_tex : filter_linear, repeat_disable;
uniform sampler2D road_tex : filter_linear, repeat_disable;
uniform sampler2D lawn_tex : filter_linear, repeat_disable;
uniform sampler2D trample_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-150.0, -90.0, 0.0017, 0.0029);   // x0, z0, 1/width, 1/height
uniform vec4 trample_rect = vec4(-10.0, -10.0, 0.0033, 0.0054); // x0, z0, 1/width, 1/height
uniform vec4 map_rect = vec4(-150.0, -90.0, 430.0, 250.0);      // x0, z0, x1, z1 of the built city
uniform vec3 haze_color : source_color = vec3(0.42, 0.44, 0.56);
uniform vec3 snow_tint : source_color = vec3(0.89, 0.88, 0.93);
uniform float cover = 0.0;
uniform float sparkle = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	float slush = 0.0;
	float rv = 0.0;
	float occl = 0.0;
	float roadv = 0.0;
	float lv = 0.0;
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		slush = texture(slush_tex, muv).r;
		rv = texture(rails_tex, muv).r;
		occl = texture(occl_tex, muv).r;
		roadv = texture(road_tex, muv).r;
		lv = texture(lawn_tex, muv).r;
	}
	float rails = smoothstep(0.7, 0.92, rv);
	float bed = smoothstep(0.18, 0.42, rv);
	float road = smoothstep(0.25, 0.55, roadv);
	float east_west = smoothstep(0.75, 0.92, roadv);
	float lawn = smoothstep(0.7, 0.9, lv);
	float plaza = smoothstep(0.18, 0.42, lv);
	float walk = plaza * (1.0 - lawn);
	vec2 tuv = (p - trample_rect.xy) * trample_rect.zw;
	float stamped = 0.0;
	if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) stamped = texture(trample_tex, tuv).r;
	// trodden tonight: full where they passed, filling in as the snow falls on (the cover since then)
	float tramp = 0.0;

	float macro = texture(macro_tex, p * 0.011).r;
	float macro2 = texture(macro_tex, rot(0.7) * p * 0.0047 + 0.31).g;
	float macro3 = texture(macro_tex, p * 0.051 + 0.37).b;

	// ---- what is under the snow
	vec2 suv = p * 0.5;
	vec3 setts = texture(setts_tex, suv).rgb;
	float lum = dot(setts, vec3(0.333));
	vec3 stone = setts * vec3(0.42, 0.43, 0.48);
	vec2 fuv = p / 0.6;
	vec2 cell = fract(fuv);
	float joint_f = 1.0 - smoothstep(0.0, 0.05, min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y)));
	vec3 flags = texture(flags_tex, p * 0.21).rgb * vec3(0.66, 0.64, 0.62) * (0.9 + 0.2 * hash(floor(fuv)));
	flags *= 1.0 - 0.16 * joint_f;
	// (two layers of the grass, turned against each other: one alone shows its tile through the first snow)
	vec3 grass = mix(texture(grass_tex, p * 0.18).rgb, texture(grass_tex, rot(0.9) * p * 0.113 + 0.4).rgb, 0.5) * vec3(0.42, 0.48, 0.36) * (0.8 + 0.3 * macro3);
	vec3 bare = mix(flags, stone, road);
	bare = mix(bare, grass, lawn);
	bare = mix(bare, vec3(0.13, 0.135, 0.15), bed * 0.6);
	bare = mix(bare, vec3(0.16, 0.17, 0.19), rails * 0.7);

	// ---- the powder: two layers of the tile, turned and scaled against each other
	// (three layers of it at scales that never line up, their weights wandering with the macro noise, so no tile
	// and no grid shows however low the moon lies)
	vec4 a0 = texture(powder_tex, rot(0.37) * p / 13.3 + vec2(0.13, 0.29));
	vec4 a1 = texture(powder_tex, rot(1.13) * p / 4.9 + vec2(0.37, 0.71));
	vec4 a2 = texture(powder_tex, rot(2.41) * p / 2.07 + vec2(0.61, 0.05));
	float wa = 0.45 + 0.4 * macro2;
	float wb = 0.35 + 0.3 * (1.0 - macro);
	float hgt = (a0.a * wa + a1.a * wb + a2.a * 0.3) / (wa + wb + 0.3);
	vec2 g0 = rot(-0.37) * (a0.rgb * 2.0 - 1.0).xy;
	vec2 g1 = rot(-1.13) * (a1.rgb * 2.0 - 1.0).xy;
	vec2 g2 = rot(-2.41) * (a2.rgb * 2.0 - 1.0).xy;
	// (deep, undisturbed snow is smoother: the lumps soften on the lawns)
	float soft = mix(0.8, 0.45, lawn);
	vec3 np = normalize(vec3((g0 * wa * 0.6 + g1 * wb + g2 * 0.45) * soft, 1.0));
	vec3 snow = snow_tint * (0.935 + 0.07 * hgt + 0.05 * (macro - 0.5) + 0.03 * (macro2 - 0.5));
	// a breath of blue in the hollows
	snow = mix(snow * vec3(0.93, 0.95, 1.03), snow, smoothstep(0.25, 0.7, hgt));
	// (where the first snow holds and where it is thin: broad noise only, a fine tile would print through as a grid)
	float n = (macro - 0.5) * 0.3 + (macro2 - 0.5) * 0.2 + (macro3 - 0.5) * 0.1 + (hgt - 0.5) * 0.12;
	float hold = mix(mix(0.04, 0.42, road), -0.18, lawn);
	float s = smoothstep(hold, hold + 0.5, cover + n);
	vec3 laid = mix(bare, snow, s);

	// ---- the walks of the square: trodden through the evening, greyer, the snow broken into prints
	vec3 crust = texture(packed_tex, rot(0.4) * p * 0.31).rgb * vec3(0.8, 0.81, 0.86);
	float broken = smoothstep(0.35, 0.75, a2.a + (a1.a - 0.5) * 0.6);
	vec3 trod = mix(crust * 0.86, crust, broken);
	trod = mix(bare * 1.1, trod, smoothstep(0.05, 0.45, cover + (macro3 - 0.5) * 0.3));
	float walked = walk * (0.32 + 0.25 * smoothstep(0.4, 0.8, macro3));
	vec3 col = mix(laid, trod, walked * s);

	// ---- tonight's tracks: trampled grey where they went, churned, the edge ragged; filling in as the snow falls
	if (stamped > 0.002) tramp = 1.0 - smoothstep(0.0, 0.1, cover - stamped + (hgt - 0.5) * 0.08);
	tramp *= smoothstep(0.0, 0.03, stamped - 0.002);
	vec3 churn = mix(crust * 0.66, snow * 0.86, smoothstep(0.3, 0.7, a1.a * 0.6 + a2.a * 0.4));
	vec3 track = mix(churn, bare * 1.15, 0.25 * (1.0 - s));
	col = mix(col, track, tramp * 0.9 * smoothstep(0.0, 0.2, cover));

	// ---- the streets: slush, the wheel tracks wet and dark, white banks at the kerbs
	float across = mix(p.x, p.y, east_west);
	float along = mix(p.y, p.x, east_west);
	// two wheel tracks to a lane, wandering a little, broken where fresh snow has drifted over them
	float lane = fract(across / 3.4 + (macro2 - 0.5) * 0.25);
	float wheel = max(1.0 - smoothstep(0.035, 0.1, abs(lane - 0.25)), 1.0 - smoothstep(0.035, 0.1, abs(lane - 0.72)));
	wheel *= smoothstep(0.25, 0.6, texture(macro_tex, vec2(along * 0.021, across * 0.11) + 0.5).r + 0.15);
	vec3 mush = texture(packed_tex, p * 0.22).rgb * vec3(0.66, 0.65, 0.68);
	vec3 wet_setts = mix(stone * 0.9, mush * 0.62, 0.35);
	float busy = clamp(slush + road * 0.35, 0.0, 1.0) * road;
	vec3 street = mix(mush, wet_setts, wheel * 0.55);
	street = mix(street, vec3(0.12, 0.125, 0.14), bed * 0.75);
	street = mix(street, vec3(0.2, 0.21, 0.23), rails * 0.6);
	float bank = smoothstep(0.9, 0.55, roadv) * road * (1.0 - bed);
	street = mix(street, snow * 0.92, bank * smoothstep(0.1, 0.5, cover));
	col = mix(col, street, busy * smoothstep(0.0, 0.25, cover));
	// the rules' trodden ground off the streets (a crossing, the stand at the corner)
	col = mix(col, mix(col, crust * 0.8, 0.8), slush * (1.0 - road) * smoothstep(0.0, 0.25, cover));
	// on the setts under thin snow the joints still print, faintly
	col = mix(col, col * (0.92 + 0.08 * smoothstep(0.25, 0.45, lum)), road * s * (1.0 - busy) * 0.5);
	col *= 1.0 - 0.42 * occl;
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float haze = smoothstep(4.0, 40.0, length(outside));
	ALBEDO = mix(col, haze_color, haze);

	// ---- normals, wetness, the glints
	float powder = s * (1.0 - busy) * (1.0 - tramp * 0.8) * (1.0 - walked * 0.6);
	vec3 n_stone = texture(setts_nrm, suv).rgb * 2.0 - 1.0;
	vec3 n_bare = normalize(mix(vec3(0.0, 0.0, 1.0), n_stone, road * 0.8));
	vec3 nm = normalize(mix(n_bare, np, powder));
	float wet = (1.0 - s) * (1.0 - lawn) * (0.55 + 0.45 * road) + busy * (0.35 + 0.5 * wheel) + bed * 0.6 + rails * 0.5;
	float rough = mix(0.86, 0.2, clamp(wet, 0.0, 1.0));
	float spec = mix(0.32, 0.65, clamp(wet, 0.0, 1.0));
	// a grain here and there turned to the light: about one in thirty, a pixel or so across at any zoom
	float scale = max(fwidth(p.x), fwidth(p.y)) * 1.1;
	scale = exp2(ceil(log2(max(scale, 0.004))));
	vec2 gcell = floor(p / scale);
	float g = hash(gcell * 0.137 + 17.3);
	float glint = step(0.965, g) * powder * (1.0 - haze) * sparkle;
	vec3 facet = normalize(vec3((hash(gcell + 3.1) - 0.5) * 1.2, (hash(gcell + 7.7) - 0.5) * 1.2, 1.0));
	nm = normalize(mix(nm, facet, glint));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.75;
	ROUGHNESS = mix(rough, 0.14, glint);
	SPECULAR = mix(spec, 1.0, glint);
}
