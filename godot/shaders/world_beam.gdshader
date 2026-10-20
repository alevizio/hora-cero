shader_type spatial;
// A straight ribbon between two points on one pooled quad (see world.gd): detection lines, aim lines and tracers.
// UV.x runs 0..1 from the source to the target, UV.y across the ribbon.
//   fill   0..1  solid part measured from the source (a detection line fills with the guard's suspicion)
//   dash_m       length of the dashes of the unfilled remainder in metres (0 = nothing beyond the fill)
//   head   >= 0  tracer mode: a bright streak whose head is at `head` (0..1+) with a tail `tail` long
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform vec4 rest : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform float length_m = 1.0;
uniform float fill = 1.0;
uniform float dash_m = 0.0;
uniform float head = -1.0;
uniform float tail = 0.35;

void fragment() {
	float x = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float aa_x = max(fwidth(x), 0.0001);
	float soft = 1.0 - smoothstep(0.55, 1.0, across);
	vec4 c = vec4(0.0);
	if (head >= 0.0) {
		// tracer: hot head, fading tail
		float behind = (head - x) / max(tail, 0.001);
		float streak = step(0.0, behind) * (1.0 - smoothstep(0.0, 1.0, behind));
		c = vec4(mix(color.rgb, vec3(1.0), streak * streak * streak * 0.6), color.a * streak * (1.0 - smoothstep(0.3, 1.0, across)));
	} else {
		float filled = 1.0 - smoothstep(fill - aa_x, fill + aa_x, x);
		float dashes = 0.0;
		if (dash_m > 0.0) {
			float cell = fract(x * length_m / (dash_m * 2.0));
			dashes = step(cell, 0.5) * (1.0 - smoothstep(0.2, 0.75, across));
		}
		// the filled part: a pale core inside the colour, so it reads on grass, dirt and on a cone of the same hue
		vec3 core = mix(color.rgb, vec3(1.0), (1.0 - smoothstep(0.1, 0.5, across)) * 0.55);
		c = mix(vec4(rest.rgb, rest.a * dashes), vec4(core, color.a * soft), filled);
		// a bright tip where the fill ends
		float tip = (1.0 - smoothstep(0.0, 0.3 / max(length_m, 0.01), abs(x - fill))) * step(0.01, fill) * step(fill, 0.995);
		c.rgb = mix(c.rgb, vec3(1.0), tip * 0.7);
		c.a = max(c.a, tip * soft * color.a);
	}
	ALBEDO = c.rgb;
	ALPHA = clamp(c.a, 0.0, 1.0);
}
