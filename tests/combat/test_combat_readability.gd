extends SceneTree
## Focused actual room/health/brain checks for the presentation changes.
const Numbers = preload("res://scripts/presentation/combat/damage_numbers.gd")
var game: Node
var room: Node2D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMBAT READABILITY: " + label)

func numbers() -> Array:
	return room.impact_feedback.events.filter(func(event: Dictionary) -> bool: return str(event.kind) == "number")

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_combat_readability"):
		push_error("Refusing non-test profile")
		quit(1)
		return
	check(game.new_profile() and game.start_run(), "isolated real run starts")
	if game.run == null:
		quit(1)
		return
	game.run.hero_id = "CH01"
	game.run.level = 8
	game.run.stats = load(AssetCatalog.resolve("res://scripts/domain/combat/stat_resolver.gd")).resolve("CH01", 8, {}, {})
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.profile.settings.damage_numbers = true
	game.profile.settings.enemy_skill_paths = true
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.combat_audio.audible = false
	room.obstructions.clear()
	for actor in room.enemies.get_children(): actor.free()
	room.player.position = Vector2(1000,800)
	var actor: Node2D = room.spawn_enemy(Vector2(1100,800), "M01", 1)
	actor.health.reset(200.0)
	actor.armor = 0.0
	actor.magic_resist = 0.0
	room.impact_feedback.clear_feedback()
	actor.status.grant_guard(25.0, 5.0, "readability", 200.0)
	var before_hp: float = actor.health.current
	actor.take_damage(40.0, &"primary", Vector2.RIGHT, {"damage_type":"physical", "critical":true})
	var items: Array = numbers()
	check(items.size() == 2, "HP overflow and actual shield absorption have separate numbers")
	if items.size() == 2:
		check(is_equal_approx(float(items[0].amount), before_hp - actor.health.current) and is_equal_approx(float(items[1].amount), 25.0), "displayed amounts equal actual resources consumed")
		check(items[0].presentation.critical and int(items[0].presentation.font_size) == 31 and items[1].presentation.feedback_kind == "shield", "critical metadata enlarges real damage and shield is marked")
	room.impact_feedback.clear_feedback()
	actor.status.apply("invulnerable",1.0,2.0)
	actor.take_damage(100.0,&"primary")
	check(numbers().is_empty(), "immune hit produces no fictional damage")
	actor.status.states.clear()
	actor.health.reset(3.0)
	actor.take_damage(999.0,&"equipment_true",Vector2.ZERO,{"damage_type":"true"})
	items = numbers()
	check(items.size() == 1 and is_equal_approx(float(items[0].amount),3.0), "lethal overkill displays only consumed HP")
	var colors: Array = []
	for kind: String in ["kinetic","fire","electric","cold","corrosion","true"]:
		var style: Dictionary = Numbers.presentation(12.0,"primary",{"damage_kind":kind})
		check(style.damage_kind == kind and not style.critical, kind + " has truthful presentation metadata")
		colors.append(style.color)
	for color: Color in colors: check(colors.count(color) == 1, "damage categories have distinct colors")
	check(Numbers.damage_kind("primary",{"damage_type":"physical","status":"burn"}) == "kinetic", "applied burn does not relabel a physical packet")
	check(Numbers.damage_kind("burn",{"damage_type":"magic"}) == "fire", "real burn DOT is shown as fire")
	game.profile.settings.reduced_fx = true
	room.impact_feedback.clear_feedback()
	room.add_damage_text(Vector2.ZERO,12,&"primary",{"critical":true})
	check(numbers().size() == 1 and numbers()[0].reduced and numbers()[0].presentation.critical, "reduced effects retain numbers and real critical weight")
	for index in 80: room.add_damage_text(Vector2(index,0),2,&"burn",{"dot":true})
	check(room.impact_feedback.events.size() <= 32, "many hits keep bounded event storage")
	room.impact_feedback.advance(1.0)
	check(room.impact_feedback.events.is_empty(), "all numbers expire after their real lifetime")
	actor = room.spawn_enemy(Vector2(1100,800), "M01", 1)
	for step in 500:
		actor._physics_process(0.01)
		if actor.state == &"locked": break
	var command: Dictionary = actor.brain.current_telegraph()
	check(not command.is_empty(), "actual enemy brain publishes locked skill")
	room.enemy_telegraphs.refresh()
	check(not room.enemy_telegraphs.snapshot().is_empty(), "enabled setting presents real skill")
	game.profile.settings.enemy_skill_paths = false
	room.enemy_telegraphs.refresh()
	check(room.enemy_telegraphs.snapshot().is_empty() and actor.brain.current_telegraph() == command, "disabled setting clears only presentation; brain command remains unchanged")
	game.profile.settings.enemy_skill_paths = true
	room.enemy_telegraphs.refresh()
	check(not room.enemy_telegraphs.snapshot().is_empty(), "reenabling restores current real warning")
	room.free()
	await process_frame
	print("COMBAT_READABILITY_CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
