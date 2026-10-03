extends Node
## Exact-source sampling checks plus optional real 2560x1440 room captures.
## Screenshots/measurements stay in ignored artifacts; never use a player save.
const Art = preload("res://scripts/presentation/monsters/enemy_art.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const SkillPresentation = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const Virtual = preload("res://scripts/presentation/monsters/variant_hd_texture.gd")
const GROUPS := {"base":{"M22":[0],"M34":[0,1,4]},"ruins":{"M06":[0,6,7],"M09":[7],"M12":[0,5,6,7]},"hive":{"M17":[0,1,2,6,7],"M22":[5,7]},"soft":{"M04":[1],"M23":[0,3]}}
const EXPECTED := {"M04":[1],"M06":[0,6,7],"M09":[7],"M12":[0,5,6,7],"M17":[0,1,2,6,7],"M22":[0,5,7],"M23":[0,3],"M34":[0,1,4]}
var output := "res://artifacts/enemy-variant-hd-art-v2/"
var group := "base"
var frozen_root := ""
var only_identity := ""
var skip_legacy_captures := false
var checks := 0
var failures := 0
var room: RoomController
var hud: Control
var layer: CanvasLayer
var originals: Dictionary = {}
var measurements: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(300.0).timeout.connect(func(): push_error("ENEMY_VARIANT_HD_ART timeout"); get_tree().quit(1))
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

func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func selected_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for name: String in GROUPS:
		if group != "all" and name != group: continue
		for identity: String in GROUPS[name]:
			if not only_identity.is_empty() and identity != only_identity: continue
			for index: int in GROUPS[name][identity]:
				var biome: String = "B01" if identity in ["M04","M06","M09"] else "B02" if identity in ["M12","M17"] else "B03" if identity in ["M22","M23"] else "B04"
				var room_id: String = {"B01":"L01","B02":"L07","B03":"L15","B04":"L19"}[biome]
				result.append({"id":identity,"index":index,"room":room_id,"biome":biome})
	return result

func load_originals() -> void:
	Art._load_all_for_audit()
	var current := Art._variants
	Art._variants = {}
	Art._load_variants()
	originals = Art._variants.duplicate(true)
	Art._variants = current

func check_registry() -> void:
	Art._load_all_for_audit()
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
	check(total == 599 and changed == 22 and total-changed == 577 and Art.VARIANT_HD_INDICES == EXPECTED, "exactly 22 of 599 approved entries upgraded; other 577 untouched")
	var candidates: Array = []
	for path: String in Art.VARIANT_HD_MANIFESTS:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
		candidates.append_array(raw.overrides)
	check(candidates.size() == 22, "four manifests contain exactly the 22 approved source identities")
	for candidate: Dictionary in candidates:
		check(not Art._variant_hd_entry(candidate).is_empty(), "valid exact-source candidate accepted")
		for field: String in ["identity","visual_variant_index","variant_id","texture","region","foot","source_height"]:
			var bad: Dictionary = candidate.duplicate(true)
			match field:
				"identity": bad.source[field] = "M01"
				"visual_variant_index": bad.source[field] = 99999
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
		if candidate.has("virtual_transparent_layout"):
			for field: String in ["native_texture_size","virtual_canvas_size","native_texture_offset","virtual_registration_region","virtual_foot","logical_region_in_native_texture_coordinates","safe_native_sample_region","safe_sample_destination_normalized_within_logical_rect"]:
				var bad: Dictionary = candidate.duplicate(true)
				bad.virtual_transparent_layout[field][0] += .5
				check(Art._variant_hd_entry(bad).is_empty(), "invalid virtual " + field + " retains original")
			var missing: Dictionary = candidate.duplicate(true)
			missing.erase("virtual_transparent_layout")
			check(Art._variant_hd_entry(missing).is_empty(), "missing required virtual layout retains original")
		else:
			var padded: Dictionary = candidate.duplicate(true)
			padded["virtual_transparent_layout"] = {}
			check(Art._variant_hd_entry(padded).is_empty(), "unapproved key cannot opt into virtual layout")
	check(Art._variants == originals, "candidate validation does not mutate the original registry")
	Art._variants = live
	check(Art._entries == canonical and Art._skill_icons == badges, "canonical, expansion, boss bodies and all skill icons are unchanged")
	for identity: String in ["BO01","BO02","BO03","BO04"]:
		check(bool(Art.entry_for(identity).get("combat_body",false)), identity + " published HD combat body stays active")
	for identity: String in EXPECTED:
		check(Art.variant_entry_for(identity,-1) == canonical[identity] and Art.variant_entry_for(identity,99999) == canonical[identity], identity + " invalid indices retain canonical fallback")
		seed(41827)
		var expected := randi()
		seed(41827)
		for serial: int in 15:
			var count: int = originals[identity].size()
			var offset := posmod(("L19:41827:"+identity).hash(),count)
			check(Art.variant_index_for(identity,serial,"L19",41827) == posmod(offset+serial,count), identity + " keeps deterministic original allocation")
		check(randi() == expected, identity + " allocation consumes no gameplay RNG")
	check_four_checkpoint(live)
	check_virtual_pixels(live)

func check_four_checkpoint(live: Dictionary) -> void:
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://tests/fixtures/enemy_variant_hd_four_checkpoint.json")))
	for path: String in checkpoint.file_sha256:
		var current_hash := digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve("res://"+path)))
		check(current_hash == checkpoint.file_sha256[path], "frozen four-key asset/manifest bytes unchanged: " + path)
		if not frozen_root.is_empty():
			check(FileAccess.file_exists(AssetCatalog.resolve(frozen_root.path_join(path))) and digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve(frozen_root.path_join(path)))) == current_hash, "matches immutable four-key preview bytes: " + path)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(Art.VARIANT_HD_MANIFEST)))
	check(raw.overrides.size() == 4, "original four-key checkpoint manifest remains independent")
	for candidate: Dictionary in raw.overrides:
		var source: Dictionary = candidate.source
		var actual: Dictionary = live[source.identity][int(source.visual_variant_index)]
		var expected: Dictionary = originals[source.identity][int(source.visual_variant_index)].duplicate(true)
		var parsed := Art.parse_entry(candidate.replacement,Vector2(1254,1254))
		for field: String in ["region","foot","source_height"]: expected[field] = parsed[field]
		expected["texture"] = actual.texture
		expected["texture_path"] = candidate.replacement.texture
		expected["hd_variant"] = true
		expected["hd_source"] = source.duplicate(true)
		check(actual == expected, "four-key renderer entry remains exactly equivalent: " + source.variant_id)

