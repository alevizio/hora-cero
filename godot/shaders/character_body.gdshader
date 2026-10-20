shader_type spatial;
// Skinned, vertex-coloured character surface (one draw call per figure).
// COLOR.rgb = sRGB albedo with baked occlusion, UV.x = roughness, UV.y = metallic.
// CUSTOM0.xyz = where the vertex sits in the bind pose, CUSTOM0.w = which surface it is
// (0 wool, 1 canvas, 2 leather, 3 skin, 4 hair, 5 plain). The texture is worked out from the
// bind-pose position, so it stays on the cloth however the figure moves, and its finest grain
// fades out once it would be smaller than a pixel.
render_mode diffuse_lambert_wrap;

uniform float sky_fill : hint_range(0.0, 1.0) = 0.30; // how much down-facing surfaces darken
uniform float sheen : hint_range(0.0, 0.5) = 0.10;    // soft cloth rim that lifts the figure off the ground
uniform vec3 tint : source_color = vec3(1.0);          // dulled for a body lying hidden in cover
uniform float grain : hint_range(0.0, 2.0) = 1.0;      // strength of the cloth, leather and skin texture

varying vec3 base;
varying vec4 rest;

void vertex() {
	float up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
	base = COLOR.rgb * tint * mix(1.0 - sky_fill, 1.0, up * 0.5 + 0.5);
	rest = CUSTOM0;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// Brightness change (about +-0.1) for a surface at bind-pose point p.
float surface_grain(vec3 p, float kind, float px) {
	float fine = 1.0 - smoothstep(0.0012, 0.0035, px); // threads and pores: only up close
	float mid = 1.0 - smoothstep(0.005, 0.018, px);    // mottling: from mid zoom in
	float k = 0.0;
	if (kind < 0.5) {
		// wool serge: blotchy dye, a diagonal twill and a little fuzz
		k += (vnoise(p * 21.0) - 0.5) * 0.06;
		k += (vnoise(p * 68.0) - 0.5) * 0.10 * mid;
		k += sin((p.x + p.y + p.z) * 1900.0) * 0.035 * fine;
		k += (vnoise(p * 240.0) - 0.5) * 0.09 * fine;
	} else if (kind < 1.5) {
		// canvas: a plain weave and uneven dye
		k += (vnoise(p * 34.0) - 0.5) * 0.10;
		k += sin(p.y * 2300.0) * sin((p.x + p.z) * 2300.0) * 0.04 * fine;
	} else if (kind < 2.5) {
		// leather: worn patches and a pebbled grain
		k += (vnoise(p * 32.0) - 0.5) * 0.16;
		k += (vnoise(p * 280.0) - 0.5) * 0.12 * fine;
	} else if (kind < 3.5) {
		// skin: faint blotches
		k += (vnoise(p * 85.0) - 0.5) * 0.06 * mid;
	} else if (kind < 4.5) {
		// hair: strands, combed more or less downwards
		k += (vnoise(p * vec3(380.0, 55.0, 380.0)) - 0.5) * 0.26 * mid;
	}
	return k;
}

void fragment() {
	float px = length(fwidth(rest.xyz));
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = base * (1.0 + surface_grain(rest.xyz, rest.w, px) * grain) * (1.0 + sheen * rim * rim * UV.x);
	ROUGHNESS = UV.x;
	METALLIC = UV.y;
	SPECULAR = 0.4;
}
