class_name HeroAbilities
extends RefCounted
## Each successful cast owns a finite timeline. Cancellation drops only future
## events; cost, cooldown, fired projectiles and deployed objects remain committed.

const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const FeedbackScript = preload("res://scripts/presentation/characters/hero_feedback.gd")
const WarriorKit = preload("res://scripts/gameplay/characters/kits/warrior_kit.gd")
const GunnerKit = preload("res://scripts/gameplay/characters/kits/gunner_kit.gd")
const MageKit = preload("res://scripts/gameplay/characters/kits/mage_kit.gd")
const INPUT_SLOTS := ["q", "secondary", "f", "ultimate"]

var owner_player: Node2D
var feedback: Node2D
var active: Dictionary = {}
var last_failure: String = ""
var last_failure_details: Dictionary = {}
var cast_serial: int = 0

func configure(player: Node2D) -> void:
	owner_player = player
	feedback = owner_player.get_node_or_null("HeroFeedback")
	if not is_instance_valid(feedback):
		feedback = FeedbackScript.new()
		feedback.configure(owner_player)
		owner_player.add_child(feedback)
	cancel()

func busy() -> bool:
	return not active.is_empty()

func recovery_chain_wait() -> float:
	if active.is_empty():
		return 0.0
	# A follow-up may trim only recovery. All shots, waves and authored travel
	# belong to the committed action and must finish before its next action.
	var data: Dictionary = active.spec
	var release_end: float = float(data.windup)
	var events: Array[Dictionary] = active.events
	if not events.is_empty():
		release_end = maxf(release_end, float(events.back().time))
	if float(data.get("travel", 0.0)) > 0.0:
		release_end = maxf(release_end, float(data.windup) + float(data.get("travel_time", 0.0)))
	var contact_recovery: float = 0.07 if str(data.slot) in ["secondary", "ultimate"] else 0.06
	if str(data.slot) == "f" or (str(data.hero) == "CH03" and str(data.slot) == "secondary"):
		contact_recovery = 0.045
	var chain_at: float = minf(float(data.duration), release_end + contact_recovery)
	return maxf(0.0, chain_at - float(active.elapsed))

func recovery_chain_ready() -> bool:
	if active.is_empty():
		return true
	return int(active.next_event) >= active.events.size() and recovery_chain_wait() <= 0.00001

func finish_recovery() -> bool:
	if active.is_empty() or not recovery_chain_ready():
		return false
	if is_instance_valid(feedback):
		feedback.cancel_cast()
	_finish_active()
	return true

func _finish_active() -> void:
	# Retire the old reference before completion hooks. Reentrant observers can
	# neither finish it twice nor have a new active cast cleared after callbacks.
	var finished: Dictionary = active
	active = {}
	if str(finished.spec.hero) == "CH02" and str(finished.spec.origin_slot) == "q":
		owner_player.loadout.event("gunner_q_completed", {"event_id":"skill:" + str(finished.serial) + ":q_move", "actual_distance":float(finished.get("actual_travel", 0.0)), "skill_id":str(finished.skill_id), "input_slot":str(finished.input_slot), "damage_source":"skill", "proc_depth":0, "equipment_eligible":true})
	if owner_player.role_kit != null and owner_player.role_kit.has_method("on_skill_finished"):
		owner_player.role_kit.on_skill_finished(finished)

func cancel() -> void:
	active.clear()
	if is_instance_valid(feedback):
		feedback.cancel_cast()

func movement_scale() -> float:
	if active.is_empty():
		return 1.0
	var data: Dictionary = active.spec
	var clock: float = float(active.elapsed)
	if float(data.get("travel", 0.0)) > 0.0 and clock >= float(data.windup) and clock < float(data.windup) + float(data.get("travel_time", 0.0)):
		return 0.0
	return float(data.get("movement", 1.0))

func hero_key() -> String:
	var identifier: String = owner_player.hero_id() if is_instance_valid(owner_player) else "CH01"
	return {"breaker":"CH01", "ranger":"CH02", "resonator":"CH03"}.get(identifier, identifier)

static func preview_spec(hero_id: String, level: int, stats: Dictionary, slot: String) -> Dictionary:
	var helper := HeroAbilities.new()
	return helper.spec(slot, hero_id, level, stats)

