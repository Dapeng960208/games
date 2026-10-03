extends Node
var room: Node2D
var checks:=0
var failures:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 displacement: "+message)
func _ready() -> void: run.call_deferred()
func fresh(id: String) -> Node2D:
	for actor: Node in room.enemies.get_children(): actor.free()
	room.harbor.reset()
	room.player.position=Vector2(400,540)
	var actor: Node2D=room.spawn_enemy(Vector2(450,540),id)
	actor.brain._begin(actor,room.player)
	return actor
func run() -> void:
	room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED # Direct contract fixture only.
	add_child(room)
	await get_tree().process_frame
	check(Game.profile_path.begins_with("user://test_b08_candidate/"),"isolated profile")
	var actor:=fresh("B08-M01")
	var before: Vector2=actor.position
	actor.apply_knockback(Vector2.RIGHT,12)
	check(actor.position==before and actor.has_pending_displacement(),"accepted push stays queued, not teleported")
	check(actor.brain.phase=="warning" and room.warnings.size()==1,"small standing displacement preserves original 30-unit tolerance")
	actor.apply_knockback(Vector2.RIGHT,24)
	check(actor.brain.phase=="recovery" and actor.state==&"recovery" and actor.brain.action.is_empty(),"cumulative projected displacement cancels standing action before next brain tick")
	check(room.warnings.is_empty(),"cancel releases warning slot")
	actor.brain.tick(actor,.01,room.player)
	check(room.feathers.is_empty(),"cancelled arrow cannot release from old origin")
	actor._advance_pushes(.2)
	check(actor.position.is_equal_approx(before+Vector2(36,0)) and not actor.has_pending_displacement(),"queued pushes keep original integrated distance and lifetime")
	actor=fresh("B08-M01")
	actor.position=Vector2(122.4,540)
	actor.brain.action.origin=actor.position
	actor.apply_knockback(Vector2.LEFT,40)
	check(not actor.has_pending_displacement() and actor.brain.phase=="warning","fully edge-blocked request does not cancel stationary warning")
	actor=fresh("B08-M01")
	actor.position=Vector2(137.4,540)
	actor.brain.action.origin=actor.position
	actor.apply_knockback(Vector2.LEFT,40)
	actor._advance_pushes(.2)
	check(room.valid_ground(actor.position,actor.navigation_radius) and actor.position.x>=122.39,"partial push obeys real edge guard")
	check(actor.brain.phase=="warning","clipped displacement within tolerance preserves warning")
	for id: String in ["B08-M02","B08-M03","B08-M05"]:
		actor=fresh(id)
		actor.brain._release(actor)
		var cooldown: float=actor.brain.cooldown
		var hp: float=Game.run.hp
		check(actor.brain.phase=="transit",id+" fixture is actual committed travel")
		actor.apply_knockback(Vector2.DOWN,12)
		check(actor.brain.phase=="recovery" and not actor.brain.transit and actor.brain.action.is_empty(),id+" accepted push cancels active movement")
		check(actor.brain.cooldown==cooldown and room.warnings.is_empty() and room.wind.dive_owner.is_empty(),id+" cooldown preserved and threat ownership released")
		actor.brain.tick(actor,.1,room.player)
		check(Game.run.hp==hp,id+" cancelled landing cannot hit player")
	actor=fresh("B08-M06")
	check(room.harbor.chimes.size()==1,"chime warning creates authored destructible object")
	actor.apply_knockback(Vector2.DOWN,40)
	check(room.harbor.chimes.is_empty() and room.warnings.is_empty(),"displaced chime warning clears owned delayed hit")
	actor=fresh("BO08")
	actor.apply_knockback(Vector2.RIGHT,80)
	check(actor.brain.phase=="warning" and not actor.has_pending_displacement(),"boss displacement immunity remains at Actor boundary")
	check(await room.cleanup_for_exit(),"bounded cleanup")
	room.free()
	Game.reload_profile()
	await get_tree().process_frame
	print("B08_DISPLACEMENT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
