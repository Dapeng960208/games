extends SceneTree
## Exercise the real profile/expedition transactions without simulating combat.
## Runtime fixtures match test_core_expedition.gd; skill availability comes from
## HeroAbilities' production specification and the actual persisted run level.
const Controller = preload("res://scripts/app/game.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/domain/expedition/expedition_state.gd")
const HEROES := ["CH01", "CH02", "CH03"]
const SKILLS := ["q", "secondary", "f", "ultimate"]

var checks: int = 0
var failures: int = 0
var directory: String
var abilities_script: Script

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FIRST RUN PROGRESSION FAIL: " + label)

func _game(filename: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + filename
	root.add_child(game)
	return game

func _runtime(game: Node) -> Dictionary:
	var player: Dictionary = {"cooldowns":{},"passive_count":0,"walk_distance":0.0,"aim_direction":[1.0,0.0],"cast_serial":0}
	for key: String in Snapshot.SKILLS: player.cooldowns[key] = 0.0
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.0
	var equipment: Dictionary = {"room_id":"","room_low_shield_used":false,"room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.dash_time = -100.0
	equipment.delayed_shield_at = -1.0
	var modifiers: Dictionary = {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 1.0 if key.ends_with("_scale") else 0.0
	equipment["adapter"] = {"clock":0.0,"movement_time":0.0,"event_serial":0,"modifiers":modifiers}
	return {"snapshot_version":1,"mode":"safe_boundary","hero_id":game.run.hero_id,"hp":game.run.hp,"resource":game.run.resource,
		"player":player,"equipment":equipment,"status":{"clock":0.0,"shock_cooldown":0.0,"states":{},"guards":{},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}}

func _start(game: Node, hero: String, fresh: bool = true) -> bool:
	if fresh:
		var created: bool = game.new_profile()
		_check(created, hero + " creates an isolated fresh profile")
		if not created: return false
	var selected: bool = game.select_hero(hero)
	_check(selected, hero + " selects its own progression")
	if not selected: return false
	var started: bool = game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":960208})
	_check(started, hero + " starts a real first-tier expedition")
	if not started or game.run == null: return false
	_check(Expedition.runtime_valid(_runtime(game), hero, game.run.stats), hero + " boundary fixture validates")
	return true

func _ability_script_valid() -> bool:
	if abilities_script == null or not abilities_script.can_instantiate(): return false
	for method: Dictionary in abilities_script.get_script_method_list():
		if str(method.name) == "preview_spec": return true
	return false

func _assert_progress(game: Node, xp: int, level: int, available_slots: int, context: String) -> void:
	if not _ability_script_valid():
		_check(false, context + " cannot validate skills without a valid ability script")
		quit(1)
		return
	var hero: String = game.run.hero_id
	_check(int(game.profile.hero_xp[hero]) == xp, context + " has exactly " + str(xp) + " committed XP")
	_check(game.run.level == level and game.hero_level(hero) == level, context + " live and profile level agree at " + str(level))
	for index in range(SKILLS.size()):
		var slot: String = SKILLS[index]
		var spec: Dictionary = abilities_script.preview_spec(hero, game.run.level, game.run.stats, slot)
		_check(not spec.is_empty(), context + " resolves production " + slot + " specification")
		if spec.is_empty(): continue
		var available: bool = game.run.level >= int(spec.unlock)
		_check(available == (index < available_slots), context + " " + slot + (" is unlocked" if index < available_slots else " stays locked"))

func _advance(game: Node) -> bool:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		var resolved: bool = game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game))
		_check(resolved, "resolve entrance or earned relic offer")
		if not resolved: return false
	var snapshot: Dictionary = game.expedition_snapshot()
	var next: Dictionary = snapshot.next_node
	if next.is_empty(): return false
	var selected: bool = game.choose_expedition_node(int(next.node_index), str(next.room_id))
	_check(selected, "lock the next authored room")
	if not selected: return false
	var advanced: bool = game.advance_expedition_node(_runtime(game), snapshot.checkpoint_id)
	_check(advanced, "commit the next room entrance: " + game.last_error)
	return advanced

func _complete(game: Node) -> bool:
	var event_id: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	# Non-boss expedition rooms award 30 XP in room.gd. The tutorial bonus is
	# deliberately absent here: complete_hero_tutorial must stage it itself.
	var rewards: Dictionary = {"xp":30,"mastery":180}
	var committed: bool = game.commit_expedition_completion(event_id, _runtime(game), rewards)
	_check(committed, "commit room XP and staged tutorial together: " + game.last_error)
	if not committed: return false
	var xp: int = int(game.profile.hero_xp[game.run.hero_id])
	_check(game.commit_expedition_completion(event_id, _runtime(game), rewards), "room completion retry is accepted")
	_check(int(game.profile.hero_xp[game.run.hero_id]) == xp, "completion retry cannot repeat either XP award")
	return true

func _first_expedition(hero: String) -> void:
	var game := _game("progression-" + hero + ".json")
	if not _start(game, hero): game.free(); return
	_assert_progress(game, 0, 1, 1, hero + " new profile")
	_check(game.run.expedition.route.nodes.size() == 6, hero + " first expedition uses six nodes")
	var completed_rooms: int = 0
	var reached_boss: bool = false
	for unused in range(game.run.expedition.route.nodes.size() - 1):
		if not _advance(game): break
		var role: String = game.expedition_snapshot().node.role
		if role == "supply":
			_check(completed_rooms == 2, hero + " supply follows the first two rewarded rooms")
			_assert_progress(game, 90, 3, 3, hero + " supply adds no XP")
			continue
		if role == "boss":
			reached_boss = true
			_check(completed_rooms == 3 and game.run.boss_defeats.is_empty(), hero + " reaches boss after three non-boss clears")
			_assert_progress(game, 120, 4, 4, hero + " before fighting boss")
			break
		if completed_rooms == 0:
			_check(game.complete_hero_tutorial(), hero + " records the real tutorial milestone")
			_check(game.complete_hero_tutorial(), hero + " repeated uncommitted milestone remains idempotent")
			_check(game.run.staged_tutorial and not hero in game.profile.tutorial_completed, hero + " tutorial flag waits for room commit")
			_assert_progress(game, 0, 1, 1, hero + " staged tutorial cannot unlock skills early")
		else:
			_check(not game.complete_hero_tutorial(), hero + " committed tutorial cannot pay again")
		if not _complete(game): break
		completed_rooms += 1
		var expected_xp: int = 30 + completed_rooms * 30
		_assert_progress(game, expected_xp, completed_rooms + 1, completed_rooms + 1, hero + " clear " + str(completed_rooms))
		_check(hero in game.profile.tutorial_completed and not game.run.staged_tutorial, hero + " room commits tutorial and clears staged flag")
		# A fresh controller load must recover the same newly unlocked skills.
		game.reload_profile()
		_check(game.run != null, hero + " committed room resumes from disk")
		if game.run == null: break
		_assert_progress(game, expected_xp, completed_rooms + 1, completed_rooms + 1, hero + " reloaded clear " + str(completed_rooms))
	_check(reached_boss, hero + " all four skills are available before the first boss")
	game.free()

func _uncommitted_death(hero: String) -> void:
	var game := _game("death-" + hero + ".json")
	if not _start(game, hero) or not _advance(game): game.free(); return
	_check(game.complete_hero_tutorial(), hero + " stages tutorial before dying")
	_check(game.grant_hero_xp(30, game.run.id + ":uncommitted-room"), hero + " stages an unfinished room callback")
	_assert_progress(game, 0, 1, 1, hero + " unfinished room")
	_check(game.damage_player(1000000.0) > 0.0 and game.run == null, hero + " lethal damage settles the unfinished expedition")
	_check(int(game.profile.hero_xp[hero]) == 0 and not hero in game.profile.tutorial_completed, hero + " death discards uncommitted room and tutorial XP")
	game.reload_profile()
	_check(game.run == null and game.hero_level(hero) == 1, hero + " death remains level one after disk reload")
	if _start(game, hero, false):
		_assert_progress(game, 0, 1, 1, hero + " next run after death")
		_check(not game.run.staged_tutorial, hero + " next run has no leaked tutorial flag")
	game.free()

func _legacy_level_one(hero: String) -> void:
	var profile: Dictionary = ProfileStore.fresh_profile()
	profile.selected_hero = hero
	profile.permanent_gold = 37
	# A v2 file predates expeditions and contains no saved skill unlock list.
	# Loading it must derive Q availability without granting XP or rewriting it.
	var document: Dictionary = {"schema_version":2,"revision":7,"profile_initialized":true,"profile":profile,"active_run":null}
	_check(ProfileStore._valid_document(document), hero + " legacy level-one fixture is a valid v2 save")
	var filename: String = "legacy-level-one-" + hero + ".json"
	var file := FileAccess.open(AssetCatalog.resolve(directory + "/" + filename), FileAccess.WRITE)
	_check(file != null, hero + " writes isolated legacy save")
	if file == null: return
	file.store_string(JSON.stringify(document))
	file.close()
	var game := _game(filename)
	_check(game.has_profile and game.profile.permanent_gold == 37 and game.profile.selected_hero == hero, hero + " loads the existing profile without resetting it")
	_check(game.hero_level(hero) == 1 and game.profile.tutorial_completed.is_empty(), hero + " old profile stays level one with no tutorial grant")
	if _start(game, hero, false):
		_assert_progress(game, 0, 1, 1, hero + " old level-one save naturally gains Q")
		_check(game.profile.permanent_gold == 37 and game.profile.tutorial_completed.is_empty(), hero + " skill availability leaves wallet and tutorial progress intact")
	game.free()

func _run() -> void:
	# HeroAbilities references Game. Load only after autoloads are registered,
	# rather than compiling it during this SceneTree script's initialization.
	abilities_script = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_abilities.gd"))
	var abilities_valid: bool = _ability_script_valid()
	_check(abilities_valid, "production ability script loads after Game autoload")
	if not abilities_valid:
		quit(1)
		return
	directory = "res://tools/godot/test-runs/first_run_progression_" + str(Time.get_ticks_usec())
	var created: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_check(created == OK, "create isolated progression fixture directory")
	if created == OK:
		for hero: String in HEROES:
			_first_expedition(hero)
			_uncommitted_death(hero)
			_legacy_level_one(hero)
	print("FIRST RUN PROGRESSION TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)
