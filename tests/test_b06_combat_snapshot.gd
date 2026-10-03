extends Node
const Fixture=preload("res://tests/test_b06_enemy_skills.gd")
const Skills=preload("res://scripts/combat/b06_enemy_skills.gd")
const Enemy=preload("res://scripts/combat/enemy.gd")
const Runtime=preload("res://scripts/combat/enemy_skill_runtime.gd")
const Codec=preload("res://scripts/combat/b06_combat_state_codec.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value: failures+=1; push_error("B06 SNAPSHOT "+label)
func arena()->Node2D:
	var value:=Fixture.Arena.new()
	value.visible=false
	value.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(value)
	value.add_child(value.enemies)
	value.add_child(value.victim)
	value.enemy_skills=Runtime.new()
	value.add_child(value.enemy_skills)
	value.enemy_skills.configure(value)
	return value
func _ready()->void: _run.call_deferred()
func _run()->void:
	var a:Node2D=arena()
	var old:Dictionary={"player":a.victim}
	for n in [1,2,4,5,6,12,15,16,18]:
		var actor:=Enemy.new()
		actor.room=a
		actor.configure(Skills.profile("B06-M%02d"%n,30,4),{"reward_enabled":false})
		a.enemies.add_child(actor)
		actor.state=&"execute"
		old["enemy:"+str(n)]=actor
		var c:=Skills.active(actor.profile,Vector2.ZERO,Vector2(100,0),true,true)
		if n==5: c["b06_target_refs"]=a.enemy_skills.b06.support_targets(actor,c)
		actor.cast_enemy_skill(c)
	a.victim.position=Vector2(100,0)
	a.enemy_skills.advance(.2)
	var index:=0
	for actor:Node in a.enemies.get_children():
		if actor.static_actor:
			old["anchor:"+str(index)]=actor
			index+=1
	var old_ids:Dictionary={}
	for id:String in old: old_ids[old[id].get_instance_id()]=id
	var encode:=func(actor:Node2D)->String: return str(old_ids.get(actor.get_instance_id(),""))
	var decode:=func(id:String)->Node2D: return old.get(id)
	a.enemy_skills.b06.summon_attempts[old["enemy:1"].get_instance_id()]=2
	var captured:Dictionary=a.enemy_skills.b06.capture_candidate(encode)
	check(not captured.is_empty(),"capture live jobs/motions/anchors/buffs")
	if captured.is_empty():
		for key:String in a.enemy_skills.b06.SAVE_ARRAYS:
			print("CODEC ",key,"=",Codec.encode(a.enemy_skills.get(key),encode).ok)
			_scan(a.enemy_skills.get(key),encode,key)
		print("CODEC effects=",Codec.encode(a.enemy_skills.b06.effects,encode).ok)
		_scan(a.enemy_skills.b06.effects,encode,"effects")
		print("RECEIPTS ",a.enemy_skills.b06.hit_receipts," IDS ",old_ids)
		get_tree().quit(1)
		return
	var saved:Dictionary=JSON.parse_string(JSON.stringify(captured))
	check(a.enemy_skills.b06.validate_candidate(saved,decode),"JSON snapshot validates")
	if not a.enemy_skills.b06.validate_candidate(saved,decode):
		var unpacked:=Codec.decode(saved,decode)
		print("UNPACK ",unpacked.ok)
		if unpacked.ok:
			for key:String in a.enemy_skills.b06.SAVE_ARRAYS:
				for command:Dictionary in unpacked.value.arrays[key]:
					if not a.enemy_skills.b06._saved_command_valid(command): print("BAD COMMAND ",key," ",command)
			for effect:Dictionary in unpacked.value.effects:
				if not a.enemy_skills.b06._saved_command_valid(effect): print("BAD EFFECT ",effect)
			print("SAVE META ",saved.clock," ",saved.serial," ",saved.hazard_serial," RECEIPTS ",saved.receipts)
		get_tree().quit(1)
		return
	check(not saved.effects.is_empty() and not saved.arrays.jobs.is_empty() and not saved.arrays.motions.is_empty(),"snapshot genuinely midcombat")
	var b:Node2D=arena()
	var fresh:Dictionary={"player":b.victim}
	for id:String in old:
		if id=="player": continue
		var source:Node2D=old[id]
		var actor:=Enemy.new()
		actor.room=b
		actor.configure(source.profile,{"reward_enabled":false,"static_actor":source.static_actor,"actor_kind":source.actor_kind})
		b.enemies.add_child(actor)
		actor.position=source.position
		actor.state=source.state
		actor.aim_direction=source.aim_direction
		actor.health.reset(float(source.health.maximum),2)
		actor.health.current=source.health.current
		actor.status.guards=source.status.guards.duplicate(true)
		actor.status.total_absorbed=source.status.total_absorbed
		fresh[id]=actor
	for id:String in old:
		if id=="player": continue
		var source:Node2D=old[id]
		if source.owner_enemy!=null:
			var owner:Node2D=source.owner_enemy.get_ref()
			if is_instance_valid(owner): fresh[id].owner_enemy=weakref(fresh[old_ids[owner.get_instance_id()]])
	b.victim.position=a.victim.position
	var decode_fresh:=func(id:String)->Node2D:return fresh.get(id)
	check(b.enemy_skills.b06.restore_candidate(saved,decode_fresh),"restore all actorreferences into new instances")
	check(b.enemy_skills.motions[0].owner_id!=a.enemy_skills.motions[0].owner_id,"owner IDs genuinely rebased")
	check(b.enemy_skills.b06.summon_attempts.get(fresh["enemy:1"].get_instance_id())==2,"finite summon attempts survive restore")
	check(b.enemy_skills._owner(b.enemy_skills.motions[0]).has_meta("enemy_skill_motion"),"motion marker restored")
	var bad:Dictionary=saved.duplicate(true)
	bad.serial=-1
	var before:float=b.enemy_skills.b06.clock
	check(not b.enemy_skills.b06.restore_candidate(bad,decode_fresh) and b.enemy_skills.b06.clock==before,"invalid metadata rejected atomically")
	bad=saved.duplicate(true)
	bad.effects[0].remaining=999
	check(not b.enemy_skills.b06.restore_candidate(bad,decode_fresh),"invalid effect lifetime rejected")
	bad=saved.duplicate(true)
	bad.arrays.jobs[0].damage=int(bad.arrays.jobs[0].damage)+1
	check(not b.enemy_skills.b06.restore_candidate(bad,decode_fresh),"forged damage rejected against profile")
	check(not b.enemy_skills.b06.restore_candidate(saved,func(_id:String)->Node2D:return null),"missing binding fails closed")
	a.victim.hits.clear()
	b.victim.hits.clear()
	a.victim.states.clear()
	b.victim.states.clear()
	for step in 240:
		a.enemy_skills.advance(1.0/60)
		b.enemy_skills.advance(1.0/60)
	check(a.victim.hits==b.victim.hits,"resumed actual damage sequence identical")
	check(a.victim.states==b.victim.states,"resumed statuses identical")
	check(a.enemy_skills.jobs.size()==b.enemy_skills.jobs.size() and a.enemy_skills.b06.effects.size()==b.enemy_skills.b06.effects.size(),"resumed finite lifecycle identical")
	for id:String in ["enemy:1","enemy:4"]: check(old[id].position.is_equal_approx(fresh[id].position),"motion replay position "+id)
	# The brain retains the exact locked warning; no fresh release on restore.
	var original:Node2D=old["enemy:1"]
	var restored:Node2D=fresh["enemy:1"]
	original.position=Vector2.ZERO
	a.victim.position=Vector2(100,0)
	original.brain.configure(original.profile)
	original.brain.tick(original,.8,a.victim)
	original.brain.tick(original,1,a.victim)
	var brain_save:Dictionary=JSON.parse_string(JSON.stringify(original.brain.capture_candidate(encode)))
	check(restored.brain.restore_candidate(brain_save,decode_fresh),"locked brain JSON restore")
	check(restored.brain.phase==original.brain.phase and restored.brain.current_telegraph().direction==original.brain.current_telegraph().direction,"locked geometry/state retained")
	brain_save.cooldown=999
	check(not restored.brain.restore_candidate(brain_save,decode_fresh),"brain rejects forged cooldown")
	check(not Codec.encode(self,encode).ok,"codec rejects arbitrary engineObject")
	check(not Codec.decode({"$b06":"callable","path":"res://anything"},decode).ok,"codec rejects executable tag")
	a.enemy_skills.reset_room()
	b.enemy_skills.reset_room()
	a.free()
	b.free()
	print("B06_COMBAT_SNAPSHOT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func _scan(value:Variant,resolver:Callable,path:String)->void:
	if Codec.encode(value,resolver).ok:return
	if value is Dictionary:
		for key:Variant in value:
			if not key is String: print("BAD KEY ",path, " ", key," TYPE ",typeof(key))
			if key=="owner_id" or key=="hit_ids":continue
			_scan(value[key],resolver,path+":"+str(key))
	elif value is Array:
		for i in value.size():_scan(value[i],resolver,path+":"+str(i))
	else:print("BAD LEAF ",path," TYPE ",typeof(value)," VALUE ",value)
