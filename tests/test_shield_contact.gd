extends SceneTree
## Deterministic mechanism checks through the real damage/confirmation pipeline.
## No direct calls to _confirm_contact, ImpactFeedback.confirm_hit or audio cues.
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
var game: Node
var room: Node2D
var checks := 0
var failures := 0
var serial := 0
var cues: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SHIELD_CONTACT FAIL: " + label)

func fixture(hero: String = "CH01", reduced: bool = false) -> void:
	if is_instance_valid(room): room.free()
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":.85, "reduced_fx":reduced}, true)
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = Resolver.resolve(hero, 8, {}, {})
	game.run.stats.crit_chance = 0.0
	game.run.stats.true_damage_bonus = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.relics.clear()
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	cues.clear()
	room.combat_audio.cue_played.connect(func(cue: String): cues.append(cue))

func target(shield: float = 0.0) -> Node2D:
	var actor: Node2D = room.spawn_enemy(room.player.position + Vector2(70, 0), "M01", 1, {"reward_enabled":false})
	actor.health.reset(1000.0)
	actor.training_ai_disabled = true
	if shield > 0: check(actor.status.grant_guard(shield, 30.0, "fixture", actor.health.maximum), "real guard is granted")
	return actor

func direct(actor: Node2D, amount: float = 20.0, source: StringName = &"primary", equipment: bool = false) -> bool:
	serial += 1
	return room.resolve_direct_hit(actor, amount, source, "", 0.0, Vector2.RIGHT,
		{"attack_id":"shield-test:" + str(serial), "root_event_id":"shield-test:" + str(serial),
		"damage_type":"true", "attacker_stats":game.run.stats.duplicate(true), "equipment_eligible":equipment})

func derived(actor: Node2D, amount: float = 20.0, source: StringName = &"node") -> void:
	room.resolve_derived_hit(actor, amount, source, Vector2.RIGHT,
		{"damage_type":"true", "attacker_stats":game.run.stats.duplicate(true)})

func contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in room.impact_feedback.events:
		if str(event.get("kind", "")) == "hit": result.append(event)
	return result

func one_contact(label: String, hp_damage: float, shield_damage: float, broken: bool) -> Dictionary:
	var found: Array[Dictionary] = contacts()
	check(found.size() == 1, label + " emits one actual contact")
	if found.size() != 1: return {}
	var hit: Dictionary = found[0]
	check(hit.has("hp_damage") and hit.has("shield_damage") and hit.has("shield_broken"), label + " carries original packet HP/shield fields")
	check(is_equal_approx(float(hit.get("hp_damage", -1)), hp_damage) and is_equal_approx(float(hit.get("shield_damage", -1)), shield_damage), label + " separates actual HP and shield consumption")
	check(bool(hit.get("shield_broken", not broken)) == broken, label + " records exact original-packet shield break")
	check(is_equal_approx(float(hit.get("damage", -1)), hp_damage + shield_damage), label + " contact amount excludes later packets")
	return hit

func shield_cues() -> Array[String]:
	var found: Array[String] = []
	for cue: String in cues:
		if cue.contains("shield"): found.append(cue)
	return found

func absorption_cases() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		for reduced: bool in [false, true]:
			for shape: String in ["absorbed", "overflow", "exact", "body"]:
				fixture(hero, reduced)
				var initial_shield: float = {"absorbed":50.0, "overflow":5.0, "exact":20.0, "body":0.0}[shape]
				var actor: Node2D = target(initial_shield)
				var hp_damage: float = maxf(0, 20.0 - initial_shield)
				var shield_damage: float = minf(initial_shield, 20.0)
				var broken: bool = shape in ["overflow", "exact"]
				var label: String = hero + " " + shape + (" reduced" if reduced else "")
				check(direct(actor), label + " actual packet is confirmed")
				check(is_equal_approx(actor.health.current, 1000.0 - hp_damage) and is_equal_approx(actor.status.shield(), maxf(0, initial_shield - 20.0)), label + " actual target resources match absorption")
				var hit: Dictionary = one_contact(label, hp_damage, shield_damage, broken)
				if hit.is_empty(): continue
				check(str(hit.hero_id) == hero and bool(hit.reduced) == reduced, label + " preserves class identity and reduced-effects choice")
				check(not bool(hit.passive) and str(hit.source) == "primary", label + " keeps original-basic attribution")
				check(shield_cues().size() == (1 if initial_shield > 0 else 0), label + " shield audio only accompanies consumed shield")
				if initial_shield > 0 and not shield_cues().is_empty():
					check(str(shield_cues()[0]).contains("break") == broken, label + " exact exhaustion and overflow both use break cue")

