extends SceneTree
## Body presentation acceptance without EnemyActor, a live run, asset imports,
## image capture or a GPU. Run: tools/test.ps1 -Suite enemy_presentation -SkipImport

const Visual = preload("res://scripts/presentation/monsters/enemy_visual.gd")
var failures: Array[String] = []
var checks: int = 0

class BrainStub:
	extends RefCounted
	var progress: float = 0.0
	func current_telegraph() -> Dictionary:
		return {"progress":progress}

class PropsStub:
	extends RefCounted
	var carrying: bool = false
	func carried_by(_actor: Node2D) -> bool:
		return carrying

class RoomStub:
	extends Node2D
	var enemy_props: RefCounted = PropsStub.new()

class ActorStub:
	extends Node2D
	var profile: Dictionary = {"archetype":"skirmisher"}
	var enemy_id: String = ""
	var body_bounds := Rect2(-30, -52, 60, 70)
	var body_region := Rect2(20, 10, 60, 70)
	var body_texture: Texture2D
	var empty_body_texture: Texture2D
	var state: StringName = &"chase"
	var state_time: float = 0.0
	var aim_direction := Vector2.RIGHT
	var move_speed: float = 100.0
	var knockback := Vector2.ZERO
	var reaction_remaining: float = 0.0
	var brain: RefCounted = BrainStub.new()
	var velocity := Vector2(100, 0)
	var navigation_radius: float = 17.0
	var room: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _fixture(role: String = "skirmisher") -> Array:
	var actor := ActorStub.new()
	actor.profile.archetype = role
	root.add_child(actor)
	var visual := Visual.new()
	actor.add_child(visual)
	visual.reduced_fx_override = 0
	visual.configure(actor)
	return [actor, visual]

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	_test_displacement()
	_test_phases()
	_test_recoil_and_pause()
	_test_archetypes()
	_test_manifest_and_anchors()
	_test_production_manifest()
	_test_empty_m35()
	if failures.is_empty():
		print("ENEMY PRESENTATION PASS: %d checks" % checks)
	quit(0 if failures.is_empty() else 1)

func _test_displacement() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	var original_bounds: Rect2 = actor.body_bounds
	for i in 20:
		visual.advance(0.016)
	_check(is_zero_approx(visual.stride_phase) and is_zero_approx(visual.movement_weight), "Desired velocity while blocked never creates footfalls")
	actor.position += Vector2(6, 0)
	visual.advance(0.06)
	_check(visual.stride_phase > 0.0 and visual.movement_weight > 0.5, "Resolved displacement advances the gait")
	var stride: float = visual.stride_phase
	for i in 20:
		visual.advance(0.016)
	_check(is_equal_approx(stride, visual.stride_phase) and is_zero_approx(visual.movement_weight), "Blocked body settles and stops its cycle")
	actor.position += Vector2(300, 0)
	visual.advance(0.016)
	_check(is_equal_approx(stride, visual.stride_phase), "Teleport correction does not fast-forward the walk cycle")
	actor.knockback = Vector2(100, 0)
	actor.position += Vector2(2, 0)
	visual.advance(0.016)
	_check(is_equal_approx(stride, visual.stride_phase), "Knockback sliding does not become walking")
	_check(actor.body_bounds == original_bounds and actor.velocity == Vector2(100,0) and actor.navigation_radius == 17.0, "Presentation leaves body bounds, velocity and navigation unchanged")
	actor.free()

func _test_phases() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	actor.state = &"telegraph"
	actor.state_time = 0.6
	actor.brain.progress = 0.7
	visual.advance(0.016)
	var prepare: Vector2 = visual.body_offset
	_check(prepare.x < -1.0 and is_equal_approx(visual.phase_progress, 0.7), "Telegraph tracks the brain's public progress and leans back")
	actor.state = &"locked"
	actor.state_time = 0.4
	actor.brain.progress = 0.0
	visual.advance(0.016)
	var locked: Vector2 = visual.body_offset
	_check(locked.x < prepare.x and visual.body_scale.y < 1.0, "Locked silhouette holds a deeper compression")
	actor.state = &"execute"
	actor.state_time = 0.1
	actor.velocity = Vector2.ZERO
	actor.set_meta("enemy_skill_motion", true)
	visual.advance(0.016)
	_check(visual.body_offset.x > 3.0 and visual.body_rotation > 0.0, "Execution releases forward even when skill movement has zero velocity")
	var stride: float = visual.stride_phase
	actor.position += Vector2(10,0)
	actor.state_time = 0.0
	visual.advance(0.1)
	_check(visual.body_offset.x > 3.0 and is_equal_approx(stride,visual.stride_phase), "Held skill motion retains release without running footsteps")
	actor.remove_meta("enemy_skill_motion")
	actor.state = &"recovery"
	actor.state_time = 0.8
	visual.advance(0.016)
	var initial: float = visual.body_offset.length()
	actor.state_time = 0.1
	visual.advance(0.016)
	_check(visual.body_offset.length() < initial * 0.1, "Recovery returns the silhouette towards its foot anchor")
	_check(actor.state == &"recovery" and actor.state_time == 0.1, "Visual advancement never alters AI phase or its remaining time")
	actor.aim_direction = Vector2.LEFT
	visual.advance(0.016)
	_check(visual.facing < 0.0 and visual.scale.x < 0.0, "Body orientation follows the actor's aim")
	actor.free()

