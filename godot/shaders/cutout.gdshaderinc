// A paper cut-out's silhouette (scripts/three_d/cutout.gd): the drawing, the ink outline round it and the paper rim
// beyond that, all taken from the drawing's alpha. Shared by the card itself and its two x-ray passes, so that all
// three agree on the figure's edge.
// UV runs 0..1 over the drawn part of the picture (its transparent margins trimmed), a little past it on every side
// for the outline and the rim.
uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 used = vec4(0.0, 0.0, 1.0, 1.0);   // the drawn rectangle of the picture, in its UV (x, y, w, h)
uniform vec2 outline_uv = vec2(0.04, 0.015);     // the ink outline's width, in card UV (a circle in metres)
uniform vec2 rim_uv = vec2(0.03, 0.011);         // the paper rim's width beyond it

instance uniform float flip = 0.0;               // 1: the drawing mirrored (he walks the other way)

vec2 card_uv(vec2 uv) {
	return vec2(flip > 0.5 ? 1.0 - uv.x : uv.x, uv.y);
}

vec4 art_at(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
	return texture(art, used.xy + uv * used.zw);
}

// The most of the drawing's alpha within `r` (card UV) of uv: twelve taps round a circle and four halfway.
float near_alpha(vec2 uv, vec2 r) {
	float a = 0.0;
	for (int i = 0; i < 12; i++) {
		float t = float(i) * 0.5235988;
		a = max(a, art_at(uv + vec2(cos(t), sin(t)) * r).a);
	}
	for (int i = 0; i < 4; i++) {
		float t = float(i) * 1.5707963 + 0.785398;
		a = max(a, art_at(uv + vec2(cos(t), sin(t)) * r * 0.5).a);
	}
	return a;
}

// x: the drawing's own alpha, y: the outline's (drawing and ink), z: the whole card's (drawing, ink and paper rim).
vec3 silhouette(vec2 uv) {
	float a = art_at(uv).a;
	float o = max(a, near_alpha(uv, outline_uv));
	float r = max(o, near_alpha(uv, outline_uv + rim_uv));
	return vec3(a, o, r);
}
