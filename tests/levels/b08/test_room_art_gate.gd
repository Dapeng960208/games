extends Node
const Mapping=preload("res://scripts/levels/b08/presentation/room_art_mapping.gd")
func _ready() -> void:
	var mapping=Mapping.new()
	var valid: bool=mapping.configure("L43",Rect2(0,0,1624,1044))
	var rejected: bool=not valid and mapping.errors==["Missing independent room painting"]
	# Failed staging PNGs are never optional fallback art or approved geometry.
	var unchanged: bool=not Mapping.requested("L44")
	print("B08_ROOM_ART_GATE checks=2 failures=",0 if rejected and unchanged else 1)
	get_tree().quit(0 if rejected and unchanged else 1)