func check_virtual_pixels(live: Dictionary) -> void:
	check(Virtual.textures.size() == 3, "virtual texture cache is bounded to the three approved M12 keys")
	var retained_bytes := 0
	for index: int in [5,6,7]:
		var entry: Dictionary = live.M12[index]
		check(entry.has("virtual_transparent_layout"), "M12 virtual layout is installed: " + str(index))
		if not entry.has("virtual_transparent_layout"): continue
		var layout: Dictionary = entry.virtual_transparent_layout
		var path: String = entry.texture_path
		var before := digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve(path)))
		var native := Image.new()
		check(native.load_png_from_buffer(FileAccess.get_file_as_bytes(AssetCatalog.resolve(path))) == OK, "native PNG bytes decode without importer transformations")
		var import_settings := ConfigFile.new()
		if FileAccess.file_exists(AssetCatalog.resolve(path+".import")):
			check(import_settings.load(path+".import") == OK and import_settings.get_value("params","process/fix_alpha_border",true) == false, "virtual export import disables alpha-border RGB rewriting")
		var canvas: Image = entry.texture.get_image()
		check(native != null and canvas.get_size() == Virtual.CANVAS_SIZE and canvas.has_mipmaps(), "virtual canvas/native pixels and mipmaps exist")
		if native == null: continue
		retained_bytes += canvas.get_data().size()
		native.clear_mipmaps()
		canvas.clear_mipmaps()
		var copied := canvas.get_region(Rect2i(layout.offset,Virtual.NATIVE_SIZE))
		check(copied.get_data() == native.get_data(), "all native RGBA bytes copied exactly without alpha/color edits")
		var imported := load(AssetCatalog.resolve(path)) as Texture2D
		var exported_pixels: Image = imported.get_image()
		exported_pixels.clear_mipmaps()
		check(exported_pixels.get_data() == native.get_data(), "lossless imported export fallback retains exact native RGBA bytes")
		var offset: Vector2i = layout.offset
		var strips: Array[Rect2i] = [Rect2i(0,0,offset.x,1280),Rect2i(offset.x+1254,0,1280-offset.x-1254,1280),Rect2i(offset.x,1254,1254,26)]
		for strip: Rect2i in strips:
			if not strip.has_area(): continue
			var bytes := canvas.get_region(strip).get_data()
			var empty := PackedByteArray()
			empty.resize(bytes.size())
			check(bytes == empty, "new virtual padding is all-zero RGBA")
		check(Virtual.sampled(path,layout) == entry.texture and Virtual.textures.size() == 3, "repeated registration reuses bounded cached texture")
		check(not Art.Sampler.textures.has(path), "virtual key retains no redundant native sampled GPU texture")
		check(digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve(path))) == before, "virtual sampling never writes native PNG bytes")
	check(retained_bytes <= 27*1024*1024, "three padded RGBA+mipmap textures stay below 27MiB")

