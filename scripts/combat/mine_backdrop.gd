extends Node2D
## Fixed painted chunks join the combat ground to its complete landscape.
## The original painting and common world transform keep all seams coherent.

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const Art = preload("res://scripts/world/world_art.gd")
const Chunks = preload("res://scripts/world/environment_chunks.gd")
const FLOOR_TEXTURE_PATH := Art.FLOOR_PATH
const FLOOR_WORLD_SCALE := 0.34
const FLOOR_DEPTH_SCALE := 0.80
const FLOOR_TILE_WORLD_SIZE := Vector2(426.0,340.8)

var arena := Rect2(48, 106, 2704, 1588)
var biome: String = "B01"
var blueprint_room_id: String = ""
var world_seed: int = 41827
var palette: Dictionary = {}
var floor_texture: Texture2D
var perimeter_layout: Dictionary = {}
var environment_texture: Texture2D
var environment_world_rect := Rect2()
var environment_chunks: Node2D
var ground_composition: Node2D

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_environment()
	_update_palette()
	queue_redraw()

func _load_floor_texture() -> void:
	floor_texture = Art.floor_texture_for(biome)

func _load_environment() -> void:
	environment_texture = Art.environment_texture_for(biome,blueprint_room_id)
	environment_world_rect = Art.environment_world_rect(arena,biome,blueprint_room_id)
	if not is_instance_valid(environment_chunks):
		environment_chunks = Chunks.new()
		environment_chunks.name = "EnvironmentChunks"
		add_child(environment_chunks)
	environment_chunks.configure(environment_texture,environment_world_rect,blueprint_room_id)
	if environment_texture==null: _load_floor_texture()

func configure(world_arena: Rect2, biome_id: String = "B01", seed_value: int = 41827, room_id: String = "") -> void:
	arena = world_arena
	biome = biome_id
	blueprint_room_id = room_id
	world_seed = seed_value
	perimeter_layout = {"arena":arena,"entry":Vector2(arena.position.x+180,arena.get_center().y),"exit":Vector2(arena.end.x-180,arena.get_center().y)}
	_load_environment()
	_update_palette()
	queue_redraw()

func configure_layout(layout: Dictionary) -> void:
	perimeter_layout = layout.duplicate(false)
	blueprint_room_id = Art.environment_room_id(layout)
	# The painting follows compact blueprint coordinates, even when the room's
	# physical bounding box expands slightly to a natural curved walkable edge.
	arena = layout.get("arena",arena)
	_load_environment()
	if not is_instance_valid(ground_composition):
		ground_composition = preload("res://scripts/world/room_ground_composition.gd").new()
		ground_composition.name = "RoomGroundComposition"
		ground_composition.z_index = 1
		add_child(ground_composition)
	ground_composition.configure(layout,biome)
	queue_redraw()

func _update_palette() -> void:
	palette = Art.palette(biome)

func _draw() -> void:
	if environment_texture!=null and environment_world_rect.has_area():
		# Six Sprite2D regions submit the continuous painting. Visibility culling
		# operates per chunk; all six still share one resident mother texture.
		return
	if palette.is_empty():
		_update_palette()
	draw_rect(arena, palette.ground)
	_draw_floor()

func _draw_floor() -> void:
	if floor_texture == null:
		return
	var definition: Dictionary = Art.floor_definition(biome)
	var parent: Texture2D = TextureSampler.sampled(str(definition.path))
	var native: Rect2 = definition.source
	# Individual panel UVs prevent adjacent faction surfaces leaking into the
	# floor. Explicit mirrored tiles also preserve the outer platform boundary.
	for y: int in range(ceili(arena.size.y/FLOOR_TILE_WORLD_SIZE.y)):
		for x: int in range(ceili(arena.size.x/FLOOR_TILE_WORLD_SIZE.x)):
			var tile := Rect2(arena.position+Vector2(x,y)*FLOOR_TILE_WORLD_SIZE,FLOOR_TILE_WORLD_SIZE)
			var clipped: Rect2 = tile.intersection(arena)
			var fraction: Vector2 = clipped.size/FLOOR_TILE_WORLD_SIZE
			var source := Rect2(native.position,native.size*fraction)
			var origin: Vector2 = clipped.position
			var reflection := Vector2.ONE
			if x%2==1:
				source.position.x = native.end.x-source.size.x
				origin.x += clipped.size.x
				reflection.x = -1
			if y%2==1:
				source.position.y = native.end.y-source.size.y
				origin.y += clipped.size.y
				reflection.y = -1
			# Texture regions require positive rectangles. A canvas reflection
			# mirrors both complete and final partial tiles without skipped rows.
			draw_set_transform(origin,0,reflection)
			draw_texture_rect_region(parent,Rect2(Vector2.ZERO,clipped.size),source,Color.WHITE,false,true)
	draw_set_transform(Vector2.ZERO)
