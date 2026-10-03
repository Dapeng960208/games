extends "res://tests/ui/test_role_natural_ui.gd"
## Runs only after all three complete production families are admitted. The
## gallery samples registered source poses; live observations use native inputs.
## No resource, cooldown, HP, position, damage or completion state is injected.
const SharedArt = preload("res://scripts/presentation/characters/hero_shared_action_family.gd")
const SkillPresentation = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const BasicFeedback = preload("res://scripts/presentation/characters/hero_feedback.gd")
const HeroArt = preload("res://scripts/presentation/characters/hero_visual.gd")
const WARRIOR_PEAK_CAPTURES := {"E":"warrior-basic-release-peak","SE":"warrior-basic-southeast-release-peak","S":"warrior-basic-south-release-peak","SW":"warrior-basic-southwest-release-peak","W":"warrior-basic-west-release-peak","NW":"warrior-basic-northwest-release-peak","N":"warrior-basic-north-release-peak","NE":"warrior-basic-northeast-release-peak"}
var autoplay := false
var warrior_feedback_probe := false
var warrior_2k_ready := false
var warrior_2k_after_serial := -1
var slash_texture_ids: Dictionary = {}
var slash_source_hashes: Dictionary = {}
var observed_frames: Dictionary = {}
var observed_art_releases: Dictionary = {}
var observed_art_projectiles: Dictionary = {}

class PreviewAbilities extends RefCounted:
	var active: Dictionary = {}
	func busy() -> bool: return not active.is_empty()

class PreviewPlayer extends Node2D:
	var hero := "CH01"
	var abilities := PreviewAbilities.new()
	var stride := 0.0
	var visual_hitstop := 0.0
	var dash_remaining := 0.0
	var dash_elapsed := 0.0
	var dash_direction := Vector2.RIGHT
	var aim_direction := Vector2.RIGHT
	var _automatic_attack_target: WeakRef
	func hero_id() -> String: return hero

class PreviewBrain extends RefCounted:
	func current_skill() -> Dictionary: return {"phase":"locked"}

class PreviewEnemy extends Node2D:
	var brain := PreviewBrain.new()
	func is_alive() -> bool: return true

class PreviewRoom extends Node2D:
	var player: PreviewPlayer
	var enemies := Node2D.new()

class FamilyGallery extends Control:
	var family: Dictionary
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("f9f2e0"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font,Vector2(24,28),str(family.hero_id)+" - registered production family: 8 views / 8 shared body poses",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("24384a"))
		for direction_index: int in SharedArt.DIRECTIONS.size():
			var key: String = SharedArt.DIRECTIONS[direction_index]
			draw_string(font,Vector2(113+direction_index*138,56),key,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("24384a"))
			for pose_index: int in SharedArt.POSES.size():
				var pose_name: String = SharedArt.POSES[pose_index]
				if direction_index == 0: draw_string(font,Vector2(5,104+pose_index*75),pose_name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("24384a"))
				var frame: Dictionary = family.directions[key][pose_name]
				draw_set_transform(Vector2(141+direction_index*138,127+pose_index*75),0,Vector2.ONE*.50)
				draw_texture_rect_region(frame.texture,frame.bounds,frame.region)
				draw_set_transform(Vector2.ZERO)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	_run.call_deferred()
	get_tree().create_timer(300.0).timeout.connect(func(): push_error("Runtime role art timeout"); get_tree().quit(2))

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_save_capture(name_value)

func _save_capture(name_value: String) -> void:
	var directory: String = Game.profile_path.get_base_dir()+"/captures"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"isolated art screenshot directory")
	var pixels: Image = get_viewport().get_texture().get_image()
	if name_value.contains("-2k-"): check(pixels.get_size() == Vector2i(2560,1440),"actual 2560 by 1440 render pixels")
	check(pixels.save_png(directory+"/"+name_value+".png") == OK,"actual production art capture "+name_value)
	print("ROLE_ART_CAPTURE ",directory+"/"+name_value+".png window=",DisplayServer.window_get_size()," pixels=",pixels.get_size())

