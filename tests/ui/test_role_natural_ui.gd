extends Node
## Synthetic unlock setup only. The actual new Main/UI configures each four-slot
## set and departs. Native enemies, AI, collision, damage, resources and clocks
## then run without mutation. This is automated play, not a human feel review.
const MainScene = preload("res://scenes/app/main.tscn")
const Catalog = preload("res://scripts/domain/combat/skill_catalog.gd")
const Driver = preload("res://tests/support/role_natural_controller.gd")
const EFFECTS_LOADOUTS := {"CH01":["CH01_SK10","CH01_SK08","CH01_SK12","CH01_SK01"],"CH02":["CH02_SK08","CH02_SK12","CH02_SK01","CH02_SK07"],"CH03":["CH03_SK07","CH03_SK08","CH03_SK12","CH03_SK03"]}
var app: Node
var driver: RefCounted
var failures: Array[String] = []
var checks := 0
var active := false
var elapsed := 0.0
var next_log := 0.0
var row: Dictionary = {}
var rows: Array[Dictionary] = []
var observed_targets: Dictionary = {}
var observed_releases: Dictionary = {}
var release_count := 0
var report_path := ""
var effects_probe := false
var observed_deployments: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	_run.call_deferred()
	get_tree().create_timer(2400.0).timeout.connect(func(): push_error("Natural UI watchdog"); get_tree().quit(2))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("ROLE NATURAL UI: "+label)

func frames(count: int = 3) -> void:
	for index: int in count: await get_tree().process_frame

func click(name_value: String) -> bool:
	var control: Button = app.find_child(name_value,true,false) as Button
	if control == null or control.disabled or not control.is_visible_in_tree(): return false
	control.pressed.emit()
	await frames()
	return true

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory: String = Game.profile_path.get_base_dir()+"/captures"
	DirAccess.make_dir_recursive_absolute(directory)
	var pixels: Image = get_viewport().get_texture().get_image()
	check(pixels.save_png(directory+"/"+name_value+".png") == OK,"actual native graphical battle capture "+name_value)
	print("NATURAL_CAPTURE ",directory+"/"+name_value+".png window=",DisplayServer.window_get_size()," pixels=",pixels.get_size())

func _run() -> void:
	if not Game.profile_path.contains("test_role_natural_ui"): get_tree().quit(2); return
	check(DisplayServer.get_name() != "headless","natural UI review uses the real graphical renderer")
	check(Engine.physics_ticks_per_second == 60 and is_equal_approx(Engine.time_scale,1.0),"native60Hz and native clock")
	check(Game.new_profile(),"isolated fresh profile")
	for group: String in ["SG01","SG02","SG03","SG04","SG05","SG06","SG07","SG08"]:
		check(bool(Game.grant_skill_group(group,"fixture:natural:"+group).ok),"synthetic skill collection setup "+group)
	var setup: Dictionary = Game.profile.duplicate(true)
	setup.settings.auto_attack = false
	setup.settings.camera_shake = false
	check(Game._commit_profile(setup),"fixture settings use validated store; no battle overrides")
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	# Native OS cursors cannot reach the off-screen part of an oversized
	# window. 2K component captures are separate; drive gameplay in a window
	# the real screen can contain, and record that actual size.
	get_window().size = Vector2i(2560,1440) if usable.size.x >= 2560 and usable.size.y >= 1440 else Vector2i(1280,720)
	get_window().position = usable.position+(usable.size-get_window().size)/2
	get_window().content_scale_size = Vector2i(1280,720)
	print("NATURAL_DISPLAY ",JSON.stringify({"screen":str(DisplayServer.screen_get_size()),"usable":str(usable),"window":str(get_window().size),"logical":str(get_window().content_scale_size)}))
	report_path = Game.profile_path.get_base_dir()+"/role_natural_ui.json"
	var chapter_only: bool = Game.profile_path.contains("test_role_natural_ui_chapter")
	effects_probe = Game.profile_path.contains("test_role_natural_ui_effects")
	for hero: String in Catalog.HEROES:
		for group: int in ([0] if chapter_only or effects_probe else [0,1,2]):
			await configure(hero,group)
			await play(hero,group,false)
			if Game.run != null:
				# A bounded inconclusive attempt needs explicit native cleanup; this
				# is recorded as abandonment, never extraction or chapter completion.
				Game.finish_run("abandoned")
				await frames()
			Game.reload_profile()
			check(Game.profile.skill_state[hero].learned.size() == 12,"permanent unlocks retained after actual attempt "+hero+"/"+str(group))
		if not chapter_only and not effects_probe:
			await configure(hero,0)
			await play(hero,0,true)
			if Game.run != null: Game.finish_run("abandoned"); await frames()
			Game.reload_profile()
	var covered := 0
	for attempt: Dictionary in rows:
		if bool(attempt.death_probe): continue
		for identity: String in attempt.coverage:
			if bool(attempt.coverage[identity]): covered += 1
	check(covered == (12 if chapter_only or effects_probe else 36),"all configured skills have actual releases and matching native effects via camp configurations")
	for hero: String in Catalog.HEROES:
		if effects_probe: continue # This targeted probe abandons only after observed effects; no route/boss claim.
		var attempts: Array[Dictionary] = []
		for attempt: Dictionary in rows:
			if str(attempt.hero) == hero: attempts.append(attempt)
		check(attempts.any(func(attempt: Dictionary)->bool: return bool(attempt.boss_seen)),hero+" naturally reaches a native chapter boss")
		check(attempts.any(func(attempt: Dictionary)->bool: return str(attempt.outcome) == "extracted"),hero+" legally extracts through the actual Main dialog")
		if not chapter_only: check(attempts.any(func(attempt: Dictionary)->bool: return bool(attempt.death_probe) and str(attempt.outcome) == "death"),hero+" native enemy damage produces death and settlement")
		check(attempts.any(func(attempt: Dictionary)->bool: return not attempt.restart.is_empty()),hero+" completed native checkpoint is saved and resumed")
	save_report()
	print("ROLE_NATURAL_UI_RESULT ",JSON.stringify({"checks":checks,"covered":covered,"failures":failures,"report":report_path,"method":"automated production inputs; source animations still disabled with old complete bitmap fallback"}))
	app.queue_free()
	await frames()
	get_tree().quit(0 if failures.is_empty() else 1)

