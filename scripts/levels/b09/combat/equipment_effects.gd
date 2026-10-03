extends RefCounted
## B09 event reducer. Target marks are scalar deadlines in the existing state;
## original cast roots own all one-shot limits and derived damage budgets.
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")

static func enabled(e: Variant) -> bool:
	return Numbers.is_v2(e.stats) and Numbers.b09_candidate_enabled()

static func modifiers(e: Variant, ctx: Dictionary, out: Dictionary) -> void:
	if not enabled(e): return
	out["b09_glide_distance_scale"] = 0.75 if e._has("B09-U01") else 1.0
	out["b09_direct_reduction"] = 0.08 if e._has_set("B09-SU",4) and e._health_ratio(ctx)<0.5 else 0.0
	if e._window("B09-U03:guard"): out.damage_reduction_bonus += 0.06

static func advance(e: Variant, ctx: Dictionary) -> void:
	if not enabled(e): return
	if bool(ctx.get("combat_active",false)): e.windows["B09-combat"] = e.clock + 10.0
	elif e.windows.has("B09-combat") and not e._window("B09-combat"): clear_temporary(e)

static func clear_temporary(e: Variant) -> void:
	for values: Dictionary in [e.windows,e.counts,e.buffs]:
		for id: String in values.keys():
			if id.begins_with("B09-"): values.erase(id)

