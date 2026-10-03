extends "res://scripts/levels/b09/world/preview.gd"
## Real GPU frames and mapped input through the candidate's ordinary startup.
## Durable targets, refilled resources, invulnerability, phase placement and
## finite-wave clearing are explicit fixtures, not a natural playthrough.
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
const OUTPUT := "res://artifacts/b09_2k"
var checks := 0
var failures := 0
var observations: Array[Dictionary] = []
var skill_events: Array[Dictionary] = []
var mouse_at := Vector2.ZERO
var frame_samples: Array[float] = []
var sampling := false
var last_frame_usec := 0
var stage: SubViewport
var _lamp_probe := false
var _lamp_samples: Array[Dictionary] = []
var _lamp_pending_before := false

func _lamp_state(label: String) -> Dictionary:
	var lamp: Dictionary=room.b09_mechanics.lamps.values()[0]
	var pending: Dictionary=room.b09_mechanics._pending
	return {"label":label,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"controls":room.controls_enabled(),"input_blocked":room.input_blocked,"release_gate":room.release_gate,"pressed":Input.is_action_pressed("interact"),"just_pressed":Input.is_action_just_pressed("interact"),"paused":get_tree().paused,"window_focus":get_window().has_focus(),"distance":room.player.position.distance_to(lamp.at),"los":room.has_line_of_sight(room.player.position,lamp.at),"hp":Game.run.hp,"player_hits":room.telemetry.player_hits,"clock":room.b09_mechanics.clock,"ready":lamp.ready,"warm_until":lamp.warm_until,"pending":{} if pending.is_empty() else {"id":pending.id,"remaining":pending.remaining,"hit_serial":pending.hit_serial}}

func _physics_process(_delta: float) -> void:
	if not _lamp_probe: return
	var has_pending: bool=not room.b09_mechanics._pending.is_empty()
	if _lamp_samples.size()<8 or Input.is_action_just_pressed("interact") or has_pending!=_lamp_pending_before:
		_lamp_samples.append(_lamp_state("physics_before_room"))
	_lamp_pending_before=has_pending

