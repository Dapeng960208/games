extends Node
## Native production BO04 Extreme stationary-combat observations. Copies only
## the locally observed permanent build into the isolated profile; never ticks AI,
## damages actors directly, resets cooldowns or overwrites combat positions.
## tools/test.ps1 -Suite boss_stationary -SkipImport
## Default: actual Lv12 and normal Lv20 S06/RL03 II, basic + W/E/R.
## BOSS_STATIONARY_MODE=basic replays the two original basic-only fixtures.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const ITEMS := {"EQ08":5,"EQ18":5,"EQ28":3,"EQ38":0,"EQ48":3,"EQ58":3}
const CASES := [
	{"id":"actual_L12_S06_basic","mode":"basic","level":12,"xp":1590,"relic":false,"skills":false},
	{"id":"actual_L12_S06_RL03_II_basic","mode":"basic","level":12,"xp":1590,"relic":true,"skills":false},
	{"id":"actual_L12_S06_RL03_II_skills","mode":"skills","level":12,"xp":1590,"relic":true,"skills":true},
	{"id":"normal_L20_S06_RL03_II_skills","mode":"skills","level":20,"xp":3600,"relic":true,"skills":true}]
var stage: SubViewport
var room: RoomController
var boss: BossActor
var run_ref: RunSession
var current: Dictionary = {}
var cases: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var running := false
var elapsed := 0.0
var next_sample := 0.0
var next_skill_try := 0.0
var old_state := ""
var old_action := ""
var old_phase := 0
var old_used := 0
var old_hits := 0
var old_hp := 0.0
var old_shield := 0.0
var last_boss_hp := 0.0
var old_boss_hp := 0.0
var initial_position := Vector2.ZERO
var checks := 0
var failures := 0
var result_path := ""
var skill_casts: Dictionary = {}
var skill_hits: Dictionary = {}
var skill_hp_damage: Dictionary = {}
var observed_boss_hp := 0.0
var actual_incoming_hp_damage := 0.0
var overlap_input := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS_STATIONARY: "+label)

func _build_profile(configuration: Dictionary) -> void:
	Game.profile.selected_hero = "CH01"
	Game.profile.hero_xp.CH01 = int(configuration.xp)
	Game.profile.bosses = ["BO01","BO02","BO03"]
	Game.profile.loadout.clear()
	Game.profile.equipment.clear()
	for id: String in ITEMS:
		Game.profile.equipment[id] = {"level":int(ITEMS[id])}
		Game.profile.loadout[ContentRegistry.equipment(id).slot] = id
	Game.profile.settings["auto_attack"] = false
	Game.profile.settings["camera_shake"] = false
	Game.profile.branches.CH01 = {"q":"","ultimate":""}

func aim(at: Vector2) -> void:
	var point := room.get_canvas_transform()*at
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	stage.push_input(motion,true)

func state() -> Dictionary:
	var live := is_instance_valid(boss)
	if live: last_boss_hp = boss.health.current
	var brain: BossBrain = boss.boss_brain if live else null
	var adds := 0
	for actor: Node in room.enemies.get_children():
		if actor != boss and actor is EnemyActor and actor.is_alive() and actor.actor_kind != "objective": adds += 1
	var value := {"t":elapsed,"hp":run_ref.hp,"shield":run_ref.shield,"resource":run_ref.resource,"boss_hp":last_boss_hp,
		"boss_phase":brain.phase if brain != null else old_phase,"boss_action":brain.current_action if brain != null else old_action,"boss_state":str(brain.state) if brain != null else "freed",
		"distance":room.player.position.distance_to(boss.position) if live else -1.0,"player_position":[room.player.position.x,room.player.position.y],
		"boss_position":[boss.position.x,boss.position.y] if live else [],"boss_state_time":brain.state_time if brain != null else 0.0,"boss_weakpoint":brain.weakpoint if brain != null else "",
		"shots":int(room.telemetry.shots),"primary_hits":int(room.telemetry.primary_hits),"received_hits":int(room.telemetry.player_hits),"dashes":int(room.telemetry.dashes),
		"attack_cooldown":room.player.shot_cooldown,"skill_cooldowns":room.player.cooldowns.duplicate(),"hero_cast_serial":room.player.abilities.cast_serial,
		"hit_chain":room.player.hit_chain.count,"process_live":room.can_process() and room.player.can_process() and (not live or boss.can_process()),
		"native_ai_time":brain.elapsed if brain != null else elapsed,"contact_damage":boss.contact_damage if live else float(current.get("contact_damage",0)),"alive_adds":adds,
		"skill_casts":skill_casts.duplicate(),"skill_hits":skill_hits.duplicate(),"skill_hp_damage":skill_hp_damage.duplicate(),"actual_incoming_hp_damage":actual_incoming_hp_damage}
	return value

