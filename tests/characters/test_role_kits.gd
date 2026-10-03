extends Node
## Direct behavior checks for the approved roles, using isolated state and real
## original-hit/release hooks. These are module checks, not natural-play evidence.

const Catalog = preload("res://scripts/domain/combat/skill_catalog.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Actor = preload("res://scripts/gameplay/characters/hero_actor.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void: push_error("ROLE KITS timed out"); get_tree().quit(2))
	_run.call_deferred()

func same_values(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("ROLE KITS: " + label)

func _run() -> void:
	if not Game.profile_path.contains("test_role_kits"):
		push_error("Use --test-profile containing test_role_kits")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated profile/run")
	if Game.run == null:
		_finish()
		return
	_catalog()
	_warrior()
	_gunner()
	_mage()
	_equipment_identity()
	_relic_resource_descriptions()
	_role_resource_descriptions()
	_feel_regressions()
	await _archives()
	await _live_skill_matrix()
	_finish()

func fixture(hero: String) -> Node2D:
	Game.run.hero_id = hero
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve(hero, 8, {}, {}, Game.run.ruleset_version())
	Game.run.stats["resource_gain_bonus"] = 0.0
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.shield = 0
	Game.run.resource = Game.run.stats.resource_max
	Game.run.resource_decay_remainder = 0.0
	Game.run.skill_loadout_snapshot = Catalog.starter_ids(hero)
	Game.run.skill_branches_snapshot = {hero + "_SK01":"", hero + "_SK04":""}
	return Actor.new()

func units(value: float) -> float:
	return float(Numbers.scale(value, Game.run.ruleset_version()))

func _relic_resource_descriptions() -> void:
	var original_locale: String = Words.locale
	for locale: String in ["zh", "en"]:
		Words.locale = locale
		for version: int in [Numbers.LEGACY, Numbers.V2]:
			for rank: int in [1, 2]:
				var amount: int = int(Numbers.scale(15 if rank == 2 else 10, version))
				var description: String = str(ClassRelics.display("CH01","RL03",rank,"",version).description)
				check(description.contains("%d Rage" % amount if locale == "en" else "%d怒气" % amount), "warrior relic description matches runtime units "+locale+"/"+str(version)+"/"+str(rank))
		var race: Dictionary = ClassRelics.display("CH01","RL03",1,"B01",Numbers.V2)
		check(str(race.race_trait).contains("10 resource" if locale == "en" else "10点职业资源"), "race resource trait retains its actual ten units without double scaling "+locale)
	Words.locale = original_locale

func _role_resource_descriptions() -> void:
	var frozen_versions: Dictionary = Game.run.frozen_versions.duplicate(true)
	for version: int in [Numbers.LEGACY,Numbers.V2]:
		Game.run.frozen_versions["ruleset_version"] = version
		for bonus: float in [0.0,0.25]:
			for hero: String in Catalog.HEROES:
				var actor: Node2D = fixture(hero)
				Game.run.stats = StatResolver.resolve(hero,8,{}, {},version)
				Game.run.stats.resource_gain_bonus = bonus
				Game.run.resource = float(Game.run.stats.resource_max)-1.0
				var kit: RefCounted = load(Catalog.KIT_PATHS[hero]).new()
				kit.configure(actor)
				if hero == "CH03": kit.starlight = 3
				var hud: Dictionary = kit.hud_state()
				check(not str(hud.name_en).is_empty() and not str(hud.description_en).is_empty() and not str(hud.hint_en).is_empty(), "role HUD has actual English fields "+hero+"/"+str(version)+"/"+str(bonus))
				if hero == "CH01":
					var matches := true
					for base: int in [10,8,5]: matches = matches and str(hud.description).contains("+%d怒" % int(Numbers.amount(float(Numbers.scale(base,version))*(1.0+bonus if version == Numbers.V2 else 1.0),version)))
					check(matches and str(hud.hint).contains("衰减%d怒" % int(Numbers.scale(10,version))), "war HUD potential gains scale, while decay excludes gain bonus")
				elif hero == "CH03":
					var refund: int = int(Numbers.amount(float(Numbers.scale(10,version))*(1.0+bonus if version == Numbers.V2 else 1.0),version))
					check(str(hud.description).contains("回复%d法力" % refund) and str(hud.hint).contains("回%d法力" % refund) and int(hud.max) == 3 and float(hud.decay_duration) == 8.0 and float(hud.chorus_multiplier) == 1.25, "mage HUD refund matches units and gain; stacks, time and percentage stay fixed")
				else:
					check(str(hud.description).contains("8发") and str(hud.description).contains("1.0秒") and str(hud.description).contains("45%–65%") and str(hud.description).contains("三发"), "gunner magazine, seconds, precision percentage and empowered rounds stay unscaled")
				actor.free()
	Game.run.frozen_versions = frozen_versions

func _warrior() -> void:
	var actor: Node2D = fixture("CH01")
	var kit: RefCounted = load(Catalog.KIT_PATHS.CH01).new()
	kit.configure(actor)
	Game.run.resource = 0
	var original := {"root_event_id":"fixture:basic:1", "original_basic":true, "proc_depth":0, "equipment_eligible":true}
	var absorbed := {"confirmed":true, "hp_damage":0.0, "shield_damage":units(1)}
	kit.on_original_hit(null, original, absorbed)
	check(is_equal_approx(float(Game.run.resource), units(10)), "shield-only primary gives ten rage")
	kit.on_original_hit(null, original, absorbed)
	check(is_equal_approx(float(Game.run.resource), units(10)), "multi-target primary root gives rage once")
	var derived: Dictionary = original.duplicate()
	derived.root_event_id = "fixture:derived"
	derived.proc_depth = 1
	kit.on_original_hit(null, derived, absorbed)
	check(is_equal_approx(float(Game.run.resource), units(10)), "derived damage cannot grant rage")
	kit.on_original_hit(null, {"root_event_id":"fixture:immune", "original_basic":true}, {"confirmed":false, "hp_damage":0.0, "shield_damage":0.0})
	check(is_equal_approx(float(Game.run.resource), units(10)), "immune and zero-loss contacts cannot grant rage")
	var spell := {"root_event_id":"fixture:cast:1", "skill_id":"CH01_SK01", "original_basic":false, "branch":"B", "proc_depth":0, "equipment_eligible":true}
	kit.on_original_hit(null, spell, absorbed)
	kit.on_original_hit(null, spell, absorbed)
	check(is_equal_approx(float(Game.run.resource), units(28)), "first skill hit grants eight plus branch ten once")
	kit.on_hurt(units(1), {})
	kit.on_hurt(units(1), {})
	check(is_equal_approx(float(Game.run.resource), units(33)), "incoming damage gives five rage at most once per second")
	kit.tick(1.0)
	kit.on_hurt(units(1), {})
	check(is_equal_approx(float(Game.run.resource), units(38)), "incoming rage recovers after exactly one second")
	Game.run.resource = float(Game.run.stats.resource_max) - units(10)
	original.root_event_id = "fixture:full"
	kit.on_original_hit(null, original, absorbed)
	check(is_equal_approx(float(kit.berserk_remaining), 8.0), "confirmed full rage starts eight-second berserk")
	check(is_equal_approx(kit.primary_damage_multiplier(), 1.2) and is_equal_approx(kit.attack_speed_multiplier(), 1.25) and is_equal_approx(kit.movement_multiplier(), 1.1), "berserk exposes the approved damage, attack-speed and movement gains")
	var frozen: float = kit.primary_damage_multiplier()
	kit.tick(2.0)
	original.root_event_id = "fixture:no-refresh"
	kit.on_original_hit(null, original, absorbed)
	check(is_equal_approx(float(kit.berserk_remaining), 6.0), "more rage never refreshes berserk duration")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(kit.export_state()))
	var restored: RefCounted = load(Catalog.KIT_PATHS.CH01).new()
	restored.configure(actor)
	restored.restore_state(saved)
	check(same_values(restored.export_state(), saved), "JSON-only state retains rage timers and dedup ledger")
	kit.tick(6.0)
	check(is_equal_approx(float(kit.berserk_remaining), 0.0) and is_equal_approx(float(kit.berserk_rearm_remaining), 3.0), "berserk ends into the three-second rearm lock")
	check(is_equal_approx(frozen, 1.2) and is_equal_approx(kit.primary_damage_multiplier(), 1.0), "an attack's captured multiplier remains unchanged after berserk ends")
	original.root_event_id = "fixture:locked"
	kit.on_original_hit(null, original, absorbed)
	check(float(kit.berserk_remaining) == 0.0, "full rage cannot retrigger during lock")
	kit.tick(3.0)
	check(float(kit.berserk_remaining) == 0.0, "timer expiry alone does not trigger berserk")
	original.root_event_id = "fixture:retrigger"
	kit.on_original_hit(null, original, absorbed)
	check(is_equal_approx(float(kit.berserk_remaining), 8.0), "next valid event retriggers even when rage remained full")
	check(Game.run.shield == 0, "original hits do not retain the old three-hit shield")
	Game.run.resource = units(100)
	actor.combat_time = 5.0
	actor._tick_resources(4.9)
	check(is_equal_approx(float(Game.run.resource), units(100)), "rage stays intact through the five-second combat grace")
	actor._tick_resources(0.6)
	check(is_equal_approx(float(Game.run.resource), units(95)), "only the half-second after combat grace decays at ten per second")
	for index: int in 60:
		actor._tick_resources(1.0 / 60.0)
	check(is_equal_approx(float(Game.run.resource), units(85)), "fractional decay is independent of sixty frame subdivisions")
	actor.free()

func _gunner() -> void:
	var actor: Node2D = fixture("CH02")
	var kit: RefCounted = load(Catalog.KIT_PATHS.CH02).new()
	kit.configure(actor)
	check(int(kit.ammo) == 8 and int(kit.enhanced_shots) == 0 and not kit.request_reload(), "new gunner starts full and ignores unnecessary manual reload")
	var energy: float = float(Game.run.resource)
	for index: int in 8:
		check(kit.can_primary(), "ordinary magazine permits round " + str(index + 1))
		kit.primary_damage_multiplier()
		kit.on_primary_created()
	check(int(kit.ammo) == 0 and bool(kit.reloading) and not kit.can_primary(), "eighth successful projectile starts auto reload and blocks primary")
	check(float(Game.run.resource) == energy, "primary magazine does not consume skill energy")
	kit.tick(0.999)
	check(bool(kit.reloading) and int(kit.ammo) == 0, "normal reload does not fill early")
	kit.tick(0.001)
	check(not bool(kit.reloading) and int(kit.ammo) == 8 and int(kit.enhanced_shots) == 0, "normal reload finishes exactly at one second")
	for edge: float in [0.45, 0.65]:
		kit.configure(actor)
		kit.on_primary_created()
		check(kit.request_reload(), "manual reload starts with a nonfull magazine")
		kit.tick(edge)
		check(kit.request_reload() and int(kit.ammo) == 8 and int(kit.enhanced_shots) == 3 and not bool(kit.reloading), "precision window includes boundary " + str(edge))
	kit.on_primary_created()
	check(is_equal_approx(kit.primary_damage_multiplier(), 1.2), "enhancement snapshots twenty-percent primary damage")
	var ammo: int = int(kit.ammo)
	var boosted: int = int(kit.enhanced_shots)
	kit.primary_damage_multiplier()
	check(int(kit.ammo) == ammo and int(kit.enhanced_shots) == boosted, "a failed projectile creation consumes neither ammo nor enhancement")
	kit.on_primary_created()
	check(int(kit.ammo) == ammo - 1 and int(kit.enhanced_shots) == boosted - 1, "only successful creation spends the captured enhanced shot")
	kit.configure(actor)
	kit.on_primary_created()
	kit.request_reload()
	kit.tick(0.449)
	check(kit.request_reload() and bool(kit.precision_attempted), "early precision attempt fails once")
	kit.tick(0.101)
	check(not kit.request_reload() and bool(kit.reloading) and int(kit.enhanced_shots) == 0, "failed attempt cannot try again inside the window")
	kit.on_dash_finished(false)
	check(bool(kit.reloading) and int(kit.ammo) == 7, "failed dash cannot cancel reload or refill")
	kit.on_dash_finished(true)
	check(not bool(kit.reloading) and int(kit.ammo) == 8 and int(kit.enhanced_shots) == 0, "successful dash cancels reload and clamps ordinary refill at eight")
	kit.configure(actor)
	for index: int in 6:
		kit.on_primary_created()
	kit.request_reload()
	kit.tick(0.3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(kit.export_state()))
	var restored: RefCounted = load(Catalog.KIT_PATHS.CH02).new()
	restored.configure(actor)
	check(bool(restored.restore_state(saved)) and same_values(restored.export_state(), saved), "same-room JSON restore retains two rounds and partial reload")
	restored.on_room_changed()
	check(int(restored.ammo) == 2 and not bool(restored.reloading), "room transition cancels progress without free full magazine")
	var serial: int = int(kit.reload_serial)
	kit.on_skill_release({"cast_id":1, "skill_id":"CH02_SK10"})
	check(int(kit.ammo) == 8 and int(kit.enhanced_shots) == 3 and not bool(kit.reloading), "actual tactical release fills the magazine and sets three enhanced rounds")
	check(not bool(kit._finish_reload(serial, true)), "late completion for cancelled reload serial is ignored")
	kit.on_skill_release({"cast_id":2, "skill_id":"CH02_SK10"})
	check(int(kit.enhanced_shots) == 3, "repeated tactical gains set three instead of stacking six")
	actor.free()

func _mage() -> void:
	var actor: Node2D = fixture("CH03")
	var kit: RefCounted = load(Catalog.KIT_PATHS.CH03).new()
	kit.configure(actor)
	check(actor.get_child_count() == 1 and actor.get_child(0).name == "StarCompanion", "mage owns one fixed companion")
	kit.configure(actor)
	check(actor.get_child_count() == 1, "reconfiguration reuses the single companion")
	check(int(kit.starlight) == 0, "a prepared or cancelled windup has not called release and gains no star")
	kit.on_skill_release({"cast_id":1, "skill_id":"CH03_SK01", "combat":false})
	check(int(kit.starlight) == 0, "out-of-combat release gains no starlight")
	for serial: int in [2, 3, 4]:
		var modifier: Dictionary = kit.on_skill_release({"cast_id":serial, "skill_id":"CH03_SK01", "combat":true})
		check(is_equal_approx(float(modifier.damage_multiplier), 1.0), "building starlight does not prematurely boost spell " + str(serial))
	check(int(kit.starlight) == 3, "third actual release readies chorus")
	Game.run.resource = units(50)
	var empowered: Dictionary = kit.on_skill_release({"cast_id":5, "skill_id":"CH03_SK03", "combat":true})
	check(int(kit.starlight) == 0 and bool(empowered.chorus) and is_equal_approx(float(empowered.damage_multiplier), 1.25) and is_equal_approx(float(empowered.shield_multiplier), 1.25), "next release consumes three stars and freezes damage and shield gain")
	check(is_equal_approx(float(Game.run.resource), units(60)), "chorus restores exactly ten mana")
	check(kit.on_skill_release({"cast_id":5, "skill_id":"CH03_SK03", "combat":true}) == empowered and is_equal_approx(float(Game.run.resource), units(60)), "repeated pulse callback reuses frozen modifier without repeat refund")
	kit.on_skill_release({"cast_id":6, "skill_id":"CH03_SK01", "combat":true})
	kit.tick(7.999)
	check(int(kit.starlight) == 1, "star survives the final millisecond of eight-second grace")
	kit.tick(0.001)
	check(int(kit.starlight) == 0, "starlight fades after exactly eight seconds without a release")
	kit.on_skill_release({"cast_id":7, "skill_id":"CH03_SK10", "combat":true})
	check(int(kit.starlight) == 2 and is_equal_approx(float(kit.echo_remaining), 6.0), "dual-star release provides one ordinary and one extra layer plus six-second echo")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(kit.export_state()))
	var restored: RefCounted = load(Catalog.KIT_PATHS.CH03).new()
	restored.configure(actor)
	check(bool(restored.restore_state(saved)) and same_values(restored.export_state(), saved), "mage JSON-only state restores starlight, release cursor and echo")
	actor.free()

