extends Node2D
## Original ImageGen floor repeated at native world-pixel size, with restrained
## flush decals. Room-owned obstacles are the only solid props.

const FLOOR_TEXTURE_PATH := "res://assets/generated/world/B01_floor_v1.png"

var arena := Rect2(48, 106, 2704, 1588)
var biome: String = "B01"
var world_seed: int = 41827
var palette: Dictionary = {}
var floor_texture: Texture2D

func _ready() -> void:
	# Mirror repeat joins identical source-edge pixels; the authored native-scale
	# mineral surface stays continuous without visible vertical tile cuts.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	_load_floor_texture()
	_update_palette()
	queue_redraw()

func _load_floor_texture() -> void:
	var path: String = "res://assets/generated/world/"+biome+"_floor_v1.png"
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		path = FLOOR_TEXTURE_PATH
	if ResourceLoader.exists(path):
		floor_texture = load(path)
	elif FileAccess.file_exists(path):
		# New authored source images can be previewed before the editor's next
		# import pass. This reads the same original PNG at its native dimensions.
		var source_image: Image = Image.load_from_file(path)
		if not source_image.is_empty():
			source_image.generate_mipmaps()
			floor_texture = ImageTexture.create_from_image(source_image)

func configure(world_arena: Rect2, biome_id: String = "B01", seed_value: int = 41827) -> void:
	arena = world_arena
	biome = biome_id
	world_seed = seed_value
	_load_floor_texture()
	_update_palette()
	queue_redraw()

func _update_palette() -> void:
	match biome:
		"B02":
			palette = {"base":Color("14211f"), "tile":Color("192925"), "seam":Color("0f1919"), "metal":Color("344740"), "accent":Color("a9ba69"), "light":Color("85d6ba")}
		"B03":
			palette = {"base":Color("171e29"), "tile":Color("202b39"), "seam":Color("111a24"), "metal":Color("3e5265"), "accent":Color("91adcb"), "light":Color("a3dbed")}
		"B04":
			palette = {"base":Color("241b21"), "tile":Color("30252c"), "seam":Color("1c141d"), "metal":Color("514147"), "accent":Color("c18778"), "light":Color("cfabcf")}
		_:
			palette = {"base":Color("141e27"), "tile":Color("1a2730"), "seam":Color("101920"), "metal":Color("3a474e"), "accent":Color("bb8855"), "light":Color("77c7d0")}

func _draw() -> void:
	if palette.is_empty():
		_update_palette()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var base: Color = palette.base
	var accent: Color = palette.accent
	draw_rect(arena.grow(160.0), base.darkened(0.55))
	draw_rect(arena, base)
	_draw_floor(rng)
	_draw_inlaid_tracks()
	_draw_surface_marks(rng)
	# Boundary exactly matches the arena used by actor collision.
	draw_rect(arena.grow(-3.0), palette.metal, false, 6.0)
	draw_rect(arena.grow(-9.0), Color(accent, 0.36), false, 1.0)
	for x in range(int(arena.position.x + 40), int(arena.end.x - 30), 80):
		_rivet(Vector2(x, arena.position.y + 4))
		_rivet(Vector2(x, arena.end.y - 4))
	for y in range(int(arena.position.y + 40), int(arena.end.y - 30), 80):
		_rivet(Vector2(arena.position.x + 4, y))
		_rivet(Vector2(arena.end.x - 4, y))
	_draw_edge_lamps()
	# Exterior rock stays outside the collision boundary.
	_draw_exterior(rng)

func _draw_floor(rng: RandomNumberGenerator) -> void:
	if floor_texture != null:
		# tile=true repeats the 1254x1254 image at 1 image pixel : 1 world unit;
		# increasing a room's extent reveals more repeats instead of larger stones.
		var tint := Color(0.82, 0.82, 0.80, 1.0)
		match biome:
			"B02": tint = Color(0.72, 0.82, 0.73, 1.0)
			"B03": tint = Color(0.77, 0.82, 0.9, 1.0)
			"B04": tint = Color(0.86, 0.73, 0.78, 1.0)
		# Preserve the original rust hue while reducing high-frequency stone
		# contrast beneath characters, enemies, pickups, and attack warnings.
		tint = tint.darkened(0.24)
		draw_texture_rect(floor_texture, arena, true, tint)
		# A thin ambient veil keeps bright loot and red warnings above floor detail.
		draw_rect(arena, Color(palette.base, 0.13))
	else:
		# A quiet irregular fallback if an image import is unavailable; no grid.
		for i in range(int(arena.get_area() / 23000.0)):
			var center := Vector2(rng.randf_range(arena.position.x + 60, arena.end.x - 60), rng.randf_range(arena.position.y + 60, arena.end.y - 60))
			var polygon := PackedVector2Array()
			for side in range(7):
				var point: Vector2 = center + Vector2.RIGHT.rotated(side * TAU / 7.0) * rng.randf_range(18, 53)
				polygon.append(point)
			draw_colored_polygon(polygon, Color(palette.tile, rng.randf_range(0.3, 0.65)))

