shader_type canvas_item;
// One-pass finishing grade drawn on a CanvasLayer below the HUD (see atmosphere.gd).
// Works on the display-referred image: gentle filmic S-curve, muted olive/steel palette, vignette, light grain.
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float contrast = 0.22;          // S-curve amount
uniform float saturation = 0.86;
uniform vec3 shadow_tint : source_color = vec3(0.46, 0.50, 0.54);     // cool steel in the darks
uniform vec3 highlight_tint : source_color = vec3(0.54, 0.52, 0.46);  // warm khaki in the lights
uniform float tint_amount = 0.10;
uniform float lift = 0.022;             // haze: blacks never quite reach black
uniform vec3 lift_color = vec3(0.80, 0.92, 1.0);  // the haze's colour
uniform float vignette = 0.22;
uniform float grain = 0.018;
uniform float sharpen = 0.0;            // 0 = off (no extra taps); ~0.3 is a mild unsharp mask
uniform float tilt_shift = 0.0;         // 0 = off (no extra taps); 1 = the miniature look: top and bottom soft
uniform float tilt_band = 0.16;         // half-height of the sharp band round the middle of the screen
uniform float tilt_radius = 3.2;        // blur radius at the very top / bottom, in pixels

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (tilt_shift > 0.0) {
		// soft above and below a sharp band a little under the middle (where the eye sits in the picture)
		float d = abs(SCREEN_UV.y - 0.54);
		float r = smoothstep(tilt_band, 0.5, d) * tilt_radius * tilt_shift;
		if (r > 0.25) {
			vec2 px = SCREEN_PIXEL_SIZE * r;
			vec3 acc = c * 0.2;
			acc += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV + px * vec2(0.7, 0.7)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV + px * vec2(-0.7, 0.7)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV + px * vec2(0.7, -0.7)).rgb * 0.1;
			acc += texture(screen_tex, SCREEN_UV + px * vec2(-0.7, -0.7)).rgb * 0.1;
			c = acc;
		}
	}
	if (sharpen > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 blur = texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb + texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb
				+ texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb + texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb;
		c = clamp(c + (c - blur * 0.25) * sharpen, 0.0, 1.0);
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// split-tone, then pull chroma in slightly
	vec3 toned = c * mix(shadow_tint, highlight_tint, smoothstep(0.1, 0.75, l)) * 2.0;
	c = mix(c, toned, tint_amount);
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
	// S-curve around mid grey
	vec3 s = c * c * (3.0 - 2.0 * c);
	c = mix(c, s, contrast);
	c = c * (1.0 - lift) + lift * lift_color;
	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.25, 0.95, dot(v, v) * 2.0);
	c += (hash(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
