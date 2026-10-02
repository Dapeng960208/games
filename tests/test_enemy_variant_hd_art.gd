extends Node
## Exact-source sampling checks plus optional real 2560x1440 room captures.
## Screenshots/measurements stay in ignored artifacts; never use a player save.
const Art = preload("res://scripts/combat/enemy_art.gd")
const RoomScene = preload("res://scenes/room.tscn")
const SkillPresentation = preload("res://scripts/combat/enemy_skill_presentation.gd")
const CASES := [{"id":"M22","index":0,"room":"L15","biome":"B03"}, {"id":"M34","index":0,"room":"L19","biome":"B04"}, {"id":"M34","index":1,"room":"L19","biome":"B04"}, {"id":"M34","index":4,"room":"L19","biome":"B04"}]
const OUTPUT := "res://artifacts/enemy-variant-hd-art/"
var checks := 0
var failures := 0
var room: MineRoom
var hud: Control
var layer: CanvasLayer
var originals: Dictionary = {}
var measurements: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90.0).timeout.connect(func(): push_error("ENEMY_VARIANT_HD_ART timeout"); get_tree().quit(1))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY_VARIANT_HD_ART: " + label)

func frames() -> void:
	for index: int in 2:
		await get_tree().process_frame
		await get_tree().physics_frame

func check_registry() -> void:
	Art.entry_for("M34")
	var live := Art._variants.duplicate(true)
	var canonical := Art._entries.duplicate(true)
	var badges := Art._skill_icons.duplicate(true)
	Art._variants = {}
	Art._load_variants()
	originals = Art._variants.duplicate(true)
	var total := 0
	var changed := 0
	var distinct: Dictionary = {}
	for identity: String in originals:
		check(live.has(identity) and live[identity].size() == originals[identity].size(), identity + " keeps exact variant count")
		for index: int in originals[identity].size():
			var old: Dictionary = originals[identity][index]
			var current: Dictionary = live[identity][index]
			total += 1
			check(current.variant_id == old.variant_id and current.visual_variant_index == old.visual_variant_index, identity + " keeps original stable identity " + str(index))
			var key := Art.appearance_key(current)
			check(not distinct.has(key), identity + " remains a distinct appearance " + str(index))
			distinct[key] = true
			if bool(current.get("hd_variant",false)):
				changed += 1
				check(Art.VARIANT_HD_INDICES.has(identity) and index in Art.VARIANT_HD_INDICES[identity], identity + " replacement is explicitly bounded")
				check(current.hd_source.variant_id == old.variant_id and current.hd_source.texture == old.texture_path, identity + " HD source matches original entry")
			else:
				check(current == old, identity + " non-target entry is completely unchanged " + str(index))
	check(total == 599 and changed == 4 and total-changed == 595, "exactly four of 599 entries upgraded; other 595 untouched")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Art.VARIANT_HD_MANIFEST))
	check(raw.overrides.size() == 4, "manifest contains exactly the four approved source identities")
	for candidate: Dictionary in raw.overrides:
		check(not Art._variant_hd_entry(candidate).is_empty(), "valid exact-source candidate accepted")
		for field: String in ["identity","visual_variant_index","variant_id","texture","region","foot","source_height"]:
			var bad: Dictionary = candidate.duplicate(true)
			match field:
				"identity": bad.source[field] = "M01"
				"visual_variant_index": bad.source[field] = 2
				"region": bad.source[field][0] += 1
				"foot": bad.source[field][0] += 1
				"source_height": bad.source[field] += 1
				_: bad.source[field] = "wrong-source"
			check(Art._variant_hd_entry(bad).is_empty(), "changed source " + field + " safely retains original")
		for field: String in ["source_identity","source_variant_id","texture","region","foot","full_color","native_redraw"]:
			var bad: Dictionary = candidate.duplicate(true)
			match field:
				"region": bad.replacement[field][2] *= .9
				"foot": bad.replacement[field][0] += 20
				"full_color", "native_redraw": bad.replacement[field] = false
				_: bad.replacement[field] = "wrong-replacement"
			check(Art._variant_hd_entry(bad).is_empty(), "changed replacement " + field + " safely retains original")
	check(Art._variants == originals, "candidate validation does not mutate the original registry")
	Art._variants = live
	check(Art._entries == canonical and Art._skill_icons == badges, "canonical, expansion, boss bodies and all skill icons are unchanged")
	for identity: String in ["BO01","BO02","BO03","BO04"]:
		check(bool(Art.entry_for(identity).get("combat_body",false)), identity + " published HD combat body stays active")
	for identity: String in ["M22","M34"]:
		check(Art.variant_entry_for(identity,-1) == canonical[identity] and Art.variant_entry_for(identity,99999) == canonical[identity], identity + " invalid indices retain canonical fallback")
		seed(41827)
		var expected := randi()
		seed(41827)
		for serial: int in 15:
			var count: int = originals[identity].size()
			var offset := posmod(("L19:41827:"+identity).hash(),count)
			check(Art.variant_index_for(identity,serial,"L19",41827) == posmod(offset+serial,count), identity + " keeps deterministic original allocation")
		check(randi() == expected, identity + " allocation consumes no gameplay RNG")

