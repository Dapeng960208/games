extends "res://tests/test_combat_feedback.gd"
const Atlas = preload("res://scripts/combat/hero_directional_atlas.gd")
var observations: Array[Dictionary] = []
var pending_captures: Array[Dictionary] = []
var damage_log: Array[Dictionary] = []
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
	if not Game.profile_path.contains("test_directional_combat_capture"):
		_finish(2)
		return
	graphical=DisplayServer.get_name()!="headless"
	check(graphical,"direction acceptance has a graphical frame buffer")
	if not graphical:
		_finish(2)
		return
	DisplayServer.window_set_size(Vector2i(2560,1440))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage=SubViewport.new()
	stage.size=Vector2i(2560,1440)
	stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally=true
	add_child(stage)
	var presentation:=TextureRect.new()
	presentation.texture=stage.get_texture()
	presentation.size=Vector2(2560,1440)
	presentation.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	app=load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frame()
	var heroes: Array[String] = ["CH01","CH02","CH03"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--directional-heroes="): heroes.assign(argument.trim_prefix("--directional-heroes=").split(",",false))
	for hero: String in heroes:
		check(Atlas.load_family(hero).size()==8,hero+" complete atlas is active")
		if Atlas.load_family(hero).is_empty(): continue
		check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(),hero+" fresh direction fixture")
		check(Game.grant_hero_xp(3600,"direction_level_"+hero),hero+" level20 via actual progression")
		room=app.room
		room.spawn_enabled=false
		for enemy: Node in room.enemies.get_children(): enemy.queue_free()
		await frame()
		var center:=_open_stage()
		check(not center.is_zero_approx(),hero+" real geometry accepts all-direction test lane")
		if center.is_zero_approx(): continue
		target=room.spawn_enemy(center,"M01",1,{"reward_enabled":false})
		await wait_seconds(.55)
		target.training_ai_disabled=true
		target.health.reset(1000000)
		target.rank="boss"
		target.health.damaged.connect(_direction_damage)
		current_hero=hero
		for index: int in 8:
			var direction:=Vector2.from_angle(index*PI/4.0)
			var key: String=Atlas.DIRECTIONS[index]
			room.player.position=center
			target.position=center+direction*85.0
			anchor=target.position
			room.camera.follow_target()
			room.camera.force_update_scroll()
			aim_tracking=true
			await frame()
			await get_tree().physics_frame
			await frame()
			check(room.player.aim_direction.dot(direction)>.98,hero+key+" actual pointer aim")
			# Explicit independent pose fixtures: resource/CD resets are declared,
			# unlike the separate sixty-second spell-only native-clock test.
			Game.restore_resource(float(Game.run.stats.resource_max))
			room.player.cooldowns={"q":0.0,"secondary":0.0,"f":0.0,"ultimate":0.0}
			room.player.shot_cooldown=0.0
			var before: float=target.health.current
			var damage_start: int=damage_log.size()
			var slot: String="q" if hero=="CH03" else "secondary"
			check(room.player.cast_skill(slot,anchor),hero+key+" public directional spell")
			var seen := {}
			var turned := false
			var started: float=float(room.elapsed)
			while float(room.elapsed)-started<.95:
				await frame()
				var phase: String=room.player.get_meta("hero_visual_pose","")
				if phase in ["windup","release","recovery"] and not seen.has(phase):
					seen[phase]=true
					_observe(hero,key,phase+"_pointer_turned" if phase=="recovery" and turned else phase,direction)
				if phase=="release" and not turned:
					# Turn immediately after the actual rendered release, not after
					# a wall-clock delay that can already be idle on a slow renderer.
					turned=true
					aim_tracking=false
					anchor=center-direction*85.0
					_aim_input()
				if phase=="idle" and not room.player.abilities.busy(): break
			check(seen.has("windup") and seen.has("release") and seen.has("recovery"),hero+key+" actual three phases observed")
			await wait_seconds(.25)
			check(float(target.health.current)<before,hero+key+" real directional skill contact")
			check(_hit_since(damage_start,slot),hero+key+" damage belongs to this skill, not earlier status ticks")
			anchor=target.position
			aim_tracking=true
			await frame()
			await get_tree().physics_frame
			before=target.health.current
			damage_start=damage_log.size()
			check(room.player.fire(direction,target),hero+key+" public directional basic")
			await frame()
			_observe(hero,key,"basic",direction)
			await wait_seconds(.42)
			check(float(target.health.current)<before,hero+key+" real basic contact")
			check(_hit_since(damage_start,"primary"),hero+key+" basic has its own confirmed hit")
			# PNG encoding is synchronous and can exceed a short release window.
			# Save only after both native actions are over; captured pixels stay raw.
			_flush_captures()
		aim_tracking=false
		Game.finish_run("abandoned")
		await frame()
	var file:=FileAccess.open("res://artifacts/directional_combat_capture.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"method":"Native production main/room/player at2560x1440, real geometry and pointer, public skills/basics, committed-direction pointer reversal, real projectile/melee damage. Lv20 fixture by XP API; durable M01 with AI disabled/boss antiknockback. Each independent direction resets resource/cooldowns explicitly. Actual PNG framebuffer captures for S/SE/SW; other directions retain runtime source/anchor evidence. No image compositing; not natural balance certification."},"\t"))
		file.close()
	print("DIRECTIONAL_COMBAT_CAPTURE checks=",checks," failures=",failures," samples=",observations.size())
	_finish(1 if failures else 0)

func _observe(hero: String,key: String,phase: String,direction: Vector2) -> void:
	var player: Node2D=room.player
	var drawn: String=player.get_meta("hero_directional_key","")
	var actual: Vector2=player.get_meta("hero_presentation_direction",Vector2.ZERO)
	check(drawn==key,hero+key+phase+" selects authored direction")
	check(actual.dot(direction)>.98,hero+key+phase+" committed body vector")
	var row: Dictionary={"hero":hero,"key":key,"phase":phase,"actual_phase":str(player.get_meta("hero_visual_pose","")),"elapsed":float(room.elapsed),"drawn":drawn,"source":player.get_meta("hero_visual_source",""),"frame":player.get_meta("hero_visual_frame",-1),"muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO)),"foot":str(player.get_meta("hero_foot_local",Vector2.ZERO))}
	if key in ["S","SE","SW"]:
		var path: String="res://artifacts/directional_"+hero+"_"+key+"_"+phase+"_2k.png"
		pending_captures.append({"image":stage.get_texture().get_image(),"path":path,"label":hero+key+phase})
		row["screenshot"]=path
	observations.append(row)

func _flush_captures() -> void:
	for capture: Dictionary in pending_captures:
		check(capture.image.save_png(capture.path)==OK,str(capture.label)+" raw framebuffer saved")
	pending_captures.clear()

func _direction_damage(amount: float) -> void:
	damage_log.append({"amount":amount,"source":str(target.last_damage_context.get("damage_source","")),"slot":str(target.last_damage_context.get("skill_slot",""))})

func _hit_since(start: int, slot: String) -> bool:
	for index: int in range(start,damage_log.size()):
		var hit: Dictionary=damage_log[index]
		if (slot=="primary" and hit.source=="primary") or (slot!="primary" and hit.source=="skill" and hit.slot==slot): return true
	return false
