shader_type spatial;
// An art-pack model in our night's snow (scripts/three_d/cutout.gd, the slot's "finish"): its own colours (its texture,
// or its material's colour) and nothing of its design changed, only made to read under our lights:
//  - its texture sampled sharp (mipmaps a little sharper than the default choice of them), so its atlas stays crisp at
//    the distance the game sees it from, and smooth up close (a drawn face reads as a drawing, not as pixels);
//  - lit like the squad (wrapped light, the sky's fill from above);
//  - wet as the night goes on (darker, glossier) and the night's snow settling where it faces up, above a height (a
//    man's hood and shoulders; a creature's back);
//  - a cold rim round its edge (and on a gloss, a cold sheen), so a dark shape reads against the white snow.
// The snow and the wet are set for all of them at once as the night goes on (cutout.gd weather()).
//
// Cloth that brings its own bake (tools/art_pack.py refine-person: Juan Salvo's model; its vertex colours' alpha under
// one half marks it) is dressed as the squad's clothes are (character_cloth.gdshader): its atlas's alpha names what
// each swatch is (k / 15: 14 twill, 13 canvas, 12 padded cloth, 11 leather, 10 rubber, 9 dark hard, 8 steel, 7 glass,
// 6 skin; 15 none), and for each its grain (in the figure's own rest space, so it stays put on the cloth as he moves),
// its roughness and sheen; its baked occlusion (R) shading the creases and what is tucked away; mud and wet from the
// ground up and in the creases (G); its edges rubbed lighter (B); its cloth bunched in folds at the bends (A); its colours
// held to the night's range in the atlas (no brighter, no more saturated than the squad's, its hues as they are); and
// the squad's soft sheen at the edge in place of most of the cold rim; and a few flakes on the crown of his head from
// the start, as on the squad's caps.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = true;
uniform vec4 albedo : source_color = vec4(1.0);
// the brightness of its colours (a chitin darker than its swatch)
uniform float darken : hint_range(0.0, 2.0) = 1.0;
// a sharper choice of mipmap than the default (negative: sharper)
uniform float tex_bias : hint_range(-2.0, 1.0) = -0.6;
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.85;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.5;
uniform float specular_value : hint_range(0.0, 1.0) = 0.4;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float sky_fill : hint_range(0.0, 1.0) = 0.25;
uniform vec3 rim_color : source_color = vec3(0.6, 0.72, 0.95);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.15;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
// a cold sheen across its gloss, strongest where it turns from the light
uniform float sheen : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.9, 0.95);
// the night's snow on it (0..1) and how wet it is (0..1)
uniform float snow = 0.0;
uniform float wet = 0.0;
// snow only above this height (model units, as the model stands) and on faces this much upward
uniform float snow_from = 0.0;
uniform float snow_up : hint_range(0.0, 1.0) = 0.55;
// the size of its patches (per model unit)
uniform float snow_scale = 7.0;
// how much a wet surface darkens
uniform float wet_dark : hint_range(0.0, 1.0) = 0.35;

// a skinned figure: where each vertex stood at rest and how far up it faced there (CUSTOM0), so the snow stays where it
// settled (on the hood and shoulders) however he moves, and does not land on an arm he raises
uniform bool rest_snow = false;

// --- baked cloth (see above)
// how dark its glass is (it shows what it reflects)
uniform float glass_dark : hint_range(0.0, 1.0) = 0.6;
// how much of its baked occlusion darkens it, and how deep its folds and grain are
uniform float occlusion : hint_range(0.0, 1.0) = 0.75;
uniform float folds : hint_range(0.0, 2.0) = 1.0;
uniform float grain : hint_range(0.0, 2.0) = 1.0;
uniform vec3 mud_color : source_color = vec3(0.24, 0.2, 0.16);
// the squad's sheen at the edge (character_cloth.gdshader), and how much of the cold rim a baked figure keeps
uniform float cloth_sheen : hint_range(0.0, 0.5) = 0.14;
uniform float baked_rim : hint_range(0.0, 1.0) = 0.3;
// a little snow on the crown of his head from the start, as on the squad's caps (more as the night goes on)
uniform float crown_snow : hint_range(0.0, 1.0) = 0.7;
// a model that brings its own physical maps (cutout.gd, the finish "pbr"): its normal map, and its packed occlusion (R),
// roughness (G) and metal (B), read as they are
uniform bool use_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
uniform bool use_orm = false;
uniform bool orm_ao = true;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 obj;
varying vec3 world_n;
varying float up_n;
varying vec4 bake;
varying float baked;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	obj = VERTEX;
	up_n = world_n.y;
	if (rest_snow) {
		obj = CUSTOM0.xyz;
		up_n = CUSTOM0.w;
	}
	bake = COLOR;
	baked = step(COLOR.a, 0.502);
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

