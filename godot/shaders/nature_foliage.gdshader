shader_type spatial;
// Alpha cut-out foliage: tree boughs, crowns, shrubs and ground cover.
// Vertex COLOR.rgb = baked depth shading (x per-instance tint), COLOR.a = wind weight (0 = rigid).
// With use_cells = 1 the atlas rectangle comes from INSTANCE_CUSTOM (xy = origin, zw = size) and UV spans 0..1.
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float use_cells = 0.0;
uniform float flat_normal = 0.0;        // 1 = shade like the ground (grass tufts)
uniform float wind_amp = 0.06;
uniform float wrap = 0.45;              // diffuse wrap: soft, leafy falloff
uniform float brightness = 0.62;        // linear albedo gain (exposure trim)
uniform float mip_bias = -0.6;          // slightly sharper cut-outs than the default mip choice
uniform vec4 map_rect = vec4(5.0, 0.0, 40.0, 25.0);
uniform vec3 haze_color : source_color = vec3(0.16, 0.20, 0.20);

void vertex() {
	if (use_cells > 0.5) {
		UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	}
	float ph = VERTEX.x * 0.37 + VERTEX.z * 0.29;
	float sway = sin(TIME * 1.15 + ph) * 0.6 + sin(TIME * 2.7 + ph * 2.3) * 0.4;
	VERTEX += vec3(0.8, 0.12, 0.6) * (sway * wind_amp * COLOR.a);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), flat_normal));
	// distance haze, same curve as the terrain
	vec2 outside = max(max(map_rect.xy - VERTEX.xz, VERTEX.xz - map_rect.zw), vec2(0.0));
	COLOR.a = smoothstep(16.0, 72.0, length(outside)) * 0.92;
}

void fragment() {
	vec4 t = texture(atlas, UV, mip_bias);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = mix(t.rgb * COLOR.rgb * brightness, haze_color, COLOR.a);
	// cards carry hand-set "volume" normals: do not flip them on back faces
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
