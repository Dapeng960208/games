class_name HeroPassives
extends RefCounted

const Numbers = preload("res://config/numerical_rules.gd")
## Automatic, room-local class passives. Only confirmed original packets and
## successful cast commitments enter this state; derived damage never does.

const ROOT_LIMIT := 128
const ROOT_LIFETIME := 12.0
const FOCUS_LIFETIME := 5.0
const RHYTHM_LIFETIME := 8.0

var owner_player: Node2D
var _hero: String = ""
var _clock: float = 0.0
var _count: int = 0
var _cooldown: float = 0.0
var _seen: Dictionary = {}
var _reservations: Dictionary = {}
var _focus: WeakRef
var _focus_remaining: float = 0.0
var _last_kind: String = ""
var _rhythm_remaining: float = 0.0
var _capture_serial: int = 0
var _restored_serial: int = 0

func configure(player: Node2D) -> void:
	owner_player = player
	reset()

func reset() -> void:
	_hero = owner_player.hero_id() if is_instance_valid(owner_player) else ""
	_clock = 0.0
	_count = 0
	_cooldown = 0.0
	_seen.clear()
	_reservations.clear()
	_focus = null
	_focus_remaining = 0.0
	_last_kind = ""
	_rhythm_remaining = 0.0

## An immediate equipment change may rebuild the actor's JSON-safe combat
## snapshot, but it must not renew a passive or erase its original-event ledger.
## This detached state is strictly in-memory and contains WeakRefs by design.
## Never place it in expedition.runtime, a profile, JSON or a room-entry save.
func capture_same_room() -> Dictionary:
	if not _available() or not is_instance_valid(owner_player.room):
		return {}
	_capture_serial += 1
	return {"source":weakref(self), "owner":weakref(owner_player), "room":weakref(owner_player.room), "serial":_capture_serial,
		"hero_id":_hero, "run_id":str(Game.run.id), "layout_id":str(owner_player.room.get("layout_id")), "checkpoint_id":str(Game.run.expedition.get("checkpoint_id", "")),
		"clock":_clock, "count":_count, "cooldown":_cooldown, "seen":_seen.duplicate(true), "reservations":_reservations.duplicate(true),
		"focus":_focus, "focus_remaining":_focus_remaining, "last_kind":_last_kind, "rhythm_remaining":_rhythm_remaining}

## Accept only the latest capture from this exact module, actor and room. The
## one-use serial prevents a retained UI value from rewinding timers a second
## time; room/checkpoint identity prevents carrying target state into a new room.
func restore_same_room(state: Dictionary) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	for key: String in ["source", "owner", "room"]:
		if not state.get(key) is WeakRef:
			return false
	if state.source.get_ref() != self or state.owner.get_ref() != owner_player or state.room.get_ref() != owner_player.room:
		return false
	var serial: int = int(state.get("serial", -1))
	if serial != _capture_serial or serial <= _restored_serial or str(state.get("hero_id", "")) != _hero or str(state.get("run_id", "")) != str(Game.run.id):
		return false
	if str(state.get("layout_id", "")) != str(owner_player.room.get("layout_id")) or str(state.get("checkpoint_id", "")) != str(Game.run.expedition.get("checkpoint_id", "")):
		return false
	for key: String in ["clock", "cooldown", "focus_remaining", "rhythm_remaining"]:
		if not state.get(key) is float and not state.get(key) is int:
			return false
		if not is_finite(float(state[key])) or float(state[key]) < 0.0:
			return false
	if not state.get("count") is int or not state.get("seen") is Dictionary or not state.get("reservations") is Dictionary or str(state.get("last_kind", "")) not in ["", "basic", "skill", "q", "secondary", "f", "ultimate"]:
		return false
	if state.get("focus") != null and not state.focus is WeakRef:
		return false
	_clock = float(state.clock)
	_count = clampi(int(state.count), 0, 2 if _hero == "CH02" else 3)
	_cooldown = float(state.cooldown)
	_seen = state.seen.duplicate(true)
	_reservations = state.reservations.duplicate(true)
	_trim(_seen)
	_trim(_reservations)
	_focus = state.get("focus")
	_focus_remaining = float(state.focus_remaining)
	_last_kind = str(state.last_kind)
	_rhythm_remaining = float(state.rhythm_remaining)
	if _hero == "CH02" and not _target_alive(_focus_target()):
		_focus = null
		_focus_remaining = 0.0
		_count = 0
	_restored_serial = serial
	return true

