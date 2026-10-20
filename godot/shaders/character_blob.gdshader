shader_type spatial;
// Soft contact shadow under a character: radial falloff on a ground quad.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float a = 1.0 - d;
	ALBEDO = vec3(0.015, 0.02, 0.018);
	ALPHA = a * a * (3.0 - 2.0 * a) * strength;
}
