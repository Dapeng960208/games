extends Node2D
## Calm daylight courtyard. The ground is a single softly textured surface;
## lush details and ruin columns live along the arena's real outer boundary.

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const Art = preload("res://scripts/world/world_art.gd")
const FLOOR_TEXTURE_PATH := Art.FLOOR_PATH
const FLOOR_WORLD_SCALE := 0.34
const FLOOR_DEPTH_SCALE := 0.80
const FLOOR_TILE_WORLD_SIZE := Vector2(426.0,340.8)

var arena := Rect2(48, 106, 2704, 1588)
var biome: String = "B01"
var world_seed: int = 41827
var palette: Dictionary = {}
var floor_texture: Texture2D

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_floor_texture()
	_update_palette()
	queue_redraw()

func _load_floor_texture() -> void:
	floor_texture = Art.floor_texture_for(biome)

func configure(world_arena: Rect2, biome_id: String = "B01", seed_value: int = 41827) -> void:
	arena = world_arena
	biome = biome_id
	world_seed = seed_value
	_load_floor_texture()
	_update_palette()
	queue_redraw()

func _update_palette() -> void:
	palette = Art.palette(biome)

func _draw() -> void:
	if palette.is_empty():
		_update_palette()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	# Soft teal water and greenery extend beyond the walkable courtyard, so
	# camera edges never reveal the old black cave vignette.
	draw_rect(arena.grow(720.0), palette.water.lightened(0.19))
	_draw_platform()
	draw_rect(arena, palette.ground)
	_draw_floor()
	_draw_inlaid_compass(arena.get_center(), 66.0)
	_draw_boundary(rng)
	_draw_exterior(rng)

func _draw_platform() -> void:
	# The walkable coordinates remain the upper platform. Its forward/right
	# stone faces are visible outside that boundary, making height explicit
	# without projecting or moving any actor or collision rectangle.
	var depth := Vector2(0,68.0)
	var forward := PackedVector2Array([Vector2(arena.position.x,arena.end.y),arena.end,arena.end+depth,Vector2(arena.position.x,arena.end.y)+depth])
	draw_colored_polygon(forward,palette.stone_side)
	var right := PackedVector2Array([Vector2(arena.end.x,arena.position.y),arena.end,arena.end+Vector2(23,68),Vector2(arena.end.x+23,arena.position.y+68)])
	draw_colored_polygon(right,palette.stone_side.darkened(0.12))
	draw_line(Vector2(arena.position.x,arena.end.y+68),arena.end+Vector2(23,68),Color(palette.shadow,0.35),4.0,true)
	for row: int in range(2):
		var y: float = arena.end.y+10+row*30
		draw_line(Vector2(arena.position.x,y),Vector2(arena.end.x,y),Color(palette.seam,0.58),1.8,true)
		for x: int in range(int(arena.position.x+36+row*48),int(arena.end.x),98):
			draw_line(Vector2(x,y),Vector2(x,y+28),Color(palette.seam,0.50),1.5,true)

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

func _draw_inlaid_compass(at: Vector2, radius: float) -> void:
	# A faded, flush compass is scenery, with no glow or pickup silhouette.
	draw_set_transform(at,0,Vector2(1.0,0.76))
	at = Vector2.ZERO
	draw_arc(at, radius, 0, TAU, 56, Color(palette.seam, 0.25), 2.0, true)
	draw_arc(at, radius - 9, 0, TAU, 56, Color(palette.seam, 0.18), 1.3, true)
	for axis: int in range(4):
		var direction := Vector2.from_angle(axis * PI * 0.5 - PI * 0.5)
		var side := direction.orthogonal()
		var tip: Vector2 = at + direction * (radius - 14)
		var center: Vector2 = at + direction * 9
		draw_colored_polygon(PackedVector2Array([at, center + side * 10, tip]), Color(palette.seam, 0.20))
		draw_colored_polygon(PackedVector2Array([at, tip, center - side * 10]), Color(palette.stone_side, 0.12))
	draw_set_transform(Vector2.ZERO)