func _ready() -> void:
	super._ready()
	_run_checks.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("B09_2K: "+label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func aim(at: Vector2) -> void:
	mouse_at=room.get_canvas_transform()*at
	var motion := InputEventMouseMotion.new()
	motion.position=mouse_at
	motion.global_position=mouse_at
	# Official local Viewport coordinates; does not move the native OS cursor.
	get_viewport().push_input(motion,true)

func mapped_input(action: String, pressed: bool) -> void:
	var event: InputEvent=InputMap.action_get_events(action)[0].duplicate()
	if event is InputEventMouseButton:
		event.position=mouse_at
		event.global_position=mouse_at
		event.pressed=pressed
	elif event is InputEventKey:
		event.pressed=pressed
		event.echo=false
	Input.parse_input_event(event)

func release_all() -> void:
	for action: String in ["move_left","move_right","move_up","move_down","click_move","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		mapped_input(action,false)

func tap(action: String) -> void:
	mapped_input(action,true)
	await frames(1)
	mapped_input(action,false)

func click_control(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	get_viewport().push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.position=point
		event.global_position=point
		event.pressed=pressed
		get_viewport().push_input(event,true)
		await frames(1)

func capture(label: String) -> void:
	var previous := sampling
	sampling=false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),label+" actual GPU framebuffer is 2560x1440")
	check(image.save_png(OUTPUT.path_join(label+".png"))==OK,label+" capture saved")
	observations.append({"capture":label,"pixels":[image.get_width(),image.get_height()],"room":room.layout_id if is_instance_valid(room) else "menu"})
	sampling=previous
	last_frame_usec=Time.get_ticks_usec()

func _process(delta: float) -> void:
	super._process(delta)
	var now := Time.get_ticks_usec()
	if sampling and last_frame_usec>0:
		frame_samples.append(float(now-last_frame_usec)/1000.0)
	last_frame_usec=now

func observe_skill(slot: String, reason: String, details: Dictionary) -> void:
	skill_events.append({"slot":slot,"reason":reason,"details":details.duplicate(true)})

func accepted(slot: String) -> bool:
	for event: Dictionary in skill_events:
		if event.slot==slot and event.reason=="accepted": return true
	return false

func _test_hero(index: int) -> void:
	heroes.select(index)
	difficulties.select(4)
	_start()
	check(is_instance_valid(room) and route!=null,"ordinary preview startup for hero "+str(index))
	if not is_instance_valid(room): return
	await frames(8)
	var hero: String=Game.run.hero_id
	check(room.controls_enabled() and not room.player.click_navigation.is_active(),hero+" startup releases controls")
	var hud_inside := true
	for bounds: Rect2 in hud.coverage_rects(): hud_inside=hud_inside and get_viewport().get_visible_rect().encloses(bounds)
	check(hud_inside,hero+" shared HUD instruments inside logical viewport")
	check(hud.health_bar.value==Game.run.hp and hud.health_bar.max_value==Game.run.max_hp and hud.resource_bar.value==Game.run.resource,hero+" shared meters read actual candidate values")
	check(hud.skill_slots.size()==5 and hud.skill_slots[0].key=="Q" and hud.skill_slots[1].key=="W" and hud.skill_slots[2].key=="E" and hud.skill_slots[3].key=="R",hero+" shared HUD exposes the real four abilities and dodge")
	check(not hud.gold_label.visible and not hud.room_identity_plate.visible and hud.expedition_label.text=="B09 · D4 · 1/7",hero+" candidate HUD reports actual route without formal rewards or an invented map")
	check(get_viewport().get_visible_rect().encloses(restart.get_global_rect()),hero+" return button inside logical viewport")
	room.player.invulnerable=180.0
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position=Content.point([500,900])
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frames(3)
	var initial: Vector2=room.player.position
	mapped_input("move_right",true)
	await frames(8)
	mapped_input("move_right",false)
	check(room.player.position.x>initial.x+15.0 and room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),hero+" mapped arrow drives actual physics")
	var destination: Vector2=room.player.position+Vector2(90,60)
	aim(destination)
	check(room.player.get_global_mouse_position().distance_to(destination)<0.01,hero+" local pointer maps through active 2K camera")
	await tap("click_move")
	check(room.player.click_navigation.is_active(),hero+" mapped right mouse builds production path")
	await frames(45)
	check(room.player.position.distance_to(destination)<8.0,hero+" right mouse reaches legal destination")
	initial=room.player.position
	aim(initial+Vector2(150,0))
	var dashes: int=room.telemetry.dashes
	await tap("dash")
	await frames(20)
	check(room.telemetry.dashes==dashes+1 and room.player.position.distance_to(initial)>40.0,hero+" mapped space commits real dash")
	room.player.position=Content.point([650,900])
	var target: Node2D=room.spawn_enemy(room.player.position+Vector2(80,0),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,4),"reward_enabled":false})
	target.health.reset(1000000.0)
	target.training_ai_disabled=true
	target.state=&"chase"
	room.player.skill_input_feedback.connect(observe_skill)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frames(5)
	aim(target.position)
	var before: float=target.health.current
	var shots: int=room.telemetry.shots
	mapped_input("attack",true)
	await frames(45)
	mapped_input("attack",false)
	check(room.telemetry.shots>shots and target.health.current<before,hero+" mapped left mouse resolves actual primary damage")
	check(int(target.get_meta("b09_layers",3))<3,hero+" actual primary damage breaks crystal plate")
	await frames(40)
	for slot: String in ["q","secondary","f","ultimate"]:
		# Each cast is independent. Refills and repositioning are fixtures.
		room.player.cancel_actions()
		room.player.position=Content.point([650,900])
		target.position=room.player.position+Vector2(80,0)
		Game.run.resource=float(Game.run.stats.resource_max)
		room.player.cooldowns[slot]=0.0
		skill_events.clear()
		aim(target.position)
		await tap("skill_"+slot)
		await frames(5)
		check(accepted(slot),hero+" mapped "+slot+" receives accepted cast feedback")
		check(float(room.player.cooldowns[slot])>0.0,hero+" "+slot+" owns real cooldown")
		await capture(hero.to_lower()+"_"+slot)
		await frames(110)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.enemy_skills.reset_room()
	room.player.cancel_actions()
	var lamp_id: String=room.b09_mechanics.lamps.keys()[0]
	var lamp: Dictionary=room.b09_mechanics.lamps[lamp_id]
	room.player.position=lamp.at
	await frames(2)
	check(room.nearby_interaction().get("kind","")=="objective",hero+" actual F lamp selection")
	_lamp_samples.clear()
	_lamp_pending_before=not room.b09_mechanics._pending.is_empty()
	_lamp_samples.append(_lamp_state("before_tap"))
	_lamp_probe=true
	await tap("interact")
	_lamp_samples.append(_lamp_state("after_tap"))
	check(not room.b09_mechanics._pending.is_empty(),hero+" mapped F starts 0.6s lamp channel")
	await frames(42)
	_lamp_samples.append(_lamp_state("after_channel"))
	_lamp_probe=false
	print("B09_F_DIAG ",hero," ",JSON.stringify(_lamp_samples))
	check(float(lamp.warm_until)>room.b09_mechanics.clock and float(lamp.ready)>room.b09_mechanics.clock,hero+" automatic clock completes lamp and cooldown")
	await capture(hero.to_lower()+"_lamp")
	var open_button: Button=room.find_child("B09EquipmentOpen",true,false)
	await click_control(open_button)
	await frames(3)
	check(inventory.panel.visible and room.input_blocked,hero+" actual UI click opens equipment and blocks combat")
	check(get_viewport().get_visible_rect().encloses(inventory.panel.get_global_rect()),hero+" equipment panel fits 2K logical viewport")
	for control: Node in inventory.panel.find_children("*","Button",true,false):
		if str(control.text)=="领取19件测试装备": await click_control(control); break
	check(inventory.last_error.is_empty(),hero+" real candidate test catalogue: "+inventory.last_error)
	var catalog_count := 0
	for id: String in inventory.ids:
		if id.begins_with("b09_catalog:"+hero+":"): catalog_count+=1
	check(catalog_count==19 and inventory.list.item_count>=19,hero+" all 19 legal catalogue instances are listed")
	await capture(hero.to_lower()+"_equipment")
	room.player.cancel_actions()
	var set_id: String=["B09-SW","B09-SG","B09-SM"][index]
	for suffix: String in ["head","chest","hands","legs","feet","ring","accessory","weapon"]:
		check(inventory.equip("b09_catalog:"+hero+":"+set_id+"-"+suffix),hero+" equips real instance "+suffix+": "+inventory.last_error)
	check(Game.run.loadout_snapshot.size()==8,hero+" actual eight-slot class loadout")
	inventory._refresh()
	await frames(3)
	await capture(hero.to_lower()+"_equipped")
	inventory._close()
	await frames(3)
	check(room.controls_enabled(),hero+" closing equipment returns input")
	target=room.spawn_enemy(room.player.position+Vector2(160 if hero=="CH01" else 80,0),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,4),"reward_enabled":false})
	target.health.reset(1000000.0)
	target.training_ai_disabled=true
	target.state=&"chase"
	Game.run.resource=float(Game.run.stats.resource_max)
	room.player.cooldowns.q=0.0
	skill_events.clear()
	aim(target.position)
	before=target.health.current
	await tap("skill_q")
	await frames(90)
	check(accepted("q") and target.health.current<before,hero+" equipped class set casts Q and resolves real damage: "+JSON.stringify(skill_events)+" HP "+str(before)+" -> "+str(target.health.current))
	await capture(hero.to_lower()+"_equipped_combat")
	observations.append({"hero":hero,"input":"mapped arrows/right mouse/left mouse/Q/W/E/R/space/F, local viewport equipment button clicks","shots":room.telemetry.shots,"dashes":room.telemetry.dashes,"lamp":"real clock","loadout":Game.run.loadout_snapshot.duplicate(true)})
	release_all()
	await room.combat_audio.wait_for_cleanup()
	_restart()
	await frames(2)

