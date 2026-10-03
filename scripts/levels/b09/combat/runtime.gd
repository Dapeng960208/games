extends RefCounted
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
var host: Node2D
func configure(value: Node2D) -> void: host=value

func prepare(caster: Node2D, c: Dictionary) -> Dictionary:
	return Skills.freeze(c,caster.profile)

func execute(c: Dictionary) -> bool:
	var actor: Node2D=host._owner(c)
	if not host._alive(actor) or not is_instance_valid(host.room.b09_mechanics): return true
	var map: Node2D=host.room.b09_mechanics
	if bool(c.get("b09_origin_matches",false)) and actor.position.distance_to(Vector2(c.origin))>4: return true
	if c.has("b09_refraction_anchor") and not host._alive(c.b09_refraction_anchor.get_ref()): return true
	if actor.enemy_id=="B09-M16" and c.kind=="projectile" and int(c.difficulty)>=4:
		for shot: Dictionary in host.projectiles.duplicate():
			if shot.get("caster_enemy_id")=="B09-M16": host.projectiles.erase(shot)
	match str(c.kind):
		"b09_reform": actor.set_meta("b09_layers",mini(3,int(actor.get_meta("b09_layers",0))+1))
		"b09_reform_allies":
			for ally: Node2D in map.allies(actor).slice(0,int(c.get("max_targets",2))): ally.set_meta("b09_layers",mini(3,int(ally.get_meta("b09_layers",0))+1))
			if host.room.difficulty>=4 and actor.enemy_id=="B09-M08": map.expose(actor,2.0,true)
		"b09_siphon":
			var nearest: Dictionary={}
			for lamp: Dictionary in map.lamps.values():
				if nearest.is_empty() or actor.position.distance_squared_to(lamp.at)<actor.position.distance_squared_to(nearest.at): nearest=lamp
			if not nearest.is_empty(): nearest.siphon_until=map.clock+4.0
			if host.room.difficulty>=2: actor.set_meta("b09_layers",mini(3,int(actor.get_meta("b09_layers",0))+1))
		"b09_bridge": map.request_bridge(str(c.get("b09_bridge_id","")),0.0 if actor.actor_kind=="boss" else 2.0)
		"b09_snow": map.snow.append({"at":c.target,"radius":float(c.radius),"until":map.clock+float(c.duration)})
		"b09_ice": map.ice.append({"rect":Rect2(Vector2(c.target)-Vector2(c.ice_size)*0.5,c.ice_size),"until":map.clock+float(c.duration)})
		"b09_summon":
			var rounds := int(actor.get_meta("b09_guard_rounds",0))
			var casts: Array=actor.get_meta("b09_guard_casts",[])
			var cast_id := str(c.get("cast_id",""))
			var owned := 0
			for enemy: Node2D in host.room.enemies.get_children():
				if host._alive(enemy) and enemy.owner_enemy!=null and enemy.owner_enemy.get_ref()==actor: owned+=1
			if rounds>=2 or owned>=2 or (not cast_id.is_empty() and cast_id in casts): return true
			var admitted := 0
			for side in [-1,1]:
				if owned+admitted>=2: break
				var p := Skills.profile("B09-M01",45,host.room.difficulty)
				p.max_hp=int(p.max_hp*0.5)
				var add: Node2D=host.room.spawn_enemy(actor.position+Vector2(side*100,80),"B09-M01",45,{"owner":actor,"profile":p,"reward_enabled":false,"zone_index":-1})
				if is_instance_valid(add):
					add.set_meta("b09_no_support",true)
					admitted+=1
			if admitted>0:
				actor.set_meta("b09_guard_rounds",rounds+1)
				if not cast_id.is_empty(): casts.append(cast_id)
				actor.set_meta("b09_guard_casts",casts)
		"b09_wall", "b09_shield":
			var at: Vector2=c.target if c.kind=="b09_wall" else actor.position+Vector2(c.direction)*65
			var strike := c.duplicate(true)
			strike.kind="melee" if c.kind=="b09_shield" else "ground_area"
			strike.shape="cone" if c.kind=="b09_shield" else "circle"
			strike.radius=60.0
			strike.duration=0.0
			strike["b09_custom_done"]=true
			host._execute(strike)
			var placement_safe := at.distance_to(host.room.exit_position)>=160
			for lamp: Dictionary in map.lamps.values(): placement_safe=placement_safe and at.distance_to(lamp.at)>=160
			var boxes: Array[Rect2]=[Rect2(at-Vector2(60,10),Vector2(120,20))]
			if float(c.get("gap",0))>0: boxes=[Rect2(at-Vector2(60,10),Vector2(10,20)),Rect2(at+Vector2(50,-10),Vector2(10,20))]
			var shatter_assigned := false
			for box: Rect2 in boxes:
				if not placement_safe or box.grow(Balance.PLAYER_RADIUS).has_point(host.room.player.position) or not host.room.valid_ground(box.get_center(),10): continue
				var anchor: Node2D=host.room.spawn_enemy_skill_anchor(actor,box.get_center(),actor.health.maximum*(0.2 if c.kind=="b09_wall" else 0.15),"crystal_wall")
				if is_instance_valid(anchor):
					if c.kind=="b09_shield": anchor.set_meta("b09_enemy_shield",true)
					var wall := {"rect":box,"actor":weakref(anchor),"until":map.clock+float(c.duration)}
					if c.has("shatter") and not shatter_assigned:
						wall["shatter"]=c.shatter
						wall["owner"]=weakref(actor)
						shatter_assigned=true
					map.walls.append(wall)
		_: return false
	released(c)
	return true

func released(c: Dictionary) -> void:
	if bool(c.get("b09_custom_done",false)): return
	var actor: Node2D=host._owner(c)
	if not host._alive(actor): return
	if host.room.difficulty>=4 and int(c.get("stage",0))==1 and actor.enemy_id in ["B09-M11","B09-M18"]: host.room.b09_mechanics.expose(actor,2.0)
	for index in c.get("followups",[]).size():
		var next: Dictionary=c.followups[index].duplicate(true)
		if c.has("b09_refraction_anchor"): next["b09_refraction_anchor"]=c.b09_refraction_anchor
		next["cast_id"]=str(c.get("cast_id",""))+":"+str(index)
		host.emit_skill(actor,next)

func motion_finished(c: Dictionary, complete: bool) -> void:
	var actor: Node2D=host._owner(c)
	if not host._alive(actor): return
	if not complete or (bool(c.get("b09_stop_on_snow",false)) and not host.room.b09_mechanics.is_ice(actor.position)):
		if actor.enemy_id in ["B09-M04","B09-M09"]:
			for job: Dictionary in host.jobs.duplicate():
				if int(job.get("owner_id",0))==actor.get_instance_id(): host.jobs.erase(job)
			if actor.enemy_id=="B09-M04" and host.room.difficulty>=4:
				actor.brain.state=&"recovery"
				actor.brain.state_time=1.3
				actor.brain.state_duration=1.3
