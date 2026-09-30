extends Node2D
## A room sibling so objective bodies share the actors' effective Z and foot sort.
## Ground markers stay on RoomObjectives, whose draw list is below the actors.
var objective_host: Node2D

func _init() -> void:
	z_index = 2
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(_delta: float) -> void:
	if not is_instance_valid(objective_host):
		queue_free()
		return
	objective_host.sync_body_layer()
