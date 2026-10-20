shader_type spatial;
// The Plaza de Mayo kit's detail atlas (plaza/plaza_a.png) in one draw, the use chosen per vertex (UV2.x):
//   0 solid (doors, shutters, dark glass, signs, reliefs; front faces only), 1 cut-out and two-sided (railings,
//   balustrades, awnings, fences, twigs, papers), 2 lit from inside (warm windows, a café's front, a bus's windows; the
//   vertex colour tints and dims the light), 3 glowing (lamp globes, headlamps, a taxi's sign), 4 a palm's fronds
//   (cut-out, two-sided, white with snow where a side faces up), 5 glass by night (a car's windows: glossy).
// Dithered away ("fade" < 1) with its building; a palm's crown (a multimesh's instance, `instance_fade`) by its own
// instance's INSTANCE_CUSTOM.r, above `fade_above` metres of it. A palm's fronds sway in the wind (`sway`: how hard it
// blows; their tips most, from the crown out).
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float energy = 3.0;
uniform float glow_energy = 7.0;
uniform float snow_amount = 1.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;
uniform bool instance_fade = false;
uniform float fade_above = 0.0;
uniform float sway = 0.0;

varying flat float mode;
varying vec3 wpos;
varying vec3 wnrm;
varying float ifade;

void vertex() {
	mode = UV2.x;
	ifade = (instance_fade && VERTEX.y > fade_above) ? INSTANCE_CUSTOM.r : 1.0;
	if (sway > 0.0 && int(UV2.x + 0.5) == 4) {
		// a frond bends from the crown: the further out along it, the more (the palm's trunk is the model's y axis)
		float r = length(VERTEX.xz);
		float ph = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.21)) + r * 0.35;
		float gust = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.1 + ph * 1.7) * 0.4;
		float amp = sway * 0.022 * r * r;
		// (the wind's way in the palm's own space: its transform is a turn and a uniform scale, so the transpose will do)
		vec3 wind = transpose(mat3(MODEL_MATRIX)) * vec3(1.0, 0.0, 0.35);
		VERTEX += normalize(wind) * gust * amp + vec3(0.0, sin(TIME * 1.7 + ph * 2.3) * amp * 0.35, 0.0);
	}
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
	float f = min(fade, ifade);
	if (f < 0.999 && bayer4(FRAGCOORD.xy) > f) discard;
	int m = int(mode + 0.5);
	vec4 t = texture(atlas, UV);
	bool cut = m == 1 || m == 4;
	// (the fronds' leaflets thin out in the far mip levels: keep more of them)
	if (cut && t.a < (m == 4 ? 0.3 : 0.5)) discard;
	if (!cut && !FRONT_FACING) discard;
	if (m == 2 || m == 3) {
		ALBEDO = t.rgb * 0.12;
		EMISSION = t.rgb * COLOR.rgb * (m == 3 ? glow_energy : energy);
		ROUGHNESS = 0.25;
		SPECULAR = 0.6;
	} else if (m == 4) {
		vec3 up = FRONT_FACING ? wnrm : -wnrm;
		float n = texture(macro_tex, wpos.xz * 1.3 + wpos.y * 0.7).r;
		float n2 = texture(macro_tex, wpos.xz * 0.37 - wpos.y * 0.21).g;
		// the fronds shed much of it: snow lies in clumps along their upper faces where they lie flattest, the olive of
		// the leaflets between (about half of a crown seen from above); a crown fading over somebody sheds its snow
		// with its leaves, so that what is left of it is its own colour, not a white ghost
		float n3 = texture(macro_tex, wpos.xz * 2.1 + wpos.y * 1.3).g;
		float lie = smoothstep(0.6, 0.95, up.y + (n - 0.5) * 0.4);
		float clump = smoothstep(0.46, 0.64, n3 * 0.7 + n2 * 0.3);
		float s = clamp(lie * clump * 1.3, 0.0, 1.0) * snow_amount * COLOR.a * smoothstep(0.55, 0.98, ifade);
		// (the leaflets' dull olive, kept green under the moon from above: a little more saturated, no sheen)
		vec3 leaf = t.rgb * COLOR.rgb;
		float luma = dot(leaf, vec3(0.3, 0.55, 0.15));
		leaf = max(mix(vec3(luma), leaf, 1.35), vec3(0.0)) * 0.82;
		ALBEDO = mix(leaf, snow_color * (0.88 + 0.12 * n), s);
		ROUGHNESS = mix(0.78, 0.85, s);
		SPECULAR = mix(0.22, 0.35, s);
		BACKLIGHT = vec3(0.05, 0.06, 0.05) * (1.0 - s);
	} else if (m == 5) {
		ALBEDO = t.rgb * COLOR.rgb;
		ROUGHNESS = 0.24;
		SPECULAR = 0.7;
	} else {
		ALBEDO = t.rgb * COLOR.rgb;
		ROUGHNESS = cut ? 0.6 : 0.55;
		SPECULAR = 0.45;
	}
}