## Preview and live actors share the three source-specific H definitions. AD
## remains a separate aggregated stat; basic AP must never enter skill H twice.
static func preview_powers(hero: String, stats: Dictionary) -> Dictionary:
	var version: int = int(stats.get("ruleset_version", Numbers.LEGACY))
	var fallback: float = 27.0 if hero == "CH01" else 24.0 if hero == "CH02" else 18.0
	var attack: Variant = Numbers.amount(float(stats.get("attack", Numbers.scale(fallback, version))), version)
	var ability: Variant = Numbers.amount(float(stats.get("ability_power", 0.0)), version)
	var ratios: Dictionary = Numbers.value("mage_power_ratios")
	var skill_power: Variant=Numbers.amount(float(attack)+(float(ratios.skill_ap)*float(ability) if hero=="CH03" else 0.0),version)
	# Candidate is frozen in the isolated run stats, applies to spells against
	# every target, and never multiplies AP/basic/relic/shield/healing sources.
	if hero=="CH03" and version==Numbers.V2 and int(stats.get("mage_balance_candidate",0))==1:
		skill_power=Numbers.amount(float(skill_power)*float(stats.get("mage_spell_power_multiplier",1.0)),version)
	if hero=="CH01" and version==Numbers.V2 and int(stats.get("warrior_balance_candidate",0))==1:
		skill_power=Numbers.amount(float(skill_power)*float(stats.get("warrior_skill_power_multiplier",1.0)),version)
	return {
		"basic_H":Numbers.amount(float(attack) + (float(ratios.basic_ap) * float(ability) if hero == "CH03" and version == Numbers.V2 else 0.0), version),
		"skill_H":skill_power,
		"relic_H":Numbers.amount(float(stats.get("ability_power", Numbers.scale(28.0, version))), version) if hero == "CH03" else attack,
	}

static func packet_amount(coefficient: float, power: float, stats: Dictionary) -> Variant:
	return Numbers.amount(coefficient * power, int(stats.get("ruleset_version", Numbers.LEGACY)))

static func kit_script(hero: String) -> Script:
	return WarriorKit if hero == "CH01" else GunnerKit if hero == "CH02" else MageKit

static func preview_skill_spec(hero: String, stats: Dictionary, skill_id: String, input_slot: String = "") -> Dictionary:
	return _catalog_spec(hero, stats, skill_id, input_slot, stats.get("skill_progress", {}).get(skill_id, {}))

static func _catalog_spec(hero: String, stats: Dictionary, skill_id: String, input_slot: String, progress: Dictionary) -> Dictionary:
	var kit: Script = kit_script(hero)
	var data: Dictionary = {}
	for entry: Dictionary in kit.skill_specs():
		if str(entry.get("skill_id", "")) == skill_id:
			data = entry.duplicate(true)
			break
	if data.is_empty(): return {}
	var rank: int = clampi(int(progress.get("level", progress.get("rank", 1))), 1, 5)
	var branch: String = str(progress.get("branch", "")).to_upper()
	var gate: int = 4 if skill_id.ends_with("SK01") else 5 if skill_id.ends_with("SK04") else 99
	if rank < gate or branch not in ["A", "B"]: branch = ""
	if rank >= 2: data.merge(data.get("mastery_upgrade", {}), true)
	if not branch.is_empty(): data.merge(data.get("branch_options", {}).get(branch, {}), true)
	var variant_helper: RefCounted = kit.new()
	if variant_helper.has_method("apply_mastery_branch"):
		variant_helper.apply_mastery_branch(data, rank, branch)
	elif variant_helper.has_method("apply_skill_variant"):
		variant_helper.apply_skill_variant(data, rank, branch)
	data["hero"] = hero
	data["icon_id"] = str(data.get("icon_id", "skill." + skill_id.to_lower()))
	data["slot"] = str(data.get("origin_slot", "skill"))
	if str(data.slot).is_empty(): data.slot = "skill"
	data["origin_slot"] = str(data.slot)
	data["input_slot"] = input_slot
	data["input"] = {"q":"Q", "secondary":"W", "f":"E", "ultimate":"R"}.get(input_slot, "")
	data["branch"] = branch
	data["rank"] = rank
	data["unlock"] = 1
	data["damage_type"] = str(data.get("damage_type", "magic" if hero == "CH03" else "physical"))
	data["windup"] = float(data.get("windup", 0.12))
	data["duration"] = maxf(float(data.get("duration", 0.36)), float(data.windup) + 0.08)
	data["movement"] = float(data.get("movement", 0.85))
	data["coefficient"] = float(data.get("coefficient", 0.0))
	data["cost"] = Numbers.scale(float(data.get("cost", 0.0)), int(stats.get("ruleset_version", Numbers.LEGACY)))
	data["base_cooldown"] = float(data.get("cooldown", 0.0))
	var cap: float = float(Numbers.value("caps").cooldown_reduction) if Numbers.is_v2(stats) else 0.30
	data["cooldown"] = float(data.base_cooldown) * (1.0 - clampf(float(stats.get("cooldown_reduction", 0.0)), 0.0, cap))
	data["mastery_multiplier"] = 1.0 + 0.05 * (rank - 1)
	return data

