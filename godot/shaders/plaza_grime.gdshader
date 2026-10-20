shader_type spatial;
// The weathering of the Plaza de Mayo kit's stuccoed fronts (plaza_kit.gd grime()): quads laid a hair off the walls,
// darkening them (blended toward the dirt's own near-black: the GL Compatibility renderer's multiply blend is off by
// its HDR scale when glow is on, the mix is not): the streaks the rain carries down from the sills, soot and damp under the cornices and string
// courses, rising damp at the foot, grime in the recesses (plaza/grime.png: four strips, UV2.x which; alpha how
// dark). The vertex colour's alpha scales it. It thins out with distance as the night's haze takes the walls, and is
// dithered away ("fade" < 1) with its building.
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D grime : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.9;
// (metres from the camera over which it thins out, as the haze takes the walls)
uniform vec2 haze = vec2(120.0, 420.0);
uniform float fade = 1.0;

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

varying float dist;

void vertex() {
	// (the game's own camera is orthographic, far back: no haze to thin it there)
	dist = PROJECTION_MATRIX[3][3] > 0.5 ? 0.0 : length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) discard;
	vec4 g = texture(grime, UV);
	float a = clamp(g.a * COLOR.a * strength * (1.0 - smoothstep(haze.x, haze.y, dist)), 0.0, 0.92);
	ALBEDO = g.rgb * COLOR.rgb * 0.25;
	ALPHA = a;
}
