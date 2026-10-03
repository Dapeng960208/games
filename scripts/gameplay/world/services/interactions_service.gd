extends RefCounted
## Interactions behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func _update_gold(delta: float) -> void:
	for i in range(host.gold_drops.size() - 1, -1, -1):
		var drop: Dictionary = host.gold_drops[i]
		drop["age"] += delta
		var offset: Vector2 = host.player.position - drop["at"]
		if offset.length() <= Balance.GOLD_PICKUP_RADIUS:
			if Game.add_gold(drop["amount"]):
				if is_instance_valid(host.combat_audio):
					host.combat_audio.pickup()
				host.telemetry["gold_collected"] += drop["amount"]
				host.add_ring(drop["at"], Color("e6aa4a"), 21.0, 0.2)
				host.gold_drops.remove_at(i)
		elif offset.length() <= Balance.GOLD_ATTRACT_RADIUS:
			drop["at"] = drop["at"].move_toward(host.player.position, Balance.GOLD_ATTRACT_SPEED * delta)

func nearby_interaction() -> Dictionary:
	if Game.run == null or host.player == null:
		return {}
	if not host.expedition_context.is_empty() and not Game.pending_field_equipment().is_empty():
		var loot_at = host.loot_position()
		if host.player.position.distance_to(loot_at) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position,loot_at):
			return {"kind":"loot","position":loot_at,"label":"整理战利品" if Words.locale != "en" else "Collect loot"}
	if is_instance_valid(host.b05_mechanics):
		var gate: Dictionary = host.b05_mechanics.nearby_mechanism(host.player.position)
		if not gate.is_empty(): return gate
	if bool(host.layout.get("b06_candidate",false)) and not bool(host.expedition_context.get("b06_progression",false)) and host.objective_complete and host.player.position.distance_to(host.exit_position) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position,host.exit_position):
		return {"kind":"b06_candidate_next","position":host.exit_position,"label":"结束候选预览" if host.layout_id == "BO06" else "前往下一候选房"}
	if is_instance_valid(host.objectives):
		var task: Dictionary = host.objectives.nearby_interaction(host.player.position)
		if not task.is_empty():
			return task
	if not host.expedition_context.is_empty():
		var role: String = str(host.expedition_context.get("role", ""))
		var service_at: Vector2 = host.layout.get("service_position", Vector2(1260,900))
		if role in ["entrance", "supply"] and host.player.position.distance_to(service_at) < 100:
			return {"kind":"relic_choice" if role == "entrance" else "supply", "position":service_at, "label":"选择遗物" if role == "entrance" else "途中补给"}
		if (host.objective_rewarded or role in ["entrance", "supply"]) and host.player.position.distance_to(host.exit_position) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position,host.exit_position):
			var kind: String = "extract" if role == "boss" else ("early_extract" if bool(host.expedition_context.get("early_extraction",false)) else "next")
			return {"kind":kind,"position":host.exit_position,"label":"完成远征 · 撤离" if role == "boss" else "前往下一站"}
		if is_instance_valid(host.enemy_props):
			var supply: Dictionary = host.enemy_props.nearest_interaction(host.player.position)
			if not supply.is_empty() and bool(supply.get("available",false)): return supply
		return {}
	if host.player.position.distance_to(host.exit_position) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position, host.exit_position):
		return {"kind":"extract"}
	for id in host.relic_positions:
		if not Game.run.relics.has(id) and host.player.position.distance_to(host.relic_positions[id]) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position, host.relic_positions[id]):
			return {"kind":"relic","id":id}
	if is_instance_valid(host.enemy_props):
		var prop: Dictionary = host.enemy_props.nearest_interaction(host.player.position)
		if not prop.is_empty() and bool(prop.get("available",false)):
			return prop
	return {}

func interaction_hint() -> String:
	var nearby = host.nearby_interaction()
	if nearby.is_empty():
		return ""
	var key: String = host._interaction_key()
	if nearby.kind in ["objective","b05_gate","b05_sunleaf","next","early_extract","relic_choice","supply","loot","b06_candidate_next"]:
		return "[" + key + "] " + str(nearby.get("label","继续远征"))
	if nearby["kind"] == "extract":
		return tr("INTERACT_EXTRACT").replace("[E]", "["+key+"]")
	if nearby.kind == "buff":
		return "[" + key + "] " + str(nearby.get("name_en" if Words.locale == "en" else "name",""))
	var id: String = nearby["id"]
	return tr("INTERACT_RELIC").format({"name":tr("RELIC_" + id.to_upper() + "_NAME")}).replace("[E]", "["+key+"]")

func _interaction_key() -> String:
	return preload("res://scripts/infrastructure/input/control_bindings.gd").label_for("interact", Game.profile.get("settings", {}).get("controls", {}), Words.locale)

