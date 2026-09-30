class_name EquipmentEffects
extends RefCounted
## Deterministic equipment event reducer; never reads/mutates Game or scene nodes.
## configure accepts six slot -> EQ IDs, resolved stats, and rage/energy/mana.
## Time advances ONLY through advance(delta, context), so menus/pause freeze ICDs.
## before_hit reads PRE-HIT target_states, returning damage/crit/knockback bonuses.
## after_hit follows a confirmed hit. status_applied RECORDS successful application
## (not a request, not immunity). When resume_after_statuses is true, the caller
## must confirm accepted statuses, then send statuses_resolved even if all failed;
## this resumes remaining slots in order. Continuations can request feet statuses
## once more before completing charm/set effects. Native status confirmations
## arrive before after_hit. kill follows confirmed death, once per target.
## Other events: room_enter, dash, dash_end, damaged, shield_gain, skill_cast.
## Every discrete event requires unique attack_id or event_id; attacks share their
## root_event_id across targets and stages. Sources: primary (depth 0), burn tick
## (kill-only S01 exception), equipment/relic/status (never eligible recursive hits).
## Context: hp,max_hp,shield,equipment_shield,resource,resource_max,resource_type;
## H (basic attack snapshot), X (raw pre-crit/pre-bonus strike), attack_id,target_id,
## target_states:Array, target_full_hp, original_basic,equipment_eligible,critical,
## applied_states:Array, nearby_targets:[{id,distance,alive}], moving,
## current_speed,base_speed,nearby_burning; damaged hp_damage,shield_absorbed,
## shield_broken,enemy_damage; room_enter room_id,unvisited; remaining_cooldowns.
## Outputs are additive conditionals, except knockback *_scale which multiply;
## shields:[{source,ratio,duration}] preserves each shield's expiry and combines
## sources by max; shield_ratio is a fallback only. Shield/heal/resource restores
## are ONE-SHOT commands, never stats.
## statuses/status_extensions target IDs; bonus_hits use raw X and never crit.
## Caller applies modifier caps with existing base stats, applies commands once,
## and calls status_applied only with statuses the target actually accepted.
## reserve_native/root_usage share the four-package budget with original status
## and relic packets. Optional coefficient reservation is for equipment-derived
## damage; legacy relic coefficients do not consume the equipment-only 1.2X cap.
## skill_cost is a pure preview; skill_cast consumes EQ56 only after paid success.

const Registry = preload("res://scripts/data/content_registry.gd")
const ENEMY_STATES: Array[String] = ["burn", "shock", "chill", "corrosion", "bleed", "grievous"]
const ACTIVE_SLOTS: Array[String] = ["Q", "right", "F", "R"]
var clock: float = 0.0
var equipped: Dictionary = {}
var set_counts: Dictionary = {}
var stats: Dictionary = {}
var resource_type: String = ""
var cooldowns: Dictionary = {}
var buffs: Dictionary = {}
var windows: Dictionary = {}
var roots: Dictionary = {}
var rooms: Dictionary = {}
var deaths: Dictionary = {}
var counts: Dictionary = {}
var same_target: Dictionary = {}
var first_full_targets: Dictionary = {}
var shock_targets: Dictionary = {}
var heal_history: Array[Dictionary] = []
var resource_history: Array[Dictionary] = []
var refund_history: Array[Dictionary] = []
var undamaged_time: float = 0.0
var eq12_spent_at: float = 0.0
var movement_time: float = 0.0
var dash_time: float = -100.0
var room_id: String = ""
var room_low_shield_used: bool = false
var room_first_kill_used: bool = false
var delayed_shield_at: float = -1.0

static func implemented_ids() -> Array[String]:
	var result: Array[String] = []
	for index in range(1, 61):
		result.append("EQ%02d" % index)
	return result

static func implemented_set_ids() -> Array[String]:
	return ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"]

func configure(loadout: Dictionary, resolved_stats: Dictionary, type: String) -> void:
	stats = resolved_stats.duplicate(true)
	resource_type = type if type in ["rage", "energy", "mana"] else ""
	var binding: Dictionary = loadout_binding(loadout)
	equipped = binding.equipped
	set_counts = binding.set_counts
	clock = 0.0
	for state in [cooldowns, buffs, windows, roots, rooms, deaths, counts, same_target, first_full_targets, shock_targets]:
		state.clear()
	heal_history.clear()
	resource_history.clear()
	refund_history.clear()
	undamaged_time = 0.0
	eq12_spent_at = 0.0
	movement_time = 0.0
	dash_time = -100.0
	room_id = ""
	room_low_shield_used = false
	room_first_kill_used = false
	delayed_shield_at = -1.0

## Bind rule identities without replaying entry, clearing ICDs or advancing time.
## The caller restores a migrated snapshot after this when changing a live run.
func rebind(loadout: Dictionary, resolved_stats: Dictionary, type: String) -> void:
	var previous: Dictionary = {"equipped":equipped.duplicate(), "set_counts":set_counts.duplicate()}
	var next: Dictionary = loadout_binding(loadout)
	for values: Dictionary in [buffs, windows, counts, same_target]:
		_prune_loadout_sources(values, previous, next)
	if not source_active("S05_6", previous) or not source_active("S05_6", next):
		delayed_shield_at = -1.0
	if not source_active("S02_6", previous) or not source_active("S02_6", next):
		shock_targets.clear()
	# Queued slot continuations belong to the old loadout. Consumed budgets and
	# histories remain intact; safe-boundary restore clears these scene roots.
	for root: Dictionary in roots.values():
		root.erase("pending_context")
		root.erase("pending_stage")
	equipped = next.equipped
	set_counts = next.set_counts
	stats = resolved_stats.duplicate(true)
	resource_type = type if type in ["rage", "energy", "mana"] else ""

