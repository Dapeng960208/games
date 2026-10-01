extends RefCounted
## Combat-first grave sealing and real charge/attack barricade counterplay.
var host: Node2D
var biome_id := ""
var variant := 0
var count := 2
var clock := 0.0
var working := ""
var revivals := 0
var pending: Array[Dictionary] = []
var _charge_receipts: Dictionary = {}
const MAX_REVIVALS := 4
const GRAVE_REVIVAL_RADIUS := 320.0
const SEAL_SECONDS := 1.6

func configure(next_host: Node2D, next_biome: String, next_variant: int, next_count: int) -> void:
	host = next_host
	biome_id = next_biome
	variant = next_variant
	count = next_count
	clock = 0.0
	working = ""
	revivals = 0
	pending.clear()
	_charge_receipts.clear()
	for index: int in count:
		var at: Vector2 = host.combat_objective_point(index,count)
		if biome_id=="B03":
			host.add_element("grave_seal_"+str(index),at,host.combat_objective_label(index,"封墓石 " + str(index+1)),"grave_seal",host.combat_objective_asset(index,"B03_transformer"),{"description":host.interaction_key()+" 开始封墓；站近1.6秒，离开保留进度。未封墓可有限复生敌人","description_en":host.interaction_key()+" begins sealing; stay near for 1.6s. Leaving preserves progress. Unsealed graves permit limited resurrection.","repeatable":true,"always_label":true,"visual_height":90.0})
		else:
			host.add_target("war_barricade_"+str(index),at,120.0+variant*15.0,host.combat_objective_asset(index,"B04_resonance_obelisk"),host.combat_objective_label(index,"战寨路障 " + str(index+1)),{"description":"引重装冲锋撞碎，或用普攻拆除；拆障后附近兽人防御短暂削弱","description_en":"Lure a heavy charge into this barricade or break it with basic attacks. Nearby orc defenses weaken after the breach.","always_label":true,"visual_height":96.0})
	host.message = status_text()

func _paused() -> bool:
	return host.is_inside_tree() and host.get_tree().paused

func tick(delta: float) -> void:
	if delta<=0 or not is_finite(delta) or _paused() or host.finished: return
	clock += delta
	if biome_id!="B03": return
	if not working.is_empty():
		var item: Dictionary = host.element(working)
		if not item.is_empty() and not bool(item.done) and host.near(item.position,90):
			item.progress = minf(1.0,float(item.progress)+delta/SEAL_SECONDS)
			if float(item.progress)>=1.0:
				host.set_done(working)
				item.interactive = false
				host.event("grave_sealed",{"id":working,"remaining":count-host.completed_count})
				working = ""
	if host.completed_count>=count:
		pending.clear()
	else:
		_tick_revivals(delta)
	if host.completed_count>=count and host.combat_actors().is_empty() and pending.is_empty():
		host.finish()
	host.message = status_text()

func interact(id: String, actor: Node2D) -> bool:
	if biome_id!="B03" or host.finished or _paused() or actor!=host.player(): return false
	var item: Dictionary = host.element(id)
	if not id.begins_with("grave_seal_") or item.is_empty() or bool(item.done) or not host.near(item.position,90): return false
	working = id
	host.event("grave_seal_started",{"id":id})
	return true

func on_target_hit(_id: String, _context: Dictionary) -> void: pass

func on_target_destroyed(id: String) -> void:
	if biome_id!="B04" or host.finished or not id.begins_with("war_barricade_"): return
	var item: Dictionary = host.element(id)
	if item.is_empty() or bool(item.done): return
	host.set_done(id)
	for actor: Node2D in host.enemies_near(item.position,440):
		host.combat_counter_effect(actor,"war_drum",6.0)
	host.event("war_barricade_breached",{"id":id,"position":item.position})
	if host.completed_count>=count: host.finish()

func notify_enemy_death(enemy: Node2D) -> void:
	if biome_id!="B03" or host.finished or _paused() or host.completed_count>=count or not is_instance_valid(enemy): return
	if str(enemy.get("actor_kind"))!="enemy" or bool(enemy.get("static_actor")) or str(enemy.get("rank"))=="boss" or bool(enemy.get_meta("grave_revived",false)) or bool(enemy.get_meta("grave_death_recorded",false)): return
	if revivals+pending.size()>=MAX_REVIVALS: return
	var id: String = str(enemy.get("enemy_id"))
	if id.is_empty(): return
	var profile: Dictionary = enemy.get("profile") if enemy.get("profile") is Dictionary else {}
	if str(profile.get("biome_id",""))!="B03": return
	var at: Vector2 = enemy.position
	var grave: Dictionary = _nearest_grave(at)
	if grave.is_empty(): return
	enemy.set_meta("grave_death_recorded",true)
	pending.append({"enemy_id":id,"level":int(enemy.get("enemy_level")),"zone_index":int(enemy.get("zone_index")),"position":host.safe_point(Vector2(grave.position)+Vector2(64,0),24),"remaining":1.5,"attempts":0})
	host.event("grave_revival_warned",{"position":pending.back().position,"remaining":1.5})
	if host.room.has_method("add_ring"): host.room.add_ring(pending.back().position,Color("bda0c8"),38,1.5)

