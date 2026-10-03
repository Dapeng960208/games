extends Node
const Candidate = preload("res://scripts/levels/b07/world/candidate.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Skills = preload("res://scripts/levels/b07/combat/enemy_skills.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures+=1; push_error("B07 LIVE "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Rules.b07_candidate_enabled() or not Game.profile_path.begins_with("user://test_b07_candidate/"): get_tree().quit(2); return
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":27007}),"isolated run")
	if Game.run == null: get_tree().quit(1); return
	check(Rules.parameters().implemented_chapters==4,"shipped default remains4")
	check(not WorldCatalog.biomes().has("B07"),"B07 not released into campaign/economy")
	var room = load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var initial: Dictionary = Candidate.route()[0]; initial.node_index=-100
	var prepared: Dictionary=room.prepare_expedition_node(initial)
	check(prepared.get("valid",false),"first room prepares")
	if not prepared.get("valid",false): room.free(); get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared)
	add_child(room)
	await get_tree().process_frame
	for context: Dictionary in Candidate.route():
		context.node_index=-100
		var next: Dictionary=room.prepare_expedition_node(context)
		check(next.get("valid",false),"prepare "+str(context.room_id))
		if not next.get("valid",false): continue
		room.apply_prepared_expedition_node(next)
		check(is_instance_valid(room.b07_mechanics),"real mirror host")
		check(room.ground_polygon==Geometry.polygon(context.room_id),"real floor matches")
		room.input_blocked=false; room.release_gate=false
		var definition := Geometry.room(context.room_id)
		var mirror: Dictionary=definition.mirrors[0]
		room.player.position=Geometry.world_point(mirror.position)
		check(room.objectives.interact(mirror.id,room.player),"production F channel")
		room.b07_mechanics.tick(.6)
		check(room.b07_mechanics.state.mirrors[mirror.id]==1,"actual rotation commits")
		if context.room_id=="L37":
			var beam: Array=room.b07_mechanics.state.current_direction(mirror.id).path
			var at: Vector2=Geometry.world_point(beam[0]).lerp(Geometry.world_point(beam[1]),.5)
			var guard=room.spawn_enemy(at,"B07-M04",31,{"profile":Skills.profile("B07-M04",31,0),"reward_enabled":false})
			guard.aim_direction=Vector2.RIGHT
			check(room.b07_mechanics.is_lit(guard),"real actor beam intersection")
			check(room.b07_mechanics.filter_damage(guard,100,Vector2.LEFT,"physical")==80,"lit front20percent")
			check(room.b07_mechanics.filter_damage(guard,100,Vector2.RIGHT,"physical")==100,"rear bypass")
			guard.set_meta("b07_shield_active",true); guard.set_meta("b07_shield_direction",Vector2.RIGHT)
			check(room.b07_mechanics.filter_damage(guard,100,Vector2.LEFT,"physical")==65,"strongest shield35 no stacking")
			check(room.b07_mechanics.filter_damage(guard,100,Vector2.LEFT,"true")==100,"true damage bypass")
			var scout=room.spawn_enemy(at+Vector2(0,140),"B07-M02",31,{"profile":Skills.profile("B07-M02",31,0),"reward_enabled":false})
			room.player.position=Geometry.world_point(definition.entry)
			scout.set_meta("b07_camouflaged",true)
			room.b07_mechanics.tick(.01)
			check(not room.b07_mechanics.is_revealed(scout) and scout.body_visual.modulate.a>=.35,"camouflage still visible")
			check(scout.take_damage(10,&"primary",Vector2.RIGHT,{"damage_type":"true"}),"actual revealing damage")
			check(room.b07_mechanics.is_revealed(scout),"confirmed hit reveals")
			room.b07_mechanics.tick(3.01)
			check(not room.b07_mechanics.is_revealed(scout),"damage reveal expires at3s")
			guard.free(); scout.free()
		if context.room_id=="BO07":
			check(is_instance_valid(room._boss_actor) and room._boss_actor.enemy_id=="BO07","correct real boss")
			room._boss_actor.health.current=room._boss_actor.health.maximum*.6
			room.b07_mechanics.tick(.01)
			check(room.b07_mechanics.state.boss_multiplier()==.7,"actual phase2 shield")
			var altar=room.b07_mechanics._altar
			check(altar in room.targets_in_radius(altar.position,50),"altar targetable by all hero attacks")
			check(altar.take_damage(999999,&"primary",Vector2.RIGHT,{"damage_type":"true"}),"actual altar hit accepted")
			check(room.b07_mechanics.state.altar_hp==0,"confirmed damage destroys altar")
		else:
			for zone in room.encounter_zones.size():
				room.player.position=room.encounter_zones[zone].center
				room._update_encounters(4)
				check(room._living_enemy_count()>0 or room.activated_encounters.has(zone),"real finite wave "+str(context.room_id)+":"+str(zone))
				for cycle in 4:
					for actor in room.enemies.get_children():
						check(not actor.reward_enabled,"no economic rewards")
						actor.free()
					room._update_encounters(4)
			check(room._encounters_exhausted(),"wave exhaustion")
			room._tick_expedition(0)
			check(room.objective_complete and not room.objective_rewarded,"candidate clear without settlement")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free()
	Game.run=null
	print("B07 LIVE ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
