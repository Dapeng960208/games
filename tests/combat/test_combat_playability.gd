extends Node
## Observational combat probe: real main/room, normal Lv1 starters, fixed route.
## Bot uses only movement inputs, aim, public fire/cast/dash actions and nearby E.
## No actor, health, damage, resource, reward, cooldown, or enemy-AI mutation.
## tools/test.ps1 -Suite combat_playability -SkipImport

const SEED := 41827
const SECONDS := 40.0
var app: Node
var checks := 0
var failures := 0
var reports: Array[Dictionary] = []
var current: Dictionary = {}
var cast_counts: Dictionary = {}
var cast_failures: Dictionary = {}
var total_damage := 0.0
var previous_hp := 0.0
var travelled := 0.0
var idle_motion_seconds := 0.0
var last_position := Vector2.ZERO
var desired_motion := Vector2.ZERO
var fire_successes := 0
var start_elapsed := 0.0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COMBAT_PLAYABILITY FAIL: "+label)

func frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	call_deferred("run_probe")

func movement(direction: Vector2) -> void:
	desired_motion = direction.limit_length(1.0)
	for action: String in ["move_left","move_right","move_up","move_down"]:
		if InputMap.has_action(action): Input.action_release(action)
	if direction.x < 0: Input.action_press("move_left",-direction.x)
	if direction.x > 0: Input.action_press("move_right",direction.x)
	if direction.y < 0: Input.action_press("move_up",-direction.y)
	if direction.y > 0: Input.action_press("move_down",direction.y)

func aim(at: Vector2) -> void:
	var mouse := InputEventMouseMotion.new()
	mouse.position = get_viewport().get_canvas_transform()*app.room.to_global(at)
	get_viewport().push_input(mouse,true)
	app.room.player.aim_direction = app.room.player.position.direction_to(at)

func nearest_enemy() -> Node2D:
	var result: Node2D = null
	for actor in app.room.enemies.get_children():
		if actor.actor_kind == "objective" or not actor.is_alive() or actor.is_queued_for_deletion(): continue
		if result == null or actor.position.distance_squared_to(app.room.player.position) < result.position.distance_squared_to(app.room.player.position):
			result = actor
	return result

func observe() -> Dictionary:
	var room: Node2D = app.room
	return {"time":snappedf(room.elapsed-start_elapsed,.01),"hp":snappedf(Game.run.hp,.01),"resource":snappedf(Game.run.resource,.01),"kills":Game.run.kills,"living":room._living_enemy_count(),"shots":Game.run.shots,"position":[snappedf(room.player.position.x,.1),snappedf(room.player.position.y,.1)],"zones_activated":room.activated_encounters.size(),"objective_complete":room.objective_complete,"controls_enabled":room.controls_enabled(),"telemetry":room.telemetry.duplicate(true)}

func bot_step(tick: int) -> void:
	var room: Node2D = app.room
	var player: Node2D = room.player
	var enemy: Node2D = nearest_enemy()
	if enemy == null:
		# Reach the next real encounter zone. Objectives are deliberately only
		# interacted with when already nearby; this is a combat pace probe.
		var destination: Vector2 = room.navigation_target().get("position",player.position)
		for index in room.encounter_zones.size():
			if not room.activated_encounters.has(index):
				destination = room.encounter_zones[index].center
				break
		movement(room.navigation_direction(player.position,destination,Balance.PLAYER_RADIUS) if player.position.distance_to(destination)>30 else Vector2.ZERO)
		aim(destination)
	else:
		var offset: Vector2 = enemy.position-player.position
		var distance: float = offset.length()
		var direction: Vector2 = offset.normalized()
		var clear: bool = room.has_line_of_sight(player.position,enemy.position)
		var motion := Vector2.ZERO
		# Area attacks test enemy centers against 105 px. Leave a margin for
		# the real 120 ms melee windup instead of idling just outside its reach.
		var desired_range: float = 58.0 if Game.run.hero_id == "CH01" else 280.0
		if distance > desired_range+30 or not clear:
			motion = room.navigation_direction(player.position,enemy.position,Balance.PLAYER_RADIUS)
		elif Game.run.hero_id != "CH01" and distance < desired_range-40:
			motion = -direction
		elif Game.run.hero_id != "CH01":
			motion = direction.orthogonal()*.6
		if not motion.is_zero_approx() and room.move_actor(player.position,motion*18,Balance.PLAYER_RADIUS).distance_to(player.position)<3:
			motion = room.navigation_direction(player.position,Vector2(1400,900),Balance.PLAYER_RADIUS)
		movement(motion)
		aim(enemy.position)
		# A visible windup within 160 px is the bot's only dodge trigger.
		if str(enemy.state) in ["windup","telegraph","lock"] and distance<160:
			player.start_dash(-direction if Game.run.hero_id != "CH01" else direction.orthogonal())
		var cast := false
		if tick%30 == 0:
			for slot: String in ["ultimate","f","secondary","q"]:
				var spec: Dictionary = player.skill_definition(slot)
				if Game.run.level < int(spec.unlock): continue
				if player.cast_skill(slot,enemy.position):
					cast_counts[slot] = int(cast_counts.get(slot,0))+1
					cast = true
					break
				var reason: String = player.last_cast_error
				cast_failures[reason] = int(cast_failures.get(reason,0))+1
		if clear and not cast and distance < (98.0 if Game.run.hero_id == "CH01" else 440.0):
			if player.fire(direction): fire_successes += 1
	if tick%60 == 0 and is_instance_valid(room.objectives):
		var interaction: Dictionary = room.objectives.nearby_interaction(player.position)
		if not interaction.is_empty(): room.interact()

