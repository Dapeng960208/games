extends SceneTree
## Authored enemy identities, executable brain commands and shared spawn budgets.
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Brain = preload("res://scripts/combat/enemy_brain.gd")
const LEVELS := [1,5,10,15,20]
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ENEMY_ARCHETYPES: "+label)

func sequence(id: String, level: int) -> Array[Dictionary]:
	var brain: RefCounted = Brain.new()
	brain.configure(Profiles.resolve(id,level))
	return brain._build_sequence()

func _run() -> void:
	var identities: Dictionary = {}
	for id: String in Catalog.enemy_ids():
		var catalog: Dictionary = Catalog.enemy(id)
		check(catalog.has("archetype") and catalog.has("damage_type") and catalog.has("magic_resist"),id+" declares a combat identity in authored content")
		identities[catalog.archetype] = true
		var previous: Dictionary = {}
		for level: int in LEVELS:
			var profile: Dictionary = Profiles.resolve(id,level)
			var parameters: Dictionary = profile.attack_parameters
			var label: String = id+" level "+str(level)
			check(profile.archetype==catalog.archetype and profile.damage_kind==catalog.damage_kind and profile.behavior_id==catalog.behavior_id,label+" retains authored role and unique prototype")
			check(profile.damage_type in ["physical","magic"],label+" exposes a canonical damage school")
			check(profile.armor>=0 and profile.magic_resist>=0 and profile.armor<=24 and profile.magic_resist<=32,label+" bounded final defenses")
			check(profile.max_hp<=180 and profile.damage<=25 and profile.move_speed<=132,label+" ordinary strength remains within encounter safety limits")
			check(parameters.tell_seconds>=catalog.minimum_tell_seconds and parameters.tell_seconds>=0.55 and parameters.area_tell_seconds>=0.8,label+" retains melee and area reaction time")
			check(parameters.locked_line_delay_seconds>=0.4 and parameters.combo_gap_seconds>=0.55 and not parameters.track_after_lock,label+" frozen aim and numbered combos stay readable")
			check(profile.attack_cooldown_seconds==profile.recovery_seconds and parameters.recovery_seconds==profile.recovery_seconds and profile.recovery_seconds>=parameters.exposure_seconds,label+" cadence field is the real executable counterattack window")
			check(parameters.spawn_grace_seconds>=0.8 and not parameters.spawn_can_damage and parameters.max_active_hazards<=2 and parameters.summon_cap<=2,label+" finite effects and safe spawning")
			for command: Dictionary in sequence(id,level):
				check(command.damage_type==profile.damage_type,label+" actual skill command carries the explicit damage school")
			if not previous.is_empty():
				check(profile.max_hp>previous.max_hp and profile.damage>previous.damage and profile.move_speed>=previous.move_speed,label+" levels strengthen real attributes")
				check(profile.armor>=previous.armor and profile.magic_resist>=previous.magic_resist,label+" defenses never regress across level bands")
				if level<=15:
					check(profile.mechanics.size()>previous.mechanics.size() and profile.attack_parameters!=previous.attack_parameters,label+" adds authored executable mechanics, not only HP")
			previous = profile
	check(identities.size()==5,"all five distinct combat archetypes are represented")
	_comparisons()
	_executed_patterns()
	_actor_interface()
	_budgets()
	print("ENEMY_ARCHETYPES: %d checks; %d failures; 36 prototypes / 5 archetypes" % [checks,failures])
	quit(0 if failures==0 else 1)

func _comparisons() -> void:
	for level: int in LEVELS:
		var tank: Dictionary = Profiles.resolve("M08",level)
		var assassin: Dictionary = Profiles.resolve("M10",level)
		var caster: Dictionary = Profiles.resolve("M31",level)
		var regular: Dictionary = Profiles.resolve("M01",level)
		var support: Dictionary = Profiles.resolve("M09",level)
		check(tank.max_hp>assassin.max_hp*1.8 and tank.armor>assassin.armor+10,"tank survives through health and physical defense at "+str(level))
		check(assassin.damage>tank.damage*1.3 and assassin.damage>regular.damage and assassin.move_speed>tank.move_speed*1.5,"assassin trades durability for real physical burst and mobility")
		check(assassin.damage_type=="physical" and assassin.magic_resist<tank.magic_resist,"assassin retains fragile physical identity")
		check(caster.damage_type=="magic" and caster.armor<tank.armor and caster.magic_resist>tank.magic_resist,"caster attacks magic resistance and stays weak to physical pressure")
		check(support.damage<regular.damage and tank.attack_cooldown_seconds>assassin.attack_cooldown_seconds,"support damage and tank cadence differ from aggressive roles")
		check(Profiles.resolve("M08",level,"elite").magic_resist>tank.magic_resist,"elite resistance is resolved once in the profile")
	check(Profiles.resolve("M10").archetype=="assassin","M10 is the authored bud-foot assassin, never misclassified as a mage")
	check(Profiles.resolve("M04").archetype=="skirmisher" and Profiles.resolve("M28").archetype=="assassin","ordinary swarms and sound-charging ambushers are not flattened into one role")

