extends Node
## Real boss actors and EnemySkillRuntime, with deterministic collision only.
## tools/test.ps1 -Suite first_four_bosses -SkipImport -SkipRestart

const Profiles = preload("res://scripts/combat/boss_profiles.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Brain = preload("res://scripts/combat/boss_brain.gd")
const SkillFixtures = preload("res://tests/test_enemy_skills.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const IDS := ["BO01", "BO02", "BO03", "BO04"]

class Minion extends SkillFixtures.ActorFixture:
	var owner_enemy: WeakRef
	var reward_enabled: bool = false
	var profile: Dictionary = {}

class RecordedBoss extends "res://scripts/combat/boss.gd":
	var casts: Array[Dictionary] = []
	func cast_enemy_skill(skill: Dictionary) -> void:
		casts.append(skill.duplicate(true))
		super.cast_enemy_skill(skill)

class ThemeRoom extends SkillFixtures.RoomFixture:
	var layout: Dictionary = {}
	var enemy_skills: Node2D
	var fx_font: Font = ThemeDB.fallback_font
	var corpse_count: int = 4
	var consumed_corpses: int = 0
	var deaths: int = 0

	func spawn_enemy_summon(caster: Node2D, prototype_id: String, at: Vector2) -> Node2D:
		var owned: int = 0
		for child: Node in enemies.get_children():
			if child is Minion and child.owner_enemy != null and child.owner_enemy.get_ref() == caster and child.is_alive(): owned += 1
		if owned >= 2 or summon_budget <= 0 or not valid_ground(at, 12.0): return null
		var actor := Minion.new()
		actor.room = self
		actor.enemy_id = prototype_id
		actor.position = at
		actor.owner_enemy = weakref(caster)
		actor.profile = Catalog.enemy(prototype_id)
		enemies.add_child(actor)
		spawned.append(actor)
		summon_budget -= 1
		return actor

	func consume_enemy_corpse(_caster: Node2D, _radius: float) -> bool:
		if corpse_count <= 0: return false
		corpse_count -= 1
		consumed_corpses += 1
		return true

	func enemy_died(_enemy: Node2D) -> void:
		deaths += 1

	func add_damage_text(_at: Vector2, _amount: float, _kind: StringName, _context: Dictionary = {}) -> void:
		pass

var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FIRST FOUR BOSSES FAIL: " + label)

func fixture(id: String) -> Dictionary:
	var host := ThemeRoom.new()
	add_child(host)
	var player := SkillFixtures.ActorFixture.new()
	player.room = host
	player.health.reset(100000.0)
	player.position = Vector2(620,400)
	host.player = player
	host.add_child(player)
	host.recipients = [player]
	var runtime := Runtime.new()
	host.add_child(runtime)
	runtime.configure(host)
	host.enemy_skills = runtime
	var boss := RecordedBoss.new()
	boss.room = host
	boss.position = Vector2(300,400)
	check(boss.configure_boss(id,0,777), id + " resolves production profile")
	host.enemies.add_child(boss)
	return {"room":host, "boss":boss, "player":player, "runtime":runtime}

func tick(sim: Dictionary, duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.00001:
		var step: float = minf(0.02, remaining)
		sim.boss.boss_brain.tick(sim.boss, step, sim.player)
		sim.runtime.advance(step)
		remaining -= step

func trigger(sim: Dictionary, action: String, phase_value: int = 1) -> Dictionary:
	var boss: RecordedBoss = sim.boss
	var brain: BossBrain = boss.boss_brain
	boss.health.current = boss.health.maximum * ([1.0,0.69,0.34][phase_value-1])
	brain.tick(boss, 0.001, sim.player)
	brain.state = &"recovery"
	brain.state_time = 0.0
	brain.action_index = (Brain.SEQUENCES[boss.boss_id][phase_value] as Array).find(action)
	check(brain.action_index >= 0, boss.boss_id + " has actual sequence action " + action)
	brain._begin_action(boss, sim.player, action)
	var tell: Dictionary = brain.current_telegraph()
	check(not tell.is_empty() and str(tell.get("action_id", "")) == action, action + " enters real telegraph")
	if tell.is_empty(): return {}
	var old_casts: int = boss.casts.size()
	tick(sim, float(tell.tell)-0.08)
	check(boss.casts.size() == old_casts, action + " cannot hit before tell completion")
	tick(sim, 0.1)
	var locked: Dictionary = brain.current_telegraph()
	check(bool(locked.get("locked",false)), action + " locks for a visible dodge window")
	var frozen: String = var_to_str([locked.get("target"),locked.get("points",[]),locked.get("paths",[]),locked.get("direction")])
	var player_at: Vector2 = sim.player.position
	sim.player.position += Vector2(0,60)
	brain.tick(boss,0.01,sim.player)
	var after: Dictionary = brain.current_telegraph()
	check(frozen == var_to_str([after.get("target"),after.get("points",[]),after.get("paths",[]),after.get("direction")]), action + " keeps committed hit geometry when target moves")
	sim.player.position = player_at
	tick(sim,float(locked.get("lock",0.4))+0.04)
	check(boss.casts.size() == old_casts+1, action + " executes exactly once")
	return boss.casts.back() if boss.casts.size() > old_casts else {}

func run_checks() -> void:
	var isolated: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-profile=") and arg.contains("test_first_four_bosses"): isolated = true
	if not isolated:
		push_error("This suite requires an isolated first_four_bosses test profile")
		get_tree().quit(1)
		return
	if not Game.has_profile: Game.new_profile()
	check(Game.start_run(), "isolated combat run starts")
	var names := ["日曜机关巨像", "琥珀虫后", "缝合镇长", "裂岩大酋长"]
	for index: int in IDS.size():
		var id: String = IDS[index]
		for difficulty: int in range(5):
			var profile: Dictionary = Profiles.resolve(id,difficulty)
			check(Profiles.validate(profile).is_empty() and profile.name == names[index], id + " clan identity and existing difficulty " + str(difficulty))
			for wave: Dictionary in profile.reinforcement_waves:
				for member: Dictionary in wave.members:
					check(Catalog.enemy(member.enemy_id).biome_id == profile.biome_id, id + " phase summon belongs to its clan")
	await solar_checks()
	await brood_checks()
	await grave_checks()
	await warchief_checks()
	Game.finish_run("abandoned")
	print("FIRST FOUR BOSSES TESTS: ", checks-failures, "/", checks, " passed")
	get_tree().quit(1 if failures else 0)

func solar_checks() -> void:
	var sim: Dictionary = fixture("BO01")
	var boss: RecordedBoss = sim.boss
	var hp: float = boss.health.current
	var shield: float = boss.status.shield()
	check(shield > 0.0, "Sunwheel enters with a real absorbable energy shield")
	boss.take_damage(60.0,&"primary",Vector2.RIGHT,{"damage_type":"true"})
	check(boss.health.current == hp and is_equal_approx(boss.status.shield(),shield-60.0), "contact consumes energy shield before HP")
	var sweep: Dictionary = trigger(sim,"hammer_fan")
	check(sweep.kind == "melee" and sweep.shape == "cone" and sweep.thematic_action == "gear_arm_sweep", "Sunwheel gear arm is executable cone melee")
	var lightning: Dictionary = trigger(sim,"ladle_drag")
	check(lightning.status.id == "shock" and sim.runtime.hazards.size() > 0, "Sunwheel warned lightning creates damaging electric trace")
	check(boss.apply_arena_counter("BO01:cooling_valve:0",{"thematic_counter":"solar_conduit"}), "arena energy circuit invokes production boss counter")
	check(boss.status.shield() == 0.0 and boss.boss_brain.weakpoint_open(), "energy circuit breaks shield and opens counterattack window")
	boss.boss_phase_started(2,0.69)
	check(sim.runtime.hazards.is_empty(), "phase change retires old lightning")
	boss.configure_boss("BO01",0,777)
	check(boss.status.shield() > 0.0 and not boss.boss_brain.weakpoint_open() and boss.reinforcement_status().count == 0, "retry resets shield, opening and reinforcement state")
	boss.take_damage(boss.status.shield()+1.0,&"primary",Vector2.RIGHT,{"damage_type":"true"})
	check(boss.status.shield() == 0.0 and boss.boss_brain.weakpoint_open(), "ordinary attacks can also break shield without elemental requirement")
	sim.room.queue_free()
	await get_tree().process_frame

func brood_checks() -> void:
	var sim: Dictionary = fixture("BO02")
	var boss: RecordedBoss = sim.boss
	var acid: Dictionary = trigger(sim,"spore_pod")
	check(acid.status.id == "corrosion" and sim.runtime.hazards.size() <= 2, "queen acid pools obey active hazard cap")
	var wing: Dictionary = trigger(sim,"root_link")
	check(wing.kind == "melee" and wing.shape == "cone" and wing.thematic_action == "wing_cone", "queen wing has executable cone hit geometry")
	trigger(sim,"brood_eggs")
	check(sim.runtime.jobs.size() == 2 and sim.room.anchors.size() == 2, "queen lays two real attackable delayed eggs")
	for egg: Node2D in sim.room.anchors:
		egg.health.damage(1000.0)
	tick(sim,0.04)
	check(sim.runtime.jobs.is_empty() and boss.boss_brain.weakpoint_open(), "destroying eggs immediately cancels hatch and exposes queen")
	tick(sim,2.6)
	check(sim.room.spawned.filter(func(actor: Node2D) -> bool: return actor.enemy_id == "M14").is_empty(), "destroyed eggs never hatch later")
	trigger(sim,"brood_eggs")
	tick(sim,2.3)
	var hatchlings: Array = sim.room.spawned.filter(func(actor: Node2D) -> bool: return actor.enemy_id == "M14")
	check(hatchlings.size() == 2, "live eggs hatch actual same-clan insect adds")
	for child: Node2D in hatchlings:
		check(child.profile.biome_id == "B02" and not child.reward_enabled and child.owner_enemy.get_ref() == boss, "insect hatchlings are owner-bound and have no farming rewards")
		child.queue_free()
	await get_tree().process_frame
	trigger(sim,"brood_eggs")
	tick(sim,2.3)
	check(boss.boss_brain.brood_batches == 3 and boss.boss_brain._build_action(boss,sim.player,"brood_eggs").is_empty(), "queen egg attempts have a fight-wide finite cap")
	sim.runtime.cancel_owner(boss)
	await get_tree().process_frame
	check(sim.runtime.active_effect_count() == 0, "queen cancellation retires eggs, pools and hatchlings")
	boss.configure_boss("BO02",0,777)
	check(boss.boss_brain.brood_batches == 0 and not boss.boss_brain.weakpoint_open(), "queen retry resets egg budget and opening")
	sim.room.queue_free()
	await get_tree().process_frame

func grave_checks() -> void:
	var sim: Dictionary = fixture("BO03")
	var boss: RecordedBoss = sim.boss
	var before: Vector2 = sim.player.position
	var stitch: Dictionary = trigger(sim,"glide")
	check(stitch.kind == "pull" and sim.player.position.distance_to(boss.position) < before.distance_to(boss.position), "mayor stitch really pulls a warned target")
	var barrel: Dictionary = trigger(sim,"capacitor_burst")
	check(barrel.kind == "projectile" and barrel.count == 1 and sim.runtime.projectiles.size() == 1, "mayor launches one actual barrel projectile")
	check(boss.boss_brain._build_action(boss,sim.player,"grave_recall").is_empty() and boss.boss_brain.grave_recalls == 0, "empty grave never spends future resurrection budget before adds die")
	for index: int in 2:
		var fallen: Node2D = sim.room.spawn_enemy_summon(boss,"M27",Vector2(300,540+index*34))
		fallen.health.damage(1000.0)
		check(boss.notify_reinforcement_death(fallen) and not boss.notify_reinforcement_death(fallen), "owner-bound dead zombie records one actual grave receipt")
		fallen.queue_free()
	await get_tree().process_frame
	trigger(sim,"grave_recall")
	trigger(sim,"grave_recall")
	check(boss.combat_snapshot().grave_receipts == 0 and boss.combat_snapshot().grave_spawned == 2, "mayor consumes actual finite boss-add corpse receipts for only two recalls")
	for child in sim.room.spawned:
		if not is_instance_valid(child): continue
		check(child.enemy_id == "M27" and child.profile.biome_id == "B03" and not child.reward_enabled and not boss.notify_reinforcement_death(child), "recalled cartoon zombies stay in clan, award no XP/gold and cannot re-register")
	check(boss.boss_brain._build_action(boss,sim.player,"grave_recall").is_empty(), "mayor cannot refill grave limit by cycling skills")
	boss.configure_boss("BO03",0,777)
	await get_tree().process_frame
	check(sim.room.spawned.all(func(child) -> bool: return not is_instance_valid(child)), "retry removes previous recalled actors")
	check(boss.apply_arena_counter("BO03:fuse_box:0",{"thematic_counter":"grave_seal"}) and boss.boss_brain._build_action(boss,sim.player,"grave_recall").is_empty(), "sealing grave prevents future recalls and exposes mayor")
	sim.room.queue_free()
	await get_tree().process_frame

func warchief_checks() -> void:
	var sim: Dictionary = fixture("BO04")
	var boss: RecordedBoss = sim.boss
	var slam: Dictionary = trigger(sim,"resonance_ring")
	check(slam.kind == "ground_area" and slam.shape == "ring" and slam.ring_gap_degrees > 0.0, "warchief slam preserves a real safe arc")
	trigger(sim,"war_drum_rage")
	check(boss.boss_brain.rage_time > 0.0 and boss.boss_brain.outgoing_damage_multiplier() == 1.25, "war drum opens timed actual damage boost")
	var boosted: Dictionary = trigger(sim,"resonance_ring")
	check(is_equal_approx(float(boosted.damage_multiplier),float(slam.damage_multiplier)*1.25), "rage modifies emitted attack damage")
	check(boss.apply_arena_counter("BO04:edge_bell:0",{"thematic_counter":"war_drum"}) and boss.boss_brain.rage_time == 0.0 and boss.boss_brain.outgoing_damage_multiplier() == 1.0, "broken drum cancels rage and future drum casts")
	check(sim.runtime.supports.is_empty(), "broken drum also removes its real haste supports")
	check(boss.boss_brain._build_action(boss,sim.player,"war_drum_rage").is_empty(), "broken drum cannot immediately recharge")
	boss.configure_boss("BO04",0,777)
	boss.boss_brain.current_action = "war_drum_rage"
	boss.boss_brain.state = &"telegraph"
	boss.boss_brain.command = boss.boss_brain._build_action(boss,sim.player,"war_drum_rage")
	check(boss.apply_biome_counter("war_drum",2.5) and boss.boss_brain.current_telegraph().is_empty(), "breaking a warned drum cancels that pending haste cast")
	boss.configure_boss("BO04",0,777)
	sim.runtime.reset_room()
	sim.room.obstructions.assign([Rect2(740,270,80,270)])
	sim.player.position = Vector2(620,400)
	var charge: Dictionary = trigger(sim,"sound_blade")
	check(charge.kind == "charge" and charge.travel_distance > boss.position.distance_to(sim.player.position), "warchief commits clearly warned charge beyond target toward wall")
	tick(sim,1.5)
	check(sim.runtime.motions.is_empty() and boss.position.x < 740.0 and boss.boss_brain.weakpoint == "wall_stunned_warchief", "real wall collision stops motion and gives stunned weakpoint")
	check(boss.boss_brain.state_name() == &"recovery" and boss.boss_brain.weakpoint_time > 0.5, "wall stun blocks skill progression for its readable recovery")
	var casts_before: int = boss.casts.size()
	tick(sim,0.4)
	check(boss.casts.size() == casts_before, "wall stun cannot release an extra skill")
	boss.health.damage(boss.health.maximum)
	check(boss.is_complete() and sim.runtime.active_effect_count() == 0 and boss.boss_brain.stopped, "warchief death cancels all attacks and state machine")
	sim.room.queue_free()
	await get_tree().process_frame