func refresh(actor: MineEnemy) -> void:
	actor.body_visual.advance(.016)
	actor.queue_redraw()
	room.enemy_telegraphs.refresh()
	room.queue_redraw()
	hud.refresh()
	await frames()
	if DisplayServer.get_name() != "headless": RenderingServer.force_draw(false)

func capture(filename: String, actor: MineEnemy) -> void:
	await refresh(actor)
	if DisplayServer.get_name() == "headless": return
	var pixels := get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440), filename + " is a native 2K framebuffer")
	check(pixels.save_png(OUTPUT+filename+".png") == OK, filename + " saves actual production pixels")

func spawn_sample(item: Dictionary, legacy: bool) -> MineEnemy:
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children(): actor.free()
	var identity: String = item.id
	var index: int = item.index
	var hd: Dictionary = Art._variants[identity][index]
	if legacy: Art._variants[identity][index] = originals[identity][index]
	# Use the actual allocation/spawn path, selecting its serial rather than
	# changing the actor after ready or giving it a separate test renderer.
	room._enemy_visual_room_key = room.layout_id + ":" + str(room.layout_seed)
	room._enemy_visual_counts[identity] = posmod(index-Art.variant_index_for(identity,0,room.layout_id,room.layout_seed),Art.variant_count(identity))
	var actor := room.spawn_enemy(Vector2(840,610),identity,15)
	Art._variants[identity][index] = hd
	check(actor != null and int(actor.profile.get("visual_variant_index",-1)) == index, identity + " actual room selects exact variant " + str(index))
	if actor == null: return null
	actor.state = &"chase"
	actor.aim_direction = Vector2.RIGHT
	room.player.position = room.clamp_actor(actor.position + Vector2(-155,0),30.0)
	room.player.aim_direction = room.player.position.direction_to(actor.position)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	return actor

func check_frame(actor: MineEnemy, entry: Dictionary, label: String) -> void:
	var visual: EnemyVisual = actor.body_visual
	var frame := visual.body_frame()
	check(frame.texture == entry.texture and frame.region == entry.region and frame.full_color, label + " draws only the exact selected body")
	check(visual.selected_frame.is_empty() and visual.asset_mode == "storybook_static", label + " never substitutes a canonical motion-bank pose")
	var foot: Vector2 = frame.bounds.position+(entry.foot-entry.region.position)*frame.bounds.size.y/entry.source_height
	check(foot.length() < .001, label + " anchors its complete body on the original ground origin")
	check(visual.skill_badge.icon == Art.skill_icon_for(actor.enemy_id), label + " retains original upright skill icon")

