extends Node
## Focused structural checks; graphics run only when explicitly scheduled.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Review = preload("res://scripts/levels/b07/art/l37_convergence_environment.gd")
const Fx = preload("res://scripts/levels/b07/art/l37_review_fx.gd")
const Skills = preload("res://scripts/levels/b07/combat/enemy_skills.gd")
const Actors = preload("res://scripts/levels/b07/art/actor_review.gd")
const CardLayout = preload("res://scripts/levels/b07/art/l37_skill_card_layout.gd")
const Cards = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const PropSkins = preload("res://scripts/levels/b07/art/l37_prop_skins.gd")
var failures := 0
var capture_room: Node2D
var capture_wait_checks := 0
var capture_integrity: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("L37 CONVERGENCE: "+label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(1280,720)
	await get_tree().process_frame
	var out := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if out.is_empty() or not Game.profile_path.begins_with("user://test_b07_candidate/"):
		get_tree().quit(2)
		return
	var launch := Launcher.new()
	launch.auto_start = false
	launch.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(launch)
	check(launch.start_candidate("CH01",0,false),"isolated launcher: "+launch.last_error)
	if not is_instance_valid(launch.room):
		launch.free()
		get_tree().quit(1)
		return
	var room: Node2D = launch.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.camera.process_mode = Node.PROCESS_MODE_DISABLED
	# Runtime explicitly chooses PAUSABLE and does not inherit room.DISABLED.
	room.enemy_skills.process_mode = Node.PROCESS_MODE_DISABLED
	capture_room = room
	room.combat_audio.audible = false
	var backdrop: Node2D = room.get_node("MineBackdrop")
	if Review.requested():
		check(is_instance_valid(backdrop.b07_art_trial) and backdrop.b07_art_trial.get("review_ready") == true,"new review environment installed")
		if is_instance_valid(backdrop.b07_art_trial) and backdrop.b07_art_trial.get("review_ready") == true:
			var art: Node2D = backdrop.b07_art_trial
			check(art.review_components.is_empty(),"unsupported four-piece collage withdrawn")
			check(not art.get_node("NorthCityCompositionReview").visible,"failed RGB crop not visible")
			var foundation: Node2D = art.foundation
			check(foundation.visible,"review foundation visible")
			check(foundation.get_script().resource_path.ends_with("l37_review_foundation.gd"),"oblique review foundation installed")
			var west_face := false
			for face: Dictionary in foundation.faces:
				var edge: Array = face.blueprint_edge
				var authored: Array=Geometry.room("L37").walkable_polygon
				if edge == [Vector2(authored[-1][0],authored[-1][1]),Vector2(authored[0][0],authored[0][1])]: west_face = true
				check(Vector2(face.polygon[0]).is_equal_approx(Vector2(edge[0])*Geometry.SCALE),"foundation original first ground contact")
				check(Vector2(face.polygon[1]).is_equal_approx(Vector2(edge[1])*Geometry.SCALE),"foundation original second ground contact")
				check((Vector2(face.polygon[2])-Vector2(face.polygon[1])).is_equal_approx(Vector2(-140,260)*Geometry.SCALE),"review exterior extrusion")
				for overlap: PackedVector2Array in Geometry2D.intersect_polygons(face.polygon,room.ground_polygon):
					check(Geometry.area(overlap)<.01,"foundation never overlaps walkable floor")
			check(west_face,"west side has an exterior cliff face")
			for child: Node in art.get_children():
				if child != foundation and child.get_script() == preload("res://scripts/levels/b07/art/terrace_foundation.gd"):
					check(not child.visible,"old vertical foundation hidden")
			for layer: Sprite2D in art.layers:
				if layer.name == "WalkableTerrace":
					check(layer.material.shader.resource_path.ends_with("l37_review_ground.gdshader"),"ground uses review-only broad illumination")
	else:
		check(not is_instance_valid(backdrop.b07_art_trial) or backdrop.b07_art_trial.get("review_ready") != true,"new assembly stays opt-in")
	check(room.ground_polygon == Geometry.polygon("L37"),"original walkable polygon")
	check(room.layout.obstructions.size() == 2,"original two collision covers")
	check(room.player.position == Geometry.world_point([320,900]),"actual player entry")
	check(room.exit_position == Geometry.world_point([2480,900]),"actual exit")
	if Review.requested():
		room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
		check(room.camera.b07_north_review,"existing north-follow camera preserved")
		check(room.camera.position == room.player.position+Vector2(160,-160),"actual player-follow offset")
		check(room.camera.zoom.is_equal_approx(Vector2(.72,.72)),"existing camera scale")
		_check_fx(room)
		_check_actors(room)
		_check_prop_skins(room)
	else:
		check(not Fx.enabled(room.enemy_skills),"new effects stay opt-in")
		check(PropSkins.skin_recipes(room).is_empty(),"new mechanism skins stay opt-in")
		for actor: Node2D in room.enemies.get_children():
			check(not Actors.enabled_for(actor),"new actor review stays opt-in")
			var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
			var temporary_badge := badge == null
			if temporary_badge:
				badge=Node2D.new()
				actor.add_child(badge)
			check(CardLayout.placement(badge).is_empty(),"review card placement stays opt-in")
			if temporary_badge: badge.free()
	if DisplayServer.get_name() != "headless" and "--b07-review-capture" in OS.get_cmdline_user_args():
		check(Review.requested(),"capture requires complete review opt-in")
		get_window().content_scale_size = Vector2i(1280,720)
		get_window().size = Vector2i(2560,1440)
		await get_tree().process_frame
		room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await _save_frame(out,"L37_convergence_entry_follow.png")
		var extent: Vector2 = get_viewport().get_visible_rect().size/room.camera.zoom
		print("L37 REVIEW actual view=",Rect2(room.camera.get_screen_center_position()-extent*.5,extent)," zoom=",room.camera.zoom)
		if "--b07-review-actions" in OS.get_cmdline_user_args():
			await _directed_actions(room,out,true)
	elif "--b07-review-actions-check" in OS.get_cmdline_user_args():
		await _directed_actions(room,out,false)
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	launch.free()
	Game.run = null
	if "--b07-review-dodge-check" in OS.get_cmdline_user_args() or "--b07-review-dodge-capture" in OS.get_cmdline_user_args():
		var capture_dodge := "--b07-review-dodge-capture" in OS.get_cmdline_user_args()
		check(not capture_dodge or DisplayServer.get_name() != "headless","dodge capture requires graphical renderer")
		await _movement_dodge(out,capture_dodge and DisplayServer.get_name() != "headless")
	if capture_wait_checks>0:
		var integrity_file := FileAccess.open(out.path_join("L37_capture_integrity_report.json"),FileAccess.WRITE)
		check(integrity_file != null,"write capture integrity report")
		if integrity_file != null:
			integrity_file.store_string(JSON.stringify({"wait_checks":capture_wait_checks,"frames":capture_integrity,"failures":failures},"  "))
			integrity_file.close()
	print("L37 CONVERGENCE checks, failures=",failures,"; full continuous animations=0; visual acceptance pending")
	get_tree().quit(1 if failures else 0)

func _check_fx(room: Node2D) -> void:
	var runtime: Node2D = room.enemy_skills
	var checked_identities: Array[String] = []
	check(Fx.enabled(runtime),"effects require actual L37 runtime")
	var detached := Node2D.new()
	check(not Fx.enabled(detached),"detached preview cannot enable effects")
	detached.free()
	for actor: Node2D in room.enemies.get_children():
		checked_identities.append(str(actor.enemy_id))
		var command: Dictionary = Skills.active(actor.profile,actor.position,room.player.position,false)
		var untouched := command.duplicate(true)
		check(Fx.effect_spec(runtime,command).is_empty(),"warning never displays release art")
		var visual := command.duplicate(true)
		visual.merge({"color":Color.WHITE,"remaining":.22},true)
		if actor.enemy_id == "B07-M01":
			check(Fx.effect_spec(runtime,visual).get("id","") == "spear_impact","actual spear release mapping")
			var tail := Skills.child(visual,"melee","cone",40,.8)
			tail.merge({"color":Color.WHITE,"remaining":.22},true)
			check(Fx.effect_spec(runtime,tail).is_empty(),"tail has no invented texture")
		elif actor.enemy_id == "B07-M02":
			check(Fx.effect_spec(runtime,visual).get("id","") == "sand_landing","actual landing mapping")
			var ball := Skills.area(command,command.target,50,30,.8)
			ball.merge({"lob":true,"color":Color.WHITE,"remaining":.22},true)
			check(Fx.effect_spec(runtime,ball).get("id","") == "sand_ball","actual ground-area followup mapping")
			check(Fx.projectile_spec(runtime,ball).is_empty(),"sand ball does not invent projectile")
		elif actor.enemy_id == "B07-M03":
			visual.position = actor.position
			var spec := Fx.projectile_spec(runtime,visual)
			check(spec.get("id","") == "sand_disc" and spec.get("position") == actor.position,"disc follows actual shot position")
			check(Fx.projectile_spec(runtime,visual,true).is_empty(),"reduced FX uses procedural fallback")
		check(Fx.effect_spec(runtime,visual,true).is_empty(),"reduced release uses procedural fallback")
		check(command == untouched,"presentation leaves real command unchanged")
	for identity: String in ["B07-M01","B07-M02","B07-M03"]:
		check(identity in checked_identities,"actual initial encounter contains "+identity)

func _check_actors(room: Node2D) -> void:
	var frame_count := 0
	for actor: Node2D in room.enemies.get_children():
		check(Actors.enabled_for(actor),"actual encounter identity is review-enabled")
		var bank: Dictionary = actor.body_visual._bank
		check(bank.get("b07_review_bank",false),"native review bank installed: "+actor.enemy_id)
		if not bank.get("b07_review_bank",false): continue
		check(bank.get("continuous_animation_sets_complete",-1) == 0,"no complete-animation claim")
		check(not bank.clips.has("walk"),"no fabricated walk clip")
		check(actor.body_visual._foot == Vector2.ZERO,"review ground root aligns physical anchor")
		var initial: Dictionary = actor.body_visual.selected_frame
		for pose: String in bank.clips:
			frame_count += 1
			var frame: Dictionary = bank.clips[pose][0]
			actor.body_visual.selected_frame = frame
			var body: Dictionary = actor.body_visual.body_frame()
			var factor: float = body.bounds.size.y/body.region.size.y
			var mapped_root: Vector2 = body.bounds.position+(Vector2(frame.foot)-body.region.position)*factor
			check(mapped_root.is_zero_approx(),"source root maps to origin: "+actor.enemy_id+" "+pose)
			check(body.get("full_color",false),"original body colors: "+pose)
			check(absf(factor*float(bank.body_height)-float(bank.world_reference_height)*float(frame.source_pose_scale))<.001,"anatomy ratio, not pose height: "+pose)
		actor.body_visual.selected_frame = initial
		# Read-only selection contract: inject authored commands into the frozen
		# brain for this check, never execute a cast, then restore its state.
		var saved_command: Dictionary = actor.brain._command
		var saved_phase: StringName = actor.brain.phase
		var authored: Dictionary = Skills.active(actor.profile,actor.position,room.player.position,false)
		actor.brain._command = authored
		for phase: StringName in [&"telegraph",&"locked",&"execute",&"recovery"]:
			actor.brain.phase = phase
			var expected: String = str(authored.ability_id).get_slice(":",1)+":"+("telegraph" if phase == &"locked" else str(phase))
			check(Actors.select_frame(actor,bank).get("name","") == expected,"authored phase selects key pose: "+expected)
		actor.brain._command = {}
		actor.brain.phase = &"chase"
		if actor.enemy_id == "B07-M03":
			var shot := authored.duplicate(true)
			shot.owner_id = actor.get_instance_id()
			room.enemy_skills.projectiles.append(shot)
			check(Actors.select_frame(actor,bank).get("name","") == "returning_disc:recovery","actual disc in flight stays empty-handed")
			room.enemy_skills.projectiles.erase(shot)
		actor.brain._command = saved_command
		actor.brain.phase = saved_phase
		var original_id: String = room.layout_id
		room.layout_id = "L38"
		check(not Actors.enabled_for(actor),"review excluded from another actual room")
		room.layout_id = original_id
	check(frame_count == 14,"exactly fourteen registered discrete key poses")
	# Actual-room gate also excludes another chapter and another B07 room.
	var previous_id: String = room.layout_id
	for other: String in ["L38","L01"]:
		room.layout_id=other
		check(not CardLayout.enabled(room) and not CardLayout.ensure(room),"card coordinator rejects another room/chapter: "+other)
	room.layout_id=previous_id


func _directed_actions(room: Node2D, out: String, capture: bool) -> void:
	# Directed isolated capture, not a natural-play claim. Keep the real player
	# at the original entrance and its real camera. Move only test enemies into
	# legal cast range, then advance their actual FSM and shared runtime.
	var offsets := {"B07-M01":Vector2(140,-60),"B07-M02":Vector2(110,120),"B07-M03":Vector2(210,-90)}
	for actor: Node2D in room.enemies.get_children():
		actor.position = room.player.position+Vector2(offsets[actor.enemy_id])
		actor.brain.configure(actor.profile)
		actor.brain.tick(actor,.81,room.player)
		check(str(actor.brain.phase) == "telegraph","actual FSM entered telegraph: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	_refresh_badges(room)
	_check_card_layout(room,2)
	if capture: await _save_frame(out,"L37_directed_telegraph.png")
	for actor: Node2D in room.enemies.get_children():
		var tell: Dictionary = actor.brain.current_skill()
		actor.brain.tick(actor,float(tell.get("remaining",0))+.01,room.player)
		check(str(actor.brain.phase) == "locked","actual FSM entered lock: "+actor.enemy_id)
		var locked: Dictionary = actor.brain.current_skill()
		actor.brain.tick(actor,float(locked.get("remaining",0))+.01,room.player)
		check(str(actor.brain.phase) == "execute","actual FSM released: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	_refresh_badges(room)
	_check_card_layout(room,2)
	var before_wait := _runtime_snapshot(room)
	await get_tree().create_timer(.05).timeout
	check(_runtime_snapshot(room) == before_wait,"real engine frames cannot advance frozen directed runtime")
	if capture: await _save_frame(out,"L37_directed_execute_start.png")
	room.enemy_skills.advance(.20)
	for actor: Node2D in room.enemies.get_children():
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	_refresh_badges(room)
	_check_card_layout(room,2)
	if capture: await _save_frame(out,"L37_directed_mid_motion.png")
	room.enemy_skills.advance(.21)
	for actor: Node2D in room.enemies.get_children():
		actor.brain.tick(actor,.42,room.player)
		check(str(actor.brain.phase) == "recovery","actual FSM recovery: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	_refresh_badges(room)
	_check_card_layout(room,2)
	if capture: await _save_frame(out,"L37_directed_landing_recovery.png")
	print("L37 DIRECTED ACTIONS: real FSM+runtime, moved enemies only; no natural-play or continuous-animation acceptance")

func _runtime_snapshot(room: Node2D) -> Dictionary:
	var runtime: Node2D = room.enemy_skills
	var actors: Array[Dictionary] = []
	for actor: Node2D in room.enemies.get_children():
		actors.append({"position":actor.position,"phase":str(actor.brain.phase),"age":actor.brain.age,"state":str(actor.state),"state_time":actor.state_time,"command":actor.brain.current_skill().duplicate(true)})
	return {"player":room.player.position,"velocity":room.player.velocity,"stride":room.player.stride,"immunity":room.player.invulnerable,"dash":room.player.dash_remaining,"hp":Game.run.hp,"shield":Game.run.shield,
		"clock":runtime._biome_clock,"jobs":runtime.jobs.duplicate(true),"projectiles":runtime.projectiles.duplicate(true),
		"hazards":runtime.hazards.duplicate(true),"motions":runtime.motions.duplicate(true),"visuals":runtime.visuals.duplicate(true),"supports":runtime.supports.duplicate(true),"marks":runtime.marks.duplicate(true),"actors":actors}

func _refresh_badges(room: Node2D) -> void:
	# Freeze the whole FSM cohort before deriving its ranked UI selection.
	for actor: Node2D in room.enemies.get_children():
		actor.body_visual._update_skill_badge()
		actor.queue_redraw()
	CardLayout.publish(room)

func _save_frame(out: String, filename: String) -> void:
	check(capture_room.enemy_skills.process_mode == Node.PROCESS_MODE_DISABLED,"snapshot runtime explicitly frozen")
	var before := _runtime_snapshot(capture_room)
	await RenderingServer.frame_post_draw
	check(_runtime_snapshot(capture_room) == before,"snapshot wait never advances combat: "+filename)
	capture_wait_checks += 1
	var shown := 0
	for actor: Node2D in capture_room.enemies.get_children():
		var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
		if badge != null and badge.visible and badge.show_detail: shown += 1
	var candidates := Cards.detail_candidates(capture_room).size()
	check(shown == candidates,"snapshot actual card count matches candidates: "+filename)
	capture_integrity.append({"file":filename,"combat_unchanged_during_wait":_runtime_snapshot(capture_room)==before,"visible_detail_cards":shown,"candidate_detail_cards":candidates})
	var image := get_viewport().get_texture().get_image()
	check(image.get_size() == Vector2i(2560,1440),"directed 2K frame")
	check(image.save_png(out.path_join(filename)) == OK,"save directed frame: "+filename)

func _movement_dodge(out: String, capture: bool) -> void:
	if capture:
		check(Review.requested(),"dodge capture requires complete review opt-in")
		get_window().content_scale_size = Vector2i(1280,720)
		get_window().size = Vector2i(2560,1440)
		await get_tree().process_frame
	# A separate directed sample. Fresh room/run; only M02 is staged before
	# warning. After lock, keyboard movement uses the unmodified hero physics
	# and room collision path. No dash, teleport, target rewrite or immunity.
	var launch := Launcher.new()
	launch.auto_start = false
	launch.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(launch)
	check(launch.start_candidate("CH01",0,false),"fresh dodge launcher: "+launch.last_error)
	if not is_instance_valid(launch.room):
		launch.free()
		return
	var room: Node2D = launch.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.camera.process_mode = Node.PROCESS_MODE_DISABLED
	# Runtime explicitly chooses PAUSABLE and does not inherit room.DISABLED.
	room.enemy_skills.process_mode = Node.PROCESS_MODE_DISABLED
	capture_room = room
	room.combat_audio.audible = false
	room._physics_process(.01) # Release the normal all-inputs-up entrance gate.
	check(room.controls_enabled(),"normal movement input enabled")
	check(room.enemy_skills.active_effect_count() == 0,"fresh dodge room has no old effects")
	check(room.player.invulnerable == 0 and room.player.dash_remaining == 0,"fresh player has no immunity or dash")
	var m02: Node2D
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id == "B07-M02": m02 = actor
	check(is_instance_valid(m02),"fresh M02 available")
	if not is_instance_valid(m02):
		launch.free()
		Game.run = null
		return
	m02.position = room.player.position+Vector2(110,120)
	m02.brain.configure(m02.profile)
	m02.brain.tick(m02,.81,room.player)
	check(str(m02.brain.phase) == "telegraph","dodge M02 real telegraph")
	m02.brain.tick(m02,float(m02.brain.current_skill().remaining)+.01,room.player)
	check(str(m02.brain.phase) == "locked","dodge M02 real lock")
	var locked: Dictionary = m02.brain.current_skill()
	var target: Vector2 = locked.target
	var hp_before: float = Game.run.hp
	var shield_before: float = Game.run.shield
	var start: Vector2 = room.player.position
	var zoom: Vector2 = room.camera.zoom
	var camera_offset: Vector2 = room.camera.position-room.player.position
	var trace: Array[Dictionary] = []
	var frames: Array[Dictionary] = []
	var elapsed := 0.0
	var midpoint_seen := false
	var released := false
	var landed := false
	var landing_position := Vector2.ZERO
	var landing_player := Vector2.ZERO
	var landing_time := 0.0
	await _dodge_frame(room,m02,out,"locked",capture,frames,elapsed)
	Input.action_press("move_right")
	# Fixed 10 ms simulation steps advance production paths exactly once.
	# Other enemies stay visible at their original encounter positions.
	for step in 160:
		room.player._physics_process(.01)
		m02.brain.tick(m02,.01,room.player)
		room.enemy_skills.advance(.01)
		elapsed += .01
		check(m02.brain.current_skill().get("target",target) == target,"M02 lock never retargets")
		check(room.player.invulnerable == 0 and room.player.dash_remaining == 0,"movement never uses immunity or dash")
		trace.append({"t":elapsed,"player":_xy(room.player.position),"velocity":_xy(room.player.velocity),"m02":_xy(m02.position),"phase":str(m02.brain.phase),"hp":Game.run.hp,"shield":Game.run.shield})
		if room.enemy_skills.has_motion(m02):
			released = true
			var motion: Dictionary = room.enemy_skills.motions[0]
			check(Vector2(motion.target) == target,"released motion retains frozen target")
			if not midpoint_seen and float(motion.elapsed) >= float(motion.duration)*.5-.0001:
				midpoint_seen = true
				await _dodge_frame(room,m02,out,"mid_motion",capture,frames,elapsed)
		elif released and not landed:
			landed = true
			landing_position = m02.position
			landing_player = room.player.position
			landing_time = elapsed
			Input.action_release("move_right")
			await _dodge_frame(room,m02,out,"landing",capture,frames,elapsed)
		if landed and str(m02.brain.phase) == "recovery" and elapsed >= landing_time+.12:
			await _dodge_frame(room,m02,out,"recovery",capture,frames,elapsed)
			break
	Input.action_release("move_right")
	check(released and midpoint_seen and landed,"dodge traverses real release/midpoint/landing")
	check(landing_position.distance_to(target)<.1,"actual landing matches immutable lock point")
	check(landing_player.distance_to(target)>float(locked.radius)+Balance.PLAYER_RADIUS,"normal movement clears landing hit area")
	check(room.player.position.distance_to(start)>55,"player genuinely moved")
	check(Game.run.hp == hp_before and Game.run.shield == shield_before,"landing avoided without HP or shield damage")
	check(room.camera.zoom == zoom,"dodge retains existing camera zoom")
	var report := {"sample":"directed_real_keyboard_movement","natural_play_acceptance":false,
		"fresh_room":true,"difficulty":0,"input":"move_right","movement_path":"HeroActor._physics_process -> room.move_actor",
		"locked_target":_xy(target),"player_start":_xy(start),"actual_landing":_xy(landing_position),"player_at_landing":_xy(landing_player),
		"landing_time":landing_time,"landing_radius":locked.radius,"player_radius":Balance.PLAYER_RADIUS,
		"hp_before":hp_before,"hp_after":Game.run.hp,"hp_damage":hp_before-Game.run.hp,
		"shield_before":shield_before,"shield_after":Game.run.shield,"shield_damage":shield_before-Game.run.shield,
		"camera_zoom":_xy(zoom),"camera_follow_offset":_xy(camera_offset),"runtime_explicitly_frozen_during_capture":true,"capture_wait_checks":capture_wait_checks,"frames":frames,"trajectory":trace,"failures":failures}
	var file := FileAccess.open(out.path_join("L37_movement_dodge_report.json"),FileAccess.WRITE)
	check(file != null,"write movement dodge report")
	if file != null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("L37 MOVEMENT DODGE: lock=",target," landing=",landing_position," player=",landing_player," hp_damage=",hp_before-Game.run.hp," shield_damage=",shield_before-Game.run.shield)
	check(await room.combat_audio.wait_for_cleanup(),"dodge audio cleanup")
	launch.free()
	Game.run = null

func _xy(point: Vector2) -> Array:
	return [point.x,point.y]

func _dodge_frame(room: Node2D, actor: Node2D, out: String, phase: String, capture: bool, frames: Array[Dictionary], elapsed: float) -> void:
	actor.body_visual.advance(.01)
	actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	room.camera.follow_target()
	room.camera.force_update_scroll()
	_refresh_badges(room)
	if Review.requested(): _check_card_layout(room,1)
	var filename := "L37_movement_dodge_"+phase+".png"
	frames.append({"phase":phase,"t":elapsed,"file":filename if capture else "","player":_xy(room.player.position),"m02":_xy(actor.position),"camera":_xy(room.camera.position),"zoom":_xy(room.camera.zoom)})
	if capture: await _save_frame(out,filename)

func _check_prop_skins(room: Node2D) -> void:
	var skins: Array[Dictionary] = PropSkins.skin_recipes(room)
	check(skins.size() == 4,"four skins of existing mechanisms and covers")
	var displayed := 0
	for recipe: Dictionary in room._depth_canvas.recipes:
		check(str(recipe.get("kind","")) != "b07_low_stone","old cover rectangles replaced, not doubled")
		if recipe.get("depth_kind","") == "b07_review_skin": displayed += 1
	check(displayed == 4,"four review skins in actual depth layer")
	for skin: Dictionary in skins:
		var source: String = skin.source
		if source == "sun_mirror_pedestal": check(skin.foot == Geometry.world_point([980,630]),"mirror skin on original mechanism")
		elif source == "sun_altar_disc": check(skin.foot == Geometry.world_point([1904,630]),"altar skin on original mechanism")
		elif source == "low_stone_cover":
			var rect: Rect2 = skin.collision_rect
			check(skin.foot == rect.get_center(),"cover skin on existing collision center")
			check(is_equal_approx(skin.visual_bounds.size.x,rect.size.x),"cover skin matches original width")
	for sprite: Node2D in room._depth_canvas.get_children():
		if sprite.get_script() == PropSkins:
			check(sprite.material == null and sprite.modulate == Color.WHITE,"prop skins keep original RGB")
	check(room.b07_mechanics.z_index == 3,"real sun warnings remain above skins")

func _check_card_layout(room: Node2D, expected_count: int) -> void:
	var candidates: Array[int] = Cards.detail_candidates(room)
	check(candidates.size() == expected_count,"real detail cards remain visible: "+str(expected_count))
	var shown: Array[int] = []
	for actor: Node2D in room.enemies.get_children():
		var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
		if badge != null and badge.visible and badge.show_detail:
			shown.append(actor.get_instance_id())
	check(shown.size() == expected_count,"actual visible badges match expected count")
	for id: int in candidates: check(id in shown,"every selected card actually visible")
	for id: int in shown: check(id in candidates,"no stale selected badge remains")
	var bodies: Array[Rect2] = CardLayout.body_rects(room)
	var occupied: Array[Rect2] = []
	for id: int in candidates:
		var actor: Node2D = instance_from_id(id)
		var badge: Node2D = actor.get_node("EnemySkillBadge")
		var layout: Dictionary = CardLayout.placement(badge)
		check(not layout.is_empty(),"actual card has review layout")
		if layout.is_empty(): continue
		check(layout.fits_viewport and not layout.fallback and float(layout.overlap_score) == 0,"live card fits without fallback or overlap")
		var actual: Rect2 = badge.get_global_transform_with_canvas()*Rect2(layout.origin,CardLayout.SIZE)
		var rect: Rect2 = layout.rect
		check(actual.position.distance_to(rect.position)<.01 and actual.size.distance_to(rect.size)<.01,"reported card bounds match actual badge transform")
		for body: Rect2 in bodies: check(not rect.intersects(body.grow(CardLayout.GAP)),"card avoids every live body")
		for other: Rect2 in occupied: check(not rect.intersects(other.grow(CardLayout.GAP)),"detail cards avoid each other")
		occupied.append(rect)
