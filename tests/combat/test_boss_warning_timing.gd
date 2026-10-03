extends SceneTree
## Requested warning pacing only. No HP/damage/recovery balance sampling.
const Brain = preload("res://scripts/gameplay/bosses/boss_brain.gd")
const Profiles = preload("res://scripts/domain/combat/boss_profiles.gd")
const Fixtures = preload("res://tests/combat/test_bosses.gd")
const RuntimeFixtures = preload("res://tests/combat/test_enemy_skills.gd")
const Runtime = preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
const Presentation = preload("res://scripts/presentation/monsters/boss_skill_presentation.gd")
const Abilities = preload("res://scripts/domain/combat/boss_ability_catalog.gd")
const STEP := 1.0/240.0
var checks := 0
var failures: Array[String] = []
var export_rows: Array = []

class RuntimeCaster extends Fixtures.ActorStub:
	var runtime: Node2D
	var profile: Dictionary = {}
	var actor_kind := "boss"
	var rank := "boss"
	func cast_enemy_skill(skill: Dictionary) -> void:
		casts.append(skill.duplicate(true))
		runtime.emit_skill(self,skill)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: call_deferred("run_checks")

func run_checks() -> void:
	for id: String in Profiles.ids():
		for d: int in 5:
			for phase_id: int in [1,2,3]:
				var brain := Brain.new()
				brain.configure(Profiles.resolve(id,d,2),137)
				brain.phase = phase_id
				for action: String in brain.available_actions():
					var actor := Fixtures.ActorStub.new()
					var victim := Fixtures.VictimStub.new()
					root.add_child(actor)
					root.add_child(victim)
					actor.position = Vector2(300,300)
					victim.position = Vector2(500,300)
					actor.health.current = actor.health.maximum * [1.0,0.6,0.2][phase_id-1]
					brain.configure(Profiles.resolve(id,d,2),137)
					brain.phase = phase_id
					var legacy := Brain.new()
					legacy.configure(Profiles.resolve(id,d,1),137)
					legacy.phase = phase_id
					var before := legacy._build_action(actor,victim,action)
					var after := brain._build_action(actor,victim,action)
					check(not before.is_empty() and not after.is_empty(), action + " legal command exists")
					if after.is_empty() or before.is_empty():
						actor.free(); victim.free(); continue
					check(float(after.tell)+float(after.lock) < float(before.tell)+float(before.lock), action + " selected difficulty really shortens total warning")
					check(float(after.tell)>=0.45 and float(after.lock)>=0.24, action + " keeps boss reaction floors")
					check(brain._apply_warning_timing(after)==after, action + " never compounds timing")
					for key: String in ["damage_multiplier","recovery","cooldown","weakpoint_duration","weakpoint_delay","range","radius","width","duration","count"]:
						check(before.get(key)==after.get(key), action + " preserves " + key)
					brain.configure(Profiles.resolve(id,d,2),137)
					brain.phase = phase_id
					brain._begin_action(actor,victim,action)
					var expected := float(brain.command.tell)+float(brain.command.lock)
					var readout := Presentation.readout(brain)
					check(is_equal_approx(float(readout.remaining),expected), action + " cast UI countdown equals actual warning")
					var elapsed := 0.0
					var locked_target: Variant = null
					while actor.casts.is_empty() and elapsed < 4.0:
						brain.tick(actor,STEP,victim)
						elapsed += STEP
						if brain.state == &"locked":
							if locked_target == null:
								locked_target = brain.command.get("target")
								victim.position += Vector2(0,70)
							else: check(brain.command.get("target")==locked_target, action + " locked geometry stays frozen")
						if elapsed < expected-STEP: check(actor.casts.is_empty(), action + " no early release")
					check(actor.casts.size()==1 and elapsed>=expected-STEP and elapsed<=expected+STEP*2.1, action + " one release matches displayed tell+lock")
					export_rows.append({"boss_id":id,"action":action,"name":Abilities.title(action),"phase":phase_id,"difficulty":d,"family":after.warning_family,"before_tell":before.tell,"before_lock":before.lock,"tell":after.tell,"lock":after.lock,"recovery":after.get("recovery",0),"observed_release":elapsed})
					actor.free(); victim.free()
	_alternate_ring_variants()
	for d: int in [0,4]: _actual_damage(d)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(AssetCatalog.resolve(arg.trim_prefix("--output=")),FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(export_rows,"\t")+"\n"); file.close()
	print("BOSS_WARNING_TIMING: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _alternate_ring_variants() -> void:
	var actor := Fixtures.ActorStub.new()
	var victim := Fixtures.VictimStub.new()
	root.add_child(actor); root.add_child(victim)
	victim.position = Vector2(200,0)
	for d: int in 5:
		var brain := Brain.new()
		brain.configure(Profiles.resolve("BO04",d,2),137)
		brain.phase = 3
		for variant: String in ["outer","inner"]:
			var command := brain._build_action(actor,victim,"alternating_ring")
			check(str(command.warning_family)==("large_ring" if variant=="outer" else "area"), "alternating ring distinct safe-window family")
			check(float(command.tell)>= (0.75 if variant=="outer" else 0.60), "alternating ring retains geometry-specific floor")
			export_rows.append({"boss_id":"BO04","action":"alternating_ring","name":Abilities.title("alternating_ring"),"variant":variant,"phase":3,"difficulty":d,"family":command.warning_family,"before_tell":command.authored_tell_seconds,"before_lock":command.authored_lock_seconds,"tell":command.tell,"lock":command.lock,"recovery":command.get("recovery",0),"observed_release":-1.0})
	actor.free(); victim.free()

func _actual_damage(difficulty: int) -> void:
	var room := RuntimeFixtures.RoomFixture.new()
	root.add_child(room)
	var runtime := Runtime.new()
	room.add_child(runtime)
	runtime.configure(room)
	runtime.set_physics_process(false)
	var caster := RuntimeCaster.new()
	caster.runtime = runtime
	caster.profile = Profiles.resolve("BO01",difficulty,2)
	caster.position = Vector2(300,300)
	room.enemies.add_child(caster)
	var victim := RuntimeFixtures.ActorFixture.new()
	victim.position = Vector2(450,300)
	victim.health.reset(100000.0)
	room.add_child(victim)
	room.player = victim
	room.recipients.append(victim)
	var brain := Brain.new()
	brain.configure(caster.profile)
	brain._begin_action(caster,victim,"hammer_fan")
	var expected := float(brain.command.tell)+float(brain.command.lock)
	var elapsed := 0.0
	while victim.hits.is_empty() and elapsed<2.0:
		brain.tick(caster,STEP,victim)
		runtime.advance(STEP)
		elapsed += STEP
		if elapsed<expected-STEP: check(victim.hits.is_empty(), "D%d no actual damage before warning ends" % difficulty)
	check(victim.hits.size()==1 and elapsed>=expected-STEP and elapsed<=expected+STEP*2.1, "D%d actual runtime hit lands on release" % difficulty)
	room.free()