func _run() -> void:
	warrior_feedback_probe = Game.profile_path.contains("test_runtime_warrior_feedback")
	if not warrior_feedback_probe and not Game.profile_path.contains("test_runtime_role_art"): get_tree().quit(2); return
	check(DisplayServer.get_name() != "headless","actual art validation uses the graphical renderer")
	var heroes: Array = ["CH01"] if warrior_feedback_probe else Catalog.HEROES
	for hero: String in heroes:
		var family: Dictionary = SharedArt.load_family(hero)
		check(not family.is_empty(),hero+" complete registered family is admitted before live testing")
		if family.is_empty(): get_tree().quit(2); return
		for key: String in ([] if warrior_feedback_probe else SharedArt.DIRECTIONS):
			for pose_name: String in SharedArt.POSES:
				var frame: Dictionary = family.directions[key][pose_name]
				check(frame.texture != null and frame.art_family == "shared_action" and str(frame.path).begins_with("asset://heroes/"+hero.to_lower()+"_poses_"+key.to_lower()+"_") and AssetCatalog.resolve(frame.path).ends_with(".png"),hero+" registered PNG identity "+key+"/"+pose_name)
	check(Game.new_profile(),"isolated actual-art profile")
	if warrior_feedback_probe: _check_basic_detail_clock()
	var setup: Dictionary = Game.profile.duplicate(true)
	setup.settings.auto_attack = false
	setup.settings.camera_shake = false
	check(Game._commit_profile(setup),"fixture input settings only; battle state remains native")
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames()
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	get_window().position = usable.position+(usable.size-get_window().size)/2
	print("ROLE_ART_DISPLAY screen=",DisplayServer.screen_get_size()," usable=",usable," gameplay_window=",get_window().size)
	for hero: String in heroes:
		await configure(hero,0)
		if not warrior_feedback_probe: await _gallery(hero)
		await _live_art(hero)
		if Game.run != null: check(not Game.finish_run("abandoned").is_empty(),hero+" explicitly abandons the art probe; no completion claim")
		await frames()
	var mode: String = "runtime_warrior_feedback" if warrior_feedback_probe else "runtime_role_art"
	var result := {"checks":checks,"failures":failures,"roles":rows,"method":"three-role basic-clock presentation fixtures and one native warrior feedback probe" if warrior_feedback_probe else "registered production gallery plus automated native inputs; no human feel or 36-damage-matrix claim"}
	var output := FileAccess.open(Game.profile_path.get_base_dir()+"/"+mode+".json",FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(result,"\t")); output.close()
	print("RUNTIME_ROLE_ART_RESULT ",JSON.stringify(result))
	app.queue_free()
	await frames()
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_basic_detail_clock() -> void:
	# Pure presentation fixtures: callbacks and the existing feedback clock are
	# real, while enemies only provide stable card candidates. No native AI claim.
	for hero: String in Catalog.HEROES:
		var preview := PreviewRoom.new()
		var player := PreviewPlayer.new()
		player.hero = hero
		preview.player = player
		preview.add_child(player)
		preview.add_child(preview.enemies)
		add_child(preview)
		var feedback: HeroFeedback = BasicFeedback.new()
		player.add_child(feedback)
		feedback.configure(player)
		feedback.hide()
		if hero == "CH01":
			_check_warrior_weapon_anchors(player,feedback)
			feedback.advance(.04) # The final anchor fixture ended at .27, still recovery.
		for index: int in 3:
			var enemy := PreviewEnemy.new()
			enemy.position = Vector2(30+index*10,0)
			preview.enemies.add_child(enemy)
			if index == 2: player._automatic_attack_target = weakref(enemy)
		var idle: Array[int] = SkillPresentation.detail_candidates(preview)
		check(idle.size() == 2 and idle[0] == player._automatic_attack_target.get_ref().get_instance_id(),hero+" idle retains two-card budget and actual target priority")
		feedback.observe_basic("attack_windup",.16,Vector2.RIGHT)
		feedback.advance(.08)
		check(SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview).is_empty(),hero+" actual recorded basic windup suppresses card/nameplate predicate")
		player.visual_hitstop = .05
		var age: float = feedback._basic_age
		feedback.advance(.2)
		check(feedback._basic_age == age and SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview).is_empty(),hero+" hitstop freezes basic age and keeps text suppressed")
		player.visual_hitstop = 0.0
		feedback.advance(.08)
		check(not SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview) == idle,hero+" expired windup restores unchanged idle candidates")
		feedback.observe_basic("attack_strike",.29,Vector2.RIGHT)
		feedback.advance(.04)
		check(SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview).is_empty(),hero+" actual basic release suppresses card/nameplate predicate")
		feedback.advance(.12)
		check(SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview).is_empty(),hero+" actual basic recovery still suppresses text")
		feedback.advance(.14)
		check(not SkillPresentation.basic_in_progress(player) and SkillPresentation.detail_candidates(preview) == idle,hero+" basic recovery ending restores unchanged idle candidates")
		player.dash_remaining = .1
		check(SkillPresentation.detail_candidates(preview).is_empty(),hero+" existing dash suppression remains")
		player.dash_remaining = 0.0
		player.abilities.active = {"spec":{}}
		check(SkillPresentation.detail_candidates(preview).is_empty(),hero+" existing committed skill suppression remains")
		preview.free()

