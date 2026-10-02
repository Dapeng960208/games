shader_type canvas_item;
render_mode unshaded;

// The room painting is enlarged at fullscreen. Reconstruct source edges with
// Catmull-Rom interpolation instead of blurring them with bilinear sampling.
// All regions sample the full shared texture, so their joins remain continuous.
varying vec4 authored_color;

void vertex() {
	authored_color = COLOR;
}

vec4 cubic_weights(float f) {
	float f2 = f * f;
	float f3 = f2 * f;
	return vec4(-0.5 * f + f2 - 0.5 * f3,
		1.0 - 2.5 * f2 + 1.5 * f3,
		0.5 * f + 2.0 * f2 - 1.5 * f3,
		-0.5 * f2 + 0.5 * f3);
}

vec4 enlarged_painting(sampler2D painting_texture, vec2 uv, vec2 texel) {
	vec2 pixel = uv / texel - 0.5;
	vec2 base = floor(pixel);
	vec4 wx = cubic_weights(fract(pixel.x));
	vec4 wy = cubic_weights(fract(pixel.y));
	vec2 middle_weight = vec2(wx.y + wx.z, wy.y + wy.z);
	vec2 middle = base + vec2(wx.z, wy.z) / middle_weight;
	vec3 x = vec3(base.x - 1.0, middle.x, base.x + 2.0) + 0.5;
	vec3 y = vec3(base.y - 1.0, middle.y, base.y + 2.0) + 0.5;
	vec3 weight_x = vec3(wx.x, middle_weight.x, wx.w);
	vec3 weight_y = vec3(wy.x, middle_weight.y, wy.w);
	// Combine the two positive middle weights through hardware linear sampling:
	// nine reads reconstruct the same sixteen-tap cubic neighborhood.
	vec4 result = vec4(0.0);
	for (int row = 0; row < 3; row++) {
		for (int column = 0; column < 3; column++) {
			result += textureLod(painting_texture, vec2(x[column], y[row]) * texel, 0.0)
				* weight_x[column] * weight_y[row];
		}
	}
	return clamp(result, vec4(0.0), vec4(1.0));
}

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float footprint = max(length(dFdx(pixel)), length(dFdy(pixel)));
	vec4 painting = texture(TEXTURE, UV);
	// Keep mipmapped antialiasing in room overviews and blend smoothly near 1:1.
	// Reconstruction is used only when the image is enlarged on screen.
	if (footprint < 1.0) {
		float reconstruction = 1.0 - smoothstep(0.75, 1.0, footprint);
		painting = mix(painting, enlarged_painting(TEXTURE, UV, TEXTURE_PIXEL_SIZE), reconstruction);
	}
	COLOR = painting * authored_color;
}
