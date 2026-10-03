extends SceneTree
## Pure command/FSM/adapter contract check. No production room, save, GPU,
## art approval or natural-balance claim is implied by this directed suite.
const Skills = preload("res://scripts/levels/b07/combat/enemy_skills.gd")
const Brain = preload("res://scripts/levels/b07/combat/enemy_brain.gd")
const Boss = preload("res://scripts/levels/b07/combat/boss_brain.gd")
const Adapter = preload("res://scripts/levels/b07/combat/enemy_runtime.gd")
class Mechanism extends RefCounted:
	var lit := true
	var mirror_state := 1
	var area_clear := true
	var revealed := false
	func is_lit(_actor: Node2D) -> bool: return lit
	func is_revealed(_actor: Node2D) -> bool: return revealed
	func reveal_actor(_actor: Node2D, _seconds: float) -> void: revealed=true
	func enemy_attack_lines(_actor: Node2D, maximum: int) -> Array:
		var lines: Array=[{"origin":Vector2(140,-80),"target":Vector2(140,160),"mirror_id":"fixed_east","mirror_state":mirror_state},
			{"origin":Vector2(240,-80),"target":Vector2(240,160),"mirror_id":"fixed_west","mirror_state":mirror_state}]
		return lines.slice(0,maximum)
	func enemy_line_valid(command: Dictionary) -> bool: return int(command.get("mirror_state",-1))==mirror_state
	func admit_persistent_area(_at: Vector2, _radius: float) -> bool: return area_clear
class Arena extends Node2D:
	var b07_mechanics := Mechanism.new()
	var player: Node2D
	var obstruction := 1.0
	var run_seed := 707
	func blocked_fraction(_start: Vector2, _end: Vector2, _radius: float) -> float: return obstruction
	func has_line_of_sight(_start: Vector2, _end: Vector2) -> bool: return true
	func navigation_direction(start: Vector2, target: Vector2, _radius: float) -> Vector2: return start.direction_to(target)
	func move_actor(start: Vector2, displacement: Vector2, _radius: float) -> Vector2: return start+displacement*obstruction
class Health extends RefCounted:
	var maximum := 1000.0
	var current := 1000.0
class Actor extends Node2D:
	var room: Node2D
	var profile: Dictionary={}
	var state: StringName=&"chase"
	var state_time := 0.0
	var aim_direction := Vector2.RIGHT
	var velocity := Vector2.ZERO
	var navigation_radius := 18.0
	var brain: RefCounted
	var health := Health.new()
	var casts: Array=[]
	func is_alive() -> bool: return true
	func cast_enemy_skill(command: Dictionary) -> void: casts.append(command.duplicate(true))
	func boss_phase_started(_phase: int, _ratio: float) -> void: pass
class Host extends Node2D:
	const MAX_EFFECTS := 128
	var room: Node2D
	var jobs: Array[Dictionary]=[]
	var executed: Array=[]
	var motions: Array[Dictionary]=[]
	func _owner(command: Dictionary) -> Node2D: return command.owner.get_ref()
	func _alive(actor: Node2D) -> bool: return is_instance_valid(actor)
	func active_effect_count() -> int: return jobs.size()
	func _execute(command: Dictionary) -> void: executed.append(command)
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("B07 combat: "+label)