func refresh(actor: EnemyActor) -> void:
	actor.body_visual.advance(.016)
	actor.queue_redraw()
	room.enemy_telegraphs.refresh()
	room.queue_redraw()
	hud.refresh()
	await frames()
	if DisplayServer.get_name() != "headless": RenderingServer.force_draw(false)

func capture(filename: String, actor: EnemyActor) -> void:
	await refresh(actor)
	if DisplayServer.get_name() == "headless": return
	var pixels := get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440), filename + " is a native 2K framebuffer")
	check(pixels.save_png(output+filename+".png") == OK, filename + " saves actual production pixels")

func spawn_sample(item: Dictionary, legacy: bool) -> EnemyActor:
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
	# L07's old (840,610) sample point is behind a beacon. Use clear floor
	# for B02 only; gameplay geometry and production art are untouched.
	var sample_at := Vector2(960,460) if item.biome == "B02" else Vector2(840,610)
	var actor := room.spawn_enemy(sample_at,identity,15)
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

func check_frame(actor: EnemyActor, entry: Dictionary, label: String) -> void:
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
	if not skip_legacy_captures:
		await capture(label+"_legacy_right",actor)
		actor.aim_direction = Vector2.LEFT
		await capture(label+"_legacy_left",actor)
	actor = spawn_sample(item,false)
	if actor == null: return
	var entry := Art.variant_entry_for(item.id,item.index)
	check(bool(entry.get("hd_variant",false)), label + " uses approved native HD sample")
	check(actor.body_bounds.is_equal_approx(old_bounds), label + " preserves exact old width, height and foot pivot")
	check(actor.profile == profile and actor.navigation_radius == radius and actor.position == position_before, label + " preserves profile, AI, damage, collision and position")
	var expected_texture_size := Vector2(1280,1280) if entry.has("virtual_transparent_layout") else Vector2(1254,1254)
	check(entry.texture.get_size() == expected_texture_size and entry.texture.get_image().has_mipmaps(), label + " uses native pixels with antialiased mip sampling")
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
		if entry.has("virtual_transparent_layout"): await check_death_snapshot(actor,entry,label,direction)
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
	if actor.has_meta("enemy_skill_motion"):
		# Authored leap motion is gameplay, not a visual-transform side effect.
		# Let its real runtime finish before checking the recovery pose.
		for step: int in 160:
			room.enemy_skills._physics_process(.025)
			actor.brain.tick(actor,.025,room.player)
			if actor.state == &"recovery": break
	else:
		actor.brain.tick(actor,actor.brain._remaining+.001,room.player)
	await refresh(actor)
	check(actor.state == &"recovery", label + " actual skill reaches recovery")
	check_frame(actor,entry,label+" recovery")
	var presentation_position := actor.position
	actor.body_visual.reduced_fx_override = 1
	actor.receive_confirmed_impact(Vector2.RIGHT,1.0,true)
	await refresh(actor)
	check(is_zero_approx(actor.body_visual.flash_strength) and actor.body_visual.skill_badge.visible, label + " reduced effects preserve body and skill presentation")
	check(actor.body_bounds.is_equal_approx(old_bounds) and actor.navigation_radius == radius and actor.position == presentation_position, label + " presentation leaves original bounds/collision and gameplay-resolved position unchanged")
	measurements.append({"identity":item.id,"variant_index":item.index,"variant_id":entry.variant_id,"source_height":entry.source_height,"old_source_height":originals[item.id][item.index].source_height,"world_bounds":str(actor.body_bounds),"collision_radius":radius,"camera_zoom":room.camera.zoom.y,"shown_height_2k":shown_height,"source_pixels_per_screen_pixel":entry.source_height/shown_height})
	check(await room.combat_audio.wait_for_cleanup(), label + " audio releases before next fixture")

