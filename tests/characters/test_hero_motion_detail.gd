extends Node
## Direct checks for the movement-facing and grounded dodge presentation only.
## Real Player dash state supplies its fixed direction, including mage's zero
## velocity teleport. Combat launches continue to sample committed release art.

const Visual = preload("res://scripts/presentation/characters/hero_visual.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
var room: RoomController
var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO MOTION DETAIL FAIL: "+label)

func fixture(hero: String) -> void:
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		Input.action_release(action)
	if is_instance_valid(room):
		room.free()
	if Game.run != null:
		Game.finish_run("abandoned")
	check(Game.select_hero(hero) and Game.start_run(),hero+" isolated production run starts")
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.combat_audio.audible = false
	room.player.position = Vector2(820,530)
	for enemy in room.enemies.get_children():
		enemy.free()

func gameplay_state() -> Dictionary:
	return {"hp":Game.run.hp,"resource":Game.run.resource,"shield":Game.run.shield,
		"projectiles":room.projectiles.get_child_count(),"cooldowns":room.player.cooldowns.duplicate(true),
		"dash_cooldown":room.player.dash_cooldown,"shot_cooldown":room.player.shot_cooldown,
		"position":room.player.position,"stride":room.player.stride,"aim":room.player.aim_direction}

func open_lane() -> Vector2:
	for y in range(250,951,100):
		for x in range(300,1401,100):
			var at := Vector2(x,y)
			if room.valid_ground(at,Balance.PLAYER_RADIUS) and room.blocked_fraction(at,at+Vector2(230,0),Balance.PLAYER_RADIUS) >= 1.0:
				return at
	return Vector2.ZERO

func feedback_contracts(hero: String) -> void:
	fixture(hero)
	var player: HeroActor = room.player
	var feedback: HeroFeedback = player.get_node("HeroFeedback")
	var lane: Vector2 = open_lane()
	check(lane != Vector2.ZERO,hero+" production room has an unobstructed movement fixture lane")
	if lane == Vector2.ZERO:
		return
	player.position = lane
	player.velocity = Vector2.ZERO
	feedback.advance(.01)
	var initial_steps: int = feedback.locomotion_events
	# Placement jumps and requested velocity are not proof that a foot landed.
	player.position += Vector2(80,0)
	player.velocity = Vector2.RIGHT*player.stat("move_speed",220.0)
	var before: Dictionary = gameplay_state()
	feedback.advance(.01)
	check(feedback.locomotion_events == initial_steps and not feedback.motion_state().moving,hero+" instant fixture jump creates no walking stamp")
	check(gameplay_state() == before,hero+" jump observation changes no combat/player state")
	for index in 8:
		feedback.advance(.05)
	check(feedback.locomotion_events == initial_steps and not feedback.motion_state().moving,hero+" held velocity without resolved position change creates no steps")
	# Exercise the real input/collision-resolved movement path and shared FX budget.
	player.position = lane
	player.velocity = Vector2.ZERO
	feedback.advance(.01)
	room.input_blocked = false
	room.pointer_input_blocked = true
	for index in 70:
		feedback.class_event("brace",player.position,Vector2.RIGHT)
	var started_at: Vector2 = player.position
	Input.action_press("move_right")
	for index in 14:
		player._physics_process(.05)
	Input.action_release("move_right")
	player._physics_process(.001)
	var walked: float = player.position.distance_to(started_at)
	var steps: int = feedback.locomotion_events-initial_steps
	check(walked > 100.0 and room.valid_ground(player.position,Balance.PLAYER_RADIUS),hero+" actual input resolves walking on production floor")
	check(steps >= 2 and steps <= 7,hero+" resolved walk emits bounded footfall events (%d steps, %.1f travel, %.3f hitstop)" % [steps,walked,player.visual_hitstop])
	check(feedback.effects.size() <= 64 and feedback.effects.any(func(effect: Dictionary) -> bool: return str(effect.kind) == "footfall"),hero+" movement shares the bounded combat feedback queue")
	before = gameplay_state()
	feedback.advance(.01)
	feedback.motion_state()
	var pose: Dictionary = feedback.pose_state()
	Visual.presentation_direction(player.aim_direction,player.velocity,pose,false)
	check(gameplay_state() == before,hero+" footfall/facing sampling does not alter HP resource shots cooldowns aim position or stride")
	# A real pause holds existing stamps; resuming while still stationary cannot
	# replay the frozen interval as extra steps.
	var held_effects: Array = feedback.effects.duplicate(true)
	var held_steps: int = feedback.locomotion_events
	get_tree().paused = true
	feedback.advance(.6)
	player._physics_process(.6)
	check(feedback.effects == held_effects and feedback.locomotion_events == held_steps,hero+" pause holds feedback ages and locomotion events")
	check(player.position == before.position and is_equal_approx(player.stride,before.stride),hero+" paused movement preserves position and stride")
	get_tree().paused = false
	feedback.advance(.001)
	check(feedback.locomotion_events == held_steps,hero+" unpause cannot fabricate catch-up steps")
	# Hitstop can coexist with real locomotion. Observe that distance during the
	# frozen visual interval, then release input before visuals resume.
	player.position = lane
	player.velocity = Vector2.ZERO
	feedback.advance(.01)
	player.visual_hitstop = 1.0
	held_effects = feedback.effects.duplicate(true)
	held_steps = feedback.locomotion_events
	started_at = player.position
	Input.action_press("move_right")
	for index in 4:
		player._physics_process(.04)
	Input.action_release("move_right")
	player._physics_process(.001)
	check(player.position.distance_to(started_at) > 20.0,hero+" hitstop check uses actual resolved player movement")
	check(feedback.effects == held_effects and feedback.locomotion_events == held_steps,hero+" hitstop freezes FX without turning travel into footfalls")
	player.visual_hitstop = 0.0
	feedback.advance(.001)
	check(feedback.locomotion_events == held_steps,hero+" ending hitstop creates no accumulated phantom footfall")
	# Real dodge start/end stamps are visuals only, and mage's preparation keeps
	# the frozen dodge direction even when the live pointer aim changes.
	player.position = lane
	player.velocity = Vector2.ZERO
	feedback.advance(.01)
	check(player.start_dash(Vector2.UP),hero+" production dash begins for feedback acceptance")
	player.aim_direction = Vector2.LEFT
	before = gameplay_state()
	feedback.advance(.01)
	var state: Dictionary = feedback.motion_state()
	check(bool(state.dashing) and Vector2(state.direction).is_equal_approx(Vector2.UP),hero+" dash feedback keeps committed direction against live aim changes")
	check(feedback.effects.any(func(effect: Dictionary) -> bool: return str(effect.kind) == "dash_depart"),hero+" real dash start produces a departure stamp")
	var frame: Dictionary = Visual.presentation_frame_info(hero,"back",feedback.pose_state(),player.stride,false,true)
	Visual.body_transform(frame,hero,Vector2(state.direction),Vector2.ZERO,{"phase":"idle","dash_progress":.5})
	check(gameplay_state() == before,hero+" dodge pose/stamp sampling changes no gameplay state")
	player._tick_dash(.035)
	player.aim_direction = Vector2.DOWN
	feedback.advance(.01)
	check(Vector2(feedback.motion_state().direction).is_equal_approx(Vector2.UP),hero+" mid-dash feedback ignores later pointer redirection")
	if hero == "CH03":
		check(player.velocity == Vector2.ZERO,hero+" zero-velocity mage preparation still shows fixed dash travel direction")
	player._tick_dash(player.dash_remaining)
	before = gameplay_state()
	feedback.advance(.01)
	check(feedback.effects.any(func(effect: Dictionary) -> bool: return str(effect.kind) == "dash_land"),hero+" actual dash end produces one landing stamp")
	check(gameplay_state() == before and feedback.locomotion_events == held_steps,hero+" landing/teleport distance cannot fabricate steps or change gameplay")
	wall_slide_contract(hero)
	if hero in ["CH01","CH02"]:
		skill_travel_contract(hero,lane)

func wall_slide_contract(hero: String) -> void:
	var player: HeroActor = room.player
	var feedback: HeroFeedback = player.get_node("HeroFeedback")
	# The isolated default room can contain no solid props. A declared temporary
	# wall exercises production move_actor collision; it is never written to JSON.
	var saved_walls: Array[Rect2] = room.obstructions.duplicate()
	room.obstructions.append(Rect2(open_lane()+Vector2(90,-50),Vector2(40,110)))
	var wall_found := false
	for wall: Rect2 in room.obstructions:
		if wall.size.y < 40.0:
			continue
		var at := Vector2(wall.position.x-Balance.PLAYER_RADIUS-.01,wall.get_center().y)
		if not room.valid_ground(at,Balance.PLAYER_RADIUS) or room.blocked_fraction(at,at+Vector2(0,12),Balance.PLAYER_RADIUS) < 1.0:
			continue
		wall_found = true
		player.position = at
		player.velocity = Vector2.ZERO
		feedback.advance(.001)
		Visual._walk_is_moving(player,player.stride,player.velocity)
		Input.action_press("move_right")
		Input.action_press("move_down")
		var before: Vector2 = player.position
		player._physics_process(.02)
		var first: Vector2 = player.position
		player._physics_process(.02)
		before = player.position
		Visual._walk_is_moving(player,player.stride,player.velocity)
		player._physics_process(.02)
		var actual: Vector2 = player.position-before
		var walking: bool = Visual._walk_is_moving(player,player.stride,player.velocity)
		var direction: Vector2 = Visual.presentation_direction(player.aim_direction,player.velocity,feedback.pose_state(),walking,Vector2.ZERO,false,player.get_meta("_hero_visual_motion").direction)
		check(actual.y > .5 and absf(actual.x) < actual.y*.05 and first.y < player.position.y,hero+" real diagonal input slides down declared vertical obstruction")
		check(player.velocity.x > 1.0 and player.velocity.y > 1.0,hero+" wall-slide fixture retains diagonal requested velocity")
		check(walking and direction.is_equal_approx(actual.normalized()),hero+" body faces collision-resolved slide rather than diagonal request")
		check(Vector2(feedback.motion_state().direction).is_equal_approx(direction),hero+" walking body and floor-facing feedback agree on real wall slide")
		Input.action_release("move_right")
		Input.action_release("move_down")
		break
	check(wall_found,hero+" collision fixture provides a real obstruction for facing acceptance")
	room.obstructions = saved_walls

func skill_travel_contract(hero: String, lane: Vector2) -> void:
	var player: HeroActor = room.player
	var feedback: HeroFeedback = player.get_node("HeroFeedback")
	check(Game.grant_hero_xp(3600,"motion_travel:"+hero),hero+" fixture unlocks real Q through progression")
	Game.restore_resource(1000)
	player.position = lane
	player.velocity = Vector2.ZERO
	player.cooldowns.q = 0.0
	feedback.advance(.01)
	var count: int = feedback.locomotion_events
	var started_at: Vector2 = player.position
	check(player.cast_skill("q",lane+Vector2(100,0)),hero+" actual Q commits movement skill")
	var duration: float = float(player.abilities.active.spec.get("duration",.7))
	for index in ceili((duration+.05)/.01):
		player._physics_process(.01)
	check(player.position.distance_to(started_at) > 10.0,hero+" actual Q check exercises skill travel")
	check(feedback.locomotion_events == count,hero+" skill travel does not add ordinary walking footfalls")
	player.position = lane
	player.velocity = Vector2.ZERO
	player.cooldowns.q = 0.0
	Game.restore_resource(1000)
	feedback.advance(.01)
	count = feedback.locomotion_events
	started_at = player.position
	Input.action_press("move_down")
	check(player.cast_skill("q",lane+Vector2(100,0)),hero+" Q starts while real ordinary movement input is held")
	for index in ceili(duration*.65/.01):
		player._physics_process(.01)
	Input.action_release("move_down")
	player._physics_process(.001)
	check(player.abilities.busy() and player.position.distance_to(started_at) > 10.0,hero+" simultaneous Q/input check remains inside actual skill travel timeline")
	check(feedback.locomotion_events == count,hero+" held movement during Q cannot add ordinary footfalls over skill trail")
	player.cancel_actions()

func run_checks() -> void:
	if not str(Game.profile_path).contains("test_hero_motion_detail"):
		push_error("Refusing non-isolated hero motion detail profile")
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated profile starts")
	var idle := {"phase":"idle","slot":"basic","direction":Vector2.RIGHT,"progress":0.0}
	var attack := {"phase":"release","slot":"basic","direction":Vector2.RIGHT,"progress":0.0}
	check(Visual.presentation_direction(Vector2.RIGHT,Vector2.UP*200,idle,true).is_equal_approx(Vector2.UP),"walking body faces actual travel without changing pointer aim")
	check(Visual.presentation_direction(Vector2.RIGHT,Vector2.UP*200,idle,false).is_equal_approx(Vector2.RIGHT),"blocked movement retains aim rather than skating direction")
	check(Visual.presentation_direction(Vector2.RIGHT,Vector2.UP*200,attack,true).is_equal_approx(Vector2.RIGHT),"committed attack overrides simultaneous movement")
	check(Visual.presentation_direction(Vector2.RIGHT,Vector2.ZERO,idle,false,Vector2.UP,true).is_equal_approx(Vector2.UP),"teleport body uses fixed dash direction while velocity is zero")
	for hero: String in ["CH01","CH02","CH03"]:
		for bank: String in ["front","back"]:
			var aim := Vector2(-1,-.6 if bank == "back" else .6).normalized()
			var source: Dictionary = Visual.presentation_frame_info(hero,bank,idle,7.0,true,true)
			check(not source.is_empty() and str(source.get("phase","")) == "dodge",hero+" "+bank+" selects a low authored dodge body instead of walk/idle")
			if source.is_empty():
				continue
			check(str(source.get("source_phase","")) in ["recovery","windup"],hero+" dodge retains its authored source phase")
			check(is_equal_approx(float(source.body_height),Visual.GENERATED_HEIGHT),hero+" dodge preserves shared anatomy scale")
			for progress: float in [0.0,.5,1.0]:
				var pose: Dictionary = idle.duplicate()
				pose["dash_progress"] = progress
				var body: Transform2D = Visual.body_transform(source,hero,aim,Vector2(20,-6),pose,true,7.0)
				check((body*Vector2(0,Visual.FOOT_OFFSET)).is_equal_approx(Vector2(0,Visual.FOOT_OFFSET)),hero+" dodge leaves sole midpoint fixed through anticipation/contact/settle")
				check(body.x.is_finite() and body.y.is_finite() and absf(body.determinant()) > .90,hero+" dodge keeps intact nondegenerate silhouette")
				if hero == "CH02":
					check(is_zero_approx(body.x.y) and is_zero_approx(body.y.x),"gunner dodge preserves unrotated shoulder/body anatomy")
			# The real release launch path must still equal the body attachment.
			var released: Dictionary = Visual.presentation_frame_info(hero,bank,attack,0.0,false)
			var lean: Vector2 = aim*(5.0 if hero == "CH01" else 1.5)
			var body: Transform2D = Visual.body_transform(released,hero,aim,lean,attack)
			var muzzle: Vector2 = released.anchors.get("muzzle",released.anchors.get("right_hand",Vector2(26,-28)))
			check((body*muzzle).is_equal_approx(Visual.release_muzzle_local(hero,"basic",aim)),hero+" normal launch matches committed release pixels after movement changes")
		fixture(hero)
		room.player.aim_direction = Vector2.RIGHT
		check(room.player.start_dash(Vector2.UP),hero+" actual player dash starts")
		room.player._tick_dash(.035)
		var shown: Vector2 = Visual.presentation_direction(room.player.aim_direction,room.player.velocity,idle,false,room.player.dash_direction,room.player.dash_remaining > 0.0)
		check(shown.is_equal_approx(Vector2.UP),hero+" actual dash shows its movement direction against contrary pointer aim")
		check(room.player.aim_direction.is_equal_approx(Vector2.RIGHT),hero+" visual direction leaves aiming state untouched")
		if hero == "CH03":
			check(room.player.velocity == Vector2.ZERO,"mage remains physically stationary during teleport preparation")
	var mage: Dictionary = Visual.presentation_frame_info("CH03","front",idle,7.0,true)
	check(str(mage.phase) == "idle" and Visual.walk_frame_info("CH03","front",90.0).is_empty(),"rejected mage walk sheet remains disabled")
	var mage_body: Transform2D = Visual.body_transform(mage,"CH03",Vector2.RIGHT,Vector2(5,-3),idle,true,7.0)
	check((mage_body*Vector2(0,Visual.FOOT_OFFSET)).is_equal_approx(Vector2(0,Visual.FOOT_OFFSET)),"mage walking refinement grounds approved idle body")
	check(absf(mage_body.y.x) <= .0121 and mage_body.y.y >= .9879,"mage walking torso sway stays restrained")
	for hero: String in ["CH01","CH02","CH03"]:
		feedback_contracts(hero)
	if is_instance_valid(room):
		room.free()
	print("HERO MOTION DETAIL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