static func event(e: Variant, name: String, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not enabled(e): return
	var slot := str(ctx.get("skill_slot",ctx.get("slot","")))
	match name:
		"before_hit":
			if e._eligible(ctx): _before(e,ctx,root,out,slot)
		"after_hit":
			if not e._eligible(ctx) or not bool(ctx.get("confirmed",false)): return
			_before(e,ctx,root,e._empty(),slot)
			_after(e,ctx,root,out,slot)
			if bool(ctx.get("shield_broken",false)): _broken(e,ctx,root,out)
		"b09_barrier_broken":
			if _original(ctx): _broken(e,ctx,root,out)
		"skill_cast":
			if not _original(ctx) or not bool(ctx.get("cast_success",false)): return
			if e._has_set("B09-SM",6) and slot in ["secondary","ultimate"] and e._activate("B09-SM_6",10.0,root,out,false):
				var hit_root: Dictionary = e._root(str(ctx.get("b09_hit_root_id",ctx.get("root_event_id",ctx.get("event_id","")))))
				hit_root["b09_condense_armed"] = true
				hit_root["b09_condense_targets"] = []
		"damaged":
			if not e._has_set("B09-SU",6) or not bool(ctx.get("enemy_damage",false)) or bool(ctx.get("self_damage",false)): return
			var loss := Numbers.integer(maxf(0.0,float(ctx.get("hp_damage",0.0))))
			if loss<=0: return
			var threshold := maxi(1,Numbers.integer(float(ctx.get("max_hp",e.stats.get("max_hp",0.0)))*0.1))
			e.counts["B09-SU_6:damage"] = mini(threshold,int(e.counts.get("B09-SU_6:damage",0))+loss)
			if int(e.counts["B09-SU_6:damage"]) >= threshold and e._activate("B09-SU_6",15.0,root,out,false):
				e.counts["B09-SU_6:damage"] = 0
				out["b09_cleanse"] = true
				e._shield(out,ctx,0.03,"B09-SU_6")
		"ordinary_negative_cleared":
			if e._has("B09-U02") and bool(ctx.get("actually_cleared",false)) and e._activate("B09-U02",15.0,root,out,false): e._heal(out,ctx,0.02)

static func _before(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	if slot=="f" and (e._has_set("B09-SG",2) or e._has_set("B09-SM",2)): out.damage_bonus += 0.08
	if slot!="secondary": return
	if e._has_set("B09-SW",2): out["b09_shield_damage_bonus"] = 0.12
	if e._has_set("B09-SW",6):
		if not root.flags.has("B09-SW_6:w"):
			root.flags["B09-SW_6:w"] = e._window("B09-SW_6:next_w") and not bool(root.get("b09_sw6_armed_this_cast",false))
			if bool(root.flags["B09-SW_6:w"]): e.windows.erase("B09-SW_6:next_w")
		if bool(root.flags["B09-SW_6:w"]): out.damage_bonus += 0.12

static func _after(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	var target := str(ctx.get("target_id",""))
	if target.is_empty(): return
	if slot=="secondary" and e._has_set("B09-SW",4) and not bool(root.get("b09_sw4_used",false)):
		root["b09_sw4_used"] = true
		if int(ctx.get("b09_layers_before",0))>0:
			out["b09_break_layer"] = target
		elif e._activate("B09-SW_4",7.0,root,out,false): _packet(e,ctx,root,out,"B09-SW_4",0.20,target,"physical")
	if slot=="secondary" and e._has_set("B09-SW",6) and bool(root.flags.get("B09-SW_6:w",false)) and not bool(root.get("b09_sw6_healed",false)):
		root["b09_sw6_healed"] = true
		e._heal(out,ctx,0.03)
	if slot=="f" and e._has_set("B09-SG",4) and not bool(root.get("b09_sg4_used",false)) and e._activate("B09-SG_4",8.0,root,out,false):
		root["b09_sg4_used"] = true
		e.windows["B09-SG_4:mark:"+target] = e.clock+4.0
		out["b09_slow"] = {"target_id":target,"multiplier":0.95 if bool(ctx.get("b09_target_boss",false)) else 0.90,"duration":2.0}
	if slot=="secondary" and e._has_set("B09-SG",6) and e._window("B09-SG_4:mark:"+target) and not bool(root.get("b09_sg6_used",false)) and e._activate("B09-SG_6",10.0,root,out,false):
		root["b09_sg6_used"] = true
		e.windows.erase("B09-SG_4:mark:"+target)
		e._buff("B09-SG_6","move_speed_bonus",0.08,3.0)
		_packet(e,ctx,root,out,"B09-SG_6",0.40,target,"physical")
	if slot=="f" and e._has_set("B09-SM",4) and float(ctx.get("paid_cost",0.0))>0.0:
		if not root.has("b09_e_targets"): root["b09_e_targets"] = []
		if target not in root.b09_e_targets: root.b09_e_targets.append(target)
		var mana := 30.0 if bool(ctx.get("b09_single_boss",false)) else 60.0 if root.b09_e_targets.size()>=2 else 0.0
		if mana>0 and not bool(root.get("b09_sm4_used",false)) and e._activate("B09-SM_4",8.0,root,out,false):
			root["b09_sm4_used"] = true
			out.resource_restore += minf(mana,maxf(0.0,float(ctx.get("resource_max",e.stats.get("resource_max",0.0)))-float(ctx.get("resource",0.0))))
	if slot in ["secondary","ultimate"] and e._has_set("B09-SM",6) and bool(root.get("b09_condense_armed",false)) and int(ctx.get("b09_segment",0))==0:
		if root.b09_condense_targets.size()<3 and target not in root.b09_condense_targets:
			root.b09_condense_targets.append(target)
			e.windows["B09-SM_6:mark:"+target] = e.clock+4.0
	if slot=="q" and e._has_set("B09-SM",6) and e._window("B09-SM_6:mark:"+target):
		e.windows.erase("B09-SM_6:mark:"+target)
		_packet(e,ctx,root,out,"B09-SM_6:q:"+target,0.25,target,"magic")

static func _broken(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if e._has_set("B09-SW",6) and e._activate("B09-SW_6",10.0,root,out,false):
		# Shield death / the last crystal layer can dispatch before this hit commits.
		# The breaking cast arms a later W, even across its remaining targets.
		root["b09_sw6_armed_this_cast"] = true
		e.windows["B09-SW_6:next_w"] = e.clock+6.0
	if e._has("B09-U03") and e._activate("B09-U03",12.0,root,out,false): e.windows["B09-U03:guard"] = e.clock+4.0

static func _original(ctx: Dictionary) -> bool:
	return int(ctx.get("proc_depth",0))==0 and bool(ctx.get("equipment_eligible",true)) and str(ctx.get("damage_source","skill")) in ["primary","basic","skill"]

static func _packet(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, id: String, coefficient: float, target: String, power_type: String) -> void:
	var stats: Dictionary = ctx.get("attacker_stats",e.stats)
	var power := maxf(0.0,float(stats.get("ability_power" if power_type=="magic" else "attack",0.0)))
	e._prime_b05_budget(ctx,root,power)
	var remaining := maxi(0,int(Numbers.derived_budget(float(root.b05_budget_basis),2))-int(root.get("damage_spent",0)))
	var amount := mini(Numbers.integer(power*coefficient),remaining)
	if amount<=0 or not e._activate(id+":packet",0.0,root,out): return
	root["damage_spent"] = int(root.get("damage_spent",0))+amount
	root.coefficient = float(root.damage_spent)/maxf(1.0,float(root.raw_packet))
	out.bonus_hits.append({"target_ids":[target],"damage":amount,"damage_by_target":{target:amount},"damage_type":power_type,"source":"equipment","damage_source":"equipment","proc_depth":1,"equipment_eligible":false,"critical":false,"states":[],"effect_id":id})
