extends SceneTree
## V2-only warning pacing, exact catalog/HUD clocks, frozen aim, and real damage
## release. V1's historical safety contract stays unchanged.
const Timing = preload("res://scripts/combat/enemy_warning_timing.gd")
const Brain = preload("res://scripts/combat/enemy_brain.gd")
const Abilities = preload("res://scripts/combat/enemy_ability_catalog.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Presentation = preload("res://scripts/combat/enemy_skill_presentation.gd")
const Fixtures = preload("res://tests/test_enemy_skills.gd")
const Actors = preload("res://tests/test_enemy_ability_expansion.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const STEP := 0.005
var checks := 0
var failures := 0

class Caster extends Actors.Actor:
 var runtime: Node2D
 var clock: float = 0.0
 var release_time: float = -1.0
 func cast_enemy_skill(command: Dictionary) -> void:
  casts.append(command.duplicate(true))
  release_time = clock
  runtime.emit_skill(self,command)

func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("ENEMY WARNING TIMING: "+label)
func near(a: float,b: float,label: String,tolerance: float=0.00001) -> void: check(absf(a-b)<=tolerance,label+" ("+str(a)+" / "+str(b)+")")

func run_checks() -> void:
 for id: String in Abilities.ENTRIES:
  var prior: float = INF
  for difficulty: int in range(5):
   var source: Dictionary = Profiles.resolve(id,20,"normal",2,difficulty)
   var brain := Brain.new()
   brain.configure(source)
   var record: Array[Dictionary] = Abilities.all_skills(id,difficulty,source)
   var commands: Array[Dictionary] = brain._build_sequence(false)
   var total: float = 0.0
   for index: int in commands.size():
    var values: Dictionary = brain.timing_for_command(commands[index],index)
    near(float(record[index].tell_seconds),float(values.tell_seconds),id+" codex tracking equals runtime at selected D")
    near(float(record[index].lock_seconds),float(values.lock_seconds),id+" codex lock equals runtime at selected D")
    near(float(values.cooldown),float(source.recovery_seconds),id+" warning pacing leaves recovery unchanged")
    check(float(values.tell_seconds)>=float(values.minimum_tell_seconds) and float(values.lock_seconds)>=.22,id+" bounded readable V2 floors")
    check(float(values.tell_seconds)+float(values.lock_seconds)<float(values.authored_tell_seconds)+float(values.authored_lock_seconds),id+" every selected D actually shortens warning")
    total += float(values.tell_seconds)+float(values.lock_seconds)
   check(total<prior,id+" higher selected D shortens same baseline sequence")
   prior = total
   var legacy := Brain.new()
   legacy.configure(Profiles.resolve(id,20,"normal",1,difficulty))
   var legacy_commands: Array[Dictionary] = legacy._build_sequence(false)
   for index: int in legacy_commands.size():
    var values: Dictionary = legacy.timing_for_command(legacy_commands[index],index)
    near(float(values.tell_seconds),float(values.authored_tell_seconds),id+" V1 tracking preserved")
    near(float(values.lock_seconds),.4,id+" V1 lock preserved")
 for difficulty: int in [0,4]:
  for id: String in ["M01","M03","M11","M36","M37","M39","M42","M51"]: real_release(id,difficulty)
 test_scan_floor()
 print("ENEMY WARNING TIMING: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

func real_release(id: String,difficulty: int) -> void:
 var room := Fixtures.RoomFixture.new()
 root.add_child(room)
 var runtime := Runtime.new()
 room.add_child(runtime)
 runtime.configure(room)
 runtime.set_physics_process(false)
 var caster := Caster.new()
 caster.enemy_id = id
 caster.profile = Profiles.resolve(id,1,"normal",2,difficulty)
 caster.room = room
 caster.runtime = runtime
 caster.position = Vector2(300,300)
 caster.brain = Brain.new()
 caster.brain.configure(caster.profile)
 room.enemies.add_child(caster)
 var victim := Actors.Actor.new()
 victim.position = Vector2(340,300)
 room.add_child(victim)
 room.player = victim
 room.recipients.append(victim)
 var started: float = -1.0
 var locked: float = -1.0
 var expected: Dictionary = {}
 var frozen: Dictionary = {}
 var previous_progress: float = -1.0
 for frame: int in 1400:
  caster.clock += STEP
  caster.brain.tick(caster,STEP,victim)
  caster.position += caster.velocity*STEP
  var command: Dictionary = caster.brain.current_telegraph()
  if not command.is_empty():
   if started<0:
    started = caster.clock
    expected = command.warning_timing
   var hud: Dictionary = Presentation.readout(caster.brain)
   var fraction: float = float(command.progress)
   var actual_progress: float = (float(command.telegraph_seconds)+fraction*float(command.locked_seconds))/(float(command.telegraph_seconds)+float(command.locked_seconds)) if bool(command.locked) else fraction*float(command.telegraph_seconds)/(float(command.telegraph_seconds)+float(command.locked_seconds))
   near(float(hud.progress),actual_progress,id+" cast-card percentage uses exact live clocks")
   check(float(hud.progress)+0.00001>=previous_progress,id+" tracking→lock countdown is continuous")
   previous_progress = float(hud.progress)
   if bool(command.locked):
    if locked<0:
     locked = caster.clock
     frozen = command.duplicate(true)
     # Force a late change in victim direction, after the committed warning.
     victim.position += Vector2(0,25)
    near(Vector2(command.direction).distance_to(frozen.direction),0,id+" locked aim cannot rotate")
   check(caster.casts.is_empty() and victim.hits.is_empty(),id+" no emitted effect/damage before warning completes")
  if not caster.casts.is_empty(): break
 check(started>=0 and locked>=0 and caster.release_time>0,id+" actual brain reaches tracking, lock, release")
 if not expected.is_empty():
  near(locked-started,float(expected.tell_seconds),id+" real tracking duration",STEP*1.1)
  near(caster.release_time-locked,float(expected.lock_seconds),id+" real lock duration",STEP*1.1)
  near(caster.release_time-started,float(expected.tell_seconds)+float(expected.lock_seconds),id+" first effect starts at shortened advertised release",STEP*2.1)
  near(float(caster.casts[0].telegraph_seconds),float(expected.tell_seconds),id+" emitted command retains actual tracking seconds")
  near(float(caster.casts[0].locked_seconds),float(expected.lock_seconds),id+" emitted command retains actual lock seconds")
 if id=="M01": check(not victim.hits.is_empty(),"M01 first real damage resolves precisely at release")
 runtime.cancel_owner(caster)
 room.free()

class MarkRuntime extends Node2D:
 func consume_scan_mark(_actor: Node2D) -> float: return 0.85
class MarkRoom extends Node2D:
 var enemy_skills: Node2D = MarkRuntime.new()
 func _init() -> void: add_child(enemy_skills)

func test_scan_floor() -> void:
 var room := MarkRoom.new()
 root.add_child(room)
 var actor := Actors.Actor.new()
 actor.room = room
 room.add_child(actor)
 var victim := Actors.Actor.new()
 victim.position = Vector2(90,0)
 room.add_child(victim)
 for difficulty: int in range(5):
  var brain := Brain.new()
  brain.configure(Profiles.resolve("M03",1,"normal",2,difficulty))
  brain.call("_begin_cycle",actor,victim)
  var command: Dictionary = brain.current_telegraph()
  var expected: Dictionary = brain.timing_for_command(command,0)
  near(float(command.telegraph_seconds),maxf(float(expected.minimum_tell_seconds),float(expected.tell_seconds)*.85),"scan mark respects selected-D floor")
  near(float(command.locked_seconds),float(expected.lock_seconds),"scan never shortens fixed lock further")
 room.free()