func _test_recoil_and_pause() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	actor.state = &"idle"
	visual.advance(0.016)
	visual.receive_impact(Vector2.RIGHT, 1.0, false)
	var light_offset: float = visual.body_offset.x
	_check(light_offset > 3.0 and visual.body_scale.x < 0.94 and visual.body_scale.y > 1.0 and visual.flash_strength > 0.5 and visual.flash_strength <= 0.60, "Horizontal hammer contact compresses along its force and preserves body detail under the flash")
	_check(actor.material == null and visual.material is ShaderMaterial, "Flash material is isolated from the actor's telegraphs and health bar")
	_check(is_equal_approx(float(visual.material.get_shader_parameter("impact_mix")), visual.flash_strength), "The body shader receives the current flash amount")
	visual.receive_impact(Vector2.LEFT, 1.0, true)
	_check(visual.body_offset.x < -light_offset, "Heavy impact has a stronger recoil in the incoming direction")
	actor.aim_direction = Vector2.LEFT
	visual.advance(0.016)
	_check(visual.facing > 0.0, "Recoil holds the current body orientation while AI aim changes")
	var before: Transform2D = visual.transform
	var flash: float = visual.flash_strength
	var clock: float = visual.get("_clock")
	visual.advance(0.0)
	_check(visual.transform == before and visual.flash_strength == flash, "Zero delta freezes recoil and flash")
	paused = true
	visual.advance(0.5)
	visual.receive_impact(Vector2.DOWN, 1.5, true)
	_check(visual.transform == before and visual.flash_strength == flash and visual.get("_clock") == clock, "Paused advance and impacts leave the visual state frozen")
	paused = false
	for i in 25:
		visual.advance(0.016)
	_check(is_zero_approx(visual.flash_strength) and visual.body_offset.length() < 0.001 and absf(visual.body_rotation) < 0.001, "Recoil and flash completely settle without lingering drift")
	for i in 20:
		visual.receive_impact(Vector2.RIGHT, 100.0, true)
	_check(visual.body_offset.length() <= 12.0 and absf(visual.body_rotation) <= 0.16, "Rapid repeated heavy hits have bounded displacement and rotation")
	visual.reduced_fx_override = 1
	# Assess a fresh light contact after the protected heavy reaction has settled.
	for _step in 3:
		visual.advance(0.10)
	visual.receive_impact(Vector2.RIGHT, 1.0, false)
	_check(is_zero_approx(visual.flash_strength) and visual.body_offset.x > 0.0 and visual.body_offset.x < light_offset * 0.5, "Reduced effects disables the flash and limits motion while preserving a readable response")
	actor.free()

func _test_archetypes() -> void:
	var signatures: Array[Vector3] = []
	for role: String in ["skirmisher", "tank", "assassin", "caster", "support"]:
		var fixture: Array = _fixture(role)
		var actor: ActorStub = fixture[0]
		var visual: Visual = fixture[1]
		for i in 10:
			actor.position += Vector2(1.6,0)
			visual.advance(0.016)
		var signature := Vector3(visual.stride_phase, visual.body_offset.y, visual.body_rotation)
		_check(not signatures.has(signature), "%s has a distinct stride and body weighting" % role)
		signatures.append(signature)
		for next_phase: StringName in [&"idle", &"telegraph", &"locked", &"execute", &"recovery"]:
			actor.state = next_phase
			actor.state_time = 0.5
			for progress: float in [0.0, 0.5, 1.0]:
				actor.brain.progress = progress
				visual.advance(0.016)
				_check(visual.body_offset.is_finite() and visual.body_scale.is_finite() and visual.body_scale.x > 0.0 and visual.body_scale.y > 0.0 and visual.body_offset.length() <= 12.0, "%s / %s has finite bounded presentation" % [role,next_phase])
		actor.free()