func _live_skill_matrix() -> void:
	# These fixtures deliberately equip each identity to Q in a detached combat
	# session. The actual room resolves casts, collision, packets and deployments.
	for group: String in ["SG01", "SG02", "SG03", "SG04", "SG05", "SG06", "SG07", "SG08"]:
		check(bool(Game.grant_skill_group(group, "fixture:matrix:" + group).ok), "matrix owns learned group " + group)
	for hero: String in Catalog.HEROES:
		for entry: Dictionary in Catalog.skills(hero):
			var detached: Node2D = fixture(hero)
			detached.free()
			var identity: String = str(entry.skill_id)
			var configured: Array[String] = [identity]
			for starter: String in Catalog.starter_ids(hero):
				if starter != identity and configured.size() < 4:
					configured.append(starter)
			Game.run.skill_loadout_snapshot = configured
			Game.run.stats["skill_loadout"] = configured.duplicate()
			Game.run.stats["crit_chance"] = 0.0
			var room: Node2D = RoomScene.instantiate()
			room.process_mode = Node.PROCESS_MODE_DISABLED
			room.geometry_enabled = false
			get_tree().root.add_child(room)
			room.spawn_enabled = false
			room.release_gate = false
			room.input_blocked = false
			room.combat_audio.audible = false
			for child: Node in room.enemies.get_children():
				child.free()
			var actor: Node2D = room.player
			actor.position = Vector2(1100, 750)
			actor.aim_direction = Vector2.RIGHT
			var offset: float = 150.0 if identity == "CH01_SK01" else 70.0
			var target: Node2D = room.spawn_enemy(actor.position + Vector2(offset, 0), "M01", 1)
			target.health.reset(1000000.0)
			target.armor = 0.0
			target.magic_resist = 0.0
			target.reward_enabled = false
			target.training_ai_disabled = true
			if hero == "CH02":
				actor.role_kit.ammo = 1
			var at: Vector2 = target.position
			var spec: Dictionary = actor.abilities.spec("q")
			var audio_slot: String = str(spec.get("audio_slot", spec.get("origin_slot", "")))
			check(Audio.stream_for(hero, "prepare_" + audio_slot) != null and Audio.stream_for(hero, audio_slot) != null and Audio.skill_music_stream_for(hero, audio_slot) != null, identity + " maps preparation, release and motif to valid authored PCM")
			room.combat_audio.audible = false
			room.combat_audio.set_process(false)
			var cues: Array[String] = []
			var motifs: Array[String] = []
			room.combat_audio.cue_played.connect(func(cue: String): cues.append(cue))
			room.combat_audio.skill_music_played.connect(func(_hero: String, slot: String): motifs.append(slot))
			check(str(spec.get("skill_id", "")) == identity, identity + " follows its identity after moving to Q")
			var before: float = float(Game.run.resource)
			var cost: float = float(spec.get("cost", 0.0))
			var hp: float = float(target.health.current)
			var origin: Vector2 = actor.position
			var progress_before: int = int(Game.get_skill_progress(hero, identity).get("xp", 0))
			check(actor.cast_skill("q", at), identity + " commits a cancellable preparation")
			actor.abilities.tick(maxf(0.001, float(spec.get("windup", 0.1)) * 0.5))
			actor.abilities.cancel()
			actor.abilities.tick(8.0)
			check(float(target.health.current) == hp and float(Game.run.shield) == 0.0 and room.projectiles.get_child_count() == 0, identity + " cancellation before release creates no damage, guard or projectile")
			check(int(Game.get_skill_progress(hero, identity).get("xp", 0)) == progress_before, identity + " cancelled windup earns no mastery")
			check(cues.count("prepare_" + audio_slot) == 1 and cues.count(audio_slot) == 0 and motifs.is_empty(), identity + " cancelled preparation produces no release sound or motif")
			check(is_equal_approx(before - float(Game.run.resource), cost) and float(actor.cooldowns.get(identity, -1.0)) > 0.0, identity + " cancellation retains its committed payment and identity cooldown")
			Game.run.resource = before
			actor.cooldowns[identity] = 0.0
			room.combat_audio.advance(8.0)
			cues.clear()
			check(actor.cast_skill("q", at), identity + " commits through the real four-slot cast entry")
			check(is_equal_approx(before - float(Game.run.resource), cost), identity + " pays resource exactly once at commitment")
			check(float(actor.cooldowns.get(identity, -1.0)) > 0.0, identity + " starts a cooldown under skill identity")
			check(not actor.abilities.try_cast("q", at), identity + " cannot pay a second time while the same cast is active")
			check(is_equal_approx(before - float(Game.run.resource), cost), identity + " rejected repeated input spends nothing")
			var best_guard: float = 0.0
			var first_release_seen := false
			var mage_feedback := {"chorus":false, "moving_center":false, "depart":false, "arrive":false}
			var observed_release_events: int = actor.abilities.feedback.release_events.size()
			for frame: int in 350:
				if identity == "CH03_SK11" and frame == 40:
					actor.position += Vector2(20,15)
				room.combat_audio.advance(0.02)
				actor.abilities.tick(0.02)
				for effect: Dictionary in actor.abilities.feedback.effects:
					if str(effect.kind) == "chorus": mage_feedback.chorus = true
					if identity == "CH03_SK12" and str(effect.kind) == "blink_depart":
						mage_feedback.depart = Vector2(effect.at).is_equal_approx(origin)
					if identity == "CH03_SK12" and str(effect.kind) == "blink_arrive":
						mage_feedback.arrive = Vector2(effect.at).is_equal_approx(actor.position)
				if identity == "CH03_SK11" and actor.abilities.feedback.release_events.size() > observed_release_events:
					var latest: Dictionary = actor.abilities.feedback.effects.back()
					check(str(latest.kind) == "dome_wave" and Vector2(latest.at).is_equal_approx(actor.position), "new moving star pulse feedback uses its actual current body center")
					mage_feedback.moving_center = true
				observed_release_events = actor.abilities.feedback.release_events.size()
				best_guard = maxf(best_guard, float(Game.run.shield))
				for child: Node in room.get_children():
					if child != actor and child.has_method("advance") and not child.is_queued_for_deletion():
						child.advance(0.02)
				for child: Node in room.projectiles.get_children():
					if not child.is_queued_for_deletion():
						child._physics_process(0.02)
				first_release_seen = first_release_seen or int(Game.get_skill_progress(hero, identity).get("xp", 0)) > progress_before
				if frame % 25 == 24:
					await get_tree().process_frame
			check(first_release_seen, identity + " emits one actual release and permanent mastery")
			var gained: int = int(Game.get_skill_progress(hero, identity).get("xp", 0)) - progress_before
			check(gained == clampi(int(ceilf(float(entry.base_cooldown) / 4.0)), 1, 12), identity + " multi-stage effects grow mastery once")
			check(not actor.abilities.busy(), identity + " finite timeline completes")
			check(cues.count(audio_slot) == actor.role_kit.timeline(spec).size() and motifs.size() == 1 and motifs[0] == audio_slot, identity + " finite release cadence emits one motif and one sound per actual event")
			var guard_skill: bool = identity in ["CH01_SK03", "CH01_SK06", "CH01_SK10", "CH03_SK03", "CH03_SK06"]
			var utility_skill: bool = identity in ["CH02_SK06", "CH02_SK10", "CH03_SK10"]
			if guard_skill:
				check(best_guard > 0.0, identity + " actually creates its authored guard")
			if not utility_skill and not identity in ["CH01_SK06", "CH01_SK10", "CH03_SK06"]:
				check(float(target.health.current) < hp, identity + " produces actual confirmed damage")
			if identity == "CH02_SK06":
				check(actor.position.distance_to(origin) >= 100.0 and actor.status.has("damage_reduction"), "smoke step moves and grants its one-second reduction")
			elif identity == "CH02_SK10":
				check(int(actor.role_kit.ammo) == 8 and int(actor.role_kit.enhanced_shots) == 3, "tactical reload acts at real first release")
			elif identity == "CH03_SK10":
				check(int(actor.role_kit.starlight) == 2, "dual-star effect actually adds its extra layer")
				check(mage_feedback.chorus, "dual-star release emits its real chorus feedback")
			elif identity == "CH03_SK11":
				check(mage_feedback.moving_center, "moving star patrol emits actual body-centered pulses")
			elif identity == "CH03_SK12":
				check(mage_feedback.depart and mage_feedback.arrive, "star blink distinguishes origin pulse and destination flash")
			if hero == "CH03":
				check(actor.find_children("StarCompanion", "Node2D", false, false).size() == 1, identity + " reuses the one fixed companion")
			if identity in ["CH02_SK01", "CH03_SK01"]:
				await _primary_creation_boundary(room, hero)
			if identity == hero + "_SK01":
				_relic_core(room, hero, target)
			if identity == "CH03_SK04":
				await _mage_delayed_echo(room, target)
			await room.combat_audio.wait_for_cleanup()
			room.free()

