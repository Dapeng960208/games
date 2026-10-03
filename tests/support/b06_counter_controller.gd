extends "res://tests/support/b06_balance_controller.gd"
## Optional player-input route: one completed west drain, then legal pillar bait.
## No actor positions, clocks, cooldowns, damage, or encounter geometry are written.
var drained := false
var bait_attempted := false
func counter_target(boss: Node2D) -> Dictionary:
	if not is_instance_valid(boss) or not is_instance_valid(room.b06_mechanics): return {}
	var host = room.b06_mechanics
	var tide: Dictionary = host.state.snapshot()
	var geometry: Dictionary = room.layout.get("b06_geometry",{})
	if not drained:
		if int(tide.drained_until.get("bay_west",0))>int(tide.now_us):
			drained=true
		else:
			var gate: Vector2=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point(geometry.gates[0].position)
			if room.player.position.distance_to(gate)<=60:
				room.player.clear_movement_target()
				if tide.channel.is_empty(): room.interact()
				return {"position":gate,"interactive":true}
			return {"position":gate,"interactive":true}
	if bait_attempted or int(tide.drained_until.get("bay_west",0))<=int(tide.now_us): return {}
	var pillar: Vector2=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point(geometry.reef_pillars[0])
	if host.boss_state.exposure_remaining()>0:
		bait_attempted=true
		return {}
	# Lead the boss toward the drained pillar, attacking whenever in reach.
	# Visible claw warning remains handled by inherited legal dodge behavior.
	var bait: Vector2=pillar+boss.position.direction_to(pillar)*65.0
	if boss.position.distance_to(pillar)>145 or room.player.position.distance_to(bait)>30:
		navigate_to_reachable(next_decision,bait,15.0,visible_threats())
		mode(next_decision,"pillar_bait",bait)
		return {"position":bait,"interactive":false,"move_only":true}
	return {}
