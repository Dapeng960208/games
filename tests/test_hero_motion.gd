extends Node
## Actual player/abilities/feedback timing; graphical mode records front/back
## windup, release and recovery from committed casts, never fabricated states.
const RoomScene = preload("res://scenes/room.tscn")
const Visual = preload("res://scripts/combat/hero_visual.gd")
var room: MineRoom
var checks: int = 0
var failures: int = 0
var graphical: bool = false

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO MOTION FAIL: "+label)

func step(duration: float) -> void:
	var remaining: float = duration
	while remaining > .00001:
		var delta: float = minf(.01,remaining)
		room.player._physics_process(delta)
		for enemy in room.enemies.get_children():
			if enemy.is_alive() and not enemy.is_queued_for_deletion():
				enemy._physics_process(delta)
		for shot in room.projectiles.get_children():
			if not shot.is_queued_for_deletion():
				shot._physics_process(delta)
		for deployment in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room == room and deployment.is_alive():
				deployment.advance(delta)
		room._physics_process(delta)
		remaining -= delta

func fresh(hero: String) -> void:
	if is_instance_valid(room):
		room.free()
	if Game.run != null:
		Game.finish_run("abandoned")
	check(Game.select_hero(hero) and Game.start_run(),hero+" real run starts")
	check(Game.grant_hero_xp(3600,"motion:"+hero),hero+" real progression unlocks skills")
	room = RoomScene.instantiate()
	room.run_seed = 41827
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	for enemy in room.enemies.get_children():
		enemy.free()
	var center := Vector2.ZERO
	for y in range(500,1401,100):
		for x in range(700,2101,100):
			var candidate := Vector2(x,y)
			var clear: bool = room.valid_ground(candidate,24)
			for side in range(8):
				clear = clear and room.blocked_fraction(candidate,candidate+Vector2.from_angle(side*TAU/8)*240,24) >= 1.0
			if clear:
				center = candidate
				break
		if center != Vector2.ZERO:
			break
	check(center != Vector2.ZERO,"actual generated room has open capture stage")
	room.player.position = center
	room.camera.follow_target()
	room.camera.force_update_scroll()
	Game.restore_resource(1000)
	room.combat_audio.audible = false

func capture(hero: String, bank: String, phase: String) -> void:
	room.player.queue_redraw()
	room.queue_redraw()
	if not graphical:
		return
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	check(frame.save_png("res://artifacts/motion_"+hero+"_"+bank+"_"+phase+".png") == OK,hero+" saved real "+bank+" "+phase+" frame")
	check(str(room.player.get_meta("hero_visual_pose","")) == phase,hero+" renderer consumed actual "+phase+" pose")
	check(str(room.player.get_meta("hero_visual_bank","")) == bank,hero+" renderer selected correct aiming bank")

func run_checks() -> void:
	if not Game.profile_path.contains("test_hero_motion"):
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile(),"isolated motion profile")
	for hero: String in ["CH01","CH02","CH03"]:
		for bank: String in ["front","back"]:
			fresh(hero)
			var feedback: Node2D = room.player.get_node("HeroFeedback")
			check(feedback.z_index+room.player.z_index < room.enemy_skills.z_index,"friendly feedback remains below actual enemy warning layer")
			for phase: String in ["idle","windup","release","recovery"]:
				var image: Dictionary = Visual.action_frame_info(hero,bank,phase)
				check(not image.is_empty(),hero+" has original "+bank+" "+phase+" raster pose")
				if not image.is_empty():
					check(image.anchors.foot == Vector2(0,8) and float(image.body_height)==88,hero+" "+phase+" preserves fixed body scale and foot anchor")
			var direction := Vector2(1,1 if bank=="front" else -1).normalized()
			room.player.aim_direction = direction
			var slot: String = "q" if hero=="CH03" else "secondary"
			var target: Vector2 = room.player.position+direction*72
			var victim: MineEnemy = room.spawn_enemy(target)
			victim.training_ai_disabled = true
			victim.health.reset(10000)
			var before: float = victim.health.current
			var cost: float = room.player.skill_definition(slot).cost
			var resource: float = Game.run.resource
			check(room.player.cast_skill(slot,target),hero+" actual cast begins")
			check(absf(resource-Game.run.resource-cost)<.001,hero+" visual upgrade preserves real resource cost")
			var windup: float = room.player.abilities.active.spec.windup
			step(windup*.45)
			check(str(feedback.pose_state().phase)=="windup" and feedback.release_events.is_empty(),hero+" anticipation precedes actual release")
			await capture(hero,bank,"windup")
			step(windup*.55+.001)
			check(feedback.release_events.size()==1 and str(feedback.pose_state().phase)=="release",hero+" exactly one real release drives strike frame")
			await capture(hero,bank,"release")
			step(.19)
			check(str(feedback.pose_state().phase)=="recovery",hero+" actual cast continues into authored recovery")
			await capture(hero,bank,"recovery")
			check(victim.health.current<before,hero+" capture retains real damage rather than fake hit FX")
			check(feedback.impact_events>0,hero+" impact callback only follows actual target loss")
			# Cancellation drops future release callbacks without refunding costs.
			step(1)
			room.player.cooldowns[slot]=0.0
			Game.restore_resource(1000)
			check(room.player.cast_skill(slot,target),hero+" second real cast starts")
			var releases: int = feedback.release_events.size()
			room.player.cancel_actions()
			step(windup+.1)
			check(feedback.release_events.size()==releases and str(feedback.pose_state().phase)=="idle",hero+" cancelled cast has no phantom pose release")
		fresh(hero)
		var feedback: Node2D = room.player.get_node("HeroFeedback")
		if graphical:
			for index in range(8):
				var direction := Vector2.from_angle(index*TAU/8)
				room.player.aim_direction = direction
				room.player.queue_redraw()
				await RenderingServer.frame_post_draw
				check(str(room.player.get_meta("hero_visual_bank","")) == ("back" if direction.y < -.2 else "front"),hero+" eight-direction input selects correct front/back raster")
				check(float(room.player.get_meta("hero_visual_flip",0)) == (-1.0 if direction.x < -.05 else 1.0),hero+" left/right direction mirrors body and anchors together")
		room.player.aim_direction = Vector2.RIGHT
		check(room.player.fire(Vector2.RIGHT),hero+" actual basic starts")
		step(.14)
		check(feedback.basic_events==1,hero+" single basic observation per committed release")
		if hero == "CH02":
			step(.6)
			Game.restore_resource(1000)
			check(room.player.cast_skill("ultimate",room.player.position+Vector2(180,0)),"ranger real ultimate starts")
			step(1.2)
			check(feedback.release_events.size()==4,"ranger R has exactly four feedback releases")
			for index in 4:
				check(int(feedback.release_events[index].index)==index and int(feedback.release_events[index].count)==4,"ranger per-shot and final-shot identities match real timeline")
		elif hero == "CH03":
			step(.6)
			Game.restore_resource(1000)
			check(room.player.cast_skill("ultimate",room.player.position+Vector2(90,0)),"resonator real dome starts")
			step(.5)
			check(feedback.deployment_events==0,"dome does not fabricate an immediate damage tick")
			step(1.0)
			check(feedback.deployment_events==1,"first visible dome pulse comes from real one-second tick")
	if is_instance_valid(room):
		room.free()
	print("HERO MOTION ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