func _initialize() -> void:
	var arena := Arena.new()
	var actor := Actor.new()
	var victim := Actor.new()
	actor.room=arena
	arena.player=victim
	victim.position=Vector2(100,0)
	for n in range(1,19):
		for d in 5:
			var id := "B07-M%02d" % n
			var p := Skills.profile(id,35,d)
			check(not p.is_empty(),id+" lawful chapter profile")
			if p.is_empty(): continue
			check(bool(p.gameplay_implemented)==(n in [1,2,3,4,5,6,7,13]),id+" honest first-playable scope")
			check(bool(p.b07_candidate_contact_only)==not Skills.implemented(id),id+" explicit fallback flag")
			actor.profile=p
			var source := Skills.active(p,Vector2.ZERO,victim.position,true)
			var command := Skills.constrain(actor,source)
			check(float(command.tell)>=float(command.timing.minimum_tell_seconds) and float(command.lock)>=.22,id+" shared warning floors")
			var frozen := Skills.freeze_damage(command,p)
			check(not frozen.is_empty() and int(frozen.damage)==Skills.Numbers.skill_damage(p,int(command.coefficient),1,frozen),id+" damage resolves once")
			if not Skills.implemented(id):
				check(not bool(command.get("active",false)) and str(p.implementation_status)=="fallback_basic_active_deferred",id+" authored active not pretended")
				check(command.kind=="melee" and command.range==90.0 and command.coefficient==100,id+" playable basic only")
				continue
			check(bool(command.active) and command.cooldown==Skills.CDS[n-1],id+" authored cooldown")
			match n:
				1:
					check(command.range==180.0 and command.coefficient==110,"spear fixed line")
					check(command.followups.size()==(2 if d>=4 else 1 if d>=2 else 0),"spear cumulative D additions")
					if d>=2: check(command.followups[0].coefficient==40 and command.followups[0].delay>=.8,"tail owns independent warning")
				2:
					check(command.kind=="charge" and command.coefficient==95 and command.landing_only,"scout landing attack")
					check(float(command.tell)+float(command.lock)>=1.0,"camouflage never removes full visible warning")
				3:
					check(command.kind=="projectile" and command.range==260.0 and command.coefficient==100,"outbound physical disc")
					check(command.followups.size()==(1 if d>=2 else 0),"return only D2+")
					if d>=2:
						check(command.followups[0].coefficient==40 and command.followups[0].origin==command.target,"return starts at frozen endpoint")
						check(not is_zero_approx(float(command.followups[0].target.y)) if d>=4 else command.followups[0].target==Vector2.ZERO,"lit D4 fixed diagonal")
				4:
					check(command.kind=="b07_shield" and command.coefficient==0 and command.duration==2.0,"stance cannot emit support damage")
					check(command.followups[0].coefficient==110 and command.followups[0].delay==2.0,"shield bash after two seconds")
					check(command.followups[0].b07_push==(50.0 if d>=2 else 0.0),"shield push gate")
				5:
					check(command.kind=="b07_heal" and command.coefficient==0 and command.range==200.0,"healing is zero-damage bounded support")
					check(float(command.tell)+float(command.lock)>=1.3,"healer full visible channel")
					check(command.target_count==(2 if d>=4 else 1) and command.heal_ratio==(.03 if d>=4 else .04 if d>=2 else .06),"heal tier ratios")
					check(command.shield_ratio==(.04 if d>=2 else 0.0) and command.shield_duration==3.0,"candidate shield duration and cumulative tier")
				6:
					check(command.kind=="charge" and command.path_mode=="burrow" and command.landing_only and command.radius==70.0 and command.coefficient==100,"burrow only hits the warned landing")
					check(float(command.tell)+float(command.lock)>=1.1 and command.b07_mound,"persistent mound tell")
					check(command.recovery_floor>=1.2 and command.b07_after_motion=="sand_emerge","burrow opening independent of assassin speed")
				7:
					check(command.kind=="b07_vortex" and command.radius==100.0 and command.coefficient==60,"sand vortex distinct geometry")
					check(command.followups.size()==(2 if d>=4 else 1 if d>=2 else 0),"sand D2 ticks D4 outgoing line")
					if d>=2: check(command.followups[0].coefficient==20 and command.followups[0].tick_interval==1.0 and command.followups[0].duration==2.0,"bounded two-second pool")
				13:
					check(command.range==360.0 and command.coefficient==125,"sun beam length and strength")
					check(command.followups.size()==(1 if d>=2 else 0),"fixed mirror line D2 gate")
					if d>=2:
						check(command.followups[0].points==[Vector2(140,-80),Vector2(140,160)],"beam uses authored mirror segment, no random ray")
						check(command.followups[0].coefficient==40 and command.followups[0].delay==(1.0 if d>=4 else .8),"beam second-stage damage and warning")
	# Environment conditioning is done before lock and never mutates the source.
	actor.profile=Skills.profile("B07-M03",35,4)
	arena.obstruction=.5
	var disc := Skills.constrain(actor,Skills.active(actor.profile,Vector2.ZERO,victim.position,false))
	check(disc.target==Vector2(130,0) and disc.followups[0].origin==Vector2(130,0),"wall clips outbound and return start together")
	check(disc.followups[0].target==Vector2.ZERO,"unlit D4 retains original return line")
	arena.obstruction=1.0
	arena.b07_mechanics.area_clear=false
	actor.profile=Skills.profile("B07-M07",35,2)
	var vortex := Skills.constrain(actor,Skills.active(actor.profile,Vector2.ZERO,victim.position,true))
	check(vortex.followups[0].admission_deferred,"mirror clearance excludes persistent pool")
	arena.b07_mechanics.area_clear=true
	var host := Host.new()
	host.room=arena
	var adapter := Adapter.new()
	adapter.configure(host)
	actor.profile=Skills.profile("B07-M13",35,4)
	var beam := Skills.constrain(actor,Skills.active(actor.profile,Vector2.ZERO,victim.position,true))
	var bend := adapter.prepare(actor,beam.followups[0])
	check(adapter.admitted(bend),"frozen mirror line admitted")
	arena.b07_mechanics.mirror_state=2
	check(not adapter.admitted(bend),"turning mirror cancels frozen hostile line")
	check(bend.points==[Vector2(140,-80),Vector2(140,160)],"cancellation never tracks a new target")
	# Ordinary FSM really locks the displayed command before releasing it.
	actor.profile=Skills.profile("B07-M01",35,2)
	actor.brain=Brain.new()
	actor.brain.configure(actor.profile)
	actor.brain.tick(actor,.8,victim)
	actor.brain.tick(actor,1.0,victim)
	var locked: Dictionary=actor.brain.current_telegraph()
	check(locked.locked,"ordinary FSM reaches lock")
	victim.position=Vector2(0,100)
	actor.brain.tick(actor,.4,victim)
	check(actor.casts.size()==1 and actor.casts[0].points==locked.points,"actual release equals locked line")
	actor.brain.on_damaged(actor,{})
	check(arena.b07_mechanics.revealed,"actual damage notifies reveal mechanics")
	# Two-second shield clocks belong to the adapter, including cancellation.
	actor.profile=Skills.profile("B07-M04",35,4)
	actor.brain.configure(actor.profile)
	actor.brain.cooldown=10.0
	var shield := adapter.prepare(actor,Skills.active(actor.profile,Vector2.ZERO,Vector2(100,0),true))
	adapter.execute(shield)
	check(actor.get_meta("b07_shield_active",false),"runtime enables shield stance")
	arena.b07_mechanics.lit=false
	adapter.advance(.1)
	check(actor.brain.cooldown==12.0,"D4 lost light spends one extra two-second cooldown")
	adapter.advance(.1)
	check(actor.brain.cooldown==12.0,"lost-light penalty cannot stack every frame")
	adapter.advance(1.8)
	check(not actor.get_meta("b07_shield_active",false) and adapter.effects.is_empty(),"shield ends at two seconds")
	for d in 5:
		var boss := Boss.new()
		var p := Skills.boss_profile(d)
		boss.configure(p,707)
		check(boss.available_actions(2).size()==[2,3,4,4,4][d],"four implemented boss ability gates")
		check("altar_lines" not in boss.available_actions(1),"altar lines require second phase")
		check(p.deferred_actions==["shadow_guards","sunwheel_return"],"boss deferred abilities explicit")
		for action: String in boss.available_actions(2):
			var c := Skills.boss_action(p,action,Vector2.ZERO,Vector2(100,0),2)
			check(not c.is_empty() and float(c.lock)>=.24,"boss warning floor "+action)
			var frozen := Skills.freeze_damage(c,p)
			check(not frozen.is_empty() and frozen.damage==Skills.Numbers.skill_damage(p,int(c.coefficient),2,frozen),"boss phase damage single source "+action)
			if action=="golden_tail": check(is_equal_approx(c.ring_start,PI*.5) and is_equal_approx(c.ring_end,PI*1.5),"tail is rear half-circle")
		actor.profile=p
		actor.brain=boss
		boss.phase=2
		if d>=2:
			boss._begin_action(actor,victim,"altar_lines")
			check(boss.command.mirror_lines.size()==2 and boss.command.paths.size()==2,"boss previews both fixed mirror lines")
	adapter.reset()
	host.free()
	actor.free()
	victim.free()
	arena.free()
	print("B07 combat: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
