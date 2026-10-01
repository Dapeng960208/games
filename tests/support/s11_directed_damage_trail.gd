extends "res://tests/support/s11_damage_trail.gd"
## Read-only receipt-time eligibility. Captured inside the native receipt,
## before Player adds post-hit invulnerability or invokes on-hit passives.
var room_reference: WeakRef

func record(raw_amount: float, resolved_amount: float, hp_before: float, hp_after: float, shield_before: float, shield_after: float, context: Dictionary, elapsed: float) -> void:
	super.record(raw_amount,resolved_amount,hp_before,hp_after,shield_before,shield_after,context,elapsed)
	var room: MineRoom = room_reference.get_ref() if room_reference != null else null
	if not is_instance_valid(room): return
	var boss: MineBoss = room._boss_actor
	var player: SalvagerPlayer = room.player
	var row: Dictionary = all_events.back()
	row["boss_phase_at_impact"] = boss.boss_brain.phase if is_instance_valid(boss) else 0
	row["maximum_player_hp"] = Game.run.max_hp if Game.run != null else hp_before
	row["damage_reduction"] = float(context.get("damage_reduction",0))
	row["static_equipment_damage_reduction"] = float(Game.run.stats.get("equipment_damage_reduction",0)) if Game.run != null else 0.0
	row["invulnerable_context"] = bool(context.get("invulnerable",false))
	row["hurt_invulnerability_before_receipt"] = player.invulnerable
	row["dash_protected_before_receipt"] = player.dash_protected()
	row["native_status_modifiers"] = player.status.damage_modifiers().duplicate(true)
	row["eligible_full_hp_unshielded_p3"] = row.boss_phase_at_impact==3 and hp_before==row.maximum_player_hp and shield_before==0 and row.damage_reduction==0 and not row.invulnerable_context and player.invulnerable<=0 and not player.dash_protected() and not bool(context.get("dot",false)) and str(context.get("damage_event",""))!="shock"
