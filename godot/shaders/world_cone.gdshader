shader_type spatial;
// Sight cone of one guard, drawn flat on the ground (see world.gd).
// The mesh is a fixed fan; the vertex stage places it from `lengths` (where each sight ray stops, in metres) so the
// script only uploads 41 floats when a guard moves. The fragment stage draws the two zones:
//   near zone  - solid tint: "seen here in any stance"
//   far zone   - concentric bands: "seen only standing, safe if crouched"; the bands stand still on a calm cone
//                and flow outward on a wary or alarmed one, so the guard's state does not hang on colour alone
// with a crisp arc between them, a rim at the limit of vision and hairline sides. A wave of the warning colour
// grows from the guard with his suspicion.
// Each cone is drawn twice, the near zone (`zone` 0) on a higher layer and before the far zones (`zone` 1), and
// both write depth: where cones overlap only the uppermost zone is blended, near zones first. Eleven cones on
// one yard therefore read as one map of what is watched instead of adding up to soup.
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled, fog_disabled;

const int RAYS = 40;
uniform float lengths[41];
uniform int zone = 0;
uniform float fov = 1.15;               // radians
uniform float near_m = 3.0;
uniform float range_m = 5.9;
uniform vec3 tint : source_color = vec3(0.7, 0.9, 0.4);
uniform vec3 warn : source_color = vec3(1.0, 0.7, 0.15);
uniform float suspicion = 0.0;          // 0..1, radius of the warning wave as a share of the range
uniform float strength = 1.0;           // whole cone
uniform float far_strength = 1.0;       // far zone only (guards away from the camera focus are drawn lighter)
uniform float pulse = 0.0;              // 0..1 extra glow of the near zone (alarm)
uniform float drift = 0.0;              // metres the far bands have run outward (they flow on wary and alarmed cones)
// Bush rectangles in world X/Z (min.x, min.z, max.x, max.z): a croucher inside is hidden beyond `reveal_m`.
uniform vec4 bushes[8];
uniform float reveal_m = 2.25;
// Water in world X/Z (the river, the basin): nobody stands there, so no cone is drawn over it. A sentry looking out
// across the water, or a lookout on a ship's deck, shows his cone from the quay edge on.
uniform vec4 water[4];

varying vec2 local;
varying float edge_t;
varying vec2 world_xz;

void vertex() {
	float a = (UV.x / float(RAYS) - 0.5) * fov;
	float len = lengths[int(UV.x + 0.5)] * UV.y;
	VERTEX = vec3(cos(a) * len, 0.0, sin(a) * len);
	local = VERTEX.xz;
	edge_t = UV.y;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float stroke(float dist, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, dist);
}

void fragment() {
	float d = length(local);
	float aa = max(fwidth(d), 0.0005);
	float edge = d / max(edge_t, 0.001);                    // where this ray stops
	float side = (0.5 * fov - abs(atan(local.y, local.x))) * d;   // metres to the nearer side
	for (int i = 0; i < 4; i++) {
		vec4 w = water[i];
		if (world_xz.x > w.x && world_xz.x < w.z && world_xz.y > w.y && world_xz.y < w.w) discard;
	}
	float in_bush = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 b = bushes[i];
		in_bush = max(in_bush, step(b.x, world_xz.x) * step(world_xz.x, b.z) * step(b.y, world_xz.y) * step(world_xz.y, b.w));
	}
	float near_edge = mix(near_m, min(near_m, reveal_m), in_bush);
	if (zone == 0 && d > near_edge + 0.05 + aa) discard;
	if (zone == 1 && d < near_edge - 0.06 - aa) discard;
	float in_near = 1.0 - smoothstep(near_edge - aa, near_edge + aa, d);
	// far zone: bands 0.20 m wide every 0.52 m, anchored on the zone boundary so the first gap follows the arc
	float period = 0.52;
	float band = abs(fract((d - near_m - drift) / period - 0.5) - 0.5) * period;
	float stripes = stroke(band, 0.105, aa) * (1.0 - smoothstep(0.35, 0.6, aa / period));
	float far_fill = (0.10 + 0.40 * stripes + 0.16 * smoothstep(0.35, 0.6, aa / period)) * far_strength;
	float near_fill = 0.52 + 0.10 * pulse;
	float alpha = mix(far_fill, near_fill, in_near);
	// lines: zone boundary, rim at the limit (thinner where a wall cuts the view), sides
	float reach = step(range_m - 0.06, edge);
	float arc = stroke(abs(d - near_edge), max(0.05, aa * 1.1), aa) * step(d, edge - 0.02);
	float rim = stroke(edge - d, max(mix(0.035, 0.09, reach), aa * 1.6), aa);
	float sides = stroke(side, max(0.026, aa * 0.8), aa) * smoothstep(0.25, 0.6, d);
	alpha = max(alpha, max(arc * 0.95, max(rim * mix(0.55, 0.9, reach), sides * 0.6)));
	// suspicion: the warning colour floods outward from the guard
	float front = suspicion * range_m;
	float in_wave = (1.0 - smoothstep(front - aa, front + aa, d)) * step(0.004, suspicion);
	float crest = stroke(abs(d - front), max(0.045, aa), aa) * step(0.004, suspicion) * step(suspicion, 0.995);
	vec3 col = mix(tint, warn, in_wave);
	alpha = max(alpha + in_wave * 0.13, crest * 0.9);
	col = mix(col, vec3(1.0), max(arc, rim * reach) * 0.22 + crest * 0.35);
	// soften the hub so the fan does not end in a hard spike under the guard's feet
	alpha *= smoothstep(0.08, 0.45, d);
	alpha = clamp(alpha * strength, 0.0, 1.0);
	if (alpha < 0.012) discard;
	ALBEDO = col;
	ALPHA = alpha;
}