func _feel_regressions() -> void:
	for hero: String in Catalog.HEROES:
		fixture(hero).free()
		var room: Node2D = RoomScene.instantiate()
		room.process_mode = Node.PROCESS_MODE_DISABLED
		room.geometry_enabled = false
		get_tree().root.add_child(room)
		room.spawn_enabled = false
		room.release_gate = false
		room.input_blocked = false
		room.combat_audio.audible = false
		for child: Node in room.enemies.get_children(): child.free()
		var actor: Node2D = room.player
		actor.position = Vector2(1100,750)
		var target: Node2D = room.spawn_enemy(actor.position + Vector2(70,0), "M01", 1)
		target.training_ai_disabled = true
		target.health.reset(1000000, 2)
		if hero == "CH01":
			var off_axis: Node2D = room.spawn_enemy(actor.position + Vector2(0,-70), "M01", 1)
			off_axis.training_ai_disabled = true
			off_axis.health.reset(1000000, 2)
			actor.aim_direction = Vector2.RIGHT
			check(actor.fire(Vector2.RIGHT), "warrior starts a legal right-facing basic windup")
			actor.aim_direction = Vector2.UP
			actor._tick_attack(.13)
			check(float(target.health.current) < 1000000 and float(off_axis.health.current) == 1000000, "changing pointer during windup never turns the committed melee cone")
			check(actor._attack_direction.is_equal_approx(Vector2.RIGHT) and actor.abilities.feedback.pose_state().direction.is_equal_approx(Vector2.RIGHT), "basic start, release pose and actual hit direction agree")
		else:
			var original_position: Vector2 = target.position
			for source: StringName in [&"primary", &"child"]:
				check(target.take_damage(10, source, Vector2.RIGHT, {"ruleset_version":2,"damage_type":"true","attacker_stats":Game.run.stats,"original_basic":source == &"primary","equipment_eligible":false,"proc_depth":0}), hero + " light packet consumes real HP")
			check(target.knockback.is_zero_approx() and target.pending_displacement().is_zero_approx() and target.position.is_equal_approx(original_position), hero + " light projectile packets add no generic physical push")
		var pauses: Dictionary = {"CH01":{"secondary":.055,"ultimate":.065},"CH02":{"secondary":.035},"CH03":{"secondary":.032,"f":.045,"ultimate":.045}}
		for origin_slot: String in pauses[hero]:
			for input_slot: String in Catalog.INPUT_SLOTS:
				room._contact_pulse_until = -1.0
				room._contact_pulse_heavy = false
				actor.visual_hitstop = 0.0
				target.body_visual._contact_hold_remaining = 0.0
				room._confirm_contact(target, Vector2.RIGHT, &"skill", false, 10, false, {"skill_slot":origin_slot,"input_slot":input_slot})
				check(is_equal_approx(actor.visual_hitstop, float(pauses[hero][origin_slot])) and is_equal_approx(target.body_visual._contact_hold_remaining, actor.visual_hitstop), hero + " same frozen origin hitstop on both bodies after moving " + origin_slot + " into " + input_slot)
		var reduced_before: bool = bool(Game.profile.settings.get("reduced_fx",false))
		Game.profile.settings.reduced_fx = true
		room._contact_pulse_until = -1.0
		actor.visual_hitstop = 0.0
		target.body_visual._contact_hold_remaining = 0.0
		room._confirm_contact(target, Vector2.RIGHT, &"skill", false, 10, false, {"skill_slot":"ultimate"})
		check(actor.visual_hitstop == 0.0 and target.body_visual._contact_hold_remaining == 0.0, hero + " reduced effects suppress both presentation holds")
		Game.profile.settings.reduced_fx = reduced_before
		if hero == "CH02":
			var fx: Node = actor.abilities.feedback
			fx.effects.clear()
			actor.role_kit.configure(actor)
			for index: int in 8: actor.role_kit.on_primary_created()
			actor.role_kit.tick(1.0)
			actor.role_kit.on_primary_created()
			actor.role_kit.request_reload()
			actor.role_kit.tick(.5)
			actor.role_kit.request_reload()
			actor.role_kit.on_primary_created()
			actor.role_kit.request_reload()
			actor.role_kit.tick(.2)
			actor.role_kit.request_reload()
			actor.role_kit.request_reload()
			actor.role_kit.tick(.8)
			var kinds: Array[String] = []
			for effect: Dictionary in fx.effects: kinds.append(str(effect.kind))
			check(kinds.count("reload_start") == 3 and kinds.count("reload_complete") == 2 and kinds.count("reload_success") == 1 and kinds.count("reload_missed") == 1, "automatic, normal, precise and failed reloads each emit one real event; repeated failure emits none")
		room.free()