func heavy_and_class_cases() -> void:
	var pauses: Dictionary = {}
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero)
		var actor: Node2D = target(50)
		direct(actor)
		pauses[hero] = room.player.visual_hitstop
		fixture(hero)
		actor = target(5)
		var source: StringName = &"f" if hero == "CH03" else &"secondary"
		direct(actor, 20, source)
		var hit: Dictionary = one_contact(hero + " heavy break", 15, 5, true)
		check(not hit.is_empty() and bool(hit.get("heavy", false)) and room.player.visual_hitstop > float(pauses[hero]), hero + " class heavy action retains stronger contact weight")
	check(float(pauses.CH01) > float(pauses.CH03) and float(pauses.CH03) > float(pauses.CH02), "three classes retain distinct hit-pause weights on shield contact")

func refusal_cases() -> void:
	for kind: String in ["immune", "zero"]:
		fixture()
		var actor: Node2D = target(50)
		if kind == "immune": actor.apply_status("invulnerable", 1, 10)
		check(not direct(actor, 0 if kind == "zero" else 20), kind + " original packet is unconfirmed")
		check(actor.health.current == 1000 and actor.status.shield() == 50 and contacts().is_empty() and cues.is_empty(), kind + " produces no HP/shield loss or contact audio/visual")
		check(room.player.visual_hitstop == 0 and room.camera.impact_stats().started == 0, kind + " creates no camera/pause feedback")

func derived_cases() -> void:
	for source: StringName in [&"node", &"field", &"node_detonation"]:
		fixture("CH03")
		var actor: Node2D = target(5)
		derived(actor, 20, source)
		var hit: Dictionary = one_contact(str(source) + " derived break", 15, 5, true)
		check(not hit.is_empty() and str(hit.get("source", "")) == str(source) and bool(hit.get("passive", false)) == (source != &"node_detonation"), str(source) + " retains derived/passive presentation tier")
		check(not bool(actor.last_damage_context.get("original_basic", true)) and not bool(actor.last_damage_context.get("equipment_eligible", true)) and int(actor.last_damage_context.get("proc_depth", 0)) >= 1, str(source) + " shield break cannot become an equipment/basic root")
		check(cues == (["shield_break"] if source == &"node_detonation" else ["passive_impact"]), str(source) + " break keeps direct/passive cue ownership")
		if source != &"node_detonation": check(room.player.visual_hitstop == 0 and room.camera.impact_stats().started == 0, str(source) + " passive shield hit never starts player hit-pause/camera kick")

func original_packet_isolation() -> void:
	fixture("CH02")
	game.run.stats.true_damage_bonus = 12.0
	var actor: Node2D = target(25)
	check(direct(actor, 20, &"primary", true), "original shield packet confirms before true-damage follow-up")
	check(is_equal_approx(actor.status.shield(), 0) and is_equal_approx(actor.health.current, 993), "later true-damage packet really exhausts remaining 5 shield and consumes 7 HP")
	one_contact("original packet before equipment true damage", 0, 20, false)
	check(shield_cues().size() == 1 and not shield_cues()[0].contains("break"), "later equipment packet cannot forge original-packet break sound")

func weak_anchor_lifetime() -> void:
	fixture("CH03")
	var actor: Node2D = target(5)
	direct(actor, 20, &"f")
	var hit: Dictionary = one_contact("weak target lifetime", 15, 5, true)
	var reference: WeakRef = weakref(actor)
	check(not hit.is_empty() and hit.get("anchor") is WeakRef, "shield contact stores a weak target anchor")
	actor.free()
	check(reference.get_ref() == null, "active shield fragments do not keep a freed target alive")
	room.impact_feedback.advance(.02)
	check(reference.get_ref() == null, "advancing detached shield presentation safely handles released target")
	room.impact_feedback.advance(2.0)
	check(contacts().is_empty(), "shield and body contact events expire")

func run_checks() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_shield_contact") or DisplayServer.get_name() != "headless":
		push_error("Shield mechanism test requires headless and isolated test_shield_contact profile")
		quit(2)
		return
	create_timer(35, true, false, true).timeout.connect(func():
		if is_instance_valid(room): room.free()
		push_error("Shield mechanism watchdog expired")
		quit(1))
	AudioServer.set_bus_mute(0, true)
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated run starts")
	if game.run == null: quit(1); return
	absorption_cases()
	heavy_and_class_cases()
	refusal_cases()
	derived_cases()
	original_packet_isolation()
	weak_anchor_lifetime()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	game.finish_run("abandoned")
	print("SHIELD_CONTACT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
