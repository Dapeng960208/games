extends "res://scripts/gameplay/characters/hero_abilities.gd"
## Read-only timeline wrapping. Calls each production method exactly once.
var audit: Array[Dictionary] = []
var last_commit: Dictionary = {}
func state_row(kind: String) -> Dictionary:
	return {"kind":kind,"t":owner_player.room.elapsed if is_instance_valid(owner_player) else 0.0,"serial":active.get("serial",0),"slot":active.get("spec",{}).get("slot",""),"elapsed":active.get("elapsed",0),"duration":active.get("spec",{}).get("duration",0),"next_event":active.get("next_event",0),"event_count":active.get("events",[]).size(),"paid_cost":active.get("paid_cost",0),"player_position":owner_player.position if is_instance_valid(owner_player) else Vector2.ZERO,"target":active.get("target",Vector2.ZERO)}
func cancel() -> void:
	if not active.is_empty(): audit.append(state_row("cancel"))
	super.cancel()
func tick(delta: float) -> void:
	var before := state_row("timeline_ended") if not active.is_empty() else {}
	var audit_start := audit.size()
	super.tick(delta)
	if not before.is_empty() and active.is_empty():
		var cancelled := false
		for i in range(audit_start,audit.size()):
			if audit[i].kind=="cancel": cancelled=true
		if not cancelled: audit.append(before)
func _resolve(index: int) -> void:
	var row := state_row("release")
	row["event_index"]=index
	audit.append(row)
	super._resolve(index)

func try_cast(slot: String, target: Vector2, validate_only: bool = false, allow_recovery_chain: bool = false, ignore_busy: bool = false, preview_cooldown: bool = false) -> bool:
	var before: float = Game.run.resource if Game.run!=null else 0
	var result := super.try_cast(slot,target,validate_only,allow_recovery_chain,ignore_busy,preview_cooldown)
	if result and not validate_only:
		last_commit=state_row("paid_commit")
		last_commit["resource_before"]=before
		last_commit["resource_after_class_refund"]=Game.run.resource
		last_commit["effective_class_refund"]=float(Game.run.resource)-before+float(active.paid_cost)
		audit.append(last_commit)
	return result
