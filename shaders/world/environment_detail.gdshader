shader_type canvas_item;
render_mode unshaded;

// Native-resolution room repaints retain the authored normalized world mapping.
// Their short overlaps feather over the unchanged painting; this is not an
// upscaler and does not modify geometry, camera, props or collision.
uniform vec2 source_size;
uniform vec2 feather_width = vec2(16.0, 24.0);
uniform vec4 feather_edges;
uniform vec2 uv_origin = vec2(0.0);
uniform vec2 uv_extent = vec2(1.0);
varying vec4 authored_color;

void vertex() {
	authored_color = COLOR;
}

void fragment() {
	vec2 pixel = (UV - uv_origin) / uv_extent * source_size;
	float coverage = 1.0;
	if (feather_edges.x > 0.0) coverage *= smoothstep(0.0, feather_width.x, pixel.x);
	if (feather_edges.y > 0.0) coverage *= smoothstep(0.0, feather_width.y, pixel.y);
	if (feather_edges.z > 0.0) coverage *= smoothstep(0.0, feather_width.x, source_size.x - pixel.x);
	if (feather_edges.w > 0.0) coverage *= smoothstep(0.0, feather_width.y, source_size.y - pixel.y);
	COLOR = texture(TEXTURE, UV) * authored_color * vec4(1.0, 1.0, 1.0, coverage);
}
