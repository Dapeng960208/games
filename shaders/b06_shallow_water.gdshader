shader_type canvas_item;
render_mode unshaded;
uniform vec4 patch_rect;
uniform float wet_opacity = 0.48;
uniform float edge_width = 5.0;
varying vec2 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
 vec2 inner = min(local_point - patch_rect.xy, patch_rect.xy + patch_rect.zw - local_point);
 float edge = smoothstep(0.0, edge_width, min(inner.x, inner.y));
 vec4 water = texture(TEXTURE, UV);
 COLOR = vec4(water.rgb, water.a * wet_opacity * mix(0.12, 1.0, edge));
}
