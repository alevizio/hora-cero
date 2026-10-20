shader_type spatial;
// The Plaza de Mayo's falling snow (plaza_ground.gd): a MultiMesh of quads, each instance one flake, its origin a
// random point in a unit cube. The vertex shader lays the cube over a box `box_size` metres round `box_center`, moves
// every flake down and with the wind (TIME for the steady fall, `drift` for what the rules' waves add, summed on the
// CPU so a change of speed never makes the flakes jump), wraps it back into the box (so the box can follow the
// camera), and draws it facing the camera at the size it has on screen, never less than `min_px` pixels (a flake
// too small to see is drawn at that size and fainter, so the snow reads at every zoom of the orthographic game
// camera), stretched along its motion over `streak` seconds (a heavy wave falls in short streaks). Each flake takes
// the light of the lamps near it (up to 12, nearest the view: `lamps`, `lamp_colors`), warm and bright under a lamp,
// pale blue in the dark. In comic ink they are printed as white dots ringed in ink.
// Compatibility renderer: no particles, no compute; one draw per layer.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec3 box_center = vec3(140.0, 15.0, 80.0);
uniform vec3 box_size = vec3(100.0, 30.0, 100.0);
// metres of fall and wind added on top of the steady fall (CPU, accumulated)
uniform vec3 drift = vec3(0.0);
// the steady part of the fall (metres a second, with TIME), the wind and the fall of the moment (for the streaks)
uniform float base_fall = 0.9;
uniform vec3 velocity = vec3(0.4, -1.2, 0.15);
uniform float flutter = 0.35;
// a flake's diameter in metres, the least and most pixels it is drawn at, the seconds of motion it is smeared over
uniform float size_m = 0.05;
uniform float min_px = 1.6;
uniform float max_px = 18.0;
uniform float streak = 0.03;
uniform float strength = 0.8;
// fade the flakes nearer the camera than near_fade.x (gone) .. near_fade.y (whole), metres
uniform vec2 near_fade = vec2(0.0, 0.0);
uniform vec3 flake_color : source_color = vec3(0.8, 0.84, 0.95);
uniform vec4 lamps[12];
uniform vec4 lamp_colors[12];
uniform int lamp_count = 0;
uniform float ink = 0.0;
// the viewport in pixels (set by the CPU: VIEWPORT_SIZE is not to be had in a vertex shader on every renderer)
uniform vec2 screen = vec2(1280.0, 720.0);
// the colour grade's tilt-shift (post_grade.gdshader): above and below its sharp band it blurs with eight taps on a
// ring, which would print a small bright flake as a ring of dots; a flake there is drawn softened to that width first
uniform float tilt_band = 0.16;
uniform float tilt_radius = 0.0;

varying vec2 quad;
varying float stretch;
varying float alpha;
varying vec3 tone;
varying float px_size;

