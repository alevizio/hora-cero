shader_type spatial;
// A paper cut-out seen through whatever stands between it and the camera: the card's second overlay pass, like
// xray.gdshader for the modelled figures (the same tint, set each frame by world.gd; the same stencil mark of where a
// figure is what the camera sees, from cutout_xray_mark.gdshader, so a card never shows through itself), in the card's
// own outline.
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_disabled, shadows_disabled, blend_mix, fog_disabled;
stencil_mode read, compare_not_equal, 1;

#include "res://shaders/cutout.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float clear_m = 0.35;
uniform float fade_m = 0.30;
instance uniform vec4 xray_tint = vec4(0.0);

void fragment() {
	if (xray_tint.a <= 0.001) discard;
	vec3 s = silhouette(card_uv(UV));
	if (s.y < 0.5) discard;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, d) * 2.0 - 1.0, 1.0);
	float scene = -v.z / v.w;
	float gap = -VERTEX.z - scene;
	if (gap < clear_m) discard;
	// the drawing's inside a flat tint, its outline brighter
	float edge = 1.0 - smoothstep(0.4, 0.6, s.x);
	ALBEDO = mix(xray_tint.rgb, vec3(1.0), edge * 0.35);
	ALPHA = xray_tint.a * (0.5 + 0.4 * edge) * smoothstep(clear_m, clear_m + fade_m, gap);
}
