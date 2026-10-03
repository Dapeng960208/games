extends Node
const Skills=preload("res://scripts/combat/b05_enemy_skills.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("B05 MOUTHS: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_projectile_mouths"): get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated baseline")
	var room=load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled=false;room.process_mode=Node.PROCESS_MODE_DISABLED;room.spawn_enabled=false
	add_child(room);await get_tree().process_frame
	room.player.position=Vector2(1500,1200)
	var actor=load("res://scenes/enemy.tscn").instantiate()
	actor.room=room;actor.position=Vector2(600,400)
	actor.configure(Skills.profile("B05-M16",25,0),{"reward_enabled":false});room.enemies.add_child(actor)
	actor.state=&"execute"
	var command:=Skills.active(actor.profile,actor.position,actor.position+Vector2(200,0),false)
	actor.brain._command=command;actor.brain.phase=&"execute"
	actor.cast_enemy_skill(command)
	var outlets: Array=actor.body_visual.b05_visual_outlets()
	check(outlets.size()==3,"three registered native mouths")
	check(room.enemy_skills.projectiles.size()==3,"three physical fan shots")
	var first: Dictionary=room.enemy_skills.projectiles[0]
	for index in room.enemy_skills.projectiles.size():
		var shot: Dictionary=room.enemy_skills.projectiles[index]
		check(shot.position==actor.position and shot.origin==actor.position,"physical origin preserved")
		check(room.enemy_skills.projectile_visual_position(shot).is_equal_approx(outlets[index].position),"display begins at corresponding mouth")
		check(is_equal_approx(float(shot.distance_left),280.0),"locked travel range unchanged")
	var offset: Vector2=first.b05_visual_offset
	var physical: Vector2=first.position
	room.enemy_skills.advance(.07)
	check(Vector2(first.position).distance_to(physical)>0,"physical flight still advances")
	check((room.enemy_skills.projectile_visual_position(first)-Vector2(first.position)).is_equal_approx(offset*.5),"display transfer halves by70ms")
	room.enemy_skills.advance(.08)
	check(room.enemy_skills.projectile_visual_position(first).is_equal_approx(first.position),"display rejoins locked physical flight by140ms")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_PROJECTILE_MOUTHS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
