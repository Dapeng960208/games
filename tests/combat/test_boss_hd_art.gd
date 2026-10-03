extends "res://tests/ui/test_boss_skill_ui.gd"
## Production-room regression for the four native HD combat bodies. AI time is
## stepped explicitly; this is rendering/registration QA, not balance testing.
## tools/test.ps1 -Suite boss_hd_art -Graphical -SkipImport
const EnemyArtSource = preload("res://scripts/presentation/monsters/enemy_art.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const HD_OUTPUT := "res://artifacts/boss-hd-art/"
var measurements: Array[Dictionary] = []

func opaque_bounds(source: Image) -> Rect2:
	var rgba: Image = source.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)
	var bytes := rgba.get_data()
	var width := rgba.get_width()
	var minimum := Vector2i(width,rgba.get_height())
	var maximum := Vector2i(-1,-1)
	for y in rgba.get_height():
		for x in width:
			if bytes[(y*width+x)*4+3] > 16:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	return Rect2(Vector2(minimum),Vector2(maximum-minimum+Vector2i.ONE)) if maximum.x >= 0 else Rect2()

func capture(filename: String, boss: BossActor) -> void:
	if DisplayServer.get_name() == "headless": return
	await refresh_draw(boss)
	var pixels := get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440), filename+" is a native 2K framebuffer")
	check(pixels.save_png(HD_OUTPUT+filename) == OK, filename+" saves real production pixels")

func old_entry(index: int, id: String) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(EnemyArtSource.MANIFESTS[index])))
	var texture: Texture2D = Sampler.sampled(raw.texture)
	var parsed := EnemyArtSource.parse_entry(raw.entries[id],texture.get_size())
	parsed.merge({"texture":texture,"texture_path":raw.texture,"source_family":EnemyArtSource.FAMILY})
	return parsed

func check_current_frame(boss: BossActor, entry: Dictionary, label: String) -> void:
	var frame: Dictionary = boss.body_visual.body_frame()
	check(frame.texture == entry.texture and frame.region == entry.region and frame.full_color, label+" displays only the identity-matched HD body")
	check(boss.body_visual.asset_mode == "storybook_static",label+" preserves the existing static-pose transform path")
	var factor: float = frame.bounds.size.y / float(entry.source_height)
	var foot: Vector2 = frame.bounds.position+(entry.foot-entry.region.position)*factor
	check(foot.length() < 0.001,label+" registers the complete source at the same ground origin")
	check(is_equal_approx(frame.bounds.size.x/frame.bounds.size.y,entry.region.size.x/entry.region.size.y),label+" keeps source proportions without stretching")

