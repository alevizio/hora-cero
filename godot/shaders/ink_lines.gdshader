shader_type spatial;
// Comic ink, the drawing half (scripts/three_d/ink.gd; ink_paper.gdshader prints it). One quad over the whole view,
// drawn first among the blended passes (render priority below everything else that blends), so that it reads the
// solid world from the screen and depth textures and redraws it as a pen drawing:
//  - outlines where the depth jumps (silhouettes) or bends (creases), and where the picture's brightness steps hard
//    (a lit window, a door, a stripe of paint);
//  - the tone posterised into bare paper, hatching, cross-hatching and solid black;
//  - the hatching drawn ON the surfaces (world-anchored, so it stays put when the view pans or turns), in a direction
//    of its own for the ground and for each way a wall faces, its spacing kept near hatch_px pixels at any zoom by
//    stepping between octaves;
//  - lamps, lit windows and snow left as bare paper.
// The output is grey (0 ink .. 1 paper); the paper's colour, its grain and the halftone are the print pass's job.
// The blended passes drawn after this one (sight cones, routes, markers, x-rays, falling snow, mist) go over the
// drawing as they are; the print pass keeps their colour where it is strong.
// The game runs on the Compatibility renderer: depth comes back in [0, 1] and is mapped to OpenGL's [-1, 1]; the
// screen texture holds the opaque world as the tonemapper made it, and ink.gd sets the tonemapper to pass this
// quad's grey through untouched (linear, exposure 1, white 1).
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform float line_scale = 1.0;     // outline width in pixels at 720 lines (twice this is drawn: both sides of a step)
uniform float crease = 1.3;         // bend in the depth (change of slope) that draws a crease line
uniform float crease_soft = 0.9;    // and over how much more it reaches full black
uniform float color_edge = 0.32;    // brightness step that draws a line (0 = off)
uniform float exposure = 1.0;       // scene brightness gain before the tone is posterised
uniform float gamma_k = 1.0;        // and a curve on it (below 1 lifts the darks)
uniform vec4 levels = vec4(0.10, 0.22, 0.36, 0.52); // solid black below .x, cross-hatching below .y, hatching below .z, fine hatching below .w
uniform float soft = 0.035;         // width of the step between two tones
uniform float hatch_px = 7.0;       // hatch spacing on screen, in pixels at 720 lines
uniform float light = 0.93;         // brighter than this (lamps, lit windows) stays bare paper, lines and all
uniform float far_fade = 0.0;       // 0..1: how much the hatching thins with distance (atmosphere)
uniform float sky_ink = 0.0;        // the empty background: 0 paper, 1 solid black
uniform bool lite = false;          // phones: 5 depth and 3 colour samples instead of 9 and 5 (no diagonal creases)
uniform int debug_view = 0;         // 1 depth edges, 2 normals, 3 tone bands, 4 hatch only, 5 the screen as read

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// The view-space position of the pixel `p` (clamped to the view) from the depth texture.
vec3 view_at(sampler2D depth, ivec2 p, ivec2 lim, vec2 size, mat4 inv_proj) {
	ivec2 q = clamp(p, ivec2(0), lim);
	float d = texelFetch(depth, q, 0).r;
	vec2 uv = (vec2(q) + 0.5) / size;
	vec4 v = inv_proj * vec4(vec3(uv, d) * 2.0 - 1.0, 1.0);
	return v.xyz / v.w;
}