func _test_manifest_and_anchors() -> void:
	var manifest: Dictionary = {"body_height":100,"cycle_distance":40,"frames":[
		{"index":0,"region":[0,0,80,120],"foot":[40,110]},
		{"index":1,"region":[80,0,100,120],"foot":[130,110]},
		{"index":2,"region":[180,0,80,120],"foot":[215,110]},
		{"index":3,"region":[260,0,80,120],"foot":[290,110]}],
		"clips":{"walk":[0,1],"windup":[0,1],"release":[2],"recovery":[1],"hurt":[3]}}
	var bank: Dictionary = Visual.parse_motion_manifest(manifest, Vector2(340,120))
	_check(bank.clips.walk.size() == 2 and bank.clips.telegraph.size() == 2 and bank.clips.locked[0].name == "1", "Explicit numeric clips resolve and locked holds the final windup frame")
	_check(bank.clips.execute[0].name == "2" and bank.clips.recoil[0].name == "3", "Release and hurt aliases resolve to skill and impact phases")
	var broken: Dictionary = manifest.duplicate(true)
	broken.frames = [{"index":0,"region":[330,0,80,120],"foot":[350,100]}]
	_check(Visual.parse_motion_manifest(broken, Vector2(340,120)).is_empty(), "Out-of-atlas regions are rejected")
	broken.frames = [{"index":0,"region":[0,0,80,120]}]
	_check(Visual.parse_motion_manifest(broken, Vector2(340,120)).is_empty(), "Frames without an authored foot anchor are rejected")
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	bank.texture = GradientTexture2D.new()
	visual.set("_bank", bank)
	actor.position = Vector2(12,0)
	visual.advance(0.1)
	_check(is_equal_approx(visual.stride_phase, TAU * 12.0 / 40.0) and visual.asset_mode == "authored_frames", "An authored cycle uses actual distance and opts into genuine frames")
	var frame: Dictionary = visual.body_frame()
	var authored: Dictionary = visual.selected_frame
	var foot_in_source: Vector2 = authored.foot - authored.region.position
	var local_foot: Vector2 = frame.bounds.position + foot_in_source * actor.body_bounds.size.y / float(bank.body_height)
	_check(local_foot.length() < 0.0001, "Asymmetric source frames keep the authored foot at the local pivot")
	for i in 10:
		visual.advance(0.016)
	_check(visual.asset_mode == "authored_frames" and visual.selected_frame.name == "0", "Stopping keeps the authored contact pose instead of swapping to the old portrait")
	actor.state = &"execute"
	actor.state_time = 0.1
	visual.advance(0.016)
	_check(visual.selected_frame.name == "2", "Execute selects the actual release frame")
	visual.receive_impact(Vector2.RIGHT)
	_check(visual.selected_frame.name == "3", "Impact overlays skills with the authored hurt frame")
	actor.free()

func _test_production_manifest() -> void:
	var path: String = "asset://enemies/M01_motion_v1.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(path)):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	_check(raw is Dictionary, "M01 production metadata is valid JSON")
	if not raw is Dictionary:
		return
	var dimensions: Array = raw.get("image_size", [])
	_check(dimensions.size() == 2, "M01 production metadata states its image dimensions")
	if dimensions.size() != 2:
		return
	var bank: Dictionary = Visual.parse_motion_manifest(raw, Vector2(float(dimensions[0]), float(dimensions[1])))
	_check(not bank.is_empty(), "M01 production regions and foot anchors are accepted by the actual parser")
	if bank.is_empty():
		return
	for clip: String in ["walk", "telegraph", "locked", "execute", "recovery", "recoil"]:
		_check(bank.clips.has(clip) and not bank.clips[clip].is_empty(), "M01 production %s clip is available" % clip)
	_check(bank.clips.walk.size() == 8 and bank.clips.recoil.size() == 4, "M01 retains all eight walk poses and all four authored recoil poses")

func _test_empty_m35() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	actor.enemy_id = "M35"
	actor.body_texture = GradientTexture2D.new()
	actor.empty_body_texture = GradientTexture2D.new()
	var room := RoomStub.new()
	root.add_child(room)
	actor.room = room
	var before: Dictionary = visual.body_frame()
	_check(before.texture == actor.empty_body_texture, "M35 starts with its existing empty-body resource while not carrying")
	room.enemy_props.carrying = true
	var carried: Dictionary = visual.body_frame()
	_check(carried.texture == actor.body_texture and carried.bounds == before.bounds and carried.region == before.region, "M35 pickup only switches the authoritative texture; bounds and foot stay stable")
	actor.free()
	room.free()