func event(kind: String, details: Dictionary = {}) -> void:
	var value := state()
	value["kind"] = kind
	value.merge(details,true)
	events.append(value)

func _physics_process(delta: float) -> void:
	if not running: return
	elapsed += delta
	if is_instance_valid(boss):
		last_boss_hp = boss.health.current
		var brain: BossBrain = boss.boss_brain
		if old_state != str(brain.state) or old_action != brain.current_action or old_phase != brain.phase:
			var warning := brain.current_telegraph()
			event("boss_state",{"warning_contains_player":room.enemy_skills.shape_contains(warning,room.player.position,Balance.PLAYER_RADIUS) if not warning.is_empty() else false,"warning_shape":str(warning.get("shape","")),"warning_inner_radius":float(warning.get("inner_radius",0)),"warning_radius":float(warning.get("radius",0))})
			old_state = str(brain.state)
			old_action = brain.current_action
			old_phase = brain.phase
		var used := 0
		for count: int in brain.tactical_snapshot().actions_used.values(): used += count
		if used > old_used:
			event("boss_release",{"cast_number":used,"casts_by_action":brain.tactical_snapshot().actions_used.duplicate(true)})
			old_used = used
	if int(room.telemetry.player_hits)>old_hits:
		event("received_hit",{"hit_number":int(room.telemetry.player_hits),"hp_delta":run_ref.hp-old_hp,"shield_delta":run_ref.shield-old_shield})
		old_hits = int(room.telemetry.player_hits)
	if run_ref.hp != old_hp or run_ref.shield != old_shield:
		actual_incoming_hp_damage += maxf(0.0,old_hp-run_ref.hp)
		event("health_guard_change",{"hp_delta":run_ref.hp-old_hp,"shield_delta":run_ref.shield-old_shield})
	old_hp = run_ref.hp
	old_shield = run_ref.shield
	if last_boss_hp < old_boss_hp:
		event("boss_damage",{"amount":old_boss_hp-last_boss_hp})
	old_boss_hp = last_boss_hp
	if elapsed >= next_sample:
		var sample := state()
		samples.append(sample)
		print("BOSS_STATIONARY_SECOND ",current.id," ",JSON.stringify(sample))
		next_sample += 1.0
	if elapsed >= 90.0 or Game.run == null or run_ref.hp <= 0.0 or not is_instance_valid(boss) or boss.is_queued_for_deletion() or boss.health.current <= 0.0:
		running = false
		room.process_mode = Node.PROCESS_MODE_DISABLED
		return
	aim(boss.position)
	# Same production request API and natural cooldown as repeated attack input.
	# No move or dash input is sent; normal received knockback remains active.
	if bool(current.skills) and elapsed >= next_skill_try and room.player.combo_queue.is_empty():
		next_skill_try = elapsed+.15
		for slot: String in ["ultimate","secondary","f"]:
			if room.player.cooldowns[slot] <= 0.0 and room.player.request_skill(slot,boss.position): break
	if room.player.shot_cooldown <= 0.0 and room.player.combo_queue.is_empty():
		var direction := room.player.position.direction_to(boss.position)
		if direction.is_zero_approx():
			# A stationary manual swing remains legal when a leap lands exactly
			# on the player's feet. Retain the real pointer aim rather than submit
			# an invalid zero direction or force an automatic-target zero vector.
			if not overlap_input: event("attack_overlap_fallback")
			overlap_input = true
			room.player.request_attack(room.player.aim_direction)
		else:
			overlap_input = false
			room.player.request_attack(direction,boss)

