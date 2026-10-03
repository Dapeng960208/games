class_name EquipmentEffects
extends RefCounted
const Numerical = preload("res://scripts/infrastructure/content/runtime_rules.gd")
## Deterministic equipment event reducer; never reads/mutates Game or scene nodes.
## configure accepts legacy slot -> EQ IDs or v2 slot -> instance IDs plus
## StatResolver equipment_templates. Only template identities select fixed traits.
## Time advances ONLY through advance(delta, context), so menus/pause freeze ICDs.
## before_hit reads PRE-HIT target_states, returning damage/crit/knockback bonuses.
## after_hit follows a confirmed hit. status_applied RECORDS successful application
## (not a request, not immunity). When resume_after_statuses is true, the caller
## must confirm accepted statuses, then send statuses_resolved even if all failed;
## this resumes remaining slots in order. Continuations can request feet statuses
## once more before completing charm/set effects. Native status confirmations
## arrive before after_hit. kill follows confirmed death, once per target.
## V2 adapters settle_status_requests before status_applied/continuation so only
## accepted standalone equipment-status bundles commit their packet and ICD.
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
## V2 S11 counts successful original paid casts at commit, with a stable cast root
## and actual paid_cost. Hit/deployment callbacks cannot contribute to this count.

const B10 = preload("res://scripts/levels/b10/combat/equipment_effects.gd")
const B06 = preload("res://scripts/levels/b06/combat/equipment_effects.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const ENEMY_STATES: Array[String] = ["burn", "shock", "chill", "corrosion", "bleed", "grievous"]
const ACTIVE_SLOTS: Array[String] = ["Q", "right", "F", "R"]
var clock: float = 0.0
var equipped: Dictionary = {}
var instance_loadout: Dictionary = {}
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

static func implemented_ids(ruleset: int = 1) -> Array[String]:
	var result: Array[String] = []
	for index in range(1, 97):
		result.append("EQ%02d" % index)
	# New templates have no inherited old fixed affixes.
	if ruleset == 2:
		for id: String in ["B05-U01", "B05-U02", "B05-U03", "B06-U01", "B06-U02", "B06-U03", "B10-U01", "B10-U02", "B10-U03"]: result.append(id)
	return result

static func implemented_set_ids(ruleset: int = 1) -> Array[String]:
	var result: Array[String] = ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10", "S11", "S12", "S13", "S14"]
	if ruleset == 2: result.append_array(["B05-SW", "B05-SG", "B05-SM", "B05-SU", "B06-SW", "B06-SG", "B06-SM", "B06-SU", "B10-SW", "B10-SG", "B10-SM", "B10-SU"])
	return result

func configure(loadout: Dictionary, resolved_stats: Dictionary, type: String) -> void:
	stats = resolved_stats.duplicate(true)
	resource_type = type if type in ["rage", "energy", "mana"] else ""
	var binding: Dictionary = loadout_binding(loadout, resolved_stats)
	instance_loadout = binding.get("instance_loadout", {}).duplicate(true)
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
	var next: Dictionary = loadout_binding(loadout, resolved_stats)
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
	instance_loadout = next.get("instance_loadout", {}).duplicate(true)
	equipped = next.equipped
	set_counts = next.set_counts
	stats = resolved_stats.duplicate(true)
	resource_type = type if type in ["rage", "energy", "mana"] else ""

## V2 bindings consume a validated resolver snapshot, never an unowned template
## guessed from an instance ID. Identity stays in instance_loadout while fixed
## trait sources keep their stable template IDs and cooldown identities.
static func loadout_binding(loadout: Dictionary, resolved_stats: Dictionary = {}) -> Dictionary:
	var items: Dictionary = {}
	var sets: Dictionary = {}
	var ruleset: int = int(resolved_stats.get("ruleset_version", Numerical.LEGACY))
	var templates: Dictionary = loadout
	var instances: Dictionary = {}
	if ruleset == Numerical.V2:
		var bound: Variant = resolved_stats.get("loadout")
		var mapped: Variant = resolved_stats.get("equipment_templates")
		if not bound is Dictionary or not mapped is Dictionary:
			return {"equipped":items, "set_counts":sets, "instance_loadout":instances}
		for slot: Variant in loadout:
			if not slot is String or slot not in Registry.slots(ruleset) or not loadout[slot] is String:
				return {"equipped":{}, "set_counts":{}, "instance_loadout":{}}
			if not str(loadout[slot]).is_empty(): instances[slot] = loadout[slot]
		if instances != bound or mapped.size() != instances.size():
			return {"equipped":{}, "set_counts":{}, "instance_loadout":{}}
		templates = mapped
	for slot: String in Registry.slots(ruleset):
		var id: String = str(templates.get(slot, ""))
		var item: Dictionary = Registry.equipment(id, ruleset)
		if item.is_empty() or str(item.get("slot", "")) != slot or items.has(id):
			if ruleset == Numerical.V2 and instances.has(slot):
				return {"equipped":{}, "set_counts":{}, "instance_loadout":{}}
			continue
		items[id] = true
		var set_id: String = str(item.get("set_id", ""))
		if not set_id.is_empty():
			sets[set_id] = int(sets.get(set_id, 0)) + 1
	var result: Dictionary = {"equipped":items, "set_counts":sets}
	if ruleset == Numerical.V2: result["instance_loadout"] = instances.duplicate(true)
	return result

## IDs may carry a room/target suffix. Set sources require their exact tier,
## so retaining two pieces never keeps a former four/six-piece benefit.
static func source_active(source: String, binding: Dictionary) -> bool:
	var id: String = source.trim_prefix("equipment:").trim_prefix("set_").get_slice(":", 0)
	if id in ["B05-combat", "B06-combat", "B10-combat"]:
		for template_id: String in binding.get("equipped", {}):
			if template_id.begins_with(id.trim_suffix("combat")): return true
		return false
	if id.begins_with("EQ") or id in ["B05-U01", "B05-U02", "B05-U03", "B06-U01", "B06-U02", "B06-U03", "B10-U01", "B10-U02", "B10-U03"]:
		return bool(binding.get("equipped", {}).get(id, false))
	var pieces: PackedStringArray = id.split("_")
	return pieces.size() == 2 and pieces[0] in implemented_set_ids(2) and pieces[1] in ["2", "4", "6"] and int(binding.get("set_counts", {}).get(pieces[0], 0)) >= int(pieces[1])

static func _prune_loadout_sources(values: Dictionary, previous: Dictionary, next: Dictionary) -> void:
	for id: String in values.keys():
		if not source_active(id, previous) or not source_active(id, next):
			values.erase(id)

## Pure save-state migration. Never clear cooldowns, consumed room flags or
## rate-limit histories: taking an item off and on cannot replenish rewards.
static func for_loadout(state: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, old_stats: Dictionary = {}, new_stats: Dictionary = {}) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	var previous: Dictionary = loadout_binding(old_loadout, old_stats)
	var next: Dictionary = loadout_binding(new_loadout, new_stats)
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
		"received_displacement_reduction":0.0, "terrain_slow_reduction":0.0, "received_healing_bonus":0.0, "immediate_w_radius_scale":1.0,
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

func _paid_spell_cast(ctx: Dictionary) -> bool:
	var paid_cost := float(ctx.get("paid_cost", 0.0))
	var original := _eligible(ctx) and not _basic(ctx) and str(ctx.get("damage_source", "")) == "skill"
	var active_slot := str(ctx.get("slot", "")) in ["q", "secondary", "f", "ultimate"]
	return original and active_slot and bool(ctx.get("cast_success", false)) and is_finite(paid_cost) and paid_cost > 0.0

func _health_ratio(ctx: Dictionary) -> float:
	return float(ctx.get("hp", 0.0)) / maxf(1.0, float(ctx.get("max_hp", stats.get("max_hp", 1.0))))

func _modifiers(ctx: Dictionary, out: Dictionary) -> void:
	B06.modifiers(self, ctx, out)
	B10.modifiers(self, ctx, out)
	var shielded: bool = float(ctx.get("shield", 0.0)) > 0.0
	for id: String in equipped:
		var passive: Dictionary = Registry.equipment(id, int(stats.get("ruleset_version", Numerical.LEGACY))).get("combat_passive", {})
		if not passive.is_empty() and _shop_condition(str(passive.condition),ctx):
			out[str(passive.stat)] += float(passive.amount)
	for set_id: String in set_counts:
		if int(set_counts[set_id]) < 2: continue
		var passive: Dictionary = Registry.sets(int(stats.get("ruleset_version", Numerical.LEGACY))).get(set_id,{}).get("shop_passive", {})
		if not passive.is_empty() and _shop_condition(str(passive.condition),ctx):
			out[str(passive.stat)] += float(passive.amount)
	if _has_set("S09",6) and shielded: out.damage_bonus += 0.08
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

func _shop_condition(condition: String, ctx: Dictionary) -> bool:
	match condition:
		"shielded": return float(ctx.get("shield",0.0)) > 0.0
		"moving": return bool(ctx.get("moving",false))
		"resource_half": return float(ctx.get("resource_max",stats.get("resource_max",0.0))) > 0.0 and float(ctx.get("resource",0.0)) >= float(ctx.get("resource_max",stats.get("resource_max",0.0))) * 0.5
		"full_hp": return _health_ratio(ctx) >= 1.0
		"injured": return _health_ratio(ctx) > 0.0 and _health_ratio(ctx) < 1.0
		"low_hp": return _health_ratio(ctx) > 0.0 and _health_ratio(ctx) <= 0.5
	return false

func _cap_modifiers(out: Dictionary) -> Dictionary:
	var limits: Dictionary = Numerical.value("caps") if Numerical.is_v2(stats) else {}
	out.damage_bonus = clampf(out.damage_bonus, 0.0, maxf(0.0, float(limits.get("damage_bonus", 0.60)) - float(stats.get("damage_bonus", 0.0))))
	out.crit_bonus = clampf(out.crit_bonus, 0.0, maxf(0.0, (1.0 if preload("res://scripts/domain/combat/crit_policy.gd").enabled(stats) else 0.75) - float(stats.get("crit_chance", 0.0))))
	out.attack_speed_bonus = clampf(out.attack_speed_bonus, 0.0, maxf(0.0, float(limits.get("attack_speed", 0.60)) - float(stats.get("attack_speed_bonus", 0.0))))
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
	B06.advance(self, delta, ctx, out)
	B10.advance(self, delta, ctx, out)
	_b05_advance(ctx, out)
	_modifiers(ctx, out)
	return _cap_modifiers(out)

func handle(event: String, ctx: Dictionary) -> Dictionary:
	if event == "before_hit" and Numerical.is_v2(stats):
		return preview_hit(ctx)
	return _handle(event, ctx)

## Blocked / immune / rounded-zero contacts cannot spend a proc window or a
## hit counter. Preview precisely the same reducer against isolated state; the
## first confirmed after_hit commits _before through _after below.
func preview_hit(ctx: Dictionary) -> Dictionary:
	var previous: Dictionary = {"roots":roots, "cooldowns":cooldowns, "windows":windows,
		"counts":counts, "same_target":same_target, "first_full_targets":first_full_targets,
		"eq12_spent_at":eq12_spent_at}
	roots = roots.duplicate()
	var root_id: String = str(ctx.get("root_event_id", ctx.get("attack_id", ctx.get("event_id", ""))))
	if roots.has(root_id): roots[root_id] = roots[root_id].duplicate(true)
	cooldowns = cooldowns.duplicate(true)
	windows = windows.duplicate(true)
	counts = counts.duplicate(true)
	same_target = same_target.duplicate(true)
	first_full_targets = first_full_targets.duplicate(true)
	var out: Dictionary = _handle("before_hit", ctx)
	roots = previous.roots
	cooldowns = previous.cooldowns
	windows = previous.windows
	counts = previous.counts
	same_target = previous.same_target
	first_full_targets = previous.first_full_targets
	eq12_spent_at = float(previous.eq12_spent_at)
	return out

func _handle(event: String, ctx: Dictionary) -> Dictionary:
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
		"class_shield_gain":
			if Numerical.is_v2(stats) and _has_set("S06", 4) and bool(ctx.get("accepted_refresh", false)) and not bool(ctx.get("equipment", false)) and str(ctx.get("source", "")) in ["hero_passive:three_rivets", "hero_f"] and _activate("S06_4", 6.0, root, out, false):
				_buff("S06_4", "damage_bonus", 0.20, 4.0)
		"skill_cast":
			if float(ctx.get("base_cost", 0.0)) > 0.0 and bool(ctx.get("cast_success", true)) and str(ctx.get("resource_type", resource_type)) == resource_type:
				windows.erase("EQ56")
				if _has_set("S11",4) and _activate("S11_4",6.0,root,out,false): _buff("S11_4","damage_bonus",0.08,3.0)
				if Numerical.is_v2(stats) and _has_set("S11",6) and _paid_spell_cast(ctx) and not bool(root.get("paid_cast_counted", false)):
					root["paid_cast_counted"] = true
					# A new counter never imports partial progress from the old basic-hit rule.
					if _nth("S11_6:paid_cast",4): _refund(out,ctx,root,"S11_6",5.0,"active",0.35)
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
	_b05_event(event, ctx, root, out)
	B06.event(self, event, ctx, root, out)
	B10.event(self, event, ctx, root, out)
	_modifiers(ctx, out)
	return _cap_modifiers(out)

func skill_cost(base_cost: float, ctx: Dictionary = {}) -> float:
	if base_cost <= 0.0:
		return 0.0
	var reduction: float = 0.08 if _window("EQ56") and str(ctx.get("resource_type", resource_type)) == resource_type else 0.0
	if Numerical.is_v2(stats) and _has_set("B10-SU", 4) and _window("B10-SU_4:discount"): reduction += 0.08
	var ruleset := int(stats.get("ruleset_version", Numerical.LEGACY))
	return Numerical.amount(maxf(Numerical.scale(1.0, ruleset), base_cost * (1.0 - minf(0.20, reduction))), ruleset)

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
	return {"packets":int(root.packets), "coefficient":float(root.coefficient), "damage_spent":int(root.get("damage_spent", 0))}

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

## Standalone status commands provisionally occupy one shared packet while the
## adapter asks the receiver. Rejected writes never start their emitter's ICD.
func _activate_status(id: String, icd: float, root: Dictionary, out: Dictionary) -> bool:
	if not Numerical.is_v2(stats): return _activate(id, icd, root, out)
	if not _ready(id) or int(root.packets) >= 4: return false
	if not root.has("pending_status_effects"): root["pending_status_effects"] = {}
	if root.pending_status_effects.has(id): return false
	root.pending_status_effects[id] = {"icd":icd}
	root.packets += 1
	return true

## Multiple statuses emitted by one effect (EQ06) share one reservation. One
## accepted write commits it; all rejected releases it before later slots run.
func settle_status_requests(ctx: Dictionary, commands: Array, accepted_effects: Array[String]) -> Array[String]:
	var committed: Array[String] = []
	if not Numerical.is_v2(stats): return committed
	var root_id: String = str(ctx.get("root_event_id", ctx.get("attack_id", ctx.get("event_id", ""))))
	var root: Dictionary = roots.get(root_id, {})
	var pending: Dictionary = root.get("pending_status_effects", {})
	for command: Dictionary in commands:
		var id: String = str(command.get("effect_id", ""))
		if not pending.has(id): continue
		var request: Dictionary = pending[id]
		pending.erase(id)
		if id in accepted_effects:
			cooldowns[id] = clock + float(request.icd)
			committed.append(id)
		else:
			root.packets = maxi(0, int(root.packets) - 1)
	return committed

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
		if not Numerical.is_v2(stats) and _has_set("S06", 4) and bool(root.flags.S06_4) and float(ctx.get("shield", 0.0)) > 0.0 and _activate("S06_4", 3.0, root, out, false): root.attack_modifiers.damage_bonus += 0.12
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
	if Numerical.is_v2(stats) or not bool(root.counted):
		_before(ctx, root, _empty())
	if bool(root.post_counted):
		return
	root.post_counted = true
	var target: String = str(ctx.get("target_id", ""))
	if _has("EQ01") and bool(root.flags.get("EQ01_bleed", false)) and _activate_status("EQ01_bleed", 0.0, root, out): _status(out, ctx, "bleed", "EQ01_bleed")
	if _has("EQ03") and not _state(ctx, "burn") and _activate_status("EQ03:" + target, 4.0, root, out): _status(out, ctx, "burn", "EQ03:" + target)
	if _has("EQ04") and _nth("EQ04", 3) and _activate_status("EQ04", 0.0, root, out): _status(out, ctx, "shock", "EQ04")
	if _has("EQ05") and _nth("EQ05", 3) and _activate_status("EQ05", 0.0, root, out): _status(out, ctx, "chill", "EQ05")
	if _has("EQ06") and _consecutive("EQ06", target, 3) and _activate_status("EQ06", 0.0, root, out):
		_status(out, ctx, "corrosion", "EQ06")
		_status(out, ctx, "grievous", "EQ06")
	if _has("EQ07") and _nth("EQ07", 4) and _activate("EQ07", 3.0, root, out): _shield(out, ctx, 0.03)
	if _has("EQ10") and bool(root.flags.get("EQ10", false)) and _activate_status("EQ10", 6.0, root, out): _status(out, ctx, "shock", "EQ10")
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
	var eq38_condition: bool = float(ctx.get("shield", 0.0)) > 0.0 if Numerical.is_v2(stats) else _state(ctx, "chill")
	if _has("EQ38") and bool(root.flags.get("EQ38", false)) and eq38_condition: _bonus(out, ctx, root, "EQ38", 5.0, 0.20, 1, false)
	if _has("EQ39") and critical and _state(ctx, "corrosion") and _activate("EQ39", 4.0, root, out, false): _buff("EQ39", "attack_speed_bonus", 0.04, 2.0)
	if applied.has("shock") and _has("EQ44"): _refund(out, ctx, root, "EQ44", 3.0, "dash", 0.10)
	if applied.has("corrosion") and _has("EQ46") and _activate("EQ46", 5.0, root, out, false): _buff("EQ46", "move_speed_bonus", 0.05, 3.0)
	if _has("EQ50") and bool(root.flags.get("EQ50", false)) and _state(ctx, "shock") and _activate_status("EQ50", 6.0, root, out): _status(out, ctx, "chill", "EQ50")
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
	if not Numerical.is_v2(stats) and _has_set("S11",6) and _basic(ctx) and _nth("S11_6",4): _refund(out,ctx,root,"S11_6",5.0,"active",0.35)
	if _has_set("S12",4) and critical and _activate("S12_4",6.0,root,out,false): _buff("S12_4","attack_speed_bonus",0.08,3.0)
	if _has_set("S12",6) and critical: _bonus(out,ctx,root,"S12_6",5.0,0.30,1,false)
	if _has_set("S14",6) and _shop_condition("low_hp",ctx): _bonus(out,ctx,root,"S14_6",6.0,0.25,3,false)
	if applied.has("burn") and _has("EQ53") and _activate("EQ53", 7.0, root, out): _shield(out, ctx, 0.02)
	if _has("EQ55") and critical and _state(ctx, "chill") and _activate("EQ55", 5.0, root, out): _heal(out, ctx, 0.01)
	if _has("EQ56") and _basic(ctx) and _state(ctx, "corrosion") and not resource_type.is_empty() and _activate("EQ56", 6.0, root, out, false): windows.EQ56 = clock + 3.0
	var eq58_condition: bool = float(ctx.get("shield", 0.0)) > 0.0 if Numerical.is_v2(stats) else _state(ctx, "chill")
	if _has("EQ58") and eq58_condition and _activate("EQ58", 6.0, root, out): _shield(out, ctx, 0.02)
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
	if _has_set("S06", 6):
		if Numerical.is_v2(stats):
			if bool(ctx.get("full_break_w", false)) and bool(ctx.get("shielded_cast", false)):
				_bonus(out, ctx, root, "S06_6", 4.0, 0.60, 3, false, "", float(ctx.get("H_skill", ctx.get("H", 0.0))), "physical")
		elif bool(root.flags.get("S06_6", false)):
			_bonus(out, ctx, root, "S06_6", 8.0, 0.40, 3, false)
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
	if id != room_id:
		clear_b05_temporary()
		clear_b06_temporary()
		clear_b10_temporary()
	if id.is_empty(): return
	# Reused fixed-room blueprints still become the current room. Retain their
	# consumed one-time flags instead of replaying entry rewards.
	room_id = id
	if rooms.has(id): return
	rooms[id] = true
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
	if _has_set("S10",4) and _activate("S10_4",6.0,root,out,false): _buff("S10_4","move_speed_bonus",0.10,3.0)
	if _has_set("S10",6) and _activate("S10_6",8.0,root,out): _shield(out,ctx,0.04,"S10_6")
	for id in ["EQ02", "EQ08", "EQ10", "EQ38", "EQ40", "EQ50"]:
		windows[id] = clock + 3.0
	windows.EQ60 = clock + 3.0
	windows.S08_4 = clock + 2.0
	windows.S08_2 = clock + 2.0
	if not Numerical.is_v2(stats) and float(ctx.get("shield", 0.0)) > 0.0:
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
	if _has_set("S09",4) and _activate("S09_4",8.0,root,out): _shield(out,ctx,0.05,"S09_4")
	if _has_set("S14",4) and _shop_condition("low_hp",ctx) and _activate("S14_4",8.0,root,out,false): _buff("S14_4","attack_speed_bonus",0.10,3.0)
	if _has("EQ21") and not room_low_shield_used and _health_ratio(ctx) < 0.30 and _health_ratio(ctx) > 0.0 and _activate("EQ21:" + room_id, 0.0, root, out):
		room_low_shield_used = true
		_shield(out, ctx, 0.05)
		out.self_statuses.append({"status":"invulnerable","power":1.0,"duration":0.6,"source":"EQ21"})
	if _has_set("S05", 4) and float(ctx.get("shield_absorbed", 0.0)) > 0.0 and _activate("S05_4", 6.0, root, out, false): _buff("S05_4", "attack_speed_bonus", 0.10, 3.0)
	if bool(ctx.get("shield_broken", false)) and float(ctx.get("shield_absorbed", 0.0)) > 0.0:
		if _has("EQ18") and _activate("EQ18", 8.0, root, out, false): windows.EQ18 = clock + 3.0
		if _has("EQ57") and _activate("EQ57", 8.0, root, out, false): _buff("EQ57", "move_speed_bonus", 0.06, 3.0)
		if _has_set("S05", 6) and _activate("S05_6", 10.0, root, out): delayed_shield_at = clock + 1.0
		if not Numerical.is_v2(stats) and _has_set("S06", 6): windows.S06_6 = clock + 5.0

func _kill(ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	var target: String = str(ctx.get("target_id", ""))
	if target.is_empty() or deaths.has(target): return
	deaths[target] = true
	var eligible: bool = _eligible(ctx)
	var burn_tick: bool = str(ctx.get("damage_source", "")) == "burn" and int(ctx.get("proc_depth", 0)) <= 1
	if not eligible and not burn_tick: return
	if eligible and _has_set("S13",4) and _activate("S13_4",5.0,root,out): _heal(out,ctx,0.02)
	if eligible and _has_set("S13",6) and _activate("S13_6",8.0,root,out): _shield(out,ctx,0.05,"S13_6")
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

func _status(out: Dictionary, ctx: Dictionary, id: String, effect_id: String = "") -> void:
	var base_duration: float = 4.0 if id == "corrosion" else 3.0
	var bonus: float = float(stats.get("status_duration", 0.0)) + (0.20 if id == "chill" and _has_set("S03", 2) else 0.0)
	out.statuses.append({"target_id":str(ctx.get("target_id", "")), "status":id,
		"duration":base_duration * (1.0 + minf(0.40, bonus)), "power":float(ctx.get("H", stats.get("attack", 0.0))), "source":"equipment"})
	if Numerical.is_v2(stats): out.statuses.back()["effect_id"] = effect_id

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
	if Numerical.is_v2(stats):
		var maximum := Numerical.integer(float(ctx.get("max_hp", stats.get("max_hp", 0))))
		var pending := int(out.get("heal_amount", 0))
		var missing := maxi(0, maximum - Numerical.integer(float(ctx.get("hp", maximum))) - pending)
		var budget := maxi(0, Numerical.integer(maximum * 0.03) - int(_history_total(heal_history)))
		var accepted_units := mini(Numerical.integer(maximum * ratio), mini(missing, budget))
		if accepted_units > 0:
			out["heal_amount"] = pending + accepted_units
			heal_history.append({"time":clock, "amount":accepted_units})
		return
	var accepted: float = maxf(0.0, minf(ratio, minf(0.03 - _history_total(heal_history), 1.0 - _health_ratio(ctx) - float(out.heal_ratio))))
	if accepted > 0.0:
		out.heal_ratio += accepted
		heal_history.append({"time":clock, "amount":accepted})

func _restore_resource(out: Dictionary, ctx: Dictionary, root: Dictionary) -> void:
	if resource_type.is_empty() or str(ctx.get("resource_type", resource_type)) != resource_type: return
	_prune_history(resource_history, 5.0)
	var maximum: float = maxf(0.0, float(ctx.get("resource_max", stats.get("resource_max", 0.0))))
	var desired: float = Numerical.scale(float({"rage":1.0, "energy":2.0, "mana":3.0}.get(resource_type, 0.0)), int(stats.get("ruleset_version", Numerical.LEGACY)))
	var budget: float = maximum * 0.20
	if Numerical.is_v2(stats):
		desired = Numerical.integer(desired * (1.0 + clampf(float(stats.get("resource_gain_bonus", 0.0)), 0.0, 0.30)))
		budget = Numerical.integer(budget)
	var amount: float = maxf(0.0, minf(desired, minf(maximum - float(ctx.get("resource", 0.0)), budget - _history_total(resource_history))))
	if Numerical.is_v2(stats): amount = floor(amount)
	if amount > 0.0 and _activate("EQ32", 3.0, root, out):
		out.resource_restore += amount
		if Numerical.is_v2(stats): out.resource_restore = Numerical.integer(float(out.resource_restore))
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

func _bonus(out: Dictionary, ctx: Dictionary, root: Dictionary, id: String, icd: float, coefficient: float, limit: int, exclude_primary: bool, state: String = "", damage_base: float = -1.0, damage_type: String = "") -> void:
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
	var basis: float = maxf(0.0, float(ctx.get("X", ctx.get("H", 0.0)))) if damage_base < 0.0 else maxf(0.0, damage_base)
	var accepted: float = coefficient
	var amounts: Dictionary = {}
	if Numerical.is_v2(stats):
		if not root.has("raw_packet"):
			root["raw_packet"] = Numerical.integer(float(ctx.get("X", ctx.get("H", 0.0))))
			root["damage_spent"] = int(floor(float(root.raw_packet) * float(root.coefficient)))
		var remaining: int = maxi(0, int(Numerical.derived_budget(float(root.raw_packet), Numerical.V2)) - int(root.damage_spent))
		var requested: int = Numerical.integer(basis * coefficient)
		var spent: int = 0
		# Preserve target order: round each full requested packet, then clip to
		# the shared remaining integer amount. Never spread a fractional ratio.
		for target in targets:
			var packet: int = mini(remaining, requested)
			if packet <= 0: break
			amounts[target] = packet
			remaining -= packet
			spent += packet
		if spent <= 0 or not _activate(id, icd, root, out): return
		root.damage_spent += spent
		root.coefficient = float(root.damage_spent) / maxf(1.0, float(root.raw_packet))
		targets.assign(amounts.keys())
	else:
		# Legacy budgets divided the available coefficient across every target.
		accepted = minf(coefficient, maxf(0.0, 1.20 - float(root.coefficient)) / float(targets.size()))
		if accepted <= 0.0 or not _activate(id, icd, root, out): return
		root.coefficient += accepted * float(targets.size())
	var derived_states: Array = []
	if not state.is_empty():
		# Global duration applies to derived statuses; S03's primary-only bonus does
		# not. Send an explicit duration so the adapter need not guess the source.
		derived_states.append({"status":state, "duration":(4.0 if state == "corrosion" else 3.0) * (1.0 + minf(0.40, float(stats.get("status_duration", 0.0))))})
	var command: Dictionary = {"target_ids":targets, "damage_by_target":amounts, "damage":Numerical.amount(basis * accepted, int(stats.get("ruleset_version", Numerical.LEGACY))),
		"coefficient":accepted, "source":"equipment", "damage_source":"equipment", "proc_depth":1,
		"equipment_eligible":false, "critical":false, "states":derived_states,
		"power":float(ctx.get("H", 0.0)), "effect_id":id}
	if not damage_type.is_empty(): command["damage_type"] = damage_type
	out.bonus_hits.append(command)

func _prune_history(history: Array[Dictionary], duration: float) -> void:
	while not history.is_empty() and float(history[0].time) <= clock - duration:
		history.pop_front()

func _history_total(history: Array[Dictionary]) -> float:
	var value: float = 0.0
	for item in history: value += float(item.amount)
	return value


## B05 extends the released reducer without changing historical item effects.
## All counters use confirmed original events; stable cast roots suppress AoE ticks.
func b05_control_duration(duration: float, other_reduction: float = 0.0) -> float:
	var reduction := clampf(other_reduction + (0.20 if _has_set("B05-SU", 2) else 0.0), 0.0, 0.50)
	return maxf(0.0, duration) * (1.0 - reduction)

func b05_e_shield(amount: float) -> float:
	return amount * (1.12 if Numerical.is_v2(stats) and _has_set("B05-SW", 2) else 1.0)

func clear_b05_temporary() -> void:
	for values: Dictionary in [windows, counts, buffs]:
		for key: String in values.keys():
			if key.begins_with("B05-"): values.erase(key)
	# Global ICDs deliberately survive combat end, room transitions and swapping.

func _b05_advance(ctx: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(stats): return
	if windows.has("B05-combat") and not _window("B05-combat"):
		clear_b05_temporary()
	for key: String in windows.keys():
		if not key.begins_with("B05-SU_4:exit:") or clock < float(windows[key]): continue
		windows.erase(key)
		if _has_set("B05-SU", 4):
			var root := _root("b05_exit:" + key + ":" + str(clock))
			if _activate("B05-SU_4", 12.0, root, out): _shield(out, ctx, 0.06, "B05-SU_4")

func _b05_event(event: String, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(stats): return
	var slot := str(ctx.get("skill_slot", ctx.get("slot", "")))
	var original := _eligible(ctx)
	if event == "skill_cast" and _paid_spell_cast(ctx) and bool(ctx.get("combat_active", false)):
		windows["B05-combat"] = clock + 10.0
	if event == "before_hit" and original:
		if _has_set("B05-SG", 2) and bool(ctx.get("hunter_marked", false)): out.damage_bonus += 0.08
		if _has_set("B05-SM", 2) and slot == "q": out.damage_bonus += 0.08
		if _has_set("B05-SW", 6) and slot == "q":
			if not root.flags.has("B05-SW_6:q"):
				root.flags["B05-SW_6:q"] = _window("B05-SW_6:q")
				windows.erase("B05-SW_6:q")
			if bool(root.flags.get("B05-SW_6:q", false)): out.damage_bonus += 0.10
		if _has_set("B05-SG", 6) and slot == "secondary" and (str(root.first_target).is_empty() or str(root.first_target) == str(ctx.get("target_id", ""))):
			if not root.flags.has("B05-SG_6:w"):
				root.flags["B05-SG_6:w"] = _window("B05-SG_6:w")
				windows.erase("B05-SG_6:w")
			if bool(root.flags.get("B05-SG_6:w", false)): out.damage_bonus += 0.12
	elif event == "after_hit" and original and bool(ctx.get("confirmed", false)):
		# before_hit previews may have consumed a conditional window in their copy.
		# Commit B05 hit modifiers only after actual health/shield loss, like V2.
		_b05_event("before_hit", ctx, root, _empty())
		windows["B05-combat"] = clock + 10.0
		if _has_set("B05-SG", 4) and slot == "secondary" and bool(ctx.get("hunter_marked", false)) and not bool(root.get("b05_pierced", false)):
			var prior: int = out.bonus_hits.size()
			_b05_packet(ctx, root, out, "B05-SG_4", 0.0, 0.35, ctx.get("b05_pierce_targets", []), 1, "physical")
			if out.bonus_hits.size() > prior: root["b05_pierced"] = true
		if bool(root.get("b05_hit_counted", false)): return
		root["b05_hit_counted"] = true
		if _has_set("B05-SW", 4) and slot == "secondary" and _window("B05-SW_4:absorbed") and _ready("B05-SW_4"):
			windows.erase("B05-SW_4:absorbed")
			_b05_packet(ctx, root, out, "B05-SW_4", 6.0, 0.30, ctx.get("b05_arc_targets", []), 3, "physical")
		if _has_set("B05-SW", 6) and slot == "secondary" and _ready("B05-SW_6"):
			if _b05_sequence("B05-SW_6", 8.0, 0, 0, false):
				if _activate("B05-SW_6", 8.0, root, out, false):
					out.cooldown_refunds.append({"slot":"F", "seconds":minf(1.5, maxf(0.0, float(ctx.get("remaining_cooldowns", {}).get("F", 0.0)))), "source":"equipment"})
					windows["B05-SW_6:q"] = clock + 6.0
		if _has_set("B05-SU", 6) and (_basic(ctx) or float(ctx.get("paid_cost", 0.0)) > 0.0) and _ready("B05-SU_6") and _nth("B05-SU_6", 3):
			if _activate("B05-SU_6", 12.0, root, out):
				_heal(out, ctx, 0.03)
				_buff("B05-SU_6", "move_speed_bonus", 0.08, 3.0)
	elif event == "damaged":
		if float(ctx.get("hp_damage", 0.0)) + float(ctx.get("shield_absorbed", 0.0)) > 0.0: windows["B05-combat"] = clock + 10.0
		if _has_set("B05-SW", 4) and float(ctx.get("e_shield_absorbed", 0.0)) > 0.0:
			windows["B05-SW_4:absorbed"] = clock + 300.0
	elif event == "skill_cast" and _has_set("B05-SM", 4) and _paid_spell_cast(ctx) and bool(ctx.get("combat_active", false)) and _ready("B05-SM_4"):
		if bool(root.get("b05_paid_counted", false)): return
		root["b05_paid_counted"] = true
		var skill_index := ["q", "secondary", "f", "ultimate"].find(slot) + 1
		if _b05_sequence("B05-SM_4", 6.0, skill_index, int(ctx.paid_cost), true) and _activate("B05-SM_4", 6.0, root, out, false):
			out.resource_restore += minf(60.0, maxf(0.0, float(ctx.get("resource_max", 0.0)) - float(ctx.get("resource", 0.0))))
	elif event == "gunner_q_completed" and _has_set("B05-SG", 6) and float(ctx.get("actual_distance", 0.0)) >= 100.0 and bool(ctx.get("combat_active", false)):
		if _activate("B05-SG_6", 6.0, root, out, false): windows["B05-SG_6:w"] = clock + 6.0
	elif event == "mage_w_node_placed" and _has_set("B05-SM", 6) and bool(ctx.get("node_placed", false)) and bool(ctx.get("combat_active", false)):
		if _activate("B05-SM_6", 8.0, root, out, false):
			var fixed_power := float(ctx.get("attacker_stats", stats).get("ability_power", 0.0))
			_prime_b05_budget(ctx, root, fixed_power)
			out["b05_bloom"] = {"delay":1.0, "radius":110.0, "damage":Numerical.integer(fixed_power * 0.40), "root_event_id":str(ctx.get("root_event_id", ""))}
	elif event == "b05_bloom_due" and _has_set("B05-SM", 6):
		_b05_packet(ctx, root, out, "B05-SM_6:ring", 0.0, 0.40, ctx.get("b05_bloom_targets", []), 3, "magic", float(ctx.get("bloom_damage", 0.0)), false)
	elif event == "hostile_hazard":
		var hazard := str(ctx.get("hazard_id", ""))
		if hazard.is_empty(): return
		var inside := "B05-SU_4:inside:" + hazard
		var exited := "B05-SU_4:exit:" + hazard
		if bool(ctx.get("inside", false)):
			counts[inside] = 1
			windows.erase(exited)
		elif counts.has(inside):
			counts.erase(inside)
			if _has_set("B05-SU", 4): windows[exited] = clock + 1.0
		if bool(ctx.get("zone_damaged", false)) and windows.has(exited): windows[exited] = clock + 1.0
	elif event == "root_ended" and _has("B05-U01") and bool(ctx.get("actually_rooted", false)):
		if _activate("B05-U01", 10.0, root, out, false): _buff("B05-U01", "move_speed_bonus", 0.10, 2.0)
	elif event == "external_heal" and _has("B05-U02") and float(ctx.get("actual_healing", 0.0)) > 0.0:
		if _activate("B05-U02", 12.0, root, out):
			_shield(out, ctx, 0.02, "B05-U02")
			out.shields.back().duration = 3.0
	elif event == "hostile_destructible_destroyed" and _has("B05-U03") and bool(ctx.get("player_attributed", false)):
		if _activate("B05-U03", 12.0, root, out, false): _buff("B05-U03", "damage_reduction_bonus", 0.05, 4.0)

## Rolling three-event window. Only the last two prior qualifying events survive.
## Slots/costs are small integers and expiries finite scalars in the save contract.
func _b05_sequence(id: String, seconds: float, slot: int, cost: int, alternating: bool) -> bool:
	var entries: Array[Dictionary] = []
	for index in 2:
		var key := id + ":seq" + str(index)
		if _window(key): entries.append({"until":windows[key], "slot":int(counts.get(key + ":slot", 0)), "cost":int(counts.get(key + ":cost", 0))})
	if alternating and not entries.is_empty() and int(entries.back().slot) == slot: entries.clear()
	entries.append({"until":clock + seconds, "slot":slot, "cost":cost})
	var spent := 0
	for entry: Dictionary in entries: spent += int(entry.cost)
	var complete := entries.size() >= 3 and (not alternating or spent >= 60)
	if complete: entries.clear()
	elif entries.size() > 2: entries = entries.slice(entries.size() - 2)
	for index in 2:
		var key := id + ":seq" + str(index)
		windows.erase(key)
		counts.erase(key + ":slot")
		counts.erase(key + ":cost")
		if index < entries.size():
			windows[key] = float(entries[index].until)
			counts[key + ":slot"] = int(entries[index].slot)
			counts[key + ":cost"] = int(entries[index].cost)
	return complete

## B05 damage budgets are authored fixed AD/AP, never the class's blended H.
## Geometry is supplied by the live adapter, which has actual collision/LOS data.
func _b05_packet(ctx: Dictionary, root: Dictionary, out: Dictionary, id: String, icd: float, coefficient: float, targets: Array, limit: int, power_type: String, frozen_damage: float = -1.0, allow_new_budget: bool = true) -> void:
	if targets.is_empty(): return
	var power_stats: Dictionary = ctx.get("attacker_stats", stats)
	var fixed_power := float(power_stats.get("ability_power" if power_type == "magic" else "attack", 0.0))
	var amount := Numerical.integer(fixed_power * coefficient) if frozen_damage < 0.0 else Numerical.integer(frozen_damage)
	if allow_new_budget:
		_prime_b05_budget(ctx, root, fixed_power)
	elif not root.has("b05_budget_basis"):
		return # A derived release cannot create a new independent budget.
	if amount <= 0: return
	var ids: Array[String] = []
	for value: Variant in targets:
		var target := str(value)
		if target.is_empty() or target in ids: continue
		ids.append(target)
		if ids.size() >= limit: break
	if ids.is_empty(): return
	var remaining := maxi(0, int(Numerical.derived_budget(float(root.b05_budget_basis), Numerical.V2)) - int(root.get("damage_spent", 0)))
	var amounts := {}
	var spent := 0
	for target: String in ids:
		var packet := mini(amount, remaining)
		if packet <= 0: break
		amounts[target] = packet
		remaining -= packet
		spent += packet
	if spent <= 0 or not _activate(id, icd, root, out): return
	root["damage_spent"] = int(root.get("damage_spent", 0)) + spent
	root.coefficient = float(root.damage_spent) / maxf(1.0, float(root.raw_packet))
	ids.assign(amounts.keys())
	out.bonus_hits.append({"target_ids":ids, "damage":amount, "damage_by_target":amounts, "coefficient":coefficient,
		"source":"equipment", "damage_source":"equipment", "damage_type":power_type, "proc_depth":1,
		"equipment_eligible":false, "critical":false, "states":[], "effect_id":id})


## B05 fixed-P supplement: one shared cast budget uses max(original X, fixed P).
## Called only by a confirmed direct trigger or actual original node placement.
## Old equipment _bonus still uses its unchanged original-X budget calculation.
func _prime_b05_budget(ctx: Dictionary, root: Dictionary, fixed_power: float) -> void:
	if not root.has("raw_packet"):
		root["raw_packet"] = Numerical.integer(float(ctx.get("X", ctx.get("H", 0.0))))
		root["damage_spent"] = int(floor(float(root.raw_packet) * float(root.coefficient)))
	root["b05_budget_basis"] = maxf(float(root.get("b05_budget_basis", 0.0)), maxf(float(root.raw_packet), fixed_power))


func clear_b06_temporary() -> void:
	for values: Dictionary in [windows, counts, buffs]:
		for key: String in values.keys():
			if key.begins_with("B06-"): values.erase(key)

func clear_b10_temporary() -> void:
	for values: Dictionary in [windows, counts, buffs]:
		for key: String in values.keys():
			if key.begins_with("B10-"): values.erase(key)
