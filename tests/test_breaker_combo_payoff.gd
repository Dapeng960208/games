extends SceneTree
## Short, isolated check of the Momentum payoff. Root runs this after UI/gameplay
## integration; no import, graphics capture or player save is touched here.
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
var abilities_script: Script
var game: Node
var room: Node2D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BREAKER COMBO FAIL: " + note)

func setup(momentum: int, rage: float) -> void:
	room.player.cancel_actions()
	room.player.dash_remaining = 0.0
	room.player.dash_cooldown = 0.0
	room.player.cooldowns.secondary = 0.0
	room.player.break_stacks = 0
	room.player.gain_break_stacks(momentum)
	game.run.resource = rage

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_breaker_combo_payoff"):
		push_error("Refusing non-isolated breaker combo profile")
		quit(2)
		return
	abilities_script = load("res://scripts/combat/hero_abilities.gd")
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated run starts")
	if game.run == null:
		quit(1)
		return
	game.run.hero_id = "CH01"
	game.run.level = 8
	game.run.stats = Resolver.resolve("CH01", 8, {}, {})
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.loadout_snapshot.clear()
	game.run.relics.clear()
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.obstructions.clear()
	room.combat_audio.audible = false
	room.player.position = Vector2(500,350)
	room.player.aim_direction = Vector2.RIGHT
	var target := Vector2(590,350)
	setup(3,0.0)
	room.player.loadout.effects.windows["EQ56"] = 5.0
	check(room.player.skill_definition("secondary").cost == 0.0, "live skill card exposes zero Rage at full Momentum")
	check(abilities_script.preview_spec("CH01",8,game.run.stats,"secondary").cost == 30.0, "catalog preview remains independent of live Momentum")
	check(room.player.abilities.can_cast("secondary",target) and room.player.break_stacks == 3 and game.run.resource == 0.0, "validation accepts full Momentum without consuming it")
	check(room.player.cast_skill("secondary",target), "zero Rage full Momentum sweep starts")
	check(room.player.loadout.effects.windows.has("EQ56"), "free sweep preserves the discount for the next paid skill")
	room.player.loadout.effects.windows.erase("EQ56")
	check(room.player.break_stacks == 0 and game.run.resource == 0.0 and is_equal_approx(room.player.cooldowns.secondary,4.0), "free sweep consumes three stacks and commits normal cooldown")
	check(is_equal_approx(room.player.abilities.active.spec.coefficient,3.55), "free sweep retains the three-stack damage reward")
	check(room.player.start_dash(Vector2.LEFT), "real dash can cancel paid commitment")
	check(not room.player.abilities.busy() and room.player.break_stacks == 0 and game.run.resource == 0.0 and room.player.cooldowns.secondary == 4.0, "cancel refunds neither stacks nor cooldown")
	for momentum: int in [0,1,2]:
		setup(momentum,0.0)
		check(not room.player.cast_skill("secondary",target) and room.player.last_cast_error == "resource" and room.player.break_stacks == momentum and room.player.cooldowns.secondary == 0.0, "non-full zero Rage stays unavailable at %d stacks" % momentum)
	setup(3,0.0)
	room.player.cooldowns.secondary = 1.5
	check(not room.player.cast_skill("secondary",target) and room.player.last_cast_error == "cooldown" and room.player.break_stacks == 3, "full Momentum cannot bypass cooldown or lose stacks to rejection")
	setup(2,30.0)
	check(room.player.skill_definition("secondary").cost == 30.0 and room.player.cast_skill("secondary",target), "non-full sweep retains its ordinary thirty Rage cost")
	check(game.run.resource == 0.0 and room.player.break_stacks == 0, "ordinary sweep commits both Rage and existing stacks")
	room.player.cancel_actions()
	check(await room.combat_audio.wait_for_cleanup(), "audio cleanup completes")
	room.free()
	print("BREAKER COMBO PAYOFF: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
