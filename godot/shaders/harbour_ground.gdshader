shader_type spatial;
// Bordeaux quays at night after rain: granite setts, cinder ballast in the rail yard, concrete aprons on the
// building site, tar on the road, mud where the lorries turn. Everything is wet; water stands in the joints
// and in puddles, which turn into mirrors for the lamps (the renderer's own specular does the reflections).
// World-space mapped; the two masks are built at load by harbour_ground.gd from the mission layout:
//   zone_tex  R = cinders, G = tar, B = concrete, A = mud   (setts where all four are 0)
//   wear_tex  R = contact occlusion, G = wetness bias, B = grime and oil, A = kerb / edge darkening
render_mode cull_back;

uniform sampler2D setts_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // rgb + height
uniform sampler2D setts_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cinder_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cinder_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tar_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tar_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // rgb + height
uniform sampler2D mud_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D zone_tex : filter_linear, repeat_disable;
uniform sampler2D wear_tex : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-34.0, -44.0, 0.0078125, 0.0078125);   // origin.xz, 1/size
uniform vec4 map_rect = vec4(13.0, 0.0, 60.0, 40.0);               // playable min.xz, max.xz
uniform float uv_m = 0.390625;          // 1 / 2.56 m
uniform float wetness = 0.62;           // how much rain is still lying about
uniform float gain = 0.95;              // linear albedo gain (exposure trim for this material)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 unpack(vec4 n) {
	return vec3(n.rg * 2.0 - 1.0, 0.0);
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 m1 = texture(macro_tex, p * 0.0213);
	vec4 m2 = texture(macro_tex, p.yx * 0.0871 + vec2(0.37, 0.11));
	vec4 m3 = texture(macro_tex, p * 0.31 + vec2(0.61, 0.23));
	vec2 muv = (p - mask_rect.xy) * mask_rect.zw;
	// zones are read through a small warp so their edges fray like real wear, not stamped rectangles
	vec4 zone = texture(zone_tex, muv + ((m3.rg - 0.5) * 0.6 + (m2.ba - 0.5) * 0.4) * mask_rect.zw);
	vec4 wear = texture(wear_tex, muv);
	vec2 uv = p * uv_m;
	// setts run east-west on the quay; a slight swing breaks the repeat
	vec4 st = texture(setts_tex, uv);
	vec4 ci = texture(cinder_tex, uv * 1.15 + vec2(0.31, 0.17));
	vec4 ta = texture(tar_tex, uv * 0.8 + vec2(0.13, 0.57));
	vec4 co = texture(concrete_tex, uv * 0.5 + vec2(0.43, 0.21));
	vec4 mu = texture(mud_tex, uv * 0.75 + vec2(0.71, 0.33));
	vec3 nst = unpack(texture(setts_nrm, uv));
	vec3 nci = unpack(texture(cinder_nrm, uv * 1.15 + vec2(0.31, 0.17)));
	vec3 nta = unpack(texture(tar_nrm, uv * 0.8 + vec2(0.13, 0.57)));
	vec3 nco = unpack(texture(concrete_nrm, uv * 0.5 + vec2(0.43, 0.21)));
	vec3 nmu = unpack(texture(mud_nrm, uv * 0.75 + vec2(0.71, 0.33)));

	// ---- blend the surfaces (height-aware where they meet) ----
	float w_ci = smoothstep(0.25, 0.75, zone.r + (ci.a - 0.5) * 0.5);
	float w_ta = smoothstep(0.25, 0.75, zone.g + (ta.a - 0.5) * 0.4);
	float w_co = smoothstep(0.25, 0.75, zone.b + (m1.g - 0.5) * 0.3);
	float w_mu = smoothstep(0.2, 0.8, zone.a + (m2.r - 0.5) * 0.6 - (st.a - 0.5) * 0.3);
	vec3 col = st.rgb;
	vec3 nrm = nst;
	float height = st.a;
	col = mix(col, ci.rgb, w_ci); nrm = mix(nrm, nci, w_ci); height = mix(height, ci.a, w_ci);
	col = mix(col, ta.rgb, w_ta); nrm = mix(nrm, nta, w_ta); height = mix(height, ta.a, w_ta);
	col = mix(col, co.rgb * vec3(0.92, 0.92, 0.9), w_co); nrm = mix(nrm, nco, w_co); height = mix(height, 0.55 + (co.r - 0.5) * 0.3, w_co);
	col = mix(col, mu.rgb * vec3(0.72, 0.66, 0.58), w_mu); nrm = mix(nrm, nmu, w_mu); height = mix(height, mu.a * 0.6, w_mu);

	// ---- broad variation, grime, occlusion ----
	col *= 0.86 + 0.24 * m1.b;
	col *= mix(1.0, 0.82 + 0.2 * m2.g, 0.6);
	float grime = wear.b * smoothstep(0.25, 0.75, m3.b + 0.2);
	col = mix(col, col * vec3(0.42, 0.40, 0.38), grime * 0.7);
	col *= mix(1.0, 0.45, wear.r);
	col *= 1.0 - wear.a * 0.25;

	// ---- water: a film everywhere, puddles where the ground is low ----
	float wet_base = clamp(wetness * (0.65 + 0.7 * wear.g), 0.0, 1.0);
	float basin = smoothstep(0.42, 0.72, m1.a * 0.65 + m2.b * 0.35 + wear.g * 0.35 - height * 0.45);
	float puddle = clamp(basin * wet_base * 1.6, 0.0, 1.0);
	float film = clamp(wet_base * (1.0 - height) * 1.4, 0.0, 1.0);
	col *= mix(1.0, 0.62, max(film, puddle * 0.9));   // wet stone goes darker
	nrm = mix(nrm, vec3(0.0), puddle * 0.92);
	float rough = mix(0.86, 0.38, film);
	rough = mix(rough, 0.06, puddle);

	// ---- beyond the playable ground the quays sink into the dark ----
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float away = smoothstep(2.0, 26.0, length(outside));
	col *= 1.0 - away * 0.78;

	ALBEDO = col * gain;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.6, puddle);
	vec3 n = normalize(vec3(nrm.x * 1.1, 1.0, -nrm.y * 1.1));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
