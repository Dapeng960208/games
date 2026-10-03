extends "res://tests/levels/b05/test_b05_balance_matrix.gd"
const ReceiptTrail = preload("res://tests/support/s11_directed_damage_trail.gd")
const PassiveDriver = preload("res://tests/support/b05_tolerance_controller.gd")
var directed_result: Dictionary = {}
func initialize_directed_scenario() -> void:
	config["experiment"] = "separate_p3_single_packet"
	# Synthetic PRE-clock phase/spawn, excluded from all baseline TTK aggregates.
	var initial_hp := floorf(float(boss.health.maximum)*.35)
	boss.health.damage(float(boss.health.current)-initial_hp)
	boss.boss_brain.tick(boss,.000001,room.player)
	check(boss.boss_brain.phase==3,"native HP threshold enters P3")
	var entry := room.player.position
	var found := false
	for i in 32:
		var point := boss.position+Vector2.from_angle(TAU*float(i)/32)*175.0
		if room.valid_ground(point,Balance.PLAYER_RADIUS) and room.has_line_of_sight(boss.position,point):
			room.player.position=point
			found=true
			break
	check(found,"declared P3 initial ground lawful")
	var guard: float = room.player.status.shield()
	room.player.status.absorb(guard)
	room.player.status.tick_guard(0)
	run_ref.shield=room.player.status.shield()
	check(run_ref.hp==run_ref.max_hp and run_ref.shield==0,"supplement starts fullHP/no shield")
	trail=ReceiptTrail.new();trail.room_reference=weakref(room);Game.damage_trail=trail
	driver=PassiveDriver.new()
	boss.boss_brain._begin_action(boss,room.player,"crown_sweep")
	check(boss.boss_brain.current_action=="crown_sweep" and boss.boss_brain.state==&"telegraph","native P3 dangerous single swing telegraph")
	fixture["directed_initial_conditions"]={"synthetic":true,"excluded_from_baseline_ttk":true,"initial_hp":initial_hp,"phase":3,"action":"crown_sweep","action_reason":"largest authored BO05 single-packet coefficient1.10; not a multi-ring volley","entry_shield_consumed":guard,"authored_spawn":[entry.x,entry.y],"actual_spawn":[room.player.position.x,room.player.position.y],"full_hp":run_ref.hp,"no_offense_healing_or_defensive_input":true}
	last_boss_hp=initial_hp;boss_max_hp=initial_hp;directed_result={}
func requires_attack_evidence() -> bool: return false
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not running or trail.all_events.is_empty(): return
	var packet: Dictionary = trail.all_events.front()
	var eligible: bool = bool(packet.get("eligible_full_hp_unshielded_p3",false)) and trail.all_events.size()==1
	directed_result={"eligible":eligible,"packet":packet.duplicate(true),"hp_loss_fraction":float(packet.hp_loss)/run_ref.max_hp,"survived":float(packet.hp_after)>0,"passed":eligible and float(packet.hp_after)>0 and float(packet.hp_loss)/run_ref.max_hp<=.20}
	running=false;room.process_mode=Node.PROCESS_MODE_DISABLED
func finish_record() -> void:
	super.finish_record()
	rows.back()["outcome"]="directed_packet_received" if not directed_result.is_empty() else "directed_no_packet"
	rows.back()["directed_result"]=directed_result.duplicate(true)
