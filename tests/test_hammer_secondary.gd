extends SceneTree
## Real cast/hit/physics acceptance. Fixed M01 targets and 1 ms manual player
## ticks isolate event boundaries; this is not balance, graphics or listening QA.
## Parser fixtures use existing images read-only and replace only process-local
## clip cache entries. Production enabled assets are checked last; pass
## --fixtures-only while art is still awaiting approval. No image is generated.
const Atlas = preload("res://scripts/combat/hero_skill_atlas.gd")
const Visual = preload("res://scripts/combat/hero_visual.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const NAMES := ["plant", "coil", "drive", "contact", "follow", "ready"]
const PLAYER_AT := Vector2(500, 350)
var game: Node
var room: Node2D
var room_scene: PackedScene
var fixture_directory: String
var saved_cache: Dictionary = {}
var fixture_clips: Dictionary = {}
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HAMMER SECONDARY FAIL: " + label)

func _key(bank: String) -> String:
	return "res://assets/generated/heroes/CH01_secondary_%s_v1.json" % bank

func _write_json(name: String, data: Dictionary) -> String:
	var path: String = fixture_directory.path_join(name + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated JSON fixture opens: " + name)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()
	return path

func _manifest(bank: String) -> Dictionary:
	var frames: Array = []
	for index: int in NAMES.size():
		# Distinct parser regions, not a claim these old pixels depict a sweep.
		var x: int = 64 + index * 96
		frames.append({"name":NAMES[index], "region":[x,64,80,80], "foot":[x+40,136],
			"head":[x+40,70], "grip":[x+50,108], "muzzle":[x+72,104]})
	return {"schema_version":1, "hero_id":"CH01", "slot":"secondary", "bank":bank, "enabled":true,
		"texture":"res://assets/generated/heroes/CH01_actions_%s_v2.png" % bank, "body_height":66.0, "frames":frames,
		"phase_frames":{"windup":["plant","coil","drive"], "release":["contact"], "recovery":["follow","ready"]},
		"phase_weights":{"windup":[1.0,1.0,1.0], "release":[1.0], "recovery":[1.0,1.0]}}

func _prepare_fixtures() -> bool:
	fixture_directory = game.profile_path.get_base_dir().path_join("hammer_secondary_fixtures")
	check(DirAccess.make_dir_recursive_absolute(fixture_directory) == OK, "isolated fixture directory created")
	for bank: String in ["front", "back"]:
		var key: String = _key(bank)
		saved_cache[key] = {"present":Atlas._clips.has(key), "clip":Atlas._clips.get(key, {})}
		var clip: Dictionary = Atlas.load_clip(_write_json(bank, _manifest(bank)))
		check(not clip.is_empty(), bank + " CH01 secondary six-frame contract loads")
		if clip.is_empty(): return false
		fixture_clips[bank] = clip
		Atlas._clips[key] = clip
	return true

func _restore_cache() -> void:
	for key: String in saved_cache:
		if saved_cache[key].present: Atlas._clips[key] = saved_cache[key].clip
		else: Atlas._clips.erase(key)

func _fixture(level: int = 8, reduced_fx: bool = false, direction: Vector2 = Vector2.RIGHT) -> void:
	if is_instance_valid(room):
		room.combat_audio.stop_all()
		room.free()
	game.run.hero_id = "CH01"
	game.run.level = level
	game.run.stats = Resolver.resolve("CH01", level, {}, {})
	game.run.stats.crit_chance = 0.0
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":1.0, "reduced_fx":reduced_fx}, true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true # Keep the OS cursor from overriding committed test aim.
	room.obstructions.clear()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.player.position = PLAYER_AT
	room.player.aim_direction = direction.normalized()
	room.player.combat_time = 1000.0 # Isolate cast expenditure from out-of-combat rage decay.

func _dummy(at: Vector2) -> Node2D:
	var enemy: Node2D = room.spawn_enemy(at, "M01")
	enemy.health.reset(10000.0)
	enemy.state = &"chase"
	return enemy

func _feedback() -> Node:
	return room.player.get_node("HeroFeedback")

func _frame() -> Dictionary:
	var pose: Dictionary = _feedback().pose_state()
	var direction: Vector2 = pose.direction
	return Visual.presentation_frame_info("CH01", "back" if direction.y < -0.20 else "front", pose, 20.0, true, room.player.dash_remaining > 0.0)

func _tick(duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.0000001:
		var step: float = minf(0.001, remaining)
		room.elapsed += step
		room.player._physics_process(step)
		remaining -= step

func _trace(level: int, bank: String, reduced_fx: bool, label: String) -> Dictionary:
	var direction := Vector2(1.0, -0.4 if bank == "back" else 0.4).normalized()
	_fixture(level, reduced_fx, direction)
	var target: Node2D = _dummy(PLAYER_AT + direction * 90.0)
	var feedback: Node = _feedback()
	var spec: Dictionary = room.player.skill_definition("secondary")
	check(room.player.cast_skill("secondary", target.position), label + " actual cast accepted")
	check(is_equal_approx(game.run.resource, 100.0 - float(spec.cost)) and is_equal_approx(room.player.cooldowns.secondary, float(spec.cooldown)), label + " resource and cooldown commit once")
	var seen: Array[String] = []
	var release_time: float = -1.0
	var finish_time: float = -1.0
	var hit_time: float = -1.0
	var contact_valid: bool = false
	var recovery_started: bool = false
	var recovery_from_zero: bool = false
	var before: float = target.health.current
	for index: int in 821:
		if index > 0: _tick(0.001)
		var time: float = index * 0.001
		var frame: Dictionary = _frame()
		var pose: Dictionary = feedback.pose_state()
		if not recovery_started and str(pose.phase) == "recovery":
			recovery_started = true
			recovery_from_zero = pose.has("authored_phase_progress") and float(pose.authored_phase_progress) < 0.02
		if bool(frame.get("skill_sequence", false)):
			var frame_name: String = str(frame.get("frame_name", ""))
			if not seen.has(frame_name): seen.append(frame_name)
		if feedback.release_events.size() > 0 and release_time < 0.0: release_time = time
		if not room.player.abilities.busy() and finish_time < 0.0: finish_time = time
		if target.health.current < before and hit_time < 0.0:
			hit_time = time
			contact_valid = feedback.impact_events > 0 and feedback.release_events.size() == 1 and frame.get("frame_name") == "contact" and str(_feedback().pose_state().phase) == "release"
	check(seen == NAMES, label + " real physics samples all six poses in authored order")
	check(absf(release_time - 0.18) <= 0.002 and absf(hit_time - release_time) <= 0.0011, label + " contact pose shares actual 180 ms release and confirmed damage")
	check(contact_valid, label + " actual confirmed hit is accompanied by contact, not cached windup")
	check(recovery_started and recovery_from_zero, label + " actual release transitions into full authored recovery from zero")
	check(absf(finish_time - (0.46 if level >= 12 else 0.54)) <= 0.002, label + " real recovery finishes at level-specific duration despite visual stop")
	check(feedback.release_events.size() == 1 and feedback.impact_events == 1, label + " whole six-frame presentation produces exactly one release and one confirmed impact")
	check(not room.player.abilities.busy(), label + " completed clip cannot keep gameplay cast busy")
	return {"damage":before-target.health.current, "release_time":release_time, "finish_time":finish_time, "seen":seen}

func _test_real_hitstop_and_aim() -> void:
	_fixture()
	var direction: Vector2 = Vector2.from_angle(PI / 6.0)
	var target: Node2D = _dummy(PLAYER_AT + direction * 90.0)
	check(room.player.cast_skill("secondary", target.position), "tracking cast starts facing right")
	room.player.aim_direction = Vector2.DOWN
	_tick(0.179)
	var windup: Dictionary = _feedback().pose_state()
	check(windup.phase == "windup" and target.health.current == 10000.0, "sampled pre-release pose has not damaged target")
	check(absf(Vector2.RIGHT.angle_to(windup.direction) - PI / 6.0) < 0.001, "hammer windup follows aim only within committed 30-degree cone")
	_tick(0.002)
	var frozen: Dictionary = _feedback().pose_state()
	check(target.health.current < 10000.0 and room.player.visual_hitstop > 0.0 and _frame().get("frame_name") == "contact", "real hit replaces previously cached windup with contact under hitstop")
	var elapsed: float = room.player.abilities.active.elapsed
	room.player.aim_direction = Vector2.UP
	_tick(0.01)
	check(_feedback().pose_state() == frozen and _frame().get("frame_name") == "contact", "actual hitstop freezes contact pose")
	check(float(room.player.abilities.active.elapsed) > elapsed, "visual hitstop does not stop the gameplay timeline")
	check(Vector2(room.player.abilities.active.direction).is_equal_approx(direction), "post-release aim changes do not rotate committed sweep")
	room.player.cancel_actions()
	check(_feedback().pose_state().phase == "idle" and not _frame().get("skill_sequence", false), "cancel clears a real frozen skill pose immediately")

func _damage_sample(stacks: int, reduced_fx: bool = false) -> Dictionary:
	_fixture(8, reduced_fx)
	room.player.gain_break_stacks(stacks)
	var center: Node2D = _dummy(PLAYER_AT + Vector2(90,0))
	var extended: Node2D = _dummy(PLAYER_AT + Vector2(130,0))
	var flank: Node2D = _dummy(PLAYER_AT + Vector2.from_angle(deg_to_rad(70.0)) * 90.0)
	var outside: Node2D = _dummy(PLAYER_AT + Vector2(145,0))
	check(room.player.cast_skill("secondary", center.position), "real sweep commits with %d momentum" % stacks)
	check(room.player.break_stacks == 0 and is_equal_approx(game.run.resource,100.0 if stacks == 3 else 70.0), "sweep consumes Momentum; full three-stack sweep costs no Rage")
	_tick(0.179)
	check(center.health.current == 10000.0 and extended.health.current == 10000.0, "neither normal nor extended victim is hit during windup")
	_tick(0.002)
	check(center.health.current < 10000.0 and outside.health.current == 10000.0, "release hits central victim but respects maximum radial reach")
	check((extended.health.current < 10000.0) == (stacks == 3) and (flank.health.current < 10000.0) == (stacks == 3), "full momentum expands both actual radius and actual arc")
	check(str(center.last_damage_context.get("skill_slot", "")) == "secondary" and not bool(center.last_damage_context.get("original_basic", true)), "real sweep damage retains skill attribution")
	check(_frame().get("frame_name") == "contact", "damage sample presents the authored contact pose")
	return {"damage":10000.0-center.health.current, "extended":10000.0-extended.health.current, "flank":10000.0-flank.health.current}

func _test_cancel_and_cost() -> void:
	_fixture()
	var target: Node2D = _dummy(PLAYER_AT + Vector2(90,0))
	game.run.resource = 29.0
	room.player.gain_break_stacks(2)
	check(not room.player.cast_skill("secondary",target.position) and room.player.break_stacks == 2 and room.player.cooldowns.secondary == 0.0, "non-full Momentum still requires Rage without spending stacks on rejection")
	game.run.resource = 30.0
	check(room.player.cast_skill("secondary",target.position) and game.run.resource == 0.0, "exactly thirty rage can commit sweep")
	check(not room.player.cast_skill("secondary",target.position), "committed cast cannot be duplicated")
	_tick(0.10)
	check(room.player.start_dash(Vector2.LEFT), "actual defensive dash cancels committed windup")
	_tick(0.50)
	check(target.health.current == 10000.0 and _feedback().release_events.is_empty(), "dash cancellation drops future release and damage")
	check(room.player.break_stacks == 0 and game.run.resource == 0.0 and room.player.cooldowns.secondary > 0.0, "cancel does not refund momentum, resource, or cooldown")
	check(not _frame().get("skill_sequence", false), "cancelled skill cannot override dash or idle art")

func _test_banks_and_mirror() -> void:
	for y: float in [0.4, -0.4]:
		var bank: String = "back" if y < 0.0 else "front"
		var right := Vector2(1,y).normalized()
		var left := Vector2(-1,y).normalized()
		for aim: Vector2 in [right,left]:
			_fixture(8, false, aim)
			check(room.player.cast_skill("secondary",PLAYER_AT+aim*90.0), bank + " directed whiff cast starts")
			_tick(0.181)
			var frame: Dictionary = _frame()
			check(frame.get("bank") == bank and frame.get("frame_name") == "contact", bank + " release uses pose aim to select authored bank")
			check(_feedback().impact_events == 0 and room.player.visual_hitstop == 0.0, "authored release on a whiff does not fabricate impact or hitstop")
			check(frame.anchors.foot == Vector2(0,8) and frame.body_height == 88.0, bank + " authored source keeps fixed ground and body scale")
			check(Visual._action_offset(frame,"CH01",aim,Vector2(20,20),_feedback().pose_state()) == Vector2.ZERO, "authored sweep suppresses procedural body lean/release shove")
		var right_anchor: Vector2 = Visual.release_muzzle_local("CH01","secondary",right)
		var left_anchor: Vector2 = Visual.release_muzzle_local("CH01","secondary",left)
		check(right_anchor.is_equal_approx(left_anchor * Vector2(-1,1)), bank + " production release-anchor transform mirrors X and preserves Y")

func _test_missing_fallback() -> void:
	for mode: String in ["disabled", "missing_texture"]:
		var data: Dictionary = _manifest("front")
		if mode == "disabled": data.enabled = false
		else: data.texture = fixture_directory.path_join("absent.png")
		check(Atlas.load_clip(_write_json(mode,data)).is_empty(), mode + " clip safely rejects loading")
	for bank: String in ["front","back"]: Atlas._clips[_key(bank)] = {}
	_fixture()
	var target: Node2D = _dummy(PLAYER_AT+Vector2(90,0))
	check(room.player.cast_skill("secondary",target.position), "missing authored assets do not reject skill")
	_tick(0.181)
	var fallback: Dictionary = _frame()
	check(target.health.current < 10000.0 and _feedback().release_events.size() == 1 and _feedback().impact_events == 1, "missing assets preserve real release and confirmed damage")
	check(not fallback.is_empty() and fallback.phase == "release" and not fallback.get("skill_sequence",false), "missing assets use established action-phase fallback")
	for bank: String in ["front","back"]: Atlas._clips[_key(bank)] = fixture_clips[bank]

func _check_production_assets() -> void:
	for bank: String in ["front","back"]:
		Atlas._clips.erase(_key(bank))
		var clip: Dictionary = Atlas.load_clip(_key(bank))
		check(not clip.is_empty(), bank + " production metadata is enabled and loads")
		if clip.is_empty(): continue
		var regions: Array = []
		for frame_name: String in NAMES:
			var frame: Dictionary = clip.frames.get(frame_name,{})
			check(not frame.is_empty(), bank + " production has " + frame_name)
			if frame.is_empty(): continue
			check(not regions.has(frame.region) and frame.anchors.has("head") and frame.anchors.has("grip") and frame.anchors.has("muzzle"), bank + " independent region/anchors for " + frame_name)
			regions.append(frame.region)
		_trace(8,bank,false,"production " + bank)

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_hammer_secondary"):
		push_error("Refusing non-isolated hammer secondary profile")
		quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	check(game.new_profile() and game.start_run(), "isolated hammer run starts")
	room_scene = load("res://scenes/room.tscn")
	var fixtures_only: bool = "--fixtures-only" in OS.get_cmdline_user_args()
	if game.run != null and _prepare_fixtures():
		var normal: Dictionary = _trace(8,"front",false,"level8 front")
		_trace(12,"back",false,"level12 back")
		var reduced: Dictionary = _trace(8,"front",true,"reduced FX")
		check(is_equal_approx(normal.damage,reduced.damage) and normal.release_time == reduced.release_time and normal.finish_time == reduced.finish_time, "reduced FX preserves damage and real release/recovery timing")
		_test_real_hitstop_and_aim()
		var base: Dictionary = _damage_sample(0)
		var full: Dictionary = _damage_sample(3)
		check(base.damage > 0.0 and is_equal_approx(float(full.damage)/float(base.damage),3.55/2.2), "actual damage scales from 2.2 to 3.55 power at full momentum")
		_test_cancel_and_cost()
		_test_banks_and_mirror()
		_test_missing_fallback()
	_restore_cache()
	if game.run != null and not fixtures_only: _check_production_assets()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "audio cleanup completed")
		room.free()
	print("HAMMER SECONDARY: %d checks, %d failures; fixtures_only=%s; fixed targets/manual 1 ms ticks; no visual approval claim" % [checks,failures,str(fixtures_only)])
	quit(0 if failures == 0 else 1)
