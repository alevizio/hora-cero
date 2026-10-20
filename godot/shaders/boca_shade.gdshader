shader_type spatial;
// The dark that falls on the quay when its lamps die: laid on the ground over the ground the lamps lit (the rules'
// powered light), a cold blue veil over the snow, soft at its edges (vertex alpha: 1 inside, 0 at the outer border).
// "amount" 0 (lamps lit): nothing (the node is hidden); 1: the lamps are out.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 shade : source_color = vec3(0.07, 0.08, 0.16);
uniform float strength = 0.56;
uniform float amount = 0.0;

void fragment() {
	float m = COLOR.a;
	m = m * m * (3.0 - 2.0 * m);
	ALBEDO = shade;
	ALPHA = m * amount * strength;
}