func _skill_feedback(slot: String, reason: String, details: Dictionary) -> void:
	if not running or reason not in ["accepted","queued"]: return
	if slot != "attack" and reason == "accepted": skill_casts[slot] = int(skill_casts.get(slot,0))+1
	event("hero_skill_request",{"slot":slot,"reason":reason,"details":details.duplicate(true)})

func _boss_damaged(_amount: float) -> void:
	if not running or not is_instance_valid(boss): return
	var amount := maxf(0.0,observed_boss_hp-boss.health.current)
	observed_boss_hp = boss.health.current
	var context: Dictionary = boss.last_damage_context
	var slot := str(context.get("skill_slot",""))
	# The signal observes HP losses, not shield-only contact. Hit counts are
	# original packets; slot-attributed HP damage includes equipment follow-ups.
	if str(context.get("damage_source","")) == "skill" and slot in ["secondary","f","ultimate"]:
		if int(context.get("proc_depth",0)) == 0: skill_hits[slot] = int(skill_hits.get(slot,0))+1
		skill_hp_damage[slot] = float(skill_hp_damage.get(slot,0))+amount
	event("boss_damage_packet",{"amount":amount,"damage_source":str(context.get("damage_source","")),"skill_slot":slot,"root_event_id":str(context.get("root_event_id","")),"attack_id":str(context.get("attack_id","")),"damage_type":str(context.get("damage_type","")),"proc_depth":int(context.get("proc_depth",0))})

