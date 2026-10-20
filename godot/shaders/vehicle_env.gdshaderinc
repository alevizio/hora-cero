// The night round a vehicle as its chrome, its lacquer and its glass reflect it (plaza_vehicle.gdshader,
// plaza_vehicle_glass.gdshader): there are no reflection probes in the web build, so this is a small made-up sky. Above,
// the dark of the snowing sky; along the horizon the warm glow of the street lamps and the lit windows, brightest in a
// thin line (the line along a chrome bumper or a wing); below, the snow on the street lit by the lamps.
// `n`, `v`: the normal and the view direction (view space); `f0` the reflectance looking straight on (metal: high);
// `tint` the metal's own colour (white for lacquer and glass). Added as light (EMISSION).
uniform vec3 env_sky : source_color = vec3(0.07, 0.075, 0.11);
uniform vec3 env_horizon : source_color = vec3(0.55, 0.45, 0.34);
uniform vec3 env_ground : source_color = vec3(0.20, 0.20, 0.235);
uniform float env_strength = 0.6;

vec3 vehicle_env(vec3 n, vec3 v, mat4 inv_view, float f0, vec3 tint) {
	vec3 r = (inv_view * vec4(reflect(-v, n), 0.0)).xyz;
	float up = r.y;
	vec3 sky = mix(env_horizon * 0.45, env_sky, smoothstep(0.02, 0.45, up));
	vec3 below = mix(env_horizon * 0.3, env_ground, smoothstep(-0.02, -0.3, up));
	vec3 c = up > 0.0 ? sky : below;
	c += env_horizon * exp(-abs(up - 0.03) * 38.0) * 0.9;
	float f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	return c * tint * f * env_strength;
}
