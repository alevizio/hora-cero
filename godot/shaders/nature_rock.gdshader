shader_type spatial;
// Shore rocks and loose stones: world-space triplanar rock, wet tide band, algae line, baked vertex AO.
// Vertex COLOR.r = AO, COLOR.g = per-rock tone, COLOR.b = moss amount, COLOR.a = sits in the tide zone.
render_mode cull_back;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.42;
uniform float water_level = -0.19;
uniform float gain = 0.80;              // linear albedo gain (exposure trim for this material)
uniform vec4 map_rect = vec4(5.0, 0.0, 40.0, 25.0);
uniform vec3 haze_color : source_color = vec3(0.16, 0.20, 0.20);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 q = wpos * tex_scale;
	vec3 cx = texture(rock_tex, q.zy).rgb;
	vec3 cy = texture(rock_tex, q.xz).rgb;
	vec3 cz = texture(rock_tex, q.xy).rgb;
	vec2 nx = texture(rock_nrm, q.zy).rg * 2.0 - 1.0;
	vec2 ny = texture(rock_nrm, q.xz).rg * 2.0 - 1.0;
	vec2 nz = texture(rock_nrm, q.xy).rg * 2.0 - 1.0;
	vec3 col = cx * w.x + cy * w.y + cz * w.z;
	// whiteout-style triplanar normal blend
	vec3 tx = vec3(0.0, nx.y, nx.x);
	vec3 ty = vec3(ny.x, 0.0, -ny.y);
	vec3 tz = vec3(nz.x, nz.y, 0.0);
	vec3 bumped = normalize(n + (tx * w.x + ty * w.y + tz * w.z) * 0.9);

	col *= mix(0.86, 1.10, COLOR.g);
	// moss and lichen creep over sheltered tops
	float top = smoothstep(0.35, 0.85, n.y) * COLOR.b * smoothstep(0.38, 0.62, cy.g + cz.r * 0.3);
	col = mix(col, vec3(0.13, 0.16, 0.075), top * 0.55);
	// tide zone: dark and wet below, a green-brown algae line just above the water
	float h = wpos.y - water_level;
	float wet = (1.0 - smoothstep(0.02, 0.26, h + (cy.r - 0.4) * 0.25)) * COLOR.a;
	float algae = (1.0 - smoothstep(0.0, 0.16, abs(h - 0.07))) * 0.45 * COLOR.a;
	col = mix(col, col * vec3(0.42, 0.44, 0.42), wet);
	col = mix(col, vec3(0.085, 0.10, 0.05), algae);
	col *= mix(0.42, 1.0, COLOR.r);

	vec2 outside = max(max(map_rect.xy - wpos.xz, wpos.xz - map_rect.zw), vec2(0.0));
	col = mix(col * gain, haze_color, smoothstep(16.0, 72.0, length(outside)) * 0.92);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
	ROUGHNESS = mix(0.9, 0.38, wet);
	SPECULAR = mix(0.25, 0.5, wet);
}
