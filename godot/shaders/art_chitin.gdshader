shader_type spatial;
// A beetle's carapace for an art-pack creature (the cascarudo; scripts/three_d/cutout.gd, the slot's finish "chitin"),
// over the friends' model as they made it: nothing of its shape or its own colour's hue changed, only made to read as
// an insect's shell in our night (the square's warm lamps, its blue sky, the snow).
// What the rigging tool baked into the model (tools/art_pack.py rig-creature) is read here: per vertex, its occlusion
// (COLOR.r: crevices and the underside dark), its convexity (COLOR.g, 0.5 flat: edges and ridges worn lighter, creases
// darker) and how much of it is leg or underside (COLOR.b: darker, matte); and where each vertex stood at rest (UV:
// x, y; UV2.x: z; each stored as value / 4 + 0.5), so that the patterns drawn on it stay put on its legs as they walk. On a model without them
// (has_bake false) the shell still reads, from its own normals and positions.
//  - a very dark olive-brown chitin (not black), a lighter tone of its own colour on the crown; close to the lens a
//    little lighter still, the legs and underside most, with more of the snow's light thrown up under it (the game's
//    camera sees it as dark as ever);
//  - fine growth ridges round the shell; its striae (grooves from front to back, spaced round its girth, a row of
//    punctures in each, the midline's suture deeper) and a few segment lines across its flanks; pitted with fine dents
//    (a bump, worked out from the screen-space slope of the pattern: it needs no UVs);
//  - polished on the crown of the shell, matte and dusty in the joints, the creases and underneath;
//  - each rib between two striae rounded, so the lamps' highlights and the night's reflection break at every line;
//    the lips either side of a groove worn lighter;
//  - the night round it in its gloss (worked out, not a probe): the city's lamplit glow low in the sky, the dark sky
//    overhead, the snow below, lamps' glints along the horizon; sharp on the polished crown, a dull sheen where matte;
//  - a thin-film sheen (oil on water: blue, green and bronze) only at grazing angles, in the highlights of the lights
//    and in that reflection;
//  - the snow's light thrown back up onto what faces down (the sky's ambient light has none from below);
//  - wet as the night goes on (darker, glossier: the lamps catch in it), the night's snow dusting what faces up;
//  - a cold rim so the dark shape reads against the white snow (off in comic ink, with the reflection).
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.333, 0.412, 0.235, 1.0);
// how dark the shell is against its own colour (a very dark olive-brown), and the underside against the shell
uniform float darken : hint_range(0.0, 2.0) = 0.85;
uniform float under_dark : hint_range(0.0, 1.0) = 0.3;
uniform bool has_bake = true;
// the pattern's scale (per model unit) and depth
uniform float ridge_freq = 140.0;
uniform float pit_scale = 90.0;
uniform float bump = 1.0;
uniform float roughness_crown : hint_range(0.0, 1.0) = 0.24;
uniform float roughness_joint : hint_range(0.0, 1.0) = 0.78;
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
uniform float film : hint_range(0.0, 2.0) = 0.9;
uniform float wear : hint_range(0.0, 2.0) = 1.0;
// the worn edges' and the plates' lips' colour (a dusty tan), the dust in its joints and creases
uniform vec3 worn_color : source_color = vec3(0.4, 0.36, 0.27);
uniform vec3 dust_color : source_color = vec3(0.34, 0.32, 0.29);
uniform float dust : hint_range(0.0, 1.0) = 0.35;
// how rounded each rib is between two striae (the highlights break at the lines); how many striae to a radian round
// the shell's long axis (the model's z, at the height axis_y, model units); where its wing cases begin, from the front
// (the model's -z) back (model units: the plate in front of them, over its head, is smooth)
uniform float plate_dome : hint_range(0.0, 3.0) = 1.0;
uniform float striae = 9.0;
uniform float axis_y = 0.75;
uniform float elytra_from = -0.3;
uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 0.98);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.4;
// the night in its gloss: the sky overhead, the city's lamplit glow low in it, the snow below; how much of it, how many
// lamps' glints along the horizon
uniform vec3 env_zenith : source_color = vec3(0.06, 0.08, 0.15);
uniform vec3 env_horizon : source_color = vec3(0.75, 0.58, 0.42);
uniform vec3 env_ground : source_color = vec3(0.5, 0.51, 0.58);
uniform float env_strength : hint_range(0.0, 4.0) = 1.0;
uniform float glints : hint_range(0.0, 4.0) = 1.0;
// close to (a trailer's lens, a close look: under near_from metres to a pixel) its tone is lifted, the legs and
// underside more, and more of the snow's light is thrown up under it, so its plates and joints read; at the game's
// camera (past near_to) it is as dark as ever, a shape against the snow
uniform float near_from = 0.014;
uniform float near_to = 0.026;
uniform float near_lift : hint_range(0.0, 2.0) = 0.12;
uniform float near_under_lift : hint_range(0.0, 2.0) = 0.45;
uniform float near_bounce : hint_range(0.0, 2.0) = 0.6;
// the snow's light thrown back up onto what faces down (the sky's ambient has none from below): its colour, how much
uniform vec3 bounce_color : source_color = vec3(0.78, 0.78, 0.86);
uniform float bounce : hint_range(0.0, 2.0) = 1.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float snow = 0.0;
uniform float wet = 0.0;
// the height (model units) above which the shell's crown is (polished), and above which snow can lie
uniform float crown_from = 1.15;
uniform float snow_from = 0.72;
uniform float snow_up : hint_range(0.0, 1.0) = 0.62;
uniform float snow_scale = 9.0;
// metres per model unit (the bump's height is worked out in the model's units)
uniform float model_scale = 2.0;