func spec(slot: String, preview_hero: String = "", _preview_level: int = -1, preview_stats: Dictionary = {}) -> Dictionary:
	var preview: bool = not preview_hero.is_empty()
	var hero: String = preview_hero if preview else hero_key()
	var stats: Dictionary = preview_stats if preview else Game.run.stats if Game.run != null else {}
	var index: int = INPUT_SLOTS.find(slot)
	var skill_id: String = slot if slot.begins_with(hero + "_SK") else hero + "_SK%02d" % (index + 1)
	var progress: Dictionary = stats.get("skill_progress", {}).get(skill_id, {})
	if not preview and is_instance_valid(owner_player):
		skill_id = owner_player.skill_id_for_slot(slot) if index >= 0 else slot
		progress = owner_player.skill_progress(skill_id)
	elif index >= 0 and stats.get("skill_loadout") is Array and stats.skill_loadout.size() == 4:
		skill_id = str(stats.skill_loadout[index])
		progress = stats.get("skill_progress", {}).get(skill_id, {})
	return _catalog_spec(hero, stats, skill_id, slot if index >= 0 else "", progress)

func can_cast(slot: String, target: Vector2, ignore_busy: bool = false, preview_cooldown: bool = false) -> bool:
	# Same checks as commitment, but no resource/cooldown/stack/audio mutation.
	return try_cast(slot, target, true, false, ignore_busy, preview_cooldown)

