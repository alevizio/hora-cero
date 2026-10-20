shader_type spatial;
// Falling snow: a MultiMesh of small quads, each instance a flake whose origin lies somewhere in a box `span` metres
// on a side. The vertex shader moves every flake down and sideways with TIME and wraps it back into the box around
// `focus` (where the camera looks), then turns the quad to face the camera. Nothing moves on the CPU.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec3 focus = vec3(32.0, 0.0, 26.0);
uniform vec3 span = vec3(48.0, 18.0, 48.0);
uniform float fall_speed = 1.1;
uniform vec2 wind = vec2(0.35, 0.12);
uniform float flake_size = 0.06;
uniform float strength = 0.75;
uniform vec3 flake_color : source_color = vec3(0.86, 0.9, 1.0);

varying vec2 quad;
varying float fade;

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float t = TIME;
	float wobble = sin(t * 0.9 + seed.x * 3.1 + seed.z * 1.7) * 0.25;
	vec3 p = seed + vec3(wind.x * t + wobble, -fall_speed * t * (0.8 + 0.4 * fract(seed.x * 7.13)), wind.y * t);
	vec3 lo = focus - span * 0.5 + vec3(0.0, span.y * 0.5 - 1.0, 0.0);
	p = lo + mod(p - lo, span);
	// thin out toward the top and bottom of the box so the wrap is never seen
	float h = (p.y - lo.y) / span.y;
	fade = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.75, 1.0, h));
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float size = flake_size * (0.7 + 0.6 * fract(seed.z * 13.7));
	vec3 world = p + (right * VERTEX.x + up * VERTEX.y) * size * 2.0;
	quad = VERTEX.xy * 2.0;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(quad);
	ALBEDO = flake_color;
	ALPHA = (1.0 - smoothstep(0.35, 1.0, r)) * strength * fade;
}
