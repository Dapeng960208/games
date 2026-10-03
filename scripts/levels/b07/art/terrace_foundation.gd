extends Node2D
## Authored cliff material on the exact platform's visible exterior faces.
## This is scenery only: no navigation, obstacles, damage, or artificial bridge.
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const MATERIAL = preload("res://shaders/levels/b07/foundation_material.gdshader")
var texture: Texture2D
var faces: Array[Dictionary]=[]
func configure(source: Texture2D, polygon_blueprint: PackedVector2Array, top_contact_y: float = 0.0, depth: float = 260.0) -> bool:
	if source==null or polygon_blueprint.size()<3 or not faces.is_empty() or depth<=0 or depth>500: return false
	var extrusion:=Vector2(0,depth)
	var size:=source.get_size()
	if top_contact_y<0 or top_contact_y>=size.y-1: return false
	texture=source
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat=CanvasItem.TEXTURE_REPEAT_DISABLED
	var stone:=ShaderMaterial.new()
	stone.shader=MATERIAL
	material=stone
	var material_height:=size.y-top_contact_y
	var tile_width:=depth*size.x/material_height
	var along:=0.0
	for index in polygon_blueprint.size():
		var a:=polygon_blueprint[index]
		var b:=polygon_blueprint[(index+1)%polygon_blueprint.size()]
		var edge:=b-a
		var u_start:=along/tile_width
		along+=edge.length()
		# A vertical western edge has no front-facing surface under a straight
		# screen-down extrusion; do not rotate the entire wall texture up it.
		if edge.cross(extrusion)>=0: continue
		var face:=PackedVector2Array([a,b,b+extrusion,a+extrusion])
		# Reject an inward or self-crossed face rather than covering walkable art.
		for overlap: PackedVector2Array in Geometry2D.intersect_polygons(face,polygon_blueprint):
			if Geometry.area(overlap)>.01: return false
		var uv:=PackedVector2Array([Vector2(u_start,top_contact_y/size.y),Vector2(along/tile_width,top_contact_y/size.y),Vector2(along/tile_width,1),Vector2(u_start,1)])
		for point in face.size(): face[point]*=Geometry.SCALE
		faces.append({"polygon":face,"uv":uv,"blueprint_edge":[a,b]})
	queue_redraw()
	return not faces.is_empty()
func _draw() -> void:
	if texture==null: return
	for face: Dictionary in faces:
		draw_polygon(face.polygon,PackedColorArray([Color.WHITE]),face.uv,texture)
