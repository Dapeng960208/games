extends "res://scripts/gameplay/monsters/enemy_actor.gd"
## Real attackable alternative to turning two mirrors. No loot or XP.
var mechanism_host: Node2D
func _ready() -> void:
	static_actor = true
	reward_enabled = false
	actor_kind = "objective"
	super._ready()
	state = &"idle"
	if is_instance_valid(body_visual): body_visual.visible = false
func is_alive() -> bool:
	return is_instance_valid(mechanism_host) and mechanism_host.state.phase >= 2 and mechanism_host.state.altar_hp > 0
func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	if not is_alive(): return false
	var accepted := super.take_damage(amount,kind,direction,context)
	if accepted:
		mechanism_host.state.damage_altar(float(last_damage_result.get("hp_damage",0)))
		queue_redraw()
	return accepted
func _die() -> void: state = &"dead"; velocity = Vector2.ZERO
func synchronize() -> void:
	if health == null: return
	health.current = mechanism_host.state.altar_hp
	health.dead = health.current <= 0
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(mechanism_host): return
	var enabled: bool = mechanism_host.state.phase >= 2 and mechanism_host.state.altar_hp > 0
	draw_circle(Vector2.ZERO,32,Color("4d8e82") if enabled else Color("ac9875"))
	draw_arc(Vector2.ZERO,35,0,TAU,32,Color("ead078"),4,true)
	if enabled:
		draw_rect(Rect2(-36,-50,72,7),Color("55433e"))
		draw_rect(Rect2(-34,-48,68*mechanism_host.state.altar_hp/maxf(1,mechanism_host.state.altar_max_hp),3),Color("f9e097"))
