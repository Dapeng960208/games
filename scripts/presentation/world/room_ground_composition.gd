extends Node2D
## Fixed ground-plane composition above the painting, below actors and danger
## telegraphs. No update loop, collision, random placement or gameplay state.
const Presentation = preload("res://scripts/presentation/world/room_presentation.gd")
const Details = preload("res://scripts/presentation/world/room_ground_details.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
var layout: Dictionary = {}
var design: Dictionary = {}
var biome := "B01"
var ground := PackedVector2Array()
var composition: Dictionary = {}

func configure(next_layout: Dictionary, biome_id: String) -> void:
	layout = next_layout
	design = Presentation.for_layout(layout)
	biome = biome_id
	if design.is_empty():
		hide()
		return
	show()
	# Independent room paintings carry the scene composition. Keep the extra
	# route/apron details quiet so they do not wash out the painted floor.
	var environment: Dictionary = Art.environment_definition(biome,Art.environment_room_id(layout))
	self_modulate = Color(1,1,1,.38 if bool(environment.get("room_specific",false)) else 1.0)
	ground = Art.environment_ground_polygon(layout.arena,biome,Art.environment_room_id(layout))
	if ground.is_empty():
		var arena: Rect2 = layout.arena
		ground = PackedVector2Array([arena.position,Vector2(arena.end.x,arena.position.y),arena.end,Vector2(arena.position.x,arena.end.y)])
	composition = Details.build(layout,design,biome,ground)
	queue_redraw()

func _draw() -> void:
	if design.is_empty() or composition.is_empty(): return
	Details.draw(self,composition,biome)