func check_death_snapshot(actor: EnemyActor, entry: Dictionary, label: String, direction: Vector2) -> void:
	room.defeat_feedback.clear_feedback()
	# Corpse feedback has its own lower world layer. Place this fixture's
	# sample below the distant prop label, then restore the live actor.
	var actor_position := actor.position
	actor.position += Vector2(0,160)
	var frame: Dictionary = actor.body_visual.body_frame()
	check(room.defeat_feedback.capture(actor,direction), label + " virtual body accepts actual death snapshot")
	if room.defeat_feedback.events.is_empty():
		actor.position = actor_position
		return
	var event: Dictionary = room.defeat_feedback.events.back()
	check(event.frame == frame and event.frame.texture == entry.texture, label + " death snapshot retains full original logical frame")
	check(Rect2(Vector2.ZERO,entry.texture.get_size()).encloses(event.frame.region), label + " death snapshot samples strictly inside virtual texture")
	check(signf(event.basis.determinant()) == direction.x, label + " death snapshot preserves left/right mirror")
	actor.visible = false
	room.defeat_feedback.advance(.08)
	await capture(label+"_hd_death_"+("right" if direction.x>0 else "left"),actor)
	actor.visible = true
	actor.position = actor_position
	room.defeat_feedback.clear_feedback()