// Line pattern: 1 on the lines (spacing `s`, half-width `w` as a share of the spacing), 0 between, antialiased.
float lines(float coord, float s, float w) {
	float f = coord / s;
	float d = abs(fract(f + 0.5) - 0.5);
	float aa = max(fwidth(f), 0.0005);
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

// The same lines at the two octaves round the wanted spacing, cross-faded: the in-between lines fade as the view
// pulls back, instead of every line swimming.
float hatch(float coord, float other, float s0, float t, float w) {
	float wob = s0 * 0.09 * sin(other / s0 * 0.73) + s0 * 0.05 * sin(other / s0 * 2.31 + 1.7);
	// the pen's pressure: each line swells and thins along its length, and no two lines alike
	float row = floor(coord / s0 + 0.5);
	float press = 0.7 + 0.3 * sin(other / s0 * 0.37 + row * 2.39) + 0.18 * sin(other / s0 * 1.13 + row * 5.1);
	w *= press;
	float a = lines(coord + wob, s0, w);
	float b = lines(coord + wob, s0 * 2.0, w * 0.5);
	return mix(a, b, t);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 size = VIEWPORT_SIZE;
	float res = max(size.y / 720.0, 0.75);
	// whole pixels: neighbours are fetched, never filtered, so a flat surface stays exactly flat
	int r = max(1, int(round(line_scale * res)));
	ivec2 at = ivec2(FRAGCOORD.xy);
	ivec2 lim = ivec2(size) - 1;
	mat4 ip = INV_PROJECTION_MATRIX;
	// --- depth: the pixel and its eight neighbours at the line's width, as positions in view space
	vec3 pc = view_at(depth_tex, at, lim, size, ip);
	vec3 pl = view_at(depth_tex, at - ivec2(r, 0), lim, size, ip);
	vec3 pr = view_at(depth_tex, at + ivec2(r, 0), lim, size, ip);
	vec3 pd = view_at(depth_tex, at - ivec2(0, r), lim, size, ip);
	vec3 pu = view_at(depth_tex, at + ivec2(0, r), lim, size, ip);
	float zc = -pc.z;
	float zl = -pl.z;
	float zr = -pr.z;
	float zd = -pd.z;
	float zu = -pu.z;
	// the diagonals catch creases that run along the axes' grain; a phone may go without them (lite)
	float ed = 0.0;
	if (!lite) {
		float z1 = -view_at(depth_tex, at + ivec2(r, r), lim, size, ip).z;
		float z2 = -view_at(depth_tex, at - ivec2(r, r), lim, size, ip).z;
		float z3 = -view_at(depth_tex, at + ivec2(r, -r), lim, size, ip).z;
		float z4 = -view_at(depth_tex, at + ivec2(-r, r), lim, size, ip).z;
		ed = max(abs(z1 + z2 - 2.0 * zc), abs(z3 + z4 - 2.0 * zc));
	}
	float dc = texelFetch(depth_tex, at, 0).r;
	// metres a pixel covers here (an orthographic camera: the same everywhere)
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	// (abs: the Compatibility renderer flips the projection upside down when it draws into a texture)
	float px_m = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * size.y) * (ortho ? 1.0 : max(zc, 0.05));
	// --- outlines from the depth: the second difference is nought on any flat surface however steep, large at a
	// step (a silhouette) and in between at a bend (a crease)
	float step_m = float(r) * px_m;
	float e = max(max(abs(zl + zr - 2.0 * zc), abs(zu + zd - 2.0 * zc)), ed);
	float bend = e / max(step_m, 1e-5);
	float edge = smoothstep(crease, crease + crease_soft, bend);
	// --- the picture and its brightness steps
	vec3 c = texelFetch(screen_tex, at, 0).rgb;
	float L = luma(c);
	if (color_edge > 0.0) {
		float lr = luma(texelFetch(screen_tex, clamp(at + ivec2(r, 0), ivec2(0), lim), 0).rgb);
		float lu = luma(texelFetch(screen_tex, clamp(at + ivec2(0, r), ivec2(0), lim), 0).rgb);
		float g;
		if (lite) {
			// two taps: the steps to the right and above (the line falls on one side of the step only)
			g = max(abs(lr - L), abs(lu - L)) * 1.4;
		} else {
			float ll = luma(texelFetch(screen_tex, clamp(at - ivec2(r, 0), ivec2(0), lim), 0).rgb);
			float ld = luma(texelFetch(screen_tex, clamp(at - ivec2(0, r), ivec2(0), lim), 0).rgb);
			g = max(abs(ll - lr), abs(lu - ld));
		}
		edge = max(edge, smoothstep(color_edge, color_edge * 1.6, g));
	}
	// --- the surface: its normal from the depth (the flatter side of each pair, so an edge does not bend it)
	vec3 ddx = (abs(zr - zc) < abs(zc - zl)) ? pr - pc : pc - pl;
	vec3 ddy = (abs(zu - zc) < abs(zc - zd)) ? pu - pc : pc - pd;
	vec3 n = normalize(cross(ddx, ddy));
	if (n.z < 0.0) n = -n;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 wp = (INV_VIEW_MATRIX * vec4(pc, 1.0)).xyz;
	// --- the tone, posterised
	float tone = pow(clamp(L * exposure, 0.0, 1.0), gamma_k);
	bool sky = dc >= 0.99999;
	// hatch coordinates on the surface: along the ground's diagonal, slanted on the walls (each way a wall faces its own)
	vec2 hc;
	vec2 cc;
	vec3 an = abs(nw);
	if (an.y > 0.6) {
		hc = vec2(dot(wp.xz, vec2(0.966, 0.259)), dot(wp.xz, vec2(-0.259, 0.966)));
		cc = vec2(dot(wp.xz, vec2(0.259, -0.966)), dot(wp.xz, vec2(0.966, 0.259)));
	} else if (an.x > an.z) {
		hc = vec2(dot(vec2(wp.z, wp.y), vec2(0.857, 0.515)), dot(vec2(wp.z, wp.y), vec2(-0.515, 0.857)));
		cc = vec2(dot(vec2(wp.z, wp.y), vec2(-0.857, 0.515)), dot(vec2(wp.z, wp.y), vec2(0.515, 0.857)));
	} else {
		hc = vec2(dot(vec2(wp.x, wp.y), vec2(-0.857, 0.515)), dot(vec2(wp.x, wp.y), vec2(0.515, 0.857)));
		cc = vec2(dot(vec2(wp.x, wp.y), vec2(0.857, 0.515)), dot(vec2(wp.x, wp.y), vec2(-0.515, 0.857)));
	}
	float want = px_m * hatch_px * res;
	float lv = log2(max(want, 1e-4));
	float s0 = exp2(floor(lv));
	float t = lv - floor(lv);
	float k = soft;
	// how dark: 0 paper .. 1 black, in four steps with soft shoulders
	float w_black = 1.0 - smoothstep(levels.x - k, levels.x + k, tone);
	float w_cross = 1.0 - smoothstep(levels.y - k, levels.y + k, tone);
	float w_hatch = 1.0 - smoothstep(levels.z - k, levels.z + k, tone);
	float w_fine = 1.0 - smoothstep(levels.w - k, levels.w + k, tone);
	// lines thicken as the tone darkens within its band
	float dark = 1.0 - tone;
	float h1 = hatch(hc.x, hc.y, s0, t, mix(0.10, 0.24, w_hatch));
	float h2 = hatch(cc.x, cc.y, s0 * 1.0, t, mix(0.09, 0.20, w_cross));
	float hf = hatch(hc.x, hc.y, s0 * 2.0, t, 0.07);
	float ink = max(w_black, max(h1 * w_hatch, max(h2 * w_cross, hf * w_fine * (1.0 - w_hatch))));
	if (far_fade > 0.0 && !ortho) ink *= 1.0 - far_fade * smoothstep(40.0, 120.0, zc);
	// light: lamps, lit windows, the snow at its brightest stay bare paper
	float lit = smoothstep(light - 0.03, light + 0.03, L * exposure);
	ink *= 1.0 - lit;
	edge *= 1.0 - 0.75 * lit;
	if (sky) {
		ink = sky_ink;
		edge = 0.0;
	}
	float g = 1.0 - max(ink, edge);
	if (debug_view == 1) g = 1.0 - edge;
	if (debug_view == 3) g = 1.0 - (w_black * 0.25 + w_cross * 0.25 + w_hatch * 0.25 + w_fine * 0.25);
	if (debug_view == 4) g = 1.0 - ink;
	ALBEDO = debug_view == 2 ? nw * 0.5 + 0.5 : (debug_view == 5 ? c : vec3(g));
	ALPHA = 1.0;
}
