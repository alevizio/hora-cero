shader_type spatial;
// Footprints and ski tracks pressed into the snow: one MultiMesh instance per print in the rules (simulation tracks),
// a flat quad on the ground mapped to one cell of prints.png (INSTANCE_CUSTOM.x: 0 boots, 1 skis). The instance
// colour's alpha fades the print as new snow fills it.
render_mode cull_back, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D prints_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 snow_shadow : source_color = vec3(0.50, 0.58, 0.74);

void vertex() {
	UV = vec2(INSTANCE_CUSTOM.x * 0.5 + UV.x * 0.5, UV.y);
}

void fragment() {
	vec4 t = texture(prints_tex, UV);
	ALBEDO = snow_shadow * t.rgb * 1.3;
	ALPHA = t.a * COLOR.a;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