func check_death_only(index: int) -> void:
	var prepared := room.prepare_expedition_node({"room_id":"L07","role":"combat","biome_id":"B02","node_index":2,"node_count":7,"difficulty":0,"seed":41827,"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)), "M12 death sample real room prepares")
	if not bool(prepared.get("valid",false)): return
	room.apply_prepared_expedition_node(prepared)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	room.spawn_enabled = false
	var actor := spawn_sample({"id":"M12","index":index,"room":"L07","biome":"B02"},false)
	if actor == null: return
	var entry := Art.variant_entry_for("M12",index)
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT]:
		actor.aim_direction = direction
		await refresh(actor)
		check_frame(actor,entry,"M12 death-only "+str(index))
		await check_death_snapshot(actor,entry,"M12_%02d" % index,direction)
	check(await room.combat_audio.wait_for_cleanup(), "death-only fixture audio releases")

func check_subpixel(index: int) -> void:
	var item := {"id":"M17","index":index,"room":"L07","biome":"B02"}
	var prepared := room.prepare_expedition_node({"room_id":"L07","role":"combat","biome_id":"B02","node_index":2,"node_count":7,"difficulty":0,"seed":41827,"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)), "wing/orb actual room prepares")
	if not bool(prepared.get("valid",false)): return
	room.apply_prepared_expedition_node(prepared)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	room.spawn_enabled = false
	var actor := spawn_sample(item,false)
	if actor == null: return
	var visual: EnemyVisual = actor.body_visual
	var entry := Art.variant_entry_for("M17",index)
	check(visual.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and entry.texture.get_image().has_mipmaps(), "M17 actual linear/mipmap sampling enabled")
	var origin := actor.position
	var camera_origin := room.camera.position
	var screen_factor: float = room.camera.zoom.x*2.0
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT]:
		actor.aim_direction = direction
		visual.advance(.016)
		# Keep the exact pose/time fixed. Only translation traverses quarter
		# physical pixels; returning to zero catches nondeterministic shimmer.
		var fixed_transform := visual.transform
		var initial_digest := ""
		for sample: int in 5:
			var fraction: float = float(sample%4)*.25
			actor.position = origin+Vector2(fraction,fraction)/screen_factor
			visual.transform = fixed_transform
			room.camera.position = camera_origin
			room.camera.force_update_scroll()
			visual.queue_redraw()
			actor.queue_redraw()
			await frames()
			check_frame(actor,entry,"M17 subpixel "+str(index))
			if DisplayServer.get_name() == "headless": continue
			RenderingServer.force_draw(false)
			var pixels := get_viewport().get_texture().get_image()
			check(pixels.get_size() == Vector2i(2560,1440), "subpixel captures are native2K")
			var screen: Transform2D = visual.get_global_transform_with_canvas()
			var canvas_box: Rect2 = screen*visual.body_frame().bounds
			# Canvas units are the1280x720 logical viewport; screenshot is2x.
			var physical_box := Rect2i((canvas_box.position*2.0).floor(),(canvas_box.size*2.0).ceil()).grow(8)
			physical_box = physical_box.intersection(Rect2i(Vector2i.ZERO,pixels.get_size()))
			var current_digest := digest(pixels.get_region(physical_box).get_data())
			if sample == 0: initial_digest = current_digest
			if sample == 4: check(current_digest == initial_digest, "returning to identical subpixel pose yields identical wing/orb pixels")
			check(pixels.save_png(output+"M17_%02d_%s_subpixel_%d.png" % [index,"right" if direction.x>0 else "left",sample]) == OK, "save real subpixel sampling frame")
	actor.position = origin
	check(await room.combat_audio.wait_for_cleanup(), "subpixel fixture audio releases")

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_variant_hd_art"):
		push_error("HD variant checks require an isolated test_enemy_variant_hd_art profile")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hd-group="): group = argument.trim_prefix("--hd-group=")
		if argument.begins_with("--hd-frozen-root="): frozen_root = argument.trim_prefix("--hd-frozen-root=")
		if argument.begins_with("--hd-only="): only_identity = argument.trim_prefix("--hd-only=")
		if argument == "--hd-skip-legacy": skip_legacy_captures = true
	if group not in ["base","ruins","hive","soft","all","registry","subpixel","death"]:
		push_error("Unknown HD sample group")
		get_tree().quit(2)
		return
	if not only_identity.is_empty() and not EXPECTED.has(only_identity):
		push_error("Unknown HD identity filter")
		get_tree().quit(2)
		return
	output += group+("_"+only_identity if not only_identity.is_empty() else "")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if group in ["base","registry","all"]: check_registry()
	else: load_originals()
	if group == "registry":
		print("ENEMY_VARIANT_HD_ART_RESULT checks=",checks," failures=",failures," group=",group)
		get_tree().quit(1 if failures else 0)
		return
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
	hud = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	await frames()
	if group == "death":
		for index: int in [5,6,7]:
			await check_death_only(index)
			if failures > 0: break
	elif group == "subpixel":
		for index: int in [0,1,2,6,7]:
			await check_subpixel(index)
			if failures > 0: break
	else:
		for item: Dictionary in selected_cases():
			await check_sample(item)
			if failures > 0: break
	var file := FileAccess.open(AssetCatalog.resolve(output+"measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"\t"))
	file.close()
	layer.free()
	room.free()
	Game.run = null
	await frames()
	print("ENEMY_VARIANT_HD_ART_RESULT checks=",checks," failures=",failures," graphical=",DisplayServer.get_name()!="headless"," group=",group)
	get_tree().quit(1 if failures else 0)
