shader_type spatial;
// Low mist over the river and the basin: slow drifting veils, dark blue in the open, warm where a lamp stands
// near (the same lamp list the water uses), so every light seems to hang in its own halo.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 mist_color : source_color = vec3(0.12, 0.15, 0.20);
uniform float density = 0.18;
uniform vec4 lamps[16];
uniform vec4 lamp_colors[16];
uniform int lamp_count = 0;
uniform float lamps_on = 1.0;
uniform float dawn = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float a = texture(noise_tex, p * 0.035 + TIME * vec2(0.004, -0.010)).r;
	float b = texture(noise_tex, p * 0.09 + TIME * vec2(-0.008, -0.006)).g;
	float c = texture(noise_tex, p.yx * 0.017 + TIME * vec2(0.002, 0.003)).b;
	float veil = smoothstep(0.2, 1.0, a * 0.55 + b * 0.3 + c * 0.35);
	vec3 lit = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		if (i >= lamp_count) break;
		vec4 lamp = lamps[i];
		vec2 d = p - lamp.xz;
		float r = 3.0 + lamp.w * 1.5;
		lit += lamp_colors[i].rgb * lamp.w * exp(-dot(d, d) / (r * r)) * 0.55;
	}
	vec3 col = mist_color * (1.0 + dawn * 0.9) + lit * lamps_on;
	ALBEDO = col;
	ALPHA = veil * density * (1.0 - dawn * 0.25);
}
