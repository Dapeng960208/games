extends Node
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
const Brain = preload("res://scripts/levels/b09/combat/brain.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const FIELDS := ["max_hp","damage","armor","magic_resist"]
# Independently resolved archive14 points: each role at Lv41/43/45, D0 then D4.
const STATS := {
	"F":[[10897,907,615,540],[43589,2085,735,660],[11272,929,630,555],[45088,2137,750,675],[11646,952,645,570],[46586,2190,765,690]],
	"R":[[8637,993,570,525],[34546,2284,690,645],[8933,1018,585,540],[35734,2341,705,660],[9230,1043,600,555],[36921,2398,720,675]],
	"C":[[6335,1063,480,690],[25341,2445,600,810],[6553,1090,495,705],[26212,2507,615,825],[6771,1116,510,720],[27083,2568,630,840]],
	"S":[[8718,658,561,668],[34871,1512,693,800],[9018,674,578,685],[36070,1550,710,817],[9317,690,594,701],[37269,1588,726,833]],
	"A":[[4389,1192,446,488],[17558,2741,566,608],[4540,1221,461,503],[18161,2809,581,623],[4691,1251,476,518],[18765,2878,596,638]],
	"T":[[14302,658,897,604],[57208,1512,1035,742],[14794,674,914,621],[59175,1550,1052,759],[15285,690,932,638],[61142,1588,1070,776]]
}
const ROLES := ["F","C","R","A","T","S","F","S","A","R","R","C","T","S","C","R","F","C"]
const LAYERS := [2,0,0,0,3,0,1,0,0,0,1,0,3,0,0,0,2,2]
const CDS := [7,8,7,7,10,12,8,13,9,9,9,11,12,14,11,10,10,13]
const TELLS := [1.0,1.1,1.0,0.9,1.1,1.2,1.0,1.3,1.1,1.0,1.0,1.3,1.3,1.4,1.2,1.3,1.2,1.4]
var checks := 0
var failures := 0
var room: Node2D
var route: RefCounted

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("B09_MONSTER: "+label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not Game.profile_path.contains("test_b09_candidate"):
		push_error("B09 monster contract requires an isolated test_b09_candidate profile")
		get_tree().quit(2)
		return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated fixture starts")
	Game.profile_path="user://test_b09_candidate/monster_contract.json"
	_profile_contract()
	_skill_contract()
	_boss_contract()
	room=load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	for actor in room.enemies.get_children(): actor.free()
	route=Traversal.new()
	check(route.configure(room,4,909) and route.start(),"runtime fixture enters B09")
	room.release_gate=false
	room.input_blocked=false
	room.player.invulnerable=9999.0
	_frozen_release()
	_interrupt_contract()
	_bridge_wave_contract()
	_refraction_contract()
	_support_contract()
	_guard_contract()
	check(await room.combat_audio.wait_for_cleanup(),"combat audio cleanup")
	room.free()
	Game.run=null
	print("B09_MONSTER_CONTRACT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func _profile_contract() -> void:
	check(Content.data().enemy_ids.size()==18,"18 identities")
	for index in 18:
		var id := "B09-M%02d" % (index+1)
		var authored := Content.enemy(id)
		check(authored.profile==ROLES[index] and int(authored.crystal_layers)==LAYERS[index],id+" authored role/layers")
		check(int(authored.first_level)==41+2*(index/6),id+" first appearance")
		for level_index in 3:
			var level: int=[41,43,45][level_index]
			for difficulty_index in 2:
				var difficulty: int=[0,4][difficulty_index]
				var profile := Skills.profile(id,level,difficulty)
				var expected: Array=STATS[authored.profile][level_index*2+difficulty_index]
				var actual: Array=[]
				for field: String in FIELDS: actual.append(profile[field])
				check(actual==expected,id+" Lv"+str(level)+" D"+str(difficulty)+" exact HP/A/AR/MR "+str(actual))
				check(profile.enemy_level==level and profile.difficulty==difficulty and profile.enemy_growth_version==3,id+" fixed growth provenance")
		check(Skills.profile(id,40,0).is_empty() and Skills.profile(id,41,5).is_empty() and Skills.profile(id,41,0,"boss").is_empty(),id+" rejects invalid admission")
	print("B09_MONSTER_STAT_POINTS ",JSON.stringify(STATS))

func _skill_contract() -> void:
	for index in 18:
		var id := "B09-M%02d" % (index+1)
		for difficulty in 5:
			var profile := Skills.profile(id,int(Content.enemy(id).first_level),difficulty)
			var active := Skills.active(profile,Vector2(400,400),Vector2(500,400))
			var frozen := Skills.freeze(active,profile)
			check(float(active.cooldown)==float(CDS[index]),id+" D"+str(difficulty)+" authored cooldown")
			check(float(active.timing.authored_tell_seconds)==float(TELLS[index]),id+" authored warning")
			_check_packet(frozen,profile,id+" D"+str(difficulty))
			var changed := profile.duplicate(true)
			changed.damage=int(profile.damage)*100
			check(Skills.freeze(frozen,changed)==frozen,id+" repeated preparation preserves complete frozen packet")
			if index in [5,7,13]:
				check(float(active.tell)+float(active.lock)>=float(TELLS[index])-0.001,id+" interruptible channel retains duration")
	var d0 := Skills.profile("B09-M10",43,0)
	var bomb := Skills.active(d0,Vector2(400,400),Vector2(500,400))
	check(float(bomb.delay)==1.0 and float(bomb.radius)==90.0,"M10 one-second landing fuse")
	var charge := Skills.active(Skills.profile("B09-M09",43,4),Vector2(400,400),Vector2(500,400))
	check(charge.followups[0].kind=="charge" and charge.followups[0].coefficient==50 and charge.b09_stop_on_snow and charge.followups[0].b09_stop_on_snow,"M09 both declared 0.5a stages obey rough snow")
	var wall := Skills.active(Skills.profile("B09-M12",43,4),Vector2(400,400),Vector2(500,400))
	check(float(wall.gap)==100.0 and float(wall.width)==120.0 and wall.shatter.coefficient==40,"M12 D4 100px gap and single 0.4a shatter definition")
	var ring := Skills.active(Skills.profile("B09-M15",45,4),Vector2(400,400),Vector2(500,400))
	check(ring.followups[0].ring_gap_degrees==70.0 and ring.followups[0].ring_gap_angle==0.0,"M15 safe sector frozen at warning")

func _check_packet(packet: Dictionary, profile: Dictionary, label: String) -> void:
	var boss: bool=profile.rank=="boss"
	var factor: float=([1.0,1.06,1.12,1.2,1.3][int(profile.difficulty)]*[1.0,1.1,1.2][int(packet.get("b09_phase",1))-1]) if boss else (1.25*[1.0,1.05,1.1,1.15,1.2][int(profile.difficulty)])
	var expected := int(floor(float(profile.damage)*float(packet.coefficient)/100.0*factor+0.5))
	check(bool(packet.get("b09_frozen",false)) and int(packet.damage)==expected,label+" integer command damage")
	for child: Dictionary in packet.get("followups",[]): _check_packet(child,profile,label+" stage "+str(child.stage))
	if packet.has("shatter"): _check_packet(packet.shatter,profile,label+" shatter")

func _boss_contract() -> void:
	for difficulty in 5:
		var profile := Skills.boss_profile(difficulty)
		var brain := Brain.new()
		brain.configure(profile)
		check(brain._phase_for_ratio(0.70001)==1 and brain._phase_for_ratio(0.7)==2 and brain._phase_for_ratio(0.35001)==2 and brain._phase_for_ratio(0.35)==3,"Queen inclusive 70%/35% thresholds D"+str(difficulty))
		for phase in range(1,4):
			var actions := brain.available_actions(phase)
			check(("prism_ray" in actions)==(difficulty>=1),"Queen D1 ray")
			check(("bridge_decree" in actions)==(difficulty>=2 and phase>=2),"Queen D2 P2 bridge")
			check(("crown_guards" in actions)==(difficulty>=3 and phase>=2),"Queen D3 P2 guards")
			check(("mirror_verdict" in actions)==(difficulty>=4 and phase>=3),"Queen D4 P3 mirrors")
			for action: String in actions:
				var command := Skills.freeze(Skills.boss_action(profile,action,Vector2(400,400),Vector2(500,400),phase),profile)
				_check_packet(command,profile,"Queen "+action+" D"+str(difficulty)+" P"+str(phase))
				if action=="reform": check(command.tell+command.lock>=1.5,"Queen 1.5s interruptible reform")

func _reset(difficulty: int = 4) -> void:
	room.enemy_skills.reset_room()
	for enemy in room.enemies.get_children(): enemy.free()
	room.b09_mechanics.walls.clear()
	room.b09_mechanics.bridge.clear()
	room.difficulty=difficulty
	room.player.position=Vector2(700,500)

func _spawn(id: String, at: Vector2) -> Node2D:
	return room.spawn_enemy(at,id,int(Content.enemy(id).first_level),{"profile":Skills.profile(id,int(Content.enemy(id).first_level),room.difficulty)})

func _frozen_release() -> void:
	_reset()
	var actor := _spawn("B09-M03",Vector2(500,500))
	actor.brain._begin_action(actor,room.player)
	var warning: Dictionary=actor.brain.command.duplicate(true)
	check(warning.has("damage") and warning.b09_frozen,"real warning carries frozen damage")
	actor.profile.damage=int(actor.profile.damage)*10
	room.player.position=Vector2(650,620)
	actor.brain.tick(actor,float(warning.tell)+0.01,room.player)
	actor.brain.tick(actor,float(warning.lock)+0.01,room.player)
	check(room.enemy_skills.projectiles.size()==1,"real brain releases primary projectile")
	if not room.enemy_skills.projectiles.is_empty():
		var shot: Dictionary=room.enemy_skills.projectiles[0]
		check(shot.damage==warning.damage and shot.origin==warning.origin and shot.target==warning.target and shot.direction==warning.direction,"released damage and path equal warning despite later profile/target changes")
	check(room.enemy_skills.jobs.size()==1 and room.enemy_skills.jobs[0].damage==warning.followups[0].damage,"delayed side shards retain warning damage")
	check(is_equal_approx(actor.brain._ordinary_ready,actor.brain.elapsed+7.0),"active CD starts at release")

func _interrupt_contract() -> void:
	for id: String in ["B09-M06","B09-M08","B09-M14"]:
		_reset()
		room.b09_mechanics.definition.bridges=Content.room("L53").bridges.duplicate(true)
		var actor := _spawn(id,Vector2(500,500))
		if id=="B09-M08":
			var ally := _spawn("B09-M01",Vector2(560,550))
			ally.set_meta("b09_layers",0)
		actor.brain._begin_action(actor,room.player)
		check(actor.brain.command.get("interruptible",false),id+" actual active channel")
		actor.brain.on_damaged(actor,{"dot":true})
		check(actor.brain.state==&"telegraph",id+" DOT does not interrupt")
		var cooldown: float=actor.brain.command.cooldown
		actor.brain.on_damaged(actor,{"dot":false})
		check(actor.brain.state==&"recovery" and actor.brain.command.is_empty(),id+" direct hit cancels release")
		check(is_equal_approx(actor.brain._ordinary_ready,actor.brain.elapsed+cooldown*0.5),id+" interrupted half cooldown")
		check(room.enemy_skills.jobs.is_empty() and room.enemy_skills.projectiles.is_empty() and room.b09_mechanics.bridge.is_empty(),id+" no post-interrupt effects")

func _refraction_contract() -> void:
	for difficulty in [0,4]:
		_reset(difficulty)
		room.player.position=Vector2(600,500)
		var first := _spawn("B09-M16",Vector2(400,400))
		var second := _spawn("B09-M16",Vector2(400,650))
		for actor: Node2D in [first,second]:
			actor.brain._begin_action(actor,room.player)
			var command: Dictionary=actor.brain.command
			check(command.has("b09_refraction_anchor"),"M16 actual destructible refraction column D"+str(difficulty))
			if command.has("b09_refraction_anchor"):
				var column: Node2D=command.b09_refraction_anchor.get_ref()
				check(absf(column.health.maximum-actor.health.maximum*0.15)<=1.0,"M16 column has 15% actor HP")
			actor.state=&"execute"
			room.enemy_skills.emit_skill(actor,command)
		check(room.enemy_skills.projectiles.size()==(1 if difficulty==4 else 2),"M16 D4 only global single active line; D0 independent lines")
		if not second.brain.command.has("b09_refraction_anchor"): continue
		var column: Node2D=second.brain.command.b09_refraction_anchor.get_ref()
		column.take_damage(10000000,&"primary",Vector2.RIGHT,{"damage_type":"true"})
		room.enemy_skills.advance(0.01)
		check(room.enemy_skills.projectiles.size()==(0 if difficulty==4 else 1),"destroyed M16 column cancels its in-flight line")
		room.enemy_skills.advance(1.01)
		var second_pending := 0
		for job: Dictionary in room.enemy_skills.jobs:
			if int(job.owner_id)==second.get_instance_id(): second_pending+=1
		check(second_pending==0,"destroyed M16 column cancels delayed explosion")

func _bridge_wave_contract() -> void:
	for side in [-1,0,1]:
		_reset()
		var map: Node2D=room.b09_mechanics
		map.definition.bridges=Content.room("L53").bridges.duplicate(true)
		map._bridge_cursor=0
		var box := Content.rect(map.definition.bridges[0].rect)
		room.player.position=box.get_center()+Vector2(side*(box.size.x*0.5+40),0)
		room.player.invulnerable=0.0
		Game.run.hp=Game.run.max_hp
		var before: float=Game.run.hp
		var actor := _spawn("B09-M14",box.get_center()+Vector2(100,100))
		actor.brain._begin_action(actor,room.player)
		var warning: Dictionary=actor.brain.command.duplicate(true)
		check(warning.get("kind")=="b09_bridge" and warning.followups.size()==2,"M14 actual bridge admission declares two end waves")
		for wave: Dictionary in warning.followups:
			check(not wave.has("targets") and wave.target.distance_to(box.get_center())>float(wave.radius),"bridge end wave does not inherit root center targets")
		actor.brain.tick(actor,float(warning.tell)+0.01,room.player)
		actor.brain.tick(actor,float(warning.lock)+0.01,room.player)
		check((Game.run.hp<before)==(side!=0),"M14 actual damage at bridge end "+str(side)+"; center remains safe from end waves")
		check(map.bridge.get("state")=="warning" and map.bridge.remaining==2.0,"M14 release starts independent two-second bridge warning")
	room.player.invulnerable=9999.0

func _support_contract() -> void:
	_reset()
	var singer := _spawn("B09-M08",Vector2(500,500))
	var allies: Array=[]
	for offset in [Vector2(50,0),Vector2(80,0),Vector2(120,0)]:
		var ally := _spawn("B09-M01",singer.position+offset)
		ally.set_meta("b09_layers",2)
		allies.append(ally)
	singer.set_meta("b09_layers",2)
	singer.state=&"execute"
	room.enemy_skills.emit_skill(singer,Skills.active(singer.profile,singer.position,room.player.position))
	check(allies[0].get_meta("b09_layers")==3 and allies[1].get_meta("b09_layers")==3 and allies[2].get_meta("b09_layers")==2,"M08 reform capped at nearest two allies, three layers")
	check(singer.get_meta("b09_layers")==0,"M08 D4 own layers exposed")
	room.b09_mechanics.tick(1.99)
	check(singer.get_meta("b09_layers")==0,"M08 exposure not restored early")
	room.b09_mechanics.tick(0.02)
	check(singer.get_meta("b09_layers")==2,"M08 layers restore after two seconds")

func _guard_contract() -> void:
	_reset()
	check(route._install(6),"Queen runtime installed")
	for enemy in room.enemies.get_children():
		if enemy!=room._boss_actor: enemy.free()
	var queen: Node2D=room._boss_actor
	queen.health.current=floor(float(queen.health.maximum)*0.7)
	queen.brain.tick(queen,0.01,room.player)
	check(queen.brain.phase==2 and queen.state==&"phase_shift","real Queen enters P2 at 70%")
	queen.health.current=floor(float(queen.health.maximum)*0.35)
	queen.brain.tick(queen,0.01,room.player)
	check(queen.brain.phase==3 and queen.state==&"phase_shift","real Queen enters P3 at 35%")
	queen.state=&"execute"
	var profile := Skills.profile("B09-M01",45,4)
	for round_index in 3:
		var command := Skills.boss_action(queen.profile,"crown_guards",queen.position,room.player.position,2)
		command["cast_id"]="guard_round:"+str(round_index)
		room.enemy_skills.emit_skill(queen,command)
		var guards: Array=[]
		for enemy: Node2D in room.enemies.get_children():
			if enemy!=queen and enemy.actor_kind=="enemy": guards.append(enemy)
		check(guards.size()==(2 if round_index<2 else 0),"Queen at most two guard rounds "+str(round_index))
		for guard: Node2D in guards:
			check(guard.health.maximum==int(profile.max_hp*0.5) and not guard.reward_enabled and bool(guard.get_meta("b09_no_support",false)),"Queen guard 50% HP, no rewards/support")
			check(guard.owner_enemy!=null and guard.owner_enemy.get_ref()==queen,"Queen guard unique owner")
		if not guards.is_empty():
			var singer := _spawn("B09-M08",queen.position+Vector2(30,0))
			queen.set_meta("b09_layers",0)
			for guard: Node2D in guards: guard.set_meta("b09_layers",0)
			check(room.b09_mechanics.allies(singer).is_empty(),"ordinary support excludes Queen and owned guards")
			singer.free()
		room.enemy_skills.emit_skill(queen,command)
		check(queen.brain._owned_add_count(queen)==guards.size(),"repeat guard release cannot exceed concurrent two")
		for guard: Node2D in guards: guard.free()