func try_cast(slot: String, target: Vector2, validate_only: bool = false, allow_recovery_chain: bool = false, ignore_busy: bool = false, preview_cooldown: bool = false) -> bool:
	last_failure = ""
	last_failure_details = {}
	if not is_instance_valid(owner_player) or Game.run == null or Game.run.hp <= 0.0:
		return _fail("unavailable")
	if slot not in INPUT_SLOTS: return _fail("invalid_skill")
	if busy() and not (validate_only and ignore_busy) and not (allow_recovery_chain and recovery_chain_ready()):
		return _fail("busy")
	var data: Dictionary = spec(slot)
	if data.is_empty() or not owner_player.skill_is_learned(str(data.skill_id)):
		return _fail("locked")
	if float(owner_player.cooldowns.get(str(data.skill_id), 0.0)) > 0.00001 and not (validate_only and preview_cooldown):
		return _fail("cooldown")
	var origin: Vector2 = owner_player.position
	var direction: Vector2 = owner_player.aim_direction.normalized()
	if not direction.is_finite() or direction.is_zero_approx():
		return _fail("invalid_direction")
	var hero: String = data.hero
	if float(owner_player.get("_enemy_root_remaining")) > 0.0 and float(data.get("travel", 0.0)) > 0.0:
		return _fail("invalid_ground", {"cause":"rooted"})
	var travel_direction: Vector2 = direction
	if hero == "CH02" and str(data.origin_slot) == "q":
		var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		travel_direction = move.normalized() if not move.is_zero_approx() else -direction
	if float(data.get("travel", 0.0)) > 0.0:
		var step: Vector2 = owner_player.room.move_actor(origin, travel_direction * 4.0, Balance.PLAYER_RADIUS)
		if step.distance_squared_to(origin) < 0.1:
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	var ground_cast: bool = str(data.get("target_type", "direction")) == "ground"
	if bool(data.get("follow_player", false)):
		# The mobile branch is self-centered, so an unused cursor over a wall
		# must not block it or consume a different targeting rule than its effect.
		target = origin
	if ground_cast:
		if not target.is_finite():
			return _fail("invalid_ground", {"cause":"blocked_ground"})
		if origin.distance_to(target) > float(data.range) + 0.01:
			if hero == "CH01" and str(data.origin_slot) == "ultimate":
				target = owner_player.room.move_actor(origin, origin.direction_to(target) * float(data.range), 4.0)
			else: return _fail("invalid_ground", {"cause":"out_of_range", "range":float(data.range), "distance":origin.distance_to(target)})
		if not owner_player.room.valid_ground(target, 14.0) or not owner_player.room.has_line_of_sight(origin, target):
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	if hero == "CH01" and str(data.origin_slot) == "ultimate":
		if not target.is_finite():
			return _fail("invalid_ground", {"cause":"blocked_ground"})
		var offset: Vector2 = target - origin
		if offset.length() > float(data.range):
			offset = offset.normalized() * float(data.range)
		target = owner_player.room.move_actor(origin, offset, 4.0)
		if not owner_player.room.valid_ground(target, 4.0):
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	var ground_facing: bool = ground_cast or (hero == "CH01" and str(data.origin_slot) == "ultimate")
	if ground_facing and origin.distance_squared_to(target) > 0.001:
		# A queued landing is a committed point. Its body/weapon faces that point,
		# even if the mouse has moved elsewhere before the queued cast starts.
		direction = origin.direction_to(target)
	var cost: float = float(data.cost)
	if owner_player.has_method("resource_cost"):
		cost = owner_player.resource_cost(cost)
	if not is_finite(cost) or cost < 0.0 or Game.run.resource < cost:
		return _fail("resource", {"cost":cost, "resource":float(Game.run.resource)})
	if validate_only:
		return true
	if not Game.try_spend_resource(cost):
		return _fail("resource")
	# Validation and payment succeeded. Retire only the old completed recovery;
	# released projectiles, deployments and feedback still own their lifetimes.
	if busy():
		finish_recovery()
	owner_player.cooldowns[str(data.skill_id)] = float(data.cooldown)
	owner_player.resource_delay = float(Game.run.stats.get("resource_regen_delay", 0.5 if hero == "CH02" else 0.8))
	cast_serial += 1
	var base_power: float = float(owner_player.skill_power())
	var mastery: float = float(data.mastery_multiplier)
	var class_multiplier: float = float(owner_player.role_kit.damage_multiplier(str(data.skill_id))) if owner_player.role_kit != null and owner_player.role_kit.has_method("damage_multiplier") else 1.0
	active = {"spec":data, "skill_id":str(data.skill_id), "input_slot":slot, "branch":str(data.branch), "rank":int(data.rank), "cast_id":cast_serial, "elapsed":0.0, "origin":origin, "target":target, "direction":direction, "initial_direction":direction, "travel_direction":travel_direction, "ground_facing":ground_facing,"base_power":base_power, "power":packet_amount(mastery * class_multiplier, base_power, Game.run.stats), "guard_multiplier":mastery, "attacker_stats":Game.run.stats.duplicate(true), "class_state":owner_player.class_state_snapshot(), "events":_timeline(data), "next_event":0, "serial":cast_serial, "paid_cost":cost, "actual_travel":0.0, "released":false, "shielded_cast":float(Game.run.shield) > 0.0, "combat":owner_player.in_real_combat()}
	owner_player.visual_event("cast_" + str(data.slot), float(data.duration))
	if is_instance_valid(feedback):
		feedback.cast_started(data, active.direction, active.target, cast_serial)
	return true

func _fail(reason: String, details: Dictionary = {}) -> bool:
	last_failure = reason
	last_failure_details = details.duplicate(true)
	return false

