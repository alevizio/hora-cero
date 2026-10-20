shader_type spatial;
// Muzzle flash: a ragged star with a hot core on a camera-facing quad, added to the scene
// for a few hundredths of a second (operative.gd places, sizes and rolls the quad).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float gain : hint_range(0.0, 4.0) = 1.6;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// uneven tongues of flame: a few long, a few short
	float tongues = pow(abs(cos(a * 2.0)), 6.0) * 0.55 + pow(abs(cos(a * 3.0 + 1.1)), 10.0) * 0.38;
	float edge = 0.30 + 0.66 * tongues;
	float flame = smoothstep(edge, edge * 0.25, r);
	float core = exp(-r * r * 16.0);
	vec3 tint = mix(vec3(1.0, 0.50, 0.12), vec3(1.0, 0.93, 0.70), clamp(core * 1.4 + flame * 0.35, 0.0, 1.0));
	float amount = clamp(flame * 0.8 + core, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint * amount * gain;
	ALPHA = amount;
}
