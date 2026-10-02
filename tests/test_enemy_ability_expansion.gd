extends SceneTree
## Focused command, difficulty and real-runtime counterplay checks. No natural
## progression sampling or player saves. Run with an isolated profile path.
const Catalog = preload("res://scripts/combat/enemy_ability_catalog.gd")
const Brain = preload("res://scripts/combat/enemy_brain.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const Presentation = preload("res://scripts/combat/enemy_skill_presentation.gd")
const Fixtures = preload("res://tests/test_enemy_skills.gd")
const Health = preload("res://scripts/combat/health.gd")
var checks := 0
var failures := 0

class Actor extends Node2D:
 var profile: Dictionary = {}
 var enemy_id: String = ""
 var state: StringName = &"chase"
 var state_time: float = 0.0
 var velocity := Vector2.ZERO
 var knockback := Vector2.ZERO
 var aim_direction := Vector2.RIGHT
 var collision_radius: float = 12.0
 var navigation_radius: float = 12.0
 var actor_kind: String = "enemy"
 var zone_index: int = 0
 var room: Node2D
 var brain: RefCounted
 var health: Node = Health.new()
 var contact_damage: float = 10.0
 var hits: Array[Dictionary] = []
 var statuses: Array[Dictionary] = []
 var casts: Array[Dictionary] = []
 var _automatic_attack_target: WeakRef
 func _init() -> void:
  add_child(health)
  health.reset(10000.0)
 func is_alive() -> bool: return not health.dead and not is_queued_for_deletion()
 func receive_damage(amount: float, origin: Vector2) -> bool:
  hits.append({"amount":amount,"origin":origin})
  return health.damage(amount)
 func receive_enemy_status(command: Dictionary) -> bool:
  statuses.append(command.duplicate(true))
  return true
 func cast_enemy_skill(command: Dictionary) -> void: casts.append(command.duplicate(true))

func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("ABILITY EXPANSION: "+label)

func run_checks() -> void:
 check(Catalog.ENTRIES.size()==54,"all54 ability identities")
 for id: String in Catalog.ENTRIES:
  for difficulty: int in range(5):
   for level: int in [1,20]:
    var profile: Dictionary = Profiles.resolve(id,level,"normal",2,difficulty)
    var brain := Brain.new()
    brain.configure(profile)
    var commands: Array[Dictionary] = brain._build_sequence()
    check(not commands.is_empty(),id+" commands at each selected D/level")
    check(brain.selected_difficulty==difficulty,id+" selected difficulty retained")
    check(brain.mechanic_tier==(1 if level==1 else 4),id+" numeric tier unchanged")
    var extras: int = 0
    for command: Dictionary in commands:
     if command.has("unlock_difficulty"): extras += 1
     check(not str(command.get("ability_id","")).is_empty() and command.get("caster_enemy_id","")==id,id+" commands source-stamped")
     check(int(command.get("max_active_hazards",2))<=2 and int(command.get("count",1))<=5,id+" safety caps")
    check(extras==(0 if difficulty==0 else 1),id+" bounded rotating stage")
   var skills: Array[Dictionary] = Catalog.all_skills(id,difficulty,Profiles.resolve(id,1,"normal",2,difficulty))
   var available: int = 0
   var locked: int = 0
   for skill: Dictionary in skills:
    check(not str(skill.name).is_empty() and not str(skill.effect).is_empty(),id+" codex actual skill details")
    if int(skill.min_difficulty)>0:
     if bool(skill.locked): locked += 1
     else: available += 1
   check(available==difficulty and locked==4-difficulty,id+" exact0–4 unlock contract")
  var seen: Dictionary = {}
  for cycle: int in range(4):
   var extra: Dictionary = Catalog.extra_command(id,4,cycle)
   seen[str(extra.mechanism_id)] = true
  check(seen.size()==4,id+" four real distinct mechanisms remain in pool")
 check_effective_values()
 check_new_signatures()
 check_runtime_counterplay()
 check_ui_budget()
 print("ENEMY ABILITY EXPANSION: ",checks-failures,"/",checks," passed")
 quit(1 if failures else 0)

func check_new_signatures() -> void:
 var seen: Dictionary = {}
 for index: int in range(1,55):
  var id: String = "M%02d" % index
  var brain := Brain.new()
  brain.configure(Profiles.resolve(id,1,"normal",1,0))
  var descriptors: Array = []
  for command: Dictionary in brain._build_sequence():
   var gameplay: Dictionary = {}
   for key: String in ["kind","shape","range","radius","angle","inner_radius","target_offsets","mode","pull_distance","returning","requires_pull_hit","requires_counter_hit","break_interrupts_owner","break_exposes_owner","retreat","projectile_angles","status","aim_offset"]:
    if command.has(key): gameplay[key] = command[key]
   descriptors.append(gameplay)
  var signature: String = JSON.stringify(descriptors)
  check(not seen.has(signature),id+" distinct runtime signature")
  seen[signature] = id

func fixture() -> Dictionary:
 var room := Fixtures.RoomFixture.new()
 root.add_child(room)
 var owner := Actor.new()
 owner.position = Vector2(300,300)
 owner.room = room
 owner.enemy_id = "M38"
 room.enemies.add_child(owner)
 var victim := Actor.new()
 victim.position = Vector2(650,330)
 room.add_child(victim)
 room.recipients.append(victim)
 room.player = victim
 var runtime := Runtime.new()
 room.add_child(runtime)
 runtime.configure(room)
 runtime.set_physics_process(false)
 return {"room":room,"owner":owner,"victim":victim,"runtime":runtime}

func emit(f: Dictionary, command: Dictionary) -> Dictionary:
 command["origin"] = f.owner.position
 command["direction"] = Vector2.RIGHT
 command["target"] = f.owner.position+Vector2(float(command.get("range",100)),0)
 Brain.normalize_geometry(command)
 f.runtime.emit_skill(f.owner,command)
 return command

func check_runtime_counterplay() -> void:
 var f: Dictionary = fixture()
 var returned: Dictionary = emit(f,{"kind":"projectile","shape":"line","range":200.0,"radius":5.0,"speed":200.0,"count":1,"returning":true,"pierce":true,"damage":10.0})
 check(returned.paths[0].size()==3 and returned.paths[0][2]==returned.origin,"return path is fully frozen and visible")
 f.runtime.advance(1.05)
 check(f.runtime.projectiles.size()==1 and bool(f.runtime.projectiles[0].get("returning_leg",false)),"real projectile turns back")
 f.victim.position = Vector2(400,300)
 f.runtime.advance(.6)
 check(f.victim.hits.size()==1,"return leg hits a newly entered target")
 f.runtime.advance(.5)
 check(f.victim.hits.size()==1 and f.runtime.projectiles.is_empty(),"return shot hits each target once and retires")
 emit(f,{"kind":"guard","mode":"screen","charges":2,"angle":1.8,"duration":4.0,"break_exposes_owner":true})
 check(f.runtime.filter_incoming_damage(f.owner,10.0,&"primary",Vector2.LEFT)==0,"screen first real charge")
 f.runtime.filter_incoming_damage(f.owner,10.0,&"primary",Vector2.LEFT)
 check(f.owner.has_meta("enemy_guard_broken"),"exhausted screen publishes interrupt receipt")
 f.owner.remove_meta("enemy_guard_broken")
 emit(f,{"kind":"ground_area","shape":"line","range":150.0,"radius":10.0,"duration":4.0,"breakable":true,"break_interrupts_owner":true,"damage_multiplier":0.0,"status":{"id":"slow","duration":.8}})
 check(f.runtime.hazards.size()==1,"real breakable net spawned")
 if not f.runtime.hazards.is_empty():
  var anchor: Node = f.runtime.hazards[0].anchor_ref.get_ref()
  anchor.health.damage(10000.0)
  f.runtime.advance(.01)
 check(f.owner.has_meta("enemy_hazard_broken") and f.runtime.hazards.is_empty(),"breaking real net cancels field and publishes interrupt")
 f.owner.remove_meta("enemy_hazard_broken")
 f.victim.position = Vector2(400,350)
 emit(f,{"kind":"pull","shape":"line","range":200.0,"radius":12.0,"pull_distance":60.0,"record_pull_hit":true,"damage_multiplier":0.0})
 check(not f.owner.has_meta("enemy_pull_connected"),"missed hook has no hit receipt")
 f.victim.position = Vector2(400,300)
 emit(f,{"kind":"pull","shape":"line","range":200.0,"radius":12.0,"pull_distance":60.0,"record_pull_hit":true,"damage_multiplier":0.0})
 check(f.owner.get_meta("enemy_pull_connected",false) and f.victim.position.x<400,"connected hook really displaces and gates followup")
 for id: String in ["M47","M51"]:
  var brain := Brain.new()
  brain.configure(Profiles.resolve(id,1,"normal",1,0))
  if f.owner.has_meta("enemy_pull_connected"): f.owner.remove_meta("enemy_pull_connected")
  brain.set("_sequence",brain._build_sequence())
  brain.set("_stage",1)
  brain.call("_begin_stage",f.owner,f.victim)
  check(brain.current_telegraph().is_empty(),id+" denied condition does not show fake cast")
  check(brain.phase==&"recovery",id+" denied condition exposes real recovery")
  brain.configure(Profiles.resolve(id,1,"normal",1,0))
  brain.set("_sequence",brain._build_sequence())
  brain.set("_stage",1)
  if id=="M47": f.owner.set_meta("enemy_pull_connected",true)
  else: brain.set("_counter_hits",1)
  brain.call("_begin_stage",f.owner,f.victim)
  check(not brain.current_telegraph().is_empty(),id+" accepted condition begins full telegraph")
 var counter := Brain.new()
 counter.configure(Profiles.resolve("M51",1,"normal",1,0))
 counter.set("_telegraph",counter._build_sequence()[0])
 counter.set("phase",&"execute")
 counter.on_damaged(f.owner,{"kind":"primary","direction":Vector2.RIGHT,"damage":1.0})
 check(int(counter.get("_counter_hits"))==0,"M51 flanking strike does not trigger retaliation")
 counter.on_damaged(f.owner,{"kind":"primary","direction":Vector2.LEFT,"damage":1.0})
 check(int(counter.get("_counter_hits"))==1,"M51 frontal strike arms its conditional counter")
 var retreat := Brain.new()
 retreat.configure(Profiles.resolve("M45",1,"normal",1,0))
 retreat.set("_sequence",retreat._build_sequence())
 retreat.set("_stage",1)
 retreat.set("_cycle_target",f.victim.position)
 retreat.call("_begin_stage",f.owner,f.victim)
 check(float(retreat.current_telegraph().direction.x)<0,"mender locks an actual retreat direction")
 var ring: Dictionary = {"shape":"ring","origin":Vector2.ZERO,"direction":Vector2.RIGHT,"radius":132.0,"inner_radius":65.0}
 check(not f.runtime.shape_contains(ring,Vector2(25,0),12) and f.runtime.shape_contains(ring,Vector2(90,0),12),"echo ring keeps actual safe core")
 f.runtime.cancel_owner(f.owner)
 check(f.runtime.active_effect_count()==0,"owner cancellation cleans all expansion effects")
 f.room.free()

func check_ui_budget() -> void:
 var f: Dictionary = fixture()
 for index: int in 18:
  var actor := Actor.new()
  actor.position = Vector2(500+index*3,300)
  actor.room = f.room
  actor.enemy_id = "M%02d" % (index+1)
  actor.brain = Brain.new()
  actor.brain.configure(Profiles.resolve(actor.enemy_id,1,"normal",1,0))
  actor.brain.set("phase",&"locked")
  actor.brain.set("_telegraph",Catalog.decorate({"kind":"melee","phase":"locked","stage":0,"stage_count":2},actor.brain.profile,0))
  f.room.enemies.add_child(actor)
  if index==17: f.victim._automatic_attack_target = weakref(actor)
 var visible: Array[int] = Presentation.detail_candidates(f.room)
 check(visible.size()==2,"18 concurrent actors produce only two detailed cards")
 check(visible[0]==f.victim._automatic_attack_target.get_ref().get_instance_id(),"actual attacked target wins priority")
 var target: Actor = f.victim._automatic_attack_target.get_ref()
 var before: Dictionary = target.brain.current_skill()
 var info: Dictionary = Presentation.readout(target.brain)
 check(info.id==before.ability_id and info.stage_count==before.stage_count,"UI reads the actual cast identity and sequence")
 check(target.brain.current_skill()==before,"UI never mutates combat state")
 f.room.free()

func check_effective_values() -> void:
 var numbers: Script = load("res://scripts/combat/enemy_numerical_v2.gd")
 for id: String in ["M06","M12","M33","M37","M50"]:
  for difficulty: int in [0,4]:
   var profile: Dictionary = Profiles.resolve(id,20,"normal",2,difficulty)
   for skill: Dictionary in Catalog.all_skills(id,difficulty,profile):
    var exact: Dictionary = numbers.command(skill.command,profile)
    var shown: Dictionary = Catalog.effective_command(skill.command,profile)
    for key: String in ["anchor_health","cover_hp","pod_health","status"]:
     if exact.has(key): check(shown.get(key)==exact.get(key),id+" UI "+key+" matches actual numerical packet")
    for key: String in ["anchor_health","cover_hp","pod_health"]:
     if exact.has(key): check(str(skill.effect).contains(str(exact[key])),id+" effect text shows actual "+key+" value")
