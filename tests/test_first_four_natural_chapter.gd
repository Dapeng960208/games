extends Node
## Naked negative control. Inputs and observers only; no damage or actor overrides.
const RoomScene = preload("res://scenes/room.tscn")
const ObservedRoom = preload("res://tests/support/b05_balance_observed_room.gd")
const Driver = preload("res://tests/support/first_four_natural_controller.gd")
const CritPolicy = preload("res://scripts/combat/crit_policy.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Economy = preload("res://scripts/core/instance_economy.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Progression = preload("res://scripts/core/hero_progression.gd")
const NativeProfile = preload("res://scripts/core/numerical_profile.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Expedition = preload("res://scripts/world/expedition_controller.gd")
const Trail = preload("res://tests/support/b05_guard_damage_trail.gd")
var room: MineRoom
var stage: SubViewport
var driver: RefCounted
var trail: RefCounted
var expedition: RefCounted
var current_run: RunState
var report: Dictionary = {}
var room_rows: Array[Dictionary] = []
var current_row: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var active := false
var elapsed := 0.0
var room_started := 0.0
var next_objective := 0.0
var next_sample := 0.0
var outgoing_start := 0
var ability_start := 0
var packet_start := 0
var kills_start := 0
var wall_start := 0
var output_path := ""
var outcome := ""
var chapter := 1
var equipment_mode := "naked"
var mode := "chapter"
var stationary_pressure := false
var limit_seconds := 360.0
var old_progress := ""
var last_progress_at := 0.0
var last_position := Vector2.INF
var initial_player_id := 0
var next_diagnostic := 60.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	_run.call_deferred()

func arg(key: String, fallback: String = "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--"+key+"="): return value.trim_prefix("--"+key+"=")
	return fallback

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); push_error("FIRST FOUR NATURAL: "+label)
	return ok

func frozen_fixture(hero: String, level: int) -> Dictionary:
	if chapter not in [1,2,3,4] or level!=(chapter-1)*5+1 or hero not in ["CH01","CH02","CH03"]: return {}
	var loadout := {}
	var owned := {}
	for slot: String in Registry.slots(2): loadout[slot]=""
	var talents := {}
	var remaining := level-1
	for key: String in ["mastery","precision","dexterity","vitality","resistance","agility"]:
		var rank:=mini(remaining,Progression.rank_cap())
		if rank>0: talents[key]=rank
		remaining-=rank
	var equipment_manifest := []
	if equipment_mode!="naked":
		var rarity: String="gold" if equipment_mode=="G2" else ("purple" if equipment_mode=="P5" else "green")
		var enhancement: int=2 if equipment_mode=="G2" else (5 if equipment_mode=="P5" else 0)
		var affix_count: int=4 if equipment_mode=="G2" else (3 if equipment_mode=="P5" else 2)
		var pool:=Acquisition.natural_pool("B%02d"%chapter)
		for slot: String in Registry.slots(2):
			var candidates: Array=pool.get(slot,[]).duplicate()
			candidates.sort()
			for template: String in candidates:
				var power: String="magic" if hero=="CH03" else "physical"
				var rolls := {}
				for key: String in Instances.main_keys(template,power): rolls[key]=50
				var legal:=Instances.legal_affixes(template,power)
				var affixes := []
				for key: String in legal.slice(0,affix_count): affixes.append({"type":key,"u":50})
				var steps := []
				for step in range(enhancement): steps.append({"g":10,"pity":0,"base_price_peak":Economy.enhancement_price(step+1,level)})
				var id: String="first-four:%d:%s:%s"%[chapter,hero,slot]
				var item:=Instances.create({"instance_id":id,"source_event_id":"test-owned:"+id,"template_id":template,"item_level":level,"rarity":rarity,"power_type":power,"main_rolls":rolls,"affix_type_and_quantile":affixes,"enhancement_rank":enhancement,"enhancement_steps":steps,"purchase_baseline_gold":Economy.purchase_baseline_price(template,rarity,level),"location":"equipped"})
				if item.is_empty() or not Instances.can_equip(item,hero,level): continue
				owned[id]=item;loadout[slot]=id
				equipment_manifest.append(item.duplicate(true))
				break
		if owned.size()!=8: return {}
	var branches := {"q":"","ultimate":""}
	var stats:=Resolver.resolve(hero,level,loadout,owned,2,talents)
	stats["branches"]=branches.duplicate(true)
	check(Progression.valid_talents(talents,level) and Progression.available_points(talents,level)==0,"legal entry talents")
	return {"level":level,"owned":owned,"loadout":loadout,"talents":talents,"branches":branches,"stats":stats,"manifest":{"fixture_version":"first-four-entry-level-v1","chapter":chapter,"hero_id":hero,"level":level,"equipment_mode":equipment_mode,"talents":talents,"branches":branches,"items":equipment_manifest,"entry_stats":stats.duplicate(true),"acquisition_assumption":"Geared cases assume eight owned legal same-chapter items at entry level. G2=gold+2, P5=purple+5, green0=green+0; 50th-quantile rolls and +10% enhancement steps. No proof of acquisition/forging unlock/time. naked has none. No legacy S11 fixture."}}

func _run() -> void:
	if not Game.profile_path.contains("test_first_four_natural_chapter"):
		get_tree().quit(2); return
	output_path = arg("output",Game.profile_path.get_base_dir().path_join("naked_chapter.json"))
	chapter=int(arg("chapter","1"))
	equipment_mode=arg("equipment","naked")
	check(equipment_mode in ["naked","green0","G2","P5"],"explicit legal equipment mode")
	if arg("parse-only","false")=="true":
		for ch in range(1,5):
			chapter=ch
			for hero: String in ["CH01","CH02","CH03"]:
				for gear: String in ["naked","green0","G2","P5"]:
					equipment_mode=gear
					check(not frozen_fixture(hero,(ch-1)*5+1).is_empty(),"entry fixture %d %s %s"%[ch,hero,gear])
		print("FIRST_FOUR_FIXTURE_CHECK ",checks," failures=",failures)
		get_tree().quit(0 if failures.is_empty() else 1); return
	mode = arg("mode","chapter")
	stationary_pressure=arg("stationary-pressure","false")=="true"
	check(not stationary_pressure or mode=="group","stationary pressure only uses an independent authored group")
	limit_seconds = float(arg("max-seconds","360"))
	var hero := arg("hero","CH03")
	var level := int(arg("level",str((chapter-1)*5+1)))
	var difficulty := int(arg("difficulty","0"))
	var fight_seed := int(arg("seed","1001"))
	check(mode in ["chapter","group"],"bounded defined mode")
	check(Engine.physics_ticks_per_second==60 and is_equal_approx(Engine.time_scale,1.0),"native60Hz time_scale1")
	var fixture := frozen_fixture(hero,level)
	check(not fixture.is_empty(),"fixture resolved at exact chapter entry level")
	if fixture.is_empty() or not failures.is_empty(): get_tree().quit(1); return
	check(Game.new_profile(),"fresh isolated test profile")
	Game.profile = NativeProfile.fresh(ProfileStore.fresh_profile())
	Game.profile.selected_hero = hero
	Game.profile.hero_xp[hero] = Progression.thresholds()[level-1]
	Game.profile.bosses = []
	for prior in range(1,chapter): Game.profile.bosses.append("BO%02d"%prior)
	Game.profile.equipment = fixture.owned.duplicate(true)
	Game.profile.loadout = fixture.loadout.duplicate(true)
	Game.profile.loadout_presets = {hero:fixture.loadout.duplicate(true)}
	Game.profile.talents = {hero:fixture.talents.duplicate(true)}
	Game.profile.branches[hero] = fixture.branches.duplicate(true)
	Game.profile.settings.auto_attack = false
	Game.profile.settings.camera_shake = false
	check(ProfileStore._valid_progression(Game.profile),"legal production profile with all eight empty slots")
	check(Game.start_run({"expedition":true,"biome_id":"B%02d"%chapter,"difficulty":difficulty,"seed":fight_seed}),"production first four entry accepted: "+Game.last_error)
	if Game.run==null or not failures.is_empty(): get_tree().quit(1); return
	current_run = Game.run
	trail = Trail.new(); Game.damage_trail = trail
	expedition = Expedition.new(Game)
	report = {"schema":"first-four-natural-chapter-v1","chapter":chapter,"equipment_mode":equipment_mode,"expected_archive":15,"mode":mode,"controller":Driver.FIRST_FOUR_VERSION,"method":"Native production room/route/AI/damage, automated 0.1s visible-danger decisions and lawful dash, mage zero basics; not human play or standing tanking","fixture":fixture.manifest,"difficulty":difficulty,"seed":fight_seed,"route":expedition.snapshot().route.duplicate(true),"entry_calibration":current_run.enemy_calibration_snapshot.duplicate(true),"skip_policy":"Skip every mandatory relic offer through production API; native skip may heal up to6% max HP, recorded separately. No supply purchases.","transitions":[],"relic_skips":[],"source_sha256":source_hashes(),"display":DisplayServer.get_name(),"physics_hz":60,"time_scale":1,"active_limit_seconds":limit_seconds}
	report["stationary_pressure"]=stationary_pressure
	if stationary_pressure:report["method"]="Controlled stationary pressure at the authored entry: no movement, dash, offense or defensive casts; native enemies/waves only. Inactivity is inconclusive if actors never reach the entry."
	report["resolved_entry_stats"] = current_run.stats.duplicate(true)
	check(int(current_run.enemy_calibration_snapshot.get("version",0))==15,"new candidate archive15 mandatory")
	check(current_run.level==level,"exact minimum chapter entry level")
	var bare_run:=RunState.new()
	bare_run.enemy_calibration_snapshot=current_run.enemy_calibration_snapshot.duplicate(true)
	bare_run.stats=Resolver.resolve(hero,level,{}, {},2,{})
	var bare_stats: Dictionary=bare_run.stats
	check(is_equal_approx(float(bare_stats.crit_chance),.25) and is_equal_approx(float(bare_stats.crit_multiplier),2.0),"new global intrinsic critical baseline .25/2")
	check(is_equal_approx(float(CritPolicy.MAX_CHANCE),1.0) and is_equal_approx(float(CritPolicy.MAX_MULTIPLIER),3.0),"new global critical caps 1/3")
	check(int(current_run.stats.get("crit_policy_version",0))==1 and float(current_run.stats.crit_chance)>=.25 and float(current_run.stats.crit_chance)<=1.0 and float(current_run.stats.crit_multiplier)>=2.0 and float(current_run.stats.crit_multiplier)<=3.0,"actual run critical stats admitted under new baseline/caps")
	if equipment_mode=="naked":
		check(current_run.stats.loadout.is_empty() and current_run.stats.sets.is_empty() and current_run.stats.equipment_templates.is_empty() and current_run.equipment_snapshot.is_empty(),"empty equipment")
		for key: String in current_run.stats.equipment_contribution: check(is_zero_approx(float(current_run.stats.equipment_contribution[key])),"zero equipment "+key)
	else:
		for item: Dictionary in current_run.equipment_snapshot.values(): check(Instances.can_equip(item,hero,level) and int(item.item_level)<=level,"legal current entry-level item")
	var expected_stats: Dictionary=CritPolicy.apply_player(fixture.stats,current_run.enemy_calibration_snapshot)
	expected_stats.merge({"temporary_buffs":{},"relic_levels":{}})
	check(current_run.stats==expected_stats,"production entry resolver equals independently frozen naked stats plus empty expedition metadata")
	check(current_run.relics.is_empty() and current_run.expedition.temporary_buffs.is_empty() and not current_run.demo,"no relics, purchased buffs, or demo bonus")
	AudioServer.set_bus_mute(0,true)
	for action: String in InputMap.get_actions(): Input.action_release(action)
	get_tree().paused = true
	stage = SubViewport.new(); stage.size=Vector2i(1280,720); stage.handle_input_locally=true; add_child(stage)
	room = RoomScene.instantiate(); room.set_script(ObservedRoom)
	if DisplayServer.get_name()=="headless": room.get_node("MineBackdrop").set_script(preload("res://tests/support/b05_balance_headless_backdrop.gd"))
	var context: Dictionary = expedition.current_context() if mode=="chapter" else {"room_id":arg("room","L30"),"role":"normal","biome_id":"B%02d"%chapter,"node_index":1,"node_count":7,"difficulty":difficulty,"seed":fight_seed,"phase":"combat","expedition":true}
	var prepared := room.prepare_expedition_node(context)
	if not check(bool(prepared.get("valid",false)),"production room preflight"): get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared); stage.add_child(room)
	room.player.abilities=preload("res://tests/support/b05_balance_observed_abilities.gd").new()
	room.player.abilities.configure(room.player)
	trail.player_reference=weakref(room.player)
	initial_player_id=room.player.get_instance_id()
	driver=Driver.new(); driver.configure(room)
	room.recording=true
	seed(fight_seed)
	if mode=="chapter":
		skip_relics()
		if not advance_native(): outcome="transition_blocked"
	start_room()
	wall_start=Time.get_ticks_usec()
	active=outcome.is_empty()
	get_tree().paused=false
	print("FIRST_FOUR_NATURAL_BEGIN ",JSON.stringify({"mode":mode,"level":level,"hero":hero,"difficulty":difficulty,"room":room.layout_id}))
	while active: await get_tree().process_frame
	finish_room(outcome)
	report["outcome"]=outcome
	report["active_seconds"]=elapsed
	report["host_seconds"]=float(Time.get_ticks_usec()-wall_start)/1000000.0
	report["whole_chapter_clear_proven"] = mode=="chapter" and outcome=="chapter_cleared"
	report["final_hp"]=current_run.hp
	report["final_max_hp"]=current_run.max_hp
	report["effective_received_hits"]=trail.all_events.filter(func(p:Dictionary)->bool:return float(p.hp_loss)+float(p.shield_absorbed)>0).size()
	report["incoming_packets"]=trail.all_events.duplicate(true)
	if outcome=="chapter_cleared":
		var settlement: Dictionary=Game.finish_run("extracted")
		check(not settlement.is_empty() and Game.run==null,"native full chapter extraction accepted")
		report["native_settlement"]=settlement
	elif outcome=="natural_death":
		report["native_settlement"]=Game.last_result.duplicate(true)
		report["death_settlement_committed"]=Game.run==null
	var total_loss:=0.0
	var total_shield:=0.0
	var total_kills:=0
	for row: Dictionary in room_rows:
		total_loss+=float(row.hp_loss);total_shield+=float(row.shield_absorbed);total_kills+=int(row.kills)
	report.merge({"hp_loss":total_loss,"shield_absorbed":total_shield,"kills":total_kills,"basic_shots_total":room.telemetry.shots,"empty_equipment_verified":room_rows.all(func(row:Dictionary)->bool:return bool(row.empty_equipment_verified)),"loot_policy":"No equip or keep decisions. Production auto-generated pending loot is recorded without mutation; native extraction may bank it after the naked run ends."})
	report["source_sha256_after"]=source_hashes()
	check(report.source_sha256==report.source_sha256_after,"measured source files unchanged during attempt")
	if hero=="CH03": check(int(room.telemetry.shots)==0,"mage zero basic attacks")
	save_report()
	print("FIRST_FOUR_NATURAL_RESULT ",JSON.stringify({"outcome":outcome,"active_seconds":elapsed,"hp":current_run.hp,"hits":report.effective_received_hits,"rooms":room_rows.size(),"failures":failures,"output":output_path}))
	room.recording=false
	await room.combat_audio.wait_for_cleanup()
	room.free()
	if Game.run!=null: Game.finish_run("abandoned")
	get_tree().paused=false
	get_tree().quit(0 if failures.is_empty() else 1)

