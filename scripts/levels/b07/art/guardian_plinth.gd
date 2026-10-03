extends Node2D
## Separate decorative support under the western guardian's measured base.
## All four corners stay outside L37's floor; this is not an accessible platform.
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const CORNERS := [Vector2(-745,1260),Vector2(-390,1150),Vector2(-25,1275),Vector2(-400,1425)]
var surface: Texture2D
var polygon:=PackedVector2Array()
var uv:=PackedVector2Array()
var foundation: Node2D
func configure(floor_texture: Texture2D, wall_texture: Texture2D) -> bool:
	if floor_texture==null or wall_texture==null or not polygon.is_empty(): return false
	var blueprint:=PackedVector2Array(CORNERS)
	var walkable:=PackedVector2Array()
	for p: Array in Geometry.room("L37").walkable_polygon: walkable.append(Vector2(p[0],p[1]))
	for overlap: PackedVector2Array in Geometry2D.intersect_polygons(blueprint,walkable):
		if Geometry.area(overlap)>.01: return false
	surface=floor_texture
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for point: Vector2 in blueprint:
		polygon.append(point*Geometry.SCALE)
		uv.append((point+Vector2(900,0))/Vector2(2800,1800))
	foundation=preload("res://scripts/levels/b07/art/terrace_foundation.gd").new()
	add_child(foundation)
	foundation.z_index=-1
	if not foundation.configure(wall_texture,blueprint,0,440): return false
	queue_redraw()
	return true
func _draw() -> void:
	if surface!=null: draw_polygon(polygon,PackedColorArray([Color.WHITE]),uv,surface)
