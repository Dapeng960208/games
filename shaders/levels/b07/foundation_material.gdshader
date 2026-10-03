shader_type canvas_item;
render_mode unshaded;
void fragment() {
 // Reflect alternate native spans so opposite source edges never form a seam.
 float u = 1.0 - abs(fract(UV.x * 0.5) * 2.0 - 1.0);
 vec4 stone = texture(TEXTURE, vec2(u, clamp(UV.y, 0.0, 1.0)));
 // The exposed lower cliff recedes into existing canyon haze, not a cut slab.
 stone.a *= 1.0 - smoothstep(0.88, 1.0, UV.y);
 COLOR = stone;
}