func skip_relics() -> void:
	for offer: Dictionary in expedition.snapshot().get("relic_offers",[]):
		if not str(offer.get("decision","")).is_empty(): continue
		var before := float(Game.run.hp)
		var resource_before := float(Game.run.resource)
		if not check(Game.choose_run_relic(str(offer.offer_id),"skip","",room.expedition_runtime_snapshot()),"native relic skip"): return
		check(room.restore_expedition_runtime(expedition.snapshot().runtime),"restore committed skip state")
		current_run=Game.run
		report.relic_skips.append({"t":elapsed,"room_id":room.layout_id,"node_index":expedition.current_index(),"hp_before":before,"hp_after":current_run.hp,"native_skip_healing":current_run.hp-before,"resource_before":resource_before,"resource_after":current_run.resource})

func advance_native() -> bool:
	var options: Array=expedition.next_options()
	if options.is_empty(): return false
	# Frozen route policy: lexicographically smallest permitted room ID.
	options.sort()
	var target := str(options[0])
	var context: Dictionary=expedition.candidate(target)
	var prepared: Dictionary=room.prepare_expedition_node(context)
	if not check(bool(prepared.get("valid",false)),"native transition preflight"): return false
	var checkpoint: String=str(expedition.snapshot().checkpoint_id)
	var hp_before := float(Game.run.hp)
	var resource_before := float(Game.run.resource)
	var cooldowns_before: Dictionary=room.player.cooldowns.duplicate(true)
	if not check(Game.choose_expedition_node(int(context.node_index),target),"native route choice"): return false
	if not check(Game.advance_expedition_node(prepared.runtime,checkpoint),"native advance: "+Game.last_error): return false
	prepared.runtime=Game.expedition_snapshot().runtime.duplicate(true)
	room.apply_prepared_expedition_node(prepared)
	current_run=Game.run
	check(room.player.get_instance_id()==initial_player_id,"same player across transition")
	check(room.player.cooldowns==cooldowns_before,"transition preserves cooldowns")
	check(is_equal_approx(current_run.hp,hp_before) and is_equal_approx(current_run.resource,resource_before),"transition preserves absolute HP/resource")
	report.transitions.append({"t":elapsed,"room_id":target,"node_index":expedition.current_index(),"hp_before":hp_before,"hp_after":current_run.hp,"resource_before":resource_before,"resource_after":current_run.resource,"player_instance_preserved":room.player.get_instance_id()==initial_player_id})
	driver.configure(room)
	return true

