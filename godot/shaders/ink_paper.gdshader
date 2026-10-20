shader_type canvas_item;
// Comic ink, the printing half (scripts/three_d/ink.gd; ink_lines.gdshader draws it): one canvas pass under the HUD in
// place of the colour grade. The 3D view arrives as grey ink on white, with the blended passes drawn over it in their
// own colours. This prints it on newsprint:
//  - grey becomes ink on warm paper; washes between the two (mist, the river, a contact shadow) go to a halftone
//    screen, which belongs to the page and so stays put on the screen;
//  - strong colour survives as a second, flat printing colour (the sight cones, routes and markers keep their
//    meaning; world.gd prints them in warm colours, greens and red-violet); weak colour and any cold blue (the snow
//    in shadow, a trodden track) are printed in black;
//  - paper grain, a few fibres, a slight unevenness of the ink, and a soft darkening at the edges.
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec3 paper : source_color = vec3(0.925, 0.898, 0.823);
uniform vec3 ink : source_color = vec3(0.075, 0.068, 0.062);
uniform float spot = 1.0;           // how much of strong colour is kept (0: everything in black and white)
uniform float spot_from = 0.12;     // chroma where colour starts to be kept
uniform float spot_to = 0.28;       // and where it is kept whole
uniform float halftone = 0.55;      // 0..1: how much of the in-between greys goes to dots
uniform float dot_px = 4.2;         // halftone cell, in pixels at 720 lines
uniform float grain = 0.045;
uniform float fibres = 0.035;
uniform float vignette = 0.16;
uniform float ink_density = 1.0;    // 1 = the ink as given; below lets the paper show through the blacks a little
uniform float raw = 0.0;            // 1: the picture as it comes (to look at the drawing pass's debug views)

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float L = dot(c, vec3(0.299, 0.587, 0.114));
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float chroma = hi - lo;
	vec2 fc = FRAGCOORD.xy;
	float res = max(1.0 / SCREEN_PIXEL_SIZE.y / 720.0, 0.75);
	// --- halftone: a 45-degree dot screen for the greys between ink and paper
	float cell = dot_px * res;
	vec2 rot = vec2(fc.x + fc.y, fc.x - fc.y) * 0.70710678 / cell;
	vec2 f = fract(rot) - 0.5;
	float dist = length(f) * 1.4142;          // 0 at a dot's centre .. 1 at the cell's corner
	float cover = 1.0 - L;                     // how much ink the grey asks for
	float rad = sqrt(clamp(cover, 0.0, 1.0));  // a dot of that area
	float aa = 1.6 / cell;
	float dots = 1.0 - smoothstep(rad - aa, rad + aa, dist);
	// only where the grey is an even wash (mist, water, a shadow under a man), not the soft edge of a pen line
	vec2 sp = SCREEN_PIXEL_SIZE * 2.0 * res;
	float lx = dot(texture(screen_tex, SCREEN_UV + vec2(sp.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float ly = dot(texture(screen_tex, SCREEN_UV + vec2(0.0, sp.y)).rgb, vec3(0.299, 0.587, 0.114));
	float even = 1.0 - smoothstep(0.03, 0.10, max(abs(lx - L), abs(ly - L)));
	float keep = smoothstep(spot_from, spot_to, chroma) * spot;
	// the game prints its marks in warm colours, greens and red-violet (world.gd); a cold blue is the scene's own
	// (snow in shadow, a trodden track) and prints in black
	keep *= 1.0 - smoothstep(0.0, 0.08, c.b - max(c.r, c.g));
	float mid = smoothstep(0.06, 0.2, L) * (1.0 - smoothstep(0.8, 0.94, L)) * even * (1.0 - keep);
	float inked = mix(cover, dots, halftone * mid);
	// --- the page
	float g = 1.0 - inked;
	float tooth = (hash(floor(fc)) - 0.5) * grain;
	float cloud = (vnoise(fc / (38.0 * res)) - 0.5) * 0.05 + (vnoise(fc / (9.0 * res) + 7.3) - 0.5) * 0.025;
	float fibre = smoothstep(0.82, 0.98, vnoise(vec2(fc.x * 0.06, fc.y * 0.9) / res + 3.1)) * fibres;
	vec3 sheet = paper * (1.0 + cloud + tooth) - fibre;
	vec3 blot = ink + (vnoise(fc / (6.0 * res)) - 0.5) * 0.03 + (1.0 - ink_density) * 0.2;
	vec3 o = mix(blot, sheet, g);
	// --- the second colour: what is strongly coloured keeps its hue over the drawing, like a flat overprint
	vec3 hue = c - vec3(L);
	o += hue * keep * 1.15;
	// --- the edges of the page, a little darker
	vec2 v = SCREEN_UV - 0.5;
	o *= 1.0 - vignette * smoothstep(0.2, 0.9, dot(v, v) * 2.0);
	COLOR = vec4(raw > 0.5 ? c : clamp(o, 0.0, 1.0), 1.0);
}
