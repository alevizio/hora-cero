shader_type spatial;
// A cloth flag waving from its pole (the Plaza de Mayo kit): a grid laid flat along local +X from the hoist (UV.x 0)
// to the fly (UV.x 1), UV.y from the top. Waves run out along it, bigger toward the fly, the cloth a little heavy with
// the wet night; the picture is a rectangle of the kit's atlas ("rect": x, y, w, h in UV).
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fly = 2.4;
uniform float wind = 1.0;
uniform float speed = 1.0;
uniform float phase = 0.0;

void vertex() {
	float u = UV.x;
	float t = TIME * speed + phase;
	float k = 6.2 / fly;
	float ph = VERTEX.x * k - t * 3.4 + UV.y * 0.9;
	float amp = u * fly * (0.07 + 0.025 * sin(t * 0.6)) * wind;
	float w1 = sin(ph);
	float w2 = sin(VERTEX.x * k * 2.1 - t * 5.3 + UV.y * 2.0);
	VERTEX.z += w1 * amp + w2 * amp * 0.25;
	// the cloth hangs a little and its fly end draws in as it waves
	VERTEX.y -= u * u * fly * 0.08 * (1.3 - wind * 0.5);
	VERTEX.x -= u * fly * 0.03 * (1.0 + w1);
	float dz = (cos(ph) * k * amp + cos(VERTEX.x * k * 2.1 - t * 5.3 + UV.y * 2.0) * k * 2.1 * amp * 0.25);
	NORMAL = normalize(vec3(-dz, 0.0, 1.0));
	UV = rect.xy + UV * rect.zw;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * (FRONT_FACING ? 1.0 : 0.85);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = c.rgb * 0.25;
}