varying vec3 rest;
varying vec3 world_n;
varying vec4 bake;
varying float film_t;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// (stored as value / 4 + 0.5)
	rest = has_bake ? (vec3(UV.x, UV.y, UV2.x) - 0.5) * 4.0 : VERTEX;
	bake = has_bake ? COLOR : vec4(0.8, 0.5, step(NORMAL.y, -0.2), 1.0);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
	               mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
	               mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// growth ridges round the shell: fine bands following its height and its girth, wobbled (0..1, peaks narrow)
float ridges_at(vec3 p) {
	float wob = noise3(p * 7.0) * 2.0 + noise3(p * 19.0) * 0.6;
	float r1 = sin(p.y * ridge_freq + wob * 2.2);
	float r2 = sin(length(p.xz) * ridge_freq * 0.7 + wob * 1.6);
	return pow(mix(r2, r1, 0.55) * 0.5 + 0.5, 3.0);
}

// the shell's lines: x the grooves (its striae from front to back, spaced round its girth and a little wavy, the
// midline's suture deeper, a few segment lines across its flanks; 0..1), y how high the rib between two striae stands
// there (rounded), z the lip either side of a stria, w the punctures in a row along each stria
vec4 plates_at(vec3 p) {
	float wav = noise3(p * 4.0) * 0.25;
	vec2 round_ = vec2(p.x, p.y - axis_y);
	float ang = atan(round_.x, round_.y) + (noise3(p * 3.0) - 0.5) * 0.06;
	float u = ang * striae;
	float a = abs(fract(u) - 0.5) * 2.0;
	// (none round the ends of the axis, where they would all meet)
	float poles = smoothstep(0.32, 0.55, length(round_)) * smoothstep(elytra_from - 0.12, elytra_from + 0.12, p.z);
	float stria = smoothstep(0.86, 0.97, a) * poles;
	float suture = (1.0 - smoothstep(0.008, 0.026, abs(ang) * length(round_))) * step(0.0, round_.y) * poles;
	float c = abs(fract(p.z * 3.2 + wav) - 0.5) * 2.0;
	float flank = smoothstep(0.5, 1.0, abs(ang));
	float groove = max(max(stria * 0.45, suture), smoothstep(0.93, 0.985, c) * flank * 0.8);
	float rib = (1.0 - a * a) * poles;
	float lip = smoothstep(0.7, 0.86, a) * (1.0 - smoothstep(0.88, 0.94, a)) * poles;
	float punct = smoothstep(0.84, 0.96, a) * smoothstep(0.55, 0.85, 1.0 - abs(fract(p.z * 20.0 + floor(u) * 0.37) - 0.5) * 2.0) * poles;
	return vec4(groove, rib, lip, punct);
}

// the thin film's colour, round blue, green and bronze
vec3 film_colour(float t) {
	vec3 bronze = vec3(0.85, 0.55, 0.22);
	vec3 green = vec3(0.25, 0.85, 0.45);
	vec3 blue = vec3(0.25, 0.45, 1.0);
	float k = t * 3.0;
	return k < 1.0 ? mix(bronze, green, k) : (k < 2.0 ? mix(green, blue, k - 1.0) : mix(blue, bronze, k - 2.0));
}