func _primary_creation_boundary(room: Node2D, hero: String) -> void:
	var actor: Node2D = room.player
	var fillers: Array[Node2D] = []
	while room.projectiles.get_child_count() < Balance.MAX_PROJECTILES:
		var filler := Node2D.new()
		room.projectiles.add_child(filler)
		fillers.append(filler)
	actor.shot_cooldown = 0.0
	if hero == "CH02":
		actor.role_kit.ammo = 8
		actor.role_kit.enhanced_shots = 3
	var shots: int = int(Game.run.shots)
	check(not actor.fire(Vector2.UP), hero + " actual capped projectile creation rejects a primary")
	check(int(Game.run.shots) == shots and actor.shot_cooldown == 0.0, hero + " failed creation restores ordinary shot commitment")
	if hero == "CH02":
		check(int(actor.role_kit.ammo) == 8 and int(actor.role_kit.enhanced_shots) == 3, "actual failed gunner projectile consumes no ammo or enhanced round")
	else:
		actor.role_kit.starlight = 3
		actor.role_kit.decay_remaining = 8.0
		var progress: int = int(Game.get_skill_progress(hero, "CH03_SK01").xp)
		actor.cooldowns["CH03_SK01"] = 0.0
		Game.run.resource = Game.run.stats.resource_max
		check(actor.abilities.try_cast("q", actor.position + Vector2.UP * 70), "capped mage spell still commits a normal preparation")
		actor.abilities.tick(1.0)
		check(int(actor.role_kit.starlight) == 3 and int(Game.get_skill_progress(hero, "CH03_SK01").xp) == progress, "failed first actual effect cannot consume chorus or grant mastery")
	for filler: Node2D in fillers:
		filler.free()
	actor.shot_cooldown = 0.0
	check(actor.fire(Vector2.UP), hero + " uncapped real primary creates one projectile")
	check(int(Game.run.shots) == shots + 1, hero + " one primary pipeline records exactly one shot")
	if hero == "CH02":
		check(int(actor.role_kit.ammo) == 7 and int(actor.role_kit.enhanced_shots) == 2, "successful real gunner creation consumes one ordinary and one enhanced round")
	await get_tree().process_frame