func install(configuration: Dictionary) -> void:
	get_tree().paused = true
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	if Game.run != null: Game.finish_run("abandoned")
	_build_profile(configuration)
	check(Game.start_run(),"observed build starts isolated real run")
	run_ref = Game.run
	check(run_ref.level == int(configuration.level) and int(run_ref.stats.sets.get("S06",0)) == 6 and (int(configuration.level) != 12 or absf(run_ref.max_hp-167.368421)<.001),"specified permanent level and six S06 pieces resolve through production profile")
	if bool(configuration.relic):
		run_ref.relics = ["arc"]
		run_ref.stats["relic_levels"] = {"RL03":2}
	room = RoomScene.instantiate()
	stage.add_child(room)
	var prepared := room.prepare_expedition_node({"room_id":"BO04","role":"boss","biome_id":"B04","node_index":6,"node_count":7,"difficulty":4,"seed":41827,"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)),"BO04 Extreme prepares actual production arena")
	room.apply_prepared_expedition_node(prepared)
	boss = room._boss_actor as BossActor
	check(boss != null and int(boss.profile.difficulty) == 4,"actual BO04 Extreme boss and counters install")
	room.player.position = room.clamp_actor(boss.position+Vector2(-82,12),Balance.PLAYER_RADIUS)
	room.player.clear_movement_target()
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.player.skill_input_feedback.connect(_skill_feedback)
	boss.health.damaged.connect(_boss_damaged)
	initial_position = room.player.position
	current = configuration.duplicate(true)
	samples.clear()
	events.clear()
	elapsed = 0.0
	next_sample = 0.0
	next_skill_try = 0.0
	old_state = ""
	old_action = ""
	old_phase = 0
	old_used = 0
	old_hits = 0
	old_hp = run_ref.hp
	old_shield = run_ref.shield
	actual_incoming_hp_damage = 0.0
	overlap_input = false
	skill_casts.clear()
	skill_hits.clear()
	skill_hp_damage.clear()
	last_boss_hp = boss.health.current
	observed_boss_hp = last_boss_hp
	old_boss_hp = last_boss_hp
	current["resolved_stats"] = run_ref.stats.duplicate(true)
	current["boss_profile"] = boss.profile.duplicate(true)
	current["contact_damage"] = boss.contact_damage
	current["skill_definitions"] = {}
	for slot: String in ["secondary","f","ultimate"]: current.skill_definitions[slot] = room.player.skill_definition(slot)
	check(initial_position.distance_to(boss.position) < 105.0 and room.has_line_of_sight(initial_position,boss.position),"initial feet are in real melee reach with clear LOS")
	get_tree().paused = false
	print("BOSS_STATIONARY_BEGIN ",current.id," hp=",run_ref.hp," boss_hp=",boss.health.current," fixture_stats=",JSON.stringify(run_ref.stats))
	running = true

func _run() -> void:
	if not Game.profile_path.contains("test_boss_stationary"): get_tree().quit(2); return
	result_path = Game.profile_path.get_base_dir().path_join("boss_stationary_observations.json")
	check(Game.new_profile(),"isolated profile exists")
	AudioServer.set_bus_mute(0,true)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","click_move","move_to_cursor","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if InputMap.has_action(action): Input.action_release(action)
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.handle_input_locally = true
	add_child(stage)
	var selected_mode := OS.get_environment("BOSS_STATIONARY_MODE")
	if selected_mode.is_empty(): selected_mode = "skills"
	check(selected_mode in ["basic","skills"],"fixture selector names an available native scenario group")
	for configuration: Dictionary in CASES:
		if str(configuration.mode) != selected_mode: continue
		await install(configuration)
		while running: await get_tree().process_frame
		var final := state()
		var outcome := "boss_defeated" if last_boss_hp <= 0.0 or (is_instance_valid(boss) and boss.is_queued_for_deletion()) else "player_died" if run_ref.hp <= 0.0 else "time_limit"
		check(int(room.telemetry.dashes) == 0,"stationary driver never uses dash")
		check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up") and not Input.is_action_pressed("move_down") and not Input.is_action_pressed("click_move"),"stationary driver never supplies keyboard or pointer movement")
		check(elapsed >= .8 and int(room.telemetry.shots)>0,"native fight reaches production attack input")
		check(absf(float(final.native_ai_time)-elapsed) <= .1,"native Boss physics advances with elapsed fight time allowing initial preparation frame")
		check(old_used > 0,"native Boss AI releases real production attacks")
		check(actual_incoming_hp_damage > 0.0,"production enemy attacks cause actual player HP loss")
		if str(configuration.id) in ["actual_L12_S06_RL03_II_skills","normal_L20_S06_RL03_II_skills"]:
			check(outcome == "player_died" and is_instance_valid(boss) and not boss.health.dead and last_boss_hp > 0.0,"specified stationary W/E/R S06 RL03 II reference build dies while BO04 Extreme remains alive")
		var record := {"configuration":current.duplicate(true),"outcome":outcome,"final":final,"samples":samples.duplicate(true),"events":events.duplicate(true),"displacement":initial_position.distance_to(room.player.position)}
		cases.append(record)
		print("BOSS_STATIONARY_OUTCOME ",current.id," ",outcome," t=",elapsed," hp=",run_ref.hp," boss_hp=",last_boss_hp," received=",room.telemetry.player_hits," shots=",room.telemetry.shots)
		_save()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	if Game.run != null: Game.finish_run("abandoned")
	stage.free()
	await get_tree().process_frame
	print("BOSS_STATIONARY_RESULT checks=",checks," failures=",failures," cases=",cases.size()," evidence=",result_path)
	get_tree().quit(1 if failures else 0)

func _save() -> void:
	var file := FileAccess.open(AssetCatalog.resolve(result_path),FileAccess.WRITE)
	check(file != null,"native observations write only beside isolated test profile")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"\t"))
		file.close()
