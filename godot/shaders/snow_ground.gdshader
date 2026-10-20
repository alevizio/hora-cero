shader_type spatial;
// The snow at Vemork (Operation Gunnerside): fresh wind-packed snow everywhere, trodden and driven to a grey crust on
// the roads, the railway and the plant's yard (mask R), the railway's ballast and sleepers showing through (mask G),
// dark at the foot of walls and under the pines (mask B). A faint glitter of crystals catches the light. Far outside
// the map the snow dissolves into the night haze.
render_mode cull_back;

uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ballast_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-8.0, -8.0, 0.0125, 0.0125);   // x0, z0, 1/width, 1/height
uniform vec4 map_rect = vec4(0.0, 0.0, 64.0, 52.0);          // x0, z0, x1, z1
uniform vec3 haze_color : source_color = vec3(0.05, 0.065, 0.10);
uniform vec3 snow_tint : source_color = vec3(0.86, 0.90, 0.97);
uniform float tile = 0.25;          // UV per metre for the ground textures (4 m tiles)
uniform float sparkle = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv = p * tile;
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	vec4 mask = vec4(0.0);
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) mask = texture(mask_tex, muv);
	float macro = texture(macro_tex, p * 0.013).r;
	float macro2 = texture(macro_tex, p * 0.051 + 0.37).g;
	// the wind ripples run two ways, mixed by a slow noise, so they never line up across the whole field
	vec2 uv2 = mat2(vec2(0.62, 0.78), vec2(-0.78, 0.62)) * uv * 0.71 + 0.37;
	float turn = smoothstep(0.35, 0.65, macro);
	vec4 snow = mix(texture(snow_tex, uv), texture(snow_tex, uv2), turn);
	vec4 crust = texture(packed_tex, uv * 1.3);
	vec3 ballast = texture(ballast_tex, uv * 2.2).rgb;
	// fresh snow: near white, a little blue in the hollows, larger soft variations
	vec3 col = snow.rgb * snow_tint * (0.9 + 0.12 * macro + 0.05 * macro2);
	col = mix(col * vec3(0.88, 0.92, 1.0), col, smoothstep(0.2, 0.7, snow.a));
	float packed = clamp(mask.r * (0.75 + 0.5 * macro2), 0.0, 1.0);
	col = mix(col, crust.rgb * vec3(0.92, 0.93, 0.96), packed);
	col = mix(col, ballast * 0.75, mask.g * (0.55 + 0.3 * macro));
	col *= 1.0 - 0.55 * mask.b;
	// beyond the map's edge the ground fades into the night
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float haze = smoothstep(10.0, 60.0, length(outside));
	ALBEDO = mix(col, haze_color, haze * 0.9);
	vec3 n1 = mix(texture(snow_nrm, uv).rgb, texture(snow_nrm, uv2).rgb, turn);
	vec3 n2 = texture(packed_nrm, uv * 1.3).rgb;
	NORMAL_MAP = mix(n1, n2, packed);
	NORMAL_MAP_DEPTH = mix(0.4 + 0.35 * macro2, 0.9, packed);
	ROUGHNESS = mix(0.78, 0.92, max(packed, mask.g));
	SPECULAR = mix(0.42, 0.25, packed);
	// glitter: a few crystals per square decimetre turn their face to the eye
	vec2 cell = floor(p * 38.0);
	float h = hash(cell);
	vec3 face = normalize(vec3(hash(cell + 3.1) - 0.5, 1.2, hash(cell + 7.7) - 0.5));
	vec3 vn = normalize((VIEW_MATRIX * vec4(face, 0.0)).xyz);
	float glint = step(0.93, h) * pow(max(dot(vn, VIEW), 0.0), 60.0);
	EMISSION = vec3(0.75, 0.82, 1.0) * glint * sparkle * (1.0 - packed) * (1.0 - haze) * 0.9;
}
