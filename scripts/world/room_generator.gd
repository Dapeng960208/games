class_name RoomGenerator
extends RefCounted
## Seeded, independent floor props. Only authored voids keep large collision
## geometry; every solid object has its own small, visible ground footprint.
## A cached connected path network is reserved before rejection sampling, so
## generation never needs to rebuild a navigation graph for each placed prop.

const Layouts = preload("res://scripts/world/room_layouts.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const VOID_KINDS := ["mine_pit", "gear_gap", "suspended_void", "water_channel", "floating_platform_gap", "ventilation_shaft", "acid_reservoir", "gantry_void", "mirror_pool", "deep_rift", "echo_disc_gap"]
const ASSETS := {
	"B01": ["B01_winch", "B01_ore_cart", "B01_crate_stack"],
	"B02": ["B02_spore_nest", "B02_root_barrier", "B02_fungal_rock"],
	"B03": ["B03_transformer", "B03_pipe_manifold", "B03_wrecked_drone"],
	"B04": ["B04_crystal_cluster", "B04_resonance_obelisk", "B04_broken_receiver"]
}
const ASSET_BOUNDS := {
	"B01_winch": Vector2(188, 144), "B01_ore_cart": Vector2(175, 135), "B01_crate_stack": Vector2(165, 127),
	"B02_spore_nest": Vector2(154, 144), "B02_root_barrier": Vector2(213, 130), "B02_fungal_rock": Vector2(160, 164),
	"B03_transformer": Vector2(154, 179), "B03_pipe_manifold": Vector2(183, 157), "B03_wrecked_drone": Vector2(182, 135),
	"B04_crystal_cluster": Vector2(168, 170), "B04_resonance_obelisk": Vector2(135, 198), "B04_broken_receiver": Vector2(179, 151)
}
const PATH_CLEARANCE := 72.0
const PROP_GAP := 112.0
const MAX_ATTEMPTS := 900
const MIN_PROPS := 4
const MAX_PROPS := 8
const CENTRAL_CLEARING := Rect2(1180.0, 740.0, 440.0, 320.0)
const CROSS_CLEARANCES := [Rect2(0.0, 820.0, 2800.0, 160.0), Rect2(1320.0, 0.0, 160.0, 1800.0)]
const COLUMN_SIZE := Vector2(80.0, 185.0)
const COLUMN_FOOTPRINT := Vector2(80.0, 34.0)
static var _skeletons: Dictionary = {}

static func generate(room_id: String, seed_value: int) -> Dictionary:
	return _generate_with_budget(room_id, seed_value, MAX_ATTEMPTS)

static func _generate_with_budget(room_id: String, seed_value: int, random_budget: int) -> Dictionary:
	# Private budget parameter lets acceptance tests force the exhaustion path.
	# Four useful obstacles are enough; visual richness comes from harmless
	# edge decoration rather than forcing colliders into the walking space.
	var started: int = Time.get_ticks_usec()
	var skeleton: Dictionary = _skeleton(room_id)
	if skeleton.is_empty():
		return {}
	var layout: Dictionary = skeleton.layout.duplicate(true)
	layout["seed"] = seed_value
	layout["generated"] = true
	layout["generation_version"] = 4
	layout["prop_instances"] = []
	layout["decoration_instances"] = []
	layout["reserved_paths"] = skeleton.paths.duplicate(true)
	layout["buff_anchors"] = []
	for zone: Dictionary in layout.get("encounter_zones", []):
		layout.buff_anchors.append(zone.center)
	var rng := RandomNumberGenerator.new()
	# Room identity salts a saved run seed; both values remain reproducible.
	rng.seed = seed_value ^ (int(room_id.trim_prefix("L")) * 104729)
	var target: int = rng.randi_range(MIN_PROPS, MAX_PROPS - 1)
	var biome: String = str(layout.biome_id)
	var assets: Array = ASSETS[biome]
	var placed: Array[Dictionary] = []
	var arena: Rect2 = layout.arena
	var placement: Rect2 = arena.grow(-104.0)
	var attempts: int = 0
	while placed.size() < target and attempts < maxi(0, random_budget):
		attempts += 1
		var asset_index: int = placed.size() if placed.size() < 3 else rng.randi_range(0, assets.size() - 1)
		var asset: String = str(assets[asset_index])
		var scale_value: float = rng.randf_range(0.76, 0.98)
		if asset == "B03_wrecked_drone":
			# Light detached drones can be displaced by magnetic attacks. A large
			# transformer or pipe bank must never slide like a small supply box.
			scale_value = rng.randf_range(0.55, 0.63)
		var size: Vector2 = ASSET_BOUNDS[asset] * scale_value
		var position := Vector2(rng.randf_range(placement.position.x, placement.end.x), rng.randf_range(placement.position.y, placement.end.y))
		_try_place(asset, position, size, skeleton, placed, layout, rng)
	var used_fallback: bool = placed.size() < MIN_PROPS
	if used_fallback:
		_fill_minimum(skeleton, placed, layout, rng)
	if placed.size() < MIN_PROPS:
		push_error("Room generation could not place the required " + str(MIN_PROPS) + " reachable props: " + room_id + " seed=" + str(seed_value) + " actual=" + str(placed.size()))
		return {}
	_replace_landmarks(skeleton, placed, layout, rng)
	layout.prop_instances = placed
	layout.decoration_instances = _edge_decorations(skeleton, placed, layout, rng)
	layout["generation_attempts"] = attempts
	layout["generation_fallback_used"] = used_fallback
	layout["generation_usec"] = Time.get_ticks_usec() - started
	layout["reserved_clearance_radius"] = Layouts.MAX_ACTOR_RADIUS
	return layout

static func _replace_landmarks(skeleton: Dictionary, placed: Array[Dictionary], layout: Dictionary, rng: RandomNumberGenerator) -> void:
	# Replace scenery within the existing budget. Utility-bearing thin walls and
	# movable fragments stay intact; no extra solid is added to the room.
	var candidates: Array[Vector2] = [Vector2(930,630),Vector2(1880,1180),Vector2(1880,630),Vector2(930,1180)]
	for y: float in [510.0, 620.0, 730.0, 1100.0, 1210.0, 1320.0]:
		for x: float in [760.0, 900.0, 1040.0, 1760.0, 1900.0, 2040.0]:
			candidates.append(Vector2(x,y)+Vector2(rng.randf_range(-22,22),rng.randf_range(-18,18)))
	var target: int = rng.randi_range(2, 3)
	var replaced: int = 0
	for index: int in placed.size():
		if replaced >= target: break
		var original: Dictionary = placed[index]
		if "thin_wall" in original.tags or "movable" in original.tags: continue
		var others: Array[Dictionary] = placed.duplicate()
		others.remove_at(index)
		for position: Vector2 in candidates:
			var collision := Rect2(position-COLUMN_FOOTPRINT*0.5,COLUMN_FOOTPRINT)
			var visual := Rect2(Vector2(position.x-COLUMN_SIZE.x*0.5,collision.end.y-COLUMN_SIZE.y),COLUMN_SIZE)
			if not _can_place(collision,visual,skeleton,others): continue
			var physical_index: int = layout.obstructions.find(original.collision_rect)
			if physical_index < 0: break
			var column: Dictionary = original.duplicate(true)
			column.merge({"architecture_key":"column", "position":position, "collision_rect":collision,
				"visual_size":COLUMN_SIZE, "visual_rect":visual, "rotation":0.0},true)
			column.tags.append("storybook_architecture")
			placed[index] = column
			layout.obstructions[physical_index] = collision
			replaced += 1
			break
	layout["landmark_count"] = replaced

static func _edge_decorations(skeleton: Dictionary, placed: Array[Dictionary], layout: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	# These props are silhouettes only: no solid/movable/breakable tags and a
	# zero-area physical rectangle. Keep them at the perimeter and away from
	# required interactions and all reserved walking corridors.
	var result: Array[Dictionary] = []
	var assets: Array = ASSETS[str(layout.biome_id)]
	var domain: Rect2 = layout.arena.grow(-116.0)
	var target: int = rng.randi_range(8, 12)
	for attempt: int in 600:
		if result.size() >= target: break
		var side: int = rng.randi_range(0, 3)
		var position := Vector2(rng.randf_range(domain.position.x, domain.end.x), rng.randf_range(domain.position.y + 96.0, domain.end.y))
		var depth: float = rng.randf_range(0.0, 105.0)
		if side == 0: position.x = domain.position.x + depth
		elif side == 1: position.x = domain.end.x - depth
		elif side == 2: position.y = domain.position.y + 96.0 + depth
		else: position.y = domain.end.y - depth
		var asset: String = str(assets[rng.randi_range(0, assets.size() - 1)])
		var size: Vector2 = ASSET_BOUNDS[asset] * rng.randf_range(0.50, 0.72)
		var visual := Rect2(position - Vector2(size.x * 0.5, size.y), size)
		if not domain.encloses(visual): continue
		var clear: bool = true
		for obstacle: Rect2 in skeleton.layout.static_obstructions:
			if visual.grow(20.0).intersects(obstacle, true): clear = false; break
		if not clear: continue
		for corridor: Rect2 in skeleton.corridors:
			if visual.grow(12.0).intersects(corridor, true): clear = false; break
		if not clear: continue
		for reservation: Rect2 in skeleton.reservations:
			if visual.grow(16.0).intersects(reservation, true): clear = false; break
		if not clear: continue
		for anchor: Vector2 in skeleton.anchors:
			if visual.grow(90.0).has_point(anchor): clear = false; break
		if not clear: continue
		for other: Dictionary in placed + result:
			if visual.grow(24.0).intersects(other.visual_rect, true): clear = false; break
		if not clear: continue
		result.append({"id":str(layout.room_id)+":decoration:"+str(result.size()), "asset":asset, "position":position,
			"visual_size":size, "visual_rect":visual, "collision_rect":Rect2(position,Vector2.ZERO),
			"kind":"edge_decoration", "tags":["decoration","non_solid",str(layout.biome_id)], "rotation":rng.randf_range(-0.05,0.05)})
	return result

static func _try_place(asset: String, position: Vector2, size: Vector2, skeleton: Dictionary, placed: Array[Dictionary], layout: Dictionary, rng: RandomNumberGenerator) -> bool:
	var footprint := Vector2(size.x * 0.73, size.y * 0.30)
	if asset.ends_with("obelisk"):
		footprint = Vector2(size.x * 0.58, size.y * 0.23)
	var collision := Rect2(position - footprint * 0.5, footprint)
	var visual := Rect2(Vector2(position.x - size.x * 0.5, collision.end.y - size.y), size)
	if not layout.arena.grow(-64.0).encloses(visual) or not _can_place(collision, visual, skeleton, placed):
		return false
	var room_id: String = str(layout.room_id)
	var tags: Array[String] = ["solid", "generated_prop", str(layout.biome_id)]
	var kind: String = "independent_prop"
	if room_id == "L11" and asset == "B02_root_barrier":
		kind = "breakable_wall"
		tags.append("thin_wall")
	if asset == "B03_wrecked_drone":
		tags.append("movable")
	placed.append({"id": room_id + ":prop:" + str(placed.size()), "asset": asset, "position": position, "visual_size": size, "visual_rect": visual, "collision_rect": collision, "kind": kind, "tags": tags, "rotation": rng.randf_range(-0.045, 0.045)})
	layout.obstructions.append(collision)
	layout.obstruction_kinds.append(kind)
	return true

static func _fill_minimum(skeleton: Dictionary, placed: Array[Dictionary], layout: Dictionary, rng: RandomNumberGenerator) -> void:
	# Spatial scan is bounded, shuffled and jittered deterministically by the
	# saved seed. It uses the SAME clearance rules and never places an unsafe
	# fallback wall, removes a reservation, or reruns the navigation graph.
	var domain: Rect2 = layout.arena.grow(-104.0)
	var columns: int = int(ceil(domain.size.x / 88.0))
	var rows: int = int(ceil(domain.size.y / 84.0))
	var cells: Array[int] = []
	for index: int in range(columns * rows):
		cells.append(index)
	for index: int in range(cells.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: int = cells[index]
		cells[index] = cells[other]
		cells[other] = swap
	var assets: Array = ASSETS[str(layout.biome_id)]
	for scale_value: float in [0.90, 0.78]:
		for cell: int in cells:
			var position: Vector2 = domain.position + Vector2((float(cell % columns) + 0.5) * domain.size.x / float(columns), (float(cell / columns) + 0.5) * domain.size.y / float(rows))
			position += Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-22.0, 22.0))
			# Try every shape at a cell rather than repeatedly demanding a single
			# oversized first asset. Successful placements still mix all 3 assets.
			for offset: int in range(assets.size()):
				var asset: String = str(assets[(placed.size() + offset) % assets.size()])
				var size: Vector2 = ASSET_BOUNDS[asset] * (0.57 if asset == "B03_wrecked_drone" else scale_value)
				if _try_place(asset, position, size, skeleton, placed, layout, rng):
					break
			if placed.size() >= MIN_PROPS:
				return

static func _skeleton(room_id: String) -> Dictionary:
	if _skeletons.has(room_id):
		return _skeletons[room_id]
	var layout: Dictionary = Layouts.build(room_id)
	if layout.is_empty():
		return {}
	var kept: Array[Rect2] = []
	var kinds: Array[String] = []
	var original_kinds: Array = layout.get("obstruction_kinds", [])
	for index: int in range(layout.obstructions.size()):
		var kind: String = str(original_kinds[index]) if index < original_kinds.size() else ""
		if kind in VOID_KINDS:
			kept.append(layout.obstructions[index])
			kinds.append(kind)
	layout["obstructions"] = kept
	layout["obstruction_kinds"] = kinds
	layout["static_obstructions"] = kept.duplicate()
	layout["static_obstruction_kinds"] = kinds.duplicate()
	layout["biome_id"] = str(Catalog.room(room_id).get("biome_id", "B01"))
	var report: Dictionary = Layouts.validate_layout(layout, Layouts.MAX_ACTOR_RADIUS)
	if not bool(report.valid):
		push_error("Cannot generate disconnected room skeleton " + room_id + ": " + str(report.errors))
		return {}
	var paths: Dictionary = {}
	var corridors: Array[Rect2] = []
	var unique: Dictionary = {}
	for path_id: String in report.paths:
		var path: Array[Vector2] = _compress(report.paths[path_id])
		paths[path_id] = path
		for index: int in range(1, path.size()):
			var a: Vector2 = path[index - 1]
			var b: Vector2 = path[index]
			var rect := Rect2(a.min(b), (b - a).abs()).grow(PATH_CLEARANCE)
			var key: String = str(rect)
			if not unique.has(key):
				corridors.append(rect)
				unique[key] = true
	var reservations: Array[Rect2] = []
	for zone: Dictionary in layout.get("dynamic_reservations", []):
		if zone.get("rect") is Rect2:
			reservations.append(zone.rect.grow(PATH_CLEARANCE))
	for zone: Dictionary in layout.get("hazard_zones", []):
		if zone.get("rect") is Rect2:
			reservations.append(zone.rect.grow(20.0))
	var anchors: Array[Vector2] = [layout.entry, layout.exit]
	for key: String in ["spawn_points", "objective_points", "topology_probes"]:
		anchors.append_array(layout.get(key, []))
	for item: Dictionary in layout.get("interactables", []):
		anchors.append(item.position)
	for zone: Dictionary in layout.get("encounter_zones", []):
		anchors.append(zone.center)
		anchors.append_array(zone.get("spawn_points", []))
	_skeletons[room_id] = {"layout": layout, "paths": paths, "corridors": corridors, "anchors": anchors, "reservations": reservations}
	return _skeletons[room_id]

static func _compress(source: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point: Vector2 in source:
		if result.size() >= 2:
			var a: Vector2 = result[result.size() - 2]
			var b: Vector2 = result[result.size() - 1]
			if (is_equal_approx(a.x, b.x) and is_equal_approx(b.x, point.x)) or (is_equal_approx(a.y, b.y) and is_equal_approx(b.y, point.y)):
				result[result.size() - 1] = point
				continue
		result.append(point)
	return result

static func _can_place(collision: Rect2, visual: Rect2, skeleton: Dictionary, placed: Array[Dictionary]) -> bool:
	# The concept's broad courtyard is an actual walking space. Supplies and
	# mission objects keep their authored anchors; generated cover stays around
	# the perimeter rather than reclaiming that central combat area.
	if visual.grow(24.0).intersects(CENTRAL_CLEARING, true): return false
	for clearance: Rect2 in CROSS_CLEARANCES:
		if collision.grow(Layouts.MAX_ACTOR_RADIUS).intersects(clearance,true): return false
	for obstacle: Rect2 in skeleton.layout.static_obstructions:
		if collision.grow(PROP_GAP).intersects(obstacle, true) or visual.grow(8.0).intersects(obstacle, true):
			return false
	for corridor: Rect2 in skeleton.corridors:
		if collision.intersects(corridor, true):
			return false
	for reservation: Rect2 in skeleton.reservations:
		if visual.intersects(reservation, true):
			return false
	for anchor: Vector2 in skeleton.anchors:
		if collision.grow(80.0).has_point(anchor) or visual.grow(16.0).has_point(anchor):
			return false
	for other: Dictionary in placed:
		if collision.grow(PROP_GAP).intersects(other.collision_rect, true) or visual.grow(26.0).intersects(other.visual_rect, true):
			return false
	return true