func _timeline(data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if owner_player.role_kit != null and owner_player.role_kit.has_method("timeline"):
		for event: Dictionary in owner_player.role_kit.timeline(data):
			if is_finite(float(event.get("time", -1.0))) and float(event.get("time", -1.0)) >= 0.0:
				events.append(event.duplicate(true))
	if events.size() > 32: events.resize(32)
	if events.is_empty(): events.append({"time":float(data.windup), "index":0})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	data.duration = maxf(float(data.duration), float(events.back().time) + 0.08)
	return events

func tick(delta: float) -> void:
	if not is_instance_valid(owner_player):
		return
	if is_instance_valid(feedback):
		feedback.advance(delta)
	if active.is_empty():
		return
	if Game.run == null or Game.run.hp <= 0.0:
		cancel()
		return
	var previous: float = float(active.elapsed)
	var finish: float = minf(previous + maxf(delta, 0.0), float(active.spec.duration))
	var events: Array[Dictionary] = active.events
	while int(active.next_event) < events.size():
		var event: Dictionary = events[int(active.next_event)]
		var event_time: float = float(event.time)
		if event_time > finish + 0.00001:
			break
		_advance(previous, event_time)
		active.elapsed = event_time
		active.next_event = int(active.next_event) + 1
		_resolve(int(event.index))
		previous = event_time
	_advance(previous, finish)
	active.elapsed = finish
	if finish >= float(active.spec.duration) - 0.00001:
		_finish_active()

func _advance(from_time: float, to_time: float) -> void:
	var data: Dictionary = active.spec
	var elapsed: float = maxf(0.0, to_time - from_time)
	var aim: Vector2 = owner_player.aim_direction.normalized()
	if data.hero == "CH02" and data.slot == "ultimate" and not aim.is_zero_approx():
		var direction: Vector2 = active.direction
		active.direction = direction.rotated(clampf(direction.angle_to(aim), -PI * 0.5 * elapsed, PI * 0.5 * elapsed))
	elif from_time < float(data.windup) and not aim.is_zero_approx() and not bool(active.get("ground_facing",false)):
		if data.hero == "CH01" and data.slot == "secondary":
			var initial: Vector2 = active.initial_direction
			active.direction = initial.rotated(clampf(initial.angle_to(aim), -PI / 6.0, PI / 6.0))
		elif data.slot != "q" or data.hero != "CH01":
			active.direction = aim
	var distance: float = float(data.get("travel", 0.0))
	var duration: float = float(data.get("travel_time", 0.0))
	if distance > 0.0 and duration > 0.0:
		var start: float = float(data.windup)
		var portion: float = maxf(0.0, minf(to_time, start + duration) - maxf(from_time, start)) / duration
		if portion > 0.0 and float(owner_player.get("_enemy_root_remaining")) <= 0.0:
			var previous: Vector2 = owner_player.position
			owner_player.position = owner_player.room.move_actor(owner_player.position, active.travel_direction * distance * portion, Balance.PLAYER_RADIUS)
			active["actual_travel"] = float(active.get("actual_travel", 0.0)) + previous.distance_to(owner_player.position)
			owner_player.visual_event("skill_slide", 0.10)

func _resolve(index: int) -> void:
	if owner_player.role_kit != null and owner_player.role_kit.has_method("can_release") and not owner_player.role_kit.can_release(active, index): return
	var first_release: bool = not bool(active.released)
	if first_release:
		active.released = true
		var modifier: Dictionary = owner_player.notify_skill_release(active)
		active.power = packet_amount(float(modifier.get("damage_multiplier", 1.0)), float(active.power), active.attacker_stats)
		active.guard_multiplier = float(active.guard_multiplier) * float(modifier.get("shield_multiplier", modifier.get("guard_multiplier", 1.0)))
		owner_player.record_skill_release(active)
	var data: Dictionary = active.spec
	var context: Dictionary = {"root_event_id":"skill:" + str(active.serial), "attack_id":"skill:" + str(active.serial) + ":" + str(index), "cast_id":int(active.serial), "skill_id":str(active.skill_id), "input_slot":str(active.input_slot), "skill_slot":str(data.origin_slot), "branch":str(active.branch), "power":active.power, "H":active.power, "base_power":active.base_power, "original_basic":false, "equipment_eligible":true, "original":true, "damage_type":str(data.damage_type), "attacker_stats":active.attacker_stats, "class_state":active.class_state, "spell_critical_eligible":str(data.hero) == "CH03", "paid_cost":float(active.paid_cost), "damage_source":"skill", "proc_depth":0, "b05_direction":active.direction, "b05_origin":owner_player.position, "H_skill":active.power, "shielded_cast":bool(active.get("shielded_cast", false)), "berserk_active":bool(active.class_state.get("berserk_active", false))}
	context["b09_segment"] = index
	active["hit_context"] = context
	if owner_player.role_kit != null and owner_player.role_kit.has_method("resolve_skill"): owner_player.role_kit.resolve_skill(active, index)
	owner_player.visual_event("release_" + str(data.slot), 0.12)
	var audio_slot: String = str(data.get("audio_slot", data.origin_slot))
	owner_player._play_combat_audio(&"cast", [str(data.hero), audio_slot])
	if first_release: owner_player._play_combat_audio(&"skill_music", [str(data.hero), audio_slot])
	if is_instance_valid(feedback):
		var center: Vector2 = active.target if bool(active.ground_facing) else owner_player.position
		feedback.skill_released(data, active.direction, center, index, active.events.size(), int(active.serial))

func _projectile_origin(direction: Vector2) -> Vector2:
	# A long visible barrel must not put the collision origin through a thin wall.
	return owner_player.room.move_actor(owner_player.position, direction * 19.0, 4.0)
