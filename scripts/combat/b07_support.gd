extends RefCounted
## Candidate-local support contract. Recipient identities are chosen once when
## channeling starts, never silently substituted after the player turns a mirror.
const Props = preload("res://scripts/combat/combat_properties.gd")
const Rules = preload("res://config/numerical_rules.gd")

static func eligible(caster: Node2D, ally: Node2D, command: Dictionary) -> bool:
	if not is_instance_valid(ally) or ally==caster or ally.is_queued_for_deletion(): return false
	if not ally.has_method("is_alive") or not ally.is_alive(): return false
	if str(Props.read(ally,"actor_kind","enemy"))!="enemy" or str(Props.read(ally,"rank","normal"))=="boss" or ally.has_meta("enemy_skill_anchor"): return false
	var id := str(Props.read(ally,"enemy_id",""))
	if not id.begins_with("B07-M") or id=="B07-M05": return false
	var room: Variant=Props.read(caster,"room")
	var light: Variant=Props.read(room,"b07_mechanics")
	if not light is Object or not light.has_method("is_lit") or not light.is_lit(ally): return false
	if caster.position.distance_to(ally.position)>float(command.get("range",200)): return false
	return room is Object and room.has_method("has_line_of_sight") and room.has_line_of_sight(caster.position,ally.position)

static func select(caster: Node2D, command: Dictionary) -> Array:
	var candidates: Array[Node2D]=[]
	var container: Variant=Props.read(Props.read(caster,"room"),"enemies")
	if not container is Node: return []
	for node: Node in container.get_children():
		if not node is Node2D or not eligible(caster,node,command): continue
		var hp: Variant=Props.read(node,"health")
		if hp is Object and float(hp.current)<float(hp.maximum): candidates.append(node)
	candidates.sort_custom(func(a: Node2D,b: Node2D) -> bool:
		var ad:=caster.position.distance_squared_to(a.position)
		var bd:=caster.position.distance_squared_to(b.position)
		return a.get_instance_id()<b.get_instance_id() if is_equal_approx(ad,bd) else ad<bd)
	var refs: Array=[]
	for ally: Node2D in candidates:
		if refs.size()>=int(command.get("target_count",1)): break
		if not refs.is_empty() and not Props.read(caster,"room").has_line_of_sight(refs[-1].get_ref().position,ally.position): continue
		refs.append(weakref(ally))
	return refs

static func valid(caster: Node2D, command: Dictionary) -> bool:
	var refs: Array=command.get("b07_target_refs",[])
	if refs.is_empty(): return false
	var previous:=caster.position
	for ref: WeakRef in refs:
		var ally: Node2D=ref.get_ref()
		if not eligible(caster,ally,command) or not Props.read(caster,"room").has_line_of_sight(previous,ally.position): return false
		previous=ally.position
	return true

static func link(caster: Node2D, command: Dictionary) -> Dictionary:
	var result:=command.duplicate(true)
	if not result.has("b07_target_refs"): result["b07_target_refs"]=select(caster,result)
	var points: Array=[caster.position]
	for ref: WeakRef in result.b07_target_refs:
		var ally: Node2D=ref.get_ref()
		if is_instance_valid(ally): points.append(ally.position)
	result["points"]=points
	result["paths"]=[points] if points.size()>1 else []
	if points.size()>1:
		result["target"]=points[-1]
		result["direction"]=caster.position.direction_to(points[1])
	return result

static func execute(host: Node2D, caster: Node2D, command: Dictionary) -> void:
	# Loss of any link cancels this single channel; never heal a new candidate.
	if not valid(caster,command): return
	for ref: WeakRef in command.b07_target_refs:
		var ally: Node2D=ref.get_ref()
		var hp: Variant=Props.read(ally,"health")
		if not hp is Object or not ally.has_method("heal"): continue
		var actual: float=ally.heal(Rules.integer(float(hp.maximum)*float(command.heal_ratio)))
		_feedback(host.room,ally,actual,&"heal")
		var status: Variant=Props.read(ally,"status")
		if float(command.get("shield_ratio",0))>0 and status is Object:
			var before: float=status.shield()
			status.grant_guard(Rules.integer(float(hp.maximum)*float(command.shield_ratio)),float(command.shield_duration),"b07_turquoise",float(hp.maximum))
			_feedback(host.room,ally,maxf(0,float(status.shield())-before),&"guard")
		var flash:=command.duplicate(true)
		flash.merge({"kind":"utility","shape":"circle","origin":ally.position,"target":ally.position,"radius":24.0,"points":[],"paths":[]},true)
		host._flash(flash,Color("66d3b0"))

static func _feedback(room: Node2D, ally: Node2D, amount: float, kind: StringName) -> void:
	if amount>0 and room.has_method("add_damage_text"):
		room.add_damage_text(ally.position+Vector2(0,-75),amount,kind,{"feedback_kind":str(kind)})