func start_room() -> void:
	current_run=Game.run
	room_started=elapsed; next_objective=elapsed; next_sample=elapsed
	outgoing_start=room.packets.size();ability_start=room.player.abilities.audit.size()
	packet_start=trail.all_events.size(); kills_start=int(room.telemetry.kills)
	var present_ids: Array[String]=[]
	for actor: Node in room.enemies.get_children():present_ids.append(str(actor.get_instance_id()))
	for id: String in room.actor_roster.keys():
		if id not in present_ids:room.actor_roster.erase(id)
	room.scan_actors()
	current_row={"room_id":room.layout_id,"context":room.expedition_context.duplicate(true),"start_active_seconds":elapsed,"entry_level":current_run.level,"entry_profile_level":Game.hero_level(current_run.hero_id),"start_hp":current_run.hp,"start_max_hp":current_run.max_hp,"start_resource":current_run.resource,"samples":[]}
	old_progress="";last_progress_at=elapsed;last_position=room.player.position
	room.release_gate=false;room.pointer_release_gate=false

func finish_room(result: String) -> void:
	if current_row.is_empty(): return
	room.scan_actors()
	var hp_loss:=0.0
	var hits:=0
	for packet: Dictionary in trail.all_events.slice(packet_start):
		hp_loss+=float(packet.hp_loss)
		if float(packet.hp_loss)+float(packet.shield_absorbed)>0: hits+=1
	var actors: Array[Dictionary]=[]
	for actor: Dictionary in room.actor_roster.values():
		actors.append({"template":actor.template,"actor_kind":actor.actor_kind,"level":actor.level,"rank":actor.rank,"initial_hp":actor.initial_hp,"last_hp":actor.last_hp,"actor_damage":actor.actor_damage})
	current_row.merge({"outcome":result,"active_seconds":elapsed-room_started,"end_level":current_run.level,"end_profile_level":Game.hero_level(current_run.hero_id),"end_hp":current_run.hp,"end_max_hp":current_run.max_hp,"end_resource":current_run.resource,"hp_loss":hp_loss,"effective_received_hits":hits,"kills":int(room.telemetry.kills)-kills_start,"finite_groups":room.encounter_progress.duplicate(true),"activated_groups":room.activated_encounters.duplicate(true),"all_authored_waves_exhausted":room._encounters_exhausted(),"actor_roster":actors,"controller_rejections":driver.rejected.duplicate(true),"basic_shots_total":room.telemetry.shots,"equipment_runtime":{"equipped":room.player.loadout.effects.equipped.duplicate(true),"set_counts":room.player.loadout.effects.set_counts.duplicate(true),"buffs":room.player.loadout.effects.buffs.duplicate(true),"refund_history":room.player.loadout.effects.refund_history.duplicate(true),"resource_history":room.player.loadout.effects.resource_history.duplicate(true)},"dashes_total":room.telemetry.dashes})
	var shield_absorbed:=0.0
	var shield_sources: Dictionary={}
	for packet: Dictionary in trail.all_events.slice(packet_start):
		shield_absorbed+=float(packet.shield_absorbed)
		for source: String in packet.get("guard_sources_at_receipt",{}):shield_sources[source]=true
	var healing:=0.0
	for packet: Dictionary in room.packets.slice(outgoing_start):
		if str(packet.kind)=="heal":healing+=float(packet.amount)
	var payments: Array=room.player.abilities.audit.slice(ability_start)
	for payment: Dictionary in payments:
		if str(payment.kind)!="paid_commit":continue
		check(float(payment.resource_before)+0.00001>=float(payment.paid_cost),"ability has legal resource payment")
		check(is_equal_approx(float(payment.resource_after_class_refund),float(payment.resource_before)-float(payment.paid_cost)+float(payment.effective_class_refund)),"native ability payment balances")
	current_row.merge({"shield_absorbed":shield_absorbed,"shield_sources":shield_sources.keys(),"combat_healing_feedback":healing,"native_net_healing_inferred":float(current_run.hp)-float(current_row.start_hp)+hp_loss,"ability_payment_and_timeline":payments,"outgoing_packets":room.packets.slice(outgoing_start),"empty_equipment_verified":current_run.equipment_snapshot.is_empty() and room.player.loadout.effects.equipped.is_empty(),"unclaimed_native_pending_items":current_run.expedition.get("pending_equipment",{}).size()})
	room_rows.append(current_row.duplicate(true))
	print("FIRST_FOUR_NATURAL_ROOM ",JSON.stringify({"room":room.layout_id,"outcome":result,"seconds":current_row.active_seconds,"hp_loss":hp_loss,"hp":current_run.hp,"hits":hits,"kills":current_row.kills}))
	current_row={}