func interact() -> void:
	if not host.controls_enabled():
		return
	var nearby = host.nearby_interaction()
	if nearby.is_empty():
		return
	if nearby.kind == "b05_gate" and is_instance_valid(host.b05_mechanics):
		host.b05_mechanics.interact(str(nearby.id),host.player,"player",func() -> bool: return Game.run != null and Game.run.hp > 0.0,host.has_line_of_sight)
	elif nearby.kind == "b05_sunleaf" and is_instance_valid(host.b05_mechanics):
		host.b05_mechanics.toggle_sunleaf(str(nearby.id),host.player)
	elif nearby.kind == "objective":
		host.objectives.interact(str(nearby.id),host.player)
	elif nearby.kind in ["next","early_extract","relic_choice","supply","loot","b06_candidate_next"]:
		host.set_input_blocked(true)
		host.interaction_requested.emit(str(nearby.kind),host.expedition_context.duplicate(true))
	elif nearby["kind"] == "extract":
		host.set_input_blocked(true)
		host.interaction_requested.emit("extract", {})
	elif nearby.kind == "buff":
		host.enemy_props.interact(str(nearby.id),host.player)
	else:
		var id: String = nearby["id"]
		if Game.equip_relic(id):
			if is_instance_valid(host.combat_audio):
				host.combat_audio.pickup()
			host.add_ring(host.relic_positions[id], Color("67c7d5"), 64.0, 0.65)

func _draw_exit() -> void:
	var at = host.exit_position
	var nearby = host.player != null and host.player.position.distance_to(at) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position, at)
	# RaisedScenery owns the painted portal body. Only its flush interaction
	# guide belongs on the ground canvas, beneath actors and warnings.
	host.draw_arc(at,56.0,0,TAU,40,Color(0.15,0.50,0.51,0.60 if nearby else 0.22),2.0,true)
	host.draw_arc(at,53.0,0,TAU,40,Color("fff3d7"),1.1,true)
	host.draw_polyline(PackedVector2Array([at+Vector2(-10,-3),at+Vector2(0,-13),at+Vector2(10,-3)]),Color("257f83"),3.0,true)
	host.draw_line(at+Vector2(0,-12),at+Vector2(0,14),Color("257f83"),3.0)

func _draw_relic(id: String, at: Vector2) -> void:
	var collected: bool = Game.run == null or Game.run.relics.has(id)
	var nearby: bool = host.player != null and host.player.position.distance_to(at) <= Balance.INTERACTION_RADIUS and host.has_line_of_sight(host.player.position, at)
	host.draw_set_transform(at)
	# Retain pickup affordance without the retired dark industrial plinth.
	host.draw_arc(Vector2(0,8),24,0,TAU,32,Color("c8b478"),1.5,true)
	if collected:
		host.draw_circle(Vector2(0,3),4.0,Color("526d69"))
	else:
		var pulse = 0.75 + 0.15 * sin(host.elapsed * 2.0)
		host.draw_circle(Vector2(0,-3),34.0,Color(0.4,0.78,0.84,0.04*pulse))
		host.draw_circle(Vector2(0,-3),22.0,Color(0.4,0.78,0.84,0.08*pulse))
		if host.relic_textures.has(id):
			host.draw_texture_rect(host.relic_textures[id],Rect2(-25,-30,50,50),false)
		else:
			host._draw_relic_fallback(id)
		if nearby:
			host.draw_arc(Vector2.ZERO,40,0,TAU,32,Color("e6aa4a"),1.5,true)
	host.draw_set_transform(Vector2.ZERO)

func _draw_relic_fallback(id: String) -> void:
	var color = Color("67c7d5")
	match id:
		"split":
			host.draw_polyline(PackedVector2Array([Vector2(-12,4),Vector2(0,-13),Vector2(12,4),Vector2(-12,4)]),color,2.0,true)
			host.draw_line(Vector2(0,16),Vector2(0,2),Color("f1eadc"),2.0)
			host.draw_line(Vector2(0,2),Vector2(-15,-10),color,2.0)
			host.draw_line(Vector2(0,2),Vector2(15,-10),color,2.0)
		"ember":
			host.draw_colored_polygon(PackedVector2Array([Vector2(-10,8),Vector2(-11,-1),Vector2(-4,-8),Vector2(-1,-18),Vector2(6,-6),Vector2(11,0),Vector2(9,8),Vector2(0,12)]),Color("e6aa4a"))
			host.draw_colored_polygon(PackedVector2Array([Vector2(-4,8),Vector2(0,-5),Vector2(5,8)]),Color("f8dfa0"))
		"arc":
			host.draw_arc(Vector2.ZERO,15,-0.5,PI+0.5,24,color,2.0,true)
			host.draw_polyline(PackedVector2Array([Vector2(4,-13),Vector2(-6,1),Vector2(4,1),Vector2(-4,15)]),Color("d6fbff"),3.0,true)
