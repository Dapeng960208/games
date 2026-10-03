shader_type canvas_item;
render_mode unshaded;

uniform vec2 ground[64];
uniform int ground_count = 0;
uniform vec4 room_rect;
uniform vec2 source_extent;
uniform float alpha_cutoff = 0.0;
varying vec2 room_point;

void vertex() {
	room_point = room_rect.xy + VERTEX / source_extent * room_rect.zw;
}

bool inside_ground(vec2 point) {
	bool inside = false;
	for (int i = 0; i < 64; i++) {
		if (i >= ground_count) break;
		int previous = (i + ground_count - 1) % ground_count;
		vec2 a = ground[i];
		vec2 b = ground[previous];
		if ((a.y > point.y) != (b.y > point.y)) {
			if (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
		}
	}
	return inside;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	if (alpha_cutoff > 0.0) source.a *= smoothstep(alpha_cutoff - 0.04, alpha_cutoff + 0.04, source.a);
	if (inside_ground(room_point)) source.a = 0.0;
	COLOR = source;
}