func configure(hero: String, group: int) -> void:
	app.show_camp()
	await frames()
	check(await click("Open_heroes"),"opens actual redesigned hero page")
	check(await click("Preview_"+hero),"selects actual hero preview "+hero)
	if str(Game.profile.selected_hero) != hero: check(await click("PrimaryAction"),"commits actual hero selection "+hero)
	check(await click("Tab_skills"),"opens actual skill page")
	var desired: Array[String] = []
	for index: int in 4:
		var identity: String = str(EFFECTS_LOADOUTS[hero][index]) if effects_probe else hero+"_SK%02d" % (group*4+index+1)
		desired.append(identity)
		check(await click("InspectSkill_"+Catalog.INPUT_SLOTS[index]),"chooses draft slot "+Catalog.INPUT_SLOTS[index])
		check(await click("SkillPool_"+identity),"chooses learned skill "+identity)
		var draft: Dictionary = app.find_child("Workshop",true,false).get_meta("dossier_draft_"+hero,{})
		if str(draft.get("loadout",[])[index]) != identity:
			check(await click("ReplaceDraftSkill"),"places skill through real draft UI "+identity)
		else: check(true,"real UI already has requested identity in this slot "+identity)
	var apply: Button = app.find_child("ApplySkillConfig",true,false) as Button
	if apply != null and not apply.disabled:
		check(await click("ApplySkillConfig"),"applies complete four-slot setup through real UI")
	else: check(Game.get_loadout(hero) == desired,"unchanged real UI configuration needs no new commit")
	check(Game.get_loadout(hero) == desired,"camp config exact four stable identities "+str(desired))
	await capture(hero+"-set"+str(group)+"-camp")
	app.show_camp()
	await frames()

