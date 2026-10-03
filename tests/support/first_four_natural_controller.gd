extends "res://tests/support/b05_balance_controller.gd"
## Same lawful input controller, plus non-Boss room breakable objectives.
## Never calls damage, completion, or objective mutation APIs.
const FIRST_FOUR_VERSION := "first-four-natural-controller-v1"
func counter_target(boss: Node2D) -> Dictionary:
	var inherited:=super.counter_target(boss)
	if not inherited.is_empty() or is_instance_valid(boss): return inherited
	if not is_instance_valid(room.objectives) or room._living_enemy_count()>0: return {}
	var nearest := INF
	var result := {}
	for item: Dictionary in room.objectives.elements.values():
		if not (bool(item.get("breakable",false)) or bool(item.get("attackable",false))) or bool(item.get("done",false)) or bool(item.get("destroyed",false)) or not bool(item.get("active",true)): continue
		var actor: Node2D=room.objectives.targets.get(str(item.id))
		if not is_instance_valid(actor) or not actor.is_alive(): continue
		var distance: float=room.player.position.distance_squared_to(actor.position)
		if distance<nearest:
			nearest=distance
			result={"actor":actor,"position":actor.position,"breakable":true}
	return result