func _mage_delayed_echo(room: Node2D, target: Node2D) -> void:
	var actor: Node2D = room.player
	Game.run.skill_loadout_snapshot.assign(["CH03_SK04", "CH03_SK10", "CH03_SK02", "CH03_SK03"])
	Game.run.stats.skill_loadout = Game.run.skill_loadout_snapshot.duplicate()
	actor.skill_loadout.assign(Game.run.skill_loadout_snapshot)
	actor.role_kit.reset()
	Game.run.resource = Game.run.stats.resource_max
	actor.cooldowns.CH03_SK10 = 0.0
	actor.cooldowns.CH03_SK04 = 0.0
	check(actor.abilities.try_cast("secondary", actor.position), "dual-star arms echo through its actual equipped input")
	actor.abilities.tick(0.5)
	var armed: Dictionary = actor.role_kit.export_state()
	var echo_power: float = float(armed.echo_power)
	var at: Vector2 = actor.position + Vector2.RIGHT * 200
	target.position = at + Vector2.RIGHT * 500
	var xp_before: int = int(Game.get_skill_progress("CH03", "CH03_SK04").xp)
	check(actor.abilities.try_cast("q", at), "wish garden commits after dual-star")
	actor.abilities.tick(0.8)
	var field: Node2D
	for child: Node in room.get_children():
		if child.get("kind") == "field" and not child.is_queued_for_deletion():
			field = child
	check(is_instance_valid(field) and float(actor.role_kit.echo_remaining) > 0.0, "empty initial explosion preserves echo until an authored field pulse hits")
	if is_instance_valid(field):
		target.position = field.position
		var hp: float = float(target.health.current)
		field.advance(1.0)
		var first: float = hp - float(target.health.current)
		check(is_equal_approx(first, float(field.damage) + float(Numbers.amount(echo_power * 0.8, Game.run.ruleset_version()))), "first valid field pulse adds exactly one frozen dual-star echo")
		check(float(actor.role_kit.echo_remaining) == 0.0, "field's class-only receipt consumes echo once")
		hp = float(target.health.current)
		field.advance(1.0)
		check(is_equal_approx(hp - float(target.health.current), float(field.damage)), "later pulse cannot repeat dual-star echo")
		check(int(Game.get_skill_progress("CH03", "CH03_SK04").xp) - xp_before == 8, "field pulses and echo keep exactly one mastery release")
		actor.role_kit.on_skill_release({"cast_id":actor.abilities.cast_serial + 100, "skill_id":"CH03_SK10", "combat":true, "power":echo_power})
		var derived: Node2D = room.add_deployment("field", target.position, {"owner_player":actor, "skill_id":"CH03_SK04", "cast_id":actor.abilities.cast_serial + 101, "damage_source":"equipment", "proc_depth":1, "damage":10.0, "lifetime":2.0, "radius":80.0})
		derived.advance(1.0)
		check(float(actor.role_kit.echo_remaining) > 0.0, "equipment-derived field cannot send an authored class receipt or consume echo")
	await get_tree().process_frame

