shader_type spatial;
// The Transbordador's riveted lattice: a cut-out card seen from both sides, the panels repeating along its length,
// the iron lifted to the bridge's grey (the texture is drawn dark), snow caught on the members that face up a
// little. Dithered away ("fade" < 1) when somebody stands behind it.
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tint = 2.2;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = y * 4 + x;
	float m = 0.0;
	if (i == 0) m = 0.0; else if (i == 1) m = 8.0; else if (i == 2) m = 2.0; else if (i == 3) m = 10.0;
	else if (i == 4) m = 12.0; else if (i == 5) m = 4.0; else if (i == 6) m = 14.0; else if (i == 7) m = 6.0;
	else if (i == 8) m = 3.0; else if (i == 9) m = 11.0; else if (i == 10) m = 1.0; else if (i == 11) m = 9.0;
	else if (i == 12) m = 15.0; else if (i == 13) m = 7.0; else if (i == 14) m = 13.0; else m = 5.0;
	return (m + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) discard;
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) discard;
	vec3 iron = t.rgb * COLOR.rgb * tint;
	// a line of snow along the top of every member: where the texel above (world up, mapped into the card's UV) is open
	vec2 up_uv = dFdx(UV) * dFdx(wpos).y + dFdy(UV) * dFdy(wpos).y;
	up_uv = up_uv / max(length(up_uv), 1e-6);
	float above = texture(atlas, UV + up_uv * 0.014).a;
	float snow = (1.0 - above) * 0.85;
	ALBEDO = mix(iron, snow_color, snow);
	ROUGHNESS = mix(0.6, 0.8, snow);
	SPECULAR = 0.4;
}
