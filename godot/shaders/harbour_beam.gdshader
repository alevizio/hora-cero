shader_type spatial;
// The searchlight's beam through the night mist: a soft additive cone, brightest at the lens and along its
// axis, fading out with distance; a little drifting grain so it reads as light in the air, not glass.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform vec3 beam_color : source_color = vec3(0.78, 0.86, 1.0);
uniform float strength = 1.0;
uniform float intensity = 1.5;

varying vec3 local;
varying vec3 wpos;

void vertex() {
	local = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// the cone's axis runs along local Y (height 18 m): -9 at the lens, +9 at the wide far end
	float t = clamp((local.y + 9.0) / 18.0, 0.0, 1.0);
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(rim, 1.6);
	float fade = (1.0 - smoothstep(0.15, 1.0, t)) * smoothstep(0.0, 0.04, t);
	float grain = 0.85 + 0.15 * sin(wpos.x * 3.1 + wpos.z * 2.3 + TIME * 0.7) * sin(wpos.y * 4.7 - TIME * 0.5);
	ALBEDO = beam_color;
	ALPHA = clamp(intensity * strength * core * fade * grain, 0.0, 1.0);
}
