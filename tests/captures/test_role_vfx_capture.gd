extends "res://tests/combat/test_combat_feedback.gd"
## Narrow graphical acceptance for the role redesign. Inherits the production
## cast, mouse-aim, contact attribution and framebuffer observers. Each sample
## has a fresh isolated run so previous deployments cannot supply its damage.

var current_reduced := false
var selected_sample_keys: PackedStringArray = []
const ROLE_SAMPLES := [
	{"hero":"CH01", "slot":"secondary", "reduced":false},
	{"hero":"CH01", "slot":"ultimate", "reduced":false},
	{"hero":"CH02", "slot":"secondary", "reduced":false},
	{"hero":"CH02", "slot":"f", "reduced":false},
	{"hero":"CH03", "slot":"q", "reduced":false},
	{"hero":"CH03", "slot":"secondary", "reduced":false},
	{"hero":"CH03", "slot":"f", "reduced":false},
	{"hero":"CH03", "slot":"ultimate", "reduced":false},
	{"hero":"CH03", "slot":"ultimate", "reduced":true},
]

func run_checks() -> void:
	if not Game.profile_path.contains("test_role_vfx_capture"):
		push_error("Role VFX capture requires an isolated test_role_vfx_capture profile")
		_finish(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	check(graphical,"role acceptance has an actual graphical framebuffer")
	if not graphical:
		_finish(2)
		return
	DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	stage.add_child(app)
	await frame()
	await frame()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role-samples="):
			selected_sample_keys = argument.trim_prefix("--role-samples=").split(",",false)
	for sample: Dictionary in ROLE_SAMPLES:
		if not selected_sample_keys.is_empty() and not selected_sample_keys.has(str(sample.hero)+":"+str(sample.slot)): continue
		current_hero = str(sample.hero)
		current_reduced = bool(sample.reduced)
		check(Game.new_profile(),current_hero+" fresh isolated role fixture")
		Game.set_setting("language","zh_CN")
		Game.set_setting("reduced_fx",current_reduced)
		check(Game.select_hero(current_hero) and Game.start_run(),current_hero+" production main starts run")
		room = app.room
		room.spawn_enabled = false
		check(Game.grant_hero_xp(3600,"role_visual_"+str(records.size())),current_hero+" level20 through production XP API")
		check(Game.run.level == 20,current_hero+" actual fixture level is 20")
		for enemy in room.enemies.get_children(): enemy.queue_free()
		await frame()
		anchor = _open_stage()
		check(not anchor.is_zero_approx(),current_hero+" verified legal open production ground")
		if anchor.is_zero_approx():
			_finish(1)
			return
		target = room.spawn_enemy(anchor,"M01",1,{"reward_enabled":false})
		check(is_instance_valid(target),current_hero+" actual production target exists")
		await wait_seconds(0.55)
		target.training_ai_disabled = true
		target.health.reset(10000.0)
		target.health.damaged.connect(_on_damage)
		Game.restore_resource(float(Game.run.stats.get("resource_max",100)))
		initial_resource_fills += 1
		await _prepare_action(str(sample.slot))
		await _capture_action(str(sample.slot))
		records[-1]["reduced_fx"] = current_reduced
		if str(sample.slot) == "ultimate" and current_hero == "CH03":
			check(bool(records[-1].telegraph_overlap_captured),"mage domain coexists with an actual enemy warning; reduced_fx="+str(current_reduced))
		aim_tracking = false
		Game.finish_run("abandoned")
		await frame()
		await frame()
	var report := {
		"checks":checks,"failures":failures,"captures":captures,"graphical":graphical,
		"audio":"Master safety muted. Native cue scheduling is observed; this is not a subjective listening assessment.",
		"fixture":"Fresh production main/room/player/enemy per sample. Level20 granted through XP API; starter loadout. Random room spawning disabled, actual ground geometry retained. Durable M01 HP10000, target AI suspended; an ordinary unmodified attacker remains active for each domain-warning overlap. One declared initial resource refill per fresh fixture. Mage W: player180px behind target, crystal cast100px behind target so both real actors leave its silhouette visible. Gunner E: legal ground65px right/40px above target so target stays within130px blast while the grenade silhouette is visible. Native cast timelines, projectiles, damage attribution, movement, cooldowns, hitstop, deployments and feedback run normally. PNGs are actual scene SubViewport framebuffers with no compositing.",
		"clips":records,
	}
	var file := FileAccess.open(AssetCatalog.resolve("res://artifacts/role_vfx_capture.json"),FileAccess.WRITE)
	check(file != null,"role VFX report created")
	if file != null:
		report.checks = checks
		report.failures = failures
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("ROLE_VFX_CAPTURE_RESULT checks=",checks," failures=",failures," clips=",records.size()," captures=",captures)
	_finish(1 if failures else 0)

func _capture_frame(phase: String) -> void:
	_save_frame(phase)
	if phase == "start" and ((current_hero == "CH02" and str(active_record.slot) == "secondary") or (current_hero == "CH03" and str(active_record.slot) == "q")):
		await wait_seconds(float(active_record.spec.windup)+0.04)
		_save_frame("released_projectile")
	if phase == "impact" and ((current_hero == "CH01" and str(active_record.slot) in ["secondary","ultimate"]) or (current_hero in ["CH02","CH03"] and str(active_record.slot) == "f")):
		# Observe the real expansion following contact. Waiting advances the
		# ordinary scene clock; no effect age, damage or pose is fabricated.
		await wait_seconds(0.085)
		_save_frame("impact_expansion")

func _save_frame(phase: String) -> void:
	var filename := "role_vfx_"+current_hero+"_"+str(active_record.slot)+("_reduced" if current_reduced else "_full")+"_"+phase+".png"
	var status: Error = stage.get_texture().get_image().save_png("res://artifacts/"+filename)
	check(status == OK,"actual role framebuffer saved: "+filename)
	if status == OK: captures += 1
	active_record.frames.append({"phase":phase,"file":filename,"t":float(room.elapsed)-float(active_record.start_time),"target_hp":target.health.current,"resource":Game.run.resource,"visual_state":str(room.player.visual_state),"native_impact_events":_feedback_impact_count()-int(active_record.feedback_impacts_before),"enemy_telegraphs":_telegraph_count(),"reduced_fx":current_reduced})

func _prepare_action(slot: String) -> void:
	await super._prepare_action(slot)
	if current_hero == "CH03" and slot == "secondary":
		room.player.position = anchor-Vector2(180,0)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await frame()
		await frame()
		_aim_input()
		await get_tree().physics_frame
		await frame()
		check(room.player.aim_direction.dot((anchor-room.player.position).normalized()) > 0.98,"mage crystal fixture retains production pointer aim")

func _capture_action(slot: String) -> void:
	var target_anchor := anchor
	if current_hero == "CH03" and slot == "secondary": anchor -= Vector2(60,0)
	elif current_hero == "CH02" and slot == "f": anchor += Vector2(65,-40)
	await super._capture_action(slot)
	anchor = target_anchor

func _ultimate_visual_active() -> bool:
	# This probe requires an actual deployed domain. The earlier cast windup is
	# not sufficient evidence that the domain leaves enemy warnings readable.
	if current_hero != "CH03": return super._ultimate_visual_active()
	for node in get_tree().get_nodes_in_group("hero_deployments"):
		if node.room == room and node.kind == "field" and node.is_alive(): return true
	return false
