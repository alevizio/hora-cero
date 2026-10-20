shader_type spatial;
// The ground of La Boca on the snowy night (Operation Riachuelo): fresh wet snow on the pavements, the quay, the patios
// and the quiet streets (where footprints show); on the busy streets, the square and the avenue (the rules' packed
// snow) the granite setts show through grey slush, snow lodged in their joints, wet and dark where the wheels run;
// the tram rails cut dark lines; dark at the foot of every wall. Beyond the city it all dissolves into the blue haze.
render_mode cull_back;

uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D setts_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
// the layout, one map each: R slush (where the snow is trodden), the tram rails, the foot of the walls, the carriageways
uniform sampler2D slush_tex : filter_linear, repeat_disable;
uniform sampler2D rails_tex : filter_linear, repeat_disable;
uniform sampler2D occl_tex : filter_linear, repeat_disable;
uniform sampler2D road_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-60.0, -45.0, 0.0027, 0.0040);   // x0, z0, 1/width, 1/height
uniform vec4 map_rect = vec4(-60.0, -45.0, 300.0, 200.0);      // x0, z0, x1, z1 of the built city
uniform vec3 haze_color : source_color = vec3(0.42, 0.44, 0.56);
uniform vec3 snow_tint : source_color = vec3(0.84, 0.86, 0.93);
uniform float sparkle = 0.6;

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
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	float slush = 0.0;
	float rails = 0.0;
	float occl = 0.0;
	float road = 0.0;
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		slush = texture(slush_tex, muv).r;
		rails = texture(rails_tex, muv).r;
		occl = texture(occl_tex, muv).r;
		road = texture(road_tex, muv).r;
	}
	float macro = texture(macro_tex, p * 0.013).r;
	float macro2 = texture(macro_tex, p * 0.051 + 0.37).g;
	float fine = texture(macro_tex, p * 0.31 + 0.11).b;
	vec2 uv = p * 0.25;
	// fresh snow: wet, soft, a little blue in its hollows
	vec4 sn = texture(snow_tex, uv);
	vec3 snow = sn.rgb * snow_tint * (0.92 + 0.1 * macro + 0.04 * macro2);
	snow = mix(snow * vec3(0.9, 0.93, 1.0), snow, smoothstep(0.2, 0.7, sn.a));
	// granite setts (0.5 m texture tiles at 4 per 2 m), wet; snow lodged in the joints
	vec2 suv = p * 0.5;
	vec3 setts = texture(setts_tex, suv).rgb;
	float lum = dot(setts, vec3(0.333));
	vec3 stone = setts * vec3(0.52, 0.53, 0.58);
	float joint = smoothstep(0.42, 0.28, lum);
	stone = mix(stone, snow * 0.86, joint * 0.75);
	// trodden slush: grey, uneven, thinner in the wheel tracks and on the crown of the road
	vec3 crust = texture(packed_tex, p * 0.22).rgb * vec3(0.9, 0.9, 0.94);
	float cover = smoothstep(0.25, 0.8, macro2 * 0.6 + fine * 0.5 + (1.0 - road) * 0.45);
	vec3 trodden = mix(stone, crust, cover);
	// on the pavements trodden snow, not stone
	trodden = mix(mix(snow * vec3(0.86, 0.88, 0.95), crust * 1.08, 0.55 + 0.3 * fine), trodden, road);
	float s = clamp(slush * (0.85 + 0.3 * macro2), 0.0, 1.0);
	vec3 col = mix(snow, trodden, s);
	// on the quiet streets the setts only show as a faint pattern under the snow
	col = mix(col, col * (0.92 + 0.08 * smoothstep(0.25, 0.45, lum)), road * (1.0 - s) * 0.6);
	// the tram rails: a dark wet strip with the steel in it
	col = mix(col, stone * 0.7, rails * 0.8);
	col *= 1.0 - 0.42 * occl;
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float haze = smoothstep(4.0, 40.0, length(outside));
	ALBEDO = mix(col, haze_color, haze);
	vec3 n_snow = texture(snow_nrm, uv).rgb;
	vec3 n_stone = texture(setts_nrm, suv).rgb;
	NORMAL_MAP = mix(n_snow, mix(n_stone, vec3(0.5, 0.5, 1.0), cover * 0.7), s);
	NORMAL_MAP_DEPTH = mix(0.5, 1.0, s);
	float wet = s * road * (1.0 - cover) + rails;
	ROUGHNESS = mix(0.8, 0.28, clamp(wet, 0.0, 1.0));
	SPECULAR = mix(0.4, 0.6, clamp(wet, 0.0, 1.0));
	vec2 cell = floor(p * 38.0);
	float h = hash(cell);
	vec3 face = normalize(vec3(hash(cell + 3.1) - 0.5, 1.2, hash(cell + 7.7) - 0.5));
	vec3 vn = normalize((VIEW_MATRIX * vec4(face, 0.0)).xyz);
	float glint = step(0.93, h) * pow(max(dot(vn, VIEW), 0.0), 60.0);
	EMISSION = vec3(0.75, 0.82, 1.0) * glint * sparkle * (1.0 - s) * (1.0 - haze) * 0.8;
}
