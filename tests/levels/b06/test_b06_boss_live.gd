extends Node
const Skills = preload("res://scripts/levels/b06/combat/enemy_skills.gd")
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const BossLayouts = preload("res://scripts/domain/world/boss_layouts.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B06 BOSS LIVE: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b06_boss_live"): get_tree().quit(2); return
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26003}),"isolated baseline")
	var room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await get_tree().process_frame
	check(BossLayouts.build("BO06",1).is_empty(),"default boss gate closed")
	check(not BossLayouts.build("BO06",1,true).is_empty(),"explicit candidate BossLayouts supported")
	for difficulty in 5:
		var context := {"biome_id":"B06","room_id":"BO06","role":"boss","difficulty":difficulty,"b06_candidate":true,"node_index":-100}
		var prepared: Dictionary = room.prepare_expedition_node(context)
		check(prepared.get("valid",false),"candidate boss preparation")
		room.apply_prepared_expedition_node(prepared)
		var boss = room._boss_actor
		var host = room.b06_mechanics
		check(is_instance_valid(boss) and boss.boss_id == "BO06","real BossActor registered")
		check(boss.brain == boss.boss_brain and boss.brain.get_script().resource_path.ends_with("b06_boss_brain.gd"),"BO06 brain factory")
		check(int(boss.health.maximum) == int(Skills.boss_profile(difficulty).max_hp),"resolved boss HP once")
		check(host.state == host.boss_state.tide_state(),"one shared tide clock")
		room.player.position = boss.position+Vector2(150,0)
		boss.boss_brain._begin_action(boss,room.player,"siege_claw")
		var warned: Dictionary = boss.boss_brain.current_telegraph()
		check(warned.get("action_id") == "siege_claw","claw warning")
		room.player.position = boss.position+Vector2(-150,0)
		boss.boss_brain.tick(boss,.01,room.player)
		check(boss.boss_brain.current_telegraph().direction == warned.direction,"claw cannot track after warning")
		boss.health.current = floor(boss.health.maximum*.7)
		boss.boss_brain.tick(boss,.01,room.player)
		check(boss.boss_brain.phase == 2 and host.state.clock_state().phase == "low","P2 starts full low sequence")
		host.tick(10)
		check(host.state.clock_state().phase == "high","P2 actual high tide")
		var before: Dictionary = host.state.snapshot()
		boss.health.current = floor(boss.health.maximum*.4)
		boss.boss_brain.tick(boss,.01,room.player)
		check(boss.boss_brain.phase == 3 and host.state.snapshot().tide_start_us == before.tide_start_us,"P3 never resets single tide")
		host.tick(6)
		check(not host.can_enemy_cast() and not host.can_enemy_hit(),"actual output window blocks both admission stages")
		boss.boss_brain.tick(boss,.1,room.player)
		check(boss.boss_brain.command.is_empty(),"output window cancels pending warning")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(host.checkpoint()))
		host.tick(2.5)
		check(host.can_enemy_cast(),"full2.5second output window")
		check(host.restore_checkpoint(saved) and not host.can_enemy_hit(),"boss exact JSON restore")
		check(host.state == host.boss_state.tide_state(),"restore preserves shared clock identity")
		host.tick(2.5)
		room.player.position = boss.position+Vector2(180,0)
		boss.boss_brain._begin_action(boss,room.player,"dual_cannon")
		var first: Dictionary = boss.boss_brain.current_telegraph()
		var lateral: Vector2 = first.origin-boss.position
		check(is_equal_approx(lateral.length(),100),"cannon muzzle offsets preserve middle corridor")
		for frame in 150:
			boss.boss_brain.tick(boss,.02,room.player)
			if boss.boss_brain._stage == 1: break
		check(boss.boss_brain._stage == 1,"dual cannon admits separately warned second stage")
		check(not boss.reward_enabled,"boss has no direct rewards")
		# Mechanics-only fixture protection: this is not a strength/TTK sample.
		room.player.status.apply("invulnerable",1,60)
		for action: String in boss.boss_brain.available_actions(3):
			boss.boss_brain._action_ready_at.clear()
			room.player.position = boss.position+Vector2(140,0)
			boss.boss_brain._begin_action(boss,room.player,action)
			var initial: Dictionary = boss.boss_brain.current_telegraph()
			check(initial.get("action_id") == action,"actual action warning "+action)
			check(float(initial.get("tell",0))+float(initial.get("lock",0)) > 0,"legal warning for "+action)
			if action == "shell_bombard":
				check(initial.target.distance_to(initial.b06_dry_refuge) >= 198,"actual full-footprint dry refuge")
			for frame in 250:
				boss.boss_brain.tick(boss,.02,room.player)
				if boss.boss_brain.state == &"recovery": break
			check(int(boss.boss_brain._actions_used.get(action,0)) > 0,"actual shared runtime released "+action)
			check(boss.boss_brain.command.is_empty(),"completed sequence clears warning "+action)
		check(boss.boss_brain.brood_batches <= 2,"finite escort attempt ceiling")
		for actor in room.enemies.get_children():
			if actor == boss or actor.owner_enemy == null: continue
			check(not actor.reward_enabled and actor.owner_enemy.get_ref() == boss,"escort reward and ownership isolation")
	var retry_boss: Node2D = room._boss_actor
	room.enemy_skills.b06.summon_attempts[retry_boss.get_instance_id()] = 2
	retry_boss.configure(Skills.boss_profile(4),{"actor_kind":"boss","reward_enabled":false})
	check(not room.enemy_skills.b06.summon_attempts.has(retry_boss.get_instance_id()),"same actor new-encounter retry resets finite escort ledger")
	check(room.b06_mechanics.state.clock_state().phase == "inactive" and retry_boss.boss_brain.phase == 1,"same actor retry resets single boss clock")
	room.enemy_skills.b06.summon_attempts[retry_boss.get_instance_id()] = 1
	retry_boss.boss_phase_started(2,.7)
	check(room.enemy_skills.b06.summon_attempts[retry_boss.get_instance_id()] == 1,"phase cleanup preserves finite escort budget")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free()
	Game.run = null
	print("B06_BOSS_LIVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