func _draw_inlaid_tracks() -> void:
	var metal: Color = palette.metal
	var accent: Color = palette.accent
	# Rails sit flush in the floor; actors and projectiles pass over them.
	for y in [arena.position.y + 46.0, arena.end.y - 46.0]:
		for x in range(int(arena.position.x + 30), int(arena.end.x - 25), 28):
			draw_line(Vector2(x, y - 10), Vector2(x, y + 10), Color(metal, 0.33), 5)
		for offset in [-6.0, 6.0]:
			draw_line(Vector2(arena.position.x + 22, y + offset), Vector2(arena.end.x - 22, y + offset), metal.darkened(0.1), 2)
			draw_line(Vector2(arena.position.x + 22, y + offset - 1), Vector2(arena.end.x - 22, y + offset - 1), Color(accent, 0.22), 1)
	# A few buried track fragments, with no continuous lanes or square floor grid.
	for fraction in [Vector2(0.19, 0.27), Vector2(0.56, 0.68), Vector2(0.82, 0.38)]:
		var start: Vector2 = arena.position + arena.size * fraction
		var direction := Vector2(1.0, 0.26).normalized()
		var across := Vector2(-direction.y, direction.x)
		for side in [-1.0, 1.0]:
			var rail: Vector2 = start + across * side * 9
			draw_line(rail, rail + direction * 156, Color(metal, 0.42), 3)
			draw_line(rail, rail + direction * 156, Color(accent, 0.15), 1)
		for tie in range(5):
			var p: Vector2 = start + direction * (tie * 30 + 16)
			draw_line(p - across * 14, p + across * 14, Color(metal, 0.27), 3)

func _draw_surface_marks(rng: RandomNumberGenerator) -> void:
	var count: int = int(arena.get_area() / 47000.0)
	for i in range(count):
		var p := Vector2(rng.randf_range(arena.position.x + 80, arena.end.x - 80), rng.randf_range(arena.position.y + 80, arena.end.y - 80))
		var angle: float = rng.randf_range(0, TAU)
		var direction := Vector2.RIGHT.rotated(angle)
		var length: float = rng.randf_range(9, 30)
		draw_line(p, p + direction * length, Color(palette.seam, 0.4), 2)
		if i % 5 == 0:
			draw_arc(p, 22, angle, angle + PI * 0.8, 15, Color(palette.metal, 0.17), 1)
		if i % 9 == 0:
			# Mineral flecks follow an irregular ground fissure, never an item glow.
			var ore_points := PackedVector2Array([p - direction * 15, p, p + direction * 11 + direction.orthogonal() * 4, p + direction * 28])
			draw_polyline(ore_points, Color(palette.accent, 0.2), 1)
		if biome == "B02" and i % 3 == 0:
			for j in range(3):
				draw_circle(p + direction.rotated(j * 1.7) * 7, 5, Color(palette.accent, 0.055))
		elif biome == "B03" and i % 3 == 0:
			draw_line(p, p + direction * 26, Color(palette.light, 0.08), 1)
			draw_line(p + direction * 13, p + direction * 13 + direction.rotated(0.8) * 12, Color(palette.light, 0.07), 1)
		elif biome == "B04" and i % 4 == 0:
			draw_arc(p, 12, 0, TAU, 16, Color(palette.accent, 0.09), 2)

func _rivet(p: Vector2) -> void:
	draw_circle(p, 2.3, palette.seam)
	draw_circle(p + Vector2(0, -0.7), 1.2, Color(palette.accent, 0.62))

func _draw_edge_lamps() -> void:
	for x in range(int(arena.position.x + 140), int(arena.end.x - 80), 360):
		_lamp(Vector2(x, arena.position.y + 12), false)
		_lamp(Vector2(x, arena.end.y - 12), false)
	for y in range(int(arena.position.y + 170), int(arena.end.y - 80), 360):
		_lamp(Vector2(arena.position.x + 12, y), true)
		_lamp(Vector2(arena.end.x - 12, y), true)

func _lamp(p: Vector2, vertical: bool) -> void:
	for radius in [36.0, 24.0, 14.0]:
		draw_circle(p, radius, Color(palette.light, 0.018))
	var size := Vector2(9, 22) if vertical else Vector2(22, 9)
	draw_rect(Rect2(p - size * 0.5, size), palette.seam)
	draw_rect(Rect2(p - size * 0.5 + Vector2(2, 2), size - Vector2(4, 4)), palette.accent)
	draw_rect(Rect2(p - size * 0.5 + Vector2(3, 3), size - Vector2(6, 6)), palette.light)

func _draw_exterior(rng: RandomNumberGenerator) -> void:
	for x in range(int(arena.position.x - 80), int(arena.end.x + 80), 88):
		_rock(Vector2(x, arena.position.y - 58), rng)
		_rock(Vector2(x + 24, arena.end.y + 58), rng)
	for y in range(int(arena.position.y + 32), int(arena.end.y), 88):
		_rock(Vector2(arena.position.x - 58, y), rng)
		_rock(Vector2(arena.end.x + 58, y + 20), rng)

func _rock(p: Vector2, rng: RandomNumberGenerator) -> void:
	var polygon := PackedVector2Array()
	for i in range(6):
		var radius: float = rng.randf_range(25, 44)
		polygon.append(p + Vector2.RIGHT.rotated(i * TAU / 6.0) * radius)
	draw_colored_polygon(polygon, palette.base.darkened(0.22))
	draw_polyline(PackedVector2Array([polygon[3], polygon[4], polygon[5], polygon[0]]), Color(palette.metal, 0.35), 2)