func _clear_fixture() -> void:
	# Explicit bounded-wave fixture; room and F traversal still run normally.
	if room.layout_id=="BO09":
		room._boss_actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true"})
		await frames(2)
	else:
		for zone in room.encounter_zones.size():
			room.player.position=room.encounter_zones[zone].center
			for step in 5:
				room._update_encounters(4.0)
				for enemy: Node in room.enemies.get_children(): enemy.free()
		await frames(3)
	room.enemy_skills.reset_room()
	for projectile: Node in room.projectiles.get_children(): projectile.free()
	check(room.objective_complete and room._living_enemy_count()==0,"finite clear fixture "+room.layout_id)

func _test_queen() -> void:
	var queen: Node2D=room._boss_actor
	queen.health.current=queen.health.maximum*0.3
	queen.position=Content.point([1400,900])
	room.player.position=queen.position+Vector2(250,0)
	room.player.invulnerable=180.0
	await frames(60)
	check(queen.brain.phase==3 and "mirror_verdict" in queen.brain.available_actions(),"Queen actual D4 / 35% phase admits mirror")
	room.enemy_skills.cancel_owner(queen)
	queen.brain._begin_action(queen,room.player,"prism_ray")
	check(queen.brain.state==&"telegraph" and queen.brain.command.get("action_id","")=="prism_ray","Queen actual prism warning")
	var command: Dictionary=queen.brain.command.duplicate(true)
	await capture("bo09_prism_warning")
	mapped_input("move_down",true)
	await frames(10)
	mapped_input("move_down",false)
	check(queen.brain.command.target==command.target and queen.brain.command.direction==command.direction,"Queen telegraph freezes target across real player movement")
	var released := false
	for step in 100:
		await frames(1)
		if not room.enemy_skills.projectiles.is_empty():
			released=true
			check(int(room.enemy_skills.projectiles[0].damage)==int(Skills.freeze(command,queen.profile).damage),"Queen real projectile uses warned frozen damage")
			await capture("bo09_prism_projectile")
			break
	check(released,"Queen real frames release visible projectile")
	room.enemy_skills.cancel_owner(queen)
	queen.brain._begin_action(queen,room.player,"mirror_verdict")
	check(queen.brain.command.get("action_id","")=="mirror_verdict" and queen.brain.command.followups.size()==2,"Queen D4 actual three-stage mirror warning")
	await capture("bo09_mirror_warning")
	var followups := false
	for step in 100:
		await frames(1)
		if room.enemy_skills.jobs.size()>=2:
			followups=true
			await capture("bo09_mirror_execute")
			break
	check(followups,"Queen real frames schedule two finite mirror followups")
	sampling=true
	last_frame_usec=Time.get_ticks_usec()
	await frames(180)
	sampling=false
	check(room.enemy_skills.active_effect_count()<=room.enemy_skills.MAX_EFFECTS,"Queen effects remain inside runtime cap")