func _executed_patterns() -> void:
	for level: int in [1,5,10,15]:
		var acid: Array[Dictionary] = sequence("M11",level)
		check(acid.size()==(1 if level==1 else (2 if level==5 else 3)),"acid caster teaches one landing before multi-point combinations")
		var shield: Array[Dictionary] = sequence("M08",level)
		check(shield[0].kind=="guard" and shield[1].kind=="melee","tank retains directional shield then authored bash")
		check(shield[1].status.id=="slow" and shield[1].status.duration<=0.96 and shield[1].status.magnitude>=0.75,"tank shield bash adds bounded movement control without a stun lock")
		check(sequence("M01",level)[0].get("status",{}).is_empty(),"ordinary melee does not inherit the tank's control")
		check(sequence("M28",level)[0].kind=="charge" and sequence("M28",level)[0].damage_type=="physical","sound ambusher executes a physical charge")
		check(sequence("M32",level)[0].requires_stealth_terrain and sequence("M15",level)[0].path_mode=="burrow","ambushers retain their different terrain and displacement decisions")
		check(sequence("M31",level)[0].refraction and sequence("M31",level)[0].damage_type=="magic","crystal caster retains its single-refraction spell")
	var tank: Dictionary = Profiles.resolve("M08",1)
	var late_tank: Dictionary = Profiles.resolve("M08",4)
	check(late_tank.attack_cooldown_seconds<tank.attack_cooldown_seconds and late_tank.attack_parameters.tell_seconds==tank.attack_parameters.tell_seconds,"level cadence improves without shortening a telegraph")

func _actor_interface() -> void:
	# Configure the production actor without entering a room or starting a save.
	var enemy_script: Script = load("res://scripts/combat/enemy.gd")
	for id: String in ["M08","M10","M31"]:
		var definition: Dictionary = Profiles.resolve(id,15,"elite")
		var actor: Node = enemy_script.new()
		actor.configure(definition)
		check(is_equal_approx(actor.armor,definition.armor) and is_equal_approx(actor.magic_resist,definition.magic_resist),id+" actor consumes final defenses without multiplying level growth twice")
		check(is_equal_approx(actor.contact_damage,definition.damage) and is_equal_approx(actor.move_speed,definition.move_speed),id+" actor consumes real archetype damage and speed")
		actor.free()

func _budgets() -> void:
	for room_id: String in Catalog.room_ids():
		for difficulty: int in [0,2,4]:
			var room_slots: int = 0
			for zone: int in range(3):
				var plan: Dictionary = Profiles.encounter_plan(room_id,zone,difficulty)
				check(not plan.is_empty(),room_id+" archetypes keep a feasible encounter plan")
				if plan.is_empty(): continue
				room_slots += int(plan.concurrent_cap)
				check(plan.room_cap==18 and plan.concurrent_cap<=6,room_id+" preserves shared concurrent room cap")
				for wave: Array in plan.waves:
					var slots: int = 0
					var spent: int = 0
					for profile: Dictionary in wave:
						slots += int(profile.encounter_slot_cost)
						spent += int(profile.encounter_budget_cost)
						check(profile.has("archetype") and profile.has("magic_resist"),"spawned profiles carry final combat identities")
						if profile.reserved_summon_count>0:
							check(profile.encounter_slot_cost==1+profile.reserved_summon_count and profile.reserved_summon_threat>0,"summoned children still reserve slots and threat")
					check(slots<=plan.concurrent_cap and spent<=plan.concurrent_threat_budget,room_id+" every simultaneous wave obeys slots and threat budget")
			check(room_slots<=18,room_id+" all three zones combined remain within 18 reserved live slots")