func _equipment_identity() -> void:
	var effects: RefCounted = load("res://scripts/domain/combat/equipment_effects.gd").new()
	var stats := {"ruleset_version":2, "scale_version":10, "max_hp":1000, "attack":200, "resource_max":1000}
	effects.configure({}, stats, "rage")
	var original := {"source":&"skill", "skill_id":"CH01_SK05", "input_slot":"secondary", "equipment_eligible":true, "original":true, "derived":false, "original_basic":false, "proc_depth":0, "target_id":"fixture:enemy", "confirmed":true, "valid_target":true, "H":200.0, "X":200.0, "hp":1000, "max_hp":1000, "shield":100.0, "remaining_cooldowns":{"CH01_SK05":2.0, "CH01_SK12":6.0, "q":9.0, "dash":8.0}}
	check(bool(effects._eligible(original)), "new stable skill with source StringName participates in equipment original hits")
	for field: String in ["original", "derived", "proc_depth"]:
		var excluded: Dictionary = original.duplicate(true)
		excluded[field] = false if field == "original" else true if field == "derived" else 1
		check(not bool(effects._eligible(excluded)), "derived chain is excluded by " + field)
	effects.set_counts = {"S11":6}
	var result: Dictionary
	for index: int in 4:
		var paid: Dictionary = original.duplicate(true)
		paid.merge({"root_event_id":"fixture:paid:" + str(index), "attack_id":"fixture:paid:" + str(index), "skill_id":"CH01_SK%02d" % (index + 5), "base_cost":20.0, "paid_cost":20.0, "cast_success":true, "resource_type":"rage"}, true)
		result = effects.handle("skill_cast", paid)
		check(result.cooldown_refunds.size() == (1 if index == 3 else 0), "four distinct paid stable skills count once at cast " + str(index + 1))
		effects.handle("skill_cast", paid)
	check(result.cooldown_refunds.size() == 1 and str(result.cooldown_refunds[0].get("skill_id", "")) == "CH01_SK12" and is_equal_approx(float(result.cooldown_refunds[0].seconds), 0.35), "paid-cast refund selects the longest stable skill and ignores input labels and dash")
	effects.configure({}, stats, "rage")
	effects.set_counts = {"S06":6}
	var shielded: Dictionary = original.duplicate(true)
	shielded.merge({"attack_id":"fixture:berserk", "root_event_id":"fixture:berserk", "base_power":200.0, "berserk_active":true, "shielded_cast":true, "nearby_targets":[{"id":"fixture:enemy", "distance":0.0}, {"id":"fixture:second", "distance":20.0}, {"id":"fixture:third", "distance":40.0}, {"id":"fixture:fourth", "distance":60.0}]}, true)
	var burst: Dictionary = effects.handle("after_hit", shielded)
	check(burst.bonus_hits.size() == 1 and burst.bonus_hits[0].target_ids.size() <= 3, "shielded berserk set targets at most three enemies in one finite command")
	for packet: Dictionary in burst.bonus_hits:
		var total: float = 0.0
		for amount: Variant in packet.get("damage_by_target", {}).values():
			total += float(amount)
			check(float(amount) > 0.0 and float(amount) <= 120.0, "berserk derived target retains its authored maximum 0.6H")
		check(total <= 240.0, "berserk derived targets share the existing 1.2H root budget")
	effects.configure({}, stats, "rage")
	effects.set_counts = {"S06":6}
	shielded.attack_id = "fixture:obsolete"
	shielded.root_event_id = "fixture:obsolete"
	shielded.berserk_active = false
	shielded.full_break_w = true
	check(effects.handle("after_hit", shielded).bonus_hits.is_empty(), "old full-break flag cannot enable the new berserk set")
	effects.configure({}, stats, "energy")
	effects.set_counts = {"B05-SG":4, "B06-SG":2}
	var moved: Dictionary = original.duplicate(true)
	moved.merge({"attack_id":"fixture:rail-q", "root_event_id":"fixture:rail-q", "skill_id":"CH02_SK02", "input_slot":"q", "empowered_round":true, "H_skill":200.0, "b05_pierce_targets":[{"id":"fixture:pierce", "distance":30.0, "alive":true}]}, true)
	check(is_equal_approx(float(effects.handle("before_hit", moved).damage_bonus), 0.16), "B06 rail bonus follows SK02 when moved to Q alongside generic empowered bonus")
	check(effects.handle("after_hit", moved).bonus_hits.size() == 1, "B05 rail pierce follows SK02 when moved to Q")
	moved.attack_id = "fixture:fan-secondary"
	moved.root_event_id = "fixture:fan-secondary"
	moved.skill_id = "CH02_SK05"
	moved.input_slot = "secondary"
	check(is_equal_approx(float(effects.handle("before_hit", moved).damage_bonus), 0.08) and effects.handle("after_hit", moved).bonus_hits.is_empty(), "SK05 retains only generic empowered bonus and cannot borrow B05 or B06 rail-only benefits")