func _physics_process(delta: float) -> void:
	if not active or get_tree().paused: return
	elapsed+=delta
	if Game.run!=null: current_run=Game.run
	room.scan_actors()
	if current_run.hp<=0 or Game.run==null:
		outcome="natural_death";stop();return
	if not failures.is_empty(): outcome="harness_failed";stop();return
	if mode=="group" and room.objective_complete:
		outcome="authored_group_room_cleared";stop();return
	if mode=="chapter" and room.objective_rewarded:
		if str(room.expedition_context.role)=="boss":outcome="chapter_cleared";stop();return
		finish_room("native_room_cleared")
		skip_relics()
		if not advance_native():outcome="transition_blocked";stop();return
		start_room()
	if elapsed>=limit_seconds:outcome="observation_bound_inconclusive";stop();return
	if elapsed>=next_sample:
		current_row.samples.append({"t":elapsed,"hp":current_run.hp,"resource":current_run.resource,"level":current_run.level,"profile_level":Game.hero_level(current_run.hero_id),"position":[room.player.position.x,room.player.position.y],"live_enemies":room._living_enemy_count(),"kills":room.telemetry.kills,"groups":room.activated_encounters.duplicate(),"no_reachable_approach":driver.rejected.get("no_reachable_approach",0)})
		next_sample+=1
		var objective_health := {}
		for actor: Node in room.enemies.get_children():
			if actor is MineEnemy and actor.actor_kind=="objective":objective_health[str(actor.get_instance_id())]=actor.health.current
		if elapsed>=next_diagnostic:
			print("FIRST_FOUR_NATURAL_PROGRESS ",JSON.stringify({"t":elapsed,"room":room.layout_id,"hp":current_run.hp,"enemies":room._living_enemy_count(),"kills":room.telemetry.kills,"position":json_value(room.player.position),"objective_health":objective_health}))
			next_diagnostic+=60.0
		var signature:=str(objective_health)+str(room.telemetry.kills)+"/"+str(room._living_enemy_count())+"/"+str(room.activated_encounters)+"/"+str(current_run.hp)+"/"+str(trail.all_events.size())
		if signature!=old_progress or room.player.position.distance_to(last_position)>8:
			last_progress_at=elapsed;last_position=room.player.position;old_progress=signature
		if elapsed-last_progress_at>=90 and not room.player.abilities.busy():
			report["blocker"]={"room":room.layout_id,"position":[room.player.position.x,room.player.position.y],"objective_health":objective_health,"navigation_target":json_value(room.navigation_target()),"no_progress_seconds":elapsed-last_progress_at,"rejections":driver.rejected.duplicate(true),"qualification":"Controller could not submit a reachable path; not proof that a human has no route."}
			outcome="controller_no_progress_inconclusive";stop();return
	if equipment_mode=="naked": check_naked()
	if not stationary_pressure:
		driver.step(elapsed)
		objective_step()