func check_sample(item: Dictionary) -> void:
	var prepared := room.prepare_expedition_node({"room_id":item.room,"role":"combat","biome_id":item.biome,"node_index":2,"node_count":7,"difficulty":0,"seed":41827,"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)), str(item.room) + " real room prepares")
	if not bool(prepared.get("valid",false)): return
	room.apply_prepared_expedition_node(prepared)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	room.spawn_enabled = false
	var label: String = "%s_%02d" % [item.id,item.index]
	var actor := spawn_sample(item,true)
	if actor == null: return
	var old_bounds := actor.body_bounds
	var profile := actor.profile.duplicate(true)
	var position_before := actor.position
	var radius := actor.navigation_radius
	await capture(label+"_legacy_right",actor)
	actor.aim_direction = Vector2.LEFT
	await capture(label+"_legacy_left",actor)
	actor = spawn_sample(item,false)
	if actor == null: return
	var entry := Art.variant_entry_for(item.id,item.index)
	check(bool(entry.get("hd_variant",false)), label + " uses approved native HD sample")
	check(actor.body_bounds.is_equal_approx(old_bounds), label + " preserves exact old width, height and foot pivot")
	check(actor.profile == profile and actor.navigation_radius == radius and actor.position == position_before, label + " preserves profile, AI, damage, collision and position")
	check(entry.texture.get_size() == Vector2(1254,1254) and entry.texture.get_image().has_mipmaps(), label + " uses native source with antialiased mip sampling")
	var shown_height: float = actor.body_bounds.size.y*room.camera.zoom.y*2.0
	check(float(entry.source_height) > shown_height*4.0, label + " has over four source pixels per 2K screen pixel")
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT]:
		actor.aim_direction = direction
		await capture(label+"_hd_"+("right" if direction.x>0 else "left"),actor)
		check_frame(actor,entry,label)
		check(signf(actor.body_visual.scale.x) == direction.x, label + " mirrors by actual aim direction")
		check(actor.body_visual.skill_badge.scale == Vector2.ONE, label + " skill badge remains unmirrored")
		var contact: Dictionary = actor.impact_anchor(direction)
		check(not contact.is_empty() and contact.anchor.get_ref() == actor.body_visual, label + " contact resolves to the mirrored HD body")
	# Start and advance the genuine authored skill with a fixed player target.
	actor.brain.age = 1.0
	actor.brain._begin_cycle(actor,room.player)
	actor.brain._publish(actor)
	await capture(label+"_hd_telegraph",actor)
	check_frame(actor,entry,label+" telegraph")
	check(actor.state == &"telegraph" and actor.body_visual.skill_badge.info == SkillPresentation.readout(actor.brain), label + " actual telegraph owns skill presentation")
	check(not room.enemy_telegraphs.snapshot().is_empty(), label + " real warning layer displays the skill")
	actor.brain.tick(actor,actor.brain._remaining+.001,room.player)
	await refresh(actor)
	check(actor.state == &"locked", label + " actual skill reaches locked phase")
	check_frame(actor,entry,label+" locked")
	actor.brain.tick(actor,actor.brain._remaining+.001,room.player)
	await capture(label+"_hd_release",actor)
	check(actor.state == &"execute" and actor.body_visual.skill_badge.command.get("phase") == "execute", label + " actual runtime release retains matching skill readout")
	check_frame(actor,entry,label+" execute")
	actor.brain.tick(actor,actor.brain._remaining+.001,room.player)
	await refresh(actor)
	check(actor.state == &"recovery", label + " actual skill reaches recovery")
	check_frame(actor,entry,label+" recovery")
	actor.body_visual.reduced_fx_override = 1
	actor.receive_confirmed_impact(Vector2.RIGHT,1.0,true)
	await refresh(actor)
	check(is_zero_approx(actor.body_visual.flash_strength) and actor.body_visual.skill_badge.visible, label + " reduced effects preserve body and skill presentation")
	check(actor.body_bounds.is_equal_approx(old_bounds) and actor.navigation_radius == radius and actor.position == position_before, label + " all poses leave original gameplay geometry unchanged")
	measurements.append({"identity":item.id,"variant_index":item.index,"variant_id":entry.variant_id,"source_height":entry.source_height,"old_source_height":originals[item.id][item.index].source_height,"world_bounds":str(actor.body_bounds),"collision_radius":radius,"camera_zoom":room.camera.zoom.y,"shown_height_2k":shown_height,"source_pixels_per_screen_pixel":entry.source_height/shown_height})
	check(await room.combat_audio.wait_for_cleanup(), label + " audio releases before next fixture")

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_variant_hd_art"):
		push_error("HD variant checks require an isolated test_enemy_variant_hd_art profile")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	check_registry()
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":41827}), "isolated real run starts")
	Game.profile.settings["enemy_skill_paths"] = true
	Game.profile.settings["reduced_fx"] = false
	room = RoomScene.instantiate()
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	await frames()
	for item: Dictionary in CASES: await check_sample(item)
	var file := FileAccess.open(OUTPUT+"measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"\t"))
	file.close()
	layer.free()
	room.free()
	Game.run = null
	await frames()
	print("ENEMY_VARIANT_HD_ART_RESULT checks=",checks," failures=",failures," graphical=",DisplayServer.get_name()!="headless")
	get_tree().quit(1 if failures else 0)
