shader_type canvas_item;
render_mode unshaded;
uniform vec2 source_size = vec2(1536.0,1024.0);
uniform vec2 tile_extent = vec2(512.0,512.0);
uniform vec2 ground[16];
uniform int ground_count = 0;
uniform vec2 painted_floor[32];
uniform int floor_count = 0;
uniform vec4 gate_west;
uniform vec4 gate_east;

bool in_ground(vec2 p) {
 bool hit=false;
 for(int i=0;i<16;i++) { if(i>=ground_count)break; int j=(i+ground_count-1)%ground_count; vec2 a=ground[i]; vec2 b=ground[j];
  if((a.y>p.y)!=(b.y>p.y)) { if(p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) hit=!hit; }
 }
 return hit;
}
bool in_floor(vec2 p) {
 bool hit=false;
 for(int i=0;i<32;i++) { if(i>=floor_count)break; int j=(i+floor_count-1)%floor_count; vec2 a=painted_floor[i]; vec2 b=painted_floor[j];
  if((a.y>p.y)!=(b.y>p.y)) { if(p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) hit=!hit; }
 }
 return hit;
}
bool in_rect(vec2 p,vec4 r) { return p.x>=r.x && p.y>=r.y && p.x<=r.x+r.z && p.y<=r.y+r.w; }
void fragment() {
 vec2 p=UV*source_size;
 float opacity=0.0;
 if(ground_count>=3 && floor_count>=3 && !in_ground(p) && in_floor(p) && !in_rect(p,gate_west) && !in_rect(p,gate_east)) {
  float distance=10000.0;
  for(int i=0;i<16;i++) { if(i>=ground_count)break; int j=(i+1)%ground_count; vec2 a=ground[i];vec2 edge=ground[j]-a;float t=clamp(dot(p-a,edge)/max(dot(edge,edge),0.0001),0.0,1.0);distance=min(distance,length(p-a-t*edge)); }
  vec2 west_delta=max(max(gate_west.xy-p,p-(gate_west.xy+gate_west.zw)),vec2(0.0));
  vec2 east_delta=max(max(gate_east.xy-p,p-(gate_east.xy+gate_east.zw)),vec2(0.0));
  distance=min(distance,min(length(west_delta),length(east_delta)));
  float outer_distance=10000.0;
  for(int i=0;i<32;i++) { if(i>=floor_count)break;int j=(i+1)%floor_count;vec2 a=painted_floor[i];vec2 e=painted_floor[j]-a;float t=clamp(dot(p-a,e)/max(dot(e,e),0.0001),0.0,1.0);outer_distance=min(outer_distance,length(p-a-t*e)); }
  vec3 leaf=texture(TEXTURE,UV*source_size/tile_extent).rgb;
  float leaf_edge=(1.0-smoothstep(0.2,0.75,dot(leaf,vec3(.2126,.7152,.0722))))*6.0;
  opacity=smoothstep(0.0,14.0,distance-leaf_edge)*smoothstep(0.0,3.0,outer_distance);
 }
 COLOR=texture(TEXTURE,UV*source_size/tile_extent)*vec4(1.0,1.0,1.0,opacity)*COLOR;
}
