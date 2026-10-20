shader_type spatial;
// The trailer's foreground snow (hc2_director.gd, dev tool): big flakes falling a metre or a few from the lens, out of
// focus, drawn as the soft discs a lens makes of them (each the size of its circle of confusion, fainter the bigger),
// warm where a lamp is near them, cold blue in the dark. A MultiMesh of quads, each instance one flake whose origin is
// a random point in a unit cube; the cube is laid over a box round the lens and wrapped, so the box follows the lens
// while the flakes stay where they are in the world (they slide past as the lens moves). Drawn after the depth of
// field (they are their own blur).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec3 box_center = vec3(0.0);
uniform vec3 box_size = vec3(5.0, 4.0, 5.0);
uniform float fall = 0.55;
uniform vec3 wind = vec3(0.12, 0.0, 0.05);
uniform float clock = 0.0;
uniform float focus = 6.0;
uniform float blur_px = 8.0;
uniform float size_m = 0.012;
uniform float max_px = 90.0;
uniform float strength = 0.5;
uniform vec3 cold : source_color = vec3(0.55, 0.62, 0.8);
uniform vec4 lamps[12];
uniform vec4 lamp_colors[12];
uniform int lamp_count = 0;
uniform vec2 screen = vec2(1920.0, 1080.0);

varying vec2 quad;
varying float alpha;
varying vec3 tone;

float h1(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float r1 = h1(seed.x * 13.7 + seed.y * 71.1 + seed.z * 3.3);
	float r2 = h1(seed.y * 29.1 + seed.z * 5.7);
	float r3 = h1(seed.z * 41.9 + seed.x * 17.3);
	float t = clock;
	float spd = 0.7 + 0.6 * r1;
	vec3 wob = vec3(sin(t * (0.5 + 0.6 * r2) + r3 * 6.28), 0.0, cos(t * (0.4 + 0.5 * r3) + r1 * 6.28)) * 0.25;
	vec3 p = seed * box_size + (wind * t + vec3(0.0, -fall * t, 0.0)) * spd + wob;
	vec3 lo = box_center - box_size * 0.5;
	p = lo + mod(p - lo, box_size);
	vec3 f = (p - lo) / box_size;
	float edge = smoothstep(0.0, 0.12, min(f.x, 1.0 - f.x)) * smoothstep(0.0, 0.12, min(f.z, 1.0 - f.z))
			* smoothstep(0.0, 0.12, min(f.y, 1.0 - f.y));
	vec4 vpos = VIEW_MATRIX * vec4(p, 1.0);
	float z = -vpos.z;
	vec4 c = PROJECTION_MATRIX * vpos;
	float w = max(c.w, 0.001);
	// the flake's own size on screen, and its blur (the depth of field's circle of confusion, hc2_dof.gdshader)
	vec4 cu = PROJECTION_MATRIX * (vpos + vec4(0.0, size_m * (0.6 + 0.8 * r3), 0.0, 0.0));
	float px = abs(cu.y / max(cu.w, 0.001) - c.y / w) * 0.5 * screen.y;
	float k = abs(1.0 / focus - 1.0 / max(z, 0.05)) * focus * 2.0;
	float blur = min(k * blur_px * screen.y / 1080.0, max_px * screen.y / 1080.0);
	float d = sqrt(px * px + blur * blur) + 1.0;
	// a disc of light: the flake's light spread over the disc (fainter the bigger), never quite gone
	alpha = strength * edge * clamp(px * px * 2.5 / (d * d) + 0.06, 0.0, 1.0) * smoothstep(0.25, 0.6, z);
	vec2 off = VERTEX.xy * d * 2.0;
	POSITION = c + vec4(off * 2.0 / screen * w, 0.0, 0.0);
	if (c.w <= 0.05) POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	quad = VERTEX.xy * 2.0;
	vec3 lit = cold;
	for (int i = 0; i < 12; i++) {
		if (i >= lamp_count) break;
		vec3 dv = p - lamps[i].xyz;
		float kk = clamp(1.0 - length(dv) / lamps[i].w, 0.0, 1.0);
		lit += lamp_colors[i].rgb * (kk * kk * (1.0 + 2.5 * kk * kk));
	}
	tone = lit;
}

void fragment() {
	float r = length(quad);
	// a lens's disc: nearly flat, a little brighter at its rim, a soft edge
	float disc = 1.0 - smoothstep(0.82, 1.0, r);
	float rim = 1.0 + 0.25 * smoothstep(0.55, 0.9, r);
	ALBEDO = tone * disc * rim * alpha;
	ALPHA = 1.0;
}
