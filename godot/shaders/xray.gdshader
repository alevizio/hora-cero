shader_type spatial;
// A figure seen through whatever stands between him and the camera (a building, a crane, a ship): an overlay
// pass on the character's body (operative.gd) that draws only where something solid hides him, at least
// `clear_m` in front of him, in a flat tint with a brighter rim. world.gd sets the tint each frame: a guard in
// his sight-cone colour, an operative in his own; alpha 0 hides it (a guard who is down, the launch screen).
// Never where a figure is what the camera sees (the stencil mark of xray_mark.gdshader, the pass before this one):
// a crouching man's head hides his boots, an arm crosses his chest, a comrade stands in front of him, and none of
// that is a wall to see him through.
// The game runs on the Compatibility renderer: depth comes back in [0, 1] and is mapped to OpenGL's [-1, 1].
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled, blend_mix, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float clear_m = 0.35;    // nearer than this (a kerb, the ground at his boots) does not count as hiding him
uniform float fade_m = 0.30;     // and he comes through gradually over the next stretch, no hard edge
instance uniform vec4 xray_tint = vec4(0.0);

void fragment() {
	if (xray_tint.a <= 0.001) discard;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, d) * 2.0 - 1.0, 1.0);
	float scene = -v.z / v.w;
	float gap = -VERTEX.z - scene;
	if (gap < clear_m) discard;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(xray_tint.rgb, vec3(1.0), rim * rim * 0.35);
	ALPHA = xray_tint.a * (0.42 + 0.58 * rim * rim) * smoothstep(clear_m, clear_m + fade_m, gap);
}
