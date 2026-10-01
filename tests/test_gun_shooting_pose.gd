extends SceneTree
## Headless rules/presentation contract, using real accepted fire/cast events.
## Manual 1 ms player ticks and an empty arena isolate timing, not balance or
## native animation quality. Existing images are read-only; no renderer/GPU claim.
const Visual = preload("res://scripts/combat/hero_visual.gd")
const Atlas = preload("res://scripts/combat/hero_skill_atlas.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Metrics = preload("res://scripts/combat/presentation_metrics.gd")
const STABLE := ["brace", "lock", "absorb"]
var game: Node
var room: Node2D
var room_scene: PackedScene
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GUN SHOOTING POSE FAIL: " + label)

func _fixture(direction: Vector2 = Vector2.RIGHT, reduced_fx: bool = false) -> void:
	if is_instance_valid(room):
		room.combat_audio.stop_all()
		room.free()
	game.run.hero_id = "CH02"
	game.run.level = 8
	game.run.stats = Resolver.resolve("CH02",8,{}, {})
	game.run.stats.crit_chance = 0.0
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"reduced_fx":reduced_fx, "muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":1.0},true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.obstructions.clear()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.player.position = Vector2(600,350)
	room.player.aim_direction = direction.normalized()
	room.player.resource_delay = 1000.0

