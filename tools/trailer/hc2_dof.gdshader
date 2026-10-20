shader_type spatial;
// The trailer's depth of field (hc2_director.gd, dev tool): a quad over the whole frame, drawn first of the
// see-through things (render_priority -128), that reads the scene drawn so far (the opaque world: the snow falling,
// the halos and the glass are drawn after it, sharp) and its depth, and blurs each pixel by its circle of confusion:
// nothing at `focus` metres, more the further it is in front or behind, up to `max_px` pixels (at 1080 lines).
// Gathered over a golden-angle disc whose samples only take what is at least as blurred as they reach (so a sharp
// subject never smears onto the soft background behind it, nor the background bleeds over its edge).
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float focus = 6.0;
// the blur a thing gets at twice (or half) the focus distance, in pixels at 1080 lines; and the most
uniform float blur_px = 8.0;
uniform float max_px = 18.0;
// how much more the near side blurs than the far (a long lens close up)
uniform float near_gain = 1.0;
uniform float strength = 1.0;
// calibration: 1 the screen as read, 2 a log ramp of linear light (0.001 .. 10) across the frame
uniform int mode = 0;
// The screen texture holds the opaque world as the renderer stored it, and what this quad writes is stored the same
// way again (the Compatibility renderer multiplies a material's output by the exposure, among other things, before it
// stores it): read back, it is multiplied by `gain` to come out as it went in. Measured against the scene drawn without
// the quad (the director's view probes with dof_mode 1): 1 / sqrt(exposure) to within 2 levels in 255 (median),
// at the plaza's two exposures (0.46 and 0.58). Where nothing is blurred the quad lets the scene through untouched.
uniform float gain = 1.0;

vec3 screen(vec2 uv) {
	return texture(screen_tex, uv).rgb * gain;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, -0.999, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	return -v.z / v.w;
}

float coc(float z, float scale) {
	// thin lens: the blur grows with |1/focus - 1/z|, scaled so that z = 2 * focus gives blur_px
	float k = (1.0 / focus - 1.0 / max(z, 0.05)) * focus * 2.0;
	k = k < 0.0 ? k * near_gain : k;
	return clamp(abs(k) * blur_px * scale, 0.0, max_px * scale) * strength;
}

void fragment() {
	float scale = VIEWPORT_SIZE.y / 1080.0;
	float z0 = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float c0 = coc(z0, scale);
	vec3 base = screen(SCREEN_UV);
	if (mode == 1) {
		ALBEDO = base;
		ALPHA = 1.0;
	} else if (mode == 2) {
		ALBEDO = vec3(pow(10.0, mix(-3.0, 1.0, SCREEN_UV.x)));
		ALPHA = 1.0;
	} else {
		// the widest a sample may reach: the most blur there is (a soft thing in front reaches over a sharp one)
		float reach = max_px * scale * strength;
		vec3 acc = base;
		float wsum = 1.0;
		float spread = 0.0;
		const int N = 32;
		float turn = hash(FRAGCOORD.xy) * 6.2832;
		for (int i = 1; i < N; i++) {
			float a = float(i) * 2.39996 + turn;
			float r = sqrt(float(i) / float(N)) * reach;
			vec2 uv = SCREEN_UV + vec2(cos(a), sin(a)) * r / VIEWPORT_SIZE;
			float zi = linear_depth(uv, INV_PROJECTION_MATRIX);
			float ci = coc(zi, scale);
			// a sample counts if its own blur reaches this far, and (if it lies behind this pixel) if this pixel's does
			float own = smoothstep(r - 1.5, r + 0.5, ci);
			float here = zi > z0 + 0.05 ? smoothstep(r - 1.5, r + 0.5, c0) : 1.0;
			float w = own * here;
			acc += screen(uv) * w;
			wsum += w;
			// a blurred thing in front reaching over this pixel
			spread = max(spread, zi < z0 - 0.05 ? w * ci : 0.0);
		}
		ALBEDO = acc / wsum;
		// where nothing is blurred (and nothing blurred reaches), the scene shows through as it was drawn
		ALPHA = smoothstep(0.35, 1.6, max(c0, spread));
	}
}