func play(hero: String, group: int, death_probe: bool) -> void:
	check(await click("Depart"),"native departure button")
	if app.find_child("ConfirmWishDeparture",true,false) != null: check(await click("ConfirmWishDeparture"),"native wish departure confirmation")
	await frames(5)
	check(Game.run != null and is_instance_valid(app.room) and app.route == "run","native expedition entered "+hero)
	if Game.run == null or not is_instance_valid(app.room): return
	row = {"hero":hero,"set":group,"death_probe":death_probe,"method":"native Main/newUI, production input requests, native60Hz, no HP/damage/resource/cooldown/completion writes","art":"old complete bitmap fallback; new animation family disabled","start_level":Game.run.level,"start_hp":Game.run.hp,"start_resource":Game.run.resource,"loadout":Game.run.skill_loadout_snapshot.duplicate(),"coverage":{},"effects":{},"packets":[],"releases":[],"rooms":[],"samples":[],"outcome":"","boss_seen":false,"enemy_movements":0,"reload_results":[],"restart":{}}
	for identity: String in Game.run.skill_loadout_snapshot:
		row.coverage[identity] = false
		row.effects[identity] = {"release":false,"damage":0.0,"guard":false,"utility":false,"deployment":false,"control":false}
	observed_targets.clear()
	observed_releases.clear()
	observed_deployments.clear()
	row["control_samples"] = []
	row["deployments"] = []
	await dismiss_offers()
	await advance()
	driver = Driver.new()
	driver.configure(app.room)
	driver.coverage = row.coverage
	driver.passive_death = death_probe
	driver.effects_probe = effects_probe
	elapsed = 0.0
	next_log = 0.0
	active = true
	var limit: float = 120.0 if effects_probe else 90.0 if death_probe else 480.0 if Game.profile_path.contains("test_role_natural_ui_chapter") else 240.0 if group == 0 else 120.0
	var last_room: String = ""
	var restart_done := false
	var host_begin: int = Time.get_ticks_msec()
	while active and elapsed < limit and float(Time.get_ticks_msec()-host_begin) < (limit+60.0)*1000.0:
		# Required completion dialogs pause physics. Orchestration must remain
		# alive to operate those UI controls; all battle ticks stay native60Hz.
		await get_tree().process_frame
		if Game.run == null:
			row.outcome = str(Game.last_result.get("outcome","settled"))
			break
		if effects_probe and all_covered():
			row.outcome = "target_effects_observed"
			break
		if app.room.layout_id != last_room:
			last_room = app.room.layout_id
			row.rooms.append({"room":last_room,"phase":str(app.room.expedition_context.get("role","")),"t":elapsed})
			row.boss_seen = bool(row.boss_seen) or str(app.room.expedition_context.get("role","")) == "boss"
		if app.expedition.current_complete():
			active = false
			await dismiss_offers()
			if not death_probe and not restart_done and int(app.expedition.current_index()) > 0:
				var before: Dictionary = app.room.expedition_runtime_snapshot()
				check(Game.save_expedition_checkpoint(before),"actual completed-room checkpoint saves for restart")
				var saved: Dictionary = Game.run.expedition.runtime.duplicate(true)
				var saved_loadout: Array = Game.run.skill_loadout_snapshot.duplicate()
				Game.reload_profile()
				check(Game.run != null,"actual isolated restart restores committed expedition")
				if Game.run != null:
					check(JSON.parse_string(JSON.stringify(Game.run.expedition.runtime)) == JSON.parse_string(JSON.stringify(saved)) and Game.run.skill_loadout_snapshot == saved_loadout,"restart retains entire acknowledged runtime and frozen four slots without free resource or ammunition")
				app._continue_game()
				await frames(5)
				await dismiss_offers()
				row.restart = {"room":app.room.layout_id,"hp":Game.run.hp,"resource":Game.run.resource,"loadout":Game.run.skill_loadout_snapshot.duplicate(),"role_state":app.room.player.export_role_state()}
				restart_done = true
				driver.configure(app.room)
				driver.coverage = row.coverage
			if not death_probe and app.expedition.can_extract() and (group > 0 and all_covered() or str(app.room.expedition_context.get("role","")) == "boss"):
				app.show_extraction()
				await frames()
				var buttons: Array[Node] = app.modals[-1].node.find_children("*","Button",true,false)
				if not buttons.is_empty(): (buttons[0] as Button).pressed.emit()
				await frames(5)
				if Game.run == null: row.outcome = "extracted"; break
			if not await advance(): row.outcome = "route_blocked"; break
			driver.configure(app.room)
			driver.coverage = row.coverage
			driver.passive_death = death_probe
			active = true
		if elapsed >= next_log:
			row.samples.append({"t":elapsed,"room":app.room.layout_id,"hp":Game.run.hp,"resource":Game.run.resource,"kills":app.room.telemetry.kills,"enemies":app.room._living_enemy_count(),"role":app.room.player.class_state_snapshot()})
			print("ROLE_NATURAL_PROGRESS ",JSON.stringify({"hero":hero,"set":group,"death_probe":death_probe,"t":elapsed,"room":app.room.layout_id,"hp":Game.run.hp,"coverage":row.coverage,"kills":app.room.telemetry.kills,"rejections":driver.rejected}))
			await capture(hero+"-set"+str(group)+("-death" if death_probe else "-battle")+"-"+str(int(elapsed)))
			next_log += 30.0
	active = false
	if str(row.outcome).is_empty(): row.outcome = "bounded_inconclusive"
	row.elapsed = elapsed
	row.requests = driver.requested.duplicate(true)
	row.rejections = driver.rejected.duplicate(true)
	row.decisions = driver.decisions.duplicate(true)
	await frames(5)
	await capture(hero+"-set"+str(group)+("-death" if death_probe else "-outcome"))
	rows.append(row.duplicate(true))
	if not death_probe:
		for identity: String in row.coverage: check(bool(row.coverage[identity]),"native actual release and effect observed "+identity)
	print("ROLE_NATURAL_ATTEMPT ",JSON.stringify({"hero":hero,"set":group,"death_probe":death_probe,"outcome":row.outcome,"t":elapsed,"coverage":row.coverage,"boss_seen":row.boss_seen,"restart":row.restart}))
	save_report()