func _tick(duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.0000001:
		var step: float = minf(0.001,remaining)
		room.elapsed += step
		room.player._physics_process(step)
		remaining -= step

func _presentation() -> Dictionary:
	var feedback: Node = room.player.get_node("HeroFeedback")
	var pose: Dictionary = Visual.gunner_presentation_pose(room.player,feedback.pose_state())
	var direction: Vector2 = pose.direction.normalized()
	var bank: String = "back" if direction.y < -0.20 else "front"
	return {"pose":pose, "direction":direction, "bank":bank,
		"frame":Visual.presentation_frame_info("CH02",bank,pose,room.player.stride,room.player.velocity.length_squared()>4.0,room.player.dash_remaining>0.0)}

func _check_release_anchor(slot: String, label: String) -> void:
	var sample: Dictionary = _presentation()
	var frame: Dictionary = sample.frame
	check(frame.get("gun_shooting_pose",false) and frame.get("frame_name") == "lock", label + " accepted release keeps rifle shouldered")
	if not bool(frame.get("gun_shooting_pose",false)): return
	var direction: Vector2 = sample.direction
	var offset: Vector2 = Visual._action_offset(frame,"CH02",direction,Vector2(50,50),sample.pose)
	var flip: float = -1.0 if direction.x < -0.05 else 1.0
	var presented_muzzle: Vector2 = offset + Vector2(frame.anchors.muzzle) * Vector2(flip,1)
	check(presented_muzzle.distance_to(Visual.release_muzzle_local("CH02",slot,direction)) < 0.03, label + " launch helper uses the actual selected body frame and recoil")
	check(offset.length() < 2.0, label + " authored recoil remains below two world pixels")

func _test_source_mapping() -> void:
	for bank: String in ["front","back"]:
		var source: Dictionary = Atlas.load_clip("res://assets/generated/heroes/CH02_secondary_%s_v1.json" % bank)
		check(not source.is_empty(), bank + " existing approved source loads")
		if source.is_empty(): continue
		check(source.frames.size() == 6 and Atlas.sample_clip(source,"release",0.0).get("frame_name") == "fire", bank + " raw six-source-frame sampler remains unchanged")
		for slot: String in ["basic","q","secondary","ultimate"]:
			for phase: String in ["windup","release","recovery"]:
				for progress: float in [0.0,0.49,0.99,1.0]:
					var pose: Dictionary = {"slot":slot,"phase":phase,"progress":progress,"authored_phase_progress":progress}
					var frame: Dictionary = Visual.presentation_frame_info("CH02",bank,pose,20.0,true)
					check(frame.get("frame_name") in STABLE and frame.get("gun_shooting_pose",false), bank + " " + slot + " " + phase + " selects a stable shoulder pose")
					if not bool(frame.get("gun_shooting_pose",false)): continue
					var raw: Dictionary = source.frames[str(frame.frame_name)]
					check(frame.region == raw.region and frame.bounds == raw.bounds and frame.anchors == raw.anchors and frame.body_height == Metrics.HERO_BODY_HEIGHT, "registration preserves full authored body, shoulder/grip/muzzle, fixed anatomy and foot")
		var light: Dictionary = Visual.presentation_frame_info("CH02",bank,{"slot":"basic","phase":"release","progress":0.0},0.0,false)
		var heavy: Dictionary = Visual.presentation_frame_info("CH02",bank,{"slot":"secondary","phase":"release","progress":0.0},0.0,false)
		check(float(heavy.get("gun_recoil",0.0)) > float(light.get("gun_recoil",0.0)) and float(heavy.get("gun_recoil",2.0)) < 2.0, "secondary recoil is more distinct while remaining restrained")
		check(not Visual.presentation_frame_info("CH02",bank,{"slot":"f","phase":"release","progress":0.0},0.0,false).get("gun_shooting_pose",false), "trap placement does not become rifle shooting")
		check(not Visual.presentation_frame_info("CH02",bank,{"slot":"basic","phase":"release","progress":0.0},0.0,false,true).get("gun_shooting_pose",false), "dash keeps priority over shooting pose")

func _test_basic_chain() -> void:
	_fixture()
	var player: Node2D = room.player
	check(player.fire(Vector2.RIGHT), "first actual basic accepted")
	_check_release_anchor("basic","basic")
	var first: Node2D = room.projectiles.get_child(0)
	var before: Dictionary = {"position":first.position, "direction":first.direction, "damage":first.damage, "speed":first.speed, "range":first.distance_left}
	var accepted: int = 1
	var stable: bool = true
	var held_gap: bool = false
	for _step: int in 1000:
		_tick(0.001)
		if player.shot_cooldown <= 0.0:
			check(player.fire(Vector2.RIGHT), "next basic accepted at real cooldown boundary")
			accepted += 1
		var sample: Dictionary = _presentation()
		stable = stable and sample.frame.get("frame_name") in ["lock","absorb"]
		held_gap = held_gap or bool(sample.pose.get("gun_hold",false))
		if accepted == 3: break
	check(accepted == 3 and held_gap and stable, "three naturally spaced basics never lower then raise the rifle between shots")
	check(room.projectiles.get_child_count() == 3, "presentation never creates duplicate basic projectiles")
	check(first.position == before.position and first.direction == before.direction and first.damage == before.damage and first.speed == before.speed and first.distance_left == before.range, "pose sampling cannot alter frozen projectile physics")
	check(is_equal_approx(first.speed,950.0) and is_equal_approx(first.damage,player.attack_power()), "basic retains existing speed and damage")
	_tick(float(player.shot_cooldown)+0.01)
	check(not _presentation().frame.get("gun_shooting_pose",false), "stopped firing returns to normal idle after real cooldown")

func _cast_trace(slot: String, direction: Vector2, reduced_fx: bool = false) -> Dictionary:
	_fixture(direction,reduced_fx)
	var player: Node2D = room.player
	var feedback: Node = player.get_node("HeroFeedback")
	var spec: Dictionary = player.skill_definition(slot)
	check(player.cast_skill(slot,player.position+direction*150.0), "actual " + slot + " cast accepted")
	var timeline: Array = player.abilities.active.events.duplicate(true)
	var cost_after: float = game.run.resource
	check(is_equal_approx(cost_after,100.0-float(spec.cost)) and is_equal_approx(player.cooldowns[slot],float(spec.cooldown)), slot + " resource and cooldown commit unchanged")
	var seen: Array[String] = []
	var released: int = 0
	var stable: bool = true
	var release_times: Array[float] = []
	for step: int in ceili(float(spec.duration)/0.001)+1:
		_tick(0.001)
		var sample: Dictionary = _presentation()
		if sample.pose.phase != "idle":
			stable = stable and sample.frame.get("frame_name") in STABLE
			if not seen.has(str(sample.frame.get("frame_name",""))): seen.append(str(sample.frame.get("frame_name","")))
		if feedback.release_events.size() > released:
			release_times.append((step+1)*0.001)
			_check_release_anchor(slot,slot + " release %d" % released)
			check(absf(release_times.back()-float(timeline[released].time)) <= 0.002, slot + " actual release remains on its committed timeline")
			released = feedback.release_events.size()
	check(stable and not seen.has("fire") and not seen.has("ready") and not seen.has("shoulder"), slot + " windup/recovery between burst shots never uses throwback or lowered-rifle cells")
	check(released == timeline.size() and room.projectiles.get_child_count() == timeline.size(), slot + " emits exactly the unchanged committed projectile count")
	check(not player.abilities.busy(), slot + " rendering leaves gameplay recovery duration unchanged")
	var total_damage: float = 0.0
	for projectile: Node2D in room.projectiles.get_children():
		total_damage += projectile.damage
		check(projectile.direction.is_finite() and projectile.speed == float(spec.speed), slot + " projectile retains authored direction and speed")
	return {"times":release_times, "damage":total_damage, "resource":cost_after}

func _test_completed_cast_to_basic() -> void:
	_cast_trace("ultimate",Vector2.RIGHT)
	var feedback: Node = room.player.get_node("HeroFeedback")
	check(not room.player.abilities.busy() and not feedback._cast.is_empty(), "fixture reaches real finished R with residual visual tail")
	check(room.player.fire(Vector2.RIGHT), "basic can fire immediately after real R recovery")
	var sample: Dictionary = _presentation()
	check(sample.pose.slot == "basic" and sample.pose.phase == "release" and sample.frame.get("frame_name") == "lock", "new actual basic overrides old skill presentation tail")
	_check_release_anchor("basic","post-R basic")

func _test_mirror_and_fallback() -> void:
	for y: float in [0.4,-0.4]:
		var right := Vector2(1,y).normalized()
		var left := Vector2(-1,y).normalized()
		for direction: Vector2 in [right,left]:
			_fixture(direction)
			check(room.player.fire(direction), "front/back mirrored real basic accepted")
			_check_release_anchor("basic","mirrored basic")
		var a: Vector2 = Visual.release_muzzle_local("CH02","basic",right)
		var b: Vector2 = Visual.release_muzzle_local("CH02","basic",left)
		check(a.is_equal_approx(b*Vector2(-1,1)), "horizontal mirroring also mirrors recoil and physical frame muzzle anchor")
	var path: String = "res://assets/generated/heroes/CH02_secondary_front_v1.json"
	var saved: Dictionary = Atlas._clips.get(path,{})
	Atlas._clips[path] = {}
	_fixture()
	check(room.player.fire(Vector2.RIGHT), "missing shoulder atlas cannot block real fire")
	var fallback: Dictionary = _presentation().frame
	check(not fallback.is_empty() and not fallback.get("gun_shooting_pose",false) and fallback.phase == "release", "missing atlas retains existing action fallback")
	Atlas._clips[path] = saved

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_gun_shooting_pose"):
		push_error("Refusing non-isolated gun shooting pose profile")
		quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	check(game.new_profile() and game.start_run(), "isolated actual run starts")
	if game.run == null:
		quit(1)
		return
	room_scene = load("res://scenes/room.tscn")
	_test_source_mapping()
	_test_basic_chain()
	for slot: String in ["q","secondary","ultimate"]: _cast_trace(slot,Vector2.RIGHT)
	var regular: Dictionary = _cast_trace("ultimate",Vector2(1,-0.4).normalized(),false)
	var reduced: Dictionary = _cast_trace("ultimate",Vector2(1,-0.4).normalized(),true)
	check(regular == reduced, "reduced FX preserves burst timing, damage and resource")
	_test_completed_cast_to_basic()
	_test_mirror_and_fallback()
	check(await room.combat_audio.wait_for_cleanup(), "audio cleanup completed")
	room.free()
	print("GUN SHOOTING POSE: %d checks, %d failures; stable shoulder mapping, two facing banks only; no GPU/visual approval claim" % [checks,failures])
	quit(0 if failures == 0 else 1)