func tick(delta: float) -> void:
	if not _available() or not is_finite(delta) or delta < 0.0:
		return
	_clock += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_focus_remaining = maxf(0.0, _focus_remaining - delta)
	_rhythm_remaining = maxf(0.0, _rhythm_remaining - delta)
	if _hero == "CH02" and (_focus_remaining <= 0.0 or not _target_alive(_focus_target())):
		_focus = null
		_count = 0
	if _hero == "CH03" and _rhythm_remaining <= 0.0:
		_count = 0
		_last_kind = ""
	for root: String in _seen.keys():
		if _clock - float(_seen[root]) > ROOT_LIFETIME:
			_seen.erase(root)
	for root: String in _reservations.keys():
		if _clock - float(_reservations[root].time) > ROOT_LIFETIME:
			_reservations.erase(root)

## The weak-point bonus belongs to the original hit. Reserve it before damage,
## but consume the mark only after health/shield loss confirms that packet.
func before_hit(target: Node2D, amount: float, source: StringName, context: Dictionary) -> float:
	if not _available() or _hero != "CH02" or not _original(source, context) or not is_finite(amount) or amount <= 0.0:
		return amount
	var root: String = _root(context)
	if root.is_empty() or _seen.has(root) or _cooldown > 0.0 or _count < 2 or _focus_remaining <= 0.0 or target != _focus_target():
		return amount
	if _reservations.has(root) and int(_reservations[root].target_id) != target.get_instance_id():
		return amount
	_reservations[root] = {"target_id":target.get_instance_id(), "time":_clock}
	_trim(_reservations)
	var bonus: Variant = Numbers.amount(maxf(0.0, float(context.get("H", owner_player.attack_power()))) * 0.65, Game.run.ruleset_version())
	return amount + float(bonus)

## The room calls this only after a direct hit removes health or shield. The
## explicit loss check also protects callers outside that shared hit pipeline.
func record_hit(target: Node2D, source: StringName, context: Dictionary) -> void:
	if not _available() or not _original(source, context) or not is_instance_valid(target):
		return
	if float(context.get("hp_damage", 0.0)) + float(context.get("shield_damage", 0.0)) <= 0.0:
		return
	var root: String = _root(context)
	if root.is_empty() or _seen.has(root):
		return
	_seen[root] = _clock
	_trim(_seen)
	var reserved: Dictionary = _reservations.get(root, {})
	_reservations.erase(root)
	var basic: bool = source == &"primary" and bool(context.get("original_basic", false))
	if _hero == "CH01":
		if not basic or _cooldown > 0.0:
			return
		_count += 1
		if _count >= 3:
			_count = 0
			_cooldown = 6.0
			owner_player.grant_guard(Game.run.max_hp * 0.08, 3.0, "hero_passive:three_rivets")
	elif _hero == "CH02":
		if not reserved.is_empty() and int(reserved.target_id) == target.get_instance_id():
			_count = 0
			_focus = null
			_focus_remaining = 0.0
			_cooldown = 2.0
			_feedback("mark_burst", target.position)
		elif basic and _cooldown <= 0.0:
			_count = mini(2, _count + 1) if target == _focus_target() and _focus_remaining > 0.0 else 1
			_focus = weakref(target)
			_focus_remaining = FOCUS_LIFETIME
			if _count == 2:
				_feedback("mark", target.position)
	elif _hero == "CH03" and basic and Game.run.ruleset_version() != Numbers.V2:
		_record_rhythm("basic")

## Call once after validation and resource payment, using the committed cast's
## serial. Multiple shots/waves, cancellation and persistent fields cannot refund.
func skill_committed(slot: String, cast_id: int) -> void:
	if not _available() or _hero != "CH03" or slot not in ["q", "secondary", "f", "ultimate"]:
		return
	var root: String = "cast:" + str(cast_id)
	if _seen.has(root):
		return
	_seen[root] = _clock
	_trim(_seen)
	if _cooldown > 0.0:
		return
	if Game.run.ruleset_version() == Numbers.V2:
		# Spell weaving rewards deliberate spell changes. Basics remain optional,
		# and a persistent field or multiple missiles cannot enter this cast ledger.
		_record_rhythm(slot)
		if _count >= 3:
			var definition: Dictionary = ContentRegistry.hero(_hero).get("passive",{})
			_count = 0
			_cooldown = float(definition.get("icd_v2",1.2))
			owner_player.restore_class_resource(float(Numbers.scale(float(definition.get("resource_gain_v2",10)),Numbers.V2)))
			owner_player.cooldowns.q = maxf(0.0, float(owner_player.cooldowns.q) - float(definition.get("q_cooldown_refund_v2",.6)))
			owner_player.charge_nearest_resonance(owner_player.position, 260.0)
			if is_instance_valid(owner_player.room):
				owner_player.room.add_ring(owner_player.position, Color("78d9d1"), 38.0, 0.28)
		return
	if _count >= 3:
		_count = 0
		_last_kind = "skill"
		_rhythm_remaining = RHYTHM_LIFETIME
		_cooldown = 2.0
		owner_player.restore_class_resource(float(Numbers.scale(8.0, Game.run.ruleset_version())))
		owner_player.charge_nearest_resonance(owner_player.position, 260.0)
		if is_instance_valid(owner_player.room):
			owner_player.room.add_ring(owner_player.position, Color("78d9d1"), 38.0, 0.28)
	else:
		_record_rhythm("skill")

