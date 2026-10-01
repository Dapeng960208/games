extends RecentDamageTrail
## Transparent append-only observer of the existing production damage receipt.
var all_events: Array[Dictionary] = []

func clear() -> void:
	super.clear()
	all_events.clear()

func record(raw_amount: float, resolved_amount: float, hp_before: float, hp_after: float, shield_before: float, shield_after: float, context: Dictionary, elapsed: float) -> void:
	super.record(raw_amount,resolved_amount,hp_before,hp_after,shield_before,shield_after,context,elapsed)
	var row := {"t":elapsed,"raw":raw_amount,"resolved":resolved_amount,"hp_loss":maxf(0.0,hp_before-hp_after),
		"shield_absorbed":maxf(0.0,shield_before-shield_after),"hp_before":hp_before,"hp_after":hp_after,"shield_before":shield_before,"shield_after":shield_after}
	for key: String in ["source_id","source_name","attack_id","damage_type","dot","status","damage_event","key_states"]:
		if context.has(key): row[key] = context[key]
	all_events.append(row)