void fragment() {
	float ao = clamp(bake.r, 0.0, 1.0);
	float convex = (bake.g - 0.5) * 2.0;
	float under = clamp(bake.b, 0.0, 1.0);
	vec3 wn = normalize(world_n);
	float crown = smoothstep(crown_from - 0.25, crown_from + 0.2, rest.y) * (1.0 - under);
	float shell = 1.0 - under;
	// how fine a pattern this pixel can hold (a pattern finer than a pixel or two fades to its average)
	float px = length(fwidth(rest));
	float f_ridge = 1.0 - smoothstep(0.35, 1.2, px * ridge_freq * 0.5);
	float f_seg = 1.0 - smoothstep(0.4, 1.2, px * 40.0);
	float f_dome = 1.0 - smoothstep(0.6, 1.4, px * 60.0);
	// how near the lens is (metres to a pixel at this depth, either lens)
	float mpp = (PROJECTION_MATRIX[3][3] > 0.5 ? 1.0 : abs(VERTEX.z)) * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float near = 1.0 - smoothstep(near_from, near_to, mpp);
	float f_pit = 1.0 - smoothstep(0.35, 1.2, px * pit_scale * 0.5);
	// the scales of it: big mottles (they read from the game's camera), the plates' lines, the growth ridges, the pits
	float mott = noise3(rest * 2.6) * 0.65 + noise3(rest * 6.1 + 3.3) * 0.35;
	float hue = noise3(rest * 1.7 + 11.0);
	float ridge = ridges_at(rest) * mix(0.3, 1.0, crown) * shell;
	vec4 plate = plates_at(rest);
	float seg = plate.x * shell;
	float lip = plate.z * shell * f_seg;
	float pits = smoothstep(0.74, 0.9, noise3(rest * pit_scale)) + 0.5 * smoothstep(0.78, 0.92, noise3(rest * pit_scale * 2.3 + 7.1))
		+ plate.w * shell;
	float grain = noise3(rest * pit_scale * 3.0);
	// the height the bump is worked from (model units)
	float h = (ridge * 0.5 * f_ridge - seg * 1.2 * f_seg - pits * 0.3 * f_pit + (grain - 0.5) * 0.06 * f_pit
		+ plate.y * plate_dome * shell * 1.5 * f_dome) * bump * 0.004;
	// the bump: the slope of that height across the screen, turned into a tilt of the normal (no UVs needed)
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	vec3 bumped = normalize(abs(det) * NORMAL - grad * model_scale);
	// colour: its own olive deepened to a near-black brown-green, mottled greener and browner; browner and darker
	// underneath and on the legs; a touch lighter on the crown; worn lighter on edges and ridges, dark in creases,
	// the plates' lines and pits
	vec3 brown = vec3(0.105, 0.072, 0.04) * darken / 0.6;
	vec3 base = mix(albedo.rgb * darken, brown, mix(0.25, 0.65, hue));
	base = mix(base, brown * 0.8, under * 0.6);
	base *= mix(1.0, 1.0 - under_dark * 0.6, under);
	base *= (1.0 + 0.4 * crown) * mix(0.8, 1.2, mott);
	float worn = clamp(convex * 1.8, -1.0, 1.0);
	base *= 1.0 + wear * 0.5 * max(worn, 0.0) - 0.35 * max(-worn, 0.0);
	base *= 1.0 + 0.35 * (ridge - 0.25) * f_ridge;
	base *= 1.0 - 0.5 * seg * f_seg - 0.12 * pits * f_pit * (1.0 - 0.5 * under);
	// the edges and the plates' lips worn to a dusty tan (patchy), dust in the joints and creases
	float scuff = clamp(wear * (0.55 * max(worn, 0.0) + 0.45 * lip) * (0.5 + mott), 0.0, 0.65);
	base = mix(base, worn_color * mix(0.4, 0.6, mott), scuff);
	float dusty = clamp(max(-convex, 0.0) * 1.4 + (1.0 - ao) * 0.7, 0.0, 1.0) * (1.0 - crown);
	base = mix(base, dust_color * 0.32, dust * dusty * 0.7);
	base *= mix(0.55, 1.0, ao);
	base *= 1.0 + near * mix(near_lift, near_under_lift, under);
	// wet with the night: darker, glossier; the night's snow dusting what faces up
	float s_up = smoothstep(snow_up - 0.15, snow_up + 0.2, wn.y + (noise3(rest * snow_scale) - 0.5) * 0.45);
	float high = smoothstep(snow_from - 0.08, snow_from + 0.12, rest.y);
	float patch = noise3(rest * snow_scale) * 0.6 + noise3(rest * snow_scale * 3.1) * 0.4;
	float s = s_up * high * smoothstep(0.0, 1.0, snow * (0.35 + patch * 1.1)) * (0.6 + 0.4 * ao);
	float w = wet * (1.0 - s);
	base *= mix(1.0, 0.75, w);
	// polished on the crown, matte and dusty in the joints, the creases and underneath; mottled; the ridges' tops shine
	float rough = mix(roughness_crown, roughness_joint, clamp(max(under, 1.0 - ao * 1.15) + max(-convex, 0.0) * 0.8, 0.0, 1.0));
	rough += (mott - 0.5) * 0.22 + 0.25 * seg * f_seg + 0.15 * pits * f_pit - 0.08 * ridge * f_ridge;
	rough = mix(rough, rough * 0.55, w);
	// the oil-slick film: which colour by the angle and a slow drift over the shell
	film_t = fract(dot(bumped, normalize(VIEW)) * 1.7 + noise3(rest * 3.0) * 0.6);
	ALBEDO = mix(base, snow_color * (0.88 + 0.12 * patch), s);
	NORMAL = normalize(mix(bumped, NORMAL, s));
	float rgh = clamp(mix(rough, 0.95, s), 0.04, 1.0);
	ROUGHNESS = rgh;
	SPECULAR = mix(specular_value * mix(0.55, 1.0, ao), 0.3, s);
	METALLIC = 0.0;
	AO = mix(ao, 1.0, s * 0.6);
	AO_LIGHT_AFFECT = 0.35;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	EMISSION = rim_color * rim * (rim_strength + sheen * 0.4) * ao * (1.0 - s) * (1.0 - 0.7 * under) * 0.5;
	// the night in its gloss: the sky, the city's glow low in it and the snow below, reflected (in the world's frame);
	// sharp where polished, a dull blur where matte; lamps' glints along the horizon; the thin film's colours at a slant
	vec3 bv = normalize(mix(bumped, NORMAL, s));
	vec3 rv = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, bv), 0.0)).xyz);
	float gl = 1.0 - rgh;
	float sharp = gl * gl;
	float band = mix(0.55, 0.05, sharp);
	vec3 env = rv.y >= 0.0 ? mix(env_horizon, env_zenith, smoothstep(-0.02, band * 1.6, rv.y))
		: mix(env_horizon * 0.7, env_ground, smoothstep(0.0, band, -rv.y));
	float az = atan(rv.x, rv.z);
	float lamp = smoothstep(0.66, 0.9, noise3(vec3(az * 7.0, rv.y * 9.0, 2.0))) * (1.0 - smoothstep(0.02, 0.3, abs(rv.y - 0.08)));
	env += env_horizon * lamp * glints * 3.0 * sharp;
	env = mix((env_horizon + env_zenith + env_ground) * 0.2, env, 0.15 + 0.85 * sharp);
	float ndv = clamp(dot(bv, VIEW), 0.0, 1.0);
	float fres = (0.045 + 0.955 * pow(1.0 - ndv, 5.0)) * mix(1.0, 0.3, rgh);
	vec3 tint = mix(vec3(1.0), film_colour(film_t) * 1.6, clamp(pow(1.0 - ndv, 1.6) * film * (1.0 - s), 0.0, 1.0));
	// the snow's light thrown back up under it (dimmer when snow lies on it: that faces up)
	float below = clamp(0.5 - 0.5 * wn.y, 0.0, 1.0);
	EMISSION += ALBEDO * bounce_color * bounce * (1.0 + near * near_bounce) * below * mix(0.4, 1.0, ao) * mix(0.45, 1.0, under);
	// the thin film in the sky's light, at a slant (a colour of its own, faint, on the polished parts)
	EMISSION += film_colour(film_t) * film * pow(1.0 - ndv, 3.0) * 0.07 * sharp * ao * (1.0 - s) * clamp(sheen * 2.5, 0.0, 1.5);
	EMISSION += env * tint * fres * env_strength * clamp(sheen * 2.5, 0.0, 1.5) * mix(ao * ao, 1.0, 0.25) * (1.0 - 0.6 * s);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// wrapped light, as the squad's
	float wrap = clamp((ndl + 0.3) / 1.3, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap / PI;
	// a GGX highlight; at grazing angles its colour runs through the film's
	vec3 hv = normalize(VIEW + LIGHT);
	float ndh = max(dot(NORMAL, hv), 0.0);
	float ndv = max(dot(NORMAL, VIEW), 0.001);
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((ndv * (1.0 - k) + k) * (max(ndl, 0.0) * (1.0 - k) + k));
	float vdh = max(dot(VIEW, hv), 0.0);
	float fres = pow(1.0 - vdh, 5.0);
	float graze = pow(1.0 - ndv, 2.5);
	vec3 f0 = vec3(0.04 + 0.04 * SPECULAR_AMOUNT);
	vec3 tint = mix(vec3(1.0), film_colour(film_t) * 1.6, clamp(graze * film, 0.0, 1.0));
	vec3 f = (f0 + (1.0 - f0) * fres) * tint;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * max(ndl, 0.0) * d * vis * f;
}
