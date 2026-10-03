extends "res://tests/support/s11_damage_trail.gd"
## Read-only source attribution at the native receipt, before player.status.absorb.
## Shared-max ties remain multiple possible sources; never add their capacities.
var player_reference: WeakRef
func record(raw_amount:float,resolved_amount:float,hp_before:float,hp_after:float,shield_before:float,shield_after:float,context:Dictionary,elapsed:float)->void:
	super.record(raw_amount,resolved_amount,hp_before,hp_after,shield_before,shield_after,context,elapsed)
	if player_reference==null:return
	var player:SalvagerPlayer=player_reference.get_ref()
	if not is_instance_valid(player):return
	var row:Dictionary=all_events.back()
	row["guard_sources_at_receipt"]=player.status.guards.duplicate(true)
	row["guard_rule"]="shared_max_not_sum"
	row["guard_capacity_before_status_absorb"]=player.status.shield()
	row["guard_pool_matches_receipt"]=is_equal_approx(float(player.status.shield()),shield_before)
	row["maximum_capacity_sources"]=[]
	for source:String in player.status.guards:
		var guard:Dictionary=player.status.guards[source]
		if float(guard.get("remaining",0))>0 and is_equal_approx(float(guard.get("amount",0)),shield_before) and shield_before>0:
			row.maximum_capacity_sources.append(source)