func _check_warrior_weapon_anchors(player: PreviewPlayer, feedback: HeroFeedback) -> void:
	feedback.configure(player)
	var front: Node2D = feedback.get_node_or_null("WarriorBasicBlade") as Node2D
	check(front != null and feedback.find_children("WarriorBasicBlade","Node2D",false,false).size() == 1 and not front.z_as_relative and front.z_index == 3 and front.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"repeated warrior configure preserves one absolute z3 mip-filtered basic blade")
	var paths: Dictionary = {}
	var instances: Dictionary = {}
	var hashes: Dictionary = {}
	for heading: String in SharedArt.DIRECTIONS:
		var identity: String = "asset://heroes/ch01_basic_slash_"+heading.to_lower()+".png"
		var texture: Texture2D = BasicFeedback._basic_slash_textures.get(identity)
		check(texture != null and texture.get_size() == Vector2(1254,1254),heading+" production slash texture has actual native 1254 square size")
		if texture == null: continue
		slash_texture_ids[identity] = str(texture.get_instance_id())
		instances[str(texture.get_instance_id())] = true
		var bitmap: Image = texture.get_image()
		check(bitmap != null and bitmap.has_mipmaps(),heading+" admitted slash texture has mipmaps")
		var path: String = AssetCatalog.resolve(identity)
		paths[path] = true
		check(path == "res://assets/characters/warrior/fx/directional/slash_"+heading.to_lower()+".png",heading+" stable slash identity resolves to its independent authored PNG")
		var original := Image.new()
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		slash_source_hashes[identity] = digest.finish().hex_encode()
		hashes[slash_source_hashes[identity]] = true
		var decoded: Error = original.load_png_from_buffer(bytes)
		check(decoded == OK and original.get_size() == Vector2i(1254,1254) and original.get_pixel(0,0).a < .01,heading+" independent source retains native size and transparent canvas")
	check(paths.size() == 8 and instances.size() == 8 and hashes.size() == 8 and BasicFeedback._basic_slash_textures.size() == 8,"eight authored directions use eight distinct source hashes and admitted textures, not one rotated source")
	feedback.configure(player)
	for identity: String in slash_texture_ids:
		check(str(BasicFeedback._basic_slash_textures[identity].get_instance_id()) == str(slash_texture_ids[identity]),identity+" reconfigure reuses its existing static cache")
	for index: int in 8:
		var direction := Vector2.from_angle(index*PI/4.0)
		for phase: String in ["windup","release"]:
			var sampled: Dictionary = HeroArt.warrior_basic_weapon_anchors(direction,phase)
			var pose := {"phase":phase,"slot":"basic","skill_id":"","progress":1.0 if phase == "windup" else 0.0,"direction":direction}
			var frame: Dictionary = HeroArt.presentation_frame_info("CH01","back" if direction.y < -.20 else "front",pose,0.0,false)
			var transform: Transform2D = HeroArt.body_transform(frame,"CH01",direction,-direction*4.0 if phase == "windup" else direction*5.0,pose)
			check(not sampled.is_empty() and int(frame.frame_index)%8 == (3 if phase == "windup" else 4) and Vector2(sampled.grip).is_equal_approx(transform*Vector2(frame.anchors.grip)) and Vector2(sampled.muzzle).is_equal_approx(transform*Vector2(frame.anchors.muzzle)),SharedArt.DIRECTIONS[index]+" actual "+phase+" weapon anchors share the authored body's transform")
		player.aim_direction = -direction
		player.set_meta("hero_muzzle_local",Vector2(999,999))
		feedback.observe_basic("attack_strike",.29,direction)
		var effect: Dictionary = feedback.effects.back()
		var release: Dictionary = HeroArt.warrior_basic_weapon_anchors(direction,"release")
		check(Vector2(effect.weapon_end).is_equal_approx(release.muzzle) and Vector2(effect.weapon_grip).is_equal_approx(release.grip) and Vector2(effect.weapon_start).is_finite() and Vector2(effect.direction).is_equal_approx(direction),SharedArt.DIRECTIONS[index]+" real strike freezes committed release anchors rather than previous rendered metadata/live aim")
		var heading: String = SharedArt.DIRECTIONS[index]
		check(str(effect.slash_direction) == heading and str(effect.slash_texture_id) == "asset://heroes/ch01_basic_slash_"+heading.to_lower()+".png" and Vector2(effect.slash_size) == BasicFeedback.BASIC_SLASH_LAYOUTS[heading].size and Vector2(effect.slash_offset) == BasicFeedback.BASIC_SLASH_LAYOUTS[heading].offset,heading+" real strike records independent texture and authored pose layout")
		var frozen: Vector2 = effect.weapon_end
		player.aim_direction = direction.orthogonal()
		feedback.advance(.04)
		check(Vector2(effect.weapon_end) == frozen and feedback.effects.has(effect),SharedArt.DIRECTIONS[index]+" legitimate release peak keeps the frozen source")
		feedback.advance(.23)
		check(not feedback.effects.has(effect),SharedArt.DIRECTIONS[index]+" blade expires on the existing finite feedback clock")
	check(HeroArt.warrior_basic_weapon_anchors(Vector2.RIGHT,"recovery").is_empty(),"weapon sampling rejects unsupported phase")

