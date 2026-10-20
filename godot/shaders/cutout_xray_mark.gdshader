shader_type spatial;
// First half of a paper cut-out's x-ray (cutout_xray.gdshader is the second, chained as its next pass): the card's
// outline marked in the stencil where the camera sees it, as xray_mark.gdshader does for the modelled figures.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, blend_mix, fog_disabled;
stencil_mode write, compare_always, 1;

#include "res://shaders/cutout.gdshaderinc"

void fragment() {
	if (silhouette(card_uv(UV)).y < 0.5) discard;
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
