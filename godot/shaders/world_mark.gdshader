shader_type spatial;
// Ground markers and short-lived event effects drawn on one pooled quad each (see world.gd).
// The quad spans UV -1..1; `size_m` is its half-size in metres so that line weights stay constant.
//   shape 0 RING     p.x radius (share of half-size), p.y dash count (0 = solid), p.z inner fill alpha, p.w centre dot radius (m)
//   shape 1 BRACKET  p.x half-size of the square (share), p.y arm length (share of its side), p.z fill alpha
//   shape 2 RETICLE  p.x ring radius (share), p.y tick length (share), p.z centre dot radius (m)
//   shape 3 WAVES    p.x progress 0..1 (wave fronts run out to the rim), p.y number of fronts, p.z rim dash count
//   shape 4 PUFF     p.x progress 0..1: a soft disc that grows and thins out
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int shape = 0;
uniform vec4 p = vec4(0.9, 0.0, 0.0, 0.0);
uniform vec4 color : source_color = vec4(1.0);
uniform float size_m = 1.0;
uniform float line_m = 0.05;
uniform float spin = 0.0;

varying vec2 q;

void vertex() {
	q = UV * 2.0 - 1.0;
}

float stroke(float dist, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, dist);
}

void fragment() {
	vec2 m = q * size_m;                         // metres from the centre
	float r = length(m);
	float aa = max(fwidth(r), 0.0005);
	float hw = max(line_m * 0.5, aa * 0.75);
	float ang = atan(m.y, m.x) + spin;
	float a = 0.0;
	if (shape == 0) {
		float rad = p.x * size_m;
		float ring = stroke(abs(r - rad), hw, aa);
		if (p.y > 0.5) {
			float cell = abs(fract(ang / 6.2831853 * p.y) - 0.5);
			ring *= 1.0 - smoothstep(0.30, 0.30 + aa / max(rad, 0.01) * p.y * 0.16, cell);
		}
		a = max(ring, p.z * (1.0 - smoothstep(rad - aa, rad + aa, r)));
		a = max(a, stroke(r, p.w, aa) * step(0.0005, p.w));
	} else if (shape == 1) {
		float c = cos(spin);
		float s = sin(spin);
		vec2 v = abs(vec2(m.x * c - m.y * s, m.x * s + m.y * c));
		float half_size = p.x * size_m;
		float box = max(v.x, v.y);
		float edge = stroke(abs(box - half_size), hw, aa);
		float arm = half_size * (1.0 - p.y * 2.0);
		a = edge * step(arm, min(v.x, v.y));
		a = max(a, p.z * (1.0 - smoothstep(half_size - aa, half_size + aa, box)));
	} else if (shape == 2) {
		float rad = p.x * size_m;
		a = stroke(abs(r - rad), hw, aa);
		float c = cos(spin);
		float s = sin(spin);
		vec2 v = abs(vec2(m.x * c - m.y * s, m.x * s + m.y * c));
		float tick = stroke(min(v.x, v.y), hw, aa) * step(rad - p.y * size_m * 0.5, r) * step(r, rad + p.y * size_m);
		a = max(a, tick);
		a = max(a, stroke(r, p.z, aa) * step(0.0005, p.z));
	} else if (shape == 3) {
		float t = clamp(p.x, 0.0, 1.0);
		float count = max(p.y, 1.0);
		for (float i = 0.0; i < 3.0; i += 1.0) {
			if (i >= count) break;
			float front = (t - i * 0.16) * size_m * 0.98;
			float alive = step(0.0, front) * (1.0 - smoothstep(0.55, 1.0, (t - i * 0.16)));
			a = max(a, stroke(abs(r - front), hw * (1.6 - 0.35 * i), aa) * alive * (1.0 - 0.25 * i));
			// faint wash behind the first front
			if (i < 0.5) a = max(a, 0.10 * alive * (1.0 - smoothstep(front - aa, front + aa, r)) * smoothstep(front - 1.6, front, r));
		}
		float rim = stroke(abs(r - size_m * 0.98), hw * 0.7, aa) * (1.0 - smoothstep(0.7, 1.0, t)) * 0.55;
		if (p.z > 0.5) rim *= step(abs(fract(ang / 6.2831853 * p.z) - 0.5), 0.27);
		a = max(a, rim);
	} else {
		float t = clamp(p.x, 0.0, 1.0);
		float rad = size_m * (0.35 + 0.65 * sqrt(t));
		a = (1.0 - smoothstep(rad * 0.25, rad, r)) * (1.0 - t) * (1.0 - t);
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