func _gallery(hero: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var gallery := FamilyGallery.new()
	gallery.family = SharedArt.load_family(hero)
	gallery.size = Vector2(1280,720)
	layer.add_child(gallery)
	add_child(layer)
	await frames()
	await capture(hero+"-source-gallery")
	DisplayServer.window_set_size(Vector2i(2560,1440))
	await frames(4)
	await capture(hero+"-2k-source-gallery")
	DisplayServer.window_set_size(Vector2i(1280,720))
	get_window().position = DisplayServer.screen_get_usable_rect().position+(DisplayServer.screen_get_usable_rect().size-get_window().size)/2
	layer.queue_free()
	await frames()

func _wait_native(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0 and Game.run != null:
		await get_tree().physics_frame
		remaining -= 1.0/60.0

func _live_art(hero: String) -> void:
	app._start_run()
	await frames()
	if app.find_child("ConfirmWishDeparture",true,false) != null: check(await click("ConfirmWishDeparture"),"actual departure confirmation")
	await dismiss_offers()
	check(Game.run != null and is_instance_valid(app.room) and app.modals.is_empty(),hero+" real Main creates an unobstructed entrance")
	if Game.run == null or not is_instance_valid(app.room): return
	row = {"hero":hero,"poses":{},"directions":{},"source_paths":{},"frames":[],"guard_release":false,"reload_observed":false,"primary_projectiles":0,"muzzle_samples":[],"basic_visual_captures":[]}
	observed_frames.clear()
	observed_art_releases.clear()
	observed_art_projectiles.clear()
	elapsed = 0.0
	driver = Driver.new()
	driver.configure(app.room)
	active = true
	autoplay = false
	for index: int in 8:
		var direction: Vector2 = Vector2.from_angle(index*PI/4.0)
		driver.aim(app.room.player.position+direction*100.0)
		await frames(3)
		while app.room.player.shot_cooldown > 0.0 or app.room.player.abilities.busy(): await _wait_native(.05)
		check(app.room.player.request_attack(direction),hero+" native primary input accepted for "+SharedArt.DIRECTIONS[posmod(roundi(direction.angle()/(PI/4.0)),8)])
		await _wait_native(.85)
	await _wait_native(.2 if warrior_feedback_probe else 1.2)
	var player: HeroActor = app.room.player
	var primary_serial: int = player._primary_serial
	var primary_projectiles: int = int(row.primary_projectiles)
	await _wait_native(.6)
	check(player._primary_serial == primary_serial and int(row.primary_projectiles) == primary_projectiles,hero+" released inputs produce no extra autonomous primary cycle")
	if hero in ["CH02","CH03"]: check(primary_projectiles == 8,hero+" eight accepted native basic inputs create exactly eight original projectiles")
	if not warrior_feedback_probe:
		for heading: String in SharedArt.DIRECTIONS: check(row.directions.has(heading),hero+" actual actor renders authored heading "+heading)
		var destination: Vector2 = player.position+Vector2(130,0)
		check(app.room.valid_ground(destination,Balance.PLAYER_RADIUS) and player.request_move(destination,false),hero+" native navigation starts within the entrance")
		await _wait_native(1.6)
		player.clear_movement_target()
		driver.aim(player.position+Vector2(100,0))
		await frames(3)
		check(player.start_dash(Vector2.RIGHT),hero+" native dash input accepted")
		await _wait_native(.5)
		await capture(hero+"-live-entrance")
	check(await advance(),hero+" actual route UI enters native combat for the guard pose")
	if Game.run != null and is_instance_valid(app.room):
		driver.configure(app.room)
		driver.coverage = {}
		for identity: String in Game.run.skill_loadout_snapshot: driver.coverage[identity] = false
		autoplay = true
		var remaining := 60.0
		var route_changes := 0
		while remaining > 0.0 and Game.run != null and Game.run.hp > 0.0 and not _probe_complete(hero):
			await _wait_native(.1)
			remaining -= .1
			if warrior_feedback_probe and not warrior_2k_ready and _warrior_phase_captures_saved():
				DisplayServer.window_set_size(Vector2i(2560,1440))
				get_window().position = DisplayServer.screen_get_usable_rect().position+(DisplayServer.screen_get_usable_rect().size-get_window().size)/2
				await frames(4)
				warrior_2k_after_serial = app.room.player._primary_serial
				warrior_2k_ready = true
			if Game.run != null and app.expedition.current_complete() and route_changes < 3:
				if await advance(): driver.configure(app.room); route_changes += 1
		row["native_route_changes"] = route_changes
		autoplay = false
		if warrior_feedback_probe and Game.run != null:
			app.room.player.clear_movement_target()
			await _wait_native(.45)
			check(not SkillPresentation.basic_in_progress(app.room.player),"native released inputs return to idle object/nameplate visibility predicate")
			await capture("CH01-warrior-native-idle-labels")
		elif not warrior_feedback_probe: await capture(hero+"-live-combat")
	active = false
	for pose_name: String in (["basic_windup","basic_release","basic_recovery"] if warrior_feedback_probe else ["walk_left","walk_right","basic_windup","basic_release","basic_recovery","dash","guard_cast"]): check(row.poses.has(pose_name),hero+" actual native action rendered "+pose_name)
	if not warrior_feedback_probe: check(bool(row.guard_release),hero+" actual guard-class skill reached a production release")
	if hero == "CH01": check(_probe_complete(hero) if warrior_feedback_probe else captured_visuals.has("warrior-basic-release-mid") and captured_visuals.has("warrior-basic-contact"),"warrior swing phases and confirmed native primary contact have actual rendered captures")
	if hero == "CH02": check(bool(row.reload_observed),"gunner native eight-shot magazine renders its own reload pose")
	if hero == "CH03": check(is_instance_valid(app.room) and is_instance_valid(app.room.player) and app.room.player.find_children("StarCompanion","Node2D",true,false).size() == 1,"mage has one live companion; its body never falls back to the old engineer")
	rows.append(row.duplicate(true))

func _probe_complete(hero: String) -> bool:
	if warrior_feedback_probe: return _warrior_phase_captures_saved() and str(captured_visuals.get("warrior-basic-2k-contact","")) == "saved"
	return bool(row.guard_release) and row.poses.has("guard_cast") and (hero != "CH01" or captured_visuals.has("warrior-basic-contact"))

func _warrior_phase_captures_saved() -> bool:
	for name_value: String in WARRIOR_PEAK_CAPTURES.values():
		if str(captured_visuals.get(name_value,"")) != "saved": return false
	return str(captured_visuals.get("warrior-basic-contact","")) == "saved" and str(captured_visuals.get("warrior-basic-recovery","")) == "saved"

func _physics_process(delta: float) -> void:
	if not active or Game.run == null or not is_instance_valid(app.room): return
	elapsed += delta
	var player: HeroActor = app.room.player
	if not is_instance_valid(player): return
	if autoplay: driver.step(elapsed)
	if Game.run == null or not is_instance_valid(app.room): return
	if autoplay and app.room._living_enemy_count() == 0 and not app.room.objective_complete and app.room.controls_enabled():
		var destination: Dictionary = app.room.navigation_target()
		if destination.has("position"):
			var at: Vector2 = destination.position
			if player.position.distance_to(at) > 65.0: driver.navigate_to_reachable(elapsed,at,45.0,driver.visible_threats())
			else: player.clear_movement_target(); app.room.interact()
	for projectile: Node in app.room.projectiles.get_children():
		if not projectile.has_method("visual_path_snapshot") or str(projectile.get("source")) != "primary" or observed_art_projectiles.has(projectile.get_instance_id()): continue
		observed_art_projectiles[projectile.get_instance_id()] = true
		row.primary_projectiles += 1
		var path: Dictionary = projectile.visual_path_snapshot()
		if row.muzzle_samples.size() < 8 and not path.is_empty(): row.muzzle_samples.append({"t":elapsed,"origin":str(path.get("origin",Vector2.ZERO)),"visual_start":str(path.get("knots",[{}])[0].get("point",Vector2.ZERO)),"direction":str(projectile.direction),"hero_body_muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO))})
	if Game.run.hero_id == "CH02" and bool(player.class_state_view().get("reloading",false)): row.reload_observed = true
	for event: Dictionary in player.abilities.feedback.release_events:
		var key: String = str(event.serial)+":"+str(event.index)
		if observed_art_releases.has(key): continue
		observed_art_releases[key] = true
		var identity: String = str(event.skill_id)
		if driver.coverage.has(identity): driver.coverage[identity] = true
		if identity == Game.run.hero_id+"_SK03": row.guard_release = true

func _process(_delta: float) -> void:
	if not active or Game.run == null or not is_instance_valid(app.room): return
	var player: HeroActor = app.room.player
	if not is_instance_valid(player): return
	if Game.run.hero_id == "CH01": _observe_warrior_captures(player)
	var source: String = str(player.get_meta("hero_visual_source",""))
	var index: int = int(player.get_meta("hero_visual_frame",-1))
	var heading: String = str(player.get_meta("hero_directional_key",""))
	if source.is_empty() or index < 0: return
	var key: String = str(player.get_instance_id())+":"+source+":"+str(index)
	if observed_frames.has(key): return
	observed_frames[key] = true
	check(source.begins_with("asset://heroes/"+Game.run.hero_id.to_lower()+"_poses_") and SharedArt.DIRECTIONS.has(heading),Game.run.hero_id+" actual drawn body uses only its complete new PNG family")
	var transform: Transform2D = player.get_meta("hero_body_transform",Transform2D.IDENTITY)
	check(float(player.get_meta("hero_visual_flip",0.0)) == 1.0 and transform.x.is_equal_approx(Vector2.RIGHT) and transform.y.is_equal_approx(Vector2.DOWN) and Vector2(player.get_meta("hero_foot_local",Vector2.INF)).is_equal_approx(Vector2(0,8)),Game.run.hero_id+" actual drawn body has no mirroring, rotation or foot drift")
	var pose_name: String = SharedArt.POSES[posmod(index,8)]
	row.poses[pose_name] = true
	row.directions[heading] = true
	row.source_paths[source] = true
	row.frames.append({"t":elapsed,"source":source,"frame":index,"heading":heading,"pose":pose_name,"muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO)),"foot":str(player.get_meta("hero_foot_local",Vector2.ZERO))})

func _observe_warrior_captures(player: HeroActor) -> void:
	if warrior_feedback_probe:
		for effect: Dictionary in player.abilities.feedback.effects:
			if str(effect.get("kind","")) != "swing" or str(effect.get("slot","")) != "basic": continue
			var age: float = float(effect.get("age",0.0))
			var heading: String = SharedArt.DIRECTIONS[posmod(roundi(Vector2(effect.direction).angle()/(PI/4.0)),8)]
			var name_value: String = WARRIOR_PEAK_CAPTURES[heading]
			if not captured_visuals.has(name_value) and age >= .02 and age <= .045: _queue_warrior_capture(name_value,effect)
			if not captured_visuals.has("warrior-basic-recovery") and age >= .10 and age <= .13: _queue_warrior_capture("warrior-basic-recovery",effect)
		if not captured_visuals.has("warrior-basic-contact") and is_instance_valid(app.room.impact_feedback):
			for event: Dictionary in app.room.impact_feedback.events:
				if str(event.get("hero_id","")) == "CH01" and str(event.get("source","")) == "primary" and not bool(event.get("passive",true)) and float(event.get("hp_damage",0.0)) > 0.0 and float(event.get("age",0.0)) >= .025 and float(event.get("age",0.0)) <= .045:
					_queue_warrior_capture("warrior-basic-contact",event)
					break
		if warrior_2k_ready and player._primary_serial > warrior_2k_after_serial and not captured_visuals.has("warrior-basic-2k-contact") and is_instance_valid(app.room.impact_feedback):
			for event: Dictionary in app.room.impact_feedback.events:
				if str(event.get("hero_id","")) == "CH01" and str(event.get("source","")) == "primary" and not bool(event.get("passive",true)) and float(event.get("hp_damage",0.0)) > 0.0 and float(event.get("age",0.0)) >= .025 and float(event.get("age",0.0)) <= .045:
					_queue_warrior_capture("warrior-basic-2k-contact",event)
					break
		return
	if not captured_visuals.has("warrior-basic-release-mid"):
		for effect: Dictionary in player.abilities.feedback.effects:
			if str(effect.get("kind","")) != "swing" or str(effect.get("slot","")) != "basic" or float(effect.get("age",0.0)) < .10 or float(effect.get("age",0.0)) > .16: continue
			_queue_warrior_capture("warrior-basic-release-mid",{"kind":"swing","age":effect.age,"variant":effect.get("variant",-1),"at":str(effect.at),"direction":str(effect.direction),"radius":effect.radius,"arc":effect.arc,"body":str(player.get_meta("hero_visual_source",""))})
			break
	if not captured_visuals.has("warrior-basic-contact") and is_instance_valid(app.room.impact_feedback):
		for event: Dictionary in app.room.impact_feedback.events:
			if str(event.get("hero_id","")) != "CH01" or str(event.get("source","")) != "primary" or bool(event.get("passive",true)) or float(event.get("hp_damage",0.0)) <= 0.0 or float(event.get("age",0.0)) < .025 or float(event.get("age",0.0)) > .065: continue
			_queue_warrior_capture("warrior-basic-contact",{"kind":"confirmed_primary_contact","serial":event.serial,"age":event.age,"variant":event.get("basic_variant",-1),"hp_damage":event.hp_damage,"at":str(app.room.impact_feedback.contact_position(event)),"direction":str(event.direction),"body":str(player.get_meta("hero_visual_source",""))})
			break

func _queue_warrior_capture(name_value: String, evidence: Dictionary) -> void:
	captured_visuals[name_value] = true
	if warrior_feedback_probe:
		_capture_warrior_frame.call_deferred(name_value,evidence)
		return
	row.basic_visual_captures.append(evidence)
	capture.call_deferred("CH01-"+name_value)

func _capture_warrior_frame(name_value: String, event: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	if not active or Game.run == null or not is_instance_valid(app.room) or not is_instance_valid(app.room.player): return
	var player: HeroActor = app.room.player
	var age: float = float(event.get("age",-1.0))
	# Avoid calling a recovery screenshot a release if a frame was delayed.
	if (name_value.ends_with("release-peak") or name_value.ends_with("contact")) and (age < .025 or age > .065):
		captured_visuals.erase(name_value)
		return
	if not SkillPresentation.basic_in_progress(player):
		captured_visuals.erase(name_value)
		return
	var evidence := {"capture":name_value,"render_frame":Engine.get_frames_drawn(),"t":elapsed,"primary_serial":player._primary_serial,"effect_kind":str(event.get("kind","confirmed_primary_contact")),"effect_age":age,"basic_age":player.abilities.feedback._basic_age,"body":str(player.get_meta("hero_visual_source","")),"frame":int(player.get_meta("hero_visual_frame",-1)),"render_pose":str(player.get_meta("hero_visual_pose","")),"heading":str(player.get_meta("hero_directional_key","")),"foot":str(player.get_meta("hero_foot_local",Vector2.ZERO)),"grip":str(player.get_meta("hero_grip_local",Vector2.ZERO)),"muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO)),"effect_origin":str(event.get("at",Vector2.ZERO)),"effect_direction":str(event.get("direction",Vector2.ZERO)),"text_suppressed":SkillPresentation.basic_in_progress(player),"detail_candidates":SkillPresentation.detail_candidates(app.room).size(),"hp_damage":float(event.get("hp_damage",0.0)),"variant":int(event.get("variant",event.get("basic_variant",-1)))}
	for anchor_name: String in ["weapon_start","weapon_end","weapon_grip"]:
		if event.has(anchor_name): evidence[anchor_name] = str(event[anchor_name])
	var front: Node2D = player.abilities.feedback.get_node_or_null("WarriorBasicBlade") as Node2D
	evidence["front_node_count"] = player.abilities.feedback.find_children("WarriorBasicBlade","Node2D",false,false).size()
	evidence["front_z"] = front.z_index if front != null else -99
	evidence["front_absolute"] = front != null and not front.z_as_relative
	check(int(evidence.front_node_count) == 1 and int(evidence.front_z) == 3 and bool(evidence.front_absolute),"actual warrior uses one bounded absolute front blade")
	var slash_effect: Dictionary = event if event.has("slash_texture_id") else {}
	if slash_effect.is_empty():
		for possible: Dictionary in player.abilities.feedback.effects:
			if possible.has("slash_texture_id"): slash_effect = possible
	var slash_identity: String = str(slash_effect.get("slash_texture_id",""))
	var texture: Texture2D = BasicFeedback._basic_slash_textures.get(slash_identity)
	evidence["slash_direction"] = str(slash_effect.get("slash_direction",""))
	evidence["slash_texture_id"] = slash_identity
	evidence["slash_source_instance"] = str(texture.get_instance_id()) if texture != null else "0"
	evidence["slash_source_sha256"] = str(slash_source_hashes.get(slash_identity,""))
	evidence["slash_native_size"] = str(texture.get_size()) if texture != null else "missing"
	evidence["slash_size"] = str(slash_effect.get("slash_size",Vector2.ZERO))
	evidence["slash_offset"] = str(slash_effect.get("slash_offset",Vector2.ZERO))
	check(texture != null and slash_texture_ids.has(slash_identity) and str(evidence.slash_source_instance) == str(slash_texture_ids[slash_identity]),"native directional slash reuses its admitted texture cache")
	check(front != null and front.transform.x.is_equal_approx(Vector2.RIGHT) and front.transform.y.is_equal_approx(Vector2.DOWN),"actual directional slash layer is not rotated or mirrored")
	if name_value.ends_with("release-peak"): check(str(evidence.slash_direction) == str(evidence.heading),"actual peak selects the matching authored body and slash heading")
	check(bool(evidence.text_suppressed) and int(evidence.detail_candidates) == 0,"actual rendered basic "+name_value+" suppresses nameplate/detail predicate")
	if name_value.ends_with("release-peak"): check(int(evidence.frame)%8 == 4 and float(evidence.basic_age) < .09,"peak screenshot samples the actual basic release body")
	if name_value.ends_with("recovery"): check(int(evidence.frame)%8 == 5 and float(evidence.basic_age) >= .09 and float(evidence.basic_age) < .29,"recovery screenshot samples the actual basic recovery body")
	if name_value.contains("-2k-"): check(player._primary_serial > warrior_2k_after_serial,"2K contact comes from a later lawful native primary input")
	row.basic_visual_captures.append(evidence)
	_save_capture("CH01-"+name_value)
	captured_visuals[name_value] = "saved"