func dismiss_offers() -> void:
	for index: int in 64:
		# Completion and restart can leave mandatory offers queued without an
		# open modal. Open the real production decision page before selecting.
		if app.modals.is_empty():
			app._show_pending_expedition_offer()
			await frames()
		if app.find_child("ConfirmZeroBenefitSkip",true,false) != null:
			await click("ConfirmZeroBenefitSkip")
		elif app.find_child("SkipExpeditionRelic",true,false) != null:
			await click("SkipExpeditionRelic")
		elif app.find_child("FieldKeepCurrent",true,false) != null:
			await click("FieldKeepCurrent")
		else:
			# Any equipment card can be closed without taking or equipping it.
			if not app.modals.is_empty(): app._pop_modal(); await frames()
			else: break

func advance() -> bool:
	if Game.run == null or not app.expedition.current_complete(): return false
	var before_index: int = int(app.expedition.current_index())
	app.show_expedition(true)
	await frames()
	var choices: Array[Node] = app.find_children("Choose_*","Button",true,false)
	for node: Node in choices:
		if not (node as Button).disabled:
			(node as Button).pressed.emit()
			await frames(5)
			await dismiss_offers()
			var success: bool = Game.run != null and int(app.expedition.current_index()) == before_index+1
			if not success: log_route_block(before_index)
			return success
	log_route_block(before_index)
	return false

func log_route_block(before_index: int) -> void:
	var diagnostic: Dictionary = {"previous":before_index,"last_error":Game.last_error,"required_undecided":[],"modals":[]}
	if Game.run != null:
		diagnostic["node_index"] = Game.run.expedition.node_index
		diagnostic["phase"] = Game.run.expedition.phase
		for offer: Dictionary in Game.run.expedition.offers.values():
			if bool(offer.get("required",false)) and str(offer.get("decision","")).is_empty(): diagnostic.required_undecided.append(str(offer.get("offer_id","")))
	for modal: Dictionary in app.modals: diagnostic.modals.append(str(modal.node.name))
	row["route_failure"] = diagnostic
	print("ROLE_NATURAL_ROUTE_BLOCK ",JSON.stringify(diagnostic))

func all_covered() -> bool:
	for value: Variant in row.coverage.values():
		if not bool(value): return false
	return true