func check_naked() -> void:
	if not current_run.loadout_snapshot.is_empty():
		for slot: String in current_run.loadout_snapshot:
			if str(current_run.loadout_snapshot[slot])!="":check(false,"equipped item during naked attempt");return
	if not room.player.loadout.effects.equipped.is_empty() or not room.player.loadout.effects.set_counts.is_empty() or not room.player.loadout.effects.buffs.is_empty() or not room.player.loadout.effects.refund_history.is_empty() or not room.player.loadout.effects.resource_history.is_empty():check(false,"equipment proc or refund active in naked attempt")
	if not current_run.relics.is_empty():check(false,"relic present during naked attempt")
	if not current_run.expedition.get("temporary_buffs",{}).is_empty():check(false,"purchased supply buff present")

func objective_step() -> void:
	if elapsed<next_objective or not room.controls_enabled():return
	next_objective=elapsed+.1
	if room._living_enemy_count()>0:return
	var warnings: Array[Dictionary]=driver.visible_threats()
	if driver.danger_at(room.player.position,warnings)>0:return
	var destination: Dictionary=room.navigation_target()
	if not destination.has("position"):return
	var at: Vector2=destination.position
	if room.player.position.distance_to(at)>65:driver.navigate_to_reachable(elapsed,at,45,warnings)
	else:room.player.clear_movement_target();room.interact()

func stop() -> void:
	active=false
	room.process_mode=Node.PROCESS_MODE_DISABLED

func save_report() -> void:
	report["rooms"]=room_rows
	report["checks"]=checks
	report["failures"]=failures
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var f:=FileAccess.open(output_path,FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(json_value(report),"\t"));f.close()

func source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["tests/test_first_four_natural_chapter.gd","tests/support/first_four_natural_controller.gd","tests/support/b05_balance_controller.gd","scripts/combat/room.gd","scripts/combat/player.gd","scripts/combat/stat_resolver.gd","scripts/combat/hero_abilities.gd","scripts/combat/enemy_calibration.gd","scripts/combat/shared_enemy_growth.gd","scripts/combat/monster_role_policy.gd","scripts/combat/enemy_numerical_v2.gd","scripts/world/b05_room_mechanisms.gd","scripts/world/b05_mechanism_snapshot.gd","scripts/core/run_controller.gd","scripts/combat/enemy_profiles.gd","scripts/world/route_generator.gd","data/numerical_v2.json"]:
		result[path]=FileAccess.get_file_as_string("res://"+path).sha256_text()
	return result

func json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[str(key)]=json_value(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(json_value(item))
		return result
	if value is Vector2:return [value.x,value.y]
	return value
