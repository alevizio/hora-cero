shader_type spatial;
// The Garonne and the basin at night: dark, slow, a little oily. Small ripples and the long slow swell of the
// tide; the moon catches the ripples; every lamp on the quay throws a broken column of light across the water
// toward the viewer (computed here from the lamp list, since the renderer has no planar reflections).
render_mode cull_back, depth_draw_always;

uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;   // R lacy foam, G soft blotches, B fine noise
uniform vec3 deep_color : source_color = vec3(0.020, 0.030, 0.034);
uniform vec3 silt_color : source_color = vec3(0.060, 0.058, 0.048);
uniform vec4 map_rect = vec4(13.0, 0.0, 60.0, 40.0);
uniform float flow = 0.08;              // the river runs north (toward -Z), m/s of texture drift
uniform float wave_strength = 0.34;
// Lamps: xyz = position, w = strength; colours: rgb, a = streak length factor. lamps_on fades them all (power cut).
uniform vec4 lamps[16];
uniform vec4 lamp_colors[16];
uniform int lamp_count = 0;
uniform float lamps_on = 1.0;
uniform float water_y = -2.3;
uniform float dawn = 0.0;
uniform vec3 sky_glow = vec3(0.0);       // a sky that is still light (La Boca's blue hour), seen in the water

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float swell = sin(wpos.z * 0.21 + wpos.x * 0.07 + TIME * 0.45) * 0.035 + sin(wpos.z * 0.6 - wpos.x * 0.3 + TIME * 0.8) * 0.012;
	VERTEX.y += swell;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 drift = vec2(0.0, -flow) * TIME;
	vec2 n1 = texture(normal_tex, (p + drift) * 0.13 + TIME * vec2(0.006, 0.003)).rg * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, vec2(p.y, -p.x) * 0.051 + drift.yx * 0.04 + TIME * vec2(-0.004, 0.007)).rg * 2.0 - 1.0;
	vec2 n3 = texture(normal_tex, (p + drift * 1.4) * 0.42 + TIME * vec2(0.019, -0.013)).rg * 2.0 - 1.0;
	vec4 det = texture(detail_tex, (p + drift) * 0.04);
	float calm = smoothstep(0.25, 0.75, texture(detail_tex, p * 0.012 + TIME * vec2(0.001, 0.0006)).g);
	// zoomed out, the fine ripples would only alias into glitter: they fade as a pixel grows past a few cm
	float px = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.025, 0.07, px);
	vec2 nxy = (n1 * 0.6 + n2 * mix(0.35, 0.7, fine) + n3 * 0.15 * fine) * wave_strength * mix(0.55, 1.15, calm);
	vec3 n = normalize(vec3(nxy.x, 1.0, -nxy.y));

	vec3 col = mix(deep_color, silt_color, det.g * 0.6 + 0.2);
	// floating scum and the odd sheen of oil drift with the current
	float scum = smoothstep(0.72, 0.9, det.r * (0.6 + 0.6 * det.b));
	col = mix(col, vec3(0.10, 0.10, 0.085), scum * 0.25);
	vec2 outside = max(max(map_rect.xy - p, p - map_rect.zw), vec2(0.0));
	float away = smoothstep(4.0, 40.0, length(outside));

	// ---- lamp columns: the mirror image of each lamp, smeared toward the viewer by the ripples ----
	vec3 f = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	vec2 fdir = normalize(f.xz + vec2(1e-5));
	vec2 fside = vec2(-fdir.y, fdir.x);
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		if (i >= lamp_count) break;
		vec4 lamp = lamps[i];
		float h = max(lamp.y - water_y, 0.1);
		vec2 centre = lamp.xz - f.xz * h / max(-f.y, 0.2);
		vec2 o = p - centre;
		float along = dot(o, fdir);
		float across = dot(o, fside) + nxy.x * 0.9 + nxy.y * 0.3;
		float len = (0.9 + h * 0.55) * lamp_colors[i].a;
		float width = 0.16 + 0.10 * h * 0.1 + abs(along) * 0.06;
		float shape = exp(-pow(across / width, 2.0)) * exp(-pow(along / len, 2.0));
		// broken into glints by the ripples
		float glint = smoothstep(0.2, 0.75, n3.y * 0.5 + 0.5 + n1.x * 0.35 + det.b * 0.3);
		glow += lamp_colors[i].rgb * lamp.w * shape * mix(0.25, 1.0, glint);
	}
	// the night sky in the water: a dull blue sheen that grows toward grazing angles
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 sky = mix(vec3(0.022, 0.030, 0.046), vec3(0.04, 0.048, 0.06), det.g) * (0.5 + 0.9 * fres);
	sky += vec3(0.035, 0.04, 0.07) * dawn * (0.2 + 1.4 * fres) * (0.6 + 0.8 * det.g);   // the blue hour in the water
	sky += sky_glow * (0.35 + 1.3 * fres) * (0.7 + 0.6 * det.g) * (0.8 + 0.4 * n.x);
	EMISSION = glow * lamps_on * (1.0 - away) * (1.0 - dawn * 0.8) + sky * (1.0 - away * 0.7);
	ALBEDO = col * (1.0 - away * 0.6) + vec3(0.025, 0.028, 0.034) * dawn;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.08, 0.22, scum);
	SPECULAR = 0.55;
}

// Dark water hardly takes diffuse light; the moon and the lamps make sharp glints on the ripples.
void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR * 0.08;
	float glint = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 48.0);
	SPECULAR_LIGHT += glint * 0.35 * ATTENUATION * LIGHT_COLOR;
}
