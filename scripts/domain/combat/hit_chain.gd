class_name CombatHitChain
extends RefCounted
## Confirmed direct attacks only. Presentation and persisted stats never own stacks.
const MAX_HITS := 100
const WINDOW := 4.0
const BONUS_PER_HIT := 0.005
const PACKET_LIMIT := 256
const MILESTONES := [10, 25, 50, 75, 100]
var actor: Node2D
var hero: String = ""
var count: int = 0
var remaining: float = 0.0
var packets: Dictionary = {}

func configure(owner_actor: Node2D) -> void:
	actor = owner_actor
	hero = actor.hero_id()
	reset()

func reset() -> void:
	count = 0
	remaining = 0.0
	packets.clear()

func _available() -> bool:
	if not is_instance_valid(actor) or Game.run == null or Game.run.hp <= 0.0:
		reset()
		return false
	if hero != actor.hero_id():
		hero = actor.hero_id()
		reset()
	return true

func tick(delta: float) -> void:
	if not _available() or actor.get_tree().paused or not is_finite(delta) or delta <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		count = 0
	# Keep consumed IDs when the chain ends: a late pierce cannot count twice.

func _original(source: StringName, context: Dictionary) -> bool:
	return source in [&"primary", &"q", &"secondary", &"f", &"ultimate"] and bool(context.get("equipment_eligible", false)) and int(context.get("proc_depth", 0)) == 0 and (source != &"primary" or bool(context.get("original_basic", false))) and not str(context.get("attack_id", "")).is_empty()

func multiplier(source: StringName, context: Dictionary) -> float:
	if not _available() or not _original(source, context):
		return 1.0
	var id: String = str(context.attack_id)
	if not packets.has(id):
		if packets.size() >= PACKET_LIMIT:
			packets.erase(packets.keys()[0])
		# All victims of one swing/pierce receive its pre-contact bonus.
		packets[id] = {"multiplier":1.0 + count * BONUS_PER_HIT, "confirmed":false}
	return float(packets[id].multiplier)

func record_hit(source: StringName, context: Dictionary) -> bool:
	if not _available() or not _original(source, context) or float(context.get("hp_damage", 0.0)) + float(context.get("shield_damage", 0.0)) <= 0.0:
		return false
	multiplier(source, context)
	var id: String = str(context.attack_id)
	if bool(packets[id].confirmed):
		return false
	packets[id].confirmed = true
	count = mini(MAX_HITS, count + 1)
	remaining = WINDOW
	return true

func snapshot() -> Dictionary:
	_available()
	var tier: int = 0
	var next: int = MAX_HITS
	for threshold: int in MILESTONES:
		if count >= threshold: tier += 1
		elif next == MAX_HITS: next = threshold
	return {"count":count, "maximum":MAX_HITS, "remaining":remaining, "duration":WINDOW, "bonus":count * BONUS_PER_HIT, "tier":tier, "next":next, "hero":hero}
