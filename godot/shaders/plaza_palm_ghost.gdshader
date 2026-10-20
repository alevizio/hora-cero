shader_type spatial;
// A palm's crown thinning out over somebody under it (plaza_kit_props.gd sync_palms): the crown drawn again, see-through,
// in its own colours, while the solid one (plaza_detail / plaza_walls, the instance's INSTANCE_CUSTOM.r at 0) is
// away. One instance a crown; INSTANCE_CUSTOM.g how much of it shows. Above `fade_above` metres of the palm only (its
// trunk stays solid); the fronds sway as the solid ones do. The fronds from the atlas (UV2.x 4, its leaf use), the
// boot of frond bases and the snow cap in its heart a dark olive.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float fade_above = 6.0;
uniform float sway = 0.0;

varying flat float mode;
varying float keep;
varying float alpha;

void vertex() {
	mode = UV2.x;
	keep = VERTEX.y > fade_above ? 1.0 : 0.0;
	alpha = INSTANCE_CUSTOM.g;
	if (sway > 0.0 && int(UV2.x + 0.5) == 4) {
		float r = length(VERTEX.xz);
		float ph = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.21)) + r * 0.35;
		float gust = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.1 + ph * 1.7) * 0.4;
		float amp = sway * 0.022 * r * r;
		vec3 wind = transpose(mat3(MODEL_MATRIX)) * vec3(1.0, 0.0, 0.35);
		VERTEX += normalize(wind) * gust * amp + vec3(0.0, sin(TIME * 1.7 + ph * 2.3) * amp * 0.35, 0.0);
	}
}

void fragment() {
	if (keep < 0.5 || alpha < 0.01) discard;
	vec3 col = vec3(0.1, 0.1, 0.07);
	if (int(mode + 0.5) == 4) {
		vec4 t = texture(atlas, UV);
		if (t.a < 0.3) discard;
		vec3 leaf = t.rgb * COLOR.rgb;
		float luma = dot(leaf, vec3(0.3, 0.55, 0.15));
		col = max(mix(vec3(luma), leaf, 1.35), vec3(0.0)) * 0.82;
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.22;
	ALPHA = alpha;
}
