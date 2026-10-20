shader_type spatial;
// Every built surface in La Boca under the night's wet snow (Operation Riachuelo): the surface's own textures (painted
// iron, lime render, brick, planks, granite, iron), with snow lying wherever it faces up enough to hold it: roofs,
// cornices, sills, ledges, rails, lamp tops. The vertex colour's alpha says how much snow a thing holds (1 = all it
// can; a warm chimney or a roof over a stove holds less). Dithered away ("fade" < 1) when somebody stands behind it.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform bool rough_alpha = false;
uniform float roughness = 0.9;
uniform float normal_scale = 1.0;
uniform float specular = 0.4;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float snow_amount = 1.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	vec2 uv = UV * uv_scale;
	vec4 t = texture(albedo_tex, uv);
	vec3 base = t.rgb * COLOR.rgb;
	float rough = rough_alpha ? t.a : roughness;
	float n = texture(macro_tex, wpos.xz * 0.21 + wpos.y * 0.07).r;
	float n2 = texture(macro_tex, wpos.xz * 0.9 + wpos.y * 0.3).g;
	// snow lies on what faces up; on a roof the ribs and the laps show through where it is thinnest
	float lie = smoothstep(0.42, 0.78, wnrm.y + (n - 0.5) * 0.35);
	float thin = smoothstep(0.25, 0.75, n2) * 0.25;
	float drift = (1.0 - smoothstep(0.0, 0.55, wpos.y)) * smoothstep(0.2, 0.0, abs(wnrm.y)) * 0.55;
	float s = clamp(max(lie - thin * lie * (1.0 - COLOR.a * 0.5), drift * step(0.45, n)) * snow_amount * COLOR.a, 0.0, 1.0);
	vec3 snow = snow_color * (0.9 + 0.12 * n);
	ALBEDO = mix(base, snow, s);
	if (use_normal) {
		NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), s * 0.9);
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ROUGHNESS = mix(rough, 0.8, s);
	SPECULAR = mix(specular, 0.35, s);
}
