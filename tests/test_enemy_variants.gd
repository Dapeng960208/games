extends "res://tests/test_enemy_integration.gd"
## Real finite wave spawning, visible frame identities, source feet and casts.

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_variants"):
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated real run starts")
	for id: String in ["L15", "L19"]:
		await _test_room_waves(id)
	_test_identity_and_skill_badge()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("ENEMY VARIANTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _frame_key(actor: MineEnemy) -> String:
	var frame: Dictionary = actor.body_visual.body_frame()
	var entry: Dictionary = Art.variant_entry_for(actor.enemy_id, int(actor.profile.visual_variant_index))
	check(frame.texture == entry.texture and frame.region == entry.region, actor.enemy_id + " real drawn texture/region matches allocation")
	return Art.appearance_key(entry)

func _test_room_waves(id: String) -> void:
	fixture(id)
	room.difficulty = 4
	var appearances: Dictionary = {}
	var total: int = 0
	var expected: int = 0
	for zone: int in 3:
		var plan: Dictionary = room._encounter_plan(zone)
		expected += int(plan.total_count)
		room.player.position = room.encounter_zones[zone].center
		var wave_index: int = 0
		for wave_members: Array in plan.waves:
			check(room._spawn_encounter_wave(zone, wave_members), "%s Z%d materializes real complete finite wave" % [id, zone])
			check(room.enemies.get_child_count() == wave_members.size(), id + " wave contains all actual actors")
			for actor: MineEnemy in room.enemies.get_children():
				appearances[_frame_key(actor)] = true
				total += 1
				check(actor.brain != null and actor.profile.behavior_id == Profiles.resolve(actor.enemy_id, actor.enemy_level).behavior_id, actor.enemy_id + " outfit retains its original behavior")
				check(room.valid_ground(actor.position, actor.navigation_radius), actor.enemy_id + " uses actual walkable ground and gameplay radius")
			if zone == 1 and wave_index == 0:
				await _capture_current_wave(id)
			clear_enemies()
			wave_index += 1
	var repeat: float = float(total - appearances.size()) / maxf(1.0, total)
	check(total == expected and repeat < .3, "%s real entire D4 room: %d actors, %d body regions, %.4f repeat" % [id, total, appearances.size(), repeat])
	var allocated: int = 0
	for count: int in room._enemy_visual_counts.values(): allocated += count
	check(allocated == total, id + " room appearance counter includes retired prior waves")
	var first_identity: String = str(room._encounter_plan(0).waves[0][0].enemy_id)
	var seed_value: int = room.layout_seed
	check(room.load_room_layout(id, 4, seed_value), id + " same-seed room reload succeeds")
	var actor := room.spawn_enemy(room.encounter_zones[0].center, first_identity, 20)
	check(actor != null and int(actor.profile.visual_variant_index) == Art.variant_index_for(first_identity, 0, id, seed_value), id + " same-seed reload restarts deterministic appearance allocation")
	clear_enemies()

func _capture_current_wave(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	room.camera.global_position = room.player.global_position
	room.camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	var pixels: Image = get_viewport().get_texture().get_image()
	var output: String = Game.profile_path.get_base_dir().path_join(id + "_enemy_variants.png")
	check(not pixels.is_empty() and pixels.save_png(output) == OK, id + " saves real GPU wave capture within isolated test directory")
	print("ENEMY VARIANT GPU: " + output)

func _test_identity_and_skill_badge() -> void:
	fixture()
	var standalone := MineEnemy.new()
	standalone.configure(Profiles.resolve("M01", 8))
	standalone.room = room
	standalone.process_mode = Node.PROCESS_MODE_DISABLED
	room.enemies.add_child(standalone)
	check(standalone.body_texture == Art.entry_for("M01").texture and standalone.body_region == Art.entry_for("M01").region, "default entry_for retains canonical original body")
	standalone.free()
	for identity: String in ["M01", "M10", "M19", "M27", "M28", "M35"]:
		var actor := room.spawn_enemy(Vector2(1050, 800), identity, 8)
		check(actor != null, identity + " real actor is allocated before ready")
		if actor == null: continue
		var visual: EnemyVisual = actor.body_visual
		var initial: Dictionary = visual.body_frame()
		var entry: Dictionary = Art.variant_entry_for(identity, int(actor.profile.visual_variant_index))
		var source_foot: Vector2 = initial.bounds.position + (entry.foot - entry.region.position) * initial.bounds.size.y / float(entry.source_height)
		check(source_foot.length() < .001 and is_equal_approx(actor.body_bounds.end.y, 18.0), identity + " measured source foot registers to preserved gameplay pivot")
		check(initial.texture != null and (initial.region as Rect2).has_area() and (initial.texture as Texture2D).get_size().x >= (initial.region as Rect2).end.x, identity + " loads real in-bounds generated atlas")
		check(not visual.contact_anchor(Vector2.RIGHT).is_empty(), identity + " alpha silhouette provides real impact contact")
		for state: StringName in [&"chase", &"telegraph", &"locked", &"execute", &"recovery"]:
			actor.state = state
			actor.state_time = .2
			visual.advance(.016)
			var frame: Dictionary = visual.body_frame()
			check(frame.texture == initial.texture and frame.region == initial.region and visual.selected_frame.is_empty(), identity + " " + str(state) + " keeps chosen outfit without old motion-bank override")
		actor.free()
	var actor := room.spawn_enemy(Vector2(1090,800), "M27", 8)
	actor.state = &"chase"
	until(func(): return actor.state in [&"telegraph", &"locked"], 8.0)
	var visual: EnemyVisual = actor.body_visual
	check(actor.state in [&"telegraph", &"locked"] and visual.skill_badge.visible, "actual shovel attack opens its skill badge with real telegraph")
	var tell: Dictionary = actor.brain.current_telegraph()
	check(visual.skill_badge.command.get("kind", "") == tell.get("kind", "") and int(visual.skill_badge.command.get("stage", -1)) == int(tell.get("stage", -2)), "badge describes actual current cast and combo stage")
	check(visual.skill_badge.icon.texture == Art.skill_icon_for("M27").texture and visual.skill_badge.icon.region == Art.skill_icon_for("M27").region, "shovel cast uses its own painted skill illustration")
	visual.reduced_fx_override = 1
	visual.advance(.016)
	check(visual.skill_badge.visible and visual.skill_badge.reduced_fx and not actor.brain.current_telegraph().is_empty(), "reduced FX preserves cast badge and ground-warning payload")
	visual.skill_badge.icon = {}
	visual.skill_badge.queue_redraw()
	check(visual.skill_badge.visible and not visual.skill_badge.command.is_empty(), "missing icon preserves warning fallback and actual cast")
	actor.state = &"recovery"
	visual.advance(.016)
	check(not visual.skill_badge.visible, "badge retires after actual cast ends")
	var counts: Dictionary = room._enemy_visual_counts.duplicate()
	var anchor := room.spawn_enemy(Vector2(930,800), "", 1, {"static_actor":true,"actor_kind":"hazard_endpoint","profile":{"max_hp":10.0,"navigation_radius":10.0}})
	check(anchor != null and room._enemy_visual_counts == counts and not anchor.profile.has("visual_variant_index"), "static skill endpoint consumes no appearance index")
	check(Art.variant_entry_for("M01", -1).region == Art.entry_for("M01").region and Art.variant_entry_for("M01", 999999).region == Art.entry_for("M01").region, "invalid selected index falls back to canonical body")