// a pattern's contrast faded out as it gets finer than a few pixels (no shimmer far off)
float fine(float phase) {
	return clamp(1.5 - fwidth(phase) * 0.9, 0.0, 1.0);
}

// the normal tilted by a height field (metres) over the surface, from its screen derivatives (no tangents needed)
vec3 bumped(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dhdx * r1 + dhdy * r2);
	vec3 b = abs(det) * n - g;
	return dot(b, b) > 1e-24 ? normalize(b) : n;
}

void fragment() {
	vec4 t = use_tex ? texture(albedo_tex, UV, tex_bias) : vec4(1.0);
	vec3 base = albedo.rgb * darken * t.rgb;
	vec3 wn = normalize(world_n);
	// --- baked cloth: what the swatch is, and its grain, folds, mud and wear
	float kind = baked > 0.5 && use_tex ? floor(t.a * 15.0 + 0.5) : 15.0;
	bool cloth = kind >= 12.0 && kind <= 14.0;
	bool hide = kind >= 10.0 && kind <= 11.0;
	float rough = roughness_dry;
	float spec = specular_value;
	float metal = metallic_value;
	float height = 0.0;
	// the patterns' phases and how far each is faded (screen derivatives taken here, outside any branch)
	float ph_twill = dot(obj, vec3(0.62, 0.74, 0.26)) * 1100.0;
	float fade_twill = fine(ph_twill);
	float fade_weave = fine(obj.y * 900.0);
	float fade_fibre = fine(obj.y * 260.0);
	float fade_pebble = fine(obj.x * 340.0);
	float ph_fold = obj.y * 95.0 + noise3(obj * 8.0) * 7.0 + obj.x * 18.0;
	float fade_fold = fine(ph_fold);
	if (kind > 14.5 && use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		rough = orm.g;
		metal = orm.b;
		spec = mix(0.3, 0.5, 1.0 - orm.g);
		if (orm_ao) {
			AO = orm.r;
			AO_LIGHT_AFFECT = 0.25;
			spec *= mix(0.5, 1.0, orm.r);
		}
	}
	if (kind < 14.5) {
		float ao = bake.r;
		float mud = bake.g;
		float wear = bake.b;
		float fold = clamp((0.5 - bake.a) * 2.0, 0.0, 1.0) * folds;
		// (its colours are held to the night's range in the atlas already); glass is dark, its light is reflected
		if (kind == 7.0) base *= glass_dark;
		// the grain of it, fixed on the cloth (rest space, metres)
		float mottle = noise3(obj * 21.0) * 0.6 + noise3(obj * 63.0) * 0.4 - 0.5;
		float fibre = noise3(obj * 260.0) - 0.5;
		if (kind == 14.0) {
			// twill: fine diagonal ribs over a soft mottle
			float rib = sin(ph_twill) * fade_twill;
			base *= 1.0 + grain * (0.14 * mottle + 0.05 * rib + 0.06 * fibre * fade_fibre);
			height += grain * (0.00012 * rib);
			rough = 0.9;
			spec = 0.3;
		} else if (kind == 13.0) {
			// canvas and webbing: a plain weave
			vec3 q = obj * 900.0;
			float w = sin(q.x + q.z) * sin(q.y) * fade_weave;
			base *= 1.0 + grain * (0.16 * mottle + 0.05 * w + 0.05 * fibre);
			height += grain * 0.0001 * w;
			rough = 0.93;
			spec = 0.28;
		} else if (kind == 12.0) {
			// the padded cloth of the hood: soft quilting lumps, a faint nap
			float lump = noise3(obj * 34.0);
			base *= 1.0 + grain * (0.12 * mottle + 0.08 * (lump - 0.5) + 0.04 * fibre);
			height += grain * 0.0012 * lump;
			rough = 0.82;
			spec = 0.32;
		} else if (kind == 11.0) {
			// leather: a pebbled grain, creased, its edges rubbed pale
			float peb = noise3(obj * 340.0);
			base *= 1.0 + grain * (0.18 * mottle + 0.06 * (peb - 0.5) * fade_pebble);
			height += grain * 0.00015 * peb;
			rough = 0.58;
			spec = 0.42;
		} else if (kind == 10.0) {
			base *= 1.0 + grain * (0.1 * mottle);
			rough = 0.62;
			spec = 0.36;
		} else if (kind == 9.0) {
			base *= 1.0 + grain * (0.08 * mottle);
			rough = 0.45;
			spec = 0.48;
		} else if (kind == 8.0) {
			base *= 1.0 + grain * (0.1 * mottle);
			rough = 0.38;
			spec = 0.5;
			metal = 0.55;
		} else if (kind == 7.0) {
			rough = 0.1;
			spec = 0.75;
		} else if (kind == 6.0) {
			base *= 1.0 + 0.05 * mottle;
			rough = 0.62;
			spec = 0.34;
		}
		// folds: cloth bunched in rings round the bend, wandering a little
		if (cloth || hide) {
			float ridge = 0.5 + 0.5 * sin(ph_fold);
			float f = fold * smoothstep(0.15, 0.6, noise3(obj * 13.0 + 3.1)) * fade_fold;
			base *= 1.0 - 0.32 * f * (1.0 - ridge) * (1.0 - ridge);
			height += 0.0035 * f * ridge;
		}
		// worn edges: leather, rubber, canvas and steel rubbed lighter and greyer; cloth only a little fuzzed
		float rub = wear * (0.55 + 0.9 * noise3(obj * 31.0));
		float wear_k = hide ? 0.55 : (kind == 13.0 ? 0.4 : (kind == 8.0 || kind == 9.0 ? 0.6 : (cloth ? 0.15 : 0.0)));
		vec3 pale = mix(base, vec3(dot(base, vec3(0.33))), 0.4) * 1.45 + 0.01;
		base = mix(base, pale, clamp(rub * wear_k, 0.0, 1.0));
		// mud: splashed up from the ground and worked into the creases, in patches
		float splash = mud * smoothstep(0.25, 0.75, noise3(obj * 17.0 + 7.0) * 0.7 + mud * 0.6);
		float mud_k = cloth || hide ? 0.6 : (kind == 6.0 || kind == 7.0 ? 0.0 : 0.35);
		base = mix(base, mud_color * (0.75 + 0.5 * noise3(obj * 45.0)), clamp(splash * mud_k, 0.0, 0.85));
		rough = mix(rough, 0.95, splash * mud_k * 0.6);
		// occlusion: the creases, the armpits, the coat's inside, the respirator's shadow (not on the face or the glass:
		// they sit inside the hood and would go dark)
		float occ = kind == 6.0 || kind == 7.0 ? 0.0 : occlusion;
		base *= mix(1.0, ao, occ * 0.5);
		AO = mix(1.0, ao, occ);
		AO_LIGHT_AFFECT = 0.3;
		spec *= mix(0.4, 1.0, ao);
	}
	// snow: where it faces up, above its height, in patches that grow with the night
	float patch = noise3(obj * snow_scale) * 0.65 + noise3(obj * snow_scale * 2.7) * 0.35;
	float up = smoothstep(snow_up - 0.2, snow_up + 0.25, up_n + (patch - 0.5) * 0.5);
	float high = smoothstep(snow_from - 0.04, snow_from + 0.06, obj.y);
	// a dusting first, patchy, that thickens and closes up as the night goes on
	float s = up * high * smoothstep(0.0, 1.0, snow * (0.45 + patch * 1.1));
	// a baked figure: flakes lying on the crown of his head whatever the hour (cutout.gd sets snow_from at 0.7 of his
	// height for cloth: the crown is what faces up above 0.92 of it)
	float top_y = snow_from / 0.7 * 0.92;
	float crown = (kind < 14.5 ? 1.0 : 0.0) * smoothstep(0.5, 0.85, up_n) * smoothstep(top_y - 0.02, top_y + 0.03, obj.y);
	float flake = smoothstep(0.66, 0.78, noise3(obj * 150.0)) * (0.65 + 0.35 * noise3(obj * 41.0));
	s = max(s, crown * flake * crown_snow * (0.7 + 0.3 * clamp(snow * 2.0, 0.0, 1.0)));
	float w = wet * (1.0 - s);
	base *= mix(1.0, 1.0 - wet_dark, w);
	float shade = mix(1.0 - sky_fill, 1.0, wn.y * 0.5 + 0.5);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	// the snow lies in the grain: a little lumpy; the relief of grain, folds and snow (outside any branch: derivatives)
	height += kind < 14.5 ? 0.002 * s * noise3(obj * 90.0) : 0.0;
	vec3 relief = bumped(NORMAL, VERTEX, height);
	if (kind < 14.5) {
		// the squad's soft sheen at the edge, on cloth
		base *= 1.0 + cloth_sheen * (1.0 - facing) * (1.0 - facing) * (cloth ? 1.0 : 0.5);
		NORMAL = relief;
	}
	if (kind > 14.5 && use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth * (1.0 - s);
	}
	ALBEDO = mix(base * shade, snow_color * (0.9 + 0.1 * patch), s);
	ROUGHNESS = mix(mix(rough, min(rough, roughness_wet), w), 0.92, s);
	SPECULAR = mix(mix(spec, max(spec, 0.55), w), 0.3, s);
	METALLIC = metal * (1.0 - s);
	float rim_k = kind < 14.5 ? baked_rim : 1.0;
	EMISSION = rim_color * (rim * rim_strength * rim_k + sheen * rim * rim * 0.6) * (1.0 - s);
}