func _physics_process(delta: float) -> void:
	if not active or get_tree().paused or Game.run == null or not is_instance_valid(app.room): return
	elapsed += delta
	var room: RoomController = app.room
	for target: Node in room.enemies.get_children():
		if not target is EnemyActor: continue
		var identifier: int = target.get_instance_id()
		if not observed_targets.has(identifier):
			observed_targets[identifier] = target.position
			target.health.damaged.connect(func(amount: float):
				if not is_instance_valid(target): return
				var packet: Dictionary = target.last_damage_context.duplicate(true)
				var identity: String = str(packet.get("skill_id",""))
				if row.effects.has(identity):
					row.effects[identity].damage += minf(amount,float(target.health.maximum))
					row.packets.append({"t":elapsed,"skill_id":identity,"cast_id":int(packet.get("cast_id",-1)),"enemy":target.enemy_id,"amount":amount,"source":str(packet.get("damage_source","")),"depth":int(packet.get("proc_depth",0)),"control":target.visible_status_ids()})
					observe_contact.call_deferred(target, identity, packet, target.position)
			)
		elif Vector2(observed_targets[identifier]).distance_to(target.position) > 10.0:
			row.enemy_movements += 1
			observed_targets[identifier] = target.position
	var player: HeroActor = room.player
	for event: Dictionary in player.abilities.feedback.release_events:
		var key := str(player.get_instance_id())+":"+str(event.serial)+":"+str(event.index)
		if observed_releases.has(key): continue
		observed_releases[key] = true
		var identity: String = str(event.skill_id)
		if row.effects.has(identity):
			row.effects[identity].release = true
			row.releases.append({"t":elapsed,"skill_id":identity,"serial":int(event.serial),"event":int(event.index),"resource":Game.run.resource,"role":player.class_state_snapshot(),"position":[player.position.x,player.position.y]})
			if identity in ["CH01_SK03","CH01_SK06","CH01_SK10","CH03_SK03","CH03_SK06"] and float(Game.run.shield) > 0.0: row.effects[identity].guard = true
			if identity == "CH02_SK06" and player.status.has("damage_reduction"): row.effects[identity].utility = true
			if identity == "CH02_SK10" and int(player.class_state_snapshot().get("enhanced_shots",0)) == 3: row.effects[identity].utility = true
			if identity == "CH03_SK10" and float(player.role_kit.echo_remaining) > 0.0: row.effects[identity].utility = true
	for child: Node in get_tree().get_nodes_in_group("hero_deployments"):
		if child.get("room") != room or child.is_queued_for_deletion(): continue
		var options: Dictionary = child.options if child is HeroDeployment else child.context
		var identity: String = str(options.get("skill_id",""))
		if row.effects.has(identity):
			row.effects[identity].deployment = true
			if not observed_deployments.has(child.get_instance_id()):
				observed_deployments[child.get_instance_id()] = true
				row.deployments.append({"t":elapsed,"skill_id":identity,"kind":str(child.kind),"cast_id":int(options.get("cast_id",-1)),"at":[child.position.x,child.position.y]})
	for identity: String in row.effects:
		var effects: Dictionary = row.effects[identity]
		row.coverage[identity] = bool(effects.release) and (float(effects.damage) > 0.0 or bool(effects.guard) or bool(effects.utility) or bool(effects.deployment))
		if effects_probe:
			if identity == "CH01_SK10": row.coverage[identity] = bool(effects.release) and float(effects.damage) > 0.0
			elif identity in ["CH01_SK08","CH01_SK12","CH03_SK07","CH03_SK08","CH03_SK12"]: row.coverage[identity] = bool(effects.release) and bool(effects.control) and float(effects.damage) > 0.0
			elif identity == "CH02_SK08": row.coverage[identity] = bool(effects.release) and bool(effects.deployment) and bool(effects.control) and float(effects.damage) > 0.0
			elif identity == "CH02_SK12": row.coverage[identity] = bool(effects.release) and bool(effects.deployment) and float(effects.damage) > 0.0
	driver.step(elapsed)
	if room._living_enemy_count() == 0 and room.controls_enabled() and not room.objective_complete:
		var destination: Dictionary = room.navigation_target()
		if destination.has("position"):
			var at: Vector2 = destination.position
			if player.position.distance_to(at) > 65.0: driver.navigate_to_reachable(elapsed,at,45.0,driver.visible_threats())
			else: player.clear_movement_target(); room.interact()

func observe_contact(target: EnemyActor, identity: String, packet: Dictionary, before: Vector2) -> void:
	if not is_instance_valid(target) or not target.is_alive() or not row.effects.has(identity): return
	var pending: Vector2 = target.pending_displacement()
	var chill: Dictionary = target.status.states.get("chill",{})
	var ordinary_remaining: float = float(target._ordinary_slow_remaining)
	var ordinary_multiplier: float = float(target._ordinary_slow_multiplier)
	var control := false
	if identity in ["CH01_SK12","CH03_SK07","CH03_SK12"]: control = float(chill.get("remaining",0)) > 0.0
	if identity == "CH02_SK08": control = ordinary_remaining > 0.0 and ordinary_multiplier == 0.0
	if identity in ["CH01_SK08","CH03_SK08"]:
		for request: Dictionary in driver.requested:
			if int(request.cast_id) == int(packet.get("cast_id",-1)) and str(request.skill_id) == identity:
				var at: Array = request.at if identity == "CH01_SK08" else request.target
				control = pending.dot(Vector2(float(at[0]),float(at[1]))-target.position) > 0.01
				break
	if control:
		row.effects[identity].control = true
		row.control_samples.append({"t":elapsed,"skill_id":identity,"cast_id":int(packet.get("cast_id",-1)),"enemy":target.enemy_id,"at":[before.x,before.y],"pending":[pending.x,pending.y],"chill_remaining":float(chill.get("remaining",0)),"ordinary_remaining":ordinary_remaining,"ordinary_multiplier":ordinary_multiplier})

func save_report() -> void:
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema":"three-role-natural-ui-v1","renderer":DisplayServer.get_name(),"window":str(DisplayServer.window_get_size()),"logical":str(get_viewport().get_visible_rect().size),"attempts":rows,"failures":failures},"\t"))
