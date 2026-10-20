shader_type spatial;
// The vehicles made from the friends' models (tools/vehicles.gd: godot/assets/vehicles/): the Línea 60 colectivo, the
// small saloon and the light pickup of the time, each one mesh of one surface. Per vertex: COLOR its material's colour
// (linear; for the paint a car takes its own colour, its shade), UV2.x what it is (paint, paint of its own, metal,
// rubber, glass, headlamp, tail lamp, lettering, route board, amber lamp, a taxi's yellow roof), UV the lettering's coordinates. A multimesh
// of them gives each instance its paint (INSTANCE_CUSTOM.rgb) and how it stands (.a: 0 parked, its lamps out, snowed
// in a little deeper; 0.5 a car waiting with its lamps on; 1 a colectivo in service, its windows, headlamps and route
// board lit); a single one takes the uniforms. The
// night's snow (snow_amount) whitens whatever faces up and, on the colectivo's rounded roof, lies in a layer that
// thickens through the night (inflate). Dithered away ("fade" < 1) when somebody stands behind it, like the buildings.
// The near copies of the cars (tools/vehicles.gd "_near") carry their inside (14, and 16 the painted dashboard: no snow
// on them) and their glass as a second surface (plaza_vehicle_glass.gdshader). Every car's number plates (15) are a
// cell of the second atlas, one of eight registrations picked by where the car stands. The chrome, the paint and the
// glass take the night's light from round them (vehicle_env.gdshaderinc: the dark sky, the glow of the lamps along
// the horizon, the lit snow below); the lower panels are wet and splashed with slush.
render_mode cull_back;

#include "res://shaders/vehicle_env.gdshaderinc"

uniform sampler2D lettering : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float snow_amount = 0.5;
// metres of snow on a roof at the end of the night (the cap tools/vehicles.gd laid over the faces that look up)
uniform float cap_depth = 0.12;
uniform sampler2D filete : source_color, filter_linear_mipmap, repeat_disable;
// a single vehicle's paint and state (a multimesh's come per instance)
uniform bool per_instance = false;
uniform vec3 paint : source_color = vec3(0.1, 0.1, 0.1);
uniform float in_service = 1.0;
uniform vec3 snow_color : source_color = vec3(0.9, 0.89, 0.94);
uniform vec3 cabin_light : source_color = vec3(1.0, 0.78, 0.5);
uniform float fade = 1.0;
// how high the slush and the wet reach up a vehicle's sides (metres)
uniform float wet_height = 0.55;

varying flat float kind;
varying flat float plate;
varying vec3 lpos;
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 state;

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