static func loadout_binding(loadout: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	var sets: Dictionary = {}
	for slot in Registry.SLOTS:
		var id: String = str(loadout.get(slot, ""))
		var item: Dictionary = Registry.equipment(id)
		if item.is_empty() or str(item.get("slot", "")) != slot or items.has(id):
			continue
		items[id] = true
		var set_id: String = str(item.get("set_id", ""))
		if not set_id.is_empty():
			sets[set_id] = int(sets.get(set_id, 0)) + 1
	return {"equipped":items, "set_counts":sets}

## IDs may carry a room/target suffix. Set sources require their exact tier,
## so retaining two pieces never keeps a former four/six-piece benefit.
static func source_active(source: String, binding: Dictionary) -> bool:
	var id: String = source.trim_prefix("equipment:").trim_prefix("set_").get_slice(":", 0)
	if id.begins_with("EQ"):
		return bool(binding.get("equipped", {}).get(id, false))
	var pieces: PackedStringArray = id.split("_")
	return pieces.size() == 2 and pieces[0] in implemented_set_ids() and pieces[1] in ["2", "4", "6"] and int(binding.get("set_counts", {}).get(pieces[0], 0)) >= int(pieces[1])

static func _prune_loadout_sources(values: Dictionary, previous: Dictionary, next: Dictionary) -> void:
	for id: String in values.keys():
		if not source_active(id, previous) or not source_active(id, next):
			values.erase(id)

## Pure save-state migration. Never clear cooldowns, consumed room flags or
## rate-limit histories: taking an item off and on cannot replenish rewards.
static func for_loadout(state: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	var previous: Dictionary = loadout_binding(old_loadout)
	var next: Dictionary = loadout_binding(new_loadout)
	# Older checkpoints used the shared dash timer for these two effects. Only
	# a source worn on both sides may retain that unconsumed, remaining window.
	for id: String in ["EQ60", "S08_4"]:
		var until: float = float(result.dash_time) + (3.0 if id == "EQ60" else 2.0)
		if not result.windows.has(id) and source_active(id, previous) and source_active(id, next) and until > float(result.clock):
			result.windows[id] = until
	for key: String in ["buffs", "windows", "counts"]:
		_prune_loadout_sources(result[key], previous, next)
	if not source_active("S05_6", previous) or not source_active("S05_6", next):
		result.delayed_shield_at = -1.0
	return result

## Cache refresh only. Unlike advance(0), this cannot release a due shield or
## refund command while the player is looking at the replacement card.
func passive_modifiers(ctx: Dictionary) -> Dictionary:
	var result: Dictionary = _empty()
	_modifiers(ctx, result)
	return _cap_modifiers(result)

func _empty() -> Dictionary:
	return {"damage_bonus":0.0, "crit_bonus":0.0, "attack_speed_bonus":0.0,
		"move_speed_bonus":0.0, "damage_reduction_bonus":0.0,
		"knockback_scale":1.0, "received_knockback_scale":1.0, "slow_resistance":0.0,
		"chill_duration_bonus":0.0, "cost_reduction":0.0, "resource_restore":0.0,
		"resource_type":resource_type, "heal_ratio":0.0, "shield_ratio":0.0,
		"shield_duration":4.0, "shields":[], "resume_after_statuses":false, "cooldown_refunds":[], "statuses":[],
		"status_extensions":[], "self_statuses":[], "bonus_hits":[], "triggered":[]}

func _has(id: String) -> bool:
	return equipped.has(id)

func _has_set(id: String, pieces: int) -> bool:
	return int(set_counts.get(id, 0)) >= pieces

func _state(ctx: Dictionary, id: String) -> bool:
	return id in ctx.get("target_states", [])

func _eligible(ctx: Dictionary) -> bool:
	return bool(ctx.get("equipment_eligible", false)) and int(ctx.get("proc_depth", 0)) == 0 and str(ctx.get("damage_source", "primary")) in ["primary", "basic", "skill"] and bool(ctx.get("valid_target", true))

func _basic(ctx: Dictionary) -> bool:
	return _eligible(ctx) and bool(ctx.get("original_basic", false))

func _health_ratio(ctx: Dictionary) -> float:
	return float(ctx.get("hp", 0.0)) / maxf(1.0, float(ctx.get("max_hp", stats.get("max_hp", 1.0))))

func _modifiers(ctx: Dictionary, out: Dictionary) -> void:
	var shielded: bool = float(ctx.get("shield", 0.0)) > 0.0
	if _has("EQ11") and _health_ratio(ctx) < 0.30:
		out.move_speed_bonus += 0.05
	if _has("EQ17") and shielded:
		out.received_knockback_scale *= 0.80
	if _has("EQ23") and bool(ctx.get("nearby_burning", false)):
		out.damage_reduction_bonus += 0.04
	if _has("EQ28") and float(ctx.get("current_speed", 1.0)) < float(ctx.get("base_speed", 1.0)):
		out.received_knockback_scale *= 0.75
	if _has("EQ31") and _health_ratio(ctx) >= 1.0:
		out.damage_bonus += 0.03
	if _has("EQ37") and shielded:
		out.attack_speed_bonus += 0.04
	if _has("EQ41"):
		out.received_knockback_scale *= 0.90
	if _has("EQ45") and bool(ctx.get("self_chilled", false)):
		out.slow_resistance += 0.20
	if _has("EQ47") and shielded:
		out.slow_resistance += 0.15
	if _has("EQ51") and _health_ratio(ctx) < 0.30:
		out.damage_reduction_bonus += 0.03
	if _has_set("S05", 2) and shielded:
		out.damage_bonus += 0.06
	if _has_set("S03", 2):
		out.chill_duration_bonus += 0.20
	if _window("EQ56"):
		out.cost_reduction = 0.08
	for id: String in buffs:
		var buff: Dictionary = buffs[id]
		if float(buff.until) <= clock:
			continue
		if str(buff.stat) == "received_knockback_scale":
			out[buff.stat] *= float(buff.amount)
		else:
			out[buff.stat] += float(buff.amount)

func _cap_modifiers(out: Dictionary) -> Dictionary:
	out.damage_bonus = clampf(out.damage_bonus, 0.0, maxf(0.0, 0.60 - float(stats.get("damage_bonus", 0.0))))
	out.crit_bonus = clampf(out.crit_bonus, 0.0, maxf(0.0, 0.75 - float(stats.get("crit_chance", 0.0))))
	out.attack_speed_bonus = clampf(out.attack_speed_bonus, 0.0, maxf(0.0, 0.60 - float(stats.get("attack_speed_bonus", 0.0))))
	out.move_speed_bonus = clampf(out.move_speed_bonus, 0.0, maxf(0.0, 0.45 - float(stats.get("move_speed_bonus", 0.0))))
	out.damage_reduction_bonus = clampf(out.damage_reduction_bonus, 0.0, maxf(0.0, 0.35 - float(stats.get("equipment_damage_reduction", 0.0))))
	out.chill_duration_bonus = clampf(out.chill_duration_bonus, 0.0, maxf(0.0, 0.40 - float(stats.get("status_duration", 0.0))))
	out.slow_resistance = clampf(out.slow_resistance, 0.0, 1.0)
	return out

func advance(delta: float, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = _empty()
	if delta < 0.0 or not is_finite(delta):
		return out
	clock += delta
	undamaged_time += delta
	movement_time = movement_time + delta if bool(ctx.get("moving", false)) else 0.0
	if _has("EQ49") and movement_time >= 2.0 and not _window("EQ49"):
		windows.EQ49 = clock + 3.0
		movement_time = 0.0
	_prune_history(heal_history, 1.0)
	_prune_history(resource_history, 5.0)
	_prune_history(refund_history, 1.0)
	for id in buffs.keys():
		if float(buffs[id].until) <= clock:
			buffs.erase(id)
	if delayed_shield_at >= 0.0 and clock >= delayed_shield_at:
		if float(ctx.get("hp", 0.0)) > 0.0: _shield(out, ctx, 0.10, "S05_6")
		delayed_shield_at = -1.0
	if _has("EQ22") and undamaged_time >= 5.0 and _ready("EQ22") and float(ctx.get("remaining_cooldowns", {}).get("dash", 0.0)) > 0.0:
		var root: Dictionary = _root("advance:" + str(clock))
		_refund(out, ctx, root, "EQ22", 8.0, "dash", 0.20)
	_modifiers(ctx, out)
	return _cap_modifiers(out)

func handle(event: String, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = _empty()
	var event_id: String = str(ctx.get("attack_id", ctx.get("event_id", "")))
	if event_id.is_empty():
		return out
	var root_id: String = str(ctx.get("root_event_id", event_id))
	var root: Dictionary = _root(root_id)
	# Original skill/status/relic packets can reserve the same root budget before
	# equipment dispatch. These are cumulative counts, never per-target additions.
	root.packets = maxi(int(root.packets), int(ctx.get("root_packets_used", 0)))
	root.coefficient = maxf(float(root.coefficient), float(ctx.get("root_coefficient_used", 0.0)))
	var target: String = str(ctx.get("target_id", ""))
	var key: String = event + ":" + event_id + ":" + target
	if event == "status_applied":
		key += ":" + str(ctx.get("application_id", "")) + ":" + ",".join(ctx.get("applied_states", []))
	if event == "statuses_resolved": key += ":" + str(root.get("pending_stage", "none"))
	if root.seen.has(key):
		return out
	root.seen[key] = true
	match event:
		"room_enter": _enter_room(ctx, root, out)
		"dash": _dash(ctx, root, out)
		"dash_end":
			if _has("EQ30") and _activate("EQ30", 5.0, root, out, false):
				_buff("EQ30", "damage_reduction_bonus", 0.06, 1.0)
			if _has("EQ48") and _activate("EQ48", 6.0, root, out):
				_shield(out, ctx, 0.02)
		"damaged": _damaged(ctx, root, out)
		"skill_cast":
			if float(ctx.get("base_cost", 0.0)) > 0.0 and bool(ctx.get("cast_success", true)) and str(ctx.get("resource_type", resource_type)) == resource_type:
				windows.erase("EQ56")
		"before_hit":
			if _eligible(ctx): _before(ctx, root, out)
		"after_hit":
			if _eligible(ctx): _after(ctx, root, out)
		"status_applied":
			if _eligible(ctx): _status_applied(ctx, root, out)
		"statuses_resolved":
			if root.has("pending_context"):
				var pending: Dictionary = root.pending_context
				var stage: String = str(root.get("pending_stage", "weapon"))
				root.erase("pending_context")
				if stage == "feet": _after_charm(pending, root, out)
				else: _after_rest(pending, root, out)
		"kill": _kill(ctx, root, out)
	_modifiers(ctx, out)
	return _cap_modifiers(out)

func skill_cost(base_cost: float, ctx: Dictionary = {}) -> float:
	if base_cost <= 0.0:
		return 0.0
	var reduction: float = 0.08 if _window("EQ56") and str(ctx.get("resource_type", resource_type)) == resource_type else 0.0
	return maxf(1.0, base_cost * (1.0 - minf(0.20, reduction)))

func _root(id: String) -> Dictionary:
	if not roots.has(id):
		roots[id] = {"seen":{}, "reserved":{}, "packets":0, "coefficient":0.0, "first_target":"", "flags":{}, "counted":false, "post_counted":false, "post_completed":false, "applied":{}, "attack_modifiers":{"damage_bonus":0.0,"knockback_scale":1.0}, "armed":{}}
	return roots[id]

## The adapter reserves original skill-status / legacy relic packets BEFORE
## dispatching equipment. A stable packet ID is one shared package across targets.
## Coefficient is the SUM across that package's targets. Repeat reservations are
## idempotent; callers still own once-only execution of their reserved package.
func reserve_native(root_id: String, packet_id: String, coefficient: float = 0.0) -> bool:
	if root_id.is_empty() or packet_id.is_empty() or coefficient < 0.0 or not is_finite(coefficient): return false
	var root: Dictionary = _root(root_id)
	if root.reserved.has(packet_id): return bool(root.reserved[packet_id])
	var allowed: bool = int(root.packets) < 4 and float(root.coefficient) + coefficient <= 1.200001
	root.reserved[packet_id] = allowed
	if allowed:
		root.packets += 1
		root.coefficient += coefficient
	return allowed

func root_usage(root_id: String) -> Dictionary:
	var root: Dictionary = _root(root_id)
	return {"packets":int(root.packets), "coefficient":float(root.coefficient)}

func _ready(id: String) -> bool:
	return clock + 0.000001 >= float(cooldowns.get(id, 0.0))

func _activate(id: String, icd: float, root: Dictionary, out: Dictionary, packet: bool = true) -> bool:
	if not _ready(id) or (packet and int(root.packets) >= 4):
		return false
	if packet:
		root.packets += 1
	cooldowns[id] = clock + icd
	out.triggered.append(id)
	return true

func _buff(id: String, stat: String, amount: float, duration: float) -> void:
	buffs[id] = {"stat":stat, "amount":amount, "until":clock + duration}

func _window(id: String) -> bool:
	return float(windows.get(id, -1.0)) > clock

func _nth(id: String, interval: int) -> bool:
	counts[id] = int(counts.get(id, 0)) + 1
	if int(counts[id]) >= interval:
		counts[id] = 0
		return true
	return false

func _consecutive(id: String, target: String, interval: int) -> bool:
	var previous: Dictionary = same_target.get(id, {})
	var count: int = int(previous.get("count", 0)) if str(previous.get("target", "")) == target and clock - float(previous.get("time", -100.0)) <= 3.0 else 0
	count += 1
	same_target[id] = {"target":target, "count":0 if count >= interval else count, "time":clock}
	return count >= interval

func _before(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	var target: String = str(ctx.get("target_id", ""))
	var first: bool = not bool(root.counted)
	if first:
		root.counted = true
		root.first_target = target
		for id in ["EQ02", "EQ08", "EQ10", "EQ18", "EQ38", "EQ40", "EQ49", "EQ50", "EQ59", "S06_4", "S06_6", "S08_2"]:
			root.flags[id] = _window(id)
			windows.erase(id)
		if _has("EQ01") and _consecutive("EQ01", target, 3):
			out.damage_bonus += 0.08
			root.flags["EQ01_bleed"] = true
		if _has("EQ02") and bool(root.flags.EQ02) and _activate("EQ02", 4.0, root, out, false):
			root.attack_modifiers.damage_bonus += 0.10
		if _has("EQ08") and bool(root.flags.EQ08) and _activate("EQ08", 4.0, root, out, false):
			root.attack_modifiers.knockback_scale *= 1.25
		if _has("EQ12") and undamaged_time >= 4.0 and clock - eq12_spent_at >= 4.0:
			out.damage_bonus += 0.08
			eq12_spent_at = clock
		if _has("EQ18") and bool(root.flags.EQ18):
			root.attack_modifiers.knockback_scale *= 1.30
		if _has("EQ59") and bool(root.flags.EQ59):
			counts.EQ59 = 0
		if _has_set("S06", 4) and bool(root.flags.S06_4) and float(ctx.get("shield", 0.0)) > 0.0 and _activate("S06_4", 3.0, root, out, false): root.attack_modifiers.damage_bonus += 0.12
	out.damage_bonus += float(root.attack_modifiers.damage_bonus)
	out.knockback_scale *= float(root.attack_modifiers.knockback_scale)
	for ready_id in ["EQ49", "EQ59"]:
		var needed_state: String = "chill" if ready_id == "EQ49" else "corrosion"
		if _has(ready_id) and bool(root.flags.get(ready_id, false)) and _state(ctx, needed_state):
			if not root.armed.has(ready_id): root.armed[ready_id] = _activate(ready_id, 4.0, root, out, false)
			if bool(root.armed[ready_id]): out.crit_bonus += 0.05 if ready_id == "EQ49" else 0.10
	if _has("EQ09") and bool(ctx.get("target_full_hp", false)) and not first_full_targets.has(target):
		out.crit_bonus += 0.08
		first_full_targets[target] = true
	if _has("EQ15") and _state(ctx, "chill"): out.crit_bonus += 0.04
	if _has("EQ34") and _state(ctx, "shock"): out.damage_bonus += 0.04
	if _has("EQ54") and _state(ctx, "shock"): out.crit_bonus += 0.03
	if _has_set("S01", 2) and _state(ctx, "burn"): out.damage_bonus += 0.08
	if _has_set("S04", 2) and _state(ctx, "corrosion"): out.damage_bonus += 0.08
	if _has_set("S06", 2) and float(ctx.get("shield", 0.0)) > 0.0: out.knockback_scale *= 1.20
	if _has_set("S07", 2) and (_state(ctx, "chill") or _state(ctx, "corrosion")): out.crit_bonus += 0.06

func _after(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	# Callers may omit before_hit only when they do not need pre-hit bonuses.
	if not bool(root.counted):
		_before(ctx, root, _empty())
	if bool(root.post_counted):
		return
	root.post_counted = true
	var target: String = str(ctx.get("target_id", ""))
	if _has("EQ01") and bool(root.flags.get("EQ01_bleed", false)) and _activate("EQ01_bleed", 0.0, root, out): _status(out, ctx, "bleed")
	if _has("EQ03") and not _state(ctx, "burn") and _activate("EQ03:" + target, 4.0, root, out): _status(out, ctx, "burn")
	if _has("EQ04") and _nth("EQ04", 3) and _activate("EQ04", 0.0, root, out): _status(out, ctx, "shock")
	if _has("EQ05") and _nth("EQ05", 3) and _activate("EQ05", 0.0, root, out): _status(out, ctx, "chill")
	if _has("EQ06") and _consecutive("EQ06", target, 3) and _activate("EQ06", 0.0, root, out):
		_status(out, ctx, "corrosion")
		_status(out, ctx, "grievous")
	if _has("EQ07") and _nth("EQ07", 4) and _activate("EQ07", 3.0, root, out): _shield(out, ctx, 0.03)
	if _has("EQ10") and bool(root.flags.get("EQ10", false)) and _activate("EQ10", 6.0, root, out): _status(out, ctx, "shock")
	if not out.statuses.is_empty():
		root.pending_context = ctx.duplicate(true)
		root.pending_stage = "weapon"
		out.resume_after_statuses = true
		return
	_after_rest(ctx, root, out)

func _after_rest(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if bool(root.get("rest_started", false)): return
	root.rest_started = true
	var target: String = str(ctx.get("target_id", ""))
	var critical: bool = bool(ctx.get("critical", false))
	var applied: Dictionary = root.applied
	if _has("EQ14") and _state(ctx, "shock") and _activate("EQ14", 6.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ19") and critical and _state(ctx, "corrosion") and _state(ctx, "chill") and _activate("EQ19", 3.0, root, out): _extend(out, ctx, "chill")
	if applied.has("shock") and _has("EQ24") and _activate("EQ24", 6.0, root, out, false): _buff("EQ24", "damage_reduction_bonus", 0.05, 2.0)
	if _has("EQ25") and _state(ctx, "chill") and _activate("EQ25", 4.0, root, out, false): _buff("EQ25", "received_knockback_scale", 0.80, 2.0)
	if applied.has("corrosion") and _has("EQ26") and _activate("EQ26", 6.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ29") and critical and _state(ctx, "chill") and _activate("EQ29", 6.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ32") and _basic(ctx) and _nth("EQ32", 5): _restore_resource(out, ctx, root)
	if _has("EQ33") and _state(ctx, "burn") and _activate("EQ33", 2.0, root, out): _extend(out, ctx, "burn")
	if _has("EQ35"):
		if _state(ctx, "chill"):
			if _consecutive("EQ35", target, 3): _bonus(out, ctx, root, "EQ35", 4.0, 0.15, 1, false)
		else: same_target.erase("EQ35")
	if _has("EQ36") and _state(ctx, "corrosion") and _activate("EQ36", 2.0, root, out): _extend(out, ctx, "corrosion")
	if _has("EQ38") and bool(root.flags.get("EQ38", false)) and _state(ctx, "chill"): _bonus(out, ctx, root, "EQ38", 5.0, 0.20, 1, false)
	if _has("EQ39") and critical and _state(ctx, "corrosion") and _activate("EQ39", 4.0, root, out, false): _buff("EQ39", "attack_speed_bonus", 0.04, 2.0)
	if applied.has("shock") and _has("EQ44"): _refund(out, ctx, root, "EQ44", 3.0, "dash", 0.10)
	if applied.has("corrosion") and _has("EQ46") and _activate("EQ46", 5.0, root, out, false): _buff("EQ46", "move_speed_bonus", 0.05, 3.0)
	if _has("EQ50") and bool(root.flags.get("EQ50", false)) and _state(ctx, "shock") and _activate("EQ50", 6.0, root, out): _status(out, ctx, "chill")
	if not out.statuses.is_empty():
		root.pending_context = ctx.duplicate(true)
		root.pending_stage = "feet"
		out.resume_after_statuses = true
		return
	_after_charm(ctx, root, out)

func _after_charm(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if bool(root.post_completed): return
	root.post_completed = true
	var target: String = str(ctx.get("target_id", ""))
	var critical: bool = bool(ctx.get("critical", false))
	var applied: Dictionary = root.applied
	if applied.has("burn") and _has("EQ53") and _activate("EQ53", 7.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ55") and critical and _state(ctx, "chill") and _activate("EQ55", 5.0, root, out): _heal(out, ctx, 0.01)
	if _has("EQ56") and _basic(ctx) and _state(ctx, "corrosion") and not resource_type.is_empty() and _activate("EQ56", 6.0, root, out, false): windows.EQ56 = clock + 3.0
	if _has("EQ58") and _state(ctx, "chill") and _activate("EQ58", 6.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ59"):
		if int(counts.get("EQ59", 0)) >= 3 and not _window("EQ59"): counts.EQ59 = 0
		counts.EQ59 = 0 if critical else mini(3, int(counts.get("EQ59", 0)) + 1)
		if int(counts.EQ59) >= 3: windows.EQ59 = clock + 3.0
	if _has("EQ60") and _window("EQ60") and _any_enemy_state(ctx.get("target_states", [])) and _activate("EQ60", 5.0, root, out, false): _buff("EQ60", "attack_speed_bonus", 0.05, 2.0)
	if applied.has("burn") and _has_set("S01", 4) and _activate("S01_4", 8.0, root, out, false): _buff("S01_4", "damage_bonus", 0.10, 3.0)
	if _has_set("S02", 2) and _state(ctx, "shock"): _refund(out, ctx, root, "S02_2", 2.0, "dash", 0.15)
	if _has_set("S02", 4) and _state(ctx, "shock"): _bonus(out, ctx, root, "S02_4", 4.0, 0.25, 2, true)
	if _has_set("S02", 6) and _state(ctx, "shock"):
		shock_targets[target] = clock
		for id in shock_targets.keys():
			if clock - float(shock_targets[id]) > 6.0: shock_targets.erase(id)
		if shock_targets.size() >= 3 and _activate("S02_6", 10.0, root, out, false):
			_buff("S02_6", "attack_speed_bonus", 0.10, 5.0)
			shock_targets.clear()
	if _has_set("S03", 4) and _state(ctx, "chill") and _activate("S03_4", 5.0, root, out): _shield(out, ctx, 0.04)
	if _has_set("S03", 6) and _state(ctx, "chill"): _bonus(out, ctx, root, "S03_6", 6.0, 0.30, 3, true, "chill")
	if applied.has("corrosion") and _has_set("S04", 4) and _activate("S04_4", 3.0, root, out): _heal(out, ctx, 0.01)
	if _has_set("S04", 6) and _state(ctx, "corrosion"): _bonus(out, ctx, root, "S04_6", 6.0, 0.35, 3, true)
	if _has_set("S06", 6) and bool(root.flags.get("S06_6", false)): _bonus(out, ctx, root, "S06_6", 8.0, 0.40, 3, false)
	if _has_set("S07", 4) and critical and (_state(ctx, "chill") or _state(ctx, "corrosion")): _refund(out, ctx, root, "S07_4", 2.0, "active", 0.25)
	if _has_set("S07", 6) and critical and (_state(ctx, "chill") or _state(ctx, "corrosion")) and _nth("S07_6", 3): _bonus(out, ctx, root, "S07_6", 5.0, 0.40, 1, false)
	if _has_set("S08", 2) and bool(root.flags.get("S08_2", false)) and _state(ctx, "shock"): _refund(out, ctx, root, "S08_2", 3.0, "dash", 0.20)
	if not applied.is_empty() and _has_set("S08", 4) and _window("S08_4") and _activate("S08_4", 6.0, root, out, false): _buff("S08_4", "move_speed_bonus", 0.12, 3.0)

func _status_applied(ctx: Dictionary, root: Dictionary, _out: Dictionary) -> void:
	# Confirmation only. Slot-ordered continuation consumes these after weapon
	# statuses have resolved, keeping a chest proc ahead of later hand/feet/charm.
	for id in ctx.get("applied_states", []):
		if id in ENEMY_STATES and not root.applied.has(id):
			root.applied[id] = true

func _enter_room(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	var id: String = str(ctx.get("room_id", ""))
	if id.is_empty() or rooms.has(id): return
	rooms[id] = true
	room_id = id
	room_low_shield_used = false
	room_first_kill_used = false
	undamaged_time = 0.0
	windows.clear()
	delayed_shield_at = -1.0
	if _has("EQ27") and bool(ctx.get("combat_room", true)) and _activate("EQ27:" + id, 0.0, root, out): _shield(out, ctx, 0.04)
	if _has("EQ42") and bool(ctx.get("unvisited", true)):
		_buff("EQ42", "move_speed_bonus", 0.08, 3.0)

func _dash(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	dash_time = clock
	for id in ["EQ02", "EQ08", "EQ10", "EQ38", "EQ40", "EQ50"]:
		windows[id] = clock + 3.0
	windows.EQ60 = clock + 3.0
	windows.S08_4 = clock + 2.0
	windows.S08_2 = clock + 2.0
	if float(ctx.get("shield", 0.0)) > 0.0:
		windows.S06_4 = clock + 2.0
	if _has("EQ20") and _activate("EQ20", 4.0, root, out, false):
		out.self_statuses.append({"status":"damage_reduction","power":0.12,"duration":2.0,"source":"EQ20"})
	if _has_set("S08", 6) and float(ctx.get("shield", 0.0)) > 0.0:
		var dash_context: Dictionary = ctx.duplicate()
		dash_context.X = float(ctx.get("H", stats.get("attack", 0.0)))
		_bonus(out, dash_context, root, "S08_6", 8.0, 0.35, 3, true, "chill")

func _damaged(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not bool(ctx.get("enemy_damage", false)): return
	if float(ctx.get("hp_damage", 0.0)) <= 0.0 and float(ctx.get("shield_absorbed", 0.0)) <= 0.0: return
	undamaged_time = 0.0
	if _has("EQ21") and not room_low_shield_used and _health_ratio(ctx) < 0.30 and _health_ratio(ctx) > 0.0 and _activate("EQ21:" + room_id, 0.0, root, out):
		room_low_shield_used = true
		_shield(out, ctx, 0.05)
		out.self_statuses.append({"status":"invulnerable","power":1.0,"duration":0.6,"source":"EQ21"})
	if _has_set("S05", 4) and float(ctx.get("shield_absorbed", 0.0)) > 0.0 and _activate("S05_4", 6.0, root, out, false): _buff("S05_4", "attack_speed_bonus", 0.10, 3.0)
	if bool(ctx.get("shield_broken", false)) and float(ctx.get("shield_absorbed", 0.0)) > 0.0:
		if _has("EQ18") and _activate("EQ18", 8.0, root, out, false): windows.EQ18 = clock + 3.0
		if _has("EQ57") and _activate("EQ57", 8.0, root, out, false): _buff("EQ57", "move_speed_bonus", 0.06, 3.0)
		if _has_set("S05", 6) and _activate("S05_6", 10.0, root, out): delayed_shield_at = clock + 1.0
		if _has_set("S06", 6): windows.S06_6 = clock + 5.0

func _kill(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	var target: String = str(ctx.get("target_id", ""))
	if target.is_empty() or deaths.has(target): return
	deaths[target] = true
	var eligible: bool = _eligible(ctx)
	var burn_tick: bool = str(ctx.get("damage_source", "")) == "burn" and int(ctx.get("proc_depth", 0)) <= 1
	if not eligible and not burn_tick: return
	if eligible and _has("EQ13") and _state(ctx, "burn"): _refund(out, ctx, root, "EQ13", 3.0, "active", 0.15)
	if eligible and _has("EQ16") and _state(ctx, "corrosion") and float(ctx.get("distance", 0.0)) <= 240.0 and _activate("EQ16", 5.0, root, out): _heal(out, ctx, 0.01)
	if _has("EQ40") and eligible and bool(root.flags.get("EQ40", false)): _refund(out, ctx, root, "EQ40", 5.0, "dash", 0.20)
	if _has("EQ43") and eligible and _state(ctx, "burn") and _activate("EQ43", 5.0, root, out, false): _buff("EQ43", "move_speed_bonus", 0.06, 3.0)
	if eligible and _has("EQ52") and not room_first_kill_used and _activate("EQ52:" + room_id, 0.0, root, out):
		room_first_kill_used = true
		_heal(out, ctx, 0.01)
	if _has_set("S01", 6) and _state(ctx, "burn"):
		var kill_context: Dictionary = ctx.duplicate()
		if burn_tick: kill_context.X = float(ctx.get("H", 0.0))
		_bonus(out, kill_context, root, "S01_6", 6.0, 0.35, 3, true)

func _any_enemy_state(states: Array) -> bool:
	for id in states:
		if id in ENEMY_STATES: return true
	return false

func _status(out: Dictionary, ctx: Dictionary, id: String) -> void:
	var base_duration: float = 4.0 if id == "corrosion" else 3.0
	var bonus: float = float(stats.get("status_duration", 0.0)) + (0.20 if id == "chill" and _has_set("S03", 2) else 0.0)
	out.statuses.append({"target_id":str(ctx.get("target_id", "")), "status":id,
		"duration":base_duration * (1.0 + minf(0.40, bonus)), "power":float(ctx.get("H", stats.get("attack", 0.0))), "source":"equipment"})

func _extend(out: Dictionary, ctx: Dictionary, id: String) -> void:
	out.status_extensions.append({"target_id":str(ctx.get("target_id", "")), "status":id, "seconds":0.30, "max_duration":(4.0 if id == "corrosion" else 3.0) * 1.40, "source":"equipment"})

func _shield(out: Dictionary, _ctx: Dictionary, ratio: float, source: String = "") -> void:
	# Source shields combine by MAXIMUM, not sum. Do not subtract an existing
	# stronger source or merge their expiry clocks; the adapter owns shield state.
	var accepted: float = clampf(ratio, 0.0, 0.35)
	if accepted <= 0.0: return
	if source.is_empty(): source = str(out.triggered.back()) if not out.triggered.is_empty() else "equipment"
	out.shields.append({"ratio":accepted, "duration":4.0, "source":source})
	out.shield_ratio = maxf(float(out.shield_ratio), accepted)

func _heal(out: Dictionary, ctx: Dictionary, ratio: float) -> void:
	_prune_history(heal_history, 1.0)
	var accepted: float = maxf(0.0, minf(ratio, minf(0.03 - _history_total(heal_history), 1.0 - _health_ratio(ctx) - float(out.heal_ratio))))
	if accepted > 0.0:
		out.heal_ratio += accepted
		heal_history.append({"time":clock, "amount":accepted})

func _restore_resource(out: Dictionary, ctx: Dictionary, root: Dictionary) -> void:
	if resource_type.is_empty() or str(ctx.get("resource_type", resource_type)) != resource_type: return
	_prune_history(resource_history, 5.0)
	var maximum: float = maxf(0.0, float(ctx.get("resource_max", stats.get("resource_max", 0.0))))
	var desired: float = float({"rage":1.0, "energy":2.0, "mana":3.0}.get(resource_type, 0.0))
	var amount: float = maxf(0.0, minf(desired, minf(maximum - float(ctx.get("resource", 0.0)), maximum * 0.20 - _history_total(resource_history))))
	if amount > 0.0 and _activate("EQ32", 3.0, root, out):
		out.resource_restore += amount
		resource_history.append({"time":clock, "amount":amount})

func _refund(out: Dictionary, ctx: Dictionary, root: Dictionary, id: String, icd: float, kind: String, desired: float) -> void:
	_prune_history(refund_history, 1.0)
	var remaining: Dictionary = ctx.get("remaining_cooldowns", {})
	var slot: String = "dash" if kind == "dash" else ""
	var longest: float = float(remaining.get("dash", 0.0)) if kind == "dash" else 0.0
	if kind == "active":
		for candidate in ACTIVE_SLOTS:
			if float(remaining.get(candidate, 0.0)) > longest:
				slot = candidate
				longest = float(remaining[candidate])
	for pending: Dictionary in out.cooldown_refunds:
		if str(pending.slot) == slot:
			longest = maxf(0.0, longest - float(pending.seconds))
	var accepted: float = maxf(0.0, minf(desired, minf(0.50 - _history_total(refund_history), longest)))
	if accepted <= 0.0 or not _activate(id, icd, root, out): return
	out.cooldown_refunds.append({"slot":slot, "seconds":accepted, "source":"equipment"})
	refund_history.append({"time":clock, "amount":accepted})

func _bonus(out: Dictionary, ctx: Dictionary, root: Dictionary, id: String, icd: float, coefficient: float, limit: int, exclude_primary: bool, state: String = "") -> void:
	var targets: Array[String] = []
	var primary: String = str(ctx.get("target_id", ""))
	if not exclude_primary and limit == 1 and (primary.is_empty() or not bool(ctx.get("target_alive", true))): return
	if not exclude_primary and not primary.is_empty() and bool(ctx.get("target_alive", true)): targets.append(primary)
	for candidate: Dictionary in ctx.get("nearby_targets", []):
		var target: String = str(candidate.get("id", ""))
		if target.is_empty() or target in targets or (exclude_primary and target == primary) or not bool(candidate.get("alive", true)) or float(candidate.get("distance", 10000.0)) > 240.0: continue
		if targets.size() >= mini(3, limit): break
		targets.append(target)
	if targets.is_empty(): return
	# The 1.2 X limit covers all targets, not just the coefficient of each packet.
	var accepted: float = minf(coefficient, maxf(0.0, 1.20 - float(root.coefficient)) / float(targets.size()))
	if accepted <= 0.0 or not _activate(id, icd, root, out): return
	root.coefficient += accepted * float(targets.size())
	var derived_states: Array = []
	if not state.is_empty():
		# Global duration applies to derived statuses; S03's primary-only bonus does
		# not. Send an explicit duration so the adapter need not guess the source.
		derived_states.append({"status":state, "duration":(4.0 if state == "corrosion" else 3.0) * (1.0 + minf(0.40, float(stats.get("status_duration", 0.0))))})
	out.bonus_hits.append({"target_ids":targets, "damage":maxf(0.0, float(ctx.get("X", ctx.get("H", 0.0)))) * accepted,
		"coefficient":accepted, "source":"equipment", "damage_source":"equipment", "proc_depth":1,
		"equipment_eligible":false, "critical":false, "states":derived_states,
		"power":float(ctx.get("H", 0.0)), "effect_id":id})

func _prune_history(history: Array[Dictionary], duration: float) -> void:
	while not history.is_empty() and float(history[0].time) <= clock - duration:
		history.pop_front()

func _history_total(history: Array[Dictionary]) -> float:
	var value: float = 0.0
	for item in history: value += float(item.amount)
	return value
