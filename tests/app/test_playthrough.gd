extends Node
## Legacy single-room live-physics loop. Bot aim is exact, not a human balance study.

var app: Node
var room: Node2D
var failures := 0
var checks := 0

func _ready() -> void:
	call_deferred("run_playthrough")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1

func movement(direction: Vector2) -> void:
	var states := {"move_right":direction.x>0.15,"move_left":direction.x< -0.15,"move_down":direction.y>0.15,"move_up":direction.y< -0.15}
	for action in states:
		if states[action]:
			Input.action_press(action)
		else:
			Input.action_release(action)

func run_playthrough() -> void:
	if not Game.profile_path.contains("test_combat"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"create isolated permanent profile")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	app.show_camp()
	check(Game.start_run(),"start legacy single-room combat fixture")
	room = app.room
	check(room != null and Game.run != null,"camp creates real combat room")
	Engine.time_scale = 6.0
	var route: Array[String] = ["split","ember","arc"]
	var acquired := 0
	var extraction_requested := false
	var max_enemies := 0
	var stats: Dictionary = room.telemetry
	for frame in range(360):
		if Game.run == null:
			break
		Input.action_release("interact")
		max_enemies = maxi(max_enemies,room.enemies.get_child_count())
		if not app.modals.is_empty():
			extraction_requested = true
			break
		var nearest: Node2D
		var near_distance := INF
		for enemy in room.enemies.get_children():
			if enemy.is_alive():
				var distance: float = enemy.position.distance_squared_to(room.player.position)
				if distance < near_distance:
					near_distance = distance
					nearest = enemy
		if nearest != null and acquired == route.size():
			room.player.fire((nearest.position-room.player.position).normalized())
		var goal := Vector2(640,360)
		if acquired < route.size():
			if Game.run.relics.has(route[acquired]):
				acquired += 1
			if acquired < route.size():
				goal = room.RELIC_POSITIONS[route[acquired]]
		elif Game.run.gold >= Balance.GOLD_PER_ENEMY:
			goal = room.EXIT_POSITION
		elif not room.gold_drops.is_empty():
			goal = room.gold_drops[0].at
		var offset: Vector2 = goal-room.player.position
		movement(offset.normalized() if offset.length()>18 else Vector2.ZERO)
		if frame % 2 == 0 and offset.length()<40 and (acquired < route.size() or Game.run.gold>=Balance.GOLD_PER_ENEMY):
			Input.action_press("interact")
		await get_tree().physics_frame
	movement(Vector2.ZERO)
	Input.action_release("interact")
	Engine.time_scale = 1.0
	check(acquired == 3,"bot walks to all three stations and uses real E input")
	check(extraction_requested,"bot returns to the lift and requests extraction through E")
	check(stats.kills>0 and stats.gold_collected>=17,"live run kills enemies and collects physical gold")
	check(stats.split_spawned>0 and stats.burn_ticks>0 and stats.arc_hits>0,"live run observes all three relic effects")
	var carried: int = Game.run.gold if Game.run != null else 0
	var hp: float = Game.run.hp if Game.run != null else 0
	if extraction_requested:
		app._settle("extracted")
	check(Game.run==null and Game.last_result.outcome=="extracted" and Game.profile.permanent_gold==carried,"real extraction commits all carried gold")
	var bank: int = Game.profile.permanent_gold
	Game.reload_profile()
	check(Game.profile.permanent_gold==bank and Game.profile.discoveries.size()==3,"reload keeps earned gold and three discoveries")
	app.show_camp()
	check(Game.start_run(),"start second legacy single-room fixture")
	check(Game.run!=null and Game.run.gold==0 and Game.run.relics.is_empty(),"return to camp starts a clean second legacy run")
	Game.finish_run("abandoned")
	print("LIVE PLAYTHROUGH: ",checks-failures,"/",checks," passed; collected=",carried," hp_at_extraction=",hp," max_enemies=",max_enemies," telemetry=",stats)
	get_tree().quit(1 if failures else 0)
