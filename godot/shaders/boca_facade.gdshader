shader_type spatial;
// La Boca's facade atlas (boca/facade_a.png): windows dark and lit, shutters, doors, painted signs, railings,
// awnings. One shader, three uses: shaded and solid (doors, shutters, dark glass, signs), shaded cut-out and
// two-sided (railings, balustrades, awnings; "cutout"), and lit from inside ("lit": the warm windows, a shop's door,
// a porthole), where the vertex colour tints and dims the light. Dithered away with its building ("fade").
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool cutout = false;
uniform bool lit = false;
// one surface for both (La Boca's kits): cut-out everywhere, lit where the vertex's UV2.x is 1
uniform bool layered = false;
uniform float energy = 2.4;
uniform float fade = 1.0;

varying flat float lit_v;

void vertex() {
	lit_v = UV2.x;
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
	vec4 t = texture(atlas, UV);
	bool is_lit = layered ? lit_v > 0.5 : lit;
	bool is_cut = layered ? !is_lit : cutout;
	if (is_cut && t.a < 0.5) discard;
	if (!is_cut && !is_lit && !FRONT_FACING) discard;
	if (is_lit) {
		ALBEDO = t.rgb * 0.12;
		EMISSION = t.rgb * COLOR.rgb * energy;
		ROUGHNESS = 0.25;
		SPECULAR = 0.6;
	} else {
		ALBEDO = t.rgb * COLOR.rgb;
		ROUGHNESS = is_cut ? 0.6 : 0.55;
		SPECULAR = 0.45;
	}
}