func _draw_boundary(rng: RandomNumberGenerator) -> void:
	# This eight-unit stone coping follows the actual actor boundary exactly.
	# Foliage has no collision and stays out of central combat and routes.
	draw_rect(arena.grow(5.0), palette.stone_side, false, 10.0)
	draw_rect(arena, palette.stone, false, 6.0)
	draw_rect(arena.grow(-4.0), Color(palette.seam, 0.44), false, 1.5)
	for x: int in range(int(arena.position.x + 70), int(arena.end.x - 50), 160):
		_draw_edge_garden(Vector2(x, arena.position.y + 3), Vector2.DOWN, rng)
		_draw_edge_garden(Vector2(x + 54, arena.end.y - 3), Vector2.UP, rng)
	for y: int in range(int(arena.position.y + 90), int(arena.end.y - 60), 180):
		_draw_edge_garden(Vector2(arena.position.x + 3, y), Vector2.RIGHT, rng)
		_draw_edge_garden(Vector2(arena.end.x - 3, y + 43), Vector2.LEFT, rng)

func _draw_edge_garden(at: Vector2, inward: Vector2, rng: RandomNumberGenerator) -> void:
	var across: Vector2 = inward.orthogonal()
	for index: int in range(rng.randi_range(3, 6)):
		var center: Vector2 = at + across * rng.randf_range(-28, 28) - inward * rng.randf_range(0, 13)
		var radius: float = rng.randf_range(4, 10)
		draw_circle(center, radius, palette.foliage)
		draw_circle(center + Vector2(-2, -2), radius * 0.66, palette.leaf)
		if index % 3 == 0:
			var blossom: Vector2 = center - Vector2(0, radius * 0.34)
			for petal: int in range(5):
				draw_circle(blossom + Vector2.from_angle(petal * TAU / 5.0) * 2.8, 2.3, palette.stone.lightened(0.08))
			draw_circle(blossom, 1.6, palette.gold)

func _draw_exterior(rng: RandomNumberGenerator) -> void:
	# Tall masonry is rendered by RaisedScenery, sorting at each true base.
	# Its shadows stay on this ground plane and do not cover warning telegraphs.
	for side: int in range(4):
		var length: float = arena.size.x if side<2 else arena.size.y
		var count: int = maxi(3,floori(length/420.0))
		for index: int in range(count):
			var progress: float = (float(index)+0.5)/float(count)
			var at: Vector2
			match side:
				0: at = Vector2(lerpf(arena.position.x,arena.end.x,progress),arena.position.y-36)
				1: at = Vector2(lerpf(arena.position.x,arena.end.x,progress),arena.end.y+86)
				2: at = Vector2(arena.position.x-82,lerpf(arena.position.y,arena.end.y,progress))
				_: at = Vector2(arena.end.x+82,lerpf(arena.position.y,arena.end.y,progress))
			var height: float = 160.0 if index%2==0 else 80.0
			var footprint := Rect2(at-Vector2(34,16),Vector2(68,32))
			preload("res://scripts/world/room_appearance.gd")._draw_cast_shadow(self,footprint,height,biome)
	for index: int in range(38):
		var edge: int = index % 4
		var progress: float = rng.randf()
		var at: Vector2
		match edge:
			0: at = Vector2(lerpf(arena.position.x, arena.end.x, progress), arena.position.y - rng.randf_range(54, 180))
			1: at = Vector2(lerpf(arena.position.x, arena.end.x, progress), arena.end.y + rng.randf_range(68, 180))
			2: at = Vector2(arena.position.x - rng.randf_range(70, 180), lerpf(arena.position.y, arena.end.y, progress))
			_: at = Vector2(arena.end.x + rng.randf_range(70, 180), lerpf(arena.position.y, arena.end.y, progress))
		draw_circle(at, rng.randf_range(18, 40), Color(palette.foliage, 0.38))
		draw_arc(at + Vector2(12, 11), rng.randf_range(20, 30), 0.05, PI * 0.95, 16, Color(palette.leaf, 0.20), 2.0, true)