func run_probe() -> void:
	if not Game.profile_path.contains("test_combat_playability") or DisplayServer.get_name() != "headless":
		get_tree().quit(2)
		return
	get_viewport().size = Vector2i(1280,720)
	get_tree().create_timer(210.0).timeout.connect(func(): push_error("Combat playability probe timed out"); get_tree().quit(1))
	AudioServer.set_bus_mute(0,true)
	for hero: String in ["CH01","CH02","CH03"]:
		movement(Vector2.ZERO)
		check(Game.new_profile(),"fresh isolated profile "+hero)
		check(Game.select_hero(hero),"select normal hero "+hero)
		app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
		add_child(app)
		await frames(2)
		check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":SEED}),"normal seeded departure "+hero)
		await frames(2)
		for offer: Dictionary in Game.expedition_snapshot().get("relic_offers",[]):
			if str(offer.get("decision","")).is_empty(): app._choose_expedition_relic(str(offer.offer_id),"skip")
		app._clear_modals()
		var options: Array = app.expedition.next_options()
		check(not options.is_empty(),"first real B01 room available")
		if options.is_empty(): get_tree().quit(1); return
		app._advance_expedition(str(options[0]))
		app._clear_modals()
		await frames(2)
		check(app.expedition.current_index()==1 and app.room.configuration_ready,"first combat room installed")
		check(Game.run.level==1 and not Game.run.demo and Game.run.relics.is_empty(),"Lv1 ordinary loadout without trial boosts")
		current = {"hero":hero,"level":Game.run.level,"difficulty":0,"route_seed":SEED,"room":app.room.layout_id,"layout_seed":app.room.layout_seed,"stats":Game.run.stats.duplicate(true),"loadout":Game.run.loadout_snapshot.duplicate(true),"samples":[],"locked_slots":[]}
		for slot: String in ["q","secondary","f","ultimate"]:
			if Game.run.level < int(app.room.player.skill_definition(slot).unlock): current.locked_slots.append(slot)
		cast_counts = {}; cast_failures = {}; total_damage = 0; travelled = 0; idle_motion_seconds = 0; fire_successes = 0
		previous_hp = Game.run.hp
		last_position = app.room.player.position
		start_elapsed = app.room.elapsed
		# Production critical hits and cosmetic events use the global RNG.
		seed(SEED)
		var initial_stats: Dictionary = Game.run.stats.duplicate(true)
		var snapshot: Dictionary = observe()
		for tick in int(SECONDS*60):
			if Game.run == null or not is_instance_valid(app.room): break
			if not app.modals.is_empty(): break
			if tick%6 == 0: bot_step(tick)
			await frames(1)
			if Game.run == null or not is_instance_valid(app.room): break
			var moved: float = app.room.player.position.distance_to(last_position)
			travelled += moved
			if desired_motion.length()>.1 and moved<.2: idle_motion_seconds += 1.0/60.0
			last_position = app.room.player.position
			total_damage += maxf(0.0,previous_hp-Game.run.hp)
			previous_hp = Game.run.hp
			snapshot = observe()
			if tick%300 == 0:
				current.samples.append(snapshot.duplicate(true))
			if app.room.elapsed-start_elapsed >= SECONDS: break
		current["final"] = snapshot
		current["died"] = Game.run == null and str(Game.last_result.get("outcome","")) == "death"
		current["result"] = Game.last_result.duplicate(true) if Game.run == null else {}
		current["damage_received"] = snappedf(total_damage,.01)
		current["distance_travelled"] = snappedf(travelled,.1)
		current["blocked_motion_seconds"] = snappedf(idle_motion_seconds,.01)
		current["fire_actions_accepted"] = fire_successes
		current["casts"] = cast_counts.duplicate(true)
		current["cast_rejections"] = cast_failures.duplicate(true)
		current["paused_by_modal"] = not app.modals.is_empty()
		if Game.run != null: check(Game.run.stats == initial_stats,"probe leaves resolved stats untouched")
		reports.append(current.duplicate(true))
		print("COMBAT_PLAYABILITY_OBSERVATION ",JSON.stringify(current))
		movement(Vector2.ZERO)
		if is_instance_valid(app.room): await app.room.combat_audio.wait_for_cleanup()
		if Game.run != null: Game.finish_run("abandoned")
		await frames(2)
		app.set_process(false)
		await app.music.wait_for_cleanup()
		app.free()
		await frames(2)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var output := FileAccess.open(AssetCatalog.resolve("res://artifacts/combat_playability.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"method":"real 60 Hz physics, normal seeded Lv1 B01 entry, public actions and movement input; observational bot, not human balance validation","seconds_per_hero":SECONDS,"reports":reports},"\t"))
	output.close()
	print("COMBAT_PLAYABILITY_RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