func _relic_core(room: Node2D, hero: String, target: Node2D) -> void:
	var relics: Script = load("res://scripts/domain/combat/class_relics.gd")
	var actor: Node2D = room.player
	Game.run.resource = units(30)
	if hero == "CH02":
		actor.role_kit.ammo = 2
		actor.role_kit.enhanced_shots = 1
		actor.role_kit.request_reload()
		actor.role_kit.tick(0.3)
	elif hero == "CH03":
		actor.role_kit.starlight = 0
		actor.role_kit.decay_remaining = 0.0
	var packet := {"root_event_id":"fixture:RL03:" + hero, "attack_id":"fixture:RL03:" + hero, "original":true, "derived":false, "original_basic":true, "equipment_eligible":true, "proc_depth":0, "source":&"primary", "damage_source":"primary"}
	check(bool(relics.apply_reserved(room, {"arc":0.35}, packet, target.position, target, Vector2.RIGHT)), hero + " RL03 emits its mapped real class command")
	if hero == "CH01":
		check(Game.run.shield > 0 and float(Game.run.resource) == units(40) and actor.break_stacks == 0, "warrior RL03 gives guard and ten rage with no retired break stack")
	elif hero == "CH02":
		check(int(actor.role_kit.ammo) == 3 and int(actor.role_kit.enhanced_shots) == 1 and bool(actor.role_kit.reloading) and is_equal_approx(float(actor.role_kit.reload_elapsed), 0.3), "gunner RL03 refills an ordinary round without precision refresh or reload cancellation")
	else:
		check(float(Game.run.resource) == units(33) and int(actor.role_kit.starlight) == 1, "mage RL03 restores three mana and one starlight")
	var saved: Dictionary = actor.role_kit.export_state()
	var resource: float = float(Game.run.resource)
	var hp: float = float(target.health.current)
	check(not bool(relics.apply_reserved(room, {"arc":0.35}, packet, target.position, target, Vector2.RIGHT)) and same_values(actor.role_kit.export_state(), saved) and float(Game.run.resource) == resource and float(target.health.current) == hp, hero + " repeated relic root cannot duplicate class command or derived damage")
	var skill: Dictionary = packet.duplicate(true)
	skill.root_event_id = "fixture:RL03:active:" + hero
	skill.source = &"skill"
	skill.damage_source = "skill"
	check(not bool(relics.apply_reserved(room, {"arc":0.35}, skill, target.position, target, Vector2.RIGHT)), hero + " active skill cannot borrow basic-only relic activation")
	var derived: Dictionary = packet.duplicate(true)
	derived.root_event_id = "fixture:RL03:derived:" + hero
	derived.proc_depth = 1
	derived.derived = true
	check(not bool(relics.apply_reserved(room, {"arc":0.35}, derived, target.position, target, Vector2.RIGHT)), hero + " derived damage cannot recurse into mapped relic command")