func _test_rooms() -> void:
	heroes.select(1)
	difficulties.select(4)
	_start()
	await frames(8)
	room.player.invulnerable=180.0
	var profile_before := Game.profile.duplicate(true)
	for index in 7:
		check(route.node_index==index and room.layout_id==Content.room_ids()[index],"ordered live room "+str(index))
		var focus := Node2D.new()
		focus.position=room.ARENA.get_center()
		room.add_child(focus)
		room.camera.target=focus
		room.camera.follow_target()
		room.camera.force_update_scroll()
		if room.layout_id!="BO09": room.player.position=room.encounter_zones[0].center
		await frames(20)
		check(room._living_enemy_count()>0,"live authored roster rendered in "+room.layout_id)
		await capture(room.layout_id.to_lower()+"_live")
		if room.layout_id=="BO09": await _test_queen()
		await _clear_fixture()
		room.player.position=room.exit_position
		await frames(2)
		check(room.nearby_interaction().get("kind","")=="b09_candidate_next","real exit selected "+room.layout_id)
		await tap("interact")
		await frames(3)
		check(route.finished if index==6 else route.node_index==index+1,"mapped F advances once from "+str(index)+" error="+route.last_error+" inventory="+inventory.last_error)
		if route.node_index!=index+1 and not route.finished: break
		room.camera.target=room.player
	for key: String in ["permanent_gold","hero_xp","materials","bosses","branches","research_xp","progression_receipts"]:
		check(Game.profile.get(key)==profile_before.get(key),"isolated gear reward preserves formal "+key)
	check(route.finished and room.input_blocked,"final completion blocks further combat input")
	await capture("completed")

func _run_checks() -> void:
	if DisplayServer.get_name()=="headless" or not Rules.b09_candidate_enabled():
		push_error("B09_2K requires a graphical renderer and explicit isolated B09 flags")
		get_tree().quit(2)
		return
	get_tree().create_timer(180.0).timeout.connect(func(): push_error("B09_2K timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	# A standalone viewport uses Godot's documented local pointer cache. Native
	# Window mouse queries use the OS cursor even after synthetic pointer input.
	stage=SubViewport.new()
	stage.name="B09LocalInput2K"
	stage.size=Vector2i(2560,1440)
	stage.size_2d_override=Vector2i(1280,720)
	stage.size_2d_override_stretch=true
	stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally=true
	get_tree().root.add_child(stage)
	reparent(stage)
	var presentation := TextureRect.new()
	presentation.texture=stage.get_texture()
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation.mouse_filter=Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(presentation)
	await frames(5)
	check(get_window().size==Vector2i(2560,1440),"actual window is 2560x1440")
	check(get_viewport().get_visible_rect().encloses(menu.get_global_rect()),"menu fits logical viewport at 2K")
	await capture("menu")
	for index in 3: await _test_hero(index)
	await _test_rooms()
	frame_samples.sort()
	var total := 0.0
	for value: float in frame_samples: total+=value
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"window":[get_window().size.x,get_window().size.y],"observations":observations,"frame_intervals_ms":{"count":frame_samples.size(),"mean":total/maxi(1,frame_samples.size()),"p95":frame_samples[int((frame_samples.size()-1)*0.95)] if not frame_samples.is_empty() else 0.0,"max":frame_samples.back() if not frame_samples.is_empty() else 0.0},"method":"Real GPU framebuffer; ordinary B09 preview startup, mapped physical key/mouse event objects via Input.parse_input_event, official Viewport local pointer, automatic player/room/brain/effect physics. Durable targets/resource refills/invulnerability/phase placement/finite-wave clearing are fixtures. Captures are direct framebuffer PNGs; no compositing or offline resizing. OS cursor/device input, natural clearing/balance, long-session performance and monitor visibility are not certified."}
	var file := FileAccess.open(OUTPUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	release_all()
	await room.combat_audio.wait_for_cleanup()
	_restart()
	await frames(2)
	print("B09_2K checks=",checks," failures=",failures," renderer=",report.renderer," frame_intervals_ms=",report.frame_intervals_ms)
	get_tree().quit(1 if failures else 0)
