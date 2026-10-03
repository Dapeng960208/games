shader_type canvas_item;
render_mode unshaded;
uniform vec2 scaled_blueprint_size;
uniform vec2 blueprint_crop;
uniform vec2 blueprint_origin;
uniform vec2 draw_area_size = vec2(2800.0,1800.0);
uniform bool exterior = false;
uniform vec2 ground[16];
uniform int ground_count = 0;
bool inside_ground(vec2 p) {
 bool hit = false;
 for (int i = 0; i < 16; i++) {
  if (i >= ground_count) break;
  int j = (i + ground_count - 1) % ground_count;
  vec2 a = ground[i]; vec2 b = ground[j];
  if ((a.y > p.y) != (b.y > p.y)) {
   if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) hit = !hit;
  }
 }
 return hit;
}
void fragment() {
 vec2 q = UV * scaled_blueprint_size - blueprint_crop;
 vec2 p = q + blueprint_origin;
 bool inside = inside_ground(p);
 if (q.x < 0.0 || q.y < 0.0 || q.x > draw_area_size.x || q.y > draw_area_size.y || inside == exterior) discard;
 COLOR = texture(TEXTURE, UV);
}
