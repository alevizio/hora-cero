shader_type spatial;
// First half of the x-ray (xray.gdshader is the second, chained as its next pass): every figure's body drawn once
// more, invisibly, after the whole world, marking in the stencil buffer the pixels where a figure is what the
// camera sees. The x-ray never draws on those, so a man never shows through his own arm, his pack or a comrade
// standing in front of him, only through the world: a wall, a wagon, a ship. Drawn early among the blended passes
// (operative.gd sets its render priority below every x-ray), with the depth test on: a body hidden behind a wall
// marks nothing there. Both sides, so the back of a hair card or a cap brim marks too.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, blend_mix, fog_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
