shader_type spatial;
// The glass of a near copy of a car (tools/vehicles.gd "<name>_near", its second surface; plaza.gd vehicle_materials):
// see-through, so that its seats, dashboard and steering wheel show, dark and tinted, with the night in it (more of it
// at a slant, fresnel), and the snow dusted up its feet and over the windscreen's rake as the night goes on. UV2.y how
// high up its windows a point is (0 at their feet). A multimesh gives each car its state (INSTANCE_CUSTOM.a: 0 parked,
// 0.5 waiting, its lamps on, its driver keeping the glass clearer; 1 a colectivo in service, its glass misted warm);
// a single vehicle the uniforms. (The rules' colectivo's glass too: its lit inside shows through.)
render_mode blend_mix, cull_back, depth_draw_opaque;

#include "res://shaders/vehicle_env.gdshaderinc"

uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float snow_amount = 0.5;
uniform bool per_instance = false;
uniform float in_service = 0.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform float fade = 1.0;
uniform vec3 cabin_light : source_color = vec3(1.0, 0.78, 0.5);

varying vec4 state;
varying vec3 wpos;
varying vec3 wnrm;
varying float hgt;

void vertex() {
	state = per_instance ? INSTANCE_CUSTOM : vec4(0.0, 0.0, 0.0, in_service);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hgt = UV2.y;
}

void fragment() {
	float lit = step(0.25, state.a);
	// (a colectivo in service: its glass misted from the warm inside, a glow in it)
	float cabin = clamp((state.a - 0.5) * 2.0, 0.0, 1.0);
	float n = texture(macro_tex, wpos.xz * 1.1 + wpos.y * 0.7).r;
	float n2 = texture(macro_tex, wpos.xz * 0.23 + wpos.y * 0.31).g;
	// the snow: a crust along the glass's foot (thicker in drifts), a dusting over the raked windscreen
	float night = clamp(snow_amount * 1.3 - 0.1, 0.0, 1.0) * (1.0 - 0.55 * lit);
	float foot = 1.0 - smoothstep(0.02 + 0.1 * n2, 0.06 + 0.16 * n2, hgt);
	float rake = smoothstep(0.3, 0.7, wnrm.y) * smoothstep(0.5, 0.85, n * 0.6 + n2 * 0.6) * 0.5;
	float dust = clamp((foot * 0.85 + rake) * night, 0.0, 1.0);
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(vec3(0.015, 0.02, 0.025), snow_color * (0.9 + 0.1 * n), dust);
	ROUGHNESS = mix(0.06, 0.8, dust);
	SPECULAR = mix(0.9, 0.35, dust);
	METALLIC = 0.0;
	EMISSION = (vehicle_env(NORMAL, VIEW, INV_VIEW_MATRIX, 0.06, vec3(1.0)) * 1.4 + cabin_light * cabin * 1.1) * (1.0 - dust);
	ALPHA = clamp(0.30 + 0.6 * f + dust + 0.3 * cabin, 0.0, 1.0) * fade;
}