func check_boss(index: int) -> void:
	var id: String = IDS[index]
	var boss := await install(id,0)
	if boss == null: return
	var entry := EnemyArtSource.entry_for(id)
	check(bool(entry.get("combat_body",false)) and not bool(entry.get("individual_body",false)), id+" owns dedicated boss registration")
	check(entry.source_identity == id and entry.texture_path == "asset://ui/refactor_v1/codex/"+id+".png",id+" reuses its approved exact full-body source")
	var source: Image = entry.texture.get_image()
	check(source.get_size() == Vector2i(1254,1254) and source.get_pixel(0,0).a < .01,id+" retains native source resolution and alpha")
	check(entry.region.encloses(opaque_bounds(source)),id+" crop contains the complete opaque body, feet and weapons")
	var profile_before: Dictionary = boss.profile.duplicate(true)
	var collision_before: float = boss.navigation_radius
	var position_before: Vector2 = boss.position
	# Compare with the true old atlas renderer in the same production arena.
	# Runtime-only test state is restored before all HD assertions and captures.
	var legacy := old_entry(index,id)
	EnemyArtSource._entries[id] = legacy
	boss.configure(profile_before)
	check(boss.boss_id == id,id+" legacy comparison configures")
	var legacy_bounds: Rect2 = boss.body_bounds
	await capture(id+"_legacy_idle_2560x1440.png",boss)
	EnemyArtSource._entries[id] = entry
	boss.configure(profile_before)
	check(boss.boss_id == id,id+" HD comparison configures")
	var hd_bounds: Rect2 = boss.body_bounds
	check(is_equal_approx(legacy_bounds.size.y,hd_bounds.size.y) and is_equal_approx(legacy_bounds.end.y,hd_bounds.end.y) and is_equal_approx(hd_bounds.end.y,48.0),id+" preserves measured old combat height and foot pivot")
	check(boss.navigation_radius == collision_before and boss.position == position_before and boss.profile == profile_before,id+" leaves profile, damage/AI parameters, collision and actor position unchanged")
	check_current_frame(boss,entry,id+" idle")
	await capture(id+"_hd_idle_2560x1440.png",boss)
	var logical_to_physical := 2.0
	var shown_height: float = hd_bounds.size.y*room.camera.zoom.y*logical_to_physical
	check(float(entry.source_height) > shown_height*2.0,id+" has over two native pixels per displayed vertical pixel at production 2K scale")
	measurements.append({"id":id,"source_height":entry.source_height,"old_source_height":legacy.source_height,"world_height":hd_bounds.size.y,"old_world_width":legacy_bounds.size.x,"world_width":hd_bounds.size.x,"foot_y":hd_bounds.end.y,"camera_zoom":room.camera.zoom.y,"shown_height_2k":shown_height,"source_pixels_per_screen_pixel":float(entry.source_height)/shown_height})
	var action: String = Presentation.BASIC_ATTACKS[index]
	boss.boss_brain._begin_action(boss,room.player,action)
	boss.boss_brain.tick(boss,boss.boss_brain.state_time*.5,room.player)
	await refresh_draw(boss)
	check_draw(boss,action,false)
	check_current_frame(boss,entry,id+" telegraph")
	var preparation: Vector2 = boss.body_visual.body_offset
	await capture(id+"_hd_windup_2560x1440.png",boss)
	boss.boss_brain.tick(boss,boss.boss_brain.state_time+.001,room.player)
	await refresh_draw(boss)
	check_current_frame(boss,entry,id+" locked")
	boss.boss_brain.tick(boss,boss.boss_brain.state_time+.001,room.player)
	await refresh_draw(boss)
	check(Presentation.readout(boss.boss_brain).stage == "release" and boss.body_visual.body_offset.distance_to(preparation)>4,id+" preserves actual attack-release body animation")
	check_current_frame(boss,entry,id+" release")
	await capture(id+"_hd_release_2560x1440.png",boss)
	boss.boss_brain.tick(boss,.26,room.player)
	await refresh_draw(boss)
	check_current_frame(boss,entry,id+" recovery")
	var pose_before: Transform2D = boss.body_visual.transform
	var health_before: float = boss.health.current
	room.resolve_direct_hit(boss,28.0,&"primary","",0.0,Vector2.RIGHT,{"damage_type":"true","equipment_eligible":false,"original_basic":false})
	check(boss.health.current < health_before or boss.status.shield()>0,id+" actual direct-hit path resolves")
	check(not boss.body_visual.transform.is_equal_approx(pose_before),id+" confirmed impact still animates the HD body")
	var contact: Dictionary = boss.impact_anchor(Vector2.RIGHT)
	check(not contact.is_empty() and contact.anchor.get_ref() == boss.body_visual,id+" contact uses the visible HD alpha mask")
	check_current_frame(boss,entry,id+" impact")
	await capture(id+"_hd_impact_2560x1440.png",boss)
	boss.body_visual.reduced_fx_override = 1
	for step: int in 5: boss.body_visual.advance(.1)
	boss.receive_confirmed_impact(Vector2.LEFT,1.0,true)
	check(is_zero_approx(boss.body_visual.flash_strength),id+" reduced effects suppress whitening while retaining the body")
	for repeat: int in 3:
		boss.body_visual.configure(boss)
		check(boss.body_bounds.is_equal_approx(hd_bounds),id+" repeated visual registration does not grow or shift the body")
	check(boss.navigation_radius == collision_before and boss.position == position_before,id+" all body transforms leave gameplay geometry unchanged")

func _run() -> void:
	if not Game.profile_path.contains("test_boss_hd_art"):
		push_error("Boss HD checks require an isolated test_boss_hd_art profile")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HD_OUTPUT))
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":41827}),"isolated real run starts")
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
	for index: int in IDS.size(): await check_boss(index)
	var file := FileAccess.open(AssetCatalog.resolve(HD_OUTPUT+"measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"\t"))
	file.close()
	check(await room.combat_audio.wait_for_cleanup(),"room audio releases")
	layer.free()
	room.free()
	Game.run = null
	await frames()
	print("BOSS_HD_ART_RESULT checks=",checks," failures=",failures," graphical=",DisplayServer.get_name()!="headless")
	get_tree().quit(1 if failures else 0)