func _nearest_grave(at: Vector2) -> Dictionary:
	var selected: Dictionary = {}
	var distance := GRAVE_REVIVAL_RADIUS * GRAVE_REVIVAL_RADIUS
	for index: int in count:
		var item: Dictionary = host.element("grave_seal_"+str(index))
		if bool(item.get("done",false)): continue
		var next: float = at.distance_squared_to(item.position)
		if next<distance: selected=item; distance=next
	return selected

func _tick_revivals(delta: float) -> void:
	for index: int in range(pending.size()-1,-1,-1):
		var item: Dictionary = pending[index]
		item.remaining = maxf(0,float(item.remaining)-delta)
		if float(item.remaining)>0: continue
		var revived: Node2D = host.room.spawn_enemy(item.position,str(item.enemy_id),int(item.level),{"zone_index":int(item.zone_index),"reward_enabled":false})
		if is_instance_valid(revived):
			revived.set_meta("grave_revived",true)
			revivals += 1
			host.event("grave_enemy_revived",{"enemy_id":item.enemy_id,"position":revived.position,"total":revivals,"reward_enabled":false})
			pending.remove_at(index)
		else:
			item.attempts = int(item.attempts)+1
			if int(item.attempts)>=6: pending.remove_at(index)
			else: item.remaining = 0.5

func notify_charge_impact(caster: Node2D, from: Vector2, to: Vector2) -> Dictionary:
	if biome_id!="B04" or host.finished or _paused() or not is_instance_valid(caster) or from.distance_to(to)<12:
		return {"success":false,"reason":"not_eligible"}
	var profile: Dictionary = caster.get("profile") if caster.get("profile") is Dictionary else {}
	if str(profile.get("biome_id",""))!="B04" or str(caster.get("actor_kind"))!="enemy": return {"success":false,"reason":"not_orc_charge"}
	var receipt: String = str(caster.get_instance_id())+":"+str(from)+":"+str(to)
	if clock-float(_charge_receipts.get(receipt,-10.0))<0.5: return {"success":false,"reason":"duplicate_charge"}
	_charge_receipts[receipt] = clock
	var destroyed: int = 0
	for index: int in count:
		var id: String = "war_barricade_"+str(index)
		var item: Dictionary = host.element(id)
		if bool(item.get("done",false)) or _segment_distance(item.position,from,to)>64: continue
		var target: Node2D = item.get("target_actor")
		if not is_instance_valid(target) or not target.is_alive(): continue
		target.take_damage(float(target.health.maximum)+1.0,&"arena_charge",from.direction_to(to),{"damage_type":"true","arena_charge":true})
		if bool(item.done): destroyed += 1
	return {"success":destroyed>0,"destroyed":destroyed}

func _segment_distance(at: Vector2, from: Vector2, to: Vector2) -> float:
	var direction: Vector2 = to-from
	var progress: float = clampf((at-from).dot(direction)/maxf(.001,direction.length_squared()),0,1)
	return at.distance_to(from+direction*progress)

func blocks_dash() -> bool: return false
func encounter_directive(_index: int) -> Dictionary: return {}

func navigation_target() -> Dictionary:
	if host.finished: return {"position":host.layout.exit,"title":"目标完成 · 前往出口","title_en":"Objective complete · Head to the exit"}
	var nearest: Dictionary = {}
	var best := INF
	for item: Dictionary in host.elements.values():
		if bool(item.get("done",false)): continue
		var distance: float = host.player().position.distance_squared_to(item.position) if is_instance_valid(host.player()) else 0.0
		if distance<best: nearest=item; best=distance
	if not nearest.is_empty(): return {"id":nearest.id,"position":nearest.position,"title":nearest.label}
	var actors: Array = host.combat_actors()
	return {"position":actors[0].position if not actors.is_empty() else host.layout.exit,"title":"墓穴已封 · 清理街道","title_en":"Graves sealed · Clear the street"}

func status_text() -> String:
	if biome_id=="B03": return "封墓 %d/%d · E封印，站近1.6秒；全部封闭后清场 · 复生 %d/%d" % [host.completed_count,count,revivals,MAX_REVIVALS]
	return "路障 %d/%d · 引重装冲锋撞碎，或普攻拆障；破障削弱防御" % [host.completed_count,count]

func status_text_en() -> String:
	if biome_id=="B03": return "Graves %d/%d · %s seals in 1.6s nearby; seal all, then clear · Revivals %d/%d" % [host.completed_count,count,host.interaction_key(),revivals,MAX_REVIVALS]
	return "Barricades %d/%d · Lure heavy charges or use basic attacks; breaches weaken defenses" % [host.completed_count,count]