func _archives() -> void:
	for id: String in ["L02", "L08", "L11", "L14", "L20"]:
		var detached: Node2D = fixture("CH01")
		detached.free()
		var room: Node2D = RoomScene.instantiate()
		room.process_mode = Node.PROCESS_MODE_DISABLED
		var context := {"room_id":id, "role":"normal", "node_index":1, "biome_id":str(WorldCatalog.room(id).get("biome_id", "B01")), "seed":41827}
		var prepared: Dictionary = room.prepare_expedition_node(context)
		check(bool(prepared.get("valid", false)), id + " real authored room prepares")
		if not bool(prepared.get("valid", false)):
			room.free()
			continue
		room.apply_prepared_expedition_node(prepared)
		get_tree().root.add_child(room)
		room.spawn_enabled = false
		var archive: Dictionary = room.skill_archive()
		check(not archive.is_empty(), id + " archive is present at a legal ground point")
		if not archive.is_empty():
			var at: Vector2 = archive.position
			check(room.valid_ground(at, 18.0), id + " archive has an eighteen-pixel clear footprint")
			check(room.player.click_navigation.request(room.layout.entry, at, 14.0), id + " archive is reachable through the actual click-navigation graph")
			for point: Vector2 in room.player.click_navigation.path:
				check(room.valid_ground(point, 14.0), id + " archived route waypoint remains walkable")
		await room.combat_audio.wait_for_cleanup()
		room.free()

func _catalog() -> void:
	var ids: Dictionary = {}
	for hero: String in Catalog.HEROES:
		var entries: Array[Dictionary] = Catalog.skills(hero)
		check(entries.size() == 12, hero + " has twelve active skills")
		check(Catalog.starter_ids(hero).size() == 4, hero + " starts with four skills")
		for index: int in entries.size():
			var spec: Dictionary = entries[index]
			var id: String = "%s_SK%02d" % [hero, index + 1]
			check(str(spec.get("skill_id", "")) == id and not ids.has(id), id + " has a unique stable identity")
			ids[id] = true
			check(str(spec.get("hero_id", "")) == hero and not str(spec.get("name", "")).is_empty(), id + " has class ownership and a name")
			check(float(spec.get("cost", -1)) >= 0.0 and float(spec.get("cooldown", -1)) > 0.0, id + " has a finite cost/cooldown budget")
			check(is_finite(float(spec.get("cost", INF))) and is_finite(float(spec.get("cooldown", INF))), id + " rejects nonfinite budgets")
			check(Catalog.skill(id) == spec, id + " lookup returns the same detached spec")
			if index >= 4:
				var group: String = "SG%02d" % (index - 3)
				check(str(spec.acquisition_group) == group and id in Catalog.group_skills(group), id + " belongs to the three-class reward group")
	check(ids.size() == 36, "all thirty-six identities exist")
	for index: int in 8:
		var group: String = "SG%02d" % (index + 1)
		check(Catalog.group_skills(group).size() == 3, group + " unlocks one skill per class")
	check(Catalog.skill("CH01_SK99").is_empty() and Catalog.skill("invalid").is_empty(), "unknown skills are rejected")
	check(Catalog.group_skills("SG00").is_empty() and Catalog.group_skills("SG09").is_empty(), "unknown rewards are rejected")

func _finish() -> void:
	print("ROLE KITS: %d checks; failures=%s; module fixture (not natural combat)" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
