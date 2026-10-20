shader_type spatial;
// A paper cut-out figure (scripts/three_d/cutout.gd): a flat drawing on a card that stands in the world and turns to
// face the camera, cut out round its edge with a thick ink outline and a thin rim of white paper beyond it. Solid
// (alpha scissor), so it hides what is behind it, casts its depth for comic ink's outlines and takes the scene's
// light like any figure: the moon, the lamps, the shadow of a wall. A little fill from the front keeps the drawing
// readable at night.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/cutout.gdshaderinc"

uniform vec3 ink_color : source_color = vec3(0.055, 0.05, 0.048);
uniform vec3 paper_color : source_color = vec3(0.93, 0.91, 0.85);
uniform float fill = 0.42;              // light of its own, a share of its colour
uniform float lean_to_sky = 0.55;       // how far the normal leans up, to catch the sky and the moon from above
instance uniform vec4 tint = vec4(1.0); // dulled in cover; a stand-in's grey

void fragment() {
	vec2 uv = card_uv(UV);
	vec3 s = silhouette(uv);
	vec4 t = art_at(uv);
	vec3 col = mix(paper_color, ink_color, smoothstep(0.4, 0.6, s.y));
	col = mix(col, t.rgb, smoothstep(0.4, 0.6, s.x));
	col *= tint.rgb;
	ALBEDO = col;
	EMISSION = col * fill;
	ROUGHNESS = 1.0;
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, lean_to_sky));
	ALPHA = s.z;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
