extends "res://scripts/levels/b06/combat/enemy_runtime.gd"
## Read-only audit at the exact native filter seam. Calls production once.
var damage_filter_audit: Array[Dictionary] = []
func filter_damage(target: Node2D, amount: float, kind: StringName, from_direction: Vector2, damage_type: String, context: Dictionary = {}) -> float:
	var facing: Vector2 = Props.read(target,"aim_direction",Vector2.RIGHT)
	var region := "front_shell" if not from_direction.is_zero_approx() and facing.dot(-from_direction.normalized())>.5 else "side_abdomen"
	var mechanism: Variant = Skills.mechanics(target)
	var boss_state: Variant = Props.read(mechanism,"boss_state") if mechanism is Object else null
	var before := {"t":host.room.elapsed,"target_template":str(Props.read(target,"enemy_id","")),"target_id":target.get_instance_id(),"kind":str(kind),"damage_type":damage_type,"attack_id":context.get("attack_id",""),"root_event_id":context.get("root_event_id",""),"input_amount":amount,"from_direction":from_direction,"facing":facing,"region":region,"region_multiplier":float(boss_state.incoming_multiplier(region)) if boss_state is Object else 1.0,"armor":target.effective_armor(),"magic_resist":target.magic_resist,"armor_penetration":context.get("armor_penetration",context.get("attacker_stats",{}).get("armor_penetration",0)),"magic_penetration":context.get("magic_penetration",context.get("attacker_stats",{}).get("magic_penetration",0)),"armor_multiplier":context.get("armor_multiplier",1.0),"corrosion":target.status.has("corrosion")}
	var result: float = super.filter_damage(target,amount,kind,from_direction,damage_type,context)
	before["output_amount"]=result
	if host.room.recording: damage_filter_audit.append(before)
	return result
