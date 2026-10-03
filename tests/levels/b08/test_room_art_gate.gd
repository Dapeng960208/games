extends Node
const Mapping=preload("res://scripts/levels/b08/presentation/room_art_mapping.gd")
const Art=preload("res://scripts/infrastructure/assets/world_art.gd")
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 room painting gate: "+label)
func _ready() -> void:
	var mapping:=Mapping.new()
	check(Mapping.requested("L43") and not Mapping.requested("L44"),"explicit first-room-only candidate gate")
	var valid: bool=mapping.configure("L43",Rect2(0,0,1624,1044))
	check(valid and mapping.errors.is_empty(),"registered derived painting and boundary share one contract")
	if not valid: finish(); return
	check(mapping.definition.path=="asset://world/rooms/L43_environment_v1.png","independent room source resolves through catalog")
	check(mapping.definition.texture.get_size()==Vector2(1536,1024),"actual mother source dimensions")
	check(mapping.floor.segment_clear(Vector2(540,340),Vector2(1100,340),40),"complete 560-unit radius40 bypass")
	check(mapping.floor.holes.size()==1 and not mapping.floor.contains(Vector2(812,400)),"complete central cloud hole is excluded")
	check(mapping.floor.contains(Vector2(70,500),18) and not Geometry.contains("L43",Vector2(70,500),18),"new painted outline does not mutate original debug floor")
	check(Geometry.floors("L43").size()==6 and Geometry.lanes("L43")[0].rect==Geometry.rect([880,325,1150,220]),"legacy floor and real wind lane stay unchanged")
	var entry:=Geometry.point(Geometry.ENTRY.L43)
	check(mapping.point_from_source(mapping.source_from_world(entry)).distance_to(entry)<.001,"entry round-trip shares WorldArt transform")
	var original: Dictionary=Art._environments["B08:L43"]
	var moved: Dictionary=original.duplicate(true)
	moved.metadata.walkable_normalized_holes[0][0][1]-=.002
	Art._environments["B08:L43"]=moved
	var rejected:=Mapping.new()
	check(not rejected.configure("L43",Rect2(0,0,1624,1044)) and "Original cloud hole moved" in rejected.errors and rejected.floor==null,"metadata cannot silently move preserved hole")
	Art._environments["B08:L43"]=original
	finish()
func finish() -> void:
	print("B08_ROOM_ART_GATE checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
