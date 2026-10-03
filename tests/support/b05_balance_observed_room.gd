extends "res://tests/support/s11_observed_room.gd"
## Transparent before/after audit. Does not call preview/proc APIs a second time.
var direct_audit: Array[Dictionary] = []
func _resolve_numerical_direct_hit(target: MineEnemy, amount: float, source: StringName, applied_status: String, push: float, direction: Vector2, attack_context: Dictionary) -> bool:
	var row := {"t":elapsed,"source":str(source),"X":amount,"root_event_id":attack_context.get("root_event_id",""),"attack_id":attack_context.get("attack_id",""),"target_id":target.get_instance_id(),"target_template":target.enemy_id,"target_hp_before":target.health.current,"target_shield_before":target.status.shield(),"target_armor":target.effective_armor(),"target_magic_resist":target.magic_resist,"target_states_before":target.status.states.duplicate(true),"class_mark_before":player.has_hunter_mark(target),"class_passive_before":player.passives.snapshot().duplicate(true),"chain_before":player.hit_chain.snapshot().duplicate(true),"boss_incoming_multiplier_before":target.boss_brain.incoming_damage_multiplier() if target is MineBoss else 1.0,"biome_weakpoint_before":target.biome_weakpoint_open(),"attacker_stats":Game.run.stats.duplicate(true),"packet_start":packets.size()}
	var result := super._resolve_numerical_direct_hit(target,amount,source,applied_status,push,direction,attack_context)
	row.merge({"confirmed":result,"target_hp_after":target.health.current,"target_shield_after":target.status.shield(),"class_mark_after":player.has_hunter_mark(target),"class_passive_after":player.passives.snapshot().duplicate(true),"chain_after":player.hit_chain.snapshot().duplicate(true),"packet_end":packets.size()})
	if recording: direct_audit.append(row)
	return result
