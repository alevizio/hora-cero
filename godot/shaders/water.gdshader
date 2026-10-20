shader_type spatial;
// Coastal sea: analytic depth tint from the shoreline, three scrolling normal layers, surf foam at the
// waterline and around rocks. Alpha-blended only in the shallows so the wet beach shows through.
render_mode cull_back, depth_draw_never;

uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;   // R lacy foam, G soft blotches, B fine noise
uniform sampler2D mask_tex : filter_linear, repeat_disable;           // A = rock proximity
uniform vec4 mask_rect = vec4(-4.0, -19.5, 0.015625, 0.015625);
uniform vec4 map_rect = vec4(5.0, 0.0, 40.0, 25.0);
uniform vec3 shallow_color : source_color = vec3(0.37, 0.45, 0.38);
uniform vec3 mid_color : source_color = vec3(0.17, 0.29, 0.31);
uniform vec3 deep_color : source_color = vec3(0.10, 0.19, 0.23);
uniform vec3 foam_color : source_color = vec3(0.80, 0.83, 0.80);
uniform vec3 haze_color : source_color = vec3(0.16, 0.20, 0.20);
uniform float water_level = -0.19;
uniform float wave_strength = 0.46;
uniform float gain = 0.5;              // linear albedo gain (exposure trim for this material)

varying vec3 wpos;

float coast_x(float z) {
	float o = max(max(-1.0 - z, z - 26.0), 0.0);
	float w = smoothstep(0.0, 14.0, o);
	return 4.85 + sin(z * 0.9) * 0.10 + sin(z * 0.37 + 1.3) * 0.14 + w * (sin(z * 0.085 + 0.6) * 5.5 + sin(z * 0.21 + 2.0) * 2.2);
}

// Seabed height for a signed shore distance; mirrored in nature.gd (beach_height).
float bed(float sd) {
	return -0.30 * smoothstep(0.45, -0.55, sd) - 1.3 * smoothstep(-0.5, -4.0, sd);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sd = wpos.x - coast_x(wpos.z);
	float open = smoothstep(0.0, -7.0, sd);
	float swell = sin(wpos.z * 0.55 + wpos.x * 0.21 + TIME * 0.8) * 0.030 + sin(wpos.z * 1.3 - wpos.x * 0.4 + TIME * 1.15) * 0.012;
	VERTEX.y += swell * mix(0.45, 1.0, open);
	wpos.y = VERTEX.y;
}

void fragment() {
	vec2 p = wpos.xz;
	float sd = p.x - coast_x(p.y);
	float depth = max(wpos.y - bed(sd), 0.0);
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float out_d = length(outside);
	float haze = smoothstep(16.0, 72.0, out_d) * 0.92;
	vec4 det = texture(detail_tex, p * 0.045 + TIME * vec2(0.004, 0.002));

	// ---- surface normal: two broad layers and a fine ripple, all drifting in different directions ----
	vec2 n1 = texture(normal_tex, p * 0.105 + TIME * vec2(0.011, 0.006)).rg * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, vec2(p.y, -p.x) * 0.043 + TIME * vec2(-0.005, 0.008)).rg * 2.0 - 1.0;
	vec2 n3 = texture(normal_tex, p * 0.33 + TIME * vec2(0.021, -0.016)).rg * 2.0 - 1.0;
	// wind does not ruffle the sea evenly: broad calm lanes and darker gust patches hide the texture repeat
	float gust = smoothstep(0.28, 0.72, texture(detail_tex, p * 0.0113 + TIME * vec2(0.0016, 0.0009)).g * 0.6 + det.b * 0.4);
	vec2 nxy = (n1 * 0.55 + n2 * 0.75 + n3 * 0.28) * wave_strength * mix(0.40, 1.15, gust) * (1.0 - haze * 0.8) * (0.35 + 0.65 * smoothstep(0.0, 0.5, depth));
	vec3 n = normalize(vec3(nxy.x, 1.0, -nxy.y));

	// ---- body colour by depth ----
	vec3 col = mix(shallow_color, mid_color, smoothstep(0.03, 1.0, depth));
	col = mix(col, deep_color, clamp(smoothstep(0.8, 1.48, depth) * 0.7 + smoothstep(-4.0, -34.0, sd) * 0.4, 0.0, 1.0));
	col *= (0.90 + 0.22 * det.g) * mix(1.05, 0.94, gust);  // broad tonal drift
	col += (nxy.x + nxy.y) * 0.035;                      // facets facing the sky pick up a little light

	// ---- foam: lapping surf at the waterline, collars round the rocks ----
	float rocks = texture(mask_tex, (p - mask_rect.xy) * mask_rect.zw).a;
	float lace = texture(detail_tex, p * 0.23 + vec2(TIME * 0.010, sin(TIME * 0.5 + p.y * 0.6) * 0.02)).r;
	float lace2 = texture(detail_tex, p.yx * 0.13 - vec2(TIME * 0.007, 0.0)).r;
	float pulse = 0.5 + 0.5 * sin(TIME * 0.9 + p.y * 0.45 + det.g * 5.0);
	float line = 1.0 - smoothstep(0.0, 0.035 + 0.05 * pulse, depth);                      // thin bright edge
	float wash = (1.0 - smoothstep(0.02, 0.22 + 0.16 * pulse, depth)) * smoothstep(0.18, 0.6, lace + lace2 * 0.5);
	float collar = smoothstep(0.30, 0.90, rocks) * smoothstep(0.22, 0.70, lace + rocks * 0.40 + 0.15 * pulse) * step(0.01, depth);
	float streaks = smoothstep(0.55, 0.95, lace2 * (0.5 + 0.7 * det.g)) * 0.14 * smoothstep(0.25, 1.0, depth);
	float foam = clamp(line * 0.8 + wash * 0.75 + collar * 0.85 + streaks, 0.0, 1.0);

	col = mix(col, foam_color, foam * 0.85);
	col = mix(col * gain, haze_color, haze);
	ALBEDO = col;
	ALPHA = clamp(smoothstep(0.0, 0.05, depth) * mix(0.42, 0.97, smoothstep(0.0, 0.60, depth)) + foam * 0.6, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.22, 0.7, foam);
	SPECULAR = 0.45;
}

// Soft, broad sun glint: a tight physically based highlight turns into sparkling noise when zoomed out.
void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	float glint = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 22.0);
	SPECULAR_LIGHT += glint * 0.028 * ATTENUATION * LIGHT_COLOR;
}
