extends "res://scripts/combat/enemy.gd"
## Production root wells use the ordinary confirmed-hit pipeline, but never
## count as encounters, grant rewards, or emit an enemy-death callback.
const WELL_CANVAS := Vector2(128,128)
const WELL_PIVOT := Vector2(0.5,0.70)
const WELL_ART := "res://assets/generated/world/b05_rootwell/rootwell-%s-native.png"
var mechanism_host: Node2D
var well_id := ""
var _well_textures: Dictionary = {}
var _broken_reported := false

func _ready() -> void:
	static_actor = true
	reward_enabled = false
	actor_kind = "objective"
	super._ready()
	state = &"idle"
	state_time = 0.0
	for visual_state: String in ["active","hit","disconnected","destroyed"]:
		_well_textures[visual_state] = TextureSampler.sampled(WELL_ART % visual_state)
	queue_redraw()

func impact_material() -> String:
	return "organic"

func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	if not is_instance_valid(mechanism_host) or not mechanism_host.well_can_take_damage(well_id):
		last_damage_result = {"confirmed":false,"hp_damage":0.0,"shield_damage":0.0}
		return false
	var was_active: bool = mechanism_host.well_is_active(well_id)
	var accepted: bool = super.take_damage(amount,kind,direction,context)
	if accepted:
		# Settlement has already applied defense, immunity, caps and shield rules.
		var receipt: Dictionary = mechanism_host.apply_confirmed_well_damage(well_id,last_damage_result)
		if bool(receipt.get("destroyed",false)) and not _broken_reported:
			_broken_reported = true
			var settled_context := context.duplicate()
			settled_context["b05_active_well_destroyed"] = was_active
			mechanism_host.well_destroyed_by_hit(well_id,settled_context)
	queue_redraw()
	return accepted

func _die() -> void:
	# Damage receipt is settled by take_damage after the health signal returns.
	# Keep the authored destroyed sprite as a non-attackable landmark.
	velocity = Vector2.ZERO
	state = &"dead"

func synchronize_well(value: Dictionary) -> void:
	if health == null or value.is_empty(): return
	health.current = clampf(float(value.hp),0.0,health.maximum)
	health.dead = health.current <= 0.0 or bool(value.closed)
	_broken_reported = health.current <= 0.0
	state = &"dead" if health.dead else &"idle"
	queue_redraw()

func _draw() -> void:
	if health == null: return
	var visual_state := "active"
	if health.current <= 0.0: visual_state = "destroyed"
	elif hurt_flash > 0.0: visual_state = "hit"
	elif is_instance_valid(mechanism_host) and not mechanism_host.well_is_active(well_id): visual_state = "disconnected"
	var texture: Texture2D = _well_textures.get(visual_state)
	if texture != null:
		draw_texture_rect(texture,Rect2(-WELL_CANVAS*WELL_PIVOT,WELL_CANVAS),false)
	if not health.dead:
		draw_rect(Rect2(-31,-91,62,7),Color("f8f2dc"))
		draw_rect(Rect2(-29,-89,58*health.current/maxf(1.0,health.maximum),3),Color("2c9690"))
