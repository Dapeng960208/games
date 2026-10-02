extends Node
## Observational combat feedback harness: production actors, casts and rendering.
## Only fixture placement, durable target HP, AI suspension and initial resources
## are controlled. Damage, projectiles, hitstop and effects are never fabricated.

var app: Node
var stage: SubViewport
var room: Node2D
var target: Node2D
var anchor := Vector2.ZERO
var checks := 0
var failures := 0
var captures := 0
var active_record: Dictionary = {}
var records: Array[Dictionary] = []
var hero_ledgers: Array[Dictionary] = []
var selected_heroes: Array[String] = ["CH01","CH02","CH03"]
var initial_resource_fills := 0
var master_bus := -1
var old_mute := false
var graphical := false
var movie_only := false
var aim_tracking := false
var current_hero := ""
const SLOTS := ["basic","q","secondary","f","ultimate"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100 # Observe after native actors, never drive them.
	for argument in OS.get_cmdline_user_args():
		if argument == "--feedback-movie-only": movie_only = true
		if argument.begins_with("--feedback-hero="):
			var hero := argument.trim_prefix("--feedback-hero=")
			if hero in ["CH01","CH02","CH03"]: selected_heroes.assign([hero])
	master_bus = AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		old_mute = AudioServer.is_bus_mute(master_bus)
		AudioServer.set_bus_mute(master_bus,true)
	get_tree().create_timer(110.0).timeout.connect(func():
		push_error("Combat feedback capture timed out")
		_finish(1))
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ",description)
	else:
		failures += 1
		push_error("FAIL "+description)

func _finish(code: int) -> void:
	Input.action_release("attack")
	if is_instance_valid(room) and is_instance_valid(room.combat_audio): room.combat_audio.stop_all()
	if master_bus >= 0: AudioServer.set_bus_mute(master_bus,old_mute)
	get_tree().quit(code)

func frame() -> void:
	if graphical:
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame

func wait_seconds(duration: float) -> void:
	var until: float = float(room.elapsed)+duration
	while is_instance_valid(room) and float(room.elapsed) < until:
		await frame()

func _process(_delta: float) -> void:
	if not is_instance_valid(room) or Game.run == null: return
	if aim_tracking: _aim_input()
	if active_record.is_empty(): return
	var player: Node2D = room.player
	active_record["elapsed"] = float(room.elapsed)-float(active_record.start_time)
	active_record["max_visual_hitstop"] = maxf(float(active_record.max_visual_hitstop),float(player.visual_hitstop))
	active_record["max_hurt_flash"] = maxf(float(active_record.max_hurt_flash),float(target.hurt_flash))
	active_record["max_knockback_impulse"] = maxf(float(active_record.max_knockback_impulse),target.knockback.length())
	active_record["max_target_displacement"] = maxf(float(active_record.max_target_displacement),target.position.distance_to(active_record.target_origin))
	active_record["max_projectiles"] = maxi(int(active_record.max_projectiles),room.projectiles.get_child_count())
	active_record["max_effects"] = maxi(int(active_record.max_effects),room.effects.size())
	active_record["max_enemy_telegraphs"] = maxi(int(active_record.max_enemy_telegraphs),_telegraph_count())
	if is_instance_valid(room.combat_audio):
		active_record["max_audio_voices"] = maxi(int(active_record.max_audio_voices),int(room.combat_audio.active_voice_count()))
	var deployments := 0
	for node in get_tree().get_nodes_in_group("hero_deployments"):
		if node.room == room and node.is_alive(): deployments += 1
	active_record["max_deployments"] = maxi(int(active_record.max_deployments),deployments)
	for effect: Dictionary in room.effects:
		var kind := str(effect.get("kind",""))
		if not active_record.effect_kinds.has(kind): active_record.effect_kinds.append(kind)
	var state := str(player.visual_state)
	if not active_record.visual_states.has(state): active_record.visual_states.append(state)

func _physics_process(_delta: float) -> void:
	if active_record.is_empty() or not is_instance_valid(room) or Game.run == null: return
	# A render may cover multiple physics ticks. Retain both observations so a
	# 30 ms visual pause missed by a slow screenshot frame is not called absent.
	active_record["max_physics_hitstop"] = maxf(float(active_record.max_physics_hitstop),float(room.player.visual_hitstop))

func _on_damage(amount: float) -> void:
	if active_record.is_empty(): return
	var source := str(target.last_damage_context.get("damage_source","unknown"))
	var event := {"t":float(room.elapsed)-float(active_record.start_time),"amount":amount,"source":source,"skill_slot":str(target.last_damage_context.get("skill_slot","")),"root_event_id":str(target.last_damage_context.get("root_event_id","")),"hp_after":target.health.current,"target_position":[target.position.x,target.position.y]}
	active_record.damage_events.append(event)
	active_record["damage"] = float(active_record.damage)+amount
	if float(active_record.first_damage_time) < 0:
		active_record["first_damage_time"] = event.t

func run_checks() -> void:
	if not Game.profile_path.contains("test_combat_feedback"):
		push_error("Combat feedback requires an isolated test_combat_feedback profile")
		_finish(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	if graphical: DisplayServer.window_set_size(Vector2i(1280,720))
	check(Game.new_profile(),"isolated combat feedback profile")
	Game.set_setting("language","zh_CN")
	Game.set_setting("reduced_fx",false)
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	app = load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frame()
	await frame()
	for hero: String in selected_heroes:
		current_hero = hero
		check(Game.select_hero(hero),hero+" selected through profile API")
		check(Game.start_run(),hero+" started through production scene")
		room = app.room
		room.spawn_enabled = false
		# Actual progression API updates the live stat snapshot; no injected levels.
		check(Game.grant_hero_xp(3600,"feedback_training_"+hero),hero+" skills unlocked through real XP")
		check(Game.run.level == 20,hero+" actual level is 20")
		for enemy in room.enemies.get_children(): enemy.queue_free()
		for projectile in room.projectiles.get_children(): projectile.queue_free()
		await frame()
		anchor = _open_stage()
		check(not anchor.is_zero_approx(),hero+" verified open production training lane")
		if anchor.is_zero_approx():
			_finish(1)
			return
		target = room.spawn_enemy(anchor,"M01",1,{"reward_enabled":false})
		check(is_instance_valid(target),hero+" durable production enemy exists")
		if not is_instance_valid(target):
			_finish(1)
			return
		# Let the normal spawn presentation finish before suspending decisions.
		await wait_seconds(0.55)
		# AI alone is suspended; native status, hurt, motion and knockback still tick.
		target.training_ai_disabled = true
		target.health.reset(10000.0)
		target.health.damaged.connect(_on_damage)
		Game.restore_resource(float(Game.run.stats.get("resource_max",100)))
		initial_resource_fills += 1
		var ledger := {"hero":hero,"level":Game.run.level,"loadout":Game.profile.loadout.duplicate(true),"initial_resource":Game.run.resource,"initial_fill_count":1,"warmup_basic_attacks":0,"warmup_resource_gained":0.0,"clips":[]}
		for slot: String in SLOTS:
			await _prepare_action(slot)
			if slot != "basic":
				var required := float(room.player.skill_definition(slot).cost)
				await _earn_resource(required,ledger)
				await _prepare_action(slot)
			await _capture_action(slot)
			ledger.clips.append({"slot":slot,"resource_before":records[-1].resource_before,"resource_after_cast":records[-1].resource_after_cast,"resource_end":records[-1].resource_end})
		ledger["final_resource"] = Game.run.resource
		hero_ledgers.append(ledger)
		aim_tracking = false
		Game.finish_run("abandoned")
		await frame()
		await frame()
	var report := {"checks":checks,"failures":failures,"captures":captures,"graphical":graphical,"heroes":selected_heroes,"initial_resource_fills":initial_resource_fills,"audio":"Master muted during capture; native audio events and active voice counts sampled; no audio quality claim.","fixture":"Production main/room/player/enemy at level20 through XP API; starter loadout retained. One resource fill per hero. Enemy AI suspended, HP10000. Real geometry, motion, cooldowns, resource recovery, damage and effects. Player/target placement reset between named demonstrations; deployments remain so follow-up synergies are real.","ledgers":hero_ledgers,"clips":records}
	var suffix := selected_heroes[0] if selected_heroes.size() == 1 else "all"
	if movie_only: suffix += "_movie"
	var file := FileAccess.open("res://artifacts/combat_feedback_"+suffix+".json",FileAccess.WRITE)
	check(file != null,"feedback report created")
	if file != null:
		report["checks"] = checks
		report["failures"] = failures
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("COMBAT_FEEDBACK_RESULT checks=",checks," failures=",failures," clips=",records.size()," captures=",captures)
	_finish(1 if failures else 0)

func _open_stage() -> Vector2:
	for y in range(850,1351,100):
		for x in range(1000,1901,100):
			var candidate := Vector2(x,y)
			var valid: bool = room.valid_ground(candidate,30.0)
			for offset: Vector2 in [Vector2(-360,0),Vector2(180,0),Vector2(0,-210),Vector2(0,210),Vector2(-200,150),Vector2(100,-150)]:
				valid = valid and room.blocked_fraction(candidate,candidate+offset,30.0) >= 1.0
			if valid: return candidate
	return Vector2.ZERO

func _prepare_action(slot: String) -> void:
	while room.player.abilities.busy() or room.player.attack_remaining > 0 or room.player.dash_remaining > 0:
		await frame()
	target.position = anchor
	target.knockback = Vector2.ZERO
	var distance := 90.0
	if slot == "q": distance = 200.0 if current_hero == "CH01" else 120.0
	elif slot == "secondary" and current_hero == "CH02": distance = 180.0
	elif slot == "ultimate": distance = 110.0
	room.player.position = anchor-Vector2(distance,0)
	room.player.knockback = Vector2.ZERO
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frame()
	await frame()
	aim_tracking = true
	# Target screen coordinates only after the real camera has reached its new
	# transform. Dispatch locally so another window's OS cursor cannot aim left.
	for attempt in 6:
		_aim_input()
		await get_tree().physics_frame
		await frame()
		var expected: Vector2 = (anchor-room.player.position).normalized()
		if room.player.aim_direction.dot(expected) > 0.98: break
	check(room.player.aim_direction.dot((anchor-room.player.position).normalized()) > 0.98,current_hero+" "+slot+" production mouse aim reaches target")
	if room.player.aim_direction.dot((anchor-room.player.position).normalized()) <= 0.98:
		print("AIM_DIAGNOSTIC player=",room.player.position," target=",anchor," mouse_world=",room.player.get_global_mouse_position()," mouse_viewport=",stage.get_mouse_position()," canvas=",room.get_canvas_transform()," actual_aim=",room.player.aim_direction)
		_finish(2)
		await frame()

func _aim_input() -> void:
	var aim_at := room.get_canvas_transform()*room.to_global(anchor)
	var motion := InputEventMouseMotion.new()
	motion.position = aim_at
	motion.global_position = aim_at
	stage.push_input(motion,true)

func _earn_resource(required: float, ledger: Dictionary) -> void:
	var before: float = Game.run.resource
	var started: float = float(room.elapsed)
	while Game.run.resource+0.01 < required and float(room.elapsed)-started < 18.0:
		if current_hero == "CH01":
			await _prepare_action("basic")
			var previous_shots: int = Game.run.shots
			var attack_started: float = float(room.elapsed)
			Input.action_press("attack")
			while Game.run.shots == previous_shots and float(room.elapsed)-attack_started < 2.0:
				await get_tree().physics_frame
				await frame()
			Input.action_release("attack")
			if Game.run.shots == previous_shots:
				check(false,current_hero+" actual warmup attack timed out")
				break
			ledger.warmup_basic_attacks += 1
			await wait_seconds(float(Game.run.stats.attack_interval)+0.08)
		else:
			await wait_seconds(0.15)
	ledger.warmup_resource_gained += maxf(0.0,Game.run.resource-before)
	check(Game.run.resource+0.01 >= required,current_hero+" resource budget reached through actual play/recovery")

func _capture_action(slot: String) -> void:
	var player: Node2D = room.player
	if slot == "ultimate":
		# One genuine attacker supplies an unforced enemy-warning overlap probe.
		var warning_actor: Node2D = room.spawn_enemy(player.position+Vector2(0,76),"M01",1,{"reward_enabled":false})
		if is_instance_valid(warning_actor): warning_actor.health.reset(10000.0)
	var spec: Dictionary = player.skill_definition(slot) if slot != "basic" else {"cost":0.0,"windup":0.12 if current_hero == "CH01" else 0.0,"duration":float(Game.run.stats.attack_interval),"cooldown":float(Game.run.stats.attack_interval)}
	active_record = {"hero":current_hero,"slot":slot,"start_time":float(room.elapsed),"elapsed":0.0,"spec":spec.duplicate(true),"target_origin":target.position,"resource_before":Game.run.resource,"resource_after_cast":Game.run.resource,"resource_end":0.0,"damage":0.0,"damage_events":[],"first_damage_time":-1.0,"max_visual_hitstop":0.0,"max_hurt_flash":0.0,"max_knockback_impulse":0.0,"max_target_displacement":0.0,"max_projectiles":0,"max_effects":0,"max_deployments":0,"max_enemy_telegraphs":0,"effect_kinds":[],"visual_states":[],"frames":[]}
	active_record["max_audio_voices"] = 0
	active_record["max_physics_hitstop"] = 0.0
	active_record["audio_accepted_before"] = int(room.combat_audio.accepted_events) if is_instance_valid(room.combat_audio) else 0
	active_record["audio_rejected_before"] = int(room.combat_audio.rejected_events) if is_instance_valid(room.combat_audio) else 0
	active_record["feedback_impacts_before"] = _feedback_impact_count()
	var shots_before: int = Game.run.shots
	var success: bool
	if slot == "basic":
		Input.action_press("attack")
		while Game.run.shots == shots_before and float(room.elapsed)-float(active_record.start_time) < 2.0:
			await get_tree().physics_frame
			await frame()
		Input.action_release("attack")
		success = Game.run.shots > shots_before
	else:
		var aim := anchor-Vector2(40,0) if current_hero == "CH03" and slot == "secondary" else anchor
		success = player.cast_skill(slot,aim)
	active_record["resource_after_cast"] = Game.run.resource
	active_record["cooldown_after_cast"] = player.shot_cooldown if slot == "basic" else float(player.cooldowns.get(slot,0))
	active_record["cast_success"] = success
	check(success,current_hero+" "+slot+" starts through real input/cast")
	if slot != "basic": await frame()
	await _capture_frame("start")
	var hit_saved := false
	var recovery_saved := false
	var overlap_saved := false
	var duration := maxf(1.05,float(spec.get("duration",0.5))+0.5)
	if current_hero == "CH03" and slot == "secondary": duration = 2.1
	if current_hero == "CH03" and slot == "ultimate": duration = 2.65
	while float(room.elapsed)-float(active_record.start_time) < duration:
		if slot == "ultimate" and not overlap_saved and _telegraph_count() > 0 and _ultimate_visual_active():
			await _capture_frame("telegraph_overlap")
			overlap_saved = true
		# HP loss may come from a previous action's status/deployment. A contact
		# capture needs this action's attributed damage and native impact feedback.
		if not hit_saved and _own_hit_count(active_record) > 0 and _feedback_impact_count() > int(active_record.feedback_impacts_before):
			await _capture_frame("impact")
			hit_saved = true
		if not recovery_saved and float(room.elapsed)-float(active_record.start_time) >= maxf(0.18,float(spec.get("duration",0.5))-0.045):
			# This samples the real timeline end, not an invented recovery pose.
			await _capture_frame("timeline_end")
			recovery_saved = true
		await frame()
	active_record["resource_end"] = Game.run.resource
	active_record["target_end"] = [target.position.x,target.position.y]
	active_record["target_origin"] = [active_record.target_origin.x,active_record.target_origin.y]
	active_record["own_hit_count"] = _own_hit_count(active_record)
	active_record["feedback_impact_events"] = _feedback_impact_count()-int(active_record.feedback_impacts_before)
	active_record["own_damage"] = 0.0
	active_record["own_first_damage_time"] = -1.0
	for event: Dictionary in active_record.damage_events:
		if _is_own_hit(active_record,event):
			active_record["own_damage"] = float(active_record.own_damage)+float(event.amount)
			if float(active_record.own_first_damage_time) < 0: active_record["own_first_damage_time"] = event.t
	active_record["telegraph_overlap_captured"] = overlap_saved
	active_record["audio_player_nodes"] = get_tree().root.find_children("*","AudioStreamPlayer",true,false).size()+get_tree().root.find_children("*","AudioStreamPlayer2D",true,false).size()+get_tree().root.find_children("*","AudioStreamPlayer3D",true,false).size()
	active_record["audio_accepted_events"] = int(room.combat_audio.accepted_events)-int(active_record.audio_accepted_before) if is_instance_valid(room.combat_audio) else 0
	active_record["audio_rejected_events"] = int(room.combat_audio.rejected_events)-int(active_record.audio_rejected_before) if is_instance_valid(room.combat_audio) else 0
	check(int(active_record.own_hit_count) > 0,current_hero+" "+slot+" produces damage attributed to its own action")
	check(hit_saved and int(active_record.feedback_impact_events) > 0,current_hero+" "+slot+" produces native confirmed-contact feedback and impact frame")
	check(recovery_saved and not player.abilities.busy(),current_hero+" "+slot+" completes its action timeline")
	check(int(active_record.audio_accepted_events) > 0,current_hero+" "+slot+" reaches native audio scheduling")
	print("FEEDBACK ",current_hero," ",slot," dmg=",active_record.damage," hits=",active_record.own_hit_count," cost=",float(active_record.resource_before)-float(active_record.resource_after_cast)," hitstop=",active_record.max_visual_hitstop," push=",active_record.max_target_displacement," fx=",active_record.effect_kinds)
	records.append(active_record.duplicate(true))
	active_record.clear()

func _own_hit_count(record: Dictionary) -> int:
	var total := 0
	for event: Dictionary in record.damage_events:
		if _is_own_hit(record,event): total += 1
	return total

func _is_own_hit(record: Dictionary, event: Dictionary) -> bool:
	return (record.slot == "basic" and event.source == "primary") or (record.hero == "CH03" and record.slot == "secondary" and (event.source == "node" or (event.source == "skill" and event.skill_slot == "node"))) or (event.source == "skill" and event.skill_slot == record.slot)

func _feedback_impact_count() -> int:
	var feedback: Node = room.player.get_node_or_null("HeroFeedback")
	return int(feedback.impact_events) if is_instance_valid(feedback) else 0

func _telegraph_count() -> int:
	var count := 0
	for enemy in room.enemies.get_children():
		if enemy.training_ai_disabled: continue
		if enemy.brain != null:
			if not enemy.brain.current_telegraph().is_empty(): count += 1
		elif enemy.state == &"windup": count += 1
	return count

func _ultimate_visual_active() -> bool:
	# Ignore old damage text or unrelated rings: the actual ultimate timeline or
	# its real field must still be active. Visibility/occlusion still needs review.
	if room.player.abilities.busy() and str(room.player.abilities.active.spec.slot) == "ultimate": return true
	if current_hero == "CH03":
		for node in get_tree().get_nodes_in_group("hero_deployments"):
			if node.room == room and node.kind == "field" and node.is_alive(): return true
	return false

func _capture_frame(phase: String) -> void:
	# Caller already waits for the renderer; no pose, damage or effect is injected.
	var entry := {"phase":phase,"t":float(room.elapsed)-float(active_record.start_time),"resource":Game.run.resource,"target_hp":target.health.current,"visual_state":str(room.player.visual_state),"visual_hitstop":room.player.visual_hitstop,"feedback_impact_events":_feedback_impact_count()-int(active_record.feedback_impacts_before),"effect_count":room.effects.size(),"projectile_count":room.projectiles.get_child_count(),"enemy_telegraphs":_telegraph_count(),"sampling_basis":"First rendered frame after input/cast" if phase == "start" else "First rendered frame after attributed health damage and native confirmed-contact feedback" if phase == "impact" else "Configured action timeline end; visual_state may already be idle" if phase == "timeline_end" else "Actual enemy telegraph coexists with native hero effects"}
	if graphical and not movie_only:
		var filename := "combat_feedback_"+current_hero+"_"+str(active_record.slot)+"_"+phase+".png"
		var frame_image: Image = stage.get_texture().get_image()
		if frame_image.save_png("res://artifacts/"+filename) == OK:
			captures += 1
			entry["file"] = filename
		else:
			check(false,"save actual feedback frame "+filename)
	active_record.frames.append(entry)
