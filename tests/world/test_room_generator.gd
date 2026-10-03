extends Node
## Independently validate actual seeded collision and every required anchor.
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _signature(layout: Dictionary) -> String:
	return var_to_str([layout.get("prop_instances", []), layout.get("decoration_instances", [])])

func _run() -> void:
	_check(Generator.generate("unknown", 1).is_empty(), "Unknown template is rejected")
	var maximum_warm_usec: int = 0
	var minimum_count: int = 100
	var maximum_count: int = 0
	var total_paths: int = 0
	for room_id: String in Catalog.room_ids():
		var authored: Dictionary = Layouts.build(room_id)
		var baseline: String = ""
		var asset_types: Dictionary = {}
		for seed_value: int in [1, 19, 517, 98761, 41827, 960208]:
			var layout: Dictionary = Generator.generate(room_id, seed_value)
			_check(not layout.is_empty(), room_id + " generation succeeds")
			if layout.is_empty(): continue
			var props: Array = layout.prop_instances
			minimum_count = mini(minimum_count, props.size())
			maximum_count = maxi(maximum_count, props.size())
			_check(props.size() >= 4 and props.size() <= 8, room_id + " sparse solid object density 4-8, actual=" + str(props.size()))
			_check(int(layout.landmark_count) <= 3, room_id + " landmark replacements stay within the existing solid budget")
			if room_id == "L05": _check(int(layout.landmark_count) >= 2, room_id + " native central scene includes two safely placed architectural landmarks")
			var decorations: Array = layout.decoration_instances
			_check(not decorations.is_empty() and decorations.size() <= 12, room_id + " edge decorations supply visual detail without extra obstacles")
			for decoration: Dictionary in decorations:
				_check("non_solid" in decoration.tags and "solid" not in decoration.tags and not decoration.collision_rect.has_area(), room_id + " decoration has no physical footprint")
				_check(not layout.obstructions.has(decoration.collision_rect), room_id + " decoration never enters movement collision")
				var at: Vector2 = decoration.position
				_check(minf(minf(at.x, 2800.0 - at.x), minf(at.y, 1800.0 - at.y)) <= 360.0, room_id + " decorations stay outside the main walking space")
			_check(layout.entry == authored.entry and layout.exit == authored.exit, room_id + " keeps entry and exit")
			_check(layout.encounter_zones == authored.encounter_zones and layout.interactables == authored.interactables and layout.objective_points == authored.objective_points, room_id + " preserves authored encounter and objective anchors")
			_check(layout.obstructions.size() == layout.static_obstructions.size() + props.size(), room_id + " no invisible old solid walls")
			_check(layout.obstruction_kinds.size() == layout.obstructions.size(), room_id + " rendered collision recipes match")
			_check(layout.static_obstruction_kinds.size() == layout.static_obstructions.size(), room_id + " static visual kinds match pits")
			_check(not bool(layout.gameplay_implemented) and not bool(layout.dynamic_states_verified), room_id + " no claim that generation implements template objectives")
			_check(layout.static_obstructions.is_empty(), room_id + " removes old rectangular pits and pools")
			for i: int in range(props.size()):
				var item: Dictionary = props[i]
				asset_types[item.asset] = true
				_check(str(item.asset).begins_with(str(Catalog.room(room_id).biome_id)), room_id + " themed original asset")
				_check(FileAccess.file_exists(AssetCatalog.resolve("asset://props/" + str(item.asset) + "_v1.png")), room_id + " actual PNG exists")
				_check(layout.obstructions.has(item.collision_rect), room_id + " actual gameplay collision exists")
				_check(not item.visual_rect.grow(24.0).intersects(Generator.CENTRAL_CLEARING, true), room_id + " solid props leave the central courtyard open")
				for clearance: Rect2 in Generator.CROSS_CLEARANCES:
					_check(not item.collision_rect.grow(24.0).intersects(clearance,true), room_id + " solid props preserve the broad central cross")
				_check(item.collision_rect.get_center().is_equal_approx(item.position), room_id + " sprite foot anchor equals collision center")
				_check(item.visual_rect.grow(0.02).encloses(item.collision_rect) and item.collision_rect.size.x <= item.visual_size.x and item.collision_rect.size.y < item.visual_size.y * 0.5, room_id + " tight lower-body footprint")
				if str(item.get("architecture_key", "")) == "column":
					_check(item.collision_rect.size == Vector2(80,34) and item.visual_size == Vector2(80,185) and "thin_wall" not in item.tags and "movable" not in item.tags, room_id + " budgeted column has a small matching base and never replaces a utility")
				_check(is_equal_approx(item.visual_rect.end.y, item.collision_rect.end.y), room_id + " image feet and physical bottom align")
				if "movable" in item.tags:
					_check(item.collision_rect.size.x <= 85.0 and item.collision_rect.size.y <= 55.0, room_id + " only small physical props can be magnetically displaced")
				for j: int in range(i + 1, props.size()):
					_check(not item.collision_rect.grow(72.0).intersects(props[j].collision_rect, true), room_id + " gaps between physical objects remain walkable")
					_check(not item.visual_rect.grow(24.0).intersects(props[j].visual_rect, true), room_id + " art silhouettes are separate")
			# The independent exhaustive validator checks actual generated geometry,
			# rather than trusting the generator's reserved-path bookkeeping.
			var report: Dictionary = Layouts.validate_layout(layout, 24.0)
			_check(bool(report.valid), room_id + " seed=" + str(seed_value) + " every anchor is physically connected: " + str(report.errors))
			total_paths += report.paths.size()
			for path: Array in layout.reserved_paths.values():
				for i: int in range(1, path.size()):
					_check(Layouts.segment_clear(layout, path[i - 1], path[i], 24.0), room_id + " retained path supports largest 48px actor")
			var signature: String = _signature(layout)
			if seed_value == 1:
				baseline = signature
			else:
				_check(signature != baseline, room_id + " different seed changes positions, sizes, and composition")
				maximum_warm_usec = maxi(maximum_warm_usec, int(layout.generation_usec))
			var replay: Dictionary = Generator.generate(room_id, seed_value)
			_check(_signature(replay) == signature and replay.obstructions == layout.obstructions, room_id + " seed exactly reproduces art and collisions")
			layout.prop_instances.clear()
			layout.obstructions.clear()
			_check(not Generator.generate(room_id, seed_value).prop_instances.is_empty(), room_id + " caller mutations cannot poison generator cache")
		_check(asset_types.size() == 3, room_id + " three different original theme props appear across seeds")
		var sample: Dictionary = Generator.generate(room_id, 1)
		# Force the public algorithm past its exhausted random-sampling budget.
		# This tests the actual deterministic spatial fallback, not a lucky seed.
		var fallback: Dictionary = Generator._generate_with_budget(room_id, 7289, 0)
		_check(not fallback.is_empty() and fallback.prop_instances.size() >= 4 and fallback.prop_instances.size() <= 8, room_id + " zero random budget keeps the sparse obstacle budget")
		if not fallback.is_empty():
			_check(bool(fallback.generation_fallback_used) and int(fallback.generation_attempts) == 0, room_id + " forced fixture actually took fallback branch")
			_check(_signature(fallback) == _signature(Generator._generate_with_budget(room_id, 7289, 0)), room_id + " fallback is deterministic")
			var fallback_report: Dictionary = Layouts.validate_layout(fallback, 24.0)
			_check(bool(fallback_report.valid), room_id + " fallback preserves all real paths: " + str(fallback_report.errors))
			_check(fallback.buff_anchors.size() == 3, room_id + " fallback retains three reachable spread encounter anchors for buffs")
			for i: int in range(fallback.prop_instances.size()):
				for j: int in range(i + 1, fallback.prop_instances.size()):
					_check(not fallback.prop_instances[i].collision_rect.grow(72.0).intersects(fallback.prop_instances[j].collision_rect, true), room_id + " fallback never sacrifices gaps for density")
		if room_id == "L11":
			_check(sample.prop_instances.any(func(item: Dictionary) -> bool: return str(item.kind) == "breakable_wall" and "thin_wall" in item.tags), "L11 retains an actual destructible root barrier")
		if str(sample.biome_id) == "B03":
			_check(sample.prop_instances.any(func(item: Dictionary) -> bool: return "movable" in item.tags), room_id + " retains actual small magnetic debris")
		print("ROOM_GENERATOR " + room_id + " seeds=6 asset_types=" + str(asset_types.size()) + " static_pits=" + str(sample.static_obstructions.size()) + " landmarks=" + str(sample.landmark_count))
		if room_id == "L05":
			for prop: Dictionary in sample.prop_instances:
				if str(prop.get("architecture_key", "")) == "column": print("LANDMARK L05 seed=1 position=",prop.position," collision=",prop.collision_rect)
	_check(maximum_warm_usec < 400000, "Warm generation under 400ms, actual=" + str(maximum_warm_usec) + "us")
	print("ROOM_GENERATOR_TESTS checks=" + str(checks) + " failures=" + str(failures) + " seeds=144 paths=" + str(total_paths) + " props=" + str(minimum_count) + ".." + str(maximum_count) + " warm_max_usec=" + str(maximum_warm_usec))
	get_tree().quit(0 if failures == 0 else 1)
