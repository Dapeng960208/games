shader_type canvas_item;
render_mode unshaded;
uniform vec2 source_size=vec2(1536.0,1024.0);
uniform vec2 tile_extent=vec2(512.0,512.0);
uniform vec2 ground[16];
uniform int ground_count=0;
uniform vec4 repair_rect=vec4(205.0,680.0,1130.0,175.0);
uniform vec4 paint_clip_rect=vec4(205.0,680.0,1130.0,175.0);
uniform vec4 entrance_join_rect=vec4(0.0);
uniform vec4 repair_feather=vec4(0.0,32.0,0.0,0.0);
uniform vec4 south_portal;
uniform vec4 secondary_portal;
uniform bool fascia=false;
uniform bool unique_patch=false;
uniform float fascia_depth=28.0;
uniform bool fascia_all_edges=false;
uniform bool fascia_in_repair_region=false;
uniform float fascia_join_feather=24.0;
uniform sampler2D reference_painting : filter_linear_mipmap;
uniform bool match_reference_shading=false;
uniform vec2 reference_offset=vec2(0.0,-96.0);
uniform vec3 material_average=vec3(.85,.70,.45);
varying vec4 source_modulate;
void vertex(){source_modulate=COLOR;}
bool inside_ground(vec2 p){
 bool hit=false;
 for(int i=0;i<16;i++){if(i>=ground_count)break;int j=(i+ground_count-1)%ground_count;vec2 a=ground[i];vec2 b=ground[j];
  if((a.y>p.y)!=(b.y>p.y)){if(p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x)hit=!hit;}
 }return hit;
}
bool inside_rect(vec2 p,vec4 r){return p.x>=r.x&&p.y>=r.y&&p.x<=r.x+r.z&&p.y<=r.y+r.w;}
vec2 mirrored_repeat(vec2 p){return 1.0-abs(fract(p*.5)*2.0-1.0);}
void fragment(){
 vec2 p=UV*source_size;vec4 result=vec4(0.0);
 if(!fascia){
  if(inside_ground(p)&&inside_rect(p,repair_rect)&&inside_rect(p,paint_clip_rect)){
   result=texture(TEXTURE,unique_patch ? (p-repair_rect.xy)/repair_rect.zw : mirrored_repeat(p/tile_extent));
   float alpha=1.0;
   if(repair_feather.x>0.0)alpha*=smoothstep(0.0,repair_feather.x,p.x-paint_clip_rect.x);
   if(repair_feather.y>0.0)alpha*=smoothstep(0.0,repair_feather.y,p.y-paint_clip_rect.y);
   if(repair_feather.z>0.0)alpha*=smoothstep(0.0,repair_feather.z,paint_clip_rect.x+paint_clip_rect.z-p.x);
   if(repair_feather.w>0.0)alpha*=smoothstep(0.0,repair_feather.w,paint_clip_rect.y+paint_clip_rect.w-p.y);
   // A bounded flat entry inlay may continue beneath the repaired floor.
   // This never reveals the old raised roots along the rest of the edge.
   if(entrance_join_rect.z>0.0&&entrance_join_rect.w>32.0){
    float join_y=smoothstep(entrance_join_rect.y,entrance_join_rect.y+16.0,p.y)*(1.0-smoothstep(entrance_join_rect.y+entrance_join_rect.w-16.0,entrance_join_rect.y+entrance_join_rect.w,p.y));
    alpha*=mix(1.0,smoothstep(entrance_join_rect.x,entrance_join_rect.x+entrance_join_rect.z,p.x),join_y);
   }
   result.a*=alpha;
   if(match_reference_shading){
    vec3 reference=textureLod(reference_painting,clamp((p+reference_offset)/source_size,vec2(0.0),vec2(1.0)),4.0).rgb;
    result.rgb*=clamp(reference/max(material_average,vec3(.01)),vec3(.55),vec3(1.08));
   }
  }
 }else if(!inside_ground(p)&&!inside_rect(p,south_portal)&&!inside_rect(p,secondary_portal)){
  float distance=10000.0;float along=0.0;
  for(int i=0;i<16;i++){
   if(i>=ground_count)break;int j=(i+1)%ground_count;vec2 a=ground[i];vec2 b=ground[j];vec2 edge=b-a;
   if(!fascia_all_edges&&(a.y<700.0||b.y<700.0||abs(edge.x)<.01))continue;
   float projected=dot(p-a,edge)/max(dot(edge,edge),.001);
   // Do not draw a round material end-cap where a partial fascia meets
   // the untouched painted perimeter. Internal polygon joins remain covered.
   int previous=(i+ground_count-1)%ground_count;int next=(j+1)%ground_count;
   bool previous_active=fascia_all_edges||(ground[previous].y>=700.0&&a.y>=700.0&&abs(a.x-ground[previous].x)>=.01);
   bool next_active=fascia_all_edges||(b.y>=700.0&&ground[next].y>=700.0&&abs(ground[next].x-b.x)>=.01);
   if((projected<0.0&&!previous_active)||(projected>1.0&&!next_active))continue;
   float t=clamp(projected,0.0,1.0);
   vec2 nearest=a+t*edge;float candidate=length(p-nearest);
   if(candidate<distance){distance=candidate;along=dot(nearest,normalize(edge));}
  }
  vec4 region=vec4(repair_rect.xy-vec2(fascia_depth),repair_rect.zw+vec2(fascia_depth*2.0));
  if(distance<=fascia_depth&&(!fascia_in_repair_region||inside_rect(p,region))){
   float u=1.0-abs(fract(along/1024.0)*2.0-1.0);
   result=texture(TEXTURE,vec2(u,(449.0+distance/fascia_depth*159.0)/1024.0));
   result.a=result.a>.125?1.0:(result.a<.01?0.0:result.a);
   if(fascia_in_repair_region&&fascia_join_feather>0.0){
    float join_distance=min(min(p.x-region.x,region.x+region.z-p.x),min(p.y-region.y,region.y+region.w-p.y));
    result.a*=smoothstep(0.0,fascia_join_feather,join_distance);
   }
  }
 }
 COLOR=result*source_modulate;
}