void vertex() {
	kind = UV2.x;
	state = per_instance ? INSTANCE_CUSTOM : vec4(paint, in_service);
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	// each car its own registration: one of the atlas's eight plates, by where it stands
	plate = floor(fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453) * 8.0);
	// the snow cap: its top rises off the paint as the night's snow lies deeper (a parked car's deeper than a bus's
	// in service), the foot of its skirt stays on the paint
	if (int(UV2.x + 0.5) == 12) VERTEX.y += 0.006 + UV2.y * (0.008 + cap_depth * snow_amount * (1.2 - 0.4 * step(0.25, state.a)));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) discard;
	int k = int(kind + 0.5);
	vec3 base = COLOR.rgb;
	float rough = 0.45;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	// the lamps on (a car waiting, a colectivo in service); the cabin lit (a colectivo in service)
	float lit = step(0.25, state.a);
	float cabin = clamp((state.a - 0.5) * 2.0, 0.0, 1.0);
	float n = texture(macro_tex, wpos.xz * 0.37 + wpos.y * 0.21).r;
	if (k == 1) {
		// paint of the car's own: its colour in the shade the model gives this panel
		base = state.rgb * COLOR.r;
		rough = 0.34;
	} else if (k == 0 || k == 13) {
		rough = 0.36;
		// (13: a taxi's yellow roof, brushed clear of most of the snow, catching the lamps' light: it reads yellow at night)
		if (k == 13) emit = base * 0.22;
	} else if (k == 2) {
		rough = 0.24;
		metal = 0.75;
		base = mix(base, vec3(0.55, 0.57, 0.6), 0.2);
	} else if (k == 3) {
		rough = 0.85;
		spec = 0.3;
	} else if (k == 4) {
		// glass: in a colectivo in service, its windows lit warm from inside; else dark and glossy, the sky in it
		rough = 0.08;
		spec = 0.8;
		base = vec3(0.025, 0.03, 0.04);
		float row = smoothstep(1.7, 2.3, wpos.y - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y);
		emit = cabin_light * cabin * (1.6 - 0.5 * row);
	} else if (k == 5) {
		base = vec3(0.85, 0.82, 0.7);
		rough = 0.12;
		emit = vec3(1.0, 0.88, 0.62) * lit * 6.0;
	} else if (k == 6) {
		base = vec3(0.35, 0.03, 0.02);
		rough = 0.15;
		emit = vec3(1.0, 0.12, 0.06) * lit * 2.5;
	} else if (k == 10) {
		rough = 0.15;
		emit = vec3(1.0, 0.55, 0.15) * lit * 0.6;
	} else if (k == 7) {
		vec4 t = texture(lettering, UV);
		if (t.a < 0.5) discard;
		base = t.rgb * t.rgb;
		rough = 0.4;
	} else if (k == 11) {
		vec4 t = texture(filete, UV);
		if (t.a < 0.5) discard;
		base = t.rgb;
		rough = 0.35;
	} else if (k == 12) {
		// the snow cap: patchy while the snow is thin, whole later
		// (drifts a few metres across, not spots: the wind lays it in from one side of the roof; at nightfall a few
		// patches, by the small hours all of it)
		float patch = texture(macro_tex, wpos.xz * 0.11).g * 0.7 + texture(macro_tex, wpos.xz * 0.31).g * 0.3;
		if (patch > (snow_amount - 0.22) * 2.2) discard;
		// (its edge and its skirt a little in shadow: a cushion of snow, rounded off)
		base = snow_color * (0.93 + 0.08 * n) * mix(0.8, 1.0, COLOR.r) * (1.0 - 0.1 * COLOR.g);
		rough = 0.8;
		spec = 0.35;
	} else if (k == 9) {
		// the route board: lit from behind on a bus in service
		rough = 0.5;
		emit = vec3(1.0, 0.92, 0.75) * lit * 0.9;
	} else if (k == 14 || k == 16) {
		// the inside, in the car's shade: the seats, the headlining, the steering wheel; the dashboard painted
		base = (k == 16 ? state.rgb * COLOR.r : base) * 0.55;
		rough = k == 16 ? 0.4 : 0.85;
		spec = 0.3;
		// (a colectivo in service: its inside lit warm by its ceiling lamps)
		emit = cabin_light * cabin * (COLOR.rgb * 2.6 + 0.09);
	} else if (k == 15) {
		// the number plate (its cell, then the car's own registration along the row)
		base = texture(filete, UV + vec2(plate * 0.125, 0.0)).rgb;
		rough = 0.4;
	}
	// wet and splashed low down (the slush thrown up off the road): darker, glossier, a grey-brown film
	float wet = 0.0;
	if (k <= 3 || k == 13) {
		wet = 1.0 - smoothstep(wet_height * 0.55, wet_height + 0.08 * n, lpos.y);
		base = mix(base, base * 0.55 + vec3(0.05, 0.045, 0.04) * (0.6 + 0.6 * n), wet * 0.8);
		rough = mix(rough, 0.18, wet * 0.7);
	}
	// snow on whatever faces up (the bonnet, the roof, the wings' crowns; not the bellied sides, their paint showing):
	// a parked car more than one in service
	float lie = smoothstep(0.6, 0.9, wnrm.y + (n - 0.5) * 0.3);
	float s = clamp(lie * clamp(snow_amount * 1.4 - 0.08, 0.0, 1.0) * (1.15 - 0.45 * lit) * ((k == 7 || k == 11 || k >= 14) ? 0.0 : (k == 13) ? 0.3 : (k == 4) ? 0.7 : 1.0), 0.0, 1.0);
	ALBEDO = mix(base, snow_color * (0.92 + 0.1 * n), s);
	ROUGHNESS = mix(rough, 0.8, s);
	METALLIC = metal * (1.0 - s);
	SPECULAR = mix(spec, 0.35, s);
	// the night round it in the chrome, the paint's lacquer and the glass (fresnel)
	float refl = (k == 2) ? 1.6 : (k <= 1 || k == 13) ? 0.18 : (k == 4) ? 0.5 : (k == 5 || k == 6 || k == 10) ? 0.3 : 0.0;
	if (k == 3) refl = 0.06 * wet;
	vec3 env = vehicle_env(NORMAL, VIEW, INV_VIEW_MATRIX, k == 2 ? 0.6 : 0.04, k == 2 ? base : vec3(1.0));
	EMISSION = emit * (1.0 - s) + env * refl * (1.0 - s) * (1.0 + 2.0 * wet * float(k != 2));
}
