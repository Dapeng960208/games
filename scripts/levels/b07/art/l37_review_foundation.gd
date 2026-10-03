extends "res://scripts/levels/b07/art/terrace_foundation.gd"
## Review-only cliff projection. The original ground contact is authoritative;
## the oblique exterior wall introduces no floor, collider or navigation point.
const REVIEW_EXTRUSION := Vector2(-140,260)
func configure(source: Texture2D, polygon_blueprint: PackedVector2Array, top_contact_y: float = 0.0, depth: float = 260.0) -> bool:
	if source == null or polygon_blueprint.size()<3 or not faces.is_empty() or not is_equal_approx(depth,260): return false
	var size := source.get_size()
	if top_contact_y<0 or top_contact_y>=size.y-1: return false
	texture=source
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat=CanvasItem.TEXTURE_REPEAT_DISABLED
	var stone := ShaderMaterial.new()
	stone.shader=MATERIAL
	material=stone
	var tile_width := REVIEW_EXTRUSION.length()*size.x/(size.y-top_contact_y)
	var along := 0.0
	for index in polygon_blueprint.size():
		var a := polygon_blueprint[index]
		var b := polygon_blueprint[(index+1)%polygon_blueprint.size()]
		var edge := b-a
		var u_start := along/tile_width
		along+=edge.length()
		if edge.cross(REVIEW_EXTRUSION)>=0: continue
		var face := PackedVector2Array([a,b,b+REVIEW_EXTRUSION,a+REVIEW_EXTRUSION])
		for overlap: PackedVector2Array in Geometry2D.intersect_polygons(face,polygon_blueprint):
			if Geometry.area(overlap)>.01: return false
		var uv := PackedVector2Array([Vector2(u_start,top_contact_y/size.y),Vector2(along/tile_width,top_contact_y/size.y),Vector2(along/tile_width,1),Vector2(u_start,1)])
		for point in face.size(): face[point]*=Geometry.SCALE
		faces.append({"polygon":face,"uv":uv,"blueprint_edge":[a,b]})
	queue_redraw()
	return not faces.is_empty()
