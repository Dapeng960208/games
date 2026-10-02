extends "res://tests/test_combat_feedback.gd"
## Native 60-second spell-only probe. Normal physics, public cast requests,
## actual pointer, collision, mana and cooldowns; no mid-run resource refills.
var issued: Array[Dictionary] = []
var damages: Array[Dictionary] = []
var minimum_mana := 0.0
var spell_start := 0.0
var closing := false

func _finish(code: int) -> void:
	if closing: return
	closing=true
	aim_tracking=false
	Input.action_release("attack")
	if is_instance_valid(room) and is_instance_valid(room.combat_audio):
		room.combat_audio.stop_all()
		await room.combat_audio.wait_for_cleanup()
	if is_instance_valid(app): app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.run=null
	super._finish(code)

func _open_stage() -> Vector2:
	return preload("res://tests/hero_capture_ground.gd").find_lane(room)

func run_checks() -> void:
	if not Game.profile_path.contains("test_mage_spell_only_capture"):
		_finish(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	var lane_probe: bool = "--lane-probe" in OS.get_cmdline_user_args()
	if not lane_probe: check(graphical,"native graphical frame buffer")
	if not graphical and not lane_probe:
		_finish(2)
		return
	DisplayServer.window_set_size(Vector2i(2560,1440))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.size = Vector2i(2560,1440)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(2560,1440)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	app = load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frame()
	check(Game.new_profile() and Game.select_hero("CH03") and Game.start_run(),"fresh isolated native mage run")
	check(Game.grant_hero_xp(3600,"mage_spell_only_level"),"skills unlocked through production XP")
	Game.set_setting("auto_attack",false)
	room=app.room
	room.spawn_enabled=false
	for enemy: Node in room.enemies.get_children(): enemy.queue_free()
	await frame()
	anchor=_open_stage()
	check(not anchor.is_zero_approx(),"real legal open training lane")
	if lane_probe:
		print("ROLE_LANE_PROBE arena=",room.ARENA," anchor=",anchor)
		_finish(1 if anchor.is_zero_approx() else 0)
		return
	if anchor.is_zero_approx():
		_finish(1)
		return
	target=room.spawn_enemy(anchor,"M01",1,{"reward_enabled":false})
	await wait_seconds(.55)
	target.training_ai_disabled=true
	target.rank="boss"
	target.health.reset(1000000)
	target.health.damaged.connect(observe_spell_damage)
	room.player.position=anchor-Vector2(110,0)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	current_hero="CH03"
	aim_tracking=true
	await frame()
	await frame()
	# One declared fixture start fill; no refill after the measured segment starts.
	Game.restore_resource(float(Game.run.stats.resource_max))
	initial_resource_fills=1
	minimum_mana=Game.run.resource
	spell_start=float(room.elapsed)
	var due := {"secondary":0.0,"f":.6,"ultimate":6.0}
	var cadence := {"secondary":15.0,"f":17.0,"ultimate":34.0}
	var saved := {}
	while float(room.elapsed)-spell_start<60.0 and Game.run.hp>0:
		var now: float=float(room.elapsed)-spell_start
		minimum_mana=minf(minimum_mana,float(Game.run.resource))
		if not room.player.abilities.busy():
			var selected := ""
			for slot: String in ["ultimate","f","secondary"]:
				if now>=float(due[slot]) and room.player.cooldowns[slot]<=0.00001 and room.player.abilities.can_cast(slot,target.position):
					selected=slot
					break
			if selected.is_empty() and room.player.cooldowns.q<=0.00001: selected="q"
			if not selected.is_empty():
				var before: float=Game.run.resource
				if room.player.cast_skill(selected,target.position):
					issued.append({"slot":selected,"t":now,"mana_before":before,"mana_after":Game.run.resource})
					if due.has(selected): due[selected]=now+float(cadence[selected])
					if not saved.has(selected):
						saved[selected]=true
						await wait_seconds(.20 if selected in ["secondary","f"] else .40)
						await frame()
						var name := "res://artifacts/mage_spell_only_"+selected+"_2k.png"
						check(stage.get_texture().get_image().save_png(name)==OK,"native "+selected+" capture saved")
		await frame()
	var counts := {}
	for event: Dictionary in issued: counts[event.slot]=int(counts.get(event.slot,0))+1
	check(room.player.get_node("HeroFeedback").basic_events==0,"60 seconds zero basic attacks")
	check(initial_resource_fills==1,"no mid-segment resource refill")
	check(int(counts.get("q",0))>=22,"at least22 real Q casts in60seconds")
	check(int(counts.get("secondary",0))>=3 and int(counts.get("f",0))>=3 and int(counts.get("ultimate",0))>=2,"W/E/R remain usable in spell-only segment")
	check(damages.size()>25 and target.health.current<1000000,"native spells actually connect")
	check(Game.run.resource>=0 and Game.run.resource<=Game.run.stats.resource_max,"resource bounds maintained")
	await frame()
	check(stage.get_texture().get_image().save_png("res://artifacts/mage_spell_only_end_2k.png")==OK,"end state captured")
	var report := {"method":"Actual production main/room/player/HUD at 2560x1440, native60second clocks, original geometry. Level20 granted via XP, starter equipment retained. One durable M01 with AI disabled and boss anti-knockback rank. Public cast requests, real pointer, projectiles, damage and resource clocks. One initial fill before measurement; no later refills, basics, cooldown resets or fabricated hits. Controlled training acceptance, not natural balance certification.","checks":checks,"failures":failures,"seconds":float(room.elapsed)-spell_start,"counts":counts,"minimum_mana":minimum_mana,"end_mana":Game.run.resource,"casts":issued,"damage":damages}
	var file:=FileAccess.open("res://artifacts/mage_spell_only_capture.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MAGE_SPELL_ONLY_CAPTURE checks=",checks," failures=",failures," counts=",counts," minimum_mana=",minimum_mana)
	_finish(1 if failures else 0)

func observe_spell_damage(amount: float) -> void:
	damages.append({"t":float(room.elapsed)-spell_start,"amount":amount,"source":str(target.last_damage_context.get("damage_source","")),"slot":str(target.last_damage_context.get("skill_slot",""))})