float h1(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float r1 = h1(seed.x * 13.7 + seed.y * 71.1 + seed.z * 3.3);
	float r2 = h1(seed.y * 29.1 + seed.z * 5.7);
	float r3 = h1(seed.z * 41.9 + seed.x * 17.3);
	float spd = 0.72 + 0.56 * r1;
	float t = TIME;
	vec3 wob = vec3(sin(t * (0.6 + 0.7 * r2) + r3 * 6.2832), 0.0, cos(t * (0.5 + 0.6 * r3) + r1 * 6.2832)) * flutter * (0.5 + r2);
	vec3 p = seed * box_size + drift * spd + vec3(0.0, -base_fall * t * spd, 0.0) + wob;
	vec3 lo = box_center - box_size * 0.5;
	p = lo + mod(p - lo, box_size);
	// thin out toward the box's walls, its top and the ground, so the wrap is never seen
	vec3 f = (p - lo) / box_size;
	float edge = smoothstep(0.0, 0.08, min(f.x, 1.0 - f.x)) * smoothstep(0.0, 0.08, min(f.z, 1.0 - f.z));
	float vert = smoothstep(0.0, 0.03, f.y) * (1.0 - smoothstep(0.82, 1.0, f.y));
	vec4 vpos = VIEW_MATRIX * vec4(p, 1.0);
	vec4 c = PROJECTION_MATRIX * vpos;
	vec3 vel = velocity * spd;
	vec4 c2 = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p - vel * streak, 1.0));
	vec2 vp = max(screen, vec2(1.0));
	float w = max(c.w, 0.001);
	// its size on screen, from a point its diameter above it (in view space) projected too
	vec4 cu = PROJECTION_MATRIX * (vpos + vec4(0.0, size_m * (0.55 + 0.9 * r3), 0.0, 0.0));
	float px = abs(cu.y / max(cu.w, 0.001) - c.y / w) * 0.5 * vp.y;
	float lo_px = min_px * vp.y / 720.0;
	float pxd = clamp(px, lo_px, max_px * vp.y / 720.0);
	// a flake drawn bigger than it is shows fainter (but never so faint that the snow stops reading)
	float energy = clamp(px / pxd, 0.0, 1.0);
	float sy = 1.0 - (c.y / w * 0.5 + 0.5);
	float blur = smoothstep(tilt_band, 0.5, abs(sy - 0.54)) * tilt_radius * vp.y / 720.0;
	float soft_px = sqrt(pxd * pxd + 4.0 * blur * blur);
	energy *= mix(1.0, pxd * pxd / (soft_px * soft_px), 0.8);
	pxd = soft_px;
	float big = clamp(px / pxd, 1.0, 4.0);
	vec2 d = (c.xy / w - c2.xy / max(c2.w, 0.001)) * 0.5 * vp;
	float run = length(d);
	vec2 axis = run > 0.01 ? d / run : vec2(0.0, 1.0);
	vec2 across = vec2(-axis.y, axis.x);
	float len = pxd + run;
	stretch = len / pxd;
	px_size = pxd;
	vec2 off = axis * VERTEX.y * len + across * VERTEX.x * pxd - d * 0.5;
	POSITION = c + vec4(off * 2.0 / vp * w, 0.0, 0.0);
	if (c.w <= 0.0) POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	quad = VERTEX.xy * 2.0;
	float near = near_fade.y > 0.0 ? smoothstep(near_fade.x, near_fade.y, c.w) : 1.0;
	alpha = strength * edge * vert * near * mix(energy, 1.0, 0.55) * mix(1.0, 1.0 / stretch, 0.6) / mix(1.0, big, 0.5);
	// the lamps' light caught by the flake
	vec3 lit = flake_color;
	for (int i = 0; i < 12; i++) {
		if (i >= lamp_count) break;
		vec3 dv = p - lamps[i].xyz;
		float k = clamp(1.0 - length(dv) / lamps[i].w, 0.0, 1.0);
		lit += lamp_colors[i].rgb * (k * k * (1.0 + 2.5 * k * k));
	}
	tone = lit;
}

void fragment() {
	// a round flake, or a short capsule along its fall
	float along = abs(quad.y) * stretch;
	float dy = max(along - (stretch - 1.0), 0.0);
	float r = sqrt(quad.x * quad.x + dy * dy);
	// (a flake of a few pixels is drawn nearly flat, or its soft edge would leave nothing of it)
	float edge0 = mix(0.72, 0.25, smoothstep(3.0, 10.0, px_size));
	if (ink > 0.5) {
		// comic snow: a white dot with a ring of ink round it
		float dot_a = 1.0 - smoothstep(0.82, 1.0, r);
		float rim = smoothstep(0.42, 0.62, r);
		ALBEDO = mix(vec3(1.0), vec3(0.08, 0.07, 0.07), rim);
		ALPHA = dot_a * clamp(alpha * 1.6, 0.0, 1.0);
	} else {
		ALBEDO = tone;
		ALPHA = (1.0 - smoothstep(edge0, 1.0, r)) * alpha;
	}
}