func snapshot() -> Dictionary:
	_available()
	var definition: Dictionary = ContentRegistry.hero(_hero).get("passive", {})
	var hint: String = ""
	var tint := Color("eabb78")
	var max_count: int = 3
	var spell_refund: int = Numbers.integer(float(Numbers.scale(float(definition.get("resource_gain_v2",10)),Numbers.V2))*float(owner_player.resource_gain_multiplier())) if _hero == "CH03" and is_instance_valid(owner_player) else 0
	var q_refund: float = float(definition.get("q_cooldown_refund_v2",.6))
	if _hero == "CH01":
		var momentum: int = int(owner_player.break_stacks) if is_instance_valid(owner_player) else 0
		hint = "有效普攻 %d/3 · 破势 %d/3 · 满势 W 免怒" % [_count, momentum]
	elif _hero == "CH02":
		max_count = 2
		tint = Color("d9bbff")
		hint = "弱点就绪 · 下次普攻 / 技能 +65%攻击" if _count == 2 else "同目标命中 %d/2 · 第三击 / 技能破弱点" % _count
	else:
		tint = Color("78d9d1")
		if Game.run != null and Game.run.ruleset_version() == Numbers.V2:
			hint = "交替施法 %d/3 · 第三次回%d法力 / Q减%.1f秒" % [_count,spell_refund,q_refund]
		else:
			hint = "共鸣已满 · 下次技能回 %d 法力" % int(Numbers.scale(8.0, Game.run.ruleset_version() if Game.run != null else Numbers.LEGACY)) if _count >= 3 else "普攻 / 技能交替 · 共鸣 %d/3" % _count
	if _cooldown > 0.0:
		hint = "被动冷却 %.1f 秒" % _cooldown
	return {"name":str(definition.get("name", "职业被动")), "description":str(definition.get("description", "")), "current":_count, "max":max_count, "hint":hint, "color":tint, "icd":_cooldown, "cooldown":_cooldown, "ready":_cooldown <= 0.0 and ((_hero == "CH02" and _count == 2) or (_hero == "CH03" and _count >= 3)), "focus_remaining":_focus_remaining, "rhythm_remaining":_rhythm_remaining,"resource_refund":spell_refund,"q_cooldown_refund":q_refund}

func _record_rhythm(kind: String) -> void:
	if _cooldown > 0.0 or kind == _last_kind:
		return
	_last_kind = kind
	_count = mini(3, _count + 1)
	_rhythm_remaining = RHYTHM_LIFETIME

func _available() -> bool:
	if not is_instance_valid(owner_player):
		return false
	if owner_player.hero_id() != _hero:
		reset()
	if Game.run == null or Game.run.hp <= 0.0:
		reset()
		return false
	return true

func _original(source: StringName, context: Dictionary) -> bool:
	return source in [&"primary", &"q", &"secondary", &"f", &"ultimate"] and bool(context.get("equipment_eligible", false)) and int(context.get("proc_depth", 0)) == 0 and (source != &"primary" or bool(context.get("original_basic", false)))

func _root(context: Dictionary) -> String:
	return str(context.get("root_event_id", context.get("attack_id", "")))

func _focus_target() -> Node2D:
	return _focus.get_ref() as Node2D if _focus != null else null

func _target_alive(target: Node2D) -> bool:
	return is_instance_valid(target) and target.has_method("is_alive") and bool(target.is_alive())

func _trim(values: Dictionary) -> void:
	while values.size() > ROOT_LIMIT:
		values.erase(values.keys()[0])

func _feedback(kind: String, at: Vector2) -> void:
	var feedback: Node = owner_player.get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.class_event(kind, at, owner_player.aim_direction)
